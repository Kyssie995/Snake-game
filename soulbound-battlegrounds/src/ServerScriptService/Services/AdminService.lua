--!strict
-- AdminService: chat commands for development/testing. Whitelist only.
-- Commands (prefix ;):
--   ;xp <amount>            give Soul XP to your equipped weapon
--   ;level <n>              set equipped weapon level
--   ;tokens <amount>        give Spirit Tokens
--   ;weapon <id>            unlock + equip a weapon
--   ;energy                 fill Soul Energy to max
--   ;resetdata              wipe your profile to defaults (careful!)
--   ;dummyxp                reset your daily dummy XP cap
--   ;hitboxdebug            toggle hitbox visualization

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Modules.CombatConstants)
local WeaponConfigs = require(ReplicatedStorage.Modules.WeaponConfigs)

local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local CombatService = require(script.Parent.CombatService)

local AdminService = {}

-- Add your team's UserIds here. Studio always allows.
local ADMIN_USER_IDS: { [number]: boolean } = {
	-- [12345678] = true,
}

local function isAdmin(player: Player): boolean
	return RunService:IsStudio() or ADMIN_USER_IDS[player.UserId] == true
end

local function handleCommand(player: Player, message: string)
	if not isAdmin(player) or message:sub(1, 1) ~= ";" then
		return
	end
	local args = message:sub(2):split(" ")
	local cmd = args[1] and args[1]:lower()
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end

	if cmd == "xp" then
		local amount = tonumber(args[2]) or 100
		ProgressionService.AwardXP(player, amount)
	elseif cmd == "level" then
		local target = math.clamp(tonumber(args[2]) or 1, 1, Constants.PROGRESSION.MAX_LEVEL)
		local data = profile.weapons[profile.equippedWeapon]
		if data then
			data.level = target
			data.xp = 0
		end
	elseif cmd == "tokens" then
		profile.spiritTokens += tonumber(args[2]) or 10
	elseif cmd == "weapon" then
		local id = args[2]
		if id and WeaponConfigs.Get(id) then
			if not table.find(profile.unlockedWeapons, id) then
				table.insert(profile.unlockedWeapons, id)
				profile.weapons[id] = profile.weapons[id] or { xp = 0, level = 1 }
			end
			profile.equippedWeapon = id
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0
			end
		end
	elseif cmd == "energy" then
		local character = player.Character
		if character then
			CombatService.AddEnergy(character, Constants.ENERGY.MAX)
		end
	elseif cmd == "resetdata" then
		profile.weapons = { [WeaponConfigs.STARTER_WEAPON] = { xp = 0, level = 1 } }
		profile.unlockedWeapons = { WeaponConfigs.STARTER_WEAPON }
		profile.equippedWeapon = WeaponConfigs.STARTER_WEAPON
		profile.spiritTokens = 0
		profile.totalKills = 0
	elseif cmd == "dummyxp" then
		profile.dummyXPToday = 0
	elseif cmd == "hitboxdebug" then
		_G.SOULBOUND_DEBUG_HITBOX = not _G.SOULBOUND_DEBUG_HITBOX
	end
end

function AdminService.Init()
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(message)
			handleCommand(player, message)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.Chatted:Connect(function(message)
			handleCommand(player, message)
		end)
	end
end

return AdminService
