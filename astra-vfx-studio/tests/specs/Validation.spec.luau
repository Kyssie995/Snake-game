--!strict
-- Core/Validation: totality, every diagnostic family, 1-based paths, strict mode, graph pass-through and lints.
return function(T: any, use: (string) -> any, _ctx: any)
	local Validation = use("AstraVFX.Core.Validation")
	local Constants = use("AstraVFX.Core.Constants")
	local Json = use("AstraVFX.Core.Json")
	local Random = use("AstraVFX.Core.Random")
	local Components = use("AstraVFX.Core.Components")

	-- ── Helpers ──────────────────────────────────────────────────────────────────────────────────────────

	-- Builds a mixed-type row (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end

	-- Every code any test in this file produced (checked against Validation.CODES at the end).
	local emitted: { [string]: boolean } = {}

	local function V(def: any, options: any?): any
		local result = Validation.validate(def, options)
		for _, list in { result.errors, result.warnings, result.infos } do
			for _, d in list do
				emitted[d.code] = true
			end
		end
		return result
	end

	local function all(result: any): { any }
		local out = {}
		for _, list in { result.errors, result.warnings, result.infos } do
			for _, d in list do
				table.insert(out, d)
			end
		end
		return out
	end

	-- First diagnostic with `code` (and `path` when given), or nil.
	local function find(result: any, code: string, path: string?): any
		for _, d in all(result) do
			if d.code == code and (path == nil or d.path == path) then
				return d
			end
		end
		return nil
	end

	local function count(result: any, code: string): number
		local n = 0
		for _, d in all(result) do
			if d.code == code then
				n += 1
			end
		end
		return n
	end

	local function codes(result: any): string
		local out = {}
		for _, d in all(result) do
			table.insert(out, d.severity .. " " .. d.code .. " @ " .. d.path .. ": " .. d.message)
		end
		return table.concat(out, "\n")
	end

	-- Asserts a diagnostic exists with the given severity.
	local function expectDiag(result: any, severity: string, code: string, path: string?): any
		local d = find(result, code, path)
		if d == nil then
			error("expected " .. code .. " at " .. tostring(path) .. ", got:\n" .. codes(result), 2)
		end
		T.expect(d.severity).toBe(severity)
		return d
	end

	local function expectClean(result: any)
		if #result.errors > 0 or #result.warnings > 0 then
			error("expected no errors/warnings, got:\n" .. codes(result), 2)
		end
		T.expect(result.ok).toBe(true)
	end

	local function deepCopy(v: any): any
		if type(v) ~= "table" or v == Json.NULL or v == Json.EMPTY_OBJECT then
			return v
		end
		local out = {}
		for k, x in pairs(v) do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function deepFreeze(v: any): any
		if type(v) == "table" and not table.isfrozen(v) then
			for _, x in pairs(v) do
				deepFreeze(x)
			end
			table.freeze(v)
		end
		return v
	end

	-- A valid definition that exercises most component types, markers, palette, graph and quality.
	local function baseDef(): any
		return {
			schemaVersion = 1,
			id = "test-fx",
			name = "Test FX",
			description = "Validation fixture",
			tags = { "test", "impact" },
			duration = 2,
			loop = false,
			seed = 42,
			timeScale = 1,
			palette = { primary = "#8A5CFF", hot = "#FFFFFF" },
			markers = {
				{ id = "impact", time = 0.5, label = "Impact", event = "Impact", phase = "impact" } :: any,
				{ id = "end", time = 2, label = "End", color = "$primary" },
			},
			components = {
				{
					id = "root",
					name = "Root",
					type = "group",
					properties = { spin = { 0, 90, 0 } },
				} :: any,
				{
					id = "trail",
					name = "Trail",
					type = "trail",
					parent = "root",
					transform = { position = { 2, 0, 0 } },
					properties = { color = "$primary", width = 0.5 },
				},
				{
					id = "sparks",
					name = "Sparks",
					type = "particles",
					phase = "impact",
					properties = { rate = 0, burst = 20, color = { R(0, "$hot"), R(1, "#FF0000") }, size = 0.5 },
					events = { { id = "e1", time = 0.25, action = "emit", count = 10 } },
					qualityOverrides = { Low = { burst = 8 } },
				},
				{
					id = "beam",
					name = "Beam",
					type = "beam",
					minQuality = "Medium",
					properties = { width0 = 1, width1 = 0, to = { 0, 0, -20 } },
					tracks = {
						{
							id = "fade",
							channel = "transparency",
							keyframes = { { time = 0, value = 1 }, { time = 0.3, value = 0, easing = "Quad.Out" } },
						},
					},
				},
				{
					id = "core",
					name = "Core",
					type = "sphere",
					startTime = 0,
					duration = 1.2,
					transform = { scale = 1, rotation = { 0, 45, 0 } },
					properties = { coreColor = "#9641FF", shellColor = "$primary" },
					tracks = {
						{
							id = "scale",
							channel = "scale",
							keyframes = {
								{ time = 0, value = 1 },
								{ time = 1.2, value = 8, easing = { bezier = { 0.2, 0, 0.2, 1 } } },
							},
						} :: any,
						{
							id = "tint",
							channel = "shellColor",
							keyframes = { { time = 0, value = "$primary" }, { time = 1, value = "#000000" } },
						},
					},
				},
				{ id = "flash", name = "Flash", type = "flash", startTime = 0.5, duration = 0.5 },
				{ id = "mesh", name = "Mesh", type = "mesh", properties = { meshType = "Sphere" } },
				{
					id = "boom",
					name = "Boom",
					type = "sound",
					properties = { soundId = "rbxassetid://123" },
					events = {
						{ id = "p", time = 0, action = "play" },
						{ id = "f", time = 0.1, action = "fire", name = "Boom" },
					},
				},
				{ id = "wave", name = "Wave", type = "shockwave", properties = { expandEasing = "Quint.Out" } },
			},
			graph = {
				nodes = {
					{ id = "start", type = "OnPlay" } :: any,
					{ id = "emit", type = "Emit", params = { target = "sparks", count = 5 } },
				},
				links = { { from = "start.out", to = "emit.in" } },
			},
			quality = { Low = { countScale = 0.3, maxLights = 1 }, High = { lightShadows = true } },
			metadata = { author = "tests", nested = { list = { 1, 2, 3 } } },
		}
	end

	local function component(def: any, id: string): any
		for _, c in def.components do
			if c.id == id then
				return c
			end
		end
		error("no component " .. id)
	end

	-- ── Basics ───────────────────────────────────────────────────────────────────────────────────────────

	T.describe("Validation basics", function()
		T.it("accepts the fixture without errors or warnings", function()
			expectClean(V(baseDef()))
		end)

		T.it("returns the ValidationResult shape", function()
			local result = V(baseDef())
			T.expect(type(result.errors)).toBe("table")
			T.expect(type(result.warnings)).toBe("table")
			T.expect(type(result.infos)).toBe("table")
			T.expect(result.ok).toBe(true)
		end)

		T.it("accepts a definition decoded from JSON text (Json sentinels included)", function()
			local text = [[{
				"$schema": "../schema/astra-effect.schema.json",
				"schemaVersion": 1, "id": "json-fx", "name": "Json FX", "duration": 1.5,
				"palette": {},
				"components": [
					{ "id": "p", "name": "Puff", "type": "particles", "properties": {},
					  "events": [ { "id": "e", "time": 0, "action": "emit", "count": 12 } ] },
					{ "id": "s", "name": "Spark", "type": "part", "tracks": [] }
				]
			}]]
			local ok, def = Json.decode(text)
			T.expect(ok).toBe(true)
			T.expect(def.palette).toBe(Json.EMPTY_OBJECT)
			expectClean(V(def))
		end)

		T.it("does not mutate its input (deeply frozen definition)", function()
			local def = baseDef()
			local before = Json.encode(def)
			deepFreeze(def)
			local result = V(def)
			T.expect(result.ok).toBe(true)
			T.expect(Json.encode(def)).toBe(before)
		end)

		T.it("is deterministic", function()
			local broken = baseDef()
			broken.components[3].properties = { rate = 900, Burst = 1, zzz = true, aaa = false }
			broken.components[2].tracks = { { id = "x", channel = "nope", keyframes = {} } }
			local a = V(broken)
			local b = V(deepCopy(broken))
			T.expect(codes(a)).toBe(codes(b))
			-- unknown keys are visited in sorted order
			local unknown = {}
			for _, d in a.warnings do
				if d.code == "property.unknown" then
					table.insert(unknown, d.path)
				end
			end
			T.expect(unknown).toEqual({
				"components[3].properties.Burst",
				"components[3].properties.aaa",
				"components[3].properties.zzz",
			})
		end)

		T.it("sets componentId on component diagnostics", function()
			local def = baseDef()
			component(def, "sparks").properties.rate = -5
			local d = expectDiag(V(def), "error", "property.range", "components[3].properties.rate")
			T.expect(d.componentId).toBe("sparks")
		end)
	end)

	-- ── Totality ─────────────────────────────────────────────────────────────────────────────────────────

	T.describe("Validation totality", function()
		local cyclic: any = {}
		cyclic.self = cyclic
		cyclic[1] = cyclic

		local GARBAGE: { any } = {
			5,
			-1,
			0 / 0,
			math.huge,
			"text",
			"",
			true,
			false,
			{},
			{ 1, 2, 3 },
			{ a = 1 },
			{ [1] = 1, x = 2 },
			{ [3] = 1 },
			Json.NULL,
			Json.EMPTY_OBJECT,
			function() end,
			Vector3.new(1, 2, 3),
			Color3.new(1, 0, 0),
			cyclic,
		}

		T.it("never throws for garbage definitions", function()
			for _, g in GARBAGE do
				local ok, result = pcall(Validation.validate, g)
				T.expect(ok).toBe(true)
				T.expect(result.ok).toBe(false)
				T.expect(#result.errors).toBeGreaterThan(0)
			end
			local ok, result = pcall(Validation.validate :: any)
			T.expect(ok).toBe(true)
			expectDiag(result, "error", "effect.type", "")
		end)

		T.it("never throws for garbage options", function()
			for _, g in GARBAGE do
				local ok, result = pcall(Validation.validate, baseDef(), g)
				T.expect(ok).toBe(true)
				T.expect(result.ok).toBe(true)
			end
		end)

		-- Every table path of the fixture, as key lists.
		local function paths(v: any, prefix: { any }, out: { { any } })
			if type(v) ~= "table" then
				return
			end
			local keys = {}
			for k in pairs(v) do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, k in keys do
				local p = table.clone(prefix)
				table.insert(p, k)
				table.insert(out, p)
				paths(v[k], p, out)
			end
		end

		-- Sets def[p[1]]...[p[n]] = value; skips paths that run through garbage placed earlier.
		local function setPath(def: any, p: { any }, value: any)
			local t = def
			for i = 1, #p - 1 do
				if type(t) ~= "table" then
					return
				end
				t = t[p[i]]
			end
			if type(t) == "table" and not table.isfrozen(t) and getmetatable(t) == nil then
				t[p[#p]] = value
			end
		end

		T.it("never throws when any value of a valid definition is replaced by garbage", function()
			local list: { { any } } = {}
			paths(baseDef(), {}, list)
			T.expect(#list).toBeGreaterThan(100)
			local replacements: { any } = { "nil" }
			for _, g in GARBAGE do
				table.insert(replacements, g)
			end
			local runs = 0
			for _, p in list do
				for _, g in replacements do
					local def = baseDef()
					setPath(def, p, if g == "nil" then nil else g)
					local ok, result = pcall(Validation.validate, def)
					if not ok then
						error("validate threw for path " .. table.concat(p :: any, ".") .. ": " .. tostring(result))
					end
					T.expect(type(result.ok)).toBe("boolean")
					runs += 1
				end
			end
			T.expect(runs).toBeGreaterThan(1000)
		end)

		T.it("never throws for random deep garbage (seeded)", function()
			local rng = Random.new(1234)
			local function garbage(depth: number): any
				local r = rng:int(1, 10)
				if depth > 4 or r <= 4 then
					return GARBAGE[rng:int(1, #GARBAGE)]
				elseif r <= 7 then
					local t = {}
					for i = 1, rng:int(0, 4) do
						t[i] = garbage(depth + 1)
					end
					return t
				end
				local t = {}
				for _, key in { "id", "type", "time", "value", "keyframes", "tracks", "properties", "channel" } do
					if rng:next() < 0.5 then
						t[key] = garbage(depth + 1)
					end
				end
				return t
			end
			for _ = 1, 300 do
				local def = baseDef()
				local list: { { any } } = {}
				paths(def, {}, list)
				for _ = 1, 3 do
					setPath(def, list[rng:int(1, #list)], garbage(0))
				end
				local ok, result = pcall(Validation.validate, def)
				if not ok then
					error("validate threw: " .. tostring(result))
				end
			end
		end)

		T.it("handles cyclic tables anywhere", function()
			local def = baseDef()
			def.components[1].properties.spin = cyclic
			def.components[2].tracks = cyclic
			def.metadata = { loop = cyclic }
			def.graph = cyclic
			def.palette = { primary = cyclic }
			def.components[4] = cyclic
			local result = V(def)
			T.expect(result.ok).toBe(false)
			expectDiag(result, "error", "property.type", "components[1].properties.spin")
			expectDiag(result, "error", "effect.metadata", "metadata.loop")
			expectDiag(result, "error", "component.invalid", "components[4]")
		end)

		T.it("reports (never throws) hostile metatables as effect.internal", function()
			local def = baseDef()
			def.components[2] = setmetatable({}, {
				__index = function()
					error(setmetatable({}, {
						__tostring = function()
							error("nope")
						end,
					}))
				end,
			})
			local ok, result = pcall(V, def)
			T.expect(ok).toBe(true)
			expectDiag(result, "error", "effect.internal", "components[2]")
			T.expect(result.ok).toBe(false)
			-- the other components are still validated
			def.components[3].properties.rate = 1000
			expectDiag(V(def), "error", "property.range", "components[3].properties.rate")
		end)
	end)

	-- ── Effect fields ────────────────────────────────────────────────────────────────────────────────────

	T.describe("Validation effect fields", function()
		T.it("rejects non-object definitions", function()
			expectDiag(V(5), "error", "effect.type", "")
			expectDiag(V({ 1, 2 }), "error", "effect.type", "")
			expectDiag(V(Json.NULL), "error", "effect.type", "")
		end)

		T.it("checks schemaVersion", function()
			local def = baseDef()
			def.schemaVersion = nil
			local d = expectDiag(V(def), "error", "effect.schema_version", "schemaVersion")
			T.expect(d.hint).toMatch("Migration")
			def.schemaVersion = 2
			T.expect(expectDiag(V(def), "error", "effect.schema_version").hint).toMatch("update")
			def.schemaVersion = 0
			expectDiag(V(def), "error", "effect.schema_version")
			def.schemaVersion = "1"
			expectDiag(V(def), "error", "effect.schema_version")
		end)

		T.it("checks id, name and duration", function()
			local def = baseDef()
			def.id = "has space"
			def.name = "   "
			def.duration = 0
			local result = V(def)
			expectDiag(result, "error", "effect.id", "id")
			expectDiag(result, "error", "effect.name", "name")
			expectDiag(result, "error", "effect.duration", "duration")
			def.id = string.rep("a", 65)
			def.name = string.rep("n", Constants.NAME_MAX_LENGTH + 1)
			def.duration = Constants.MAX_DURATION + 1
			result = V(def)
			expectDiag(result, "error", "effect.id")
			expectDiag(result, "error", "effect.name")
			expectDiag(result, "error", "effect.duration")
			def.id = string.rep("a", 64)
			def.name = string.rep("n", Constants.NAME_MAX_LENGTH)
			def.duration = Constants.MAX_DURATION
			expectClean(V(def))
			def.duration = 0 / 0
			expectDiag(V(def), "error", "effect.duration")
			def.duration = nil
			expectDiag(V(def), "error", "effect.duration")
		end)

		T.it("checks optional effect fields", function()
			local def = baseDef()
			def.description = 5
			def.tags = R("ok", 7)
			def.loop = "yes"
			def.seed = 1.5
			def.timeScale = 0
			local result = V(def)
			expectDiag(result, "error", "effect.description", "description")
			expectDiag(result, "error", "effect.tags", "tags[2]")
			expectDiag(result, "error", "effect.loop", "loop")
			expectDiag(result, "error", "effect.seed", "seed")
			expectDiag(result, "error", "effect.time_scale", "timeScale")
			def.tags = "x"
			def.timeScale = Constants.MAX_TIME_SCALE + 1
			result = V(def)
			expectDiag(result, "error", "effect.tags", "tags")
			expectDiag(result, "error", "effect.time_scale")
		end)

		T.it("checks the palette", function()
			local def = baseDef()
			def.palette = { primary = "#8A5CFF", hot = "nope", ["bad key"] = "#FFFFFF", alias = "$primary" }
			local result = V(def)
			expectDiag(result, "error", "effect.palette", "palette.hot")
			expectDiag(result, "error", "effect.palette", 'palette["bad key"]')
			expectDiag(result, "error", "effect.palette", "palette.alias")
			def.palette = { 1, 2 }
			expectDiag(V(def), "error", "effect.palette", "palette")
		end)

		T.it("checks metadata is plain JSON", function()
			local def = baseDef()
			def.metadata = { a = { b = { 1, 0 / 0 } } }
			expectDiag(V(def), "error", "effect.metadata", "metadata.a.b[2]")
			def.metadata = { f = print }
			expectDiag(V(def), "error", "effect.metadata", "metadata.f")
			def.metadata = "x"
			expectDiag(V(def), "error", "effect.metadata", "metadata")
		end)

		T.it("checks components presence and warns about empty effects", function()
			local def = baseDef()
			def.components = nil
			expectDiag(V(def), "error", "effect.components", "components")
			def.components = { a = 1 }
			expectDiag(V(def), "error", "effect.components", "components")
			def.components = {}
			def.graph = nil
			local result = V(def)
			T.expect(result.ok).toBe(true)
			expectDiag(result, "warning", "effect.empty", "components")
		end)

		T.it("warns about unknown top-level fields and allows $schema", function()
			local def = baseDef()
			def["$schema"] = "x.json"
			def.colour = "red"
			local result = V(def)
			expectDiag(result, "warning", "effect.unknown_field", "colour")
			T.expect(count(result, "effect.unknown_field")).toBe(1)
			T.expect(result.ok).toBe(true)
			expectDiag(V(def, { strict = true }), "error", "effect.unknown_field", "colour")
		end)

		T.it("enforces the component limit", function()
			local def = baseDef()
			def.components = {}
			for i = 1, Constants.MAX_COMPONENTS + 1 do
				table.insert(def.components, { id = "c" .. i, name = "C" .. i, type = "group" })
			end
			expectDiag(V(def), "error", "component.limit", "components")
			table.remove(def.components)
			T.expect(find(V(def), "component.limit")).toBeNil()
		end)
	end)

	-- ── Components ───────────────────────────────────────────────────────────────────────────────────────

	T.describe("Validation components", function()
		T.it("checks entries, ids, names and types", function()
			local def = baseDef()
			table.insert(def.components, 5)
			table.insert(def.components, { id = "root", name = "Dup", type = "group" })
			table.insert(def.components, { id = "bad id", name = "", type = "Particles" })
			table.insert(def.components, { name = "NoId", type = 5 })
			local result = V(def)
			expectDiag(result, "error", "component.invalid", "components[10]")
			expectDiag(result, "error", "component.duplicate_id", "components[11].id")
			expectDiag(result, "error", "component.id", "components[12].id")
			expectDiag(result, "error", "component.name", "components[12].name")
			local d = expectDiag(result, "error", "component.type", "components[12].type")
			T.expect(d.hint).toMatch("particles")
			expectDiag(result, "error", "component.type", "components[13].type")
			expectDiag(result, "error", "component.id", "components[13].id")
		end)

		T.it("checks scalar component fields", function()
			local def = baseDef()
			local c = component(def, "flash")
			c.enabled = "no"
			c.startTime = -1
			c.duration = 0
			c.phase = "Impact"
			c.minQuality = "Ultra"
			c.notes = {}
			c.extra = 1
			local result = V(def)
			expectDiag(result, "error", "component.enabled", "components[6].enabled")
			expectDiag(result, "error", "component.start_time", "components[6].startTime")
			expectDiag(result, "error", "component.duration", "components[6].duration")
			T.expect(expectDiag(result, "error", "component.phase", "components[6].phase").hint).toMatch("impact")
			expectDiag(result, "error", "component.min_quality", "components[6].minQuality")
			expectDiag(result, "error", "component.notes", "components[6].notes")
			expectDiag(result, "warning", "component.unknown_field", "components[6].extra")
		end)

		T.it("warns about spans outside the effect", function()
			local def = baseDef()
			component(def, "flash").startTime = 2
			expectDiag(V(def), "warning", "component.timing", "components[6].startTime")
			def = baseDef()
			component(def, "flash").duration = 5
			expectDiag(V(def), "warning", "component.timing", "components[6].duration")
			def = baseDef()
			component(def, "flash").startTime = 1.5 -- 1.5 + 0.5 = 2 (exactly the end)
			T.expect(find(V(def), "component.timing")).toBeNil()
		end)

		T.it("checks transforms", function()
			local def = baseDef()
			component(def, "core").transform = { position = { 1, 2 }, rotation = "x", scale = -1, skew = 1 }
			local result = V(def)
			expectDiag(result, "error", "component.transform", "components[5].transform.position")
			expectDiag(result, "error", "component.transform", "components[5].transform.rotation")
			expectDiag(result, "error", "component.transform", "components[5].transform.scale")
			expectDiag(result, "warning", "component.unknown_field", "components[5].transform.skew")
			component(def, "core").transform = { position = 3 } -- a single number is a valid vector3
			T.expect(find(V(def), "component.transform")).toBeNil()
			component(def, "core").transform = 7
			expectDiag(V(def), "error", "component.transform", "components[5].transform")
		end)

		T.it("checks the parent hierarchy", function()
			local def = baseDef()
			component(def, "trail").parent = "trail"
			expectDiag(V(def), "error", "component.parent_self", "components[2].parent")
			component(def, "trail").parent = "Root"
			T.expect(expectDiag(V(def), "error", "component.parent_missing", "components[2].parent").hint)
				.toMatch('"root"')
			component(def, "trail").parent = 5
			expectDiag(V(def), "error", "component.parent", "components[2].parent")
		end)

		T.it("detects parent cycles once per cycle", function()
			local def = baseDef()
			component(def, "root").parent = "beam"
			component(def, "beam").parent = "trail"
			-- root -> beam -> trail -> root ; mesh hangs off the cycle
			component(def, "mesh").parent = "beam"
			local result = V(def)
			T.expect(count(result, "component.parent_cycle")).toBe(1)
			local d = expectDiag(result, "error", "component.parent_cycle", "components[1].parent")
			T.expect(d.message).toMatch("root %-> beam %-> trail %-> root")
			T.expect(d.componentId).toBe("root")
		end)

		T.it("rejects parents that cannot have children", function()
			local def = baseDef()
			component(def, "mesh").parent = "boom"
			T.expect(find(V(def), "component.parent_type")).toBeNil()
			-- every registered type may parent today; flip one descriptor temporarily (restored below)
			local sound = Components.get("sound")
			T.expect(table.isfrozen(sound)).toBe(false)
			sound.canParent = false
			local ok, result = pcall(V, def)
			sound.canParent = true
			T.expect(ok).toBe(true)
			local d = expectDiag(result, "error", "component.parent_type", "components[7].parent")
			T.expect(d.componentId).toBe("mesh")
		end)

		T.it("notes components below a disabled ancestor", function()
			local def = baseDef()
			component(def, "root").enabled = false
			local result = V(def)
			local d = expectDiag(result, "info", "component.disabled_ancestor", "components[2]")
			T.expect(d.componentId).toBe("trail")
			T.expect(result.ok).toBe(true)
		end)
	end)

	-- ── Properties ───────────────────────────────────────────────────────────────────────────────────────

	T.describe("Validation properties", function()
		T.it("reports unknown properties as warnings (errors when strict)", function()
			local def = baseDef()
			component(def, "sparks").properties.Rate = 5
			local result = V(def)
			local d = expectDiag(result, "warning", "property.unknown", "components[3].properties.Rate")
			T.expect(d.hint).toMatch('"rate"')
			T.expect(result.ok).toBe(true)
			result = V(def, { strict = true })
			expectDiag(result, "error", "property.unknown", "components[3].properties.Rate")
			T.expect(result.ok).toBe(false)
		end)

		T.it("hints at legacy concept keys", function()
			local def = baseDef()
			component(def, "core").properties.initialScale = 1
			component(def, "core").properties.color = "#FFFFFF"
			local result = V(def)
			T.expect(expectDiag(result, "warning", "property.unknown", "components[5].properties.initialScale").hint)
				.toMatch("Migration")
			T.expect(expectDiag(result, "warning", "property.unknown", "components[5].properties.color").hint)
				.toMatch("coreColor")
		end)

		T.it("checks every value with Codec (type vs range)", function()
			local def = baseDef()
			local props = component(def, "sparks").properties
			props.rate = 401 -- above the engine cap
			props.burst = 2.5 -- not an integer
			props.lifetime = { 3, 1 } -- min > max
			props.shape = "Ball" -- not in the enum
			props.texture = 12.5
			props.spreadAngle = { 1, 2, 3 }
			local result = V(def)
			expectDiag(result, "error", "property.range", "components[3].properties.rate")
			expectDiag(result, "error", "property.type", "components[3].properties.burst")
			expectDiag(result, "error", "property.type", "components[3].properties.lifetime")
			expectDiag(result, "error", "property.range", "components[3].properties.shape")
			expectDiag(result, "error", "property.type", "components[3].properties.texture")
			expectDiag(result, "error", "property.type", "components[3].properties.spreadAngle")
		end)

		T.it("enforces the sequence keypoint limit", function()
			local def = baseDef()
			local keys = {}
			for i = 1, Constants.MAX_SEQUENCE_KEYPOINTS + 1 do
				table.insert(keys, { (i - 1) / Constants.MAX_SEQUENCE_KEYPOINTS, 0.5 })
			end
			component(def, "sparks").properties.transparency = keys
			local d = expectDiag(V(def), "error", "property.range", "components[3].properties.transparency")
			T.expect(d.message).toMatch("21 keypoints")
			table.remove(keys)
			keys[#keys][1] = 1
			T.expect(find(V(def), "property.range")).toBeNil()
		end)

		T.it("checks palette references in colours and colour sequences", function()
			local def = baseDef()
			component(def, "trail").properties.color = "$missing"
			component(def, "core").properties.coreColor = "$alsoMissing"
			component(def, "sparks").properties.color = { R(0, "#FFFFFF"), R(1, "$gone") }
			local result = V(def)
			expectDiag(result, "error", "property.ref", "components[2].properties.color")
			expectDiag(result, "error", "property.ref", "components[5].properties.coreColor")
			expectDiag(result, "error", "property.ref", "components[3].properties.color")
		end)

		T.it("checks easing-valued string properties", function()
			local def = baseDef()
			component(def, "wave").properties.fadeEasing = "quad.in"
			expectDiag(V(def), "error", "property.type", "components[9].properties.fadeEasing")
		end)

		T.it("rejects a properties value that is not an object", function()
			local def = baseDef()
			component(def, "sparks").properties = { 1, 2 }
			expectDiag(V(def), "error", "component.properties", "components[3].properties")
		end)
	end)

	-- ── Tracks, keyframes, events ────────────────────────────────────────────────────────────────────────

	T.describe("Validation tracks and keyframes", function()
		T.it("uses 1-based paths down to keyframe values", function()
			local def = baseDef()
			component(def, "sparks").tracks = {
				{
					id = "rate",
					channel = "rate",
					keyframes = { { time = 0, value = 10 } :: any, { time = 0.5, value = "x" } },
				},
			}
			expectDiag(V(def), "error", "keyframe.value", "components[3].tracks[1].keyframes[2].value")
		end)

		T.it("checks track structure, ids and channels", function()
			local def = baseDef()
			component(def, "core").tracks = {
				5 :: any,
				{ id = "a", channel = "radius", keyframes = { { time = 0, value = 1 } } },
				{ id = "a", channel = "Radius", keyframes = { { time = 0, value = 1 } } },
				{ id = "b", channel = "coreMaterial", keyframes = { { time = 0, value = 1 } } },
				{ id = "c", channel = "radius", keyframes = { { time = 0, value = 2 } } },
				{ id = "d", channel = "radius", enabled = false, keyframes = { { time = 0, value = 2 } } },
				{ id = "bad id", channel = 7, keyframes = {}, enabled = "x", extra = true },
			}
			local result = V(def)
			expectDiag(result, "error", "track.invalid", "components[5].tracks[1]")
			expectDiag(result, "error", "track.duplicate_id", "components[5].tracks[3].id")
			T.expect(expectDiag(result, "error", "track.channel", "components[5].tracks[3].channel").hint)
				.toMatch('"radius"')
			T.expect(expectDiag(result, "error", "track.channel", "components[5].tracks[4].channel").hint)
				.toMatch("not animatable")
			expectDiag(result, "error", "track.duplicate_channel", "components[5].tracks[5].channel")
			T.expect(find(result, "track.duplicate_channel", "components[5].tracks[6].channel")).toBeNil()
			expectDiag(result, "error", "track.id", "components[5].tracks[7].id")
			expectDiag(result, "error", "track.channel", "components[5].tracks[7].channel")
			expectDiag(result, "error", "track.keyframes", "components[5].tracks[7].keyframes")
			expectDiag(result, "error", "track.enabled", "components[5].tracks[7].enabled")
			expectDiag(result, "warning", "track.unknown_field", "components[5].tracks[7].extra")
			component(def, "core").tracks = "x"
			expectDiag(V(def), "error", "component.tracks", "components[5].tracks")
		end)

		T.it("checks keyframes", function()
			local def = baseDef()
			component(def, "beam").tracks = {
				{
					id = "w",
					channel = "width0",
					keyframes = {
						"x" :: any,
						{ time = -1, value = 1 },
						{ time = 0.5 },
						{ time = 0.2, value = 2, easing = "Bogus", junk = 1 },
						{ time = 0.3, value = -1 },
					},
				} :: any,
				{ id = "t", channel = "tint", keyframes = { { time = 0, value = "$nope" } } },
			}
			local result = V(def)
			local p = "components[4].tracks[1].keyframes"
			expectDiag(result, "error", "keyframe.invalid", p .. "[1]")
			expectDiag(result, "error", "keyframe.time", p .. "[2].time")
			expectDiag(result, "error", "keyframe.value", p .. "[3].value")
			expectDiag(result, "error", "keyframe.easing", p .. "[4].easing")
			expectDiag(result, "warning", "keyframe.unknown_field", p .. "[4].junk")
			expectDiag(result, "warning", "keyframe.order", p .. "[4].time")
			-- width0 channel: min 0 (channel spec range)
			expectDiag(result, "error", "keyframe.value", p .. "[5].value")
			expectDiag(result, "error", "keyframe.ref", "components[4].tracks[2].keyframes[1].value")
		end)

		T.it("enforces track and keyframe limits", function()
			local def = baseDef()
			local tracks = {}
			for i = 1, Constants.MAX_TRACKS_PER_COMPONENT + 1 do
				table.insert(
					tracks,
					{ id = "t" .. i, channel = "position", enabled = false, keyframes = { { time = 0, value = 0 } } }
				)
			end
			component(def, "core").tracks = tracks
			expectDiag(V(def), "error", "track.limit", "components[5].tracks")
			local keys = {}
			for i = 1, Constants.MAX_KEYFRAMES_PER_TRACK + 1 do
				table.insert(keys, { time = i / 1000, value = 1 })
			end
			component(def, "core").tracks = { { id = "s", channel = "scale", keyframes = keys } }
			expectDiag(V(def), "error", "keyframe.limit", "components[5].tracks[1].keyframes")
		end)
	end)

	T.describe("Validation events", function()
		T.it("checks event structure, actions, counts and names", function()
			local def = baseDef()
			component(def, "sparks").events = {
				{ id = "a", time = 0, action = "emit", count = 5 } :: any,
				{ id = "a", time = 0, action = "emit" },
				{ id = "c", time = -1, action = "Emit", count = 5 },
				{ id = "d", time = 0, action = "emit", count = Constants.MAX_EMIT_COUNT + 1 },
				{ id = "e", time = 0, action = "clear", count = 3, name = "x" },
				{ id = "f", time = 0, action = "fire" },
				{ id = "g", time = 0, action = "fire", name = "bad name!" },
				{ id = "h", time = 0, action = 5, extra = 1 },
				"x",
			}
			local result = V(def)
			local p = "components[3].events"
			expectDiag(result, "error", "event.duplicate_id", p .. "[2].id")
			expectDiag(result, "error", "event.count", p .. "[2].count")
			expectDiag(result, "error", "event.time", p .. "[3].time")
			T.expect(expectDiag(result, "error", "event.action", p .. "[3].action").hint).toMatch('"emit"')
			expectDiag(result, "error", "event.count", p .. "[4].count")
			expectDiag(result, "warning", "event.count", p .. "[5].count")
			expectDiag(result, "warning", "event.name", p .. "[5].name")
			expectDiag(result, "error", "event.name", p .. "[6].name")
			expectDiag(result, "error", "event.name", p .. "[7].name")
			expectDiag(result, "error", "event.action", p .. "[8].action")
			expectDiag(result, "warning", "event.unknown_field", p .. "[8].extra")
			expectDiag(result, "error", "event.invalid", p .. "[9]")
			component(def, "sparks").events = { { time = 0, action = "emit", count = 1 } }
			expectDiag(V(def), "error", "event.id", p .. "[1].id")
			component(def, "sparks").events = 5
			expectDiag(V(def), "error", "component.events", p)
		end)

		T.it("rejects actions the component type does not declare", function()
			local def = baseDef()
			component(def, "core").events = { { id = "x", time = 0, action = "emit", count = 1 } }
			local d = expectDiag(V(def), "error", "event.action", "components[5].events[1].action")
			T.expect(d.message).toMatch("sphere")
		end)

		T.it("enforces the event limit", function()
			local def = baseDef()
			local events = {}
			for i = 1, Constants.MAX_EVENTS_PER_COMPONENT + 1 do
				table.insert(events, { id = "e" .. i, time = 0, action = "emit", count = 1 })
			end
			component(def, "sparks").events = events
			expectDiag(V(def), "error", "event.limit", "components[3].events")
		end)
	end)

	-- ── Markers ──────────────────────────────────────────────────────────────────────────────────────────

	T.describe("Validation markers", function()
		T.it("checks markers", function()
			local def = baseDef()
			def.markers = {
				{ id = "m", time = 0.5, label = "A" } :: any,
				{ id = "m", time = 3, label = "B" },
				{ id = "bad id", time = -1, label = 5, phase = "boom", event = "1abc", color = "$none", x = 1 },
				7,
			}
			local result = V(def)
			expectDiag(result, "error", "marker.duplicate_id", "markers[2].id")
			expectDiag(result, "warning", "marker.time", "markers[2].time")
			expectDiag(result, "error", "marker.id", "markers[3].id")
			expectDiag(result, "error", "marker.time", "markers[3].time")
			expectDiag(result, "error", "marker.label", "markers[3].label")
			expectDiag(result, "error", "marker.phase", "markers[3].phase")
			expectDiag(result, "error", "marker.event", "markers[3].event")
			expectDiag(result, "error", "marker.color", "markers[3].color")
			expectDiag(result, "warning", "marker.unknown_field", "markers[3].x")
			expectDiag(result, "error", "marker.invalid", "markers[4]")
			def.markers = { { id = "m", time = 0, label = "A", event = "", color = "#F00" } }
			expectClean(V(def))
			def.markers = "x"
			expectDiag(V(def), "error", "marker.type", "markers")
		end)

		T.it("enforces the marker limit", function()
			local def = baseDef()
			def.markers = {}
			for i = 1, Constants.MAX_MARKERS + 1 do
				table.insert(def.markers, { id = "m" .. i, time = 0, label = "M" })
			end
			expectDiag(V(def), "error", "marker.limit", "markers")
		end)
	end)

	-- ── Graph and quality ────────────────────────────────────────────────────────────────────────────────

	T.describe("Validation graph and quality", function()
		T.it("passes Graph.validate diagnostics through", function()
			local def = baseDef()
			def.graph.nodes[2].params.target = "nope"
			local result = V(def)
			expectDiag(result, "error", "graph.component_missing", "graph.nodes[2].params.target")
			def.graph = 5
			expectDiag(V(def), "error", "graph.type")
		end)

		T.it("checks the effect quality map", function()
			local def = baseDef()
			def.quality = {
				low = { countScale = 0.5 },
				Medium = { countScale = -1, sizeCompensation = 0, lightShadows = 1, maxLights = 1.5, colour = 1 },
				High = 5,
			}
			local result = V(def)
			T.expect(expectDiag(result, "error", "quality.level", "quality.low").hint).toMatch('"Low"')
			expectDiag(result, "error", "quality.value", "quality.Medium.countScale")
			expectDiag(result, "error", "quality.value", "quality.Medium.sizeCompensation")
			expectDiag(result, "error", "quality.value", "quality.Medium.lightShadows")
			expectDiag(result, "error", "quality.value", "quality.Medium.maxLights")
			expectDiag(result, "warning", "quality.field", "quality.Medium.colour")
			expectDiag(result, "error", "quality.type", "quality.High")
			def.quality = { 1 }
			expectDiag(V(def), "error", "quality.type", "quality")
		end)

		T.it("checks component qualityOverrides", function()
			local def = baseDef()
			component(def, "sparks").qualityOverrides = {
				Ultra = { rate = 1 },
				Low = { rate = 999, nope = 1 },
				Medium = "x",
			}
			local result = V(def)
			expectDiag(result, "error", "quality.level", "components[3].qualityOverrides.Ultra")
			expectDiag(result, "error", "property.range", "components[3].qualityOverrides.Low.rate")
			expectDiag(result, "warning", "property.unknown", "components[3].qualityOverrides.Low.nope")
			expectDiag(result, "error", "quality.type", "components[3].qualityOverrides.Medium")
			component(def, "sparks").qualityOverrides = 3
			expectDiag(V(def), "error", "quality.type", "components[3].qualityOverrides")
		end)
	end)

	-- ── Lints ────────────────────────────────────────────────────────────────────────────────────────────

	T.describe("Validation lints", function()
		T.it("lint.trail_static: a trail needs a moving source", function()
			local def = baseDef()
			component(def, "root").properties.spin = { 0, 0, 0 }
			local d = expectDiag(V(def), "warning", "lint.trail_static", "components[2]")
			T.expect(d.componentId).toBe("trail")
			-- position track on the trail itself
			component(def, "trail").tracks = {
				{
					id = "p",
					channel = "position",
					keyframes = { { time = 0, value = { 0, 0, 0 } }, { time = 1, value = { 5, 0, 0 } } },
				},
			}
			T.expect(find(V(def), "lint.trail_static")).toBeNil()
			-- a single keyframe does not move
			component(def, "trail").tracks[1].keyframes = { { time = 0, value = { 0, 0, 0 } } }
			expectDiag(V(def), "warning", "lint.trail_static")
			-- rotation track on the ancestor
			component(def, "trail").tracks = nil
			component(def, "root").tracks = {
				{
					id = "r",
					channel = "rotation",
					keyframes = { { time = 0, value = 0 } :: any, { time = 1, value = { 0, 180, 0 } } },
				},
			}
			T.expect(find(V(def), "lint.trail_static")).toBeNil()
			-- graph tween of the trail's position
			component(def, "root").tracks = nil
			def.graph.nodes[3] = {
				id = "tw",
				type = "Tween",
				params = { target = "trail", channel = "position", value = { 0, 5, 0 }, duration = 0.5 },
			}
			def.graph.links[2] = { from = "emit.out", to = "tw.in" }
			T.expect(find(V(def), "lint.trail_static")).toBeNil()
			-- disabled components are not linted
			def = baseDef()
			component(def, "root").properties.spin = nil
			component(def, "trail").enabled = false
			T.expect(find(V(def), "lint.trail_static")).toBeNil()
			-- neither are components below a disabled ancestor (they are not built)
			def = baseDef()
			component(def, "root").properties.spin = nil
			component(def, "root").enabled = false
			local result = V(def)
			T.expect(find(result, "lint.trail_static")).toBeNil()
			expectDiag(result, "info", "component.disabled_ancestor", "components[2]")
		end)

		T.it("lint.particles_silent: particles that never emit", function()
			local def = baseDef()
			def.graph = nil
			local sparks = component(def, "sparks")
			sparks.properties.burst = 0
			sparks.events = nil
			sparks.qualityOverrides = nil
			local d = expectDiag(V(def), "warning", "lint.particles_silent", "components[3]")
			T.expect(d.componentId).toBe("sparks")
			-- default rate (20) emits
			sparks.properties.rate = nil
			T.expect(find(V(def), "lint.particles_silent")).toBeNil()
			sparks.properties.rate = 0
			-- an emit event
			sparks.events = { { id = "e", time = 0, action = "emit", count = 1 } }
			T.expect(find(V(def), "lint.particles_silent")).toBeNil()
			sparks.events = { { id = "e", time = 0, action = "enable" } }
			expectDiag(V(def), "warning", "lint.particles_silent")
			-- a rate track above 0
			sparks.tracks =
				{ { id = "r", channel = "rate", keyframes = { { time = 0, value = 0 }, { time = 1, value = 50 } } } }
			T.expect(find(V(def), "lint.particles_silent")).toBeNil()
			sparks.tracks = nil
			-- a quality override
			sparks.qualityOverrides = { High = { burst = 5 } }
			T.expect(find(V(def), "lint.particles_silent")).toBeNil()
			sparks.qualityOverrides = nil
			-- a graph Emit via a Component node link
			def.graph = {
				nodes = {
					{ id = "go", type = "OnPlay" } :: any,
					{ id = "ref", type = "Component", params = { component = "sparks" } },
					{ id = "emit", type = "Emit", params = { count = 3 } },
				},
				links = { { from = "go.out", to = "emit.in" }, { from = "ref.component", to = "emit.target" } },
			}
			local result = V(def)
			T.expect(find(result, "lint.particles_silent")).toBeNil()
			T.expect(result.ok).toBe(true)
			-- an Emit aimed at another component does not count
			def.graph.nodes[2].params.component = "trail"
			expectDiag(V(def), "warning", "lint.particles_silent")
		end)

		T.it("lint.zero_width: a beam with zero width", function()
			local def = baseDef()
			local beam = component(def, "beam")
			beam.properties.width0 = 0
			expectDiag(V(def), "warning", "lint.zero_width", "components[4]")
			beam.tracks =
				{ { id = "w", channel = "width1", keyframes = { { time = 0, value = 0 }, { time = 1, value = 2 } } } }
			T.expect(find(V(def), "lint.zero_width")).toBeNil()
		end)

		T.it("lint.outside_duration: keyframes and events beyond the span", function()
			local def = baseDef()
			local core = component(def, "core") -- span 1.2 s
			table.insert(core.tracks[1].keyframes, { time = 1.5, value = 2 })
			table.insert(core.tracks[1].keyframes, { time = 1.8, value = 3 })
			local result = V(def)
			local d =
				expectDiag(result, "warning", "lint.outside_duration", "components[5].tracks[1].keyframes[3].time")
			T.expect(d.message).toMatch("^2 keyframe")
			T.expect(count(result, "lint.outside_duration")).toBe(1)
			-- events at or after the span end are dropped by the schedule
			def = baseDef()
			component(def, "flash").events = nil
			component(def, "sparks").startTime = 1.5 -- span 0.5 s, event at 0.25 is fine
			T.expect(find(V(def), "lint.outside_duration")).toBeNil()
			component(def, "sparks").events[1].time = 0.5
			expectDiag(V(def), "warning", "lint.outside_duration", "components[3].events[1].time")
			-- a key exactly at the end is fine
			def = baseDef()
			T.expect(find(V(def), "lint.outside_duration")).toBeNil()
		end)

		T.it("lint.flash_short: span shorter than the envelope", function()
			local def = baseDef()
			local flash = component(def, "flash")
			flash.duration = 0.2 -- < 0.03 + 0.02 + 0.25
			local d = expectDiag(V(def), "warning", "lint.flash_short", "components[6]")
			T.expect(d.message).toMatch("0.3 s")
			flash.properties = { decay = 0.1 }
			T.expect(find(V(def), "lint.flash_short")).toBeNil()
			-- the effect end clamps the span too
			flash.properties = nil
			flash.duration = nil
			flash.startTime = 1.9
			expectDiag(V(def), "warning", "lint.flash_short")
		end)

		T.it("lint.filemesh_no_id: FileMesh without meshId", function()
			local def = baseDef()
			local mesh = component(def, "mesh")
			mesh.properties.meshType = "FileMesh"
			expectDiag(V(def), "warning", "lint.filemesh_no_id", "components[7].properties.meshId")
			mesh.properties.meshId = "rbxassetid://1234"
			T.expect(find(V(def), "lint.filemesh_no_id")).toBeNil()
		end)

		T.it("lints never produce errors", function()
			local def = baseDef()
			component(def, "root").properties.spin = nil
			component(def, "beam").properties.width0 = 0
			component(def, "flash").duration = 0.1
			component(def, "mesh").properties.meshType = "FileMesh"
			local result = V(def)
			T.expect(result.ok).toBe(true)
			T.expect(#result.warnings).toBe(4)
		end)
	end)

	-- ── Code table ───────────────────────────────────────────────────────────────────────────────────────

	T.describe("Validation.CODES", function()
		T.it("lists unique codes with severities and summaries", function()
			local seen = {}
			for _, entry in Validation.CODES do
				T.expect(seen[entry.code]).toBeNil()
				seen[entry.code] = true
				T.expect(entry.severity == "error" or entry.severity == "warning" or entry.severity == "info")
					.toBe(true)
				T.expect(#entry.summary).toBeGreaterThan(0)
			end
		end)

		T.it("documents every code the tests produced", function()
			local documented = {}
			for _, entry in Validation.CODES do
				documented[entry.code] = true
			end
			local missing = {}
			for c in pairs(emitted) do
				if not documented[c] and string.sub(c, 1, 6) ~= "graph." then
					table.insert(missing, c)
				end
			end
			table.sort(missing)
			T.expect(missing).toEqual({})
			-- and the tests above produced nearly every documented code
			local unseen = {}
			for c in pairs(documented) do
				if not emitted[c] and c ~= "graph.*" then
					table.insert(unseen, c)
				end
			end
			table.sort(unseen)
			T.expect(unseen).toEqual({})
		end)
	end)
end
