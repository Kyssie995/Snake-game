--!strict
--[[
	Migration — upgrades older effect documents to the current schema version. See docs/MODULE_CONTRACTS.md §12.

	  Migration.CURRENT                        = Constants.SCHEMA_VERSION
	  Migration.migrate(raw) -> (EffectDefinition?, { Diagnostic })
	  Migration.STEPS                          step registry: STEPS[n] upgrades version n to n + 1
	  Migration.detect(raw) -> (version?, legacyReasons)   which version migrate() would start from
	  Migration.slug(text, fallback?) -> string             id slug ("VioletImpact" -> "violetimpact")

	migrate() never mutates its input: it works on a deep copy (Json.NULL / Json.EMPTY_OBJECT sentinels are kept by
	identity, metatables are dropped). It does not validate; run Validation.validate on the result. The result is
	nil only for input that cannot be a document at all (error diagnostics); otherwise every change is described
	by an info (or warning) diagnostic with a 1-based path.

	Version detection:
	  * schemaVersion missing                      -> version 0 (info migration.missing_version)
	  * schemaVersion 0                            -> version 0
	  * schemaVersion == 1 with legacy concept keys -> version 0 (info migration.legacy_concept_format). The project
	    brief's example is labelled "schemaVersion": 1 although it uses the concept format. Legacy keys are:
	      - properties.initialScale / finalScale on a type that has a "scale" channel and no such property
	        (sphere in the brief), or
	      - properties.color given as an [r, g, b] array on a type that has no "color" property but other colour
	        properties (sphere: coreColor / shellColor).
	  * schemaVersion > CURRENT                    -> error migration.future_version, nil
	  * anything else that is not a whole number >= 0 -> error migration.version_invalid, nil

	Version 0 (pre-release "concept" format) -> 1:
	  * effect name missing -> the id (or "Effect"); effect id missing or not a valid id -> slug of the name
	  * components without a valid id get a slug of their invalid id string, else name, else type, made unique
	    ("core", "core-2", ...); components without a name get their id as name
	  * properties.color [r, g, b] (or any colour) on a type without "color" -> every colour property whose name
	    ends in "Color" (sphere: coreColor and shellColor) that is not set yet; the key "color" is removed
	  * colour properties (color3 / colorSequence kinds) given as [r, g, b] arrays -> "#RRGGBB"
	  * properties.initialScale / finalScale (missing one = 1) on a type with a "scale" channel -> a "scale" track
	    from initialScale (time 0) to finalScale (end of the component: its duration, else the effect duration minus
	    its startTime), Linear. Equal values set transform.scale instead (unless already set). Without a usable
	    span transform.scale = initialScale (warning). If a scale track already exists the keys are dropped and the
	    track is kept (warning). Non-numeric or negative values are left in place (warning; Validation reports them)
	  * tracks / events / markers without ids get slug ids (channel / action / label), unique per scope

	Diagnostic codes:
	  error    migration.invalid               input is not an object (or a JSON text of one)
	  error    migration.json                  string input is not valid JSON (extension: migrate accepts JSON text)
	  error    migration.not_json              input contains a cycle or is nested deeper than Json.MAX_DEPTH
	  error    migration.version_invalid       schemaVersion is not a whole number >= 0
	  error    migration.future_version        schemaVersion is newer than CURRENT
	  error    migration.no_step               no registered step upgrades this version (programmer error)
	  info     migration.missing_version       no schemaVersion; treated as version 0
	  info     migration.legacy_concept_format schemaVersion 1 with concept-format keys; treated as version 0
	  info     migration.step                  one step ran ("schema 0 -> 1")
	  info     migration.effect_name           effect name added
	  info     migration.effect_id             effect id added / replaced by a slug
	  info     migration.component_id          component id added / replaced by a slug
	  info     migration.component_name        component name added
	  info     migration.color                 colour converted to "#RRGGBB" or moved to the type's colour keys
	  info     migration.scale_track           initialScale / finalScale converted (track or transform.scale)
	  warning  migration.scale_conflict        initialScale / finalScale dropped (a scale track exists), or no span
	  warning  migration.scale_invalid         initialScale / finalScale not usable; left in place
	  info     migration.track_id              track id added
	  info     migration.event_id              event id added
	  info     migration.marker_id             marker id added

	Adding version 2: bump Constants.SCHEMA_VERSION, add STEPS[1] = { from = 1, to = 2, description, run } and keep
	STEPS[0]; documents run through every step from their version up to CURRENT. migrate(raw, { target, steps })
	(extension, used by tests) runs against another step table / target version.
]]

local Codec = require(script.Parent.Codec)
local Components = require(script.Parent.Components)
local Constants = require(script.Parent.Constants)
local Json = require(script.Parent.Json)
local Types = require(script.Parent.Types)

type Diagnostic = Types.Diagnostic
type Severity = Types.Severity
type EffectDefinition = Types.EffectDefinition
type ComponentDescriptor = Types.ComponentDescriptor

-- Collects diagnostics of one migrate() call.
export type Report = {
	diagnostics: { Diagnostic },
	add: (self: Report, severity: Severity, code: string, path: string, message: string, componentId: string?) -> (),
}

export type Step = {
	from: number,
	to: number,
	description: string,
	run: (doc: { [string]: any }, report: Report) -> (),
}

export type MigrateOptions = {
	target: number?, -- default CURRENT
	steps: { [number]: Step }?, -- default Migration.STEPS
}

local Migration = {}

Migration.CURRENT = Constants.SCHEMA_VERSION

local NULL: any = Json.NULL
local EMPTY_OBJECT: any = Json.EMPTY_OBJECT
local INF = math.huge
local ID_PATTERN = Constants.ID_PATTERN
local ID_MAX_LENGTH = Constants.ID_MAX_LENGTH

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function isSentinel(v: any): boolean
	return rawequal(v, NULL) or rawequal(v, EMPTY_OBJECT)
end

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
	return if n == maxIndex then n else nil
end

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

local function isId(v: any): boolean
	return type(v) == "string" and #v >= 1 and #v <= ID_MAX_LENGTH and string.match(v, ID_PATTERN) ~= nil
end

local function num(n: number): string
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	local s = string.format("%.6f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

local function describe(v: any): string
	if v == nil then
		return "nothing"
	elseif rawequal(v, NULL) then
		return "null"
	elseif type(v) == "number" then
		return if isFinite(v) then num(v) else tostring(v)
	elseif type(v) == "string" then
		return string.format("%q", if #v > 40 then string.sub(v, 1, 37) .. "..." else v)
	elseif type(v) == "table" then
		local n = arrayLength(v)
		if n then
			return if n == 0 then "an empty table" else "an array of " .. n .. " items"
		end
		return "an object"
	end
	return "a " .. typeof(v) .. " value"
end

local function field(base: string, key: string): string
	if string.match(key, "^[A-Za-z_][A-Za-z0-9_]*$") then
		return if base == "" then key else base .. "." .. key
	end
	return base .. "[" .. string.format("%q", key) .. "]"
end

local function item(base: string, i: number): string
	return base .. "[" .. i .. "]"
end

-- Writable table at parent[key]: replaces the frozen Json.EMPTY_OBJECT sentinel with a fresh table.
local function writable(parent: { [any]: any }, key: any): { [any]: any }
	local t = parent[key]
	if rawequal(t, EMPTY_OBJECT) then
		local fresh = {}
		parent[key] = fresh
		return fresh
	end
	return t
end

-- Deep copy of plain data. Sentinels are kept by identity, metatables dropped, keys kept as they are.
-- Returns (copy, nil) or (nil, problem) for cycles and excessive nesting.
local function deepCopy(value: any, path: string, depth: number, stack: { [any]: boolean }): (any, string?)
	if type(value) ~= "table" or isSentinel(value) then
		return value, nil
	end
	if stack[value] then
		return nil, path .. " refers back to one of its own containers (cycle)"
	end
	if depth > Json.MAX_DEPTH then
		return nil, path .. " is nested deeper than " .. Json.MAX_DEPTH .. " levels"
	end
	stack[value] = true
	local out = {}
	for k, v in pairs(value) do
		local childPath = if type(k) == "string" then field(path, k) else path .. "[" .. tostring(k) .. "]"
		local copy, problem = deepCopy(v, childPath, depth + 1, stack)
		if problem then
			stack[value] = nil
			return nil, problem
		end
		out[k] = copy
	end
	stack[value] = nil
	return out, nil
end

local function newReport(): Report
	local report = {
		diagnostics = {} :: { Diagnostic },
	}
	function report.add(
		self: Report,
		severity: Severity,
		code: string,
		path: string,
		message: string,
		componentId: string?
	)
		table.insert(self.diagnostics, {
			severity = severity,
			code = code,
			path = path,
			message = message,
			componentId = componentId,
		})
	end
	return report :: any
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Ids
-- ─────────────────────────────────────────────────────────────────────────────

-- Lower-case id slug: runs of characters outside [a-z0-9_-] become "-", leading/trailing "-" are trimmed, at most
-- Constants.ID_MAX_LENGTH characters. Empty results return `fallback` (default "effect").
function Migration.slug(text: any, fallback: string?): string
	local s = if type(text) == "string" then string.lower(text) else ""
	s = string.gsub(s, "[^a-z0-9_%-]+", "-")
	s = string.gsub(s, "%-%-+", "-")
	s = string.gsub(s, "^%-+", "")
	s = string.sub(s, 1, ID_MAX_LENGTH)
	s = string.gsub(s, "%-+$", "")
	if s == "" then
		return fallback or "effect"
	end
	return s
end

-- `base` or "base-2", "base-3", ... (whichever is free in `taken`); marks the result as taken.
local function unique(base: string, taken: { [string]: boolean }): string
	local candidate = base
	local n = 1
	while taken[candidate] do
		n += 1
		local suffix = "-" .. n
		candidate = string.sub(base, 1, ID_MAX_LENGTH - #suffix) .. suffix
	end
	taken[candidate] = true
	return candidate
end

-- Collects valid ids of the object entries of an array.
local function takenIds(list: { any }): { [string]: boolean }
	local taken: { [string]: boolean } = {}
	for _, entry in list do
		if isObject(entry) and isId(entry.id) then
			taken[entry.id] = true
		end
	end
	return taken
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Legacy detection
-- ─────────────────────────────────────────────────────────────────────────────

local function isRgbArray(v: any): boolean
	return arrayLength(v) == 3 and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
end

-- "[150, 65, 255]" for RGB arrays, describe() otherwise (messages only).
local function showColor(v: any): string
	if isRgbArray(v) then
		return "[" .. num(v[1]) .. ", " .. num(v[2]) .. ", " .. num(v[3]) .. "]"
	end
	return describe(v)
end

-- Colour properties that receive a legacy `color` on a type without one ("coreColor", "shellColor" for sphere).
local function colorTargets(descriptor: ComponentDescriptor): { string }
	local out: { string } = {}
	for _, spec in descriptor.properties do
		if spec.kind == "color3" and string.match(spec.name, "Color$") then
			table.insert(out, spec.name)
		end
	end
	return out
end

local function hasLegacyScale(descriptor: ComponentDescriptor, props: { [string]: any }): boolean
	if props.initialScale == nil and props.finalScale == nil then
		return false
	end
	local t = descriptor.type
	return Components.channelSpec(t, "scale") ~= nil
		and Components.propertySpec(t, "initialScale") == nil
		and Components.propertySpec(t, "finalScale") == nil
end

local function hasLegacyColor(descriptor: ComponentDescriptor, props: { [string]: any }): boolean
	return isRgbArray(props.color)
		and Components.propertySpec(descriptor.type, "color") == nil
		and #colorTargets(descriptor) > 0
end

-- Version migrate() starts from, plus the reasons when a schemaVersion 1 document uses concept-format keys.
-- version nil = not migratable (see migrate()).
function Migration.detect(raw: any): (number?, { string })
	local reasons: { string } = {}
	if not isObject(raw) then
		return nil, reasons
	end
	local version = raw.schemaVersion
	if version == nil then
		return 0, reasons
	end
	if not isFinite(version) or version < 0 or version % 1 ~= 0 then
		return nil, reasons
	end
	if version == 1 then
		local components = raw.components
		local n = arrayLength(components)
		for i = 1, n or 0 do
			local c = components[i]
			if not isObject(c) or type(c.type) ~= "string" or not isObject(c.properties) then
				continue
			end
			local descriptor = Components.get(c.type)
			if descriptor == nil then
				continue
			end
			local path = item("components", i) .. ".properties"
			if hasLegacyScale(descriptor, c.properties) then
				table.insert(reasons, path .. ": initialScale/finalScale")
			end
			if hasLegacyColor(descriptor, c.properties) then
				table.insert(reasons, path .. ".color: [r, g, b] on " .. c.type)
			end
		end
		if #reasons > 0 then
			return 0, reasons
		end
	end
	return version, reasons
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 0 -> 1 (concept format -> schema 1)
-- ─────────────────────────────────────────────────────────────────────────────

local function hex(value: any): string?
	local okCheck, valid = pcall(Codec.check :: any, "color3", value)
	if not okCheck or not valid then
		return nil
	end
	local ok, canonical = pcall(Codec.normalize :: any, "color3", value)
	if ok and type(canonical) == "string" then
		return canonical
	end
	return nil
end

-- Seconds from the component start to its end, or nil when unknown.
local function componentLength(doc: { [string]: any }, c: { [string]: any }): number?
	local duration = c.duration
	if isFinite(duration) and duration > 0 then
		return duration
	end
	local effectDuration = doc.duration
	local start = if isFinite(c.startTime) then c.startTime else 0
	if isFinite(effectDuration) and effectDuration - start > 0 then
		return effectDuration - start
	end
	return nil
end

local function migrateColors(
	report: Report,
	descriptor: ComponentDescriptor,
	props: { [string]: any },
	path: string,
	componentId: string?
)
	local t = descriptor.type
	local color = props.color
	if color ~= nil and Components.propertySpec(t, "color") == nil then
		local targets = colorTargets(descriptor)
		local value = hex(color)
		if #targets > 0 and value then
			local assigned: { string } = {}
			for _, target in targets do
				if props[target] == nil then
					props[target] = value
					table.insert(assigned, target)
				end
			end
			props.color = nil
			report:add(
				"info",
				"migration.color",
				field(path, "color"),
				"color "
					.. showColor(color)
					.. (if #assigned > 0
						then " -> " .. table.concat(assigned, ", ") .. ' = "' .. value .. '"'
						else " removed (" .. table.concat(targets, ", ") .. " already set)")
					.. " ("
					.. t
					.. " has no color property)",
				componentId
			)
		end
	end
	for _, spec in descriptor.properties do
		local v = props[spec.name]
		if (spec.kind == "color3" or spec.kind == "colorSequence") and isRgbArray(v) then
			local value = hex(v)
			if value then
				props[spec.name] = value
				report:add(
					"info",
					"migration.color",
					field(path, spec.name),
					spec.name .. " " .. showColor(v) .. ' -> "' .. value .. '"',
					componentId
				)
			end
		end
	end
end

local function migrateScale(
	report: Report,
	doc: { [string]: any },
	c: { [string]: any },
	props: { [string]: any },
	path: string,
	componentId: string?
)
	local initial: any = props.initialScale
	local final: any = props.finalScale
	if initial == nil then
		initial = 1
	end
	if final == nil then
		final = 1
	end
	local propsPath = field(path, "properties")
	if not (isFinite(initial) and initial >= 0 and isFinite(final) and final >= 0) then
		report:add(
			"warning",
			"migration.scale_invalid",
			propsPath,
			"initialScale/finalScale must be numbers >= 0 (got "
				.. describe(props.initialScale)
				.. " / "
				.. describe(props.finalScale)
				.. "); left unchanged",
			componentId
		)
		return
	end
	local tracks = c.tracks
	if tracks ~= nil and arrayLength(tracks) == nil then
		report:add(
			"warning",
			"migration.scale_invalid",
			propsPath,
			"initialScale/finalScale cannot become a track because tracks is not an array; left unchanged",
			componentId
		)
		return
	end
	props.initialScale = nil
	props.finalScale = nil
	if tracks ~= nil then
		for _, track in tracks :: { any } do
			if isObject(track) and track.channel == "scale" then
				report:add(
					"warning",
					"migration.scale_conflict",
					propsPath,
					"initialScale/finalScale dropped: the component already has a scale track",
					componentId
				)
				return
			end
		end
	end
	local function setRestScale(value: number, severity: Severity, code: string, message: string)
		local transform = c.transform
		if transform == nil then
			transform = {}
			c.transform = transform
		elseif isObject(transform) then
			transform = writable(c, "transform")
		else
			report:add(
				"warning",
				"migration.scale_conflict",
				field(path, "transform"),
				message .. "; transform is not an object, value dropped",
				componentId
			)
			return
		end
		if transform.scale == nil then
			transform.scale = value
			report:add(severity, code, field(field(path, "transform"), "scale"), message, componentId)
		else
			report:add(
				"warning",
				"migration.scale_conflict",
				field(field(path, "transform"), "scale"),
				message .. "; transform.scale was already set and is kept",
				componentId
			)
		end
	end
	if initial == final then
		setRestScale(
			initial,
			"info",
			"migration.scale_track",
			"initialScale = finalScale = " .. num(initial) .. " -> transform.scale"
		)
		return
	end
	local length = componentLength(doc, c)
	if length == nil then
		setRestScale(
			initial,
			"warning",
			"migration.scale_conflict",
			"initialScale/finalScale need a component span; transform.scale = initialScale (" .. num(initial) .. ")"
		)
		return
	end
	local list: { any }
	if tracks == nil then
		list = {}
		c.tracks = list
	else
		list = writable(c, "tracks")
	end
	local id = unique("scale", takenIds(list))
	table.insert(list, {
		id = id,
		channel = "scale",
		keyframes = {
			{ time = 0, value = initial },
			{ time = length, value = final },
		},
	})
	report:add(
		"info",
		"migration.scale_track",
		item(field(path, "tracks"), #list),
		"initialScale/finalScale -> scale track "
			.. num(initial)
			.. " -> "
			.. num(final)
			.. " over "
			.. num(length)
			.. " s",
		componentId
	)
end

-- Gives entries of an array without a usable id a slug id (`labelKey` names the field the slug is made from).
local function migrateEntryIds(
	report: Report,
	list: { any },
	path: string,
	labelKey: string,
	fallback: string,
	code: string,
	what: string,
	componentId: string?
)
	local taken = takenIds(list)
	for i, entry in list do
		if isObject(entry) and entry.id == nil then
			local e = writable(list, i)
			local id = unique(Migration.slug(e[labelKey], fallback), taken)
			e.id = id
			report:add(
				"info",
				code,
				field(item(path, i), "id"),
				what .. ' without id -> id "' .. id .. '"',
				componentId
			)
		end
	end
end

local function migrateComponent(
	report: Report,
	doc: { [string]: any },
	components: { any },
	i: number,
	taken: { [string]: boolean }
)
	local c = writable(components, i)
	local path = item("components", i)
	if not isId(c.id) then
		-- an invalid id string keeps its intent ("Not Valid!" -> "not-valid"), else the name, else the type
		local base = Migration.slug(c.id, "")
		if base == "" then
			base = Migration.slug(c.name, "")
		end
		if base == "" then
			base = Migration.slug(c.type, "component")
		end
		local id = unique(base, taken)
		report:add(
			"info",
			"migration.component_id",
			field(path, "id"),
			(if c.id == nil then "component without id" else "component id " .. describe(c.id) .. " is not a valid id")
				.. ' -> id "'
				.. id
				.. '"',
			id
		)
		c.id = id
	end
	local componentId: string? = if isId(c.id) then c.id else nil
	if type(c.name) ~= "string" or c.name == "" then
		c.name = c.id
		report:add(
			"info",
			"migration.component_name",
			field(path, "name"),
			'component name -> "' .. tostring(c.id) .. '"',
			componentId
		)
	end
	local descriptor = if type(c.type) == "string" then Components.get(c.type) else nil
	if descriptor and isObject(c.properties) and next(c.properties) ~= nil then
		local props = writable(c, "properties")
		local propsPath = field(path, "properties")
		migrateColors(report, descriptor, props, propsPath, componentId)
		if hasLegacyScale(descriptor, props) then
			migrateScale(report, doc, c, props, path, componentId)
		end
	end
	if arrayLength(c.tracks) then
		local tracks = writable(c, "tracks")
		migrateEntryIds(
			report,
			tracks,
			field(path, "tracks"),
			"channel",
			"track",
			"migration.track_id",
			"track",
			componentId
		)
	end
	if arrayLength(c.events) then
		local events = writable(c, "events")
		migrateEntryIds(
			report,
			events,
			field(path, "events"),
			"action",
			"event",
			"migration.event_id",
			"event",
			componentId
		)
	end
end

local function step0(doc: { [string]: any }, report: Report)
	if type(doc.name) ~= "string" or doc.name == "" then
		local name = if type(doc.id) == "string" and doc.id ~= "" then doc.id else "Effect"
		doc.name = name
		report:add("info", "migration.effect_name", "name", 'effect without name -> name "' .. name .. '"')
	end
	if doc.id == nil or (type(doc.id) == "string" and not isId(doc.id)) then
		local id = Migration.slug(doc.name, "effect")
		report:add(
			"info",
			"migration.effect_id",
			"id",
			(if doc.id == nil then "effect without id" else "effect id " .. describe(doc.id) .. " is not a valid id")
				.. ' -> id "'
				.. id
				.. '"'
		)
		doc.id = id
	end
	if arrayLength(doc.components) then
		local components = writable(doc, "components")
		local taken = takenIds(components)
		for i, c in components do
			if isObject(c) then
				migrateComponent(report, doc, components, i, taken)
			end
		end
	end
	if arrayLength(doc.markers) then
		local markers = writable(doc, "markers")
		migrateEntryIds(report, markers, "markers", "label", "marker", "migration.marker_id", "marker", nil)
	end
end

Migration.STEPS = {
	[0] = {
		from = 0,
		to = 1,
		description = 'pre-release concept format -> schema 1 (ids, "#RRGGBB" colours, initialScale/finalScale -> scale track)',
		run = step0,
	} :: Step,
} :: { [number]: Step }

-- ─────────────────────────────────────────────────────────────────────────────
-- Entry point
-- ─────────────────────────────────────────────────────────────────────────────

-- Upgrades `raw` (a definition table or its JSON text) to schema CURRENT. Never mutates `raw`, never throws for
-- data problems (returns nil plus an error diagnostic when the input cannot be a document).
function Migration.migrate(raw: any, options: MigrateOptions?): (EffectDefinition?, { Diagnostic })
	local o: MigrateOptions = options or {}
	local target = o.target or Migration.CURRENT
	local steps = o.steps or Migration.STEPS
	local report = newReport()

	if type(raw) == "string" then
		local ok, decoded = Json.decode(raw)
		if not ok then
			report:add("error", "migration.json", "", "effect text is not valid JSON: " .. tostring(decoded))
			return nil, report.diagnostics
		end
		raw = decoded
	end
	if not isObject(raw) or rawequal(raw, NULL) then
		report:add("error", "migration.invalid", "", "an effect definition must be an object, got " .. describe(raw))
		return nil, report.diagnostics
	end

	local copy, problem = deepCopy(raw, "", 1, {})
	if problem then
		report:add("error", "migration.not_json", "", "the definition is not plain JSON data: " .. problem)
		return nil, report.diagnostics
	end
	local doc: { [string]: any } = if rawequal(copy, EMPTY_OBJECT) then {} else copy

	local rawVersion = doc.schemaVersion
	if rawVersion ~= nil and (not isFinite(rawVersion) or rawVersion < 0 or rawVersion % 1 ~= 0) then
		report:add(
			"error",
			"migration.version_invalid",
			"schemaVersion",
			"schemaVersion must be a whole number >= 0, got " .. describe(rawVersion)
		)
		return nil, report.diagnostics
	end
	if rawVersion ~= nil and rawVersion > target then
		report:add(
			"error",
			"migration.future_version",
			"schemaVersion",
			"schemaVersion "
				.. num(rawVersion)
				.. " is newer than this runtime supports ("
				.. num(target)
				.. "); update ASTRA VFX"
		)
		return nil, report.diagnostics
	end

	local version: number
	if rawVersion == nil then
		version = 0
		report:add(
			"info",
			"migration.missing_version",
			"schemaVersion",
			"no schemaVersion; treated as version 0 (pre-release concept format)"
		)
	else
		local detected, reasons = Migration.detect(doc)
		version = detected or rawVersion
		if #reasons > 0 and version ~= rawVersion then
			report:add(
				"info",
				"migration.legacy_concept_format",
				"schemaVersion",
				"schemaVersion "
					.. num(rawVersion)
					.. " but concept-format keys ("
					.. table.concat(reasons, "; ")
					.. "); migrated as version "
					.. num(version)
			)
		end
	end

	while version < target do
		local step = steps[version]
		if step == nil then
			report:add("error", "migration.no_step", "schemaVersion", "no migration step from version " .. num(version))
			return nil, report.diagnostics
		end
		step.run(doc, report)
		report:add(
			"info",
			"migration.step",
			"schemaVersion",
			"schema " .. num(step.from) .. " -> " .. num(step.to) .. ": " .. step.description
		)
		version = step.to
	end
	doc.schemaVersion = target
	return doc :: any, report.diagnostics
end

return Migration
