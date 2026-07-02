--!strict
-- Main: server bootstrap. Initializes services in dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Modules.Net)

-- 1. Remotes must exist before anything touches them
Net.Init()

-- 2. Services (order matters: data -> progression -> combat -> everything else)
local Services = ServerScriptService.Services

local initOrder = {
	"DataService",
	"ProgressionService",
	"CombatService",
	"AbilityService",
	"SoulClashService",
	"SpiritEchoService",
	"DestructionService",
	"TrainingDummyService",
	"AdminService",
}

for _, name in initOrder do
	local module = require(Services:FindFirstChild(name))
	local ok, err = pcall(module.Init)
	if ok then
		print("[Soulbound] " .. name .. " initialized")
	else
		warn("[Soulbound] " .. name .. " FAILED to init: " .. tostring(err))
	end
end

print("[Soulbound] Server ready.")
