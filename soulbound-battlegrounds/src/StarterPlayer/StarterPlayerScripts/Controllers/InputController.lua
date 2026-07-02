--!strict
-- InputController: translates keyboard/mouse/touch into intent remotes.
-- Sends ONLY intents — the server decides everything.
-- PC bindings: LMB = M1 (hold = charged heavy) · F = block · Q = Soul Dash
-- 1-4 = abilities · G = Final Release · E = clash mash (when prompted)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Modules.Net)
local Constants = require(ReplicatedStorage.Modules.CombatConstants)

local InputController = {}

local player = Players.LocalPlayer
local combatRequest: RemoteEvent
local abilityRequest: RemoteEvent
local clashInput: RemoteEvent

local clashActive = false
function InputController.SetClashActive(active: boolean)
	clashActive = active
end

local m1DownAt: number? = nil
local HEAVY_HOLD_THRESHOLD = 0.35 -- hold LMB this long -> charged heavy

local function moveDirection(): Vector3
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		return humanoid.MoveDirection
	end
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.CFrame.LookVector or Vector3.zAxis
end

local function sendM1Release()
	if not m1DownAt then
		return
	end
	local held = os.clock() - m1DownAt
	m1DownAt = nil
	if held >= HEAVY_HOLD_THRESHOLD then
		combatRequest:FireServer({ action = "Heavy" })
	else
		-- Variant: holding Space at swing time = air-launch finisher intent
		local variant = UserInputService:IsKeyDown(Enum.KeyCode.Space) and "air" or nil
		combatRequest:FireServer({ action = "M1", variant = variant })
	end
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		m1DownAt = os.clock()
	elseif input.KeyCode == Enum.KeyCode.F then
		combatRequest:FireServer({ action = "BlockStart" })
	elseif input.KeyCode == Enum.KeyCode.Q then
		combatRequest:FireServer({ action = "Dash", direction = moveDirection() })
	elseif input.KeyCode == Enum.KeyCode.G then
		abilityRequest:FireServer({ slot = 0 }) -- ultimate
	elseif input.KeyCode == Constants.CLASH.MASH_KEY and clashActive then
		clashInput:FireServer()
	elseif input.KeyCode == Enum.KeyCode.One then
		abilityRequest:FireServer({ slot = 1 })
	elseif input.KeyCode == Enum.KeyCode.Two then
		abilityRequest:FireServer({ slot = 2 })
	elseif input.KeyCode == Enum.KeyCode.Three then
		abilityRequest:FireServer({ slot = 3 })
	elseif input.KeyCode == Enum.KeyCode.Four then
		abilityRequest:FireServer({ slot = 4 })
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		sendM1Release()
	elseif input.KeyCode == Enum.KeyCode.F then
		combatRequest:FireServer({ action = "BlockEnd" })
	end
end

-- Touch controls (month-3 pass adds proper buttons; these bind the basics)
local function bindTouchButtons()
	if not UserInputService.TouchEnabled then
		return
	end
	ContextActionService:BindAction("TouchM1", function(_, state)
		if state == Enum.UserInputState.Begin then
			combatRequest:FireServer({ action = "M1" })
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:SetTitle("TouchM1", "Attack")

	ContextActionService:BindAction("TouchDash", function(_, state)
		if state == Enum.UserInputState.Begin then
			combatRequest:FireServer({ action = "Dash", direction = moveDirection() })
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:SetTitle("TouchDash", "Dash")

	ContextActionService:BindAction("TouchBlock", function(_, state)
		if state == Enum.UserInputState.Begin then
			combatRequest:FireServer({ action = "BlockStart" })
		elseif state == Enum.UserInputState.End then
			combatRequest:FireServer({ action = "BlockEnd" })
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:SetTitle("TouchBlock", "Block")

	for slot = 1, 4 do
		local actionName = "TouchAbility" .. slot
		ContextActionService:BindAction(actionName, function(_, state)
			if state == Enum.UserInputState.Begin then
				abilityRequest:FireServer({ slot = slot })
			end
			return Enum.ContextActionResult.Sink
		end, true)
		ContextActionService:SetTitle(actionName, tostring(slot))
	end
end

function InputController.Init()
	combatRequest = Net.GetEvent("CombatRequest")
	abilityRequest = Net.GetEvent("AbilityRequest")
	clashInput = Net.GetEvent("ClashInput")

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	bindTouchButtons()
end

return InputController
