--!strict
--[[
	beam — a native Beam between two Attachments (docs/COMPONENTS_SPEC.md §3).

	Instances: Beam (parented to the effect Root part; beams render only under Workspace) + Attachment0/1 on the
	Root. The Beam is the first entry of `instances`.

	Geometry: the engine draws a cubic Bézier P0 = A0, P1 = A0 + A0.Axis·CurveSize0, P2 = A1 − A1.Axis·CurveSize1,
	P3 = A1 (Axis = attachment +X). ASTRA orients the attachments so that equal curveSize0/1 bend the beam into an
	arch towards `curveDirection`:
	  d   = unit(to − from)                          (beam axis, component space)
	  c   = unit(curveDirection)
	  y   = unit(c × d)                              (shared by both attachments, so the ribbon does not twist)
	  A0  = localCFrame · CFrame(from) · R(d, roll) · fromMatrix(c, y)
	  A1  = localCFrame · CFrame(to)   · R(d, roll) · fromMatrix(−c, y)
	R(d, roll) rotates both frames about the beam axis. When c is (anti)parallel to d, y falls back to a vector
	perpendicular to c. Which attachment axis spans the ribbon width with faceCamera = false is not documented by
	the engine, so `roll` is the empirical knob for the ribbon plane.

	Channels: transform (scale = width multiplier), transparency (fade) / tint (sequence rebuild only on change),
	width0/1, curveSize0/1, from/to (move the attachments), brightness, textureSpeed. Beams have no time factor,
	so TextureSpeed = textureSpeed × s, s = the effect's effective time scale: the definition's timeScale at build
	time, then whatever the Player passes to setTimeScale (definition × Play option × handle:SetTimeScale, 0
	while paused). Slow motion slows the texture scroll, fast motion speeds it up, a pause stops it. Written only
	when the value changes; reset() restores the build value.

	Segments = max(segments, gradient keypoints − 1), at most 1000: a Color/Transparency sequence with n keypoints
	needs at least n − 1 segments (engine fact, research §2.6). `segments` is NOT quality-scaled
	(docs/ROBLOX_API_CONSTRAINTS.md K14, ARCHITECTURE §5.4, COMPONENTS_SPEC §3: the engine lowers beam segments at
	low graphics quality itself), but Validation can only check the authored value against the authored
	sequences, so the floor is enforced here. Fade/tint rebuild the sequences with the same keypoint count, so the
	floor is fixed.
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

type FrameContext = Types.FrameContext
type CompiledComponent = Types.CompiledComponent

local prop = Common.prop
local channel = Common.channel

local WHITE = Color3.new(1, 1, 1)
local EPSILON = 1e-6
local INF = math.huge

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

-- Attachment CFrames (relative to the Root part) for a beam from `from` to `to` in component space.
local function attachmentFrames(
	localCFrame: CFrame,
	from: Vector3,
	to: Vector3,
	curveDirection: Vector3,
	roll: number
): (CFrame, CFrame)
	local axis = to - from
	local d = if axis.Magnitude > EPSILON then axis.Unit else Vector3.new(0, 0, -1)
	local c = if curveDirection.Magnitude > EPSILON then curveDirection.Unit else Vector3.new(0, 1, 0)
	local y = c:Cross(d)
	if y.Magnitude < EPSILON then
		-- curveDirection along the beam axis: any vector perpendicular to c keeps the frame orthonormal.
		local reference = if math.abs(c.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
		y = c:Cross(reference)
	end
	y = y.Unit
	local rotation0 = CFrame.fromMatrix(Vector3.zero, c, y)
	local rotation1 = CFrame.fromMatrix(Vector3.zero, -c, y)
	if roll ~= 0 then
		local r = CFrame.fromAxisAngle(d, math.rad(roll))
		rotation0 = r * rotation0
		rotation1 = r * rotation1
	end
	return localCFrame * (CFrame.new(from) * rotation0), localCFrame * (CFrame.new(to) * rotation1)
end

local MAX_SEGMENTS = 1000

-- Beam.Segments for the authored segment count: never below (gradient keypoints − 1).
local function segmentCount(segments: number, color: ColorSequence, transparency: NumberSequence): number
	local gradient = math.max(#color.Keypoints, #transparency.Keypoints) - 1
	return math.clamp(math.max(math.floor(segments + 0.5), gradient), 1, MAX_SEGMENTS)
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
	type = "beam",
	displayName = "Beam",
	category = "Beams & Trails",
	description = "Native Beam between two attachments: lasers, arcs, streaks and ribbons.",
	icon = "═",
	properties = {
		prop(
			"from",
			"vector3",
			{ 0, 0, 0 },
			"Start point (Attachment0) in component space.",
			{ category = "Shape", scale = "length" }
		),
		prop(
			"to",
			"vector3",
			{ 0, 0, -10 },
			"End point (Attachment1) in component space.",
			{ category = "Shape", scale = "length" }
		),
		prop(
			"curveDirection",
			"vector3",
			{ 0, 1, 0 },
			"Direction the beam arches towards when curveSize0/1 are positive.",
			{ category = "Shape" }
		),
		prop(
			"roll",
			"number",
			0,
			"Rotation of both attachments about the beam axis in degrees (ribbon plane when not facing the camera).",
			{ category = "Shape", min = -360, max = 360 }
		),
		prop("texture", "asset", "", "Beam texture (empty = solid colour).", { category = "Appearance" }),
		prop("color", "colorSequence", "#FFFFFF", "Colour along the beam length.", { category = "Appearance" }),
		prop(
			"transparency",
			"numberSequence",
			0,
			"Transparency along the beam length.",
			{ category = "Appearance", min = 0, max = 1 }
		),
		prop(
			"width0",
			"number",
			1,
			"Width in studs at Attachment0 (the width changes linearly along the beam).",
			{ category = "Shape", min = 0, max = 1000, scale = "length" }
		),
		prop(
			"width1",
			"number",
			1,
			"Width in studs at Attachment1.",
			{ category = "Shape", min = 0, max = 1000, scale = "length" }
		),
		prop(
			"curveSize0",
			"number",
			0,
			"Bézier handle length at the start (towards curveDirection).",
			{ category = "Shape", min = -1000, max = 1000, scale = "length" }
		),
		prop(
			"curveSize1",
			"number",
			0,
			"Bézier handle length at the end (towards curveDirection).",
			{ category = "Shape", min = -1000, max = 1000, scale = "length" }
		),
		prop(
			"segments",
			"integer",
			10,
			"Straight segments the curve is drawn with (at least keypoints - 1 for gradients).",
			{ category = "Shape", min = 1, max = 1000 } -- no quality scaling (K14)
		),
		prop(
			"textureLength",
			"number",
			1,
			"Texture repeat length in studs (Wrap) or repeat count (Stretch).",
			{ category = "Appearance", min = 0.01, max = 1000, scale = "length" }
		),
		prop(
			"textureMode",
			"enum",
			"Stretch",
			"How the texture is mapped along the beam (Static behaves like Wrap on beams).",
			{ category = "Appearance", enum = { "Stretch", "Wrap", "Static" }, enumType = "TextureMode" }
		),
		prop(
			"textureSpeed",
			"number",
			1,
			"Texture scroll speed in cycles per second (× effect time scale).",
			{ category = "Appearance", min = -100, max = 100 }
		),
		prop(
			"faceCamera",
			"boolean",
			true,
			"Turn the ribbon towards the camera (billboard beam).",
			{ category = "Appearance" }
		),
		prop(
			"lightEmission",
			"number",
			0,
			"Additive blending amount (0 = normal, 1 = additive glow).",
			{ category = "Appearance", min = 0, max = 1 }
		),
		prop(
			"lightInfluence",
			"number",
			0,
			"How much environment lighting tints the beam.",
			{ category = "Appearance", min = 0, max = 1 }
		),
		prop(
			"brightness",
			"number",
			1,
			"Brightness multiplier (with lightInfluence < 1).",
			{ category = "Appearance", min = 0, max = 100 }
		),
		prop(
			"zOffset",
			"number",
			0,
			"Render offset towards the camera in studs (against z-fighting).",
			{ category = "Appearance" }
		),
		Common.spinProperty(),
	},
	channels = {
		channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		channel("scale", "number", "Width multiplier (× width0 / width1).", { min = 0 }),
		channel(
			"transparency",
			"number",
			"Fade over the authored transparency: t' = 1 - (1 - t)(1 - fade).",
			{ min = 0, max = 1 }
		),
		channel("tint", "color3", "Multiplies the authored colour sequence (white = unchanged)."),
		channel("width0", "number", "Width at Attachment0 in studs.", {
			min = 0,
			max = 1000,
			scale = "length",
			baseProperty = "width0",
		}),
		channel("width1", "number", "Width at Attachment1 in studs.", {
			min = 0,
			max = 1000,
			scale = "length",
			baseProperty = "width1",
		}),
		channel("curveSize0", "number", "Bézier handle length at the start.", {
			min = -1000,
			max = 1000,
			scale = "length",
			baseProperty = "curveSize0",
		}),
		channel("curveSize1", "number", "Bézier handle length at the end.", {
			min = -1000,
			max = 1000,
			scale = "length",
			baseProperty = "curveSize1",
		}),
		channel("from", "vector3", "Start point in component space.", { scale = "length", baseProperty = "from" }),
		channel("to", "vector3", "End point in component space.", { scale = "length", baseProperty = "to" }),
		channel("brightness", "number", "Brightness multiplier.", { min = 0, max = 100, baseProperty = "brightness" }),
		channel("textureSpeed", "number", "Texture scroll speed (× effect time scale).", {
			min = -100,
			max = 100,
			baseProperty = "textureSpeed",
		}),
	},
	events = {
		{ action = "enable", description = "Shows the beam (while active)." },
		{ action = "disable", description = "Hides the beam." },
	},
	canParent = true,
	supportsViewport = false,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): Types.ComponentInstance
		local props = component.props
		local builtTimeScale: number = if isFinite(ctx.effect.timeScale) then math.max(ctx.effect.timeScale, 0) else 1
		local curveDirection: Vector3 = props.curveDirection
		local roll: number = props.roll
		local baseFrom: Vector3 = props.from
		local baseTo: Vector3 = props.to
		local baseColor: ColorSequence = props.color
		local baseTransparency: NumberSequence = props.transparency
		local baseWidth0: number = props.width0
		local baseWidth1: number = props.width1
		local baseCurve0: number = props.curveSize0
		local baseCurve1: number = props.curveSize1
		local baseBrightness: number = props.brightness
		local baseTextureSpeed: number = props.textureSpeed

		local a0 = Common.newAttachment(ctx, component.id, component.name .. "_A0")
		local a1 = Common.newAttachment(ctx, component.id, component.name .. "_A1")
		local builtA0, builtA1 = attachmentFrames(CFrame.new(), baseFrom, baseTo, curveDirection, roll)
		a0.CFrame = builtA0
		a1.CFrame = builtA1

		local beam = Instance.new("Beam")
		beam.Name = component.name
		beam.Enabled = false
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Texture = props.texture
		beam.Color = baseColor
		beam.Transparency = baseTransparency
		beam.Width0 = baseWidth0 * component.scale
		beam.Width1 = baseWidth1 * component.scale
		beam.CurveSize0 = baseCurve0
		beam.CurveSize1 = baseCurve1
		beam.Segments = segmentCount(props.segments, baseColor, baseTransparency)
		beam.TextureLength = props.textureLength
		beam.TextureMode = props.textureMode
		local builtTextureSpeed = baseTextureSpeed * builtTimeScale
		beam.TextureSpeed = builtTextureSpeed
		beam.FaceCamera = props.faceCamera
		beam.LightEmission = props.lightEmission
		beam.LightInfluence = props.lightInfluence
		beam.Brightness = baseBrightness
		beam.ZOffset = props.zOffset
		ctx.tagInstance(beam, component.id)
		beam.Parent = ctx.root

		local active = false
		local enabledByEvent = true
		local released = false
		local enabled = false
		local scale = component.scale
		local width0 = baseWidth0
		local width1 = baseWidth1
		local curve0 = baseCurve0
		local curve1 = baseCurve1
		local from = baseFrom
		local to = baseTo
		local fade = 0
		local tint = WHITE
		local brightness = baseBrightness
		local textureSpeed = baseTextureSpeed
		local effectTimeScale = builtTimeScale
		local writtenTextureSpeed = builtTextureSpeed
		local localCFrame = CFrame.new()
		local lastA0 = builtA0
		local lastA1 = builtA1

		local function refreshEnabled()
			local on = active and enabledByEvent and not released
			if on ~= enabled then
				enabled = on
				beam.Enabled = on
			end
		end

		local function refreshAttachments()
			local cf0, cf1 = attachmentFrames(localCFrame, from, to, curveDirection, roll)
			if cf0 ~= lastA0 then
				lastA0 = cf0
				a0.CFrame = cf0
			end
			if cf1 ~= lastA1 then
				lastA1 = cf1
				a1.CFrame = cf1
			end
		end

		-- Beam.TextureSpeed = authored × effect time scale, written only when it changes.
		local function writeTextureSpeed()
			local v = textureSpeed * effectTimeScale
			if v ~= writtenTextureSpeed then
				writtenTextureSpeed = v
				beam.TextureSpeed = v
			end
		end

		local controller = Common.controller(component, { beam, a0, a1 })

		function controller.setActive(_self, isActive: boolean, _frame: FrameContext)
			if isActive ~= active then
				active = isActive
				refreshEnabled()
			end
		end

		function controller.apply(_self, name: string, value: any)
			local isNumber = type(value) == "number"
			if name == "scale" then
				if isNumber then
					local v = math.max(value, 0)
					if v ~= scale then
						scale = v
						beam.Width0 = width0 * v
						beam.Width1 = width1 * v
					end
				end
			elseif name == "width0" then
				if isNumber then
					local v = math.max(value, 0)
					if v ~= width0 then
						width0 = v
						beam.Width0 = v * scale
					end
				end
			elseif name == "width1" then
				if isNumber then
					local v = math.max(value, 0)
					if v ~= width1 then
						width1 = v
						beam.Width1 = v * scale
					end
				end
			elseif name == "curveSize0" then
				if isNumber and value ~= curve0 then
					curve0 = value
					beam.CurveSize0 = value
				end
			elseif name == "curveSize1" then
				if isNumber and value ~= curve1 then
					curve1 = value
					beam.CurveSize1 = value
				end
			elseif name == "from" then
				if typeof(value) == "Vector3" and value ~= from then
					from = value
					refreshAttachments()
				end
			elseif name == "to" then
				if typeof(value) == "Vector3" and value ~= to then
					to = value
					refreshAttachments()
				end
			elseif name == "transparency" then
				if isNumber then
					local v = math.clamp(value, 0, 1)
					if v ~= fade then
						fade = v
						beam.Transparency = Common.fadeSequence(baseTransparency, v)
					end
				end
			elseif name == "tint" then
				if typeof(value) == "Color3" and value ~= tint then
					tint = value
					beam.Color = Common.tintSequence(baseColor, value)
				end
			elseif name == "brightness" then
				if isNumber then
					local v = math.clamp(value, 0, 100)
					if v ~= brightness then
						brightness = v
						beam.Brightness = v
					end
				end
			elseif name == "textureSpeed" then
				if isNumber and value ~= textureSpeed then
					textureSpeed = value
					writeTextureSpeed()
				end
			end
		end

		function controller.setTransform(_self, newLocalCFrame: CFrame, _worldCFrame: CFrame, _frame: FrameContext)
			if newLocalCFrame ~= localCFrame then
				localCFrame = newLocalCFrame
				refreshAttachments()
			end
		end

		function controller.onAction(_self, action: Types.ScheduledAction, _frame: FrameContext)
			if action.action == "enable" then
				enabledByEvent = true
				refreshEnabled()
			elseif action.action == "disable" then
				enabledByEvent = false
				refreshEnabled()
			end
		end

		function controller.setTimeScale(_self, scale: number)
			if isFinite(scale) and scale >= 0 and scale ~= effectTimeScale then
				effectTimeScale = scale
				writeTextureSpeed()
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
			beam.Enabled = false
			scale = component.scale
			width0 = baseWidth0
			width1 = baseWidth1
			beam.Width0 = baseWidth0 * scale
			beam.Width1 = baseWidth1 * scale
			curve0 = baseCurve0
			curve1 = baseCurve1
			beam.CurveSize0 = baseCurve0
			beam.CurveSize1 = baseCurve1
			fade = 0
			beam.Transparency = baseTransparency
			tint = WHITE
			beam.Color = baseColor
			brightness = baseBrightness
			beam.Brightness = baseBrightness
			textureSpeed = baseTextureSpeed
			effectTimeScale = builtTimeScale
			writtenTextureSpeed = builtTextureSpeed
			beam.TextureSpeed = builtTextureSpeed
			from = baseFrom
			to = baseTo
			localCFrame = CFrame.new()
			lastA0 = builtA0
			lastA1 = builtA1
			a0.CFrame = builtA0
			a1.CFrame = builtA1
		end

		return controller
	end,
	estimateCost = function(component: CompiledComponent, _quality: Types.QualityProfile): Types.CostEstimate
		local props = component.props
		local cost = Common.cost()
		cost.instances = 3
		cost.attachments = 2
		cost.beams = 1
		local moving = Common.isMoving(component)
		-- Heuristic: one write per non-transform track; transform changes rewrite both attachment CFrames.
		cost.propertyUpdates = countTracksExcept(component, TRANSFORM_TRACKS) + (if moving then 2 else 0)
		cost.transparentLayers = 1
		-- Heuristic overdraw: ribbon area = mean width × straight length.
		local from: Vector3 = props.from
		local to: Vector3 = props.to
		local meanWidth = (props.width0 + props.width1) / 2 * component.scale
		cost.overdrawWeight = meanWidth * (to - from).Magnitude
		return cost
	end,
}

return descriptor
