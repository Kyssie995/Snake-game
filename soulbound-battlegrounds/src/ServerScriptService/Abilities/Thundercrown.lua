--!strict
-- Thundercrown — lightning greatsword. Heavy damage, stuns, destruction.
-- TEMPLATE STATUS: all moves functional; Storm Leap arc + chain-lightning
-- visuals need polish.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hitbox = require(ReplicatedStorage.Modules.HitboxModule)
local Stun = require(ReplicatedStorage.Modules.StunManager)

local Thundercrown = {}
Thundercrown.Moves = {}

-- Move 1 (Lv1): Thunder Cleave — big vertical slash, small AoE shock.
Thundercrown.Moves[1] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "ThundercrownCleave", character = character })
	task.delay(0.3, function() -- heavier windup than other weapons' pokes
		if not character.Parent or not Stun.IsActionable(character) then
			return
		end
		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame * CFrame.new(0, 0, -move.range / 2),
			size = Vector3.new(7, 9, move.range),
		})
		for _, victim in hits do
			if Hitbox.HasLineOfSight(character, victim) then
				Combat.DealDamage(victim, {
					amount = move.damage,
					attacker = character,
					attackerPlayer = ctx.player,
					hitstun = 0.6, -- shock lingers
				})
			end
		end
	end)
end

-- Move 2 (Lv5): Storm Leap — leap forward + crashing AoE that pops enemies up.
Thundercrown.Moves[2] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	local distance = move.range
	local distMult = Combat.GetUltimateMod(character, "stormLeapDistMult")
	if distMult then
		distance *= distMult
	end

	Combat.BroadcastFX({ fx = "ThundercrownLeap", character = character })
	root.AssemblyLinearVelocity = root.CFrame.LookVector * (distance * 1.6) + Vector3.new(0, 45, 0)

	task.delay(0.65, function() -- landing moment (approximate arc time)
		if not character.Parent then
			return
		end
		Combat.BroadcastFX({ fx = "ThundercrownCrash", character = character })
		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame * CFrame.new(0, -2, 0),
			size = Vector3.new(16, 8, 16),
		})
		for _, victim in hits do
			if Hitbox.HasLineOfSight(character, victim) then
				Combat.DealDamage(victim, {
					amount = move.damage,
					attacker = character,
					attackerPlayer = ctx.player,
					airLaunch = true, -- pop them up for followups
				})
			end
		end
	end)
end

-- Move 3 (Lv15): Static Field — 4s ground field, micro-stun every second.
Thundercrown.Moves[3] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local fieldCFrame = ctx.root.CFrame

	Combat.BroadcastFX({ fx = "ThundercrownField", position = fieldCFrame.Position, radius = move.range, duration = 4 })

	task.spawn(function()
		for _ = 1, 4 do
			task.wait(1)
			if not character.Parent then
				return
			end
			local hits = Hitbox.Sweep({
				attacker = character,
				cframe = fieldCFrame,
				size = Vector3.new(move.range * 2, 10, move.range * 2),
			})
			for _, victim in hits do
				Combat.DealDamage(victim, {
					amount = move.damage,
					attacker = character,
					attackerPlayer = ctx.player,
					hitstun = 0.3, -- the micro-stun
				})
			end
		end
	end)
end

-- Move 4 (Lv25): Crown Breaker — slowest, hardest swing in the game.
-- Guard-breaks, clash eligible, ragdolls victims through weak walls.
Thundercrown.Moves[4] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "ThundercrownCrownCharge", character = character })
	task.delay(1.1, function() -- very reactable — dodge it or clash it
		if not character.Parent or not Stun.IsActionable(character) then
			return
		end
		Combat.BroadcastFX({ fx = "ThundercrownCrownBreaker", character = character })
		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame * CFrame.new(0, 0, -move.range / 2),
			size = Vector3.new(10, 8, move.range),
		})
		for _, victim in hits do
			if not Hitbox.HasLineOfSight(character, victim) then
				continue
			end
			Combat.DealDamage(victim, {
				amount = move.damage,
				attacker = character,
				attackerPlayer = ctx.player,
				isHeavy = true,
				clashEligible = true,
				knockback = 90, -- fast enough to smash weak walls
			})
		end
	end)
end

-- Final Release: Tempest King Release — every 3rd M1 calls lightning,
-- Storm Leap doubles in distance.
function Thundercrown.Ultimate(ctx)
	local Combat = ctx.services.Combat

	Combat.SetUltimateMods(ctx.character, {
		stormLeapDistMult = 2,
		onM1Hit = function(attackerCharacter: Model, victim: Model, comboIndex: number)
			if comboIndex % 3 ~= 0 or not victim.Parent then
				return
			end
			local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not vRoot then
				return
			end
			Combat.BroadcastFX({ fx = "ThundercrownStrike", position = vRoot.Position })
			Combat.DealDamage(victim, {
				amount = 6,
				attacker = attackerCharacter,
				attackerPlayer = ctx.player,
				bypassBlock = true,
				hitstun = 0.4,
			})
		end,
	}, ctx.config.ultimate.duration)
end

return Thundercrown
