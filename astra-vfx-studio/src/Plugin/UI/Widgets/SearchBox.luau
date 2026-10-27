--!strict
--[[
	SearchBox — text field with a magnifier glyph and a clear button; reports every text change.

		local search = SearchBox.new({
			placeholder = "Komponenten suchen…",
			onChange = function(text) library:filter(text) end, -- every change (GetPropertyChangedSignal("Text"))
			onSubmit = function(text) end,   -- optional: Enter
			parent = toolbar,
		})
		search:setValue("")                   -- display only, no callbacks
		search:clear()                        -- empties the field and fires onChange("")

	Escape clears the field. The magnifier is drawn from Frames (no font glyph dependency).
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)

export type Props = {
	value: string?,
	placeholder: string?,
	size: UDim2?,
	enabled: boolean?,
	onChange: ((text: string) -> ())?,
	onSubmit: ((text: string) -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local SearchBox = {}
SearchBox.__index = SearchBox

type SearchBoxData = {
	instance: Frame,
	box: TextBox,
	clearButton: TextButton,
	_maid: any, -- Maid (any: generic Maid methods do not unify across modules in the old solver)
	_stroke: UIStroke,
	_props: Props,
	_lastText: string,
	_enabled: boolean,
	_focused: boolean,
	_hovered: boolean,
}

export type SearchBox = typeof(setmetatable({} :: SearchBoxData, SearchBox))

local c = Theme.colors
local ICON_W = 22
local CLEAR_W = 22

local function magnifier(parent: Instance)
	local icon = Instance.new("Frame")
	icon.Name = "Magnifier"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 6, 0.5, 0)
	icon.Size = UDim2.fromOffset(12, 12)
	icon.Parent = parent

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromOffset(8, 8)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local ringStroke = Kit.stroke(c.textMuted)
	ringStroke.Thickness = 1.5
	ringStroke.Parent = ring
	ring.Parent = icon

	local handle = Instance.new("Frame")
	handle.Name = "Handle"
	handle.BackgroundColor3 = c.textMuted
	handle.BorderSizePixel = 0
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Position = UDim2.fromOffset(9.5, 9.5)
	handle.Size = UDim2.fromOffset(2, 5)
	handle.Rotation = -45
	handle.Parent = icon
end

function SearchBox.new(props: Props): SearchBox
	local maid = Maid.new()
	local root = Instance.new("Frame")
	root.Name = "SearchBox"
	root.BackgroundColor3 = c.bg2
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Size = props.size or UDim2.new(1, 0, 0, Theme.metrics.rowHeight)
	Kit.applyCommon(root, props :: any)
	Kit.corner().Parent = root
	local stroke = Kit.stroke()
	stroke.Parent = root
	maid:give(root)

	magnifier(root)

	local box = Instance.new("TextBox")
	box.Name = "Box"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Position = UDim2.fromOffset(ICON_W, 0)
	box.Size = UDim2.new(1, -(ICON_W + CLEAR_W), 1, 0)
	box.ClearTextOnFocus = false
	box.MultiLine = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.FontFace = Theme.fonts.regular
	box.TextSize = Theme.textSize.normal
	box.TextColor3 = c.text
	box.PlaceholderText = props.placeholder or "Suchen…"
	box.PlaceholderColor3 = c.textMuted
	box.Text = props.value or ""
	box.Selectable = false
	box.Parent = root

	local clearButton = Instance.new("TextButton")
	clearButton.Name = "Clear"
	clearButton.AutoButtonColor = false
	clearButton.BackgroundColor3 = c.bg3
	clearButton.BackgroundTransparency = 1
	clearButton.BorderSizePixel = 0
	clearButton.AnchorPoint = Vector2.new(1, 0.5)
	clearButton.Position = UDim2.new(1, -3, 0.5, 0)
	clearButton.Size = UDim2.fromOffset(CLEAR_W - 4, CLEAR_W - 4)
	clearButton.FontFace = Theme.fonts.medium
	clearButton.TextSize = Theme.textSize.title
	clearButton.TextColor3 = c.textMuted
	clearButton.Text = "×"
	clearButton.Selectable = false
	Kit.corner(3).Parent = clearButton
	clearButton.Parent = root

	local self = setmetatable({
		instance = root,
		box = box,
		clearButton = clearButton,
		_maid = maid,
		_stroke = stroke,
		_props = props,
		_lastText = props.value or "",
		_enabled = props.enabled ~= false,
		_focused = false,
		_hovered = false,
	}, SearchBox)

	maid:give(box:GetPropertyChangedSignal("Text"):Connect(function()
		self:_sync()
	end))
	maid:give(box.Focused:Connect(function()
		self._focused = true
		self:_refresh()
	end))
	maid:give(box.FocusLost:Connect(function(enterPressed: boolean, input: InputObject?)
		self._focused = false
		local escape = false
		if input ~= nil then
			local ok, key = pcall(function()
				return (input :: any).KeyCode
			end)
			escape = ok and key == Enum.KeyCode.Escape
		end
		self:_sync()
		if escape then
			self:clear()
		elseif enterPressed and props.onSubmit then
			props.onSubmit(box.Text)
		end
		self:_refresh()
	end))
	maid:give(clearButton.Activated:Connect(function()
		if self._enabled then
			self:clear()
		end
	end))
	maid:give(clearButton.MouseEnter:Connect(function()
		clearButton.BackgroundTransparency = 0
		clearButton.TextColor3 = c.text
	end))
	maid:give(clearButton.MouseLeave:Connect(function()
		clearButton.BackgroundTransparency = 1
		clearButton.TextColor3 = c.textMuted
	end))
	maid:give(root.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	maid:give(root.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))

	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

-- Reports the current text if it changed since the last report (safe to call repeatedly).
function SearchBox._sync(self: SearchBox)
	local text = self.box.Text
	self.clearButton.Visible = text ~= ""
	if text == self._lastText then
		return
	end
	self._lastText = text
	if self._props.onChange then
		self._props.onChange(text)
	end
end

function SearchBox._refresh(self: SearchBox)
	local enabled = self._enabled
	self._stroke.Color = if self._focused
		then c.accent
		elseif self._hovered and enabled then c.borderStrong
		else c.border
	self.box.TextEditable = enabled
	self.box.TextColor3 = if enabled then c.text else c.textMuted
	self.instance.Interactable = enabled
	self.clearButton.Visible = self.box.Text ~= ""
end

-- Empties the field and fires onChange("") when it was not empty.
function SearchBox.clear(self: SearchBox)
	self.box.Text = ""
	self:_sync()
end

-- Sets the text without firing callbacks.
function SearchBox.setValue(self: SearchBox, text: string)
	self._lastText = text
	self.box.Text = text
	self:_refresh()
end

function SearchBox.getValue(self: SearchBox): string
	return self.box.Text
end

function SearchBox.focus(self: SearchBox)
	if self._enabled then
		self.box:CaptureFocus()
	end
end

function SearchBox.setEnabled(self: SearchBox, enabled: boolean)
	self._enabled = enabled
	if not enabled and self.box:IsFocused() then
		self.box:ReleaseFocus()
	end
	self:_refresh()
end

function SearchBox.destroy(self: SearchBox)
	self._maid:clean()
end

return SearchBox
