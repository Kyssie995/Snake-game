--!strict
--[[
	part — one physics-free Part (Block, Ball, Cylinder, Wedge, CornerWedge). docs/COMPONENTS_SPEC.md §5.

	Behaviour:
	* Part.Size = (`size` channel, else the `size` property) × scale (`scale` channel, else transform.scale),
	  clamped per axis to the engine range 0.001..2048. Roblox cylinders extend along the part's X axis and Ball
	  parts are spheres (engine facts, docs/research/api-geometry-lighting-tween.md P1).
	* `transparency` / `color` channels write Part.Transparency / Part.Color directly (part-like semantics).
	* The part is invisible (Transparency = 1) until setActive(true) and again after setActive(false) or release().
	* Movement goes through frame.moveParts/moveCFrames, queued only when the world CFrame changes. Every property
	  write is skipped when the value equals the last written one.
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type FrameContext = Types.FrameContext
type CostEstimate = Types.CostEstimate

local MIN_SIZE = 0.001 -- engine minimum per axis (BasePart.Size)
local MAX_SIZE = 2048 -- engine maximum per axis

local SHAPES = { "Block", "Ball", "Cylinder", "Wedge", "CornerWedge" }

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

local function clampSize(v: Vector3): Vector3
	return Vector3.new(
		math.clamp(v.X, MIN_SIZE, MAX_SIZE),
		math.clamp(v.Y, MIN_SIZE, MAX_SIZE),
		math.clamp(v.Z, MIN_SIZE, MAX_SIZE)
	)
end

-- Number of tracked channels that cause property writes (position/rotation tracks are CFrame moves).
local function propertyTracks(component: CompiledComponent): number
	local n = 0
	for channel in component.tracks do
		if channel ~= "position" and channel ~= "rotation" then
			n += 1
		end
	end
	return n
end

-- Materials that render see-through even at Transparency 0 (sorted with the transparent pass).
local function isSeeThrough(material: any): boolean
	return material == Enum.Material.ForceField or material == Enum.Material.Glass
end

local descriptor: Types.ComponentDescriptor = {
	type = "part",
	displayName = "Part",
	category = "Geometry",
	description = "A single anchored, non-colliding Part (block, ball, cylinder, wedge or corner wedge).",
	icon = "■",
	properties = {
		Common.prop("shape", "enum", "Block", "Part shape (Enum.PartType). Cylinders extend along the local X axis.", {
			category = "Shape",
			enum = SHAPES,
			enumType = "PartType",
		}),
		Common.prop("size", "vector3", { 1, 1, 1 }, "Part size in studs (multiplied by the component scale).", {
			category = "Shape",
			min = MIN_SIZE,
			max = MAX_SIZE,
			scale = "length",
		}),
		Common.prop("color", "color3", "#FFFFFF", "Part colour.", { category = "Appearance" }),
		Common.prop("material", "enum", "Neon", "Part material. Neon glows; ForceField/Glass look refractive.", {
			category = "Appearance",
			enum = MATERIALS,
			enumType = "Material",
		}),
		Common.prop("transparency", "number", 0, "Part transparency (0 = opaque, 1 = invisible).", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("reflectance", "number", 0, "Part reflectance.", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
			advanced = true,
		}),
		Common.prop("castShadow", "boolean", false, "Whether the part casts a shadow (off is cheaper).", {
			category = "Appearance",
			advanced = true,
		}),
		Common.spinProperty(),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		Common.channel("scale", "number", "Uniform size multiplier of this component.", { min = 0 }),
		Common.channel("size", "vector3", "Absolute part size in studs (Part.Size before the scale multiplier).", {
			min = MIN_SIZE,
			max = MAX_SIZE,
			scale = "length",
			baseProperty = "size",
		}),
		Common.channel("transparency", "number", "Part.Transparency (overrides the property while tracked).", {
			min = 0,
			max = 1,
			baseProperty = "transparency",
		}),
		Common.channel("color", "color3", "Part.Color.", { baseProperty = "color" }),
	},
	events = {},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local part = Common.newPart(ctx, component.id, component.name) :: Part
		part.Shape = props.shape
		part.Material = props.material
		part.Reflectance = props.reflectance
		part.CastShadow = props.castShadow == true

		local instances: { Instance } = { part }
		local controller = Common.controller(component, instances)

		local alive = true
		local active = false
		local released = false
		local size: Vector3 = props.size
		local scale: number = component.scale
		local transparency: number = props.transparency
		local color: Color3 = props.color

		-- Last written values (property writes are skipped when unchanged).
		local writtenSize: Vector3? = nil
		local writtenTransparency: number? = nil
		local writtenColor: Color3? = nil
		local movedTo: CFrame? = nil

		local function refresh()
			if not alive then
				return
			end
			local s = clampSize(size * math.max(scale, 0))
			if s ~= writtenSize then
				writtenSize = s
				part.Size = s
			end
			local t = if active and not released then math.clamp(transparency, 0, 1) else 1
			if t ~= writtenTransparency then
				writtenTransparency = t
				part.Transparency = t
			end
			if color ~= writtenColor then
				writtenColor = color
				part.Color = color
			end
		end

		-- Authored (freshly built) state: inactive, property values, no pending move.
		local function restore()
			active = false
			released = false
			size = props.size
			scale = component.scale
			transparency = props.transparency
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
			if channel == "size" then
				if typeof(value) ~= "Vector3" then
					return
				end
				size = value
			elseif channel == "scale" then
				if type(value) ~= "number" then
					return
				end
				scale = value
			elseif channel == "transparency" then
				if type(value) ~= "number" then
					return
				end
				transparency = value
			elseif channel == "color" then
				if typeof(value) ~= "Color3" then
					return
				end
				color = value
			else
				return
			end
			refresh()
		end

		function controller.setTransform(
			_self: ComponentInstance,
			_localCFrame: CFrame,
			worldCFrame: CFrame,
			frame: FrameContext
		)
			if alive and worldCFrame ~= movedTo then
				movedTo = worldCFrame
				table.insert(frame.moveParts, part)
				table.insert(frame.moveCFrames, worldCFrame)
			end
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
		local tracks = component.tracks
		local cost = Common.cost()
		cost.instances = 1
		cost.parts = 1
		cost.movingParts = if Common.isMoving(component) then 1 else 0
		cost.propertyUpdates = propertyTracks(component)
		local translucent = tracks.transparency ~= nil
			or (props.transparency > 0 and props.transparency < 1)
			or isSeeThrough(props.material)
		if translucent then
			local s: Vector3 = props.size * component.scale
			local extent = math.max(s.X, s.Y, s.Z)
			cost.transparentLayers = 1
			cost.overdrawWeight = extent * extent
		end
		local notes = {}
		if tracks.size or tracks.scale then
			table.insert(notes, "Part.Size is written every frame while size/scale animate (costlier than a move).")
		end
		if #notes > 0 then
			cost.notes = notes
		end
		return cost
	end,
}

return descriptor
