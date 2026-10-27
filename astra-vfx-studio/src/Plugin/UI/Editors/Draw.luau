--!strict
--[[
	Draw — tiny vector drawing kit for the value editors (curves, wires, markers, grids) built from plain Frames.

		local Draw = require(script.Parent.Draw)
		local axis = Draw.line(canvas, Vector2.new(0, 40), Vector2.new(200, 40), 1, Theme.colors.border)
		Draw.setLine(axis, Vector2.new(0, 50), Vector2.new(200, 50))         -- move it (e.g. during a drag)
		local curve = Draw.polyline(canvas, points, 2, Theme.colors.accent)   -- container Frame "Polyline"
		Draw.setPolyline(curve, newPoints)                                    -- reuses the segment frames
		local knob = Draw.dot(canvas, Vector2.new(20, 20), 4, Theme.colors.keyframe, { stroke = Theme.colors.bg0 })
		Draw.setDot(knob, Vector2.new(30, 20))
		local grid = Draw.grid(canvas, 10, 4, { majorEvery = 5 })             -- scale-positioned, follows resizes
		local pts = Draw.bezier(p0, c0, c1, p1, 24)                           -- sample a cubic bezier (25 points)

	Coordinates are pixel offsets in the parent's local space (top-left origin, y down); `Draw.toPixel` /
	`Draw.fromPixel` map normalised [0, 1]² values (optionally with y up) to that space and back.

	A line is one Frame (AnchorPoint 0.5/0.5) placed at the segment midpoint, sized (length, thickness) and turned
	with `Rotation`. Polyline segments are lengthened by `thickness` (square caps) so joints show no gaps.
	All shapes are non-interactive (Active = false, Interactable = false): they never swallow clicks meant for
	handles below or above them. Colours default to Theme tokens.

	Path2D (engine 0.745: SetControlPoints with Path2DControlPoint.new(UDim2, ...), Thickness, Color3) was
	considered, but Path2DControlPoint cannot be constructed in Lune and Path2D is a GuiBase (no
	Rotation/Size/ZIndex layering like GuiObjects), so the editors draw with Frames everywhere; this works the same
	in Studio and in tests. Thousands of segments are fine for editor-sized curves (a 20-key sequence curve is
	usually drawn with 64..200 segments).
]]

local Theme = require(script.Parent.Parent.Theme)

local Draw = {}

export type Style = {
	name: string?, -- instance name (default "Line", "Polyline", "Dot", "Rect", "Grid")
	color: Color3?, -- fill colour (lines, dots, rects); polyline/line also take the positional colour
	transparency: number?, -- BackgroundTransparency (default 0)
	zIndex: number?,
	stroke: Color3?, -- dots/rects: outline colour (UIStroke)
	strokeThickness: number?, -- default 1
	hollow: boolean?, -- dots/rects: transparent fill, outline only (needs `stroke`, falls back to `color`)
	caps: boolean?, -- lines: lengthen by `thickness` (square caps). Polylines default true, single lines false.
}

export type GridStyle = {
	name: string?,
	color: Color3?, -- minor lines (default Theme.colors.gridMinor)
	majorColor: Color3?, -- every `majorEvery`-th line (default Theme.colors.gridMajor)
	majorEvery: number?, -- 0/nil: no major lines
	thickness: number?, -- default 1
	edges: boolean?, -- also draw the outer border lines (default false)
	zIndex: number?,
}

local DEFAULT_LINE = Theme.colors.accent
local DEFAULT_DOT = Theme.colors.accent

local function inert(gui: GuiObject)
	gui.Active = false
	gui.Selectable = false
	gui.Interactable = false
	gui.BorderSizePixel = 0
end

local function finite(v: Vector2): boolean
	return v.X == v.X and v.Y == v.Y and math.abs(v.X) ~= math.huge and math.abs(v.Y) ~= math.huge
end

-- Geometry of a segment frame: position (midpoint), size and rotation in degrees.
function Draw.segment(p0: Vector2, p1: Vector2, thickness: number, caps: boolean?): (UDim2, UDim2, number)
	if not finite(p0) or not finite(p1) then
		return UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), 0
	end
	local d = p1 - p0
	local length = d.Magnitude
	local mid = (p0 + p1) / 2
	local rotation = if length > 0 then math.deg(math.atan2(d.Y, d.X)) else 0
	local width = length + (if caps then thickness else 0)
	return UDim2.fromOffset(mid.X, mid.Y), UDim2.fromOffset(width, thickness), rotation
end

-- Repositions an existing line frame. Returns the frame.
function Draw.setLine(line: Frame, p0: Vector2, p1: Vector2, thickness: number?, caps: boolean?): Frame
	local t = thickness or line.Size.Y.Offset
	if t <= 0 then
		t = 1
	end
	local capped = if caps == nil then line:GetAttribute("AstraCaps") == true else caps
	local position, size, rotation = Draw.segment(p0, p1, t, capped)
	line.Position = position
	line.Size = size
	line.Rotation = rotation
	return line
end

-- A straight line from p0 to p1 (pixel offsets in `parent`). `parent` may be nil (parent it yourself).
function Draw.line(
	parent: Instance?,
	p0: Vector2,
	p1: Vector2,
	thickness: number?,
	color: Color3?,
	style: Style?
): Frame
	local s: Style = style or {}
	local frame = Instance.new("Frame")
	frame.Name = s.name or "Line"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = color or s.color or DEFAULT_LINE
	frame.BackgroundTransparency = s.transparency or 0
	if s.zIndex then
		frame.ZIndex = s.zIndex
	end
	inert(frame)
	if s.caps then
		frame:SetAttribute("AstraCaps", true)
	end
	Draw.setLine(frame, p0, p1, thickness or 1, s.caps == true)
	if parent then
		frame.Parent = parent
	end
	return frame
end

-- Segment frames of a polyline container, in drawing order.
local function segments(container: Instance): { Frame }
	local list: { Frame } = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") and child.Name == "Segment" then
			table.insert(list, child :: Frame)
		end
	end
	table.sort(list, function(a: Frame, b: Frame): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	return list
end

--[[
	Updates a polyline container to `points` (>= 2 points draw #points - 1 segments; fewer draw nothing). Existing
	segment frames are reused, missing ones created and extra ones destroyed, so redrawing during a drag does not
	churn instances. thickness/color default to the values the container was created with.
]]
function Draw.setPolyline(container: Frame, points: { Vector2 }, thickness: number?, color: Color3?): Frame
	local t = thickness or (container:GetAttribute("AstraThickness") :: number?) or 1
	local c = color or container.BackgroundColor3
	local transparency = (container:GetAttribute("AstraTransparency") :: number?) or 0
	local caps = container:GetAttribute("AstraCaps") ~= false
	container:SetAttribute("AstraThickness", t)
	container.BackgroundColor3 = c -- remembered for later updates (the container itself stays transparent)
	local existing = segments(container)
	local needed = math.max(0, #points - 1)
	for i = 1, needed do
		local seg = existing[i]
		if seg == nil then
			seg = Instance.new("Frame")
			seg.Name = "Segment"
			seg.AnchorPoint = Vector2.new(0.5, 0.5)
			seg.ZIndex = container.ZIndex
			inert(seg)
			seg.Parent = container
		end
		seg.LayoutOrder = i
		seg.BackgroundColor3 = c
		seg.BackgroundTransparency = transparency
		local position, size, rotation = Draw.segment(points[i], points[i + 1], t, caps)
		seg.Position = position
		seg.Size = size
		seg.Rotation = rotation
	end
	for i = needed + 1, #existing do
		existing[i]:Destroy()
	end
	return container
end

-- Connected line through `points`. Returns a transparent full-size container Frame named "Polyline" whose
-- children "Segment" are the line frames (so the points share the parent's coordinate space).
function Draw.polyline(
	parent: Instance?,
	points: { Vector2 },
	thickness: number?,
	color: Color3?,
	style: Style?
): Frame
	local s: Style = style or {}
	local container = Instance.new("Frame")
	container.Name = s.name or "Polyline"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	if s.zIndex then
		container.ZIndex = s.zIndex
	end
	inert(container)
	container:SetAttribute("AstraTransparency", s.transparency or 0)
	container:SetAttribute("AstraCaps", s.caps ~= false)
	Draw.setPolyline(container, points, thickness or 1, color or s.color or DEFAULT_LINE)
	if parent then
		container.Parent = parent
	end
	return container
end

-- Number of segment frames in a polyline container.
function Draw.segmentCount(container: Instance): number
	return #segments(container)
end

-- Moves (and optionally resizes) a dot.
function Draw.setDot(dot: Frame, center: Vector2, radius: number?): Frame
	local r = radius or dot.Size.X.Offset / 2
	dot.Position = UDim2.fromOffset(center.X, center.Y)
	dot.Size = UDim2.fromOffset(r * 2, r * 2)
	return dot
end

local function outline(gui: GuiObject, s: Style)
	local strokeColor = s.stroke or (if s.hollow then s.color else nil)
	if strokeColor then
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Outline"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = strokeColor
		stroke.Thickness = s.strokeThickness or 1
		stroke.Parent = gui
	end
end

-- Filled circle (or ring with style.hollow) centred on `center`.
function Draw.dot(parent: Instance?, center: Vector2, radius: number, color: Color3?, style: Style?): Frame
	local s: Style = style or {}
	local dot = Instance.new("Frame")
	dot.Name = s.name or "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = color or s.color or DEFAULT_DOT
	dot.BackgroundTransparency = if s.hollow then 1 else (s.transparency or 0)
	if s.zIndex then
		dot.ZIndex = s.zIndex
	end
	inert(dot)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot
	if s.hollow and s.stroke == nil then
		outline(dot, { stroke = color or s.color or DEFAULT_DOT, strokeThickness = s.strokeThickness })
	else
		outline(dot, s)
	end
	Draw.setDot(dot, center, radius)
	if parent then
		dot.Parent = parent
	end
	return dot
end

-- Axis-aligned rectangle spanning p0..p1 (any two opposite corners).
function Draw.setRect(rect: Frame, p0: Vector2, p1: Vector2): Frame
	local x0, x1 = math.min(p0.X, p1.X), math.max(p0.X, p1.X)
	local y0, y1 = math.min(p0.Y, p1.Y), math.max(p0.Y, p1.Y)
	rect.Position = UDim2.fromOffset(x0, y0)
	rect.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
	return rect
end

function Draw.rect(parent: Instance?, p0: Vector2, p1: Vector2, color: Color3?, style: Style?): Frame
	local s: Style = style or {}
	local rect = Instance.new("Frame")
	rect.Name = s.name or "Rect"
	rect.BackgroundColor3 = color or s.color or Theme.colors.selection
	rect.BackgroundTransparency = if s.hollow then 1 else (s.transparency or 0)
	if s.zIndex then
		rect.ZIndex = s.zIndex
	end
	inert(rect)
	outline(rect, s)
	Draw.setRect(rect, p0, p1)
	if parent then
		rect.Parent = parent
	end
	return rect
end

--[[
	Background grid with `columns` × `rows` cells. Lines are positioned by scale, so the grid follows the parent's
	size without redrawing. Returns a full-size container "Grid" with children "V<i>" / "H<i>" (i = 1 .. n-1, plus
	0 and n when style.edges is set). Every `majorEvery`-th line uses `majorColor`.
]]
function Draw.grid(parent: Instance?, columns: number, rows: number, style: GridStyle?): Frame
	local s: GridStyle = style or {}
	local cols = math.max(1, math.floor(columns))
	local rws = math.max(1, math.floor(rows))
	local thickness = s.thickness or 1
	local minor = s.color or Theme.colors.gridMinor
	local major = s.majorColor or Theme.colors.gridMajor
	local every = s.majorEvery or 0
	local container = Instance.new("Frame")
	container.Name = s.name or "Grid"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	if s.zIndex then
		container.ZIndex = s.zIndex
	end
	inert(container)
	local first = if s.edges then 0 else 1
	local function colour(i: number): Color3
		return if every > 0 and i % every == 0 then major else minor
	end
	for i = first, cols do
		if s.edges or i < cols then
			local v = Instance.new("Frame")
			v.Name = "V" .. i
			v.AnchorPoint = Vector2.new(if i == cols then 1 elseif i == 0 then 0 else 0.5, 0)
			v.Position = UDim2.fromScale(i / cols, 0)
			v.Size = UDim2.new(0, thickness, 1, 0)
			v.BackgroundColor3 = colour(i)
			inert(v)
			v.Parent = container
		end
	end
	for i = first, rws do
		if s.edges or i < rws then
			local h = Instance.new("Frame")
			h.Name = "H" .. i
			h.AnchorPoint = Vector2.new(0, if i == rws then 1 elseif i == 0 then 0 else 0.5)
			h.Position = UDim2.fromScale(0, i / rws)
			h.Size = UDim2.new(1, 0, 0, thickness)
			h.BackgroundColor3 = colour(i)
			inert(h)
			h.Parent = container
		end
	end
	if parent then
		container.Parent = parent
	end
	return container
end

-- Destroys every child of `container` (e.g. to redraw a canvas from scratch).
function Draw.clear(container: Instance)
	for _, child in container:GetChildren() do
		child:Destroy()
	end
end

-- Normalised point (0..1 on both axes) -> pixel offset inside a box of `size`. flipY: y = 0 at the bottom.
function Draw.toPixel(point: Vector2, size: Vector2, flipY: boolean?): Vector2
	local y = if flipY then 1 - point.Y else point.Y
	return Vector2.new(point.X * size.X, y * size.Y)
end

-- Inverse of toPixel (no clamping).
function Draw.fromPixel(pixel: Vector2, size: Vector2, flipY: boolean?): Vector2
	local x = if size.X ~= 0 then pixel.X / size.X else 0
	local y = if size.Y ~= 0 then pixel.Y / size.Y else 0
	return Vector2.new(x, if flipY then 1 - y else y)
end

-- `segmentCount` + 1 points on the cubic bezier p0 -> p3 with control points c0, c1 (both ends included).
function Draw.bezier(p0: Vector2, c0: Vector2, c1: Vector2, p3: Vector2, segmentCount: number?): { Vector2 }
	local n = math.max(1, math.floor(segmentCount or 24))
	local points: { Vector2 } = table.create(n + 1)
	for i = 0, n do
		local t = i / n
		local u = 1 - t
		points[i + 1] = p0 * (u * u * u) + c0 * (3 * u * u * t) + c1 * (3 * u * t * t) + p3 * (t * t * t)
	end
	return points
end

return Draw
