--!strict
--[[
	Panel — the standard root container of every ASTRA panel: a header bar (optional icon, title, toolbar slot on
	the right) above a padded body. The body is a plain Frame, or a vertically scrolling frame with `scroll = true`.

		local panel = Panel.new({ title = "Explorer", parent = host.root })
		local bar = Toolbar.new({ autoWidth = true })
		panel:setToolbar(bar)                    -- widget object or GuiObject, placed right in the header
		list.instance.Parent = panel.body
		...
		panel:destroy()                          -- also destroys the toolbar and everything given to panel:give()

	The panel's root Frame is the `host.root` layer for popups, tooltips, toasts and dialogs (no layout objects, so
	those overlays can be positioned freely). When the panel is parented directly to a LayerCollector (the
	DockWidgetPluginGui), its ZIndexBehavior is set to Sibling (ControlKit.useSiblingZIndex), which the overlay
	layering relies on.
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)
local Kit = require(script.Parent.ControlKit)

local Panel = {}
Panel.__index = Panel

export type Props = {
	title: string?,
	icon: string?, -- glyph text or an image ("rbxassetid://…", "rbxasset://…")
	toolbar: any?, -- widget object (with .instance) or GuiObject for the header's right slot
	header: boolean?, -- false hides the header bar (default true)
	padding: number?, -- body padding in px (default Theme.metrics.padding)
	scroll: boolean?, -- body is a vertical ScrollingFrame with automatic canvas height
	enabled: boolean?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	parent: Instance?,
}

type PanelData = {
	instance: Frame,
	header: Frame,
	titleLabel: TextLabel,
	iconLabel: GuiObject?,
	toolbarSlot: Frame,
	body: GuiObject,
	maid: Maid.Maid,
	_toolbar: any?,
	_toolbarMaid: Maid.Maid,
	_destroyed: boolean,
}

export type Panel = typeof(setmetatable({} :: PanelData, Panel))

local function isImage(icon: string): boolean
	return string.sub(icon, 1, 3) == "rbx" or string.sub(icon, 1, 4) == "http"
end

local function guiOf(item: any): GuiObject?
	if typeof(item) == "Instance" then
		return item :: GuiObject
	elseif type(item) == "table" and typeof(item.instance) == "Instance" then
		return item.instance
	end
	return nil
end

function Panel.new(props: Props): Panel
	local metrics = Theme.metrics
	local headerHeight = if props.header == false then 0 else metrics.headerHeight
	local padding = props.padding or metrics.padding

	local root = New("Frame", {
		Name = props.name or "Panel",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.new(),
		BackgroundColor3 = Theme.colors.bg1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}) :: Frame

	local header = New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, headerHeight),
		BackgroundColor3 = Theme.colors.bg2,
		BorderSizePixel = 0,
		Visible = props.header ~= false,
		ZIndex = 2,
		Parent = root,
	}, {
		New("UIPadding", {
			PaddingLeft = UDim.new(0, metrics.padding),
			PaddingRight = UDim.new(0, metrics.paddingSmall),
		}),
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	}) :: Frame
	-- 1px divider under the header (outside the header so its UIListLayout does not place it)
	New("Frame", {
		Name = "HeaderDivider",
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, headerHeight - 1),
		BackgroundColor3 = Theme.colors.border,
		BorderSizePixel = 0,
		Visible = props.header ~= false,
		ZIndex = 3,
		Parent = root,
	})

	local iconLabel: GuiObject? = nil
	if props.icon and props.icon ~= "" then
		local icon = props.icon :: string
		if isImage(icon) then
			iconLabel = New("ImageLabel", {
				Name = "Icon",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				Image = icon,
				ImageColor3 = Theme.colors.textDim,
				ScaleType = Enum.ScaleType.Fit,
				Parent = header,
			})
		else
			iconLabel = New("TextLabel", {
				Name = "Icon",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				Text = icon,
				TextColor3 = Theme.colors.textDim,
				TextSize = Theme.textSize.normal,
				FontFace = Theme.fonts.medium,
				Parent = header,
			})
		end
	end

	local titleLabel = New("TextLabel", {
		Name = "Title",
		LayoutOrder = 2,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = props.title or "",
		TextColor3 = Theme.colors.text,
		TextSize = Theme.textSize.normal,
		FontFace = Theme.fonts.medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	}, {
		New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
	}) :: TextLabel

	local toolbarSlot = New("Frame", {
		Name = "ToolbarSlot",
		LayoutOrder = 3,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = header,
	}) :: Frame

	local body: GuiObject
	if props.scroll then
		body = New("ScrollingFrame", {
			Name = "Body",
			Position = UDim2.new(0, 0, 0, headerHeight),
			Size = UDim2.new(1, 0, 1, -headerHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = metrics.scrollBar,
			ScrollBarImageColor3 = Theme.colors.borderStrong,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			Parent = root,
		}, {
			New("UIPadding", {
				PaddingLeft = UDim.new(0, padding),
				PaddingRight = UDim.new(0, padding),
				PaddingTop = UDim.new(0, padding),
				PaddingBottom = UDim.new(0, padding),
			}),
		})
	else
		body = New("Frame", {
			Name = "Body",
			Position = UDim2.new(0, 0, 0, headerHeight),
			Size = UDim2.new(1, 0, 1, -headerHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = root,
		}, {
			New("UIPadding", {
				PaddingLeft = UDim.new(0, padding),
				PaddingRight = UDim.new(0, padding),
				PaddingTop = UDim.new(0, padding),
				PaddingBottom = UDim.new(0, padding),
			}),
		})
	end

	local self = setmetatable({
		instance = root,
		header = header,
		titleLabel = titleLabel,
		iconLabel = iconLabel,
		toolbarSlot = toolbarSlot,
		body = body,
		maid = Maid.new(),
		_toolbar = nil,
		_toolbarMaid = Maid.new(),
		_destroyed = false,
	}, Panel)

	if props.toolbar ~= nil then
		self:setToolbar(props.toolbar)
	end
	if props.enabled == false then
		self:setEnabled(false)
	end
	local parent = props.parent
	if parent then
		if parent:IsA("LayerCollector") then
			Kit.useSiblingZIndex(parent)
		end
		root.Parent = parent
	end
	return self
end

function Panel.setTitle(self: Panel, title: string)
	self.titleLabel.Text = title
end

-- Places a widget object (anything with `.instance`) or a GuiObject in the header's right slot. The previous
-- toolbar is destroyed; the panel owns (and destroys) the new one.
function Panel.setToolbar(self: Panel, toolbar: any?)
	self._toolbarMaid:clean()
	self._toolbar = toolbar
	if toolbar == nil then
		return
	end
	local gui = guiOf(toolbar)
	assert(gui, "Panel:setToolbar expects a widget object or a GuiObject")
	gui.Parent = self.toolbarSlot
	self._toolbarMaid:give(toolbar)
end

function Panel.getToolbar(self: Panel): any?
	return self._toolbar
end

-- Hands a cleanup task (connection, instance, widget, function) to the panel; it runs on destroy().
function Panel.give<T>(self: Panel, task: T): T
	return self.maid:give(task)
end

function Panel.setEnabled(self: Panel, enabled: boolean)
	self.instance.Interactable = enabled
	self.titleLabel.TextColor3 = if enabled then Theme.colors.text else Theme.colors.textMuted
	if self._toolbar and type(self._toolbar) == "table" and type(self._toolbar.setEnabled) == "function" then
		self._toolbar:setEnabled(enabled)
	end
end

function Panel.destroy(self: Panel)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._toolbarMaid:clean()
	self.maid:clean()
	self.instance:Destroy()
end

return Panel
