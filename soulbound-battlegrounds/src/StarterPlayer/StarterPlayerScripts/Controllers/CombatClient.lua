--!strict
-- CombatClient: receives CombatFX broadcasts and plays visuals locally.
-- Adding a weapon = add its fx cases here (or a per-weapon VFX module later).
-- Nothing in this file affects gameplay — it is pure presentation.

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
