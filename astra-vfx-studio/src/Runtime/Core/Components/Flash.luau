--!strict
--[[
	flash — procedural impact flash: a Ball part plus an optional PointLight on an Attachment, driven by a built-in
	attack → hold → decay envelope over the component's local time. docs/COMPONENTS_SPEC.md §10.

	Pure function of (localTime, props, colour channel) — no randomness, so the seed is not used. With
	A = attack, H = hold, D = decay, T = A + H + D and t = localTime:
	  envelope e(t) = t / A                    for 0 <= t < A   (A = 0: peak immediately)
	                = 1                        for A <= t < A + H
	                = 1 − (t − A − H) / D      for A + H <= t < T
	                = 0                        for t >= T
	  diameter(t)   = startSize + (size − startSize) × CubicOut(clamp(t / T, 0, 1))      × scale
	                  (fast growth while the flash is bright, `size` = final diameter at the end of the decay)
	  Transparency  = 1 − e(t)                 (0 at the peak, 1 at the end of the decay)
	  Light         Brightness = e(t) × peakBrightness, Enabled while e(t) > 0, Range = range × scale (≤ 120),
	                Color = `color`.
	`scale` is the rest value transform.scale (the component has no scale channel). The light is not built in
	viewport mode (lights do not render in a ViewportFrame). Invisible until setActive(true).
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type FrameContext = Types.FrameContext
type CostEstimate = Types.CostEstimate

local MIN_SIZE = 0.001
local MAX_SIZE = 2048
local MAX_LIGHT_RANGE = 120
-- Envelope values below this count as 0 (float residue at the end of the decay must not keep the light on).
local ENVELOPE_EPSILON = 1e-9

-- Enum.Material items without the NotBrowsable terrain-only entries (Air, Water). API dump 0.745.
local MATERIALS = {
	"Plastic",
	"SmoothPlastic",
	"Neon",
	"Wood",
	"WoodPlanks",
	"Marble",
	"Basalt",
	"Slate",
	"CrackedLava",
	"Concrete",
	"Limestone",
	"Granite",
	"Pavement",
	"Brick",
	"Pebble",
	"Cobblestone",
	"Rock",
	"Sandstone",
	"CorrodedMetal",
	"DiamondPlate",
	"Foil",
	"Metal",
	"Grass",
	"LeafyGrass",
	"Sand",
	"Fabric",
	"Snow",
	"Mud",
	"Ground",
	"Asphalt",
	"Salt",
	"Ice",
	"Glacier",
	"Glass",
	"ForceField",
	"Cardboard",
	"Carpet",
	"CeramicTiles",
	"ClayRoofTiles",
	"RoofShingles",
	"Leather",
	"Plaster",
	"Rubber",
}

-- Envelope value (0..1) at local time t.
local function envelope(t: number, attack: number, hold: number, decay: number): number
	if t < 0 then
		return 0
	end
	if t < attack then
		return t / attack
	end
	local decayStart = attack + hold
	if t < decayStart then
		return 1
	end
	if decay <= 0 then
		return 0
	end
	local e = 1 - (t - decayStart) / decay
	if e <= ENVELOPE_EPSILON then
		return 0
	end
	return e
end

-- Diameter progress (0..1, Cubic.Out over the whole envelope).
local function growth(t: number, total: number): number
	if total <= 0 then
		return 1
	end
	local p = math.clamp(t / total, 0, 1)
	local q = 1 - p
	return 1 - q * q * q
end

local descriptor: Types.ComponentDescriptor = {
	type = "flash",
	displayName = "Impact Flash",
	category = "Procedural",
	description = "Short glowing ball + light with an attack/hold/decay envelope (impact frames, muzzle flashes).",
	icon = "✸",
	properties = {
		Common.prop("color", "color3", "#FFFFFF", "Flash and light colour.", { category = "Appearance" }),
		Common.prop("size", "number", 6, "Final diameter in studs (reached at the end of the decay).", {
			category = "Shape",
			min = 0,
			max = 500,
			scale = "length",
		}),
		Common.prop("startSize", "number", 1, "Diameter at the start of the flash in studs.", {
			category = "Shape",
			min = 0,
			max = 500,
			scale = "length",
		}),
		Common.prop("attack", "number", 0.03, "Seconds from invisible to peak brightness.", {
			category = "Envelope",
			min = 0,
			max = 5,
			step = 0.01,
		}),
		Common.prop("hold", "number", 0.02, "Seconds held at peak brightness.", {
			category = "Envelope",
			min = 0,
			max = 5,
			step = 0.01,
		}),
		Common.prop("decay", "number", 0.25, "Seconds from peak to fully faded.", {
			category = "Envelope",
			min = 0.01,
			max = 10,
			step = 0.01,
		}),
		Common.prop("material", "enum", "Neon", "Ball material.", {
			category = "Appearance",
			enum = MATERIALS,
			enumType = "Material",
		}),
		Common.prop("light", "boolean", true, "Adds a PointLight that follows the envelope.", { category = "Light" }),
		Common.prop("peakBrightness", "number", 10, "PointLight brightness at the peak.", {
			category = "Light",
			min = 0,
			max = 100,
		}),
		Common.prop("range", "number", 16, "PointLight range in studs (engine maximum 120).", {
			category = "Light",
			min = 0,
			max = MAX_LIGHT_RANGE,
			scale = "length",
		}),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("color", "color3", "Flash Part.Color and light colour.", { baseProperty = "color" }),
	},
	events = {},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local ball = Common.newPart(ctx, component.id, component.name) :: Part
		ball.Shape = Enum.PartType.Ball
		ball.Material = props.material

		local instances: { Instance } = { ball }
		local attachment: Attachment? = nil
		local light: PointLight? = nil
		local scale = math.max(component.scale, 0)
		if props.light == true and not ctx.viewport then
			local a = Common.newAttachment(ctx, component.id, component.name .. "_Light")
			local l = Instance.new("PointLight")
			l.Name = "Light"
			l.Enabled = false
			l.Shadows = false
			l.Brightness = 0
			l.Range = math.clamp(props.range * scale, 0, MAX_LIGHT_RANGE)
			ctx.tagInstance(l, component.id)
			l.Parent = a
			attachment = a
			light = l
			table.insert(instances, a)
			table.insert(instances, l)
		end

		local controller = Common.controller(component, instances)

		local attack: number = props.attack
		local hold: number = props.hold
		local decay: number = props.decay
		local total = attack + hold + decay
		local startDiameter: number = props.startSize * scale
		local endDiameter: number = props.size * scale
		local peak: number = props.peakBrightness

		local alive = true
		local active = false
		local released = false
		local localTime = 0
		local color: Color3 = props.color

		local writtenSize: Vector3? = nil
		local writtenTransparency: number? = nil
		local writtenColor: Color3? = nil
		local writtenEnabled: boolean? = nil
		local writtenBrightness: number? = nil
		local writtenLightColor: Color3? = nil
		local movedTo: CFrame? = nil
		local attachedTo: CFrame? = nil

		local function refresh()
			if not alive then
				return
			end
			local e = envelope(localTime, attack, hold, decay)
			local d = startDiameter + (endDiameter - startDiameter) * growth(localTime, total)
			local x = math.clamp(d, MIN_SIZE, MAX_SIZE)
			local size = Vector3.new(x, x, x)
			if size ~= writtenSize then
				writtenSize = size
				ball.Size = size
			end
			local visible = active and not released
			local t = if visible then 1 - e else 1
			if t ~= writtenTransparency then
				writtenTransparency = t
				ball.Transparency = t
			end
			if color ~= writtenColor then
				writtenColor = color
				ball.Color = color
			end
			if light then
				local enabled = visible and e > 0
				if enabled ~= writtenEnabled then
					writtenEnabled = enabled
					light.Enabled = enabled
				end
				local b = e * peak
				if b ~= writtenBrightness then
					writtenBrightness = b
					light.Brightness = b
				end
				if color ~= writtenLightColor then
					writtenLightColor = color
					light.Color = color
				end
			end
		end

		local function restore()
			active = false
			released = false
			localTime = 0
			color = props.color
			movedTo = nil
			if alive and attachment and attachedTo ~= CFrame.identity then
				attachment.CFrame = CFrame.identity
			end
			attachedTo = CFrame.identity
			refresh()
		end
		restore()

		function controller.setActive(_self: ComponentInstance, isActive: boolean, _frame: FrameContext)
			active = isActive
			refresh()
		end

		function controller.apply(_self: ComponentInstance, channel: string, value: any)
			if channel == "color" and typeof(value) == "Color3" then
				color = value
				refresh()
			end
		end

		function controller.setTransform(
			_self: ComponentInstance,
			localCFrame: CFrame,
			worldCFrame: CFrame,
			frame: FrameContext
		)
			if not alive then
				return
			end
			if worldCFrame ~= movedTo then
				movedTo = worldCFrame
				table.insert(frame.moveParts, ball)
				table.insert(frame.moveCFrames, worldCFrame)
			end
			if attachment and localCFrame ~= attachedTo then
				attachedTo = localCFrame
				attachment.CFrame = localCFrame
			end
		end

		controller.update = function(_self: ComponentInstance, time: number, _frame: FrameContext)
			localTime = time
			refresh()
		end

		function controller.release(_self: ComponentInstance)
			released = true
			refresh()
		end

		function controller.reset(_self: ComponentInstance)
			restore()
		end

		function controller.destroy(self: ComponentInstance)
			alive = false
			for _, inst in self.instances do
				inst:Destroy()
			end
			table.clear(self.instances)
		end

		return controller
	end,
	estimateCost = function(component: CompiledComponent, _quality: Types.QualityProfile): CostEstimate
		local props = component.props
		local hasLight = props.light == true
		local cost = Common.cost()
		cost.parts = 1
		cost.attachments = if hasLight then 1 else 0
		cost.lights = if hasLight then 1 else 0
		cost.instances = 1 + (if hasLight then 2 else 0)
		cost.movingParts = if Common.isMoving(component) then 1 else 0
		-- Heuristic: Size + Transparency every frame of the envelope, + light Brightness, + colour track writes.
		local updates = 2 + (if hasLight then 1 else 0)
		if component.tracks.color then
			updates += 1 + (if hasLight then 1 else 0)
		end
		cost.propertyUpdates = updates
		local d = math.max(props.size, props.startSize) * component.scale
		cost.transparentLayers = 1
		cost.overdrawWeight = d * d
		local total = props.attack + props.hold + props.decay
		if component.endTime - component.startTime < total then
			cost.notes = { "Component span is shorter than attack + hold + decay; the flash is cut off." }
		end
		return cost
	end,
}

return descriptor
