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
			local ghost = Instance.new("Part")
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.Material = Enum.Material.ForceField
			ghost.Color = VFXUtil.WeaponColors.Frostveil
			ghost.Size = Vector3.new(2.4, 4.8, 1.4)
			ghost.CFrame = CFrame.new(root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius)
			ghost.Transparency = 0.4
			ghost.Parent = workspace
			TweenService:Create(ghost, TweenInfo.new(0.7), { Transparency = 1 }):Play()
			Debris:AddItem(ghost, 0.8)
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
