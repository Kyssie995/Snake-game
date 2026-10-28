--!strict
--[[
	Public runtime API (src/Runtime/init.luau, ModuleScript "AstraVFX"; docs/ARCHITECTURE.md §5.3,
	docs/MODULE_CONTRACTS.md §19): registration (tables, JSON text, ModuleScripts, StringValues, folders, lazy
	script.Effects), Play / TryPlay options, handles, the compile cache, pooling, cleanup and leaks. Effects run
	through the real Scheduler, driven by the Lune fakes (ctx.fakes:step fires Heartbeat).
]]
return function(T: any, use: (string) -> any, ctx: any)
	local AstraVFX = use("AstraVFX")
	local Constants = use("AstraVFX.Core.Constants")
	local Json = use("AstraVFX.Core.Json")
	local Pool = use("AstraVFX.Core.Pool")
	local Scheduler = use("AstraVFX.Core.Scheduler")
	local Fixtures = use("Tests.Specs.Helpers.EffectFixtures")
	local HarnessModule = use("Tests.Specs.Helpers.PlaybackHarness")
	local expect = T.expect

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end
	local isLune = ctx.environment == "lune"
	local DT = 1 / 60

	local H: any = nil
	local baseline = 0
	T.beforeEach(function()
		AstraVFX._reset()
		Scheduler.clear()
		H = HarnessModule.new(use, ctx)
		if isLune then
			baseline = ctx.fakes.heartbeat:connectionCount()
		end
	end)
	T.afterEach(function()
		AstraVFX._reset()
		Scheduler.clear()
		Pool.setCapacity(Pool.DEFAULT_CAPACITY)
		H:cleanup()
	end)

	local function frames(n: number)
		for _ = 1, n do
			ctx.fakes:step(DT)
		end
	end

	local function heartbeats(): number
		return ctx.fakes.heartbeat:connectionCount()
	end

	local function simpleDef(): any
		return {
			schemaVersion = 1,
			id = "simple",
			name = "Simple",
			duration = 1,
			palette = { primary = "#FF0000" },
			markers = { { id = "hit", time = 0.25, label = "Hit", event = "Hit" } },
			components = R({
				id = "core",
				name = "Core",
				type = "part",
				transform = { position = { 0, 1, 0 } },
				properties = { color = "$primary" },
			}, {
				id = "sparks",
				name = "Sparks",
				type = "particles",
				properties = { rate = 0, burst = 20, lifetime = { 0.2, 0.3 } },
				events = R(
					{ id = "a", time = 0.2, action = "emit", count = 12 },
					{ id = "b", time = 0.6, action = "emit", count = 40 }
				),
			}),
			graph = {
				nodes = R(
					{ id = "on", type = "OnEvent", params = { name = "Detonate" } },
					{ id = "boom", type = "Emit", params = { target = "sparks", count = 7 } }
				),
				links = { { from = "on.out", to = "boom.in" } },
			},
		}
	end

	local function containerOf(handle: any): any
		return handle._player.built.container
	end

	T.describe("AstraVFX.Register", function()
		T.it("registers tables and JSON text, finds effects by id and name", function()
			expect(AstraVFX.Register(simpleDef())).toBe("Simple")
			expect(AstraVFX.IsRegistered("Simple")).toBe(true)
			expect(AstraVFX.IsRegistered("simple")).toBe(true)
			expect(AstraVFX.IsRegistered("nope")).toBe(false)
			expect(AstraVFX.Register(Fixtures.FULL_JSON)).toBe("Violet Impact")
			expect(AstraVFX.IsRegistered("violetImpact")).toBe(true)
			expect(AstraVFX.GetNames()).toEqual({ "Simple", "Violet Impact" })
			expect(AstraVFX.Version).toBe(Constants.VERSION)
		end)

		T.it("migrates legacy documents before validating them", function()
			local name = AstraVFX.Register({
				name = "VioletImpact",
				duration = 1.2,
				components = R({
					type = "sphere",
					name = "core",
					properties = { color = { 150, 65, 255 }, initialScale = 1, finalScale = 8 },
				}),
			})
			expect(name).toBe("VioletImpact")
			expect(AstraVFX.IsRegistered("violetimpact")).toBe(true)
		end)

		T.it("raises a readable diagnostic summary for invalid definitions", function()
			local bad = simpleDef()
			bad.duration = -1
			bad.components[1].type = "laser"
			local ok, err = pcall(AstraVFX.Register :: any, bad)
			expect(ok).toBe(false)
			local message = tostring(err)
			expect(message).toContain('effect "Simple" is invalid')
			expect(message).toContain("effect.duration")
			expect(message).toContain("component.type")
			expect(AstraVFX.IsRegistered("simple")).toBe(false)
			expect(function()
				AstraVFX.Register("{ not json")
			end).toThrow("migration.json")
			expect(function()
				AstraVFX.Register(42 :: any)
			end).toThrow("expected a definition")
		end)

		T.itIf(isLune, "registers ModuleScripts, StringValues and folders of them", function()
			local folder = H:folder("Bundle")
			local module = Instance.new("ModuleScript")
			module.Name = "ShardModule"
			module.Source = [[return {
				schemaVersion = 1, id = "shard", name = "Shard", duration = 0.5,
				components = { { id = "core", name = "Core", type = "part" } },
			}]]
			module.Parent = folder
			local text = Instance.new("StringValue")
			text.Name = "GlowText"
			text.Value = Json.encode({
				schemaVersion = 1,
				id = "glow",
				name = "Glow",
				duration = 0.5,
				components = R({ id = "l", name = "Light", type = "light" }),
			})
			text.Parent = folder
			local nested = Instance.new("Folder")
			nested.Name = "Nested"
			nested.Parent = folder
			local jsonModule = Instance.new("ModuleScript")
			jsonModule.Name = "Ring"
			jsonModule.Source = 'return [=[{"schemaVersion": 1, "id": "ringfx", "name": "Ring FX", "duration": 1, '
				.. '"components": [{"id": "r", "name": "R", "type": "ring"}]}]=]'
			jsonModule.Parent = nested
			expect(AstraVFX.Register(folder)).toEqual({ "Glow", "Ring FX", "Shard" })
			-- instance names are aliases
			expect(AstraVFX.IsRegistered("ShardModule")).toBe(true)
			expect(AstraVFX.IsRegistered("GlowText")).toBe(true)
			expect(AstraVFX.Register(module)).toBe("Shard")
			local bad = Instance.new("Part")
			bad.Parent = folder
			expect(function()
				AstraVFX.Register(folder)
			end).toThrow("cannot register a Part")
		end)

		T.itIf(isLune, "registers script.Effects lazily and skips broken children", function()
			local runtimeModule = ctx.loader:resolve("AstraVFX")
			local effects = Instance.new("Folder")
			effects.Name = "Effects"
			table.insert(H.created, effects)
			local good = Instance.new("StringValue")
			good.Name = "Spark"
			good.Value = Json.encode({
				schemaVersion = 1,
				id = "spark",
				name = "Spark",
				duration = 0.5,
				components = { { id = "core", name = "Core", type = "part" } },
			})
			good.Parent = effects
			local broken = Instance.new("StringValue")
			broken.Name = "Broken"
			broken.Value = '{ "schemaVersion": 1, "id": "broken", "name": "Broken", "duration": 0, "components": [] }'
			broken.Parent = effects
			effects.Parent = runtimeModule
			expect(AstraVFX.IsRegistered("Spark")).toBe(true)
			expect(AstraVFX.IsRegistered("Broken")).toBe(false)
			-- children added later are found on the next miss
			local late = Instance.new("StringValue")
			late.Name = "Late"
			late.Value = Json.encode({
				schemaVersion = 1,
				id = "late",
				name = "Late",
				duration = 0.5,
				components = { { id = "core", name = "Core", type = "part" } },
			})
			late.Parent = effects
			local handle = AstraVFX.Play("Late", { Parent = H:folder("LazyParent") })
			expect(handle.Id).toBe("late")
			handle:Destroy()
		end)

		T.it("Unregister removes an effect; re-registering replaces it and drops its cache", function()
			AstraVFX.Register(simpleDef())
			local parent = H:folder("Parent")
			local handle = AstraVFX.Play("Simple", { Parent = parent, Quality = "High" })
			handle:Destroy()
			expect(Pool.count()).toBe(1)
			expect(AstraVFX._cacheSize()).toBe(1)
			local changed = simpleDef()
			changed.palette.primary = "#00FF00"
			AstraVFX.Register(changed)
			expect(Pool.count()).toBe(0)
			expect(AstraVFX._cacheSize()).toBe(0)
			local again = AstraVFX.Play("Simple", { Parent = parent, Quality = "High" })
			local part = again._player.built.controllers.core.instances[1]
			expect(part.Color).toBeCloseTo(Color3.new(0, 1, 0), 1e-6)
			again:Destroy()
			expect(AstraVFX.Unregister("Simple")).toBe(true)
			expect(AstraVFX.Unregister("Simple")).toBe(false)
			expect(AstraVFX.IsRegistered("simple")).toBe(false)
		end)

		T.it("Validate migrates and validates without registering", function()
			local result, def = AstraVFX.Validate(simpleDef())
			expect(result.ok).toBe(true)
			expect(def.id).toBe("simple")
			local bad = simpleDef()
			bad.components[2].properties.rate = 1000
			local badResult = AstraVFX.Validate(bad)
			expect(badResult.ok).toBe(false)
			expect(badResult.errors[1].code).toBe("property.range")
			local notJson = AstraVFX.Validate("{")
			expect(notJson.ok).toBe(false)
			expect(notJson.errors[1].code).toBe("migration.json")
			expect(AstraVFX.IsRegistered("simple")).toBe(false)
		end)
	end)

	T.describe("AstraVFX.Play", function()
		T.it("errors on unknown names and invalid options; TryPlay returns the message", function()
			AstraVFX.Register(simpleDef())
			expect(function()
				AstraVFX.Play("Missing")
			end).toThrow("unknown effect")
			local handle, err = AstraVFX.TryPlay("Missing")
			expect(handle).toBeNil()
			expect(err).toContain("unknown effect")
			for _, case in
				{
					R({ Scale = 0 }, "Scale"),
					R({ Scale = 0 / 0 }, "Scale"),
					R({ Quality = "Ultra" }, "Quality"),
					R({ TimeScale = -1 }, "TimeScale"),
					R({ CFrame = Vector3.zero }, "CFrame"),
					R({ Position = CFrame.new() }, "Position"),
					R({ Attach = "part" }, "Attach"),
					R({ Loop = 1 }, "Loop"),
					R({ OnEvent = true }, "OnEvent"),
					R({ Postion = Vector3.zero }, "unknown option"),
				} :: { any }
			do
				local h, message = AstraVFX.TryPlay("Simple", case[1])
				expect(h).toBeNil()
				expect(message).toContain(case[2])
			end
			expect(AstraVFX.ActiveCount()).toBe(0)
		end)

		T.itIf(isLune, "builds into Workspace by default and never runs actions in the build frame", function()
			AstraVFX.Register(simpleDef())
			local mark = H:emitMark()
			local handle = AstraVFX.Play("Simple", { Position = Vector3.new(0, 5, 0), Quality = "High" })
			local container = containerOf(handle)
			expect(container.Parent).toBe(workspace)
			expect(container.Name).toBe("AstraVFX_Simple")
			expect(handle.Name).toBe("Simple")
			expect(handle:GetState()).toBe("playing")
			expect(H:emitsSince(mark)).toEqual({})
			frames(1) -- the frame the copy was built in
			expect(H:emitsSince(mark)).toEqual({})
			expect(handle:GetTime()).toBe(0)
			frames(1)
			expect(H:emitsSince(mark)).toEqual({ 20 }) -- burst on activation
			expect(handle._player.built.root.CFrame).toBeCloseTo(CFrame.new(0, 5, 0), 1e-4)
			handle:Destroy()
			expect(container.Parent).toBeNil()
		end)

		T.itIf(isLune, "destroy removes the container and disconnects the scheduler when no effect is left", function()
			AstraVFX.Register(simpleDef())
			Pool.setCapacity(0) -- no pooling: the copy is destroyed
			local parent = H:folder("Parent")
			local a = AstraVFX.Play("Simple", { Parent = parent })
			local b = AstraVFX.Play("Simple", { Parent = parent })
			expect(heartbeats()).toBe(baseline + 1)
			expect(AstraVFX.ActiveCount()).toBe(2)
			frames(3)
			local containerA = containerOf(a)
			a:Destroy()
			expect(containerA.Parent).toBeNil()
			expect(a._player.built.destroyed).toBe(true)
			expect(heartbeats()).toBe(baseline + 1)
			b:Destroy()
			b:Destroy()
			expect(heartbeats()).toBe(baseline)
			expect(heartbeats()).toBe(0)
			expect(Scheduler.count()).toBe(0)
			expect(AstraVFX.ActiveCount()).toBe(0)
			expect(#parent:GetChildren()).toBe(0)
			expect(a:IsPlaying()).toBe(false)
			a:Stop() -- no-ops after the end
			a:Fire("Detonate")
		end)

		T.itIf(isLune, "100 Play/Destroy cycles leak no instances, connections or handles", function()
			AstraVFX.Register(simpleDef())
			local workspaceChildren = #workspace:GetChildren()
			for i = 1, 100 do
				local handle = AstraVFX.Play("Simple", { Position = Vector3.new(i, 0, 0), Quality = "High" })
				local finished = 0
				handle.Finished:Connect(function()
					finished += 1
				end)
				if i % 3 == 0 then
					frames(2)
				end
				handle:Destroy()
				expect(finished).toBe(1)
				expect(handle.Finished:count()).toBe(0) -- signals are disconnected with the copy
				expect(handle.Event:count()).toBe(0)
			end
			frames(2)
			expect(#workspace:GetChildren()).toBe(workspaceChildren)
			expect(heartbeats()).toBe(baseline)
			expect(Scheduler.count()).toBe(0)
			expect(AstraVFX.ActiveCount()).toBe(0)
			expect(Pool.count() <= Pool.DEFAULT_CAPACITY).toBe(true)
			expect(AstraVFX._cacheSize()).toBe(1)
			-- the effects that ended by themselves leak nothing either
			for i = 1, 5 do
				AstraVFX.Play("Simple", { Position = Vector3.new(i, 0, 0), Quality = "High" })
			end
			frames(120)
			expect(AstraVFX.ActiveCount()).toBe(0)
			expect(#workspace:GetChildren()).toBe(workspaceChildren)
			expect(heartbeats()).toBe(baseline)
		end)

		T.itIf(isLune, "a pooled replay looks exactly like a fresh build", function()
			AstraVFX.Register(Fixtures.FULL_JSON)
			local parent = H:folder("PoolParent")
			local options = { Parent = parent, Quality = "High", CFrame = CFrame.new(0, 3, 0) }
			local first = AstraVFX.Play("Violet Impact", options)
			local firstContainer = containerOf(first)
			frames(40)
			first:Fire("Detonate")
			frames(10)
			first:Destroy()
			expect(Pool.count()).toBe(1)
			local pooled = AstraVFX.Play("Violet Impact", options)
			expect(containerOf(pooled)).toBe(firstContainer) -- reused copy
			expect(Pool.count()).toBe(0)
			local fresh = AstraVFX.Play("Violet Impact", options)
			expect(containerOf(fresh) ~= firstContainer).toBe(true)
			expect(H:snapshot(containerOf(pooled))).toEqual(H:snapshot(containerOf(fresh)))
			for _, n in { 2, 15, 30, 50 } do
				frames(n)
				expect(pooled:GetTime()).toBe(fresh:GetTime())
				expect(H:snapshot(containerOf(pooled))).toEqual(H:snapshot(containerOf(fresh)))
			end
		end)

		T.itIf(isLune, "Palette overrides recolour palette references", function()
			AstraVFX.Register(simpleDef())
			local parent = H:folder("Parent")
			local default = AstraVFX.Play("Simple", { Parent = parent, Quality = "High" })
			local blue = Color3.fromRGB(80, 160, 255)
			local tinted = AstraVFX.Play("Simple", { Parent = parent, Quality = "High", Palette = { primary = blue } })
			frames(2)
			local defaultPart = default._player.built.controllers.core.instances[1]
			local tintedPart = tinted._player.built.controllers.core.instances[1]
			expect(defaultPart.Color).toBeCloseTo(Color3.new(1, 0, 0), 1e-6)
			expect(tintedPart.Color).toBeCloseTo(blue, 1e-6)
			expect(AstraVFX._cacheSize()).toBe(2) -- the palette is part of the cache key
		end)

		T.itIf(isLune, "Quality Low reduces emitted particles", function()
			AstraVFX.Register(simpleDef())
			local parent = H:folder("Parent")
			local function total(quality: string): { number }
				local mark = H:emitMark()
				local handle = AstraVFX.Play("Simple", { Parent = parent, Quality = quality })
				frames(100) -- 1 s + 0.3 s tail + the build frame
				expect(handle:IsPlaying()).toBe(false)
				return H:emitsSince(mark)
			end
			expect(total("High")).toEqual({ 20, 12, 40 })
			-- 20 × 0.35 = 7, 12 × 0.35 = 4.2 -> 4, 40 × 0.35 = 14
			expect(total("Low")).toEqual({ 7, 4, 14 })
		end)

		T.itIf(isLune, "SetQuality sets the default quality ('Auto' detects; Medium off-client)", function()
			AstraVFX.Register(simpleDef())
			local parent = H:folder("Parent")
			expect(AstraVFX.GetQuality()).toBe("Auto")
			AstraVFX.SetQuality("Low")
			local low = AstraVFX.Play("Simple", { Parent = parent })
			expect(low._player.compiled.quality.level).toBe("Low")
			AstraVFX.SetQuality("Auto")
			local auto = AstraVFX.Play("Simple", { Parent = parent })
			expect(auto._player.compiled.quality.level).toBe("Medium") -- Lune is Studio: detect() -> Medium
			expect(function()
				AstraVFX.SetQuality("Ultra" :: any)
			end).toThrow("SetQuality")
		end)

		T.itIf(isLune, "handles pause, resume, scale time, fire graph events and report events", function()
			AstraVFX.Register(simpleDef())
			local parent = H:folder("Parent")
			local fromOption: { string } = {}
			local handle = AstraVFX.Play("Simple", {
				Parent = parent,
				Quality = "High",
				OnEvent = function(name: string)
					table.insert(fromOption, name)
				end,
			})
			local fromSignal: { string } = {}
			handle.Event:Connect(function(name: string)
				table.insert(fromSignal, name)
			end)
			frames(1 + 18) -- build frame + 0.3 s
			expect(fromSignal).toEqual({ "Hit" })
			expect(fromOption).toEqual({ "Hit" })
			handle:Pause()
			local t = handle:GetTime()
			frames(10)
			expect(handle:GetTime()).toBe(t)
			expect(handle:IsPlaying()).toBe(true)
			handle:Resume()
			handle:SetTimeScale(0.5)
			frames(2)
			expect(handle:GetTime()).toBeCloseTo(t + DT, 1e-9)
			local mark = H:emitMark()
			handle:Fire("Detonate")
			frames(1)
			expect(H:emitsSince(mark)).toEqual({ 7 })
			handle:SetCFrame(CFrame.new(7, 0, 0))
			frames(1)
			expect(handle._player.built.root.CFrame).toBeCloseTo(CFrame.new(7, 0, 0), 1e-4)
			handle:Seek(0.1)
			expect(handle:GetTime()).toBe(0.1)
			handle:Stop()
			expect(handle:GetState()).toBe("stopping")
			expect(handle:IsPlaying()).toBe(false)
			local reasons: { string } = {}
			handle.Finished:Connect(function(reason: string)
				table.insert(reasons, reason)
			end)
			-- the stop linger follows the rate: particles age at TimeScale 0.5, so the 0.3 s lifetime lasts 0.6 s
			frames(30)
			expect(reasons).toEqual({})
			frames(10)
			expect(reasons).toEqual({ "finished" })
			expect(AstraVFX.ActiveCount()).toBe(0)
		end)

		T.itIf(isLune, "Autoplay = false builds and poses the effect but waits for Resume", function()
			AstraVFX.Register(simpleDef())
			local mark = H:emitMark()
			local handle = AstraVFX.Play("Simple", { Parent = H:folder("Parent"), Autoplay = false, Quality = "High" })
			expect(handle:GetState()).toBe("paused")
			frames(10)
			expect(handle:GetTime()).toBe(0)
			expect(H:emitsSince(mark)).toEqual({})
			handle:Resume()
			frames(1)
			expect(H:emitsSince(mark)).toEqual({ 20 })
		end)

		T.itIf(isLune, "Attach follows a moving part through the scheduler (with Offset)", function()
			AstraVFX.Register(simpleDef())
			local target = Instance.new("Part")
			target.Anchored = true
			target.CFrame = CFrame.new(0, 0, 0)
			target.Parent = workspace
			table.insert(H.created, target)
			local handle =
				AstraVFX.Play("Simple", { Parent = H:folder("Parent"), Attach = target, Offset = CFrame.new(0, 2, 0) })
			local core = handle._player.built.controllers.core.instances[1]
			frames(1)
			for i = 1, 20 do
				target.CFrame = CFrame.new(i, 0, -i)
				frames(1)
				expect(core.CFrame).toBeCloseTo(CFrame.new(i, 3, -i), 1e-4)
			end
		end)

		T.itIf(isLune, "Loop keeps playing until stopped; StopAll ends every effect", function()
			AstraVFX.Register(simpleDef())
			local parent = H:folder("Parent")
			local looping = AstraVFX.Play("Simple", { Parent = parent, Loop = true })
			local once = AstraVFX.Play("Simple", { Parent = parent })
			frames(150) -- 2.5 s
			expect(looping:IsPlaying()).toBe(true)
			expect(looping._player.cycle >= 2).toBe(true)
			expect(once:IsPlaying()).toBe(false)
			expect(AstraVFX.ActiveCount()).toBe(1)
			AstraVFX.StopAll()
			expect(looping:GetState()).toBe("stopping")
			frames(30)
			expect(AstraVFX.ActiveCount()).toBe(0)
			local again = AstraVFX.Play("Simple", { Parent = parent, Loop = true })
			AstraVFX.StopAll(true)
			expect(again:GetState()).toBe("destroyed")
			expect(heartbeats()).toBe(baseline)
		end)

		T.it("caches compiled variants by options", function()
			AstraVFX.Register(simpleDef())
			local parent = H:folder("Parent")
			AstraVFX.Play("Simple", { Parent = parent, Quality = "High" }):Destroy()
			AstraVFX.Play("Simple", { Parent = parent, Quality = "High" }):Destroy()
			expect(AstraVFX._cacheSize()).toBe(1)
			AstraVFX.Play("Simple", { Parent = parent, Quality = "High", Scale = 2 }):Destroy()
			AstraVFX.Play("Simple", { Parent = parent, Quality = "Low" }):Destroy()
			AstraVFX.Play("Simple", { Parent = parent, Quality = "High", Seed = 5 }):Destroy()
			expect(AstraVFX._cacheSize()).toBe(4)
			local big = AstraVFX.Play("Simple", { Parent = parent, Quality = "High", Scale = 2 })
			expect(big._player.compiled.scale).toBe(2)
			big:Destroy()
		end)

		T.itIf(isLune, "Preload warms the pool for a variant", function()
			AstraVFX.Register(simpleDef())
			expect(AstraVFX.Preload("Simple", { Count = 3, Quality = "High" })).toBe(3)
			expect(Pool.count()).toBe(3)
			expect(AstraVFX.Preload("Simple", { Count = 3, Quality = "High" })).toBe(0)
			local handle = AstraVFX.Play("Simple", { Parent = H:folder("Parent"), Quality = "High" })
			expect(Pool.count()).toBe(2) -- taken from the pool
			handle:Destroy()
			expect(Pool.count()).toBe(3) -- the raised capacity keeps all three
			expect(function()
				AstraVFX.Preload("Missing")
			end).toThrow("unknown effect")
			expect(function()
				AstraVFX.Preload("Simple", { Count = -1 })
			end).toThrow("Count")
			expect(function()
				AstraVFX.Preload("Simple", { Colour = 1 } :: any)
			end).toThrow("unknown option")
		end)

		T.it("SetUpdateEvent selects the scheduler event", function()
			AstraVFX.SetUpdateEvent("Heartbeat")
			expect(Scheduler.getEventName()).toBe("Heartbeat")
			expect(function()
				AstraVFX.SetUpdateEvent("Stepped" :: any)
			end).toThrow("Heartbeat")
		end)
	end)

	T.describe("AstraVFX.SetMaxActive", function()
		local function auraDef(): any
			local def = simpleDef()
			def.id = "aura"
			def.name = "Aura"
			def.loop = true
			return def
		end

		-- Runs fn with the runtime's warn() captured (Lune: modules read globals through ctx.loader.globals).
		local function captureWarnings(fn: () -> ()): { string }
			local globals = ctx.loader.globals
			local original = globals.warn
			local out: { string } = {}
			globals.warn = function(...: any)
				local parts = {}
				for i = 1, select("#", ...) do
					table.insert(parts, tostring((select(i, ...))))
				end
				table.insert(out, table.concat(parts, " "))
			end
			local ok, err = pcall(fn :: any)
			globals.warn = original
			if not ok then
				error(err, 0)
			end
			return out
		end

		T.it("defaults to 64, accepts whole numbers >= 1 or math.huge and resets with _reset", function()
			expect(AstraVFX.GetMaxActive()).toBe(64)
			AstraVFX.SetMaxActive(3)
			expect(AstraVFX.GetMaxActive()).toBe(3)
			AstraVFX.SetMaxActive(math.huge)
			expect(AstraVFX.GetMaxActive()).toBe(math.huge)
			for _, bad in { 0, -1, 1.5, 0 / 0, -math.huge, "8" :: any } do
				expect(function()
					AstraVFX.SetMaxActive(bad)
				end).toThrow("SetMaxActive")
			end
			AstraVFX._reset()
			expect(AstraVFX.GetMaxActive()).toBe(64)
		end)

		T.itIf(isLune, "a Play beyond the cap stops the oldest non-looping effect gracefully", function()
			AstraVFX.Register(simpleDef())
			AstraVFX.Register(auraDef())
			AstraVFX.SetMaxActive(3)
			local parent = H:folder("Parent")
			local aura = AstraVFX.Play("Aura", { Parent = parent }) -- the oldest, but looping
			local first = AstraVFX.Play("Simple", { Parent = parent, Autoplay = false }) -- paused effects count
			local second = AstraVFX.Play("Simple", { Parent = parent })
			frames(2)
			local warnings = captureWarnings(function()
				local third = AstraVFX.Play("Simple", { Parent = parent })
				expect(third:GetState()).toBe("playing")
			end)
			expect(warnings).toEqual({}) -- making room is normal operation, not a problem
			expect(first:GetState()).toBe("stopping") -- Stop(): emission ends, live particles finish
			expect(second:GetState()).toBe("playing")
			expect(aura:GetState()).toBe("playing")
			-- stopping effects linger for their tail but no longer count against the cap
			local fourth = AstraVFX.Play("Simple", { Parent = parent })
			expect(second:GetState()).toBe("stopping")
			expect(fourth:GetState()).toBe("playing")
			expect(AstraVFX.ActiveCount()).toBe(5) -- ActiveCount still includes the two lingering effects
			frames(30) -- the 0.3 s tails end
			expect(first:GetState()).toBe("finished")
			expect(second:GetState()).toBe("finished")
			expect(AstraVFX.ActiveCount()).toBe(3)
			AstraVFX.StopAll(true)
		end)

		T.itIf(
			isLune,
			"when every counted effect loops, Play is refused with a warning (TryPlay: nil, 'limit')",
			function()
				AstraVFX.Register(simpleDef())
				AstraVFX.Register(auraDef())
				AstraVFX.SetMaxActive(2)
				local parent = H:folder("Parent")
				local a = AstraVFX.Play("Aura", { Parent = parent })
				local b = AstraVFX.Play("Aura", { Parent = parent, Loop = true })
				local tried: any, err: any, played: any = nil, nil, nil
				local warnings = captureWarnings(function()
					tried, err = AstraVFX.TryPlay("Simple", { Parent = parent })
					played = AstraVFX.Play("Simple", { Parent = parent })
				end)
				expect(tried).toBeNil()
				expect(err).toBe("limit")
				expect(played).toBeNil()
				expect(#warnings).toBe(2)
				expect(warnings[1]).toContain("2 active effects")
				expect(warnings[1]).toContain("Simple")
				expect(AstraVFX.ActiveCount()).toBe(2)
				expect(#parent:GetChildren()).toBe(2) -- nothing was built for the refused plays
				-- SetLoop(false) makes an effect a candidate again; a stopped effect frees its slot
				a:SetLoop(false)
				local c = AstraVFX.Play("Simple", { Parent = parent })
				expect(c).never.toBeNil()
				expect(a:GetState()).toBe("stopping")
				b:Stop()
				local d, noErr = AstraVFX.TryPlay("Aura", { Parent = parent })
				expect(d).never.toBeNil()
				expect(noErr).toBeNil()
				-- unlimited
				AstraVFX.SetMaxActive(math.huge)
				for _ = 1, 3 do
					expect(AstraVFX.Play("Aura", { Parent = parent })).never.toBeNil()
				end
				AstraVFX.StopAll(true)
			end
		)

		T.itIf(
			isLune,
			"a lowered cap takes effect with the next Play, which stops as many old effects as needed",
			function()
				AstraVFX.Register(simpleDef())
				local parent = H:folder("Parent")
				local handles = {}
				for i = 1, 4 do
					handles[i] = AstraVFX.Play("Simple", { Parent = parent })
				end
				AstraVFX.SetMaxActive(2)
				for _, handle in handles do
					expect(handle:GetState()).toBe("playing")
				end
				-- the next Play stops the oldest effects until it fits: 4 counted -> 1 + the new one
				local newest = AstraVFX.Play("Simple", { Parent = parent })
				expect(handles[1]:GetState()).toBe("stopping")
				expect(handles[2]:GetState()).toBe("stopping")
				expect(handles[3]:GetState()).toBe("stopping")
				expect(handles[4]:GetState()).toBe("playing")
				expect(newest:GetState()).toBe("playing")
				AstraVFX.StopAll(true)
			end
		)

		T.itIf(isLune, "a Play that fails or is invalid stops nothing, even when the cap is full", function()
			AstraVFX.Register(simpleDef())
			AstraVFX.Register(auraDef())
			AstraVFX.SetMaxActive(1)
			local parent = H:folder("Parent")
			local first = AstraVFX.Play("Simple", { Parent = parent })
			-- the palette colour is only checked by the Compiler, after the cap made room
			local failed, err = AstraVFX.TryPlay("Simple", { Parent = parent, Palette = { primary = 5 :: any } })
			expect(failed).toBeNil()
			expect(err).toContain("palette")
			expect(first:GetState()).toBe("playing") -- not stopped for a play that never started
			expect(AstraVFX.ActiveCount()).toBe(1)
			-- name and option errors come before the cap: they raise instead of reporting "limit"
			first:Stop(0)
			local aura = AstraVFX.Play("Aura", { Parent = parent })
			expect(function()
				AstraVFX.Play("Simple", { Parent = parent, Foo = true } :: any)
			end).toThrow("unknown option")
			expect(function()
				AstraVFX.Play("Missing", { Parent = parent })
			end).toThrow("unknown effect")
			local _, limit = AstraVFX.TryPlay("Simple", { Parent = parent })
			expect(limit).toBe("limit")
			expect(aura:GetState()).toBe("playing")
			AstraVFX.StopAll(true)
		end)
	end)
end
