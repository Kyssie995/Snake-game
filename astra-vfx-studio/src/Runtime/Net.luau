--!strict
--[[
	Net — optional server -> client replication of effects (docs/ARCHITECTURE.md §5.3, docs/MODULE_CONTRACTS.md §19,
	docs/ROBLOX_API_CONSTRAINTS.md §21 and K51).

	Gameplay stays server-authoritative; effects are cosmetic and rendered by the clients. The server never builds
	VFX instances: it sends a small payload, every client validates it and plays the effect locally through
	AstraVFX.TryPlay. There is deliberately NO client -> server path.

	Server:
	  Net.Init() -> Folder                         creates (or reuses) Folder "AstraVFXNet" under the AstraVFX module
	                                               with RemoteEvent "Play" and UnreliableRemoteEvent "PlayUnreliable"
	                                               (both classes exist in API dump 0.745). Children are created
	                                               before the folder is parented. Called lazily by the Play*
	                                               functions when needed.
	  Net.PlayAll(name, options?)                  FireAllClients
	  Net.PlayFor(players, name, options?)         FireClient for one Player or a list of players
	  Net.PlayNear(position, radius, name, options?) -> { Player }
	                                               FireClient for every player whose character root
	                                               (HumanoidRootPart, else PrimaryPart) is within `radius` studs
	Client:
	  Net.Listen() -> Listener                     connects OnClientEvent of both remotes (idempotent). Never yields:
	                                               when the folder / remotes have not replicated yet it watches
	                                               ChildAdded and connects when they appear. listener:Disconnect().

	Options (server side; anything else is an error, because it cannot be replicated meaningfully):
	  CFrame, Position, Attach (Instance reference), Scale, TimeScale, Seed, Quality, Unreliable (boolean).
	Payload (serialisable only): { name, cframe?, position?, attach?, scale?, timeScale?, seed?, quality? }.
	When Attach is given without CFrame / Position the server adds the target's current CFrame, so clients that
	do not have the instance (StreamingEnabled: the reference arrives as nil, ST-1) play at that CFrame instead.
	Unreliable = true uses the UnreliableRemoteEvent (unordered, may drop; for replaceable cosmetic effects only);
	a payload whose estimated size exceeds Net.UNRELIABLE_BUDGET (900 bytes, below the documented 1000-byte drop
	limit, RE-3/RE-4) falls back to the reliable RemoteEvent.

	Client validation (Net._decode / Net._validate): the payload must be a table; `name` a non-empty string of at
	most Net.MAX_NAME_LENGTH (100) characters naming a registered effect; cframe a CFrame, position a Vector3,
	attach a BasePart / Attachment / Model (a missing attach — streamed out — is fine), scale / timeScale / seed
	finite numbers, quality "Low" | "Medium" | "High" | "Auto". Anything else makes the payload malformed and it is
	ignored (counted in Net.stats.ignored, never an error). scale is clamped to [0.05, 20], timeScale to
	[0.05, 10]. Unknown payload keys are ignored (forward compatibility).

	Test hooks: Net._encode(name, options?) -> (payload, unreliable), Net._decode(payload) -> (name?, options?,
	reason?), Net._validate(payload) (decode + registry check), Net._handle(payload) -> Handle? (what the client
	listener does), Net._playersNear(position, radius, players) (pure filter, works with fake player tables),
	Net._setRemotes(reliable?, unreliable?) (inject fake remotes), Net._reset().
]]

local Constants = require(script.Parent.Core.Constants)
local Env = require(script.Parent.Core.Env)
local Types = require(script.Parent.Core.Types)

type PlayOptions = Types.PlayOptions

export type Payload = {
	name: string,
	cframe: CFrame?,
	position: Vector3?,
	attach: Instance?,
	scale: number?,
	timeScale: number?,
	seed: number?,
	quality: string?,
}

export type NetOptions = {
	CFrame: CFrame?,
	Position: Vector3?,
	Attach: Instance?,
	Scale: number?,
	TimeScale: number?,
	Seed: number?,
	Quality: string?,
	Unreliable: boolean?,
}

export type Listener = {
	Connected: boolean,
	Disconnect: (self: Listener) -> (),
}

local Net = {}

Net.FOLDER_NAME = "AstraVFXNet"
Net.RELIABLE_NAME = "Play"
Net.UNRELIABLE_NAME = "PlayUnreliable"
Net.MAX_NAME_LENGTH = Constants.NAME_MAX_LENGTH
Net.SCALE_MIN = 0.05
Net.SCALE_MAX = 20
Net.TIME_SCALE_MIN = 0.05
Net.TIME_SCALE_MAX = 10
Net.UNRELIABLE_BUDGET = 900
Net.stats = { received = 0, played = 0, ignored = 0 }

local INF = math.huge
local QUALITIES: { [string]: boolean } = { Low = true, Medium = true, High = true, Auto = true }
local OPTION_KEYS: { [string]: boolean } = {
	CFrame = true,
	Position = true,
	Attach = true,
	Scale = true,
	TimeScale = true,
	Seed = true,
	Quality = true,
	Unreliable = true,
}

local runtime: any = nil -- the AstraVFX API table (bound by init.luau)
local reliableRemote: any = nil
local unreliableRemote: any = nil
local listener: Listener? = nil

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function describe(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return typeof(v)
end

-- Called by init.luau so Net never requires its parent at load time (no require cycle).
function Net._bind(api: any)
	runtime = api
end

local function api(): any
	if runtime == nil then
		-- Net was required on its own: load the runtime API (it binds itself). The cast keeps static require
		-- tracing out of this deliberate back-reference.
		local parent: any = script.Parent
		runtime = (require :: any)(parent)
	end
	return runtime
end

local function isAttachTarget(v: any): boolean
	return typeof(v) == "Instance" and (v:IsA("BasePart") or v:IsA("Attachment") or v:IsA("PVInstance"))
end

-- Current CFrame of an attach target (fallback for clients without the instance), or nil.
local function currentCFrame(target: Instance): CFrame?
	if target:IsA("BasePart") then
		return (target :: BasePart).CFrame
	elseif target:IsA("Attachment") then
		local ok, cf = pcall(function(): CFrame
			return (target :: Attachment).WorldCFrame
		end)
		if ok then
			return cf
		end
		local parent = target.Parent
		if parent and parent:IsA("BasePart") then
			return (parent :: BasePart).CFrame * (target :: Attachment).CFrame
		end
		return nil
	elseif target:IsA("PVInstance") then
		return (target :: PVInstance):GetPivot()
	end
	return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Payloads
-- ─────────────────────────────────────────────────────────────────────────────

local VALUE_SIZE: { [string]: number } = {
	number = 9,
	boolean = 2,
	Vector3 = 13,
	CFrame = 20,
	Instance = 6,
}

-- Rough serialized size in bytes (docs/ROBLOX_API_CONSTRAINTS.md RE-4 cost estimates).
function Net._estimateSize(payload: { [string]: any }): number
	local size = 8
	for key, value in payload do
		size += #tostring(key) + 3
		local t = typeof(value)
		if t == "string" then
			size += #value + 3
		else
			size += VALUE_SIZE[t] or 16
		end
	end
	return size
end

local function checkName(fn: string, name: any)
	if type(name) ~= "string" or name == "" or #name > Net.MAX_NAME_LENGTH then
		error(
			"Net."
				.. fn
				.. ": name must be a non-empty string of at most "
				.. Net.MAX_NAME_LENGTH
				.. " characters, got "
				.. describe(name),
			3
		)
	end
end

-- Server side: PlayOptions subset -> (payload, use the unreliable remote).
function Net._encode(name: string, options: NetOptions?): (Payload, boolean)
	checkName("Play", name)
	local o: any = options or {}
	if type(o) ~= "table" then
		error("Net.Play: options must be a table, got " .. typeof(o), 2)
	end
	for key in o do
		if type(key) ~= "string" or not OPTION_KEYS[key] then
			error(
				"Net.Play: option "
					.. describe(key)
					.. " cannot be replicated (allowed: CFrame, Position, Attach, Scale, TimeScale, Seed, Quality, Unreliable)",
				2
			)
		end
	end
	local payload: Payload = { name = name }
	if o.CFrame ~= nil then
		if typeof(o.CFrame) ~= "CFrame" then
			error("Net.Play: CFrame must be a CFrame, got " .. describe(o.CFrame), 2)
		end
		payload.cframe = o.CFrame
	end
	if o.Position ~= nil then
		if typeof(o.Position) ~= "Vector3" then
			error("Net.Play: Position must be a Vector3, got " .. describe(o.Position), 2)
		end
		payload.position = o.Position
	end
	if o.Attach ~= nil then
		if not isAttachTarget(o.Attach) then
			error("Net.Play: Attach must be a BasePart, Attachment or Model, got " .. describe(o.Attach), 2)
		end
		payload.attach = o.Attach
		if payload.cframe == nil and payload.position == nil then
			payload.cframe = currentCFrame(o.Attach)
		end
	end
	if o.Scale ~= nil then
		if not (isFinite(o.Scale) and o.Scale > 0) then
			error("Net.Play: Scale must be a finite number > 0, got " .. tostring(o.Scale), 2)
		end
		payload.scale = o.Scale
	end
	if o.TimeScale ~= nil then
		if not (isFinite(o.TimeScale) and o.TimeScale >= 0) then
			error("Net.Play: TimeScale must be a finite number >= 0, got " .. tostring(o.TimeScale), 2)
		end
		payload.timeScale = o.TimeScale
	end
	if o.Seed ~= nil then
		if not isFinite(o.Seed) then
			error("Net.Play: Seed must be a finite number, got " .. tostring(o.Seed), 2)
		end
		payload.seed = o.Seed
	end
	if o.Quality ~= nil then
		if not (type(o.Quality) == "string" and QUALITIES[o.Quality]) then
			error('Net.Play: Quality must be "Low", "Medium", "High" or "Auto", got ' .. describe(o.Quality), 2)
		end
		payload.quality = o.Quality
	end
	if o.Unreliable ~= nil and type(o.Unreliable) ~= "boolean" then
		error("Net.Play: Unreliable must be a boolean, got " .. describe(o.Unreliable), 2)
	end
	local unreliable = o.Unreliable == true and Net._estimateSize(payload :: any) <= Net.UNRELIABLE_BUDGET
	return payload, unreliable
end

-- Client side: structural validation + clamping. Returns (name, PlayOptions) or (nil, nil, reason).
function Net._decode(payload: any): (string?, PlayOptions?, string?)
	if type(payload) ~= "table" then
		return nil, nil, "payload is not a table"
	end
	local name = payload.name
	if type(name) ~= "string" or name == "" or #name > Net.MAX_NAME_LENGTH then
		return nil, nil, "invalid name"
	end
	local cframe = payload.cframe
	if cframe ~= nil and typeof(cframe) ~= "CFrame" then
		return nil, nil, "cframe is not a CFrame"
	end
	local position = payload.position
	if position ~= nil and typeof(position) ~= "Vector3" then
		return nil, nil, "position is not a Vector3"
	end
	local attach = payload.attach
	if attach ~= nil and not isAttachTarget(attach) then
		return nil, nil, "attach is not a BasePart, Attachment or Model"
	end
	local scale = payload.scale
	if scale ~= nil then
		if not isFinite(scale) then
			return nil, nil, "scale is not a finite number"
		end
		scale = math.clamp(scale, Net.SCALE_MIN, Net.SCALE_MAX)
	end
	local timeScale = payload.timeScale
	if timeScale ~= nil then
		if not isFinite(timeScale) then
			return nil, nil, "timeScale is not a finite number"
		end
		timeScale = math.clamp(timeScale, Net.TIME_SCALE_MIN, Net.TIME_SCALE_MAX)
	end
	local seed = payload.seed
	if seed ~= nil and not isFinite(seed) then
		return nil, nil, "seed is not a finite number"
	end
	local quality = payload.quality
	if quality ~= nil and not (type(quality) == "string" and QUALITIES[quality]) then
		return nil, nil, "invalid quality"
	end
	local options: PlayOptions = {
		CFrame = if cframe ~= nil then cframe elseif position ~= nil then CFrame.new(position) else nil,
		Attach = attach,
		Scale = scale,
		TimeScale = timeScale,
		Seed = seed,
		Quality = quality :: any,
	}
	return name, options, nil
end

-- Client side: decode + the name must be a registered effect.
function Net._validate(payload: any): (string?, PlayOptions?, string?)
	local name, options, reason = Net._decode(payload)
	if name == nil then
		return nil, nil, reason
	end
	if not api().IsRegistered(name) then
		return nil, nil, "unknown effect " .. string.format("%q", name)
	end
	return name, options, nil
end

-- Client side: what the listener does with one received payload. Returns the handle or nil (ignored).
function Net._handle(payload: any): any
	Net.stats.received += 1
	local name, options = Net._validate(payload)
	if name == nil then
		Net.stats.ignored += 1
		return nil
	end
	local handle, err = api().TryPlay(name, options)
	if handle == nil then
		Net.stats.ignored += 1
		warn("[AstraVFX] Net: could not play " .. name .. ": " .. tostring(err))
		return nil
	end
	Net.stats.played += 1
	return handle
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Remotes
-- ─────────────────────────────────────────────────────────────────────────────

local function ensureChild(folder: Instance, className: string, name: string): Instance
	local existing = folder:FindFirstChild(name)
	if existing ~= nil and existing.ClassName == className then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

-- Server: creates (or reuses) the remotes under the AstraVFX module.
function Net.Init(): Folder
	local module: Instance = script.Parent
	local found: Instance? = module:FindFirstChild(Net.FOLDER_NAME)
	local f: Folder
	local created = false
	if found ~= nil and found:IsA("Folder") then
		f = found :: Folder
	else
		f = Instance.new("Folder")
		f.Name = Net.FOLDER_NAME
		created = true
	end
	reliableRemote = ensureChild(f, "RemoteEvent", Net.RELIABLE_NAME)
	unreliableRemote = ensureChild(f, "UnreliableRemoteEvent", Net.UNRELIABLE_NAME)
	if created then
		f.Parent = module
	end
	return f
end

-- Test hook: use fake remotes (tables with FireAllClients / FireClient / OnClientEvent).
function Net._setRemotes(reliable: any, unreliable: any)
	reliableRemote = reliable
	unreliableRemote = unreliable
end

local function remoteFor(unreliable: boolean): any
	if reliableRemote == nil then
		Net.Init()
	end
	if unreliable and unreliableRemote ~= nil then
		return unreliableRemote
	end
	return reliableRemote
end

-- Server: plays an effect on every client.
function Net.PlayAll(name: string, options: NetOptions?)
	local payload, unreliable = Net._encode(name, options)
	remoteFor(unreliable):FireAllClients(payload)
end

-- Server: plays an effect on one player or a list of players.
function Net.PlayFor(players: any, name: string, options: NetOptions?)
	local payload, unreliable = Net._encode(name, options)
	local list: { any }
	if typeof(players) == "Instance" then
		list = { players }
	elseif type(players) == "table" then
		list = players
	else
		error("Net.PlayFor: expected a Player or a list of players, got " .. typeof(players), 2)
	end
	local remote = remoteFor(unreliable)
	for _, player in list do
		remote:FireClient(player, payload)
	end
end

-- Character root of a player (HumanoidRootPart, else the model's PrimaryPart), or nil.
local function characterRoot(player: any): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Players whose character root lies within `radius` studs of `position` (pure; fake player tables work).
function Net._playersNear(position: Vector3, radius: number, players: { any }): { any }
	local out = {}
	for _, player in players do
		local ok, root = pcall(characterRoot, player)
		if ok and root ~= nil then
			if ((root :: BasePart).CFrame.Position - position).Magnitude <= radius then
				table.insert(out, player)
			end
		end
	end
	return out
end

-- Server: plays an effect for the players near `position`. Returns the players it was sent to.
function Net.PlayNear(position: Vector3, radius: number, name: string, options: NetOptions?): { any }
	if typeof(position) ~= "Vector3" then
		error("Net.PlayNear: position must be a Vector3, got " .. describe(position), 2)
	end
	if not (isFinite(radius) and radius >= 0) then
		error("Net.PlayNear: radius must be a finite number >= 0, got " .. tostring(radius), 2)
	end
	local payload, unreliable = Net._encode(name, options)
	local playersService: any = Env.getService("Players")
	local near = Net._playersNear(position, radius, playersService:GetPlayers())
	if #near > 0 then
		local remote = remoteFor(unreliable)
		for _, player in near do
			remote:FireClient(player, payload)
		end
	end
	return near
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Client
-- ─────────────────────────────────────────────────────────────────────────────

local function onPayload(payload: any)
	local ok, err = pcall(Net._handle, payload)
	if not ok then
		Net.stats.ignored += 1
		warn("[AstraVFX] Net: payload handling failed: " .. tostring(err))
	end
end

-- Client: plays every effect the server sends. Idempotent; never yields.
function Net.Listen(): Listener
	local existing = listener
	if existing and existing.Connected then
		return existing
	end
	local connections: { any } = {}
	local hooked: { [any]: boolean } = {}
	local self: Listener

	local function hook(remote: any)
		if remote ~= nil and not hooked[remote] and self.Connected then
			hooked[remote] = true
			table.insert(connections, remote.OnClientEvent:Connect(onPayload))
		end
	end

	local function hookFolder(folder: Instance)
		hook(folder:FindFirstChild(Net.RELIABLE_NAME))
		hook(folder:FindFirstChild(Net.UNRELIABLE_NAME))
		if not hooked[folder] then
			hooked[folder] = true
			table.insert(
				connections,
				folder.ChildAdded:Connect(function(child: Instance)
					if child.Name == Net.RELIABLE_NAME or child.Name == Net.UNRELIABLE_NAME then
						hook(child)
					end
				end)
			)
		end
	end

	self = {
		Connected = true,
		Disconnect = function(l: Listener)
			if not l.Connected then
				return
			end
			l.Connected = false
			for _, c in connections do
				c:Disconnect()
			end
			table.clear(connections)
			if listener == l then
				listener = nil
			end
		end,
	}
	listener = self

	if reliableRemote ~= nil or unreliableRemote ~= nil then
		hook(reliableRemote)
		hook(unreliableRemote)
		return self
	end
	local module: Instance = script.Parent
	local folder = module:FindFirstChild(Net.FOLDER_NAME)
	if folder ~= nil then
		hookFolder(folder)
	else
		table.insert(
			connections,
			module.ChildAdded:Connect(function(child: Instance)
				if child.Name == Net.FOLDER_NAME then
					hookFolder(child)
				end
			end)
		)
	end
	return self
end

-- Test hook: disconnects the listener, forgets the remotes and the stats.
function Net._reset()
	local l = listener
	if l then
		l:Disconnect()
	end
	listener = nil
	reliableRemote = nil
	unreliableRemote = nil
	Net.stats.received = 0
	Net.stats.played = 0
	Net.stats.ignored = 0
end

return Net
