--!strict
--[[
	Vector3Input — X/Y/Z NumberInputs side by side with coloured axis labels (X = error red, Y = success green,
	Z = loop blue from Theme). Values are JSON arrays { x, y, z } (Types.JsonVector3).

		local offset = Vector3Input.new({
			value = { 0, 2, 0 },
			step = 0.1, precision = 3, min = -1000, max = 1000,  -- applied to every axis
			host = host,                                        -- enables drag-scrubbing on the axis labels
			onChange = function(vector, final, axis)            -- vector is a fresh { x, y, z } array,
				if final then editor:transact("Offset", ...) end  -- axis the index that was edited (1..3)
			end,
			parent = row,
		})
		offset:setValue({ 1, 2, 3 })                            -- display only (also accepts a Vector3)
		offset:setMixed({ false, true, false })                 -- "—" on axes that differ in a multi-selection

	Each axis is a NumberInput (drag-scrub label + typed arithmetic). onChange(value, false) streams while
	scrubbing, onChange(value, true) once at the end and for typed values. The third argument is the edited axis
	index, so multi-selection editors can apply only that component (the other entries may be "mixed").

	Vector3Input.group(props, axes, constrain?) is the shared builder behind Vector2Input and NumberRangeInput:
	`axes` = { { label, color } }, `constrain(values, changedIndex) -> values` may adjust the other entries.
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)
local NumberInput = require(script.Parent.NumberInput)

local Vector3Input = {}
Vector3Input.__index = Vector3Input

export type Axis = { label: string, color: Color3? }

export type Props = {
	value: any?, -- { number } array (or Vector3 / Vector2 / NumberRange datatypes)
	min: number?,
	max: number?,
	step: number?,
	precision: number?,
	labels: { string }?, -- overrides the axis labels
	host: any?,
	enabled: boolean?,
	onChange: ((value: { number }, final: boolean, axis: number) -> ())?,
	spacing: number?, -- gap between fields (default 4)
	name: string?,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

export type Constrain = (values: { number }, changedIndex: number) -> { number }

type GroupData = {
	instance: Frame,
	fields: { any }, -- NumberInput widgets, one per axis
	maid: Maid.Maid,
	_props: Props,
	_values: { number },
	_constrain: Constrain?,
	_enabled: boolean,
	_destroyed: boolean,
}

export type VectorInput = typeof(setmetatable({} :: GroupData, Vector3Input))

Vector3Input.AXES = {
	{ label = "X", color = Theme.colors.error },
	{ label = "Y", color = Theme.colors.success },
	{ label = "Z", color = Theme.colors.loop },
} :: { Axis }

-- Converts arrays and Roblox datatypes into a fresh array of `n` numbers (missing entries = 0).
function Vector3Input.toArray(value: any, n: number): { number }
	local out = table.create(n, 0)
	local kind = typeof(value)
	if kind == "Vector3" then
		out[1], out[2], out[3] = value.X, value.Y, value.Z
	elseif kind == "Vector2" then
		out[1], out[2] = value.X, value.Y
	elseif kind == "NumberRange" then
		out[1], out[2] = value.Min, value.Max
	elseif kind == "number" then
		for i = 1, n do
			out[i] = value
		end
	elseif kind == "table" then
		for i = 1, n do
			local v = value[i]
			if type(v) == "number" then
				out[i] = v
			end
		end
	end
	return out
end

function Vector3Input.group(props: Props, axes: { Axis }, constrain: Constrain?): VectorInput
	local n = #axes
	local root = New("Frame", {
		Name = props.name or "VectorInput",
		Size = props.size or UDim2.new(1, 0, 0, Theme.metrics.rowHeight),
		Position = props.position or UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, props.spacing or 4),
		}),
	}) :: Frame

	local self = setmetatable({
		instance = root,
		fields = {},
		maid = Maid.new(),
		_props = props,
		_values = Vector3Input.toArray(props.value, n),
		_constrain = constrain,
		_enabled = props.enabled ~= false,
		_destroyed = false,
	}, Vector3Input)

	if constrain then
		self._values = constrain(self._values, 0)
	end

	for i, axis in axes do
		local label = if props.labels and props.labels[i] then props.labels[i] else axis.label
		local field = NumberInput.new({
			name = "Axis" .. label,
			label = label,
			labelColor = axis.color,
			value = self._values[i],
			min = props.min,
			max = props.max,
			step = props.step,
			precision = props.precision,
			host = props.host,
			enabled = props.enabled,
			layoutOrder = i,
			size = UDim2.new(0, 0, 1, 0),
			onChange = function(value: number, final: boolean)
				self:_axisChanged(i, value, final)
			end,
			parent = root,
		})
		New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = field.instance })
		self.fields[i] = field
		self.maid:give(field)
	end
	self._values = self:getValue() -- as clamped/rounded by the fields

	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function Vector3Input.new(props: Props): VectorInput
	return Vector3Input.group(props, Vector3Input.AXES)
end

function Vector3Input._axisChanged(self: VectorInput, index: number, value: number, final: boolean)
	local values = table.clone(self._values)
	values[index] = value
	if self._constrain then
		values = self._constrain(values, index)
		-- show adjusted partner values
		for i, v in values do
			if i ~= index and v ~= self._values[i] then
				self.fields[i]:setValue(v)
			end
		end
	end
	self._values = values
	if self._props.onChange then
		self._props.onChange(table.clone(values), final, index)
	end
end

-- Display only; accepts arrays or datatypes. No callbacks.
function Vector3Input.setValue(self: VectorInput, value: any)
	local values = Vector3Input.toArray(value, #self.fields)
	if self._constrain then
		values = self._constrain(values, 0)
	end
	for i, field in self.fields do
		field:setValue(values[i])
	end
	self._values = self:getValue()
end

-- Fresh array of the current values (as clamped/rounded by the fields).
function Vector3Input.getValue(self: VectorInput): { number }
	local out = {}
	for i, field in self.fields do
		out[i] = field:getValue()
	end
	return out
end

-- true/false for all axes or one boolean per axis.
function Vector3Input.setMixed(self: VectorInput, mixed: boolean | { boolean })
	for i, field in self.fields do
		local m = if type(mixed) == "table" then (mixed :: { boolean })[i] == true else mixed == true
		field:setMixed(m)
	end
end

function Vector3Input.setRange(self: VectorInput, min: number?, max: number?)
	for _, field in self.fields do
		field:setRange(min, max)
	end
end

function Vector3Input.setEnabled(self: VectorInput, enabled: boolean)
	self._enabled = enabled
	for _, field in self.fields do
		field:setEnabled(enabled)
	end
end

function Vector3Input.isDragging(self: VectorInput): boolean
	for _, field in self.fields do
		if field:isDragging() then
			return true
		end
	end
	return false
end

function Vector3Input.destroy(self: VectorInput)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.maid:clean()
	table.clear(self.fields)
	self.instance:Destroy()
end

return Vector3Input
