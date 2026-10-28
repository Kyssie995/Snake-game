--!strict
--[[
	cameraShake — client-side camera shake (docs/COMPONENTS_SPEC.md §17). Builds no instances, ever.

	Offset (camera space) at local time t, with S = component span (endTime − startTime):
	  strength s(t, d) = envelope(t) × falloff(d)
	  envelope(t)      = clamp(min(rise, fall), 0, 1); 0 for t < 0 and t >= S
	                       rise = min(t / attack, 1)                     (attack = 0: 1)
	                       fall = 1 − decayEasing(p), p = (t − (S − decay)) / decay, during the last `decay` seconds
	                              of the span (1 before that; decay = 0: 1 until the span ends)
	                     Overlapping attack and decay take the smaller value (the peak then stays below 1).
	  falloff(d)       = 1 for d <= innerRadius, linear to 0 at outerRadius, 0 beyond (outerRadius <= innerRadius:
	                     hard edge at innerRadius). d = distance from the camera (its unshaken CFrame) to the
	                     component's world position.
	  noise_a(u)       = Σ_k w_k · sin(2π · (r_a,k · u + φ_a,k)) / Σ_k w_k    (|noise| <= 1, smooth, zero-mean)
	                     u = t × frequency, six axes a (pitch, yaw, roll, x, y, z), three sines k each:
	                     w = (1, 0.6, 0.35), r_a,k = (1, 0.59, 0.31)_k × (1 ± 0.1, seed-derived),
	                     φ_a,k in [0, 1) seed-derived (Core/Random seeded with the component seed) → repeatable.
	  rotation         = amplitude × s × (weights.X · noise_pitch, weights.Y · noise_yaw, weights.Z · noise_roll) deg
	  position         = positionAmplitude × scale × s × (noise_x, noise_y, noise_z) studs
	  offset           = CFrame.new(position) × CFrame.fromOrientation(rotation in radians)
	`amplitude` is the rest value of the `amplitude` channel (rotation degrees; positionAmplitude is not animated).
	transform.scale multiplies positionAmplitude and both radii (the effect scale is already applied by the Compiler).
	The fastest noise component runs at `frequency` itself (the other sines are slower wander).

	Mixer. All active shakes of one kind (client / preview) share a module-level mixer that owns the camera writes:
	  apply:   current = Camera.CFrame; base = the remembered base if Camera.CFrame still holds the mixer's last
	           write; current × (last offset)⁻¹ if someone else moved the camera since that write (Studio
	           navigation may move relative to what the camera showed: taking the offset out keeps the error within
	           one offset whether the mover was relative or absolute, instead of folding the shake into the base
	           every frame); current when there is no write to compare with (the client's undo step cleared it).
	           Camera.CFrame = base × offset₁ × offset₂ × … (shakes in activation order).
	  restore: if Camera.CFrame still holds the mixer's last write, put the base back.
	So concurrent shakes (several hits at once) compose instead of fighting over the camera, and offsets never
	accumulate. Camera.CFrame is written only when the target differs; the value read back after a write is what
	"still holds the last write" compares against (property storage may round — Lune's does).

	Where it runs:
	  * Client at runtime (not ctx.isPreview, Players.LocalPlayer ~= nil). While at least one client shake is active
	    the mixer holds two render-step bindings (RunService:BindToRenderStep — client only, lower priority runs
	    earlier; docs/ROBLOX_API_CONSTRAINTS.md §12):
	      "AstraVFX_Shake_<token>_<n>"      at Enum.RenderPriority.Camera.Value + 1 (after the default camera
	                                        scripts): apply;
	      "AstraVFX_ShakeUndo_<token>_<n>"  at Camera.Value − 1 (before them): restore.
	    The undo binding is an addition to the spec. The camera scripts recompute Camera.CFrame every frame, but the
	    default PlayerModule cameras derive the next look direction from Camera.CFrame.LookVector (BaseCamera
	    GetCameraLookVector — ASSUMPTION, not verified in this repository), so a rotation left in place would feed
	    back into the next frame and drift the view. Both are unbound (UnbindFromRenderStep; does not throw for
	    unknown names — VERIFIED) when the last client shake deactivates, is released, reset or destroyed, and the
	    camera is restored. <token> distinguishes copies of the runtime module (e.g. in Actors), <n> counts binds.
	  * Server / no local player: no-op (no bindings, no camera writes).
	  * Preview (ctx.isPreview): only when previewInStudio is true and workspace.CurrentCamera exists. No bindings:
	    the base is captured at activation and every update() re-applies base × offsets (Studio's edit camera is not
	    driven by camera scripts). If the author moves the camera meanwhile (Camera.CFrame no longer holds the last
	    write) the moved CFrame without the last offset becomes the base instead of being snapped back. When the
	    last preview shake stops, the base is restored — only while Camera.CFrame still holds the last write.
	  * Viewport builds: never (supportsViewport = false; the Builder uses a placeholder anyway).
	The offset at a local time depends only on (t, seed, props, amplitude channel, distance) — scrubbing is exact.
]]

local Common = require(script.Parent.Common)
local Easing = require(script.Parent.Parent.Easing)
local Random = require(script.Parent.Parent.Random)
local Types = require(script.Parent.Parent.Types)

type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type FrameContext = Types.FrameContext
type CostEstimate = Types.CostEstimate
type EasingFn = Types.EasingFn

local MAX_AMPLITUDE = 20
local TAU = 2 * math.pi
local RAD = math.pi / 180
local AXES = 6 -- pitch, yaw, roll, x, y, z
local SINES = 3
local WEIGHTS = { 1, 0.6, 0.35 }
local WEIGHT_SUM = 1.95
local RATES = { 1, 0.59, 0.31 }
local RATE_JITTER = 0.1

-- ─────────────────────────────────────────────────────────────────────────────
-- Pure functions
-- ─────────────────────────────────────────────────────────────────────────────

local function linear(alpha: number): number
	return math.clamp(alpha, 0, 1)
end

-- Easing.parse for a string property; invalid definitions fall back to Linear (Validation reports them).
local function parseEasing(def: any): EasingFn
	local ok, fn = pcall(Easing.parse :: any, def)
	if ok and type(fn) == "function" then
		return fn
	end
	return linear
end

-- Strength envelope (0..1) at local time t for a component span of `span` seconds.
local function envelope(t: number, span: number, attack: number, decay: number, ease: EasingFn): number
	if t < 0 or t >= span then
		return 0
	end
	local rise = if attack > 0 then math.min(t / attack, 1) else 1
	local fall = 1
	if decay > 0 then
		local p = (t - (span - decay)) / decay
		if p > 0 then
			fall = 1 - ease(math.min(p, 1))
		end
	end
	return math.clamp(math.min(rise, fall), 0, 1)
end

-- Distance falloff (0..1).
local function falloff(distance: number, inner: number, outer: number): number
	if distance <= inner then
		return 1
	elseif distance >= outer then
		return 0
	end
	return 1 - (distance - inner) / (outer - inner)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Mixer (module-level; see header)
-- ─────────────────────────────────────────────────────────────────────────────

type Shaker = {
	-- Camera-space offset at the shake's current local time for a camera at `cameraPosition`.
	offset: (cameraPosition: Vector3) -> CFrame,
}

type Mixer = {
	client: boolean,
	shakers: { Shaker },
	workspaceService: any,
	runService: any,
	camera: Camera?, -- camera the mixer last wrote to
	base: CFrame, -- that camera's CFrame without shake
	offset: CFrame, -- the composed offset of the last write (base × offset = written)
	written: CFrame?, -- the value it held after the mixer's last write
	bound: boolean,
	applyName: string,
	undoName: string,
}

-- Distinguishes this module instance's binding names from other copies of the runtime (other Actors / VMs).
local TOKEN = string.format("%08x", Random.hash(tostring({}), os.clock()))
local bindCount = 0

local function newMixer(client: boolean): Mixer
	return {
		client = client,
		shakers = {},
		workspaceService = nil,
		runService = nil,
		camera = nil,
		base = CFrame.identity,
		offset = CFrame.identity,
		written = nil,
		bound = false,
		applyName = "",
		undoName = "",
	}
end

local clientMixer = newMixer(true)
local previewMixer = newMixer(false)

local function restore(m: Mixer)
	local camera = m.camera
	local written = m.written
	m.camera = nil
	m.written = nil
	if camera and written and written ~= m.base and camera.CFrame == written then
		camera.CFrame = m.base
	end
end

local function apply(m: Mixer)
	local camera = Common.currentCamera(m.workspaceService)
	if camera ~= m.camera then
		restore(m)
	end
	if camera == nil then
		return
	end
	local current = camera.CFrame
	local written = m.written
	local base: CFrame
	if written == nil then
		base = current
	elseif current == written then
		base = m.base
	else
		base = current * m.offset:Inverse()
	end
	local offset = CFrame.identity
	for _, shaker in m.shakers do
		offset *= shaker.offset(base.Position)
	end
	local target = base * offset
	m.camera = camera
	m.base = base
	m.offset = offset
	if target ~= current then
		camera.CFrame = target
		m.written = camera.CFrame
	else
		m.written = current
	end
end

local function bind(m: Mixer)
	if m.bound then
		return
	end
	m.bound = true
	bindCount += 1
	local suffix = TOKEN .. "_" .. tostring(bindCount)
	m.applyName = "AstraVFX_Shake_" .. suffix
	m.undoName = "AstraVFX_ShakeUndo_" .. suffix
	local runService = m.runService
	local cameraPriority = Enum.RenderPriority.Camera.Value
	local ok, err = pcall(function()
		runService:BindToRenderStep(m.undoName, cameraPriority - 1, function(_dt: number)
			restore(m)
		end)
		runService:BindToRenderStep(m.applyName, cameraPriority + 1, function(_dt: number)
			apply(m)
		end)
	end :: any)
	if not ok then
		warn("AstraVFX cameraShake: BindToRenderStep failed: " .. tostring(err))
	end
end

local function unbind(m: Mixer)
	if not m.bound then
		return
	end
	m.bound = false
	local runService = m.runService
	pcall(function()
		runService:UnbindFromRenderStep(m.applyName)
	end :: any)
	pcall(function()
		runService:UnbindFromRenderStep(m.undoName)
	end :: any)
end

local function add(m: Mixer, shaker: Shaker, workspaceService: any, runService: any)
	if table.find(m.shakers, shaker) then
		return
	end
	if #m.shakers == 0 then
		-- An idle mixer adopts the services of its first shake (tests substitute them through Env).
		m.workspaceService = workspaceService
		m.runService = runService
	end
	table.insert(m.shakers, shaker)
	if m.client then
		bind(m)
	else
		apply(m)
	end
end

local function remove(m: Mixer, shaker: Shaker)
	local index = table.find(m.shakers, shaker)
	if index == nil then
		return
	end
	table.remove(m.shakers, index)
	if #m.shakers == 0 then
		unbind(m)
		restore(m)
	elseif not m.client then
		apply(m)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Descriptor
-- ─────────────────────────────────────────────────────────────────────────────

local descriptor: Types.ComponentDescriptor = {
	type = "cameraShake",
	displayName = "Camera Shake",
	category = "Camera",
	description = "Shakes the local player's camera while active (smooth seeded noise, attack/decay, distance falloff). "
		.. "Client only; the Studio preview is opt-in.",
	icon = "≋",
	properties = {
		Common.prop("amplitude", "number", 0.6, "Rotation in degrees at full strength.", {
			category = "Strength",
			min = 0,
			max = MAX_AMPLITUDE,
			step = 0.05,
		}),
		Common.prop("positionAmplitude", "number", 0.15, "Positional offset in studs at full strength.", {
			category = "Strength",
			min = 0,
			max = 10,
			step = 0.01,
			scale = "length",
		}),
		Common.prop("frequency", "number", 18, "Shake frequency in Hz (the fastest noise component).", {
			category = "Motion",
			min = 0.1,
			max = 60,
		}),
		Common.prop("attack", "number", 0.02, "Seconds from rest to full strength (linear).", {
			category = "Envelope",
			min = 0,
			max = 5,
			step = 0.01,
		}),
		Common.prop("decay", "number", 0.35, "Fade-out over the last `decay` seconds of the component span.", {
			category = "Envelope",
			min = 0,
			max = 10,
			step = 0.01,
		}),
		Common.prop(
			"decayEasing",
			"string",
			"Quad.Out",
			"Easing of the fade-out (strength = 1 − easing(progress)).",
			{
				category = "Envelope",
			}
		),
		Common.prop(
			"rotationWeights",
			"vector3",
			{ 1, 0.6, 0.3 },
			"Share of the rotation amplitude per axis: pitch (X), yaw (Y), roll (Z).",
			{ category = "Strength", min = 0, max = 1 }
		),
		Common.prop("innerRadius", "number", 20, "Full strength while the camera is within this distance (studs).", {
			category = "Falloff",
			min = 0,
			max = 10000,
			scale = "length",
		}),
		Common.prop(
			"outerRadius",
			"number",
			120,
			"No shake beyond this distance; linear falloff in between (studs).",
			{
				category = "Falloff",
				min = 0,
				max = 10000,
				scale = "length",
			}
		),
		Common.prop(
			"previewInStudio",
			"boolean",
			false,
			"Also shake the Studio camera in the editor preview (off by default).",
			{ category = "Preview" }
		),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs (falloff origin).", {
			scale = "length",
		}),
		Common.channel("amplitude", "number", "Rotation amplitude in degrees at full strength.", {
			min = 0,
			max = MAX_AMPLITUDE,
			baseProperty = "amplitude",
		}),
	},
	events = {},
	canParent = true,
	supportsViewport = false,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local instances: { Instance } = {}
		local controller = Common.controller(component, instances)

		local scale = math.max(component.scale, 0)
		local positionAmplitude: number = props.positionAmplitude * scale
		local innerRadius: number = props.innerRadius * scale
		local outerRadius: number = props.outerRadius * scale
		local frequency: number = props.frequency
		local attack: number = props.attack
		local decay: number = props.decay
		local decayEase = parseEasing(props.decayEasing)
		local weights: Vector3 = props.rotationWeights
		local span = math.max(component.endTime - component.startTime, 0)

		-- Noise table: per axis and sine a phase in [0, 1) and a rate factor (seed-derived, fixed draw order).
		local rng = Random.new(component.seed)
		local phases: { number } = table.create(AXES * SINES)
		local rates: { number } = table.create(AXES * SINES)
		for i = 1, AXES * SINES do
			local k = (i - 1) % SINES + 1
			phases[i] = rng:next()
			rates[i] = RATES[k] * (1 + RATE_JITTER * (2 * rng:next() - 1))
		end

		local function noise(axis: number, u: number): number
			local first = (axis - 1) * SINES
			local sum = 0
			for k = 1, SINES do
				local i = first + k
				sum += WEIGHTS[k] * math.sin(TAU * (rates[i] * u + phases[i]))
			end
			return sum / WEIGHT_SUM
		end

		-- Which mixer (if any) this build feeds.
		local mixer: Mixer? = nil
		if ctx.isPreview then
			if props.previewInStudio == true and not ctx.viewport then
				mixer = previewMixer
			end
		elseif not ctx.viewport and Common.hasLocalPlayer() then
			mixer = clientMixer
		end
		local workspaceService: any = if mixer then Common.tryService("Workspace") else nil
		local runService: any = if mixer == clientMixer then Common.tryService("RunService") else nil
		if workspaceService == nil or (mixer == clientMixer and runService == nil) then
			mixer = nil
		end

		local alive = true
		local active = false
		local released = false
		local localTime = 0
		local amplitude: number = props.amplitude
		local restPosition = (ctx.root.CFrame * CFrame.new(component.position)).Position
		local worldPosition = restPosition

		local shaker: Shaker = {
			offset = function(cameraPosition: Vector3): CFrame
				local t = localTime
				local s = envelope(t, span, attack, decay, decayEase)
					* falloff((cameraPosition - worldPosition).Magnitude, innerRadius, outerRadius)
				-- `not (s > 0)` also catches NaN (a NaN world position, e.g. an Attach target flung by physics):
				-- a NaN Camera.CFrame would never equal the last write, so the undo step could not repair it.
				if not (s > 0) then
					return CFrame.identity
				end
				local u = t * frequency
				local r = amplitude * s * RAD
				local p = positionAmplitude * s
				return CFrame.new(p * noise(4, u), p * noise(5, u), p * noise(6, u))
					* CFrame.fromOrientation(
						r * weights.X * noise(1, u),
						r * weights.Y * noise(2, u),
						r * weights.Z * noise(3, u)
					)
			end,
		}

		local function sync()
			local m = mixer
			if m == nil then
				return
			end
			if alive and active and not released then
				add(m, shaker, workspaceService, runService)
			else
				remove(m, shaker)
			end
		end

		function controller.setActive(_self: ComponentInstance, isActive: boolean, frame: FrameContext)
			if not alive then
				return
			end
			active = isActive
			if isActive then
				localTime = math.max(frame.time - component.startTime, 0)
			end
			sync()
		end

		function controller.apply(_self: ComponentInstance, channel: string, value: any)
			if channel == "amplitude" and type(value) == "number" and value == value then
				amplitude = math.clamp(value, 0, MAX_AMPLITUDE)
			end
		end

		function controller.setTransform(
			_self: ComponentInstance,
			_localCFrame: CFrame,
			worldCFrame: CFrame,
			_frame: FrameContext
		)
			worldPosition = worldCFrame.Position
		end

		controller.update = function(_self: ComponentInstance, time: number, _frame: FrameContext)
			if not alive then
				return
			end
			localTime = time
			if mixer == previewMixer and active and not released then
				apply(previewMixer)
			end
		end

		function controller.release(_self: ComponentInstance)
			released = true
			sync()
		end

		function controller.reset(_self: ComponentInstance)
			active = false
			released = false
			sync()
			localTime = 0
			amplitude = props.amplitude
			worldPosition = restPosition
		end

		function controller.destroy(self: ComponentInstance)
			if alive then
				alive = false
				sync()
			end
			table.clear(self.instances)
		end

		return controller
	end,
	estimateCost = function(component: CompiledComponent, _quality: Types.QualityProfile): CostEstimate
		local props = component.props
		local cost = Common.cost()
		-- Camera.CFrame per rendered frame while active: undo + apply on clients (the preview writes once).
		cost.propertyUpdates = 2
		local notes = { "client only: offsets Camera.CFrame every rendered frame (no instances)" }
		if props.outerRadius <= props.innerRadius then
			table.insert(notes, "outerRadius <= innerRadius: hard cut-off at innerRadius instead of a falloff.")
		end
		if props.attack + props.decay > component.endTime - component.startTime then
			table.insert(notes, "attack + decay exceed the component span; the shake never reaches full strength.")
		end
		cost.notes = notes
		return cost
	end,
}

return descriptor
