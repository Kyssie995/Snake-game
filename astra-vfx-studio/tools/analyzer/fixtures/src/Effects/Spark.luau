--!strict
-- Korrekte Verwendung von ParticleEmitter, Beam, TweenService, Color3, NumberSequence & Co.
-- Erwartung: keine Fehler.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(script.Parent.Parent.Shared.Config)
local Util = require(script.Parent.Parent.Shared.Util)

local Spark = {}

function Spark.makeEmitter(target: BasePart, rate: number): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = "SparkAttachment"
	attachment.Position = Vector3.new(0, 1, 0)
	attachment.Parent = target

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = rate
	emitter.Lifetime = Config.Lifetime
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Color = ColorSequence.new(Config.Palette[1], Config.Palette[2])
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = Util.fadeSequence(0, 1)
	emitter.LightEmission = 1
	emitter.Texture = "rbxassetid://243660364"
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Parent = attachment
	emitter:Emit(10)
	return emitter
end

function Spark.makeBeam(a: Attachment, b: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Attachment0 = a
	beam.Attachment1 = b
	beam.Color = ColorSequence.new(Color3.fromRGB(0, 170, 255))
	beam.Transparency = NumberSequence.new(0.2, 1)
	beam.Width0 = 0.5
	beam.Width1 = 0
	beam.FaceCamera = true
	beam.LightEmission = Util.clamp01(2)
	beam.Parent = a
	return beam
end

function Spark.flash(part: BasePart)
	local info = TweenInfo.new(Config.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(part, info, { Transparency = 1, Color = Color3.new(1, 0.5, 0) })
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			part.Material = Enum.Material.Neon
		end
	end)
	tween:Play()
	Debris:AddItem(part, Config.FadeTime + 1)
end

-- IsA verfeinert den Typ, FindFirstChildWhichIsA / Clone liefern den Klassentyp
function Spark.tintAll(root: Instance, color: Color3)
	for _, child in root:GetDescendants() do
		if child:IsA("ParticleEmitter") then
			child.Color = ColorSequence.new(color)
		elseif child:IsA("BasePart") then
			child.Color = color
		end
	end

	local light = root:FindFirstChildWhichIsA("PointLight")
	if light then
		light.Color = color
		local copy = light:Clone()
		copy.Brightness = 2
		copy.Parent = root
	end
end

function Spark.pulse(emitter: ParticleEmitter): RBXScriptConnection
	local t = 0
	return RunService.Heartbeat:Connect(function(dt: number)
		t += dt
		emitter.Rate = Config.DefaultRate * (1 + math.sin(t * 4))
	end)
end

function Spark.later(emitter: ParticleEmitter)
	task.delay(0.5, function()
		emitter.Enabled = false
	end)
	emitter:GetPropertyChangedSignal("Rate"):Connect(function()
		print("rate changed", emitter.Rate)
	end)
end

return Spark
