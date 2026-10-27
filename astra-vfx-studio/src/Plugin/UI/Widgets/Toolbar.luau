--!strict
--[[
	Toolbar — horizontal bar of buttons (IconButton/Button widgets or any GuiObject) with separators and
	flexible spacers, laid out by a UIListLayout. The toolbar owns its items and destroys them with itself.

		local bar = Toolbar.new({
			items = {
				IconButton.new({ glyph = "▶", tooltip = "Play", host = host, onActivate = play }),
				"separator",
				Button.new({ text = "Export", onActivate = export }),
				"spacer",                                  -- pushes the following items to the right
				someGuiObject,
			},
			parent = panel.body,
		})
		bar:add(IconButton.new({ ... }))
		bar:setEnabled(false)                          -- forwards to every item with setEnabled
		bar:destroy()

	`autoWidth = true` sizes the bar to its content (for Panel header slots); otherwise it spans the parent width.
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)

local Toolbar = {}
Toolbar.__index = Toolbar

Toolbar.SEPARATOR = "separator"
Toolbar.SPACER = "spacer"

export type Props = {
	items: { any }?, -- widget objects, GuiObjects, "separator" or "spacer"
	height: number?, -- default Theme.metrics.toolbarHeight (Theme.metrics.headerHeight with autoWidth)
	autoWidth: boolean?,
	padding: number?, -- gap between items (default 2)
	background: boolean?, -- draw bg1 + bottom border (default true unless autoWidth)
	enabled: boolean?, -- false disables every item (also items added later)
	name: string?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

type ToolbarData = {
	instance: Frame,
	content: Frame,
	maid: Maid.Maid,
	items: { any },
	_order: number,
	_enabled: boolean,
	_destroyed: boolean,
}

export type Toolbar = typeof(setmetatable({} :: ToolbarData, Toolbar))

function Toolbar.new(props: Props): Toolbar
	local autoWidth = props.autoWidth == true
	local height = props.height or (if autoWidth then Theme.metrics.headerHeight else Theme.metrics.toolbarHeight)
	local background = if props.background ~= nil then props.background else not autoWidth

	local root = New("Frame", {
		Name = props.name or "Toolbar",
		Size = if autoWidth then UDim2.new(0, 0, 0, height) else UDim2.new(1, 0, 0, height),
		AutomaticSize = if autoWidth then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
		Position = props.position or UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		BackgroundColor3 = Theme.colors.bg1,
		BackgroundTransparency = if background then 0 else 1,
		BorderSizePixel = 0,
	}) :: Frame

	-- Items live in `content` so the bottom border line is not placed by the list layout.
	local content = New("Frame", {
		Name = "Content",
		Size = if autoWidth then UDim2.new(0, 0, 1, 0) else UDim2.fromScale(1, 1),
		AutomaticSize = if autoWidth then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, props.padding or 2),
		}),
		New("UIPadding", {
			PaddingLeft = UDim.new(0, if autoWidth then 0 else Theme.metrics.paddingSmall),
			PaddingRight = UDim.new(0, if autoWidth then 0 else Theme.metrics.paddingSmall),
		}),
	}) :: Frame

	if background then
		New("Frame", {
			Name = "BottomBorder",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.colors.border,
			BorderSizePixel = 0,
			Parent = root,
		})
	end

	local self = setmetatable({
		instance = root,
		content = content,
		maid = Maid.new(),
		items = {},
		_order = 0,
		_enabled = true,
		_destroyed = false,
	}, Toolbar)

	if props.enabled == false then
		self._enabled = false
	end
	local items: { any } = props.items or {}
	for _, item in items do
		self:add(item)
	end
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

-- Adds a widget object (with .instance), a GuiObject, "separator" or "spacer". Returns the item (or the created
-- separator/spacer Frame).
function Toolbar.add(self: Toolbar, item: any): any
	if item == Toolbar.SEPARATOR then
		return self:addSeparator()
	elseif item == Toolbar.SPACER then
		return self:addSpacer()
	end
	local gui: GuiObject
	if typeof(item) == "Instance" then
		gui = item :: GuiObject
	elseif type(item) == "table" and typeof(item.instance) == "Instance" then
		gui = item.instance
	else
		error("Toolbar:add expects a widget object, a GuiObject, 'separator' or 'spacer'", 2)
	end
	self._order += 1
	gui.LayoutOrder = self._order
	gui.Parent = self.content
	table.insert(self.items, item)
	self.maid:give(item)
	if not self._enabled then
		if type(item) == "table" and type(item.setEnabled) == "function" then
			item:setEnabled(false)
		else
			gui.Interactable = false
		end
	end
	return item
end

function Toolbar.addSeparator(self: Toolbar): Frame
	self._order += 1
	-- 9px wide holder with a centred 1px line (4px margin on both sides)
	local holder = New("Frame", {
		Name = "Separator",
		LayoutOrder = self._order,
		Size = UDim2.new(0, 9, 1, 0),
		BackgroundTransparency = 1,
		Parent = self.content,
	}, {
		New("Frame", {
			Name = "Line",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1, 16),
			BackgroundColor3 = Theme.colors.borderStrong,
			BorderSizePixel = 0,
		}),
	}) :: Frame
	self.maid:give(holder)
	return holder
end

-- Flexible empty space; items added after it are pushed to the right end of the bar.
function Toolbar.addSpacer(self: Toolbar): Frame
	self._order += 1
	local spacer = New("Frame", {
		Name = "Spacer",
		LayoutOrder = self._order,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = self.content,
	}, {
		New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
	}) :: Frame
	self.maid:give(spacer)
	return spacer
end

-- Destroys all items (widgets and GuiObjects).
function Toolbar.clear(self: Toolbar)
	self.maid:clean()
	table.clear(self.items)
	self._order = 0
end

function Toolbar.setEnabled(self: Toolbar, enabled: boolean)
	self._enabled = enabled
	for _, item in self.items do
		if type(item) == "table" and type(item.setEnabled) == "function" then
			item:setEnabled(enabled)
		elseif typeof(item) == "Instance" and item:IsA("GuiObject") then
			(item :: GuiObject).Interactable = enabled
		end
	end
end

function Toolbar.destroy(self: Toolbar)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.maid:clean()
	table.clear(self.items)
	self.instance:Destroy()
end

return Toolbar
