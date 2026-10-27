--!strict
--[[
	shockwave — procedural expanding disc: `layers` flattened Cylinder parts. docs/COMPONENTS_SPEC.md §11.

	Roblox cylinders extend along the part's X axis (engine fact P1), so every layer is placed at
	worldCFrame × CFrame.Angles(0, 0, π/2), which turns the cylinder axis onto the component's local Y axis; the
	disc lies in the local XZ plane. Size = (height, 2r, 2r).

	Pure function of (localTime, props, colour channel) — no randomness, so the seed is not used. With
	n = layers, Δ = layerDelay and the component span S = endTime − startTime, every layer runs the same animation
	over L = max(S − (n − 1)·Δ, 1/60) seconds, layer i (0-based) starting i·Δ later, so the last layer finishes
	exactly at the end of the span:
	  u_i(t)       = clamp((t − i·Δ) / L, 0, 1)
	  radius_i     = lerp(startRadius, endRadius, expandEasing(u_i)) × scale
	  height_i     = height × layerThinning^i × scale
	  Transparency = lerp(startTransparency, 1, fadeEasing(u_i)); layers whose start time has not come are hidden.
	`expandEasing` / `fadeEasing` are Core/Easing definitions ("Quart.Out", "Linear", ...); an invalid string
	falls back to Linear (Validation reports it). `scale` is the rest value transform.scale (no scale channel).
	Invisible until setActive(true); writes are skipped when unchanged.
]]

local Common = require(script.Parent.Common)
local Easing = require(script.Parent.Parent.Easing)
local Types = require(script.Parent.Parent.Types)

type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type FrameContext = Types.FrameContext
type CostEstimate = Types.CostEstimate
type EasingFn = Types.EasingFn

local MIN_SIZE = 0.001
local MAX_SIZE = 2048
local MIN_LAYER_SPAN = 1 / 60
-- Rotates the cylinder axis (part X) onto the component's local Y axis.
local AXIS = CFrame.Angles(0, 0, math.pi / 2)

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

local function linear(alpha: number): number
	return math.clamp(alpha, 0, 1)
end

-- Easing.parse for a string property; invalid definitions fall back to Linear.
local function parseEasing(def: any): EasingFn
	local ok, fn = pcall(Easing.parse :: any, def)
	if ok and type(fn) == "function" then
		return fn
	end
	return linear
end

local function layerCount(component: CompiledComponent): number
	return math.max(1, math.floor(component.props.layers))
end

local descriptor: Types.ComponentDescriptor = {
	type = "shockwave",
	displayName = "Shockwave",
	category = "Procedural",
	description = "Expanding, fading disc made of flattened cylinders (ground slams, impact rings, ripples).",
	icon = "◎",
	properties = {
		Common.prop("startRadius", "number", 0.5, "Radius at the start in studs.", {
			category = "Shape",
			min = 0,
			max = 2000,
			scale = "length",
		}),
		Common.prop("endRadius", "number", 12, "Radius at the end in studs.", {
			category = "Shape",
			min = 0,
			max = 2000,
			scale = "length",
		}),
		Common.prop("height", "number", 0.3, "Disc thickness in studs (along the local Y axis).", {
			category = "Shape",
			min = 0.01,
			max = 100,
			scale = "length",
		}),
		Common.prop("color", "color3", "#FFFFFF", "Disc colour.", { category = "Appearance" }),
		Common.prop("material", "enum", "ForceField", "Disc material. ForceField/Glass give a refractive look.", {
			category = "Appearance",
			enum = MATERIALS,
			enumType = "Material",
		}),
		Common.prop("startTransparency", "number", 0, "Transparency at the start (fades to 1).", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("expandEasing", "string", "Quart.Out", "Easing of the radius (e.g. Quart.Out, Linear).", {
			category = "Animation",
		}),
		Common.prop("fadeEasing", "string", "Quad.In", "Easing of the fade to transparency 1 (e.g. Quad.In).", {
			category = "Animation",
		}),
		Common.prop("layers", "integer", 1, "Number of discs (each later and thinner than the previous one).", {
			category = "Layers",
			min = 1,
			max = 4,
			quality = "segments",
		}),
		Common.prop("layerDelay", "number", 0.05, "Seconds between the start of consecutive layers.", {
			category = "Layers",
			min = 0,
			max = 2,
			step = 0.01,
		}),
		Common.prop("layerThinning", "number", 0.6, "Height factor per layer (layer i: height × thinning^i).", {
			category = "Layers",
			min = 0.05,
			max = 1,
			step = 0.05,
		}),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		Common.channel("color", "color3", "Part.Color of every layer.", { baseProperty = "color" }),
	},
	events = {},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local count = layerCount(component)
		local parts: { BasePart } = {}
		local instances: { Instance } = {}
		for i = 1, count do
			local part = Common.newPart(ctx, component.id, component.name .. "_Layer" .. i) :: Part
			part.Shape = Enum.PartType.Cylinder
			part.Material = props.material
			parts[i] = part
			instances[i] = part
		end
		local controller = Common.controller(component, instances)

		local scale = math.max(component.scale, 0)
		local startRadius: number = props.startRadius
		local endRadius: number = props.endRadius
		local startTransparency: number = props.startTransparency
		local delay: number = props.layerDelay
		local expand = parseEasing(props.expandEasing)
		local fadeOut = parseEasing(props.fadeEasing)
		local span = math.max(component.endTime - component.startTime - (count - 1) * delay, MIN_LAYER_SPAN)
		local heights: { number } = {}
		for i = 1, count do
			heights[i] = math.clamp(props.height * props.layerThinning ^ (i - 1) * scale, MIN_SIZE, MAX_SIZE)
		end

		local alive = true
		local active = false
		local released = false
		local localTime = 0
		local color: Color3 = props.color

		local writtenSize: { Vector3 } = {}
		local writtenTransparency: { number } = {}
		local writtenColor: Color3? = nil
		local movedTo: CFrame? = nil

		local function refresh()
			if not alive then
				return
			end
			local visible = active and not released
			for i, part in parts do
				local start = (i - 1) * delay
				local u = math.clamp((localTime - start) / span, 0, 1)
				local r = (startRadius + (endRadius - startRadius) * expand(u)) * scale
				local d = math.clamp(2 * r, MIN_SIZE, MAX_SIZE)
				local size = Vector3.new(heights[i], d, d)
				if size ~= writtenSize[i] then
					writtenSize[i] = size
					part.Size = size
				end
				local t = 1
				if visible and localTime >= start then
					t = math.clamp(startTransparency + (1 - startTransparency) * fadeOut(u), 0, 1)
				end
				if t ~= writtenTransparency[i] then
					writtenTransparency[i] = t
					part.Transparency = t
				end
			end
			if color ~= writtenColor then
				writtenColor = color
				for _, part in parts do
					part.Color = color
				end
			end
		end

		local function restore()
			active = false
			released = false
			localTime = 0
			color = props.color
			movedTo = nil
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
			_localCFrame: CFrame,
			worldCFrame: CFrame,
			frame: FrameContext
		)
			if alive and worldCFrame ~= movedTo then
				movedTo = worldCFrame
				local cf = worldCFrame * AXIS
				for _, part in parts do
					table.insert(frame.moveParts, part)
					table.insert(frame.moveCFrames, cf)
				end
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
		local count = layerCount(component)
		local cost = Common.cost()
		cost.instances = count
		cost.parts = count
		cost.movingParts = if Common.isMoving(component) then count else 0
		-- Heuristic: every layer writes Size and Transparency each frame, + Color while the colour is tracked.
		cost.propertyUpdates = count * (if component.tracks.color then 3 else 2)
		cost.transparentLayers = count
		local d = 2 * math.max(props.startRadius, props.endRadius) * component.scale
		cost.overdrawWeight = count * d * d
		cost.notes = { "Shockwave layers resize every frame (Part.Size writes are costlier than moves)." }
		return cost
	end,
}

return descriptor
