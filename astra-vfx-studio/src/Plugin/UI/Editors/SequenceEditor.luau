--!strict
--[[
	SequenceEditor — NumberSequence curve editor (ParticleEmitter Size / Transparency / Squash, Trail WidthScale …).

		local size = SequenceEditor.new({
			value = { { 0, 0.5 }, { 0.3, 2, 0.4 }, { 1, 0 } }, -- JSON form: number or [[t, v, envelope?], ...]
			min = 0, max = 10,               -- hard value limits (default 0..1); envelopes are >= 0
			range = { 0, 1 },                -- initial view range (default { min, max })
			autoRange = true,                -- view grows (up to max) to fit the data; default: range narrower than limits
			presetLow = 0, presetHigh = 1,   -- levels of the presets (transparency: presetLow = 1, presetHigh = 0)
			precision = 3,                   -- decimals of dragged values (times always use 3)
			host = host,                     -- { plugin, widget, root }: mouse editing, preset popup, scrubbing
			onChange = function(value, final) -- JSON form; final = false while dragging/scrubbing, then true once
				if final then editor:endGesture(true) else editor:updateGesture(value) end
			end,
			onSelect = function(index) end,  -- selected keypoint index (nil = none)
			parent = section.body,
		})
		size:setValue(1.5)                   -- display only, no callbacks
		size:addKeypoint(0.5, 2)             -- acts like the user: fires onChange(value, true)

	The value is always the canonical JSON form (Codec.normalize "numberSequence" with spec { min, max }): a plain
	number when the curve is constant (two equal keypoints, no envelope), otherwise [[t, v], [t, v, e], ...] with
	2..20 keypoints, first time 0, last time 1.

	Mouse (DockWidgets: UI/Input.drag polls host.widget:GetRelativeMousePosition(); no UserInputService):
	* drag a keypoint: time + value. The first and last keypoint keep time 0 / 1; middle keypoints stay between
	  their neighbours (at least MIN_GAP apart, so the engine never sees equal times). Dragged values are clamped
	  to the view range; with autoRange the view grows when a value touches its top (released at the edge) and
	  shrinks back when the data no longer needs it.
	* Alt-drag a keypoint, or drag one of the two envelope handles above/below the selected keypoint: envelope
	  (the translucent ± band; the engine's envelopes are symmetric). Right-click a handle resets the envelope.
	* double-click empty space (Activated clickCount 2): add a keypoint there (at most 20).
	* right-click a keypoint: remove it (never the first/last one, never below two keypoints).
	* click empty space: deselect.
	Every gesture reports onChange(value, false) for intermediate states and onChange(value, true) once at the end.

	Toolbar: presets (Konstant, Linear ein/aus, Ein- und ausblenden, Puls, Ease-Out gebacken) and "Glätten", which
	runs a monotone cubic (PCHIP, no overshoot, so limits hold) through the keypoints (values and envelopes) and
	bakes it to ≤ 20 linear keypoints with Curves.bakeToSequenceKeypoints — the engine only interpolates linearly.
	The numeric fields below the graph edit the selected keypoint (time, value, envelope "±").

	The curve is a polyline through Curves.evaluateNumberSequence at the keypoint times (exact: the engine
	interpolates linearly); the envelope band is sampled with Curves.evaluateNumberSequenceEnvelope.
	Drawing uses UI/Editors/Draw (Frames); everything is redrawn when the plot's AbsoluteSize changes.
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Input = require(script.Parent.Parent.Input)
local Kit = require(script.Parent.Parent.Widgets.ControlKit)
local Button = require(script.Parent.Parent.Widgets.Button)
local Dropdown = require(script.Parent.Parent.Widgets.Dropdown)
local NumberInput = require(script.Parent.Parent.Widgets.NumberInput)
local Draw = require(script.Parent.Draw)
local Codec = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Codec)
local Curves = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Curves)
local Easing = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Easing)

export type Props = {
	value: any?,
	min: number?,
	max: number?,
	range: { number }?,
	autoRange: boolean?,
	precision: number?,
	presetLow: number?,
	presetHigh: number?,
	graphHeight: number?,
	host: Kit.Host?,
	size: UDim2?,
	enabled: boolean?,
	onChange: ((value: any, final: boolean) -> ())?,
	onSelect: ((index: number?) -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

-- { time, value, envelope }
export type Keypoint = { number }

type DragState = {
	kind: string, -- "point" | "envelope"
	index: number,
	t0: number,
	v0: number,
	e0: number,
	dir: number, -- envelope: +1 = dragging up grows it, -1 = dragging down grows it
}

local SequenceEditor = {}
SequenceEditor.__index = SequenceEditor

type SequenceEditorData = {
	instance: Frame,
	toolbar: Frame,
	graph: Frame,
	plot: TextButton,
	grid: Frame,
	zeroLine: Frame,
	band: Frame,
	bandTop: Frame,
	bandBottom: Frame,
	curve: Frame,
	pointsLayer: Frame,
	dots: { Frame },
	handles: { Frame },
	handleLines: { Frame },
	valueLabels: { TextLabel },
	timeLabels: { TextLabel },
	countLabel: TextLabel,
	presets: any, -- Dropdown
	smoothButton: any, -- Button
	fields: { [string]: any }, -- NumberInputs: time, value, envelope
	_maid: any,
	_props: Props,
	_spec: any, -- Codec spec { min, max }
	_keys: { Keypoint },
	_value: any,
	_selected: number?,
	_min: number,
	_max: number,
	_baseLo: number,
	_baseHi: number,
	_lo: number,
	_hi: number,
	_autoRange: boolean,
	_precision: number,
	_enabled: boolean,
	_destroyed: boolean,
	_drag: DragState?,
	_dragChanged: boolean,
	_bandColumns: { Frame },
}

export type SequenceEditor = typeof(setmetatable({} :: SequenceEditorData, SequenceEditor))

local c = Theme.colors

local MAX_KEYPOINTS = 20
local MIN_GAP = 0.001
local TIME_DECIMALS = 3
local HIT_RADIUS = 7
local HANDLE_OFFSET = 12
local ROW = Theme.metrics.rowHeight
local GAP = 4
local AXIS_W = 34
local AXIS_H = 14
local PAD_T = 8
local PAD_R = 8
local BAND_COLUMNS = 64
local DEFAULT_GRAPH_HEIGHT = 140
local SMOOTH_TOLERANCE = 0.0025 -- fraction of the view span (well below one pixel of a 140 px graph)

SequenceEditor.MAX_KEYPOINTS = MAX_KEYPOINTS
SequenceEditor.MIN_GAP = MIN_GAP

SequenceEditor.PRESETS = {
	{ value = "constant", label = "Konstant", description = "Gleichbleibend auf dem hohen Wert" },
	{ value = "linearIn", label = "Linear ein", description = "Linear vom niedrigen zum hohen Wert" },
	{ value = "linearOut", label = "Linear aus", description = "Linear vom hohen zum niedrigen Wert" },
	{ value = "fadeInOut", label = "Ein- und ausblenden", description = "Rampe hoch, halten, Rampe runter" },
	{ value = "pulse", label = "Puls", description = "Spitze in der Mitte" },
	{ value = "easeOut", label = "Ease-Out (gebacken)", description = "Quad.Out vom hohen zum niedrigen Wert" },
}

-- helpers ---------------------------------------------------------------------------------------------------------

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

local function roundTo(x: number, decimals: number): number
	local r = Kit.round(x, decimals)
	return if r == 0 then 0 else r
end

-- Smallest "nice" number (1, 2, 2.5, 5 × 10^k) >= x; mirrored for negative x.
local function niceCeil(x: number): number
	if x == 0 or x ~= x then
		return 0
	end
	if x < 0 then
		-- largest nice number <= -x, negated
		local y = -x
		local mag = 10 ^ math.floor(math.log10(y))
		local best = mag
		for _, m in { 1, 2, 2.5, 5, 10 } do
			if m * mag <= y + 1e-9 then
				best = m * mag
			end
		end
		return -best
	end
	local mag = 10 ^ math.floor(math.log10(x))
	for _, m in { 1, 2, 2.5, 5, 10 } do
		if m * mag >= x - 1e-9 * mag then
			return m * mag
		end
	end
	return 10 * mag
end

-- New upper view bound: grows when the data touches the top, shrinks back towards `base` when it is no longer
-- needed. `other` is the opposite bound; results stay within [base, limit].
local function fitUpper(required: number, other: number, current: number, base: number, limit: number): number
	local span = current - other
	local bound = current
	if required >= other + span * 0.98 then
		bound = niceCeil(other + (required - other) * 1.25)
	elseif required < other + span * 0.4 and current > base then
		bound = niceCeil(other + (required - other) * 1.25)
	end
	return clamp(math.max(bound, base), base, limit)
end

local function sequenceOf(keys: { Keypoint }): NumberSequence?
	local ok, seq = pcall(function()
		local list = table.create(#keys)
		for i, kp in keys do
			list[i] = NumberSequenceKeypoint.new(kp[1], kp[2], kp[3])
		end
		return NumberSequence.new(list)
	end)
	return if ok then seq else nil
end

-- Linear evaluation straight from the keypoints (fallback when no NumberSequence can be built).
local function linearAt(keys: { Keypoint }, t: number, slot: number): number
	local n = #keys
	if t <= keys[1][1] then
		return keys[1][slot]
	end
	for i = 1, n - 1 do
		local a, b = keys[i], keys[i + 1]
		if t < b[1] then
			local span = b[1] - a[1]
			local alpha = if span > 0 then (t - a[1]) / span else 1
			return a[slot] + (b[slot] - a[slot]) * alpha
		end
	end
	return keys[n][slot]
end

-- JSON value (number | [[t, v, e?], ...]) -> internal keypoints (always a list, envelope explicit).
local function keysOf(canonical: any): { Keypoint }
	if type(canonical) == "number" then
		return { { 0, canonical, 0 }, { 1, canonical, 0 } }
	end
	local keys: { Keypoint } = {}
	for i, kp in canonical do
		keys[i] = { kp[1], kp[2], kp[3] or 0 }
	end
	return keys
end

local function rawOf(keys: { Keypoint }): { { number } }
	local raw: { { number } } = table.create(#keys)
	for i, kp in keys do
		raw[i] = if kp[3] > 0 then { kp[1], kp[2], kp[3] } else { kp[1], kp[2] }
	end
	return raw
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if #a ~= #b then
		return false
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

-- Monotone cubic (PCHIP / Fritsch–Butland) tangents: the interpolant never overshoots its neighbouring points.
local function monotoneTangents(xs: { number }, ys: { number }): { number }
	local n = #xs
	local m: { number } = table.create(n, 0)
	if n < 2 then
		return m
	end
	local h: { number } = table.create(n - 1, 0)
	local d: { number } = table.create(n - 1, 0)
	for k = 1, n - 1 do
		h[k] = xs[k + 1] - xs[k]
		d[k] = if h[k] > 0 then (ys[k + 1] - ys[k]) / h[k] else 0
	end
	if n == 2 then
		m[1], m[2] = d[1], d[1]
		return m
	end
	for k = 2, n - 1 do
		local d0, d1 = d[k - 1], d[k]
		if d0 * d1 > 0 then
			local w1 = 2 * h[k] + h[k - 1]
			local w2 = h[k] + 2 * h[k - 1]
			m[k] = (w1 + w2) / (w1 / d0 + w2 / d1)
		end
	end
	-- one-sided three-point end slopes, shape preserving (as in MATLAB's pchip)
	local function endSlope(h0: number, h1: number, d0: number, d1: number): number
		local s = if h0 + h1 > 0 then ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1) else d0
		if s * d0 <= 0 then
			return 0
		elseif d0 * d1 <= 0 and math.abs(s) > math.abs(3 * d0) then
			return 3 * d0
		end
		return s
	end
	m[1] = endSlope(h[1], h[2], d[1], d[2])
	m[n] = endSlope(h[n - 1], h[n - 2], d[n - 1], d[n - 2])
	return m
end

local function hermiteAt(xs: { number }, ys: { number }, m: { number }, x: number): number
	local n = #xs
	if x <= xs[1] then
		return ys[1]
	elseif x >= xs[n] then
		return ys[n]
	end
	local k = 1
	while k < n - 1 and xs[k + 1] <= x do
		k += 1
	end
	local h = xs[k + 1] - xs[k]
	if h <= 0 then
		return ys[k + 1]
	end
	local s = (x - xs[k]) / h
	local s2 = s * s
	local s3 = s2 * s
	return (2 * s3 - 3 * s2 + 1) * ys[k]
		+ (s3 - 2 * s2 + s) * h * m[k]
		+ (-2 * s3 + 3 * s2) * ys[k + 1]
		+ (s3 - s2) * h * m[k + 1]
end

--[[
	Smooth curve through `keys` ([[t, v, e?], ...] or internal { t, v, e }) baked to <= 20 linear keypoints.
	Values and envelopes use separate monotone cubics (no overshoot: limits and envelope >= 0 hold). `tolerance` is
	absolute (default 0.0025 × the value span of the keys, at least 1e-4). Returns the canonical JSON value
	(Codec.normalize with `spec`) and the bake's max error.
]]
function SequenceEditor.smoothKeypoints(keys: { { number } }, spec: any?, tolerance: number?): (any, number)
	local xs, ys, es = {}, {}, {}
	local lo, hi = math.huge, -math.huge
	local hasEnvelope = false
	for i, kp in keys do
		xs[i], ys[i], es[i] = kp[1], kp[2], kp[3] or 0
		lo = math.min(lo, ys[i])
		hi = math.max(hi, ys[i])
		if es[i] > 0 then
			hasEnvelope = true
		end
	end
	local mv = monotoneTangents(xs, ys)
	local me = monotoneTangents(xs, es)
	local tol = tolerance or math.max(1e-4, (hi - lo) * SMOOTH_TOLERANCE)
	local valueFn = function(t: number): number
		return hermiteAt(xs, ys, mv, t)
	end
	local envelopeFn = if hasEnvelope
		then function(t: number): number
			return math.max(0, hermiteAt(xs, es, me, t))
		end
		else nil
	local baked, maxError = Curves.bakeToSequenceKeypoints(valueFn, MAX_KEYPOINTS, tol, envelopeFn)
	return Codec.normalize("numberSequence", baked, spec), maxError
end

-- JSON value of a preset between the levels `low` and `high` (not yet clamped to any limits).
function SequenceEditor.preset(id: string, low: number, high: number): any
	if id == "constant" then
		return high
	elseif id == "linearIn" then
		return { { 0, low }, { 1, high } }
	elseif id == "linearOut" then
		return { { 0, high }, { 1, low } }
	elseif id == "fadeInOut" then
		return { { 0, low }, { 0.2, high }, { 0.8, high }, { 1, low } }
	elseif id == "pulse" then
		return { { 0, low }, { 0.5, high }, { 1, low } }
	elseif id == "easeOut" then
		local ease = Easing.get("Quad", "Out")
		local tol = math.max(1e-4, math.abs(high - low) * SMOOTH_TOLERANCE)
		local baked = Curves.bakeToSequenceKeypoints(function(t: number): number
			return high + (low - high) * ease(t)
		end, MAX_KEYPOINTS, tol)
		return baked
	end
	error("SequenceEditor.preset: unknown preset " .. tostring(id), 2)
end

local function label(parent: Instance, name: string, text: string, align: Enum.TextXAlignment): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = Theme.fonts.regular
	l.TextSize = Theme.textSize.tiny
	l.TextColor3 = c.textMuted
	l.TextXAlignment = align
	l.Text = text
	l.Parent = parent
	return l
end

-- construction ----------------------------------------------------------------------------------------------------

function SequenceEditor.new(props: Props): SequenceEditor
	local maid = Maid.new()
	local min = props.min or 0
	local max = props.max or 1
	if not (max > min) then
		error("SequenceEditor.new: max must be greater than min", 2)
	end
	local range = props.range
	local baseLo, baseHi = min, max
	if range then
		baseLo = clamp(range[1], min, max)
		baseHi = clamp(range[2], min, max)
		if baseHi <= baseLo then
			baseLo, baseHi = min, max
		end
	end
	local autoRange = if props.autoRange ~= nil then props.autoRange else (baseLo > min or baseHi < max)
	local graphHeight = props.graphHeight or DEFAULT_GRAPH_HEIGHT
	local host = props.host

	local root = Instance.new("Frame")
	root.Name = "SequenceEditor"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = props.size or UDim2.new(1, 0, 0, ROW + GAP + graphHeight + GAP + ROW)
	Kit.applyCommon(root, props :: any)
	maid:give(root)

	-- toolbar: presets, smoothing, keypoint count
	local toolbar = Instance.new("Frame")
	toolbar.Name = "Toolbar"
	toolbar.BackgroundTransparency = 1
	toolbar.Size = UDim2.new(1, 0, 0, ROW)
	toolbar.Parent = root

	local countLabel = label(toolbar, "Count", "", Enum.TextXAlignment.Right)
	countLabel.AnchorPoint = Vector2.new(1, 0)
	countLabel.Position = UDim2.fromScale(1, 0)
	countLabel.Size = UDim2.new(0, 48, 1, 0)
	countLabel.TextSize = Theme.textSize.small

	-- graph
	local graph = Instance.new("Frame")
	graph.Name = "Graph"
	graph.BackgroundColor3 = c.bg0
	graph.BorderSizePixel = 0
	graph.Position = UDim2.fromOffset(0, ROW + GAP)
	graph.Size = UDim2.new(1, 0, 1, -(2 * ROW + 2 * GAP))
	Kit.corner().Parent = graph
	Kit.stroke().Parent = graph
	graph.Parent = root

	local plot = Instance.new("TextButton")
	plot.Name = "Plot"
	plot.Text = ""
	plot.AutoButtonColor = false
	plot.BackgroundTransparency = 1
	plot.BorderSizePixel = 0
	plot.Selectable = false
	plot.Position = UDim2.fromOffset(AXIS_W, PAD_T)
	plot.Size = UDim2.new(1, -(AXIS_W + PAD_R), 1, -(PAD_T + AXIS_H))
	plot.Parent = graph

	local grid = Draw.grid(plot, 8, 4, { majorEvery = 2, edges = true })

	local zeroLine = Instance.new("Frame")
	zeroLine.Name = "Zero"
	zeroLine.BackgroundColor3 = c.borderStrong
	zeroLine.BorderSizePixel = 0
	zeroLine.AnchorPoint = Vector2.new(0, 0.5)
	zeroLine.Size = UDim2.new(1, 0, 0, 1)
	zeroLine.Visible = false
	zeroLine.Parent = plot

	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BackgroundTransparency = 1
	band.Size = UDim2.fromScale(1, 1)
	band.Visible = false
	band.Parent = plot
	local bandTop = Draw.polyline(band, {}, 1, c.accent, { name = "BandTop", transparency = 0.45 })
	local bandBottom = Draw.polyline(band, {}, 1, c.accent, { name = "BandBottom", transparency = 0.45 })

	local curve = Draw.polyline(plot, {}, 2, c.accent, { name = "Curve" })

	local handleLines = {
		Draw.line(plot, Vector2.zero, Vector2.zero, 1, c.teal, { name = "EnvelopeLine", transparency = 0.35 }),
		Draw.line(plot, Vector2.zero, Vector2.zero, 1, c.teal, { name = "EnvelopeLine", transparency = 0.35 }),
	}

	local pointsLayer = Instance.new("Frame")
	pointsLayer.Name = "Points"
	pointsLayer.BackgroundTransparency = 1
	pointsLayer.Size = UDim2.fromScale(1, 1)
	pointsLayer.Parent = plot

	local handles = {
		Draw.dot(plot, Vector2.zero, 3, c.teal, { name = "EnvelopeHandle", stroke = c.bg0 }),
		Draw.dot(plot, Vector2.zero, 3, c.teal, { name = "EnvelopeHandle", stroke = c.bg0 }),
	}
	for i = 1, 2 do
		handles[i].Visible = false
		handleLines[i].Visible = false
	end

	-- axis labels (scale-positioned against frames that share the plot's extent, so they follow resizes)
	local valueAxis = Instance.new("Frame")
	valueAxis.Name = "ValueAxis"
	valueAxis.BackgroundTransparency = 1
	valueAxis.Position = UDim2.fromOffset(0, PAD_T)
	valueAxis.Size = UDim2.new(0, AXIS_W - 4, 1, -(PAD_T + AXIS_H))
	valueAxis.Parent = graph
	local valueLabels: { TextLabel } = {}
	for i = 0, 4 do
		local l = label(valueAxis, "V" .. i, "", Enum.TextXAlignment.Right)
		l.AnchorPoint = Vector2.new(1, 0.5)
		l.Position = UDim2.fromScale(1, i / 4)
		l.Size = UDim2.fromOffset(AXIS_W, 12)
		valueLabels[i + 1] = l
	end

	local timeAxis = Instance.new("Frame")
	timeAxis.Name = "TimeAxis"
	timeAxis.BackgroundTransparency = 1
	timeAxis.Position = UDim2.new(0, AXIS_W, 1, -AXIS_H)
	timeAxis.Size = UDim2.new(1, -(AXIS_W + PAD_R), 0, AXIS_H)
	timeAxis.Parent = graph
	local timeLabels: { TextLabel } = {}
	for i = 0, 4 do
		local f = i / 4
		local l = label(timeAxis, "T" .. i, Kit.format(f, 2), Enum.TextXAlignment.Center)
		l.AnchorPoint = Vector2.new(if i == 0 then 0 elseif i == 4 then 1 else 0.5, 0)
		l.TextXAlignment = if i == 0
			then Enum.TextXAlignment.Left
			elseif i == 4 then Enum.TextXAlignment.Right
			else Enum.TextXAlignment.Center
		l.Position = UDim2.new(f, 0, 0, 1)
		l.Size = UDim2.fromOffset(30, 12)
		timeLabels[i + 1] = l
	end

	-- numeric fields of the selected keypoint
	local fieldRow = Instance.new("Frame")
	fieldRow.Name = "Fields"
	fieldRow.BackgroundTransparency = 1
	fieldRow.Position = UDim2.new(0, 0, 1, -ROW)
	fieldRow.Size = UDim2.new(1, 0, 0, ROW)
	fieldRow.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = fieldRow

	local self = setmetatable({
		instance = root,
		toolbar = toolbar,
		graph = graph,
		plot = plot,
		grid = grid,
		zeroLine = zeroLine,
		band = band,
		bandTop = bandTop,
		bandBottom = bandBottom,
		curve = curve,
		pointsLayer = pointsLayer,
		dots = {},
		handles = handles,
		handleLines = handleLines,
		valueLabels = valueLabels,
		timeLabels = timeLabels,
		countLabel = countLabel,
		presets = nil :: any,
		smoothButton = nil :: any,
		fields = {},
		_maid = maid,
		_props = props,
		_spec = { min = min, max = max },
		_keys = {},
		_value = 0 :: any,
		_selected = nil :: number?,
		_min = min,
		_max = max,
		_baseLo = baseLo,
		_baseHi = baseHi,
		_lo = baseLo,
		_hi = baseHi,
		_autoRange = autoRange,
		_precision = props.precision or 3,
		_enabled = props.enabled ~= false,
		_destroyed = false,
		_drag = nil :: DragState?,
		_dragChanged = false,
		_bandColumns = {},
	}, SequenceEditor)

	local presets = Dropdown.new({
		name = "Presets",
		options = SequenceEditor.PRESETS,
		placeholder = "Vorlage…",
		host = host,
		popupWidth = 190,
		size = UDim2.fromOffset(132, ROW),
		onChange = function(id: any)
			self.presets:setValue(nil)
			self:applyPreset(id)
		end,
	})
	presets.instance.Parent = toolbar
	maid:give(presets)
	self.presets = presets

	local smooth = Button.new({
		name = "Smooth",
		text = "Glätten",
		tooltip = "Weiche Kurve durch die Punkte, gebacken auf höchstens 20 lineare Keypoints",
		host = host,
		position = UDim2.fromOffset(132 + GAP, 0),
		onActivate = function()
			self:smooth()
		end,
	})
	smooth.instance.Parent = toolbar
	maid:give(smooth)
	self.smoothButton = smooth

	local span = max - min
	local fieldSize = UDim2.new(1 / 3, -3, 1, 0)
	local function field(key: string, order: number, fieldProps: { [string]: any })
		fieldProps.name = key
		fieldProps.layoutOrder = order
		fieldProps.size = fieldSize
		fieldProps.host = host
		local input = NumberInput.new(fieldProps :: any)
		input.instance.Parent = fieldRow
		maid:give(input)
		self.fields[key] = input
	end
	field("time", 1, {
		label = "Zeit",
		min = 0,
		max = 1,
		step = 0.01,
		precision = TIME_DECIMALS,
		tooltip = "Zeit des Keypoints (0 = Anfang, 1 = Ende der Lebensdauer)",
		onChange = function(v: number, final: boolean)
			local sel = self._selected
			if sel then
				self:setKeypointTime(sel, v, final)
			end
		end,
	})
	field("value", 2, {
		label = "Wert",
		min = min,
		max = max,
		step = niceCeil(span / 200),
		precision = self._precision,
		onChange = function(v: number, final: boolean)
			local sel = self._selected
			if sel then
				self:setKeypointValue(sel, v, final)
			end
		end,
	})
	field("envelope", 3, {
		label = "±",
		min = 0,
		max = span,
		step = niceCeil(span / 200),
		precision = self._precision,
		tooltip = "Streuung (Envelope): zufällige Abweichung ± um den Wert",
		onChange = function(v: number, final: boolean)
			local sel = self._selected
			if sel then
				self:setKeypointEnvelope(sel, v, final)
			end
		end,
	})

	-- mouse
	if host and host.widget then
		maid:give(Input.drag(host.widget, plot, {
			onPress = function(pos: Vector2, mods: Input.Mods)
				self:_press(pos, mods)
			end,
			onMove = function(_pos: Vector2, delta: Vector2, _mods: Input.Mods)
				self:_dragMove(delta)
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, _moved: boolean)
				self:_dragEnd()
			end,
			onClick = function(pos: Vector2, _mods: Input.Mods)
				if self._enabled and self:_hitTest(pos) == nil then
					self:selectKeypoint(nil)
				end
			end,
		}, { threshold = 2 }))
		maid:give(Input.onRightClick(plot, function(_input: InputObject)
			if not self._enabled then
				return
			end
			local kind, index = self:_hitTest(Input.mousePosition(host.widget))
			if kind == "point" and index then
				self:removeKeypoint(index)
			elseif kind == "envelope" and index then
				self:setKeypointEnvelope(index, 0, true)
			end
		end))
		maid:give(plot.Activated:Connect(function(_input: InputObject?, clickCount: number?)
			if not self._enabled or (clickCount or 1) < 2 then
				return
			end
			local pos = Input.mousePosition(host.widget)
			if self:_hitTest(pos) ~= nil then
				return
			end
			local t, v = self:pixelToPoint(pos)
			if t > 0 and t < 1 then
				self:addKeypoint(t, v)
			end
		end))
	end
	maid:give(plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_render()
	end))

	local fallback = clamp(props.presetHigh or baseHi, min, max)
	if not self:_load(if props.value ~= nil then props.value else fallback) then
		self:_load(fallback)
	end
	if self._autoRange then
		self:_fitRange()
	end
	self:_applyEnabled()
	self:_render()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

-- state -----------------------------------------------------------------------------------------------------------

-- Loads a JSON value (or a NumberSequence) into the keypoint list. Returns false (state unchanged) when invalid.
function SequenceEditor._load(self: SequenceEditor, value: any): boolean
	local ok, canonical = pcall(function(): any
		if typeof(value) == "NumberSequence" then
			return Codec.encode("numberSequence", value, self._spec)
		end
		return Codec.normalize("numberSequence", value, self._spec)
	end)
	if not ok then
		return false
	end
	self._value = canonical
	self._keys = keysOf(canonical)
	local sel = self._selected
	if sel and sel > #self._keys then
		self._selected = nil
	end
	return true
end

-- Re-encodes the keypoints (canonical JSON, clamped) and re-reads them so getKeypoints() matches getValue().
function SequenceEditor._commitKeys(self: SequenceEditor)
	local canonical = Codec.normalize("numberSequence", rawOf(self._keys), self._spec)
	self._value = canonical
	self._keys = keysOf(canonical)
end

function SequenceEditor._emit(self: SequenceEditor, final: boolean)
	self:_commitKeys()
	if final and self._autoRange then
		self:_fitRange()
	end
	self:_render()
	local onChange = self._props.onChange
	if onChange then
		onChange(self._value, final)
	end
end

function SequenceEditor._fitRange(self: SequenceEditor)
	local dataMin, dataMax = math.huge, -math.huge
	for _, kp in self._keys do
		dataMin = math.min(dataMin, kp[2] - kp[3])
		dataMax = math.max(dataMax, kp[2] + kp[3])
	end
	dataMin = clamp(dataMin, self._min, self._max)
	dataMax = clamp(dataMax, self._min, self._max)
	local lo, hi = self._lo, self._hi
	local newHi = fitUpper(dataMax, lo, hi, self._baseHi, self._max)
	local newLo = -fitUpper(-dataMin, -newHi, -lo, -self._baseLo, -self._min)
	if newHi > newLo then
		self._lo, self._hi = newLo, newHi
	end
end

-- geometry --------------------------------------------------------------------------------------------------------

function SequenceEditor._plotGeometry(self: SequenceEditor): (Vector2, Vector2)
	local pos, size = Kit.geometry(self.plot)
	return pos, Vector2.new(math.max(size.X, 1), math.max(size.Y, 1))
end

-- (time, value) -> pixel offset inside the plot.
function SequenceEditor._toLocal(self: SequenceEditor, t: number, v: number): Vector2
	local _, size = self:_plotGeometry()
	return Vector2.new(t * size.X, (1 - (v - self._lo) / (self._hi - self._lo)) * size.Y)
end

-- (time, value) -> widget-space pixel (what host.widget:GetRelativeMousePosition() reports).
function SequenceEditor.pointToPixel(self: SequenceEditor, t: number, v: number): Vector2
	local pos = self:_plotGeometry()
	return pos + self:_toLocal(t, v)
end

-- Widget-space pixel -> (time, value) (not clamped).
function SequenceEditor.pixelToPoint(self: SequenceEditor, pixel: Vector2): (number, number)
	local pos, size = self:_plotGeometry()
	local l = pixel - pos
	return l.X / size.X, self._lo + (1 - l.Y / size.Y) * (self._hi - self._lo)
end

-- Plot-local positions of the envelope handles (top, bottom) and of the keypoint itself.
function SequenceEditor._handleLocal(self: SequenceEditor, index: number): (Vector2, Vector2, Vector2)
	local kp = self._keys[index]
	local dot = self:_toLocal(kp[1], kp[2])
	local top = self:_toLocal(kp[1], kp[2] + kp[3])
	local bottom = self:_toLocal(kp[1], kp[2] - kp[3])
	return Vector2.new(dot.X, math.min(top.Y, dot.Y - HANDLE_OFFSET)),
		Vector2.new(dot.X, math.max(bottom.Y, dot.Y + HANDLE_OFFSET)),
		dot
end

-- Widget-space positions of the selected keypoint's envelope handles (nil when nothing is selected).
function SequenceEditor.handlePixels(self: SequenceEditor): (Vector2?, Vector2?)
	local sel = self._selected
	if sel == nil or self._keys[sel] == nil then
		return nil, nil
	end
	local pos = self:_plotGeometry()
	local top, bottom = self:_handleLocal(sel)
	return pos + top, pos + bottom
end

-- What is under a widget-space pixel: ("envelope", index, dir) | ("point", index, 0) | nil.
function SequenceEditor._hitTest(self: SequenceEditor, pixel: Vector2): (string?, number?, number)
	local top, bottom = self:handlePixels()
	local sel = self._selected
	if sel and top and bottom then
		if (pixel - top).Magnitude <= HIT_RADIUS then
			return "envelope", sel, 1
		elseif (pixel - bottom).Magnitude <= HIT_RADIUS then
			return "envelope", sel, -1
		end
	end
	local best: number? = nil
	local bestDistance = HIT_RADIUS
	for i, kp in self._keys do
		local d = (self:pointToPixel(kp[1], kp[2]) - pixel).Magnitude
		if d <= bestDistance then
			best, bestDistance = i, d
		end
	end
	if best then
		return "point", best, 0
	end
	return nil, nil, 0
end

-- mouse gestures --------------------------------------------------------------------------------------------------

function SequenceEditor._press(self: SequenceEditor, pos: Vector2, mods: Input.Mods)
	self._drag = nil
	self._dragChanged = false
	if not self._enabled then
		return
	end
	local kind, index, dir = self:_hitTest(pos)
	if kind == nil or index == nil then
		return
	end
	self:selectKeypoint(index)
	if kind == "point" and mods.alt then
		kind, dir = "envelope", 1
	end
	local kp = self._keys[index]
	self._drag = { kind = kind, index = index, t0 = kp[1], v0 = kp[2], e0 = kp[3], dir = dir }
end

function SequenceEditor._dragMove(self: SequenceEditor, delta: Vector2)
	local drag = self._drag
	if drag == nil or self._keys[drag.index] == nil then
		return
	end
	local _, size = self:_plotGeometry()
	local span = self._hi - self._lo
	local changed
	if drag.kind == "point" then
		changed = self:_setPoint(drag.index, drag.t0 + delta.X / size.X, drag.v0 - delta.Y / size.Y * span, true)
	else
		changed = self:_setEnvelope(drag.index, drag.e0 - drag.dir * delta.Y / size.Y * span)
	end
	if changed then
		self._dragChanged = true
		self:_emit(false)
	end
end

function SequenceEditor._dragEnd(self: SequenceEditor)
	local drag = self._drag
	self._drag = nil
	if drag and self._dragChanged then
		self._dragChanged = false
		self:_emit(true)
	end
end

-- constraints -----------------------------------------------------------------------------------------------------

-- Allowed time interval of keypoint `index` (first/last are locked to 0/1). nil when locked or no room.
function SequenceEditor._timeBounds(self: SequenceEditor, index: number): (number?, number?)
	local keys = self._keys
	if index <= 1 or index >= #keys then
		return nil, nil
	end
	local lo = keys[index - 1][1] + MIN_GAP
	local hi = keys[index + 1][1] - MIN_GAP
	if lo > hi then
		return nil, nil
	end
	return lo, hi
end

function SequenceEditor._constrainTime(self: SequenceEditor, index: number, t: number): number
	local kp = self._keys[index]
	local lo, hi = self:_timeBounds(index)
	if lo == nil or hi == nil then
		return kp[1]
	end
	return clamp(roundTo(clamp(t, lo, hi), TIME_DECIMALS), lo, hi)
end

function SequenceEditor._constrainValue(self: SequenceEditor, v: number, viewOnly: boolean): number
	local lo = if viewOnly then math.max(self._lo, self._min) else self._min
	local hi = if viewOnly then math.min(self._hi, self._max) else self._max
	return clamp(roundTo(clamp(v, lo, hi), self._precision), lo, hi)
end

function SequenceEditor._setPoint(self: SequenceEditor, index: number, t: number, v: number, viewOnly: boolean): boolean
	local kp = self._keys[index]
	local newT = self:_constrainTime(index, t)
	local newV = self:_constrainValue(v, viewOnly)
	if newT == kp[1] and newV == kp[2] then
		return false
	end
	kp[1], kp[2] = newT, newV
	return true
end

function SequenceEditor._setEnvelope(self: SequenceEditor, index: number, e: number): boolean
	local kp = self._keys[index]
	local newE = clamp(roundTo(clamp(e, 0, self._max - self._min), self._precision), 0, self._max - self._min)
	if newE == kp[3] then
		return false
	end
	kp[3] = newE
	return true
end

-- public API ------------------------------------------------------------------------------------------------------

-- Sets the value without firing callbacks. Accepts the JSON form or a NumberSequence; invalid values are
-- ignored (returns false). Re-setting the current value keeps a gesture in progress intact.
function SequenceEditor.setValue(self: SequenceEditor, value: any): boolean
	local okCanonical, canonical = pcall(function(): any
		if typeof(value) == "NumberSequence" then
			return Codec.encode("numberSequence", value, self._spec)
		end
		return Codec.normalize("numberSequence", value, self._spec)
	end)
	if not okCanonical then
		return false
	end
	if deepEqual(canonical, self._value) then
		return true
	end
	self:_load(canonical)
	if self._autoRange then
		self:_fitRange()
	end
	self:_render()
	return true
end

-- Canonical JSON value (number or [[t, v, e?], ...]).
function SequenceEditor.getValue(self: SequenceEditor): any
	local v = self._value
	return if type(v) == "table" then rawOf(keysOf(v)) else v
end

-- Copy of the keypoints as { time, value, envelope } triples (always a list, also for constant values).
function SequenceEditor.getKeypoints(self: SequenceEditor): { Keypoint }
	local out: { Keypoint } = table.create(#self._keys)
	for i, kp in self._keys do
		out[i] = { kp[1], kp[2], kp[3] }
	end
	return out
end

function SequenceEditor.getKeypointCount(self: SequenceEditor): number
	return #self._keys
end

function SequenceEditor.getSelected(self: SequenceEditor): number?
	return self._selected
end

-- Selects keypoint `index` (nil clears). Fires onSelect when the selection changes.
function SequenceEditor.selectKeypoint(self: SequenceEditor, index: number?)
	local sel = if index ~= nil and self._keys[index] ~= nil then index else nil
	if sel == self._selected then
		return
	end
	self._selected = sel
	self:_render()
	local onSelect = self._props.onSelect
	if onSelect then
		onSelect(sel)
	end
end

--[[
	Adds a keypoint at time t (like a double-click): value defaults to the curve's current value at t and the
	envelope to the current envelope. Fires onChange(value, true) and selects the new keypoint. Returns its index,
	or nil when 20 keypoints exist already or t is closer than MIN_GAP to an existing keypoint.
]]
function SequenceEditor.addKeypoint(self: SequenceEditor, t: number, v: number?, e: number?): number?
	local keys = self._keys
	if not self._enabled or #keys >= MAX_KEYPOINTS or t ~= t then
		return nil
	end
	local time = roundTo(clamp(t, MIN_GAP, 1 - MIN_GAP), TIME_DECIMALS)
	local index = #keys
	for i = 2, #keys do
		if time < keys[i][1] then
			index = i
			break
		end
	end
	if time - keys[index - 1][1] < MIN_GAP - 1e-9 or keys[index][1] - time < MIN_GAP - 1e-9 then
		return nil
	end
	local seq = sequenceOf(keys)
	local value = v
	if value == nil then
		value = if seq then Curves.evaluateNumberSequence(seq, time) else linearAt(keys, time, 2)
	end
	local envelope = e
	if envelope == nil then
		envelope = if seq then Curves.evaluateNumberSequenceEnvelope(seq, time) else linearAt(keys, time, 3)
	end
	local span = self._max - self._min
	table.insert(keys, index, {
		time,
		self:_constrainValue(value :: number, false),
		clamp(roundTo(envelope :: number, self._precision), 0, span),
	})
	local sel = self._selected
	if sel and sel >= index then
		self._selected = sel + 1
	end
	self:_emit(true)
	self:selectKeypoint(index)
	return index
end

-- Removes keypoint `index` (like a right-click). The first and last keypoint and the last two cannot be removed.
-- Fires onChange(value, true). Returns true when removed.
function SequenceEditor.removeKeypoint(self: SequenceEditor, index: number): boolean
	local keys = self._keys
	if not self._enabled or index <= 1 or index >= #keys or #keys <= 2 then
		return false
	end
	table.remove(keys, index)
	local sel = self._selected
	local selectionChanged = false
	if sel == index then
		self._selected = nil
		selectionChanged = true
	elseif sel and sel > index then
		self._selected = sel - 1
	end
	self:_emit(true)
	if selectionChanged and self._props.onSelect then
		self._props.onSelect(nil)
	end
	return true
end

-- Field edits (like typing/scrubbing the numeric fields). `final` defaults to true; onChange fires when the
-- keypoint changed or when final is true (closing a scrub gesture).
function SequenceEditor.setKeypointTime(self: SequenceEditor, index: number, t: number, final: boolean?)
	local kp = self._keys[index]
	if kp == nil or not self._enabled then
		return
	end
	local isFinal = final ~= false
	local changed = self:_setPoint(index, t, kp[2], false)
	if changed or isFinal then
		self:_emit(isFinal)
	end
end

function SequenceEditor.setKeypointValue(self: SequenceEditor, index: number, v: number, final: boolean?)
	local kp = self._keys[index]
	if kp == nil or not self._enabled then
		return
	end
	local isFinal = final ~= false
	local changed = self:_setPoint(index, kp[1], v, false)
	if changed or isFinal then
		self:_emit(isFinal)
	end
end

function SequenceEditor.setKeypointEnvelope(self: SequenceEditor, index: number, e: number, final: boolean?)
	if self._keys[index] == nil or not self._enabled then
		return
	end
	local isFinal = final ~= false
	local changed = self:_setEnvelope(index, e)
	if changed or isFinal then
		self:_emit(isFinal)
	end
end

-- Applies a preset (SequenceEditor.PRESETS) between presetLow and presetHigh. Fires onChange(value, true).
function SequenceEditor.applyPreset(self: SequenceEditor, id: string): boolean
	if not self._enabled then
		return false
	end
	local low = self._props.presetLow or self._baseLo
	local high = self._props.presetHigh or self._baseHi
	local ok, raw = pcall(SequenceEditor.preset, id, low, high)
	if not ok or not self:_load(raw) then
		return false
	end
	local hadSelection = self._selected ~= nil
	self._selected = nil
	self:_emit(true)
	if hadSelection and self._props.onSelect then
		self._props.onSelect(nil)
	end
	return true
end

-- "Glätten": smooth curve through the keypoints baked to <= 20 linear keypoints. Fires onChange(value, true).
-- Returns the bake's max error (in value units), or nil when disabled.
function SequenceEditor.smooth(self: SequenceEditor): number?
	if not self._enabled then
		return nil
	end
	local tolerance = math.max(1e-4, (self._hi - self._lo) * SMOOTH_TOLERANCE)
	local value, maxError = SequenceEditor.smoothKeypoints(self._keys, self._spec, tolerance)
	self:_load(value)
	local hadSelection = self._selected ~= nil
	self._selected = nil
	self:_emit(true)
	if hadSelection and self._props.onSelect then
		self._props.onSelect(nil)
	end
	return maxError
end

-- View range (lo, hi) of the value axis.
function SequenceEditor.getRange(self: SequenceEditor): (number, number)
	return self._lo, self._hi
end

-- Sets the view range (clamped to the limits). It also becomes the base the auto range shrinks back to.
function SequenceEditor.setRange(self: SequenceEditor, lo: number, hi: number)
	local newLo = clamp(lo, self._min, self._max)
	local newHi = clamp(hi, self._min, self._max)
	if newHi <= newLo then
		return
	end
	self._baseLo, self._baseHi = newLo, newHi
	self._lo, self._hi = newLo, newHi
	if self._autoRange then
		self:_fitRange()
	end
	self:_render()
end

-- Value limits (min, max).
function SequenceEditor.getLimits(self: SequenceEditor): (number, number)
	return self._min, self._max
end

function SequenceEditor.isDragging(self: SequenceEditor): boolean
	return self._drag ~= nil
end

function SequenceEditor._applyEnabled(self: SequenceEditor)
	local enabled = self._enabled
	self.presets:setEnabled(enabled)
	self.smoothButton:setEnabled(enabled)
end

function SequenceEditor.setEnabled(self: SequenceEditor, enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self:_dragEnd()
	end
	self:_applyEnabled()
	self:_render()
end

function SequenceEditor.destroy(self: SequenceEditor)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._maid:clean() -- a drag in progress ends with onChange(value, true) (Input.drag -> onEnd)
end

-- rendering -------------------------------------------------------------------------------------------------------

function SequenceEditor._yScale(self: SequenceEditor, v: number): number
	return 1 - (v - self._lo) / (self._hi - self._lo)
end

function SequenceEditor._render(self: SequenceEditor)
	if self._destroyed then
		return
	end
	local keys = self._keys
	local n = #keys
	local enabled = self._enabled
	local seq = sequenceOf(keys)
	local lo, hi = self._lo, self._hi

	local function valueAt(t: number): number
		return if seq then Curves.evaluateNumberSequence(seq, t) else linearAt(keys, t, 2)
	end
	local function envelopeAt(t: number): number
		return if seq then Curves.evaluateNumberSequenceEnvelope(seq, t) else linearAt(keys, t, 3)
	end

	-- curve (exact: linear between keypoints)
	local points: { Vector2 } = table.create(n)
	for i, kp in keys do
		points[i] = self:_toLocal(kp[1], valueAt(kp[1]))
	end
	Draw.setPolyline(self.curve, points, 2, if enabled then c.accent else c.textMuted)

	-- envelope band
	local hasEnvelope = false
	for _, kp in keys do
		if kp[3] > 0 then
			hasEnvelope = true
			break
		end
	end
	self.band.Visible = hasEnvelope
	if hasEnvelope then
		local columns = self._bandColumns
		for j = 1, BAND_COLUMNS do
			local existing: Frame? = columns[j]
			local column: Frame
			if existing then
				column = existing
			else
				column = Instance.new("Frame")
				column.Name = "Column"
				column.BackgroundColor3 = c.accent
				column.BackgroundTransparency = 0.82
				column.BorderSizePixel = 0
				column.Active = false
				column.Interactable = false
				column.Parent = self.band
				columns[j] = column
			end
			local t = (j - 0.5) / BAND_COLUMNS
			local v, e = valueAt(t), envelopeAt(t)
			local top = self:_yScale(clamp(v + e, lo, hi))
			local bottom = self:_yScale(clamp(v - e, lo, hi))
			column.Position = UDim2.fromScale((j - 1) / BAND_COLUMNS, top)
			column.Size = UDim2.fromScale(1 / BAND_COLUMNS, math.max(0, bottom - top))
		end
		local upper: { Vector2 } = table.create(n)
		local lower: { Vector2 } = table.create(n)
		for i, kp in keys do
			local t = kp[1]
			local v, e = valueAt(t), envelopeAt(t)
			upper[i] = self:_toLocal(t, clamp(v + e, lo, hi))
			lower[i] = self:_toLocal(t, clamp(v - e, lo, hi))
		end
		Draw.setPolyline(self.bandTop, upper)
		Draw.setPolyline(self.bandBottom, lower)
	end

	-- zero line (signed ranges such as Squash)
	self.zeroLine.Visible = lo < 0 and hi > 0
	if lo < 0 and hi > 0 then
		self.zeroLine.Position = UDim2.fromScale(0, self:_yScale(0))
	end

	-- keypoints
	local sel = self._selected
	for i, kp in keys do
		local existing: Frame? = self.dots[i]
		local dot: Frame
		if existing then
			dot = existing
		else
			dot = Draw.dot(self.pointsLayer, Vector2.zero, 4, c.text, { name = "Point", stroke = c.bg0 })
			self.dots[i] = dot
		end
		local selected = i == sel
		Draw.setDot(dot, self:_toLocal(kp[1], kp[2]), if selected then 5 else 4)
		dot.BackgroundColor3 = if not enabled then c.textMuted elseif selected then c.accent else c.text
		local outline = dot:FindFirstChild("Outline") :: UIStroke?
		if outline then
			outline.Color = if selected then c.keyframeSelected else c.bg0
		end
		dot.Visible = true
	end
	for i = n + 1, #self.dots do
		self.dots[i].Visible = false
	end

	-- envelope handles of the selected keypoint
	local showHandles = enabled and sel ~= nil and keys[sel] ~= nil
	for i = 1, 2 do
		self.handles[i].Visible = showHandles
		self.handleLines[i].Visible = showHandles
	end
	if showHandles and sel then
		local top, bottom, dot = self:_handleLocal(sel)
		Draw.setDot(self.handles[1], top)
		Draw.setDot(self.handles[2], bottom)
		Draw.setLine(self.handleLines[1], dot, top)
		Draw.setLine(self.handleLines[2], dot, bottom)
	end

	-- labels
	local span = hi - lo
	local decimals = math.clamp(2 - math.floor(math.log10(span / 4) + 1e-9), 0, 4)
	for i = 0, 4 do
		self.valueLabels[i + 1].Text = Kit.format(hi - span * i / 4, decimals)
	end
	self.countLabel.Text = n .. "/" .. MAX_KEYPOINTS

	-- fields
	local kp = if sel then keys[sel] else nil
	local fields = self.fields
	if kp then
		fields.time:setValue(kp[1])
		fields.value:setValue(kp[2])
		fields.envelope:setValue(kp[3])
	else
		fields.time:setMixed(true)
		fields.value:setMixed(true)
		fields.envelope:setMixed(true)
	end
	fields.time:setEnabled(enabled and kp ~= nil and sel ~= 1 and sel ~= n)
	fields.value:setEnabled(enabled and kp ~= nil)
	fields.envelope:setEnabled(enabled and kp ~= nil)
end

return SequenceEditor
