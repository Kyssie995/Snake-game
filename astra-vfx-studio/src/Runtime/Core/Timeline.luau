--!strict
--[[
	Timeline — component spans, the static action schedule and time helpers for the editor.
	See docs/MODULE_CONTRACTS.md §9.

	Interpretation notes (where the contract leaves room):
	* span(def, comp): the authored interval [startTime, startTime + duration) with the defaults startTime = 0 and
	  duration = def.duration - startTime, intersected with [0, def.duration]: start = clamp(startTime, 0, D),
	  end = clamp(startTime + duration, start, D). A negative duration gives an empty span (end == start).
	  NaN or non-number fields fall back to their defaults; an effect duration that is not a finite number >= 0
	  counts as 0.
	* isActive: start <= t < end (half-open, so an empty span is never active).
	* staticSchedule: one action per component event whose absolute time (startTime + event.time) lies inside the
	  component's span [startTime, endTime) — the same half-open rule as isActive, so an event at exactly endTime
	  is dropped — plus one { action = "fire", name = marker.event, source = "marker" } per marker with a
	  non-empty `event`. Events and markers whose time is not finite are dropped. Marker times are not clamped
	  (staticSchedule does not know the effect duration). Ordering: time, then component order, then event order
	  inside the component; at equal times marker actions come after component events, in marker order. After
	  sorting, `order` is the 1-based position in the returned list. Inputs are not mutated.
	* sort(actions): in place, stable (merge sort): time, then `order` (missing order = 0), then the current
	  position. NaN times sort last. Returns the same table for convenience.
	* range(actions, t0, t1, includeStart): `actions` must be sorted by time. Returns (first, last) indices of the
	  actions with t0 < time <= t1 (t0 <= time <= t1 when includeStart is true). The range is empty when
	  last < first (e.g. t1 < t0, a NaN bound or nothing due), so `for i = first, last do` just works.
	* snap(t, options): candidates are every finite target within `tolerance` of t and the nearest grid line
	  (round half up of t / grid; when 1 / grid is a whole number the result is computed as k / (1 / grid), so
	  grid = 0.1 yields 0.3 rather than 0.30000000000000004). The grid always applies (it is the editor's
	  quantisation); the tolerance only limits targets: nil = unlimited, an invalid value (negative, NaN, not a
	  number) = 0 (only exact matches). The nearest candidate wins; on equal distance targets win over the grid
	  and earlier targets over later ones. A grid that is not a finite number > 0 is ignored. Without candidates
	  (or for a non-finite t) t is returned unchanged.
	* format(t, maxDecimals?): seconds rounded half up to `maxDecimals` (default 3, clamped to 0..6) decimals with
	  trailing zeros removed and an "s" suffix: 1.25 -> "1.25s", 2 -> "2s", -0.5 -> "-0.5s", 1.0005 -> "1.001s".
	  NaN -> "NaN", +-inf -> "inf" / "-inf". Pure integer arithmetic, identical on every platform.
]]

local Types = require(script.Parent.Types)

type EffectDefinition = Types.EffectDefinition
type ComponentDef = Types.ComponentDef
type CompiledComponent = Types.CompiledComponent
type MarkerDef = Types.MarkerDef
type ScheduledAction = Types.ScheduledAction

export type SnapOptions = {
	grid: number?, -- grid step in seconds (e.g. 1 / 60 or 0.05)
	targets: { number }?, -- magnetic times (playhead, markers, keyframes, component edges ...)
	tolerance: number?, -- max distance for targets; nil = unlimited
}

local Timeline = {}

local INF = math.huge
local MAX_FORMAT_DECIMALS = 6

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function isNumber(x: any): boolean
	return type(x) == "number" and x == x
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Spans
-- ─────────────────────────────────────────────────────────────────────────────

-- Absolute [start, end) of a component, defaults applied and clamped to [0, def.duration].
function Timeline.span(def: EffectDefinition, comp: ComponentDef): (number, number)
	if type(def) ~= "table" then
		error("Timeline.span: effect definition must be a table, got " .. typeof(def), 2)
	end
	if type(comp) ~= "table" then
		error("Timeline.span: component definition must be a table, got " .. typeof(comp), 2)
	end
	local duration: any = def.duration
	local effectDuration: number = if isFinite(duration) and duration > 0 then duration else 0
	local rawStart: any = comp.startTime
	local start: number = if isNumber(rawStart) then rawStart else 0
	local rawDuration: any = comp.duration
	local finish: number = if isNumber(rawDuration) then start + rawDuration else effectDuration
	if finish ~= finish then
		finish = effectDuration -- inf - inf
	end
	local s = math.clamp(start, 0, effectDuration)
	local e = math.clamp(finish, s, effectDuration)
	if s == 0 then
		s = 0 -- -0 -> 0
	end
	if e == 0 then
		e = 0
	end
	return s, e
end

-- True while the component is active at absolute time t (start <= t < end).
function Timeline.isActive(c: CompiledComponent, t: number): boolean
	return t >= c.startTime and t < c.endTime
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Sorting
-- ─────────────────────────────────────────────────────────────────────────────

-- Strict "a comes before b" for (time, order); NaN times after every number. Equal keys return false (the merge
-- sort keeps them in their current order).
local function before(a: ScheduledAction, b: ScheduledAction): boolean
	local ta, tb = a.time, b.time
	local nanA, nanB = ta ~= ta, tb ~= tb
	if nanA ~= nanB then
		return nanB
	end
	if not nanA and ta ~= tb then
		return ta < tb
	end
	local oa: number = a.order or 0
	local ob: number = b.order or 0
	return oa < ob
end

-- Sorts actions in place by (time, order); stable for equal keys. Returns `actions`.
function Timeline.sort(actions: { ScheduledAction }): { ScheduledAction }
	local n = #actions
	if n < 2 then
		return actions
	end
	local sorted = true
	for i = 2, n do
		if before(actions[i], actions[i - 1]) then
			sorted = false
			break
		end
	end
	if sorted then
		return actions
	end
	-- Bottom-up merge sort (stable): runs of `width` from `src` are merged into `dst`.
	local src: { ScheduledAction } = table.clone(actions)
	local dst: { ScheduledAction } = table.create(n)
	local width = 1
	while width < n do
		local lo = 1
		while lo <= n do
			local mid = math.min(lo + width, n + 1)
			local hi = math.min(lo + 2 * width, n + 1)
			local i, j, k = lo, mid, lo
			while i < mid and j < hi do
				-- Take from the right run only when it is strictly before the left one.
				if before(src[j], src[i]) then
					dst[k] = src[j]
					j += 1
				else
					dst[k] = src[i]
					i += 1
				end
				k += 1
			end
			while i < mid do
				dst[k] = src[i]
				i += 1
				k += 1
			end
			while j < hi do
				dst[k] = src[j]
				j += 1
				k += 1
			end
			lo = hi
		end
		src, dst = dst, src
		width *= 2
	end
	for i = 1, n do
		actions[i] = src[i]
	end
	return actions
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Static schedule
-- ─────────────────────────────────────────────────────────────────────────────

-- Component events (absolute times, inside the span) + marker "fire" actions, sorted.
function Timeline.staticSchedule(components: { CompiledComponent }, markers: { MarkerDef }?): { ScheduledAction }
	local out: { ScheduledAction } = {}
	local sequence = 0
	local componentList: { CompiledComponent } = components or {}
	for _, c in componentList do
		local start, finish = c.startTime, c.endTime
		local events: { Types.CompiledEvent } = c.events or {}
		for _, ev in events do
			local relative: any = ev.time
			local t = if isFinite(relative) then start + relative else INF
			if isFinite(t) and t >= start and t < finish then
				sequence += 1
				local action: ScheduledAction = {
					time = t,
					action = ev.action,
					componentId = c.id,
					count = ev.count,
					name = ev.name,
					source = "event",
					sourceId = ev.id,
					order = sequence,
				}
				table.insert(out, action)
			end
		end
	end
	local markerList: { MarkerDef } = markers or {}
	for _, m in markerList do
		local event: any = m.event
		if type(event) == "string" and event ~= "" and isFinite(m.time) then
			sequence += 1
			local action: ScheduledAction = {
				time = m.time,
				action = "fire",
				name = event,
				source = "marker",
				sourceId = m.id,
				order = sequence,
			}
			table.insert(out, action)
		end
	end
	Timeline.sort(out)
	for i, action in out do
		action.order = i
	end
	return out
end

-- First index whose time is > t (or >= t when inclusive); #actions + 1 if none.
local function firstAfter(actions: { ScheduledAction }, t: number, inclusive: boolean): number
	local lo, hi = 1, #actions + 1
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		local mt = actions[mid].time
		local isAfter = if inclusive then mt >= t else mt > t
		if isAfter then
			hi = mid
		else
			lo = mid + 1
		end
	end
	return lo
end

-- Index range (first, last) of the sorted actions with t0 < time <= t1 (t0 <= time with includeStart).
function Timeline.range(actions: { ScheduledAction }, t0: number, t1: number, includeStart: boolean?): (number, number)
	if t0 ~= t0 or t1 ~= t1 then
		return 1, 0 -- NaN bound: nothing is due
	end
	local first = firstAfter(actions, t0, includeStart == true)
	local last = firstAfter(actions, t1, false) - 1
	return first, last
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Editor helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function gridPoint(t: number, grid: number): number
	local inverse = 1 / grid
	local whole = math.floor(inverse + 0.5)
	if whole >= 1 and math.abs(inverse - whole) <= 1e-9 * whole then
		return math.floor(t * whole + 0.5) / whole
	end
	return math.floor(t / grid + 0.5) * grid
end

-- Snaps t to the nearest grid line or target (targets only within tolerance).
function Timeline.snap(t: number, options: SnapOptions?): number
	if not isFinite(t) then
		return t
	end
	local o: SnapOptions = options or {}
	local tolerance: number = INF
	local rawTolerance: any = o.tolerance
	if rawTolerance ~= nil then
		tolerance = if isNumber(rawTolerance) and rawTolerance >= 0 then rawTolerance else 0
	end
	local best, bestDistance = t, INF
	local found = false
	local targets: any = o.targets
	if type(targets) == "table" then
		for _, target in targets do
			if isFinite(target) then
				local distance = math.abs(target - t)
				if distance <= tolerance and (not found or distance < bestDistance) then
					best, bestDistance, found = target, distance, true
				end
			end
		end
	end
	local grid: any = o.grid
	if isFinite(grid) and grid > 0 then
		local g = gridPoint(t, grid)
		local distance = math.abs(g - t)
		if not found or distance < bestDistance then
			best, found = g, true
		end
	end
	if best == 0 then
		best = 0 -- -0 -> 0
	end
	return best
end

-- Human-readable seconds, e.g. 1.25 -> "1.25s".
function Timeline.format(t: number, maxDecimals: number?): string
	if type(t) ~= "number" then
		error("Timeline.format: expected a number, got " .. typeof(t), 2)
	end
	if t ~= t then
		return "NaN"
	elseif t == INF then
		return "inf"
	elseif t == -INF then
		return "-inf"
	end
	local decimals = 3
	if maxDecimals ~= nil then
		if not isNumber(maxDecimals) then
			error("Timeline.format: maxDecimals must be a number, got " .. tostring(maxDecimals), 2)
		end
		decimals = math.clamp(math.floor(maxDecimals), 0, MAX_FORMAT_DECIMALS)
	end
	local scale = 10 ^ decimals
	local magnitude = math.abs(t)
	local sign = if t < 0 then "-" else ""
	-- The tiny bias makes decimal halves (1.0005, stored as 1.000499999...) round up as people expect.
	local units = math.floor(magnitude * scale + 0.5 + 1e-6)
	if units == 0 then
		return "0s"
	end
	if units >= 2 ^ 53 then
		return sign .. string.format("%.0f", magnitude) .. "s"
	end
	local whole = math.floor(units / scale)
	local fraction = units - whole * scale
	local text = string.format("%.0f", whole)
	if fraction > 0 then
		local digits = string.format("%0" .. decimals .. ".0f", fraction)
		text ..= "." .. (string.gsub(digits, "0+$", ""))
	end
	return sign .. text .. "s"
end

return Timeline
