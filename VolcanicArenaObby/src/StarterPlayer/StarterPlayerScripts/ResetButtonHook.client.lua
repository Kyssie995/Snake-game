--[[
	ResetButtonHook.client.lua
	--------------------------------------------------------------------
	WHERE THIS GOES:
	  StarterPlayer > StarterPlayerScripts > ResetButtonHook (LocalScript)

	Replaces Roblox's default Reset Character button (Esc menu) with
	our cartoon death animation.  When the player clicks Reset, instead
	of instantly killing the character, we fire the RequestReset
	RemoteEvent and let the server run CartoonBurst + checkpoint
	respawn.

	NOTE: SetCore("ResetButtonCallback") can throw if CoreGui hasn't
	finished loading, so we retry in a loop — this is the standard
	pattern recommended by Roblox.
--------------------------------------------------------------------]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ObbyConfig"))

local remotes      = ReplicatedStorage:WaitForChild(Config.Remotes.Folder)
local requestReset = remotes:WaitForChild(Config.Remotes.RequestReset)

-- The reset button fires this BindableEvent instead of killing us
local resetBindable = Instance.new("BindableEvent")
resetBindable.Event:Connect(function()
	requestReset:FireServer()
end)

-- Retry until CoreGui accepts the callback (can take a few frames)
task.spawn(function()
	local tries = 0
	while tries < 30 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", resetBindable)
		end)
		if ok then return end
		tries += 1
		task.wait(0.5)
	end
	warn("[VolcanicArena] Could not hook the reset button; default reset stays active.")
end)
