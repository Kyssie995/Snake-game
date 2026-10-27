--!strict
--[[
	Codec — converts property and channel values between their JSON form (EffectDefinition) and Roblox
	datatypes (CompiledEffect). See docs/MODULE_CONTRACTS.md §6.

	One canonicaliser per kind powers every entry point:

	  check(kind, value, spec)             strict, pure Luau: JSON form only, out-of-range values are errors
	  normalize(kind, value, spec)         lenient: clamps to spec.min/max, returns the canonical JSON form
	  decode(kind, value, spec, palette)   builds the Roblox value from normalize(value)
	  encode(kind, robloxValue, spec)      Roblox value -> canonical JSON form (same canonicaliser)

	so `normalize(x)` deep-equals `encode(decode(x))` for every valid x without "$palette" colours.

	Interpretation notes (where the contract leaves room):
	* Range rules (spec.min/max) apply to numbers, integers, vector components, both ends of a NumberRange and
	  the values of NumberSequence keypoints (not to envelopes or times). check() reports violations as problem
	  "range"; normalize/decode/encode clamp. Integers clamp to [ceil(min), floor(max)].
	* Structural problems (wrong type, NaN/inf, malformed keypoints, too many keypoints, enum names outside
	  spec.enum, bad colour strings, unknown palette keys) are never "fixed": check() returns false, the other
	  functions raise an error.
	* Roblox stores Vector3, Vector2, NumberRange and sequence keypoints as 32-bit floats. The canonical form of
	  those numbers is the shortest decimal that maps to the same float32 (0.1 stays 0.1, 1/3 -> 0.33333334),
	  so encode() strips float32 noise and agrees with normalize(). Plain number/integer kinds stay doubles.
	  Finite values beyond the float32 range are structural errors for those kinds. -0 becomes 0.
	* Colours: canonical "#RRGGBB" (uppercase) or "$key". "#RGB" expands; [r, g, b] (0..255) rounds to whole
	  numbers. Decoded colours are exactly Color3.fromRGB of the canonical hex. "$key" resolves through the
	  `palette` argument (Color3 values, clamped to 0..1; "#RRGGBB"-style strings are accepted as well); an
	  unknown key is an error (problem "ref"). Palette keys follow Constants.ID_PATTERN (1..64 characters).
	  check() cannot see the palette; Validation can use Codec.paletteRefs() to verify references.
	* Sequences: 2..min(spec.maxKeypoints or 20, 20) keypoints, times within 0..1 and non-descending, the first
	  exactly 0, the last exactly 1, envelope >= 0. Canonical keypoints omit a zero envelope. Exactly two
	  keypoints with the same value and zero envelopes collapse to the plain value (NumberSequence and
	  ColorSequence); a NumberRange with min == max collapses to the plain number.
	  A colorSequence array whose first element is a number is read as an [r, g, b] colour.
	* asset: integer ids and "http(s)://www.roblox.com/asset/?id=N" canonicalise to "rbxassetid://N";
	  "rbxassetid://N", "rbxasset://path" and "" are kept. encode() returns unrecognised engine strings unchanged.
	* enum: with spec.enum the name must be listed (case-sensitive). Without spec.enum any identifier passes
	  check(); decode() still requires a real Enum[spec.enumType] item. encode() returns EnumItem.Name even when
	  spec.enum does not list it.
	* string values must be valid UTF-8. componentRef: "" or an id matching Constants.ID_PATTERN (<= 64 chars);
	  existence and spec.componentTypes are Validation's job.
	* decode() also accepts a value that already has the decoded Roblox type (e.g. a Color3 for "color3"); it is
	  re-encoded first, so clamping still applies.
	* Extension: check() returns a third value naming the problem class ("type" | "range") so Validation can
	  pick property.type vs property.range.
	* lerp() does not clamp alpha (Back/Elastic overshoot); colour results are clamped to 0..1; booleans step to
	  `b` at alpha >= 1. alpha == 0 / 1 return `a` / `b` exactly.
]]

local Constants = require(script.Parent.Constants)
local Types = require(script.Parent.Types)

type PropertySpec = Types.PropertySpec
type ChannelSpec = Types.ChannelSpec

-- Minimal spec shape read by the codec. PropertySpec and ChannelSpec both qualify.
export type SpecLike = {
	min: number?,
	max: number?,
	enum: { string }?,
	enumType: string?,
	maxKeypoints: number?,
	default: any?,
}
export type Spec = PropertySpec | ChannelSpec | SpecLike
export type Palette = { [string]: Color3 }
-- "type": malformed value; "range": outside spec.min/max, spec.enum or the keypoint limit; "ref": palette key.
export type Problem = "type" | "range" | "ref"

local Codec = {}

Codec.KINDS = {
	"number",
	"integer",
	"boolean",
	"string",
	"enum",
	"color3",
	"vector3",
	"vector2",
	"numberRange",
	"numberSequence",
	"colorSequence",
	"asset",
	"componentRef",
}
Codec.CHANNEL_KINDS = { "number", "vector3", "color3", "boolean" }

local MAX_KEYPOINTS = Constants.MAX_SEQUENCE_KEYPOINTS
local MAX_SAFE_INTEGER = 2 ^ 53
local MAX_FLOAT32 = 3.4028234663852886e38
local MAX_EXACT_FLOAT32_INTEGER = 16777216
local INF = math.huge

type Ctx = {
	strict: boolean,
	min: number?,
	max: number?,
	enum: { string }?,
	enumType: string?,
	maxKeypoints: number,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Failures (structured errors caught by the public entry points)
-- ─────────────────────────────────────────────────────────────────────────────

local Failure = {}
Failure.__tostring = function(self: any): string
	return tostring(self.message)
end

local function fail(message: string, problem: Problem?): never
	error(setmetatable({ message = message, problem = problem or "type" }, Failure), 0)
end

-- Runs fn(...) and converts a Failure into (false, message, problem). Other errors are programmer errors and
-- propagate unchanged.
local function run(fn: any, ...: any): (boolean, any, Problem?)
	local ok, result = pcall(fn, ...)
	if ok then
		return true, result, nil
	end
	if type(result) == "table" and getmetatable(result) == Failure then
		return false, result.message, result.problem
	end
	error(result, 0)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Formatting helpers for error messages
-- ─────────────────────────────────────────────────────────────────────────────

local function fmt(n: number): string
	if n ~= n then
		return "NaN"
	elseif n == INF then
		return "inf"
	elseif n == -INF then
		return "-inf"
	elseif n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	return (string.format("%.9g", n))
end

-- Returns n when t is a proper array with keys exactly 1..n (0 for an empty table), else nil.
local function arrayLength(t: any): number?
	if type(t) ~= "table" then
		return nil
	end
	local count = 0
	local maxIndex = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
			return nil
		end
		count += 1
		if k > maxIndex then
			maxIndex = k
		end
	end
	if count ~= maxIndex then
		return nil
	end
	return count
end

local function describe(v: any): string
	local t = typeof(v)
	if t == "nil" then
		return "nil"
	elseif t == "number" then
		return fmt(v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		if #v > 40 then
			return string.format("%q", string.sub(v, 1, 37) .. "...")
		end
		return string.format("%q", v)
	elseif t == "table" then
		local n = arrayLength(v)
		if n == 0 then
			return "an empty table"
		elseif n == 1 then
			return "an array of 1 item"
		elseif n then
			return "an array of " .. n .. " items"
		end
		return "an object"
	end
	return "a " .. t .. " value"
end

-- ' (did you mean "Name"?)' when `name` matches a candidate case-insensitively.
local function caseHint(name: string, candidates: { string }): string
	local lower = string.lower(name)
	for _, c in candidates do
		if string.lower(c) == lower then
			return ' (did you mean "' .. c .. '"?)'
		end
	end
	return ""
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Numbers
-- ─────────────────────────────────────────────────────────────────────────────

local function readNumber(v: any, label: string): number
	if type(v) ~= "number" then
		return fail(label .. " must be a number, got " .. describe(v))
	end
	if v ~= v or v == INF or v == -INF then
		return fail(label .. " must be a finite number, got " .. fmt(v))
	end
	return v
end

-- A number that Roblox stores as float32 (vector components, ranges, keypoints).
local function readFloat(v: any, label: string): number
	local n = readNumber(v, label)
	if math.abs(n) > MAX_FLOAT32 then
		return fail(label .. " " .. fmt(n) .. " is too large (Roblox stores it as a 32-bit float)")
	end
	return n
end

local function limit(ctx: Ctx, n: number, label: string): number
	local lo, hi = ctx.min, ctx.max
	if lo ~= nil and n < lo then
		if ctx.strict then
			fail(label .. " " .. fmt(n) .. " is below the minimum " .. fmt(lo), "range")
		end
		n = lo
	end
	if hi ~= nil and n > hi then
		if ctx.strict then
			fail(label .. " " .. fmt(n) .. " is above the maximum " .. fmt(hi), "range")
		end
		n = hi
	end
	return n
end

local f32Scratch = buffer.create(4)

local function toFloat32(x: number): number
	buffer.writef32(f32Scratch, 0, x)
	return buffer.readf32(f32Scratch, 0)
end

local SHORT_FORMATS = { "%.6g", "%.7g", "%.8g", "%.9g" }

-- Shortest decimal that maps to the same float32 as x (9 significant digits always round-trip).
local function canonFloat(x: number): number
	local v = toFloat32(x)
	if v == 0 then
		return 0
	end
	if v == math.floor(v) and math.abs(v) <= MAX_EXACT_FLOAT32_INTEGER then
		return v
	end
	for _, f in SHORT_FORMATS do
		local n = tonumber(string.format(f, v))
		if n ~= nil and toFloat32(n) == v then
			return n
		end
	end
	return v
end

local function canonLimitedFloat(ctx: Ctx, v: any, label: string): number
	return canonFloat(limit(ctx, readFloat(v, label), label))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Colours
-- ─────────────────────────────────────────────────────────────────────────────

local RGB_NAMES = { "red", "green", "blue" }
local COLOUR_FORMS = '"#RRGGBB", "#RGB", [r, g, b] (0-255) or "$paletteKey"'

local function isPaletteKey(key: string): boolean
	return #key >= 1 and #key <= Constants.ID_MAX_LENGTH and string.match(key, Constants.ID_PATTERN) ~= nil
end

-- Canonical colour string ("#RRGGBB" uppercase or "$key"). `where` prefixes messages ("" or "keypoint 2: ").
local function canonColor(v: any, where: string): string
	if type(v) == "string" then
		if string.sub(v, 1, 1) == "$" then
			if not isPaletteKey(string.sub(v, 2)) then
				return fail(
					where
						.. "invalid palette reference "
						.. describe(v)
						.. ' (expected "$" followed by 1-64 letters, digits, "_" or "-")'
				)
			end
			return v
		end
		local hex = string.match(v, "^#(%x+)$")
		if hex and #hex == 6 then
			return "#" .. string.upper(hex)
		elseif hex and #hex == 3 then
			local r, g, b = string.sub(hex, 1, 1), string.sub(hex, 2, 2), string.sub(hex, 3, 3)
			return string.upper("#" .. r .. r .. g .. g .. b .. b)
		end
		return fail(where .. "invalid colour " .. describe(v) .. " (expected " .. COLOUR_FORMS .. ")")
	elseif type(v) == "table" then
		if arrayLength(v) ~= 3 then
			return fail(where .. "a colour array must be [r, g, b] with 3 numbers 0-255, got " .. describe(v))
		end
		local c = {}
		for i = 1, 3 do
			local label = where .. RGB_NAMES[i] .. " component"
			local x = readNumber(v[i], label)
			if x < 0 or x > 255 then
				return fail(label .. " " .. fmt(x) .. " is outside 0-255")
			end
			c[i] = math.floor(x + 0.5)
		end
		return string.format("#%02X%02X%02X", c[1], c[2], c[3])
	end
	return fail(where .. "expected a colour (" .. COLOUR_FORMS .. "), got " .. describe(v))
end

local function channel255(x: number): number
	if x ~= x then
		return 0
	end
	return math.floor(math.clamp(x, 0, 1) * 255 + 0.5)
end

local function toHex(color: Color3): string
	return string.format("#%02X%02X%02X", channel255(color.R), channel255(color.G), channel255(color.B))
end

local function clamp01(x: number): number
	if x ~= x then
		return 0
	end
	return math.clamp(x, 0, 1)
end

local function clampColor(c: Color3): Color3
	local r, g, b = c.R, c.G, c.B
	if r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 then
		return c
	end
	return Color3.new(clamp01(r), clamp01(g), clamp01(b))
end

-- "#RRGGBB" (canonical) -> Color3
local function hexToColor(hex: string): Color3
	local r = tonumber(string.sub(hex, 2, 3), 16) :: number
	local g = tonumber(string.sub(hex, 4, 5), 16) :: number
	local b = tonumber(string.sub(hex, 6, 7), 16) :: number
	return Color3.fromRGB(r, g, b)
end

-- Canonical colour -> Color3, resolving "$key" through the palette.
local function resolveColor(canon: string, palette: Palette?, where: string): Color3
	if string.sub(canon, 1, 1) ~= "$" then
		return hexToColor(canon)
	end
	local key = string.sub(canon, 2)
	local entry: any = if palette then palette[key] else nil
	if typeof(entry) == "Color3" then
		return clampColor(entry)
	elseif type(entry) == "string" and string.sub(entry, 1, 1) ~= "$" then
		local ok, hex = run(canonColor, entry, "")
		if ok then
			return hexToColor(hex)
		end
	end
	return fail(
		where .. "unknown palette colour " .. describe(canon) .. (if palette then "" else " (no palette given)"),
		"ref"
	)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Canonicalisers: JSON form -> canonical JSON form (strict: range errors; lenient: clamp)
-- ─────────────────────────────────────────────────────────────────────────────

type Canon = (ctx: Ctx, v: any) -> any

local CANON: { [string]: Canon } = {}

CANON.number = function(ctx: Ctx, v: any): any
	local n = limit(ctx, readNumber(v, "value"), "value")
	if n == 0 then
		n = 0 -- drop -0
	end
	return n
end

CANON.integer = function(ctx: Ctx, v: any): any
	local n = readNumber(v, "value")
	if n ~= math.floor(n) then
		return fail("value must be a whole number, got " .. fmt(n))
	end
	if math.abs(n) > MAX_SAFE_INTEGER then
		return fail("whole number " .. fmt(n) .. " is too large (limit 2^53)")
	end
	local lo = ctx.min
	local hi = ctx.max
	if lo ~= nil and n < math.ceil(lo) then
		if ctx.strict then
			fail("value " .. fmt(n) .. " is below the minimum " .. fmt(lo), "range")
		end
		n = math.ceil(lo)
	end
	if hi ~= nil and n > math.floor(hi) then
		if ctx.strict then
			fail("value " .. fmt(n) .. " is above the maximum " .. fmt(hi), "range")
		end
		n = math.floor(hi)
	end
	if n == 0 then
		n = 0
	end
	return n
end

CANON.boolean = function(_ctx: Ctx, v: any): any
	if type(v) ~= "boolean" then
		return fail("value must be true or false, got " .. describe(v))
	end
	return v
end

CANON.string = function(_ctx: Ctx, v: any): any
	if type(v) ~= "string" then
		return fail("value must be a string, got " .. describe(v))
	end
	if utf8.len(v) == nil then
		return fail("string is not valid UTF-8")
	end
	return v
end

CANON.enum = function(ctx: Ctx, v: any): any
	if type(v) ~= "string" then
		return fail("value must be an enum item name (string), got " .. describe(v))
	end
	local allowed = ctx.enum
	if allowed then
		if table.find(allowed, v) == nil then
			return fail(
				describe(v) .. " is not one of: " .. table.concat(allowed, ", ") .. caseHint(v, allowed),
				"range"
			)
		end
	elseif string.match(v, "^[%a_][%w_]*$") == nil then
		return fail("invalid enum item name " .. describe(v))
	end
	return v
end

CANON.color3 = function(_ctx: Ctx, v: any): any
	return canonColor(v, "")
end

local AXES = { "X", "Y", "Z" }

local function canonVector(ctx: Ctx, v: any, n: number): { number }
	local out = {}
	if type(v) == "number" then
		local x = canonLimitedFloat(ctx, v, "value")
		for i = 1, n do
			out[i] = x
		end
		return out
	end
	if arrayLength(v) ~= n then
		return fail(
			"expected " .. (if n == 3 then "[x, y, z]" else "[x, y]") .. " or a single number, got " .. describe(v)
		)
	end
	for i = 1, n do
		out[i] = canonLimitedFloat(ctx, v[i], AXES[i] .. " component")
	end
	return out
end

CANON.vector3 = function(ctx: Ctx, v: any): any
	return canonVector(ctx, v, 3)
end

CANON.vector2 = function(ctx: Ctx, v: any): any
	return canonVector(ctx, v, 2)
end

CANON.numberRange = function(ctx: Ctx, v: any): any
	if type(v) == "number" then
		return canonLimitedFloat(ctx, v, "value")
	end
	if arrayLength(v) ~= 2 then
		return fail("expected a number or [min, max], got " .. describe(v))
	end
	local lo = readFloat(v[1], "range min")
	local hi = readFloat(v[2], "range max")
	if lo > hi then
		return fail("range min " .. fmt(lo) .. " is greater than range max " .. fmt(hi))
	end
	lo = canonFloat(limit(ctx, lo, "range min"))
	hi = canonFloat(limit(ctx, hi, "range max"))
	if lo == hi then
		return lo
	end
	return { lo, hi }
end

-- Validates the keypoint array itself; returns its length.
local function keypointCount(ctx: Ctx, v: any, forms: string): number
	local len = arrayLength(v)
	if len == nil or len == 0 then
		return fail("expected " .. forms .. ", got " .. describe(v))
	end
	if len < 2 then
		return fail("a sequence needs at least 2 keypoints (the first at time 0, the last at time 1), got 1")
	end
	if len > ctx.maxKeypoints then
		return fail("sequence has " .. len .. " keypoints; at most " .. ctx.maxKeypoints .. " are allowed", "range")
	end
	return len
end

-- Validates keypoint i's time against the engine rules; returns the raw time.
local function keypointTime(kp: { any }, i: number, len: number, previous: number): number
	local label = "keypoint " .. i .. " time"
	local t = readNumber(kp[1], label)
	if t < 0 or t > 1 then
		return fail(label .. " " .. fmt(t) .. " is outside 0..1")
	end
	if i == 1 and t ~= 0 then
		return fail("the first keypoint must be at time 0, got " .. fmt(t))
	end
	if i == len and t ~= 1 then
		return fail("the last keypoint must be at time 1, got " .. fmt(t))
	end
	if t < previous then
		return fail(
			label
				.. " "
				.. fmt(t)
				.. " is before the previous keypoint's time "
				.. fmt(previous)
				.. " (times must not decrease)"
		)
	end
	return t
end

CANON.numberSequence = function(ctx: Ctx, v: any): any
	if type(v) == "number" then
		return canonLimitedFloat(ctx, v, "value")
	end
	local len = keypointCount(ctx, v, "a number or keypoints [[time, value, envelope?], ...]")
	local out = {}
	local previous = 0
	for i = 1, len do
		local kp = v[i]
		local n = arrayLength(kp)
		if n ~= 2 and n ~= 3 then
			return fail("keypoint " .. i .. " must be [time, value] or [time, value, envelope], got " .. describe(kp))
		end
		local t = keypointTime(kp, i, len, previous)
		previous = t
		local value = canonLimitedFloat(ctx, kp[2], "keypoint " .. i .. " value")
		local envelope = 0
		if n == 3 then
			local label = "keypoint " .. i .. " envelope"
			envelope = readFloat(kp[3], label)
			if envelope < 0 then
				return fail(label .. " " .. fmt(envelope) .. " must not be negative")
			end
			envelope = canonFloat(envelope)
		end
		if envelope > 0 then
			out[i] = { canonFloat(t), value, envelope }
		else
			out[i] = { canonFloat(t), value }
		end
	end
	if len == 2 and #out[1] == 2 and #out[2] == 2 and out[1][2] == out[2][2] then
		return out[1][2]
	end
	return out
end

CANON.colorSequence = function(ctx: Ctx, v: any): any
	if type(v) == "string" or (type(v) == "table" and type(v[1]) == "number") then
		return canonColor(v, "")
	end
	local len = keypointCount(ctx, v, "a colour or keypoints [[time, colour], ...]")
	local out: { { any } } = {}
	local previous = 0
	for i = 1, len do
		local kp = v[i]
		if arrayLength(kp) ~= 2 then
			return fail("keypoint " .. i .. " must be [time, colour], got " .. describe(kp))
		end
		local t = keypointTime(kp, i, len, previous)
		previous = t
		out[i] = { canonFloat(t), canonColor(kp[2], "keypoint " .. i .. ": ") }
	end
	if len == 2 and out[1][2] == out[2][2] then
		return out[1][2]
	end
	return out
end

local ASSET_FORMS = '"rbxassetid://123", "rbxasset://path", "https://www.roblox.com/asset/?id=123", 123 or ""'

CANON.asset = function(_ctx: Ctx, v: any): any
	if type(v) == "number" then
		if v ~= v or v ~= math.floor(v) or v < 1 or v > MAX_SAFE_INTEGER then
			return fail("asset id must be a positive whole number, got " .. fmt(v))
		end
		return "rbxassetid://" .. string.format("%.0f", v)
	end
	if type(v) ~= "string" then
		return fail("expected an asset (" .. ASSET_FORMS .. "), got " .. describe(v))
	end
	if v == "" or string.match(v, "^rbxassetid://%d+$") or string.match(v, "^rbxasset://%S+$") then
		return v
	end
	local id = string.match(v, "^https?://www%.roblox%.com/asset/%?id=(%d+)$")
	if id then
		return "rbxassetid://" .. id
	end
	return fail("invalid asset " .. describe(v) .. " (expected " .. ASSET_FORMS .. ")")
end

CANON.componentRef = function(_ctx: Ctx, v: any): any
	if type(v) ~= "string" then
		return fail('expected a component id or "", got ' .. describe(v))
	end
	if v ~= "" and (#v > Constants.ID_MAX_LENGTH or string.match(v, Constants.ID_PATTERN) == nil) then
		return fail(
			"invalid component id "
				.. describe(v)
				.. ' (1-'
				.. Constants.ID_MAX_LENGTH
				.. ' letters, digits, "_" or "-"; "" for none)'
		)
	end
	return v
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Builders: canonical JSON form -> Roblox value
-- ─────────────────────────────────────────────────────────────────────────────

type Build = (c: any, ctx: Ctx, palette: Palette?) -> any

local function identity(c: any, _ctx: Ctx, _palette: Palette?): any
	return c
end

local BUILD: { [string]: Build } = {
	number = identity,
	integer = identity,
	boolean = identity,
	string = identity,
	asset = identity,
	componentRef = identity,
}

BUILD.enum = function(c: any, ctx: Ctx, _palette: Palette?): any
	local enumType = ctx.enumType
	if enumType == nil then
		return c
	end
	local ok, item = pcall(function()
		return (Enum :: any)[enumType][c]
	end)
	if not ok or typeof(item) ~= "EnumItem" then
		return fail(describe(c) .. " is not an item of Enum." .. enumType)
	end
	return item
end

BUILD.color3 = function(c: any, _ctx: Ctx, palette: Palette?): any
	return resolveColor(c, palette, "")
end

BUILD.vector3 = function(c: any, _ctx: Ctx, _palette: Palette?): any
	return Vector3.new(c[1], c[2], c[3])
end

BUILD.vector2 = function(c: any, _ctx: Ctx, _palette: Palette?): any
	return Vector2.new(c[1], c[2])
end

BUILD.numberRange = function(c: any, _ctx: Ctx, _palette: Palette?): any
	if type(c) == "number" then
		return NumberRange.new(c, c)
	end
	return NumberRange.new(c[1], c[2])
end

BUILD.numberSequence = function(c: any, _ctx: Ctx, _palette: Palette?): any
	local keys: { NumberSequenceKeypoint } = {}
	if type(c) == "number" then
		keys[1] = NumberSequenceKeypoint.new(0, c, 0)
		keys[2] = NumberSequenceKeypoint.new(1, c, 0)
	else
		for i, kp in c do
			keys[i] = NumberSequenceKeypoint.new(kp[1], kp[2], kp[3] or 0)
		end
	end
	return NumberSequence.new(keys)
end

BUILD.colorSequence = function(c: any, _ctx: Ctx, palette: Palette?): any
	local keys: { ColorSequenceKeypoint } = {}
	if type(c) == "string" then
		local color = resolveColor(c, palette, "")
		keys[1] = ColorSequenceKeypoint.new(0, color)
		keys[2] = ColorSequenceKeypoint.new(1, color)
	else
		for i, kp in c do
			keys[i] = ColorSequenceKeypoint.new(kp[1], resolveColor(kp[2], palette, "keypoint " .. i .. ": "))
		end
	end
	return ColorSequence.new(keys)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Encoders: Roblox value -> canonical JSON form
-- ─────────────────────────────────────────────────────────────────────────────

local function wrongType(expected: string, v: any): never
	return fail("expected " .. expected .. ", got " .. describe(v))
end

local ENCODE: { [string]: Canon } = {}

ENCODE.number = function(ctx: Ctx, v: any): any
	if type(v) ~= "number" then
		return wrongType("a number", v)
	end
	return CANON.number(ctx, v)
end

ENCODE.integer = function(ctx: Ctx, v: any): any
	if type(v) ~= "number" then
		return wrongType("a number", v)
	end
	return CANON.integer(ctx, if v == v then math.floor(v + 0.5) else v)
end

ENCODE.boolean = CANON.boolean

ENCODE.string = function(_ctx: Ctx, v: any): any
	if type(v) ~= "string" then
		return wrongType("a string", v)
	end
	return v
end

ENCODE.enum = function(_ctx: Ctx, v: any): any
	if typeof(v) == "EnumItem" then
		return (v :: EnumItem).Name
	elseif type(v) == "string" then
		return v
	end
	return wrongType("an EnumItem", v)
end

ENCODE.color3 = function(_ctx: Ctx, v: any): any
	if typeof(v) ~= "Color3" then
		return wrongType("a Color3", v)
	end
	return toHex(v)
end

ENCODE.vector3 = function(ctx: Ctx, v: any): any
	if typeof(v) ~= "Vector3" then
		return wrongType("a Vector3", v)
	end
	local vec = v :: Vector3
	return canonVector(ctx, { vec.X, vec.Y, vec.Z }, 3)
end

ENCODE.vector2 = function(ctx: Ctx, v: any): any
	if typeof(v) ~= "Vector2" then
		return wrongType("a Vector2", v)
	end
	local vec = v :: Vector2
	return canonVector(ctx, { vec.X, vec.Y }, 2)
end

ENCODE.numberRange = function(ctx: Ctx, v: any): any
	if typeof(v) ~= "NumberRange" then
		return wrongType("a NumberRange", v)
	end
	local range = v :: NumberRange
	return CANON.numberRange(ctx, { range.Min, range.Max })
end

ENCODE.numberSequence = function(ctx: Ctx, v: any): any
	if typeof(v) ~= "NumberSequence" then
		return wrongType("a NumberSequence", v)
	end
	local raw = {}
	for i, kp in (v :: NumberSequence).Keypoints do
		raw[i] = { kp.Time, kp.Value, kp.Envelope }
	end
	return CANON.numberSequence(ctx, raw)
end

ENCODE.colorSequence = function(ctx: Ctx, v: any): any
	if typeof(v) == "Color3" then
		return toHex(v)
	elseif typeof(v) ~= "ColorSequence" then
		return wrongType("a ColorSequence", v)
	end
	local raw: { { any } } = {}
	for i, kp in (v :: ColorSequence).Keypoints do
		raw[i] = { kp.Time, toHex(kp.Value) }
	end
	return CANON.colorSequence(ctx, raw)
end

ENCODE.asset = function(ctx: Ctx, v: any): any
	local value: any = v
	if typeof(v) == "Content" then
		local uri = (v :: any).Uri
		value = if type(uri) == "string" then uri else ""
	end
	if type(value) ~= "string" and type(value) ~= "number" then
		return wrongType("an asset string", v)
	end
	local ok, result = run(CANON.asset, ctx, value)
	if ok then
		return result
	elseif type(value) == "string" then
		return value -- engine strings we do not recognise (rbxthumb://, other URLs) are kept verbatim
	end
	return fail(result)
end

ENCODE.componentRef = ENCODE.string

-- Roblox types decode() passes through (re-encoded first).
local DECODED_TYPE: { [string]: string } = {
	enum = "EnumItem",
	color3 = "Color3",
	vector3 = "Vector3",
	vector2 = "Vector2",
	numberRange = "NumberRange",
	numberSequence = "NumberSequence",
	colorSequence = "ColorSequence",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

local function makeCtx(spec: Spec?, strict: boolean, level: number): Ctx
	local s: any = spec
	if s ~= nil and type(s) ~= "table" then
		error("Codec: spec must be a PropertySpec/ChannelSpec table, got " .. typeof(s), level)
	end
	local function num(x: any): number?
		return if type(x) == "number" and x == x then x else nil
	end
	local maxKeys = MAX_KEYPOINTS
	local specMax = s and num(s.maxKeypoints)
	if specMax then
		maxKeys = math.clamp(math.floor(specMax), 2, MAX_KEYPOINTS)
	end
	return {
		strict = strict,
		min = s and num(s.min),
		max = s and num(s.max),
		enum = if s and type(s.enum) == "table" then s.enum else nil,
		enumType = if s and type(s.enumType) == "string" then s.enumType else nil,
		maxKeypoints = maxKeys,
	}
end

local function kindError(fnName: string, kind: any): never
	error("Codec." .. fnName .. ": unknown value kind " .. describe(kind), 3)
end

-- Checks a JSON-form value against the kind and spec. Returns (true) or (false, message, problem).
function Codec.check(kind: string, value: any, spec: Spec?): (boolean, string?, Problem?)
	local canon = CANON[kind]
	if canon == nil then
		return false, "unknown value kind " .. describe(kind), "type" :: Problem
	end
	local ok: boolean, result: any, problem: Problem? = run(canon, makeCtx(spec, true, 3), value)
	if ok then
		return true, nil, nil
	end
	return false, result, problem
end

-- Canonical JSON form of a JSON value (clamped to spec.min/max). Errors on structurally invalid values.
function Codec.normalize(kind: string, value: any, spec: Spec?): any
	local canon = CANON[kind]
	if canon == nil then
		return kindError("normalize", kind)
	end
	local ok, result = run(canon, makeCtx(spec, false, 3), value)
	if not ok then
		error("Codec.normalize(" .. kind .. "): " .. tostring(result), 2)
	end
	return result
end

-- JSON form -> Roblox datatype (clamped). "$key" colours resolve through `palette`. Errors on invalid values.
function Codec.decode(kind: string, value: any, spec: Spec?, palette: Palette?): any
	local canon = CANON[kind]
	local build = BUILD[kind]
	if canon == nil or build == nil then
		return kindError("decode", kind)
	end
	local ctx = makeCtx(spec, false, 3)
	local ok, result = run(function()
		local decodedType = DECODED_TYPE[kind]
		local c
		if decodedType ~= nil and typeof(value) == decodedType then
			c = ENCODE[kind](ctx, value)
		else
			c = canon(ctx, value)
		end
		return build(c, ctx, palette)
	end)
	if not ok then
		error("Codec.decode(" .. kind .. "): " .. tostring(result), 2)
	end
	return result
end

-- Roblox datatype -> canonical JSON form (clamped to spec.min/max). Errors when the value has the wrong type.
function Codec.encode(kind: string, robloxValue: any, spec: Spec?): any
	local encoder = ENCODE[kind]
	if encoder == nil then
		return kindError("encode", kind)
	end
	local ctx = makeCtx(spec, false, 3)
	ctx.maxKeypoints = INF
	ctx.enum = nil
	local ok, result = run(encoder, ctx, robloxValue)
	if not ok then
		error("Codec.encode(" .. kind .. "): " .. tostring(result), 2)
	end
	return result
end

local function deepCopy(v: any): any
	if type(v) ~= "table" or getmetatable(v) ~= nil then
		return v -- tables with metatables are sentinels/objects (e.g. Json.EMPTY_OBJECT): keep identity
	end
	local out = {}
	for k, x in pairs(v) do
		out[deepCopy(k)] = deepCopy(x)
	end
	return out
end

-- Deep copy of spec.default (safe to mutate).
function Codec.default(spec: Spec): any
	local s: any = spec
	if type(s) ~= "table" then
		error("Codec.default: spec must be a table, got " .. typeof(s), 2)
	end
	return deepCopy(s.default)
end

-- Parses any accepted colour form (or a Color3) into a Color3; nil when invalid or the palette key is unknown.
function Codec.parseColor(value: any, palette: Palette?): Color3?
	if typeof(value) == "Color3" then
		return value
	end
	local ok, result = run(function()
		return resolveColor(canonColor(value, ""), palette, "")
	end)
	return if ok then result else nil
end

-- Color3 -> "#RRGGBB" (uppercase; components clamped to 0..1 and rounded to 0..255).
function Codec.toHex(color: Color3): string
	if typeof(color) ~= "Color3" then
		error("Codec.toHex: expected a Color3, got " .. typeof(color), 2)
	end
	return toHex(color)
end

-- Interpolates two decoded channel values. alpha is not clamped (overshooting easings extrapolate).
function Codec.lerp(kind: string, a: any, b: any, alpha: number): any
	if kind == "number" then
		if type(a) ~= "number" or type(b) ~= "number" then
			error("Codec.lerp(number): expected numbers, got " .. typeof(a) .. " and " .. typeof(b), 2)
		end
		if alpha == 0 then
			return a
		elseif alpha == 1 then
			return b
		end
		return a + (b - a) * alpha
	elseif kind == "vector3" then
		if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
			error("Codec.lerp(vector3): expected Vector3s, got " .. typeof(a) .. " and " .. typeof(b), 2)
		end
		if alpha == 0 then
			return a
		elseif alpha == 1 then
			return b
		end
		return (a :: Vector3):Lerp(b, alpha)
	elseif kind == "color3" then
		if typeof(a) ~= "Color3" or typeof(b) ~= "Color3" then
			error("Codec.lerp(color3): expected Color3s, got " .. typeof(a) .. " and " .. typeof(b), 2)
		end
		if alpha == 0 then
			return a
		elseif alpha == 1 then
			return b
		end
		local c = (a :: Color3):Lerp(b, alpha)
		if alpha < 0 or alpha > 1 then
			c = clampColor(c)
		end
		return c
	elseif kind == "boolean" then
		return if alpha >= 1 then b else a
	end
	error("Codec.lerp: unsupported channel kind " .. describe(kind), 2)
end

-- Palette keys (without "$") referenced by a JSON-form colour or colour sequence, in order of appearance.
function Codec.paletteRefs(kind: string, value: any): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(c: any)
		if type(c) == "string" and string.sub(c, 1, 1) == "$" then
			local key = string.sub(c, 2)
			if not seen[key] then
				seen[key] = true
				table.insert(out, key)
			end
		end
	end
	if kind == "color3" then
		add(value)
	elseif kind == "colorSequence" then
		if type(value) == "table" then
			for _, kp in ipairs(value) do
				if type(kp) == "table" then
					add(kp[2])
				end
			end
		else
			add(value)
		end
	end
	return out
end

return Codec
