--!strict
-- Ashfang — COMPLETE reference weapon implementation.
-- Fire wolf blade: aggressive melee pressure, Burn damage-over-time.
-- Every other weapon module follows this exact shape (see _WeaponTemplate).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hitbox = require(ReplicatedStorage.Modules.HitboxModule)
local StatusEffects = require(ReplicatedStorage.Modules.StatusEffects)
local Stun = require(ReplicatedStorage.Modules.StunManager)

local BURN_DPS = 2
local BURN_DURATION = 3

local Ashfang = {}
Ashfang.Moves = {}

--------------------------------------------------------------------------
-- Move 1 (Lv1): Ember Slash — fast 270° arc, applies Burn, combo extender
--------------------------------------------------------------------------
Ashfang.Moves[1] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig

	Combat.BroadcastFX({ fx = "AshfangEmberSlash", character = ctx.character })

	task.delay(0.15, function()
		if not ctx.character.Parent then
			return
		end
		-- Wide arc: one box centered forward, slightly oversized sideways
		local hits = Hitbox.Sweep({
			attacker = ctx.character,
			cframe = ctx.root.CFrame * CFrame.new(0, 0, -move.range / 2),
			size = Vector3.new(move.range * 1.6, 6, move.range),
		})
		for _, victim in hits do
			if not Hitbox.HasLineOfSight(ctx.character, victim) then
				continue
			end
			local landed = Combat.DealDamage(victim, {
				amount = move.damage,
				attacker = ctx.character,
				attackerPlayer = ctx.player,
				hitstun = 0.45,
			})
			if landed then
				StatusEffects.ApplyBurn(victim, BURN_DPS, BURN_DURATION, ctx.player)
			end
		end
	end)
end

--------------------------------------------------------------------------
-- Move 2 (Lv5): Wolf Rush — flame-wolf dash; 3 bites + knockback slash
--------------------------------------------------------------------------
Ashfang.Moves[2] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local root = ctx.root
	local character = ctx.character

	Combat.BroadcastFX({ fx = "AshfangWolfRush", character = character })

	-- Server-driven dash: sweep a hitbox along the path each step
	local direction = root.CFrame.LookVector
	local totalDistance = move.range
	local steps = 8
	local stepDist = totalDistance / steps
	local target: Model? = nil

	for i = 1, steps do
		if not character.Parent or not Stun.IsActionable(character) then
			return
		end
		root.CFrame += direction * stepDist
		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame,
			size = Vector3.new(6, 6, 6),
		})
		if #hits > 0 then
			target = hits[1]
			break
		end
		task.wait(0.03)
	end

	if not target or not Hitbox.HasLineOfSight(character, target) then
		return
	end

	-- 3 rapid bites
	for bite = 1, 3 do
		if not target.Parent or not character.Parent then
			return
		end
		Combat.DealDamage(target, {
			amount = 3,
			attacker = character,
			attackerPlayer = ctx.player,
			hitstun = 0.35,
		})
		Combat.BroadcastFX({ fx = "AshfangBite", character = character, victim = target, index = bite })
		task.wait(0.18)
	end

	-- Finishing knockback slash
	if target.Parent and character.Parent then
		Combat.DealDamage(target, {
			amount = 6,
			attacker = character,
			attackerPlayer = ctx.player,
			knockback = 45,
		})
	end
end

--------------------------------------------------------------------------
-- Move 3 (Lv15): Flame Counter — 0.6s parry; negate hit, erupt, ragdoll
--------------------------------------------------------------------------
Ashfang.Moves[3] = function(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character

	Combat.BroadcastFX({ fx = "AshfangCounterStance", character = character })

	Combat.SetCounterWindow(character, 0.6, function(attacker: Model)
		if not character.Parent then
			return
		end
		Combat.BroadcastFX({ fx = "AshfangCounterTrigger", character = character })
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local aRoot = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not aRoot then
			return
		end
		local dir = (aRoot.Position - root.Position)
		local landed = Combat.DealDamage(attacker, {
			amount = ctx.moveConfig.damage,
			attacker = character,
			attackerPlayer = ctx.player,
			bypassBlock = true, -- they attacked into a counter; no hiding
			knockback = 50,
			knockbackDirection = dir.Magnitude > 0.001 and dir.Unit or Vector3.zAxis,
		})
		if landed then
			StatusEffects.ApplyBurn(attacker, BURN_DPS, BURN_DURATION, ctx.player)
		end
	end)
end

--------------------------------------------------------------------------
-- Move 4 (Lv25): Burning Fang — charged slam, ground-fire cone, guard break
-- Clash eligible.
--------------------------------------------------------------------------
Ashfang.Moves[4] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "AshfangFangCharge", character = character })

	task.delay(0.7, function() -- reactable windup
		if not character.Parent or not Stun.IsActionable(character) then
			return
		end
		Combat.BroadcastFX({ fx = "AshfangFangSlam", character = character })

		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame * CFrame.new(0, 0, -move.range / 2),
			size = Vector3.new(8, 7, move.range),
		})
		for _, victim in hits do
			if not Hitbox.HasLineOfSight(character, victim) then
				continue
			end
			local landed = Combat.DealDamage(victim, {
				amount = move.damage,
				attacker = character,
				attackerPlayer = ctx.player,
				isHeavy = true, -- guard breaks
				clashEligible = true, -- Soul Clash hook
				knockback = 60,
			})
			if landed then
				StatusEffects.ApplyBurn(victim, BURN_DPS, BURN_DURATION * 1.5, ctx.player)
			end
		end

		-- Lingering ground-fire cone: 3 pulses over 2.4s
		local coneCFrame = root.CFrame * CFrame.new(0, -2, -move.range / 2)
		task.spawn(function()
			for _ = 1, 3 do
				task.wait(0.8)
				if not character.Parent then
					return
				end
				local burnedHits = Hitbox.Sweep({
					attacker = character,
					cframe = coneCFrame,
					size = Vector3.new(10, 4, move.range),
				})
				for _, victim in burnedHits do
					StatusEffects.ApplyBurn(victim, BURN_DPS, BURN_DURATION, ctx.player)
				end
			end
		end)
	end)
end

--------------------------------------------------------------------------
-- Final Release: Inferno Pack Release (Lv35)
-- Twin fangs, +20% M1 speed, Wolf Rush CD halved, 2 spectral wolves that
-- auto-lunge at nearby enemies applying Burn.
--------------------------------------------------------------------------
function Ashfang.Ultimate(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character
	local duration = ctx.config.ultimate.duration

	Combat.SetUltimateMods(character, {
		m1SpeedMult = 1.2,
		moveCooldownMult2 = 0.5, -- Wolf Rush cooldown halved
	}, duration)

	-- Spectral wolves: two invisible "pets" that periodically lunge at the
	-- nearest enemy within 25 studs. Represented purely by VFX broadcasts +
	-- server damage ticks — no physical NPCs needed in alpha.
	local endsAt = os.clock() + duration
	task.spawn(function()
		while os.clock() < endsAt and character.Parent do
			task.wait(2.5)
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid or humanoid.Health <= 0 then
				return
			end
			local hits = Hitbox.Sweep({
				attacker = character,
				cframe = root.CFrame,
				size = Vector3.new(50, 20, 50),
			})
			for i = 1, math.min(2, #hits) do
				local victim = hits[i]
				if Hitbox.HasLineOfSight(character, victim) then
					Combat.BroadcastFX({ fx = "AshfangWolfLunge", character = character, victim = victim, wolf = i })
					local landed = Combat.DealDamage(victim, {
						amount = 4,
						attacker = character,
						attackerPlayer = ctx.player,
						hitstun = 0.25,
					})
					if landed then
						StatusEffects.ApplyBurn(victim, BURN_DPS, BURN_DURATION, ctx.player)
					end
				end
			end
		end
	end)
end

return Ashfang
