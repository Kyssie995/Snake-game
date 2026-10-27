--!strict
--[[
	Random — deterministic pseudo-random numbers (Roblox's `Random` is not available in Lune, and its algorithm
	is not specified, so ASTRA ships its own).

	Generator: mulberry32 (32-bit state, period 2^32) implemented with exact integer arithmetic on doubles plus
	bit32, so the same seed yields bit-identical next() values on every platform. The initial state is the seed
	scrambled by a splitmix-style step (add the golden-ratio constant, then the murmur3 fmix32 finalizer), which
	decorrelates neighbouring seeds (1, 2, 3, ...).

	Interpretation notes (docs/MODULE_CONTRACTS.md §3):
	  * Random.new(seed): a finite integer with |seed| < 2^53 is reduced modulo 2^32 (so -1 ≡ 4294967295 and
	    seed + 2^32 ≡ seed). Any other seed (fractions, NaN, ±inf, huge numbers, strings) is replaced by
	    Random.hash(seed). nil means 0.
	  * Random.hash(...): FNV-1a 32-bit over tostring() of each part; parts are separated by one 0x1F byte (so
	    hash("ab", "c") ~= hash("a", "bc")); a single part is plain FNV-1a of its text. Numbers are normalized
	    first (-0 → "0", every NaN → "nan") because tostring() differs for those. Only string, number, boolean
	    and nil parts are accepted (tostring of tables/instances is not deterministic). Result: integer in
	    [0, 2^32).
	  * rng:int(min, max): inclusive; swapped if min > max; fractional bounds are rounded inward; errors if the
	    range contains no integer or a bound is not finite.
	  * rng:range(min, max): min + (max - min) * next() — [min, max) for min < max, min when equal.
	  * rng:unitVector() / rng:inCone(): sampled without trigonometry on random values (Marsaglia's rejection
	    method, at most 64 attempts, then a fixed fallback axis), so results depend only on IEEE-exact
	    operations (+ - * / sqrt) of the random stream; inCone only applies cos() to the angle argument.
	    inCone draws a direction uniformly from the spherical cap of half-angle angleDeg (clamped to [0, 180];
	    NaN → 0) around `direction`; a zero or non-finite direction means "no preferred axis" → unitVector().
	  * rng:pick(list) returns nil for an empty list (without consuming a number).
]]

local Random = {}

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { _state: number }, Rng))

local TWO_32 = 4294967296
local TWO_53 = 2 ^ 53
local GOLDEN_GAMMA = 0x9E3779B9
local MULBERRY_INCREMENT = 0x6D2B79F5
local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619
local SEPARATOR = 0x1F

-- Builtins as locals (still compiled as builtin fast calls; no global lookups in custom environments).
local bxor, bor, rshift = bit32.bxor, bit32.bor, bit32.rshift
local floor, ceil, sqrt, abs = math.floor, math.ceil, math.sqrt, math.abs
local byte = string.byte
local newVector3 = Vector3.new

-- (a * b) mod 2^32 for a, b in [0, 2^32), exact (all intermediate products stay below 2^53).
local function imul(a: number, b: number): number
	local aLo = a % 65536
	local aHi = (a - aLo) / 65536
	local bLo = b % 65536
	local bHi = (b - bLo) / 65536
	return (aLo * bLo + ((aHi * bLo + aLo * bHi) % 65536) * 65536) % TWO_32
end

-- murmur3 32-bit finalizer (bijective on [0, 2^32)).
local function fmix32(h: number): number
	h = bxor(h, rshift(h, 16))
	h = imul(h, 0x85EBCA6B)
	h = bxor(h, rshift(h, 13))
	h = imul(h, 0xC2B2AE35)
	return bxor(h, rshift(h, 16))
end

local function partText(part: any): string
	local t = type(part)
	if t == "string" then
		return part
	elseif t == "number" then
		if part ~= part then
			return "nan"
		elseif part == 0 then
			return "0"
		end
		return tostring(part)
	elseif t == "boolean" or t == "nil" then
		return tostring(part)
	end
	error("Random.hash: unsupported part of type " .. typeof(part) .. " (use strings and numbers)", 3)
end

-- FNV-1a 32-bit hash over tostring() of all parts (0x1F between parts). Returns an integer in [0, 2^32).
function Random.hash(...: string | number): number
	local h = FNV_OFFSET
	local count = select("#", ...)
	local parts = { ... }
	for i = 1, count do
		if i > 1 then
			h = imul(bxor(h, SEPARATOR), FNV_PRIME)
		end
		local text = partText(parts[i])
		for j = 1, #text do
			h = imul(bxor(h, byte(text, j)), FNV_PRIME)
		end
	end
	return h
end

-- Creates a generator. Same seed ⇒ same sequence on every platform.
function Random.new(seed: number?): Rng
	local s: number
	local value: any = seed
	if value == nil then
		s = 0
	elseif type(value) == "number" and value == value and abs(value) < TWO_53 and value % 1 == 0 then
		s = value % TWO_32
	else
		s = Random.hash(value)
	end
	return setmetatable({ _state = fmix32((s + GOLDEN_GAMMA) % TWO_32) }, Rng)
end

-- Next number in [0, 1) (multiples of 2^-32).
function Rng.next(self: Rng): number
	local a = (self._state + MULBERRY_INCREMENT) % TWO_32
	self._state = a
	local t = imul(bxor(a, rshift(a, 15)), bor(a, 1))
	t = bxor((t + imul(bxor(t, rshift(t, 7)), bor(t, 61))) % TWO_32, t)
	return bxor(t, rshift(t, 14)) / TWO_32
end

-- Number in [min, max).
function Rng.range(self: Rng, min: number, max: number): number
	return min + (max - min) * self:next()
end

-- Integer in [min, max] (inclusive).
function Rng.int(self: Rng, min: number, max: number): number
	local lo, hi = min, max
	if lo > hi then
		lo, hi = hi, lo
	end
	lo, hi = ceil(lo), floor(hi)
	if lo ~= lo or hi ~= hi or lo == -math.huge or hi == math.huge then
		error("Random:int: bounds must be finite numbers (got " .. tostring(min) .. ", " .. tostring(max) .. ")", 2)
	end
	if lo > hi then
		error("Random:int: no integer between " .. tostring(min) .. " and " .. tostring(max), 2)
	end
	return math.min(hi, lo + floor(self:next() * (hi - lo + 1)))
end

-- -1 or 1 with equal probability.
function Rng.sign(self: Rng): number
	return if self:next() < 0.5 then -1 else 1
end

-- Uniformly distributed direction on the unit sphere (Marsaglia 1972).
function Rng.unitVector(self: Rng): Vector3
	for _ = 1, 64 do
		local x = 2 * self:next() - 1
		local y = 2 * self:next() - 1
		local s = x * x + y * y
		if s < 1 then
			local f = 2 * sqrt(1 - s)
			return newVector3(x * f, y * f, 1 - 2 * s)
		end
	end
	return newVector3(0, 1, 0) -- unreachable in practice (probability ~1e-43)
end

-- Uniform point on the unit circle (rejection sampling, no trigonometry).
local function unitCircle(self: Rng): (number, number)
	for _ = 1, 64 do
		local x = 2 * self:next() - 1
		local y = 2 * self:next() - 1
		local s = x * x + y * y
		if s < 1 and s > 1e-12 then
			local inv = 1 / sqrt(s)
			return x * inv, y * inv
		end
	end
	return 1, 0 -- unreachable in practice
end

-- Uniformly distributed unit vector within `angleDeg` degrees of `direction` (spherical cap).
function Rng.inCone(self: Rng, direction: Vector3, angleDeg: number): Vector3
	local magnitude = direction.Magnitude
	if not (magnitude > 1e-9 and magnitude < math.huge) then
		return self:unitVector()
	end
	local angle = if angleDeg == angleDeg then math.clamp(angleDeg, 0, 180) else 0
	local d = direction / magnitude
	local cosAngle = math.cos(math.rad(angle))
	-- cos(theta) uniform in [cos(angle), 1] gives a uniform distribution over the cap's area.
	local z = 1 - self:next() * (1 - cosAngle)
	local cx, cy = unitCircle(self)
	local r = sqrt(math.max(0, 1 - z * z))
	local helper = if abs(d.Y) < 0.9 then newVector3(0, 1, 0) else newVector3(1, 0, 0)
	local u = helper:Cross(d).Unit
	local v = d:Cross(u)
	return u * (r * cx) + v * (r * cy) + d * z
end

-- Random element of `list`, or nil when it is empty.
function Rng.pick(self: Rng, list: { any }): any
	local count = #list
	if count == 0 then
		return nil
	end
	return list[self:int(1, count)]
end

-- Independent copy that continues with the same sequence.
function Rng.clone(self: Rng): Rng
	return setmetatable({ _state = self._state }, Rng)
end

return Random
