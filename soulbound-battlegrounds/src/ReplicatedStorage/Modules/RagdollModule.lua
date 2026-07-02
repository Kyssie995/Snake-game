--!strict
-- RagdollModule: physics knockback + temporary ragdoll with recovery.
-- Server-only. Works on R6 and R15 by swapping Motor6Ds for BallSockets.

local Debris = game:GetService("Debris")
local Constants = require(script.Parent.CombatConstants)

local RagdollModule = {}

local active: { [Model]: boolean } = {}

local function setRagdollJoints(character: Model, enabled: boolean)
	for _, desc in character:GetDescendants() do
		if desc:IsA("Motor6D") and desc.Part1 and desc.Part1.Name ~= "HumanoidRootPart" then
			if enabled then
				local socket = Instance.new("BallSocketConstraint")
				local a0 = Instance.new("Attachment")
				local a1 = Instance.new("Attachment")
				a0.CFrame = desc.C0
				a1.CFrame = desc.C1
				a0.Parent = desc.Part0
				a1.Parent = desc.Part1
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.Name = "RagdollSocket"
				socket.Parent = desc.Parent
				desc.Enabled = false
			end
		end
	end
	if not enabled then
		for _, desc in character:GetDescendants() do
			if desc:IsA("BallSocketConstraint") and desc.Name == "RagdollSocket" then
				if desc.Attachment0 then desc.Attachment0:Destroy() end
				if desc.Attachment1 then desc.Attachment1:Destroy() end
				desc:Destroy()
			elseif desc:IsA("Motor6D") then
				desc.Enabled = true
			end
		end
	end
end

function RagdollModule.IsRagdolled(character: Model): boolean
	return active[character] == true
end

-- Knock a character back with ragdoll physics.
-- direction should be a unit vector; speed in studs/second.
function RagdollModule.Knockback(character: Model, direction: Vector3, speed: number, duration: number?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if active[character] then
		return
	end
	active[character] = true

	local ragdollTime = duration or 1.0
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	setRagdollJoints(character, true)

	-- Upward bias makes knockback arcs look better and clears ground friction
	local velocity = (direction.Unit * speed) + Vector3.new(0, speed * 0.35, 0)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.MaxForce = 1e5
	lv.VectorVelocity = velocity
	lv.Parent = root
	Debris:AddItem(lv, 0.15) -- brief impulse, then pure physics
	Debris:AddItem(attachment, 0.15)

	-- Tag the root so DestructionService can detect wall impacts
	character:SetAttribute("RagdollFlying", true)

	task.delay(ragdollTime, function()
		character:SetAttribute("RagdollFlying", false)
		-- Recovery: wait until roughly grounded/slow, then stand up
		local t0 = os.clock()
		while os.clock() - t0 < 3 do
			if root.Parent == nil or humanoid.Health <= 0 then
				break
			end
			if root.AssemblyLinearVelocity.Magnitude < 8 then
				break
			end
			task.wait(0.1)
		end
		task.wait(Constants.STUN.RAGDOLL_RECOVERY)
		if character.Parent and humanoid.Health > 0 then
			setRagdollJoints(character, false)
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		active[character] = nil
	end)
end

-- Pop a target straight up for air combos.
function RagdollModule.AirLaunch(character: Model, upSpeed: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	root.AssemblyLinearVelocity = Vector3.new(
		root.AssemblyLinearVelocity.X * 0.2,
		upSpeed,
		root.AssemblyLinearVelocity.Z * 0.2
	)
end

function RagdollModule.Cleanup(character: Model)
	active[character] = nil
end

return RagdollModule
