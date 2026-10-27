--!strict
return function(T: any, use: (string) -> any, ctx: any)
	local Env = use("AstraVFX.Core.Env")
	local isLune = ctx.environment == "lune"

	-- Fake RunService whose flags can be set per test; methods check that they are called with `self`.
	local function fakeRunService(flags: { [string]: any }): any
		local fake: any = { calls = 0 }
		for _, method in { "IsStudio", "IsRunning", "IsClient", "IsServer" } do
			fake[method] = function(self: any)
				assert(self == fake, "RunService method called without self")
				fake.calls += 1
				local v = flags[method]
				if type(v) == "function" then
					return v()
				end
				return v
			end
		end
		return fake
	end

	T.describe("Env", function()
		local savedFlags: { [string]: boolean } = {}
		T.beforeEach(function()
			Env.reset()
			if ctx.fakes then
				savedFlags = table.clone(ctx.fakes.flags)
			end
		end)
		T.afterEach(function()
			Env.reset()
			if ctx.fakes then
				for k, v in savedFlags do
					ctx.fakes.flags[k] = v
				end
			end
		end)

		T.describe("getService", function()
			T.it("returns the DataModel's services", function()
				local runService = Env.getService("RunService")
				T.expect(runService).toBe(game:GetService("RunService"))
				T.expect(runService.ClassName).toBe("RunService")
				T.expect(Env.getService("Workspace")).toBe(workspace)
			end)
			T.it("returns the same instance on repeated calls", function()
				local a = Env.getService("ReplicatedStorage")
				T.expect(Env.getService("ReplicatedStorage")).toBe(a)
				T.expect(a).toBe(game:GetService("ReplicatedStorage"))
			end)
			T.it("errors for invalid service names and argument types", function()
				T.expect(function()
					Env.getService("NotAService")
				end).toThrow("NotAService")
				T.expect(function()
					Env.getService(5 :: any)
				end).toThrow("service name must be a string")
			end)
		end)

		T.describe("override / reset", function()
			T.it("prefers overrides over real services", function()
				local fake = { name = "fake" }
				Env.override("RunService", fake)
				T.expect(Env.getService("RunService")).toBe(fake)
				T.expect(Env.getService("Workspace")).toBe(workspace)
			end)
			T.it("overrides services that were already fetched (and cached)", function()
				local real = Env.getService("Players")
				local fake = { fake = true }
				Env.override("Players", fake)
				T.expect(Env.getService("Players")).toBe(fake)
				Env.override("Players", nil)
				T.expect(Env.getService("Players")).toBe(real)
			end)
			T.it("supports names that are not real services", function()
				local value = { answer = 42 }
				Env.override("MyTestService", value)
				T.expect(Env.getService("MyTestService")).toBe(value)
			end)
			T.it("removes a single override with nil", function()
				local a, b = {}, {}
				Env.override("RunService", a)
				Env.override("Workspace", b)
				Env.override("RunService", nil)
				T.expect(Env.getService("RunService")).toBe(game:GetService("RunService"))
				T.expect(Env.getService("Workspace")).toBe(b)
			end)
			T.it("reset removes every override", function()
				Env.override("RunService", {})
				Env.override("Workspace", {})
				Env.reset()
				T.expect(Env.getService("RunService")).toBe(game:GetService("RunService"))
				T.expect(Env.getService("Workspace")).toBe(workspace)
				Env.reset() -- idempotent
				T.expect(Env.getService("Workspace")).toBe(workspace)
			end)
			T.it("rejects non-string names", function()
				T.expect(function()
					Env.override(nil :: any, {})
				end).toThrow("service name must be a string")
				T.expect(function()
					Env.override({} :: any, {})
				end).toThrow("service name must be a string")
			end)
		end)

		T.describe("run context flags", function()
			T.it("reads the flags of an overridden RunService", function()
				local fake = fakeRunService({ IsStudio = true, IsRunning = false, IsClient = true, IsServer = false })
				Env.override("RunService", fake)
				T.expect(Env.isStudio()).toBe(true)
				T.expect(Env.isRunning()).toBe(false)
				T.expect(Env.isClient()).toBe(true)
				T.expect(Env.isServer()).toBe(false)
				T.expect(fake.calls).toBe(4)
			end)
			T.it("does not cache results (IsRunning changes when a simulation starts)", function()
				local flags = { IsStudio = true, IsRunning = false, IsClient = false, IsServer = true }
				Env.override("RunService", fakeRunService(flags))
				T.expect(Env.isRunning()).toBe(false)
				flags.IsRunning = true
				T.expect(Env.isRunning()).toBe(true)
				flags.IsServer = false
				T.expect(Env.isServer()).toBe(false)
			end)
			T.it("returns false when a method throws", function()
				Env.override(
					"RunService",
					fakeRunService({
						IsStudio = function()
							error("security check failed")
						end,
						IsRunning = true,
					})
				)
				T.expect(Env.isStudio()).toBe(false)
				T.expect(Env.isRunning()).toBe(true)
			end)
			T.it("returns false for missing methods and non-boolean results", function()
				Env.override("RunService", {})
				T.expect(Env.isStudio()).toBe(false)
				T.expect(Env.isRunning()).toBe(false)
				T.expect(Env.isClient()).toBe(false)
				T.expect(Env.isServer()).toBe(false)
				Env.override(
					"RunService",
					fakeRunService({ IsStudio = "yes", IsRunning = 1, IsClient = {}, IsServer = nil })
				)
				T.expect(Env.isStudio()).toBe(false)
				T.expect(Env.isRunning()).toBe(false)
				T.expect(Env.isClient()).toBe(false)
				T.expect(Env.isServer()).toBe(false)
			end)
			T.it("returns false when RunService is not a table or instance", function()
				Env.override("RunService", 5)
				T.expect(Env.isStudio()).toBe(false)
				Env.override("RunService", false)
				T.expect(Env.isClient()).toBe(false)
			end)
			T.itIf(isLune and ctx.fakes ~= nil, "reads the real RunService (engine fakes in Lune)", function()
				local flags = ctx.fakes.flags
				flags.IsStudio, flags.IsRunning, flags.IsClient, flags.IsServer = true, false, true, false
				T.expect(Env.isStudio()).toBe(true)
				T.expect(Env.isRunning()).toBe(false)
				T.expect(Env.isClient()).toBe(true)
				T.expect(Env.isServer()).toBe(false)
				flags.IsStudio, flags.IsRunning, flags.IsClient, flags.IsServer = false, true, false, true
				T.expect(Env.isStudio()).toBe(false)
				T.expect(Env.isRunning()).toBe(true)
				T.expect(Env.isClient()).toBe(false)
				T.expect(Env.isServer()).toBe(true)
			end)
			T.itIf(not isLune, "reports Studio inside Roblox Studio", function()
				T.expect(Env.isStudio()).toBe(true)
			end)
		end)

		T.describe("without a DataModel", function()
			-- Loads a fresh copy of Env with `game` removed from its environment (Lune loader internals).
			local canIsolate = isLune and ctx.loader ~= nil and ctx.loader.globals ~= nil and ctx.loader._compile ~= nil
			T.itIf(canIsolate, "errors clearly in getService and falls back to false for flags", function()
				local loader = ctx.loader
				local saved = loader.globals.game
				loader.globals.game = nil
				local ok, result = pcall(function(): any
					local fresh = loader:_compile(loader:resolve("AstraVFX.Core.Env"))()
					local okService, err = pcall(fresh.getService, "RunService")
					local studio = fresh.isStudio()
					local fake = {}
					fresh.override("RunService", fake) -- overrides still work without a DataModel
					return {
						okService = okService,
						err = tostring(err),
						studio = studio,
						overridden = fresh.getService("RunService") == fake,
					}
				end)
				loader.globals.game = saved
				T.expect(ok).toBe(true)
				T.expect(result.okService).toBe(false)
				T.expect(result.err).toContain("no DataModel")
				T.expect(result.studio).toBe(false)
				T.expect(result.overridden).toBe(true)
			end)
		end)

		T.describe("now", function()
			T.it("returns a monotonic clock in seconds", function()
				local a = Env.now()
				local b = Env.now()
				T.expect(type(a)).toBe("number")
				T.expect(b).toBeGreaterThanOrEqual(a)
				T.expect(math.abs(Env.now() - os.clock())).toBeLessThan(1)
			end)
		end)
	end)
end
