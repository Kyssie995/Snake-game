--!strict
--[[
	Graph.NodeTypes — registry of node graph node types (docs/MODULE_CONTRACTS.md §11, ARCHITECTURE §6).

	Every node type declares typed pins and its parameters as PropertySpecs (built with Components.Common.prop, so
	Codec.check / Codec.normalize work on them directly and the Inspector can render them like component
	properties). Node types are frozen; never mutate them.

	Pin kinds: "exec" (control flow) and the data kinds "number", "vector3", "color3", "boolean", "string",
	"component" (a component id) and "any" (matches every data kind, never "exec").

	Conventions:
	  * Every non-trigger exec node has exactly one exec input named "in". Exec inputs accept many links; an exec
	    output accepts at most one (fan-out only through Parallel / Sequence).
	  * Data inputs fall back to the param with the same name when unlinked, then to that param's default.
	  * Variadic outputs (Sequence "then1..then8", Parallel / RandomBranch "out1..out8"): the node type lists all
	    eight pins; only the first `count` (param, 2..8) are active for a given node (NodeTypes.outputs).

	Extensions beyond the contract's NodeType shape (all read-only):
	  trigger   "play" | "marker" | "event" for OnPlay / OnMarker / OnEvent
	  action    ScheduledAction.action produced by action nodes ("emit", "enable", "tween", "set", "fire", "play",
	            "regenerate"); SetEnabled produces "enable" or "disable" depending on `enabled`
	  pure      true for data nodes (no exec pins, evaluated on demand)
	  variadic  { countParam, prefix, min, max } for count-dependent outputs
	  special   param name -> how the param is validated beyond Codec.check:
	              "easing"       Types.EasingDef (string or { bezier = {...} }), checked with Easing.check
	              "channel"      channel name declared by the target component type
	              "channelValue" JSON value whose kind follows the target channel's ChannelSpec
	              "marker"       id of a marker in the effect definition
	              "eventName"    event name (Constants.EVENT_NAME_PATTERN, at most Constants.ID_MAX_LENGTH chars)
	  The "value" param of Tween / SetProperty is declared with kind "number" and default nil as a placeholder;
	  its effective spec (kind and default) comes from the target channel (Graph.resolveParamSpec).
]]

local Common = require(script.Parent.Parent.Components.Common)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)

type PropertySpec = Types.PropertySpec

export type PinKind = "exec" | "number" | "vector3" | "color3" | "boolean" | "string" | "component" | "any"

export type Pin = {
	name: string,
	kind: PinKind,
	label: string?,
	description: string?,
	componentTypes: { string }?, -- component pins: allowed target component types (nil = any)
}

export type ParamSpecial = "easing" | "channel" | "channelValue" | "marker" | "eventName"

export type TriggerKind = "play" | "marker" | "event"

export type Variadic = {
	countParam: string,
	prefix: string,
	min: number,
	max: number,
}

export type NodeType = {
	type: string,
	displayName: string,
	category: string, -- "Triggers" | "Flow" | "Data" | "Math" | "Actions"
	description: string,
	inputs: { Pin },
	outputs: { Pin },
	params: { PropertySpec },
	trigger: TriggerKind?,
	action: string?,
	pure: boolean,
	variadic: Variadic?,
	special: { [string]: ParamSpecial },
}

export type PinDirection = "input" | "output"

local NodeTypes = {}

NodeTypes.CATEGORIES = { "Triggers", "Flow", "Data", "Math", "Actions" }
NodeTypes.PIN_KINDS = { "exec", "number", "vector3", "color3", "boolean", "string", "component", "any" }
NodeTypes.MAX_BRANCHES = 8
NodeTypes.MATH_OPS = { "add", "sub", "mul", "div", "min", "max", "pow", "lerp" }

local MAX_DURATION = Constants.MAX_DURATION
local MAX_BRANCHES = NodeTypes.MAX_BRANCHES

-- ─────────────────────────────────────────────────────────────────────────────
-- Builders
-- ─────────────────────────────────────────────────────────────────────────────

local function exec(name: string, label: string, description: string?): Pin
	return { name = name, kind = "exec", label = label, description = description }
end

local function data(name: string, kind: PinKind, label: string, description: string?, componentTypes: { string }?): Pin
	return { name = name, kind = kind, label = label, description = description, componentTypes = componentTypes }
end

local function prop(
	name: string,
	kind: Types.PropertyKind,
	default: any,
	description: string,
	options: any?
): PropertySpec
	return Common.prop(name, kind, default, description, options)
end

local function targetParam(componentTypes: { string }?): PropertySpec
	local what = if componentTypes then table.concat(componentTypes, "/") .. " component" else "component"
	return prop(
		"target",
		"componentRef",
		"",
		"Id of the " .. what .. " this node acts on (used when the target pin is not linked).",
		{ label = "Target", componentTypes = componentTypes }
	)
end

local function targetPin(componentTypes: { string }?): Pin
	return data("target", "component", "Target", "Component to act on (overrides the target param).", componentTypes)
end

local function countParam(default: number, description: string): PropertySpec
	return prop("count", "integer", default, description, { label = "Count", min = 2, max = MAX_BRANCHES, step = 1 })
end

local function numbered(prefix: string, label: string, description: string): { Pin }
	local pins = {}
	for i = 1, MAX_BRANCHES do
		table.insert(pins, exec(prefix .. i, label .. " " .. i, description))
	end
	return pins
end

local function deepFreeze(t: any): any
	if type(t) == "table" and not table.isfrozen(t) then
		for _, v in pairs(t) do
			deepFreeze(v)
		end
		table.freeze(t)
	end
	return t
end

type NodeTypeInit = {
	type: string,
	displayName: string,
	category: string,
	description: string,
	inputs: { Pin }?,
	outputs: { Pin }?,
	params: { PropertySpec }?,
	trigger: TriggerKind?,
	action: string?,
	pure: boolean?,
	variadic: Variadic?,
	special: { [string]: any }?,
}

local function define(init: NodeTypeInit): NodeType
	local nodeType: NodeType = {
		type = init.type,
		displayName = init.displayName,
		category = init.category,
		description = init.description,
		inputs = init.inputs or {},
		outputs = init.outputs or {},
		params = init.params or {},
		trigger = init.trigger,
		action = init.action,
		pure = init.pure == true,
		variadic = init.variadic,
		special = (init.special or {}) :: { [string]: ParamSpecial },
	}
	return nodeType
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Node types
-- ─────────────────────────────────────────────────────────────────────────────

local IN = exec("in", "In", "Runs this node.")
local OUT = exec("out", "Out", "Continues after this node.")

local branchParams: { PropertySpec } = { countParam(2, "Number of outputs (2..8).") }
for i = 1, MAX_BRANCHES do
	table.insert(
		branchParams,
		prop(
			"weight" .. i,
			"number",
			1,
			"Relative probability of output " .. i .. " (all zero = uniform).",
			{ label = "Weight " .. i, min = 0, max = 1000, step = 0.1 }
		)
	)
end

local definitions: { NodeType } = {
	-- Triggers ------------------------------------------------------------------------------------------------
	define({
		type = "OnPlay",
		displayName = "On Play",
		category = "Triggers",
		description = "Fires once when the effect starts (time 0 of every cycle).",
		outputs = { OUT },
		trigger = "play",
	}),
	define({
		type = "OnMarker",
		displayName = "On Marker",
		category = "Triggers",
		description = "Fires at the time of a timeline marker.",
		outputs = { OUT },
		params = { prop("marker", "string", "", "Id of the marker that triggers this flow.", { label = "Marker" }) },
		trigger = "marker",
		special = { marker = "marker" },
	}),
	define({
		type = "OnEvent",
		displayName = "On Event",
		category = "Triggers",
		description = "Fires when game code calls handle:Fire(name), at the current effect time.",
		outputs = { OUT },
		params = { prop("name", "string", "", "Event name passed to handle:Fire().", { label = "Event" }) },
		trigger = "event",
		special = { name = "eventName" },
	}),

	-- Flow ----------------------------------------------------------------------------------------------------
	define({
		type = "Delay",
		displayName = "Delay",
		category = "Flow",
		description = "Continues after a number of seconds.",
		inputs = { IN, data("seconds", "number", "Seconds") },
		outputs = { OUT },
		params = {
			prop("seconds", "number", 0.5, "Delay in seconds.", { label = "Seconds", min = 0, max = MAX_DURATION }),
		},
	}),
	define({
		type = "Sequence",
		displayName = "Sequence",
		category = "Flow",
		description = "Fires Then 1..N one after another, `interval` seconds apart.",
		inputs = { IN, data("interval", "number", "Interval") },
		outputs = numbered("then", "Then", "Fires at t + (i - 1) * interval."),
		params = {
			countParam(2, "Number of outputs (2..8)."),
			prop(
				"interval",
				"number",
				0.1,
				"Seconds between consecutive outputs.",
				{ label = "Interval", min = 0, max = MAX_DURATION }
			),
		},
		variadic = { countParam = "count", prefix = "then", min = 2, max = MAX_BRANCHES },
	}),
	define({
		type = "Parallel",
		displayName = "Parallel",
		category = "Flow",
		description = "Fires Out 1..N at the same time (the way to fan out an exec flow).",
		inputs = { IN },
		outputs = numbered("out", "Out", "Fires immediately."),
		params = { countParam(2, "Number of outputs (2..8).") },
		variadic = { countParam = "count", prefix = "out", min = 2, max = MAX_BRANCHES },
	}),
	define({
		type = "Loop",
		displayName = "Loop",
		category = "Flow",
		description = "Fires Body `count` times, `interval` seconds apart, then Completed.",
		inputs = { IN, data("count", "number", "Count"), data("interval", "number", "Interval") },
		outputs = {
			exec("body", "Body", "Fires once per iteration at t + index * interval."),
			exec("completed", "Completed", "Fires at t + count * interval."),
			data("index", "number", "Index", "Iteration index (0-based), valid inside the Body flow."),
		},
		params = {
			prop(
				"count",
				"integer",
				3,
				"Number of iterations.",
				{ label = "Count", min = 1, max = Constants.MAX_LOOP_ITERATIONS, step = 1 }
			),
			prop(
				"interval",
				"number",
				0.1,
				"Seconds between iterations.",
				{ label = "Interval", min = 0, max = MAX_DURATION }
			),
		},
	}),
	define({
		type = "RandomBranch",
		displayName = "Random Branch",
		category = "Flow",
		description = "Fires one of Out 1..N, chosen deterministically from the seed (optionally weighted).",
		inputs = { IN },
		outputs = numbered("out", "Out", "Fires when chosen."),
		params = branchParams,
		variadic = { countParam = "count", prefix = "out", min = 2, max = MAX_BRANCHES },
	}),

	-- Data ----------------------------------------------------------------------------------------------------
	define({
		type = "RandomNumber",
		displayName = "Random Number",
		category = "Data",
		description = "Deterministic random number in [min, max), new for every trigger and loop iteration.",
		inputs = { data("min", "number", "Min"), data("max", "number", "Max") },
		outputs = { data("value", "number", "Value") },
		params = {
			prop("min", "number", 0, "Lower bound (inclusive).", { label = "Min" }),
			prop("max", "number", 1, "Upper bound (exclusive).", { label = "Max" }),
		},
		pure = true,
	}),
	define({
		type = "Number",
		displayName = "Number",
		category = "Data",
		description = "A constant number.",
		outputs = { data("value", "number", "Value") },
		params = { prop("value", "number", 0, "The number.", { label = "Value" }) },
		pure = true,
	}),
	define({
		type = "Vector",
		displayName = "Vector",
		category = "Data",
		description = "A constant Vector3.",
		outputs = { data("value", "vector3", "Value") },
		params = { prop("value", "vector3", { 0, 0, 0 }, "The vector [x, y, z].", { label = "Value" }) },
		pure = true,
	}),
	define({
		type = "Color",
		displayName = "Color",
		category = "Data",
		description = 'A constant colour ("#RRGGBB" or a "$palette" reference).',
		outputs = { data("value", "color3", "Value") },
		params = { prop("value", "color3", "#FFFFFF", "The colour.", { label = "Value" }) },
		pure = true,
	}),
	define({
		type = "Component",
		displayName = "Component",
		category = "Data",
		description = "Outputs a component of this effect, for action nodes' Target pins.",
		outputs = { data("component", "component", "Component") },
		params = { prop("component", "componentRef", "", "Id of the component.", { label = "Component" }) },
		pure = true,
	}),

	-- Math ----------------------------------------------------------------------------------------------------
	define({
		type = "Math",
		displayName = "Math",
		category = "Math",
		description = "Arithmetic on numbers: add, sub, mul, div, min, max, pow, lerp(a, b, t).",
		inputs = { data("a", "number", "A"), data("b", "number", "B"), data("t", "number", "T") },
		outputs = { data("result", "number", "Result") },
		params = {
			prop("op", "enum", "add", "Operation.", { label = "Operation", enum = NodeTypes.MATH_OPS }),
			prop("a", "number", 0, "First operand.", { label = "A" }),
			prop("b", "number", 1, "Second operand.", { label = "B" }),
			prop("t", "number", 0.5, "Interpolation factor (lerp only).", { label = "T" }),
		},
		pure = true,
	}),

	-- Actions -------------------------------------------------------------------------------------------------
	define({
		type = "Emit",
		displayName = "Emit",
		category = "Actions",
		description = "Emits a burst of particles from a particles component.",
		inputs = { IN, targetPin({ "particles" }), data("count", "number", "Count") },
		outputs = { OUT },
		params = {
			targetParam({ "particles" }),
			prop(
				"count",
				"integer",
				10,
				"Number of particles (scaled by the quality profile).",
				{ label = "Count", min = 0, max = Constants.MAX_EMIT_COUNT, step = 1, quality = "count" }
			),
		},
		action = "emit",
	}),
	define({
		type = "SetEnabled",
		displayName = "Set Enabled",
		category = "Actions",
		description = "Enables or disables a component (emitters, beams, trails, lights).",
		inputs = { IN, targetPin(nil), data("enabled", "boolean", "Enabled") },
		outputs = { OUT },
		params = {
			targetParam(nil),
			prop("enabled", "boolean", true, "true = enable, false = disable.", { label = "Enabled" }),
		},
		action = "enable",
	}),
	define({
		type = "Tween",
		displayName = "Tween",
		category = "Actions",
		description = "Animates a channel of a component to a value over a duration.",
		inputs = { IN, targetPin(nil), data("value", "any", "Value"), data("duration", "number", "Duration") },
		outputs = {
			exec("out", "Out", "Fires when the tween starts."),
			exec("done", "Done", "Fires when the tween has finished."),
		},
		params = {
			targetParam(nil),
			prop("channel", "string", "", "Channel of the target component (e.g. position).", { label = "Channel" }),
			prop("value", "number", nil, "Target value; its kind follows the channel.", { label = "Value" }),
			prop(
				"duration",
				"number",
				0.5,
				"Tween duration in seconds.",
				{ label = "Duration", min = 0, max = MAX_DURATION }
			),
			prop("easing", "string", "Linear", 'Easing ("Quad.InOut", { bezier = {...} }, ...).', {
				label = "Easing",
			}),
		},
		action = "tween",
		special = { channel = "channel", value = "channelValue", easing = "easing" },
	}),
	define({
		type = "SetProperty",
		displayName = "Set Property",
		category = "Actions",
		description = "Sets a channel of a component to a value immediately.",
		inputs = { IN, targetPin(nil), data("value", "any", "Value") },
		outputs = { OUT },
		params = {
			targetParam(nil),
			prop("channel", "string", "", "Channel of the target component (e.g. position).", { label = "Channel" }),
			prop("value", "number", nil, "New value; its kind follows the channel.", { label = "Value" }),
		},
		action = "set",
		special = { channel = "channel", value = "channelValue" },
	}),
	define({
		type = "FireEvent",
		displayName = "Fire Event",
		category = "Actions",
		description = "Forwards a named event to game code (handle.Event / OnEvent).",
		inputs = { IN, data("name", "string", "Name") },
		outputs = { OUT },
		params = { prop("name", "string", "", "Event name.", { label = "Event" }) },
		action = "fire",
		special = { name = "eventName" },
	}),
	define({
		type = "PlaySound",
		displayName = "Play Sound",
		category = "Actions",
		description = "Plays a sound component.",
		inputs = { IN, targetPin({ "sound" }) },
		outputs = { OUT },
		params = { targetParam({ "sound" }) },
		action = "play",
	}),
	define({
		type = "Regenerate",
		displayName = "Regenerate",
		category = "Actions",
		description = "Regenerates the shape of a lightning component.",
		inputs = { IN, targetPin({ "lightning" }) },
		outputs = { OUT },
		params = { targetParam({ "lightning" }) },
		action = "regenerate",
	}),
}

local byType: { [string]: NodeType } = {}
local inputIndex: { [string]: { [string]: Pin } } = {}
local outputIndex: { [string]: { [string]: number } } = {}
local paramIndex: { [string]: { [string]: PropertySpec } } = {}

for _, nodeType in definitions do
	assert(byType[nodeType.type] == nil, "duplicate node type " .. nodeType.type)
	byType[nodeType.type] = nodeType
	local inputs: { [string]: Pin } = {}
	for _, pin in nodeType.inputs do
		assert(inputs[pin.name] == nil, nodeType.type .. ": duplicate input " .. pin.name)
		inputs[pin.name] = pin
	end
	local outputs: { [string]: number } = {}
	for i, pin in nodeType.outputs do
		assert(outputs[pin.name] == nil and inputs[pin.name] == nil, nodeType.type .. ": duplicate pin " .. pin.name)
		outputs[pin.name] = i
	end
	local params: { [string]: PropertySpec } = {}
	for _, spec in nodeType.params do
		assert(params[spec.name] == nil, nodeType.type .. ": duplicate param " .. spec.name)
		params[spec.name] = spec
	end
	inputIndex[nodeType.type] = inputs
	outputIndex[nodeType.type] = outputs
	paramIndex[nodeType.type] = params
	deepFreeze(nodeType)
end
table.freeze(definitions)

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

-- Node type by name, or nil (non-string input returns nil).
function NodeTypes.get(nodeType: any): NodeType?
	if type(nodeType) ~= "string" then
		return nil
	end
	return byType[nodeType]
end

-- All node types in palette order (Triggers, Flow, Data, Math, Actions).
function NodeTypes.list(): { NodeType }
	return table.clone(definitions)
end

-- Param spec of a node type, or nil.
function NodeTypes.paramSpec(nodeType: NodeType, name: any): PropertySpec?
	local params = paramIndex[nodeType.type]
	return if params and type(name) == "string" then params[name] else nil
end

-- Number of active variadic outputs for a node with these params (nil for non-variadic types).
-- Invalid or missing counts fall back to the param default; values are rounded and clamped to [min, max].
function NodeTypes.count(nodeType: NodeType, params: any): number?
	local variadic = nodeType.variadic
	if variadic == nil then
		return nil
	end
	local spec = NodeTypes.paramSpec(nodeType, variadic.countParam)
	local value: any = if type(params) == "table" then params[variadic.countParam] else nil
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		value = if spec then spec.default else variadic.min
	end
	return math.clamp(math.floor(value + 0.5), variadic.min, variadic.max)
end

-- Input pins of a node type (static).
function NodeTypes.inputs(nodeType: NodeType): { Pin }
	return nodeType.inputs
end

-- Active output pins for a node with these params (variadic outputs limited to `count`).
function NodeTypes.outputs(nodeType: NodeType, params: any): { Pin }
	local n = NodeTypes.count(nodeType, params)
	if n == nil then
		return nodeType.outputs
	end
	local out = {}
	for i = 1, n do
		out[i] = nodeType.outputs[i]
	end
	return out
end

-- Finds a pin by name. Returns (pin, direction, active); active is false for a variadic output beyond `count`.
function NodeTypes.findPin(nodeType: NodeType, params: any, name: any): (Pin?, PinDirection?, boolean)
	if type(name) ~= "string" then
		return nil, nil, false
	end
	local input = inputIndex[nodeType.type][name]
	if input then
		return input, "input", true
	end
	local index = outputIndex[nodeType.type][name]
	if index then
		local n = NodeTypes.count(nodeType, params)
		local pin = nodeType.outputs[index]
		return pin, "output", n == nil or index <= n
	end
	return nil, nil, false
end

return NodeTypes
