--[[
	CheckpointService.server.lua
	--------------------------------------------------------------------
	WHERE THIS GOES:  ServerScriptService > CheckpointService (Script)

	Checkpoint system for the Volcanic Arena Obby.

	HOW CHECKPOINTS WORK:
	  * Any BasePart tagged "Checkpoint" (CollectionService tag) with a
	    number attribute "Order" is a checkpoint pad.  MapBuilder
	    creates these for you; to add your own, tag any part
	    "Checkpoint" and give it an Order attribute (1, 2, 3, ...).
	  * Touching a pad with a HIGHER Order than your current one
	    claims it: the pad flashes green, a ping plays, and the client
	    gets a CheckpointReached event for UI.
	  * The player's progress is stored as the attribute
	    "CheckpointOrder" on the Player, and the respawn CFrame is
	    cached here on the server.
	  * After DeathHandler calls player:LoadCharacter(), this script's
	    CharacterAdded hook teleports the fresh character to the last
	    claimed checkpoint.
--------------------------------------------------------------------]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ObbyConfig"))

-- [player] = CFrame of last claimed checkpoint (above the pad)
local respawnCFrames = {}

local function getCheckpointReachedRemote()
	local remotes = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, 10)
	return remotes and remotes:WaitForChild(Config.Remotes.CheckpointReached, 10)
end

--------------------------------------------------------------------
-- Claiming checkpoints
--------------------------------------------------------------------
local function flashPad(pad)
	local originalColor = pad.Color
	pad.Color = Config.Colors.CheckpointOn
	local light = Instance.new("PointLight")
	light.Color = Config.Colors.CheckpointOn
	light.Brightness = 4
	light.Range = 14
	light.Parent = pad
	TweenService:Create(light, TweenInfo.new(1.2), { Brightness = 0 }):Play()
	Debris:AddItem(light, 1.3)
	task.delay(1.2, function()
		-- Stay green once claimed by anyone (obby convention);
		-- change this line to `pad.Color = originalColor` if you
		-- prefer pads to reset.
		pad.Color = Config.Colors.CheckpointOn:Lerp(originalColor, 0.35)
	end)
end

local function playPing(pad)
	if Config.Sounds.Checkpoint == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.Checkpoint
	sound.Volume = 0.7
	sound.Parent = pad
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function onCheckpointTouched(pad, hit)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then return end

	local order = pad:GetAttribute("Order")
	if typeof(order) ~= "number" then return end

	local current = player:GetAttribute("CheckpointOrder") or 0
	if order <= current then return end -- only ever move forward

	player:SetAttribute("CheckpointOrder", order)
	respawnCFrames[player] = pad.CFrame + Vector3.new(0, 4, 0)

	flashPad(pad)
	playPing(pad)

	local remote = getCheckpointReachedRemote()
	if remote then
		remote:FireClient(player, order)
	end
end

local function hookCheckpoint(pad)
	pad.Touched:Connect(function(hit)
		onCheckpointTouched(pad, hit)
	end)
end

for _, pad in ipairs(CollectionService:GetTagged("Checkpoint")) do
	hookCheckpoint(pad)
end
CollectionService:GetInstanceAddedSignal("Checkpoint"):Connect(hookCheckpoint)

--------------------------------------------------------------------
-- Respawning at the last checkpoint
--------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("CheckpointOrder", 0)

	player.CharacterAdded:Connect(function(character)
		local savedCFrame = respawnCFrames[player]
		if not savedCFrame then return end -- no checkpoint yet: normal spawn

		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root then
			-- Wait one frame so the default spawn placement finishes
			task.wait()
			character:PivotTo(savedCFrame)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	respawnCFrames[player] = nil
end)
