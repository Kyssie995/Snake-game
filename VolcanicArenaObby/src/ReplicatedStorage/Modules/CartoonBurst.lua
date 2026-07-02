--[[
	CartoonBurst.lua
	--------------------------------------------------------------------
	WHERE THIS GOES:  ReplicatedStorage > Modules > CartoonBurst (ModuleScript)

	The reusable cartoon death / reset animation.  100% stylized and
	non-realistic: the character shakes, puffs up, red PAINT-style
	splats pop out, then the whole thing bursts into comic chunks,
	stars and smoke.  No gore, no body detail — just paint.

	This module is SERVER-SIDE (spawned parts replicate to everyone).
	Camera shake + local boom are handled by the client script
	(DeathEffectsClient) via the PlayDeathFX RemoteEvent.

	REUSING IT IN OTHER MAPS:
		local CartoonBurst = require(ReplicatedStorage.Modules.CartoonBurst)
		CartoonBurst.Play(character)              -- fire and forget
		CartoonBurst.Play(character, function()   -- or with a callback
			-- runs when the burst finishes (respawn the player here)
		end)

	It only needs ObbyConfig next to it and a RemoteEvent named
	"PlayDeathFX" inside ReplicatedStorage.Remotes (created for you by
	DeathHandler.server.lua).

	CUSTOM SPLAT MESHPARTS (optional, recommended):
	Put your own stylized MeshParts in a folder:
		ReplicatedStorage > Assets > SplatMeshes
	Any MeshParts found there are cloned at random for the splats and
	chunks.  If the folder is missing, the module auto-builds simple
	ball/disc parts so everything still works out of the box.
	See the README for how to set up the MeshParts.
--------------------------------------------------------------------]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")

local Config = require(script.Parent:WaitForChild("ObbyConfig"))
local D      = Config.Death
local C      = Config.Colors

local CartoonBurst = {}

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------

local rng = Random.new()

-- One shared folder in Workspace so debris stays tidy
local function getEffectsFolder()
	local folder = workspace:FindFirstChild("CartoonBurstFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CartoonBurstFX"
		folder.Parent = workspace
	end
	return folder
end

local function playSound(soundId, parent, volume, pitch)
	if soundId == nil or soundId == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

-- Grabs a random custom splat MeshPart if the user made an Assets
-- folder, otherwise builds a stylized ball so the system works
-- without any manual asset setup.
local function makeSplatPart(size)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local meshFolder = assets and assets:FindFirstChild("SplatMeshes")

	local part
	if meshFolder and #meshFolder:GetChildren() > 0 then
		local meshes = meshFolder:GetChildren()
		part = meshes[rng:NextInteger(1, #meshes)]:Clone()
		part.Size = size
	else
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Size = size
	end

	part.Material = Enum.Material.SmoothPlastic
	part.Color = rng:NextNumber() > 0.4 and C.SplatRed or C.SplatRed2
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Flat comic "paint puddle" left on the ground
local function makeGroundSplat(position)
	local splat = Instance.new("Part")
	splat.Shape = Enum.PartType.Cylinder
	splat.Material = Enum.Material.SmoothPlastic
	splat.Color = C.SplatRed
	splat.Size = Vector3.new(0.2, 0.5, 0.5)
	splat.CanCollide = false
	splat.CanQuery = false
	splat.Anchored = true
	-- Cylinders lie on their X axis, so roll 90 degrees to face up
	splat.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return splat
end

-- Comic-book white "poof" star (built from crossed neon wedges)
local function makePoofStar(position)
	local star = Instance.new("Part")
	star.Shape = Enum.PartType.Ball
	star.Material = Enum.Material.Neon
	star.Color = C.PoofWhite
	star.Size = Vector3.new(1.2, 1.2, 1.2)
	star.Anchored = true
	star.CanCollide = false
	star.CanQuery = false
	star.CFrame = CFrame.new(position)
	return star
end

-- Grey cartoon smoke burst
local function attachSmoke(part)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(180, 180, 180), Color3.fromRGB(90, 90, 90))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 6),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.8, 1.6)
	smoke.Speed = NumberRange.new(4, 9)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = part
	return smoke
end

-- Red confetti-ish paint particles
local function attachRedBurstParticles(part)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(C.SplatRed, C.SplatRed2)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Rate = 0
	emitter.Parent = part
	return emitter
end

--------------------------------------------------------------------
-- Animation phases
--------------------------------------------------------------------

-- (1) Freeze the character in place
local function freeze(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end
	if root then
		root.Anchored = true
	end
end

-- (2) Pressure build-up: shake harder and harder + puff up (R15)
local function shake(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root then return end

	-- Puff the character up like an over-inflated balloon (R15 only;
	-- R6 has no scale values, the shake alone still sells the gag)
	if humanoid then
		for _, scaleName in ipairs({ "BodyWidthScale", "BodyDepthScale", "BodyHeightScale", "HeadScale" }) do
			local scaleValue = humanoid:FindFirstChild(scaleName)
			if scaleValue and scaleValue:IsA("NumberValue") then
				TweenService:Create(scaleValue, TweenInfo.new(
					D.ShakeTime, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out
				), { Value = scaleValue.Value * D.InflateScale }):Play()
			end
		end
	end

	playSound(Config.Sounds.Pop, root, 0.8, 0.6)

	local baseCFrame = root.CFrame
	local elapsed = 0
	while elapsed < D.ShakeTime do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		local intensity = (elapsed / D.ShakeTime) * D.ShakeIntensity
		root.CFrame = baseCFrame
			* CFrame.new(
				rng:NextNumber(-intensity, intensity),
				rng:NextNumber(-intensity, intensity) * 0.5,
				rng:NextNumber(-intensity, intensity))
			* CFrame.Angles(
				math.rad(rng:NextNumber(-8, 8) * intensity),
				math.rad(rng:NextNumber(-8, 8) * intensity),
				math.rad(rng:NextNumber(-8, 8) * intensity))
	end
	root.CFrame = baseCFrame
end

-- (3) Red splats pop out around the character during the build-up
local function popSplats(character, effectsFolder)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local origin = root.Position

	for i = 1, D.SplatCount do
		task.delay((i - 1) * (D.ShakeTime * 0.7 / D.SplatCount), function()
			local size = rng:NextNumber(0.6, 1.4)
			local splat = makeSplatPart(Vector3.new(size, size, size))
			splat.Anchored = true

			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = rng:NextNumber(2.5, 4.5)
			local target = origin + Vector3.new(
				math.cos(angle) * dist,
				rng:NextNumber(-1, 3),
				math.sin(angle) * dist)

			splat.CFrame = CFrame.new(origin)
			splat.Parent = effectsFolder

			-- Pop outward with a bouncy tween, then shrink away
			TweenService:Create(splat, TweenInfo.new(
				0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out
			), { CFrame = CFrame.new(target) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0) }):Play()

			task.delay(0.6, function()
				TweenService:Create(splat, TweenInfo.new(0.4), {
					Size = Vector3.zero,
					Transparency = 1,
				}):Play()
			end)
			Debris:AddItem(splat, 1.2)
			playSound(Config.Sounds.Splat, splat, 0.5, rng:NextNumber(0.9, 1.4))
		end)
	end
end

-- (4)+(5) The BOOM: hide the character, throw stylized chunks,
-- stars, smoke, particles, ground paint, and fire the client FX remote
local function burst(character, effectsFolder)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local origin = root.Position

	-- Invisible anchored emitter part at the burst point
	local fxPart = Instance.new("Part")
	fxPart.Size = Vector3.new(1, 1, 1)
	fxPart.Transparency = 1
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanQuery = false
	fxPart.CFrame = CFrame.new(origin)
	local smoke = attachSmoke(fxPart)
	local redFX = attachRedBurstParticles(fxPart)
	fxPart.Parent = effectsFolder

	-- Vanish the character instantly (cartoon "gone in a puff")
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end

	-- BOOM assets
	smoke:Emit(30)
	redFX:Emit(60)
	playSound(Config.Sounds.Boom, fxPart, 1, 1)
	playSound(Config.Sounds.Splat, fxPart, 1, 0.55) -- low-pitched splat doubles as a boom layer

	-- Tell every client to shake their camera / flash the screen
	local remotes = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	local playFX = remotes and remotes:FindFirstChild(Config.Remotes.PlayDeathFX)
	if playFX then
		playFX:FireAllClients(origin)
	end

	-- Flying red chunks (physics-driven, non-collidable with players)
	for _ = 1, D.ChunkCount do
		local size = rng:NextNumber(0.5, 1.3)
		local chunk = makeSplatPart(Vector3.new(size, size, size))
		chunk.Anchored = false
		chunk.CanCollide = true
		chunk.CollisionGroup = "CartoonDebris" -- registered by DeathHandler
		chunk.CFrame = CFrame.new(origin + Vector3.new(
			rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 1.5), rng:NextNumber(-1, 1)))
		chunk.AssemblyLinearVelocity = Vector3.new(
			rng:NextNumber(-28, 28),
			rng:NextNumber(18, 42),
			rng:NextNumber(-28, 28))
		chunk.AssemblyAngularVelocity = Vector3.new(
			rng:NextNumber(-20, 20), rng:NextNumber(-20, 20), rng:NextNumber(-20, 20))
		chunk.Parent = effectsFolder

		task.delay(D.EffectLifetime - 0.5, function()
			TweenService:Create(chunk, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end)
		Debris:AddItem(chunk, D.EffectLifetime)
	end

	-- White comic stars that flash and expand
	for _ = 1, D.StarCount do
		local star = makePoofStar(origin + Vector3.new(
			rng:NextNumber(-3, 3), rng:NextNumber(-1, 3), rng:NextNumber(-3, 3)))
		star.Parent = effectsFolder
		TweenService:Create(star, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(4, 4, 4),
			Transparency = 1,
		}):Play()
		Debris:AddItem(star, 0.6)
	end

	-- Paint puddles on the ground below the burst
	for _ = 1, D.GroundSplatCount do
		local rayOrigin = origin + Vector3.new(rng:NextNumber(-4, 4), 2, rng:NextNumber(-4, 4))
		local result = workspace:Raycast(rayOrigin, Vector3.new(0, -20, 0))
		if result then
			local puddle = makeGroundSplat(result.Position + Vector3.new(0, 0.1, 0))
			puddle.Parent = effectsFolder
			local width = rng:NextNumber(2.5, 5)
			TweenService:Create(puddle, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.2, width, width),
			}):Play()
			task.delay(D.EffectLifetime - 0.6, function()
				TweenService:Create(puddle, TweenInfo.new(0.5), {
					Size = Vector3.new(0.2, 0.4, 0.4),
					Transparency = 1,
				}):Play()
			end)
			Debris:AddItem(puddle, D.EffectLifetime)
		end
	end

	Debris:AddItem(fxPart, D.EffectLifetime)
end

--------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------

--[[
	CartoonBurst.Play(character, onFinished?)
	Runs the whole sequence: freeze -> shake+splats -> BOOM -> callback.
	Yields nothing to the caller; the callback fires after
	Config.Death.RespawnDelay so you can respawn the player from it.
]]
function CartoonBurst.Play(character, onFinished)
	assert(character and character:FindFirstChild("HumanoidRootPart"),
		"CartoonBurst.Play needs a character with a HumanoidRootPart")

	task.spawn(function()
		local effectsFolder = getEffectsFolder()

		freeze(character)                     -- (1)
		task.wait(D.FreezeTime)

		popSplats(character, effectsFolder)   -- (3) runs during the shake
		shake(character)                      -- (2) yields for ShakeTime

		burst(character, effectsFolder)       -- (4)+(5)

		task.wait(D.RespawnDelay)             -- (6) handled by caller
		if onFinished then
			onFinished()
		end
	end)
end

return CartoonBurst
