--!strict
--[[
	Graph.Runner — compiles a GraphDef into a CompiledGraph and unrolls trigger flows into ScheduledActions on the
	effect timeline (docs/MODULE_CONTRACTS.md §11, ARCHITECTURE §6). No threads, no yields, no recursion.

	compile(graph, def) never throws. It expects a validated graph, but on malformed input it simply drops what it
	cannot use: nodes without a valid unique id or with an unknown type, links whose refs / pins / directions /
	kinds are invalid, self links, and every link inside a cycle (exec and data; so run() can never loop).
	When an exec output has several links only the first (in link order) is used; when a data input has several
	links only the first is used. Params are canonicalised with Codec.normalize (clamped);
	invalid params fall back to their defaults; easing is resolved with Easing.parse (invalid -> Linear).

	run(compiled, trigger, startTime, seed, cycle, effect?) -> (ActionList, RunInfo)
	  * Roots: every OnPlay node ("play"), every OnMarker whose marker == trigger.id ("marker"), every OnEvent
	    whose name == trigger.id ("event"), in node order; their "out" fires at startTime. A non-finite startTime
	    means 0, or the marker's time for marker triggers. (Graph.staticSchedule runs play at 0 and every marker
	    at its time.)
	  * Unrolling uses an explicit priority queue ordered by (time, LIFO among equal times): flows are processed
	    in time order, and at equal times depth-first in pin order (out1 before out2, iteration 0 before 1, a
	    Tween's "out" flow before "done" at duration 0, all Loop bodies before "completed" at interval 0).
	    The returned actions are therefore sorted by time; `order` is the 1-based emission index.
	  * Delay(seconds): out at t + seconds. Sequence(count, interval): then_i at t + (i - 1) * interval.
	    Parallel(count): out_i at t. Loop(count, interval): body at t + i * interval for i = 0..count-1, each in
	    a child context where Loop.index = i; completed at t + count * interval in the caller's context.
	    RandomBranch(count, weight_i): one out_i (weights >= 0; all zero = uniform).
	  * Data (pull-based, memoised per context): a context is the trigger run, and every Loop iteration opens a
	    child context (fresh memo, index bound). Within a context every data node is evaluated at most once, so
	    all consumers see the same value (e.g. one RandomNumber shared by Emit.count and Delay.seconds); a new
	    iteration gets new values. Loop.index read outside the loop's body is 0. (Data cycles cannot occur:
	    compile() drops them; the evaluator would also fall back to the param on a cycle.)
	  * Unlinked data inputs fall back to the param with the same name, then the param default (a linked
	    target that yields an empty component id also falls back to the target param). Numbers coming
	    through links are clamped to the param's declared range (integers rounded); non-finite values use the
	    param. Math results that are not finite (div by 0, pow of a negative base) are 0.
	  * Random values are deterministic per (seed, cycle, trigger, node id, invocation index): every evaluation of
	    a RandomNumber and every execution of a RandomBranch uses Random.new(Random.hash(seed, cycle, trigger key,
	    node id, n)) with n counting that node's invocations in this run. The trigger key ("play",
	    "marker:<id>", "event:<name>@<startTime>") keeps flows of different triggers (and repeated event fires at
	    different times) independent. Including the trigger is an extension of the contract's key.
	  * Actions (ScheduledAction, source = "graph", sourceId = node id):
	      Emit        action "emit", componentId, count (rounded, clamped 0..MAX_EMIT_COUNT; × countScale of
	                  effect.quality when an effect is given, min 1; 0 emits nothing)
	      SetEnabled  action "enable" | "disable", componentId
	      Tween       action "tween", componentId, channel, value (decoded), duration, easing (EasingFn)
	      SetProperty action "set", componentId, channel, value (decoded)
	      FireEvent   action "fire", name
	      PlaySound   action "play", componentId ; Regenerate action "regenerate", componentId
	    The flow always continues through action nodes, but the action itself is skipped when the target is
	    empty, does not exist (effect.byId when an effect is given — e.g. removed by minQuality — else the
	    definition's components), has a type the pin does not allow, when the event name is invalid, or when a
	    channel value cannot be decoded for the channel's kind (no implicit conversions).
	  * Channel values: decoded with Codec.decode against Components.channelSpec(target type, channel) (clamped
	    to its min/max; colours resolve "$palette" keys through effect.palette, else the definition's palette).
	    "length" channels are multiplied by effect.scale. With an unregistered target type the kind is inferred
	    from the value (number, boolean, colour string, [x, y, z]). A missing value param means the kind's zero
	    (0, [0, 0, 0], "#FFFFFF", false).
	  * Limits: at most Constants.MAX_GRAPH_ACTIONS actions per run, a work budget (queued flows + node
	    evaluations, Runner.MAX_WORK) and at most Runner.MAX_PENDING queued flows at once. Hitting any of them
	    stops unrolling; the list keeps the actions produced so far (the earliest ones, since flows run in time
	    order) and is flagged as truncated.
	  * Result: the list is a plain array of ScheduledActions; its `truncated` flag is readable as list.truncated
	    (provided through a metatable, so `for _, action in list` / ipairs / # only ever see actions). The second
	    return value is a RunInfo { truncated, actions, work, diagnostics } where diagnostics holds a
	    "graph.action_limit" warning when truncated.
]]

local Codec = require(script.Parent.Parent.Codec)
local Components = require(script.Parent.Parent.Components)
local Constants = require(script.Parent.Parent.Constants)
local Easing = require(script.Parent.Parent.Easing)
local Model = require(script.Parent.Model)
local NodeTypes = require(script.Parent.NodeTypes)
local Random = require(script.Parent.Parent.Random)
local Types = require(script.Parent.Parent.Types)

type ScheduledAction = Types.ScheduledAction
type Diagnostic = Types.Diagnostic
type EasingFn = Types.EasingFn
type ChannelSpec = Types.ChannelSpec
type PropertySpec = Types.PropertySpec
type CompiledEffect = Types.CompiledEffect
type NodeType = NodeTypes.NodeType
type Pin = NodeTypes.Pin

export type PinRef = { node: string, pin: string }

export type CompiledNode = {
	id: string,
	type: string,
	nodeType: NodeType,
	index: number, -- position in graph.nodes
	params: { [string]: any }, -- canonical JSON values of every declared param (defaults filled in)
	constants: { [string]: any }, -- decoded param values (all kinds except colours, which need the palette)
	execOut: { [string]: PinRef }, -- exec output pin -> target exec input
	dataIn: { [string]: PinRef }, -- data input pin -> source output
	count: number?, -- active variadic outputs (Sequence / Parallel / RandomBranch)
	weights: { number }?, -- RandomBranch weights for out1..outN
	easing: EasingFn?, -- Tween
	channelSpec: ChannelSpec?, -- Tween / SetProperty with a statically known target
}

export type Triggers = {
	play: { string },
	marker: { [string]: { string } },
	event: { [string]: { string } },
}

export type CompiledGraph = {
	nodes: { [string]: CompiledNode },
	order: { string }, -- node ids in definition order
	triggers: Triggers, -- trigger node ids by kind / marker id / event name
	markerTimes: { [string]: number },
	components: { [string]: string }, -- component id -> type (from the definition)
	palette: { [string]: Color3 }, -- decoded definition palette
}

export type Trigger = { kind: "play" | "marker" | "event", id: string? }

export type ActionList = { [number]: ScheduledAction, truncated: boolean }

export type RunInfo = {
	truncated: boolean,
	actions: number,
	work: number,
	diagnostics: { Diagnostic },
}

local Runner = {}

-- Upper bound for queued flows + node evaluations per run. compile() removes cycles, so only pathological
-- nesting (e.g. four nested 100-iteration loops without actions) can reach it; a 100 x 100 loop grid with a
-- 15-node data chain per action stays below it.
Runner.MAX_WORK = 200000
-- Upper bound for flows waiting in the queue at the same time (bounds memory for wide nesting).
Runner.MAX_PENDING = 50000

local MAX_ACTIONS = Constants.MAX_GRAPH_ACTIONS
local INF = math.huge
local floor = math.floor

local COMPLETE_META: any = table.freeze({ __index = table.freeze({ truncated = false }) })
local TRUNCATED_META: any = table.freeze({ __index = table.freeze({ truncated = true }) })
local NO_WEIGHTS: { number } = table.freeze({})

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

-- ─────────────────────────────────────────────────────────────────────────────
-- compile
-- ─────────────────────────────────────────────────────────────────────────────

local function decodePalette(def: any): { [string]: Color3 }
	local palette: { [string]: Color3 } = {}
	if type(def) ~= "table" or type(def.palette) ~= "table" then
		return palette
	end
	for key, value in pairs(def.palette) do
		if type(key) == "string" then
			local color = Codec.parseColor(value)
			if color then
				palette[key] = color
			end
		end
	end
	return palette
end

local function normalizeParam(nodeType: NodeType, spec: PropertySpec, raw: any): any
	local special = nodeType.special[spec.name]
	if special == "easing" then
		if raw ~= nil and Easing.check(raw) then
			return Easing.normalize(raw)
		end
		return spec.default
	elseif special == "channelValue" then
		return raw -- kind depends on the target channel: decoded per action
	elseif special == "marker" or special == "eventName" or special == "channel" then
		return if type(raw) == "string" then raw else spec.default
	end
	if raw ~= nil then
		local ok, value = pcall(Codec.normalize, spec.kind, raw, spec)
		if ok then
			return value
		end
	end
	return Codec.default(spec)
end

local function decodeConstant(spec: PropertySpec, value: any): any
	if value == nil or spec.kind == "color3" then
		return nil
	end
	local ok, decoded = pcall(Codec.decode, spec.kind, value, spec)
	return if ok then decoded else nil
end

-- Compiles a graph for an effect definition. Never throws; see the module header for malformed input.
function Runner.compile(graph: any, def: any): CompiledGraph
	local index = Model.index(graph)
	local components = Model.components(def)
	local compiled: CompiledGraph = {
		nodes = {},
		order = {},
		triggers = { play = {}, marker = {}, event = {} },
		markerTimes = Model.markers(def),
		components = components,
		palette = decodePalette(def),
	}

	for _, id in index.order do
		local entry = index.nodes[id]
		local nodeType = entry.nodeType
		if nodeType == nil then
			continue
		end
		local params: { [string]: any } = {}
		local constants: { [string]: any } = {}
		for _, spec in nodeType.params do
			local value = normalizeParam(nodeType, spec, entry.params[spec.name])
			params[spec.name] = value
			if nodeType.special[spec.name] == nil then
				constants[spec.name] = decodeConstant(spec, value)
			end
		end
		local node: CompiledNode = {
			id = id,
			type = nodeType.type,
			nodeType = nodeType,
			index = entry.index,
			params = params,
			constants = constants,
			execOut = {},
			dataIn = {},
			count = NodeTypes.count(nodeType, params),
			weights = nil,
			easing = nil,
			channelSpec = nil,
		}
		if nodeType.type == "RandomBranch" then
			local weights = {}
			for i = 1, node.count or 0 do
				local w = constants["weight" .. i]
				weights[i] = if finite(w) and w > 0 then w else 0
			end
			node.weights = weights
		end
		if nodeType.special.easing == "easing" then
			local ok, fn = (pcall :: any)(Easing.parse, params.easing)
			node.easing = if ok then fn else (Easing.parse(nil))
		end
		if nodeType.special.channel == "channel" then
			node.channelSpec = Model.channelSpec(index, components, entry)
		end
		compiled.nodes[id] = node
		table.insert(compiled.order, id)

		local trigger = nodeType.trigger
		if trigger == "play" then
			table.insert(compiled.triggers.play, id)
		elseif trigger == "marker" or trigger == "event" then
			local key = if trigger == "marker" then params.marker else params.name
			if type(key) == "string" and key ~= "" then
				local byKey = compiled.triggers[trigger] :: { [string]: { string } }
				local list = byKey[key]
				if list == nil then
					list = {}
					byKey[key] = list
				end
				table.insert(list, id)
			end
		end
	end

	-- Links: only structurally valid ones; first link wins per exec output / data input.
	for _, link in index.links do
		local src = index.nodes[link.fromNode]
		local dst = index.nodes[link.toNode]
		local srcNode = compiled.nodes[link.fromNode]
		local dstNode = compiled.nodes[link.toNode]
		if src == nil or dst == nil or srcNode == nil or dstNode == nil or link.fromNode == link.toNode then
			continue
		end
		local fromPin, fromDir, fromActive = Model.pin(src, link.fromPin)
		local toPin, toDir = Model.pin(dst, link.toPin)
		if fromPin == nil or toPin == nil or fromDir ~= "output" or toDir ~= "input" or not fromActive then
			continue
		end
		local fromKind = Model.pinKind(index, components, src, fromPin)
		local toKind = Model.pinKind(index, components, dst, toPin)
		if not Model.kindsCompatible(fromKind, toKind) then
			continue
		end
		if fromKind == "exec" then
			if srcNode.execOut[link.fromPin] == nil then
				srcNode.execOut[link.fromPin] = { node = link.toNode, pin = link.toPin }
			end
		elseif dstNode.dataIn[link.toPin] == nil then
			dstNode.dataIn[link.toPin] = { node = link.fromNode, pin = link.fromPin }
		end
	end

	-- Unvalidated input only: drop every compiled link inside a cycle (exec or data), so run() never sees one.
	local adjacency: Model.Adjacency = {}
	for _, id in compiled.order do
		adjacency[id] = {}
	end
	for _, id in compiled.order do
		local node = compiled.nodes[id]
		for _, ref in node.execOut do
			table.insert(adjacency[id], { to = ref.node, link = 0 })
		end
		for _, ref in node.dataIn do
			table.insert(adjacency[ref.node], { to = id, link = 0 })
		end
	end
	for _, group in Model.stronglyConnected(compiled.order, adjacency) do
		if #group > 1 then
			local members: { [string]: boolean } = {}
			for _, id in group do
				members[id] = true
			end
			for _, id in group do
				local node = compiled.nodes[id]
				for pin, ref in node.execOut do
					if members[ref.node] then
						node.execOut[pin] = nil
					end
				end
				for pin, ref in node.dataIn do
					if members[ref.node] then
						node.dataIn[pin] = nil
					end
				end
			end
		end
	end
	return compiled
end

-- ─────────────────────────────────────────────────────────────────────────────
-- run: state, queue, contexts
-- ─────────────────────────────────────────────────────────────────────────────

type Context = {
	parent: Context?,
	loop: string?, -- Loop node id whose iteration this context is
	index: number,
	memo: { [string]: any }, -- node id -> outputs table | IN_PROGRESS
}

type Item = { time: number, seq: number, node: string, ctx: Context }

type State = {
	compiled: CompiledGraph,
	seed: number,
	cycle: number,
	triggerKey: string,
	palette: { [string]: Color3 },
	byId: { [string]: any }?, -- effect.byId when an effect is given
	countScale: number?,
	scale: number,
	actions: { ScheduledAction },
	truncated: boolean,
	stopped: boolean,
	work: number,
	seq: number,
	heap: { Item },
	invocations: { [string]: number },
	colorCache: { [string]: Color3 },
}

local IN_PROGRESS = table.freeze({})

-- Spends one unit of the work budget; false (and truncation) when it is exhausted.
local function spend(state: State): boolean
	if state.stopped then
		return false
	end
	state.work += 1
	if state.work > Runner.MAX_WORK then
		state.truncated = true
		state.stopped = true
		return false
	end
	return true
end

-- a before b: earlier time, or the later push at equal times (LIFO => depth-first among equal times).
local function before(a: Item, b: Item): boolean
	if a.time ~= b.time then
		return a.time < b.time
	end
	return a.seq > b.seq
end

local function heapPush(heap: { Item }, item: Item)
	table.insert(heap, item)
	local i = #heap
	while i > 1 do
		local parent = i // 2
		if before(heap[i], heap[parent]) then
			heap[i], heap[parent] = heap[parent], heap[i]
			i = parent
		else
			break
		end
	end
end

local function heapPop(heap: { Item }): Item?
	local n = #heap
	if n == 0 then
		return nil
	end
	local top = heap[1]
	heap[1] = heap[n]
	heap[n] = nil
	n -= 1
	local i = 1
	while true do
		local l, r = 2 * i, 2 * i + 1
		local best = i
		if l <= n and before(heap[l], heap[best]) then
			best = l
		end
		if r <= n and before(heap[r], heap[best]) then
			best = r
		end
		if best == i then
			break
		end
		heap[i], heap[best] = heap[best], heap[i]
		i = best
	end
	return top
end

-- Queues the flow linked to `node.pin` at `time` (no-op when the output is not linked).
local function fire(state: State, node: CompiledNode, pin: string, time: number, ctx: Context)
	local target = node.execOut[pin]
	if target == nil or not spend(state) then
		return
	end
	if #state.heap >= Runner.MAX_PENDING then
		state.truncated = true
		state.stopped = true
		return
	end
	state.seq += 1
	heapPush(state.heap, { time = time, seq = state.seq, node = target.node, ctx = ctx })
end

local function nextInvocation(state: State, nodeId: string): number
	local n = state.invocations[nodeId] or 0
	state.invocations[nodeId] = n + 1
	return n
end

local function rngFor(state: State, nodeId: string)
	local n = nextInvocation(state, nodeId)
	return Random.new(Random.hash(state.seed, state.cycle, state.triggerKey, nodeId, n))
end

local function loopIndex(ctx: Context?, loopId: string): number
	local c = ctx
	while c do
		if c.loop == loopId then
			return c.index
		end
		c = c.parent
	end
	return 0
end

-- Decoded colour param (palette-aware, cached per run).
local function colorParam(state: State, node: CompiledNode, name: string): Color3?
	local key = node.id .. "." .. name
	local cached = state.colorCache[key]
	if cached then
		return cached
	end
	local spec = NodeTypes.paramSpec(node.nodeType, name)
	local value = node.params[name]
	if spec == nil or value == nil then
		return nil
	end
	local ok, color = pcall(Codec.decode, "color3", value, spec, state.palette)
	if not ok then
		ok, color = pcall(Codec.decode, "color3", spec.default, spec, state.palette)
	end
	if ok and typeof(color) == "Color3" then
		state.colorCache[key] = color
		return color
	end
	return nil
end

-- Param fallback value of a data input (decoded).
local function paramValue(state: State, node: CompiledNode, name: string): any
	local constant = node.constants[name]
	if constant ~= nil then
		return constant
	end
	local spec = NodeTypes.paramSpec(node.nodeType, name)
	if spec and spec.kind == "color3" then
		return colorParam(state, node, name)
	end
	return nil
end

-- Value of a linked source in a context, or nil when unavailable (not evaluated / cycle / unknown source).
local function linkedValue(state: State, ctx: Context, ref: PinRef): any
	local source = state.compiled.nodes[ref.node]
	if source == nil then
		return nil
	end
	if source.type == "Loop" and ref.pin == "index" then
		return loopIndex(ctx, source.id)
	end
	local outputs = ctx.memo[source.id]
	if type(outputs) ~= "table" or outputs == IN_PROGRESS then
		return nil
	end
	return outputs[ref.pin]
end

local function number(x: any, fallback: number): number
	return if finite(x) then x else fallback
end

-- Clamps a number to a param's declared range (integers rounded); non-finite -> the param's value.
local function sanitize(node: CompiledNode, name: string, value: any): number
	local spec = NodeTypes.paramSpec(node.nodeType, name)
	local fallback = node.constants[name]
	local v = number(value, number(fallback, if spec then number(spec.default, 0) else 0))
	if spec then
		if spec.kind == "integer" then
			v = floor(v + 0.5)
		end
		if spec.min and v < spec.min then
			v = spec.min
		end
		if spec.max and v > spec.max then
			v = spec.max
		end
	end
	return v
end

local function computeMath(op: any, a: number, b: number, t: number): number
	local r: number
	if op == "add" then
		r = a + b
	elseif op == "sub" then
		r = a - b
	elseif op == "mul" then
		r = a * b
	elseif op == "div" then
		r = if b == 0 then 0 else a / b
	elseif op == "min" then
		r = math.min(a, b)
	elseif op == "max" then
		r = math.max(a, b)
	elseif op == "pow" then
		r = a ^ b
	elseif op == "lerp" then
		r = a + (b - a) * t
	else
		r = 0 -- unreachable for compiled graphs: compile() replaces invalid ops by the default "add"
	end
	return if finite(r) then r else 0
end

-- Outputs of a pure node whose inputs are all available in ctx.memo.
local function compute(state: State, ctx: Context, node: CompiledNode): { [string]: any }
	local function input(name: string): any
		local ref = node.dataIn[name]
		if ref then
			local v = linkedValue(state, ctx, ref)
			if v ~= nil then
				return v
			end
		end
		return paramValue(state, node, name)
	end
	local kind = node.type
	if kind == "Number" then
		return { value = number(node.constants.value, 0) }
	elseif kind == "Vector" then
		local v = node.constants.value
		return { value = if typeof(v) == "Vector3" then v else Vector3.zero }
	elseif kind == "Color" then
		return { value = colorParam(state, node, "value") or Color3.new(1, 1, 1) }
	elseif kind == "Component" then
		local id = node.params.component
		return { component = if type(id) == "string" then id else "" }
	elseif kind == "RandomNumber" then
		local min = number(input("min"), 0)
		local max = number(input("max"), 1)
		local rng = rngFor(state, node.id)
		return { value = number(rng:range(min, max), min) }
	elseif kind == "Math" then
		local a = number(input("a"), 0)
		local b = number(input("b"), 0)
		local t = number(input("t"), 0)
		return { result = computeMath(node.params.op, a, b, t) }
	end
	return {}
end

-- Evaluates a pure node (and, iteratively, its pure dependencies) in a context. Returns its outputs or nil.
local function evaluate(state: State, ctx: Context, rootId: string): { [string]: any }?
	local memo = ctx.memo
	local existing = memo[rootId]
	if existing ~= nil then
		return if existing == IN_PROGRESS then nil else existing
	end
	local nodes = state.compiled.nodes
	local stack: { string } = { rootId }
	memo[rootId] = IN_PROGRESS
	while #stack > 0 do
		local id = stack[#stack]
		local node = nodes[id]
		local pending: string? = nil
		for _, pin in node.nodeType.inputs do
			local ref = node.dataIn[pin.name]
			if ref then
				local source = nodes[ref.node]
				if source and source.nodeType.pure and memo[ref.node] == nil then
					pending = ref.node
					break
				end
			end
		end
		if pending then
			if not spend(state) then
				break
			end
			memo[pending] = IN_PROGRESS
			table.insert(stack, pending)
		else
			table.remove(stack)
			if not spend(state) then
				break
			end
			memo[id] = compute(state, ctx, node)
		end
	end
	-- Budget exhausted mid-way: leave nothing half-evaluated behind.
	for _, id in stack do
		if memo[id] == IN_PROGRESS then
			memo[id] = nil
		end
	end
	local result = memo[rootId]
	return if type(result) == "table" and result ~= IN_PROGRESS then result else nil
end

-- Decoded value of a data input of an exec node in a context (link, then param).
local function inputValue(state: State, ctx: Context, node: CompiledNode, name: string): any
	local ref = node.dataIn[name]
	if ref then
		local source = state.compiled.nodes[ref.node]
		if source and source.nodeType.pure then
			evaluate(state, ctx, source.id)
		end
		local v = linkedValue(state, ctx, ref)
		if v ~= nil then
			return v
		end
	end
	return paramValue(state, node, name)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- run: actions
-- ─────────────────────────────────────────────────────────────────────────────

local function addAction(state: State, node: CompiledNode, time: number, action: { [string]: any }): boolean
	if state.stopped then
		return false
	end
	if #state.actions >= MAX_ACTIONS then
		state.truncated = true
		state.stopped = true
		return false
	end
	action.time = time
	action.source = "graph"
	action.sourceId = node.id
	action.order = #state.actions + 1
	table.insert(state.actions, action :: any)
	return true
end

local function componentType(state: State, id: string): string?
	local byId = state.byId
	if byId then
		local component = byId[id]
		return if type(component) == "table" and type(component.type) == "string" then component.type else nil
	end
	return state.compiled.components[id]
end

-- Target component id of an action node if it exists and has an allowed type, else nil.
local function resolveTarget(state: State, ctx: Context, node: CompiledNode): (string?, string?)
	local id = inputValue(state, ctx, node, "target")
	if type(id) ~= "string" or id == "" then
		id = node.params.target
	end
	if type(id) ~= "string" or id == "" then
		return nil, nil
	end
	local kind = componentType(state, id)
	if kind == nil then
		return nil, nil
	end
	local pin = NodeTypes.findPin(node.nodeType, node.params, "target")
	local allowed = if pin then pin.componentTypes else nil
	if allowed and not table.find(allowed, kind) then
		return nil, nil
	end
	return id, kind
end

local function decodedKind(v: any): string?
	local t = typeof(v)
	if t == "number" then
		return if finite(v) then "number" else nil
	elseif t == "Vector3" then
		return "vector3"
	elseif t == "Color3" then
		return "color3"
	elseif t == "boolean" then
		return "boolean"
	end
	return nil
end

local function jsonKind(v: any): string?
	if type(v) == "number" then
		return if finite(v) then "number" else nil
	elseif type(v) == "boolean" then
		return "boolean"
	elseif type(v) == "string" then
		return "color3"
	elseif type(v) == "table" then
		return "vector3"
	end
	return nil
end

local ZERO: { [string]: any } = { number = 0, vector3 = { 0, 0, 0 }, color3 = "#FFFFFF", boolean = false }

-- Decoded, scaled channel value for a Tween / SetProperty action, or nil when it cannot be produced.
local function channelValue(state: State, ctx: Context, node: CompiledNode, spec: ChannelSpec?): any
	local decoded: any = nil
	local ref = node.dataIn.value
	local linked: any = nil
	if ref then
		local source = state.compiled.nodes[ref.node]
		if source and source.nodeType.pure then
			evaluate(state, ctx, source.id)
		end
		linked = linkedValue(state, ctx, ref)
	end
	if linked ~= nil then
		local kind = decodedKind(linked)
		if kind == nil or (spec and spec.kind ~= kind) then
			return nil -- no implicit conversions
		end
		local ok, v = pcall(Codec.decode, kind, linked, spec)
		decoded = if ok then v else nil
	else
		local raw = node.params.value
		local kind = if spec then spec.kind else jsonKind(raw)
		if kind == nil then
			return nil
		end
		if raw == nil then
			raw = ZERO[kind]
		end
		local ok, v = pcall(Codec.decode, kind, raw, spec, state.palette)
		decoded = if ok then v else nil
	end
	if decoded ~= nil and spec and spec.scale == "length" and state.scale ~= 1 then
		if type(decoded) == "number" or typeof(decoded) == "Vector3" then
			decoded = (decoded :: any) * state.scale
		end
	end
	return decoded
end

local function runAction(state: State, item: Item, node: CompiledNode)
	local ctx = item.ctx
	local t = item.time
	local kind = node.type
	if kind == "FireEvent" then
		local name = inputValue(state, ctx, node, "name")
		if type(name) ~= "string" or name == "" then
			name = node.params.name
		end
		if
			type(name) == "string"
			and #name <= Constants.ID_MAX_LENGTH
			and string.match(name, Constants.EVENT_NAME_PATTERN)
		then
			if not addAction(state, node, t, { action = "fire", name = name }) then
				return
			end
		end
		fire(state, node, "out", t, ctx)
		return
	end

	local target, targetType = resolveTarget(state, ctx, node)
	if kind == "Emit" then
		if target then
			local count = sanitize(node, "count", inputValue(state, ctx, node, "count"))
			local countScale = state.countScale
			if countScale and count > 0 then
				count = math.max(1, floor(count * countScale + 0.5))
			end
			if
				count > 0 and not addAction(state, node, t, { action = "emit", componentId = target, count = count })
			then
				return
			end
		end
		fire(state, node, "out", t, ctx)
	elseif kind == "SetEnabled" then
		if target then
			local enabled = inputValue(state, ctx, node, "enabled")
			if type(enabled) ~= "boolean" then
				enabled = node.constants.enabled ~= false
			end
			local action = if enabled then "enable" else "disable"
			if not addAction(state, node, t, { action = action, componentId = target }) then
				return
			end
		end
		fire(state, node, "out", t, ctx)
	elseif kind == "Tween" or kind == "SetProperty" then
		local channel = node.params.channel
		local duration = 0
		if kind == "Tween" then
			duration = sanitize(node, "duration", inputValue(state, ctx, node, "duration"))
		end
		if target and type(channel) == "string" and channel ~= "" then
			local spec = Components.channelSpec(targetType :: string, channel)
			local value = channelValue(state, ctx, node, spec)
			if value ~= nil then
				local action: { [string]: any } = { componentId = target, channel = channel, value = value }
				if kind == "Tween" then
					action.action = "tween"
					action.duration = duration
					action.easing = node.easing
				else
					action.action = "set"
				end
				if not addAction(state, node, t, action) then
					return
				end
			end
		end
		if kind == "Tween" then
			fire(state, node, "done", t + duration, ctx)
		end
		fire(state, node, "out", t, ctx)
	elseif kind == "PlaySound" or kind == "Regenerate" then
		if target then
			if not addAction(state, node, t, { action = node.nodeType.action, componentId = target }) then
				return
			end
		end
		fire(state, node, "out", t, ctx)
	end
end

local function process(state: State, item: Item)
	local node = state.compiled.nodes[item.node]
	if node == nil then
		return
	end
	local kind = node.type
	local t = item.time
	local ctx = item.ctx
	if node.nodeType.action then
		runAction(state, item, node)
	elseif kind == "Delay" then
		local seconds = sanitize(node, "seconds", inputValue(state, ctx, node, "seconds"))
		fire(state, node, "out", t + seconds, ctx)
	elseif kind == "Sequence" then
		local interval = sanitize(node, "interval", inputValue(state, ctx, node, "interval"))
		for i = node.count or 0, 1, -1 do
			fire(state, node, "then" .. i, t + (i - 1) * interval, ctx)
		end
	elseif kind == "Parallel" then
		for i = node.count or 0, 1, -1 do
			fire(state, node, "out" .. i, t, ctx)
		end
	elseif kind == "Loop" then
		local count = sanitize(node, "count", inputValue(state, ctx, node, "count"))
		local interval = sanitize(node, "interval", inputValue(state, ctx, node, "interval"))
		fire(state, node, "completed", t + count * interval, ctx)
		if node.execOut.body then
			for i = count - 1, 0, -1 do
				if state.stopped then
					break
				end
				local child: Context = { parent = ctx, loop = node.id, index = i, memo = {} }
				fire(state, node, "body", t + i * interval, child)
			end
		end
	elseif kind == "RandomBranch" then
		local weights = node.weights or NO_WEIGHTS
		local n = #weights
		if n > 0 then
			local total = 0
			for _, w in weights do
				total += w
			end
			local rng = rngFor(state, node.id)
			local r = rng:next()
			local chosen = n
			if total <= 0 then
				chosen = math.min(n, floor(r * n) + 1)
			else
				local target = r * total
				local acc = 0
				for i, w in weights do
					acc += w
					if target < acc then
						chosen = i
						break
					end
				end
			end
			fire(state, node, "out" .. chosen, t, ctx)
		end
	end
end

local function triggerRoots(compiled: CompiledGraph, kind: string, id: any): { string }
	if kind == "play" then
		return compiled.triggers.play
	elseif kind == "marker" then
		return if type(id) == "string" then compiled.triggers.marker[id] or {} else {}
	elseif kind == "event" then
		return if type(id) == "string" then compiled.triggers.event[id] or {} else {}
	end
	error("Graph.run: unknown trigger kind " .. Model.describe(kind) .. ' (expected "play", "marker" or "event")', 3)
end

-- Unrolls the flows of one trigger into scheduled actions (sorted by time). See the module header.
function Runner.run(
	compiled: CompiledGraph,
	trigger: Trigger,
	startTime: number,
	seed: number,
	cycle: number,
	effect: CompiledEffect?
): (ActionList, RunInfo)
	if type(compiled) ~= "table" or type((compiled :: any).nodes) ~= "table" then
		error("Graph.run: expected a CompiledGraph (from Graph.compile), got " .. typeof(compiled), 2)
	end
	if type(trigger) ~= "table" then
		error("Graph.run: trigger must be { kind = ..., id = ... }, got " .. typeof(trigger), 2)
	end
	local kind = trigger.kind
	local id = trigger.id
	local roots = triggerRoots(compiled, kind, id)

	local t0: number
	if finite(startTime) then
		t0 = startTime
	elseif kind == "marker" and type(id) == "string" and compiled.markerTimes[id] then
		t0 = compiled.markerTimes[id]
	else
		t0 = 0
	end
	local triggerKey = if kind == "play"
		then "play"
		elseif kind == "marker" then "marker:" .. tostring(id)
		else "event:" .. tostring(id) .. "@" .. tostring(t0)

	local fx: any = effect
	local palette = compiled.palette
	local byId = nil
	local countScale = nil
	local scale = 1
	if type(fx) == "table" then
		if type(fx.palette) == "table" then
			palette = fx.palette
		end
		if type(fx.byId) == "table" then
			byId = fx.byId
		end
		if type(fx.quality) == "table" and finite(fx.quality.countScale) and fx.quality.countScale >= 0 then
			countScale = fx.quality.countScale
		end
		if finite(fx.scale) and fx.scale > 0 then
			scale = fx.scale
		end
	end

	local state: State = {
		compiled = compiled,
		seed = if finite(seed) then seed else 0,
		cycle = if finite(cycle) then cycle else 0,
		triggerKey = triggerKey,
		palette = palette,
		byId = byId,
		countScale = countScale,
		scale = scale,
		actions = {},
		truncated = false,
		stopped = false,
		work = 0,
		seq = 0,
		heap = {},
		invocations = {},
		colorCache = {},
	}

	local rootCtx: Context = { parent = nil, loop = nil, index = 0, memo = {} }
	for i = #roots, 1, -1 do
		local node = compiled.nodes[roots[i]]
		if node then
			fire(state, node, "out", t0, rootCtx)
		end
	end
	while not state.stopped do
		local item = heapPop(state.heap)
		if item == nil then
			break
		end
		if not spend(state) then
			break
		end
		process(state, item)
	end

	local diagnostics: { Diagnostic } = {}
	if state.truncated then
		table.insert(diagnostics, {
			severity = "warning",
			code = "graph.action_limit",
			path = "graph",
			message = "graph unrolling stopped after "
				.. #state.actions
				.. " actions (limits per trigger: "
				.. MAX_ACTIONS
				.. " actions, "
				.. Runner.MAX_WORK
				.. " work units, "
				.. Runner.MAX_PENDING
				.. " queued flows)",
			hint = "reduce Loop counts or nesting",
		})
	end
	local list = setmetatable(state.actions, if state.truncated then TRUNCATED_META else COMPLETE_META) :: any
	local info: RunInfo = {
		truncated = state.truncated,
		actions = #state.actions,
		work = state.work,
		diagnostics = diagnostics,
	}
	return list :: ActionList, info
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Static schedule (play + markers)
-- ─────────────────────────────────────────────────────────────────────────────

type Tagged = { action: ScheduledAction, run: number }

-- Runs the "play" trigger at 0 and every marker trigger at its marker time (effect.markers when given, else the
-- definition's markers) and merges the actions sorted by (time, trigger order, order); `order` is renumbered
-- 1..n. Each trigger has its own action limit; the result is truncated if any run was.
function Runner.staticSchedule(
	compiled: CompiledGraph,
	seed: number,
	cycle: number,
	effect: CompiledEffect?
): (ActionList, RunInfo)
	local markers: { { id: string, time: number, position: number } } = {}
	local fx: any = effect
	local source: any = if type(fx) == "table" and type(fx.markers) == "table" then fx.markers else nil
	if source then
		local seen = {}
		for i, marker in ipairs(source) do
			if type(marker) == "table" and type(marker.id) == "string" and not seen[marker.id] then
				seen[marker.id] = true
				table.insert(markers, { id = marker.id, time = number(marker.time, 0), position = i })
			end
		end
	else
		for markerId, time in compiled.markerTimes do
			table.insert(markers, { id = markerId, time = time, position = 0 })
		end
	end
	table.sort(markers, function(a, b): boolean
		if a.time ~= b.time then
			return a.time < b.time
		elseif a.position ~= b.position then
			return a.position < b.position
		end
		return a.id < b.id
	end)

	local tagged: { Tagged } = {}
	local truncated = false
	local work = 0
	local diagnostics: { Diagnostic } = {}
	local function collect(runIndex: number, list: ActionList, info: RunInfo)
		for _, action in ipairs(list) do
			table.insert(tagged, { action = action, run = runIndex })
		end
		truncated = truncated or info.truncated
		work += info.work
		for _, d in info.diagnostics do
			table.insert(diagnostics, d)
		end
	end
	local playList, playInfo = Runner.run(compiled, { kind = "play" }, 0, seed, cycle, effect)
	collect(0, playList, playInfo)
	for i, marker in markers do
		if compiled.triggers.marker[marker.id] then
			local list, info =
				Runner.run(compiled, { kind = "marker", id = marker.id }, marker.time, seed, cycle, effect)
			collect(i, list, info)
		end
	end
	table.sort(tagged, function(a: Tagged, b: Tagged): boolean
		if a.action.time ~= b.action.time then
			return a.action.time < b.action.time
		elseif a.run ~= b.run then
			return a.run < b.run
		end
		return a.action.order < b.action.order
	end)
	local actions: { ScheduledAction } = {}
	for i, entry in tagged do
		entry.action.order = i
		actions[i] = entry.action
	end
	local list = setmetatable(actions, if truncated then TRUNCATED_META else COMPLETE_META) :: any
	return list :: ActionList, { truncated = truncated, actions = #actions, work = work, diagnostics = diagnostics }
end

-- Trigger summary of a compiled graph: whether OnPlay exists, marker ids and event names with flows (sorted).
function Runner.triggers(compiled: CompiledGraph): { play: boolean, markers: { string }, events: { string } }
	local markers, events = {}, {}
	for markerId in compiled.triggers.marker do
		table.insert(markers, markerId)
	end
	for name in compiled.triggers.event do
		table.insert(events, name)
	end
	table.sort(markers)
	table.sort(events)
	return { play = #compiled.triggers.play > 0, markers = markers, events = events }
end

return Runner
