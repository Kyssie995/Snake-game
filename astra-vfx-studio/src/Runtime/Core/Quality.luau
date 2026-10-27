--!strict
--[[
	Quality — quality profiles (Low / Medium / High), per-effect overrides and client quality detection.
	See docs/MODULE_CONTRACTS.md §14 and docs/ARCHITECTURE.md §5.4.

	| level  | countScale | segmentScale | sizeCompensation | lightShadows   | maxLights            |
	|--------|------------|--------------|------------------|----------------|----------------------|
	| Low    | 0.35       | 0.5          | 1.12             | false          | 2                    |
	| Medium | 0.65       | 0.75         | 1.05             | false          | 4                    |
	| High   | 1          | 1            | 1                | true (as authored) | math.huge (unlimited) |

	Interpretation notes (where the contract leaves room):
	* PROFILES and the profiles in it are frozen. resolve() always returns a fresh, unfrozen copy, so callers may
	  keep or modify it without affecting other effects.
	* High's "unlimited" maxLights is math.huge (Quality.UNLIMITED); `lightCount >= profile.maxLights` comparisons
	  work unchanged. JSON encoders cannot write it (Json rejects inf), so encode profiles field by field.
	  High's lightShadows = true means "shadows as authored" (a light's own `shadows` property still decides).
	* resolve(level, overrides): level nil or "Auto" -> detect(). A QualityProfile table is accepted as the base too
	  (extension for Compiler options.quality); its invalid fields fall back to PROFILES[profile.level]. Any other
	  value is a programmer error (error); network input must be checked with Quality.isLevel first.
	  `overrides` is the definition's `quality` map ({ [QualityLevel]: QualityProfileOverride }); only the entry
	  of the resolved level is merged, field by field. Invalid values are ignored (the base value stays):
	    countScale, segmentScale  finite number >= 0
	    sizeCompensation          finite number > 0
	    lightShadows              boolean
	    maxLights                 whole number >= 0, or math.huge
	  Unknown fields (including `level`) and non-table overrides / entries are ignored.
	* detect(): only a live game client reads the player's setting. Not a client (server, CLI, Lune) or running
	  in Studio (edit mode, plugin preview, play tests: the editor passes its own preview level) -> "Medium".
	  On a client, UserSettings():GetService("UserGameSettings").SavedQualityLevel is read inside pcall (any
	  failure, e.g. no UserSettings global in Lune -> "Medium") and mapped by fromSavedQualityLevel:
	    QualityLevel1-3 -> Low   (the engine turns shadows off below level 4)
	    QualityLevel4-7 -> Medium
	    QualityLevel8-10 -> High
	    Automatic -> Medium      (the effective level is not readable by scripts; Medium is the safe middle)
	  This mapping is an ASSUMPTION (docs/research/vfx-design-performance.md B27-B31, §4.2 item 7).
	* rank(level): Low 1, Medium 2, High 3; anything else is an error. includes(level, minQuality): true when
	  minQuality is nil or rank(level) >= rank(minQuality); invalid levels are errors (Validation reports bad
	  minQuality values in definitions before they reach the Compiler).
]]

local Env = require(script.Parent.Env)
local Types = require(script.Parent.Types)

type QualityLevel = Types.QualityLevel
type QualityProfile = Types.QualityProfile
type QualityProfileOverride = Types.QualityProfileOverride

local Quality = {}

local INF = math.huge

local LEVELS: { QualityLevel } = { "Low", "Medium", "High" }
local DEFAULT_LEVEL: QualityLevel = "Medium"

Quality.LEVELS = table.freeze(LEVELS)
Quality.DEFAULT_LEVEL = DEFAULT_LEVEL
Quality.UNLIMITED = INF
-- Fields of QualityProfile / QualityProfileOverride that overrides may change, in a fixed order.
local OVERRIDE_FIELDS: { string } = { "countScale", "segmentScale", "sizeCompensation", "lightShadows", "maxLights" }
Quality.OVERRIDE_FIELDS = table.freeze(OVERRIDE_FIELDS)

local function makeProfile(
	level: QualityLevel,
	countScale: number,
	segmentScale: number,
	sizeCompensation: number,
	lightShadows: boolean,
	maxLights: number
): QualityProfile
	local profile: QualityProfile = {
		level = level,
		countScale = countScale,
		segmentScale = segmentScale,
		sizeCompensation = sizeCompensation,
		lightShadows = lightShadows,
		maxLights = maxLights,
	}
	return table.freeze(profile)
end

local LOW = makeProfile("Low", 0.35, 0.5, 1.12, false, 2)
local MEDIUM = makeProfile("Medium", 0.65, 0.75, 1.05, false, 4)
local HIGH = makeProfile("High", 1, 1, 1, true, INF)

Quality.PROFILES = table.freeze({ Low = LOW, Medium = MEDIUM, High = HIGH })

local BY_LEVEL: { [string]: QualityProfile } = { Low = LOW, Medium = MEDIUM, High = HIGH }
local RANK: { [string]: number } = { Low = 1, Medium = 2, High = 3 }

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local VALIDATORS: { [string]: (any) -> boolean } = {
	countScale = function(v: any): boolean
		return isFinite(v) and v >= 0
	end,
	segmentScale = function(v: any): boolean
		return isFinite(v) and v >= 0
	end,
	sizeCompensation = function(v: any): boolean
		return isFinite(v) and v > 0
	end,
	lightShadows = function(v: any): boolean
		return type(v) == "boolean"
	end,
	maxLights = function(v: any): boolean
		return type(v) == "number" and v >= 0 and (v == INF or v == math.floor(v))
	end,
}

local function describe(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return typeof(v) .. " " .. tostring(v)
end

-- True for "Low", "Medium" and "High".
function Quality.isLevel(value: any): boolean
	return type(value) == "string" and RANK[value] ~= nil
end

-- True when `value` is acceptable for the override field `field` (see the table in the header).
function Quality.isValidOverride(field: string, value: any): boolean
	local validator = VALIDATORS[field]
	return validator ~= nil and validator(value)
end

-- Low 1, Medium 2, High 3.
function Quality.rank(level: QualityLevel): number
	local rank = RANK[level :: any]
	if rank == nil then
		error("Quality.rank: unknown quality level " .. describe(level), 2)
	end
	return rank
end

-- True when a component with `minQuality` is built at `level` (nil minQuality: always).
function Quality.includes(level: QualityLevel, minQuality: QualityLevel?): boolean
	local rank = RANK[level :: any]
	if rank == nil then
		error("Quality.includes: unknown quality level " .. describe(level), 2)
	end
	if minQuality == nil then
		return true
	end
	local required = RANK[minQuality :: any]
	if required == nil then
		error("Quality.includes: unknown minQuality " .. describe(minQuality), 2)
	end
	return rank >= required
end

-- Maps Enum.SavedQualitySetting (EnumItem, its Name or its Value) to a level; nil if unrecognised.
function Quality.fromSavedQualityLevel(value: any): QualityLevel?
	local v: any = value
	if typeof(v) == "EnumItem" then
		v = v.Name
	end
	local n: number? = nil
	if type(v) == "string" then
		if v == "Automatic" then
			return "Medium"
		end
		local digits = string.match(v, "^QualityLevel(%d+)$")
		if digits then
			n = tonumber(digits)
		end
	elseif type(v) == "number" then
		if v == 0 then
			return "Medium" -- Automatic
		end
		n = v
	end
	if n == nil or n ~= math.floor(n) then
		return nil
	elseif n >= 1 and n <= 3 then
		return "Low"
	elseif n >= 4 and n <= 7 then
		return "Medium"
	elseif n >= 8 and n <= 10 then
		return "High"
	end
	return nil
end

local function readSavedQualityLevel(): any
	return UserSettings():GetService("UserGameSettings").SavedQualityLevel
end

-- The player's quality on a live client (SavedQualityLevel), otherwise "Medium". Never errors.
function Quality.detect(): QualityLevel
	if not Env.isClient() or Env.isStudio() then
		return DEFAULT_LEVEL
	end
	local ok, value = pcall(readSavedQualityLevel)
	if not ok then
		return DEFAULT_LEVEL
	end
	return Quality.fromSavedQualityLevel(value) or DEFAULT_LEVEL
end

local function copyProfile(source: any, fallback: QualityProfile): QualityProfile
	local out: any = table.clone(fallback)
	for _, field in OVERRIDE_FIELDS do
		local v = source[field]
		if v ~= nil and VALIDATORS[field](v) then
			out[field] = v
		end
	end
	return out
end

-- The profile for `level` ("Auto"/nil: detect()) with the matching entry of `overrides` merged in.
function Quality.resolve(
	level: (QualityLevel | "Auto" | QualityProfile)?,
	overrides: { [string]: QualityProfileOverride }?
): QualityProfile
	local requested: any = level
	local result: QualityProfile
	if requested == nil or requested == "Auto" then
		result = table.clone(BY_LEVEL[Quality.detect()])
	elseif type(requested) == "string" then
		local base = BY_LEVEL[requested]
		if base == nil then
			error("Quality.resolve: unknown quality level " .. describe(requested) .. " (Low, Medium, High, Auto)", 2)
		end
		result = table.clone(base)
	elseif type(requested) == "table" then
		local base = BY_LEVEL[requested.level]
		if base == nil then
			error("Quality.resolve: profile has an unknown level " .. describe(requested.level), 2)
		end
		result = copyProfile(requested, base)
	else
		error("Quality.resolve: expected a quality level or profile, got " .. describe(requested), 2)
	end
	local entries: any = overrides
	if type(entries) == "table" then
		local override = entries[result.level]
		if type(override) == "table" then
			result = copyProfile(override, result)
		end
	end
	return result
end

return Quality
