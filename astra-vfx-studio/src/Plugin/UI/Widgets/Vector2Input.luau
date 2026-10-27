--!strict
--[[
	Vector2Input — X/Y NumberInputs with coloured axis labels; values are JSON arrays { x, y } (Types.JsonVector2).
	Same API as Vector3Input (built with Vector3Input.group).

		local pos = Vector2Input.new({
			value = { 0.5, 0.5 }, step = 0.01, precision = 3, host = host,
			onChange = function(vector, final) ... end,          -- vector = { x, y }
			parent = row,
		})
		pos:setValue({ 0, 1 })                                    -- display only (also accepts a Vector2)
]]

local Theme = require(script.Parent.Parent.Theme)
local Vector3Input = require(script.Parent.Vector3Input)

local Vector2Input = {}

export type Props = Vector3Input.Props
export type Vector2Input = Vector3Input.VectorInput

Vector2Input.AXES = {
	{ label = "X", color = Theme.colors.error },
	{ label = "Y", color = Theme.colors.success },
} :: { Vector3Input.Axis }

function Vector2Input.new(props: Props): Vector2Input
	if props.name == nil then
		props = table.clone(props)
		props.name = "Vector2Input"
	end
	return Vector3Input.group(props, Vector2Input.AXES)
end

return Vector2Input
