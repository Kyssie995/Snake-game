--!strict
--[[
	Authoring/Diagnostics (docs/MODULE_CONTRACTS.md §20): multi-line text of diagnostic lists, one-line summaries of
	ValidationResults, and the helpers count / toResult / sorted. The line format matches the error summaries of
	AstraVFX.Register (the runtime keeps its own copy because it must not require Authoring).
]]
return function(T: any, use: (string) -> any, _ctx: any)
	local Diagnostics = use("Authoring.Diagnostics")
	local AstraVFX = use("AstraVFX")
	local Validation = use("AstraVFX.Core.Validation")
	local expect = T.expect

	local function R(...: any): { any }
		return { ... }
	end

	local function d(severity: string, code: string, path: string, message: string, hint: string?): any
		return { severity = severity, code = code, path = path, message = message, hint = hint }
	end

	local RATE = d(
		"error",
		"property.range",
		"components[2].properties.rate",
		"rate 500 is above the maximum 400",
		"lower the rate"
	)
	local TRAIL = d("warning", "lint.trail_static", "components[3]", "trail without a movement source")
	local MIGRATED = d("info", "migration.step", "schemaVersion", "schema 0 -> 1: concept format")
	local ROOT = d("error", "effect.type", "", "the definition is not an object")

	local function invalidDef(): any
		return {
			schemaVersion = 1,
			id = "broken",
			name = "Broken",
			duration = -1,
			components = R(
				{ id = "a", name = "A", type = "laser" },
				{ id = "b", name = "B", type = "particles", properties = { rate = -3 } }
			),
		}
	end

	T.describe("Diagnostics.line", function()
		T.it("is '<severity> <code> <path>: <message>' (no path part for the empty path)", function()
			expect(Diagnostics.line(RATE)).toBe(
				"error property.range components[2].properties.rate: rate 500 is above the maximum 400"
			)
			expect(Diagnostics.line(ROOT)).toBe("error effect.type: the definition is not an object")
			expect(Diagnostics.line(MIGRATED)).toBe("info migration.step schemaVersion: schema 0 -> 1: concept format")
		end)

		T.it("matches the lines of AstraVFX.Register's error summary", function()
			AstraVFX._reset()
			local ok, err = pcall(AstraVFX.Register :: any, invalidDef())
			expect(ok).toBe(false)
			local result = Validation.validate(invalidDef())
			expect(#result.errors >= 3).toBe(true)
			for _, e in result.errors do
				expect(tostring(err)).toContain("\n  " .. Diagnostics.line(e))
			end
			AstraVFX._reset()
		end)

		T.it("tolerates malformed diagnostics", function()
			expect(Diagnostics.line({} :: any)).toBe("error: ")
			expect(Diagnostics.line({ severity = "warning", code = 5, message = { 1 } } :: any)).toContain(
				"warning 5: table"
			)
			expect(Diagnostics.line("oops" :: any)).toBe("error oops")
		end)
	end)

	T.describe("Diagnostics.format", function()
		T.it("writes one block per diagnostic with hint lines, in list order", function()
			expect(Diagnostics.format({ RATE, TRAIL, MIGRATED })).toBe(table.concat({
				"error property.range components[2].properties.rate: rate 500 is above the maximum 400",
				"  hint: lower the rate",
				"warning lint.trail_static components[3]: trail without a movement source",
				"info migration.step schemaVersion: schema 0 -> 1: concept format",
			}, "\n"))
		end)

		T.it("returns an empty string for an empty list", function()
			expect(Diagnostics.format({})).toBe("")
		end)

		T.it("supports limit, hints = false and indent", function()
			local list = { RATE, TRAIL, MIGRATED, ROOT }
			expect(Diagnostics.format(list, { limit = 2, indent = "  " })).toBe(table.concat({
				"  error property.range components[2].properties.rate: rate 500 is above the maximum 400",
				"    hint: lower the rate",
				"  warning lint.trail_static components[3]: trail without a movement source",
				"  ... and 2 more",
			}, "\n"))
			expect(Diagnostics.format(list, { hints = false, limit = 1 })).toBe(
				"error property.range components[2].properties.rate: rate 500 is above the maximum 400\n... and 3 more"
			)
			expect(Diagnostics.format(list, { limit = 0 })).toBe("... and 4 more")
			expect(Diagnostics.format(list, { limit = 99 })).toBe(Diagnostics.format(list))
		end)

		T.it("indents continuation lines of multi-line messages and hints", function()
			local multi = d("error", "x.y", "p", "first\nsecond", "hint one\nhint two")
			expect(Diagnostics.format({ multi }, { indent = "> " })).toBe(table.concat({
				"> error x.y p: first",
				">   second",
				">   hint: hint one",
				">         hint two",
			}, "\n"))
		end)

		T.it("formats real validation output and rejects non-tables", function()
			local result = Validation.validate(invalidDef())
			local text = Diagnostics.format(result.errors)
			expect(text).toContain("error effect.duration duration:")
			expect(text).toContain("error component.type components[1].type:")
			expect(text).toContain("components[2].properties.rate")
			expect(function()
				Diagnostics.format("nope" :: any)
			end).toThrow("Diagnostics.format: list must be a table")
		end)
	end)

	T.describe("Diagnostics.summary", function()
		T.it("describes a clean result", function()
			expect(Diagnostics.summary({ ok = true, errors = {}, warnings = {}, infos = {} })).toBe(
				"valid: 0 errors, 0 warnings, 0 infos"
			)
		end)

		T.it("names the first warning of a valid result", function()
			local summary =
				Diagnostics.summary({ ok = true, errors = {}, warnings = { TRAIL, TRAIL }, infos = { MIGRATED } })
			expect(summary).toBe(
				"valid: 0 errors, 2 warnings, 1 info; first warning: lint.trail_static components[3]: trail without a movement source"
			)
		end)

		T.it("names the first error of an invalid result on one line", function()
			local multi = d("error", "effect.json", "", "not\nplain   JSON")
			local summary =
				Diagnostics.summary({ ok = false, errors = { multi, RATE }, warnings = { TRAIL }, infos = {} })
			expect(summary).toBe("invalid: 2 errors, 1 warning, 0 infos; first error: effect.json: not plain JSON")
			expect(string.find(summary, "\n", 1, true)).toBeNil()
		end)

		T.it("summarises real validation results and plain diagnostic lists", function()
			local result = Validation.validate(invalidDef())
			local summary = Diagnostics.summary(result)
			expect(string.sub(summary, 1, 9)).toBe("invalid: ")
			expect(summary).toContain(#result.errors .. " errors")
			expect(summary).toContain("first error: " .. string.sub(Diagnostics.line(result.errors[1]), 7))
			expect(Diagnostics.summary({ TRAIL, RATE } :: any)).toBe(
				"invalid: 1 error, 1 warning, 0 infos; first error: property.range components[2].properties.rate: rate 500 is above the maximum 400"
			)
			expect(Diagnostics.summary({} :: any)).toBe("valid: 0 errors, 0 warnings, 0 infos")
		end)

		T.it("trusts errors over a wrong ok flag and rejects non-tables", function()
			expect(string.sub(Diagnostics.summary({ ok = true, errors = { RATE }, warnings = {}, infos = {} }), 1, 8)).toBe(
				"invalid:"
			)
			expect(function()
				Diagnostics.summary(nil :: any)
			end).toThrow("Diagnostics.summary: expected a ValidationResult")
		end)
	end)

	T.describe("Diagnostics helpers", function()
		T.it("count, toResult and sorted split by severity and keep the order", function()
			local list = { MIGRATED, RATE, TRAIL, ROOT, { code = "odd" } :: any }
			expect(Diagnostics.count(list)).toEqual({ errors = 3, warnings = 1, infos = 1 })
			local result = Diagnostics.toResult(list)
			expect(result.ok).toBe(false)
			expect(result.errors).toEqual({ RATE, ROOT, list[5] })
			expect(result.warnings).toEqual({ TRAIL })
			expect(result.infos).toEqual({ MIGRATED })
			expect(Diagnostics.toResult({ TRAIL }).ok).toBe(true)
			local sorted = Diagnostics.sorted(list)
			expect(sorted[1]).toBe(RATE)
			expect(sorted[2]).toBe(ROOT)
			expect(sorted[3]).toBe(list[5])
			expect(sorted[4]).toBe(TRAIL)
			expect(sorted[5]).toBe(MIGRATED)
			expect(#list).toBe(5) -- not modified
			expect(list[1]).toBe(MIGRATED)
		end)
	end)
end
