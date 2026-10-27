--!strict
-- Verzeichnis-Modul: Shared/Util ist ein ModuleScript, Lerp ist sein Kind.
local Lerp = require(script.Lerp)
local Legacy = require(script.Parent.Legacy)

local Util = {}

function Util.fadeSequence(from: number, to: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from),
		NumberSequenceKeypoint.new(0.5, Lerp.lerp(from, to, 0.5)),
		NumberSequenceKeypoint.new(1, to),
	})
end

Util.clamp01 = Legacy.clamp01

return Util
