--!strict
--[[
	CurveGraph — value curve of one number channel track (the timeline's curve view). Building block: the Timeline
	panel hosts it and owns the document; the graph reports edits.

		local graph = CurveGraph.new({
			keyframes = { { time = 0, value = 0, easing = "Quad.Out" }, { time = 0.5, value = 1 } }, -- JSON form
			duration = 2,                    -- seconds: time view 0..duration, keys stay within 0..duration
			minValue = nil, maxValue = nil,  -- value view; nil = auto from the data (curve incl. overshoot) + padding
			min = 0, max = 1,                -- optional hard value limits (the channel spec's min/max)
			snap = function(t) return math.round(t * 30) / 30 end, -- optional snapping hook for dragged times
			host = host,                     -- { plugin, widget, root }: mouse editing, wheel zoom, middle-drag pan
			onChange = function(keyframes, final) end, -- sorted copy; final = false while dragging, then true once
			onSelect = function(indices) end,           -- sorted 1-based indices into the reported keyframes
			parent = timeline.body,
		})

	Drawing (UI/Editors/Draw, Frames): the track is compiled with Curves.compileTrack(def, { name = "value", kind =
	"number" }) and evaluated with Curves.evaluate on ~1 sample per 3 px of the visible time range (plus samples
	right before/at every key so Constant steps stay sharp); segments are clipped to the plot rectangle. Keys are
	diamonds; for segments whose easing is { bezier = { x1, y1, x2, y2 } } and whose start or end key is selected,
	two handles are drawn at (t_i + x·Δt, v_i + y·Δv) (Δv falls back to a quarter of the view height when the
	segment is flat, so flat segments stay editable).

	Mouse (UI/Input.drag + host.widget:GetRelativeMousePosition; no UserInputService):
	* click a key: select it (Shift adds, Ctrl toggles); click empty space: clear; drag on empty space: box select
	  (with Shift/Ctrl: added to the selection).
	* drag a selected key: moves time + value of every selected key. props.snap(time) snaps the grabbed key's time;
	  the others move by the same offset. Keys stay within 0..duration and the value limits, are re-sorted by time
	  (stable) and the new indices of the selection are reported with onSelect.
	* drag a bezier handle: edits that segment's easing (x clamped to 0..1, values rounded to 3 decimals).
	* wheel: zoom time around the mouse; Ctrl+wheel: zoom values; Shift+wheel: scroll time. Middle-drag: pan.
	Every edit gesture reports onChange(keyframes, false) for intermediate states and onChange(keyframes, true)
	once at the end. setKeyframes() with the keyframes the graph reported last is a no-op (echo from the document),
	so a gesture in progress keeps its mapping.
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Input = require(script.Parent.Parent.Input)
local Kit = require(script.Parent.Parent.Widgets.ControlKit)
local Draw = require(script.Parent.Draw)
local Curves = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Curves)
local Easing = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Easing)

export type Keyframe = { [string]: any } -- { time: number, value: number, easing: EasingDef? } (+ extra fields kept)

export type Props = {
	keyframes: { Keyframe }?,
	duration: number?,
	minValue: number?,
	maxValue: number?,
	min: number?,
	max: number?,
	snap: ((time: number) -> number)?,
	timePrecision: number?,
	precision: number?,
	color: Color3?,
	host: Kit.Host?,
	size: UDim2?,
	enabled: boolean?,
	onChange: ((keyframes: { Keyframe }, final: boolean) -> ())?,
	onSelect: ((indices: { number }) -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

export type View = { t0: number, t1: number, v0: number, v1: number }

type Origin = { time: number, value: number }

type DragState = {
	kind: string, -- "keys" | "handle" | "box"
	grab: Keyframe?,
	origins: { [Keyframe]: Origin },
	which: number, -- handle 1 / 2
	clickReplace: boolean, -- click (no movement) on an already selected key reduces the selection to it
	start: Vector2,
	additive: boolean,
	base: { [Keyframe]: boolean },
}

local CurveGraph = {}
CurveGraph.__index = CurveGraph

type CurveGraphData = {
	instance: Frame,
	plot: TextButton,
	gridLayer: Frame,
	curveLayer: Frame,
	handleLayer: Frame,
	keyLayer: Frame,
	outside: Frame,
	boxRect: Frame,
	playhead: Frame,
	valueAxis: Frame,
	timeAxis: Frame,
	diamonds: { Frame },
	segments: { Frame },
	handleDots: { Frame },
	handleLines: { Frame },
	gridLines: { Frame },
	valueLabels: { TextLabel },
	timeLabels: { TextLabel },
	_maid: any,
	_props: Props,
	_keys: { Keyframe },
	_selected: { [Keyframe]: boolean },
	_lastIndices: { number },
	_reported: { Keyframe }?,
	_track: any, -- CompiledTrack?
	_view: View,
	_autoValue: boolean,
	_duration: number?,
	_snap: ((time: number) -> number)?,
	_timePrecision: number,
	_precision: number,
	_enabled: boolean,
	_destroyed: boolean,
	_drag: DragState?,
	_dragChanged: boolean,
	_pan: View?,
	_playhead: number?,
	_handles: { { key: Keyframe, which: number, pixel: Vector2 } },
}

export type CurveGraph = typeof(setmetatable({} :: CurveGraphData, CurveGraph))

local c = Theme.colors

local AXIS_W = 40
local AXIS_H = 16
local PAD = 6
local DIAMOND = 9
local HIT_RADIUS = 7
local HANDLE_RADIUS = 4
local CLIP_MARGIN = 4
local ZOOM_STEP = 1.2
local MIN_TIME_SPAN = 1e-3
local MAX_TIME_SPAN = 1e5
local MIN_VALUE_SPAN = 1e-6
local MAX_VALUE_SPAN = 1e9
local CHANNEL_SPEC = { name = "value", kind = "number", description = "CurveGraph channel" }

-- helpers ---------------------------------------------------------------------------------------------------------

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

-- (a, b) with b - a clamped to [minSpan, maxSpan] around the midpoint.
local function spanned(a: number, b: number, minSpan: number, maxSpan: number): (number, number)
	local span = b - a
	if span >= minSpan and span <= maxSpan then
		return a, b
	end
	local mid = (a + b) / 2
	local s = clamp(span, minSpan, maxSpan)
	return mid - s / 2, mid + s / 2
end

local function roundTo(x: number, decimals: number): number
	local r = Kit.round(x, decimals)
	return if r == 0 then 0 else r
end

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function positive(x: any): number?
	return if finite(x) and x > 0 then x else nil
end

local function numberOf(v: any): number
	return if finite(v) then v else 0
end

-- Grid step: smallest 1/2/2.5/5 × 10^k >= span / target.
local function niceStep(span: number, target: number): number
	local raw = span / math.max(target, 1)
	if raw <= 0 or raw ~= raw then
		return 1
	end
	local mag = 10 ^ math.floor(math.log10(raw))
	for _, m in { 1, 2, 2.5, 5, 10 } do
		if m * mag >= raw - 1e-12 * mag then
			return m * mag
		end
	end
	return 10 * mag
end

-- Decimals needed for labels at multiples of a niceStep() step (0.25 -> 2, 0.5 -> 1, 2.5 -> 1, 5 -> 0).
local function decimalsFor(step: number): number
	local exponent = math.floor(math.log10(step) + 1e-9)
	local decimals = math.max(0, -exponent)
	if math.abs(step / 10 ^ exponent - 2.5) < 1e-6 then
		decimals += 1
	end
	return math.min(decimals, 6)
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Liang–Barsky: the part of segment p0-p1 inside [x0, x1] × [y0, y1], or nil.
local function clipSegment(p0: Vector2, p1: Vector2, x0: number, y0: number, x1: number, y1: number): (Vector2?, Vector2?)
	local dx, dy = p1.X - p0.X, p1.Y - p0.Y
	local u0, u1 = 0, 1
	local function edge(p: number, q: number): boolean
		if p == 0 then
			return q >= 0
		end
		local r = q / p
		if p < 0 then
			if r > u1 then
				return false
			end
			if r > u0 then
				u0 = r
			end
		else
			if r < u0 then
				return false
			end
			if r < u1 then
				u1 = r
			end
		end
		return true
	end
	if
		edge(-dx, p0.X - x0)
		and edge(dx, x1 - p0.X)
		and edge(-dy, p0.Y - y0)
		and edge(dy, y1 - p0.Y)
	then
		return Vector2.new(p0.X + u0 * dx, p0.Y + u0 * dy), Vector2.new(p0.X + u1 * dx, p0.Y + u1 * dy)
	end
	return nil, nil
end

-- Stable sort of keyframes by time (equal times keep their current order).
local function sortKeys(keys: { Keyframe })
	local order: { [Keyframe]: number } = {}
	for i, key in keys do
		order[key] = i
	end
	table.sort(keys, function(a: Keyframe, b: Keyframe): boolean
		local ta, tb = numberOf(a.time), numberOf(b.time)
		if ta ~= tb then
			return ta < tb
		end
		return order[a] < order[b]
	end)
end

local function bezierOf(key: Keyframe): { number }?
	local easing = key.easing
	if type(easing) == "table" and type(easing.bezier) == "table" then
		local ok = Easing.check(easing)
		if ok then
			return easing.bezier
		end
	end
	return nil
end

local function newFrame(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.Active = false
	f.Interactable = false
	f.Parent = parent
	return f
end

local function newLabel(parent: Instance, name: string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = Theme.fonts.regular
	l.TextSize = Theme.textSize.tiny
	l.TextColor3 = c.textMuted
	l.Size = UDim2.fromOffset(AXIS_W - 4, 12)
	l.Text = ""
	l.Parent = parent
	return l
end

-- construction ----------------------------------------------------------------------------------------------------

function CurveGraph.new(props: Props): CurveGraph
	local maid = Maid.new()
	local host = props.host

	local root = Instance.new("Frame")
	root.Name = "CurveGraph"
	root.BackgroundColor3 = c.bg0
	root.BorderSizePixel = 0
	root.Size = props.size or UDim2.new(1, 0, 0, 180)
	Kit.applyCommon(root, props :: any)
	Kit.corner().Parent = root
	Kit.stroke().Parent = root
	maid:give(root)

	local plot = Instance.new("TextButton")
	plot.Name = "Plot"
	plot.Text = ""
	plot.AutoButtonColor = false
	plot.BackgroundTransparency = 1
	plot.BorderSizePixel = 0
	plot.Selectable = false
	plot.ClipsDescendants = true
	plot.Position = UDim2.fromOffset(AXIS_W, PAD)
	plot.Size = UDim2.new(1, -(AXIS_W + PAD), 1, -(PAD + AXIS_H))
	plot.Parent = root

	local gridLayer = newFrame(plot, "Grid")
	local outside = Instance.new("Frame")
	outside.Name = "Outside" -- shades the time after the component's duration
	outside.BackgroundColor3 = c.bg1
	outside.BackgroundTransparency = 0.35
	outside.BorderSizePixel = 0
	outside.Active = false
	outside.Interactable = false
	outside.Visible = false
	outside.Parent = plot
	local curveLayer = newFrame(plot, "Curve")
	local handleLayer = newFrame(plot, "Handles")
	local keyLayer = newFrame(plot, "Keys")

	local boxRect = Draw.rect(plot, Vector2.zero, Vector2.zero, c.selection, {
		name = "BoxSelect",
		transparency = 0.6,
		stroke = c.selectionStrong,
	})
	boxRect.Visible = false

	local playhead = Instance.new("Frame")
	playhead.Name = "Playhead"
	playhead.BackgroundColor3 = c.playhead
	playhead.BorderSizePixel = 0
	playhead.AnchorPoint = Vector2.new(0.5, 0)
	playhead.Size = UDim2.new(0, 1, 1, 0)
	playhead.Active = false
	playhead.Interactable = false
	playhead.Visible = false
	playhead.Parent = plot

	local valueAxis = newFrame(root, "ValueAxis")
	valueAxis.Position = UDim2.fromOffset(0, PAD)
	valueAxis.Size = UDim2.new(0, AXIS_W - 4, 1, -(PAD + AXIS_H))
	local timeAxis = newFrame(root, "TimeAxis")
	timeAxis.Position = UDim2.new(0, AXIS_W, 1, -AXIS_H)
	timeAxis.Size = UDim2.new(1, -(AXIS_W + PAD), 0, AXIS_H)

	local self = setmetatable({
		instance = root,
		plot = plot,
		gridLayer = gridLayer,
		curveLayer = curveLayer,
		handleLayer = handleLayer,
		keyLayer = keyLayer,
		outside = outside,
		boxRect = boxRect,
		playhead = playhead,
		valueAxis = valueAxis,
		timeAxis = timeAxis,
		diamonds = {},
		segments = {},
		handleDots = {},
		handleLines = {},
		gridLines = {},
		valueLabels = {},
		timeLabels = {},
		_maid = maid,
		_props = props,
		_keys = {},
		_selected = {},
		_lastIndices = {},
		_reported = nil :: { Keyframe }?,
		_track = nil :: any,
		_view = { t0 = 0, t1 = 1, v0 = 0, v1 = 1 },
		_autoValue = props.minValue == nil or props.maxValue == nil,
		_duration = positive(props.duration),
		_snap = props.snap,
		_timePrecision = props.timePrecision or 3,
		_precision = props.precision or 3,
		_enabled = props.enabled ~= false,
		_destroyed = false,
		_drag = nil :: DragState?,
		_dragChanged = false,
		_pan = nil :: View?,
		_playhead = nil :: number?,
		_handles = {},
	}, CurveGraph)

	if host and host.widget then
		maid:give(Input.drag(host.widget, plot, {
			onPress = function(pos: Vector2, mods: Input.Mods)
				self:_press(pos, mods)
			end,
			onMove = function(pos: Vector2, delta: Vector2, _mods: Input.Mods)
				self:_dragMove(pos, delta)
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, _moved: boolean)
				self:_dragEnd()
			end,
			onClick = function(pos: Vector2, mods: Input.Mods)
				self:_click(pos, mods)
			end,
		}, { threshold = 2 }))
		maid:give(Input.drag(host.widget, plot, {
			onPress = function(_pos: Vector2, _mods: Input.Mods)
				self._pan = table.clone(self._view)
			end,
			onMove = function(_pos: Vector2, delta: Vector2, _mods: Input.Mods)
				local start = self._pan
				if start == nil then
					return
				end
				local _, size = self:_plotGeometry()
				local dt = -delta.X / size.X * (start.t1 - start.t0)
				local dv = delta.Y / size.Y * (start.v1 - start.v0)
				self._autoValue = false
				self:setView(start.t0 + dt, start.t1 + dt, start.v0 + dv, start.v1 + dv)
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, _moved: boolean)
				self._pan = nil
			end,
		}, { button = Enum.UserInputType.MouseButton3, threshold = 1 }))
		maid:give(Input.wheel(plot, function(direction: number, input: InputObject)
			local ok, mods = pcall(Input.mods, input)
			local m: Input.Mods = if ok then mods else { ctrl = false, shift = false, alt = false }
			self:_wheel(direction, m, Input.mousePosition(host.widget))
		end))
	end
	maid:give(plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_render()
	end))

	self:_load(props.keyframes or {})
	self:frameAll()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

-- data ------------------------------------------------------------------------------------------------------------

-- Replaces the keyframes (deep copies, stably sorted by time). The selection is kept by index, because the
-- document hands out new tables after every change. A drag in progress is moved over to the new tables.
function CurveGraph._load(self: CurveGraph, keyframes: { Keyframe })
	local oldKeys = self._keys
	local indices = self:getSelection()
	local keys: { Keyframe } = {}
	for i, kf in keyframes do
		keys[i] = deepCopy(kf)
	end
	sortKeys(keys)
	self._keys = keys
	local selected: { [Keyframe]: boolean } = {}
	for _, index in indices do
		local key = keys[index]
		if key then
			selected[key] = true
		end
	end
	self._selected = selected
	self._lastIndices = self:getSelection()
	local drag = self._drag
	if drag then
		if #oldKeys == #keys then
			local map: { [Keyframe]: Keyframe } = {}
			for i, old in oldKeys do
				map[old] = keys[i]
			end
			local origins: { [Keyframe]: Origin } = {}
			for old, origin in drag.origins do
				local new = map[old]
				if new then
					origins[new] = origin
				end
			end
			drag.origins = origins
			drag.grab = if drag.grab then map[drag.grab] else nil
			local base: { [Keyframe]: boolean } = {}
			for old in drag.base do
				local new = map[old]
				if new then
					base[new] = true
				end
			end
			drag.base = base
		else
			-- the keyframes changed under the gesture: end it (closing the host's gesture if it changed anything)
			self._drag = nil
			if self._dragChanged then
				self._dragChanged = false
				self:_emit(true)
			end
		end
	end
	self:_compile()
end

function CurveGraph._compile(self: CurveGraph)
	self._track = nil
	if #self._keys == 0 then
		return
	end
	local spec = table.clone(CHANNEL_SPEC) :: any
	spec.min = self._props.min
	spec.max = self._props.max
	local ok, track = pcall(Curves.compileTrack :: any, { id = "curve", channel = "value", keyframes = self._keys }, spec)
	if ok then
		self._track = track
	end
end

-- Sorted copy of the keyframes (JSON form).
function CurveGraph.getKeyframes(self: CurveGraph): { Keyframe }
	local out: { Keyframe } = table.create(#self._keys)
	for i, key in self._keys do
		out[i] = deepCopy(key)
	end
	return out
end

-- Replaces the keyframes without firing callbacks. The selection is kept by index. Passing the keyframes the
-- graph reported last (the document echoing an edit) changes nothing.
function CurveGraph.setKeyframes(self: CurveGraph, keyframes: { Keyframe })
	if self._reported and deepEqual(keyframes, self._reported) then
		return
	end
	if deepEqual(keyframes, self:getKeyframes()) then
		return
	end
	self:_load(keyframes)
	if self._autoValue and self._drag == nil and self._pan == nil then
		self:_fitValues()
	end
	self:_render()
end

CurveGraph.setValue = CurveGraph.setKeyframes
CurveGraph.getValue = CurveGraph.getKeyframes

-- Value of the compiled curve at time t (nil without keyframes or for invalid data).
function CurveGraph.evaluate(self: CurveGraph, t: number): number?
	local track = self._track
	if track == nil then
		return nil
	end
	return Curves.evaluate(track, t)
end

function CurveGraph._emit(self: CurveGraph, final: boolean)
	self:_compile()
	self:_render()
	local out = self:getKeyframes()
	self._reported = self:getKeyframes()
	local onChange = self._props.onChange
	if onChange then
		onChange(out, final)
	end
end

-- selection -------------------------------------------------------------------------------------------------------

-- Sorted indices of the selected keyframes.
function CurveGraph.getSelection(self: CurveGraph): { number }
	local out: { number } = {}
	for i, key in self._keys do
		if self._selected[key] then
			table.insert(out, i)
		end
	end
	return out
end

-- Reports the selection when its indices changed since the last report.
function CurveGraph._reportSelection(self: CurveGraph)
	local indices = self:getSelection()
	local last = self._lastIndices
	local same = #indices == #last
	if same then
		for i, v in indices do
			if last[i] ~= v then
				same = false
				break
			end
		end
	end
	self._lastIndices = indices
	if not same then
		local onSelect = self._props.onSelect
		if onSelect then
			onSelect(table.clone(indices))
		end
	end
end

--[[
	Selects keyframes by index. mode: "replace" (default), "add", "toggle" or "remove". Fires onSelect when the
	selection changed.
]]
function CurveGraph.select(self: CurveGraph, indices: { number }, mode: string?)
	local m = mode or "replace"
	if m == "replace" then
		self._selected = {}
	end
	for _, index in indices do
		local key = self._keys[index]
		if key then
			if m == "toggle" then
				if self._selected[key] then
					self._selected[key] = nil
				else
					self._selected[key] = true
				end
			elseif m == "remove" then
				self._selected[key] = nil
			else
				self._selected[key] = true
			end
		end
	end
	self:_render()
	self:_reportSelection()
end

function CurveGraph.clearSelection(self: CurveGraph)
	self:select({}, "replace")
end

-- edits -----------------------------------------------------------------------------------------------------------

function CurveGraph._clampValue(self: CurveGraph, v: number): number
	local lo = self._props.min or -math.huge
	local hi = self._props.max or math.huge
	return clamp(roundTo(v, self._precision), lo, hi)
end

-- Moves the selected keys by (dt, dv) from `origins` (time offset clamped so all stay within 0..duration).
-- Returns true when anything changed.
function CurveGraph._moveFrom(self: CurveGraph, origins: { [Keyframe]: Origin }, dt: number, dv: number): boolean
	local minT, maxT = math.huge, -math.huge
	for _, origin in origins do
		minT = math.min(minT, origin.time)
		maxT = math.max(maxT, origin.time)
	end
	if minT == math.huge then
		return false
	end
	local offset = math.max(dt, -minT)
	local duration = self._duration
	if duration then
		offset = math.min(offset, duration - maxT)
	end
	local changed = false
	for key, origin in origins do
		local time = clamp(roundTo(origin.time + offset, self._timePrecision), 0, duration or math.huge)
		local value = self:_clampValue(origin.value + dv)
		if time ~= key.time or value ~= key.value then
			key.time = time
			key.value = value
			changed = true
		end
	end
	if changed then
		sortKeys(self._keys)
	end
	return changed
end

local function originsOf(self: CurveGraph): { [Keyframe]: Origin }
	local origins: { [Keyframe]: Origin } = {}
	for key in self._selected do
		origins[key] = { time = numberOf(key.time), value = numberOf(key.value) }
	end
	return origins
end

-- Moves the selected keys (programmatic drag): time offset dt (s), value offset dv. `final` defaults to true.
function CurveGraph.moveSelected(self: CurveGraph, dt: number, dv: number, final: boolean?)
	if not self._enabled then
		return
	end
	local isFinal = final ~= false
	local changed = self:_moveFrom(originsOf(self), dt, dv)
	if changed or isFinal then
		self:_emit(isFinal)
		self:_reportSelection()
	end
end

-- Sets the easing of keyframe `index` (interpolation towards the next key). Fires onChange(keyframes, true).
function CurveGraph.setEasing(self: CurveGraph, index: number, easing: any): boolean
	local key = self._keys[index]
	if key == nil or not self._enabled or not Easing.check(easing) then
		return false
	end
	key.easing = deepCopy(easing)
	self:_emit(true)
	return true
end

-- Removes the selected keyframes. Fires onChange(keyframes, true) and onSelect({}). Returns how many were removed.
function CurveGraph.deleteSelected(self: CurveGraph): number
	if not self._enabled then
		return 0
	end
	local kept: { Keyframe } = {}
	local removed = 0
	for _, key in self._keys do
		if self._selected[key] then
			removed += 1
		else
			table.insert(kept, key)
		end
	end
	if removed == 0 then
		return 0
	end
	self._keys = kept
	self._selected = {}
	self:_emit(true)
	self:_reportSelection()
	return removed
end

-- view ------------------------------------------------------------------------------------------------------------

function CurveGraph.getView(self: CurveGraph): View
	return table.clone(self._view)
end

-- Sets the visible window (spans are clamped to sane limits). Omitted value bounds keep the current ones.
function CurveGraph.setView(self: CurveGraph, t0: number, t1: number, v0: number?, v1: number?)
	if not (finite(t0) and finite(t1)) then
		return
	end
	local view = self._view
	view.t0, view.t1 = spanned(t0, t1, MIN_TIME_SPAN, MAX_TIME_SPAN)
	if v0 ~= nil and v1 ~= nil and finite(v0) and finite(v1) then
		view.v0, view.v1 = spanned(v0, v1, MIN_VALUE_SPAN, MAX_VALUE_SPAN)
	end
	self:_render()
end

-- Value range of the data: keys and the evaluated curve (overshooting easings) over the keyed time range.
function CurveGraph._dataRange(self: CurveGraph): (number?, number?)
	local keys = self._keys
	if #keys == 0 then
		return nil, nil
	end
	local lo, hi = math.huge, -math.huge
	for _, key in keys do
		local v = numberOf(key.value)
		lo = math.min(lo, v)
		hi = math.max(hi, v)
	end
	local track = self._track
	if track then
		local tFirst, tLast = numberOf(keys[1].time), numberOf(keys[#keys].time)
		if tLast > tFirst then
			for _, v in Curves.sample(track, tFirst, tLast, 200) do
				lo = math.min(lo, v)
				hi = math.max(hi, v)
			end
		end
	end
	return lo, hi
end

function CurveGraph._fitValues(self: CurveGraph)
	local props = self._props
	local lo, hi = self:_dataRange()
	local v0, v1
	if lo == nil or hi == nil then
		v0, v1 = 0, 1
	elseif hi - lo < 1e-9 then
		local pad = math.max(math.abs(lo) * 0.1, 0.5)
		v0, v1 = lo - pad, hi + pad
	else
		local pad = (hi - lo) * 0.1
		v0, v1 = lo - pad, hi + pad
	end
	if props.minValue ~= nil then
		v0 = props.minValue
	end
	if props.maxValue ~= nil then
		v1 = props.maxValue
	end
	if v1 <= v0 then
		v1 = v0 + 1
	end
	self._view.v0, self._view.v1 = v0, v1
end

-- Fits the view to the duration (or the keys) and the data's value range (or minValue/maxValue).
function CurveGraph.frameAll(self: CurveGraph)
	local keys = self._keys
	local span = self._duration or math.max(1, if #keys > 0 then numberOf(keys[#keys].time) else 1)
	local pad = span * 0.03
	self._view.t0, self._view.t1 = -pad, span + pad
	self._autoValue = self._props.minValue == nil or self._props.maxValue == nil
	self:_fitValues()
	self:_render()
end

-- Zooms the time axis by `factor` (> 1 zooms in) around `anchor` (default: the view centre).
function CurveGraph.zoomTime(self: CurveGraph, factor: number, anchor: number?)
	local view = self._view
	local a = anchor or (view.t0 + view.t1) / 2
	local f = 1 / factor
	self:setView(a + (view.t0 - a) * f, a + (view.t1 - a) * f)
end

-- Zooms the value axis by `factor` (> 1 zooms in) around `anchor` (default: the view centre).
function CurveGraph.zoomValue(self: CurveGraph, factor: number, anchor: number?)
	local view = self._view
	local a = anchor or (view.v0 + view.v1) / 2
	local f = 1 / factor
	self._autoValue = false
	self:setView(view.t0, view.t1, a + (view.v0 - a) * f, a + (view.v1 - a) * f)
end

-- Scrolls the view by dt seconds and dv value units.
function CurveGraph.pan(self: CurveGraph, dt: number, dv: number?)
	local view = self._view
	local d = dv or 0
	if d ~= 0 then
		self._autoValue = false
	end
	self:setView(view.t0 + dt, view.t1 + dt, view.v0 + d, view.v1 + d)
end

function CurveGraph._wheel(self: CurveGraph, direction: number, mods: Input.Mods, mouse: Vector2)
	local t, v = self:pixelToPoint(mouse)
	if mods.shift then
		local view = self._view
		self:pan(-direction * (view.t1 - view.t0) * 0.1, 0)
	elseif mods.ctrl then
		self:zoomValue(ZOOM_STEP ^ direction, v)
	else
		self:zoomTime(ZOOM_STEP ^ direction, t)
	end
end

function CurveGraph.setDuration(self: CurveGraph, duration: number?)
	self._duration = positive(duration)
	self:_render()
end

function CurveGraph.setSnap(self: CurveGraph, snap: ((time: number) -> number)?)
	self._snap = snap
end

-- Playhead line at time t (nil hides it).
function CurveGraph.setPlayhead(self: CurveGraph, t: number?)
	self._playhead = t
	self:_render()
end

-- geometry --------------------------------------------------------------------------------------------------------

function CurveGraph._plotGeometry(self: CurveGraph): (Vector2, Vector2)
	local pos, size = Kit.geometry(self.plot)
	return pos, Vector2.new(math.max(size.X, 1), math.max(size.Y, 1))
end

function CurveGraph._toLocal(self: CurveGraph, t: number, v: number): Vector2
	local _, size = self:_plotGeometry()
	local view = self._view
	return Vector2.new(
		(t - view.t0) / (view.t1 - view.t0) * size.X,
		(1 - (v - view.v0) / (view.v1 - view.v0)) * size.Y
	)
end

-- (time, value) -> widget-space pixel (what host.widget:GetRelativeMousePosition() reports).
function CurveGraph.pointToPixel(self: CurveGraph, t: number, v: number): Vector2
	local pos = self:_plotGeometry()
	return pos + self:_toLocal(t, v)
end

-- Widget-space pixel -> (time, value).
function CurveGraph.pixelToPoint(self: CurveGraph, pixel: Vector2): (number, number)
	local pos, size = self:_plotGeometry()
	local l = pixel - pos
	local view = self._view
	return view.t0 + l.X / size.X * (view.t1 - view.t0), view.v0 + (1 - l.Y / size.Y) * (view.v1 - view.v0)
end

-- Value distance used for a bezier segment's handles (flat segments use a quarter of the view height).
function CurveGraph._segmentDv(self: CurveGraph, a: Keyframe, b: Keyframe): number
	local dv = numberOf(b.value) - numberOf(a.value)
	if math.abs(dv) < 1e-9 then
		return (self._view.v1 - self._view.v0) * 0.25
	end
	return dv
end

-- (time, value) of bezier handle `which` (1 / 2) of the segment starting at keyframe `index`, or nil.
function CurveGraph.handlePoint(self: CurveGraph, index: number, which: number): (number?, number?)
	local a, b = self._keys[index], self._keys[index + 1]
	if a == nil or b == nil then
		return nil, nil
	end
	local bezier = bezierOf(a)
	if bezier == nil then
		return nil, nil
	end
	local ta, va = numberOf(a.time), numberOf(a.value)
	local dt = numberOf(b.time) - ta
	local dv = self:_segmentDv(a, b)
	local x, y = bezier[which * 2 - 1], bezier[which * 2]
	return ta + x * dt, va + y * dv
end

-- Widget-space pixel of a bezier handle (nil when the segment has no bezier easing).
function CurveGraph.handlePixel(self: CurveGraph, index: number, which: number): Vector2?
	local t, v = self:handlePoint(index, which)
	if t == nil or v == nil then
		return nil
	end
	return self:pointToPixel(t, v)
end

-- Segments (start key indices) whose handles are shown: bezier easing and an endpoint selected.
function CurveGraph._visibleHandleSegments(self: CurveGraph): { number }
	local out: { number } = {}
	local keys = self._keys
	for i = 1, #keys - 1 do
		if bezierOf(keys[i]) and (self._selected[keys[i]] or self._selected[keys[i + 1]]) then
			table.insert(out, i)
		end
	end
	return out
end

-- ("handle", key, which) | ("key", key) | nil for a widget-space pixel.
function CurveGraph._hitTest(self: CurveGraph, pixel: Vector2): (string?, Keyframe?, number)
	for _, i in self:_visibleHandleSegments() do
		for which = 1, 2 do
			local p = self:handlePixel(i, which)
			if p and (p - pixel).Magnitude <= HIT_RADIUS then
				return "handle", self._keys[i], which
			end
		end
	end
	local best: Keyframe? = nil
	local bestDistance = HIT_RADIUS
	for _, key in self._keys do
		local d = (self:pointToPixel(numberOf(key.time), numberOf(key.value)) - pixel).Magnitude
		if d <= bestDistance then
			best, bestDistance = key, d
		end
	end
	if best then
		return "key", best, 0
	end
	return nil, nil, 0
end

-- mouse gestures --------------------------------------------------------------------------------------------------

function CurveGraph._press(self: CurveGraph, pos: Vector2, mods: Input.Mods)
	self._drag = nil
	self._dragChanged = false
	if not self._enabled then
		return
	end
	local kind, key, which = self:_hitTest(pos)
	local empty: { [Keyframe]: Origin } = {}
	if kind == "handle" and key then
		self._drag = {
			kind = "handle",
			grab = key,
			origins = empty,
			which = which,
			clickReplace = false,
			start = pos,
			additive = false,
			base = {},
		}
		return
	end
	if kind == "key" and key then
		local wasSelected = self._selected[key] == true
		if mods.ctrl then
			if wasSelected then
				self._selected[key] = nil
			else
				self._selected[key] = true
			end
		elseif mods.shift then
			self._selected[key] = true
		elseif not wasSelected then
			self._selected = { [key] = true }
		end
		self:_render()
		self:_reportSelection()
		if self._selected[key] then
			self._drag = {
				kind = "keys",
				grab = key,
				origins = originsOf(self),
				which = 0,
				clickReplace = wasSelected and not mods.ctrl and not mods.shift,
				start = pos,
				additive = false,
				base = {},
			}
		end
		return
	end
	self._drag = {
		kind = "box",
		grab = nil,
		origins = empty,
		which = 0,
		clickReplace = false,
		start = pos,
		additive = mods.shift or mods.ctrl,
		base = table.clone(self._selected),
	}
end

function CurveGraph._dragMove(self: CurveGraph, pos: Vector2, delta: Vector2)
	local drag = self._drag
	if drag == nil or not self._enabled then
		return
	end
	local _, size = self:_plotGeometry()
	local view = self._view
	if drag.kind == "keys" then
		local grab = drag.grab
		local origin = if grab then drag.origins[grab] else nil
		if origin == nil then
			return
		end
		local dt = delta.X / size.X * (view.t1 - view.t0)
		local dv = -delta.Y / size.Y * (view.v1 - view.v0)
		local snap = self._snap
		if snap then
			local ok, snapped = pcall(snap, origin.time + dt)
			if ok and finite(snapped) then
				dt = snapped - origin.time
			end
		end
		if self:_moveFrom(drag.origins, dt, dv) then
			self._dragChanged = true
			self:_emit(false)
			self:_reportSelection()
		end
	elseif drag.kind == "handle" then
		local key = drag.grab
		if key == nil then
			return
		end
		local index = table.find(self._keys, key)
		local nextKey = if index then self._keys[index + 1] else nil
		local bezier = bezierOf(key)
		if index == nil or nextKey == nil or bezier == nil then
			return
		end
		local t, v = self:pixelToPoint(pos)
		local ta, va = numberOf(key.time), numberOf(key.value)
		local dt = numberOf(nextKey.time) - ta
		local dv = self:_segmentDv(key, nextKey)
		local x = if dt > 0 then clamp((t - ta) / dt, 0, 1) else bezier[drag.which * 2 - 1]
		local y = (v - va) / dv
		local b = { bezier[1], bezier[2], bezier[3], bezier[4] }
		b[drag.which * 2 - 1] = roundTo(x, 3)
		b[drag.which * 2] = roundTo(clamp(y, -1e3, 1e3), 3)
		if b[1] ~= bezier[1] or b[2] ~= bezier[2] or b[3] ~= bezier[3] or b[4] ~= bezier[4] then
			key.easing = { bezier = b }
			self._dragChanged = true
			self:_emit(false)
		end
	elseif drag.kind == "box" then
		local t0, v0 = self:pixelToPoint(drag.start)
		local t1, v1 = self:pixelToPoint(pos)
		local tLo, tHi = math.min(t0, t1), math.max(t0, t1)
		local vLo, vHi = math.min(v0, v1), math.max(v0, v1)
		local selected: { [Keyframe]: boolean } = if drag.additive then table.clone(drag.base) else {}
		for _, key in self._keys do
			local t, v = numberOf(key.time), numberOf(key.value)
			if t >= tLo and t <= tHi and v >= vLo and v <= vHi then
				selected[key] = true
			end
		end
		self._selected = selected
		local plotPos = self:_plotGeometry()
		self.boxRect.Visible = true
		Draw.setRect(self.boxRect, drag.start - plotPos, pos - plotPos)
		self:_render()
		self:_reportSelection()
	end
end

function CurveGraph._dragEnd(self: CurveGraph)
	local drag = self._drag
	self._drag = nil
	self.boxRect.Visible = false
	if drag and self._dragChanged and (drag.kind == "keys" or drag.kind == "handle") then
		self._dragChanged = false
		self:_emit(true)
	end
	self._dragChanged = false
end

function CurveGraph._click(self: CurveGraph, pos: Vector2, mods: Input.Mods)
	if not self._enabled then
		return
	end
	local kind, key = self:_hitTest(pos)
	if kind == "key" and key then
		local drag = self._drag
		if mods.ctrl or mods.shift then
			return
		end
		-- a click on a key that was already part of a multi-selection reduces the selection to it
		if drag == nil or drag.clickReplace or not self._selected[key] then
			self._selected = { [key] = true }
			self:_render()
			self:_reportSelection()
		end
	elseif kind == nil and not mods.ctrl and not mods.shift then
		self:clearSelection()
	end
end

function CurveGraph.isDragging(self: CurveGraph): boolean
	return self._drag ~= nil or self._pan ~= nil
end

function CurveGraph.setEnabled(self: CurveGraph, enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self:_dragEnd()
	end
	self:_render()
end

function CurveGraph.destroy(self: CurveGraph)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._maid:clean() -- a key/handle drag in progress ends with onChange(keyframes, true)
end

-- rendering -------------------------------------------------------------------------------------------------------

local function pooled(pool: { Frame }, index: number, make: () -> Frame): Frame
	local existing: Frame? = pool[index]
	if existing then
		existing.Visible = true
		return existing
	end
	local frame = make()
	pool[index] = frame
	return frame
end

local function hideFrom(pool: { Frame }, first: number)
	for i = first, #pool do
		pool[i].Visible = false
	end
end

local function pooledLabel(pool: { TextLabel }, index: number, parent: Instance): TextLabel
	local existing: TextLabel? = pool[index]
	if existing then
		existing.Visible = true
		return existing
	end
	local l = newLabel(parent, "Label")
	pool[index] = l
	return l
end

function CurveGraph._renderGrid(self: CurveGraph, size: Vector2)
	local view = self._view
	local tSpan, vSpan = view.t1 - view.t0, view.v1 - view.v0
	local tStep = niceStep(tSpan, size.X / 70)
	local vStep = niceStep(vSpan, size.Y / 28)
	local used, labelsT, labelsV = 0, 0, 0
	local function line(horizontal: boolean, scale: number, colour: Color3)
		used += 1
		local f = pooled(self.gridLines, used, function(): Frame
			local frame = Instance.new("Frame")
			frame.Name = "GridLine"
			frame.BorderSizePixel = 0
			frame.Active = false
			frame.Interactable = false
			frame.Parent = self.gridLayer
			return frame
		end)
		f.BackgroundColor3 = colour
		if horizontal then
			f.AnchorPoint = Vector2.new(0, 0.5)
			f.Position = UDim2.fromScale(0, scale)
			f.Size = UDim2.new(1, 0, 0, 1)
		else
			f.AnchorPoint = Vector2.new(0.5, 0)
			f.Position = UDim2.fromScale(scale, 0)
			f.Size = UDim2.new(0, 1, 1, 0)
		end
	end
	local tDecimals = decimalsFor(tStep)
	local first = math.ceil(view.t0 / tStep)
	for i = first, first + 200 do
		local t = i * tStep
		if t > view.t1 then
			break
		end
		local scale = (t - view.t0) / tSpan
		line(false, scale, if i == 0 then c.borderStrong else c.gridMajor)
		labelsT += 1
		local l = pooledLabel(self.timeLabels, labelsT, self.timeAxis)
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(scale, 0, 0, 2)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.Text = Kit.format(t, tDecimals)
	end
	local vDecimals = decimalsFor(vStep)
	local firstV = math.ceil(view.v0 / vStep)
	for i = firstV, firstV + 200 do
		local v = i * vStep
		if v > view.v1 then
			break
		end
		local scale = 1 - (v - view.v0) / vSpan
		line(true, scale, if i == 0 then c.borderStrong else c.gridMajor)
		labelsV += 1
		local l = pooledLabel(self.valueLabels, labelsV, self.valueAxis)
		l.AnchorPoint = Vector2.new(1, 0.5)
		l.Position = UDim2.fromScale(1, scale)
		l.TextXAlignment = Enum.TextXAlignment.Right
		l.Text = Kit.format(v, vDecimals)
	end
	hideFrom(self.gridLines, used + 1)
	for i = labelsT + 1, #self.timeLabels do
		self.timeLabels[i].Visible = false
	end
	for i = labelsV + 1, #self.valueLabels do
		self.valueLabels[i].Visible = false
	end
end

function CurveGraph._renderCurve(self: CurveGraph, size: Vector2)
	local track = self._track
	local used = 0
	if track then
		local view = self._view
		local tSpan = view.t1 - view.t0
		local n = math.clamp(math.floor(size.X / 3), 24, 300)
		local times: { number } = table.create(n + 1)
		for i = 0, n do
			times[i + 1] = view.t0 + tSpan * i / n
		end
		local eps = tSpan * 1e-6
		for _, key in self._keys do
			local t = numberOf(key.time)
			if t > view.t0 and t < view.t1 then
				table.insert(times, t - eps)
				table.insert(times, t)
			end
		end
		table.sort(times)
		local colour = if self._enabled then (self._props.color or Theme.pinColors.number) else c.textMuted
		local previous: Vector2? = nil
		local x0, y0 = -CLIP_MARGIN, -CLIP_MARGIN
		local x1, y1 = size.X + CLIP_MARGIN, size.Y + CLIP_MARGIN
		for _, t in times do
			local v = Curves.evaluate(track, t)
			local p = self:_toLocal(t, v)
			if previous then
				local a, b = clipSegment(previous, p, x0, y0, x1, y1)
				if a and b then
					used += 1
					local seg = pooled(self.segments, used, function(): Frame
						return Draw.line(self.curveLayer, Vector2.zero, Vector2.zero, 2, colour, {
							name = "Segment",
							caps = true,
						})
					end)
					seg.BackgroundColor3 = colour
					Draw.setLine(seg, a, b, 2, true)
				end
			end
			previous = p
		end
	end
	hideFrom(self.segments, used + 1)
end

function CurveGraph._renderKeys(self: CurveGraph, size: Vector2)
	local enabled = self._enabled
	local used = 0
	for _, key in self._keys do
		local p = self:_toLocal(numberOf(key.time), numberOf(key.value))
		if p.X >= -DIAMOND and p.X <= size.X + DIAMOND and p.Y >= -DIAMOND and p.Y <= size.Y + DIAMOND then
			used += 1
			local diamond = pooled(self.diamonds, used, function(): Frame
				local d = Instance.new("Frame")
				d.Name = "Key"
				d.AnchorPoint = Vector2.new(0.5, 0.5)
				d.Size = UDim2.fromOffset(DIAMOND, DIAMOND)
				d.Rotation = 45
				d.BorderSizePixel = 0
				d.Active = false
				d.Interactable = false
				local stroke = Instance.new("UIStroke")
				stroke.Name = "Outline"
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Color = c.bg0
				stroke.Thickness = 1
				stroke.Parent = d
				d.Parent = self.keyLayer
				return d
			end)
			local selected = self._selected[key] == true
			diamond.Position = UDim2.fromOffset(p.X, p.Y)
			diamond.BackgroundColor3 = if not enabled then c.textMuted
				elseif selected then c.keyframeSelected
				else c.keyframe
			local outline = diamond:FindFirstChild("Outline") :: UIStroke?
			if outline then
				outline.Color = if selected then c.accent else c.bg0
			end
		end
	end
	hideFrom(self.diamonds, used + 1)
end

function CurveGraph._renderHandles(self: CurveGraph)
	local used = 0
	if self._enabled then
		for _, i in self:_visibleHandleSegments() do
			local a, b = self._keys[i], self._keys[i + 1]
			local pa = self:_toLocal(numberOf(a.time), numberOf(a.value))
			local pb = self:_toLocal(numberOf(b.time), numberOf(b.value))
			for which = 1, 2 do
				local t, v = self:handlePoint(i, which)
				if t and v then
					used += 1
					local p = self:_toLocal(t, v)
					local anchor = if which == 1 then pa else pb
					local lineFrame = pooled(self.handleLines, used, function(): Frame
						return Draw.line(self.handleLayer, anchor, p, 1, c.textDim, { name = "HandleLine" })
					end)
					Draw.setLine(lineFrame, anchor, p, 1)
					local dot = pooled(self.handleDots, used, function(): Frame
						return Draw.dot(self.handleLayer, p, HANDLE_RADIUS, c.teal, { name = "Handle", stroke = c.bg0 })
					end)
					Draw.setDot(dot, p, HANDLE_RADIUS)
				end
			end
		end
	end
	hideFrom(self.handleLines, used + 1)
	hideFrom(self.handleDots, used + 1)
end

function CurveGraph._render(self: CurveGraph)
	if self._destroyed then
		return
	end
	local _, size = self:_plotGeometry()
	local view = self._view
	self:_renderGrid(size)
	self:_renderCurve(size)
	self:_renderHandles()
	self:_renderKeys(size)

	local duration = self._duration
	if duration and duration < view.t1 then
		local x = math.max(0, (duration - view.t0) / (view.t1 - view.t0))
		self.outside.Visible = true
		self.outside.Position = UDim2.fromScale(x, 0)
		self.outside.Size = UDim2.fromScale(math.max(0, 1 - x), 1)
	else
		self.outside.Visible = false
	end

	local playhead = self._playhead
	if playhead and playhead >= view.t0 and playhead <= view.t1 then
		self.playhead.Visible = true
		self.playhead.Position = UDim2.fromScale((playhead - view.t0) / (view.t1 - view.t0), 0)
	else
		self.playhead.Visible = false
	end
end

return CurveGraph
