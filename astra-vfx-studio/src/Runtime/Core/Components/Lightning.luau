--!strict
--[[
	lightning — procedural bolts and arcs. docs/COMPONENTS_SPEC.md §15.

	Shape (component space, then × transform scale s). The main bolt is a polyline of n = segments points from
	`from` to `to` (so n − 1 sub-segments); interior point j (u = (j − 1)/(n − 1)) is offset perpendicular to the
	bolt by a random vector of length ≤ jitter·sin(π·u) (uniform angle around the axis, uniform radius). The
	endpoints are exactly `from` and `to` (no offset is computed for them).
	Branches (only when branchLength > 0): `branches` side bolts starting at a random point of the main polyline
	(u ∈ [0.15, 0.85)), heading 20°..45° away from the bolt direction (random side) with length branchLength × main
	length; each is a zig-zag of m = max(2, round((n − 1)·branchLength) + 1) points with half the jitter, drawn
	0.6 × as thick as the main bolt.
	Shape seed = Random.hash(component.seed, regenerateCount, floor(localTime·flickerRate + 1e-9)) → a new
	deterministic shape every 1/flickerRate seconds (flickerRate 0 = static; the 1e-9 guards bucket edges against
	float noise). The `regenerate` event increments regenerateCount (reset() restores 0). The shape is recomputed
	only when the seed bucket or `from`/`to` change, so update() is a pure function of (localTime, seed,
	regenerateCount, props, channel values).

	render = "beam": one Attachment per polyline point on ctx.root (Attachment.CFrame = localCFrame × point) and one
	Beam per sub-segment between consecutive attachments, parented to the Root part: FaceCamera = true,
	Segments = 1, Width0 = Width1 = thickness·s, CurveSize 0, LightEmission / Brightness / Texture from the
	properties, LightInfluence 0, Color = ColorSequence(color), Transparency = NumberSequence(transparency).
	Beams do not render in a ViewportFrame, so a viewport build always uses part mode.
	render = "part": one Block part per sub-segment (material from the properties, Neon by default) with
	Size = (w, w, |b − a|) and local CFrame lookAt(midpoint, b) (with a fallback up axis for vertical segments,
	where CFrame.lookAt with +Y up is undefined); world CFrames are queued on frame.moveParts.

	All instances are allocated at build time (counts after quality). Channels: position, rotation, from, to
	(component space), thickness, transparency (overrides the property), color. Invisible until setActive(true);
	release() hides the bolt until reset().
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
local UP = Vector3.new(0, 1, 0)
local DOWN = Vector3.new(0, -1, 0)
local BRANCH_THICKNESS = 0.6
local BRANCH_JITTER = 0.5
local BRANCH_MIN_ANGLE = 20
local BRANCH_MAX_ANGLE = 45
local BUCKET_EPSILON = 1e-9

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

-- CFrame at `position` whose LookVector is `direction`.
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

-- Two unit vectors perpendicular to the unit vector d (and to each other).
local function perpendicularBasis(d: Vector3): (Vector3, Vector3)
	local helper = if math.abs(d.Y) < 0.9 then UP else Vector3.new(1, 0, 0)
	local p1 = helper:Cross(d).Unit
	return p1, d:Cross(p1)
end

export type Layout = {
	points: number, -- main bolt points n
	branches: number, -- effective branch count
	branchPoints: number, -- points per branch m
	segments: number, -- total sub-segments (beams or parts)
	attachments: number, -- total polyline points (beam mode attachments)
}

local function layoutOf(props: { [string]: any }): Layout
	local n = math.max(2, math.floor(props.segments))
	local branchLength: number = props.branchLength
	local b = if branchLength > 0 then math.max(0, math.floor(props.branches)) else 0
	local m = math.max(2, math.floor((n - 1) * branchLength + 0.5) + 1)
	return {
		points = n,
		branches = b,
		branchPoints = m,
		segments = (n - 1) + b * (m - 1),
		attachments = n + b * m,
	}
end

-- Zig-zag from a to b with `count` points into out[1..count]; endpoints exact, offsets ≤ jitter·sin(π·u).
local function zigzag(rng: Random.Rng, a: Vector3, b: Vector3, count: number, jitter: number, out: { Vector3 })
	local delta = b - a
	local length = delta.Magnitude
	local d = if length > 1e-9 then delta / length else DOWN
	local p1, p2 = perpendicularBasis(d)
	out[1] = a
	for j = 2, count - 1 do
		local u = (j - 1) / (count - 1)
		local angle = rng:next() * TAU
		local radius = rng:next() * jitter * math.sin(math.pi * u)
		out[j] = a + delta * u + (p1 * math.cos(angle) + p2 * math.sin(angle)) * radius
	end
	out[count] = b
end

-- Fills polylines[1] (main bolt) and polylines[2..] (branches) for one shape seed.
local function generate(
	layout: Layout,
	shapeSeed: number,
	from: Vector3,
	to: Vector3,
	jitter: number,
	branchLength: number,
	polylines: { { Vector3 } }
)
	local rng = Random.new(shapeSeed)
	local main = polylines[1]
	local n = layout.points
	zigzag(rng, from, to, n, jitter, main)
	local delta = to - from
	local mainLength = delta.Magnitude
	local d = if mainLength > 1e-9 then delta / mainLength else DOWN
	local p1, p2 = perpendicularBasis(d)
	for branch = 1, layout.branches do
		local u0 = rng:range(0.15, 0.85)
		local f = u0 * (n - 1)
		local k = math.min(math.floor(f) + 1, n - 1)
		local frac = f - (k - 1)
		local start = main[k] + (main[k + 1] - main[k]) * frac
		local angle = math.rad(rng:range(BRANCH_MIN_ANGLE, BRANCH_MAX_ANGLE))
		local side = rng:next() * TAU
		local sideways = p1 * math.cos(side) + p2 * math.sin(side)
		local direction = d * math.cos(angle) + sideways * math.sin(angle)
		local stop = start + direction * (branchLength * mainLength)
		zigzag(rng, start, stop, layout.branchPoints, jitter * BRANCH_JITTER, polylines[branch + 1])
	end
end

type Segment = { line: number, index: number, widthFactor: number }

-- Flat list of sub-segments: main bolt first, then each branch.
local function segmentsOf(layout: Layout): { Segment }
	local out: { Segment } = {}
	for j = 1, layout.points - 1 do
		table.insert(out, { line = 1, index = j, widthFactor = 1 })
	end
	for b = 1, layout.branches do
		for j = 1, layout.branchPoints - 1 do
			table.insert(out, { line = b + 1, index = j, widthFactor = BRANCH_THICKNESS })
		end
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
	type = "lightning",
	displayName = "Lightning",
	category = "Procedural",
	description = "Flickering zig-zag bolts with branches, drawn with beams or neon parts.",
	icon = "ϟ",
	properties = {
		Common.prop("from", "vector3", { 0, 10, 0 }, "Start point of the bolt in component space.", {
			category = "Shape",
			scale = "length",
		}),
		Common.prop("to", "vector3", { 0, 0, 0 }, "End point of the bolt in component space.", {
			category = "Shape",
			scale = "length",
		}),
		Common.prop("segments", "integer", 12, "Points along the main bolt (including both ends).", {
			category = "Shape",
			min = 2,
			max = 64,
			quality = "segments",
		}),
		Common.prop("jitter", "number", 1.5, "Maximum sideways offset of the zig-zag in studs.", {
			category = "Shape",
			min = 0,
			max = 500,
			scale = "length",
		}),
		Common.prop("branches", "integer", 2, "Number of side branches.", {
			category = "Shape",
			min = 0,
			max = 8,
			quality = "count",
		}),
		Common.prop("branchLength", "number", 0.35, "Branch length relative to the main bolt (0 = no branches).", {
			category = "Shape",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("flickerRate", "number", 20, "New random shape per second (0 = static shape).", {
			category = "Animation",
			min = 0,
			max = 120,
		}),
		Common.prop("thickness", "number", 0.3, "Bolt width in studs (branches are 0.6 × as thick).", {
			category = "Appearance",
			min = 0.01,
			max = 50,
			scale = "length",
		}),
		Common.prop("color", "color3", "#A8DCFF", "Bolt colour.", { category = "Appearance" }),
		Common.prop("render", "enum", "beam", "Drawn with Beams (glow) or Neon parts (renders in viewports).", {
			category = "Appearance",
			enum = { "beam", "part" },
		}),
		Common.prop("lightEmission", "number", 1, "Beam additive blending (beam render).", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("brightness", "number", 2, "Beam brightness (beam render).", {
			category = "Appearance",
			min = 0,
			max = 100,
		}),
		Common.prop("texture", "asset", "", "Beam texture (beam render; empty = solid colour).", {
			category = "Appearance",
		}),
		Common.prop("transparency", "number", 0, "Bolt transparency.", {
			category = "Appearance",
			min = 0,
			max = 1,
			step = 0.05,
		}),
		Common.prop("material", "enum", "Neon", "Part material (part render).", {
			category = "Appearance",
			enum = MATERIALS,
			enumType = "Material",
		}),
	},
	channels = {
		Common.channel("position", "vector3", "Offset from the parent/effect origin in studs.", { scale = "length" }),
		Common.channel("rotation", "vector3", "Rotation in degrees (Orientation order X, Y, Z)."),
		Common.channel("from", "vector3", "Start point in component space.", {
			scale = "length",
			baseProperty = "from",
		}),
		Common.channel("to", "vector3", "End point in component space.", { scale = "length", baseProperty = "to" }),
		Common.channel("thickness", "number", "Bolt width in studs.", {
			min = 0.01,
			max = 50,
			scale = "length",
			baseProperty = "thickness",
		}),
		Common.channel("transparency", "number", "Bolt transparency (Beam.Transparency / Part.Transparency).", {
			min = 0,
			max = 1,
			baseProperty = "transparency",
		}),
		Common.channel("color", "color3", "Bolt colour (Beam.Color / Part.Color).", { baseProperty = "color" }),
	},
	events = {
		{ action = "regenerate", description = "Draws a new random bolt shape immediately." },
	},
	canParent = true,
	supportsViewport = true,
	build = function(ctx: Types.BuildContext, component: CompiledComponent): ComponentInstance
		local props = component.props
		local layout = layoutOf(props)
		local segments = segmentsOf(layout)
		local partMode = props.render == "part" or ctx.viewport

		local polylines: { { Vector3 } } = { {} }
		for b = 1, layout.branches do
			polylines[b + 1] = {}
		end

		local instances: { Instance } = {}
		local parts: { BasePart } = {}
		local beams: { Beam } = {}
		local attachments: { { Attachment } } = {}
		if partMode then
			for i = 1, #segments do
				local part = Common.newPart(ctx, component.id, component.name .. "_Segment" .. i) :: Part
				part.Shape = Enum.PartType.Block
				part.Material = props.material
				parts[i] = part
				table.insert(instances, part)
			end
		else
			for line = 1, #polylines do
				local count = if line == 1 then layout.points else layout.branchPoints
				local list: { Attachment } = {}
				for j = 1, count do
					list[j] = Common.newAttachment(ctx, component.id, component.name .. "_P" .. line .. "_" .. j)
				end
				attachments[line] = list
			end
			for i, segment in segments do
				local beam = Instance.new("Beam")
				beam.Name = component.name .. "_Bolt" .. i
				beam.Enabled = false
				beam.Attachment0 = attachments[segment.line][segment.index]
				beam.Attachment1 = attachments[segment.line][segment.index + 1]
				beam.FaceCamera = true
				beam.Segments = 1
				beam.CurveSize0 = 0
				beam.CurveSize1 = 0
				beam.Texture = props.texture
				beam.LightEmission = props.lightEmission
				beam.LightInfluence = 0
				beam.Brightness = props.brightness
				ctx.tagInstance(beam, component.id)
				beam.Parent = ctx.root
				beams[i] = beam
				table.insert(instances, beam)
			end
			for _, list in attachments do
				for _, attachment in list do
					table.insert(instances, attachment)
				end
			end
		end
		local controller = Common.controller(component, instances)
		local mover = newMover(parts)

		local scale = math.max(component.scale, 0)
		local jitter: number = props.jitter
		local branchLength: number = props.branchLength
		local flickerRate = math.max(props.flickerRate, 0)

		local alive = true
		local active = false
		local released = false
		local localTime = 0
		local regenerateCount = 0
		local from: Vector3 = props.from
		local to: Vector3 = props.to
		local thickness: number = props.thickness
		local transparency: number = props.transparency
		local color: Color3 = props.color
		local localCFrame = CFrame.identity
		local world: CFrame? = nil
		local placedWorld: CFrame? = nil
		local placedVersion = -1

		-- Shape cache: recomputed when the seed bucket or the endpoints change.
		local shapeBucket: number? = nil
		local shapeRegenerations = -1
		local shapeFrom: Vector3? = nil
		local shapeTo: Vector3? = nil
		local shapeVersion = 0
		local geometryVersion = -1
		local segmentCFrames: { CFrame } = {}
		local segmentLengths: { number } = {}

		local writtenAttachment: { { CFrame } } = {}
		local writtenWidth: { number } = {}
		local writtenSize: { Vector3 } = {}
		local writtenEnabled: boolean? = nil
		local writtenTransparency: number? = nil
		local writtenColor: Color3? = nil
		for line = 1, #attachments do
			writtenAttachment[line] = {}
		end

		local function bucketAt(time: number): number
			return math.floor(time * flickerRate + BUCKET_EPSILON)
		end

		-- Recomputes the polylines when needed; returns true when the shape changed.
		local function ensureShape(): boolean
			local bucket = bucketAt(localTime)
			if
				bucket == shapeBucket
				and regenerateCount == shapeRegenerations
				and from == shapeFrom
				and to == shapeTo
			then
				return false
			end
			shapeBucket = bucket
			shapeRegenerations = regenerateCount
			shapeFrom = from
			shapeTo = to
			local seed = Random.hash(component.seed, regenerateCount, bucket)
			generate(layout, seed, from, to, jitter, branchLength, polylines)
			shapeVersion += 1
			return true
		end

		-- Part mode: local CFrame and length of every sub-segment (scaled).
		local function refreshSegmentGeometry()
			if geometryVersion == shapeVersion then
				return
			end
			geometryVersion = shapeVersion
			for i, segment in segments do
				local line = polylines[segment.line]
				local a = line[segment.index] * scale
				local b = line[segment.index + 1] * scale
				segmentCFrames[i] = lookAlong((a + b) / 2, b - a)
				segmentLengths[i] = (b - a).Magnitude
			end
		end

		local function refreshAttachments()
			for line, list in attachments do
				local points = polylines[line]
				local written = writtenAttachment[line]
				for j, attachment in list do
					local cf = localCFrame * CFrame.new(points[j] * scale)
					if cf ~= written[j] then
						written[j] = cf
						attachment.CFrame = cf
					end
				end
			end
		end

		local function place(frame: FrameContext?)
			local w = world
			if not partMode or w == nil or frame == nil then
				return
			end
			if w == placedWorld and geometryVersion == placedVersion then
				return
			end
			placedWorld = w
			placedVersion = geometryVersion
			for i in parts do
				mover.move(frame, i, w * segmentCFrames[i])
			end
		end

		local function refresh()
			local visible = active and not released
			local t = math.clamp(transparency, 0, 1)
			if partMode then
				refreshSegmentGeometry()
				local width = math.max(thickness, 0) * scale
				for i, part in parts do
					local w = math.clamp(width * segments[i].widthFactor, MIN_SIZE, MAX_SIZE)
					local size = Vector3.new(w, w, math.clamp(segmentLengths[i], MIN_SIZE, MAX_SIZE))
					if size ~= writtenSize[i] then
						writtenSize[i] = size
						part.Size = size
					end
				end
				local pt = if visible then t else 1
				if pt ~= writtenTransparency then
					writtenTransparency = pt
					for _, part in parts do
						part.Transparency = pt
					end
				end
				if color ~= writtenColor then
					writtenColor = color
					for _, part in parts do
						part.Color = color
					end
				end
			else
				refreshAttachments()
				local width = math.max(thickness, 0) * scale
				for i, beam in beams do
					local w = width * segments[i].widthFactor
					if w ~= writtenWidth[i] then
						writtenWidth[i] = w
						beam.Width0 = w
						beam.Width1 = w
					end
				end
				if visible ~= writtenEnabled then
					writtenEnabled = visible
					for _, beam in beams do
						beam.Enabled = visible
					end
				end
				if t ~= writtenTransparency then
					writtenTransparency = t
					local sequence = NumberSequence.new(t)
					for _, beam in beams do
						beam.Transparency = sequence
					end
				end
				if color ~= writtenColor then
					writtenColor = color
					local sequence = ColorSequence.new(color)
					for _, beam in beams do
						beam.Color = sequence
					end
				end
			end
		end

		local function restore()
			active = false
			released = false
			localTime = 0
			regenerateCount = 0
			from = props.from
			to = props.to
			thickness = props.thickness
			transparency = props.transparency
			color = props.color
			localCFrame = CFrame.identity
			world = nil
			placedWorld = nil
			mover.forget()
			ensureShape()
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
			if channel == "from" then
				if typeof(value) == "Vector3" and value ~= from then
					from = value
					ensureShape()
					refresh()
				end
			elseif channel == "to" then
				if typeof(value) == "Vector3" and value ~= to then
					to = value
					ensureShape()
					refresh()
				end
			elseif channel == "thickness" then
				if type(value) == "number" then
					thickness = value
					refresh()
				end
			elseif channel == "transparency" then
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
			newLocalCFrame: CFrame,
			worldCFrame: CFrame,
			frame: FrameContext
		)
			if not alive then
				return
			end
			world = worldCFrame
			if partMode then
				place(frame)
			elseif newLocalCFrame ~= localCFrame then
				localCFrame = newLocalCFrame
				refreshAttachments()
			end
		end

		controller.update = function(_self: ComponentInstance, time: number, frame: FrameContext)
			if not alive then
				return
			end
			localTime = time
			if ensureShape() then
				refresh()
			end
			place(frame)
		end

		function controller.onAction(_self: ComponentInstance, action: Types.ScheduledAction, frame: FrameContext)
			if not alive or action.action ~= "regenerate" then
				return
			end
			regenerateCount += 1
			ensureShape()
			refresh()
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
		local layout = layoutOf(props)
		local partMode = props.render == "part"
		local flickerRate = math.max(props.flickerRate, 0)
		-- Fraction of 60 Hz frames that draw a new shape (heuristic).
		local reshape = math.min(1, flickerRate / 60)
		local moving = Common.isMoving(component) or tracks.from ~= nil or tracks.to ~= nil
		local cost = Common.cost()
		local length = (props.to - props.from).Magnitude * component.scale
		local area = props.thickness
			* component.scale
			* length
			* (1 + layout.branches * props.branchLength * BRANCH_THICKNESS)
		if partMode then
			local n = layout.segments
			cost.instances = n
			cost.parts = n
			cost.movingParts = if moving or flickerRate > 0 then n else 0
			-- Heuristic: Size write per part per new shape, + one per tracked appearance channel.
			cost.propertyUpdates = n * reshape
				+ (if tracks.thickness then n else 0)
				+ (if tracks.transparency then n else 0)
				+ (if tracks.color then n else 0)
			local translucent = tracks.transparency ~= nil
				or (props.transparency > 0 and props.transparency < 1)
				or isSeeThrough(props.material)
			if translucent then
				cost.transparentLayers = n
				cost.overdrawWeight = area
			end
		else
			cost.instances = layout.attachments + layout.segments
			cost.attachments = layout.attachments
			cost.beams = layout.segments
			-- Heuristic: attachment CFrame writes per new shape or moved transform, + beam writes per track.
			local attachmentWrites = if moving then layout.attachments else layout.attachments * reshape
			cost.propertyUpdates = attachmentWrites
				+ (if tracks.thickness then 2 * layout.segments else 0)
				+ (if tracks.transparency then layout.segments else 0)
				+ (if tracks.color then layout.segments else 0)
			cost.transparentLayers = layout.segments
			cost.overdrawWeight = area
			cost.notes = { "Beam render does not show in ViewportFrames; viewport builds switch to part render." }
		end
		return cost
	end,
}

return descriptor
