--!strict
--[[
	ComponentsCameraRuntime — the camera components (cameraShake, screenFlash; docs/COMPONENTS_SPEC.md §17-18)
	end to end through the public runtime API: Validation and the Compiler accept them as they are (no
	camera-specific code), and AstraVFX.Play → Builder → Player → Scheduler drives them on a simulated client and
	on a server.

	Setup: the real (Lune) Workspace with a fresh test Camera as CurrentCamera (restored afterwards). A client is
	simulated with Env.override("Players", { LocalPlayer = … }); the server is Lune's real Players service
	(LocalPlayer = nil). Frames are `ctx.fakes:step(DT)`: PreRender / RenderStepped, the render-step bindings
	(tests/lune/Fakes.luau), then Heartbeat (the Scheduler steps the Players). On the client a stand-in for the
	default camera scripts is bound at Enum.RenderPriority.Camera and sets the camera to `scripted` every frame,
	so "unshaken" means camera.CFrame == scripted.

	Expectations per frame follow the timing rules: a component is active for player times t with
	startTime <= t < endTime (Timeline.isActive). A shake is bound while active; the camera shows its offset in a
	frame whose render step ran while it was active (render runs before the Heartbeat that may end it).
]]

return function(T: any, use: (string) -> any, ctx: any)
	local AstraVFX = use("AstraVFX")
	local Common = use("AstraVFX.Core.Components.Common")
	local Compiler = use("AstraVFX.Core.Compiler")
	local Env = use("AstraVFX.Core.Env")
	local Pool = use("AstraVFX.Core.Pool")
	local Scheduler = use("AstraVFX.Core.Scheduler")
	local Validation = use("AstraVFX.Core.Validation")
	local expect = T.expect
	local isLune = ctx.environment == "lune"
	local fakes = ctx.fakes

	local DT = 1 / 60
	local RAD = math.pi / 180
	local CAMERA_SCRIPT = "AstraVFXSpec_CameraScript"
	local HIT = Color3.fromRGB(255, 32, 64)
	local BLUE = Color3.fromRGB(32, 64, 255)
	local WHITE = Color3.new(1, 1, 1)

	-- Shake: [0.1, 0.6), amplitude track 8 → 2. Flash: [0.2, 0.6), envelope 0.05 / 0.1 / 0.2 (ends at 0.55),
	-- tint "$hit" until local 0.15 (Constant), then blue. Sparks give the effect a particle tail.
	local SHAKE_START, SHAKE_END = 0.1, 0.6
	local FLASH_START, FLASH_END = 0.2, 0.6
	local FLASH_ATTACK, FLASH_HOLD, FLASH_DECAY = 0.05, 0.1, 0.2
	local AMPLITUDE_FROM, AMPLITUDE_TO = 8, 2
	local POSITION_AMPLITUDE = 0.5
	local WEIGHTS = Vector3.new(1, 0.6, 0.3)

	local function definition(id: string?, duration: number?): any
		return {
			schemaVersion = 1,
			id = id or "cameraHit",
			name = if id then id else "Camera Hit",
			duration = duration or 1,
			palette = { hit = "#FF2040" },
			components = {
				{
					id = "sparks",
					name = "Sparks",
					type = "particles",
					properties = { rate = 0, burst = 0, lifetime = { 0.5, 0.5 } },
					events = { { id = "pop", time = 0, action = "emit", count = 5 } },
				},
				{
					id = "shake",
					name = "Shake",
					type = "cameraShake",
					startTime = SHAKE_START,
					duration = SHAKE_END - SHAKE_START,
					properties = {
						amplitude = AMPLITUDE_FROM,
						positionAmplitude = POSITION_AMPLITUDE,
						frequency = 12,
						attack = 0.05,
						decay = 0.2,
						decayEasing = "Quad.Out",
						rotationWeights = { WEIGHTS.X, WEIGHTS.Y, WEIGHTS.Z },
						innerRadius = 50,
						outerRadius = 200,
					},
					tracks = {
						{
							id = "calm",
							channel = "amplitude",
							keyframes = {
								{ time = 0, value = AMPLITUDE_FROM },
								{ time = SHAKE_END - SHAKE_START, value = AMPLITUDE_TO },
							},
						},
					},
				},
				{
					id = "flash",
					name = "Impact Frame",
					type = "screenFlash",
					startTime = FLASH_START,
					duration = FLASH_END - FLASH_START,
					properties = {
						brightness = 0.25,
						contrast = 1.5,
						saturation = -1,
						tint = "$hit",
						attack = FLASH_ATTACK,
						hold = FLASH_HOLD,
						decay = FLASH_DECAY,
					},
					tracks = {
						{
							id = "tintTrack",
							channel = "tint",
							keyframes = {
								{ time = 0, value = "$hit", easing = "Constant" },
								{ time = FLASH_ATTACK + FLASH_HOLD, value = "#2040FF" },
							},
						},
					},
				},
			},
		}
	end

	local function flashEnvelope(lt: number): number
		if lt < 0 then
			return 0
		elseif lt < FLASH_ATTACK then
			return lt / FLASH_ATTACK
		elseif lt < FLASH_ATTACK + FLASH_HOLD then
			return 1
		end
		return math.max(1 - (lt - FLASH_ATTACK - FLASH_HOLD) / FLASH_DECAY, 0)
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- Setup
	-- ─────────────────────────────────────────────────────────────────────────

	local workspaceService: any = nil
	local originalCamera: Camera? = nil
	local camera: Camera = Instance.new("Camera")
	local home = CFrame.new()
	local scripted = CFrame.new()
	local scriptBound = false

	T.beforeEach(function()
		AstraVFX._reset()
		Scheduler.clear()
		Env.override("Workspace", nil)
		Env.override("Players", nil)
		workspaceService = Env.getService("Workspace")
		originalCamera = workspaceService.CurrentCamera
		camera = Instance.new("Camera")
		camera.Name = "CameraRuntimeSpecCamera"
		camera.CFrame = CFrame.new(0, 6, 30) * CFrame.Angles(-0.15, 0.05, 0)
		camera.Parent = workspaceService
		workspaceService.CurrentCamera = camera
		home = camera.CFrame
		scripted = home
		scriptBound = false
	end)

	T.afterEach(function()
		AstraVFX._reset()
		Scheduler.clear()
		Pool.setCapacity(Pool.DEFAULT_CAPACITY)
		if scriptBound then
			Env.getService("RunService"):UnbindFromRenderStep(CAMERA_SCRIPT)
		end
		Env.override("Players", nil)
		if originalCamera ~= nil then
			workspaceService.CurrentCamera = originalCamera
		end
		camera:Destroy()
	end)

	local function asClient()
		Env.override("Players", { LocalPlayer = { Name = "CameraRuntimeSpecPlayer" } })
		expect(Common.hasLocalPlayer()).toBe(true)
	end

	-- Stand-in for the default camera scripts: an absolute camera CFrame every render step.
	local function bindCameraScript(cf: CFrame)
		camera.CFrame = cf
		scripted = camera.CFrame -- the value as stored (Lune rounds on the first write)
		Env.getService("RunService"):BindToRenderStep(CAMERA_SCRIPT, Enum.RenderPriority.Camera.Value, function()
			camera.CFrame = scripted
		end)
		scriptBound = true
	end

	local function astraBindings(): number
		local n = 0
		for name in fakes.renderBindings do
			if string.sub(name, 1, 9) == "AstraVFX_" then
				n += 1
			end
		end
		return n
	end

	local function effectsUnderCamera(): { ColorCorrectionEffect }
		local out = {}
		for _, inst in camera:GetDescendants() do
			if inst:IsA("ColorCorrectionEffect") then
				table.insert(out, inst :: ColorCorrectionEffect)
			end
		end
		return out
	end

	local function postEffectsAnywhere(): number
		local n = 0
		for _, inst in workspaceService:GetDescendants() do
			if inst:IsA("PostEffect") then
				n += 1
			end
		end
		return n
	end

	local function frame(): number
		fakes:step(DT)
		return 0
	end

	-- Steps until the handle's time reaches `t` (at most 600 frames).
	local function stepTo(handle: any, t: number)
		for _ = 1, 600 do
			if handle:GetTime() >= t then
				return
			end
			frame()
		end
		error("stepTo: time " .. t .. " not reached", 2)
	end

	local function expectEffect(effect: any, e: number, tint: Color3, label: string)
		local function near(actual: number, wanted: number, what: string)
			if math.abs(actual - wanted) > 1e-5 then
				error(string.format("%s %s: got %.6f, expected %.6f", label, what, actual, wanted), 3)
			end
		end
		near(effect.Brightness, 0.25 * e, "Brightness")
		near(effect.Contrast, 1.5 * e, "Contrast")
		near(effect.Saturation, -1 * e, "Saturation")
		local c: Color3 = effect.TintColor
		near(c.R, 1 + (tint.R - 1) * e, "TintColor.R")
		near(c.G, 1 + (tint.G - 1) * e, "TintColor.G")
		near(c.B, 1 + (tint.B - 1) * e, "TintColor.B")
		expect(effect.Enabled).toBe(true)
		expect(effect.Archivable).toBe(false)
	end

	-- ─────────────────────────────────────────────────────────────────────────
	-- Validation + Compiler (no camera-specific code in either)
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsCameraRuntime validation and compile", function()
		T.it("Validation accepts both camera types without diagnostics", function()
			local result, migrated = AstraVFX.Validate(definition())
			expect(result.ok).toBe(true)
			expect(result.errors).toEqual({})
			expect(result.warnings).toEqual({})
			expect(migrated).never.toBeNil()
			expect(Validation.validate(definition()).ok).toBe(true)
		end)

		T.it("Validation reports bad camera values through the generic descriptor checks", function()
			local def = definition()
			def.components[2].properties.amplitude = 50
			def.components[2].properties.decayEasing = "Wobbly.Sideways"
			def.components[2].tracks[1].keyframes[2].value = "loud"
			def.components[3].properties.contrast = 9
			def.components[3].tracks[1].keyframes[2].value = 12
			local result = Validation.validate(def)
			expect(result.ok).toBe(false)
			local paths: { [string]: boolean } = {}
			for _, d in result.errors do
				paths[d.path] = true
			end
			expect(paths["components[2].properties.amplitude"]).toBe(true)
			expect(paths["components[2].properties.decayEasing"]).toBe(true)
			expect(paths["components[2].tracks[1].keyframes[2].value"]).toBe(true)
			expect(paths["components[3].properties.contrast"]).toBe(true)
			expect(paths["components[3].tracks[1].keyframes[2].value"]).toBe(true)
		end)

		T.it("the Compiler decodes, scales and schedules them like any other component", function()
			local compiled = Compiler.compile(definition(), { quality = "Low", scale = 2 })
			local shake = compiled.byId.shake
			local flash = compiled.byId.flash
			expect(shake).never.toBeNil()
			expect(flash).never.toBeNil()
			expect(shake.startTime).toBe(SHAKE_START)
			expect(shake.endTime).toBeCloseTo(SHAKE_END, 1e-9)
			-- scale = "length" properties × effect scale; the rest unchanged
			expect(shake.props.positionAmplitude).toBeCloseTo(POSITION_AMPLITUDE * 2, 1e-9)
			expect(shake.props.innerRadius).toBeCloseTo(100, 1e-9)
			expect(shake.props.outerRadius).toBeCloseTo(400, 1e-9)
			expect(shake.props.amplitude).toBe(AMPLITUDE_FROM)
			expect(shake.props.frequency).toBe(12)
			expect(shake.props.decayEasing).toBe("Quad.Out")
			expect(shake.props.rotationWeights).toBeCloseTo(WEIGHTS, 1e-9)
			expect(shake.props.previewInStudio).toBe(false)
			expect(shake.tracks.amplitude.kind).toBe("number")
			-- palette references decode to Color3 in properties and keyframes
			expect(flash.props.tint).toBeCloseTo(HIT, 1e-6)
			expect(flash.props.contrast).toBe(1.5)
			expect(flash.tracks.tint.kind).toBe("color3")
			expect(flash.tracks.tint.keys[1].value).toBeCloseTo(HIT, 1e-6)
			expect(flash.tracks.tint.keys[1].constant).toBe(true)
			expect(compiled.maxTail).toBeCloseTo(0.5, 1e-9) -- the sparks only: camera types have no tail
		end)
	end)

	-- ─────────────────────────────────────────────────────────────────────────
	-- Playback through AstraVFX.Play
	-- ─────────────────────────────────────────────────────────────────────────

	T.describe("ComponentsCameraRuntime playback", function()
		T.itIf(isLune, "a client: Play shakes the camera and flashes the screen exactly during their spans", function()
			asClient()
			bindCameraScript(CFrame.new(0, 8, 24) * CFrame.Angles(-0.3, 0.2, 0))
			expect(AstraVFX.Register(definition())).toBe("Camera Hit")
			local handle = AstraVFX.Play("Camera Hit", { Position = Vector3.new(0, 0, 10), Scale = 2 })
			local container = handle._player.built.container
			expect(container.Parent).toBe(workspaceService)
			expect(astraBindings()).toBe(0)
			local wasActive = false
			local sawShake, sawFlash, sawBlue = 0, 0, 0
			local finished: string? = nil
			handle.Finished:Connect(function(reason: string)
				finished = reason
			end)
			for i = 1, 200 do
				frame()
				local t: number = handle:GetTime()
				local state = handle:GetState()
				local active = state == "playing" and t >= SHAKE_START and t < SHAKE_END
				local label = string.format("frame %d (t = %.4f)", i, t)
				-- shake: bound exactly while active, camera offset while it was active through the render step
				expect({ label, astraBindings() }).toEqual({ label, if active then 2 else 0 })
				if active and wasActive then
					expect({ label, camera.CFrame ~= scripted }).toEqual({ label, true })
					sawShake += 1
					local lt = t - DT - SHAKE_START -- the local time the render step used (previous Heartbeat)
					local amplitude = AMPLITUDE_FROM + (AMPLITUDE_TO - AMPLITUDE_FROM) * lt / (SHAKE_END - SHAKE_START)
					local offset = scripted:Inverse() * camera.CFrame
					local rx, ry, rz = offset:ToOrientation()
					local limit = amplitude * RAD + 1e-4
					expect(math.abs(rx) <= limit * WEIGHTS.X).toBe(true)
					expect(math.abs(ry) <= limit * WEIGHTS.Y).toBe(true)
					expect(math.abs(rz) <= limit * WEIGHTS.Z).toBe(true)
					local p = offset.Position
					local pLimit = POSITION_AMPLITUDE * 2 + 1e-3 -- positionAmplitude × Scale
					expect(math.max(math.abs(p.X), math.abs(p.Y), math.abs(p.Z)) <= pLimit).toBe(true)
				elseif not active then
					expect({ label, camera.CFrame == scripted }).toEqual({ label, true })
				end
				wasActive = active
				-- flash: exists only while its envelope is above 0, values follow the envelope and the tint track
				local lt = t - FLASH_START
				local flashActive = state == "playing" and t >= FLASH_START and t < FLASH_END
				local e = if flashActive then flashEnvelope(lt) else 0
				local list = effectsUnderCamera()
				expect({ label, #list }).toEqual({ label, if e > 1e-9 then 1 else 0 })
				if #list == 1 and math.abs(lt - (FLASH_ATTACK + FLASH_HOLD)) > 1e-6 then
					local tint = if lt < FLASH_ATTACK + FLASH_HOLD then HIT else BLUE
					expectEffect(list[1], e, tint, label)
					expect(list[1]:GetAttribute("AstraComponent")).toBe("flash")
					sawFlash += 1
					if tint == BLUE then
						sawBlue += 1
					end
				end
				-- nothing of the camera types ever lives in the container
				for _, inst in container:GetDescendants() do
					local owner = inst:GetAttribute("AstraComponent")
					expect(owner ~= "shake" and owner ~= "flash").toBe(true)
				end
				if finished then
					break
				end
			end
			expect(finished).toBe("finished")
			expect(sawShake).toBeGreaterThan(20)
			expect(sawFlash).toBeGreaterThan(10)
			expect(sawBlue).toBeGreaterThan(3)
			-- after the end: no binding, no effect, camera untouched, nothing left playing
			expect(astraBindings()).toBe(0)
			expect(postEffectsAnywhere()).toBe(0)
			expect(AstraVFX.ActiveCount()).toBe(0)
			frame()
			expect(camera.CFrame).toBe(scripted)
		end)

		T.itIf(isLune, "a server: the same effect plays without bindings, camera writes or post effects", function()
			local players: any = Env.getService("Players")
			expect(players.LocalPlayer).toBeNil()
			expect(Common.hasLocalPlayer()).toBe(false)
			AstraVFX.Register(definition())
			local handle = AstraVFX.Play("Camera Hit", { Position = Vector3.new(0, 0, 10) })
			local log = #fakes.renderLog
			local finished: string? = nil
			handle.Finished:Connect(function(reason: string)
				finished = reason
			end)
			local reachedShake = false
			for _ = 1, 200 do
				frame()
				if handle:GetTime() >= SHAKE_START + 0.1 then
					reachedShake = true
				end
				expect(camera.CFrame).toBe(home)
				expect(postEffectsAnywhere()).toBe(0)
				expect(#camera:GetChildren()).toBe(0)
				if finished then
					break
				end
			end
			expect(reachedShake).toBe(true)
			expect(finished).toBe("finished")
			expect(#fakes.renderLog).toBe(log) -- not a single BindToRenderStep / UnbindFromRenderStep
			expect(AstraVFX.ActiveCount()).toBe(0)
		end)

		T.itIf(isLune, "Stop, Destroy, Seek and pooled replays always release the camera at once", function()
			asClient()
			bindCameraScript(CFrame.new(3, 7, 20) * CFrame.Angles(-0.2, -0.4, 0))
			AstraVFX.Register(definition())
			-- Stop mid-effect: bindings and the post effect go immediately, the camera is the script's again
			local a = AstraVFX.Play("Camera Hit", { Position = Vector3.new(0, 0, 10) })
			stepTo(a, 0.3)
			expect(astraBindings()).toBe(2)
			expect(#effectsUnderCamera()).toBe(1)
			expect(camera.CFrame ~= scripted).toBe(true)
			a:Stop()
			expect(astraBindings()).toBe(0)
			expect(#effectsUnderCamera()).toBe(0)
			expect(camera.CFrame).toBe(scripted)
			for _ = 1, 10 do
				frame()
				expect(astraBindings()).toBe(0)
				expect(#effectsUnderCamera()).toBe(0)
				expect(camera.CFrame).toBe(scripted)
			end
			for _ = 1, 60 do
				frame()
			end
			expect(a:GetState()).toBe("finished")
			-- the copy went back to the pool; a replay reuses it and works again
			expect(Pool.count()).toBe(1)
			local b = AstraVFX.Play("Camera Hit", { Position = Vector3.new(0, 0, 10) })
			expect(Pool.count()).toBe(0)
			stepTo(b, 0.3)
			expect(astraBindings()).toBe(2)
			expect(#effectsUnderCamera()).toBe(1)
			-- Seek back before both spans, then into them again (deterministic state, no stale bindings)
			b:Seek(0.05)
			expect(astraBindings()).toBe(0)
			expect(#effectsUnderCamera()).toBe(0)
			expect(camera.CFrame).toBe(scripted)
			b:Seek(0.3)
			expect(astraBindings()).toBe(2)
			local list = effectsUnderCamera()
			expect(#list).toBe(1)
			expectEffect(list[1], 1, HIT, "after Seek(0.3)") -- local 0.1: hold, tint still "$hit"
			-- Destroy mid-effect
			b:Destroy()
			expect(astraBindings()).toBe(0)
			expect(#effectsUnderCamera()).toBe(0)
			expect(camera.CFrame).toBe(scripted)
			frame()
			expect(camera.CFrame).toBe(scripted)
			expect(AstraVFX.ActiveCount()).toBe(0)
		end)

		T.itIf(isLune, "spans that end with the effect release the camera before the particle tail ends", function()
			asClient()
			bindCameraScript(CFrame.new(0, 5, 18))
			local def = definition("tailHit", SHAKE_END) -- duration = both spans' end
			AstraVFX.Register(def)
			local handle = AstraVFX.Play("tailHit", { Position = Vector3.new(0, 0, 5) })
			stepTo(handle, 0.3)
			expect(astraBindings()).toBe(2)
			stepTo(handle, SHAKE_END)
			expect(handle:GetState()).toBe("playing") -- waiting for the sparks' tail
			expect(astraBindings()).toBe(0)
			expect(#effectsUnderCamera()).toBe(0)
			frame()
			expect(camera.CFrame).toBe(scripted)
			expect(handle:GetState()).toBe("playing")
		end)

		T.itIf(isLune, "concurrent plays share one binding pair until the last one ends", function()
			asClient()
			bindCameraScript(CFrame.new(0, 5, 18))
			AstraVFX.Register(definition())
			local first = AstraVFX.Play("Camera Hit", { Position = Vector3.new(0, 0, 0) })
			stepTo(first, 0.2)
			local second = AstraVFX.Play("Camera Hit", { Position = Vector3.new(4, 0, 0) })
			for _ = 1, 3 do
				frame()
			end
			expect(astraBindings()).toBe(2)
			expect(#effectsUnderCamera()).toBe(2) -- one post effect per flash; the engine combines them
			stepTo(first, SHAKE_END)
			expect(second:GetTime() < SHAKE_END).toBe(true)
			expect(astraBindings()).toBe(2) -- still shaking for the second play
			stepTo(second, SHAKE_END)
			expect(astraBindings()).toBe(0)
			frame()
			expect(camera.CFrame).toBe(scripted)
			expect(#effectsUnderCamera()).toBe(0)
		end)

		T.itIf(isLune, "a camera beyond outerRadius (× Scale) is not shaken, inside it is", function()
			asClient()
			bindCameraScript(CFrame.new(0, 5, 18))
			AstraVFX.Register(definition())
			-- outerRadius 200 studs: an effect 500 studs away binds (it is active) but writes nothing
			local far = AstraVFX.Play("Camera Hit", { Position = Vector3.new(500, 0, 0) })
			stepTo(far, 0.3)
			expect(astraBindings()).toBe(2)
			expect(camera.CFrame).toBe(scripted)
			far:Destroy()
			-- Scale 3 → outerRadius 600: the same position is now inside the falloff
			local scaled = AstraVFX.Play("Camera Hit", { Position = Vector3.new(500, 0, 0), Scale = 3 })
			stepTo(scaled, 0.3)
			frame()
			expect(camera.CFrame ~= scripted).toBe(true)
			scaled:Destroy()
			expect(camera.CFrame).toBe(scripted)
		end)

		T.itIf(isLune, "a looping effect rebinds every cycle and leaves nothing behind when destroyed", function()
			asClient()
			bindCameraScript(CFrame.new(0, 5, 18))
			AstraVFX.Register(definition())
			local handle = AstraVFX.Play("Camera Hit", { Position = Vector3.new(0, 0, 0), Loop = true })
			local cyclesWithShake: { [number]: boolean } = {}
			local cyclesWithFlash: { [number]: boolean } = {}
			for _ = 1, 160 do
				frame()
				local cycle = handle._player.cycle
				if astraBindings() == 2 then
					cyclesWithShake[cycle] = true
				end
				if #effectsUnderCamera() == 1 then
					cyclesWithFlash[cycle] = true
				end
			end
			expect(cyclesWithShake[0] and cyclesWithShake[1]).toBe(true)
			expect(cyclesWithFlash[0] and cyclesWithFlash[1]).toBe(true)
			handle:Destroy()
			expect(astraBindings()).toBe(0)
			expect(#effectsUnderCamera()).toBe(0)
			frame()
			expect(camera.CFrame).toBe(scripted)
		end)
	end)
end
