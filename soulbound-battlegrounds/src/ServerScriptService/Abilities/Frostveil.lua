--!strict
-- Frostveil — ice mirror katana. Zoning/control via Chill stacks (3 = freeze).
-- TEMPLATE STATUS: Moves 1 & 4 and the ultimate slow-field are functional;
-- Frozen Step trail and Mirror Trap are roughed in and need VFX + tuning.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Hitbox = require(ReplicatedStorage.Modules.HitboxModule)
local StatusEffects = require(ReplicatedStorage.Modules.StatusEffects)
local Stun = require(ReplicatedStorage.Modules.StunManager)

local CHILL_DURATION = 5

local Frostveil = {}
Frostveil.Moves = {}

-- Move 1 (Lv1): Ice Cut — crescent projectile wave, 1 Chill stack.
Frostveil.Moves[1] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "FrostveilIceCut", character = character })

	-- Server-stepped projectile: march a hitbox forward
	local direction = root.CFrame.LookVector
	local origin = root.CFrame
	task.spawn(function()
		local steps = 10
		for i = 1, steps do
			task.wait(0.04)
			if not character.Parent then
				return
			end
			local cframe = origin * CFrame.new(0, 0, -(move.range / steps) * i)
			local hits = Hitbox.Sweep({
				attacker = character,
				cframe = cframe,
				size = Vector3.new(7, 5, 4),
			})
			if #hits > 0 then
				local victim = hits[1]
				if Hitbox.HasLineOfSight(character, victim) then
					local landed = Combat.DealDamage(victim, {
						amount = move.damage,
						attacker = character,
						attackerPlayer = ctx.player,
						hitstun = 0.4,
					})
					if landed then
						StatusEffects.ApplyChill(victim, 1, CHILL_DURATION)
					end
				end
				return -- wave breaks on first hit
			end
		end
	end)
end

-- Move 2 (Lv5): Frozen Step — dash leaving a freezing trail for 3s.
Frostveil.Moves[2] = function(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "FrostveilFrozenStep", character = character })
	local startPos = root.Position
	root.CFrame += root.CFrame.LookVector * ctx.moveConfig.range

	-- Trail: pulse a box along the dash line for 3s applying Chill
	local endPos = root.Position
	local mid = (startPos + endPos) / 2
	local length = (endPos - startPos).Magnitude
	local trailCFrame = CFrame.lookAt(mid, endPos)
	task.spawn(function()
		for _ = 1, 6 do
			task.wait(0.5)
			if not character.Parent then
				return
			end
			local hits = Hitbox.Sweep({
				attacker = character,
				cframe = trailCFrame,
				size = Vector3.new(5, 4, length),
			})
			for _, victim in hits do
				StatusEffects.ApplyChill(victim, 1, CHILL_DURATION)
			end
		end
	end)
end

-- Move 3 (Lv15): Mirror Trap — invisible mirror freezes the first toucher.
Frostveil.Moves[3] = function(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character
	local root = ctx.root

	local trap = Instance.new("Part")
	trap.Name = "MirrorTrap"
	trap.Anchored = true
	trap.CanCollide = false
	trap.Transparency = 0.9 -- nearly invisible shimmer
	trap.Material = Enum.Material.Glass
	trap.Size = Vector3.new(5, 6, 1)
	trap.CFrame = root.CFrame * CFrame.new(0, 0, -ctx.moveConfig.range)
	trap.Parent = Workspace
	Combat.BroadcastFX({ fx = "FrostveilMirrorPlace", position = trap.Position })

	local sprung = false
	trap.Touched:Connect(function(hit)
		if sprung then
			return
		end
		local victim = hit:FindFirstAncestorOfClass("Model")
		if not victim or victim == character then
			return
		end
		local humanoid = victim:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		sprung = true
		Combat.DealDamage(victim, {
			amount = ctx.moveConfig.damage,
			attacker = character,
			attackerPlayer = ctx.player,
		})
		Stun.ApplyStun(victim, "GuardBreak", 1.5) -- the freeze
		Combat.BroadcastFX({ fx = "Frozen", character = victim, duration = 1.5 })
		trap:Destroy()
	end)

	task.delay(20, function() -- traps expire
		if trap.Parent then
			trap:Destroy()
		end
	end)
end

-- Move 4 (Lv25): Crystal Burst — AoE ring, guard-breaks, 2 Chill stacks.
Frostveil.Moves[4] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "FrostveilCrystalCharge", character = character })
	task.delay(0.6, function()
		if not character.Parent or not Stun.IsActionable(character) then
			return
		end
		Combat.BroadcastFX({ fx = "FrostveilCrystalBurst", character = character })
		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame,
			size = Vector3.new(move.range * 2, 8, move.range * 2),
		})
		for _, victim in hits do
			if not Hitbox.HasLineOfSight(character, victim) then
				continue
			end
			local landed = Combat.DealDamage(victim, {
				amount = move.damage,
				attacker = character,
				attackerPlayer = ctx.player,
				isHeavy = true,
				clashEligible = true,
				knockback = 45,
			})
			if landed then
				StatusEffects.ApplyChill(victim, 2, CHILL_DURATION)
			end
		end
	end)
end

-- Final Release: Winter Domain Release — slow dome + double Chill.
-- TODO polish: mirror-clone flickers at dome edge (pure client VFX).
function Frostveil.Ultimate(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character
	local duration = ctx.config.ultimate.duration
	local DOME_RADIUS = 30

	local endsAt = os.clock() + duration
	task.spawn(function()
		while os.clock() < endsAt and character.Parent do
			task.wait(1)
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return
			end
			Combat.BroadcastFX({ fx = "FrostveilDomePulse", position = root.Position, radius = DOME_RADIUS })
			local hits = Hitbox.Sweep({
				attacker = character,
				cframe = root.CFrame,
				size = Vector3.new(DOME_RADIUS * 2, 20, DOME_RADIUS * 2),
			})
			for _, victim in hits do
				StatusEffects.ApplySlow(victim, 0.75, 1.2)
			end
		end
	end)
	-- Double Chill while active: cheap implementation — the dome pulse above
	-- already adds pressure; per-hit double stacks can hook ApplyChill later.
end

return Frostveil
