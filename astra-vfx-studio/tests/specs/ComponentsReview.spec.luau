--!strict
--[[
	Regression specs for the adversarial review of the component descriptors (Core/Components/*).

	Each `describe` block pins one defect that the family specs (ComponentsNative / ComponentsGeometry /
	ComponentsProcedural) did not catch. The tests were written to fail against the reviewed descriptors and pass
	after the fix:

	  1. particles  — continuous emission kept running while the Player was seeking (spec: seek = "no emission").
	  2. particles  — the transparency fade left NumberSequence envelopes untouched, so fade = 1 still showed
	                  particles whose random offset was negative (value 1, envelope e → visible down to 1 − e).
	  3. particles  — the `rate` channel multiplied its values by quality.countScale although its baseProperty is
	                  the already quality-scaled `rate` property: applying the rest value changed the built Rate.
	  4. trail      — seeking jumps drew streaks between scrubbed positions (segments cannot be reconstructed, so
	                  a seek must clear them like the Player clears particles).
	  5. beam       — Segments could drop below (gradient keypoints − 1) after the Compiler's segment quality
	                  scaling, which breaks colour/transparency gradients (engine fact, research §2.6).
	  6. lightning  — authored `regenerate` events were counted per execution, so replaying/scrubbing over them
	                  changed the shape at the same local time (procedural components must be pure functions of
	                  local time).
]]

return function(T: any, use: (string) -> any, ctx: any)
	local Harness = use("Tests.Specs.Helpers.ComponentHarness")
	local Components = use("AstraVFX.Core.Components")
	local Constants = use("AstraVFX.Core.Constants")
	local expect = T.expect
	local isLune = ctx.environment == "lune"
	local fakes = ctx.fakes

	local LOW = {
		level = "Low",
		countScale = 0.35,
		segmentScale = 0.5,
		sizeCompensation = 1.12,
		lightShadows = false,
		maxLights = 2,
	}

	local open: { any } = {}
	local function harness(): any
		local h = Harness.new(use)
		table.insert(open, h)
		return h
	end

	T.afterEach(function()
		for _, h in open do
			h:cleanup()
		end
		table.clear(open)
	end)

	-- Builds with a custom CompiledComponent (post-Compiler values, events) or BuildContext.
	local function buildWith(h: any, componentType: string, props: { [string]: any }?, options: any?, mutate: any?)
		local component = h:compile(componentType, props, options)
		local bctx = h:context({ [component.id] = component }, options)
		if mutate then
			mutate(component, bctx)
		end
		local controller = Components.get(componentType).build(bctx, component)
		table.insert(h.controllers, controller)
		return controller, component, bctx
	end

	-- One Player frame in the documented order: setActive (on change) → apply → setTransform → update → flush.
	local function step(h: any, c: any, localTime: number, seeking: boolean?, world: CFrame?)
		local f = h:frame(localTime, if seeking then 0 else 1 / 60, seeking)
		local cf = world or CFrame.new()
		c:setTransform(cf, h.root.CFrame * cf, f)
		if c.update then
			c:update(localTime, f)
		end
		h:flush(f)
		return f
	end

	local function clearsOf(inst: any): number
		local n = 0
		for _, c in fakes.clears do
			if c == inst then
				n += 1
			end
		end
		return n
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- 1. particles: no continuous emission while seeking
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("review: particles while seeking", function()
		T.it("keeps continuous emission off during seek frames and resumes on the next playback frame", function()
			local h = harness()
			local c = h:build("particles", { rate = 50 })
			local e = c.instances[1]
			c:setActive(true, h:frame(0.5, 0, true))
			expect(e.Enabled).toBe(false)
			step(h, c, 0.5, true)
			expect(e.Enabled).toBe(false)
			step(h, c, 0.52, false)
			expect(e.Enabled).toBe(true)
			-- A seek in the middle of playback switches emission off again until playback continues.
			step(h, c, 1.5, true)
			expect(e.Enabled).toBe(false)
			step(h, c, 1.52, false)
			expect(e.Enabled).toBe(true)
		end)

		T.it("a seek never re-enables an emitter that a disable event, rate 0 or release() switched off", function()
			local h = harness()
			local c = h:build("particles", { rate = 50 })
			local e = c.instances[1]
			c:setActive(true, h:frame(0, 1 / 60))
			c:onAction({ time = 0, action = "disable", source = "event", order = 1 }, h:frame(0, 1 / 60))
			step(h, c, 0.1, true)
			step(h, c, 0.2, false)
			expect(e.Enabled).toBe(false)
			c:onAction({ time = 0.2, action = "enable", source = "event", order = 2 }, h:frame(0.2, 1 / 60))
			expect(e.Enabled).toBe(true)
			c:release()
			step(h, c, 0.3, true)
			step(h, c, 0.4, false)
			expect(e.Enabled).toBe(false)
		end)

		T.it("reset() forgets a pending seek state", function()
			local h = harness()
			local c = h:build("particles", { rate = 50 })
			local e = c.instances[1]
			c:setActive(true, h:frame(0, 0, true))
			c:reset()
			c:setActive(true, h:frame(0, 1 / 60))
			expect(e.Enabled).toBe(true)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 2. particles: the fade also scales the envelopes
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("review: particles transparency fade with envelopes", function()
		T.it("fade = 1 hides every particle, including those with a negative random offset", function()
			local h = harness()
			local c = h:build("particles", { transparency = { { 0, 0.5, 0.5 }, { 1, 0.2, 0.1 } } })
			local e = c.instances[1]
			c:apply("transparency", 1)
			for _, k in e.Transparency.Keypoints do
				expect(k.Value).toBeCloseTo(1, 1e-6)
				expect(k.Value - k.Envelope).toBeGreaterThanOrEqual(1 - 1e-6)
			end
		end)

		T.it("maps the whole envelope range through t' = 1 - (1 - t)(1 - fade)", function()
			local h = harness()
			local c = h:build("particles", { transparency = { { 0, 0.5, 0.5 }, { 1, 0.2, 0.1 } } })
			local e = c.instances[1]
			c:apply("transparency", 0.5)
			local k = e.Transparency.Keypoints
			expect(k[1].Value).toBeCloseTo(0.75, 1e-6)
			expect(k[1].Envelope).toBeCloseTo(0.25, 1e-6)
			expect(k[2].Value).toBeCloseTo(0.6, 1e-6)
			expect(k[2].Envelope).toBeCloseTo(0.05, 1e-6)
			-- Both ends of every keypoint's random range follow the fade formula.
			local lo, hi = 0.5 - 0.5, 0.5 + 0.5
			expect(k[1].Value - k[1].Envelope).toBeCloseTo(1 - (1 - lo) * 0.5, 1e-6)
			expect(k[1].Value + k[1].Envelope).toBeCloseTo(1 - (1 - hi) * 0.5, 1e-6)
			c:apply("transparency", 0)
			local restored = e.Transparency.Keypoints
			expect(restored[1].Value).toBeCloseTo(0.5, 1e-6)
			expect(restored[1].Envelope).toBeCloseTo(0.5, 1e-6)
			expect(restored[2].Envelope).toBeCloseTo(0.1, 1e-6)
		end)

		T.it("keeps the keypoint count (Roblox limit 20)", function()
			local h = harness()
			local keys = {}
			for i = 0, 19 do
				table.insert(keys, { i / 19, (i % 3) / 4, 0.1 })
			end
			local c = h:build("particles", { transparency = keys })
			c:apply("transparency", 0.3)
			expect(#c.instances[1].Transparency.Keypoints).toBe(20)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 3. particles: the rate channel works in the compiled (quality-scaled) domain of its baseProperty
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("review: particles rate channel domain", function()
		T.it("applying the channel's rest value (props.rate, already quality-scaled) keeps the built Rate", function()
			local h = harness()
			-- What the Compiler hands the descriptor on Low: rate 20 × countScale 0.35 = 7.
			local c, component = buildWith(h, "particles", { rate = 7 }, { quality = LOW })
			local e = c.instances[1]
			expect(e.Rate).toBe(7)
			c:apply("rate", component.props.rate)
			expect(e.Rate).toBe(7)
		end)

		T.it("writes channel values as given (clamped to the engine cap), never scaled a second time", function()
			local h = harness()
			local c = buildWith(h, "particles", { rate = 7 }, { quality = LOW })
			local e = c.instances[1]
			c:apply("rate", 100)
			expect(e.Rate).toBe(100)
			c:apply("rate", 5000)
			expect(e.Rate).toBe(Constants.MAX_PARTICLE_RATE)
			c:apply("rate", -1)
			expect(e.Rate).toBe(0)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 4. trail: seeking clears drawn segments
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("review: trail while seeking", function()
		T.itIf(isLune, "clears after every seeking transform and never during playback transforms", function()
			local h = harness()
			local c = h:build("trail", { clearOnStart = false })
			local trail = c.instances[1]
			c:setActive(true, h:frame(0, 1 / 60))
			step(h, c, 0, false, CFrame.new(0, 0, 0))
			step(h, c, 0.1, false, CFrame.new(1, 0, 0))
			expect(clearsOf(trail)).toBe(0)
			-- Scrub to t = 1: the attachments jump; the streak from the old position must not survive.
			step(h, c, 1, true, CFrame.new(40, 0, 0))
			expect(clearsOf(trail)).toBe(1)
			-- Scrub again without moving: still a seek, still cleared (state at t has no drawn segments).
			step(h, c, 1, true, CFrame.new(40, 0, 0))
			expect(clearsOf(trail)).toBe(2)
			-- Playback continues from the scrubbed position: the trail draws normally again.
			step(h, c, 1.02, false, CFrame.new(41, 0, 0))
			expect(clearsOf(trail)).toBe(2)
			expect(trail.Enabled).toBe(true)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 5. beam: Segments never below gradient keypoints - 1
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("review: beam segments vs gradient keypoints", function()
		local function colorKeys(n: number): { any }
			local keys = {}
			for i = 0, n - 1 do
				local key: { any } = { i / (n - 1), if i % 2 == 0 then "#FF0000" else "#0000FF" }
				table.insert(keys, key)
			end
			return keys
		end
		local function numberKeys(n: number): { any }
			local keys = {}
			for i = 0, n - 1 do
				table.insert(keys, { i / (n - 1), (i % 2) * 0.8 })
			end
			return keys
		end

		T.it("raises Segments to (colour keypoints - 1) after quality lowered them", function()
			local h = harness()
			-- segments 10 at High → 5 after segmentScale 0.5 (what the Compiler passes on Low).
			local c = h:build("beam", { color = colorKeys(12), segments = 5 })
			expect(c.instances[1].Segments).toBe(11)
		end)

		T.it("raises Segments to (transparency keypoints - 1) as well", function()
			local h = harness()
			local c = h:build("beam", { transparency = numberKeys(15), segments = 3 })
			expect(c.instances[1].Segments).toBe(14)
		end)

		T.it("keeps authored segments when they already cover the gradient", function()
			local h = harness()
			local c = h:build("beam", { color = colorKeys(4), segments = 20 })
			expect(c.instances[1].Segments).toBe(20)
			local plain = h:build("beam", { segments = 1 })
			expect(plain.instances[1].Segments).toBe(1)
		end)

		T.it("reset() and channel changes keep the gradient floor", function()
			local h = harness()
			local c = h:build("beam", { color = colorKeys(12), segments = 2 })
			c:setActive(true, h:frame(0, 1 / 60))
			c:apply("tint", Color3.new(0.5, 0.5, 0.5))
			c:apply("transparency", 0.4)
			c:reset()
			expect(c.instances[1].Segments).toBe(11)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 6. lightning: authored regenerate events are part of the pure shape function
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("review: lightning regenerate events and scrubbing", function()
		local EVENT_TIME = 0.5

		local function regenerateAction(order: number): any
			return {
				time = EVENT_TIME,
				action = "regenerate",
				source = "event",
				sourceId = "regen1",
				order = order,
			}
		end

		-- Builds a static (flickerRate 0) part-mode bolt with one authored regenerate event at 0.5 s, runs
		-- `history` ({ localTime, executeEvent?, seeking? } per frame) and returns the segment CFrames.
		local function shapeAfter(history: { { any } }): string
			local h = harness()
			local c, component = buildWith(
				h,
				"lightning",
				{ flickerRate = 0, render = "part" },
				nil,
				function(comp: any)
					comp.events = { { id = "regen1", time = EVENT_TIME, action = "regenerate" } }
				end
			)
			c:setActive(true, h:frame(0, 1 / 60))
			for i, entry in history do
				local t: number = entry[1]
				local f = step(h, c, t, entry[3] == true)
				if entry[2] then
					c:onAction(regenerateAction(i), f)
					h:flush(f)
				end
			end
			local rows = {}
			for _, inst: any in h:instancesOf(component.id) do
				table.insert(rows, inst.Name .. "=" .. tostring(inst.CFrame) .. "/" .. tostring(inst.Size))
			end
			table.sort(rows)
			return table.concat(rows, "\n")
		end

		T.it("the shape at a local time does not depend on how often the event was replayed", function()
			local fresh = shapeAfter({ { 0.7, true } })
			-- Play past the event, scrub back before it, scrub forward again (the Player may replay the event).
			local scrubbed = shapeAfter({ { 0.6, true }, { 0.2, false, true }, { 0.7, true, true } })
			expect(scrubbed).toBe(fresh)
		end)

		T.it("before the event the first shape is shown again after scrubbing back", function()
			local before = shapeAfter({ { 0.2 } })
			local back = shapeAfter({ { 0.6, true }, { 0.9 }, { 0.2, false, true } })
			expect(back).toBe(before)
		end)

		T.it("the authored event still changes the shape when its time is reached", function()
			expect(shapeAfter({ { 0.7, true } })).never.toBe(shapeAfter({ { 0.3 } }))
		end)

		T.it(
			"runtime regenerate actions (graph, no authored event) still draw a new shape; reset() restores",
			function()
				local h = harness()
				local c, component = h:build("lightning", { flickerRate = 0, render = "part" })
				c:setActive(true, h:frame(0, 1 / 60))
				step(h, c, 0.3)
				local function shape(): string
					local rows = {}
					for _, inst: any in h:instancesOf(component.id) do
						table.insert(rows, tostring(inst.CFrame))
					end
					table.sort(rows)
					return table.concat(rows, ";")
				end
				local first = shape()
				local f = h:frame(0.3, 1 / 60)
				c:onAction({ time = 0.3, action = "regenerate", source = "graph", sourceId = "node7", order = 1 }, f)
				h:flush(f)
				expect(shape()).never.toBe(first)
				c:reset()
				c:setActive(true, h:frame(0, 1 / 60))
				step(h, c, 0.3)
				expect(shape()).toBe(first)
			end
		)
	end)
end
