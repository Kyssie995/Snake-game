--!strict
--[[
	AstraVFXClient (LocalScript in StarterPlayerScripts) — ASTRA VFX Studio example, see examples/README.md.

	  * Net.Listen(): plays every effect the server sends (AstraVFXDemo.server.luau -> Net.PlayAll).
	  * Key F: plays "FireExplosion" locally at the mouse hit position. Only this player sees it — a purely local,
	    cosmetic effect (e.g. instant feedback). Effects everybody must see are started by the server.
	  * The effect's marker event "Impact" (handle.Event) gives a short camera FOV kick.
	  * Key G: plays "VioletImpact" attached to the character (Attach + Offset): the effect follows the
	    HumanoidRootPart every frame.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- The effect definitions (ReplicatedStorage.AstraVFX.Effects) must have replicated before the first lookup.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- The cast only exists for the static type checker, which cannot follow requires through services.
local AstraVFX = require(ReplicatedStorage:WaitForChild("AstraVFX")) :: any

local EXPLOSION = "FireExplosion" -- examples/Effects/FireExplosion.vfx.json (marker event "Impact")
local ATTACHED = "VioletImpact" -- effects/VioletImpact.vfx.json
local MAX_DISTANCE = 1000 -- studs for the mouse ray
local KICK_FOV = 6 -- degrees added to the field of view on "Impact"
local KICK_TIME = 0.3 -- seconds back to the normal field of view

local player = Players.LocalPlayer

-- 1. Server -> client replication. Idempotent and non-yielding; waits for the remotes by itself.
AstraVFX.Net.Listen()

-- 2. Optional warm-up: builds pooled copies now, so the first key press only re-parents a ready copy.
AstraVFX.Preload(EXPLOSION, { Count = 2 })

-- World position under the mouse (raycast from the camera), ignoring the own character.
local function mouseHitPosition(): Vector3?
	local camera: Camera? = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	params.FilterDescendantsInstances = if character ~= nil then { character } else {}
	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_DISTANCE, params)
	if result == nil then
		return nil
	end
	return result.Position
end

-- Short field-of-view kick; a new tween on the same property replaces a running one.
local restFov: number? = nil
local function cameraKick()
	local camera: Camera? = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local rest = restFov or camera.FieldOfView
	restFov = rest
	camera.FieldOfView = rest + KICK_FOV
	local info = TweenInfo.new(KICK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(camera, info, { FieldOfView = rest }):Play()
end

local function playExplosion()
	local position = mouseHitPosition()
	if position == nil then
		return
	end
	-- TryPlay returns (nil, message) instead of raising, e.g. when the effect is not registered.
	local handle, err = AstraVFX.TryPlay(EXPLOSION, { Position = position })
	if handle == nil then
		warn("[AstraVFXClient] " .. tostring(err))
		return
	end
	-- Marker / component / graph "fire" events of this playing copy. (Alternative: the OnEvent play option.)
	handle.Event:Connect(function(name: string)
		if name == "Impact" then
			cameraKick()
		end
	end)
end

local function playAttached()
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end
	-- Follows the root part every frame; 6 studs in front of the character (-Z is forward), at 40 % size.
	-- If the character is removed while the effect plays, it stays at the last position and finishes there.
	AstraVFX.Play(ATTACHED, { Attach = root, Offset = CFrame.new(0, 0, -6), Scale = 0.4 })
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return -- typing in a TextBox, chat, ...
	end
	if input.KeyCode == Enum.KeyCode.F then
		playExplosion()
	elseif input.KeyCode == Enum.KeyCode.G then
		playAttached()
	end
end)
