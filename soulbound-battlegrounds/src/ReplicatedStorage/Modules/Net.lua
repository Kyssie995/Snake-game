--!strict
-- Net: single owner of all RemoteEvents/RemoteFunctions.
-- Server calls Net.Init() once; clients call Net.Get*() which waits for creation.
-- All client->server remotes are rate-limited server-side in RegisterHandler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local REMOTE_EVENTS = {
	"AbilityRequest", -- client -> server {slot: number}
	"CombatRequest", -- client -> server {action: string, ...}
	"ClashInput", -- client -> server (mash press, no payload)
	"CombatFX", -- server -> clients {fx: string, ...}
	"HUDUpdate", -- server -> client {field: string, value: any}
	"ClashState", -- server -> clients {phase: string, ...}
}

local REMOTE_FUNCTIONS = {
	"ShopRequest", -- client -> server {action: "Buy"|"Equip", weapon: string}
}

local FOLDER_NAME = "Remotes"

function Net.Init()
	assert(RunService:IsServer(), "Net.Init must run on the server")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in REMOTE_EVENTS do
		local ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	for _, name in REMOTE_FUNCTIONS do
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function getFolder(): Folder
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Net.GetEvent(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.GetFunction(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

-- Server-side handler registration with a per-player token-bucket rate limit.
-- Any handler error or over-rate call is swallowed (never trust, never crash).
export type Handler = (player: Player, ...any) -> ()

local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

local function allow(player: Player, name: string, perSecond: number): boolean
	local pb = buckets[player]
	if not pb then
		pb = {}
		buckets[player] = pb
	end
	local b = pb[name]
	local now = os.clock()
	if not b then
		b = { tokens = perSecond, last = now }
		pb[name] = b
	end
	b.tokens = math.min(perSecond, b.tokens + (now - b.last) * perSecond)
	b.last = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

function Net.RegisterHandler(name: string, perSecond: number, handler: Handler)
	assert(RunService:IsServer(), "RegisterHandler is server-only")
	Net.GetEvent(name).OnServerEvent:Connect(function(player, ...)
		if not allow(player, name, perSecond) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(("[Net] handler %s errored: %s"):format(name, tostring(err)))
		end
	end)
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

-- Sanity guards for remote args coming from clients.
function Net.SafeVector3(v: any, maxMagnitude: number): Vector3?
	if typeof(v) ~= "Vector3" then
		return nil
	end
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then -- NaN check
		return nil
	end
	if v.Magnitude > maxMagnitude then
		return nil
	end
	return v
end

function Net.SafeString(s: any, maxLen: number): string?
	if typeof(s) ~= "string" or #s > maxLen then
		return nil
	end
	return s
end

return Net
