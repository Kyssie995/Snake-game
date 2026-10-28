--!strict
--[[
	Core/Player — frame algorithm, schedule execution, seek, loop, stop / finish (docs/MODULE_CONTRACTS.md §17,
	docs/ARCHITECTURE.md §5.2).

	Effects are real definitions (Luau tables / JSON text) taken through Validation -> Compiler -> Builder into Lune
	Instances; the Player is stepped by hand. Engine calls are observed through the Lune fakes (ctx.fakes.emits /
	clears / sounds, BulkMoveTo). Expected frames and values are computed independently (float accumulation of dt
	as the frame loop does it, easing formulas, CFrame composition), never by calling the Player again.
]]
return function(T: any, use: (string) -> any, ctx: any)
	local Env = use("AstraVFX.Core.Env")
	local Graph = use("AstraVFX.Core.Graph")
	local Json = use("AstraVFX.Core.Json")
	local Player = use("AstraVFX.Core.Player")
	local Fixtures = use("Tests.Specs.Helpers.EffectFixtures")
	local HarnessModule = use("Tests.Specs.Helpers.PlaybackHarness")
	local expect = T.expect

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function R(...: any): { any }
		return { ... }
	end
	local isLune = ctx.environment == "lune"
	local DT = 1 / 60

	local H: any = nil
	T.beforeEach(function()
		H = HarnessModule.new(use, ctx)
	end)
	T.afterEach(function()
		H:cleanup()
		Env.override("Workspace", nil)
	end)

	-- First frame index k (1-based) at which the accumulated time sum(dt) reaches `target`.
	local function frameReaching(dt: number, target: number): number
		local t = 0
		for k = 1, 100000 do
			t += dt
			if t >= target then
				return k
			end
		end
		error("unreachable")
	end

	local function emitterOf(p: any, id: string): any
		return p.built.controllers[id].instances[1]
	end

	local function burstDef(): any
		return {
			schemaVersion = 1,
			id = "bursts",
			name = "Bursts",
			duration = 1.5,
			components = R({
				id = "sparks",
				name = "Sparks",
				type = "particles",
				properties = { rate = 0, lifetime = { 0.5, 0.5 } },
				events = R(
					{ id = "early", time = 0.2, action = "emit", count = 12 },
					{ id = "late", time = 1.0, action = "emit", count = 40 }
				),
			}),
		}
	end

	T.describe("Player start and first frame", function()
		T.itIf(isLune, "start() poses everything at t = 0 without activating or executing anything", function()
			local def = {
				schemaVersion = 1,
				id = "pose",
				name = "Pose",
				duration = 1,
				components = R({
					id = "sparks",
					name = "Sparks",
					type = "particles",
					transform = { position = { 0, 2, 0 } },
					properties = { rate = 10, burst = 5 },
					events = R({ id = "zero", time = 0, action = "emit", count = 3 }),
				}, { id = "core", name = "Core", type = "part", transform = { position = { 1, 0, 0 } } }),
			}
			local origin = CFrame.new(10, 0, 0)
			local p = H:player(def, nil, { cframe = origin })
			local mark = H:emitMark()
			p.player:start()
			expect(p.player.state).toBe("playing")
			expect(p.player.time).toBe(0)
			expect(H:emitsSince(mark)).toEqual({})
			local emitter = emitterOf(p, "sparks")
			expect(emitter.Enabled).toBe(false)
			local core = p.built.controllers.core.instances[1]
			expect(core.Transparency).toBe(1) -- inactive = invisible
			expect(core.CFrame).toBeCloseTo(origin * CFrame.new(1, 0, 0), 1e-4) -- but already in place
			expect(p.built.root.CFrame).toBeCloseTo(origin, 1e-4)
			expect(emitter.Parent.CFrame).toBeCloseTo(CFrame.new(0, 2, 0), 1e-4) -- attachment on the root
			-- the first step activates (burst 5) and runs the action at exactly t = 0 (emit 3)
			p.player:step(DT)
			expect(H:emitsSince(mark, emitter)).toEqual({ 5, 3 })
			expect(emitter.Enabled).toBe(true)
			expect(core.Transparency).toBe(0)
			-- start() is a no-op when not idle
			p.player:start()
			expect(p.player.time).toBeCloseTo(DT, 1e-12)
		end)

		T.itIf(isLune, "applies the transform before setActive(true), so a burst spawns in place", function()
			local def = {
				schemaVersion = 1,
				id = "inplace",
				name = "In Place",
				duration = 1,
				components = R({
					id = "sparks",
					name = "Sparks",
					type = "particles",
					startTime = 0.5,
					transform = { position = { 0, 2, 0 } },
					properties = { rate = 0, burst = 4 },
				}),
			}
			local p = H:player(def)
			local controller = p.built.controllers.sparks
			local attachment = controller.instances[2]
			local seen: { any } = {}
			local original = controller.setActive
			controller.setActive = function(self: any, active: boolean, frame: any)
				if active then
					table.insert(seen, attachment.CFrame)
				end
				original(self, active, frame)
			end
			p.player:start()
			H:steps(p.player, 40, DT)
			expect(#seen).toBe(1)
			expect(seen[1]).toBeCloseTo(CFrame.new(0, 2, 0), 1e-4)
		end)
	end)

	T.describe("Player schedule", function()
		T.itIf(isLune, "emits the bursts at 0.2 s and 1.0 s on exactly the right 1/60 frames", function()
			local p = H:player(burstDef())
			local emitter = emitterOf(p, "sparks")
			p.player:start()
			local frameA = frameReaching(DT, 0.2)
			local frameB = frameReaching(DT, 1.0)
			local perFrame: { [number]: { number } } = {}
			for k = 1, 100 do
				local mark = H:emitMark()
				p.player:step(DT)
				local list = H:emitsSince(mark, emitter)
				if #list > 0 then
					perFrame[k] = list
				end
			end
			local expected: { [number]: { number } } = {}
			expected[frameA] = { 12 }
			expected[frameB] = { 40 }
			expect(perFrame).toEqual(expected)
			-- sum of 12 × (1/60) is 0.19999999999999998 < 0.2, so the burst lands on frame 13 (float accumulation)
			expect(frameA >= 12 and frameA <= 13).toBe(true)
			expect(frameB >= 60 and frameB <= 61).toBe(true)
		end)

		T.itIf(isLune, "scales event counts with the quality profile (Low)", function()
			local p = H:player(burstDef(), { quality = "Low" })
			local emitter = emitterOf(p, "sparks")
			local mark = H:emitMark()
			p.player:start()
			H:steps(p.player, 100, DT)
			-- 12 × 0.35 = 4.2 -> 4, 40 × 0.35 = 14
			expect(H:emitsSince(mark, emitter)).toEqual({ 4, 14 })
		end)

		T.itIf(isLune, "toggles continuous emission exactly at the span boundaries", function()
			local def = {
				schemaVersion = 1,
				id = "rate",
				name = "Rate",
				duration = 1.5,
				components = R({
					id = "stream",
					name = "Stream",
					type = "particles",
					startTime = 0.5,
					duration = 0.5,
					properties = { rate = 20 },
				}),
			}
			local p = H:player(def)
			local emitter = emitterOf(p, "stream")
			p.player:start()
			expect(emitter.Enabled).toBe(false)
			local t = 0
			local switches = 0
			local last = false
			for _ = 1, 100 do
				p.player:step(DT)
				t += DT
				local want = t >= 0.5 and t < 1.0
				expect(R(t, emitter.Enabled)).toEqual(R(t, want))
				if emitter.Enabled ~= last then
					switches += 1
					last = emitter.Enabled
				end
			end
			expect(switches).toBe(2)
			expect(emitter.Rate).toBeCloseTo(20, 1e-6)
		end)

		T.itIf(isLune, "activates a span that starts and ends inside one frame so its burst is not lost", function()
			local def = {
				schemaVersion = 1,
				id = "short",
				name = "Short",
				duration = 1,
				components = R({
					id = "blip",
					name = "Blip",
					type = "particles",
					startTime = 0.42,
					duration = 0.03,
					properties = { rate = 30, burst = 6 },
				}),
			}
			local p = H:player(def)
			local emitter = emitterOf(p, "blip")
			local mark = H:emitMark()
			p.player:start()
			H:steps(p.player, 10, 0.1)
			expect(H:emitsSince(mark, emitter)).toEqual({ 6 })
			expect(emitter.Enabled).toBe(false)
		end)

		T.itIf(isLune, "evaluates a transparency track at exact times (Quad.In, Constant, linear)", function()
			local def = {
				schemaVersion = 1,
				id = "fade",
				name = "Fade",
				duration = 2,
				components = R({
					id = "core",
					name = "Core",
					type = "part",
					properties = { transparency = 0.3 },
					tracks = R({
						id = "t",
						channel = "transparency",
						keyframes = R(
							{ time = 0, value = 0, easing = "Quad.In" },
							{ time = 1, value = 1, easing = "Constant" },
							{ time = 1.5, value = 0.2 }
						),
					}),
				}),
			}
			local p = H:player(def, nil, { autoRelease = false })
			local part = p.built.controllers.core.instances[1]
			p.player:start()
			local expected = {
				0.25 ^ 2, -- 0.25: Quad.In(0.25)
				0.5 ^ 2,
				0.75 ^ 2,
				1, -- 1.0: value of the key at 1
				1, -- 1.25: Constant segment
				0.2, -- 1.5: last key
				0.2,
				1, -- 2.0: span ended -> hidden
			}
			for i, value in expected do
				p.player:step(0.25)
				expect(p.player.time).toBe(i * 0.25)
				expect(part.Transparency).toBeCloseTo(value, 1e-6)
			end
			-- seek reaches the same exact values
			p.player:seek(0.5)
			expect(part.Transparency).toBeCloseTo(0.25, 1e-6)
			p.player:seek(1.25)
			expect(part.Transparency).toBeCloseTo(1, 1e-6)
		end)

		T.itIf(isLune, "passes a channel value to the controller only when it changed", function()
			local def = {
				schemaVersion = 1,
				id = "applies",
				name = "Applies",
				duration = 2,
				components = R({
					id = "core",
					name = "Core",
					type = "part",
					tracks = R({
						id = "t",
						channel = "transparency",
						keyframes = R({ time = 0, value = 0.5, easing = "Constant" }, { time = 1, value = 0.8 }),
					}),
				}),
			}
			local p = H:player(def)
			local controller = p.built.controllers.core
			local calls: { any } = {}
			local original = controller.apply
			controller.apply = function(self: any, channel: string, value: any)
				table.insert(calls, { channel, value })
				original(self, channel, value)
			end
			p.player:start()
			H:steps(p.player, 110, DT)
			expect(#calls).toBe(2)
			expect(calls[1][1]).toBe("transparency")
			expect(calls[1][2]).toBeCloseTo(0.5, 1e-9)
			expect(calls[2][2]).toBeCloseTo(0.8, 1e-9)
		end)

		T.itIf(
			isLune,
			"routes fire actions to the event signal, onEvent and actionExecuted in schedule order",
			function()
				local def = H:decode([[
{
  "schemaVersion": 1, "id": "events", "name": "Events", "duration": 1,
  "markers": [ { "id": "m", "time": 0.5, "label": "Impact", "event": "Impact" } ],
  "components": [
    { "id": "core", "name": "Core", "type": "part",
      "events": [ { "id": "f", "time": 0.25, "action": "fire", "name": "CoreFire" } ] }
  ],
  "graph": {
    "nodes": [
      { "id": "play", "type": "OnPlay" },
      { "id": "wait", "type": "Delay", "params": { "seconds": 0.75 } },
      { "id": "fe", "type": "FireEvent", "params": { "name": "GraphFire" } }
    ],
    "links": [ { "from": "play.out", "to": "wait.in" }, { "from": "wait.out", "to": "fe.in" } ]
  }
}]])
				local fromCallback: { string } = {}
				local p = H:player(def, nil, {
					onEvent = function(name: string)
						table.insert(fromCallback, name)
					end,
				})
				local fromSignal: { string } = {}
				local executed: { string } = {}
				p.player.event:Connect(function(name: string)
					table.insert(fromSignal, name)
				end)
				p.player.actionExecuted:Connect(function(action: any)
					table.insert(executed, action.source .. ":" .. tostring(action.name))
				end)
				p.player:start()
				H:steps(p.player, 70, DT)
				expect(fromSignal).toEqual({ "CoreFire", "Impact", "GraphFire" })
				expect(fromCallback).toEqual({ "CoreFire", "Impact", "GraphFire" })
				expect(executed).toEqual({ "event:CoreFire", "marker:Impact", "graph:GraphFire" })
			end
		)

		T.itIf(isLune, "a failing onEvent handler is reported and does not stop the frame", function()
			local def = {
				schemaVersion = 1,
				id = "bad",
				name = "Bad",
				duration = 1,
				markers = { { id = "m", time = 0.1, label = "M", event = "Boom" } },
				components = R({
					id = "sparks",
					name = "Sparks",
					type = "particles",
					properties = { rate = 0 },
					events = R({ id = "e", time = 0.1, action = "emit", count = 2 }),
				}),
			}
			local p = H:player(def, nil, {
				onEvent = function(_name: string)
					error("handler exploded")
				end,
			})
			local mark = H:emitMark()
			p.player:start()
			H:steps(p.player, 12, DT)
			expect(H:emitsSince(mark)).toEqual({ 2 })
			expect(p.player.state).toBe("playing")
		end)
	end)

	T.describe("Player transforms", function()
		T.itIf(isLune, "composes parent transforms with spin, a position track and the scale channel", function()
			local def = {
				schemaVersion = 1,
				id = "xf",
				name = "Transform",
				duration = 2,
				components = R({
					id = "pivot",
					name = "Pivot",
					type = "group",
					transform = { position = { 0, 2, 0 } },
					properties = { spin = { 0, 90, 0 } },
				}, {
					id = "arm",
					name = "Arm",
					type = "part",
					parent = "pivot",
					transform = { position = { 3, 0, 0 } },
					properties = { size = { 1, 1, 1 } },
					tracks = R({
						id = "s",
						channel = "scale",
						keyframes = R({ time = 0, value = 1 }, { time = 1, value = 3 }),
					}, {
						id = "p",
						channel = "position",
						keyframes = R({ time = 0, value = { 3, 0, 0 } }, { time = 1, value = { 5, 0, 0 } }),
					}),
				}),
			}
			local origin = CFrame.new(10, 0, 0) * CFrame.Angles(0, 0, math.rad(30))
			local p = H:player(def, nil, { cframe = origin })
			local part = p.built.controllers.arm.instances[1]
			p.player:start()
			H:steps(p.player, 2, 0.25)
			local pivotLocal = CFrame.new(0, 2, 0) * CFrame.fromOrientation(0, math.rad(45), 0)
			local expected = origin * pivotLocal * CFrame.new(4, 0, 0)
			expect(part.CFrame).toBeCloseTo(expected, 1e-4)
			expect(part.Size).toBeCloseTo(Vector3.new(2, 2, 2), 1e-4)
			expect(p.built.root.CFrame).toBeCloseTo(origin, 1e-4)
		end)

		T.itIf(
			isLune,
			"follows a moving attach target with the offset and keeps the last CFrame once it is removed",
			function()
				local def = {
					schemaVersion = 1,
					id = "attach",
					name = "Attach",
					duration = 3,
					components = R(
						{ id = "core", name = "Core", type = "part", transform = { position = { 0, 1, 0 } } },
						{
							id = "late",
							name = "Late",
							type = "particles",
							startTime = 1,
							transform = { position = { 0, 0, -2 } },
							properties = { shape = "Box", rate = 0, burst = 3 },
						}
					),
				}
				local target = Instance.new("Part")
				target.Anchored = true
				target.CFrame = CFrame.new(0, 5, 0)
				target.Parent = workspace
				table.insert(H.created, target)
				local offset = CFrame.new(0, 0, 1)
				local p = H:player(def, nil, { attach = target, offset = offset, cframe = CFrame.new(99, 99, 99) })
				local core = p.built.controllers.core.instances[1]
				local host = p.built.controllers.late.instances[2] -- Box shape: emitter in a host part
				expect(host:IsA("BasePart")).toBe(true)
				p.player:start()
				expect(p.built.root.CFrame).toBeCloseTo(CFrame.new(0, 5, 0) * offset, 1e-4)
				for i = 1, 70 do
					target.CFrame = CFrame.new(i * 0.5, 5, 0) * CFrame.Angles(0, math.rad(i), 0)
					p.player:step(DT)
					local root = target.CFrame * offset
					expect(p.built.root.CFrame).toBeCloseTo(root, 1e-3)
					expect(core.CFrame).toBeCloseTo(root * CFrame.new(0, 1, 0), 1e-3)
					-- the inactive host part follows as well, so it activates (and bursts) in place
					expect(host.CFrame).toBeCloseTo(root * CFrame.new(0, 0, -2), 1e-3)
				end
				local last = p.built.root.CFrame
				target.Parent = nil -- removed (e.g. streamed out): keep the last CFrame and keep playing
				target.CFrame = CFrame.new(500, 0, 0)
				H:steps(p.player, 5, DT)
				expect(p.built.root.CFrame).toBeCloseTo(last, 1e-6)
				expect(p.player.state).toBe("playing")
				-- setCFrame detaches; the offset still applies
				p.player:setCFrame(CFrame.new(1, 2, 3))
				p.player:step(DT)
				expect(p.built.root.CFrame).toBeCloseTo(CFrame.new(1, 2, 3) * offset, 1e-4)
			end
		)

		T.itIf(isLune, "follows an Attachment target (parent part CFrame × attachment CFrame)", function()
			local def = {
				schemaVersion = 1,
				id = "att",
				name = "Att",
				duration = 1,
				components = R({ id = "core", name = "Core", type = "part" }),
			}
			local holder = Instance.new("Part")
			holder.Anchored = true
			holder.CFrame = CFrame.new(3, 0, 0)
			holder.Parent = workspace
			table.insert(H.created, holder)
			local attachment = Instance.new("Attachment")
			attachment.CFrame = CFrame.new(0, 4, 0)
			attachment.Parent = holder
			local p = H:player(def, nil, { attach = attachment })
			p.player:start()
			p.player:step(DT)
			expect(p.built.root.CFrame).toBeCloseTo(CFrame.new(3, 4, 0), 1e-4)
			holder.CFrame = CFrame.new(-3, 0, 0)
			p.player:step(DT)
			expect(p.built.root.CFrame).toBeCloseTo(CFrame.new(-3, 4, 0), 1e-4)
		end)

		T.itIf(isLune, "moves every part with exactly one BulkMoveTo per frame (FireCFrameChanged)", function()
			local calls: { any } = {}
			local recorder = {
				BulkMoveTo = function(_self: any, parts: { BasePart }, cframes: { CFrame }, mode: any)
					table.insert(calls, { n = #parts, mode = mode, parts = table.clone(parts) })
					for i, part in parts do
						part.CFrame = cframes[i]
					end
				end,
			}
			Env.override("Workspace", recorder)
			local def = {
				schemaVersion = 1,
				id = "bulk",
				name = "Bulk",
				duration = 1,
				components = R({ id = "rocks", name = "Rocks", type = "debris", properties = { count = 6 } }, {
					id = "core",
					name = "Core",
					type = "part",
					tracks = R({
						id = "p",
						channel = "position",
						keyframes = R({ time = 0, value = { 0, 0, 0 } }, { time = 1, value = { 0, 5, 0 } }),
					}),
				}),
			}
			local p = H:player(def)
			p.player:start()
			expect(#calls).toBe(1)
			expect(calls[1].parts[1]).toBe(p.built.root) -- the Root part moves with the others
			for frame = 1, 10 do
				p.player:step(DT)
				expect(#calls).toBe(frame + 1)
			end
			for _, call in calls do
				expect(call.mode).toBe(Enum.BulkMoveMode.FireCFrameChanged)
				expect(call.n > 0).toBe(true)
			end
			expect(p.player:lastMoveCount()).toBe(calls[#calls].n)
			local core = p.built.controllers.core.instances[1]
			expect(core.CFrame.Position.Y).toBeCloseTo(5 * 10 * DT, 1e-3)
		end)

		T.itIf(isLune, "uses a WorldModel ancestor of the container instead of Workspace (viewport)", function()
			local calls = 0
			Env.override("Workspace", {
				BulkMoveTo = function()
					calls += 1
				end,
			})
			local worldModel = Instance.new("WorldModel")
			table.insert(H.created, worldModel)
			local def = {
				schemaVersion = 1,
				id = "vp",
				name = "Viewport",
				duration = 1,
				components = R({ id = "core", name = "Core", type = "part", transform = { position = { 0, 3, 0 } } }),
			}
			local p = H:player(def, nil, { cframe = CFrame.new(5, 0, 0) }, { parent = worldModel, viewport = true })
			p.player:start()
			p.player:step(DT)
			expect(calls).toBe(0)
			local core = p.built.controllers.core.instances[1]
			expect(core.CFrame).toBeCloseTo(CFrame.new(5, 3, 0), 1e-4)
		end)
	end)

	T.describe("Player graph actions", function()
		T.itIf(isLune, "tweens from the current value with easing and applies set immediately", function()
			local def = H:decode([[
{
  "schemaVersion": 1, "id": "tween", "name": "Tween", "duration": 2,
  "components": [
    { "id": "core", "name": "Core", "type": "part", "properties": { "transparency": 0.2, "color": "#FF0000" } }
  ],
  "graph": {
    "nodes": [
      { "id": "play", "type": "OnPlay" },
      { "id": "par", "type": "Parallel", "params": { "count": 2 } },
      { "id": "wait", "type": "Delay", "params": { "seconds": 0.5 } },
      { "id": "fade", "type": "Tween",
        "params": { "target": "core", "channel": "transparency", "value": 1, "duration": 0.5, "easing": "Quad.In" } },
      { "id": "waitColor", "type": "Delay", "params": { "seconds": 0.25 } },
      { "id": "paint", "type": "SetProperty", "params": { "target": "core", "channel": "color", "value": "#0000FF" } },
      { "id": "waitMove", "type": "Delay", "params": { "seconds": 0.5 } },
      { "id": "move", "type": "Tween",
        "params": { "target": "core", "channel": "position", "value": [0, 4, 0], "duration": 0.25 } }
    ],
    "links": [
      { "from": "play.out", "to": "par.in" },
      { "from": "par.out1", "to": "wait.in" },
      { "from": "wait.out", "to": "fade.in" },
      { "from": "par.out2", "to": "waitColor.in" },
      { "from": "waitColor.out", "to": "paint.in" },
      { "from": "fade.done", "to": "waitMove.in" },
      { "from": "waitMove.out", "to": "move.in" }
    ]
  }
}]])
			local p = H:player(def)
			local part = p.built.controllers.core.instances[1]
			p.player:start()
			p.player:step(0.25) -- t = 0.25: SetProperty runs (after the evaluation) and is applied in this frame
			expect(part.Color).toBeCloseTo(Color3.new(0, 0, 1), 1e-6)
			expect(part.Transparency).toBeCloseTo(0.2, 1e-6)
			p.player:step(0.25) -- t = 0.5: the tween starts now (from 0.2)
			expect(part.Transparency).toBeCloseTo(0.2, 1e-6)
			p.player:step(0.25) -- t = 0.75: alpha 0.5, Quad.In -> 0.25
			expect(part.Transparency).toBeCloseTo(0.2 + 0.8 * 0.25, 1e-6)
			p.player:step(0.25) -- t = 1.0: done
			expect(part.Transparency).toBeCloseTo(1, 1e-6)
			p.player:step(0.25) -- t = 1.25: the override holds the target
			expect(part.Transparency).toBeCloseTo(1, 1e-6)
			p.player:step(0.25) -- t = 1.5: position tween starts (transform overrides apply from the next frame)
			p.player:step(0.125) -- t = 1.625: linear alpha 0.5 -> y = 2
			expect(part.CFrame.Position).toBeCloseTo(Vector3.new(0, 2, 0), 1e-4)
			p.player:step(0.125)
			p.player:step(0.125)
			expect(part.CFrame.Position).toBeCloseTo(Vector3.new(0, 4, 0), 1e-4)
		end)

		T.itIf(isLune, "fire(name) unrolls OnEvent flows from the current time", function()
			local def = H:decode([[
{
  "schemaVersion": 1, "id": "detonate", "name": "Detonate", "duration": 2,
  "components": [ { "id": "sparks", "name": "Sparks", "type": "particles", "properties": { "rate": 0 } } ],
  "graph": {
    "nodes": [
      { "id": "on", "type": "OnEvent", "params": { "name": "Detonate" } },
      { "id": "big", "type": "Emit", "params": { "target": "sparks", "count": 7 } },
      { "id": "wait", "type": "Delay", "params": { "seconds": 0.1 } },
      { "id": "small", "type": "Emit", "params": { "target": "sparks", "count": 3 } }
    ],
    "links": [
      { "from": "on.out", "to": "big.in" },
      { "from": "big.out", "to": "wait.in" },
      { "from": "wait.out", "to": "small.in" }
    ]
  }
}]])
			local p = H:player(def)
			local emitter = emitterOf(p, "sparks")
			p.player:start()
			H:steps(p.player, 30, DT)
			local mark = H:emitMark()
			local fireTime = p.player.time
			p.player:fire("Detonate")
			p.player:fire("Unknown") -- no flow: nothing happens
			expect(H:emitsSince(mark)).toEqual({}) -- queued, not executed immediately
			p.player:step(DT)
			expect(H:emitsSince(mark, emitter)).toEqual({ 7 })
			-- the delayed emit runs in the first frame whose time reaches fireTime + 0.1
			local before = p.player.time
			for _ = 1, 20 do
				before = p.player.time
				p.player:step(DT)
				if #H:emitsSince(mark, emitter) > 1 then
					break
				end
			end
			expect(H:emitsSince(mark, emitter)).toEqual({ 7, 3 })
			expect(before < fireTime + 0.1).toBe(true)
			expect(p.player.time >= fireTime + 0.1).toBe(true)
		end)

		T.itIf(isLune, "SetEnabled switches a type without enable/disable events off and on", function()
			local def = H:decode([[
{
  "schemaVersion": 1, "id": "toggle", "name": "Toggle", "duration": 2,
  "components": [ { "id": "core", "name": "Core", "type": "part" } ],
  "graph": {
    "nodes": [
      { "id": "play", "type": "OnPlay" },
      { "id": "seq", "type": "Sequence", "params": { "count": 2, "interval": 0.5 } },
      { "id": "w", "type": "Delay", "params": { "seconds": 0.5 } },
      { "id": "off", "type": "SetEnabled", "params": { "target": "core", "enabled": false } },
      { "id": "on", "type": "SetEnabled", "params": { "target": "core", "enabled": true } }
    ],
    "links": [
      { "from": "play.out", "to": "w.in" },
      { "from": "w.out", "to": "seq.in" },
      { "from": "seq.then1", "to": "off.in" },
      { "from": "seq.then2", "to": "on.in" }
    ]
  }
}]])
			local p = H:player(def)
			local part = p.built.controllers.core.instances[1]
			p.player:start()
			p.player:step(0.25)
			expect(part.Transparency).toBe(0)
			p.player:step(0.25) -- 0.5: disable runs and hides the part at once
			expect(part.Transparency).toBe(1)
			p.player:step(0.25) -- 0.75
			expect(part.Transparency).toBe(1)
			p.player:step(0.25) -- 1.0: enable runs after this frame's evaluation
			expect(part.Transparency).toBe(1)
			p.player:step(0.25) -- 1.25: active again
			expect(part.Transparency).toBe(0)
		end)
	end)

	T.describe("Player loop", function()
		local function loopDef(): any
			return H:decode([[
{
  "schemaVersion": 1, "id": "looper", "name": "Looper", "duration": 0.5, "loop": true, "seed": 7,
  "components": [
    { "id": "sparks", "name": "Sparks", "type": "particles",
      "properties": { "rate": 20, "burst": 5 },
      "events": [
        { "id": "pop", "time": 0.1, "action": "emit", "count": 3 },
        { "id": "off", "time": 0.3, "action": "disable" }
      ] }
  ],
  "graph": {
    "nodes": [
      { "id": "play", "type": "OnPlay" },
      { "id": "pick", "type": "RandomBranch", "params": { "count": 4 } },
      { "id": "a", "type": "FireEvent", "params": { "name": "A" } },
      { "id": "b", "type": "FireEvent", "params": { "name": "B" } },
      { "id": "c", "type": "FireEvent", "params": { "name": "C" } },
      { "id": "d", "type": "FireEvent", "params": { "name": "D" } }
    ],
    "links": [
      { "from": "play.out", "to": "pick.in" },
      { "from": "pick.out1", "to": "a.in" },
      { "from": "pick.out2", "to": "b.in" },
      { "from": "pick.out3", "to": "c.in" },
      { "from": "pick.out4", "to": "d.in" }
    ]
  }
}]])
		end

		T.itIf(isLune, "runs the schedule every cycle with the cycle's RandomBranch choice", function()
			local p = H:player(loopDef())
			local compiled = p.compiled
			local log: { any } = {}
			p.player.event:Connect(function(name: string)
				table.insert(log, { cycle = p.player.cycle, name = name })
			end)
			p.player:start()
			local cycles = 12
			H:steps(p.player, cycles * 15 + 5, 1 / 30)
			expect(p.player.cycle).toBe(cycles)
			local distinct: { [string]: boolean } = {}
			local expected: { any } = {}
			for cycle = 0, cycles do
				local list = Graph.run(compiled.graph, { kind = "play" }, 0, compiled.seed, cycle, compiled)
				local name = nil
				for _, action in ipairs(list) do
					if action.action == "fire" then
						name = action.name
					end
				end
				table.insert(expected, { cycle = cycle, name = name })
				distinct[name] = true
			end
			expect(log).toEqual(expected)
			local count = 0
			for _ in distinct do
				count += 1
			end
			expect(count > 1).toBe(true) -- different seeds per cycle
		end)

		T.itIf(isLune, "re-activates components every cycle and restores emitters disabled by an event", function()
			local p = H:player(loopDef())
			local emitter = emitterOf(p, "sparks")
			local mark = H:emitMark()
			p.player:start()
			p.player:step(0.05) -- 0.05
			expect(emitter.Enabled).toBe(true)
			H:steps(p.player, 6, 0.05) -- 0.35: disabled by the event at 0.3
			expect(emitter.Enabled).toBe(false)
			H:steps(p.player, 4, 0.05) -- 0.55 -> wrapped to cycle 1, t = 0.05
			expect(p.player.cycle).toBe(1)
			expect(p.player.time).toBeCloseTo(0.05, 1e-9)
			expect(emitter.Enabled).toBe(true)
			-- burst on activation + pop at 0.1, every cycle
			H:steps(p.player, 2, 0.05)
			expect(H:emitsSince(mark, emitter)).toEqual({ 5, 3, 5, 3 })
		end)

		T.itIf(isLune, "runs the actions of every cycle a long frame passes through", function()
			local def: any = {
				schemaVersion = 1,
				id = "tiny",
				name = "Tiny",
				duration = 0.04,
				loop = true,
				components = R({
					id = "sparks",
					name = "Sparks",
					type = "particles",
					properties = { rate = 0 },
					events = R({ id = "e", time = 0.01, action = "emit", count = 2 }),
				}),
			}
			local p = H:player(def)
			local emitter = emitterOf(p, "sparks")
			local mark = H:emitMark()
			p.player:start()
			p.player:step(0.1) -- 0 -> 0.1 = cycles 0 and 1 completely, cycle 2 up to 0.02
			expect(p.player.cycle).toBe(2)
			expect(p.player.time).toBeCloseTo(0.02, 1e-9)
			expect(H:emitsSince(mark, emitter)).toEqual({ 2, 2, 2 })
		end)

		T.itIf(isLune, "setLoop(false) lets a looping effect end", function()
			local p = H:player(loopDef())
			p.player:start()
			H:steps(p.player, 20, 1 / 30)
			expect(p.player.cycle).toBe(1)
			p.player:setLoop(false)
			local alive = true
			for _ = 1, 200 do
				alive = p.player:step(1 / 30)
				if not alive then
					break
				end
			end
			expect(alive).toBe(false)
			expect(p.player.state).toBe("finished")
			expect(p.player.cycle).toBe(1)
		end)
	end)

	T.describe("Player seek", function()
		T.itIf(isLune, "seek(t) gives identical instances from different histories and never emits", function()
			local function fresh(): any
				local p = H:player(Fixtures.full(Json), { quality = "High" }, { cframe = CFrame.new(0, 10, 0) })
				return p
			end
			-- The engine clocks follow the play state (paused -> 0), not the history: compare them separately.
			local CLOCKS = { TimeScale = true, TextureSpeed = true }
			local function state(container: any): any
				local out = {}
				for key, props in H:snapshot(container) do
					local kept = {}
					for name, value in props do
						if not CLOCKS[name] then
							kept[name] = value
						end
					end
					out[key] = kept
				end
				return out
			end
			local function clocks(container: any): { number }
				local out = {}
				for _, inst in container:GetDescendants() do
					if inst:IsA("ParticleEmitter") then
						table.insert(out, (inst :: any).TimeScale)
					elseif inst:IsA("Beam") then
						table.insert(out, (inst :: any).TextureSpeed)
					end
				end
				return out
			end
			local mark = H:emitMark()
			local clears = #ctx.fakes.clears
			local a = fresh()
			a.player:seek(0.5)
			expect(a.player.state).toBe("paused")
			expect(a.player.time).toBe(0.5)
			local snapA = state(a.built.container)
			expect(H:emitsSince(mark)).toEqual({})
			for _, v in clocks(a.built.container) do
				expect(v).toBe(0) -- paused: frozen
			end

			local b = fresh()
			b.player:start()
			H:steps(b.player, 80, DT)
			b.player:fire("Detonate")
			b.player:step(DT)
			local played = #H:emitsSince(mark)
			expect(played > 0).toBe(true)
			local mark2 = H:emitMark()
			b.player:seek(0.5)
			expect(H:emitsSince(mark2)).toEqual({})
			expect(state(b.built.container)).toEqual(snapA)
			expect(b.player.state).toBe("playing")
			a.player:resume()
			expect(clocks(b.built.container)).toEqual(clocks(a.built.container)) -- both playing at rate 1
			expect(H:snapshot(b.built.container)).toEqual(H:snapshot(a.built.container))

			b.player:seek(1.8)
			b.player:seek(0.5)
			expect(state(b.built.container)).toEqual(snapA)
			expect(H:emitsSince(mark2)).toEqual({})
			expect(#ctx.fakes.clears > clears).toBe(true) -- particles were cleared through the controllers

			-- the root and a part are where the composition says
			expect(b.built.root.CFrame).toBeCloseTo(CFrame.new(0, 10, 0), 1e-4)
			-- playback continues from the seeked time; actions at exactly t run with the next step
			b.player:step(DT)
			expect(b.player.time).toBeCloseTo(0.5 + DT, 1e-9)
		end)

		T.itIf(isLune, "seek replays overrides and enable/disable state but no emission", function()
			local def = H:decode([[
{
  "schemaVersion": 1, "id": "replay", "name": "Replay", "duration": 2,
  "components": [
    { "id": "core", "name": "Core", "type": "part", "properties": { "transparency": 0 } },
    { "id": "sparks", "name": "Sparks", "type": "particles", "properties": { "rate": 10 },
      "events": [
        { "id": "e", "time": 0.2, "action": "emit", "count": 9 },
        { "id": "off", "time": 0.4, "action": "disable" }
      ] }
  ],
  "graph": {
    "nodes": [
      { "id": "play", "type": "OnPlay" },
      { "id": "fade", "type": "Tween",
        "params": { "target": "core", "channel": "transparency", "value": 1, "duration": 1, "easing": "Linear" } }
    ],
    "links": [ { "from": "play.out", "to": "fade.in" } ]
  }
}]])
			local p = H:player(def)
			local part = p.built.controllers.core.instances[1]
			local emitter = emitterOf(p, "sparks")
			local mark = H:emitMark()
			p.player:seek(0.75)
			expect(part.Transparency).toBeCloseTo(0.75, 1e-6)
			expect(emitter.Enabled).toBe(false) -- seeking: no continuous emission
			expect(H:emitsSince(mark)).toEqual({})
			p.player:resume()
			p.player:step(0.05) -- playback frame: still disabled by the replayed event
			expect(emitter.Enabled).toBe(false)
			expect(part.Transparency).toBeCloseTo(0.8, 1e-6)
			p.player:seek(0.3)
			p.player:step(0.05)
			expect(emitter.Enabled).toBe(true) -- before the disable event
			expect(H:emitsSince(mark)).toEqual({})
		end)

		T.itIf(isLune, "clamps the seek time and rejects non-finite times", function()
			local p = H:player(burstDef())
			p.player:seek(99)
			expect(p.player.time).toBe(1.5)
			p.player:seek(-3)
			expect(p.player.time).toBe(0)
			expect(function()
				p.player:seek(0 / 0)
			end).toThrow("finite")
		end)
	end)

	T.describe("Player pause, stop and finish", function()
		T.itIf(isLune, "a paused player does not activate anything (no bursts until resumed)", function()
			local def: any = {
				schemaVersion = 1,
				id = "held",
				name = "Held",
				duration = 1,
				components = R({
					id = "sparks",
					name = "Sparks",
					type = "particles",
					properties = { rate = 0, burst = 6 },
				}),
			}
			local p = H:player(def)
			local emitter = emitterOf(p, "sparks")
			local mark = H:emitMark()
			p.player:start()
			p.player:pause()
			H:steps(p.player, 5, DT)
			expect(H:emitsSince(mark, emitter)).toEqual({})
			expect(emitter.Enabled).toBe(false)
			p.player:resume()
			p.player:step(DT)
			expect(H:emitsSince(mark, emitter)).toEqual({ 6 })
		end)

		T.itIf(isLune, "a handler that destroys the player ends the frame's action loop", function()
			local def: any = {
				schemaVersion = 1,
				id = "reentrant",
				name = "Reentrant",
				duration = 1,
				markers = R({ id = "m", time = 0.1, label = "M", event = "Kill" }),
				components = R({
					id = "sparks",
					name = "Sparks",
					type = "particles",
					properties = { rate = 0 },
					events = R({ id = "after", time = 0.1, action = "emit", count = 5 }),
				}),
			}
			local p = H:player(def)
			local mark = H:emitMark()
			-- the marker fire at 0.1 comes after the component event at 0.1 in schedule order; destroy on it, and
			-- also fire a graph-less runtime event (ignored) from inside the handler
			local order: { string } = {}
			p.player.actionExecuted:Connect(function(action: any)
				table.insert(order, action.action)
			end)
			p.player.event:Connect(function(_name: string)
				p.player:fire("Nothing")
				p.player:destroy()
			end)
			p.player:start()
			local alive = true
			for _ = 1, 20 do
				alive = p.player:step(DT)
				if not alive then
					break
				end
			end
			expect(alive).toBe(false)
			expect(order).toEqual({ "emit" }) -- the fire action was cut short with the copy
			expect(H:emitsSince(mark)).toEqual({ 5 })
			expect(p.player.state).toBe("destroyed")
			expect(p.built.destroyed).toBe(true)
		end)

		T.itIf(isLune, "pause freezes time and actions; resume continues", function()
			local p = H:player(burstDef())
			local emitter = emitterOf(p, "sparks")
			local mark = H:emitMark()
			p.player:start()
			H:steps(p.player, 6, DT)
			p.player:pause()
			expect(p.player.state).toBe("paused")
			local t = p.player.time
			H:steps(p.player, 30, DT)
			expect(p.player.time).toBe(t)
			expect(H:emitsSince(mark, emitter)).toEqual({})
			p.player:resume()
			H:steps(p.player, 10, DT)
			expect(H:emitsSince(mark, emitter)).toEqual({ 12 })
		end)

		T.itIf(isLune, "stop() releases emitters, lets particles finish and cleans up after the tail", function()
			local def = {
				schemaVersion = 1,
				id = "stopper",
				name = "Stopper",
				duration = 3,
				components = R({
					id = "sparks",
					name = "Sparks",
					type = "particles",
					properties = { rate = 50, lifetime = { 0.5, 1.5 } },
					events = R({ id = "later", time = 1.0, action = "emit", count = 10 }),
				}),
			}
			local p = H:player(def)
			expect(p.compiled.maxTail).toBe(1.5)
			local emitter = emitterOf(p, "sparks")
			local reasons: { string } = {}
			p.player.finished:Connect(function(reason: string)
				table.insert(reasons, reason)
			end)
			p.player:start()
			H:steps(p.player, 18, DT)
			expect(emitter.Enabled).toBe(true)
			local mark = H:emitMark()
			p.player:stop()
			expect(p.player.state).toBe("stopping")
			expect(emitter.Enabled).toBe(false) -- no new particles, live ones finish
			local frames = frameReaching(DT, 1.5)
			for k = 1, frames do
				local alive = p.player:step(DT)
				if k < frames then
					expect(alive).toBe(true)
					expect(p.built.container.Parent).never.toBeNil()
				else
					expect(alive).toBe(false)
				end
			end
			expect(p.player.state).toBe("finished")
			expect(p.built.destroyed).toBe(true)
			expect(p.built.container.Parent).toBeNil()
			expect(reasons).toEqual({ "finished" })
			expect(H:emitsSince(mark)).toEqual({}) -- the event at 1.0 never ran
			p.player:stop() -- no-op
			p.player:destroy()
			expect(reasons).toEqual({ "finished" })
		end)

		T.itIf(isLune, "stop(fade) lingers for `fade` real seconds; stop(0) finishes at once", function()
			local p = H:player(burstDef())
			p.player:start()
			p.player:step(DT)
			p.player:stop(0.25)
			local frames = frameReaching(DT, 0.25)
			for _ = 1, frames - 1 do
				expect(p.player:step(DT)).toBe(true)
			end
			expect(p.player:step(DT)).toBe(false)

			local q = H:player(burstDef())
			q.player:start()
			q.player:stop(0)
			expect(q.player.state).toBe("finished")
			expect(q.built.destroyed).toBe(true)
			expect(function()
				H:player(burstDef()).player:stop(-1)
			end).toThrow("fade")
		end)

		T.itIf(isLune, "a one-shot effect finishes after duration + tail (real seconds)", function()
			local def = {
				schemaVersion = 1,
				id = "oneshot",
				name = "One Shot",
				duration = 1,
				components = R({
					id = "sparks",
					name = "Sparks",
					type = "particles",
					properties = { rate = 10, lifetime = { 0.2, 0.4 } },
				}),
			}
			local p = H:player(def)
			local finished = 0
			p.player.finished:Connect(function()
				finished += 1
			end)
			p.player:start()
			-- independent emulation of the end rule: tail starts with the overshoot past the end, then += dt
			-- (maxTail is lifetime.Max, a float32 inside NumberRange)
			local limit = p.compiled.maxTail
			expect(limit).toBeCloseTo(0.4, 1e-6)
			local t, tail, expectedFrame = 0, nil :: number?, 0
			for k = 1, 1000 do
				t += DT
				if t >= 1 then
					tail = if tail == nil then t - 1 else (tail :: number) + DT
					if (tail :: number) >= limit then
						expectedFrame = k
						break
					end
				end
			end
			local frame = 0
			for k = 1, 1000 do
				if not p.player:step(DT) then
					frame = k
					break
				end
			end
			expect(frame).toBe(expectedFrame)
			expect(finished).toBe(1)
			expect(p.built.destroyed).toBe(true)
		end)

		T.itIf(isLune, "timeScale scales the effect time", function()
			local def = burstDef()
			def.timeScale = 2
			local p = H:player(def, nil, { timeScale = 0.25 })
			p.player:start()
			H:steps(p.player, 10, 0.1)
			expect(p.player.time).toBeCloseTo(0.5, 1e-9) -- 1 s × 0.25 × 2
			p.player:setTimeScale(1)
			p.player:step(0.1)
			expect(p.player.time).toBeCloseTo(0.7, 1e-9)
			expect(function()
				p.player:setTimeScale(-1)
			end).toThrow("setTimeScale")
		end)

		local function scaledDef(): any
			return {
				schemaVersion = 1,
				id = "scaled",
				name = "Scaled",
				duration = 2,
				timeScale = 0.5,
				components = R(
					{ id = "sparks", name = "Sparks", type = "particles", properties = { rate = 10, timeScale = 0.8 } },
					{ id = "ray", name = "Ray", type = "beam", properties = { textureSpeed = 2 } },
					{ id = "core", name = "Core", type = "part" }
				),
			}
		end

		T.itIf(
			isLune,
			"propagates the effective time scale to the controllers (start, pause, resume, setTimeScale, seek)",
			function()
				local p = H:player(scaledDef(), nil, { timeScale = 0.5 })
				local emitter = emitterOf(p, "sparks")
				local beam = p.built.controllers.ray.instances[1]
				local calls: { number } = {}
				local controller = p.built.controllers.sparks
				local original = controller.setTimeScale
				controller.setTimeScale = function(self: any, scale: number)
					table.insert(calls, scale)
					original(self, scale)
				end
				-- built with the definition's timeScale only
				expect(emitter.TimeScale).toBeCloseTo(0.4) -- 0.8 × 0.5
				expect(beam.TextureSpeed).toBeCloseTo(1) -- 2 × 0.5
				p.player:start() -- rate 0.25 = 0.5 (definition) × 0.5 (option)
				expect(emitter.TimeScale).toBeCloseTo(0.2)
				expect(beam.TextureSpeed).toBeCloseTo(0.5)
				H:steps(p.player, 5, DT)
				expect(calls).toEqual({ 0.25 }) -- once per change, not per frame
				p.player:pause()
				expect(emitter.TimeScale).toBe(0) -- the engine freezes live particles
				expect(beam.TextureSpeed).toBe(0)
				p.player:setTimeScale(2) -- remembered, but the copy stays frozen while paused
				p.player:step(DT)
				expect(emitter.TimeScale).toBe(0)
				p.player:resume() -- rate 1
				expect(emitter.TimeScale).toBeCloseTo(0.8)
				expect(beam.TextureSpeed).toBeCloseTo(2)
				p.player:setTimeScale(6) -- rate 3: particles stop at the engine maximum 1, beams scroll faster
				expect(emitter.TimeScale).toBeCloseTo(1)
				expect(beam.TextureSpeed).toBeCloseTo(6)
				expect(calls).toEqual({ 0.25, 0, 1, 3 })
				-- seek resets the copy to its built state and applies the current scale again
				p.player:seek(0.5)
				expect(emitter.TimeScale).toBeCloseTo(1)
				expect(beam.TextureSpeed).toBeCloseTo(6)
				p.player:pause()
				p.player:seek(0.75)
				expect(emitter.TimeScale).toBe(0)
				expect(beam.TextureSpeed).toBe(0)
				p.player:setTimeScale(0) -- a zero time scale freezes like a pause
				p.player:resume()
				expect(emitter.TimeScale).toBe(0)
				expect(beam.TextureSpeed).toBe(0)
				p.player:setTimeScale(1)
				expect(emitter.TimeScale).toBeCloseTo(0.4)
				expect(beam.TextureSpeed).toBeCloseTo(1)
				p.player:destroy()
				local n = #calls
				p.player:setTimeScale(2)
				expect(#calls).toBe(n) -- nothing reaches a released copy
			end
		)

		T.itIf(isLune, "stop() of a paused effect unfreezes the engine clocks so live particles can finish", function()
			local p = H:player(scaledDef())
			p.player:start()
			p.player:step(DT)
			p.player:pause()
			expect(emitterOf(p, "sparks").TimeScale).toBe(0)
			p.player:stop()
			expect(p.player.state).toBe("stopping")
			expect(emitterOf(p, "sparks").TimeScale).toBeCloseTo(0.4) -- 0.8 × 0.5 (rate)
			expect(p.built.controllers.ray.instances[1].TextureSpeed).toBeCloseTo(1)
		end)

		T.itIf(isLune, "an Autoplay-style pause right after start() freezes the copy before its first frame", function()
			local p = H:player(scaledDef())
			p.player:start()
			p.player:pause()
			expect(emitterOf(p, "sparks").TimeScale).toBe(0)
			p.player:resume()
			expect(emitterOf(p, "sparks").TimeScale).toBeCloseTo(0.4)
		end)

		T.itIf(
			isLune,
			"the tail and the stop linger follow the effective rate (particles age at min(1, rate))",
			function()
				local function tailDef(): any
					return {
						schemaVersion = 1,
						id = "tail",
						name = "Tail",
						duration = 1,
						components = R({
							id = "sparks",
							name = "Sparks",
							type = "particles",
							properties = { rate = 10, lifetime = { 0.4, 0.4 } },
						}),
					}
				end
				-- rate 0.5: the effect ends after 2 real seconds (8 × 0.25), particles live 0.8 real seconds
				local p = H:player(tailDef(), nil, { timeScale = 0.5 })
				p.player:start()
				local alive = {}
				for _ = 1, 12 do
					table.insert(alive, p.player:step(0.25))
				end
				-- steps 9-11 are the tail (0, 0.25, 0.5, 0.75 s); a rate-independent tail of 0.4 s would end at step 10
				expect(alive).toEqual({ true, true, true, true, true, true, true, true, true, true, true, false })

				-- stop(): the default linger is the tail at the current rate
				local q = H:player(tailDef(), nil, { timeScale = 0.5 })
				q.player:start()
				q.player:step(0.25)
				q.player:stop()
				expect({ q.player:step(0.25), q.player:step(0.25), q.player:step(0.25), q.player:step(0.25) }).toEqual({
					true,
					true,
					true,
					false,
				})
				-- faster than real time: particles cannot age faster than 1, so the tail is the lifetime
				local r = H:player(tailDef(), nil, { timeScale = 0.5 })
				r.player:start()
				r.player:setTimeScale(6)
				r.player:step(0.25)
				r.player:stop()
				expect({ r.player:step(0.25), r.player:step(0.25) }).toEqual({ true, false })
			end
		)

		T.itIf(isLune, "destroy() is immediate and idempotent; options.release can take the copy", function()
			local taken: any = nil
			local p = H:player(burstDef(), nil, {
				release = function(built: any): boolean
					taken = built
					return true
				end,
			})
			local reasons: { string } = {}
			p.player.finished:Connect(function(reason: string)
				table.insert(reasons, reason)
			end)
			p.player:start()
			p.player:step(DT)
			p.player:destroy()
			p.player:destroy()
			expect(p.player.state).toBe("destroyed")
			expect(taken).toBe(p.built)
			expect(p.built.destroyed).toBe(false) -- the release callback owns it now
			expect(reasons).toEqual({ "destroyed" })
			expect(p.player:step(DT)).toBe(false)
			p.built:destroy()

			-- a release callback that declines (or fails) leaves the copy to be destroyed
			local q = H:player(burstDef(), nil, {
				release = function(_built: any): boolean
					error("pool exploded")
				end,
			})
			q.player:start()
			q.player:destroy()
			expect(q.built.destroyed).toBe(true)
		end)

		T.itIf(isLune, "autoRelease = false keeps the instances after the end so seek can revive the player", function()
			local p = H:player(burstDef(), nil, { autoRelease = false })
			p.player:start()
			local alive = true
			while alive do
				alive = p.player:step(0.1)
			end
			expect(p.player.state).toBe("finished")
			expect(p.built.destroyed).toBe(false)
			p.player:seek(0.25)
			expect(p.player.state).toBe("paused")
			expect(p.player.time).toBe(0.25)
			p.player:destroy()
			expect(p.built.destroyed).toBe(true)
		end)
	end)

	T.describe("Player.new", function()
		T.it("validates its arguments", function()
			local compiled = H:compile(burstDef())
			local built = use("AstraVFX.Core.Builder").build(compiled)
			table.insert(H.created, built.container)
			expect(function()
				Player.new(nil :: any, built)
			end).toThrow("CompiledEffect")
			expect(function()
				Player.new(compiled, nil :: any)
			end).toThrow("BuiltEffect")
			expect(function()
				Player.new(compiled, built, { cframe = Vector3.zero } :: any)
			end).toThrow("cframe")
			expect(function()
				Player.new(compiled, built, { timeScale = -1 })
			end).toThrow("timeScale")
			expect(function()
				Player.new(compiled, built, { attach = "part" } :: any)
			end).toThrow("attach")
			local other = H:compile(Fixtures.full(Json))
			expect(function()
				Player.new(other, built)
			end).toThrow("no controller")
			local player = Player.new(compiled, built)
			expect(player.state).toBe("idle")
			expect(player:step(DT)).toBe(true) -- idle players wait for start()
			expect(player.time).toBe(0)
			built:destroy()
			expect(function()
				Player.new(compiled, built)
			end).toThrow("destroyed")
		end)
	end)
end
