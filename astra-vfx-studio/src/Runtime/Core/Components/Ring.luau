--!strict
--[[
	ring — procedural rings, polygons, stars and spokes (magic circles) built from thin Block parts in the
	component's local XZ plane. docs/COMPONENTS_SPEC.md §12.

	Geometry (component space; s = scale, r = radius·s, w = thickness·s, h = height·s). Vertices lie on the circle
	of radius r: v_i = r·(cos θ_i, 0, sin θ_i), θ_i = −π/2 + 2π(i − 1)/N, so vertex 1 points forward (−Z).
	  ring     N = segments, chords v_i → v_{i+1}
	  polygon  N = points,   edges  v_i → v_{i+1}
	  star     N = points,   edges  v_i → v_{i+k} with k = starStep reduced to 1..⌊N/2⌋ (k ≡ 0 mod N → 1, k > N/2 →
	           N − k: {N/k} and {N/(N−k)} are the same figure); N edges, N/2 diameters when 2k = N
	  spokes   N = points radial bars from innerRadius·s to r along θ_i
	A chord spanning the half-angle φ (π/N for ring/polygon, πk/N for star) is a Block with Size = (L, h, w) —
	X along the edge, Y = local up, Z = radial — centred on the apothem r·cos φ:
	  L = 2r·sin φ + w·min(tan φ, 2) + 0.05·w
	The w·tan φ term extends both ends by (w/2)·tan φ, which exactly closes the outer corner where neighbouring
	chords meet (mitre; capped at 2 for sharp star tips, 0 for star diameters); the 0.05·w term is the slight overlap
	that keeps seams from showing. Spokes: Size = (|r − inner|, h, w) centred at (inner + r)/2 on their ray.
	Sizes are clamped to the engine range 0.001..2048.

	The ring is static: no randomness (the seed is unused) and no time dependence. Geometry is recomputed only when
	radius / thickness / scale change (dirty flag); each part then gets one Size write, and its new CFrame
	(worldCFrame × local edge CFrame) is queued on frame.moveParts by the next setTransform/update. Moves are skipped
	for parts whose CFrame did not change. Channels: transform (scale = uniform multiplier of radius, innerRadius,
	thickness and height), radius, thickness, transparency (Part.Transparency, overrides the property),
	color (Part.Color). Invisible until setActive(true); release() hides the parts until reset().
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type FrameContext = Types.FrameContext
type CostEstimate = Types.CostEstimate

local MIN_SIZE = 0.001
local MAX_SIZE = 2048
local TAU = 2 * math.pi
local START_ANGLE = -math.pi / 2
local MAX_MITRE = 2
local OVERLAP = 0.05
local UP = Vector3.new(0, 1, 0)

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

local function clampSize(x: number): number
	return math.clamp(x, MIN_SIZE, MAX_SIZE)
end

local function isSeeThrough(material: any): boolean
	return material == Enum.Material.ForceField or material == Enum.Material.Glass
end

type Layout = {
	spokes: boolean,
	n: number, -- vertex count N
	k: number, -- star step (1 for ring/polygon/spokes)
	edges: number, -- number of parts
}

-- Resolves the style into vertex count, step and part count (all fixed at build time).
local function layoutOf(props: { [string]: any }): Layout
	local style = props.style
	if style == "polygon" then
		local n = math.max(3, math.floor(props.points))
		return { spokes = false, n = n, k = 1, edges = n }
	elseif style == "star" then
		local n = math.max(3, math.floor(props.points))
		local k = math.floor(props.starStep) % n
		if k == 0 then
			k = 1
		end
		if 2 * k > n then
			k = n - k
		end
		return { spokes = false, n = n, k = k, edges = if 2 * k == n then math.floor(n / 2) else n }
	elseif style == "spokes" then
		local n = math.max(1, math.floor(props.points))
		return { spokes = true, n = n, k = 1, edges = n }
	end
	local n = math.max(3, math.floor(props.segments))
	return { spokes = false, n = n, k = 1, edges = n }
end

-- Local (component-space) CFrames and sizes of every edge. Lengths are already scaled.
local function computeGeometry(
	layout: Layout,
	radius: number,
	innerRadius: number,
	thickness: number,
	height: number,
	cframes: { CFrame },
	sizes: { Vector3 }
)
	local r = math.max(radius, 0)
	local w = math.max(thickness, 0)
	local sizeW = clampSize(w)
	local sizeH = clampSize(height)
	local n = layout.n
	if layout.spokes then
		local inner = math.max(innerRadius, 0)
		local mid = (inner + r) / 2
		local length = clampSize(math.abs(r - inner))
		for i = 1, layout.edges do
			local theta = START_ANGLE + TAU * (i - 1) / n
			local radial = Vector3.new(math.cos(theta), 0, math.sin(theta))
			cframes[i] = CFrame.fromMatrix(radial * mid, radial, UP)
			sizes[i] = Vector3.new(length, sizeH, sizeW)
		end
		return
	end
	local k = layout.k
	local phi = math.pi * k / n
	local mitre = if 2 * k == n then 0 else math.min(math.tan(phi), MAX_MITRE)
	local length = clampSize(2 * r * math.sin(phi) + w * mitre + OVERLAP * w)
	local apothem = r * math.cos(phi)
	for i = 1, layout.edges do
		-- Mid-angle of the chord v_i → v_{i+k}.
		local theta = START_ANGLE + TAU * (i - 1) / n + phi
		local c, s = math.cos(theta), math.sin(theta)
		cframes[i] = CFrame.fromMatrix(Vector3.new(c, 0, s) * apothem, Vector3.new(-s, 0, c), UP)
		sizes[i] = Vector3.new(length, sizeH, sizeW)
	end
end

type Mover = {
	move: (frame: FrameContext, index: number, cframe: CFrame) -> (),
	forget: () -> (),
}

-- Batches part moves into frame.moveParts/moveCFrames (one BulkMoveTo per frame). Parts whose target CFrame is
-- unchanged are skipped; a part queued twice in the same frame (setTransform, then update) has its slot
-- overwritten instead of being appended again.
local function newMover(parts: { BasePart }): Mover
	local placed: { [number]: CFrame } = {}
	local slots: { [number]: number } = {}
	local slotFrame: FrameContext? = nil
	local function move(frame: FrameContext, index: number, cframe: CFrame)
		if placed[index] == cframe then
			return
		end
		placed[index] = cframe
		if slotFrame ~= frame then
			slotFrame = frame
			table.clear(slots)
		end
		local part = parts[index]
		local slot = slots[index]
		if slot and frame.moveParts[slot] == part then
			frame.moveCFrames[slot] = cframe
		else
			table.insert(frame.moveParts, part)
			table.insert(frame.moveCFrames, cframe)
			slots[index] = #frame.moveParts
		end
	end
	local function forget()
		table.clear(placed)
		table.clear(slots)
		slotFrame = nil
	end
	return { move = move, forget = forget }
end

local descriptor: Types.ComponentDescriptor = {
	type = "ring",
	displayName = "Ring",
	category = "Procedural",
	description = "Rings, polygons, stars and spokes from thin parts in the local XZ plane (magic circles).",
	icon = "◯",
	properties = {
		Common.prop("style", "enum", "ring", "Figure: ring (circle of chords), polygon, star or spokes.", {
			category = "Shape",
			enum = { "ring", "polygon", "star", "spokes" },
		}),
		Common.prop("segments", "integer", 24, "Chords around the circle (ring style).", {
			category = "Shape",
			min = 3,
			max = 128,
			quality = "segments",
		}),
		Common.prop("points", "integer", 5, "Corners of the polygon/star, or number of spokes.", {
			category = "Shape",
			min = 3,
			max = 32,
		}),
		Common.prop("starStep", "integer", 2, "Star: each edge connects corner i to corner i + starStep.", {
			category = "Shape",
			min = 1,
			max = 15,
		}),
		Common.prop("radius", "number", 4, "Outer radius in studs (corners lie on this circle).", {
			category = "Shape",
			min = 0,
			max = 2000,
			scale = "length",
		}),
		Common.prop("innerRadius", "number", 0, "Spokes: radius where the spokes start, in studs.", {
			category = "Shape",
			min = 0,
			max = 2000,
			scale = "length",
		}),
		Common.prop("thickness", "number", 0.2, "Radial width of the lines in studs.", {
			category = "Shape",
			min = 0.001,
			max = 100,
			scale = "length",
		}),
		Common.prop("height", "number", 0.1, "Height of the lines along the local Y axis in studs.", {
			category = "Shape",
			min = 0.001,
			max = 100,
			scale = "length",
		}),
		Common.prop("color", "color3", "#FFFFFF", "Line colour.", { category = "Appearance" }),
		Common.prop("material", "enum", "Neon", "Line material.", {
			category = "Appearance",
			enum = MATERIALS,
			enumType = "Material",
		}),
		Common.prop("transparency", "number", 0, "Line transparency.", {
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
		Common.channel("radius", "number", "Outer radius in studs.", {
			min = 0,
			max = 2000,
			scale = "length",
			baseProperty = "radius",
		}),
		Common.channel("thickness", "number", "Radial width of the lines in studs.", {
			min = 0.001,
			max = 100,
			scale = "length",
			baseProperty = "thickness",
		}),
		Common.channel("transparency", "number", "Part.Transparency of every line.", {
			min = 0,
			max = 1,
			baseProperty = "transparency",
		}),
		Common.channel("color", "color3", "Part.Color of every line.", { baseProperty = "color" }),
	},
	events = {},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local layout = layoutOf(props)
		local parts: { BasePart } = {}
		local instances: { Instance } = {}
		for i = 1, layout.edges do
			local part = Common.newPart(ctx, component.id, component.name .. "_Edge" .. i) :: Part
			part.Shape = Enum.PartType.Block
			part.Material = props.material
			parts[i] = part
			instances[i] = part
		end
		local controller = Common.controller(component, instances)
		local mover = newMover(parts)

		local innerRadius: number = props.innerRadius
		local height: number = props.height

		local alive = true
		local active = false
		local released = false
		local scale: number = component.scale
		local radius: number = props.radius
		local thickness: number = props.thickness
		local transparency: number = props.transparency
		local color: Color3 = props.color

		local localCFrames: { CFrame } = {}
		local sizes: { Vector3 } = {}
		local geometryDirty = true
		local geometryStamp = 0 -- bumps whenever the local geometry is recomputed
		local world: CFrame? = nil
		local placedWorld: CFrame? = nil
		local placedStamp = -1

		local writtenSize: { Vector3 } = {}
		local writtenTransparency: number? = nil
		local writtenColor: Color3? = nil

		local function refreshGeometry()
			if not geometryDirty then
				return
			end
			geometryDirty = false
			geometryStamp += 1
			local k = math.max(scale, 0)
			computeGeometry(layout, radius * k, innerRadius * k, thickness * k, height * k, localCFrames, sizes)
			for i, part in parts do
				local size = sizes[i]
				if size ~= writtenSize[i] then
					writtenSize[i] = size
					part.Size = size
				end
			end
		end

		local function refreshAppearance()
			local t = if active and not released then math.clamp(transparency, 0, 1) else 1
			if t ~= writtenTransparency then
				writtenTransparency = t
				for _, part in parts do
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

		-- Queues every part whose world CFrame changed (new transform or new geometry).
		local function place(frame: FrameContext)
			local w = world
			if w == nil or (w == placedWorld and geometryStamp == placedStamp) then
				return
			end
			placedWorld = w
			placedStamp = geometryStamp
			for i in parts do
				mover.move(frame, i, w * localCFrames[i])
			end
		end

		local function restore()
			active = false
			released = false
			scale = component.scale
			radius = props.radius
			thickness = props.thickness
			transparency = props.transparency
			color = props.color
			world = nil
			placedWorld = nil
			mover.forget()
			geometryDirty = true
			refreshGeometry()
			refreshAppearance()
		end
		restore()

		function controller.setActive(_self: ComponentInstance, isActive: boolean, _frame: FrameContext)
			if not alive then
				return
			end
			active = isActive
			refreshAppearance()
		end

		function controller.apply(_self: ComponentInstance, channel: string, value: any)
			if not alive then
				return
			end
			local isNumber = type(value) == "number"
			if channel == "scale" then
				if isNumber and value ~= scale then
					scale = value
					geometryDirty = true
					refreshGeometry()
				end
			elseif channel == "radius" then
				if isNumber and value ~= radius then
					radius = value
					geometryDirty = true
					refreshGeometry()
				end
			elseif channel == "thickness" then
				if isNumber and value ~= thickness then
					thickness = value
					geometryDirty = true
					refreshGeometry()
				end
			elseif channel == "transparency" then
				if isNumber then
					transparency = value
					refreshAppearance()
				end
			elseif channel == "color" then
				if typeof(value) == "Color3" then
					color = value
					refreshAppearance()
				end
			end
		end

		function controller.setTransform(
			_self: ComponentInstance,
			_localCFrame: CFrame,
			worldCFrame: CFrame,
			frame: FrameContext
		)
			if not alive then
				return
			end
			world = worldCFrame
			place(frame)
		end

		-- Static geometry: update only flushes moves of geometry changed after the last setTransform.
		controller.update = function(_self: ComponentInstance, _time: number, frame: FrameContext)
			if alive then
				place(frame)
			end
		end

		function controller.release(_self: ComponentInstance)
			if not alive then
				return
			end
			released = true
			refreshAppearance()
		end

		function controller.reset(_self: ComponentInstance)
			if alive then
				restore()
			end
		end

		function controller.destroy(self: ComponentInstance)
			alive = false
			mover.forget()
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
		local layout = layoutOf(props)
		local n = layout.edges
		local cost = Common.cost()
		cost.instances = n
		cost.parts = n
		cost.movingParts = if Common.isMoving(component) then n else 0
		-- Heuristic writes per active frame: one Size write per part while the geometry is animated, one write
		-- per part for each tracked appearance channel.
		local updates = 0
		if tracks.radius or tracks.thickness or tracks.scale then
			updates += n
		end
		if tracks.transparency then
			updates += n
		end
		if tracks.color then
			updates += n
		end
		cost.propertyUpdates = updates
		local translucent = tracks.transparency ~= nil
			or (props.transparency > 0 and props.transparency < 1)
			or isSeeThrough(props.material)
		if translucent then
			cost.transparentLayers = n
			-- Heuristic: total line area (edge length × thickness).
			local cframes: { CFrame } = {}
			local sizes: { Vector3 } = {}
			local k = component.scale
			computeGeometry(
				layout,
				props.radius * k,
				props.innerRadius * k,
				props.thickness * k,
				props.height * k,
				cframes,
				sizes
			)
			local area = 0
			for _, size in sizes do
				area += size.X * size.Z
			end
			cost.overdrawWeight = area
		end
		if tracks.radius or tracks.thickness or tracks.scale then
			cost.notes = { "Animated radius/thickness/scale rewrites Part.Size of every line (costlier than moves)." }
		end
		return cost
	end,
}

return descriptor
