--!strict
return function(T: any, use: (string) -> any, _ctx: any)
	local Timeline = use("AstraVFX.Core.Timeline")
	local Random = use("AstraVFX.Core.Random")

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function L(...: any): { any }
		return { ... }
	end

	local function effect(duration: any): any
		return { schemaVersion = 1, id = "fx", name = "FX", duration = duration, components = {} }
	end

	local function component(fields: { [string]: any }?): any
		local c: any = { id = "c", name = "C", type = "group" }
		local f: { [string]: any } = fields or {}
		for k, v in f do
			c[k] = v
		end
		return c
	end

	local function compiled(id: string, startTime: number, endTime: number, events: { any }?): any
		return {
			id = id,
			name = id,
			type = "particles",
			depth = 0,
			startTime = startTime,
			endTime = endTime,
			props = {},
			position = Vector3.zero,
			rotation = Vector3.zero,
			scale = 1,
			tracks = {},
			events = events or {},
			seed = 1,
		}
	end

	local function ev(id: string, time: number, action: string?, extra: { [string]: any }?): any
		local e: any = { id = id, time = time, action = action or "emit" }
		local f: { [string]: any } = extra or {}
		for k, v in f do
			e[k] = v
		end
		return e
	end

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function summary(actions: { any }): { string }
		local out = {}
		for _, a in actions do
			table.insert(out, string.format("%g %s %s", a.time, a.action, tostring(a.sourceId)))
		end
		return out
	end

	T.describe("Timeline", function()
		T.describe("span", function()
			T.it("defaults to [0, duration) for components without timing", function()
				local s, e = Timeline.span(effect(2), component())
				T.expect(s).toBe(0)
				T.expect(e).toBe(2)
			end)

			T.it("uses startTime with the default duration = effect duration - startTime", function()
				local s, e = Timeline.span(effect(3), component({ startTime = 1.25 }))
				T.expect(s).toBe(1.25)
				T.expect(e).toBe(3)
			end)

			T.it("uses an explicit duration", function()
				local s, e = Timeline.span(effect(3), component({ startTime = 0.5, duration = 1 }))
				T.expect(s).toBe(0.5)
				T.expect(e).toBe(1.5)
				local s2, e2 = Timeline.span(effect(3), component({ duration = 0.25 }))
				T.expect(s2).toBe(0)
				T.expect(e2).toBe(0.25)
			end)

			T.it("clamps the span to the effect duration", function()
				local s, e = Timeline.span(effect(2), component({ startTime = 1.5, duration = 5 }))
				T.expect(s).toBe(1.5)
				T.expect(e).toBe(2)
				local s2, e2 = Timeline.span(effect(2), component({ startTime = 4, duration = 1 }))
				T.expect(s2).toBe(2)
				T.expect(e2).toBe(2)
				local s3, e3 = Timeline.span(effect(2), component({ startTime = 4 }))
				T.expect(s3).toBe(2)
				T.expect(e3).toBe(2)
			end)

			T.it("intersects negative start times with [0, duration]", function()
				local s, e = Timeline.span(effect(2), component({ startTime = -1, duration = 1.5 }))
				T.expect(s).toBe(0)
				T.expect(e).toBe(0.5)
				local s2, e2 = Timeline.span(effect(2), component({ startTime = -1 }))
				T.expect(s2).toBe(0)
				T.expect(e2).toBe(2)
				local s3, e3 = Timeline.span(effect(2), component({ startTime = -3, duration = 1 }))
				T.expect(s3).toBe(0)
				T.expect(e3).toBe(0)
			end)

			T.it("gives an empty span for zero or negative durations", function()
				local s, e = Timeline.span(effect(2), component({ startTime = 1, duration = 0 }))
				T.expect(s).toBe(1)
				T.expect(e).toBe(1)
				local s2, e2 = Timeline.span(effect(2), component({ startTime = 1, duration = -0.5 }))
				T.expect(s2).toBe(1)
				T.expect(e2).toBe(1)
			end)

			T.it("falls back to defaults for NaN and non-number fields", function()
				local s, e = Timeline.span(effect(2), component({ startTime = 0 / 0, duration = 0 / 0 }))
				T.expect(s).toBe(0)
				T.expect(e).toBe(2)
				local s2, e2 = Timeline.span(effect(2), component({ startTime = "1", duration = "x" }))
				T.expect(s2).toBe(0)
				T.expect(e2).toBe(2)
			end)

			T.it("handles infinite fields", function()
				local s, e = Timeline.span(effect(2), component({ startTime = 0.5, duration = math.huge }))
				T.expect(s).toBe(0.5)
				T.expect(e).toBe(2)
				local s2, e2 = Timeline.span(effect(2), component({ startTime = -math.huge, duration = math.huge }))
				T.expect(s2).toBe(0)
				T.expect(e2).toBe(2)
				local s3, e3 = Timeline.span(effect(2), component({ startTime = math.huge }))
				T.expect(s3).toBe(2)
				T.expect(e3).toBe(2)
			end)

			T.it("treats an invalid effect duration as 0", function()
				for _, d in L(0, -1, 0 / 0, math.huge, "2", {}) do
					local s, e = Timeline.span(effect(d), component({ startTime = 0.5 }))
					T.expect(s).toBe(0)
					T.expect(e).toBe(0)
				end
				local s, e = Timeline.span(effect(nil), component({ startTime = 0.5 }))
				T.expect(s).toBe(0)
				T.expect(e).toBe(0)
			end)

			T.it("normalizes -0 to 0", function()
				local s, e = Timeline.span(effect(1), component({ startTime = -0, duration = -0 }))
				T.expect(1 / s).toBe(math.huge)
				T.expect(1 / e).toBe(math.huge)
			end)

			T.it("errors for non-table arguments", function()
				T.expect(function()
					Timeline.span(nil :: any, component())
				end).toThrow("effect definition must be a table")
				T.expect(function()
					Timeline.span(effect(1), nil :: any)
				end).toThrow("component definition must be a table")
			end)
		end)

		T.describe("isActive", function()
			T.it("is true on [start, end) only", function()
				local c = compiled("a", 0.5, 1.5)
				T.expect(Timeline.isActive(c, 0.4999)).toBe(false)
				T.expect(Timeline.isActive(c, 0.5)).toBe(true)
				T.expect(Timeline.isActive(c, 1)).toBe(true)
				T.expect(Timeline.isActive(c, 1.4999)).toBe(true)
				T.expect(Timeline.isActive(c, 1.5)).toBe(false)
				T.expect(Timeline.isActive(c, 0 / 0)).toBe(false)
			end)

			T.it("is never true for an empty span", function()
				local c = compiled("a", 1, 1)
				T.expect(Timeline.isActive(c, 1)).toBe(false)
				T.expect(Timeline.isActive(c, 0.999)).toBe(false)
			end)
		end)

		T.describe("staticSchedule", function()
			T.it("converts component events to absolute actions", function()
				local schedule = Timeline.staticSchedule({
					compiled("burst", 0.5, 2, {
						ev("e1", 0, "emit", { count = 30 }),
						ev("e2", 0.25, "disable"),
					}),
				}, {})
				T.expect(#schedule).toBe(2)
				local a = schedule[1]
				T.expect(a.time).toBe(0.5)
				T.expect(a.action).toBe("emit")
				T.expect(a.componentId).toBe("burst")
				T.expect(a.count).toBe(30)
				T.expect(a.source).toBe("event")
				T.expect(a.sourceId).toBe("e1")
				T.expect(a.order).toBe(1)
				T.expect(schedule[2].time).toBe(0.75)
				T.expect(schedule[2].action).toBe("disable")
				T.expect(schedule[2].count).toBeNil()
				T.expect(schedule[2].order).toBe(2)
			end)

			T.it("drops events outside the component span [start, end)", function()
				local schedule = Timeline.staticSchedule({
					compiled("c", 1, 2, {
						ev("before", -0.1),
						ev("start", 0),
						ev("inside", 0.999),
						ev("atEnd", 1),
						ev("after", 3),
						ev("nan", 0 / 0),
						ev("inf", math.huge),
					}),
				}, {})
				local ids = {}
				for _, a in schedule do
					table.insert(ids, a.sourceId)
				end
				T.expect(ids).toEqual({ "start", "inside" })
			end)

			T.it("drops every event of an empty span", function()
				local schedule = Timeline.staticSchedule({ compiled("c", 1, 1, { ev("a", 0) }) }, {})
				T.expect(#schedule).toBe(0)
			end)

			T.it("adds marker events as fire actions and skips markers without event", function()
				local schedule = Timeline.staticSchedule(
					{},
					L(
						{ id = "m1", time = 0.4, label = "Impact", event = "Impact" },
						{ id = "m2", time = 0.6, label = "Note" },
						{ id = "m3", time = 0.8, label = "Empty", event = "" },
						{ id = "m4", time = 0 / 0, label = "Broken", event = "Broken" }
					)
				)
				T.expect(#schedule).toBe(1)
				local a = schedule[1]
				T.expect(a.time).toBe(0.4)
				T.expect(a.action).toBe("fire")
				T.expect(a.name).toBe("Impact")
				T.expect(a.source).toBe("marker")
				T.expect(a.sourceId).toBe("m1")
				T.expect(a.componentId).toBeNil()
				T.expect(a.order).toBe(1)
			end)

			T.it("copies the event name of fire events", function()
				local schedule = Timeline.staticSchedule({
					compiled("snd", 0, 1, { ev("f", 0.5, "fire", { name = "Boom" }) }),
				})
				T.expect(schedule[1].name).toBe("Boom")
				T.expect(schedule[1].componentId).toBe("snd")
			end)

			T.it("orders by time, then component order, then event order; markers last on ties", function()
				local schedule = Timeline.staticSchedule({
					compiled("a", 0, 2, { ev("a1", 1), ev("a2", 0.5), ev("a3", 1) }),
					compiled("b", 0.5, 2, { ev("b1", 0.5), ev("b2", 0) }),
					compiled("c", 0, 2, { ev("c1", 1) }),
				}, {
					{ id = "m1", time = 1, label = "M1", event = "One" },
					{ id = "m0", time = 0.5, label = "M0", event = "Half" },
				})
				T.expect(summary(schedule)).toEqual({
					"0.5 emit a2",
					"0.5 emit b2",
					"0.5 fire m0",
					"1 emit a1",
					"1 emit a3",
					"1 emit b1",
					"1 emit c1",
					"1 fire m1",
				})
				for i, a in schedule do
					T.expect(a.order).toBe(i)
				end
			end)

			T.it("handles missing markers and components without events", function()
				local c = compiled("c", 0, 1)
				c.events = nil
				T.expect(Timeline.staticSchedule({ c })).toEqual({})
				T.expect(Timeline.staticSchedule({}, nil)).toEqual({})
			end)

			T.it("does not mutate its inputs", function()
				local components = { compiled("a", 0, 2, { ev("x", 1), ev("y", 0.5) }) }
				local markers = { { id = "m", time = 0.1, label = "M", event = "E" } }
				local before = deepCopy({ components, markers })
				Timeline.staticSchedule(components, markers)
				T.expect({ components, markers }).toEqual(before)
			end)

			T.it("is deterministic", function()
				local rng = Random.new(5)
				local components = {}
				for i = 1, 20 do
					local events = {}
					for j = 1, 10 do
						table.insert(events, ev("e" .. j, math.floor(rng:next() * 8) / 8))
					end
					table.insert(components, compiled("c" .. i, math.floor(rng:next() * 4) / 4, 2, events))
				end
				local a = Timeline.staticSchedule(components, {})
				local b = Timeline.staticSchedule(components, {})
				T.expect(a).toEqual(b)
				for i = 2, #a do
					T.expect(a[i].time >= a[i - 1].time).toBe(true)
				end
			end)
		end)

		T.describe("sort", function()
			local function action(time: number, order: number?, tag: string?): any
				return { time = time, action = "emit", source = "graph", order = order or 0, sourceId = tag }
			end

			T.it("sorts by time, then order", function()
				local list = { action(2, 1, "a"), action(1, 5, "b"), action(1, 2, "c"), action(0, 9, "d") }
				Timeline.sort(list)
				T.expect(summary(list)).toEqual({ "0 emit d", "1 emit c", "1 emit b", "2 emit a" })
			end)

			T.it("is stable for equal (time, order)", function()
				local list = {}
				for i = 1, 50 do
					table.insert(list, action(i % 3, 0, tostring(i)))
				end
				Timeline.sort(list)
				local previous: any = nil
				for _, a in list do
					if previous and previous.time == a.time then
						T.expect(tonumber(a.sourceId) > tonumber(previous.sourceId)).toBe(true)
					end
					previous = a
				end
			end)

			T.it("sorts in place and returns the same table", function()
				local list = { action(1), action(0) }
				T.expect(Timeline.sort(list)).toBe(list)
				T.expect(list[1].time).toBe(0)
				local empty = {}
				T.expect(Timeline.sort(empty)).toBe(empty)
				local single = { action(3) }
				T.expect(Timeline.sort(single)[1].time).toBe(3)
			end)

			T.it("treats missing order as 0 and puts NaN times last", function()
				local a = action(1, 1, "a")
				local b: any = { time = 1, action = "emit", source = "graph", sourceId = "b" }
				local c = action(0 / 0, 0, "nan")
				local d = action(math.huge, 0, "inf")
				local list = { c, a, d, b }
				Timeline.sort(list)
				T.expect(list[1].sourceId).toBe("b")
				T.expect(list[2].sourceId).toBe("a")
				T.expect(list[3].sourceId).toBe("inf")
				T.expect(list[4].sourceId).toBe("nan")
			end)

			T.it("matches a reference stable insertion sort on random data", function()
				local rng = Random.new(2024)
				for _, n in { 2, 3, 7, 16, 33, 100, 1000 } do
					local list = {}
					for i = 1, n do
						table.insert(list, action(rng:int(0, 10) / 4, rng:int(0, 3), tostring(i)))
					end
					local reference = table.clone(list)
					for i = 2, #reference do
						local item = reference[i]
						local j = i - 1
						while
							j >= 1
							and (
								reference[j].time > item.time
								or (reference[j].time == item.time and reference[j].order > item.order)
							)
						do
							reference[j + 1] = reference[j]
							j -= 1
						end
						reference[j + 1] = item
					end
					Timeline.sort(list)
					for i = 1, n do
						T.expect(list[i]).toBe(reference[i])
					end
				end
			end)
		end)

		T.describe("range", function()
			local function at(times: { number }): { any }
				local list = {}
				for i, t in times do
					table.insert(list, { time = t, action = "emit", source = "event", order = i })
				end
				return list
			end

			T.it("returns the actions with t0 < time <= t1", function()
				local list = at({ 0, 0.5, 1, 1, 1.5, 2 })
				local first, last = Timeline.range(list, 0.5, 1.5, false)
				T.expect(first).toBe(3)
				T.expect(last).toBe(5)
			end)

			T.it("includes t0 when includeStart is true", function()
				local list = at({ 0, 0.5, 1, 1, 1.5, 2 })
				local first, last = Timeline.range(list, 0, 0.5, true)
				T.expect(first).toBe(1)
				T.expect(last).toBe(2)
				local first2, last2 = Timeline.range(list, 1, 1, true)
				T.expect(first2).toBe(3)
				T.expect(last2).toBe(4)
				local first3, last3 = Timeline.range(list, 0, 0.5, nil)
				T.expect(first3).toBe(2)
				T.expect(last3).toBe(2)
			end)

			T.it("returns an empty range (last < first) when nothing is due", function()
				local list = at({ 0, 1, 2 })
				local first, last = Timeline.range(list, 0.1, 0.9, false)
				T.expect(last < first).toBe(true)
				local f2, l2 = Timeline.range(list, 1, 1, false)
				T.expect(l2 < f2).toBe(true)
				local f3, l3 = Timeline.range(list, 2, 5, false)
				T.expect(f3).toBe(4)
				T.expect(l3).toBe(3)
				local f4, l4 = Timeline.range(list, 1.5, 0.5, true)
				T.expect(l4 < f4).toBe(true)
				local f5, l5 = Timeline.range({}, 0, 10, true)
				T.expect(f5).toBe(1)
				T.expect(l5).toBe(0)
			end)

			T.it("covers everything with an unbounded interval", function()
				local list = at({ 0, 1, 2 })
				local first, last = Timeline.range(list, -math.huge, math.huge, true)
				T.expect(first).toBe(1)
				T.expect(last).toBe(3)
			end)

			T.it("returns an empty range for NaN bounds", function()
				local list = at({ 0, 1, 2 })
				local first, last = Timeline.range(list, 0 / 0, 1, false)
				T.expect(last < first).toBe(true)
				local f2, l2 = Timeline.range(list, 0, 0 / 0, true)
				T.expect(l2 < f2).toBe(true)
			end)

			T.it("never reports actions with NaN times as due (sort puts them last)", function()
				local list = at({ 1, 0 / 0, 2, 0 / 0 })
				Timeline.sort(list)
				T.expect(list[3].time ~= list[3].time).toBe(true)
				local first, last = Timeline.range(list, 0, 5, false)
				T.expect(first).toBe(1)
				T.expect(last).toBe(2)
				local f2, l2 = Timeline.range(list, -math.huge, math.huge, true)
				T.expect(f2).toBe(1)
				T.expect(l2).toBe(2)
				local f3, l3 = Timeline.range(list, 2, math.huge, false)
				T.expect(l3 < f3).toBe(true)
			end)

			T.it("matches a linear scan on random sorted data", function()
				local rng = Random.new(31)
				local times = {}
				for _ = 1, 300 do
					table.insert(times, rng:int(0, 60) / 8)
				end
				table.sort(times)
				local list = at(times)
				for _ = 1, 300 do
					local t0 = rng:int(-2, 62) / 8
					local t1 = t0 + rng:int(0, 10) / 8
					for _, includeStart in { false, true } do
						local first, last = Timeline.range(list, t0, t1, includeStart)
						for i, a in list do
							local due = (a.time > t0 or (includeStart and a.time == t0)) and a.time <= t1
							T.expect(i >= first and i <= last).toBe(due)
						end
					end
				end
			end)
		end)

		T.describe("snap", function()
			T.it("returns t unchanged without options or candidates", function()
				T.expect(Timeline.snap(0.37)).toBe(0.37)
				T.expect(Timeline.snap(0.37, {})).toBe(0.37)
				T.expect(Timeline.snap(0.37, { targets = {} })).toBe(0.37)
			end)

			T.it("snaps to the nearest grid line (always)", function()
				T.expect(Timeline.snap(0.37, { grid = 0.25 })).toBe(0.25)
				T.expect(Timeline.snap(0.38, { grid = 0.25 })).toBe(0.5)
				T.expect(Timeline.snap(0.37, { grid = 0.25, tolerance = 0.01 })).toBe(0.25)
				T.expect(Timeline.snap(-0.3, { grid = 0.25 })).toBe(-0.25)
				T.expect(Timeline.snap(0.125, { grid = 0.25 })).toBe(0.25) -- halves round up
			end)

			T.it("produces clean decimals for decimal grids", function()
				T.expect(Timeline.snap(0.31, { grid = 0.1 })).toBe(0.3)
				T.expect(Timeline.snap(0.69, { grid = 0.1 })).toBe(0.7)
				T.expect(Timeline.snap(1.04, { grid = 0.05 })).toBe(1.05)
				T.expect(Timeline.snap(0.35, { grid = 0.1 })).toBe(0.4)
				T.expect(Timeline.snap(0.51, { grid = 1 / 60 })).toBe(31 / 60)
				T.expect(Timeline.snap(1.4, { grid = 0.3 })).toBeCloseTo(1.5, 1e-12)
			end)

			T.it("snaps to targets within the tolerance only", function()
				T.expect(Timeline.snap(0.52, { targets = { 0.5, 0.9 }, tolerance = 0.05 })).toBe(0.5)
				T.expect(Timeline.snap(0.6, { targets = { 0.5, 0.9 }, tolerance = 0.05 })).toBe(0.6)
				T.expect(Timeline.snap(0.54, { targets = { 0.5 }, tolerance = 0.05 })).toBe(0.5)
				T.expect(Timeline.snap(0.625, { targets = { 0.5 }, tolerance = 0.125 })).toBe(0.5) -- inclusive
			end)

			T.it("snaps to the nearest target without a tolerance", function()
				T.expect(Timeline.snap(0.6, { targets = { 0.5, 0.9 } })).toBe(0.5)
				T.expect(Timeline.snap(0.8, { targets = { 0.5, 0.9 } })).toBe(0.9)
				T.expect(Timeline.snap(5, { targets = { 0.5 }, tolerance = math.huge })).toBe(0.5)
			end)

			T.it("lets the nearest candidate win between grid and targets", function()
				-- grid point 0.5 is 0.02 away, target 0.537 is 0.017 away
				T.expect(Timeline.snap(0.52, { grid = 0.1, targets = { 0.537 }, tolerance = 0.02 })).toBe(0.537)
				-- target out of tolerance: grid wins
				T.expect(Timeline.snap(0.51, { grid = 0.1, targets = { 0.537 }, tolerance = 0.02 })).toBe(0.5)
				-- grid closer than an in-tolerance target
				T.expect(Timeline.snap(0.502, { grid = 0.1, targets = { 0.51 }, tolerance = 0.02 })).toBe(0.5)
			end)

			T.it("prefers targets on ties, and earlier targets over later ones", function()
				-- 0.375: grid line 0.5 and target 0.25 are both 0.125 away (exact binary values)
				T.expect(Timeline.snap(0.375, { grid = 0.25, targets = { 0.25 }, tolerance = 0.2 })).toBe(0.25)
				T.expect(Timeline.snap(0.375, { grid = 0.25 })).toBe(0.5)
				T.expect(Timeline.snap(0.5, { targets = { 0.4, 0.6 } })).toBe(0.4)
				T.expect(Timeline.snap(0.5, { targets = { 0.6, 0.4 } })).toBe(0.6)
			end)

			T.it("ignores invalid grids, targets and tolerances", function()
				for _, grid in L(0, -0.1, 0 / 0, math.huge, "0.1") do
					T.expect(Timeline.snap(0.37, { grid = grid :: any })).toBe(0.37)
				end
				T.expect(Timeline.snap(0.37, { targets = { 0 / 0, math.huge, "0.4" :: any } })).toBe(0.37)
				-- an invalid tolerance disables target snapping (only exact matches remain)
				T.expect(Timeline.snap(0.37, { targets = { 0.4 }, tolerance = -1 })).toBe(0.37)
				T.expect(Timeline.snap(0.37, { targets = { 0.4 }, tolerance = 0 / 0 })).toBe(0.37)
				T.expect(Timeline.snap(0.4, { targets = { 0.4 }, tolerance = -1 })).toBe(0.4)
				T.expect(Timeline.snap(0.37, { targets = 5 :: any })).toBe(0.37)
			end)

			T.it("returns non-finite t unchanged", function()
				local nan = Timeline.snap(0 / 0, { grid = 0.1 })
				T.expect(nan ~= nan).toBe(true)
				T.expect(Timeline.snap(math.huge, { grid = 0.1, targets = { 1 } })).toBe(math.huge)
			end)

			T.it("normalizes -0 results to 0", function()
				T.expect(1 / Timeline.snap(-0.01, { grid = 0.1 })).toBe(math.huge)
			end)
		end)

		T.describe("format", function()
			T.it("formats seconds with up to 3 decimals", function()
				T.expect(Timeline.format(1.25)).toBe("1.25s")
				T.expect(Timeline.format(2)).toBe("2s")
				T.expect(Timeline.format(0)).toBe("0s")
				T.expect(Timeline.format(0.1)).toBe("0.1s")
				T.expect(Timeline.format(0.05)).toBe("0.05s")
				T.expect(Timeline.format(12.5)).toBe("12.5s")
				T.expect(Timeline.format(60)).toBe("60s")
				T.expect(Timeline.format(0.001)).toBe("0.001s")
			end)

			T.it("rounds half up to milliseconds", function()
				T.expect(Timeline.format(1.2345)).toBe("1.235s")
				T.expect(Timeline.format(1.0005)).toBe("1.001s")
				T.expect(Timeline.format(0.0004)).toBe("0s")
				T.expect(Timeline.format(0.9999)).toBe("1s")
				T.expect(Timeline.format(1 / 3)).toBe("0.333s")
			end)

			T.it("formats negative values and -0", function()
				T.expect(Timeline.format(-0.5)).toBe("-0.5s")
				T.expect(Timeline.format(-0)).toBe("0s")
				T.expect(Timeline.format(-0.0001)).toBe("0s")
				T.expect(Timeline.format(-2.25)).toBe("-2.25s")
			end)

			T.it("honours maxDecimals (clamped to 0..6)", function()
				T.expect(Timeline.format(1.23456, 1)).toBe("1.2s")
				T.expect(Timeline.format(1.25, 0)).toBe("1s")
				T.expect(Timeline.format(1.5, 0)).toBe("2s")
				T.expect(Timeline.format(1.2345678, 6)).toBe("1.234568s")
				T.expect(Timeline.format(1.2345678, 10)).toBe("1.234568s")
				T.expect(Timeline.format(1.25, -3)).toBe("1s")
				T.expect(Timeline.format(0.0625, 2.9)).toBe("0.06s")
			end)

			T.it("formats non-finite and huge values", function()
				T.expect(Timeline.format(0 / 0)).toBe("NaN")
				T.expect(Timeline.format(math.huge)).toBe("inf")
				T.expect(Timeline.format(-math.huge)).toBe("-inf")
				T.expect(Timeline.format(1e20)).toBe("100000000000000000000s")
				T.expect(Timeline.format(123456789)).toBe("123456789s")
			end)

			T.it("errors for non-numbers", function()
				T.expect(function()
					Timeline.format("1" :: any)
				end).toThrow("expected a number")
				T.expect(function()
					Timeline.format(1, "2" :: any)
				end).toThrow("maxDecimals must be a number")
			end)
		end)
	end)
end
