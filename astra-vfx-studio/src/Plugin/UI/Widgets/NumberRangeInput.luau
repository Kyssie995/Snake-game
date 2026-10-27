--!strict
--[[
	NumberRangeInput — Min/Max NumberInputs for NumberRange properties (Types.JsonNumberRange: n or [min, max]).
	The range stays ordered: raising Min above Max pushes Max up, lowering Max below Min pulls Min down, and
	external values with min > max are swapped. onChange always receives a fresh { min, max } array (Codec
	collapses equal ends to a plain number).

		local lifetime = NumberRangeInput.new({
			value = { 0.5, 1.2 },                 -- or a plain number, or a NumberRange
			min = 0, step = 0.05, precision = 2, host = host,
			onChange = function(range, final) ... end,
			parent = row,
		})
		lifetime:setValue(2)                      -- shows 2 .. 2 (display only)
]]

local Theme = require(script.Parent.Parent.Theme)
local Vector3Input = require(script.Parent.Vector3Input)

local NumberRangeInput = {}

export type Props = Vector3Input.Props
export type NumberRangeInput = Vector3Input.VectorInput

NumberRangeInput.AXES = {
	{ label = "Min", color = Theme.colors.textDim },
	{ label = "Max", color = Theme.colors.textDim },
} :: { Vector3Input.Axis }

-- Keeps values[1] <= values[2]. changedIndex 0 = value set from outside.
function NumberRangeInput.constrain(values: { number }, changedIndex: number): { number }
	local lo, hi = values[1], values[2]
	if lo <= hi then
		return values
	end
	if changedIndex == 1 then
		return { lo, lo }
	elseif changedIndex == 2 then
		return { hi, hi }
	end
	return { hi, lo }
end

function NumberRangeInput.new(props: Props): NumberRangeInput
	if props.name == nil then
		props = table.clone(props)
		props.name = "NumberRangeInput"
	end
	return Vector3Input.group(props, NumberRangeInput.AXES, NumberRangeInput.constrain)
end

return NumberRangeInput
