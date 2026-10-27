--!strict
--[[
	radialBurst — impact lines / spikes: `count` thin Block parts shooting outward from the component origin along
	deterministic directions. docs/COMPONENTS_SPEC.md §13.

	Directions (component space, fixed at build time). Each spike i (0-based, n = count) blends a regular direction
	b_i with a random direction q_i drawn from the same distribution (Core/Random seeded with component.seed):
	  d_i = unit(lerp(b_i, q_i, jitter))        (falls back to b_i if the blend is degenerate)
	  sphere      b_i: Fibonacci sphere  y = 1 − 2(i + ½)/n,                        q_i: rng:unitVector()
	  hemisphere  b_i: Fibonacci cap     y = 1 − (i + ½)/n   (upper half, +Y),      q_i: unitVector with |y|
	  cone        b_i: Fibonacci cap     cos θ = 1 − (i + ½)/n·(1 − cos coneAngle), q_i: rng:inCone(+Y, coneAngle)
	  ring        b_i: angle −π/2 + 2πi/n in the local XZ plane,                    q_i: unitVector projected on XZ
	The azimuth of the Fibonacci patterns advances by the golden angle. jitter = 0 gives perfectly regular,
	seed-independent directions; jitter = 1 fully random ones.

	Animation — a pure function of localTime (S = component span endTime − startTime, s = transform scale):
	  u    = clamp(localTime / S, 0, 1)
	  head = lerp(startRadius, endRadius, Cubic.Out(u))       tail = lerp(startRadius, endRadius, Cubic.In(u))
	  spike i: centre d_i·(head + tail)/2·s, long axis d_i, Size = (w, w, |head − tail|·s), w = width·(1 − u)·s
	So the spike length rises from 0, peaks (¾ of the travel at u = ½) and shrinks back to 0 while the width tapers
	to 0. Degenerate spikes (length or width below the 0.001-stud engine minimum, i.e. at u = 0 and u = 1) are
	hidden. Channels: position, rotation, transparency (Part.Transparency, overrides the property), color.
	All parts are allocated at build time; update() rewrites Size (all spikes share one size) and queues the moved
	CFrames on frame.moveParts. Invisible until setActive(true); release() hides the spikes until reset().
]]

local Common = require(script.Parent.Common)
local Easing = require(script.Parent.Parent.Easing)
local Random = require(script.Parent.Parent.Random)
local Types = require(script.Parent.Parent.Types)

type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type FrameContext = Types.FrameContext
type CostEstimate = Types.CostEstimate

local MIN_SIZE = 0.001
local MAX_SIZE = 2048
local MIN_SPAN = 1 / 60
local TAU = 2 * math.pi
local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
local UP = Vector3.new(0, 1, 0)

local headEase = Easing.get("Cubic", "Out")
local tailEase = Easing.get("Cubic", "In")

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

local function isSeeThrough(material: any): boolean
	return material == Enum.Material.ForceField or material == Enum.Material.Glass
end

-- CFrame at `position` whose LookVector is `direction` (CFrame.lookAt with a fallback up axis for vertical
-- directions, where lookAt with +Y up is undefined).
local function lookAlong(position: Vector3, direction: Vector3): CFrame
	local magnitude = direction.Magnitude
	if magnitude < 1e-9 then
		return CFrame.new(position)
	end
	local look = direction / magnitude
	local up = if math.abs(look.Y) < 0.999 then UP else Vector3.new(0, 0, 1)
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(position, right, right:Cross(look), -look)
end

local function countOf(component: CompiledComponent): number
	return math.max(1, math.floor(component.props.count))
end

local function fibonacci(i: number, y: number): Vector3
	local r = math.sqrt(math.max(0, 1 - y * y))
	local azimuth = i * GOLDEN_ANGLE
	return Vector3.new(math.cos(azimuth) * r, y, math.sin(azimuth) * r)
end

-- Regular direction of spike i (0-based) out of n.
local function regularDirection(distribution: string, i: number, n: number, coneAngle: number): Vector3
	if distribution == "hemisphere" then
		return fibonacci(i, 1 - (i + 0.5) / n)
	elseif distribution == "cone" then
		local cosCone = math.cos(math.rad(math.clamp(coneAngle, 0, 180)))
		return fibonacci(i, 1 - (i + 0.5) / n * (1 - cosCone))
	elseif distribution == "ring" then
		local theta = -math.pi / 2 + TAU * i / n
		return Vector3.new(math.cos(theta), 0, math.sin(theta))
	end
	return fibonacci(i, 1 - 2 * (i + 0.5) / n)
end

-- Random direction from the same distribution.
local function randomDirection(rng: Random.Rng, distribution: string, coneAngle: number): Vector3
	if distribution == "hemisphere" then
		local v = rng:unitVector()
		return Vector3.new(v.X, math.abs(v.Y), v.Z)
	elseif distribution == "cone" then
		return rng:inCone(UP, coneAngle)
	elseif distribution == "ring" then
		local v = rng:unitVector()
		local flat = Vector3.new(v.X, 0, v.Z)
		return if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(1, 0, 0)
	end
	return rng:unitVector()
end

-- Deterministic spike directions for a component (pure function of seed and props).
local function directionsOf(component: CompiledComponent): { Vector3 }
	local props = component.props
	local n = countOf(component)
	local distribution: string = props.distribution
	local coneAngle: number = props.coneAngle
	local jitter = math.clamp(props.jitter, 0, 1)
	local rng = Random.new(component.seed)
	local out: { Vector3 } = {}
	for i = 0, n - 1 do
		local base = regularDirection(distribution, i, n, coneAngle)
		local random = randomDirection(rng, distribution, coneAngle)
		local blended = base:Lerp(random, jitter)
		out[i + 1] = if blended.Magnitude > 1e-6 then blended.Unit else base
	end
	return out
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
	type = "radialBurst",
	displayName = "Radial Burst",
	category = "Procedural",
	description = "Impact lines: thin spikes shooting outward along deterministic directions, then vanishing.",
	icon = "✳",
	properties = {
		Common.prop("count", "integer", 12, "Number of spikes.", {
			category = "Shape",
			min = 1,
			max = 256,
			quality = "count",
		}),
		Common.prop("distribution", "enum", "sphere", "Direction pattern: sphere, upper hemisphere, XZ ring, cone.", {
			category = "Shape",
			enum = { "sphere", "hemisphere", "ring", "cone" },
		}),
		Common.prop("coneAngle", "number", 45, "Cone half-angle in degrees around the local +Y axis (cone).", {
			category = "Shape",
			min = 0,
			max = 180,
		}),
		Common.prop("startRadius", "number", 0.5, "Distance from the origin where the spikes start, in studs.", {
			category = "Motion",
			min = 0,
			max = 2000,
			scale = "length",
		}),
		Common.prop("endRadius", "number", 10, "Distance the spike heads travel to, in studs.", {
			category = "Motion",
			min = 0,
			max = 2000,
			scale = "length",
		}),
		Common.prop("width", "number", 0.3, "Spike width in studs at the start (tapers to 0).", {
			category = "Shape",
			min = 0.001,
			max = 100,
			scale = "length",
		}),
		Common.prop("jitter", "number", 0.3, "Direction randomness: 0 = regular pattern, 1 = fully random.", {
			category = "Shape",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("color", "color3", "#FFFFFF", "Spike colour.", { category = "Appearance" }),
		Common.prop("material", "enum", "Neon", "Spike material.", {
			category = "Appearance",
			enum = MATERIALS,
			enumType = "Material",
		}),
		Common.prop("transparency", "number", 0, "Spike transparency.", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
		}),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		Common.channel("transparency", "number", "Part.Transparency of every spike.", {
			min = 0,
			max = 1,
			baseProperty = "transparency",
		}),
		Common.channel("color", "color3", "Part.Color of every spike.", { baseProperty = "color" }),
	},
	events = {},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local directions = directionsOf(component)
		local parts: { BasePart } = {}
		local instances: { Instance } = {}
		local rotations: { CFrame } = {}
		for i, direction in directions do
			local part = Common.newPart(ctx, component.id, component.name .. "_Spike" .. i) :: Part
			part.Shape = Enum.PartType.Block
			part.Material = props.material
			parts[i] = part
			instances[i] = part
			rotations[i] = lookAlong(Vector3.zero, direction)
		end
		local controller = Common.controller(component, instances)
		local mover = newMover(parts)

		local scale = math.max(component.scale, 0)
		local startRadius: number = props.startRadius
		local endRadius: number = props.endRadius
		local width: number = props.width
		local span = math.max(component.endTime - component.startTime, MIN_SPAN)

		local alive = true
		local active = false
		local released = false
		local localTime = 0
		local transparency: number = props.transparency
		local color: Color3 = props.color
		local world: CFrame? = nil
		-- Placement cache: skip the per-part CFrame work when neither the transform nor the local state changed.
		local evaluations = 0
		local placedWorld: CFrame? = nil
		local placedEvaluation = -1

		-- Geometry at the current local time (shared by every spike).
		local centre = 0
		local spikeSize = Vector3.new(MIN_SIZE, MIN_SIZE, MIN_SIZE)
		local degenerate = true

		local writtenSize: Vector3? = nil
		local writtenTransparency: number? = nil
		local writtenColor: Color3? = nil

		local function evaluate()
			evaluations += 1
			local u = math.clamp(localTime / span, 0, 1)
			local head = startRadius + (endRadius - startRadius) * headEase(u)
			local tail = startRadius + (endRadius - startRadius) * tailEase(u)
			local length = math.abs(head - tail) * scale
			local w = width * (1 - u) * scale
			centre = (head + tail) / 2 * scale
			degenerate = length < MIN_SIZE or w < MIN_SIZE
			local sw = math.clamp(w, MIN_SIZE, MAX_SIZE)
			spikeSize = Vector3.new(sw, sw, math.clamp(length, MIN_SIZE, MAX_SIZE))
		end

		local function refresh()
			if spikeSize ~= writtenSize then
				writtenSize = spikeSize
				for _, part in parts do
					part.Size = spikeSize
				end
			end
			local t = if active and not released and not degenerate then math.clamp(transparency, 0, 1) else 1
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

		local function place(frame: FrameContext)
			local w = world
			if w == nil or (w == placedWorld and evaluations == placedEvaluation) then
				return
			end
			placedWorld = w
			placedEvaluation = evaluations
			for i, direction in directions do
				mover.move(frame, i, w * (rotations[i] + direction * centre))
			end
		end

		local function restore()
			active = false
			released = false
			localTime = 0
			transparency = props.transparency
			color = props.color
			world = nil
			placedWorld = nil
			mover.forget()
			evaluate()
			refresh()
		end
		restore()

		function controller.setActive(_self: ComponentInstance, isActive: boolean, _frame: FrameContext)
			if not alive then
				return
			end
			active = isActive
			refresh()
		end

		function controller.apply(_self: ComponentInstance, channel: string, value: any)
			if not alive then
				return
			end
			if channel == "transparency" then
				if type(value) == "number" then
					transparency = value
					refresh()
				end
			elseif channel == "color" then
				if typeof(value) == "Color3" then
					color = value
					refresh()
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

		controller.update = function(_self: ComponentInstance, time: number, frame: FrameContext)
			if not alive then
				return
			end
			if time ~= localTime then
				localTime = time
				evaluate()
				refresh()
			end
			place(frame)
		end

		function controller.release(_self: ComponentInstance)
			if not alive then
				return
			end
			released = true
			refresh()
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
		local n = countOf(component)
		local cost = Common.cost()
		cost.instances = n
		cost.parts = n
		-- Procedural motion: every spike moves every frame while the burst plays.
		cost.movingParts = n
		-- Heuristic: one Size write per spike per frame, + one per tracked appearance channel.
		cost.propertyUpdates = n + (if tracks.transparency then n else 0) + (if tracks.color then n else 0)
		local translucent = tracks.transparency ~= nil
			or (props.transparency > 0 and props.transparency < 1)
			or isSeeThrough(props.material)
		if translucent then
			cost.transparentLayers = n
			-- Heuristic: spike area at the peak (¾ of the travel × width at mid-life).
			local travel = math.abs(props.endRadius - props.startRadius) * component.scale
			cost.overdrawWeight = n * 0.75 * travel * props.width * 0.5 * component.scale
		end
		cost.notes = { "Spikes resize every frame (Part.Size writes are costlier than moves)." }
		return cost
	end,
}

return descriptor
