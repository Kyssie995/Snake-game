--!strict
--[[
	Graph.Validator — Graph.validate (diagnostics for a whole graph) and Graph.canConnect (live check of one
	hypothetical link for the editor). Neither ever throws, whatever the input.

	Diagnostic codes (paths are absolute in the effect, 1-based: "graph.nodes[2].params.count", "graph.links[3]"):

	  error    graph.type              graph / graph.nodes / graph.links has the wrong type
	  error    graph.limit             more than Constants.MAX_GRAPH_NODES nodes or MAX_GRAPH_LINKS links
	  error    graph.node_invalid      node entry is not an object
	  error    graph.node_id           node id missing or not [A-Za-z0-9_-]{1,64}
	  error    graph.node_duplicate    node id used twice (the first node keeps it)
	  error    graph.node_type         unknown node type
	  error    graph.node_position     position is not [x, y]
	  error    graph.param_type        param has the wrong JSON form (Codec.check / Easing.check)
	  error    graph.param_range       param outside its range (Codec.check problem "range")
	  warning  graph.param_unknown     param not declared by the node type
	  error    graph.param_ref         "$key" colour whose key is not in the effect palette
	  error    graph.component_missing component reference does not exist in def.components
	                                   (warning when a Component node has no component selected)
	  error    graph.component_type    referenced component has a type the pin/param does not allow
	  error    graph.marker_missing    OnMarker marker does not exist (warning when no marker is set)
	  error    graph.event_name        event name is not a valid name (warning when empty)
	  warning  graph.target_missing    action node has neither a linked target nor a target param
	  warning  graph.channel_missing   Tween / SetProperty without a channel
	  error    graph.channel_unknown   channel not declared by the (registered) target component type
	  info     graph.channel_unverified target type is not in the component registry; channel not checked
	  warning  graph.action_unsupported registered target type does not declare the action as an event
	  error    graph.link_invalid      link entry is not an object
	  error    graph.link_ref          from / to is not a "nodeId.pinName" string
	  error    graph.link_node         link references a node that does not exist
	  error    graph.link_pin          pin does not exist on the node (or is beyond a variadic count)
	  error    graph.link_direction    link does not go from an output pin to an input pin
	  error    graph.link_kind         pin kinds are incompatible (exec only to exec; "any" matches any data
	                                   kind; no implicit conversions such as number -> vector3)
	  error    graph.link_duplicate    the same link appears twice
	  error    graph.input_multiple    a data input has more than one link
	  error    graph.output_multiple   an exec output has more than one link (fan out with Parallel/Sequence)
	  error    graph.cycle             the graph (exec and data links together) contains a cycle
	  warning  graph.unreachable       exec node not reachable from any trigger node (never runs)

	Rules for links are only checked once the earlier ones pass (a link with an unknown node is not also
	reported for its pins). Links touching nodes of unknown type are not checked further. Cycles are searched on
	every wired link (valid nodes, pins and direction; Graph.Model). Reachability follows the exec links that
	compile() keeps (the first link of an exec output), so the target of a rejected fan-out link is also
	reported as unreachable.

	canConnect(graph, def, from, to) applies the same link rules to a new link from -> to against the current
	graph, plus: the input / exec output must still be free, the link must not exist yet, must not create a cycle
	and must fit in MAX_GRAPH_LINKS. It returns (true) or (false, reason, code), where code is the diagnostic code
	of the failed rule (extension: lets the editor replace an occupied input on "graph.input_multiple").
]]

local Codec = require(script.Parent.Parent.Codec)
local Components = require(script.Parent.Parent.Components)
local Constants = require(script.Parent.Parent.Constants)
local Easing = require(script.Parent.Parent.Easing)
local Model = require(script.Parent.Model)
local NodeTypes = require(script.Parent.NodeTypes)
local Types = require(script.Parent.Parent.Types)

type Diagnostic = Types.Diagnostic
type Severity = Types.Severity
type PropertySpec = Types.PropertySpec
type NodeType = NodeTypes.NodeType
type Pin = NodeTypes.Pin
type NodeEntry = Model.NodeEntry
type Index = Model.Index
type ParsedLink = Model.ParsedLink

local Validator = {}

local describe = Model.describe
local NO_IDS: { string } = table.freeze({})
local EVENT_NAME_PATTERN = Constants.EVENT_NAME_PATTERN
local ID_MAX_LENGTH = Constants.ID_MAX_LENGTH

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function add(
	out: { Diagnostic },
	severity: Severity,
	code: string,
	path: string,
	message: string,
	hint: string?,
	componentId: string?
)
	table.insert(out, {
		severity = severity,
		code = code,
		path = path,
		message = message,
		hint = hint,
		componentId = componentId,
	})
end

local function contains(list: { string }, value: string): boolean
	for _, v in list do
		if v == value then
			return true
		end
	end
	return false
end

-- Case-insensitive suggestion from a candidate list.
local function suggest(name: any, candidates: { string }): string?
	if type(name) ~= "string" then
		return nil
	end
	local lower = string.lower(name)
	for _, candidate in candidates do
		if string.lower(candidate) == lower then
			return 'did you mean "' .. candidate .. '"?'
		end
	end
	return nil
end

local function nodeTypeNames(): { string }
	local names = {}
	for _, nodeType in NodeTypes.list() do
		table.insert(names, nodeType.type)
	end
	return names
end

local function pinNames(pins: { Pin }): string
	local names = {}
	for _, pin in pins do
		table.insert(names, pin.name)
	end
	return if #names > 0 then table.concat(names, ", ") else "(none)"
end

local function label(entry: NodeEntry): string
	local nodeType = entry.nodeType
	return 'node "' .. entry.id .. '"' .. (if nodeType then " (" .. nodeType.type .. ")" else "")
end

local function isEventName(value: any): boolean
	return type(value) == "string" and #value <= ID_MAX_LENGTH and string.match(value, EVENT_NAME_PATTERN) ~= nil
end

-- Kind of a JSON value usable as a channel value when the channel spec is unknown.
local function jsonChannelKind(value: any): string?
	if type(value) == "number" then
		return if value == value and math.abs(value) < math.huge then "number" else nil
	elseif type(value) == "boolean" then
		return "boolean"
	elseif type(value) == "string" then
		return if Codec.check("color3", value) then "color3" else nil
	elseif type(value) == "table" then
		return if Codec.check("vector3", value) then "vector3" else nil
	end
	return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Params
-- ─────────────────────────────────────────────────────────────────────────────

type Context = {
	out: { Diagnostic },
	index: Index,
	components: { [string]: string },
	markers: { [string]: number },
	palette: { [string]: boolean },
}

-- Palette keys of a definition.
local function paletteKeys(def: any): { [string]: boolean }
	local keys: { [string]: boolean } = {}
	if type(def) == "table" and type(def.palette) == "table" then
		for key in pairs(def.palette) do
			if type(key) == "string" then
				keys[key] = true
			end
		end
	end
	return keys
end

-- "$key" colour references that are not in the effect palette.
local function checkPaletteRefs(ctx: Context, kind: string, value: any, path: string, what: string)
	for _, key in Codec.paletteRefs(kind, value) do
		if not ctx.palette[key] then
			add(
				ctx.out,
				"error",
				"graph.param_ref",
				path,
				what .. ': palette entry "' .. key .. '" does not exist',
				'add it to the effect\'s palette or use a "#RRGGBB" colour'
			)
		end
	end
end

local function checkComponentRef(ctx: Context, value: string, allowed: { string }?, path: string, what: string)
	if value == "" then
		return
	end
	local componentType = ctx.components[value]
	if componentType == nil then
		add(
			ctx.out,
			"error",
			"graph.component_missing",
			path,
			what .. ' references component "' .. value .. '", which does not exist',
			"use the id of a component of this effect",
			value
		)
	elseif allowed and not contains(allowed, componentType) then
		add(
			ctx.out,
			"error",
			"graph.component_type",
			path,
			what
				.. ' references component "'
				.. value
				.. '" of type '
				.. componentType
				.. ", expected "
				.. table.concat(allowed, " or "),
			nil,
			value
		)
	end
end

local function checkParam(ctx: Context, entry: NodeEntry, spec: PropertySpec, value: any, path: string)
	local nodeType = entry.nodeType :: NodeType
	local special = nodeType.special[spec.name]
	local what = label(entry) .. " param " .. spec.name
	if special == "easing" then
		local ok, problem = Easing.check(value)
		if not ok then
			add(ctx.out, "error", "graph.param_type", path, what .. ": " .. tostring(problem))
		end
		return
	elseif special == "channelValue" then
		local channelSpec = Model.channelSpec(ctx.index, ctx.components, entry)
		if channelSpec then
			local ok, problem, class = Codec.check(channelSpec.kind, value, channelSpec)
			if not ok then
				local code = if class == "range" then "graph.param_range" else "graph.param_type"
				add(
					ctx.out,
					"error",
					code,
					path,
					what .. " (" .. channelSpec.kind .. " channel " .. channelSpec.name .. "): " .. tostring(problem)
				)
			else
				checkPaletteRefs(ctx, channelSpec.kind, value, path, what)
			end
		else
			local kind = jsonChannelKind(value)
			if kind == nil then
				add(
					ctx.out,
					"error",
					"graph.param_type",
					path,
					what .. ": expected a number, boolean, colour or [x, y, z], got " .. describe(value)
				)
			else
				checkPaletteRefs(ctx, kind, value, path, what)
			end
		end
		return
	end

	local ok, problem, class = Codec.check(spec.kind, value, spec)
	if not ok then
		local code = if class == "range" then "graph.param_range" else "graph.param_type"
		add(ctx.out, "error", code, path, what .. ": " .. tostring(problem))
		return
	end
	if special == "marker" then
		if value ~= "" and ctx.markers[value] == nil then
			add(
				ctx.out,
				"error",
				"graph.marker_missing",
				path,
				what .. ': marker "' .. value .. '" does not exist',
				"use the id of one of the effect's markers"
			)
		end
	elseif special == "eventName" then
		if value ~= "" and not isEventName(value) then
			add(
				ctx.out,
				"error",
				"graph.event_name",
				path,
				what .. ": " .. describe(value) .. " is not a valid event name",
				"letters, digits, _ and -, starting with a letter or _ (at most " .. ID_MAX_LENGTH .. " characters)"
			)
		end
	elseif spec.kind == "componentRef" then
		checkComponentRef(ctx, value, spec.componentTypes, path, what)
	elseif spec.kind == "color3" then
		checkPaletteRefs(ctx, spec.kind, value, path, what)
	end
end

local function checkParams(ctx: Context, entry: NodeEntry, path: string)
	local nodeType = entry.nodeType :: NodeType
	local params = entry.params
	for _, spec in nodeType.params do
		local value = params[spec.name]
		if value ~= nil then
			checkParam(ctx, entry, spec, value, path .. ".params." .. spec.name)
		end
	end
	local unknown: { string } = {}
	local odd = 0
	for key in pairs(params) do
		if type(key) == "string" then
			if NodeTypes.paramSpec(nodeType, key) == nil then
				table.insert(unknown, key)
			end
		else
			odd += 1
		end
	end
	table.sort(unknown)
	local declared = {}
	for _, spec in nodeType.params do
		table.insert(declared, spec.name)
	end
	for _, key in unknown do
		local hint = suggest(key, declared)
		if hint == nil and key == "weights" and nodeType.type == "RandomBranch" then
			hint = "use weight1 .. weight8"
		end
		add(
			ctx.out,
			"warning",
			"graph.param_unknown",
			path .. ".params." .. key,
			label(entry) .. " has no param " .. describe(key),
			hint or (if #declared > 0 then "params: " .. table.concat(declared, ", ") else "this node has no params")
		)
	end
	if odd > 0 then
		add(ctx.out, "warning", "graph.param_unknown", path .. ".params", label(entry) .. " has non-string param keys")
	end
end

-- Node-level checks that depend on links and the definition (targets, channels, empty names).
local function checkSemantics(ctx: Context, entry: NodeEntry, path: string)
	local nodeType = entry.nodeType :: NodeType
	local params = entry.params
	local index = ctx.index
	local kind = nodeType.type

	if kind == "OnMarker" then
		local marker = params.marker
		if marker == nil or marker == "" then
			add(
				ctx.out,
				"warning",
				"graph.marker_missing",
				path .. ".params.marker",
				label(entry) .. " has no marker; it never fires"
			)
		end
	elseif kind == "OnEvent" then
		local name = params.name
		if name == nil or name == "" then
			add(
				ctx.out,
				"warning",
				"graph.event_name",
				path .. ".params.name",
				label(entry) .. " has no event name; it never fires"
			)
		end
	elseif kind == "FireEvent" then
		local name = params.name
		if (name == nil or name == "") and Model.incoming(index, entry.id, "name") == nil then
			add(
				ctx.out,
				"warning",
				"graph.event_name",
				path .. ".params.name",
				label(entry) .. " has no event name; it does nothing"
			)
		end
	elseif kind == "Component" then
		local component = params.component
		if component == nil or component == "" then
			add(
				ctx.out,
				"warning",
				"graph.component_missing",
				path .. ".params.component",
				label(entry) .. " has no component selected"
			)
		end
	end

	if nodeType.action == nil or NodeTypes.paramSpec(nodeType, "target") == nil then
		return
	end
	local target, origin = Model.staticComponent(index, entry, "target")
	if origin == "param" and (target == nil or target == "") then
		add(
			ctx.out,
			"warning",
			"graph.target_missing",
			path .. ".params.target",
			label(entry) .. " has no target component; it does nothing",
			"link a Component node to its target pin or set params.target"
		)
	end
	local componentType = if target and target ~= "" then ctx.components[target] else nil

	if nodeType.special.channel == "channel" then
		local channel = params.channel
		if channel == nil or channel == "" then
			add(
				ctx.out,
				"warning",
				"graph.channel_missing",
				path .. ".params.channel",
				label(entry) .. " has no channel; it does nothing"
			)
		elseif type(channel) == "string" and componentType then
			if Components.get(componentType) == nil then
				add(
					ctx.out,
					"info",
					"graph.channel_unverified",
					path .. ".params.channel",
					label(entry)
						.. ': component type "'
						.. componentType
						.. '" is not registered, channel "'
						.. channel
						.. '" was not checked',
					nil,
					target
				)
			elseif Components.channelSpec(componentType, channel) == nil then
				local channels = {}
				for _, spec in (Components.get(componentType) :: any).channels do
					table.insert(channels, spec.name)
				end
				add(
					ctx.out,
					"error",
					"graph.channel_unknown",
					path .. ".params.channel",
					label(entry) .. ": component type " .. componentType .. ' has no channel "' .. channel .. '"',
					suggest(channel, channels)
						or (
							if #channels > 0 then "channels: " .. table.concat(channels, ", ") else "it has no channels"
						),
					target
				)
			end
		end
	elseif componentType and Components.get(componentType) then
		local action = nodeType.action :: string
		if nodeType.type == "SetEnabled" and params.enabled == false then
			action = "disable"
		end
		local allowed = (NodeTypes.paramSpec(nodeType, "target") :: PropertySpec).componentTypes
		local typeAllowed = allowed == nil or contains(allowed, componentType)
		if typeAllowed and Components.eventSpec(componentType, action) == nil then
			add(
				ctx.out,
				"warning",
				"graph.action_unsupported",
				path,
				label(entry) .. ": component type " .. componentType .. ' does not handle "' .. action .. '"',
				nil,
				target
			)
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Links
-- ─────────────────────────────────────────────────────────────────────────────

type LinkCheck = {
	ok: boolean,
	code: string?,
	message: string?,
	hint: string?,
	side: string?, -- "from" | "to" | nil (whole link)
	componentId: string?,
	fromPin: Pin?,
	toPin: Pin?,
}

local function fail(code: string, side: string?, message: string, hint: string?, componentId: string?): LinkCheck
	return { ok = false, code = code, side = side, message = message, hint = hint, componentId = componentId }
end

-- Shared link rules for validate() and canConnect(). `fromRef` / `toRef` are the raw refs.
local function checkLink(index: Index, components: { [string]: string }, fromRef: any, toRef: any): LinkCheck
	local fromNode, fromPinName = Model.parseRef(fromRef)
	local toNode, toPinName = Model.parseRef(toRef)
	if fromNode == nil or fromPinName == nil then
		return fail("graph.link_ref", "from", 'expected "nodeId.pinName", got ' .. describe(fromRef))
	end
	if toNode == nil or toPinName == nil then
		return fail("graph.link_ref", "to", 'expected "nodeId.pinName", got ' .. describe(toRef))
	end
	local src = index.nodes[fromNode]
	local dst = index.nodes[toNode]
	if src == nil then
		return fail("graph.link_node", "from", 'node "' .. fromNode .. '" does not exist')
	end
	if dst == nil then
		return fail("graph.link_node", "to", 'node "' .. toNode .. '" does not exist')
	end
	if src.nodeType == nil then
		return fail("graph.node_type", "from", label(src) .. " has an unknown type")
	end
	if dst.nodeType == nil then
		return fail("graph.node_type", "to", label(dst) .. " has an unknown type")
	end
	local srcType = src.nodeType :: NodeType
	local dstType = dst.nodeType :: NodeType
	local fromPin, fromDir, fromActive = Model.pin(src, fromPinName)
	local toPin, toDir = Model.pin(dst, toPinName)
	if fromPin == nil then
		return fail(
			"graph.link_pin",
			"from",
			label(src) .. ' has no pin "' .. fromPinName .. '"',
			"outputs: " .. pinNames(NodeTypes.outputs(srcType, src.params))
		)
	end
	if toPin == nil then
		return fail(
			"graph.link_pin",
			"to",
			label(dst) .. ' has no pin "' .. toPinName .. '"',
			"inputs: " .. pinNames(dstType.inputs)
		)
	end
	if not fromActive then
		return fail(
			"graph.link_pin",
			"from",
			label(src)
				.. ': output "'
				.. fromPinName
				.. '" is not active (count = '
				.. tostring(NodeTypes.count(srcType, src.params))
				.. ")",
			"raise params.count or link an active output"
		)
	end
	if fromDir ~= "output" or toDir ~= "input" then
		if fromDir == "input" and toDir == "output" then
			return fail(
				"graph.link_direction",
				nil,
				"link is reversed: " .. fromRef .. " is an input and " .. toRef .. " is an output",
				"links go from an output pin (from) to an input pin (to); swap from and to"
			)
		elseif fromDir ~= "output" then
			return fail(
				"graph.link_direction",
				"from",
				fromRef .. " is an input pin; links must start at an output",
				"outputs: " .. pinNames(NodeTypes.outputs(srcType, src.params))
			)
		end
		return fail(
			"graph.link_direction",
			"to",
			toRef .. " is an output pin; links must end at an input",
			"inputs: " .. pinNames(dstType.inputs)
		)
	end
	local fromKind = Model.pinKind(index, components, src, fromPin :: Pin)
	local toKind = Model.pinKind(index, components, dst, toPin :: Pin)
	if not Model.kindsCompatible(fromKind, toKind) then
		local hint = nil
		if fromKind == "number" and toKind == "vector3" then
			hint = "numbers are not converted to vectors; use a Vector node"
		elseif fromKind == "exec" or toKind == "exec" then
			hint = "exec pins only connect to exec pins"
		end
		return fail(
			"graph.link_kind",
			nil,
			"cannot connect " .. fromRef .. " (" .. fromKind .. ") to " .. toRef .. " (" .. toKind .. ")",
			hint
		)
	end
	local allowed = (toPin :: Pin).componentTypes
	if allowed and fromKind == "component" and srcType.type == "Component" then
		local id = src.params.component
		local componentType = if type(id) == "string" then components[id] else nil
		if componentType and not contains(allowed, componentType) then
			return fail(
				"graph.component_type",
				nil,
				toRef
					.. " accepts "
					.. table.concat(allowed, " or ")
					.. ' components, but "'
					.. id
					.. '" is of type '
					.. componentType,
				nil,
				id
			)
		end
	end
	return { ok = true, fromPin = fromPin, toPin = toPin }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- validate
-- ─────────────────────────────────────────────────────────────────────────────

type ValidLink = { link: ParsedLink, fromPin: Pin, toPin: Pin }

local function nodeIdProblem(id: any): string
	if id == nil then
		return "node has no id"
	elseif type(id) ~= "string" then
		return "node id must be a string, got " .. describe(id)
	elseif #id == 0 then
		return "node id is empty"
	elseif #id > ID_MAX_LENGTH then
		return "node id is longer than " .. ID_MAX_LENGTH .. " characters"
	end
	return "node id " .. describe(id) .. " may only contain letters, digits, _ and -"
end

-- Diagnostics for a graph in the context of its effect definition. nil graph => no diagnostics.
function Validator.validate(graph: any, def: any): { Diagnostic }
	local out: { Diagnostic } = {}
	if graph == nil then
		return out
	end
	if type(graph) ~= "table" then
		add(
			out,
			"error",
			"graph.type",
			"graph",
			"graph must be an object with nodes and links, got " .. describe(graph)
		)
		return out
	end
	local rawNodes: any = graph.nodes
	local rawLinks: any = graph.links
	if rawNodes ~= nil and Model.arrayLength(rawNodes) == nil then
		add(out, "error", "graph.type", "graph.nodes", "graph.nodes must be an array, got " .. describe(rawNodes))
	end
	if rawLinks ~= nil and Model.arrayLength(rawLinks) == nil then
		add(out, "error", "graph.type", "graph.links", "graph.links must be an array, got " .. describe(rawLinks))
	end
	local nodeList, linkList = Model.lists(graph)
	if #nodeList > Constants.MAX_GRAPH_NODES then
		add(
			out,
			"error",
			"graph.limit",
			"graph.nodes",
			"graph has " .. #nodeList .. " nodes, the limit is " .. Constants.MAX_GRAPH_NODES
		)
	end
	if #linkList > Constants.MAX_GRAPH_LINKS then
		add(
			out,
			"error",
			"graph.limit",
			"graph.links",
			"graph has " .. #linkList .. " links, the limit is " .. Constants.MAX_GRAPH_LINKS
		)
	end

	local index = Model.index(graph)
	local ctx: Context = {
		out = out,
		index = index,
		components = Model.components(def),
		markers = Model.markers(def),
		palette = paletteKeys(def),
	}

	-- Nodes ------------------------------------------------------------------------------------------------
	local typeNames = nodeTypeNames()
	for i, node in ipairs(nodeList) do
		local path = "graph.nodes[" .. i .. "]"
		if type(node) ~= "table" then
			add(out, "error", "graph.node_invalid", path, "node must be an object, got " .. describe(node))
			continue
		end
		local entry: NodeEntry? = nil
		if not Model.isId(node.id) then
			add(out, "error", "graph.node_id", path .. ".id", nodeIdProblem(node.id))
		else
			local first = index.nodes[node.id]
			if first and first.index ~= i then
				add(
					out,
					"error",
					"graph.node_duplicate",
					path .. ".id",
					'node id "' .. node.id .. '" is already used by graph.nodes[' .. first.index .. "]",
					"node ids must be unique"
				)
			else
				entry = first
			end
		end
		local nodeType = NodeTypes.get(node.type)
		if nodeType == nil then
			add(
				out,
				"error",
				"graph.node_type",
				path .. ".type",
				"unknown node type " .. describe(node.type),
				suggest(node.type, typeNames) or ("node types: " .. table.concat(typeNames, ", "))
			)
		end
		if node.position ~= nil then
			local ok, problem = Codec.check("vector2", node.position)
			if not ok then
				add(out, "error", "graph.node_position", path .. ".position", "position: " .. tostring(problem))
			end
		end
		local params: any = node.params
		if params ~= nil and type(params) ~= "table" then
			add(
				out,
				"error",
				"graph.param_type",
				path .. ".params",
				"params must be an object, got " .. describe(params)
			)
		end
		if nodeType then
			-- Duplicate / invalid ids still get their params checked (against a detached entry).
			local subject: NodeEntry = entry
				or {
					id = if type(node.id) == "string" then node.id else "?",
					index = i,
					def = node,
					nodeType = nodeType,
					params = if type(params) == "table" then params else {},
				}
			checkParams(ctx, subject, path)
			if entry then
				checkSemantics(ctx, subject, path)
			end
		end
	end

	-- Links ------------------------------------------------------------------------------------------------
	local valid: { ValidLink } = {}
	local parsedByIndex: { [number]: ParsedLink } = {}
	for _, link in index.links do
		parsedByIndex[link.index] = link
	end
	for i, link in ipairs(linkList) do
		local path = "graph.links[" .. i .. "]"
		if type(link) ~= "table" then
			add(
				out,
				"error",
				"graph.link_invalid",
				path,
				"link must be an object with from and to, got " .. describe(link)
			)
			continue
		end
		local result = checkLink(index, ctx.components, link.from, link.to)
		if not result.ok then
			if result.code ~= "graph.node_type" then -- unknown node types are reported on the node
				local where = if result.side then path .. "." .. result.side else path
				add(
					out,
					"error",
					result.code :: string,
					where,
					result.message :: string,
					result.hint,
					result.componentId
				)
			end
			continue
		end
		local parsed = parsedByIndex[i]
		if parsed then
			table.insert(valid, { link = parsed, fromPin = result.fromPin :: Pin, toPin = result.toPin :: Pin })
		end
	end

	-- Multiplicity -------------------------------------------------------------------------------------------
	local exact: { [string]: number } = {}
	local dataInputs: { [string]: number } = {}
	local execOutputs: { [string]: number } = {}
	local accepted: { ValidLink } = {} -- links compile() keeps (first per exec output / data input)
	for _, v in valid do
		local link = v.link
		local path = "graph.links[" .. link.index .. "]"
		local fromKey = link.fromNode .. "." .. link.fromPin
		local toKey = link.toNode .. "." .. link.toPin
		local key = fromKey .. ">" .. toKey
		if exact[key] then
			add(
				out,
				"error",
				"graph.link_duplicate",
				path,
				"duplicate link " .. fromKey .. " -> " .. toKey .. " (same as graph.links[" .. exact[key] .. "])"
			)
			continue
		end
		exact[key] = link.index
		local keep = true
		if v.toPin.kind ~= "exec" then
			local first = dataInputs[toKey]
			if first then
				keep = false
				add(
					out,
					"error",
					"graph.input_multiple",
					path .. ".to",
					"data input " .. toKey .. " already has a link (graph.links[" .. first .. "])",
					"a data input takes at most one link"
				)
			else
				dataInputs[toKey] = link.index
			end
		end
		if v.fromPin.kind == "exec" then
			local first = execOutputs[fromKey]
			if first then
				keep = false
				add(
					out,
					"error",
					"graph.output_multiple",
					path .. ".from",
					"exec output " .. fromKey .. " already has a link (graph.links[" .. first .. "])",
					"to run several flows, insert a Parallel or Sequence node"
				)
			else
				execOutputs[fromKey] = link.index
			end
		end
		if keep then
			table.insert(accepted, v)
		end
	end

	-- Cycles -----------------------------------------------------------------------------------------------
	local adjacency = Model.adjacency(index)
	for _, cycle in Model.cycles(index, adjacency) do
		local nodes = table.clone(cycle.nodes)
		table.insert(nodes, nodes[1])
		add(
			out,
			"error",
			"graph.cycle",
			"graph.links[" .. cycle.link .. "]",
			"cycle: " .. table.concat(nodes, " -> "),
			"graphs must be acyclic (exec and data links); use Loop for repetition"
		)
	end

	-- Reachability -------------------------------------------------------------------------------------------
	local execNext: { [string]: { string } } = {}
	for _, v in accepted do
		if v.fromPin.kind == "exec" then
			local list = execNext[v.link.fromNode]
			if list == nil then
				list = {}
				execNext[v.link.fromNode] = list
			end
			table.insert(list, v.link.toNode)
		end
	end
	local reached: { [string]: boolean } = {}
	local stack: { string } = {}
	for _, id in index.order do
		local nodeType = index.nodes[id].nodeType
		if nodeType and nodeType.trigger then
			reached[id] = true
			table.insert(stack, id)
		end
	end
	while #stack > 0 do
		local id = table.remove(stack) :: string
		for _, nextId in execNext[id] or NO_IDS do
			if not reached[nextId] then
				reached[nextId] = true
				table.insert(stack, nextId)
			end
		end
	end
	for _, id in index.order do
		local entry = index.nodes[id]
		local nodeType = entry.nodeType
		if nodeType and not nodeType.pure and nodeType.trigger == nil and not reached[id] then
			add(
				out,
				"warning",
				"graph.unreachable",
				"graph.nodes[" .. entry.index .. "]",
				label(entry) .. " is not reachable from a trigger node; it never runs",
				"connect its in pin to the flow of an OnPlay, OnMarker or OnEvent node"
			)
		end
	end
	return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- canConnect
-- ─────────────────────────────────────────────────────────────────────────────

-- Would a new link from -> to be valid? (true) or (false, reason, code).
function Validator.canConnect(graph: any, def: any, from: any, to: any): (boolean, string?, string?)
	if type(graph) ~= "table" then
		return false, "there is no graph", "graph.type"
	end
	local index = Model.index(graph)
	local components = Model.components(def)
	local result = checkLink(index, components, from, to)
	if not result.ok then
		return false, result.message, result.code
	end
	local fromNode, fromPin = Model.parseRef(from)
	local toNode, toPin = Model.parseRef(to)
	local fromKey = (fromNode :: string) .. "." .. (fromPin :: string)
	local toKey = (toNode :: string) .. "." .. (toPin :: string)
	if fromNode == toNode then
		return false, "a node cannot be connected to itself", "graph.cycle"
	end
	for _, link in index.links do
		if link.fromNode == fromNode and link.fromPin == fromPin and link.toNode == toNode and link.toPin == toPin then
			return false, fromKey .. " is already connected to " .. toKey, "graph.link_duplicate"
		end
	end
	if index.linkCount >= Constants.MAX_GRAPH_LINKS then
		return false,
			"the graph already has " .. index.linkCount .. " links (limit " .. Constants.MAX_GRAPH_LINKS .. ")",
			"graph.limit"
	end
	if (result.toPin :: Pin).kind ~= "exec" then
		for _, link in index.links do
			if link.toNode == toNode and link.toPin == toPin then
				return false,
					"input " .. toKey .. " is already connected (from " .. link.fromNode .. "." .. link.fromPin .. ")",
					"graph.input_multiple"
			end
		end
	end
	if (result.fromPin :: Pin).kind == "exec" then
		for _, link in index.links do
			if link.fromNode == fromNode and link.fromPin == fromPin then
				return false,
					"exec output "
						.. fromKey
						.. " is already connected (to "
						.. link.toNode
						.. "."
						.. link.toPin
						.. "); use a Parallel or Sequence node to fan out",
					"graph.output_multiple"
			end
		end
	end
	local adjacency = Model.adjacency(index)
	local path = Model.path(adjacency, toNode :: string, fromNode :: string)
	if path then
		-- New link from -> to closes the existing path to -> ... -> from.
		table.insert(path, 1, fromNode :: string)
		return false, "would create a cycle: " .. table.concat(path, " -> "), "graph.cycle"
	end
	return true, nil, nil
end

return Validator
