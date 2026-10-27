--[[
	Fakes (Lune only)

	Lune's Instances carry properties but no engine behaviour: no events, no ParticleEmitter:Emit(), no RunService
	loop. This module implements the small set of engine members ASTRA uses, so runtime code can be exercised
	unchanged. Everything a fake does is recorded so specs can assert on it (e.g. how many particles were emitted).

	These fakes are deliberately minimal. They prove call sequencing and data flow, NOT visual results.
]]

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Fakes = {}

export type FakeConnection = { Connected: boolean, Disconnect: (self: FakeConnection) -> () }
export type FakeSignal = {
	Connect: (self: FakeSignal, fn: (...any) -> ()) -> FakeConnection,
	Once: (self: FakeSignal, fn: (...any) -> ()) -> FakeConnection,
	Fire: (self: FakeSignal, ...any) -> (),
	connectionCount: (self: FakeSignal) -> number,
	_handlers: { [FakeConnection]: (...any) -> () },
}

local function newSignal(name: string): FakeSignal
	local signal = { _handlers = {}, _name = name } :: any
	function signal.Connect(self: FakeSignal, fn: (...any) -> ()): FakeConnection
		local connection = { Connected = true } :: any
		function connection.Disconnect(c: FakeConnection)
			c.Connected = false
			self._handlers[c] = nil
		end
		self._handlers[connection] = fn
		return connection
	end
	function signal.Once(self: FakeSignal, fn: (...any) -> ()): FakeConnection
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function signal.Fire(self: FakeSignal, ...: any)
		local snapshot = {}
		for c, fn in pairs(self._handlers) do
			table.insert(snapshot, { c, fn })
		end
		for _, pair in snapshot do
			if pair[1].Connected then
				pair[2](...)
			end
		end
	end
	function signal.connectionCount(self: FakeSignal): number
		local n = 0
		for _ in pairs(self._handlers) do
			n += 1
		end
		return n
	end
	function signal.Wait()
		error("FakeSignal:Wait() is not supported in tests (" .. name .. ")")
	end
	return signal
end
Fakes.newSignal = newSignal

-- Per-instance signal storage (weak keys so destroyed instances do not leak across tests)
local instanceSignals: { [any]: { [string]: FakeSignal } } = setmetatable({}, { __mode = "k" }) :: any

local function instanceSignal(inst: any, name: string): FakeSignal
	local map = instanceSignals[inst]
	if not map then
		map = {}
		instanceSignals[inst] = map
	end
	local s = map[name]
	if not s then
		s = newSignal(name)
		map[name] = s
	end
	return s
end

export type Fakes = {
	heartbeat: FakeSignal,
	preRender: FakeSignal,
	renderStepped: FakeSignal,
	stepped: FakeSignal,
	flags: { IsStudio: boolean, IsRunning: boolean, IsClient: boolean, IsServer: boolean, IsEdit: boolean },
	emits: { { instance: any, count: number } },
	clears: { any },
	sounds: { { instance: any, action: string } },
	reset: (self: Fakes) -> (),
	step: (self: Fakes, dt: number) -> (),
	totalEmitted: (self: Fakes, instance: any?) -> number,
	signalFor: (self: Fakes, instance: any, eventName: string) -> FakeSignal,
}

local installed: Fakes? = nil

function Fakes.install(): Fakes
	if installed then
		return installed
	end
	local fakes = {
		heartbeat = newSignal("Heartbeat"),
		preRender = newSignal("PreRender"),
		renderStepped = newSignal("RenderStepped"),
		stepped = newSignal("Stepped"),
		flags = { IsStudio = true, IsRunning = false, IsClient = true, IsServer = false, IsEdit = true },
		emits = {},
		clears = {},
		sounds = {},
	} :: any

	function fakes.reset(self: Fakes)
		table.clear(self.emits)
		table.clear(self.clears)
		table.clear(self.sounds)
		self.heartbeat._handlers = {}
		self.preRender._handlers = {}
		self.renderStepped._handlers = {}
		self.stepped._handlers = {}
		self.flags.IsStudio = true
		self.flags.IsRunning = false
		self.flags.IsClient = true
		self.flags.IsServer = false
		self.flags.IsEdit = true
	end

	-- Fires one frame of the main RunService events (PreRender/RenderStepped receive dt, Heartbeat receives dt).
	function fakes.step(self: Fakes, dt: number)
		self.preRender:Fire(dt)
		self.renderStepped:Fire(dt)
		self.stepped:Fire(0, dt)
		self.heartbeat:Fire(dt)
	end

	function fakes.totalEmitted(self: Fakes, instance: any?): number
		local n = 0
		for _, e in self.emits do
			if instance == nil or e.instance == instance then
				n += e.count
			end
		end
		return n
	end

	function fakes.signalFor(_self: Fakes, instance: any, eventName: string): FakeSignal
		return instanceSignal(instance, eventName)
	end

	-- RunService
	roblox.implementProperty("RunService", "Heartbeat", function()
		return fakes.heartbeat
	end)
	roblox.implementProperty("RunService", "PreRender", function()
		return fakes.preRender
	end)
	roblox.implementProperty("RunService", "RenderStepped", function()
		return fakes.renderStepped
	end)
	roblox.implementProperty("RunService", "Stepped", function()
		return fakes.stepped
	end)
	for _, flag in { "IsStudio", "IsRunning", "IsClient", "IsServer", "IsEdit" } do
		roblox.implementMethod("RunService", flag, function()
			return fakes.flags[flag]
		end)
	end
	roblox.implementMethod("RunService", "IsRunMode", function()
		return fakes.flags.IsRunning
	end)

	-- Effects
	roblox.implementMethod("ParticleEmitter", "Emit", function(self, count: number?)
		table.insert(fakes.emits, { instance = self, count = count or 16 })
	end)
	roblox.implementMethod("ParticleEmitter", "Clear", function(self)
		table.insert(fakes.clears, self)
	end)
	roblox.implementMethod("Trail", "Clear", function(self)
		table.insert(fakes.clears, self)
	end)
	for _, action in { "Play", "Stop", "Pause", "Resume" } do
		roblox.implementMethod("Sound", action, function(self)
			table.insert(fakes.sounds, { instance = self, action = action })
		end)
	end

	-- WorldRoot:BulkMoveTo — applies the CFrames like the engine would.
	local function bulkMove(_self, parts: { any }, cframes: { any }, _mode: any?)
		assert(#parts == #cframes, "BulkMoveTo: parts and cframes must have the same length")
		for i, part in parts do
			part.CFrame = cframes[i]
		end
	end
	roblox.implementMethod("Workspace", "BulkMoveTo", bulkMove)
	roblox.implementMethod("WorldModel", "BulkMoveTo", bulkMove)

	-- Model pivots (simple: pivot = PrimaryPart CFrame or first BasePart)
	roblox.implementMethod("Model", "GetPivot", function(self)
		local primary = self.PrimaryPart or self:FindFirstChildWhichIsA("BasePart", true)
		return if primary then primary.CFrame else roblox.CFrame.new()
	end)
	roblox.implementMethod("BasePart", "GetPivot", function(self)
		return self.CFrame
	end)

	-- HttpService JSON helpers
	roblox.implementMethod("HttpService", "JSONEncode", function(_self, value: any)
		return serde.encode("json", value)
	end)
	roblox.implementMethod("HttpService", "JSONDecode", function(_self, text: string)
		return serde.decode("json", text)
	end)
	local guidCounter = 0
	roblox.implementMethod("HttpService", "GenerateGUID", function(_self, wrap: boolean?)
		guidCounter += 1
		local s = string.format("00000000-0000-4000-8000-%012d", guidCounter)
		return if wrap == false then s else "{" .. s .. "}"
	end)

	-- TextService (approximation, only used by UI smoke tests)
	roblox.implementMethod(
		"TextService",
		"GetTextSize",
		function(_self, text: string, size: number, _font: any, _frame: any)
			return roblox.Vector2.new(#text * size * 0.5, size)
		end
	)

	-- Generic instance events used by editor code. They exist as signals but never fire on their own.
	for _, eventName in
		{
			"Changed",
			"AncestryChanged",
			"Destroying",
			"ChildAdded",
			"ChildRemoved",
			"DescendantAdded",
			"DescendantRemoving",
			"AttributeChanged",
		}
	do
		roblox.implementProperty("Instance", eventName, function(self)
			return instanceSignal(self, eventName)
		end)
	end
	-- GUI events (fire only when a test fires them via fakes:signalFor(inst, name):Fire(...))
	local guiEvents = {
		GuiObject = { "InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave", "MouseMoved", "MouseWheelForward", "MouseWheelBackward", "SelectionGained", "SelectionLost" },
		GuiButton = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseButton2Down", "MouseButton2Up" },
		TextBox = { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" },
		Path2D = { "ControlPointChanged" },
	}
	for className, events in guiEvents do
		for _, eventName in events do
			roblox.implementProperty(className, eventName, function(self)
				return instanceSignal(self, eventName)
			end)
		end
	end
	local focused: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	roblox.implementMethod("TextBox", "CaptureFocus", function(self)
		focused[self] = true
	end)
	roblox.implementMethod("TextBox", "ReleaseFocus", function(self)
		focused[self] = nil
	end)
	roblox.implementMethod("TextBox", "IsFocused", function(self)
		return focused[self] == true
	end)
	roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, property: string)
		return instanceSignal(self, "Changed:" .. property)
	end)
	roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, attribute: string)
		return instanceSignal(self, "AttributeChanged:" .. attribute)
	end)

	installed = fakes
	return fakes
end

return Fakes
