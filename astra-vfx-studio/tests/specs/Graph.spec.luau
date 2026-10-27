--!strict
-- Core/Graph: node types, validation, live connection checks, cycle detection, compilation and unrolling.
return function(T: any, use: (string) -> any, _ctx: any)
	local Graph = use("AstraVFX.Core.Graph")
	local Codec = use("AstraVFX.Core.Codec")
	local Constants = use("AstraVFX.Core.Constants")
	local Easing = use("AstraVFX.Core.Easing")
	local Json = use("AstraVFX.Core.Json")
	local NodeTypes = Graph.NodeTypes

	-- ── Builders ─────────────────────────────────────────────────────────────────────────────────────────

	local function N(id: string, nodeType: string, params: { [string]: any }?): any
		return { id = id, type = nodeType, params = params }
	end

	local function L(from: string, to: string): any
		return { from = from, to = to }
	end

	-- Builds a mixed-type row (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end

	local function G(nodes: { any }, links: { any }?): any
		return { nodes = nodes, links = links or {} }
	end

	local function makeDef(): any
		return {
			schemaVersion = 1,
			id = "fx",
			name = "FX",
			duration = 5,
			palette = { primary = "#FF0000" },
			markers = {
				{ id = "m1", time = 1.5, label = "Impact", event = "Impact" } :: any,
				{ id = "m2", time = 0.5, label = "Charge" },
			},
			components = {
				{ id = "g1", name = "Group", type = "group" },
				{ id = "fx", name = "Sparks", type = "particles" },
				{ id = "snd", name = "Boom", type = "sound" },
				{ id = "bolt", name = "Bolt", type = "lightning" },
				-- a type that is never registered (other component types are added over time)
				{ id = "cx", name = "Custom", type = "customThing" },
			},
		}
	end

	local DEF = makeDef()

	local function codes(diags: { any }): { string }
		local out = {}
		for _, d in diags do
			table.insert(out, d.code)
		end
		return out
	end

	local function count(diags: { any }, code: string): number
		local n = 0
		for _, d in diags do
			if d.code == code then
				n += 1
			end
		end
		return n
	end

	local function errors(diags: { any }): { any }
		local out = {}
		for _, d in diags do
			if d.severity == "error" then
				table.insert(out, d)
			end
		end
		return out
	end

	local function run(
		graph: any,
		def: any?,
		trigger: any?,
		startTime: number?,
		seed: number?,
		cycle: number?,
		effect: any?
	)
		local compiled = Graph.compile(graph, def or DEF)
		return Graph.run(compiled, trigger or { kind = "play" }, startTime or 0, seed or 1, cycle or 0, effect)
	end

	-- Actions as compact { time, action, componentId, count } rows (times rounded to 1e-9).
	local function rows(list: { any }): { any }
		local out = {}
		for _, a in list do
			table.insert(out, {
				math.floor(a.time * 1e9 + 0.5) / 1e9,
				a.action,
				a.componentId or a.name or "",
				a.count or 0,
			})
		end
		return out
	end

	local function emitCounts(list: { any }): { number }
		local out = {}
		for _, a in list do
			if a.action == "emit" then
				table.insert(out, a.count)
			end
		end
		return out
	end

	-- Deterministic pseudo-random numbers in [0, 1) (no math.random).
	local function lcg(seed: number): () -> number
		local state = seed
		return function(): number
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
	end

	-- OnPlay -> <flow nodes...> -> Emit fx (count n). `chain` lists node defs already linked in order by "in"/"out".
	local function playEmit(emitParams: { [string]: any }?): any
		local params = emitParams or { target = "fx" }
		return G({ N("p", "OnPlay"), N("e", "Emit", params) }, { L("p.out", "e.in") })
	end

	-- ── NodeTypes ────────────────────────────────────────────────────────────────────────────────────────

	T.describe("Graph.NodeTypes", function()
		local EXPECTED = {
			"OnPlay",
			"OnMarker",
			"OnEvent",
			"Delay",
			"Sequence",
			"Parallel",
			"Loop",
			"RandomBranch",
			"RandomNumber",
			"Number",
			"Vector",
			"Color",
			"Component",
			"Math",
			"Emit",
			"SetEnabled",
			"Tween",
			"SetProperty",
			"FireEvent",
			"PlaySound",
			"Regenerate",
		}

		T.it("lists every node type of the contract exactly once", function()
			local names = {}
			for _, nodeType in NodeTypes.list() do
				table.insert(names, nodeType.type)
			end
			T.expect(names).toEqual(EXPECTED)
			for _, name in EXPECTED do
				T.expect(NodeTypes.get(name)).never.toBeNil()
			end
		end)

		T.it("returns nil for unknown or non-string types", function()
			T.expect(NodeTypes.get("onplay")).toBeNil()
			T.expect(NodeTypes.get("Nope")).toBeNil()
			T.expect(NodeTypes.get(42)).toBeNil()
			T.expect(NodeTypes.get(nil)).toBeNil()
			T.expect(NodeTypes.get({})).toBeNil()
		end)

		T.it("declares well-formed pins, categories and params", function()
			local kinds = {}
			for _, k in NodeTypes.PIN_KINDS do
				kinds[k] = true
			end
			local categories = {}
			for _, c in NodeTypes.CATEGORIES do
				categories[c] = true
			end
			for _, nodeType in NodeTypes.list() do
				T.expect(categories[nodeType.category]).toBe(true)
				T.expect(type(nodeType.displayName)).toBe("string")
				T.expect(type(nodeType.description)).toBe("string")
				local seen = {}
				for _, pin in nodeType.inputs do
					T.expect(kinds[pin.kind]).toBe(true)
					T.expect(seen[pin.name]).toBeNil()
					seen[pin.name] = true
				end
				for _, pin in nodeType.outputs do
					T.expect(kinds[pin.kind]).toBe(true)
					T.expect(seen[pin.name]).toBeNil()
					seen[pin.name] = true
				end
				local hasExecIn = false
				for _, pin in nodeType.inputs do
					if pin.kind == "exec" then
						hasExecIn = true
						T.expect(pin.name).toBe("in")
					end
				end
				T.expect(hasExecIn).toBe(not nodeType.pure and nodeType.trigger == nil)
				if nodeType.trigger then
					T.expect(#nodeType.inputs).toBe(0)
				end
			end
		end)

		T.it("has param defaults that pass their own checks", function()
			for _, nodeType in NodeTypes.list() do
				for _, spec in nodeType.params do
					local special = nodeType.special[spec.name]
					if special == "easing" then
						T.expect((Easing.check(spec.default))).toBe(true)
					elseif special ~= "channelValue" then
						local ok, problem = Codec.check(spec.kind, spec.default, spec)
						if not ok then
							T.fail(nodeType.type .. "." .. spec.name .. ": " .. tostring(problem))
						end
					end
				end
			end
		end)

		T.it("gives every data input a param of the same name (unlinked fallback)", function()
			for _, nodeType in NodeTypes.list() do
				for _, pin in nodeType.inputs do
					if pin.kind ~= "exec" then
						T.expect(NodeTypes.paramSpec(nodeType, pin.name)).never.toBeNil()
					end
				end
			end
		end)

		T.it("restricts action target pins and params to component types", function()
			local function allowed(nodeType: string): any
				local nt = NodeTypes.get(nodeType)
				local pin = NodeTypes.findPin(nt, {}, "target")
				T.expect(pin.kind).toBe("component")
				local spec = NodeTypes.paramSpec(nt, "target")
				T.expect(spec.kind).toBe("componentRef")
				T.expect(spec.componentTypes).toEqual(pin.componentTypes)
				return pin.componentTypes
			end
			T.expect(allowed("Emit")).toEqual({ "particles" })
			T.expect(allowed("PlaySound")).toEqual({ "sound" })
			T.expect(allowed("Regenerate")).toEqual({ "lightning" })
			T.expect(allowed("SetEnabled")).toBeNil()
			T.expect(allowed("Tween")).toBeNil()
			T.expect(allowed("SetProperty")).toBeNil()
		end)

		T.it("declares the documented pins of Loop and Tween", function()
			local loop = NodeTypes.get("Loop")
			local names = {}
			for _, pin in loop.outputs do
				table.insert(names, pin.name .. ":" .. pin.kind)
			end
			T.expect(names).toEqual({ "body:exec", "completed:exec", "index:number" })
			local tween = NodeTypes.get("Tween")
			names = {}
			for _, pin in tween.outputs do
				table.insert(names, pin.name)
			end
			T.expect(names).toEqual({ "out", "done" })
			T.expect(NodeTypes.findPin(tween, {}, "value").kind).toBe("any")
		end)

		T.it("resolves variadic outputs from the count param", function()
			local seq = NodeTypes.get("Sequence")
			T.expect(#NodeTypes.outputs(seq, { count = 3 })).toBe(3)
			T.expect(NodeTypes.outputs(seq, { count = 3 })[3].name).toBe("then3")
			T.expect(#NodeTypes.outputs(seq, {})).toBe(2) -- default
			T.expect(#NodeTypes.outputs(seq, { count = 99 })).toBe(8) -- clamped
			T.expect(#NodeTypes.outputs(seq, { count = 0 / 0 })).toBe(2)
			T.expect(#NodeTypes.outputs(seq, { count = "x" })).toBe(2)
			T.expect(#NodeTypes.outputs(seq, nil)).toBe(2)
			local pin, direction, active = NodeTypes.findPin(seq, { count = 3 }, "then5")
			T.expect(pin.name).toBe("then5")
			T.expect(direction).toBe("output")
			T.expect(active).toBe(false)
			T.expect(NodeTypes.count(NodeTypes.get("Delay"), {})).toBeNil()
			T.expect(#NodeTypes.outputs(NodeTypes.get("Parallel"), { count = 8 })).toBe(8)
			T.expect(#NodeTypes.outputs(NodeTypes.get("RandomBranch"), { count = 5 })).toBe(5)
		end)

		T.it("finds pins by direction and rejects unknown names", function()
			local delay = NodeTypes.get("Delay")
			local _, d1 = NodeTypes.findPin(delay, {}, "in")
			local _, d2 = NodeTypes.findPin(delay, {}, "out")
			T.expect(d1).toBe("input")
			T.expect(d2).toBe("output")
			T.expect((NodeTypes.findPin(delay, {}, "nope"))).toBeNil()
			T.expect((NodeTypes.findPin(delay, {}, 5))).toBeNil()
		end)

		T.it("is frozen", function()
			local emit = NodeTypes.get("Emit")
			T.expect(function()
				emit.type = "X"
			end).toThrow()
			T.expect(function()
				table.insert(emit.inputs, { name = "x", kind = "exec" })
			end).toThrow()
			T.expect(function()
				emit.params[1].default = "nope"
			end).toThrow()
			-- list() returns a copy: mutating it does not affect the registry
			local list = NodeTypes.list()
			table.remove(list, 1)
			T.expect(#NodeTypes.list()).toBe(21)
		end)
	end)

	-- ── parseRef ─────────────────────────────────────────────────────────────────────────────────────────

	T.describe("Graph.parseRef", function()
		T.it("splits node.pin references", function()
			local node, pin = Graph.parseRef("emit_1.out")
			T.expect(node).toBe("emit_1")
			T.expect(pin).toBe("out")
			node, pin = Graph.parseRef("seq-2.then8")
			T.expect(node).toBe("seq-2")
			T.expect(pin).toBe("then8")
		end)

		T.it("rejects malformed references", function()
			local bad: { any } = {
				"a",
				".out",
				"a.",
				"a.b.c",
				"a b.out",
				"a.1x",
				"a.o-ut",
				string.rep("x", 65) .. ".out",
				"",
				5,
				true,
				{},
			}
			for _, ref in bad do
				local node, pin = Graph.parseRef(ref)
				T.expect(node).toBeNil()
				T.expect(pin).toBeNil()
			end
			T.expect((Graph.parseRef(nil :: any))).toBeNil()
		end)
	end)

	-- ── validate ─────────────────────────────────────────────────────────────────────────────────────────

	T.describe("Graph.validate", function()
		T.it("accepts a valid graph without diagnostics", function()
			local g = G({
				N("p", "OnPlay"),
				N("c", "Component", { component = "fx" }),
				N("n", "Number", { value = 5 }),
				N("e", "Emit"),
			}, { L("p.out", "e.in"), L("c.component", "e.target"), L("n.value", "e.count") })
			T.expect(Graph.validate(g, DEF)).toEqual({})
		end)

		T.it("returns no diagnostics for a nil graph and accepts empty graphs", function()
			T.expect(Graph.validate(nil, DEF)).toEqual({})
			T.expect(Graph.validate(G({}, {}), DEF)).toEqual({})
			T.expect(Graph.validate({ nodes = Json.EMPTY_OBJECT, links = Json.EMPTY_OBJECT }, DEF)).toEqual({})
			T.expect(Graph.validate({}, DEF)).toEqual({}) -- missing lists are treated as empty
		end)

		T.it("reports wrong top-level types", function()
			for _, garbage in { 5, "graph", true } :: { any } do
				local diags = Graph.validate(garbage, DEF)
				T.expect(codes(diags)).toEqual({ "graph.type" })
				T.expect(diags[1].path).toBe("graph")
			end
			local diags = Graph.validate({ nodes = 5, links = { x = 1 } }, DEF)
			T.expect(codes(diags)).toEqual({ "graph.type", "graph.type" })
			T.expect(diags[1].path).toBe("graph.nodes")
			T.expect(diags[2].path).toBe("graph.links")
			diags = Graph.validate({ nodes = { [1] = N("a", "OnPlay"), [3] = N("b", "OnPlay") } }, DEF)
			T.expect(codes(diags)).toEqual({ "graph.type" })
		end)

		T.it("reports non-object nodes and links", function()
			local diags = Graph.validate({ nodes = R(5, "x"), links = { true } }, DEF)
			T.expect(codes(diags)).toEqual({ "graph.node_invalid", "graph.node_invalid", "graph.link_invalid" })
			T.expect(diags[2].path).toBe("graph.nodes[2]")
			T.expect(diags[3].path).toBe("graph.links[1]")
		end)

		T.it("reports invalid and duplicate node ids", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("p", "OnPlay"), N("bad id", "OnPlay"), { type = "OnPlay" } :: any }),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.node_duplicate", "graph.node_id", "graph.node_id" })
			T.expect(diags[1].path).toBe("graph.nodes[2].id")
			T.expect(diags[1].message).toContain("graph.nodes[1]")
			T.expect(diags[3].message).toContain("no id")
			local long = Graph.validate(G({ N(string.rep("a", 65), "OnPlay") }), DEF)
			T.expect(codes(long)).toEqual({ "graph.node_id" })
		end)

		T.it("reports unknown node types with a suggestion", function()
			local diags = Graph.validate(G({ N("p", "OnPlay"), N("d", "delay"), N("x", "Teleport") }), DEF)
			T.expect(codes(diags)).toEqual({ "graph.node_type", "graph.node_type" })
			T.expect(diags[1].path).toBe("graph.nodes[2].type")
			T.expect(diags[1].hint).toContain('"Delay"')
			T.expect(diags[2].hint).toContain("OnPlay")
		end)

		T.it("checks node positions and the params container", function()
			local diags = Graph.validate(
				G({
					{ id = "p", type = "OnPlay", position = { 10, 20 } },
					{ id = "q", type = "OnPlay", position = R(1, "x") },
					{ id = "r", type = "OnPlay", params = 5 },
				}),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.node_position", "graph.param_type" })
			T.expect(diags[1].path).toBe("graph.nodes[2].position")
			T.expect(diags[2].path).toBe("graph.nodes[3].params")
		end)

		T.it("checks param types and ranges with Codec", function()
			local g = G({
				N("p", "OnPlay"),
				N("d1", "Delay", { seconds = "soon" }),
				N("d2", "Delay", { seconds = 100 }),
				N("l1", "Loop", { count = Constants.MAX_LOOP_ITERATIONS + 1 }),
				N("l2", "Loop", { count = 0 }),
				N("l3", "Loop", { count = 2.5 }),
				N("s", "Sequence", { count = 9 }),
				N("m", "Math", { op = "mod" }),
				N("e", "Emit", { target = "fx", count = Constants.MAX_EMIT_COUNT + 1 }),
			}, {
				L("p.out", "d1.in"),
				L("d1.out", "d2.in"),
				L("d2.out", "l1.in"),
				L("l1.completed", "l2.in"),
				L("l2.completed", "l3.in"),
				L("l3.completed", "s.in"),
				L("s.then1", "e.in"),
			})
			local diags = Graph.validate(g, DEF)
			T.expect(codes(diags)).toEqual({
				"graph.param_type",
				"graph.param_range",
				"graph.param_range",
				"graph.param_range",
				"graph.param_type",
				"graph.param_range",
				"graph.param_range",
				"graph.param_range",
			})
			T.expect(diags[1].path).toBe("graph.nodes[2].params.seconds")
			T.expect(diags[7].path).toBe("graph.nodes[8].params.op")
			for _, d in diags do
				T.expect(d.severity).toBe("error")
			end
		end)

		T.it("checks easing params with Easing.check", function()
			local function easing(value: any): { any }
				return Graph.validate(
					G({ N("p", "OnPlay"), N("t", "Tween", { target = "g1", channel = "position", easing = value }) }, {
						L("p.out", "t.in"),
					}),
					DEF
				)
			end
			T.expect(easing("Quad.InOut")).toEqual({})
			T.expect(easing({ bezier = { 0.25, 0.1, 0.25, 1 } })).toEqual({})
			T.expect(codes(easing("quad"))).toEqual({ "graph.param_type" })
			T.expect(codes(easing({ bezier = { 2, 0, 0, 1 } }))).toEqual({ "graph.param_type" })
			T.expect(codes(easing(5))).toEqual({ "graph.param_type" })
		end)

		T.it("warns about unknown params", function()
			local diags = Graph.validate(
				G({
					N("p", "OnPlay", { foo = 1 }),
					N("r", "RandomBranch", { weights = { 1, 2 } }),
					N("d", "Delay", { Seconds = 1 }),
				}, { L("p.out", "r.in"), L("r.out1", "d.in") }),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.param_unknown", "graph.param_unknown", "graph.param_unknown" })
			for _, d in diags do
				T.expect(d.severity).toBe("warning")
			end
			T.expect(diags[1].path).toBe("graph.nodes[1].params.foo")
			T.expect(diags[2].hint).toContain("weight1")
			T.expect(diags[3].hint).toContain('"seconds"')
		end)

		T.it("checks component references and their types", function()
			local diags = Graph.validate(
				G({
					N("p", "OnPlay"),
					N("par", "Parallel", { count = 4 }),
					N("e1", "Emit", { target = "missing" }),
					N("e2", "Emit", { target = "g1" }),
					N("s", "PlaySound", { target = "fx" }),
					N("r", "Regenerate", { target = "bolt" }),
				}, {
					L("p.out", "par.in"),
					L("par.out1", "e1.in"),
					L("par.out2", "e2.in"),
					L("par.out3", "s.in"),
					L("par.out4", "r.in"),
				}),
				DEF
			)
			T.expect(codes(diags))
				.toEqual({ "graph.component_missing", "graph.component_type", "graph.component_type" })
			T.expect(diags[1].path).toBe("graph.nodes[3].params.target")
			T.expect(diags[1].componentId).toBe("missing")
			T.expect(diags[2].message).toContain("particles")
			T.expect(diags[3].message).toContain("sound")
		end)

		T.it("checks the component type of a linked Component node", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("c", "Component", { component = "g1" }), N("e", "Emit") }, {
					L("p.out", "e.in"),
					L("c.component", "e.target"),
				}),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.component_type" })
			T.expect(diags[1].path).toBe("graph.links[2]")
			local missing = Graph.validate(G({ N("c", "Component", { component = "nope" }), N("d", "Component") }), DEF)
			T.expect(codes(missing)).toEqual({ "graph.component_missing", "graph.component_missing" })
			T.expect(missing[1].severity).toBe("error")
			T.expect(missing[2].severity).toBe("warning")
		end)

		T.it("warns about action nodes without a target", function()
			local diags = Graph.validate(playEmit({}), DEF)
			T.expect(codes(diags)).toEqual({ "graph.target_missing" })
			T.expect(diags[1].severity).toBe("warning")
			T.expect(diags[1].path).toBe("graph.nodes[2].params.target")
			T.expect(Graph.validate(playEmit({ target = "" }), DEF)[1].code).toBe("graph.target_missing")
		end)

		T.it("checks OnMarker markers", function()
			local function marker(params: any): { any }
				return Graph.validate(G({ N("m", "OnMarker", params) }), DEF)
			end
			T.expect(marker({ marker = "m1" })).toEqual({})
			local missing = marker({ marker = "zz" })
			T.expect(codes(missing)).toEqual({ "graph.marker_missing" })
			T.expect(missing[1].severity).toBe("error")
			local empty = marker({})
			T.expect(codes(empty)).toEqual({ "graph.marker_missing" })
			T.expect(empty[1].severity).toBe("warning")
			T.expect(codes(marker({ marker = 5 }))).toEqual({ "graph.param_type" })
			-- without a definition no marker exists
			T.expect(codes(Graph.validate(G({ N("m", "OnMarker", { marker = "m1" }) }), nil))).toEqual({
				"graph.marker_missing",
			})
		end)

		T.it("checks event names of OnEvent and FireEvent", function()
			T.expect(Graph.validate(G({ N("e", "OnEvent", { name = "Detonate" }) }), DEF)).toEqual({})
			local bad = Graph.validate(G({ N("e", "OnEvent", { name = "1abc" }) }), DEF)
			T.expect(codes(bad)).toEqual({ "graph.event_name" })
			T.expect(bad[1].severity).toBe("error")
			local empty = Graph.validate(G({ N("e", "OnEvent") }), DEF)
			T.expect(codes(empty)).toEqual({ "graph.event_name" })
			T.expect(empty[1].severity).toBe("warning")
			local fire = Graph.validate(G({ N("p", "OnPlay"), N("f", "FireEvent") }, { L("p.out", "f.in") }), DEF)
			T.expect(codes(fire)).toEqual({ "graph.event_name" })
			T.expect(fire[1].severity).toBe("warning")
			local fireBad = Graph.validate(
				G({ N("p", "OnPlay"), N("f", "FireEvent", { name = "has space" }) }, { L("p.out", "f.in") }),
				DEF
			)
			T.expect(codes(fireBad)).toEqual({ "graph.event_name" })
			T.expect(fireBad[1].severity).toBe("error")
		end)

		T.it("checks Tween / SetProperty channels against the target type", function()
			local function tween(params: any): { any }
				return Graph.validate(G({ N("p", "OnPlay"), N("t", "Tween", params) }, { L("p.out", "t.in") }), DEF)
			end
			T.expect(tween({ target = "g1", channel = "position", value = { 1, 2, 3 } })).toEqual({})
			local unknown = tween({ target = "g1", channel = "transparency" })
			T.expect(codes(unknown)).toEqual({ "graph.channel_unknown" })
			T.expect(unknown[1].severity).toBe("error")
			T.expect(unknown[1].hint).toContain("position")
			local cased = tween({ target = "g1", channel = "Position" })
			T.expect(cased[1].hint).toContain('"position"')
			local missing = tween({ target = "g1" })
			T.expect(codes(missing)).toEqual({ "graph.channel_missing" })
			T.expect(missing[1].severity).toBe("warning")
			-- unregistered component type: the channel cannot be verified -> info, no error
			local unverified = tween({ target = "cx", channel = "transparency", value = 0.5 })
			T.expect(codes(unverified)).toEqual({ "graph.channel_unverified" })
			T.expect(unverified[1].severity).toBe("info")
		end)

		T.it("checks the value param against the channel kind", function()
			local function setProp(params: any): { any }
				return Graph.validate(
					G({ N("p", "OnPlay"), N("s", "SetProperty", params) }, { L("p.out", "s.in") }),
					DEF
				)
			end
			T.expect(setProp({ target = "g1", channel = "rotation", value = { 0, 90, 0 } })).toEqual({})
			T.expect(codes(setProp({ target = "g1", channel = "position", value = "#FF0000" }))).toEqual({
				"graph.param_type",
			})
			T.expect(codes(setProp({ target = "g1", channel = "position", value = { 1, 2 } }))).toEqual({
				"graph.param_type",
			})
			-- unresolvable channel: any channel-like JSON value is accepted, garbage is not
			T.expect(codes(setProp({ target = "cx", channel = "rate", value = 5 }))).toEqual({
				"graph.channel_unverified",
			})
			T.expect(codes(setProp({ target = "cx", channel = "rate", value = { a = 1 } }))).toEqual({
				"graph.param_type",
				"graph.channel_unverified",
			})
		end)

		T.it("checks palette references of colour values", function()
			T.expect(Graph.validate(G({ N("c", "Color", { value = "$primary" }) }), DEF)).toEqual({})
			local missing = Graph.validate(G({ N("c", "Color", { value = "$secondary" }) }), DEF)
			T.expect(codes(missing)).toEqual({ "graph.param_ref" })
			T.expect(missing[1].path).toBe("graph.nodes[1].params.value")
			T.expect(missing[1].message).toContain("secondary")
			-- inferred colour channel value
			local setProp = Graph.validate(
				G({ N("p", "OnPlay"), N("s", "SetProperty", { target = "cx", channel = "tint", value = "$nope" }) }, {
					L("p.out", "s.in"),
				}),
				DEF
			)
			T.expect(codes(setProp)).toEqual({ "graph.param_ref", "graph.channel_unverified" })
		end)

		T.it("warns when the target type does not handle the action", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("s", "SetEnabled", { target = "g1" }) }, { L("p.out", "s.in") }),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.action_unsupported" })
			T.expect(diags[1].severity).toBe("warning")
			T.expect(diags[1].componentId).toBe("g1")
			-- unregistered types are not second-guessed
			T.expect(
				Graph.validate(
					G({ N("p", "OnPlay"), N("s", "SetEnabled", { target = "cx" }) }, { L("p.out", "s.in") }),
					DEF
				)
			).toEqual({})
			-- a restricted target of the wrong type is reported once (component_type), not twice
			local wrong =
				Graph.validate(G({ N("p", "OnPlay"), N("e", "Emit", { target = "g1" }) }, { L("p.out", "e.in") }), DEF)
			T.expect(codes(wrong)).toEqual({ "graph.component_type" })
		end)

		T.it("reports malformed refs, unknown nodes and unknown pins", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("e", "Emit", { target = "fx" }) }, {
					L("p.out", "e.in"),
					{ from = "p", to = "e.in" },
					{ from = "p.out", to = 7 },
					L("ghost.out", "e.in"),
					L("p.out", "ghost.in"),
					L("p.nope", "e.in"),
					L("p.out", "e.nope"),
				}),
				DEF
			)
			T.expect(codes(diags)).toEqual({
				"graph.link_ref",
				"graph.link_ref",
				"graph.link_node",
				"graph.link_node",
				"graph.link_pin",
				"graph.link_pin",
			})
			T.expect(diags[1].path).toBe("graph.links[2].from")
			T.expect(diags[2].path).toBe("graph.links[3].to")
			T.expect(diags[3].path).toBe("graph.links[4].from")
			T.expect(diags[4].path).toBe("graph.links[5].to")
			T.expect(diags[5].path).toBe("graph.links[6].from")
			T.expect(diags[5].hint).toContain("out")
			T.expect(diags[6].path).toBe("graph.links[7].to")
			T.expect(diags[6].hint).toContain("target")
		end)

		T.it("rejects links to inactive variadic outputs", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("s", "Sequence", { count = 3 }), N("e", "Emit", { target = "fx" }) }, {
					L("p.out", "s.in"),
					L("s.then5", "e.in"),
				}),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.link_pin", "graph.unreachable" })
			T.expect(diags[1].message).toContain("count = 3")
		end)

		T.it("checks link direction", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("d", "Delay"), N("e", "Emit", { target = "fx" }) }, {
					L("p.out", "d.in"),
					L("e.in", "d.out"), -- reversed
					L("d.in", "e.in"), -- starts at an input
					L("d.out", "p.out"), -- ends at an output
				}),
				DEF
			)
			T.expect(codes(diags)).toEqual({
				"graph.link_direction",
				"graph.link_direction",
				"graph.link_direction",
				"graph.unreachable",
			})
			T.expect(diags[1].path).toBe("graph.links[2]")
			T.expect(diags[1].hint).toContain("swap")
			T.expect(diags[2].path).toBe("graph.links[3].from")
			T.expect(diags[3].path).toBe("graph.links[4].to")
		end)

		T.it("rejects incompatible pin kinds without implicit conversion", function()
			local diags = Graph.validate(
				G({
					N("p", "OnPlay"),
					N("par", "Parallel", { count = 2 }),
					N("n", "Number", { value = 1 }),
					N("v", "Vector"),
					N("e", "Emit", { target = "fx" }),
					N("t", "Tween", { target = "g1", channel = "position" }),
				}, {
					L("p.out", "par.in"),
					L("par.out1", "e.in"),
					L("par.out2", "t.in"),
					L("n.value", "e.target"), -- number -> component
					L("n.value", "t.value"), -- number -> vector3 (position channel)
					L("p.out", "e.count"), -- exec -> number
					L("n.value", "e.in"), -- number -> exec
					L("v.value", "e.count"), -- vector3 -> number
				}),
				DEF
			)
			T.expect(codes(diags)).toEqual({
				"graph.link_kind",
				"graph.link_kind",
				"graph.link_kind",
				"graph.link_kind",
				"graph.link_kind",
			})
			T.expect(diags[1].message).toContain("(number)")
			T.expect(diags[1].message).toContain("(component)")
			T.expect(diags[2].hint).toContain("Vector node")
			T.expect(diags[3].hint).toContain("exec")
		end)

		T.it("lets any-kind pins accept every data kind", function()
			local function valueFrom(source: any, target: string): { any }
				return Graph.validate(
					G({ N("p", "OnPlay"), source, N("s", "SetProperty", { target = target, channel = "custom" }) }, {
						L("p.out", "s.in"),
						L(source.id .. "." .. (if source.type == "Component" then "component" else "value"), "s.value"),
					}),
					DEF
				)
			end
			-- unregistered target type: the value pin stays "any"
			for _, source in { N("n", "Number"), N("v", "Vector"), N("c", "Color"), N("r", "RandomNumber") } do
				T.expect(codes(errors(valueFrom(source, "cx")))).toEqual({})
			end
			-- registered: Vector -> position is fine, Color -> position is not
			local ok = Graph.validate(
				G({ N("p", "OnPlay"), N("v", "Vector"), N("t", "Tween", { target = "g1", channel = "position" }) }, {
					L("p.out", "t.in"),
					L("v.value", "t.value"),
				}),
				DEF
			)
			T.expect(ok).toEqual({})
			local bad = Graph.validate(
				G({ N("p", "OnPlay"), N("c", "Color"), N("t", "Tween", { target = "g1", channel = "position" }) }, {
					L("p.out", "t.in"),
					L("c.value", "t.value"),
				}),
				DEF
			)
			T.expect(codes(bad)).toEqual({ "graph.link_kind" })
		end)

		T.it("allows at most one link per data input", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("a", "Number"), N("b", "Number"), N("d", "Delay") }, {
					L("p.out", "d.in"),
					L("a.value", "d.seconds"),
					L("b.value", "d.seconds"),
				}),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.input_multiple" })
			T.expect(diags[1].path).toBe("graph.links[3].to")
			T.expect(diags[1].message).toContain("graph.links[2]")
		end)

		T.it("allows at most one link per exec output but many per exec input", function()
			local fanOut = Graph.validate(
				G({ N("p", "OnPlay"), N("a", "Emit", { target = "fx" }), N("b", "Emit", { target = "fx" }) }, {
					L("p.out", "a.in"),
					L("p.out", "b.in"),
				}),
				DEF
			)
			T.expect(codes(fanOut)).toEqual({ "graph.output_multiple", "graph.unreachable" })
			T.expect(fanOut[1].path).toBe("graph.links[2].from")
			T.expect(fanOut[1].hint).toContain("Parallel")
			local fanIn = Graph.validate(
				G({ N("p", "OnPlay"), N("par", "Parallel"), N("e", "Emit", { target = "fx" }) }, {
					L("p.out", "par.in"),
					L("par.out1", "e.in"),
					L("par.out2", "e.in"),
				}),
				DEF
			)
			T.expect(fanIn).toEqual({})
			-- data outputs may feed many inputs
			local dataFan = Graph.validate(
				G({ N("p", "OnPlay"), N("n", "Number"), N("d", "Delay"), N("e", "Emit", { target = "fx" }) }, {
					L("p.out", "d.in"),
					L("d.out", "e.in"),
					L("n.value", "d.seconds"),
					L("n.value", "e.count"),
				}),
				DEF
			)
			T.expect(dataFan).toEqual({})
		end)

		T.it("reports duplicate links once", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("e", "Emit", { target = "fx" }) }, { L("p.out", "e.in"), L("p.out", "e.in") }),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.link_duplicate" })
			T.expect(diags[1].path).toBe("graph.links[2]")
		end)

		T.it("detects exec cycles", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("a", "Delay"), N("b", "Delay") }, {
					L("p.out", "a.in"),
					L("a.out", "b.in"),
					L("b.out", "a.in"),
				}),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.cycle" })
			T.expect(diags[1].message).toBe("cycle: a -> b -> a")
			T.expect(diags[1].path).toBe("graph.links[3]")
		end)

		T.it("detects self-loops", function()
			local diags = Graph.validate(
				G({ N("p", "OnPlay"), N("a", "Delay") }, { L("p.out", "a.in"), L("a.out", "a.in") }),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.cycle" })
			T.expect(diags[1].message).toBe("cycle: a -> a")
			T.expect(diags[1].path).toBe("graph.links[2]")
		end)

		T.it("detects data cycles", function()
			local diags = Graph.validate(
				G({ N("a", "Math"), N("b", "Math") }, { L("a.result", "b.a"), L("b.result", "a.b") }),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.cycle" })
			T.expect(diags[1].message).toBe("cycle: a -> b -> a")
		end)

		T.it("detects longer and mixed exec/data cycles, one diagnostic per cycle group", function()
			local long = Graph.validate(
				G({ N("m1", "Math"), N("m2", "Math"), N("m3", "Math"), N("m4", "Math"), N("m5", "Math") }, {
					L("m1.result", "m2.a"),
					L("m2.result", "m3.a"),
					L("m3.result", "m4.a"),
					L("m4.result", "m5.a"),
					L("m5.result", "m1.a"),
				}),
				DEF
			)
			T.expect(codes(long)).toEqual({ "graph.cycle" })
			T.expect(long[1].message).toBe("cycle: m1 -> m2 -> m3 -> m4 -> m5 -> m1")
			-- Emit -> Loop (exec), Loop.index -> Math -> Emit.count (data)
			local mixed = Graph.validate(
				G({ N("p", "OnPlay"), N("e", "Emit", { target = "fx" }), N("l", "Loop"), N("m", "Math") }, {
					L("p.out", "e.in"),
					L("e.out", "l.in"),
					L("l.index", "m.a"),
					L("m.result", "e.count"),
				}),
				DEF
			)
			T.expect(codes(mixed)).toEqual({ "graph.cycle" })
			T.expect(mixed[1].message).toContain("e -> l -> m -> e")
			-- two independent cycles
			local two = Graph.validate(
				G({ N("a", "Math"), N("b", "Math"), N("c", "Math"), N("d", "Math") }, {
					L("a.result", "b.a"),
					L("b.result", "a.a"),
					L("c.result", "d.a"),
					L("d.result", "c.a"),
				}),
				DEF
			)
			T.expect(count(two, "graph.cycle")).toBe(2)
		end)

		T.it("warns about exec nodes unreachable from a trigger", function()
			local diags = Graph.validate(
				G({ N("e", "Emit", { target = "fx" }), N("n", "Number"), N("d", "Delay") }, { L("d.out", "e.in") }),
				DEF
			)
			T.expect(codes(diags)).toEqual({ "graph.unreachable", "graph.unreachable" })
			T.expect(diags[1].path).toBe("graph.nodes[1]")
			T.expect(diags[2].path).toBe("graph.nodes[3]")
			for _, d in diags do
				T.expect(d.severity).toBe("warning")
			end
		end)

		T.it("enforces the node and link limits", function()
			local nodes = {}
			for i = 1, Constants.MAX_GRAPH_NODES + 1 do
				nodes[i] = N("n" .. i, "Number")
			end
			local diags = Graph.validate(G(nodes), DEF)
			T.expect(codes(diags)).toEqual({ "graph.limit" })
			T.expect(diags[1].path).toBe("graph.nodes")
			local links = {}
			for i = 1, Constants.MAX_GRAPH_LINKS + 1 do
				links[i] = L("a.value", "b.a")
			end
			local tooMany = Graph.validate(G({ N("a", "Number"), N("b", "Math") }, links), DEF)
			T.expect(tooMany[1].code).toBe("graph.limit")
			T.expect(tooMany[1].path).toBe("graph.links")
			-- exactly at the limit is fine
			table.remove(nodes)
			T.expect(Graph.validate(G(nodes), DEF)).toEqual({})
		end)

		T.it("produces well-formed, deterministic diagnostics", function()
			local g = G({
				N("p", "OnPlay", { x = 1, y = 2, z = 3 }),
				N("p", "Nope"),
				N("e", "Emit", { target = "g1", count = -1 }),
			}, { L("p.out", "e.in"), L("p.out", "e.in"), L("e.in", "p.out"), { from = 1 } })
			local a = Graph.validate(g, DEF)
			local b = Graph.validate(g, DEF)
			T.expect(a).toEqual(b)
			T.expect(#a).toBeGreaterThan(5)
			for _, d in a do
				T.expect(d.severity == "error" or d.severity == "warning" or d.severity == "info").toBe(true)
				T.expect(d.code).toMatch("^graph%.[a-z_]+$")
				T.expect(d.path).toMatch("^graph")
				T.expect(type(d.message)).toBe("string")
			end
			-- unknown params are reported in sorted order
			local unknown = {}
			for _, d in a do
				if d.code == "graph.param_unknown" then
					table.insert(unknown, d.path)
				end
			end
			T.expect(unknown)
				.toEqual({ "graph.nodes[1].params.x", "graph.nodes[1].params.y", "graph.nodes[1].params.z" })
		end)

		T.it("does not mutate its inputs", function()
			local g = G({ N("p", "OnPlay"), N("e", "Emit", { target = "fx", count = 3 }) }, { L("p.out", "e.in") })
			local snapshot = Json.encode(g)
			local defSnapshot = Json.encode(DEF)
			Graph.validate(g, DEF)
			Graph.canConnect(g, DEF, "p.out", "e.in")
			Graph.compile(g, DEF)
			T.expect(Json.encode(g)).toBe(snapshot)
			T.expect(Json.encode(DEF)).toBe(defSnapshot)
		end)
	end)

	-- ── canConnect ───────────────────────────────────────────────────────────────────────────────────────

	T.describe("Graph.canConnect", function()
		local function base(): any
			return G({
				N("p", "OnPlay"),
				N("a", "Delay"),
				N("b", "Delay"),
				N("n", "Number"),
				N("c", "Component", { component = "g1" }),
				N("e", "Emit"),
				N("par", "Parallel", { count = 2 }),
			}, { L("p.out", "a.in"), L("a.out", "b.in"), L("n.value", "b.seconds") })
		end

		T.it("accepts a valid new link", function()
			local ok, reason, code = Graph.canConnect(base(), DEF, "b.out", "e.in")
			T.expect(ok).toBe(true)
			T.expect(reason).toBeNil()
			T.expect(code).toBeNil()
			T.expect((Graph.canConnect(base(), DEF, "n.value", "e.count"))).toBe(true)
			-- exec inputs take many links
			T.expect((Graph.canConnect(base(), DEF, "par.out1", "b.in"))).toBe(true)
		end)

		T.it("rejects malformed refs, unknown nodes and pins", function()
			local function check(from: any, to: any, expectedCode: string)
				local ok, reason, code = Graph.canConnect(base(), DEF, from, to)
				T.expect(ok).toBe(false)
				T.expect(type(reason)).toBe("string")
				T.expect(code).toBe(expectedCode)
			end
			check("b", "e.in", "graph.link_ref")
			check("b.out", 5, "graph.link_ref")
			check("ghost.out", "e.in", "graph.link_node")
			check("b.out", "e.nope", "graph.link_pin")
			check("par.out3", "e.in", "graph.link_pin")
		end)

		T.it("rejects wrong directions and kinds with a reason", function()
			local ok, reason, code = Graph.canConnect(base(), DEF, "e.in", "b.out")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.link_direction")
			T.expect(reason).toContain("reversed")
			ok, reason, code = Graph.canConnect(base(), DEF, "n.value", "e.target")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.link_kind")
			T.expect(reason).toContain("number")
			T.expect(reason).toContain("component")
		end)

		T.it("rejects components of the wrong type", function()
			local ok, reason, code = Graph.canConnect(base(), DEF, "c.component", "e.target")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.component_type")
			T.expect(reason).toContain("particles")
		end)

		T.it("rejects occupied data inputs and exec outputs", function()
			local _, reason1, code1 = Graph.canConnect(base(), DEF, "n.value", "a.seconds")
			T.expect(code1).toBeNil() -- free
			T.expect(reason1).toBeNil()
			local ok, reason, code = Graph.canConnect(base(), DEF, "n.value", "b.seconds")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.link_duplicate")
			T.expect(reason).toContain("already connected")
			local g = base()
			table.insert(g.nodes, N("n2", "Number"))
			ok, reason, code = Graph.canConnect(g, DEF, "n2.value", "b.seconds")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.input_multiple")
			ok, reason, code = Graph.canConnect(base(), DEF, "p.out", "e.in")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.output_multiple")
			T.expect(reason).toContain("Parallel")
		end)

		T.it("rejects links that would create a cycle", function()
			local ok, reason, code = Graph.canConnect(base(), DEF, "b.out", "a.in")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.cycle")
			T.expect(reason).toBe("would create a cycle: b -> a -> b")
			ok, reason, code = Graph.canConnect(base(), DEF, "b.out", "p.out")
			T.expect(code).toBe("graph.link_direction")
			-- self connection
			ok, reason, code = Graph.canConnect(G({ N("m", "Math") }), DEF, "m.result", "m.a")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.cycle")
			-- data path closing a cycle through exec links: b.out -> ... and Loop.index back
			local g = G({ N("p", "OnPlay"), N("l", "Loop"), N("m", "Math"), N("e", "Emit", { target = "fx" }) }, {
				L("p.out", "l.in"),
				L("l.body", "e.in"),
				L("l.index", "m.a"),
			})
			T.expect((Graph.canConnect(g, DEF, "m.result", "e.count"))).toBe(true)
			ok, reason, code = Graph.canConnect(g, DEF, "m.result", "l.count")
			T.expect(code).toBe("graph.cycle")
			T.expect(reason).toBe("would create a cycle: m -> l -> m")
		end)

		T.it("resolves the value kind through a linked Component node", function()
			local g = G({
				N("p", "OnPlay"),
				N("c", "Component", { component = "g1" }),
				N("t", "Tween", { channel = "position" }),
				N("n", "Number"),
				N("v", "Vector"),
			}, { L("p.out", "t.in"), L("c.component", "t.target") })
			local ok, reason, code = Graph.canConnect(g, DEF, "n.value", "t.value")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.link_kind")
			T.expect(reason).toContain("vector3")
			T.expect((Graph.canConnect(g, DEF, "v.value", "t.value"))).toBe(true)
			T.expect(Graph.pinKind(g, DEF, "t.value")).toBe("vector3")
			-- the channel is checked against the linked component's type
			local bad = G({
				N("p", "OnPlay"),
				N("c", "Component", { component = "g1" }),
				N("t", "Tween", { channel = "transparency" }),
			}, { L("p.out", "t.in"), L("c.component", "t.target") })
			T.expect(codes(Graph.validate(bad, DEF))).toEqual({ "graph.channel_unknown" })
		end)

		T.it("enforces the link limit", function()
			local links = {}
			for i = 1, Constants.MAX_GRAPH_LINKS do
				links[i] = L("x.value", "y.a")
			end
			local g = G({ N("x", "Number"), N("y", "Math"), N("z", "Math") }, links)
			local ok, _, code = Graph.canConnect(g, DEF, "x.value", "z.a")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("graph.limit")
		end)

		T.it("never throws on garbage", function()
			for _, g in { nil, 5, "x", {}, { nodes = 5 }, { nodes = { 1, 2 }, links = { 3 } } } :: { any } do
				local ok, reason = Graph.canConnect(g, nil, "a.out", "b.in")
				T.expect(ok).toBe(false)
				T.expect(type(reason)).toBe("string")
			end
		end)
	end)

	-- ── findCycle ────────────────────────────────────────────────────────────────────────────────────────

	T.describe("Graph.findCycle", function()
		T.it("returns nil for acyclic graphs", function()
			T.expect(Graph.findCycle(playEmit())).toBeNil()
			T.expect(Graph.findCycle(G({}))).toBeNil()
		end)

		T.it("returns the node ids of a cycle in order", function()
			local g = G({ N("p", "OnPlay"), N("a", "Delay"), N("b", "Delay"), N("c", "Delay") }, {
				L("p.out", "a.in"),
				L("a.out", "b.in"),
				L("b.out", "c.in"),
				L("c.out", "a.in"),
			})
			T.expect(Graph.findCycle(g)).toEqual({ "a", "b", "c" })
			T.expect(Graph.findCycle(G({ N("a", "Delay") }, { L("a.out", "a.in") }))).toEqual({ "a" })
			T.expect(
				Graph.findCycle(G({ N("x", "Math"), N("y", "Math") }, { L("x.result", "y.a"), L("y.result", "x.a") }))
			)
				.toEqual({ "x", "y" })
		end)

		T.it("ignores links to missing nodes and never throws", function()
			T.expect(Graph.findCycle(G({ N("a", "Delay") }, { L("a.out", "ghost.in"), L("ghost.out", "a.in") })))
				.toBeNil()
			for _, g in { nil, 5, "x", { nodes = "x" }, { nodes = { 1 }, links = { 2 } } } :: { any } do
				T.expect(Graph.findCycle(g)).toBeNil()
			end
		end)
	end)

	-- ── compile / run ────────────────────────────────────────────────────────────────────────────────────

	T.describe("Graph.run", function()
		T.it("OnPlay -> Emit schedules one emit at the start time", function()
			local list, info = run(playEmit({ target = "fx", count = 7 }))
			T.expect(#list).toBe(1)
			local a = list[1]
			T.expect(a.time).toBe(0)
			T.expect(a.action).toBe("emit")
			T.expect(a.componentId).toBe("fx")
			T.expect(a.count).toBe(7)
			T.expect(a.source).toBe("graph")
			T.expect(a.sourceId).toBe("e")
			T.expect(a.order).toBe(1)
			T.expect(list.truncated).toBe(false)
			T.expect(info.truncated).toBe(false)
			T.expect(info.actions).toBe(1)
			T.expect(info.diagnostics).toEqual({})
		end)

		T.it("uses defaults for missing params", function()
			local list = run(playEmit({ target = "fx" }))
			T.expect(list[1].count).toBe(10)
		end)

		T.it("returns an empty list for graphs without matching triggers", function()
			T.expect(#run(G({}))).toBe(0)
			T.expect(#run(playEmit(), DEF, { kind = "event", id = "Nope" })).toBe(0)
			T.expect(#run(playEmit(), DEF, { kind = "marker", id = "m1" })).toBe(0)
			T.expect(#run(playEmit(), DEF, { kind = "event" })).toBe(0)
		end)

		T.it("follows Delay chains", function()
			local g = G({
				N("p", "OnPlay"),
				N("d1", "Delay", { seconds = 0.5 }),
				N("d2", "Delay", { seconds = 0.25 }),
				N("e", "Emit", { target = "fx" }),
			}, {
				L("p.out", "d1.in"),
				L("d1.out", "d2.in"),
				L("d2.out", "e.in"),
			})
			local list = run(g)
			T.expect(rows(list)).toEqual({ R(0.75, "emit", "fx", 10) })
			-- startTime offsets everything
			local later = run(g, DEF, { kind = "play" }, 2)
			T.expect(rows(later)).toEqual({ R(2.75, "emit", "fx", 10) })
		end)

		T.it("Delay seconds can come from a data link and are clamped to the param range", function()
			local function delayFrom(value: number): any
				return G({
					N("p", "OnPlay"),
					N("n", "Number", { value = value }),
					N("d", "Delay"),
					N("e", "Emit", { target = "fx" }),
				}, {
					L("p.out", "d.in"),
					L("d.out", "e.in"),
					L("n.value", "d.seconds"),
				})
			end
			T.expect(run(delayFrom(1.25))[1].time).toBe(1.25)
			T.expect(run(delayFrom(-3))[1].time).toBe(0)
			T.expect(run(delayFrom(1e9))[1].time).toBe(Constants.MAX_DURATION)
		end)

		T.it("Sequence fires then1..N at t + (i - 1) * interval", function()
			local g = G({
				N("p", "OnPlay"),
				N("s", "Sequence", { count = 3, interval = 0.2 }),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
				N("e3", "Emit", { target = "fx", count = 3 }),
			}, { L("p.out", "s.in"), L("s.then1", "e1.in"), L("s.then2", "e2.in"), L("s.then3", "e3.in") })
			T.expect(rows(run(g, DEF, { kind = "play" }, 1))).toEqual({
				R(1, "emit", "fx", 1),
				R(1.2, "emit", "fx", 2),
				R(1.4, "emit", "fx", 3),
			})
		end)

		T.it("Sequence with interval 0 keeps pin order", function()
			local g = G({
				N("p", "OnPlay"),
				N("s", "Sequence", { count = 2, interval = 0 }),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
			}, { L("p.out", "s.in"), L("s.then2", "e2.in"), L("s.then1", "e1.in") })
			T.expect(emitCounts(run(g))).toEqual({ 1, 2 })
		end)

		T.it("Parallel fires every output at the same time in pin order, depth first", function()
			local g = G({
				N("p", "OnPlay"),
				N("par", "Parallel", { count = 3 }),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e1b", "Emit", { target = "fx", count = 11 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
				N("e3", "Emit", { target = "fx", count = 3 }),
			}, {
				L("p.out", "par.in"),
				L("par.out3", "e3.in"),
				L("par.out1", "e1.in"),
				L("e1.out", "e1b.in"),
				L("par.out2", "e2.in"),
			})
			local list = run(g)
			T.expect(emitCounts(list)).toEqual({ 1, 11, 2, 3 })
			for i, a in list do
				T.expect(a.time).toBe(0)
				T.expect(a.order).toBe(i)
			end
		end)

		T.it("keeps pin order at equal times reached later through delays", function()
			-- The same structure must order its equal-time actions identically whether the branches meet at the
			-- trigger time or later (last-writer-wins actions such as SetProperty depend on it).
			local function counts(seconds: number): { number }
				local g = G({
					N("p", "OnPlay"),
					N("par", "Parallel", { count = 3 }),
					N("d1", "Delay", { seconds = seconds }),
					N("d2", "Delay", { seconds = seconds }),
					N("d3a", "Delay", { seconds = seconds / 2 }),
					N("d3b", "Delay", { seconds = seconds / 2 }),
					N("e1", "Emit", { target = "fx", count = 1 }),
					N("e2", "Emit", { target = "fx", count = 2 }),
					N("e3", "Emit", { target = "fx", count = 3 }),
				}, {
					L("p.out", "par.in"),
					L("par.out1", "d1.in"),
					L("d1.out", "e1.in"),
					L("par.out2", "d2.in"),
					L("d2.out", "e2.in"),
					L("par.out3", "d3a.in"),
					L("d3a.out", "d3b.in"),
					L("d3b.out", "e3.in"),
				})
				return emitCounts(run(g))
			end
			T.expect(counts(0)).toEqual({ 1, 2, 3 })
			T.expect(counts(0.5)).toEqual({ 1, 2, 3 })
		end)

		T.it("runs Loop iterations in index order (and completed last) when their flows meet later", function()
			local g = G({
				N("p", "OnPlay"),
				N("l", "Loop", { count = 3, interval = 0 }),
				N("d", "Delay", { seconds = 1 }),
				N("dc", "Delay", { seconds = 1 }),
				N("m", "Math", { op = "add", b = 1 }),
				N("e", "Emit", { target = "fx" }),
				N("c", "Emit", { target = "fx", count = 99 }),
			}, {
				L("p.out", "l.in"),
				L("l.body", "d.in"),
				L("d.out", "e.in"),
				L("l.index", "m.a"),
				L("m.result", "e.count"),
				L("l.completed", "dc.in"),
				L("dc.out", "c.in"),
			})
			local list = run(g)
			T.expect(emitCounts(list)).toEqual({ 1, 2, 3, 99 })
			for _, a in list do
				T.expect(a.time).toBe(1)
			end
		end)

		T.it("runs a Tween's out flow before its done flow when both reach the same later time", function()
			local g = G({
				N("p", "OnPlay"),
				N("tw", "Tween", { target = "cx", channel = "rate", value = 1, duration = 0.5 }),
				N("d", "Delay", { seconds = 0.5 }),
				N("eOut", "Emit", { target = "fx", count = 1 }),
				N("eDone", "Emit", { target = "fx", count = 2 }),
			}, {
				L("p.out", "tw.in"),
				L("tw.out", "d.in"),
				L("d.out", "eOut.in"),
				L("tw.done", "eDone.in"),
			})
			T.expect(emitCounts(run(g))).toEqual({ 1, 2 })
		end)

		T.it("Loop fires body per iteration with a 0-based index and completed after count * interval", function()
			local g = G({
				N("p", "OnPlay"),
				N("l", "Loop", { count = 4, interval = 0.5 }),
				N("m", "Math", { op = "add", b = 1 }),
				N("e", "Emit", { target = "fx" }),
				N("done", "FireEvent", { name = "LoopDone" }),
			}, {
				L("p.out", "l.in"),
				L("l.body", "e.in"),
				L("l.index", "m.a"),
				L("m.result", "e.count"),
				L("l.completed", "done.in"),
			})
			T.expect(rows(run(g))).toEqual({
				R(0, "emit", "fx", 1),
				R(0.5, "emit", "fx", 2),
				R(1, "emit", "fx", 3),
				R(1.5, "emit", "fx", 4),
				R(2, "fire", "LoopDone", 0),
			})
		end)

		T.it("Loop with interval 0 runs every body before completed", function()
			local g = G({
				N("p", "OnPlay"),
				N("l", "Loop", { count = 3, interval = 0 }),
				N("e", "Emit", { target = "fx", count = 1 }),
				N("c", "Emit", { target = "fx", count = 99 }),
			}, { L("p.out", "l.in"), L("l.body", "e.in"), L("l.completed", "c.in") })
			T.expect(emitCounts(run(g))).toEqual({ 1, 1, 1, 99 })
		end)

		T.it("nested loops multiply: 3 x 4 = 12 emits at the right times with both indices", function()
			local g = G({
				N("p", "OnPlay"),
				N("outer", "Loop", { count = 3, interval = 1 }),
				N("inner", "Loop", { count = 4, interval = 0.1 }),
				N("mul", "Math", { op = "mul", b = 10 }),
				N("add", "Math", { op = "add" }),
				N("one", "Math", { op = "add", b = 1 }),
				N("e", "Emit", { target = "fx" }),
			}, {
				L("p.out", "outer.in"),
				L("outer.body", "inner.in"),
				L("inner.body", "e.in"),
				L("outer.index", "mul.a"),
				L("mul.result", "add.a"),
				L("inner.index", "add.b"),
				L("add.result", "one.a"),
				L("one.result", "e.count"),
			})
			local list = run(g)
			T.expect(#list).toBe(12)
			local i = 0
			for outer = 0, 2 do
				for inner = 0, 3 do
					i += 1
					T.expect(list[i].time).toBeCloseTo(outer + inner * 0.1, 1e-9)
					T.expect(list[i].count).toBe(outer * 10 + inner + 1)
				end
			end
		end)

		T.it("Loop count and interval can come from data links (clamped)", function()
			local function loopWith(countValue: number): any
				return G({
					N("p", "OnPlay"),
					N("n", "Number", { value = countValue }),
					N("l", "Loop", { interval = 0.1 }),
					N("e", "Emit", { target = "fx", count = 1 }),
				}, { L("p.out", "l.in"), L("n.value", "l.count"), L("l.body", "e.in") })
			end
			T.expect(#run(loopWith(5))).toBe(5)
			T.expect(#run(loopWith(4.6))).toBe(5) -- rounded
			T.expect(#run(loopWith(0))).toBe(1) -- clamped to the param minimum
			T.expect(#run(loopWith(1e6))).toBe(Constants.MAX_LOOP_ITERATIONS)
		end)

		T.it("Loop.index outside the loop body is 0", function()
			local g = G({
				N("p", "OnPlay"),
				N("l", "Loop", { count = 3, interval = 0.1 }),
				N("m", "Math", { op = "add", b = 5 }),
				N("e", "Emit", { target = "fx" }),
			}, { L("p.out", "l.in"), L("l.completed", "e.in"), L("l.index", "m.a"), L("m.result", "e.count") })
			local list = run(g)
			T.expect(#list).toBe(1)
			T.expect(list[1].count).toBe(5)
			T.expect(list[1].time).toBeCloseTo(0.3, 1e-9)
		end)

		T.it("Emit count comes from links, is rounded, clamped and quality-scaled", function()
			local function emitWith(value: number, effect: any?): any
				local g = G(
					{ N("p", "OnPlay"), N("n", "Number", { value = value }), N("e", "Emit", { target = "fx" }) },
					{
						L("p.out", "e.in"),
						L("n.value", "e.count"),
					}
				)
				return run(g, DEF, nil, 0, 1, 0, effect)
			end
			T.expect(emitWith(12.4)[1].count).toBe(12)
			T.expect(emitWith(1e9)[1].count).toBe(Constants.MAX_EMIT_COUNT)
			T.expect(#emitWith(0)).toBe(0) -- nothing to emit
			T.expect(#emitWith(-5)).toBe(0)
			T.expect(emitWith(20, { quality = { countScale = 0.35 } })[1].count).toBe(7)
			T.expect(emitWith(1, { quality = { countScale = 0.35 } })[1].count).toBe(1) -- min 1
		end)

		T.it("SetEnabled schedules enable / disable", function()
			local function setEnabled(params: any): any
				return run(G({ N("p", "OnPlay"), N("s", "SetEnabled", params) }, { L("p.out", "s.in") }))
			end
			T.expect(rows(setEnabled({ target = "fx" }))).toEqual({ R(0, "enable", "fx", 0) })
			T.expect(rows(setEnabled({ target = "fx", enabled = false }))).toEqual({ R(0, "disable", "fx", 0) })
			T.expect(rows(setEnabled({ target = "g1", enabled = true }))).toEqual({ R(0, "enable", "g1", 0) })
		end)

		T.it("Tween schedules a decoded payload and fires done after the duration", function()
			local g = G({
				N("p", "OnPlay"),
				N("t", "Tween", {
					target = "g1",
					channel = "position",
					value = { 1, 2, 3 },
					duration = 0.25,
					easing = "Quad.InOut",
				}),
				N("e", "Emit", { target = "fx", count = 1 }),
				N("f", "FireEvent", { name = "Started" }),
			}, { L("p.out", "t.in"), L("t.done", "e.in"), L("t.out", "f.in") })
			local list = run(g, DEF, nil, 1)
			T.expect(#list).toBe(3)
			local tween = list[1]
			T.expect(tween.action).toBe("tween")
			T.expect(tween.time).toBe(1)
			T.expect(tween.componentId).toBe("g1")
			T.expect(tween.channel).toBe("position")
			T.expect(tween.value).toBeA("Vector3")
			T.expect(tween.value).toBeCloseTo(Vector3.new(1, 2, 3), 1e-6)
			T.expect(tween.duration).toBe(0.25)
			T.expect(type(tween.easing)).toBe("function")
			local reference = Easing.get("Quad", "InOut")
			for _, x in { 0, 0.1, 0.3, 0.5, 0.8, 1 } do
				T.expect(tween.easing(x)).toBeCloseTo(reference(x), 1e-12)
			end
			T.expect(rows(list))
				.toEqual({ R(1, "tween", "g1", 0), R(1, "fire", "Started", 0), R(1.25, "emit", "fx", 1) })
		end)

		T.it("Tween defaults: Linear easing, kind zero value, clamped duration", function()
			local g = G(
				{ N("p", "OnPlay"), N("t", "Tween", { target = "g1", channel = "rotation" }) },
				{ L("p.out", "t.in") }
			)
			local tween = run(g)[1]
			T.expect(tween.value).toBe(Vector3.zero)
			T.expect(tween.duration).toBe(0.5)
			T.expect(tween.easing(0.3)).toBeCloseTo(0.3, 1e-12)
			local long = run(G({
				N("p", "OnPlay"),
				N("n", "Number", { value = 500 }),
				N("t", "Tween", { target = "g1", channel = "rotation" }),
			}, {
				L("p.out", "t.in"),
				L("n.value", "t.duration"),
			}))[1]
			T.expect(long.duration).toBe(Constants.MAX_DURATION)
		end)

		T.it("Tween / SetProperty values come from links and scale length channels", function()
			local function tweenFrom(channel: string, effect: any?): any
				local g = G({
					N("p", "OnPlay"),
					N("v", "Vector", { value = { 1, 2, 3 } }),
					N("c", "Component", { component = "g1" }),
					N("t", "Tween", { channel = channel }),
				}, { L("p.out", "t.in"), L("v.value", "t.value"), L("c.component", "t.target") })
				return run(g, DEF, nil, 0, 1, 0, effect)[1]
			end
			T.expect(tweenFrom("position").value).toBeCloseTo(Vector3.new(1, 2, 3), 1e-6)
			T.expect(tweenFrom("position", { scale = 2 }).value).toBeCloseTo(Vector3.new(2, 4, 6), 1e-6)
			-- rotation is not a length channel
			T.expect(tweenFrom("rotation", { scale = 2 }).value).toBeCloseTo(Vector3.new(1, 2, 3), 1e-6)
		end)

		T.it("SetProperty schedules a set action", function()
			local g = G({
				N("p", "OnPlay"),
				N("s", "SetProperty", { target = "g1", channel = "rotation", value = { 0, 90, 0 } }),
			}, {
				L("p.out", "s.in"),
			})
			local list = run(g)
			T.expect(#list).toBe(1)
			T.expect(list[1].action).toBe("set")
			T.expect(list[1].channel).toBe("rotation")
			T.expect(list[1].value).toBeCloseTo(Vector3.new(0, 90, 0), 1e-6)
			T.expect(list[1].duration).toBeNil()
			T.expect(list[1].easing).toBeNil()
		end)

		T.it("infers the value kind for unregistered target types and resolves palette colours", function()
			local function setValue(value: any, effect: any?): any
				local g = G(
					{ N("p", "OnPlay"), N("s", "SetProperty", { target = "cx", channel = "tint", value = value }) },
					{
						L("p.out", "s.in"),
					}
				)
				return run(g, DEF, nil, 0, 1, 0, effect)[1]
			end
			T.expect(setValue("#00FF00").value).toBe(Color3.fromRGB(0, 255, 0))
			T.expect(setValue("$primary").value).toBe(Color3.fromRGB(255, 0, 0))
			T.expect(setValue("$primary", { palette = { primary = Color3.new(0, 0, 1) } }).value)
				.toBe(Color3.new(0, 0, 1))
			T.expect(setValue(0.5).value).toBe(0.5)
			T.expect(setValue(true).value).toBe(true)
			T.expect(setValue({ 1, 2, 3 }).value).toBeCloseTo(Vector3.new(1, 2, 3), 1e-6)
			T.expect(setValue("$unknown")).toBeNil() -- cannot be decoded: skipped
			T.expect(setValue({ a = 1 })).toBeNil()
		end)

		T.it("Color nodes resolve palette references", function()
			local function colorOf(value: string, effect: any?): any
				local g = G({
					N("p", "OnPlay"),
					N("c", "Color", { value = value }),
					N("s", "SetProperty", { target = "cx", channel = "tint" }),
				}, { L("p.out", "s.in"), L("c.value", "s.value") })
				return run(g, DEF, nil, 0, 1, 0, effect)[1].value
			end
			T.expect(colorOf("#336699")).toBe(Color3.fromRGB(0x33, 0x66, 0x99))
			T.expect(colorOf("$primary")).toBe(Color3.fromRGB(255, 0, 0))
			T.expect(colorOf("$primary", { palette = { primary = Color3.new(0, 1, 0) } })).toBe(Color3.new(0, 1, 0))
			T.expect(colorOf("$missing")).toBe(Color3.new(1, 1, 1)) -- falls back to the param default
		end)

		T.it("rejects linked values of the wrong kind at runtime (no implicit conversion)", function()
			-- the graph is invalid (validate rejects it) but compile/run must stay safe: the link is dropped
			local g = G({
				N("p", "OnPlay"),
				N("n", "Number", { value = 5 }),
				N("t", "Tween", { target = "g1", channel = "position", value = { 7, 7, 7 } }),
			}, { L("p.out", "t.in"), L("n.value", "t.value") })
			T.expect(codes(Graph.validate(g, DEF))).toEqual({ "graph.link_kind" })
			local list = run(g)
			T.expect(list[1].value).toBeCloseTo(Vector3.new(7, 7, 7), 1e-6)
		end)

		T.it("Math implements every operation and maps non-finite results to 0", function()
			local function math3(op: string, a: number, b: number, t: number?): number
				local g = G({
					N("p", "OnPlay"),
					N("m", "Math", { op = op, a = a, b = b, t = t or 0.5 }),
					N("s", "SetProperty", { target = "cx", channel = "rate" }),
				}, { L("p.out", "s.in"), L("m.result", "s.value") })
				return run(g)[1].value
			end
			T.expect(math3("add", 2, 3)).toBe(5)
			T.expect(math3("sub", 2, 3)).toBe(-1)
			T.expect(math3("mul", 2, 3)).toBe(6)
			T.expect(math3("div", 3, 2)).toBe(1.5)
			T.expect(math3("div", 3, 0)).toBe(0)
			T.expect(math3("min", 2, 3)).toBe(2)
			T.expect(math3("max", 2, 3)).toBe(3)
			T.expect(math3("pow", 2, 10)).toBe(1024)
			T.expect(math3("pow", -8, 0.5)).toBe(0)
			T.expect(math3("pow", 10, 400)).toBe(0)
			T.expect(math3("lerp", 10, 20, 0.25)).toBe(12.5)
		end)

		T.it("Math inputs fall back to params when unlinked and use links when present", function()
			local g = G({
				N("p", "OnPlay"),
				N("x", "Number", { value = 4 }),
				N("m", "Math", { op = "mul", a = 100, b = 3 }),
				N("s", "SetProperty", { target = "cx", channel = "rate" }),
			}, { L("p.out", "s.in"), L("x.value", "m.a"), L("m.result", "s.value") })
			T.expect(run(g)[1].value).toBe(12)
		end)

		T.it("FireEvent forwards a name; invalid names are skipped but the flow continues", function()
			local g = G({
				N("p", "OnPlay"),
				N("f1", "FireEvent", { name = "Boom" }),
				N("f2", "FireEvent", { name = "not valid" }),
				N("e", "Emit", { target = "fx", count = 1 }),
			}, { L("p.out", "f1.in"), L("f1.out", "f2.in"), L("f2.out", "e.in") })
			T.expect(rows(run(g))).toEqual({ R(0, "fire", "Boom", 0), R(0, "emit", "fx", 1) })
			local list = run(g)
			T.expect(list[1].name).toBe("Boom")
			T.expect(list[1].componentId).toBeNil()
		end)

		T.it("PlaySound and Regenerate target their component types", function()
			local g = G({
				N("p", "OnPlay"),
				N("par", "Parallel", { count = 3 }),
				N("s", "PlaySound", { target = "snd" }),
				N("r", "Regenerate", { target = "bolt" }),
				N("bad", "PlaySound", { target = "fx" }), -- wrong type: skipped at runtime
			}, { L("p.out", "par.in"), L("par.out1", "s.in"), L("par.out2", "r.in"), L("par.out3", "bad.in") })
			T.expect(rows(run(g))).toEqual({ R(0, "play", "snd", 0), R(0, "regenerate", "bolt", 0) })
		end)

		T.it("skips actions whose target is missing but keeps the flow going", function()
			local g = G({
				N("p", "OnPlay"),
				N("e1", "Emit", { target = "ghost" }),
				N("e2", "Emit"),
				N("e3", "Emit", { target = "fx", count = 3 }),
			}, { L("p.out", "e1.in"), L("e1.out", "e2.in"), L("e2.out", "e3.in") })
			T.expect(rows(run(g))).toEqual({ R(0, "emit", "fx", 3) })
			-- with an effect, targets are checked against effect.byId (e.g. removed by minQuality)
			local effect = { byId = { other = { type = "particles" } } }
			T.expect(#run(playEmit({ target = "fx" }), DEF, nil, 0, 1, 0, effect)).toBe(0)
			local present = { byId = { fx = { type = "particles" } } }
			T.expect(#run(playEmit({ target = "fx" }), DEF, nil, 0, 1, 0, present)).toBe(1)
		end)

		T.it("Component nodes feed action targets", function()
			local g = G(
				{ N("p", "OnPlay"), N("c", "Component", { component = "fx" }), N("e", "Emit", { target = "ignored" }) },
				{
					L("p.out", "e.in"),
					L("c.component", "e.target"),
				}
			)
			T.expect(rows(run(g))).toEqual({ R(0, "emit", "fx", 10) })
		end)

		T.it("OnMarker flows run at the marker time", function()
			local g = G({
				N("m", "OnMarker", { marker = "m1" }),
				N("d", "Delay", { seconds = 0.1 }),
				N("e", "Emit", { target = "fx", count = 2 }),
			}, { L("m.out", "d.in"), L("d.out", "e.in") })
			local list = run(g, DEF, { kind = "marker", id = "m1" }, 1.5)
			T.expect(#list).toBe(1)
			T.expect(list[1].time).toBeCloseTo(1.6, 1e-9)
			-- a non-finite start time falls back to the marker's own time
			local fallback = run(g, DEF, { kind = "marker", id = "m1" }, 0 / 0)
			T.expect(fallback[1].time).toBeCloseTo(1.6, 1e-9)
			T.expect(#run(g, DEF, { kind = "marker", id = "m2" }, 0.5)).toBe(0)
		end)

		T.it("OnEvent flows run at the runtime trigger time", function()
			local g = G({
				N("ev", "OnEvent", { name = "Detonate" }),
				N("ev2", "OnEvent", { name = "Other" }),
				N("e", "Emit", { target = "fx", count = 4 }),
				N("f", "FireEvent", { name = "Other" }),
			}, { L("ev.out", "e.in"), L("ev2.out", "f.in") })
			local list = run(g, DEF, { kind = "event", id = "Detonate" }, 2.5)
			T.expect(rows(list)).toEqual({ R(2.5, "emit", "fx", 4) })
			T.expect(rows(run(g, DEF, { kind = "event", id = "Other" }, 3))).toEqual({ R(3, "fire", "Other", 0) })
			T.expect(#run(g, DEF, { kind = "event", id = "detonate" }, 3)).toBe(0) -- case-sensitive
		end)

		T.it("runs every matching trigger node in node order", function()
			local g = G({
				N("p1", "OnPlay"),
				N("p2", "OnPlay"),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
			}, { L("p2.out", "e2.in"), L("p1.out", "e1.in") })
			T.expect(emitCounts(run(g))).toEqual({ 1, 2 })
		end)

		T.it("returns actions sorted by time with order 1..n", function()
			local g = G({
				N("p", "OnPlay"),
				N("par", "Parallel", { count = 3 }),
				N("d1", "Delay", { seconds = 0.7 }),
				N("d2", "Delay", { seconds = 0.2 }),
				N("l", "Loop", { count = 5, interval = 0.3 }),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
				N("e3", "Emit", { target = "fx", count = 3 }),
			}, {
				L("p.out", "par.in"),
				L("par.out1", "d1.in"),
				L("d1.out", "e1.in"),
				L("par.out2", "d2.in"),
				L("d2.out", "e2.in"),
				L("par.out3", "l.in"),
				L("l.body", "e3.in"),
			})
			local list = run(g)
			T.expect(#list).toBe(7)
			for i = 2, #list do
				T.expect(list[i].time >= list[i - 1].time).toBe(true)
			end
			for i, a in list do
				T.expect(a.order).toBe(i)
			end
		end)
	end)

	-- ── Randomness ───────────────────────────────────────────────────────────────────────────────────────

	T.describe("Graph randomness", function()
		local function branchGraph(params: { [string]: any }?): any
			local p = params or { count = 2 }
			return G({
				N("p", "OnPlay"),
				N("l", "Loop", { count = 60, interval = 0.01 }),
				N("r", "RandomBranch", p),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
				N("e3", "Emit", { target = "fx", count = 3 }),
			}, {
				L("p.out", "l.in"),
				L("l.body", "r.in"),
				L("r.out1", "e1.in"),
				L("r.out2", "e2.in"),
				L("r.out3", "e3.in"),
			})
		end

		T.it("RandomBranch is deterministic for the same seed and cycle", function()
			local compiled = Graph.compile(branchGraph(), DEF)
			local a = Graph.run(compiled, { kind = "play" }, 0, 42, 0)
			local b = Graph.run(compiled, { kind = "play" }, 0, 42, 0)
			T.expect(emitCounts(a)).toEqual(emitCounts(b))
			T.expect(#a).toBe(60)
			-- a fresh compile gives the same result too
			T.expect(emitCounts(run(branchGraph(), DEF, nil, 0, 42, 0))).toEqual(emitCounts(a))
			local ones, twos = 0, 0
			for _, c in emitCounts(a) do
				if c == 1 then
					ones += 1
				elseif c == 2 then
					twos += 1
				end
			end
			T.expect(ones + twos).toBe(60)
			T.expect(ones).toBeGreaterThan(10)
			T.expect(twos).toBeGreaterThan(10)
		end)

		T.it("RandomBranch differs across seeds and cycles", function()
			local compiled = Graph.compile(branchGraph(), DEF)
			local base = emitCounts(Graph.run(compiled, { kind = "play" }, 0, 42, 0))
			T.expect(emitCounts(Graph.run(compiled, { kind = "play" }, 0, 43, 0))).never.toEqual(base)
			T.expect(emitCounts(Graph.run(compiled, { kind = "play" }, 0, 42, 1))).never.toEqual(base)
			T.expect(emitCounts(Graph.run(compiled, { kind = "play" }, 0, 42, 2))).never.toEqual(base)
		end)

		T.it("RandomBranch honours weights", function()
			local always2 = emitCounts(run(branchGraph({ count = 3, weight1 = 0, weight2 = 1, weight3 = 0 })))
			for _, c in always2 do
				T.expect(c).toBe(2)
			end
			-- all weights zero: uniform over the active outputs
			local uniform = emitCounts(run(branchGraph({ count = 3, weight1 = 0, weight2 = 0, weight3 = 0 })))
			local seen = {}
			for _, c in uniform do
				seen[c] = true
			end
			T.expect(seen[1] and seen[2] and seen[3]).toBe(true)
			-- inactive outputs are never chosen
			for _, c in emitCounts(run(branchGraph({ count = 2, weight3 = 1000 }))) do
				T.expect(c < 3).toBe(true)
			end
			-- weights 1 : 3 over 400 draws
			local g = G({
				N("p", "OnPlay"),
				N("lo", "Loop", { count = 4, interval = 1 }),
				N("l", "Loop", { count = 100, interval = 0.001 }),
				N("r", "RandomBranch", { count = 2, weight1 = 1, weight2 = 3 }),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
			}, {
				L("p.out", "lo.in"),
				L("lo.body", "l.in"),
				L("l.body", "r.in"),
				L("r.out1", "e1.in"),
				L("r.out2", "e2.in"),
			})
			local twos = 0
			local counts = emitCounts(run(g, DEF, nil, 0, 7, 0))
			for _, c in counts do
				if c == 2 then
					twos += 1
				end
			end
			T.expect(#counts).toBe(400)
			T.expect(twos / 400).toBeGreaterThan(0.65)
			T.expect(twos / 400).toBeLessThan(0.85)
		end)

		T.it("RandomNumber stays in [min, max), is deterministic and differs across seeds and cycles", function()
			local function numbers(seed: number, cycle: number, min: number?, max: number?): { number }
				local g = G({
					N("p", "OnPlay"),
					N("l", "Loop", { count = 50, interval = 0.01 }),
					N("rn", "RandomNumber", { min = min or 2, max = max or 5 }),
					N("s", "SetProperty", { target = "cx", channel = "rate" }),
				}, { L("p.out", "l.in"), L("l.body", "s.in"), L("rn.value", "s.value") })
				local out = {}
				for _, a in run(g, DEF, nil, 0, seed, cycle) do
					table.insert(out, a.value)
				end
				return out
			end
			local a = numbers(1, 0)
			T.expect(#a).toBe(50)
			for _, v in a do
				T.expect(v >= 2 and v < 5).toBe(true)
			end
			T.expect(numbers(1, 0)).toEqual(a)
			T.expect(numbers(2, 0)).never.toEqual(a)
			T.expect(numbers(1, 1)).never.toEqual(a)
			-- values differ per iteration (fresh context per loop iteration)
			local distinct = {}
			local n = 0
			for _, v in a do
				if not distinct[v] then
					distinct[v] = true
					n += 1
				end
			end
			T.expect(n).toBeGreaterThan(40)
			-- min > max still yields values between the bounds; min == max is constant
			for _, v in numbers(1, 0, 5, 2) do
				T.expect(v > 2 and v <= 5).toBe(true)
			end
			for _, v in numbers(1, 0, 3, 3) do
				T.expect(v).toBe(3)
			end
		end)

		T.it("RandomNumber inputs can come from links", function()
			local g = G({
				N("p", "OnPlay"),
				N("lo", "Number", { value = 100 }),
				N("hi", "Number", { value = 101 }),
				N("rn", "RandomNumber"),
				N("s", "SetProperty", { target = "cx", channel = "rate" }),
			}, { L("p.out", "s.in"), L("lo.value", "rn.min"), L("hi.value", "rn.max"), L("rn.value", "s.value") })
			local v = run(g)[1].value
			T.expect(v >= 100 and v < 101).toBe(true)
		end)

		T.it("shares one random value between consumers in the same context", function()
			local g = G({
				N("p", "OnPlay"),
				N("rn", "RandomNumber", { min = 1, max = 1000 }),
				N("par", "Parallel", { count = 2 }),
				N("e1", "Emit", { target = "fx" }),
				N("e2", "Emit", { target = "fx" }),
			}, {
				L("p.out", "par.in"),
				L("par.out1", "e1.in"),
				L("par.out2", "e2.in"),
				L("rn.value", "e1.count"),
				L("rn.value", "e2.count"),
			})
			for seed = 1, 10 do
				local counts = emitCounts(run(g, DEF, nil, 0, seed, 0))
				T.expect(#counts).toBe(2)
				T.expect(counts[1]).toBe(counts[2])
			end
		end)

		T.it("keeps flows of different triggers independent", function()
			local g = G({
				N("p", "OnPlay"),
				N("m", "OnMarker", { marker = "m1" }),
				N("ev", "OnEvent", { name = "Hit" }),
				N("rn", "RandomNumber", { min = 0, max = 1 }),
				N("s1", "SetProperty", { target = "cx", channel = "rate" }),
				N("s2", "SetProperty", { target = "cx", channel = "rate" }),
				N("s3", "SetProperty", { target = "cx", channel = "rate" }),
			}, {
				L("p.out", "s1.in"),
				L("m.out", "s2.in"),
				L("ev.out", "s3.in"),
				L("rn.value", "s1.value"),
				L("rn.value", "s2.value"),
				L("rn.value", "s3.value"),
			})
			local compiled = Graph.compile(g, DEF)
			local play = Graph.run(compiled, { kind = "play" }, 0, 5, 0)[1].value
			local marker = Graph.run(compiled, { kind = "marker", id = "m1" }, 1.5, 5, 0)[1].value
			local event1 = Graph.run(compiled, { kind = "event", id = "Hit" }, 2, 5, 0)[1].value
			local event1again = Graph.run(compiled, { kind = "event", id = "Hit" }, 2, 5, 0)[1].value
			local event2 = Graph.run(compiled, { kind = "event", id = "Hit" }, 3, 5, 0)[1].value
			T.expect(play).never.toBe(marker)
			T.expect(play).never.toBe(event1)
			T.expect(event1).toBe(event1again)
			T.expect(event1).never.toBe(event2)
		end)

		T.it("identical inputs give identical action lists", function()
			local compiled = Graph.compile(branchGraph({ count = 3 }), DEF)
			local a = Graph.run(compiled, { kind = "play" }, 0, 9, 3)
			local b = Graph.run(compiled, { kind = "play" }, 0, 9, 3)
			T.expect(a).toEqual(b)
		end)
	end)

	-- ── Limits and robustness ────────────────────────────────────────────────────────────────────────────

	T.describe("Graph limits and robustness", function()
		T.it("caps the actions per trigger and flags the list as truncated", function()
			local g = G({
				N("p", "OnPlay"),
				N("lo", "Loop", { count = 100, interval = 0.1 }),
				N("li", "Loop", { count = 100, interval = 0.001 }),
				N("par", "Parallel", { count = 2 }),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
			}, {
				L("p.out", "lo.in"),
				L("lo.body", "li.in"),
				L("li.body", "par.in"),
				L("par.out1", "e1.in"),
				L("par.out2", "e2.in"),
			})
			local list, info = run(g)
			T.expect(#list).toBe(Constants.MAX_GRAPH_ACTIONS)
			T.expect(list.truncated).toBe(true)
			T.expect(info.truncated).toBe(true)
			T.expect(codes(info.diagnostics)).toEqual({ "graph.action_limit" })
			T.expect(info.diagnostics[1].severity).toBe("warning")
			-- the flag is not a key of the list: generic iteration only sees actions
			local n = 0
			for _, a in list do
				n += 1
				T.expect(type(a)).toBe("table")
			end
			T.expect(n).toBe(Constants.MAX_GRAPH_ACTIONS)
			T.expect(rawget(list :: any, "truncated")).toBeNil()
			-- the earliest actions are kept (flows run in time order)
			local last = list[#list].time
			T.expect(last).toBeLessThan(5)
			for i = 2, #list do
				T.expect(list[i].time >= list[i - 1].time).toBe(true)
			end
		end)

		T.it("exactly MAX_GRAPH_ACTIONS actions are not truncated", function()
			local g = G({
				N("p", "OnPlay"),
				N("lo", "Loop", { count = 100, interval = 0.1 }),
				N("li", "Loop", { count = 100, interval = 0.001 }),
				N("e", "Emit", { target = "fx", count = 1 }),
			}, { L("p.out", "lo.in"), L("lo.body", "li.in"), L("li.body", "e.in") })
			local list, info = run(g)
			T.expect(#list).toBe(Constants.MAX_GRAPH_ACTIONS)
			T.expect(list.truncated).toBe(false)
			T.expect(info.truncated).toBe(false)
			T.expect(info.work).toBeLessThan(Graph.MAX_WORK)
			-- the 100 x 100 grid lands at the right times
			T.expect(list[1].time).toBe(0)
			T.expect(list[101].time).toBeCloseTo(0.1, 1e-9)
			T.expect(list[10000].time).toBeCloseTo(9.9 + 0.099, 1e-9)
		end)

		T.it("compile drops every link inside a cycle of an unvalidated graph", function()
			local g = G({
				N("p", "OnPlay"),
				N("a", "Delay", { seconds = 0 }),
				N("b", "Delay", { seconds = 0 }),
				N("e", "Emit", { target = "fx", count = 1 }),
			}, {
				L("p.out", "a.in"),
				L("a.out", "b.in"),
				L("b.out", "a.in"),
				L("e.out", "p.out"), -- invalid direction: ignored
			})
			local compiled = Graph.compile(g, DEF)
			T.expect(compiled.nodes.p.execOut.out.node).toBe("a")
			T.expect(compiled.nodes.a.execOut.out).toBeNil()
			T.expect(compiled.nodes.b.execOut.out).toBeNil()
			local list, info = Graph.run(compiled, { kind = "play" }, 0, 1, 0)
			T.expect(#list).toBe(0)
			T.expect(info.truncated).toBe(false)
			-- an action inside a cycle runs once (entered from outside), never loops
			local withEmit = G({
				N("p", "OnPlay"),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
			}, {
				L("p.out", "e1.in"),
				L("e1.out", "e2.in"),
				L("e2.out", "e1.in"),
			})
			local list2, info2 = run(withEmit)
			T.expect(emitCounts(list2)).toEqual({ 1 })
			T.expect(info2.truncated).toBe(false)
			-- Loop whose body re-enters the loop
			local loopCycle = G({ N("p", "OnPlay"), N("l", "Loop", { count = 100, interval = 0 }), N("d", "Delay") }, {
				L("p.out", "l.in"),
				L("l.body", "d.in"),
				L("d.out", "l.in"),
			})
			local _, info3 = run(loopCycle)
			T.expect(info3.truncated).toBe(false)
			-- self links are never compiled
			local selfLoop = G({ N("p", "OnPlay"), N("e", "Emit", { target = "fx", count = 1 }) }, {
				L("p.out", "e.in"),
				L("e.out", "e.in"),
			})
			local list4, info4 = run(selfLoop)
			T.expect(#list4).toBe(1)
			T.expect(info4.truncated).toBe(false)
			-- data cycles: inputs inside the cycle fall back to their params (a = 1 + 1)
			local data = G({
				N("p", "OnPlay"),
				N("a", "Math", { op = "add", a = 1, b = 1 }),
				N("b", "Math", { op = "add", a = 10, b = 10 }),
				N("e", "Emit", { target = "fx" }),
			}, { L("p.out", "e.in"), L("a.result", "b.a"), L("b.result", "a.a"), L("a.result", "e.count") })
			local list5 = run(data)
			T.expect(#list5).toBe(1)
			T.expect(list5[1].count).toBe(2)
		end)

		T.it("run never loops on a hand-made cyclic CompiledGraph", function()
			-- exec cycle injected after compile: the action cap stops it
			local compiled = Graph.compile(
				G({
					N("p", "OnPlay"),
					N("e1", "Emit", { target = "fx", count = 1 }),
					N("e2", "Emit", { target = "fx", count = 2 }),
				}, {
					L("p.out", "e1.in"),
					L("e1.out", "e2.in"),
				}),
				DEF
			)
			compiled.nodes.e2.execOut.out = { node = "e1", pin = "in" }
			local list, info = Graph.run(compiled, { kind = "play" }, 0, 1, 0)
			T.expect(#list).toBe(Constants.MAX_GRAPH_ACTIONS)
			T.expect(info.truncated).toBe(true)
			-- exec cycle without actions: the work budget stops it
			local delays = Graph.compile(
				G({ N("p", "OnPlay"), N("a", "Delay", { seconds = 0 }), N("b", "Delay", { seconds = 0 }) }, {
					L("p.out", "a.in"),
					L("a.out", "b.in"),
				}),
				DEF
			)
			delays.nodes.b.execOut.out = { node = "a", pin = "in" }
			local list2, info2 = Graph.run(delays, { kind = "play" }, 0, 1, 0)
			T.expect(#list2).toBe(0)
			T.expect(info2.truncated).toBe(true)
			T.expect(info2.work).toBeLessThanOrEqual(Graph.MAX_WORK + 1)
			-- data cycle injected after compile: the evaluator falls back to params
			local data = Graph.compile(
				G({
					N("p", "OnPlay"),
					N("a", "Math", { op = "add", a = 1, b = 1 }),
					N("b", "Math", { op = "add", a = 10, b = 10 }),
					N("e", "Emit", { target = "fx" }),
				}, { L("p.out", "e.in"), L("a.result", "b.a"), L("a.result", "e.count") }),
				DEF
			)
			data.nodes.a.dataIn.a = { node = "b", pin = "result" }
			local list3 = Graph.run(data, { kind = "play" }, 0, 1, 0)
			-- a pulls b; b's input from a is in progress -> b = 10 + 10; a = 20 + 1
			T.expect(list3[1].count).toBe(21)
			-- links to nodes that do not exist are ignored
			data.nodes.e.dataIn.count = { node = "ghost", pin = "value" }
			data.nodes.p.execOut.out = { node = "ghost", pin = "in" }
			T.expect(#Graph.run(data, { kind = "play" }, 0, 1, 0)).toBe(0)
		end)

		T.it("bounds pathological nesting with the work budget", function()
			-- 4 nested 100-iteration loops without actions = 10^8 flows
			local g = G({
				N("p", "OnPlay"),
				N("l1", "Loop", { count = 100, interval = 0 }),
				N("l2", "Loop", { count = 100, interval = 0 }),
				N("l3", "Loop", { count = 100, interval = 0 }),
				N("l4", "Loop", { count = 100, interval = 0 }),
				N("d", "Delay", { seconds = 0 }),
			}, {
				L("p.out", "l1.in"),
				L("l1.body", "l2.in"),
				L("l2.body", "l3.in"),
				L("l3.body", "l4.in"),
				L("l4.body", "d.in"),
			})
			local started = os.clock()
			local list, info = run(g)
			T.expect(#list).toBe(0)
			T.expect(info.truncated).toBe(true)
			T.expect(info.work).toBeLessThanOrEqual(Graph.MAX_WORK + 1)
			T.expect(os.clock() - started).toBeLessThan(10)
			-- wide nesting (outer iterations before inner ones) is bounded by the pending-flow limit
			local wide = G({
				N("p", "OnPlay"),
				N("l1", "Loop", { count = 100, interval = 0.0001 }),
				N("l2", "Loop", { count = 100, interval = 0.01 }),
				N("l3", "Loop", { count = 100, interval = 1 }),
				N("d", "Delay", { seconds = 0 }),
			}, { L("p.out", "l1.in"), L("l1.body", "l2.in"), L("l2.body", "l3.in"), L("l3.body", "d.in") })
			local _, info2 = run(wide)
			T.expect(info2.truncated).toBe(true)
		end)

		T.it("handles long exec and data chains without recursion", function()
			local nodes = { N("p", "OnPlay") }
			local links = {}
			local previous = "p.out"
			for i = 1, 200 do
				table.insert(nodes, N("d" .. i, "Delay", { seconds = 0.01 }))
				table.insert(links, L(previous, "d" .. i .. ".in"))
				previous = "d" .. i .. ".out"
			end
			table.insert(nodes, N("s", "SetProperty", { target = "cx", channel = "rate" }))
			table.insert(links, L(previous, "s.in"))
			-- 50 chained Math nodes: m1 = 0 + 1, m(i) = m(i-1) + 1
			local source = nil
			for i = 1, 50 do
				table.insert(nodes, N("m" .. i, "Math", { op = "add", a = 0, b = 1 }))
				if source then
					table.insert(links, L(source, "m" .. i .. ".a"))
				end
				source = "m" .. i .. ".result"
			end
			table.insert(links, L(source :: string, "s.value"))
			local g = G(nodes, links)
			T.expect(errors(Graph.validate(g, DEF))).toEqual({})
			local list = run(g)
			T.expect(#list).toBe(1)
			T.expect(list[1].time).toBeCloseTo(2, 1e-9)
			T.expect(list[1].value).toBe(50)
		end)

		T.it("compiles without a definition (no components, markers or palette)", function()
			local g = G({
				N("p", "OnPlay"),
				N("e", "Emit", { target = "fx" }),
				N("f", "FireEvent", { name = "Still" }),
			}, { L("p.out", "e.in"), L("e.out", "f.in") })
			local compiled = Graph.compile(g, nil)
			T.expect(compiled.components).toEqual({})
			T.expect(rows(Graph.run(compiled, { kind = "play" }, 0, 1, 0))).toEqual({ R(0, "fire", "Still", 0) })
			T.expect(codes(Graph.validate(g, nil))).toEqual({ "graph.component_missing" })
		end)

		T.it("compile drops malformed parts instead of throwing", function()
			local g = G({
				N("p", "OnPlay"),
				N("p", "Delay"), -- duplicate id: dropped
				N("x", "Teleport"), -- unknown type: dropped
				{ id = 5, type = "Emit" } :: any,
				N("e", "Emit", { target = "fx", count = "many" }), -- invalid param: default
				N("e2", "Emit", { target = "fx", count = 2 }),
			}, {
				L("p.out", "e.in"),
				L("p.out", "e2.in"), -- second link on one exec output: ignored
				L("x.out", "e.in"),
				L("e.out", "nope"),
				{ from = 1, to = 2 } :: any,
				5 :: any,
			})
			local compiled = Graph.compile(g, DEF)
			T.expect(compiled.order).toEqual({ "p", "e", "e2" })
			T.expect(compiled.nodes.p.type).toBe("OnPlay")
			T.expect(rows(Graph.run(compiled, { kind = "play" }, 0, 1, 0))).toEqual({ R(0, "emit", "fx", 10) })
		end)

		T.it("compile canonicalises params (clamped) and resolves specs", function()
			local g = G({
				N("l", "Loop", { count = 500, interval = -1 }),
				N("t", "Tween", { target = "g1", channel = "position", easing = "Quad.Out" }),
				N("s", "Sequence", { count = 4 }),
				N("r", "RandomBranch", { count = 3, weight2 = 5 }),
			})
			local compiled = Graph.compile(g, DEF)
			T.expect(compiled.nodes.l.params.count).toBe(Constants.MAX_LOOP_ITERATIONS)
			T.expect(compiled.nodes.l.params.interval).toBe(0)
			T.expect(compiled.nodes.t.params.easing).toBe("Quad")
			T.expect(compiled.nodes.t.channelSpec.kind).toBe("vector3")
			T.expect(compiled.nodes.t.channelSpec.name).toBe("position")
			T.expect(compiled.nodes.s.count).toBe(4)
			T.expect(compiled.nodes.r.weights).toEqual({ 1, 5, 1 })
			T.expect(compiled.components).toEqual({
				g1 = "group",
				fx = "particles",
				snd = "sound",
				bolt = "lightning",
				cx = "customThing",
			})
			T.expect(compiled.markerTimes).toEqual({ m1 = 1.5, m2 = 0.5 })
			T.expect(compiled.palette.primary).toBe(Color3.fromRGB(255, 0, 0))
		end)

		T.it("run reports programmer errors", function()
			local compiled = Graph.compile(playEmit(), DEF)
			T.expect(function()
				Graph.run(nil :: any, { kind = "play" }, 0, 1, 0)
			end).toThrow("CompiledGraph")
			T.expect(function()
				Graph.run(compiled, "play" :: any, 0, 1, 0)
			end).toThrow("trigger")
			T.expect(function()
				Graph.run(compiled, { kind = "jump" } :: any, 0, 1, 0)
			end).toThrow("unknown trigger kind")
		end)

		T.it("sanitises seed, cycle and start time", function()
			local compiled = Graph.compile(playEmit({ target = "fx", count = 1 }), DEF)
			local list = Graph.run(compiled, { kind = "play" }, 0 / 0, "x" :: any, nil :: any)
			T.expect(rows(list)).toEqual({ R(0, "emit", "fx", 1) })
			local inf = Graph.run(compiled, { kind = "play" }, math.huge, 1, 0)
			T.expect(inf[1].time).toBe(0)
		end)

		T.it("never throws on garbage input (fuzz)", function()
			local rand = lcg(12345)
			local types = {}
			for _, nodeType in NodeTypes.list() do
				table.insert(types, nodeType.type)
			end
			local pins = {
				"in",
				"out",
				"value",
				"result",
				"a",
				"b",
				"t",
				"body",
				"index",
				"then1",
				"out2",
				"target",
				"count",
				"done",
				"x",
			}
			local function pick(list: { any }): any
				return list[math.floor(rand() * #list) + 1]
			end
			local function garbage(depth: number): any
				local r = rand()
				if r < 0.15 then
					return math.floor(rand() * 200) - 50
				elseif r < 0.2 then
					return (if rand() < 0.5 then 0 / 0 else math.huge)
				elseif r < 0.35 then
					return pick({ "", "x", "fx", "g1", "m1", "#FF0000", "$primary", "Quad.InOut", "a.out", "Hit" })
				elseif r < 0.45 then
					return rand() < 0.5
				elseif r < 0.55 or depth > 2 then
					return nil
				end
				local t = {}
				for i = 1, math.floor(rand() * 4) do
					if rand() < 0.5 then
						t[i] = garbage(depth + 1)
					else
						t[pick({ "a", "count", "value", "bezier", "seconds" })] = garbage(depth + 1)
					end
				end
				return t
			end
			for _ = 1, 300 do
				local nodes = {}
				local ids = {}
				for i = 1, math.floor(rand() * 8) do
					local id = if rand() < 0.9 then "n" .. math.floor(rand() * 8) else garbage(0)
					table.insert(ids, id)
					local params: any = {}
					if rand() < 0.2 then
						params = garbage(0)
					else
						for _ = 1, math.floor(rand() * 4) do
							params[pick({
								"count",
								"interval",
								"seconds",
								"target",
								"channel",
								"value",
								"op",
								"a",
								"marker",
								"name",
								"easing",
								"weight1",
								"min",
								"max",
								"enabled",
								"component",
								"duration",
							})] =
								garbage(1)
						end
					end
					nodes[i] = if rand() < 0.95
						then { id = id, type = if rand() < 0.9 then pick(types) else garbage(0), params = params }
						else garbage(0)
				end
				local links = {}
				for i = 1, math.floor(rand() * 12) do
					local from = tostring(pick(ids) or "a") .. "." .. pick(pins)
					local to = tostring(pick(ids) or "b") .. "." .. pick(pins)
					links[i] = if rand() < 0.9 then { from = from, to = to } else garbage(0)
				end
				local g: any = if rand() < 0.97 then { nodes = nodes, links = links } else garbage(0)
				local def: any = if rand() < 0.9 then DEF else garbage(0)
				local ok, err = pcall(function()
					Graph.validate(g, def)
					Graph.findCycle(g)
					Graph.canConnect(
						g,
						def,
						tostring(pick(ids) or "a") .. "." .. pick(pins),
						tostring(pick(ids) or "b") .. "." .. pick(pins)
					)
					local compiled = Graph.compile(g, def)
					for _, trigger in
						{ { kind = "play" }, { kind = "marker", id = "m1" }, { kind = "event", id = "Hit" } } :: { any }
					do
						local list, info = Graph.run(compiled, trigger, rand() * 3, math.floor(rand() * 100), 0)
						assert(#list <= Constants.MAX_GRAPH_ACTIONS, "too many actions")
						assert(info.actions == #list, "info mismatch")
					end
					Graph.staticSchedule(compiled, 1, 0)
				end)
				if not ok then
					T.fail("graph engine threw on garbage: " .. tostring(err))
				end
			end
		end)
	end)

	-- ── staticSchedule / triggers / helpers ──────────────────────────────────────────────────────────────

	T.describe("Graph.staticSchedule", function()
		T.it("merges play and marker flows sorted by time and renumbers order", function()
			local g = G({
				N("p", "OnPlay"),
				N("m1", "OnMarker", { marker = "m1" }),
				N("m2", "OnMarker", { marker = "m2" }),
				N("d", "Delay", { seconds = 1 }),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
				N("e3", "Emit", { target = "fx", count = 3 }),
			}, {
				L("p.out", "d.in"),
				L("d.out", "e1.in"),
				L("m1.out", "e2.in"),
				L("m2.out", "e3.in"),
			})
			local list, info = Graph.staticSchedule(Graph.compile(g, DEF), 1, 0)
			T.expect(rows(list)).toEqual({ R(0.5, "emit", "fx", 3), R(1, "emit", "fx", 1), R(1.5, "emit", "fx", 2) })
			for i, a in list do
				T.expect(a.order).toBe(i)
			end
			T.expect(list.truncated).toBe(false)
			T.expect(info.actions).toBe(3)
			-- effect.markers override the definition's marker times
			local moved = Graph.staticSchedule(Graph.compile(g, DEF), 1, 0, {
				markers = { { id = "m1", time = 0.1, label = "x" }, { id = "m2", time = 3, label = "y" } },
			})
			T.expect(rows(moved)).toEqual({ R(0.1, "emit", "fx", 2), R(1, "emit", "fx", 1), R(3, "emit", "fx", 3) })
		end)

		T.it("propagates truncation of a marker flow", function()
			local g = G({
				N("m", "OnMarker", { marker = "m2" }),
				N("lo", "Loop", { count = 100, interval = 0.01 }),
				N("li", "Loop", { count = 100, interval = 0.0001 }),
				N("par", "Parallel"),
				N("e1", "Emit", { target = "fx", count = 1 }),
				N("e2", "Emit", { target = "fx", count = 2 }),
			}, {
				L("m.out", "lo.in"),
				L("lo.body", "li.in"),
				L("li.body", "par.in"),
				L("par.out1", "e1.in"),
				L("par.out2", "e2.in"),
			})
			local list, info = Graph.staticSchedule(Graph.compile(g, DEF), 1, 0)
			T.expect(#list).toBe(Constants.MAX_GRAPH_ACTIONS)
			T.expect(list.truncated).toBe(true)
			T.expect(info.truncated).toBe(true)
			T.expect(codes(info.diagnostics)).toEqual({ "graph.action_limit" })
			T.expect(list[1].time).toBe(0.5)
		end)

		T.it("lists the triggers with flows", function()
			local g = G({
				N("p", "OnPlay"),
				N("m", "OnMarker", { marker = "m1" }),
				N("e1", "OnEvent", { name = "Hit" }),
				N("e2", "OnEvent", { name = "Detonate" }),
				N("e3", "OnEvent"),
			})
			T.expect(Graph.triggers(Graph.compile(g, DEF))).toEqual({
				play = true,
				markers = { "m1" },
				events = { "Detonate", "Hit" },
			})
			T.expect(Graph.triggers(Graph.compile(G({}), DEF))).toEqual({ play = false, markers = {}, events = {} })
		end)
	end)

	T.describe("Graph.resolveParamSpec / pinKind", function()
		local g = G({
			N("t", "Tween", { target = "g1", channel = "position" }),
			N("u", "Tween", { target = "cx", channel = "rate" }),
			N("n", "Number"),
		})

		T.it("resolves the value param from the target channel", function()
			local spec = Graph.resolveParamSpec(g, DEF, "t", "value")
			T.expect(spec.kind).toBe("vector3")
			T.expect(spec.default).toEqual({ 0, 0, 0 })
			T.expect(spec.scale).toBe("length")
			-- unresolvable -> the static placeholder
			local static = Graph.resolveParamSpec(g, DEF, "u", "value")
			T.expect(static.kind).toBe("number")
			T.expect(static.default).toBeNil()
			T.expect(Graph.resolveParamSpec(g, DEF, "t", "duration").kind).toBe("number")
			T.expect(Graph.resolveParamSpec(g, DEF, "t", "nope")).toBeNil()
			T.expect(Graph.resolveParamSpec(g, DEF, "ghost", "value")).toBeNil()
		end)

		T.it("resolves pin kinds", function()
			T.expect(Graph.pinKind(g, DEF, "t.value")).toBe("vector3")
			T.expect(Graph.pinKind(g, DEF, "u.value")).toBe("any")
			T.expect(Graph.pinKind(g, DEF, "n.value")).toBe("number")
			T.expect(Graph.pinKind(g, DEF, "t.in")).toBe("exec")
			T.expect(Graph.pinKind(g, DEF, "t.nope")).toBeNil()
			T.expect(Graph.pinKind(g, DEF, "bad")).toBeNil()
		end)
	end)
end
