--!strict
-- .lua-Endung wird wie .luau behandelt.
local Legacy = {}

function Legacy.clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

return Legacy
