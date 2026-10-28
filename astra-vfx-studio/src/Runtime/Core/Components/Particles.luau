--!strict
--[[
	particles — a native ParticleEmitter (docs/COMPONENTS_SPEC.md §2).

	Instances (first entry = the emitter; children are listed before their parents so destroy() never touches an
	instance that was already destroyed through its parent):
	  shape == "Point": ParticleEmitter inside an Attachment on the effect Root. The emitter spawns at the
	                    attachment; the attachment orientation (component transform) turns EmissionDirection.
	  otherwise:        ParticleEmitter inside an invisible host Part (Common.newPart, Size = emitterSize × scale)
	                    with `Shape` set. Sphere/Cylinder render wrongly under an Attachment (engine docs), so every
	                    volume shape gets a BasePart parent. The host part moves through frame.moveParts.

	Behaviour:
	  * Continuous emission: Enabled = active and rate > 0 (and not disabled by an event, not released, not
	    seeking). The seek state is taken from every frame the controller sees (setActive, setTransform, update,
	    onAction), so a seek switches continuous emission off and the next playback frame switches it back on.
	  * `burst` particles are emitted once when the component becomes active; `emit` events call Emit(count).
	    Nothing is emitted while frame.seeking (scrubbing must stay deterministic: the Player clears particles on
	    seek and the engine cannot fast-forward them) or after release().
	  * Size = authored size × scale × quality.sizeCompensation (scale = transform.scale, overridden by the
	    `scale` channel).
	  * Channels `transparency` (fade) and `tint` (Common.tintSequence) rebuild the sequences only when the channel
	    value changed; every channel caches its last applied value. The fade maps each keypoint's whole random range
	    [v − e, v + e] through t' = 1 − (1 − t)(1 − fade), i.e. value' = 1 − (1 − v)(1 − fade) and
	    envelope' = e·(1 − fade) (local fadeSequence; Common.fadeSequence keeps the envelope, so a fade of 1 would
	    still show particles whose random offset is negative).
	  * TimeScale = clamp(clamp(timeScale, 0, 1) × s, 0, 1) with s = the effect's effective time scale: the
	    definition's timeScale at build time, then whatever the Player passes to setTimeScale (definition ×
	    Play option × handle:SetTimeScale, 0 while paused — the engine freezes live particles). The engine range
	    is 0..1, so slow motion works but fast motion cannot speed particles up beyond normal speed (VERIFIED,
	    docs/ROBLOX_API_CONSTRAINTS.md §1.3; Studio TimeScale bugs PE-B1 / U2 are REPORTED). Written only when
	    the value changes; reset() restores the build value.
	  * The `rate` channel works in the same (compiled) domain as its baseProperty `rate`: values are written as
	    given, clamped to the 400/s engine cap. Applying the rest value props.rate (already × countScale) therefore
	    leaves the built Rate unchanged. Quality scaling of animated rates belongs to the Compiler, like every
	    other quality rule.
	  * release() sets Enabled = false: live particles finish their lifetime (tailTime = lifetime.Max).
]]

local Common = require(script.Parent.Common)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)

type FrameContext = Types.FrameContext
type CompiledComponent = Types.CompiledComponent

local prop = Common.prop
local channel = Common.channel

local DEFAULT_EMIT_COUNT = 16 -- ParticleEmitter:Emit() default (engine)
local WHITE = Color3.new(1, 1, 1)
local INF = math.huge

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local SHAPES: { [string]: Enum.ParticleEmitterShape } = {
	Box = Enum.ParticleEmitterShape.Box,
	Sphere = Enum.ParticleEmitterShape.Sphere,
	Cylinder = Enum.ParticleEmitterShape.Cylinder,
	Disc = Enum.ParticleEmitterShape.Disc,
}

-- The Roblox shape for volume shapes, nil for "Point" (attachment emitter).
local function volumeShape(name: any): Enum.ParticleEmitterShape?
	if type(name) ~= "string" or name == "Point" then
		return nil
	end
	local shape: Enum.ParticleEmitterShape? = SHAPES[name]
	return shape
end

-- Fade over an authored transparency sequence: t' = 1 − (1 − t)(1 − fade) applied to the whole random range of
-- every keypoint, so the envelope shrinks with (1 − fade) and fade = 1 hides every particle. Keypoint count is kept.
local function fadeSequence(base: NumberSequence, fade: number): NumberSequence
	if fade <= 0 then
		return base
	end
	local f = math.clamp(fade, 0, 1)
	local keep = 1 - f
	local keys = {}
	for i, k in base.Keypoints do
		keys[i] = NumberSequenceKeypoint.new(k.Time, math.clamp(1 - (1 - k.Value) * keep, 0, 1), k.Envelope * keep)
	end
	return NumberSequence.new(keys)
end

local function maxSequenceValue(sequence: NumberSequence): number
	local m = 0
	for _, k in sequence.Keypoints do
		m = math.max(m, k.Value + k.Envelope)
	end
	return m
end

local function countTracksExcept(component: CompiledComponent, excluded: { [string]: boolean }): number
	local n = 0
	for name in component.tracks do
		if not excluded[name] then
			n += 1
		end
	end
	return n
end

local TRANSFORM_TRACKS = { position = true, rotation = true }

local descriptor: Types.ComponentDescriptor = {
	type = "particles",
	displayName = "Particles",
	category = "Particles",
	description = "Native ParticleEmitter: continuous emission, bursts and emit events.",
	icon = "✦",
	properties = {
		prop(
			"texture",
			"asset",
			"rbxasset://textures/particles/sparkles_main.dds",
			"Particle texture (asset id or built-in rbxasset path).",
			{ category = "Appearance" }
		),
		prop("color", "colorSequence", "#FFFFFF", "Colour over each particle's lifetime.", { category = "Appearance" }),
		prop(
			"transparency",
			"numberSequence",
			0,
			"Transparency over each particle's lifetime (0 = opaque, 1 = invisible).",
			{ category = "Appearance", min = 0, max = 1 }
		),
		prop(
			"size",
			"numberSequence",
			1,
			"Particle size in studs over its lifetime (× scale × quality size compensation).",
			{ category = "Appearance", min = 0, max = 100, scale = "length" }
		),
		prop(
			"squash",
			"numberSequence",
			0,
			"Squash over lifetime: > 0 taller and narrower, < 0 wider and flatter.",
			{ category = "Appearance", min = -3, max = 3, advanced = true }
		),
		prop(
			"lifetime",
			"numberRange",
			{ 1, 2 },
			"Seconds each particle lives (random between min and max; engine cap 20 s).",
			{ category = "Emission", min = 0, max = 20 }
		),
		prop(
			"rate",
			"number",
			20,
			"Particles per second while active (0 = bursts only; engine cap 400/s, 100/s on mobile).",
			{ category = "Emission", min = 0, max = 400, quality = "count" }
		),
		prop(
			"burst",
			"integer",
			0,
			"Particles emitted once when the component becomes active.",
			{ category = "Emission", min = 0, max = 10000, quality = "count" }
		),
		prop(
			"speed",
			"numberRange",
			{ 5, 5 },
			"Initial speed in studs/second along the emission direction (negative = backwards).",
			{ category = "Motion", min = -1000, max = 1000, scale = "length" }
		),
		prop(
			"spreadAngle",
			"vector2",
			{ 0, 0 },
			"Random emission angle in degrees around the two axes perpendicular to the emission direction.",
			{ category = "Motion", min = -360, max = 360 }
		),
		prop(
			"acceleration",
			"vector3",
			{ 0, 0, 0 },
			"Constant acceleration in studs/s² (world axes), e.g. gravity or buoyancy.",
			{ category = "Motion", scale = "length" }
		),
		prop(
			"drag",
			"number",
			0,
			"Velocity half-life drag (exponential slow-down).",
			{ category = "Motion", min = 0, max = 100 }
		),
		prop(
			"rotation",
			"numberRange",
			{ 0, 0 },
			"Initial sprite rotation in degrees (random between min and max).",
			{ category = "Motion", min = -360, max = 360 }
		),
		prop(
			"rotSpeed",
			"numberRange",
			{ 0, 0 },
			"Sprite rotation speed in degrees/second (random between min and max).",
			{ category = "Motion", min = -3600, max = 3600 }
		),
		prop(
			"emissionDirection",
			"enum",
			"Top",
			"Face of the emitter (attachment / host part) particles are emitted from.",
			{
				category = "Motion",
				enum = { "Top", "Bottom", "Front", "Back", "Left", "Right" },
				enumType = "NormalId",
			}
		),
		prop(
			"shape",
			"enum",
			"Point",
			"Emission shape. Point emits from an attachment; the others emit from an invisible host part.",
			{ category = "Shape", enum = { "Point", "Box", "Sphere", "Cylinder", "Disc" } }
		),
		prop(
			"emitterSize",
			"vector3",
			{ 1, 1, 1 },
			"Size of the emission volume (host part size) for non-Point shapes.",
			{ category = "Shape", min = 0, max = 2048, scale = "length" }
		),
		prop(
			"shapeStyle",
			"enum",
			"Volume",
			"Emit inside the shape volume or on its surface.",
			{ category = "Shape", enum = { "Volume", "Surface" }, enumType = "ParticleEmitterShapeStyle" }
		),
		prop("shapeInOut", "enum", "Outward", "Emission direction relative to the shape: outward, inward or both.", {
			category = "Shape",
			enum = { "Outward", "Inward", "InAndOut" },
			enumType = "ParticleEmitterShapeInOut",
		}),
		prop(
			"shapePartial",
			"number",
			1,
			"Partial shape: cylinder top radius, disc inner radius or sphere cap angle (0..1).",
			{ category = "Shape", min = 0, max = 1 }
		),
		prop("orientation", "enum", "FacingCamera", "How particle sprites are oriented.", {
			category = "Appearance",
			enum = { "FacingCamera", "FacingCameraWorldUp", "VelocityParallel", "VelocityPerpendicular" },
			enumType = "ParticleOrientation",
		}),
		prop(
			"lightEmission",
			"number",
			0,
			"Additive blending amount (0 = normal, 1 = fully additive glow).",
			{ category = "Appearance", min = 0, max = 1 }
		),
		prop(
			"lightInfluence",
			"number",
			0,
			"How much environment lighting tints the particles.",
			{ category = "Appearance", min = 0, max = 1 }
		),
		prop(
			"brightness",
			"number",
			1,
			"Brightness multiplier of the emitted light (with lightInfluence 0).",
			{ category = "Appearance", min = 0, max = 100 }
		),
		prop(
			"zOffset",
			"number",
			0,
			"Render offset towards (+) or away from (-) the camera in studs.",
			{ category = "Appearance", min = -100, max = 100 }
		),
		prop(
			"timeScale",
			"number",
			1,
			"Simulation speed 0..1 (engine range); the emitter runs at clamp(timeScale × effect time scale, 0, 1).",
			{ category = "Emission", min = 0, max = 1 }
		),
		prop(
			"lockedToPart",
			"boolean",
			false,
			"Live particles move rigidly with the emitter.",
			{ category = "Motion" }
		),
		prop(
			"velocityInheritance",
			"number",
			0,
			"Fraction of the host part velocity given to new particles.",
			{ category = "Motion", min = 0, max = 1, advanced = true }
		),
		prop(
			"windAffectsDrag",
			"boolean",
			false,
			"Particles with drag follow Workspace.GlobalWind.",
			{ category = "Motion", advanced = true }
		),
		prop("flipbookLayout", "enum", "None", "Flipbook grid of the texture (flipbooks need a 1024×1024 texture).", {
			category = "Flipbook",
			enum = { "None", "Grid2x2", "Grid4x4", "Grid8x8" },
			enumType = "ParticleFlipbookLayout",
		}),
		prop(
			"flipbookMode",
			"enum",
			"Loop",
			"Flipbook playback mode (OneShot spreads the frames over the particle lifetime).",
			{
				category = "Flipbook",
				enum = { "Loop", "OneShot", "PingPong", "Random" },
				enumType = "ParticleFlipbookMode",
			}
		),
		prop(
			"flipbookFramerate",
			"numberRange",
			{ 1, 1 },
			"Flipbook frames per second (random between min and max; engine max 30).",
			{ category = "Flipbook", min = 0, max = 30 }
		),
		prop(
			"flipbookStartRandom",
			"boolean",
			false,
			"Each particle starts on a random flipbook frame.",
			{ category = "Flipbook" }
		),
		Common.spinProperty(),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		Common.channel("scale", "number", "Size multiplier of the particles and the emission volume.", { min = 0 }),
		channel(
			"transparency",
			"number",
			"Fade over the authored transparency: t' = 1 - (1 - t)(1 - fade). Affects live particles.",
			{ min = 0, max = 1 }
		),
		channel("tint", "color3", "Multiplies the authored colour sequence (white = unchanged)."),
		channel(
			"rate",
			"number",
			"Particles per second (same domain as the rate property). 0 stops continuous emission.",
			{ min = 0, max = 400, baseProperty = "rate" }
		),
		channel("brightness", "number", "Brightness multiplier.", { min = 0, max = 100, baseProperty = "brightness" }),
		channel("lightEmission", "number", "Additive blending amount.", {
			min = 0,
			max = 1,
			baseProperty = "lightEmission",
		}),
		channel("acceleration", "vector3", "Acceleration in studs/s² (world axes).", {
			scale = "length",
			baseProperty = "acceleration",
		}),
		channel("timeScale", "number", "Simulation speed 0..1 (× effect time scale, clamped to 0..1).", {
			min = 0,
			max = 1,
			baseProperty = "timeScale",
		}),
	},
	events = {
		{ action = "emit", description = "Emits `count` particles at once (default 16).", usesCount = true },
		{ action = "clear", description = "Removes all live particles immediately." },
		{ action = "enable", description = "Re-enables continuous emission (while active and rate > 0)." },
		{ action = "disable", description = "Stops continuous emission; live particles finish." },
	},
	canParent = true,
	supportsViewport = false,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): Types.ComponentInstance
		local props = component.props
		local quality = ctx.effect.quality
		local countScale: number = quality.countScale
		local sizeCompensation: number = quality.sizeCompensation
		local builtTimeScale: number = if isFinite(ctx.effect.timeScale) then math.max(ctx.effect.timeScale, 0) else 1

		local shapeEnum = volumeShape(props.shape)
		local isPoint = not shapeEnum
		local baseSize: NumberSequence = props.size
		local baseTransparency: NumberSequence = props.transparency
		local baseColor: ColorSequence = props.color
		local emitterSize: Vector3 = props.emitterSize
		local baseRate: number = math.clamp(props.rate, 0, Constants.MAX_PARTICLE_RATE)
		local baseBrightness: number = props.brightness
		local baseLightEmission: number = props.lightEmission
		local baseAcceleration: Vector3 = props.acceleration
		local baseTimeScale: number = math.clamp(props.timeScale, 0, 1)
		local burst: number = math.clamp(math.floor(props.burst + 0.5), 0, Constants.MAX_EMIT_COUNT)
		local defaultEmit = Common.scaledCount(DEFAULT_EMIT_COUNT, countScale, 1)

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = component.name
		emitter.Enabled = false
		-- Every property is written explicitly: Instance.new defaults differ from Studio-insert defaults
		-- (e.g. LightInfluence), and ASTRA's defaults differ from both (Lifetime 1..2).
		emitter.Texture = props.texture
		emitter.Color = baseColor
		emitter.Transparency = baseTransparency
		emitter.Size = Common.scaleSequence(baseSize, component.scale * sizeCompensation)
		emitter.Squash = props.squash
		emitter.Lifetime = props.lifetime
		emitter.Rate = baseRate
		emitter.Speed = props.speed
		emitter.SpreadAngle = props.spreadAngle
		emitter.Acceleration = baseAcceleration
		emitter.Drag = props.drag
		emitter.Rotation = props.rotation
		emitter.RotSpeed = props.rotSpeed
		emitter.EmissionDirection = props.emissionDirection
		emitter.Shape = shapeEnum or Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = props.shapeStyle
		emitter.ShapeInOut = props.shapeInOut
		emitter.ShapePartial = props.shapePartial
		emitter.Orientation = props.orientation
		emitter.LightEmission = baseLightEmission
		emitter.LightInfluence = props.lightInfluence
		emitter.Brightness = baseBrightness
		emitter.ZOffset = props.zOffset
		local builtEngineTimeScale = math.clamp(baseTimeScale * builtTimeScale, 0, 1)
		emitter.TimeScale = builtEngineTimeScale
		emitter.LockedToPart = props.lockedToPart
		emitter.VelocityInheritance = props.velocityInheritance
		emitter.WindAffectsDrag = props.windAffectsDrag
		emitter.FlipbookLayout = props.flipbookLayout
		emitter.FlipbookMode = props.flipbookMode
		emitter.FlipbookFramerate = props.flipbookFramerate
		emitter.FlipbookStartRandom = props.flipbookStartRandom
		ctx.tagInstance(emitter, component.id)

		local attachment: Attachment? = nil
		local hostPart: BasePart? = nil
		local instances: { Instance } = { emitter }
		if isPoint then
			local a = Common.newAttachment(ctx, component.id, component.name)
			emitter.Parent = a
			attachment = a
			table.insert(instances, a)
		else
			local p = Common.newPart(ctx, component.id, component.name)
			p.Size = emitterSize * component.scale
			emitter.Parent = p
			hostPart = p
			table.insert(instances, p)
		end
		local builtHostCFrame = ctx.root.CFrame

		-- Runtime state (everything that channels/events can change).
		local active = false
		local enabledByEvent = true
		local released = false
		local enabled = false
		local seeking = false
		local rate = baseRate
		local scale = component.scale
		local fade = 0
		local tint = WHITE
		local brightness = baseBrightness
		local lightEmission = baseLightEmission
		local acceleration = baseAcceleration
		local timeScale = baseTimeScale
		local effectTimeScale = builtTimeScale
		local writtenTimeScale = builtEngineTimeScale
		local lastCFrame: CFrame? = nil

		local function refreshEnabled()
			local on = active and enabledByEvent and not released and not seeking and rate > 0
			if on ~= enabled then
				enabled = on
				emitter.Enabled = on
			end
		end

		-- Tracks frame.seeking: continuous emission is off during seek frames, back on with the next playback frame.
		local function observe(frame: FrameContext?)
			local isSeeking = frame ~= nil and frame.seeking == true
			if isSeeking ~= seeking then
				seeking = isSeeking
				refreshEnabled()
			end
		end

		-- ParticleEmitter.TimeScale = clamp(authored × effect time scale, 0, 1), written only when it changes.
		local function writeTimeScale()
			local v = math.clamp(timeScale * effectTimeScale, 0, 1)
			if v ~= writtenTimeScale then
				writtenTimeScale = v
				emitter.TimeScale = v
			end
		end

		local function applyScale()
			emitter.Size = Common.scaleSequence(baseSize, scale * sizeCompensation)
			if hostPart then
				hostPart.Size = emitterSize * scale
			end
		end

		local function emit(count: number, frame: FrameContext?)
			if released or (frame ~= nil and frame.seeking) then
				return
			end
			local n = math.clamp(math.floor(count + 0.5), 0, Constants.MAX_EMIT_COUNT)
			if n > 0 then
				emitter:Emit(n)
			end
		end

		local controller = Common.controller(component, instances)

		function controller.setActive(_self, isActive: boolean, frame: FrameContext)
			if isActive == active then
				observe(frame)
				return
			end
			active = isActive
			seeking = frame ~= nil and frame.seeking == true
			refreshEnabled()
			if isActive and burst > 0 then
				emit(burst, frame)
			end
		end

		function controller.apply(_self, name: string, value: any)
			if name == "transparency" then
				if type(value) == "number" then
					local v = math.clamp(value, 0, 1)
					if v ~= fade then
						fade = v
						emitter.Transparency = fadeSequence(baseTransparency, v)
					end
				end
			elseif name == "tint" then
				if typeof(value) == "Color3" and value ~= tint then
					tint = value
					emitter.Color = Common.tintSequence(baseColor, value)
				end
			elseif name == "rate" then
				if type(value) == "number" then
					local r = math.clamp(value, 0, Constants.MAX_PARTICLE_RATE)
					if r ~= rate then
						rate = r
						emitter.Rate = r
						refreshEnabled()
					end
				end
			elseif name == "brightness" then
				if type(value) == "number" then
					local v = math.clamp(value, 0, 100)
					if v ~= brightness then
						brightness = v
						emitter.Brightness = v
					end
				end
			elseif name == "lightEmission" then
				if type(value) == "number" then
					local v = math.clamp(value, 0, 1)
					if v ~= lightEmission then
						lightEmission = v
						emitter.LightEmission = v
					end
				end
			elseif name == "acceleration" then
				if typeof(value) == "Vector3" and value ~= acceleration then
					acceleration = value
					emitter.Acceleration = value
				end
			elseif name == "timeScale" then
				if type(value) == "number" then
					local v = math.clamp(value, 0, 1)
					if v ~= timeScale then
						timeScale = v
						writeTimeScale()
					end
				end
			elseif name == "scale" then
				if type(value) == "number" then
					local v = math.max(value, 0)
					if v ~= scale then
						scale = v
						applyScale()
					end
				end
			end
		end

		function controller.setTransform(_self, localCFrame: CFrame, worldCFrame: CFrame, frame: FrameContext)
			observe(frame)
			if attachment then
				if localCFrame ~= lastCFrame then
					lastCFrame = localCFrame
					attachment.CFrame = localCFrame
				end
			elseif hostPart then
				if worldCFrame ~= lastCFrame then
					lastCFrame = worldCFrame
					table.insert(frame.moveParts, hostPart)
					table.insert(frame.moveCFrames, worldCFrame)
				end
			end
		end

		-- No procedural motion: update only follows the seek state (the Player calls it every active frame).
		controller.update = function(_self, _localTime: number, frame: FrameContext)
			observe(frame)
		end

		function controller.onAction(_self, action: Types.ScheduledAction, frame: FrameContext)
			observe(frame)
			local kind = action.action
			if kind == "emit" then
				emit(action.count or defaultEmit, frame)
			elseif kind == "clear" then
				emitter:Clear()
			elseif kind == "enable" then
				enabledByEvent = true
				refreshEnabled()
			elseif kind == "disable" then
				enabledByEvent = false
				refreshEnabled()
			end
		end

		function controller.setTimeScale(_self, scale: number)
			if isFinite(scale) and scale >= 0 and scale ~= effectTimeScale then
				effectTimeScale = scale
				writeTimeScale()
			end
		end

		function controller.release(_self)
			released = true
			refreshEnabled()
		end

		function controller.reset(_self)
			active = false
			enabledByEvent = true
			released = false
			enabled = false
			seeking = false
			emitter.Enabled = false
			emitter:Clear()
			rate = baseRate
			emitter.Rate = baseRate
			fade = 0
			emitter.Transparency = baseTransparency
			tint = WHITE
			emitter.Color = baseColor
			brightness = baseBrightness
			emitter.Brightness = baseBrightness
			lightEmission = baseLightEmission
			emitter.LightEmission = baseLightEmission
			acceleration = baseAcceleration
			emitter.Acceleration = baseAcceleration
			timeScale = baseTimeScale
			effectTimeScale = builtTimeScale
			writtenTimeScale = builtEngineTimeScale
			emitter.TimeScale = builtEngineTimeScale
			scale = component.scale
			applyScale()
			lastCFrame = nil
			if attachment then
				attachment.CFrame = CFrame.new()
			end
			if hostPart then
				hostPart.CFrame = builtHostCFrame
			end
		end

		return controller
	end,
	estimateCost = function(component: CompiledComponent, quality: Types.QualityProfile): Types.CostEstimate
		local props = component.props
		local isPoint = not volumeShape(props.shape)
		local cost = Common.cost()
		cost.instances = 2
		cost.emitters = 1
		if isPoint then
			cost.attachments = 1
		else
			cost.parts = 1
		end
		local rate: number = math.clamp(props.rate, 0, Constants.MAX_PARTICLE_RATE)
		local lifetime: NumberRange = props.lifetime
		local burstCount: number = props.burst
		local defaultEmit = Common.scaledCount(DEFAULT_EMIT_COUNT, quality.countScale, 1)
		for _, event in component.events do
			if event.action == "emit" then
				burstCount += event.count or defaultEmit
			end
		end
		cost.continuousRate = rate
		cost.burstCount = burstCount
		cost.maxLifetime = lifetime.Max
		local moving = Common.isMoving(component)
		cost.movingParts = if moving and not isPoint then 1 else 0
		-- Heuristic: one property write per non-transform track, plus the attachment CFrame write when moving.
		cost.propertyUpdates = countTracksExcept(component, TRANSFORM_TRACKS) + (if moving and isPoint then 1 else 0)
		cost.transparentLayers = 1
		-- Heuristic overdraw: (largest sprite size)² × particles alive at once (rate × mean lifetime + bursts).
		local size = maxSequenceValue(props.size) * component.scale * quality.sizeCompensation
		local alive = rate * (lifetime.Min + lifetime.Max) / 2 + burstCount
		cost.overdrawWeight = size * size * alive
		local notes = {}
		if rate > 100 then
			table.insert(notes, "Rate above 100/s: the engine caps emitters at 100 particles/s on mobile.")
		end
		if props.flipbookLayout ~= Enum.ParticleFlipbookLayout.None then
			table.insert(notes, "Flipbooks need a 1024×1024 texture and are disabled on low-memory clients.")
		end
		cost.notes = if #notes > 0 then notes else nil
		return cost
	end,
	tailTime = function(component: CompiledComponent): number
		local lifetime: NumberRange = component.props.lifetime
		return lifetime.Max
	end,
}

return descriptor
