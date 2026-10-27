--!strict
--[[
	Section — collapsible group for the inspector: a 24px header (arrow, title, optional badge) above a body that
	stacks its children vertically (UIListLayout, automatic height).

		local emission = Section.new({
			title = "Emission",
			expanded = true,
			badge = "3",                                  -- optional dim text on the right (e.g. animated count)
			onToggle = function(expanded) view.sections.emission = expanded end,
			parent = inspectorList,
		})
		emission:add(PropertyRow.new({ label = "Rate", field = NumberInput.new({ ... }) }))
		emission:setExpanded(false)                       -- no callback

	Items added with :add() are owned by the section (destroyed with it or by :clear()).
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)

local Section = {}
Section.__index = Section

export type Props = {
	title: string,
	expanded: boolean?, -- default true
	badge: string?,
	onToggle: ((expanded: boolean) -> ())?,
	spacing: number?, -- gap between body rows (default 2)
	padding: number?, -- body padding (default Theme.metrics.paddingSmall)
	name: string?,
	layoutOrder: number?,
	parent: Instance?,
}

type SectionData = {
	instance: Frame,
	header: TextButton,
	body: Frame,
	maid: Maid.Maid,
	_props: Props,
	_items: Maid.Maid,
	_list: { any },
	_count: number,
	_expanded: boolean,
	_hovered: boolean,
	_enabled: boolean,
	_destroyed: boolean,
}

export type Section = typeof(setmetatable({} :: SectionData, Section))

function Section.new(props: Props): Section
	local rh = Theme.metrics.rowHeight
	local pad = props.padding or Theme.metrics.paddingSmall

	local root = New("Frame", {
		Name = props.name or ("Section_" .. props.title),
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	local header = New("TextButton", {
		Name = "Header",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, rh),
		AutoButtonColor = false,
		BackgroundColor3 = Theme.colors.bg2,
		BorderSizePixel = 0,
		Selectable = false,
		Text = "",
		Parent = root,
	}, {
		New("Frame", {
			Name = "TopBorder",
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.colors.border,
			BorderSizePixel = 0,
		}),
		New("TextLabel", {
			Name = "Arrow",
			Position = UDim2.fromOffset(4, 0),
			Size = UDim2.new(0, 14, 1, 0),
			BackgroundTransparency = 1,
			Text = "▶",
			TextSize = 8,
			FontFace = Theme.fonts.regular,
			TextColor3 = Theme.colors.textDim,
		}),
		New("TextLabel", {
			Name = "Title",
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -80, 1, 0),
			BackgroundTransparency = 1,
			Text = props.title,
			TextSize = Theme.textSize.small,
			FontFace = Theme.fonts.bold,
			TextColor3 = Theme.colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		New("TextLabel", {
			Name = "Badge",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.new(0, 52, 1, 0),
			BackgroundTransparency = 1,
			Text = props.badge or "",
			TextSize = Theme.textSize.tiny,
			FontFace = Theme.fonts.regular,
			TextColor3 = Theme.colors.textMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	}) :: TextButton

	local body = New("Frame", {
		Name = "Body",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, props.spacing or 2),
		}),
		New("UIPadding", {
			PaddingTop = UDim.new(0, pad),
			PaddingBottom = UDim.new(0, pad),
		}),
	}) :: Frame

	local self = setmetatable({
		instance = root,
		header = header,
		body = body,
		maid = Maid.new(),
		_props = props,
		_items = Maid.new(),
		_list = {},
		_count = 0,
		_expanded = props.expanded ~= false,
		_hovered = false,
		_enabled = true,
		_destroyed = false,
	}, Section)

	self.maid:give(header.Activated:Connect(function()
		if self._enabled then
			self:toggle()
		end
	end))
	self.maid:give(header.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	self.maid:give(header.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))

	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

function Section._refresh(self: Section)
	local header = self.header
	header.BackgroundColor3 = if self._hovered and self._enabled then Theme.colors.bg3 else Theme.colors.bg2
	local arrow = header:FindFirstChild("Arrow") :: TextLabel
	arrow.Rotation = if self._expanded then 90 else 0
	local title = header:FindFirstChild("Title") :: TextLabel
	title.TextColor3 = if self._enabled then Theme.colors.text else Theme.colors.textMuted
	self.body.Visible = self._expanded
end

-- Appends a widget object (with .instance) or a GuiObject to the body. Returns the item.
function Section.add(self: Section, item: any): any
	local gui: GuiObject
	if typeof(item) == "Instance" then
		gui = item :: GuiObject
	elseif type(item) == "table" and typeof(item.instance) == "Instance" then
		gui = item.instance
	else
		error("Section:add expects a widget object or a GuiObject", 2)
	end
	self._count += 1
	gui.LayoutOrder = self._count
	gui.Parent = self.body
	self._items:give(item)
	table.insert(self._list, item)
	if not self._enabled and type(item) == "table" and type(item.setEnabled) == "function" then
		item:setEnabled(false)
	end
	return item
end

-- Destroys every item added with :add().
function Section.clear(self: Section)
	self._items:clean()
	table.clear(self._list)
	self._count = 0
end

function Section.isExpanded(self: Section): boolean
	return self._expanded
end

-- Expands/collapses without calling onToggle.
function Section.setExpanded(self: Section, expanded: boolean)
	self._expanded = expanded
	self:_refresh()
end

Section.setValue = Section.setExpanded

-- Flips the state like a click (calls onToggle).
function Section.toggle(self: Section)
	self:setExpanded(not self._expanded)
	if self._props.onToggle then
		self._props.onToggle(self._expanded)
	end
end

function Section.setTitle(self: Section, title: string)
	(self.header:FindFirstChild("Title") :: TextLabel).Text = title
end

function Section.setBadge(self: Section, badge: string?)
	(self.header:FindFirstChild("Badge") :: TextLabel).Text = badge or ""
end

-- Disables the header and forwards to every added item that has setEnabled.
function Section.setEnabled(self: Section, enabled: boolean)
	self._enabled = enabled
	self.header.Interactable = enabled
	for _, item in self._list do
		if type(item) == "table" and type(item.setEnabled) == "function" then
			item:setEnabled(enabled)
		end
	end
	self:_refresh()
end

function Section.destroy(self: Section)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._items:clean()
	self.maid:clean()
	self.instance:Destroy()
end

return Section
