--!strict
--[[
	Label — single text line (truncated with "…") or wrapped paragraph.

		local title = Label.new({ text = "Emitter", variant = "title", parent = header })
		local hint = Label.new({
			text = "Keine Komponente ausgewählt",
			variant = "muted",               -- "normal" (default) | "dim" | "muted" | "title" | "mono" | "error"
			wrap = true,                     -- wrap instead of truncating; height grows with the text
			alignX = Enum.TextXAlignment.Center,
			parent = body,
		})
		hint:setValue("Neu")                 -- same as hint:setText("Neu")
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)

export type Variant = "normal" | "dim" | "muted" | "title" | "mono" | "error"

export type Props = {
	text: string?,
	variant: Variant?,
	size: UDim2?, -- default: full width × rowHeight (wrap: full width, automatic height)
	textSize: number?,
	alignX: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	wrap: boolean?,
	rich: boolean?,
	color: Color3?, -- explicit colour (use Theme tokens)
	enabled: boolean?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local Label = {}
Label.__index = Label

type LabelData = {
	instance: TextLabel,
	_maid: any, -- Maid (any: generic Maid methods do not unify across modules in the old solver)
	_variant: Variant,
	_enabled: boolean,
	_color: Color3?,
	_textSize: number?,
}

export type Label = typeof(setmetatable({} :: LabelData, Label))

local function style(variant: Variant): (Font, number, Color3)
	local c = Theme.colors
	if variant == "title" then
		return Theme.fonts.bold, Theme.textSize.title, c.text
	elseif variant == "dim" then
		return Theme.fonts.regular, Theme.textSize.normal, c.textDim
	elseif variant == "muted" then
		return Theme.fonts.regular, Theme.textSize.small, c.textMuted
	elseif variant == "mono" then
		return Theme.fonts.mono, Theme.textSize.small, c.text
	elseif variant == "error" then
		return Theme.fonts.regular, Theme.textSize.small, c.error
	end
	return Theme.fonts.regular, Theme.textSize.normal, c.text
end

function Label.new(props: Props): Label
	local maid = Maid.new()
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextXAlignment = props.alignX or Enum.TextXAlignment.Left
	label.TextYAlignment = props.alignY or (if props.wrap then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center)
	label.RichText = props.rich == true
	if props.wrap then
		label.TextWrapped = true
		label.TextTruncate = Enum.TextTruncate.None
		label.Size = props.size or UDim2.fromScale(1, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
	else
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Size = props.size or UDim2.new(1, 0, 0, Theme.metrics.rowHeight)
	end
	label.Text = props.text or ""
	Kit.applyCommon(label, props :: any)
	maid:give(label)

	local self = setmetatable({
		instance = label,
		_maid = maid,
		_variant = (props.variant or "normal") :: Variant,
		_enabled = props.enabled ~= false,
		_color = props.color,
		_textSize = props.textSize,
	}, Label)
	self:_refresh()
	if props.parent then
		label.Parent = props.parent
	end
	return self
end

function Label._refresh(self: Label)
	local font, size, color = style(self._variant)
	local label = self.instance
	label.FontFace = font
	label.TextSize = self._textSize or size
	label.TextColor3 = if not self._enabled then Theme.colors.textMuted else (self._color or color)
end

function Label.setText(self: Label, text: string)
	self.instance.Text = text
end

function Label.setValue(self: Label, text: string)
	self.instance.Text = text
end

function Label.getText(self: Label): string
	return self.instance.Text
end

function Label.setVariant(self: Label, variant: Variant)
	self._variant = variant
	self:_refresh()
end

function Label.setColor(self: Label, color: Color3?)
	self._color = color
	self:_refresh()
end

function Label.setEnabled(self: Label, enabled: boolean)
	self._enabled = enabled
	self:_refresh()
end

function Label.destroy(self: Label)
	self._maid:clean()
end

return Label
