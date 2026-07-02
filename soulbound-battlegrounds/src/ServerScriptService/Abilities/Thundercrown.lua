--!strict
-- Thundercrown — COMPLETE weapon implementation.
-- Lightning greatsword: slow, massive damage, stuns, breaks the environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Hitbox = require(ReplicatedStorage.Modules.HitboxModule)
local Stun = require(ReplicatedStorage.Modules.StunManager)

local DestructionService = require(ServerScriptService.Services.DestructionService)

local Thundercrown = {}
Thundercrown.Moves = {}

--------------------------------------------------------------------------
-- Move 1 (Lv1): Thunder Cleave — big vertical bolt-slash, small AoE shock.
--------------------------------------------------------------------------
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
		Combat.BroadcastFX({ fx = "ThundercrownCleaveImpact", position = (root.CFrame * CFrame.new(0, 0, -move.range / 2)).Position })
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

--------------------------------------------------------------------------
-- Move 2 (Lv5): Storm Leap — leap forward, crash on actual landing, pop
-- enemies airborne. Landing is detected by polling for ground contact
-- (with a timeout) instead of a fixed delay, so short and long arcs both
-- crash at the right moment.
--------------------------------------------------------------------------
Thundercrown.Moves[2] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local distance = move.range
	local distMult = Combat.GetUltimateMod(character, "stormLeapDistMult")
	if distMult then
		distance *= distMult
	end

	Combat.BroadcastFX({ fx = "ThundercrownLeap", character = character })
	root.AssemblyLinearVelocity = root.CFrame.LookVector * (distance * 1.6) + Vector3.new(0, 45, 0)

	task.spawn(function()
		task.wait(0.25) -- let the leap actually leave the ground
		local deadline = os.clock() + 1.6
		while os.clock() < deadline do
			if not character.Parent or humanoid.Health <= 0 then
				return
			end
			if humanoid.FloorMaterial ~= Enum.Material.Air then
				break -- landed
			end
			task.wait(0.05)
		end
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

--------------------------------------------------------------------------
-- Move 3 (Lv15): Static Field — charge the ground for 4s; enemies inside
-- are shocked (micro-stun) every second.
--------------------------------------------------------------------------
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
				local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
				local landed = Combat.DealDamage(victim, {
					amount = move.damage,
					attacker = character,
					attackerPlayer = ctx.player,
					hitstun = 0.3, -- the micro-stun
				})
				if landed and vRoot then
					Combat.BroadcastFX({ fx = "ThundercrownStrike", position = vRoot.Position })
				end
			end
		end
	end)
end

--------------------------------------------------------------------------
-- Move 4 (Lv25): Crown Breaker — the slowest, hardest swing in the game.
-- Guard-breaks, Soul Clash eligible, ragdolls victims hard enough to smash
-- weak walls — and shatters destructibles in the swing arc itself.
--------------------------------------------------------------------------
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

		-- The swing itself smashes destructibles in front of the caster
		local impactCenter = (root.CFrame * CFrame.new(0, 0, -move.range / 2)).Position
		DestructionService.SmashArea(impactCenter, move.range * 0.8, root.CFrame.LookVector * 60)

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
				knockback = 90, -- fast enough to smash weak walls on impact
			})
		end
	end)
end

--------------------------------------------------------------------------
-- Final Release: Tempest King Release (Lv35)
-- A storm crown ignites: every 3rd M1 calls a lightning strike, Storm Leap
-- doubles in distance, and nearby destructibles periodically arc with
-- chain lightning (small smashes around the caster).
--------------------------------------------------------------------------
function Thundercrown.Ultimate(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character
	local duration = ctx.config.ultimate.duration

	Combat.SetUltimateMods(character, {
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
	}, duration)

	Combat.BroadcastFX({ fx = "ThundercrownCrownIgnite", character = character, duration = duration })

	-- Chain lightning: every 3s, arc to (and shatter) destructibles near
	-- the caster — walking through the market mid-ultimate is a spectacle.
	local endsAt = os.clock() + duration
	task.spawn(function()
		while os.clock() < endsAt and character.Parent do
			task.wait(3)
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid or humanoid.Health <= 0 then
				return
			end
			Combat.BroadcastFX({ fx = "ThundercrownChainArc", position = root.Position, radius = 15 })
			DestructionService.SmashArea(root.Position, 15, Vector3.new(0, 25, 0))
		end
	end)
end

return Thundercrown
