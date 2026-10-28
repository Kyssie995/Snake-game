--!strict
--[[
	Authoring/Diagnostics — human-readable text for Types.Diagnostic lists and ValidationResults
	(docs/MODULE_CONTRACTS.md §20). Used by the CLI, the plugin (status line, toasts, dialogs) and every authoring
	function that raises on an invalid definition (Exporter).

	  Diagnostics.format(list, options?) -> string     multi-line text, one block per diagnostic, in list order:
	      error property.range components[2].properties.rate: rate 500 is above the maximum 400
	        hint: lower the rate or split the emitter
	    options = { limit: number?,    at most `limit` diagnostics, then "... and N more" (default: all)
	                hints: boolean?,   hint lines (default true)
	                indent: string? }  prefix of every line (default "")
	    An empty list gives "". No trailing newline.
	  Diagnostics.line(d) -> string                    the first line of one block: "<severity> <code> <path>: <message>"
	                                                   (the path part is left out when the path is "")
	  Diagnostics.summary(result) -> string            one line for a ValidationResult (or a plain Diagnostic list):
	      "valid: 0 errors, 0 warnings, 0 infos"
	      "valid: 0 errors, 2 warnings, 1 info; first warning: lint.trail_static components[3]: ..."
	      "invalid: 3 errors, 1 warning, 0 infos; first error: property.range components[2].properties.rate: ..."
	  Diagnostics.count(list) -> { errors, warnings, infos }
	  Diagnostics.toResult(list) -> ValidationResult   splits a list by severity (ok = no errors), order kept
	  Diagnostics.sorted(list) -> list                 a new list: errors, then warnings, then infos (stable)

	The line format is the one AstraVFX.Register uses for its error summaries (src/Runtime/init.luau keeps its own
	copy: the runtime must not require Authoring, docs/ARCHITECTURE.md §2), so CLI, plugin and runtime errors look
	alike. Every function is total for malformed input (missing fields, non-string values, unknown severities):
	values are shown with tostring, a message spanning several lines is indented under its first line, and the
	one-line summary collapses whitespace runs (newlines included) to single spaces.
]]

local Types = require(script.Parent.Parent.AstraVFX.Core.Types)

type Diagnostic = Types.Diagnostic
type ValidationResult = Types.ValidationResult

export type FormatOptions = {
	limit: number?,
	hints: boolean?,
	indent: string?,
}

export type Counts = { errors: number, warnings: number, infos: number }

local Diagnostics = {}

local SEVERITY_RANK: { [string]: number } = { error = 1, warning = 2, info = 3 }

local function text(v: any): string
	if type(v) == "string" then
		return v
	end
	if v == nil then
		return ""
	end
	return tostring(v)
end

-- Severity name of a diagnostic ("error" | "warning" | "info"), or its text when it is something else.
local function severityOf(d: any): string
	if type(d) ~= "table" then
		return "error"
	end
	local s = d.severity
	if type(s) == "string" and s ~= "" then
		return s
	end
	return "error"
end

-- Collapses every whitespace run (newlines included) into one space and trims the ends.
local function oneLine(s: string): string
	local collapsed = string.gsub(s, "%s+", " ")
	return (string.match(collapsed, "^%s*(.-)%s*$") or collapsed)
end

-- Indents every line after the first one of `s` with `prefix`.
local function indentContinuation(s: string, prefix: string): string
	if string.find(s, "\n", 1, true) == nil then
		return s
	end
	return (string.gsub(s, "\n", "\n" .. prefix))
end

local function plural(n: number, word: string): string
	return tostring(n) .. " " .. word .. (if n == 1 then "" else "s")
end

-- "<severity> <code> <path>: <message>" (the path is left out when empty). Multi-line messages stay multi-line.
function Diagnostics.line(d: Diagnostic): string
	local v: any = d
	if type(v) ~= "table" then
		return "error " .. text(v)
	end
	local code = text(v.code)
	local path = text(v.path)
	local head = severityOf(v)
	if code ~= "" then
		head ..= " " .. code
	end
	if path ~= "" then
		head ..= " " .. path
	end
	return head .. ": " .. text(v.message)
end

-- Multi-line, human-readable text of a diagnostic list (see the module header).
function Diagnostics.format(list: { Diagnostic }, options: FormatOptions?): string
	if type(list) ~= "table" then
		error("Diagnostics.format: list must be a table of diagnostics, got " .. typeof(list), 2)
	end
	local o: FormatOptions = options or {}
	local indent = if type(o.indent) == "string" then o.indent else ""
	local hints = o.hints ~= false
	local limit = #list
	if type(o.limit) == "number" and o.limit == o.limit and o.limit >= 0 then
		limit = math.min(limit, math.floor(o.limit))
	end
	local lines: { string } = {}
	for i = 1, limit do
		local d: any = list[i]
		table.insert(lines, indent .. indentContinuation(Diagnostics.line(d), indent .. "  "))
		if hints and type(d) == "table" and d.hint ~= nil and text(d.hint) ~= "" then
			table.insert(lines, indent .. "  hint: " .. indentContinuation(text(d.hint), indent .. "        "))
		end
	end
	if limit < #list then
		table.insert(lines, indent .. "... and " .. (#list - limit) .. " more")
	end
	return table.concat(lines, "\n")
end

-- Number of errors, warnings and infos in a list (unknown severities count as errors).
function Diagnostics.count(list: { Diagnostic }): Counts
	local counts: Counts = { errors = 0, warnings = 0, infos = 0 }
	if type(list) ~= "table" then
		return counts
	end
	for _, d in list do
		local s = severityOf(d)
		if s == "warning" then
			counts.warnings += 1
		elseif s == "info" then
			counts.infos += 1
		else
			counts.errors += 1
		end
	end
	return counts
end

-- Splits a diagnostic list by severity into a ValidationResult (ok = no errors). Order is kept per severity.
function Diagnostics.toResult(list: { Diagnostic }): ValidationResult
	local result: ValidationResult = { ok = true, errors = {}, warnings = {}, infos = {} }
	if type(list) ~= "table" then
		return result
	end
	for _, d in list do
		local s = severityOf(d)
		if s == "warning" then
			table.insert(result.warnings, d)
		elseif s == "info" then
			table.insert(result.infos, d)
		else
			table.insert(result.errors, d)
		end
	end
	result.ok = #result.errors == 0
	return result
end

-- A new list sorted by severity (errors, warnings, infos); equal severities keep their order.
function Diagnostics.sorted(list: { Diagnostic }): { Diagnostic }
	local indexed: { { d: Diagnostic, i: number, r: number } } = {}
	for i, d in list do
		table.insert(indexed, { d = d, i = i, r = SEVERITY_RANK[severityOf(d)] or 1 })
	end
	table.sort(indexed, function(a, b): boolean
		if a.r ~= b.r then
			return a.r < b.r
		end
		return a.i < b.i
	end)
	local out: { Diagnostic } = {}
	for _, entry in indexed do
		table.insert(out, entry.d)
	end
	return out
end

local function isResult(v: any): boolean
	return type(v) == "table" and (type(v.errors) == "table" or type(v.warnings) == "table" or type(v.infos) == "table")
end

-- One-line summary of a ValidationResult (a plain diagnostic list is split by severity first).
function Diagnostics.summary(result: ValidationResult): string
	local r: any = result
	if not isResult(r) then
		if type(r) ~= "table" then
			error("Diagnostics.summary: expected a ValidationResult or a diagnostic list, got " .. typeof(r), 2)
		end
		r = Diagnostics.toResult(r)
	end
	local errors: { Diagnostic } = if type(r.errors) == "table" then r.errors else {}
	local warnings: { Diagnostic } = if type(r.warnings) == "table" then r.warnings else {}
	local infos: { Diagnostic } = if type(r.infos) == "table" then r.infos else {}
	local ok = #errors == 0
	if type(r.ok) == "boolean" then
		ok = r.ok and #errors == 0
	end
	local out = (if ok then "valid: " else "invalid: ")
		.. plural(#errors, "error")
		.. ", "
		.. plural(#warnings, "warning")
		.. ", "
		.. plural(#infos, "info")
	local first: any = nil
	local label = ""
	if #errors > 0 then
		first, label = errors[1], "first error"
	elseif #warnings > 0 then
		first, label = warnings[1], "first warning"
	end
	if first ~= nil then
		local line = Diagnostics.line(first)
		-- drop the severity word: the label already says it
		local severity = severityOf(first)
		if type(first) == "table" and string.sub(line, 1, #severity + 1) == severity .. " " then
			line = string.sub(line, #severity + 2)
		end
		out ..= "; " .. label .. ": " .. oneLine(line)
	end
	return out
end

return Diagnostics
