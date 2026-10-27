--!strict
-- Wurzel-ModuleScript des Fixture-Projekts (Verzeichnis mit init.luau = ModuleScript "src").
local Config = require(script.Shared.Config)
local Effects = require(script.Effects)
local Types = require(script.Shared.Types)

local Fixture = {}

function Fixture.play(target: BasePart): Types.EffectHandle
	local handle = Effects.spawnSparks(target, Config.DefaultRate)
	return handle
end

function Fixture.version(): string
	return Config.Version
end

return Fixture
