--!strict
--[[
	Tree — virtualised tree view on top of ScrollList. The caller owns the data: `items()` returns the FLATTENED,
	currently visible rows (children of collapsed items omitted) and the tree reports user intent through
	callbacks, then re-reads `items()` (refresh) after each callback.

		local tree = Tree.new({
			host = host,                                       -- { plugin, widget, root } (drag & drop, popups)
			items = function()                                 -- flattened visible rows, in display order
				return { { id = "a", label = "Burst", depth = 0, expandable = true, expanded = true,
				           icon = "◆", color = Theme.categoryColor("Particles"), selected = true }, ... }
			end,
			onToggle = function(id, expanded) state.expanded[id] = expanded end,
			onSelect = function(ids, mode, clickedId) editor:select("components", ids, mode) end,
			onRename = function(id, newName) ... end,          -- double click (or tree:beginRename(id)) edits inline
			onContext = function(id, input) menus:open(...) end, -- right click; id = nil on empty space
			onDragDrop = function(ids, targetId, position) ... end, -- position "before" | "after" | "inside"
			parent = panel.body,
		})
		tree:refresh()                                         -- after external data changes

	Selection modes passed to onSelect (they match Editor:select): plain click → ({id}, "replace"); Ctrl → ({id},
	"toggle"); Shift → (range from the anchor, "replace"); Ctrl+Shift → (range, "add"); click on empty space →
	({}, "replace"). Right click on an unselected row selects it first.
	onSelect also receives the click modifiers ({ ctrl, shift, alt }) as a fourth argument.
	Keyboard: tree:handleKey(keyCode, mods) from the panel's input catcher (arrows, Home/End, F2).
	Drag & drop (needs props.host and onDragDrop): dragging a selected row drags the whole visible selection.
	"inside" is offered for rows with `droppable = true` (default: `expandable`). Dropping onto a dragged row or
	one of its descendants is rejected; `canDrop(ids, targetId, position)` can veto further targets.
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)
local Input = require(script.Parent.Parent.Input)
local ScrollList = require(script.Parent.ScrollList)
local Kit = require(script.Parent.ControlKit)

local Tree = {}
Tree.__index = Tree

export type TreeItem = {
	id: string,
	label: string,
	icon: string?, -- glyph text or an image ("rbxassetid://…")
	color: Color3?, -- icon colour
	depth: number?,
	expandable: boolean?,
	expanded: boolean?,
	selected: boolean?,
	muted: boolean?, -- disabled / hidden components: dimmed label
	hint: string?, -- right-aligned dim text (type name, count, …)
	renamable: boolean?, -- default true
	droppable: boolean?, -- accepts "inside" drops (default: expandable)
}

export type DropPosition = "before" | "after" | "inside"
export type SelectMode = "replace" | "toggle" | "add"

export type Props = {
	items: () -> { TreeItem },
	host: any?,
	rowHeight: number?,
	indent: number?,
	onToggle: ((id: string, expanded: boolean) -> ())?,
	onSelect: ((ids: { string }, mode: SelectMode, clickedId: string?, mods: Input.Mods) -> ())?,
	onActivate: ((id: string) -> ())?, -- double click when no onRename is given
	onRename: ((id: string, newLabel: string) -> ())?,
	onContext: ((id: string?, input: InputObject) -> ())?,
	onDragDrop: ((ids: { string }, targetId: string, position: DropPosition) -> ())?,
	canDrop: ((ids: { string }, targetId: string, position: DropPosition) -> boolean)?,
	emptyText: string?,
	enabled: boolean?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

type DragState = {
	ids: { string },
	excluded: { [string]: boolean }, -- dragged rows and their (flattened) descendants: never valid targets
	targetId: string?,
	position: DropPosition?,
	valid: boolean,
}

type TreeData = {
	instance: Frame,
	list: ScrollList.ScrollList,
	maid: Maid.Maid,
	indicator: Frame,
	_props: Props,
	_items: { TreeItem },
	_indexById: { [string]: number },
	_anchor: string?, -- fixed end of shift ranges
	_cursor: string?, -- moving end (keyboard navigation)
	_pendingClick: string?,
	_drag: DragState?,
	_renaming: { id: string, box: TextBox }?,
	_emptyLabel: TextLabel,
	_indent: number,
	_enabled: boolean,
	_destroyed: boolean,
}

export type Tree = typeof(setmetatable({} :: TreeData, Tree))

local EXPANDER_WIDTH = 16
local ICON_WIDTH = 18

local function isImage(icon: string): boolean
	return string.sub(icon, 1, 3) == "rbx" or string.sub(icon, 1, 4) == "http"
end

local function NO_MODS(): Input.Mods
	return { ctrl = false, shift = false, alt = false }
end

local function modsOf(input: InputObject?): Input.Mods
	if input == nil then
		return NO_MODS()
	end
	local ok, mods = pcall(Input.mods, input :: InputObject)
	return if ok then mods else NO_MODS()
end

function Tree.new(props: Props): Tree
	assert(type(props.items) == "function", "Tree.new: props.items must be a function")
	local rowHeight = props.rowHeight or Theme.metrics.rowHeight

	local root = New("Frame", {
		Name = props.name or "Tree",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}) :: Frame

	local self: Tree
	local list = ScrollList.new({
		rowHeight = rowHeight,
		count = 0,
		createRow = function(row: TextButton)
			self:_createRow(row)
		end,
		render = function(row: TextButton, index: number)
			self:_renderRow(row, index)
		end,
		onRowActivated = function(index: number, input: InputObject?, clickCount: number)
			self:_rowActivated(index, input, clickCount)
		end,
		onRowInput = function(index: number, input: InputObject)
			self:_rowInput(index, input)
		end,
		parent = root,
	})

	local indicator = New("Frame", {
		Name = "DropIndicator",
		Visible = false,
		BackgroundColor3 = Theme.colors.accent,
		BorderSizePixel = 0,
		ZIndex = 10,
		Size = UDim2.new(1, 0, 0, 2),
		Parent = list.instance,
	}, {
		New("UIStroke", {
			Name = "InsideStroke",
			Color = Theme.colors.accent,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Enabled = false,
		}),
	}) :: Frame

	local emptyLabel = New("TextLabel", {
		Name = "Empty",
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.fromOffset(8, 8),
		Text = props.emptyText or "",
		TextColor3 = Theme.colors.textMuted,
		TextSize = Theme.textSize.small,
		FontFace = Theme.fonts.regular,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = root,
	}) :: TextLabel

	self = setmetatable({
		instance = root,
		list = list,
		maid = Maid.new(),
		indicator = indicator,
		_props = props,
		_items = {},
		_indexById = {},
		_anchor = nil,
		_cursor = nil,
		_pendingClick = nil,
		_drag = nil,
		_renaming = nil,
		_emptyLabel = emptyLabel,
		_indent = props.indent or Theme.metrics.indent,
		_enabled = true,
		_destroyed = false,
	}, Tree)
	self.maid:give(list)

	-- clicks on the empty area below the rows
	self.maid:give(list.instance.InputBegan:Connect(function(input: InputObject)
		self:_backgroundInput(input)
	end))

	-- parent first so the first visible-range estimate sees the real size
	if props.parent then
		root.Parent = props.parent
	end
	if props.enabled == false then
		self._enabled = false
		self.list:setEnabled(false)
	end
	self:refresh()
	return self
end

-- Re-reads props.items() and re-renders.
function Tree.refresh(self: Tree)
	if self._destroyed then
		return
	end
	local items: { TreeItem } = self._props.items() or {}
	self._items = items
	local byId = {}
	for i, item in items do
		byId[item.id] = i
	end
	self._indexById = byId
	if self._renaming and byId[self._renaming.id] == nil then
		self:endRename(false)
	end
	self._emptyLabel.Visible = #items == 0 and (self._props.emptyText or "") ~= ""
	local drag = self._drag
	if drag then
		drag.excluded = self:_excludedSet(drag.ids)
	end
	self.list:setCount(#items)
	if self._renaming then
		self:_placeRenameBox()
	end
end

function Tree.getItems(self: Tree): { TreeItem }
	return self._items
end

function Tree.indexOf(self: Tree, id: string): number?
	return self._indexById[id]
end

function Tree.scrollTo(self: Tree, id: string)
	local index = self._indexById[id]
	if index then
		self.list:scrollToIndex(index)
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- rows

function Tree._createRow(self: Tree, row: TextButton)
	local rh = self.list.rowHeight
	local expander = New("TextButton", {
		Name = "Expander",
		Size = UDim2.new(0, EXPANDER_WIDTH, 1, 0),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "▶",
		TextColor3 = Theme.colors.textDim,
		TextSize = 8,
		FontFace = Theme.fonts.regular,
		Selectable = false,
		Parent = row,
	}) :: TextButton
	expander.Activated:Connect(function()
		local index = self.list:indexOf(row)
		if index then
			self:_toggle(index)
		end
	end)
	New("ImageLabel", {
		Name = "IconImage",
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		Parent = row,
	})
	New("TextLabel", {
		Name = "IconGlyph",
		Size = UDim2.new(0, 14, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = Theme.textSize.small,
		FontFace = Theme.fonts.medium,
		Visible = false,
		Parent = row,
	})
	New("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		TextColor3 = Theme.colors.text,
		TextSize = Theme.textSize.normal,
		FontFace = Theme.fonts.regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	New("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(0, 80, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Theme.colors.textMuted,
		TextSize = Theme.textSize.tiny,
		FontFace = Theme.fonts.regular,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	-- selection accent on the left edge
	New("Frame", {
		Name = "SelectionBar",
		Size = UDim2.new(0, 2, 0, rh),
		BackgroundColor3 = Theme.colors.accent,
		BorderSizePixel = 0,
		Visible = false,
		Parent = row,
	})

	local host = self._props.host
	if host and host.widget and self._props.onDragDrop then
		local handle = Input.drag(host.widget, row, {
			onPress = function(_pos: Vector2, mods: Input.Mods)
				local index = self.list:indexOf(row)
				if index then
					self:_press(index, mods)
				end
			end,
			onClick = function()
				self:_releaseClick()
			end,
			onStart = function()
				self:_dragStart(row)
			end,
			onMove = function(pos: Vector2)
				self:_dragMove(pos)
			end,
			onEnd = function(_pos: Vector2, cancelled: boolean, moved: boolean)
				self:_dragEnd(cancelled, moved)
			end,
		})
		self.maid:give(handle)
	end
end

function Tree._renderRow(self: Tree, row: TextButton, index: number)
	local item = self._items[index]
	if item == nil then
		return
	end
	local depth = item.depth or 0
	local x = 4 + depth * self._indent
	local hovered = self.list:isHovered(index)
	local dragSource = self._drag ~= nil and table.find((self._drag :: DragState).ids, item.id) ~= nil

	if item.selected then
		row.BackgroundColor3 = Theme.colors.selection
		row.BackgroundTransparency = 0
	elseif hovered and self._enabled then
		row.BackgroundColor3 = Theme.colors.bg3
		row.BackgroundTransparency = 0
	else
		row.BackgroundTransparency = 1
	end
	local bar = row:FindFirstChild("SelectionBar") :: Frame
	bar.Visible = item.selected == true

	local expander = row:FindFirstChild("Expander") :: TextButton
	expander.Position = UDim2.fromOffset(x, 0)
	expander.Visible = item.expandable == true
	expander.Rotation = if item.expanded then 90 else 0
	expander.TextColor3 = if hovered then Theme.colors.text else Theme.colors.textDim
	x += EXPANDER_WIDTH

	local image = row:FindFirstChild("IconImage") :: ImageLabel
	local glyph = row:FindFirstChild("IconGlyph") :: TextLabel
	local icon = item.icon
	local iconColor = item.color or Theme.colors.textDim
	if icon and icon ~= "" then
		if isImage(icon) then
			image.Visible = true
			glyph.Visible = false
			image.Image = icon
			image.ImageColor3 = iconColor
			image.ImageTransparency = if item.muted then 0.5 else 0
			image.Position = UDim2.new(0, x, 0.5, 0)
		else
			glyph.Visible = true
			image.Visible = false
			glyph.Text = icon
			glyph.TextColor3 = iconColor
			glyph.TextTransparency = if item.muted then 0.5 else 0
			glyph.Position = UDim2.fromOffset(x, 0)
		end
		x += ICON_WIDTH
	else
		image.Visible = false
		glyph.Visible = false
	end

	local hint = row:FindFirstChild("Hint") :: TextLabel
	local hintText = item.hint or ""
	hint.Text = hintText
	hint.Visible = hintText ~= ""
	local hintWidth = if hintText ~= "" then 86 else 4

	local label = row:FindFirstChild("Label") :: TextLabel
	label.Text = item.label
	label.Position = UDim2.fromOffset(x + 2, 0)
	label.Size = UDim2.new(1, -(x + 2 + hintWidth), 1, 0)
	label.TextColor3 = if item.muted then Theme.colors.textMuted else Theme.colors.text
	label.TextTransparency = if dragSource then 0.5 else 0
	label.FontFace = if item.selected then Theme.fonts.medium else Theme.fonts.regular
	label.Visible = not (self._renaming ~= nil and (self._renaming :: any).id == item.id)
end

-- ---------------------------------------------------------------------------------------------------------------
-- interaction

function Tree._toggle(self: Tree, index: number)
	local item = self._items[index]
	if not item or not item.expandable or not self._enabled then
		return
	end
	if self._props.onToggle then
		self._props.onToggle(item.id, not item.expanded)
	end
	self:refresh()
end

function Tree._emitSelect(self: Tree, ids: { string }, mode: SelectMode, clickedId: string?, mods: Input.Mods?)
	self._cursor = clickedId
	if self._props.onSelect then
		self._props.onSelect(ids, mode, clickedId, mods or NO_MODS())
	end
	self:refresh()
end

-- Applies a selection click on `index` with modifiers.
function Tree._click(self: Tree, index: number, mods: Input.Mods)
	local item = self._items[index]
	if not item then
		return
	end
	local anchorIndex = if self._anchor then self._indexById[self._anchor :: string] else nil
	if mods.shift and anchorIndex then
		local a, b = math.min(anchorIndex, index), math.max(anchorIndex, index)
		local ids = {}
		for i = a, b do
			table.insert(ids, self._items[i].id)
		end
		self:_emitSelect(ids, if mods.ctrl then "add" else "replace", item.id, mods)
	elseif mods.ctrl then
		self._anchor = item.id
		self:_emitSelect({ item.id }, "toggle", item.id, mods)
	else
		self._anchor = item.id
		self:_emitSelect({ item.id }, "replace", item.id, mods)
	end
end

-- Mouse button 1 pressed on a row. A plain press on an already selected row defers the selection change to the
-- release, so the whole selection can be dragged.
function Tree._press(self: Tree, index: number, mods: Input.Mods)
	if not self._enabled then
		return
	end
	if self._renaming then
		self:endRename(true)
	end
	local item = self._items[index]
	if not item then
		return
	end
	if item.selected and not mods.ctrl and not mods.shift and self._props.onDragDrop then
		self._pendingClick = item.id
	else
		self._pendingClick = nil
		self:_click(index, mods)
	end
end

function Tree._releaseClick(self: Tree)
	local id = self._pendingClick
	self._pendingClick = nil
	if id then
		local index = self._indexById[id]
		if index then
			self:_click(index, NO_MODS())
		end
	end
end

function Tree._rowInput(self: Tree, index: number, input: InputObject)
	if not self._enabled then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 then
		-- with drag & drop enabled, Input.drag's onPress handles the press
		local host = self._props.host
		if not (host and host.widget and self._props.onDragDrop) then
			self:_press(index, modsOf(input))
		end
	elseif kind == Enum.UserInputType.MouseButton2 then
		local item = self._items[index]
		if not item then
			return
		end
		if not item.selected then
			self._anchor = item.id
			self:_emitSelect({ item.id }, "replace", item.id)
		end
		if self._props.onContext then
			self._props.onContext(item.id, input)
		end
	end
end

function Tree._rowActivated(self: Tree, index: number, _input: InputObject?, clickCount: number)
	if clickCount < 2 or not self._enabled then
		return
	end
	local item = self._items[index]
	if not item then
		return
	end
	if self._props.onRename and item.renamable ~= false then
		self:beginRename(item.id)
	elseif self._props.onActivate then
		self._props.onActivate(item.id)
	elseif item.expandable then
		self:_toggle(index)
	end
end

-- Input on the scrolling frame itself: only presses below the last row count as "empty space".
function Tree._backgroundInput(self: Tree, input: InputObject)
	if not self._enabled then
		return
	end
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.MouseButton2 then
		return
	end
	local host = self._props.host
	local pos: Vector2
	if host and host.widget then
		pos = Input.mousePosition(host.widget)
	else
		local p = input.Position
		pos = Vector2.new(p.X, p.Y)
	end
	local framePos, frameSize = Kit.geometry(self.list.instance)
	if pos.X >= framePos.X + frameSize.X - Theme.metrics.scrollBar - 2 then
		return -- scroll bar
	end
	local canvas = self.list:toCanvas(pos)
	if canvas.Y < #self._items * self.list.rowHeight then
		return -- a row handles it
	end
	if kind == Enum.UserInputType.MouseButton1 then
		if self._renaming then
			self:endRename(true)
		end
		self._anchor = nil
		self:_emitSelect({}, "replace", nil)
	elseif self._props.onContext then
		self._props.onContext(nil, input)
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- keyboard

-- Selects items[index] like a click (shift extends the range from the anchor) and scrolls it into view.
function Tree._moveTo(self: Tree, index: number, shift: boolean)
	local item = self._items[index]
	if not item then
		return
	end
	self.list:scrollToIndex(index)
	local anchorIndex = if self._anchor then self._indexById[self._anchor :: string] else nil
	if shift and anchorIndex then
		local a, b = math.min(anchorIndex, index), math.max(anchorIndex, index)
		local ids = {}
		for i = a, b do
			table.insert(ids, self._items[i].id)
		end
		self:_emitSelect(ids, "replace", item.id, { ctrl = false, shift = true, alt = false })
	else
		self._anchor = item.id
		self:_emitSelect({ item.id }, "replace", item.id)
	end
end

--[[
	Keyboard navigation for the panel's input catcher (UI/Input.onKey). Returns true when the key was handled.
	Up/Down move the selection (Shift extends it), Home/End jump, Left collapses or goes to the parent, Right
	expands or goes to the first child, F2 renames.
]]
function Tree.handleKey(self: Tree, keyCode: Enum.KeyCode, mods: Input.Mods?): boolean
	if not self._enabled or self._renaming or #self._items == 0 then
		return false
	end
	local m: Input.Mods = mods or NO_MODS()
	local count = #self._items
	local current = if self._cursor then self._indexById[self._cursor :: string] else nil
	if current == nil then
		for i, item in self._items do
			if item.selected then
				current = i
				break
			end
		end
	end
	if keyCode == Enum.KeyCode.Down then
		self:_moveTo(if current then math.min(count, current + 1) else 1, m.shift)
	elseif keyCode == Enum.KeyCode.Up then
		self:_moveTo(if current then math.max(1, current - 1) else count, m.shift)
	elseif keyCode == Enum.KeyCode.Home then
		self:_moveTo(1, m.shift)
	elseif keyCode == Enum.KeyCode.End then
		self:_moveTo(count, m.shift)
	elseif keyCode == Enum.KeyCode.Left and current then
		local item = self._items[current]
		if item.expandable and item.expanded then
			self:_toggle(current)
		else
			local depth = item.depth or 0
			for i = current - 1, 1, -1 do
				if (self._items[i].depth or 0) < depth then
					self:_moveTo(i, false)
					break
				end
			end
		end
	elseif keyCode == Enum.KeyCode.Right and current then
		local item = self._items[current]
		if item.expandable and not item.expanded then
			self:_toggle(current)
		elseif item.expandable and current < count then
			self:_moveTo(current + 1, false)
		end
	elseif keyCode == Enum.KeyCode.F2 and current then
		self:beginRename(self._items[current].id)
	else
		return false
	end
	return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- drag & drop

function Tree._dragStart(self: Tree, row: TextButton)
	local index = self.list:indexOf(row)
	if not index or not self._enabled then
		return
	end
	local item = self._items[index]
	local ids = {}
	if item.selected then
		for _, it in self._items do
			if it.selected then
				table.insert(ids, it.id)
			end
		end
	else
		ids = { item.id }
	end
	self._pendingClick = nil
	self._drag = { ids = ids, excluded = self:_excludedSet(ids), targetId = nil, position = nil, valid = false }
	self.list:refresh()
end

-- Ids of the dragged rows and all rows below them in the flattened order (their descendants). One O(n) pass at
-- drag start (and on refresh during a drag), so validating a target per mouse move is O(1).
function Tree._excludedSet(self: Tree, ids: { string }): { [string]: boolean }
	local dragged: { [string]: boolean } = {}
	for _, id in ids do
		dragged[id] = true
	end
	local excluded: { [string]: boolean } = {}
	local subtreeDepth: number? = nil -- depth of the dragged row whose subtree is being walked
	for _, item in self._items do
		local depth = item.depth or 0
		if subtreeDepth ~= nil and depth <= subtreeDepth then
			subtreeDepth = nil
		end
		if subtreeDepth ~= nil then
			excluded[item.id] = true
		elseif dragged[item.id] then
			excluded[item.id] = true
			subtreeDepth = depth
		end
	end
	return excluded
end

-- true when items[index] is one of the dragged rows or a descendant of one (in the flattened order).
function Tree._isDraggedOrDescendant(self: Tree, index: number, ids: { string }): boolean
	local item = self._items[index]
	if item == nil then
		return false
	end
	local drag = self._drag
	local excluded = if drag and drag.ids == ids then drag.excluded else self:_excludedSet(ids)
	return excluded[item.id] == true
end

-- Computes target row and drop position for a widget-relative mouse position.
function Tree.dropTargetAt(self: Tree, pos: Vector2): (string?, DropPosition?)
	local count = #self._items
	if count == 0 then
		return nil, nil
	end
	local rh = self.list.rowHeight
	local y = self.list:toCanvas(pos).Y
	if y < 0 then
		return self._items[1].id, "before"
	elseif y >= count * rh then
		return self._items[count].id, "after"
	end
	local index = math.floor(y / rh) + 1
	local item = self._items[index]
	local frac = (y - (index - 1) * rh) / rh
	local container = if item.droppable ~= nil then item.droppable else item.expandable == true
	if container then
		if frac < 0.25 then
			return item.id, "before"
		elseif frac > 0.75 then
			return item.id, "after"
		end
		return item.id, "inside"
	end
	if frac < 0.5 then
		return item.id, "before"
	end
	return item.id, "after"
end

function Tree._dragMove(self: Tree, pos: Vector2)
	local drag = self._drag
	if not drag then
		return
	end
	local targetId, rawPosition = self:dropTargetAt(pos)
	local position: DropPosition? = rawPosition :: any
	local valid = false
	if targetId and position then
		local index = self._indexById[targetId]
		valid = index ~= nil and not self:_isDraggedOrDescendant(index, drag.ids)
		if valid and self._props.canDrop then
			valid = self._props.canDrop(drag.ids, targetId, position) == true
		end
	end
	drag.targetId = targetId
	drag.position = position
	drag.valid = valid
	self:_placeIndicator()
	self:_autoScroll(pos)
end

function Tree._placeIndicator(self: Tree)
	local drag = self._drag
	local indicator = self.indicator
	local stroke = indicator:FindFirstChild("InsideStroke") :: UIStroke
	if not drag or not drag.valid or not drag.targetId then
		indicator.Visible = false
		return
	end
	local index = self._indexById[drag.targetId :: string]
	if not index then
		indicator.Visible = false
		return
	end
	local rh = self.list.rowHeight
	local item = self._items[index]
	local x = 4 + (item.depth or 0) * self._indent + EXPANDER_WIDTH
	indicator.Visible = true
	if drag.position == "inside" then
		indicator.BackgroundTransparency = 0.85
		stroke.Enabled = true
		indicator.Position = UDim2.fromOffset(1, (index - 1) * rh + 1)
		indicator.Size = UDim2.new(1, -2, 0, rh - 2)
	else
		indicator.BackgroundTransparency = 0
		stroke.Enabled = false
		local y = if drag.position == "before" then (index - 1) * rh else index * rh
		indicator.Position = UDim2.fromOffset(x, y - 1)
		indicator.Size = UDim2.new(1, -x, 0, 2)
	end
end

function Tree._autoScroll(self: Tree, pos: Vector2)
	local frame = self.list.instance
	local ok, abs = pcall(function()
		return frame.AbsolutePosition
	end)
	if not ok then
		return
	end
	local height = ScrollList.measure(frame).Y
	local localY = pos.Y - (abs :: Vector2).Y
	local rh = self.list.rowHeight
	local step = 0
	if localY < rh * 0.75 then
		step = -rh / 2
	elseif localY > height - rh * 0.75 then
		step = rh / 2
	end
	if step ~= 0 then
		local maxTop = math.max(0, #self._items * rh - height)
		local current = frame.CanvasPosition
		frame.CanvasPosition = Vector2.new(current.X, math.clamp(current.Y + step, 0, maxTop))
	end
end

function Tree._dragEnd(self: Tree, cancelled: boolean, moved: boolean)
	local drag = self._drag
	self._drag = nil
	self.indicator.Visible = false
	if not drag then
		return
	end
	if moved and not cancelled and drag.valid and drag.targetId and drag.position and self._props.onDragDrop then
		self._props.onDragDrop(drag.ids, drag.targetId :: string, drag.position :: DropPosition)
	end
	self:refresh()
end

function Tree.isDragging(self: Tree): boolean
	return self._drag ~= nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- inline rename

function Tree._placeRenameBox(self: Tree)
	local renaming = self._renaming
	if not renaming then
		return
	end
	local index = self._indexById[renaming.id]
	if not index then
		return
	end
	local item = self._items[index]
	local rh = self.list.rowHeight
	local x = 4
		+ (item.depth or 0) * self._indent
		+ EXPANDER_WIDTH
		+ (if item.icon and item.icon ~= "" then ICON_WIDTH else 0)
	renaming.box.Position = UDim2.fromOffset(x, (index - 1) * rh + 2)
	renaming.box.Size = UDim2.new(1, -(x + 6), 0, rh - 4)
end

-- Starts inline editing of an item's label. Commits on Enter / focus loss, cancels on Escape.
function Tree.beginRename(self: Tree, id: string)
	if not self._props.onRename or not self._enabled then
		return
	end
	if self._renaming then
		self:endRename(true)
	end
	local index = self._indexById[id]
	if not index then
		return
	end
	self.list:scrollToIndex(index)
	local item = self._items[index]
	local box = New("TextBox", {
		Name = "RenameBox",
		ZIndex = 5,
		Text = item.label,
		ClearTextOnFocus = false,
		BackgroundColor3 = Theme.colors.bg2,
		BorderSizePixel = 0,
		TextColor3 = Theme.colors.text,
		TextSize = Theme.textSize.normal,
		FontFace = Theme.fonts.regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClipsDescendants = true,
		Parent = self.list.instance,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0, Theme.metrics.corner) }),
		New("UIStroke", { Color = Theme.colors.accent, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		New("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
	}) :: TextBox
	self._renaming = { id = id, box = box }
	self:_placeRenameBox()
	box.FocusLost:Connect(function(_enterPressed: boolean, cause: InputObject?)
		local cancelled = cause ~= nil and (cause :: any).KeyCode == Enum.KeyCode.Escape
		if self._renaming and self._renaming.box == box then
			self:endRename(not cancelled)
		end
	end)
	self.list:refreshIndex(index)
	box:CaptureFocus()
end

-- Ends inline editing; commit = true calls onRename when the text changed and is not blank.
function Tree.endRename(self: Tree, commit: boolean)
	local renaming = self._renaming
	if not renaming then
		return
	end
	self._renaming = nil
	local box = renaming.box
	local text = string.gsub(string.gsub(box.Text, "^%s+", ""), "%s+$", "")
	box:Destroy()
	local index = self._indexById[renaming.id]
	local item = if index then self._items[index] else nil
	if commit and item and text ~= "" and text ~= item.label and self._props.onRename then
		self._props.onRename(renaming.id, text)
		self:refresh()
	elseif index then
		self.list:refreshIndex(index)
	end
end

function Tree.isRenaming(self: Tree): boolean
	return self._renaming ~= nil
end

-- ---------------------------------------------------------------------------------------------------------------

function Tree.setEnabled(self: Tree, enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self:endRename(false)
	end
	self.list:setEnabled(enabled)
	self.list:refresh()
end

function Tree.destroy(self: Tree)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._renaming = nil
	self._drag = nil
	self.maid:clean()
	self.instance:Destroy()
end

return Tree
