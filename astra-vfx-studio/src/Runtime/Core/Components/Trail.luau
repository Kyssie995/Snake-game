--!strict
--[[
	trail — a native Trail between two Attachments (docs/COMPONENTS_SPEC.md §4).

	Instances: Trail (parented to the effect Root part) + Attachment0/1 on the Root at ∓width/2 along
	`widthDirection` around the component's position:
	  A0 = localCFrame · CFrame(−dir · w/2),  A1 = localCFrame · CFrame(+dir · w/2),  w = width × scale
	The trail only draws while the attachments move (animate `position`, spin a parent group or attach the effect
	to a moving part). Re-assigning Trail.Attachment0/1 clears the drawn segments (engine), so ASTRA assigns them once
	and afterwards only moves the attachments through Attachment.CFrame.

	Behaviour:
	  * Enabled = active (and not disabled by an event, not released). Inactive / released trails stop adding
	    segments; existing segments fade out over `lifetime` (tailTime = lifetime).
	  * clearOnStart: Clear() when the component becomes active, and once more after the first transform of the
	    activation so the jump from the previous position never leaves a streak.
	  * Seeking: every transform with frame.seeking clears the drawn segments after moving the attachments. Trail
	    segments cannot be reconstructed for a scrubbed time (like particles, which the Player clears on seek), and
	    without the clear every scrub jump would leave a streak between the scrubbed positions. Playback frames
	    never clear, so drawing continues from the scrubbed position.
	  * Channels: transform (scale = width multiplier), width, transparency (fade), tint, brightness.
]]

local Common = require(script.Parent.Common)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)

type FrameContext = Types.FrameContext
type CompiledComponent = Types.CompiledComponent

local prop = Common.prop
local channel = Common.channel

local WHITE = Color3.new(1, 1, 1)

local function direction(v: Vector3): Vector3
	return if v.Magnitude > 1e-6 then v.Unit else Vector3.new(0, 1, 0)
end

local function attachmentFrames(localCFrame: CFrame, dir: Vector3, width: number): (CFrame, CFrame)
	local half = dir * (width / 2)
	return localCFrame * CFrame.new(-half), localCFrame * CFrame.new(half)
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
	type = "trail",
	displayName = "Trail",
	category = "Beams & Trails",
	description = "Native Trail: a ribbon left behind by the moving component (swings, dashes, projectiles).",
	icon = "〰",
	properties = {
		prop(
			"width",
			"number",
			1,
			"Trail width in studs (separation of the two attachments).",
			{ category = "Shape", min = 0, max = 100, scale = "length" }
		),
		prop(
			"widthDirection",
			"vector3",
			{ 0, 1, 0 },
			"Component-space axis the two attachments are spread along.",
			{ category = "Shape" }
		),
		prop(
			"lifetime",
			"number",
			0.5,
			"Seconds a trail segment stays visible.",
			{ category = "Shape", min = 0.01, max = 20 }
		),
		prop(
			"minLength",
			"number",
			0.1,
			"Minimum movement in studs before a new segment is created.",
			{ category = "Shape", min = 0, max = 100, scale = "length" }
		),
		prop(
			"maxLength",
			"number",
			0,
			"Maximum trail length in studs (0 = unlimited).",
			{ category = "Shape", min = 0, max = 10000, scale = "length" }
		),
		prop(
			"widthScale",
			"numberSequence",
			1,
			"Width multiplier over the segment lifetime (0..1, centred).",
			{ category = "Shape", min = 0, max = 1 }
		),
		prop("color", "colorSequence", "#FFFFFF", "Colour over the segment lifetime.", { category = "Appearance" }),
		prop(
			"transparency",
			"numberSequence",
			0,
			"Transparency over the segment lifetime.",
			{ category = "Appearance", min = 0, max = 1 }
		),
		prop("texture", "asset", "", "Trail texture (empty = solid colour).", { category = "Appearance" }),
		prop(
			"textureLength",
			"number",
			1,
			"Texture repeat length in studs.",
			{ category = "Appearance", scale = "length" }
		),
		prop(
			"textureMode",
			"enum",
			"Stretch",
			"Stretch over the lifetime, Wrap (tile) or Static (stamped, e.g. footprints).",
			{ category = "Appearance", enum = { "Stretch", "Wrap", "Static" }, enumType = "TextureMode" }
		),
		prop("faceCamera", "boolean", false, "Turn the ribbon towards the camera.", { category = "Appearance" }),
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
			"How much environment lighting tints the trail.",
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
			"clearOnStart",
			"boolean",
			true,
			"Clear previously drawn segments when the component becomes active.",
			{ category = "Shape" }
		),
		Common.spinProperty(),
	},
	channels = {
		channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		channel("scale", "number", "Width multiplier (× width).", { min = 0 }),
		channel("width", "number", "Trail width in studs.", {
			min = 0,
			max = 100,
			scale = "length",
			baseProperty = "width",
		}),
		channel(
			"transparency",
			"number",
			"Fade over the authored transparency: t' = 1 - (1 - t)(1 - fade). Affects drawn segments.",
			{ min = 0, max = 1 }
		),
		channel("tint", "color3", "Multiplies the authored colour sequence (white = unchanged)."),
		channel("brightness", "number", "Brightness multiplier.", { min = 0, max = 100, baseProperty = "brightness" }),
	},
	events = {
		{ action = "enable", description = "Resumes drawing new segments (while active)." },
		{ action = "disable", description = "Stops drawing new segments; drawn segments fade out." },
		{ action = "clear", description = "Removes all drawn segments immediately." },
	},
	canParent = true,
	supportsViewport = false,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): Types.ComponentInstance
		local props = component.props
		local dir = direction(props.widthDirection)
		local baseWidth: number = props.width
		local baseColor: ColorSequence = props.color
		local baseTransparency: NumberSequence = props.transparency
		local baseBrightness: number = props.brightness
		local clearOnStart: boolean = props.clearOnStart

		local a0 = Common.newAttachment(ctx, component.id, component.name .. "_A0")
		local a1 = Common.newAttachment(ctx, component.id, component.name .. "_A1")
		local builtA0, builtA1 = attachmentFrames(CFrame.new(), dir, baseWidth * component.scale)
		a0.CFrame = builtA0
		a1.CFrame = builtA1

		local trail = Instance.new("Trail")
		trail.Name = component.name
		trail.Enabled = false
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = math.clamp(props.lifetime, 0.01, Constants.MAX_TRAIL_LIFETIME)
		trail.MinLength = props.minLength
		trail.MaxLength = props.maxLength
		trail.WidthScale = props.widthScale
		trail.Color = baseColor
		trail.Transparency = baseTransparency
		trail.Texture = props.texture
		trail.TextureLength = props.textureLength
		trail.TextureMode = props.textureMode
		trail.FaceCamera = props.faceCamera
		trail.LightEmission = props.lightEmission
		trail.LightInfluence = props.lightInfluence
		trail.Brightness = baseBrightness
		ctx.tagInstance(trail, component.id)
		trail.Parent = ctx.root

		local active = false
		local enabledByEvent = true
		local released = false
		local enabled = false
		local clearPending = false
		local scale = component.scale
		local width = baseWidth
		local fade = 0
		local tint = WHITE
		local brightness = baseBrightness
		local localCFrame = CFrame.new()
		local lastA0 = builtA0
		local lastA1 = builtA1

		local function refreshEnabled()
			local on = active and enabledByEvent and not released
			if on ~= enabled then
				enabled = on
				trail.Enabled = on
			end
		end

		local function refreshAttachments()
			local cf0, cf1 = attachmentFrames(localCFrame, dir, width * scale)
			if cf0 ~= lastA0 then
				lastA0 = cf0
				a0.CFrame = cf0
			end
			if cf1 ~= lastA1 then
				lastA1 = cf1
				a1.CFrame = cf1
			end
		end

		local controller = Common.controller(component, { trail, a0, a1 })

		function controller.setActive(_self, isActive: boolean, _frame: FrameContext)
			if isActive == active then
				return
			end
			active = isActive
			clearPending = isActive and clearOnStart
			if clearPending then
				trail:Clear()
			end
			refreshEnabled()
		end

		function controller.apply(_self, name: string, value: any)
			local isNumber = type(value) == "number"
			if name == "scale" then
				if isNumber then
					local v = math.max(value, 0)
					if v ~= scale then
						scale = v
						refreshAttachments()
					end
				end
			elseif name == "width" then
				if isNumber then
					local v = math.max(value, 0)
					if v ~= width then
						width = v
						refreshAttachments()
					end
				end
			elseif name == "transparency" then
				if isNumber then
					local v = math.clamp(value, 0, 1)
					if v ~= fade then
						fade = v
						trail.Transparency = Common.fadeSequence(baseTransparency, v)
					end
				end
			elseif name == "tint" then
				if typeof(value) == "Color3" and value ~= tint then
					tint = value
					trail.Color = Common.tintSequence(baseColor, value)
				end
			elseif name == "brightness" then
				if isNumber then
					local v = math.clamp(value, 0, 100)
					if v ~= brightness then
						brightness = v
						trail.Brightness = v
					end
				end
			end
		end

		function controller.setTransform(_self, newLocalCFrame: CFrame, _worldCFrame: CFrame, frame: FrameContext)
			if newLocalCFrame ~= localCFrame then
				localCFrame = newLocalCFrame
				refreshAttachments()
			end
			-- Seeking: the state at a scrubbed time has no drawn segments (see header). clearPending: the attachments
			-- now sit at the activation position, so drop anything drawn from the old one.
			if frame.seeking or clearPending then
				clearPending = false
				trail:Clear()
			end
		end

		function controller.onAction(_self, action: Types.ScheduledAction, _frame: FrameContext)
			local kind = action.action
			if kind == "enable" then
				enabledByEvent = true
				refreshEnabled()
			elseif kind == "disable" then
				enabledByEvent = false
				refreshEnabled()
			elseif kind == "clear" then
				trail:Clear()
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
			clearPending = false
			trail.Enabled = false
			scale = component.scale
			width = baseWidth
			fade = 0
			trail.Transparency = baseTransparency
			tint = WHITE
			trail.Color = baseColor
			brightness = baseBrightness
			trail.Brightness = baseBrightness
			localCFrame = CFrame.new()
			lastA0 = builtA0
			lastA1 = builtA1
			a0.CFrame = builtA0
			a1.CFrame = builtA1
			trail:Clear()
		end

		return controller
	end,
	estimateCost = function(component: CompiledComponent, _quality: Types.QualityProfile): Types.CostEstimate
		local props = component.props
		local cost = Common.cost()
		cost.instances = 3
		cost.attachments = 2
		cost.trails = 1
		local lifetime: number = math.clamp(props.lifetime, 0.01, Constants.MAX_TRAIL_LIFETIME)
		cost.maxLifetime = lifetime
		local moving = Common.isMoving(component)
		-- Heuristic: one write per non-transform track; transform changes rewrite both attachment CFrames.
		cost.propertyUpdates = countTracksExcept(component, TRANSFORM_TRACKS) + (if moving then 2 else 0)
		cost.transparentLayers = 1
		-- Heuristic overdraw: width × lifetime × an assumed 20 studs/s of motion.
		cost.overdrawWeight = props.width * component.scale * lifetime * 20
		if not moving then
			cost.notes =
				{ "The trail itself does not move; it only draws if a parent moves or the effect is attached." }
		end
		return cost
	end,
	tailTime = function(component: CompiledComponent): number
		return math.clamp(component.props.lifetime, 0.01, Constants.MAX_TRAIL_LIFETIME)
	end,
}

return descriptor
