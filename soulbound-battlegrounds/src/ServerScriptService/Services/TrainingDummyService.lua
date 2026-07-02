--!strict
-- TrainingDummyService: rigs tagged "TrainingDummy" get HP, register with the
-- combat pipeline (so all moves work on them), award capped XP, and reset a
-- few seconds after "dying".
--
-- Map setup: place R15/R6 rigs (with Humanoid) and tag the Model
-- "TrainingDummy". Optional attribute DummyMode: "Static" | "Blocking".

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Modules.CombatConstants)

local CombatService = require(script.Parent.CombatService)

local TrainingDummyService = {}

local TAG = "TrainingDummy"
local RESET_TIME = 4

local function setupDummy(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	model:SetAttribute("IsTrainingDummy", true)
	humanoid.MaxHealth = Constants.MAX_HEALTH
	humanoid.Health = Constants.MAX_HEALTH
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = 0

	local homeCFrame = root.CFrame
	CombatService.RegisterNPC(model)

	-- "Blocking" dummies hold block so players can practice guard breaks
	if model:GetAttribute("DummyMode") == "Blocking" then
		local state = CombatService.GetState(model)
		if state then
			state.blocking = true
			model:SetAttribute("Blocking", true)
			-- Blocking dummies never run out of block HP
			task.spawn(function()
				while model.Parent do
					local s = CombatService.GetState(model)
					if s then
						s.blockHP = Constants.BLOCK.MAX_BLOCK_HP
						s.blocking = true
					end
					task.wait(1)
				end
			end)
		end
	end

	humanoid.HealthChanged:Connect(function(health)
		if health <= 0 then
			task.delay(RESET_TIME, function()
				if model.Parent then
					root.CFrame = homeCFrame
					root.AssemblyLinearVelocity = Vector3.zero
					humanoid.Health = humanoid.MaxHealth
					CombatService.RegisterNPC(model) -- fresh combat state
				end
			end)
		end
	end)
end

function TrainingDummyService.Init()
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("Model") then
			setupDummy(instance)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
		if instance:IsA("Model") then
			setupDummy(instance)
		end
	end)
end

return TrainingDummyService
