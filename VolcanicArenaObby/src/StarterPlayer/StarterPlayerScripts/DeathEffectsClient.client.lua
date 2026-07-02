--[[
	DeathEffectsClient.client.lua
	--------------------------------------------------------------------
	WHERE THIS GOES:
	  StarterPlayer > StarterPlayerScripts > DeathEffectsClient (LocalScript)

	Client half of the cartoon death animation.  When the server's
	CartoonBurst module reaches the BOOM, it fires PlayDeathFX to all
	clients with the burst position.  This script then:

	  * Shakes the local camera (stronger the closer you are)
	  * Flashes a quick red comic "splat" vignette if it was YOUR burst
	  * Plays a local boom whose volume falls off with distance

	Also listens to CheckpointReached and pops a small "CHECKPOINT!"
	toast at the top of the screen.
--------------------------------------------------------------------]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Players           = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ObbyConfig"))
local D = Config.Death

local player  = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Config.Remotes.Folder)
local playDeathFX       = remotes:WaitForChild(Config.Remotes.PlayDeathFX)
local checkpointReached = remotes:WaitForChild(Config.Remotes.CheckpointReached)

local rng = Random.new()

--------------------------------------------------------------------
-- Screen GUI (red flash + checkpoint toast)
--------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VolcanicArenaFX"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local redFlash = Instance.new("Frame")
redFlash.Name = "RedFlash"
redFlash.Size = UDim2.fromScale(1, 1)
redFlash.BackgroundColor3 = Config.Colors.SplatRed
redFlash.BackgroundTransparency = 1
redFlash.BorderSizePixel = 0
redFlash.ZIndex = 10
redFlash.Parent = screenGui

local toast = Instance.new("TextLabel")
toast.Name = "CheckpointToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0.08, 0)
toast.Size = UDim2.fromScale(0.4, 0.07)
toast.BackgroundTransparency = 1
toast.Font = Enum.Font.FredokaOne
toast.TextScaled = true
toast.TextColor3 = Config.Colors.CheckpointOn
toast.TextStrokeTransparency = 0.3
toast.TextTransparency = 1
toast.Text = ""
toast.Parent = screenGui

--------------------------------------------------------------------
-- Camera shake
--------------------------------------------------------------------
local SHAKE_BINDING = "VolcanicArenaCameraShake"
local shakeActive = false

local function shakeCamera(magnitude)
	if shakeActive then
		RunService:UnbindFromRenderStep(SHAKE_BINDING)
	end
	shakeActive = true
	local elapsed = 0
	-- Bound AFTER the default camera update (priority Camera + 1) so
	-- our offset is applied on top of it and never overwritten.
	RunService:BindToRenderStep(SHAKE_BINDING, Enum.RenderPriority.Camera.Value + 1, function(dt)
		elapsed += dt
		if elapsed >= D.CameraShakeTime then
			RunService:UnbindFromRenderStep(SHAKE_BINDING)
			shakeActive = false
			return
		end
		-- Decaying random offset each frame
		local decay = 1 - (elapsed / D.CameraShakeTime)
		local strength = magnitude * decay
		local camera = workspace.CurrentCamera
		camera.CFrame = camera.CFrame * CFrame.new(
			rng:NextNumber(-strength, strength) * 0.25,
			rng:NextNumber(-strength, strength) * 0.25,
			0
		) * CFrame.Angles(
			math.rad(rng:NextNumber(-strength, strength)),
			math.rad(rng:NextNumber(-strength, strength)),
			math.rad(rng:NextNumber(-strength, strength) * 0.5)
		)
	end)
end

--------------------------------------------------------------------
-- BOOM handler
--------------------------------------------------------------------
playDeathFX.OnClientEvent:Connect(function(burstPosition)
	local camera = workspace.CurrentCamera
	local distance = (camera.CFrame.Position - burstPosition).Magnitude

	-- Shake scales down with distance; inaudible past ~150 studs
	local falloff = math.clamp(1 - distance / 150, 0, 1)
	if falloff > 0 then
		shakeCamera(D.CameraShakeMag * falloff)
	end

	-- Local boom (if configured) with distance-based volume
	if Config.Sounds.Boom ~= "" and falloff > 0 then
		local boom = Instance.new("Sound")
		boom.SoundId = Config.Sounds.Boom
		boom.Volume = falloff
		boom.PlaybackSpeed = rng:NextNumber(0.95, 1.1)
		boom.Parent = SoundService
		boom:Play()
		boom.Ended:Once(function() boom:Destroy() end)
	end

	-- Red comic flash only when it's the local player bursting
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - burstPosition).Magnitude < 8 then
		redFlash.BackgroundTransparency = 0.35
		TweenService:Create(redFlash, TweenInfo.new(
			0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out
		), { BackgroundTransparency = 1 }):Play()
	end
end)

--------------------------------------------------------------------
-- Checkpoint toast
--------------------------------------------------------------------
checkpointReached.OnClientEvent:Connect(function(order)
	toast.Text = order >= 99 and "FINAL CHECKPOINT!" or ("CHECKPOINT " .. order .. "!")
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.3
	toast.Position = UDim2.new(0.5, 0, 0.06, 0)
	TweenService:Create(toast, TweenInfo.new(
		0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out
	), { Position = UDim2.new(0.5, 0, 0.08, 0) }):Play()
	task.delay(1.6, function()
		TweenService:Create(toast, TweenInfo.new(0.5), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end)
end)
