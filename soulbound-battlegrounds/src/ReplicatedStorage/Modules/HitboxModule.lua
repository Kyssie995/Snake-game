--!strict
-- HitboxModule: server-side spatial-query hitboxes.
-- Usage:
--   local hits = Hitbox.Sweep({
--       attacker = character,
--       cframe = rootPart.CFrame * CFrame.new(0, 0, -4),
--       size = Vector3.new(5, 5, 7),
--   })
-- Returns a list of hit Humanoid characters (each character at most once),
-- excluding the attacker. Set _G.SOULBOUND_DEBUG_HITBOX = true to visualize.

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Hitbox = {}

export type SweepParams = {
	attacker: Model?,
	cframe: CFrame,
	size: Vector3,
	pingCompensation: number?, -- 0..1 fraction to inflate box (capped)
}

local MAX_INFLATION = 0.15 -- never inflate a hitbox more than 15%

local function visualize(cframe: CFrame, size: Vector3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0.7
	part.Color = Color3.fromRGB(255, 60, 60)
	part.Material = Enum.Material.Neon
	part.CFrame = cframe
	part.Size = size
	part.Parent = Workspace
	Debris:AddItem(part, 0.25)
end

function Hitbox.Sweep(params: SweepParams): { Model }
	local size = params.size
	if params.pingCompensation then
		local inflate = 1 + math.clamp(params.pingCompensation, 0, MAX_INFLATION)
		size = size * inflate
	end

	if _G.SOULBOUND_DEBUG_HITBOX then
		visualize(params.cframe, size)
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	if params.attacker then
		overlap.FilterDescendantsInstances = { params.attacker }
	end

	local parts = Workspace:GetPartBoundsInBox(params.cframe, size, overlap)
	local seen: { [Model]: boolean } = {}
	local hits: { Model } = {}

	for _, part in parts do
		local character = part:FindFirstAncestorOfClass("Model")
		if character and not seen[character] then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				seen[character] = true
				table.insert(hits, character)
			end
		end
	end

	return hits
end

-- Line-of-sight check so melee can't hit through walls.
function Hitbox.HasLineOfSight(fromCharacter: Model, toCharacter: Model): boolean
	local fromRoot = fromCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local toRoot = toCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not fromRoot or not toRoot then
		return false
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { fromCharacter, toCharacter }
	local direction = toRoot.Position - fromRoot.Position
	local result = Workspace:Raycast(fromRoot.Position, direction, rayParams)
	if result then
		local hit = result.Instance
		-- Debris/destructible fragments shouldn't block hits
		if hit.CanCollide and hit.Transparency < 0.9 then
			return false
		end
	end
	return true
end

-- Server-side range sanity: is target within maxRange of attacker (with a
-- generous latency allowance)? Used to validate targeted abilities.
function Hitbox.WithinRange(attacker: Model, target: Model, maxRange: number): boolean
	local a = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
	local b = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not a or not b then
		return false
	end
	return (a.Position - b.Position).Magnitude <= maxRange * 1.2
end

return Hitbox
