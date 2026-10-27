--!strict
--[[
	GradientEditor — ColorSequence editor working on the JSON colorSequence form.

		local tint = GradientEditor.new({
			value = { { 0, "#FFFFFF" }, { 0.4, "#FFB23D" }, { 1, "$ember" } }, -- or a plain colour "#FF8A3D"
			palette = { ember = "#C81E0A" },       -- optional: "$key" colours (name -> "#RRGGBB" or Color3)
			host = host,                           -- { plugin, widget, root }: drags, popups, tooltips
			onChange = function(value, final) ... end, -- final = false while dragging, true once at the end
			onSelect = function(index) end,       -- optional: selection changed
			maxKeypoints = 20,                     -- optional (2..20, the engine limit is 20)
			inlinePicker = false,                  -- true: ColorPicker embedded below; false: swatch -> popup picker
			parent = row,
		})
		tint:setValue("#33C3B0")                   -- display only, no callbacks
		tint:addKeypoint(0.5)                      -- the programmatic methods behave like user edits

	Engine rules (docs/research/api-particles-beams-trails.md): 2..20 keypoints, the first at time 0, the last at
	time 1, linear RGB interpolation. The value reported by onChange is Codec.normalize("colorSequence", ...), so
	two identical keypoints collapse into the plain colour string.

	Interaction:
	* Bar (UIGradient of the decoded sequence): pressing adds a keypoint with the colour evaluated at that time
	  (Curves.evaluateColorSequence) and selects it; dragging before releasing moves it (one gesture, one undo
	  step). At the keypoint limit the add button is disabled and the bar shows a tooltip instead.
	* Handles below the bar: click selects, dragging moves the time (first/last stay at 0/1, the others are
	  clamped between their neighbours, times rounded to 0.001), right-click removes (never first/last, min 2).
	* Toolbar: presets (solid, two-tone from the current endpoints, fire, ice, energy), add (+, in the middle of
	  the widest gap), delete (−, the selected keypoint).
	* Selected keypoint: colour via ColorPicker (popup from the swatch, or inline), time NumberInput.
	Every gesture reports onChange(v, false) while it runs and onChange(v, true) once at the end; discrete edits
	report true. A setValue that equals the current value is ignored, so re-renders during a drag are harmless.
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Input = require(script.Parent.Parent.Input)
local Kit = require(script.Parent.Parent.Widgets.ControlKit)
local Tooltip = require(script.Parent.Parent.Widgets.Tooltip)
local NumberInput = require(script.Parent.Parent.Widgets.NumberInput)
local IconButton = require(script.Parent.Parent.Widgets.IconButton)
local Dropdown = require(script.Parent.Parent.Widgets.Dropdown)
local ColorSwatch = require(script.Parent.Parent.Widgets.ColorSwatch)
local ColorPicker = require(script.Parent.ColorPicker)
local Draw = require(script.Parent.Draw)
local Codec = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Codec)
local Curves = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Curves)
local Constants = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Constants)

-- { time, colour } with colour "#RRGGBB" or "$key"
export type Keypoint = { any }

export type Props = {
	value: any?,
	palette: { [string]: any }?,
	host: Kit.Host?,
	onChange: ((value: any, final: boolean) -> ())?,
	onSelect: ((index: number) -> ())?,
	maxKeypoints: number?,
	inlinePicker: boolean?,
	enabled: boolean?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

export type Preset = { value: string, label: string, description: string? }

type Handle = { button: TextButton, chip: Frame, stem: Frame, stroke: UIStroke }

type Gesture = { index: number, offset: number, kind: string }

local GradientEditor = {}
GradientEditor.__index = GradientEditor

GradientEditor.MAX_KEYPOINTS = Constants.MAX_SEQUENCE_KEYPOINTS -- 20
GradientEditor.LIMIT_TEXT = "Höchstens %d Keypoints – entferne einen, um einen neuen hinzuzufügen"
GradientEditor.TIME_DECIMALS = 3

GradientEditor.PRESETS = {
	{ value = "solid", label = "Einfarbig", description = "Farbe des gewählten Keypoints" },
	{ value = "twoTone", label = "Zweifarbig", description = "Nur Anfangs- und Endfarbe" },
	{ value = "fire", label = "Feuer", description = "Weißglut → Orange → Glut" },
	{ value = "ice", label = "Eis", description = "Weiß → Eisblau → Tiefblau" },
	{ value = "energy", label = "Energie", description = "Weiß → Cyan → Violett" },
} :: { Preset }

-- Fixed presets in JSON form (colorSequence keypoints).
GradientEditor.PRESET_VALUES = {
	fire = {
		{ 0, "#FFF4C2" },
		{ 0.2, "#FFD34D" },
		{ 0.45, "#FF8A1F" },
		{ 0.75, "#D7340F" },
		{ 1, "#3D0B05" },
	},
	ice = {
		{ 0, "#FFFFFF" },
		{ 0.3, "#C8F1FF" },
		{ 0.65, "#5BB8FF" },
		{ 1, "#1C3D99" },
	},
	energy = {
		{ 0, "#FFFFFF" },
		{ 0.25, "#8CF8FF" },
		{ 0.6, "#8B6CFF" },
		{ 1, "#2B0F66" },
	},
} :: { [string]: { Keypoint } }

type EditorData = {
	instance: Frame,
	presets: any, -- Dropdown
	addButton: any, -- IconButton
	deleteButton: any, -- IconButton
	bar: Frame,
	gradient: UIGradient,
	barHit: TextButton,
	track: Frame,
	handles: { Handle },
	swatch: any?, -- ColorSwatch (popup mode)
	picker: any?, -- ColorPicker (inline mode)
	timeInput: any, -- NumberInput
	_maid: any,
	_handleMaid: any,
	_props: Props,
	_host: Kit.Host?,
	_palette: { [string]: any }?,
	_max: number,
	_keypoints: { Keypoint },
	_value: any,
	_sequence: ColorSequence,
	_selected: number,
	_gesture: Gesture?,
	_pending: boolean,
	_enabled: boolean,
	_popup: any?, -- open ColorPicker popup
	_addTooltipLimited: boolean?,
	_destroyed: boolean,
}

export type GradientEditor = typeof(setmetatable({} :: EditorData, GradientEditor))

local c = Theme.colors
local ROW = Theme.metrics.rowHeight
local GAP = 6
local BAR_HEIGHT = 22
local TRACK_HEIGHT = 18
local INSET = 7 -- half a handle: the end handles stay inside the editor
local HANDLE_WIDTH = 12
local TIME_WIDTH = 96

-- Helpers --------------------------------------------------------------------------------------------------------

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function copyKeypoints(list: { Keypoint }): { Keypoint }
	local out: { Keypoint } = table.create(#list)
	for i, kp in list do
		out[i] = { kp[1], kp[2] }
	end
	return out
end

local function roundTime(t: number): number
	return Kit.round(math.clamp(t, 0, 1), GradientEditor.TIME_DECIMALS)
end

-- Canonical keypoint list and value of any JSON colorSequence (invalid values become white).
local function parse(value: any): ({ Keypoint }, any)
	local ok, normalized = pcall(Codec.normalize :: any, "colorSequence", value)
	if not ok then
		normalized = "#FFFFFF"
	end
	if type(normalized) == "string" then
		return { { 0, normalized }, { 1, normalized } }, normalized
	end
	return copyKeypoints(normalized), normalized
end

-- JSON value of a keypoint list (two identical keypoints collapse into the colour).
local function encode(list: { Keypoint }): any
	return Codec.normalize("colorSequence", list)
end

-- Value of a preset for the current keypoints (nil for unknown ids).
function GradientEditor.presetValue(id: string, keypoints: { Keypoint }?, selected: number?): any
	local list: { Keypoint } = keypoints or { { 0, "#FFFFFF" }, { 1, "#FFFFFF" } }
	if id == "solid" then
		local kp = list[selected or 1] or list[1]
		return Codec.normalize("colorSequence", { { 0, kp[2] }, { 1, kp[2] } })
	elseif id == "twoTone" then
		return Codec.normalize("colorSequence", { { 0, list[1][2] }, { 1, list[#list][2] } })
	end
	local fixed = GradientEditor.PRESET_VALUES[id]
	if fixed then
		return Codec.normalize("colorSequence", fixed)
	end
	return nil
end

-- Construction -------------------------------------------------------------------------------------------------

function GradientEditor.new(props: Props): GradientEditor
	local maid = Maid.new()
	local host = props.host
	local max =
		math.clamp(math.floor(props.maxKeypoints or GradientEditor.MAX_KEYPOINTS), 2, GradientEditor.MAX_KEYPOINTS)
	local keypoints, value = parse(props.value)

	local root = Instance.new("Frame")
	root.Name = "GradientEditor"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	Kit.applyCommon(root, props :: any)
	maid:give(root)

	local self = setmetatable({
		instance = root,
		presets = nil :: any,
		addButton = nil :: any,
		deleteButton = nil :: any,
		bar = nil :: any,
		gradient = nil :: any,
		barHit = nil :: any,
		track = nil :: any,
		handles = {},
		swatch = nil :: any,
		picker = nil :: any,
		timeInput = nil :: any,
		_maid = maid,
		_handleMaid = Maid.new(),
		_props = props,
		_host = host,
		_palette = props.palette,
		_max = max,
		_keypoints = keypoints,
		_value = value,
		_sequence = ColorSequence.new(Color3.new(1, 1, 1)),
		_selected = 1,
		_gesture = nil :: Gesture?,
		_pending = false,
		_enabled = props.enabled ~= false,
		_popup = nil :: any,
		_addTooltipLimited = nil :: boolean?,
		_destroyed = false,
	}, GradientEditor)

	-- toolbar ---------------------------------------------------------------------------------------------------
	local presetOptions: { any } = {}
	for _, preset in GradientEditor.PRESETS do
		table.insert(presetOptions, { value = preset.value, label = preset.label, description = preset.description })
	end
	local presets = Dropdown.new({
		name = "Presets",
		options = presetOptions,
		placeholder = "Vorlage…",
		host = host,
		size = UDim2.new(1, -(ROW * 2 + 8), 0, ROW),
		onChange = function(id: any)
			self.presets:setValue(nil)
			self:applyPreset(id)
		end,
	})
	presets.instance.Parent = root
	maid:give(presets)
	self.presets = presets

	local addSlot = Instance.new("Frame")
	addSlot.Name = "AddSlot"
	addSlot.BackgroundTransparency = 1
	addSlot.Position = UDim2.new(1, -(ROW * 2 + 4), 0, 0)
	addSlot.Size = UDim2.fromOffset(ROW, ROW)
	addSlot.Parent = root
	local add = IconButton.new({
		name = "Add",
		glyph = "+",
		tooltip = "Keypoint hinzufügen",
		host = host,
		onActivate = function()
			self:addKeypoint(self:_widestGapTime())
		end,
	})
	add.instance.Parent = addSlot
	maid:give(add)
	self.addButton = add
	if host then
		-- a disabled button may not receive hover events: the slot explains the limit
		maid:give(Tooltip.attach(host, addSlot, function(): string?
			return if self:canAdd() then nil else self:_limitText()
		end))
	end

	local delete = IconButton.new({
		name = "Delete",
		glyph = "−",
		tooltip = "Gewählten Keypoint entfernen (oder Rechtsklick auf einen Griff)",
		host = host,
		position = UDim2.new(1, -ROW, 0, 0),
		onActivate = function()
			self:removeKeypoint(self._selected)
		end,
	})
	delete.instance.Parent = root
	maid:give(delete)
	self.deleteButton = delete

	-- bar + handles ------------------------------------------------------------------------------------------------
	local y = ROW + GAP
	local bar = Instance.new("Frame")
	bar.Name = "Preview" -- user content: shows the edited gradient
	-- UIGradient multiplies the background colour: a white background shows the sequence as it is.
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(INSET, y)
	bar.Size = UDim2.new(1, -INSET * 2, 0, BAR_HEIGHT)
	bar.Parent = root
	Kit.corner(3).Parent = bar
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Gradient"
	gradient.Parent = bar
	self.bar = bar
	self.gradient = gradient
	-- the border is a separate frame: a UIStroke on the bar itself would be tinted by its UIGradient
	local border = Instance.new("Frame")
	border.Name = "Border"
	border.BackgroundTransparency = 1
	border.BorderSizePixel = 0
	border.Position = bar.Position
	border.Size = bar.Size
	border.Parent = root
	Kit.corner(3).Parent = border
	Kit.stroke(c.borderStrong).Parent = border

	local barHit = Instance.new("TextButton")
	barHit.Name = "BarHit"
	barHit.Text = ""
	barHit.AutoButtonColor = false
	barHit.BackgroundTransparency = 1
	barHit.BorderSizePixel = 0
	barHit.Selectable = false
	barHit.Position = bar.Position
	barHit.Size = bar.Size
	barHit.ZIndex = 2
	barHit.Parent = root
	self.barHit = barHit
	if host then
		maid:give(Tooltip.attach(host, barHit, function(): string?
			return if self:canAdd() then "Klicken: Keypoint hinzufügen" else self:_limitText()
		end))
	end
	y += BAR_HEIGHT + 2

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Position = UDim2.fromOffset(INSET, y)
	track.Size = UDim2.new(1, -INSET * 2, 0, TRACK_HEIGHT)
	track.Parent = root
	self.track = track
	y += TRACK_HEIGHT + GAP

	-- selected keypoint: colour + time ------------------------------------------------------------------------------
	local timeInput = NumberInput.new({
		name = "Time",
		label = "Zeit",
		value = 0,
		min = 0,
		max = 1,
		step = 0.01,
		precision = GradientEditor.TIME_DECIMALS,
		host = host,
		tooltip = "Zeit des gewählten Keypoints (0..1)",
		position = UDim2.new(1, -TIME_WIDTH, 0, y),
		size = UDim2.fromOffset(TIME_WIDTH, ROW),
		onChange = function(v: number, final: boolean)
			self:setKeypointTime(self._selected, v, final)
		end,
	})
	timeInput.instance.Parent = root
	maid:give(timeInput)
	self.timeInput = timeInput

	if props.inlinePicker then
		local swatchRow = Instance.new("TextLabel")
		swatchRow.Name = "SelectedLabel"
		swatchRow.BackgroundTransparency = 1
		swatchRow.Position = UDim2.fromOffset(0, y)
		swatchRow.Size = UDim2.new(1, -(TIME_WIDTH + GAP), 0, ROW)
		swatchRow.FontFace = Theme.fonts.medium
		swatchRow.TextSize = Theme.textSize.small
		swatchRow.TextColor3 = c.textDim
		swatchRow.TextXAlignment = Enum.TextXAlignment.Left
		swatchRow.Text = ""
		swatchRow.Parent = root
		y += ROW + GAP
		local picker = ColorPicker.new({
			name = "Picker",
			value = keypoints[1][2],
			palette = props.palette,
			host = host,
			position = UDim2.fromOffset(0, y),
			onChange = function(v: string, final: boolean)
				self:setKeypointColor(self._selected, v, final)
			end,
		})
		picker.instance.Parent = root
		maid:give(picker)
		self.picker = picker
		y += picker.instance.Size.Y.Offset
	else
		local swatch = ColorSwatch.new({
			name = "Color",
			value = keypoints[1][2],
			palette = props.palette :: any,
			host = host,
			tooltip = "Farbe des gewählten Keypoints",
			position = UDim2.fromOffset(0, y),
			size = UDim2.new(1, -(TIME_WIDTH + GAP), 0, ROW),
			onPick = function()
				self:openPicker()
			end,
		})
		swatch.instance.Parent = root
		maid:give(swatch)
		self.swatch = swatch
		y += ROW
	end

	root.Size = props.size or UDim2.new(1, 0, 0, y)

	-- gestures -----------------------------------------------------------------------------------------------------
	if host and host.widget then
		maid:give(Input.drag(host.widget, barHit, {
			onPress = function(pos: Vector2, _mods: Input.Mods)
				if not self._enabled or not self:canAdd() then
					return -- at the limit the bar's tooltip explains why nothing happens
				end
				local index = self:_insert(self:_timeAt(pos), nil, true)
				if index then
					self._gesture = { index = index, offset = 0, kind = "bar" }
				end
			end,
			onMove = function(pos: Vector2, _delta: Vector2, _mods: Input.Mods)
				local g = self._gesture
				if g and g.kind == "bar" then
					self:_moveTo(g.index, self:_timeAt(pos), true)
				end
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, _moved: boolean)
				local g = self._gesture
				if g and g.kind == "bar" then
					self._gesture = nil
					self:_emit(true)
				end
			end,
		}, { threshold = 2 }))
	end
	maid:give(self._handleMaid)
	maid:give(function()
		if self._popup then
			self._popup:close()
			self._popup = nil
		end
	end)

	self:_rebuild()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

-- Geometry ------------------------------------------------------------------------------------------------------

-- Time (0..1, rounded to TIME_DECIMALS) at a widget-space mouse position.
function GradientEditor._timeAt(self: GradientEditor, pos: Vector2): number
	local p, size = Kit.geometry(self.track)
	return roundTime((pos.X - p.X) / math.max(1, size.X))
end

function GradientEditor._widestGapTime(self: GradientEditor): number
	local list = self._keypoints
	local best, at = -1, 0.5
	for i = 1, #list - 1 do
		local gap = list[i + 1][1] - list[i][1]
		if gap > best then
			best = gap
			at = (list[i][1] + list[i + 1][1]) / 2
		end
	end
	return roundTime(at)
end

function GradientEditor._limitText(self: GradientEditor): string
	return string.format(GradientEditor.LIMIT_TEXT, self._max)
end

-- Colours ---------------------------------------------------------------------------------------------------------

function GradientEditor._resolve(self: GradientEditor, colour: any): Color3
	return Codec.parseColor(colour, self._palette :: any) or c.textMuted
end

-- Decoded ColorSequence of the current keypoints (palette references resolved; unknown references are grey).
function GradientEditor._decode(self: GradientEditor): ColorSequence
	local ok, seq = pcall(Codec.decode :: any, "colorSequence", self._keypoints, nil, self._palette)
	if ok and typeof(seq) == "ColorSequence" then
		return seq
	end
	local keys: { ColorSequenceKeypoint } = {}
	for i, kp in self._keypoints do
		keys[i] = ColorSequenceKeypoint.new(kp[1], self:_resolve(kp[2]))
	end
	return ColorSequence.new(keys)
end

-- State changes ---------------------------------------------------------------------------------------------------

--[[
	Reports the current keypoints. Non-final reports only happen when the value changed; a final report happens
	when it changed or when it closes earlier non-final reports (one undo step per gesture).
]]
function GradientEditor._emit(self: GradientEditor, final: boolean)
	if self._destroyed then
		return -- child widgets ending their gestures while being cleaned up report nothing more
	end
	local value = encode(self._keypoints)
	local changed = not deepEqual(value, self._value)
	self._value = value
	if final then
		if changed or self._pending then
			self._pending = false
			if self._props.onChange then
				self._props.onChange(value, true)
			end
		end
	elseif changed then
		self._pending = true
		if self._props.onChange then
			self._props.onChange(value, false)
		end
	end
end

-- Inserts a keypoint at `time` (colour evaluated there unless given) and selects it; `report` sends the
-- non-final report of a gesture. Returns the new index, or nil at the limit.
function GradientEditor._insert(self: GradientEditor, time: number, colour: any?, report: boolean): number?
	if not self:canAdd() then
		return nil
	end
	local list = self._keypoints
	local t = roundTime(time)
	local value: any = colour
	if value == nil then
		value = Codec.toHex(Curves.evaluateColorSequence(self._sequence, t))
	else
		value = Codec.normalize("color3", value)
	end
	-- after every keypoint with time <= t, but never after the last one (it stays at 1) or before the first
	local index = #list
	for i = 2, #list do
		if list[i][1] > t then
			index = i
			break
		end
	end
	table.insert(list, index, { t, value })
	self._selected = index
	self:_rebuild()
	if report then
		self:_emit(false)
	end
	if self._props.onSelect then
		self._props.onSelect(index)
	end
	return index
end

-- Moves keypoint `index` to `time` (clamped between its neighbours; first/last are fixed); `report` sends a
-- non-final report. Returns true when the time changed.
function GradientEditor._moveTo(self: GradientEditor, index: number, time: number, report: boolean): boolean
	local list = self._keypoints
	if index <= 1 or index >= #list then
		return false
	end
	local t = math.clamp(roundTime(time), list[index - 1][1], list[index + 1][1])
	if t == list[index][1] then
		return false
	end
	list[index][1] = t
	self:_refresh()
	if report then
		self:_emit(false)
	end
	return true
end

-- Display ------------------------------------------------------------------------------------------------------------

function GradientEditor._buildHandle(self: GradientEditor, index: number): Handle
	local button = Instance.new("TextButton")
	button.Name = "Handle"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Selectable = false
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Size = UDim2.fromOffset(HANDLE_WIDTH, TRACK_HEIGHT)
	button.ZIndex = 3
	local stem = Draw.line(button, Vector2.new(HANDLE_WIDTH / 2, 0), Vector2.new(HANDLE_WIDTH / 2, 5), 2, c.textDim, {
		name = "Stem",
	})
	local chip = Instance.new("Frame")
	chip.Name = "Chip" -- user content: the keypoint colour
	chip.BorderSizePixel = 0
	chip.Position = UDim2.fromOffset(0, 5)
	chip.Size = UDim2.fromOffset(HANDLE_WIDTH, HANDLE_WIDTH)
	chip.Interactable = false
	chip.Parent = button
	Kit.corner(3).Parent = chip
	local stroke = Kit.stroke(c.borderStrong)
	stroke.Name = "Outline"
	stroke.Parent = button
	Kit.corner(3).Parent = button
	button.Parent = self.track

	local maid = self._handleMaid
	maid:give(button)
	local host = self._host
	if host and host.widget then
		maid:give(Input.drag(host.widget, button, {
			onPress = function(pos: Vector2, _mods: Input.Mods)
				if not self._enabled then
					return
				end
				self:selectKeypoint(index)
				local kp = self._keypoints[index]
				if kp then
					self._gesture = { index = index, offset = kp[1] - self:_timeAt(pos), kind = "handle" }
				end
			end,
			onMove = function(pos: Vector2, _delta: Vector2, _mods: Input.Mods)
				local g = self._gesture
				if g and g.kind == "handle" and g.index == index then
					self:_moveTo(index, self:_timeAt(pos) + g.offset, true)
				end
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, _moved: boolean)
				local g = self._gesture
				if g and g.kind == "handle" and g.index == index then
					self._gesture = nil
					self:_emit(true)
				end
			end,
		}, { threshold = 2 }))
	else
		maid:give(button.Activated:Connect(function()
			if self._enabled then
				self:selectKeypoint(index)
			end
		end))
	end
	maid:give(Input.onRightClick(button, function()
		if self._enabled then
			self:removeKeypoint(index)
		end
	end))
	if host then
		maid:give(Tooltip.attach(host, button, function(): string?
			local kp = self._keypoints[index]
			if kp == nil then
				return nil
			end
			local fixed = if index == 1 or index == #self._keypoints then " (fest)" else ""
			return string.format("%s @ %s%s", tostring(kp[2]), Kit.format(kp[1], 3), fixed)
		end))
	end
	return { button = button, chip = chip, stem = stem, stroke = stroke }
end

-- Recreates the handles when the keypoint count changed, then refreshes everything.
function GradientEditor._rebuild(self: GradientEditor)
	if #self.handles ~= #self._keypoints then
		self._handleMaid:clean()
		table.clear(self.handles)
		for i = 1, #self._keypoints do
			self.handles[i] = self:_buildHandle(i)
		end
	end
	self:_refresh()
end

function GradientEditor._refresh(self: GradientEditor)
	local list = self._keypoints
	local n = #list
	local enabled = self._enabled
	self._selected = math.clamp(self._selected, 1, n)
	local selected = self._selected
	self._sequence = self:_decode()
	self.gradient.Color = self._sequence
	for i, handle in self.handles do
		local kp = list[i]
		if kp then
			local isSelected = i == selected
			handle.button.Position = UDim2.new(kp[1], 0, 0, 0)
			handle.button.Interactable = enabled
			handle.chip.BackgroundColor3 = self:_resolve(kp[2])
			handle.stroke.Color = if isSelected then c.accent else c.borderStrong
			handle.stroke.Thickness = if isSelected then 2 else 1
			handle.stem.BackgroundColor3 = if isSelected
				then c.accent
				elseif i == 1 or i == n then c.textMuted
				else c.textDim
			handle.button.ZIndex = if isSelected then 4 else 3
		end
	end
	local canAdd = self:canAdd()
	self.addButton:setEnabled(enabled and canAdd)
	if self._addTooltipLimited ~= not canAdd then
		self._addTooltipLimited = not canAdd
		self.addButton:setTooltip(if canAdd then "Keypoint hinzufügen" else self:_limitText())
	end
	self.deleteButton:setEnabled(enabled and self:canRemove(selected))
	self.presets:setEnabled(enabled)
	self.barHit.Interactable = enabled

	local kp = list[selected]
	local movable = selected > 1 and selected < n
	if movable then
		self.timeInput:setRange(list[selected - 1][1], list[selected + 1][1])
	else
		self.timeInput:setRange(0, 1)
	end
	if not self.timeInput:isDragging() then
		self.timeInput:setValue(kp[1])
	end
	self.timeInput:setEnabled(enabled and movable)
	if self.swatch then
		self.swatch:setValue(kp[2])
		self.swatch:setEnabled(enabled)
	end
	if self.picker then
		self.picker:setValue(kp[2])
		self.picker:setEnabled(enabled)
		local label = self.instance:FindFirstChild("SelectedLabel") :: TextLabel?
		if label then
			label.Text = string.format("Keypoint %d / %d", selected, n)
		end
	end
end

-- Public API -----------------------------------------------------------------------------------------------------

-- Display only (no callbacks). Equal values are ignored; the selection index is kept (clamped).
function GradientEditor.setValue(self: GradientEditor, value: any)
	local keypoints, normalized = parse(value)
	if deepEqual(normalized, self._value) then
		return
	end
	self._keypoints = keypoints
	self._value = normalized
	self:_rebuild()
end

-- Current JSON colorSequence (canonical: a colour string when both keypoints are equal).
function GradientEditor.getValue(self: GradientEditor): any
	return self._value
end

-- Copy of the keypoint list { { time, colour }, ... } (always at least 2 entries).
function GradientEditor.getKeypoints(self: GradientEditor): { Keypoint }
	return copyKeypoints(self._keypoints)
end

function GradientEditor.keypointCount(self: GradientEditor): number
	return #self._keypoints
end

-- Decoded sequence shown by the bar.
function GradientEditor.getSequence(self: GradientEditor): ColorSequence
	return self._sequence
end

function GradientEditor.getSelected(self: GradientEditor): number
	return self._selected
end

function GradientEditor.getMaxKeypoints(self: GradientEditor): number
	return self._max
end

function GradientEditor.canAdd(self: GradientEditor): boolean
	return #self._keypoints < self._max
end

function GradientEditor.canRemove(self: GradientEditor, index: number): boolean
	return index > 1 and index < #self._keypoints and #self._keypoints > 2
end

-- Adds a keypoint like a click on the bar (colour evaluated at `time` unless given). Returns the index or nil.
function GradientEditor.addKeypoint(self: GradientEditor, time: number, colour: any?): number?
	local index = self:_insert(time, colour, false)
	if index then
		self:_emit(true)
	end
	return index
end

-- Removes a keypoint (never the first/last; at least 2 remain). Returns true when removed.
function GradientEditor.removeKeypoint(self: GradientEditor, index: number): boolean
	if not self:canRemove(index) then
		return false
	end
	table.remove(self._keypoints, index)
	if self._gesture then
		self._gesture = nil
	end
	local previous = self._selected
	if previous >= index then
		self._selected = math.max(1, previous - 1)
	end
	self:_rebuild()
	self:_emit(true)
	if self._selected ~= previous and self._props.onSelect then
		self._props.onSelect(self._selected)
	end
	return true
end

-- Selects a keypoint (no value change). Returns false for invalid indices.
function GradientEditor.selectKeypoint(self: GradientEditor, index: number): boolean
	if self._keypoints[index] == nil then
		return false
	end
	if index ~= self._selected then
		self._selected = index
		self:_refresh()
		if self._props.onSelect then
			self._props.onSelect(index)
		end
	end
	return true
end

-- Sets a keypoint's time like the time field (clamped between the neighbours; first/last are fixed).
-- final = false (scrubbing) reports non-final changes; the default reports onChange(v, true).
function GradientEditor.setKeypointTime(self: GradientEditor, index: number, time: number, final: boolean?): boolean
	local list = self._keypoints
	if index <= 1 or index >= #list then
		return false
	end
	local isFinal = final ~= false
	self:_moveTo(index, time, not isFinal)
	if isFinal then
		self:_emit(true)
	end
	return true
end

-- Sets a keypoint's colour (any JSON colour form; "$key" stays a reference) like the colour picker.
function GradientEditor.setKeypointColor(self: GradientEditor, index: number, colour: any, final: boolean?): boolean
	local kp = self._keypoints[index]
	if kp == nil then
		return false
	end
	local ok, canonical = pcall(Codec.normalize :: any, "color3", colour)
	if not ok then
		return false
	end
	local isFinal = final ~= false
	if kp[2] ~= canonical then
		kp[2] = canonical
		self:_refresh()
		if not isFinal then
			self:_emit(false)
		end
	end
	if isFinal then
		self:_emit(true)
	end
	return true
end

-- Applies a preset ("solid", "twoTone", "fire", "ice", "energy"). Reports onChange(v, true).
function GradientEditor.applyPreset(self: GradientEditor, id: string): boolean
	local value = GradientEditor.presetValue(id, self._keypoints, self._selected)
	if value == nil then
		return false
	end
	local keypoints = parse(value)
	if #keypoints > self._max then
		return false
	end
	self._keypoints = keypoints
	self._selected = math.clamp(self._selected, 1, #keypoints)
	self:_rebuild()
	self:_emit(true)
	return true
end

-- Opens the colour picker for the selected keypoint: the popup (swatch mode, needs host) or the inline picker.
function GradientEditor.openPicker(self: GradientEditor): any
	if self.picker then
		return self.picker
	end
	local host = self._host
	if host == nil or not self._enabled then
		return nil
	end
	local index = self._selected
	local kp = self._keypoints[index]
	local popup = ColorPicker.open(host, {
		value = kp[2],
		palette = self._palette,
		anchor = if self.swatch then self.swatch.instance else nil,
		title = string.format("Keypoint %d", index),
		onChange = function(v: string, final: boolean)
			if not self._destroyed then
				self:setKeypointColor(index, v, final)
			end
		end,
		onClose = function()
			self._popup = nil
		end,
	})
	self._popup = popup
	return popup
end

-- Replaces the palette used to resolve "$key" colours (and the inline picker's chips).
function GradientEditor.setPalette(self: GradientEditor, palette: { [string]: any }?)
	self._palette = palette
	self._props = table.clone(self._props)
	self._props.palette = palette
	if self.swatch then
		self.swatch:setPalette(palette :: any)
	end
	if self.picker then
		local old = self.picker
		local picker = ColorPicker.new({
			name = "Picker",
			value = self._keypoints[self._selected][2],
			palette = palette,
			host = self._host,
			position = old.instance.Position,
			onChange = function(v: string, final: boolean)
				self:setKeypointColor(self._selected, v, final)
			end,
		})
		picker.instance.Parent = self.instance
		self._maid:give(picker)
		old:destroy()
		self.picker = picker
	end
	self:_refresh()
end

function GradientEditor.isDragging(self: GradientEditor): boolean
	return self._gesture ~= nil
end

function GradientEditor.setEnabled(self: GradientEditor, enabled: boolean)
	self._enabled = enabled
	if not enabled and self._popup then
		self._popup:close()
		self._popup = nil
	end
	self:_refresh()
end

function GradientEditor.destroy(self: GradientEditor)
	if self._destroyed then
		return
	end
	-- a running gesture (bar, handle, time scrub, picker drag) still ends with final = true
	self._gesture = nil
	if self._pending then
		self:_emit(true)
	end
	self._destroyed = true
	self._maid:clean()
end

return GradientEditor
