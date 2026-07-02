--!strict
-- _WeaponTemplate: copy this file to create a new Soul Weapon.
-- (Files prefixed with _ are skipped by AbilityService's loader.)
--
-- Checklist for a new weapon:
--   1. Create ReplicatedStorage/Modules/WeaponConfigs/<Name>.lua (see Ashfang config)
--   2. Copy this file to ServerScriptService/Abilities/<Name>.lua
--   3. Implement Moves[1..4] and Ultimate
--   4. Add client VFX cases for your fx names in CombatClient
--   That's it — AbilityService, progression, the shop, and the UI pick the
--   weapon up automatically from the config.
--
-- ctx fields: player, character, root, config, moveConfig,
--             services = { Combat, Progression }
--
-- Rules every move must follow:
--   * NEVER trust anything from the client — ctx is built server-side.
--   * Damage ONLY through ctx.services.Combat.DealDamage (block/clash/
--     energy/XP/death all live there).
--   * Check `character.Parent` and StunManager.IsActionable after every
--     task.wait/task.delay — the caster may have died or been interrupted.
--   * Cooldowns are already started by AbilityService before your move runs.
--   * Broadcast visuals with Combat.BroadcastFX({fx = "YourEffectName", ...})
--     and implement the visual client-side in CombatClient.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hitbox = require(ReplicatedStorage.Modules.HitboxModule)
local StatusEffects = require(ReplicatedStorage.Modules.StatusEffects)
local Stun = require(ReplicatedStorage.Modules.StunManager)

local Weapon = {}
Weapon.Moves = {}

-- Move 1 (Lv1): usually your fast, low-commitment poke.
Weapon.Moves[1] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	Combat.BroadcastFX({ fx = "TemplateMove1", character = ctx.character })
	task.delay(0.15, function()
		if not ctx.character.Parent then
			return
		end
		local hits = Hitbox.Sweep({
			attacker = ctx.character,
			cframe = ctx.root.CFrame * CFrame.new(0, 0, -move.range / 2),
			size = Vector3.new(6, 6, move.range),
		})
		for _, victim in hits do
			if Hitbox.HasLineOfSight(ctx.character, victim) then
				Combat.DealDamage(victim, {
					amount = move.damage,
					attacker = ctx.character,
					attackerPlayer = ctx.player,
					hitstun = 0.4,
				})
			end
		end
	end)
end

-- Move 2 (Lv5): usually mobility or a gap-closer.
Weapon.Moves[2] = function(ctx)
	-- TODO: implement
end

-- Move 3 (Lv15): usually utility (trap / counter / zone).
Weapon.Moves[3] = function(ctx)
	-- TODO: implement
end

-- Move 4 (Lv25): the heavy. Set isHeavy = true and clashEligible = true on
-- its DealDamage so it guard-breaks and can trigger Soul Clash.
Weapon.Moves[4] = function(ctx)
	-- TODO: implement
end

-- Final Release (Lv35): apply buffs via Combat.SetUltimateMods and/or run a
-- timed loop. Supported mods read by the core:
--   m1SpeedMult (number), moveCooldownMult<slot> (number),
--   backstabMult (number, Voidneedle), onM1Hit (fn(character, victim, comboIndex))
function Weapon.Ultimate(ctx)
	-- TODO: implement
end

return Weapon
