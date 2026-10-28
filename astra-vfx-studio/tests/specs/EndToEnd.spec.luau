--!strict
--[[
	EndToEnd — the whole runtime from JSON text to cleanup through the public API (AstraVFX) and the real
	Core/Scheduler, driven by the Lune fakes (ctx.fakes:step fires Heartbeat; Emit / Clear / Sound calls are logged,
	BulkMoveTo applies the CFrames). docs/ARCHITECTURE.md §5, docs/MODULE_CONTRACTS.md §12–§19.

	Effects (inline JSON text, schema version 1):
	  EXPLOSION  flash + shockwave + burst particles (+ emit event) + smoke particles (rate track) + debris + light
	             (brightness track); marker "Impact" at 0.1 s
	  LIGHTNING  lightning (regenerate event, thickness track) + flash + ring (radius / transparency tracks) +
	             particles fed by a graph: OnMarker(strike) -> Loop(4 × 0.1 s) -> Emit 12, completed -> Delay 0.2 s
	             -> Emit 30 -> FireEvent "Aftershock"; marker "Impact" at 0.2 s
	  AURA       looping 1 s: spinning group (360°/s) with a trail and particles as children + a pulsing sphere;
	             marker "Pulse" at 0.5 s

	Part 1 plays the three effects end to end (activation order, emits, events, finish / stop, pooling, cleanup of
	instances, connections, handles and render bindings, no warnings) and checks that procedural state is a pure
	function of the seed. Part 2 is an adversarial review of the runtime (loop boundaries, long frames, time-scale
	changes, seek / resume, attach targets that disappear, palette × quality × scale variants, fuzzed input through
	Register, re-entrant lifecycle calls, yielding handlers, API names). Part 3 is a CPU-side performance sanity
	check: Lune timings are reported for information only and are NOT frame-rate claims; the assertions are about
	work counts (no growth with elapsed frames, linear in components).

	Every test captures warn() of the runtime modules (the loader's global) and fails on unexpected warnings, so a
	player error isolated by the Scheduler ("effect player failed and was destroyed") cannot pass silently.
]]
return function(T: any, use: (string) -> any, ctx: any)
	local AstraVFX = use("AstraVFX")
	local Builder = use("AstraVFX.Core.Builder")
	local Compiler = use("AstraVFX.Core.Compiler")
	local Constants = use("AstraVFX.Core.Constants")
	local Json = use("AstraVFX.Core.Json")
	local Migration = use("AstraVFX.Core.Migration")
	local Player = use("AstraVFX.Core.Player")
	local Pool = use("AstraVFX.Core.Pool")
	local Random = use("AstraVFX.Core.Random")
	local Scheduler = use("AstraVFX.Core.Scheduler")
	local Validation = use("AstraVFX.Core.Validation")
	local Fixtures = use("Tests.Specs.Helpers.EffectFixtures")
	local HarnessModule = use("Tests.Specs.Helpers.PlaybackHarness")
	local expect = T.expect

	local isLune = ctx.environment == "lune"
	local DT = 1 / 60
	local EPS = 1e-9

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- Effects
	-- ─────────────────────────────────────────────────────────────────────────

	local EXPLOSION_JSON = [=[
{
  "schemaVersion": 1,
  "id": "e2eExplosion",
  "name": "E2E Explosion",
  "description": "Ground explosion: flash, shockwave, sparks, smoke, debris and a light pulse.",
  "tags": ["e2e", "explosion"],
  "duration": 2,
  "seed": 1234,
  "palette": { "fire": "#FF8A2A", "hot": "#FFF4C8", "smoke": "#3A3430" },
  "markers": [
    { "id": "impact", "time": 0.1, "label": "Impact", "phase": "impact", "event": "Impact" },
    { "id": "settle", "time": 1.2, "label": "Settle", "phase": "dissipation" }
  ],
  "components": [
    { "id": "flash", "name": "Flash", "type": "flash", "phase": "impact", "startTime": 0.1, "duration": 0.4,
      "properties": { "color": "$hot", "size": 10, "startSize": 2, "attack": 0.03, "hold": 0.02, "decay": 0.3,
        "range": 24, "peakBrightness": 12 } },
    { "id": "wave", "name": "Shockwave", "type": "shockwave", "phase": "impact", "startTime": 0.1, "duration": 0.8,
      "transform": { "position": [0, 0.2, 0] },
      "properties": { "startRadius": 1, "endRadius": 18, "height": 0.4, "layers": 2, "color": "$fire",
        "startTransparency": 0.2 } },
    { "id": "sparks", "name": "Sparks", "type": "particles", "phase": "impact", "startTime": 0.1, "duration": 0.3,
      "properties": { "rate": 0, "burst": 40, "lifetime": [0.3, 0.6], "speed": [30, 60], "spreadAngle": [180, 180],
        "size": [[0, 0.6], [1, 0]], "color": [[0, "$hot"], [1, "$fire"]], "lightEmission": 1,
        "acceleration": [0, -40, 0] },
      "events": [ { "id": "second", "time": 0.1, "action": "emit", "count": 20 } ] },
    { "id": "smoke", "name": "Smoke", "type": "particles", "phase": "secondary", "startTime": 0.15, "duration": 1.2,
      "properties": { "rate": 30, "lifetime": [0.8, 1.2], "speed": [4, 8], "spreadAngle": [60, 60],
        "size": [[0, 2], [1, 6]], "color": "$smoke", "transparency": [[0, 0.3], [1, 1]], "shape": "Sphere",
        "emitterSize": [3, 1, 3] },
      "tracks": [ { "id": "rateDown", "channel": "rate", "keyframes": [
        { "time": 0, "value": 30 }, { "time": 1.1, "value": 0, "easing": "Quad.Out" } ] } ] },
    { "id": "rocks", "name": "Rocks", "type": "debris", "phase": "secondary", "startTime": 0.1, "duration": 1.5,
      "properties": { "count": 16, "size": [0.4, 1.2], "speed": [25, 45], "spreadAngle": 70,
        "gravity": [0, -90, 0], "floor": true, "floorHeight": 0, "fadeTime": 0.4 } },
    { "id": "glow", "name": "Glow", "type": "light", "phase": "impact", "startTime": 0.1, "duration": 0.6,
      "transform": { "position": [0, 2, 0] },
      "properties": { "color": "$fire", "brightness": 8, "range": 30 },
      "tracks": [ { "id": "fadeLight", "channel": "brightness", "keyframes": [
        { "time": 0, "value": 8 }, { "time": 0.55, "value": 0, "easing": "Quad.In" } ] } ] }
  ]
}
]=]

	local LIGHTNING_JSON = [=[
{
  "schemaVersion": 1,
  "id": "e2eLightning",
  "name": "E2E Lightning Strike",
  "duration": 1.5,
  "seed": 77,
  "palette": { "bolt": "#BFE6FF", "core": "#FFFFFF" },
  "markers": [ { "id": "strike", "time": 0.2, "label": "Strike", "phase": "impact", "event": "Impact" } ],
  "components": [
    { "id": "bolt", "name": "Bolt", "type": "lightning", "startTime": 0.2, "duration": 0.5,
      "properties": { "from": [0, 30, 0], "to": [0, 0, 0], "segments": 16, "branches": 3, "jitter": 2.5,
        "flickerRate": 30, "thickness": 0.5, "color": "$bolt" },
      "tracks": [ { "id": "thin", "channel": "thickness", "keyframes": [
        { "time": 0, "value": 0.6 }, { "time": 0.45, "value": 0.05, "easing": "Quad.In" } ] } ],
      "events": [ { "id": "reshape", "time": 0.25, "action": "regenerate" } ] },
    { "id": "flash", "name": "Flash", "type": "flash", "startTime": 0.2, "duration": 0.35,
      "properties": { "color": "$core", "size": 6, "startSize": 1, "decay": 0.25 } },
    { "id": "ring", "name": "Ground Ring", "type": "ring", "startTime": 0.2, "duration": 0.8,
      "transform": { "position": [0, 0.1, 0] },
      "properties": { "style": "ring", "segments": 32, "radius": 2, "thickness": 0.3, "color": "$bolt" },
      "tracks": [
        { "id": "grow", "channel": "radius", "keyframes": [
          { "time": 0, "value": 2 }, { "time": 0.7, "value": 12, "easing": "Quart.Out" } ] },
        { "id": "fade", "channel": "transparency", "keyframes": [
          { "time": 0, "value": 0 }, { "time": 0.7, "value": 1 } ] } ] },
    { "id": "zaps", "name": "Zaps", "type": "particles",
      "properties": { "rate": 0, "lifetime": [0.15, 0.3], "speed": [15, 25], "spreadAngle": [180, 180],
        "color": "$bolt", "lightEmission": 1, "size": 0.4 } }
  ],
  "graph": {
    "nodes": [
      { "id": "onStrike", "type": "OnMarker", "params": { "marker": "strike" } },
      { "id": "crackle", "type": "Loop", "params": { "count": 4, "interval": 0.1 } },
      { "id": "zap", "type": "Emit", "params": { "target": "zaps", "count": 12 } },
      { "id": "wait", "type": "Delay", "params": { "seconds": 0.2 } },
      { "id": "final", "type": "Emit", "params": { "target": "zaps", "count": 30 } },
      { "id": "after", "type": "FireEvent", "params": { "name": "Aftershock" } }
    ],
    "links": [
      { "from": "onStrike.out", "to": "crackle.in" },
      { "from": "crackle.body", "to": "zap.in" },
      { "from": "crackle.completed", "to": "wait.in" },
      { "from": "wait.out", "to": "final.in" },
      { "from": "final.out", "to": "after.in" }
    ]
  }
}
]=]

	local AURA_JSON = [=[
{
  "schemaVersion": 1,
  "id": "e2eAura",
  "name": "E2E Aura",
  "duration": 1,
  "loop": true,
  "seed": 5,
  "palette": { "aura": "#7A4DFF", "spark": "#E0D0FF" },
  "markers": [ { "id": "pulse", "time": 0.5, "label": "Pulse", "event": "Pulse" } ],
  "components": [
    { "id": "pivot", "name": "Pivot", "type": "group", "transform": { "position": [0, 2, 0] },
      "properties": { "spin": [0, 360, 0] } },
    { "id": "orbitTrail", "name": "Orbit Trail", "type": "trail", "parent": "pivot",
      "transform": { "position": [3, 0, 0] },
      "properties": { "width": 0.6, "lifetime": 0.3, "color": "$aura", "lightEmission": 1, "clearOnStart": false } },
    { "id": "motes", "name": "Motes", "type": "particles", "parent": "pivot", "transform": { "position": [-3, 0, 0] },
      "properties": { "rate": 15, "burst": 5, "lifetime": [0.5, 1], "speed": [1, 2], "color": "$spark", "size": 0.3 } },
    { "id": "core", "name": "Core", "type": "sphere", "transform": { "position": [0, 2, 0] },
      "properties": { "radius": 1, "coreColor": "$spark", "shellColor": "$aura", "pulseAmplitude": 0.1,
        "pulseFrequency": 2, "lightRange": 12 } }
  ]
}
]=]

	local function decode(text: string): any
		local ok, value = Json.decode(text)
		assert(ok, "JSON: " .. tostring(value))
		return value
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- Harness: warnings, scheduler frames, instrumentation
	-- ─────────────────────────────────────────────────────────────────────────

	local H: any = nil
	local baseline = 0
	local warnings: { string } = {}
	local originalWarn: any = nil
	local suspended: { thread } = {} -- coroutines a test left suspended (resumed in afterEach)

	T.beforeEach(function()
		AstraVFX._reset()
		Scheduler.clear()
		H = HarnessModule.new(use, ctx)
		table.clear(warnings)
		if isLune then
			baseline = ctx.fakes.heartbeat:connectionCount()
			originalWarn = ctx.loader.globals.warn
			ctx.loader.globals.warn = function(...: any)
				local parts = {}
				for i = 1, select("#", ...) do
					parts[i] = tostring((select(i, ...)))
				end
				table.insert(warnings, table.concat(parts, " "))
			end
		end
	end)

	T.afterEach(function()
		for _, co in suspended do
			if coroutine.status(co) == "suspended" then
				pcall(coroutine.resume, co)
			end
		end
		table.clear(suspended)
		if isLune and originalWarn then
			ctx.loader.globals.warn = originalWarn
			originalWarn = nil
		end
		AstraVFX._reset()
		Scheduler.clear()
		Pool.setCapacity(Pool.DEFAULT_CAPACITY)
		H:cleanup()
	end)

	local function expectNoWarnings()
		if #warnings > 0 then
			T.fail("unexpected warnings:\n  " .. table.concat(warnings, "\n  "))
		end
	end

	local function frames(n: number, dt: number?)
		for _ = 1, n do
			ctx.fakes:step(dt or DT)
		end
	end

	local function heartbeats(): number
		return ctx.fakes.heartbeat:connectionCount()
	end

	local function alive(handle: any): boolean
		local state = handle:GetState()
		return state ~= "finished" and state ~= "destroyed"
	end

	-- Steps scheduler frames until the handle has ended; returns the number of frames.
	local function runToEnd(handle: any, maxFrames: number, dt: number?): number
		local n = 0
		while alive(handle) do
			if n >= maxFrames then
				error("the effect did not end within " .. maxFrames .. " frames (state " .. handle:GetState() .. ")", 2)
			end
			ctx.fakes:step(dt or DT)
			n += 1
		end
		return n
	end

	type Log = { activations: { any }, actions: { any }, events: { any } }

	-- Wraps every controller's setActive and listens to actionExecuted / Event of one handle.
	local function instrument(handle: any): Log
		local player = handle._player
		local log: Log = { activations = {}, actions = {}, events = {} }
		for _, id in player.built.order do
			local controller = player.built.controllers[id]
			local original = controller.setActive
			controller.setActive = function(self: any, active: boolean, frame: any)
				table.insert(log.activations, {
					id = id,
					active = active,
					time = frame.time,
					seeking = frame.seeking,
					cycle = player.cycle,
				})
				return original(self, active, frame)
			end
		end
		player.actionExecuted:Connect(function(action: any)
			table.insert(log.actions, { time = player.time, cycle = player.cycle, action = action })
		end)
		handle.Event:Connect(function(name: string)
			table.insert(log.events, { name = name, time = player.time })
		end)
		return log
	end

	local function activationIds(log: Log, active: boolean): { string }
		local out = {}
		for _, a in log.activations do
			if a.active == active then
				table.insert(out, a.id)
			end
		end
		return out
	end

	-- Times of the first activation / deactivation of `id`.
	local function activationTime(log: Log, id: string, active: boolean): number?
		for _, a in log.activations do
			if a.id == id and a.active == active then
				return a.time
			end
		end
		return nil
	end

	-- True when `t` is the time of the first frame (length dt) that reaches `at`.
	local function firstFrameAt(t: number?, at: number, dt: number): boolean
		return t ~= nil and t >= at - EPS and t - dt < at + EPS
	end

	local function emitterOf(handle: any, id: string): any
		return handle._player.built.controllers[id].instances[1]
	end

	local function countEmits(log: Log, componentId: string?): { number }
		local out = {}
		for _, entry in log.actions do
			local a = entry.action
			if a.action == "emit" and (componentId == nil or a.componentId == componentId) then
				table.insert(out, a.count)
			end
		end
		return out
	end

	local function eventNames(log: Log): { string }
		local out = {}
		for _, e in log.events do
			table.insert(out, e.name)
		end
		return out
	end

	-- Everything a finished effect must have released.
	local function expectClean(parent: Instance?)
		expect(AstraVFX.ActiveCount()).toBe(0)
		expect(Scheduler.count()).toBe(0)
		expect(Scheduler.isConnected()).toBe(false)
		expect(heartbeats()).toBe(baseline)
		expect(ctx.fakes:renderBindingCount()).toBe(0)
		if parent then
			expect(#parent:GetChildren()).toBe(0)
		end
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- Part 1: three effects end to end
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("EndToEnd playback", function()
		T.itIf(isLune, "Register, Play, Seek and Stop never mutate the caller's definition table", function()
			local parent = H:folder("E2EPure", workspace)
			for _, text in { EXPLOSION_JSON, LIGHTNING_JSON, AURA_JSON } do
				local def = decode(text)
				local before = Json.encode(def)
				AstraVFX.Register(def)
				local handle = AstraVFX.Play(def.id, { Parent = parent, Quality = "Low", Scale = 2, Seed = 3 })
				frames(20)
				handle:Seek(0.3)
				handle:Fire("Detonate")
				frames(5)
				handle:Stop()
				runToEnd(handle, 400)
				expect(Json.encode(def)).toBe(before)
			end
			expectClean(parent)
			expectNoWarnings()
		end)

		T.it("the three effects validate without any diagnostic and compile on every quality level", function()
			for _, text in { EXPLOSION_JSON, LIGHTNING_JSON, AURA_JSON } do
				local def = decode(text)
				local result = Validation.validate(def, { strict = true })
				expect(#result.errors + #result.warnings + #result.infos).toBe(0)
				local migrated, migration = Migration.migrate(def)
				expect(migrated ~= nil).toBe(true)
				expect(#migration).toBe(0)
				for _, level in Constants.QUALITY_LEVELS do
					local _, compilerWarnings = Compiler.compile(def, { quality = level })
					expect(compilerWarnings).toEqual({})
				end
			end
		end)

		T.itIf(
			isLune,
			"explosion: JSON -> Register -> Play with options -> activation order, emits, Impact, cleanup",
			function()
				expect(AstraVFX.Register(EXPLOSION_JSON)).toBe("E2E Explosion")
				local parent = H:folder("E2EExplosion", workspace)
				local origin = CFrame.new(10, 0, -5) * CFrame.Angles(0, math.rad(30), 0)
				local onEvents: { string } = {}
				local handle = AstraVFX.Play("e2eExplosion", {
					CFrame = origin,
					Scale = 1.5,
					Quality = "High",
					Seed = 99,
					TimeScale = 1,
					Parent = parent,
					OnEvent = function(name: string)
						table.insert(onEvents, name)
					end,
				})
				local log = instrument(handle)
				local reasons: { string } = {}
				handle.Finished:Connect(function(reason: string)
					table.insert(reasons, reason)
				end)
				local container = handle._player.built.container
				expect(container.Parent).toBe(parent)
				local mark = H:emitMark()
				local sparks = emitterOf(handle, "sparks")
				local smoke = emitterOf(handle, "smoke")
				local light = emitterOf(handle, "glow")

				-- frame 1 is the build frame (Scheduler), frame 2 the first step (t = DT): nothing starts before 0.1 s
				frames(2)
				expect(handle:GetTime()).toBeCloseTo(DT, 1e-9)
				expect(log.activations).toEqual({})
				expect(H:emitsSince(mark)).toEqual({})
				-- on to 0.5 s
				while handle:GetTime() < 0.5 - EPS do
					frames(1)
				end
				expect(activationIds(log, true)).toEqual({ "flash", "wave", "sparks", "rocks", "glow", "smoke" })
				for _, id in { "flash", "wave", "sparks", "rocks", "glow" } do
					expect(firstFrameAt(activationTime(log, id, true), 0.1, DT)).toBe(true)
				end
				expect(firstFrameAt(activationTime(log, "smoke", true), 0.15, DT)).toBe(true)
				-- the burst on activation + the "emit" event at 0.2 s
				expect(H:emitsSince(mark, sparks)).toEqual({ 40, 20 })
				expect(H:emitsSince(mark, smoke)).toEqual({})
				expect(smoke.Enabled).toBe(true)
				expect(smoke.Rate < 30 and smoke.Rate > 0).toBe(true) -- rate track 30 -> 0
				-- Scale 1.5: lengths scale (range 30 -> 45, emitter volume 3 x 1 x 3 -> 4.5 x 1.5 x 4.5)
				expect(light.Range).toBeCloseTo(45, 1e-4)
				expect(smoke.Parent.Size).toBeCloseTo(Vector3.new(4.5, 1.5, 4.5), 1e-4)
				expect(handle._player.built.root.CFrame).toBeCloseTo(origin, 1e-4)
				-- the Impact marker reached handle.Event and OnEvent once, in its frame
				expect(eventNames(log)).toEqual({ "Impact" })
				expect(onEvents).toEqual({ "Impact" })
				expect(firstFrameAt(log.events[1].time, 0.1, DT)).toBe(true)

				local remaining = runToEnd(handle, 400)
				-- 2 s + tail (smoke lifetime 1.2 s, real seconds)
				expect(handle._player.time >= 2).toBe(true)
				expect(remaining > 0).toBe(true)
				expect(reasons).toEqual({ "finished" })
				expect(activationIds(log, false)).toEqual({ "sparks", "flash", "glow", "wave", "smoke", "rocks" })
				local ends: { [string]: number } =
					{ sparks = 0.4, flash = 0.5, glow = 0.7, wave = 0.9, smoke = 1.35, rocks = 1.6 }
				for id, at in ends do
					expect(firstFrameAt(activationTime(log, id, false), at, DT)).toBe(true)
				end
				expect(H:emitsSince(mark, sparks)).toEqual({ 40, 20 })
				expect(eventNames(log)).toEqual({ "Impact" })
				expect(handle:GetState()).toBe("finished")
				expect(handle:IsPlaying()).toBe(false)
				-- the copy went back to the pool (reset, unparented), nothing else is left
				expect(container.Parent).toBeNil()
				expect(Pool.count()).toBe(1)
				expect(handle.Finished:count()).toBe(0)
				expect(handle.Event:count()).toBe(0)
				expectClean(parent)
				expectNoWarnings()
				-- after the reset nothing survives: the pooled copy is destroyed too
				local built = handle._player.built
				AstraVFX._reset()
				expect(Pool.count()).toBe(0)
				expect(built.destroyed).toBe(true)
			end
		)

		T.itIf(isLune, "lightning: graph Loop / Delay emits and events land on their exact frames", function()
			AstraVFX.Register(LIGHTNING_JSON)
			local parent = H:folder("E2ELightning", workspace)
			local handle = AstraVFX.Play("E2E Lightning Strike", { Parent = parent, Quality = "High" })
			local log = instrument(handle)
			local zaps = emitterOf(handle, "zaps")
			local mark = H:emitMark()
			local ring = handle._player.built.controllers.ring.instances[1]
			local ringSizes: { number } = {}
			local boltShapes: { [string]: boolean } = {}
			local bolt = handle._player.built.controllers.bolt
			frames(1)
			while alive(handle) do
				frames(1)
				local t = handle:GetTime()
				if t > 0.2 and t < 0.9 then
					table.insert(ringSizes, ring.Size.X)
				end
				if t > 0.2 and t < 0.7 then
					boltShapes[tostring(bolt.instances[#bolt.instances].CFrame.Position)] = true
				end
			end
			-- graph emits at 0.2 / 0.3 / 0.4 / 0.5 (loop body) and 0.8 (after Delay), each in its own frame
			local emits = {}
			for _, entry in log.actions do
				if entry.action.action == "emit" then
					table.insert(emits, entry)
				end
			end
			expect(#emits).toBe(5)
			for i, at in { 0.2, 0.3, 0.4, 0.5, 0.8 } do
				expect(emits[i].action.source).toBe("graph")
				expect(firstFrameAt(emits[i].time, at, DT)).toBe(true)
			end
			expect(H:emitsSince(mark, zaps)).toEqual({ 12, 12, 12, 12, 30 })
			-- marker event first, graph FireEvent after the last emit
			expect(eventNames(log)).toEqual({ "Impact", "Aftershock" })
			expect(firstFrameAt(log.events[1].time, 0.2, DT)).toBe(true)
			expect(firstFrameAt(log.events[2].time, 0.8, DT)).toBe(true)
			-- the authored regenerate event ran at 0.45 s
			local regenerated = false
			for _, entry in log.actions do
				if entry.action.action == "regenerate" then
					regenerated = firstFrameAt(entry.time, 0.45, DT)
				end
			end
			expect(regenerated).toBe(true)
			-- ring radius track grows the ring; the bolt flickers (30 Hz) through several shapes
			expect(ringSizes[#ringSizes] > ringSizes[1]).toBe(true)
			local shapes = 0
			for _ in boltShapes do
				shapes += 1
			end
			expect(shapes > 5).toBe(true)
			expect(activationIds(log, true)).toEqual({ "zaps", "bolt", "flash", "ring" })
			expectClean(parent)
			expectNoWarnings()
		end)

		T.itIf(isLune, "aura: loops with a spinning group, the trail orbits, Stop ends it gracefully", function()
			AstraVFX.Register(AURA_JSON)
			local parent = H:folder("E2EAura", workspace)
			local handle =
				AstraVFX.Play("E2E Aura", { Parent = parent, Position = Vector3.new(0, 5, 0), Quality = "High" })
			local log = instrument(handle)
			local motes = emitterOf(handle, "motes")
			local trailController = handle._player.built.controllers.orbitTrail
			local a0 = trailController.instances[2]
			local mark = H:emitMark()
			local clearsBefore = #ctx.fakes.clears
			frames(1)
			local angles: { number } = {}
			for _ = 1, 200 do -- 3.33 s
				frames(1)
				local p = a0.CFrame.Position - Vector3.new(0, 2, 0)
				expect(Vector2.new(p.X, p.Z).Magnitude).toBeCloseTo(3, 1e-3) -- orbit radius 3 around the pivot
				table.insert(angles, math.atan2(p.Z, p.X))
			end
			expect(handle._player.cycle).toBe(3)
			expect(eventNames(log)).toEqual({ "Pulse", "Pulse", "Pulse" })
			for i, e in log.events do
				expect(firstFrameAt(e.time, 0.5, DT)).toBe(true)
				expect(i > 0).toBe(true)
			end
			-- motes burst 5 on activation, once per cycle (cycles 0..3)
			expect(H:emitsSince(mark, motes)).toEqual({ 5, 5, 5, 5 })
			-- clearOnStart = false: the trail is never cleared, also not on the loop wraps
			for i = clearsBefore + 1, #ctx.fakes.clears do
				expect(ctx.fakes.clears[i] ~= trailController.instances[1]).toBe(true)
			end
			-- the orbit moves every frame (360°/s ≈ 6° per frame)
			local moved = 0
			for i = 2, #angles do
				if math.abs(angles[i] - angles[i - 1]) > 0.05 then
					moved += 1
				end
			end
			expect(moved >= #angles - 5).toBe(true)
			-- every component re-activates each cycle in topological order
			local firstCycle = {}
			for _, a in log.activations do
				if a.active and a.cycle == 1 then
					table.insert(firstCycle, a.id)
				end
			end
			expect(firstCycle).toEqual({ "pivot", "orbitTrail", "motes", "core" })
			local reasons: { string } = {}
			handle.Finished:Connect(function(reason: string)
				table.insert(reasons, reason)
			end)
			handle:Stop()
			expect(handle:GetState()).toBe("stopping")
			expect(handle:IsPlaying()).toBe(false)
			expect(motes.Enabled).toBe(false) -- released: no new particles
			local lingered = runToEnd(handle, 200)
			-- default fade = tail = max(particle lifetime 1, trail lifetime 0.3) = 1 s of real time
			expect(lingered >= 59 and lingered <= 62).toBe(true)
			expect(reasons).toEqual({ "finished" })
			expect(Pool.count()).toBe(1)
			expectClean(parent)
			expectNoWarnings()
		end)

		T.itIf(
			isLune,
			"procedural state is a pure function of the seed (two runs, same seed; other seed differs)",
			function()
				AstraVFX.Register(EXPLOSION_JSON)
				AstraVFX.Register(LIGHTNING_JSON)
				local parent = H:folder("E2ESeed", workspace)
				local CHECK = { 10, 20, 35, 50, 70 }
				local function record(name: string, seed: number): { any }
					local handle = AstraVFX.Play(name, { Parent = parent, Seed = seed, CFrame = CFrame.new(1, 2, 3) })
					local container = handle._player.built.container
					local snapshots = {}
					local frame = 0
					while alive(handle) and frame < CHECK[#CHECK] do
						frames(1)
						frame += 1
						if table.find(CHECK, frame) then
							table.insert(snapshots, H:snapshot(container))
						end
					end
					handle:Destroy()
					return snapshots
				end
				for _, name in { "e2eExplosion", "e2eLightning" } do
					local a = record(name, 4242)
					local b = record(name, 4242) -- second run reuses the pooled copy
					expect(#a).toBe(#CHECK)
					expect(a).toEqual(b)
					local other = record(name, 4243)
					local same = true
					for i = 1, #CHECK do
						local ok = pcall(function()
							expect(other[i]).toEqual(a[i])
						end)
						same = same and ok
					end
					expect(same).toBe(false)
				end
				-- the compiled schedule (graph unrolling included) is identical as well
				local def = decode(LIGHTNING_JSON)
				local c1 = Compiler.compile(def, { seed = 4242 })
				local c2 = Compiler.compile(decode(LIGHTNING_JSON), { seed = 4242 })
				expect(#c1.schedule).toBe(#c2.schedule)
				for i, action in c1.schedule do
					expect(action.time).toBe(c2.schedule[i].time)
					expect(action.action).toBe(c2.schedule[i].action)
					expect(action.count).toBe(c2.schedule[i].count)
				end
				expectNoWarnings()
			end
		)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Part 2: adversarial review
	-- ─────────────────────────────────────────────────────────────────────────

	-- Compiles + builds + creates a Player outside the API (exact control over every step).
	local function rawPlayer(def: any, compileOptions: any?, playerOptions: any?): any
		return H:player(def, compileOptions or { quality = "High" }, playerOptions)
	end

	T.describe("EndToEnd loop boundaries", function()
		local function lateBurst(loop: boolean): any
			return {
				schemaVersion = 1,
				id = "lateBurst",
				name = "Late Burst",
				duration = 1,
				loop = loop,
				components = R({
					id = "late",
					name = "Late",
					type = "particles",
					startTime = 0.97,
					duration = 0.03,
					properties = { rate = 0, burst = 10, lifetime = { 0.2, 0.2 } },
				}),
			}
		end

		T.itIf(
			isLune,
			"a span inside the frame that crosses the loop end still activates (its burst is not lost)",
			function()
				-- dt = 0.06: the frame from 0.96 to 1.02 contains the whole span [0.97, 1.0) of every cycle
				local results = {}
				for _, loop in { false, true } do
					local p = rawPlayer(lateBurst(loop))
					local emitter = p.built.controllers.late.instances[1]
					local mark = H:emitMark()
					p.player:start()
					H:steps(p.player, 17, 0.06) -- 1.02 s: through the end of cycle 0
					results[loop] = #H:emitsSince(mark, emitter)
					if loop then
						H:steps(p.player, 17, 0.06) -- 2.04 s: through the end of cycle 1
						expect(p.player.cycle).toBe(2)
						expect(H:emitsSince(mark, emitter)).toEqual({ 10, 10 })
					end
				end
				expect(results[false]).toBe(1)
				expect(results[true]).toBe(1)
				expectNoWarnings()
			end
		)

		T.itIf(isLune, "the frame that crosses the loop end sends each part at most once to BulkMoveTo", function()
			local def = decode(AURA_JSON)
			local p = rawPlayer(def)
			local calls: { { any } } = {}
			local workspaceService: any = workspace
			local original = workspaceService.BulkMoveTo
			p.player.start(p.player)
			p.player._worldRoot = function()
				return {
					BulkMoveTo = function(_self: any, parts: { any }, cframes: { any }, mode: any)
						table.insert(calls, table.clone(parts))
						original(workspaceService, parts, cframes, mode)
					end,
				}
			end
			H:steps(p.player, 130, 1 / 60) -- through two wraps
			expect(p.player.cycle).toBe(2)
			for _, parts in calls do
				local seen = {}
				for _, part in parts do
					expect(seen[part]).toBeNil()
					seen[part] = true
				end
			end
			expectNoWarnings()
		end)

		T.itIf(isLune, "every scheduled action runs exactly once per cycle for any frame length", function()
			local def = {
				schemaVersion = 1,
				id = "everyCycle",
				name = "Every Cycle",
				duration = 1,
				loop = true,
				markers = R(
					{ id = "start", time = 0, label = "Start", event = "Start" },
					{ id = "mid", time = 0.5, label = "Mid", event = "Mid" },
					{ id = "last", time = 1, label = "Last", event = "Last" }
				),
				components = R({
					id = "p",
					name = "P",
					type = "particles",
					properties = { rate = 0, lifetime = { 0.1, 0.1 } },
					events = R(
						{ id = "e0", time = 0, action = "emit", count = 1 },
						{ id = "e1", time = 0.25, action = "emit", count = 2 },
						{ id = "e2", time = 0.999, action = "emit", count = 3 }
					),
				}),
				graph = {
					nodes = R(
						{ id = "play", type = "OnPlay" },
						{ id = "branch", type = "RandomBranch", params = { count = 2 } },
						{ id = "a", type = "Emit", params = { target = "p", count = 4 } },
						{ id = "b", type = "Emit", params = { target = "p", count = 5 } }
					),
					links = R(
						{ from = "play.out", to = "branch.in" },
						{ from = "branch.out1", to = "a.in" },
						{ from = "branch.out2", to = "b.in" }
					),
				},
			}
			local rng = Random.new(31)
			local cases: { any } = {
				{
					name = "1/60",
					next = function(): number
						return 1 / 60
					end,
				},
				{
					name = "0.1 (clamp)",
					next = function(): number
						return 0.1
					end,
				},
				{
					name = "0.037",
					next = function(): number
						return 0.037
					end,
				},
				{
					name = "random",
					next = function(): number
						return rng:range(0.001, 0.1)
					end,
				},
				{
					name = "0.1 × timeScale 10 (a whole cycle per frame)",
					timeScale = 10,
					next = function(): number
						return 0.1
					end,
				},
				{
					name = "1/60 × timeScale 7.3",
					timeScale = 7.3,
					next = function(): number
						return 1 / 60
					end,
				},
			}
			for _, case in cases do
				local p = rawPlayer(def)
				if case.timeScale then
					p.player:setTimeScale(case.timeScale)
				end
				local seen: { [string]: number } = {}
				p.player.actionExecuted:Connect(function(action: any)
					local key = p.player.cycle .. ":" .. tostring(action.sourceId) .. ":" .. action.action
					seen[key] = (seen[key] or 0) + 1
				end)
				p.player:start()
				local total = 0
				while total < 7.5 do
					local dt = case.next()
					total += dt
					p.player:step(dt)
				end
				local cycles = p.player.cycle -- cycles 0 .. cycles - 1 are complete
				expect(cycles >= 7).toBe(true)
				for cycle = 0, cycles - 1 do
					local schedule = Compiler.scheduleForCycle(p.compiled, cycle)
					expect(#schedule).toBe(7) -- 3 events + 3 markers + 1 graph emit
					for _, action in schedule do
						local key = cycle .. ":" .. tostring(action.sourceId) .. ":" .. action.action
						if seen[key] ~= 1 then
							T.fail(case.name .. ": " .. key .. " ran " .. tostring(seen[key] or 0) .. " times")
						end
					end
				end
			end
			expectNoWarnings()
		end)

		T.itIf(isLune, "toggling setLoop around the end does not shorten the next tail", function()
			local def = decode(AURA_JSON) -- tail 1 s (particle lifetime)
			def.loop = false
			local p = rawPlayer(def)
			p.player:start()
			H:steps(p.player, 60, 1 / 60) -- t = 1.0: the tail starts
			H:steps(p.player, 30, 1 / 60) -- 0.5 s of the 1 s tail
			expect(p.player.state).toBe("playing")
			p.player:setLoop(true)
			H:steps(p.player, 30, 1 / 60) -- a new cycle
			expect(p.player.cycle >= 1).toBe(true)
			p.player:setLoop(false)
			local rest = (1 - p.player.time) * 60 -- frames to the end of this cycle
			local frames2 = 0
			while p.player:step(1 / 60) do
				frames2 += 1
				assert(frames2 < 1000, "never finished")
			end
			-- the rest of the cycle + the full 1 s tail (60 frames), not the 0.5 s left over from the first end
			expect(frames2).toBeGreaterThanOrEqual(math.floor(rest) + 58)
			expect(frames2).toBeLessThanOrEqual(math.ceil(rest) + 62)
			expectNoWarnings()
		end)
	end)

	T.describe("EndToEnd time scale and seeking", function()
		local function metronome(): any
			local events = {}
			for i = 0, 19 do
				table.insert(events, { id = "e" .. i, time = i * 0.05, action = "emit", count = i + 1 })
			end
			return {
				schemaVersion = 1,
				id = "metronome",
				name = "Metronome",
				duration = 1,
				components = R({
					id = "p",
					name = "P",
					type = "particles",
					properties = { rate = 0, lifetime = { 0.1, 0.1 } },
					events = events,
				}),
			}
		end

		T.itIf(isLune, "time-scale changes mid-play never skip or double an action", function()
			local p = rawPlayer(metronome())
			local executed: { any } = {}
			p.player.actionExecuted:Connect(function(action: any)
				table.insert(executed, { count = action.count, at = action.time, now = p.player.time })
			end)
			p.player:start()
			local scales = { 0.3, 2.5, 0, 1, 10, 0.05, 4 }
			local frame = 0
			while p.player:step(1 / 60) do
				frame += 1
				if frame % 7 == 0 then
					p.player:setTimeScale(scales[(frame // 7 - 1) % #scales + 1])
				end
				assert(frame < 5000, "never finished")
			end
			expect(#executed).toBe(20)
			for i, e in executed do
				expect(e.count).toBe(i)
				expect(e.now >= e.at - EPS).toBe(true)
			end
			expectNoWarnings()
		end)

		T.itIf(isLune, "seek mid-play, then resume: the remaining actions run exactly once", function()
			AstraVFX.Register(LIGHTNING_JSON)
			local parent = H:folder("E2ESeek", workspace)
			local handle = AstraVFX.Play("e2eLightning", { Parent = parent, Quality = "High" })
			local log = instrument(handle)
			local zaps = emitterOf(handle, "zaps")
			frames(1)
			while handle:GetTime() < 0.33 do
				frames(1)
			end
			local mark = H:emitMark()
			expect(countEmits(log, "zaps")).toEqual({ 12, 12 }) -- 0.2 and 0.3
			handle:Seek(0.4) -- exactly on the 0.4 emit: it runs with the next step, once
			expect(H:emitsSince(mark)).toEqual({}) -- seeking never emits
			frames(1)
			expect(H:emitsSince(mark, zaps)).toEqual({ 12 })
			runToEnd(handle, 200)
			expect(H:emitsSince(mark, zaps)).toEqual({ 12, 12, 30 }) -- 0.4, 0.5, 0.8
			expect(eventNames(log)).toEqual({ "Impact", "Aftershock" })
			expectNoWarnings()
		end)

		T.itIf(isLune, "seek backwards replays nothing; playing on repeats the actions after the seek time", function()
			AstraVFX.Register(LIGHTNING_JSON)
			local parent = H:folder("E2ESeekBack", workspace)
			local handle = AstraVFX.Play("e2eLightning", { Parent = parent, Quality = "High" })
			local log = instrument(handle)
			local zaps = emitterOf(handle, "zaps")
			frames(1)
			while handle:GetTime() < 0.9 do
				frames(1)
			end
			expect(countEmits(log, "zaps")).toEqual({ 12, 12, 12, 12, 30 })
			local mark = H:emitMark()
			handle:Seek(0.25)
			-- the ring is evaluated at 0.25 s right away (radius track), the bolt is active again
			expect(handle._player._byId.bolt.active).toBe(true)
			expect(handle._player._byId.zaps.active).toBe(true)
			runToEnd(handle, 200)
			expect(H:emitsSince(mark, zaps)).toEqual({ 12, 12, 12, 30 }) -- 0.3, 0.4, 0.5, 0.8
			expectNoWarnings()
		end)

		T.itIf(isLune, "seek(t) reproduces the visible state that playing to t reached", function()
			-- Allowed differences: ParticleEmitter.Enabled (seeking pauses continuous emission until the next playback
			-- frame) and property values of components that are not active at t (invisible either way: seek resets
			-- them to the built state, playback leaves their last values).
			local function close(a: any, b: any): boolean
				local kind = typeof(a)
				if kind == "number" then
					return math.abs(a - b) < 1e-3
				elseif kind == "CFrame" then
					-- component-wise: Lune stores rotations rounded, so the axes are not exactly unit vectors
					return (a.Position - b.Position).Magnitude < 1e-3
						and (a.LookVector - b.LookVector).Magnitude < 1e-4
						and (a.UpVector - b.UpVector).Magnitude < 1e-4
				elseif kind == "Vector3" then
					return (a - b).Magnitude < 1e-3
				elseif kind == "Color3" then
					return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 1e-3
				end
				return a == b
			end
			local VISIBILITY: { [string]: boolean } = { Transparency = true, Enabled = true }
			for _, text in { EXPLOSION_JSON, LIGHTNING_JSON, AURA_JSON } do
				local def = decode(text)
				for _, frameCount in { 9, 20, 33, 47, 61, 80 } do
					local p = rawPlayer(def)
					p.player:start()
					H:steps(p.player, frameCount, DT)
					local t = p.player.time
					local activeIds: { [string]: boolean } = {}
					for id, plan in p.player._byId do
						activeIds[id] = plan.active
					end
					local owner: { [string]: string } = {}
					for i, inst in p.built.container:GetDescendants() do
						owner[i .. ":" .. inst.ClassName .. ":" .. inst.Name] = inst:GetAttribute("AstraComponent")
							or ""
					end
					local played = H:snapshot(p.built.container)
					p.player:seek(t)
					local seeked = H:snapshot(p.built.container)
					for key, props in played do
						local active = activeIds[owner[key]] == true
						for prop, value in props do
							local emitterFlag = prop == "Enabled"
								and string.find(key, ":ParticleEmitter:", 1, true) ~= nil
							if
								not emitterFlag
								and (active or VISIBILITY[prop])
								and not close(value, seeked[key][prop])
							then
								T.fail(
									string.format(
										"%s t=%.3f %s.%s: played %s, seek %s",
										def.id,
										t,
										key,
										prop,
										tostring(value),
										tostring(seeked[key][prop])
									)
								)
							end
						end
					end
					p.player:destroy()
				end
			end
			expectNoWarnings()
		end)

		T.itIf(
			isLune,
			"Pause / Seek / Resume with Autoplay = false and SetTimeScale(0) keep the clock consistent",
			function()
				AstraVFX.Register(EXPLOSION_JSON)
				local parent = H:folder("E2EPaused", workspace)
				local handle = AstraVFX.Play("e2eExplosion", { Parent = parent, Autoplay = false })
				local log = instrument(handle)
				frames(10)
				expect(handle:GetState()).toBe("paused")
				expect(handle:GetTime()).toBe(0)
				expect(log.activations).toEqual({})
				handle:Seek(0.3)
				expect(handle:GetState()).toBe("paused")
				for _, a in log.activations do
					expect(a.seeking).toBe(true)
				end
				frames(10)
				expect(handle:GetTime()).toBe(0.3)
				handle:Resume()
				handle:SetTimeScale(0)
				frames(10)
				expect(handle:GetTime()).toBe(0.3)
				handle:SetTimeScale(2)
				frames(6)
				expect(handle:GetTime()).toBeCloseTo(0.5, 1e-9)
				-- the 0.2 s emit was before the seek time: never executed; the burst at 0.1 s neither
				expect(countEmits(log, "sparks")).toEqual({})
				handle:Destroy()
				expectClean(parent)
				expectNoWarnings()
			end
		)
	end)

	T.describe("EndToEnd attach targets", function()
		T.itIf(isLune, "follows a moving target and keeps the last CFrame once the target is destroyed", function()
			AstraVFX.Register(LIGHTNING_JSON)
			local parent = H:folder("E2EAttach", workspace)
			local target = Instance.new("Part")
			target.Anchored = true
			target.CFrame = CFrame.new(0, 3, 0)
			target.Parent = workspace
			table.insert(H.created, target)
			local offset = CFrame.new(0, 1, 0)
			local handle = AstraVFX.Play("e2eLightning", { Parent = parent, Attach = target, Offset = offset })
			local root = handle._player.built.root
			frames(1)
			for i = 1, 20 do
				target.CFrame = CFrame.new(i, 3, 0)
				frames(1)
				expect(root.CFrame).toBeCloseTo(CFrame.new(i, 4, 0), 1e-4)
			end
			target:Destroy()
			frames(5)
			expect(root.CFrame).toBeCloseTo(CFrame.new(20, 4, 0), 1e-4)
			runToEnd(handle, 200)
			expect(handle:GetState()).toBe("finished")
			expectClean(parent)
			expectNoWarnings()
		end)

		T.itIf(isLune, "a target removed from the world (streamed out) keeps the effect at its last CFrame", function()
			AstraVFX.Register(EXPLOSION_JSON)
			local model = Instance.new("Model")
			local target = Instance.new("Part")
			target.Anchored = true
			target.CFrame = CFrame.new(7, 1, 0)
			target.Parent = model
			model.Parent = workspace
			table.insert(H.created, model)
			-- the container lives under the target's model (discouraged, but possible)
			local handle = AstraVFX.Play("e2eExplosion", { Parent = model, Attach = target })
			local root = handle._player.built.root
			frames(20)
			model.Parent = nil -- streamed out / removed: the container goes with it
			target.CFrame = CFrame.new(100, 0, 0)
			frames(5)
			expect(root.CFrame).toBeCloseTo(CFrame.new(7, 1, 0), 1e-4)
			runToEnd(handle, 400)
			expect(handle:GetState()).toBe("finished")
			expectClean(nil)
			expectNoWarnings()
		end)

		T.itIf(isLune, "a container removed from the outside is destroyed at the end, never pooled", function()
			AstraVFX.Register(EXPLOSION_JSON)
			local parent = H:folder("E2ERemoved", workspace)
			local handle = AstraVFX.Play("e2eExplosion", { Parent = parent })
			local built = handle._player.built
			frames(20)
			-- e.g. game code cleared the folder, or the parent was destroyed (Roblox then locks Parent, so the pool
			-- could not reset / re-parent the copy anyway)
			built.container.Parent = nil
			runToEnd(handle, 400)
			expect(handle:GetState()).toBe("finished")
			expect(built.destroyed).toBe(true)
			expect(Pool.count()).toBe(0)
			expectClean(parent)
			expectNoWarnings()
		end)

		T.itIf(isLune, "an Attachment and a Model target are followed too", function()
			AstraVFX.Register(AURA_JSON)
			local parent = H:folder("E2EAttachKinds", workspace)
			local model = Instance.new("Model")
			local body = Instance.new("Part")
			body.Anchored = true
			body.CFrame = CFrame.new(5, 0, 0)
			body.Parent = model
			model.PrimaryPart = body
			local attachment = Instance.new("Attachment")
			attachment.CFrame = CFrame.new(0, 2, 0)
			attachment.Parent = body
			model.Parent = workspace
			table.insert(H.created, model)
			local onModel = AstraVFX.Play("e2eAura", { Parent = parent, Attach = model })
			local onAttachment = AstraVFX.Play("e2eAura", { Parent = parent, Attach = attachment })
			frames(3)
			expect(onModel._player.built.root.CFrame).toBeCloseTo(CFrame.new(5, 0, 0), 1e-4)
			expect(onAttachment._player.built.root.CFrame).toBeCloseTo(CFrame.new(5, 2, 0), 1e-4)
			body.CFrame = CFrame.new(-5, 0, 0)
			frames(1)
			expect(onModel._player.built.root.CFrame).toBeCloseTo(CFrame.new(-5, 0, 0), 1e-4)
			expect(onAttachment._player.built.root.CFrame).toBeCloseTo(CFrame.new(-5, 2, 0), 1e-4)
			AstraVFX.StopAll(true)
			expectClean(parent)
			expectNoWarnings()
		end)
	end)

	T.describe("EndToEnd variants", function()
		T.itIf(
			isLune,
			"every palette × quality × scale combination plays to the end with the expected values",
			function()
				AstraVFX.Register(EXPLOSION_JSON)
				local parent = H:folder("E2EVariants", workspace)
				local profiles = {
					Low = { countScale = 0.35, maxLights = 2 },
					Medium = { countScale = 0.65, maxLights = 4 },
					High = { countScale = 1, maxLights = math.huge },
				}
				local blue = Color3.fromRGB(40, 120, 255)
				local variants = 0
				for _, quality in Constants.QUALITY_LEVELS do
					for _, scale in { 0.5, 1, 2.5, 10 } do
						for _, palette in R(nil, { hot = blue }) do
							variants += 1
							local handle = AstraVFX.Play("e2eExplosion", {
								Parent = parent,
								Quality = quality,
								Scale = scale,
								Palette = palette,
							})
							local log = instrument(handle)
							local controllers = handle._player.built.controllers
							local countScale = profiles[quality].countScale
							local function scaled(n: number): number
								return math.max(1, math.floor(n * countScale + 0.5))
							end
							-- counts follow the quality profile, lengths the scale (light range capped at 120)
							expect(#controllers.rocks.instances).toBe(scaled(16))
							expect(controllers.glow.instances[1].Range).toBeCloseTo(math.min(30 * scale, 120), 1e-4)
							local flashBall = controllers.flash.instances[1]
							runToEnd(handle, 600)
							local expectedHot = if palette then blue else Color3.fromRGB(255, 244, 200)
							expect(flashBall.Color).toBeCloseTo(expectedHot, 1e-3)
							expect(countEmits(log, "sparks")).toEqual({ scaled(20) })
							expect(eventNames(log)).toEqual({ "Impact" })
						end
					end
				end
				-- one compiled variant per combination, palettes included
				expect(AstraVFX._cacheSize()).toBe(variants)
				expectClean(parent)
				expectNoWarnings()
			end
		)

		T.itIf(
			isLune,
			"graph SetProperty / Tween on a particle rate follow the quality profile like a rate track",
			function()
				local def = {
					schemaVersion = 1,
					id = "rateQuality",
					name = "Rate Quality",
					duration = 1,
					components = R(
						{
							id = "tracked",
							name = "Tracked",
							type = "particles",
							properties = { rate = 0 },
							tracks = R({ id = "r", channel = "rate", keyframes = R({ time = 0, value = 100 }) }),
						},
						{ id = "graphSet", name = "Graph Set", type = "particles", properties = { rate = 0 } },
						{ id = "graphTween", name = "Graph Tween", type = "particles", properties = { rate = 0 } }
					),
					graph = {
						nodes = R(
							{ id = "play", type = "OnPlay" },
							{ id = "split", type = "Parallel", params = { count = 2 } },
							{
								id = "set",
								type = "SetProperty",
								params = { target = "graphSet", channel = "rate", value = 100 },
							},
							{
								id = "tween",
								type = "Tween",
								params = { target = "graphTween", channel = "rate", value = 100, duration = 0 },
							}
						),
						links = R(
							{ from = "play.out", to = "split.in" },
							{ from = "split.out1", to = "set.in" },
							{ from = "split.out2", to = "tween.in" }
						),
					},
				}
				local expected: { [string]: number } = { Low = 35, Medium = 65, High = 100 }
				for _, level in Constants.QUALITY_LEVELS do
					local p = rawPlayer(def, { quality = level })
					p.player:start()
					H:steps(p.player, 3, DT)
					for _, id in { "tracked", "graphSet", "graphTween" } do
						local rate = p.built.controllers[id].instances[1].Rate
						if math.abs(rate - expected[level]) > 1e-6 then
							T.fail(level .. " " .. id .. ": Rate " .. rate .. ", expected " .. expected[level])
						end
					end
					p.player:destroy()
				end
				expectNoWarnings()
			end
		)

		T.it(
			"Beam.Segments is never quality-scaled (constraints K14, ARCHITECTURE §5.4, COMPONENTS_SPEC §3)",
			function()
				-- the engine already lowers beam segments at low graphics quality; ring / lightning / shockwave
				-- subdivisions are the procedural segments the profile scales
				local def = {
					schemaVersion = 1,
					id = "beamSegments",
					name = "Beam Segments",
					duration = 1,
					components = R(
						{ id = "b", name = "B", type = "beam", properties = { segments = 20 } },
						{ id = "r", name = "R", type = "ring", properties = { segments = 32 } }
					),
				}
				expect(Validation.validate(def).ok).toBe(true)
				local expectedRing = { Low = 16, Medium = 24, High = 32 }
				for _, level in Constants.QUALITY_LEVELS do
					local compiled = Compiler.compile(def, { quality = level })
					expect(compiled.byId.b.props.segments).toBe(20)
					expect(compiled.byId.r.props.segments).toBe(expectedRing[level])
				end
			end
		)

		T.itIf(isLune, "Scale and Quality reach the graph: emit counts and channel values of graph actions", function()
			AstraVFX.Register(LIGHTNING_JSON)
			local parent = H:folder("E2EGraphVariants", workspace)
			local handle = AstraVFX.Play("e2eLightning", { Parent = parent, Quality = "Low", Scale = 2 })
			local log = instrument(handle)
			runToEnd(handle, 400)
			expect(countEmits(log, "zaps")).toEqual({ 4, 4, 4, 4, 11 }) -- round(12 × 0.35), round(30 × 0.35)
			expectNoWarnings()
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Fuzzed input: Register must reject exactly the invalid definitions, and whatever it accepts must play
	-- ─────────────────────────────────────────────────────────────────────────

	local NAN = 0 / 0
	local INF = math.huge

	local function deepCopy(v: any): any
		if type(v) ~= "table" or v == Json.NULL or v == Json.EMPTY_OBJECT then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function nastyValues(): { any }
		return {
			0,
			-1,
			1,
			0.5,
			-0.25,
			3,
			1e9,
			-1e9,
			2 ^ 60,
			INF,
			-INF,
			NAN,
			"",
			"x",
			"#ZZZZZZ",
			"#FFF",
			"#12345",
			"$missing",
			"$fire",
			"$bolt",
			"Linear",
			"Bogus.Out",
			"Quad.InOut",
			"rbxassetid://123",
			"core",
			"zaps",
			"sparks",
			"pivot",
			"particles",
			"group",
			true,
			false,
			{},
			{ 1 },
			{ 1, 2 },
			{ 1, 2, 3 },
			{ 0, 0, 0 },
			{ -5, 1e9, 0 },
			{ "a", "b" },
			{ { 0, 1 }, { 1, 0 } },
			R(R(0, "#FFFFFF"), R(1, "#000000")),
			{ { 0, 1 }, { 0.5, 2 } },
			{ x = 1 },
			string.rep("a", 120),
			Json.NULL,
			Json.EMPTY_OBJECT,
		}
	end

	type Slot = { parent: any, key: any, depth: number }

	local function collectSlots(root: any): { Slot }
		local slots: { Slot } = {}
		local function walk(t: any, depth: number)
			if depth > 8 then
				return
			end
			local keys = {}
			for k in t do
				table.insert(keys, k)
			end
			table.sort(keys, function(a: any, b: any): boolean
				return tostring(a) < tostring(b)
			end)
			for _, k in keys do
				table.insert(slots, { parent = t, key = k, depth = depth })
				local v = t[k]
				if type(v) == "table" and v ~= Json.NULL and v ~= Json.EMPTY_OBJECT then
					walk(v, depth + 1)
				end
			end
		end
		walk(root, 0)
		return slots
	end

	local function describeValue(v: any): string
		if type(v) == "table" then
			local ok, text = pcall(Json.encode, v, { pretty = false })
			return if ok then text else "<table>"
		end
		return tostring(v)
	end

	-- Applies one random mutation; returns a description.
	local function mutate(def: any, rng: any, nasty: { any }): string
		local slots = collectSlots(def)
		if #slots == 0 then
			return "no slots"
		end
		local slot = slots[rng:int(1, #slots)]
		local parent, key = slot.parent, slot.key
		local old = parent[key]
		local roll = rng:next()
		local path = tostring(key) .. "@" .. slot.depth
		if roll < 0.45 then
			local value = deepCopy(rng:pick(nasty))
			parent[key] = value
			return "set " .. path .. " = " .. describeValue(value)
		elseif roll < 0.6 then
			parent[key] = nil
			if type(key) == "number" and Json.isArray(parent) == false then
				-- keep arrays dense: shift the tail down
				local n = 0
				for k in parent do
					if type(k) == "number" and k > n then
						n = k
					end
				end
				for i = key, n do
					parent[i] = parent[i + 1]
				end
			end
			return "remove " .. path
		elseif roll < 0.78 and type(old) == "number" then
			local value = if rng:next() < 0.5 then old * rng:range(-3, 3) else old + rng:range(-2, 2)
			parent[key] = value
			return "perturb " .. path .. " -> " .. tostring(value)
		elseif roll < 0.9 and type(key) == "number" then
			-- duplicate an array element (duplicate ids, extra keyframes / components)
			table.insert(parent, deepCopy(old))
			return "duplicate " .. path
		else
			local value = deepCopy(rng:pick(nasty))
			if type(parent) == "table" then
				parent["extra" .. rng:int(1, 3)] = value
			end
			return "add field near " .. path .. " = " .. describeValue(value)
		end
	end

	local function exercise(name: string, seed: number, parent: Instance): string?
		for _, quality in { "Low", "High" } do
			local handle, err = AstraVFX.TryPlay(name, { Parent = parent, Quality = quality, Seed = seed })
			if handle == nil then
				return "accepted definition does not play (" .. quality .. "): " .. tostring(err)
			end
			for _ = 1, 10 do
				ctx.fakes:step(0.05)
			end
			handle:Fire("Detonate")
			handle:Seek((seed % 7) * 0.3)
			ctx.fakes:step(0.05)
			handle:SetTimeScale(2)
			ctx.fakes:step(0.05)
			handle:Stop()
			for _ = 1, 3 do
				ctx.fakes:step(0.05)
			end
			handle:Destroy()
		end
		return nil
	end

	T.describe("EndToEnd fuzzed definitions", function()
		T.itIf(
			isLune,
			"Register rejects exactly the invalid mutants; every accepted mutant compiles, builds and plays",
			function()
				local sources = { EXPLOSION_JSON, LIGHTNING_JSON, AURA_JSON, Fixtures.FULL_JSON }
				local rng = Random.new(20261028)
				local nasty = nastyValues()
				local parent = H:folder("E2EFuzz", workspace)
				local failures: { string } = {}
				local accepted, rejected = 0, 0
				local ITERATIONS = 240
				for i = 1, ITERATIONS do
					local def = decode(sources[(i - 1) % #sources + 1])
					local changes = {}
					for _ = 1, rng:int(1, 3) do
						table.insert(changes, mutate(def, rng, nasty))
					end
					local label = "#" .. i .. " [" .. table.concat(changes, "; ") .. "]"
					table.clear(warnings)
					local validOk, result = pcall(AstraVFX.Validate, def)
					if not validOk then
						table.insert(failures, label .. ": Validate threw: " .. tostring(result))
						continue
					end
					local ok, nameOrErr = pcall(AstraVFX.Register, def)
					if ok ~= result.ok then
						table.insert(
							failures,
							label
								.. ": Validate.ok = "
								.. tostring(result.ok)
								.. " but Register ok = "
								.. tostring(ok)
								.. (if ok then "" else " (" .. tostring(nameOrErr) .. ")")
						)
					elseif not ok then
						rejected += 1
						if not string.find(tostring(nameOrErr), "AstraVFX.Register:", 1, true) then
							table.insert(failures, label .. ": unreadable Register error: " .. tostring(nameOrErr))
						end
					else
						accepted += 1
						local _, migrated = AstraVFX.Validate(def)
						for _, level in Constants.QUALITY_LEVELS do
							local compiledOk, compiled, compilerWarnings =
								pcall(Compiler.compile, migrated, { quality = level })
							if not compiledOk then
								table.insert(
									failures,
									label .. ": compile " .. level .. " threw: " .. tostring(compiled)
								)
							else
								for _, d in compilerWarnings do
									if string.sub(d.code, 1, 9) == "compiler." then
										table.insert(
											failures,
											label .. ": compiler warning on a valid definition: " .. d.code
										)
									end
								end
							end
						end
						local problem = exercise(nameOrErr, i, parent)
						if problem then
							table.insert(failures, label .. ": " .. problem)
						end
						for _, w in warnings do
							if not string.find(w, "was cut off", 1, true) then
								table.insert(failures, label .. ": warning while playing: " .. w)
							end
						end
					end
					AstraVFX._reset()
					Scheduler.clear()
					if #failures >= 12 then
						break
					end
				end
				table.clear(warnings)
				if #failures > 0 then
					T.fail(#failures .. " fuzz failures:\n  " .. table.concat(failures, "\n  "))
				end
				-- the fuzzer must exercise both paths substantially
				expect(accepted > 40).toBe(true)
				expect(rejected > 40).toBe(true)
				expect(#parent:GetChildren()).toBe(0)
			end
		)

		T.it("a value that is not plain JSON in an unknown field makes the definition invalid (not a crash)", function()
			for _, place in { "property", "field", "param" } do
				local def = decode(LIGHTNING_JSON)
				if place == "property" then
					def.components[4].properties.extra = -INF
				elseif place == "field" then
					def.components[1].tracks[1].keyframes[1].note = NAN
				else
					def.graph.nodes[2].params.extra = NAN
				end
				local result = AstraVFX.Validate(def)
				expect(result.ok).toBe(false)
				expect(result.errors[1].code).toBe("effect.json")
				local ok, err = pcall(AstraVFX.Register, def)
				expect(ok).toBe(false)
				expect(tostring(err)).toContain("AstraVFX.Register:")
				expect(tostring(err)).toContain("effect.json")
				-- as a warning-only unknown field it is still accepted when its value is plain JSON
				if place == "property" then
					def.components[4].properties.extra = 5
				elseif place == "field" then
					def.components[1].tracks[1].keyframes[1].note = "x"
				else
					def.graph.nodes[2].params.extra = 1
				end
				expect(AstraVFX.Validate(def).ok).toBe(true)
			end
		end)

		T.it("Register rejects malformed sources with a readable summary and registers nothing", function()
			local cases: { any } = {
				R(nil, "expected a definition"),
				R(true, "expected a definition"),
				R("{", "migration.json"),
				R("[]", "AstraVFX.Register"),
				R({ schemaVersion = 99, id = "future", name = "Future", duration = 1, components = {} }, "schema"),
				R({ schemaVersion = 1, id = "bad id!", name = "X", duration = 1, components = {} }, "effect.id"),
				R({ schemaVersion = 1, id = "nan", name = "NaN", duration = NAN, components = {} }, "effect.duration"),
				R({ schemaVersion = 1, id = "inf", name = "Inf", duration = INF, components = {} }, "effect.duration"),
			}
			for _, case in cases do
				local ok, err = pcall(AstraVFX.Register, case[1])
				expect(ok).toBe(false)
				expect(tostring(err)).toContain(case[2])
			end
			-- a cyclic table is rejected, not followed forever
			local cyclic: any = { schemaVersion = 1, id = "cyc", name = "Cyc", duration = 1, components = {} }
			cyclic.metadata = { self = cyclic }
			expect(pcall(AstraVFX.Register, cyclic)).toBe(false)
			expect(AstraVFX.GetNames()).toEqual({})
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Lifecycle re-entrancy
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("EndToEnd lifecycle", function()
		T.itIf(isLune, "Destroy / Stop are idempotent and safe from inside every callback", function()
			AstraVFX.Register(EXPLOSION_JSON)
			AstraVFX.Register(LIGHTNING_JSON)
			local parent = H:folder("E2ELifecycle", workspace)
			-- destroyed from its own Impact event (handle.Event), twice
			local a = AstraVFX.Play("e2eExplosion", { Parent = parent })
			a.Event:Connect(function()
				a:Destroy()
				a:Destroy()
			end)
			-- stopped from OnEvent, then destroyed from Finished
			local b: any
			b = AstraVFX.Play("e2eLightning", {
				Parent = parent,
				OnEvent = function(name: string)
					if name == "Impact" then
						b:Stop(0.1)
						b:Stop()
					end
				end,
			})
			b.Finished:Connect(function()
				b:Destroy()
			end)
			-- StopAll(true) from an actionExecuted handler of a third effect, plays a fresh one from Finished
			local c = AstraVFX.Play("e2eLightning", { Parent = parent })
			local replay: any = nil
			c._player.actionExecuted:Connect(function(action: any)
				if action.action == "emit" and replay == nil then
					AstraVFX.StopAll(true)
				end
			end)
			c.Finished:Connect(function(reason: string)
				if reason == "destroyed" and replay == nil then
					replay = AstraVFX.Play("e2eExplosion", { Parent = parent })
				end
			end)
			frames(80)
			expect(a:GetState()).toBe("destroyed")
			expect(b:GetState()).toBe("destroyed")
			expect(c:GetState()).toBe("destroyed")
			expect(replay).never.toBeNil()
			runToEnd(replay, 400)
			for _, h in { a, b, c, replay } do
				h:Destroy()
				h:Stop()
				h:Pause()
				h:Resume()
				h:Seek(0.5)
				h:Fire("Detonate")
				expect(h:IsPlaying()).toBe(false)
			end
			expectClean(parent)
			expectNoWarnings()
		end)

		T.itIf(isLune, "Destroy from an end-of-cycle event of a looping, moving effect leaves no stale move", function()
			local def = decode(EXPLOSION_JSON)
			table.insert(def.markers, { id = "cycleEnd", time = 2, label = "Cycle end", event = "CycleEnd" })
			AstraVFX.Register(def)
			Pool.setCapacity(0) -- the copy is destroyed, not pooled
			local parent = H:folder("E2ECycleEnd", workspace)
			local target = Instance.new("Part")
			target.Anchored = true
			target.Parent = workspace
			table.insert(H.created, target)
			local handle: any
			handle = AstraVFX.Play("e2eExplosion", {
				Parent = parent,
				Attach = target,
				Loop = true,
				OnEvent = function(name: string)
					if name == "CycleEnd" then
						handle:Destroy()
					end
				end,
			})
			local built = handle._player.built
			local guard = 0
			while alive(handle) do
				guard += 1
				target.CFrame = CFrame.new(guard * 0.1, 0, 0) -- the root moves every frame
				ctx.fakes:step(DT)
				assert(guard < 300, "never destroyed")
			end
			expect(handle:GetState()).toBe("destroyed")
			expect(handle._player.time).toBe(2) -- destroyed in the frame that crossed the end of cycle 0
			expect(built.destroyed).toBe(true)
			expectClean(parent)
			expectNoWarnings()
		end)

		T.itIf(isLune, "Unregister / re-Register while an effect plays: it finishes, its copy is not pooled", function()
			AstraVFX.Register(EXPLOSION_JSON)
			local parent = H:folder("E2EUnregister", workspace)
			local handle = AstraVFX.Play("e2eExplosion", { Parent = parent })
			frames(30)
			expect(AstraVFX.Unregister("e2eExplosion")).toBe(true)
			local changed = decode(EXPLOSION_JSON)
			changed.components[1].properties.color = "#00FF00"
			AstraVFX.Register(changed)
			runToEnd(handle, 400)
			expect(Pool.count()).toBe(0) -- its cache entry was dropped: the copy was destroyed
			local again = AstraVFX.Play("e2eExplosion", { Parent = parent })
			expect(again._player.built.controllers.flash.instances[1].Color).toBeCloseTo(Color3.new(0, 1, 0), 1e-6)
			again:Destroy()
			expectClean(parent)
			expectNoWarnings()
		end)

		T.itIf(isLune, "randomized churn of every handle call leaves nothing behind", function()
			for _, text in { EXPLOSION_JSON, LIGHTNING_JSON, AURA_JSON } do
				AstraVFX.Register(text)
			end
			local parent = H:folder("E2EChurn", workspace)
			local workspaceChildren = #workspace:GetChildren()
			local rng = Random.new(777)
			local names = { "e2eExplosion", "e2eLightning", "e2eAura" }
			local handles: { any } = {}
			local finishedCount: { [any]: number } = {}
			for _ = 1, 700 do
				local r = rng:next()
				local h = if #handles > 0 then handles[rng:int(1, #handles)] else nil
				if r < 0.08 or h == nil then
					local handle = AstraVFX.Play(names[rng:int(1, 3)], {
						Parent = parent,
						Quality = Constants.QUALITY_LEVELS[rng:int(1, 3)],
						Loop = if rng:next() < 0.2 then true else nil,
						TimeScale = rng:range(0, 3),
						Position = Vector3.new(rng:range(-50, 50), 0, rng:range(-50, 50)),
					})
					finishedCount[handle] = 0
					handle.Finished:Connect(function()
						finishedCount[handle] += 1
					end)
					table.insert(handles, handle)
				elseif r < 0.13 then
					h:Stop(if rng:next() < 0.5 then rng:range(0, 0.5) else nil)
				elseif r < 0.17 then
					h:Destroy()
				elseif r < 0.22 then
					h:Pause()
				elseif r < 0.3 then
					h:Resume()
				elseif r < 0.36 then
					h:Seek(rng:range(-1, 3))
				elseif r < 0.4 then
					h:Fire("Detonate")
				elseif r < 0.44 then
					h:SetLoop(rng:next() < 0.5)
				elseif r < 0.48 then
					h:SetTimeScale(rng:range(0, 4))
				elseif r < 0.5 then
					h:SetCFrame(CFrame.new(rng:range(-9, 9), 0, 0))
				end
				ctx.fakes:step(rng:range(0, 0.12)) -- > 0.1 exercises the Scheduler clamp
				local living = 0
				for _, handle in handles do
					if alive(handle) then
						living += 1
					end
				end
				expect(AstraVFX.ActiveCount()).toBe(living)
				expect(Scheduler.count()).toBe(living)
				expect(Scheduler.isConnected()).toBe(living > 0)
			end
			AstraVFX.StopAll()
			for _, handle in handles do
				handle:Resume() -- paused + stopping still counts real seconds
				handle:SetTimeScale(1)
			end
			local guard = 0
			while AstraVFX.ActiveCount() > 0 do
				ctx.fakes:step(DT)
				guard += 1
				assert(guard < 2000, "handles never ended")
			end
			for _, handle in handles do
				expect(finishedCount[handle]).toBe(1)
				expect(handle._player.built.container.Parent == nil or handle._player.built.destroyed).toBe(true)
			end
			expect(Pool.count() <= 3 * 3 * Pool.DEFAULT_CAPACITY).toBe(true)
			expect(#workspace:GetChildren()).toBe(workspaceChildren)
			expectClean(parent)
			expectNoWarnings()
		end)

		T.itIf(isLune, "a yielding OnEvent / Event / Finished handler does not freeze the other effects", function()
			AstraVFX.Register(LIGHTNING_JSON)
			AstraVFX.Register(AURA_JSON)
			local parent = H:folder("E2EYield", workspace)
			-- Handlers yield only while a frame runs in its own coroutine (never the runner's main thread).
			local driving = false
			local yielded = 0
			local function maybeYield()
				if driving then
					yielded += 1
					coroutine.yield()
				end
			end
			local strike = AstraVFX.Play("e2eLightning", {
				Parent = parent,
				OnEvent = function(name: string)
					if name == "Impact" then
						maybeYield()
					end
				end,
			})
			strike.Event:Connect(function(name: string)
				if name == "Aftershock" then
					maybeYield()
				end
			end)
			strike.Finished:Connect(maybeYield)
			local aura = AstraVFX.Play("e2eAura", { Parent = parent })
			-- Like RunService, run every frame in its own thread: a handler that yields suspends that thread only.
			local function frame()
				local co = coroutine.create(function()
					ctx.fakes:step(DT)
				end)
				driving = true
				local ok, err = coroutine.resume(co)
				driving = false
				assert(ok, err)
				if coroutine.status(co) == "suspended" then
					table.insert(suspended, co)
				end
			end
			local auraTimes: { number } = {}
			for _ = 1, 200 do
				frame()
				table.insert(auraTimes, aura:GetTime())
			end
			expect(yielded).toBe(3)
			expect(strike:GetState()).toBe("finished")
			-- the aura kept running through every yield
			local frozen = 0
			for i = 3, #auraTimes do
				if auraTimes[i] == auraTimes[i - 1] then
					frozen += 1
				end
			end
			expect(frozen).toBe(0)
			aura:Destroy()
			expectClean(parent)
			expectNoWarnings()
		end)
	end)

	T.describe("EndToEnd component events", function()
		T.itIf(
			isLune,
			"a component 'fire' event reaches Event / OnEvent at its time (Validation accepts it on every type)",
			function()
				local def = decode(AURA_JSON)
				def.loop = false
				def.components[4].events = R(
					{ id = "glint", time = 0.25, action = "fire", name = "Glint" },
					{ id = "late", time = 0.75, action = "fire", name = "Glint2" }
				)
				local result = Validation.validate(def)
				expect(result.ok).toBe(true)
				expect(#result.warnings).toBe(0)
				AstraVFX.Register(def)
				local parent = H:folder("E2EFire", workspace)
				local received: { string } = {}
				local handle = AstraVFX.Play("e2eAura", {
					Parent = parent,
					OnEvent = function(name: string)
						table.insert(received, name)
					end,
				})
				local log = instrument(handle)
				runToEnd(handle, 300)
				expect(received).toEqual({ "Glint", "Pulse", "Glint2" })
				expect(eventNames(log)).toEqual({ "Glint", "Pulse", "Glint2" })
				expect(firstFrameAt(log.events[1].time, 0.25, DT)).toBe(true)
				expectClean(parent)
				expectNoWarnings()
			end
		)
	end)

	T.describe("EndToEnd network", function()
		T.itIf(
			isLune,
			"server PlayAll -> client listener plays the effect with clamped options and cleans up",
			function()
				local Net = AstraVFX.Net
				local Signal = use("AstraVFX.Core.Signal")
				-- A loopback remote: FireAllClients delivers to this machine's OnClientEvent (one simulated client).
				local function loopback(): any
					local remote: any = { OnClientEvent = Signal.new(), sent = 0 }
					function remote.FireAllClients(self: any, payload: any)
						self.sent += 1
						self.OnClientEvent:Fire(payload)
					end
					return remote
				end
				local reliable, unreliable = loopback(), loopback()
				Net._reset()
				Net._setRemotes(reliable, unreliable)
				AstraVFX.Register(LIGHTNING_JSON)
				local listener = Net.Listen()
				local target = Instance.new("Part")
				target.Anchored = true
				target.CFrame = CFrame.new(0, 0, 30)
				target.Parent = workspace
				table.insert(H.created, target)
				Net.PlayAll("E2E Lightning Strike", { Attach = target, Scale = 100, TimeScale = 50, Quality = "High" })
				Net.PlayAll("e2eLightning", { Position = Vector3.new(5, 0, 0), Unreliable = true })
				Net.PlayAll("NotRegistered", { Position = Vector3.zero })
				expect(reliable.sent).toBe(2)
				expect(unreliable.sent).toBe(1)
				expect(AstraVFX.ActiveCount()).toBe(2)
				expect(Net.stats).toEqual({ received = 3, played = 2, ignored = 1 })
				expect(AstraVFX._cacheSize()).toBe(2) -- two compile variants (Scale 20 and 1)
				-- client-side clamps. Scale 100 -> 20: the bolt (from = [0, 30, 0]) reaches 600 studs above the target.
				local attached: Instance? = nil
				for _, child in workspace:GetChildren() do
					local root = child:FindFirstChild("Root")
					if child.Name == "AstraVFX_E2E Lightning Strike" and root and root:IsA("BasePart") then
						if ((root :: BasePart).CFrame.Position - target.CFrame.Position).Magnitude < 1e-3 then
							attached = child
						end
					end
				end
				frames(4) -- the strike starts at 0.2 s effect time = 0.02 s real time with TimeScale 10
				expect(attached).never.toBeNil()
				local top = 0
				for _, d in (attached :: Instance):GetDescendants() do
					if d:IsA("Attachment") then
						top = math.max(top, (d :: Attachment).CFrame.Position.Y)
					end
				end
				expect(top > 550 and top < 650).toBe(true)
				-- TimeScale 50 -> 10: the scaled copy ends after 1.5 s / 10 + 0.3 s tail (real) ≈ 27 frames, the other
				-- after 1.5 s + 0.3 s ≈ 108 frames
				local frame = 4
				local firstEnd: number? = nil
				while AstraVFX.ActiveCount() > 0 do
					ctx.fakes:step(DT)
					frame += 1
					if firstEnd == nil and AstraVFX.ActiveCount() == 1 then
						firstEnd = frame
					end
					assert(frame < 600, "the replicated effects never ended")
				end
				expect(firstEnd ~= nil and firstEnd >= 26 and firstEnd <= 32).toBe(true)
				expect(frame >= 108 and frame <= 114).toBe(true)
				listener:Disconnect()
				Net._reset()
				expectClean(nil)
				expectNoWarnings()
			end
		)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- API surface (ARCHITECTURE §5.3, MODULE_CONTRACTS §15–§19)
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("EndToEnd API surface", function()
		T.it("exposes the documented names with the documented kinds", function()
			for _, name in
				{
					"Register",
					"Play",
					"TryPlay",
					"Preload",
					"SetQuality",
					"StopAll",
					"ActiveCount",
					"Validate",
					"Unregister",
					"IsRegistered",
					"GetNames",
				}
			do
				expect(type(AstraVFX[name])).toBe("function")
			end
			expect(AstraVFX.Version).toBe(Constants.VERSION)
			local Net = AstraVFX.Net
			for _, name in { "Init", "PlayAll", "PlayFor", "PlayNear", "Listen" } do
				expect(type(Net[name])).toBe("function")
			end
			for _, name in
				{
					"start",
					"step",
					"seek",
					"pause",
					"resume",
					"stop",
					"destroy",
					"setTimeScale",
					"setCFrame",
					"setLoop",
					"fire",
				}
			do
				expect(type(Player[name])).toBe("function")
			end
			for _, name in { "add", "remove", "count", "step", "setEventName" } do
				expect(type(Scheduler[name])).toBe("function")
			end
			for _, name in { "acquire", "release", "prewarm", "clear", "setCapacity" } do
				expect(type(Pool[name])).toBe("function")
			end
			expect(type(Builder.build)).toBe("function")
			expect(type(Compiler.compile)).toBe("function")
			expect(type(Compiler.key)).toBe("function")
			expect(Migration.CURRENT).toBe(Constants.SCHEMA_VERSION)
			expect(type(Migration.migrate)).toBe("function")
			expect(type(Validation.validate)).toBe("function")
		end)

		T.itIf(isLune, "handles carry the documented methods, signals and fields", function()
			AstraVFX.Register(AURA_JSON)
			local parent = H:folder("E2EApi", workspace)
			local handle = AstraVFX.Play("e2eAura", { Parent = parent })
			for _, name in
				{
					"Stop",
					"Destroy",
					"Pause",
					"Resume",
					"SetTimeScale",
					"SetCFrame",
					"Fire",
					"SetLoop",
					"Seek",
					"GetTime",
					"GetState",
					"IsPlaying",
				}
			do
				expect(type(handle[name])).toBe("function")
			end
			expect(type(handle.Finished.Connect)).toBe("function")
			expect(type(handle.Event.Connect)).toBe("function")
			expect(handle.Name).toBe("E2E Aura")
			expect(handle.Id).toBe("e2eAura")
			-- Preload(name, { Count, Quality }) warms the pool for that variant: the next Play builds nothing
			handle:Destroy()
			AstraVFX._reset()
			AstraVFX.Register(AURA_JSON)
			expect(AstraVFX.Preload("E2E Aura", { Count = 2, Quality = "Medium" })).toBe(2)
			expect(Pool.count()).toBe(2)
			local pooled = AstraVFX.Play("E2E Aura", { Parent = parent, Quality = "Medium" })
			expect(Pool.count()).toBe(1)
			pooled:Destroy()
			expectClean(parent)
			expectNoWarnings()
		end)
	end)

	T.describe("EndToEnd test harness", function()
		-- Lune drops an Instance's userdata wrapper when Luau holds no reference to it (the next access makes a new
		-- one), so a weak-keyed table keyed by Instances loses entries of live instances on GC. The fakes keep
		-- per-instance signals in such a table: a handler connected to an instance only the tree references
		-- could vanish before the event fired (intermittent UI spec failures in full runs).
		T.itIf(
			isLune,
			"fake instance signals keep their handlers while connected, across garbage collections",
			function()
				local folder = Instance.new("Folder")
				table.insert(H.created, folder)
				do
					local part = Instance.new("Part")
					part.Name = "P"
					part.Parent = folder
				end
				local hits = 0
				local connection = (folder:FindFirstChild("P") :: any).AncestryChanged:Connect(function()
					hits += 1
				end)
				local junk = {}
				for i = 1, 2000000 do
					junk[i % 1000 + 1] = { i } -- allocation pressure: several GC cycles
				end
				ctx.fakes:signalFor(folder:FindFirstChild("P"), "AncestryChanged"):Fire()
				expect(hits).toBe(1)
				connection:Disconnect()
			end
		)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Part 3: performance sanity (CPU-side Lune measurement, NOT an FPS claim)
	-- ─────────────────────────────────────────────────────────────────────────

	-- A wide effect: `n` children (parts, rings, particles, debris, lights) under a spinning group, all active
	-- for the whole run, each with a track.
	local function wideEffect(n: number): any
		local components: { any } = {
			{ id = "pivot", name = "Pivot", type = "group", properties = { spin = { 0, 90, 0 } } },
		}
		local kinds = { "part", "ring", "particles", "debris", "light" }
		for i = 1, n do
			local kind = kinds[(i - 1) % #kinds + 1]
			local c: any = {
				id = "c" .. i,
				name = "C" .. i,
				type = kind,
				parent = "pivot",
				transform = { position = { (i % 7) - 3, i % 3, (i % 5) - 2 } },
			}
			if kind == "part" then
				c.tracks = R({
					id = "t",
					channel = "transparency",
					keyframes = R({ time = 0, value = 0 }, { time = 10, value = 1 }),
				})
			elseif kind == "ring" then
				c.properties = { segments = 12 }
				c.tracks = R({
					id = "t",
					channel = "radius",
					keyframes = R({ time = 0, value = 1 }, { time = 10, value = 5 }),
				})
			elseif kind == "particles" then
				c.properties = { rate = 5 }
				c.tracks =
					R({ id = "t", channel = "rate", keyframes = R({ time = 0, value = 5 }, { time = 10, value = 1 }) })
			elseif kind == "debris" then
				c.properties = { count = 4 }
			else
				c.tracks = R({
					id = "t",
					channel = "brightness",
					keyframes = R({ time = 0, value = 1 }, { time = 10, value = 3 }),
				})
			end
			table.insert(components, c)
		end
		return {
			schemaVersion = 1,
			id = "wide" .. n,
			name = "Wide " .. n,
			duration = 10,
			components = components,
		}
	end

	-- Counts controller calls per frame for one player over `frameCount` frames.
	local function workPerFrame(def: any, frameCount: number): { number }
		local p = rawPlayer(def)
		local calls = 0
		for _, controller in p.built.controllers do
			for _, method in { "apply", "setTransform", "update", "onAction", "setActive" } do
				local original = controller[method]
				if original then
					controller[method] = function(...: any)
						calls += 1
						return original(...)
					end
				end
			end
		end
		p.player:start()
		local out = {}
		for _ = 1, frameCount do
			calls = 0
			p.player:step(1 / 60)
			table.insert(out, calls)
		end
		return out
	end

	local function average(list: { number }, from: number, to: number): number
		local sum = 0
		for i = from, to do
			sum += list[i]
		end
		return sum / (to - from + 1)
	end

	T.describe("EndToEnd performance sanity", function()
		T.itIf(isLune, "per-frame work is constant over time and linear in the number of components", function()
			local small = workPerFrame(wideEffect(20), 300)
			local large = workPerFrame(wideEffect(40), 300)
			-- no growth with elapsed frames (frames 2..100 vs 201..300; frame 1 activates everything)
			expect(average(small, 201, 300)).toBeLessThanOrEqual(average(small, 2, 100) * 1.05)
			expect(average(large, 201, 300)).toBeLessThanOrEqual(average(large, 2, 100) * 1.05)
			-- twice the components, about twice the calls (linear, not quadratic)
			local ratio = average(large, 2, 300) / average(small, 2, 300)
			expect(ratio > 1.8 and ratio < 2.2).toBe(true)
			expectNoWarnings()
		end)

		T.itIf(isLune, "50 concurrent effects stepping 300 frames (CPU-side Lune timing, reported only)", function()
			for _, text in { EXPLOSION_JSON, LIGHTNING_JSON, AURA_JSON } do
				AstraVFX.Register(text)
			end
			local parent = H:folder("E2EPerf", workspace)
			local names = { "e2eExplosion", "e2eLightning", "e2eAura" }
			local function measure(count: number): { number }
				for i = 1, count do
					AstraVFX.Play(names[(i - 1) % 3 + 1], {
						Parent = parent,
						Loop = true, -- keep every effect alive for the whole run
						Position = Vector3.new(i * 4, 0, 0),
						Quality = "High",
					})
				end
				expect(AstraVFX.ActiveCount()).toBe(count)
				local times = {}
				for _ = 1, 300 do
					local started = os.clock()
					ctx.fakes:step(DT)
					table.insert(times, os.clock() - started)
				end
				expect(AstraVFX.ActiveCount()).toBe(count)
				AstraVFX.StopAll(true)
				return times
			end
			local fifty = measure(50)
			local twentyFive = measure(25)
			local avg50 = average(fifty, 2, 300)
			local avg25 = average(twentyFive, 2, 300)
			print(
				string.format(
					"[perf] Lune CPU time per Scheduler frame (not an FPS claim): 50 effects %.3f ms "
						.. "(%.1f µs / effect; frames 2-100 %.3f ms, 201-300 %.3f ms), 25 effects %.3f ms",
					avg50 * 1000,
					avg50 * 1e6 / 50,
					average(fifty, 2, 100) * 1000,
					average(fifty, 201, 300) * 1000,
					avg25 * 1000
				)
			)
			-- loose sanity bounds only (timings are noisy): no growth over time, no blow-up with the count
			expect(average(fifty, 201, 300)).toBeLessThan(average(fifty, 2, 100) * 3 + 0.002)
			expect(avg50).toBeLessThan(avg25 * 4 + 0.002)
			expectClean(parent)
			expectNoWarnings()
		end)
	end)
end
