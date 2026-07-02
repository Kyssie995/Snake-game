--!strict
-- DataService: session-locked player profiles on DataStore.
-- Minimal ProfileService-style implementation: lock on load, heartbeat the
-- lock, release on leave, flush on BindToClose. Swap for ProfileService
-- post-alpha if desired — the public API here won't change.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WeaponConfigs = require(game:GetService("ReplicatedStorage").Modules.WeaponConfigs)

local STORE_NAME = "SoulboundPlayerData_v1"
local LOCK_TTL = 90 -- seconds a stale lock is honored
local AUTOSAVE_INTERVAL = 60

export type WeaponData = {
	xp: number,
	level: number,
}

export type Profile = {
	weapons: { [string]: WeaponData },
	unlockedWeapons: { string },
	equippedWeapon: string,
	spiritTokens: number,
	totalKills: number,
	dummyXPToday: number,
	dummyXPDay: number, -- os.date day-of-year stamp
	settings: { damageNumbers: boolean },
	_lock: { serverId: string, at: number }?,
}

local DataService = {}

local store = DataStoreService:GetDataStore(STORE_NAME)
local profiles: { [Player]: Profile } = {}
local serverId = game.JobId ~= "" and game.JobId or "studio"

local function defaultProfile(): Profile
	local starter = WeaponConfigs.STARTER_WEAPON
	return {
		weapons = { [starter] = { xp = 0, level = 1 } },
		unlockedWeapons = { starter },
		equippedWeapon = starter,
		spiritTokens = 0,
		totalKills = 0,
		dummyXPToday = 0,
		dummyXPDay = 0,
		settings = { damageNumbers = true },
	}
end

local function keyFor(userId: number): string
	return "player_" .. userId
end

local function save(player: Player, releasing: boolean)
	local profile = profiles[player]
	if not profile then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player.UserId), function(old)
			-- Only write if we hold the lock (or it's ours/stale)
			if old and old._lock and old._lock.serverId ~= serverId
				and os.time() - old._lock.at < LOCK_TTL then
				return nil -- another live server owns it; abort write
			end
			if releasing then
				profile._lock = nil
			else
				profile._lock = { serverId = serverId, at = os.time() }
			end
			return profile
		end)
	end)
	if not ok then
		warn("[DataService] save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

local function load(player: Player)
	local loaded: Profile? = nil
	local locked = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player.UserId), function(old: Profile?)
			if old and old._lock and old._lock.serverId ~= serverId
				and os.time() - old._lock.at < LOCK_TTL then
				locked = true
				return nil -- session locked elsewhere; don't claim
			end
			loaded = old or defaultProfile()
			loaded._lock = { serverId = serverId, at = os.time() }
			return loaded
		end)
	end)
	if not ok then
		warn("[DataService] load failed for " .. player.Name .. ": " .. tostring(err))
		if RunService:IsStudio() then
			-- Studio without API access: fall back to an in-memory profile so
			-- testing isn't blocked. Nothing will save.
			warn("[DataService] Studio fallback: using in-memory profile (enable"
				.. " 'Studio Access to API Services' to test persistence)")
			if player.Parent then
				profiles[player] = defaultProfile()
			end
			return
		end
		player:Kick("Data failed to load. Please rejoin.")
		return
	end
	if locked then
		player:Kick("Your data is active on another server. Please wait a moment and rejoin.")
		return
	end
	if player.Parent then
		local profile = loaded or defaultProfile()
		-- Migrate: ensure every unlocked weapon has a weapons entry
		for _, weaponId in profile.unlockedWeapons do
			if not profile.weapons[weaponId] then
				profile.weapons[weaponId] = { xp = 0, level = 1 }
			end
		end
		profiles[player] = profile
	end
end

function DataService.GetProfile(player: Player): Profile?
	return profiles[player]
end

-- Yields until the profile is available (or player leaves).
function DataService.WaitForProfile(player: Player): Profile?
	while player.Parent and not profiles[player] do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.Init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player, true)
		profiles[player] = nil
	end)

	-- Autosave + lock heartbeat
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		local done = 0
		local total = 0
		for player in profiles do
			total += 1
			task.spawn(function()
				save(player, true)
				done += 1
			end)
		end
		local deadline = os.clock() + 25
		while done < total and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return DataService
