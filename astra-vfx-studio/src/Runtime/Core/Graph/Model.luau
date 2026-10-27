--!strict
--[[
	Graph.Model — shared, never-throwing analysis of raw (possibly malformed) GraphDefs, used by the validator,
	the live connection check and the compiler.

	* parseRef("node.pin"): node id per Constants.ID_PATTERN (≤ Constants.ID_MAX_LENGTH chars), pin name an
	  identifier ([A-Za-z_][A-Za-z0-9_]*). Ids cannot contain ".", so the first "." separates the two parts.
	* index(graph): nodes with a valid, unique id (first occurrence wins) and links whose two refs parse. Anything
	  else is skipped here (the validator reports it).
	* The dependency graph used for cycle detection has one edge per wired link (both nodes exist with known
	  types, `from` is an active output pin, `to` an input pin; exec and data links alike, kinds are not
	  compared), directed from the `from` node to the `to` node. Links that are already invalid for other
	  reasons (unknown pins, reversed direction) therefore do not produce extra cycle errors.
	* Pin kinds are resolved per node: Tween / SetProperty "value" takes the kind of the target channel
	  (Components.channelSpec of the statically known target component type), otherwise "any".
]]

local Components = require(script.Parent.Parent.Components)
local Constants = require(script.Parent.Parent.Constants)
local NodeTypes = require(script.Parent.NodeTypes)
local Types = require(script.Parent.Parent.Types)

type NodeType = NodeTypes.NodeType
type Pin = NodeTypes.Pin
type PinKind = NodeTypes.PinKind
type PinDirection = NodeTypes.PinDirection
type ChannelSpec = Types.ChannelSpec

export type NodeEntry = {
	id: string,
	index: number, -- 1-based position in graph.nodes
	def: { [string]: any }, -- the raw NodeDef table
	nodeType: NodeType?, -- nil for unknown types
	params: { [string]: any }, -- raw params table ({} when missing or not a table)
}

export type ParsedLink = {
	index: number, -- 1-based position in graph.links
	from: string,
	to: string,
	fromNode: string,
	fromPin: string,
	toNode: string,
	toPin: string,
}

export type Index = {
	nodes: { [string]: NodeEntry },
	order: { string }, -- valid node ids in definition order
	links: { ParsedLink }, -- links whose refs parse, in definition order
	nodeCount: number, -- #graph.nodes (raw)
	linkCount: number, -- #graph.links (raw)
}

export type Edge = { to: string, link: number }
export type Adjacency = { [string]: { Edge } }

local Model = {}

local NO_EDGES: { Edge } = table.freeze({})

local ID_PATTERN = Constants.ID_PATTERN
local ID_MAX_LENGTH = Constants.ID_MAX_LENGTH
local PIN_PATTERN = "^[A-Za-z_][A-Za-z0-9_]*$"

-- ─────────────────────────────────────────────────────────────────────────────
-- Basics
-- ─────────────────────────────────────────────────────────────────────────────

-- Length of a plain array (keys exactly 1..n), or nil. Tables without keys (including Json.EMPTY_OBJECT) are
-- empty arrays.
function Model.arrayLength(value: any): number?
	if type(value) ~= "table" then
		return nil
	end
	local n = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil
		end
		n += 1
	end
	for i = 1, n do
		if value[i] == nil then
			return nil
		end
	end
	return n
end

function Model.isId(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= ID_MAX_LENGTH
		and string.match(value, ID_PATTERN) ~= nil
end

-- "node.pin" -> (node, pin), or nil when malformed.
function Model.parseRef(ref: any): (string?, string?)
	if type(ref) ~= "string" then
		return nil, nil
	end
	local dot = string.find(ref, ".", 1, true)
	if dot == nil then
		return nil, nil
	end
	local nodeId = string.sub(ref, 1, dot - 1)
	local pin = string.sub(ref, dot + 1)
	if not Model.isId(nodeId) or #pin > ID_MAX_LENGTH or string.match(pin, PIN_PATTERN) == nil then
		return nil, nil
	end
	return nodeId, pin
end

function Model.describe(value: any): string
	local t = typeof(value)
	if t == "string" then
		local s: string = value
		if #s > 40 then
			s = string.sub(s, 1, 37) .. "..."
		end
		return string.format("%q", s)
	elseif t == "number" or t == "boolean" or t == "nil" then
		return tostring(value)
	end
	return t
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Indexing
-- ─────────────────────────────────────────────────────────────────────────────

-- Lists of a graph as arrays ({} when missing or malformed).
function Model.lists(graph: any): ({ any }, { any })
	if type(graph) ~= "table" then
		return {}, {}
	end
	local nodes: any = graph.nodes
	local links: any = graph.links
	return (if Model.arrayLength(nodes) then nodes else {}), (if Model.arrayLength(links) then links else {})
end

function Model.index(graph: any): Index
	local rawNodes, rawLinks = Model.lists(graph)
	local nodes: { [string]: NodeEntry } = {}
	local order: { string } = {}
	for i, node in ipairs(rawNodes) do
		if type(node) == "table" and Model.isId(node.id) and nodes[node.id] == nil then
			local params: any = node.params
			nodes[node.id] = {
				id = node.id,
				index = i,
				def = node,
				nodeType = NodeTypes.get(node.type),
				params = if type(params) == "table" then params else {},
			}
			table.insert(order, node.id)
		end
	end
	local links: { ParsedLink } = {}
	for i, link in ipairs(rawLinks) do
		if type(link) == "table" then
			local fromNode, fromPin = Model.parseRef(link.from)
			local toNode, toPin = Model.parseRef(link.to)
			if fromNode and fromPin and toNode and toPin then
				table.insert(links, {
					index = i,
					from = link.from,
					to = link.to,
					fromNode = fromNode,
					fromPin = fromPin,
					toNode = toNode,
					toPin = toPin,
				})
			end
		end
	end
	return { nodes = nodes, order = order, links = links, nodeCount = #rawNodes, linkCount = #rawLinks }
end

-- id -> component type for every component of the definition with a string id and type (first wins).
function Model.components(def: any): { [string]: string }
	local out: { [string]: string } = {}
	if type(def) ~= "table" or type(def.components) ~= "table" then
		return out
	end
	for _, component in ipairs(def.components) do
		if type(component) == "table" and type(component.id) == "string" and type(component.type) == "string" then
			if out[component.id] == nil then
				out[component.id] = component.type
			end
		end
	end
	return out
end

-- marker id -> time (seconds) for every marker of the definition with a string id (first wins).
function Model.markers(def: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(def) ~= "table" or type(def.markers) ~= "table" then
		return out
	end
	for _, marker in ipairs(def.markers) do
		if type(marker) == "table" and type(marker.id) == "string" and out[marker.id] == nil then
			local t = marker.time
			out[marker.id] = if type(t) == "number" and t == t and math.abs(t) < math.huge then t else 0
		end
	end
	return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Pins and kinds
-- ─────────────────────────────────────────────────────────────────────────────

-- Data kinds are compatible when equal or when either side is "any"; exec only connects to exec.
function Model.kindsCompatible(fromKind: string, toKind: string): boolean
	if fromKind == "exec" or toKind == "exec" then
		return fromKind == toKind
	end
	return fromKind == toKind or fromKind == "any" or toKind == "any"
end

-- Finds a pin on an indexed node: (pin, direction, active).
function Model.pin(entry: NodeEntry?, name: string): (Pin?, PinDirection?, boolean)
	if entry == nil or entry.nodeType == nil then
		return nil, nil, false
	end
	return NodeTypes.findPin(entry.nodeType :: NodeType, entry.params, name)
end

-- First link feeding `nodeId.pin` (in link order), if any.
function Model.incoming(index: Index, nodeId: string, pin: string): ParsedLink?
	for _, link in index.links do
		if link.toNode == nodeId and link.toPin == pin then
			return link
		end
	end
	return nil
end

-- Statically known component id for a component pin / param of a node: the linked Component node's param or
-- the node's own `pinName` param. Returns (id, origin) where origin is "link" or "param"; nil when unknown.
function Model.staticComponent(index: Index, entry: NodeEntry, pinName: string): (string?, string?)
	local link = Model.incoming(index, entry.id, pinName)
	if link then
		local source = index.nodes[link.fromNode]
		if source and source.nodeType and source.nodeType.type == "Component" and link.fromPin == "component" then
			local id = source.params.component
			return if type(id) == "string" then id else nil, "link"
		end
		return nil, "link"
	end
	local id = entry.params[pinName]
	return if type(id) == "string" then id else nil, "param"
end

-- Channel spec of a Tween / SetProperty node's target channel, when statically resolvable.
function Model.channelSpec(index: Index, components: { [string]: string }, entry: NodeEntry): ChannelSpec?
	local channel = entry.params.channel
	if type(channel) ~= "string" then
		return nil
	end
	local target = Model.staticComponent(index, entry, "target")
	local componentType = if target then components[target] else nil
	if componentType == nil then
		return nil
	end
	return Components.channelSpec(componentType, channel)
end

-- Effective kind of a pin: Tween/SetProperty "value" follows the channel spec, every other pin is static.
function Model.pinKind(index: Index, components: { [string]: string }, entry: NodeEntry, pin: Pin): string
	local nodeType = entry.nodeType
	if pin.kind == "any" and nodeType and nodeType.special[pin.name] == "channelValue" then
		local spec = Model.channelSpec(index, components, entry)
		if spec then
			return spec.kind
		end
	end
	return pin.kind
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Dependency graph and cycles
-- ─────────────────────────────────────────────────────────────────────────────

-- True when a parsed link is wired correctly: both nodes exist with known types, `from` names an active output
-- and `to` an input (pin kinds are not compared).
function Model.isWired(index: Index, link: ParsedLink): boolean
	local _, fromDir, fromActive = Model.pin(index.nodes[link.fromNode], link.fromPin)
	local _, toDir = Model.pin(index.nodes[link.toNode], link.toPin)
	return fromDir == "output" and fromActive and toDir == "input"
end

-- One edge per wired link (Model.isWired), in link order.
function Model.adjacency(index: Index): Adjacency
	local adjacency: Adjacency = {}
	for _, id in index.order do
		adjacency[id] = {}
	end
	for _, link in index.links do
		local edges = adjacency[link.fromNode]
		if edges and Model.isWired(index, link) then
			table.insert(edges, { to = link.toNode, link = link.index })
		end
	end
	return adjacency
end

-- True when `target` is reachable from `start` (iterative DFS; start reaches itself).
function Model.reaches(adjacency: Adjacency, start: string, target: string): boolean
	if start == target then
		return true
	end
	local seen: { [string]: boolean } = { [start] = true }
	local stack = { start }
	while #stack > 0 do
		local id = table.remove(stack) :: string
		for _, edge in adjacency[id] or NO_EDGES do
			if edge.to == target then
				return true
			end
			if not seen[edge.to] then
				seen[edge.to] = true
				table.insert(stack, edge.to)
			end
		end
	end
	return false
end

-- Shortest path of node ids from `start` to `target` (BFS, edges in link order), or nil.
function Model.path(adjacency: Adjacency, start: string, target: string, allowed: { [string]: boolean }?): { string }?
	local previous: { [string]: string } = {}
	local seen: { [string]: boolean } = { [start] = true }
	local queue = { start }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		for _, edge in adjacency[id] or NO_EDGES do
			if edge.to == target then
				local path = { target }
				local cursor = id
				while cursor ~= start do
					table.insert(path, 1, cursor)
					cursor = previous[cursor]
				end
				table.insert(path, 1, start)
				return path
			end
			if not seen[edge.to] and (allowed == nil or allowed[edge.to]) then
				seen[edge.to] = true
				previous[edge.to] = id
				table.insert(queue, edge.to)
			end
		end
	end
	return nil
end

-- First cycle found by an iterative DFS over nodes in definition order: node ids in cycle order (the last one
-- links back to the first); { id } for a self-loop; nil when acyclic.
function Model.findCycle(index: Index, adjacency: Adjacency): { string }?
	local state: { [string]: number } = {} -- nil = unvisited, 1 = on stack, 2 = done
	for _, root in index.order do
		if state[root] == nil then
			local stack: { { id: string, edge: number } } = { { id = root, edge = 0 } }
			state[root] = 1
			while #stack > 0 do
				local frame = stack[#stack]
				local edges = adjacency[frame.id] or NO_EDGES
				frame.edge += 1
				local edge = edges[frame.edge]
				if edge == nil then
					state[frame.id] = 2
					table.remove(stack)
				elseif state[edge.to] == 1 then
					-- Back edge: the cycle is the stack slice from edge.to to the top.
					local cycle = {}
					local collecting = false
					for _, f in stack do
						if f.id == edge.to then
							collecting = true
						end
						if collecting then
							table.insert(cycle, f.id)
						end
					end
					return cycle
				elseif state[edge.to] == nil then
					state[edge.to] = 1
					table.insert(stack, { id = edge.to, edge = 0 })
				end
			end
		end
	end
	return nil
end

export type Cycle = { nodes: { string }, link: number } -- link = index of the link closing the cycle

-- Strongly connected components (iterative Tarjan) of the graph given by `order` (all node ids) and
-- `adjacency`, in completion order. Every node appears in exactly one group; groups of one node may or may not
-- have a self-loop (check the adjacency).
function Model.stronglyConnected(order: { string }, adjacency: Adjacency): { { string } }
	local indexOf: { [string]: number } = {}
	local lowlink: { [string]: number } = {}
	local onStack: { [string]: boolean } = {}
	local sccStack: { string } = {}
	local counter = 0
	local groups: { { string } } = {}

	for _, root in order do
		if indexOf[root] == nil then
			local call: { { id: string, edge: number } } = {}
			local function visit(id: string)
				counter += 1
				indexOf[id] = counter
				lowlink[id] = counter
				table.insert(sccStack, id)
				onStack[id] = true
				table.insert(call, { id = id, edge = 0 })
			end
			visit(root)
			while #call > 0 do
				local frame = call[#call]
				local edges = adjacency[frame.id] or NO_EDGES
				frame.edge += 1
				local edge = edges[frame.edge]
				if edge then
					if indexOf[edge.to] == nil then
						visit(edge.to)
					elseif onStack[edge.to] then
						lowlink[frame.id] = math.min(lowlink[frame.id], indexOf[edge.to])
					end
				else
					table.remove(call)
					local parent = call[#call]
					if parent then
						lowlink[parent.id] = math.min(lowlink[parent.id], lowlink[frame.id])
					end
					if lowlink[frame.id] == indexOf[frame.id] then
						local group = {}
						repeat
							local member = table.remove(sccStack) :: string
							onStack[member] = false
							table.insert(group, member)
						until member == frame.id
						table.insert(groups, group)
					end
				end
			end
		end
	end
	return groups
end

-- Every cycle group (strongly connected component with more than one node, or a self-loop), ordered by the
-- position of their first node; each with one concrete (shortest) cycle through that node.
function Model.cycles(index: Index, adjacency: Adjacency): { Cycle }
	local groups = Model.stronglyConnected(index.order, adjacency)

	local position: { [string]: number } = {}
	for i, id in index.order do
		position[id] = i
	end
	local out: { Cycle } = {}
	for _, group in groups do
		table.sort(group, function(a: string, b: string): boolean
			return position[a] < position[b]
		end)
		local first = group[1]
		local members: { [string]: boolean } = {}
		for _, id in group do
			members[id] = true
		end
		local selfLink: number? = nil
		for _, edge in adjacency[first] or NO_EDGES do
			if edge.to == first then
				selfLink = edge.link
				break
			end
		end
		if selfLink then
			table.insert(out, { nodes = { first }, link = selfLink })
		elseif #group > 1 then
			-- Shortest cycle through `first` inside the group: first -> ... -> last -> first.
			local best: { string }? = nil
			local closing: number? = nil
			for _, id in group do
				for _, edge in adjacency[id] or NO_EDGES do
					if edge.to == first then
						local p = Model.path(adjacency, first, id, members)
						if p and (best == nil or #p < #best) then
							best = p
							closing = edge.link
						end
					end
				end
			end
			if best and closing then
				table.insert(out, { nodes = best, link = closing })
			end
		end
	end
	table.sort(out, function(a: Cycle, b: Cycle): boolean
		return position[a.nodes[1]] < position[b.nodes[1]]
	end)
	return out
end

return Model
