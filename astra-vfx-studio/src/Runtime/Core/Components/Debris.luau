--!strict
--[[
	debris — kinematic fragments: `count` small parts thrown from the component origin. docs/COMPONENTS_SPEC.md §14.

	Per piece i (own Core/Random stream seeded with Random.hash(component.seed, i), so piece i looks the same at
	every quality level — lower counts show a subset of the same pieces):
	  shape      Block | Wedge | Ball (Mixed: uniform pick of the three)
	  size       s ∈ [size.Min, size.Max); Ball (s, s, s); Block/Wedge (s, s·[0.5, 1), s·[0.6, 1)) for irregular chunks
	  velocity   v0 = rng:inCone(direction, spreadAngle) × [speed.Min, speed.Max)   (spreadAngle = cone half-angle)
	  spin       random axis, rate ∈ [spinSpeed.Min, spinSpeed.Max) deg/s, random initial orientation
	  colour     color × f, f = 1 + [−colorVariance, colorVariance) (brightness variance, clamped to 0..1)
	Motion — exact linear-drag ballistics (k = drag, g = gravity, p0 = origin), a pure function of localTime t:
	  p(t) = p0 + v0·(1 − e^(−kt))/k + g·(t/k − (1 − e^(−kt))/k²)          (k < 1e-6: p0 + v0·t + ½·g·t²)
	Floor (optional): the landing time t_hit = first t ≥ 0 at which y(t) < floorHeight is found at build time
	(closed form for k = 0, 64-step scan + bisection otherwise, searched over the component span). From t_hit on,
	the piece rests at p(t_hit) with y = floorHeight exactly and stops spinning (rotation frozen at t_hit).
	Fade: with S = endTime − startTime and F = min(fadeTime, S), a = clamp((t − (S − F))/F, 0, 1) (0 when F = 0);
	  Transparency = 1 − (1 − transparency)(1 − a), Size = size·(1 − a)   (pieces shrink while they fade)
	All motion happens in component space (direction, gravity and floor are local; rotate `direction`, not the
	component, to keep gravity pointing down) and is multiplied by the transform scale s:
	  CFrame = worldCFrame × CFrame(p(t)·s) × spin(t) × initialOrientation, Size × s.
	Channels: position, rotation, color (per-piece variance factors are kept), transparency (overrides the
	property). Invisible until setActive(true); release() hides the pieces until reset(). No instances are created
	after build.
]]

local Common = require(script.Parent.Common)
local Random = require(script.Parent.Parent.Random)
local Types = require(script.Parent.Parent.Types)

type CompiledComponent = Types.CompiledComponent
type ComponentInstance = Types.ComponentInstance
type FrameContext = Types.FrameContext
type CostEstimate = Types.CostEstimate

local MIN_SIZE = 0.001
local MAX_SIZE = 2048
local TAU = 2 * math.pi
local DRAG_EPSILON = 1e-6
local SCAN_STEPS = 64
local BISECTIONS = 48
local MIXED_SHAPES = { "Block", "Wedge", "Ball" }

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

local function countOf(component: CompiledComponent): number
	return math.max(1, math.floor(component.props.count))
end

-- Position at time t (component space, unscaled) of a piece starting at the origin with velocity v0.
local function ballistic(v0: Vector3, g: Vector3, k: number, t: number): Vector3
	if k < DRAG_EPSILON then
		return v0 * t + g * (0.5 * t * t)
	end
	local decay = 1 - math.exp(-k * t)
	return v0 * (decay / k) + g * (t / k - decay / (k * k))
end

-- Landing time without drag: smallest t > 0 with y(t) = vy·t + ½·gy·t² < floorHeight (floorHeight ≤ 0), solved
-- in closed form (numerically stable quadratic roots). 0 when the piece starts on the floor moving down.
local function landingTimeNoDrag(vy: number, gy: number, floorHeight: number): number
	-- y(t) − floorHeight = a·t² + b·t + c with c ≥ 0.
	local a, b, c = 0.5 * gy, vy, -floorHeight
	if c == 0 then
		if b < 0 or (b == 0 and a < 0) then
			return 0
		end
		return if b > 0 and a < 0 then -b / a else math.huge
	end
	if a == 0 then
		return if b < 0 then c / -b else math.huge
	end
	local disc = b * b - 4 * a * c
	if disc < 0 then
		return math.huge
	end
	local root = math.sqrt(disc)
	local q = -0.5 * (b + (if b >= 0 then root else -root))
	local first = math.huge
	local r1 = q / a
	if r1 > 0 then
		first = r1
	end
	if q ~= 0 then
		local r2 = c / q
		if r2 > 0 and r2 < first then
			first = r2
		end
	end
	return first
end

-- First time t ≥ 0 at which the piece is below floorHeight (math.huge if never). With drag the crossing is
-- searched in [0, horizon] (the component span): 64-step scan, then bisection.
local function landingTime(v0: Vector3, g: Vector3, k: number, floorHeight: number, horizon: number): number
	if floorHeight > 0 then
		return 0 -- starts below the floor: clamped from the start
	end
	if k < DRAG_EPSILON then
		return landingTimeNoDrag(v0.Y, g.Y, floorHeight)
	end
	if floorHeight == 0 and (v0.Y < 0 or (v0.Y == 0 and g.Y < 0)) then
		return 0
	end
	local function below(t: number): boolean
		return ballistic(v0, g, k, t).Y < floorHeight
	end
	local previous = 0
	for step = 1, SCAN_STEPS do
		local t = horizon * step / SCAN_STEPS
		if below(t) then
			local lo, hi = previous, t
			for _ = 1, BISECTIONS do
				local mid = (lo + hi) / 2
				if below(mid) then
					hi = mid
				else
					lo = mid
				end
			end
			return hi
		end
		previous = t
	end
	return math.huge
end

type Piece = {
	shape: string,
	size: Vector3, -- unscaled
	velocity: Vector3,
	spinAxis: Vector3,
	spinRate: number, -- radians per second
	orientation: CFrame, -- initial rotation
	colorFactor: number,
	landing: number, -- t_hit or math.huge
	rest: Vector3, -- resting position (valid when landing < math.huge)
}

-- Deterministic piece table (pure function of seed and props).
local function piecesOf(component: CompiledComponent): { Piece }
	local props = component.props
	local n = countOf(component)
	local sizeRange: NumberRange = props.size
	local speedRange: NumberRange = props.speed
	local spinRange: NumberRange = props.spinSpeed
	local direction: Vector3 = props.direction
	local spread: number = props.spreadAngle
	local gravity: Vector3 = props.gravity
	local drag = math.max(props.drag, 0)
	local variance = math.clamp(props.colorVariance, 0, 1)
	local shapeSetting: string = props.shape
	local floorEnabled = props.floor == true
	local floorHeight: number = props.floorHeight
	local span = math.max(component.endTime - component.startTime, 0)
	local pieces: { Piece } = {}
	for i = 1, n do
		local rng = Random.new(Random.hash(component.seed, i))
		local shape = shapeSetting
		local pick = rng:int(1, #MIXED_SHAPES)
		if shape ~= "Block" and shape ~= "Wedge" and shape ~= "Ball" then
			shape = MIXED_SHAPES[pick]
		end
		local s = rng:range(sizeRange.Min, sizeRange.Max)
		local sy = s * rng:range(0.5, 1)
		local sz = s * rng:range(0.6, 1)
		local size = if shape == "Ball" then Vector3.new(s, s, s) else Vector3.new(s, sy, sz)
		local velocity = rng:inCone(direction, spread) * rng:range(speedRange.Min, speedRange.Max)
		local spinAxis = rng:unitVector()
		local spinRate = math.rad(rng:range(spinRange.Min, spinRange.Max))
		local orientation = CFrame.fromAxisAngle(rng:unitVector(), rng:range(0, TAU))
		local colorFactor = 1 + rng:range(-variance, variance)
		local landing = if floorEnabled then landingTime(velocity, gravity, drag, floorHeight, span) else math.huge
		local rest = Vector3.zero
		if landing < math.huge then
			local p = ballistic(velocity, gravity, drag, landing)
			rest = Vector3.new(p.X, floorHeight, p.Z)
		end
		pieces[i] = {
			shape = shape,
			size = size,
			velocity = velocity,
			spinAxis = spinAxis,
			spinRate = spinRate,
			orientation = orientation,
			colorFactor = colorFactor,
			landing = landing,
			rest = rest,
		}
	end
	return pieces
end

local function varied(color: Color3, factor: number): Color3
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

local function clampVector(v: Vector3): Vector3
	return Vector3.new(
		math.clamp(v.X, MIN_SIZE, MAX_SIZE),
		math.clamp(v.Y, MIN_SIZE, MAX_SIZE),
		math.clamp(v.Z, MIN_SIZE, MAX_SIZE)
	)
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
	type = "debris",
	displayName = "Debris",
	category = "Procedural",
	description = "Kinematic rock fragments thrown in a cone, with exact drag ballistics, spin, floor and fade.",
	icon = "▲",
	properties = {
		Common.prop("count", "integer", 12, "Number of pieces.", {
			category = "Emission",
			min = 1,
			max = 200,
			quality = "count",
		}),
		Common.prop("shape", "enum", "Mixed", "Piece shape (Mixed picks Block, Wedge or Ball per piece).", {
			category = "Shape",
			enum = { "Block", "Wedge", "Ball", "Mixed" },
		}),
		Common.prop("size", "numberRange", { 0.3, 0.8 }, "Piece size range in studs.", {
			category = "Shape",
			min = 0.01,
			max = 50,
			scale = "length",
		}),
		Common.prop("speed", "numberRange", { 20, 40 }, "Initial speed range in studs/second.", {
			category = "Motion",
			min = 0,
			max = 2000,
			scale = "length",
		}),
		Common.prop("direction", "vector3", { 0, 1, 0 }, "Main throw direction (component space).", {
			category = "Motion",
		}),
		Common.prop("spreadAngle", "number", 60, "Cone half-angle around the direction in degrees.", {
			category = "Motion",
			min = 0,
			max = 180,
		}),
		Common.prop("gravity", "vector3", { 0, -80, 0 }, "Acceleration in studs/second² (component space).", {
			category = "Motion",
			scale = "length",
		}),
		Common.prop("drag", "number", 0, "Linear drag coefficient k (velocity decays as e^(−k·t)).", {
			category = "Motion",
			min = 0,
			max = 20,
		}),
		Common.prop("spinSpeed", "numberRange", { 90, 360 }, "Spin speed range in degrees/second.", {
			category = "Motion",
			min = 0,
			max = 3600,
		}),
		Common.prop("color", "color3", "#6B5B4B", "Base colour of the pieces.", { category = "Appearance" }),
		Common.prop("colorVariance", "number", 0.15, "Per-piece brightness variance (0 = all identical).", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("material", "enum", "Slate", "Piece material.", {
			category = "Appearance",
			enum = MATERIALS,
			enumType = "Material",
		}),
		Common.prop("transparency", "number", 0, "Piece transparency.", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("fadeTime", "number", 0.3, "Pieces fade out and shrink during the last fadeTime seconds.", {
			category = "Appearance",
			min = 0,
			max = 10,
			step = 0.05,
		}),
		Common.prop("floor", "boolean", false, "Stop pieces at floorHeight (they rest and stop spinning).", {
			category = "Floor",
		}),
		Common.prop("floorHeight", "number", 0, "Floor height on the local Y axis in studs.", {
			category = "Floor",
			scale = "length",
		}),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		Common.channel("color", "color3", "Base colour (per-piece variance is kept).", { baseProperty = "color" }),
		Common.channel("transparency", "number", "Part.Transparency before the fade-out.", {
			min = 0,
			max = 1,
			baseProperty = "transparency",
		}),
	},
	events = {},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local pieces = piecesOf(component)
		local parts: { BasePart } = {}
		local instances: { Instance } = {}
		for i, piece in pieces do
			local part = Common.newPart(ctx, component.id, component.name .. "_Piece" .. i) :: Part
			part.Shape = (Enum.PartType :: any)[piece.shape]
			part.Material = props.material
			parts[i] = part
			instances[i] = part
		end
		local controller = Common.controller(component, instances)
		local mover = newMover(parts)

		local scale = math.max(component.scale, 0)
		local gravity: Vector3 = props.gravity
		local drag = math.max(props.drag, 0)
		local span = math.max(component.endTime - component.startTime, 0)
		local fadeLength = math.clamp(props.fadeTime, 0, span)
		local fadeStart = span - fadeLength

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
		local fade = 0
		local locals: { CFrame } = {}

		local writtenSize: { Vector3 } = {}
		local writtenTransparency: number? = nil
		local writtenColor: Color3? = nil

		local function evaluate()
			evaluations += 1
			local t = math.max(localTime, 0)
			fade = if fadeLength > 0 then math.clamp((t - fadeStart) / fadeLength, 0, 1) else 0
			for i, piece in pieces do
				local p: Vector3
				local spinTime = t
				if t >= piece.landing then
					p = piece.rest
					spinTime = piece.landing
				else
					p = ballistic(piece.velocity, gravity, drag, t)
				end
				local spin = CFrame.fromAxisAngle(piece.spinAxis, piece.spinRate * spinTime)
				locals[i] = CFrame.new(p * scale) * spin * piece.orientation
			end
		end

		local function refresh()
			local shrink = (1 - fade) * scale
			for i, part in parts do
				local size = clampVector(pieces[i].size * shrink)
				if size ~= writtenSize[i] then
					writtenSize[i] = size
					part.Size = size
				end
			end
			local t = 1
			if active and not released then
				t = 1 - (1 - math.clamp(transparency, 0, 1)) * (1 - fade)
			end
			if t ~= writtenTransparency then
				writtenTransparency = t
				for _, part in parts do
					part.Transparency = t
				end
			end
			if color ~= writtenColor then
				writtenColor = color
				for i, part in parts do
					part.Color = varied(color, pieces[i].colorFactor)
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
			for i in parts do
				mover.move(frame, i, w * locals[i])
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
		-- Procedural motion: every piece moves every frame (until it rests on the floor).
		cost.movingParts = n
		-- Heuristic peak writes per frame: Size + Transparency of every piece while fading, + Color while tracked.
		local updates = 0
		if props.fadeTime > 0 then
			updates += 2 * n
		elseif tracks.transparency then
			updates += n
		end
		if tracks.color then
			updates += n
		end
		cost.propertyUpdates = updates
		local translucent = tracks.transparency ~= nil
			or (props.transparency > 0 and props.transparency < 1)
			or isSeeThrough(props.material)
			or props.fadeTime > 0
		if translucent then
			cost.transparentLayers = n
			local sizeRange: NumberRange = props.size
			local s = (sizeRange.Min + sizeRange.Max) / 2 * component.scale
			cost.overdrawWeight = n * s * s
		end
		cost.notes = { "Debris pieces move every frame and resize while fading (Part.Size writes)." }
		return cost
	end,
}

return descriptor
