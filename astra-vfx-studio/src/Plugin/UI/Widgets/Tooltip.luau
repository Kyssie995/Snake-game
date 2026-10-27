--!strict
--[[
	Tooltip — small text panel near the mouse after hovering a GuiObject for Tooltip.DELAY (0.5 s).

		local handle = Tooltip.attach(host, button, "Effekt abspielen")
		local dynamic = Tooltip.attach(host, field, function() return "Wert: " .. tostring(value) end)
		maid:give(handle)            -- handle:Disconnect() (or handle:destroy()) detaches it
		handle:setText("Neuer Text")

	Built on MouseEnter/MouseLeave and a cancellable task.delay (UserInputService does not work in widgets).
	Only one tooltip is visible per host; it is parented to host.root, positioned at the mouse
	(widget:GetRelativeMousePosition) and clamped into the root. Pressing a mouse button over the target hides it.
	A text function returning nil or "" shows nothing.
]]

local Theme = require(script.Parent.Parent.Theme)
local Kit = require(script.Parent.ControlKit)

type Host = Kit.Host

export type TextSource = string | () -> string?

export type Options = {
	delay: number?, -- seconds before showing (default Tooltip.DELAY)
}

export type TooltipHandle = {
	Disconnect: (self: TooltipHandle) -> (),
	destroy: (self: TooltipHandle) -> (),
	setText: (self: TooltipHandle, text: TextSource) -> (),
}

local Tooltip = {}

Tooltip.DELAY = 0.5
Tooltip.MAX_WIDTH = 280
Tooltip.OFFSET = Vector2.new(12, 18)

local function resolve(source: TextSource): string?
	if type(source) == "function" then
		local ok, text = pcall(source :: any)
		if ok and type(text) == "string" and text ~= "" then
			return text
		end
		return nil
	end
	if type(source) == "string" and source ~= "" then
		return source
	end
	return nil
end

-- Hides the tooltip of `host` (if any).
function Tooltip.hide(host: Host)
	local state = Kit.hostState(host, "tooltip")
	Kit.cancel(state.thread)
	state.thread = nil
	local frame = state.frame
	state.frame = nil
	state.owner = nil
	if frame then
		frame:Destroy()
	end
end

-- The visible tooltip frame of `host`, or nil.
function Tooltip.current(host: Host): Frame?
	local state = Kit.hostState(host, "tooltip")
	local frame = state.frame
	if frame and frame.Parent ~= nil then
		return frame
	end
	return nil
end

-- Shows `text` immediately at the mouse position (replacing any tooltip of this host). `owner` is optional.
function Tooltip.show(host: Host, text: string, owner: GuiObject?): Frame?
	Tooltip.hide(host)
	if (host.root :: any) == nil or text == "" then
		return nil
	end
	local state = Kit.hostState(host, "tooltip")
	local textSize = Theme.textSize.small
	local padX, padY = 8, 5
	local bounds = Kit.measure(text, textSize, Tooltip.MAX_WIDTH)
	local size = Vector2.new(bounds.X + padX * 2, bounds.Y + padY * 2)

	local _, rootSize = Kit.geometry(host.root)
	local mouse = Kit.mouseInRoot(host)
	local x = mouse.X + Tooltip.OFFSET.X
	local y = mouse.Y + Tooltip.OFFSET.Y
	if x + size.X > rootSize.X - 4 then
		x = rootSize.X - size.X - 4
	end
	if y + size.Y > rootSize.Y - 4 then
		y = mouse.Y - size.Y - 6
	end
	x = math.max(4, x)
	y = math.max(4, y)

	local frame = Instance.new("Frame")
	frame.Name = "AstraTooltip"
	frame.BackgroundColor3 = Theme.colors.bg0
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.Position = UDim2.fromOffset(x, y)
	frame.Active = false
	frame.Interactable = false
	Kit.corner().Parent = frame
	Kit.stroke(Theme.colors.borderStrong).Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(padX, padY)
	label.Size = UDim2.new(1, -padX * 2, 1, -padY * 2)
	label.FontFace = Theme.fonts.regular
	label.TextSize = textSize
	label.TextColor3 = Theme.colors.text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = text
	label.Parent = frame

	Kit.raise(frame, Kit.Z.tooltip)
	frame.Parent = host.root
	state.frame = frame
	state.owner = owner
	return frame
end

function Tooltip.attach(host: Host, gui: GuiObject, text: TextSource, options: Options?): TooltipHandle
	local o: Options = options or {}
	local source: TextSource = text
	local hovered = false
	local pending: thread? = nil
	local connections: { any } = {}

	local function cancelPending()
		Kit.cancel(pending)
		pending = nil
	end

	local function hideOwn()
		local state = Kit.hostState(host, "tooltip")
		if state.owner == gui then
			Tooltip.hide(host)
		end
	end

	local function schedule()
		cancelPending()
		local delay = o.delay or Tooltip.DELAY
		pending = task.delay(delay, function()
			pending = nil
			if not hovered or gui.Parent == nil then
				return
			end
			local resolved = resolve(source)
			if resolved then
				Tooltip.show(host, resolved, gui)
			end
		end)
	end

	table.insert(
		connections,
		gui.MouseEnter:Connect(function()
			hovered = true
			schedule()
		end)
	)
	table.insert(
		connections,
		gui.MouseLeave:Connect(function()
			hovered = false
			cancelPending()
			hideOwn()
		end)
	)
	table.insert(
		connections,
		gui.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 then
				cancelPending()
				hideOwn()
			end
		end)
	)

	local handle = {} :: any
	function handle.Disconnect(_self: TooltipHandle)
		hovered = false
		cancelPending()
		hideOwn()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end
	handle.destroy = handle.Disconnect
	function handle.setText(_self: TooltipHandle, newText: TextSource)
		source = newText
		local state = Kit.hostState(host, "tooltip")
		if state.owner == gui and state.frame then
			local resolved = resolve(source)
			if resolved then
				Tooltip.show(host, resolved, gui)
			else
				Tooltip.hide(host)
			end
		end
	end
	return handle :: TooltipHandle
end

return Tooltip
