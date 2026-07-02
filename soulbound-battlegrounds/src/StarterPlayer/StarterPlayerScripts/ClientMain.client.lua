--!strict
-- ClientMain: boots all client controllers.

local controllers = script.Parent:WaitForChild("Controllers")

local initOrder = {
	"UIController",
	"CameraController",
	"CombatClient",
	"InputController",
}

for _, name in initOrder do
	local module = require(controllers:WaitForChild(name))
	local ok, err = pcall(module.Init)
	if not ok then
		warn("[Soulbound] client controller " .. name .. " failed: " .. tostring(err))
	end
end
