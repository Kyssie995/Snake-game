--!strict
--[[
	mesh — a physics-free host Part + SpecialMesh. docs/COMPONENTS_SPEC.md §6.

	MeshPart.MeshId is NotAccessibleSecurity (not writable by scripts or plugins), so ASTRA renders meshes through a
	SpecialMesh, whose MeshId/TextureId are writable and whose Scale/Offset are cheap to animate (no collision
	update). Engine facts: docs/research/api-geometry-lighting-tween.md M1, M7-M12.

	Behaviour:
	* Part.Size = `partSize` (constant; clamped to 0.001..2048). The component scale (`scale` channel /
	  transform.scale) is applied through SpecialMesh.Scale = meshScale × scale, never through Part.Size.
	* For Brick/Sphere/Wedge/Cylinder, SpecialMesh.Scale multiplies the part size, so the effect scale (already
	  applied to `partSize` by the Compiler) reaches the rendered size. For FileMesh, Scale is relative to the
	  uploaded mesh and Part.Size does not affect rendering, so SpecialMesh.Scale additionally includes the effect
	  scale (ctx.effect.scale) — otherwise a scaled effect would leave FileMeshes at their authored size.
	* SpecialMesh.Offset = offset × scale (the offset scales with the mesh it belongs to).
	* `vertexColor` is a Color3 in ASTRA and is written as Vector3(r, g, b) (DataModelMesh.VertexColor; it only tints
	  a FileMesh texture).
	* `FileMesh` without `meshId` builds an empty FileMesh (renders nothing; Validation warns).
	* Invisible (Part.Transparency = 1) until setActive(true). Writes are skipped when values are unchanged.
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type FrameContext = Types.FrameContext
type CostEstimate = Types.CostEstimate

local MIN_SIZE = 0.001
local MAX_SIZE = 2048

-- Head/Torso are non-standard and the remaining MeshTypes are deprecated (research M8 / ASTRA §4.15).
local MESH_TYPES = { "Sphere", "Cylinder", "Brick", "Wedge", "FileMesh" }

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

local function nonNegative(v: Vector3): Vector3
	return Vector3.new(math.max(v.X, 0), math.max(v.Y, 0), math.max(v.Z, 0))
end

local function colorToVector(c: Color3): Vector3
	return Vector3.new(c.R, c.G, c.B)
end

local function propertyTracks(component: CompiledComponent): number
	local n = 0
	for channel in component.tracks do
		if channel ~= "position" and channel ~= "rotation" then
			n += 1
		end
	end
	return n
end

local descriptor: Types.ComponentDescriptor = {
	type = "mesh",
	displayName = "Mesh",
	category = "Geometry",
	description = "A SpecialMesh (sphere, cylinder, brick, wedge or uploaded FileMesh) on an invisible-collision Part.",
	icon = "◆",
	properties = {
		Common.prop("meshType", "enum", "Sphere", "SpecialMesh.MeshType. FileMesh needs a meshId.", {
			category = "Mesh",
			enum = MESH_TYPES,
			enumType = "MeshType",
		}),
		Common.prop("meshId", "asset", "", "Mesh asset for FileMesh (SpecialMesh.MeshId).", { category = "Mesh" }),
		Common.prop("textureId", "asset", "", "Texture asset (SpecialMesh.TextureId).", { category = "Mesh" }),
		Common.prop("partSize", "vector3", { 1, 1, 1 }, "Host Part size in studs (Brick/Sphere/Wedge scale it).", {
			category = "Mesh",
			scale = "length",
		}),
		Common.prop("meshScale", "vector3", { 1, 1, 1 }, "SpecialMesh.Scale (multiplied by the component scale).", {
			category = "Mesh",
			min = 0,
			max = 10000,
		}),
		Common.prop("offset", "vector3", { 0, 0, 0 }, "SpecialMesh.Offset in studs (render offset from the part).", {
			category = "Mesh",
			scale = "length",
		}),
		Common.prop("vertexColor", "color3", "#FFFFFF", "Tints the FileMesh texture (SpecialMesh.VertexColor).", {
			category = "Appearance",
		}),
		Common.prop("color", "color3", "#FFFFFF", "Part colour.", { category = "Appearance" }),
		Common.prop("material", "enum", "SmoothPlastic", "Part material (may not render on a SpecialMesh).", {
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
		Common.spinProperty(),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		Common.channel("scale", "number", "Uniform size multiplier of this component.", { min = 0 }),
		Common.channel("meshScale", "vector3", "SpecialMesh.Scale before the scale multiplier.", {
			min = 0,
			max = 10000,
			baseProperty = "meshScale",
		}),
		Common.channel("offset", "vector3", "SpecialMesh.Offset in studs.", {
			scale = "length",
			baseProperty = "offset",
		}),
		Common.channel("transparency", "number", "Part.Transparency (overrides the property while tracked).", {
			min = 0,
			max = 1,
			baseProperty = "transparency",
		}),
		Common.channel("color", "color3", "Part.Color.", { baseProperty = "color" }),
		Common.channel("vertexColor", "color3", "SpecialMesh.VertexColor (tints the FileMesh texture).", {
			baseProperty = "vertexColor",
		}),
	},
	events = {},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local part = Common.newPart(ctx, component.id, component.name)
		part.Size = clampSize(props.partSize)
		part.Material = props.material

		local mesh = Instance.new("SpecialMesh")
		mesh.Name = "Mesh"
		mesh.MeshType = props.meshType -- must be explicit: Instance.new("SpecialMesh") defaults to Head
		mesh.MeshId = props.meshId
		mesh.TextureId = props.textureId
		ctx.tagInstance(mesh, component.id)
		mesh.Parent = part

		local isFileMesh = props.meshType == Enum.MeshType.FileMesh
		local effectScale = if isFileMesh then ctx.effect.scale else 1

		local instances: { Instance } = { part, mesh }
		local controller = Common.controller(component, instances)

		local alive = true
		local active = false
		local released = false
		local scale: number = component.scale
		local meshScale: Vector3 = props.meshScale
		local offset: Vector3 = props.offset
		local transparency: number = props.transparency
		local color: Color3 = props.color
		local vertexColor: Color3 = props.vertexColor

		local writtenScale: Vector3? = nil
		local writtenOffset: Vector3? = nil
		local writtenTransparency: number? = nil
		local writtenColor: Color3? = nil
		local writtenVertexColor: Vector3? = nil
		local movedTo: CFrame? = nil

		local function refresh()
			if not alive then
				return
			end
			local k = math.max(scale, 0)
			local s = nonNegative(meshScale) * (k * effectScale)
			if s ~= writtenScale then
				writtenScale = s
				mesh.Scale = s
			end
			local o = offset * k
			if o ~= writtenOffset then
				writtenOffset = o
				mesh.Offset = o
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
			local vc = colorToVector(vertexColor)
			if vc ~= writtenVertexColor then
				writtenVertexColor = vc
				mesh.VertexColor = vc
			end
		end

		local function restore()
			active = false
			released = false
			scale = component.scale
			meshScale = props.meshScale
			offset = props.offset
			transparency = props.transparency
			color = props.color
			vertexColor = props.vertexColor
			movedTo = nil
			refresh()
		end
		restore()

		function controller.setActive(_self: ComponentInstance, isActive: boolean, _frame: FrameContext)
			active = isActive
			refresh()
		end

		function controller.apply(_self: ComponentInstance, channel: string, value: any)
			if channel == "scale" then
				if type(value) ~= "number" then
					return
				end
				scale = value
			elseif channel == "meshScale" then
				if typeof(value) ~= "Vector3" then
					return
				end
				meshScale = value
			elseif channel == "offset" then
				if typeof(value) ~= "Vector3" then
					return
				end
				offset = value
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
			elseif channel == "vertexColor" then
				if typeof(value) ~= "Color3" then
					return
				end
				vertexColor = value
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
		cost.instances = 2 -- Part + SpecialMesh
		cost.parts = 1
		cost.movingParts = if Common.isMoving(component) then 1 else 0
		cost.propertyUpdates = propertyTracks(component)
		local material = props.material
		local seeThrough = material == Enum.Material.ForceField or material == Enum.Material.Glass
		if tracks.transparency ~= nil or (props.transparency > 0 and props.transparency < 1) or seeThrough then
			-- Rendered size: partSize × meshScale for primitive mesh types; FileMesh size is unknown here.
			local s: Vector3 = props.meshScale * component.scale
			if props.meshType ~= Enum.MeshType.FileMesh then
				s = s * props.partSize
			end
			local extent = math.max(s.X, s.Y, s.Z)
			cost.transparentLayers = 1
			cost.overdrawWeight = extent * extent
		end
		local notes = {}
		if props.meshType == Enum.MeshType.FileMesh and props.meshId == "" then
			table.insert(notes, "FileMesh without meshId renders nothing.")
		end
		if material == Enum.Material.Neon or seeThrough then
			table.insert(notes, "BasePart.Material may not render correctly on a SpecialMesh (engine doc).")
		end
		if #notes > 0 then
			cost.notes = notes
		end
		return cost
	end,
}

return descriptor
