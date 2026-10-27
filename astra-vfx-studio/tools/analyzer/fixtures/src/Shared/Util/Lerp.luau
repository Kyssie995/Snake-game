--!strict
-- Kind von Util; geht ueber script.Parent.Parent zu Shared/Config.
local Config = require(script.Parent.Parent.Config)

local Lerp = {}

function Lerp.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Lerp.fade(t: number): number
	return Lerp.lerp(0, 1, t / Config.FadeTime)
end

return Lerp
