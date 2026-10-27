--!strict
return function(T: any, use: (string) -> any, ctx: any)
	local Easing = use("AstraVFX.Core.Easing")

	local ROBLOX_STYLES =
		{ "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Elastic", "Bounce" }
	local CURVED_STYLES =
		{ "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Elastic", "Bounce" }
	local MONOTONE_STYLES =
		{ "Linear", "Constant", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular" }
	local DIRECTIONS = { "In", "Out", "InOut" }

	-- Robert Penner's direct In/Out/InOut equations (easings.net form, Back s = 1.70158 / InOut s·1.525,
	-- Elastic p = 0.3 / InOut p = 0.45), evaluated independently in double precision at SAMPLES.
	local SAMPLES = { 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9 }
	-- stylua: ignore start
	local REFERENCE: { [string]: { number } } = {
		["Sine.In"] = { 0.0123116594048622, 0.0761204674887133, 0.190983005625053, 0.292893218813452, 0.412214747707527, 0.61731656763491, 0.843565534959769 },
		["Sine.Out"] = { 0.156434465040231, 0.38268343236509, 0.587785252292473, 0.707106781186547, 0.809016994374947, 0.923879532511287, 0.987688340595138 },
		["Sine.InOut"] = { 0.0244717418524232, 0.146446609406726, 0.345491502812526, 0.5, 0.654508497187474, 0.853553390593274, 0.975528258147577 },
		["Quad.In"] = { 0.01, 0.0625, 0.16, 0.25, 0.36, 0.5625, 0.81 },
		["Quad.Out"] = { 0.19, 0.4375, 0.64, 0.75, 0.84, 0.9375, 0.99 },
		["Quad.InOut"] = { 0.02, 0.125, 0.32, 0.5, 0.68, 0.875, 0.98 },
		["Cubic.In"] = { 0.001, 0.015625, 0.064, 0.125, 0.216, 0.421875, 0.729 },
		["Cubic.Out"] = { 0.271, 0.578125, 0.784, 0.875, 0.936, 0.984375, 0.999 },
		["Cubic.InOut"] = { 0.004, 0.0625, 0.256, 0.5, 0.744, 0.9375, 0.996 },
		["Quart.In"] = { 0.0001, 0.00390625, 0.0256, 0.0625, 0.1296, 0.31640625, 0.6561 },
		["Quart.Out"] = { 0.3439, 0.68359375, 0.8704, 0.9375, 0.9744, 0.99609375, 0.9999 },
		["Quart.InOut"] = { 0.0008, 0.03125, 0.2048, 0.5, 0.7952, 0.96875, 0.9992 },
		["Quint.In"] = { 1e-05, 0.0009765625, 0.01024, 0.03125, 0.07776, 0.2373046875, 0.59049 },
		["Quint.Out"] = { 0.40951, 0.7626953125, 0.92224, 0.96875, 0.98976, 0.9990234375, 0.99999 },
		["Quint.InOut"] = { 0.00016, 0.015625, 0.16384, 0.5, 0.83616, 0.984375, 0.99984 },
		["Exponential.In"] = { 0.001953125, 0.0055242717280199, 0.015625, 0.03125, 0.0625, 0.176776695296637, 0.5 },
		["Exponential.Out"] = { 0.5, 0.823223304703363, 0.9375, 0.96875, 0.984375, 0.99447572827198, 0.998046875 },
		["Exponential.InOut"] = { 0.001953125, 0.015625, 0.125, 0.5, 0.875, 0.984375, 0.998046875 },
		["Circular.In"] = { 0.00501256289338003, 0.0317541634481457, 0.083484861008832, 0.133974596215561, 0.2, 0.338562172233852, 0.564110105645933 },
		["Circular.Out"] = { 0.435889894354067, 0.661437827766148, 0.8, 0.866025403784439, 0.916515138991168, 0.968245836551854, 0.99498743710662 },
		["Circular.InOut"] = { 0.0101020514433644, 0.0669872981077807, 0.2, 0.5, 0.8, 0.933012701892219, 0.989897948556636 },
		["Back.In"] = { -0.01431422, -0.0641365625, -0.0993516800000001, -0.0876975, -0.02902752, 0.1825903125, 0.59117202 },
		["Back.Out"] = { 0.40882798, 0.8174096875, 1.02902752, 1.0876975, 1.09935168, 1.0641365625, 1.01431422 },
		["Back.InOut"] = { -0.037518552, -0.09968184375, 0.0899257920000001, 0.5, 0.910074208, 1.09968184375, 1.037518552 },
		["Elastic.In"] = { 0.001953125, -0.0055242717280199, 0.015625, -0.015625, -0.03125, 0.0883883476483184, -0.25 },
		["Elastic.Out"] = { 1.25, 0.911611652351682, 1.03125, 1.015625, 0.984375, 1.00552427172802, 0.998046875 },
		["Elastic.InOut"] = { 0.000339156597005722, 0.011969444423734, -0.117461577598239, 0.5, 1.11746157759824, 0.988030555576266, 0.999660843402994 },
		["Bounce.In"] = { 0.0118750000000001, 0.02734375, 0.2275, 0.234375, 0.0900000000000002, 0.52734375, 0.924375 },
		["Bounce.Out"] = { 0.075625, 0.47265625, 0.91, 0.765625, 0.7725, 0.97265625, 0.988125 },
		["Bounce.InOut"] = { 0.03, 0.1171875, 0.34875, 0.5, 0.65125, 0.8828125, 0.97 },
	}
	-- CSS cubic-bezier reference values (exact rational bisection, 80 steps) at x = 0.1, 0.25, 0.5, 0.75, 0.9.
	local BEZIER_X = { 0.1, 0.25, 0.5, 0.75, 0.9 }
	local BEZIER_REFERENCE: { { points: { number }, values: { number } } } = {
		{ points = { 0.25, 0.1, 0.25, 1 }, values = { 0.09479630571604325, 0.40851059135539586, 0.802403387584857, 0.9604589783489741, 0.9943164774845563 } },
		{ points = { 0.42, 0, 1, 1 }, values = { 0.01702660965156294, 0.09346465071882486, 0.3153568125725393, 0.6218618691748902, 0.8394278457624665 } },
		{ points = { 0, 0, 0.58, 1 }, values = { 0.16057215423753346, 0.3781381308251098, 0.6846431874274607, 0.9065353492811752, 0.982973390348437 } },
		{ points = { 0.42, 0, 0.58, 1 }, values = { 0.019722453548311196, 0.12916193104731982, 0.5, 0.8708380689526802, 0.9802775464516889 } },
		{ points = { 0.68, -0.55, 0.265, 1.55 }, values = { -0.06629147733352873, -0.08280710882832257, 0.6066798972237717, 1.0891657748134211, 1.06237319516637 } },
		{ points = { 1, 0, 0, 1 }, values = { 0.003761674958083166, 0.029724605511925198, 0.5, 0.9702753944880748, 0.9962383250419168 } },
	}
	-- stylua: ignore end

	local function all(fn: (style: string, direction: string, f: (number) -> number) -> ())
		for _, style in Easing.STYLES do
			for _, direction in DIRECTIONS do
				fn(style, direction, Easing.get(style, direction))
			end
		end
	end

	-- Deterministic pseudo-random numbers in [0, 1) for property tests (no math.random).
	local function lcg(seed: number): () -> number
		local state = seed
		return function(): number
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
	end

	-- Independent cubic-bezier reference: plain bisection on s, 100 steps.
	local function referenceBezier(x1: number, y1: number, x2: number, y2: number, x: number): number
		local function bx(s: number): number
			return 3 * (1 - s) ^ 2 * s * x1 + 3 * (1 - s) * s ^ 2 * x2 + s ^ 3
		end
		local function by(s: number): number
			return 3 * (1 - s) ^ 2 * s * y1 + 3 * (1 - s) * s ^ 2 * y2 + s ^ 3
		end
		local lo, hi = 0, 1
		for _ = 1, 100 do
			local m = (lo + hi) / 2
			if bx(m) < x then
				lo = m
			else
				hi = m
			end
		end
		return by((lo + hi) / 2)
	end

	T.describe("Easing", function()
		T.describe("constants", function()
			T.it("lists every Roblox EasingStyle name plus Constant", function()
				for _, style in ROBLOX_STYLES do
					T.expect(Easing.STYLES).toContain(style)
				end
				T.expect(Easing.STYLES).toContain("Constant")
				T.expect(Easing.STYLES).toHaveLength(12)
				T.expect(Easing.STYLES).never.toContain("Bezier")
				T.expect(Easing.STYLES).never.toContain("Spring")
			end)
			T.it("lists In, Out and InOut but no OutIn", function()
				T.expect(Easing.DIRECTIONS).toEqual({ "In", "Out", "InOut" })
				T.expect(Easing.DIRECTIONS).never.toContain("OutIn")
			end)
		end)

		T.describe("curves", function()
			T.it("return exactly 0 at t = 0 and exactly 1 at t = 1 for every style and direction", function()
				all(function(style: string, direction: string, f: (number) -> number)
					if f(0) ~= 0 or f(1) ~= 1 then
						T.fail(style .. "." .. direction .. ": f(0) = " .. f(0) .. ", f(1) = " .. f(1))
					end
				end)
			end)

			T.it("clamp alpha outside [0, 1] like TweenService:GetValue and map NaN to 0", function()
				all(function(style: string, direction: string, f: (number) -> number)
					local name = style .. "." .. direction
					for _, t in { -0.5, -1e-12, -math.huge, 0 / 0 } do
						if f(t) ~= 0 then
							T.fail(name .. ": f(" .. tostring(t) .. ") = " .. f(t))
						end
					end
					for _, t in { 1 + 1e-12, 1.5, 7, math.huge } do
						if f(t) ~= 1 then
							T.fail(name .. ": f(" .. tostring(t) .. ") = " .. f(t))
						end
					end
				end)
			end)

			T.it("match known sample values", function()
				T.expect(Easing.get("Quad", "In")(0.5)).toBe(0.25)
				T.expect(Easing.get("Quad", "Out")(0.5)).toBe(0.75)
				T.expect(Easing.get("Quad", "InOut")(0.25)).toBe(0.125)
				T.expect(Easing.get("Cubic", "In")(0.5)).toBe(0.125)
				T.expect(Easing.get("Quart", "Out")(0.5)).toBe(0.9375)
				T.expect(Easing.get("Quint", "In")(0.5)).toBe(0.03125)
				T.expect(Easing.get("Sine", "Out")(0.5)).toBeCloseTo(math.sin(math.pi / 4), 1e-12)
				T.expect(Easing.get("Sine", "In")(0.5)).toBeCloseTo(1 - math.cos(math.pi / 4), 1e-12)
				T.expect(Easing.get("Exponential", "In")(0.5)).toBeCloseTo(2 ^ -5, 1e-12)
				T.expect(Easing.get("Exponential", "Out")(0.5)).toBeCloseTo(1 - 2 ^ -5, 1e-12)
				T.expect(Easing.get("Circular", "In")(0.5)).toBeCloseTo(1 - math.sqrt(0.75), 1e-12)
				T.expect(Easing.get("Back", "In")(0.5)).toBeCloseTo(-0.0876975, 1e-12)
				T.expect(Easing.get("Elastic", "Out")(0.5)).toBeCloseTo(1.015625, 1e-12)
				T.expect(Easing.get("Bounce", "Out")(0.5)).toBeCloseTo(0.765625, 1e-12)
				T.expect(Easing.get("Linear", "In")(0.3)).toBe(0.3)
			end)

			T.it("match Penner's direct equations at sample points", function()
				for name, values in REFERENCE do
					local dot = string.find(name, ".", 1, true) :: number
					local f = Easing.get(string.sub(name, 1, dot - 1), string.sub(name, dot + 1))
					for i, t in SAMPLES do
						local got = f(t)
						if math.abs(got - values[i]) > 1e-12 then
							T.fail(name .. "(" .. t .. ") = " .. got .. ", expected " .. values[i])
						end
					end
				end
			end)

			T.it("satisfy Out(t) = 1 - In(1 - t)", function()
				for _, style in Easing.STYLES do
					if style == "Constant" then
						continue
					end
					local fin, fout = Easing.get(style, "In"), Easing.get(style, "Out")
					for i = 0, 200 do
						local t = i / 200
						T.expect(fout(t)).toBeCloseTo(1 - fin(1 - t), 1e-12)
					end
				end
			end)

			T.it("are point-symmetric for InOut: f(1 - x) = 1 - f(x)", function()
				for _, style in Easing.STYLES do
					if style == "Constant" then
						continue
					end
					local f = Easing.get(style, "InOut")
					for i = 0, 500 do
						local x = i / 500
						if math.abs(f(1 - x) - (1 - f(x))) > 1e-9 then
							T.fail(style .. ".InOut not symmetric at " .. x)
						end
					end
				end
			end)

			T.it("are exactly 0.5 and continuous at t = 0.5 for InOut", function()
				for _, style in CURVED_STYLES do
					local f = Easing.get(style, "InOut")
					T.expect(f(0.5)).toBe(0.5)
					-- Circular has a vertical tangent at 0.5 (sqrt), so allow sqrt(h)-sized differences.
					for _, h in { 1e-6, 1e-9, 1e-12 } do
						T.expect(f(0.5 - h)).toBeCloseTo(0.5, 4 * math.sqrt(h))
						T.expect(f(0.5 + h)).toBeCloseTo(0.5, 4 * math.sqrt(h))
						T.expect(f(0.5 - h)).toBeLessThanOrEqual(0.5)
						T.expect(f(0.5 + h)).toBeGreaterThanOrEqual(0.5)
					end
				end
			end)

			T.it("are monotone non-decreasing for monotone styles", function()
				for _, style in MONOTONE_STYLES do
					for _, direction in DIRECTIONS do
						local f = Easing.get(style, direction)
						local previous = f(0)
						for i = 1, 2000 do
							local v = f(i / 2000)
							if v < previous then
								T.fail(style .. "." .. direction .. " decreases at " .. (i / 2000))
							end
							previous = v
						end
					end
				end
			end)

			T.it("are continuous inside (0, 1) (no jumps between close samples)", function()
				all(function(style: string, direction: string, f: (number) -> number)
					if style == "Constant" then
						return
					end
					local h = 1e-4
					for i = 1, 999 do
						local t = i / 1000
						if math.abs(f(t + h) - f(t)) > 0.01 then
							T.fail(style .. "." .. direction .. " jumps near " .. t)
						end
					end
				end)
			end)

			T.it("overshoot for Back and Elastic and stay inside [0, 1] for Bounce", function()
				T.expect(Easing.get("Back", "In")(0.3)).toBeLessThan(0)
				T.expect(Easing.get("Back", "Out")(0.7)).toBeGreaterThan(1)
				T.expect(Easing.get("Elastic", "Out")(0.1)).toBeGreaterThan(1)
				local low, high = 0, 1
				for _, direction in DIRECTIONS do
					local f = Easing.get("Bounce", direction)
					for i = 0, 1000 do
						local v = f(i / 1000)
						low, high = math.min(low, v), math.max(high, v)
					end
					local e = Easing.get("Elastic", direction)
					for i = 0, 1000 do
						local v = e(i / 1000)
						T.expect(v).toBeGreaterThan(-0.5)
						T.expect(v).toBeLessThan(1.5)
					end
				end
				T.expect(low).toBeGreaterThanOrEqual(-1e-12)
				T.expect(high).toBeLessThanOrEqual(1 + 1e-12)
			end)

			T.it("Constant holds 0 until the end of the segment", function()
				for _, direction in DIRECTIONS do
					local f = Easing.get("Constant", direction)
					T.expect(f(0)).toBe(0)
					T.expect(f(0.5)).toBe(0)
					T.expect(f(0.999999)).toBe(0)
					T.expect(f(1)).toBe(1)
					T.expect(f(2)).toBe(1)
				end
			end)

			T.it("Linear ignores the direction", function()
				for _, direction in DIRECTIONS do
					local f = Easing.get("Linear", direction)
					for i = 0, 10 do
						T.expect(f(i / 10)).toBe(i / 10)
					end
				end
			end)

			T.it("are deterministic and cached per style and direction", function()
				T.expect(Easing.get("Quad", "In")).toBe(Easing.get("Quad", "In"))
				T.expect(Easing.get("Elastic", "InOut")).toBe(Easing.get("Elastic", "InOut"))
				local f = Easing.get("Elastic", "InOut")
				local first = {}
				for i = 0, 50 do
					first[i] = f(i / 50)
				end
				for i = 0, 50 do
					T.expect(f(i / 50)).toBe(first[i])
				end
			end)
		end)

		T.describe("get", function()
			T.it("defaults to the Out direction", function()
				for _, style in Easing.STYLES do
					T.expect(Easing.get(style)).toBe(Easing.get(style, "Out"))
				end
				T.expect(Easing.DEFAULT_DIRECTION).toBe("Out")
			end)
			T.it("rejects unknown styles and directions", function()
				T.expect(function()
					Easing.get("quad")
				end).toThrow('did you mean "Quad"')
				T.expect(function()
					Easing.get("Spring")
				end).toThrow("not supported")
				T.expect(function()
					Easing.get("Bezier", "In")
				end).toThrow("not supported")
				T.expect(function()
					Easing.get("Quad", "OutIn")
				end).toThrow("OutIn")
				T.expect(function()
					Easing.get("Quad", "in")
				end).toThrow('did you mean "In"')
				T.expect(function()
					Easing.get("", nil)
				end).toThrow("empty")
				T.expect(function()
					Easing.get("Quad.In")
				end).toThrow("without a direction")
				T.expect(function()
					Easing.get(5 :: any)
				end).toThrow("style must be a string")
			end)
		end)

		T.describe("bezier", function()
			T.it("bezier(0, 0, 1, 1) is linear", function()
				local f = Easing.bezier(0, 0, 1, 1)
				for i = 0, 100 do
					T.expect(f(i / 100)).toBeCloseTo(i / 100, 1e-12)
				end
			end)

			T.it("has exact endpoints and clamps alpha", function()
				for _, ref in BEZIER_REFERENCE do
					local p = ref.points
					local f = Easing.bezier(p[1], p[2], p[3], p[4])
					T.expect(f(0)).toBe(0)
					T.expect(f(1)).toBe(1)
					T.expect(f(-1)).toBe(0)
					T.expect(f(2)).toBe(1)
					T.expect(f(0 / 0)).toBe(0)
				end
			end)

			T.it("matches CSS ease, ease-in, ease-out, ease-in-out and overshoot references", function()
				for _, ref in BEZIER_REFERENCE do
					local p = ref.points
					local f = Easing.bezier(p[1], p[2], p[3], p[4])
					for i, x in BEZIER_X do
						local got = f(x)
						if math.abs(got - ref.values[i]) > 1e-8 then
							T.fail(
								"bezier("
									.. table.concat(p, ", ")
									.. ")("
									.. x
									.. ") = "
									.. got
									.. ", expected "
									.. ref.values[i]
							)
						end
					end
				end
			end)

			T.it("CSS ease(0.5) is about 0.8024", function()
				T.expect(Easing.bezier(0.25, 0.1, 0.25, 1)(0.5)).toBeCloseTo(0.8024034, 1e-6)
			end)

			T.it("agrees with an independent bisection for many control points", function()
				local rand = lcg(12345)
				for _ = 1, 150 do
					local x1, x2 = rand(), rand()
					local y1, y2 = rand() * 4 - 1.5, rand() * 4 - 1.5
					local f = Easing.bezier(x1, y1, x2, y2)
					for i = 1, 19 do
						local x = i / 20
						local expected = referenceBezier(x1, y1, x2, y2, x)
						if math.abs(f(x) - expected) > 1e-7 then
							T.fail(
								string.format(
									"bezier(%g, %g, %g, %g)(%g) = %g, expected %g",
									x1,
									y1,
									x2,
									y2,
									x,
									f(x),
									expected
								)
							)
						end
					end
				end
			end)

			T.it("handles degenerate handles (plateaus, x1 = x2 = 0 or 1) robustly", function()
				local cases = {
					{ 0, 0, 0, 1 },
					{ 1, 0, 1, 1 },
					{ 0, 1, 0, 1 },
					{ 1, 0, 0, 1 },
					{ 1, 1, 0, 0 },
					{ 0.5, 0, 0.5, 1 },
				}
				for _, p in cases do
					local f = Easing.bezier(p[1], p[2], p[3], p[4])
					for i = 0, 400 do
						local x = i / 400
						local v = f(x)
						T.expect(v == v).toBe(true)
						-- Where x'(s) = 0 (plateau) y(x) has a vertical tangent: both solvers are only accurate to
						-- about the cube root of the x tolerance there.
						T.expect(v).toBeCloseTo(referenceBezier(p[1], p[2], p[3], p[4], x), 1e-3)
					end
				end
			end)

			T.it("is monotone in x when y1, y2 are within [0, 1]", function()
				for _, p in { { 0.25, 0.1, 0.25, 1 }, { 0.42, 0, 0.58, 1 }, { 1, 0, 0, 1 }, { 0.9, 0.1, 0.1, 0.9 } } do
					local f = Easing.bezier(p[1], p[2], p[3], p[4])
					local previous = 0
					for i = 0, 1000 do
						local v = f(i / 1000)
						T.expect(v).toBeGreaterThanOrEqual(previous - 1e-9)
						previous = v
					end
				end
			end)

			T.it("accepts unbounded y values (overshoot)", function()
				local f = Easing.bezier(0.5, -2, 0.5, 3)
				local low, high = 0, 1
				for i = 0, 100 do
					local v = f(i / 100)
					low, high = math.min(low, v), math.max(high, v)
				end
				T.expect(low).toBeLessThan(-0.1)
				T.expect(high).toBeGreaterThan(1.1)
			end)

			T.it("rejects x outside [0, 1] and non-finite control points", function()
				T.expect(function()
					Easing.bezier(-0.1, 0, 1, 1)
				end).toThrow("x1")
				T.expect(function()
					Easing.bezier(0, 0, 1.5, 1)
				end).toThrow("x2")
				T.expect(function()
					Easing.bezier(0, 0 / 0, 1, 1)
				end).toThrow("y1")
				T.expect(function()
					Easing.bezier(0, 0, 1, math.huge)
				end).toThrow("y2")
				T.expect(function()
					(Easing.bezier :: any)(0, 0, 1)
				end).toThrow("y2")
			end)

			T.it("is deterministic", function()
				local a = Easing.bezier(0.3, 0.8, 0.2, 1.2)
				local b = Easing.bezier(0.3, 0.8, 0.2, 1.2)
				for i = 0, 100 do
					T.expect(a(i / 100)).toBe(b(i / 100))
				end
			end)
		end)

		T.describe("check", function()
			T.it("accepts every valid definition", function()
				local valid: { any } =
					{ "Linear", "Constant", "Quad", "Back.InOut", "Elastic.In", "Bounce.Out", "Linear.In" }
				for _, style in Easing.STYLES do
					table.insert(valid, style)
					for _, direction in DIRECTIONS do
						table.insert(valid, style .. "." .. direction)
					end
				end
				table.insert(valid, { bezier = { 0.25, 0.1, 0.25, 1 } })
				table.insert(valid, { bezier = { 0, -5, 1, 7 } })
				table.insert(valid, { bezier = { 1, 0, 0, 1 } })
				for _, def in valid do
					local ok, err = Easing.check(def)
					if not ok then
						T.fail("rejected " .. tostring(def) .. ": " .. tostring(err))
					end
				end
				T.expect(Easing.check(nil)).toBe(true)
			end)

			T.it("rejects invalid definitions with precise messages", function()
				local cases: { { any } } = {
					{ "quad.out", 'did you mean "Quad"' },
					{ "Quad.out", 'did you mean "Out"' },
					{ "Quad.OutIn", "OutIn" },
					{ "Spring", "not supported" },
					{ "Bezier.InOut", "not supported" },
					{ "Wobble", "unknown easing style" },
					{ "", "empty" },
					{ "Quad.", "unknown easing direction" },
					{ "Quad.In.Out", "unknown easing direction" },
					{ ".In", "unknown easing style" },
					{ 5, "got 5" },
					{ true, "got boolean" },
					{ { bezier = { 0, 0, 1 } }, "exactly 4" },
					{ { bezier = { 0, 0, 1, 1, 1 } }, "exactly 4" },
					{ { bezier = { 1.2, 0, 1, 1 } }, "x1 must be within 0..1" },
					{ { bezier = { 0, 0, -0.01, 1 } }, "x2 must be within 0..1" },
					{ { bezier = { 0, 0 / 0, 1, 1 } }, "y1 must be a finite number" },
					{ { bezier = { 0, 0, 1, "1" :: any } }, "y2 must be a finite number" },
					{ { bezier = "0,0,1,1" }, "bezier = { x1, y1, x2, y2 }" },
					{ { curve = { 0, 0, 1, 1 } }, "unexpected key" },
					{ { bezier = { 0, 0, 1, 1 }, extra = 1 }, "unexpected key" },
					{ {}, "bezier = { x1, y1, x2, y2 }" },
					{ { bezier = { x1 = 0, y1 = 0, x2 = 1, y2 = 1 } }, "exactly 4" },
				}
				for _, case in cases do
					local ok, err = Easing.check(case[1])
					if ok then
						T.fail("accepted " .. tostring(case[1]))
					end
					T.expect(err).toContain(case[2])
				end
			end)
		end)

		T.describe("parse", function()
			T.it("treats nil as Linear", function()
				local f, isConstant = Easing.parse(nil)
				T.expect(f).toBe(Easing.get("Linear"))
				T.expect(isConstant).toBe(false)
			end)
			T.it("resolves style names to the cached curves", function()
				T.expect((Easing.parse("Quad"))).toBe(Easing.get("Quad", "Out"))
				T.expect((Easing.parse("Quad.InOut"))).toBe(Easing.get("Quad", "InOut"))
				T.expect((Easing.parse("Back.In"))).toBe(Easing.get("Back", "In"))
				local _, isConstant = Easing.parse("Quad.In")
				T.expect(isConstant).toBe(false)
			end)
			T.it("flags Constant segments", function()
				local f, isConstant = Easing.parse("Constant")
				T.expect(isConstant).toBe(true)
				T.expect(f(0.5)).toBe(0)
				T.expect(f(1)).toBe(1)
			end)
			T.it("builds bezier curves", function()
				local f, isConstant = Easing.parse({ bezier = { 0.25, 0.1, 0.25, 1 } })
				T.expect(isConstant).toBe(false)
				T.expect(f(0.5)).toBeCloseTo(0.802403387584857, 1e-8)
			end)
			T.it("errors on invalid definitions", function()
				T.expect(function()
					Easing.parse("quad.out")
				end).toThrow("Easing.parse")
				T.expect(function()
					Easing.parse({ bezier = { 2, 0, 1, 1 } })
				end).toThrow("x1")
				T.expect(function()
					Easing.parse("Quad.OutIn")
				end).toThrow("OutIn")
			end)
		end)

		T.describe("normalize", function()
			T.it("returns the canonical form", function()
				T.expect(Easing.normalize("Quad")).toBe("Quad")
				T.expect(Easing.normalize("Quad.Out")).toBe("Quad")
				T.expect(Easing.normalize("Quad.In")).toBe("Quad.In")
				T.expect(Easing.normalize("Back.InOut")).toBe("Back.InOut")
				T.expect(Easing.normalize("Linear")).toBe("Linear")
				T.expect(Easing.normalize("Linear.InOut")).toBe("Linear")
				T.expect(Easing.normalize("Constant")).toBe("Constant")
				T.expect(Easing.normalize("Constant.In")).toBe("Constant")
				T.expect(Easing.normalize(nil)).toBe("Linear")
			end)
			T.it("copies bezier definitions and drops -0", function()
				local def = { bezier = { -0, 0.1, 0.25, 1 } }
				local n = Easing.normalize(def)
				T.expect(n).toEqual({ bezier = { 0, 0.1, 0.25, 1 } })
				T.expect(n).never.toBe(def)
				T.expect(n.bezier).never.toBe(def.bezier)
				T.expect(1 / n.bezier[1]).toBe(math.huge)
			end)
			T.it("is idempotent and keeps the meaning", function()
				local defs: { any } = { "Quad", "Elastic.InOut", "Linear.In", { bezier = { 0.1, 0.2, 0.3, 0.4 } } }
				for _, style in Easing.STYLES do
					for _, direction in DIRECTIONS do
						table.insert(defs, style .. "." .. direction)
					end
				end
				for _, def in defs do
					local once = Easing.normalize(def)
					T.expect(Easing.normalize(once)).toEqual(once)
					local a, b = Easing.parse(def), Easing.parse(once)
					for i = 0, 20 do
						T.expect(a(i / 20)).toBe(b(i / 20))
					end
				end
			end)
			T.it("errors on invalid definitions", function()
				T.expect(function()
					Easing.normalize("quad.out")
				end).toThrow("Easing.normalize")
				T.expect(function()
					Easing.normalize({ bezier = { 0, 0, 1 } } :: any)
				end).toThrow("exactly 4")
			end)
		end)

		T.itIf(ctx.environment == "studio", "matches TweenService:GetValue for every Roblox style", function()
			local TweenService = game:GetService("TweenService")
			for _, style in ROBLOX_STYLES do
				for _, direction in DIRECTIONS do
					local f = Easing.get(style, direction)
					for i = 0, 100 do
						local alpha = i / 100
						local expected = TweenService:GetValue(
							alpha,
							(Enum.EasingStyle :: any)[style],
							(Enum.EasingDirection :: any)[direction]
						)
						if math.abs(f(alpha) - expected) > 1e-4 then
							T.fail(
								style
									.. "."
									.. direction
									.. "("
									.. alpha
									.. ") = "
									.. f(alpha)
									.. ", TweenService "
									.. expected
							)
						end
					end
				end
			end
		end)
	end)
end
