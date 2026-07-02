--!strict
-- CameraController: shake, FOV punches, ultimate push-in, Soul Clash framing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CameraController = {}

local camera = workspace.CurrentCamera
local BASE_FOV = 70

local shakeIntensity = 0
local clashConnection: RBXScriptConnection? = nil

function CameraController.Shake(intensity: number)
	shakeIntensity = math.max(shakeIntensity, intensity)
end

function CameraController.FOVPunch(delta: number, duration: number)
	local tween = TweenService:Create(camera, TweenInfo.new(duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = BASE_FOV + delta,
	})
	tween:Play()
	tween.Completed:Connect(function()
		TweenService:Create(camera, TweenInfo.new(duration / 2), { FieldOfView = BASE_FOV }):Play()
	end)
end

-- Ultimate activation: zoom-in punch that recovers over the activation time
function CameraController.UltimatePush(duration: number)
	CameraController.FOVPunch(-18, duration)
	CameraController.Shake(1.2)
end

-- Soul Clash: side-on cinematic framing of both fighters
function CameraController.FrameClash(rootA: BasePart, rootB: BasePart, duration: number)
	CameraController.EndClash()
	camera.CameraType = Enum.CameraType.Scriptable
	local startTime = os.clock()
	clashConnection = RunService.RenderStepped:Connect(function()
		if os.clock() - startTime > duration + 0.5 or not rootA.Parent or not rootB.Parent then
			CameraController.EndClash()
			return
		end
		local mid = (rootA.Position + rootB.Position) / 2
		local axis = (rootB.Position - rootA.Position)
		if axis.Magnitude < 0.01 then
			return
		end
		local side = axis.Unit:Cross(Vector3.yAxis)
		local distance = math.max(axis.Magnitude * 1.6, 14)
		-- Slight slow orbit for drama
		local t = (os.clock() - startTime) * 0.15
		local offset = (side * math.cos(t) + axis.Unit * math.sin(t) * 0.3).Unit * distance
		camera.CFrame = CFrame.lookAt(mid + offset + Vector3.new(0, 4, 0), mid)
	end)
end

function CameraController.EndClash()
	if clashConnection then
		clashConnection:Disconnect()
		clashConnection = nil
	end
	camera.CameraType = Enum.CameraType.Custom
end

function CameraController.Init()
	camera.FieldOfView = BASE_FOV
	-- Shake decay loop. Must run AFTER the default camera scripts write
	-- camera.CFrame each frame, or the offset gets overwritten — hence
	-- BindToRenderStep at Camera priority + 1 instead of .RenderStepped.
	RunService:BindToRenderStep("SoulboundCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if shakeIntensity > 0.01 then
			local offset = Vector3.new(
				(math.random() - 0.5) * shakeIntensity,
				(math.random() - 0.5) * shakeIntensity,
				0
			) * 0.5
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			shakeIntensity *= math.exp(-6 * dt) -- smooth decay
		else
			shakeIntensity = 0
		end
	end)
end

return CameraController
