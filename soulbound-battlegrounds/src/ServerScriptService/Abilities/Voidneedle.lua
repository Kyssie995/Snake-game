--!strict
-- Voidneedle — shadow rapier. Teleports, invisibility, assassination.
-- TEMPLATE STATUS: all four moves functional at a basic level; Dark Thread's
-- dash-cancel escape and Eclipse afterimages need polish.
-- NOTE the server-side teleport validation in Backstab Rift — never let the
-- client pick teleport destinations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hitbox = require(ReplicatedStorage.Modules.HitboxModule)
local Stun = require(ReplicatedStorage.Modules.StunManager)

local Voidneedle = {}
Voidneedle.Moves = {}

-- Move 1 (Lv1): Shadow Pierce — lunge thrust, phase through target on hit.
Voidneedle.Moves[1] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "VoidneedlePierce", character = character })
	root.CFrame += root.CFrame.LookVector * (move.range * 0.5)

	task.delay(0.08, function()
		if not character.Parent then
			return
		end
		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame * CFrame.new(0, 0, -3),
			size = Vector3.new(4, 5, 7),
		})
		local victim = hits[1]
		if victim and Hitbox.HasLineOfSight(character, victim) then
			Combat.DealDamage(victim, {
				amount = move.damage,
				attacker = character,
				attackerPlayer = ctx.player,
				hitstun = 0.4,
			})
			-- Phase through: reappear just behind the victim, facing their back
			local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
			if vRoot then
				root.CFrame = vRoot.CFrame * CFrame.new(0, 0, 4)
					* CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, math.pi, 0)
				root.CFrame = CFrame.lookAt(root.Position, vRoot.Position)
			end
		end
	end)
end

-- Move 2 (Lv5): Vanish Step — 2s invisibility, next M1 +8 damage.
-- Implementation: LocalTransparencyModifier is client-side, so we replicate
-- invisibility by tweening real transparency + a "VanishBonus" attribute the
-- damage pipeline could read; alpha keeps it simple with a timed attribute.
Voidneedle.Moves[2] = function(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character

	Combat.BroadcastFX({ fx = "VoidneedleVanish", character = character, active = true })
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Transparency = 0.92
		elseif part:IsA("Decal") then
			part.Transparency = 0.92
		end
	end
	character:SetAttribute("VanishBonus", true)

	task.delay(2, function()
		if not character.Parent then
			return
		end
		Combat.BroadcastFX({ fx = "VoidneedleVanish", character = character, active = false })
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.Transparency = 0
			elseif part:IsA("Decal") then
				part.Transparency = 0
			end
		end
		task.delay(3, function() -- bonus lingers briefly after reveal
			character:SetAttribute("VanishBonus", false)
		end)
	end)
end

-- Move 3 (Lv15): Dark Thread — tether; pull after 1s unless victim dashes.
Voidneedle.Moves[3] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	-- Find nearest target in a forward cone
	local hits = Hitbox.Sweep({
		attacker = character,
		cframe = root.CFrame * CFrame.new(0, 0, -move.range / 2),
		size = Vector3.new(10, 8, move.range),
	})
	local victim = hits[1]
	if not victim or not Hitbox.HasLineOfSight(character, victim) then
		return
	end

	Combat.BroadcastFX({ fx = "VoidneedleThread", character = character, victim = victim })
	Combat.DealDamage(victim, {
		amount = move.damage,
		attacker = character,
		attackerPlayer = ctx.player,
	})

	local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
	local threadStart = vRoot and vRoot.Position

	task.delay(1, function()
		if not character.Parent or not victim.Parent or not vRoot or not threadStart then
			return
		end
		-- Escape check: if the victim moved far from where they were threaded
		-- (i.e. they dashed), the thread snaps.
		if (vRoot.Position - threadStart).Magnitude > 15 then
			Combat.BroadcastFX({ fx = "VoidneedleThreadSnap", victim = victim })
			return
		end
		-- Pull to caster
		local pullTo = root.Position + root.CFrame.LookVector * 4
		vRoot.AssemblyLinearVelocity = (pullTo - vRoot.Position).Unit * 80
		Stun.ApplyStun(victim, "Hitstun", 0.6)
		Combat.BroadcastFX({ fx = "VoidneedleThreadPull", victim = victim })
	end)
end

-- Move 4 (Lv25): Backstab Rift — teleport behind target, heavy stab.
-- Clash eligible. Server validates range and line of sight — the client only
-- pressed a key.
Voidneedle.Moves[4] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	-- Server picks the target: nearest valid enemy in range with LoS
	local hits = Hitbox.Sweep({
		attacker = character,
		cframe = root.CFrame,
		size = Vector3.new(move.range * 2, 12, move.range * 2),
	})
	local target: Model? = nil
	local bestDist = math.huge
	for _, candidate in hits do
		local cRoot = candidate:FindFirstChild("HumanoidRootPart") :: BasePart?
		if cRoot and Hitbox.HasLineOfSight(character, candidate) then
			local dist = (cRoot.Position - root.Position).Magnitude
			if dist < bestDist and dist <= move.range * 1.2 then
				bestDist = dist
				target = candidate
			end
		end
	end
	if not target then
		return
	end
	local tRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart

	Combat.BroadcastFX({ fx = "VoidneedleRiftOut", character = character })
	-- Teleport behind the target (server-computed destination)
	root.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3.5)
	root.CFrame = CFrame.lookAt(root.Position, tRoot.Position)
	Combat.BroadcastFX({ fx = "VoidneedleRiftIn", character = character })

	task.delay(0.15, function()
		if not character.Parent or not target.Parent then
			return
		end
		local mult = Combat.GetUltimateMod(character, "backstabMult") or 1.25
		Combat.DealDamage(target, {
			amount = move.damage * mult,
			attacker = character,
			attackerPlayer = ctx.player,
			isHeavy = true,
			clashEligible = true,
			knockback = 40,
		})
	end)
end

-- Final Release: Eclipse Release — afterimages, double Vanish, +50% backstab.
-- TODO polish: victim-side screen dimming (client shader) + Vanish charges.
function Voidneedle.Ultimate(ctx)
	ctx.services.Combat.SetUltimateMods(ctx.character, {
		backstabMult = 1.5,
		moveCooldownMult2 = 0.5, -- approximates 2-charge Vanish for alpha
		m1SpeedMult = 1.1,
	}, ctx.config.ultimate.duration)
end

return Voidneedle
