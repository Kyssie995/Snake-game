--!strict
--[[
	Core/Scheduler — one RunService connection for every player, first-frame deferral, dt clamping, error isolation
	(docs/MODULE_CONTRACTS.md §18). Uses stand-in players (tables with step/destroy) and real Core/Players driven
	through the Lune fakes (ctx.fakes:step fires Heartbeat / PreRender).
]]
return function(T: any, use: (string) -> any, ctx: any)
	local Scheduler = use("AstraVFX.Core.Scheduler")
	local HarnessModule = use("Tests.Specs.Helpers.PlaybackHarness")
	local expect = T.expect

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end
	local isLune = ctx.environment == "lune"

	type Fake = {
		name: string,
		steps: { number },
		destroyed: number,
		step: (self: any, dt: number) -> boolean,
		destroy: (self: any) -> (),
	}

	local function fake(name: string, behaviour: ((self: any, dt: number) -> boolean)?): Fake
		local p: Fake = {
			name = name,
			steps = {},
			destroyed = 0,
			step = function(self: any, dt: number): boolean
				table.insert(self.steps, dt)
				if behaviour then
					return behaviour(self, dt)
				end
				return true
			end,
			destroy = function(self: any)
				self.destroyed += 1
			end,
		}
		return p
	end

	local function heartbeats(): number
		return ctx.fakes.heartbeat:connectionCount()
	end

	local baseline = 0
	T.beforeEach(function()
		Scheduler.clear()
		Scheduler.setEventName("Heartbeat")
		if isLune then
			baseline = heartbeats()
		end
	end)
	T.afterEach(function()
		Scheduler.clear()
		Scheduler.setEventName("Heartbeat")
		if isLune then
			ctx.fakes.flags.IsClient = true
		end
	end)

	T.describe("Scheduler connection", function()
		T.itIf(isLune, "holds exactly one Heartbeat connection while players exist", function()
			expect(Scheduler.isConnected()).toBe(false)
			local a, b, c = fake("a"), fake("b"), fake("c")
			Scheduler.add(a)
			expect(heartbeats()).toBe(baseline + 1)
			Scheduler.add(b)
			Scheduler.add(c)
			Scheduler.add(c) -- twice: no-op
			expect(Scheduler.count()).toBe(3)
			expect(heartbeats()).toBe(baseline + 1)
			expect(Scheduler.isConnected()).toBe(true)
			Scheduler.remove(a)
			Scheduler.remove(b)
			expect(heartbeats()).toBe(baseline + 1)
			Scheduler.remove(c)
			Scheduler.remove(c) -- unknown: no-op
			expect(Scheduler.count()).toBe(0)
			expect(heartbeats()).toBe(baseline)
			expect(Scheduler.isConnected()).toBe(false)
			expect(a.destroyed + b.destroyed + c.destroyed).toBe(0) -- remove never destroys
		end)

		T.itIf(isLune, "steps players from the frame after their first frame, through the RunService event", function()
			local a = fake("a")
			Scheduler.add(a)
			ctx.fakes:step(1 / 60) -- a's build frame: activated, not stepped
			expect(a.steps).toEqual({})
			ctx.fakes:step(1 / 60)
			ctx.fakes:step(1 / 30)
			expect(#a.steps).toBe(2)
			expect(a.steps[1]).toBeCloseTo(1 / 60, 1e-12)
			expect(a.steps[2]).toBeCloseTo(1 / 30, 1e-12)
			-- a player added later waits for its own first frame
			local b = fake("b")
			Scheduler.add(b)
			ctx.fakes:step(1 / 60)
			expect(#a.steps).toBe(3)
			expect(b.steps).toEqual({})
			ctx.fakes:step(1 / 60)
			expect(#b.steps).toBe(1)
		end)

		T.itIf(isLune, "uses PreRender only when selected on a client, and reconnects", function()
			local preBaseline = ctx.fakes.preRender:connectionCount()
			local a = fake("a")
			Scheduler.add(a)
			Scheduler.setEventName("PreRender")
			expect(Scheduler.getEventName()).toBe("PreRender")
			expect(heartbeats()).toBe(baseline)
			expect(ctx.fakes.preRender:connectionCount()).toBe(preBaseline + 1)
			ctx.fakes.preRender:Fire(0.02)
			ctx.fakes.preRender:Fire(0.02)
			expect(a.steps).toEqual({ 0.02 })
			Scheduler.setEventName("Heartbeat")
			expect(ctx.fakes.preRender:connectionCount()).toBe(preBaseline)
			expect(heartbeats()).toBe(baseline + 1)
			-- not a client (server): PreRender is refused, Heartbeat stays
			ctx.fakes.flags.IsClient = false
			Scheduler.setEventName("PreRender")
			expect(Scheduler.getEventName()).toBe("Heartbeat")
			expect(heartbeats()).toBe(baseline + 1)
			expect(function()
				Scheduler.setEventName("RenderStepped" :: any)
			end).toThrow("Heartbeat")
		end)
	end)

	T.describe("Scheduler.step", function()
		T.it("clamps dt to [0, 0.1]", function()
			local a = fake("a")
			Scheduler.add(a)
			Scheduler.step(0) -- first frame
			Scheduler.step(5)
			Scheduler.step(-1)
			Scheduler.step(0 / 0)
			Scheduler.step(0.05)
			Scheduler.step(math.huge)
			expect(a.steps).toEqual({ 0.1, 0, 0, 0.05, 0.1 })
		end)

		T.itIf(isLune, "removes players that report the end and disconnects when the last one is gone", function()
			local a = fake("a", function(self: any, _dt: number): boolean
				return #self.steps < 3
			end)
			local b = fake("b")
			Scheduler.add(a)
			Scheduler.add(b)
			for _ = 1, 5 do
				Scheduler.step(0.01)
			end
			expect(#a.steps).toBe(3)
			expect(Scheduler.count()).toBe(1)
			expect(a.destroyed).toBe(0)
			Scheduler.remove(b)
			expect(heartbeats()).toBe(baseline)
		end)

		T.it("isolates a failing player: it is removed and destroyed, the others continue", function()
			local a = fake("a")
			local bad = fake("bad", function(_self: any, _dt: number): boolean
				error("frame exploded")
			end)
			local c = fake("c")
			Scheduler.add(a)
			Scheduler.add(bad)
			Scheduler.add(c)
			Scheduler.step(0.01)
			Scheduler.step(0.01)
			Scheduler.step(0.01)
			expect(#bad.steps).toBe(1)
			expect(bad.destroyed).toBe(1)
			expect(#a.steps).toBe(2)
			expect(#c.steps).toBe(2)
			expect(Scheduler.count()).toBe(2)
			-- a failing destroy is reported too and does not break the frame
			local worse = fake("worse", function(_self: any, _dt: number): boolean
				error("again")
			end)
			worse.destroy = function(_self: any)
				error("destroy exploded")
			end
			Scheduler.add(worse)
			Scheduler.step(0.01)
			Scheduler.step(0.01)
			expect(Scheduler.count()).toBe(2)
			expect(#a.steps).toBe(4)
		end)

		T.it("lets players add and remove players while stepping; nested steps are ignored", function()
			local late = fake("late")
			local victim = fake("victim")
			local spawner: Fake
			spawner = fake("spawner", function(self: any, _dt: number): boolean
				if #self.steps == 1 then
					Scheduler.add(late)
					Scheduler.remove(victim)
					Scheduler.remove(spawner)
					Scheduler.step(1) -- nested: ignored
				end
				return true
			end)
			Scheduler.add(spawner)
			Scheduler.add(victim)
			Scheduler.step(0.01) -- first frame of both
			Scheduler.step(0.01) -- spawner adds late, removes victim (not stepped afterwards) and itself
			expect(#spawner.steps).toBe(1)
			local victimSteps = #victim.steps
			expect(victimSteps <= 1).toBe(true)
			expect(late.steps).toEqual({}) -- added during the step: waits for its first frame
			Scheduler.step(0.02)
			expect(late.steps).toEqual({ 0.02 })
			expect(#victim.steps).toBe(victimSteps)
			expect(Scheduler.count()).toBe(1)
		end)

		T.it("clear() destroys every player and players() lists them", function()
			local a, b = fake("a"), fake("b")
			Scheduler.add(a)
			Scheduler.step(0)
			Scheduler.add(b)
			local list = Scheduler.players()
			expect(#list).toBe(2)
			expect(list[1]).toBe(a)
			expect(list[2]).toBe(b)
			Scheduler.clear()
			expect(a.destroyed).toBe(1)
			expect(b.destroyed).toBe(1)
			expect(Scheduler.count()).toBe(0)
			expect(Scheduler.isConnected()).toBe(false)
		end)

		T.it("rejects things that are not players", function()
			expect(function()
				Scheduler.add(nil :: any)
			end).toThrow("step method")
			expect(function()
				Scheduler.add({} :: any)
			end).toThrow("step method")
		end)
	end)

	T.describe("Scheduler with real players", function()
		T.itIf(isLune, "drives Core/Players from Heartbeat and never steps one in its build frame", function()
			local H = HarnessModule.new(use, ctx)
			local ok, err = pcall(function()
				local def = {
					schemaVersion = 1,
					id = "sched",
					name = "Sched",
					duration = 0.5,
					components = R({
						id = "sparks",
						name = "Sparks",
						type = "particles",
						properties = { rate = 0, burst = 4, lifetime = { 0.1, 0.1 } },
					}),
				}
				local p = H:player(def)
				local emitter = p.built.controllers.sparks.instances[1]
				local mark = H:emitMark()
				p.player:start()
				Scheduler.add(p.player)
				ctx.fakes:step(1 / 60) -- the frame the copy was built in: nothing runs
				expect(H:emitsSince(mark, emitter)).toEqual({})
				expect(p.player.time).toBe(0)
				ctx.fakes:step(1 / 60)
				expect(H:emitsSince(mark, emitter)).toEqual({ 4 })
				expect(p.player.time).toBeCloseTo(1 / 60, 1e-12)
				-- the player finishes by itself; the scheduler removes it and disconnects
				for _ = 1, 60 do
					ctx.fakes:step(1 / 60)
				end
				expect(p.player.state).toBe("finished")
				expect(Scheduler.count()).toBe(0)
				expect(heartbeats()).toBe(baseline)
				expect(p.built.destroyed).toBe(true)
			end :: any)
			H:cleanup()
			if not ok then
				error(err, 0)
			end
		end)

		T.itIf(isLune, "a player whose controller fails is destroyed and removed", function()
			local H = HarnessModule.new(use, ctx)
			local ok, err = pcall(function()
				local def = {
					schemaVersion = 1,
					id = "boom",
					name = "Boom",
					duration = 1,
					components = R({ id = "core", name = "Core", type = "part" }),
				}
				local good = H:player(def)
				local bad = H:player(def)
				bad.built.controllers.core.update = function()
					error("controller exploded")
				end
				good.player:start()
				bad.player:start()
				Scheduler.add(good.player)
				Scheduler.add(bad.player)
				ctx.fakes:step(1 / 60)
				ctx.fakes:step(1 / 60)
				expect(bad.player.state).toBe("destroyed")
				expect(bad.built.destroyed).toBe(true)
				expect(good.player.state).toBe("playing")
				expect(Scheduler.count()).toBe(1)
			end :: any)
			H:cleanup()
			if not ok then
				error(err, 0)
			end
		end)
	end)
end
