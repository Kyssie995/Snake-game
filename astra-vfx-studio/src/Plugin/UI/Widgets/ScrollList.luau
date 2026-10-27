--!strict
--[[
	ScrollList — virtualised vertical list. Only the rows inside the visible range (+ a small buffer) exist as
	instances; they are pooled and re-used while scrolling, so 10 000+ rows cost no more than one screen.

		local list
		list = ScrollList.new({
			rowHeight = 24,
			count = #entries,
			createRow = function(row) -- once per pooled row: build its children
				New("TextLabel", { Name = "Label", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
					Parent = row })
			end,
			render = function(row, index) -- whenever a row shows `index` (scrolling, refresh, hover)
				row.Label.Text = entries[index].name
				row.BackgroundTransparency = if list:isHovered(index) then 0 else 1
			end,
			onRowActivated = function(index, input, clickCount) ... end,
			parent = panel.body,
		})
		list:setCount(#entries)        -- data length changed (re-renders the visible rows)
		list:refresh()                 -- data changed, same length
		list:scrollToIndex(250)

	Rows are TextButtons (Text = "", AutoButtonColor = false, transparent) so they deliver Activated(input,
	clickCount) for double clicks. `render` must fully describe a row because rows are recycled.
	The visible range comes from the ScrollingFrame's AbsoluteSize/CanvasPosition and is recomputed on
	CanvasPosition/AbsoluteSize changes. Where AbsoluteSize is unavailable (Lune tests) the height is derived
	from the Size chain, or props.viewportHeight.
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)

local ScrollList = {}
ScrollList.__index = ScrollList

local DEFAULT_VIEW = Vector2.new(800, 600)

export type Props = {
	rowHeight: number?, -- default Theme.metrics.rowHeight
	count: number?,
	render: (row: TextButton, index: number, list: any) -> (),
	createRow: ((row: TextButton, list: any) -> ())?,
	onRowActivated: ((index: number, input: InputObject?, clickCount: number) -> ())?,
	onRowInput: ((index: number, input: InputObject, row: TextButton) -> ())?, -- InputBegan on a row
	onHoverChanged: ((index: number?) -> ())?,
	buffer: number?, -- extra rows above and below the visible range (default 4)
	viewportHeight: number?, -- fallback height when AbsoluteSize cannot be read
	name: string?,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

type ScrollListData = {
	instance: ScrollingFrame,
	maid: Maid.Maid,
	rowHeight: number,
	count: number,
	hoverIndex: number?,
	_props: Props,
	_buffer: number,
	_active: { [number]: TextButton },
	_rowIndex: { [TextButton]: number },
	_pool: { TextButton },
	_created: number,
	_first: number,
	_last: number,
	_enabled: boolean,
	_destroyed: boolean,
	_updating: boolean,
}

export type ScrollList = typeof(setmetatable({} :: ScrollListData, ScrollList))

-- Best-effort size of a GuiObject: AbsoluteSize when the engine provides it, otherwise resolved from the Size
-- chain (scale × parent + offset), ignoring layouts/padding. Used only for the visible-range estimate.
local function fallbackSize(inst: Instance?, depth: number): Vector2
	if inst == nil or depth > 32 or not inst:IsA("GuiObject") then
		return DEFAULT_VIEW
	end
	local gui = inst :: GuiObject
	local parentSize = fallbackSize(gui.Parent, depth + 1)
	local s = gui.Size
	return Vector2.new(parentSize.X * s.X.Scale + s.X.Offset, parentSize.Y * s.Y.Scale + s.Y.Offset)
end

local function measure(gui: GuiObject): Vector2
	local ok, size = pcall(function()
		return gui.AbsoluteSize
	end)
	if ok and typeof(size) == "Vector2" and size.Y > 0 then
		return size
	end
	return fallbackSize(gui, 0)
end
ScrollList.measure = measure

function ScrollList.new(props: Props): ScrollList
	assert(type(props.render) == "function", "ScrollList.new: props.render is required")
	local rowHeight = props.rowHeight or Theme.metrics.rowHeight
	local count = math.max(0, math.floor(props.count or 0))

	local frame = New("ScrollingFrame", {
		Name = props.name or "ScrollList",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, count * rowHeight),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = Theme.metrics.scrollBar,
		ScrollBarImageColor3 = Theme.colors.borderStrong,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Selectable = false,
		ClipsDescendants = true,
	}) :: ScrollingFrame

	local self = setmetatable({
		instance = frame,
		maid = Maid.new(),
		rowHeight = rowHeight,
		count = count,
		hoverIndex = nil,
		_props = props,
		_buffer = props.buffer or 4,
		_active = {},
		_rowIndex = {},
		_pool = {},
		_created = 0,
		_first = 1,
		_last = 0,
		_enabled = true,
		_destroyed = false,
		_updating = false,
	}, ScrollList)

	self.maid:give(frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_update(false)
	end))
	self.maid:give(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_update(false)
	end))

	if props.parent then
		frame.Parent = props.parent
	end
	self:_update(true)
	return self
end

function ScrollList._viewportHeight(self: ScrollList): number
	local ok, size = pcall(function()
		return self.instance.AbsoluteSize
	end)
	if ok and typeof(size) == "Vector2" and size.Y > 0 then
		return size.Y
	end
	return self._props.viewportHeight or fallbackSize(self.instance, 0).Y
end

function ScrollList._createRow(self: ScrollList): TextButton
	self._created += 1
	local row = New("TextButton", {
		Name = "Row",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.colors.bg3,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = false,
		Size = UDim2.new(1, 0, 0, self.rowHeight),
		ClipsDescendants = true,
		Parent = self.instance,
	}) :: TextButton
	row.Activated:Connect(function(input: InputObject?, clickCount: number?)
		local index = self._rowIndex[row]
		if index and self._enabled and self._props.onRowActivated then
			self._props.onRowActivated(index, input, clickCount or 1)
		end
	end)
	row.InputBegan:Connect(function(input: InputObject)
		local index = self._rowIndex[row]
		if index and self._enabled and self._props.onRowInput then
			self._props.onRowInput(index, input, row)
		end
	end)
	row.MouseEnter:Connect(function()
		local index = self._rowIndex[row]
		if index then
			self:_setHover(index)
		end
	end)
	row.MouseLeave:Connect(function()
		local index = self._rowIndex[row]
		if index and self.hoverIndex == index then
			self:_setHover(nil)
		end
	end)
	if self._props.createRow then
		self._props.createRow(row, self)
	end
	return row
end

function ScrollList._setHover(self: ScrollList, index: number?)
	if self.hoverIndex == index then
		return
	end
	local previous = self.hoverIndex
	self.hoverIndex = index
	if previous then
		self:refreshIndex(previous)
	end
	if index then
		self:refreshIndex(index)
	end
	if self._props.onHoverChanged then
		self._props.onHoverChanged(index)
	end
end

function ScrollList._renderRow(self: ScrollList, row: TextButton, index: number)
	row.Position = UDim2.new(0, 0, 0, (index - 1) * self.rowHeight)
	row.Visible = true
	self._props.render(row, index, self)
end

-- Recomputes the visible range; creates/recycles rows. `all` re-renders rows that stay visible too.
function ScrollList._update(self: ScrollList, all: boolean)
	if self._destroyed or self._updating then
		return
	end
	self._updating = true
	local rh = self.rowHeight
	local count = self.count
	local top = math.max(0, self.instance.CanvasPosition.Y)
	local height = self:_viewportHeight()
	local first = math.max(1, math.floor(top / rh) + 1 - self._buffer)
	local last = math.min(count, math.ceil((top + height) / rh) + self._buffer)

	-- recycle rows that left the range
	local leaving = {}
	for index in self._active do
		if index < first or index > last then
			table.insert(leaving, index)
		end
	end
	for _, index in leaving do
		local row = self._active[index]
		self._active[index] = nil
		self._rowIndex[row] = nil
		row.Visible = false
		table.insert(self._pool, row)
	end
	if self.hoverIndex and (self.hoverIndex :: number) > count then
		self.hoverIndex = nil
	end

	local ok, err = pcall(function()
		for index = first, last do
			local existing: TextButton? = self._active[index]
			if existing then
				if all then
					self:_renderRow(existing, index)
				end
			else
				local row = table.remove(self._pool) or self:_createRow()
				self._active[index] = row
				self._rowIndex[row] = index
				self:_renderRow(row, index)
			end
		end
	end)
	self._first = first
	self._last = last
	self._updating = false
	if not ok then
		error(err, 0)
	end
end

-- Changes the number of rows (CanvasSize = count × rowHeight) and re-renders the visible rows.
function ScrollList.setCount(self: ScrollList, count: number)
	count = math.max(0, math.floor(count))
	self.count = count
	self.instance.CanvasSize = UDim2.new(0, 0, 0, count * self.rowHeight)
	local maxTop = math.max(0, count * self.rowHeight - self:_viewportHeight())
	local pos = self.instance.CanvasPosition
	if pos.Y > maxTop then
		self._updating = true -- the property signal would update with stale data; we update below
		self.instance.CanvasPosition = Vector2.new(pos.X, maxTop)
		self._updating = false
	end
	self:_update(true)
end

-- Re-renders every visible row (data changed).
function ScrollList.refresh(self: ScrollList)
	self:_update(true)
end

-- Re-renders one row if it is currently instantiated.
function ScrollList.refreshIndex(self: ScrollList, index: number)
	local row = self._active[index]
	if row and not self._destroyed then
		self:_renderRow(row, index)
	end
end

-- Scrolls so that `index` is visible. align: "nearest" (default), "top" or "center".
function ScrollList.scrollToIndex(self: ScrollList, index: number, align: string?)
	if self.count == 0 then
		return
	end
	index = math.clamp(math.floor(index), 1, self.count)
	local rh = self.rowHeight
	local height = self:_viewportHeight()
	local top = self.instance.CanvasPosition.Y
	local rowTop = (index - 1) * rh
	local target = top
	if align == "center" then
		target = rowTop - (height - rh) / 2
	elseif align == "top" or rowTop < top then
		target = rowTop
	elseif rowTop + rh > top + height then
		target = rowTop + rh - height
	end
	target = math.clamp(target, 0, math.max(0, self.count * rh - height))
	if target ~= top then
		self.instance.CanvasPosition = Vector2.new(self.instance.CanvasPosition.X, target)
	end
	self:_update(false)
end

-- First/last index of the instantiated range (including the buffer).
function ScrollList.getVisibleRange(self: ScrollList): (number, number)
	return self._first, self._last
end

-- Index currently shown by a row instance (nil for pooled rows).
function ScrollList.indexOf(self: ScrollList, row: Instance): number?
	return self._rowIndex[row :: any]
end

function ScrollList.rowAt(self: ScrollList, index: number): TextButton?
	return self._active[index]
end

-- Number of row instances that are currently shown.
function ScrollList.visibleRowCount(self: ScrollList): number
	local n = 0
	for _ in self._active do
		n += 1
	end
	return n
end

-- Number of row instances ever created (shown + pooled).
function ScrollList.createdRowCount(self: ScrollList): number
	return self._created
end

-- Row index under a canvas-space y coordinate (nil outside the rows).
function ScrollList.indexAtCanvasY(self: ScrollList, y: number): number?
	local index = math.floor(y / self.rowHeight) + 1
	if index < 1 or index > self.count then
		return nil
	end
	return index
end

-- Converts a widget-relative mouse position into canvas space (y measured from the top of row 1).
function ScrollList.toCanvas(self: ScrollList, pos: Vector2): Vector2
	local ok, abs = pcall(function()
		return self.instance.AbsolutePosition
	end)
	local origin = if ok and typeof(abs) == "Vector2" then abs else Vector2.zero
	return pos - origin + self.instance.CanvasPosition
end

function ScrollList.isHovered(self: ScrollList, index: number): boolean
	return self.hoverIndex == index
end

function ScrollList.setEnabled(self: ScrollList, enabled: boolean)
	self._enabled = enabled
	self.instance.ScrollingEnabled = enabled
	self.instance.Interactable = enabled
end

function ScrollList.isEnabled(self: ScrollList): boolean
	return self._enabled
end

function ScrollList.destroy(self: ScrollList)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.maid:clean()
	table.clear(self._active)
	table.clear(self._rowIndex)
	table.clear(self._pool)
	self.instance:Destroy()
end

return ScrollList
