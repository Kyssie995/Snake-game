--!strict
-- AbilityService: validates ability intents and routes them to the equipped
-- weapon's ability module. Also owns the Final Release (ultimate) flow.
--
-- Weapon ability module interface (see Abilities/Ashfang for reference):
--   Module.Moves[slot] = function(ctx) end   -- executes move `slot` (1..4)
--   Module.Ultimate = function(ctx) end      -- applies Final Release
-- ctx = { player, character, root, config, moveConfig, services }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Modules.Net)
local Constants = require(ReplicatedStorage.Modules.CombatConstants)
local Cooldowns = require(ReplicatedStorage.Modules.CooldownManager)
local Stun = require(ReplicatedStorage.Modules.StunManager)
local WeaponConfigs = require(ReplicatedStorage.Modules.WeaponConfigs)

local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)

local AbilityService = {}

local abilityModules: { [string]: any } = {}

export type MoveContext = {
	player: Player,
	character: Model,
	root: BasePart,
	config: WeaponConfigs.WeaponConfig,
	moveConfig: WeaponConfigs.MoveConfig?,
	services: {
		Combat: typeof(CombatService),
		Progression: typeof(ProgressionService),
	},
}

local function buildContext(player: Player, slot: number?): MoveContext?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local weaponId = ProgressionService.GetEquippedWeapon(player)
	local config = weaponId and WeaponConfigs.Get(weaponId)
	if not config then
		return nil
	end
	return {
		player = player,
		character = character,
		root = root,
		config = config,
		moveConfig = slot and config.moves[slot] or nil,
		services = { Combat = CombatService, Progression = ProgressionService },
	}
end

local function handleAbilityRequest(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local slot = payload.slot
	if typeof(slot) ~= "number" then
		return
	end

	-- Slot 0 = ultimate
	if slot == 0 then
		AbilityService.TryUltimate(player)
		return
	end
	if slot ~= math.floor(slot) or slot < 1 or slot > 4 then
		return
	end

	local ctx = buildContext(player, slot)
	if not ctx or not ctx.moveConfig then
		return
	end

	-- Validation gauntlet (the anti-exploit spine):
	if not Stun.IsActionable(ctx.character) then
		return
	end
	if not ProgressionService.IsMoveUnlocked(player, ctx.config.id, slot) then
		return
	end
	local cooldownKey = "Move" .. slot
	if not Cooldowns.IsReady(ctx.character, cooldownKey) then
		return
	end

	local module = abilityModules[ctx.config.id]
	local move = module and module.Moves and module.Moves[slot]
	if not move then
		return
	end

	local cooldown = ctx.moveConfig.cooldown
	local cdMult = CombatService.GetUltimateMod(ctx.character, "moveCooldownMult" .. slot)
	if cdMult then
		cooldown *= cdMult
	end
	Cooldowns.Start(ctx.character, cooldownKey, cooldown)
	Net.GetEvent("HUDUpdate"):FireClient(player, { field = "Cooldown", value = { slot = slot, duration = cooldown } })

	local ok, err = pcall(move, ctx)
	if not ok then
		warn(("[AbilityService] %s move %d errored: %s"):format(ctx.config.id, slot, tostring(err)))
	end
end

function AbilityService.TryUltimate(player: Player)
	local ctx = buildContext(player, nil)
	if not ctx then
		return
	end
	local character = ctx.character
	local state = CombatService.GetState(character)
	if not state then
		return
	end

	if not Stun.IsActionable(character) then
		return
	end
	if not ProgressionService.IsUltimateUnlocked(player, ctx.config.id) then
		return
	end
	if state.energy < Constants.ULTIMATE.REQUIRED_ENERGY then
		return
	end
	if not Cooldowns.IsReady(character, "Ultimate") then
		return
	end

	local module = abilityModules[ctx.config.id]
	if not module or not module.Ultimate then
		return
	end

	Cooldowns.Start(character, "Ultimate", ctx.config.ultimate.cooldown)
	state.energy = 0
	Net.GetEvent("HUDUpdate"):FireClient(player, { field = "Energy", value = 0 })

	-- Cinematic activation: lock + invulnerable
	Stun.ApplyStun(character, "UltimateLock", Constants.ULTIMATE.ACTIVATION_TIME)
	state.spawnProtectedUntil = os.clock() + Constants.ULTIMATE.ACTIVATION_TIME -- reuse as invuln
	CombatService.BroadcastFX({
		fx = "UltimateActivate",
		character = character,
		weapon = ctx.config.id,
		name = ctx.config.ultimate.name,
		duration = ctx.config.ultimate.duration,
	})

	task.delay(Constants.ULTIMATE.ACTIVATION_TIME, function()
		if not character.Parent then
			return
		end
		local ok, err = pcall(module.Ultimate, ctx)
		if not ok then
			warn(("[AbilityService] %s ultimate errored: %s"):format(ctx.config.id, tostring(err)))
		end
		-- End-of-ultimate vulnerability window
		task.delay(ctx.config.ultimate.duration, function()
			if character.Parent then
				CombatService.BroadcastFX({ fx = "UltimateEnd", character = character, weapon = ctx.config.id })
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.WalkSpeed = 16 * Constants.ULTIMATE.END_SLOW_MULT
					task.delay(Constants.ULTIMATE.END_SLOW_TIME, function()
						if humanoid.Parent then
							humanoid.WalkSpeed = 16
						end
					end)
				end
			end
		end)
	end)
end

function AbilityService.Init()
	-- Load every ability module in ServerScriptService/Abilities
	for _, child in ServerScriptService.Abilities:GetChildren() do
		if child:IsA("ModuleScript") and not child.Name:match("^_") then
			local ok, moduleOrErr = pcall(require, child)
			if ok then
				abilityModules[child.Name] = moduleOrErr
			else
				warn("[AbilityService] failed to load " .. child.Name .. ": " .. tostring(moduleOrErr))
			end
		end
	end

	Net.RegisterHandler("AbilityRequest", Constants.RATES.AbilityRequest, handleAbilityRequest)
end

return AbilityService
