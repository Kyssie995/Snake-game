--!strict
-- CooldownManager: per-entity keyed cooldowns. Server-authoritative;
-- the client mirrors its own copy purely for UI radials.

local CooldownManager = {}

-- entityKey (Player or Model) -> { [cooldownName]: expiresAtClock }
local cooldowns: { [any]: { [string]: number } } = {}

function CooldownManager.Start(entity: any, name: string, duration: number)
	local map = cooldowns[entity]
	if not map then
		map = {}
		cooldowns[entity] = map
	end
	map[name] = os.clock() + duration
end

function CooldownManager.IsReady(entity: any, name: string): boolean
	local map = cooldowns[entity]
	if not map then
		return true
	end
	local expires = map[name]
	return expires == nil or os.clock() >= expires
end

function CooldownManager.TimeLeft(entity: any, name: string): number
	local map = cooldowns[entity]
	if not map then
		return 0
	end
	local expires = map[name]
	if not expires then
		return 0
	end
	return math.max(0, expires - os.clock())
end

-- Refund (perfect dodge refunds dash, Final Release halves a move's CD, etc.)
function CooldownManager.Reduce(entity: any, name: string, seconds: number)
	local map = cooldowns[entity]
	if map and map[name] then
		map[name] -= seconds
	end
end

function CooldownManager.Clear(entity: any, name: string?)
	if name then
		local map = cooldowns[entity]
		if map then
			map[name] = nil
		end
	else
		cooldowns[entity] = nil
	end
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	cooldowns[player] = nil
end)

return CooldownManager
