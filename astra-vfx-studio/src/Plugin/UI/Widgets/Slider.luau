--!strict
--[[
	Slider — horizontal track with thumb; click or drag on the track, or type into the value field.

		local opacity = Slider.new({
			value = 0.5, min = 0, max = 1,
			step = 0.05,                     -- optional snapping (nil = continuous, rounded to `precision`)
			precision = 2,
			showValue = true,                -- typed value field on the right (default true)
			host = host,                     -- { plugin, widget, root }; needed for click/drag
			onChange = function(value, final)
				-- final = false while dragging, true once on release (and for typed values)
			end,
			parent = row,
		})
		opacity:setValue(0.25)               -- display only, no callbacks

	Mouse handling uses UI/Input.drag (GuiObject.InputBegan + widget:GetRelativeMousePosition() per Heartbeat);
	the value maps from the rail's AbsolutePosition/AbsoluteSize (ControlKit.geometry).
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Input = require(script.Parent.Parent.Input)
local Kit = require(script.Parent.ControlKit)

export type Props = {
	value: number?,
	min: number?, -- default 0
	max: number?, -- default 1
	step: number?,
	precision: number?, -- default 2
	showValue: boolean?,
	valueWidth: number?, -- default 44
	host: Kit.Host?,
	size: UDim2?,
	enabled: boolean?,
	onChange: ((value: number, final: boolean) -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local Slider = {}
Slider.__index = Slider

type SliderData = {
	instance: Frame,
	hit: TextButton,
	rail: Frame,
	fill: Frame,
	thumb: Frame,
	box: TextBox?,
	_maid: any, -- Maid (any: generic Maid methods do not unify across modules in the old solver)
	_props: Props,
	_value: number,
	_min: number,
	_max: number,
	_step: number?,
	_precision: number,
	_enabled: boolean,
	_hovered: boolean,
	_dragging: boolean,
	_dragChanged: boolean,
	_focused: boolean,
	_focusText: string?, -- value box text when focus was gained
	_boxStroke: UIStroke?,
}

export type Slider = typeof(setmetatable({} :: SliderData, Slider))

local c = Theme.colors
local THUMB = 12

function Slider.new(props: Props): Slider
	local maid = Maid.new()
	local showValue = props.showValue ~= false
	local valueWidth = props.valueWidth or 44

	local root = Instance.new("Frame")
	root.Name = "Slider"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = props.size or UDim2.new(1, 0, 0, Theme.metrics.rowHeight)
	Kit.applyCommon(root, props :: any)
	maid:give(root)

	local hit = Instance.new("TextButton")
	hit.Name = "Track"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.BorderSizePixel = 0
	hit.Size = if showValue then UDim2.new(1, -(valueWidth + 6), 1, 0) else UDim2.fromScale(1, 1)
	hit.Selectable = false
	hit.Parent = root

	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.BackgroundColor3 = c.bg3
	rail.BorderSizePixel = 0
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.new(0, THUMB / 2, 0.5, 0)
	rail.Size = UDim2.new(1, -THUMB, 0, 4)
	Kit.corner(2).Parent = rail
	rail.Parent = hit

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = c.accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	Kit.corner(2).Parent = fill
	fill.Parent = rail

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.BackgroundColor3 = c.text
	thumb.BorderSizePixel = 0
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.fromScale(0, 0.5)
	thumb.Size = UDim2.fromOffset(THUMB, THUMB)
	Kit.corner(THUMB // 2).Parent = thumb
	Kit.stroke(c.bg0).Parent = thumb
	thumb.Parent = rail

	local box: TextBox? = nil
	local boxStroke: UIStroke? = nil
	if showValue then
		local b = Instance.new("TextBox")
		b.Name = "Value"
		b.BackgroundColor3 = c.bg2
		b.BorderSizePixel = 0
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.fromScale(1, 0)
		b.Size = UDim2.new(0, valueWidth, 1, 0)
		b.ClearTextOnFocus = false
		b.FontFace = Theme.fonts.regular
		b.TextSize = Theme.textSize.small
		b.TextColor3 = c.text
		b.TextXAlignment = Enum.TextXAlignment.Right
		b.PlaceholderText = ""
		b.Text = ""
		b.Selectable = false
		Kit.corner().Parent = b
		local s = Kit.stroke()
		s.Parent = b
		boxStroke = s
		Kit.padding(4, 6).Parent = b
		b.Parent = root
		box = b
	end

	local self = setmetatable({
		instance = root,
		hit = hit,
		rail = rail,
		fill = fill,
		thumb = thumb,
		box = box,
		_maid = maid,
		_props = props,
		_value = 0,
		_min = props.min or 0,
		_max = props.max or 1,
		_step = props.step,
		_precision = props.precision or 2,
		_enabled = props.enabled ~= false,
		_hovered = false,
		_dragging = false,
		_dragChanged = false,
		_focused = false,
		_focusText = nil :: string?,
		_boxStroke = boxStroke,
	}, Slider)
	self._value = self:_normalize(props.value or self._min, true)

	maid:give(hit.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	maid:give(hit.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))

	local host = props.host
	if host and host.widget then
		maid:give(Input.drag(host.widget, hit, {
			onPress = function(pos: Vector2, _mods: Input.Mods)
				if not self._enabled then
					return
				end
				self._dragging = true
				self._dragChanged = false
				self:_setFromPosition(pos)
				self:_refresh()
			end,
			onMove = function(pos: Vector2, _delta: Vector2, _mods: Input.Mods)
				if self._dragging then
					self:_setFromPosition(pos)
				end
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, _moved: boolean)
				if not self._dragging then
					return
				end
				self._dragging = false
				self:_refresh()
				if self._dragChanged and props.onChange then
					props.onChange(self._value, true)
				end
			end,
		}, { threshold = 1 }))
	end

	if box then
		maid:give(box.Focused:Connect(function()
			self._focused = true
			box.Text = Kit.format(self._value, self._precision)
			self._focusText = box.Text
			box.SelectionStart = 1
			box.CursorPosition = #box.Text + 1
			self:_refresh()
		end))
		maid:give(box.FocusLost:Connect(function(_enterPressed: boolean, input: InputObject?)
			self._focused = false
			-- leaving without typing commits nothing (the value may have changed externally meanwhile)
			local untouched = box.Text == self._focusText
			self._focusText = nil
			local escape = false
			if input ~= nil then
				local ok, key = pcall(function()
					return (input :: any).KeyCode
				end)
				escape = ok and key == Enum.KeyCode.Escape
			end
			local parsed = if escape or untouched then nil else Kit.evaluate(box.Text)
			if parsed ~= nil then
				local value = self:_normalize(parsed, false)
				if value ~= self._value then
					self._value = value
					self:_refresh()
					if props.onChange then
						props.onChange(value, true)
					end
				end
			end
			self:_refresh()
		end))
	end

	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

-- Clamps, optionally snaps to the step grid, and rounds.
function Slider._normalize(self: Slider, value: number, snap: boolean): number
	local lo, hi = math.min(self._min, self._max), math.max(self._min, self._max)
	local v = Kit.clamp(value, lo, hi)
	local decimals = self._precision
	local step = self._step
	if snap and step and step > 0 then
		v = self._min + math.round((v - self._min) / step) * step
		v = Kit.clamp(v, lo, hi)
		decimals = math.max(decimals, Kit.decimals(step))
	end
	v = Kit.round(v, decimals)
	if v == 0 then
		v = 0
	end
	return v
end

function Slider._fraction(self: Slider): number
	local range = self._max - self._min
	if range == 0 then
		return 0
	end
	return math.clamp((self._value - self._min) / range, 0, 1)
end

-- Maps a widget-space mouse position onto the rail and updates the value (fires onChange(value, false)).
function Slider._setFromPosition(self: Slider, pos: Vector2)
	local railPos, railSize = Kit.geometry(self.rail)
	local width = math.max(1, railSize.X)
	local frac = math.clamp((pos.X - railPos.X) / width, 0, 1)
	local value = self:_normalize(self._min + frac * (self._max - self._min), true)
	if value ~= self._value then
		self._value = value
		self._dragChanged = true
		self:_refresh()
		if self._props.onChange then
			self._props.onChange(value, false)
		end
	end
end

function Slider._refresh(self: Slider)
	local frac = self:_fraction()
	local enabled = self._enabled
	self.fill.Size = UDim2.fromScale(frac, 1)
	self.thumb.Position = UDim2.fromScale(frac, 0.5)
	self.fill.BackgroundColor3 = if enabled then c.accent else c.textMuted
	self.thumb.BackgroundColor3 = if not enabled
		then c.textMuted
		elseif self._dragging or self._hovered then c.accentHover
		else c.text
	self.rail.BackgroundColor3 = if self._hovered and enabled then c.bg4 else c.bg3
	self.instance.Interactable = enabled
	local box = self.box
	if box then
		box.TextEditable = enabled
		box.TextColor3 = if enabled then c.text else c.textMuted
		local text = Kit.format(self._value, self._precision)
		if not self._focused then
			box.Text = text
		elseif box.Text == self._focusText and box.Text ~= text then
			-- focused but not edited yet: follow external value changes (only real changes are written, rewriting
			-- the text of a focused TextBox can reset caret and selection)
			self._focusText = text
			box.Text = text
		end
		local stroke = self._boxStroke
		if stroke then
			stroke.Color = if self._focused then c.accent else c.border
		end
	end
end

-- Sets the value without firing callbacks.
function Slider.setValue(self: Slider, value: number)
	self._value = self:_normalize(value, false)
	self:_refresh()
end

function Slider.getValue(self: Slider): number
	return self._value
end

function Slider.setRange(self: Slider, min: number, max: number)
	self._min = min
	self._max = max
	self._value = self:_normalize(self._value, false)
	self:_refresh()
end

function Slider.isDragging(self: Slider): boolean
	return self._dragging
end

function Slider.setEnabled(self: Slider, enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self._hovered = false
	end
	self:_refresh()
end

function Slider.destroy(self: Slider)
	self._maid:clean()
end

return Slider
