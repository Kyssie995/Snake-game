--!strict
--[[
	Tabs — tab strip with one content page per tab; only the selected page is visible.

		local tabs = Tabs.new({
			tabs = { { id = "props", text = "Eigenschaften" }, { id = "events", text = "Events", icon = "⚡" } },
			selected = "props",                         -- default: first tab
			onChange = function(id, final) settings:set("inspectorTab", id) end, -- final is always true
			parent = panel.body,
		})
		propertyList.Parent = tabs:page("props")
		tabs:setValue("events")                         -- switches without calling onChange
		tabs:addTab({ id = "notes", text = "Notizen" }) -- returns the new page Frame
		tabs:setBadge("events", "3")

	The selected tab is drawn on the page colour (bg1) with an accent underline; others are dim with a bg3 hover.
	Badges are rendered as dim rich text after the label.
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)

local Tabs = {}
Tabs.__index = Tabs

export type TabSpec = { id: string, text: string, icon: string?, badge: string? }

export type Props = {
	tabs: { TabSpec }?,
	selected: string?,
	onChange: ((id: string, final: boolean) -> ())?,
	enabled: boolean?,
	stripHeight: number?, -- default Theme.metrics.headerHeight
	name: string?,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

type TabEntry = {
	spec: TabSpec,
	button: TextButton,
	page: Frame,
	hovered: boolean,
	order: number,
}

type TabsData = {
	instance: Frame,
	strip: Frame,
	content: Frame,
	maid: Maid.Maid,
	_props: Props,
	_tabs: { [string]: TabEntry },
	_order: { string },
	_selected: string?,
	_enabled: boolean,
	_destroyed: boolean,
}

export type Tabs = typeof(setmetatable({} :: TabsData, Tabs))

function Tabs.new(props: Props): Tabs
	local stripHeight = props.stripHeight or Theme.metrics.headerHeight

	local root = New("Frame", {
		Name = props.name or "Tabs",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		BackgroundColor3 = Theme.colors.bg1,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}) :: Frame

	local strip = New("Frame", {
		Name = "Strip",
		Size = UDim2.new(1, 0, 0, stripHeight),
		BackgroundColor3 = Theme.colors.bg0,
		BorderSizePixel = 0,
		ZIndex = 2, -- tabs cover the strip border below them
		Parent = root,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 1),
		}),
		New("UIPadding", { PaddingLeft = UDim.new(0, Theme.metrics.paddingSmall) }),
	}) :: Frame
	New("Frame", {
		Name = "StripBorder",
		Position = UDim2.new(0, 0, 0, stripHeight - 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.colors.border,
		BorderSizePixel = 0,
		Parent = root,
	})

	local content = New("Frame", {
		Name = "Content",
		Position = UDim2.new(0, 0, 0, stripHeight),
		Size = UDim2.new(1, 0, 1, -stripHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = root,
	}) :: Frame

	local self = setmetatable({
		instance = root,
		strip = strip,
		content = content,
		maid = Maid.new(),
		_props = props,
		_tabs = {},
		_order = {},
		_selected = nil,
		_enabled = true,
		_destroyed = false,
	}, Tabs)

	local specs: { TabSpec } = props.tabs or {}
	for _, spec in specs do
		self:addTab(spec)
	end
	local initial = props.selected or self._order[1]
	if initial then
		self:setValue(initial)
	end
	if props.enabled == false then
		self:setEnabled(false)
	end
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

local function escape(text: string): string
	return (
		string.gsub(text, "[<>&\"']", {
			["<"] = "&lt;",
			[">"] = "&gt;",
			["&"] = "&amp;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

local function hex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

-- Rich text of a tab button: optional icon, label and a dim badge (e.g. a count).
local function tabText(spec: TabSpec): string
	local text = escape(spec.text)
	if spec.icon and spec.icon ~= "" then
		text = escape(spec.icon :: string) .. "  " .. text
	end
	if spec.badge and spec.badge ~= "" then
		text ..= string.format(
			'  <font color="%s" size="%d">%s</font>',
			hex(Theme.colors.textMuted),
			Theme.textSize.tiny,
			escape(spec.badge :: string)
		)
	end
	return text
end

function Tabs._refreshTab(self: Tabs, entry: TabEntry)
	local selected = self._selected == entry.spec.id
	local button = entry.button
	button.BackgroundColor3 = if selected
		then Theme.colors.bg1
		elseif entry.hovered and self._enabled then Theme.colors.bg3
		else Theme.colors.bg0
	button.TextColor3 = if not self._enabled
		then Theme.colors.textMuted
		elseif selected then Theme.colors.text
		else Theme.colors.textDim
	button.FontFace = if selected then Theme.fonts.medium else Theme.fonts.regular
	button.Interactable = self._enabled
	button.Text = tabText(entry.spec)
	local underline = button:FindFirstChild("Underline") :: Frame
	underline.Visible = selected
	entry.page.Visible = selected
end

-- Adds a tab at the end and returns its page Frame.
function Tabs.addTab(self: Tabs, tabSpec: TabSpec): Frame
	assert(type(tabSpec.id) == "string" and self._tabs[tabSpec.id] == nil, "Tabs:addTab: missing or duplicate id")
	local spec = table.clone(tabSpec) -- setText/setBadge must not mutate the caller's table
	local order = #self._order + 1
	local button = New("TextButton", {
		Name = "Tab_" .. spec.id,
		LayoutOrder = order,
		Size = UDim2.new(0, 0, 1, -3),
		AutomaticSize = Enum.AutomaticSize.X,
		AutoButtonColor = false,
		BackgroundColor3 = Theme.colors.bg0,
		BorderSizePixel = 0,
		Selectable = false,
		Text = tabText(spec),
		RichText = true,
		TextSize = Theme.textSize.small,
		FontFace = Theme.fonts.regular,
		TextColor3 = Theme.colors.textDim,
		Parent = self.strip,
	}, {
		New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		New("UICorner", { CornerRadius = UDim.new(0, Theme.metrics.corner) }),
		New("Frame", {
			Name = "Underline",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, -12, 1, 0),
			Size = UDim2.new(1, 24, 0, 2),
			BackgroundColor3 = Theme.colors.accent,
			BorderSizePixel = 0,
			Visible = false,
		}),
	}) :: TextButton

	local page = New("Frame", {
		Name = "Page_" .. spec.id,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Parent = self.content,
	}) :: Frame

	local entry: TabEntry = { spec = spec, button = button, page = page, hovered = false, order = order }
	self._tabs[spec.id] = entry
	table.insert(self._order, spec.id)

	button.Activated:Connect(function()
		if self._enabled then
			self:select(spec.id)
		end
	end)
	button.MouseEnter:Connect(function()
		entry.hovered = true
		self:_refreshTab(entry)
	end)
	button.MouseLeave:Connect(function()
		entry.hovered = false
		self:_refreshTab(entry)
	end)
	self.maid:give(button)
	self.maid:give(page)

	if self._selected == nil then
		self._selected = spec.id
	end
	self:_refreshTab(entry)
	return page
end

-- Removes a tab and destroys its page. Selects the first remaining tab when the removed one was selected.
function Tabs.removeTab(self: Tabs, id: string)
	local entry = self._tabs[id]
	if not entry then
		return
	end
	self._tabs[id] = nil
	local index = table.find(self._order, id)
	if index then
		table.remove(self._order, index)
	end
	entry.button:Destroy()
	entry.page:Destroy()
	if self._selected == id then
		self._selected = nil
		local nextId = self._order[1]
		if nextId then
			self:setValue(nextId)
		end
	end
end

function Tabs.page(self: Tabs, id: string): Frame?
	local entry = self._tabs[id]
	return if entry then entry.page else nil
end

function Tabs.tabIds(self: Tabs): { string }
	return table.clone(self._order)
end

function Tabs.getValue(self: Tabs): string?
	return self._selected
end

-- Switches to `id` without calling onChange.
function Tabs.setValue(self: Tabs, id: string)
	if self._tabs[id] == nil then
		return
	end
	self._selected = id
	for _, entry in self._tabs do
		self:_refreshTab(entry)
	end
end

-- Switches to `id` like a user click (calls onChange when the selection changes).
function Tabs.select(self: Tabs, id: string)
	if self._tabs[id] == nil or self._selected == id then
		return
	end
	self:setValue(id)
	if self._props.onChange then
		self._props.onChange(id, true)
	end
end

function Tabs.setText(self: Tabs, id: string, text: string)
	local entry = self._tabs[id]
	if entry then
		entry.spec.text = text
		self:_refreshTab(entry)
	end
end

function Tabs.setBadge(self: Tabs, id: string, badge: string?)
	local entry = self._tabs[id]
	if entry then
		entry.spec.badge = badge
		self:_refreshTab(entry)
	end
end

function Tabs.setEnabled(self: Tabs, enabled: boolean)
	self._enabled = enabled
	for _, entry in self._tabs do
		entry.button.Interactable = enabled
		self:_refreshTab(entry)
	end
end

function Tabs.destroy(self: Tabs)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.maid:clean()
	table.clear(self._tabs)
	self.instance:Destroy()
end

return Tabs
