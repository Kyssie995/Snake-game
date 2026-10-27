--!strict
--[[
	light — a native PointLight / SpotLight / SurfaceLight (docs/COMPONENTS_SPEC.md §7).

	Local lights only illuminate as DIRECT children of a BasePart or Attachment under Workspace (engine docs):
	  Point / Spot: the light inside an Attachment on the effect Root (Attachment.CFrame = component transform;
	                for a SpotLight on an attachment `face` picks the attachment axis, Front = −Z).
	  Surface:      the SurfaceLight inside an invisible host Part (Common.newPart, Size = surfaceSize) that moves
	                through frame.moveParts; `face` picks the part face that emits.
	The light is the first entry of `instances`.

	Behaviour:
	  * Enabled = active (and not disabled by an event, not released).
	  * Range is clamped to Constants.MAX_LIGHT_RANGE (120) after the Compiler's scaling and for the range channel.
	  * Shadows = shadows and quality.lightShadows.
	  * Angle/Face only exist on Spot/Surface lights; the `angle` channel is ignored for Point lights.
	  * Channels: position, rotation, brightness, range, color, angle (each caches its last value).
]]

local Common = require(script.Parent.Common)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)

type FrameContext = Types.FrameContext
type CompiledComponent = Types.CompiledComponent

local prop = Common.prop
local channel = Common.channel

local function clampRange(v: number): number
	return math.clamp(v, 0, Constants.MAX_LIGHT_RANGE)
end

local function clampAngle(v: number): number
	return math.clamp(v, 0, Constants.MAX_SPOTLIGHT_ANGLE)
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
	type = "light",
	displayName = "Light",
	category = "Lighting",
	description = "Native point, spot or surface light that illuminates the surroundings.",
	icon = "☀",
	properties = {
		prop(
			"lightType",
			"enum",
			"Point",
			"Light class: Point (all directions), Spot (cone) or Surface (from a part face).",
			{ category = "Light", enum = { "Point", "Spot", "Surface" } }
		),
		prop("color", "color3", "#FFFFFF", "Light colour.", { category = "Light" }),
		prop("brightness", "number", 1, "Light brightness.", { category = "Light", min = 0, max = 100 }),
		prop(
			"range",
			"number",
			8,
			"Reach in studs (clamped to 120 after scaling).",
			{ category = "Light", min = 0, max = 120, scale = "length" }
		),
		prop(
			"angle",
			"number",
			90,
			"Cone angle in degrees (Spot / Surface).",
			{ category = "Light", min = 0, max = 180 }
		),
		prop("face", "enum", "Front", "Face the light shines from (Spot / Surface). On an attachment Front = −Z.", {
			category = "Light",
			enum = { "Front", "Back", "Top", "Bottom", "Left", "Right" },
			enumType = "NormalId",
		}),
		prop(
			"shadows",
			"boolean",
			false,
			"Cast shadows (only when the quality profile allows light shadows).",
			{ category = "Light" }
		),
		prop(
			"surfaceSize",
			"vector3",
			{ 4, 4, 0.2 },
			"Size of the emitting host part (Surface only).",
			{ category = "Light", scale = "length" }
		),
	},
	channels = {
		channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		channel("brightness", "number", "Light brightness.", { min = 0, max = 100, baseProperty = "brightness" }),
		channel("range", "number", "Reach in studs (clamped to 120).", {
			min = 0,
			max = 120,
			scale = "length",
			baseProperty = "range",
		}),
		channel("color", "color3", "Light colour.", { baseProperty = "color" }),
		channel("angle", "number", "Cone angle in degrees (Spot / Surface).", {
			min = 0,
			max = 180,
			baseProperty = "angle",
		}),
	},
	events = {
		{ action = "enable", description = "Turns the light on (while active)." },
		{ action = "disable", description = "Turns the light off." },
	},
	canParent = true,
	supportsViewport = false,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): Types.ComponentInstance
		local props = component.props
		local lightType: string = props.lightType
		local baseColor: Color3 = props.color
		local baseBrightness: number = props.brightness
		local baseRange = clampRange(props.range)
		local baseAngle = clampAngle(props.angle)
		local shadows = props.shadows == true and ctx.effect.quality.lightShadows == true

		local pointLight: PointLight? = nil
		local spotLight: SpotLight? = nil
		local surfaceLight: SurfaceLight? = nil
		local light: Light
		if lightType == "Spot" then
			local l = Instance.new("SpotLight")
			l.Range = baseRange
			l.Angle = baseAngle
			l.Face = props.face
			spotLight = l
			light = l
		elseif lightType == "Surface" then
			local l = Instance.new("SurfaceLight")
			l.Range = baseRange
			l.Angle = baseAngle
			l.Face = props.face
			surfaceLight = l
			light = l
		else
			local l = Instance.new("PointLight")
			l.Range = baseRange
			pointLight = l
			light = l
		end
		light.Name = component.name
		light.Enabled = false
		light.Color = baseColor
		light.Brightness = baseBrightness
		light.Shadows = shadows
		ctx.tagInstance(light, component.id)

		local attachment: Attachment? = nil
		local hostPart: BasePart? = nil
		local instances: { Instance } = { light }
		if surfaceLight then
			local p = Common.newPart(ctx, component.id, component.name)
			p.Size = props.surfaceSize
			light.Parent = p
			hostPart = p
			table.insert(instances, p)
		else
			local a = Common.newAttachment(ctx, component.id, component.name)
			light.Parent = a
			attachment = a
			table.insert(instances, a)
		end
		local builtHostCFrame = ctx.root.CFrame

		local active = false
		local enabledByEvent = true
		local released = false
		local enabled = false
		local color = baseColor
		local brightness = baseBrightness
		local range = baseRange
		local angle = baseAngle
		local lastCFrame: CFrame? = nil

		local function refreshEnabled()
			local on = active and enabledByEvent and not released
			if on ~= enabled then
				enabled = on
				light.Enabled = on
			end
		end

		local function writeRange(v: number)
			if pointLight then
				pointLight.Range = v
			elseif spotLight then
				spotLight.Range = v
			elseif surfaceLight then
				surfaceLight.Range = v
			end
		end

		local function writeAngle(v: number)
			if spotLight then
				spotLight.Angle = v
			elseif surfaceLight then
				surfaceLight.Angle = v
			end
		end

		local controller = Common.controller(component, instances)

		function controller.setActive(_self, isActive: boolean, _frame: FrameContext)
			if isActive ~= active then
				active = isActive
				refreshEnabled()
			end
		end

		function controller.apply(_self, name: string, value: any)
			if name == "brightness" then
				if type(value) == "number" then
					local v = math.clamp(value, 0, 100)
					if v ~= brightness then
						brightness = v
						light.Brightness = v
					end
				end
			elseif name == "range" then
				if type(value) == "number" then
					local v = clampRange(value)
					if v ~= range then
						range = v
						writeRange(v)
					end
				end
			elseif name == "color" then
				if typeof(value) == "Color3" and value ~= color then
					color = value
					light.Color = value
				end
			elseif name == "angle" then
				if type(value) == "number" and pointLight == nil then
					local v = clampAngle(value)
					if v ~= angle then
						angle = v
						writeAngle(v)
					end
				end
			end
		end

		function controller.setTransform(_self, localCFrame: CFrame, worldCFrame: CFrame, frame: FrameContext)
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

		function controller.onAction(_self, action: Types.ScheduledAction, _frame: FrameContext)
			if action.action == "enable" then
				enabledByEvent = true
				refreshEnabled()
			elseif action.action == "disable" then
				enabledByEvent = false
				refreshEnabled()
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
			light.Enabled = false
			color = baseColor
			light.Color = baseColor
			brightness = baseBrightness
			light.Brightness = baseBrightness
			range = baseRange
			writeRange(baseRange)
			angle = baseAngle
			writeAngle(baseAngle)
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
		local isSurface = props.lightType == "Surface"
		local cost = Common.cost()
		cost.instances = 2
		cost.lights = 1
		if isSurface then
			cost.parts = 1
		else
			cost.attachments = 1
		end
		if props.shadows == true and quality.lightShadows == true then
			cost.shadowLights = 1
		end
		local moving = Common.isMoving(component)
		cost.movingParts = if moving and isSurface then 1 else 0
		-- Heuristic: one write per non-transform track, plus the attachment CFrame write when moving.
		cost.propertyUpdates = countTracksExcept(component, TRANSFORM_TRACKS)
			+ (if moving and not isSurface then 1 else 0)
		if cost.shadowLights > 0 and moving then
			cost.notes = { "Moving shadow-casting lights are expensive; prefer shadows = false for fast effects." }
		end
		return cost
	end,
}

return descriptor
