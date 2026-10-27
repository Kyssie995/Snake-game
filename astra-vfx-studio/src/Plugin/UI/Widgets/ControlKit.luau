--!strict
--[[
	ControlKit — shared helpers for the basic widgets (Button, TextInput, NumberInput, Slider, Dropdown, ...).

		local Kit = require(script.Parent.ControlKit)
		local box = New("Frame", { BackgroundColor3 = Theme.colors.bg2 }, { Kit.corner(), Kit.stroke() })
		local pos, size = Kit.geometry(box)         -- safe AbsolutePosition/AbsoluteSize (see below)
		Kit.format(1.2500, 3)                       -- "1.25"
		Kit.evaluate("2 * (3 + 0,5)")               -- 7  (comma accepted as decimal separator)

	Host = { plugin, widget, root }: `widget` provides GetRelativeMousePosition / WindowFocusReleased, `root` is the
	panel's root Frame and serves as the layer for popups, tooltips, toasts and dialogs.

	Lune has no layout engine: reading AbsolutePosition/AbsoluteSize fails there. `Kit.geometry` falls back to
	position (0, 0) and the Size offsets (or 100 px when an axis has no positive offset), which keeps mouse-to-value
	mapping deterministic in tests.
]]

local TextService = game:GetService("TextService")

local Theme = require(script.Parent.Parent.Theme)
local Input = require(script.Parent.Parent.Input)

local ControlKit = {}

export type Host = { plugin: any, widget: any, root: GuiObject }

-- Z layers inside host.root (only relative order matters).
ControlKit.Z = {
	dialog = 800,
	toast = 1100,
	popup = 1200,
	tooltip = 1300,
}

-- Enum fonts matching Theme.fonts (TextService:GetTextSize takes Enum.Font).
ControlKit.FONT_ENUM = {
	regular = Enum.Font.BuilderSans,
	medium = Enum.Font.BuilderSansMedium,
	bold = Enum.Font.BuilderSansBold,
	mono = Enum.Font.RobotoMono,
}

ControlKit.FALLBACK_SIZE = 100

function ControlKit.corner(radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.metrics.corner)
	return c
end

function ControlKit.stroke(color: Color3?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or Theme.colors.border
	s.Thickness = 1
	s.Transparency = transparency or 0
	return s
end

function ControlKit.padding(left: number, right: number?, top: number?, bottom: number?): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, left)
	p.PaddingRight = UDim.new(0, right or left)
	p.PaddingTop = UDim.new(0, top or 0)
	p.PaddingBottom = UDim.new(0, bottom or top or 0)
	return p
end

-- Applies the common optional props (name, layoutOrder, position, anchorPoint, zIndex) to a widget root.
function ControlKit.applyCommon(inst: GuiObject, props: { [string]: any })
	if props.name ~= nil then
		inst.Name = props.name
	end
	if props.layoutOrder ~= nil then
		inst.LayoutOrder = props.layoutOrder
	end
	if props.position ~= nil then
		inst.Position = props.position
	end
	if props.anchorPoint ~= nil then
		inst.AnchorPoint = props.anchorPoint
	end
	if props.zIndex ~= nil then
		inst.ZIndex = props.zIndex
	end
end

local function fallbackAxis(offset: number): number
	return if offset > 0 then offset else ControlKit.FALLBACK_SIZE
end

-- AbsolutePosition and AbsoluteSize, with a deterministic fallback where no layout engine exists (Lune).
function ControlKit.geometry(gui: GuiObject): (Vector2, Vector2)
	local ok, pos, size = pcall(function()
		return gui.AbsolutePosition, gui.AbsoluteSize
	end)
	if ok and typeof(pos) == "Vector2" and typeof(size) == "Vector2" then
		return pos, size
	end
	local s = gui.Size
	return Vector2.zero, Vector2.new(fallbackAxis(s.X.Offset), fallbackAxis(s.Y.Offset))
end

-- Mouse position relative to host.root's top-left corner.
function ControlKit.mouseInRoot(host: Host): Vector2
	local mouse = Input.mousePosition(host.widget)
	local rootPos = ControlKit.geometry(host.root)
	return mouse - rootPos
end

-- Sets ZIndex on `root` and every GuiObject below it (z + depth), so popups stay on top in both
-- ZIndexBehavior.Sibling and ZIndexBehavior.Global.
function ControlKit.raise(root: Instance, z: number)
	local function visit(inst: Instance, depth: number)
		if inst:IsA("GuiObject") then
			(inst :: GuiObject).ZIndex = z + depth
		end
		for _, child in inst:GetChildren() do
			visit(child, depth + 1)
		end
	end
	visit(root, 0)
end

-- Text bounds for layout decisions (popups/tooltips are sized explicitly so they can be clamped into the root).
function ControlKit.measure(text: string, textSize: number, maxWidth: number?, font: Enum.Font?): Vector2
	local ok, size = pcall(function()
		return TextService:GetTextSize(
			text,
			textSize,
			font or ControlKit.FONT_ENUM.regular,
			Vector2.new(maxWidth or 10000, 10000)
		)
	end)
	if ok and typeof(size) == "Vector2" then
		local width = if maxWidth then math.min(size.X, maxWidth) else size.X
		return Vector2.new(math.ceil(width), math.ceil(size.Y))
	end
	return Vector2.new(#text * textSize * 0.55, textSize)
end

-- Plugin mouse cursor (best effort; "SizeEW", "PointingHand", ... from rbxasset://SystemCursors). nil resets.
function ControlKit.setCursor(host: Host?, cursor: string?)
	if host == nil or host.plugin == nil then
		return
	end
	pcall(function()
		local mouse = host.plugin:GetMouse()
		mouse.Icon = if cursor then "rbxasset://SystemCursors/" .. cursor else ""
	end)
end

-- Cancels a task.delay thread; safe for nil, finished or currently running threads.
function ControlKit.cancel(thread: thread?)
	if thread ~= nil and coroutine.running() ~= thread then
		pcall(task.cancel, thread)
	end
end

-- Per-host state (weak keys on host.root so closed panels do not leak).
local hostStates: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

function ControlKit.hostState(host: Host, key: string): { [string]: any }
	local root = host.root
	local states = hostStates[root]
	if states == nil then
		states = {}
		hostStates[root] = states
	end
	local state = states[key]
	if state == nil then
		state = {}
		states[key] = state
	end
	return state
end

-- Hover / press tracking for custom visual states. `onState(hovered, pressed)` runs on every change.
-- Returns the connections (give them to a Maid).
function ControlKit.bindStates(gui: GuiObject, onState: (hovered: boolean, pressed: boolean) -> ()): { any }
	local hovered, pressed = false, false
	local connections: { any } = {}
	table.insert(
		connections,
		gui.MouseEnter:Connect(function()
			hovered = true
			onState(hovered, pressed)
		end)
	)
	table.insert(
		connections,
		gui.MouseLeave:Connect(function()
			hovered = false
			pressed = false
			onState(hovered, pressed)
		end)
	)
	table.insert(
		connections,
		gui.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				pressed = true
				onState(hovered, pressed)
			end
		end)
	)
	table.insert(
		connections,
		gui.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				pressed = false
				onState(hovered, pressed)
			end
		end)
	)
	return connections
end

-- Full-size transparent click catcher in host.root (used to close popups on outside clicks).
function ControlKit.overlay(host: Host, name: string, z: number, onOutside: () -> ()): TextButton
	local overlay = Instance.new("TextButton")
	overlay.Name = name
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Active = true
	overlay.Selectable = false
	overlay.ZIndex = z
	overlay.Activated:Connect(onOutside)
	overlay.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			onOutside()
		end
	end)
	overlay.Parent = host.root
	return overlay
end

-- Numbers -------------------------------------------------------------------------------------------------------

function ControlKit.round(value: number, decimals: number): number
	local m = 10 ^ decimals
	return math.round(value * m) / m
end

-- Number of decimals needed to represent `x` exactly (0..6).
function ControlKit.decimals(x: number): number
	for i = 0, 6 do
		local m = 10 ^ i
		if math.abs(x * m - math.round(x * m)) < 1e-7 then
			return i
		end
	end
	return 6
end

function ControlKit.clamp(value: number, min: number?, max: number?): number
	if min ~= nil and value < min then
		value = min
	end
	if max ~= nil and value > max then
		value = max
	end
	return value
end

-- Formats with at most `precision` decimals; trailing zeros are dropped ("1.50" -> "1.5", "2.00" -> "2").
function ControlKit.format(value: number, precision: number): string
	if value ~= value then
		return "NaN"
	elseif value == math.huge then
		return "inf"
	elseif value == -math.huge then
		return "-inf"
	end
	local p = math.max(0, math.floor(precision))
	local s = string.format("%." .. tostring(p) .. "f", value)
	if p > 0 then
		s = (string.gsub(s, "0+$", ""))
		s = (string.gsub(s, "%.$", ""))
	end
	if s == "-0" then
		s = "0"
	end
	return s
end

--[[
	Evaluates a small arithmetic expression typed into a number field: numbers (1, .5, 2e3, "0,5"), unary +/-,
	+ - * / % ^ and parentheses. Returns nil for anything else (no `load`, no globals).
]]
function ControlKit.evaluate(text: string): number?
	local s = string.gsub(string.gsub(text, ",", "."), "%s+", "")
	if s == "" then
		return nil
	end
	local pos = 1
	local function peek(): string
		return string.sub(s, pos, pos)
	end

	local parseExpr: () -> number?
	local parseUnary: () -> number?

	local function parseNumber(): number?
		local token = string.match(s, "^%d+%.?%d*[eE][%+%-]?%d+", pos)
			or string.match(s, "^%.%d+[eE][%+%-]?%d+", pos)
			or string.match(s, "^%d+%.?%d*", pos)
			or string.match(s, "^%.%d+", pos)
		if token == nil then
			return nil
		end
		pos += #token
		return tonumber(token)
	end

	local function parseAtom(): number?
		if peek() == "(" then
			pos += 1
			local v = parseExpr()
			if v == nil or peek() ~= ")" then
				return nil
			end
			pos += 1
			return v
		end
		return parseNumber()
	end

	local function parsePower(): number?
		local base = parseAtom()
		if base == nil then
			return nil
		end
		if peek() == "^" then
			pos += 1
			local exponent = parseUnary()
			if exponent == nil then
				return nil
			end
			return base ^ exponent
		end
		return base
	end

	parseUnary = function(): number?
		local c = peek()
		if c == "-" or c == "+" then
			pos += 1
			local v = parseUnary()
			if v == nil then
				return nil
			end
			return if c == "-" then -v else v
		end
		return parsePower()
	end

	local function parseTerm(): number?
		local v = parseUnary()
		while v ~= nil do
			local op = peek()
			if op ~= "*" and op ~= "/" and op ~= "%" then
				break
			end
			pos += 1
			local rhs = parseUnary()
			if rhs == nil then
				return nil
			end
			if op == "*" then
				v *= rhs
			elseif op == "/" then
				v /= rhs
			else
				v %= rhs
			end
		end
		return v
	end

	parseExpr = function(): number?
		local v = parseTerm()
		while v ~= nil do
			local op = peek()
			if op ~= "+" and op ~= "-" then
				break
			end
			pos += 1
			local rhs = parseTerm()
			if rhs == nil then
				return nil
			end
			v = if op == "+" then v + rhs else v - rhs
		end
		return v
	end

	local result = parseExpr()
	if result == nil or pos <= #s then
		return nil
	end
	if result ~= result or result == math.huge or result == -math.huge then
		return nil
	end
	return result
end

return ControlKit
