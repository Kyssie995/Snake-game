--!strict
--[[
	Core/Compiler — EffectDefinition -> CompiledEffect (docs/MODULE_CONTRACTS.md §15, COMPONENTS_SPEC §0).

	Realistic definitions come from JSON text (tests/specs/Helpers/EffectFixtures.luau, decoded with Core/Json) or
	small Luau tables. Expected numbers are written out by hand (quality profile arithmetic, scale factors) rather
	than recomputed with the module under test.
]]
return function(T: any, use: (string) -> any, _ctx: any)
	local Compiler = use("AstraVFX.Core.Compiler")
	local Components = use("AstraVFX.Core.Components")
	local Json = use("AstraVFX.Core.Json")
	local Quality = use("AstraVFX.Core.Quality")
	local Random = use("AstraVFX.Core.Random")
	local Curves = use("AstraVFX.Core.Curves")
	local Fixtures = use("Tests.Specs.Helpers.EffectFixtures")
	local expect = T.expect

	local PRIMARY = Color3.fromRGB(0x8A, 0x5C, 0xFF)
	local WHITE = Color3.fromRGB(255, 255, 255)

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end

	local function full(): any
		return Fixtures.full(Json)
	end

	local function effect(components: { any }, extra: { [string]: any }?): any
		local def: { [string]: any } = {
			schemaVersion = 1,
			id = "test",
			name = "Test",
			duration = 2,
			components = components,
		}
		local fields: { [string]: any } = extra or {}
		for k, v in fields do
			def[k] = v
		end
		return def
	end

	local function ids(compiled: any): { string }
		local out = {}
		for _, c in compiled.components do
			table.insert(out, c.id)
		end
		return out
	end

	-- { time, action, componentId | "", count | -1, name | "", source } per scheduled action.
	local function rows(schedule: { any }): { { any } }
		local out = {}
		for _, a in schedule do
			table.insert(out, R(a.time, a.action, a.componentId or "", a.count or -1, a.name or "", a.source))
		end
		return out
	end

	local function withoutGraphCounts(schedule: { any }): { { any } }
		local out = rows(schedule)
		for i, a in schedule do
			if a.source == "graph" and a.action == "emit" then
				out[i][4] = "random"
			end
		end
		return out
	end

	T.describe("Compiler.compile — full effect", function()
		T.it("compiles every registered component type of a realistic definition", function()
			local compiled = Compiler.compile(full(), { quality = "High" })
			local seen: { [string]: boolean } = {}
			for _, c in compiled.components do
				seen[c.type] = true
				expect(compiled.byId[c.id]).toBe(c)
			end
			for _, componentType in Components.types() do
				expect(seen[componentType]).toBe(true)
			end
			expect(#Components.types()).toBe(17)
			-- disabled group + child are gone; everything else is built at High
			expect(ids(compiled)).toEqual({
				"pivot",
				"sparks",
				"slash",
				"swoosh",
				"core",
				"orb",
				"glow",
				"boom",
				"energy",
				"flash",
				"wave",
				"circle",
				"spikes",
				"rocks",
				"bolt",
				"ultra",
				"shake",
				"impactFrame",
			})
		end)

		T.it("fills the effect-level fields", function()
			local def = full()
			local compiled = Compiler.compile(def, { quality = "High" })
			expect(compiled.id).toBe("violetImpact")
			expect(compiled.name).toBe("Violet Impact")
			expect(compiled.duration).toBe(2)
			expect(compiled.loop).toBe(false)
			expect(compiled.timeScale).toBe(1)
			expect(compiled.seed).toBe(42)
			expect(compiled.scale).toBe(1)
			expect(compiled.quality.level).toBe("High")
			expect(compiled.definition).toBe(def)
			expect(#compiled.markers).toBe(2)
			expect(compiled.markers[1].id).toBe("impact")
			expect(compiled.graph).never.toBeNil()
			expect(compiled.palette.primary).toBe(PRIMARY)
			expect(compiled.palette.dark).toBe(Color3.fromRGB(0x20, 0x00, 0x40))
		end)

		T.it("decodes properties, fills defaults and ignores unknown keys", function()
			local compiled = Compiler.compile(full(), { quality = "High" })
			local sparks = compiled.byId.sparks.props
			expect(sparks.rate).toBe(40)
			expect(sparks.burst).toBe(25)
			expect(sparks.speed).toBe(NumberRange.new(10, 20))
			expect(sparks.acceleration).toBe(Vector3.new(0, -10, 0))
			expect(sparks.shape).toBe("Sphere")
			expect(sparks.color.Keypoints[1].Value).toBe(PRIMARY)
			expect(sparks.color.Keypoints[2].Value).toBe(WHITE)
			expect(sparks.size.Keypoints[2].Envelope).toBeCloseTo(0.25, 1e-6)
			expect(sparks.texture).toBe("rbxasset://textures/particles/sparkles_main.dds") -- default
			expect(sparks.drag).toBe(0)
			expect(sparks.emissionDirection).toBe(Enum.NormalId.Top)
			expect(sparks.unknownProp).toBeNil()
			local slash = compiled.byId.slash.props
			expect(slash.textureMode).toBe(Enum.TextureMode.Stretch)
			expect(slash.faceCamera).toBe(true)
			expect(compiled.byId.core.props.shape).toBe(Enum.PartType.Ball)
			expect(compiled.byId.core.props.color).toBe(WHITE)
			expect(compiled.byId.glow.props.range).toBe(16)
			expect(compiled.byId.glow.props.shadows).toBe(true)
			expect(compiled.byId.energy.props.shellColor).toBe(PRIMARY)
			-- every declared property is present, nothing else
			for _, c in compiled.components do
				local descriptor = Components.get(c.type)
				local n = 0
				for _ in c.props do
					n += 1
				end
				expect(n).toBe(#descriptor.properties)
				for _, spec in descriptor.properties do
					expect(c.props[spec.name]).never.toBeNil()
				end
			end
		end)

		T.it("computes hierarchy, depth, spans, rest transforms and seeds", function()
			local compiled = Compiler.compile(full(), { quality = "High" })
			local pivot, sparks = compiled.byId.pivot, compiled.byId.sparks
			expect(pivot.parentId).toBeNil()
			expect(pivot.depth).toBe(0)
			expect(sparks.parentId).toBe("pivot")
			expect(sparks.depth).toBe(1)
			expect(sparks.startTime).toBe(0.5)
			expect(sparks.endTime).toBe(1.5)
			expect(compiled.byId.wave.startTime).toBe(0.5)
			expect(compiled.byId.wave.endTime).toBe(2) -- default duration: effect duration - startTime
			expect(compiled.byId.energy.endTime).toBe(0.6)
			expect(pivot.position).toBe(Vector3.new(0, 2, 0))
			expect(pivot.rotation).toBe(Vector3.new(0, 45, 0))
			expect(pivot.scale).toBe(1)
			expect(compiled.byId.orb.scale).toBe(1.5)
			expect(compiled.byId.swoosh.position).toBe(Vector3.new(3, 0, 0))
			expect(compiled.byId.core.position).toBe(Vector3.zero)
			for _, c in compiled.components do
				expect(c.seed).toBe(Random.hash(42, c.id))
			end
		end)

		T.it("compiles tracks per channel and skips disabled tracks", function()
			local compiled = Compiler.compile(full(), { quality = "High" })
			local core = compiled.byId.core
			expect(core.tracks.size).never.toBeNil()
			expect(core.tracks.transparency).toBeNil() -- enabled = false
			expect(core.tracks.size.kind).toBe("vector3")
			expect(Curves.evaluate(core.tracks.size, 0.5)).toBe(Vector3.new(3, 3, 3))
			local w = compiled.byId.slash.tracks.width0
			expect(#w.keys).toBe(2)
			expect(Curves.evaluate(w, 0.2)).toBe(2)
			expect(compiled.byId.sparks.tracks.rate.keys[1].value).toBe(40)
		end)

		T.it("copies events and keeps emit counts at High", function()
			local compiled = Compiler.compile(full(), { quality = "High" })
			local events = compiled.byId.sparks.events
			expect(#events).toBe(3)
			expect(events[1]).toEqual({ id = "pop", time = 0.25, action = "emit", count = 30 })
			expect(events[2].count).toBe(1)
			expect(events[3].count).toBe(4)
			expect(compiled.byId.bolt.events[1].action).toBe("regenerate")
		end)

		T.it("merges component events, marker events and graph actions into one sorted schedule", function()
			local compiled = Compiler.compile(full(), { quality = "High" })
			expect(withoutGraphCounts(compiled.schedule)).toEqual({
				R(0, "emit", "sparks", "random", "", "graph"),
				R(0.5, "regenerate", "bolt", -1, "", "event"),
				R(0.5, "fire", "", -1, "Impact", "marker"),
				R(0.5, "fire", "", -1, "Shake", "graph"),
				R(0.75, "emit", "sparks", 30, "", "event"),
				R(0.75, "tween", "core", -1, "", "graph"),
				R(1, "emit", "sparks", 1, "", "event"),
				R(1, "play", "boom", -1, "", "event"),
				R(1, "disable", "ultra", -1, "", "graph"),
				R(1.25, "emit", "sparks", 4, "", "event"),
			})
			for i, a in compiled.schedule do
				expect(a.order).toBe(i)
			end
			local emit = compiled.schedule[1]
			expect(emit.sourceId).toBe("burst")
			expect(emit.count >= 5 and emit.count <= 15).toBe(true)
			expect(emit.count).toBe(math.floor(emit.count))
			local tween = compiled.schedule[6]
			expect(tween.channel).toBe("transparency")
			expect(tween.value).toBe(1)
			expect(tween.duration).toBe(0.25)
			expect(type(tween.easing)).toBe("function")
			-- OnEvent flows are runtime-only: no regenerate from the graph in the static schedule
			for _, a in compiled.schedule do
				expect(a.source == "graph" and a.action == "regenerate").toBe(false)
			end
		end)

		T.it("computes maxTail from descriptor tail times", function()
			local high = Compiler.compile(full(), { quality = "High" })
			expect(high.maxTail).toBeCloseTo(1.5, 1e-6) -- particles lifetime.Max (trail lifetime is 0.4)
			local low = Compiler.compile(full(), { quality = "Low" })
			expect(low.maxTail).toBeCloseTo(0.8, 1e-6) -- qualityOverrides.Low.lifetime
			local none = Compiler.compile(effect({ { id = "p", name = "P", type = "part" } }), { quality = "High" })
			expect(none.maxTail).toBe(0)
		end)

		T.it("is deterministic: compiling twice yields deep-equal components and schedules", function()
			local a = Compiler.compile(full(), { quality = "Medium", scale = 1.5 })
			local b = Compiler.compile(full(), { quality = "Medium", scale = 1.5 })
			expect(a.components).toEqual(b.components)
			expect(a.schedule).toEqual(b.schedule)
			expect(a.palette).toEqual(b.palette)
			-- the canonical JSON round trip compiles to the same result
			local def = full()
			local ok, again = Json.decode(Json.encode(def, { pretty = false }))
			expect(ok).toBe(true)
			local c = Compiler.compile(again, { quality = "Medium", scale = 1.5 })
			expect(c.components).toEqual(a.components)
			expect(c.schedule).toEqual(a.schedule)
		end)

		T.it("uses a fixture that passes Core/Validation (when the module is available)", function()
			local ok, Validation = pcall(use, "AstraVFX.Core.Validation")
			if not ok or type(Validation) ~= "table" or type(Validation.validate) ~= "function" then
				return
			end
			local result = Validation.validate(full())
			local errors = {}
			for _, d in result.errors do
				table.insert(errors, d.path .. ": " .. d.code)
			end
			expect(errors).toEqual({})
		end)

		T.it("never mutates the definition", function()
			local def = full()
			local before = Json.encode(def)
			Compiler.compile(def, { quality = "Low", scale = 3, palette = { primary = Color3.new(1, 0, 0) } })
			Compiler.compile(def, { quality = "High" })
			expect(Json.encode(def)).toBe(before)
		end)
	end)

	T.describe("Compiler.compile — quality", function()
		T.it("scales count and segment properties: Low vs Medium vs High", function()
			local high = Compiler.compile(full(), { quality = "High" })
			local medium = Compiler.compile(full(), { quality = "Medium" })
			local low = Compiler.compile(full(), { quality = "Low" })
			-- particles: rate 40 (number), burst 25 (integer)
			expect(high.byId.sparks.props.rate).toBe(40)
			expect(medium.byId.sparks.props.rate).toBeCloseTo(26, 1e-9) -- 40 × 0.65
			expect(low.byId.sparks.props.rate).toBeCloseTo(14, 1e-9) -- 40 × 0.35
			expect(high.byId.sparks.props.burst).toBe(25)
			expect(medium.byId.sparks.props.burst).toBe(16) -- 16.25
			expect(low.byId.sparks.props.burst).toBe(9) -- 8.75
			-- debris / radialBurst counts, lightning segments + branches, shockwave layers
			expect(high.byId.rocks.props.count).toBe(20)
			expect(low.byId.rocks.props.count).toBe(7)
			expect(high.byId.spikes.props.count).toBe(16)
			expect(low.byId.spikes.props.count).toBe(6) -- 5.6
			expect(high.byId.bolt.props.segments).toBe(16)
			expect(medium.byId.bolt.props.segments).toBe(12)
			expect(low.byId.bolt.props.segments).toBe(8)
			expect(high.byId.bolt.props.branches).toBe(3)
			expect(low.byId.bolt.props.branches).toBe(1) -- 1.05
			expect(high.byId.wave.props.layers).toBe(3)
			expect(low.byId.wave.props.layers).toBe(2) -- 1.5 rounds up
			-- ring is Medium+ only; its segments follow segmentScale
			expect(high.byId.circle.props.segments).toBe(32)
			expect(medium.byId.circle.props.segments).toBe(24)
			-- non-quality properties are unchanged
			expect(low.byId.sparks.props.speed).toBe(high.byId.sparks.props.speed)
			expect(low.byId.rocks.props.speed).toBe(high.byId.rocks.props.speed)
		end)

		T.it("keeps counts >= 1, never raises fractional rates and keeps 0", function()
			local function rateAt(level: string, rate: number, burst: number): (number, number)
				local def = effect({
					{ id = "p", name = "P", type = "particles", properties = { rate = rate, burst = burst } },
				})
				local props = Compiler.compile(def, { quality = level }).byId.p.props
				return props.rate, props.burst
			end
			local r, b = rateAt("Low", 2, 1)
			expect(r).toBe(1) -- 0.7 -> at least 1
			expect(b).toBe(1) -- 0.35 -> at least 1
			r, b = rateAt("Low", 0.5, 0)
			expect(r).toBe(0.5) -- a sub-1 rate is never raised
			expect(b).toBe(0)
			r = rateAt("Low", 0, 0)
			expect(r).toBe(0)
			r = rateAt("High", 0.5, 0)
			expect(r).toBe(0.5)
			-- segments never go below the property minimum (ring: 3)
			local ring = effect({ { id = "r", name = "R", type = "ring", properties = { segments = 4 } } })
			expect(Compiler.compile(ring, { quality = "Low" }).byId.r.props.segments).toBe(3)
		end)

		T.it("scales emit event counts with countScale (min 1, 0 stays 0, missing stays nil)", function()
			local low = Compiler.compile(full(), { quality = "Low" })
			local events = low.byId.sparks.events
			expect(events[1].count).toBe(11) -- 30 × 0.35 = 10.5
			expect(events[2].count).toBe(1) -- 0.35 -> 1
			expect(events[3].count).toBe(1) -- 1.4 -> 1
			local def = effect({
				{
					id = "p",
					name = "P",
					type = "particles",
					events = R(
						{ id = "a", time = 0, action = "emit", count = 0 },
						{ id = "b", time = 0.1, action = "emit", count = 99999 },
						{ id = "c", time = 0.2, action = "emit" },
						{ id = "d", time = 0.3, action = "clear", count = 50 }
					),
				},
			})
			local compiled = Compiler.compile(def, { quality = "Medium" })
			expect(compiled.byId.p.events[1].count).toBe(0)
			expect(compiled.byId.p.events[2].count).toBe(6500) -- clamped to 10000, × 0.65
			expect(compiled.byId.p.events[3].count).toBeNil() -- descriptor default applies at runtime
			expect(compiled.byId.p.events[4].count).toBe(50) -- only emit counts are quality-scaled
		end)

		T.it("scales graph emit counts with the same profile", function()
			local high = Compiler.compile(full(), { quality = "High" })
			local low = Compiler.compile(full(), { quality = "Low" })
			local n = high.schedule[1].count
			expect(low.schedule[1].count).toBe(math.max(1, math.floor(n * 0.35 + 0.5)))
		end)

		T.it("quality-scales tracks whose channel rests on a count property (particles rate)", function()
			local low = Compiler.compile(full(), { quality = "Low" })
			local keys = low.byId.sparks.tracks.rate.keys
			expect(keys[1].value).toBeCloseTo(14, 1e-9)
			expect(keys[2].value).toBe(0)
			-- channels without a quality base property are untouched
			local w = low.byId.slash.tracks.width0
			expect(Curves.evaluate(w, 0.2)).toBe(2)
		end)

		T.it("applies qualityOverrides of the active level as exact values before decoding", function()
			local def = effect({
				{
					id = "p",
					name = "P",
					type = "particles",
					properties = { rate = 100, lifetime = { 1, 3 }, size = 2 },
					qualityOverrides = { Low = { rate = 30, size = 1 }, High = { lifetime = 5 } },
				},
			})
			local low = Compiler.compile(def, { quality = "Low" }).byId.p.props
			expect(low.rate).toBe(30) -- the author's value for Low, not 30 × 0.35
			expect(low.size).toBe(NumberSequence.new(1))
			expect(low.lifetime).toBe(NumberRange.new(1, 3))
			local medium = Compiler.compile(def, { quality = "Medium" }).byId.p.props
			expect(medium.rate).toBeCloseTo(65, 1e-9)
			expect(medium.size).toBe(NumberSequence.new(2))
			local high = Compiler.compile(def, { quality = "High" }).byId.p.props
			expect(high.lifetime).toBe(NumberRange.new(5, 5))
			-- overrides still get the effect scale
			local scaled = Compiler.compile(def, { quality = "Low", scale = 2 }).byId.p.props
			expect(scaled.size).toBe(NumberSequence.new(2))
		end)

		T.it("omits minQuality components below their level and children of removed parents", function()
			local low = Compiler.compile(full(), { quality = "Low" })
			expect(low.byId.circle).toBeNil()
			expect(low.byId.ultra).toBeNil()
			expect(low.byId.hidden).toBeNil()
			expect(low.byId.hiddenChild).toBeNil()
			local medium = Compiler.compile(full(), { quality = "Medium" })
			expect(medium.byId.circle).never.toBeNil()
			expect(medium.byId.ultra).toBeNil()
			-- graph actions on removed components are skipped
			for _, a in low.schedule do
				expect(a.componentId == "ultra").toBe(false)
			end
			local def = effect({
				{ id = "g", name = "G", type = "group", minQuality = "High" },
				{ id = "child", name = "Child", type = "part", parent = "g" },
				{ id = "grandchild", name = "Grandchild", type = "part", parent = "child" },
				{ id = "other", name = "Other", type = "part" },
			})
			expect(ids(Compiler.compile(def, { quality = "Medium" }))).toEqual({ "other" })
			expect(ids(Compiler.compile(def, { quality = "High" }))).toEqual({ "g", "child", "grandchild", "other" })
		end)

		T.it("drops lights beyond quality.maxLights in component order", function()
			local def = effect({
				{ id = "l1", name = "L1", type = "light" },
				{ id = "off", name = "Off", type = "light", enabled = false },
				{ id = "l2", name = "L2", type = "light" },
				{ id = "g", name = "G", type = "group" },
				{ id = "l3", name = "L3", type = "light", parent = "g" },
				{ id = "underL3", name = "Under L3", type = "part", parent = "l3" },
				{ id = "l4", name = "L4", type = "light" },
				{ id = "l5", name = "L5", type = "light" },
				{ id = "l6", name = "L6", type = "light" },
			})
			-- Low: 2 lights; the disabled light does not count; children of dropped lights go too
			expect(ids(Compiler.compile(def, { quality = "Low" }))).toEqual({ "l1", "l2", "g" })
			expect(ids(Compiler.compile(def, { quality = "Medium" }))).toEqual({
				"l1",
				"l2",
				"g",
				"l3",
				"underL3",
				"l4",
			})
			expect(#Compiler.compile(def, { quality = "High" }).components).toBe(8)
			-- per-effect quality overrides change the limit
			def.quality = { Low = { maxLights = 0 } }
			expect(ids(Compiler.compile(def, { quality = "Low" }))).toEqual({ "g" })
		end)

		T.it("accepts a QualityProfile and merges the definition's quality overrides", function()
			local def = effect({ { id = "p", name = "P", type = "particles", properties = { rate = 100 } } })
			local profile = Quality.resolve("High")
			profile.countScale = 0.5
			expect(Compiler.compile(def, { quality = profile }).byId.p.props.rate).toBe(50)
			def.quality = { Medium = { countScale = 0.1 } }
			local compiled = Compiler.compile(def, { quality = "Medium" })
			expect(compiled.quality.countScale).toBe(0.1)
			expect(compiled.byId.p.props.rate).toBeCloseTo(10, 1e-9)
			-- "Auto" / nil resolve through Quality.detect() (Medium outside a live client)
			expect(Compiler.compile(def).quality.level).toBe(Quality.detect())
			expect(Compiler.compile(def, { quality = "Auto" }).quality.level).toBe(Quality.detect())
		end)

		T.it("keeps Beam.Segments as the descriptor declares it (quality rule from the registry)", function()
			-- docs/ARCHITECTURE.md §5.4 + constraints K14 say Beam.Segments must NOT be quality-scaled, but the beam
			-- descriptor declares quality = "segments"; the Compiler follows the registry (single source of truth).
			local spec = Components.propertySpec("beam", "segments")
			local low = Compiler.compile(full(), { quality = "Low" })
			if spec.quality == "segments" then
				expect(low.byId.slash.props.segments).toBe(10)
			else
				expect(low.byId.slash.props.segments).toBe(20)
			end
		end)
	end)

	T.describe("Compiler.compile — effect scale", function()
		local function expectScaled(kind: string, a: any, b: any, factor: number, label: string)
			local t = typeof(a)
			if t == "number" then
				expect(b).toBeCloseTo(a * factor, 1e-6)
			elseif t == "Vector3" or t == "Vector2" then
				expect(b).toBeCloseTo(a * factor, 1e-5)
			elseif t == "NumberRange" then
				expect(b.Min).toBeCloseTo(a.Min * factor, 1e-5)
				expect(b.Max).toBeCloseTo(a.Max * factor, 1e-5)
			elseif t == "NumberSequence" then
				expect(#b.Keypoints).toBe(#a.Keypoints)
				for i, k in a.Keypoints do
					expect(b.Keypoints[i].Time).toBe(k.Time)
					expect(b.Keypoints[i].Value).toBeCloseTo(k.Value * factor, 1e-5)
					expect(b.Keypoints[i].Envelope).toBeCloseTo(k.Envelope * factor, 1e-5)
				end
			else
				error(label .. ": unexpected length kind " .. kind .. " / " .. t)
			end
		end

		T.it("scale 2 doubles every length property and leaves the rest unchanged", function()
			local one = Compiler.compile(full(), { quality = "High" })
			local two = Compiler.compile(full(), { quality = "High", scale = 2 })
			expect(two.scale).toBe(2)
			local checked = 0
			for _, c in one.components do
				local other = two.byId[c.id]
				for _, spec in Components.get(c.type).properties do
					local a, b = c.props[spec.name], other.props[spec.name]
					if spec.scale == "length" then
						expectScaled(spec.kind, a, b, 2, c.id .. "." .. spec.name)
						checked += 1
					else
						expect(b).toEqual(a)
					end
				end
			end
			expect(checked > 40).toBe(true)
			-- spot checks with hand-written numbers
			expect(two.byId.sparks.props.speed).toBe(NumberRange.new(20, 40))
			expect(two.byId.sparks.props.emitterSize).toBe(Vector3.new(4, 4, 4))
			expect(two.byId.slash.props.width0).toBe(4)
			expect(two.byId.slash.props.to).toBe(Vector3.new(8, 0, 0))
			expect(two.byId.glow.props.range).toBe(32) -- descriptors clamp the engine limit (120) themselves
			expect(two.byId.rocks.props.gravity).toBe(Vector3.new(0, -120, 0))
			expect(two.byId.rocks.props.spinSpeed).toBe(one.byId.rocks.props.spinSpeed) -- degrees: not a length
			expect(two.byId.boom.props.volume).toBe(0.8)
		end)

		T.it("scales rest positions and length channels, not rotations or the component's own scale", function()
			local one = Compiler.compile(full(), { quality = "High" })
			local two = Compiler.compile(full(), { quality = "High", scale = 2 })
			expect(two.byId.pivot.position).toBe(Vector3.new(0, 4, 0))
			expect(two.byId.swoosh.position).toBe(Vector3.new(6, 0, 0))
			expect(two.byId.pivot.rotation).toBe(Vector3.new(0, 45, 0))
			expect(two.byId.orb.scale).toBe(1.5)
			-- part.size (length channel) doubles, beam width0 (length) doubles, particles rate does not
			expect(Curves.evaluate(two.byId.core.tracks.size, 0.5)).toBe(Vector3.new(6, 6, 6))
			expect(Curves.evaluate(two.byId.slash.tracks.width0, 0.2)).toBe(4)
			expect(two.byId.sparks.tracks.rate.keys[1].value).toBe(one.byId.sparks.tracks.rate.keys[1].value)
			-- graph channel values follow the same rule (part transparency is not a length)
			expect(two.schedule[6].value).toBe(1)
		end)

		T.it("rejects invalid scales", function()
			expect(function()
				Compiler.compile(full(), { scale = 0 })
			end).toThrow("scale")
			expect(function()
				Compiler.compile(full(), { scale = -1 })
			end).toThrow("scale")
			expect(function()
				Compiler.compile(full(), { scale = math.huge })
			end).toThrow("scale")
		end)
	end)

	T.describe("Compiler.compile — palette and seeds", function()
		T.it("resolves $name references through the definition palette merged with overrides", function()
			local green = Color3.fromRGB(0, 255, 0)
			local compiled = Compiler.compile(full(), { quality = "High", palette = { primary = green } })
			expect(compiled.palette.primary).toBe(green)
			expect(compiled.palette.hot).toBe(WHITE)
			expect(compiled.byId.slash.props.color).toBe(ColorSequence.new(green))
			expect(compiled.byId.sparks.props.color.Keypoints[1].Value).toBe(green)
			expect(compiled.byId.sparks.props.color.Keypoints[2].Value).toBe(WHITE)
			expect(compiled.byId.energy.props.shellColor).toBe(green)
			expect(compiled.byId.glow.props.color).toBe(green)
			-- tracks resolve through the same palette
			local def = effect({
				{
					id = "p",
					name = "P",
					type = "part",
					tracks = {
						{
							id = "c",
							channel = "color",
							keyframes = { { time = 0, value = "$accent" }, { time = 1, value = "#000000" } },
						},
					},
				},
			}, { palette = { accent = "#FF0000" } })
			local plain = Compiler.compile(def, { quality = "High" })
			expect(Curves.evaluate(plain.byId.p.tracks.color, 0)).toBe(Color3.fromRGB(255, 0, 0))
			local blue = Color3.fromRGB(0, 0, 255)
			local over = Compiler.compile(def, { quality = "High", palette = { accent = blue, extra = blue } })
			expect(Curves.evaluate(over.byId.p.tracks.color, 0)).toBe(blue)
			expect(over.palette.extra).toBe(blue)
		end)

		T.it("rejects palette overrides that are not colours", function()
			expect(function()
				Compiler.compile(full(), { palette = { primary = 5 :: any } })
			end).toThrow("palette")
		end)

		T.it("uses options.seed, then def.seed, then a hash of the id", function()
			local def = full()
			expect(Compiler.compile(def, { quality = "High" }).seed).toBe(42)
			local seeded = Compiler.compile(def, { quality = "High", seed = 7 })
			expect(seeded.seed).toBe(7)
			expect(seeded.byId.rocks.seed).toBe(Random.hash(7, "rocks"))
			def.seed = nil
			expect(Compiler.compile(def, { quality = "High" }).seed).toBe(Random.hash("violetImpact"))
		end)
	end)

	T.describe("Compiler.compile — order and robustness", function()
		T.it("orders parents before children and otherwise keeps definition order", function()
			local def = effect({
				{ id = "child", name = "Child", type = "part", parent = "mid" },
				{ id = "a", name = "A", type = "part" },
				{ id = "mid", name = "Mid", type = "group", parent = "top" },
				{ id = "top", name = "Top", type = "group" },
				{ id = "b", name = "B", type = "part", parent = "top" },
			})
			local compiled = Compiler.compile(def, { quality = "High" })
			expect(ids(compiled)).toEqual({ "a", "top", "mid", "child", "b" })
			expect(compiled.byId.top.depth).toBe(0)
			expect(compiled.byId.mid.depth).toBe(1)
			expect(compiled.byId.child.depth).toBe(2)
			expect(compiled.byId.b.depth).toBe(1)
			expect(compiled.byId.child.parentId).toBe("mid")
		end)

		T.it("skips unknown types, duplicate ids, parent cycles and undeclared track channels with warnings", function()
			local def = effect({
				{ id = "x", name = "X", type = "doesNotExist" },
				{ id = "xChild", name = "X Child", type = "part", parent = "x" },
				{ id = "dup", name = "Dup", type = "part" },
				{ id = "dup", name = "Dup 2", type = "part" },
				{ id = "c1", name = "C1", type = "group", parent = "c2" },
				{ id = "c2", name = "C2", type = "group", parent = "c1" },
				{ id = "orphan", name = "Orphan", type = "part", parent = "missing", minQuality = "Ultra" },
				{
					id = "t",
					name = "T",
					type = "part",
					tracks = {
						{ id = "bad", channel = "nope", keyframes = { { time = 0, value = 1 } } },
						{ id = "t1", channel = "transparency", keyframes = { { time = 0, value = 0.5 } } },
						{ id = "t2", channel = "transparency", keyframes = { { time = 0, value = 0.9 } } },
					},
				},
			})
			local compiled, diagnostics = Compiler.compile(def, { quality = "High" })
			expect(ids(compiled)).toEqual({ "dup", "orphan", "t" })
			expect(compiled.byId.orphan.parentId).toBeNil()
			expect(Curves.evaluate(compiled.byId.t.tracks.transparency, 0)).toBe(0.5) -- first track wins
			local codes: { [string]: number } = {}
			for _, d in diagnostics do
				expect(d.severity).toBe("warning")
				codes[d.code] = (codes[d.code] or 0) + 1
			end
			expect(codes["compiler.component_type"]).toBe(1)
			expect(codes["compiler.component_id"]).toBe(1)
			expect(codes["compiler.parent_cycle"]).toBe(2)
			expect(codes["compiler.parent"]).toBe(1)
			expect(codes["compiler.track_channel"]).toBe(1)
			expect(codes["compiler.track_duplicate"]).toBe(1)
		end)

		T.it("reports invalid property values with the component and property", function()
			local def = effect({ { id = "p", name = "P", type = "part", properties = { size = "big" } } })
			expect(function()
				Compiler.compile(def, { quality = "High" })
			end).toThrow('"p" property "size"')
			local ref = effect({ { id = "p", name = "P", type = "part", properties = { color = "$nope" } } })
			expect(function()
				Compiler.compile(ref, { quality = "High" })
			end).toThrow("palette")
		end)

		T.it("passes graph unrolling limits on as warnings", function()
			local def = effect({ { id = "p", name = "P", type = "particles" } }, {
				graph = {
					nodes = {
						{ id = "play", type = "OnPlay" },
						{ id = "outer", type = "Loop", params = { count = 100, interval = 0.01 } },
						{ id = "inner", type = "Loop", params = { count = 100, interval = 0 } },
						{ id = "fan", type = "Parallel", params = { count = 2 } },
						{ id = "e1", type = "Emit", params = { target = "p", count = 1 } },
						{ id = "e2", type = "Emit", params = { target = "p", count = 1 } },
					},
					links = {
						{ from = "play.out", to = "outer.in" },
						{ from = "outer.body", to = "inner.in" },
						{ from = "inner.body", to = "fan.in" },
						{ from = "fan.out1", to = "e1.in" },
						{ from = "fan.out2", to = "e2.in" },
					},
				},
			})
			local compiled, diagnostics = Compiler.compile(def, { quality = "High" })
			expect(#compiled.schedule).toBe(10000) -- Constants.MAX_GRAPH_ACTIONS
			local codes = {}
			for _, d in diagnostics do
				table.insert(codes, d.code)
			end
			expect(codes).toEqual({ "graph.action_limit" })
		end)

		T.it("compiles an effect without components, markers or graph", function()
			local compiled, diagnostics = Compiler.compile(effect({}), { quality = "Low" })
			expect(#compiled.components).toBe(0)
			expect(#compiled.schedule).toBe(0)
			expect(compiled.graph).toBeNil()
			expect(compiled.maxTail).toBe(0)
			expect(#diagnostics).toBe(0)
		end)
	end)

	T.describe("Compiler.scheduleForCycle", function()
		T.it("returns the compiled schedule for cycle 0 and regenerates graph randomness per cycle", function()
			local compiled = Compiler.compile(full(), { quality = "High" })
			expect(Compiler.scheduleForCycle(compiled, 0)).toBe(compiled.schedule)
			local base = withoutGraphCounts(compiled.schedule)
			local counts: { [number]: boolean } = { [compiled.schedule[1].count] = true }
			local distinct = 1
			for cycle = 1, 6 do
				local schedule = Compiler.scheduleForCycle(compiled, cycle)
				expect(schedule).never.toBe(compiled.schedule)
				-- same actions and times; only the random graph count may change
				expect(withoutGraphCounts(schedule)).toEqual(base)
				for i, a in schedule do
					expect(a.order).toBe(i)
				end
				local n = schedule[1].count
				if not counts[n] then
					counts[n] = true
					distinct += 1
				end
				-- deterministic per cycle
				expect(rows(Compiler.scheduleForCycle(compiled, cycle))).toEqual(rows(schedule))
			end
			expect(distinct > 1).toBe(true)
		end)

		T.it("returns the static schedule unchanged for effects without a graph", function()
			local def = full()
			def.graph = nil
			local compiled = Compiler.compile(def, { quality = "High" })
			expect(compiled.graph).toBeNil()
			expect(Compiler.scheduleForCycle(compiled, 4)).toBe(compiled.schedule)
			expect(#compiled.schedule).toBe(6)
		end)
	end)

	T.describe("Compiler.key", function()
		T.it("is stable for equal input and changes with content and every option", function()
			local def = full()
			local base = Compiler.key(def, { quality = "High" })
			expect(Compiler.key(full(), { quality = "High" })).toBe(base)
			expect(string.sub(base, 1, #"violetImpact|")).toBe("violetImpact|")
			local variants = {
				Compiler.key(def, { quality = "Low" }),
				Compiler.key(def, { quality = "High", scale = 2 }),
				Compiler.key(def, { quality = "High", seed = 1 }),
				Compiler.key(def, { quality = "High", palette = { primary = Color3.new(1, 0, 0) } }),
				Compiler.key(def, { quality = "High", palette = { primary = Color3.new(1, 0, 0.5) } }),
			}
			local changed = full()
			changed.components[2].properties.rate = 41
			table.insert(variants, Compiler.key(changed, { quality = "High" }))
			local seen = { [base] = true }
			for _, k in variants do
				expect(seen[k]).toBeNil()
				seen[k] = true
			end
			-- an explicit seed equal to def.seed compiles the same effect -> same key
			expect(Compiler.key(def, { quality = "High", seed = 42 })).toBe(base)
			-- "Auto" keys by the detected level
			expect(Compiler.key(def, { quality = "Auto" })).toBe(Compiler.key(def, { quality = Quality.detect() }))
			-- palette override order does not matter
			local p1 = Compiler.key(def, { palette = { a = Color3.new(1, 0, 0), b = Color3.new(0, 1, 0) } })
			local p2 = Compiler.key(def, { palette = { b = Color3.new(0, 1, 0), a = Color3.new(1, 0, 0) } })
			expect(p1).toBe(p2)
		end)

		T.it("accepts a precomputed content hash", function()
			local def = full()
			local hash = Compiler.contentHash(def)
			expect(hash).toBe(Compiler.contentHash(full()))
			expect(Compiler.key(def, { quality = "Low" }, hash)).toBe(Compiler.key(def, { quality = "Low" }))
			expect(Compiler.key(def, { quality = "Low" }, "other")).never.toBe(Compiler.key(def, { quality = "Low" }))
		end)
	end)
end
