--!strict
--[[
	AstraVFXDemo (Script in ServerScriptService) — ASTRA VFX Studio example, see examples/README.md.

	Server-authoritative gameplay, cosmetic client rendering:
	  * Every INTERVAL seconds the server casts an "attack" at the part named "VFXTarget" (else at the origin).
	  * The visual is only a message: Net.PlayAll sends the effect name and a CFrame, every client plays the effect
	    locally (AstraVFXClient.client.luau calls Net.Listen()). The server builds no VFX instances at all.
	  * The gameplay consequence (damage) runs on the server's OWN clock, IMPACT_DELAY seconds after the cast. It
	    never waits for, or depends on, the effect: a client with low quality, a dropped message or an effect that
	    is streamed out cannot change who gets hurt or when.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The cast only exists for the static type checker, which cannot follow requires through services.
local AstraVFX = require(ReplicatedStorage:WaitForChild("AstraVFX")) :: any
local Net = AstraVFX.Net

local EFFECT = "VioletImpact" -- effects/VioletImpact.vfx.json, synced into ReplicatedStorage.AstraVFX.Effects
local INTERVAL = 4 -- seconds between casts
local IMPACT_DELAY = 0.6 -- seconds from cast to damage; gameplay timing chosen by the server
local DAMAGE = 10
local DAMAGE_RADIUS = 10 -- studs

-- Creates the RemoteEvents (ReplicatedStorage.AstraVFX.AstraVFXNet) before the first client listens.
Net.Init()

if not AstraVFX.IsRegistered(EFFECT) then
	warn("[AstraVFXDemo] effect " .. EFFECT .. " is not registered (missing in ReplicatedStorage.AstraVFX.Effects?)")
end

-- Where the attack happens: the part "VFXTarget" in Workspace, or the world origin.
local function targetCFrame(): CFrame
	local target = workspace:FindFirstChild("VFXTarget")
	if target ~= nil and target:IsA("BasePart") then
		return target.CFrame
	end
	return CFrame.identity
end

-- Gameplay: damages every character whose root part is within DAMAGE_RADIUS of `position`.
local function applyDamage(position: Vector3)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid ~= nil and root ~= nil and root:IsA("BasePart") then
				if (root.Position - position).Magnitude <= DAMAGE_RADIUS then
					humanoid:TakeDamage(DAMAGE)
				end
			end
		end
	end
end

local function cast()
	local origin = targetCFrame()
	-- Cosmetic: every client renders the effect itself. Reliable by default; pass Unreliable = true for
	-- replaceable spam effects (may be dropped, see docs/RUNTIME_API.md).
	Net.PlayAll(EFFECT, { CFrame = origin })
	-- Gameplay: an independent server timer, not an effect event.
	task.delay(IMPACT_DELAY, applyDamage, origin.Position)
end

while true do
	task.wait(INTERVAL)
	cast()
end
