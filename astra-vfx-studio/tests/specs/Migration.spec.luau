--!strict
-- Core/Migration: version detection (incl. the brief's mislabelled concept example), the 0 -> 1 step, the step
-- registry, input immutability and rejection of unusable / future documents.
return function(T: any, use: (string) -> any, _ctx: any)
	local Migration = use("AstraVFX.Core.Migration")
	local Validation = use("AstraVFX.Core.Validation")
	local Constants = use("AstraVFX.Core.Constants")
	local Json = use("AstraVFX.Core.Json")

	-- The exact example from the project brief (labelled schemaVersion 1, written in the concept format).
	local BRIEF_EXAMPLE =
		[[{"schemaVersion":1,"name":"VioletImpact","duration":2.5,"components":[{"id":"core","type":"sphere","startTime":0,"duration":1.2,"properties":{"color":[150,65,255],"initialScale":1,"finalScale":8}}]}]]

	-- Builds a mixed-type row (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end

	local function decode(text: string): any
		local ok, value = Json.decode(text)
		assert(ok, value)
		return value
	end

	local function find(diags: { any }, code: string, path: string?): any
		for _, d in diags do
			if d.code == code and (path == nil or d.path == path) then
				return d
			end
		end
		return nil
	end

	local function list(diags: { any }): string
		local out = {}
		for _, d in diags do
			table.insert(out, d.severity .. " " .. d.code .. " @ " .. d.path .. ": " .. d.message)
		end
		return table.concat(out, "\n")
	end

	local function expectDiag(diags: { any }, severity: string, code: string, path: string?): any
		local d = find(diags, code, path)
		if d == nil then
			error("expected " .. code .. " at " .. tostring(path) .. ", got:\n" .. list(diags), 2)
		end
		T.expect(d.severity).toBe(severity)
		return d
	end

	-- Migrated documents must validate without errors (warnings listed in the failure message).
	local function expectValid(def: any)
		local result = Validation.validate(def)
		if not result.ok then
			local lines = {}
			for _, d in result.errors do
				table.insert(lines, d.code .. " @ " .. d.path .. ": " .. d.message)
			end
			error("expected a valid definition, got:\n" .. table.concat(lines, "\n"), 2)
		end
		return result
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

	local function v1(): any
		return {
			schemaVersion = 1,
			id = "fx",
			name = "FX",
			duration = 1,
			palette = Json.EMPTY_OBJECT,
			components = {
				{
					id = "p",
					name = "P",
					type = "particles",
					properties = { color = { 255, 0, 0 }, burst = 5 },
				} :: any,
				{ id = "g", name = "G", type = "group", properties = Json.EMPTY_OBJECT },
			},
		}
	end

	-- ── Basics ───────────────────────────────────────────────────────────────────────────────────────────

	T.describe("Migration basics", function()
		T.it("targets the current schema version", function()
			T.expect(Migration.CURRENT).toBe(Constants.SCHEMA_VERSION)
			T.expect(Migration.CURRENT).toBe(1)
			T.expect(Migration.STEPS[0].from).toBe(0)
			T.expect(Migration.STEPS[0].to).toBe(1)
		end)

		T.it("returns current documents as an equal deep copy without diagnostics", function()
			local raw = v1()
			local def, diags = Migration.migrate(raw)
			T.expect(diags).toEqual({})
			T.expect(def).toEqual(raw)
			T.expect(def).never.toBe(raw)
			T.expect(def.components).never.toBe(raw.components)
			T.expect(def.components[1].properties.color).never.toBe(raw.components[1].properties.color)
			-- sentinels are kept by identity, so the canonical JSON is unchanged
			T.expect(def.palette).toBe(Json.EMPTY_OBJECT)
			T.expect(Json.encode(def)).toBe(Json.encode(raw))
		end)

		T.it("does not treat [r, g, b] on a type with a color property as legacy", function()
			local version, reasons = Migration.detect(v1())
			T.expect(version).toBe(1)
			T.expect(reasons).toEqual({})
		end)

		T.it("never mutates its input (deeply frozen)", function()
			local raw = decode(BRIEF_EXAMPLE)
			local before = Json.encode(raw)
			deepFreeze(raw)
			local def = Migration.migrate(raw)
			T.expect(def).never.toBeNil()
			T.expect(Json.encode(raw)).toBe(before)
			T.expect(raw.id).toBeNil()
			T.expect(raw.components[1].properties.initialScale).toBe(1)
			T.expect(table.isfrozen(def)).toBe(false)
		end)

		T.it("is deterministic", function()
			local a, da = Migration.migrate(BRIEF_EXAMPLE)
			local b, db = Migration.migrate(decode(BRIEF_EXAMPLE))
			T.expect(Json.encode(a)).toBe(Json.encode(b))
			T.expect(list(da)).toBe(list(db))
		end)
	end)

	-- ── The brief's example ──────────────────────────────────────────────────────────────────────────────

	T.describe("Migration of the brief example", function()
		T.it("detects the concept format despite schemaVersion 1", function()
			local version, reasons = Migration.detect(decode(BRIEF_EXAMPLE))
			T.expect(version).toBe(0)
			T.expect(#reasons).toBe(2)
		end)

		T.it("migrates into a valid v1 definition", function()
			local def, diags = Migration.migrate(decode(BRIEF_EXAMPLE))
			T.expect(def).never.toBeNil()
			local legacy = expectDiag(diags, "info", "migration.legacy_concept_format", "schemaVersion")
			T.expect(legacy.message).toMatch("initialScale")
			expectDiag(diags, "info", "migration.step", "schemaVersion")
			expectDiag(diags, "info", "migration.effect_id", "id")
			expectDiag(diags, "info", "migration.component_name", "components[1].name")
			local color = expectDiag(diags, "info", "migration.color", "components[1].properties.color")
			T.expect(color.message).toMatch("%[150, 65, 255%]")
			T.expect(color.componentId).toBe("core")
			expectDiag(diags, "info", "migration.scale_track", "components[1].tracks[1]")
			for _, d in diags do
				T.expect(d.severity).toBe("info")
			end

			T.expect(def.schemaVersion).toBe(1)
			T.expect(def.id).toBe("violetimpact")
			T.expect(def.name).toBe("VioletImpact")
			T.expect(def.duration).toBe(2.5)
			local core = def.components[1]
			T.expect(core.id).toBe("core")
			T.expect(core.name).toBe("core")
			T.expect(core.type).toBe("sphere")
			T.expect(core.startTime).toBe(0)
			T.expect(core.duration).toBe(1.2)
			T.expect(core.properties).toEqual({ coreColor = "#9641FF", shellColor = "#9641FF" })
			T.expect(core.tracks).toEqual({
				{
					id = "scale",
					channel = "scale",
					keyframes = { { time = 0, value = 1 }, { time = 1.2, value = 8 } },
				},
			})

			local result = expectValid(def)
			T.expect(#result.errors).toBe(0)
			T.expect(#result.warnings).toBe(0)
		end)

		T.it("accepts the JSON text directly (extension)", function()
			local fromText, diagsText = Migration.migrate(BRIEF_EXAMPLE)
			local fromTable, diagsTable = Migration.migrate(decode(BRIEF_EXAMPLE))
			T.expect(fromText).toEqual(fromTable)
			T.expect(#diagsText).toBe(#diagsTable)
		end)

		T.it("round-trips through canonical JSON and stays valid", function()
			local def = Migration.migrate(BRIEF_EXAMPLE)
			local again, diags = Migration.migrate(Json.encode(def))
			T.expect(diags).toEqual({})
			T.expect(again).toEqual(def)
			expectValid(again)
		end)
	end)

	T.describe("Migration of the brief example (integration)", function()
		T.it("compiles: scale 1 -> 8 over 1.2 s, colours decoded (when the Compiler is available)", function()
			local okCompiler, Compiler = pcall(use, "AstraVFX.Core.Compiler")
			local okCurves, Curves = pcall(use, "AstraVFX.Core.Curves")
			if not (okCompiler and okCurves and type(Compiler) == "table" and type(Compiler.compile) == "function") then
				return
			end
			local def = Migration.migrate(BRIEF_EXAMPLE)
			local compiled = Compiler.compile(def, { quality = "High" })
			local core = compiled.byId.core
			T.expect(core.startTime).toBe(0)
			T.expect(core.endTime).toBeCloseTo(1.2, 1e-9)
			T.expect(core.props.coreColor).toBeCloseTo(Color3.fromRGB(150, 65, 255), 1e-6)
			T.expect(core.props.shellColor).toBeCloseTo(Color3.fromRGB(150, 65, 255), 1e-6)
			T.expect(Curves.evaluate(core.tracks.scale, 0)).toBeCloseTo(1, 1e-9)
			T.expect(Curves.evaluate(core.tracks.scale, 0.6)).toBeCloseTo(4.5, 1e-9)
			T.expect(Curves.evaluate(core.tracks.scale, 1.2)).toBeCloseTo(8, 1e-9)
		end)
	end)

	-- ── Version handling ─────────────────────────────────────────────────────────────────────────────────

	T.describe("Migration versions", function()
		T.it("treats a missing schemaVersion as version 0", function()
			local raw = decode([[{"name":"Old","duration":1,"components":[{"type":"part"}]}]])
			local def, diags = Migration.migrate(raw)
			expectDiag(diags, "info", "migration.missing_version", "schemaVersion")
			expectDiag(diags, "info", "migration.step")
			T.expect(def.schemaVersion).toBe(1)
			T.expect(def.id).toBe("old")
			T.expect(def.components[1].id).toBe("part")
			T.expect(def.components[1].name).toBe("part")
			expectValid(def)
		end)

		T.it("migrates an explicit version 0", function()
			local def, diags =
				Migration.migrate({ schemaVersion = 0, id = "zero", name = "Zero", duration = 1, components = {} })
			T.expect(find(diags, "migration.missing_version")).toBeNil()
			expectDiag(diags, "info", "migration.step")
			T.expect(def.schemaVersion).toBe(1)
			T.expect(def.id).toBe("zero")
		end)

		T.it("rejects future versions", function()
			local def, diags =
				Migration.migrate({ schemaVersion = 2, id = "x", name = "X", duration = 1, components = {} })
			T.expect(def).toBeNil()
			expectDiag(diags, "error", "migration.future_version", "schemaVersion")
			T.expect(#diags).toBe(1)
		end)

		T.it("rejects invalid versions", function()
			for _, version in R("1", -1, 1.5, 0 / 0, math.huge, true, {}) do
				local def, diags = Migration.migrate({ schemaVersion = version, name = "X" })
				T.expect(def).toBeNil()
				expectDiag(diags, "error", "migration.version_invalid", "schemaVersion")
			end
		end)

		T.it("rejects input that cannot be a document", function()
			for _, raw in { nil :: any, 5, true, { 1, 2, 3 }, Json.NULL, print, Vector3.new(1, 2, 3) } do
				local def, diags = Migration.migrate(raw)
				T.expect(def).toBeNil()
				expectDiag(diags, "error", "migration.invalid", "")
			end
			local def, diags = Migration.migrate("{ not json")
			T.expect(def).toBeNil()
			T.expect(expectDiag(diags, "error", "migration.json", "").message).toMatch("line 1")
			def, diags = Migration.migrate("[1, 2]")
			T.expect(def).toBeNil()
			expectDiag(diags, "error", "migration.invalid", "")
		end)

		T.it("rejects cycles and excessive nesting", function()
			local raw: any = { schemaVersion = 1, name = "X", metadata = {} }
			raw.metadata.self = raw
			local def, diags = Migration.migrate(raw)
			T.expect(def).toBeNil()
			T.expect(expectDiag(diags, "error", "migration.not_json", "").message).toMatch("metadata.self")
			local deep: any = {}
			local t = deep
			for _ = 1, Json.MAX_DEPTH + 5 do
				t.x = {}
				t = t.x
			end
			def, diags = Migration.migrate({ schemaVersion = 1, name = "X", metadata = deep })
			T.expect(def).toBeNil()
			expectDiag(diags, "error", "migration.not_json")
			-- shared (acyclic) references are fine and are copied separately
			local shared = { 1, 2, 3 }
			local ok =
				Migration.migrate({ schemaVersion = 1, id = "s", name = "S", tags = shared, metadata = { t = shared } })
			T.expect(ok).never.toBeNil()
			T.expect(ok.tags).never.toBe(ok.metadata.t)
		end)

		T.it("migrates an empty object into a document that Validation explains", function()
			local def, diags = Migration.migrate(Json.EMPTY_OBJECT)
			T.expect(def).never.toBeNil()
			expectDiag(diags, "info", "migration.missing_version")
			T.expect(def.id).toBe("effect")
			T.expect(def.name).toBe("Effect")
			local result = Validation.validate(def)
			T.expect(result.ok).toBe(false) -- no duration, no components
		end)
	end)

	-- ── Step 0 -> 1 details ──────────────────────────────────────────────────────────────────────────────

	T.describe("Migration step 0 -> 1", function()
		T.it("slugs names into ids", function()
			T.expect(Migration.slug("VioletImpact")).toBe("violetimpact")
			T.expect(Migration.slug("  Fire Ball!! ")).toBe("fire-ball")
			T.expect(Migration.slug("a__b--c")).toBe("a__b-c")
			T.expect(Migration.slug("Ünïcode")).toBe("n-code")
			T.expect(Migration.slug("")).toBe("effect")
			T.expect(Migration.slug("!!!", "component")).toBe("component")
			T.expect(Migration.slug(5)).toBe("effect")
			local long = Migration.slug(string.rep("ab ", 40))
			T.expect(#long <= Constants.ID_MAX_LENGTH).toBe(true)
			T.expect(string.sub(long, -1)).never.toBe("-")
		end)

		T.it("gives components unique ids and names", function()
			local def, diags = Migration.migrate({
				name = "Ids",
				duration = 1,
				components = {
					{ name = "Spark", type = "part" } :: any,
					{ name = "Spark", type = "part" },
					{ id = "spark-3", name = "Taken", type = "part" },
					{ id = "Not Valid!", type = "group" },
					{ type = "flash" },
					{ type = "flash" },
					"garbage",
				},
			})
			local ids = {}
			for i = 1, 6 do
				table.insert(ids, def.components[i].id)
			end
			T.expect(ids).toEqual({ "spark", "spark-2", "spark-3", "not-valid", "flash", "flash-2" })
			T.expect(def.components[4].name).toBe("not-valid")
			T.expect(def.components[5].name).toBe("flash")
			T.expect(def.components[7]).toBe("garbage") -- left for Validation
			expectDiag(diags, "info", "migration.component_id", "components[1].id")
			expectDiag(diags, "info", "migration.component_id", "components[4].id")
			T.expect(find(diags, "migration.component_id", "components[3].id")).toBeNil()
			local result = Validation.validate(def)
			T.expect(#result.errors).toBe(1)
			T.expect(result.errors[1].code).toBe("component.invalid")
		end)

		T.it("replaces an invalid effect id and fills a missing name from the id", function()
			local def, diags = Migration.migrate({ id = "My Effect", duration = 1, components = {} })
			T.expect(def.name).toBe("My Effect")
			T.expect(def.id).toBe("my-effect")
			expectDiag(diags, "info", "migration.effect_name", "name")
			expectDiag(diags, "info", "migration.effect_id", "id")
		end)

		T.it("converts colours", function()
			local def, diags = Migration.migrate({
				name = "Colours",
				duration = 1,
				components = {
					{ id = "a", name = "A", type = "part", properties = { color = { 255, 128, 0 } } } :: any,
					{ id = "b", name = "B", type = "trail", properties = { color = { 0, 0, 255 } } },
					{ id = "c", name = "C", type = "sphere", properties = { color = "#0F0", coreColor = "#FFFFFF" } },
					{ id = "d", name = "D", type = "sphere", properties = { shellColor = { 1, 2, 3 } } },
					{ id = "e", name = "E", type = "sound", properties = { color = { 1, 2, 3 } } },
				},
			})
			T.expect(def.components[1].properties.color).toBe("#FF8000")
			T.expect(def.components[2].properties.color).toBe("#0000FF")
			-- an existing coreColor is kept; only the missing shellColor receives the legacy colour
			T.expect(def.components[3].properties).toEqual({ coreColor = "#FFFFFF", shellColor = "#00FF00" })
			T.expect(def.components[4].properties).toEqual({ shellColor = "#010203" })
			-- a type without colour keys keeps the value (Validation reports it as unknown)
			T.expect(def.components[5].properties.color).toEqual({ 1, 2, 3 })
			expectDiag(diags, "info", "migration.color", "components[1].properties.color")
			expectDiag(diags, "info", "migration.color", "components[3].properties.color")
			expectDiag(diags, "info", "migration.color", "components[4].properties.shellColor")
			T.expect(find(diags, "migration.color", "components[5].properties.color")).toBeNil()
			local result = Validation.validate(def)
			T.expect(result.ok).toBe(true)
			T.expect(result.warnings[1].code).toBe("property.unknown")
		end)

		T.it("turns initialScale/finalScale into a scale track over the component span", function()
			local def, diags = Migration.migrate({
				name = "Scales",
				duration = 3,
				components = {
					-- no component duration: effect duration - startTime
					{
						id = "a",
						name = "A",
						type = "sphere",
						startTime = 1,
						properties = { initialScale = 0.5, finalScale = 4 },
					} :: any,
					-- only finalScale: initialScale defaults to 1
					{ id = "b", name = "B", type = "part", duration = 2, properties = { finalScale = 3 } },
					-- equal values: rest scale instead of a track
					{ id = "c", name = "C", type = "ring", properties = { initialScale = 2, finalScale = 2 } },
					-- an existing track id "scale" makes the new one unique
					{
						id = "d",
						name = "D",
						type = "mesh",
						duration = 1,
						tracks = { { id = "scale", channel = "transparency", keyframes = { { time = 0, value = 0 } } } },
						properties = { initialScale = 1, finalScale = 0 },
					},
				},
			})
			local a = def.components[1]
			T.expect(a.properties).toEqual({})
			T.expect(a.tracks[1].keyframes).toEqual({ { time = 0, value = 0.5 }, { time = 2, value = 4 } })
			local b = def.components[2]
			T.expect(b.tracks[1].keyframes).toEqual({ { time = 0, value = 1 }, { time = 2, value = 3 } })
			local c = def.components[3]
			T.expect(c.tracks).toBeNil()
			T.expect(c.transform).toEqual({ scale = 2 })
			local d = def.components[4]
			T.expect(#d.tracks).toBe(2)
			T.expect(d.tracks[2].id).toBe("scale-2")
			T.expect(d.tracks[2].channel).toBe("scale")
			expectDiag(diags, "info", "migration.scale_track", "components[1].tracks[1]")
			expectDiag(diags, "info", "migration.scale_track", "components[3].transform.scale")
			expectDiag(diags, "info", "migration.scale_track", "components[4].tracks[2]")
			expectValid(def)
		end)

		T.it("keeps an existing scale track and reports the conflict", function()
			local def, diags = Migration.migrate({
				name = "Conflict",
				duration = 1,
				components = {
					{
						id = "a",
						name = "A",
						type = "sphere",
						tracks = { { id = "s", channel = "scale", keyframes = { { time = 0, value = 2 } } } },
						properties = { initialScale = 1, finalScale = 8 },
					} :: any,
					{
						id = "b",
						name = "B",
						type = "sphere",
						transform = { scale = 3 },
						properties = { initialScale = 5, finalScale = 5 },
					},
				},
			})
			T.expect(def.components[1].properties).toEqual({})
			T.expect(#def.components[1].tracks).toBe(1)
			expectDiag(diags, "warning", "migration.scale_conflict", "components[1].properties")
			T.expect(def.components[2].transform.scale).toBe(3)
			expectDiag(diags, "warning", "migration.scale_conflict", "components[2].transform.scale")
			expectValid(def)
		end)

		T.it("falls back to transform.scale without a usable span", function()
			local def, diags = Migration.migrate({
				name = "NoSpan",
				components = {
					{ id = "a", name = "A", type = "sphere", properties = { initialScale = 2, finalScale = 6 } },
				},
			})
			T.expect(def.components[1].transform).toEqual({ scale = 2 })
			expectDiag(diags, "warning", "migration.scale_conflict", "components[1].transform.scale")
		end)

		T.it("leaves unusable legacy scales in place", function()
			local def, diags = Migration.migrate({
				name = "Bad",
				duration = 1,
				components = {
					{ id = "a", name = "A", type = "sphere", properties = { initialScale = "big", finalScale = 2 } } :: any,
					{
						id = "b",
						name = "B",
						type = "sphere",
						tracks = 5,
						properties = { initialScale = 1, finalScale = 2 },
					},
				},
			})
			T.expect(def.components[1].properties.initialScale).toBe("big")
			expectDiag(diags, "warning", "migration.scale_invalid", "components[1].properties")
			T.expect(def.components[2].properties.finalScale).toBe(2)
			expectDiag(diags, "warning", "migration.scale_invalid", "components[2].properties")
			local result = Validation.validate(def)
			T.expect(result.ok).toBe(false) -- tracks = 5
		end)

		T.it("does not convert legacy keys on types without a scale channel", function()
			local def = Migration.migrate({
				name = "Light",
				duration = 1,
				components = {
					{ id = "l", name = "L", type = "light", properties = { initialScale = 1, finalScale = 2 } },
				},
			})
			T.expect(def.components[1].properties).toEqual({ initialScale = 1, finalScale = 2 })
			T.expect(def.components[1].tracks).toBeNil()
		end)

		T.it("adds ids to tracks, events and markers", function()
			local def, diags = Migration.migrate({
				name = "Entries",
				duration = 2,
				markers = {
					{ time = 0.5, label = "Big Hit" },
					{ time = 1, label = "Big Hit" },
					{ id = "x", time = 1.5, label = "X" },
				},
				components = {
					{
						id = "p",
						name = "P",
						type = "particles",
						tracks = {
							{ channel = "rate", keyframes = { { time = 0, value = 10 } } },
							{ channel = "brightness", keyframes = { { time = 0, value = 2 } } },
						},
						events = {
							{ time = 0, action = "emit", count = 5 },
							{ time = 0.5, action = "emit", count = 5 },
						},
					},
				},
			})
			T.expect(def.markers[1].id).toBe("big-hit")
			T.expect(def.markers[2].id).toBe("big-hit-2")
			T.expect(def.markers[3].id).toBe("x")
			local p = def.components[1]
			T.expect(p.tracks[1].id).toBe("rate")
			T.expect(p.tracks[2].id).toBe("brightness")
			T.expect(p.events[1].id).toBe("emit")
			T.expect(p.events[2].id).toBe("emit-2")
			expectDiag(diags, "info", "migration.marker_id", "markers[1].id")
			expectDiag(diags, "info", "migration.track_id", "components[1].tracks[1].id")
			expectDiag(diags, "info", "migration.event_id", "components[1].events[2].id")
			T.expect(find(diags, "migration.marker_id", "markers[3].id")).toBeNil()
			expectValid(def)
		end)

		T.it("writes into tables that were Json.EMPTY_OBJECT", function()
			local raw = decode(
				[[{"name":"Empty","duration":1,"components":[{}, {"type":"sphere","properties":{"color":[1,2,3]}}]}]]
			)
			T.expect(raw.components[1]).toBe(Json.EMPTY_OBJECT)
			local def = Migration.migrate(raw)
			T.expect(def.components[1].id).toBe("component")
			T.expect(def.components[2].id).toBe("sphere")
			T.expect(def.components[2].properties.coreColor).toBe("#010203")
			T.expect(Json.EMPTY_OBJECT.id).toBeNil()
		end)
	end)

	-- ── Step registry ────────────────────────────────────────────────────────────────────────────────────

	T.describe("Migration step registry", function()
		local stepV2 = {
			from = 1,
			to = 2,
			description = "test step: rename effect description to summary",
			run = function(doc: any, report: any)
				if doc.description ~= nil then
					doc.summary = doc.description
					doc.description = nil
					report:add("info", "test.renamed", "description", "description -> summary")
				end
			end,
		}

		T.it("chains steps up to the target version", function()
			local steps = { [0] = Migration.STEPS[0], [1] = stepV2 }
			local raw = decode(BRIEF_EXAMPLE)
			raw.description = "concept"
			local def, diags = Migration.migrate(raw, { target = 2, steps = steps })
			T.expect(def.schemaVersion).toBe(2)
			T.expect(def.summary).toBe("concept")
			T.expect(def.components[1].tracks[1].channel).toBe("scale")
			local stepsRun = {}
			for _, d in diags do
				if d.code == "migration.step" then
					table.insert(stepsRun, d.message)
				end
			end
			T.expect(#stepsRun).toBe(2)
			T.expect(stepsRun[1]).toMatch("^schema 0 %-> 1")
			T.expect(stepsRun[2]).toMatch("^schema 1 %-> 2")
			expectDiag(diags, "info", "test.renamed")
			-- a version-1 document only runs the second step
			local def1, diags1 = Migration.migrate(v1(), { target = 2, steps = steps })
			T.expect(def1.schemaVersion).toBe(2)
			T.expect(#diags1).toBe(1)
		end)

		T.it("reports a missing step", function()
			local def, diags = Migration.migrate(v1(), { target = 2 })
			T.expect(def).toBeNil()
			expectDiag(diags, "error", "migration.no_step", "schemaVersion")
		end)
	end)
end
