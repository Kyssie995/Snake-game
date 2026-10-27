--[[
	Loader (Lune only)

	Rebuilds the plugin's Rojo project as a tree of real Lune `roblox` Instances (Folder, ModuleScript, Script, ...)
	following Rojo's file conventions, and provides a Roblox-compatible `require(moduleScript)`.

	Why: the source code uses classic Roblox instance requires (`require(script.Parent.Json)`), so tests and the
	CLI can only load it inside an Instance tree. Lune's Instances validate property names and value types against
	the Roblox reflection database, which turns many "invented API" mistakes into test failures.

	Supported Rojo rules (subset used by this project):
	  dir/                -> Folder (or the module itself if it contains init.luau / init.server.luau / init.client.luau)
	  X.luau / X.lua      -> ModuleScript
	  X.server.luau       -> Script, X.client.luau -> LocalScript
	  X.json              -> ModuleScript returning the decoded JSON (Rojo "JSON module")
	  X.txt               -> StringValue
	  *.meta.json, *.model.json, *.project.json -> ignored
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Instance = roblox.Instance

local Loader = {}
Loader.__index = Loader

export type Loader = typeof(setmetatable(
	{} :: {
		projectDir: string,
		root: any,
		paths: { [any]: string },
		jsonModules: { [any]: any },
		cache: { [any]: any },
		loading: { [any]: boolean },
		globals: { [string]: any },
		game: any,
	},
	Loader
))

local BUILTINS = {
	"assert",
	"error",
	"getmetatable",
	"ipairs",
	"next",
	"pairs",
	"pcall",
	"print",
	"rawequal",
	"rawget",
	"rawlen",
	"rawset",
	"select",
	"setmetatable",
	"tonumber",
	"tostring",
	"type",
	"typeof",
	"unpack",
	"xpcall",
	"gcinfo",
	"newproxy",
	"coroutine",
	"math",
	"string",
	"table",
	"os",
	"debug",
	"utf8",
	"bit32",
	"buffer",
	"vector",
}

local DATATYPES = {
	"Axes",
	"BrickColor",
	"CFrame",
	"Color3",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"Content",
	"Enum",
	"Faces",
	"Font",
	"Instance",
	"NumberRange",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"PhysicalProperties",
	"Ray",
	"Rect",
	"Region3",
	"Region3int16",
	"UDim",
	"UDim2",
	"Vector2",
	"Vector2int16",
	"Vector3",
	"Vector3int16",
}

local function join(a: string, b: string): string
	if a == "" then
		return b
	end
	return a .. "/" .. b
end

local function endsWith(s: string, suffix: string): boolean
	return #s >= #suffix and string.sub(s, -#suffix) == suffix
end

local function stripSuffix(s: string, suffix: string): string
	return string.sub(s, 1, #s - #suffix)
end

local function baseGlobals(game: any): { [string]: any }
	local g: { [string]: any } = {}
	local env = getfenv and getfenv(0) or _G
	for _, name in BUILTINS do
		g[name] = (env :: any)[name]
	end
	for _, name in DATATYPES do
		g[name] = (roblox :: any)[name]
	end
	g.task = task
	g.warn = function(...)
		print("[warn]", ...)
	end
	g.tick = os.clock
	g.time = os.clock
	g.game = game
	g.workspace = game:GetService("Workspace")
	g._G = {}
	g.shared = {}
	return g
end

function Loader.new(projectDir: string, projectFile: string?): Loader
	local self = setmetatable({
		projectDir = projectDir,
		root = nil :: any,
		paths = {},
		jsonModules = {},
		cache = {},
		loading = {},
		globals = {},
		game = Instance.new("DataModel"),
	}, Loader)
	self.globals = baseGlobals(self.game)
	local projectPath = join(projectDir, projectFile or "default.project.json")
	local project = serde.decode("json", fs.readFile(projectPath))
	self.root = self:_buildNode(project.name, project.tree)
	return self
end

-- Builds the instance for a project tree node ($path / $className / children).
function Loader._buildNode(self: Loader, name: string, node: { [string]: any }): any
	local inst
	if node["$path"] then
		inst = self:_buildPath(name, join(self.projectDir, node["$path"]))
	else
		inst = Instance.new(node["$className"] or "Folder")
		inst.Name = name
	end
	for key, child in pairs(node) do
		if string.sub(key, 1, 1) ~= "$" then
			local c = self:_buildNode(key, child)
			c.Parent = inst
		end
	end
	return inst
end

local INIT_FILES = {
	{ "init.luau", "ModuleScript" },
	{ "init.lua", "ModuleScript" },
	{ "init.server.luau", "Script" },
	{ "init.server.lua", "Script" },
	{ "init.client.luau", "LocalScript" },
	{ "init.client.lua", "LocalScript" },
}

local SCRIPT_SUFFIXES = {
	{ ".server.luau", "Script" },
	{ ".server.lua", "Script" },
	{ ".client.luau", "LocalScript" },
	{ ".client.lua", "LocalScript" },
	{ ".luau", "ModuleScript" },
	{ ".lua", "ModuleScript" },
}

local IGNORED_SUFFIXES = { ".meta.json", ".model.json", ".project.json" }

function Loader._buildPath(self: Loader, name: string, path: string): any
	if fs.isDir(path) then
		local inst
		local initFile = nil
		for _, entry in INIT_FILES do
			if fs.isFile(join(path, entry[1])) then
				inst = Instance.new(entry[2])
				initFile = entry[1]
				inst.Source = fs.readFile(join(path, entry[1]))
				self.paths[inst] = join(path, entry[1])
				break
			end
		end
		if not inst then
			inst = Instance.new("Folder")
			self.paths[inst] = path
		end
		inst.Name = name
		local entries = fs.readDir(path)
		table.sort(entries)
		for _, entry in entries do
			if entry ~= initFile and string.sub(entry, 1, 1) ~= "." then
				local child = self:_buildEntry(join(path, entry), entry)
				if child then
					child.Parent = inst
				end
			end
		end
		return inst
	end
	local inst = self:_buildEntry(path, string.match(path, "[^/]+$") :: string)
	if inst == nil then
		error("Loader: unsupported file " .. path)
	end
	inst.Name = name
	return inst
end

function Loader._buildEntry(self: Loader, path: string, entry: string): any?
	if fs.isDir(path) then
		return self:_buildPath(entry, path)
	end
	for _, suffix in IGNORED_SUFFIXES do
		if endsWith(entry, suffix) then
			return nil
		end
	end
	for _, s in SCRIPT_SUFFIXES do
		if endsWith(entry, s[1]) then
			local inst = Instance.new(s[2])
			inst.Name = stripSuffix(entry, s[1])
			inst.Source = fs.readFile(path)
			self.paths[inst] = path
			return inst
		end
	end
	if endsWith(entry, ".json") then
		local inst = Instance.new("ModuleScript")
		inst.Name = stripSuffix(entry, ".json")
		local text = fs.readFile(path)
		inst.Source = "-- JSON module (generated by Rojo from " .. entry .. ")\nreturn nil"
		self.jsonModules[inst] = serde.decode("json", text)
		self.paths[inst] = path
		return inst
	end
	if endsWith(entry, ".txt") then
		local inst = Instance.new("StringValue")
		inst.Name = stripSuffix(entry, ".txt")
		inst.Value = fs.readFile(path)
		self.paths[inst] = path
		return inst
	end
	return nil
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local t = {}
	for k, x in pairs(v) do
		t[k] = deepCopy(x)
	end
	return t
end

-- Roblox-compatible require for ModuleScript instances of this tree.
function Loader.require(self: Loader, module: any): any
	if typeof(module) ~= "Instance" then
		error("Loader.require expects a ModuleScript instance, got " .. typeof(module), 2)
	end
	if not module:IsA("ModuleScript") then
		error("Attempted to require a non-ModuleScript: " .. module:GetFullName(), 2)
	end
	local cached = self.cache[module]
	if cached ~= nil then
		return cached.value
	end
	if self.jsonModules[module] ~= nil then
		local value = deepCopy(self.jsonModules[module])
		self.cache[module] = { value = value }
		return value
	end
	if self.loading[module] then
		error("Cyclic require detected while loading " .. module:GetFullName(), 2)
	end
	self.loading[module] = true
	local fn = self:_compile(module)
	local results = table.pack(fn())
	self.loading[module] = nil
	if results.n ~= 1 then
		error("Module " .. module:GetFullName() .. " did not return exactly one value", 2)
	end
	self.cache[module] = { value = results[1] }
	return results[1]
end

function Loader._compile(self: Loader, scriptInstance: any, extraGlobals: { [string]: any }?): () -> ...any
	local env = setmetatable({
		script = scriptInstance,
		require = function(target: any)
			return self:require(target)
		end,
	}, { __index = self.globals })
	if extraGlobals then
		for k, v in pairs(extraGlobals) do
			(env :: any)[k] = v
		end
	end
	local debugName = self.paths[scriptInstance] or scriptInstance:GetFullName()
	return luau.load(scriptInstance.Source, {
		debugName = debugName,
		environment = env,
		injectGlobals = false,
	})
end

-- Runs a Script/LocalScript instance (used for plugin smoke tests). Extra globals (e.g. `plugin`) can be passed.
function Loader.runScript(self: Loader, scriptInstance: any, extraGlobals: { [string]: any }?)
	local fn = self:_compile(scriptInstance, extraGlobals)
	return fn()
end

-- Resolves a dotted path relative to the tree root, e.g. "AstraVFX.Core.Json".
function Loader.resolve(self: Loader, path: string): any
	local node = self.root
	for part in string.gmatch(path, "[^%.]+") do
		local child = node:FindFirstChild(part)
		if child == nil then
			error(
				"Loader.resolve: '" .. part .. "' not found under " .. node:GetFullName() .. " (path " .. path .. ")",
				2
			)
		end
		node = child
	end
	return node
end

function Loader.use(self: Loader, path: string): any
	return self:require(self:resolve(path))
end

function Loader.fileOf(self: Loader, inst: any): string?
	return self.paths[inst]
end

return Loader
