--!strict
--[[
	Generator — Authoring/Generator (structured text-to-effect generation): Lexicon (folding, stemming, compounds,
	bigrams, shades), interpretation (archetype head noun, element, intensity, speed, colour, layers, negation),
	the canonical prompt of the task, a corpus of English / German / adversarial prompts (each one validates
	without errors or warnings, compiles at every quality, stays inside the Analyzer budgets and — with the Lune
	fakes — builds and plays to completion), craft-rule timing, determinism, options and fallbacks.
]]
return function(T: any, use: (string) -> any, ctx: any)
	local Generator = use("Authoring.Generator")
	local Lexicon = use("Authoring.Generator.Lexicon")
	local Recipes = use("Authoring.Generator.Recipes")
	local Composer = use("Authoring.Generator.Composer")
	local Analyzer = use("Authoring.Analyzer")
	local Ids = use("Authoring.Ids")
	local Compiler = use("AstraVFX.Core.Compiler")
	local Constants = use("AstraVFX.Core.Constants")
	local Json = use("AstraVFX.Core.Json")
	local Random = use("AstraVFX.Core.Random")
	local Validation = use("AstraVFX.Core.Validation")
	local HarnessModule = use("Tests.Specs.Helpers.PlaybackHarness")
	local expect = T.expect
	local isLune = ctx.environment == "lune"

	local CANONICAL = "Create a massive blue lightning explosion with a charging sphere, electrical arcs, a bright "
		.. "impact flash and an expanding shockwave."

	-- English, German and adversarial prompts (the corpus every generic check runs over).
	local ENGLISH: { string } = {
		CANONICAL,
		"fire explosion",
		"Huge fiery explosion with smoke and debris",
		"small ice impact",
		"quick lightning strike",
		"A slow holy beam of light",
		"laser beam with sparks",
		"fire slash",
		"fast wind slash with a trail",
		"dark shadow aura",
		"poison aura",
		"arcane magic circle with runes",
		"teleport portal",
		"massive meteor impact with rocks and a camera shake",
		"earth slam",
		"water splash impact",
		"nature healing aura with leaves",
		"toxic explosion without debris",
		"golden holy strike with rays",
		"purple energy orb aura",
		"tiny slow purple slash",
		"big electric aura with lightning arcs",
		"holy teleport",
		"huge energy beam charging up",
		"light blue ice strike",
		"massive fire lightning explosion with charge, sphere, arcs, flash, shockwave, smoke, debris, sparks, beam, "
			.. "trail, pillar, rays, camera shake and impact frame",
		"massive charging lightning magic circle with sparks, smoke, shockwave, beam, pillar, rays, shake and arcs",
		"massive slow charging fire meteor with arcs, sparks, smoke, debris, beam, pillar, rays",
	}
	local GERMAN: { string } = {
		"Erstelle eine riesige Feuerexplosion mit Rauch und Trümmern",
		"Ein schneller Blitzeinschlag mit Funken",
		"Langsamer heiliger Lichtstrahl",
		"Kleiner Eisschnitt",
		"Dunkle Schattenaura",
		"Magischer Kreis mit Runen",
		"Gewaltiger Meteor mit Druckwelle und Trümmern",
		"Giftige Explosion ohne Rauch",
		"Teleportation mit Säule",
		"Grüne Energiekugel, die sich auflädt und explodiert",
		"Wasserstrahl",
		"Erdbeben-Einschlag mit Steinen",
		"Windstoß mit Spur",
		"Natur-Aura mit Blättern",
	}
	local EDGE: { string } = {
		"no flash, no shockwave, no sparks, no smoke, no sphere",
		"",
		"asdf qwerty zxcv",
		"!!!???",
		"💥 explosion ✨",
		"explosion \255\254 fire",
		string.rep("blah ", 2000),
	}
	local PROMPTS: { string } = {}
	for _, list in { ENGLISH, GERMAN, EDGE } do
		table.move(list, 1, #list, #PROMPTS + 1, PROMPTS)
	end

	local PHASES = Constants.PHASES

	local function generate(prompt: string, options: any?): (any, any)
		return Generator.generate(prompt, options)
	end

	-- Cache: one generation per corpus prompt (determinism is tested separately).
	local cache: { [string]: { def: any, report: any } } = {}
	local function cached(prompt: string): (any, any)
		local entry = cache[prompt]
		if not entry then
			local def, report = generate(prompt)
			entry = { def = def, report = report }
			cache[prompt] = entry
		end
		return entry.def, entry.report
	end

	local function byPhase(def: any, phase: string, componentType: string?): { any }
		local out = {}
		for _, component in def.components do
			if component.phase == phase and (componentType == nil or component.type == componentType) then
				table.insert(out, component)
			end
		end
		return out
	end

	local function find(def: any, name: string): any
		for _, component in def.components do
			if component.name == name then
				return component
			end
		end
		return nil
	end

	local function marker(def: any, phase: string): any
		for _, m in def.markers or {} do
			if m.phase == phase then
				return m
			end
		end
		return nil
	end

	local function rgb(hex: string): (number, number, number)
		return tonumber(string.sub(hex, 2, 3), 16) :: number,
			tonumber(string.sub(hex, 4, 5), 16) :: number,
			tonumber(string.sub(hex, 6, 7), 16) :: number
	end

	local function luminance(hex: string): number
		local r, g, b = rgb(hex)
		return 0.2126 * r + 0.7152 * g + 0.0722 * b
	end

	local function contains(list: { any }, value: any): boolean
		return table.find(list, value) ~= nil
	end

	-- Built-in texture file names of docs/COMPONENTS_SPEC.md §16 (read from the doc in Lune, else Recipes).
	local function verifiedTextures(): { [string]: boolean }
		local set: { [string]: boolean } = {}
		local ok, text = pcall(function()
			return ctx.readFile("docs/COMPONENTS_SPEC.md")
		end)
		if ok and type(text) == "string" then
			local first = string.find(text, "## 16. Built-in textures", 1, true)
			local last = first and string.find(text, "\n## 17", first, true)
			if first and last then
				local section = string.sub(text, first, last)
				local particlesPart, rootPart = string.match(section, "^(.-)Also present directly(.*)$")
				for name in string.gmatch(particlesPart or section, "`([%w_]+%.%a+)`") do
					set["rbxasset://textures/particles/" .. name] = true
				end
				for name in string.gmatch(rootPart or "", "`([%w_/]+%.%a+)`") do
					set["rbxasset://textures/" .. name] = true
				end
			end
		end
		if next(set) == nil then
			for _, path in Recipes.TEXTURES do
				set[path] = true
			end
		end
		return set
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- Lexicon
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("Lexicon", function()
		T.it("folds case, umlauts and ß and separates on punctuation", function()
			expect(Lexicon.fold("Trümmer, GROSSE Säule; Weiß!")).toBe("trummer  grosse saule  weiss ")
			expect(Lexicon.tokenize("Feuer-Explosion mit Größe 3")).toEqual({
				"feuer",
				"explosion",
				"mit",
				"grosse",
				"3",
			})
			expect(Lexicon.tokenize("💥 boom\255")).toEqual({ "boom" })
		end)

		T.it("stems plural and German endings only onto real entries", function()
			expect((Lexicon.lookup("runes"))).toBe("rune")
			expect((Lexicon.lookup("kugeln"))).toBe("kugel")
			expect((Lexicon.lookup("riesigen"))).toBe("riesig")
			expect((Lexicon.lookup("flashes"))).toBe("flash")
			expect((Lexicon.lookup("blitze"))).toBe("blitz")
			expect((Lexicon.lookup("run"))).toBeNil()
			expect((Lexicon.lookup("strahlen"))).toBe("strahlen") -- rays, not "strahl" (beam)
		end)

		T.it("matches both umlaut spellings", function()
			local a = Lexicon.match(Lexicon.tokenize("Trümmer"))
			local b = Lexicon.match(Lexicon.tokenize("Truemmer"))
			expect(#a).toBe(1)
			expect(#b).toBe(1)
			expect(a[1].tags[1].value).toBe("debris")
			expect(b[1].tags[1].value).toBe("debris")
		end)

		T.it("splits German and English compounds into known parts only", function()
			local matches, unknown =
				Lexicon.match({ "feuerexplosion", "lichtsaule", "thunderstorm", "string", "notice" })
			local forms = {}
			for _, m in matches do
				table.insert(forms, m.form)
			end
			expect(forms).toEqual({ "feuer", "explosion", "lichtsaule", "thunder", "storm" })
			expect(unknown).toEqual({ "string", "notice" })
			-- Explicit entries win: a "Blitzlicht" is a flash, not lightning + light.
			local flash = Lexicon.match({ "blitzlicht" })
			expect(#flash).toBe(1)
			expect(flash[1].tags[1].kind).toBe("component")
			expect(flash[1].tags[1].value).toBe("flash")
		end)

		T.it("reads bigrams and shades", function()
			local i1 = Generator.interpret("a shock wave")
			expect(i1.element).toBe("neutral")
			expect(contains(i1.components, "shockwave")).toBe(true)
			local i2 = Generator.interpret("light blue explosion")
			expect(i2.element).toBe("neutral")
			expect(i2.color).toBe("blue")
			expect(i2.shade).toBe("light")
			local i3 = Generator.interpret("dunkelblaue Explosion")
			expect(i3.element).toBe("neutral")
			expect(i3.color).toBe("blue")
			expect(i3.shade).toBe("dark")
			local i4 = Generator.interpret("camera shake")
			expect(contains(i4.components, "shake")).toBe(true)
		end)

		T.it("ignores stopwords and numbers, reports unknown words", function()
			local _, unknown = Lexicon.match(Lexicon.tokenize("Create a 3 fire wobble for the game"))
			expect(unknown).toEqual({ "wobble", "game" })
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Interpretation
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("interpret", function()
		T.it("reads the canonical prompt", function()
			local intent = Generator.interpret(CANONICAL)
			expect(intent.archetype).toBe("explosion")
			expect(intent.element).toBe("lightning")
			expect(intent.intensity).toBe(2)
			expect(intent.speed).toBe(1)
			expect(intent.color).toBe("blue")
			expect(intent.charge).toBe(true)
			expect(intent.bright).toBe(true)
			for _, request in { "sphere", "arcs", "flash", "shockwave", "charge" } do
				expect(contains(intent.components, request)).toBe(true)
			end
			expect(intent.unknown).toEqual({})
		end)

		T.it("defaults to a neutral impact", function()
			for _, prompt in { "", "   ", "asdf", "?!" } do
				local intent = Generator.interpret(prompt)
				expect(intent.archetype).toBe("impact")
				expect(intent.element).toBe("neutral")
				expect(intent.intensity).toBe(1)
				expect(intent.speed).toBe(1)
			end
		end)

		T.it("picks the head noun as archetype", function()
			local cases: { { string } } = {
				{ "explosive slash", "slash" },
				{ "lightning strike explosion", "explosion" },
				{ "meteor impact", "meteor" },
				{ "impact explosion", "explosion" },
				{ "explosion with a beam", "explosion" },
				{ "with a laser", "beam" },
				{ "Explosion mit Strahl", "explosion" },
				{ "Blitzeinschlag", "strike" },
				{ "Laserstrahl", "beam" },
				{ "a big punch", "impact" },
			}
			for _, case in cases do
				expect(Generator.interpret(case[1]).archetype).toBe(case[2])
			end
		end)

		T.it("recognises every archetype in English and German", function()
			local cases: { { string } } = {
				{ "explosion", "explosion" },
				{ "Explosion", "explosion" },
				{ "blast", "explosion" },
				{ "burst", "explosion" },
				{ "strike", "strike" },
				{ "bolt", "strike" },
				{ "Einschlag", "strike" },
				{ "beam", "beam" },
				{ "laser", "beam" },
				{ "Strahl", "beam" },
				{ "slash", "slash" },
				{ "swing", "slash" },
				{ "Schnitt", "slash" },
				{ "aura", "aura" },
				{ "magic circle", "magicCircle" },
				{ "rune", "magicCircle" },
				{ "Kreis", "magicCircle" },
				{ "teleport", "teleport" },
				{ "portal", "teleport" },
				{ "meteor", "meteor" },
				{ "Komet", "meteor" },
				{ "impact", "impact" },
				{ "Aufprall", "impact" },
			}
			for _, case in cases do
				expect(Generator.interpret(case[1]).archetype).toBe(case[2])
			end
		end)

		T.it("recognises every element in English and German", function()
			local cases: { { string } } = {
				{ "fire", "fire" },
				{ "flame", "fire" },
				{ "Feuer", "fire" },
				{ "lightning", "lightning" },
				{ "electric", "lightning" },
				{ "thunder", "lightning" },
				{ "Blitz", "lightning" },
				{ "Strom", "lightning" },
				{ "ice", "ice" },
				{ "frost", "ice" },
				{ "Eis", "ice" },
				{ "water", "water" },
				{ "Wasser", "water" },
				{ "poison", "poison" },
				{ "toxic", "poison" },
				{ "Gift", "poison" },
				{ "shadow", "shadow" },
				{ "dark", "shadow" },
				{ "void", "shadow" },
				{ "Schatten", "shadow" },
				{ "holy", "holy" },
				{ "light", "holy" },
				{ "Licht", "holy" },
				{ "heilig", "holy" },
				{ "energy", "energy" },
				{ "magic", "energy" },
				{ "arcane", "energy" },
				{ "Energie", "energy" },
				{ "Magie", "energy" },
				{ "earth", "earth" },
				{ "rock", "earth" },
				{ "stone", "earth" },
				{ "Erde", "earth" },
				{ "Stein", "earth" },
				{ "wind", "wind" },
				{ "air", "wind" },
				{ "Luft", "wind" },
				{ "nature", "nature" },
				{ "leaf", "nature" },
				{ "Natur", "nature" },
			}
			for _, case in cases do
				expect(Generator.interpret(case[1]).element).toBe(case[2])
			end
		end)

		T.it("reads intensity and speed words", function()
			local cases: { { any } } = {
				{ "massive", 2, 1 },
				{ "huge", 2, 1 },
				{ "giant", 2, 1 },
				{ "gewaltig", 2, 1 },
				{ "riesige", 2, 1 },
				{ "big", 1.4, 1 },
				{ "groß", 1.4, 1 },
				{ "großen", 1.4, 1 },
				{ "small", 0.6, 1 },
				{ "tiny", 0.6, 1 },
				{ "kleine", 0.6, 1 },
				{ "quick", 1, 0.7 },
				{ "fast", 1, 0.7 },
				{ "schnell", 1, 0.7 },
				{ "slow", 1, 1.4 },
				{ "langsame", 1, 1.4 },
				{ "massive slow", 2, 1.4 },
			}
			for _, case in cases do
				local intent = Generator.interpret(case[1])
				expect(intent.intensity).toBe(case[2])
				expect(intent.speed).toBe(case[3])
			end
		end)

		T.it("reads the explicit layer keywords", function()
			local cases: { { string } } = {
				{ "charging", "charge" },
				{ "aufladen", "charge" },
				{ "orb", "sphere" },
				{ "core", "sphere" },
				{ "lightning", "arcs" },
				{ "Lichtbogen", "arcs" },
				{ "Kugel", "sphere" },
				{ "arcs", "arcs" },
				{ "Bögen", "arcs" },
				{ "flash", "flash" },
				{ "Blitzlicht", "flash" },
				{ "ring", "shockwave" },
				{ "Druckwelle", "shockwave" },
				{ "smoke", "smoke" },
				{ "Rauch", "smoke" },
				{ "debris", "debris" },
				{ "rocks", "debris" },
				{ "Trümmer", "debris" },
				{ "sparks", "sparks" },
				{ "embers", "sparks" },
				{ "Funken", "sparks" },
				{ "beam", "beam" },
				{ "trail", "trail" },
				{ "Spur", "trail" },
				{ "pillar", "pillar" },
				{ "Säule", "pillar" },
				{ "rays", "rays" },
				{ "Strahlen", "rays" },
			}
			for _, case in cases do
				expect(contains(Generator.interpret(case[1]).components, case[2])).toBe(true)
			end
		end)

		T.it("negates the layer words that follow a negation", function()
			local i1 = Generator.interpret("explosion without smoke or debris")
			expect(i1.excluded).toEqual({ "smoke", "debris" })
			expect(contains(i1.components, "smoke")).toBe(false)
			local i2 = Generator.interpret("Explosion ohne Trümmer")
			expect(i2.excluded).toEqual({ "debris" })
			local i3 = Generator.interpret("no fire, ice impact")
			expect(i3.element).toBe("ice")
		end)

		T.it("uses the first element and colour and notes the rest", function()
			local intent = Generator.interpret("fire and ice explosion, red and blue")
			expect(intent.element).toBe("fire")
			expect(intent.color).toBe("red")
			local joined = table.concat(intent.notes, " ")
			expect(string.find(joined, "one element per effect", 1, true) ~= nil).toBe(true)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Canonical prompt
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("canonical prompt", function()
		T.it("validates without errors or warnings", function()
			local def = cached(CANONICAL)
			local result = Validation.validate(def)
			expect(result.ok).toBe(true)
			expect(#result.errors).toBe(0)
			expect(#result.warnings).toBe(0)
			expect(def.schemaVersion).toBe(Constants.SCHEMA_VERSION)
		end)

		T.it("has a sphere in the charge phase", function()
			local def = cached(CANONICAL)
			local spheres = byPhase(def, "charge", "sphere")
			expect(#spheres).toBeGreaterThanOrEqual(1)
			expect(spheres[1].name).toBe("Charge Sphere")
			-- It grows over the charge (a radius track rising to its rest radius).
			local track = spheres[1].tracks[1]
			expect(track.channel).toBe("radius")
			expect(track.keyframes[2].value).toBeGreaterThan(track.keyframes[1].value)
		end)

		T.it("has lightning in the action phase", function()
			local def = cached(CANONICAL)
			local arcs = byPhase(def, "action", "lightning")
			expect(#arcs).toBeGreaterThanOrEqual(2)
			for _, arc in arcs do
				expect(string.find(arc.name, "Arc", 1, true) ~= nil).toBe(true)
			end
		end)

		T.it("has a flash and a shockwave in the impact phase at the Impact marker", function()
			local def = cached(CANONICAL)
			local impact = marker(def, "impact")
			expect(impact).toBeTruthy()
			expect(impact.event).toBe("Impact")
			expect(impact.label).toBe("Impact")
			local flashes = byPhase(def, "impact", "flash")
			local waves = byPhase(def, "impact", "shockwave")
			expect(#flashes).toBe(1)
			expect(#waves).toBe(1)
			expect(flashes[1].name).toBe("Impact Flash")
			expect(flashes[1].startTime).toBeCloseTo(impact.time, 1e-9)
			expect(waves[1].startTime).toBeCloseTo(impact.time, 1e-9)
			-- "bright": peak brightness above the default
			expect(flashes[1].properties.peakBrightness).toBeGreaterThan(10)
		end)

		T.it("has secondary particles", function()
			local def = cached(CANONICAL)
			expect(#byPhase(def, "secondary", "particles")).toBeGreaterThanOrEqual(1)
		end)

		T.it("uses a blue / cyan palette: bright core, saturated mid, dark edge", function()
			local def = cached(CANONICAL)
			local palette = def.palette
			local r, g, b = rgb(palette.mid)
			expect(b).toBeGreaterThan(r)
			expect(b).toBeGreaterThanOrEqual(g)
			expect(b).toBeGreaterThanOrEqual(200)
			expect(luminance(palette.core)).toBeGreaterThan(luminance(palette.mid))
			expect(luminance(palette.mid)).toBeGreaterThan(luminance(palette.edge))
			expect(palette.core).never.toBe("#FFFFFF")
			local _, _, cb = rgb(palette.core)
			local cr = rgb(palette.core)
			expect(cb).toBeGreaterThanOrEqual(cr)
		end)

		T.it("has one marker per phase in order, and the charge before the impact", function()
			local def = cached(CANONICAL)
			local labels = {}
			for i, m in def.markers do
				table.insert(labels, m.phase)
				if i > 1 then
					expect(m.time).toBeGreaterThanOrEqual(def.markers[i - 1].time)
				end
			end
			expect(labels).toEqual(PHASES)
			expect(marker(def, "charge").time).toBeLessThan(marker(def, "action").time)
			expect(marker(def, "action").time).toBeLessThan(marker(def, "impact").time)
		end)

		T.it("is massive: scaled sizes and a camera shake / impact frame", function()
			local massive = cached(CANONICAL)
			local normal = generate("blue lightning explosion with a charging sphere, arcs, flash and shockwave")
			local w1 = find(massive, "Shockwave")
			local w2 = find(normal, "Shockwave")
			expect(w1.properties.endRadius).toBeCloseTo(2 * w2.properties.endRadius, 1e-6)
			expect(massive.duration).toBeGreaterThan(normal.duration)
			expect(find(massive, "Camera Shake")).toBeTruthy()
			expect(find(massive, "Impact Frame")).toBeTruthy()
			expect(find(massive, "Impact Frame").minQuality).toBe("Medium")
		end)

		T.it("names the effect and reports what it recognised", function()
			local def, report = cached(CANONICAL)
			expect(def.name).toBe("Massive Blue Lightning Explosion")
			expect(def.id).toBe("massive-blue-lightning-explosion")
			expect(report.archetype).toBe("explosion")
			expect(report.element).toBe("lightning")
			expect(report.intensity).toBe(2)
			expect(report.speed).toBe(1)
			for _, word in { "massive", "blue", "lightning", "explosion", "charging", "sphere", "arcs", "flash" } do
				expect(contains(report.recognized, word)).toBe(true)
			end
			expect(contains(report.recognized, "with")).toBe(false)
			expect(#report.components).toBe(#def.components)
			expect(contains(report.components, "Charge Sphere")).toBe(true)
			expect(#report.notes).toBeGreaterThanOrEqual(5)
			expect(report.performance.High).toBe("ok")
			expect(report.fallback).toBe(false)
			expect(report.seed).toBe(def.seed)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Corpus
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("prompt corpus", function()
		T.it("has at least 30 prompts in English and German", function()
			expect(#ENGLISH + #GERMAN).toBeGreaterThanOrEqual(30)
			expect(#GERMAN).toBeGreaterThanOrEqual(10)
			-- Every German prompt is understood: something besides stopwords was recognised.
			for _, prompt in GERMAN do
				local intent = Generator.interpret(prompt)
				expect(#intent.recognized).toBeGreaterThan(0)
				expect(intent.unknown).toEqual({})
			end
		end)

		T.it("validates every definition without errors or warnings", function()
			for _, prompt in PROMPTS do
				local def = cached(prompt)
				local result = Validation.validate(def)
				if not result.ok or #result.warnings > 0 then
					local first = result.errors[1] or result.warnings[1]
					T.fail(string.format("%q: %s %s %s", prompt, first.code, first.path, first.message))
				end
				local _, report = cached(prompt)
				expect(report.fallback).toBe(false)
			end
		end)

		T.it("encodes canonically and survives a JSON round trip", function()
			for _, prompt in PROMPTS do
				local def = cached(prompt)
				local text = Json.encode(def)
				local ok, decoded = Json.decode(text)
				expect(ok).toBe(true)
				expect(Json.encode(decoded)).toBe(text)
				expect(Validation.validate(decoded).ok).toBe(true)
			end
		end)

		T.it("compiles at every quality without compiler diagnostics", function()
			for _, prompt in PROMPTS do
				local def = cached(prompt)
				for _, level in Constants.QUALITY_LEVELS do
					local compiled, diagnostics = Compiler.compile(def, { quality = level })
					expect(#diagnostics).toBe(0)
					expect(#compiled.components).toBeGreaterThan(0)
				end
			end
		end)

		T.it("stays inside the Analyzer budgets (High never over; Low never over)", function()
			for _, prompt in PROMPTS do
				local def = cached(prompt)
				local high = Analyzer.analyze(def, { quality = "High" })
				local low = Analyzer.analyze(def, { quality = "Low" })
				if high.status == "over" or low.status == "over" then
					T.fail(string.format("%q: High %s, Low %s", prompt, high.status, low.status))
				end
				-- Low really is lighter (optional layers drop, counts scale).
				expect(low.totals.instances).toBeLessThanOrEqual(high.totals.instances)
				expect(low.peaks.liveParticles.value).toBeLessThanOrEqual(high.peaks.liveParticles.value)
			end
		end)

		T.it("follows the palette convention: bright core, saturated mid, dark edge", function()
			local function saturation(hex: string): number
				local r, g, b = rgb(hex)
				local hi, lo = math.max(r, g, b), math.min(r, g, b)
				return if hi == 0 then 0 else (hi - lo) / hi
			end
			for _, prompt in PROMPTS do
				local palette = cached(prompt).palette
				for _, key in { "core", "mid", "edge", "smoke" } do
					expect(string.match(palette[key], "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
				end
				expect(luminance(palette.core)).toBeGreaterThan(luminance(palette.mid))
				expect(luminance(palette.mid)).toBeGreaterThan(luminance(palette.edge))
				expect(saturation(palette.mid)).toBeGreaterThan(saturation(palette.core))
			end
		end)

		T.it("uses only verified built-in textures", function()
			local verified = verifiedTextures()
			for _, prompt in PROMPTS do
				local def = cached(prompt)
				for _, component in def.components do
					local texture = component.properties and component.properties.texture
					if texture ~= nil and texture ~= "" then
						if not verified[texture] then
							T.fail(string.format("%q: %s uses %s", prompt, component.id, texture))
						end
					end
				end
			end
		end)

		T.it("gives every component a phase, a proper name and a unique id", function()
			for _, prompt in PROMPTS do
				local def = cached(prompt)
				local ids = Ids.collect(def)
				local count = #(def.markers or {})
				for _, component in def.components do
					count += 1 + #(component.tracks or {}) + #(component.events or {})
					expect(contains(PHASES, component.phase)).toBe(true)
					expect(string.match(component.name, "^%u") ~= nil).toBe(true)
					expect(string.find(component.name, "_", 1, true)).toBeNil()
				end
				local unique = 0
				for _ in ids do
					unique += 1
				end
				expect(unique).toBe(count)
			end
		end)

		T.it("always has an Impact marker event and markers for its phases", function()
			for _, prompt in PROMPTS do
				local def = cached(prompt)
				local impact = marker(def, "impact")
				expect(impact).toBeTruthy()
				expect(impact.event).toBe("Impact")
				for _, component in def.components do
					expect(marker(def, component.phase)).toBeTruthy()
				end
				for _, m in def.markers do
					expect(m.time).toBeLessThanOrEqual(def.duration)
				end
			end
		end)

		T.it("keeps every span inside the effect and every keyframe inside its span", function()
			for _, prompt in PROMPTS do
				local def = cached(prompt)
				for _, component in def.components do
					local start, duration = component.startTime, component.duration
					expect(start + duration).toBeLessThanOrEqual(def.duration + 1e-9)
					for _, track in component.tracks or {} do
						for _, key in track.keyframes do
							expect(key.time).toBeLessThanOrEqual(duration + 1e-9)
						end
					end
					for _, event in component.events or {} do
						expect(event.time).toBeLessThan(duration)
					end
				end
			end
		end)

		T.itIf(isLune, "builds and plays every definition to completion with the Lune fakes", function()
			local H = HarnessModule.new(use, ctx)
			local ok, err = pcall(function()
				for _, prompt in PROMPTS do
					local def = cached(prompt)
					for _, level in { "High", "Low" } do
						local p = H:player(def, { quality = level })
						local player = p.player
						player:start()
						local dt = 1 / 30
						local steps = 0
						local limit = math.ceil((def.duration * 2 + 8) / dt)
						if def.loop then
							-- Two cycles, then a graceful stop; the tail must still finish.
							while player.time < def.duration * 0.5 or (player.cycle or 0) < 2 do
								player:step(dt)
								steps += 1
								if steps > limit then
									break
								end
							end
							expect((player.cycle or 0) >= 1).toBe(true)
							player:stop()
						end
						while player:step(dt) do
							steps += 1
							if steps > limit then
								break
							end
						end
						if player.state ~= "finished" then
							error(string.format("%q at %s did not finish (state %s)", prompt, level, player.state), 0)
						end
						expect(p.built.destroyed or p.built.container.Parent == nil).toBe(true)
					end
				end
			end)
			H:cleanup()
			if not ok then
				error(err, 0)
			end
		end)

		T.itIf(isLune, "emits particles and fires the Impact event while playing", function()
			local H = HarnessModule.new(use, ctx)
			local ok, err = pcall(function()
				local def = cached(CANONICAL)
				local events: { string } = {}
				local mark = H:emitMark()
				local p = H:player(def, { quality = "High" }, {
					onEvent = function(name: string)
						table.insert(events, name)
					end,
				})
				p.player:start()
				local steps = 0
				while p.player:step(1 / 60) and steps < 2000 do
					steps += 1
				end
				expect(p.player.state).toBe("finished")
				expect(contains(events, "Impact")).toBe(true)
				expect(#H:emitsSince(mark)).toBeGreaterThan(0)
			end)
			H:cleanup()
			if not ok then
				error(err, 0)
			end
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Craft rules
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("craft rules", function()
		local SAMPLES = {
			CANONICAL,
			"fire explosion",
			"small quick ice impact",
			"slow massive holy strike",
			"Langsamer riesiger Meteor",
			"schneller kleiner Feuerschnitt",
		}

		T.it("impact flash: 0.03 s attack, 0.2–0.35 s decay, never cut off", function()
			for _, prompt in SAMPLES do
				local flash = find(generate(prompt), "Impact Flash")
				expect(flash).toBeTruthy()
				local p = flash.properties
				expect(p.attack).toBe(0.03)
				expect(p.decay).toBeGreaterThanOrEqual(0.2)
				expect(p.decay).toBeLessThanOrEqual(0.35)
				expect(flash.duration).toBeGreaterThanOrEqual(p.attack + (p.hold or 0.02) + p.decay)
				expect(p.color).toBe("$core")
			end
		end)

		T.it("shockwave: 0.4–0.8 s expansion with Quart.Out", function()
			for _, prompt in SAMPLES do
				local wave = find(generate(prompt), "Shockwave")
				if wave then
					expect(wave.duration).toBeGreaterThanOrEqual(0.4)
					expect(wave.duration).toBeLessThanOrEqual(0.8)
					expect(wave.properties.expandEasing or "Quart.Out").toBe("Quart.Out")
					expect(wave.properties.endRadius).toBeGreaterThan(wave.properties.startRadius)
				end
			end
		end)

		T.it("dissipation: lingers longest with a 1–2 s fade", function()
			for _, prompt in SAMPLES do
				local def = generate(prompt)
				local layers = byPhase(def, "dissipation", "particles")
				expect(#layers).toBe(1)
				local lifetime = layers[1].properties.lifetime
				expect(lifetime[2]).toBeGreaterThanOrEqual(1)
				expect(lifetime[2]).toBeLessThanOrEqual(2)
				local sparks = find(def, "Impact Sparks")
				expect(sparks.properties.lifetime[2]).toBeLessThan(lifetime[2])
			end
		end)

		T.it("layers a readable silhouette: core, flash, sparks, dissipation", function()
			for _, prompt in { "fire explosion", "ice impact", "earth strike", "Gift-Explosion" } do
				local def = generate(prompt)
				expect(
					#byPhase(def, "action", "sphere")
						+ #byPhase(def, "action", "beam")
						+ #byPhase(def, "action", "lightning")
						+ #byPhase(def, "action", "part")
				).toBeGreaterThanOrEqual(1)
				expect(#byPhase(def, "impact", "flash")).toBe(1)
				expect(#byPhase(def, "impact", "particles")).toBeGreaterThanOrEqual(1)
				expect(#byPhase(def, "dissipation")).toBeGreaterThanOrEqual(1)
			end
		end)

		T.it("speed scales the timeline, intensity the sizes", function()
			local quick = generate("quick fire explosion")
			local normal = generate("fire explosion")
			local slow = generate("slow fire explosion")
			expect(marker(quick, "impact").time).toBeLessThan(marker(normal, "impact").time)
			expect(marker(slow, "impact").time).toBeGreaterThan(marker(normal, "impact").time)
			expect(quick.duration).toBeLessThan(slow.duration)
			local small = find(generate("small fire explosion"), "Shockwave")
			local big = find(generate("big fire explosion"), "Shockwave")
			local base = find(normal, "Shockwave")
			expect(small.properties.endRadius).toBeCloseTo(0.6 * base.properties.endRadius, 1e-6)
			expect(big.properties.endRadius).toBeCloseTo(1.4 * base.properties.endRadius, 1e-6)
		end)

		T.it("marks optional layers with minQuality so Low keeps the silhouette", function()
			local def = cached(CANONICAL)
			local optional = 0
			for _, component in def.components do
				if component.minQuality then
					optional += 1
				end
			end
			expect(optional).toBeGreaterThanOrEqual(2)
			local high = Compiler.compile(def, { quality = "High" })
			local low = Compiler.compile(def, { quality = "Low" })
			expect(#low.components).toBeLessThan(#high.components)
			expect(low.byId["impact-flash"]).toBeTruthy()
			expect(low.byId["shockwave"]).toBeTruthy()
		end)

		T.it("uses the palette references everywhere colours appear", function()
			local def = cached(CANONICAL)
			local text = Json.encode(def.components)
			expect(string.find(text, '"#', 1, true)).toBeNil()
			for _, key in { "$core", "$mid" } do
				expect(string.find(text, key, 1, true) ~= nil).toBe(true)
			end
		end)

		T.it("builds loops that repeat seamlessly", function()
			for _, prompt in { "fire aura", "arcane magic circle", "Schattenaura", "big electric aura with arcs" } do
				local def = generate(prompt)
				expect(def.loop).toBe(true)
				local impact = marker(def, "impact")
				expect(impact.time).toBeCloseTo(def.duration / 2, 1e-6)
				for _, component in def.components do
					for _, track in component.tracks or {} do
						if component.startTime == 0 and component.duration == def.duration then
							local keys = track.keyframes
							expect(keys[1].time).toBe(0)
							expect(keys[#keys].time).toBe(component.duration)
							expect(keys[#keys].value).toEqual(keys[1].value)
						end
					end
				end
			end
		end)

		T.it("adds element layers: flames, arcs, shards, splash, rays, debris", function()
			local cases: { { string } } = {
				{ "fire explosion", "Flame Burst" },
				{ "lightning explosion", "Electric Arc 1" },
				{ "ice explosion", "Ice Shards" },
				{ "water impact", "Water Splash" },
				{ "holy impact", "Light Rays" },
				{ "earth impact", "Rock Debris" },
				{ "poison impact", "Toxic Bubbles" },
				{ "nature impact", "Leaves" },
				{ "wind impact", "Swirl Trail 1" },
				{ "lightning strike", "Lightning Bolt" },
				{ "holy strike", "Light Pillar" },
				{ "fire strike", "Strike Beam" },
			}
			for _, case in cases do
				local def = generate(case[1])
				if not find(def, case[2]) then
					T.fail(case[1] .. " has no " .. case[2])
				end
			end
		end)

		T.it("archetype templates produce their signature layers", function()
			local cases: { { string } } = {
				{ "beam", "Beam Core" },
				{ "slash", "Slash Arc" },
				{ "slash", "Swing Trail" },
				{ "meteor", "Meteor Trail" },
				{ "teleport", "Portal Ring" },
				{ "teleport", "Light Pillar" },
				{ "aura", "Ground Ring" },
				{ "magic circle", "Rune Star" },
				{ "strike", "Target Telegraph" },
				{ "explosion", "Gathering Energy" },
				{ "explosion with debris", "Debris" },
			}
			for _, case in cases do
				local def = generate(case[1])
				if not find(def, case[2]) then
					T.fail(case[1] .. " has no " .. case[2])
				end
			end
		end)

		T.it("honours negations and explicit layers", function()
			local def = generate("fire explosion without smoke, no debris and no shake")
			expect(#byPhase(def, "dissipation")).toBe(0)
			expect(#byPhase(def, "secondary", "debris")).toBe(0)
			expect(find(def, "Camera Shake")).toBeNil()
			local plain = generate("lightning explosion")
			expect(find(plain, "Smoke")).toBeNil()
			local smoky = generate("lightning explosion with smoke")
			expect(find(smoky, "Smoke")).toBeTruthy()
			local all = generate("no flash, no shockwave, no sparks, no smoke, no sphere")
			expect(#all.components).toBeGreaterThanOrEqual(1)
			expect(Validation.validate(all).ok).toBe(true)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Determinism, options, robustness
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("determinism and options", function()
		T.it("gives byte-identical output for the same prompt and seed", function()
			for _, prompt in { CANONICAL, "Dunkle Schattenaura", "quick lightning strike", "" } do
				local a = Json.encode((generate(prompt)))
				local b = Json.encode((generate(prompt)))
				expect(a).toBe(b)
				local c = Json.encode((generate(prompt, { seed = 7 })))
				local d = Json.encode((generate(prompt, { seed = 7 })))
				expect(c).toBe(d)
			end
		end)

		T.it("defaults the seed to Random.hash(prompt) and stores it", function()
			local def, report = generate(CANONICAL)
			expect(def.seed).toBe(Random.hash(CANONICAL))
			expect(report.seed).toBe(def.seed)
			local seeded = generate(CANONICAL, { seed = 12345.9 })
			expect(seeded.seed).toBe(12345)
		end)

		T.it("varies only the procedural details with the seed", function()
			local a = generate(CANONICAL, { seed = 1 })
			local b = generate(CANONICAL, { seed = 2 })
			expect(#a.components).toBe(#b.components)
			expect(Json.encode(a.components)).never.toBe(Json.encode(b.components))
			expect(Json.encode(a.markers)).toBe(Json.encode(b.markers))
			expect(Validation.validate(b).ok).toBe(true)
		end)

		T.it("uses options.name for the name and id", function()
			local def, report = generate("fire explosion", { name = "  My Boom  " })
			expect(def.name).toBe("My Boom")
			expect(def.id).toBe("my-boom")
			expect(report.name).toBe("My Boom")
			local long = generate("fire explosion", { name = string.rep("Ü", 150) })
			expect(utf8.len(long.name)).toBeLessThanOrEqual(Constants.NAME_MAX_LENGTH)
			expect(Validation.validate(long).ok).toBe(true)
			local blank = generate("fire explosion", { name = "   " })
			expect(blank.name).toBe("Fire Explosion")
		end)

		T.it("rejects programmer errors", function()
			expect(function()
				Generator.generate(42 :: any)
			end).toThrow("prompt must be a string")
			expect(function()
				Generator.generate("x", { seed = 0 / 0 })
			end).toThrow("options.seed")
			expect(function()
				Generator.generate("x", { seed = math.huge })
			end).toThrow("options.seed")
		end)

		T.it("accepts nil as an empty prompt and can skip the analysis", function()
			local def, report = Generator.generate(nil, { analyze = false })
			expect(Validation.validate(def).ok).toBe(true)
			expect(report.archetype).toBe("impact")
			expect(next(report.performance)).toBeNil()
			expect(def.description).toBeNil()
		end)

		T.it("keeps the description valid UTF-8 and short", function()
			local def = generate("explosion \255\254 fire " .. string.rep("ä", 500))
			expect(utf8.len(def.description)).toBeTruthy()
			expect(utf8.len(def.description)).toBeLessThanOrEqual(Generator.DESCRIPTION_MAX_LENGTH + 1)
			expect(function()
				Json.encode(def)
			end).never.toThrow()
		end)

		T.it("records the interpretation in metadata and tags", function()
			local def = cached(CANONICAL)
			expect(def.tags).toEqual({ "generated", "explosion", "lightning" })
			expect(def.metadata.generator.version).toBe(Generator.VERSION)
			expect(def.metadata.generator.intensity).toBe(2)
		end)

		T.it("plans layers without building (Composer.plan)", function()
			local entries = Composer.plan({
				archetype = "explosion",
				element = "fire",
				intensity = 1,
				speed = 1,
				charge = false,
				bright = false,
				components = { "smoke" },
				excluded = { "debris" },
			})
			local kinds = {}
			local lastRank = 0
			for _, entry in entries do
				table.insert(kinds, entry.kind)
				local rank = table.find(PHASES, entry.phase) :: number
				expect(rank).toBeGreaterThanOrEqual(lastRank)
				lastRank = rank
			end
			expect(contains(kinds, "flameBurst")).toBe(true)
			expect(contains(kinds, "elementDebris")).toBe(false)
			expect(contains(kinds, "dissipation")).toBe(true)
		end)

		T.it("drops the optional layers that break a High budget", function()
			local budget = Analyzer.BUDGETS.High
			local saved = budget.beams
			budget.beams = 8
			local ok, def, report = pcall(Generator.generate, CANONICAL)
			budget.beams = saved
			expect(ok).toBe(true)
			-- Arcs 2 and 3 (optional, 7 beams each) go first; the required arc and the impact frame stay.
			expect(find(def, "Electric Arc 1")).toBeTruthy()
			expect(find(def, "Electric Arc 2")).toBeNil()
			expect(find(def, "Electric Arc 3")).toBeNil()
			expect(find(def, "Impact Frame")).toBeTruthy()
			expect(report.performance.High).never.toBe("over")
			expect(string.find(table.concat(report.notes, " "), "Electric Arc 3", 1, true) ~= nil).toBe(true)
			expect(contains(report.components, "Electric Arc 2")).toBe(false)
			expect(Validation.validate(def).ok).toBe(true)
			-- Budgets that no optional layer can fix are reported, not hidden.
			budget.beams = 1
			local ok2, _, report2 = pcall(Generator.generate, CANONICAL)
			budget.beams = saved
			expect(ok2).toBe(true)
			expect(report2.performance.High).toBe("over")
		end)

		T.it("falls back to the generic impact when composing fails", function()
			local original = Composer.compose
			local calls = 0
			Composer.compose = function(intent: any, options: any)
				calls += 1
				if calls == 1 then
					error("boom", 0)
				end
				return original(intent, options)
			end
			local ok, def, report = pcall(Generator.generate, "fire explosion")
			Composer.compose = original
			expect(ok).toBe(true)
			expect(report.fallback).toBe(true)
			expect(report.archetype).toBe("impact")
			expect(Validation.validate(def).ok).toBe(true)
			expect(string.find(table.concat(report.notes, " "), "boom", 1, true) ~= nil).toBe(true)
		end)
	end)
end
