--!strict
--[[
	Compiler — EffectDefinition -> CompiledEffect for one (quality, scale, palette, seed) combination.
	See docs/MODULE_CONTRACTS.md §15, docs/COMPONENTS_SPEC.md §0 and docs/ARCHITECTURE.md §4/§5.

	  Compiler.compile(def, options?) -> (CompiledEffect, { Diagnostic })
	  Compiler.scheduleForCycle(compiled, cycle) -> { ScheduledAction }
	  Compiler.key(def, options?, contentHash?) -> string
	  Compiler.contentHash(def) -> string

	Pure: no Instances, no yields, no global state. The input definition is never mutated (the compiled effect
	keeps a reference to it as `definition`) and is expected to be migrated + validated; compile() is defensive
	anyway (see "Robustness") and never reads properties the component descriptors do not declare.

	Steps of compile():
	  1. Options: quality = Quality.resolve(options.quality, def.quality) (nil / "Auto" -> Quality.detect(); a
	     QualityProfile table is accepted as well), scale = options.scale or 1 (finite > 0, else error),
	     seed = options.seed or def.seed or Random.hash(def.id).
	  2. Palette: every definition entry ("#RRGGBB") decoded to a Color3, then options.palette merged over it
	     (Color3 values, or colour strings Codec.parseColor understands; overrides may add new keys). "$name"
	     references in properties, tracks and graph values resolve through this merged palette.
	  3. Order: stable topological order — parents before children, otherwise definition order (at every step
	     the ready component with the smallest definition index comes next, so a definition that lists parents
	     first keeps its order exactly). depth = 0 for roots, parent depth + 1 below.
	  4. Filter, walking that order: a component is built when its type is registered, enabled ~= false,
	     Quality.includes(level, minQuality) and its parent (if any) is built. Light components are counted in
	     the same walk (only lights that would be built count); lights beyond quality.maxLights are dropped
	     together with their descendants.
	  5. Per component:
	     * props: for every PropertySpec of the descriptor the JSON value is qualityOverrides[level][name], else
	       properties[name], else spec.default, decoded with Codec.decode(kind, value, spec, palette) (clamped
	       to spec.min/max in authored units).
	     * quality rules, for values that do NOT come from qualityOverrides (an override is the author's exact
	       value for that level):
	         quality = "count"     integer kind: Common.scaledCount(v, countScale, 1) (rounded, >= 1 when v > 0)
	                               number kind:  v * countScale, at least min(v, 1) when v > 0 (not rounded,
	                                             so a fractional rate such as 0.5/s is never raised)
	         quality = "segments"  round(v * segmentScale), at least spec.min or 1
	       then clamped to spec.min/max again. A factor of exactly 1 leaves the value untouched.
	     * effect scale on spec.scale == "length": numbers and vectors × scale, NumberRange ends × scale,
	       NumberSequence values and envelopes × scale (Common.scaleSequence). Not clamped afterwards
	       (descriptors clamp engine limits such as Light.Range <= 120 themselves).
	     * rest transform: position = transform.position × scale, rotation (degrees) as authored, scale =
	       transform.scale (default 1; the component's own multiplier, not the effect scale).
	     * tracks: tracks with enabled ~= false on a declared channel, via Curves.compileTrack(track,
	       channelSpec, palette, scale) (Curves scales "length" channels). One track per channel: the first wins.
	       A number channel whose baseProperty has a quality rule (particles `rate` -> property `rate`, "count")
	       gets the same rule on every keyframe value, so tracks and the rest value share the compiled domain
	       (controllers write channel values as given).
	     * events: copied in definition order; "emit" counts are clamped to 0..MAX_EMIT_COUNT and scaled with
	       Common.scaledCount(count, countScale, 1) (0 stays 0; a missing count stays nil = descriptor default).
	     * seed = Random.hash(seed, component.id); startTime/endTime = Timeline.span(def, component).
	  6. Graph: Graph.compile(def.graph, def) when the graph has nodes (compiled.graph, used by the Player for
	     OnEvent triggers), else nil.
	  7. schedule = scheduleForCycle(compiled, 0).
	  8. maxTail = max(descriptor.tailTime(component)) over the built components (0 without any).

	scheduleForCycle(compiled, cycle): Timeline.staticSchedule(components, markers) merged with
	Graph.staticSchedule(graph, seed, cycle, compiled) (OnPlay at 0 + every OnMarker at its marker time, each
	unrolled with Graph.run). At equal times timeline actions (events, markers) come before graph actions; the
	merged list is stably sorted by time and `order` renumbered 1..n. The Player calls it for every loop cycle
	(graph random values depend on (seed, cycle)). Without a graph, or for cycle 0, it returns compiled.schedule
	itself; otherwise a fresh list. Treat the result as read-only.

	key(def, options?, contentHash?): "<id>|<content hash>|q=<profile>|s=<scale>|seed=<seed>|p=<palette>".
	The content hash covers Json.encode(def, { pretty = false }) (two FNV-1a 32-bit hashes + length), the
	profile part lists every field of the resolved quality profile (so "Auto" keys by the detected level and a
	custom profile by its numbers), the palette part the override entries sorted by key (exact RGB values).
	Encoding the definition is O(size); callers that keep immutable definitions (the runtime registry) can
	compute Compiler.contentHash(def) once and pass it as the third argument.

	The second return value of compile() lists warnings: graph unrolling limits (graph.action_limit) and
	components / tracks skipped on unvalidated input (compiler.*).

	Robustness (unvalidated input; Validation reports these properly): components without a string id, with a
	duplicate id or an unregistered type are skipped (with their descendants); an unknown parent id makes the
	component a root; components in a parent cycle are skipped; an invalid minQuality is ignored; tracks on
	undeclared channels are skipped. Invalid property, keyframe or palette values raise errors (Codec / Curves).
]]

local Codec = require(script.Parent.Codec)
local Common = require(script.Parent.Components.Common)
local Components = require(script.Parent.Components)
local Constants = require(script.Parent.Constants)
local Curves = require(script.Parent.Curves)
local Graph = require(script.Parent.Graph)
local Json = require(script.Parent.Json)
local Quality = require(script.Parent.Quality)
local Random = require(script.Parent.Random)
local Timeline = require(script.Parent.Timeline)
local Types = require(script.Parent.Types)

type EffectDefinition = Types.EffectDefinition
type ComponentDef = Types.ComponentDef
type CompiledEffect = Types.CompiledEffect
type CompiledComponent = Types.CompiledComponent
type CompiledTrack = Types.CompiledTrack
type CompiledEvent = Types.CompiledEvent
type ScheduledAction = Types.ScheduledAction
type QualityProfile = Types.QualityProfile
type QualityLevel = Types.QualityLevel
type PropertySpec = Types.PropertySpec
type Diagnostic = Types.Diagnostic
type MarkerDef = Types.MarkerDef

export type CompileOptions = {
	quality: (QualityLevel | "Auto" | QualityProfile)?,
	scale: number?,
	palette: { [string]: Color3 }?,
	seed: number?,
}

local Compiler = {}

local INF = math.huge
local MAX_EMIT_COUNT = Constants.MAX_EMIT_COUNT

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function fmt(x: any): string
	if type(x) == "number" then
		if x == 0 then
			return "0" -- also -0
		end
		return string.format("%.17g", x)
	end
	return tostring(x)
end

local function warning(code: string, path: string, message: string, componentId: string?): Diagnostic
	return { severity = "warning", code = code, path = path, message = message, componentId = componentId }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Options
-- ─────────────────────────────────────────────────────────────────────────────

local function resolveScale(value: any): number
	if value == nil then
		return 1
	end
	if not isFinite(value) or value <= 0 then
		error("Compiler: options.scale must be a finite number > 0, got " .. fmt(value), 3)
	end
	return value
end

local function resolveSeed(value: any, def: EffectDefinition): number
	if isFinite(value) then
		return value
	end
	local own: any = def.seed
	if isFinite(own) then
		return own
	end
	return Random.hash(def.id)
end

local function buildPalette(def: EffectDefinition, overrides: any): { [string]: Color3 }
	local palette: { [string]: Color3 } = {}
	local source: any = def.palette
	if type(source) == "table" then
		for key, value in source do
			if type(key) == "string" then
				local color = Codec.parseColor(value)
				if color then
					palette[key] = color
				end
			end
		end
	end
	if overrides ~= nil then
		if type(overrides) ~= "table" then
			error("Compiler: options.palette must be a table of Color3 values, got " .. typeof(overrides), 3)
		end
		for key, value in overrides do
			local color = if type(key) == "string" then Codec.parseColor(value) else nil
			if color == nil then
				error("Compiler: options.palette[" .. tostring(key) .. "] must be a Color3, got " .. typeof(value), 3)
			end
			palette[key] = color
		end
	end
	return palette
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Order + filter
-- ─────────────────────────────────────────────────────────────────────────────

type Placed = { def: ComponentDef, index: number, parentId: string?, depth: number }

-- Stable topological order (header step 3) combined with the build filter (step 4).
local function orderAndFilter(def: EffectDefinition, quality: QualityProfile, diagnostics: { Diagnostic }): { Placed }
	local list: { ComponentDef } = def.components or {}
	local indexOf: { [string]: number } = {}
	local valid: { [number]: boolean } = {}
	for i, c in list do
		local id: any = if type(c) == "table" then c.id else nil
		if type(id) ~= "string" then
			table.insert(diagnostics, warning("compiler.component_id", "components[" .. i .. "]", "skipped: no id"))
		elseif indexOf[id] ~= nil then
			table.insert(
				diagnostics,
				warning("compiler.component_id", "components[" .. i .. "]", "skipped: duplicate id " .. id, id)
			)
		else
			indexOf[id] = i
			valid[i] = true
		end
	end

	local children: { [number]: { number } } = {}
	local parentIndex: { [number]: number } = {}
	local ready: { number } = {}
	for i, c in list do
		if not valid[i] then
			continue
		end
		local parent: any = c.parent
		local p: number? = nil
		if type(parent) == "string" and parent ~= "" then
			p = indexOf[parent]
			if p == nil then
				table.insert(
					diagnostics,
					warning(
						"compiler.parent",
						"components[" .. i .. "].parent",
						"unknown parent " .. parent .. "; treated as a root",
						c.id
					)
				)
			end
		end
		if p == nil or p == i then
			table.insert(ready, i)
		else
			parentIndex[i] = p
			local siblings = children[p]
			if siblings == nil then
				siblings = {}
				children[p] = siblings
			end
			table.insert(siblings, i)
		end
	end

	local level: QualityLevel = quality.level
	local maxLights = quality.maxLights
	local lights = 0
	local built: { [number]: boolean } = {}
	local depthOf: { [number]: number } = {}
	local out: { Placed } = {}
	-- `ready` stays sorted ascending: take the smallest index, insert its children in order.
	while #ready > 0 do
		local i = table.remove(ready, 1) :: number
		local c = list[i]
		local p = parentIndex[i]
		local depth = if p then depthOf[p] + 1 else 0
		depthOf[i] = depth
		local kids = children[i]
		if kids then
			for _, child in kids do
				local pos = #ready + 1
				for k, existing in ready do
					if existing > child then
						pos = k
						break
					end
				end
				table.insert(ready, pos, child)
			end
		end

		local keep = c.enabled ~= false
		if Components.get(c.type) == nil then
			keep = false
			table.insert(
				diagnostics,
				warning(
					"compiler.component_type",
					"components[" .. i .. "].type",
					"skipped: unknown component type " .. tostring(c.type),
					c.id
				)
			)
		end
		local minQuality: any = c.minQuality
		if keep and minQuality ~= nil and Quality.isLevel(minQuality) then
			keep = Quality.includes(level, minQuality)
		end
		if keep and p ~= nil then
			keep = built[p] == true
		end
		if keep and c.type == "light" then
			lights += 1
			keep = lights <= maxLights
		end
		if keep then
			built[i] = true
			table.insert(out, {
				def = c,
				index = i,
				parentId = if p then list[p].id else nil,
				depth = depth,
			})
		end
	end
	for i, c in list do
		if valid[i] and depthOf[i] == nil then
			table.insert(
				diagnostics,
				warning("compiler.parent_cycle", "components[" .. i .. "].parent", "skipped: parent cycle", c.id)
			)
		end
	end
	return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Values
-- ─────────────────────────────────────────────────────────────────────────────

local function clampToSpec(v: number, spec: PropertySpec): number
	local lo, hi = spec.min, spec.max
	if lo ~= nil and v < lo then
		v = if spec.kind == "integer" then math.ceil(lo) else lo
	end
	if hi ~= nil and v > hi then
		v = if spec.kind == "integer" then math.floor(hi) else hi
	end
	return v
end

-- Quality rule of one decoded value (header step 5).
local function applyQuality(spec: PropertySpec, value: any, quality: QualityProfile): any
	local rule = spec.quality
	if rule == nil or type(value) ~= "number" then
		return value
	end
	if rule == "count" then
		local factor = quality.countScale
		if factor == 1 then
			return value
		end
		local n: number
		if spec.kind == "integer" then
			n = Common.scaledCount(value, factor, 1)
		else
			n = value * factor
			if value > 0 then
				n = math.max(n, math.min(value, 1))
			end
		end
		return clampToSpec(n, spec)
	elseif rule == "segments" then
		local factor = quality.segmentScale
		if factor == 1 then
			return value
		end
		local n = math.floor(value * factor + 0.5)
		n = math.max(n, spec.min or 1)
		return clampToSpec(n, spec)
	end
	return value
end

-- Effect scale of one decoded "length" value (numbers, vectors, ranges, number sequences).
local function applyScale(value: any, factor: number): any
	if factor == 1 then
		return value
	end
	local t = typeof(value)
	if t == "number" then
		return value * factor
	elseif t == "Vector3" then
		return (value :: Vector3) * factor
	elseif t == "Vector2" then
		return (value :: Vector2) * factor
	elseif t == "NumberRange" then
		local r = value :: NumberRange
		return NumberRange.new(r.Min * factor, r.Max * factor)
	elseif t == "NumberSequence" then
		return Common.scaleSequence(value :: NumberSequence, factor)
	end
	return value
end

local function decodeVector(value: any, fallback: Vector3): Vector3
	if value == nil then
		return fallback
	end
	return Codec.decode("vector3", value)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Components
-- ─────────────────────────────────────────────────────────────────────────────

type Env = {
	def: EffectDefinition,
	quality: QualityProfile,
	scale: number,
	palette: { [string]: Color3 },
	seed: number,
	diagnostics: { Diagnostic },
}

local function compileProps(env: Env, c: ComponentDef, descriptor: Types.ComponentDescriptor): { [string]: any }
	local authored: any = c.properties
	if type(authored) ~= "table" then
		authored = {}
	end
	local overrides: any = c.qualityOverrides
	local levelOverrides: any = if type(overrides) == "table" then overrides[env.quality.level] else nil
	if type(levelOverrides) ~= "table" then
		levelOverrides = nil
	end
	local props: { [string]: any } = {}
	for _, spec in descriptor.properties do
		local name = spec.name
		local raw: any = nil
		local overridden = false
		if levelOverrides ~= nil and levelOverrides[name] ~= nil then
			raw = levelOverrides[name]
			overridden = true
		elseif authored[name] ~= nil then
			raw = authored[name]
		else
			raw = spec.default
		end
		local ok, value = pcall(Codec.decode :: any, spec.kind, raw, spec, env.palette)
		if not ok then
			error(
				"Compiler: component "
					.. string.format("%q", c.id)
					.. " property "
					.. string.format("%q", name)
					.. ": "
					.. tostring(value),
				0
			)
		end
		if not overridden then
			value = applyQuality(spec, value, env.quality)
		end
		if spec.scale == "length" then
			value = applyScale(value, env.scale)
		end
		props[name] = value
	end
	return props
end

local function compileTracks(env: Env, c: ComponentDef, path: string): { [string]: CompiledTrack }
	local tracks: { [string]: CompiledTrack } = {}
	local source: any = c.tracks
	if type(source) ~= "table" then
		return tracks
	end
	for i, track in source do
		if type(track) ~= "table" or track.enabled == false then
			continue
		end
		local channel: any = track.channel
		local spec = if type(channel) == "string" then Components.channelSpec(c.type, channel) else nil
		if spec == nil then
			table.insert(
				env.diagnostics,
				warning(
					"compiler.track_channel",
					path .. ".tracks[" .. i .. "].channel",
					"skipped: " .. c.type .. " has no channel " .. tostring(channel),
					c.id
				)
			)
			continue
		end
		if tracks[channel] ~= nil then
			table.insert(
				env.diagnostics,
				warning(
					"compiler.track_duplicate",
					path .. ".tracks[" .. i .. "]",
					"skipped: a track on channel " .. channel .. " already exists",
					c.id
				)
			)
			continue
		end
		local ok, compiled = pcall(Curves.compileTrack :: any, track, spec, env.palette, env.scale)
		if not ok then
			error("Compiler: component " .. string.format("%q", c.id) .. ": " .. tostring(compiled), 0)
		end
		local base = spec.baseProperty
		local baseSpec = if base and spec.kind == "number" then Components.propertySpec(c.type, base) else nil
		if baseSpec and baseSpec.quality then
			for _, key in (compiled :: CompiledTrack).keys do
				key.value = applyQuality(baseSpec, key.value, env.quality)
			end
		end
		tracks[channel] = compiled
	end
	return tracks
end

local function compileEvents(env: Env, c: ComponentDef): { CompiledEvent }
	local events: { CompiledEvent } = {}
	local source: any = c.events
	if type(source) ~= "table" then
		return events
	end
	local countScale = env.quality.countScale
	for _, ev in source do
		if type(ev) ~= "table" then
			continue
		end
		local count: any = ev.count
		if ev.action == "emit" and isFinite(count) then
			local n = math.clamp(math.floor(count + 0.5), 0, MAX_EMIT_COUNT)
			count = math.min(Common.scaledCount(n, countScale, 1), MAX_EMIT_COUNT)
		end
		table.insert(events, {
			id = ev.id,
			time = ev.time,
			action = ev.action,
			count = count,
			name = ev.name,
		})
	end
	return events
end

local function compileComponent(env: Env, placed: Placed): CompiledComponent
	local c = placed.def
	local descriptor = Components.get(c.type) :: Types.ComponentDescriptor
	local path = "components[" .. placed.index .. "]"
	local startTime, endTime = Timeline.span(env.def, c)
	local transform: any = c.transform
	if type(transform) ~= "table" then
		transform = {}
	end
	local position = decodeVector(transform.position, Vector3.zero) * env.scale
	local rotation = decodeVector(transform.rotation, Vector3.zero)
	local ownScale: any = transform.scale
	local compiled: CompiledComponent = {
		id = c.id,
		name = if type(c.name) == "string" then c.name else c.id,
		type = c.type,
		parentId = placed.parentId,
		depth = placed.depth,
		startTime = startTime,
		endTime = endTime,
		props = compileProps(env, c, descriptor),
		position = position,
		rotation = rotation,
		scale = if isFinite(ownScale) and ownScale >= 0 then ownScale else 1,
		tracks = compileTracks(env, c, path),
		events = compileEvents(env, c),
		seed = Random.hash(env.seed, c.id),
	}
	return compiled
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Schedule
-- ─────────────────────────────────────────────────────────────────────────────

local function buildSchedule(compiled: CompiledEffect, cycle: number, diagnostics: { Diagnostic }?): { ScheduledAction }
	local out: { ScheduledAction } = Timeline.staticSchedule(compiled.components, compiled.markers)
	local graph = compiled.graph
	if graph == nil then
		return out
	end
	local n = #out
	local list, info = Graph.staticSchedule(graph, compiled.seed, cycle, compiled)
	for _, action in ipairs(list) do
		n += 1
		action.order = n
		out[n] = action
	end
	Timeline.sort(out)
	for i, action in out do
		action.order = i
	end
	if diagnostics then
		for _, d in info.diagnostics do
			table.insert(diagnostics, d)
		end
	end
	return out
end

-- Static schedule of loop cycle `cycle` (cycle 0 / no graph: compiled.schedule itself). Read-only result.
function Compiler.scheduleForCycle(compiled: CompiledEffect, cycle: number): { ScheduledAction }
	if type(compiled) ~= "table" or type((compiled :: any).components) ~= "table" then
		error("Compiler.scheduleForCycle: expected a CompiledEffect, got " .. typeof(compiled), 2)
	end
	local c: number = if isFinite(cycle) then cycle else 0
	if compiled.graph == nil or c == 0 then
		return compiled.schedule
	end
	return buildSchedule(compiled, c, nil)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- compile
-- ─────────────────────────────────────────────────────────────────────────────

local function hasGraphNodes(graph: any): boolean
	return type(graph) == "table" and type(graph.nodes) == "table" and #graph.nodes > 0
end

-- Compiles a migrated + validated definition. Returns the CompiledEffect and compiler warnings.
function Compiler.compile(def: EffectDefinition, options: CompileOptions?): (CompiledEffect, { Diagnostic })
	if type(def) ~= "table" then
		error("Compiler.compile: definition must be a table, got " .. typeof(def), 2)
	end
	if type(def.id) ~= "string" then
		error("Compiler.compile: definition has no id", 2)
	end
	local o: CompileOptions = options or {}
	if type(o) ~= "table" then
		error("Compiler.compile: options must be a table, got " .. typeof(o), 2)
	end
	local diagnostics: { Diagnostic } = {}
	local quality = Quality.resolve(o.quality, def.quality :: any)
	local scale = resolveScale(o.scale)
	local palette = buildPalette(def, o.palette)
	local seed = resolveSeed(o.seed, def)
	local env: Env = {
		def = def,
		quality = quality,
		scale = scale,
		palette = palette,
		seed = seed,
		diagnostics = diagnostics,
	}

	local components: { CompiledComponent } = {}
	local byId: { [string]: CompiledComponent } = {}
	local maxTail = 0
	for _, placed in orderAndFilter(def, quality, diagnostics) do
		local component = compileComponent(env, placed)
		table.insert(components, component)
		byId[component.id] = component
		local descriptor = Components.get(component.type) :: Types.ComponentDescriptor
		local tailTime = descriptor.tailTime
		if tailTime then
			local tail = tailTime(component)
			if isFinite(tail) and tail > maxTail then
				maxTail = tail
			end
		end
	end

	local markers: { MarkerDef } = {}
	local sourceMarkers: any = def.markers
	if type(sourceMarkers) == "table" then
		for _, marker in sourceMarkers do
			if type(marker) == "table" then
				table.insert(markers, marker)
			end
		end
	end

	local duration: any = def.duration
	local timeScale: any = def.timeScale
	local compiled: CompiledEffect = {
		id = def.id,
		name = if type(def.name) == "string" then def.name else def.id,
		duration = if isFinite(duration) and duration > 0 then duration else 0,
		loop = def.loop == true,
		timeScale = if isFinite(timeScale) and timeScale >= 0 then timeScale else 1,
		seed = seed,
		scale = scale,
		quality = quality,
		palette = palette,
		components = components,
		byId = byId,
		markers = markers,
		schedule = {},
		graph = if hasGraphNodes(def.graph) then Graph.compile(def.graph, def) else nil,
		maxTail = maxTail,
		definition = def,
	}
	compiled.schedule = buildSchedule(compiled, 0, diagnostics)
	return compiled, diagnostics
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cache key
-- ─────────────────────────────────────────────────────────────────────────────

-- Content hash of the canonical compact JSON of `def` ("<fnv1a><fnv1a'>-<length>").
function Compiler.contentHash(def: EffectDefinition): string
	local text = Json.encode(def, { pretty = false })
	return string.format("%08x%08x-%d", Random.hash(text), Random.hash(#text, text), #text)
end

local function colorKey(value: any): string
	if typeof(value) == "Color3" then
		local c = value :: Color3
		return string.format("%.9g,%.9g,%.9g", c.R, c.G, c.B)
	end
	return typeof(value) .. ":" .. tostring(value)
end

-- Cache key: definition id + content hash + resolved quality profile + scale + seed + palette overrides.
function Compiler.key(def: EffectDefinition, options: CompileOptions?, contentHash: string?): string
	if type(def) ~= "table" then
		error("Compiler.key: definition must be a table, got " .. typeof(def), 2)
	end
	local o: CompileOptions = options or {}
	local hash = contentHash or Compiler.contentHash(def)
	local profile = Quality.resolve(o.quality, def.quality :: any)
	local quality = table.concat({
		profile.level,
		fmt(profile.countScale),
		fmt(profile.segmentScale),
		fmt(profile.sizeCompensation),
		tostring(profile.lightShadows),
		fmt(profile.maxLights),
	}, ",")
	local scale: any = if o.scale == nil then 1 else o.scale
	local paletteParts: { string } = {}
	local overrides: any = o.palette
	if type(overrides) == "table" then
		local keys: { string } = {}
		for k in overrides do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		for _, k in keys do
			table.insert(paletteParts, k .. "=" .. colorKey(overrides[k]))
		end
	end
	return table.concat({
		tostring(def.id),
		hash,
		"q=" .. quality,
		"s=" .. fmt(scale),
		"seed=" .. fmt(resolveSeed(o.seed, def)),
		"p=" .. table.concat(paletteParts, ";"),
	}, "|")
end

return Compiler
