--!strict
--[[
	EasingPicker — compact easing field: a button with a mini curve and the easing's name that opens a popup with
	every style × direction as thumbnails, plus a bezier mode (two draggable handles, x1/y1/x2/y2 fields and the CSS
	presets ease, ease-in, ease-out, ease-in-out).

		local easing = EasingPicker.new({
			value = "Quad.Out",              -- EasingDef JSON form: "Linear" | "Constant" | "Style.Dir" | { bezier = {x1, y1, x2, y2} }
			host = host,                     -- { plugin, widget, root }; the popup is parented to host.root
			onChange = function(value, final) -- bezier drags/scrubs: final = false while dragging, then true once
				editor:setKeyEasing(trackId, index, value)
			end,
			parent = row,
		})
		easing:setValue({ bezier = { 0.42, 0, 0.58, 1 } })   -- display only, no callbacks
		easing:choose("Back.InOut")                          -- like a click on that thumbnail

	Values: style choices are reported in the explicit form "Style.Direction" ("Quad.Out", "Elastic.InOut"); Linear
	and Constant have no direction ("Linear", "Constant"). Beziers are { bezier = { x1, y1, x2, y2 } } with x1, x2
	clamped to 0..1 (Easing requires a monotone x(s)), y1, y2 to -2..3 and all four rounded to 3 decimals.
	setValue accepts every form Easing.check accepts ("Quad" = "Quad.Out", nil = "Linear").

	Popup: closes on a style choice, a click outside (transparent overlay in host.root), right-click outside,
	WindowFocusReleased, a second click on the button, setEnabled(false), destroy() and when the button is destroyed
	with an ancestor. In bezier mode it stays open while editing. Thumbnails sample Easing.get / Easing.parse; the
	bezier preview draws the parametric curve P0 (0,0), P1, P2, P3 (1,1) (Draw.bezier) — the same curve Easing.bezier
	evaluates as y(x).
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Input = require(script.Parent.Parent.Input)
local Kit = require(script.Parent.Parent.Widgets.ControlKit)
local Button = require(script.Parent.Parent.Widgets.Button)
local NumberInput = require(script.Parent.Parent.Widgets.NumberInput)
local Draw = require(script.Parent.Draw)
local Easing = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Easing)

export type Props = {
	value: any?,
	host: Kit.Host?,
	size: UDim2?,
	enabled: boolean?,
	onChange: ((value: any, final: boolean) -> ())?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local EasingPicker = {}
EasingPicker.__index = EasingPicker

type CellState = { button: TextButton, stroke: UIStroke, curve: Frame, points: { Vector2 }, hovered: boolean }

type EasingPickerData = {
	instance: TextButton,
	thumb: Frame,
	thumbCurve: Frame,
	label: TextLabel,
	arrow: TextLabel,
	popup: Frame?,
	overlay: TextButton?,
	cells: { [string]: TextButton }, -- thumbnail buttons by definition ("Quad.Out", "Linear", ...)
	_cellStates: { [string]: CellState },
	modeButtons: { [string]: any }, -- Buttons
	stylesPage: ScrollingFrame?,
	bezierPage: Frame?,
	preview: TextButton?,
	previewCurve: Frame?,
	previewLines: { Frame },
	bezierHandles: { Frame },
	bezierInputs: { any }, -- NumberInputs x1, y1, x2, y2
	presetButtons: { [string]: any },
	_maid: any,
	_popupMaid: any,
	_stroke: UIStroke,
	_props: Props,
	_value: any,
	_bezier: { number },
	_mode: string,
	_open: boolean,
	_enabled: boolean,
	_hovered: boolean,
	_destroyed: boolean,
	_dragHandle: number?,
	_dragChanged: boolean,
}

export type EasingPicker = typeof(setmetatable({} :: EasingPickerData, EasingPicker))

local c = Theme.colors
local ROW = Theme.metrics.rowHeight

local STYLE_LABEL_W = 64
local CELL_W = 44
local CELL_H = 26
local CELL_GAP = 4
local ROW_H = CELL_H + 4
local HEADER_H = 16
local POPUP_PAD = 6
local POPUP_W = POPUP_PAD * 2 + STYLE_LABEL_W + 3 * CELL_W + 2 * CELL_GAP + 8 -- + scroll bar
local MODE_H = ROW + 8
local PREVIEW_H = 150
local PREVIEW_PAD = 14
local PREVIEW_Y_MIN = -0.6
local PREVIEW_Y_MAX = 1.6
local HANDLE_RADIUS = 5
local HANDLE_HIT = 10
local THUMB_W = 30
local THUMB_H = 16
local Y_MIN = -2
local Y_MAX = 3
local DECIMALS = 3

EasingPicker.STYLES = Easing.STYLES
EasingPicker.DIRECTIONS = Easing.DIRECTIONS

-- CSS timing functions (cubic-bezier control points).
EasingPicker.CSS_PRESETS = {
	{ name = "ease", bezier = { 0.25, 0.1, 0.25, 1 } },
	{ name = "ease-in", bezier = { 0.42, 0, 1, 1 } },
	{ name = "ease-out", bezier = { 0, 0, 0.58, 1 } },
	{ name = "ease-in-out", bezier = { 0.42, 0, 0.58, 1 } },
}

local DEFAULT_BEZIER = { 0.25, 0.1, 0.25, 1 }

-- helpers ---------------------------------------------------------------------------------------------------------

local function directionless(style: string): boolean
	return style == "Linear" or style == "Constant"
end

local function split(def: string): (string, string?)
	local dot = string.find(def, ".", 1, true)
	if dot == nil then
		return def, nil
	end
	return string.sub(def, 1, dot - 1), string.sub(def, dot + 1)
end

local function roundTo(x: number, decimals: number): number
	local r = Kit.round(x, decimals)
	return if r == 0 then 0 else r
end

local function clampBezier(b: { number }): { number }
	return {
		roundTo(math.clamp(b[1], 0, 1), DECIMALS),
		roundTo(math.clamp(b[2], Y_MIN, Y_MAX), DECIMALS),
		roundTo(math.clamp(b[3], 0, 1), DECIMALS),
		roundTo(math.clamp(b[4], Y_MIN, Y_MAX), DECIMALS),
	}
end

local function sameBezier(a: { number }, b: { number }): boolean
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

--[[
	Explicit JSON form of a valid easing definition: "Style.Direction" for styles with a direction (the default
	direction is written out: "Quad" -> "Quad.Out"), "Linear" / "Constant" without one, beziers copied
	({ bezier = { x1, y1, x2, y2 } }). nil -> "Linear". Returns nil for invalid definitions.
]]
function EasingPicker.explicit(def: any): any
	if def == nil then
		return "Linear"
	end
	local ok = Easing.check(def)
	if not ok then
		return nil
	end
	if type(def) == "string" then
		local style, direction = split(def)
		if directionless(style) then
			return style
		end
		return style .. "." .. (direction or Easing.DEFAULT_DIRECTION)
	end
	local b = def.bezier
	return { bezier = { b[1], b[2], b[3], b[4] } }
end

-- Display name: "Quad.Out", "Linear", a CSS preset name ("ease-in-out") or "Bezier x1, y1, x2, y2".
function EasingPicker.label(def: any): string
	local explicit = EasingPicker.explicit(def)
	if explicit == nil then
		return "?"
	elseif type(explicit) == "string" then
		return explicit
	end
	local b = explicit.bezier
	for _, preset in EasingPicker.CSS_PRESETS do
		if sameBezier(preset.bezier, b) then
			return preset.name
		end
	end
	return string.format(
		"Bezier %s, %s, %s, %s",
		Kit.format(b[1], 2),
		Kit.format(b[2], 2),
		Kit.format(b[3], 2),
		Kit.format(b[4], 2)
	)
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

local function sameValue(a: any, b: any): boolean
	if type(a) == "table" and type(b) == "table" then
		return sameBezier(a.bezier, b.bezier)
	end
	return a == b
end

-- `n` + 1 points of an easing curve fitted into a box of `size` with `pad` px padding (y up). The vertical range
-- covers 0..1 and any overshoot of the curve.
local function curvePoints(fn: (number) -> number, n: number, size: Vector2, pad: number): { Vector2 }
	local values: { number } = table.create(n + 1)
	local lo, hi = 0, 1
	for i = 0, n do
		local v = fn(i / n)
		values[i + 1] = v
		lo = math.min(lo, v)
		hi = math.max(hi, v)
	end
	local w = size.X - 2 * pad
	local h = size.Y - 2 * pad
	local points: { Vector2 } = table.create(n + 1)
	for i = 0, n do
		local y = (values[i + 1] - lo) / (hi - lo)
		points[i + 1] = Vector2.new(pad + w * i / n, pad + h * (1 - y))
	end
	return points
end

local function samplesFor(style: string): number
	if style == "Elastic" or style == "Bounce" then
		return 28
	elseif style == "Constant" then
		return 40 -- keeps the step at the end steep
	end
	return 16
end

local function easingFn(def: any): ((number) -> number, string)
	local explicit = EasingPicker.explicit(def)
	if type(explicit) == "string" then
		local style, direction = split(explicit)
		return Easing.get(style, direction), style
	end
	local fn = Easing.parse(explicit)
	return fn, "Bezier"
end

local function newLabel(parent: Instance, name: string, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = Theme.fonts.regular
	l.TextSize = Theme.textSize.small
	l.TextColor3 = c.textDim
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = text
	l.Parent = parent
	return l
end

-- construction ----------------------------------------------------------------------------------------------------

function EasingPicker.new(props: Props): EasingPicker
	local maid = Maid.new()

	local root = Instance.new("TextButton")
	root.Name = "EasingPicker"
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundColor3 = c.bg2
	root.BorderSizePixel = 0
	root.Selectable = false
	root.Size = props.size or UDim2.new(1, 0, 0, ROW)
	Kit.applyCommon(root, props :: any)
	Kit.corner().Parent = root
	local stroke = Kit.stroke()
	stroke.Parent = root
	maid:give(root)

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.BackgroundColor3 = c.bg0
	thumb.BorderSizePixel = 0
	thumb.AnchorPoint = Vector2.new(0, 0.5)
	thumb.Position = UDim2.new(0, 4, 0.5, 0)
	thumb.Size = UDim2.fromOffset(THUMB_W, THUMB_H)
	thumb.Active = false
	Kit.corner(2).Parent = thumb
	thumb.Parent = root
	local thumbCurve = Draw.polyline(thumb, {}, 1, c.accent, { name = "Curve" })

	local label = newLabel(root, "Label", "")
	label.Position = UDim2.fromOffset(THUMB_W + 10, 0)
	label.Size = UDim2.new(1, -(THUMB_W + 30), 1, 0)
	label.TextSize = Theme.textSize.normal
	label.TextColor3 = c.text

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

	local initial = EasingPicker.explicit(props.value) or "Linear"
	local self = setmetatable({
		instance = root,
		thumb = thumb,
		thumbCurve = thumbCurve,
		label = label,
		arrow = arrow,
		popup = nil :: Frame?,
		overlay = nil :: TextButton?,
		cells = {},
		_cellStates = {},
		modeButtons = {},
		stylesPage = nil :: ScrollingFrame?,
		bezierPage = nil :: Frame?,
		preview = nil :: TextButton?,
		previewCurve = nil :: Frame?,
		previewLines = {},
		bezierHandles = {},
		bezierInputs = {},
		presetButtons = {},
		_maid = maid,
		_popupMaid = nil :: any,
		_stroke = stroke,
		_props = props,
		_value = initial,
		_bezier = if type(initial) == "table" then table.clone(initial.bezier) else table.clone(DEFAULT_BEZIER),
		_mode = if type(initial) == "table" then "bezier" else "styles",
		_open = false,
		_enabled = props.enabled ~= false,
		_hovered = false,
		_destroyed = false,
		_dragHandle = nil :: number?,
		_dragChanged = false,
	}, EasingPicker)

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

-- button ----------------------------------------------------------------------------------------------------------

function EasingPicker._refresh(self: EasingPicker)
	if self._destroyed then
		return
	end
	local enabled = self._enabled
	self.label.Text = EasingPicker.label(self._value)
	self.label.TextColor3 = if enabled then c.text else c.textMuted
	self.arrow.TextColor3 = if enabled then (if self._open then c.text else c.textDim) else c.textMuted
	self._stroke.Color = if self._open then c.accent elseif self._hovered and enabled then c.borderStrong else c.border
	self.instance.BackgroundColor3 = if not enabled then c.bg1 elseif self._hovered then c.bg3 else c.bg2
	self.instance.Interactable = enabled
	local fn, style = easingFn(self._value)
	Draw.setPolyline(
		self.thumbCurve,
		curvePoints(fn, samplesFor(style), Vector2.new(THUMB_W, THUMB_H), 2),
		1,
		if enabled then c.accent else c.textMuted
	)
end

-- popup -----------------------------------------------------------------------------------------------------------

function EasingPicker.isOpen(self: EasingPicker): boolean
	return self._open
end

function EasingPicker.getMode(self: EasingPicker): string
	return self._mode
end

-- Opens the popup (needs props.host with a root). No-op when disabled or already open.
function EasingPicker.open(self: EasingPicker)
	local host = self._props.host
	if self._open or not self._enabled or self._destroyed or host == nil or (host.root :: any) == nil then
		return
	end
	local popupMaid = Maid.new()
	self._popupMaid = popupMaid
	self._open = true

	local overlay = Kit.overlay(host, "AstraEasingOverlay", Kit.Z.popup, function()
		self:close()
	end)
	popupMaid:give(overlay)
	self.overlay = overlay

	local popup = Instance.new("Frame")
	popup.Name = "AstraEasingPopup"
	popup.BackgroundColor3 = c.bg2
	popup.BorderSizePixel = 0
	popup.Active = true -- sinks clicks so they do not reach the overlay underneath
	popup.ClipsDescendants = true
	Kit.corner().Parent = popup
	Kit.stroke(c.borderStrong).Parent = popup
	popupMaid:give(popup)
	self.popup = popup

	-- mode bar
	local modes = { { id = "styles", text = "Stile" }, { id = "bezier", text = "Bezier" } }
	for i, mode in modes do
		local button = Button.new({
			name = "Mode_" .. mode.id,
			text = mode.text,
			variant = if self._mode == mode.id then "primary" else "ghost",
			size = UDim2.fromOffset(72, ROW),
			position = UDim2.fromOffset(POPUP_PAD + (i - 1) * 76, POPUP_PAD),
			onActivate = function()
				self:setMode(mode.id)
			end,
		})
		button.instance.Parent = popup
		popupMaid:give(button)
		self.modeButtons[mode.id] = button
	end

	self:_buildStyles(popup, popupMaid)
	self:_buildBezier(popup, popupMaid, host)

	-- size and position: below the button, above when there is no room, clamped into the root
	local rootPos, rootSize = Kit.geometry(host.root)
	local buttonPos, buttonSize = Kit.geometry(self.instance)
	local contentH = math.max(HEADER_H + #Easing.STYLES * ROW_H, PREVIEW_H + 3 * (ROW + 4) + 4)
	local width = POPUP_W
	local height = math.min(MODE_H + contentH + POPUP_PAD, math.max(ROW * 4, rootSize.Y - 8))
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

	self:_applyMode()
	self:_refreshPopup()
	popup.Parent = host.root
	Kit.raise(popup, Kit.Z.popup + 1)
	self:_refresh()
end

function EasingPicker._buildStyles(self: EasingPicker, popup: Frame, popupMaid: any)
	local page = Instance.new("ScrollingFrame")
	page.Name = "Styles"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Position = UDim2.fromOffset(POPUP_PAD, MODE_H)
	page.Size = UDim2.new(1, -POPUP_PAD, 1, -(MODE_H + POPUP_PAD))
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.ScrollBarThickness = Theme.metrics.scrollBar
	page.ScrollBarImageColor3 = c.borderStrong
	page.CanvasSize = UDim2.fromOffset(0, HEADER_H + #Easing.STYLES * ROW_H)
	page.Parent = popup
	self.stylesPage = page

	for i, direction in Easing.DIRECTIONS do
		local header = newLabel(page, "Header_" .. direction, direction)
		header.TextSize = Theme.textSize.tiny
		header.TextColor3 = c.textMuted
		header.TextXAlignment = Enum.TextXAlignment.Center
		header.Position = UDim2.fromOffset(STYLE_LABEL_W + (i - 1) * (CELL_W + CELL_GAP), 0)
		header.Size = UDim2.fromOffset(CELL_W, HEADER_H)
	end

	for row, style in Easing.STYLES do
		local y = HEADER_H + (row - 1) * ROW_H
		local styleLabel = newLabel(page, "Style_" .. style, style)
		styleLabel.Position = UDim2.fromOffset(0, y)
		styleLabel.Size = UDim2.fromOffset(STYLE_LABEL_W - 4, CELL_H)
		if directionless(style) then
			self:_buildCell(
				page,
				popupMaid,
				style,
				style,
				UDim2.fromOffset(STYLE_LABEL_W, y),
				3 * CELL_W + 2 * CELL_GAP
			)
		else
			for i, direction in Easing.DIRECTIONS do
				local x = STYLE_LABEL_W + (i - 1) * (CELL_W + CELL_GAP)
				self:_buildCell(page, popupMaid, style, style .. "." .. direction, UDim2.fromOffset(x, y), CELL_W)
			end
		end
	end
end

function EasingPicker._buildCell(
	self: EasingPicker,
	page: ScrollingFrame,
	popupMaid: any,
	style: string,
	def: string,
	position: UDim2,
	width: number
)
	local cell = Instance.new("TextButton")
	cell.Name = def
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.BackgroundColor3 = c.bg1
	cell.BorderSizePixel = 0
	cell.Selectable = false
	cell.Position = position
	cell.Size = UDim2.fromOffset(width, CELL_H)
	Kit.corner(3).Parent = cell
	local cellStroke = Kit.stroke()
	cellStroke.Parent = cell
	cell.Parent = page
	local points = curvePoints(Easing.get(split(def)), samplesFor(style), Vector2.new(width, CELL_H), 4)
	local curve = Draw.polyline(cell, points, 1, c.textDim, { name = "Curve" })
	local state: CellState = { button = cell, stroke = cellStroke, curve = curve, points = points, hovered = false }
	self._cellStates[def] = state
	self.cells[def] = cell
	popupMaid:give(cell.MouseEnter:Connect(function()
		state.hovered = true
		self:_paintCell(def)
	end))
	popupMaid:give(cell.MouseLeave:Connect(function()
		state.hovered = false
		self:_paintCell(def)
	end))
	popupMaid:give(cell.Activated:Connect(function()
		self:choose(def)
	end))
	self:_paintCell(def)
end

-- Selected / hovered look of one thumbnail cell.
function EasingPicker._paintCell(self: EasingPicker, def: string)
	local state = self._cellStates[def]
	if state == nil then
		return
	end
	local selected = sameValue(self._value, def)
	state.button.BackgroundColor3 = if selected then c.accentDim elseif state.hovered then c.bg3 else c.bg1
	state.stroke.Color = if selected then c.accent else c.border
	Draw.setPolyline(state.curve, state.points, 1, if selected or state.hovered then c.text else c.textDim)
end

function EasingPicker._buildBezier(self: EasingPicker, popup: Frame, popupMaid: any, host: Kit.Host)
	local page = Instance.new("Frame")
	page.Name = "Bezier"
	page.BackgroundTransparency = 1
	page.Position = UDim2.fromOffset(POPUP_PAD, MODE_H)
	page.Size = UDim2.new(1, -2 * POPUP_PAD, 1, -(MODE_H + POPUP_PAD))
	page.Parent = popup
	self.bezierPage = page

	local previewW = POPUP_W - 2 * POPUP_PAD
	local preview = Instance.new("TextButton")
	preview.Name = "Preview"
	preview.Text = ""
	preview.AutoButtonColor = false
	preview.BackgroundColor3 = c.bg0
	preview.BorderSizePixel = 0
	preview.Selectable = false
	preview.Size = UDim2.fromOffset(previewW, PREVIEW_H)
	Kit.corner().Parent = preview
	Kit.stroke().Parent = preview
	preview.Parent = page
	self.preview = preview

	local size = Vector2.new(previewW, PREVIEW_H)
	local function at(x: number, y: number): Vector2
		return self:_previewPoint(x, y, size)
	end
	-- reference lines: y = 0, y = 1 and the linear diagonal
	Draw.line(preview, at(0, 0), at(1, 0), 1, c.gridMajor, { name = "Axis" })
	Draw.line(preview, at(0, 1), at(1, 1), 1, c.gridMajor, { name = "Axis" })
	Draw.line(preview, at(0, 0), at(0, 1), 1, c.gridMinor, { name = "Axis" })
	Draw.line(preview, at(1, 0), at(1, 1), 1, c.gridMinor, { name = "Axis" })
	Draw.line(preview, at(0, 0), at(1, 1), 1, c.gridMinor, { name = "Diagonal" })
	self.previewLines = {
		Draw.line(preview, at(0, 0), at(0, 0), 1, c.textDim, { name = "HandleLine" }),
		Draw.line(preview, at(1, 1), at(1, 1), 1, c.textDim, { name = "HandleLine" }),
	}
	self.previewCurve = Draw.polyline(preview, {}, 2, c.accent, { name = "Curve" })
	Draw.dot(preview, at(0, 0), 3, c.text, { name = "End" })
	Draw.dot(preview, at(1, 1), 3, c.text, { name = "End" })
	self.bezierHandles = {
		Draw.dot(preview, at(0, 0), HANDLE_RADIUS, c.teal, { name = "Handle1", stroke = c.bg0 }),
		Draw.dot(preview, at(1, 1), HANDLE_RADIUS, c.teal, { name = "Handle2", stroke = c.bg0 }),
	}

	-- x1 / y1 / x2 / y2 fields (two rows)
	local names = { "x1", "y1", "x2", "y2" }
	local fieldW = (previewW - 4) / 2
	for i, name in names do
		local isX = i % 2 == 1
		local input = NumberInput.new({
			name = name,
			label = name,
			value = self._bezier[i],
			min = if isX then 0 else Y_MIN,
			max = if isX then 1 else Y_MAX,
			step = 0.01,
			precision = DECIMALS,
			host = host,
			size = UDim2.fromOffset(fieldW, ROW),
			position = UDim2.fromOffset(
				if i <= 2 then (i - 1) * (fieldW + 4) else (i - 3) * (fieldW + 4),
				PREVIEW_H + 4 + (if i <= 2 then 0 else ROW + 4)
			),
			onChange = function(v: number, final: boolean)
				local b = table.clone(self._bezier)
				b[i] = v
				self:setBezier(b[1], b[2], b[3], b[4], final)
			end,
		})
		input.instance.Parent = page
		popupMaid:give(input)
		self.bezierInputs[i] = input
	end

	-- CSS presets
	local presetW = (previewW - 3 * 4) / 4
	for i, preset in EasingPicker.CSS_PRESETS do
		local button = Button.new({
			name = "Preset_" .. preset.name,
			text = preset.name,
			variant = "secondary",
			size = UDim2.fromOffset(presetW, ROW),
			position = UDim2.fromOffset((i - 1) * (presetW + 4), PREVIEW_H + 4 + 2 * (ROW + 4)),
			onActivate = function()
				self:applyPreset(preset.name)
			end,
		})
		button.instance.Parent = page
		popupMaid:give(button)
		self.presetButtons[preset.name] = button
	end

	-- dragging the handles
	local widget = host.widget
	if widget then
		popupMaid:give(Input.drag(widget, preview, {
			onPress = function(pos: Vector2, _mods: Input.Mods)
				self._dragHandle = self:_hitHandle(pos)
				self._dragChanged = false
			end,
			onMove = function(pos: Vector2, _delta: Vector2, _mods: Input.Mods)
				local handle = self._dragHandle
				if handle == nil or not self._enabled then
					return
				end
				local x, y = self:previewPixelToPoint(pos)
				local b = table.clone(self._bezier)
				b[handle * 2 - 1] = x
				b[handle * 2] = math.clamp(y, PREVIEW_Y_MIN, PREVIEW_Y_MAX)
				if self:_applyBezier(b) then
					self._dragChanged = true
					self:_emit(false)
				end
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, _moved: boolean)
				local changed = self._dragHandle ~= nil and self._dragChanged
				self._dragHandle = nil
				self._dragChanged = false
				if changed then
					self:_emit(true)
				end
			end,
		}, { threshold = 1 }))
	end
end

-- Pixel position (inside the preview) of a bezier-space point (x 0..1, y PREVIEW_Y_MIN..PREVIEW_Y_MAX, y up).
function EasingPicker._previewPoint(_self: EasingPicker, x: number, y: number, size: Vector2): Vector2
	local w = size.X - 2 * PREVIEW_PAD
	local h = size.Y - 2 * PREVIEW_PAD
	local ny = (y - PREVIEW_Y_MIN) / (PREVIEW_Y_MAX - PREVIEW_Y_MIN)
	return Vector2.new(PREVIEW_PAD + x * w, PREVIEW_PAD + (1 - ny) * h)
end

function EasingPicker._previewGeometry(self: EasingPicker): (Vector2, Vector2)
	local preview = self.preview
	if preview == nil then
		return Vector2.zero, Vector2.new(1, 1)
	end
	return Kit.geometry(preview)
end

-- Widget-space pixel of a bezier-space point in the preview (for tests and hosts). Needs an open popup.
function EasingPicker.previewPointToPixel(self: EasingPicker, x: number, y: number): Vector2
	local pos, size = self:_previewGeometry()
	return pos + self:_previewPoint(x, y, size)
end

-- Widget-space pixel -> bezier-space point (x clamped to 0..1, y unclamped).
function EasingPicker.previewPixelToPoint(self: EasingPicker, pixel: Vector2): (number, number)
	local pos, size = self:_previewGeometry()
	local l = pixel - pos
	local w = math.max(size.X - 2 * PREVIEW_PAD, 1)
	local h = math.max(size.Y - 2 * PREVIEW_PAD, 1)
	local x = math.clamp((l.X - PREVIEW_PAD) / w, 0, 1)
	local y = PREVIEW_Y_MIN + (1 - (l.Y - PREVIEW_PAD) / h) * (PREVIEW_Y_MAX - PREVIEW_Y_MIN)
	return x, y
end

-- Widget-space pixel of bezier handle 1 or 2.
function EasingPicker.handlePixel(self: EasingPicker, handle: number): Vector2
	local b = self._bezier
	local y = math.clamp(b[handle * 2], PREVIEW_Y_MIN, PREVIEW_Y_MAX)
	return self:previewPointToPixel(b[handle * 2 - 1], y)
end

function EasingPicker._hitHandle(self: EasingPicker, pixel: Vector2): number?
	if self._mode ~= "bezier" or not self._enabled then
		return nil
	end
	local best: number? = nil
	local bestDistance = HANDLE_HIT
	for handle = 1, 2 do
		local d = (self:handlePixel(handle) - pixel).Magnitude
		if d <= bestDistance then
			best, bestDistance = handle, d
		end
	end
	return best
end

function EasingPicker._applyMode(self: EasingPicker)
	local mode = self._mode
	if self.stylesPage then
		(self.stylesPage :: ScrollingFrame).Visible = mode == "styles"
	end
	if self.bezierPage then
		(self.bezierPage :: Frame).Visible = mode == "bezier"
	end
	for id, button in self.modeButtons do
		button:setVariant(if id == mode then "primary" else "ghost")
	end
end

-- Updates the open popup to the current value (selected cell, bezier preview, fields).
function EasingPicker._refreshPopup(self: EasingPicker)
	if not self._open then
		return
	end
	for def in self._cellStates do
		self:_paintCell(def)
	end
	local preview = self.preview
	if preview then
		local size = Vector2.new(preview.Size.X.Offset, preview.Size.Y.Offset)
		local b = self._bezier
		local p0 = self:_previewPoint(0, 0, size)
		local p3 = self:_previewPoint(1, 1, size)
		local p1 = self:_previewPoint(b[1], math.clamp(b[2], PREVIEW_Y_MIN, PREVIEW_Y_MAX), size)
		local p2 = self:_previewPoint(b[3], math.clamp(b[4], PREVIEW_Y_MIN, PREVIEW_Y_MAX), size)
		-- the parametric curve through the unclamped control points (Easing.bezier evaluates the same curve)
		local q1 = self:_previewPoint(b[1], b[2], size)
		local q2 = self:_previewPoint(b[3], b[4], size)
		local curve = self.previewCurve
		if curve then
			Draw.setPolyline(curve, Draw.bezier(p0, q1, q2, p3, 40), 2, if self._enabled then c.accent else c.textMuted)
		end
		Draw.setLine(self.previewLines[1], p0, p1)
		Draw.setLine(self.previewLines[2], p3, p2)
		Draw.setDot(self.bezierHandles[1], p1)
		Draw.setDot(self.bezierHandles[2], p2)
	end
	for i, input in self.bezierInputs do
		input:setValue(self._bezier[i])
	end
end

-- Switches the popup between "styles" and "bezier" (does not change the value).
function EasingPicker.setMode(self: EasingPicker, mode: string)
	if mode ~= "styles" and mode ~= "bezier" then
		return
	end
	self._mode = mode
	self:_applyMode()
	self:_refreshPopup()
end

function EasingPicker.close(self: EasingPicker)
	if not self._open then
		return
	end
	self._open = false
	local popupMaid = self._popupMaid
	self._popupMaid = nil
	self.popup = nil
	self.overlay = nil
	self.stylesPage = nil
	self.bezierPage = nil
	self.preview = nil
	self.previewCurve = nil
	self.previewLines = {}
	self.bezierHandles = {}
	self.bezierInputs = {}
	self.presetButtons = {}
	self.modeButtons = {}
	table.clear(self.cells)
	table.clear(self._cellStates)
	if popupMaid then
		popupMaid:clean() -- a handle drag in progress ends with onChange(value, true)
	end
	self:_refresh()
end

-- value -----------------------------------------------------------------------------------------------------------

function EasingPicker._emit(self: EasingPicker, final: boolean)
	self:_refresh()
	self:_refreshPopup()
	local onChange = self._props.onChange
	if onChange then
		onChange(deepCopy(self._value), final)
	end
end

-- Sets the bezier state and value (clamped, rounded). Returns true when the value changed.
function EasingPicker._applyBezier(self: EasingPicker, b: { number }): boolean
	local clamped = clampBezier(b)
	local current = self._value
	self._bezier = clamped
	self._mode = "bezier"
	if type(current) == "table" and sameBezier(current.bezier, clamped) then
		return false
	end
	self._value = { bezier = table.clone(clamped) }
	return true
end

-- Sets the value without firing callbacks. Invalid definitions are ignored (returns false).
function EasingPicker.setValue(self: EasingPicker, def: any): boolean
	local explicit = EasingPicker.explicit(def)
	if explicit == nil then
		return false
	end
	if sameValue(explicit, self._value) then
		return true
	end
	self._value = explicit
	if type(explicit) == "table" then
		self._bezier = clampBezier(explicit.bezier)
		if self._dragHandle == nil then
			self._mode = "bezier"
		end
	end
	if self._open then
		self:_applyMode()
	end
	self:_refresh()
	self:_refreshPopup()
	return true
end

-- Explicit JSON form (a fresh table for beziers).
function EasingPicker.getValue(self: EasingPicker): any
	return deepCopy(self._value)
end

-- Chooses a definition as if the user clicked it: fires onChange(value, true) when it differs. Style choices
-- close the popup. Returns false for invalid definitions.
function EasingPicker.choose(self: EasingPicker, def: any): boolean
	if not self._enabled then
		return false
	end
	local explicit = EasingPicker.explicit(def)
	if explicit == nil then
		return false
	end
	if type(explicit) == "table" then
		local b = explicit.bezier
		self:setBezier(b[1], b[2], b[3], b[4], true)
		return true
	end
	local changed = not sameValue(explicit, self._value)
	self._value = explicit
	self._mode = "styles"
	self:close()
	self:_refresh()
	if changed then
		local onChange = self._props.onChange
		if onChange then
			onChange(explicit, true)
		end
	end
	return true
end

-- Bezier edit (fields, presets, programmatic). `final` defaults to true; onChange fires when the value changed or
-- when final is true (closing a scrub gesture).
function EasingPicker.setBezier(self: EasingPicker, x1: number, y1: number, x2: number, y2: number, final: boolean?)
	if not self._enabled then
		return
	end
	local isFinal = final ~= false
	local changed = self:_applyBezier({ x1, y1, x2, y2 })
	if self._open then
		self:_applyMode()
	end
	if changed or isFinal then
		self:_emit(isFinal)
	else
		self:_refreshPopup()
	end
end

-- Applies a CSS preset ("ease", "ease-in", "ease-out", "ease-in-out"). Returns false for unknown names.
function EasingPicker.applyPreset(self: EasingPicker, name: string): boolean
	for _, preset in EasingPicker.CSS_PRESETS do
		if preset.name == name then
			local b = preset.bezier
			self:setBezier(b[1], b[2], b[3], b[4], true)
			return true
		end
	end
	return false
end

function EasingPicker.isDragging(self: EasingPicker): boolean
	return self._dragHandle ~= nil
end

function EasingPicker.setEnabled(self: EasingPicker, enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self._hovered = false
		self:close()
	end
	self:_refresh()
end

function EasingPicker.destroy(self: EasingPicker)
	if self._destroyed then
		return
	end
	self:close()
	self._destroyed = true
	self._maid:clean()
end

return EasingPicker
