--!strict
-- CombatClient: receives CombatFX broadcasts and plays visuals locally.
-- Adding a weapon = add its fx cases here (or a per-weapon VFX module later).
-- Nothing in this file affects gameplay — it is pure presentation.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Modules.Net)
local Constants = require(ReplicatedStorage.Modules.CombatConstants)
local VFXUtil = require(ReplicatedStorage.Modules.VFXUtil)

local CombatClient = {}

local player = Players.LocalPlayer
local CameraController -- resolved in Init (sibling module)
local UIController

local function colorFor(weaponId: string?): Color3
	return (weaponId and VFXUtil.WeaponColors[weaponId]) or Color3.fromRGB(200, 220, 255)
end

local function rootOf(character: any): BasePart?
	if typeof(character) == "Instance" and character:IsA("Model") then
		return character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return nil
end

-- Hit-stop: brief local freeze-frame for punch
local function hitStop()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	-- Cheap hit-stop: pause animations for a few frames
	for _, track in humanoid:GetPlayingAnimationTracks() do
		local speed = track.Speed
		track:AdjustSpeed(0)
		task.delay(Constants.M1.HITSTOP, function()
			if track.IsPlaying then
				track:AdjustSpeed(speed)
			end
		end)
	end
end

-- Jagged sky-to-ground lightning bolt out of neon segments
local function lightningBolt(position: Vector3, color: Color3)
	local from = position + Vector3.new(math.random(-8, 8), 45, math.random(-8, 8))
	local points = { from }
	local segments = 6
	for i = 1, segments - 1 do
		local t = i / segments
		local point = from:Lerp(position, t)
			+ Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
		table.insert(points, point)
	end
	table.insert(points, position)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local segment = Instance.new("Part")
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.Material = Enum.Material.Neon
		segment.Color = color
		segment.Size = Vector3.new(0.35, 0.35, (a - b).Magnitude)
		segment.CFrame = CFrame.lookAt((a + b) / 2, b)
		segment.Parent = workspace
		TweenService:Create(segment, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		Debris:AddItem(segment, 0.3)
	end
	VFXUtil.HitSpark(position, color)
end

-- Translucent ghost snapshot of a character (Vanish/afterimages)
local function ghostShell(cframe: CFrame, color: Color3, lifetime: number)
	local ghost = Instance.new("Part")
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.Material = Enum.Material.ForceField
	ghost.Color = color
	ghost.Size = Vector3.new(2.4, 4.8, 1.4)
	ghost.CFrame = cframe
	ghost.Transparency = 0.5
	ghost.Parent = workspace
	TweenService:Create(ghost, TweenInfo.new(lifetime), { Transparency = 1 }):Play()
	Debris:AddItem(ghost, lifetime + 0.1)
end

local fxHandlers: { [string]: (payload: any) -> () } = {
	HitSpark = function(p)
		if typeof(p.position) == "Vector3" then
			VFXUtil.HitSpark(p.position, colorFor(p.weapon))
		end
		-- Local-player extras
		local myCharacter = player.Character
		if p.victim == myCharacter then
			CameraController.Shake(0.4)
		end
		if typeof(p.damage) == "number" and p.position then
			UIController.ShowDamageNumber(p.position, p.damage)
		end
		hitStop()
	end,
	M1Swing = function(p)
		local root = rootOf(p.character)
		if root then
			-- Trail flash on the character's blade if present
			local blade = p.character:FindFirstChild("SoulBlade", true)
			local trail = blade and blade:FindFirstChildOfClass("Trail")
			if trail then
				trail.Enabled = true
				task.delay(0.3, function()
					trail.Enabled = false
				end)
			end
		end
	end,
	SoulDash = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position - Vector3.new(0, 2, 0), Color3.fromRGB(160, 200, 255), 4, 0.3)
		end
	end,
	PerfectDodge = function(_p)
		-- Local slow-mo feel: brief FOV punch (time manipulation is server-hostile)
		CameraController.FOVPunch(-12, 0.3)
		UIController.Flash("PERFECT DODGE", Color3.fromRGB(120, 255, 200))
	end,
	PerfectDodgeFlash = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, Color3.fromRGB(120, 255, 200), 6, 0.4)
		end
	end,
	BlockHit = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position + root.CFrame.LookVector * 2, Color3.fromRGB(220, 220, 220))
		end
	end,
	GuardBreak = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, Color3.fromRGB(255, 80, 80), 8, 0.5)
		end
		if p.character == player.Character then
			CameraController.Shake(1)
			UIController.Flash("GUARD BROKEN", Color3.fromRGB(255, 80, 80))
		end
	end,
	HeavyCharge = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position, colorFor(p.weapon))
		end
	end,
	HeavySwing = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, colorFor(p.weapon), 6, 0.35)
		end
	end,
	UltimateActivate = function(p)
		local root = rootOf(p.character)
		local color = colorFor(p.weapon)
		if root then
			VFXUtil.Shockwave(root.Position, color, 25, 1.2)
			VFXUtil.ApplyAura(p.character, color, 3)
		end
		CameraController.Shake(1.5)
		if p.character == player.Character then
			CameraController.UltimatePush(Constants.ULTIMATE.ACTIVATION_TIME)
			UIController.Flash(tostring(p.name), color)
			UIController.StartUltimateTimer(p.duration)
		end
		-- Music sting hook: SoundService:PlayLocalSound(stingFor(p.weapon))
	end,
	UltimateEnd = function(p)
		VFXUtil.RemoveAura(p.character)
		-- Restore level-based aura tier
		local tier = p.character:GetAttribute("AuraTier")
		local weaponId = p.character:GetAttribute("EquippedWeapon")
		if typeof(tier) == "number" and tier > 0 and typeof(weaponId) == "string" then
			VFXUtil.ApplyAura(p.character, colorFor(weaponId), math.min(tier, 3))
		end
	end,
	Frozen = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position, Color3.fromRGB(160, 230, 255))
		end
	end,
	LevelUp = function(p)
		UIController.Flash(("%s  LEVEL %d"):format(tostring(p.weapon), p.level), Color3.fromRGB(255, 240, 150))
		local root = rootOf(player.Character)
		if root then
			VFXUtil.Shockwave(root.Position, Color3.fromRGB(255, 240, 150), 10, 0.8)
		end
	end,
	EchoAbsorbed = function(p)
		UIController.Flash("+" .. tostring(p.xp) .. " Soul XP", Color3.fromRGB(180, 220, 255))
		UIController.ShowHint(tostring(p.hint))
	end,

	-- Weapon-specific effects: alpha uses shared primitives recolored per
	-- weapon; replace with authored particle prefabs during the polish pass.
	AshfangEmberSlash = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, VFXUtil.WeaponColors.Ashfang, 9, 0.3)
		end
	end,
	AshfangWolfRush = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position, VFXUtil.WeaponColors.Ashfang)
		end
	end,
	AshfangBite = function(p)
		local root = rootOf(p.victim)
		if root then
			VFXUtil.HitSpark(root.Position, VFXUtil.WeaponColors.Ashfang)
		end
	end,
	AshfangCounterStance = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position, Color3.fromRGB(255, 200, 100))
		end
	end,
	AshfangCounterTrigger = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, VFXUtil.WeaponColors.Ashfang, 10, 0.4)
		end
		CameraController.Shake(0.8)
	end,
	AshfangFangCharge = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position + Vector3.new(0, 3, 0), VFXUtil.WeaponColors.Ashfang)
		end
	end,
	AshfangFangSlam = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, VFXUtil.WeaponColors.Ashfang, 14, 0.6)
		end
		CameraController.Shake(1)
	end,
	AshfangWolfLunge = function(p)
		local root = rootOf(p.victim)
		if root then
			VFXUtil.HitSpark(root.Position, VFXUtil.WeaponColors.Ashfang)
		end
	end,

	-- Frostveil: complete FX set (mirrors Ashfang's per-move coverage)
	FrostveilIceCut = function(p)
		-- Crescent wave: a flattened neon shard gliding forward
		if typeof(p.origin) ~= "Vector3" then
			return
		end
		local root = rootOf(p.character)
		local look = root and root.CFrame.LookVector or Vector3.zAxis
		local wave = Instance.new("Part")
		wave.Anchored = true
		wave.CanCollide = false
		wave.CanQuery = false
		wave.Material = Enum.Material.Neon
		wave.Color = VFXUtil.WeaponColors.Frostveil
		wave.Size = Vector3.new(7, 0.6, 1.2)
		wave.CFrame = CFrame.lookAt(p.origin, p.origin + look)
		wave.Transparency = 0.2
		wave.Parent = workspace
		local range = typeof(p.range) == "number" and p.range or 30
		TweenService:Create(wave, TweenInfo.new(0.4, Enum.EasingStyle.Linear), {
			CFrame = wave.CFrame * CFrame.new(0, 0, -range),
			Transparency = 0.7,
		}):Play()
		task.delay(0.45, function()
			wave:Destroy()
		end)
	end,
	FrostveilIceShatter = function(p)
		if typeof(p.position) == "Vector3" then
			VFXUtil.HitSpark(p.position, VFXUtil.WeaponColors.Frostveil)
		end
	end,
	FrostveilFrozenStep = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position - Vector3.new(0, 2, 0), VFXUtil.WeaponColors.Frostveil, 5, 0.3)
		end
	end,
	FrostveilMirrorPlace = function(p)
		if typeof(p.position) == "Vector3" then
			VFXUtil.HitSpark(p.position, Color3.fromRGB(220, 245, 255))
		end
	end,
	FrostveilMirrorSpring = function(p)
		if typeof(p.position) == "Vector3" then
			VFXUtil.Shockwave(p.position, VFXUtil.WeaponColors.Frostveil, 8, 0.5)
		end
		CameraController.Shake(0.5)
	end,
	FrostveilCrystalCharge = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position, VFXUtil.WeaponColors.Frostveil)
		end
	end,
	FrostveilCrystalBurst = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, VFXUtil.WeaponColors.Frostveil, (p.radius or 14), 0.6)
			-- Spike ring: 8 ice shards jutting outward
			for i = 1, 8 do
				local angle = (i / 8) * math.pi * 2
				local spike = Instance.new("Part")
				spike.Anchored = true
				spike.CanCollide = false
				spike.CanQuery = false
				spike.Material = Enum.Material.Ice
				spike.Color = VFXUtil.WeaponColors.Frostveil
				spike.Size = Vector3.new(1, 4, 1)
				spike.CFrame = CFrame.new(root.Position)
					* CFrame.Angles(0, angle, 0)
					* CFrame.new(0, -2, -6)
					* CFrame.Angles(math.rad(30), 0, 0)
				spike.Parent = workspace
				TweenService:Create(spike, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					CFrame = spike.CFrame * CFrame.new(0, 2.5, 0),
				}):Play()
				task.delay(0.9, function()
					TweenService:Create(spike, TweenInfo.new(0.4), { Transparency = 1 }):Play()
					task.delay(0.45, function()
						spike:Destroy()
					end)
				end)
			end
		end
		CameraController.Shake(0.8)
	end,
	FrostveilDomeStart = function(p)
		if typeof(p.position) ~= "Vector3" then
			return
		end
		VFXUtil.Shockwave(p.position, VFXUtil.WeaponColors.Frostveil, p.radius or 30, 1)
		-- Translucent dome shell for the ultimate's duration
		local dome = Instance.new("Part")
		dome.Name = "WinterDome"
		dome.Anchored = true
		dome.CanCollide = false
		dome.CanQuery = false
		dome.Shape = Enum.PartType.Ball
		dome.Material = Enum.Material.ForceField
		dome.Color = VFXUtil.WeaponColors.Frostveil
		dome.Size = Vector3.one * ((p.radius or 30) * 2)
		dome.CFrame = CFrame.new(p.position)
		dome.Transparency = 0.85
		dome.Parent = workspace
		task.delay(typeof(p.duration) == "number" and p.duration or 18, function()
			TweenService:Create(dome, TweenInfo.new(0.6), { Transparency = 1, Size = Vector3.one }):Play()
			task.delay(0.7, function()
				dome:Destroy()
			end)
		end)
	end,
	FrostveilDomePulse = function(p)
		if typeof(p.position) == "Vector3" then
			VFXUtil.Shockwave(p.position - Vector3.new(0, 2, 0), VFXUtil.WeaponColors.Frostveil, (p.radius or 30) * 0.6, 0.8)
		end
	end,
	FrostveilCloneFlicker = function(p)
		-- Ghost clones blink at the dome edge: cheap illusion via neon shells
		local root = rootOf(p.character)
		if not root then
			return
		end
		local radius = (p.radius or 30) * 0.8
		for _ = 1, 3 do
			local angle = math.random() * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
			ghostShell(CFrame.new(root.Position + offset), VFXUtil.WeaponColors.Frostveil, 0.7)
		end
	end,

	-- Voidneedle: complete FX set
	VoidneedlePierce = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position, VFXUtil.WeaponColors.Voidneedle)
		end
	end,
	VoidneedlePhase = function(p)
		local root = rootOf(p.character)
		if root then
			ghostShell(root.CFrame, VFXUtil.WeaponColors.Voidneedle, 0.4)
		end
	end,
	VoidneedleVanish = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, VFXUtil.WeaponColors.Voidneedle, p.active and 6 or 4, 0.35)
			if p.active then
				ghostShell(root.CFrame, VFXUtil.WeaponColors.Voidneedle, 0.5)
			end
		end
	end,
	VoidneedleThread = function(p)
		-- Dark tether beam between caster and victim for the thread duration
		local casterRoot = rootOf(p.character)
		local victimRoot = rootOf(p.victim)
		if not casterRoot or not victimRoot then
			return
		end
		local a0 = Instance.new("Attachment")
		a0.Parent = casterRoot
		local a1 = Instance.new("Attachment")
		a1.Parent = victimRoot
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(VFXUtil.WeaponColors.Voidneedle)
		beam.Width0 = 0.25
		beam.Width1 = 0.25
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Parent = casterRoot
		local lifetime = (typeof(p.duration) == "number" and p.duration or 1) + 0.2
		Debris:AddItem(beam, lifetime)
		Debris:AddItem(a0, lifetime)
		Debris:AddItem(a1, lifetime)
	end,
	VoidneedleThreadSnap = function(p)
		local root = rootOf(p.victim)
		if root then
			VFXUtil.HitSpark(root.Position, Color3.fromRGB(200, 160, 255))
		end
	end,
	VoidneedleThreadPull = function(p)
		local root = rootOf(p.victim)
		if root then
			VFXUtil.Shockwave(root.Position, VFXUtil.WeaponColors.Voidneedle, 5, 0.3)
		end
	end,
	VoidneedleRiftOut = function(p)
		local root = rootOf(p.character)
		if root then
			ghostShell(root.CFrame, VFXUtil.WeaponColors.Voidneedle, 0.5)
			VFXUtil.Shockwave(root.Position, VFXUtil.WeaponColors.Voidneedle, 5, 0.3)
		end
	end,
	VoidneedleRiftIn = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position, VFXUtil.WeaponColors.Voidneedle)
		end
	end,
	VoidneedleAfterimage = function(p)
		if typeof(p.cframe) == "CFrame" then
			ghostShell(p.cframe, VFXUtil.WeaponColors.Voidneedle, 0.6)
		end
	end,

	-- Thundercrown: complete FX set
	ThundercrownCleave = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position + Vector3.new(0, 4, 0), VFXUtil.WeaponColors.Thundercrown)
		end
	end,
	ThundercrownCleaveImpact = function(p)
		if typeof(p.position) == "Vector3" then
			lightningBolt(p.position, VFXUtil.WeaponColors.Thundercrown)
		end
	end,
	ThundercrownLeap = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position - Vector3.new(0, 2, 0), VFXUtil.WeaponColors.Thundercrown, 6, 0.4)
		end
	end,
	ThundercrownCrash = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, VFXUtil.WeaponColors.Thundercrown, 16, 0.6)
			lightningBolt(root.Position, VFXUtil.WeaponColors.Thundercrown)
		end
		CameraController.Shake(1)
	end,
	ThundercrownField = function(p)
		if typeof(p.position) ~= "Vector3" then
			return
		end
		-- Crackling ground disc for the field's duration
		local radius = p.radius or 12
		local duration = typeof(p.duration) == "number" and p.duration or 4
		local disc = Instance.new("Part")
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.Shape = Enum.PartType.Cylinder
		disc.Material = Enum.Material.Neon
		disc.Color = VFXUtil.WeaponColors.Thundercrown
		disc.Size = Vector3.new(0.3, radius * 2, radius * 2)
		disc.Orientation = Vector3.new(0, 0, 90)
		disc.CFrame = CFrame.new(p.position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		disc.Transparency = 0.75
		disc.Parent = workspace
		Debris:AddItem(disc, duration)
		task.spawn(function()
			for _ = 1, duration do
				task.wait(1)
				if disc.Parent then
					local angle = math.random() * math.pi * 2
					local sparkPos = p.position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (radius * math.random())
					VFXUtil.HitSpark(sparkPos, VFXUtil.WeaponColors.Thundercrown)
				end
			end
		end)
	end,
	ThundercrownCrownCharge = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.HitSpark(root.Position + Vector3.new(0, 5, 0), VFXUtil.WeaponColors.Thundercrown)
		end
	end,
	ThundercrownCrownBreaker = function(p)
		local root = rootOf(p.character)
		if root then
			VFXUtil.Shockwave(root.Position, VFXUtil.WeaponColors.Thundercrown, 14, 0.5)
			lightningBolt(root.Position + root.CFrame.LookVector * 6, VFXUtil.WeaponColors.Thundercrown)
		end
		CameraController.Shake(1.3)
	end,
	ThundercrownStrike = function(p)
		if typeof(p.position) == "Vector3" then
			lightningBolt(p.position, VFXUtil.WeaponColors.Thundercrown)
		end
	end,
	ThundercrownCrownIgnite = function(p)
		local root = rootOf(p.character)
		if root then
			-- Floating crown: three orbit sparks above the head for flavor
			lightningBolt(root.Position, VFXUtil.WeaponColors.Thundercrown)
			VFXUtil.Shockwave(root.Position + Vector3.new(0, 4, 0), VFXUtil.WeaponColors.Thundercrown, 4, 0.5)
		end
	end,
	ThundercrownChainArc = function(p)
		if typeof(p.position) ~= "Vector3" then
			return
		end
		local radius = p.radius or 15
		for _ = 1, 3 do
			local angle = math.random() * math.pi * 2
			local target = p.position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (radius * (0.5 + math.random() * 0.5))
			lightningBolt(target, VFXUtil.WeaponColors.Thundercrown)
		end
	end,
}

-- Fallback: any Frostveil/Voidneedle/Thundercrown fx name gets a generic
-- recolored effect until authored VFX land (weeks 5-6 of the roadmap).
local function genericWeaponFX(fxName: string, payload: any)
	local color = Color3.fromRGB(200, 220, 255)
	for weaponId, weaponColor in VFXUtil.WeaponColors do
		if fxName:sub(1, #weaponId) == weaponId then
			color = weaponColor
			break
		end
	end
	local root = rootOf(payload.character) or rootOf(payload.victim)
	local position = root and root.Position or payload.position
	if typeof(position) == "Vector3" then
		if fxName:find("Charge") or fxName:find("Place") then
			VFXUtil.HitSpark(position, color)
		else
			VFXUtil.Shockwave(position, color, payload.radius or 8, 0.4)
		end
	end
end

function CombatClient.Init()
	local controllers = script.Parent
	CameraController = require(controllers:WaitForChild("CameraController"))
	UIController = require(controllers:WaitForChild("UIController"))

	Net.GetEvent("CombatFX").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.fx) ~= "string" then
			return
		end
		local handler = fxHandlers[payload.fx]
		if handler then
			local ok, err = pcall(handler, payload)
			if not ok then
				warn("[CombatClient] fx " .. payload.fx .. " errored: " .. tostring(err))
			end
		else
			genericWeaponFX(payload.fx, payload)
		end
	end)

	-- Clash state → camera + UI + input gate
	local InputController = require(controllers:WaitForChild("InputController"))
	Net.GetEvent("ClashState").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		local myCharacter = player.Character
		local involved = payload.a == myCharacter or payload.b == myCharacter

		if payload.phase == "Start" then
			if involved then
				InputController.SetClashActive(true)
				UIController.ShowClashPrompt(tostring(payload.mashKey), payload.duration)
			end
			local ra, rb = rootOf(payload.a), rootOf(payload.b)
			if ra and rb then
				local mid = (ra.Position + rb.Position) / 2
				VFXUtil.Shockwave(mid, Color3.fromRGB(255, 255, 255), 8, 0.5)
				CameraController.FrameClash(ra, rb, payload.duration)
			end
		elseif payload.phase == "Resolve" or payload.phase == "Tie" or payload.phase == "Abort" then
			InputController.SetClashActive(false)
			UIController.HideClashPrompt()
			CameraController.EndClash()
			if payload.phase ~= "Abort" then
				local ra = rootOf(payload.winner or payload.a)
				if ra then
					VFXUtil.Shockwave(ra.Position, Color3.fromRGB(255, 255, 255), 20, 0.8)
				end
				CameraController.Shake(1.5)
			end
		end
	end)

	-- Aura tiers on spawn (attribute-driven, set by the server)
	local function watchCharacter(character: Model)
		task.wait(1)
		local tier = character:GetAttribute("AuraTier")
		local weaponId = character:GetAttribute("EquippedWeapon")
		if typeof(tier) == "number" and tier > 0 and typeof(weaponId) == "string" then
			VFXUtil.ApplyAura(character, colorFor(weaponId), math.min(tier, 3))
		end
	end
	for _, otherPlayer in Players:GetPlayers() do
		otherPlayer.CharacterAdded:Connect(watchCharacter)
		if otherPlayer.Character then
			task.spawn(watchCharacter, otherPlayer.Character)
		end
	end
	Players.PlayerAdded:Connect(function(otherPlayer)
		otherPlayer.CharacterAdded:Connect(watchCharacter)
	end)
end

return CombatClient
