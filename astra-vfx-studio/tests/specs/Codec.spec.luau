--!strict
return function(T: any, use: (string) -> any, _ctx: any)
	local Codec = use("AstraVFX.Core.Codec")

	-- Deterministic pseudo-random numbers in [0, 1) (no math.random).
	local function lcg(seed: number): () -> number
		local state = seed
		return function(): number
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
	end

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function L(...: any): { any }
		return { ... }
	end

	-- Compact value printer for failure messages.
	local function show(v: any, depth: number?): string
		local d = depth or 0
		if type(v) == "string" then
			return string.format("%q", v)
		elseif type(v) == "table" then
			if d > 3 then
				return "{...}"
			end
			local parts = {}
			local n = #v
			for i = 1, n do
				table.insert(parts, show(v[i], d + 1))
			end
			for k, x in pairs(v) do
				if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
					table.insert(parts, tostring(k) .. "=" .. show(x, d + 1))
				end
			end
			return "{" .. table.concat(parts, ", ") .. "}"
		elseif type(v) == "number" then
			return string.format("%.17g", v)
		end
		return typeof(v) .. "(" .. tostring(v) .. ")"
	end

	-- Exact structural equality (numbers compared with ==).
	local function same(a: any, b: any): boolean
		if type(a) ~= "table" or type(b) ~= "table" then
			return a == b
		end
		for k, x in pairs(a) do
			if not same(x, b[k]) then
				return false
			end
		end
		for k in pairs(b) do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	local function expectValid(kind: string, value: any, spec: any?)
		local ok, err = Codec.check(kind, value, spec)
		if not ok then
			T.fail(kind .. ": rejected " .. show(value) .. ": " .. tostring(err))
		end
	end

	-- Asserts check() fails with a message containing `fragment` (and optionally the given problem class),
	-- and that normalize() and decode() raise an error for structural problems.
	local function expectInvalid(kind: string, value: any, fragment: string, spec: any?, problem: string?)
		local ok, err, cls = Codec.check(kind, value, spec)
		if ok then
			T.fail(kind .. ": accepted " .. show(value))
		end
		T.expect(type(err)).toBe("string")
		if string.find(err, fragment, 1, true) == nil then
			T.fail(kind .. ": message for " .. show(value) .. " was " .. show(err) .. ", expected " .. show(fragment))
		end
		if problem then
			T.expect(cls).toBe(problem)
		end
		if cls ~= "range" then
			T.expect(function()
				Codec.normalize(kind, value, spec)
			end).toThrow("Codec.normalize(" .. kind .. ")")
			T.expect(function()
				Codec.decode(kind, value, spec)
			end).toThrow("Codec.decode(" .. kind .. ")")
		end
	end

	-- normalize(x) == encode(decode(x)), normalize is idempotent and its output passes check.
	local function expectRoundTrip(kind: string, value: any, spec: any?)
		local normalized = Codec.normalize(kind, value, spec)
		local decoded = Codec.decode(kind, value, spec)
		local encoded = Codec.encode(kind, decoded, spec)
		if not same(encoded, normalized) then
			T.fail(
				kind
					.. ": encode(decode("
					.. show(value)
					.. ")) = "
					.. show(encoded)
					.. " but normalize = "
					.. show(normalized)
			)
		end
		T.expect(Codec.normalize(kind, normalized, spec)).toEqual(normalized)
		local ok, err = Codec.check(kind, normalized, spec)
		if not ok then
			T.fail(kind .. ": normalized value " .. show(normalized) .. " fails check: " .. tostring(err))
		end
	end

	T.describe("Codec", function()
		T.describe("kinds", function()
			T.it("lists every PropertyKind and ChannelKind", function()
				T.expect(Codec.KINDS).toHaveLength(13)
				for _, kind in Codec.CHANNEL_KINDS do
					T.expect(Codec.KINDS).toContain(kind)
				end
			end)
			T.it("reports unknown kinds", function()
				local ok, err = Codec.check("matrix", 1)
				T.expect(ok).toBe(false)
				T.expect(err).toContain("unknown value kind")
				T.expect(function()
					Codec.normalize("matrix", 1)
				end).toThrow("unknown value kind")
				T.expect(function()
					Codec.decode("matrix", 1)
				end).toThrow("unknown value kind")
				T.expect(function()
					Codec.encode("matrix", 1)
				end).toThrow("unknown value kind")
			end)
			T.it("rejects a spec that is not a table", function()
				T.expect(function()
					Codec.check("number", 1, "spec" :: any)
				end).toThrow("spec must be")
			end)
		end)

		T.describe("number", function()
			T.it("accepts finite numbers", function()
				for _, v in { 0, -5, 1.5, 1e300, -1e-300 } do
					expectValid("number", v)
					T.expect(Codec.decode("number", v)).toBe(v)
				end
			end)
			T.it("rejects other types and non-finite numbers", function()
				expectInvalid("number", "1", 'must be a number, got "1"')
				expectInvalid("number", nil, "got nil")
				expectInvalid("number", true, "got true")
				expectInvalid("number", { 1 }, "got an array of 1 item")
				expectInvalid("number", 0 / 0, "finite number, got NaN")
				expectInvalid("number", math.huge, "got inf")
				expectInvalid("number", -math.huge, "got -inf")
			end)
			T.it("checks min/max and clamps when decoding", function()
				local spec = { min = 0, max = 1 }
				expectValid("number", 0, spec)
				expectValid("number", 1, spec)
				expectInvalid("number", 1.5, "1.5 is above the maximum 1", spec, "range")
				expectInvalid("number", -0.25, "-0.25 is below the minimum 0", spec, "range")
				T.expect(Codec.decode("number", 1.5, spec)).toBe(1)
				T.expect(Codec.decode("number", -3, spec)).toBe(0)
				T.expect(Codec.normalize("number", 7, spec)).toBe(1)
				T.expect(Codec.encode("number", 9, spec)).toBe(1)
				T.expect(Codec.normalize("number", 7, { min = 0 })).toBe(7)
				T.expect(Codec.normalize("number", -7, { max = 0 })).toBe(-7)
			end)
			T.it("canonicalises -0 to 0", function()
				T.expect(1 / Codec.normalize("number", -0)).toBe(math.huge)
				T.expect(1 / Codec.encode("number", -0)).toBe(math.huge)
			end)
			T.it("encode rejects wrong types", function()
				T.expect(function()
					Codec.encode("number", "1")
				end).toThrow("Codec.encode(number): expected a number")
				T.expect(function()
					Codec.encode("number", 0 / 0)
				end).toThrow("finite")
			end)
		end)

		T.describe("integer", function()
			T.it("accepts whole numbers only", function()
				expectValid("integer", 3)
				expectValid("integer", -2)
				expectValid("integer", 0)
				expectInvalid("integer", 1.5, "whole number, got 1.5")
				expectInvalid("integer", "3", "must be a number")
				expectInvalid("integer", 2 ^ 54, "too large")
				expectInvalid("integer", 0 / 0, "finite")
			end)
			T.it("clamps to whole bounds", function()
				local spec = { min = 0.5, max = 3.5 }
				expectInvalid("integer", 0, "below the minimum 0.5", spec, "range")
				expectInvalid("integer", 4, "above the maximum 3.5", spec, "range")
				expectValid("integer", 1, spec)
				expectValid("integer", 3, spec)
				T.expect(Codec.normalize("integer", 0, spec)).toBe(1)
				T.expect(Codec.normalize("integer", 10, spec)).toBe(3)
				T.expect(Codec.decode("integer", -10, { min = 1, max = 10 })).toBe(1)
			end)
			T.it("encode rounds engine values", function()
				T.expect(Codec.encode("integer", 2.6)).toBe(3)
				T.expect(Codec.encode("integer", -2.4)).toBe(-2)
				T.expect(Codec.encode("integer", 50, { max = 20 })).toBe(20)
			end)
		end)

		T.describe("boolean", function()
			T.it("accepts true and false only", function()
				expectValid("boolean", true)
				expectValid("boolean", false)
				T.expect(Codec.decode("boolean", false)).toBe(false)
				T.expect(Codec.encode("boolean", true)).toBe(true)
				expectInvalid("boolean", 1, "true or false, got 1")
				expectInvalid("boolean", "true", 'got "true"')
				expectInvalid("boolean", nil, "got nil")
			end)
		end)

		T.describe("string", function()
			T.it("accepts UTF-8 strings", function()
				expectValid("string", "")
				expectValid("string", "Impact")
				expectValid("string", "Über ✦")
				T.expect(Codec.decode("string", "x")).toBe("x")
			end)
			T.it("rejects non-strings and invalid UTF-8", function()
				expectInvalid("string", 5, "must be a string")
				expectInvalid("string", "\255\254", "UTF-8")
			end)
			T.it("encode keeps engine strings verbatim", function()
				T.expect(Codec.encode("string", "\255")).toBe("\255")
				T.expect(function()
					Codec.encode("string", 1)
				end).toThrow("expected a string")
			end)
		end)

		T.describe("enum", function()
			local shape = { enum = { "Box", "Sphere", "Cylinder", "Disc" }, enumType = "ParticleEmitterShape" }
			T.it("accepts listed names and decodes to EnumItems", function()
				expectValid("enum", "Box", shape)
				T.expect(Codec.decode("enum", "Sphere", shape)).toBe(Enum.ParticleEmitterShape.Sphere)
				T.expect(Codec.normalize("enum", "Disc", shape)).toBe("Disc")
			end)
			T.it("rejects unlisted names with a case hint", function()
				expectInvalid("enum", "box", 'did you mean "Box"', shape, "range")
				expectInvalid("enum", "Cone", '"Cone" is not one of: Box, Sphere, Cylinder, Disc', shape, "range")
				T.expect(function()
					Codec.decode("enum", "Cone", shape)
				end).toThrow("not one of")
				expectInvalid("enum", 3, "enum item name", shape)
			end)
			T.it("returns names when there is no enumType", function()
				local spec = { enum = { "add", "mul" } }
				T.expect(Codec.decode("enum", "mul", spec)).toBe("mul")
				T.expect(Codec.encode("enum", "add", spec)).toBe("add")
			end)
			T.it("without spec.enum accepts identifiers but decode needs a real item", function()
				local spec = { enumType = "Material" }
				expectValid("enum", "Neon", spec)
				expectValid("enum", "NotAMaterial", spec)
				expectInvalid("enum", "two words", "invalid enum item name", spec)
				T.expect(Codec.decode("enum", "Neon", spec)).toBe(Enum.Material.Neon)
				T.expect(function()
					Codec.decode("enum", "NotAMaterial", spec)
				end).toThrow("not an item of Enum.Material")
				T.expect(function()
					Codec.decode("enum", "Neon", { enumType = "NoSuchEnum" })
				end).toThrow("not an item of Enum.NoSuchEnum")
			end)
			T.it("encodes EnumItems by name, even when unlisted", function()
				T.expect(Codec.encode("enum", Enum.ParticleEmitterShape.Box, shape)).toBe("Box")
				T.expect(Codec.encode("enum", Enum.Material.Grass, { enum = { "Neon" }, enumType = "Material" }))
					.toBe("Grass")
				T.expect(function()
					Codec.encode("enum", 5, shape)
				end).toThrow("expected an EnumItem")
			end)
			T.it("decode passes EnumItems through", function()
				T.expect(Codec.decode("enum", Enum.ParticleEmitterShape.Cylinder, shape))
					.toBe(Enum.ParticleEmitterShape.Cylinder)
			end)
		end)

		T.describe("color3", function()
			T.it("accepts every documented colour form", function()
				local forms: { any } = {
					"#FF8000",
					"#ff8000",
					"#F80",
					"#000000",
					"#ffffff",
					{ 255, 128, 0 },
					{ 0, 0, 0 },
					"$primary",
					"$a-b_1",
				}
				for _, v in forms do
					expectValid("color3", v)
				end
			end)
			T.it("normalizes to uppercase #RRGGBB or keeps $key", function()
				T.expect(Codec.normalize("color3", "#ff8000")).toBe("#FF8000")
				T.expect(Codec.normalize("color3", "#f80")).toBe("#FF8800")
				T.expect(Codec.normalize("color3", { 255, 128, 0 })).toBe("#FF8000")
				T.expect(Codec.normalize("color3", { 127.6, 0.4, 254.5 })).toBe("#8000FF")
				T.expect(Codec.normalize("color3", "$primary")).toBe("$primary")
			end)
			T.it("rejects malformed colours with precise messages", function()
				expectInvalid("color3", "#12", 'invalid colour "#12"')
				expectInvalid("color3", "FF0000", 'invalid colour "FF0000"')
				expectInvalid("color3", "#GGGGGG", "invalid colour")
				expectInvalid("color3", "#FF00000", "invalid colour")
				expectInvalid("color3", "red", "invalid colour")
				expectInvalid("color3", { 256, 0, 0 }, "red component 256 is outside 0-255")
				expectInvalid("color3", { 0, -1, 0 }, "green component -1 is outside 0-255")
				expectInvalid("color3", L(0, 0, "1"), "blue component must be a number")
				expectInvalid("color3", { 1, 2 }, "[r, g, b] with 3 numbers")
				expectInvalid("color3", { 1, 2, 3, 4 }, "got an array of 4 items")
				expectInvalid("color3", { r = 1, g = 2, b = 3 }, "got an object")
				expectInvalid("color3", "$", "invalid palette reference")
				expectInvalid("color3", "$bad key", "invalid palette reference")
				expectInvalid("color3", "$" .. string.rep("k", 65), "invalid palette reference")
				expectInvalid("color3", 5, "expected a colour")
				expectInvalid("color3", nil, "got nil")
			end)
			T.it("decodes to exact Color3.fromRGB values", function()
				T.expect(Codec.decode("color3", "#FF8000")).toEqual(Color3.fromRGB(255, 128, 0))
				T.expect(Codec.decode("color3", "#F80")).toEqual(Color3.fromRGB(255, 136, 0))
				T.expect(Codec.decode("color3", { 10, 20, 30 })).toEqual(Color3.fromRGB(10, 20, 30))
			end)
			T.it("resolves palette references", function()
				local palette =
					{ primary = Color3.fromRGB(80, 160, 255), hot = Color3.new(2, -1, 0.5), text = "#00ff00" }
				T.expect(Codec.decode("color3", "$primary", nil, palette)).toEqual(Color3.fromRGB(80, 160, 255))
				T.expect(Codec.decode("color3", "$hot", nil, palette)).toEqual(Color3.new(1, 0, 0.5))
				T.expect(Codec.decode("color3", "$text", nil, palette)).toEqual(Color3.fromRGB(0, 255, 0))
				T.expect(function()
					Codec.decode("color3", "$missing", nil, palette)
				end).toThrow('unknown palette colour "$missing"')
				T.expect(function()
					Codec.decode("color3", "$primary")
				end).toThrow("no palette given")
				T.expect(function()
					Codec.decode("color3", "$bad", nil, { bad = "$primary" } :: any)
				end).toThrow("unknown palette colour")
			end)
			T.it("encodes Color3 values as hex", function()
				T.expect(Codec.encode("color3", Color3.new(1, 0.5, 0))).toBe("#FF8000")
				T.expect(Codec.encode("color3", Color3.new(2, -1, 0.5))).toBe("#FF0080")
				T.expect(function()
					Codec.encode("color3", "#FF0000")
				end).toThrow("expected a Color3")
			end)
			T.it("decode passes Color3 values through (clamped)", function()
				T.expect(Codec.decode("color3", Color3.fromRGB(1, 2, 3))).toEqual(Color3.fromRGB(1, 2, 3))
				T.expect(Codec.decode("color3", Color3.new(3, 0, 0))).toEqual(Color3.fromRGB(255, 0, 0))
			end)
		end)

		T.describe("toHex / parseColor", function()
			T.it("toHex rounds 0..1 floats to uppercase #RRGGBB", function()
				T.expect(Codec.toHex(Color3.new(1, 0.5, 0))).toBe("#FF8000")
				T.expect(Codec.toHex(Color3.new(0.2, 0.4, 0.6))).toBe("#336699")
				T.expect(Codec.toHex(Color3.fromRGB(1, 2, 3))).toBe("#010203")
				T.expect(Codec.toHex(Color3.new(0.999, 0.001, 0.5))).toBe("#FF0080")
				T.expect(function()
					Codec.toHex("#FFFFFF" :: any)
				end).toThrow("expected a Color3")
			end)
			T.it("toHex(fromRGB(v)) is exact for every 8-bit value", function()
				for v = 0, 255 do
					local expected = string.format("#%02X%02X%02X", v, 255 - v, (v * 7) % 256)
					T.expect(Codec.toHex(Color3.fromRGB(v, 255 - v, (v * 7) % 256))).toBe(expected)
				end
			end)
			T.it("parseColor returns a Color3 or nil", function()
				T.expect(Codec.parseColor("#FF0000")).toEqual(Color3.fromRGB(255, 0, 0))
				T.expect(Codec.parseColor({ 0, 255, 0 })).toEqual(Color3.fromRGB(0, 255, 0))
				T.expect(Codec.parseColor("#00f")).toEqual(Color3.fromRGB(0, 0, 255))
				local c = Color3.new(0.1, 0.2, 0.3)
				T.expect(Codec.parseColor(c)).toBe(c)
				T.expect(Codec.parseColor("$p", { p = Color3.new(0, 0, 1) })).toEqual(Color3.new(0, 0, 1))
				T.expect(Codec.parseColor("$p")).toBeNil()
				T.expect(Codec.parseColor("$q", { p = Color3.new(0, 0, 1) })).toBeNil()
				T.expect(Codec.parseColor("nope")).toBeNil()
				T.expect(Codec.parseColor({ 300, 0, 0 })).toBeNil()
				T.expect(Codec.parseColor(nil)).toBeNil()
			end)
		end)

		T.describe("vector3 / vector2", function()
			T.it("accept arrays and uniform numbers", function()
				expectValid("vector3", { 1, 2, 3 })
				expectValid("vector3", 2)
				expectValid("vector2", { 1, 2 })
				expectValid("vector2", -1)
				T.expect(Codec.normalize("vector3", 2)).toEqual({ 2, 2, 2 })
				T.expect(Codec.normalize("vector2", 0.5)).toEqual({ 0.5, 0.5 })
				T.expect(Codec.decode("vector3", { 1, -2, 3.5 })).toEqual(Vector3.new(1, -2, 3.5))
				T.expect(Codec.decode("vector2", { 4, 5 })).toEqual(Vector2.new(4, 5))
				T.expect(Codec.decode("vector3", 3)).toEqual(Vector3.new(3, 3, 3))
			end)
			T.it("reject malformed vectors", function()
				expectInvalid("vector3", { 1, 2 }, "expected [x, y, z] or a single number, got an array of 2 items")
				expectInvalid("vector3", { 1, 2, 3, 4 }, "got an array of 4 items")
				expectInvalid("vector3", L(1, 2, "3"), "Z component must be a number")
				expectInvalid("vector3", { 1, 0 / 0, 3 }, "Y component must be a finite number")
				expectInvalid("vector3", { x = 1, y = 2, z = 3 }, "got an object")
				expectInvalid("vector3", "1,2,3", "got")
				expectInvalid("vector3", { 1e39, 0, 0 }, "too large")
				expectInvalid("vector2", { 1, 2, 3 }, "expected [x, y]")
				expectInvalid("vector2", {}, "got an empty table")
				expectInvalid("vector2", true, "got true")
			end)
			T.it("apply min/max per component", function()
				local spec = { min = 0, max = 10 }
				expectInvalid("vector3", { 1, 11, 2 }, "Y component 11 is above the maximum 10", spec, "range")
				expectInvalid("vector3", -1, "value -1 is below the minimum 0", spec, "range")
				T.expect(Codec.normalize("vector3", { -5, 5, 50 }, spec)).toEqual({ 0, 5, 10 })
				T.expect(Codec.decode("vector2", { 20, -20 }, spec)).toEqual(Vector2.new(10, 0))
				T.expect(Codec.encode("vector3", Vector3.new(-1, 3, 12), spec)).toEqual({ 0, 3, 10 })
			end)
			T.it("strip float32 noise when encoding", function()
				local v = Vector3.new(0.1, 0.2, 0.3)
				T.expect(Codec.encode("vector3", v)).toEqual({ 0.1, 0.2, 0.3 })
				T.expect(Codec.encode("vector2", Vector2.new(1.1, -2.7))).toEqual({ 1.1, -2.7 })
				T.expect(Codec.normalize("vector3", { 1 / 3, 0, 0 })).toEqual({ 0.33333334, 0, 0 })
				T.expect(1 / Codec.normalize("vector3", { -0, 0, 0 })[1]).toBe(math.huge)
			end)
			T.it("encode rejects wrong types", function()
				T.expect(function()
					Codec.encode("vector3", { 1, 2, 3 })
				end).toThrow("expected a Vector3")
				T.expect(function()
					Codec.encode("vector2", Vector3.new(1, 2, 3))
				end).toThrow("expected a Vector2")
			end)
		end)

		T.describe("numberRange", function()
			T.it("accepts n and [min, max]", function()
				expectValid("numberRange", 2)
				expectValid("numberRange", { 1, 2 })
				expectValid("numberRange", { 3, 3 })
				T.expect(Codec.normalize("numberRange", { 1, 2 })).toEqual({ 1, 2 })
				T.expect(Codec.normalize("numberRange", { 3, 3 })).toBe(3)
				T.expect(Codec.normalize("numberRange", 1.5)).toBe(1.5)
			end)
			T.it("decodes to NumberRange", function()
				local r = Codec.decode("numberRange", { 0.5, 2 })
				T.expect(typeof(r)).toBe("NumberRange")
				T.expect(r.Min).toBe(0.5)
				T.expect(r.Max).toBe(2)
				local single = Codec.decode("numberRange", 4)
				T.expect(single.Min).toBe(4)
				T.expect(single.Max).toBe(4)
			end)
			T.it("rejects malformed ranges", function()
				expectInvalid("numberRange", { 3, 1 }, "range min 3 is greater than range max 1")
				expectInvalid("numberRange", { 1 }, "expected a number or [min, max]")
				expectInvalid("numberRange", { 1, 2, 3 }, "got an array of 3 items")
				expectInvalid("numberRange", L(1, "2"), "range max must be a number")
				expectInvalid("numberRange", "1..2", "expected a number or [min, max]")
				expectInvalid("numberRange", 0 / 0, "finite")
			end)
			T.it("clamps both ends", function()
				local spec = { min = 0, max = 20 }
				expectInvalid("numberRange", { -1, 5 }, "range min -1 is below the minimum 0", spec, "range")
				expectInvalid("numberRange", { 1, 25 }, "range max 25 is above the maximum 20", spec, "range")
				T.expect(Codec.normalize("numberRange", { -1, 25 }, spec)).toEqual({ 0, 20 })
				T.expect(Codec.normalize("numberRange", { 30, 40 }, spec)).toBe(20)
			end)
			T.it("encodes NumberRange (collapsing equal ends)", function()
				T.expect(Codec.encode("numberRange", NumberRange.new(1.1))).toBe(1.1)
				T.expect(Codec.encode("numberRange", NumberRange.new(0.1, 0.7))).toEqual({ 0.1, 0.7 })
				T.expect(function()
					Codec.encode("numberRange", 1)
				end).toThrow("expected a NumberRange")
			end)
		end)

		T.describe("numberSequence", function()
			T.it("accepts a number or 2..20 keypoints", function()
				expectValid("numberSequence", 1)
				expectValid("numberSequence", { { 0, 1 }, { 1, 0 } })
				expectValid("numberSequence", { { 0, 0.5, 0.1 }, { 0.5, 1, 0 }, { 1, 0 } })
				expectValid("numberSequence", { { 0, 0 }, { 0.5, 0 }, { 0.5, 1 }, { 1, 1 } }) -- equal times = step
				local keys = {}
				for i = 1, 20 do
					keys[i] = { (i - 1) / 19, i }
				end
				expectValid("numberSequence", keys)
			end)
			T.it("rejects sequences that break the engine rules", function()
				expectInvalid("numberSequence", {}, "got an empty table")
				expectInvalid("numberSequence", { { 0, 1 } }, "at least 2 keypoints")
				expectInvalid("numberSequence", { { 0.1, 1 }, { 1, 0 } }, "first keypoint must be at time 0, got 0.1")
				expectInvalid("numberSequence", { { 0, 1 }, { 0.9, 0 } }, "last keypoint must be at time 1, got 0.9")
				expectInvalid(
					"numberSequence",
					{ { 0, 1 }, { 0.6, 0 }, { 0.4, 0 }, { 1, 0 } },
					"keypoint 3 time 0.4 is before the previous keypoint's time 0.6"
				)
				expectInvalid(
					"numberSequence",
					{ { 0, 1 }, { 1.5, 0 }, { 1, 0 } },
					"keypoint 2 time 1.5 is outside 0..1"
				)
				expectInvalid(
					"numberSequence",
					{ { 0, 1, -0.5 }, { 1, 0 } },
					"keypoint 1 envelope -0.5 must not be negative"
				)
				expectInvalid("numberSequence", { { 0, 1, 0, 0 }, { 1, 0 } }, "keypoint 1 must be [time, value]")
				expectInvalid("numberSequence", { { 0 }, { 1, 0 } }, "keypoint 1 must be [time, value]")
				expectInvalid("numberSequence", { L(0, "1"), { 1, 0 } }, "keypoint 1 value must be a number")
				expectInvalid("numberSequence", { L("0", 1), { 1, 0 } }, "keypoint 1 time must be a number")
				expectInvalid("numberSequence", { 0, 1 }, "got a flat array")
				expectInvalid("numberSequence", "1", "expected a number or keypoints")
				expectInvalid("numberSequence", { { 0, 1 }, { 1, 0 / 0 } }, "keypoint 2 value must be a finite number")
				local keys = {}
				for i = 1, 21 do
					keys[i] = { (i - 1) / 20, 0 }
				end
				expectInvalid("numberSequence", keys, "21 keypoints; at most 20", nil, "range")
				T.expect(function()
					Codec.normalize("numberSequence", keys)
				end).toThrow("at most 20")
			end)
			T.it("honours spec.maxKeypoints (capped at the engine limit)", function()
				local three = { { 0, 0 }, { 0.5, 1 }, { 0.75, 1 }, { 1, 0 } }
				expectInvalid("numberSequence", three, "4 keypoints; at most 3", { maxKeypoints = 3 }, "range")
				expectValid("numberSequence", three, { maxKeypoints = 4 })
				local keys = {}
				for i = 1, 21 do
					keys[i] = { (i - 1) / 20, 0 }
				end
				expectInvalid("numberSequence", keys, "at most 20", { maxKeypoints = 50 }, "range")
				expectValid("numberSequence", { { 0, 0 }, { 1, 0 } }, { maxKeypoints = 1 })
			end)
			T.it("clamps keypoint values, not envelopes", function()
				local spec = { min = 0, max = 1 }
				expectInvalid(
					"numberSequence",
					{ { 0, 2 }, { 1, 0 } },
					"keypoint 1 value 2 is above the maximum 1",
					spec,
					"range"
				)
				expectInvalid("numberSequence", 1.5, "value 1.5 is above the maximum 1", spec, "range")
				T.expect(Codec.normalize("numberSequence", { { 0, 2, 0.5 }, { 1, -1 } }, spec)).toEqual({
					{ 0, 1, 0.5 },
					{ 1, 0 },
				})
				local seq = Codec.decode("numberSequence", { { 0, 2, 3 }, { 1, -1 } }, spec)
				T.expect(seq.Keypoints[1].Value).toBe(1)
				T.expect(seq.Keypoints[1].Envelope).toBe(3)
				T.expect(seq.Keypoints[2].Value).toBe(0)
			end)
			T.it("collapses two identical keypoints to the plain number", function()
				T.expect(Codec.normalize("numberSequence", { { 0, 5 }, { 1, 5 } })).toBe(5)
				T.expect(Codec.normalize("numberSequence", { { 0, 5, 0 }, { 1, 5, 0 } })).toBe(5)
				T.expect(Codec.normalize("numberSequence", { { 0, 5, 1 }, { 1, 5 } }))
					.toEqual({ { 0, 5, 1 }, { 1, 5 } })
				T.expect(Codec.normalize("numberSequence", { { 0, 5 }, { 0.5, 5 }, { 1, 5 } })).toEqual({
					{ 0, 5 },
					{ 0.5, 5 },
					{ 1, 5 },
				})
				T.expect(Codec.encode("numberSequence", NumberSequence.new(5))).toBe(5)
				T.expect(Codec.encode("numberSequence", NumberSequence.new(0.3, 0.3))).toBe(0.3)
			end)
			T.it("decodes to NumberSequence with envelopes", function()
				local seq = Codec.decode("numberSequence", { { 0, 0.5, 0.25 }, { 0.5, 1 }, { 1, 0 } })
				T.expect(typeof(seq)).toBe("NumberSequence")
				T.expect(#seq.Keypoints).toBe(3)
				T.expect(seq.Keypoints[1].Envelope).toBe(0.25)
				T.expect(seq.Keypoints[2].Time).toBe(0.5)
				T.expect(seq.Keypoints[3].Value).toBe(0)
				local constant = Codec.decode("numberSequence", 2)
				T.expect(#constant.Keypoints).toBe(2)
				T.expect(constant.Keypoints[1].Value).toBe(2)
				T.expect(constant.Keypoints[2].Time).toBe(1)
			end)
			T.it("encodes engine sequences canonically (float32 noise removed, zero envelopes omitted)", function()
				local seq = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.1),
					NumberSequenceKeypoint.new(0.3, 0.7, 0.2),
					NumberSequenceKeypoint.new(1, 1),
				})
				T.expect(Codec.encode("numberSequence", seq)).toEqual({ { 0, 0.1 }, { 0.3, 0.7, 0.2 }, { 1, 1 } })
				T.expect(function()
					Codec.encode("numberSequence", 1)
				end).toThrow("expected a NumberSequence")
			end)
		end)

		T.describe("colorSequence", function()
			T.it("accepts a colour or keypoints of any colour form", function()
				expectValid("colorSequence", "#FF0000")
				expectValid("colorSequence", { 255, 0, 0 })
				expectValid("colorSequence", "$primary")
				expectValid("colorSequence", { L(0, "#FF0000"), L(0.5, { 0, 255, 0 }), L(1, "$primary") })
			end)
			T.it("normalizes keypoints and collapses identical pairs", function()
				T.expect(Codec.normalize("colorSequence", { 255, 0, 0 })).toBe("#FF0000")
				T.expect(Codec.normalize("colorSequence", { L(0, "#f00"), L(1, { 255, 0, 0 }) })).toBe("#FF0000")
				T.expect(Codec.normalize("colorSequence", { L(0, "$a"), L(1, "$a") })).toBe("$a")
				T.expect(Codec.normalize("colorSequence", { L(0, "#ff0000"), L(1, "#0000ff") })).toEqual({
					L(0, "#FF0000"),
					L(1, "#0000FF"),
				})
			end)
			T.it("rejects malformed sequences", function()
				expectInvalid("colorSequence", { L(0, "#FF0000") }, "at least 2 keypoints")
				expectInvalid(
					"colorSequence",
					{ L(0, "#FF0000"), L(0.5, "#00FF00") },
					"last keypoint must be at time 1"
				)
				expectInvalid("colorSequence", { L(0, "#FF0000"), L(1, "#XYZ") }, 'keypoint 2: invalid colour "#XYZ"')
				expectInvalid(
					"colorSequence",
					{ L(0, "#FF0000"), L(1, { 300, 0, 0 }) },
					"keypoint 2: red component 300"
				)
				expectInvalid(
					"colorSequence",
					{ L(0, "#FF0000", 1), L(1, "#FF0000") },
					"keypoint 1 must be [time, colour]"
				)
				expectInvalid(
					"colorSequence",
					{ L(0, "#000000"), L(0.7, "#000000"), L(0.2, "#000000"), L(1, "#000000") },
					"times must not decrease"
				)
				expectInvalid("colorSequence", 5, "expected a colour or keypoints")
				expectInvalid("colorSequence", L(0, "#FF0000"), "got a single [time, colour] pair")
				expectInvalid("colorSequence", { 1, 2 }, "[r, g, b] with 3 numbers")
				expectInvalid("colorSequence", {}, "got an empty table")
				local keys = {}
				for i = 1, 21 do
					keys[i] = L((i - 1) / 20, "#FFFFFF")
				end
				expectInvalid("colorSequence", keys, "at most 20", nil, "range")
			end)
			T.it("decodes to ColorSequence and resolves palette keys", function()
				local palette = { primary = Color3.fromRGB(0, 0, 255) }
				local seq = Codec.decode(
					"colorSequence",
					{ L(0, "#FF0000"), L(0.25, "$primary"), L(1, { 0, 255, 0 }) },
					nil,
					palette
				)
				T.expect(typeof(seq)).toBe("ColorSequence")
				T.expect(#seq.Keypoints).toBe(3)
				T.expect(seq.Keypoints[1].Value).toEqual(Color3.fromRGB(255, 0, 0))
				T.expect(seq.Keypoints[2].Value).toEqual(Color3.fromRGB(0, 0, 255))
				T.expect(seq.Keypoints[2].Time).toBe(0.25)
				local constant = Codec.decode("colorSequence", "$primary", nil, palette)
				T.expect(#constant.Keypoints).toBe(2)
				T.expect(constant.Keypoints[2].Value).toEqual(Color3.fromRGB(0, 0, 255))
				T.expect(function()
					Codec.decode("colorSequence", { L(0, "#FF0000"), L(1, "$nope") }, nil, palette)
				end).toThrow('keypoint 2: unknown palette colour "$nope"')
			end)
			T.it("encodes ColorSequence and Color3", function()
				local seq = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 0, 0)),
					ColorSequenceKeypoint.new(0.3, Color3.new(0, 0.5, 0)),
					ColorSequenceKeypoint.new(1, Color3.new(0, 0, 1)),
				})
				T.expect(Codec.encode("colorSequence", seq)).toEqual({
					L(0, "#FF0000"),
					L(0.3, "#008000"),
					L(1, "#0000FF"),
				})
				T.expect(Codec.encode("colorSequence", ColorSequence.new(Color3.new(1, 1, 1)))).toBe("#FFFFFF")
				T.expect(Codec.encode("colorSequence", Color3.new(0, 1, 0))).toBe("#00FF00")
				T.expect(function()
					Codec.encode("colorSequence", "#FFFFFF")
				end).toThrow("expected a ColorSequence")
			end)
		end)

		T.describe("asset", function()
			T.it("accepts the documented forms and canonicalises ids", function()
				T.expect(Codec.normalize("asset", "rbxassetid://123")).toBe("rbxassetid://123")
				T.expect(Codec.normalize("asset", "rbxasset://textures/particles/sparkles_main.dds"))
					.toBe("rbxasset://textures/particles/sparkles_main.dds")
				T.expect(Codec.normalize("asset", "http://www.roblox.com/asset/?id=456")).toBe("rbxassetid://456")
				T.expect(Codec.normalize("asset", "https://www.roblox.com/asset/?id=789")).toBe("rbxassetid://789")
				T.expect(Codec.normalize("asset", "")).toBe("")
				T.expect(Codec.normalize("asset", 123)).toBe("rbxassetid://123")
				T.expect(Codec.normalize("asset", 9007199254740991)).toBe("rbxassetid://9007199254740991")
				T.expect(Codec.decode("asset", 42)).toBe("rbxassetid://42")
			end)
			T.it("rejects anything else", function()
				expectInvalid("asset", "abc", 'invalid asset "abc"')
				expectInvalid("asset", "rbxassetid://abc", "invalid asset")
				expectInvalid("asset", "rbxassetid://", "invalid asset")
				expectInvalid("asset", "rbxasset://", "invalid asset")
				expectInvalid("asset", " rbxassetid://1", "invalid asset")
				expectInvalid("asset", "https://example.com/asset/?id=1", "invalid asset")
				expectInvalid("asset", 0, "positive whole number, got 0")
				expectInvalid("asset", -5, "positive whole number")
				expectInvalid("asset", 1.5, "positive whole number")
				expectInvalid("asset", 0 / 0, "positive whole number")
				expectInvalid("asset", true, "expected an asset")
			end)
			T.it("encode keeps unrecognised engine strings and reads Content", function()
				local thumb = "rbxthumb://type=Asset&id=1&w=150&h=150"
				T.expect(Codec.encode("asset", thumb)).toBe(thumb)
				T.expect(Codec.encode("asset", "http://www.roblox.com/asset/?id=5")).toBe("rbxassetid://5")
				T.expect(Codec.encode("asset", Content.fromUri("rbxassetid://77"))).toBe("rbxassetid://77")
				T.expect(Codec.encode("asset", Content.none)).toBe("")
				T.expect(function()
					Codec.encode("asset", 0)
				end).toThrow("positive whole number")
				T.expect(function()
					Codec.encode("asset", true)
				end).toThrow("expected an asset string")
			end)
		end)

		T.describe("componentRef", function()
			T.it("accepts ids and the empty reference", function()
				for _, v in { "", "core", "core_1", "a-b", string.rep("x", 64) } do
					expectValid("componentRef", v)
					T.expect(Codec.decode("componentRef", v)).toBe(v)
				end
			end)
			T.it("rejects malformed ids", function()
				expectInvalid("componentRef", "a b", 'invalid component id "a b"')
				expectInvalid("componentRef", "x.y", "invalid component id")
				expectInvalid("componentRef", string.rep("x", 65), "invalid component id")
				expectInvalid("componentRef", 5, "expected a component id")
			end)
		end)

		T.describe("round trip", function()
			local CASES: { { kind: string, spec: any?, values: { any } } } = {
				{ kind = "number", values = { 0, 1, -1, 0.1, 1 / 3, 123.456, -1e-9, 1e12 } },
				{ kind = "number", spec = { min = -1, max = 2 }, values = { -5, -1, 0.5, 2, 9 } },
				{ kind = "integer", values = { 0, 7, -12, 2 ^ 40 } },
				{ kind = "integer", spec = { min = 1, max = 400 }, values = { -3, 1, 200, 999 } },
				{ kind = "boolean", values = { true, false } },
				{ kind = "string", values = { "", "Impact", "Über ✦", "line\nbreak" } },
				{
					kind = "enum",
					spec = { enum = { "Box", "Sphere" }, enumType = "ParticleEmitterShape" },
					values = { "Box", "Sphere" },
				},
				{ kind = "enum", spec = { enum = { "add", "mul" } }, values = { "add", "mul" } },
				{ kind = "enum", spec = { enumType = "Material" }, values = { "Neon", "ForceField", "SmoothPlastic" } },
				{
					kind = "color3",
					values = { "#FF8000", "#ff8000", "#abc", "#000000", "#FFFFFF", { 255, 128, 0 }, { 12.4, 200.6, 0 } },
				},
				{
					kind = "vector3",
					values = {
						{ 0, 0, 0 },
						{ 1, 2, 3 },
						{ 0.1, -0.2, 0.3 },
						{ 1 / 3, 2 / 3, 1e-7 },
						5,
						-0.25,
						{ 1e30, -1e30, 0 },
					},
				},
				{ kind = "vector3", spec = { min = 0, max = 1 }, values = { { -1, 0.5, 2 }, 3 } },
				{ kind = "vector2", values = { { 0, 0 }, { 1.1, -2.2 }, 4, { 1 / 7, 1e-3 } } },
				{ kind = "numberRange", values = { 1, 0.1, { 1, 2 }, { 0.3, 0.3 }, { -5, 5 }, { 1 / 3, 2 / 3 } } },
				{ kind = "numberRange", spec = { min = 0, max = 20 }, values = { { -1, 25 }, 30, { 2, 3 } } },
				{
					kind = "numberSequence",
					values = {
						1,
						0.3,
						{ { 0, 1 }, { 1, 0 } },
						{ { 0, 5 }, { 1, 5 } },
						{ { 0, 0.1, 0.05 }, { 0.3, 0.7 }, { 0.6, 0.2, 0.1 }, { 1, 1 } },
						{ { 0, 0 }, { 0.5, 0 }, { 0.5, 1 }, { 1, 1 } },
						{ { 0, 1 / 3 }, { 1 / 3, 2 / 3, 1 / 9 }, { 1, 0 } },
					},
				},
				{
					kind = "numberSequence",
					spec = { min = 0, max = 1 },
					values = { 2, { { 0, -1, 0.2 }, { 1, 2 } } },
				},
				{
					kind = "colorSequence",
					values = {
						"#FF0000",
						"#f0a",
						{ 10, 20, 30 },
						{ L(0, "#FF0000"), L(1, "#0000FF") },
						{ L(0, "#ff0000"), L(1, { 255, 0, 0 }) },
						{ L(0, "#000000"), L(0.3, "#808080"), L(0.3, "#FFFFFF"), L(1, "#123456") },
					},
				},
				{
					kind = "asset",
					values = {
						"",
						"rbxassetid://1",
						"rbxasset://textures/x.png",
						99,
						"https://www.roblox.com/asset/?id=3",
					},
				},
				{ kind = "componentRef", values = { "", "core", "spark-2" } },
			}
			T.it("normalize(x) == encode(decode(x)) for every kind", function()
				for _, case in CASES do
					for _, value in case.values do
						expectRoundTrip(case.kind, value, case.spec)
					end
				end
			end)
			T.it("holds for generated vectors, ranges and sequences", function()
				local rand = lcg(2024)
				for _ = 1, 200 do
					expectRoundTrip("vector3", { rand() * 200 - 100, rand() * 2 - 1, rand() * 1e-3 })
					expectRoundTrip("vector2", { rand() * 50, -rand() })
					local a, b = rand() * 10, rand() * 10
					expectRoundTrip("numberRange", { math.min(a, b), math.max(a, b) })
					local count = 2 + math.floor(rand() * 19)
					local keys = {}
					local colours = {}
					local times = {}
					for i = 1, count do
						times[i] = rand()
					end
					table.sort(times)
					times[1] = 0
					times[count] = 1
					for i = 1, count do
						if rand() < 0.5 then
							keys[i] = { times[i], rand() * 10 - 5 }
						else
							keys[i] = { times[i], rand() * 10 - 5, rand() * 2 }
						end
						colours[i] = L(
							times[i],
							{ math.floor(rand() * 256), math.floor(rand() * 256), math.floor(rand() * 256) }
						)
					end
					expectRoundTrip("numberSequence", keys)
					expectRoundTrip("numberSequence", keys, { min = -1, max = 1 })
					expectRoundTrip("colorSequence", colours)
				end
			end)
			T.it("is deterministic", function()
				local value = { { 0, 1 / 3, 0.1 }, { 0.37, 2 / 3 }, { 1, 0 } }
				local a = Codec.normalize("numberSequence", value)
				local b = Codec.normalize("numberSequence", value)
				T.expect(a).toEqual(b)
				T.expect(Codec.encode("numberSequence", Codec.decode("numberSequence", value))).toEqual(a)
			end)
			T.it("does not mutate its inputs", function()
				local value = { L(0, "#ff0000"), L(1, { 0, 0, 255 }) }
				Codec.normalize("colorSequence", value)
				Codec.decode("colorSequence", value)
				T.expect(value).toEqual({ L(0, "#ff0000"), L(1, { 0, 0, 255 }) })
			end)
		end)

		T.describe("decode pass-through", function()
			T.it("re-encodes values that already have the decoded type", function()
				T.expect(Codec.decode("vector3", Vector3.new(5, -5, 0), { min = 0 })).toEqual(Vector3.new(5, 0, 0))
				T.expect(Codec.decode("vector2", Vector2.new(1, 2))).toEqual(Vector2.new(1, 2))
				local range = Codec.decode("numberRange", NumberRange.new(1, 2))
				T.expect(range.Min).toBe(1)
				T.expect(range.Max).toBe(2)
				local seq = Codec.decode("numberSequence", NumberSequence.new(0, 2), { max = 1 })
				T.expect(seq.Keypoints[2].Value).toBe(1)
				local colours = Codec.decode("colorSequence", ColorSequence.new(Color3.new(1, 0, 0)))
				T.expect(colours.Keypoints[1].Value).toEqual(Color3.new(1, 0, 0))
			end)
		end)

		T.describe("engine integration", function()
			T.it("decoded values are accepted by real instance properties", function()
				local emitter = Instance.new("ParticleEmitter")
				emitter.Size = Codec.decode("numberSequence", { { 0, 0.5, 0.1 }, { 1, 2 } })
				emitter.Transparency = Codec.decode("numberSequence", 0.25)
				emitter.Color = Codec.decode("colorSequence", { L(0, "#FFAA00"), L(1, "#FF0000") })
				emitter.Lifetime = Codec.decode("numberRange", { 0.5, 1 })
				emitter.Speed = Codec.decode("numberRange", 10)
				emitter.Shape = Codec.decode("enum", "Sphere", { enumType = "ParticleEmitterShape" })
				emitter.Acceleration = Codec.decode("vector3", { 0, -10, 0 })
				emitter.Texture = Codec.decode("asset", 123)
				emitter.Rate = Codec.decode("number", 20)
				emitter.LockedToPart = Codec.decode("boolean", true)
				local part = Instance.new("Part")
				part.Color = Codec.decode("color3", "#336699")
				part.Material = Codec.decode("enum", "Neon", { enumType = "Material" })
				T.expect(Codec.encode("numberSequence", emitter.Size)).toEqual({ { 0, 0.5, 0.1 }, { 1, 2 } })
				T.expect(Codec.encode("colorSequence", emitter.Color)).toEqual({ L(0, "#FFAA00"), L(1, "#FF0000") })
				T.expect(Codec.encode("numberRange", emitter.Lifetime)).toEqual({ 0.5, 1 })
				T.expect(Codec.encode("enum", emitter.Shape)).toBe("Sphere")
				T.expect(Codec.encode("color3", part.Color)).toBe("#336699")
				T.expect(Codec.encode("asset", emitter.Texture)).toBe("rbxassetid://123")
				T.expect(Codec.encode("vector3", emitter.Acceleration)).toEqual({ 0, -10, 0 })
			end)
		end)

		T.describe("default", function()
			T.it("returns a deep copy of spec.default", function()
				local spec =
					{ name = "size", kind = "numberSequence", description = "", default = { { 0, 1 }, { 1, 0 } } }
				local a = Codec.default(spec)
				T.expect(a).toEqual(spec.default)
				T.expect(a).never.toBe(spec.default)
				a[1][2] = 99
				T.expect(spec.default[1][2]).toBe(1)
				T.expect(Codec.default({ default = 5 })).toBe(5)
				T.expect(Codec.default({ default = "#FFFFFF" })).toBe("#FFFFFF")
				T.expect(Codec.default({})).toBeNil()
				T.expect(function()
					Codec.default(nil :: any)
				end).toThrow("spec must be a table")
			end)
			T.it("keeps sentinel tables (with metatables) by identity", function()
				local sentinel = setmetatable({}, {
					__index = function()
						return nil
					end,
				})
				T.expect(Codec.default({ default = sentinel })).toBe(sentinel)
			end)
		end)

		T.describe("lerp", function()
			T.it("interpolates numbers with exact endpoints and extrapolates", function()
				T.expect(Codec.lerp("number", 0.1, 0.7, 0)).toBe(0.1)
				T.expect(Codec.lerp("number", 0.1, 0.7, 1)).toBe(0.7)
				T.expect(Codec.lerp("number", 0, 10, 0.25)).toBe(2.5)
				T.expect(Codec.lerp("number", 0, 10, 1.5)).toBe(15)
				T.expect(Codec.lerp("number", 0, 10, -0.5)).toBe(-5)
			end)
			T.it("interpolates Vector3 values", function()
				T.expect(Codec.lerp("vector3", Vector3.new(0, 0, 0), Vector3.new(2, 4, 6), 0.5))
					.toBeCloseTo(Vector3.new(1, 2, 3))
				local b = Vector3.new(1, 1, 1)
				T.expect(Codec.lerp("vector3", Vector3.zero, b, 1)).toBe(b)
				T.expect(Codec.lerp("vector3", Vector3.zero, b, 2)).toBeCloseTo(Vector3.new(2, 2, 2))
			end)
			T.it("interpolates colours in RGB and clamps overshoot", function()
				local red, blue = Color3.new(1, 0, 0), Color3.new(0, 0, 1)
				T.expect(Codec.lerp("color3", red, blue, 0.5)).toBeCloseTo(Color3.new(0.5, 0, 0.5))
				T.expect(Codec.lerp("color3", red, blue, 0)).toBe(red)
				T.expect(Codec.lerp("color3", red, blue, 1)).toBe(blue)
				T.expect(Codec.lerp("color3", red, blue, 1.5)).toBeCloseTo(Color3.new(0, 0, 1))
				T.expect(Codec.lerp("color3", red, blue, -0.5)).toBeCloseTo(Color3.new(1, 0, 0))
			end)
			T.it("steps booleans at the end of the segment", function()
				T.expect(Codec.lerp("boolean", false, true, 0)).toBe(false)
				T.expect(Codec.lerp("boolean", false, true, 0.99)).toBe(false)
				T.expect(Codec.lerp("boolean", false, true, 1)).toBe(true)
				T.expect(Codec.lerp("boolean", true, false, 1.2)).toBe(false)
			end)
			T.it("rejects mismatched values and unsupported kinds", function()
				T.expect(function()
					Codec.lerp("number", 1, "2", 0.5)
				end).toThrow("expected numbers")
				T.expect(function()
					Codec.lerp("vector3", Vector3.zero, 1, 0.5)
				end).toThrow("expected Vector3s")
				T.expect(function()
					Codec.lerp("color3", Color3.new(), Vector3.zero, 0.5)
				end).toThrow("expected Color3s")
				T.expect(function()
					Codec.lerp("numberSequence", 1, 2, 0.5)
				end).toThrow("unsupported channel kind")
			end)
		end)

		T.describe("paletteRefs", function()
			T.it("lists referenced palette keys once, in order", function()
				T.expect(Codec.paletteRefs("color3", "$primary")).toEqual({ "primary" })
				T.expect(Codec.paletteRefs("color3", "#FFFFFF")).toEqual({})
				T.expect(Codec.paletteRefs("colorSequence", "$a")).toEqual({ "a" })
				T.expect(
					Codec.paletteRefs("colorSequence", { L(0, "$b"), L(0.5, "#000000"), L(0.7, "$a"), L(1, "$b") })
				)
					.toEqual({
						"b",
						"a",
					})
				T.expect(Codec.paletteRefs("number", "$a")).toEqual({})
				T.expect(Codec.paletteRefs("colorSequence", { 255, 0, 0 })).toEqual({})
			end)
		end)

		T.describe("channel specs", function()
			T.it("accept ChannelSpec tables (min/max)", function()
				local channel = { name = "scale", kind = "number", description = "", min = 0 }
				T.expect(Codec.decode("number", -2, channel)).toBe(0)
				local ok, _, problem = Codec.check("number", -2, channel)
				T.expect(ok).toBe(false)
				T.expect(problem).toBe("range")
			end)
		end)
	end)
end
