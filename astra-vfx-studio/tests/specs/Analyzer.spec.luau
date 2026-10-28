--!strict
--[[
	Authoring/Analyzer — heuristic performance analysis (docs/MODULE_CONTRACTS.md §20).

	Effects are constructed so that every expected number can be computed by hand (quality profile arithmetic:
	Low countScale 0.35 / sizeCompensation 1.12, Medium 0.65 / 1.05; Common.scaledCount rounds half up).
	Particle model: every particle lives lifetime.Max; continuous = ∫ rate over the emitting time inside
	[t − L, t]; bursts are alive on [t_emit, t_emit + L].
]]
return function(T: any, use: (string) -> any, _ctx: any)
	local Analyzer = use("Authoring.Analyzer")
	local Json = use("AstraVFX.Core.Json")
	local expect = T.expect

	local function effect(components: { any }, extra: { [string]: any }?): any
		local def: { [string]: any } = {
			schemaVersion = 1,
			id = "perf",
			name = "Perf",
			duration = 3,
			components = components,
		}
		local more: { [string]: any } = extra or {}
		for k, v in more do
			def[k] = v
		end
		return def
	end

	local function component(
		id: string,
		typeName: string,
		properties: { [string]: any }?,
		fields: { [string]: any }?
	): any
		local c: { [string]: any } = { id = id, name = id, type = typeName, properties = properties or {} }
		local more: { [string]: any } = fields or {}
		for k, v in more do
			c[k] = v
		end
		return c
	end

	-- rate 100/s, lifetime 2 s, active 0–3 s (the reference case of the task description).
	local function sparks(fields: { [string]: any }?, properties: { [string]: any }?): any
		local props: { [string]: any } = { rate = 100, lifetime = 2 }
		local moreProps: { [string]: any } = properties or {}
		for k, v in moreProps do
			props[k] = v
		end
		local f: { [string]: any } = { startTime = 0, duration = 3 }
		local moreFields: { [string]: any } = fields or {}
		for k, v in moreFields do
			f[k] = v
		end
		return component("sparks", "particles", props, f)
	end

	-- Value of a series at the sample whose time is closest to t.
	local function at(report: any, key: string, t: number): number
		local best, value = math.huge, 0
		for i, time in report.series.time do
			local d = math.abs(time - t)
			if d < best then
				best, value = d, report.series[key][i]
			end
		end
		return value
	end

	local function metric(report: any, key: string): any
		for _, m in report.metrics do
			if m.key == key then
				return m
			end
		end
		error("no metric " .. key)
	end

	local function diagnostics(report: any, code: string): { any }
		local out = {}
		for _, d in report.diagnostics do
			if d.code == code then
				table.insert(out, d)
			end
		end
		return out
	end

	local function contains(text: string?, part: string): boolean
		return type(text) == "string" and string.find(text, part, 1, true) ~= nil
	end

	T.describe("Analyzer.analyze — live particles", function()
		T.it("rate 100, lifetime 2, active 0–3 s peaks at 200 from t = 2 and decays over the lifetime", function()
			local report = Analyzer.analyze(effect({ sparks() }), { quality = "High", sampleRate = 30 })
			expect(report.peaks.liveParticles.value).toBe(200)
			expect(report.peaks.liveParticles.time).toBeCloseTo(2, 1e-9)
			expect(at(report, "liveParticles", 0)).toBe(0)
			expect(at(report, "liveParticles", 1)).toBeCloseTo(100, 1e-6)
			expect(at(report, "liveParticles", 2.5)).toBeCloseTo(200, 1e-6)
			expect(at(report, "liveParticles", 3)).toBeCloseTo(200, 1e-6)
			expect(at(report, "liveParticles", 4)).toBeCloseTo(100, 1e-6) -- linear decay over lifetime.Max
			expect(at(report, "liveParticles", 5)).toBe(0)
			-- window = duration + maxTail, sampled at 30 Hz (all breakpoints lie on the grid here)
			expect(report.maxTail).toBe(2)
			expect(report.window).toBe(5)
			expect(report.sampleCount).toBe(151)
			expect(report.series.time[1]).toBe(0)
			expect(report.series.time[#report.series.time]).toBe(5)
		end)

		T.it("uses lifetime.Max of a range and continuous emission shorter than the lifetime", function()
			local report =
				Analyzer.analyze(effect({ sparks({ duration = 1 }, { lifetime = { 0.5, 2 } }) }), { quality = "High" })
			expect(report.peaks.liveParticles.value).toBe(100) -- rate × min(span, L) = 100 × 1
			expect(report.peaks.liveParticles.time).toBeCloseTo(1, 1e-9)
			-- emitted in [0, 1): all still alive at t = 2 (window [0, 2]), half at t = 2.5 (window [0.5, 2.5])
			expect(at(report, "liveParticles", 2)).toBeCloseTo(100, 1e-6)
			expect(at(report, "liveParticles", 2.5)).toBeCloseTo(50, 1e-6)
			expect(at(report, "liveParticles", 3)).toBe(0)
		end)

		T.it("adds an overlapping emit burst (50 at t = 1 → 250)", function()
			local fx = effect({ sparks({ events = { { id = "boom", time = 1, action = "emit", count = 50 } } }) })
			local report = Analyzer.analyze(fx, { quality = "High", sampleRate = 30 })
			expect(report.peaks.liveParticles.value).toBe(250)
			expect(report.peaks.liveParticles.time).toBeCloseTo(2, 1e-9)
			expect(at(report, "liveParticles", 1)).toBeCloseTo(150, 1e-6)
			expect(at(report, "liveParticles", 3)).toBeCloseTo(250, 1e-6) -- burst alive on [1, 3]
			expect(at(report, "liveParticles", 3.5)).toBeCloseTo(150, 1e-6)
			expect(report.components[1].peakParticles).toBe(250)
		end)

		T.it("emits the burst property on activation and uses the default emit count", function()
			local fx = effect({
				component(
					"pop",
					"particles",
					{ rate = 0, burst = 40, lifetime = 1 },
					{ startTime = 0.5, duration = 1 }
				),
				-- a count-less emit uses ParticleEmitter:Emit()'s default of 16 particles
				component("puff", "particles", { rate = 0, lifetime = 1 }, {
					startTime = 0,
					duration = 3,
					events = { { id = "e", time = 2, action = "emit" } },
				}),
			})
			local report = Analyzer.analyze(fx)
			expect(at(report, "liveParticles", 0.4)).toBe(0)
			expect(at(report, "liveParticles", 0.5)).toBe(40)
			expect(at(report, "liveParticles", 1.5)).toBe(40) -- closed interval [0.5, 1.5]
			expect(at(report, "liveParticles", 1.6)).toBe(0)
			expect(at(report, "liveParticles", 2.5)).toBe(16)
			expect(report.peaks.liveParticles.value).toBe(40)
		end)

		T.it("catches short bursts between grid samples through breakpoints", function()
			local fx = effect({
				component("blip", "particles", { rate = 0, lifetime = 0.01 }, {
					events = { { id = "e", time = 0.51, action = "emit", count = 30 } },
				}),
			})
			local report = Analyzer.analyze(fx, { sampleRate = 30 })
			expect(report.peaks.liveParticles.value).toBe(30)
			expect(report.peaks.liveParticles.time).toBeCloseTo(0.51, 1e-9)
		end)

		T.it("clear removes live particles and restarts the window", function()
			local fx = effect({ sparks({ events = { { id = "wipe", time = 1.5, action = "clear" } } }) })
			local report = Analyzer.analyze(fx)
			expect(at(report, "liveParticles", 1.5)).toBe(0)
			expect(at(report, "liveParticles", 2)).toBeCloseTo(50, 1e-6)
			expect(report.peaks.liveParticles.value).toBe(150) -- emitted in [1.5, 3)
			expect(report.peaks.liveParticles.time).toBeCloseTo(3, 1e-9)
		end)

		T.it("disable / enable events pause continuous emission", function()
			local fx = effect({
				sparks({
					duration = 4,
					events = {
						{ id = "off", time = 1, action = "disable" },
						{ id = "on", time = 3, action = "enable" },
					},
				}, { lifetime = 1 }),
			}, { duration = 4 })
			local report = Analyzer.analyze(fx)
			expect(at(report, "liveParticles", 1)).toBeCloseTo(100, 1e-6)
			expect(at(report, "liveParticles", 2)).toBe(0)
			expect(at(report, "liveParticles", 3.5)).toBeCloseTo(50, 1e-6)
			-- the emitter keeps its per-frame work while disabled, but it is not counted as an active emitter
			expect(at(report, "emitters", 2.5)).toBe(0)
			expect(at(report, "emitters", 3.5)).toBe(1)
			expect(at(report, "activeComponents", 2.5)).toBe(1)
		end)

		T.it("integrates an animated rate track", function()
			local fx = effect({
				sparks({
					duration = 2,
					tracks = {
						{
							id = "ramp",
							channel = "rate",
							keyframes = { { time = 0, value = 0 }, { time = 2, value = 100 } },
						},
					},
				}, { lifetime = 1 }),
			}, { duration = 2 })
			local report = Analyzer.analyze(fx)
			-- rate(τ) = 50 τ: ∫_1^2 50 τ dτ = 75
			expect(at(report, "liveParticles", 2)).toBeCloseTo(75, 0.01)
			expect(at(report, "liveParticles", 1)).toBeCloseTo(25, 0.01)
		end)

		T.it("counts graph Emit actions from the compiled schedule (quality-scaled by the graph runner)", function()
			local def = effect({ component("puff", "particles", { rate = 0, lifetime = 1 }) }, {
				graph = {
					nodes = {
						{ id = "play", type = "OnPlay" },
						{ id = "wait", type = "Delay", params = { seconds = 1 } },
						{ id = "emit", type = "Emit", params = { target = "puff", count = 60 } },
					},
					links = {
						{ from = "play.out", to = "wait.in" },
						{ from = "wait.out", to = "emit.in" },
					},
				},
			})
			local high = Analyzer.analyze(def)
			expect(at(high, "liveParticles", 0.9)).toBe(0)
			expect(at(high, "liveParticles", 1.5)).toBe(60)
			expect(high.peaks.liveParticles.time).toBeCloseTo(1, 1e-9)
			local low = Analyzer.analyze(def, { quality = "Low" })
			expect(low.peaks.liveParticles.value).toBe(21) -- round(60 × 0.35)
		end)

		T.it("handles the graph action limit (10000 emits) and passes compiler warnings through", function()
			local def = effect({ component("p", "particles", { rate = 0, lifetime = 2 }) }, {
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
			local report = Analyzer.analyze(def)
			-- 200 emits of 1 per outer iteration; the 10000-action limit stops after 50 iterations (0 … 0.49 s),
			-- all alive until t + 2
			expect(report.peaks.liveParticles.value).toBe(10000)
			expect(report.peaks.liveParticles.time).toBeCloseTo(0.49, 1e-9)
			expect(at(report, "liveParticles", 0.25)).toBe(26 * 200)
			expect(#diagnostics(report, "graph.action_limit")).toBe(1)
		end)

		T.it("analyses looping effects in steady state (earlier cycles' particles still alive)", function()
			local fx = effect({ sparks({ duration = 1 }) }, { duration = 1, loop = true })
			local report = Analyzer.analyze(fx)
			expect(report.loop).toBe(true)
			expect(report.window).toBe(1)
			-- rate × lifetime once the loop runs: 100 × 2 at every time of the cycle
			expect(report.peaks.liveParticles.value).toBeCloseTo(200, 1e-6)
			expect(at(report, "liveParticles", 0)).toBeCloseTo(200, 1e-6)
			expect(at(report, "liveParticles", 0.5)).toBeCloseTo(200, 1e-6)
			local once = Analyzer.analyze(effect({ sparks({ duration = 1 }) }, { duration = 1 }))
			expect(once.peaks.liveParticles.value).toBe(100)
		end)
	end)

	T.describe("Analyzer.analyze — quality scaling", function()
		local fx = effect({ sparks({ events = { { id = "boom", time = 1, action = "emit", count = 50 } } }) })

		T.it("scales rates and bursts by countScale", function()
			-- Low: rate 35 × 2 + round(50 × 0.35) = 70 + 18; Medium: 65 × 2 + round(32.5) = 130 + 33
			expect(Analyzer.analyze(fx, { quality = "Low" }).peaks.liveParticles.value).toBeCloseTo(88, 1e-6)
			expect(Analyzer.analyze(fx, { quality = "Medium" }).peaks.liveParticles.value).toBeCloseTo(163, 1e-6)
		end)

		T.it("compareQualities returns Low < Medium < High", function()
			local reports = Analyzer.compareQualities(fx)
			expect(reports.Low.quality).toBe("Low")
			expect(reports.Medium.quality).toBe("Medium")
			expect(reports.High.quality).toBe("High")
			expect(reports.Low.peaks.liveParticles.value).toBeLessThan(reports.Medium.peaks.liveParticles.value)
			expect(reports.Medium.peaks.liveParticles.value).toBeLessThan(reports.High.peaks.liveParticles.value)
			-- options other than quality are kept
			local coarse = Analyzer.compareQualities(fx, { sampleRate = 10, quality = "High" })
			expect(coarse.Low.sampleRate).toBe(10)
			expect(coarse.Low.quality).toBe("Low")
		end)

		T.it("drops minQuality components and scales counts of procedural parts", function()
			local def = effect({
				component("rocks", "debris", { count = 20 }),
				component("glow", "light", nil, { minQuality = "High" }),
			})
			local reports = Analyzer.compareQualities(def)
			expect(reports.High.totals.components).toBe(2)
			expect(reports.High.totals.omitted).toBe(0)
			expect(reports.Low.totals.components).toBe(1)
			expect(reports.Low.totals.omitted).toBe(1)
			expect(reports.High.totals.parts).toBe(20 + 1) -- + Root part
			expect(reports.Low.totals.parts).toBe(7 + 1) -- round(20 × 0.35)
			expect(reports.Low.totals.instances).toBeLessThan(reports.High.totals.instances)
			expect(reports.Low.peaks.movingParts.value).toBe(7)
		end)

		T.it("weights particle overdraw with sizeCompensation and the effect scale", function()
			expect(Analyzer.analyze(effect({ sparks() })).peaks.overdrawWeight.value).toBeCloseTo(200, 1e-6)
			-- Low: (1 × 1.12)² × 70 particles
			expect(Analyzer.analyze(effect({ sparks() }), { quality = "Low" }).peaks.overdrawWeight.value).toBeCloseTo(
				1.12 * 1.12 * 70,
				1e-6
			)
			-- scale 2: sprite size 2, rate unchanged
			local scaled = Analyzer.analyze(effect({ sparks() }), { scale = 2 })
			expect(scaled.scale).toBe(2)
			expect(scaled.peaks.overdrawWeight.value).toBeCloseTo(800, 1e-6)
			expect(scaled.peaks.liveParticles.value).toBe(200)
		end)
	end)

	T.describe("Analyzer.analyze — concurrency and per-frame work", function()
		T.it("counts concurrently active components, beams, lights and trails", function()
			local def = effect({
				component("b1", "beam", nil, { startTime = 0, duration = 1 }),
				component("b2", "beam", nil, { startTime = 0.5, duration = 1 }),
				component("lamp", "light", nil, { startTime = 0, duration = 2 }),
				component("pivot", "group", { spin = { 0, 180, 0 } }),
				component("streak", "trail", { lifetime = 0.5 }, { parent = "pivot", startTime = 1, duration = 1 }),
			})
			local report = Analyzer.analyze(def)
			expect(report.peaks.beams.value).toBe(2)
			expect(report.peaks.beams.time).toBeCloseTo(0.5, 1e-9)
			expect(report.peaks.lights.value).toBe(1)
			expect(report.peaks.trails.value).toBe(1)
			-- b1, b2, lamp, pivot at 0.5 s
			expect(report.peaks.activeComponents.value).toBe(4)
			expect(report.peaks.activeComponents.time).toBeCloseTo(0.5, 1e-9)
			-- the trail fades for its lifetime after the span: visible until 2.5 s
			expect(at(report, "trails", 2.25)).toBe(1)
			expect(at(report, "trails", 2.6)).toBe(0)
			expect(at(report, "activeComponents", 2.25)).toBe(1) -- only the group (span 0–3)
		end)

		T.it("counts moving parts and property writes, including motion inherited from a spinning parent", function()
			local def = effect({
				component("pivot", "group", { spin = { 0, 90, 0 } }),
				component("orbit", "part", nil, { parent = "pivot", startTime = 0, duration = 1 }),
				component("halo", "ring", { segments = 24 }, { parent = "pivot", startTime = 0.5, duration = 1 }),
				component("fade", "part", nil, {
					startTime = 2,
					duration = 1,
					tracks = {
						{
							id = "t",
							channel = "transparency",
							keyframes = { { time = 0, value = 0 }, { time = 1, value = 1 } },
						},
						{
							id = "c",
							channel = "color",
							keyframes = { { time = 0, value = "#FFFFFF" }, { time = 1, value = "#FF0000" } },
						} :: any,
					},
				}),
			})
			local report = Analyzer.analyze(def)
			expect(report.peaks.movingParts.value).toBe(25) -- orbit 1 + halo 24 at 0.5 s
			expect(report.peaks.movingParts.time).toBeCloseTo(0.5, 1e-9)
			expect(at(report, "propertyUpdates", 2.5)).toBe(2) -- transparency + color
			expect(at(report, "movingParts", 2.5)).toBe(0)
			local byId: { [string]: any } = {}
			for _, c in report.components do
				byId[c.id] = c
			end
			expect(byId.orbit.inheritedMotion).toBe(true)
			expect(byId.orbit.cost.movingParts).toBe(1)
			expect(byId.halo.cost.movingParts).toBe(24)
			expect(byId.fade.inheritedMotion).toBe(false)
			expect(byId.fade.animated).toBe(true)
			expect(byId.pivot.animated).toBe(true) -- spin
			expect(byId.orbit.animated).toBe(false)
			expect(report.totals.animated).toBe(2)
			expect(report.totals.procedural).toBe(1) -- ring
		end)

		T.it("switches a type without enable/disable events off on 'disable' (as the Player does)", function()
			local def = effect({
				component("block", "part", nil, {
					tracks = {
						{
							id = "p",
							channel = "position",
							keyframes = { { time = 0, value = { 0, 0, 0 } }, { time = 3, value = { 0, 5, 0 } } },
						},
					},
					events = { { id = "off", time = 0.5, action = "disable" } },
				}),
			})
			local report = Analyzer.analyze(def)
			expect(at(report, "movingParts", 0.25)).toBe(1)
			expect(at(report, "movingParts", 1)).toBe(0)
			expect(at(report, "activeComponents", 1)).toBe(0)
		end)

		T.it("sums totals from the cost estimates plus the container and Root part", function()
			local def = effect({
				component("sparks", "particles"),
				component("lamp", "light", { shadows = true }),
				component("boom", "sound"),
				component("slash", "beam"),
				component("pivot", "group", { spin = { 0, 90, 0 } }),
				component("streak", "trail", nil, { parent = "pivot" }),
			})
			local high = Analyzer.analyze(def)
			local totals = high.totals
			-- particles 2, light 2, sound 2, beam 3, trail 3 + Folder + Root
			expect(totals.instances).toBe(2 + 2 + 2 + 3 + 3 + 2)
			expect(totals.parts).toBe(1)
			expect(totals.attachments).toBe(1 + 1 + 1 + 2 + 2)
			expect(totals.emitters).toBe(1)
			expect(totals.beams).toBe(1)
			expect(totals.trails).toBe(1)
			expect(totals.lights).toBe(1)
			expect(totals.shadowLights).toBe(1)
			expect(totals.sounds).toBe(1)
			expect(totals.components).toBe(6)
			expect(high.peaks.shadowLights.value).toBe(1)
			-- Low turns shadows off (quality.lightShadows = false)
			expect(Analyzer.analyze(def, { quality = "Low" }).totals.shadowLights).toBe(0)
		end)

		T.it("reports transparent layers and overdraw of translucent geometry while visible", function()
			local def = effect({
				component("glass", "part", { transparency = 0.5, size = { 2, 2, 2 } }, { startTime = 1, duration = 1 }),
			})
			local report = Analyzer.analyze(def)
			expect(report.peaks.transparentLayers.value).toBe(1)
			expect(report.peaks.overdrawWeight.value).toBe(4)
			expect(report.peaks.overdrawWeight.time).toBeCloseTo(1, 1e-9)
			expect(at(report, "overdrawWeight", 0.5)).toBe(0)
		end)
	end)

	T.describe("Analyzer.analyze — budgets and diagnostics", function()
		T.it("marks the report heuristic, carries the German notice and never reports frame rates", function()
			local report = Analyzer.analyze(effect({ sparks() }))
			expect(report.heuristic).toBe(true)
			expect(report.notice).toBe("Heuristische Schätzung – keine FPS-Messung")
			expect(Analyzer.NOTICE).toBe(report.notice)
			local found: { string } = {}
			local function walk(value: any, path: string)
				if type(value) == "table" then
					for k, v in value do
						local key = string.lower(tostring(k))
						if contains(key, "fps") or contains(key, "framerate") then
							table.insert(found, path .. "." .. tostring(k))
						end
						walk(v, path .. "." .. tostring(k))
					end
				elseif type(value) == "string" and path ~= ".notice" and contains(string.lower(value), "fps") then
					table.insert(found, path)
				end
			end
			walk(report, "")
			expect(found).toEqual({})
		end)

		T.it("is ok below 80 % of every budget", function()
			local report = Analyzer.analyze(effect({ sparks() }))
			expect(report.status).toBe("ok")
			local live = metric(report, "liveParticles")
			expect(live.value).toBe(200)
			expect(live.budget).toBe(2000)
			expect(live.ratio).toBeCloseTo(0.1, 1e-9)
			expect(live.status).toBe("ok")
			expect(live.label).toBe("Lebende Partikel")
			expect(#diagnostics(report, "perf.live_particles")).toBe(0)
			expect(#report.metrics).toBe(9)
			expect(metric(report, "instances").value).toBe(4)
			expect(metric(report, "instances").time).toBeNil()
		end)

		T.it("warns above 80 % and reports over budget with a hint at the main contributor", function()
			-- Low: 400/s × 0.35 = 140/s, lifetime 2 → 280 of 300 (93 %)
			local one = effect({ component("spray", "particles", { rate = 400, lifetime = 2 }) })
			local near = Analyzer.analyze(one, { quality = "Low" })
			expect(metric(near, "liveParticles").status).toBe("warn")
			expect(near.status).toBe("warn")
			local info = diagnostics(near, "perf.live_particles")
			expect(#info).toBe(1)
			expect(info[1].severity).toBe("info")
			expect(contains(info[1].message, "93%")).toBe(true)

			local two = effect({
				component("Sparks", "particles", { rate = 400, lifetime = 2 }, { name = "Sparks" }),
				component("dust", "particles", { rate = 100, lifetime = 2 }),
			})
			local over = Analyzer.analyze(two, { quality = "Low" })
			local live = metric(over, "liveParticles")
			expect(live.value).toBe(280 + 70)
			expect(live.status).toBe("over")
			expect(live.componentId).toBe("Sparks")
			expect(over.status).toBe("over")
			local warnings = diagnostics(over, "perf.live_particles")
			expect(#warnings).toBe(1)
			local d = warnings[1]
			expect(d.severity).toBe("warning")
			expect(d.componentId).toBe("Sparks")
			expect(d.path).toBe("components[1]")
			expect(contains(d.hint, "reduce rate or lifetime on 'Sparks'")).toBe(true)
			expect(contains(d.message, "350")).toBe(true)
			expect(contains(d.message, "300")).toBe(true)
			-- High has room for it
			expect(Analyzer.analyze(two, { quality = "High" }).status).toBe("ok")
		end)

		T.it("suggests a burst reduction when bursts dominate the peak", function()
			local def = effect({
				component("Pop", "particles", { rate = 0, burst = 400, lifetime = 1 }, { name = "Pop" }),
			})
			local report = Analyzer.analyze(def, { quality = "Low", budgets = { liveParticles = 100 } })
			local d = diagnostics(report, "perf.live_particles")[1]
			expect(contains(d.hint, "reduce burst/emit counts or lifetime on 'Pop'")).toBe(true)
		end)

		T.it("suggests minQuality for lights and shadows = false for shadow lights", function()
			local lights = effect({
				component("glow", "light", nil, { name = "Glow Light" }),
				component("rim", "light"),
			})
			local low = Analyzer.analyze(lights, { quality = "Low", budgets = { lights = 1 } })
			expect(metric(low, "lights").value).toBe(2)
			local d = diagnostics(low, "perf.lights")[1]
			expect(d.severity).toBe("warning")
			expect(contains(d.hint, "set minQuality = Medium for 'Glow Light'")).toBe(true)

			local shadows = effect({
				component("a", "light", { shadows = true }),
				component("b", "light", { shadows = true }),
				component("c", "light", { shadows = true }),
			})
			local high = Analyzer.analyze(shadows, { quality = "High" })
			expect(metric(high, "shadowLights").value).toBe(3)
			expect(metric(high, "shadowLights").status).toBe("over")
			local s = diagnostics(high, "perf.shadow_lights")[1]
			expect(contains(s.hint, "set shadows = false on 'a'")).toBe(true)
			-- a budget of 0 with nothing to count is ok, with ratio nil
			local low0 = Analyzer.analyze(shadows, { quality = "Low" })
			expect(metric(low0, "shadowLights").status).toBe("ok")
			expect(metric(low0, "shadowLights").ratio).toBeNil()
		end)

		T.it("checks instances and moving parts against the budget", function()
			local def = effect({
				component("rocks1", "debris", { count = 200 }, { name = "Rocks" }),
				component("rocks2", "debris", { count = 200 }),
				component("rocks3", "debris", { count = 200 }),
				component("rocks4", "debris", { count = 200 }),
			})
			local report = Analyzer.analyze(def)
			expect(metric(report, "instances").value).toBe(802)
			expect(metric(report, "instances").status).toBe("over")
			expect(metric(report, "movingParts").value).toBe(800)
			local d = diagnostics(report, "perf.instances")[1]
			expect(d.severity).toBe("warning")
			expect(contains(d.hint, "reduce counts or segments on 'Rocks'")).toBe(true)
			expect(#diagnostics(report, "perf.moving_parts")).toBe(1)
		end)

		T.it("passes cost notes through as perf.note infos", function()
			local def = effect({ component("streak", "trail") })
			local report = Analyzer.analyze(def)
			local notes = diagnostics(report, "perf.note")
			expect(#notes).toBe(1)
			expect(notes[1].severity).toBe("info")
			expect(notes[1].componentId).toBe("streak")
			expect(report.components[1].notes).toHaveLength(1)
		end)

		T.it("sorts the per-component breakdown by cost share", function()
			local def = effect({
				component("tiny", "part"),
				component("spray", "particles", { rate = 400, lifetime = 5 }),
				component("lamp", "light"),
			})
			local report = Analyzer.analyze(def, { quality = "Low" })
			expect(report.components[1].id).toBe("spray")
			expect(report.components[#report.components].id).toBe("tiny")
			for i = 2, #report.components do
				expect(report.components[i - 1].score).toBeGreaterThanOrEqual(report.components[i].score)
			end
			expect(report.components[1].shares.liveParticles).toBeGreaterThan(0)
			expect(report.components[1].index).toBe(2)
		end)

		T.it("is deterministic and JSON-serializable", function()
			local def = effect({
				sparks({ events = { { id = "boom", time = 1, action = "emit", count = 50 } } }),
				component("halo", "ring"),
			})
			local a = Analyzer.analyze(def, { quality = "Medium" })
			local b = Analyzer.analyze(def, { quality = "Medium" })
			expect(a).toEqual(b)
			expect(Json.encode(a, { pretty = false })).toBe(Json.encode(b, { pretty = false }))
		end)

		T.it("validates options", function()
			local def = effect({ sparks() })
			expect(function()
				Analyzer.analyze(def, { quality = "Ultra" } :: any)
			end).toThrow("quality")
			expect(function()
				Analyzer.analyze(def, { sampleRate = 0 })
			end).toThrow("sampleRate")
			expect(function()
				Analyzer.analyze(def, { budgets = { fps = 60 } })
			end).toThrow("budgets")
			expect(Analyzer.analyze(def, { sampleRate = 100000 }).sampleRate).toBe(Analyzer.MAX_SAMPLE_RATE)
			expect(Analyzer.analyze(def).quality).toBe("High")
			expect(Analyzer.analyze(def).sampleRate).toBe(30)
		end)

		T.it("analyses every component type of the realistic fixture at every quality", function()
			local Fixtures = use("Tests.Specs.Helpers.EffectFixtures")
			local def = Fixtures.full(Json)
			local reports = Analyzer.compareQualities(def)
			for _, level in { "Low", "Medium", "High" } do
				local report = reports[level]
				expect(report.quality).toBe(level)
				expect(report.totals.components).toBeGreaterThan(5)
				expect(report.sampleCount).toBe(#report.series.time)
				for key, peak in report.peaks do
					local p: any = peak
					local finite = p.value == p.value and p.value >= 0 and p.value < math.huge
					local row: { any } = { level, key, finite }
					expect(row).toEqual({ level, key, true } :: { any })
					expect(#report.series[key]).toBe(report.sampleCount)
				end
				for _, c in report.components do
					local row: { any } = { level, c.id, c.score == c.score and c.score >= 0 }
					expect(row).toEqual({ level, c.id, true } :: { any })
				end
				-- every diagnostic is a perf.* (or passed-through compiler/graph) diagnostic with a path
				for _, d in report.diagnostics do
					expect(type(d.path)).toBe("string")
					expect(d.severity == "warning" or d.severity == "info").toBe(true)
				end
			end
			expect(reports.High.peaks.liveParticles.value).toBeGreaterThan(0)
			expect(reports.Low.peaks.liveParticles.value).toBeLessThan(reports.High.peaks.liveParticles.value)
			expect(reports.Low.totals.instances).toBeLessThan(reports.High.totals.instances)
			expect(reports.Low.totals.omitted).toBeGreaterThan(reports.High.totals.omitted) -- minQuality
		end)

		T.it("reads budgets from the configurable Analyzer.BUDGETS table", function()
			local def = effect({ sparks() })
			local saved = Analyzer.BUDGETS.High.liveParticles
			Analyzer.BUDGETS.High.liveParticles = 150
			local ok, report = pcall(Analyzer.analyze :: any, def)
			Analyzer.BUDGETS.High.liveParticles = saved
			expect(ok).toBe(true)
			expect(metric(report, "liveParticles").budget).toBe(150)
			expect(metric(report, "liveParticles").status).toBe("over")
			expect(Analyzer.BUDGETS.Low).toEqual({
				liveParticles = 300,
				emitters = 8,
				beams = 8,
				trails = 4,
				lights = 2,
				shadowLights = 0,
				movingParts = 40,
				propertyUpdates = 150,
				instances = 150,
			})
			expect(Analyzer.BUDGETS.Medium.liveParticles).toBe(800)
			expect(Analyzer.BUDGETS.High.shadowLights).toBe(2)
		end)
	end)
end
