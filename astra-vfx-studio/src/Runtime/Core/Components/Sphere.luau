--!strict
--[[
	sphere — procedural energy sphere: a core Ball part inside a shell Ball part, plus an optional PointLight on an
	Attachment. docs/COMPONENTS_SPEC.md §9.

	Pure function of (localTime, props, channel values) — no randomness, so the seed is not used:
	  r(t)          = radius × (1 + pulseAmplitude × sin(2π · pulseFrequency · t)) × scale
	  core diameter = 2 · r(t)            shell diameter = 2 · r(t) · shellScale      (clamped to 0.001..2048)
	  fade v (`transparency` channel) on both layers: t' = 1 − (1 − t)(1 − v)
	  light: Brightness = lightBrightness × (1 − v)  (the light fades with the sphere), Color = shell colour,
	         Range = lightRange × scale, clamped to the engine maximum of 120 studs.
	The light is not built in viewport mode (lights do not render in a ViewportFrame).
	Invisible (Transparency = 1, light disabled) until setActive(true). Writes are skipped when unchanged.
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
local TAU = 2 * math.pi

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

local function diameterSize(d: number): Vector3
	local x = math.clamp(d, MIN_SIZE, MAX_SIZE)
	return Vector3.new(x, x, x)
end

local function isSeeThrough(material: any): boolean
	return material == Enum.Material.ForceField or material == Enum.Material.Glass
end

local function translucent(transparency: number, material: any, faded: boolean): boolean
	return faded or (transparency > 0 and transparency < 1) or isSeeThrough(material)
end

local descriptor: Types.ComponentDescriptor = {
	type = "sphere",
	displayName = "Energy Sphere",
	category = "Procedural",
	description = "Pulsing energy sphere: glowing core inside a shell, with an optional point light.",
	icon = "●",
	properties = {
		Common.prop("radius", "number", 1, "Core radius in studs (the shell is radius × shellScale).", {
			category = "Shape",
			min = 0.01,
			max = 500,
			scale = "length",
		}),
		Common.prop("coreColor", "color3", "#FFFFFF", "Core colour.", { category = "Appearance" }),
		Common.prop("shellColor", "color3", "#8A5CFF", "Shell colour (also the light colour).", {
			category = "Appearance",
		}),
		Common.prop("coreMaterial", "enum", "Neon", "Core material.", {
			category = "Appearance",
			enum = MATERIALS,
			enumType = "Material",
		}),
		Common.prop("shellMaterial", "enum", "ForceField", "Shell material.", {
			category = "Appearance",
			enum = MATERIALS,
			enumType = "Material",
		}),
		Common.prop("shellScale", "number", 1.4, "Shell radius relative to the core radius.", {
			category = "Shape",
			min = 1,
			max = 10,
			step = 0.05,
		}),
		Common.prop("coreTransparency", "number", 0, "Core transparency.", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("shellTransparency", "number", 0.3, "Shell transparency.", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("pulseAmplitude", "number", 0.05, "Pulse strength: radius × (1 + amplitude × sin(2π·f·t)).", {
			category = "Pulse",
			min = 0,
			max = 1,
			step = 0.01,
		}),
		Common.prop("pulseFrequency", "number", 4, "Pulse frequency in Hz.", {
			category = "Pulse",
			min = 0,
			max = 60,
		}),
		Common.prop("light", "boolean", true, "Adds a PointLight at the sphere centre.", { category = "Light" }),
		Common.prop("lightBrightness", "number", 2, "PointLight brightness.", {
			category = "Light",
			min = 0,
			max = 100,
		}),
		Common.prop("lightRange", "number", 8, "PointLight range in studs (engine maximum 120).", {
			category = "Light",
			min = 0,
			max = MAX_LIGHT_RANGE,
			scale = "length",
		}),
		Common.spinProperty(),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		Common.channel("scale", "number", "Uniform size multiplier of this component.", { min = 0 }),
		Common.channel("radius", "number", "Core radius in studs (before pulse and scale).", {
			min = 0,
			max = 500,
			scale = "length",
			baseProperty = "radius",
		}),
		Common.channel(
			"transparency",
			"number",
			"Fade applied to core and shell: t' = 1 − (1 − t)(1 − value).",
			{
				min = 0,
				max = 1,
			}
		),
		Common.channel("coreColor", "color3", "Core Part.Color.", { baseProperty = "coreColor" }),
		Common.channel("shellColor", "color3", "Shell Part.Color and light colour.", { baseProperty = "shellColor" }),
		Common.channel("lightBrightness", "number", "PointLight brightness.", {
			min = 0,
			max = 100,
			baseProperty = "lightBrightness",
		}),
	},
	events = {},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local core = Common.newPart(ctx, component.id, component.name .. "_Core") :: Part
		core.Shape = Enum.PartType.Ball
		core.Material = props.coreMaterial
		local shell = Common.newPart(ctx, component.id, component.name .. "_Shell") :: Part
		shell.Shape = Enum.PartType.Ball
		shell.Material = props.shellMaterial

		local instances: { Instance } = { core, shell }
		local attachment: Attachment? = nil
		local light: PointLight? = nil
		if props.light == true and not ctx.viewport then
			local a = Common.newAttachment(ctx, component.id, component.name .. "_Light")
			local l = Instance.new("PointLight")
			l.Name = "Light"
			l.Enabled = false
			l.Shadows = false
			ctx.tagInstance(l, component.id)
			l.Parent = a
			attachment = a
			light = l
			table.insert(instances, a)
			table.insert(instances, l)
		end

		local controller = Common.controller(component, instances)

		local amplitude: number = props.pulseAmplitude
		local frequency: number = props.pulseFrequency
		local shellScale: number = props.shellScale
		local coreTransparency: number = props.coreTransparency
		local shellTransparency: number = props.shellTransparency
		local lightRange: number = props.lightRange

		local alive = true
		local active = false
		local released = false
		local localTime = 0
		local scale: number = component.scale
		local radius: number = props.radius
		local fade = 0
		local coreColor: Color3 = props.coreColor
		local shellColor: Color3 = props.shellColor
		local brightness: number = props.lightBrightness

		local writtenCoreSize: Vector3? = nil
		local writtenShellSize: Vector3? = nil
		local writtenCoreT: number? = nil
		local writtenShellT: number? = nil
		local writtenCoreColor: Color3? = nil
		local writtenShellColor: Color3? = nil
		local writtenEnabled: boolean? = nil
		local writtenBrightness: number? = nil
		local writtenRange: number? = nil
		local writtenLightColor: Color3? = nil
		local movedTo: CFrame? = nil
		local attachedTo: CFrame? = nil

		local function refresh()
			if not alive then
				return
			end
			local k = math.max(scale, 0)
			local pulse = 1 + amplitude * math.sin(TAU * frequency * localTime)
			local r = math.max(radius, 0) * pulse * k
			local coreSize = diameterSize(2 * r)
			if coreSize ~= writtenCoreSize then
				writtenCoreSize = coreSize
				core.Size = coreSize
			end
			local shellSize = diameterSize(2 * r * shellScale)
			if shellSize ~= writtenShellSize then
				writtenShellSize = shellSize
				shell.Size = shellSize
			end

			local visible = active and not released
			local v = math.clamp(fade, 0, 1)
			local coreT = if visible then 1 - (1 - coreTransparency) * (1 - v) else 1
			if coreT ~= writtenCoreT then
				writtenCoreT = coreT
				core.Transparency = coreT
			end
			local shellT = if visible then 1 - (1 - shellTransparency) * (1 - v) else 1
			if shellT ~= writtenShellT then
				writtenShellT = shellT
				shell.Transparency = shellT
			end
			if coreColor ~= writtenCoreColor then
				writtenCoreColor = coreColor
				core.Color = coreColor
			end
			if shellColor ~= writtenShellColor then
				writtenShellColor = shellColor
				shell.Color = shellColor
			end

			if light then
				if visible ~= writtenEnabled then
					writtenEnabled = visible
					light.Enabled = visible
				end
				local b = math.max(brightness, 0) * (1 - v)
				if b ~= writtenBrightness then
					writtenBrightness = b
					light.Brightness = b
				end
				local range = math.clamp(lightRange * k, 0, MAX_LIGHT_RANGE)
				if range ~= writtenRange then
					writtenRange = range
					light.Range = range
				end
				if shellColor ~= writtenLightColor then
					writtenLightColor = shellColor
					light.Color = shellColor
				end
			end
		end

		local function restore()
			active = false
			released = false
			localTime = 0
			scale = component.scale
			radius = props.radius
			fade = 0
			coreColor = props.coreColor
			shellColor = props.shellColor
			brightness = props.lightBrightness
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
			if channel == "scale" then
				if type(value) ~= "number" then
					return
				end
				scale = value
			elseif channel == "radius" then
				if type(value) ~= "number" then
					return
				end
				radius = value
			elseif channel == "transparency" then
				if type(value) ~= "number" then
					return
				end
				fade = value
			elseif channel == "coreColor" then
				if typeof(value) ~= "Color3" then
					return
				end
				coreColor = value
			elseif channel == "shellColor" then
				if typeof(value) ~= "Color3" then
					return
				end
				shellColor = value
			elseif channel == "lightBrightness" then
				if type(value) ~= "number" then
					return
				end
				brightness = value
			else
				return
			end
			refresh()
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
				table.insert(frame.moveParts, core)
				table.insert(frame.moveCFrames, worldCFrame)
				table.insert(frame.moveParts, shell)
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
		local tracks = component.tracks
		local hasLight = props.light == true
		local cost = Common.cost()
		cost.parts = 2
		cost.attachments = if hasLight then 1 else 0
		cost.lights = if hasLight then 1 else 0
		cost.instances = 2 + (if hasLight then 2 else 0)
		cost.movingParts = if Common.isMoving(component) then 2 else 0

		-- Heuristic property writes per active frame.
		local updates = 0
		local pulsing = props.pulseAmplitude > 0 and props.pulseFrequency > 0
		if pulsing or tracks.radius or tracks.scale then
			updates += 2 -- core + shell Size
		end
		if tracks.transparency then
			updates += 2 + (if hasLight then 1 else 0)
		end
		if tracks.coreColor then
			updates += 1
		end
		if tracks.shellColor then
			updates += 1 + (if hasLight then 1 else 0)
		end
		if hasLight and tracks.lightBrightness then
			updates += 1
		end
		if hasLight and tracks.scale then
			updates += 1 -- light Range
		end
		cost.propertyUpdates = updates

		local faded = tracks.transparency ~= nil
		local d = 2 * props.radius * component.scale * (1 + props.pulseAmplitude)
		local layers = 0
		local overdraw = 0
		if translucent(props.coreTransparency, props.coreMaterial, faded) then
			layers += 1
			overdraw += d * d
		end
		if translucent(props.shellTransparency, props.shellMaterial, faded) then
			local ds = d * props.shellScale
			layers += 1
			overdraw += ds * ds
		end
		cost.transparentLayers = layers
		cost.overdrawWeight = overdraw
		if pulsing then
			cost.notes = { "Pulse writes core and shell Part.Size every frame (costlier than a move)." }
		end
		return cost
	end,
}

return descriptor
