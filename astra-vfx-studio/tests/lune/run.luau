--[[
	Test runner (Lune).

	Usage (from the astra-vfx-studio directory):
		lune run tests/lune/run.luau                 -- run all specs
		lune run tests/lune/run.luau -- Json         -- only tests whose full name contains "Json"
		lune run tests/lune/run.luau -- --verbose    -- list every test

	Loads the Rojo project (default.project.json) into a Lune Instance tree, installs engine fakes, then runs
	every ModuleScript named "*.spec" under Tests.Specs with tests/framework/TestFramework.luau.
]]

local process = require("@lune/process")
local stdio = require("@lune/stdio")

local Loader = require("./Loader")
local Fakes = require("./Fakes")
local PluginFakes = require("./PluginFakes")

local filter: string? = nil
local verbose = false
for _, arg in process.args do
	if arg == "--verbose" or arg == "-v" then
		verbose = true
	elseif string.sub(arg, 1, 2) ~= "--" then
		filter = arg
	end
end

local fakes = Fakes.install()
local loader = Loader.new(process.cwd)
-- Studio-only globals used by plugin code (stand-ins, see PluginFakes)
loader.globals.DockWidgetPluginGuiInfo = PluginFakes.DockWidgetPluginGuiInfo
loader.globals.TweenInfo = PluginFakes.TweenInfo
local TestFramework = loader:use("Tests.Framework")

local specs = {}
for _, inst in loader:resolve("Tests.Specs"):GetDescendants() do
	if inst:IsA("ModuleScript") and string.match(inst.Name, "%.spec$") then
		local ok, fnOrErr = pcall(function()
			return loader:require(inst)
		end)
		if ok and type(fnOrErr) == "function" then
			table.insert(specs, { name = string.gsub(inst.Name, "%.spec$", ""), fn = fnOrErr })
		else
			table.insert(specs, {
				name = inst.Name,
				fn = function(T)
					T.it("loads", function()
						error("spec module failed to load: " .. tostring(fnOrErr), 0)
					end)
				end,
			})
		end
	end
end
table.sort(specs, function(a, b)
	return a.name < b.name
end)

local report = TestFramework.run(specs, function(path: string)
	return loader:use(path)
end, { environment = "lune", fakes = fakes, loader = loader, plugin = PluginFakes }, filter)

local text = TestFramework.format(report, verbose)
if report.failed > 0 then
	stdio.write(stdio.color("red") .. text .. stdio.color("reset") .. "\n")
	process.exit(1)
else
	stdio.write(stdio.color("green") .. text .. stdio.color("reset") .. "\n")
	process.exit(0)
end
