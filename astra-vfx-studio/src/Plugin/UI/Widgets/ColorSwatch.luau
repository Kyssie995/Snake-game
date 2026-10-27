--!strict
--[[
	ColorSwatch — colour preview button. Clicking it calls props.onPick(swatch, value); the colour picker (built
	separately, UI/Editors/ColorPicker) reports back through swatch:commit(value, final).

		local tint = ColorSwatch.new({
			value = "#FF8A3D",                         -- "#RRGGBB" | "#RGB" | "$paletteKey" | {r, g, b} | Color3,
			                                           -- or a gradient: ColorSequence / [[time, colour], ...]
			palette = compiled.palette,                -- resolves "$key" colours (optional)
			onPick = function(swatch, current)
				ColorPicker.open(host, { value = current, onChange = function(v, final) swatch:commit(v, final) end })
			end,
			onChange = function(value, final) ... end, -- fired by :commit()
			parent = row,
		})
		tint:setValue("$accent")                       -- display only, no callbacks

	Single colours show a chip plus the hex/palette text; gradients fill the whole field with a UIGradient.
	Unparseable values show a muted "—".
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)
local Tooltip = require(script.Parent.Tooltip)
local Codec = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Codec)

local ColorSwatch = {}
ColorSwatch.__index = ColorSwatch

export type Props = {
	value: any?,
	palette: { [string]: Color3 }?,
	onPick: ((swatch: any, value: any) -> ())?,
	onActivate: (() -> ())?, -- extra click hook (called after onPick)
	onChange: ((value: any, final: boolean) -> ())?,
	showText: boolean?, -- hex/palette text next to the chip (default true)
	host: any?,
	tooltip: string?,
	enabled: boolean?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

type ColorSwatchData = {
	instance: TextButton,
	chip: Frame,
	gradient: UIGradient,
	text: TextLabel,
	maid: Maid.Maid,
	_props: Props,
	_stroke: UIStroke,
	_value: any,
	_color: Color3?,
	_sequence: ColorSequence?,
	_hovered: boolean,
	_enabled: boolean,
	_destroyed: boolean,
}

export type ColorSwatch = typeof(setmetatable({} :: ColorSwatchData, ColorSwatch))

local CHIP_WIDTH = 28

-- Resolves a single colour (any accepted form) to a Color3, or nil.
function ColorSwatch.toColor(value: any, palette: { [string]: Color3 }?): Color3?
	if value == nil then
		return nil
	end
	return Codec.parseColor(value, palette)
end

-- Resolves gradients: a ColorSequence or a JSON keypoint list [[time, colour], ...]. nil for single colours.
function ColorSwatch.toSequence(value: any, palette: { [string]: Color3 }?): ColorSequence?
	if typeof(value) == "ColorSequence" then
		return value
	end
	if type(value) ~= "table" or type(value[1]) ~= "table" then
		return nil
	end
	local keypoints = {}
	for i, kp in value do
		if type(kp) ~= "table" or type(kp[1]) ~= "number" then
			return nil
		end
		local color = Codec.parseColor(kp[2], palette)
		if color == nil then
			return nil
		end
		local t = math.clamp(kp[1], 0, 1)
		if i == 1 then
			t = 0
		elseif i == #value then
			t = 1
		end
		table.insert(keypoints, ColorSequenceKeypoint.new(t, color))
	end
	if #keypoints < 2 then
		return nil
	end
	local ok, seq = pcall(function()
		return ColorSequence.new(keypoints)
	end)
	return if ok then seq else nil
end

function ColorSwatch.new(props: Props): ColorSwatch
	local root = New("TextButton", {
		Name = props.name or "ColorSwatch",
		Size = props.size or UDim2.new(1, 0, 0, Theme.metrics.rowHeight),
		Position = props.position or UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		AutoButtonColor = false,
		BackgroundColor3 = Theme.colors.bg2,
		BorderSizePixel = 0,
		Selectable = false,
		Text = "",
		ClipsDescendants = true,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0, Theme.metrics.corner) }),
	}) :: TextButton
	local stroke = New("UIStroke", {
		Color = Theme.colors.border,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = root,
	}) :: UIStroke

	local chip = New("Frame", {
		Name = "Chip",
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(0, CHIP_WIDTH, 1, -6),
		BackgroundColor3 = Theme.colors.bg0,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0, Theme.metrics.corner - 1) }),
		New("UIStroke", {
			Color = Theme.colors.borderStrong,
			Thickness = 1,
			Transparency = 0.3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	}) :: Frame
	local gradient = New("UIGradient", { Name = "Gradient", Enabled = false, Parent = chip }) :: UIGradient

	local text = New("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(CHIP_WIDTH + 10, 0),
		Size = UDim2.new(1, -(CHIP_WIDTH + 14), 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Theme.colors.text,
		TextSize = Theme.textSize.small,
		FontFace = Theme.fonts.mono,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = root,
	}) :: TextLabel

	local self = setmetatable({
		instance = root,
		chip = chip,
		gradient = gradient,
		text = text,
		maid = Maid.new(),
		_props = props,
		_stroke = stroke,
		_value = nil :: any,
		_color = nil :: Color3?,
		_sequence = nil :: ColorSequence?,
		_hovered = false,
		_enabled = props.enabled ~= false,
		_destroyed = false,
	}, ColorSwatch)

	self.maid:give(root.Activated:Connect(function()
		self:activate()
	end))
	self.maid:give(root.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	self.maid:give(root.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))
	if props.host and props.tooltip then
		self.maid:give(Tooltip.attach(props.host, root, props.tooltip))
	end

	self:setValue(props.value)
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function ColorSwatch._refresh(self: ColorSwatch)
	local enabled = self._enabled
	self.instance.Interactable = enabled
	self.instance.BackgroundColor3 = if self._hovered and enabled then Theme.colors.bg3 else Theme.colors.bg2
	self._stroke.Color = if self._hovered and enabled then Theme.colors.borderStrong else Theme.colors.border
	self.chip.BackgroundTransparency = if enabled then 0 else 0.5
	self.text.TextColor3 = if not enabled
		then Theme.colors.textMuted
		elseif self._color or self._sequence then Theme.colors.text
		else Theme.colors.textMuted
end

local function describe(value: any, color: Color3?): string
	if type(value) == "string" then
		if string.sub(value, 1, 1) == "$" then
			return value
		end
		return if color then Codec.toHex(color) else value
	end
	if color then
		return Codec.toHex(color)
	end
	return "—"
end

-- Display only: shows `value` without firing callbacks.
function ColorSwatch.setValue(self: ColorSwatch, value: any)
	local palette = self._props.palette
	self._value = value
	local sequence = ColorSwatch.toSequence(value, palette)
	local color = if sequence then nil else ColorSwatch.toColor(value, palette)
	self._sequence = sequence
	self._color = color
	local showText = self._props.showText ~= false

	if sequence then
		-- UIGradient multiplies the background colour, so the chip must be pure white to show the gradient as-is
		-- (a technical neutral, not a theme colour).
		self.chip.BackgroundColor3 = Color3.new(1, 1, 1)
		self.gradient.Color = sequence
		self.gradient.Enabled = true
		self.chip.Size = UDim2.new(1, -6, 1, -6)
		self.text.Visible = false
	else
		self.gradient.Enabled = false
		self.chip.BackgroundColor3 = color or Theme.colors.bg0
		self.chip.Size = if showText then UDim2.new(0, CHIP_WIDTH, 1, -6) else UDim2.new(1, -6, 1, -6)
		self.text.Visible = showText
		self.text.Text = describe(value, color)
	end
	self:_refresh()
end

function ColorSwatch.getValue(self: ColorSwatch): any
	return self._value
end

-- Resolved single colour (nil for gradients or invalid values).
function ColorSwatch.getColor(self: ColorSwatch): Color3?
	return self._color
end

function ColorSwatch.getSequence(self: ColorSwatch): ColorSequence?
	return self._sequence
end

-- Sets the value like a user edit: updates the display and calls onChange(value, final).
function ColorSwatch.commit(self: ColorSwatch, value: any, final: boolean?)
	self:setValue(value)
	if self._props.onChange then
		self._props.onChange(value, final ~= false)
	end
end

-- Like a click: calls onPick(self, value) and onActivate().
function ColorSwatch.activate(self: ColorSwatch)
	if not self._enabled or self._destroyed then
		return
	end
	if self._props.onPick then
		self._props.onPick(self, self._value)
	end
	if self._props.onActivate then
		self._props.onActivate()
	end
end

function ColorSwatch.setPalette(self: ColorSwatch, palette: { [string]: Color3 }?)
	self._props = table.clone(self._props)
	self._props.palette = palette
	self:setValue(self._value)
end

function ColorSwatch.setEnabled(self: ColorSwatch, enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self._hovered = false
	end
	self:_refresh()
end

function ColorSwatch.destroy(self: ColorSwatch)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.maid:clean()
	self.instance:Destroy()
end

-- Absolute position and size of the swatch (pickers anchor their popup to it).
function ColorSwatch.geometry(self: ColorSwatch): (Vector2, Vector2)
	return Kit.geometry(self.instance)
end

return ColorSwatch
