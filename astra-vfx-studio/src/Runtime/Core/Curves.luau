--!strict
--[[
	Curves — keyframe tracks (compile + evaluate) and engine sequences (NumberSequence / ColorSequence).
	See docs/MODULE_CONTRACTS.md §8.

	Tracks
	  compileTrack(def, spec, palette, scale)  decodes every keyframe value with Codec.decode (clamped to
	                                           spec.min/max in authored units), multiplies "length" channels
	                                           (number / vector3) by `scale`, stable-sorts the keys by time and
	                                           resolves each key's easing with Easing.parse.
	  evaluate(track, t)                       binary search on the keys (tracks may have up to 256 keys).

	Interpretation notes (where the contract leaves room):
	* `scale` defaults to 1 and must be finite. It only affects channels with spec.scale == "length" and kind
	  number/vector3; colour and boolean channels ignore it. Clamping (spec.min/max) happens before scaling.
	* compileTrack does not look at `def.enabled`; skipping disabled tracks is the Compiler's decision.
	  A track without keyframes, a keyframe time that is not a finite number, an invalid value (Codec) or an
	  invalid easing (Easing) is a programmer error (the definition should have been validated): compileTrack
	  raises an error naming the track id and the 1-based keyframe index from the definition.
	* evaluate: t before the first key (or NaN) -> first value; t at or after the last key -> last value.
	  Otherwise the segment [keys[i], keys[i+1]) with keys[i].time <= t < keys[i+1].time is used, so keys that
	  share a time form a jump and the value AT that time is the value of the LAST key with that time
	  (right-continuous, like the engine's sequence evaluation). Inside a segment:
	    constant ("Constant" easing)  keys[i].value until keys[i+1].time
	    boolean channels              step: keys[i].value until keys[i+1].time (easing is ignored)
	    number / vector3 / color3     lerp(a, b, ease(alpha)); ease() may overshoot (Back, Elastic, bezier), so
	                                  numbers and vectors may leave [a, b] on purpose; colours are clamped to 0..1
	                                  (Codec.lerp). alpha == 0 / ease == 1 return a / b exactly.
	  A track with no keys evaluates to nil.
	* sample(track, t0, t1, n): floor(n) evenly spaced samples with both ends included (the last sample is
	  evaluated at exactly t1); n < 1 -> {}; n == 1 -> { evaluate(t0) }. t1 < t0 samples backwards.

	Sequences — evaluated exactly like the creator-docs reference evaluator (the engine has no built-in
	evaluation method): t is clamped to [0, 1] (NaN -> 0); t at or before the first keypoint -> first value; t at
	or after the last keypoint -> last value; otherwise linear between the keypoints with
	Time_i <= t < Time_{i+1}, value = (next - this) * alpha + this, colours linear in RGB. Envelopes are ignored by
	evaluateNumberSequence (it returns the mean value); evaluateNumberSequenceEnvelope interpolates them the same
	way. Keypoint arrays are cached per sequence value in a weak-keyed table because `.Keypoints` builds a new
	table on every access.

	Baking (extension used by the SequenceEditor, see docs/PLUGIN_CONTRACTS.md):
	  bakeToSequenceKeypoints(fn, maxKeypoints?, tolerance?, envelopeFn?) -> (keypoints, maxError)
	The engine only interpolates linearly with at most 20 keypoints, so arbitrary curves on [0, 1] (bezier,
	easing, ...) are approximated by a piecewise-linear interpolant.
	  1. Sampling: fn (and envelopeFn) are evaluated on a uniform grid of 1001 times (t = i / 1000). Each grid
	     cell whose midpoint deviates from the cell's chord by more than max(tolerance, 1e-4 * magnitude) / 4 is
	     split recursively, down to cells of 1 / 64000, so steep spots (vertical tangents of bezier handles at
	     x = 0 or 1, Circular ends, Bounce kinks, steps) are sampled densely while smooth curves stay at 1001
	     samples. Sample times are rounded to 6 decimals (what Json writes) before fn is evaluated.
	  2. Greedy max-error subdivision: starting from the end points, the sample with the largest error is
	     inserted as a keypoint until every error is <= tolerance or maxKeypoints is reached.
	Keypoints lie on the curve (fn(t) rounded to 6 decimals, what Json writes, and then to float32 like every
	sequence number in Codec's canonical form; envelopes alike), times are strictly increasing, first 0, last 1,
	with at most 6 decimals, so the keypoints survive a JSON round trip unchanged. The result is exactly
	Codec.normalize("numberSequence", ...) of the keypoints ([[t, v], ...], [t, v, e] when the envelope is not 0),
	except that two equal keypoints stay a list instead of collapsing into a number. The second return value is
	the largest error of the returned keypoints at the samples, max(|value error|, |envelope error|), measured
	with the engine's interpolation formula.
	  maxKeypoints  default 20, floored and clamped to [2, 20]
	  tolerance     default 0.001 (absolute, in the curve's units), negative -> 0. Errors below
	                1e-12 * magnitude (magnitude = max(1, max |value|, max envelope)) count as 0, so float noise
	                never adds keypoints.
	  envelopeFn    optional; negative envelopes are clamped to 0 (the engine requires >= 0).
	Between samples the true error can exceed the reported one by about the refinement threshold (measured on
	all easing styles and several beziers: < 2e-5); a discontinuity becomes a ramp of at most 1 / 64000.
	The greedy choice is not globally optimal; with a 20-keypoint budget the Easing styles bake to a maximum error
	of 0.0009 (Sine.In) .. 0.0156 (Bounce.InOut).
]]

local Codec = require(script.Parent.Codec)
local Constants = require(script.Parent.Constants)
local Easing = require(script.Parent.Easing)
local Types = require(script.Parent.Types)

type TrackDef = Types.TrackDef
type KeyframeDef = Types.KeyframeDef
type ChannelSpec = Types.ChannelSpec
type ChannelKind = Types.ChannelKind
type CompiledTrack = Types.CompiledTrack
type CompiledKeyframe = Types.CompiledKeyframe
type EasingFn = Types.EasingFn

local Curves = {}

local INF = math.huge
local MAX_SAMPLES = 1000000
local BAKE_GRID = 1000
local DEFAULT_BAKE_TOLERANCE = 1e-3
local MAX_KEYPOINTS = Constants.MAX_SEQUENCE_KEYPOINTS

Curves.BAKE_GRID = BAKE_GRID
Curves.DEFAULT_BAKE_TOLERANCE = DEFAULT_BAKE_TOLERANCE

local CHANNEL_KINDS: { [string]: boolean } = { number = true, vector3 = true, color3 = true, boolean = true }

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function fmt(x: any): string
	if type(x) == "number" then
		return string.format("%.17g", x)
	end
	return tostring(x)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Tracks
-- ─────────────────────────────────────────────────────────────────────────────

-- Compiles a track definition: decoded values, "length" scaling, stable time order, resolved easing.
function Curves.compileTrack(def: TrackDef, spec: ChannelSpec, palette: Codec.Palette?, scale: number?): CompiledTrack
	if type(def) ~= "table" then
		error("Curves.compileTrack: track definition must be a table, got " .. typeof(def), 2)
	end
	local trackName = "track " .. string.format("%q", tostring(def.id))
	if type(spec) ~= "table" then
		error("Curves.compileTrack(" .. trackName .. "): channel spec must be a table, got " .. typeof(spec), 2)
	end
	local kind = spec.kind
	if type(kind) ~= "string" or not CHANNEL_KINDS[kind] then
		error("Curves.compileTrack(" .. trackName .. "): unsupported channel kind " .. tostring(kind), 2)
	end
	local factor = 1
	if scale ~= nil then
		if not isFinite(scale) then
			error("Curves.compileTrack(" .. trackName .. "): scale must be a finite number, got " .. fmt(scale), 2)
		end
		if spec.scale == "length" and (kind == "number" or kind == "vector3") then
			factor = scale
		end
	end

	local keyframes: { KeyframeDef } = def.keyframes
	if type(keyframes) ~= "table" or #keyframes == 0 then
		error("Curves.compileTrack(" .. trackName .. "): a track needs at least one keyframe", 2)
	end
	local n = #keyframes
	local order: { number } = table.create(n)
	for i = 1, n do
		local kf: any = keyframes[i]
		if type(kf) ~= "table" then
			error("Curves.compileTrack(" .. trackName .. ", keyframe " .. i .. "): keyframe must be a table", 2)
		end
		if not isFinite(kf.time) then
			error(
				"Curves.compileTrack("
					.. trackName
					.. ", keyframe "
					.. i
					.. "): time must be a finite number, got "
					.. fmt(kf.time),
				2
			)
		end
		order[i] = i
	end
	-- Stable: equal times keep their definition order (a jump between two keys at the same time).
	table.sort(order, function(a: number, b: number): boolean
		local ta, tb = keyframes[a].time, keyframes[b].time
		if ta ~= tb then
			return ta < tb
		end
		return a < b
	end)

	local keys: { CompiledKeyframe } = table.create(n)
	for position, index in order do
		local kf = keyframes[index]
		local okValue, value = pcall(Codec.decode :: any, kind, kf.value, spec, palette)
		if not okValue then
			error("Curves.compileTrack(" .. trackName .. ", keyframe " .. index .. "): " .. tostring(value), 2)
		end
		if factor ~= 1 then
			value = value * factor
		end
		local okEase, ease, constant = pcall(Easing.parse :: any, kf.easing)
		if not okEase then
			error("Curves.compileTrack(" .. trackName .. ", keyframe " .. index .. "): " .. tostring(ease), 2)
		end
		local time = kf.time
		if time == 0 then
			time = 0 -- -0 -> 0
		end
		keys[position] = {
			time = time,
			value = value,
			ease = ease :: EasingFn,
			constant = constant == true,
		}
	end
	return {
		id = def.id,
		channel = def.channel,
		kind = kind :: ChannelKind,
		keys = keys,
	}
end

local function lerpValue(kind: string, a: any, b: any, e: number): any
	if kind == "number" then
		if e == 0 then
			return a
		elseif e == 1 then
			return b
		end
		return a + (b - a) * e
	end
	return Codec.lerp(kind, a, b, e)
end

-- Value of the track at `localTime` (seconds relative to the component start).
function Curves.evaluate(track: CompiledTrack, localTime: number): any
	local keys = track.keys
	local n = #keys
	if n == 0 then
		return nil
	end
	local first = keys[1]
	-- `not (t >= first)` also catches NaN.
	if n == 1 or not (localTime >= first.time) then
		return first.value
	end
	local last = keys[n]
	if localTime >= last.time then
		return last.value
	end
	-- Invariant: keys[lo].time <= t < keys[hi].time
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if keys[mid].time <= localTime then
			lo = mid
		else
			hi = mid
		end
	end
	local a = keys[lo]
	local kind = track.kind
	if a.constant or kind == "boolean" then
		return a.value
	end
	local b = keys[hi]
	local alpha = (localTime - a.time) / (b.time - a.time)
	return lerpValue(kind, a.value, b.value, a.ease(alpha))
end

-- `n` evenly spaced values of the track on [t0, t1] (both ends included).
function Curves.sample(track: CompiledTrack, t0: number, t1: number, n: number): { any }
	if not isFinite(t0) or not isFinite(t1) then
		error("Curves.sample: t0 and t1 must be finite numbers, got " .. fmt(t0) .. " and " .. fmt(t1), 2)
	end
	if type(n) ~= "number" or n ~= n then
		error("Curves.sample: n must be a number, got " .. fmt(n), 2)
	end
	local count = math.floor(n)
	if count > MAX_SAMPLES then
		error("Curves.sample: n must be at most " .. MAX_SAMPLES .. ", got " .. fmt(n), 2)
	end
	local out = {}
	if count < 1 then
		return out
	elseif count == 1 then
		out[1] = Curves.evaluate(track, t0)
		return out
	end
	local span = t1 - t0
	local last = count - 1
	for i = 0, last do
		local t = if i == last then t1 else t0 + span * (i / last)
		out[i + 1] = Curves.evaluate(track, t)
	end
	return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Sequences
-- ─────────────────────────────────────────────────────────────────────────────

type NumberData = { n: number, times: { number }, values: { number }, envelopes: { number } }
type ColorData = { n: number, times: { number }, colors: { Color3 }, r: { number }, g: { number }, b: { number } }

local numberCache: { [any]: NumberData } = setmetatable({}, { __mode = "k" }) :: any
local colorCache: { [any]: ColorData } = setmetatable({}, { __mode = "k" }) :: any

local function numberData(seq: NumberSequence, fnName: string): NumberData
	local cached = numberCache[seq]
	if cached then
		return cached
	end
	if typeof(seq) ~= "NumberSequence" then
		error("Curves." .. fnName .. ": expected a NumberSequence, got " .. typeof(seq), 3)
	end
	local keypoints = seq.Keypoints
	local n = #keypoints
	if n == 0 then
		error("Curves." .. fnName .. ": the NumberSequence has no keypoints", 3)
	end
	local data: NumberData = { n = n, times = table.create(n), values = table.create(n), envelopes = table.create(n) }
	for i, kp in keypoints do
		data.times[i] = kp.Time
		data.values[i] = kp.Value
		data.envelopes[i] = kp.Envelope
	end
	numberCache[seq] = data
	return data
end

local function colorData(seq: ColorSequence): ColorData
	local cached = colorCache[seq]
	if cached then
		return cached
	end
	if typeof(seq) ~= "ColorSequence" then
		error("Curves.evaluateColorSequence: expected a ColorSequence, got " .. typeof(seq), 3)
	end
	local keypoints = seq.Keypoints
	local n = #keypoints
	if n == 0 then
		error("Curves.evaluateColorSequence: the ColorSequence has no keypoints", 3)
	end
	local data: ColorData = {
		n = n,
		times = table.create(n),
		colors = table.create(n),
		r = table.create(n),
		g = table.create(n),
		b = table.create(n),
	}
	for i, kp in keypoints do
		local c = kp.Value
		data.times[i] = kp.Time
		data.colors[i] = c
		data.r[i] = c.R
		data.g[i] = c.G
		data.b[i] = c.B
	end
	colorCache[seq] = data
	return data
end

-- Locates t in a keypoint time list. Returns (i, alpha): alpha == nil means "exactly keypoint i".
local function locate(times: { number }, n: number, t: number): (number, number?)
	if t ~= t or t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end
	if n == 1 or t <= times[1] then
		return 1, nil
	end
	if t >= times[n] then
		return n, nil
	end
	-- Invariant: times[lo] <= t < times[hi]
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	return lo, (t - times[lo]) / (times[hi] - times[lo])
end

-- Mean value of a NumberSequence at t in [0, 1] (linear between keypoints, like the engine).
function Curves.evaluateNumberSequence(seq: NumberSequence, t: number): number
	local data = numberData(seq, "evaluateNumberSequence")
	local i, alpha = locate(data.times, data.n, t)
	local values = data.values
	local this = values[i]
	if alpha == nil then
		return this
	end
	return (values[i + 1] - this) * alpha + this
end

-- Envelope of a NumberSequence at t in [0, 1] (interpolated like the values).
function Curves.evaluateNumberSequenceEnvelope(seq: NumberSequence, t: number): number
	local data = numberData(seq, "evaluateNumberSequenceEnvelope")
	local i, alpha = locate(data.times, data.n, t)
	local envelopes = data.envelopes
	local this = envelopes[i]
	if alpha == nil then
		return this
	end
	return (envelopes[i + 1] - this) * alpha + this
end

-- Colour of a ColorSequence at t in [0, 1] (linear in RGB between keypoints, like the engine).
function Curves.evaluateColorSequence(seq: ColorSequence, t: number): Color3
	local data = colorData(seq)
	local i, alpha = locate(data.times, data.n, t)
	if alpha == nil then
		return data.colors[i]
	end
	local r, g, b = data.r, data.g, data.b
	return Color3.new(
		(r[i + 1] - r[i]) * alpha + r[i],
		(g[i + 1] - g[i]) * alpha + g[i],
		(b[i + 1] - b[i]) * alpha + b[i]
	)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Baking arbitrary curves into engine sequences
-- ─────────────────────────────────────────────────────────────────────────────

-- Sample positions are integer ticks of 1 / BAKE_TICKS (1 / 64000): grid points every 64 ticks, refined cells
-- down to 1 tick. Times are rounded to 6 decimals (what Json writes) before fn is evaluated, so the baked
-- keypoints survive a JSON round trip unchanged; ticks stay distinct after rounding (1 tick > 1e-6).
local BAKE_REFINE_DEPTH = 6
local BAKE_TICKS = BAKE_GRID * 2 ^ BAKE_REFINE_DEPTH

local function tickTime(tick: number): number
	return math.floor(tick / BAKE_TICKS * 1e6 + 0.5) / 1e6
end

-- Rounds a keypoint value / envelope to 6 decimals (half away from zero) so that Json writes it exactly (the
-- float32 shortest decimal of such a number has at most 6 decimals too). Magnitudes >= 2^24 are whole numbers
-- once stored as float32 anyway.
local function jsonDecimals(v: number): number
	if v == 0 or math.abs(v) >= 16777216 then
		return v
	end
	local r = math.floor(math.abs(v) * 1e6 + 0.5) / 1e6
	return if v < 0 then -r else r
end

local function bakeSample(fn: (t: number) -> number, label: string, t: number, clampNegative: boolean): number
	local v: any = fn(t)
	if not isFinite(v) then
		error(
			"Curves.bakeToSequenceKeypoints: "
				.. label
				.. "("
				.. fmt(t)
				.. ") must return a finite number, got "
				.. (if type(v) == "number" then fmt(v) else typeof(v)),
			0
		)
	end
	if v == 0 or (clampNegative and v < 0) then
		return 0 -- also turns -0 into 0
	end
	return v
end

-- Approximates fn on [0, 1] by <= maxKeypoints linear keypoints (greedy max-error subdivision).
-- Returns the JSON keypoints ([[t, v], ...] or [t, v, e]) and the largest error at the sample points.
function Curves.bakeToSequenceKeypoints(
	fn: (t: number) -> number,
	maxKeypoints: number?,
	tolerance: number?,
	envelopeFn: ((t: number) -> number)?
): ({ { number } }, number)
	if type(fn) ~= "function" then
		error("Curves.bakeToSequenceKeypoints: fn must be a function, got " .. typeof(fn), 2)
	end
	if envelopeFn ~= nil and type(envelopeFn) ~= "function" then
		error("Curves.bakeToSequenceKeypoints: envelopeFn must be a function, got " .. typeof(envelopeFn), 2)
	end
	local budget = MAX_KEYPOINTS
	if maxKeypoints ~= nil then
		if type(maxKeypoints) ~= "number" or maxKeypoints ~= maxKeypoints then
			error("Curves.bakeToSequenceKeypoints: maxKeypoints must be a number, got " .. fmt(maxKeypoints), 2)
		end
		budget = math.clamp(math.floor(maxKeypoints), 2, MAX_KEYPOINTS)
	end
	local tol = DEFAULT_BAKE_TOLERANCE
	if tolerance ~= nil then
		if type(tolerance) ~= "number" or tolerance ~= tolerance then
			error("Curves.bakeToSequenceKeypoints: tolerance must be a number, got " .. fmt(tolerance), 2)
		end
		tol = math.max(tolerance, 0)
	end

	-- 1. Uniform grid (t = i / BAKE_GRID).
	local step = BAKE_TICKS / BAKE_GRID
	local gridValues: { number } = table.create(BAKE_GRID + 1)
	local gridEnvelopes: { number } = table.create(BAKE_GRID + 1, 0)
	local magnitude = 1
	for i = 0, BAKE_GRID do
		local t = i / BAKE_GRID
		local v = bakeSample(fn, "fn", t, false)
		gridValues[i + 1] = v
		magnitude = math.max(magnitude, math.abs(v))
		if envelopeFn then
			local e = bakeSample(envelopeFn, "envelopeFn", t, true)
			gridEnvelopes[i + 1] = e
			magnitude = math.max(magnitude, e)
		end
	end
	local threshold = math.max(tol, 1e-12 * magnitude)
	-- Cells whose midpoint is further than this from the chord are split (recursively, up to 1 tick).
	local refineThreshold = math.max(tol, 1e-4 * magnitude) / 4

	-- 2. Sample list: the grid plus refined midpoints, in time order.
	local ticks: { number } = {}
	local values: { number } = {}
	local envelopes: { number } = {}
	local function push(tick: number, v: number, e: number)
		table.insert(ticks, tick)
		table.insert(values, v)
		table.insert(envelopes, e)
	end
	local function refine(ta: number, va: number, ea: number, tb: number, vb: number, eb: number)
		if tb - ta < 2 then
			return
		end
		local tm = (ta + tb) / 2
		local t = tickTime(tm)
		local vm = bakeSample(fn, "fn", t, false)
		local em = if envelopeFn then bakeSample(envelopeFn, "envelopeFn", t, true) else 0
		local deviation = math.max(math.abs(vm - (va + vb) / 2), math.abs(em - (ea + eb) / 2))
		if deviation <= refineThreshold then
			return
		end
		refine(ta, va, ea, tm, vm, em)
		push(tm, vm, em)
		refine(tm, vm, em, tb, vb, eb)
	end
	for i = 0, BAKE_GRID do
		local tick = i * step
		push(tick, gridValues[i + 1], gridEnvelopes[i + 1])
		if i < BAKE_GRID then
			refine(tick, gridValues[i + 1], gridEnvelopes[i + 1], tick + step, gridValues[i + 2], gridEnvelopes[i + 2])
		end
	end
	local m = #ticks
	local times: { number } = table.create(m)
	for s = 1, m do
		times[s] = tickTime(ticks[s])
	end

	-- 3. Greedy subdivision: insert the sample with the largest error until it is within tolerance.
	local isKey: { boolean } = table.create(m, false)
	local err: { number } = table.create(m, 0)
	isKey[1] = true
	isKey[m] = true
	local function segmentError(a: number, b: number)
		local ta, tb = times[a], times[b]
		local va, vb = values[a], values[b]
		local ea, eb = envelopes[a], envelopes[b]
		for s = a + 1, b - 1 do
			-- Same formula as the engine evaluator: (next - this) * alpha + this.
			local alpha = (times[s] - ta) / (tb - ta)
			local e = math.abs(values[s] - ((vb - va) * alpha + va))
			if envelopeFn then
				e = math.max(e, math.abs(envelopes[s] - ((eb - ea) * alpha + ea)))
			end
			err[s] = e
		end
	end
	segmentError(1, m)
	local count = 2
	while count < budget do
		local best, bestErr = -1, threshold
		for s = 2, m - 1 do
			if not isKey[s] and err[s] > bestErr then
				best, bestErr = s, err[s]
			end
		end
		if best < 0 then
			break
		end
		isKey[best] = true
		err[best] = 0
		count += 1
		local left = best - 1
		while not isKey[left] do
			left -= 1
		end
		local right = best + 1
		while not isKey[right] do
			right += 1
		end
		segmentError(left, best)
		segmentError(best, right)
	end

	local raw: { { number } } = table.create(count)
	for s = 1, m do
		if isKey[s] then
			table.insert(raw, { times[s], jsonDecimals(values[s]), jsonDecimals(envelopes[s]) })
		end
	end

	-- 4. Canonical JSON form (values were rounded to 6 decimals above; Codec rounds sequence numbers to the
	-- shortest float32 decimal and omits zero envelopes). Codec collapses two equal keypoints into a plain number; undo that so the result is always
	-- a keypoint list.
	local okCanonical, canonical = pcall(Codec.normalize :: any, "numberSequence", raw)
	if not okCanonical then
		-- e.g. values beyond the float32 range, which the engine cannot store
		error("Curves.bakeToSequenceKeypoints: " .. tostring(canonical), 2)
	end
	if type(canonical) == "number" then
		canonical = { { 0, canonical }, { 1, canonical } }
	end
	local keypoints: { { number } } = canonical

	-- 5. Error of the returned keypoints at every sample (engine interpolation formula).
	local maxError = 0
	local last = #keypoints
	local k = 1
	for s = 1, m do
		local t = times[s]
		while k < last - 1 and keypoints[k + 1][1] <= t do
			k += 1
		end
		local a, b = keypoints[k], keypoints[k + 1]
		local v, e
		if t >= keypoints[last][1] then
			v, e = keypoints[last][2], keypoints[last][3] or 0
		elseif t <= a[1] then
			v, e = a[2], a[3] or 0
		else
			local alpha = (t - a[1]) / (b[1] - a[1])
			local ea, eb = a[3] or 0, b[3] or 0
			v = (b[2] - a[2]) * alpha + a[2]
			e = (eb - ea) * alpha + ea
		end
		local sampleError = math.max(math.abs(values[s] - v), math.abs(envelopes[s] - e))
		if sampleError > maxError then
			maxError = sampleError
		end
	end
	return keypoints, maxError
end

return Curves
