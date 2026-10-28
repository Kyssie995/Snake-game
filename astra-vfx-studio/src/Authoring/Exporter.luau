--!strict
--[[
	Authoring/Exporter — reproducible exports of effect definitions (docs/MODULE_CONTRACTS.md §20,
	docs/ARCHITECTURE.md §8).

	  Exporter.toJson(def) -> string                     canonical pretty JSON + trailing newline (files, StringValues)
	  Exporter.toLuau(def) -> string                     ModuleScript source: header comment + "return { ... }"
	  Exporter.prune(def) -> EffectDefinition            the canonical view both writers encode (see "Pruning")
	  Exporter.buildRuntimePackage(runtimeModule, defs) -> ModuleScript   AstraVFX clone with an Effects folder
	  Exporter.buildStaticModel(def, options?) -> Model  the effect frozen at one time, as plain instances
	  Exporter.HEADER                                    first line of every toLuau source (ends with "\n")

	Reproducible: equal inputs give byte-identical text and identical instance trees. Object keys follow
	Constants.KEY_ORDER and then byte-wise order (Core/Json's rule), numbers are printed by Core/Json, nothing
	depends on table iteration order, the clock or the machine. No timestamps anywhere (no AstraExportedAt).

	Pruning (toJson and toLuau): empty OPTIONAL containers are dropped — effect tags, palette, markers, graph,
	quality, metadata; component transform, tracks, events, qualityOverrides; graph node params; empty
	quality / qualityOverrides levels; a graph whose members are all empty. `components` is always written (`[]`
	when empty) and an empty component `properties` is written as `{}`. Required containers (track keyframes,
	graph nodes / links) and values (property values, keyframe values, unknown fields, metadata contents) are
	never touched, so an invalid document stays exactly as invalid. prune() never mutates `def`; its result
	shares unchanged sub-tables with `def` (treat it as read-only).

	toJson(def): Json.encode(prune(def), { pretty = true }) .. "\n". toJson(decode(toJson(def))) == toJson(def).

	toLuau(def): Exporter.HEADER .. "return " .. <literal> .. "\n". The literal uses the same key order and number
	text as toJson; tab indentation; objects one member per line (`key = value,`), arrays of at most 8 scalars on
	one line (`{ 0, 1, 0 }`), other arrays one element per line, empty tables `{}`. Keys that are Luau identifiers
	(and not keywords) are bare, others are written as ["key"]. Strings are double-quoted with escapes for '"',
	'\', \n, \r, \t and \ddd (3-digit decimal) for every other control character and DEL; valid UTF-8 is kept as
	is (invalid UTF-8 is an error, as in Core/Json). Json.NULL (and anything else that is not plain JSON) cannot
	be written as a Luau table value and raises with its path. Loading the source returns a table deep-equal to
	prune(def) (numbers as Core/Json prints them: at most 6 decimals).

	buildRuntimePackage(runtimeModule, defs): runtimeModule must be the AstraVFX ModuleScript (one with a Core
	child). Every definition is migrated (Core/Migration) and validated first (an error lists the diagnostics
	through Authoring/Diagnostics, nothing is created); duplicate ids or names are errors. Then the module is
	cloned (`Clone()`; a module with Archivable = false cannot be cloned and raises), every child named "Effects"
	and the runtime-created Net folder (Net.FOLDER_NAME, stale remotes from a running game) are removed from the
	clone, and a Folder "Effects" gets one ModuleScript per definition, sorted by name (then id): Name = definition
	name, Source = toLuau(migrated definition), attributes AstraId and AstraSchemaVersion (as the plugin's storage
	writes them). The clone gets the attribute AstraVersion = Constants.VERSION (the exporting ASTRA version) and
	loses an inherited AstraExportedAt. The clone is returned unparented; the source module is not changed. The
	runtime registers the Effects folder lazily on the first Play / IsRegistered / GetNames.

	buildStaticModel(def, options?) — "Roblox Model Export", the effect as a static prop:
	  options = { time: number? (0), quality: "Low" | "Medium" | "High"? ("High"), scale: number?, seed: number?,
	              palette: { [string]: Color3 }?, cframe: CFrame? (identity),
	              stripAttributes: boolean? (true), unlock: boolean? (true) }
	  1. migrate + validate (errors raise with the diagnostics), Compiler.compile(def, { quality, scale, palette,
	     seed }); "Auto" is refused (an export must not depend on the machine).
	  2. Builder.build(compiled) (non-preview, so every instance is Archivable) into a temporary WorldModel: the
	     Player then moves the parts with that WorldModel's BulkMoveTo (a WorldRoot that contains them) instead of
	     Workspace's.
	  3. Player.new(compiled, built, { cframe, release = keep }) and player:seek(time) (clamped to [0, duration]):
	     the deterministic state at `time` without emission — bursts, sounds and "fire" events never run, live
	     particles are not simulated ahead (the engine cannot fast-forward them). seek leaves the copy paused;
	     one paused frame (player:step(0): "hold" evaluation, no actions, time frozen) ends the seek state of the
	     controllers (particles switch continuous emission off only while frame.seeking), then player:resume()
	     restores the engine clocks (paused = ParticleEmitter.TimeScale 0). So emitters that are active at `time`
	     keep emitting at their authored rate and time scale once the model is in the world; inactive ones stay
	     disabled. This is exactly what the editor shows after scrubbing to `time`, with the clocks running.
	  4. Every child of the container (the Root part with all attachments, the component parts) moves into a new
	     Model named after the effect, PrimaryPart = Root. stripAttributes removes the runtime attributes
	     (AstraEffect, AstraComponent, AstraPreview) from the model's instances; unlock sets Locked = false on every
	     BasePart (the runtime locks its parts so playing copies cannot be selected; a prop should be selectable
	     and movable). The Model gets the attributes AstraVersion and AstraEffectId (= definition id) and
	     AstraTime (= the clamped time).
	  5. The player is destroyed with a release callback that keeps the copy, then every controller's
	     `instances` list is emptied and its destroy() runs (camera bindings, screen effects under the camera and
	     other non-instance state are released, the moved instances are not touched), and the empty container and
	     the WorldModel are destroyed. On an error in steps 2-5 everything created so far is destroyed.
	  Components that are not active at `time` are part of the model as the runtime leaves them (invisible parts,
	  disabled emitters) so the structure stays complete; camera components have no instances.
]]

local Builder = require(script.Parent.Parent.AstraVFX.Core.Builder)
local Compiler = require(script.Parent.Parent.AstraVFX.Core.Compiler)
local Constants = require(script.Parent.Parent.AstraVFX.Core.Constants)
local Json = require(script.Parent.Parent.AstraVFX.Core.Json)
local Migration = require(script.Parent.Parent.AstraVFX.Core.Migration)
local Net = require(script.Parent.Parent.AstraVFX.Net)
local Player = require(script.Parent.Parent.AstraVFX.Core.Player)
local Types = require(script.Parent.Parent.AstraVFX.Core.Types)
local Validation = require(script.Parent.Parent.AstraVFX.Core.Validation)
local Diagnostics = require(script.Parent.Diagnostics)

type EffectDefinition = Types.EffectDefinition
type Diagnostic = Types.Diagnostic
type QualityLevel = Types.QualityLevel
type BuiltEffect = Builder.BuiltEffect

export type StaticModelOptions = {
	time: number?,
	quality: QualityLevel?,
	scale: number?,
	seed: number?,
	palette: { [string]: Color3 }?,
	cframe: CFrame?,
	stripAttributes: boolean?,
	unlock: boolean?,
}

local Exporter = {}

Exporter.HEADER = "-- Generated by ASTRA VFX Studio "
	.. Constants.VERSION
	.. ". Do not edit by hand; edit the effect and re-export.\n"

Exporter.EFFECTS_FOLDER = "Effects"
Exporter.MAX_LISTED_DIAGNOSTICS = 12

local EMPTY_OBJECT: any = Json.EMPTY_OBJECT
local NULL: any = Json.NULL
local MAX_DEPTH = Json.MAX_DEPTH
local INF = math.huge

local RUNTIME_ATTRIBUTES = { Constants.ATTR_EFFECT, Constants.ATTR_COMPONENT, Constants.ATTR_PREVIEW }
local QUALITY_NAMES: { [string]: boolean } = { Low = true, Medium = true, High = true }

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function describe(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return typeof(v)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Pruning
-- ─────────────────────────────────────────────────────────────────────────────

local EFFECT_OPTIONAL = { "tags", "palette", "markers", "graph", "quality", "metadata" }
local COMPONENT_OPTIONAL = { "transform", "tracks", "events", "qualityOverrides" }

local function isSentinel(v: any): boolean
	return rawequal(v, EMPTY_OBJECT) or rawequal(v, NULL)
end

-- An empty container (a plain empty table or Json.EMPTY_OBJECT; Json.NULL is a value, not a container).
local function isEmpty(v: any): boolean
	return type(v) == "table" and not rawequal(v, NULL) and next(v) == nil
end

local function isPlainTable(v: any): boolean
	return type(v) == "table" and not isSentinel(v)
end

-- Shallow copy of a plain table (callers never pass sentinels, which carry a metatable).
local function shallowCopy(t: { [any]: any }): { [any]: any }
	return table.clone(t)
end

local function dropEmpty(t: { [any]: any }, keys: { string })
	for _, key in keys do
		if isEmpty(t[key]) then
			t[key] = nil
		end
	end
end

-- Level map (quality / qualityOverrides) without empty levels. Non-maps (arrays too: removing an element would
-- leave a sparse table that cannot be encoded) are returned unchanged.
local function pruneLevels(map: any): any
	if not isPlainTable(map) or Json.isArray(map) then
		return map
	end
	local out = {}
	for level, value in next, map do
		if not isEmpty(value) then
			out[level] = value
		end
	end
	return out
end

local function pruneComponent(c: any): any
	if not isPlainTable(c) then
		return c
	end
	local out = shallowCopy(c)
	if out.qualityOverrides ~= nil then
		out.qualityOverrides = pruneLevels(out.qualityOverrides)
	end
	dropEmpty(out, COMPONENT_OPTIONAL)
	if isEmpty(out.properties) then
		out.properties = EMPTY_OBJECT
	end
	return out
end

local function pruneGraph(graph: any): any
	if not isPlainTable(graph) then
		return graph
	end
	local out = shallowCopy(graph)
	local nodes = out.nodes
	if isPlainTable(nodes) and next(nodes) ~= nil and Json.isArray(nodes) then
		local copy = table.create(#nodes)
		for i, node in nodes do
			if isPlainTable(node) and isEmpty(node.params) then
				local n = shallowCopy(node)
				n.params = nil
				copy[i] = n
			else
				copy[i] = node
			end
		end
		out.nodes = copy
	end
	for _, value in next, out do
		if not isEmpty(value) then
			return out
		end
	end
	return nil -- nothing but empty members (or no members at all)
end

-- The canonical view of `def` that toJson / toLuau encode (see "Pruning" in the header). Never mutates `def`.
function Exporter.prune(def: EffectDefinition): EffectDefinition
	local d: any = def
	if not isPlainTable(d) then
		error("Exporter.prune: expected an effect definition table, got " .. describe(d), 2)
	end
	local out = shallowCopy(d)
	local components = out.components
	if isEmpty(components) then
		out.components = {} -- `[]` (a decoded `{}` would print as an object)
	elseif isPlainTable(components) and Json.isArray(components) then
		local copy = table.create(#components)
		for i, c in components do
			copy[i] = pruneComponent(c)
		end
		out.components = copy
	end
	if out.graph ~= nil then
		out.graph = pruneGraph(out.graph)
	end
	if out.quality ~= nil then
		out.quality = pruneLevels(out.quality)
	end
	dropEmpty(out, EFFECT_OPTIONAL)
	return out :: any
end

local function checkDefinition(fn: string, def: any)
	if not isPlainTable(def) then
		error("Exporter." .. fn .. ": expected an effect definition table, got " .. describe(def), 3)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- JSON
-- ─────────────────────────────────────────────────────────────────────────────

-- Canonical pretty JSON with a trailing newline (byte-identical for equal inputs).
function Exporter.toJson(def: EffectDefinition): string
	checkDefinition("toJson", def)
	local pruned = Exporter.prune(def)
	local ok, result = pcall(Json.encode, pruned, { pretty = true })
	if not ok then
		error("Exporter.toJson: " .. tostring(result), 2)
	end
	return result .. "\n"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Luau
-- ─────────────────────────────────────────────────────────────────────────────

local KEY_RANK: { [string]: number } = {}
for i, key in Constants.KEY_ORDER do
	if KEY_RANK[key] == nil then
		KEY_RANK[key] = i
	end
end

-- Core/Json's key order: ranked keys first (by rank), then byte-wise.
local function keyLess(a: string, b: string): boolean
	local ra, rb = KEY_RANK[a], KEY_RANK[b]
	if ra ~= nil and rb ~= nil then
		return ra < rb
	elseif ra ~= nil then
		return true
	elseif rb ~= nil then
		return false
	end
	return a < b
end

-- Luau's reserved words, plus `continue` (contextual, bracketed to be safe everywhere).
local KEYWORDS: { [string]: boolean } = {}
for word in
	string.gmatch(
		"and break continue do else elseif end false for function if in local nil not or repeat return then true until while",
		"%a+"
	)
do
	KEYWORDS[word] = true
end

local function isIdentifier(key: string): boolean
	return string.find(key, "^[%a_][%w_]*$") ~= nil and not KEYWORDS[key]
end

local LUAU_ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
	["\127"] = "\\127",
}
for code = 0, 31 do
	local c = string.char(code)
	if LUAU_ESCAPES[c] == nil then
		LUAU_ESCAPES[c] = string.format("\\%03d", code)
	end
end
local LUAU_ESCAPE_PATTERN = '[%z\1-\31"\\\127]'

local INDENTS: { [number]: string } = {}
local function indentOf(level: number): string
	local s = INDENTS[level]
	if s == nil then
		s = string.rep("\t", level)
		INDENTS[level] = s
	end
	return s
end

local function formatPath(path: { any }, length: number): string
	if length == 0 then
		return "(root)"
	end
	local parts = table.create(length)
	for i = 1, length do
		local key = path[i]
		if type(key) == "number" then
			parts[i] = "[" .. tostring(key) .. "]"
		elseif type(key) == "string" and string.find(key, "^[%a_][%w_]*$") then
			parts[i] = if i == 1 then key else "." .. key
		else
			parts[i] = "[" .. string.format("%q", tostring(key)) .. "]"
		end
	end
	return table.concat(parts)
end

-- Luau table literal of a JSON-compatible value (see the header).
local function luauLiteral(value: any): string
	local out: { string } = {}
	local n = 0
	local path: { any } = {}
	local pathLength = 0
	local visiting: { [any]: boolean } = {}
	local quoted: { [string]: string } = {}
	local numbers: { [number]: string } = {}

	local fail: (message: string) -> never = function(message: string)
		error("Exporter.toLuau: " .. message .. " at " .. formatPath(path, pathLength), 0)
	end :: any

	local function push(s: string)
		n += 1
		out[n] = s
	end

	local function quote(s: string): string
		local q = quoted[s]
		if q == nil then
			if utf8.len(s) == nil then
				fail("string is not valid UTF-8")
			end
			q = '"' .. (string.gsub(s, LUAU_ESCAPE_PATTERN, LUAU_ESCAPES)) .. '"'
			quoted[s] = q
		end
		return q :: string
	end

	local function number(x: number): string
		local s = numbers[x]
		if s == nil then
			if not isFinite(x) then
				fail("cannot export non-finite number " .. tostring(x))
			end
			s = Json.encode(x)
			numbers[x] = s
		end
		return s :: string
	end

	local function isScalar(v: any): boolean
		local t = type(v)
		return t == "string" or t == "number" or t == "boolean"
	end

	local writeTable: (t: { [any]: any }, level: number) -> ()

	local function writeValue(v: any, level: number)
		local t = type(v)
		if t == "string" then
			push(quote(v))
		elseif t == "number" then
			push(number(v))
		elseif t == "boolean" then
			push(if v then "true" else "false")
		elseif rawequal(v, NULL) then
			fail("null cannot be written as a Luau table value (remove it or use a real value)")
		elseif rawequal(v, EMPTY_OBJECT) then
			push("{}")
		elseif t == "table" then
			writeTable(v, level)
		elseif t == "nil" then
			fail("cannot export nil")
		else
			fail("cannot export a value of type " .. typeof(v))
		end
	end

	writeTable = function(t: { [any]: any }, level: number)
		if pathLength + 1 > MAX_DEPTH then
			fail("nesting deeper than " .. MAX_DEPTH .. " levels")
		end
		if visiting[t] then
			fail("cyclic table reference")
		end
		local count, maxIndex = 0, 0
		local keys: { string } = {}
		for key in next, t do
			count += 1
			local kt = type(key)
			if kt == "string" then
				table.insert(keys, key)
			elseif kt == "number" and key >= 1 and key % 1 == 0 then
				if key > maxIndex then
					maxIndex = key
				end
			else
				fail("invalid table key " .. tostring(key) .. " (" .. typeof(key) .. "); object keys must be strings")
			end
		end
		if count == 0 then
			push("{}")
			return
		end
		if #keys > 0 and maxIndex > 0 then
			fail("mixed table (array indices and string keys)")
		end
		if #keys == 0 and maxIndex ~= count then
			fail("sparse array (" .. count .. " elements but highest index " .. maxIndex .. ")")
		end
		visiting[t] = true
		pathLength += 1
		local slot = pathLength
		local inner = indentOf(level + 1)
		if #keys == 0 then
			local inline = count <= 8
			if inline then
				for i = 1, count do
					if not isScalar(t[i]) then
						inline = false
						break
					end
				end
			end
			if inline then
				push("{ ")
				for i = 1, count do
					path[slot] = i
					if i > 1 then
						push(", ")
					end
					writeValue(t[i], level + 1)
				end
				push(" }")
			else
				push("{\n")
				for i = 1, count do
					path[slot] = i
					push(inner)
					writeValue(t[i], level + 1)
					push(",\n")
				end
				push(indentOf(level) .. "}")
			end
		else
			table.sort(keys, keyLess)
			push("{\n")
			for _, key in keys do
				path[slot] = key
				push(inner)
				push(if isIdentifier(key) then key else "[" .. quote(key) .. "]")
				push(" = ")
				writeValue(t[key], level + 1)
				push(",\n")
			end
			push(indentOf(level) .. "}")
		end
		path[slot] = nil
		pathLength -= 1
		visiting[t] = nil
	end

	writeValue(value, 0)
	return table.concat(out, "", 1, n)
end

-- ModuleScript source: Exporter.HEADER .. "return { ... }\n" (canonical Luau table literal of prune(def)).
function Exporter.toLuau(def: EffectDefinition): string
	checkDefinition("toLuau", def)
	return Exporter.HEADER .. "return " .. luauLiteral(Exporter.prune(def)) .. "\n"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Migration + validation for instance exports
-- ─────────────────────────────────────────────────────────────────────────────

-- "label (N errors):\n  <diagnostics>" (at most MAX_LISTED_DIAGNOSTICS listed).
local function errorText(label: string, errors: { Diagnostic }): string
	local n = #errors
	return label
		.. " ("
		.. n
		.. (if n == 1 then " error" else " errors")
		.. "):\n"
		.. Diagnostics.format(errors, { limit = Exporter.MAX_LISTED_DIAGNOSTICS, indent = "  " })
end

local function errorsOf(list: { Diagnostic }): { Diagnostic }
	local out: { Diagnostic } = {}
	for _, d in list do
		if d.severity == "error" then
			table.insert(out, d)
		end
	end
	return out
end

-- Migrated, validated definition or an error naming every problem.
local function prepare(fn: string, raw: any, label: string): EffectDefinition
	if type(raw) ~= "table" then
		error("Exporter." .. fn .. ": " .. label .. " must be an effect definition table, got " .. describe(raw), 0)
	end
	local def, migration = Migration.migrate(raw)
	if def == nil then
		error(errorText("Exporter." .. fn .. ": " .. label .. " is not an effect definition", errorsOf(migration)), 0)
	end
	local result = Validation.validate(def)
	if not result.ok then
		local name = if type(def.name) == "string" then def.name else tostring(def.id)
		error(
			errorText("Exporter." .. fn .. ": effect " .. string.format("%q", name) .. " is invalid", result.errors),
			0
		)
	end
	return def
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Runtime package
-- ─────────────────────────────────────────────────────────────────────────────

-- Clone of the AstraVFX module with a fresh Effects folder (one generated ModuleScript per definition).
function Exporter.buildRuntimePackage(runtimeModule: ModuleScript, defs: { EffectDefinition }): ModuleScript
	local source: any = runtimeModule
	if typeof(source) ~= "Instance" or not source:IsA("ModuleScript") then
		error(
			"Exporter.buildRuntimePackage: runtimeModule must be the AstraVFX ModuleScript, got " .. describe(source),
			2
		)
	end
	if source:FindFirstChild("Core") == nil then
		error(
			"Exporter.buildRuntimePackage: " .. source:GetFullName() .. " is not the AstraVFX runtime (it has no Core)",
			2
		)
	end
	if type(defs) ~= "table" then
		error("Exporter.buildRuntimePackage: defs must be an array of effect definitions, got " .. describe(defs), 2)
	end
	local prepared: { EffectDefinition } = {}
	local byId: { [string]: number } = {}
	local byName: { [string]: number } = {}
	for i, raw in ipairs(defs) do
		local def = prepare("buildRuntimePackage", raw, "defs[" .. i .. "]")
		if byId[def.id] ~= nil then
			error(
				"Exporter.buildRuntimePackage: defs["
					.. i
					.. "] has the same id "
					.. string.format("%q", def.id)
					.. " as defs["
					.. byId[def.id]
					.. "]",
				0
			)
		end
		if byName[def.name] ~= nil then
			error(
				"Exporter.buildRuntimePackage: defs["
					.. i
					.. "] has the same name "
					.. string.format("%q", def.name)
					.. " as defs["
					.. byName[def.name]
					.. "] (the ModuleScripts would collide)",
				0
			)
		end
		byId[def.id] = i
		byName[def.name] = i
		table.insert(prepared, def)
	end
	table.sort(prepared, function(a: EffectDefinition, b: EffectDefinition): boolean
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.id < b.id
	end)
	local sources: { string } = {}
	for i, def in prepared do
		sources[i] = Exporter.toLuau(def)
	end

	local clone: any = source:Clone()
	if clone == nil then
		error("Exporter.buildRuntimePackage: " .. source:GetFullName() .. " cannot be cloned (Archivable = false?)", 2)
	end
	for _, child in clone:GetChildren() do
		if child.Name == Exporter.EFFECTS_FOLDER or child.Name == Net.FOLDER_NAME then
			child:Destroy()
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = Exporter.EFFECTS_FOLDER
	for i, def in prepared do
		local module = Instance.new("ModuleScript")
		module.Name = def.name
		module.Source = sources[i]
		module:SetAttribute("AstraId", def.id)
		module:SetAttribute("AstraSchemaVersion", def.schemaVersion)
		module.Parent = folder
	end
	folder.Parent = clone
	clone:SetAttribute("AstraVersion", Constants.VERSION)
	clone:SetAttribute("AstraExportedAt", nil) -- never a timestamp (reproducible exports)
	return clone :: ModuleScript
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Static model
-- ─────────────────────────────────────────────────────────────────────────────

local function keepCopy(_built: BuiltEffect): boolean
	return true -- the copy stays alive: its instances move into the model
end

-- Releases every controller's non-instance state without touching the instances it created.
local function releaseControllers(built: BuiltEffect)
	for i = #built.order, 1, -1 do
		local controller = built.controllers[built.order[i]]
		if controller then
			table.clear(controller.instances)
			local ok, err = pcall(controller.destroy :: any, controller)
			if not ok then
				warn("[AstraVFX] Exporter: releasing component " .. built.order[i] .. " failed: " .. tostring(err))
			end
		end
	end
	built.destroyed = true
end

-- The effect evaluated at one time as a Model of plain instances (see the module header).
function Exporter.buildStaticModel(def: EffectDefinition, options: StaticModelOptions?): Model
	local o: StaticModelOptions = options or {}
	if type(o) ~= "table" then
		error("Exporter.buildStaticModel: options must be a table, got " .. describe(o), 2)
	end
	local time: any = if o.time == nil then 0 else o.time
	if not isFinite(time) then
		error("Exporter.buildStaticModel: time must be a finite number, got " .. tostring(time), 2)
	end
	local quality: any = if o.quality == nil then "High" else o.quality
	if type(quality) ~= "string" or not QUALITY_NAMES[quality] then
		error('Exporter.buildStaticModel: quality must be "Low", "Medium" or "High", got ' .. describe(quality), 2)
	end
	if o.scale ~= nil and not (isFinite(o.scale) and (o.scale :: number) > 0) then
		error("Exporter.buildStaticModel: scale must be a finite number > 0, got " .. tostring(o.scale), 2)
	end
	if o.seed ~= nil and not isFinite(o.seed) then
		error("Exporter.buildStaticModel: seed must be a finite number, got " .. tostring(o.seed), 2)
	end
	if o.cframe ~= nil and typeof(o.cframe) ~= "CFrame" then
		error("Exporter.buildStaticModel: cframe must be a CFrame, got " .. describe(o.cframe), 2)
	end
	if o.palette ~= nil and type(o.palette) ~= "table" then
		error("Exporter.buildStaticModel: palette must be a table of Color3 values, got " .. describe(o.palette), 2)
	end
	local migrated = prepare("buildStaticModel", def, "def")
	local compiled = Compiler.compile(migrated, {
		quality = quality :: QualityLevel,
		scale = if o.scale ~= nil then math.min(o.scale, Constants.MAX_SCALE) else nil,
		palette = o.palette,
		seed = o.seed,
	})
	local at = math.clamp(time, 0, math.max(compiled.duration, 0))

	local stage = Instance.new("WorldModel")
	stage.Name = "AstraVFX_Export"
	local built: BuiltEffect? = nil
	local model: Model? = nil
	local ok, err = pcall(function()
		local copy = Builder.build(compiled, { parent = stage :: Instance })
		built = copy
		local player = Player.new(compiled, copy, { cframe = o.cframe, release = keepCopy })
		player:seek(at) -- state "paused"
		player:step(0) -- one hold frame: no actions, ends the controllers' seek state
		player:resume() -- engine clocks back to the authored time scale (never stepped again)

		local m = Instance.new("Model")
		model = m
		m.Name = migrated.name
		for _, child in copy.container:GetChildren() do
			child.Parent = m
		end
		m.PrimaryPart = copy.root
		local everything = m:GetDescendants()
		if o.stripAttributes ~= false then
			for _, inst in everything do
				for _, attribute in RUNTIME_ATTRIBUTES do
					if inst:GetAttribute(attribute) ~= nil then
						inst:SetAttribute(attribute, nil)
					end
				end
			end
		end
		if o.unlock ~= false then
			for _, inst in everything do
				if inst:IsA("BasePart") then
					(inst :: BasePart).Locked = false
				end
			end
		end
		m:SetAttribute("AstraVersion", Constants.VERSION)
		m:SetAttribute("AstraEffectId", migrated.id)
		m:SetAttribute("AstraTime", at)

		player:destroy() -- keepCopy: the copy is not destroyed
		releaseControllers(copy)
		copy.container:Destroy()
	end)
	if not ok then
		local copy = built
		if copy ~= nil and not copy.destroyed then
			pcall(function()
				copy:destroy()
			end)
		end
		local m = model
		if m ~= nil then
			m:Destroy()
		end
		stage:Destroy()
		error("Exporter.buildStaticModel: " .. tostring(err), 2)
	end
	stage:Destroy()
	return model :: Model
end

return Exporter
