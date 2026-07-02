--!strict
-- VFXUtil: shared helpers for replicated effects.
-- Server broadcasts small {fx=..., ...} payloads via the CombatFX remote;
-- clients call VFXUtil.Play locally. Nothing here affects gameplay state.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local VFXUtil = {}

-- Weapon color identities (single source of truth for VFX + UI accents)
VFXUtil.WeaponColors = {
	Ashfang = Color3.fromRGB(255, 120, 40),
	Frostveil = Color3.fromRGB(140, 225, 255),
	Voidneedle = Color3.fromRGB(150, 70, 255),
	Thundercrown = Color3.fromRGB(255, 220, 80),
}

local function makeNeonPart(size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = Workspace
	return part
end

-- Expanding shockwave ring (ultimates, clash resolve, heavy landings)
function VFXUtil.Shockwave(position: Vector3, color: Color3, maxRadius: number, duration: number)
	local ring = makeNeonPart(Vector3.new(1, 0.4, 1), CFrame.new(position), color)
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Transparency = 0.2
	local tween = TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.6, maxRadius * 2, maxRadius * 2),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(ring, duration + 0.1)
end

-- Quick hit spark burst at a position
function VFXUtil.HitSpark(position: Vector3, color: Color3)
	local spark = makeNeonPart(Vector3.new(0.6, 0.6, 0.6), CFrame.new(position), color)
	spark.Shape = Enum.PartType.Ball
	local tween = TweenService:Create(spark, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(3.2, 3.2, 3.2),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(spark, 0.25)
end

-- Attach a colored sword trail to a blade part
function VFXUtil.AttachTrail(blade: BasePart, color: Color3): Trail
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, blade.Size.Y / 2, 0)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -blade.Size.Y / 2, 0)
	a1.Parent = blade
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.25
	trail.LightEmission = 1
	trail.Enabled = false
	trail.Parent = blade
	return trail
end

-- Aura rig: particle emitter attached to the character root.
-- tier 1..3 scales density/size (levels 10/20/30 = tier1..3, 40/50 recolor+beams later).
function VFXUtil.ApplyAura(character: Model, color: Color3, tier: number): ParticleEmitter?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local existing = root:FindFirstChild("SoulAura")
	if existing then
		existing:Destroy()
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SoulAura"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.3 + tier * 0.25)
	emitter.Rate = 8 + tier * 10
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = root
	return emitter
end

function VFXUtil.RemoveAura(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	local aura = root and root:FindFirstChild("SoulAura")
	if aura then
		aura:Destroy()
	end
end

return VFXUtil
