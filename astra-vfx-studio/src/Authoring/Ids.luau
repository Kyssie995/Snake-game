--!strict
--[[
	Ids — identifier helpers for the authoring layer (docs/MODULE_CONTRACTS.md §20).

	  Ids.slug(text, fallback?) -> string                 lower-case id slug ("Violet Impact" -> "violet-impact")
	  Ids.unique(base, taken) -> string                   `base`, or the next free "stem-N"; marks it taken
	  Ids.isValid(value) -> boolean                       [A-Za-z0-9_-]{1,64} (Constants.ID_PATTERN / ID_MAX_LENGTH)
	  Ids.collect(doc, into?) -> { [string]: boolean }    every id of the effect scope (see below)

	Ids are stable: renaming changes only `name`. Every id an authoring op generates is unique across the WHOLE
	effect scope — components, tracks, events, markers and graph nodes share one namespace — which is stricter
	than Validation (tracks / events only need to be unique per component) and keeps references unambiguous.
	The effect's own id is not part of the scope (a first component "Fire" in effect "fire" stays "fire").

	slug() is Migration.slug, so a name gives the same id whether a document is migrated, imported or created in
	the editor: runs of characters outside [a-z0-9_-] become "-", leading/trailing "-" are trimmed, at most
	Constants.ID_MAX_LENGTH characters; an empty result returns `fallback` (default "id").

	unique(base, taken): an invalid `base` is slugged first. When `base` is taken, a trailing "-N" is treated as a
	counter ("core-2" continues with "core-3") and the stem is cut so that "stem-N" stays within
	Constants.ID_MAX_LENGTH. Deterministic; the result is added to `taken`.
]]

local Constants = require(script.Parent.Parent.AstraVFX.Core.Constants)
local Migration = require(script.Parent.Parent.AstraVFX.Core.Migration)

local Ids = {}

local ID_PATTERN = Constants.ID_PATTERN
local ID_MAX_LENGTH = Constants.ID_MAX_LENGTH

-- True for a string of 1..ID_MAX_LENGTH characters of A-Z a-z 0-9 _ -.
function Ids.isValid(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= ID_MAX_LENGTH
		and string.match(value, ID_PATTERN) ~= nil
end

-- Lower-case id slug of `text` (Migration.slug); `fallback` (default "id") when nothing usable remains.
function Ids.slug(text: any, fallback: string?): string
	local fb = if Ids.isValid(fallback) then fallback :: string else "id"
	return Migration.slug(text, fb)
end

-- `base` when free, else the next free "stem-N". The returned id is marked as taken.
function Ids.unique(base: string, taken: { [string]: boolean }): string
	if type(taken) ~= "table" then
		error("Ids.unique: taken must be a table, got " .. typeof(taken), 2)
	end
	local candidate = if Ids.isValid(base) then base else Ids.slug(base)
	if not taken[candidate] then
		taken[candidate] = true
		return candidate
	end
	local stem, digits = string.match(candidate, "^(.-)%-(%d+)$")
	local n = 1
	if stem and digits and stem ~= "" and #digits <= 9 then
		n = tonumber(digits) or 1
	else
		stem = candidate
	end
	local root: string = stem :: string
	-- Every attempt yields a distinct candidate, so #taken + 1 attempts always find a free one.
	local attempts = 1
	for _ in pairs(taken) do
		attempts += 1
	end
	for _ = 1, attempts do
		n += 1
		local suffix = "-" .. n
		local cut = string.sub(root, 1, ID_MAX_LENGTH - #suffix)
		cut = string.gsub(cut, "%-+$", "")
		if cut == "" then
			cut = "id"
		end
		candidate = cut .. suffix
		if not taken[candidate] then
			taken[candidate] = true
			return candidate
		end
	end
	error("Ids.unique: no free id for " .. candidate) -- unreachable
end

local function addId(set: { [string]: boolean }, entry: any)
	if type(entry) == "table" and type(entry.id) == "string" then
		set[entry.id] = true
	end
end

local function each(list: any, fn: (any) -> ())
	if type(list) == "table" then
		for _, entry in ipairs(list) do
			fn(entry)
		end
	end
end

-- Set of every id in the effect scope: component, track, event, marker and graph node ids.
function Ids.collect(doc: any, into: { [string]: boolean }?): { [string]: boolean }
	local set: { [string]: boolean } = into or {}
	if type(doc) ~= "table" then
		return set
	end
	each(doc.components, function(component: any)
		addId(set, component)
		if type(component) == "table" then
			each(component.tracks, function(track: any)
				addId(set, track)
			end)
			each(component.events, function(event: any)
				addId(set, event)
			end)
		end
	end)
	each(doc.markers, function(marker: any)
		addId(set, marker)
	end)
	if type(doc.graph) == "table" then
		each(doc.graph.nodes, function(node: any)
			addId(set, node)
		end)
	end
	return set
end

return Ids
