--!strict
--[[
	Toast — short, auto-dismissing notifications stacked bottom-right in host.root.

		Toast.show(host, "Effekt gespeichert", "success")
		local t = Toast.show(host, "Export fehlgeschlagen: …", "error", 8) -- duration in seconds
		t:dismiss()                                                          -- close early
		Toast.show(host, "Bleibt offen", "info", 0)                         -- duration <= 0: until dismissed

	Severities: "info" (accent), "success", "warning", "error" (Theme colours on a left bar). Defaults: 3 s for
	info/success, 5 s for warning, 7 s for error. At most Toast.MAX_VISIBLE toasts are shown; older ones are
	dismissed first. Each toast has a close button.
]]

local Theme = require(script.Parent.Parent.Theme)
local Kit = require(script.Parent.ControlKit)

type Host = Kit.Host

export type Severity = "info" | "success" | "warning" | "error"

export type ToastHandle = {
	instance: Frame,
	message: string,
	severity: Severity,
	dismiss: (self: ToastHandle) -> (),
	isOpen: (self: ToastHandle) -> boolean,
}

local Toast = {}

Toast.MAX_VISIBLE = 4
Toast.WIDTH = 300
Toast.DURATIONS = { info = 3, success = 3, warning = 5, error = 7 } :: { [string]: number }

local c = Theme.colors

local function severityColor(severity: Severity): Color3
	if severity == "success" then
		return c.success
	elseif severity == "warning" then
		return c.warning
	elseif severity == "error" then
		return c.error
	end
	return c.accent
end

local function container(host: Host): Frame
	local state = Kit.hostState(host, "toast")
	local existing: Frame? = state.container
	if existing and existing.Parent == host.root then
		return existing
	end
	local frame = Instance.new("Frame")
	frame.Name = "AstraToasts"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -12, 1, -12)
	frame.Size = UDim2.new(0, Toast.WIDTH, 1, -24)
	frame.ZIndex = Kit.Z.toast
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame
	frame.Parent = host.root
	state.container = frame
	state.handles = {}
	state.counter = 0
	return frame
end

-- Active toasts of `host`, oldest first.
function Toast.list(host: Host): { ToastHandle }
	local state = Kit.hostState(host, "toast")
	local out: { ToastHandle } = {}
	for _, handle in state.handles or {} do
		table.insert(out, handle)
	end
	return out
end

function Toast.clear(host: Host)
	for _, handle in Toast.list(host) do
		handle:dismiss()
	end
end

function Toast.show(host: Host, message: string, severity: Severity?, duration: number?): ToastHandle
	local sev: Severity = severity or "info"
	local parent = container(host)
	local state = Kit.hostState(host, "toast")
	state.counter += 1

	local frame = Instance.new("Frame")
	frame.Name = "Toast"
	frame.LayoutOrder = state.counter
	frame.BackgroundColor3 = c.bg2
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Active = true
	Kit.corner().Parent = frame
	Kit.stroke(c.borderStrong).Parent = frame

	local bar = Instance.new("Frame")
	bar.Name = "Severity"
	bar.BackgroundColor3 = severityColor(sev)
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0, 3, 1, 0)
	Kit.corner(2).Parent = bar
	bar.Parent = frame

	local text = Instance.new("TextLabel")
	text.Name = "Message"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(14, 0)
	text.Size = UDim2.new(1, -40, 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.FontFace = Theme.fonts.regular
	text.TextSize = Theme.textSize.normal
	text.TextColor3 = c.text
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = message
	Kit.padding(0, 0, 8, 8).Parent = text
	text.Parent = frame

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.BackgroundColor3 = c.bg3
	close.BackgroundTransparency = 1
	close.BorderSizePixel = 0
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -4, 0, 4)
	close.Size = UDim2.fromOffset(20, 20)
	close.FontFace = Theme.fonts.medium
	close.TextSize = Theme.textSize.title
	close.TextColor3 = c.textMuted
	close.Text = "×"
	close.Selectable = false
	Kit.corner(3).Parent = close
	close.Parent = frame

	local open = true
	local thread: thread? = nil
	local handle = { instance = frame, message = message, severity = sev } :: any

	function handle.dismiss(_self: ToastHandle)
		if not open then
			return
		end
		open = false
		Kit.cancel(thread)
		thread = nil
		local handles = state.handles
		if handles then
			local i = table.find(handles, handle)
			if i then
				table.remove(handles, i)
			end
		end
		frame:Destroy()
	end
	function handle.isOpen(_self: ToastHandle): boolean
		return open
	end

	close.Activated:Connect(function()
		handle:dismiss()
	end)
	close.MouseEnter:Connect(function()
		close.BackgroundTransparency = 0
		close.TextColor3 = c.text
	end)
	close.MouseLeave:Connect(function()
		close.BackgroundTransparency = 1
		close.TextColor3 = c.textMuted
	end)

	Kit.raise(frame, Kit.Z.toast + 1)
	frame.Parent = parent
	table.insert(state.handles, handle)
	while #state.handles > Toast.MAX_VISIBLE do
		state.handles[1]:dismiss()
	end

	local seconds = if duration ~= nil then duration else (Toast.DURATIONS[sev] or 3)
	if seconds > 0 then
		thread = task.delay(seconds, function()
			thread = nil
			handle:dismiss()
		end)
	end
	return handle :: ToastHandle
end

return Toast
