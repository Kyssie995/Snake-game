--!strict
return function(T: any, use: (string) -> any, _ctx: any)
	local Json = use("AstraVFX.Core.Json")
	local Constants = use("AstraVFX.Core.Constants")
	local Random = use("AstraVFX.Core.Random")

	local NULL = Json.NULL
	local EMPTY = Json.EMPTY_OBJECT

	-- Builds a heterogeneous array (keeps the type checker from inferring a single element type).
	local function list(...: any): { any }
		return { ... }
	end

	-- Returns the error message of a failing decode (and asserts that it failed).
	local function decodeError(text: string): string
		local ok, err = Json.decode(text)
		if ok then
			T.fail("expected decode to fail for " .. string.format("%q", text))
		end
		T.expect(type(err)).toBe("string")
		return err
	end

	local function decoded(text: string): any
		local ok, value = Json.decode(text)
		if not ok then
			T.fail("decode failed: " .. tostring(value))
		end
		return value
	end

	-- A realistic effect-like document (nested arrays, sequences, keyframes, sentinels, unicode).
	local function sampleDoc(): any
		return {
			schemaVersion = 1,
			id = "violet-impact",
			name = "Violet Impact",
			description = 'Layered impact with "quotes", a\ttab and ünïcødé ✨',
			tags = { "impact", "magic" },
			duration = 1.5,
			loop = false,
			seed = 42,
			palette = { primary = "#8040FF", accent = "#FFFFFF" },
			markers = { { id = "m1", time = 0.25, label = "Impact", event = "Impact", phase = "impact" } },
			components = list({
				id = "core",
				name = "Core Flash",
				type = "flash",
				startTime = 0,
				duration = 0.4,
				transform = { position = { 0, 1.5, 0 }, rotation = { 0, 45, 0 }, scale = 1 },
				properties = { color = "$primary", size = 4, brightness = 2.75 },
				tracks = {
					{
						id = "t1",
						channel = "transparency",
						keyframes = {
							{ time = 0, value = 1, easing = "Quad.Out" } :: any,
							{ time = 0.1, value = 0 } :: any,
							{ time = 0.4, value = 1, easing = { bezier = { 0.25, 0.1, 0.25, 1 } } } :: any,
						},
					},
				},
				events = { { id = "e1", time = 0, action = "emit", count = 24 } },
			}, {
				id = "sparks",
				name = "Sparks",
				type = "particles",
				parent = "core",
				enabled = true,
				properties = {
					size = { { 0, 0.5, 0.1 }, { 0.5, 1 }, { 1, 0 } },
					color = { list(0, "#FFFFFF"), list(1, "$primary") },
					lifetime = { 0.3, 0.6 },
					rate = 0,
					speed = -25.125,
					extra = EMPTY,
					list = {},
				},
				qualityOverrides = { Low = { rate = 0 } },
			}),
			graph = { nodes = { { id = "n1", type = "OnPlay", position = { 100, 200 } } }, links = {} },
			metadata = { author = "ASTRA", nested = { deep = { values = { 1, 2, 3, 4, 5, 6, 7, 8, 9 } } } },
		}
	end

	local SAMPLE_PRETTY = table.concat({
		"{",
		'  "schemaVersion": 1,',
		'  "id": "violet-impact",',
		'  "name": "Violet Impact",',
		'  "description": "Layered impact with \\"quotes\\", a\\ttab and ünïcødé ✨",',
		'  "tags": ["impact", "magic"],',
		'  "duration": 1.5,',
		'  "loop": false,',
		'  "seed": 42,',
		'  "palette": {',
		'    "accent": "#FFFFFF",',
		'    "primary": "#8040FF"',
		"  },",
		'  "markers": [',
		"    {",
		'      "id": "m1",',
		'      "phase": "impact",',
		'      "time": 0.25,',
		'      "label": "Impact",',
		'      "event": "Impact"',
		"    }",
		"  ],",
		'  "components": [',
		"    {",
		'      "id": "core",',
		'      "name": "Core Flash",',
		'      "type": "flash",',
		'      "duration": 0.4,',
		'      "startTime": 0,',
		'      "transform": {',
		'        "position": [0, 1.5, 0],',
		'        "rotation": [0, 45, 0],',
		'        "scale": 1',
		"      },",
		'      "properties": {',
		'        "brightness": 2.75,',
		'        "color": "$primary",',
		'        "size": 4',
		"      },",
		'      "tracks": [',
		"        {",
		'          "id": "t1",',
		'          "channel": "transparency",',
		'          "keyframes": [',
		"            {",
		'              "time": 0,',
		'              "value": 1,',
		'              "easing": "Quad.Out"',
		"            },",
		"            {",
		'              "time": 0.1,',
		'              "value": 0',
		"            },",
		"            {",
		'              "time": 0.4,',
		'              "value": 1,',
		'              "easing": {',
		'                "bezier": [0.25, 0.1, 0.25, 1]',
		"              }",
		"            }",
		"          ]",
		"        }",
		"      ],",
		'      "events": [',
		"        {",
		'          "id": "e1",',
		'          "time": 0,',
		'          "action": "emit",',
		'          "count": 24',
		"        }",
		"      ]",
		"    },",
		"    {",
		'      "id": "sparks",',
		'      "name": "Sparks",',
		'      "type": "particles",',
		'      "parent": "core",',
		'      "enabled": true,',
		'      "properties": {',
		'        "color": [',
		'          [0, "#FFFFFF"],',
		'          [1, "$primary"]',
		"        ],",
		'        "extra": {},',
		'        "lifetime": [0.3, 0.6],',
		'        "list": [],',
		'        "rate": 0,',
		'        "size": [',
		"          [0, 0.5, 0.1],",
		"          [0.5, 1],",
		"          [1, 0]",
		"        ],",
		'        "speed": -25.125',
		"      },",
		'      "qualityOverrides": {',
		'        "Low": {',
		'          "rate": 0',
		"        }",
		"      }",
		"    }",
		"  ],",
		'  "graph": {',
		'    "nodes": [',
		"      {",
		'        "id": "n1",',
		'        "type": "OnPlay",',
		'        "position": [100, 200]',
		"      }",
		"    ],",
		'    "links": []',
		"  },",
		'  "metadata": {',
		'    "author": "ASTRA",',
		'    "nested": {',
		'      "deep": {',
		'        "values": [',
		"          1,",
		"          2,",
		"          3,",
		"          4,",
		"          5,",
		"          6,",
		"          7,",
		"          8,",
		"          9",
		"        ]",
		"      }",
		"    }",
		"  }",
		"}",
	}, "\n")

	T.describe("Json.encode", function()
		T.describe("numbers", function()
			T.it("writes integers without a decimal point", function()
				T.expect(Json.encode(3)).toBe("3")
				T.expect(Json.encode(-17)).toBe("-17")
				T.expect(Json.encode(1000000)).toBe("1000000")
				T.expect(Json.encode(2 ^ 53 - 1)).toBe("9007199254740991")
				T.expect(Json.encode(-(2 ^ 53 - 1))).toBe("-9007199254740991")
			end)
			T.it("writes zero and negative zero as 0", function()
				T.expect(Json.encode(0)).toBe("0")
				T.expect(Json.encode(-0)).toBe("0")
				T.expect(Json.encode({ -0.0 }, { pretty = false })).toBe("[0]")
			end)
			T.it("rounds fractions to 6 decimals and strips trailing zeros", function()
				T.expect(Json.encode(0.1)).toBe("0.1")
				T.expect(Json.encode(2.5)).toBe("2.5")
				T.expect(Json.encode(-0.25)).toBe("-0.25")
				T.expect(Json.encode(1 / 3)).toBe("0.333333")
				T.expect(Json.encode(2 / 3)).toBe("0.666667")
				T.expect(Json.encode(-2 / 3)).toBe("-0.666667")
				T.expect(Json.encode(123.456789)).toBe("123.456789")
				T.expect(Json.encode(0.000001)).toBe("0.000001")
				T.expect(Json.encode(0.1 + 0.2)).toBe("0.3")
				T.expect(Json.encode(1.10000000001)).toBe("1.1")
			end)
			T.it("rounds tiny values to 0 (never -0)", function()
				T.expect(Json.encode(1e-7)).toBe("0")
				T.expect(Json.encode(-1e-7)).toBe("0")
				T.expect(Json.encode(4e-7)).toBe("0")
				T.expect(Json.encode(6e-7)).toBe("0.000001")
				T.expect(Json.encode(-6e-7)).toBe("-0.000001")
			end)
			T.it("carries rounding into the integer part", function()
				T.expect(Json.encode(0.9999999)).toBe("1")
				T.expect(Json.encode(-2.0000004)).toBe("-2")
				T.expect(Json.encode(9.9999996)).toBe("10")
				T.expect(Json.encode(-0.9999999)).toBe("-1")
			end)
			T.it("writes numbers >= 2^53 in Luau's round-trip form", function()
				T.expect(Json.encode(2 ^ 53)).toBe("9007199254740992")
				T.expect(Json.encode(1e21)).toBe("1e+21")
				T.expect(Json.encode(-1e300)).toBe("-1e+300")
				for _, x in { 2 ^ 53, 2 ^ 60, 1e21, -1e300, 1.7976931348623157e308 } do
					T.expect(decoded(Json.encode(x))).toBe(x)
				end
			end)
			T.it("rejects NaN and infinities", function()
				T.expect(function()
					Json.encode(0 / 0)
				end).toThrow("non-finite")
				T.expect(function()
					Json.encode(math.huge)
				end).toThrow("non-finite")
				T.expect(function()
					Json.encode({ x = { -math.huge } })
				end).toThrow("non-finite number -inf at x[1]")
			end)
			T.it("is idempotent and accurate for many generated numbers", function()
				local rng = Random.new(2024)
				for i = 1, 3000 do
					local magnitude = 10 ^ rng:int(-8, 15)
					local x = (rng:next() * 2 - 1) * magnitude
					if i % 7 == 0 then
						x = math.floor(x)
					end
					local s = Json.encode(x)
					local y = decoded(s)
					T.expect(type(y)).toBe("number")
					T.expect(Json.encode(y)).toBe(s)
					if math.abs(x) < 1e6 then
						T.expect(math.abs(y - x)).toBeLessThanOrEqual(5.000001e-7)
					end
					T.expect(s).toMatch("^%-?%d+%.?%d*$")
				end
			end)
		end)

		T.describe("strings", function()
			T.it("escapes quotes, backslashes and control characters", function()
				T.expect(Json.encode('a"b\\c')).toBe('"a\\"b\\\\c"')
				T.expect(Json.encode("\n\t\r\b\f")).toBe('"\\n\\t\\r\\b\\f"')
				T.expect(Json.encode("\0\1\31")).toBe('"\\u0000\\u0001\\u001f"')
				T.expect(Json.encode("\127")).toBe('"\\u007f"')
			end)
			T.it("keeps UTF-8 and '/' unescaped", function()
				T.expect(Json.encode("äöü/€😀 日本")).toBe('"äöü/€😀 日本"')
				T.expect(Json.encode("")).toBe('""')
			end)
			T.it("rejects invalid UTF-8 in values and keys", function()
				T.expect(function()
					Json.encode("\255")
				end).toThrow("not valid UTF-8")
				T.expect(function()
					Json.encode({ ["k\192\128"] = 1 })
				end).toThrow("not valid UTF-8")
				T.expect(function()
					Json.encode({ "\237\160\128" }) -- encoded surrogate
				end).toThrow("not valid UTF-8 at [1]")
			end)
		end)

		T.describe("sentinels and empty tables", function()
			T.it("encodes NULL, EMPTY_OBJECT, empty tables and booleans", function()
				T.expect(Json.encode(NULL)).toBe("null")
				T.expect(Json.encode(EMPTY)).toBe("{}")
				T.expect(Json.encode({})).toBe("[]")
				T.expect(Json.encode(true)).toBe("true")
				T.expect(Json.encode(false)).toBe("false")
				T.expect(Json.encode({ a = {}, b = EMPTY, c = NULL })).toBe('{\n  "a": [],\n  "b": {},\n  "c": null\n}')
			end)
			T.it("protects the sentinels from mutation", function()
				T.expect(function()
					EMPTY.x = 1
				end).toThrow()
				T.expect(function()
					NULL.x = 1
				end).toThrow()
				T.expect(next(EMPTY)).toBeNil()
				T.expect(EMPTY).never.toBe(NULL)
				T.expect(tostring(NULL)).toBe("Json.NULL")
			end)
			T.it("rejects nil", function()
				T.expect(function()
					Json.encode(nil)
				end).toThrow("cannot encode nil")
			end)
		end)

		T.describe("pretty layout", function()
			T.it("puts arrays of up to 8 scalars on one line", function()
				T.expect(Json.encode({ 1, 2, 3 })).toBe("[1, 2, 3]")
				T.expect(Json.encode({ 1, 2, 3, 4, 5, 6, 7, 8 })).toBe("[1, 2, 3, 4, 5, 6, 7, 8]")
				T.expect(Json.encode(list("a", true, NULL, 1.5))).toBe('["a", true, null, 1.5]')
			end)
			T.it("puts longer scalar arrays one element per line", function()
				T.expect(Json.encode({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }))
					.toBe("[\n  1,\n  2,\n  3,\n  4,\n  5,\n  6,\n  7,\n  8,\n  9\n]")
			end)
			T.it("prints arrays of short scalar arrays one element per line", function()
				T.expect(Json.encode({ { 0, 1 }, { 1, 0 } })).toBe("[\n  [0, 1],\n  [1, 0]\n]")
				T.expect(Json.encode({ v = { list(0, "#FFFFFF"), list(1, "#000000") } }))
					.toBe('{\n  "v": [\n    [0, "#FFFFFF"],\n    [1, "#000000"]\n  ]\n}')
			end)
			T.it("expands arrays containing containers", function()
				T.expect(Json.encode({ { a = 1 } })).toBe('[\n  {\n    "a": 1\n  }\n]')
				T.expect(Json.encode(list(1, { 2 }))).toBe("[\n  1,\n  [2]\n]")
				T.expect(Json.encode(list(1, {}))).toBe("[\n  1,\n  []\n]")
				T.expect(Json.encode({ EMPTY })).toBe("[\n  {}\n]")
			end)
			T.it("matches the golden layout of a realistic effect document", function()
				T.expect(Json.encode(sampleDoc())).toBe(SAMPLE_PRETTY)
				T.expect(Json.encode(sampleDoc(), { pretty = true })).toBe(SAMPLE_PRETTY)
			end)
		end)

		T.describe("compact layout", function()
			T.it("emits no whitespace outside strings", function()
				local s = Json.encode({ a = { 1, 2 }, b = { c = "x y" }, d = { { 0, 1 } } }, { pretty = false })
				T.expect(s).toBe('{"a":[1,2],"b":{"c":"x y"},"d":[[0,1]]}')
				-- Remove string literals (honouring escapes), then look for whitespace in what remains.
				local compact = Json.encode(sampleDoc(), { pretty = false })
				local outside = {}
				local inString, escaped = false, false
				for i = 1, #compact do
					local c = string.sub(compact, i, i)
					if inString then
						if escaped then
							escaped = false
						elseif c == "\\" then
							escaped = true
						elseif c == '"' then
							inString = false
						end
					elseif c == '"' then
						inString = true
					else
						table.insert(outside, c)
					end
				end
				T.expect(string.find(table.concat(outside), "[ \n\t\r]")).toBeNil()
				T.expect(string.find(compact, "a\\ttab", 1, true)).toBeTruthy()
			end)
		end)

		T.describe("key order", function()
			T.it("uses Constants.KEY_ORDER first, then byte-wise alphabetical order", function()
				local s = Json.encode({ zeta = 1, alpha = 2, name = 3, id = 4, schemaVersion = 5 }, { pretty = false })
				T.expect(s).toBe('{"schemaVersion":5,"id":4,"name":3,"alpha":2,"zeta":1}')
				local cased = Json.encode(
					{ b = 1, B = 2, a = 3, aa = 4, ab = 5, ["ä"] = 6, _x = 7 },
					{ pretty = false }
				)
				T.expect(cased).toBe('{"B":2,"_x":7,"a":3,"aa":4,"ab":5,"b":1,"ä":6}')
			end)
			T.it("orders every key of KEY_ORDER by its position", function()
				local t = {}
				for i, key in Constants.KEY_ORDER do
					t[key] = i
				end
				local expectedParts = {}
				for i, key in Constants.KEY_ORDER do
					expectedParts[i] = '"' .. key .. '":' .. i
				end
				T.expect(Json.encode(t, { pretty = false })).toBe("{" .. table.concat(expectedParts, ",") .. "}")
			end)
			T.it("accepts a custom key order (and an empty one)", function()
				local value = { a = 1, z = 2, id = 3, m = 4 }
				T.expect(Json.encode(value, { pretty = false, keyOrder = { "z", "m", "z" } }))
					.toBe('{"z":2,"m":4,"a":1,"id":3}')
				T.expect(Json.encode(value, { pretty = false, keyOrder = {} })).toBe('{"a":1,"id":3,"m":4,"z":2}')
			end)
			T.it("is independent of table insertion order", function()
				local keys = { "time", "value", "easing", "id", "zeta", "alpha", "Beta", "name", "channel", "notes" }
				local forward, backward, churned = {}, {}, {}
				for i, key in keys do
					forward[key] = i
				end
				for i = #keys, 1, -1 do
					backward[keys[i]] = i
				end
				for i = 1, 200 do
					churned["tmp" .. i] = i -- grow the hash part, then remove again
				end
				for i = #keys, 1, -1 do
					churned[keys[i]] = i
				end
				for i = 1, 200 do
					churned["tmp" .. i] = nil
				end
				local a = Json.encode(forward)
				T.expect(Json.encode(backward)).toBe(a)
				T.expect(Json.encode(churned)).toBe(a)
				T.expect(Json.encode(forward, { pretty = false })).toBe(Json.encode(churned, { pretty = false }))
			end)
		end)

		T.describe("invalid input", function()
			T.it("rejects mixed tables", function()
				local mixed: any = { 1, 2 }
				mixed.x = 3
				T.expect(function()
					Json.encode({ components = { mixed } })
				end).toThrow("mixed table (array indices and string keys) at components[1]")
			end)
			T.it("rejects sparse arrays", function()
				local sparse = {}
				sparse[1] = "a"
				sparse[3] = "c"
				T.expect(function()
					Json.encode({ list = sparse })
				end).toThrow("sparse array")
				T.expect(function()
					Json.encode({ [2] = true })
				end).toThrow("sparse array")
			end)
			T.it("rejects non-string keys", function()
				local cases: { any } = { { [0] = 1 }, { [-1] = 1 }, { [1.5] = 1 }, { [true] = 1 }, { [{}] = 1 } }
				for _, case in cases do
					T.expect(function()
						Json.encode(case)
					end).toThrow("object keys must be strings")
				end
			end)
			T.it("rejects unsupported value types with their path", function()
				T.expect(function()
					Json.encode({ a = { b = function() end } })
				end).toThrow("cannot encode a value of type function at a.b")
				T.expect(function()
					Json.encode({ components = { {}, { position = Vector3.new(1, 2, 3) } } })
				end).toThrow("type Vector3 at components[2].position")
				T.expect(function()
					Json.encode({ ["odd key"] = list(1, coroutine.create(function() end)) })
				end).toThrow('at ["odd key"][2]')
				T.expect(function()
					Json.encode(print)
				end).toThrow("at (root)")
			end)
			T.it("rejects cyclic tables but allows shared references", function()
				local selfRef: any = {}
				selfRef.me = selfRef
				T.expect(function()
					Json.encode(selfRef)
				end).toThrow("cyclic table reference at me")
				local a: any = { name = "a" }
				local b: any = { a }
				a.children = b
				T.expect(function()
					Json.encode({ a })
				end).toThrow("cyclic")
				local shared = { 1, 2 }
				T.expect(Json.encode({ x = shared, y = shared }, { pretty = false })).toBe('{"x":[1,2],"y":[1,2]}')
			end)
			T.it("limits nesting to 200 levels", function()
				local ok200: any = 1
				for _ = 1, 200 do
					ok200 = { ok200 }
				end
				local s = Json.encode(ok200, { pretty = false })
				T.expect(#s).toBe(401)
				T.expect(Json.decode(s)).toBe(true)
				T.expect(function()
					Json.encode({ ok200 })
				end).toThrow("nesting deeper than 200 levels")
			end)
			T.it("counts Json.EMPTY_OBJECT as a container level, like decode does", function()
				-- everything encode() accepts must decode again
				local deep: any = EMPTY
				for _ = 1, 199 do
					deep = { deep }
				end
				local s = Json.encode(deep, { pretty = false })
				T.expect(Json.decode(s)).toBe(true)
				T.expect(function()
					Json.encode({ deep })
				end).toThrow("nesting deeper than 200 levels")
				T.expect(Json.decode("[" .. s .. "]")).toBe(false)
			end)
			T.it("validates options", function()
				T.expect(function()
					Json.encode(1, 5 :: any)
				end).toThrow("options must be a table")
				T.expect(function()
					Json.encode(1, { pretty = "yes" :: any })
				end).toThrow("options.pretty must be a boolean")
				T.expect(function()
					Json.encode(1, { keyOrder = "id" :: any })
				end).toThrow("options.keyOrder")
				T.expect(function()
					Json.encode({ a = 1 }, { keyOrder = { 1 :: any } })
				end).toThrow("options.keyOrder must contain only strings")
			end)
			T.it("does not keep state after an error", function()
				pcall(Json.encode, { a = { b = 0 / 0 } })
				T.expect(Json.encode({ a = { b = 1 } }, { pretty = false })).toBe('{"a":{"b":1}}')
			end)
		end)
	end)

	T.describe("Json.decode", function()
		T.describe("values", function()
			T.it("parses scalars", function()
				T.expect(decoded("0")).toBe(0)
				T.expect(decoded("-0")).toBe(0)
				T.expect(decoded("42")).toBe(42)
				T.expect(decoded("-3.25")).toBe(-3.25)
				T.expect(decoded("12.5e-1")).toBe(1.25)
				T.expect(decoded("1E2")).toBe(100)
				T.expect(decoded("1e+2")).toBe(100)
				T.expect(decoded("2.5E-3")).toBe(0.0025)
				T.expect(decoded("1e-400")).toBe(0)
				T.expect(decoded("12345678901234567890")).toBe(tonumber("12345678901234567890"))
				T.expect(decoded("true")).toBe(true)
				T.expect(decoded("false")).toBe(false)
				T.expect(decoded("null")).toBe(NULL)
				T.expect(decoded('"text"')).toBe("text")
			end)
			T.it("parses nested structures", function()
				local v = decoded('{"a": [1, 2, {"b": "c"}], "d": {"e": [true, false]}, "": 0}')
				T.expect(v).toEqual({ a = list(1, 2, { b = "c" }), d = { e = { true, false } }, [""] = 0 })
			end)
			T.it("accepts all JSON whitespace", function()
				T.expect(decoded(" \t\r\n[ 1 ,\n\t2 ]\r\n ")).toEqual({ 1, 2 })
				T.expect(decoded('{\r\n  "a" :\t1\r\n}')).toEqual({ a = 1 })
			end)
			T.it("maps null in arrays to NULL and omits null members", function()
				local arr = decoded("[null, 1, null]")
				T.expect(#arr).toBe(3)
				T.expect(arr[1]).toBe(NULL)
				T.expect(arr[2]).toBe(1)
				T.expect(arr[3]).toBe(NULL)
				T.expect(decoded('{"a": null, "b": 1}')).toEqual({ b = 1 })
			end)
			T.it("returns EMPTY_OBJECT for {} and fresh tables for []", function()
				T.expect(decoded("{}")).toBe(EMPTY)
				T.expect(decoded(" { } ")).toBe(EMPTY)
				T.expect(decoded('{"a": null}')).toBe(EMPTY)
				local a, b = decoded("[]"), decoded("[]")
				T.expect(a).toEqual({})
				T.expect(a).never.toBe(b)
				T.expect(a).never.toBe(EMPTY)
				T.expect(decoded('{"x": {}, "y": []}')).toEqual({ x = EMPTY, y = {} })
			end)
			T.it("skips a leading UTF-8 BOM", function()
				T.expect(decoded('\239\187\191{"a": 1}')).toEqual({ a = 1 })
				T.expect(decoded("\239\187\191 7")).toBe(7)
			end)
		end)

		T.describe("strings", function()
			T.it("decodes all simple escapes", function()
				T.expect(decoded('"\\"\\\\\\/\\b\\f\\n\\r\\t"')).toBe('"\\/\b\f\n\r\t')
			end)
			T.it("decodes \\u escapes to UTF-8 (both hex cases)", function()
				T.expect(decoded('"\\u00e9\\u00E9"')).toBe("éé")
				T.expect(decoded('"\\u0041\\u20AC"')).toBe("A€")
				T.expect(decoded('"\\u0000"')).toBe("\0")
				T.expect(decoded('"\\u007f"')).toBe("\127")
				T.expect(decoded('"\\uFFFF"')).toBe(utf8.char(0xFFFF))
			end)
			T.it("combines surrogate pairs", function()
				T.expect(decoded('"\\uD83D\\uDE00"')).toBe("😀")
				T.expect(decoded('"x\\ud83d\\ude00y"')).toBe("x😀y")
				T.expect(decoded('"\\uDBFF\\uDFFF"')).toBe(utf8.char(0x10FFFF))
				T.expect(decoded('"\\uD800\\uDC00"')).toBe(utf8.char(0x10000))
			end)
			T.it("keeps raw UTF-8 and DEL", function()
				T.expect(decoded('"日本語 ✨ äöü"')).toBe("日本語 ✨ äöü")
				T.expect(decoded('"a\127b"')).toBe("a\127b")
			end)
		end)

		T.describe("errors (line, column, message)", function()
			T.it("reports empty input and garbage", function()
				T.expect(decodeError("")).toBe("line 1, column 1: unexpected end of input (expected a value)")
				T.expect(decodeError("   ")).toBe("line 1, column 4: unexpected end of input (expected a value)")
				T.expect(decodeError("@")).toBe("line 1, column 1: unexpected '@' (expected a value)")
				T.expect(decodeError("1 2")).toBe("line 1, column 3: unexpected '2' after the JSON value")
				T.expect(decodeError('{"a":1}}')).toBe("line 1, column 8: unexpected '}' after the JSON value")
			end)
			T.it("rejects comments", function()
				T.expect(decodeError("// c\n1")).toBe("line 1, column 1: unexpected '/' (expected a value)")
				T.expect(decodeError("[1, /* c */ 2]")).toBe("line 1, column 5: unexpected '/' (expected a value)")
			end)
			T.it("rejects trailing commas", function()
				T.expect(decodeError("[1, 2,]")).toBe("line 1, column 7: trailing comma in array")
				T.expect(decodeError('{"a": 1,}')).toBe("line 1, column 9: trailing comma in object")
				T.expect(decodeError("[,]")).toBe("line 1, column 2: unexpected ',' (expected a value)")
			end)
			T.it("rejects non-JSON number forms", function()
				T.expect(decodeError("01")).toBe("line 1, column 1: invalid number (leading zeros are not allowed)")
				T.expect(decodeError("-01")).toBe("line 1, column 1: invalid number (leading zeros are not allowed)")
				T.expect(decodeError("1.")).toContain("line 1, column 3: invalid number (expected a digit after '.'")
				T.expect(decodeError(".5")).toBe("line 1, column 1: unexpected '.' (expected a value)")
				T.expect(decodeError("+1")).toBe("line 1, column 1: unexpected '+' (expected a value)")
				T.expect(decodeError("-")).toBe("line 1, column 2: invalid number (expected a digit, got end of input)")
				T.expect(decodeError("1e"))
					.toContain("line 1, column 3: invalid number (expected a digit in the exponent")
				T.expect(decodeError("1e+")).toContain("line 1, column 4: invalid number")
				T.expect(decodeError("0x10")).toBe("line 1, column 2: unexpected 'x' after the JSON value")
				T.expect(decodeError("NaN")).toBe("line 1, column 1: unexpected 'N' (expected a value)")
				T.expect(decodeError("Infinity")).toBe("line 1, column 1: unexpected 'I' (expected a value)")
				T.expect(decodeError("-Infinity")).toContain("line 1, column 2: invalid number")
				T.expect(decodeError("1e400")).toBe("line 1, column 1: number out of range")
				T.expect(decodeError("[-1e400]")).toBe("line 1, column 2: number out of range")
			end)
			T.it("rejects bad literals", function()
				T.expect(decodeError("tru")).toBe("line 1, column 1: invalid literal (expected 'true')")
				T.expect(decodeError("[nul]")).toBe("line 1, column 2: invalid literal (expected 'null')")
				T.expect(decodeError("False")).toBe("line 1, column 1: unexpected 'F' (expected a value)")
				T.expect(decodeError("truex")).toBe("line 1, column 5: unexpected 'x' after the JSON value")
			end)
			T.it("rejects malformed arrays and objects", function()
				T.expect(decodeError("[1 2]")).toBe("line 1, column 4: expected ',' or ']' in array, got '2'")
				T.expect(decodeError("[")).toBe("line 1, column 2: unexpected end of input (expected a value)")
				T.expect(decodeError("[1")).toBe("line 1, column 3: unterminated array (expected ',' or ']')")
				T.expect(decodeError("{")).toBe("line 1, column 2: unterminated object (expected a string key)")
				T.expect(decodeError("{'a': 1}")).toBe("line 1, column 2: expected a string key in object, got '''")
				T.expect(decodeError("{a: 1}")).toBe("line 1, column 2: expected a string key in object, got 'a'")
				T.expect(decodeError('{"a" 1}')).toBe("line 1, column 6: expected ':' after object key, got '1'")
				T.expect(decodeError('{"a":1 "b":2}')).toBe("line 1, column 8: expected ',' or '}' in object, got '\"'")
				T.expect(decodeError('{"a":1')).toBe("line 1, column 7: unterminated object (expected ',' or '}')")
				T.expect(decodeError('{"a":}')).toBe("line 1, column 6: unexpected '}' (expected a value)")
			end)
			T.it("rejects duplicate keys", function()
				T.expect(decodeError('{"a":1,"a":2}')).toBe('line 1, column 8: duplicate key "a"')
				T.expect(decodeError('{"a":null,"a":2}')).toBe('line 1, column 11: duplicate key "a"')
				T.expect(decodeError('{"x":{"b":1},"y":{"b":2,"b":3}}')).toContain("duplicate key")
				T.expect(decoded('{"a":{"a":1}}')).toEqual({ a = { a = 1 } })
			end)
			T.it("rejects malformed strings", function()
				T.expect(decodeError('"abc')).toBe("line 1, column 5: unterminated string (missing closing '\"')")
				T.expect(decodeError('"abc\\')).toBe("line 1, column 6: unterminated string (missing closing '\"')")
				T.expect(decodeError('"a\tb"')).toBe("line 1, column 3: unescaped control character U+0009 in string")
				T.expect(decodeError('"a\nb"')).toBe("line 1, column 3: unescaped control character U+000A in string")
				T.expect(decodeError('"\0"')).toBe("line 1, column 2: unescaped control character U+0000 in string")
				T.expect(decodeError('"\\x"')).toBe("line 1, column 2: invalid escape sequence \\x")
				T.expect(decodeError('"\\\'"')).toBe("line 1, column 2: invalid escape sequence \\'")
				T.expect(decodeError('"\\u12"')).toBe("line 1, column 2: invalid \\u escape (expected 4 hex digits)")
				T.expect(decodeError('"\\u12G4"')).toContain("invalid \\u escape")
			end)
			T.it("rejects unpaired surrogates", function()
				T.expect(decodeError('"\\uD800"')).toBe("line 1, column 2: unpaired high surrogate \\uD800")
				T.expect(decodeError('"\\uD800x"')).toBe("line 1, column 2: unpaired high surrogate \\uD800")
				T.expect(decodeError('"\\uD800\\u0041"')).toBe("line 1, column 8: expected low surrogate after \\uD800")
				T.expect(decodeError('"\\uD800\\uD800"')).toContain("expected low surrogate")
				T.expect(decodeError('"\\uDC00"')).toBe("line 1, column 2: unpaired low surrogate \\uDC00")
				T.expect(decodeError('"\\uD800\\u12"'))
					.toBe("line 1, column 8: invalid \\u escape (expected 4 hex digits)")
			end)
			T.it("rejects invalid UTF-8", function()
				T.expect(decodeError('"\255"')).toBe("line 1, column 2: invalid UTF-8 in string")
				T.expect(decodeError('"ab\195"')).toBe("line 1, column 4: invalid UTF-8 in string")
				T.expect(decodeError('"\192\128"')).toContain("invalid UTF-8") -- overlong NUL
				T.expect(decodeError('"\237\160\128"')).toContain("invalid UTF-8") -- encoded surrogate
				T.expect(decodeError('"\244\144\128\128"')).toContain("invalid UTF-8") -- > U+10FFFF
				T.expect(decodeError('"ok\\n\255"')).toBe("line 1, column 6: invalid UTF-8 in string")
				T.expect(decodeError("\255")).toBe("line 1, column 1: unexpected byte 0xFF (expected a value)")
			end)
			T.it("counts lines and columns across line endings and unicode", function()
				T.expect(decodeError('{\n  "a": [1,\n    2,,\n  ]\n}'))
					.toBe("line 3, column 7: unexpected ',' (expected a value)")
				T.expect(decodeError("[\r\n1,\r\n]")).toBe("line 3, column 1: trailing comma in array")
				T.expect(decodeError("[\r1,\r]")).toBe("line 3, column 1: trailing comma in array")
				T.expect(decodeError("\n\n\n   x")).toBe("line 4, column 4: unexpected 'x' (expected a value)")
				T.expect(decodeError('["äöü", x]')).toBe("line 1, column 9: unexpected 'x' (expected a value)")
				T.expect(decodeError("[1, €]"))
					.toBe("line 1, column 5: unexpected character U+20AC '€' (expected a value)")
				T.expect(decodeError("\239\187\191[x]")).toBe("line 1, column 2: unexpected 'x' (expected a value)")
				T.expect(decodeError("[1]\239\187\191"))
					.toBe("line 1, column 4: unexpected character U+FEFF '\239\187\191' after the JSON value")
				T.expect(decodeError("[1]\239\187")).toBe("line 1, column 4: unexpected byte 0xEF after the JSON value")
			end)
			T.it("limits nesting depth to 200", function()
				T.expect(Json.decode(string.rep("[", 200) .. string.rep("]", 200))).toBe(true)
				T.expect(Json.decode(string.rep('{"a":', 199) .. "{}" .. string.rep("}", 199))).toBe(true)
				T.expect(decodeError(string.rep("[", 201) .. string.rep("]", 201)))
					.toBe("line 1, column 201: maximum nesting depth of 200 exceeded")
				T.expect(decodeError(string.rep("[", 100000))).toContain("maximum nesting depth of 200 exceeded")
				T.expect(decodeError(string.rep('{"a":', 201))).toContain("maximum nesting depth")
			end)
			T.it("never throws, even for non-string input", function()
				local ok, err = Json.decode(42 :: any)
				T.expect(ok).toBe(false)
				T.expect(err).toBe("line 1, column 1: expected JSON text as a string, got number")
				local ok2 = Json.decode(nil :: any)
				T.expect(ok2).toBe(false)
			end)
			T.it("recovers cleanly after an error", function()
				decodeError('{"a": [1, 2')
				T.expect(decoded('{"b": 2}')).toEqual({ b = 2 })
			end)
		end)
	end)

	T.describe("Json round trips", function()
		T.it("decode(encode(x)) deep-equals x", function()
			local doc = sampleDoc()
			T.expect(decoded(Json.encode(doc))).toEqual(doc)
			T.expect(decoded(Json.encode(doc, { pretty = false }))).toEqual(doc)
			local values: { any } =
				{ 0, -12, 0.5, 'x\n"y"', true, false, NULL, EMPTY, {}, list(1, list(2, { 3 })), { k = "v" } }
			for _, v in values do
				T.expect(decoded(Json.encode(v))).toEqual(v)
			end
			local withNulls = decoded(Json.encode({ NULL, NULL }))
			T.expect(withNulls[1]).toBe(NULL)
			T.expect(withNulls[2]).toBe(NULL)
		end)
		T.it("encode(decode(encode(x))) == encode(x) byte for byte", function()
			local doc = sampleDoc()
			for _, pretty in { true, false } do
				local once = Json.encode(doc, { pretty = pretty })
				local twice = Json.encode(decoded(once), { pretty = pretty })
				T.expect(twice).toBe(once)
				T.expect(Json.encode(decoded(twice), { pretty = pretty })).toBe(once)
			end
			T.expect(Json.encode(decoded(Json.encode(doc, { pretty = false })))).toBe(SAMPLE_PRETTY)
		end)
		T.it("canonicalizes arbitrary input text", function()
			local messy =
				'{"name":"x",  "id":"a","schemaVersion":1, "zeta": [1,2], "alpha": {"b": null, "a": 1.50, "c": 1e2}, "u": "\\u00e9\\/"}'
			local canonical = table.concat({
				"{",
				'  "schemaVersion": 1,',
				'  "id": "a",',
				'  "name": "x",',
				'  "alpha": {',
				'    "a": 1.5,',
				'    "c": 100',
				"  },",
				'  "u": "é/",',
				'  "zeta": [1, 2]',
				"}",
			}, "\n")
			T.expect(Json.encode(decoded(messy))).toBe(canonical)
			T.expect(Json.encode(decoded(canonical))).toBe(canonical)
		end)
		T.it("is deterministic across repeated runs", function()
			local first = Json.encode(sampleDoc())
			for _ = 1, 5 do
				T.expect(Json.encode(sampleDoc())).toBe(first)
			end
		end)
	end)

	T.describe("Json.isArray", function()
		T.it("classifies tables", function()
			T.expect(Json.isArray({ 1, 2, 3 })).toBe(true)
			T.expect(Json.isArray({ "a" })).toBe(true)
			T.expect(Json.isArray({})).toBe(true)
			T.expect(Json.isArray(decoded("[]"))).toBe(true)
			T.expect(Json.isArray(EMPTY)).toBe(false)
			T.expect(Json.isArray(NULL)).toBe(false)
			T.expect(Json.isArray({ a = 1 })).toBe(false)
			local mixed: any = { 1 }
			mixed.a = 1
			T.expect(Json.isArray(mixed)).toBe(false)
			T.expect(Json.isArray({ [2] = 1 })).toBe(false)
			T.expect(Json.isArray({ [1.5] = 1 })).toBe(false)
			T.expect(Json.isArray({ [0] = 1 })).toBe(false)
			T.expect(Json.isArray("abc")).toBe(false)
			T.expect(Json.isArray(nil)).toBe(false)
			T.expect(Json.isArray(5)).toBe(false)
		end)
	end)

	T.describe("Json performance", function()
		local function bestOf(runs: number, fn: () -> ()): number
			local best = math.huge
			for _ = 1, runs do
				local started = os.clock()
				fn()
				best = math.min(best, os.clock() - started)
			end
			return best
		end

		-- `count` full components (~36 values each: transform, sequences, a track with keyframes).
		local function heavyDoc(count: number): any
			local components = table.create(count)
			for i = 1, count do
				components[i] = {
					id = "c" .. i,
					name = "Component " .. i,
					type = if i % 2 == 0 then "particles" else "part",
					startTime = i * 0.01,
					duration = 0.5,
					transform = { position = { i, i * 0.5, -i }, rotation = { 0, i % 360, 0 } },
					properties = { size = { { 0, 1 }, { 1, 0 } }, color = "#FF8800", rate = i },
					tracks = {
						{
							id = "t" .. i,
							channel = "transparency",
							keyframes = { { time = 0, value = 0 }, { time = 1, value = 1 } },
						},
					},
				}
			end
			return { schemaVersion = 1, id = "big", name = "Big", duration = 10, components = components }
		end

		T.it("encodes a 2000-element document well under 50 ms", function()
			local keyframes = table.create(2000)
			for i = 1, 2000 do
				keyframes[i] =
					{ time = i * 0.005, value = (i % 17) / 16, easing = if i % 3 == 0 then "Quad.Out" else "Linear" }
			end
			local doc = {
				schemaVersion = 1,
				id = "long-track",
				name = "Long Track",
				duration = 10,
				components = {
					{
						id = "c",
						name = "C",
						type = "part",
						tracks = { { id = "t", channel = "transparency", keyframes = keyframes } },
					},
				},
			}
			local text = Json.encode(doc)
			T.expect(bestOf(3, function()
				Json.encode(doc)
			end)).toBeLessThan(0.05)
			T.expect(bestOf(3, function()
				Json.encode(doc, { pretty = false })
			end)).toBeLessThan(0.05)
			T.expect(bestOf(3, function()
				Json.decode(text)
			end)).toBeLessThan(0.05)
			T.expect(Json.encode(decoded(text))).toBe(text)
		end)

		T.it("scales linearly with document size (no quadratic string building)", function()
			local small, large = heavyDoc(500), heavyDoc(2000)
			local smallText, largeText = Json.encode(small), Json.encode(large)
			local encodeSmall = bestOf(3, function()
				Json.encode(small)
			end)
			local encodeLarge = bestOf(3, function()
				Json.encode(large)
			end)
			local decodeSmall = bestOf(3, function()
				Json.decode(smallText)
			end)
			local decodeLarge = bestOf(3, function()
				Json.decode(largeText)
			end)
			-- 4x the data: linear ≈ 4x the time, quadratic ≈ 16x. Allow generous noise.
			T.expect(encodeLarge / encodeSmall).toBeLessThan(8)
			T.expect(decodeLarge / decodeSmall).toBeLessThan(8)
			T.expect(encodeLarge).toBeLessThan(0.5)
			T.expect(#largeText).toBeGreaterThan(1000000)
			T.expect(Json.encode(decoded(largeText))).toBe(largeText)
		end)
	end)
end
