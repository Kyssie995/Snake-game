--!strict
--[[
	Player — plays one built effect copy (Core/Builder) on the effect time axis. See docs/MODULE_CONTRACTS.md §17
	and docs/ARCHITECTURE.md §5.2.

	  Player.new(compiled, built, options?) -> Player
	    options = { cframe: CFrame?, attach: Instance?, offset: CFrame?, timeScale: number?, loop: boolean?,
	                onEvent: ((name: string) -> ())?,
	                release: ((built) -> boolean)?,   extension: hands the copy back (e.g. to Core/Pool) when the
	                                                  player ends; true = taken, otherwise the copy is destroyed
	                autoRelease: boolean? }           extension (default true): false keeps the instances after
	                                                  the end (state "finished") so an editor can seek() again
	  player:start()             pose at t = 0 (see "Start"), state "playing"
	  player:step(dt) -> alive   one frame (dt in real seconds); false once finished or destroyed
	  player:seek(t)             deterministic state at t without emission (scrubbing)
	  player:pause() / resume() / stop(fade?) / destroy() / setTimeScale(n) / setCFrame(cf) / setLoop(b)
	  player:fire(name)          runtime graph trigger OnEvent(name) at the current time
	  player.time, player.state (Types.PlayerState), player.cycle, player.compiled, player.built
	  player.finished: Signal(reason: "finished" | "destroyed")   fired once when the player ends
	  player.event: Signal(name)                                   marker / component / graph "fire" events
	  player.actionExecuted: Signal(ScheduledAction)               every executed scheduled action

	Time: player.time is effect time (seconds). A step advances it by dt × timeScale × compiled.timeScale.

	Frame (step while playing):
	  1. Advance time. Loop (effect loop or setLoop(true), duration > 0): when the time reaches the duration, the
	     components are evaluated at the duration first (like the last frame of a one-shot effect: spans that end
	     deactivate, a span that lies inside this frame is still activated once so its burst is not lost), the
	     remaining actions of the cycle (t_prev, duration] run, `cycle` increments, the schedule becomes
	     Compiler.scheduleForCycle(compiled, cycle) (graph random values depend on the cycle), the time wraps and
	     the cycle state is reset: every active component is deactivated (so it re-activates — bursts, sound
	     playOnStart and trail clearOnStart happen every cycle), graph overrides and SetEnabled states are cleared,
	     components disabled by a "disable" action get a synthetic "enable" (the authored state) and pending runtime
	     actions move back by one duration, and a tail that had started (setLoop toggled after the end) restarts.
	     Runtime actions beyond the duration of a looping effect wait for the next cycle; at most 64 wraps happen
	     per step (the cycles a long frame skips run their actions, without the end-of-cycle evaluation).
	  2. Root CFrame = base × offset. base = the attach target's CFrame (BasePart.CFrame, Attachment.WorldCFrame —
	     parent part CFrame × Attachment.CFrame where WorldCFrame is not readable, e.g. Lune —, Model:GetPivot())
	     or the fixed cframe. A target that is no longer inside a WorldRoot (removed, destroyed, streamed out)
	     keeps the last base and the effect keeps playing; a target that cannot be read any more (Lune raises on
	     destroyed Instances) is dropped the same way. The Root part moves only when the CFrame changed.
	  3. Components in topological order. Transform: position / rotation are the track value (or graph override)
	     instead of the rest value; rotation += spin × max(localTime, 0) for components whose props.spin is a
	     non-zero Vector3; local = parentLocal × CFrame.new(position) × CFrame.fromOrientation(rotation°);
	     world = root × local. Activation: Timeline.isActive(component, t) and not switched off by a SetEnabled /
	     "disable" action on a type that does not declare that event. On activation the channels are applied and
	     the transform set BEFORE setActive(true), so bursts and starts happen at the right place. A span that
	     starts and ends inside one frame is activated and deactivated in that frame (its burst is not lost).
	     Active components: channels (tracks, then overrides; never position/rotation) are evaluated with
	     Curves.evaluate and passed to controller:apply only when the value changed since the last apply;
	     setTransform(local, world, frame); update(localTime, frame). Inactive components only get setTransform
	     when their world CFrame changed, so they activate at the right place.
	  4. Due actions in (t_prev, t] — on the first frame after start(), seek() or a wrap [t_prev, t] — run in
	     schedule order, merged with runtime actions from fire() (static first on equal times):
	       "fire"           -> player.event + options.onEvent (pcall) with action.name
	       "tween" / "set"  -> per-(component, channel) override, evaluated after tracks: set = the value from now
	                           on; tween = from the channel value at the action time (track / earlier override /
	                           rest value) to the target over `duration` with `easing`, then the target.
	                           Appearance channels of an active component are applied in the same frame,
	                           position / rotation with the next frame's transform evaluation.
	       "enable"/"disable" on a type that does not declare the event -> the component is switched off (now)
	                           / back on (with the next evaluation)
	       everything else -> controller:onAction(action, frame) of action.componentId
	     A handler that calls seek / stop / destroy ends the action loop of that frame.
	  5. One WorldRoot:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) for every queued part
	     (Root included; a loop-wrap frame evaluates twice, so there each part is sent once, with its last
	     CFrame). WorldRoot = the container's WorldRoot ancestor when it is not a Workspace (a WorldModel in
	     viewport mode), else Env.getService("Workspace"); without either the CFrames are assigned directly.
	  6. End (no loop): once time >= duration, the player waits for the tail and then finishes. Tail and stop
	     linger are REAL seconds (particles and trails age in real time; emitters run at min(1, compiled
	     timeScale)): tail = compiled.maxTail / clamp(compiled.timeScale, 0.1, 1).
	     Finish: state "finished", the copy goes to options.release (or is destroyed), finished:Fire("finished").

	Start: start() poses everything at t = 0 — the root and the transform of every component (BulkMoveTo) —
	without activating anything, applying channels or running actions, because an Emit in the frame the copy was
	built / parented can be ignored by the engine (docs/ROBLOX_API_CONSTRAINTS.md K6). The first step() activates
	the components and runs the actions at t = 0. (Core/Scheduler additionally steps a player first in the frame
	after the one it was added in.)

	Pause: time, tracks, schedule and procedural motion freeze; the root still follows the attach target. Engine
	particles keep simulating (there is no generic pause hook), and activation does not change while paused.
	setTimeScale / options.timeScale scale the effect clock only: ParticleEmitter.TimeScale follows the
	definition's timeScale (set at build time by the descriptor), so engine particles do not slow down with it.
	stop(fade?): every controller is release()d (no new emission, live particles finish), no more actions run, the
	time keeps advancing for transforms, and the player finishes after `fade` real seconds (default: the tail;
	0 = now). destroy(): immediate; the copy goes to options.release or is destroyed; idempotent. Signals are
	disconnected once the copy is gone.

	seek(t): t clamped to [0, duration]. Every controller is reset() (authored state, particles cleared — the
	engine cannot fast-forward particles), overrides / runtime actions / SetEnabled states are cleared, then the
	scheduled actions with time < t are replayed for their state only — tween/set overrides, enable/disable,
	clear, regenerate, stop; never emit, play or fire — and the state at t is evaluated with frame.seeking = true
	(no bursts, no sounds). The result depends only on (t, cycle), so seeking twice to the same time from any state
	gives identical instances. Actions AT t run with the next step. seek() in state "idle" or "finished" (with
	autoRelease = false) leaves the player "paused"; it is ignored while stopping or after the copy is gone.

	fire(name): Graph.run(compiled.graph, { kind = "event", id = name }, time, compiled.seed, cycle, compiled);
	the actions join the runtime queue (only while playing or paused). seek() and stop() drop the queue.

	Errors raised by controllers propagate (Core/Scheduler isolates failing players); onEvent errors are caught
	and reported with warn().

	User callbacks — options.onEvent and the handlers of finished / event / actionExecuted — run through
	task.spawn: immediately and in order, so for handlers that do not yield nothing changes, but a handler that
	yields (task.wait, WaitForChild, ...) suspends only its own thread. Called directly it would suspend the
	Scheduler's frame, and every effect would freeze until it resumed.
]]

local Builder = require(script.Parent.Builder)
local Codec = require(script.Parent.Codec)
local Common = require(script.Parent.Components.Common)
local Compiler = require(script.Parent.Compiler)
local Components = require(script.Parent.Components)
local Constants = require(script.Parent.Constants)
local Curves = require(script.Parent.Curves)
local Env = require(script.Parent.Env)
local Graph = require(script.Parent.Graph)
local Signal = require(script.Parent.Signal)
local Timeline = require(script.Parent.Timeline)
local Types = require(script.Parent.Types)

type CompiledEffect = Types.CompiledEffect
type CompiledComponent = Types.CompiledComponent
type CompiledTrack = Types.CompiledTrack
type ComponentInstance = Types.ComponentInstance
type ChannelSpec = Types.ChannelSpec
type FrameContext = Types.FrameContext
type ScheduledAction = Types.ScheduledAction
type PlayerState = Types.PlayerState
type EasingFn = Types.EasingFn
type BuiltEffect = Builder.BuiltEffect

export type PlayerOptions = {
	cframe: CFrame?,
	attach: Instance?,
	offset: CFrame?,
	timeScale: number?,
	loop: boolean?,
	onEvent: ((name: string) -> ())?,
	release: ((built: BuiltEffect) -> boolean)?,
	autoRelease: boolean?,
}

type Mode = "pose" | "play" | "hold" | "stop" | "seek"

type Override = {
	kind: string, -- "set" | "tween"
	channelKind: string,
	value: any, -- set: the value; tween: the target
	from: any, -- tween start value
	start: number, -- absolute effect time of the action
	duration: number,
	easing: EasingFn?,
}

type Plan = {
	component: CompiledComponent,
	controller: ComponentInstance,
	parent: Plan?,
	trackChannels: { string }, -- tracked channels except position / rotation, sorted
	channels: { string }, -- applied while active: tracks + overridden channels, sorted
	positionTrack: CompiledTrack?,
	rotationTrack: CompiledTrack?,
	spin: Vector3?,
	declares: { [string]: boolean }, -- event actions the descriptor declares
	active: boolean,
	applied: { [string]: any }, -- last value passed to controller:apply per channel
	localCFrame: CFrame,
	lastWorld: CFrame?,
}

type PlayerData = {
	compiled: CompiledEffect,
	built: BuiltEffect,
	time: number,
	state: PlayerState,
	cycle: number,
	finished: Signal.Signal,
	event: Signal.Signal,
	actionExecuted: Signal.Signal,

	_plans: { Plan },
	_byId: { [string]: Plan },
	_frame: FrameContext,
	_schedule: { ScheduledAction },
	_runtime: { ScheduledAction },
	_overrides: { [string]: { [string]: Override } },
	_forcedOff: { [string]: boolean },
	_disabled: { [string]: boolean },
	_includeStart: boolean,
	_epoch: number,
	_timeScale: number,
	_rate: number,
	_loop: boolean,
	_base: CFrame,
	_attach: Instance?,
	_offset: CFrame?,
	_rootCFrame: CFrame?,
	_onEvent: ((name: string) -> ())?,
	_release: ((built: BuiltEffect) -> boolean)?,
	_autoRelease: boolean,
	_disposed: boolean,
	_tail: number?,
	_tailLimit: number,
	_stopElapsed: number,
	_stopLinger: number,
	_moves: number,
	_dedupe: boolean,
}

local Player = {}
Player.__index = Player

export type Player = typeof(setmetatable({} :: PlayerData, Player))

local IDENTITY = CFrame.new()
local WHITE = Color3.new(1, 1, 1)
local INF = math.huge
local MAX_WRAPS = 64
local TAIL_MIN_RATE = 0.1
local MAX_TIME_SCALE = Constants.MAX_TIME_SCALE
local NO_ACTIONS: { ScheduledAction } = table.freeze({}) :: any

Player.MAX_WRAPS = MAX_WRAPS

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function describe(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return typeof(v) .. " " .. tostring(v)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Root / attach target
-- ─────────────────────────────────────────────────────────────────────────────

-- nil until the first attempt; true when Attachment.WorldCFrame can be read (Roblox), false otherwise (Lune).
local worldCFrameReadable: boolean? = nil

local function readWorldCFrame(attachment: Attachment): CFrame
	return attachment.WorldCFrame
end

local function attachmentCFrame(attachment: Attachment): CFrame?
	if worldCFrameReadable then
		return attachment.WorldCFrame
	end
	if worldCFrameReadable == nil then
		local ok, value = pcall(readWorldCFrame, attachment)
		worldCFrameReadable = ok and typeof(value) == "CFrame"
		if worldCFrameReadable then
			return value
		end
	end
	local parent = attachment.Parent
	if parent ~= nil and parent:IsA("BasePart") then
		return (parent :: BasePart).CFrame * attachment.CFrame
	end
	return nil
end

-- World CFrame of an attach target, or nil when it is not inside a WorldRoot (removed / destroyed / streamed out).
local function targetCFrame(target: Instance): CFrame?
	local world: Instance? = target:FindFirstAncestorWhichIsA("WorldRoot")
	if target.Parent == nil or world == nil then
		return nil
	end
	if target:IsA("BasePart") then
		return (target :: BasePart).CFrame
	elseif target:IsA("Attachment") then
		return attachmentCFrame(target :: Attachment)
	elseif target:IsA("PVInstance") then
		return (target :: PVInstance):GetPivot()
	end
	return nil
end

Player._targetCFrame = targetCFrame

-- ─────────────────────────────────────────────────────────────────────────────
-- Channel values
-- ─────────────────────────────────────────────────────────────────────────────

-- Resting value of a channel without track or override.
local function restValue(c: CompiledComponent, channel: string): any
	if channel == "position" then
		return c.position
	elseif channel == "rotation" then
		return c.rotation
	elseif channel == "scale" then
		return c.scale
	end
	local spec: ChannelSpec? = Components.channelSpec(c.type, channel)
	if spec == nil then
		return nil
	end
	local base = spec.baseProperty
	if base ~= nil then
		local v = c.props[base]
		if v ~= nil then
			return v
		end
	end
	local kind = spec.kind
	if kind == "vector3" then
		return Vector3.zero
	elseif kind == "color3" then
		return WHITE -- tint: white = unchanged
	elseif kind == "boolean" then
		return false
	end
	return 0 -- number channels without a base property are fades (0 = unchanged)
end

local function overrideValue(o: Override, t: number): any
	if o.kind == "set" then
		return o.value
	end
	local duration = o.duration
	if duration <= 0 or t >= o.start + duration then
		return o.value
	end
	local alpha = (t - o.start) / duration
	if not (alpha > 0) then
		return o.from
	end
	local easing = o.easing
	local e = if easing then easing(alpha) else alpha
	if o.channelKind == "number" then
		return o.from + (o.value - o.from) * e
	end
	return Codec.lerp(o.channelKind, o.from, o.value, e)
end

local function insertSorted(list: { string }, name: string)
	for i, existing in list do
		if existing == name then
			return
		elseif existing > name then
			table.insert(list, i, name)
			return
		end
	end
	table.insert(list, name)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Construction
-- ─────────────────────────────────────────────────────────────────────────────

local function buildPlans(compiled: CompiledEffect, built: BuiltEffect): ({ Plan }, { [string]: Plan })
	local plans: { Plan } = {}
	local byId: { [string]: Plan } = {}
	for _, c in compiled.components do
		local controller = built.controllers[c.id]
		if controller == nil then
			error(
				"Player.new: the built effect has no controller for component "
					.. string.format("%q", c.id)
					.. " (built from another CompiledEffect?)",
				3
			)
		end
		local trackChannels: { string } = {}
		for channel in c.tracks do
			if channel ~= "position" and channel ~= "rotation" then
				table.insert(trackChannels, channel)
			end
		end
		table.sort(trackChannels)
		local declares: { [string]: boolean } = {}
		local descriptor = Components.get(c.type)
		if descriptor then
			for _, event in descriptor.events do
				declares[event.action] = true
			end
		end
		local spin: any = c.props.spin
		local plan: Plan = {
			component = c,
			controller = controller,
			parent = if c.parentId then byId[c.parentId] else nil,
			trackChannels = trackChannels,
			channels = table.clone(trackChannels),
			positionTrack = c.tracks.position,
			rotationTrack = c.tracks.rotation,
			spin = if typeof(spin) == "Vector3" and (spin :: Vector3).Magnitude > 0 then spin else nil,
			declares = declares,
			active = false,
			applied = {},
			localCFrame = IDENTITY,
			lastWorld = nil,
		}
		table.insert(plans, plan)
		byId[c.id] = plan
	end
	return plans, byId
end

-- Creates a player for one built copy of `compiled` (state "idle"; call start()).
function Player.new(compiled: CompiledEffect, built: BuiltEffect, options: PlayerOptions?): Player
	if type(compiled) ~= "table" or type((compiled :: any).components) ~= "table" then
		error("Player.new: expected a CompiledEffect (Compiler.compile), got " .. typeof(compiled), 2)
	end
	if type(built) ~= "table" or type((built :: any).controllers) ~= "table" then
		error("Player.new: expected a BuiltEffect (Builder.build), got " .. typeof(built), 2)
	end
	if built.destroyed then
		error("Player.new: the built effect was already destroyed", 2)
	end
	local o: PlayerOptions = options or {}
	if type(o) ~= "table" then
		error("Player.new: options must be a table, got " .. typeof(o), 2)
	end
	if o.cframe ~= nil and typeof(o.cframe) ~= "CFrame" then
		error("Player.new: options.cframe must be a CFrame, got " .. describe(o.cframe), 2)
	end
	if o.offset ~= nil and typeof(o.offset) ~= "CFrame" then
		error("Player.new: options.offset must be a CFrame, got " .. describe(o.offset), 2)
	end
	if o.attach ~= nil and typeof(o.attach) ~= "Instance" then
		error("Player.new: options.attach must be an Instance, got " .. describe(o.attach), 2)
	end
	local timeScale: any = if o.timeScale == nil then 1 else o.timeScale
	if not isFinite(timeScale) or timeScale < 0 then
		error("Player.new: options.timeScale must be a finite number >= 0, got " .. describe(timeScale), 2)
	end
	timeScale = math.min(timeScale, MAX_TIME_SCALE)
	if o.loop ~= nil and type(o.loop) ~= "boolean" then
		error("Player.new: options.loop must be a boolean, got " .. describe(o.loop), 2)
	end
	if o.onEvent ~= nil and type(o.onEvent) ~= "function" then
		error("Player.new: options.onEvent must be a function, got " .. describe(o.onEvent), 2)
	end
	if o.release ~= nil and type(o.release) ~= "function" then
		error("Player.new: options.release must be a function, got " .. describe(o.release), 2)
	end

	local plans, byId = buildPlans(compiled, built)
	local effectRate: number = compiled.timeScale
	local self: Player
	local frame: FrameContext = {
		time = 0,
		dt = 0,
		seeking = false,
		rootCFrame = o.cframe or IDENTITY,
		moveParts = {},
		moveCFrames = {},
		fire = function(name: string)
			self:_emitEvent(name)
		end,
	}
	self = setmetatable({
		compiled = compiled,
		built = built,
		time = 0,
		state = "idle" :: PlayerState,
		cycle = 0,
		finished = Signal.new(),
		event = Signal.new(),
		actionExecuted = Signal.new(),
		_plans = plans,
		_byId = byId,
		_frame = frame,
		_schedule = compiled.schedule,
		_runtime = {},
		_overrides = {},
		_forcedOff = {},
		_disabled = {},
		_includeStart = true,
		_epoch = 0,
		_timeScale = timeScale,
		_rate = timeScale * effectRate,
		_loop = if o.loop == nil then compiled.loop == true else o.loop,
		_base = o.cframe or IDENTITY,
		_attach = o.attach,
		_offset = o.offset,
		_rootCFrame = nil,
		_onEvent = o.onEvent,
		_release = o.release,
		_autoRelease = o.autoRelease ~= false,
		_disposed = false,
		_tail = nil,
		_tailLimit = compiled.maxTail / math.clamp(effectRate, TAIL_MIN_RATE, 1),
		_stopElapsed = 0,
		_stopLinger = 0,
		_moves = 0,
		_dedupe = false,
	}, Player)
	return self
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internals
-- ─────────────────────────────────────────────────────────────────────────────

-- Calls options.onEvent; errors are reported with warn(), never raised.
local function callOnEvent(onEvent: (name: string) -> (), name: string)
	local ok, err = pcall(onEvent :: any, name)
	if not ok then
		warn("[AstraVFX] OnEvent handler error (" .. name .. "): " .. tostring(err))
	end
end

-- Fires a signal whose handlers are user code in a thread of its own (see the header). Signal.Fire catches
-- handler errors itself.
local function dispatch(signal: Signal.Signal, ...: any)
	if signal:count() > 0 then
		task.spawn(signal.Fire :: any, signal, ...)
	end
end

function Player._emitEvent(self: Player, name: string)
	if type(name) ~= "string" or name == "" then
		return
	end
	dispatch(self.event, name)
	local onEvent = self._onEvent
	if onEvent then
		task.spawn(callOnEvent, onEvent, name)
	end
end

function Player._resolveRoot(self: Player): CFrame
	local target = self._attach
	if target then
		local ok, cf = pcall(targetCFrame, target)
		if not ok then
			self._attach = nil -- cannot be read any more (Lune: destroyed): keep the last base
		elseif cf then
			self._base = cf
		end
	end
	local offset = self._offset
	return if offset then self._base * offset else self._base
end

-- Clears the move lists, resolves the root CFrame (queues the Root part when it moved) and returns the frame.
function Player._beginFrame(self: Player, seeking: boolean): FrameContext
	local frame = self._frame
	table.clear(frame.moveParts)
	table.clear(frame.moveCFrames)
	frame.seeking = seeking
	frame.time = self.time
	frame.dt = 0
	local root = self:_resolveRoot()
	frame.rootCFrame = root
	if root ~= self._rootCFrame then
		self._rootCFrame = root
		table.insert(frame.moveParts, self.built.root)
		table.insert(frame.moveCFrames, root)
	end
	return frame
end

-- The WorldRoot that moves this copy's parts (see header step 5), or nil.
function Player._worldRoot(self: Player): any
	local container = self.built.container
	local ancestor: Instance? = container:FindFirstAncestorWhichIsA("WorldRoot")
	if ancestor ~= nil and not ancestor:IsA("Workspace") then
		return ancestor
	end
	local ok, workspaceService = pcall(Env.getService :: any, "Workspace")
	if ok then
		return workspaceService
	end
	return nil
end

-- Applies every queued part move with one BulkMoveTo.
function Player._flush(self: Player)
	local frame = self._frame
	local parts = frame.moveParts
	local n = #parts
	self._moves = n
	local dedupe = self._dedupe
	self._dedupe = false
	if n == 0 then
		return
	end
	local cframes = frame.moveCFrames
	if dedupe then
		-- a loop-wrap frame evaluates twice: send every part once, with its last CFrame
		local index: { [BasePart]: number } = {}
		local m = 0
		for i = 1, n do
			local part = parts[i]
			local at = index[part]
			if at then
				cframes[at] = cframes[i]
			else
				m += 1
				index[part] = m
				parts[m] = part
				cframes[m] = cframes[i]
			end
		end
		for i = n, m + 1, -1 do
			parts[i] = nil
			cframes[i] = nil
		end
		n = m
		self._moves = n
	end
	local world = self:_worldRoot()
	if world ~= nil then
		world:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	else
		for i = 1, n do
			parts[i].CFrame = cframes[i]
		end
	end
	table.clear(parts)
	table.clear(cframes)
end

-- Channel value at absolute time t: override, else track, else rest value.
function Player._value(self: Player, plan: Plan, channel: string, t: number): any
	local c = plan.component
	local overrides = self._overrides[c.id]
	local o = if overrides then overrides[channel] else nil
	if o then
		return overrideValue(o, t)
	end
	local track = c.tracks[channel]
	if track then
		return Curves.evaluate(track, t - c.startTime)
	end
	return restValue(c, channel)
end

-- Passes changed channel values to the controller.
function Player._apply(self: Player, plan: Plan, t: number)
	local channels = plan.channels
	if #channels == 0 then
		return
	end
	local applied = plan.applied
	local controller = plan.controller
	for _, channel in channels do
		local v = self:_value(plan, channel, t)
		if v ~= nil and applied[channel] ~= v then
			applied[channel] = v
			controller:apply(channel, v)
		end
	end
end

-- Evaluates every component at self.time (header step 3). `prev` (play mode) enables transient activation.
function Player._evaluate(self: Player, mode: Mode, frame: FrameContext, prev: number?, includeStart: boolean?)
	local t = self.time
	local root = frame.rootCFrame
	local overridesById = self._overrides
	local forcedOff = self._forcedOff
	local epoch = self._epoch
	for _, plan in self._plans do
		if self._epoch ~= epoch then
			return -- a controller callback destroyed / stopped / seeked the player
		end
		local c = plan.component
		local controller = plan.controller
		local localTime = t - c.startTime
		local overrides = overridesById[c.id]
		local position = c.position
		if plan.positionTrack or (overrides and overrides.position) then
			local v = self:_value(plan, "position", t)
			if typeof(v) == "Vector3" then
				position = v
			end
		end
		local rotation = c.rotation
		if plan.rotationTrack or (overrides and overrides.rotation) then
			local v = self:_value(plan, "rotation", t)
			if typeof(v) == "Vector3" then
				rotation = v
			end
		end
		local spin = plan.spin
		if spin and localTime > 0 then
			rotation += spin * localTime
		end
		local localCFrame = Common.cframeFrom(position, rotation)
		local parent = plan.parent
		if parent then
			localCFrame = parent.localCFrame * localCFrame
		end
		plan.localCFrame = localCFrame
		local world = root * localCFrame

		if mode == "pose" then
			controller:setTransform(localCFrame, world, frame)
			plan.lastWorld = world
			continue
		end

		local want = Timeline.isActive(c, t) and not forcedOff[c.id]
		if mode == "hold" then
			-- paused: time is frozen, so activation does not change (an Autoplay = false copy stays dark)
			want = plan.active
		end
		if want ~= plan.active then
			if want then
				if mode ~= "stop" then
					self:_apply(plan, t)
					controller:setTransform(localCFrame, world, frame)
					plan.lastWorld = world
					plan.active = true
					controller:setActive(true, frame)
				end
			else
				plan.active = false
				controller:setActive(false, frame)
			end
		elseif
			not want
			and mode == "play"
			and prev ~= nil
			and c.endTime > c.startTime
			and c.startTime <= t
			and (c.startTime > prev or (includeStart and c.startTime >= prev))
			and not forcedOff[c.id]
		then
			-- The whole span lies inside this frame: activate for this frame only, so its burst is not lost.
			self:_apply(plan, t)
			controller:setTransform(localCFrame, world, frame)
			plan.lastWorld = world
			controller:setActive(true, frame)
			controller:setActive(false, frame)
		end

		if plan.active then
			self:_apply(plan, t)
			controller:setTransform(localCFrame, world, frame)
			plan.lastWorld = world
			local update = controller.update
			if update then
				update(controller, localTime, frame)
			end
		elseif plan.lastWorld ~= world then
			plan.lastWorld = world
			controller:setTransform(localCFrame, world, frame)
		end
	end
end

-- Registers a graph tween / set override (header step 4).
function Player._addOverride(self: Player, action: ScheduledAction)
	local id = action.componentId
	local plan = if id then self._byId[id] else nil
	local channel = action.channel
	if plan == nil or type(channel) ~= "string" or action.value == nil then
		return
	end
	local c = plan.component
	local spec = Components.channelSpec(c.type, channel)
	if spec == nil then
		return
	end
	local override: Override
	if action.action == "set" then
		override = {
			kind = "set",
			channelKind = spec.kind,
			value = action.value,
			from = nil,
			start = action.time,
			duration = 0,
			easing = nil,
		}
	else
		local duration: any = action.duration
		override = {
			kind = "tween",
			channelKind = spec.kind,
			value = action.value,
			from = self:_value(plan, channel, action.time),
			start = action.time,
			duration = if isFinite(duration) and duration > 0 then duration else 0,
			easing = action.easing,
		}
	end
	local overrides = self._overrides[c.id]
	if overrides == nil then
		overrides = {}
		self._overrides[c.id] = overrides
	end
	overrides[channel] = override
	if channel ~= "position" and channel ~= "rotation" then
		insertSorted(plan.channels, channel)
		if plan.active then
			-- appearance channels take effect in this frame; transforms with the next evaluation
			local v = self:_value(plan, channel, self.time)
			if v ~= nil and plan.applied[channel] ~= v then
				plan.applied[channel] = v
				plan.controller:apply(channel, v)
			end
		end
	end
end

-- Routes a component action (everything except fire / tween / set) to its controller.
function Player._route(self: Player, action: ScheduledAction, frame: FrameContext)
	local id = action.componentId
	local plan = if id then self._byId[id] else nil
	if plan == nil then
		return
	end
	local kind = action.action
	if (kind == "enable" or kind == "disable") and not plan.declares[kind] then
		if kind == "disable" then
			self._forcedOff[plan.component.id] = true
			if plan.active then
				plan.active = false
				plan.controller:setActive(false, frame)
			end
		else
			-- switched back on with the next evaluation (activation needs that frame's transform)
			self._forcedOff[plan.component.id] = nil
		end
		return
	end
	if kind == "disable" then
		self._disabled[plan.component.id] = true
	elseif kind == "enable" then
		self._disabled[plan.component.id] = nil
	end
	plan.controller:onAction(action, frame)
end

function Player._execute(self: Player, action: ScheduledAction, frame: FrameContext)
	local kind = action.action
	if kind == "fire" then
		local name = action.name
		if type(name) == "string" then
			self:_emitEvent(name)
		end
	elseif kind == "tween" or kind == "set" then
		self:_addOverride(action)
	else
		self:_route(action, frame)
	end
	dispatch(self.actionExecuted, action)
end

-- Seek replay: state-changing actions only (no emission, no events).
function Player._replay(self: Player, action: ScheduledAction, frame: FrameContext)
	local kind = action.action
	if kind == "tween" or kind == "set" then
		self:_addOverride(action)
	elseif kind ~= "emit" and kind ~= "play" and kind ~= "fire" then
		self:_route(action, frame)
	end
end

-- Runs the due static actions in (t0, t1] ([t0, t1] on the first frame) merged with due runtime actions.
function Player._runDue(self: Player, t0: number, t1: number, frame: FrameContext)
	local includeStart = self._includeStart
	self._includeStart = false
	local schedule = self._schedule
	local first, last = Timeline.range(schedule, t0, t1, includeStart)
	local due = NO_ACTIONS
	local runtime = self._runtime
	if #runtime > 0 and runtime[1].time <= t1 then
		due = {}
		local keep: { ScheduledAction } = {}
		for _, action in runtime do
			if action.time <= t1 then
				table.insert(due, action)
			else
				table.insert(keep, action)
			end
		end
		self._runtime = keep
	end
	local nd = #due
	if last < first and nd == 0 then
		return
	end
	local epoch = self._epoch
	local i, j = first, 1
	while i <= last or j <= nd do
		local action: ScheduledAction
		if j > nd or (i <= last and schedule[i].time <= due[j].time) then
			action = schedule[i]
			i += 1
		else
			action = due[j]
			j += 1
		end
		self:_execute(action, frame)
		if self._epoch ~= epoch then
			return
		end
	end
end

-- Starts the next loop cycle (header step 1).
function Player._wrap(self: Player, frame: FrameContext)
	local duration = self.compiled.duration
	self.cycle += 1
	self._schedule = Compiler.scheduleForCycle(self.compiled, self.cycle)
	for _, plan in self._plans do
		if plan.active then
			plan.active = false
			plan.controller:setActive(false, frame)
		end
	end
	self._overrides = {}
	self._forcedOff = {}
	local disabled = self._disabled
	self._disabled = {}
	for id in disabled do
		local plan = self._byId[id]
		if plan then
			local enable: ScheduledAction = {
				time = 0,
				action = "enable",
				componentId = id,
				source = "event",
				order = 0,
			}
			plan.controller:onAction(enable, frame)
		end
	end
	for _, action in self._runtime do
		action.time -= duration
	end
	self._tail = nil -- a tail that had started (setLoop(true) after the end) belongs to the old cycle
	self._includeStart = true
end

-- Ends the player normally (header step 6).
function Player._finish(self: Player)
	if self.state == "finished" or self.state == "destroyed" then
		return
	end
	self._epoch += 1
	self.state = "finished"
	self._runtime = {}
	if self._autoRelease then
		self:_dispose()
	end
	dispatch(self.finished, "finished")
	if self._disposed then
		self:_disconnect()
	end
end

-- Hands the copy to options.release or destroys it (once).
function Player._dispose(self: Player)
	if self._disposed then
		return
	end
	self._disposed = true
	local built = self.built
	if built.destroyed then
		return
	end
	local taken = false
	local release = self._release
	if release then
		local ok, result = pcall(release, built)
		if not ok then
			warn("[AstraVFX] releasing an effect copy failed: " .. tostring(result))
		end
		taken = ok and result == true
	end
	if not taken then
		built:destroy()
	end
end

function Player._disconnect(self: Player)
	self.finished:DisconnectAll()
	self.event:DisconnectAll()
	self.actionExecuted:DisconnectAll()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

-- Poses the copy at t = 0 (no activation, no actions) and starts playback. No-op unless idle.
function Player.start(self: Player)
	if self.state ~= "idle" then
		return
	end
	self.state = "playing"
	self.time = 0
	self._includeStart = true
	local frame = self:_beginFrame(false)
	self:_evaluate("pose", frame)
	self:_flush()
end

-- Advances one frame by `dt` real seconds. Returns false once the player has finished or was destroyed.
function Player.step(self: Player, dt: number): boolean
	local state = self.state
	if state == "finished" or state == "destroyed" then
		return false
	end
	if state == "idle" then
		return true
	end
	local realDt: number = if isFinite(dt) and dt > 0 then dt else 0

	if state == "paused" then
		local frame = self:_beginFrame(false)
		self:_evaluate("hold", frame)
		self:_flush()
		return true
	end

	local scaled = realDt * self._rate
	if state == "stopping" then
		self.time += scaled
		local frame = self:_beginFrame(false)
		frame.dt = scaled
		self:_evaluate("stop", frame)
		self:_flush()
		self._stopElapsed += realDt
		if self._stopElapsed >= self._stopLinger then
			self:_finish()
			return false
		end
		return true
	end

	-- playing
	local epoch = self._epoch
	local prev = self.time
	local t = prev + scaled
	local duration = self.compiled.duration
	local frame = self:_beginFrame(false)
	frame.dt = scaled
	if self._loop and duration > 0 and t >= duration then
		-- the end of this cycle, like the last frame of a one-shot effect (header step 1)
		self.time = duration
		frame.time = duration
		self._dedupe = true
		self:_evaluate("play", frame, prev, self._includeStart)
		if self._epoch == epoch then
			self:_runDue(prev, duration, frame)
		end
		local wraps = 0
		while self._epoch == epoch and t >= duration and wraps < MAX_WRAPS do
			t -= duration
			wraps += 1
			self:_wrap(frame)
			if t >= duration and wraps < MAX_WRAPS then
				-- dt longer than a whole cycle: run that cycle's actions too
				self:_runDue(0, duration, frame)
			end
		end
		if t >= duration then
			t = t % duration
		end
		prev = 0
	end
	if self._epoch ~= epoch then
		-- a handler stopped / seeked / destroyed the player during the end of the cycle
		if not self._disposed then
			self:_flush()
		end
		return self.state ~= "finished" and self.state ~= "destroyed"
	end
	local includeStart = self._includeStart
	self.time = t
	frame.time = t
	self:_evaluate("play", frame, prev, includeStart)
	if self._epoch == epoch then
		self:_runDue(prev, t, frame)
	end
	if self._epoch ~= epoch then
		if not self._disposed then
			self:_flush()
		end
		return self.state ~= "finished" and self.state ~= "destroyed"
	end
	self:_flush()

	if not self._loop and t >= duration then
		local tail = self._tail
		if tail == nil then
			tail = if self._rate > 0 then (t - math.max(prev, duration)) / self._rate else 0
		else
			tail += realDt
		end
		self._tail = tail
		if tail >= self._tailLimit then
			self:_finish()
			return false
		end
	end
	return true
end

-- Deterministic state at time t without emission (scrubbing). See the header.
function Player.seek(self: Player, t: number)
	if not isFinite(t) then
		error("Player.seek: time must be a finite number, got " .. describe(t), 2)
	end
	local state = self.state
	if state == "destroyed" or state == "stopping" or self._disposed then
		return
	end
	local duration = self.compiled.duration
	local target = math.clamp(t, 0, math.max(duration, 0))
	self._epoch += 1
	self.built:reset()
	for _, plan in self._plans do
		plan.active = false
		table.clear(plan.applied)
		plan.lastWorld = nil
		plan.channels = table.clone(plan.trackChannels)
	end
	self._overrides = {}
	self._forcedOff = {}
	self._disabled = {}
	self._runtime = {}
	self._tail = nil
	self._rootCFrame = nil
	self.time = target
	local frame = self:_beginFrame(true)
	for _, action in self._schedule do
		if not (action.time < target) then
			break
		end
		self:_replay(action, frame)
	end
	self:_evaluate("seek", frame)
	self:_flush()
	self._includeStart = true
	if state == "idle" or state == "finished" then
		self.state = "paused"
	end
end

-- Freezes the effect time (state "paused").
function Player.pause(self: Player)
	if self.state == "playing" then
		self.state = "paused"
	end
end

-- Continues a paused player; starts an idle one.
function Player.resume(self: Player)
	if self.state == "paused" then
		self.state = "playing"
	elseif self.state == "idle" then
		self:start()
	end
end

-- Graceful end: release every controller and finish after `fade` real seconds (default: the tail).
function Player.stop(self: Player, fade: number?)
	if fade ~= nil and not (isFinite(fade) and (fade :: number) >= 0) then
		error("Player.stop: fade must be a finite number >= 0, got " .. describe(fade), 2)
	end
	local state = self.state
	if state == "stopping" or state == "finished" or state == "destroyed" then
		return
	end
	if state == "idle" then
		self:_finish()
		return
	end
	self._epoch += 1
	for _, plan in self._plans do
		local ok, err = pcall(plan.controller.release :: any, plan.controller)
		if not ok then
			warn("[AstraVFX] releasing component " .. plan.component.id .. " failed: " .. tostring(err))
		end
	end
	self.state = "stopping"
	self._runtime = {}
	self._stopElapsed = 0
	self._stopLinger = if fade ~= nil then fade else self._tailLimit
	if self._stopLinger <= 0 then
		self:_finish()
	end
end

-- Immediate end: the copy goes to options.release or is destroyed. Idempotent.
function Player.destroy(self: Player)
	if self.state == "destroyed" then
		return
	end
	local wasFinished = self.state == "finished"
	self._epoch += 1
	self.state = "destroyed"
	self._runtime = {}
	self:_dispose()
	if not wasFinished then
		dispatch(self.finished, "destroyed")
	end
	self:_disconnect()
end

-- Multiplier on top of the definition's timeScale (0 freezes; clamped to Constants.MAX_TIME_SCALE).
function Player.setTimeScale(self: Player, n: number)
	if not isFinite(n) or n < 0 then
		error("Player.setTimeScale: expected a finite number >= 0, got " .. describe(n), 2)
	end
	self._timeScale = math.min(n, MAX_TIME_SCALE)
	self._rate = self._timeScale * self.compiled.timeScale
end

-- Moves the effect origin to a fixed CFrame (stops following an attach target; the offset still applies).
function Player.setCFrame(self: Player, cf: CFrame)
	if typeof(cf) ~= "CFrame" then
		error("Player.setCFrame: expected a CFrame, got " .. describe(cf), 2)
	end
	self._attach = nil
	self._base = cf
end

function Player.setLoop(self: Player, loop: boolean)
	if type(loop) ~= "boolean" then
		error("Player.setLoop: expected a boolean, got " .. describe(loop), 2)
	end
	self._loop = loop
end

-- Runtime graph trigger OnEvent(name) at the current effect time.
function Player.fire(self: Player, name: string)
	if type(name) ~= "string" then
		error("Player.fire: event name must be a string, got " .. describe(name), 2)
	end
	if self.state ~= "playing" and self.state ~= "paused" then
		return
	end
	local graph = self.compiled.graph
	if graph == nil then
		return
	end
	local list, info =
		Graph.run(graph, { kind = "event", id = name }, self.time, self.compiled.seed, self.cycle, self.compiled)
	if info.truncated then
		warn("[AstraVFX] graph event " .. name .. " was cut off after " .. tostring(info.actions) .. " actions")
	end
	local runtime = self._runtime
	for _, action in ipairs(list) do
		-- stable insert by time (after existing actions with the same time)
		local lo, hi = 1, #runtime + 1
		while lo < hi do
			local mid = (lo + hi) // 2
			if runtime[mid].time <= action.time then
				lo = mid + 1
			else
				hi = mid
			end
		end
		table.insert(runtime, lo, action)
	end
end

-- The current world CFrame of the effect origin (after attach / offset).
function Player.getRootCFrame(self: Player): CFrame
	return self:_resolveRoot()
end

-- True while the copy's instances exist (not yet released / destroyed).
function Player.isAlive(self: Player): boolean
	return not self._disposed and self.state ~= "destroyed"
end

-- Number of part moves sent with the last BulkMoveTo (diagnostics).
function Player.lastMoveCount(self: Player): number
	return self._moves
end

return Player
