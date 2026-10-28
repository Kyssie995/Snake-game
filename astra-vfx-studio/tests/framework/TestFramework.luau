--!strict
--[[
	TestFramework — a small, dependency-free BDD test framework.

	Runs unchanged in Lune (tests/lune/run.luau) and inside Roblox Studio (the plugin's self-test command).
	Spec modules return `function(T: TestApi, use: (path: string) -> any, ctx: SpecContext)`.

	Example:
		return function(T, use)
			local Json = use("AstraVFX.Core.Json")
			T.describe("Json", function()
				T.it("encodes integers without a decimal point", function()
					T.expect(Json.encode(3)).toBe("3")
				end)
			end)
		end
]]

local TestFramework = {}

export type SpecContext = {
	environment: "lune" | "studio",
	-- Optional engine fakes (only in Lune). Specs that need them should skip when nil.
	fakes: any?,
	-- Optional file access (only in Lune): reads a repository file, path relative to the project directory.
	readFile: ((path: string) -> string)?,
}

export type TestResult = {
	name: string,
	status: "passed" | "failed" | "skipped",
	message: string?,
	duration: number,
}

export type RunReport = {
	passed: number,
	failed: number,
	skipped: number,
	results: { TestResult },
}

type TestCase = {
	name: string,
	fn: (() -> ())?,
	skip: boolean,
}

type Suite = {
	name: string,
	tests: { TestCase },
	children: { Suite },
	beforeEach: { () -> () },
	afterEach: { () -> () },
	parent: Suite?,
}

local function newSuite(name: string, parent: Suite?): Suite
	return { name = name, tests = {}, children = {}, beforeEach = {}, afterEach = {}, parent = parent }
end

local function isRobloxValue(v: any): boolean
	local t = typeof(v)
	return t ~= "table" and t ~= "nil" and t ~= "number" and t ~= "string" and t ~= "boolean" and t ~= "function"
end

local function show(v: any, depth: number?): string
	local d = depth or 0
	local t = typeof(v)
	if t == "string" then
		return string.format("%q", v)
	elseif t == "table" then
		if d > 3 then
			return "{...}"
		end
		local keys = {}
		for k in pairs(v) do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for i, k in ipairs(keys) do
			if i > 12 then
				table.insert(parts, "...")
				break
			end
			table.insert(parts, tostring(k) .. "=" .. show(v[k], d + 1))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	elseif isRobloxValue(v) then
		return t .. "(" .. tostring(v) .. ")"
	end
	return tostring(v)
end
TestFramework.show = show

local function deepEqual(a: any, b: any, path: string): (boolean, string?)
	if a == b then
		return true, nil
	end
	local ta, tb = typeof(a), typeof(b)
	if ta ~= tb then
		return false, path .. ": type " .. ta .. " ~= " .. tb
	end
	if ta == "number" then
		if a ~= a and b ~= b then
			return true, nil -- NaN == NaN for test purposes
		end
		return false, path .. ": " .. tostring(a) .. " ~= " .. tostring(b)
	end
	if ta ~= "table" then
		return false, path .. ": " .. show(a) .. " ~= " .. show(b)
	end
	for k, va in pairs(a) do
		local ok, why = deepEqual(va, b[k], path .. "." .. tostring(k))
		if not ok then
			return false, why
		end
	end
	for k, vb in pairs(b) do
		if a[k] == nil and vb ~= nil then
			return false, path .. "." .. tostring(k) .. ": missing on left side (right = " .. show(vb) .. ")"
		end
	end
	return true, nil
end
TestFramework.deepEqual = deepEqual

-- Component-wise closeness for numbers and common Roblox datatypes.
local function closeTo(a: any, b: any, eps: number): boolean
	local t = typeof(a)
	if t ~= typeof(b) then
		return false
	end
	if t == "number" then
		return math.abs(a - b) <= eps
	elseif t == "Vector3" then
		return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
	elseif t == "Vector2" then
		return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps
	elseif t == "Color3" then
		return math.abs(a.R - b.R) <= eps and math.abs(a.G - b.G) <= eps and math.abs(a.B - b.B) <= eps
	elseif t == "CFrame" then
		local ca = { a:GetComponents() }
		local cb = { b:GetComponents() }
		for i = 1, 12 do
			if math.abs(ca[i] - cb[i]) > eps then
				return false
			end
		end
		return true
	elseif t == "table" then
		for k, v in pairs(a) do
			if not closeTo(v, b[k], eps) then
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
	return a == b
end
TestFramework.closeTo = closeTo

local AssertionError = {}
AssertionError.__index = AssertionError
AssertionError.__tostring = function(self)
	return self.message
end

local function fail(message: string): never
	error(setmetatable({ message = message }, AssertionError), 3)
end

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeCloseTo: (expected: any, epsilon: number?) -> (),
	toBeNil: () -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toThrow: (substring: string?) -> (),
	toContain: (item: any) -> (),
	toHaveLength: (n: number) -> (),
	toMatch: (pattern: string) -> (),
	toBeGreaterThan: (n: number) -> (),
	toBeGreaterThanOrEqual: (n: number) -> (),
	toBeLessThan: (n: number) -> (),
	toBeLessThanOrEqual: (n: number) -> (),
	toBeA: (typeName: string) -> (),
	never: Expectation,
}

local function makeExpectation(actual: any, negate: boolean): Expectation
	local e = {} :: any
	local function check(pass: boolean, message: string)
		if negate then
			pass = not pass
			message = "NOT: " .. message
		end
		if not pass then
			fail(message)
		end
	end
	function e.toBe(expected: any)
		check(actual == expected, "expected " .. show(actual) .. " to be " .. show(expected))
	end
	function e.toEqual(expected: any)
		local ok, why = deepEqual(actual, expected, "value")
		check(ok, "expected deep equality: " .. tostring(why))
	end
	function e.toBeCloseTo(expected: any, epsilon: number?)
		local eps = epsilon or 1e-4
		check(
			closeTo(actual, expected, eps),
			"expected " .. show(actual) .. " to be within " .. eps .. " of " .. show(expected)
		)
	end
	function e.toBeNil()
		check(actual == nil, "expected nil, got " .. show(actual))
	end
	function e.toBeTruthy()
		check(not not actual, "expected truthy, got " .. show(actual))
	end
	function e.toBeFalsy()
		check(not actual, "expected falsy, got " .. show(actual))
	end
	function e.toThrow(substring: string?)
		local ok, err = pcall(actual)
		local msg = tostring(err)
		if type(err) == "table" and err.message then
			msg = tostring(err.message)
		end
		local pass = not ok and (substring == nil or string.find(msg, substring, 1, true) ~= nil)
		check(
			pass,
			"expected function to throw"
				.. (if substring then " containing " .. show(substring) else "")
				.. (if ok then " (it did not throw)" else ", got: " .. msg)
		)
	end
	function e.toContain(item: any)
		local found = false
		if type(actual) == "string" then
			found = string.find(actual, tostring(item), 1, true) ~= nil
		elseif type(actual) == "table" then
			for _, v in pairs(actual) do
				if v == item then
					found = true
					break
				end
			end
		end
		check(found, "expected " .. show(actual) .. " to contain " .. show(item))
	end
	function e.toHaveLength(n: number)
		local len = if type(actual) == "string" or type(actual) == "table" then #actual else -1
		check(len == n, "expected length " .. n .. ", got " .. len)
	end
	function e.toMatch(pattern: string)
		check(
			type(actual) == "string" and string.match(actual, pattern) ~= nil,
			"expected " .. show(actual) .. " to match " .. pattern
		)
	end
	function e.toBeGreaterThan(n: number)
		check(type(actual) == "number" and actual > n, "expected " .. show(actual) .. " > " .. n)
	end
	function e.toBeGreaterThanOrEqual(n: number)
		check(type(actual) == "number" and actual >= n, "expected " .. show(actual) .. " >= " .. n)
	end
	function e.toBeLessThan(n: number)
		check(type(actual) == "number" and actual < n, "expected " .. show(actual) .. " < " .. n)
	end
	function e.toBeLessThanOrEqual(n: number)
		check(type(actual) == "number" and actual <= n, "expected " .. show(actual) .. " <= " .. n)
	end
	function e.toBeA(typeName: string)
		check(typeof(actual) == typeName, "expected typeof " .. typeName .. ", got " .. typeof(actual))
	end
	if not negate then
		e.never = makeExpectation(actual, true)
	end
	return e :: Expectation
end

export type TestApi = {
	describe: (name: string, fn: () -> ()) -> (),
	it: (name: string, fn: () -> ()) -> (),
	skip: (name: string, fn: (() -> ())?) -> (),
	itIf: (condition: boolean, name: string, fn: () -> ()) -> (),
	beforeEach: (fn: () -> ()) -> (),
	afterEach: (fn: () -> ()) -> (),
	expect: (actual: any) -> Expectation,
	fail: (message: string) -> (),
}

export type SpecModule = {
	name: string,
	fn: (T: TestApi, use: (path: string) -> any, ctx: SpecContext) -> (),
}

local function clock(): number
	return os.clock()
end

local function collect(spec: SpecModule, use: (string) -> any, ctx: SpecContext): Suite
	local root = newSuite(spec.name, nil)
	local current = root
	local api: TestApi = {
		describe = function(name, fn)
			local s = newSuite(name, current)
			table.insert(current.children, s)
			local prev = current
			current = s
			fn()
			current = prev
		end,
		it = function(name, fn)
			table.insert(current.tests, { name = name, fn = fn, skip = false })
		end,
		skip = function(name, fn)
			table.insert(current.tests, { name = name, fn = fn, skip = true })
		end,
		itIf = function(condition, name, fn)
			table.insert(current.tests, { name = name, fn = fn, skip = not condition })
		end,
		beforeEach = function(fn)
			table.insert(current.beforeEach, fn)
		end,
		afterEach = function(fn)
			table.insert(current.afterEach, fn)
		end,
		expect = function(actual)
			return makeExpectation(actual, false)
		end,
		fail = function(message)
			fail(message)
		end,
	}
	local ok, err = (pcall :: any)(spec.fn, api, use, ctx)
	if not ok then
		table.insert(root.tests, {
			name = "<spec setup>",
			fn = function()
				error("spec module failed while collecting tests: " .. tostring(err), 0)
			end,
			skip = false,
		})
	end
	return root
end

local function hooksFor(suite: Suite, kind: "beforeEach" | "afterEach"): { () -> () }
	local chain = {}
	local s: Suite? = suite
	while s do
		table.insert(chain, 1, s)
		s = s.parent
	end
	local hooks = {}
	if kind == "beforeEach" then
		for _, x in ipairs(chain) do
			for _, h in ipairs(x.beforeEach) do
				table.insert(hooks, h)
			end
		end
	else
		for i = #chain, 1, -1 do
			for _, h in ipairs(chain[i].afterEach) do
				table.insert(hooks, h)
			end
		end
	end
	return hooks
end

local function errorText(err: any): string
	if type(err) == "table" and getmetatable(err) == AssertionError then
		return err.message
	end
	return tostring(err)
end

local function runSuite(suite: Suite, prefix: string, filter: string?, report: RunReport)
	local fullName = if prefix == "" then suite.name else prefix .. " > " .. suite.name
	for _, test in ipairs(suite.tests) do
		local name = fullName .. " > " .. test.name
		if filter and not string.find(string.lower(name), string.lower(filter), 1, true) then
			continue
		end
		if test.skip or test.fn == nil then
			report.skipped += 1
			table.insert(report.results, { name = name, status = "skipped", duration = 0 })
			continue
		end
		local started = clock()
		local okAll, message = true, nil
		for _, h in ipairs(hooksFor(suite, "beforeEach")) do
			local ok, err = (xpcall :: any)(h, function(e: any): string
				return errorText(e) .. "\n" .. debug.traceback(nil, 2)
			end)
			if not ok then
				okAll, message = false, "beforeEach failed: " .. tostring(err)
				break
			end
		end
		if okAll then
			local ok, err = (xpcall :: any)(test.fn, function(e: any): string
				if type(e) == "table" and getmetatable(e) == AssertionError then
					return e.message .. "\n" .. debug.traceback(nil, 2)
				end
				return tostring(e) .. "\n" .. debug.traceback(nil, 2)
			end)
			if not ok then
				okAll, message = false, tostring(err)
			end
		end
		for _, h in ipairs(hooksFor(suite, "afterEach")) do
			local ok, err = (pcall :: any)(h)
			if not ok and okAll then
				okAll, message = false, "afterEach failed: " .. errorText(err)
			end
		end
		local result: TestResult = {
			name = name,
			status = if okAll then "passed" else "failed",
			message = message,
			duration = clock() - started,
		}
		if okAll then
			report.passed += 1
		else
			report.failed += 1
		end
		table.insert(report.results, result)
	end
	for _, child in ipairs(suite.children) do
		runSuite(child, fullName, filter, report)
	end
end

--[[
	Runs spec modules and returns a report. Never throws for failing tests.
	`filter` (optional) runs only tests whose full name contains the substring (case-insensitive).
]]
function TestFramework.run(specs: { SpecModule }, use: (string) -> any, ctx: SpecContext, filter: string?): RunReport
	local report: RunReport = { passed = 0, failed = 0, skipped = 0, results = {} }
	for _, spec in ipairs(specs) do
		local suite = collect(spec, use, ctx)
		runSuite(suite, "", filter, report)
	end
	return report
end

-- Formats a report as plain text lines (used by both runners).
function TestFramework.format(report: RunReport, verbose: boolean?): string
	local lines = {}
	for _, r in ipairs(report.results) do
		if r.status == "failed" then
			table.insert(lines, "FAIL  " .. r.name)
			table.insert(lines, "      " .. string.gsub(tostring(r.message), "\n", "\n      "))
		elseif verbose then
			table.insert(lines, (if r.status == "passed" then "ok    " else "skip  ") .. r.name)
		end
	end
	table.insert(lines, string.format("%d passed, %d failed, %d skipped", report.passed, report.failed, report.skipped))
	return table.concat(lines, "\n")
end

return TestFramework
