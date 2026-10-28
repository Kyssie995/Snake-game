--!strict
--[[
	ComponentsCamera — descriptor specs for the camera components cameraShake and screenFlash
	(docs/COMPONENTS_SPEC.md §17-18).

	Setup: every test gets a fresh Camera through Env.override("Workspace", { CurrentCamera = camera }) (tests swap
	cameras by changing that table's CurrentCamera, as the engine changes the property) and runs as a
	server (Env.override("Players", {}) — no LocalPlayer) unless it calls asClient() (a LocalPlayer). Render-step
	bindings go through the Lune fakes (tests/lune/Fakes.luau: renderBindings / renderLog / renderStep), so client
	tests run in Lune only; preview-mode tests need no fakes.

	Offsets are read back from the camera (`home:Inverse() * camera.CFrame` → pitch, yaw, roll, x, y, z). The
	cameraShake noise is internal, so envelope and falloff are checked as RATIOS between two builds with the same
	seed at the same local time (identical noise): e.g. a build in its decay vs one in its sustain. Lune rounds
	CFrame properties on the first write (~1e-5), hence the tolerances; `home` is the CFrame the camera holds after
	the assignment.

	Structure:
	  1. Spec fidelity: category, viewport flag, property ranges and clamping, channels, Theme colour.
	  2. cameraShake: server no-op, envelope, falloff, noise (bounded, smooth, seeded), channels, scale, preview
	     (opt-in, base capture, author camera moves, camera swap), client render-step lifecycle (names, priorities,
	     shared binding pair, no leaks), composition of concurrent shakes, no accumulation or drift, cost.
	  3. screenFlash: server no-op, effect lifecycle under the camera, envelope (pure function of time), write
	     caching, tint channel, release/reset/destroy, preview, camera swap, Lighting untouched, cost.
	  4. Builder integration in preview mode (preview tagging of the effect, cleanup).
]]

return function(T: any, use: (string) -> any, ctx: any)
	local Harness = use("Tests.Specs.Helpers.ComponentHarness")
	local Components = use("AstraVFX.Core.Components")
	local Codec = use("AstraVFX.Core.Codec")
	local Env = use("AstraVFX.Core.Env")
	local Compiler = use("AstraVFX.Core.Compiler")
	local Builder = use("AstraVFX.Core.Builder")
	local Constants = use("AstraVFX.Core.Constants")
	local expect = T.expect
	local isLune = ctx.environment == "lune"
	local fakes = ctx.fakes

	local RAD = math.pi / 180
	local TAU = 2 * math.pi
	local CAMERA_PRIORITY = Enum.RenderPriority.Camera.Value
	local START = CFrame.new(0, 5, 20) * CFrame.Angles(-0.2, 0.1, 0)
	local ANGLE_EPS = 2e-4 -- radians
	local STUD_EPS = 1e-3
	-- Strong shake so the signal dwarfs Lune's CFrame rounding.
	local BIG = { amplitude = 10, positionAmplitude = 2 }
	local HIGH = {
		level = "High",
		countScale = 1,
		segmentScale = 1,
		sizeCompensation = 1,
		lightShadows = true,
		maxLights = math.huge,
	}

	local camera: Camera = Instance.new("Camera")
	local home = START
	local open: { any } = {}
	-- Stand-in for the Workspace service: components keep the service, so a camera change is a property change.
	local workspaceFake: { CurrentCamera: Camera? } = { CurrentCamera = nil }

	local function harness(): any
		local h = Harness.new(use)
		table.insert(open, h)
		return h
	end

	local function useCamera(cam: Camera?)
		workspaceFake.CurrentCamera = cam
	end

	local function asClient()
		Env.override("Players", { LocalPlayer = { Name = "CameraSpecPlayer" } })
	end

	T.beforeEach(function()
		camera = Instance.new("Camera")
		camera.Name = "CameraSpecCamera"
		camera.CFrame = START
		home = camera.CFrame
		workspaceFake = { CurrentCamera = camera }
		Env.override("Workspace", workspaceFake)
		Env.override("Players", {}) -- server unless a test calls asClient()
	end)

	T.afterEach(function()
		for _, h in open do
			h:cleanup()
		end
		table.clear(open)
		if fakes then
			fakes:reset()
		end
		Env.override("Workspace", nil)
		Env.override("Players", nil)
		camera:Destroy()
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Helpers
	-- ─────────────────────────────────────────────────────────────────────────

	local function frame(h: any, t: number, seeking: boolean?): any
		return h:frame(t, if seeking then 0 else 1 / 60, seeking)
	end

	-- Where measured shakes sit by default: 2 studs in front of the camera (falloff 1).
	local function near(): CFrame
		return CFrame.new(home.Position + Vector3.new(0, 0, -2))
	end

	-- One Player frame at local time t (transform → update), then the render-step bindings (Lune).
	local function step(h: any, c: any, t: number, world: CFrame?, seeking: boolean?)
		local f = frame(h, t, seeking)
		local w = world or near()
		c:setTransform(w, w, f) -- the harness root sits at the origin: local = world
		if c.update then
			c:update(t, f)
		end
		if fakes then
			fakes:renderStep(f.dt)
		end
	end

	-- (pitch, yaw, roll, x, y, z) of the camera relative to `base` (default: home), radians and studs.
	local function offsetVector(base: CFrame?, cam: Camera?): { number }
		local o = (base or home):Inverse() * (cam or camera).CFrame
		local rx, ry, rz = o:ToOrientation()
		local p = o.Position
		return { rx, ry, rz, p.X, p.Y, p.Z }
	end

	local function scaled(v: { number }, rotation: number, position: number?): { number }
		local k = if position == nil then rotation else position
		return { v[1] * rotation, v[2] * rotation, v[3] * rotation, v[4] * k, v[5] * k, v[6] * k }
	end

	local function rotationSize(v: { number }): number
		return math.abs(v[1]) + math.abs(v[2]) + math.abs(v[3])
	end

	local function positionSize(v: { number }): number
		return math.abs(v[4]) + math.abs(v[5]) + math.abs(v[6])
	end

	local function expectVector(actual: { number }, wanted: { number }, label: string?)
		for i = 1, 6 do
			local eps = if i <= 3 then ANGLE_EPS else STUD_EPS
			if math.abs(actual[i] - wanted[i]) > eps then
				error(
					string.format(
						"%s component %d: got %.6f, expected %.6f (±%g)",
						label or "offset",
						i,
						actual[i],
						wanted[i],
						eps
					),
					2
				)
			end
		end
	end

	type MeasureOptions = {
		seed: number?,
		startTime: number?,
		endTime: number?,
		scale: number?,
		world: CFrame?,
	}

	-- Offset a fresh PREVIEW shake shows at local time t (previewInStudio forced on); destroyed afterwards, so the
	-- camera is back at home for the next measurement.
	local function measure(props: { [string]: any }?, t: number, options: MeasureOptions?): { number }
		local o: MeasureOptions = options or {}
		local p: { [string]: any } = table.clone(props or {})
		p.previewInStudio = true
		local h = harness()
		local c = h:build("cameraShake", p, {
			isPreview = true,
			seed = o.seed,
			startTime = o.startTime,
			endTime = o.endTime,
			scale = o.scale,
		})
		c:setActive(true, frame(h, t))
		step(h, c, t, o.world)
		local v = offsetVector()
		c:destroy()
		expect(camera.CFrame).toBe(home)
		return v
	end

	local function merge(a: { [string]: any }, b: { [string]: any }): { [string]: any }
		local out = table.clone(a)
		for k, v in b do
			out[k] = v
		end
		return out
	end

	local function effectsUnder(cam: Instance): { any }
		local out = {}
		for _, inst in cam:GetChildren() do
			if inst:IsA("ColorCorrectionEffect") then
				table.insert(out, inst)
			end
		end
		return out
	end

	local function bindings(): { any }
		local out = {}
		for _, b in fakes.renderBindings do
			table.insert(out, b)
		end
		table.sort(out, function(a: any, b: any): boolean
			return a.priority < b.priority
		end)
		return out
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- 1. Spec fidelity
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsCamera spec", function()
		T.it("registers both types in the Camera category, client-side only (no viewport, no events)", function()
			for _, typeName in { "cameraShake", "screenFlash" } do
				local d = Components.get(typeName)
				expect(d).never.toBeNil()
				expect(d.category).toBe("Camera")
				expect(d.supportsViewport).toBe(false)
				expect(d.canParent).toBe(true)
				expect(#d.events).toBe(0)
				expect(d.tailTime).toBeNil()
				expect(#d.description > 0).toBe(true)
			end
		end)

		T.it("cameraShake declares the §17 property ranges, defaults and length scaling", function()
			local rows: { { any } } = {
				{ "amplitude", "number", 0.6, 0, 20, nil },
				{ "positionAmplitude", "number", 0.15, 0, 10, "length" },
				{ "frequency", "number", 18, 0.1, 60, nil },
				{ "attack", "number", 0.02, 0, 5, nil },
				{ "decay", "number", 0.35, 0, 10, nil },
				{ "decayEasing", "string", "Quad.Out", nil, nil, nil },
				{ "rotationWeights", "vector3", { 1, 0.6, 0.3 }, 0, 1, nil },
				{ "innerRadius", "number", 20, 0, 10000, "length" },
				{ "outerRadius", "number", 120, 0, 10000, "length" },
				{ "previewInStudio", "boolean", false, nil, nil, nil },
			}
			local d = Components.get("cameraShake")
			expect(#d.properties).toBe(#rows)
			for i, row in rows do
				local p = d.properties[i]
				expect({ p.name, p.kind, p.min, p.max, p.scale }).toEqual({ row[1], row[2], row[4], row[5], row[6] })
				expect(p.default).toEqual(row[3])
			end
			local position = Components.channelSpec("cameraShake", "position")
			expect({ position.kind, position.scale }).toEqual({ "vector3", "length" })
			local amplitude = Components.channelSpec("cameraShake", "amplitude")
			local wanted: { any } = { "number", 0, 20, "amplitude" }
			expect({ amplitude.kind, amplitude.min, amplitude.max, amplitude.baseProperty }).toEqual(wanted)
			expect(#d.channels).toBe(2)
		end)

		T.it("screenFlash declares the §18 property ranges and defaults", function()
			local rows: { { any } } = {
				{ "brightness", "number", 0.35, -1, 2 },
				{ "contrast", "number", 0.8, -1, 3 },
				{ "saturation", "number", -0.6, -1, 2 },
				{ "tint", "color3", "#FFFFFF" },
				{ "attack", "number", 0.02, 0, 2 },
				{ "hold", "number", 0.05, 0, 2 },
				{ "decay", "number", 0.18, 0.01, 5 },
				{ "previewInStudio", "boolean", true },
			}
			local d = Components.get("screenFlash")
			expect(#d.properties).toBe(#rows)
			for i, row in rows do
				local p = d.properties[i]
				expect({ p.name, p.kind, p.min, p.max, p.scale }).toEqual({ row[1], row[2], row[4], row[5], nil })
				expect(p.default).toEqual(row[3])
			end
			local tint = Components.channelSpec("screenFlash", "tint")
			expect({ tint.kind, tint.baseProperty }).toEqual({ "color3", "tint" })
			expect(#d.channels).toBe(1)
		end)

		T.it("rejects out-of-range values in check() and clamps them when decoding", function()
			local cases: { { any } } = {
				{ "cameraShake", "amplitude", 25, 20 },
				{ "cameraShake", "amplitude", -1, 0 },
				{ "cameraShake", "frequency", 0, 0.1 },
				{ "cameraShake", "frequency", 90, 60 },
				{ "cameraShake", "decay", 11, 10 },
				{ "cameraShake", "innerRadius", 20000, 10000 },
				{ "screenFlash", "brightness", 5, 2 },
				{ "screenFlash", "contrast", -2, -1 },
				{ "screenFlash", "saturation", 3, 2 },
				{ "screenFlash", "decay", 0, 0.01 },
				{ "screenFlash", "hold", 3, 2 },
			}
			for _, case in cases do
				local spec = Components.propertySpec(case[1], case[2])
				local ok, _, problem = Codec.check(spec.kind, case[3], spec)
				expect({ case[2], ok, problem }).toEqual({ case[2], false, "range" })
				expect(Codec.decode(spec.kind, case[3], spec)).toBe(case[4])
			end
			local weights = Components.propertySpec("cameraShake", "rotationWeights")
			expect(Codec.decode("vector3", { 2, -1, 0.5 }, weights)).toBe(Vector3.new(1, 0, 0.5))
		end)

		T.it("gives the Camera category its own colour in Theme.categoryColors", function()
			local Theme = use("Plugin.UI.Theme")
			local colour = Theme.categoryColors.Camera
			expect(typeof(colour)).toBe("Color3")
			for name, other in Theme.categoryColors :: { [string]: Color3 } do
				if name ~= "Camera" then
					expect(other ~= colour).toBe(true)
				end
			end
			expect(Theme.categoryColor("Camera")).toBe(colour)
			-- every registered category has a colour
			for _, d in Components.list() do
				expect((Theme.categoryColors :: any)[d.category] ~= nil).toBe(true)
			end
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 2. cameraShake
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsCamera cameraShake", function()
		T.it("is a no-op on a server: no instances, no bindings, the camera never moves", function()
			local h = harness()
			local c, component = h:build("cameraShake", BIG)
			expect(#c.instances).toBe(0)
			c:setActive(true, frame(h, 0.1))
			for _, t in { 0.1, 0.3, 0.6 } do
				step(h, c, t)
			end
			expect(camera.CFrame).toBe(home)
			if fakes then
				expect(#fakes.renderLog).toBe(0)
			end
			expect(#h:instancesOf(component.id)).toBe(0)
			expect(#h.container:GetChildren()).toBe(1)
			c:setActive(false, frame(h, 0.7))
			c:destroy()
			expect(camera.CFrame).toBe(home)
		end)

		T.it("does nothing in the editor preview unless previewInStudio is set", function()
			local h = harness()
			local c = h:build("cameraShake", BIG, { isPreview = true })
			c:setActive(true, frame(h, 0.3))
			step(h, c, 0.3)
			step(h, c, 0.4)
			expect(camera.CFrame).toBe(home)
			if fakes then
				expect(#fakes.renderLog).toBe(0)
			end
		end)

		T.it("does nothing in a viewport build, even with previewInStudio", function()
			local h = harness()
			local c =
				h:build("cameraShake", merge(BIG, { previewInStudio = true }), { isPreview = true, viewport = true })
			c:setActive(true, frame(h, 0.3))
			step(h, c, 0.3)
			expect(camera.CFrame).toBe(home)
		end)

		T.it("shakes the preview camera relative to the base captured at activation and restores it", function()
			local expected = measure(BIG, 0.35) -- reference first: active shakes share the camera
			local h = harness()
			local c = h:build("cameraShake", merge(BIG, { previewInStudio = true }), { isPreview = true })
			c:setActive(true, frame(h, 0.3))
			step(h, c, 0.3)
			local a = offsetVector()
			expect(rotationSize(a)).toBeGreaterThan(0.01)
			expect(positionSize(a)).toBeGreaterThan(0.01)
			step(h, c, 0.35)
			local b = offsetVector()
			-- each frame is base × offset(t), not an accumulation
			expectVector(b, expected, "t = 0.35")
			c:setActive(false, frame(h, 0.4))
			expect(camera.CFrame).toBe(home)
			if fakes then
				expect(#fakes.renderLog).toBe(0) -- the preview never binds render steps
			end
		end)

		T.it("follows the envelope: attack ramp, sustain, eased decay, zero outside the span", function()
			local t0 = 0.8
			local sustain = measure(merge(BIG, { attack = 0 }), t0, { endTime = 10 })
			expect(rotationSize(sustain)).toBeGreaterThan(0.01)
			local cases: { { any } } = {
				-- props, endTime, expected strength
				{ { attack = 0 }, 10, 1 },
				{ { attack = 3.2 }, 10, 0.25 },
				{ { decay = 0.4, decayEasing = "Linear" }, 1, 0.5 },
				{ { decay = 0.4 }, 1, 0.25 }, -- default Quad.Out: 1 − (1 − (1 − 0.5)²)
				{ { decay = 0.4, decayEasing = "Quad.In" }, 1, 0.75 },
				{ { decay = 0.4, decayEasing = "NoSuchEasing" }, 1, 0.5 }, -- invalid → Linear
				{ { decay = 1.6, decayEasing = "Linear" }, 1.6, 0.5 },
				{ { decay = 0 }, 0.81, 1 },
				{ { attack = 1.6, decay = 1, decayEasing = "Linear" }, 1, 0.2 }, -- overlap: min(0.5, 0.2)
			}
			for i, case in cases do
				local v = measure(merge(BIG, case[1]), t0, { endTime = case[2] })
				expectVector(v, scaled(sustain, case[3]), "case " .. i)
			end
			-- span end and beyond, before the start
			for _, t in { 1, 1.2 } do
				expectVector(measure(BIG, t, { endTime = 1 }), scaled(sustain, 0), "t = " .. t)
			end
			local h = harness()
			local c = h:build("cameraShake", merge(BIG, { previewInStudio = true }), { isPreview = true })
			c:setActive(true, frame(h, 0))
			step(h, c, -0.1)
			expect(camera.CFrame).toBe(home)
		end)

		T.it("is a pure function of local time (scrubbing in any order, seeking frames)", function()
			local direct = measure(BIG, 0.5)
			local h = harness()
			local c = h:build("cameraShake", merge(BIG, { previewInStudio = true }), { isPreview = true })
			c:setActive(true, frame(h, 1.4, true))
			for _, t in { 1.4, 0.2, 1.9, 0.05, 0.9 } do
				step(h, c, t, nil, true)
			end
			c:apply("amplitude", 3)
			step(h, c, 0.7)
			c:apply("amplitude", 10)
			step(h, c, 0.5)
			expectVector(offsetVector(), direct, "scrubbed")
		end)

		T.it("falls off with the distance between camera and component: 1 → linear → 0", function()
			local t0 = 0.4
			local function at(d: number, props: { [string]: any }?, options: MeasureOptions?): { number }
				local o: MeasureOptions = options or {}
				o.world = CFrame.new(home.Position + Vector3.new(0, 0, -d))
				return measure(merge(BIG, props or {}), t0, o)
			end
			local full = at(0)
			expect(rotationSize(full)).toBeGreaterThan(0.01)
			for _, case in { { 10, 1 }, { 20, 1 }, { 70, 0.5 }, { 95, 0.25 }, { 120, 0 }, { 500, 0 } } do
				expectVector(at(case[1]), scaled(full, case[2]), "d = " .. case[1])
			end
			-- outerRadius <= innerRadius: hard edge at innerRadius
			local hard = { innerRadius = 50, outerRadius = 10 }
			expectVector(at(49, hard), full, "hard edge inside")
			expectVector(at(51, hard), scaled(full, 0), "hard edge outside")
			-- the component's world position counts (sideways offsets too)
			local side = measure(BIG, t0, { world = CFrame.new(home.Position + Vector3.new(70, 0, 0)) })
			expectVector(side, scaled(full, 0.5), "sideways")
		end)

		T.it("transform.scale multiplies positionAmplitude and both radii, not the rotation", function()
			local t0 = 0.4
			local full = measure(BIG, t0)
			-- scale 2: radii 40 / 240 → d = 140 is half strength; positions double, so they come out unchanged
			local v = measure(BIG, t0, { scale = 2, world = CFrame.new(home.Position + Vector3.new(0, 0, -140)) })
			expectVector(v, scaled(full, 0.5, 1), "scale 2")
		end)

		T.it("weights the rotation per axis (pitch, yaw, roll) and keeps position separate", function()
			local t0 = 0.45
			local ones = measure(merge(BIG, { rotationWeights = { 1, 1, 1 } }), t0)
			local default = measure(BIG, t0)
			expectVector(default, { ones[1], ones[2] * 0.6, ones[3] * 0.3, ones[4], ones[5], ones[6] }, "default")
			local pitchOnly = measure(merge(BIG, { rotationWeights = { 1, 0, 0 } }), t0)
			expectVector(pitchOnly, { ones[1], 0, 0, ones[4], ones[5], ones[6] }, "pitch only")
			local noPosition = measure(merge(BIG, { positionAmplitude = 0 }), t0)
			expectVector(noPosition, { default[1], default[2], default[3], 0, 0, 0 }, "no position")
			local still = measure({ amplitude = 0, positionAmplitude = 0 }, t0)
			expectVector(still, { 0, 0, 0, 0, 0, 0 }, "still")
		end)

		T.it("noise is bounded by the amplitudes, smooth in time, repeatable and seed-dependent", function()
			local h = harness()
			local c = h:build("cameraShake", merge(BIG, { previewInStudio = true }), { isPreview = true, endTime = 10 })
			c:setActive(true, frame(h, 0.05))
			local bound = { 10 * RAD, 6 * RAD, 3 * RAD, 2, 2, 2 }
			local peak = { 0, 0, 0, 0, 0, 0 }
			local dt = 1 / 600
			-- |d/dt| <= amplitude · 2π · frequency · max rate factor (1.1)
			local maxStep = { 0, 0, 0, 0, 0, 0 }
			local previous: { number }? = nil
			for i = 0, 900 do
				local t = 0.05 + i * dt
				step(h, c, t)
				local v = offsetVector()
				for k = 1, 6 do
					expect(math.abs(v[k]) <= bound[k] + (if k <= 3 then ANGLE_EPS else STUD_EPS)).toBe(true)
					peak[k] = math.max(peak[k], math.abs(v[k]))
					if previous then
						maxStep[k] = math.max(maxStep[k], math.abs(v[k] - previous[k]))
					end
				end
				previous = v
			end
			for k = 1, 6 do
				-- uses a good part of its range …
				expect(peak[k]).toBeGreaterThan(bound[k] * 0.3)
				-- … without jumps
				local limit = bound[k] * TAU * 18 * 1.1 * dt + 2 * (if k <= 3 then ANGLE_EPS else STUD_EPS)
				expect(maxStep[k] <= limit).toBe(true)
			end
			c:destroy()
			-- repeatable per seed, different across seeds
			for _, t in { 0.1, 0.37, 0.9 } do
				expectVector(measure(BIG, t, { seed = 7 }), measure(BIG, t, { seed = 7 }), "seed 7")
			end
			local a, b = measure(BIG, 0.37, { seed = 7 }), measure(BIG, 0.37, { seed = 8 })
			local difference = 0
			for k = 1, 6 do
				difference += math.abs(a[k] - b[k])
			end
			expect(difference).toBeGreaterThan(0.05)
		end)

		T.it("amplitude channel scales the rotation only, clamps to 0..20 and ignores bad values", function()
			local t0 = 0.4
			local base = measure(BIG, t0)
			local h = harness()
			local c = h:build("cameraShake", merge(BIG, { previewInStudio = true }), { isPreview = true })
			c:setActive(true, frame(h, t0))
			c:apply("amplitude", 20)
			step(h, c, t0)
			expectVector(offsetVector(), scaled(base, 2, 1), "amplitude 20")
			c:apply("amplitude", 50)
			step(h, c, t0)
			expectVector(offsetVector(), scaled(base, 2, 1), "clamped to 20")
			c:apply("amplitude", 0 / 0)
			c:apply("amplitude", "loud")
			step(h, c, t0)
			expectVector(offsetVector(), scaled(base, 2, 1), "ignored")
			c:apply("amplitude", 0)
			step(h, c, t0)
			expectVector(offsetVector(), scaled(base, 0, 1), "amplitude 0")
			-- reset restores the rest value
			c:reset()
			expect(camera.CFrame).toBe(home)
			c:setActive(true, frame(h, t0))
			step(h, c, t0)
			expectVector(offsetVector(), base, "after reset")
		end)

		T.it("preview adopts an author's camera move as the new base instead of snapping back", function()
			local t0 = 0.4
			local expected = measure(BIG, t0)
			local h = harness()
			local c = h:build("cameraShake", merge(BIG, { previewInStudio = true }), { isPreview = true })
			c:setActive(true, frame(h, 0.3))
			step(h, c, 0.3)
			-- the author turns the camera (same position, so the falloff distance stays the same)
			camera.CFrame = CFrame.new(home.Position) * CFrame.Angles(0, 1, 0)
			local moved = camera.CFrame
			step(h, c, t0)
			expectVector(offsetVector(moved), expected, "relative to the moved camera")
			-- moved again right before deactivation: left where the author put it
			camera.CFrame = CFrame.new(home.Position) * CFrame.Angles(0, -1, 0)
			local last = camera.CFrame
			c:setActive(false, frame(h, 0.5))
			expect(camera.CFrame).toBe(last)
		end)

		T.it("preview restores the old camera and shakes the new one when CurrentCamera changes", function()
			local h = harness()
			local c = h:build("cameraShake", merge(BIG, { previewInStudio = true }), { isPreview = true })
			c:setActive(true, frame(h, 0.3))
			step(h, c, 0.3)
			expect(camera.CFrame ~= home).toBe(true)
			local other = Instance.new("Camera")
			other.CFrame = START
			local otherHome = other.CFrame
			useCamera(other)
			step(h, c, 0.35)
			expect(camera.CFrame).toBe(home)
			expect(other.CFrame ~= otherHome).toBe(true)
			c:destroy()
			expect(other.CFrame).toBe(otherHome)
			other:Destroy()
		end)

		T.it("tolerates a missing camera (no errors, nothing to shake)", function()
			useCamera(nil)
			local h = harness()
			local c = h:build("cameraShake", merge(BIG, { previewInStudio = true }), { isPreview = true })
			c:setActive(true, frame(h, 0.3))
			step(h, c, 0.3)
			c:setActive(false, frame(h, 0.4))
			c:destroy()
			expect(camera.CFrame).toBe(home)
		end)

		T.itIf(isLune, "a client binds undo/apply around Enum.RenderPriority.Camera only while active", function()
			asClient()
			local h = harness()
			local c = h:build("cameraShake", BIG)
			expect(#fakes.renderLog).toBe(0) -- nothing at build time
			c:setActive(true, frame(h, 0.1))
			local list = bindings()
			expect(#list).toBe(2)
			expect(CAMERA_PRIORITY).toBe(200)
			expect(list[1].priority).toBe(CAMERA_PRIORITY - 1)
			expect(list[2].priority).toBe(CAMERA_PRIORITY + 1)
			expect(string.sub(list[1].name, 1, 19)).toBe("AstraVFX_ShakeUndo_")
			expect(string.sub(list[2].name, 1, 15)).toBe("AstraVFX_Shake_")
			c:setActive(true, frame(h, 0.1)) -- already active: no second bind
			expect(#fakes.renderLog).toBe(2)
			step(h, c, 0.2)
			expect(camera.CFrame ~= home).toBe(true)
			c:setActive(false, frame(h, 0.3))
			expect(fakes:renderBindingCount()).toBe(0)
			expect(camera.CFrame).toBe(home)
			local unbound = {}
			for _, entry in fakes.renderLog do
				if entry.action == "unbind" then
					unbound[entry.name] = true
				end
			end
			expect(unbound).toEqual({ [list[1].name] = true, [list[2].name] = true })
			-- reactivation binds fresh names; release unbinds and blocks activation until reset
			c:setActive(true, frame(h, 0.4))
			expect(fakes:renderBindingCount()).toBe(2)
			expect(fakes.renderBindings[list[2].name]).toBeNil()
			c:release()
			expect(fakes:renderBindingCount()).toBe(0)
			c:setActive(true, frame(h, 0.5))
			expect(fakes:renderBindingCount()).toBe(0)
			c:reset()
			c:setActive(true, frame(h, 0.5))
			expect(fakes:renderBindingCount()).toBe(2)
			c:reset()
			expect(fakes:renderBindingCount()).toBe(0)
			c:setActive(true, frame(h, 0.5))
			step(h, c, 0.5)
			c:destroy()
			expect(fakes:renderBindingCount()).toBe(0)
			expect(camera.CFrame).toBe(home)
			c:setActive(true, frame(h, 0.6)) -- after destroy: nothing
			c:destroy()
			expect(fakes:renderBindingCount()).toBe(0)
		end)

		T.itIf(isLune, "a client offsets whatever the camera scripts computed, every render step", function()
			-- references first (measure() steps the render bindings too)
			local expected30, expected31 = measure(BIG, 0.3), measure(BIG, 0.31)
			asClient()
			local scripted = CFrame.new(home.Position) * CFrame.Angles(0.3, -0.5, 0)
			local h = harness()
			local c = h:build("cameraShake", BIG)
			-- stand-in for the default camera scripts (Enum.RenderPriority.Camera): recompute the CFrame
			local runService: any = Env.getService("RunService")
			runService:BindToRenderStep("TestCameraScript", CAMERA_PRIORITY, function()
				camera.CFrame = scripted
			end)
			c:setActive(true, frame(h, 0.3))
			step(h, c, 0.3)
			local base = (function()
				local probe = Instance.new("Camera")
				probe.CFrame = scripted
				local stored = probe.CFrame
				probe:Destroy()
				return stored
			end)()
			-- the measured offset only depends on t and distance, so compare against a preview measurement
			expectVector(offsetVector(base), expected30, "t = 0.3")
			step(h, c, 0.31)
			expectVector(offsetVector(base), expected31, "t = 0.31")
			c:destroy()
			runService:UnbindFromRenderStep("TestCameraScript")
		end)

		T.itIf(isLune, "a client never accumulates offsets on a camera nobody updates (Scriptable)", function()
			local final = 0
			for _ = 1, 90 do
				final += 1 / 60
			end
			local expected = measure(BIG, final)
			asClient()
			local h = harness()
			local c = h:build("cameraShake", BIG)
			c:setActive(true, frame(h, 0))
			local t = 0
			for _ = 1, 90 do
				t += 1 / 60
				step(h, c, t)
			end
			expectVector(offsetVector(), expected, "after 90 frames")
			c:setActive(false, frame(h, t))
			expect(camera.CFrame).toBe(home)
		end)

		T.itIf(isLune, "a client does not drift a camera script that reads back Camera.CFrame.LookVector", function()
			asClient()
			local focus = Vector3.new(0, 2, 0)
			local zoom = 15
			-- PlayerModule-like camera: the next look direction comes from the current Camera.CFrame
			local runService: any = Env.getService("RunService")
			runService:BindToRenderStep("TestFollowCamera", CAMERA_PRIORITY, function()
				local look = camera.CFrame.LookVector
				camera.CFrame = CFrame.lookAt(focus - look * zoom, focus)
			end)
			camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, 4, 14), focus)
			fakes:renderStep(1 / 60)
			local before = camera.CFrame.LookVector
			local h = harness()
			local c = h:build("cameraShake", { amplitude = 10, positionAmplitude = 0, innerRadius = 100 })
			c:setActive(true, frame(h, 0))
			local moved = 0
			for i = 1, 120 do
				step(h, c, i / 60, CFrame.new(focus))
				moved = math.max(moved, (camera.CFrame.LookVector - before).Magnitude)
			end
			expect(moved).toBeGreaterThan(0.05) -- it did shake
			c:destroy()
			fakes:renderStep(1 / 60)
			expect((camera.CFrame.LookVector - before).Magnitude).toBeLessThan(1e-3)
			runService:UnbindFromRenderStep("TestFollowCamera")
		end)

		T.itIf(isLune, "concurrent client shakes share one binding pair and compose their offsets", function()
			asClient()
			local t0 = 0.4
			local a = measure(BIG, t0, { seed = 1 })
			local b = measure(BIG, t0, { seed = 2 })
			local h = harness()
			local ca = h:build("cameraShake", BIG, { seed = 1, id = "shakeA" })
			local cb = h:build("cameraShake", BIG, { seed = 2, id = "shakeB" })
			ca:setActive(true, frame(h, t0))
			cb:setActive(true, frame(h, t0))
			expect(fakes:renderBindingCount()).toBe(2)
			local f = frame(h, t0)
			for _, c in { ca, cb } do
				c:setTransform(near(), near(), f)
				c:update(t0, f)
			end
			fakes:renderStep(1 / 60)
			-- camera = home × offsetA × offsetB
			local function cf(v: { number }): CFrame
				return CFrame.new(v[4], v[5], v[6]) * CFrame.fromOrientation(v[1], v[2], v[3])
			end
			local composed = cf(a) * cf(b)
			local rx, ry, rz = composed:ToOrientation()
			local p = composed.Position
			expectVector(offsetVector(), { rx, ry, rz, p.X, p.Y, p.Z }, "composed")
			-- a second frame at the same time shows the same state (no accumulation between shakes)
			fakes:renderStep(1 / 60)
			expectVector(offsetVector(), { rx, ry, rz, p.X, p.Y, p.Z }, "second frame")
			ca:setActive(false, frame(h, 0.5))
			expect(fakes:renderBindingCount()).toBe(2) -- still needed by B
			fakes:renderStep(1 / 60)
			expectVector(offsetVector(), b, "B alone")
			cb:destroy()
			expect(fakes:renderBindingCount()).toBe(0)
			expect(camera.CFrame).toBe(home)
		end)

		T.itIf(isLune, "a client without a camera binds harmlessly and writes nothing", function()
			asClient()
			useCamera(nil)
			local h = harness()
			local c = h:build("cameraShake", BIG)
			c:setActive(true, frame(h, 0.2))
			step(h, c, 0.2)
			step(h, c, 0.3)
			c:destroy()
			expect(fakes:renderBindingCount()).toBe(0)
			expect(camera.CFrame).toBe(home)
		end)

		T.it("estimates no instances and two Camera.CFrame writes per frame, with notes", function()
			local h = harness()
			local d = Components.get("cameraShake")
			local _, component = h:build("cameraShake")
			local cost = d.estimateCost(component, HIGH)
			expect(cost.instances).toBe(0)
			expect(cost.parts + cost.attachments + cost.emitters + cost.lights).toBe(0)
			expect(cost.propertyUpdates).toBe(2)
			expect(cost.movingParts).toBe(0)
			expect(#cost.notes).toBe(1)
			expect(cost.notes[1]).toMatch("client only")
			local _, hard = h:build("cameraShake", { innerRadius = 50, outerRadius = 10 }, { id = "hard" })
			expect(#d.estimateCost(hard, HIGH).notes).toBe(2)
			local _, short = h:build("cameraShake", { attack = 0.3, decay = 0.3 }, { id = "short", endTime = 0.5 })
			local notes = d.estimateCost(short, HIGH).notes
			expect(notes[2]).toMatch("never reaches full strength")
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 3. screenFlash
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsCamera screenFlash", function()
		-- Values the effect should hold at envelope e (defaults: 0.35 / 0.8 / −0.6, tint white unless given).
		local function expectEffect(effect: any, e: number, tint: Color3?)
			local c = tint or Color3.new(1, 1, 1)
			expect(effect.Brightness).toBeCloseTo(0.35 * e, 1e-6)
			expect(effect.Contrast).toBeCloseTo(0.8 * e, 1e-6)
			expect(effect.Saturation).toBeCloseTo(-0.6 * e, 1e-6)
			expect(effect.TintColor).toBeCloseTo(
				Color3.new(1 + (c.R - 1) * e, 1 + (c.G - 1) * e, 1 + (c.B - 1) * e),
				1e-6
			)
		end

		T.it("is a no-op on a server: no ColorCorrectionEffect anywhere", function()
			local h = harness()
			local c, component = h:build("screenFlash")
			c:setActive(true, frame(h, 0.04))
			step(h, c, 0.04)
			expect(#c.instances).toBe(0)
			expect(#camera:GetChildren()).toBe(0)
			expect(#h:instancesOf(component.id)).toBe(0)
			expect(#h.container:GetChildren()).toBe(1)
		end)

		T.it("creates the effect under the camera only while active and removes it afterwards", function()
			asClient()
			local h = harness()
			local c, component = h:build("screenFlash")
			expect(#c.instances).toBe(0)
			step(h, c, 0.04) -- inactive
			expect(#camera:GetChildren()).toBe(0)
			c:setActive(true, frame(h, 0.04))
			local list = effectsUnder(camera)
			expect(#list).toBe(1)
			local effect = list[1]
			expect(effect.Name).toBe("AstraVFX_" .. component.name)
			expect(effect.Archivable).toBe(false)
			expect(effect.Enabled).toBe(true)
			expect(effect:GetAttribute("AstraComponent")).toBe(component.id)
			expect(c.instances).toEqual({ effect })
			expect(#h.container:GetChildren()).toBe(1) -- nothing in the container
			expectEffect(effect, 1)
			c:setActive(false, frame(h, 0.05))
			expect(#camera:GetChildren()).toBe(0)
			expect(effect.Parent).toBeNil()
			expect(#c.instances).toBe(0)
		end)

		T.it("follows attack → hold → decay as a pure function of local time", function()
			asClient()
			local h = harness()
			local c = h:build("screenFlash")
			c:setActive(true, frame(h, 0))
			expect(#effectsUnder(camera)).toBe(0) -- e(0) = 0 with attack > 0
			local cases = { { 0.01, 0.5 }, { 0.02, 1 }, { 0.05, 1 }, { 0.0699, 1 }, { 0.16, 0.5 }, { 0.205, 0.25 } }
			-- scrub in a scrambled order: every time shows its own envelope value
			for _, i in { 5, 2, 6, 1, 4, 3, 1, 6 } do
				local t, e = cases[i][1], cases[i][2]
				step(h, c, t, nil, i % 2 == 0)
				local list = effectsUnder(camera)
				expect(#list).toBe(1)
				expectEffect(list[1], e)
			end
			-- the envelope ends at attack + hold + decay = 0.25: no idle effect remains
			step(h, c, 0.25)
			expect(#effectsUnder(camera)).toBe(0)
			expect(#c.instances).toBe(0)
			step(h, c, 0.6)
			expect(#effectsUnder(camera)).toBe(0)
			-- scrubbing back re-creates it
			step(h, c, 0.04)
			expect(#effectsUnder(camera)).toBe(1)
			expectEffect(effectsUnder(camera)[1], 1)
		end)

		T.it("peaks immediately with attack = 0 and uses the configured look", function()
			asClient()
			local h = harness()
			local tint = Color3.fromRGB(255, 32, 64)
			local c = h:build(
				"screenFlash",
				{ attack = 0, brightness = 1.5, contrast = 2.5, saturation = -1, tint = "#FF2040" }
			)
			c:setActive(true, frame(h, 0))
			local effect = effectsUnder(camera)[1]
			expect(effect).never.toBeNil()
			expect(effect.Brightness).toBeCloseTo(1.5, 1e-6)
			expect(effect.Contrast).toBeCloseTo(2.5, 1e-6)
			expect(effect.Saturation).toBeCloseTo(-1, 1e-6)
			expect(effect.TintColor).toBeCloseTo(tint, 1e-6)
		end)

		T.it("writes each property only when its value changes", function()
			asClient()
			local green = Color3.new(0, 1, 0)
			local h = harness()
			local c = h:build("screenFlash", { tint = "#00FF00" })
			c:setActive(true, frame(h, 0.03))
			step(h, c, 0.03)
			local effect = effectsUnder(camera)[1]
			-- sentinels: a redundant write during the hold would overwrite them
			effect.Brightness = 0.9
			effect.Contrast = 0.9
			effect.Saturation = 0.9
			effect.TintColor = Color3.new(0.1, 0.2, 0.3)
			effect.Enabled = false
			step(h, c, 0.05)
			c:apply("tint", green) -- rest value
			step(h, c, 0.06)
			expect(effect.Brightness).toBeCloseTo(0.9, 1e-6)
			expect(effect.Contrast).toBeCloseTo(0.9, 1e-6)
			expect(effect.Saturation).toBeCloseTo(0.9, 1e-6)
			expect(effect.TintColor).toBeCloseTo(Color3.new(0.1, 0.2, 0.3), 1e-6)
			expect(effect.Enabled).toBe(false)
			-- the decay changes all four
			step(h, c, 0.16)
			expectEffect(effect, 0.5, green)
		end)

		T.it("tint channel replaces the tint at the peak; bad values are ignored; reset restores", function()
			asClient()
			local h = harness()
			local c = h:build("screenFlash", { tint = "#00FF00" })
			c:setActive(true, frame(h, 0.04))
			local effect = effectsUnder(camera)[1]
			expect(effect.TintColor).toBeCloseTo(Color3.new(0, 1, 0), 1e-6)
			c:apply("tint", Color3.new(1, 0, 0))
			expect(effect.TintColor).toBeCloseTo(Color3.new(1, 0, 0), 1e-6)
			c:apply("tint", 12345)
			c:apply("tint", "red")
			step(h, c, 0.04)
			expect(effect.TintColor).toBeCloseTo(Color3.new(1, 0, 0), 1e-6)
			step(h, c, 0.16) -- half-way back to white
			expect(effect.TintColor).toBeCloseTo(Color3.new(1, 0.5, 0.5), 1e-6)
			c:reset()
			expect(#effectsUnder(camera)).toBe(0)
			c:setActive(true, frame(h, 0.04))
			expect(effectsUnder(camera)[1].TintColor).toBeCloseTo(Color3.new(0, 1, 0), 1e-6)
		end)

		T.it("release removes the effect until reset; destroy removes it for good and is idempotent", function()
			asClient()
			local h = harness()
			local c = h:build("screenFlash")
			c:setActive(true, frame(h, 0.04))
			expect(#effectsUnder(camera)).toBe(1)
			c:release()
			expect(#effectsUnder(camera)).toBe(0)
			step(h, c, 0.05)
			c:setActive(true, frame(h, 0.05))
			expect(#effectsUnder(camera)).toBe(0)
			c:reset()
			c:setActive(true, frame(h, 0.05))
			expect(#effectsUnder(camera)).toBe(1)
			c:destroy()
			expect(#effectsUnder(camera)).toBe(0)
			expect(#c.instances).toBe(0)
			c:setActive(true, frame(h, 0.05))
			step(h, c, 0.05)
			expect(#effectsUnder(camera)).toBe(0)
			c:destroy()
		end)

		T.it("shows in the editor preview by default (previewInStudio) and not when it is off", function()
			local h = harness()
			local c = h:build("screenFlash", nil, { isPreview = true })
			c:setActive(true, frame(h, 0.04))
			expect(#effectsUnder(camera)).toBe(1)
			expect(effectsUnder(camera)[1].Archivable).toBe(false)
			c:setActive(false, frame(h, 0.05))
			expect(#effectsUnder(camera)).toBe(0)
			local off = h:build("screenFlash", { previewInStudio = false }, { isPreview = true, id = "off" })
			off:setActive(true, frame(h, 0.04))
			step(h, off, 0.04)
			expect(#effectsUnder(camera)).toBe(0)
			local viewport = h:build("screenFlash", nil, { isPreview = true, viewport = true, id = "vp" })
			viewport:setActive(true, frame(h, 0.04))
			expect(#effectsUnder(camera)).toBe(0)
		end)

		T.it("moves to the new camera when CurrentCamera changes and survives a destroyed effect", function()
			asClient()
			local h = harness()
			local c = h:build("screenFlash")
			c:setActive(true, frame(h, 0.03))
			local first = effectsUnder(camera)[1]
			local other = Instance.new("Camera")
			useCamera(other)
			step(h, c, 0.04)
			expect(#effectsUnder(camera)).toBe(0)
			expect(first.Parent).toBeNil()
			local second = effectsUnder(other)[1]
			expect(second).never.toBeNil()
			expectEffect(second, 1)
			expect(c.instances).toEqual({ second })
			-- something else destroys it (e.g. together with the camera): recreated on the next frame
			second:Destroy()
			step(h, c, 0.05)
			local third = effectsUnder(other)[1]
			expect(third).never.toBeNil()
			expect(c.instances).toEqual({ third })
			useCamera(nil)
			step(h, c, 0.05)
			expect(#effectsUnder(other)).toBe(0)
			expect(#c.instances).toBe(0)
			other:Destroy()
		end)

		T.it("never touches Lighting", function()
			asClient()
			local lighting = Env.getService("Lighting")
			local before = #lighting:GetChildren()
			local h = harness()
			local c = h:build("screenFlash", { attack = 0 })
			c:setActive(true, frame(h, 0))
			step(h, c, 0.02)
			expect(#lighting:GetChildren()).toBe(before)
		end)

		T.it("estimates one post-effect instance and four property writes per frame", function()
			local h = harness()
			local d = Components.get("screenFlash")
			local _, component = h:build("screenFlash")
			local cost = d.estimateCost(component, HIGH)
			expect(cost.instances).toBe(1)
			expect(cost.parts + cost.attachments + cost.emitters + cost.lights + cost.beams).toBe(0)
			expect(cost.propertyUpdates).toBe(4)
			expect(cost.notes).toEqual({ "post effect: full-screen pass" })
			local _, short = h:build("screenFlash", { decay = 1 }, { id = "short", endTime = 0.5 })
			local notes = d.estimateCost(short, HIGH).notes
			expect(#notes).toBe(2)
			expect(notes[2]).toMatch("cut off")
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- 4. Builder integration (preview)
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsCamera with the Builder", function()
		T.it("preview builds tag the post effect as preview-only and clean the camera up on destroy", function()
			local components: { any } = {
				{ id = "flash", name = "Flash", type = "screenFlash", properties = { attack = 0 } },
				{
					id = "shake",
					name = "Shake",
					type = "cameraShake",
					properties = { amplitude = 5, previewInStudio = true, innerRadius = 100 } :: any,
				},
			}
			local def: any = {
				schemaVersion = 1,
				id = "cameraFx",
				name = "Camera FX",
				duration = 1,
				components = components,
			}
			local compiled = Compiler.compile(def, { quality = "High" })
			local built = Builder.build(compiled, { isPreview = true })
			-- nothing in the container besides the root, nothing under the camera yet
			expect(#built.container:GetDescendants()).toBe(1)
			expect(#camera:GetChildren()).toBe(0)
			local f = {
				time = 0.3,
				dt = 1 / 60,
				seeking = false,
				rootCFrame = CFrame.new(),
				moveParts = {},
				moveCFrames = {},
				fire = function(_name: string) end,
			}
			for _, id in built.order do
				local controller = built.controllers[id]
				controller:setActive(true, f)
				controller:setTransform(CFrame.new(), CFrame.new(), f)
				if controller.update then
					controller:update(0.03, f)
				end
			end
			local effect = effectsUnder(camera)[1]
			expect(effect).never.toBeNil()
			expect(effect.Archivable).toBe(false)
			expect(effect:GetAttribute(Constants.ATTR_PREVIEW)).toBe(true)
			expect(effect:GetAttribute(Constants.ATTR_COMPONENT)).toBe("flash")
			expect(camera.CFrame ~= home).toBe(true)
			built:destroy()
			expect(#camera:GetChildren()).toBe(0)
			expect(camera.CFrame).toBe(home)
		end)
	end)
end
