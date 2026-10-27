--!strict
-- Script (Server) im Root-Ordner, verwendet die Root-Module ueber script.Parent.
local Players = game:GetService("Players")
local Fixture = require(script.Parent)
local Spark = require(script.Parent.Effects.Spark)

local part = Instance.new("Part")
part.Anchored = true
part.Size = Vector3.new(2, 2, 2)
part.CFrame = CFrame.new(0, 5, 0)
part.Parent = workspace

local handle = Fixture.play(part)
handle.emitter.Rate = 50
Spark.flash(part)
print(Fixture.version(), #Players:GetPlayers(), game.ReplicatedStorage.Name)

local toolbar = plugin:CreateToolbar("Astra VFX")
local button = toolbar:CreateButton("Spark", "Spawn sparks", "rbxassetid://0")
button.Click:Connect(function()
	handle.stop()
end)
