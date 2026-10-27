--!strict
--[[
	Graph — node graph engine (docs/MODULE_CONTRACTS.md §11, ARCHITECTURE §6).

	A graph adds logic to the timeline. It never runs threads: trigger flows are unrolled into ScheduledActions
	on the effect time axis (OnPlay / OnMarker statically by the Compiler, OnEvent at runtime by the Player).

	  Graph.NodeTypes                          node type registry (Graph/NodeTypes.luau)
	  Graph.parseRef("node.pin")               -> (nodeId, pinName) | nil
	  Graph.validate(graph, def)               -> { Diagnostic }      never throws (Graph/Validator.luau)
	  Graph.canConnect(graph, def, from, to)   -> (ok, reason?, code?) live editor check
	  Graph.findCycle(graph)                   -> { nodeId }?         one cycle (exec and data links)
	  Graph.compile(graph, def)                -> CompiledGraph       (Graph/Runner.luau)
	  Graph.run(compiled, trigger, startTime, seed, cycle, effect?) -> (ActionList, RunInfo)

	Extensions beyond the contract:
	  Graph.staticSchedule(compiled, seed, cycle, effect?) -> (ActionList, RunInfo)
	      play at 0 + every marker trigger at its time, merged and sorted (what the Compiler needs)
	  Graph.triggers(compiled) -> { play, markers, events }   which triggers have flows
	  Graph.resolveParamSpec(graph, def, nodeId, name) -> PropertySpec?   effective spec of a param (the
	      Tween / SetProperty "value" param takes kind, range and default from the target channel)
	  Graph.pinKind(graph, def, ref) -> PinKind?   effective kind of a pin ("value" follows the channel)
	  run() returns a second value (RunInfo); the list's `truncated` flag is list.truncated (see Runner).
	  Graph.MAX_WORK   per-run work budget that bounds unrolling of malformed (cyclic) graphs
]]

local Model = require(script.Model)
local NodeTypes = require(script.NodeTypes)
local Runner = require(script.Runner)
local Types = require(script.Parent.Types)
local Validator = require(script.Validator)

type Diagnostic = Types.Diagnostic
type GraphDef = Types.GraphDef
type EffectDefinition = Types.EffectDefinition
type PropertySpec = Types.PropertySpec
type CompiledEffect = Types.CompiledEffect

export type NodeType = NodeTypes.NodeType
export type Pin = NodeTypes.Pin
export type PinKind = NodeTypes.PinKind
export type CompiledGraph = Runner.CompiledGraph
export type CompiledNode = Runner.CompiledNode
export type Trigger = Runner.Trigger
export type ActionList = Runner.ActionList
export type RunInfo = Runner.RunInfo

local Graph = {}

Graph.NodeTypes = NodeTypes
-- Work budget per run (queued flows + node evaluations) and queue bound; see Graph/Runner.luau.
Graph.MAX_WORK = Runner.MAX_WORK
Graph.MAX_PENDING = Runner.MAX_PENDING

-- "node.pin" -> (nodeId, pinName); nil when malformed.
function Graph.parseRef(ref: string): (string?, string?)
	return Model.parseRef(ref)
end

-- Diagnostics (codes graph.*) for a graph in the context of its effect definition. Never throws.
function Graph.validate(graph: GraphDef?, def: EffectDefinition?): { Diagnostic }
	return Validator.validate(graph, def)
end

-- Checks a hypothetical new link for the editor: (true) or (false, reason, diagnostic code).
function Graph.canConnect(
	graph: GraphDef,
	def: EffectDefinition?,
	from: string,
	to: string
): (boolean, string?, string?)
	return Validator.canConnect(graph, def, from, to)
end

-- Node ids of one cycle (in order; the last links back to the first), or nil when the graph is acyclic.
function Graph.findCycle(graph: GraphDef): { string }?
	local index = Model.index(graph)
	return Model.findCycle(index, Model.adjacency(index))
end

-- Compiles a (validated) graph. Malformed parts are dropped, never thrown.
function Graph.compile(graph: GraphDef?, def: EffectDefinition?): CompiledGraph
	return Runner.compile(graph, def)
end

-- Unrolls one trigger into scheduled actions sorted by time (at most Constants.MAX_GRAPH_ACTIONS).
function Graph.run(
	compiled: CompiledGraph,
	trigger: Trigger,
	startTime: number,
	seed: number,
	cycle: number,
	effect: CompiledEffect?
): (ActionList, RunInfo)
	return Runner.run(compiled, trigger, startTime, seed, cycle, effect)
end

-- Play (at 0) + every marker trigger (at its time), merged and sorted; `order` renumbered.
function Graph.staticSchedule(
	compiled: CompiledGraph,
	seed: number,
	cycle: number,
	effect: CompiledEffect?
): (ActionList, RunInfo)
	return Runner.staticSchedule(compiled, seed, cycle, effect)
end

-- Which triggers have flows: { play = boolean, markers = { id }, events = { name } } (sorted).
function Graph.triggers(compiled: CompiledGraph): { play: boolean, markers: { string }, events: { string } }
	return Runner.triggers(compiled)
end

local ZERO: { [string]: any } = { number = 0, vector3 = { 0, 0, 0 }, color3 = "#FFFFFF", boolean = false }

-- Effective PropertySpec of a node's param (nil for unknown nodes/params). For "channelValue" params the kind,
-- range and default come from the target channel when it can be resolved statically.
function Graph.resolveParamSpec(graph: GraphDef, def: EffectDefinition?, nodeId: string, name: string): PropertySpec?
	local index = Model.index(graph)
	local entry = index.nodes[nodeId]
	if entry == nil or entry.nodeType == nil then
		return nil
	end
	local nodeType = entry.nodeType :: NodeType
	local spec = NodeTypes.paramSpec(nodeType, name)
	if spec == nil or nodeType.special[name] ~= "channelValue" then
		return spec
	end
	local channel = Model.channelSpec(index, Model.components(def), entry)
	if channel == nil then
		return spec
	end
	return {
		name = spec.name,
		kind = channel.kind,
		default = ZERO[channel.kind],
		label = spec.label,
		description = spec.description .. " (" .. channel.name .. ": " .. channel.description .. ")",
		min = channel.min,
		max = channel.max,
		scale = channel.scale,
	}
end

-- Effective kind of a pin given as "node.pin" (nil when the node or pin does not exist).
function Graph.pinKind(graph: GraphDef, def: EffectDefinition?, ref: string): PinKind?
	local nodeId, pinName = Model.parseRef(ref)
	if nodeId == nil or pinName == nil then
		return nil
	end
	local index = Model.index(graph)
	local entry = index.nodes[nodeId]
	local pin = Model.pin(entry, pinName)
	if entry == nil or pin == nil then
		return nil
	end
	return Model.pinKind(index, Model.components(def), entry, pin) :: any
end

return Graph
