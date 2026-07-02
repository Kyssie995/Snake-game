--!strict
-- ProgressionService: Soul XP, weapon levels, unlock gating, Spirit Tokens,
-- and the ShopRequest purchase/equip flow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Modules.Net)
local Constants = require(ReplicatedStorage.Modules.CombatConstants)
local WeaponConfigs = require(ReplicatedStorage.Modules.WeaponConfigs)

local DataService = require(script.Parent.DataService)

local ProgressionService = {}

local P = Constants.PROGRESSION

local function pushHUD(player: Player, field: string, value: any)
	Net.GetEvent("HUDUpdate"):FireClient(player, { field = field, value = value })
end

local function dayStamp(): number
	return tonumber(os.date("!%j")) or 0
end

function ProgressionService.GetEquippedWeapon(player: Player): string?
	local profile = DataService.GetProfile(player)
	return profile and profile.equippedWeapon
end

function ProgressionService.GetWeaponLevel(player: Player, weaponId: string): number
	local profile = DataService.GetProfile(player)
	local data = profile and profile.weapons[weaponId]
	return data and data.level or 0
end

-- Is a given move slot unlocked at the player's current weapon level?
function ProgressionService.IsMoveUnlocked(player: Player, weaponId: string, slot: number): boolean
	local level = ProgressionService.GetWeaponLevel(player, weaponId)
	local requiredLevel = P.MOVE_UNLOCK_LEVELS[slot]
	return requiredLevel ~= nil and level >= requiredLevel
end

function ProgressionService.IsUltimateUnlocked(player: Player, weaponId: string): boolean
	return ProgressionService.GetWeaponLevel(player, weaponId) >= P.ULTIMATE_LEVEL
end

-- Highest aura tier reached (0 = none, 1..5 for levels 10/20/30/40/50)
function ProgressionService.GetAuraTier(player: Player, weaponId: string): number
	local level = ProgressionService.GetWeaponLevel(player, weaponId)
	local tier = 0
	for i, auraLevel in P.AURA_LEVELS do
		if level >= auraLevel then
			tier = i
		end
	end
	return tier
end

-- Push the full progression snapshot to a client (called on spawn so the
-- HUD isn't blank until the first XP/token event).
function ProgressionService.PushHUDSnapshot(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local weaponId = profile.equippedWeapon
	local data = profile.weapons[weaponId]
	if data then
		pushHUD(player, "WeaponXP", {
			weapon = weaponId,
			xp = data.xp,
			level = data.level,
			toNext = P.XPToNext(data.level),
		})
	end
	pushHUD(player, "Tokens", profile.spiritTokens)
end

function ProgressionService.AwardXP(player: Player, amount: number, isDummy: boolean?)
	local profile = DataService.GetProfile(player)
	if not profile or amount <= 0 then
		return
	end

	if isDummy then
		local today = dayStamp()
		if profile.dummyXPDay ~= today then
			profile.dummyXPDay = today
			profile.dummyXPToday = 0
		end
		amount = math.floor(amount * P.DUMMY_XP_RATE)
		local room = P.DUMMY_DAILY_CAP - profile.dummyXPToday
		amount = math.clamp(amount, 0, math.max(0, room))
		if amount <= 0 then
			return
		end
		profile.dummyXPToday += amount
	end

	local weaponId = profile.equippedWeapon
	local data = profile.weapons[weaponId]
	if not data or data.level >= P.MAX_LEVEL then
		return
	end

	data.xp += amount
	local leveled = false
	while data.level < P.MAX_LEVEL and data.xp >= P.XPToNext(data.level) do
		data.xp -= P.XPToNext(data.level)
		data.level += 1
		leveled = true
	end

	pushHUD(player, "WeaponXP", { weapon = weaponId, xp = data.xp, level = data.level, toNext = P.XPToNext(data.level) })
	if leveled then
		Net.GetEvent("CombatFX"):FireClient(player, { fx = "LevelUp", level = data.level, weapon = weaponId })
	end
end

function ProgressionService.AwardKill(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	profile.totalKills += 1
	ProgressionService.AwardXP(player, P.KILL_XP)
	if profile.totalKills % Constants.TOKENS.KILL_BONUS_EVERY == 0 then
		profile.spiritTokens += 1
		pushHUD(player, "Tokens", profile.spiritTokens)
	end
end

function ProgressionService.AwardAssist(player: Player)
	ProgressionService.AwardXP(player, P.ASSIST_XP)
end

local function handleShopRequest(player: Player, request: any): any
	if typeof(request) ~= "table" then
		return { ok = false, err = "bad request" }
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return { ok = false, err = "no profile" }
	end
	local weaponId = Net.SafeString(request.weapon, 32)
	local config = weaponId and WeaponConfigs.Get(weaponId)
	if not config or not weaponId then
		return { ok = false, err = "unknown weapon" }
	end

	if request.action == "Buy" then
		if table.find(profile.unlockedWeapons, weaponId) then
			return { ok = false, err = "already owned" }
		end
		if profile.spiritTokens < config.tokenCost then
			return { ok = false, err = "not enough tokens" }
		end
		profile.spiritTokens -= config.tokenCost
		table.insert(profile.unlockedWeapons, weaponId)
		profile.weapons[weaponId] = profile.weapons[weaponId] or { xp = 0, level = 1 }
		pushHUD(player, "Tokens", profile.spiritTokens)
		return { ok = true, tokens = profile.spiritTokens }
	elseif request.action == "Equip" then
		if not table.find(profile.unlockedWeapons, weaponId) then
			return { ok = false, err = "not owned" }
		end
		profile.equippedWeapon = weaponId
		-- CombatService re-reads equipped weapon on respawn; force one now
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0 -- respawn with new weapon (alpha simplicity)
		end
		return { ok = true }
	end
	return { ok = false, err = "bad action" }
end

function ProgressionService.Init()
	Net.GetFunction("ShopRequest").OnServerInvoke = handleShopRequest

	-- Playtime tokens
	task.spawn(function()
		while true do
			task.wait(Constants.TOKENS.MINUTES_PER_TOKEN * 60)
			for _, player in Players:GetPlayers() do
				local profile = DataService.GetProfile(player)
				if profile then
					profile.spiritTokens += 1
					pushHUD(player, "Tokens", profile.spiritTokens)
				end
			end
		end
	end)
end

return ProgressionService
