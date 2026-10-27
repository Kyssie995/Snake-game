--!strict
--[[
	Env — the single, lazy gateway from Runtime/Core to engine services and the run context.

	Runtime/Core modules never call game:GetService at load time; they ask Env when they need a service, which
	lets tests (and the CLI) substitute fakes with Env.override and keeps modules loadable without a DataModel.

	Interpretation notes (docs/MODULE_CONTRACTS.md §4):
	  * getService: overrides win; otherwise `game:GetService(name)` is called directly (no pcall on this fast
	    path, so an invalid service name errors like it does in Roblox) and the result is cached per name.
	    Without a DataModel (`game` is nil) getService errors with a clear message.
	  * override(name, nil) removes a single override; reset() removes all overrides and the service cache.
	  * isStudio/isRunning/isClient/isServer call the RunService method through getService (so an overridden
	    RunService is honoured) inside pcall and return true only if the call succeeded and returned exactly
	    `true`. Any failure (no DataModel, a fake without the method, a throwing method) yields false. They are
	    not cached because IsRunning changes when a Studio simulation starts or stops.
]]

local Env = {}

local overrides: { [string]: any } = {}
local cache: { [string]: Instance } = {}

-- Returns the service `name`: the override if one is set, else game:GetService(name) (cached).
function Env.getService(name: string): Instance
	local overridden = overrides[name]
	if overridden ~= nil then
		return overridden
	end
	local cached: Instance? = cache[name]
	if cached ~= nil then
		return cached
	end
	if type(name) ~= "string" then
		error("Env.getService: service name must be a string, got " .. typeof(name), 2)
	end
	local dataModel: DataModel? = game
	if dataModel == nil then
		error("Env.getService: no DataModel (game) available to provide service '" .. name .. "'", 2)
	end
	local service = dataModel:GetService(name)
	cache[name] = service
	return service
end

-- Replaces the service `name` with `value` (tests, CLI). `nil` removes the override.
function Env.override(name: string, value: any)
	if type(name) ~= "string" then
		error("Env.override: service name must be a string, got " .. typeof(name), 2)
	end
	overrides[name] = value
end

-- Removes every override and forgets cached services.
function Env.reset()
	table.clear(overrides)
	table.clear(cache)
end

local function runServiceFlag(method: string): boolean
	local ok, result = pcall(function(): any
		local runService: any = Env.getService("RunService")
		return runService[method](runService)
	end)
	return ok and result == true
end

-- RunService:IsStudio(), false if unavailable.
function Env.isStudio(): boolean
	return runServiceFlag("IsStudio")
end

-- RunService:IsRunning(), false if unavailable.
function Env.isRunning(): boolean
	return runServiceFlag("IsRunning")
end

-- RunService:IsClient(), false if unavailable.
function Env.isClient(): boolean
	return runServiceFlag("IsClient")
end

-- RunService:IsServer(), false if unavailable.
function Env.isServer(): boolean
	return runServiceFlag("IsServer")
end

-- Monotonic clock in seconds (os.clock()); for measurements only, never for effect logic.
function Env.now(): number
	return os.clock()
end

return Env
