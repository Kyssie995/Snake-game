--!strict
--[[
	Button — text button in four variants.

		local save = Button.new({
			text = "Speichern",
			variant = "primary",           -- "primary" | "secondary" (default) | "ghost" | "danger"
			icon = "+",                    -- optional text glyph shown before the label
			tooltip = "Effekt speichern",  -- needs props.host
			host = host,
			size = UDim2.fromOffset(96, 24), -- optional; default: width fits the text, height = rowHeight
			onActivate = function() editor:save() end,
			parent = toolbar,
		})
		save:setEnabled(false)
		save:setText("Gespeichert")
		save:destroy()
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)
local Tooltip = require(script.Parent.Tooltip)

export type Variant = "primary" | "secondary" | "ghost" | "danger"

export type Props = {
	text: string?,
	variant: Variant?,
	icon: string?,
	tooltip: string?,
	host: Kit.Host?,
	size: UDim2?,
	width: number?, -- fixed pixel width (height = rowHeight)
	enabled: boolean?,
	onActivate: (() -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

type Palette = {
	bg: Color3,
	hover: Color3,
	press: Color3,
	transparency: number, -- background transparency when idle
	text: Color3,
	textHover: Color3,
	stroke: Color3?,
}

local Button = {}
Button.__index = Button

type ButtonData = {
	instance: TextButton,
	_maid: any, -- Maid (any: generic Maid methods do not unify across modules in the old solver)
	_stroke: UIStroke,
	_variant: Variant,
	_enabled: boolean,
	_hovered: boolean,
	_pressed: boolean,
	_text: string,
	_icon: string?,
	_tooltip: any,
	_props: Props,
}

export type Button = typeof(setmetatable({} :: ButtonData, Button))

local c = Theme.colors
local derived = Kit.derived

local function palette(variant: Variant): Palette
	if variant == "primary" then
		return {
			bg = c.accent,
			hover = c.accentHover,
			press = derived.accentPressed,
			transparency = 0,
			text = c.text,
			textHover = c.text,
			stroke = nil,
		}
	elseif variant == "danger" then
		return {
			bg = derived.danger,
			hover = c.error,
			press = derived.dangerPressed,
			transparency = 0,
			text = c.text,
			textHover = c.text,
			stroke = nil,
		}
	elseif variant == "ghost" then
		return {
			bg = c.bg3,
			hover = c.bg3,
			press = c.bg4,
			transparency = 1,
			text = c.textDim,
			textHover = c.text,
			stroke = nil,
		}
	end
	return {
		bg = c.bg2,
		hover = c.bg3,
		press = c.bg4,
		transparency = 0,
		text = c.text,
		textHover = c.text,
		stroke = c.border,
	}
end

local function composeText(text: string, icon: string?): string
	if icon and icon ~= "" then
		return if text ~= "" then icon .. "  " .. text else icon
	end
	return text
end

function Button.new(props: Props): Button
	local maid = Maid.new()
	local root = Instance.new("TextButton")
	root.Name = "Button"
	root.AutoButtonColor = false
	root.BorderSizePixel = 0
	root.FontFace = Theme.fonts.medium
	root.TextSize = Theme.textSize.normal
	root.TextTruncate = Enum.TextTruncate.AtEnd
	root.Selectable = false
	if props.size then
		root.Size = props.size
	elseif props.width then
		root.Size = UDim2.fromOffset(props.width, Theme.metrics.rowHeight)
	else
		root.Size = UDim2.fromOffset(0, Theme.metrics.rowHeight)
		root.AutomaticSize = Enum.AutomaticSize.X
	end
	Kit.applyCommon(root, props :: any)
	Kit.corner().Parent = root
	Kit.padding(10, 10).Parent = root
	local stroke = Kit.stroke()
	stroke.Parent = root
	maid:give(root)

	local self = setmetatable({
		instance = root,
		_maid = maid,
		_stroke = stroke,
		_variant = (props.variant or "secondary") :: Variant,
		_enabled = props.enabled ~= false,
		_hovered = false,
		_pressed = false,
		_text = props.text or "",
		_icon = props.icon,
		_tooltip = nil :: any,
		_props = props,
	}, Button)

	root.Text = composeText(self._text, self._icon)

	for _, conn in
		Kit.bindStates(root, function(hovered: boolean, pressed: boolean)
			self._hovered = hovered
			self._pressed = pressed
			self:_refresh()
		end)
	do
		maid:give(conn)
	end
	maid:give(root.Activated:Connect(function()
		if self._enabled and props.onActivate then
			props.onActivate()
		end
	end))

	if props.tooltip and props.host then
		self:setTooltip(props.tooltip)
	end
	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function Button._refresh(self: Button)
	local p = palette(self._variant)
	local root = self.instance
	if not self._enabled then
		root.BackgroundColor3 = if self._variant == "primary"
			then c.accentDim
			elseif self._variant == "danger" then derived.dangerDisabled
			else c.bg2
		root.BackgroundTransparency = p.transparency
		root.TextColor3 = c.textMuted
		self._stroke.Enabled = p.stroke ~= nil
		self._stroke.Color = c.border
		root.Interactable = false
		return
	end
	root.Interactable = true
	if self._pressed then
		root.BackgroundColor3 = p.press
		root.BackgroundTransparency = 0
	elseif self._hovered then
		root.BackgroundColor3 = p.hover
		root.BackgroundTransparency = 0
	else
		root.BackgroundColor3 = p.bg
		root.BackgroundTransparency = p.transparency
	end
	root.TextColor3 = if self._hovered then p.textHover else p.text
	self._stroke.Enabled = p.stroke ~= nil
	self._stroke.Color = if self._hovered then c.borderStrong else (p.stroke or c.border)
end

function Button.setText(self: Button, text: string)
	self._text = text
	self.instance.Text = composeText(text, self._icon)
end

function Button.setIcon(self: Button, icon: string?)
	self._icon = icon
	self.instance.Text = composeText(self._text, icon)
end

function Button.setVariant(self: Button, variant: Variant)
	self._variant = variant
	self:_refresh()
end

function Button.setEnabled(self: Button, enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self._hovered = false
		self._pressed = false
	end
	self:_refresh()
end

function Button.isEnabled(self: Button): boolean
	return self._enabled
end

-- Replaces the tooltip text (needs props.host). nil removes it.
function Button.setTooltip(self: Button, text: string?)
	local host = self._props.host
	if self._tooltip then
		self._tooltip:Disconnect()
		self._tooltip = nil
	end
	if host and text and text ~= "" then
		self._tooltip = Tooltip.attach(host, self.instance, text)
	end
end

function Button.destroy(self: Button)
	if self._tooltip then
		self._tooltip:Disconnect()
		self._tooltip = nil
	end
	self._maid:clean()
end

return Button
