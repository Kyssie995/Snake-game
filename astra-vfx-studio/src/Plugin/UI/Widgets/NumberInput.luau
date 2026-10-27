--!strict
--[[
	NumberInput — number field with a drag-to-scrub label part and click-to-type value part.

		local rate = NumberInput.new({
			label = "Rate",                  -- scrub zone on the left (a slim grip when omitted)
			labelColor = Theme.colors.error, -- optional (e.g. X/Y/Z axis colours from Theme)
			value = 20, min = 0, max = 1000,
			step = 1,                        -- value change per scrubbed pixel (shift ×10, ctrl ×0.1)
			precision = 2,                   -- displayed/stored decimals (trailing zeros hidden)
			suffix = "/s",
			host = host,                     -- { plugin, widget, root }; needed for scrubbing
			onChange = function(value, final)
				-- final = false while scrubbing, true once at the end (and for typed values),
				-- so the editor can group one drag into one undo step.
				if final then editor:endGesture(true) else editor:updateGesture(value) end
			end,
			parent = row,
		})
		rate:setValue(42)                    -- display only, no callbacks

	Typing accepts arithmetic ("2*3", "1,5" with comma, "(4+2)/3"); invalid text and Escape revert. Values are
	clamped to [min, max] and rounded to `precision` decimals (scrubbing keeps the decimals of the effective step).
	Scrubbing polls widget:GetRelativeMousePosition() every Heartbeat (UI/Input.drag) because UserInputService does
	not work inside DockWidgets. Clicking the label part without dragging focuses the text field.
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Input = require(script.Parent.Parent.Input)
local Kit = require(script.Parent.ControlKit)
local Tooltip = require(script.Parent.Tooltip)

export type Props = {
	value: number?,
	min: number?,
	max: number?,
	step: number?, -- default 1 for precision 0, else 0.1
	precision: number?, -- default 2
	label: string?,
	labelColor: Color3?,
	labelWidth: number?,
	suffix: string?,
	pixelsPerStep: number?, -- default 1
	host: Kit.Host?,
	tooltip: string?,
	size: UDim2?,
	enabled: boolean?,
	onChange: ((value: number, final: boolean) -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local NumberInput = {}
NumberInput.__index = NumberInput

type NumberInputData = {
	instance: Frame,
	scrub: TextButton,
	box: TextBox,
	_maid: any, -- Maid (any: generic Maid methods do not unify across modules in the old solver)
	_stroke: UIStroke,
	_props: Props,
	_value: number,
	_min: number?,
	_max: number?,
	_step: number,
	_precision: number,
	_suffix: string,
	_mixed: boolean,
	_enabled: boolean,
	_focused: boolean,
	_hovered: boolean,
	_scrubHovered: boolean,
	_dragging: boolean,
	_dragStart: number,
	_dragChanged: boolean,
	_drag: Input.DragHandle?,
}

export type NumberInput = typeof(setmetatable({} :: NumberInputData, NumberInput))

local c = Theme.colors

local function defaultStep(precision: number): number
	if precision <= 0 then
		return 1
	end
	return 0.1
end

function NumberInput.new(props: Props): NumberInput
	local maid = Maid.new()
	local precision = props.precision or 2
	local labelText = props.label
	local labelWidth = props.labelWidth
		or (
			if labelText and labelText ~= ""
				then Kit.measure(labelText, Theme.textSize.small, nil, Kit.FONT_ENUM.medium).X + 14
				else 12
		)

	local root = Instance.new("Frame")
	root.Name = "NumberInput"
	root.BackgroundColor3 = c.bg2
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Size = props.size or UDim2.new(1, 0, 0, Theme.metrics.rowHeight)
	Kit.applyCommon(root, props :: any)
	Kit.corner().Parent = root
	local stroke = Kit.stroke()
	stroke.Parent = root
	maid:give(root)

	local scrub = Instance.new("TextButton")
	scrub.Name = "Scrub"
	scrub.AutoButtonColor = false
	scrub.BackgroundColor3 = c.bg3
	scrub.BackgroundTransparency = 1
	scrub.BorderSizePixel = 0
	scrub.Size = UDim2.new(0, labelWidth, 1, 0)
	scrub.FontFace = Theme.fonts.medium
	scrub.TextSize = Theme.textSize.small
	scrub.TextColor3 = props.labelColor or c.textDim
	scrub.TextTruncate = Enum.TextTruncate.AtEnd
	scrub.Text = labelText or ""
	scrub.Selectable = false
	scrub.Parent = root
	if labelText == nil or labelText == "" then
		-- slim grip: two short vertical bars
		for i = 0, 1 do
			local bar = Instance.new("Frame")
			bar.Name = "Grip"
			bar.BackgroundColor3 = c.textMuted
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.new(0.5, (i * 2 - 1) * 2, 0.5, 0)
			bar.Size = UDim2.fromOffset(1, 8)
			bar.Parent = scrub
		end
	end

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = c.border
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0, labelWidth - 1, 0, 0)
	divider.Size = UDim2.new(0, 1, 1, 0)
	divider.Parent = root

	local box = Instance.new("TextBox")
	box.Name = "Box"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Position = UDim2.fromOffset(labelWidth, 0)
	box.Size = UDim2.new(1, -labelWidth, 1, 0)
	box.ClearTextOnFocus = false
	box.MultiLine = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.FontFace = Theme.fonts.regular
	box.TextSize = Theme.textSize.normal
	box.TextColor3 = c.text
	box.PlaceholderColor3 = c.textMuted
	box.PlaceholderText = ""
	box.Text = ""
	box.Selectable = false
	Kit.padding(6, 6).Parent = box
	box.Parent = root

	local self = setmetatable({
		instance = root,
		scrub = scrub,
		box = box,
		_maid = maid,
		_stroke = stroke,
		_props = props,
		_value = 0,
		_min = props.min,
		_max = props.max,
		_step = props.step or defaultStep(precision),
		_precision = precision,
		_suffix = props.suffix or "",
		_mixed = false,
		_enabled = props.enabled ~= false,
		_focused = false,
		_hovered = false,
		_scrubHovered = false,
		_dragging = false,
		_dragStart = 0,
		_dragChanged = false,
		_drag = nil :: Input.DragHandle?,
	}, NumberInput)
	self._value = self:_normalize(props.value or 0, precision)

	-- typing
	maid:give(box.Focused:Connect(function()
		self._focused = true
		box.Text = if self._mixed then "" else Kit.format(self._value, self._precision)
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
		self:_refresh()
	end))
	maid:give(box.FocusLost:Connect(function(_enterPressed: boolean, input: InputObject?)
		self._focused = false
		local escape = false
		if input ~= nil then
			local ok, key = pcall(function()
				return (input :: any).KeyCode
			end)
			escape = ok and key == Enum.KeyCode.Escape
		end
		if not escape then
			self:_commitText(box.Text)
		end
		self:_refresh()
	end))

	-- hover visuals
	maid:give(root.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	maid:give(root.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))
	maid:give(scrub.MouseEnter:Connect(function()
		self._scrubHovered = true
		if self._enabled and props.host then
			Kit.setCursor(props.host, "SizeEW")
		end
		self:_refresh()
	end))
	maid:give(scrub.MouseLeave:Connect(function()
		self._scrubHovered = false
		if not self._dragging then
			Kit.setCursor(props.host, nil)
		end
		self:_refresh()
	end))

	-- scrubbing
	local host = props.host
	if host and host.widget then
		local drag = Input.drag(host.widget, scrub, {
			onStart = function(_pos: Vector2, _mods: Input.Mods)
				if not self._enabled then
					return
				end
				self._dragging = true
				self._dragStart = self._value
				self._dragChanged = false
				self:_refresh()
			end,
			onMove = function(_pos: Vector2, delta: Vector2, mods: Input.Mods)
				if not self._dragging then
					return
				end
				local factor = 1
				if mods.shift then
					factor *= 10
				end
				if mods.ctrl then
					factor *= 0.1
				end
				local stepEff = self._step * factor
				local steps = delta.X / (props.pixelsPerStep or 1)
				steps = if steps >= 0 then math.floor(steps) else math.ceil(steps)
				local decimals = math.max(self._precision, Kit.decimals(stepEff))
				local value = self:_normalize(self._dragStart + steps * stepEff, decimals)
				if value ~= self._value or self._mixed then
					self._value = value
					self._mixed = false
					self._dragChanged = true
					self:_display()
					if props.onChange then
						props.onChange(value, false)
					end
				end
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, moved: boolean)
				if not self._dragging then
					return
				end
				self._dragging = false
				if not self._scrubHovered then
					Kit.setCursor(props.host, nil)
				end
				self:_refresh()
				if moved and self._dragChanged and props.onChange then
					props.onChange(self._value, true)
				end
			end,
			onClick = function(_pos: Vector2, _mods: Input.Mods)
				self:focus()
			end,
		})
		self._drag = drag
		maid:give(drag)
	else
		maid:give(scrub.Activated:Connect(function()
			self:focus()
		end))
	end

	if host and props.tooltip then
		maid:give(Tooltip.attach(host, scrub, props.tooltip))
	end

	self:_display()
	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function NumberInput._normalize(self: NumberInput, value: number, decimals: number): number
	local v = Kit.round(value, decimals)
	v = Kit.clamp(v, self._min, self._max)
	if v == 0 then
		v = 0 -- no "-0"
	end
	return v
end

function NumberInput._display(self: NumberInput)
	if self._focused then
		return
	end
	if self._mixed then
		self.box.Text = "—"
	else
		self.box.Text = Kit.format(self._value, self._precision) .. self._suffix
	end
end

function NumberInput._refresh(self: NumberInput)
	local enabled = self._enabled
	local stroke = self._stroke
	if self._focused then
		stroke.Color = c.accent
	elseif (self._hovered or self._dragging) and enabled then
		stroke.Color = c.borderStrong
	else
		stroke.Color = c.border
	end
	self.instance.BackgroundColor3 = if enabled then c.bg2 else c.bg1
	self.instance.Interactable = enabled
	self.box.TextEditable = enabled
	self.box.TextColor3 = if enabled then (if self._mixed then c.textDim else c.text) else c.textMuted
	self.scrub.BackgroundTransparency = if enabled and (self._scrubHovered or self._dragging) then 0 else 1
	self.scrub.TextColor3 = if enabled then (self._props.labelColor or c.textDim) else c.textMuted
	self:_display()
end

function NumberInput._commitText(self: NumberInput, text: string)
	local raw = text
	if self._suffix ~= "" then
		local s = string.find(raw, self._suffix, 1, true)
		if s then
			raw = string.sub(raw, 1, s - 1) .. string.sub(raw, s + #self._suffix)
		end
	end
	local parsed = Kit.evaluate(raw)
	if parsed == nil then
		self:_display() -- revert
		return
	end
	local value = self:_normalize(parsed, self._precision)
	local changed = value ~= self._value or self._mixed
	self._value = value
	self._mixed = false
	self:_display()
	if changed and self._props.onChange then
		self._props.onChange(value, true)
	end
end

-- Sets the value without firing callbacks (clamped and rounded).
function NumberInput.setValue(self: NumberInput, value: number)
	self._value = self:_normalize(value, math.max(self._precision, Kit.decimals(value)))
	self._mixed = false
	self:_refresh()
end

function NumberInput.getValue(self: NumberInput): number
	return self._value
end

-- Shows "—" for multi-selections with differing values (typing or scrubbing sets a real value).
function NumberInput.setMixed(self: NumberInput, mixed: boolean)
	self._mixed = mixed
	self:_refresh()
end

function NumberInput.setRange(self: NumberInput, min: number?, max: number?)
	self._min = min
	self._max = max
	self._value = self:_normalize(self._value, math.max(self._precision, Kit.decimals(self._value)))
	self:_refresh()
end

function NumberInput.setStep(self: NumberInput, step: number)
	self._step = step
end

function NumberInput.isDragging(self: NumberInput): boolean
	return self._dragging
end

function NumberInput.focus(self: NumberInput)
	if self._enabled then
		self.box:CaptureFocus()
	end
end

function NumberInput.setEnabled(self: NumberInput, enabled: boolean)
	self._enabled = enabled
	if not enabled and self.box:IsFocused() then
		self.box:ReleaseFocus()
	end
	self:_refresh()
end

function NumberInput.destroy(self: NumberInput)
	if self._dragging then
		Kit.setCursor(self._props.host, nil)
	end
	self._maid:clean()
end

return NumberInput
