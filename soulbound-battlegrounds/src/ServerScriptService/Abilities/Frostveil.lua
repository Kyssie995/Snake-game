--!strict
-- Frostveil — COMPLETE weapon implementation.
-- Ice mirror katana: zoning and control via Chill stacks (3 stacks = freeze).
-- Winter Domain Release doubles Chill application and slows enemies in a dome.
--
-- Chill flow: moves call applyChill() below, which reads the ultimate's
-- chillStacksMult mod so Winter Domain automatically doubles stacks without
-- any move knowing about the ultimate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Hitbox = require(ReplicatedStorage.Modules.HitboxModule)
local StatusEffects = require(ReplicatedStorage.Modules.StatusEffects)
local Stun = require(ReplicatedStorage.Modules.StunManager)

local CHILL_DURATION = 5
local TRAP_LIFETIME = 20
local TRAP_FREEZE_TIME = 1.5

local Frostveil = {}
Frostveil.Moves = {}

-- One active Mirror Trap per caster (placing a new one melts the old)
local activeTraps: { [Model]: BasePart } = {}

local function applyChill(Combat, caster: Model, victim: Model, baseStacks: number)
	local mult = Combat.GetUltimateMod(caster, "chillStacksMult") or 1
	StatusEffects.ApplyChill(victim, baseStacks * mult, CHILL_DURATION)
end

--------------------------------------------------------------------------
-- Move 1 (Lv1): Ice Cut — crescent ice wave projectile, 1 Chill stack.
-- Server-stepped so a laggy client can't fake projectile positions.
--------------------------------------------------------------------------
Frostveil.Moves[1] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	local origin = root.CFrame
	Combat.BroadcastFX({ fx = "FrostveilIceCut", character = character, origin = origin.Position, range = move.range })

	task.spawn(function()
		local steps = 10
		for i = 1, steps do
			task.wait(0.04)
			if not character.Parent then
				return
			end
			local cframe = origin * CFrame.new(0, 0, -(move.range / steps) * i)
			-- Wave dies against walls: check the path is clear. "Wall" means
			-- a collidable part that is NOT inside a character (humanoid
			-- check — the map itself may be grouped in a Model).
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = { character }
			local blocked = Workspace:Raycast(origin.Position, cframe.Position - origin.Position, rayParams)
			if blocked and blocked.Instance.CanCollide then
				local ancestorModel = blocked.Instance:FindFirstAncestorOfClass("Model")
				local isCharacter = ancestorModel and ancestorModel:FindFirstChildOfClass("Humanoid") ~= nil
				if not isCharacter then
					Combat.BroadcastFX({ fx = "FrostveilIceShatter", position = blocked.Position })
					return
				end
			end
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
						applyChill(Combat, character, victim, 1)
					end
					local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
					if vRoot then
						Combat.BroadcastFX({ fx = "FrostveilIceShatter", position = vRoot.Position })
					end
				end
				return -- wave breaks on first hit
			end
		end
	end)
end

--------------------------------------------------------------------------
-- Move 2 (Lv5): Frozen Step — stepped dash leaving a visible freezing trail.
-- The trail is a row of ice shards on the ground; standing in it stacks Chill.
--------------------------------------------------------------------------
Frostveil.Moves[2] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "FrostveilFrozenStep", character = character })

	-- Server-driven dash, wall-safe: raycast each step before moving
	local direction = root.CFrame.LookVector
	local steps = 8
	local stepDist = move.range / steps
	local trailPositions: { Vector3 } = {}
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	for i = 1, steps do
		if not character.Parent or not Stun.IsActionable(character) then
			break
		end
		local blocked = Workspace:Raycast(root.Position, direction * (stepDist + 2), rayParams)
		if blocked and blocked.Instance.CanCollide and blocked.Instance.Anchored then
			break -- dash stops at walls instead of clipping through
		end
		root.CFrame += direction * stepDist
		table.insert(trailPositions, root.Position)

		-- Dash-through damage: light hit + Chill on anyone passed through
		local hits = Hitbox.Sweep({
			attacker = character,
			cframe = root.CFrame,
			size = Vector3.new(5, 6, 5),
		})
		for _, victim in hits do
			local landed = Combat.DealDamage(victim, {
				amount = move.damage,
				attacker = character,
				attackerPlayer = ctx.player,
				hitstun = 0.3,
			})
			if landed then
				applyChill(Combat, character, victim, 1)
			end
		end
		task.wait(0.03)
	end

	-- Freezing trail: visible ice shards that pulse Chill for 3s
	local trailParts: { BasePart } = {}
	for _, position in trailPositions do
		local shard = Instance.new("Part")
		shard.Name = "FrostTrail"
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.Material = Enum.Material.Ice
		shard.Color = Color3.fromRGB(170, 230, 255)
		shard.Transparency = 0.25
		shard.Size = Vector3.new(3.5, 0.4, 3.5)
		shard.CFrame = CFrame.new(position - Vector3.new(0, 2.6, 0))
			* CFrame.Angles(0, math.random() * math.pi, 0)
		shard.Parent = Workspace
		table.insert(trailParts, shard)
		Debris:AddItem(shard, 3.2)
	end

	task.spawn(function()
		for _ = 1, 6 do -- 6 pulses over 3s
			task.wait(0.5)
			if not character.Parent then
				return
			end
			for _, shard in trailParts do
				if not shard.Parent then
					continue
				end
				local hits = Hitbox.Sweep({
					attacker = character,
					cframe = shard.CFrame + Vector3.new(0, 2, 0),
					size = Vector3.new(4.5, 4.5, 4.5),
				})
				for _, victim in hits do
					applyChill(Combat, character, victim, 1)
				end
			end
		end
	end)
end

--------------------------------------------------------------------------
-- Move 3 (Lv15): Mirror Trap — near-invisible mirror; first enemy to touch
-- it is frozen 1.5s. One active trap per caster; expires after 20s.
--------------------------------------------------------------------------
Frostveil.Moves[3] = function(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character
	local root = ctx.root

	-- Melt any previous trap by this caster
	local previous = activeTraps[character]
	if previous and previous.Parent then
		previous:Destroy()
	end

	local trap = Instance.new("Part")
	trap.Name = "MirrorTrap"
	trap.Anchored = true
	trap.CanCollide = false
	trap.CanQuery = false
	trap.Transparency = 0.9 -- faint shimmer; attentive players can spot it
	trap.Material = Enum.Material.Glass
	trap.Color = Color3.fromRGB(200, 240, 255)
	trap.Size = Vector3.new(5, 6, 1)
	trap.CFrame = root.CFrame * CFrame.new(0, 0, -ctx.moveConfig.range)
	trap.Parent = Workspace
	activeTraps[character] = trap
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
		if activeTraps[character] == trap then
			activeTraps[character] = nil
		end
		Combat.DealDamage(victim, {
			amount = ctx.moveConfig.damage,
			attacker = character,
			attackerPlayer = ctx.player,
		})
		Stun.ApplyStun(victim, "GuardBreak", TRAP_FREEZE_TIME) -- the freeze
		Combat.BroadcastFX({ fx = "FrostveilMirrorSpring", position = trap.Position })
		Combat.BroadcastFX({ fx = "Frozen", character = victim, duration = TRAP_FREEZE_TIME })
		trap:Destroy()
	end)

	task.delay(TRAP_LIFETIME, function()
		if trap.Parent then
			if activeTraps[character] == trap then
				activeTraps[character] = nil
			end
			Combat.BroadcastFX({ fx = "FrostveilIceShatter", position = trap.Position })
			trap:Destroy()
		end
	end)
end

--------------------------------------------------------------------------
-- Move 4 (Lv25): Crystal Burst — AoE ice-spike ring around the caster.
-- Guard-breaks, 2 Chill stacks, Soul Clash eligible.
--------------------------------------------------------------------------
Frostveil.Moves[4] = function(ctx)
	local Combat = ctx.services.Combat
	local move = ctx.moveConfig
	local character = ctx.character
	local root = ctx.root

	Combat.BroadcastFX({ fx = "FrostveilCrystalCharge", character = character })
	task.delay(0.6, function() -- reactable windup
		if not character.Parent or not Stun.IsActionable(character) then
			return
		end
		Combat.BroadcastFX({ fx = "FrostveilCrystalBurst", character = character, radius = move.range })
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
				isHeavy = true, -- guard breaks
				clashEligible = true, -- Soul Clash hook
				knockback = 45,
			})
			if landed then
				applyChill(Combat, character, victim, 2)
			end
		end
	end)
end

--------------------------------------------------------------------------
-- Final Release: Winter Domain Release (Lv35)
-- 30-stud dome: enemies inside slowed 25%; caster's Chill applies double
-- stacks (chillStacksMult mod read by applyChill); mirror clones flicker at
-- the dome edge (pure client VFX).
--------------------------------------------------------------------------
function Frostveil.Ultimate(ctx)
	local Combat = ctx.services.Combat
	local character = ctx.character
	local duration = ctx.config.ultimate.duration
	local DOME_RADIUS = 30

	Combat.SetUltimateMods(character, {
		chillStacksMult = 2,
	}, duration)

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Combat.BroadcastFX({ fx = "FrostveilDomeStart", position = root.Position, radius = DOME_RADIUS, duration = duration })
	end

	local endsAt = os.clock() + duration
	task.spawn(function()
		local flickerCounter = 0
		while os.clock() < endsAt and character.Parent do
			task.wait(1)
			local currentRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not currentRoot or not humanoid or humanoid.Health <= 0 then
				return -- domain collapses on death
			end
			Combat.BroadcastFX({ fx = "FrostveilDomePulse", position = currentRoot.Position, radius = DOME_RADIUS })

			-- Slow every enemy inside the dome
			local hits = Hitbox.Sweep({
				attacker = character,
				cframe = currentRoot.CFrame,
				size = Vector3.new(DOME_RADIUS * 2, 20, DOME_RADIUS * 2),
			})
			for _, victim in hits do
				StatusEffects.ApplySlow(victim, 0.75, 1.2)
			end

			-- Mirror clone flicker every 3rd pulse (client-side illusion)
			flickerCounter += 1
			if flickerCounter % 3 == 0 then
				Combat.BroadcastFX({ fx = "FrostveilCloneFlicker", character = character, radius = DOME_RADIUS })
			end
		end
	end)
end

return Frostveil
