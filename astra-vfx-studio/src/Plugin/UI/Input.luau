--!strict
--[[
	Input — mouse/keyboard helpers for DockWidgetPluginGuis.

	UserInputService does not work inside Studio widgets (docs/research/api-studio-plugin.md §2.8), so everything is
	built on GuiObject input events plus PluginGui:GetRelativeMousePosition():

	* Input.catcher(parent)        full-size transparent Active frame; after the user clicks it, keyboard input
	                               arrives through its InputBegan (Roblox's documented workaround).
	* Input.onKey(gui, fn)         keyboard handler with modifier state (InputObject:IsModifierKeyDown).
	* Input.drag(widget, gui, h)   press-move-release gestures. The mouse position is polled every Heartbeat from
	                               widget:GetRelativeMousePosition(), so drags keep working when the cursor leaves
	                               `gui`. A drag ends when the pressed InputObject reaches UserInputState.End, when
	                               `gui.InputEnded` fires for that button, or when the widget loses focus
	                               (onEnd(..., cancelled = true)).
	* Input.wheel(gui, fn)         mouse wheel via InputChanged (direction in input.Position.Z).
]]

local RunService = game:GetService("RunService")

local Input = {}

export type Mods = { ctrl: boolean, shift: boolean, alt: boolean }

export type DragHandlers = {
	onPress: ((pos: Vector2, mods: Mods) -> ())?, -- mouse down (before the threshold is reached)
	onStart: ((pos: Vector2, mods: Mods) -> ())?, -- first movement beyond the threshold
	onMove: ((pos: Vector2, delta: Vector2, mods: Mods) -> ())?, -- delta relative to the press position
	onEnd: ((pos: Vector2, cancelled: boolean, moved: boolean) -> ())?,
	onClick: ((pos: Vector2, mods: Mods) -> ())?, -- released without exceeding the threshold
}

export type DragOptions = {
	button: Enum.UserInputType?, -- default MouseButton1
	threshold: number?, -- pixels before onStart fires (default 3)
}

-- Anything with GetRelativeMousePosition (DockWidgetPluginGui) and optional WindowFocusReleased.
export type MouseSource = any

function Input.mods(input: InputObject): Mods
	return {
		ctrl = input:IsModifierKeyDown(Enum.ModifierKey.Ctrl) or input:IsModifierKeyDown(Enum.ModifierKey.Meta),
		shift = input:IsModifierKeyDown(Enum.ModifierKey.Shift),
		alt = input:IsModifierKeyDown(Enum.ModifierKey.Alt),
	}
end

local NO_MODS: Mods = { ctrl = false, shift = false, alt = false }

local function safeMods(input: InputObject?): Mods
	if input == nil then
		return NO_MODS
	end
	local ok, mods = pcall(Input.mods, input)
	return if ok then mods else NO_MODS
end

-- Full-size transparent frame that becomes the keyboard target after a click.
function Input.catcher(parent: GuiObject, zIndex: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "InputCatcher"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Active = true
	frame.ZIndex = zIndex or 0
	frame.Parent = parent
	return frame
end

-- Keyboard handler. `fn` receives (keyCode, mods, input).
function Input.onKey(
	gui: GuiObject,
	fn: (keyCode: Enum.KeyCode, mods: Mods, input: InputObject) -> ()
): RBXScriptConnection
	return gui.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			fn(input.KeyCode, safeMods(input), input)
		end
	end)
end

-- Current mouse position relative to the widget's top-left corner.
function Input.mousePosition(widget: MouseSource): Vector2
	local ok, pos = pcall(function()
		return widget:GetRelativeMousePosition()
	end)
	if ok and typeof(pos) == "Vector2" then
		return pos
	end
	return Vector2.zero
end

-- Converts a widget-space position into `gui`'s local space.
function Input.toLocal(gui: GuiObject, pos: Vector2): Vector2
	return pos - gui.AbsolutePosition
end

export type DragHandle = { Disconnect: (self: DragHandle) -> (), isDragging: (self: DragHandle) -> boolean }

function Input.drag(widget: MouseSource, gui: GuiObject, handlers: DragHandlers, options: DragOptions?): DragHandle
	local o: DragOptions = options or {}
	local button = o.button or Enum.UserInputType.MouseButton1
	local threshold = o.threshold or 3

	local active = false
	local moved = false
	local pressPos = Vector2.zero
	local lastPos = Vector2.zero
	local pressInput: InputObject? = nil
	local pressMods: Mods = NO_MODS
	local heartbeat: RBXScriptConnection? = nil
	local focusConn: RBXScriptConnection? = nil
	local connections: { RBXScriptConnection } = {}

	local function stop(cancelled: boolean)
		if not active then
			return
		end
		active = false
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
		if focusConn then
			focusConn:Disconnect()
			focusConn = nil
		end
		pressInput = nil
		if not moved and not cancelled and handlers.onClick then
			handlers.onClick(lastPos, pressMods)
		end
		if handlers.onEnd then
			handlers.onEnd(lastPos, cancelled, moved)
		end
	end

	local function poll()
		if not active then
			return
		end
		local input = pressInput
		if input and input.UserInputState == Enum.UserInputState.End then
			stop(false)
			return
		end
		local pos = Input.mousePosition(widget)
		if pos == lastPos then
			return
		end
		lastPos = pos
		if not moved and (pos - pressPos).Magnitude >= threshold then
			moved = true
			if handlers.onStart then
				handlers.onStart(pressPos, pressMods)
			end
		end
		if moved and handlers.onMove then
			handlers.onMove(pos, pos - pressPos, pressMods)
		end
	end

	table.insert(
		connections,
		gui.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= button or active then
				return
			end
			active = true
			moved = false
			pressInput = input
			pressMods = safeMods(input)
			pressPos = Input.mousePosition(widget)
			lastPos = pressPos
			if handlers.onPress then
				handlers.onPress(pressPos, pressMods)
			end
			heartbeat = RunService.Heartbeat:Connect(poll)
			local ok, signal = pcall(function()
				return widget.WindowFocusReleased
			end)
			if ok and signal then
				focusConn = signal:Connect(function()
					stop(true)
				end)
			end
		end)
	)
	table.insert(
		connections,
		gui.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == button and active then
				poll()
				stop(false)
			end
		end)
	)

	local handle = {} :: any
	function handle.Disconnect(_self: DragHandle)
		stop(true)
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end
	function handle.isDragging(_self: DragHandle): boolean
		return active and moved
	end
	return handle :: DragHandle
end

-- Mouse wheel. `fn(direction, input)` with direction +1 (forward/up) or -1.
function Input.wheel(gui: GuiObject, fn: (direction: number, input: InputObject) -> ()): RBXScriptConnection
	return gui.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local z = input.Position.Z
			if z ~= 0 then
				fn(if z > 0 then 1 else -1, input)
			end
		end
	end)
end

-- Right-click (MouseButton2) handler; `fn(input)`.
function Input.onRightClick(gui: GuiObject, fn: (input: InputObject) -> ()): RBXScriptConnection
	return gui.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			fn(input)
		end
	end)
end

return Input
