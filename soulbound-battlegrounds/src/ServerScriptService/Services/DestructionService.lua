--!strict
-- DestructionService: weak walls and props tagged "Destructible" break when
-- a ragdolled body or a heavy ability slams into them. Debris flies, fades,
-- and the original respawns.
--
-- Map setup: tag any Part/Model with CollectionService tag "Destructible".
-- Optional attributes on the tagged instance:
--   DestructibleType: "Wall" (respawns) | "Prop" (respawns) — default "Prop"
--   DebrisCount: number of chunks (default 6)

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Modules.CombatConstants)

local DestructionService = {}

local D = Constants.DESTRUCTION
local TAG = "Destructible"

local broken: { [Instance]: boolean } = {}

local function shatter(target: BasePart, impactVelocity: Vector3)
	if broken[target] then
		return
	end
	broken[target] = true

	local count = (target:GetAttribute("DebrisCount") :: number?) or 6
	local chunkSize = target.Size / math.ceil(count ^ (1 / 3))

	for _ = 1, count do
		local chunk = Instance.new("Part")
		chunk.Material = target.Material
		chunk.Color = target.Color
		chunk.Size = chunkSize * (0.6 + math.random() * 0.6)
		chunk.CFrame = target.CFrame * CFrame.new(
			(math.random() - 0.5) * target.Size.X,
			(math.random() - 0.5) * target.Size.Y,
			(math.random() - 0.5) * target.Size.Z
		)
		chunk.CanCollide = true
		chunk.CanQuery = false
		chunk.AssemblyLinearVelocity = impactVelocity * 0.5
			+ Vector3.new(math.random(-15, 15), math.random(5, 25), math.random(-15, 15))
		chunk.Parent = Workspace

		task.delay(D.DEBRIS_FADE_TIME - 1, function()
			if chunk.Parent then
				chunk.Anchored = true
				chunk.CanCollide = false
				local tween = game:GetService("TweenService"):Create(
					chunk, TweenInfo.new(1), { Transparency = 1 }
				)
				tween:Play()
			end
		end)
		Debris:AddItem(chunk, D.DEBRIS_FADE_TIME)
	end

	local originalParent = target.Parent
	local originalCFrame = target.CFrame
	target.Parent = nil

	task.delay(D.WALL_RESPAWN_TIME, function()
		target.CFrame = originalCFrame
		target.Parent = originalParent
		broken[target] = nil
	end)
end

-- Public: abilities call this to smash destructibles in an area
-- (e.g. Crown Breaker, ultimate shockwaves).
function DestructionService.SmashArea(position: Vector3, radius: number, velocity: Vector3?)
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("BasePart") and not broken[instance] then
			if (instance.Position - position).Magnitude <= radius then
				shatter(instance, velocity or Vector3.new(0, 20, 0))
			end
		end
	end
end

local function watchPart(part: BasePart)
	part.Touched:Connect(function(hit)
		if broken[part] then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		-- Only ragdoll-flying bodies break walls (funny + intentional)
		if character:GetAttribute("RagdollFlying") ~= true then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and root.AssemblyLinearVelocity.Magnitude >= D.MIN_IMPACT_SPEED then
			shatter(part, root.AssemblyLinearVelocity)
		end
	end)
end

function DestructionService.Init()
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("BasePart") then
			watchPart(instance)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
		if instance:IsA("BasePart") then
			watchPart(instance)
		end
	end)
end

return DestructionService
