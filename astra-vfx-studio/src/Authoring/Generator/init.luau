--!strict
--[[
	Generator — structured text-to-effect generation without an external AI (docs/ARCHITECTURE.md §8 item 4,
	docs/MODULE_CONTRACTS.md §20). Rule based: the prompt's keywords pick an archetype, an element, intensity,
	speed, colours and explicit layers; the Composer lays the layers out on the six phases (anticipation →
	charge → action → impact → secondary → dissipation). Claude or a human can then refine the result.

	  Generator.generate(prompt, { name?, seed?, analyze? }?) -> (EffectDefinition, GeneratorReport)
	  Generator.interpret(prompt) -> Intent             what the prompt was read as (no definition)
	  Generator.VERSION                                 recorded in definition.metadata.generator.version

	Reading the prompt (Generator/Lexicon: English and German, case-insensitive, umlauts folded, plural / German
	endings stemmed, German compounds split):
	  archetype   explosion | strike | beam | slash | aura (loop) | magicCircle (loop) | teleport | meteor |
	              impact. The head noun wins: the LAST archetype word before the first connector ("with", "mit",
	              "featuring", ...) — "explosive slash" is a slash, "lightning explosion with an impact flash" an
	              explosion; without one before a connector the first archetype word after it; default "impact".
	  element     the first element word ("neutral" when there is none); a negated element word is ignored.
	  intensity   the first intensity word: 2 (massive, riesig, …), 1.4 (big, groß, …), 0.6 (small, klein, …);
	              default 1. Size scale = intensity; times × (1 + 0.3 × (intensity − 1)); counts × (1 + 0.5 ×
	              (intensity − 1)).
	  speed       the first speed word: 0.7 (quick, schnell, …), 1.4 (slow, langsam, …); default 1 (time factor).
	  colour      the first colour word recolours the palette (hue); "light" / "dark" before it shade it.
	  layers      component words (charge, sphere, arcs, flash, shockwave, smoke, debris, sparks, beam, trail,
	              pillar, rays, shake, screen) add layers; a negation ("no", "without", "ohne", "kein", ...) removes
	              the layers of the component words within the next 3 words.
	  modifiers   bright (brighter, larger flash), glow / expand (recognised; part of every core / shockwave).

	Output: always a valid definition (Validation without errors), also for empty or nonsense prompts (a generic
	impact). Deterministic: the same prompt and seed give the same definition; seed defaults to
	Random.hash(prompt) and is stored in the definition. Name: options.name (trimmed, at most NAME_MAX_LENGTH
	characters) or "<Intensity> <Colour> <Element> <Archetype>" from the recognised words ("Massive Blue Lightning
	Explosion"); id = Ids.slug(name). description = the prompt (valid UTF-8, at most DESCRIPTION_MAX_LENGTH
	characters). tags = { "generated", archetype, element }. Palette keys: core, mid, edge, smoke.

	Budget safety net (options.analyze ~= false): the definition is analysed with Authoring/Analyzer at "High";
	while the status is "over", the optional component (one with a minQuality) with the largest share of an
	over-budget metric (Analyzer report.components[*].shares; else the last optional one) is removed with its
	children, and a note says so. Analyzer.BUDGETS is the budget table, so a game can tighten it.
	The analysed status of "High" and "Low" is reported in report.performance (heuristic, see Analyzer.NOTICE).

	Robustness: if composing raises or the result does not validate (a bug), the generic impact is built instead
	and the reason is added to report.notes (report.fallback = true). A non-string prompt raises (programmer
	error), nil means "". options.seed must be a finite number (rounded down to a whole number).

	GeneratorReport = {
	  archetype, element, intensity, speed,               the interpretation (see above)
	  recognized: { string },                             matched prompt words in order (folded, unique)
	  components: { string },                             component names in document order
	  notes: { string },                                  what was recognised / added / removed, and why
	  -- extensions
	  name, id, seed, duration, loop, color?, unknown: { string }, excluded: { string },
	  layers: { { id, name, type, phase, kind, minQuality? } }, phases: { [phase]: markerTime },
	  performance: { High: BudgetStatus?, Low: BudgetStatus? }, fallback: boolean,
	}
]]

local Constants = require(script.Parent.Parent.AstraVFX.Core.Constants)
local Random = require(script.Parent.Parent.AstraVFX.Core.Random)
local Types = require(script.Parent.Parent.AstraVFX.Core.Types)
local Validation = require(script.Parent.Parent.AstraVFX.Core.Validation)
local Analyzer = require(script.Parent.Analyzer)
local Ids = require(script.Parent.Ids)
local Composer = require(script.Composer)
local Lexicon = require(script.Lexicon)
local Recipes = require(script.Recipes)

type EffectDefinition = Types.EffectDefinition

export type Options = {
	name: string?,
	seed: number?,
	analyze: boolean?, -- default true: budget safety net + report.performance
}

export type Intent = Composer.Intent & {
	recognized: { string },
	unknown: { string },
	notes: { string },
}

export type LayerInfo = Composer.LayerInfo

export type GeneratorReport = {
	archetype: string,
	element: string,
	intensity: number,
	speed: number,
	recognized: { string },
	components: { string },
	notes: { string },
	name: string,
	id: string,
	seed: number,
	duration: number,
	loop: boolean,
	color: string?,
	unknown: { string },
	excluded: { string },
	layers: { LayerInfo },
	phases: { [string]: number },
	performance: { [string]: string },
	fallback: boolean,
}

local Generator = {}

Generator.VERSION = 1
Generator.MAX_PROMPT_LENGTH = 4000
Generator.DESCRIPTION_MAX_LENGTH = 300
Generator.Lexicon = Lexicon
Generator.Recipes = Recipes

local INTENSITY_WORD: { [number]: string } = { [2] = "Massive", [1.4] = "Big", [0.6] = "Small" }
local SPEED_WORD: { [number]: string } = { [0.7] = "quick", [1.4] = "slow" }
local NEGATION_WINDOW = 3

local function titleCase(word: string): string
	return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Interpretation
-- ─────────────────────────────────────────────────────────────────────────────

-- How `prompt` is read: archetype, element, intensity, speed, colour, layers (see the module header).
function Generator.interpret(prompt: string?): Intent
	local text: string = prompt or ""
	if #text > Generator.MAX_PROMPT_LENGTH then
		text = string.sub(text, 1, Generator.MAX_PROMPT_LENGTH)
	end
	local tokens, breaks = Lexicon.tokenize(text)
	local matches, unknown = Lexicon.match(tokens)
	local notes: { string } = {}

	local connector = math.huge
	local negatedUntil: { [number]: boolean } = {}
	for _, match in matches do
		for _, tag in match.tags do
			if tag.kind == "connector" and match.index < connector then
				connector = match.index
			elseif tag.kind == "negation" then
				for i = match.index + 1, match.index + NEGATION_WINDOW do
					if breaks[i] then
						break
					end
					negatedUntil[i] = true
				end
			end
		end
	end

	local recognized: { string } = {}
	local seenWord: { [string]: boolean } = {}
	local archetypeHead: string? = nil
	local archetypeAfter: string? = nil
	local headGeneric: string? = nil
	local afterGeneric: string? = nil
	local element: string? = nil
	local intensity: number? = nil
	local speed: number? = nil
	local color: string? = nil
	local shade: string? = nil
	local bright = false
	local components: { string } = {}
	local excluded: { string } = {}
	local ignored: { string } = {}
	local compoundParts: { [number]: { string } } = {}
	local compoundWord: { [number]: string } = {}
	local compoundOrder: { number } = {}
	local source: { [string]: string } = {} -- decision -> prompt word that made it

	for _, match in matches do
		local negated = negatedUntil[match.index] == true
		local useful = false
		for _, tag in match.tags do
			local kind, value = tag.kind, tag.value
			if kind == "archetype" then
				useful = true
				-- "impact" is the generic default: any specific archetype word outranks it.
				local generic = value == "impact"
				if match.index < connector then
					if generic then
						headGeneric = value
						source.headGeneric = match.word
					else
						archetypeHead = value
						source.archetypeHead = match.word
					end
				elseif generic then
					if afterGeneric == nil then
						afterGeneric = value
						source.afterGeneric = match.word
					end
				elseif archetypeAfter == nil then
					archetypeAfter = value
					source.archetypeAfter = match.word
				end
			elseif kind == "element" then
				useful = true
				if negated then
					table.insert(ignored, "element '" .. match.word .. "' (negated)")
				elseif element == nil then
					element = value
					source.element = match.word
				elseif element ~= value then
					table.insert(ignored, "element '" .. match.word .. "' (one element per effect)")
				end
			elseif kind == "intensity" then
				useful = true
				if intensity == nil then
					intensity = value
					source.intensity = match.word
				end
			elseif kind == "speed" then
				useful = true
				if speed == nil then
					speed = value
					source.speed = match.word
				end
			elseif kind == "color" then
				useful = true
				if color == nil then
					color = value
					source.color = match.word
				end
			elseif kind == "modifier" then
				useful = true
				if value == "bright" then
					bright = true
				elseif (value == "light" or value == "dark") and shade == nil then
					shade = value
				end
			elseif kind == "component" then
				useful = true
				local list = if negated then excluded else components
				if not table.find(list, value) then
					table.insert(list, value)
				end
			elseif kind == "negation" then
				useful = true
			end
		end
		if useful and not seenWord[match.word] then
			seenWord[match.word] = true
			table.insert(recognized, match.word)
		end
		if
			match.form ~= match.word
			and not string.find(match.word, " ", 1, true)
			and Lexicon.lookup(match.word) == nil
		then
			local parts = compoundParts[match.index]
			if not parts then
				parts = {}
				compoundParts[match.index] = parts
				table.insert(compoundOrder, match.index)
				compoundWord[match.index] = match.word
			end
			table.insert(parts, match.form)
		end
	end
	for _, index in compoundOrder do
		table.insert(
			notes,
			"Split compound '" .. compoundWord[index] .. "' into " .. table.concat(compoundParts[index], " + ") .. "."
		)
	end

	-- A component keyword cannot be requested and negated at the same time: the negation wins.
	for i = #components, 1, -1 do
		if table.find(excluded, components[i]) then
			table.remove(components, i)
		end
	end

	local found = archetypeHead or headGeneric or archetypeAfter or afterGeneric
	local archetype: string = found or "impact"
	if found then
		local word = source.archetypeHead or source.headGeneric or source.archetypeAfter or source.afterGeneric
		table.insert(notes, "Archetype '" .. archetype .. "' (from '" .. tostring(word) .. "').")
	else
		table.insert(notes, "No archetype recognised: generic impact.")
	end
	local elementName: string = element or "neutral"
	if element then
		table.insert(
			notes,
			"Element '" .. elementName .. "' (from '" .. source.element .. "'): palette, textures, motion."
		)
	else
		table.insert(notes, "No element recognised: neutral palette.")
	end
	if intensity then
		table.insert(
			notes,
			string.format(
				"Intensity %s (from '%s'): size × %s, timing × %s.",
				INTENSITY_WORD[intensity],
				source.intensity,
				tostring(intensity),
				tostring(math.floor((1 + 0.3 * (intensity - 1)) * 100 + 0.5) / 100)
			)
		)
	end
	if speed then
		table.insert(
			notes,
			string.format("Speed %s (from '%s'): times × %s.", SPEED_WORD[speed], source.speed, tostring(speed))
		)
	end
	if color then
		table.insert(
			notes,
			"Colour '"
				.. color
				.. "' (from '"
				.. source.color
				.. "'"
				.. (if shade then ", " .. shade else "")
				.. ") recolours the palette."
		)
	end
	if table.find(components, "charge") then
		table.insert(notes, "Charge requested.")
	end
	if bright then
		table.insert(notes, "Bright: larger, brighter impact flash.")
	end
	if #components > 0 then
		table.insert(notes, "Requested layers: " .. table.concat(components, ", ") .. ".")
	end
	if #excluded > 0 then
		table.insert(notes, "Excluded layers: " .. table.concat(excluded, ", ") .. ".")
	end
	for _, entry in ignored do
		table.insert(notes, "Ignored " .. entry .. ".")
	end
	if #unknown > 0 then
		local shown = table.move(unknown, 1, math.min(#unknown, 12), 1, {})
		table.insert(
			notes,
			"Not recognised: " .. table.concat(shown, ", ") .. (if #unknown > 12 then ", …" else "") .. "."
		)
	end

	return {
		archetype = archetype,
		element = elementName,
		intensity = intensity or 1,
		speed = speed or 1,
		color = color,
		shade = shade,
		charge = table.find(components, "charge") ~= nil,
		bright = bright,
		components = components,
		excluded = excluded,
		recognized = recognized,
		unknown = unknown,
		notes = notes,
	}
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Generation
-- ─────────────────────────────────────────────────────────────────────────────

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- At most `limit` characters of valid UTF-8 text; invalid UTF-8 is reduced to its ASCII bytes.
local function safeText(text: string, limit: number): string
	if utf8.len(text) == nil then
		text = string.gsub(text, "[\128-\255]", "")
	end
	text = string.gsub(text, "[%c]", " ")
	text = trim(text)
	local length = utf8.len(text) :: number
	if length > limit then
		local cut = utf8.offset(text, limit + 1) :: number
		text = trim(string.sub(text, 1, cut - 1)) .. "…"
	end
	return text
end

local function effectName(intent: Intent): string
	local A = Recipes.ARCHETYPES[intent.archetype]
	local E = Recipes.ELEMENTS[intent.element]
	local words: { string } = {}
	local intensityWord = INTENSITY_WORD[intent.intensity]
	if intensityWord then
		table.insert(words, intensityWord)
	end
	if intent.color then
		table.insert(words, titleCase(intent.color))
	end
	if E and E.label ~= "" then
		table.insert(words, E.label)
	end
	table.insert(words, if A then A.label else "Impact")
	return table.concat(words, " ")
end

local function normalizeSeed(seed: any, prompt: string): number
	if seed == nil then
		return Random.hash(prompt)
	end
	if type(seed) ~= "number" or seed ~= seed or seed == math.huge or seed == -math.huge then
		error("Generator.generate: options.seed must be a finite number, got " .. tostring(seed), 0)
	end
	local whole = math.floor(seed)
	if math.abs(whole) > 2 ^ 53 then
		whole = Random.hash(tostring(seed))
	end
	return whole
end

local function hasErrors(def: any): (boolean, string?)
	local result = Validation.validate(def)
	if result.ok then
		return false, nil
	end
	local first = result.errors[1]
	return true, if first then first.code .. " " .. first.path .. ": " .. first.message else "invalid"
end

-- Removes component `id` and its descendants from `def`.
local function removeSubtree(def: any, id: string)
	local doomed: { [string]: boolean } = { [id] = true }
	local changed = true
	while changed do
		changed = false
		for _, component in def.components do
			if component.parent and doomed[component.parent] and not doomed[component.id] then
				doomed[component.id] = true
				changed = true
			end
		end
	end
	for i = #def.components, 1, -1 do
		if doomed[def.components[i].id] then
			table.remove(def.components, i)
		end
	end
end

local function analyze(def: any, quality: string): any
	local ok, report = pcall(Analyzer.analyze, def, { quality = quality :: any })
	return if ok then report else nil
end

-- The optional component (minQuality set) with the largest share of an over-budget metric; else the last
-- optional component.
local function pickVictim(def: any, report: any): any
	local optional: { [string]: any } = {}
	local last: any = nil
	for _, component in def.components do
		if component.minQuality ~= nil then
			optional[component.id] = component
			last = component
		end
	end
	for _, metric in report.metrics do
		if metric.status == "over" then
			local best: any, bestShare = nil, 0
			for _, entry in report.components do
				local share = entry.shares[metric.key]
				if share and share > bestShare and optional[entry.id] then
					best, bestShare = optional[entry.id], share
				end
			end
			if best then
				return best
			end
		end
	end
	return last
end

-- Budget safety net: while High is over budget, drop the optional component that contributes most.
local function enforceBudget(def: any, notes: { string }): { [string]: string }
	local report = analyze(def, "High")
	while report and report.status == "over" do
		local victim = pickVictim(def, report)
		if victim == nil then
			break
		end
		removeSubtree(def, victim.id)
		table.insert(notes, "Removed optional layer '" .. victim.name .. "' to stay within the High budget.")
		report = analyze(def, "High")
	end
	local performance: { [string]: string } = {}
	if report then
		performance.High = report.status
	end
	local low = analyze(def, "Low")
	if low then
		performance.Low = low.status
	end
	return performance
end

local function fallbackIntent(): Intent
	return {
		archetype = "impact",
		element = "neutral",
		intensity = 1,
		speed = 1,
		color = nil,
		shade = nil,
		charge = false,
		bright = false,
		components = {},
		excluded = {},
		recognized = {},
		unknown = {},
		notes = {},
	}
end

-- Generates a layered effect definition from a text prompt (see the module header).
function Generator.generate(prompt: string?, options: Options?): (EffectDefinition, GeneratorReport)
	if prompt ~= nil and type(prompt) ~= "string" then
		error("Generator.generate: prompt must be a string, got " .. typeof(prompt), 0)
	end
	local o: Options = options or {}
	if type(o) ~= "table" then
		error("Generator.generate: options must be a table", 0)
	end
	local text: string = prompt or ""
	local seed = normalizeSeed(o.seed, text)
	local intent = Generator.interpret(text)
	local notes = table.clone(intent.notes)

	local name: string
	if type(o.name) == "string" and trim(o.name) ~= "" then
		name = safeText(o.name, Constants.NAME_MAX_LENGTH)
		if utf8.len(name) :: number > Constants.NAME_MAX_LENGTH then
			name = safeText(name, Constants.NAME_MAX_LENGTH - 1)
		end
	else
		name = effectName(intent)
	end
	local id = Ids.slug(name, "generated-effect")
	local description = safeText(text, Generator.DESCRIPTION_MAX_LENGTH)
	local function composeOptions(it: Intent): Composer.ComposeOptions
		return {
			seed = seed,
			name = name,
			id = id,
			description = if description ~= "" then description else nil,
			tags = { "generated", it.archetype, it.element },
			metadata = {
				generator = {
					version = Generator.VERSION,
					archetype = it.archetype,
					element = it.element,
					intensity = it.intensity,
					speed = it.speed,
				},
			},
		}
	end

	local fallback = false
	local ok, result: any, composed: any = pcall(Composer.compose, intent, composeOptions(intent))
	local def: any = if ok then result else nil
	local info: any = composed
	local failure: string? = if ok then nil else tostring(result)
	if ok then
		local invalid, reason = hasErrors(def)
		if invalid then
			ok = false
			failure = reason
		end
	end
	if not ok then
		fallback = true
		table.insert(notes, "Generation failed (" .. tostring(failure) .. "); built the generic impact instead.")
		intent = fallbackIntent()
		def, info = Composer.compose(intent, composeOptions(intent))
	end

	for _, note in info.notes do
		table.insert(notes, note)
	end
	local performance: { [string]: string } = {}
	if o.analyze ~= false then
		performance = enforceBudget(def, notes)
	end

	local componentNames: { string } = {}
	local present: { [string]: boolean } = {}
	for _, component in def.components do
		table.insert(componentNames, component.name)
		present[component.id] = true
	end
	local layers: { LayerInfo } = {}
	for _, layer in info.layers do
		if present[layer.id] then
			table.insert(layers, layer)
		end
	end
	table.insert(
		notes,
		string.format(
			"%d components on %d phases, %.2f s%s; Impact marker at %.2f s.",
			#def.components,
			#def.markers,
			def.duration,
			if def.loop then " (loop)" else "",
			info.times.impact or 0
		)
	)

	local report: GeneratorReport = {
		archetype = intent.archetype,
		element = intent.element,
		intensity = intent.intensity,
		speed = intent.speed,
		recognized = intent.recognized,
		components = componentNames,
		notes = notes,
		name = name,
		id = id,
		seed = seed,
		duration = def.duration,
		loop = def.loop == true,
		color = intent.color,
		unknown = intent.unknown,
		excluded = intent.excluded,
		layers = layers,
		phases = info.times,
		performance = performance,
		fallback = fallback,
	}
	return def :: EffectDefinition, report
end

return Generator
