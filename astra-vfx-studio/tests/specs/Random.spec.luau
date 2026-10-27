--!strict
return function(T: any, use: (string) -> any, _ctx: any)
	local Random = use("AstraVFX.Core.Random")

	local TWO_32 = 4294967296

	-- Raw 32-bit outputs (next() * 2^32) of the first draws. Reference values were computed once with an
	-- independent JavaScript implementation (Math.imul-based mulberry32 + murmur3 fmix32 seed scramble) and
	-- hard-coded here; the Luau implementation must reproduce them bit for bit on every platform.
	local EXPECTED: { [number]: { number } } = {
		[0] = { 2673918951, 1525398398, 1851933717, 1087923286, 744930619, 2388801345 },
		[1] = { 711699459, 1679400207, 1692264768, 2520730185, 1490823452, 3351641948 },
		[42] = { 763744907, 2711839145, 2121928412, 3759587137, 2652876385, 2058458190 },
		[123456789] = { 851475982, 2160415319, 1074201607, 3025237881, 4060174574, 2047057925 },
	}

	local function raw(rng: any, count: number): { number }
		local out = {}
		for i = 1, count do
			out[i] = rng:next() * TWO_32
		end
		return out
	end

	local function angleDeg(a: Vector3, b: Vector3): number
		local c = math.clamp(a.Unit:Dot(b.Unit), -1, 1)
		return math.deg(math.acos(c))
	end

	T.describe("Random.new / next", function()
		T.it("reproduces the reference sequences bit for bit", function()
			for seed, expected in EXPECTED do
				T.expect(raw(Random.new(seed), #expected)).toEqual(expected)
			end
		end)
		T.it("reproduces the reference value after 100000 draws", function()
			local rng = Random.new(7)
			local v = 0
			for _ = 1, 100000 do
				v = rng:next()
			end
			T.expect(v * TWO_32).toBe(3832933170)
		end)
		T.it("returns multiples of 2^-32 in [0, 1)", function()
			local rng = Random.new(99)
			local lo, hi = 1, 0
			for _ = 1, 10000 do
				local x = rng:next()
				T.expect(x >= 0 and x < 1).toBe(true)
				T.expect((x * TWO_32) % 1).toBe(0)
				lo = math.min(lo, x)
				hi = math.max(hi, x)
			end
			T.expect(lo).toBeLessThan(0.001)
			T.expect(hi).toBeGreaterThan(0.999)
		end)
		T.it("is deterministic per seed and independent between generators", function()
			local a, b = Random.new(5), Random.new(5)
			local interleaved = {}
			for i = 1, 50 do
				interleaved[i] = a:next()
				Random.new(5):next() -- unrelated generators must not disturb a or b
			end
			for i = 1, 50 do
				T.expect(b:next()).toBe(interleaved[i])
			end
		end)
		T.it("does not depend on math.random state", function()
			math.randomseed(1)
			local first = raw(Random.new(3), 10)
			math.randomseed(987654)
			local _ = math.random()
			T.expect(raw(Random.new(3), 10)).toEqual(first)
		end)
		T.it("gives different sequences for different (neighbouring) seeds", function()
			local firsts = {}
			local sum = 0
			for seed = 0, 199 do
				local v = Random.new(seed):next()
				T.expect(firsts[v]).toBeNil()
				firsts[v] = true
				sum += v
			end
			T.expect(sum / 200).toBeCloseTo(0.5, 0.06)
			T.expect(raw(Random.new(1), 4)).never.toEqual(raw(Random.new(2), 4))
		end)
		T.it("reduces integer seeds modulo 2^32", function()
			T.expect(raw(Random.new(-1), 6)).toEqual(raw(Random.new(4294967295), 6))
			T.expect(raw(Random.new(TWO_32 + 5), 6)).toEqual(raw(Random.new(5), 6))
			T.expect(raw(Random.new(-TWO_32 * 3 + 42), 6)).toEqual(EXPECTED[42])
			T.expect(raw(Random.new(-0), 6)).toEqual(EXPECTED[0])
		end)
		T.it("hashes non-integer seeds and treats nil as 0", function()
			T.expect(raw(Random.new(0.5), 4)).toEqual(raw(Random.new(Random.hash(0.5)), 4))
			T.expect(raw(Random.new(2 ^ 60), 4)).toEqual(raw(Random.new(Random.hash(2 ^ 60)), 4))
			T.expect(raw(Random.new("fire" :: any), 4)).toEqual(raw(Random.new(Random.hash("fire")), 4))
			T.expect(raw(Random.new(nil), 6)).toEqual(EXPECTED[0])
			T.expect(raw(Random.new(), 6)).toEqual(EXPECTED[0])
			T.expect(raw(Random.new(0.5), 4)).never.toEqual(raw(Random.new(0), 4))
		end)
		T.it("accepts NaN and infinite seeds deterministically", function()
			for _, seed in { 0 / 0, math.huge, -math.huge } do
				local a, b = raw(Random.new(seed), 5), raw(Random.new(seed), 5)
				T.expect(a).toEqual(b)
				for _, v in a do
					T.expect(v >= 0 and v < TWO_32).toBe(true)
				end
			end
			T.expect(raw(Random.new(0 / 0), 5)).toEqual(raw(Random.new(-(0 / 0)), 5))
		end)
		T.it("rejects seeds that cannot be hashed deterministically", function()
			T.expect(function()
				Random.new({} :: any)
			end).toThrow("unsupported part")
		end)
	end)

	T.describe("distribution", function()
		T.it("has mean 0.5 and variance 1/12 over 10k samples", function()
			local rng = Random.new(2024)
			local sum, sumSq = 0, 0
			local samples = {}
			for i = 1, 10000 do
				local x = rng:next()
				samples[i] = x
				sum += x
				sumSq += x * x
			end
			local mean = sum / 10000
			local variance = sumSq / 10000 - mean * mean
			T.expect(mean).toBeCloseTo(0.5, 0.01)
			T.expect(variance).toBeCloseTo(1 / 12, 0.005)
			-- lag-1 autocorrelation close to 0
			local cov = 0
			for i = 1, 9999 do
				cov += (samples[i] - mean) * (samples[i + 1] - mean)
			end
			T.expect(math.abs(cov / 9999 / variance)).toBeLessThan(0.03)
		end)
		T.it("fills 10 buckets evenly (chi-square sanity)", function()
			local rng = Random.new(31337)
			local buckets = table.create(10, 0)
			for _ = 1, 10000 do
				local b = math.floor(rng:next() * 10) + 1
				buckets[b] += 1
			end
			local chi = 0
			for _, count in buckets do
				T.expect(count).toBeGreaterThan(880)
				T.expect(count).toBeLessThan(1120)
				chi += (count - 1000) ^ 2 / 1000
			end
			T.expect(chi).toBeLessThan(27.9) -- p = 0.001 for 9 degrees of freedom
		end)
		T.it("keeps the mean near 0.5 for many seeds", function()
			for seed = 1, 20 do
				local rng = Random.new(seed * 7919)
				local sum = 0
				for _ = 1, 2000 do
					sum += rng:next()
				end
				T.expect(sum / 2000).toBeCloseTo(0.5, 0.03)
			end
		end)
	end)

	T.describe("range / int / sign", function()
		T.it("range stays within [min, max)", function()
			local rng = Random.new(8)
			local sum = 0
			for _ = 1, 5000 do
				local x = rng:range(2, 4)
				T.expect(x >= 2 and x < 4).toBe(true)
				sum += x
			end
			T.expect(sum / 5000).toBeCloseTo(3, 0.03)
			T.expect(rng:range(5, 5)).toBe(5)
			local y = rng:range(-1, -3)
			T.expect(y <= -1 and y > -3).toBe(true)
		end)
		T.it("int includes both bounds and nothing outside", function()
			local rng = Random.new(77)
			local counts = {}
			for _ = 1, 6000 do
				local v = rng:int(1, 6)
				T.expect(v % 1).toBe(0)
				T.expect(v >= 1 and v <= 6).toBe(true)
				counts[v] = (counts[v] or 0) + 1
			end
			for face = 1, 6 do
				T.expect(counts[face]).toBeGreaterThan(850)
				T.expect(counts[face]).toBeLessThan(1150)
			end
			local seen = {}
			for _ = 1, 500 do
				seen[rng:int(-3, 3)] = true
			end
			T.expect(seen[-3]).toBe(true)
			T.expect(seen[3]).toBe(true)
			T.expect(seen[4]).toBeNil()
			T.expect(seen[-4]).toBeNil()
		end)
		T.it("int matches the reference sequence", function()
			local rng = Random.new(42)
			local values = {}
			for i = 1, 8 do
				values[i] = rng:int(1, 100)
			end
			T.expect(values).toEqual({ 18, 64, 50, 88, 62, 48, 61, 1 })
		end)
		T.it("int handles equal, swapped and fractional bounds", function()
			local rng = Random.new(3)
			T.expect(rng:int(5, 5)).toBe(5)
			for _ = 1, 200 do
				local v = rng:int(6, 1)
				T.expect(v >= 1 and v <= 6).toBe(true)
				local w = rng:int(0.5, 2.5)
				T.expect(w == 1 or w == 2).toBe(true)
			end
			T.expect(rng:int(-2 ^ 40, 2 ^ 40) % 1).toBe(0)
		end)
		T.it("int rejects empty and non-finite ranges", function()
			local rng = Random.new(3)
			T.expect(function()
				rng:int(0.2, 0.8)
			end).toThrow("no integer between")
			T.expect(function()
				rng:int(0 / 0, 1)
			end).toThrow("finite")
			T.expect(function()
				rng:int(-math.huge, 0)
			end).toThrow("finite")
		end)
		T.it("sign returns only -1 and 1, balanced", function()
			local rng = Random.new(42)
			local first = {}
			for i = 1, 8 do
				first[i] = rng:sign()
			end
			T.expect(first).toEqual({ -1, 1, -1, 1, 1, -1, 1, -1 })
			local positives = 0
			for _ = 1, 10000 do
				local s = rng:sign()
				T.expect(s == 1 or s == -1).toBe(true)
				if s == 1 then
					positives += 1
				end
			end
			T.expect(positives).toBeGreaterThan(4800)
			T.expect(positives).toBeLessThan(5200)
		end)
	end)

	T.describe("vectors", function()
		T.it("unitVector matches the reference values", function()
			local rng = Random.new(42)
			T.expect(rng:unitVector())
				.toBeCloseTo(Vector3.new(-0.9254904132167944, 0.3774596942644243, 0.03149085977890298), 1e-6)
			T.expect(rng:unitVector())
				.toBeCloseTo(Vector3.new(-0.01572102678933871, 0.9917310932974911, -0.12736674567426176), 1e-6)
		end)
		T.it("unitVector has length 1 and is uniform on the sphere", function()
			local rng = Random.new(12)
			local sum = Vector3.zero
			local absZ, zSq = 0, 0
			local count = 5000
			for _ = 1, count do
				local v = rng:unitVector()
				T.expect(v.Magnitude).toBeCloseTo(1, 1e-6)
				sum += v
				absZ += math.abs(v.Z)
				zSq += v.Z * v.Z
			end
			T.expect((sum / count).Magnitude).toBeLessThan(0.04)
			T.expect(absZ / count).toBeCloseTo(0.5, 0.02) -- z is uniform in [-1, 1] on a sphere
			T.expect(zSq / count).toBeCloseTo(1 / 3, 0.02)
		end)
		T.it("inCone matches the reference values", function()
			local rng = Random.new(42)
			T.expect(rng:inCone(Vector3.new(0, 0, -1), 30))
				.toBeCloseTo(Vector3.new(-0.2167571815963226, -0.009815233411979825, -0.976176206132626), 1e-6)
			T.expect(rng:inCone(Vector3.new(1, 2, 3), 60))
				.toBeCloseTo(Vector3.new(0.9471220817036192, 0.17933589914913778, 0.2660796828504066), 1e-6)
		end)
		T.it("inCone stays within the cone for many directions and angles", function()
			local rng = Random.new(5)
			local directions = {
				Vector3.new(0, 0, -1),
				Vector3.new(0, 1, 0), -- exercises the helper-axis switch
				Vector3.new(0, -5, 0),
				Vector3.new(1, 2, 3),
				Vector3.new(-0.3, 0.95, 0.1),
			}
			for _, dir in directions do
				for _, angle in { 0, 5, 30, 45, 90, 135, 180 } do
					for _ = 1, 200 do
						local v = rng:inCone(dir, angle)
						T.expect(v.Magnitude).toBeCloseTo(1, 1e-5)
						T.expect(angleDeg(v, dir)).toBeLessThanOrEqual(angle + 0.01)
					end
				end
			end
		end)
		T.it("inCone with angle 0 returns the direction itself", function()
			local rng = Random.new(1)
			T.expect(rng:inCone(Vector3.new(0, 0, -3), 0)).toBeCloseTo(Vector3.new(0, 0, -1), 1e-6)
			T.expect(rng:inCone(Vector3.new(2, 0, 0), -10)).toBeCloseTo(Vector3.new(1, 0, 0), 1e-6) -- clamped
			T.expect(rng:inCone(Vector3.new(0, 1, 0), 0 / 0)).toBeCloseTo(Vector3.new(0, 1, 0), 1e-6) -- NaN → 0
		end)
		T.it("inCone samples the spherical cap uniformly", function()
			local rng = Random.new(9)
			local dir = Vector3.new(1, 1, 0).Unit
			local count = 5000
			local sumCos = 0
			local sum = Vector3.zero
			for _ = 1, count do
				local v = rng:inCone(dir, 60)
				sumCos += v:Dot(dir)
				sum += v
			end
			-- E[cos θ] over a uniform cap of half-angle α is (1 + cos α) / 2 = 0.75 for 60°.
			T.expect(sumCos / count).toBeCloseTo(0.75, 0.01)
			-- Azimuth is uniform: the mean vector points along the axis.
			local mean = sum / count
			T.expect((mean - dir * mean:Dot(dir)).Magnitude).toBeLessThan(0.02)
		end)
		T.it("inCone covers the whole sphere at 180 degrees and the hemisphere at 90", function()
			local rng = Random.new(10)
			local behind = 0
			for _ = 1, 2000 do
				local v = rng:inCone(Vector3.new(0, 0, -1), 180)
				if v.Z > 0 then
					behind += 1
				end
				T.expect(rng:inCone(Vector3.new(0, 0, -1), 90).Z).toBeLessThanOrEqual(1e-6)
			end
			T.expect(behind).toBeGreaterThan(900)
			T.expect(behind).toBeLessThan(1100)
			T.expect(rng:inCone(Vector3.new(0, 0, -1), 720).Magnitude).toBeCloseTo(1, 1e-5) -- clamped to 180
		end)
		T.it("inCone falls back to unitVector for a zero or non-finite direction", function()
			local a, b = Random.new(4), Random.new(4)
			T.expect(a:inCone(Vector3.zero, 10)).toBeCloseTo(b:unitVector(), 1e-9)
			local v = a:inCone(Vector3.new(0 / 0, 0, 0), 10)
			T.expect(v.Magnitude).toBeCloseTo(1, 1e-5)
		end)
	end)

	T.describe("pick / clone", function()
		T.it("pick matches the reference sequence and reaches every element", function()
			local rng = Random.new(42)
			local list = { "a", "b", "c", "d", "e" }
			local picks = {}
			for i = 1, 8 do
				picks[i] = rng:pick(list)
			end
			T.expect(picks).toEqual({ "a", "d", "c", "e", "d", "c", "d", "a" })
			local seen = {}
			for _ = 1, 500 do
				seen[rng:pick(list)] = true
			end
			for _, item in list do
				T.expect(seen[item]).toBe(true)
			end
		end)
		T.it("pick handles empty and single-element lists", function()
			local a, b = Random.new(6), Random.new(6)
			T.expect(a:pick({})).toBeNil()
			T.expect(a:next()).toBe(b:next()) -- an empty pick consumes nothing
			T.expect(a:pick({ "only" })).toBe("only")
		end)
		T.it("clone continues the same sequence independently", function()
			local rng = Random.new(1234)
			rng:next()
			rng:next()
			local copy = rng:clone()
			local fromCopy = raw(copy, 10)
			T.expect(raw(rng, 10)).toEqual(fromCopy)
			copy:next()
			copy:next()
			local again = rng:clone()
			T.expect(raw(again, 5)).toEqual(raw(rng, 5))
		end)
	end)

	T.describe("Random.hash", function()
		T.it("matches FNV-1a 32-bit test vectors", function()
			T.expect(Random.hash("")).toBe(0x811C9DC5)
			T.expect(Random.hash()).toBe(0x811C9DC5)
			T.expect(Random.hash("a")).toBe(0xE40C292C)
			T.expect(Random.hash("foobar")).toBe(0xBF9CF968)
			T.expect(Random.hash("VioletImpact")).toBe(980252232)
			T.expect(Random.hash("äöü")).toBe(1138454712) -- UTF-8 bytes
		end)
		T.it("hashes numbers through tostring with normalized -0 and NaN", function()
			T.expect(Random.hash(42)).toBe(Random.hash("42"))
			T.expect(Random.hash(42)).toBe(2279835011)
			T.expect(Random.hash(0.5)).toBe(Random.hash("0.5"))
			T.expect(Random.hash(-0)).toBe(Random.hash(0))
			T.expect(Random.hash(0 / 0)).toBe(Random.hash(-(0 / 0)))
			T.expect(Random.hash(0 / 0)).toBe(Random.hash("nan"))
			T.expect(Random.hash(true :: any)).toBe(Random.hash("true"))
		end)
		T.it("separates parts and respects their order", function()
			T.expect(Random.hash("seed", "comp")).toBe(131590926)
			T.expect(Random.hash("ab", "c")).toBe(3483414340)
			T.expect(Random.hash("a", "bc")).toBe(1525061270)
			T.expect(Random.hash(1, 2)).never.toBe(Random.hash(2, 1))
			T.expect(Random.hash("x", nil :: any, "y")).toBe(Random.hash("x", "nil", "y"))
			T.expect(Random.hash(7, "id")).toBe(Random.hash(7, "id"))
		end)
		T.it("returns unsigned 32-bit integers", function()
			for i = 1, 500 do
				local h = Random.hash("component-" .. i, i)
				T.expect(h % 1).toBe(0)
				T.expect(h >= 0 and h < TWO_32).toBe(true)
			end
		end)
		T.it("rejects parts without a deterministic text form", function()
			T.expect(function()
				Random.hash({} :: any)
			end).toThrow("unsupported part of type table")
			T.expect(function()
				Random.hash("ok", Vector3.one :: any)
			end).toThrow("unsupported part of type Vector3")
			T.expect(function()
				Random.hash(print :: any)
			end).toThrow("unsupported part")
		end)
	end)
end
