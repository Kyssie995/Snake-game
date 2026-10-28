--!strict
--[[
	AstraVFX.Net — server -> client replication (docs/MODULE_CONTRACTS.md §19, docs/ROBLOX_API_CONSTRAINTS.md §21).

	Lune has no networking and no RemoteEvent methods, so the payload functions (Net._encode / _decode /
	_validate / _handle) are tested directly, PlayAll / PlayFor / PlayNear run against injected fake remotes, and
	player filtering uses fake player tables with real Lune character models. Net.Init creates real Instances.
]]
return function(T: any, use: (string) -> any, ctx: any)
	local AstraVFX = use("AstraVFX")
	local Env = use("AstraVFX.Core.Env")
	local Net = use("AstraVFX.Net")
	local Scheduler = use("AstraVFX.Core.Scheduler")
	local Signal = use("AstraVFX.Core.Signal")
	local HarnessModule = use("Tests.Specs.Helpers.PlaybackHarness")
	local expect = T.expect

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end
	local isLune = ctx.environment == "lune"

	local H: any = nil

	local function effectDef(): any
		return {
			schemaVersion = 1,
			id = "zap",
			name = "Zap",
			duration = 0.5,
			components = R({ id = "core", name = "Core", type = "part", transform = { position = { 0, 1, 0 } } }),
		}
	end

	type Remote = {
		calls: { any },
		OnClientEvent: any,
		OnServerEvent: any,
		FireAllClients: (self: any, ...any) -> (),
		FireClient: (self: any, player: any, ...any) -> (),
	}

	local function fakeRemote(): Remote
		local remote: Remote = {
			calls = {},
			OnClientEvent = Signal.new(),
			OnServerEvent = Signal.new(),
			FireAllClients = function(self: any, payload: any)
				table.insert(self.calls, R("all", payload))
			end,
			FireClient = function(self: any, player: any, payload: any)
				table.insert(self.calls, R("client", player, payload))
			end,
		}
		return remote
	end

	-- A fake player table whose character is a real Lune Model with a root part at `position`.
	local function fakePlayer(name: string, position: Vector3?, rootName: string?): any
		local player: any = { Name = name }
		if position then
			local model = Instance.new("Model")
			model.Name = name .. "Character"
			local root = Instance.new("Part")
			root.Name = rootName or "HumanoidRootPart"
			root.CFrame = CFrame.new(position)
			root.Parent = model
			if rootName ~= nil then
				model.PrimaryPart = root
			end
			table.insert(H.created, model)
			player.Character = model
		end
		return player
	end

	T.beforeEach(function()
		H = HarnessModule.new(use, ctx)
		Net._reset()
		AstraVFX._reset()
		AstraVFX.Register(effectDef())
	end)
	T.afterEach(function()
		Net._reset()
		AstraVFX._reset()
		Scheduler.clear()
		Env.override("Players", nil)
		if isLune then
			local folder = ctx.loader:resolve("AstraVFX"):FindFirstChild(Net.FOLDER_NAME)
			if folder then
				folder:Destroy()
			end
		end
		H:cleanup()
	end)

	T.describe("Net.Init", function()
		T.itIf(isLune, "creates the AstraVFXNet folder with both remotes under the module, once", function()
			local module = ctx.loader:resolve("AstraVFX")
			local folder = Net.Init()
			expect(folder.Parent).toBe(module)
			expect(folder.Name).toBe("AstraVFXNet")
			local reliable = folder:FindFirstChild("Play")
			local unreliable = folder:FindFirstChild("PlayUnreliable")
			expect(reliable.ClassName).toBe("RemoteEvent")
			expect(unreliable.ClassName).toBe("UnreliableRemoteEvent")
			expect(Net.Init()).toBe(folder) -- idempotent
			expect(#folder:GetChildren()).toBe(2)
			local again = 0
			for _, child in module:GetChildren() do
				if child.Name == "AstraVFXNet" then
					again += 1
				end
			end
			expect(again).toBe(1)
		end)
	end)

	T.describe("Net payloads", function()
		T.it("encodes only serialisable options with lower-case keys", function()
			local payload, unreliable = Net._encode("Zap", {
				CFrame = CFrame.new(1, 2, 3),
				Scale = 2,
				TimeScale = 0.5,
				Seed = 9,
				Quality = "Low",
			})
			expect(unreliable).toBe(false)
			expect(payload).toEqual({
				name = "Zap",
				cframe = CFrame.new(1, 2, 3),
				scale = 2,
				timeScale = 0.5,
				seed = 9,
				quality = "Low",
			})
			local minimal = Net._encode("Zap")
			expect(minimal).toEqual({ name = "Zap" })
			for _, case in
				{
					R({ OnEvent = function() end }, "cannot be replicated"),
					R({ Palette = {} }, "cannot be replicated"),
					R({ Loop = true }, "cannot be replicated"),
					R({ Scale = 0 }, "Scale"),
					R({ Quality = "Ultra" }, "Quality"),
					R({ CFrame = Vector3.zero }, "CFrame"),
					R({ Attach = "part" }, "Attach"),
					R({ Unreliable = 1 }, "Unreliable"),
				} :: { any }
			do
				expect(function()
					Net._encode("Zap", case[1])
				end).toThrow(case[2])
			end
			expect(function()
				Net._encode(string.rep("x", 101))
			end).toThrow("100 characters")
			expect(function()
				Net._encode("")
			end).toThrow("non-empty")
		end)

		T.it("adds the attach target's CFrame as the streaming fallback", function()
			local part = Instance.new("Part")
			part.CFrame = CFrame.new(5, 6, 7)
			table.insert(H.created, part)
			local payload = Net._encode("Zap", { Attach = part })
			expect(payload.attach).toBe(part)
			expect(payload.cframe).toBeCloseTo(CFrame.new(5, 6, 7), 1e-4)
			local withPosition = Net._encode("Zap", { Attach = part, Position = Vector3.new(1, 1, 1) })
			expect(withPosition.cframe).toBeNil()
			expect(withPosition.position).toBe(Vector3.new(1, 1, 1))
		end)

		T.it("uses the unreliable remote only for small payloads", function()
			local _, small = Net._encode("Zap", { Unreliable = true, Position = Vector3.zero })
			expect(small).toBe(true)
			local long = string.rep("n", 100)
			local _, stillSmall = Net._encode(long, { Unreliable = true })
			expect(stillSmall).toBe(true)
			expect(Net._estimateSize({ name = long }) < Net.UNRELIABLE_BUDGET).toBe(true)
			local budget = Net.UNRELIABLE_BUDGET
			Net.UNRELIABLE_BUDGET = 20
			local _, tooBig = Net._encode("Zap", { Unreliable = true, CFrame = CFrame.new() })
			Net.UNRELIABLE_BUDGET = budget
			expect(tooBig).toBe(false)
		end)

		T.it("decodes valid payloads and clamps scale and time scale", function()
			local name, options =
				Net._decode({ name = "Zap", position = Vector3.new(0, 3, 0), scale = 500, timeScale = 0 })
			expect(name).toBe("Zap")
			expect(options.CFrame).toBe(CFrame.new(0, 3, 0))
			expect(options.Scale).toBe(20)
			expect(options.TimeScale).toBe(0.05)
			local _, low = Net._decode({ name = "Zap", scale = 0.0001, timeScale = 99, quality = "Auto", seed = 3 })
			expect(low.Scale).toBe(0.05)
			expect(low.TimeScale).toBe(10)
			expect(low.Quality).toBe("Auto")
			expect(low.Seed).toBe(3)
			-- cframe wins over position; unknown keys are ignored
			local _, both =
				Net._decode({ name = "Zap", cframe = CFrame.new(1, 0, 0), position = Vector3.one, extra = 1 })
			expect(both.CFrame).toBe(CFrame.new(1, 0, 0))
		end)

		T.it("ignores malformed payloads", function()
			local cases: { any } = {
				nil,
				"Zap",
				42,
				{},
				{ name = 5 },
				{ name = "" },
				{ name = string.rep("x", 101) },
				{ name = "Zap", cframe = Vector3.zero },
				{ name = "Zap", position = CFrame.new() },
				{ name = "Zap", attach = "part" },
				{ name = "Zap", attach = Instance.new("Folder") },
				{ name = "Zap", scale = "big" },
				{ name = "Zap", scale = 0 / 0 },
				{ name = "Zap", timeScale = math.huge },
				{ name = "Zap", seed = 0 / 0 },
				{ name = "Zap", quality = "Ultra" },
			}
			for i = 1, 16 do
				local name, options, reason = Net._decode(cases[i])
				expect(R(i, name, options)).toEqual(R(i))
				expect(type(reason)).toBe("string")
			end
		end)

		T.it("validates that the name is a registered effect", function()
			local name = Net._validate({ name = "Zap" })
			expect(name).toBe("Zap")
			expect(Net._validate({ name = "zap" })).toBe("zap") -- ids work too
			local missing, _, reason = Net._validate({ name = "Unknown" })
			expect(missing).toBeNil()
			expect(reason).toContain("unknown effect")
		end)
	end)

	T.describe("Net server", function()
		T.it("PlayAll / PlayFor send the payload through the chosen remote", function()
			local reliable, unreliable = fakeRemote(), fakeRemote()
			Net._setRemotes(reliable, unreliable)
			Net.PlayAll("Zap", { Position = Vector3.new(1, 2, 3) })
			expect(reliable.calls).toEqual({ R("all", { name = "Zap", position = Vector3.new(1, 2, 3) }) })
			Net.PlayAll("Zap", { Unreliable = true })
			expect(unreliable.calls).toEqual({ R("all", { name = "Zap" }) })
			local a, b = fakePlayer("a"), fakePlayer("b")
			Net.PlayFor({ a, b }, "Zap", { Scale = 2 })
			expect(#reliable.calls).toBe(3)
			expect(reliable.calls[2]).toEqual(R("client", a, { name = "Zap", scale = 2 }))
			expect(reliable.calls[3]).toEqual(R("client", b, { name = "Zap", scale = 2 }))
			expect(function()
				Net.PlayFor(5, "Zap")
			end).toThrow("list of players")
		end)

		T.it("finds players near a position by HumanoidRootPart, else PrimaryPart", function()
			local near = fakePlayer("near", Vector3.new(3, 0, 4)) -- distance 5
			local far = fakePlayer("far", Vector3.new(30, 0, 0))
			local primary = fakePlayer("primary", Vector3.new(0, 0, -2), "Torso") -- PrimaryPart only
			local noCharacter = fakePlayer("ghost")
			local broken = { Name = "broken", Character = 7 }
			local list = Net._playersNear(Vector3.zero, 5, { near, far, primary, noCharacter, broken })
			expect(list).toEqual({ near, primary })
			expect(Net._playersNear(Vector3.zero, 4.9, { near })).toEqual({})
		end)

		T.it("PlayNear sends only to the players in range (Players via Core/Env)", function()
			local reliable = fakeRemote()
			Net._setRemotes(reliable, nil)
			local near = fakePlayer("near", Vector3.new(0, 0, 10))
			local far = fakePlayer("far", Vector3.new(0, 0, 100))
			Env.override("Players", {
				GetPlayers = function(_self: any): { any }
					return { near, far }
				end,
			})
			local sent = Net.PlayNear(Vector3.zero, 20, "Zap", { Unreliable = true })
			expect(sent).toEqual({ near })
			-- no unreliable remote available: falls back to the reliable one
			expect(reliable.calls).toEqual({ R("client", near, { name = "Zap" }) })
			expect(function()
				Net.PlayNear(Vector3.zero, -1, "Zap")
			end).toThrow("radius")
		end)

		T.itIf(isLune, "creates the remotes on first use when Init was not called", function()
			-- RemoteEvent:FireAllClients does not exist in Lune, so only the lazy Init is observable here
			pcall(Net.PlayAll, "Zap")
			expect(ctx.loader:resolve("AstraVFX"):FindFirstChild("AstraVFXNet")).never.toBeNil()
		end)
	end)

	T.describe("Net client", function()
		T.itIf(
			isLune,
			"Listen plays valid payloads, ignores malformed ones and has no client -> server path",
			function()
				local reliable, unreliable = fakeRemote(), fakeRemote()
				Net._setRemotes(reliable, unreliable)
				local listener = Net.Listen()
				expect(Net.Listen()).toBe(listener) -- idempotent
				expect(reliable.OnClientEvent:count()).toBe(1)
				expect(unreliable.OnClientEvent:count()).toBe(1)
				expect(reliable.OnServerEvent:count()).toBe(0)
				expect(unreliable.OnServerEvent:count()).toBe(0)
				local parent = workspace
				local before = #parent:GetChildren()
				reliable.OnClientEvent:Fire({ name = "Zap", position = Vector3.new(0, 4, 0), quality = "High" })
				expect(AstraVFX.ActiveCount()).toBe(1)
				expect(#parent:GetChildren()).toBe(before + 1)
				unreliable.OnClientEvent:Fire({ name = "Zap", scale = 3 })
				expect(AstraVFX.ActiveCount()).toBe(2)
				reliable.OnClientEvent:Fire({ name = "Unknown" })
				reliable.OnClientEvent:Fire("garbage")
				reliable.OnClientEvent:Fire({ name = "Zap", scale = "huge" })
				expect(AstraVFX.ActiveCount()).toBe(2)
				expect(Net.stats).toEqual({ received = 5, played = 2, ignored = 3 })
				listener:Disconnect()
				expect(listener.Connected).toBe(false)
				expect(reliable.OnClientEvent:count()).toBe(0)
				reliable.OnClientEvent:Fire({ name = "Zap" })
				expect(AstraVFX.ActiveCount()).toBe(2)
				AstraVFX.StopAll(true)
			end
		)

		T.itIf(isLune, "plays at the sent CFrame when the attach target did not stream in", function()
			local handle = Net._handle({ name = "Zap", cframe = CFrame.new(10, 0, 0), attach = nil })
			expect(handle).never.toBeNil()
			ctx.fakes:step(1 / 60)
			ctx.fakes:step(1 / 60)
			local core = handle._player.built.controllers.core.instances[1]
			expect(core.CFrame).toBeCloseTo(CFrame.new(10, 1, 0), 1e-4)
			-- with the target present the effect follows it
			local target = Instance.new("Part")
			target.CFrame = CFrame.new(0, 0, 20)
			target.Parent = workspace
			table.insert(H.created, target)
			local attached = Net._handle({ name = "Zap", cframe = CFrame.new(10, 0, 0), attach = target })
			ctx.fakes:step(1 / 60)
			local attachedCore = attached._player.built.controllers.core.instances[1]
			expect(attachedCore.CFrame).toBeCloseTo(CFrame.new(0, 1, 20), 1e-4)
			AstraVFX.StopAll(true)
		end)

		T.itIf(isLune, "Listen waits for remotes that have not replicated yet without yielding", function()
			local module = ctx.loader:resolve("AstraVFX")
			local childAdded = ctx.fakes:signalFor(module, "ChildAdded")
			local before = childAdded:connectionCount()
			local listener = Net.Listen() -- no folder yet: watches the module's ChildAdded instead of waiting
			expect(listener.Connected).toBe(true)
			expect(childAdded:connectionCount()).toBe(before + 1)
			local other = Instance.new("Folder")
			other.Name = "SomethingElse"
			table.insert(H.created, other)
			childAdded:Fire(other) -- unrelated children are ignored
			listener:Disconnect()
			expect(childAdded:connectionCount()).toBe(before)
		end)
	end)
end
