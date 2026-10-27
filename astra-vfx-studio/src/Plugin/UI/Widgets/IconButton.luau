--!strict
--[[
	IconButton — square button showing a text glyph or an image, with an optional toggled state.

		local loop = IconButton.new({
			glyph = "↻",                    -- or image = "rbxassetid://123"
			tooltip = "Schleife",           -- needs props.host
			host = host,
			toggle = true,                  -- clicking flips the toggled state and calls onChange(toggled, true)
			toggled = false,
			onChange = function(on) editor:setLoop(on) end,
			onActivate = function() end,    -- called on every click
			parent = toolbar,
		})
		loop:setValue(true)                  -- updates the toggled look without callbacks
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)
local Tooltip = require(script.Parent.Tooltip)

export type Props = {
	glyph: string?,
	image: string?,
	size: number?, -- edge length in px (default rowHeight)
	glyphSize: number?,
	tooltip: string?,
	host: Kit.Host?,
	toggle: boolean?,
	toggled: boolean?,
	enabled: boolean?,
	onActivate: (() -> ())?,
	onChange: ((toggled: boolean, final: boolean) -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local IconButton = {}
IconButton.__index = IconButton

type IconButtonData = {
	instance: TextButton,
	image: ImageLabel?,
	_maid: any, -- Maid (any: generic Maid methods do not unify across modules in the old solver)
	_stroke: UIStroke,
	_enabled: boolean,
	_toggled: boolean,
	_hovered: boolean,
	_pressed: boolean,
	_tooltip: any,
	_props: Props,
}

export type IconButton = typeof(setmetatable({} :: IconButtonData, IconButton))

local c = Theme.colors

function IconButton.new(props: Props): IconButton
	local maid = Maid.new()
	local edge = props.size or Theme.metrics.rowHeight
	local root = Instance.new("TextButton")
	root.Name = "IconButton"
	root.AutoButtonColor = false
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(edge, edge)
	root.FontFace = Theme.fonts.medium
	root.TextSize = props.glyphSize or Theme.textSize.title
	root.Text = if props.image then "" else (props.glyph or "")
	root.Selectable = false
	Kit.applyCommon(root, props :: any)
	Kit.corner().Parent = root
	local stroke = Kit.stroke(c.accent)
	stroke.Parent = root
	maid:give(root)

	local image: ImageLabel? = nil
	if props.image then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromOffset(math.max(8, edge - 8), math.max(8, edge - 8))
		img.Image = props.image
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = root
		image = img
	end

	local self = setmetatable({
		instance = root,
		image = image,
		_maid = maid,
		_stroke = stroke,
		_enabled = props.enabled ~= false,
		_toggled = props.toggled == true,
		_hovered = false,
		_pressed = false,
		_tooltip = nil :: any,
		_props = props,
	}, IconButton)

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
		if not self._enabled then
			return
		end
		if props.toggle then
			self._toggled = not self._toggled
			self:_refresh()
			if props.onChange then
				props.onChange(self._toggled, true)
			end
		end
		if props.onActivate then
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

function IconButton._refresh(self: IconButton)
	local root = self.instance
	local fg: Color3
	if not self._enabled then
		root.BackgroundColor3 = c.bg2
		root.BackgroundTransparency = if self._toggled then 0 else 1
		fg = c.textMuted
		root.Interactable = false
	else
		root.Interactable = true
		if self._pressed then
			root.BackgroundColor3 = c.bg4
			root.BackgroundTransparency = 0
		elseif self._toggled then
			root.BackgroundColor3 = if self._hovered then c.selectionStrong else c.accentDim
			root.BackgroundTransparency = 0
		elseif self._hovered then
			root.BackgroundColor3 = c.bg3
			root.BackgroundTransparency = 0
		else
			root.BackgroundColor3 = c.bg3
			root.BackgroundTransparency = 1
		end
		fg = if self._toggled then c.text elseif self._hovered then c.text else c.textDim
	end
	root.TextColor3 = fg
	self._stroke.Enabled = self._toggled and self._enabled
	if self.image then
		self.image.ImageColor3 = fg
	end
end

-- Sets the toggled state without firing callbacks.
function IconButton.setValue(self: IconButton, toggled: boolean)
	self._toggled = toggled == true
	self:_refresh()
end

function IconButton.getValue(self: IconButton): boolean
	return self._toggled
end

function IconButton.setGlyph(self: IconButton, glyph: string)
	if self.image == nil then
		self.instance.Text = glyph
	end
end

function IconButton.setEnabled(self: IconButton, enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self._hovered = false
		self._pressed = false
	end
	self:_refresh()
end

function IconButton.setTooltip(self: IconButton, text: string?)
	local host = self._props.host
	if self._tooltip then
		self._tooltip:Disconnect()
		self._tooltip = nil
	end
	if host and text and text ~= "" then
		self._tooltip = Tooltip.attach(host, self.instance, text)
	end
end

function IconButton.destroy(self: IconButton)
	if self._tooltip then
		self._tooltip:Disconnect()
		self._tooltip = nil
	end
	self._maid:clean()
end

return IconButton
