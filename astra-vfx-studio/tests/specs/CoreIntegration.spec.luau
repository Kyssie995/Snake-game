--!strict
--[[
	Cross-module integration of the wave-1 core (Json, Codec, Easing, Curves, Timeline, Graph, Quality, Random).

	One realistic effect is taken from JSON text through every module the way Validation, the Compiler and the
	Player will use them: Json.decode -> Codec.check / Easing.check -> Codec.decode / Curves.compileTrack ->
	Curves.evaluate*, and Graph.validate / compile / staticSchedule + Timeline.staticSchedule -> merged schedule
	-> Timeline.sort / range frame by frame. Expected values are computed independently (formulas, hand-picked
	numbers), not by calling the module under test a second time.
]]
return function(T: any, use: (string) -> any, _ctx: any)
	local Json = use("AstraVFX.Core.Json")
	local Codec = use("AstraVFX.Core.Codec")
	local Easing = use("AstraVFX.Core.Easing")
	local Curves = use("AstraVFX.Core.Curves")
	local Timeline = use("AstraVFX.Core.Timeline")
	local Graph = use("AstraVFX.Core.Graph")
	local Quality = use("AstraVFX.Core.Quality")
	local Random = use("AstraVFX.Core.Random")
	local Components = use("AstraVFX.Core.Components")

	local EFFECT_JSON = [=[
{
  "schemaVersion": 1,
  "id": "fireball",
  "name": "Fireball ✦ Feuerbäll",
  "duration": 2,
  "seed": 7,
  "palette": { "core": "#FF8800", "hot": "#fff" },
  "markers": [
    { "id": "impact", "time": 1, "label": "Impact", "event": "Impact" }
  ],
  "components": [
    {
      "id": "orb", "name": "Orb", "type": "part", "startTime": 0.5, "duration": 1,
      "properties": { "size": [1, 1, 1], "color": "$core" },
      "tracks": [
        { "id": "fade", "channel": "transparency", "keyframes": [
          { "time": 0, "value": 1.5, "easing": "Quad.InOut" },
          { "time": 0.5, "value": 0 },
          { "time": 0.5, "value": 0.25, "easing": "Constant" },
          { "time": 1, "value": 1 }
        ] },
        { "id": "move", "channel": "position", "keyframes": [
          { "time": 1, "value": [0, 2.5, -4] },
          { "time": 0, "value": 0, "easing": { "bezier": [0.25, 0.1, 0.25, 1] } }
        ] },
        { "id": "tint", "channel": "color", "keyframes": [
          { "time": 0, "value": "$hot" },
          { "time": 1, "value": [0, 0, 255] }
        ] }
      ]
    },
    {
      "id": "sparks", "name": "Sparks", "type": "particles", "startTime": 0.25,
      "properties": {
        "size": [[0, 0.5], [0.5, 2, 0.25], [0.5, 1], [1, 0]],
        "color": [[0, "$hot"], [0.5, "#FF0000"], [0.5, "#0000FF"], [1, "$core"]],
        "lifetime": [0.5, 1],
        "emitterSize": 2
      },
      "events": [
        { "id": "burst", "time": 0, "action": "emit", "count": 20 },
        { "id": "late", "time": 1.5, "action": "emit", "count": 5 },
        { "id": "atEnd", "time": 1.75, "action": "disable" }
      ]
    }
  ],
  "graph": {
    "nodes": [
      { "id": "play", "type": "OnPlay", "position": [0, 0] },
      { "id": "seq", "type": "Sequence", "params": { "count": 2, "interval": 0.25 } },
      { "id": "rnd", "type": "RandomNumber", "params": { "min": 5, "max": 10 } },
      { "id": "emit1", "type": "Emit", "params": { "target": "sparks" } },
      { "id": "fadeTo", "type": "Tween",
        "params": { "target": "orb", "channel": "transparency", "value": 0.5, "duration": 0.5, "easing": "Sine.Out" } },
      { "id": "done", "type": "FireEvent", "params": { "name": "OrbDone" } },
      { "id": "hit", "type": "OnMarker", "params": { "marker": "impact" } },
      { "id": "par", "type": "Parallel", "params": { "count": 2 } },
      { "id": "off", "type": "SetEnabled", "params": { "target": "sparks", "enabled": false } },
      { "id": "wait", "type": "Delay", "params": { "seconds": 0.25 } },
      { "id": "emit2", "type": "Emit", "params": { "target": "sparks", "count": 8 } },
      { "id": "det", "type": "OnEvent", "params": { "name": "Detonate" } },
      { "id": "emit3", "type": "Emit", "params": { "target": "sparks", "count": 3 } }
    ],
    "links": [
      { "from": "play.out", "to": "seq.in" },
      { "from": "seq.then1", "to": "emit1.in" },
      { "from": "rnd.value", "to": "emit1.count" },
      { "from": "seq.then2", "to": "fadeTo.in" },
      { "from": "fadeTo.done", "to": "done.in" },
      { "from": "hit.out", "to": "par.in" },
      { "from": "par.out1", "to": "off.in" },
      { "from": "par.out2", "to": "wait.in" },
      { "from": "wait.out", "to": "emit2.in" },
      { "from": "det.out", "to": "emit3.in" }
    ]
  }
}
]=]

	local function decodeEffect(text: string?): any
		local ok, def = Json.decode(text or EFFECT_JSON)
		assert(ok, def)
		return def
	end

	local function component(def: any, id: string): any
		for _, c in def.components do
			if c.id == id then
				return c
			end
		end
		error("no component " .. id)
	end

	local function track(comp: any, id: string): any
		for _, t in comp.tracks do
			if t.id == id then
				return t
			end
		end
		error("no track " .. id)
	end

	-- Definition palette ("#RRGGBB" strings) -> { [key]: Color3 }, as the Compiler builds it.
	local function palette(def: any): { [string]: Color3 }
		local out: { [string]: Color3 } = {}
		for key, value in def.palette do
			out[key] = Codec.parseColor(value)
		end
		return out
	end

	local function rgb(r: number, g: number, b: number): Color3
		return Color3.fromRGB(r, g, b)
	end

	-- CompiledComponent-shaped tables for Timeline (span via Timeline.span, events as authored).
	local function compiledComponents(def: any): { any }
		local out = {}
		for _, c in def.components do
			local s, e = Timeline.span(def, c)
			table.insert(out, { id = c.id, name = c.name, type = c.type, startTime = s, endTime = e, events = c.events or {} })
		end
		return out
	end

	-- Partial CompiledEffect for Graph.run (byId, quality, scale, palette, markers).
	local function effectFor(def: any, level: string, scale: number?): any
		local byId = {}
		for _, c in compiledComponents(def) do
			byId[c.id] = c
		end
		return {
			byId = byId,
			quality = Quality.resolve(level, def.quality),
			scale = scale or 1,
			palette = palette(def),
			markers = def.markers,
		}
	end

	local function rows(list: { any }): { any }
		local out = {}
		for _, a in list do
			table.insert(out, { a.time, a.action, a.componentId or a.name or "", a.count or 0, a.source })
		end
		return out
	end

	T.describe("Core integration", function()
		T.describe("JSON text -> Json -> Codec -> Curves -> Roblox values", function()
			T.it("decodes the effect and keeps the canonical JSON form a fixed point", function()
				local def = decodeEffect()
				T.expect(def.name).toBe("Fireball ✦ Feuerbäll")
				local once = Json.encode(def)
				local ok, again = Json.decode(once)
				T.expect(ok).toBe(true)
				T.expect(Json.encode(again)).toBe(once)
				-- canonical key order (Constants.KEY_ORDER) puts schemaVersion, id and name first
				local prefix = '{\n  "schemaVersion": 1,\n  "id": "fireball",\n  "name": "Fireball'
				T.expect(string.sub(once, 1, #prefix)).toBe(prefix)
			end)

			T.it("checks every keyframe like Validation and reports the clamped value as a range problem", function()
				local def = decodeEffect()
				local orb = component(def, "orb")
				local problems = {}
				for _, tr in orb.tracks do
					local spec = Components.channelSpec(orb.type, tr.channel)
					T.expect(spec).never.toBeNil()
					for i, kf in tr.keyframes do
						local ok, message, class = Codec.check(spec.kind, kf.value, spec)
						if not ok then
							table.insert(problems, { tr.id, i, class, message })
						end
						T.expect(Easing.check(kf.easing)).toBe(true)
						for _, key in Codec.paletteRefs(spec.kind, kf.value) do
							T.expect(def.palette[key]).never.toBeNil()
						end
					end
				end
				T.expect(#problems).toBe(1)
				T.expect(problems[1][1]).toBe("fade")
				T.expect(problems[1][2]).toBe(1)
				T.expect(problems[1][3]).toBe("range")
			end)

			T.it("compiles and evaluates a number track with clamping, easing, a jump and a Constant segment", function()
				local def = decodeEffect()
				local orb = component(def, "orb")
				local spec = Components.channelSpec("part", "transparency")
				local fade = Curves.compileTrack(track(orb, "fade"), spec, palette(def), 2)
				local function quadInOut(x: number): number
					return if x < 0.5 then 2 * x * x else 1 - (-2 * x + 2) ^ 2 / 2
				end
				T.expect(Curves.evaluate(fade, -1)).toBe(1) -- 1.5 clamped to the channel max
				T.expect(Curves.evaluate(fade, 0)).toBe(1)
				T.expect(Curves.evaluate(fade, 0.125)).toBeCloseTo(1 - quadInOut(0.25), 1e-12)
				T.expect(Curves.evaluate(fade, 0.25)).toBeCloseTo(0.5, 1e-12)
				T.expect(Curves.evaluate(fade, 0.5)).toBe(0.25) -- the last key at a shared time wins
				T.expect(Curves.evaluate(fade, 0.4999)).toBeCloseTo(1 - quadInOut(0.9998), 1e-9)
				T.expect(Curves.evaluate(fade, 0.75)).toBe(0.25) -- Constant holds
				T.expect(Curves.evaluate(fade, 1)).toBe(1)
				T.expect(Curves.evaluate(fade, 0 / 0)).toBe(1)
				-- the Player evaluates at local time = absolute time - span start
				local start = Timeline.span(def, orb)
				T.expect(start).toBe(0.5)
				T.expect(Curves.evaluate(fade, 0.75 - start)).toBeCloseTo(0.5, 1e-12)
			end)

			T.it("sorts out-of-order keyframes, scales length channels and applies a bezier easing", function()
				local def = decodeEffect()
				local orb = component(def, "orb")
				local spec = Components.channelSpec("part", "position")
				T.expect(spec.scale).toBe("length")
				local move = Curves.compileTrack(track(orb, "move"), spec, nil, 2)
				T.expect(move.keys[1].time).toBe(0)
				T.expect(move.keys[2].value).toBe(Vector3.new(0, 5, -8))
				-- CSS "ease" = cubic-bezier(0.25, 0.1, 0.25, 1); ease(0.5) = 0.8024033877
				local e = 0.8024033877399112
				T.expect(Curves.evaluate(move, 0.5)).toBeCloseTo(Vector3.new(0, 5 * e, -8 * e), 1e-5)
				T.expect(Curves.evaluate(move, 0)).toBe(Vector3.zero)
				T.expect(Curves.evaluate(move, 2)).toBe(Vector3.new(0, 5, -8))
			end)

			T.it("resolves palette references and [r, g, b] colours in colour tracks", function()
				local def = decodeEffect()
				local orb = component(def, "orb")
				local spec = Components.channelSpec("part", "color")
				local tint = Curves.compileTrack(track(orb, "tint"), spec, palette(def), 2)
				T.expect(Curves.evaluate(tint, 0)).toBe(Color3.new(1, 1, 1)) -- "#fff" via "$hot"
				T.expect(Curves.evaluate(tint, 1)).toBe(rgb(0, 0, 255))
				T.expect(Curves.evaluate(tint, 0.5)).toBeCloseTo(Color3.new(0.5, 0.5, 1), 1e-6)
				-- without the palette the reference is a (programmer) error naming the track
				T.expect(function()
					Curves.compileTrack(track(orb, "tint"), spec, nil, 1)
				end).toThrow("tint")
			end)

			T.it("decodes sequence properties with shared keypoint times and evaluates them like the engine", function()
				local def = decodeEffect()
				local sparks = component(def, "sparks")
				local pal = palette(def)
				local sizeSpec = Components.propertySpec("particles", "size")
				local colorSpec = Components.propertySpec("particles", "color")
				T.expect(Codec.check("numberSequence", sparks.properties.size, sizeSpec)).toBe(true)
				T.expect(Codec.check("colorSequence", sparks.properties.color, colorSpec)).toBe(true)
				local size = Codec.decode("numberSequence", sparks.properties.size, sizeSpec, pal)
				local color = Codec.decode("colorSequence", sparks.properties.color, colorSpec, pal)
				T.expect(typeof(size)).toBe("NumberSequence")
				T.expect(#size.Keypoints).toBe(4)
				T.expect(Curves.evaluateNumberSequence(size, 0.25)).toBeCloseTo(1.25, 1e-6)
				T.expect(Curves.evaluateNumberSequenceEnvelope(size, 0.25)).toBeCloseTo(0.125, 1e-6)
				T.expect(Curves.evaluateNumberSequence(size, 0.5)).toBe(1) -- later keypoint at the shared time
				T.expect(Curves.evaluateNumberSequence(size, 0.75)).toBeCloseTo(0.5, 1e-6)
				T.expect(Curves.evaluateColorSequence(color, 0)).toBe(Color3.new(1, 1, 1))
				T.expect(Curves.evaluateColorSequence(color, 0.25)).toBeCloseTo(Color3.new(1, 0.5, 0.5), 1e-6)
				T.expect(Curves.evaluateColorSequence(color, 0.5)).toBe(rgb(0, 0, 255))
				T.expect(Curves.evaluateColorSequence(color, 1)).toBe(rgb(255, 136, 0))
				-- the other property kinds
				local lifetime = Codec.decode("numberRange", sparks.properties.lifetime)
				T.expect(lifetime.Min).toBe(0.5)
				T.expect(lifetime.Max).toBe(1)
				local emitterSize = Codec.decode("vector3", sparks.properties.emitterSize)
				T.expect(emitterSize).toBe(Vector3.new(2, 2, 2))
			end)

			T.it("keeps Codec-normalized properties stable through save / load cycles", function()
				local def = decodeEffect()
				for _, c in def.components do
					local normalized = {}
					for name, value in c.properties do
						local spec = Components.propertySpec(c.type, name)
						T.expect(spec).never.toBeNil()
						normalized[name] = Codec.normalize(spec.kind, value, spec)
					end
					c.properties = normalized
				end
				local first = Json.encode(def)
				local _, loaded = Json.decode(first)
				for _, c in loaded.components do
					for name, value in c.properties do
						local spec = Components.propertySpec(c.type, name)
						c.properties[name] = Codec.normalize(spec.kind, value, spec)
					end
				end
				T.expect(Json.encode(loaded)).toBe(first)
			end)

			T.it("evaluates a segment exactly as Codec.lerp(kind, a, b, Easing(alpha)) for every style", function()
				local specs: { any } = {
					{ "number", { name = "n", kind = "number", description = "" }, 2, -3 },
					{ "vector3", { name = "v", kind = "vector3", description = "" }, { 1, 2, 3 }, { -4, 0, 8 } },
					{ "color3", { name = "c", kind = "color3", description = "" }, "#102030", "#F0E0D0" },
				}
				for _, entry in specs do
					local kind, spec, a, b = entry[1], entry[2], entry[3], entry[4]
					local va, vb = Codec.decode(kind, a, spec), Codec.decode(kind, b, spec)
					for _, style in Easing.STYLES do
						for _, direction in Easing.DIRECTIONS do
							local def = style .. "." .. direction
							local compiled = Curves.compileTrack({
								id = "t",
								channel = spec.name,
								keyframes = { { time = 1, value = a, easing = def }, { time = 3, value = b } },
							}, spec)
							local ease = Easing.parse(def)
							for _, alpha in { 0.1, 0.5, 0.9 } do
								local got = Curves.evaluate(compiled, 1 + 2 * alpha)
								local want = if style == "Constant" then va else Codec.lerp(kind, va, vb, ease(alpha))
								if kind == "number" then
									T.expect(got).toBeCloseTo(want, 1e-12)
								else
									T.expect(got).toBeCloseTo(want, 1e-6)
								end
							end
						end
					end
				end
			end)

			T.it("bakes an easing into a sequence that survives the definition round trip", function()
				local fn = Easing.parse("Back.Out")
				local keys, err = Curves.bakeToSequenceKeypoints(fn, 20, 0.002)
				local def = decodeEffect()
				local sparks = component(def, "sparks")
				sparks.properties.size = keys
				local _, loaded = Json.decode(Json.encode(def))
				local stored = component(loaded, "sparks").properties.size
				T.expect(stored).toEqual(keys)
				local spec = Components.propertySpec("particles", "size")
				T.expect(Codec.check("numberSequence", stored, spec)).toBe(true)
				local seq = Codec.decode("numberSequence", stored, spec)
				for i = 0, 400 do
					local t = i / 400
					-- size has min 0: Back.Out never goes below 0, so no clamping is involved
					T.expect(math.abs(Curves.evaluateNumberSequence(seq, t) - fn(t)) <= err + 1e-4).toBe(true)
				end
			end)
		end)

		T.describe("Graph -> Timeline schedule -> frames", function()
			T.it("validates the graph of the JSON effect without errors", function()
				local def = decodeEffect()
				local diagnostics = Graph.validate(def.graph, def)
				for _, d in diagnostics do
					T.expect(d.severity).never.toBe("error")
				end
			end)

			T.it("unrolls play and marker flows with the documented random key", function()
				local def = decodeEffect()
				local compiled = Graph.compile(def.graph, def)
				local list = Graph.staticSchedule(compiled, def.seed, 0)
				-- RandomNumber key: (seed, cycle, trigger, node id, invocation); Emit counts are rounded
				local r = Random.new(Random.hash(7, 0, "play", "rnd", 0)):range(5, 10)
				local count = math.floor(r + 0.5)
				T.expect(rows(list)).toEqual({
					{ 0, "emit", "sparks", count, "graph" },
					{ 0.25, "tween", "orb", 0, "graph" },
					{ 0.75, "fire", "OrbDone", 0, "graph" },
					{ 1, "disable", "sparks", 0, "graph" },
					{ 1.25, "emit", "sparks", 8, "graph" },
				})
				local tween = list[2]
				T.expect(tween.channel).toBe("transparency")
				T.expect(tween.value).toBe(0.5)
				T.expect(tween.duration).toBe(0.5)
				T.expect(tween.easing(0.5)).toBe(Easing.get("Sine", "Out")(0.5))
				T.expect(tween.easing(0.5)).toBeCloseTo(math.sin(math.pi / 4), 1e-12)
			end)

			T.it("gives identical schedules for the JSON text and its canonical round trip", function()
				local def = decodeEffect()
				local _, again = Json.decode(Json.encode(def, { pretty = false }))
				local a = Graph.staticSchedule(Graph.compile(def.graph, def), 7, 3, effectFor(def, "High"))
				local b = Graph.staticSchedule(Graph.compile(again.graph, again), 7, 3, effectFor(again, "High"))
				T.expect(rows(a)).toEqual(rows(b))
				-- a new cycle draws new random numbers, the same cycle the same ones
				local c = Graph.staticSchedule(Graph.compile(def.graph, def), 7, 3, effectFor(def, "High"))
				T.expect(rows(c)).toEqual(rows(a))
			end)

			T.it("applies the quality profile's countScale to graph emits like the Compiler does for events", function()
				local def = decodeEffect()
				local compiled = Graph.compile(def.graph, def)
				local low = Quality.resolve("Low")
				local list = Graph.staticSchedule(compiled, 7, 0, effectFor(def, "Low"))
				local emits = {}
				for _, a in list do
					if a.action == "emit" then
						table.insert(emits, a.count)
					end
				end
				local r = Random.new(Random.hash(7, 0, "play", "rnd", 0)):range(5, 10)
				local full = math.floor(r + 0.5)
				-- × countScale, rounded, min 1
				T.expect(emits).toEqual({
					math.max(1, math.floor(full * low.countScale + 0.5)),
					math.max(1, math.floor(8 * low.countScale + 0.5)),
				})
			end)

			T.it("skips actions on components the Compiler removed (minQuality)", function()
				local def = decodeEffect()
				component(def, "sparks").minQuality = "High"
				local effect = effectFor(def, "Medium")
				for id, c in effect.byId do
					local comp = component(def, id)
					if not Quality.includes(effect.quality.level, comp.minQuality) then
						effect.byId[c.id] = nil
					end
				end
				local list = Graph.staticSchedule(Graph.compile(def.graph, def), 7, 0, effect)
				T.expect(rows(list)).toEqual({
					{ 0.25, "tween", "orb", 0, "graph" },
					{ 0.75, "fire", "OrbDone", 0, "graph" },
				})
			end)

			T.it("scales graph channel values exactly like Curves scales track values", function()
				local def = decodeEffect()
				def.graph = {
					nodes = {
						{ id = "p", type = "OnPlay" },
						{
							id = "s",
							type = "SetProperty",
							params = { target = "orb", channel = "size", value = { 1, 4000, 0.0001 } },
						},
					},
					links = { { from = "p.out", to = "s.in" } },
				}
				local list = Graph.run(Graph.compile(def.graph, def), { kind = "play" }, 0, 1, 0, effectFor(def, "High", 2))
				local spec = Components.channelSpec("part", "size")
				local tr = Curves.compileTrack(
					{ id = "t", channel = "size", keyframes = { { time = 0, value = { 1, 4000, 0.0001 } } } },
					spec,
					nil,
					2
				)
				T.expect(#list).toBe(1)
				T.expect(list[1].value).toBe(Curves.evaluate(tr, 0))
				-- clamped to [0.001, 2048] in authored units, then scaled
				T.expect(list[1].value).toBe(Vector3.new(2, 4096, 0.002))
			end)

			T.it("merges component events, marker events and graph actions into one schedule the Player can step", function()
				local def = decodeEffect()
				local components = compiledComponents(def)
				local static = Timeline.staticSchedule(components, def.markers)
				-- events at absolute start + time inside [start, end); "atEnd" lands exactly at the end and is dropped
				T.expect(rows(static)).toEqual({
					{ 0.25, "emit", "sparks", 20, "event" },
					{ 1, "fire", "Impact", 0, "marker" },
					{ 1.75, "emit", "sparks", 5, "event" },
				})
				local graphList = Graph.staticSchedule(Graph.compile(def.graph, def), 7, 0, effectFor(def, "High"))
				-- Compiler-style merge: static actions first at equal times, then renumber and sort (stable)
				local merged = {}
				for _, a in static do
					table.insert(merged, a)
				end
				for _, a in graphList do
					table.insert(merged, a)
				end
				for i, a in merged do
					a.order = i
				end
				Timeline.sort(merged)
				local times = {}
				for i, a in merged do
					table.insert(times, a.time)
					if i > 1 then
						local p = merged[i - 1]
						T.expect(p.time < a.time or (p.time == a.time and p.order < a.order)).toBe(true)
					end
				end
				T.expect(times).toEqual({ 0, 0.25, 0.25, 0.75, 1, 1, 1.25, 1.75 })
				T.expect(merged[2].source).toBe("event") -- static before graph at 0.25
				T.expect(merged[5].source).toBe("marker") -- and at 1

				-- Player frames: actions at 0 run on start (includeStart), then (previous, t] per frame.
				local executed: { [number]: number } = {}
				local function run(first: number, last: number, t0: number, t1: number)
					for i = first, last do
						local a = merged[i]
						T.expect(executed[i]).toBeNil()
						T.expect(a.time >= t0 and a.time <= t1).toBe(true)
						executed[i] = (executed[i] or 0) + 1
					end
				end
				local first, last = Timeline.range(merged, 0, 0, true)
				run(first, last, 0, 0)
				local t = 0
				local dt = 1 / 64
				while t < def.duration do
					local nextT = math.min(t + dt, def.duration)
					local f, l = Timeline.range(merged, t, nextT, false)
					run(f, l, t, nextT)
					t = nextT
				end
				for i = 1, #merged do
					T.expect(executed[i]).toBe(1)
				end
			end)

			T.it("runs an OnEvent flow from the current time and the Player picks it up with includeStart", function()
				local def = decodeEffect()
				local compiled = Graph.compile(def.graph, def)
				T.expect(Graph.triggers(compiled).events).toEqual({ "Detonate" })
				local now = 1.1
				local list = Graph.run(compiled, { kind = "event", id = "Detonate" }, now, 7, 0, effectFor(def, "High"))
				T.expect(rows(list)).toEqual({ { now, "emit", "sparks", 3, "graph" } })
				local pending = Timeline.sort(list)
				local f0, l0 = Timeline.range(pending, now, now + 1 / 60, false)
				T.expect(l0 < f0).toBe(true) -- (now, now + dt] misses an action exactly at `now`
				local f1, l1 = Timeline.range(pending, now, now + 1 / 60, true)
				T.expect(f1).toBe(1)
				T.expect(l1).toBe(1)
				-- unknown event names produce nothing
				T.expect(#Graph.run(compiled, { kind = "event", id = "detonate" }, now, 7, 0)).toBe(0)
			end)
		end)
	end)
end
