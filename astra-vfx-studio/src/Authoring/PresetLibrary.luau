--!strict
--[[
	Authoring/PresetLibrary — the shipped preset effects (docs/MODULE_CONTRACTS.md §20, docs/ARCHITECTURE.md §3).

	Presets are src/Presets/<Name>.vfx.json. Rojo's syncRules ("use": "text", default.project.json) turn every file
	into a StringValue named <Name> whose Value is the raw JSON text (lossless, unlike Rojo's JSON -> ModuleScript
	conversion). The folder is reached as script.Parent.Parent.Presets (Authoring and Presets are siblings in the
	plugin tree).

	  PresetLibrary.list(folder?) -> { PresetInfo }     every StringValue child, sorted by name
	  PresetLibrary.get(nameOrId, folder?) -> EffectDefinition?   a deep copy of a valid preset, or nil
	  PresetLibrary.parse(text, source?) -> PresetInfo  one preset from JSON text (pure, uncached; e.g. for the CLI)
	  PresetLibrary.folder() -> Instance?               the default Presets folder (nil when it is missing)
	  PresetLibrary.count(folder?) -> number            number of presets list() returns (no parsing)
	  PresetLibrary.clearCache()                        drops the parse caches (tests)
	  `folder` (extension) lists another folder of preset StringValues instead of the default one.

	  PresetInfo = { name, id, description?, tags, valid, diagnostics, definition?, source }
	    definition   the migrated definition (Core/Migration), nil when the text is not a definition at all
	    valid        definition ~= nil and Core/Validation reports no errors (warnings are allowed)
	    diagnostics  migration diagnostics, then validation errors, warnings and infos (and preset.duplicate_id)
	    name / id    from the definition; name falls back to `source` and id to "" when there is no definition
	    tags         the definition's tags (strings only), else {}
	    source       the StringValue's name (the file name without ".vfx.json")

	Rules:
	  * Only direct StringValue children are presets; other children (folders, scripts, other values) are
	    ignored. Text that is not JSON gives valid = false with the migration.json diagnostic, never an error.
	  * Sorted by name (case-insensitive, then byte-wise), then id, then source, so the order is deterministic.
	  * Two presets with the same id: the first one in that order keeps it; the later ones get a
	    preset.duplicate_id warning (they stay valid but get(id) never returns them).
	  * get(nameOrId) looks for, in this order: an exact id, an exact name, an exact source name, then the same
	    three case-insensitively; only valid presets are returned. The result is a fresh deep copy (Json.NULL /
	    Json.EMPTY_OBJECT sentinels are kept by identity), so the caller may edit it.
	  * list() returns fresh tables too (deep copies of definitions and diagnostics). Parsed presets are cached
	    per folder by their text: a preset is parsed again only when its StringValue's text changes (e.g. live
	    Rojo sync), and each folder's cache only keeps the texts its latest list() / get() saw.
	  * The JSON text is decoded with Core/Json by Core/Migration (migrate accepts JSON text), so a syntax error
	    is the documented migration.json diagnostic with line and column.
]]

local Migration = require(script.Parent.Parent.AstraVFX.Core.Migration)
local Types = require(script.Parent.Parent.AstraVFX.Core.Types)
local Validation = require(script.Parent.Parent.AstraVFX.Core.Validation)

type EffectDefinition = Types.EffectDefinition
type Diagnostic = Types.Diagnostic

export type PresetInfo = {
	name: string,
	id: string,
	description: string?,
	tags: { string },
	valid: boolean,
	diagnostics: { Diagnostic },
	definition: EffectDefinition?,
	source: string,
}

type Parsed = {
	definition: EffectDefinition?,
	diagnostics: { Diagnostic },
	valid: boolean,
}

local PresetLibrary = {}

PresetLibrary.FOLDER_NAME = "Presets"

-- folder -> (text -> parsed preset). Weak keys: a destroyed / dropped folder takes its cache with it.
local caches: { [Instance]: { [string]: Parsed } } = setmetatable({}, { __mode = "k" }) :: any

-- Deep copy; tables with a metatable (Json.NULL / Json.EMPTY_OBJECT sentinels) are kept by identity.
local function deepCopy(v: any): any
	if type(v) ~= "table" or getmetatable(v) ~= nil then
		return v
	end
	local out = {}
	for k, x in next, v do
		out[deepCopy(k)] = deepCopy(x)
	end
	return out
end

local function parseText(text: string): Parsed
	local def, migration = Migration.migrate(text)
	local diagnostics: { Diagnostic } = table.clone(migration)
	if def == nil then
		return { definition = nil, diagnostics = diagnostics, valid = false }
	end
	local result = Validation.validate(def)
	for _, list in { result.errors, result.warnings, result.infos } do
		for _, d in list do
			table.insert(diagnostics, d)
		end
	end
	return { definition = def, diagnostics = diagnostics, valid = result.ok }
end

local function stringsOf(v: any): { string }
	local out: { string } = {}
	if type(v) == "table" then
		for _, s in ipairs(v) do
			if type(s) == "string" then
				table.insert(out, s)
			end
		end
	end
	return out
end

-- One preset of a folder (internal: holds the cached parse, never handed out).
type Entry = {
	parsed: Parsed,
	source: string,
	name: string,
	id: string,
	duplicateOf: string?, -- source of the earlier preset that keeps this id
}

local function entryOf(parsed: Parsed, source: string): Entry
	local def: any = parsed.definition
	local name = source
	local id = ""
	if def ~= nil then
		if type(def.name) == "string" and def.name ~= "" then
			name = def.name
		end
		if type(def.id) == "string" then
			id = def.id
		end
	end
	return { parsed = parsed, source = source, name = name, id = id, duplicateOf = nil }
end

-- A PresetInfo with fresh tables (the cached definition is never handed out).
local function info(entry: Entry): PresetInfo
	local parsed = entry.parsed
	local def: any = parsed.definition
	local diagnostics: { Diagnostic } = deepCopy(parsed.diagnostics)
	if entry.duplicateOf ~= nil then
		table.insert(diagnostics, {
			severity = "warning",
			code = "preset.duplicate_id",
			path = "id",
			message = string.format(
				"preset %q has the same id %q as %q; PresetLibrary.get returns %q",
				entry.source,
				entry.id,
				entry.duplicateOf,
				entry.duplicateOf
			),
			hint = "give every preset a unique id",
		})
	end
	return {
		name = entry.name,
		id = entry.id,
		description = if def ~= nil and type(def.description) == "string" then def.description else nil,
		tags = if def ~= nil then stringsOf(def.tags) else {},
		valid = parsed.valid,
		diagnostics = diagnostics,
		definition = deepCopy(def),
		source = entry.source,
	}
end

-- One preset from its JSON text (migrated + validated). `source` defaults to "".
function PresetLibrary.parse(text: string, source: string?): PresetInfo
	if type(text) ~= "string" then
		error("PresetLibrary.parse: text must be a string, got " .. typeof(text), 2)
	end
	return info(entryOf(parseText(text), source or ""))
end

-- The default Presets folder (script.Parent.Parent.Presets), or nil when it does not exist.
function PresetLibrary.folder(): Instance?
	local root = script.Parent and script.Parent.Parent
	if root == nil then
		return nil
	end
	return root:FindFirstChild(PresetLibrary.FOLDER_NAME)
end

local function entryLess(a: Entry, b: Entry): boolean
	local la, lb = string.lower(a.name), string.lower(b.name)
	if la ~= lb then
		return la < lb
	end
	if a.name ~= b.name then
		return a.name < b.name
	end
	if a.id ~= b.id then
		return a.id < b.id
	end
	return a.source < b.source
end

local function resolveFolder(fn: string, folder: Instance?): Instance?
	if folder == nil then
		return PresetLibrary.folder()
	end
	if typeof(folder) ~= "Instance" then
		error("PresetLibrary." .. fn .. ": folder must be an Instance, got " .. typeof(folder), 3)
	end
	return folder
end

-- The presets of a folder, sorted, with duplicate ids marked (parses through the folder's cache).
local function entries(folder: Instance?): { Entry }
	local out: { Entry } = {}
	if folder == nil then
		return out
	end
	local previous = caches[folder] or {}
	local seen: { [string]: Parsed } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("StringValue") then
			local text = (child :: StringValue).Value
			local parsed = seen[text] or previous[text] or parseText(text)
			seen[text] = parsed
			table.insert(out, entryOf(parsed, child.Name))
		end
	end
	caches[folder] = seen
	table.sort(out, entryLess)
	local owner: { [string]: Entry } = {}
	for _, entry in out do
		if entry.parsed.definition ~= nil and entry.id ~= "" then
			local first = owner[entry.id]
			if first == nil then
				owner[entry.id] = entry
			else
				entry.duplicateOf = first.source
			end
		end
	end
	return out
end

-- Every preset (StringValue child of the Presets folder or of `folder`), sorted by name. Fresh tables.
function PresetLibrary.list(folder: Instance?): { PresetInfo }
	local out: { PresetInfo } = {}
	for _, entry in entries(resolveFolder("list", folder)) do
		table.insert(out, info(entry))
	end
	return out
end

local function find(list: { Entry }, key: string, field: string, insensitive: boolean): Entry?
	local wanted = if insensitive then string.lower(key) else key
	for _, entry in list do
		local value: string = (entry :: any)[field]
		if value ~= "" and (if insensitive then string.lower(value) else value) == wanted then
			return entry
		end
	end
	return nil
end

-- A deep copy of the valid preset with this id, name or source name (see the header), or nil.
function PresetLibrary.get(nameOrId: string, folder: Instance?): EffectDefinition?
	if type(nameOrId) ~= "string" then
		error("PresetLibrary.get: nameOrId must be a string, got " .. typeof(nameOrId), 2)
	end
	local valid: { Entry } = {}
	local owners: { Entry } = {} -- duplicate ids: only the first preset with an id is found by it
	for _, entry in entries(resolveFolder("get", folder)) do
		if entry.parsed.valid and entry.parsed.definition ~= nil then
			table.insert(valid, entry)
			if entry.duplicateOf == nil then
				table.insert(owners, entry)
			end
		end
	end
	for _, insensitive in { false, true } do
		local hit = find(owners, nameOrId, "id", insensitive)
			or find(valid, nameOrId, "name", insensitive)
			or find(valid, nameOrId, "source", insensitive)
		if hit then
			return deepCopy(hit.parsed.definition)
		end
	end
	return nil
end

-- Number of presets list() would return (cheap: no parsing).
function PresetLibrary.count(folder: Instance?): number
	local f = resolveFolder("count", folder)
	if f == nil then
		return 0
	end
	local n = 0
	for _, child in f:GetChildren() do
		if child:IsA("StringValue") then
			n += 1
		end
	end
	return n
end

-- Drops every parse cache (tests; the editor never needs it).
function PresetLibrary.clearCache()
	table.clear(caches)
end

return PresetLibrary
