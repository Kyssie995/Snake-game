--!strict
--[[
	Authoring/Exporter (docs/MODULE_CONTRACTS.md §20): canonical JSON, generated Luau modules (loaded back through a
	real ModuleScript and the Lune loader), runtime packages (the packaged AstraVFX clone is required through
	ctx.loader and plays an exported effect by name) and static models (compared instance by instance with a
	Player seeked to the same time).
]]
return function(T: any, use: (string) -> any, ctx: any)
	local Exporter = use("Authoring.Exporter")
	local AstraVFX = use("AstraVFX")
	local Constants = use("AstraVFX.Core.Constants")
	local Json = use("AstraVFX.Core.Json")
	local Scheduler = use("AstraVFX.Core.Scheduler")
	local Validation = use("AstraVFX.Core.Validation")
	local Fixtures = use("Tests.Specs.Helpers.EffectFixtures")
	local HarnessModule = use("Tests.Specs.Helpers.PlaybackHarness")
	local expect = T.expect

	local isLune = ctx.environment == "lune"
	local DT = 1 / 60

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end

	local function deepCopy(v: any): any
		if type(v) ~= "table" or getmetatable(v) ~= nil then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function errorOf(fn: (...any) -> ...any, ...: any): string
		local ok, err = pcall(fn, ...)
		if ok then
			return "(no error)"
		end
		return tostring(err)
	end

	local function tinyDef(): any
		return {
			schemaVersion = 1,
			id = "tiny",
			name = "Tiny",
			duration = 1,
			components = R({
				id = "core",
				name = "Core",
				type = "part",
				properties = { size = { 1, 2, 3 } },
			}),
		}
	end

	local function sparkDef(): any
		return {
			schemaVersion = 1,
			id = "export-spark",
			name = "Spark Burst",
			description = "Kleiner Funkenstoß",
			tags = { "test", "sparks" },
			duration = 1,
			seed = 7,
			palette = { primary = "#FF8800" },
			markers = R({ id = "hit", time = 0.2, label = "Hit", phase = "impact", event = "Hit" }),
			components = R({
				id = "core",
				name = "Core",
				type = "part",
				phase = "impact",
				transform = { position = { 0, 1, 0 } },
				properties = { shape = "Ball", size = { 1, 1, 1 }, color = "$primary", transparency = 0.2 },
				tracks = R({
					id = "grow",
					channel = "size",
					keyframes = R(
						{ time = 0, value = { 1, 1, 1 }, easing = "Quad.Out" },
						{ time = 0.5, value = { 3, 3, 3 } }
					),
				}),
			}, {
				id = "sparks",
				name = "Sparks",
				type = "particles",
				properties = { rate = 20, burst = 12, lifetime = { 0.2, 0.4 } },
				events = R({ id = "pop", time = 0.3, action = "emit", count = 8 }),
			}, {
				id = "glow",
				name = "Glow",
				type = "light",
				duration = 0.8,
				properties = { color = "$primary", brightness = 4, range = 12 },
			}, {
				id = "fancy",
				name = "Fancy Ring",
				type = "ring",
				minQuality = "Medium",
				properties = { radius = 3, segments = 12 },
			}),
		}
	end

	local function fullDef(): any
		return Fixtures.full(Json)
	end

	local function load(source: string): any
		local module = Instance.new("ModuleScript")
		module.Name = "Generated"
		module.Source = source
		return ctx.loader:require(module)
	end

	T.describe("Exporter.toJson", function()
		T.it("writes canonical pretty JSON with a trailing newline", function()
			local text = Exporter.toJson(tinyDef())
			expect(text).toBe(table.concat({
				"{",
				'  "schemaVersion": 1,',
				'  "id": "tiny",',
				'  "name": "Tiny",',
				'  "duration": 1,',
				'  "components": [',
				"    {",
				'      "id": "core",',
				'      "name": "Core",',
				'      "type": "part",',
				'      "properties": {',
				'        "size": [1, 2, 3]',
				"      }",
				"    }",
				"  ]",
				"}",
				"",
			}, "\n"))
			expect(text).toBe(Json.encode(tinyDef()) .. "\n")
		end)

		T.it("is byte-identical for equal inputs, whatever the construction order", function()
			local a = sparkDef()
			-- the same document built field by field in reverse order
			local b: any = {}
			local keys: { string } = {}
			for key in a do
				table.insert(keys, key)
			end
			table.sort(keys, function(x: string, y: string): boolean
				return x > y
			end)
			for _, key in keys do
				b[key] = deepCopy(a[key])
			end
			local props: any = {}
			props.transparency = 0.2
			props.color = "$primary"
			props.size = { 1, 1, 1 }
			props.shape = "Ball"
			b.components[1].properties = props
			expect(Exporter.toJson(b)).toBe(Exporter.toJson(a))
			expect(Exporter.toJson(a)).toBe(Exporter.toJson(sparkDef()))
		end)

		T.it("drops empty optional containers but keeps components and properties", function()
			local def: any = {
				schemaVersion = 1,
				id = "empty",
				name = "Empty",
				duration = 1,
				tags = {},
				palette = Json.EMPTY_OBJECT,
				markers = {},
				graph = { nodes = {}, links = {} },
				quality = { Low = {}, High = Json.EMPTY_OBJECT },
				metadata = {},
				components = R({
					id = "a",
					name = "A",
					type = "group",
					transform = {},
					properties = {},
					tracks = {},
					events = {},
					qualityOverrides = { High = {} },
				}, {
					id = "b",
					name = "B",
					type = "group",
					properties = Json.EMPTY_OBJECT,
				}, {
					id = "c",
					name = "C",
					type = "group",
				}),
			}
			local ok, decoded = Json.decode(Exporter.toJson(def))
			expect(ok).toBe(true)
			expect(decoded.tags).toBeNil()
			expect(decoded.palette).toBeNil()
			expect(decoded.markers).toBeNil()
			expect(decoded.graph).toBeNil()
			expect(decoded.quality).toBeNil()
			expect(decoded.metadata).toBeNil()
			local a = decoded.components[1]
			expect(a.transform).toBeNil()
			expect(a.tracks).toBeNil()
			expect(a.events).toBeNil()
			expect(a.qualityOverrides).toBeNil()
			expect(a.properties).toBe(Json.EMPTY_OBJECT) -- written as {}
			expect(decoded.components[2].properties).toBe(Json.EMPTY_OBJECT)
			expect(decoded.components[3].properties).toBeNil() -- not added
			expect(Exporter.toJson(def)).toContain('"properties": {}')
			-- an empty component list stays (as [])
			local none = tinyDef()
			none.components = Json.EMPTY_OBJECT
			expect(Exporter.toJson(none)).toContain('"components": []')
			-- partially empty levels: only the empty level goes
			def.quality = { Low = { countScale = 0.5 }, High = {} }
			local _, again = Json.decode(Exporter.toJson(def))
			expect(again.quality).toEqual({ Low = { countScale = 0.5 } })
		end)

		T.it("leaves required containers, values and unknown fields untouched", function()
			local def: any = tinyDef()
			def.components[1].tracks = R({ id = "t", channel = "size", keyframes = {} })
			def.graph = { nodes = R({ id = "play", type = "OnPlay", params = {} }), links = {} }
			def.metadata = { list = {}, nested = { inner = {} } }
			def.extra = {}
			local text = Exporter.toJson(def)
			local _, decoded = Json.decode(text)
			expect(decoded.components[1].tracks[1].keyframes).toEqual({})
			expect(text).toContain('"keyframes": []')
			expect(decoded.graph.nodes[1].params).toBeNil() -- optional params dropped
			expect(decoded.graph.nodes[1].id).toBe("play")
			expect(text).toContain('"links": []') -- required with nodes
			expect(text).toContain('"list": []')
			expect(text).toContain('"inner": []')
			expect(text).toContain('"extra": []')
		end)

		T.it("never mutates the input", function()
			local def: any = fullDef()
			def.tags = {}
			def.components[1].events = {}
			local before = deepCopy(def)
			Exporter.toJson(def)
			Exporter.toLuau(def)
			Exporter.prune(def)
			expect(def).toEqual(before)
			expect(def.tags).toEqual({})
			expect(def.components[1].events).toEqual({})
		end)

		T.it("round-trips and is idempotent (fixture with every component type)", function()
			local def = fullDef()
			local text = Exporter.toJson(def)
			local ok, decoded = Json.decode(text)
			expect(ok).toBe(true)
			expect(decoded).toEqual(def)
			expect(Exporter.toJson(decoded)).toBe(text)
			local result = Validation.validate(decoded)
			expect(result.errors).toEqual({})
		end)

		T.itIf(isLune and type(ctx.readFile) == "function", "reproduces the stored canonical effect file", function()
			local text = ctx.readFile("effects/VioletImpact.vfx.json")
			local ok, decoded = Json.decode(text)
			expect(ok).toBe(true)
			expect(Exporter.toJson(decoded)).toBe(text)
		end)

		T.it("raises with the path of values that are not JSON", function()
			local def = tinyDef()
			def.components[1].properties.size = { 0 / 0, 1, 1 }
			local err = errorOf(Exporter.toJson, def)
			expect(err).toContain("Exporter.toJson")
			expect(err).toContain("components[1].properties.size[1]")
			expect(errorOf(Exporter.toJson, "nope")).toContain("expected an effect definition table")
			expect(errorOf(Exporter.toJson, Json.NULL)).toContain("expected an effect definition table")
		end)
	end)

	T.describe("Exporter.toLuau", function()
		T.it("writes the header and a canonical table literal", function()
			local source = Exporter.toLuau(tinyDef())
			expect(Exporter.HEADER).toBe(
				"-- Generated by ASTRA VFX Studio "
					.. Constants.VERSION
					.. ". Do not edit by hand; edit the effect and re-export.\n"
			)
			expect(source).toBe(Exporter.HEADER .. table.concat({
				"return {",
				"\tschemaVersion = 1,",
				'\tid = "tiny",',
				'\tname = "Tiny",',
				"\tduration = 1,",
				"\tcomponents = {",
				"\t\t{",
				'\t\t\tid = "core",',
				'\t\t\tname = "Core",',
				'\t\t\ttype = "part",',
				"\t\t\tproperties = {",
				"\t\t\t\tsize = { 1, 2, 3 },",
				"\t\t\t},",
				"\t\t},",
				"\t},",
				"}",
				"",
			}, "\n"))
		end)

		T.itIf(isLune, "loads through a ModuleScript and ctx.loader into a deep-equal table", function()
			for _, def in { fullDef(), sparkDef(), tinyDef() } do
				local value = load(Exporter.toLuau(def))
				expect(value).toEqual(def)
				expect(value).toEqual(Exporter.prune(def))
				expect(Validation.validate(value).errors).toEqual({})
				-- and back: the loaded table exports to the same text
				expect(Exporter.toLuau(value)).toBe(Exporter.toLuau(def))
				expect(Exporter.toJson(value)).toBe(Exporter.toJson(def))
			end
		end)

		T.it("uses bare identifier keys and brackets everything else", function()
			local def = tinyDef()
			def.palette = { primary = "#FF0000", ["my-key"] = "#00FF00", ["end"] = "#0000FF", ["2x"] = "#FFFFFF" }
			def.metadata = { ["with space"] = 1, ["and"] = true, ["continue"] = false, _private = "x", type = "ok" }
			local source = Exporter.toLuau(def)
			expect(source).toContain('\t\tprimary = "#FF0000",')
			expect(source).toContain('\t\t["my-key"] = "#00FF00",')
			expect(source).toContain('\t\t["end"] = "#0000FF",')
			expect(source).toContain('\t\t["2x"] = "#FFFFFF",')
			expect(source).toContain('\t\t["with space"] = 1,')
			expect(source).toContain('\t\t["and"] = true,')
			expect(source).toContain('\t\t["continue"] = false,')
			expect(source).toContain('\t\t_private = "x",')
			expect(source).toContain('\t\ttype = "ok",')
			if isLune then
				expect(load(source)).toEqual(def)
			end
		end)

		T.it("follows Core/Json's key order (KEY_ORDER first, then byte-wise)", function()
			local def = tinyDef()
			def.metadata = { b = 1, a = 2, B = 3, notes = 4, id = 5 }
			local source = Exporter.toLuau(def)
			local i = function(s: string): number
				return (string.find(source, s, 1, true)) :: number
			end
			-- inside metadata: id (ranked), notes (ranked), then B, a, b
			expect(i("\t\tid = 5") < i("\t\tnotes = 4")).toBe(true)
			expect(i("\t\tnotes = 4") < i("\t\tB = 3")).toBe(true)
			expect(i("\t\tB = 3") < i("\t\ta = 2")).toBe(true)
			expect(i("\t\ta = 2") < i("\t\tb = 1")).toBe(true)
			-- effect level: components before metadata (KEY_ORDER)
			expect(i("\tcomponents = {") < i("\tmetadata = {")).toBe(true)
		end)

		T.it("escapes strings so the source holds no raw control characters", function()
			local def = tinyDef()
			local nasty = 'quote " backslash \\ newline \n tab \t cr \r nul \0 one \1 del \127 umlaut äöü 日本 \\n'
			def.components[1].notes = nasty
			def.description = "digits after escapes: \0001 \0012"
			local source = Exporter.toLuau(def)
			-- only indentation tabs and line breaks are raw control characters
			expect(string.find(source, "[%z\1-\8\11-\31\127]")).toBeNil()
			for line in string.gmatch(source, "[^\n]+") do
				expect(string.find(line, "^\t*[^\t]*$")).never.toBeNil()
			end
			expect(source).toContain('quote \\" backslash \\\\ newline \\n tab \\t cr \\r nul \\000 one \\001')
			expect(source).toContain("del \\127 umlaut äöü 日本 \\\\n")
			if isLune then
				local value = load(source)
				expect(value.components[1].notes).toBe(nasty)
				expect(value.description).toBe(def.description)
			end
		end)

		T.it("prints numbers exactly like Core/Json", function()
			local def = tinyDef()
			local values = { 0.1, -2.5, 1e-7, 1 / 3, -0, 123456789, 2 ^ 53, -1e21, 0.0000005, 2.9999999 }
			def.metadata = { numbers = values }
			local source = Exporter.toLuau(def)
			local texts: { string } = {}
			for _, v in values do
				table.insert(texts, Json.encode(v))
			end
			expect(source).toContain("\t\tnumbers = {\n\t\t\t" .. table.concat(texts, ",\n\t\t\t") .. ",\n\t\t},")
			expect(source).toContain("0.333333")
			if isLune then
				local loaded = load(source).metadata.numbers
				for i, v in values do
					expect(loaded[i]).toBe(tonumber(Json.encode(v)))
				end
			end
		end)

		T.it("writes short scalar arrays inline and nested arrays one element per line", function()
			local def = tinyDef()
			def.components[1].properties.transparency = R(R(0, 1), R(0.5, 0.25, 0.1), R(1, 0))
			def.tags = { "a", "b" }
			def.metadata = { long = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }, mixed = R("x", true, 3) }
			local source = Exporter.toLuau(def)
			expect(source).toContain(
				"\t\t\t\ttransparency = {\n\t\t\t\t\t{ 0, 1 },\n\t\t\t\t\t{ 0.5, 0.25, 0.1 },\n\t\t\t\t\t{ 1, 0 },\n\t\t\t\t},"
			)
			expect(source).toContain('\ttags = { "a", "b" },')
			expect(source).toContain('\t\tmixed = { "x", true, 3 },')
			expect(source).toContain("\t\tlong = {\n\t\t\t1,\n\t\t\t2,")
		end)

		T.it("prunes like toJson and writes empty objects as {}", function()
			local def = tinyDef()
			def.tags = {}
			def.components[1].properties = Json.EMPTY_OBJECT
			def.components[1].tracks = {}
			local source = Exporter.toLuau(def)
			expect(source).never.toContain("tags")
			expect(source).never.toContain("tracks")
			expect(source).toContain("\t\t\tproperties = {},")
		end)

		T.it("is reproducible for equal inputs", function()
			local a = Exporter.toLuau(sparkDef())
			local b = Exporter.toLuau(sparkDef())
			expect(a).toBe(b)
			local def = sparkDef()
			local reordered: any = {}
			local keys: { string } = {}
			for key in def do
				table.insert(keys, key)
			end
			table.sort(keys, function(x: string, y: string): boolean
				return x > y
			end)
			for _, key in keys do
				reordered[key] = def[key]
			end
			expect(Exporter.toLuau(reordered)).toBe(a)
		end)

		T.it("raises with a path on values a Luau table cannot hold", function()
			local function with(value: any): string
				local def = tinyDef()
				def.metadata = { bad = R(1, value) }
				return errorOf(Exporter.toLuau, def)
			end
			local nullError = with(Json.NULL)
			expect(nullError).toContain("Exporter.toLuau: null")
			expect(nullError).toContain("metadata.bad[2]")
			expect(with(0 / 0)).toContain("non-finite")
			expect(with(math.huge)).toContain("non-finite")
			expect(with(print)).toContain("type function")
			expect(with(Vector3.new(1, 2, 3))).toContain("type Vector3")
			local mixed: any = { 1 }
			mixed.x = 2
			expect(with(mixed)).toContain("mixed table")
			expect(with({ [1] = 1, [3] = 3 })).toContain("sparse array")
			expect(with({ [true] = 1 })).toContain("invalid table key")
			expect(with("\255\254")).toContain("not valid UTF-8")
			local cyclic: any = {}
			cyclic.self = cyclic
			expect(with(cyclic)).toContain("cyclic")
			local deep: any = {}
			local node = deep
			for _ = 1, Json.MAX_DEPTH + 5 do
				node.next = {}
				node = node.next
			end
			expect(with(deep)).toContain("nesting deeper than")
			expect(errorOf(Exporter.toLuau, 42)).toContain("expected an effect definition table")
		end)
	end)

	T.describe("Exporter.buildRuntimePackage", function()
		local function runtime(): any
			return ctx.loader:resolve("AstraVFX")
		end

		local function childNames(inst: Instance): { string }
			local out: { string } = {}
			for _, child in inst:GetChildren() do
				table.insert(out, child.Name)
			end
			return out
		end

		local function describeTree(inst: Instance): { any }
			local out: { any } = {}
			for _, d in inst:GetDescendants() do
				local entry: { any } = { d:GetFullName(), d.ClassName, d:GetAttributes() }
				if d:IsA("ModuleScript") then
					table.insert(entry, (d :: ModuleScript).Source)
				end
				table.insert(out, entry)
			end
			return out
		end

		local function secondDef(): any
			return {
				schemaVersion = 1,
				id = "export-alpha",
				name = "Alpha Glow",
				duration = 0.5,
				components = R({ id = "glow", name = "Glow", type = "light", properties = { brightness = 2 } }),
			}
		end

		T.itIf(isLune, "clones the runtime and adds one generated ModuleScript per definition", function()
			local source = runtime()
			local before = childNames(source)
			local package = Exporter.buildRuntimePackage(source, { sparkDef(), secondDef() })
			expect(package).never.toBe(source)
			expect(package.ClassName).toBe("ModuleScript")
			expect(package.Name).toBe(source.Name)
			expect(package.Parent).toBeNil()
			expect(package.Source).toBe(source.Source)
			expect(package:FindFirstChild("Core")).never.toBeNil()
			expect(package:FindFirstChild("Net")).never.toBeNil()
			expect(package:GetAttribute("AstraVersion")).toBe(Constants.VERSION)
			expect(package:GetAttribute("AstraExportedAt")).toBeNil()
			local effects = package:FindFirstChild("Effects") :: Instance
			expect(effects.ClassName).toBe("Folder")
			-- sorted by name
			expect(childNames(effects)).toEqual({ "Alpha Glow", "Spark Burst" })
			local spark = effects:FindFirstChild("Spark Burst") :: ModuleScript
			expect(spark.ClassName).toBe("ModuleScript")
			expect(spark.Source).toBe(Exporter.toLuau(sparkDef()))
			expect(spark:GetAttribute("AstraId")).toBe("export-spark")
			expect(spark:GetAttribute("AstraSchemaVersion")).toBe(1)
			-- the source module is untouched
			expect(childNames(source)).toEqual(before)
			expect(source:FindFirstChild("Effects")).toBeNil()
			expect(source:GetAttribute("AstraVersion")).toBeNil()
			package:Destroy()
		end)

		T.itIf(isLune, "a required package plays an exported effect by name", function()
			local package = Exporter.buildRuntimePackage(runtime(), { sparkDef(), secondDef() })
			local api = ctx.loader:require(package)
			expect(api).never.toBe(AstraVFX)
			expect(type(api.Play)).toBe("function")
			local baseline = ctx.fakes.heartbeat:connectionCount()
			local emitMark = #ctx.fakes.emits
			local folder = Instance.new("Folder")
			folder.Name = "ExportPlayground"
			local ok, err = pcall(function()
				expect(api.IsRegistered("Spark Burst")).toBe(true)
				expect(api.IsRegistered("export-alpha")).toBe(true)
				expect(api.GetNames()).toEqual({ "Alpha Glow", "Spark Burst" })
				expect(AstraVFX.IsRegistered("export-spark")).toBe(false) -- the plugin's runtime is separate
				local events: { string } = {}
				local handle = api.Play("Spark Burst", {
					Parent = folder,
					Quality = "High",
					OnEvent = function(name: string)
						table.insert(events, name)
					end,
				})
				local container = handle._player.built.container
				expect(container.Parent).toBe(folder)
				expect(#folder:GetChildren()).toBe(1)
				local finished: string? = nil
				handle.Finished:Connect(function(reason: string)
					finished = reason
				end)
				for _ = 1, 240 do
					ctx.fakes:step(DT)
					if finished then
						break
					end
				end
				expect(finished).toBe("finished")
				expect(events).toEqual({ "Hit" })
				-- only this effect played: every emit since the mark is its emitter's
				local counts: { number } = {}
				for i = emitMark + 1, #ctx.fakes.emits do
					local e = ctx.fakes.emits[i]
					expect(e.instance.Name).toBe("Sparks")
					table.insert(counts, e.count)
				end
				expect(counts).toEqual({ 12, 8 }) -- activation burst, then the emit event at 0.3 s
				expect(#folder:GetChildren()).toBe(0) -- pooled (Parent = nil) after the end
				expect(api.ActiveCount()).toBe(0)
			end)
			api._reset()
			for _ = 1, 3 do
				ctx.fakes:step(DT)
			end
			expect(ctx.fakes.heartbeat:connectionCount()).toBe(baseline)
			while #ctx.fakes.emits > emitMark do
				table.remove(ctx.fakes.emits)
			end
			folder:Destroy()
			package:Destroy()
			if not ok then
				error(err, 0)
			end
		end)

		T.itIf(isLune, "replaces an existing Effects folder and stale Net remotes", function()
			local source = runtime():Clone()
			local old = Instance.new("Folder")
			old.Name = "Effects"
			local stale = Instance.new("ModuleScript")
			stale.Name = "Old"
			stale.Source = "return {}"
			stale.Parent = old
			old.Parent = source
			local net = Instance.new("Folder")
			net.Name = "AstraVFXNet"
			net.Parent = source
			source:SetAttribute("AstraExportedAt", 1700000000)
			local package = Exporter.buildRuntimePackage(source, { secondDef() })
			local effectsFolders = 0
			for _, child in package:GetChildren() do
				if child.Name == "Effects" then
					effectsFolders += 1
				end
			end
			expect(effectsFolders).toBe(1)
			expect(package:FindFirstChild("AstraVFXNet")).toBeNil()
			expect(childNames(package:FindFirstChild("Effects") :: Instance)).toEqual({ "Alpha Glow" })
			expect(package:GetAttribute("AstraExportedAt")).toBeNil()
			-- the source keeps its own folders
			expect(source:FindFirstChild("Effects"):FindFirstChild("Old")).never.toBeNil()
			expect(source:FindFirstChild("AstraVFXNet")).never.toBeNil()
			package:Destroy()
			source:Destroy()
		end)

		T.itIf(isLune, "is reproducible: equal definitions give identical trees in any order", function()
			local a = Exporter.buildRuntimePackage(runtime(), { sparkDef(), secondDef() })
			local b = Exporter.buildRuntimePackage(runtime(), { secondDef(), sparkDef() })
			expect(describeTree(a)).toEqual(describeTree(b))
			a:Destroy()
			b:Destroy()
		end)

		T.itIf(isLune, "exports migrated definitions and rejects invalid ones", function()
			local legacy = {
				name = "Legacy Orb",
				duration = 1,
				components = R({
					type = "sphere",
					name = "core",
					properties = { color = { 150, 65, 255 }, initialScale = 1, finalScale = 4 },
				}),
			}
			local package = Exporter.buildRuntimePackage(runtime(), { legacy })
			local module = (package:FindFirstChild("Effects") :: Instance):FindFirstChild("Legacy Orb") :: ModuleScript
			local value = load(module.Source)
			expect(value.schemaVersion).toBe(1)
			expect(value.id).toBe("legacy-orb")
			expect(value.components[1].properties).toEqual({ coreColor = "#9641FF", shellColor = "#9641FF" })
			expect(module:GetAttribute("AstraId")).toBe("legacy-orb")
			package:Destroy()

			local bad = sparkDef()
			bad.duration = -1
			bad.components[1].type = "laser"
			local err = errorOf(Exporter.buildRuntimePackage, runtime(), { secondDef(), bad })
			expect(err).toContain('Exporter.buildRuntimePackage: effect "Spark Burst" is invalid')
			expect(err).toContain("effect.duration")
			expect(err).toContain("component.type")
			expect(errorOf(Exporter.buildRuntimePackage, runtime(), { "{}" })).toContain(
				"defs[1] must be an effect definition table"
			)
			local twin = secondDef()
			twin.name = "Other"
			expect(errorOf(Exporter.buildRuntimePackage, runtime(), { secondDef(), twin })).toContain(
				'defs[2] has the same id "export-alpha" as defs[1]'
			)
			local namesake = secondDef()
			namesake.id = "export-other"
			expect(errorOf(Exporter.buildRuntimePackage, runtime(), { secondDef(), namesake })).toContain(
				'has the same name "Alpha Glow"'
			)
			expect(errorOf(Exporter.buildRuntimePackage, Instance.new("Folder"), {})).toContain(
				"runtimeModule must be the AstraVFX ModuleScript"
			)
			local stranger = Instance.new("ModuleScript")
			stranger.Name = "Stranger"
			expect(errorOf(Exporter.buildRuntimePackage, stranger, {})).toContain(
				"Stranger is not the AstraVFX runtime (it has no Core)"
			)
			stranger:Destroy()
			expect(errorOf(Exporter.buildRuntimePackage, runtime(), nil)).toContain("defs must be an array")
		end)

		T.itIf(isLune, "an empty definition list gives an empty Effects folder", function()
			local package = Exporter.buildRuntimePackage(runtime(), {})
			expect(#(package:FindFirstChild("Effects") :: Instance):GetChildren()).toBe(0)
			package:Destroy()
		end)
	end)

	T.describe("Exporter.buildStaticModel", function()
		local H: any = nil
		T.beforeEach(function()
			H = HarnessModule.new(use, ctx)
		end)
		T.afterEach(function()
			H:cleanup()
		end)

		-- Reference: the same effect built normally, seeked, held for one paused frame and resumed (the exporter's
		-- sequence, see the Exporter header).
		local function reference(def: any, time: number, compileOptions: any?, playerOptions: any?): any
			local p = H:player(def, compileOptions or { quality = "High" }, playerOptions)
			p.player:seek(time)
			p.player:step(0)
			p.player:resume()
			return p
		end

		local function tagged(model: Instance, id: string): { Instance }
			local out: { Instance } = {}
			for _, d in model:GetDescendants() do
				if d:GetAttribute("AstraComponent") == id then
					table.insert(out, d)
				end
			end
			return out
		end

		T.itIf(isLune, "freezes the effect at a time as a Model with PrimaryPart = Root", function()
			local def = sparkDef()
			local model = Exporter.buildStaticModel(def, { time = 0.25 })
			expect(model.ClassName).toBe("Model")
			expect(model.Name).toBe("Spark Burst")
			expect(model.Parent).toBeNil()
			local root = model:FindFirstChild("Root") :: BasePart
			expect(root).never.toBeNil()
			expect(model.PrimaryPart).toBe(root)
			-- instance by instance the state of a Player seeked to the same time
			local p = reference(def, 0.25)
			expect(H:snapshot(model)).toEqual(H:snapshot(p.built.container))
			-- the size track is evaluated at 0.25 s (Quad.Out from 1 to 3 over 0.5 s: 1 + 2 * 0.75)
			local core: BasePart? = nil
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Core" then
					core = d :: BasePart
				end
			end
			expect(core).never.toBeNil()
			expect((core :: BasePart).Size).toBeCloseTo(Vector3.new(2.5, 2.5, 2.5), 1e-4)
			expect((core :: BasePart).Transparency).toBeCloseTo(0.2, 1e-6)
			expect((core :: BasePart).CFrame.Position).toBeCloseTo(Vector3.new(0, 1, 0), 1e-4)
			-- active at 0.25 s: the emitter emits continuously at its authored clock (not left in the seek state,
			-- not frozen at TimeScale 0 like a paused copy); the light shines
			local emitter = model:FindFirstChildWhichIsA("ParticleEmitter", true) :: ParticleEmitter
			expect(emitter.Enabled).toBe(true)
			expect(emitter.Rate).toBe(20)
			expect(emitter.TimeScale).toBe(1)
			local light = model:FindFirstChildWhichIsA("PointLight", true) :: PointLight
			expect(light.Enabled).toBe(true)
			expect(light.Brightness).toBe(4)
			model:Destroy()
		end)

		T.itIf(isLune, "the exported clocks follow the definition's timeScale", function()
			local def = sparkDef()
			def.timeScale = 0.5
			local model = Exporter.buildStaticModel(def, { time = 0.25 })
			local emitter = model:FindFirstChildWhichIsA("ParticleEmitter", true) :: ParticleEmitter
			expect(emitter.TimeScale).toBe(0.5)
			model:Destroy()
		end)

		T.itIf(isLune, "keeps the moved instances alive and leaves nothing running", function()
			local heartbeat = ctx.fakes.heartbeat:connectionCount()
			local schedulerCount = Scheduler.count()
			local emitMark = H:emitMark()
			local soundMark = #ctx.fakes.sounds
			local model = Exporter.buildStaticModel(fullDef(), { time = 0.6 })
			expect(#H:emitsSince(emitMark)).toBe(0) -- a seek never emits
			expect(#ctx.fakes.sounds).toBe(soundMark)
			expect(ctx.fakes.heartbeat:connectionCount()).toBe(heartbeat)
			expect(Scheduler.count()).toBe(schedulerCount)
			local emitters, beams = 0, 0
			for _, d in model:GetDescendants() do
				expect(d.Parent).never.toBeNil()
				expect(d.Archivable).toBe(true)
				expect(d:GetAttribute("AstraPreview")).toBeNil()
				if d:IsA("ParticleEmitter") then
					emitters += 1
					expect((d :: ParticleEmitter).TimeScale).toBe(1) -- not frozen by the seek
				elseif d:IsA("Beam") then
					beams += 1
					local beam = d :: Beam
					expect(beam.Attachment0).never.toBeNil()
					expect((beam.Attachment0 :: Attachment):IsDescendantOf(model)).toBe(true)
					expect((beam.Attachment1 :: Attachment):IsDescendantOf(model)).toBe(true)
				end
			end
			expect(emitters > 0).toBe(true)
			expect(beams > 0).toBe(true)
			model:Destroy()
		end)

		T.itIf(isLune, "strips runtime attributes and unlocks parts unless asked not to", function()
			local model = Exporter.buildStaticModel(sparkDef(), { time = 0.25 })
			local parts = 0
			for _, d in model:GetDescendants() do
				expect(d:GetAttribute("AstraComponent")).toBeNil()
				expect(d:GetAttribute("AstraEffect")).toBeNil()
				if d:IsA("BasePart") then
					parts += 1
					expect((d :: BasePart).Locked).toBe(false)
				end
			end
			expect(parts >= 2).toBe(true)
			expect(model:GetAttribute("AstraEffectId")).toBe("export-spark")
			expect(model:GetAttribute("AstraTime")).toBe(0.25)
			expect(model:GetAttribute("AstraVersion")).toBe(Constants.VERSION)
			model:Destroy()

			local kept = Exporter.buildStaticModel(sparkDef(), { time = 0.25, stripAttributes = false, unlock = false })
			expect(#tagged(kept, "core") > 0).toBe(true)
			expect(#tagged(kept, "sparks") > 0).toBe(true)
			for _, d in kept:GetDescendants() do
				if d:IsA("BasePart") then
					expect((d :: BasePart).Locked).toBe(true)
				end
			end
			kept:Destroy()
		end)

		T.itIf(isLune, "applies quality, clamps the time and places the root at cframe", function()
			local high = Exporter.buildStaticModel(sparkDef(), { stripAttributes = false })
			expect(#tagged(high, "fancy") > 0).toBe(true)
			expect(high:GetAttribute("AstraTime")).toBe(0)
			local low = Exporter.buildStaticModel(sparkDef(), { quality = "Low", time = 99, stripAttributes = false })
			expect(#tagged(low, "fancy")).toBe(0) -- minQuality Medium
			expect(low:GetAttribute("AstraTime")).toBe(1) -- clamped to the duration
			-- after the end nothing is active: the light is off, the emitter does not emit
			for _, d in low:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					expect((d :: ParticleEmitter).Enabled).toBe(false)
				end
			end
			local cf = CFrame.new(10, 5, -3) * CFrame.Angles(0, math.rad(90), 0)
			local placed = Exporter.buildStaticModel(sparkDef(), { time = 0.25, cframe = cf })
			expect((placed.PrimaryPart :: BasePart).CFrame).toBeCloseTo(cf, 1e-4)
			local p = reference(sparkDef(), 0.25, nil, { cframe = cf })
			expect(H:snapshot(placed)).toEqual(H:snapshot(p.built.container))
			high:Destroy()
			low:Destroy()
			placed:Destroy()
		end)

		T.itIf(isLune, "matches a Low-quality reference build", function()
			local model = Exporter.buildStaticModel(fullDef(), { time = 0.75, quality = "Low" })
			local p = reference(fullDef(), 0.75, { quality = "Low" })
			expect(H:snapshot(model)).toEqual(H:snapshot(p.built.container))
			model:Destroy()
		end)

		T.it("rejects bad options and invalid definitions", function()
			expect(errorOf(Exporter.buildStaticModel, sparkDef(), { quality = "Auto" })).toContain(
				'quality must be "Low", "Medium" or "High"'
			)
			expect(errorOf(Exporter.buildStaticModel, sparkDef(), { time = 0 / 0 })).toContain(
				"time must be a finite number"
			)
			expect(errorOf(Exporter.buildStaticModel, sparkDef(), { scale = 0 })).toContain("scale must be")
			expect(errorOf(Exporter.buildStaticModel, sparkDef(), { cframe = Vector3.zero })).toContain(
				"cframe must be a CFrame"
			)
			local bad = sparkDef()
			bad.components[2].properties.rate = -5
			local err = errorOf(Exporter.buildStaticModel, bad)
			expect(err).toContain('Exporter.buildStaticModel: effect "Spark Burst" is invalid (1 error)')
			expect(err).toContain("property.range components[2].properties.rate")
			expect(errorOf(Exporter.buildStaticModel, "text")).toContain("def must be an effect definition table")
		end)
	end)
end
