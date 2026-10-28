--!strict
--[[
	Common — shared helpers for component descriptors (Core/Components/*).

	Every descriptor should build its PropertySpecs with Common.prop, create Roblox instances with
	Common.newPart / Common.newAttachment (consistent, physics-free, non-colliding instances), start its
	controller from Common.controller (no-op defaults for every ComponentInstance method) and its cost
	estimate from Common.cost.

	Camera components (cameraShake, screenFlash) reach engine services only through Core/Env
	(Common.tryService / Common.hasLocalPlayer / Common.currentCamera), so specs can substitute clients, servers and
	cameras with Env.override.
]]

local Env = require(script.Parent.Parent.Env)
local Types = require(script.Parent.Parent.Types)

type PropertySpec = Types.PropertySpec
type PropertyKind = Types.PropertyKind
type ChannelSpec = Types.ChannelSpec
type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type BuildContext = Types.BuildContext
type CostEstimate = Types.CostEstimate
type FrameContext = Types.FrameContext

local Common = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Spec helpers
-- ─────────────────────────────────────────────────────────────────────────────

export type PropOptions = {
	label: string?,
	category: string?,
	min: number?,
	max: number?,
	step: number?,
	enum: { string }?,
	enumType: string?,
	componentTypes: { string }?,
	scale: Types.ScaleRule?,
	quality: Types.QualityRule?,
	advanced: boolean?,
	maxKeypoints: number?,
}

function Common.prop(
	name: string,
	kind: PropertyKind,
	default: any,
	description: string,
	options: PropOptions?
): PropertySpec
	local o: PropOptions = options or {}
	return {
		name = name,
		kind = kind,
		default = default,
		description = description,
		label = o.label,
		category = o.category,
		min = o.min,
		max = o.max,
		step = o.step,
		enum = o.enum,
		enumType = o.enumType,
		componentTypes = o.componentTypes,
		scale = o.scale,
		quality = o.quality,
		advanced = o.advanced,
		maxKeypoints = if kind == "numberSequence" or kind == "colorSequence" then (o.maxKeypoints or 20) else nil,
	}
end

export type ChannelOptions = {
	label: string?,
	min: number?,
	max: number?,
	scale: Types.ScaleRule?,
	baseProperty: string?,
}

function Common.channel(
	name: string,
	kind: Types.ChannelKind,
	description: string,
	options: ChannelOptions?
): ChannelSpec
	local o: ChannelOptions = options or {}
	return {
		name = name,
		kind = kind,
		description = description,
		label = o.label,
		min = o.min,
		max = o.max,
		scale = o.scale,
		baseProperty = o.baseProperty,
	}
end

-- Channels every positioned component supports. "position"/"rotation" are relative to the parent component.
function Common.transformChannels(): { ChannelSpec }
	return {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		Common.channel("scale", "number", "Uniform size multiplier of this component.", { min = 0 }),
	}
end

-- Optional constant spin (degrees per second) added to the rotation over the component's lifetime.
function Common.spinProperty(): PropertySpec
	return Common.prop(
		"spin",
		"vector3",
		{ 0, 0, 0 },
		"Constant rotation speed in degrees/second around X, Y, Z (procedural motion).",
		{ category = "Motion" }
	)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Instance helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Creates an anchored, non-colliding, shadowless part parented to the effect container.
function Common.newPart(ctx: BuildContext, componentId: string, name: string, className: string?): BasePart
	local part = Instance.new(className or "Part") :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.AudioCanCollide = false
	part.Locked = not ctx.isPreview
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = ctx.root.CFrame
	ctx.tagInstance(part, componentId)
	part.Parent = ctx.container
	return part
end

-- Creates an attachment on `parent` (default: the effect root part). Attachments move with their part.
function Common.newAttachment(ctx: BuildContext, componentId: string, name: string, parent: BasePart?): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	ctx.tagInstance(attachment, componentId)
	attachment.Parent = parent or ctx.root
	return attachment
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Run-context helpers (camera components)
-- ─────────────────────────────────────────────────────────────────────────────

-- The service `name` through Env (overrides win), or nil when it is unavailable (e.g. no DataModel in the CLI).
function Common.tryService(name: string): any
	local ok, service = pcall(Env.getService :: any, name)
	return if ok then service else nil
end

-- True when this machine has a local player (Players.LocalPlayer ~= nil): a client. False on servers, in Studio
-- edit mode (no LocalPlayer) and when the Players service is unavailable.
function Common.hasLocalPlayer(): boolean
	local ok, player = pcall(function(): any
		local players: any = Env.getService("Players")
		return players.LocalPlayer
	end)
	return ok and player ~= nil
end

-- `workspaceService.CurrentCamera` (the local player's / Studio's camera), or nil.
function Common.currentCamera(workspaceService: any): Camera?
	if workspaceService == nil then
		return nil
	end
	local camera = workspaceService.CurrentCamera
	if typeof(camera) == "Instance" and camera:IsA("Camera") then
		return camera
	end
	return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Math helpers
-- ─────────────────────────────────────────────────────────────────────────────

local rad = math.rad

function Common.cframeFrom(position: Vector3, rotationDegrees: Vector3): CFrame
	return CFrame.new(position)
		* CFrame.fromOrientation(rad(rotationDegrees.X), rad(rotationDegrees.Y), rad(rotationDegrees.Z))
end

-- Combines an authored transparency sequence with a fade value: t' = 1 - (1 - t) * (1 - fade).
function Common.fadeSequence(base: NumberSequence, fade: number): NumberSequence
	if fade <= 0 then
		return base
	end
	local f = math.clamp(fade, 0, 1)
	local keys = {}
	for i, k in base.Keypoints do
		local v = 1 - (1 - k.Value) * (1 - f)
		keys[i] = NumberSequenceKeypoint.new(k.Time, math.clamp(v, 0, 1), k.Envelope)
	end
	return NumberSequence.new(keys)
end

-- Multiplies all values (and envelopes) of a number sequence, e.g. particle Size × scale.
function Common.scaleSequence(base: NumberSequence, factor: number): NumberSequence
	if factor == 1 then
		return base
	end
	local keys = {}
	for i, k in base.Keypoints do
		keys[i] = NumberSequenceKeypoint.new(k.Time, k.Value * factor, k.Envelope * factor)
	end
	return NumberSequence.new(keys)
end

-- Multiplies every colour of a sequence component-wise by `tint` (white = unchanged).
function Common.tintSequence(base: ColorSequence, tint: Color3): ColorSequence
	if tint.R == 1 and tint.G == 1 and tint.B == 1 then
		return base
	end
	local keys = {}
	for i, k in base.Keypoints do
		local c = k.Value
		keys[i] = ColorSequenceKeypoint.new(k.Time, Color3.new(c.R * tint.R, c.G * tint.G, c.B * tint.B))
	end
	return ColorSequence.new(keys)
end

function Common.scaleRange(range: NumberRange, factor: number): NumberRange
	if factor == 1 then
		return range
	end
	return NumberRange.new(range.Min * factor, range.Max * factor)
end

-- Scales a count by quality and rounds; keeps at least `minimum` (default 0) when the source is > 0.
function Common.scaledCount(value: number, factor: number, minimum: number?): number
	local n = math.floor(value * factor + 0.5)
	if value > 0 then
		n = math.max(n, minimum or 0)
	end
	return n
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Controller & cost helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Returns a ComponentInstance with no-op defaults. Descriptors override the methods they need.
function Common.controller(component: CompiledComponent, instances: { Instance }): ComponentInstance
	local controller: ComponentInstance = {
		component = component,
		instances = instances,
		anchor = nil,
		setActive = function(_self: ComponentInstance, _active: boolean, _frame: FrameContext) end,
		apply = function(_self: ComponentInstance, _channel: string, _value: any) end,
		setTransform = function(
			_self: ComponentInstance,
			_localCFrame: CFrame,
			_worldCFrame: CFrame,
			_frame: FrameContext
		)
		end,
		onAction = function(_self: ComponentInstance, _action: Types.ScheduledAction, _frame: FrameContext) end,
		update = nil,
		setTimeScale = nil,
		release = function(_self: ComponentInstance) end,
		reset = function(_self: ComponentInstance) end,
		destroy = function(self: ComponentInstance)
			for _, inst in self.instances do
				inst:Destroy()
			end
			table.clear(self.instances)
		end,
	}
	return controller
end

function Common.cost(): CostEstimate
	return {
		instances = 0,
		parts = 0,
		attachments = 0,
		emitters = 0,
		beams = 0,
		trails = 0,
		lights = 0,
		shadowLights = 0,
		sounds = 0,
		continuousRate = 0,
		burstCount = 0,
		maxLifetime = 0,
		movingParts = 0,
		propertyUpdates = 0,
		transparentLayers = 0,
		overdrawWeight = 0,
		notes = nil,
	}
end

-- Number of channels of a component that have tracks (used for propertyUpdates estimates).
function Common.trackCount(component: CompiledComponent): number
	local n = 0
	for _ in component.tracks do
		n += 1
	end
	return n
end

-- True when the component moves every frame (transform tracks or spin).
function Common.isMoving(component: CompiledComponent): boolean
	local t = component.tracks
	if t.position or t.rotation or t.scale then
		return true
	end
	local spin = component.props.spin
	return typeof(spin) == "Vector3" and spin.Magnitude > 0
end

return Common
