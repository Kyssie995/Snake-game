--!strict
--[[
	Easing — easing curves for keyframe segments and graph tweens. See docs/MODULE_CONTRACTS.md §7.

	Definitions (Types.EasingDef):
	  "Linear" | "Constant" | "<Style>" | "<Style>.<In|Out|InOut>" | { bezier = { x1, y1, x2, y2 } }
	Style and direction names are case-sensitive Roblox Enum.EasingStyle / Enum.EasingDirection names. A style
	without a direction means ".Out" (Roblox's default direction). Enum.EasingDirection has no OutIn, and the
	undocumented Enum.EasingStyle.Bezier / Spring (rejected by TweenService) are not accepted as names.
	Linear and Constant ignore the direction ("Linear.In" is valid and normalizes to "Linear").

	Curves (Robert Penner's equations, which Roblox's EasingStyle curves follow). Every curve returns exactly 0
	for t <= 0 (and for NaN) and exactly 1 for t >= 1; inside (0, 1):
	  In(t):
	    Linear       t
	    Sine         1 - cos(t·π/2)
	    Quad         t²            Cubic  t³            Quart  t⁴            Quint  t⁵
	    Exponential  2^(10·(t - 1))                       (endpoints forced to exactly 0 / 1)
	    Circular     1 - sqrt(1 - t²)
	    Back         t²·((s + 1)·t - s),  s = 1.70158;   InOut uses s = 1.70158 · 1.525
	    Elastic      -2^(10·(t - 1)) · sin((t - 1 - p/4) · 2π/p),  amplitude 1, p = 0.3;  InOut uses p = 0.45
	    Bounce       1 - BounceOut(1 - t)
	  Out(t)   = 1 - In(1 - t)               (Bounce: BounceOut directly — Penner's piecewise parabola
	                                          7.5625·t² on [0, 1/2.75), +0.75 / +0.9375 / +0.984375 segments)
	  InOut(t) = In(2t) / 2                   for t < 0.5
	           = 1 - In(2 - 2t) / 2           for t >= 0.5   (In with the InOut parameters above)
	  These are algebraically identical to Penner's direct Out/InOut equations, and make InOut exactly
	  point-symmetric (f(1 - t) = 1 - f(t)) and exactly 0.5 at t = 0.5.
	  Constant: 0 for t < 1, 1 for t >= 1 (step at the end of the segment).
	  The curves have not been compared against TweenService:GetValue here (no Studio); Easing.spec contains a
	  Studio-only test that does exactly that.

	Interpretation notes (where MODULE_CONTRACTS §7 leaves room):
	* Like TweenService:GetValue, curves clamp alpha to [0, 1]; NaN maps to 0.
	* Elastic InOut uses Penner's period 0.3 · 1.5 = 0.45 (the contract fixes 0.3 only for In/Out); Back InOut uses
	  Penner's s · 1.525.
	* normalize() drops the default direction ("Quad.Out" -> "Quad") and any direction on Linear/Constant, so each
	  meaning has exactly one canonical string. Bezier definitions are copied unchanged (-0 -> 0); a bezier that
	  happens to be linear stays a bezier.
	* Easing.bezier(a, a, b, b) returns the exact Linear curve (y(s) = x(s) for such handles).

	Bezier: CSS cubic-bezier with P0 = (0, 0), P3 = (1, 1). x1, x2 must be in [0, 1] (then x(s) is monotone and
	the curve is a function of x); y1, y2 may be any finite number (overshoot). y(x) is found by solving
	x(s) = x with Newton's method (8 steps, |error| < 1e-12) and a bisection fallback (≤ 64 steps).
]]

local Types = require(script.Parent.Types)

type EasingFn = Types.EasingFn
type EasingDef = Types.EasingDef

local Easing = {}

Easing.STYLES = {
	"Linear",
	"Constant",
	"Sine",
	"Quad",
	"Cubic",
	"Quart",
	"Quint",
	"Exponential",
	"Circular",
	"Back",
	"Elastic",
	"Bounce",
}
Easing.DIRECTIONS = { "In", "Out", "InOut" } -- Enum.EasingDirection has no OutIn
Easing.DEFAULT_DIRECTION = "Out"

local PI = math.pi
local HALF_PI = math.pi / 2
local BACK_S = 1.70158
local BACK_S_INOUT = BACK_S * 1.525
local ELASTIC_PERIOD = 0.3
local ELASTIC_PERIOD_INOUT = 0.3 * 1.5

local BEZIER_EPSILON = 1e-12
local NEWTON_STEPS = 8
local BISECTION_STEPS = 64

type Raw = (t: number) -> number

-- ─────────────────────────────────────────────────────────────────────────────
-- Raw In curves (valid for t in (0, 1))
-- ─────────────────────────────────────────────────────────────────────────────

local function back(s: number): Raw
	return function(t: number): number
		return t * t * ((s + 1) * t - s)
	end
end

local function elastic(period: number): Raw
	local shift = period / 4
	local k = 2 * PI / period
	return function(t: number): number
		return -(2 ^ (10 * (t - 1))) * math.sin((t - 1 - shift) * k)
	end
end

local function bounceOut(t: number): number
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		local u = t - 1.5 / 2.75
		return 7.5625 * u * u + 0.75
	elseif t < 2.5 / 2.75 then
		local u = t - 2.25 / 2.75
		return 7.5625 * u * u + 0.9375
	end
	local u = t - 2.625 / 2.75
	return 7.5625 * u * u + 0.984375
end

type Curve = {
	inFn: Raw,
	outFn: Raw?, -- direct Out formula (otherwise 1 - In(1 - t))
	inOutFn: Raw?, -- In curve used for InOut (otherwise inFn)
}

local CURVES: { [string]: Curve } = {
	Sine = {
		inFn = function(t: number): number
			return 1 - math.cos(t * HALF_PI)
		end,
	},
	Quad = {
		inFn = function(t: number): number
			return t * t
		end,
	},
	Cubic = {
		inFn = function(t: number): number
			return t * t * t
		end,
	},
	Quart = {
		inFn = function(t: number): number
			local t2 = t * t
			return t2 * t2
		end,
	},
	Quint = {
		inFn = function(t: number): number
			local t2 = t * t
			return t2 * t2 * t
		end,
	},
	Exponential = {
		inFn = function(t: number): number
			return 2 ^ (10 * (t - 1))
		end,
	},
	Circular = {
		inFn = function(t: number): number
			return 1 - math.sqrt(1 - t * t)
		end,
	},
	Back = { inFn = back(BACK_S), inOutFn = back(BACK_S_INOUT) },
	Elastic = { inFn = elastic(ELASTIC_PERIOD), inOutFn = elastic(ELASTIC_PERIOD_INOUT) },
	Bounce = {
		inFn = function(t: number): number
			return 1 - bounceOut(1 - t)
		end,
		outFn = bounceOut,
	},
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Wrappers with exact endpoints
-- ─────────────────────────────────────────────────────────────────────────────

-- f(t) for t in (0, 1); exactly 0 for t <= 0 or NaN, exactly 1 for t >= 1.
local function clamped(f: Raw): EasingFn
	return function(t: number): number
		if t > 0 then
			if t < 1 then
				return f(t)
			end
			return 1
		end
		return 0
	end
end

local function outOf(inFn: Raw): Raw
	return function(t: number): number
		return 1 - inFn(1 - t)
	end
end

local function inOutOf(inFn: EasingFn): EasingFn
	return function(t: number): number
		if t > 0 then
			if t < 0.5 then
				return inFn(2 * t) * 0.5
			elseif t < 1 then
				return 1 - inFn(2 - 2 * t) * 0.5
			end
			return 1
		end
		return 0
	end
end

local linear: EasingFn = clamped(function(t: number): number
	return t
end)

local constant: EasingFn = function(t: number): number
	if t >= 1 then
		return 1
	end
	return 0
end

local FUNCS: { [string]: { [string]: EasingFn } } = {
	Linear = { In = linear, Out = linear, InOut = linear },
	Constant = { In = constant, Out = constant, InOut = constant },
}
for name, curve in CURVES do
	FUNCS[name] = {
		In = clamped(curve.inFn),
		Out = clamped(curve.outFn or outOf(curve.inFn)),
		InOut = inOutOf(clamped(curve.inOutFn or curve.inFn)),
	}
end

local DIRECTION_SET: { [string]: boolean } = { In = true, Out = true, InOut = true }

-- ─────────────────────────────────────────────────────────────────────────────
-- Bezier
-- ─────────────────────────────────────────────────────────────────────────────

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function fmt(n: any): string
	if type(n) ~= "number" then
		return typeof(n)
	elseif n ~= n then
		return "NaN"
	end
	return (string.format("%.9g", n))
end

-- Error message for invalid bezier control points, or nil.
local function bezierProblem(x1: any, y1: any, x2: any, y2: any): string?
	local values = { x1, y1, x2, y2 }
	local names = { "x1", "y1", "x2", "y2" }
	for i = 1, 4 do
		if not isFinite(values[i]) then
			return "bezier " .. names[i] .. " must be a finite number, got " .. fmt(values[i])
		end
	end
	if x1 < 0 or x1 > 1 then
		return "bezier x1 must be within 0..1, got " .. fmt(x1)
	end
	if x2 < 0 or x2 > 1 then
		return "bezier x2 must be within 0..1, got " .. fmt(x2)
	end
	return nil
end

-- CSS-style cubic bezier easing through (0,0), (x1,y1), (x2,y2), (1,1). Errors on invalid control points.
function Easing.bezier(x1: number, y1: number, x2: number, y2: number): EasingFn
	local problem = bezierProblem(x1, y1, x2, y2)
	if problem then
		error("Easing.bezier: " .. problem, 2)
	end
	if x1 == y1 and x2 == y2 then
		return linear -- y(s) == x(s): exactly linear
	end
	-- Polynomial coefficients: x(s) = ((ax·s + bx)·s + cx)·s, same for y.
	local cx = 3 * x1
	local bx = 3 * (x2 - x1) - cx
	local ax = 1 - cx - bx
	local cy = 3 * y1
	local by = 3 * (y2 - y1) - cy
	local ay = 1 - cy - by

	local function sampleX(s: number): number
		return ((ax * s + bx) * s + cx) * s
	end
	local function slopeX(s: number): number
		return (3 * ax * s + 2 * bx) * s + cx
	end

	local function solve(x: number): number
		local s = x
		for _ = 1, NEWTON_STEPS do
			local err = sampleX(s) - x
			if math.abs(err) < BEZIER_EPSILON then
				return s
			end
			local d = slopeX(s)
			if math.abs(d) < 1e-6 then
				break
			end
			s -= err / d
			if s < 0 or s > 1 then
				break
			end
		end
		-- Bisection: x(s) is monotone non-decreasing on [0, 1] because x1, x2 ∈ [0, 1].
		local lo, hi = 0, 1
		s = x
		for _ = 1, BISECTION_STEPS do
			local xs = sampleX(s)
			if math.abs(xs - x) < BEZIER_EPSILON then
				return s
			end
			if xs < x then
				lo = s
			else
				hi = s
			end
			s = (lo + hi) * 0.5
		end
		return s
	end

	return function(t: number): number
		if t > 0 then
			if t < 1 then
				local s = solve(t)
				return ((ay * s + by) * s + cy) * s
			end
			return 1
		end
		return 0
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Definitions
-- ─────────────────────────────────────────────────────────────────────────────

local function quote(s: string): string
	return string.format("%q", s)
end

local function caseHint(name: string, candidates: { string }): string
	local lower = string.lower(name)
	for _, c in candidates do
		if string.lower(c) == lower then
			return " (did you mean " .. quote(c) .. "?)"
		end
	end
	return ""
end

local function describe(v: any): string
	if type(v) == "string" then
		return quote(v)
	elseif type(v) == "number" then
		return fmt(v)
	end
	return typeof(v)
end

local function split(def: string): (string, string?)
	local dot = string.find(def, ".", 1, true)
	if dot == nil then
		return def, nil
	end
	return string.sub(def, 1, dot - 1), string.sub(def, dot + 1)
end

local function checkString(def: string): (boolean, string?)
	if def == "" then
		return false, 'easing must not be empty (use "Linear")'
	end
	local style, direction = split(def)
	if FUNCS[style] == nil then
		if style == "Bezier" or style == "Spring" then
			return false,
				"easing style "
					.. quote(style)
					.. " is not supported (TweenService rejects it); use { bezier = { x1, y1, x2, y2 } } for curves"
		end
		return false,
			"unknown easing style "
				.. quote(style)
				.. caseHint(style, Easing.STYLES)
				.. " (expected one of "
				.. table.concat(Easing.STYLES, ", ")
				.. ")"
	end
	if direction ~= nil and not DIRECTION_SET[direction] then
		if direction == "OutIn" then
			return false, 'easing direction "OutIn" is not supported (Enum.EasingDirection only has In, Out and InOut)'
		end
		return false,
			"unknown easing direction "
				.. quote(direction)
				.. caseHint(direction, Easing.DIRECTIONS)
				.. " in "
				.. quote(def)
				.. " (expected In, Out or InOut)"
	end
	return true, nil
end

local function checkTable(def: { [any]: any }): (boolean, string?)
	for key in pairs(def) do
		if key ~= "bezier" then
			return false, "unexpected key " .. describe(key) .. " in easing table (only 'bezier' is allowed)"
		end
	end
	local b = def.bezier
	if type(b) ~= "table" then
		return false, "easing table needs bezier = { x1, y1, x2, y2 }, got " .. describe(b)
	end
	local count = 0
	for key in pairs(b) do
		if type(key) ~= "number" or key < 1 or key > 4 or key ~= math.floor(key) then
			return false, "bezier must be an array of exactly 4 numbers { x1, y1, x2, y2 }"
		end
		count += 1
	end
	if count ~= 4 then
		return false, "bezier must be an array of exactly 4 numbers { x1, y1, x2, y2 }, got " .. count
	end
	local problem = bezierProblem(b[1], b[2], b[3], b[4])
	if problem then
		return false, problem
	end
	return true, nil
end

-- Checks an easing definition. nil is valid (Linear).
function Easing.check(def: EasingDef?): (boolean, string?)
	local d: any = def
	if d == nil then
		return true, nil
	elseif type(d) == "string" then
		return checkString(d)
	elseif type(d) == "table" then
		return checkTable(d)
	end
	return false,
		'easing must be a style name such as "Quad.Out" or { bezier = { x1, y1, x2, y2 } }, got ' .. describe(d)
end

-- Resolves a definition to (fn, isConstant). nil => Linear. Errors on invalid definitions.
function Easing.parse(def: EasingDef?): (EasingFn, boolean)
	local d: any = def
	if d == nil then
		return linear, false
	end
	local ok, problem = Easing.check(d)
	if not ok then
		error("Easing.parse: " .. tostring(problem), 2)
	end
	if type(d) == "string" then
		local style, direction = split(d)
		return FUNCS[style][direction or Easing.DEFAULT_DIRECTION], style == "Constant"
	end
	local b = d.bezier
	return Easing.bezier(b[1], b[2], b[3], b[4]), false
end

-- Curve for a style and direction (default "Out"). Errors on unknown names.
function Easing.get(style: string, direction: string?): EasingFn
	if type(style) ~= "string" then
		error("Easing.get: style must be a string, got " .. typeof(style), 2)
	end
	local byDirection = FUNCS[style]
	if byDirection == nil then
		local ok, problem = checkString(style)
		if ok then
			problem = "expected a style name without a direction, got "
				.. quote(style)
				.. " (pass the direction separately or use Easing.parse)"
		end
		error("Easing.get: " .. tostring(problem), 2)
	end
	local dir = direction or Easing.DEFAULT_DIRECTION
	local fn = byDirection[dir]
	if fn == nil then
		local _, problem = checkString(style .. "." .. tostring(dir))
		error("Easing.get: " .. tostring(problem), 2)
	end
	return fn
end

local function zero(x: number): number
	return if x == 0 then 0 else x
end

-- Canonical definition: "Quad.Out" -> "Quad", "Linear.In" -> "Linear", nil -> "Linear", bezier copied.
-- Errors on invalid definitions.
function Easing.normalize(def: EasingDef?): EasingDef
	local d: any = def
	if d == nil then
		return "Linear"
	end
	local ok, problem = Easing.check(d)
	if not ok then
		error("Easing.normalize: " .. tostring(problem), 2)
	end
	if type(d) == "string" then
		local style, direction = split(d)
		if style == "Linear" or style == "Constant" or direction == nil or direction == Easing.DEFAULT_DIRECTION then
			return style
		end
		return style .. "." .. direction
	end
	local b = d.bezier
	return { bezier = { zero(b[1]), zero(b[2]), zero(b[3]), zero(b[4]) } }
end

return Easing
