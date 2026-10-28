--!strict
--[[
	Composer — turns a Generator intent into an EffectDefinition (schema version 1).

	  Composer.compose(intent, options) -> (EffectDefinition, ComposeInfo)
	  Composer.plan(intent) -> ({ PlanEntry }, { string })        the layer kinds (+ notes), without building

	Steps:
	  1. Timeline. T = speed × (1 + 0.3 × (intensity − 1)) scales every phase length of the archetype template
	     (Recipes.ARCHETYPES): anticipation [0, a), charge [a, a + c) (only with a charge), action [.., impact),
	     then secondary and dissipation after the impact moment. The craft-rule timings inside the layers are
	     clamped (flash decay 0.2–0.35 s, shockwave 0.4–0.8 s, smoke fade 1–2 s), so speed and size never push
	     them out of their readable range. Looping archetypes use loopDuration × speed; their pulse (the impact
	     marker) sits in the middle of the cycle.
	  2. Plan. The archetype's default layers + the element's extras (Recipes.ELEMENTS[*].extras) + a charge
	     phase when requested (charge sphere + charge particles, + charge arcs for lightning) + the explicit
	     component keywords + intensity accents (massive: impact frame; big impact/slash: camera shake), minus the
	     negated keywords. Kinds are unique, sorted by phase (stable). Layers marked optional ("kind?") get
	     minQuality = "Medium" unless the prompt asked for them.
	  3. Build. Layers (Generator/Layers) add the components through the builder: ids are Ids.unique slugs of
	     the names over the whole effect scope (marker ids are reserved first), numbers are rounded to 1e-3,
	     property and keyframe values go through Codec.normalize (canonical JSON form, ranges clamped), keyframes
	     stay inside the component span and events before its end, and every component is clipped to the
	     effect duration (= the latest span end, at least the loop duration).
	  4. Markers: one per phase that has components, at the earliest start of that phase; the impact marker
	     ("Impact", event "Impact") always exists at the impact moment.

	Deterministic: no pairs() order is observable, randomness only comes from Core/Random seeded with the seed.
]]

local Codec = require(script.Parent.Parent.Parent.AstraVFX.Core.Codec)
local Components = require(script.Parent.Parent.Parent.AstraVFX.Core.Components)
local Constants = require(script.Parent.Parent.Parent.AstraVFX.Core.Constants)
local Random = require(script.Parent.Parent.Parent.AstraVFX.Core.Random)
local Types = require(script.Parent.Parent.Parent.AstraVFX.Core.Types)
local Ids = require(script.Parent.Parent.Ids)
local Layers = require(script.Parent.Layers)
local Recipes = require(script.Parent.Recipes)

type EffectDefinition = Types.EffectDefinition
type ComponentDef = Types.ComponentDef
type LayerSpec = Layers.LayerSpec
type Ctx = Layers.Ctx

export type Intent = {
	archetype: string,
	element: string,
	intensity: number,
	speed: number,
	color: string?,
	shade: string?,
	charge: boolean,
	bright: boolean,
	components: { string }, -- requested component keywords (Lexicon component tags), prompt order
	excluded: { string }, -- negated component keywords
}

export type ComposeOptions = {
	seed: number,
	name: string,
	id: string,
	description: string?,
	tags: { string }?,
	metadata: { [string]: any }?,
}

export type PlanEntry = { kind: string, phase: string, optional: boolean, explicit: boolean }

export type LayerInfo = { id: string, name: string, type: string, phase: string, kind: string, minQuality: string? }

export type ComposeInfo = {
	layers: { LayerInfo },
	notes: { string },
	times: { [string]: number },
	duration: number,
}

local Composer = {}

local PHASE_RANK: { [string]: number } = {}
for i, phase in Constants.PHASES do
	PHASE_RANK[phase] = i
end
local PHASE_LABEL: { [string]: string } = {
	anticipation = "Anticipation",
	charge = "Charge",
	action = "Action",
	impact = "Impact",
	secondary = "Secondary",
	dissipation = "Dissipation",
}
local QUALITY_RANK: { [string]: number } = { Low = 1, Medium = 2, High = 3 }

local BURST_ACCENTS = { impact = true, explosion = true, strike = true, meteor = true }

-- Explicit component keyword -> layer kinds (one-shot effects).
local REQUEST_KINDS: { [string]: { string } } = {
	sphere = { "coreBurst" },
	arcs = { "arcs" },
	flash = { "flash" },
	shockwave = { "shockwave" },
	smoke = { "dissipation" },
	debris = { "debris" },
	sparks = { "sparks", "embers" },
	beam = { "skyBeam" },
	trail = { "orbit" },
	pillar = { "pillar" },
	rays = { "rays" },
	shake = { "shake" },
	screen = { "screen" },
}
-- Looping effects map some requests differently (no one-shot bursts).
local LOOP_KINDS: { [string]: { string } } = {
	sphere = { "orb" },
	sparks = { "motes" },
	shockwave = { "pulse" },
	debris = {},
	trail = { "orbit" },
}
-- Negated keyword -> kinds removed.
local EXCLUDE_KINDS: { [string]: { string } } = {
	charge = { "chargeSphere", "chargeParticles", "chargeArcs" },
	sphere = { "chargeSphere", "coreBurst", "orb" },
	arcs = { "arcs", "chargeArcs", "residualArcs" },
	flash = { "flash", "screen" },
	shockwave = { "shockwave", "pulse" },
	smoke = { "dissipation" },
	debris = { "debris", "elementDebris" },
	sparks = { "sparks", "embers", "motes" },
	beam = { "skyBeam" },
	trail = { "orbit", "swing" },
	pillar = { "pillar" },
	rays = { "rays" },
	shake = { "shake" },
	screen = { "screen" },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Numbers and values
-- ─────────────────────────────────────────────────────────────────────────────

local function round(x: number): number
	local r = math.floor(x * 1000 + 0.5) / 1000
	return if r == 0 then 0 else r
end

-- Rounds every number of a JSON-like value (arrays and objects of numbers / strings / booleans).
local function roundDeep(value: any): any
	if type(value) == "number" then
		return round(value)
	elseif type(value) == "table" then
		local out = {}
		for k, v in value do
			out[k] = roundDeep(v)
		end
		return out
	end
	return value
end

local function contains(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Plan
-- ─────────────────────────────────────────────────────────────────────────────

local function parseKind(entry: string): (string, boolean)
	if string.sub(entry, -1) == "?" then
		return string.sub(entry, 1, -2), true
	end
	return entry, false
end

-- Layer kinds of an intent (sorted by phase) and the notes explaining additions / removals.
function Composer.plan(intent: Intent): ({ PlanEntry }, { string })
	local A = Recipes.ARCHETYPES[intent.archetype] or Recipes.ARCHETYPES.impact
	local E = Recipes.ELEMENTS[intent.element] or Recipes.ELEMENTS.neutral
	local notes: { string } = {}
	local entries: { PlanEntry } = {}
	local byKind: { [string]: PlanEntry } = {}

	local function push(kind: string, optional: boolean, explicit: boolean)
		local existing = byKind[kind]
		if existing then
			if explicit then
				existing.explicit = true
				existing.optional = false
			end
			return
		end
		local phase = Layers.PHASE[kind]
		if not phase then
			return
		end
		local entry = { kind = kind, phase = phase, optional = optional and not explicit, explicit = explicit }
		byKind[kind] = entry
		table.insert(entries, entry)
	end

	for _, raw in A.layers do
		local kind, optional = parseKind(raw)
		push(kind, optional, false)
	end
	local extras: { string } = {}
	local everyBurst: { string } = if A.burst then E.extras["*"] or {} else {}
	local forArchetype: { string } = E.extras[intent.archetype] or {}
	for _, list in { everyBurst, forArchetype } do
		for _, raw in list do
			table.insert(extras, raw)
		end
	end
	for _, raw in extras do
		local kind, optional = parseKind(raw)
		if A.loop and (kind == "debris" or kind == "splash" or kind == "flameBurst") then
			continue
		end
		push(kind, optional, false)
	end

	-- Charge phase
	local hasCharge = A.chargeDefault or (intent.charge and not A.loop)
	if intent.charge and A.loop then
		push("chargeParticles", false, true)
	elseif hasCharge then
		push("chargeSphere", false, intent.charge)
		push("chargeParticles", false, intent.charge)
		if intent.element == "lightning" then
			push("chargeArcs", false, false)
		end
		if intent.charge and not A.chargeDefault then
			table.insert(notes, "Charge phase added (" .. string.format("%.2f", A.charge) .. " s base).")
		end
	end

	-- Explicit component keywords
	for _, request in intent.components do
		if request == "charge" or contains(intent.excluded, request) then
			continue
		end
		local kinds: { string } = (if A.loop then LOOP_KINDS[request] else nil) or REQUEST_KINDS[request] or {}
		if request == "sphere" and hasCharge then
			kinds = { "chargeSphere" }
		elseif request == "beam" and intent.archetype == "beam" then
			kinds = { "beam" }
		elseif request == "arcs" and intent.archetype == "strike" then
			kinds = { "residualArcs" }
		elseif request == "trail" and (intent.archetype == "slash" or intent.archetype == "meteor") then
			kinds = { if intent.archetype == "slash" then "swing" else "meteor" }
		elseif request == "pillar" and intent.archetype == "strike" and intent.element == "holy" then
			kinds = { "strikeAction" }
		elseif request == "debris" and A.loop then
			table.insert(notes, "Debris is skipped for looping effects.")
		end
		for _, kind in kinds do
			push(kind, false, true)
		end
	end

	-- Intensity accents
	if intent.intensity >= 2 and BURST_ACCENTS[intent.archetype] then
		push("screen", false, false)
	end
	if intent.intensity >= 1.4 and (intent.archetype == "impact" or intent.archetype == "slash") then
		push("shake", false, false)
	end
	if intent.intensity < 1 then
		for _, kind in { "shake", "screen" } do
			local entry = byKind[kind]
			if entry and not entry.explicit then
				byKind[kind] = nil
				table.remove(entries, table.find(entries, entry) :: number)
			end
		end
	end

	-- Negations
	for _, request in intent.excluded do
		local removed: { string } = {}
		local kinds: { string } = EXCLUDE_KINDS[request] or {}
		for _, kind in kinds do
			local entry = byKind[kind]
			if entry then
				byKind[kind] = nil
				table.remove(entries, table.find(entries, entry) :: number)
				table.insert(removed, kind)
			end
		end
		if #removed > 0 then
			table.insert(notes, "Negated '" .. request .. "': removed " .. #removed .. " layer(s).")
		end
	end

	-- Stable sort by phase
	local order: { [PlanEntry]: number } = {}
	for i, entry in entries do
		order[entry] = i
	end
	table.sort(entries, function(a: PlanEntry, b: PlanEntry)
		local ra, rb = PHASE_RANK[a.phase], PHASE_RANK[b.phase]
		if ra ~= rb then
			return ra < rb
		end
		return order[a] < order[b]
	end)
	return entries, notes
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Builder
-- ─────────────────────────────────────────────────────────────────────────────

type BuilderState = {
	add: (self: any, spec: LayerSpec) -> string,
	components: { ComponentDef },
	info: { LayerInfo },
	taken: { [string]: boolean },
	kind: string,
	optional: boolean,
}

local function normalizeProperty(componentType: string, name: string, value: any): any
	local spec = Components.propertySpec(componentType, name)
	if not spec then
		error("Composer: " .. componentType .. " has no property '" .. name .. "'", 0)
	end
	return Codec.normalize(spec.kind, value, spec)
end

local function normalizeKey(componentType: string, channel: string, value: any): any
	local spec = Components.channelSpec(componentType, channel)
	if not spec then
		error("Composer: " .. componentType .. " has no channel '" .. channel .. "'", 0)
	end
	return Codec.normalize(spec.kind, value, spec)
end

local function strongerQuality(a: string?, b: string?): string?
	if a == nil then
		return b
	elseif b == nil then
		return a
	end
	return if QUALITY_RANK[a] >= QUALITY_RANK[b] then a else b
end

local function addComponent(self: BuilderState, spec: LayerSpec): string
	local componentType = spec.type
	if not Components.get(componentType) then
		error("Composer: unknown component type " .. componentType, 0)
	end
	local id = Ids.unique(Ids.slug(spec.name, componentType), self.taken)
	local start = math.max(round(spec.start), 0)
	local duration = math.max(round(spec.duration), 0.01)
	local def: any = {
		id = id,
		name = spec.name,
		type = componentType,
		startTime = start,
		duration = duration,
		phase = spec.phase,
	}
	if spec.parent then
		def.parent = spec.parent
	end
	local minQuality = spec.minQuality
	if self.optional then
		minQuality = strongerQuality(minQuality, "Medium")
	end
	if minQuality then
		def.minQuality = minQuality
	end
	local transform: any = {}
	if spec.position then
		transform.position = roundDeep(spec.position)
	end
	if spec.rotation then
		transform.rotation = roundDeep(spec.rotation)
	end
	if next(transform) ~= nil then
		def.transform = transform
	end

	local names: { string } = {}
	for name in spec.properties do
		table.insert(names, name)
	end
	table.sort(names)
	if #names > 0 then
		local properties: { [string]: any } = {}
		for _, name in names do
			properties[name] = normalizeProperty(componentType, name, roundDeep(spec.properties[name]))
		end
		def.properties = properties
	end

	if spec.tracks and #spec.tracks > 0 then
		local tracks = {}
		for _, track in spec.tracks do
			local keyframes = {}
			local last = 0
			for _, key in track.keys do
				local t = math.clamp(round(key[1]), last, duration)
				last = t
				local keyframe: any =
					{ time = t, value = normalizeKey(componentType, track.channel, roundDeep(key[2])) }
				local easing = key[3]
				if easing and easing ~= "Linear" then
					keyframe.easing = easing
				end
				table.insert(keyframes, keyframe)
			end
			table.insert(tracks, {
				id = Ids.unique(id .. "-" .. track.channel, self.taken),
				channel = track.channel,
				keyframes = keyframes,
			})
		end
		def.tracks = tracks
	end

	if spec.events and #spec.events > 0 then
		local events = {}
		for _, event in spec.events do
			local t = math.clamp(round(event.time), 0, math.max(duration - 0.001, 0))
			local entry: any =
				{ id = Ids.unique(id .. "-" .. event.action, self.taken), time = t, action = event.action }
			if event.count then
				entry.count = event.count
			end
			if event.name then
				entry.name = event.name
			end
			table.insert(events, entry)
		end
		def.events = events
	end

	if spec.overrides then
		local overrides: { [string]: any } = {}
		for _, level in Constants.QUALITY_LEVELS do
			local values = spec.overrides[level]
			if values then
				local out: { [string]: any } = {}
				for name, value in values do
					out[name] = normalizeProperty(componentType, name, roundDeep(value))
				end
				overrides[level] = out
			end
		end
		def.qualityOverrides = overrides
	end
	if spec.notes then
		def.notes = spec.notes
	end

	table.insert(self.components, def :: ComponentDef)
	table.insert(self.info, {
		id = id,
		name = spec.name,
		type = componentType,
		phase = spec.phase,
		kind = self.kind,
		minQuality = minQuality,
	})
	return id
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Compose
-- ─────────────────────────────────────────────────────────────────────────────

local function makeContext(intent: Intent, seed: number): Ctx
	local A = Recipes.ARCHETYPES[intent.archetype] or Recipes.ARCHETYPES.impact
	local E = Recipes.ELEMENTS[intent.element] or Recipes.ELEMENTS.neutral
	local I = intent.intensity
	local S = I
	local N = 1 + (I - 1) * 0.5
	local T = intent.speed * (1 + 0.3 * (I - 1))
	local hasCharge = A.chargeDefault or (intent.charge and not A.loop)
	local lens = {
		anticipation = A.anticipation * T,
		charge = if hasCharge then A.charge * T else 0,
		action = A.action * T,
		secondary = A.secondary * T,
		dissipation = A.dissipation * T,
	}
	local times = {
		anticipation = 0,
		charge = lens.anticipation,
		action = lens.anticipation + lens.charge,
		impact = lens.anticipation + lens.charge + lens.action,
	}
	local D = (A.loopDuration or 2) * intent.speed
	if A.loop then
		times = { anticipation = 0, charge = 0, action = 0, impact = D / 2 }
	end
	local h = A.coreHeight * S
	local center = { 0, h, 0 }
	local target = center
	if intent.archetype == "beam" then
		target = { 0, h, -(S + 36 * S) }
	elseif intent.archetype == "meteor" or intent.archetype == "strike" then
		target = { 0, h * 0.6, 0 }
	end
	local rng = Random.new(seed)
	return {
		S = S,
		N = N,
		T = T,
		I = I,
		times = times,
		lens = lens,
		loop = A.loop,
		D = D,
		center = center,
		target = target,
		ground = 0,
		E = E,
		A = A,
		element = intent.element,
		archetype = intent.archetype,
		bright = intent.bright,
		forceSmoke = contains(intent.components, "smoke"),
		tilt = rng:range(-25, 25),
		rng = rng,
		explicit = {},
	}
end

-- Builds the definition of an intent.
function Composer.compose(intent: Intent, options: ComposeOptions): (EffectDefinition, ComposeInfo)
	local A = Recipes.ARCHETYPES[intent.archetype] or Recipes.ARCHETYPES.impact
	local entries, notes = Composer.plan(intent)
	local c = makeContext(intent, options.seed)
	for _, entry in entries do
		if entry.explicit then
			c.explicit[entry.kind] = true
		end
	end
	for _, request in intent.components do
		c.explicit[request] = true
	end

	local taken: { [string]: boolean } = {}
	for _, phase in Constants.PHASES do
		taken[phase] = true
	end
	local builder: BuilderState = {
		add = addComponent,
		components = {},
		info = {},
		taken = taken,
		kind = "",
		optional = false,
	}
	local layersAny: any = Layers
	for _, entry in entries do
		builder.kind = entry.kind
		builder.optional = entry.optional
		local fn = layersAny[entry.kind]
		if type(fn) == "function" then
			fn(builder, c)
		end
	end
	if #builder.components == 0 then
		-- Everything was negated: keep a visible core so the effect is never empty.
		builder.kind = "flash"
		builder.optional = false
		Layers.flash(builder :: any, c)
		table.insert(notes, "Every layer was removed; kept a single impact flash.")
	end

	-- Duration: latest span end (loops: the cycle).
	local duration = 0
	for _, component in builder.components do
		duration = math.max(duration, (component.startTime or 0) + (component.duration or 0))
	end
	if A.loop then
		duration = math.max(c.D, 0.1)
	end
	duration = math.clamp(math.ceil(duration * 100 - 1e-6) / 100, 0.1, Constants.MAX_DURATION)
	for _, component in builder.components do
		local start = component.startTime or 0
		if start + (component.duration or 0) > duration then
			component.duration = math.max(round(duration - start), 0.01)
		end
	end

	-- Markers
	local firstStart: { [string]: number } = {}
	for _, component in builder.components do
		local phase: string = component.phase or "action"
		local start = component.startTime or 0
		if firstStart[phase] == nil or start < firstStart[phase] then
			firstStart[phase] = start
		end
	end
	firstStart.impact = round(c.times.impact)
	local markers = {}
	local times: { [string]: number } = {}
	for _, phase in Constants.PHASES do
		local t = firstStart[phase]
		if t then
			t = math.min(t, duration)
			times[phase] = t
			local marker: any = { id = phase, time = t, label = PHASE_LABEL[phase], phase = phase }
			if phase == "impact" then
				marker.event = "Impact"
			end
			table.insert(markers, marker)
		end
	end
	table.sort(markers, function(a: any, b: any)
		if a.time ~= b.time then
			return a.time < b.time
		end
		return PHASE_RANK[a.phase] < PHASE_RANK[b.phase]
	end)

	local palette = Recipes.palette(intent.element, intent.color, intent.shade)
	local def: any = {
		schemaVersion = Constants.SCHEMA_VERSION,
		id = options.id,
		name = options.name,
		duration = duration,
		seed = options.seed,
		palette = { core = palette.core, mid = palette.mid, edge = palette.edge, smoke = palette.smoke },
		markers = markers,
		components = builder.components,
	}
	if options.description and options.description ~= "" then
		def.description = options.description
	end
	if options.tags and #options.tags > 0 then
		def.tags = options.tags
	end
	if A.loop then
		def.loop = true
	end
	if options.metadata then
		def.metadata = options.metadata
	end
	return def :: EffectDefinition, { layers = builder.info, notes = notes, times = times, duration = duration }
end

return Composer
