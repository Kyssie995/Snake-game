--!strict
--[[
	PropertyRow — one inspector line: label column (Theme.metrics.labelWidth of the width), a field slot, an
	optional reset button (visible while the value differs from the default) and an optional keyframe button.

		local row = PropertyRow.new({
			label = "Rate",
			description = "Partikel pro Sekunde",        -- tooltip on the label (needs host)
			host = host,
			field = NumberInput.new({ value = 20, host = host, onChange = setRate }), -- owned by the row
			value = 20, default = 20,                   -- reset button shows while value ~= default (deep compare)
			onReset = function() setRate(20, true) end,
			keyframe = "has-track",                     -- "none" | "has-track" | "key-at-playhead"; nil = no button
			onKeyframe = function(state) editor:toggleKey("rate", state) end,
			parent = section.body,
		})
		row:setValue(42)                                -- forwards to field:setValue + updates the reset button
		row:setKeyframeState("key-at-playhead")

	Keyframe glyph: a diamond (rotated square) — outline muted (none), outline keyframe colour (has-track),
	filled keyframe colour (key at the playhead). Modified rows show their label in the bright text colour.
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)
local IconButton = require(script.Parent.IconButton)
local Tooltip = require(script.Parent.Tooltip)

local PropertyRow = {}
PropertyRow.__index = PropertyRow

export type KeyframeState = "none" | "has-track" | "key-at-playhead"

export type Props = {
	label: string,
	description: string?,
	field: any?, -- widget object (with .instance) or GuiObject; owned by the row
	value: any?,
	default: any?,
	resettable: boolean?, -- default: true when `default` or `onReset` is given
	onReset: (() -> ())?,
	keyframe: KeyframeState?, -- nil: no keyframe button
	onKeyframe: ((state: KeyframeState) -> ())?,
	host: any?,
	labelWidth: number?, -- fraction (default Theme.metrics.labelWidth)
	indent: number?, -- extra label indent in px (nested properties)
	height: number?, -- default Theme.metrics.rowHeight
	enabled: boolean?,
	name: string?,
	layoutOrder: number?,
	parent: Instance?,
}

type PropertyRowData = {
	instance: Frame,
	label: TextLabel,
	slot: Frame,
	field: any?,
	resetButton: any?, -- IconButton
	keyframeButton: any?, -- IconButton (with a Diamond frame)
	maid: Maid.Maid,
	_props: Props,
	_fieldMaid: Maid.Maid,
	_tooltip: any,
	_value: any,
	_default: any,
	_modifiedOverride: boolean?,
	_keyframe: KeyframeState?,
	_hovered: boolean,
	_enabled: boolean,
	_destroyed: boolean,
}

export type PropertyRow = typeof(setmetatable({} :: PropertyRowData, PropertyRow))

local BUTTON = 18
local GAP = 2

local function nearlyEqual(a: number, b: number): boolean
	return math.abs(a - b) <= 1e-9 * math.max(1, math.abs(a), math.abs(b))
end

-- Structural equality for JSON-style values (numbers compared with a tiny tolerance) and Roblox datatypes.
local function deepEqual(a: any, b: any): boolean
	if type(a) == "number" and type(b) == "number" then
		return nearlyEqual(a, b)
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end
PropertyRow.deepEqual = deepEqual

function PropertyRow.new(props: Props): PropertyRow
	local height = props.height or Theme.metrics.rowHeight
	local labelWidth = props.labelWidth or Theme.metrics.labelWidth
	local indent = props.indent or 0
	local resettable = if props.resettable ~= nil
		then props.resettable
		else (props.default ~= nil or props.onReset ~= nil)
	local hasKeyframe = props.keyframe ~= nil
	local buttonsWidth = (if resettable then BUTTON + GAP else 0) + (if hasKeyframe then BUTTON + GAP else 0)

	local root = New("Frame", {
		Name = props.name or ("Property_" .. props.label),
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.colors.bg3,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}) :: Frame

	local label = New("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(Theme.metrics.padding + indent, 0),
		Size = UDim2.new(
			labelWidth,
			-(Theme.metrics.padding + indent + 6),
			0,
			math.min(height, Theme.metrics.rowHeight)
		),
		BackgroundTransparency = 1,
		Text = props.label,
		TextColor3 = Theme.colors.textDim,
		TextSize = Theme.textSize.small,
		FontFace = Theme.fonts.regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = root,
	}) :: TextLabel

	local slot = New("Frame", {
		Name = "Field",
		Position = UDim2.new(labelWidth, 0, 0, 0),
		Size = UDim2.new(1 - labelWidth, -(buttonsWidth + Theme.metrics.paddingSmall), 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	}) :: Frame

	local self = setmetatable({
		instance = root,
		label = label,
		slot = slot,
		field = nil,
		resetButton = nil :: any,
		keyframeButton = nil :: any,
		maid = Maid.new(),
		_props = props,
		_fieldMaid = Maid.new(),
		_tooltip = nil,
		_value = props.value,
		_default = props.default,
		_modifiedOverride = nil,
		_keyframe = props.keyframe,
		_hovered = false,
		_enabled = true,
		_destroyed = false,
	}, PropertyRow)

	local x = -Theme.metrics.paddingSmall
	if hasKeyframe then
		local button = IconButton.new({
			name = "Keyframe",
			glyph = "",
			size = BUTTON,
			host = props.host,
			tooltip = "Keyframe setzen/entfernen",
			anchorPoint = Vector2.new(1, 0.5),
			position = UDim2.new(1, x, 0, math.min(height, Theme.metrics.rowHeight) / 2),
			onActivate = function()
				if self._keyframe and props.onKeyframe then
					props.onKeyframe(self._keyframe :: KeyframeState)
				end
			end,
			parent = root,
		})
		New("Frame", {
			Name = "Diamond",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			Rotation = 45,
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.colors.keyframe,
			BackgroundTransparency = 1,
			Parent = button.instance,
		}, {
			New("UIStroke", {
				Color = Theme.colors.textMuted,
				Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
		self.keyframeButton = button
		self.maid:give(button)
		x -= BUTTON + GAP
	end
	if resettable then
		local button = IconButton.new({
			name = "Reset",
			glyph = "↺",
			glyphSize = Theme.textSize.normal,
			size = BUTTON,
			host = props.host,
			tooltip = "Auf Standardwert zurücksetzen",
			anchorPoint = Vector2.new(1, 0.5),
			position = UDim2.new(1, x, 0, math.min(height, Theme.metrics.rowHeight) / 2),
			onActivate = function()
				self:reset()
			end,
			parent = root,
		})
		self.resetButton = button
		self.maid:give(button)
	end

	self.maid:give(root.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	self.maid:give(root.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))

	if props.description and props.description ~= "" then
		self:setDescription(props.description)
	end
	if props.field ~= nil then
		self:setField(props.field)
	end
	if props.enabled == false then
		self:setEnabled(false)
	end
	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function PropertyRow.isModified(self: PropertyRow): boolean
	if self._modifiedOverride ~= nil then
		return self._modifiedOverride :: boolean
	end
	if self._default == nil then
		return false
	end
	return not deepEqual(self._value, self._default)
end

function PropertyRow._refresh(self: PropertyRow)
	local modified = self:isModified()
	local enabled = self._enabled
	self.instance.BackgroundTransparency = if self._hovered and enabled then 0.75 else 1
	self.label.TextColor3 = if not enabled
		then Theme.colors.textMuted
		elseif modified then Theme.colors.text
		else Theme.colors.textDim
	if self.resetButton then
		self.resetButton.instance.Visible = modified
	end
	local keyButton = self.keyframeButton
	if keyButton then
		local state = self._keyframe
		keyButton.instance.Visible = state ~= nil
		local diamond = keyButton.instance:FindFirstChild("Diamond") :: Frame
		local stroke = diamond:FindFirstChildOfClass("UIStroke") :: UIStroke
		if state == "key-at-playhead" then
			diamond.BackgroundTransparency = 0
			stroke.Color = Theme.colors.keyframe
		elseif state == "has-track" then
			diamond.BackgroundTransparency = 1
			stroke.Color = Theme.colors.keyframe
		else
			diamond.BackgroundTransparency = 1
			stroke.Color = Theme.colors.textMuted
		end
		stroke.Transparency = if enabled then 0 else 0.5
	end
end

-- Places a widget (owned by the row; the previous field is destroyed) or a GuiObject in the field slot.
function PropertyRow.setField(self: PropertyRow, field: any?)
	self._fieldMaid:clean()
	self.field = field
	if field == nil then
		return
	end
	local gui: GuiObject
	if typeof(field) == "Instance" then
		gui = field :: GuiObject
	elseif type(field) == "table" and typeof(field.instance) == "Instance" then
		gui = field.instance
	else
		error("PropertyRow:setField expects a widget object or a GuiObject", 2)
	end
	gui.AnchorPoint = Vector2.zero
	gui.Position = UDim2.new()
	gui.Size = UDim2.fromScale(1, 1)
	gui.Parent = self.slot
	self._fieldMaid:give(field)
	if not self._enabled and type(field) == "table" and type(field.setEnabled) == "function" then
		field:setEnabled(false)
	end
end

-- Updates the displayed value (field:setValue when available) and the reset button. Fires no callbacks.
function PropertyRow.setValue(self: PropertyRow, value: any)
	self._value = value
	local field = self.field
	if type(field) == "table" and type(field.setValue) == "function" then
		field:setValue(value)
	end
	self:_refresh()
end

function PropertyRow.getValue(self: PropertyRow): any
	return self._value
end

function PropertyRow.setDefault(self: PropertyRow, default: any)
	self._default = default
	self:_refresh()
end

-- Forces the modified state (nil = derive it from value vs. default).
function PropertyRow.setModified(self: PropertyRow, modified: boolean?)
	self._modifiedOverride = modified
	self:_refresh()
end

-- Multi-selection with differing values: forwards to field:setMixed when available.
function PropertyRow.setMixed(self: PropertyRow, mixed: boolean)
	local field = self.field
	if type(field) == "table" and type(field.setMixed) == "function" then
		field:setMixed(mixed)
	end
end

-- Like a click on the reset button: calls onReset (when visible/modified).
function PropertyRow.reset(self: PropertyRow)
	if not self._enabled or not self:isModified() then
		return
	end
	if self._props.onReset then
		self._props.onReset()
	end
end

function PropertyRow.getKeyframeState(self: PropertyRow): KeyframeState?
	return self._keyframe
end

-- nil hides the button (only rows created with props.keyframe have one).
function PropertyRow.setKeyframeState(self: PropertyRow, state: KeyframeState?)
	self._keyframe = state
	self:_refresh()
end

function PropertyRow.setLabel(self: PropertyRow, text: string)
	self.label.Text = text
end

function PropertyRow.setDescription(self: PropertyRow, text: string?)
	if self._tooltip then
		self._tooltip:Disconnect()
		self._tooltip = nil
	end
	local host = self._props.host
	if host and text and text ~= "" then
		self._tooltip = Tooltip.attach(host, self.label, text)
	end
end

function PropertyRow.setEnabled(self: PropertyRow, enabled: boolean)
	self._enabled = enabled
	local field = self.field
	if type(field) == "table" and type(field.setEnabled) == "function" then
		field:setEnabled(enabled)
	elseif typeof(field) == "Instance" and field:IsA("GuiObject") then
		(field :: GuiObject).Interactable = enabled
	end
	if self.resetButton then
		self.resetButton:setEnabled(enabled)
	end
	if self.keyframeButton then
		self.keyframeButton:setEnabled(enabled)
	end
	self:_refresh()
end

function PropertyRow.destroy(self: PropertyRow)
	if self._destroyed then
		return
	end
	self._destroyed = true
	if self._tooltip then
		self._tooltip:Disconnect()
		self._tooltip = nil
	end
	self._fieldMaid:clean()
	self.maid:clean()
	self.instance:Destroy()
end

return PropertyRow
