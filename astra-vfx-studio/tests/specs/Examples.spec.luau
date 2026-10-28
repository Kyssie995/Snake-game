--!strict
--[[
	examples/ — the demo place (examples/default.project.json; `rojo build examples/default.project.json -o
	build/AstraVFX-Examples.rbxl`). Lune only.

	The place is loaded with a second Loader (same Rojo rules as the test tree: $path relative to the project file,
	*.vfx.json as raw-text StringValues). Every test opens a fresh copy, so each simulated machine (server, client)
	has its OWN runtime instance, like in a real game. Engine members the scripts use and Lune lacks (Players,
	UserInputService, TweenService, raycasts, Humanoid:TakeDamage, WaitForChild, task.wait / task.delay) are small
	fakes injected as script globals; RunService.Heartbeat and instance events come from ctx.fakes.

	Proves: the place's effect files register and validate, the effect names the scripts use exist, the server
	script sends a well-formed Net payload and runs its own damage timer, the client script listens, preloads,
	plays FireExplosion at the raycast hit, reacts to the "Impact" event and attaches VioletImpact to the character.
	Does NOT prove: rendering, real input, real networking (manual protocol: docs/TESTING.md).
]]
return function(T: any, use: (string) -> any, ctx: any)
	local Signal = use("AstraVFX.Core.Signal")
	local expect = T.expect

	local isLune = ctx.environment == "lune" and ctx.loader ~= nil
	local DT = 1 / 60

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end

	type Place = {
		loader: any,
		root: any,
		AstraVFX: any,
		Net: any,
		Pool: any,
		Scheduler: any,
	}

	local opened: { Place } = {}

	-- A fresh copy of the example place with its own runtime.
	local function openPlace(): Place
		local loader = ctx.loader.new(ctx.loader.projectDir .. "/examples", "default.project.json")
		local runtime = loader:use("ReplicatedStorage.AstraVFX")
		local place: Place = {
			loader = loader,
			root = loader.root,
			AstraVFX = runtime,
			Net = runtime.Net,
			Pool = loader:use("ReplicatedStorage.AstraVFX.Core.Pool"),
			Scheduler = loader:use("ReplicatedStorage.AstraVFX.Core.Scheduler"),
		}
		table.insert(opened, place)
		return place
	end

	T.afterEach(function()
		for _, place in opened do
			place.AstraVFX._reset()
			place.Scheduler.clear()
			place.Net._reset()
		end
		table.clear(opened)
	end)

	local function frames(seconds: number)
		for _ = 1, math.ceil(seconds / DT) do
			ctx.fakes:step(DT)
		end
	end

	-- `game` for an example script: GetService answers only the services listed (anything else is an error, so a
	-- new service dependency of the examples is noticed here). The place counts as fully loaded (IsLoaded).
	local function fakeGame(services: { [string]: any }): any
		return {
			GetService = function(_self: any, name: string): any
				local service = services[name]
				if service == nil then
					error("example script uses service " .. name .. ", which this spec does not fake", 2)
				end
				return service
			end,
			IsLoaded = function(_self: any): boolean
				return true
			end,
			Loaded = {
				Wait = function(_self: any)
					error("game.Loaded:Wait() while IsLoaded() is true", 2)
				end,
			},
		}
	end

	-- ReplicatedStorage with the WaitForChild Lune lacks: the child must already exist (it does in the place).
	local function replicatedStorage(place: Place): any
		local real = place.root:FindFirstChild("ReplicatedStorage")
		return {
			WaitForChild = function(_self: any, name: string): any
				local child = real:FindFirstChild(name)
				if child == nil then
					error("ReplicatedStorage." .. name .. " does not exist in the example place", 2)
				end
				return child
			end,
		}
	end

	local function fakeRemote(): any
		local remote: any = { calls = {}, OnClientEvent = Signal.new() }
		function remote.FireAllClients(self: any, payload: any)
			table.insert(self.calls, R("all", payload))
		end
		function remote.FireClient(self: any, player: any, payload: any)
			table.insert(self.calls, R("client", player, payload))
		end
		return remote
	end

	local function script(place: Place, path: string): any
		return place.loader:resolve(path)
	end

	local function containerNamed(place: Place, name: string): any
		local workspace = place.loader.game:GetService("Workspace")
		return workspace:FindFirstChild("AstraVFX_" .. name)
	end

	T.describe("Example place", function()
		T.itIf(isLune, "maps the runtime, both effect files and both scripts like the Rojo build", function()
			local place = openPlace()
			local module = script(place, "ReplicatedStorage.AstraVFX")
			expect(module.ClassName).toBe("ModuleScript")
			local effects = module:FindFirstChild("Effects")
			expect(effects).never.toBeNil()
			for _, name in { "FireExplosion", "VioletImpact" } do
				local value = effects:FindFirstChild(name)
				expect(value).never.toBeNil()
				expect(value.ClassName).toBe("StringValue")
				expect(string.sub(value.Value, 1, 1)).toBe("{")
			end
			expect(script(place, "ServerScriptService.AstraVFXDemo").ClassName).toBe("Script")
			expect(script(place, "StarterPlayer.StarterPlayerScripts.AstraVFXClient").ClassName).toBe("LocalScript")
			expect(script(place, "Workspace.VFXTarget"):IsA("BasePart")).toBe(true)
			if type(ctx.readFile) == "function" then
				expect(effects.VioletImpact.Value).toBe(ctx.readFile("effects/VioletImpact.vfx.json"))
			end
		end)

		T.itIf(isLune, "registers both effects lazily from AstraVFX.Effects, valid without warnings", function()
			local place = openPlace()
			expect(place.AstraVFX.GetNames()).toEqual({ "FireExplosion", "VioletImpact" })
			for _, value in script(place, "ReplicatedStorage.AstraVFX.Effects"):GetChildren() do
				local result = place.AstraVFX.Validate(value.Value)
				expect(result.errors).toEqual({})
				expect(result.warnings).toEqual({})
			end
		end)

		T.itIf(isLune, "FireExplosion fires its Impact marker and finishes at every quality", function()
			local place = openPlace()
			for _, quality in { "Low", "Medium", "High" } do
				local events: { string } = {}
				local handle =
					place.AstraVFX.Play("FireExplosion", { Position = Vector3.new(0, 0, 0), Quality = quality })
				handle.Event:Connect(function(name: string)
					table.insert(events, name .. "@" .. string.format("%.2f", handle:GetTime()))
				end)
				local finished: string? = nil
				handle.Finished:Connect(function(reason: string)
					finished = reason
				end)
				frames(0.1)
				expect(events).toEqual({})
				frames(0.1)
				expect(#events).toBe(1)
				expect(string.sub(events[1], 1, 7)).toBe("Impact@")
				frames(4)
				expect(finished).toBe("finished")
				expect(place.AstraVFX.ActiveCount()).toBe(0)
			end
		end)
	end)

	T.describe("AstraVFXDemo.server.luau", function()
		T.itIf(isLune, "PlayAll VioletImpact at VFXTarget every 4 s; damage on its own timer", function()
			local place = openPlace()
			local target = script(place, "Workspace.VFXTarget")
			target.CFrame = CFrame.new(3, 1, -24)
			local reliable, unreliable = fakeRemote(), fakeRemote()
			local waits: { number } = {}
			local delays: { any } = {}
			local STOP = { "stop the endless cast loop" }
			local fakeTask = {
				wait = function(seconds: number): number
					table.insert(waits, seconds)
					if #waits == 1 then
						-- Net.Init() ran at the top of the script; Lune's RemoteEvents cannot fire, so use fakes
						expect(script(place, "ReplicatedStorage.AstraVFX"):FindFirstChild("AstraVFXNet")).never.toBeNil()
						place.Net._setRemotes(reliable, unreliable)
						return seconds
					end
					error(STOP, 0)
				end,
				delay = function(seconds: number, fn: any, ...: any)
					table.insert(delays, { seconds = seconds, fn = fn, args = table.pack(...) })
				end,
			}
			local players: { any } = {}
			local game = fakeGame({
				Players = {
					GetPlayers = function(_self: any): { any }
						return players
					end,
				},
				ReplicatedStorage = replicatedStorage(place),
			})
			local ok, err = pcall(function()
				place.loader:runScript(
					script(place, "ServerScriptService.AstraVFXDemo"),
					{ game = game, workspace = script(place, "Workspace"), task = fakeTask }
				)
			end)
			expect(ok).toBe(false)
			expect(err).toBe(STOP)
			expect(waits).toEqual({ 4, 4 })

			-- cosmetic: exactly one reliable PlayAll with a payload clients accept
			expect(#unreliable.calls).toBe(0)
			expect(#reliable.calls).toBe(1)
			expect(reliable.calls[1][1]).toBe("all")
			local payload = reliable.calls[1][2]
			expect(payload.name).toBe("VioletImpact")
			expect(payload.cframe.Position).toBeCloseTo(Vector3.new(3, 1, -24), 1e-4)
			local client = openPlace()
			local name, options = client.Net._validate(payload)
			expect(name).toBe("VioletImpact")
			expect(options.CFrame.Position).toBeCloseTo(Vector3.new(3, 1, -24), 1e-4)

			-- gameplay: an independent server timer (0.6 s), damage only within 10 studs
			expect(#delays).toBe(1)
			expect(delays[1].seconds).toBe(0.6)
			expect(delays[1].args[1]).toBeCloseTo(Vector3.new(3, 1, -24), 1e-4)
			-- (Lune Parts cannot read the derived Position property, so the root part is a table as well)
			local function character(position: Vector3): (any, any)
				local root = {
					Name = "HumanoidRootPart",
					Position = position,
					IsA = function(_self: any, className: string): boolean
						return className == "BasePart"
					end,
				}
				local humanoid: any = { damage = 0 }
				function humanoid.TakeDamage(self: any, amount: number)
					self.damage += amount
				end
				local model: any = {
					FindFirstChildOfClass = function(_self: any, className: string): any
						return if className == "Humanoid" then humanoid else nil
					end,
					FindFirstChild = function(_self: any, childName: string): any
						return if childName == "HumanoidRootPart" then root else nil
					end,
				}
				return model, humanoid
			end
			local nearModel, near = character(Vector3.new(8, 1, -24))
			local farModel, far = character(Vector3.new(40, 1, -24))
			players = { { Character = nearModel }, { Character = farModel }, { Character = nil } }
			delays[1].fn(table.unpack(delays[1].args, 1, delays[1].args.n))
			expect(near.damage).toBe(10)
			expect(far.damage).toBe(0)
		end)
	end)

	T.describe("AstraVFXClient.client.luau", function()
		type Client = {
			place: Place,
			inputBegan: any,
			raycasts: { any },
			tweens: { any },
			camera: any,
			character: any,
			root: BasePart,
			hit: Vector3,
		}

		-- Runs the client script against fakes; the character is a real Model in the runtime's Workspace (attach
		-- targets must be inside a WorldRoot).
		local function startClient(): Client
			local place = openPlace()
			local workspace = place.loader.game:GetService("Workspace")
			local character = Instance.new("Model")
			character.Name = "Player1"
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = CFrame.new(0, 3, 0)
			root.Parent = character
			character.Parent = workspace
			local client: Client = {
				place = place,
				inputBegan = Signal.new(),
				raycasts = {},
				tweens = {},
				camera = nil :: any,
				character = character,
				root = root,
				hit = Vector3.new(12, 0, -8),
			}
			client.camera = {
				FieldOfView = 70,
				ViewportPointToRay = function(_self: any, x: number, y: number): Ray
					return Ray.new(Vector3.new(x, 50, y), Vector3.new(0, -1, 0))
				end,
			}
			local scriptWorkspace = {
				CurrentCamera = client.camera,
				Raycast = function(_self: any, origin: Vector3, direction: Vector3, params: any): any
					table.insert(client.raycasts, { origin = origin, direction = direction, params = params })
					return { Position = client.hit }
				end,
			}
			local game = fakeGame({
				Players = { LocalPlayer = { Character = character } },
				ReplicatedStorage = replicatedStorage(place),
				TweenService = {
					Create = function(_self: any, instance: any, info: any, goals: any): any
						local tween: any = { instance = instance, info = info, goals = goals, played = false }
						function tween.Play(self: any)
							self.played = true
						end
						table.insert(client.tweens, tween)
						return tween
					end,
				},
				UserInputService = {
					InputBegan = client.inputBegan,
					GetMouseLocation = function(_self: any): Vector2
						return Vector2.new(400, 300)
					end,
				},
			})
			place.loader:runScript(script(place, "StarterPlayer.StarterPlayerScripts.AstraVFXClient"), {
				game = game,
				workspace = scriptWorkspace,
				RaycastParams = {
					new = function(): any
						return {}
					end,
				},
				TweenInfo = {
					new = function(time: number, style: any, direction: any): any
						return { Time = time, EasingStyle = style, EasingDirection = direction }
					end,
				},
			})
			return client
		end

		local function press(client: Client, keyCode: any, gameProcessed: boolean?)
			client.inputBegan:Fire(
				{ KeyCode = keyCode, UserInputType = Enum.UserInputType.Keyboard },
				gameProcessed == true
			)
		end

		T.itIf(isLune, "starts Net.Listen and preloads two FireExplosion copies", function()
			local client = startClient()
			local module = script(client.place, "ReplicatedStorage.AstraVFX")
			-- no remotes replicated yet: the listener waits for the AstraVFXNet folder (ChildAdded)
			expect(ctx.fakes:signalFor(module, "ChildAdded"):connectionCount()).toBe(1)
			expect(client.place.Pool.count()).toBe(2)
			expect(client.place.AstraVFX.ActiveCount()).toBe(0)
			expect(client.inputBegan:count()).toBe(1)
		end)

		T.itIf(isLune, "F plays FireExplosion at the mouse hit; its Impact event kicks the camera FOV", function()
			local client = startClient()
			local AstraVFX = client.place.AstraVFX
			press(client, Enum.KeyCode.F, true) -- typing in chat: ignored
			expect(#client.raycasts).toBe(0)
			expect(AstraVFX.ActiveCount()).toBe(0)

			press(client, Enum.KeyCode.F)
			expect(#client.raycasts).toBe(1)
			local ray = client.raycasts[1]
			expect(ray.origin).toBeCloseTo(Vector3.new(400, 50, 300), 1e-6)
			expect(ray.direction).toBeCloseTo(Vector3.new(0, -1000, 0), 1e-6)
			expect(ray.params.FilterType).toBe(Enum.RaycastFilterType.Exclude)
			expect(ray.params.FilterDescendantsInstances).toEqual({ client.character })
			expect(AstraVFX.ActiveCount()).toBe(1)
			expect(client.place.Pool.count()).toBe(1) -- one preloaded copy taken
			local container = containerNamed(client.place, "FireExplosion")
			expect(container).never.toBeNil()
			expect(container.Root.CFrame.Position).toBeCloseTo(client.hit, 1e-4)

			frames(0.08)
			expect(#client.tweens).toBe(0)
			frames(0.12)
			expect(#client.tweens).toBe(1)
			local tween = client.tweens[1]
			expect(tween.instance).toBe(client.camera)
			expect(tween.goals).toEqual({ FieldOfView = 70 })
			expect(tween.info.Time).toBe(0.3)
			expect(tween.played).toBe(true)
			expect(client.camera.FieldOfView).toBe(76)

			frames(4)
			expect(AstraVFX.ActiveCount()).toBe(0)
			expect(client.place.Pool.count()).toBe(2) -- the finished copy went back to the pool
		end)

		T.itIf(isLune, "G attaches VioletImpact to the character root (Offset 6 studs ahead, Scale 0.4)", function()
			local client = startClient()
			local AstraVFX = client.place.AstraVFX
			press(client, Enum.KeyCode.G)
			expect(AstraVFX.ActiveCount()).toBe(1)
			local container = containerNamed(client.place, "VioletImpact")
			expect(container).never.toBeNil()
			expect(container.Root.CFrame.Position).toBeCloseTo(Vector3.new(0, 3, -6), 1e-4)
			client.root.CFrame = CFrame.new(10, 3, 0)
			frames(3 * DT)
			expect(container.Root.CFrame.Position).toBeCloseTo(Vector3.new(10, 3, -6), 1e-4)
			press(client, Enum.KeyCode.H) -- other keys: nothing
			expect(AstraVFX.ActiveCount()).toBe(1)
			frames(4)
			expect(AstraVFX.ActiveCount()).toBe(0)
		end)
	end)
end
