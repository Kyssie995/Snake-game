--!strict
--[[
	ColorPicker — HSV colour editor working on JSON colour values ("#RRGGBB" or "$paletteKey").

		-- inline (e.g. inside the GradientEditor or a panel)
		local picker = ColorPicker.new({
			value = "#FF8A3D",                       -- "#RRGGBB" | "#RGB" | [r, g, b] | "$key" | Color3
			palette = { accent = "#8B6CFF" },        -- optional: name -> "#RRGGBB" (Color3 accepted); shows chips,
			                                         -- choosing one returns "$accent"
			host = host,                             -- { plugin, widget, root }: drags, tooltips, recent colours
			onChange = function(value, final) ... end, -- final = false while dragging, true once at the end
			parent = body,
		})
		picker:setValue("#33C3B0")                   -- display only, no callbacks

		-- popup in host.root (transparent overlay; a click outside closes it)
		ColorPicker.open(host, {
			value = swatch:getValue(),
			anchor = swatch.instance,                -- placed below (or above) this GuiObject, clamped into the root
			onChange = function(v, final) swatch:commit(v, final) end,
			onClose = function() end,
		})

	Parts: saturation/value square (two stacked frames: white -> hue via UIGradient, then black with a
	transparency UIGradient), hue bar (UIGradient with 7 hue stops), preview (original | current; clicking the
	original reverts), hex field (validates "#RRGGBB", "RRGGBB", "#RGB" and "$key" of the palette), R/G/B
	NumberInputs (0..255, scrubbable), palette chips and the recent colours of the host (max 8, shared by every
	picker on that host.root, newest first; a colour is recorded whenever an edit is committed with final = true).

	Gestures: pressing the square/bar jumps there (onChange(v, false)), dragging follows (false), releasing reports
	onChange(v, true) once. Typed values, chips and the R/G/B fields (typing) report true; scrubbing R/G/B reports
	false then true. The HSV state is kept while editing, so the hue survives greys and black. Values set with
	setValue that equal the current value are ignored (the editor re-renders fields during a gesture).

	Drags use UI/Input.drag with host.widget (no UserInputService). Only one popup is open per host.
]]

local Theme = require(script.Parent.Parent.Theme)
local Maid = require(script.Parent.Parent.Maid)
local Input = require(script.Parent.Parent.Input)
local Kit = require(script.Parent.Parent.Widgets.ControlKit)
local Tooltip = require(script.Parent.Parent.Widgets.Tooltip)
local TextInput = require(script.Parent.Parent.Widgets.TextInput)
local NumberInput = require(script.Parent.Parent.Widgets.NumberInput)
local IconButton = require(script.Parent.Parent.Widgets.IconButton)
local Draw = require(script.Parent.Draw)
local Codec = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Codec)
local Constants = require(script.Parent.Parent.Parent.Parent.AstraVFX.Core.Constants)

export type Props = {
	value: any?,
	palette: { [string]: any }?, -- name -> "#RRGGBB" (or Color3)
	host: Kit.Host?,
	onChange: ((value: string, final: boolean) -> ())?,
	onClose: (() -> ())?, -- popup only
	showPreview: boolean?, -- default true
	showRecent: boolean?, -- default true (needs host)
	title: string?, -- popup header (default "Farbe")
	anchor: GuiObject?, -- popup only
	at: Vector2?, -- popup only: position in host.root when there is no anchor (default: the mouse)
	width: number?, -- default 232
	size: UDim2?, -- overrides the computed size (the layout inside stays fixed)
	enabled: boolean?,
	name: string?,
	position: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
}

local ColorPicker = {}
ColorPicker.__index = ColorPicker

ColorPicker.MAX_RECENT = 8
ColorPicker.WIDTH = 232

type PaletteEntry = { name: string, ref: string, color: Color3 }

type PickerData = {
	instance: Frame,
	svArea: Frame,
	svHit: TextButton,
	svCursor: Frame,
	hueGradient: UIGradient,
	hueArea: Frame,
	hueHit: TextButton,
	hueCursor: Frame,
	original: TextButton?,
	current: Frame?,
	hexInput: any, -- TextInput
	rgbInputs: { any }, -- NumberInputs R, G, B
	paletteChips: { [string]: TextButton },
	recentChips: { TextButton },
	recentRow: Frame?,
	closeButton: any?,
	_hueLayer: Frame,
	_recentMaid: any,
	overlay: TextButton?,
	_maid: any,
	_props: Props,
	_host: Kit.Host?,
	_palette: { PaletteEntry },
	_value: string,
	_color: Color3,
	_h: number,
	_s: number,
	_v: number,
	_originalValue: string,
	_dragging: string?, -- "sv" | "hue" while a press/drag is in progress
	_pending: boolean, -- a non-final change was reported and not yet closed with final = true
	_enabled: boolean,
	_popup: boolean,
	_open: boolean,
	_destroyed: boolean,
}

export type ColorPicker = typeof(setmetatable({} :: PickerData, ColorPicker))

local c = Theme.colors
local PAD = 8
local GAP = 6
local CHIP = 18
local CHIP_GAP = 4
local SV_HEIGHT = 132
local HUE_HEIGHT = 12
local HEADER = 24
local CAPTION = 14
local PREVIEW_WIDTH = 44

-- Colours ------------------------------------------------------------------------------------------------------

-- HSV (0..1 each) -> RGB (0..1 each).
function ColorPicker.hsvToRgb(h: number, s: number, v: number): (number, number, number)
	h = (h % 1) * 6
	s = math.clamp(s, 0, 1)
	v = math.clamp(v, 0, 1)
	local i = math.floor(h)
	local f = h - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, q
end

-- RGB (0..1 each) -> HSV (0..1 each); hue 0 for greys.
function ColorPicker.rgbToHsv(r: number, g: number, b: number): (number, number, number)
	local max = math.max(r, g, b)
	local min = math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then
			h = ((g - b) / d) % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	local s = if max > 0 then d / max else 0
	return h, s, max
end

local function hexOf(color: Color3): string
	return Codec.toHex(color)
end

local function hsvHex(h: number, s: number, v: number): string
	local r, g, b = ColorPicker.hsvToRgb(h, s, v)
	return hexOf(Color3.new(r, g, b))
end

local function isPaletteKey(key: string): boolean
	return #key >= 1 and #key <= Constants.ID_MAX_LENGTH and string.match(key, Constants.ID_PATTERN) ~= nil
end

-- Resolves a palette entry (Color3 or colour string) to a Color3.
local function paletteColor(entry: any): Color3?
	if typeof(entry) == "Color3" then
		return entry
	end
	if type(entry) == "string" and string.sub(entry, 1, 1) ~= "$" then
		return Codec.parseColor(entry)
	end
	return nil
end

--[[
	Parses text typed into the hex field: "#RRGGBB", "RRGGBB", "#RGB", "RGB" (case-insensitive, surrounding spaces
	ignored) -> canonical "#RRGGBB"; "$key" -> "$key" when the palette has that key. nil otherwise.
]]
function ColorPicker.parseInput(text: string, palette: { [string]: any }?): string?
	local s = string.gsub(text, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	if string.sub(s, 1, 1) == "$" then
		local key = string.sub(s, 2)
		if palette and isPaletteKey(key) and paletteColor(palette[key]) then
			return s
		end
		return nil
	end
	local hex = string.match(s, "^#?(%x+)$")
	if hex and (#hex == 6 or #hex == 3) then
		return Codec.normalize("color3", "#" .. hex)
	end
	return nil
end

-- Canonical JSON colour of `value` (nil when it is not a colour).
local function canonical(value: any): string?
	if typeof(value) == "Color3" then
		return hexOf(value)
	end
	local ok, result = pcall(Codec.normalize :: any, "color3", value)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

-- Recent colours ------------------------------------------------------------------------------------------------

-- Recent colours of a host (newest first, at most MAX_RECENT "#RRGGBB" strings). The list is live; do not mutate.
function ColorPicker.recent(host: Kit.Host): { string }
	local state = Kit.hostState(host, "colorPickerRecent")
	if state.list == nil then
		state.list = {}
	end
	return state.list
end

-- Records a colour as most recent ("#RRGGBB"; other values are ignored).
function ColorPicker.pushRecent(host: Kit.Host, value: string)
	if type(value) ~= "string" or string.match(value, "^#%x%x%x%x%x%x$") == nil then
		return
	end
	local list = ColorPicker.recent(host)
	local index = table.find(list, value)
	if index then
		table.remove(list, index)
	end
	table.insert(list, 1, value)
	while #list > ColorPicker.MAX_RECENT do
		table.remove(list)
	end
end

-- Construction ---------------------------------------------------------------------------------------------------

local function palettesEntries(palette: { [string]: any }?): { PaletteEntry }
	local out: { PaletteEntry } = {}
	if palette then
		for name, entry in palette do
			if type(name) == "string" and isPaletteKey(name) then
				local color = paletteColor(entry)
				if color then
					table.insert(out, { name = name, ref = "$" .. name, color = color })
				end
			end
		end
	end
	table.sort(out, function(a: PaletteEntry, b: PaletteEntry): boolean
		return a.name < b.name
	end)
	return out
end

local function chipButton(color: Color3, x: number, y: number): TextButton
	local chip = Instance.new("TextButton")
	chip.Name = "Chip"
	chip.Text = ""
	chip.AutoButtonColor = false
	chip.BorderSizePixel = 0
	chip.Selectable = false
	chip.BackgroundColor3 = color
	chip.Position = UDim2.fromOffset(x, y)
	chip.Size = UDim2.fromOffset(CHIP, CHIP)
	Kit.corner(3).Parent = chip
	local stroke = Kit.stroke(c.borderStrong)
	stroke.Name = "Outline"
	stroke.Parent = chip
	return chip
end

local function caption(parent: Instance, text: string, y: number, width: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Caption"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(PAD, y)
	label.Size = UDim2.fromOffset(width, CAPTION)
	label.FontFace = Theme.fonts.medium
	label.TextSize = Theme.textSize.tiny
	label.TextColor3 = c.textMuted
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

local function chipsPerRow(inner: number): number
	return math.max(1, math.floor((inner + CHIP_GAP) / (CHIP + CHIP_GAP)))
end

function ColorPicker.new(props: Props): ColorPicker
	return ColorPicker._build(props, false)
end

function ColorPicker._build(props: Props, popup: boolean): ColorPicker
	local maid = Maid.new()
	local host = props.host
	local width = props.width or ColorPicker.WIDTH
	local inner = width - PAD * 2
	local palette = palettesEntries(props.palette)
	local showRecent = props.showRecent ~= false and host ~= nil
	local showPreview = props.showPreview ~= false

	local root = Instance.new("Frame")
	root.Name = props.name or (if popup then "AstraColorPicker" else "ColorPicker")
	root.BackgroundColor3 = if popup then c.bg2 else c.bg1
	root.BorderSizePixel = 0
	root.Active = true -- sinks clicks (popup: they must not reach the overlay underneath)
	Kit.applyCommon(root, props :: any)
	Kit.corner().Parent = root
	if popup then
		Kit.stroke(c.borderStrong).Parent = root
	end
	maid:give(root)

	local self = setmetatable({
		instance = root,
		svArea = nil :: any,
		svHit = nil :: any,
		svCursor = nil :: any,
		hueGradient = nil :: any,
		hueArea = nil :: any,
		hueHit = nil :: any,
		hueCursor = nil :: any,
		original = nil :: TextButton?,
		current = nil :: Frame?,
		hexInput = nil :: any,
		rgbInputs = {},
		paletteChips = {},
		recentChips = {},
		recentRow = nil :: Frame?,
		closeButton = nil :: any,
		_hueLayer = nil :: any,
		_recentMaid = Maid.new(),
		overlay = nil :: TextButton?,
		_maid = maid,
		_props = props,
		_host = host,
		_palette = palette,
		_value = "#FFFFFF",
		_color = Color3.new(1, 1, 1),
		_h = 0,
		_s = 0,
		_v = 1,
		_originalValue = "#FFFFFF",
		_dragging = nil :: string?,
		_pending = false,
		_enabled = props.enabled ~= false,
		_popup = popup,
		_open = popup,
		_destroyed = false,
	}, ColorPicker)

	local y = PAD

	-- popup header -----------------------------------------------------------------------------------------------
	if popup then
		local header = Instance.new("TextLabel")
		header.Name = "Header"
		header.BackgroundTransparency = 1
		header.Position = UDim2.fromOffset(PAD, y - 2)
		header.Size = UDim2.fromOffset(inner - 24, HEADER - 4)
		header.FontFace = Theme.fonts.medium
		header.TextSize = Theme.textSize.small
		header.TextColor3 = c.textDim
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = props.title or "Farbe"
		header.Parent = root
		local close = IconButton.new({
			name = "Close",
			glyph = "×",
			size = 20,
			tooltip = "Schließen",
			host = host,
			position = UDim2.fromOffset(width - PAD - 20, y - 4),
			onActivate = function()
				self:close()
			end,
		})
		close.instance.Parent = root
		maid:give(close)
		self.closeButton = close
		y += HEADER
	end

	-- saturation / value square ----------------------------------------------------------------------------------
	local svArea = Instance.new("Frame")
	svArea.Name = "SVSquare"
	svArea.BackgroundTransparency = 1
	svArea.BorderSizePixel = 0
	svArea.Position = UDim2.fromOffset(PAD, y)
	svArea.Size = UDim2.fromOffset(inner, SV_HEIGHT)
	svArea.ClipsDescendants = false
	svArea.Parent = root
	self.svArea = svArea

	-- UIGradient multiplies the background colour: white backgrounds show the gradients as they are (technical
	-- neutrals, not theme colours).
	local hueLayer = Instance.new("Frame")
	hueLayer.Name = "Hue"
	hueLayer.BackgroundColor3 = Color3.new(1, 1, 1)
	hueLayer.BorderSizePixel = 0
	hueLayer.Size = UDim2.fromScale(1, 1)
	hueLayer.Parent = svArea
	self._hueLayer = hueLayer
	Kit.corner(3).Parent = hueLayer
	local hueGradient = Instance.new("UIGradient")
	hueGradient.Name = "Gradient"
	hueGradient.Rotation = 0
	hueGradient.Parent = hueLayer
	self.hueGradient = hueGradient

	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.Parent = svArea
	Kit.corner(3).Parent = shade
	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Name = "Gradient"
	shadeGradient.Rotation = 90 -- top -> bottom
	shadeGradient.Transparency = NumberSequence.new(1, 0)
	shadeGradient.Parent = shade

	self.svCursor = Draw.dot(svArea, Vector2.zero, 6, c.text, {
		name = "Cursor",
		hollow = true,
		stroke = c.text,
		strokeThickness = 2,
	})
	local ring = Draw.dot(self.svCursor, Vector2.new(6, 6), 7, c.bg0, { name = "Ring", hollow = true, stroke = c.bg0 })
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, 4, 1, 4)

	local svHit = Instance.new("TextButton")
	svHit.Name = "Hit"
	svHit.Text = ""
	svHit.AutoButtonColor = false
	svHit.BackgroundTransparency = 1
	svHit.BorderSizePixel = 0
	svHit.Selectable = false
	svHit.Size = UDim2.fromScale(1, 1)
	svHit.Parent = svArea
	self.svHit = svHit
	y += SV_HEIGHT + GAP

	-- hue bar ---------------------------------------------------------------------------------------------------
	local hueArea = Instance.new("Frame")
	hueArea.Name = "HueBar"
	hueArea.BackgroundTransparency = 1
	hueArea.BorderSizePixel = 0
	hueArea.Position = UDim2.fromOffset(PAD, y)
	hueArea.Size = UDim2.fromOffset(inner, HUE_HEIGHT)
	hueArea.Parent = root
	self.hueArea = hueArea
	local spectrum = Instance.new("Frame")
	spectrum.Name = "Spectrum"
	spectrum.BackgroundColor3 = Color3.new(1, 1, 1)
	spectrum.BorderSizePixel = 0
	spectrum.Size = UDim2.fromScale(1, 1)
	spectrum.Parent = hueArea
	Kit.corner(3).Parent = spectrum
	local stops = {}
	for i = 0, 6 do
		local r, g, b = ColorPicker.hsvToRgb(i / 6, 1, 1)
		table.insert(stops, ColorSequenceKeypoint.new(i / 6, Color3.new(r, g, b)))
	end
	local spectrumGradient = Instance.new("UIGradient")
	spectrumGradient.Name = "Gradient"
	spectrumGradient.Color = ColorSequence.new(stops)
	spectrumGradient.Parent = spectrum

	self.hueCursor = Draw.rect(hueArea, Vector2.zero, Vector2.new(4, HUE_HEIGHT + 4), c.text, {
		name = "Cursor",
		stroke = c.bg0,
	})
	self.hueCursor.AnchorPoint = Vector2.new(0.5, 0.5)

	local hueHit = Instance.new("TextButton")
	hueHit.Name = "Hit"
	hueHit.Text = ""
	hueHit.AutoButtonColor = false
	hueHit.BackgroundTransparency = 1
	hueHit.BorderSizePixel = 0
	hueHit.Selectable = false
	hueHit.Position = UDim2.fromOffset(0, -3)
	hueHit.Size = UDim2.new(1, 0, 1, 6)
	hueHit.Parent = hueArea
	self.hueHit = hueHit
	y += HUE_HEIGHT + GAP + 2

	-- preview + hex ------------------------------------------------------------------------------------------------
	local hexX = PAD
	if showPreview then
		local preview = Instance.new("Frame")
		preview.Name = "Preview"
		preview.BackgroundTransparency = 1
		preview.BorderSizePixel = 0
		preview.Position = UDim2.fromOffset(PAD, y)
		preview.Size = UDim2.fromOffset(PREVIEW_WIDTH, Theme.metrics.rowHeight)
		preview.ClipsDescendants = true
		preview.Parent = root
		Kit.corner().Parent = preview
		Kit.stroke(c.border).Parent = preview
		local original = Instance.new("TextButton")
		original.Name = "Original"
		original.Text = ""
		original.AutoButtonColor = false
		original.BorderSizePixel = 0
		original.Selectable = false
		original.Size = UDim2.fromScale(0.5, 1)
		original.Parent = preview
		local current = Instance.new("Frame")
		current.Name = "Current"
		current.BorderSizePixel = 0
		current.Position = UDim2.fromScale(0.5, 0)
		current.Size = UDim2.fromScale(0.5, 1)
		current.Parent = preview
		self.original = original
		self.current = current
		maid:give(original.Activated:Connect(function()
			self:revert()
		end))
		if host then
			maid:give(Tooltip.attach(host, original, "Ursprüngliche Farbe wiederherstellen"))
		end
		hexX = PAD + PREVIEW_WIDTH + GAP
	end

	local hexInput = TextInput.new({
		name = "Hex",
		mono = true,
		placeholder = "#RRGGBB",
		host = host,
		tooltip = "Hex-Farbe (#RRGGBB)" .. (if #palette > 0 then " oder $Palette" else ""),
		position = UDim2.fromOffset(hexX, y),
		size = UDim2.fromOffset(width - PAD - hexX, Theme.metrics.rowHeight),
		validate = function(text: string): string?
			if ColorPicker.parseInput(text, self._props.palette) == nil then
				return "Ungültige Farbe – erwartet #RRGGBB"
			end
			return nil
		end,
		onChange = function(text: string)
			local parsed = ColorPicker.parseInput(text, self._props.palette)
			if parsed then
				self:_commit(parsed, nil, true)
			end
		end,
	})
	hexInput.instance.Parent = root
	maid:give(hexInput)
	self.hexInput = hexInput
	y += Theme.metrics.rowHeight + GAP

	-- R / G / B ----------------------------------------------------------------------------------------------------
	local fieldWidth = math.floor((inner - GAP * 2) / 3)
	local labels = { "R", "G", "B" }
	local labelColors = { c.error, c.success, c.loop }
	for i = 1, 3 do
		local axis = i
		local field = NumberInput.new({
			name = labels[i],
			label = labels[i],
			labelColor = labelColors[i],
			value = 255,
			min = 0,
			max = 255,
			step = 1,
			precision = 0,
			host = host,
			position = UDim2.fromOffset(PAD + (i - 1) * (fieldWidth + GAP), y),
			size = UDim2.fromOffset(fieldWidth, Theme.metrics.rowHeight),
			onChange = function(v: number, final: boolean)
				self:_setChannel(axis, v, final)
			end,
		})
		field.instance.Parent = root
		maid:give(field)
		self.rgbInputs[i] = field
	end
	y += Theme.metrics.rowHeight + GAP

	-- palette ------------------------------------------------------------------------------------------------------
	if #palette > 0 then
		caption(root, "Palette", y, inner)
		y += CAPTION
		local perRow = chipsPerRow(inner)
		local row = Instance.new("Frame")
		row.Name = "Palette"
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(PAD, y)
		local rows = math.ceil(#palette / perRow)
		row.Size = UDim2.fromOffset(inner, rows * (CHIP + CHIP_GAP) - CHIP_GAP)
		row.Parent = root
		for index, entry in palette do
			local col = (index - 1) % perRow
			local line = math.floor((index - 1) / perRow)
			local chip = chipButton(entry.color, col * (CHIP + CHIP_GAP), line * (CHIP + CHIP_GAP))
			chip:SetAttribute("AstraValue", entry.ref)
			chip.Parent = row
			local name = entry.name
			maid:give(chip.Activated:Connect(function()
				self:choosePalette(name)
			end))
			if host then
				maid:give(Tooltip.attach(host, chip, entry.ref))
			end
			self.paletteChips[entry.name] = chip
		end
		y += rows * (CHIP + CHIP_GAP) - CHIP_GAP + GAP
	end

	-- recent colours -------------------------------------------------------------------------------------------------
	if showRecent then
		caption(root, "Zuletzt verwendet", y, inner)
		y += CAPTION
		local row = Instance.new("Frame")
		row.Name = "Recent"
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(PAD, y)
		row.Size = UDim2.fromOffset(inner, CHIP)
		row.Parent = root
		self.recentRow = row
		y += CHIP + GAP
	end

	root.Size = props.size or UDim2.fromOffset(width, y - GAP + PAD)

	-- gestures -----------------------------------------------------------------------------------------------------
	if host and host.widget then
		maid:give(Input.drag(host.widget, svHit, {
			onPress = function(pos: Vector2, _mods: Input.Mods)
				if self._enabled then
					self._dragging = "sv"
					self:_setFromSquare(pos)
				end
			end,
			onMove = function(pos: Vector2, _delta: Vector2, _mods: Input.Mods)
				if self._dragging == "sv" then
					self:_setFromSquare(pos)
				end
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, _moved: boolean)
				if self._dragging == "sv" then
					self._dragging = nil
					self:_finish()
				end
			end,
		}, { threshold = 1 }))
		maid:give(Input.drag(host.widget, hueHit, {
			onPress = function(pos: Vector2, _mods: Input.Mods)
				if self._enabled then
					self._dragging = "hue"
					self:_setFromHue(pos)
				end
			end,
			onMove = function(pos: Vector2, _delta: Vector2, _mods: Input.Mods)
				if self._dragging == "hue" then
					self:_setFromHue(pos)
				end
			end,
			onEnd = function(_pos: Vector2, _cancelled: boolean, _moved: boolean)
				if self._dragging == "hue" then
					self._dragging = nil
					self:_finish()
				end
			end,
		}, { threshold = 1 }))
	end

	self:_layer()
	self:_load(props.value)
	self._originalValue = self._value
	self:_renderRecent()
	self:_refresh()
	if props.parent then
		root.Parent = props.parent
	end
	return self
end

-- Popup ------------------------------------------------------------------------------------------------------------

-- Opens a picker as a popup in host.root (closes the host's previous picker popup). Returns the picker.
function ColorPicker.open(host: Kit.Host, props: Props): ColorPicker
	local state = Kit.hostState(host, "colorPicker")
	local previous = state.open
	if previous and previous._open then
		previous:close()
	end
	local p: Props = table.clone(props)
	p.host = host
	local picker = ColorPicker._build(p, true)
	state.open = picker

	local overlay = Kit.overlay(host, "AstraColorPickerOverlay", Kit.Z.popup, function()
		picker:close()
	end)
	picker._maid:give(overlay)
	picker.overlay = overlay

	local anchor = props.anchor
	if anchor then
		picker._maid:give(anchor.Destroying:Connect(function()
			picker:close()
		end))
	end

	-- position: below the anchor (above when there is no room), clamped into the root
	local rootPos, rootSize = Kit.geometry(host.root)
	local size = Vector2.new(picker.instance.Size.X.Offset, picker.instance.Size.Y.Offset)
	local x, y
	if anchor then
		local aPos, aSize = Kit.geometry(anchor)
		x = aPos.X - rootPos.X
		local below = aPos.Y - rootPos.Y + aSize.Y + 2
		local above = aPos.Y - rootPos.Y - 2 - size.Y
		y = below
		if below + size.Y > rootSize.Y - 4 and above >= 4 then
			y = above
		end
	else
		local at = props.at or Kit.mouseInRoot(host)
		x, y = at.X, at.Y
	end
	x = math.max(4, math.min(x, rootSize.X - size.X - 4))
	y = math.max(4, math.min(y, rootSize.Y - size.Y - 4))
	picker.instance.Position = UDim2.fromOffset(x, y)
	Kit.raise(picker.instance, Kit.Z.popup + 1)
	picker:_layer()
	picker.instance.Parent = host.root
	return picker
end

function ColorPicker.isOpen(self: ColorPicker): boolean
	return self._popup and self._open
end

-- Closes a popup picker (an open gesture still ends with onChange(v, true)); inline pickers are destroyed.
function ColorPicker.close(self: ColorPicker)
	if self._destroyed then
		return
	end
	local wasOpen = self._open
	self._open = false
	self:destroy()
	if wasOpen and self._props.onClose then
		self._props.onClose()
	end
end

-- State ------------------------------------------------------------------------------------------------------------

-- Loads a value without callbacks (invalid values load as white).
function ColorPicker._load(self: ColorPicker, value: any)
	local canon = canonical(value) or "#FFFFFF"
	local color: Color3
	if string.sub(canon, 1, 1) == "$" then
		local entry = if self._props.palette then self._props.palette[string.sub(canon, 2)] else nil
		color = paletteColor(entry) or self._color
	else
		color = Codec.parseColor(canon) or Color3.new(1, 1, 1)
	end
	self._value = canon
	self:_adoptColor(color)
end

-- Takes over a colour as the new HSV state (keeps hue for greys/black and saturation for black).
function ColorPicker._adoptColor(self: ColorPicker, color: Color3)
	self._color = color
	local h, s, v = ColorPicker.rgbToHsv(color.R, color.G, color.B)
	if v > 0 then
		if s > 0 then
			self._h = h
		end
		self._s = s
	end
	self._v = v
end

-- Applies a new value: updates the display and reports it. `hsv` keeps the editing state (square/bar); without
-- it the HSV state is derived from the colour. Non-final changes are reported only when the value changes;
-- final = true is reported when it changes or when it closes earlier non-final reports.
function ColorPicker._commit(self: ColorPicker, value: string, hsv: { number }?, final: boolean)
	if self._destroyed then
		return -- child widgets ending their gestures while being cleaned up report nothing more
	end
	local changed = value ~= self._value
	if hsv then
		self._h, self._s, self._v = hsv[1], hsv[2], hsv[3]
		local r, g, b = ColorPicker.hsvToRgb(hsv[1], hsv[2], hsv[3])
		self._color = Color3.new(r, g, b)
		self._value = value
	elseif changed then
		self:_load(value)
	end
	self:_refresh()
	if final then
		if changed or self._pending then
			self._pending = false
			if self._host and string.sub(self._value, 1, 1) == "#" then
				ColorPicker.pushRecent(self._host, self._value)
				self:_renderRecent()
			end
			if self._props.onChange then
				self._props.onChange(self._value, true)
			end
		end
	elseif changed then
		self._pending = true
		if self._props.onChange then
			self._props.onChange(self._value, false)
		end
	end
end

-- Ends a press/drag gesture (reports final = true when it changed anything).
function ColorPicker._finish(self: ColorPicker)
	if self._pending then
		self:_commit(self._value, { self._h, self._s, self._v }, true)
	end
end

function ColorPicker._setFromSquare(self: ColorPicker, pos: Vector2)
	local p, size = Kit.geometry(self.svArea)
	local s = math.clamp((pos.X - p.X) / math.max(1, size.X), 0, 1)
	local v = 1 - math.clamp((pos.Y - p.Y) / math.max(1, size.Y), 0, 1)
	self:_commit(hsvHex(self._h, s, v), { self._h, s, v }, false)
end

function ColorPicker._setFromHue(self: ColorPicker, pos: Vector2)
	local p, size = Kit.geometry(self.hueArea)
	local h = math.clamp((pos.X - p.X) / math.max(1, size.X), 0, 1)
	self:_commit(hsvHex(h, self._s, self._v), { h, self._s, self._v }, false)
end

local function channels(color: Color3): { number }
	return {
		math.floor(math.clamp(color.R, 0, 1) * 255 + 0.5),
		math.floor(math.clamp(color.G, 0, 1) * 255 + 0.5),
		math.floor(math.clamp(color.B, 0, 1) * 255 + 0.5),
	}
end

function ColorPicker._setChannel(self: ColorPicker, axis: number, value: number, final: boolean)
	local rgb = channels(self._color)
	rgb[axis] = math.clamp(math.floor(value + 0.5), 0, 255)
	local color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	local hex = hexOf(color)
	local h, s, v = self._h, self._s, self._v
	local nh, ns, nv = ColorPicker.rgbToHsv(color.R, color.G, color.B)
	if nv > 0 then
		if ns > 0 then
			h = nh
		end
		s = ns
	end
	v = nv
	if final then
		self._pending = true -- a scrub (or typed value) always closes with final = true
	end
	self:_commit(hex, { h, s, v }, final)
end

-- Display ------------------------------------------------------------------------------------------------------------

function ColorPicker._refresh(self: ColorPicker)
	local enabled = self._enabled
	local hr, hg, hb = ColorPicker.hsvToRgb(self._h, 1, 1)
	self.hueGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(hr, hg, hb))
	self.svCursor.Position = UDim2.fromScale(self._s, 1 - self._v)
	self.hueCursor.Position = UDim2.new(self._h, 0, 0.5, 0)
	if self.current then
		self.current.BackgroundColor3 = self._color
	end
	if self.original then
		local orig = self._originalValue
		local color: Color3?
		if string.sub(orig, 1, 1) == "$" then
			color = paletteColor(if self._props.palette then self._props.palette[string.sub(orig, 2)] else nil)
		else
			color = Codec.parseColor(orig)
		end
		self.original.BackgroundColor3 = color or self._color
		self.original.Interactable = enabled
	end
	self.hexInput:setValue(self._value)
	self.hexInput:setEnabled(enabled)
	local rgb = channels(self._color)
	for i, field in self.rgbInputs do
		if not field:isDragging() then
			field:setValue(rgb[i])
		end
		field:setEnabled(enabled)
	end
	for name, chip in self.paletteChips do
		local selected = self._value == "$" .. name
		local stroke = chip:FindFirstChild("Outline") :: UIStroke?
		if stroke then
			stroke.Color = if selected then c.accent else c.borderStrong
			stroke.Thickness = if selected then 2 else 1
		end
		chip.Interactable = enabled
	end
	for _, chip in self.recentChips do
		chip.Interactable = enabled
	end
	self.svHit.Interactable = enabled
	self.hueHit.Interactable = enabled
	self._hueLayer.BackgroundTransparency = if enabled then 0 else 0.5
end

function ColorPicker._renderRecent(self: ColorPicker)
	local row = self.recentRow
	local host = self._host
	if row == nil or host == nil then
		return
	end
	self._recentMaid:clean()
	table.clear(self.recentChips)
	local empty = row:FindFirstChild("Empty")
	if empty then
		empty:Destroy()
	end
	local list = ColorPicker.recent(host)
	local perRow = chipsPerRow(row.Size.X.Offset)
	for index, value in list do
		if index > perRow then
			break
		end
		local color = Codec.parseColor(value) or Color3.new(1, 1, 1)
		local chip = chipButton(color, (index - 1) * (CHIP + CHIP_GAP), 0)
		chip:SetAttribute("AstraValue", value)
		chip.Interactable = self._enabled
		chip.Parent = row
		local i = index
		self._recentMaid:give(chip)
		self._recentMaid:give(chip.Activated:Connect(function()
			self:chooseRecent(i)
		end))
		self._recentMaid:give(Tooltip.attach(host, chip, value))
		table.insert(self.recentChips, chip)
	end
	if #list == 0 then
		local none = Instance.new("TextLabel")
		none.Name = "Empty"
		none.BackgroundTransparency = 1
		none.Size = UDim2.fromScale(1, 1)
		none.FontFace = Theme.fonts.regular
		none.TextSize = Theme.textSize.tiny
		none.TextColor3 = c.textMuted
		none.TextXAlignment = Enum.TextXAlignment.Left
		none.Text = "—"
		none.Parent = row
	end
	if self._popup and self.instance.Parent ~= nil then
		Kit.raise(self.instance, Kit.Z.popup + 1)
		self:_layer()
	end
end

-- Explicit stacking inside the square and the bar (gradient layers < cursor < hit area), relative to the
-- square's own ZIndex, so it survives ControlKit.raise (popups) which flattens siblings to one ZIndex.
function ColorPicker._layer(self: ColorPicker)
	local base = self.svArea.ZIndex
	self._hueLayer.ZIndex = base + 1
	local shade = self.svArea:FindFirstChild("Shade") :: GuiObject?
	if shade then
		shade.ZIndex = base + 2
	end
	self.svCursor.ZIndex = base + 3
	for _, ring in self.svCursor:GetChildren() do
		if ring:IsA("GuiObject") then
			ring.ZIndex = base + 3
		end
	end
	self.svHit.ZIndex = base + 4
	local hueBase = self.hueArea.ZIndex
	local spectrum = self.hueArea:FindFirstChild("Spectrum") :: GuiObject?
	if spectrum then
		spectrum.ZIndex = hueBase + 1
	end
	self.hueCursor.ZIndex = hueBase + 2
	self.hueHit.ZIndex = hueBase + 3
end

-- Public API ---------------------------------------------------------------------------------------------------------

-- Display only (no callbacks). A value equal to the current one is ignored, so the HSV state survives re-renders.
function ColorPicker.setValue(self: ColorPicker, value: any)
	local canon = canonical(value) or "#FFFFFF"
	if canon == self._value then
		return
	end
	self:_load(canon)
	self:_refresh()
end

-- Current JSON colour ("#RRGGBB" or "$key").
function ColorPicker.getValue(self: ColorPicker): string
	return self._value
end

-- Resolved colour (palette references resolved).
function ColorPicker.getColor(self: ColorPicker): Color3
	return self._color
end

function ColorPicker.getHex(self: ColorPicker): string
	return hexOf(self._color)
end

function ColorPicker.getHSV(self: ColorPicker): (number, number, number)
	return self._h, self._s, self._v
end

-- Like a user edit of the square/bar: sets h, s, v (0..1) and reports onChange(value, final ~= false).
function ColorPicker.setHSV(self: ColorPicker, h: number, s: number, v: number, final: boolean?)
	local hh, ss, vv = math.clamp(h, 0, 1), math.clamp(s, 0, 1), math.clamp(v, 0, 1)
	self:_commit(hsvHex(hh, ss, vv), { hh, ss, vv }, final ~= false)
end

-- Like typing into the hex field. Returns false (and changes nothing) for invalid text.
function ColorPicker.setHex(self: ColorPicker, text: string): boolean
	local parsed = ColorPicker.parseInput(text, self._props.palette)
	if parsed == nil then
		return false
	end
	self:_commit(parsed, nil, true)
	return true
end

-- Like editing the R/G/B fields (0..255 each).
function ColorPicker.setRGB(self: ColorPicker, r: number, g: number, b: number, final: boolean?)
	local function ch(x: number): number
		return math.clamp(math.floor(x + 0.5), 0, 255)
	end
	local color = Color3.fromRGB(ch(r), ch(g), ch(b))
	local h, s, v = self._h, self._s, self._v
	local nh, ns, nv = ColorPicker.rgbToHsv(color.R, color.G, color.B)
	if nv > 0 then
		if ns > 0 then
			h = nh
		end
		s = ns
	end
	v = nv
	self:_commit(hexOf(color), { h, s, v }, final ~= false)
end

-- Chooses a palette entry (like clicking its chip): the value becomes "$name". false for unknown names.
function ColorPicker.choosePalette(self: ColorPicker, name: string): boolean
	local chip: TextButton? = self.paletteChips[name]
	if not self._enabled or chip == nil then
		return false
	end
	self:_commit("$" .. name, nil, true)
	return true
end

-- Chooses the index-th recent colour (like clicking its chip).
function ColorPicker.chooseRecent(self: ColorPicker, index: number): boolean
	local host = self._host
	if not self._enabled or host == nil then
		return false
	end
	local value = ColorPicker.recent(host)[index]
	if value == nil then
		return false
	end
	self:_commit(value, nil, true)
	return true
end

-- Back to the value the picker was created/opened with.
function ColorPicker.revert(self: ColorPicker)
	if self._enabled then
		self:_commit(self._originalValue, nil, true)
	end
end

function ColorPicker.getRecent(self: ColorPicker): { string }
	return if self._host then table.clone(ColorPicker.recent(self._host)) else {}
end

function ColorPicker.isDragging(self: ColorPicker): boolean
	return self._dragging ~= nil
end

function ColorPicker.setEnabled(self: ColorPicker, enabled: boolean)
	self._enabled = enabled
	self:_refresh()
end

function ColorPicker.destroy(self: ColorPicker)
	if self._destroyed then
		return
	end
	-- an open gesture still ends with final = true (one undo step stays closed)
	self._dragging = nil
	self:_finish()
	self._destroyed = true
	self._open = false
	local host = self._host
	if host then
		local state = Kit.hostState(host, "colorPicker")
		if state.open == self then
			state.open = nil
		end
	end
	self._recentMaid:clean()
	self._maid:clean()
end

return ColorPicker
