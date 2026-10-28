--!strict
--[[
	Effect files of the repository (Lune only: reads files through ctx.readFile, see tests/lune/run.luau).

	  tests/fixtures/concept-v0.json   the project brief's conceptual example, unchanged: labelled schemaVersion 1
	                                   but written in the pre-release concept format (RGB array colour, sphere
	                                   initialScale / finalScale, no effect id)
	  effects/VioletImpact.vfx.json    that example migrated with Core/Migration to schema v1, stored canonically

	Both directions are pinned: migrating the fixture yields exactly the stored definition, and the stored file is
	canonical, current (migrating it again changes nothing) and valid without errors or warnings.
]]
return function(T: any, use: (string) -> any, ctx: any)
	local Json = use("AstraVFX.Core.Json")
	local Migration = use("AstraVFX.Core.Migration")
	local Validation = use("AstraVFX.Core.Validation")
	local expect = T.expect

	local canRead = ctx.environment == "lune" and type(ctx.readFile) == "function"

	local CONCEPT = "tests/fixtures/concept-v0.json"
	local VIOLET = "effects/VioletImpact.vfx.json"

	local function read(path: string): string
		return ctx.readFile(path)
	end

	local function decode(text: string, label: string): any
		local ok, value = Json.decode(text)
		if not ok then
			error(label .. " is not valid JSON: " .. tostring(value), 2)
		end
		return value
	end

	T.describe("EffectFiles", function()
		T.describe("tests/fixtures/concept-v0.json", function()
			T.itIf(canRead, "is the brief's example in the concept format", function()
				local raw = decode(read(CONCEPT), CONCEPT)
				expect(raw.schemaVersion).toBe(1)
				expect(raw.id).toBeNil()
				expect(raw.name).toBe("VioletImpact")
				expect(raw.duration).toBe(2.5)
				expect(#raw.components).toBe(1)
				local core = raw.components[1]
				expect(core.id).toBe("core")
				expect(core.type).toBe("sphere")
				expect(core.startTime).toBe(0)
				expect(core.duration).toBe(1.2)
				expect(core.properties).toEqual({ color = { 150, 65, 255 }, initialScale = 1, finalScale = 8 })
				-- the legacy keys make Migration treat it as version 0 despite the label
				local version, reasons = Migration.detect(raw)
				expect(version).toBe(0)
				expect(#reasons).toBeGreaterThan(0)
			end)
		end)

		T.describe("effects/VioletImpact.vfx.json", function()
			T.itIf(canRead, "is exactly the migrated concept example (JSON text and table input)", function()
				local stored = decode(read(VIOLET), VIOLET)
				local fromText, textDiagnostics = Migration.migrate(read(CONCEPT))
				local fromTable = Migration.migrate(decode(read(CONCEPT), CONCEPT))
				expect(fromText).toEqual(stored)
				expect(fromTable).toEqual(stored)
				local legacy = false
				for _, d in textDiagnostics do
					expect(d.severity).never.toBe("error")
					if d.code == "migration.legacy_concept_format" then
						legacy = true
					end
				end
				expect(legacy).toBe(true)
			end)

			T.itIf(canRead, "keeps the migrated content: id, colours and the scale track", function()
				local stored = decode(read(VIOLET), VIOLET)
				expect(stored.schemaVersion).toBe(1)
				expect(stored.id).toBe("violetimpact")
				local core = stored.components[1]
				expect(core.properties).toEqual({ coreColor = "#9641FF", shellColor = "#9641FF" })
				expect(#core.tracks).toBe(1)
				expect(core.tracks[1].channel).toBe("scale")
				expect(core.tracks[1].keyframes).toEqual({ { time = 0, value = 1 }, { time = 1.2, value = 8 } })
			end)

			T.itIf(canRead, "is stored canonically (Json.encode, pretty, trailing newline)", function()
				local text = read(VIOLET)
				local stored = decode(text, VIOLET)
				expect(Json.encode(stored) .. "\n").toBe(text)
				-- Authoring/Exporter.toJson is the canonical writer once it exists (MODULE_CONTRACTS §20)
				local hasExporter, Exporter = pcall(use, "Authoring.Exporter")
				if hasExporter and type(Exporter) == "table" and type(Exporter.toJson) == "function" then
					expect(Exporter.toJson(stored)).toBe(text)
				end
			end)

			T.itIf(canRead, "is current and valid (no migration needed, no errors, no warnings)", function()
				local stored = decode(read(VIOLET), VIOLET)
				local again, diagnostics = Migration.migrate(stored)
				expect(again).toEqual(stored)
				expect(diagnostics).toEqual({})
				local result = Validation.validate(stored)
				expect(result.ok).toBe(true)
				expect(result.errors).toEqual({})
				expect(result.warnings).toEqual({})
			end)
		end)
	end)
end
