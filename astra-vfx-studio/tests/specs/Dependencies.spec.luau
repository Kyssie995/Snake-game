--!strict
--[[
	Dependencies — static dependency rules of docs/ARCHITECTURE.md §2, checked on the Lune Instance tree (the Rojo
	project as the Loader builds it; every ModuleScript keeps its Source).

	For every ModuleScript under AstraVFX (src/Runtime, the module itself included) the Source is lexed (comments
	and string literals removed, so documentation examples such as `require(ReplicatedStorage.AstraVFX)` do not
	count) and every `require` is classified:
	  * `require(script.<Name|Parent>...)`  a static instance path: resolved from the module's own instance; the
	                                        target must exist, be a ModuleScript and lie inside AstraVFX
	  * `(require :: any)(<name>)`          a dynamic require: allowed only for the reviewed cases in DYNAMIC
	  * anything else (string requires, `require(game...)`, `require` passed around) is a violation.
	Then the static edges are checked against the layer order inside the runtime ("a module may only require
	modules to its left"): Types, Constants -> Signal, Random, Env, Json -> Codec, Easing -> Curves -> Timeline ->
	Components/* -> Graph -> Migration -> Validation -> Quality -> Compiler -> Builder -> Player -> Scheduler, Pool
	-> Net -> runtime init. Modules inside one package (Components/*, Graph/*) may require each other.

	The same scanner checks src/Authoring (may use Runtime, Authoring and Presets, never Plugin).
]]
return function(T: any, _use: (string) -> any, ctx: any)
	local expect = T.expect
	local isLune = ctx.environment == "lune"

	-- ─────────────────────────────────────────────────────────────────────────
	-- Lexer: Luau source -> code with comments removed and string contents blanked
	-- ─────────────────────────────────────────────────────────────────────────

	-- Length of a long bracket opening ("[[", "[=[", ...) at position i, and its level; nil when there is none.
	local function longBracket(source: string, i: number): (number?, number?)
		local level = 0
		local j = i + 1
		while string.sub(source, j, j) == "=" do
			level += 1
			j += 1
		end
		if string.sub(source, j, j) == "[" then
			return j - i + 1, level
		end
		return nil, nil
	end

	local function stripCode(source: string): string
		local out: { string } = {}
		local i = 1
		local n = #source
		while i <= n do
			local c = string.sub(source, i, i)
			if c == "-" and string.sub(source, i + 1, i + 1) == "-" then
				local opening, level = nil, nil
				if string.sub(source, i + 2, i + 2) == "[" then
					opening, level = longBracket(source, i + 2)
				end
				if opening and level then
					local close = "]" .. string.rep("=", level) .. "]"
					local e = string.find(source, close, i + 2 + opening, true)
					i = if e then e + #close else n + 1
				else
					local e = string.find(source, "\n", i, true)
					i = if e then e else n + 1
				end
				table.insert(out, " ")
			elseif c == "[" then
				local opening, level = longBracket(source, i)
				if opening and level then
					local close = "]" .. string.rep("=", level) .. "]"
					local e = string.find(source, close, i + opening, true)
					i = if e then e + #close else n + 1
					table.insert(out, '""')
				else
					table.insert(out, c)
					i += 1
				end
			elseif c == '"' or c == "'" or c == "`" then
				local j = i + 1
				while j <= n do
					local d = string.sub(source, j, j)
					if d == "\\" then
						j += 2
					elseif d == c then
						break
					elseif d == "\n" and c ~= "`" then
						break -- unterminated: let the syntax check report it
					else
						j += 1
					end
				end
				table.insert(out, '""')
				i = j + 1
			else
				table.insert(out, c)
				i += 1
			end
		end
		return table.concat(out)
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- require scanner
	-- ─────────────────────────────────────────────────────────────────────────

	type Require = {
		kind: "static" | "dynamic" | "invalid",
		expression: string, -- argument text (whitespace removed)
		line: number,
	}

	local function lineAt(code: string, position: number): number
		local _, count = string.gsub(string.sub(code, 1, position), "\n", "")
		return count + 1
	end

	-- Text of the balanced (...) group that starts at `open` (an "(" character), without the parentheses.
	local function group(code: string, open: number): string?
		local depth = 0
		for j = open, #code do
			local c = string.sub(code, j, j)
			if c == "(" then
				depth += 1
			elseif c == ")" then
				depth -= 1
				if depth == 0 then
					return string.sub(code, open + 1, j - 1)
				end
			end
		end
		return nil
	end

	local function scan(source: string): { Require }
		local code = stripCode(source)
		local out: { Require } = {}
		local position = 1
		while true do
			local s, e = string.find(code, "%f[%w_]require%f[^%w_]", position)
			if s == nil or e == nil then
				break
			end
			position = e + 1
			local line = lineAt(code, s)
			local after = string.match(code, "^%s*()%(", e + 1)
			local castClose = string.match(code, "^%s*::%s*any%s*%)%s*()%(", e + 1)
			local before = string.match(string.sub(code, 1, s - 1), "%(%s*$")
			local argument: string? = nil
			local kind: "static" | "dynamic" | "invalid" = "invalid"
			if after then
				argument = group(code, after :: number)
				kind = "static"
			elseif castClose and before then
				argument = group(code, castClose :: number)
				kind = "dynamic"
			end
			local expression = if argument then (string.gsub(argument, "%s+", "")) else ""
			if kind == "static" and not string.match(expression, "^script[%.%w_]*$") then
				kind = "invalid"
			end
			table.insert(out, { kind = kind, expression = expression, line = line })
		end
		return out
	end

	-- Resolves "script.Parent.X.Y" from `module`; nil when a step does not exist.
	local function resolve(module: Instance, expression: string): Instance?
		local node: Instance? = module
		local first = true
		for segment in string.gmatch(expression, "[^%.]+") do
			if first then
				first = false
				if segment ~= "script" then
					return nil
				end
			elseif node == nil then
				return nil
			elseif segment == "Parent" then
				node = (node :: Instance).Parent
			else
				node = (node :: Instance):FindFirstChild(segment)
			end
		end
		return node
	end

	local function inside(inst: Instance, root: Instance): boolean
		return inst == root or inst:IsDescendantOf(root)
	end

	local function modulesUnder(root: Instance): { ModuleScript }
		local out: { ModuleScript } = {}
		if root:IsA("ModuleScript") then
			table.insert(out, root :: ModuleScript)
		end
		for _, d in root:GetDescendants() do
			if d:IsA("ModuleScript") then
				table.insert(out, d :: ModuleScript)
			end
		end
		return out
	end

	-- Dotted path of `inst` below `base` (default: the tree root), e.g. "AstraVFX.Core.Json".
	local function pathOf(inst: Instance, base: Instance?): string
		local parts: { string } = {}
		local node: Instance? = inst
		local root = base or ctx.loader.root
		while node and node ~= root do
			table.insert(parts, 1, (node :: Instance).Name)
			node = (node :: Instance).Parent
		end
		return table.concat(parts, ".")
	end

	-- Reviewed dynamic requires: { [module path] = { [argument] = reason } }.
	local DYNAMIC: { [string]: { [string]: string } } = {
		["AstraVFX"] = {
			inst = "Register(ModuleScript) loads an effect DEFINITION module given by game code (data, not a code dependency)",
		},
		["AstraVFX.Net"] = {
			parent = "lazy back-reference to the runtime API (local parent = script.Parent), avoids a require cycle",
		},
		["AstraVFX.Core.Components"] = {
			module = "registry: requires its own child descriptor modules (script:GetChildren())",
		},
	}

	-- ─────────────────────────────────────────────────────────────────────────
	-- Layer order (ARCHITECTURE §2)
	-- ─────────────────────────────────────────────────────────────────────────

	local RANK: { [string]: number } = {
		Types = 1,
		Constants = 1,
		Signal = 2,
		Random = 2,
		Env = 2,
		Json = 2,
		Codec = 3,
		Easing = 3,
		Curves = 4,
		Timeline = 5,
		Components = 6,
		Graph = 7,
		Migration = 8,
		Validation = 9,
		Quality = 10,
		Compiler = 11,
		Builder = 12,
		Player = 13,
		Scheduler = 14,
		Pool = 14,
		Net = 15,
		AstraVFX = 16,
	}

	-- Layer key of a runtime module: the Core module or package it belongs to ("Components" for every
	-- descriptor), "Net" or "AstraVFX" (init).
	local function layerOf(path: string): string?
		if path == "AstraVFX" then
			return "AstraVFX"
		end
		local core = string.match(path, "^AstraVFX%.Core%.([%w_]+)")
		if core then
			return core
		end
		return string.match(path, "^AstraVFX%.([%w_]+)$")
	end

	type Edge = { from: string, to: string, line: number }

	-- Static edges of every module under `root` (an "AstraVFX" module) + the rule violations found on the way.
	local function runtimeEdges(root: Instance, dynamic: { [string]: { [string]: string } }): ({ Edge }, { string })
		local base = root.Parent
		local function at(inst: Instance): string
			return pathOf(inst, base)
		end
		local edges: { Edge } = {}
		local problems: { string } = {}
		local seenDynamic: { [string]: boolean } = {}
		for _, module in modulesUnder(root) do
			local path = at(module)
			for _, r in scan(module.Source) do
				local where = path .. ":" .. r.line
				if r.kind == "static" then
					local target = resolve(module, r.expression)
					if target == nil then
						table.insert(problems, where .. ": require(" .. r.expression .. ") does not resolve")
					elseif not inside(target, root) then
						table.insert(
							problems,
							where .. ": require(" .. r.expression .. ") leaves AstraVFX (" .. at(target) .. ")"
						)
					elseif not target:IsA("ModuleScript") then
						table.insert(problems, where .. ": require(" .. r.expression .. ") is not a ModuleScript")
					else
						table.insert(edges, { from = path, to = at(target), line = r.line })
					end
				elseif r.kind == "dynamic" then
					local allowed = dynamic[path]
					if allowed == nil or allowed[r.expression] == nil then
						table.insert(
							problems,
							where .. ": unreviewed dynamic require (require :: any)(" .. r.expression .. ")"
						)
					else
						seenDynamic[path .. "|" .. r.expression] = true
					end
				else
					table.insert(
						problems,
						where .. ": require must be require(script...), got require(" .. r.expression .. ")"
					)
				end
			end
		end
		for path, list in dynamic do
			for expression in list do
				if not seenDynamic[path .. "|" .. expression] then
					table.insert(problems, "stale DYNAMIC entry " .. path .. " (" .. expression .. ")")
				end
			end
		end
		return edges, problems
	end

	-- Layer-order violations of `edges`.
	local function layerProblems(edges: { Edge }): { string }
		local problems: { string } = {}
		for _, edge in edges do
			local from, to = layerOf(edge.from), layerOf(edge.to)
			local where = edge.from .. ":" .. edge.line .. " -> " .. edge.to
			if from == nil or RANK[from] == nil then
				table.insert(problems, where .. ": " .. edge.from .. " has no place in the layer order")
			elseif to == nil or RANK[to] == nil then
				table.insert(problems, where .. ": " .. edge.to .. " has no place in the layer order")
			elseif from ~= to and RANK[to] >= RANK[from] then
				table.insert(problems, where .. ": " .. to .. " is not to the left of " .. from)
			end
		end
		return problems
	end

	local function runtimeRoot(): Instance
		return ctx.loader:resolve("AstraVFX")
	end

	T.describe("Dependencies", function()
		T.it("the lexer ignores comments and strings and finds every require form", function()
			local found = scan([==[
				--[[ require(game.ReplicatedStorage.X) ]]
				-- require(workspace.Y)
				local a = "require(script.Nope)"
				local b = [=[ require(script.AlsoNope) ]=]
				local Json = require(script.Parent.Json)
				local Deep = require( script.Parent.Parent.Core
					.Types )
				local value = (require :: any)(inst)
				local bad = require("@pkg/thing")
				local worse = require(game:GetService("ReplicatedStorage").X)
				local passed = pcall(require, x)
			]==])
			local kinds: { string } = {}
			for _, r in found do
				table.insert(kinds, r.kind .. " " .. r.expression)
			end
			expect(kinds).toEqual({
				"static script.Parent.Json",
				"static script.Parent.Parent.Core.Types",
				"dynamic inst",
				'invalid ""',
				'invalid game:GetService("").X',
				"invalid ",
			})
		end)

		T.itIf(isLune, "the checks catch planted violations (a fake runtime tree)", function()
			local base = Instance.new("Folder")
			local outside = Instance.new("ModuleScript")
			outside.Name = "Outside"
			outside.Parent = base
			local runtime = Instance.new("ModuleScript")
			runtime.Name = "AstraVFX"
			runtime.Source = "local Player = require(script.Core.Player)\nreturn {}"
			runtime.Parent = base
			local core = Instance.new("Folder")
			core.Name = "Core"
			core.Parent = runtime
			local function module(name: string, source: string)
				local m = Instance.new("ModuleScript")
				m.Name = name
				m.Source = source
				m.Parent = core
			end
			module("Json", "local X = require(script.Parent.Parent.Parent.Outside)\nreturn {}")
			module("Codec", "local P = require(script.Parent.Player)\nlocal J = require(script.Parent.Json)\nreturn {}")
			module(
				"Player",
				'local S = require("@self/Scheduler")\nlocal M = require(script.Parent.Missing)\nreturn {}'
			)
			module("Pool", "local D = (require :: any)(thing)\nreturn {}")
			local edges, problems = runtimeEdges(runtime, { AstraVFX = { gone = "stale" } })
			local text = table.concat(problems, "\n")
			expect(text).toContain("AstraVFX.Core.Json:1: require(script.Parent.Parent.Parent.Outside) leaves AstraVFX")
			expect(text).toContain('AstraVFX.Core.Player:1: require must be require(script...), got require("")')
			expect(text).toContain("AstraVFX.Core.Player:2: require(script.Parent.Missing) does not resolve")
			expect(text).toContain("AstraVFX.Core.Pool:1: unreviewed dynamic require (require :: any)(thing)")
			expect(text).toContain("stale DYNAMIC entry AstraVFX (gone)")
			expect(#problems).toBe(5)
			local layers = table.concat(layerProblems(edges), "\n")
			expect(layers).toContain(
				"AstraVFX.Core.Codec:1 -> AstraVFX.Core.Player: Player is not to the left of Codec"
			)
			expect(#layerProblems(edges)).toBe(1) -- Codec -> Json and AstraVFX -> Player are fine
			base:Destroy()
		end)

		T.itIf(isLune, "every ModuleScript under AstraVFX requires only ModuleScripts under AstraVFX", function()
			local edges, problems = runtimeEdges(runtimeRoot(), DYNAMIC)
			if #problems > 0 then
				T.fail(#problems .. " dependency problems:\n  " .. table.concat(problems, "\n  "))
			end
			-- the scan saw the whole runtime
			expect(#edges > 100).toBe(true)
			local modules = modulesUnder(runtimeRoot())
			expect(#modules >= 40).toBe(true)
		end)

		T.itIf(isLune, "runtime modules only require modules to their left in the layer order", function()
			local edges = runtimeEdges(runtimeRoot(), DYNAMIC)
			local problems = layerProblems(edges)
			if #problems > 0 then
				T.fail(#problems .. " layer violations:\n  " .. table.concat(problems, "\n  "))
			end
		end)

		T.itIf(isLune, "Authoring never requires the Plugin (and resolves every static require)", function()
			local root = ctx.loader.root
			local authoring = root:FindFirstChild("Authoring")
			if authoring == nil then
				return
			end
			local plugin = root:FindFirstChild("Plugin")
			local problems: { string } = {}
			for _, module in modulesUnder(authoring) do
				local path = pathOf(module)
				for _, r in scan(module.Source) do
					local where = path .. ":" .. r.line
					if r.kind == "static" then
						local target = resolve(module, r.expression)
						if target == nil then
							table.insert(problems, where .. ": require(" .. r.expression .. ") does not resolve")
						elseif plugin and inside(target, plugin) then
							table.insert(
								problems,
								where .. ": Authoring requires the Plugin (" .. pathOf(target) .. ")"
							)
						end
					elseif r.kind == "invalid" then
						table.insert(
							problems,
							where .. ": require must be require(script...), got require(" .. r.expression .. ")"
						)
					end
				end
			end
			if #problems > 0 then
				T.fail(#problems .. " dependency problems:\n  " .. table.concat(problems, "\n  "))
			end
		end)
	end)
end
