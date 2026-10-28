--[[
	Fakes (Lune only)

	Lune's Instances carry properties but no engine behaviour: no events, no ParticleEmitter:Emit(), no RunService
	loop. This module implements the small set of engine members ASTRA uses, so runtime code can be exercised
	unchanged. Everything a fake does is recorded so specs can assert on it (e.g. how many particles were emitted).

	These fakes are deliberately minimal. They prove call sequencing and data flow, NOT visual results.

	RunService:BindToRenderStep / UnbindFromRenderStep (Lune has neither): bindings are recorded in
	`fakes.renderBindings` (name -> { name, priority, fn, order }) and every call in `fakes.renderLog`.
	`fakes:renderStep(dt)` runs the bound functions in ascending priority (ties: bind order) — the engine's documented
	rule "lower priority runs earlier" (docs/ROBLOX_API_CONSTRAINTS.md §12). `fakes:step(dt)` runs them after
	PreRender/RenderStepped; the relative order of those events and bound functions is a choice of the fake, not a
	verified engine fact, so specs must not depend on it. Binding an existing name replaces the old binding (engine
	behaviour for duplicate names is not documented); unbinding an unknown name is a no-op (VERIFIED: it does not
	throw). Unlike the engine, the fake also works where there is no local player — specs simulate clients and
	servers through Env.override("Players", …) instead.

	Players.LocalPlayer cannot be faked here: Lune's reflection property takes precedence over
	roblox.implementProperty and always reads nil. Specs simulate a client with
	Env.override("Players", { LocalPlayer = … }). Note that Lune's Workspace starts with a default CurrentCamera and
	that `workspace.CurrentCamera = nil` is rejected by Lune, so specs that need "no camera" override Workspace too.
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
-- Instances with at least one connected handler, held strongly. Lune drops an Instance's userdata wrapper when
-- Luau no longer references it (the next access creates a new one), so the weak-keyed map above would lose the
-- signals — and their handlers — of a live instance that only the tree references, at the next GC. Like the
-- engine, a connection keeps working until it is disconnected.
local pinned: { [any]: { [string]: FakeSignal } } = {}

local function anyHandlers(map: { [string]: FakeSignal }): boolean
	for _, signal in map do
		if next(signal._handlers) ~= nil then
			return true
		end
	end
	return false
end

local function instanceSignal(inst: any, name: string): FakeSignal
	local map = instanceSignals[inst]
	if not map then
		map = {}
		instanceSignals[inst] = map
	end
	local s = map[name]
	if not s then
		s = newSignal(name)
		local connect = s.Connect
		s.Connect = function(self: FakeSignal, fn: (...any) -> ()): FakeConnection
			pinned[inst] = map
			local connection = connect(self, fn)
			local disconnect = connection.Disconnect
			connection.Disconnect = function(c: FakeConnection)
				disconnect(c)
				if pinned[inst] == map and not anyHandlers(map) then
					pinned[inst] = nil
				end
			end
			return connection
		end
		map[name] = s
	end
	return s
end

export type RenderBinding = { name: string, priority: number, fn: (dt: number) -> (), order: number }
export type RenderLogEntry = { action: "bind" | "unbind", name: string, priority: number? }

export type Fakes = {
	heartbeat: FakeSignal,
	preRender: FakeSignal,
	renderStepped: FakeSignal,
	stepped: FakeSignal,
	flags: { IsStudio: boolean, IsRunning: boolean, IsClient: boolean, IsServer: boolean, IsEdit: boolean },
	emits: { { instance: any, count: number } },
	clears: { any },
	sounds: { { instance: any, action: string } },
	renderBindings: { [string]: RenderBinding },
	renderLog: { RenderLogEntry },
	reset: (self: Fakes) -> (),
	step: (self: Fakes, dt: number) -> (),
	renderStep: (self: Fakes, dt: number) -> (),
	renderBindingCount: (self: Fakes) -> number,
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
		renderBindings = {},
		renderLog = {},
	} :: any
	local bindOrder = 0

	function fakes.reset(self: Fakes)
		table.clear(self.emits)
		table.clear(self.clears)
		table.clear(self.sounds)
		table.clear(self.renderBindings)
		table.clear(self.renderLog)
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

	-- Fires one frame of the main RunService events (PreRender/RenderStepped receive dt, Heartbeat receives dt) and
	-- runs the render-step bindings after PreRender/RenderStepped (order chosen by the fake, see header).
	function fakes.step(self: Fakes, dt: number)
		self.preRender:Fire(dt)
		self.renderStepped:Fire(dt)
		self:renderStep(dt)
		self.stepped:Fire(0, dt)
		self.heartbeat:Fire(dt)
	end

	-- Runs every BindToRenderStep function once, lowest priority first (ties: bind order). A function unbound by an
	-- earlier one in the same step does not run.
	function fakes.renderStep(self: Fakes, dt: number)
		local list: { RenderBinding } = {}
		for _, binding in self.renderBindings do
			table.insert(list, binding)
		end
		table.sort(list, function(a: RenderBinding, b: RenderBinding): boolean
			if a.priority ~= b.priority then
				return a.priority < b.priority
			end
			return a.order < b.order
		end)
		for _, binding in list do
			if self.renderBindings[binding.name] == binding then
				binding.fn(dt)
			end
		end
	end

	function fakes.renderBindingCount(self: Fakes): number
		local n = 0
		for _ in self.renderBindings do
			n += 1
		end
		return n
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
	-- RunService:BindToRenderStep(name: string, priority: int, function) / UnbindFromRenderStep(name: string)
	-- (signatures: API dump 0.745). See the header for what the fake does and does not model.
	roblox.implementMethod("RunService", "BindToRenderStep", function(_self, name: string, priority: number, fn: any)
		assert(type(name) == "string", "BindToRenderStep: name must be a string")
		assert(type(priority) == "number", "BindToRenderStep: priority must be a number")
		assert(type(fn) == "function", "BindToRenderStep: function expected")
		bindOrder += 1
		fakes.renderBindings[name] = { name = name, priority = priority, fn = fn, order = bindOrder }
		table.insert(fakes.renderLog, { action = "bind", name = name, priority = priority })
	end)
	roblox.implementMethod("RunService", "UnbindFromRenderStep", function(_self, name: string)
		assert(type(name) == "string", "UnbindFromRenderStep: name must be a string")
		fakes.renderBindings[name] = nil
		table.insert(fakes.renderLog, { action = "unbind", name = name })
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
		GuiObject = {
			"InputBegan",
			"InputChanged",
			"InputEnded",
			"MouseEnter",
			"MouseLeave",
			"MouseMoved",
			"MouseWheelForward",
			"MouseWheelBackward",
			"SelectionGained",
			"SelectionLost",
		},
		GuiButton = {
			"Activated",
			"MouseButton1Click",
			"MouseButton1Down",
			"MouseButton1Up",
			"MouseButton2Click",
			"MouseButton2Down",
			"MouseButton2Up",
		},
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
	-- Strong keys: a weak entry would be dropped when Lune collects the TextBox's userdata wrapper (see `pinned`).
	-- ReleaseFocus removes it.
	local focused: { [any]: boolean } = {}
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
