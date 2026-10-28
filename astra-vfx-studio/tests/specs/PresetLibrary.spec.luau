--!strict
--[[
	Authoring/PresetLibrary (docs/MODULE_CONTRACTS.md §20): presets are StringValues with raw JSON text (Rojo
	syncRules "text" for src/Presets/*.vfx.json). Most tests use a folder built here; the last ones check the real
	Presets folder of the plugin tree, whatever presets it contains.
]]
return function(T: any, use: (string) -> any, ctx: any)
	local PresetLibrary = use("Authoring.PresetLibrary")
	local Exporter = use("Authoring.Exporter")
	local Json = use("AstraVFX.Core.Json")
	local expect = T.expect

	local isLune = ctx.environment == "lune"

	local function R(...: any): { any }
		return { ... }
	end

	local function def(id: string, name: string, extra: { [string]: any }?): any
		local d: { [string]: any } = {
			schemaVersion = 1,
			id = id,
			name = name,
			description = "Preset " .. name,
			tags = { "test", id },
			duration = 1,
			components = R({ id = "core", name = "Core", type = "part", properties = { size = { 1, 1, 1 } } }),
		}
		local more: { [string]: any } = extra or {}
		for k, v in more do
			d[k] = v
		end
		return d
	end

	local folders: { Instance } = {}
	T.afterEach(function()
		for _, f in folders do
			f:Destroy()
		end
		table.clear(folders)
		PresetLibrary.clearCache()
	end)

	-- A folder of StringValues ({ [instanceName] = text }) plus some children that are not presets.
	local function folderWith(values: { [string]: string }): Folder
		local folder = Instance.new("Folder")
		folder.Name = "TestPresets"
		local names: { string } = {}
		for name in values do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local sv = Instance.new("StringValue")
			sv.Name = name
			sv.Value = values[name]
			sv.Parent = folder
		end
		local module = Instance.new("ModuleScript")
		module.Name = "NotAPreset"
		module.Source = "return {}"
		module.Parent = folder
		local sub = Instance.new("Folder")
		sub.Name = "Nested"
		local nested = Instance.new("StringValue")
		nested.Name = "Deep"
		nested.Value = Exporter.toJson(def("deep", "Deep"))
		nested.Parent = sub
		sub.Parent = folder
		local number = Instance.new("NumberValue")
		number.Name = "Number"
		number.Parent = folder
		table.insert(folders, folder)
		return folder
	end

	local function standard(): Folder
		local bad = def("bad", "Bad Duration")
		bad.duration = -1
		return folderWith({
			ZetaBlast = Exporter.toJson(def("zeta", "Zeta Blast")),
			AlphaWave = Exporter.toJson(def("alpha", "alpha wave")),
			Broken = '{ "schemaVersion": 1, "id": ',
			BadDuration = Exporter.toJson(bad),
			Legacy = Json.encode({
				name = "Legacy Orb",
				duration = 1,
				components = R({
					type = "sphere",
					name = "core",
					properties = { color = { 150, 65, 255 }, initialScale = 1, finalScale = 4 },
				}),
			}),
		})
	end

	local function names(list: { any }): { string }
		local out: { string } = {}
		for _, p in list do
			table.insert(out, p.name)
		end
		return out
	end

	local function byName(list: { any }, name: string): any
		for _, p in list do
			if p.name == name then
				return p
			end
		end
		return nil
	end

	local function codes(list: { any }): { string }
		local out: { string } = {}
		for _, d in list do
			table.insert(out, d.code)
		end
		return out
	end

	T.describe("PresetLibrary.list", function()
		T.it("lists the StringValue children sorted by name and ignores everything else", function()
			local list = PresetLibrary.list(standard())
			expect(names(list)).toEqual({ "alpha wave", "Bad Duration", "Broken", "Legacy Orb", "Zeta Blast" })
			local zeta = byName(list, "Zeta Blast")
			expect(zeta.id).toBe("zeta")
			expect(zeta.source).toBe("ZetaBlast")
			expect(zeta.description).toBe("Preset Zeta Blast")
			expect(zeta.tags).toEqual({ "test", "zeta" })
			expect(zeta.valid).toBe(true)
			expect(zeta.diagnostics).toEqual({})
			expect(zeta.definition).toEqual(def("zeta", "Zeta Blast"))
		end)

		T.it("reports broken JSON and invalid definitions instead of raising", function()
			local list = PresetLibrary.list(standard())
			local broken = byName(list, "Broken")
			expect(broken.valid).toBe(false)
			expect(broken.definition).toBeNil()
			expect(broken.id).toBe("")
			expect(broken.source).toBe("Broken")
			expect(broken.tags).toEqual({})
			expect(codes(broken.diagnostics)).toEqual({ "migration.json" })
			expect(broken.diagnostics[1].message).toContain("line 1, column")
			local bad = byName(list, "Bad Duration")
			expect(bad.valid).toBe(false)
			expect(bad.definition).never.toBeNil()
			expect(bad.id).toBe("bad")
			expect(codes(bad.diagnostics)).toContain("effect.duration")
		end)

		T.it("migrates legacy presets (diagnostics keep the migration notes)", function()
			local legacy = byName(PresetLibrary.list(standard()), "Legacy Orb")
			expect(legacy.valid).toBe(true)
			expect(legacy.id).toBe("legacy-orb")
			expect(legacy.definition.schemaVersion).toBe(1)
			expect(legacy.definition.components[1].properties).toEqual({ coreColor = "#9641FF", shellColor = "#9641FF" })
			local found = codes(legacy.diagnostics)
			expect(found).toContain("migration.missing_version")
			expect(found).toContain("migration.step")
			for _, d in legacy.diagnostics do
				expect(d.severity).never.toBe("error")
			end
		end)

		T.it("returns fresh tables on every call", function()
			local folder = standard()
			local first = PresetLibrary.list(folder)
			local zeta = byName(first, "Zeta Blast")
			zeta.definition.name = "Changed"
			table.insert(zeta.tags, "x")
			table.insert(byName(first, "Broken").diagnostics, { code = "planted" })
			local second = PresetLibrary.list(folder)
			expect(byName(second, "Zeta Blast").definition.name).toBe("Zeta Blast")
			expect(byName(second, "Zeta Blast").tags).toEqual({ "test", "zeta" })
			expect(codes(byName(second, "Broken").diagnostics)).toEqual({ "migration.json" })
		end)

		T.it("follows text changes of a StringValue (live sync)", function()
			local folder = standard()
			expect(byName(PresetLibrary.list(folder), "Zeta Blast")).never.toBeNil()
			local sv = folder:FindFirstChild("ZetaBlast") :: StringValue
			sv.Value = Exporter.toJson(def("zeta", "Zeta Storm"))
			local list = PresetLibrary.list(folder)
			expect(byName(list, "Zeta Blast")).toBeNil()
			expect(byName(list, "Zeta Storm").id).toBe("zeta")
			sv:Destroy()
			expect(#PresetLibrary.list(folder)).toBe(4)
		end)

		T.it("sorts deterministically and flags duplicate ids", function()
			local folder = folderWith({
				B = Exporter.toJson(def("same", "Same")),
				A = Exporter.toJson(def("same", "Same")),
				C = Exporter.toJson(def("other", "same")),
			})
			local list = PresetLibrary.list(folder)
			local order: { string } = {}
			for _, p in list do
				table.insert(order, p.name .. "/" .. p.id .. "/" .. p.source)
			end
			-- case-insensitive name first, then byte-wise name ("Same" < "same"), then id, then source
			expect(order).toEqual({ "Same/same/A", "Same/same/B", "same/other/C" })
			expect(list[1].diagnostics).toEqual({})
			expect(list[2].valid).toBe(true)
			expect(codes(list[2].diagnostics)).toEqual({ "preset.duplicate_id" })
			expect(list[2].diagnostics[1].severity).toBe("warning")
			expect(list[2].diagnostics[1].message).toContain('"A"')
			expect(PresetLibrary.get("same", folder)).toEqual(def("same", "Same"))
		end)

		T.it("returns an empty list for an empty folder and rejects non-instances", function()
			local folder = Instance.new("Folder")
			table.insert(folders, folder)
			expect(PresetLibrary.list(folder)).toEqual({})
			expect(PresetLibrary.count(folder)).toBe(0)
			expect(function()
				PresetLibrary.list("Presets" :: any)
			end).toThrow("PresetLibrary.list: folder must be an Instance")
		end)
	end)

	T.describe("PresetLibrary.get", function()
		T.it("finds valid presets by id, name or source name, also case-insensitively", function()
			local folder = standard()
			local expected = def("zeta", "Zeta Blast")
			expect(PresetLibrary.get("zeta", folder)).toEqual(expected)
			expect(PresetLibrary.get("Zeta Blast", folder)).toEqual(expected)
			expect(PresetLibrary.get("ZetaBlast", folder)).toEqual(expected)
			expect(PresetLibrary.get("ZETA", folder)).toEqual(expected)
			expect(PresetLibrary.get("zeta blast", folder)).toEqual(expected)
			expect(PresetLibrary.get("Alpha Wave", folder).id).toBe("alpha")
			expect(PresetLibrary.get("legacy-orb", folder).name).toBe("Legacy Orb")
		end)

		T.it("returns nil for missing and invalid presets", function()
			local folder = standard()
			expect(PresetLibrary.get("nope", folder)).toBeNil()
			expect(PresetLibrary.get("Broken", folder)).toBeNil()
			expect(PresetLibrary.get("bad", folder)).toBeNil()
			expect(PresetLibrary.get("", folder)).toBeNil()
			expect(PresetLibrary.get("Deep", folder)).toBeNil() -- nested StringValues are not presets
			expect(function()
				PresetLibrary.get(5 :: any, folder)
			end).toThrow("PresetLibrary.get: nameOrId must be a string")
		end)

		T.it("prefers an exact id over another preset's name", function()
			local folder = folderWith({
				First = Exporter.toJson(def("first", "second")),
				Second = Exporter.toJson(def("second", "Second Preset")),
			})
			expect(PresetLibrary.get("second", folder).name).toBe("Second Preset")
			expect(PresetLibrary.get("Second", folder).name).toBe("Second Preset") -- exact source name
		end)

		T.it("returns a deep copy the caller may edit (Json sentinels kept)", function()
			local text = Exporter.toJson(def("zeta", "Zeta Blast"))
			text = string.gsub(text, '"properties": {[^}]*}', '"properties": {}') :: string
			local folder = folderWith({ ZetaBlast = text })
			local a = PresetLibrary.get("zeta", folder)
			expect(a.components[1].properties).toBe(Json.EMPTY_OBJECT)
			a.name = "Edited"
			a.components[1].name = "Edited"
			local b = PresetLibrary.get("zeta", folder)
			expect(b.name).toBe("Zeta Blast")
			expect(b.components[1].name).toBe("Core")
			expect(a).never.toBe(b)
		end)
	end)

	T.describe("PresetLibrary.parse", function()
		T.it("parses one preset from text without a folder", function()
			local info = PresetLibrary.parse(Exporter.toJson(def("solo", "Solo")), "Solo")
			expect(info.valid).toBe(true)
			expect(info.name).toBe("Solo")
			expect(info.source).toBe("Solo")
			expect(PresetLibrary.parse("42").valid).toBe(false)
			expect(PresetLibrary.parse("42").name).toBe("")
			expect(codes(PresetLibrary.parse("42").diagnostics)).toEqual({ "migration.invalid" })
			expect(function()
				PresetLibrary.parse(nil :: any)
			end).toThrow("PresetLibrary.parse: text must be a string")
		end)
	end)

	T.describe("PresetLibrary (plugin Presets folder)", function()
		T.itIf(isLune, "uses the Presets folder next to Authoring", function()
			local folder = PresetLibrary.folder()
			expect(folder).toBe(ctx.loader:resolve("Presets"))
		end)

		T.it("lists every preset of the default folder with well-formed entries", function()
			local folder = PresetLibrary.folder()
			local list = PresetLibrary.list()
			expect(#list).toBe(PresetLibrary.count())
			if folder == nil then
				expect(#list).toBe(0)
				return
			end
			local stringValues = 0
			for _, child in folder:GetChildren() do
				if child:IsA("StringValue") then
					stringValues += 1
				end
			end
			expect(#list).toBe(stringValues)
			for _, preset in list do
				expect(type(preset.name)).toBe("string")
				expect(type(preset.id)).toBe("string")
				expect(type(preset.tags)).toBe("table")
				expect(type(preset.valid)).toBe("boolean")
				expect(type(preset.diagnostics)).toBe("table")
				expect(type(preset.source)).toBe("string")
				if preset.valid then
					expect(PresetLibrary.get(preset.source)).toEqual(preset.definition)
				end
			end
		end)
	end)
end
