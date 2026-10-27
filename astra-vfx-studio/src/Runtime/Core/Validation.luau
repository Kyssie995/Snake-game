--!strict
--[[
	Validation — checks an EffectDefinition (schema version 1) and collects every problem as a Types.Diagnostic.
	See docs/MODULE_CONTRACTS.md §13 and docs/ARCHITECTURE.md §4.

	  Validation.validate(def: any, options: { strict: boolean? }?) -> ValidationResult
	  Validation.CODES   frozen list of { code, severity, summary } (the table below; source for EFFECT_FORMAT.md)

	validate() is total: it never throws, whatever `def` is (numbers, strings, cyclic tables, wrong types at any
	depth). It is pure (no Instances, no services) and does not migrate: run Migration.migrate first. Every value is
	checked with the component registry specs (Components.propertySpec / channelSpec / eventSpec), Codec.check,
	Easing.check and Graph.validate. Diagnostics come in document order (effect fields, markers, components,
	hierarchy, graph, quality, lints) and are deterministic (object keys are visited in sorted order). Paths use
	1-based indices ("components[3].tracks[1].keyframes[2].value"); the definition itself is the empty path "".
	`componentId` is set on component diagnostics whose component has a valid id. `ok` = no errors.
	Unknown fields and properties are warnings, or errors with { strict = true }.

	Diagnostic codes (stable; severity in brackets when it depends on the case):

	  Effect
	  error    effect.type             the definition is not an object
	  error    effect.schema_version   schemaVersion missing or not Constants.SCHEMA_VERSION (migrate first)
	  error    effect.id               id missing or not [A-Za-z0-9_-]{1,64}
	  error    effect.name             name missing, empty, not a string or longer than NAME_MAX_LENGTH characters
	  error    effect.duration         duration missing, not finite or outside (0, MAX_DURATION]
	  error    effect.description      description is not a string
	  error    effect.tags             tags is not an array of strings
	  error    effect.loop             loop is not a boolean
	  error    effect.seed             seed is not a whole number (|seed| <= 2^53)
	  error    effect.time_scale       timeScale not finite or outside (0, MAX_TIME_SCALE]
	  error    effect.palette          palette is not an object, a key is not [A-Za-z0-9_-]{1,64} or a value is not a
	                                   colour ("#RRGGBB", "#RGB", [r, g, b]; "$key" references are not allowed here)
	  error    effect.metadata         metadata is not an object of plain JSON values (cycles, functions, NaN, ...)
	  error    effect.components       components missing or not an array
	  warning  effect.empty            the effect has no components
	  warning  effect.unknown_field    unknown top-level field ("$schema" is allowed) [error when strict]
	  error    effect.internal         the validator itself failed on this part of the input (reported, not thrown)

	  Components
	  error    component.limit         more than MAX_COMPONENTS components
	  error    component.invalid       entry is not an object
	  error    component.id            id missing or not [A-Za-z0-9_-]{1,64}
	  error    component.duplicate_id  id already used by an earlier component (the first one keeps it)
	  error    component.name          name missing, empty, not a string or too long
	  error    component.type          type missing or not a registered component type
	  error    component.parent        parent is not a string
	  error    component.parent_self   parent is the component itself
	  error    component.parent_missing parent id does not exist
	  error    component.parent_type   parent's type cannot be a parent (descriptor.canParent = false)
	  error    component.parent_cycle  the parent chain forms a cycle (reported once, on its first member)
	  info     component.disabled_ancestor component is enabled but an ancestor is disabled (it is not built)
	  error    component.enabled       enabled is not a boolean
	  error    component.start_time    startTime not a finite number >= 0
	  error    component.duration      duration not a finite number > 0
	  warning  component.timing        span starts at/after the effect end (never plays) or ends after it (cut off)
	  error    component.phase         phase is not one of Constants.PHASES
	  error    component.min_quality   minQuality is not Low / Medium / High
	  error    component.transform     transform is not an object, or position / rotation / scale has a bad value
	  error    component.notes         notes is not a string
	  error    component.properties    properties is not an object
	  error    component.tracks        tracks is not an array
	  error    component.events        events is not an array
	  warning  component.unknown_field unknown field on a component or its transform [error when strict]

	  Properties (also used for qualityOverrides values)
	  warning  property.unknown        property not declared by the component type [error when strict]
	  error    property.type           value has the wrong JSON form (Codec.check; easing strings: Easing.check)
	  error    property.range          value outside min/max, not in the enum list, or too many sequence keypoints
	  error    property.ref            "$key" colour not in the palette, or componentRef to a missing / wrong-type
	                                   component

	  Tracks and keyframes
	  error    track.limit             more than MAX_TRACKS_PER_COMPONENT tracks
	  error    track.invalid           entry is not an object
	  error    track.id                id missing or invalid
	  error    track.duplicate_id      id already used by another track of the same component
	  error    track.channel           channel missing or not declared by the component type
	  error    track.duplicate_channel two enabled tracks animate the same channel
	  error    track.enabled           enabled is not a boolean
	  error    track.keyframes         keyframes missing, not an array or empty
	  warning  track.unknown_field     unknown track field [error when strict]
	  error    keyframe.limit          more than MAX_KEYFRAMES_PER_TRACK keyframes
	  error    keyframe.invalid        entry is not an object
	  error    keyframe.time           time missing, not finite or negative
	  error    keyframe.value          value missing, wrong kind for the channel or outside the channel range
	  error    keyframe.ref            "$key" colour not in the palette
	  error    keyframe.easing         easing is not a valid Easing definition
	  warning  keyframe.order          keyframes are not sorted by time (the compiler sorts them, stable)
	  warning  keyframe.unknown_field  unknown keyframe field [error when strict]

	  Events (relative to the component start)
	  error    event.limit             more than MAX_EVENTS_PER_COMPONENT events
	  error    event.invalid           entry is not an object
	  error    event.id                id missing or invalid
	  error    event.duplicate_id      id already used by another event of the same component
	  error    event.time              time missing, not finite or negative
	  error    event.action            action missing or not supported by the component type ("fire" is accepted on
	                                   every type: it forwards `name` to game code)
	  error    event.count             [error] count missing or not a whole number in 1..MAX_EMIT_COUNT for actions
	                                   that use it; [warning] count given but ignored by the action
	  error    event.name              [error] name missing or not an event name for "fire"; [warning] name ignored
	  warning  event.unknown_field     unknown event field [error when strict]

	  Markers (absolute time)
	  error    marker.limit            more than MAX_MARKERS markers
	  error    marker.type             markers is not an array
	  error    marker.invalid          entry is not an object
	  error    marker.id               id missing or invalid
	  error    marker.duplicate_id     id already used by an earlier marker
	  error    marker.time             [error] time missing, not finite or negative; [warning] after the effect end
	  error    marker.label            label missing, not a string or too long
	  error    marker.phase            phase is not one of Constants.PHASES
	  error    marker.event            event is not a string matching Constants.EVENT_NAME_PATTERN ("" = no event)
	  error    marker.color            color is not a colour, or "$key" not in the palette
	  warning  marker.unknown_field    unknown marker field [error when strict]

	  Quality (effect `quality` map and component `qualityOverrides`)
	  error    quality.type            quality / qualityOverrides (or one level entry of it) is not an object
	  error    quality.level           key is not Low / Medium / High
	  error    quality.value           profile override value invalid (countScale, segmentScale: finite >= 0;
	                                   sizeCompensation: finite > 0; lightShadows: boolean; maxLights: whole >= 0)
	  warning  quality.field           unknown profile override field [error when strict]

	  Graph: every graph.* code of Graph.validate (see Core/Graph/Validator.luau), passed through unchanged.

	  Lints (warnings; skipped for disabled components)
	  warning  lint.trail_static       trail without a movement source: no position/rotation track (>= 2 keys), no
	                                   spin and no graph Tween/SetProperty of position/rotation on the trail or any
	                                   ancestor (it only draws when the effect is attached to something moving)
	  warning  lint.particles_silent   particles with rate 0, burst 0, no rate track / quality override above 0, no
	                                   emit event and no graph Emit (or rate tween) targeting it: it never emits
	  warning  lint.zero_width         beam with width0 = width1 = 0 and no width track / tween above 0 (invisible)
	  warning  lint.outside_duration   keyframes after the component's span end (never reached) or events at/after
	                                   it (dropped by the schedule); one diagnostic per track, one per event
	  warning  lint.flash_short        flash span shorter than attack + hold + decay (the envelope is cut off)
	  warning  lint.filemesh_no_id     mesh with meshType "FileMesh" but an empty meshId (renders nothing)

	Interpretation notes (where the contract leaves room):
	* Json sentinels: Json.NULL is reported as "null" wherever a value is expected; Json.EMPTY_OBJECT and plain
	  empty tables are both empty arrays and empty objects.
	* Effective property values for lints are the authored value (when valid) or the spec default; a lint is
	  skipped when a value it needs is invalid (that error is reported already).
	* Graph scans for lints are conservative: an Emit / Tween / SetProperty whose target comes from a link other
	  than a Component node counts as targeting every component.
	* Spans use Timeline.span; timing lints and warnings are skipped while the effect duration or the component's
	  own timing fields are invalid.
	* String properties whose name ends in "Easing" (shockwave expandEasing / fadeEasing) are easing definitions
	  and are checked with Easing.check.
]]

local Codec = require(script.Parent.Codec)
local Components = require(script.Parent.Components)
local Constants = require(script.Parent.Constants)
local Easing = require(script.Parent.Easing)
local Graph = require(script.Parent.Graph)
local Json = require(script.Parent.Json)
local Timeline = require(script.Parent.Timeline)
local Types = require(script.Parent.Types)

type Diagnostic = Types.Diagnostic
type Severity = Types.Severity
type ValidationResult = Types.ValidationResult
type ComponentDescriptor = Types.ComponentDescriptor
type PropertySpec = Types.PropertySpec
type ChannelSpec = Types.ChannelSpec

export type Options = {
	strict: boolean?, -- unknown fields / properties are errors instead of warnings
}

export type CodeInfo = {
	code: string,
	severity: Severity, -- the usual severity (some codes are also used with a lower one, see the table above)
	summary: string,
}

local Validation = {}

local function code(c: string, severity: Severity, summary: string): CodeInfo
	return table.freeze({ code = c, severity = severity, summary = summary })
end

-- Machine-readable version of the code table above (docs generator, editor help).
Validation.CODES = table.freeze({
	code("effect.type", "error", "The definition is not an object."),
	code("effect.schema_version", "error", "schemaVersion missing or not the current schema version."),
	code("effect.id", "error", "Effect id missing or invalid."),
	code("effect.name", "error", "Effect name missing, empty or too long."),
	code("effect.duration", "error", "Effect duration missing or outside (0, MAX_DURATION]."),
	code("effect.description", "error", "description is not a string."),
	code("effect.tags", "error", "tags is not an array of strings."),
	code("effect.loop", "error", "loop is not a boolean."),
	code("effect.seed", "error", "seed is not a whole number."),
	code("effect.time_scale", "error", "timeScale outside (0, MAX_TIME_SCALE]."),
	code("effect.palette", "error", "Invalid palette, palette key or palette colour."),
	code("effect.metadata", "error", "metadata is not an object of plain JSON values."),
	code("effect.components", "error", "components missing or not an array."),
	code("effect.empty", "warning", "The effect has no components."),
	code("effect.unknown_field", "warning", "Unknown top-level field (error when strict)."),
	code("effect.internal", "error", "The validator failed on this part of the input."),
	code("component.limit", "error", "Too many components."),
	code("component.invalid", "error", "Component entry is not an object."),
	code("component.id", "error", "Component id missing or invalid."),
	code("component.duplicate_id", "error", "Component id used twice."),
	code("component.name", "error", "Component name missing, empty or too long."),
	code("component.type", "error", "Component type missing or unknown."),
	code("component.parent", "error", "parent is not a string."),
	code("component.parent_self", "error", "Component is its own parent."),
	code("component.parent_missing", "error", "Parent component does not exist."),
	code("component.parent_type", "error", "Parent component type cannot have children."),
	code("component.parent_cycle", "error", "The parent chain forms a cycle."),
	code("component.disabled_ancestor", "info", "An ancestor is disabled, so this component is not built."),
	code("component.enabled", "error", "enabled is not a boolean."),
	code("component.start_time", "error", "startTime is not a finite number >= 0."),
	code("component.duration", "error", "duration is not a finite number > 0."),
	code("component.timing", "warning", "Span starts after the effect end or is cut off by it."),
	code("component.phase", "error", "phase is not a known phase."),
	code("component.min_quality", "error", "minQuality is not Low, Medium or High."),
	code("component.transform", "error", "Invalid transform."),
	code("component.notes", "error", "notes is not a string."),
	code("component.properties", "error", "properties is not an object."),
	code("component.tracks", "error", "tracks is not an array."),
	code("component.events", "error", "events is not an array."),
	code("component.unknown_field", "warning", "Unknown component field (error when strict)."),
	code("property.unknown", "warning", "Property not declared by the component type (error when strict)."),
	code("property.type", "error", "Property value has the wrong form."),
	code("property.range", "error", "Property value outside its range, enum or keypoint limit."),
	code("property.ref", "error", "Palette or component reference does not resolve."),
	code("track.limit", "error", "Too many tracks on one component."),
	code("track.invalid", "error", "Track entry is not an object."),
	code("track.id", "error", "Track id missing or invalid."),
	code("track.duplicate_id", "error", "Track id used twice in one component."),
	code("track.channel", "error", "Channel missing or not declared by the component type."),
	code("track.duplicate_channel", "error", "Two enabled tracks animate the same channel."),
	code("track.enabled", "error", "enabled is not a boolean."),
	code("track.keyframes", "error", "keyframes missing, not an array or empty."),
	code("track.unknown_field", "warning", "Unknown track field (error when strict)."),
	code("keyframe.limit", "error", "Too many keyframes in one track."),
	code("keyframe.invalid", "error", "Keyframe entry is not an object."),
	code("keyframe.time", "error", "Keyframe time missing, not finite or negative."),
	code("keyframe.value", "error", "Keyframe value missing, of the wrong kind or out of range."),
	code("keyframe.ref", "error", "Keyframe colour references a missing palette key."),
	code("keyframe.easing", "error", "Invalid easing definition."),
	code("keyframe.order", "warning", "Keyframes are not sorted by time."),
	code("keyframe.unknown_field", "warning", "Unknown keyframe field (error when strict)."),
	code("event.limit", "error", "Too many events on one component."),
	code("event.invalid", "error", "Event entry is not an object."),
	code("event.id", "error", "Event id missing or invalid."),
	code("event.duplicate_id", "error", "Event id used twice in one component."),
	code("event.time", "error", "Event time missing, not finite or negative."),
	code("event.action", "error", "Event action missing or not supported by the component type."),
	code("event.count", "error", "Event count missing or invalid (warning when ignored)."),
	code("event.name", "error", "Event name missing or invalid (warning when ignored)."),
	code("event.unknown_field", "warning", "Unknown event field (error when strict)."),
	code("marker.limit", "error", "Too many markers."),
	code("marker.type", "error", "markers is not an array."),
	code("marker.invalid", "error", "Marker entry is not an object."),
	code("marker.id", "error", "Marker id missing or invalid."),
	code("marker.duplicate_id", "error", "Marker id used twice."),
	code("marker.time", "error", "Marker time invalid (warning when after the effect end)."),
	code("marker.label", "error", "Marker label missing, not a string or too long."),
	code("marker.phase", "error", "Marker phase is not a known phase."),
	code("marker.event", "error", "Marker event is not a valid event name."),
	code("marker.color", "error", "Marker colour invalid or not in the palette."),
	code("marker.unknown_field", "warning", "Unknown marker field (error when strict)."),
	code("quality.type", "error", "quality / qualityOverrides (or a level entry) is not an object."),
	code("quality.level", "error", "Key is not Low, Medium or High."),
	code("quality.value", "error", "Invalid quality profile override value."),
	code("quality.field", "warning", "Unknown quality profile override field (error when strict)."),
	code("graph.*", "error", "Node graph diagnostics from Graph.validate (see Graph/Validator.luau)."),
	code("lint.trail_static", "warning", "Trail has no movement source."),
	code("lint.particles_silent", "warning", "Particles never emit."),
	code("lint.zero_width", "warning", "Beam has zero width at both ends."),
	code("lint.outside_duration", "warning", "Keyframes or events beyond the component span."),
	code("lint.flash_short", "warning", "Flash span shorter than attack + hold + decay."),
	code("lint.filemesh_no_id", "warning", "FileMesh without a meshId."),
})

-- ─────────────────────────────────────────────────────────────────────────────
-- Constants and small helpers
-- ─────────────────────────────────────────────────────────────────────────────

local NULL: any = Json.NULL
local EMPTY_OBJECT: any = Json.EMPTY_OBJECT
local INF = math.huge
local EPSILON = 1e-9
local MAX_SAFE_INTEGER = 2 ^ 53
local IDENTIFIER = "^[A-Za-z_][A-Za-z0-9_]*$"

local function toSet(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, v in list do
		set[v] = true
	end
	return set
end

local EFFECT_FIELDS = {
	"$schema",
	"schemaVersion",
	"id",
	"name",
	"description",
	"tags",
	"duration",
	"loop",
	"seed",
	"timeScale",
	"palette",
	"markers",
	"components",
	"graph",
	"quality",
	"metadata",
}
local COMPONENT_FIELDS = {
	"id",
	"name",
	"type",
	"parent",
	"enabled",
	"startTime",
	"duration",
	"phase",
	"minQuality",
	"transform",
	"properties",
	"tracks",
	"events",
	"qualityOverrides",
	"notes",
}
local TRANSFORM_FIELDS = { "position", "rotation", "scale" }
local TRACK_FIELDS = { "id", "channel", "keyframes", "enabled" }
local KEYFRAME_FIELDS = { "time", "value", "easing" }
local EVENT_FIELDS = { "id", "time", "action", "count", "name" }
local MARKER_FIELDS = { "id", "time", "label", "phase", "event", "color" }
local QUALITY_FIELDS = { "countScale", "segmentScale", "sizeCompensation", "lightShadows", "maxLights" }

local SETS = {
	effect = toSet(EFFECT_FIELDS),
	component = toSet(COMPONENT_FIELDS),
	transform = toSet(TRANSFORM_FIELDS),
	track = toSet(TRACK_FIELDS),
	keyframe = toSet(KEYFRAME_FIELDS),
	event = toSet(EVENT_FIELDS),
	marker = toSet(MARKER_FIELDS),
	quality = toSet(QUALITY_FIELDS),
}
local PHASE_SET = toSet(Constants.PHASES)
local LEVEL_SET = toSet(Constants.QUALITY_LEVELS)

-- Legacy (pre-release concept format) property keys: hint at Migration instead of a generic "unknown".
local LEGACY_HINTS: { [string]: string } = {
	initialScale = "legacy concept-format key; Migration.migrate turns initialScale/finalScale into a scale track",
	finalScale = "legacy concept-format key; Migration.migrate turns initialScale/finalScale into a scale track",
}

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

-- Length of a plain array (keys exactly 1..n; tables without keys are empty arrays), or nil.
local function arrayLength(v: any): number?
	if type(v) ~= "table" or rawequal(v, NULL) then
		return nil
	end
	local n, maxIndex = 0, 0
	for k in pairs(v) do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return nil
		end
		n += 1
		if k > maxIndex then
			maxIndex = k
		end
	end
	if n ~= maxIndex then
		return nil
	end
	return n
end

-- True for a table (not Json.NULL) whose keys are all strings (empty tables included).
local function isObject(v: any): boolean
	if type(v) ~= "table" or rawequal(v, NULL) then
		return false
	end
	for k in pairs(v) do
		if type(k) ~= "string" then
			return false
		end
	end
	return true
end

local function sortedKeys(t: { [any]: any }): { string }
	local keys: { string } = {}
	for k in pairs(t) do
		if type(k) == "string" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	return keys
end

local function num(n: number): string
	if n ~= n then
		return "NaN"
	elseif n == INF then
		return "inf"
	elseif n == -INF then
		return "-inf"
	elseif n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	local s = string.format("%.6f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

local function quote(s: string): string
	local ok, encoded = pcall(Json.encode, s)
	if ok and type(encoded) == "string" then
		return encoded
	end
	return string.format("%q", s)
end

local function describe(v: any): string
	if v == nil then
		return "nothing"
	elseif rawequal(v, NULL) then
		return "null"
	end
	local t = typeof(v)
	if t == "number" then
		return num(v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		if #v > 40 then
			return quote(string.sub(v, 1, 37) .. "...")
		end
		return quote(v)
	elseif t == "table" then
		if rawequal(v, EMPTY_OBJECT) then
			return "an empty object"
		end
		local n = arrayLength(v)
		if n == 0 then
			return "an empty table"
		elseif n == 1 then
			return "an array of 1 item"
		elseif n then
			return "an array of " .. n .. " items"
		end
		return if isObject(v) then "an object" else "a table with non-string keys"
	end
	return "a " .. t .. " value"
end

-- Path helpers ("components[2].properties.rate", 'palette["my key"]').
local function field(base: string, key: string): string
	if string.match(key, IDENTIFIER) then
		return if base == "" then key else base .. "." .. key
	end
	return base .. "[" .. quote(key) .. "]"
end

local function item(base: string, i: number): string
	return base .. "[" .. i .. "]"
end

local function isId(v: any): boolean
	return type(v) == "string"
		and #v >= 1
		and #v <= Constants.ID_MAX_LENGTH
		and string.match(v, Constants.ID_PATTERN) ~= nil
end

local function isEventName(v: any): boolean
	return type(v) == "string"
		and #v >= 1
		and #v <= Constants.ID_MAX_LENGTH
		and string.match(v, Constants.EVENT_NAME_PATTERN) ~= nil
end

local ID_RULE = "1-" .. Constants.ID_MAX_LENGTH .. " characters of A-Z a-z 0-9 _ -"

-- Case-insensitive "did you mean" from a candidate list.
local function suggest(name: any, candidates: { string }): string?
	if type(name) ~= "string" then
		return nil
	end
	local lower = string.lower(name)
	for _, candidate in candidates do
		if string.lower(candidate) == lower and candidate ~= name then
			return 'did you mean "' .. candidate .. '"?'
		end
	end
	return nil
end

-- tostring() that cannot fail (error objects may carry a throwing __tostring).
local function safeText(v: any): string
	local ok, text = pcall(tostring, v)
	return if ok and type(text) == "string" then text else "unknown error"
end

-- Codec.check / Easing.check / Codec.normalize behind pcall: a programmer error inside them must not escape.
local function check(kind: string, value: any, spec: any): (boolean, string?, string?)
	local ok, valid, message, problem = pcall(Codec.check :: any, kind, value, spec)
	if not ok then
		return false, "invalid value (" .. safeText(valid) .. ")", "type"
	end
	return valid == true, message, problem
end

local function checkEasing(def: any): (boolean, string?)
	local ok, valid, message = pcall(Easing.check :: any, def)
	if not ok then
		return false, "invalid easing (" .. safeText(valid) .. ")"
	end
	return valid == true, message
end

local function normalize(kind: string, value: any, spec: any): any
	local ok, result = pcall(Codec.normalize :: any, kind, value, spec)
	return if ok then result else nil
end

local function paletteRefs(kind: string, value: any): { string }
	local ok, refs = pcall(Codec.paletteRefs :: any, kind, value)
	return if ok and type(refs) == "table" then refs else {}
end

-- Problem (with relative sub-path) when `v` is not plain JSON data; nil when it is.
local function jsonProblem(v: any, path: string, depth: number, stack: { [any]: boolean }): (string?, string?)
	local t = type(v)
	if t == "string" then
		if utf8.len(v) == nil then
			return path, "contains a string that is not valid UTF-8"
		end
		return nil, nil
	elseif t == "number" then
		if not isFinite(v) then
			return path, "contains the number " .. num(v) .. " (JSON numbers must be finite)"
		end
		return nil, nil
	elseif t == "boolean" then
		return nil, nil
	elseif t ~= "table" then
		return path, "contains " .. describe(v)
	end
	if rawequal(v, NULL) or rawequal(v, EMPTY_OBJECT) then
		return nil, nil
	end
	if stack[v] then
		return path, "contains a cycle"
	end
	if depth > Json.MAX_DEPTH then
		return path, "is nested deeper than " .. Json.MAX_DEPTH .. " levels"
	end
	local n = arrayLength(v)
	if n == nil and not isObject(v) then
		return path, "contains a table that is neither an array nor an object with string keys"
	end
	stack[v] = true
	if n then
		for i = 1, n do
			local p, message = jsonProblem(v[i], item(path, i), depth + 1, stack)
			if p then
				stack[v] = nil
				return p, message
			end
		end
	else
		for _, key in sortedKeys(v) do
			local p, message = jsonProblem(v[key], field(path, key), depth + 1, stack)
			if p then
				stack[v] = nil
				return p, message
			end
		end
	end
	stack[v] = nil
	return nil, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────────────────────

type TrackInfo = {
	channel: string,
	keys: { { time: number?, value: any } }, -- valid keyframes (time nil when invalid); value nil when invalid
}

type Info = {
	index: number,
	path: string,
	raw: { [string]: any },
	id: string?, -- valid id (also for duplicates)
	typeName: string?,
	descriptor: ComponentDescriptor?,
	parent: any,
	enabled: boolean,
	values: { [string]: any }, -- canonical values of valid properties
	invalid: { [string]: boolean }, -- properties with invalid values
	tracks: { [string]: { TrackInfo } }, -- enabled tracks with a known channel, by channel
	emitEvents: number,
	overrideEmits: boolean, -- a qualityOverrides entry sets rate or burst above 0
	spanLength: number?, -- clamped span length, nil when unknown
	timingValid: boolean,
}

type GraphScan = {
	dynamicEmit: boolean,
	emits: { [string]: boolean },
	dynamicChannels: { [string]: boolean },
	channels: { [string]: { [string]: boolean } },
}

type Ctx = {
	result: ValidationResult,
	strict: boolean,
	unknownSeverity: Severity,
	def: { [string]: any },
	duration: number?,
	palette: { [string]: boolean },
	list: { Info },
	byId: { [string]: Info },
	graph: GraphScan,
}

local function add(
	ctx: Ctx,
	severity: Severity,
	c: string,
	path: string,
	message: string,
	hint: string?,
	componentId: string?
)
	local d: Diagnostic = {
		severity = severity,
		code = c,
		path = path,
		message = message,
		hint = hint,
		componentId = componentId,
	}
	if severity == "error" then
		table.insert(ctx.result.errors, d)
	elseif severity == "warning" then
		table.insert(ctx.result.warnings, d)
	else
		table.insert(ctx.result.infos, d)
	end
end

-- Runs fn(...) in pcall; an internal failure becomes an effect.internal error at `path` instead of a throw.
local function guard(ctx: Ctx, path: string, fn: any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		add(ctx, "error", "effect.internal", path, "the validator failed here: " .. safeText(err))
	end
end

-- Reports keys of `t` that are not in `allowed` (sorted).
local function unknownFields(
	ctx: Ctx,
	t: { [string]: any },
	allowed: { [string]: boolean },
	candidates: { string },
	path: string,
	c: string,
	what: string,
	componentId: string?
)
	for _, key in sortedKeys(t) do
		if not allowed[key] then
			add(
				ctx,
				ctx.unknownSeverity,
				c,
				field(path, key),
				what .. " has no field " .. quote(key),
				suggest(key, candidates),
				componentId
			)
		end
	end
end

-- Palette references of a colour value: one `c` diagnostic per missing key.
local function checkRefs(ctx: Ctx, kind: string, value: any, path: string, c: string, componentId: string?): boolean
	local ok = true
	for _, key in paletteRefs(kind, value) do
		if not ctx.palette[key] then
			ok = false
			add(
				ctx,
				"error",
				c,
				path,
				'palette colour "$' .. key .. '" does not exist',
				'add it to the effect palette or use a "#RRGGBB" colour',
				componentId
			)
		end
	end
	return ok
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Effect fields
-- ─────────────────────────────────────────────────────────────────────────────

local function checkName(v: any): string?
	if type(v) ~= "string" then
		return "must be a string, got " .. describe(v)
	end
	local length = utf8.len(v)
	if length == nil then
		return "must be valid UTF-8"
	elseif string.match(v, "^%s*$") then
		return "must not be empty"
	elseif length > Constants.NAME_MAX_LENGTH then
		return "must be at most " .. Constants.NAME_MAX_LENGTH .. " characters, got " .. length
	end
	return nil
end

local function validateEffectFields(ctx: Ctx)
	local def = ctx.def
	unknownFields(ctx, def, SETS.effect, EFFECT_FIELDS, "", "effect.unknown_field", "the effect")

	local version = def.schemaVersion
	if version == nil then
		add(
			ctx,
			"error",
			"effect.schema_version",
			"schemaVersion",
			"schemaVersion is missing",
			"run Migration.migrate first; the current version is " .. Constants.SCHEMA_VERSION
		)
	elseif version ~= Constants.SCHEMA_VERSION then
		local hint = if isFinite(version) and version > Constants.SCHEMA_VERSION
			then "this runtime supports schema version " .. Constants.SCHEMA_VERSION .. "; update ASTRA VFX"
			else "run Migration.migrate first"
		add(
			ctx,
			"error",
			"effect.schema_version",
			"schemaVersion",
			"schemaVersion must be " .. Constants.SCHEMA_VERSION .. ", got " .. describe(version),
			hint
		)
	end

	if not isId(def.id) then
		add(
			ctx,
			"error",
			"effect.id",
			"id",
			"effect id must be " .. ID_RULE .. ", got " .. describe(def.id),
			if type(def.id) == "string" then 'use a slug such as "violet-impact"' else nil
		)
	end

	local nameProblem = checkName(def.name)
	if nameProblem then
		add(ctx, "error", "effect.name", "name", "effect name " .. nameProblem)
	end

	local duration = def.duration
	if not isFinite(duration) or duration <= 0 or duration > Constants.MAX_DURATION then
		add(
			ctx,
			"error",
			"effect.duration",
			"duration",
			"duration must be a number of seconds in (0, " .. Constants.MAX_DURATION .. "], got " .. describe(duration)
		)
	else
		ctx.duration = duration
	end

	if def.description ~= nil and type(def.description) ~= "string" then
		add(
			ctx,
			"error",
			"effect.description",
			"description",
			"description must be a string, got " .. describe(def.description)
		)
	end

	local tags = def.tags
	if tags ~= nil then
		local n = arrayLength(tags)
		if n == nil then
			add(ctx, "error", "effect.tags", "tags", "tags must be an array of strings, got " .. describe(tags))
		else
			for i = 1, n do
				if type(tags[i]) ~= "string" then
					add(ctx, "error", "effect.tags", item("tags", i), "tag must be a string, got " .. describe(tags[i]))
				end
			end
		end
	end

	if def.loop ~= nil and type(def.loop) ~= "boolean" then
		add(ctx, "error", "effect.loop", "loop", "loop must be true or false, got " .. describe(def.loop))
	end

	local seed = def.seed
	if seed ~= nil and (not isFinite(seed) or seed % 1 ~= 0 or math.abs(seed) > MAX_SAFE_INTEGER) then
		add(ctx, "error", "effect.seed", "seed", "seed must be a whole number, got " .. describe(seed))
	end

	local timeScale = def.timeScale
	if timeScale ~= nil and (not isFinite(timeScale) or timeScale <= 0 or timeScale > Constants.MAX_TIME_SCALE) then
		add(
			ctx,
			"error",
			"effect.time_scale",
			"timeScale",
			"timeScale must be a number in (0, " .. Constants.MAX_TIME_SCALE .. "], got " .. describe(timeScale)
		)
	end

	local metadata = def.metadata
	if metadata ~= nil then
		if not isObject(metadata) then
			add(ctx, "error", "effect.metadata", "metadata", "metadata must be an object, got " .. describe(metadata))
		else
			local p, message = jsonProblem(metadata, "metadata", 1, {})
			if p and message then
				add(ctx, "error", "effect.metadata", p, "metadata " .. message, "metadata must be plain JSON data")
			end
		end
	end
end

local function validatePalette(ctx: Ctx)
	local palette = ctx.def.palette
	if palette == nil then
		return
	end
	if not isObject(palette) then
		add(
			ctx,
			"error",
			"effect.palette",
			"palette",
			"palette must be an object of name -> colour, got " .. describe(palette)
		)
		return
	end
	for _, key in sortedKeys(palette) do
		ctx.palette[key] = true
		local path = field("palette", key)
		if not isId(key) then
			add(ctx, "error", "effect.palette", path, "palette key " .. quote(key) .. " must be " .. ID_RULE)
		end
		local value = palette[key]
		if type(value) == "string" and string.sub(value, 1, 1) == "$" then
			add(ctx, "error", "effect.palette", path, "palette colours cannot reference other palette colours")
		else
			local ok, message = check("color3", value, nil)
			if not ok then
				add(ctx, "error", "effect.palette", path, "palette colour " .. tostring(message), 'use "#RRGGBB"')
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Markers
-- ─────────────────────────────────────────────────────────────────────────────

local function validateMarkers(ctx: Ctx)
	local markers = ctx.def.markers
	if markers == nil then
		return
	end
	local n = arrayLength(markers)
	if n == nil then
		add(ctx, "error", "marker.type", "markers", "markers must be an array, got " .. describe(markers))
		return
	end
	if n > Constants.MAX_MARKERS then
		add(
			ctx,
			"error",
			"marker.limit",
			"markers",
			"an effect can have at most " .. Constants.MAX_MARKERS .. " markers, got " .. n
		)
	end
	local seen: { [string]: number } = {}
	for i = 1, n do
		local marker = markers[i]
		local path = item("markers", i)
		if not isObject(marker) then
			add(ctx, "error", "marker.invalid", path, "marker must be an object, got " .. describe(marker))
			continue
		end
		unknownFields(ctx, marker, SETS.marker, MARKER_FIELDS, path, "marker.unknown_field", "a marker")
		local id = marker.id
		if not isId(id) then
			add(
				ctx,
				"error",
				"marker.id",
				field(path, "id"),
				"marker id must be " .. ID_RULE .. ", got " .. describe(id)
			)
		elseif seen[id] then
			add(
				ctx,
				"error",
				"marker.duplicate_id",
				field(path, "id"),
				"marker id " .. quote(id) .. " is already used by markers[" .. seen[id] .. "]"
			)
		else
			seen[id] = i
		end
		local t = marker.time
		if not isFinite(t) or t < 0 then
			add(
				ctx,
				"error",
				"marker.time",
				field(path, "time"),
				"marker time must be a number of seconds >= 0, got " .. describe(t)
			)
		elseif ctx.duration and t > (ctx.duration :: number) + EPSILON then
			add(
				ctx,
				"warning",
				"marker.time",
				field(path, "time"),
				"marker at " .. num(t) .. " s lies after the effect end (" .. num(ctx.duration :: number) .. " s)",
				"markers after the end never fire"
			)
		end
		local labelProblem = checkName(marker.label)
		if labelProblem then
			add(ctx, "error", "marker.label", field(path, "label"), "marker label " .. labelProblem)
		end
		if marker.phase ~= nil and not PHASE_SET[marker.phase] then
			add(
				ctx,
				"error",
				"marker.phase",
				field(path, "phase"),
				"phase must be one of " .. table.concat(Constants.PHASES, ", ") .. ", got " .. describe(marker.phase),
				suggest(marker.phase, Constants.PHASES)
			)
		end
		local event = marker.event
		if event ~= nil and not (event == "" or isEventName(event)) then
			add(
				ctx,
				"error",
				"marker.event",
				field(path, "event"),
				"marker event must be an event name ([A-Za-z_][A-Za-z0-9_-]*, at most "
					.. Constants.ID_MAX_LENGTH
					.. " characters), got "
					.. describe(event)
			)
		end
		if marker.color ~= nil then
			local ok, message = check("color3", marker.color, nil)
			if not ok then
				add(ctx, "error", "marker.color", field(path, "color"), "marker colour " .. tostring(message))
			else
				checkRefs(ctx, "color3", marker.color, field(path, "color"), "marker.color", nil)
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Components
-- ─────────────────────────────────────────────────────────────────────────────

local function propertyNames(descriptor: ComponentDescriptor): { string }
	local out = {}
	for _, spec in descriptor.properties do
		table.insert(out, spec.name)
	end
	return out
end

local function channelNames(descriptor: ComponentDescriptor): { string }
	local out = {}
	for _, spec in descriptor.channels do
		table.insert(out, spec.name)
	end
	return out
end

local function actionNames(descriptor: ComponentDescriptor): { string }
	local out = {}
	for _, spec in descriptor.events do
		table.insert(out, spec.action)
	end
	table.insert(out, "fire")
	return out
end

-- Checks one property value against its spec. Returns the canonical value when valid.
local function checkPropertyValue(
	ctx: Ctx,
	spec: PropertySpec,
	value: any,
	path: string,
	componentId: string?
): (boolean, any)
	local ok, message, problem = check(spec.kind, value, spec)
	if not ok then
		local c = if problem == "range" then "property.range" else "property.type"
		add(ctx, "error", c, path, spec.name .. ": " .. tostring(message), nil, componentId)
		return false, nil
	end
	if spec.kind == "string" and string.match(spec.name, "Easing$") then
		local easingOk, easingMessage = checkEasing(value)
		if not easingOk then
			add(ctx, "error", "property.type", path, spec.name .. ": " .. tostring(easingMessage), nil, componentId)
			return false, nil
		end
	end
	if spec.kind == "color3" or spec.kind == "colorSequence" then
		if not checkRefs(ctx, spec.kind, value, path, "property.ref", componentId) then
			return false, nil
		end
	elseif spec.kind == "componentRef" and value ~= "" then
		local target = ctx.byId[value]
		if target == nil then
			add(
				ctx,
				"error",
				"property.ref",
				path,
				spec.name .. ': component "' .. tostring(value) .. '" does not exist',
				nil,
				componentId
			)
			return false, nil
		end
		local allowed = spec.componentTypes
		if allowed and not table.find(allowed, target.typeName or "") then
			add(
				ctx,
				"error",
				"property.ref",
				path,
				spec.name
					.. ': component "'
					.. tostring(value)
					.. '" is a '
					.. tostring(target.typeName)
					.. ", expected "
					.. table.concat(allowed, " or "),
				nil,
				componentId
			)
			return false, nil
		end
	end
	return true, normalize(spec.kind, value, spec)
end

local function validateProperties(ctx: Ctx, info: Info, descriptor: ComponentDescriptor, componentId: string?)
	local properties = info.raw.properties
	if properties == nil then
		return
	end
	local path = field(info.path, "properties")
	if not isObject(properties) then
		add(
			ctx,
			"error",
			"component.properties",
			path,
			"properties must be an object, got " .. describe(properties),
			nil,
			componentId
		)
		return
	end
	local typeName = descriptor.type
	for _, key in sortedKeys(properties) do
		local spec = Components.propertySpec(typeName, key)
		local p = field(path, key)
		if spec == nil then
			local hint = LEGACY_HINTS[key] or suggest(key, propertyNames(descriptor))
			if hint == nil and key == "color" and Components.propertySpec(typeName, "coreColor") then
				hint = "this type uses coreColor / shellColor"
			end
			add(
				ctx,
				ctx.unknownSeverity,
				"property.unknown",
				p,
				typeName .. " has no property " .. quote(key),
				hint,
				componentId
			)
			info.invalid[key] = true
		else
			local ok, canonical = checkPropertyValue(ctx, spec, properties[key], p, componentId)
			if ok then
				info.values[key] = canonical
			else
				info.invalid[key] = true
			end
		end
	end
end

local function validateTransform(ctx: Ctx, info: Info, componentId: string?)
	local transform = info.raw.transform
	if transform == nil then
		return
	end
	local path = field(info.path, "transform")
	if not isObject(transform) then
		add(
			ctx,
			"error",
			"component.transform",
			path,
			"transform must be an object, got " .. describe(transform),
			nil,
			componentId
		)
		return
	end
	unknownFields(
		ctx,
		transform,
		SETS.transform,
		TRANSFORM_FIELDS,
		path,
		"component.unknown_field",
		"transform",
		componentId
	)
	for _, key in { "position", "rotation" } do
		local v = transform[key]
		if v ~= nil then
			local ok, message = check("vector3", v, nil)
			if not ok then
				add(
					ctx,
					"error",
					"component.transform",
					field(path, key),
					key .. ": " .. tostring(message),
					nil,
					componentId
				)
			end
		end
	end
	local scale = transform.scale
	if scale ~= nil then
		local ok, message = check("number", scale, { min = 0 })
		if not ok then
			add(
				ctx,
				"error",
				"component.transform",
				field(path, "scale"),
				"scale: " .. tostring(message),
				nil,
				componentId
			)
		end
	end
end

local function validateKeyframes(
	ctx: Ctx,
	info: Info,
	track: { [string]: any },
	trackPath: string,
	channel: ChannelSpec?,
	trackInfo: TrackInfo?,
	componentId: string?,
	lint: boolean
)
	local keyframes = track.keyframes
	local path = field(trackPath, "keyframes")
	local n = arrayLength(keyframes)
	if n == nil or n == 0 then
		add(
			ctx,
			"error",
			"track.keyframes",
			path,
			"keyframes must be a non-empty array, got " .. describe(keyframes),
			nil,
			componentId
		)
		return
	end
	if n > Constants.MAX_KEYFRAMES_PER_TRACK then
		add(
			ctx,
			"error",
			"keyframe.limit",
			path,
			"a track can have at most " .. Constants.MAX_KEYFRAMES_PER_TRACK .. " keyframes, got " .. n,
			nil,
			componentId
		)
	end
	local previous = -INF
	local orderReported = false
	local outside = 0
	local firstOutside: string? = nil
	local spanLength = info.spanLength
	for i = 1, n do
		local key = keyframes[i]
		local p = item(path, i)
		if not isObject(key) then
			add(
				ctx,
				"error",
				"keyframe.invalid",
				p,
				"keyframe must be an object, got " .. describe(key),
				nil,
				componentId
			)
			continue
		end
		unknownFields(ctx, key, SETS.keyframe, KEYFRAME_FIELDS, p, "keyframe.unknown_field", "a keyframe", componentId)
		local t = key.time
		local timeOk = isFinite(t) and t >= 0
		if not timeOk then
			add(
				ctx,
				"error",
				"keyframe.time",
				field(p, "time"),
				"keyframe time must be a number of seconds >= 0 (relative to the component start), got " .. describe(t),
				nil,
				componentId
			)
		else
			if t < previous and not orderReported then
				orderReported = true
				add(
					ctx,
					"warning",
					"keyframe.order",
					field(p, "time"),
					"keyframes are not sorted by time (" .. num(t) .. " s after " .. num(previous) .. " s)",
					"the compiler sorts them; sort the file to keep it readable",
					componentId
				)
			end
			if t > previous then
				previous = t
			end
			if lint and spanLength and spanLength > 0 and t > spanLength + EPSILON then
				outside += 1
				firstOutside = firstOutside or field(p, "time")
			end
		end
		local value = key.value
		local valueOk = false
		if value == nil then
			add(ctx, "error", "keyframe.value", field(p, "value"), "keyframe value is missing", nil, componentId)
		elseif channel then
			local ok, message = check(channel.kind, value, channel)
			if not ok then
				add(
					ctx,
					"error",
					"keyframe.value",
					field(p, "value"),
					channel.name .. ": " .. tostring(message),
					nil,
					componentId
				)
			elseif channel.kind == "color3" then
				valueOk = checkRefs(ctx, "color3", value, field(p, "value"), "keyframe.ref", componentId)
			else
				valueOk = true
			end
		end
		if key.easing ~= nil then
			local ok, message = checkEasing(key.easing)
			if not ok then
				add(ctx, "error", "keyframe.easing", field(p, "easing"), tostring(message), nil, componentId)
			end
		end
		if trackInfo and channel then
			table.insert(trackInfo.keys, {
				time = if timeOk then t else nil,
				value = if valueOk then normalize(channel.kind, value, channel) else nil,
			})
		end
	end
	if outside > 0 and firstOutside and spanLength then
		add(
			ctx,
			"warning",
			"lint.outside_duration",
			firstOutside,
			outside
				.. " keyframe(s) of this track lie after the component ends ("
				.. num(spanLength)
				.. " s after its start); they are never reached",
			"extend the component duration or move the keyframes",
			componentId
		)
	end
end

local function validateTracks(
	ctx: Ctx,
	info: Info,
	descriptor: ComponentDescriptor?,
	componentId: string?,
	lint: boolean
)
	local tracks = info.raw.tracks
	if tracks == nil then
		return
	end
	local path = field(info.path, "tracks")
	local n = arrayLength(tracks)
	if n == nil then
		add(
			ctx,
			"error",
			"component.tracks",
			path,
			"tracks must be an array, got " .. describe(tracks),
			nil,
			componentId
		)
		return
	end
	if n > Constants.MAX_TRACKS_PER_COMPONENT then
		add(
			ctx,
			"error",
			"track.limit",
			path,
			"a component can have at most " .. Constants.MAX_TRACKS_PER_COMPONENT .. " tracks, got " .. n,
			nil,
			componentId
		)
	end
	local ids: { [string]: number } = {}
	local channels: { [string]: number } = {}
	for i = 1, n do
		local track = tracks[i]
		local p = item(path, i)
		if not isObject(track) then
			add(ctx, "error", "track.invalid", p, "track must be an object, got " .. describe(track), nil, componentId)
			continue
		end
		unknownFields(ctx, track, SETS.track, TRACK_FIELDS, p, "track.unknown_field", "a track", componentId)
		local id = track.id
		if not isId(id) then
			add(
				ctx,
				"error",
				"track.id",
				field(p, "id"),
				"track id must be " .. ID_RULE .. ", got " .. describe(id),
				nil,
				componentId
			)
		elseif ids[id] then
			add(
				ctx,
				"error",
				"track.duplicate_id",
				field(p, "id"),
				"track id " .. quote(id) .. " is already used by tracks[" .. ids[id] .. "] of this component",
				nil,
				componentId
			)
		else
			ids[id] = i
		end
		local enabled = track.enabled
		if enabled ~= nil and type(enabled) ~= "boolean" then
			add(
				ctx,
				"error",
				"track.enabled",
				field(p, "enabled"),
				"enabled must be true or false, got " .. describe(enabled),
				nil,
				componentId
			)
		end
		local channelName = track.channel
		local channel: ChannelSpec? = nil
		if descriptor then
			if type(channelName) ~= "string" then
				add(
					ctx,
					"error",
					"track.channel",
					field(p, "channel"),
					"track channel must be a channel name, got " .. describe(channelName),
					"channels of " .. descriptor.type .. ": " .. table.concat(channelNames(descriptor), ", "),
					componentId
				)
			else
				channel = Components.channelSpec(descriptor.type, channelName)
				if channel == nil then
					local hint = suggest(channelName, channelNames(descriptor))
						or "channels of " .. descriptor.type .. ": " .. table.concat(channelNames(descriptor), ", ")
					if Components.propertySpec(descriptor.type, channelName) then
						hint = "property " .. quote(channelName) .. " is not animatable; " .. hint
					end
					add(
						ctx,
						"error",
						"track.channel",
						field(p, "channel"),
						descriptor.type .. " has no animatable channel " .. quote(channelName),
						hint,
						componentId
					)
				elseif enabled ~= false then
					if channels[channelName] then
						add(
							ctx,
							"error",
							"track.duplicate_channel",
							field(p, "channel"),
							"channel "
								.. quote(channelName)
								.. " is already animated by tracks["
								.. channels[channelName]
								.. "]",
							"merge the keyframes into one track or disable one of them",
							componentId
						)
					else
						channels[channelName] = i
					end
				end
			end
		end
		local trackInfo: TrackInfo? = nil
		if channel and enabled ~= false then
			local ti: TrackInfo = { channel = channel.name, keys = {} }
			local list = info.tracks[channel.name]
			if list == nil then
				list = {}
				info.tracks[channel.name] = list
			end
			table.insert(list, ti)
			trackInfo = ti
		end
		validateKeyframes(ctx, info, track, p, channel, trackInfo, componentId, lint)
	end
end

local function validateEvents(
	ctx: Ctx,
	info: Info,
	descriptor: ComponentDescriptor?,
	componentId: string?,
	lint: boolean
)
	local events = info.raw.events
	if events == nil then
		return
	end
	local path = field(info.path, "events")
	local n = arrayLength(events)
	if n == nil then
		add(
			ctx,
			"error",
			"component.events",
			path,
			"events must be an array, got " .. describe(events),
			nil,
			componentId
		)
		return
	end
	if n > Constants.MAX_EVENTS_PER_COMPONENT then
		add(
			ctx,
			"error",
			"event.limit",
			path,
			"a component can have at most " .. Constants.MAX_EVENTS_PER_COMPONENT .. " events, got " .. n,
			nil,
			componentId
		)
	end
	local ids: { [string]: number } = {}
	local spanLength = info.spanLength
	for i = 1, n do
		local event = events[i]
		local p = item(path, i)
		if not isObject(event) then
			add(ctx, "error", "event.invalid", p, "event must be an object, got " .. describe(event), nil, componentId)
			continue
		end
		unknownFields(ctx, event, SETS.event, EVENT_FIELDS, p, "event.unknown_field", "an event", componentId)
		local id = event.id
		if not isId(id) then
			add(
				ctx,
				"error",
				"event.id",
				field(p, "id"),
				"event id must be " .. ID_RULE .. ", got " .. describe(id),
				nil,
				componentId
			)
		elseif ids[id] then
			add(
				ctx,
				"error",
				"event.duplicate_id",
				field(p, "id"),
				"event id " .. quote(id) .. " is already used by events[" .. ids[id] .. "] of this component",
				nil,
				componentId
			)
		else
			ids[id] = i
		end
		local t = event.time
		if not isFinite(t) or t < 0 then
			add(
				ctx,
				"error",
				"event.time",
				field(p, "time"),
				"event time must be a number of seconds >= 0 (relative to the component start), got " .. describe(t),
				nil,
				componentId
			)
		elseif lint and spanLength and spanLength > 0 and t >= spanLength - EPSILON then
			add(
				ctx,
				"warning",
				"lint.outside_duration",
				field(p, "time"),
				"event at "
					.. num(t)
					.. " s is not inside the component span (0 to "
					.. num(spanLength)
					.. " s); it is dropped",
				"events must happen before the component ends",
				componentId
			)
		end
		if descriptor == nil then
			continue
		end
		local action = event.action
		local usesCount, usesName = false, false
		if type(action) ~= "string" then
			add(
				ctx,
				"error",
				"event.action",
				field(p, "action"),
				"event action must be a string, got " .. describe(action),
				"actions of " .. descriptor.type .. ": " .. table.concat(actionNames(descriptor), ", "),
				componentId
			)
			continue
		end
		if action == "fire" then
			usesName = true
		else
			local spec = Components.eventSpec(descriptor.type, action)
			if spec == nil then
				add(
					ctx,
					"error",
					"event.action",
					field(p, "action"),
					descriptor.type .. " does not support the action " .. quote(action),
					suggest(action, actionNames(descriptor))
						or "actions of " .. descriptor.type .. ": " .. table.concat(actionNames(descriptor), ", "),
					componentId
				)
				continue
			end
			usesCount = spec.usesCount == true
			usesName = spec.usesName == true
		end
		if action == "emit" then
			info.emitEvents += 1
		end
		local count = event.count
		if usesCount then
			local ok, message = check("integer", count, { min = 1, max = Constants.MAX_EMIT_COUNT })
			if count == nil then
				add(ctx, "error", "event.count", field(p, "count"), quote(action) .. " needs a count", nil, componentId)
			elseif not ok then
				add(ctx, "error", "event.count", field(p, "count"), "count: " .. tostring(message), nil, componentId)
			end
		elseif count ~= nil then
			add(
				ctx,
				"warning",
				"event.count",
				field(p, "count"),
				"count is ignored by the action " .. quote(action),
				nil,
				componentId
			)
		end
		local name = event.name
		if usesName then
			if not isEventName(name) then
				add(
					ctx,
					"error",
					"event.name",
					field(p, "name"),
					quote(action)
						.. " needs an event name ([A-Za-z_][A-Za-z0-9_-]*, at most "
						.. Constants.ID_MAX_LENGTH
						.. " characters), got "
						.. describe(name),
					nil,
					componentId
				)
			end
		elseif name ~= nil then
			add(
				ctx,
				"warning",
				"event.name",
				field(p, "name"),
				"name is ignored by the action " .. quote(action),
				nil,
				componentId
			)
		end
	end
end

local function validateOverrides(ctx: Ctx, info: Info, descriptor: ComponentDescriptor, componentId: string?)
	local overrides = info.raw.qualityOverrides
	if overrides == nil then
		return
	end
	local path = field(info.path, "qualityOverrides")
	if not isObject(overrides) then
		add(
			ctx,
			"error",
			"quality.type",
			path,
			"qualityOverrides must be an object of quality level -> properties, got " .. describe(overrides),
			nil,
			componentId
		)
		return
	end
	for _, level in sortedKeys(overrides) do
		local levelPath = field(path, level)
		if not LEVEL_SET[level] then
			add(
				ctx,
				"error",
				"quality.level",
				levelPath,
				quote(level) .. " is not a quality level (Low, Medium, High)",
				suggest(level, Constants.QUALITY_LEVELS),
				componentId
			)
		end
		local props = overrides[level]
		if not isObject(props) then
			add(
				ctx,
				"error",
				"quality.type",
				levelPath,
				"quality override must be an object of property values, got " .. describe(props),
				nil,
				componentId
			)
			continue
		end
		for _, key in sortedKeys(props) do
			local spec = Components.propertySpec(descriptor.type, key)
			local p = field(levelPath, key)
			if spec == nil then
				add(
					ctx,
					ctx.unknownSeverity,
					"property.unknown",
					p,
					descriptor.type .. " has no property " .. quote(key),
					suggest(key, propertyNames(descriptor)),
					componentId
				)
			else
				local ok, canonical = checkPropertyValue(ctx, spec, props[key], p, componentId)
				if ok and (key == "rate" or key == "burst") and type(canonical) == "number" and canonical > 0 then
					info.overrideEmits = true
				end
			end
		end
	end
end

local function validateTiming(ctx: Ctx, info: Info, componentId: string?)
	local raw = info.raw
	local startOk, durationOk = true, true
	local startTime = raw.startTime
	if startTime ~= nil and (not isFinite(startTime) or startTime < 0) then
		startOk = false
		add(
			ctx,
			"error",
			"component.start_time",
			field(info.path, "startTime"),
			"startTime must be a number of seconds >= 0, got " .. describe(startTime),
			nil,
			componentId
		)
	end
	local duration = raw.duration
	if duration ~= nil and (not isFinite(duration) or duration <= 0) then
		durationOk = false
		add(
			ctx,
			"error",
			"component.duration",
			field(info.path, "duration"),
			"duration must be a number of seconds > 0, got " .. describe(duration),
			nil,
			componentId
		)
	end
	info.timingValid = startOk and durationOk
	local effectDuration = ctx.duration
	if not (info.timingValid and effectDuration) then
		return
	end
	local s: number = if startTime ~= nil then startTime else 0
	if s >= (effectDuration :: number) then
		add(
			ctx,
			"warning",
			"component.timing",
			field(info.path, "startTime"),
			"component starts at "
				.. num(s)
				.. " s, at or after the effect end ("
				.. num(effectDuration :: number)
				.. " s); it never plays",
			nil,
			componentId
		)
	elseif duration ~= nil and s + duration > (effectDuration :: number) + EPSILON then
		add(
			ctx,
			"warning",
			"component.timing",
			field(info.path, "duration"),
			"component ends at "
				.. num(s + duration)
				.. " s, after the effect end ("
				.. num(effectDuration :: number)
				.. " s); it is cut off",
			"shorten the component or lengthen the effect",
			componentId
		)
	end
	local start, finish =
		Timeline.span({ duration = effectDuration } :: any, { startTime = startTime, duration = duration } :: any)
	info.spanLength = finish - start
end

local function validateComponent(ctx: Ctx, info: Info, firstIndexOfId: { [string]: number })
	local raw = info.raw
	local componentId = info.id
	unknownFields(
		ctx,
		raw,
		SETS.component,
		COMPONENT_FIELDS,
		info.path,
		"component.unknown_field",
		"a component",
		componentId
	)

	local id = raw.id
	if not isId(id) then
		add(
			ctx,
			"error",
			"component.id",
			field(info.path, "id"),
			"component id must be " .. ID_RULE .. ", got " .. describe(id)
		)
	elseif firstIndexOfId[id] ~= info.index then
		add(
			ctx,
			"error",
			"component.duplicate_id",
			field(info.path, "id"),
			"component id " .. quote(id) .. " is already used by components[" .. firstIndexOfId[id] .. "]",
			nil,
			componentId
		)
	end

	local nameProblem = checkName(raw.name)
	if nameProblem then
		add(
			ctx,
			"error",
			"component.name",
			field(info.path, "name"),
			"component name " .. nameProblem,
			nil,
			componentId
		)
	end

	local typeName = raw.type
	local descriptor = info.descriptor
	if type(typeName) ~= "string" then
		add(
			ctx,
			"error",
			"component.type",
			field(info.path, "type"),
			"component type must be a string, got " .. describe(typeName),
			"types: " .. table.concat(Components.types(), ", "),
			componentId
		)
	elseif descriptor == nil then
		add(
			ctx,
			"error",
			"component.type",
			field(info.path, "type"),
			"unknown component type " .. quote(typeName),
			suggest(typeName, Components.types()) or "types: " .. table.concat(Components.types(), ", "),
			componentId
		)
	end

	if raw.parent ~= nil and type(raw.parent) ~= "string" then
		add(
			ctx,
			"error",
			"component.parent",
			field(info.path, "parent"),
			"parent must be a component id, got " .. describe(raw.parent),
			nil,
			componentId
		)
	end
	if raw.enabled ~= nil and type(raw.enabled) ~= "boolean" then
		add(
			ctx,
			"error",
			"component.enabled",
			field(info.path, "enabled"),
			"enabled must be true or false, got " .. describe(raw.enabled),
			nil,
			componentId
		)
	end
	validateTiming(ctx, info, componentId)
	if raw.phase ~= nil and not PHASE_SET[raw.phase] then
		add(
			ctx,
			"error",
			"component.phase",
			field(info.path, "phase"),
			"phase must be one of " .. table.concat(Constants.PHASES, ", ") .. ", got " .. describe(raw.phase),
			suggest(raw.phase, Constants.PHASES),
			componentId
		)
	end
	if raw.minQuality ~= nil and not LEVEL_SET[raw.minQuality] then
		add(
			ctx,
			"error",
			"component.min_quality",
			field(info.path, "minQuality"),
			"minQuality must be Low, Medium or High, got " .. describe(raw.minQuality),
			suggest(raw.minQuality, Constants.QUALITY_LEVELS),
			componentId
		)
	end
	if raw.notes ~= nil and type(raw.notes) ~= "string" then
		add(
			ctx,
			"error",
			"component.notes",
			field(info.path, "notes"),
			"notes must be a string, got " .. describe(raw.notes),
			nil,
			componentId
		)
	end
	validateTransform(ctx, info, componentId)

	local lint = info.enabled and descriptor ~= nil
	if descriptor then
		validateProperties(ctx, info, descriptor, componentId)
	elseif raw.properties ~= nil and not isObject(raw.properties) then
		add(
			ctx,
			"error",
			"component.properties",
			field(info.path, "properties"),
			"properties must be an object, got " .. describe(raw.properties),
			nil,
			componentId
		)
	end
	validateTracks(ctx, info, descriptor, componentId, lint)
	validateEvents(ctx, info, descriptor, componentId, lint)
	if descriptor then
		validateOverrides(ctx, info, descriptor, componentId)
	elseif raw.qualityOverrides ~= nil and not isObject(raw.qualityOverrides) then
		add(
			ctx,
			"error",
			"quality.type",
			field(info.path, "qualityOverrides"),
			"qualityOverrides must be an object, got " .. describe(raw.qualityOverrides),
			nil,
			componentId
		)
	end
end

local function validateComponents(ctx: Ctx)
	local components = ctx.def.components
	if components == nil then
		add(ctx, "error", "effect.components", "components", "components is missing", "add a components array")
		return
	end
	local n = arrayLength(components)
	if n == nil then
		add(
			ctx,
			"error",
			"effect.components",
			"components",
			"components must be an array, got " .. describe(components)
		)
		return
	end
	if n == 0 then
		add(ctx, "warning", "effect.empty", "components", "the effect has no components; it shows nothing")
		return
	end
	if n > Constants.MAX_COMPONENTS then
		add(
			ctx,
			"error",
			"component.limit",
			"components",
			"an effect can have at most " .. Constants.MAX_COMPONENTS .. " components, got " .. n
		)
	end
	-- First pass: ids and types (references may point forwards).
	local firstIndexOfId: { [string]: number } = {}
	local infos: { [number]: Info } = {}
	local broken: { [number]: boolean } = {}
	local function register(i: number, raw: any)
		if isObject(raw) then
			local id = if isId(raw.id) then raw.id else nil
			local typeName = if type(raw.type) == "string" then raw.type else nil
			local info: Info = {
				index = i,
				path = item("components", i),
				raw = raw,
				id = id,
				typeName = typeName,
				descriptor = if typeName then Components.get(typeName) else nil,
				parent = raw.parent,
				enabled = raw.enabled ~= false,
				values = {},
				invalid = {},
				tracks = {},
				emitEvents = 0,
				overrideEmits = false,
				spanLength = nil,
				timingValid = false,
			}
			infos[i] = info
			table.insert(ctx.list, info)
			if id and firstIndexOfId[id] == nil then
				firstIndexOfId[id] = i
				ctx.byId[id] = info
			end
		end
	end
	for i = 1, n do
		local ok, err = pcall(register :: any, i, components[i])
		if not ok then
			broken[i] = true
			add(ctx, "error", "effect.internal", item("components", i), "the validator failed here: " .. safeText(err))
		end
	end
	for i = 1, n do
		local info = infos[i]
		if broken[i] then
			continue
		elseif info == nil then
			add(
				ctx,
				"error",
				"component.invalid",
				item("components", i),
				"component must be an object, got " .. describe(components[i])
			)
		else
			guard(ctx, info.path, validateComponent, ctx, info, firstIndexOfId)
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hierarchy
-- ─────────────────────────────────────────────────────────────────────────────

-- Parent info of a component (nil for roots, invalid or missing parents and self references).
local function parentOf(ctx: Ctx, info: Info): Info?
	local parent = info.parent
	if type(parent) ~= "string" or parent == info.id then
		return nil
	end
	return ctx.byId[parent]
end

local function validateHierarchy(ctx: Ctx)
	for _, info in ctx.list do
		local parent = info.parent
		if type(parent) ~= "string" then
			continue
		end
		local p = field(info.path, "parent")
		if parent == info.id then
			add(ctx, "error", "component.parent_self", p, "a component cannot be its own parent", nil, info.id)
			continue
		end
		local parentInfo = ctx.byId[parent]
		if parentInfo == nil then
			local ids = {}
			for id in pairs(ctx.byId) do
				table.insert(ids, id)
			end
			table.sort(ids)
			add(
				ctx,
				"error",
				"component.parent_missing",
				p,
				"parent component " .. quote(parent) .. " does not exist",
				suggest(parent, ids),
				info.id
			)
		elseif parentInfo.descriptor and not parentInfo.descriptor.canParent then
			add(
				ctx,
				"error",
				"component.parent_type",
				p,
				"components of type " .. parentInfo.descriptor.type .. " cannot have children",
				nil,
				info.id
			)
		end
	end

	-- Cycles: walk each chain once; a node revisited on the current walk closes a cycle.
	local done: { [Info]: boolean } = {}
	for _, info in ctx.list do
		if done[info] or (info.id and ctx.byId[info.id] ~= info) then
			continue
		end
		local chain: { Info } = {}
		local position: { [Info]: number } = {}
		local current: Info? = info
		while current and not done[current] do
			local at = position[current]
			if at then
				local members: { Info } = {}
				local first = current
				for k = at, #chain do
					table.insert(members, chain[k])
					if chain[k].index < first.index then
						first = chain[k]
					end
				end
				-- Describe the cycle starting at its first member in document order.
				local start = table.find(members, first) :: number
				local names = {}
				for k = 0, #members - 1 do
					table.insert(names, tostring(members[(start - 1 + k) % #members + 1].id))
				end
				table.insert(names, tostring(first.id))
				add(
					ctx,
					"error",
					"component.parent_cycle",
					field(first.path, "parent"),
					"the parent chain forms a cycle: " .. table.concat(names, " -> "),
					"remove one of the parent links",
					first.id
				)
				break
			end
			table.insert(chain, current)
			position[current] = #chain
			current = parentOf(ctx, current)
		end
		for _, member in chain do
			done[member] = true
		end
	end

	-- Enabled components below a disabled ancestor are not built.
	for _, info in ctx.list do
		if not info.enabled then
			continue
		end
		local seen: { [Info]: boolean } = { [info] = true }
		local current = parentOf(ctx, info)
		while current and not seen[current] do
			seen[current] = true
			if not current.enabled then
				add(
					ctx,
					"info",
					"component.disabled_ancestor",
					info.path,
					"ancestor " .. quote(tostring(current.id)) .. " is disabled, so this component is not built",
					nil,
					info.id
				)
				break
			end
			current = parentOf(ctx, current)
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Graph
-- ─────────────────────────────────────────────────────────────────────────────

-- Conservative static scan of Emit / Tween / SetProperty targets (for lints only; Graph.validate reports errors).
local function scanGraph(graph: any): GraphScan
	local scan: GraphScan = { dynamicEmit = false, emits = {}, dynamicChannels = {}, channels = {} }
	if not isObject(graph) then
		return scan
	end
	local nodes = graph.nodes
	local links = graph.links
	local nodeCount = arrayLength(nodes) or 0
	local linkCount = arrayLength(links) or 0
	local byId: { [string]: any } = {}
	for i = 1, nodeCount do
		local node = nodes[i]
		if isObject(node) and type(node.id) == "string" and byId[node.id] == nil then
			byId[node.id] = node
		end
	end
	local incoming: { [string]: string } = {}
	for i = 1, linkCount do
		local link = links[i]
		if
			isObject(link)
			and type(link.from) == "string"
			and type(link.to) == "string"
			and incoming[link.to] == nil
		then
			incoming[link.to] = link.from
		end
	end
	-- (target id, dynamic)
	local function target(node: any): (string?, boolean)
		local from = incoming[node.id .. ".target"]
		if from then
			local sourceId, pin = Graph.parseRef(from)
			local source = if sourceId then byId[sourceId] else nil
			if source and source.type == "Component" and pin == "component" then
				local params = source.params
				local id = if isObject(params) then params.component else nil
				return if type(id) == "string" and id ~= "" then id else nil, false
			end
			return nil, true
		end
		local params = node.params
		local id = if isObject(params) then params.target else nil
		return if type(id) == "string" and id ~= "" then id else nil, false
	end
	for i = 1, nodeCount do
		local node = nodes[i]
		if not (isObject(node) and type(node.id) == "string") then
			continue
		end
		if node.type == "Emit" then
			local id, dynamic = target(node)
			if dynamic then
				scan.dynamicEmit = true
			elseif id then
				scan.emits[id] = true
			end
		elseif node.type == "Tween" or node.type == "SetProperty" then
			local params = node.params
			local channel = if isObject(params) then params.channel else nil
			if type(channel) == "string" then
				local id, dynamic = target(node)
				if dynamic then
					scan.dynamicChannels[channel] = true
				elseif id then
					local set = scan.channels[id]
					if set == nil then
						set = {}
						scan.channels[id] = set
					end
					set[channel] = true
				end
			end
		end
	end
	return scan
end

local function validateGraph(ctx: Ctx)
	local graph = ctx.def.graph
	if graph == nil then
		return
	end
	ctx.graph = scanGraph(graph)
	local ok, diagnostics = pcall(Graph.validate :: any, graph, ctx.def)
	if not ok then
		add(ctx, "error", "effect.internal", "graph", "the graph validator failed: " .. safeText(diagnostics))
		return
	end
	if type(diagnostics) == "table" then
		for _, d in diagnostics do
			if type(d) == "table" then
				add(ctx, d.severity, d.code, d.path, d.message, d.hint, d.componentId)
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Quality
-- ─────────────────────────────────────────────────────────────────────────────

local function qualityValueProblem(key: string, v: any): string?
	if key == "countScale" or key == "segmentScale" then
		return if isFinite(v) and v >= 0 then nil else "must be a finite number >= 0"
	elseif key == "sizeCompensation" then
		return if isFinite(v) and v > 0 then nil else "must be a finite number > 0"
	elseif key == "lightShadows" then
		return if type(v) == "boolean" then nil else "must be true or false"
	elseif key == "maxLights" then
		return if isFinite(v) and v >= 0 and v % 1 == 0 then nil else "must be a whole number >= 0"
	end
	return nil
end

local function validateQuality(ctx: Ctx)
	local quality = ctx.def.quality
	if quality == nil then
		return
	end
	if not isObject(quality) then
		add(
			ctx,
			"error",
			"quality.type",
			"quality",
			"quality must be an object of quality level -> profile override, got " .. describe(quality)
		)
		return
	end
	for _, level in sortedKeys(quality) do
		local path = field("quality", level)
		if not LEVEL_SET[level] then
			add(
				ctx,
				"error",
				"quality.level",
				path,
				quote(level) .. " is not a quality level (Low, Medium, High)",
				suggest(level, Constants.QUALITY_LEVELS)
			)
		end
		local override = quality[level]
		if not isObject(override) then
			add(
				ctx,
				"error",
				"quality.type",
				path,
				"quality profile override must be an object, got " .. describe(override)
			)
			continue
		end
		for _, key in sortedKeys(override) do
			local p = field(path, key)
			if not SETS.quality[key] then
				add(
					ctx,
					ctx.unknownSeverity,
					"quality.field",
					p,
					"quality profile overrides have no field " .. quote(key),
					suggest(key, QUALITY_FIELDS) or "fields: " .. table.concat(QUALITY_FIELDS, ", ")
				)
			else
				local problem = qualityValueProblem(key, override[key])
				if problem then
					add(ctx, "error", "quality.value", p, key .. " " .. problem .. ", got " .. describe(override[key]))
				end
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lints
-- ─────────────────────────────────────────────────────────────────────────────

-- Effective property value: authored (when valid) or the spec default. known = false when the value is invalid.
local function effective(info: Info, name: string): (any, boolean)
	if info.invalid[name] then
		return nil, false
	end
	local v = info.values[name]
	if v ~= nil then
		return v, true
	end
	local spec = if info.typeName then Components.propertySpec(info.typeName, name) else nil
	if spec == nil then
		return nil, false
	end
	return spec.default, true
end

local function graphTouches(ctx: Ctx, info: Info, channel: string): boolean
	if ctx.graph.dynamicChannels[channel] then
		return true
	end
	local set = if info.id then ctx.graph.channels[info.id] else nil
	return set ~= nil and set[channel] == true
end

-- True when a track of `channel` has a key whose (valid) value satisfies `predicate`, or an invalid value.
local function trackAny(info: Info, channel: string, predicate: (any) -> boolean): boolean
	local list = info.tracks[channel]
	if list == nil then
		return false
	end
	for _, track in list do
		for _, key in track.keys do
			if key.value == nil or predicate(key.value) then
				return true
			end
		end
	end
	return false
end

local function isNonZero(v: any): boolean
	if type(v) == "number" then
		return v ~= 0
	elseif type(v) == "table" then
		for _, x in ipairs(v) do
			if x ~= 0 then
				return true
			end
		end
	end
	return false
end

local function hasMotion(ctx: Ctx, info: Info): boolean
	for _, channel in { "position", "rotation" } do
		local list = info.tracks[channel]
		if list then
			for _, track in list do
				if #track.keys >= 2 then
					return true
				end
			end
		end
		if graphTouches(ctx, info, channel) then
			return true
		end
	end
	local spin, known = effective(info, "spin")
	if not known then
		return info.invalid.spin == true -- invalid spin: unknown, assume motion (the error is reported)
	end
	return isNonZero(spin)
end

local function lintComponent(ctx: Ctx, info: Info)
	local typeName = info.typeName
	local componentId = info.id
	if typeName == "trail" then
		local seen: { [Info]: boolean } = {}
		local current: Info? = info
		local moving = false
		while current and not seen[current] do
			seen[current] = true
			if hasMotion(ctx, current) then
				moving = true
				break
			end
			current = parentOf(ctx, current)
		end
		if not moving then
			add(
				ctx,
				"warning",
				"lint.trail_static",
				info.path,
				"trail has no movement source (no position/rotation track or spin on it or an ancestor); it only draws while moving",
				"animate position, put it under a spinning group, or attach the effect to a moving part",
				componentId
			)
		end
	elseif typeName == "particles" then
		local rate, rateKnown = effective(info, "rate")
		local burst, burstKnown = effective(info, "burst")
		if not (rateKnown and burstKnown) then
			return
		end
		local silent = rate == 0
			and burst == 0
			and info.emitEvents == 0
			and not info.overrideEmits
			and not ctx.graph.dynamicEmit
			and not (componentId and ctx.graph.emits[componentId])
			and not graphTouches(ctx, info, "rate")
			and not trackAny(info, "rate", function(v)
				return type(v) == "number" and v > 0
			end)
		if silent then
			add(
				ctx,
				"warning",
				"lint.particles_silent",
				info.path,
				"particles never emit: rate and burst are 0 and nothing triggers an emit",
				"set rate or burst, add an emit event, animate rate or target it with a graph Emit node",
				componentId
			)
		end
	elseif typeName == "beam" then
		local w0, k0 = effective(info, "width0")
		local w1, k1 = effective(info, "width1")
		if not (k0 and k1) or w0 ~= 0 or w1 ~= 0 then
			return
		end
		for _, channel in { "width0", "width1" } do
			if graphTouches(ctx, info, channel) or trackAny(info, channel, isNonZero) then
				return
			end
		end
		add(
			ctx,
			"warning",
			"lint.zero_width",
			info.path,
			"beam has width0 = width1 = 0; it is invisible",
			"give width0 or width1 a value above 0",
			componentId
		)
	elseif typeName == "flash" then
		local spanLength = info.spanLength
		if spanLength == nil or spanLength <= 0 then
			return
		end
		local attack, ka = effective(info, "attack")
		local hold, kh = effective(info, "hold")
		local decay, kd = effective(info, "decay")
		if not (ka and kh and kd) or type(attack) ~= "number" or type(hold) ~= "number" or type(decay) ~= "number" then
			return
		end
		local total = attack + hold + decay
		if spanLength + EPSILON < total then
			add(
				ctx,
				"warning",
				"lint.flash_short",
				info.path,
				"flash lasts "
					.. num(spanLength)
					.. " s but its envelope (attack + hold + decay) needs "
					.. num(total)
					.. " s; it is cut off",
				"lengthen the component or shorten attack/hold/decay",
				componentId
			)
		end
	elseif typeName == "mesh" then
		local meshType, kt = effective(info, "meshType")
		local meshId, ki = effective(info, "meshId")
		if kt and ki and meshType == "FileMesh" and meshId == "" then
			add(
				ctx,
				"warning",
				"lint.filemesh_no_id",
				field(field(info.path, "properties"), "meshId"),
				'meshType "FileMesh" needs a meshId; without one nothing is rendered',
				'set meshId to an uploaded mesh ("rbxassetid://...") or use a built-in meshType',
				componentId
			)
		end
	end
end

local function lint(ctx: Ctx)
	for _, info in ctx.list do
		if info.enabled and info.descriptor then
			guard(ctx, info.path, lintComponent, ctx, info)
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Entry point
-- ─────────────────────────────────────────────────────────────────────────────

local function run(ctx: Ctx)
	guard(ctx, "", validateEffectFields, ctx)
	guard(ctx, "palette", validatePalette, ctx)
	guard(ctx, "markers", validateMarkers, ctx)
	guard(ctx, "components", validateComponents, ctx)
	guard(ctx, "components", validateHierarchy, ctx)
	guard(ctx, "graph", validateGraph, ctx)
	guard(ctx, "quality", validateQuality, ctx)
	guard(ctx, "components", lint, ctx)
end

-- Validates a (migrated) effect definition. Never throws.
function Validation.validate(def: any, options: Options?): ValidationResult
	local result: ValidationResult = { ok = false, errors = {}, warnings = {}, infos = {} }
	local strict = false
	pcall(function()
		local o: any = options
		strict = type(o) == "table" and o.strict == true
	end)
	local ctx: Ctx = {
		result = result,
		strict = strict,
		unknownSeverity = if strict then "error" else "warning",
		def = {},
		duration = nil,
		palette = {},
		list = {},
		byId = {},
		graph = { dynamicEmit = false, emits = {}, dynamicChannels = {}, channels = {} },
	}
	if not isObject(def) then
		add(ctx, "error", "effect.type", "", "an effect definition must be an object, got " .. describe(def))
	else
		ctx.def = def
		guard(ctx, "", run, ctx)
	end
	result.ok = #result.errors == 0
	return result
end

return Validation
