--[[ Compiles every .luau file under the given directories with Luau (via Lune) and reports syntax errors.
     Usage: lune run tools/syntax-check.luau -- src tests tools ]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local failures = 0
local count = 0
local function walk(dir: string)
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path)
		elseif string.match(entry, "%.luau$") or string.match(entry, "%.lua$") then
			count += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failures += 1
				print(path .. ": " .. tostring(err))
			end
		end
	end
end
local dirs = if #process.args > 0 then process.args else { "src", "tests", "tools" }
for _, d in dirs do
	if fs.isDir(d) then
		walk(d)
	end
end
print(string.format("syntax-check: %d files, %d with errors", count, failures))
process.exit(if failures > 0 then 1 else 0)
