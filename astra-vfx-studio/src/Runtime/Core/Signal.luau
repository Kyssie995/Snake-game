--!strict
--[[
	Signal — minimal synchronous event implementation (no BindableEvent, works in Lune and Roblox).

	Handlers run synchronously in connection order. A failing handler is reported with warn() and does not
	prevent the remaining handlers from running or break the code that fired the signal.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

type Handler = { fn: (...any) -> (), connection: Connection }

export type Signal = typeof(setmetatable({} :: { _handlers: { Handler }, _firing: number }, Signal))

local ConnectionImpl = {}
ConnectionImpl.__index = ConnectionImpl

function ConnectionImpl.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	local signal = self._signal
	local handlers = signal._handlers
	for i, h in handlers do
		if h.connection == self then
			if signal._firing > 0 then
				-- Copy-on-write while firing so iteration stays stable.
				local copy = table.clone(handlers)
				table.remove(copy, i)
				signal._handlers = copy
			else
				table.remove(handlers, i)
			end
			break
		end
	end
end

function Signal.new(): Signal
	return setmetatable({ _handlers = {}, _firing = 0 }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	local connection = setmetatable({ Connected = true, _signal = self }, ConnectionImpl) :: any
	local handlers = self._handlers
	if self._firing > 0 then
		handlers = table.clone(handlers)
		self._handlers = handlers
	end
	table.insert(handlers, { fn = fn, connection = connection })
	return connection
end

function Signal.Once(self: Signal, fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	local handlers = self._handlers
	self._firing += 1
	for _, h in handlers do
		if h.connection.Connected then
			local ok, err = pcall(h.fn :: any, ...)
			if not ok then
				warn("[AstraVFX] signal handler error: " .. tostring(err))
			end
		end
	end
	self._firing -= 1
end

function Signal.DisconnectAll(self: Signal)
	for _, h in self._handlers do
		h.connection.Connected = false
	end
	self._handlers = {}
end

-- Number of live connections (diagnostics / leak tests).
function Signal.count(self: Signal): number
	return #self._handlers
end

return Signal
