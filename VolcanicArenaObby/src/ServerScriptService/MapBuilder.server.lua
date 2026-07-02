--[[
	MapBuilder.server.lua
	--------------------------------------------------------------------
	WHERE THIS GOES:  ServerScriptService > MapBuilder (Script)

	Builds the entire "Volcanic Arena Obby" map from code at server
	start, so you don't have to place a single part by hand:

	  * Central circular spawn platform (with SpawnLocation)
	  * A winding trail of floating rock islands rising over the lava
	  * Obby jumps + TweenService moving platforms between islands
	  * Checkpoint pads (tagged "Checkpoint" with an Order attribute —
	    CheckpointService picks them up automatically)
	  * A glowing lava ocean below everything (tagged "Lava" —
	    DeathHandler makes it lethal)
	  * A final golden treasure platform with a chest
	  * Atmospheric lighting, smoke columns, rising embers, lava glow
	    and (optional) ambient volcano rumble

	Everything lands in a Workspace folder called "VolcanicArena", so
	you can delete that one folder to remove the whole map.

	Want to hand-build or decorate instead?  Turn any of the build
	steps off at the BUILD SWITCHES table below and place your own
	parts — as long as lava parts are tagged "Lava" and checkpoints
	are tagged "Checkpoint" with an Order attribute, the systems work.
--------------------------------------------------------------------]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ObbyConfig"))
local C   = Config.Colors
local MAP = Config.Map

local BUILD_SWITCHES = {
	Lava            = true,
	SpawnPlatform   = true,
	Islands         = true,
	MovingPlatforms = true,
	Treasure        = true,
	Lighting        = true,
	Ambience        = true,
}

local rng = Random.new(7) -- fixed seed: same arena every server start

-- Root folder for the whole map
local arena = Instance.new("Folder")
arena.Name = "VolcanicArena"
arena.Parent = workspace

--------------------------------------------------------------------
-- Part helpers
--------------------------------------------------------------------
local function newPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	return part
end

-- A chunky rock disc: flattened cylinder + jagged chunks underneath
local function makeIsland(centerPosition, radius)
	local island = Instance.new("Model")
	island.Name = "Island"

	local top = newPart({
		Name = "Surface",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Slate,
		Color = C.Rock,
		Size = Vector3.new(3, radius * 2, radius * 2),
		-- Cylinders point along X; roll so the flat face is up
		CFrame = CFrame.new(centerPosition) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = island,
	})

	-- Glowing cracks ring under the rim (cheap lava-lit look)
	local rim = newPart({
		Name = "GlowRim",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = C.Lava,
		Size = Vector3.new(0.6, radius * 2 + 0.4, radius * 2 + 0.4),
		CFrame = top.CFrame * CFrame.new(-1.4, 0, 0), -- just below the surface
		CanCollide = false,
		Parent = island,
	})
	rim.Transparency = 0.35

	-- Jagged rocks hanging below, so islands read as floating boulders
	local chunkCount = rng:NextInteger(3, 5)
	for i = 1, chunkCount do
		local size = radius * rng:NextNumber(0.5, 0.9)
		newPart({
			Name = "UnderRock",
			Material = Enum.Material.Basalt,
			Color = C.RockDark,
			Size = Vector3.new(size, size * rng:NextNumber(1.2, 2), size),
			CFrame = CFrame.new(centerPosition + Vector3.new(
					rng:NextNumber(-radius * 0.4, radius * 0.4),
					-size * 0.8,
					rng:NextNumber(-radius * 0.4, radius * 0.4)))
				* CFrame.Angles(rng:NextNumber(0, 0.5), rng:NextNumber(0, 3), rng:NextNumber(0, 0.5)),
			CanCollide = false,
			Parent = island,
		})
	end

	island.PrimaryPart = top
	island.Parent = arena
	return island, top
end

local function makeCheckpoint(position, order)
	local pad = newPart({
		Name = "Checkpoint" .. order,
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = C.Checkpoint,
		Size = Vector3.new(0.6, 7, 7),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = arena,
	})
	pad:SetAttribute("Order", order)
	CollectionService:AddTag(pad, "Checkpoint")

	-- Floating number above the pad
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(4, 4)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 200
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = C.Checkpoint
	label.TextStrokeTransparency = 0.4
	label.Text = tostring(order)
	label.Parent = gui
	gui.Parent = pad
	return pad
end

--------------------------------------------------------------------
-- 1) LAVA OCEAN
--------------------------------------------------------------------
if BUILD_SWITCHES.Lava then
	local lava = newPart({
		Name = "LavaOcean",
		Material = Enum.Material.Neon,
		Color = C.Lava,
		Size = Vector3.new(MAP.LavaSize, 16, MAP.LavaSize),
		CFrame = CFrame.new(0, MAP.LavaHeight - 8, 0),
		Parent = arena,
	})
	CollectionService:AddTag(lava, "Lava")

	-- Slow "breathing" glow pulse
	TweenService:Create(lava, TweenInfo.new(
		3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true
	), { Color = C.LavaHot }):Play()

	-- A dark basalt shell around the lava so the horizon isn't neon
	newPart({
		Name = "BasaltRim",
		Material = Enum.Material.Basalt,
		Color = C.RockDark,
		Size = Vector3.new(MAP.LavaSize + 200, 60, MAP.LavaSize + 200),
		CFrame = CFrame.new(0, MAP.LavaHeight - 60, 0),
		Parent = arena,
	})
end

--------------------------------------------------------------------
-- 2) CENTRAL SPAWN PLATFORM
--------------------------------------------------------------------
local spawnCenter = Vector3.new(0, MAP.IslandBaseHeight, 0)
if BUILD_SWITCHES.SpawnPlatform then
	local _, top = makeIsland(spawnCenter, 16)
	top.Name = "SpawnIsland"

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.Anchored = true
	spawnLocation.Material = Enum.Material.Slate
	spawnLocation.Color = C.RockDark
	spawnLocation.CFrame = CFrame.new(spawnCenter + Vector3.new(0, 2, 0))
	spawnLocation.Duration = 0 -- no forcefield flicker
	spawnLocation.Parent = arena

	-- Decorative torch pillars around the spawn
	for i = 1, 4 do
		local angle = math.rad(i * 90 + 45)
		local pos = spawnCenter + Vector3.new(math.cos(angle) * 13, 4, math.sin(angle) * 13)
		local pillar = newPart({
			Name = "TorchPillar",
			Material = Enum.Material.Basalt,
			Color = C.RockDark,
			Size = Vector3.new(2, 6, 2),
			CFrame = CFrame.new(pos),
			Parent = arena,
		})
		local flame = Instance.new("Fire")
		flame.Size = 6
		flame.Heat = 12
		flame.Color = C.LavaHot
		flame.SecondaryColor = C.Lava
		flame.Parent = pillar
		local light = Instance.new("PointLight")
		light.Color = C.LavaHot
		light.Range = 18
		light.Brightness = 2
		light.Parent = pillar
	end
end

--------------------------------------------------------------------
-- 3) ISLAND TRAIL + OBBY JUMPS + CHECKPOINTS
--------------------------------------------------------------------
-- The trail spirals outward and upward from spawn.  Every few
-- islands gets a checkpoint; some gaps get small hop-stones, others
-- get a moving platform (built in step 4).
local trail = {}          -- { {center = Vector3, radius = number}, ... }
local movingGaps = {}     -- { {from = Vector3, to = Vector3}, ... }

if BUILD_SWITCHES.Islands then
	local ISLAND_COUNT = 12
	local angle = 0
	local distance = 42
	local height = MAP.IslandBaseHeight
	local previousCenter = spawnCenter
	local previousRadius = 16
	local checkpointOrder = 0

	for i = 1, ISLAND_COUNT do
		angle += rng:NextNumber(0.5, 0.8)          -- spiral around the arena
		distance += rng:NextNumber(16, 24)
		height += MAP.IslandRise

		local radius = rng:NextNumber(7, 11)
		local center = Vector3.new(
			math.cos(angle) * distance, height, math.sin(angle) * distance)
		makeIsland(center, radius)
		table.insert(trail, { center = center, radius = radius })

		local gap = (Vector3.new(center.X, 0, center.Z)
			- Vector3.new(previousCenter.X, 0, previousCenter.Z)).Magnitude
			- radius - previousRadius

		if i % 4 == 2 then
			-- Long gap: bridged by a moving platform (step 4)
			table.insert(movingGaps, { from = previousCenter, to = center })
		elseif gap > MAP.JumpGap then
			-- Medium gap: scatter 1-2 small hop-stones so it's jumpable
			local hops = math.floor(gap / MAP.JumpGap)
			for h = 1, hops do
				local t = h / (hops + 1)
				local hopCenter = previousCenter:Lerp(center, t) + Vector3.new(
					rng:NextNumber(-3, 3), 1, rng:NextNumber(-3, 3))
				makeIsland(hopCenter, rng:NextNumber(2.5, 4))
			end
		end

		-- Checkpoint every third island
		if i % 3 == 0 then
			checkpointOrder += 1
			makeCheckpoint(center + Vector3.new(0, 2, 0), checkpointOrder)
		end

		previousCenter = center
		previousRadius = radius
	end
end

--------------------------------------------------------------------
-- 4) MOVING PLATFORMS (TweenService, linear so riding feels fair)
--------------------------------------------------------------------
if BUILD_SWITCHES.MovingPlatforms then
	for _, gapInfo in ipairs(movingGaps) do
		local from = gapInfo.from + Vector3.new(0, 2.5, 0)
		local to   = gapInfo.to   + Vector3.new(0, 2.5, 0)
		local midHeight = math.max(from.Y, to.Y)
		local startCFrame = CFrame.new(from.X, midHeight, from.Z)
		local endCFrame   = CFrame.new(to.X,   midHeight, to.Z)

		local platform = newPart({
			Name = "MovingPlatform",
			Material = Enum.Material.Basalt,
			Color = C.RockDark,
			Size = Vector3.new(8, 1.5, 8),
			CFrame = startCFrame,
			Parent = arena,
		})
		-- Neon edge strip so players can spot it against the dark
		local strip = newPart({
			Name = "EdgeGlow",
			Material = Enum.Material.Neon,
			Color = C.LavaHot,
			Size = Vector3.new(8.4, 0.4, 8.4),
			CFrame = startCFrame * CFrame.new(0, -0.6, 0),
			CanCollide = false,
			Parent = platform,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = platform
		weld.Part1 = strip
		weld.Parent = platform
		strip.Anchored = false

		local travelTime = (endCFrame.Position - startCFrame.Position).Magnitude
			/ MAP.MovingPlatformSpeed
		-- Linear + auto-reverse + infinite repeats = permanent ferry
		TweenService:Create(platform, TweenInfo.new(
			travelTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut,
			-1, true, 0.6
		), { CFrame = endCFrame }):Play()
	end
end

--------------------------------------------------------------------
-- 5) FINAL TREASURE PLATFORM
--------------------------------------------------------------------
if BUILD_SWITCHES.Treasure and #trail > 0 then
	local last = trail[#trail]
	local direction = Vector3.new(last.center.X, 0, last.center.Z).Unit
	local treasureCenter = last.center + direction * 34 + Vector3.new(0, MAP.IslandRise, 0)

	local _, top = makeIsland(treasureCenter, 14)
	top.Name = "TreasureIsland"
	top.Color = Color3.fromRGB(80, 66, 50) -- warmer rock for the finale

	-- Final checkpoint on the treasure island
	local finalOrder = 99
	makeCheckpoint(treasureCenter + Vector3.new(-8, 2, 0), finalOrder)

	-- The chest: simple stylized box + lid + glow
	local chestBase = newPart({
		Name = "ChestBase",
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(112, 70, 34),
		Size = Vector3.new(6, 3.5, 4),
		CFrame = CFrame.new(treasureCenter + Vector3.new(0, 3.5, 0)),
		Parent = arena,
	})
	newPart({
		Name = "ChestLid",
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(92, 56, 26),
		Size = Vector3.new(6.2, 1.4, 4.2),
		CFrame = chestBase.CFrame * CFrame.new(0, 2.2, -0.6) * CFrame.Angles(math.rad(-35), 0, 0),
		Parent = arena,
	})
	local gold = newPart({
		Name = "ChestGold",
		Material = Enum.Material.Neon,
		Color = C.Treasure,
		Size = Vector3.new(5.4, 1, 3.4),
		CFrame = chestBase.CFrame * CFrame.new(0, 1.9, 0.4),
		CanCollide = false,
		Parent = arena,
	})
	local goldLight = Instance.new("PointLight")
	goldLight.Color = C.Treasure
	goldLight.Brightness = 3
	goldLight.Range = 24
	goldLight.Parent = gold

	-- Sky beam so the goal is visible from spawn
	local beam = newPart({
		Name = "GoalBeam",
		Material = Enum.Material.Neon,
		Color = C.Treasure,
		Size = Vector3.new(1.5, 300, 1.5),
		CFrame = CFrame.new(treasureCenter + Vector3.new(0, 150, 0)),
		CanCollide = false,
		Transparency = 0.6,
		Parent = arena,
	})
	beam.CanQuery = false

	-- Victory: sparkle + fanfare + message on touching the chest
	local celebrated = {} -- [player] = true, one celebration each
	chestBase.Touched:Connect(function(hit)
		local player = game:GetService("Players"):GetPlayerFromCharacter(hit.Parent)
		if not player or celebrated[player] then return end
		celebrated[player] = true

		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(C.Treasure)
		sparkle.Lifetime = NumberRange.new(0.8, 1.5)
		sparkle.Speed = NumberRange.new(8, 16)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = 0
		sparkle.Parent = chestBase
		sparkle:Emit(80)
		game:GetService("Debris"):AddItem(sparkle, 3)

		if Config.Sounds.Victory ~= "" then
			local fanfare = Instance.new("Sound")
			fanfare.SoundId = Config.Sounds.Victory
			fanfare.Parent = chestBase
			fanfare:Play()
			game:GetService("Debris"):AddItem(fanfare, 8)
		end
	end)
end

--------------------------------------------------------------------
-- 6) ATMOSPHERE, LIGHTING & PARTICLE AMBIENCE
--------------------------------------------------------------------
if BUILD_SWITCHES.Lighting then
	Lighting.ClockTime = 2                -- volcanic night
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(45, 25, 20)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 35, 25)
	Lighting.FogEnd = 700
	Lighting.FogColor = Color3.fromRGB(60, 22, 10)

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.35
	atmosphere.Haze = 2.2
	atmosphere.Color = Color3.fromRGB(120, 60, 40)
	atmosphere.Decay = Color3.fromRGB(140, 60, 30)
	atmosphere.Glare = 0.4
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Threshold = 1.2
	bloom.Size = 40
	bloom.Parent = Lighting

	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		or Instance.new("ColorCorrectionEffect")
	colorCorrection.TintColor = Color3.fromRGB(255, 230, 215)
	colorCorrection.Contrast = 0.12
	colorCorrection.Saturation = 0.08
	colorCorrection.Parent = Lighting
end

if BUILD_SWITCHES.Ambience then
	-- Smoke columns rising from the lava at the arena edges
	for i = 1, 6 do
		local angle = math.rad(i * 60)
		local dist = rng:NextNumber(120, 220)
		local anchor = newPart({
			Name = "SmokeColumn",
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Size = Vector3.new(4, 4, 4),
			CFrame = CFrame.new(math.cos(angle) * dist, MAP.LavaHeight + 4, math.sin(angle) * dist),
			Parent = arena,
		})
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(70, 45, 40), Color3.fromRGB(25, 25, 25))
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 8),
			NumberSequenceKeypoint.new(1, 24),
		})
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Lifetime = NumberRange.new(6, 10)
		smoke.Speed = NumberRange.new(6, 12)
		smoke.Rate = 4
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.RotSpeed = NumberRange.new(-20, 20)
		smoke.Parent = anchor
	end

	-- Rising orange embers across the whole arena
	local emberAnchor = newPart({
		Name = "EmberField",
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Size = Vector3.new(400, 1, 400),
		CFrame = CFrame.new(0, MAP.LavaHeight + 6, 0),
		Parent = arena,
	})
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/fire_main.dds"
	embers.Color = ColorSequence.new(C.LavaHot, C.Lava)
	embers.Size = NumberSequence.new(0.35)
	embers.Lifetime = NumberRange.new(4, 8)
	embers.Speed = NumberRange.new(8, 14)
	embers.Rate = 30
	embers.LightEmission = 1
	embers.Acceleration = Vector3.new(2, 4, 1) -- lazy sideways drift
	embers.Parent = emberAnchor

	-- Looping volcano rumble (only if you pasted an ID in ObbyConfig)
	if Config.Sounds.VolcanoLoop ~= "" then
		local rumble = Instance.new("Sound")
		rumble.Name = "VolcanoRumble"
		rumble.SoundId = Config.Sounds.VolcanoLoop
		rumble.Looped = true
		rumble.Volume = 0.4
		rumble.Parent = workspace
		rumble:Play()
	end
end

print("[VolcanicArena] Map built: " .. #trail .. " islands, "
	.. #movingGaps .. " moving platforms.")
