--!strict
--[[
	Splitter — two panes separated by a draggable divider.

		local split = Splitter.new({
			direction = "horizontal",       -- "horizontal": first | second side by side; "vertical": first above second
			ratio = 0.3,                    -- share of the first pane (0..1)
			minFirst = 160, minSecond = 240, -- minimum pane sizes in px
			host = host,                    -- { plugin, widget, root }; needed for dragging
			onChange = function(ratio, final) settings:set("explorerSplit", ratio) end,
			parent = panel.body,
		})
		tree.instance.Parent = split.first
		inspector.instance.Parent = split.second
		split:setRatio(0.5)                 -- no callback
		print(split:getRatio())

	Dragging polls widget:GetRelativeMousePosition() (UI/Input.drag); onChange(ratio, false) while dragging and
	onChange(ratio, true) once on release. Double-clicking the divider restores props.ratio (default 0.5).
	Min sizes are enforced against the measured size (AbsoluteSize; Size offsets where no layout engine exists).
]]

local Theme = require(script.Parent.Parent.Theme)
local New = require(script.Parent.Parent.New)
local Maid = require(script.Parent.Parent.Maid)
local Input = require(script.Parent.Parent.Input)
local Kit = require(script.Parent.ControlKit)

local Splitter = {}
Splitter.__index = Splitter

export type Direction = "horizontal" | "vertical"

export type Props = {
	direction: Direction?, -- default "horizontal"
	ratio: number?, -- default 0.5
	minFirst: number?, -- px (default 60)
	minSecond: number?, -- px (default 60)
	dividerSize: number?, -- hit area thickness in px (default 6); the visible line is 1px
	host: any?,
	enabled: boolean?,
	onChange: ((ratio: number, final: boolean) -> ())?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

type SplitterData = {
	instance: Frame,
	first: Frame,
	second: Frame,
	divider: TextButton,
	maid: Maid.Maid,
	direction: Direction,
	_props: Props,
	_ratio: number,
	_defaultRatio: number,
	_dragStartRatio: number,
	_dragging: boolean,
	_hovered: boolean,
	_enabled: boolean,
	_destroyed: boolean,
}

export type Splitter = typeof(setmetatable({} :: SplitterData, Splitter))

function Splitter.new(props: Props): Splitter
	local direction: Direction = props.direction or "horizontal"
	local horizontal = direction == "horizontal"
	local thickness = props.dividerSize or 6

	local root = New("Frame", {
		Name = props.name or "Splitter",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}) :: Frame

	local first = New("Frame", {
		Name = "First",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = root,
	}) :: Frame
	local second = New("Frame", {
		Name = "Second",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = root,
	}) :: Frame

	local divider = New("TextButton", {
		Name = "Divider",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = false,
		ZIndex = 5,
		Size = if horizontal then UDim2.new(0, thickness, 1, 0) else UDim2.new(1, 0, 0, thickness),
		AnchorPoint = if horizontal then Vector2.new(0.5, 0) else Vector2.new(0, 0.5),
		Parent = root,
	}, {
		New("Frame", {
			Name = "Line",
			BackgroundColor3 = Theme.colors.border,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = if horizontal then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1),
		}),
	}) :: TextButton

	local initial = math.clamp(props.ratio or 0.5, 0, 1)
	local self = setmetatable({
		instance = root,
		first = first,
		second = second,
		divider = divider,
		maid = Maid.new(),
		direction = direction,
		_props = props,
		_ratio = initial,
		_defaultRatio = initial,
		_dragStartRatio = initial,
		_dragging = false,
		_hovered = false,
		_enabled = true,
		_destroyed = false,
	}, Splitter)

	local host = props.host
	self.maid:give(divider.MouseEnter:Connect(function()
		self._hovered = true
		if self._enabled then
			Kit.setCursor(host, if horizontal then "SplitEW" else "SplitNS")
		end
		self:_refreshLine()
	end))
	self.maid:give(divider.MouseLeave:Connect(function()
		self._hovered = false
		if not self._dragging then
			Kit.setCursor(host, nil)
		end
		self:_refreshLine()
	end))
	self.maid:give(divider.Activated:Connect(function(_input: InputObject?, clickCount: number?)
		if self._enabled and (clickCount or 1) >= 2 then
			self:setRatio(self._defaultRatio)
			self:_emit(true)
		end
	end))
	if host and host.widget then
		self.maid:give(Input.drag(host.widget, divider, {
			onStart = function()
				if not self._enabled then
					return
				end
				self._dragging = true
				self._dragStartRatio = self._ratio
				self:_refreshLine()
			end,
			onMove = function(_pos: Vector2, delta: Vector2)
				if not self._dragging then
					return
				end
				local total = self:_total()
				if total <= 0 then
					return
				end
				local d = if horizontal then delta.X else delta.Y
				local before = self._ratio
				self:_apply(self._dragStartRatio + d / total)
				if self._ratio ~= before then
					self:_emit(false)
				end
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, moved: boolean)
				if not self._dragging then
					return
				end
				self._dragging = false
				if not self._hovered then
					Kit.setCursor(host, nil)
				end
				self:_refreshLine()
				if moved then
					self:_emit(true)
				end
			end,
		}))
	end
	self.maid:give(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_apply(self._ratio)
	end))

	self:_apply(initial)
	if props.enabled == false then
		self:setEnabled(false)
	end
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

-- Size of the split axis in px.
function Splitter._total(self: Splitter): number
	local _, size = Kit.geometry(self.instance)
	return if self.direction == "horizontal" then size.X else size.Y
end

function Splitter._clamp(self: Splitter, ratio: number): number
	local total = self:_total()
	local minA = self._props.minFirst or 60
	local minB = self._props.minSecond or 60
	ratio = math.clamp(ratio, 0, 1)
	if total <= 0 then
		return ratio
	end
	if minA + minB >= total then
		return minA / (minA + minB)
	end
	return math.clamp(ratio, minA / total, 1 - minB / total)
end

function Splitter._apply(self: Splitter, ratio: number)
	local r = self:_clamp(ratio)
	self._ratio = r
	if self.direction == "horizontal" then
		self.first.Position = UDim2.new()
		self.first.Size = UDim2.new(r, 0, 1, 0)
		self.second.Position = UDim2.new(r, 1, 0, 0)
		self.second.Size = UDim2.new(1 - r, -1, 1, 0)
		self.divider.Position = UDim2.new(r, 0, 0, 0)
	else
		self.first.Position = UDim2.new()
		self.first.Size = UDim2.new(1, 0, r, 0)
		self.second.Position = UDim2.new(0, 0, r, 1)
		self.second.Size = UDim2.new(1, 0, 1 - r, -1)
		self.divider.Position = UDim2.new(0, 0, r, 0)
	end
end

function Splitter._emit(self: Splitter, final: boolean)
	if self._props.onChange then
		self._props.onChange(self._ratio, final)
	end
end

function Splitter._refreshLine(self: Splitter)
	local line = self.divider:FindFirstChild("Line") :: Frame
	local active = self._enabled and (self._hovered or self._dragging)
	line.BackgroundColor3 = if active then Theme.colors.accent else Theme.colors.border
end

function Splitter.getRatio(self: Splitter): number
	return self._ratio
end

Splitter.getValue = Splitter.getRatio

-- Sets the ratio (clamped by the min sizes) without firing onChange.
function Splitter.setRatio(self: Splitter, ratio: number)
	self:_apply(ratio)
end

Splitter.setValue = Splitter.setRatio

function Splitter.isDragging(self: Splitter): boolean
	return self._dragging
end

function Splitter.setEnabled(self: Splitter, enabled: boolean)
	self._enabled = enabled
	self.divider.Interactable = enabled
	self:_refreshLine()
end

function Splitter.destroy(self: Splitter)
	if self._destroyed then
		return
	end
	self._destroyed = true
	if self._dragging or self._hovered then
		Kit.setCursor(self._props.host, nil)
	end
	self.maid:clean()
	self.instance:Destroy()
end

return Splitter
