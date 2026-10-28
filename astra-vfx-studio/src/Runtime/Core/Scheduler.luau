--!strict
--[[
	Scheduler — the ONE RunService connection that drives every active Core/Player. See docs/MODULE_CONTRACTS.md
	§18 and docs/ARCHITECTURE.md §5.1 (ADR 3).

	  Scheduler.add(player)          registers a player (anything with :step(dt) -> boolean and :destroy())
	  Scheduler.remove(player)       unregisters it (does not destroy it)
	  Scheduler.count() -> number    registered players (including ones waiting for their first frame)
	  Scheduler.step(dt)             one frame for every registered player (the connection calls this; tests and
	                                 editors may call it manually)
	  Scheduler.setEventName(name)   "Heartbeat" (default) | "PreRender"
	  Scheduler.getEventName() / Scheduler.isConnected() / Scheduler.players()   diagnostics
	  Scheduler.clear()              destroys and removes every registered player

	Rules:
	  * Exactly one connection to RunService[eventName] (RunService through Core/Env) while at least one player is
	    registered; it is made by the first add() and disconnected as soon as the last player is removed (by
	    remove(), by finishing, or by failing). Without a RunService (no DataModel, e.g. the CLI) nothing connects
	    and players run only through manual step() calls (warned once).
	  * "PreRender" is used only when explicitly selected and only on a client (Env.isClient()); otherwise the
	    request is warned about and Heartbeat stays in use (PreRender does not exist on servers, ROBLOX_API_
	    CONSTRAINTS K28). Changing the event while connected reconnects.
	  * dt is clamped to [0, 0.1] (NaN -> 0): a long hitch never skips more than 0.1 s of effect time per frame.
	  * First frame: players added since the previous step() are only activated at the end of the next step()
	    and stepped from the one after it. So a player is never stepped in the engine frame its instances were
	    built / parented in, even when Play() runs before the scheduler's handler in the same frame (an Emit right
	    after parenting can be ignored by the engine, K6). This costs at most one frame of latency.
	  * Error isolation: a player whose step() raises is removed, destroyed (inside pcall) and reported with
	    warn(); the other players continue. A player whose step() returns false is removed.
	  * Re-entrancy: players may add / remove players (including themselves) while being stepped; a nested
	    step() call from inside a player is ignored.
]]

local Env = require(script.Parent.Env)

export type Steppable = {
	step: (self: any, dt: number) -> boolean,
	destroy: (self: any) -> (),
}

export type EventName = "Heartbeat" | "PreRender"

local Scheduler = {}

local MAX_DT = 0.1
Scheduler.MAX_DT = MAX_DT

local active: { Steppable } = {}
local pending: { Steppable } = {}
local membership: { [Steppable]: "active" | "pending" } = {}
local connection: RBXScriptConnection? = nil
local eventName: EventName = "Heartbeat"
local stepping = false
local warnedNoRunService = false

local function count(): number
	return #active + #pending
end

local function removeFrom(list: { Steppable }, player: Steppable)
	local index = table.find(list, player)
	if index then
		table.remove(list, index)
	end
end

local function disconnect()
	local c = connection
	if c then
		connection = nil
		c:Disconnect()
	end
end

local function onFrame(dt: number)
	Scheduler.step(dt)
end

local function connect()
	if connection ~= nil or count() == 0 then
		return
	end
	local ok, result = pcall(function(): any
		local runService: any = Env.getService("RunService")
		return runService[eventName]:Connect(onFrame)
	end)
	if ok and result ~= nil then
		connection = result
	elseif not warnedNoRunService then
		warnedNoRunService = true
		warn(
			"[AstraVFX] Scheduler: no RunService."
				.. eventName
				.. " available ("
				.. tostring(result)
				.. "); step manually"
		)
	end
end

local function clampDt(dt: any): number
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 then
		return 0
	end
	return math.min(dt, MAX_DT)
end

-- Registers a player; it is stepped from the frame after the next one (see header). Adding twice is a no-op.
function Scheduler.add(player: any)
	if type(player) ~= "table" or type((player :: any).step) ~= "function" then
		error("Scheduler.add: expected a player with a step method, got " .. typeof(player), 2)
	end
	if membership[player] ~= nil then
		return
	end
	membership[player] = "pending"
	table.insert(pending, player)
	connect()
end

-- Unregisters a player (it is not destroyed). Disconnects when no player is left.
function Scheduler.remove(player: any)
	local state = membership[player]
	if state == nil then
		return
	end
	membership[player] = nil
	if state == "active" then
		removeFrom(active, player)
	else
		removeFrom(pending, player)
	end
	if count() == 0 then
		disconnect()
	end
end

-- Number of registered players.
function Scheduler.count(): number
	return count()
end

-- One frame: steps every active player, then activates the players added since the previous step.
function Scheduler.step(dt: number)
	if stepping then
		return
	end
	stepping = true
	local clamped = clampDt(dt)
	local snapshot = table.clone(active)
	for _, player in snapshot do
		if membership[player] == "active" then
			local ok, alive = pcall(player.step :: any, player, clamped)
			if not ok then
				Scheduler.remove(player)
				warn("[AstraVFX] effect player failed and was destroyed: " .. tostring(alive))
				local destroyed, err = pcall(player.destroy :: any, player)
				if not destroyed then
					warn("[AstraVFX] destroying the failed player failed too: " .. tostring(err))
				end
			elseif alive == false then
				Scheduler.remove(player)
			end
		end
	end
	if #pending > 0 then
		local promoted = pending
		pending = {}
		for _, player in promoted do
			if membership[player] == "pending" then
				membership[player] = "active"
				table.insert(active, player)
			end
		end
	end
	stepping = false
	if count() == 0 then
		disconnect()
	end
end

-- Selects the RunService event ("Heartbeat" default; "PreRender" only on clients). Reconnects when connected.
function Scheduler.setEventName(name: EventName)
	if name ~= "Heartbeat" and name ~= "PreRender" then
		error('Scheduler.setEventName: expected "Heartbeat" or "PreRender", got ' .. tostring(name), 2)
	end
	local chosen: EventName = name
	if name == "PreRender" and not Env.isClient() then
		warn("[AstraVFX] Scheduler: PreRender exists only on clients; using Heartbeat")
		chosen = "Heartbeat"
	end
	if chosen == eventName then
		return
	end
	eventName = chosen
	if connection ~= nil then
		disconnect()
		connect()
	end
end

function Scheduler.getEventName(): EventName
	return eventName
end

-- True while the RunService connection exists.
function Scheduler.isConnected(): boolean
	return connection ~= nil
end

-- Copy of the registered players (active first, then pending).
function Scheduler.players(): { Steppable }
	local out = table.clone(active)
	for _, player in pending do
		table.insert(out, player)
	end
	return out
end

-- Destroys and removes every registered player (tests, plugin unload).
function Scheduler.clear()
	local all = Scheduler.players()
	for _, player in all do
		Scheduler.remove(player)
		local ok, err = pcall(player.destroy :: any, player)
		if not ok then
			warn("[AstraVFX] destroying a player failed: " .. tostring(err))
		end
	end
	disconnect()
end

return Scheduler
