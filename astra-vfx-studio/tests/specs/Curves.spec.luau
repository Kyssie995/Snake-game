--!strict
return function(T: any, use: (string) -> any, _ctx: any)
	local Curves = use("AstraVFX.Core.Curves")
	local Codec = use("AstraVFX.Core.Codec")
	local Easing = use("AstraVFX.Core.Easing")
	local Random = use("AstraVFX.Core.Random")
	local Json = use("AstraVFX.Core.Json")

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function L(...: any): { any }
		return { ... }
	end

	-- Channel specs as descriptors declare them (Common.channel shape).
	local NUMBER = { name = "transparency", kind = "number", description = "fade", min = 0, max = 1 }
	local FREE_NUMBER = { name = "brightness", kind = "number", description = "free" }
	local LENGTH = { name = "width", kind = "number", description = "width", min = 0, scale = "length" }
	local POSITION = { name = "position", kind = "vector3", description = "offset", scale = "length" }
	local ROTATION = { name = "rotation", kind = "vector3", description = "degrees" }
	local COLOR = { name = "color", kind = "color3", description = "colour" }
	local BOOL = { name = "visible", kind = "boolean", description = "flag" }

	local function track(keyframes: { any }, id: string?, channel: string?): any
		return { id = id or "t1", channel = channel or "transparency", keyframes = keyframes }
	end

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	-- Independent reference for linear tracks: last key with time <= t, linear scan.
	local function referenceLinear(keys: { { number } }, t: number): number
		if t < keys[1][1] then
			return keys[1][2]
		end
		if t >= keys[#keys][1] then
			return keys[#keys][2]
		end
		local i = 1
		for j = 1, #keys do
			if keys[j][1] <= t then
				i = j
			end
		end
		local a, b = keys[i], keys[i + 1]
		return a[2] + (b[2] - a[2]) * ((t - a[1]) / (b[1] - a[1]))
	end

	-- Port of the creator-docs reference evaluators (NumberSequence.yaml / ColorSequence.yaml), linear scan.
	local function docsEvalNS(ns: NumberSequence, time: number): number
		local kps = ns.Keypoints
		if time == 0 then
			return kps[1].Value
		end
		if time == 1 then
			return kps[#kps].Value
		end
		for i = 1, #kps - 1 do
			local this, nxt = kps[i], kps[i + 1]
			if time >= this.Time and time < nxt.Time then
				local alpha = (time - this.Time) / (nxt.Time - this.Time)
				return (nxt.Value - this.Value) * alpha + this.Value
			end
		end
		error("docsEvalNS: no segment")
	end
	local function docsEvalCS(cs: ColorSequence, time: number): Color3
		local kps = cs.Keypoints
		if time == 0 then
			return kps[1].Value
		end
		if time == 1 then
			return kps[#kps].Value
		end
		for i = 1, #kps - 1 do
			local this, nxt = kps[i], kps[i + 1]
			if time >= this.Time and time < nxt.Time then
				local alpha = (time - this.Time) / (nxt.Time - this.Time)
				return Color3.new(
					(nxt.Value.R - this.Value.R) * alpha + this.Value.R,
					(nxt.Value.G - this.Value.G) * alpha + this.Value.G,
					(nxt.Value.B - this.Value.B) * alpha + this.Value.B
				)
			end
		end
		error("docsEvalCS: no segment")
	end

	-- Random sorted keypoint times in [0, 1] with first 0, last 1 and some duplicates.
	local function randomTimes(rng: any, n: number): { number }
		local times = { 0 }
		for _ = 2, n - 1 do
			table.insert(times, math.floor(rng:next() * 1000) / 1000)
		end
		table.insert(times, 1)
		table.sort(times)
		-- force a duplicate interior time
		if n >= 5 then
			times[3] = times[2]
		end
		return times
	end

	-- Piecewise-linear evaluation of JSON keypoints ({ t, v, e? }), engine formula.
	local function evalKeys(keys: { { number } }, t: number, column: number?): number
		local c = column or 2
		local function at(i: number): number
			return keys[i][c] or 0
		end
		if t <= keys[1][1] then
			return at(1)
		end
		if t >= keys[#keys][1] then
			return at(#keys)
		end
		local i = 1
		while i < #keys and keys[i + 1][1] <= t do
			i += 1
		end
		local alpha = (t - keys[i][1]) / (keys[i + 1][1] - keys[i][1])
		return (at(i + 1) - at(i)) * alpha + at(i)
	end

	-- Max |interpolant - fn| on a dense grid independent of the baker's sampling.
	local function denseError(keys: { { number } }, fn: (number) -> number, steps: number?): number
		local n = steps or 20011
		local worst = 0
		for i = 0, n do
			local t = i / n
			worst = math.max(worst, math.abs(evalKeys(keys, t) - fn(t)))
		end
		return worst
	end

	local function checkKeypointShape(keys: { { number } }, budget: number?)
		T.expect(#keys >= 2).toBe(true)
		T.expect(#keys <= (budget or 20)).toBe(true)
		T.expect(keys[1][1]).toBe(0)
		T.expect(keys[#keys][1]).toBe(1)
		for i = 2, #keys do
			T.expect(keys[i][1] > keys[i - 1][1]).toBe(true)
		end
		for _, kp in keys do
			-- at most 6 decimals (what Json writes)
			local scaled = kp[1] * 1e6
			T.expect(math.abs(scaled - math.floor(scaled + 0.5)) < 1e-6).toBe(true)
			T.expect(#kp == 2 or #kp == 3).toBe(true)
		end
	end

	T.describe("Curves", function()
		T.describe("compileTrack", function()
			T.it("decodes number keyframes and copies id, channel and kind", function()
				local compiled = Curves.compileTrack(
					track({ { time = 0, value = 0.25 }, { time = 1, value = 0.75 } }, "fade", "transparency"),
					NUMBER,
					nil,
					1
				)
				T.expect(compiled.id).toBe("fade")
				T.expect(compiled.channel).toBe("transparency")
				T.expect(compiled.kind).toBe("number")
				T.expect(#compiled.keys).toBe(2)
				T.expect(compiled.keys[1].time).toBe(0)
				T.expect(compiled.keys[1].value).toBe(0.25)
				T.expect(compiled.keys[2].time).toBe(1)
				T.expect(compiled.keys[2].value).toBe(0.75)
				T.expect(compiled.keys[1].constant).toBe(false)
				T.expect(type(compiled.keys[1].ease)).toBe("function")
			end)

			T.it("sorts keys by time and keeps definition order for equal times (stable)", function()
				local compiled = Curves.compileTrack(
					track({
						{ time = 1, value = 0.1 },
						{ time = 0.5, value = 0.2 },
						{ time = 0, value = 0.3 },
						{ time = 0.5, value = 0.4 },
						{ time = 1, value = 0.5 },
						{ time = 0.5, value = 0.6 },
					}),
					NUMBER
				)
				local times, values = {}, {}
				for i, key in compiled.keys do
					times[i] = key.time
					values[i] = key.value
				end
				T.expect(times).toEqual({ 0, 0.5, 0.5, 0.5, 1, 1 })
				T.expect(values).toEqual({ 0.3, 0.2, 0.4, 0.6, 0.1, 0.5 })
			end)

			T.it("does not mutate the definition", function()
				local def = track({
					{ time = 1, value = 1, easing = "Quad.In" },
					{ time = 0, value = 0 },
				})
				local before = deepCopy(def)
				Curves.compileTrack(def, NUMBER, nil, 2)
				T.expect(def).toEqual(before)
			end)

			T.it("clamps values to the channel's min/max (Codec.decode)", function()
				local compiled =
					Curves.compileTrack(track({ { time = 0, value = -0.5 }, { time = 1, value = 3 } }), NUMBER)
				T.expect(compiled.keys[1].value).toBe(0)
				T.expect(compiled.keys[2].value).toBe(1)
			end)

			T.it("multiplies length channels by scale (number and vector3)", function()
				local width = Curves.compileTrack(
					track({ { time = 0, value = 2 }, { time = 1, value = 0.5 } }, "w", "width"),
					LENGTH,
					nil,
					3
				)
				T.expect(width.keys[1].value).toBe(6)
				T.expect(width.keys[2].value).toBe(1.5)
				local position = Curves.compileTrack(
					track({ { time = 0, value = { 1, 2, 3 } }, { time = 1, value = 4 } }, "p", "position"),
					POSITION,
					nil,
					2
				)
				T.expect(position.keys[1].value).toEqual(Vector3.new(2, 4, 6))
				T.expect(position.keys[2].value).toEqual(Vector3.new(8, 8, 8))
			end)

			T.it("clamps before scaling (min/max are in authored units)", function()
				local width = Curves.compileTrack(track({ { time = 0, value = -4 } }, "w", "width"), LENGTH, nil, 2)
				T.expect(width.keys[1].value).toBe(0)
				local spec = { name = "w", kind = "number", description = "", max = 1, scale = "length" }
				local capped = Curves.compileTrack(track({ { time = 0, value = 5 } }), spec, nil, 4)
				T.expect(capped.keys[1].value).toBe(4)
			end)

			T.it("does not scale channels without scale = length, colours or booleans", function()
				local rotation = Curves.compileTrack(
					track({ { time = 0, value = { 90, 0, 0 } } }, "r", "rotation"),
					ROTATION,
					nil,
					5
				)
				T.expect(rotation.keys[1].value).toEqual(Vector3.new(90, 0, 0))
				local free = Curves.compileTrack(track({ { time = 0, value = 7 } }), FREE_NUMBER, nil, 5)
				T.expect(free.keys[1].value).toBe(7)
				local colorSpec = { name = "c", kind = "color3", description = "", scale = "length" }
				local color = Curves.compileTrack(track({ { time = 0, value = "#FF0000" } }), colorSpec, nil, 5)
				T.expect(color.keys[1].value).toEqual(Color3.fromRGB(255, 0, 0))
				local boolSpec = { name = "b", kind = "boolean", description = "", scale = "length" }
				local flag = Curves.compileTrack(track({ { time = 0, value = true } }), boolSpec, nil, 5)
				T.expect(flag.keys[1].value).toBe(true)
			end)

			T.it("defaults scale to 1 when omitted", function()
				local width = Curves.compileTrack(track({ { time = 0, value = 2 } }, "w", "width"), LENGTH)
				T.expect(width.keys[1].value).toBe(2)
			end)

			T.it("decodes colours including palette references", function()
				local palette = { primary = Color3.fromRGB(80, 160, 255) }
				local compiled = Curves.compileTrack(
					track({ { time = 0, value = "#F00" }, { time = 1, value = "$primary" } }, "c", "color"),
					COLOR,
					palette,
					1
				)
				T.expect(compiled.kind).toBe("color3")
				T.expect(compiled.keys[1].value).toEqual(Color3.fromRGB(255, 0, 0))
				T.expect(compiled.keys[2].value).toEqual(Color3.fromRGB(80, 160, 255))
			end)

			T.it("resolves easing per keyframe (default Linear, Constant flag, styles, bezier)", function()
				local compiled = Curves.compileTrack(
					track({
						{ time = 0, value = 0 },
						{ time = 1, value = 0, easing = "Constant" },
						{ time = 2, value = 0, easing = "Quad.In" },
						{ time = 3, value = 0, easing = { bezier = { 0.42, 0, 0.58, 1 } } },
						{ time = 4, value = 0, easing = "Linear" },
					}),
					FREE_NUMBER
				)
				local keys = compiled.keys
				T.expect(keys[1].ease(0.3)).toBe(0.3)
				T.expect(keys[1].constant).toBe(false)
				T.expect(keys[2].constant).toBe(true)
				T.expect(keys[3].ease(0.5)).toBe(0.25)
				T.expect(keys[3].constant).toBe(false)
				T.expect(keys[4].ease(0.5)).toBeCloseTo(0.5, 1e-9)
				T.expect(keys[4].ease(0.25)).toBeCloseTo(Easing.bezier(0.42, 0, 0.58, 1)(0.25), 1e-12)
				T.expect(keys[5].ease(0.7)).toBe(0.7)
			end)

			T.it("normalizes -0 times to 0", function()
				local compiled = Curves.compileTrack(track({ { time = -0, value = 1 } }), FREE_NUMBER)
				T.expect(1 / compiled.keys[1].time).toBe(math.huge)
			end)

			T.it("errors for missing or empty keyframes", function()
				T.expect(function()
					Curves.compileTrack(track({}), NUMBER)
				end).toThrow("at least one keyframe")
				T.expect(function()
					Curves.compileTrack({ id = "x", channel = "c" } :: any, NUMBER)
				end).toThrow("at least one keyframe")
			end)

			T.it("errors for invalid arguments", function()
				T.expect(function()
					Curves.compileTrack(nil :: any, NUMBER)
				end).toThrow("track definition must be a table")
				T.expect(function()
					Curves.compileTrack(track({ { time = 0, value = 1 } }), nil :: any)
				end).toThrow("channel spec must be a table")
				T.expect(function()
					Curves.compileTrack(
						track({ { time = 0, value = 1 } }),
						{ name = "x", kind = "numberSequence", description = "" }
					)
				end).toThrow("unsupported channel kind")
				T.expect(function()
					Curves.compileTrack(track({ { time = 0, value = 1 } }), LENGTH, nil, 0 / 0)
				end).toThrow("scale must be a finite number")
				T.expect(function()
					Curves.compileTrack(track({ { time = 0, value = 1 } }), LENGTH, nil, math.huge)
				end).toThrow("scale must be a finite number")
			end)

			T.it("errors for invalid keyframe times with the definition index", function()
				T.expect(function()
					Curves.compileTrack(track({ { time = 0, value = 1 }, { time = 0 / 0, value = 1 } }), NUMBER)
				end).toThrow("keyframe 2): time must be a finite number")
				T.expect(function()
					Curves.compileTrack(track({ { time = "1", value = 1 } } :: any), NUMBER)
				end).toThrow("keyframe 1): time must be a finite number")
				T.expect(function()
					Curves.compileTrack(track({ { time = math.huge, value = 1 } }), NUMBER)
				end).toThrow("time must be a finite number")
				T.expect(function()
					Curves.compileTrack(track({ 5 } :: any), NUMBER)
				end).toThrow("keyframe must be a table")
			end)

			T.it("errors for invalid values naming track and definition keyframe index", function()
				T.expect(function()
					Curves.compileTrack(
						track({ { time = 1, value = 1 }, { time = 0, value = "abc" } }, "fadeTrack"),
						NUMBER
					)
				end).toThrow('track "fadeTrack", keyframe 2')
				T.expect(function()
					Curves.compileTrack(track({ { time = 0, value = "$missing" } }), COLOR, {})
				end).toThrow("unknown palette colour")
				T.expect(function()
					Curves.compileTrack(track({ { time = 0, value = { 1, 2 } } }), POSITION)
				end).toThrow("keyframe 1")
			end)

			T.it("errors for invalid easing definitions", function()
				T.expect(function()
					Curves.compileTrack(track({ { time = 0, value = 1, easing = "quad.out" } }), NUMBER)
				end).toThrow("keyframe 1")
				T.expect(function()
					Curves.compileTrack(
						track({ { time = 0, value = 1, easing = { bezier = { 2, 0, 0, 1 } } } }),
						NUMBER
					)
				end).toThrow("Easing")
			end)
		end)

		T.describe("evaluate", function()
			local function numberTrack(keyframes: { any }): any
				return Curves.compileTrack(track(keyframes), FREE_NUMBER)
			end

			T.it("returns the only key's value for every time", function()
				local t = numberTrack({ { time = 0.5, value = 3 } })
				for _, time in { -10, 0, 0.5, 1, 100, 0 / 0, math.huge, -math.huge } do
					T.expect(Curves.evaluate(t, time)).toBe(3)
				end
			end)

			T.it("clamps before the first and after the last key", function()
				local t = numberTrack({ { time = 1, value = 10 }, { time = 2, value = 20 } })
				T.expect(Curves.evaluate(t, 0)).toBe(10)
				T.expect(Curves.evaluate(t, -5)).toBe(10)
				T.expect(Curves.evaluate(t, 1)).toBe(10)
				T.expect(Curves.evaluate(t, 2)).toBe(20)
				T.expect(Curves.evaluate(t, 99)).toBe(20)
				T.expect(Curves.evaluate(t, math.huge)).toBe(20)
				T.expect(Curves.evaluate(t, -math.huge)).toBe(10)
			end)

			T.it("treats NaN as before the first key", function()
				local t = numberTrack({ { time = 0, value = 1 }, { time = 1, value = 2 } })
				T.expect(Curves.evaluate(t, 0 / 0)).toBe(1)
			end)

			T.it("interpolates linearly by default and hits keys exactly", function()
				local t = numberTrack({ { time = 0, value = 0 }, { time = 2, value = 10 }, { time = 3, value = 4 } })
				T.expect(Curves.evaluate(t, 0.5)).toBe(2.5)
				T.expect(Curves.evaluate(t, 1)).toBe(5)
				T.expect(Curves.evaluate(t, 2)).toBe(10)
				T.expect(Curves.evaluate(t, 2.5)).toBe(7)
				T.expect(Curves.evaluate(t, 3)).toBe(4)
			end)

			T.it("applies the easing of the segment's first key", function()
				local t = numberTrack({
					{ time = 0, value = 0, easing = "Quad.In" },
					{ time = 1, value = 100, easing = "Quad.Out" },
					{ time = 2, value = 0 },
				})
				T.expect(Curves.evaluate(t, 0.5)).toBeCloseTo(25, 1e-9)
				T.expect(Curves.evaluate(t, 1.5)).toBeCloseTo(100 - 75, 1e-9)
			end)

			T.it("lets overshooting easings leave the key range for numbers", function()
				local t = numberTrack({ { time = 0, value = 0, easing = "Back.Out" }, { time = 1, value = 1 } })
				local peak = 0
				for i = 0, 100 do
					peak = math.max(peak, Curves.evaluate(t, i / 100))
				end
				T.expect(peak > 1.05).toBe(true)
				T.expect(Curves.evaluate(t, 1)).toBe(1)
			end)

			T.it("holds the value through Constant segments", function()
				local t = numberTrack({
					{ time = 0, value = 1, easing = "Constant" },
					{ time = 1, value = 5 },
					{ time = 2, value = 9 },
				})
				T.expect(Curves.evaluate(t, 0)).toBe(1)
				T.expect(Curves.evaluate(t, 0.5)).toBe(1)
				T.expect(Curves.evaluate(t, 0.999999)).toBe(1)
				T.expect(Curves.evaluate(t, 1)).toBe(5)
				T.expect(Curves.evaluate(t, 1.5)).toBe(7)
			end)

			T.it("steps booleans regardless of easing", function()
				local t = Curves.compileTrack(
					track({
						{ time = 0, value = true, easing = "Back.Out" },
						{ time = 1, value = false, easing = "Elastic.In" },
						{ time = 2, value = true },
					}),
					BOOL
				)
				for i = 0, 99 do
					T.expect(Curves.evaluate(t, i / 100)).toBe(true)
					T.expect(Curves.evaluate(t, 1 + i / 100)).toBe(false)
				end
				T.expect(Curves.evaluate(t, 2)).toBe(true)
				T.expect(Curves.evaluate(t, -1)).toBe(true)
			end)

			T.it("jumps at keys that share a time (right-continuous)", function()
				local t = numberTrack({
					{ time = 0, value = 0 },
					{ time = 1, value = 10 },
					{ time = 1, value = 50 },
					{ time = 2, value = 60 },
				})
				T.expect(Curves.evaluate(t, 0.5)).toBe(5)
				T.expect(Curves.evaluate(t, 0.9999)).toBeCloseTo(9.999, 1e-9)
				T.expect(Curves.evaluate(t, 1)).toBe(50)
				T.expect(Curves.evaluate(t, 1.5)).toBe(55)
				local first = numberTrack({ { time = 0, value = 1 }, { time = 0, value = 2 }, { time = 1, value = 3 } })
				T.expect(Curves.evaluate(first, 0)).toBe(2)
				T.expect(Curves.evaluate(first, -1)).toBe(1)
				local last = numberTrack({ { time = 0, value = 1 }, { time = 1, value = 2 }, { time = 1, value = 3 } })
				T.expect(Curves.evaluate(last, 1)).toBe(3)
				T.expect(Curves.evaluate(last, 0.5)).toBe(1.5)
			end)

			T.it("interpolates vector3 channels", function()
				local t = Curves.compileTrack(
					track({ { time = 0, value = { 0, 0, 0 } }, { time = 2, value = { 10, 20, -30 } } }),
					POSITION,
					nil,
					1
				)
				T.expect(Curves.evaluate(t, 0.5)).toBeCloseTo(Vector3.new(2.5, 5, -7.5), 1e-5)
				T.expect(Curves.evaluate(t, 2)).toEqual(Vector3.new(10, 20, -30))
				T.expect(Curves.evaluate(t, 0)).toEqual(Vector3.zero)
			end)

			T.it("interpolates colours in RGB and clamps overshoot", function()
				local t = Curves.compileTrack(
					track({ { time = 0, value = "#FF0000" }, { time = 1, value = "#0000FF" } }),
					COLOR
				)
				local mid = Curves.evaluate(t, 0.5)
				T.expect(mid).toBeCloseTo(Color3.new(0.5, 0, 0.5), 1e-6)
				local back = Curves.compileTrack(
					track({ { time = 0, value = "#000000", easing = "Back.Out" }, { time = 1, value = "#FFFFFF" } }),
					COLOR
				)
				for i = 0, 50 do
					local c: Color3 = Curves.evaluate(back, i / 50)
					T.expect(c.R <= 1 and c.G <= 1 and c.B <= 1).toBe(true)
					T.expect(c.R >= 0).toBe(true)
				end
				T.expect(Curves.evaluate(back, 0.6)).toBeCloseTo(Color3.new(1, 1, 1), 1e-9)
			end)

			T.it("returns nil for a track without keys", function()
				T.expect(Curves.evaluate({ id = "x", channel = "c", kind = "number", keys = {} }, 0)).toBeNil()
			end)

			T.it("matches a linear-scan reference on a 256-key track (binary search)", function()
				local rng = Random.new(1234)
				local keyframes, reference = {}, {}
				local time = 0
				for i = 1, 256 do
					-- some keys share a time (jumps)
					if i % 17 ~= 0 then
						time += math.floor(rng:next() * 100 + 1) / 1000
					end
					local value = math.floor(rng:range(-100, 100) * 1000) / 1000
					table.insert(keyframes, { time = time, value = value })
					table.insert(reference, { time, value })
				end
				local compiled = Curves.compileTrack(track(keyframes), FREE_NUMBER)
				T.expect(#compiled.keys).toBe(256)
				local probes = { -1, 0, time, time + 1 }
				for _, kp in reference do
					table.insert(probes, kp[1])
				end
				for _ = 1, 2000 do
					table.insert(probes, rng:range(-0.5, time + 0.5))
				end
				for _, p in probes do
					local expected = referenceLinear(reference, p)
					local actual = Curves.evaluate(compiled, p)
					if math.abs(actual - expected) > 1e-9 then
						T.fail(string.format("t=%.17g: got %.17g, expected %.17g", p, actual, expected))
					end
				end
			end)

			T.it("is deterministic", function()
				local def = track({
					{ time = 0, value = 0, easing = "Elastic.Out" },
					{ time = 1, value = 1, easing = { bezier = { 0.1, 0.9, 0.2, 1 } } },
					{ time = 2, value = 0.5 },
				})
				local a = Curves.compileTrack(def, FREE_NUMBER)
				local b = Curves.compileTrack(def, FREE_NUMBER)
				for i = 0, 200 do
					local t = i / 100
					T.expect(Curves.evaluate(a, t)).toBe(Curves.evaluate(b, t))
				end
			end)
		end)

		T.describe("sample", function()
			local t = Curves.compileTrack(track({ { time = 0, value = 0 }, { time = 1, value = 10 } }), FREE_NUMBER)

			T.it("returns n evenly spaced samples including both ends", function()
				T.expect(Curves.sample(t, 0, 1, 5)).toEqual({ 0, 2.5, 5, 7.5, 10 })
				T.expect(Curves.sample(t, 0, 1, 2)).toEqual({ 0, 10 })
			end)

			T.it("evaluates the last sample at exactly t1", function()
				local samples = Curves.sample(t, 0.1, 0.7, 7)
				T.expect(#samples).toBe(7)
				T.expect(samples[7]).toBe(Curves.evaluate(t, 0.7))
				T.expect(samples[1]).toBe(Curves.evaluate(t, 0.1))
			end)

			T.it("handles n = 1, n < 1 and fractional n", function()
				T.expect(Curves.sample(t, 0.5, 1, 1)).toEqual({ 5 })
				T.expect(Curves.sample(t, 0, 1, 0)).toEqual({})
				T.expect(Curves.sample(t, 0, 1, -3)).toEqual({})
				T.expect(Curves.sample(t, 0, 1, 3.9)).toEqual({ 0, 5, 10 })
			end)

			T.it("samples backwards when t1 < t0 and clamps outside the keys", function()
				T.expect(Curves.sample(t, 1, 0, 3)).toEqual({ 10, 5, 0 })
				T.expect(Curves.sample(t, -1, 2, 4)).toEqual({ 0, 0, 10, 10 })
			end)

			T.it("errors for non-finite bounds and invalid n", function()
				T.expect(function()
					Curves.sample(t, 0 / 0, 1, 3)
				end).toThrow("must be finite")
				T.expect(function()
					Curves.sample(t, 0, math.huge, 3)
				end).toThrow("must be finite")
				T.expect(function()
					Curves.sample(t, 0, 1, 0 / 0)
				end).toThrow("n must be a number")
				T.expect(function()
					Curves.sample(t, 0, 1, 1e9)
				end).toThrow("at most")
			end)
		end)

		T.describe("evaluateNumberSequence", function()
			local function kp(time: number, value: number, envelope: number?): NumberSequenceKeypoint
				return NumberSequenceKeypoint.new(time, value, envelope or 0)
			end

			T.it("interpolates linearly between keypoints and hits them exactly", function()
				local seq = NumberSequence.new({ kp(0, 0), kp(0.5, 1), kp(1, 0) })
				T.expect(Curves.evaluateNumberSequence(seq, 0)).toBe(0)
				T.expect(Curves.evaluateNumberSequence(seq, 0.25)).toBe(0.5)
				T.expect(Curves.evaluateNumberSequence(seq, 0.5)).toBe(1)
				T.expect(Curves.evaluateNumberSequence(seq, 0.75)).toBe(0.5)
				T.expect(Curves.evaluateNumberSequence(seq, 1)).toBe(0)
			end)

			T.it("clamps t to [0, 1] and maps NaN to 0", function()
				local seq = NumberSequence.new({ kp(0, 2), kp(1, 4) })
				T.expect(Curves.evaluateNumberSequence(seq, -1)).toBe(2)
				T.expect(Curves.evaluateNumberSequence(seq, 5)).toBe(4)
				T.expect(Curves.evaluateNumberSequence(seq, 0 / 0)).toBe(2)
				T.expect(Curves.evaluateNumberSequence(seq, -math.huge)).toBe(2)
				T.expect(Curves.evaluateNumberSequence(seq, math.huge)).toBe(4)
			end)

			T.it("evaluates constant sequences", function()
				local seq = NumberSequence.new(5)
				for _, t in { 0, 0.3, 1 } do
					T.expect(Curves.evaluateNumberSequence(seq, t)).toBe(5)
				end
			end)

			T.it("treats equal keypoint times as a jump (value at the time = later keypoint)", function()
				local seq = NumberSequence.new({ kp(0, 0), kp(0.5, 0), kp(0.5, 1), kp(1, 1) })
				T.expect(Curves.evaluateNumberSequence(seq, 0.4999)).toBe(0)
				T.expect(Curves.evaluateNumberSequence(seq, 0.5)).toBe(1)
				T.expect(Curves.evaluateNumberSequence(seq, 0.5)).toBe(docsEvalNS(seq, 0.5))
				local atZero = NumberSequence.new({ kp(0, 3), kp(0, 7), kp(1, 9) })
				T.expect(Curves.evaluateNumberSequence(atZero, 0)).toBe(docsEvalNS(atZero, 0))
				T.expect(Curves.evaluateNumberSequence(atZero, 0)).toBe(3)
				T.expect(Curves.evaluateNumberSequence(atZero, 0.5)).toBe(8)
			end)

			T.it("matches the creator-docs reference evaluator exactly on random sequences", function()
				local rng = Random.new(77)
				for _ = 1, 40 do
					local n = rng:int(2, 20)
					local times = randomTimes(rng, n)
					local kps = {}
					for i, time in times do
						kps[i] = kp(time, rng:range(-10, 10), rng:range(0, 2))
					end
					local seq = NumberSequence.new(kps)
					local probes = { 0, 1 }
					for _, time in times do
						table.insert(probes, time)
					end
					for _ = 1, 50 do
						table.insert(probes, rng:next())
					end
					for _, p in probes do
						T.expect(Curves.evaluateNumberSequence(seq, p)).toBe(docsEvalNS(seq, p))
					end
				end
			end)

			T.it("ignores envelopes for the value and interpolates them separately", function()
				local seq = NumberSequence.new({ kp(0, 1, 0), kp(1, 3, 0.5) })
				T.expect(Curves.evaluateNumberSequence(seq, 0.5)).toBe(2)
				T.expect(Curves.evaluateNumberSequenceEnvelope(seq, 0.5)).toBe(0.25)
				T.expect(Curves.evaluateNumberSequenceEnvelope(seq, 0)).toBe(0)
				T.expect(Curves.evaluateNumberSequenceEnvelope(seq, 2)).toBe(0.5)
			end)

			T.it("caches keypoints per sequence without mixing sequences up", function()
				local a = NumberSequence.new({ kp(0, 0), kp(1, 1) })
				local b = NumberSequence.new({ kp(0, 10), kp(1, 20) })
				for _ = 1, 3 do
					T.expect(Curves.evaluateNumberSequence(a, 0.5)).toBe(0.5)
					T.expect(Curves.evaluateNumberSequence(b, 0.5)).toBe(15)
				end
			end)

			T.it("errors for values that are not NumberSequences", function()
				T.expect(function()
					Curves.evaluateNumberSequence(5 :: any, 0)
				end).toThrow("expected a NumberSequence")
				T.expect(function()
					Curves.evaluateNumberSequence(nil :: any, 0)
				end).toThrow("expected a NumberSequence")
				T.expect(function()
					Curves.evaluateNumberSequence(ColorSequence.new(Color3.new()) :: any, 0)
				end).toThrow("expected a NumberSequence")
				T.expect(function()
					Curves.evaluateNumberSequenceEnvelope({} :: any, 0)
				end).toThrow("expected a NumberSequence")
			end)
		end)

		T.describe("evaluateColorSequence", function()
			local function ckp(time: number, color: Color3): ColorSequenceKeypoint
				return ColorSequenceKeypoint.new(time, color)
			end

			T.it("interpolates linearly in RGB (not HSV)", function()
				local seq = ColorSequence.new(Color3.new(1, 0, 0), Color3.new(0, 0, 1))
				local mid = Curves.evaluateColorSequence(seq, 0.5)
				T.expect(mid).toBeCloseTo(Color3.new(0.5, 0, 0.5), 1e-7)
				T.expect(mid.G).toBe(0)
			end)

			T.it("returns keypoint colours exactly at the ends and clamps t", function()
				local red, green, blue = Color3.new(1, 0, 0), Color3.new(0, 1, 0), Color3.new(0, 0, 1)
				local seq = ColorSequence.new({ ckp(0, red), ckp(0.25, green), ckp(1, blue) })
				T.expect(Curves.evaluateColorSequence(seq, 0)).toEqual(red)
				T.expect(Curves.evaluateColorSequence(seq, -2)).toEqual(red)
				T.expect(Curves.evaluateColorSequence(seq, 0 / 0)).toEqual(red)
				T.expect(Curves.evaluateColorSequence(seq, 0.25)).toEqual(green)
				T.expect(Curves.evaluateColorSequence(seq, 1)).toEqual(blue)
				T.expect(Curves.evaluateColorSequence(seq, 3)).toEqual(blue)
				T.expect(Curves.evaluateColorSequence(seq, 0.625)).toBeCloseTo(Color3.new(0, 0.5, 0.5), 1e-7)
			end)

			T.it("matches the creator-docs reference evaluator exactly on random sequences", function()
				local rng = Random.new(99)
				for _ = 1, 30 do
					local n = rng:int(2, 20)
					local times = randomTimes(rng, n)
					local kps = {}
					for i, time in times do
						kps[i] = ckp(time, Color3.new(rng:next(), rng:next(), rng:next()))
					end
					local seq = ColorSequence.new(kps)
					for _ = 1, 40 do
						local p = rng:next()
						local actual = Curves.evaluateColorSequence(seq, p)
						local expected = docsEvalCS(seq, p)
						T.expect(actual.R).toBe(expected.R)
						T.expect(actual.G).toBe(expected.G)
						T.expect(actual.B).toBe(expected.B)
					end
				end
			end)

			T.it("errors for values that are not ColorSequences", function()
				T.expect(function()
					Curves.evaluateColorSequence(NumberSequence.new(1) :: any, 0)
				end).toThrow("expected a ColorSequence")
				T.expect(function()
					Curves.evaluateColorSequence(Color3.new() :: any, 0)
				end).toThrow("expected a ColorSequence")
			end)
		end)

		T.describe("bakeToSequenceKeypoints", function()
			T.it("bakes a linear function into its two end points", function()
				local keys, err = Curves.bakeToSequenceKeypoints(function(t: number): number
					return 2 + 3 * t
				end)
				T.expect(keys).toEqual({ { 0, 2 }, { 1, 5 } })
				T.expect(err).toBe(0)
			end)

			T.it("bakes a constant function into two keypoints", function()
				local keys, err = Curves.bakeToSequenceKeypoints(function(_t: number): number
					return 0.4
				end, 20, 0)
				T.expect(keys).toEqual({ { 0, 0.4 }, { 1, 0.4 } })
				T.expect(err).toBe(0)
			end)

			T.it("respects the tolerance and uses fewer keypoints for looser tolerances", function()
				local quad = Easing.get("Quad", "Out")
				local previousCount = math.huge
				for _, tol in { 0.0005, 0.002, 0.01, 0.05, 0.2 } do
					local keys, err = Curves.bakeToSequenceKeypoints(quad, 20, tol)
					checkKeypointShape(keys)
					if #keys < 20 then
						T.expect(err <= tol).toBe(true)
					end
					T.expect(denseError(keys, quad) <= err + tol / 4 + 1e-9).toBe(true)
					T.expect(#keys <= previousCount).toBe(true)
					previousCount = #keys
				end
				local loose = Curves.bakeToSequenceKeypoints(quad, 20, 0.2)
				T.expect(#loose <= 3).toBe(true)
			end)

			T.it("keeps the dense error of every easing style within a 20-keypoint bound", function()
				for _, style in Easing.STYLES do
					for _, direction in { "In", "Out", "InOut" } do
						local fn = Easing.get(style, direction)
						local keys, err = Curves.bakeToSequenceKeypoints(fn, 20, 0)
						checkKeypointShape(keys)
						-- measured maxima: Sine.In 0.00087 ... Bounce.InOut 0.0156
						if err > 0.016 then
							T.fail(string.format("%s.%s: reported error %.6f > 0.016", style, direction, err))
						end
						if style ~= "Constant" then
							local dense = denseError(keys, fn, 8011)
							if dense > err + 5e-5 then
								T.fail(
									string.format("%s.%s: dense %.6f vs reported %.6f", style, direction, dense, err)
								)
							end
						end
					end
				end
			end)

			T.it("samples densely near vertical tangents (bezier handles at x = 0 / 1)", function()
				for _, p in { { 0, 1, 0, 1 }, { 1, 0, 1, 0 }, { 1, 0, 0, 1 }, { 0.68, -0.55, 0.265, 1.55 } } do
					local fn = Easing.bezier(p[1], p[2], p[3], p[4])
					local keys, err = Curves.bakeToSequenceKeypoints(fn, 20, 0.001)
					checkKeypointShape(keys)
					T.expect(err < 0.015).toBe(true)
					T.expect(denseError(keys, fn, 40009) <= err + 5e-5).toBe(true)
				end
			end)

			T.it("never increases the error when more keypoints are allowed (convex/concave curves)", function()
				for _, fn in { Easing.get("Quad", "Out"), Easing.get("Sine", "In"), Easing.get("Exponential", "In") } do
					local previous = math.huge
					for budget = 2, 20 do
						local keys, err = Curves.bakeToSequenceKeypoints(fn, budget, 0)
						T.expect(#keys).toBe(budget)
						T.expect(err <= previous + 1e-15).toBe(true)
						previous = err
					end
				end
			end)

			T.it("puts keypoints on the curve and keeps the end points exact", function()
				local fn = function(t: number): number
					return math.sin(t * 5) * 3 + 1
				end
				local keys = Curves.bakeToSequenceKeypoints(fn, 12, 0)
				T.expect(#keys).toBe(12)
				for _, kp in keys do
					-- float32 canonical form: relative error < 2^-24
					T.expect(math.abs(kp[2] - fn(kp[1])) <= 1e-7 * math.max(1, math.abs(kp[2]))).toBe(true)
				end
				T.expect(keys[1][2]).toBe(Codec.normalize("numberRange", fn(0)))
				T.expect(keys[#keys][2]).toBe(Codec.normalize("numberRange", fn(1)))
			end)

			T.it("produces keypoints that survive a JSON round trip unchanged (values and envelopes too)", function()
				-- The SequenceEditor stores baked keypoints in the definition; saving and reloading it must not
				-- change them (Json writes at most 6 decimals).
				local cases: { any } = {
					{ Easing.get("Sine", "In"), nil },
					{ Easing.get("Bounce", "Out"), nil },
					{ Easing.get("Elastic", "Out"), nil },
					{
						function(t: number): number
							return 0.001 * t * t
						end,
						nil,
					},
					{
						function(t: number): number
							return math.sin(t * 5) * 3 + 1
						end,
						function(t: number): number
							return 0.1234567 * t
						end,
					},
				}
				for i, case in cases do
					local keys, err = Curves.bakeToSequenceKeypoints(case[1], 20, 1e-7, case[2])
					local ok, back = Json.decode(Json.encode(keys, { pretty = false }))
					T.expect(ok).toBe(true)
					T.expect({ case = i, keys = back }).toEqual({ case = i, keys = keys })
					T.expect(Codec.normalize("numberSequence", back)).toEqual(keys)
					T.expect(err).toBeLessThan(1)
				end
			end)

			T.it("produces canonical keypoints that Codec accepts and the evaluator reproduces", function()
				local fn = Easing.get("Back", "InOut")
				local keys, err = Curves.bakeToSequenceKeypoints(fn, 20, 0.002)
				T.expect(Codec.check("numberSequence", keys)).toBe(true)
				T.expect(Codec.normalize("numberSequence", keys)).toEqual(keys)
				local seq = Codec.decode("numberSequence", keys)
				T.expect(typeof(seq)).toBe("NumberSequence")
				for i = 0, 997 do
					local t = i / 997
					local diff = math.abs(Curves.evaluateNumberSequence(seq, t) - fn(t))
					if diff > err + 1e-4 then
						T.fail(string.format("t=%.6f: |seq - fn| = %.6f > %.6f", t, diff, err + 1e-4))
					end
				end
			end)

			T.it("clamps maxKeypoints to [2, 20] and floors fractions", function()
				local fn = Easing.get("Sine", "InOut")
				T.expect(#Curves.bakeToSequenceKeypoints(fn, 1, 0)).toBe(2)
				T.expect(#Curves.bakeToSequenceKeypoints(fn, 0, 0)).toBe(2)
				T.expect(#Curves.bakeToSequenceKeypoints(fn, -5, 0)).toBe(2)
				T.expect(#Curves.bakeToSequenceKeypoints(fn, 5.9, 0)).toBe(5)
				T.expect(#Curves.bakeToSequenceKeypoints(fn, 50, 0)).toBe(20)
				T.expect(#Curves.bakeToSequenceKeypoints(fn, math.huge, 0)).toBe(20)
				T.expect(#Curves.bakeToSequenceKeypoints(fn, nil, 0)).toBe(20)
			end)

			T.it("treats negative tolerances as 0 and infinite tolerance as 'end points only'", function()
				local fn = Easing.get("Cubic", "In")
				T.expect(Curves.bakeToSequenceKeypoints(fn, 20, -1)).toEqual(Curves.bakeToSequenceKeypoints(fn, 20, 0))
				local keys, err = Curves.bakeToSequenceKeypoints(fn, 20, math.huge)
				T.expect(#keys).toBe(2)
				T.expect(err > 0.1).toBe(true)
			end)

			T.it("uses the default tolerance 0.001", function()
				local fn = Easing.get("Quad", "In")
				T.expect(Curves.DEFAULT_BAKE_TOLERANCE).toBe(0.001)
				local keys, err = Curves.bakeToSequenceKeypoints(fn)
				T.expect(Curves.bakeToSequenceKeypoints(fn, 20, 0.001)).toEqual(keys)
				T.expect(#keys < 20).toBe(true)
				T.expect(err <= 0.001).toBe(true)
			end)

			T.it("represents steps with a ramp no wider than 1/64000", function()
				local fn = function(t: number): number
					return if t < 0.5 then 0 else 1
				end
				local keys, err = Curves.bakeToSequenceKeypoints(fn, 20, 0)
				T.expect(err).toBe(0)
				T.expect(#keys).toBe(4)
				T.expect(keys[1]).toEqual({ 0, 0 })
				T.expect(keys[3]).toEqual({ 0.5, 1 })
				T.expect(keys[4]).toEqual({ 1, 1 })
				T.expect(keys[2][2]).toBe(0)
				T.expect(0.5 - keys[2][1] <= 1 / 64000 + 1e-6).toBe(true)
			end)

			T.it("bakes envelopes alongside values", function()
				local keys, err = Curves.bakeToSequenceKeypoints(
					function(t: number): number
						return t
					end,
					20,
					0.001,
					function(_t: number): number
						return 0.2
					end
				)
				T.expect(keys).toEqual({ { 0, 0, 0.2 }, { 1, 1, 0.2 } })
				T.expect(err).toBe(0)
				-- a curved envelope needs keypoints even though the value is linear
				local curved, curvedErr = Curves.bakeToSequenceKeypoints(
					function(t: number): number
						return t
					end,
					20,
					0.001,
					function(t: number): number
						return t * t
					end
				)
				T.expect(#curved > 2).toBe(true)
				T.expect(curvedErr <= 0.001).toBe(true)
				T.expect(Codec.check("numberSequence", curved)).toBe(true)
				-- envelope 0 at t = 0 is omitted from the keypoint (canonical form)
				T.expect(#curved[1]).toBe(2)
				T.expect(#curved[#curved]).toBe(3)
				for i = 0, 1000 do
					local t = i / 1000
					T.expect(math.abs(evalKeys(curved, t, 3) - t * t) <= curvedErr + 1e-4).toBe(true)
				end
			end)

			T.it("clamps negative envelopes to 0 and omits zero envelopes", function()
				local keys = Curves.bakeToSequenceKeypoints(
					function(t: number): number
						return t
					end,
					20,
					0,
					function(_t: number): number
						return -1
					end
				)
				T.expect(keys).toEqual({ { 0, 0 }, { 1, 1 } })
			end)

			T.it("normalizes -0 values to 0", function()
				local keys = Curves.bakeToSequenceKeypoints(function(_t: number): number
					return -0
				end)
				T.expect(1 / keys[1][2]).toBe(math.huge)
				T.expect(1 / keys[2][2]).toBe(math.huge)
			end)

			T.it("errors when fn returns something that is not a finite number", function()
				for _, bad in L(0 / 0, math.huge, -math.huge, "1", {}, true) do
					T.expect(function()
						Curves.bakeToSequenceKeypoints(function(_t: number): number
							return bad :: any
						end)
					end).toThrow("must return a finite number")
				end
				T.expect(function()
					Curves.bakeToSequenceKeypoints(function(_t: number): number
						return nil :: any
					end)
				end).toThrow("must return a finite number, got nil")
				-- values the engine cannot store (float32 range)
				T.expect(function()
					Curves.bakeToSequenceKeypoints(function(t: number): number
						return 1e39 * t
					end)
				end).toThrow("Curves.bakeToSequenceKeypoints: Codec.normalize(numberSequence)")
				-- an error in the middle of the range (also inside refined cells)
				T.expect(function()
					Curves.bakeToSequenceKeypoints(function(t: number): number
						return if t > 0.7 then 0 / 0 else t
					end)
				end).toThrow("must return a finite number")
				T.expect(function()
					Curves.bakeToSequenceKeypoints(
						function(t: number): number
							return t
						end,
						nil,
						nil,
						function(_t: number): number
							return 0 / 0
						end
					)
				end).toThrow("envelopeFn(")
			end)

			T.it("errors for invalid arguments", function()
				T.expect(function()
					Curves.bakeToSequenceKeypoints(nil :: any)
				end).toThrow("fn must be a function")
				T.expect(function()
					Curves.bakeToSequenceKeypoints(math.sin, 0 / 0)
				end).toThrow("maxKeypoints must be a number")
				T.expect(function()
					Curves.bakeToSequenceKeypoints(math.sin, "5" :: any)
				end).toThrow("maxKeypoints must be a number")
				T.expect(function()
					Curves.bakeToSequenceKeypoints(math.sin, 5, 0 / 0)
				end).toThrow("tolerance must be a number")
				T.expect(function()
					Curves.bakeToSequenceKeypoints(math.sin, 5, {} :: any)
				end).toThrow("tolerance must be a number")
				T.expect(function()
					Curves.bakeToSequenceKeypoints(math.sin, 5, 0, 1 :: any)
				end).toThrow("envelopeFn must be a function")
			end)

			T.it("is deterministic", function()
				local fn = Easing.get("Elastic", "Out")
				local a, errA = Curves.bakeToSequenceKeypoints(fn, 20, 0)
				local b, errB = Curves.bakeToSequenceKeypoints(fn, 20, 0)
				T.expect(a).toEqual(b)
				T.expect(errA).toBe(errB)
			end)

			T.it("is fast enough for interactive editing", function()
				local fn = Easing.bezier(0.68, -0.55, 0.265, 1.55)
				local started = os.clock()
				for _ = 1, 5 do
					Curves.bakeToSequenceKeypoints(fn, 20, 0)
				end
				local perBake = (os.clock() - started) / 5
				T.expect(perBake < 0.1).toBe(true)
			end)
		end)
	end)
end
