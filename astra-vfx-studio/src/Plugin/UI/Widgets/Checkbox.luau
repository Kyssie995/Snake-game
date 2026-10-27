--!strict
--[[
	Checkbox — boolean toggle with an optional text label.

		local loop = Checkbox.new({
			value = true,
			text = "Schleife",
			onChange = function(checked, final) editor:setLoop(checked) end, -- final is always true
			parent = row,
		})
		loop:setValue(false)                 -- display only, no callbacks
		loop:setMixed(true)                  -- "–" for multi-selections with differing values

	The whole row (box + label) is one TextButton; Activated toggles.
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)
local Tooltip = require(script.Parent.Tooltip)

export type Props = {
	value: boolean?,
	text: string?,
	tooltip: string?,
	host: Kit.Host?,
	size: UDim2?, -- default: auto width × rowHeight
	enabled: boolean?,
	onChange: ((checked: boolean, final: boolean) -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local Checkbox = {}
Checkbox.__index = Checkbox

type CheckboxData = {
	instance: TextButton,
	box: Frame,
	mark: TextLabel,
	label: TextLabel?,
	_maid: any, -- Maid (any: generic Maid methods do not unify across modules in the old solver)
	_stroke: UIStroke,
	_props: Props,
	_value: boolean,
	_mixed: boolean,
	_enabled: boolean,
	_hovered: boolean,
}

export type Checkbox = typeof(setmetatable({} :: CheckboxData, Checkbox))

local c = Theme.colors
local BOX = 14

function Checkbox.new(props: Props): Checkbox
	local maid = Maid.new()
	local root = Instance.new("TextButton")
	root.Name = "Checkbox"
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Selectable = false
	if props.size then
		root.Size = props.size
	else
		root.Size = UDim2.fromOffset(BOX, Theme.metrics.rowHeight)
		root.AutomaticSize = Enum.AutomaticSize.X
	end
	Kit.applyCommon(root, props :: any)
	maid:give(root)

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.BackgroundColor3 = c.bg2
	box.BorderSizePixel = 0
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.Position = UDim2.fromScale(0, 0.5)
	box.Size = UDim2.fromOffset(BOX, BOX)
	Kit.corner(3).Parent = box
	local stroke = Kit.stroke(c.borderStrong)
	stroke.Parent = box
	box.Parent = root

	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.FontFace = Theme.fonts.bold
	mark.TextSize = Theme.textSize.small
	mark.TextColor3 = c.text
	mark.Text = ""
	mark.Parent = box

	local label: TextLabel? = nil
	if props.text and props.text ~= "" then
		local l = Instance.new("TextLabel")
		l.Name = "Label"
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(BOX + 8, 0)
		l.Size = UDim2.fromScale(0, 1)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.FontFace = Theme.fonts.regular
		l.TextSize = Theme.textSize.normal
		l.TextColor3 = c.text
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = props.text
		l.Parent = root
		label = l
	end

	local self = setmetatable({
		instance = root,
		box = box,
		mark = mark,
		label = label,
		_maid = maid,
		_stroke = stroke,
		_props = props,
		_value = props.value == true,
		_mixed = false,
		_enabled = props.enabled ~= false,
		_hovered = false,
	}, Checkbox)

	maid:give(root.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	maid:give(root.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))
	maid:give(root.Activated:Connect(function()
		self:toggle()
	end))
	if props.host and props.tooltip then
		maid:give(Tooltip.attach(props.host, root, props.tooltip))
	end

	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function Checkbox._refresh(self: Checkbox)
	local enabled = self._enabled
	local on = self._value and not self._mixed
	local filled = on or self._mixed
	if not enabled then
		self.box.BackgroundColor3 = if filled then c.bg4 else c.bg1
		self._stroke.Color = c.border
		self.mark.TextColor3 = c.textMuted
	else
		self.box.BackgroundColor3 = if on then c.accent elseif self._mixed then c.accentDim else c.bg2
		self._stroke.Color = if filled then c.accent elseif self._hovered then c.accent else c.borderStrong
		self.mark.TextColor3 = c.text
	end
	self.mark.Text = if self._mixed then "–" elseif on then "✓" else ""
	if self.label then
		self.label.TextColor3 = if enabled then c.text else c.textMuted
	end
	self.instance.Interactable = enabled
end

-- Flips the value as a click would (fires onChange(value, true)). Mixed becomes checked.
function Checkbox.toggle(self: Checkbox)
	if not self._enabled then
		return
	end
	self._value = if self._mixed then true else not self._value
	self._mixed = false
	self:_refresh()
	if self._props.onChange then
		self._props.onChange(self._value, true)
	end
end

-- Sets the value without firing callbacks.
function Checkbox.setValue(self: Checkbox, value: boolean)
	self._value = value == true
	self._mixed = false
	self:_refresh()
end

function Checkbox.getValue(self: Checkbox): boolean
	return self._value
end

function Checkbox.setMixed(self: Checkbox, mixed: boolean)
	self._mixed = mixed
	self:_refresh()
end

function Checkbox.setText(self: Checkbox, text: string)
	if self.label then
		self.label.Text = text
	end
end

function Checkbox.setEnabled(self: Checkbox, enabled: boolean)
	self._enabled = enabled
	self:_refresh()
end

function Checkbox.destroy(self: Checkbox)
	self._maid:clean()
end

return Checkbox
