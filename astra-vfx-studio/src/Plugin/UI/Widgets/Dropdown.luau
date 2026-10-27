--!strict
--[[
	Dropdown — button showing the current option; opens an in-widget popup list in host.root.

		local blend = Dropdown.new({
			options = {
				{ value = "Additive", label = "Additiv", description = "Hellt auf (LightEmission 1)" },
				{ value = "Normal", label = "Normal" },
			},                               -- or plain strings: { "Linear", "Quad", "Cubic" }
			value = "Normal",
			placeholder = "Auswählen…",
			host = host,                     -- { plugin, widget, root }; the popup is parented to host.root
			onChange = function(value, final) editor:set("blend", value) end, -- final is always true
			parent = row,
		})
		blend:setValue("Additive")            -- display only, no callbacks
		blend:setOptions({ "A", "B" })

	The popup shows a search filter when there are more than `searchThreshold` (8) options. It closes on a choice,
	on a click outside (full-size transparent overlay in host.root), when the widget loses focus, on setEnabled(false),
	on destroy() and when the button instance is destroyed with an ancestor (Destroying), so no orphaned overlay keeps
	swallowing clicks. Keyboard navigation is not required. Options may also be positional ({ value, label, desc }).
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)
local SearchBox = require(script.Parent.SearchBox)

export type Option = { value: any, label: string?, description: string? }

type NormalizedOption = { value: any, label: string, description: string?, index: number }

export type Item = { option: NormalizedOption, button: TextButton }

export type Props = {
	options: { any }?, -- { Option | string }
	value: any?,
	placeholder: string?,
	host: Kit.Host?,
	size: UDim2?,
	popupWidth: number?, -- minimum popup width (default 160)
	maxVisible: number?, -- rows before the list scrolls (default 8)
	searchThreshold: number?, -- default 8
	enabled: boolean?,
	onChange: ((value: any, final: boolean) -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local Dropdown = {}
Dropdown.__index = Dropdown

type DropdownData = {
	instance: TextButton,
	label: TextLabel,
	arrow: TextLabel,
	popup: Frame?,
	overlay: TextButton?,
	list: ScrollingFrame?,
	search: SearchBox.SearchBox?,
	items: { Item },
	_maid: any, -- Maid (any: generic Maid methods do not unify across modules in the old solver)
	_popupMaid: any, -- Maid?
	_stroke: UIStroke,
	_props: Props,
	_options: { NormalizedOption },
	_value: any,
	_filter: string,
	_open: boolean,
	_enabled: boolean,
	_hovered: boolean,
}

export type Dropdown = typeof(setmetatable({} :: DropdownData, Dropdown))

local c = Theme.colors
local ROW = Theme.metrics.rowHeight
local DESC_ROW = ROW + 12

local function normalize(options: { any }?): { NormalizedOption }
	local out: { NormalizedOption } = {}
	local list: { any } = options or {}
	for i, o in list do
		if type(o) == "string" or type(o) == "number" then
			table.insert(out, { value = o, label = tostring(o), description = nil, index = i })
		elseif type(o) == "table" then
			local value = if o.value ~= nil then o.value else o[1]
			local label = o.label or o[2]
			local description = o.description or o[3]
			table.insert(out, {
				value = value,
				label = if label ~= nil then tostring(label) else tostring(value),
				description = if description ~= nil and description ~= "" then tostring(description) else nil,
				index = i,
			})
		end
	end
	return out
end

local function matches(option: NormalizedOption, filter: string): boolean
	if filter == "" then
		return true
	end
	local needle = string.lower(filter)
	if string.find(string.lower(option.label), needle, 1, true) then
		return true
	end
	if option.description and string.find(string.lower(option.description), needle, 1, true) then
		return true
	end
	return string.find(string.lower(tostring(option.value)), needle, 1, true) ~= nil
end

function Dropdown.new(props: Props): Dropdown
	local maid = Maid.new()
	local root = Instance.new("TextButton")
	root.Name = "Dropdown"
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundColor3 = c.bg2
	root.BorderSizePixel = 0
	root.Size = props.size or UDim2.new(1, 0, 0, ROW)
	root.Selectable = false
	Kit.applyCommon(root, props :: any)
	Kit.corner().Parent = root
	local stroke = Kit.stroke()
	stroke.Parent = root
	maid:give(root)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(8, 0)
	label.Size = UDim2.new(1, -28, 1, 0)
	label.FontFace = Theme.fonts.regular
	label.TextSize = Theme.textSize.normal
	label.TextColor3 = c.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = root

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(1, 0)
	arrow.Position = UDim2.new(1, -6, 0, 0)
	arrow.Size = UDim2.new(0, 14, 1, 0)
	arrow.FontFace = Theme.fonts.regular
	arrow.TextSize = Theme.textSize.small
	arrow.TextColor3 = c.textDim
	arrow.Text = "▾"
	arrow.Parent = root

	local self = setmetatable({
		instance = root,
		label = label,
		arrow = arrow,
		popup = nil :: Frame?,
		overlay = nil :: TextButton?,
		list = nil :: ScrollingFrame?,
		search = nil :: SearchBox.SearchBox?,
		items = {},
		_maid = maid,
		_popupMaid = nil :: Maid.Maid?,
		_stroke = stroke,
		_props = props,
		_options = normalize(props.options),
		_value = props.value,
		_filter = "",
		_open = false,
		_enabled = props.enabled ~= false,
		_hovered = false,
	}, Dropdown)

	maid:give(root.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	maid:give(root.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))
	maid:give(root.Activated:Connect(function()
		if self._open then
			self:close()
		else
			self:open()
		end
	end))
	maid:give(root.Destroying:Connect(function()
		self:close()
	end))
	maid:give(function()
		self:close()
	end)

	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function Dropdown._current(self: Dropdown): NormalizedOption?
	for _, option in self._options do
		if option.value == self._value then
			return option
		end
	end
	return nil
end

function Dropdown._refresh(self: Dropdown)
	local enabled = self._enabled
	local current = self:_current()
	if current then
		self.label.Text = current.label
		self.label.TextColor3 = if enabled then c.text else c.textMuted
	else
		self.label.Text = self._props.placeholder or "Auswählen…"
		self.label.TextColor3 = c.textMuted
	end
	self.arrow.TextColor3 = if enabled then (if self._open then c.text else c.textDim) else c.textMuted
	self._stroke.Color = if self._open then c.accent elseif self._hovered and enabled then c.borderStrong else c.border
	self.instance.BackgroundColor3 = if not enabled then c.bg1 elseif self._hovered then c.bg3 else c.bg2
	self.instance.Interactable = enabled
end

function Dropdown.isOpen(self: Dropdown): boolean
	return self._open
end

-- Opens the popup (needs props.host with a root). No-op when disabled or already open.
function Dropdown.open(self: Dropdown)
	local host = self._props.host
	if self._open or not self._enabled or host == nil or (host.root :: any) == nil then
		return
	end
	local popupMaid = Maid.new()
	self._popupMaid = popupMaid
	self._open = true
	self._filter = ""

	local overlay = Kit.overlay(host, "AstraDropdownOverlay", Kit.Z.popup, function()
		self:close()
	end)
	popupMaid:give(overlay)
	self.overlay = overlay

	local popup = Instance.new("Frame")
	popup.Name = "AstraDropdownPopup"
	popup.BackgroundColor3 = c.bg2
	popup.BorderSizePixel = 0
	popup.Active = true -- sinks clicks so they do not reach the overlay underneath
	popup.ClipsDescendants = true
	Kit.corner().Parent = popup
	Kit.stroke(c.borderStrong).Parent = popup
	popupMaid:give(popup)
	self.popup = popup

	local top = 4
	if #self._options > (self._props.searchThreshold or 8) then
		local search = SearchBox.new({
			name = "Search",
			placeholder = "Suchen…",
			size = UDim2.new(1, -8, 0, ROW),
			position = UDim2.fromOffset(4, 4),
			onChange = function(text: string)
				self._filter = text
				self:_rebuild()
			end,
		})
		search.instance.Parent = popup
		popupMaid:give(search)
		self.search = search
		top = ROW + 8
	end

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, top)
	list.Size = UDim2.new(1, 0, 1, -(top + 4))
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = Theme.metrics.scrollBar
	list.ScrollBarImageColor3 = c.borderStrong
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.CanvasSize = UDim2.new()
	list.Parent = popup
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Parent = list
	self.list = list

	local widget = host.widget
	if widget then
		local ok, signal = pcall(function()
			return widget.WindowFocusReleased
		end)
		if ok and signal then
			popupMaid:give(signal:Connect(function()
				self:close()
			end))
		end
	end

	self:_rebuild()
	popup.Parent = host.root
	self:_refresh()
	if self.search then
		self.search:focus()
	end
end

-- Rebuilds the visible items for the current filter, then sizes, positions and raises the popup.
function Dropdown._rebuild(self: Dropdown)
	local list = self.list
	local popup = self.popup
	local host = self._props.host
	if list == nil or popup == nil or host == nil then
		return
	end
	for _, item in self.items do
		item.button:Destroy()
	end
	table.clear(self.items)
	local empty = list:FindFirstChild("Empty")
	if empty then
		empty:Destroy()
	end

	local total = 0
	local rowsShown = 0
	local maxVisible = self._props.maxVisible or 8
	local visibleHeight = 0
	for _, option in self._options do
		if matches(option, self._filter) then
			local h = if option.description then DESC_ROW else ROW
			local button = self:_buildItem(option, h)
			button.LayoutOrder = option.index
			button.Parent = list
			table.insert(self.items, { option = option, button = button })
			total += h
			rowsShown += 1
			if rowsShown <= maxVisible then
				visibleHeight += h
			end
		end
	end
	if #self.items == 0 then
		local none = Instance.new("TextLabel")
		none.Name = "Empty"
		none.BackgroundTransparency = 1
		none.Size = UDim2.new(1, 0, 0, ROW)
		none.FontFace = Theme.fonts.regular
		none.TextSize = Theme.textSize.small
		none.TextColor3 = c.textMuted
		none.Text = "Keine Treffer"
		none.Parent = list
		total = ROW
		visibleHeight = ROW
	end
	list.CanvasSize = UDim2.fromOffset(0, total)

	-- size and position (below the button, above when there is no room; clamped into the root)
	local top = list.Position.Y.Offset
	local rootPos, rootSize = Kit.geometry(host.root)
	local buttonPos, buttonSize = Kit.geometry(self.instance)
	local width = math.max(buttonSize.X, self._props.popupWidth or 160)
	local height = math.min(top + visibleHeight + 4, math.max(ROW * 2, rootSize.Y - 8))
	local x = buttonPos.X - rootPos.X
	local below = buttonPos.Y - rootPos.Y + buttonSize.Y + 2
	local above = buttonPos.Y - rootPos.Y - 2 - height
	local y = below
	if below + height > rootSize.Y - 4 and above >= 4 then
		y = above
	end
	if x + width > rootSize.X - 4 then
		x = rootSize.X - width - 4
	end
	x = math.max(4, x)
	y = math.max(4, math.min(y, rootSize.Y - height - 4))
	popup.Size = UDim2.fromOffset(width, height)
	popup.Position = UDim2.fromOffset(x, y)
	Kit.raise(popup, Kit.Z.popup + 1)
end

function Dropdown._buildItem(self: Dropdown, option: NormalizedOption, height: number): TextButton
	local selected = option.value == self._value
	local button = Instance.new("TextButton")
	button.Name = "Item"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = if selected then c.accentDim else c.bg3
	button.BackgroundTransparency = if selected then 0 else 1
	button.BorderSizePixel = 0
	button.Size = UDim2.new(1, 0, 0, height)
	button.Selectable = false

	if selected then
		local bar = Instance.new("Frame")
		bar.Name = "Selected"
		bar.BackgroundColor3 = c.accent
		bar.BorderSizePixel = 0
		bar.Size = UDim2.new(0, 2, 1, 0)
		bar.Parent = button
	end

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(10, 0)
	text.Size = UDim2.new(1, -16, 0, ROW)
	text.FontFace = if selected then Theme.fonts.medium else Theme.fonts.regular
	text.TextSize = Theme.textSize.normal
	text.TextColor3 = c.text
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Text = option.label
	text.Parent = button

	if option.description then
		local desc = Instance.new("TextLabel")
		desc.Name = "Description"
		desc.BackgroundTransparency = 1
		desc.Position = UDim2.fromOffset(10, ROW - 7)
		desc.Size = UDim2.new(1, -16, 0, 14)
		desc.FontFace = Theme.fonts.regular
		desc.TextSize = Theme.textSize.tiny
		desc.TextColor3 = c.textMuted
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.Text = option.description
		desc.Parent = button
	end

	button.MouseEnter:Connect(function()
		if not selected then
			button.BackgroundTransparency = 0
		end
	end)
	button.MouseLeave:Connect(function()
		if not selected then
			button.BackgroundTransparency = 1
		end
	end)
	button.Activated:Connect(function()
		self:_choose(option)
	end)
	return button
end

function Dropdown._choose(self: Dropdown, option: NormalizedOption)
	local changed = option.value ~= self._value
	self._value = option.value
	self:close()
	if changed and self._props.onChange then
		self._props.onChange(option.value, true)
	end
end

-- Chooses the option with `value` as if the user clicked it (fires onChange when it differs).
function Dropdown.choose(self: Dropdown, value: any)
	for _, option in self._options do
		if option.value == value then
			self:_choose(option)
			return
		end
	end
end

function Dropdown.close(self: Dropdown)
	if not self._open then
		return
	end
	self._open = false
	local popupMaid = self._popupMaid
	self._popupMaid = nil
	self.popup = nil
	self.overlay = nil
	self.list = nil
	self.search = nil
	table.clear(self.items)
	if popupMaid then
		popupMaid:clean()
	end
	self:_refresh()
end

-- Sets the value without firing callbacks.
function Dropdown.setValue(self: Dropdown, value: any)
	self._value = value
	self:_refresh()
	if self._open then
		self:_rebuild()
	end
end

function Dropdown.getValue(self: Dropdown): any
	return self._value
end

function Dropdown.setOptions(self: Dropdown, options: { any })
	self._options = normalize(options)
	self:_refresh()
	if self._open then
		self:_rebuild()
	end
end

function Dropdown.setEnabled(self: Dropdown, enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self._hovered = false
		self:close()
	end
	self:_refresh()
end

function Dropdown.destroy(self: Dropdown)
	self._maid:clean()
end

return Dropdown
