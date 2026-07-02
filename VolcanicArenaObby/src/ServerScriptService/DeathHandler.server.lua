--[[
	DeathHandler.server.lua
	--------------------------------------------------------------------
	WHERE THIS GOES:  ServerScriptService > DeathHandler (Script)

	The brain of the custom reset/death system:

	  * Creates the RemoteEvents in ReplicatedStorage > Remotes
	  * Registers the "CartoonDebris" collision group (so flying
	    chunks never push players around)
	  * Kills players who touch anything tagged "Lava"
	  * Listens for the client's custom Reset button (RequestReset)
	  * Runs CartoonBurst.Play() and respawns at the last checkpoint

	Works together with:
	  ReplicatedStorage/Modules/CartoonBurst.lua   (the animation)
	  ServerScriptService/CheckpointService.server.lua (spawn points)
	  StarterPlayerScripts/ResetButtonHook.client.lua  (reset button)
--------------------------------------------------------------------]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService    = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local Modules      = ReplicatedStorage:WaitForChild("Modules")
local Config       = require(Modules:WaitForChild("ObbyConfig"))
local CartoonBurst = require(Modules:WaitForChild("CartoonBurst"))

-- We own the whole spawn/respawn cycle, so turn off Roblox's automatic
-- respawn (it would double-spawn characters mid-animation).
Players.CharacterAutoLoads = false

--------------------------------------------------------------------
-- RemoteEvents  (created here so nothing has to be made by hand)
--------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = Config.Remotes.Folder
	remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end

ensureRemote(Config.Remotes.PlayDeathFX)
local requestReset      = ensureRemote(Config.Remotes.RequestReset)
local checkpointReached = ensureRemote(Config.Remotes.CheckpointReached) -- used by CheckpointService

--------------------------------------------------------------------
-- Collision group: debris chunks collide with the map, not players
--------------------------------------------------------------------
pcall(function()
	PhysicsService:RegisterCollisionGroup("CartoonDebris")
	PhysicsService:RegisterCollisionGroup("Players")
	PhysicsService:CollisionGroupSetCollidable("CartoonDebris", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("CartoonDebris", "CartoonDebris", false)
end)

local function setCharacterCollisionGroup(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end)
end

--------------------------------------------------------------------
-- The kill pipeline
--------------------------------------------------------------------
local KILL_COOLDOWN = 1 -- seconds; blocks double-triggers & remote spam
local dyingPlayers = {} -- [player] = true while the animation runs

local function respawnAtCheckpoint(player)
	dyingPlayers[player] = nil
	if player.Parent ~= Players then return end -- left mid-animation
	player:LoadCharacter()
	-- CheckpointService.server.lua moves the new character to the
	-- player's last checkpoint from its own CharacterAdded hook.
end

local function killPlayer(player)
	if dyingPlayers[player] then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end

	dyingPlayers[player] = true

	-- Keep Roblox's default ragdoll/death from firing mid-animation
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.BreakJointsOnDeath = false

	CartoonBurst.Play(character, function()
		respawnAtCheckpoint(player)
	end)

	-- Safety net: if anything errors inside the animation, still
	-- respawn so the player is never soft-locked.
	task.delay(Config.Death.FreezeTime + Config.Death.ShakeTime
		+ Config.Death.RespawnDelay + 3, function()
		if dyingPlayers[player] then
			respawnAtCheckpoint(player)
		end
	end)
end

--------------------------------------------------------------------
-- Triggers
--------------------------------------------------------------------

-- 1) Lava (any BasePart tagged "Lava" — MapBuilder tags the ocean)
local function hookLavaPart(lavaPart)
	lavaPart.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			killPlayer(player)
		end
	end)
end
for _, lavaPart in ipairs(CollectionService:GetTagged("Lava")) do
	hookLavaPart(lavaPart)
end
CollectionService:GetInstanceAddedSignal("Lava"):Connect(hookLavaPart)

-- 2) Custom Reset button (client fires RequestReset; validate server-side)
local lastReset = {}
requestReset.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastReset[player] and now - lastReset[player] < KILL_COOLDOWN then
		return -- ignore spam
	end
	lastReset[player] = now
	killPlayer(player)
end)

-- 3) Any other damage source (falling out of world, etc.):
--    catch Died in case something kills the humanoid directly.
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setCharacterCollisionGroup(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			if not dyingPlayers[player] then
				-- Default death slipped through — still give it the
				-- cartoon treatment before respawning.
				killPlayer(player)
			end
		end)
	end)

	-- CharacterAutoLoads is off, so spawn the first character ourselves
	player:LoadCharacter()
end)

Players.PlayerRemoving:Connect(function(player)
	dyingPlayers[player] = nil
	lastReset[player] = nil
end)
