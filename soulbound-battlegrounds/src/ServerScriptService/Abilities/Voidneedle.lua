--!strict
-- Voidneedle — COMPLETE weapon implementation.
-- Shadow rapier: teleports, invisibility, assassination (+25% backstab,
-- +50% during Eclipse Release).
-- NOTE the server-side teleport validation in Backstab Rift — the client
-- only pressed a key; the server picks the target and destination.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Hitbox = require(ReplicatedStorage.Modules.HitboxModule)
local Stun = require(ReplicatedStorage.Modules.StunManager)

local VANISH_DURATION = 2
local VANISH_BONUS_LINGER = 3 -- bonus stays armed briefly after reveal

local Voidneedle = {}
Voidneedle.Moves = {}

--------------------------------------------------------------------------
-- Move 1 (Lv1): Shadow Pierce — wall-safe lunge thrust; phase through the
-- target on hit and reappear at their back.
--------------------------------------------------------------------------
Voidneedle.Moves[1] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "VoidneedlePierce", character = character })

	-- Lunge, stopping at walls instead of clipping through
	local direction = root.CFrame.LookVector
	local lungeDist = move.range * 0.5
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	local blocked = Workspace:Raycast(root.Position, direction * (lungeDist + 2), rayParams)
	if blocked and blocked.Instance.CanCollide and blocked.Instance.Anchored then
		lungeDist = math.max(0, (blocked.Position - root.Position).Magnitude - 3)
	end
	root.CFrame += direction * lungeDist

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
			-- Phase through: reappear behind the victim, facing their back
			local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
			if vRoot then
				local behindPos = (vRoot.CFrame * CFrame.new(0, 0, 4)).Position
				root.CFrame = CFrame.lookAt(behindPos, vRoot.Position)
				Combat.BroadcastFX({ fx = "VoidneedlePhase", character = character })
			end
		end
	end)
end

--------------------------------------------------------------------------
-- Move 2 (Lv5): Vanish Step — 2s invisibility; next M1 within the window
-- (or shortly after reveal) deals +8 bonus damage.
-- The VanishBonus attribute is consumed by CombatService's M1 pipeline.
-- Original transparencies are stored so accessories/decals restore cleanly.
--------------------------------------------------------------------------
Voidneedle.Moves[2] = function(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character

	Combat.BroadcastFX({ fx = "VoidneedleVanish", character = character, active = true })

	local originals: { [Instance]: number } = {}
	for _, desc in character:GetDescendants() do
		if (desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart") or desc:IsA("Decal") then
			originals[desc] = (desc :: any).Transparency
			;(desc :: any).Transparency = 0.92
		end
	end
	character:SetAttribute("VanishBonus", true)

	task.delay(VANISH_DURATION, function()
		if not character.Parent then
			return
		end
		Combat.BroadcastFX({ fx = "VoidneedleVanish", character = character, active = false })
		for desc, transparency in originals do
			if desc.Parent then
				(desc :: any).Transparency = transparency
			end
		end
		task.delay(VANISH_BONUS_LINGER, function()
			character:SetAttribute("VanishBonus", false)
		end)
	end)
end

--------------------------------------------------------------------------
-- Move 3 (Lv15): Dark Thread — tether the nearest forward target; after 1s
-- they are yanked to you unless they broke the thread by dashing away.
--------------------------------------------------------------------------
Voidneedle.Moves[3] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	local hits = Hitbox.Sweep({
		attacker = character,
		cframe = root.CFrame * CFrame.new(0, 0, -move.range / 2),
		size = Vector3.new(10, 8, move.range),
	})
	local victim = hits[1]
	if not victim or not Hitbox.HasLineOfSight(character, victim) then
		return
	end

	Combat.BroadcastFX({ fx = "VoidneedleThread", character = character, victim = victim, duration = 1 })
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
		-- Escape check: a dash (>15 studs of displacement) snaps the thread
		if (vRoot.Position - threadStart).Magnitude > 15 then
			Combat.BroadcastFX({ fx = "VoidneedleThreadSnap", victim = victim })
			return
		end
		local pullTo = root.Position + root.CFrame.LookVector * 4
		local pullDir = pullTo - vRoot.Position
		if pullDir.Magnitude > 0.001 then
			vRoot.AssemblyLinearVelocity = pullDir.Unit * 80
		end
		Stun.ApplyStun(victim, "Hitstun", 0.6)
		Combat.BroadcastFX({ fx = "VoidneedleThreadPull", victim = victim })
	end)
end

--------------------------------------------------------------------------
-- Move 4 (Lv25): Backstab Rift — teleport behind the nearest valid target
-- and deliver a heavy stab. Guard-breaks, Soul Clash eligible.
--------------------------------------------------------------------------
Voidneedle.Moves[4] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	-- Server picks the target: nearest enemy in range with line of sight
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
	local behindPos = (tRoot.CFrame * CFrame.new(0, 0, 3.5)).Position
	root.CFrame = CFrame.lookAt(behindPos, tRoot.Position)
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

--------------------------------------------------------------------------
-- Final Release: Eclipse Release (Lv35)
-- Ghost afterimages trail the user, Vanish Step effectively gains a second
-- charge (cooldown halved), backstab bonus rises to +50%, M1s slightly
-- faster. Afterimages are pure client VFX driven by periodic broadcasts.
--------------------------------------------------------------------------
function Voidneedle.Ultimate(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character
	local duration = ctx.config.ultimate.duration

	Combat.SetUltimateMods(character, {
		backstabMult = 1.5,
		moveCooldownMult2 = 0.5, -- approximates 2-charge Vanish for alpha
		m1SpeedMult = 1.1,
	}, duration)

	-- Afterimage trail: broadcast a ghost snapshot while moving
	local endsAt = os.clock() + duration
	task.spawn(function()
		local lastPosition = ctx.root.Position
		while os.clock() < endsAt and character.Parent do
			task.wait(0.35)
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid or humanoid.Health <= 0 then
				return
			end
			if (root.Position - lastPosition).Magnitude > 3 then
				Combat.BroadcastFX({ fx = "VoidneedleAfterimage", cframe = root.CFrame })
			end
			lastPosition = root.Position
		end
	end)
end

return Voidneedle
