--!strict
--[[
	Ops — document mutations behind the editor's transact() (docs/MODULE_CONTRACTS.md §20, PLUGIN_CONTRACTS §2).

	Every op mutates the definition it is given (callers pass a working copy, transact() deep-copies) and keeps a
	valid document valid:
	  * ids: every generated id is Ids.unique over ALL ids of the effect scope (components, tracks, events,
	    markers, graph nodes share one namespace, see Ids.collect); ids never change after creation.
	  * times: finite, clamped to >= 0 and rounded to microseconds (what Json keeps); component and effect
	    durations stay >= Ops.MIN_DURATION. Keyframe tracks, component events and markers stay sorted by time
	    (stable: equal times keep their order).
	  * limits: Constants.MAX_COMPONENTS / MAX_TRACKS_PER_COMPONENT / MAX_KEYFRAMES_PER_TRACK /
	    MAX_EVENTS_PER_COMPONENT / MAX_MARKERS / MAX_GRAPH_NODES are never exceeded (the op raises instead).
	  * values: property, channel and param values go through Codec.normalize (canonical JSON form, numeric
	    ranges clamped); structurally invalid values, "$key" colours missing from the palette, component
	    references to missing components or wrong types, invalid easings and names are rejected with error().
	  * hierarchy: parents exist, can parent, and never form a cycle; removing a component removes its subtree.
	  * graph: after every graph-affecting op, Ops.repairGraph removes links and resets params that
	    Graph.validate reports as errors (e.g. links from a variadic output beyond a lowered count, a Tween
	    channel that the new target type does not have, a value whose kind no longer matches the channel).
	Unknown ids (components, tracks, keyframe indices, events, markers, nodes) and malformed arguments are
	programmer errors: error("Ops.<op>: ...", 0) without a position prefix, so the editor can show the message.
	An op that raises may have changed the document partially — transact() discards the working copy.

	Optional containers are kept minimal: defaults stay implicit (addComponent writes only the properties it is
	given), and `properties`, `tracks`, `events`, `transform`, `params`, `markers`, `tags`, `palette` and an
	empty `graph` are removed instead of being left empty.

	API (contract §20 plus documented extensions marked +):
	  Ops.newEffect(name, { duration?, id? }?) -> EffectDefinition       schemaVersion current, slug id, 2 s, no components
	  Ops.clone(doc) ; Ops.find(doc, id) -> (ComponentDef?, index?)
	  Ops.children(doc, id?) -> { ComponentDef }       roots when id is nil (components without an existing parent)
	  Ops.descendants(doc, id) -> { ComponentDef }     pre-order, children in document order
	  Ops.addComponent(doc, type, { name?, parent?, startTime?, duration?, properties?, index? }?) -> id
	      name defaults to the type's displayName; startTime defaults to 0 and duration to the rest of the
	      effect (effect duration - startTime); both are always written. index = position in doc.components.
	  Ops.removeComponents(doc, ids, { keepComponentNodes? }?) -> { nodeId }
	      removes the subtrees; component references in component properties become ""; graph: Component nodes
	      that referenced a removed component are removed with their links (keepComponentNodes = true keeps them
	      with component = "" instead), other componentRef params (action targets) become "" (Validation warns).
	      Returns the ids of the graph nodes that were changed or removed, in graph order.
	  Ops.duplicateComponents(doc, ids) -> { id }      one copy per selected subtree (descendants of selected
	      components are copied with their ancestor once), inserted after the original subtree; fresh ids for
	      components, tracks and events; parent links and componentRef properties inside the subtree are
	      remapped; the copy root keeps the original parent and gets the name suffix " Copy". Returns the new
	      root ids in selection order.
	  Ops.renameComponent(doc, id, name) ; Ops.setEnabled(doc, ids, enabled) ; Ops.setParent(doc, id, parentId?)
	  Ops.moveComponent(doc, id, newIndex) ; Ops.setTiming(doc, id, startTime?, duration?)
	+ Ops.setComponentField(doc, ids, field, value?)   phase | minQuality | notes (nil removes the field)
	  Ops.setTransform(doc, id, "position"|"rotation"|"scale", value?)    nil removes the field
	  Ops.setProperty(doc, ids, name, jsonValue) ; Ops.resetProperty(doc, ids, name)
	  Ops.addKeyframe(doc, id, channel, time, value, easing?) -> { trackId, index }
	      adds to the component's track of that channel (the first enabled one, else the first one, else a new
	      track); a keyframe at exactly the same time is replaced (value, and easing when given).
	  Ops.removeKeyframes(doc, refs)                   a track without keyframes is removed
	  Ops.moveKeyframes(doc, refs, dt) -> refs         times clamp at 0; tracks re-sorted; refs in input order
	  Ops.setKeyframe(doc, ref, { time?, value?, easing? }) -> ref
	  Ops.addEvent(doc, id, action, time, { count?, name? }?) -> eventId   count defaults to 16 for "emit"-like
	      actions, name to "Event" for "fire"; fields the action ignores are not written.
	  Ops.removeEvents(doc, eventRefs) ; Ops.moveEvent(doc, eventRef, time)
	+ Ops.setEvent(doc, eventRef, { time?, count?, name? })
	  Ops.addMarker(doc, time, label, { phase?, event?, color? }?) -> markerId
	  Ops.removeMarker(doc, id) -> { nodeId }          OnMarker params referencing it become ""
	  Ops.setMarker(doc, id, { time?, label?, phase?, event?, color? })   Json.NULL removes phase/event/color
	  Ops.setEffectField(doc, field, value?)           name, description, duration, loop, seed, timeScale, palette,
	                                                   tags; nil (or Json.NULL) removes optional fields. A palette
	                                                   that drops a key still referenced by "$key" is rejected.
	  Ops.addNode(doc, type, position?, params?) -> nodeId          (+ params)
	  Ops.removeNodes(doc, ids) ; Ops.moveNodes(doc, ids, delta [dx, dy])
	  Ops.setNodeParam(doc, id, name, value?) -> { nodeId }         nil resets; returns nodes changed by repair
	  Ops.connect(doc, from, to, { replace? }?) -> (ok, reason?, code?)    Graph.canConnect decides; with
	      replace = true an occupied data input / exec output is freed first. Unknown nodes raise.
	  Ops.disconnect(doc, from?, to) -> number         removes links into `to` (from `from` when given)
	+ Ops.repairGraph(doc) -> { nodeId }
	  Ops.copyComponents(doc, ids) -> ClipboardPayload ; Ops.pasteComponents(doc, payload, parent?, { atTime? }?)
	  Ops.copyKeyframes(doc, refs) -> ClipboardPayload ; Ops.pasteKeyframes(doc, payload, atTime, targetId?)

	Clipboard payloads are plain JSON-serialisable tables (they survive Json.encode/decode) with RELATIVE times:
	  components: { kind = "components", version = 1, origin, roots, components, palette?, source? }
	      component startTimes are relative to `origin` (the earliest copied startTime); copy roots have no
	      parent. pasteComponents places them at origin (or options.atTime) + relative time, under `parent`
	      (or at the root), with fresh ids; names are kept. Returns the new root ids.
	  keyframes:  { kind = "keyframes", version = 1, origin, tracks = { { component, channel, kind,
	      keyframes } }, palette?, source? }
	      key times are relative to `origin` (the earliest copied key in ABSOLUTE effect time, i.e. component
	      startTime + key time). pasteKeyframes(atTime) takes an absolute effect time (the playhead): every key
	      lands at atTime + relative time, converted to the target component's local time (clamped at 0).
	      Without targetId keys go back to their source components (which must exist); with targetId every
	      track goes to that component (tracks whose channel it lacks are skipped; none matching raises).
	      Returns the refs of the pasted keys.
	  `palette` carries the colours of every "$key" the payload references; pasting into a document that lacks
	  a key adds it to that document's palette (an existing key keeps the document's colour).

	KeyframeRef = { component, track, index } (track id, 1-based index into the sorted keyframes);
	EventRef = { component, event } (event id). Both are exported types of this module.
]]

local Codec = require(script.Parent.Parent.AstraVFX.Core.Codec)
local Components = require(script.Parent.Parent.AstraVFX.Core.Components)
local Constants = require(script.Parent.Parent.AstraVFX.Core.Constants)
local Easing = require(script.Parent.Parent.AstraVFX.Core.Easing)
local Graph = require(script.Parent.Parent.AstraVFX.Core.Graph)
local Json = require(script.Parent.Parent.AstraVFX.Core.Json)
local Types = require(script.Parent.Parent.AstraVFX.Core.Types)
local Ids = require(script.Parent.Ids)

type EffectDefinition = Types.EffectDefinition
type ComponentDef = Types.ComponentDef
type EasingDef = Types.EasingDef
type PropertySpec = Types.PropertySpec
type ChannelSpec = Types.ChannelSpec
type ComponentDescriptor = Types.ComponentDescriptor

export type KeyframeRef = { component: string, track: string, index: number }
export type EventRef = { component: string, event: string }
export type ClipboardTrack = { component: string, channel: string, kind: string, keyframes: { any } }
export type ClipboardPayload = {
	kind: string, -- "components" | "keyframes"
	version: number,
	origin: number,
	source: string?,
	palette: { [string]: string }?,
	roots: { string }?, -- components
	components: { ComponentDef }?, -- components
	tracks: { ClipboardTrack }?, -- keyframes
}
export type AddComponentOptions = {
	name: string?,
	parent: string?,
	startTime: number?,
	duration: number?,
	properties: { [string]: any }?,
	index: number?,
}
export type KeyframeFields = { time: number?, value: any?, easing: EasingDef? }

local Ops = {}

Ops.MIN_DURATION = 0.01 -- shortest component / effect duration ops write (seconds)
Ops.MIN_TIME_SCALE = 0.01
Ops.DEFAULT_DURATION = 2 -- newEffect
Ops.DEFAULT_EMIT_COUNT = 16 -- addEvent for actions that use a count (the particles "emit" default)
Ops.DEFAULT_EVENT_NAME = "Event" -- addEvent "fire"
Ops.CLIPBOARD_VERSION = 1
Ops.COPY_SUFFIX = " Copy"

local NULL: any = Json.NULL
local INF = math.huge
local MAX_SAFE_INTEGER = 2 ^ 53
local MAX_REPAIR_PASSES = 16

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function fail(fn: string, message: string): never
	error("Ops." .. fn .. ": " .. message, 0)
end

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function isNone(v: any): boolean
	return v == nil or rawequal(v, NULL)
end

local function quote(s: any): string
	return '"' .. tostring(s) .. '"'
end

local function describe(v: any): string
	if v == nil then
		return "nil"
	elseif rawequal(v, NULL) then
		return "null"
	elseif type(v) == "string" then
		return if #v > 40 then quote(string.sub(v, 1, 37) .. "...") else quote(v)
	elseif type(v) == "number" or type(v) == "boolean" then
		return tostring(v)
	end
	return "a " .. typeof(v)
end

-- Error text without the "file:line: " prefix error() adds.
local function cleanError(err: any): string
	local text = tostring(err)
	return (string.gsub(text, "^[^\n]-:%d+: ", ""))
end

-- Deep copy; tables with a metatable (Json.NULL / Json.EMPTY_OBJECT sentinels) are kept by identity.
local function deepCopy(v: any): any
	if type(v) ~= "table" or getmetatable(v) ~= nil then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[deepCopy(k)] = deepCopy(x)
	end
	return out
end

local function isPlainTable(v: any): boolean
	return type(v) == "table" and getmetatable(v) == nil and not table.isfrozen(v)
end

-- parent[key] as a mutable plain table (sentinels such as Json.EMPTY_OBJECT and missing values are replaced).
local function writable(parent: any, key: string): any
	local v = parent[key]
	if isPlainTable(v) then
		return v
	end
	local t = {}
	if type(v) == "table" and getmetatable(v) == nil then
		for k, x in pairs(v) do
			t[k] = x
		end
	end
	parent[key] = t
	return t
end

-- Removes parent[key] when it is an empty table.
local function dropIfEmpty(parent: any, key: string)
	local v = parent[key]
	if type(v) == "table" and next(v) == nil then
		parent[key] = nil
	end
end

local function list(v: any): { any }
	return if type(v) == "table" then v else {}
end

local function roundTime(t: number): number
	local r = math.floor(t * 1e6 + 0.5) / 1e6
	return if r == 0 then 0 else r
end

-- Finite seconds, clamped to >= 0, rounded to microseconds.
local function checkTime(fn: string, t: any, what: string): number
	if not isFinite(t) then
		fail(fn, what .. " must be a finite number of seconds, got " .. describe(t))
	end
	return roundTime(math.max(0, t))
end

local function checkDuration(fn: string, d: any, what: string, max: number?): number
	if not isFinite(d) then
		fail(fn, what .. " must be a finite number of seconds, got " .. describe(d))
	end
	local v = math.max(Ops.MIN_DURATION, roundTime(d))
	if max then
		v = math.min(v, max)
	end
	return v
end

local function truncateUtf8(s: string, maxChars: number): string
	local length = utf8.len(s)
	if length == nil or length <= maxChars then
		return s
	end
	local stop = utf8.offset(s, maxChars + 1)
	return if stop then string.sub(s, 1, stop - 1) else s
end

-- A display name / label: valid UTF-8, not blank, at most NAME_MAX_LENGTH characters (longer names are cut).
local function checkName(fn: string, name: any, what: string): string
	if type(name) ~= "string" then
		fail(fn, what .. " must be a string, got " .. describe(name))
	end
	if utf8.len(name) == nil then
		fail(fn, what .. " must be valid UTF-8")
	end
	local cut = truncateUtf8(name, Constants.NAME_MAX_LENGTH)
	if string.match(cut, "^%s*$") then
		fail(fn, what .. " must not be empty")
	end
	return cut
end

local function isEventName(v: any): boolean
	return type(v) == "string"
		and #v >= 1
		and #v <= Constants.ID_MAX_LENGTH
		and string.match(v, Constants.EVENT_NAME_PATTERN) ~= nil
end

local function checkIdList(fn: string, ids: any, what: string): { string }
	if type(ids) ~= "table" then
		fail(fn, what .. " must be an array of ids, got " .. describe(ids))
	end
	local out: { string } = {}
	for i, id in ipairs(ids) do
		if type(id) ~= "string" then
			fail(fn, what .. "[" .. i .. "] must be an id string, got " .. describe(id))
		end
		table.insert(out, id)
	end
	return out
end

local function timeOf(v: any): number
	local t = if type(v) == "table" then v.time else nil
	return if isFinite(t) then t else 0
end

-- Stable in-place sort by `.time` (equal times keep their order).
local function sortByTime(entries: { any })
	local n = #entries
	local sorted = true
	for i = 2, n do
		if timeOf(entries[i]) < timeOf(entries[i - 1]) then
			sorted = false
			break
		end
	end
	if sorted then
		return
	end
	local decorated = table.create(n)
	for i, v in ipairs(entries) do
		decorated[i] = { v = v, i = i, t = timeOf(v) }
	end
	table.sort(decorated, function(a: any, b: any): boolean
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.i < b.i
	end)
	for i, d in ipairs(decorated) do
		entries[i] = d.v
	end
end

-- Inserts `entry` after every entry whose time is <= its time (keeps a sorted list sorted).
local function insertSorted(entries: { any }, entry: any)
	local t = timeOf(entry)
	local at = #entries + 1
	for i = #entries, 1, -1 do
		if timeOf(entries[i]) <= t then
			break
		end
		at = i
	end
	table.insert(entries, at, entry)
end

local function effectDuration(doc: any): number
	local d = doc.duration
	return if isFinite(d) and d > 0 then d else Ops.DEFAULT_DURATION
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Value checks
-- ─────────────────────────────────────────────────────────────────────────────

local function hasPaletteKey(doc: any, key: string): boolean
	local palette = doc.palette
	return type(palette) == "table" and type(rawget(palette, key)) == "string"
end

local function checkPaletteRefs(fn: string, doc: any, kind: string, value: any, what: string)
	for _, key in Codec.paletteRefs(kind, value) do
		if not hasPaletteKey(doc, key) then
			fail(fn, what .. ': palette colour "$' .. key .. '" does not exist')
		end
	end
end

-- Canonical JSON form (Codec.normalize clamps ranges, raises on structural problems).
local function canonical(fn: string, kind: string, value: any, spec: any, what: string): any
	if isNone(value) then
		fail(fn, what .. " needs a value")
	end
	local ok, result = pcall(Codec.normalize :: any, kind, value, spec)
	if not ok then
		fail(fn, what .. ": " .. cleanError(result))
	end
	return deepCopy(result)
end

local function findComponent(doc: any, id: any): (any, number?)
	if type(id) ~= "string" then
		return nil, nil
	end
	for i, component in ipairs(list(doc.components)) do
		if type(component) == "table" and component.id == id then
			return component, i
		end
	end
	return nil, nil
end

local function checkComponentRef(fn: string, doc: any, value: string, allowed: { string }?, what: string)
	if value == "" then
		return
	end
	local target = findComponent(doc, value)
	if target == nil then
		fail(fn, what .. ": component " .. quote(value) .. " does not exist")
	end
	if allowed and not table.find(allowed, target.type) then
		fail(
			fn,
			what
				.. ": component "
				.. quote(value)
				.. " is a "
				.. tostring(target.type)
				.. ", expected "
				.. table.concat(allowed, " or ")
		)
	end
end

local function easingValue(fn: string, easing: any, what: string): EasingDef?
	if isNone(easing) then
		return nil
	end
	local ok, problem = Easing.check(easing)
	if not ok then
		fail(fn, what .. ": " .. tostring(problem))
	end
	local normalized = Easing.normalize(easing)
	if normalized == "Linear" then
		return nil
	end
	return deepCopy(normalized)
end

local function propertyValue(fn: string, doc: any, spec: PropertySpec, value: any, what: string): any
	local v = canonical(fn, spec.kind, value, spec, what)
	if spec.kind == "color3" or spec.kind == "colorSequence" then
		checkPaletteRefs(fn, doc, spec.kind, v, what)
	elseif spec.kind == "componentRef" then
		checkComponentRef(fn, doc, v, spec.componentTypes, what)
	elseif spec.kind == "string" and string.match(spec.name, "Easing$") then
		local ok, problem = Easing.check(v)
		if not ok then
			fail(fn, what .. ": " .. tostring(problem))
		end
		v = Easing.normalize(v)
	end
	return v
end

local function channelValue(fn: string, doc: any, spec: ChannelSpec, value: any, what: string): any
	local v = canonical(fn, spec.kind, value, spec, what)
	if spec.kind == "color3" then
		checkPaletteRefs(fn, doc, "color3", v, what)
	end
	return v
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Components
-- ─────────────────────────────────────────────────────────────────────────────

local function descriptorOf(fn: string, component: any): ComponentDescriptor
	local descriptor = if type(component.type) == "string" then Components.get(component.type) else nil
	if descriptor == nil then
		fail(fn, "component " .. quote(component.id) .. " has an unknown type " .. describe(component.type))
	end
	return descriptor :: ComponentDescriptor
end

local function getComponent(fn: string, doc: any, id: any): (any, number, ComponentDescriptor)
	local component, index = findComponent(doc, id)
	if component == nil or index == nil then
		fail(fn, "unknown component id " .. describe(id))
	end
	return component, index :: number, descriptorOf(fn, component)
end

-- parent id -> children (document order). Components whose parent does not exist count as roots ("").
local function childMap(doc: any): { [string]: { any } }
	local exists: { [string]: boolean } = {}
	for _, c in ipairs(list(doc.components)) do
		if type(c) == "table" and type(c.id) == "string" then
			exists[c.id] = true
		end
	end
	local map: { [string]: { any } } = {}
	for _, c in ipairs(list(doc.components)) do
		if type(c) == "table" then
			local parent = if type(c.parent) == "string" and exists[c.parent] and c.parent ~= c.id then c.parent else ""
			local children = map[parent]
			if children == nil then
				children = {}
				map[parent] = children
			end
			table.insert(children, c)
		end
	end
	return map
end

local function collectDescendants(map: { [string]: { any } }, id: string, out: { any }, seen: { [string]: boolean })
	local children = map[id]
	if children == nil then
		return
	end
	for _, child in children do
		if not seen[child.id] then
			seen[child.id] = true
			table.insert(out, child)
			collectDescendants(map, child.id, out, seen)
		end
	end
end

local function descendantsOf(doc: any, id: string): { any }
	local out = {}
	collectDescendants(childMap(doc), id, out, { [id] = true })
	return out
end

-- True when `id` is `ancestorId` or lies below it.
local function isInSubtree(doc: any, id: string, ancestorId: string): boolean
	local seen: { [string]: boolean } = {}
	local current: any = findComponent(doc, id)
	while current and not seen[current.id] do
		if current.id == ancestorId then
			return true
		end
		seen[current.id] = true
		current = if type(current.parent) == "string" then findComponent(doc, current.parent) else nil
	end
	return false
end

-- Validated, de-duplicated ids whose ancestors are not selected too (selection order kept).
local function selectionRoots(fn: string, doc: any, ids: any): { string }
	local requested = checkIdList(fn, ids, "ids")
	local selected: { [string]: boolean } = {}
	for _, id in requested do
		getComponent(fn, doc, id)
		selected[id] = true
	end
	local roots: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, id in requested do
		if seen[id] then
			continue
		end
		seen[id] = true
		local covered = false
		local visited: { [string]: boolean } = { [id] = true }
		local component: any = findComponent(doc, id)
		local parentId = component.parent
		while type(parentId) == "string" and not visited[parentId] do
			visited[parentId] = true
			if selected[parentId] then
				covered = true
				break
			end
			local parent: any = findComponent(doc, parentId)
			parentId = if parent then parent.parent else nil
		end
		if not covered then
			table.insert(roots, id)
		end
	end
	return roots
end

-- Root ids + all their descendants as a set.
local function subtreeSet(doc: any, roots: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	local map = childMap(doc)
	for _, id in roots do
		set[id] = true
		local out = {}
		collectDescendants(map, id, out, { [id] = true })
		for _, c in out do
			set[c.id] = true
		end
	end
	return set
end

local function checkComponentLimit(fn: string, doc: any, adding: number)
	local count = #list(doc.components)
	if count + adding > Constants.MAX_COMPONENTS then
		fail(
			fn,
			"an effect can have at most "
				.. Constants.MAX_COMPONENTS
				.. " components ("
				.. count
				.. " + "
				.. adding
				.. ")"
		)
	end
end

-- Gives every track and event of a (copied) component a fresh id.
local function freshChildIds(component: any, taken: { [string]: boolean })
	for _, track in ipairs(list(component.tracks)) do
		if type(track) == "table" then
			track.id = Ids.unique(if Ids.isValid(track.id) then track.id else "track", taken)
		end
	end
	for _, event in ipairs(list(component.events)) do
		if type(event) == "table" then
			event.id = Ids.unique(if Ids.isValid(event.id) then event.id else "event", taken)
		end
	end
end

-- Calls fn(holder, key, value, spec) for every componentRef property value (properties + qualityOverrides).
local function eachComponentRef(component: any, fn: (holder: any, key: string, value: any, spec: PropertySpec) -> ())
	local typeName = component.type
	if type(typeName) ~= "string" or Components.get(typeName) == nil then
		return
	end
	local function visit(holder: any)
		if type(holder) ~= "table" then
			return
		end
		for key, value in pairs(holder) do
			if type(key) == "string" then
				local spec = Components.propertySpec(typeName, key)
				if spec and spec.kind == "componentRef" then
					fn(holder, key, value, spec)
				end
			end
		end
	end
	visit(component.properties)
	if type(component.qualityOverrides) == "table" then
		for _, override in pairs(component.qualityOverrides) do
			visit(override)
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Palette references
-- ─────────────────────────────────────────────────────────────────────────────

local function addRefs(out: { [string]: boolean }, kind: string, value: any)
	for _, key in Codec.paletteRefs(kind, value) do
		out[key] = true
	end
end

local function componentPaletteRefs(component: any, out: { [string]: boolean })
	local typeName = component.type
	if type(typeName) ~= "string" or Components.get(typeName) == nil then
		return
	end
	local function visit(holder: any)
		if type(holder) ~= "table" then
			return
		end
		for key, value in pairs(holder) do
			local spec = if type(key) == "string" then Components.propertySpec(typeName, key) else nil
			if spec and (spec.kind == "color3" or spec.kind == "colorSequence") then
				addRefs(out, spec.kind, value)
			end
		end
	end
	visit(component.properties)
	if type(component.qualityOverrides) == "table" then
		for _, override in pairs(component.qualityOverrides) do
			visit(override)
		end
	end
	for _, track in ipairs(list(component.tracks)) do
		local channel = if type(track) == "table" and type(track.channel) == "string"
			then Components.channelSpec(typeName, track.channel)
			else nil
		if channel and channel.kind == "color3" then
			for _, key in ipairs(list(track.keyframes)) do
				if type(key) == "table" then
					addRefs(out, "color3", key.value)
				end
			end
		end
	end
end

-- Every palette key referenced anywhere in the document ("$key" strings in graph params count conservatively).
local function paletteUses(doc: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, component in ipairs(list(doc.components)) do
		if type(component) == "table" then
			componentPaletteRefs(component, out)
		end
	end
	for _, marker in ipairs(list(doc.markers)) do
		if type(marker) == "table" then
			addRefs(out, "color3", marker.color)
		end
	end
	if type(doc.graph) == "table" then
		for _, node in ipairs(list(doc.graph.nodes)) do
			if type(node) == "table" and type(node.params) == "table" then
				for _, value in pairs(node.params) do
					addRefs(out, "color3", value)
				end
			end
		end
	end
	return out
end

-- Palette entries (key -> colour) of `doc` for the keys in `refs` (nil when there are none).
local function paletteSubset(doc: any, refs: { [string]: boolean }): { [string]: string }?
	local out: { [string]: string } = {}
	local any = false
	for key in pairs(refs) do
		if hasPaletteKey(doc, key) then
			out[key] = doc.palette[key]
			any = true
		end
	end
	return if any then out else nil
end

-- Makes every key of `refs` resolve in `doc`: missing keys are added from the payload palette.
local function mergePalette(fn: string, doc: any, refs: { [string]: boolean }, source: any)
	local keys: { string } = {}
	for key in pairs(refs) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		if not hasPaletteKey(doc, key) then
			local colour = if type(source) == "table" then rawget(source, key) else nil
			if not Ids.isValid(key) or colour == nil then
				fail(fn, 'palette colour "$' .. key .. '" is neither in the document nor in the clipboard')
			end
			if type(colour) == "string" and string.sub(colour, 1, 1) == "$" then
				fail(fn, 'clipboard palette colour "$' .. key .. '" must be a colour')
			end
			local hex = canonical(fn, "color3", colour, nil, 'clipboard palette colour "$' .. key .. '"')
			writable(doc, "palette")[key] = hex
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Graph helpers
-- ─────────────────────────────────────────────────────────────────────────────

local NodeTypes = Graph.NodeTypes

local function graphOf(doc: any): any?
	local graph = doc.graph
	return if type(graph) == "table" then graph else nil
end

local function ensureGraph(doc: any): any
	local graph = writable(doc, "graph")
	writable(graph, "nodes")
	writable(graph, "links")
	return graph
end

local function getNode(fn: string, doc: any, id: any): (any, any, number, any)
	local graph = graphOf(doc)
	if graph then
		for i, node in ipairs(list(graph.nodes)) do
			if type(node) == "table" and node.id == id then
				local nodeType = NodeTypes.get(node.type)
				if nodeType == nil then
					fail(fn, "node " .. quote(id) .. " has an unknown type " .. describe(node.type))
				end
				return graph, node, i, nodeType
			end
		end
	end
	return fail(fn, "unknown node id " .. describe(id))
end

local function nodeById(graph: any, id: string): any?
	for _, node in ipairs(list(graph.nodes)) do
		if type(node) == "table" and node.id == id then
			return node
		end
	end
	return nil
end

-- Statically known target component id of a node's component pin / param (linked Component node first).
local function staticTarget(graph: any, node: any, pin: string): string?
	local key = tostring(node.id) .. "." .. pin
	for _, link in ipairs(list(graph.links)) do
		if type(link) == "table" and link.to == key then
			local fromNode, fromPin = Graph.parseRef(link.from)
			local source = if fromNode then nodeById(graph, fromNode) else nil
			if source and source.type == "Component" and fromPin == "component" then
				local id = if type(source.params) == "table" then source.params.component else nil
				return if type(id) == "string" then id else nil
			end
			return nil
		end
	end
	local id = if type(node.params) == "table" then node.params[pin] else nil
	return if type(id) == "string" then id else nil
end

local function componentType(doc: any, id: string?): string?
	if id == nil or id == "" then
		return nil
	end
	local component = findComponent(doc, id)
	return if component and type(component.type) == "string" then component.type else nil
end

-- Canonical value of a node param (raises on invalid values).
local function nodeParamValue(
	fn: string,
	doc: any,
	graph: any,
	node: any,
	nodeType: any,
	spec: PropertySpec,
	value: any
): any
	local name = spec.name
	local what = "param " .. name .. " of node " .. quote(node.id)
	local special = nodeType.special[name]
	if special == "easing" then
		local ok, problem = Easing.check(value)
		if not ok then
			fail(fn, what .. ": " .. tostring(problem))
		end
		return deepCopy(Easing.normalize(value))
	elseif special == "channelValue" then
		local targetType = componentType(doc, staticTarget(graph, node, "target"))
		local channelName = if type(node.params) == "table" then node.params.channel else nil
		local channel = if targetType and type(channelName) == "string"
			then Components.channelSpec(targetType, channelName)
			else nil
		if channel then
			return channelValue(fn, doc, channel, value, what)
		end
		-- No resolvable channel: any channel kind is accepted (number, boolean, colour, [x, y, z]).
		local kind = if type(value) == "boolean"
			then "boolean"
			elseif type(value) == "number" then "number"
			elseif type(value) == "string" then "color3"
			else "vector3"
		local v = canonical(fn, kind, value, nil, what)
		if kind == "color3" then
			checkPaletteRefs(fn, doc, "color3", v, what)
		end
		return v
	end
	local v = canonical(fn, spec.kind, value, spec, what)
	if special == "channel" then
		local targetType = componentType(doc, staticTarget(graph, node, "target"))
		if v ~= "" and targetType and Components.get(targetType) and Components.channelSpec(targetType, v) == nil then
			fail(fn, what .. ": component type " .. targetType .. " has no channel " .. quote(v))
		end
	elseif special == "marker" then
		if v ~= "" then
			local found = false
			for _, marker in ipairs(list(doc.markers)) do
				if type(marker) == "table" and marker.id == v then
					found = true
					break
				end
			end
			if not found then
				fail(fn, what .. ": marker " .. quote(v) .. " does not exist")
			end
		end
	elseif special == "eventName" then
		if v ~= "" and not isEventName(v) then
			fail(fn, what .. ": " .. describe(v) .. " is not a valid event name")
		end
	elseif spec.kind == "componentRef" then
		checkComponentRef(fn, doc, v, spec.componentTypes, what)
	elseif spec.kind == "color3" then
		checkPaletteRefs(fn, doc, "color3", v, what)
	end
	return v
end

-- Param order for setting several params at once: the target first, the channel next, the value last.
local PARAM_PRIORITY: { [string]: number } = { target = 1, component = 1, channel = 2, value = 4 }

local function sortedParamNames(params: { [string]: any }): { string }
	local names: { string } = {}
	for name in pairs(params) do
		if type(name) == "string" then
			table.insert(names, name)
		end
	end
	table.sort(names, function(a: string, b: string): boolean
		local pa, pb = PARAM_PRIORITY[a] or 3, PARAM_PRIORITY[b] or 3
		if pa ~= pb then
			return pa < pb
		end
		return a < b
	end)
	return names
end

local function nodeIdsInOrder(graph: any, set: { [string]: boolean }, extra: { string }?): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, node in ipairs(list(graph and graph.nodes)) do
		if type(node) == "table" and set[node.id] and not seen[node.id] then
			seen[node.id] = true
			table.insert(out, node.id)
		end
	end
	for _, id in (extra or {}) :: { string } do
		if set[id] and not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	return out
end

local REPAIRABLE_PARAM: { [string]: boolean } = {
	["graph.param_type"] = true,
	["graph.param_range"] = true,
	["graph.param_ref"] = true,
	["graph.component_missing"] = true,
	["graph.component_type"] = true,
	["graph.marker_missing"] = true,
	["graph.event_name"] = true,
	["graph.channel_unknown"] = true,
}

-- Removes links and resets params that Graph.validate reports as errors; returns the affected node ids.
function Ops.repairGraph(doc: EffectDefinition): { string }
	local d: any = doc
	local graph = graphOf(d)
	if graph == nil then
		return {}
	end
	local affected: { [string]: boolean } = {}
	for _ = 1, MAX_REPAIR_PASSES do
		local diagnostics = Graph.validate(graph, d)
		local nodes = list(graph.nodes)
		local links = list(graph.links)
		local resets: { { node: any, name: string } } = {}
		local dropLinks: { [number]: boolean } = {}
		for _, diagnostic in diagnostics do
			if diagnostic.severity ~= "error" then
				continue
			end
			local linkIndex = string.match(diagnostic.path, "^graph%.links%[(%d+)%]")
			if linkIndex then
				dropLinks[tonumber(linkIndex) :: number] = true
				continue
			end
			local nodeIndex, param = string.match(diagnostic.path, "^graph%.nodes%[(%d+)%]%.params%.([%w_]+)$")
			if nodeIndex and param and REPAIRABLE_PARAM[diagnostic.code] then
				local node = nodes[tonumber(nodeIndex) :: number]
				if type(node) == "table" and type(node.params) == "table" and node.params[param] ~= nil then
					table.insert(resets, { node = node, name = param })
				end
			end
		end
		if #resets == 0 and next(dropLinks) == nil then
			break
		end
		for _, reset in resets do
			writable(reset.node, "params")[reset.name] = nil
			dropIfEmpty(reset.node, "params")
			affected[reset.node.id] = true
		end
		if next(dropLinks) then
			local kept = {}
			for i, link in ipairs(links) do
				if dropLinks[i] then
					for _, ref in { link.from, link.to } do
						local nodeId = Graph.parseRef(ref)
						if nodeId then
							affected[nodeId] = true
						end
					end
				else
					table.insert(kept, link)
				end
			end
			graph.links = kept
		end
	end
	return nodeIdsInOrder(graph, affected)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Effect
-- ─────────────────────────────────────────────────────────────────────────────

-- Minimal valid definition: current schema, slug id, 2 s (or options.duration), no components.
function Ops.newEffect(name: string, options: { duration: number?, id: string? }?): EffectDefinition
	local o: { duration: number?, id: string? } = options or {}
	local displayName = if type(name) == "string" and not string.match(name, "^%s*$")
		then checkName("newEffect", name, "name")
		else "Effect"
	local id: string
	if o.id ~= nil then
		if not Ids.isValid(o.id) then
			fail("newEffect", "id must be 1-64 characters of A-Z a-z 0-9 _ -, got " .. describe(o.id))
		end
		id = o.id :: string
	else
		id = Ids.slug(displayName, "effect")
	end
	local duration = if o.duration ~= nil
		then checkDuration("newEffect", o.duration, "duration", Constants.MAX_DURATION)
		else Ops.DEFAULT_DURATION
	local doc: EffectDefinition = {
		schemaVersion = Constants.SCHEMA_VERSION,
		id = id,
		name = displayName,
		duration = duration,
		components = {},
	}
	return doc
end

-- Deep copy (Json sentinels kept by identity).
function Ops.clone(doc: EffectDefinition): EffectDefinition
	return deepCopy(doc)
end

-- Component with this id and its index in doc.components, or nil.
function Ops.find(doc: EffectDefinition, id: string): (ComponentDef?, number?)
	return findComponent(doc, id)
end

-- Direct children in document order; roots (no or a missing parent) when id is nil.
function Ops.children(doc: EffectDefinition, id: string?): { ComponentDef }
	if id ~= nil then
		getComponent("children", doc, id)
	end
	return table.clone(childMap(doc)[id or ""] or {})
end

-- All descendants, pre-order (children in document order).
function Ops.descendants(doc: EffectDefinition, id: string): { ComponentDef }
	getComponent("descendants", doc, id)
	return descendantsOf(doc, id)
end

local EFFECT_FIELDS = { "name", "description", "duration", "loop", "seed", "timeScale", "palette", "tags" }

-- Sets an effect-level field; nil / Json.NULL removes optional fields.
function Ops.setEffectField(doc: EffectDefinition, field: string, value: any)
	local fn = "setEffectField"
	local d: any = doc
	if field == "name" then
		d.name = checkName(fn, value, "name")
	elseif field == "duration" then
		d.duration = checkDuration(fn, value, "duration", Constants.MAX_DURATION)
	elseif field == "description" then
		if isNone(value) then
			d.description = nil
		elseif type(value) ~= "string" or utf8.len(value) == nil then
			fail(fn, "description must be a UTF-8 string, got " .. describe(value))
		else
			d.description = value
		end
	elseif field == "loop" then
		if isNone(value) or value == false then
			d.loop = nil
		elseif value == true then
			d.loop = true
		else
			fail(fn, "loop must be a boolean, got " .. describe(value))
		end
	elseif field == "seed" then
		if isNone(value) then
			d.seed = nil
		elseif not isFinite(value) then
			fail(fn, "seed must be a finite number, got " .. describe(value))
		else
			d.seed = math.clamp(math.floor(value + 0.5), -MAX_SAFE_INTEGER, MAX_SAFE_INTEGER)
		end
	elseif field == "timeScale" then
		if isNone(value) then
			d.timeScale = nil
		elseif not isFinite(value) then
			fail(fn, "timeScale must be a finite number, got " .. describe(value))
		else
			d.timeScale = math.clamp(value, Ops.MIN_TIME_SCALE, Constants.MAX_TIME_SCALE)
		end
	elseif field == "tags" then
		if isNone(value) then
			d.tags = nil
			return
		end
		if type(value) ~= "table" then
			fail(fn, "tags must be an array of strings, got " .. describe(value))
		end
		local out: { string } = {}
		local seen: { [string]: boolean } = {}
		for i, tag in ipairs(value) do
			if type(tag) ~= "string" or utf8.len(tag) == nil then
				fail(fn, "tags[" .. i .. "] must be a UTF-8 string, got " .. describe(tag))
			end
			if not seen[tag] then
				seen[tag] = true
				table.insert(out, tag)
			end
		end
		d.tags = if #out > 0 then out else nil
	elseif field == "palette" then
		local palette: { [string]: string } = {}
		if not isNone(value) then
			if type(value) ~= "table" then
				fail(fn, "palette must be an object of name -> colour, got " .. describe(value))
			end
			for key, colour in pairs(value) do
				if not Ids.isValid(key) then
					fail(fn, "palette key " .. describe(key) .. " must be 1-64 characters of A-Z a-z 0-9 _ -")
				end
				if type(colour) == "string" and string.sub(colour, 1, 1) == "$" then
					fail(fn, "palette colour " .. quote(key) .. " cannot reference another palette colour")
				end
				palette[key] = canonical(fn, "color3", colour, nil, "palette colour " .. quote(key))
			end
		end
		local missing: { string } = {}
		for key in pairs(paletteUses(d)) do
			if palette[key] == nil then
				table.insert(missing, key)
			end
		end
		if #missing > 0 then
			table.sort(missing)
			fail(fn, 'palette colour "$' .. missing[1] .. '" is still used; replace its references first')
		end
		d.palette = if next(palette) then palette else nil
	else
		fail(fn, "unknown effect field " .. describe(field) .. " (fields: " .. table.concat(EFFECT_FIELDS, ", ") .. ")")
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Components
-- ─────────────────────────────────────────────────────────────────────────────

-- Adds a component; returns its id. Only explicitly passed properties are written.
function Ops.addComponent(doc: EffectDefinition, componentType: string, options: AddComponentOptions?): string
	local fn = "addComponent"
	local d: any = doc
	local o: AddComponentOptions = options or {}
	local descriptor = if type(componentType) == "string" then Components.get(componentType) else nil
	if descriptor == nil then
		fail(fn, "unknown component type " .. describe(componentType))
	end
	local desc = descriptor :: ComponentDescriptor
	checkComponentLimit(fn, d, 1)
	local name = if o.name ~= nil then checkName(fn, o.name, "name") else desc.displayName
	local parentId = if o.parent == "" then nil else o.parent
	if parentId ~= nil then
		local _, _, parentDescriptor = getComponent(fn, d, parentId)
		if not parentDescriptor.canParent then
			fail(fn, "components of type " .. parentDescriptor.type .. " cannot have children")
		end
	end
	local startTime = if o.startTime ~= nil then checkTime(fn, o.startTime, "startTime") else 0
	local duration = if o.duration ~= nil
		then checkDuration(fn, o.duration, "duration")
		else math.max(Ops.MIN_DURATION, roundTime(effectDuration(d) - startTime))
	local properties: { [string]: any } = {}
	if o.properties ~= nil then
		if type(o.properties) ~= "table" then
			fail(fn, "properties must be an object, got " .. describe(o.properties))
		end
		local keys: { string } = {}
		for key in pairs(o.properties) do
			if type(key) ~= "string" then
				fail(fn, "property names must be strings")
			end
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			local spec = Components.propertySpec(desc.type, key)
			if spec == nil then
				fail(fn, desc.type .. " has no property " .. quote(key))
			end
			local value = (o.properties :: any)[key]
			if not isNone(value) then
				properties[key] = propertyValue(fn, d, spec :: PropertySpec, value, key)
			end
		end
	end
	local taken = Ids.collect(d)
	local id = Ids.unique(Ids.slug(name, desc.type), taken)
	local component: any = {
		id = id,
		name = name,
		type = desc.type,
		parent = parentId,
		startTime = startTime,
		duration = duration,
		properties = if next(properties) then properties else nil,
	}
	local components = writable(d, "components")
	local index = #components + 1
	if o.index ~= nil then
		if not isFinite(o.index) then
			fail(fn, "index must be a number, got " .. describe(o.index))
		end
		index = math.clamp(math.floor(o.index :: number), 1, #components + 1)
	end
	table.insert(components, index, component)
	return id
end

-- Removes components with their subtrees. Returns the ids of graph nodes that were changed or removed.
function Ops.removeComponents(
	doc: EffectDefinition,
	ids: { string },
	options: { keepComponentNodes: boolean? }?
): { string }
	local fn = "removeComponents"
	local d: any = doc
	local o: { keepComponentNodes: boolean? } = options or {}
	local requested = checkIdList(fn, ids, "ids")
	for _, id in requested do
		getComponent(fn, d, id)
	end
	local removed = subtreeSet(d, requested)
	local kept = {}
	for _, component in ipairs(list(d.components)) do
		if not (type(component) == "table" and removed[component.id]) then
			table.insert(kept, component)
		end
	end
	d.components = kept
	-- Component references in the remaining components.
	for _, component in kept do
		if type(component) == "table" then
			eachComponentRef(component, function(holder: any, key: string, value: any)
				if type(value) == "string" and removed[value] then
					holder[key] = ""
				end
			end)
		end
	end
	-- Graph references.
	local graph = graphOf(d)
	if graph == nil then
		return {}
	end
	local affected: { [string]: boolean } = {}
	local order: { string } = {}
	local dropNodes: { [string]: boolean } = {}
	for _, node in ipairs(list(graph.nodes)) do
		if type(node) == "table" and type(node.id) == "string" then
			table.insert(order, node.id)
		end
	end
	for _, node in ipairs(list(graph.nodes)) do
		if type(node) ~= "table" or type(node.params) ~= "table" then
			continue
		end
		local nodeType = NodeTypes.get(node.type)
		if nodeType == nil then
			continue
		end
		if node.type == "Component" and not o.keepComponentNodes then
			local ref = node.params.component
			if type(ref) == "string" and removed[ref] then
				dropNodes[node.id] = true
				affected[node.id] = true
				continue
			end
		end
		for _, spec in nodeType.params do
			local value = node.params[spec.name]
			if spec.kind == "componentRef" and type(value) == "string" and removed[value] then
				writable(node, "params")[spec.name] = ""
				affected[node.id] = true
			end
		end
	end
	if next(dropNodes) then
		local nodes = {}
		for _, node in ipairs(list(graph.nodes)) do
			if not (type(node) == "table" and dropNodes[node.id]) then
				table.insert(nodes, node)
			end
		end
		local links = {}
		for _, link in ipairs(list(graph.links)) do
			local fromNode = if type(link) == "table" then Graph.parseRef(link.from) else nil
			local toNode = if type(link) == "table" then Graph.parseRef(link.to) else nil
			if (fromNode and dropNodes[fromNode]) or (toNode and dropNodes[toNode]) then
				for _, nodeId in { fromNode, toNode } do
					if nodeId then
						affected[nodeId] = true
					end
				end
			else
				table.insert(links, link)
			end
		end
		graph.nodes = nodes
		graph.links = links
	end
	for _, id in Ops.repairGraph(d) do
		affected[id] = true
	end
	if #list(graph.nodes) == 0 and #list(graph.links) == 0 then
		d.graph = nil
	end
	return nodeIdsInOrder(nil, affected, order)
end

-- Duplicates the selected subtrees; returns the new root ids (selection order).
function Ops.duplicateComponents(doc: EffectDefinition, ids: { string }): { string }
	local fn = "duplicateComponents"
	local d: any = doc
	local roots = selectionRoots(fn, d, ids)
	local total = 0
	for _, rootId in roots do
		total += 1 + #descendantsOf(d, rootId)
	end
	checkComponentLimit(fn, d, total)
	local taken = Ids.collect(d)
	local result: { string } = {}
	for _, rootId in roots do
		local members = subtreeSet(d, { rootId })
		local components = writable(d, "components")
		local originals = {}
		local last = 0
		for i, component in ipairs(components) do
			if type(component) == "table" and members[component.id] then
				table.insert(originals, component)
				last = i
			end
		end
		local map: { [string]: string } = {}
		for _, component in originals do
			map[component.id] = Ids.unique(component.id, taken)
		end
		local copies = {}
		for _, original in originals do
			local copy = deepCopy(original)
			copy.id = map[original.id]
			if original.id == rootId then
				local base = truncateUtf8(
					tostring(original.name),
					Constants.NAME_MAX_LENGTH - utf8.len(Ops.COPY_SUFFIX) :: number
				)
				copy.name = base .. Ops.COPY_SUFFIX
			else
				copy.parent = map[original.parent]
			end
			freshChildIds(copy, taken)
			eachComponentRef(copy, function(holder: any, key: string, value: any)
				if type(value) == "string" and map[value] then
					holder[key] = map[value]
				end
			end)
			table.insert(copies, copy)
		end
		for offset, copy in copies do
			table.insert(components, last + offset, copy)
		end
		table.insert(result, map[rootId])
	end
	return result
end

function Ops.renameComponent(doc: EffectDefinition, id: string, name: string)
	local component = getComponent("renameComponent", doc, id)
	component.name = checkName("renameComponent", name, "name")
end

function Ops.setEnabled(doc: EffectDefinition, ids: { string }, enabled: boolean)
	local fn = "setEnabled"
	if type(enabled) ~= "boolean" then
		fail(fn, "enabled must be a boolean, got " .. describe(enabled))
	end
	local targets = {}
	for _, id in checkIdList(fn, ids, "ids") do
		table.insert(targets, (getComponent(fn, doc, id)))
	end
	for _, component in targets do
		component.enabled = if enabled then nil else false
	end
end

-- Re-parents a component (nil or "" = root). Local transforms are kept as they are.
function Ops.setParent(doc: EffectDefinition, id: string, parentId: string?)
	local fn = "setParent"
	local component = getComponent(fn, doc, id)
	if parentId == nil or parentId == "" then
		component.parent = nil
		return
	end
	local _, _, parentDescriptor = getComponent(fn, doc, parentId)
	if parentId == id then
		fail(fn, "a component cannot be its own parent")
	end
	if isInSubtree(doc, parentId, id) then
		fail(fn, quote(parentId) .. " lies below " .. quote(id) .. "; the parent chain would form a cycle")
	end
	if not parentDescriptor.canParent then
		fail(fn, "components of type " .. parentDescriptor.type .. " cannot have children")
	end
	component.parent = parentId
end

-- Moves a component to position newIndex of doc.components (clamped).
function Ops.moveComponent(doc: EffectDefinition, id: string, newIndex: number)
	local fn = "moveComponent"
	local d: any = doc
	local component, index = getComponent(fn, d, id)
	if not isFinite(newIndex) then
		fail(fn, "newIndex must be a number, got " .. describe(newIndex))
	end
	local components = writable(d, "components")
	local target = math.clamp(math.floor(newIndex), 1, #components)
	table.remove(components, index)
	table.insert(components, target, component)
end

-- Sets startTime (>= 0) and/or duration (>= MIN_DURATION); nil leaves a value unchanged.
function Ops.setTiming(doc: EffectDefinition, id: string, startTime: number?, duration: number?)
	local fn = "setTiming"
	local component = getComponent(fn, doc, id)
	local s = if startTime ~= nil then checkTime(fn, startTime, "startTime") else nil
	local du = if duration ~= nil then checkDuration(fn, duration, "duration") else nil
	if s ~= nil then
		component.startTime = s
	end
	if du ~= nil then
		component.duration = du
	end
end

local COMPONENT_FIELDS = { "phase", "minQuality", "notes" }

-- Sets phase / minQuality / notes of components (nil or Json.NULL removes the field).
function Ops.setComponentField(doc: EffectDefinition, ids: { string }, field: string, value: any)
	local fn = "setComponentField"
	local targets = {}
	for _, id in checkIdList(fn, ids, "ids") do
		table.insert(targets, (getComponent(fn, doc, id)))
	end
	local v: any = nil
	if not isNone(value) then
		if field == "phase" then
			if not table.find(Constants.PHASES, value) then
				fail(fn, "phase must be one of " .. table.concat(Constants.PHASES, ", ") .. ", got " .. describe(value))
			end
		elseif field == "minQuality" then
			if not table.find(Constants.QUALITY_LEVELS, value) then
				fail(fn, "minQuality must be Low, Medium or High, got " .. describe(value))
			end
		elseif field == "notes" then
			if type(value) ~= "string" or utf8.len(value) == nil then
				fail(fn, "notes must be a UTF-8 string, got " .. describe(value))
			end
		else
			fail(fn, "unknown field " .. describe(field) .. " (fields: " .. table.concat(COMPONENT_FIELDS, ", ") .. ")")
		end
		v = value
	elseif not table.find(COMPONENT_FIELDS, field) then
		fail(fn, "unknown field " .. describe(field) .. " (fields: " .. table.concat(COMPONENT_FIELDS, ", ") .. ")")
	end
	for _, component in targets do
		component[field] = v
	end
end

-- Sets transform.position / rotation ([x, y, z]) or scale (number >= 0); nil removes the field.
function Ops.setTransform(doc: EffectDefinition, id: string, field: string, value: any)
	local fn = "setTransform"
	local component = getComponent(fn, doc, id)
	local v: any = nil
	if field == "position" or field == "rotation" then
		if not isNone(value) then
			v = canonical(fn, "vector3", value, nil, field)
		end
	elseif field == "scale" then
		if not isNone(value) then
			v = canonical(fn, "number", value, { min = 0 }, field)
		end
	else
		fail(fn, "field must be position, rotation or scale, got " .. describe(field))
	end
	if v == nil and type(component.transform) ~= "table" then
		return
	end
	local transform = writable(component, "transform")
	transform[field] = v
	dropIfEmpty(component, "transform")
end

-- Sets a property on components (canonical JSON value, ranges clamped); nil resets it.
function Ops.setProperty(doc: EffectDefinition, ids: { string }, name: string, value: any)
	local fn = "setProperty"
	local d: any = doc
	local updates = {}
	for _, id in checkIdList(fn, ids, "ids") do
		local component, _, descriptor = getComponent(fn, d, id)
		local spec = Components.propertySpec(descriptor.type, name)
		if spec == nil then
			fail(fn, descriptor.type .. " has no property " .. describe(name))
		end
		local v = if isNone(value)
			then nil
			else propertyValue(fn, d, spec :: PropertySpec, value, tostring(id) .. "." .. name)
		table.insert(updates, { component = component, value = v })
	end
	for _, update in updates do
		local component = update.component
		if update.value == nil and type(component.properties) ~= "table" then
			continue
		end
		writable(component, "properties")[name] = update.value
		dropIfEmpty(component, "properties")
	end
end

-- Removes an explicitly set property (back to the descriptor default).
function Ops.resetProperty(doc: EffectDefinition, ids: { string }, name: string)
	Ops.setProperty(doc, ids, name, nil)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Keyframes
-- ─────────────────────────────────────────────────────────────────────────────

local function findTrack(component: any, trackId: any): (any, number?)
	for i, track in ipairs(list(component.tracks)) do
		if type(track) == "table" and track.id == trackId then
			return track, i
		end
	end
	return nil, nil
end

type ResolvedKey = { component: any, descriptor: ComponentDescriptor, track: any, key: any, channel: ChannelSpec }

local function resolveKeyframe(fn: string, doc: any, ref: any, what: string): ResolvedKey
	if type(ref) ~= "table" then
		fail(fn, what .. " must be a KeyframeRef { component, track, index }, got " .. describe(ref))
	end
	local component, _, descriptor = getComponent(fn, doc, ref.component)
	local track = findTrack(component, ref.track)
	if track == nil then
		fail(fn, "component " .. quote(ref.component) .. " has no track " .. describe(ref.track))
	end
	local keyframes = list(track.keyframes)
	local index = ref.index
	if not (isFinite(index) and index % 1 == 0 and index >= 1 and index <= #keyframes) then
		fail(
			fn,
			"track " .. quote(track.id) .. " has no keyframe " .. describe(index) .. " (" .. #keyframes .. " keyframes)"
		)
	end
	local channel = if type(track.channel) == "string"
		then Components.channelSpec(descriptor.type, track.channel)
		else nil
	if channel == nil then
		fail(fn, "track " .. quote(track.id) .. " animates an unknown channel " .. describe(track.channel))
	end
	return {
		component = component,
		descriptor = descriptor,
		track = track,
		key = keyframes[index],
		channel = channel :: ChannelSpec,
	}
end

local function resolveAll(fn: string, doc: any, refs: any): { ResolvedKey }
	if type(refs) ~= "table" then
		fail(fn, "refs must be an array of KeyframeRefs, got " .. describe(refs))
	end
	local out: { ResolvedKey } = {}
	for i, ref in ipairs(refs) do
		table.insert(out, resolveKeyframe(fn, doc, ref, "refs[" .. i .. "]"))
	end
	return out
end

local function refOf(componentId: string, track: any, key: any): KeyframeRef
	return { component = componentId, track = track.id, index = table.find(track.keyframes, key) :: number }
end

-- Track of `channel` on the component: the first enabled one, else the first one, else nil.
local function trackForChannel(component: any, channel: string): any?
	local fallback = nil
	for _, track in ipairs(list(component.tracks)) do
		if type(track) == "table" and track.channel == channel then
			if track.enabled ~= false then
				return track
			end
			fallback = fallback or track
		end
	end
	return fallback
end

local function ensureTrack(fn: string, doc: any, component: any, channel: string, taken: { [string]: boolean }?): any
	local track = trackForChannel(component, channel)
	if track then
		return track
	end
	local tracks = list(component.tracks)
	if #tracks >= Constants.MAX_TRACKS_PER_COMPONENT then
		fail(
			fn,
			"component "
				.. quote(component.id)
				.. " already has "
				.. Constants.MAX_TRACKS_PER_COMPONENT
				.. " tracks (the limit)"
		)
	end
	local id = Ids.unique(Ids.slug(tostring(component.id) .. "-" .. channel, "track"), taken or Ids.collect(doc))
	track = { id = id, channel = channel, keyframes = {} }
	table.insert(writable(component, "tracks"), track)
	return track
end

-- Inserts a keyframe at its sorted position; a key at exactly the same time is updated instead.
local function insertKey(fn: string, track: any, time: number, value: any, easing: EasingDef?, setEasing: boolean): any
	local keyframes = writable(track, "keyframes")
	sortByTime(keyframes)
	for _, key in ipairs(keyframes) do
		if type(key) == "table" and key.time == time then
			key.value = value
			if setEasing then
				key.easing = easing
			end
			return key
		end
	end
	if #keyframes >= Constants.MAX_KEYFRAMES_PER_TRACK then
		fail(
			fn,
			"track "
				.. quote(track.id)
				.. " already has "
				.. Constants.MAX_KEYFRAMES_PER_TRACK
				.. " keyframes (the limit)"
		)
	end
	local key = { time = time, value = value, easing = easing }
	insertSorted(keyframes, key)
	return key
end

-- Adds (or updates) a keyframe; returns { trackId, index } of the key after sorting.
function Ops.addKeyframe(
	doc: EffectDefinition,
	id: string,
	channel: string,
	time: number,
	value: any,
	easing: EasingDef?
): { trackId: string, index: number }
	local fn = "addKeyframe"
	local d: any = doc
	local component, _, descriptor = getComponent(fn, d, id)
	local spec = if type(channel) == "string" then Components.channelSpec(descriptor.type, channel) else nil
	if spec == nil then
		fail(fn, descriptor.type .. " has no animatable channel " .. describe(channel))
	end
	local t = checkTime(fn, time, "time")
	local v = channelValue(fn, d, spec :: ChannelSpec, value, channel)
	local e = easingValue(fn, easing, "easing")
	local track = ensureTrack(fn, d, component, channel)
	local key = insertKey(fn, track, t, v, e, easing ~= nil)
	return { trackId = track.id, index = table.find(track.keyframes, key) :: number }
end

-- Removes keyframes; tracks left without keyframes are removed.
function Ops.removeKeyframes(doc: EffectDefinition, refs: { KeyframeRef })
	local fn = "removeKeyframes"
	local resolved = resolveAll(fn, doc, refs)
	local doomed: { [any]: boolean } = {}
	local tracks: { any } = {}
	local seenTrack: { [any]: boolean } = {}
	for _, r in resolved do
		doomed[r.key] = true
		if not seenTrack[r.track] then
			seenTrack[r.track] = true
			table.insert(tracks, { component = r.component, track = r.track })
		end
	end
	for _, entry in tracks do
		local kept = {}
		for _, key in ipairs(list(entry.track.keyframes)) do
			if not doomed[key] then
				table.insert(kept, key)
			end
		end
		entry.track.keyframes = kept
		if #kept == 0 then
			local _, index = findTrack(entry.component, entry.track.id)
			if index then
				table.remove(writable(entry.component, "tracks"), index)
				dropIfEmpty(entry.component, "tracks")
			end
		end
	end
end

-- Shifts keyframes by dt (times clamp at 0) and re-sorts; returns the updated refs in input order.
function Ops.moveKeyframes(doc: EffectDefinition, refs: { KeyframeRef }, dt: number): { KeyframeRef }
	local fn = "moveKeyframes"
	if not isFinite(dt) then
		fail(fn, "dt must be a finite number of seconds, got " .. describe(dt))
	end
	local resolved = resolveAll(fn, doc, refs)
	local moved: { [any]: boolean } = {}
	local tracks: { [any]: boolean } = {}
	for _, r in resolved do
		if not moved[r.key] then
			moved[r.key] = true
			r.key.time = roundTime(math.max(0, timeOf(r.key) + dt))
		end
		tracks[r.track] = true
	end
	for track in pairs(tracks) do
		sortByTime(writable(track, "keyframes"))
	end
	local out: { KeyframeRef } = {}
	for _, r in resolved do
		table.insert(out, refOf(r.component.id, r.track, r.key))
	end
	return out
end

-- Updates time / value / easing of one keyframe ("Linear" or Json.NULL easing removes it); returns its new ref.
function Ops.setKeyframe(doc: EffectDefinition, ref: KeyframeRef, fields: KeyframeFields): KeyframeRef
	local fn = "setKeyframe"
	local d: any = doc
	local r = resolveKeyframe(fn, d, ref, "ref")
	if type(fields) ~= "table" then
		fail(fn, "fields must be a table, got " .. describe(fields))
	end
	for key in pairs(fields) do
		if key ~= "time" and key ~= "value" and key ~= "easing" then
			fail(fn, "unknown keyframe field " .. describe(key))
		end
	end
	local f: any = fields
	local t = if f.time ~= nil then checkTime(fn, f.time, "time") else nil
	local v = if f.value ~= nil then channelValue(fn, d, r.channel, f.value, r.channel.name) else nil
	local e = if f.easing ~= nil then easingValue(fn, f.easing, "easing") else nil
	if t ~= nil then
		r.key.time = t
	end
	if v ~= nil then
		r.key.value = v
	end
	if f.easing ~= nil then
		r.key.easing = e
	end
	sortByTime(writable(r.track, "keyframes"))
	return refOf(r.component.id, r.track, r.key)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Events
-- ─────────────────────────────────────────────────────────────────────────────

local function eventSpecOf(fn: string, descriptor: ComponentDescriptor, action: any): (boolean, boolean)
	if action == "fire" then
		return false, true
	end
	local spec = if type(action) == "string" then Components.eventSpec(descriptor.type, action) else nil
	if spec == nil then
		local actions = {}
		for _, e in descriptor.events do
			table.insert(actions, e.action)
		end
		table.insert(actions, "fire")
		fail(
			fn,
			descriptor.type
				.. " does not support the action "
				.. describe(action)
				.. " (actions: "
				.. table.concat(actions, ", ")
				.. ")"
		)
	end
	return (spec :: any).usesCount == true, (spec :: any).usesName == true
end

local function eventCount(fn: string, count: any): number
	if not isFinite(count) then
		fail(fn, "count must be a number, got " .. describe(count))
	end
	return math.clamp(math.floor(count + 0.5), 1, Constants.MAX_EMIT_COUNT)
end

local function eventName(fn: string, name: any): string
	if not isEventName(name) then
		fail(
			fn,
			"name must be an event name ([A-Za-z_][A-Za-z0-9_-]*, at most "
				.. Constants.ID_MAX_LENGTH
				.. " characters), got "
				.. describe(name)
		)
	end
	return name
end

local function resolveEvent(fn: string, doc: any, ref: any, what: string): (any, any, ComponentDescriptor, number)
	if type(ref) ~= "table" then
		fail(fn, what .. " must be an EventRef { component, event }, got " .. describe(ref))
	end
	local component, _, descriptor = getComponent(fn, doc, ref.component)
	for i, event in ipairs(list(component.events)) do
		if type(event) == "table" and event.id == ref.event then
			return component, event, descriptor, i
		end
	end
	return fail(fn, "component " .. quote(ref.component) .. " has no event " .. describe(ref.event))
end

-- Adds a component event (time relative to the component start); returns its id.
function Ops.addEvent(
	doc: EffectDefinition,
	id: string,
	action: string,
	time: number,
	fields: { [string]: any }?
): string
	local fn = "addEvent"
	local d: any = doc
	local component, _, descriptor = getComponent(fn, d, id)
	local usesCount, usesName = eventSpecOf(fn, descriptor, action)
	local t = checkTime(fn, time, "time")
	local f: { [string]: any } = fields or {}
	if type(f) ~= "table" then
		fail(fn, "fields must be a table, got " .. describe(f))
	end
	for key in pairs(f) do
		if key ~= "count" and key ~= "name" then
			fail(fn, "unknown event field " .. describe(key))
		end
	end
	local events = list(component.events)
	if #events >= Constants.MAX_EVENTS_PER_COMPONENT then
		fail(
			fn,
			"component " .. quote(id) .. " already has " .. Constants.MAX_EVENTS_PER_COMPONENT .. " events (the limit)"
		)
	end
	local event: any = { time = t, action = action }
	if usesCount then
		event.count = eventCount(fn, if f.count ~= nil then f.count else Ops.DEFAULT_EMIT_COUNT)
	end
	if usesName then
		event.name = eventName(fn, if f.name ~= nil then f.name else Ops.DEFAULT_EVENT_NAME)
	end
	event.id = Ids.unique(Ids.slug(id .. "-" .. action, "event"), Ids.collect(d))
	local list_ = writable(component, "events")
	sortByTime(list_)
	insertSorted(list_, event)
	return event.id
end

-- Removes events given as { component, event } refs.
function Ops.removeEvents(doc: EffectDefinition, refs: { EventRef })
	local fn = "removeEvents"
	if type(refs) ~= "table" then
		fail(fn, "refs must be an array of EventRefs, got " .. describe(refs))
	end
	local doomed: { [any]: boolean } = {}
	local components: { any } = {}
	for i, ref in ipairs(refs) do
		local component, event = resolveEvent(fn, doc, ref, "refs[" .. i .. "]")
		doomed[event] = true
		if not table.find(components, component) then
			table.insert(components, component)
		end
	end
	for _, component in components do
		local kept = {}
		for _, event in ipairs(list(component.events)) do
			if not doomed[event] then
				table.insert(kept, event)
			end
		end
		component.events = kept
		dropIfEmpty(component, "events")
	end
end

-- Updates time / count / name of an event (fields the action ignores are rejected).
function Ops.setEvent(doc: EffectDefinition, ref: EventRef, fields: { [string]: any })
	local fn = "setEvent"
	local component, event, descriptor = resolveEvent(fn, doc, ref, "ref")
	if type(fields) ~= "table" then
		fail(fn, "fields must be a table, got " .. describe(fields))
	end
	local usesCount, usesName = eventSpecOf(fn, descriptor, event.action)
	local t, count, name = nil, nil, nil
	for key, value in pairs(fields) do
		if key == "time" then
			t = checkTime(fn, value, "time")
		elseif key == "count" then
			if not usesCount then
				fail(fn, "the action " .. quote(event.action) .. " has no count")
			end
			count = eventCount(fn, value)
		elseif key == "name" then
			if not usesName then
				fail(fn, "the action " .. quote(event.action) .. " has no name")
			end
			name = eventName(fn, value)
		else
			fail(fn, "unknown event field " .. describe(key))
		end
	end
	if t ~= nil then
		event.time = t
	end
	if count ~= nil then
		event.count = count
	end
	if name ~= nil then
		event.name = name
	end
	sortByTime(writable(component, "events"))
end

-- Moves an event to `time` (relative to the component start, clamped at 0).
function Ops.moveEvent(doc: EffectDefinition, ref: EventRef, time: number)
	Ops.setEvent(doc, ref, { time = time })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Markers
-- ─────────────────────────────────────────────────────────────────────────────

local function findMarker(doc: any, id: any): (any, number?)
	for i, marker in ipairs(list(doc.markers)) do
		if type(marker) == "table" and marker.id == id then
			return marker, i
		end
	end
	return nil, nil
end

-- Validated marker field values ({ [field] = value | NULL }) for phase / event / color / label / time.
local function markerFields(fn: string, doc: any, fields: any, allowCore: boolean): { [string]: any }
	local out: { [string]: any } = {}
	if fields == nil then
		return out
	end
	if type(fields) ~= "table" then
		fail(fn, "fields must be a table, got " .. describe(fields))
	end
	for key, value in pairs(fields) do
		if key == "time" and allowCore then
			out.time = checkTime(fn, value, "time")
		elseif key == "label" and allowCore then
			out.label = checkName(fn, value, "label")
		elseif key == "phase" then
			if rawequal(value, NULL) then
				out.phase = NULL
			elseif not table.find(Constants.PHASES, value) then
				fail(fn, "phase must be one of " .. table.concat(Constants.PHASES, ", ") .. ", got " .. describe(value))
			else
				out.phase = value
			end
		elseif key == "event" then
			if rawequal(value, NULL) or value == "" then
				out.event = NULL
			else
				out.event = eventName(fn, value)
			end
		elseif key == "color" then
			if rawequal(value, NULL) then
				out.color = NULL
			else
				local v = canonical(fn, "color3", value, nil, "color")
				checkPaletteRefs(fn, doc, "color3", v, "color")
				out.color = v
			end
		else
			fail(fn, "unknown marker field " .. describe(key))
		end
	end
	return out
end

local function applyFields(target: any, values: { [string]: any })
	for key, value in pairs(values) do
		target[key] = if rawequal(value, NULL) then nil else value
	end
end

-- Adds a marker (absolute time); returns its id.
function Ops.addMarker(doc: EffectDefinition, time: number, label: string, fields: { [string]: any }?): string
	local fn = "addMarker"
	local d: any = doc
	local t = checkTime(fn, time, "time")
	local text = checkName(fn, label, "label")
	local values = markerFields(fn, d, fields, false)
	local markers = list(d.markers)
	if #markers >= Constants.MAX_MARKERS then
		fail(fn, "an effect can have at most " .. Constants.MAX_MARKERS .. " markers")
	end
	local marker: any = { id = Ids.unique(Ids.slug(text, "marker"), Ids.collect(d)), time = t, label = text }
	applyFields(marker, values)
	local entries = writable(d, "markers")
	sortByTime(entries)
	insertSorted(entries, marker)
	return marker.id
end

-- Removes a marker; OnMarker params that referenced it become "". Returns the affected node ids.
function Ops.removeMarker(doc: EffectDefinition, id: string): { string }
	local fn = "removeMarker"
	local d: any = doc
	local _, index = findMarker(d, id)
	if index == nil then
		fail(fn, "unknown marker id " .. describe(id))
	end
	table.remove(writable(d, "markers"), index :: number)
	dropIfEmpty(d, "markers")
	local graph = graphOf(d)
	if graph == nil then
		return {}
	end
	local affected: { [string]: boolean } = {}
	for _, node in ipairs(list(graph.nodes)) do
		local nodeType = if type(node) == "table" then NodeTypes.get(node.type) else nil
		if nodeType and type(node.params) == "table" then
			for name, special in pairs(nodeType.special) do
				if special == "marker" and node.params[name] == id then
					writable(node, "params")[name] = ""
					affected[node.id] = true
				end
			end
		end
	end
	for _, nodeId in Ops.repairGraph(d) do
		affected[nodeId] = true
	end
	return nodeIdsInOrder(graph, affected)
end

-- Updates time / label / phase / event / color of a marker (Json.NULL removes phase, event, color).
function Ops.setMarker(doc: EffectDefinition, id: string, fields: { [string]: any })
	local fn = "setMarker"
	local d: any = doc
	local marker = findMarker(d, id)
	if marker == nil then
		fail(fn, "unknown marker id " .. describe(id))
	end
	if type(fields) ~= "table" then
		fail(fn, "fields must be a table, got " .. describe(fields))
	end
	local values = markerFields(fn, d, fields, true)
	applyFields(marker, values)
	sortByTime(writable(d, "markers"))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Graph
-- ─────────────────────────────────────────────────────────────────────────────

local function setNodeParams(fn: string, doc: any, graph: any, node: any, nodeType: any, params: { [string]: any })
	for _, name in sortedParamNames(params) do
		local spec = NodeTypes.paramSpec(nodeType, name)
		if spec == nil then
			fail(fn, nodeType.type .. " has no param " .. describe(name))
		end
		local value = params[name]
		if isNone(value) then
			if type(node.params) == "table" then
				writable(node, "params")[name] = nil
				dropIfEmpty(node, "params")
			end
		else
			writable(node, "params")[name] = nodeParamValue(fn, doc, graph, node, nodeType, spec :: PropertySpec, value)
		end
	end
end

-- Adds a graph node (params optional); returns its id.
function Ops.addNode(doc: EffectDefinition, nodeTypeName: string, position: any, params: { [string]: any }?): string
	local fn = "addNode"
	local d: any = doc
	local nodeType = NodeTypes.get(nodeTypeName)
	if nodeType == nil then
		fail(fn, "unknown node type " .. describe(nodeTypeName))
	end
	local existing = graphOf(d)
	if existing and #list(existing.nodes) >= Constants.MAX_GRAPH_NODES then
		fail(fn, "a graph can have at most " .. Constants.MAX_GRAPH_NODES .. " nodes")
	end
	if params ~= nil and type(params) ~= "table" then
		fail(fn, "params must be a table, got " .. describe(params))
	end
	local pos = if isNone(position) then nil else canonical(fn, "vector2", position, nil, "position")
	local id = Ids.unique(Ids.slug(nodeTypeName, "node"), Ids.collect(d))
	local graph = ensureGraph(d)
	local node: any = { id = id, type = nodeTypeName, position = pos }
	table.insert(graph.nodes, node)
	if params then
		setNodeParams(fn, d, graph, node, nodeType, params)
	end
	return id
end

-- Removes nodes and every link touching them.
function Ops.removeNodes(doc: EffectDefinition, ids: { string })
	local fn = "removeNodes"
	local d: any = doc
	local doomed: { [string]: boolean } = {}
	for _, id in checkIdList(fn, ids, "ids") do
		getNode(fn, d, id)
		doomed[id] = true
	end
	local graph = graphOf(d)
	if graph == nil then
		return
	end
	local nodes = {}
	for _, node in ipairs(list(graph.nodes)) do
		if not (type(node) == "table" and doomed[node.id]) then
			table.insert(nodes, node)
		end
	end
	local links = {}
	for _, link in ipairs(list(graph.links)) do
		local fromNode = if type(link) == "table" then Graph.parseRef(link.from) else nil
		local toNode = if type(link) == "table" then Graph.parseRef(link.to) else nil
		if not ((fromNode and doomed[fromNode]) or (toNode and doomed[toNode])) then
			table.insert(links, link)
		end
	end
	graph.nodes = nodes
	graph.links = links
	Ops.repairGraph(d)
	if #nodes == 0 and #list(graph.links) == 0 then
		d.graph = nil
	end
end

-- Moves nodes on the canvas by delta [dx, dy].
function Ops.moveNodes(doc: EffectDefinition, ids: { string }, delta: any)
	local fn = "moveNodes"
	local d: any = doc
	local offset = canonical(fn, "vector2", delta, nil, "delta")
	local targets = {}
	for _, id in checkIdList(fn, ids, "ids") do
		local _, node = getNode(fn, d, id)
		if not table.find(targets, node) then
			table.insert(targets, node)
		end
	end
	for _, node in targets do
		local p = if type(node.position) == "table" then node.position else { 0, 0 }
		local x = (tonumber(p[1]) or 0) + offset[1]
		local y = (tonumber(p[2]) or 0) + offset[2]
		node.position = canonical(fn, "vector2", { x, y }, nil, "position")
	end
end

-- Sets (nil: resets) a node param; returns the ids of nodes changed by the graph repair.
function Ops.setNodeParam(doc: EffectDefinition, id: string, name: string, value: any): { string }
	local fn = "setNodeParam"
	local d: any = doc
	local graph, node, _, nodeType = getNode(fn, d, id)
	if type(name) ~= "string" or NodeTypes.paramSpec(nodeType, name) == nil then
		fail(fn, tostring(nodeType.type) .. " has no param " .. describe(name))
	end
	setNodeParams(fn, d, graph, node, nodeType, { [name] = if value == nil then NULL else value })
	return Ops.repairGraph(d)
end

local function checkRefNode(fn: string, doc: any, ref: any, what: string): (string, string)
	local nodeId, pin = Graph.parseRef(ref)
	if nodeId == nil or pin == nil then
		fail(fn, what .. ' must be "nodeId.pinName", got ' .. describe(ref))
	end
	getNode(fn, doc, nodeId)
	return nodeId :: string, pin :: string
end

-- Links from -> to when Graph.canConnect allows it. Returns (true) or (false, reason, code).
function Ops.connect(
	doc: EffectDefinition,
	from: string,
	to: string,
	options: { replace: boolean? }?
): (boolean, string?, string?)
	local fn = "connect"
	local d: any = doc
	checkRefNode(fn, d, from, "from")
	checkRefNode(fn, d, to, "to")
	local graph = ensureGraph(d)
	local ok, reason, code = Graph.canConnect(graph, d, from, to)
	local o: { replace: boolean? } = options or {}
	if not ok and o.replace and (code == "graph.input_multiple" or code == "graph.output_multiple") then
		local previous = graph.links
		local kept = {}
		for _, link in ipairs(previous) do
			local occupies = if code == "graph.input_multiple" then link.to == to else link.from == from
			if not occupies then
				table.insert(kept, link)
			end
		end
		graph.links = kept
		ok, reason, code = Graph.canConnect(graph, d, from, to)
		if not ok then
			graph.links = previous
		end
	end
	if not ok then
		return false, reason, code
	end
	table.insert(graph.links, { from = from, to = to })
	Ops.repairGraph(d)
	return true, nil, nil
end

-- Removes the links into `to` (only those from `from` when given); returns how many were removed.
function Ops.disconnect(doc: EffectDefinition, from: string?, to: string): number
	local fn = "disconnect"
	local d: any = doc
	checkRefNode(fn, d, to, "to")
	if from ~= nil then
		checkRefNode(fn, d, from, "from")
	end
	local graph = graphOf(d)
	if graph == nil then
		return 0
	end
	local kept = {}
	local removed = 0
	for _, link in ipairs(list(graph.links)) do
		if type(link) == "table" and link.to == to and (from == nil or link.from == from) then
			removed += 1
		else
			table.insert(kept, link)
		end
	end
	graph.links = kept
	if removed > 0 then
		Ops.repairGraph(d)
	end
	return removed
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Clipboard
-- ─────────────────────────────────────────────────────────────────────────────

-- Copies the selected subtrees (document order) with startTimes relative to the earliest one.
function Ops.copyComponents(doc: EffectDefinition, ids: { string }): ClipboardPayload
	local fn = "copyComponents"
	local d: any = doc
	local roots = selectionRoots(fn, d, ids)
	local members = subtreeSet(d, roots)
	local rootSet: { [string]: boolean } = {}
	for _, id in roots do
		rootSet[id] = true
	end
	local copies = {}
	local origin = INF
	local refs: { [string]: boolean } = {}
	for _, component in ipairs(list(d.components)) do
		if type(component) == "table" and members[component.id] then
			local copy = deepCopy(component)
			if rootSet[component.id] then
				copy.parent = nil
			end
			componentPaletteRefs(copy, refs)
			origin = math.min(origin, timeOf({ time = component.startTime }))
			table.insert(copies, copy)
		end
	end
	if origin == INF then
		origin = 0
	end
	for _, copy in copies do
		local start = timeOf({ time = copy.startTime })
		if copy.startTime ~= nil or start ~= origin then
			copy.startTime = roundTime(start - origin)
		end
	end
	return {
		kind = "components",
		version = Ops.CLIPBOARD_VERSION,
		origin = origin,
		source = d.id,
		palette = paletteSubset(d, refs),
		roots = roots,
		components = copies,
	}
end

local function checkPayload(fn: string, payload: any, kind: string)
	if type(payload) ~= "table" or payload.kind ~= kind then
		fail(
			fn,
			"expected a "
				.. kind
				.. " clipboard payload, got "
				.. describe(if type(payload) == "table" then payload.kind else payload)
		)
	end
	if type(payload.version) ~= "number" or payload.version > Ops.CLIPBOARD_VERSION then
		fail(fn, "unsupported clipboard version " .. describe(payload.version))
	end
end

-- Pastes copied components with fresh ids under `parent` (or at the root); returns the new root ids.
function Ops.pasteComponents(
	doc: EffectDefinition,
	payload: ClipboardPayload,
	parent: string?,
	options: { atTime: number? }?
): { string }
	local fn = "pasteComponents"
	local d: any = doc
	checkPayload(fn, payload, "components")
	local p: any = payload
	local o: { atTime: number? } = options or {}
	local source = list(p.components)
	if parent == "" then
		parent = nil
	end
	if parent ~= nil then
		local _, _, parentDescriptor = getComponent(fn, d, parent)
		if not parentDescriptor.canParent then
			fail(fn, "components of type " .. parentDescriptor.type .. " cannot have children")
		end
	end
	local base = if o.atTime ~= nil
		then checkTime(fn, o.atTime, "atTime")
		else (if isFinite(p.origin) then math.max(0, p.origin) else 0)
	checkComponentLimit(fn, d, #source)
	-- Ids first (references may point forwards inside the payload).
	local taken = Ids.collect(d)
	local map: { [string]: string } = {}
	for i, component in ipairs(source) do
		if type(component) ~= "table" or not Ids.isValid(component.id) then
			fail(fn, "clipboard component " .. i .. " has no valid id")
		end
		if map[component.id] then
			fail(fn, "clipboard component id " .. quote(component.id) .. " appears twice")
		end
		if type(component.type) ~= "string" or Components.get(component.type) == nil then
			fail(
				fn,
				"clipboard component " .. quote(component.id) .. " has an unknown type " .. describe(component.type)
			)
		end
		map[component.id] = Ids.unique(component.id, taken)
	end
	local refs: { [string]: boolean } = {}
	local copies = {}
	for _, component in ipairs(source) do
		local copy = deepCopy(component)
		copy.id = map[component.id]
		copy.name = checkName(fn, copy.name, "clipboard component name")
		if type(component.parent) == "string" and map[component.parent] then
			copy.parent = map[component.parent]
		else
			copy.parent = parent
		end
		local relative = timeOf({ time = component.startTime })
		if component.startTime ~= nil or base ~= 0 then
			copy.startTime = roundTime(math.max(0, base + relative))
		end
		freshChildIds(copy, taken)
		componentPaletteRefs(copy, refs)
		table.insert(copies, copy)
	end
	-- Component references: remapped inside the payload, kept when they resolve here, cleared otherwise.
	local byId: { [string]: any } = {}
	for _, component in ipairs(list(d.components)) do
		if type(component) == "table" and type(component.id) == "string" then
			byId[component.id] = component
		end
	end
	for _, copy in copies do
		byId[copy.id] = copy
	end
	for _, copy in copies do
		eachComponentRef(copy, function(holder: any, key: string, value: any, spec: PropertySpec)
			if type(value) ~= "string" or value == "" then
				return
			end
			local target = map[value] or (if byId[value] then value else nil)
			local targetComponent = if target then byId[target] else nil
			local allowed = spec.componentTypes
			if targetComponent == nil or (allowed and not table.find(allowed, targetComponent.type)) then
				holder[key] = ""
			else
				holder[key] = target
			end
		end)
	end
	mergePalette(fn, d, refs, p.palette)
	local components = writable(d, "components")
	for _, copy in copies do
		table.insert(components, copy)
	end
	local roots: { string } = {}
	local rootList = if type(p.roots) == "table" then p.roots else {}
	for _, id in ipairs(rootList) do
		if map[id] then
			table.insert(roots, map[id])
		end
	end
	if #roots == 0 then
		for _, component in ipairs(source) do
			if not (type(component.parent) == "string" and map[component.parent]) then
				table.insert(roots, map[component.id])
			end
		end
	end
	return roots
end

-- Copies keyframes; times are relative to the earliest copied key (absolute effect time).
function Ops.copyKeyframes(doc: EffectDefinition, refs: { KeyframeRef }): ClipboardPayload
	local fn = "copyKeyframes"
	local d: any = doc
	local resolved = resolveAll(fn, d, refs)
	local groups: { { component: any, track: any, channel: ChannelSpec, keys: { any } } } = {}
	local byTrack: { [any]: any } = {}
	local seenKey: { [any]: boolean } = {}
	local origin = INF
	for _, r in resolved do
		if seenKey[r.key] then
			continue
		end
		seenKey[r.key] = true
		local group = byTrack[r.track]
		if group == nil then
			group = { component = r.component, track = r.track, channel = r.channel, keys = {} }
			byTrack[r.track] = group
			table.insert(groups, group)
		end
		table.insert(group.keys, r.key)
		origin = math.min(origin, timeOf({ time = r.component.startTime }) + timeOf(r.key))
	end
	if origin == INF then
		origin = 0
	end
	origin = roundTime(origin)
	local refsUsed: { [string]: boolean } = {}
	local tracks: { ClipboardTrack } = {}
	for _, group in groups do
		local start = timeOf({ time = group.component.startTime })
		local keyframes = {}
		for _, key in group.keys do
			table.insert(keyframes, {
				time = roundTime(math.max(0, start + timeOf(key) - origin)),
				value = deepCopy(key.value),
				easing = deepCopy(key.easing),
			})
			if group.channel.kind == "color3" then
				addRefs(refsUsed, "color3", key.value)
			end
		end
		sortByTime(keyframes)
		table.insert(tracks, {
			component = group.component.id,
			channel = group.track.channel,
			kind = group.channel.kind :: string,
			keyframes = keyframes,
		})
	end
	return {
		kind = "keyframes",
		version = Ops.CLIPBOARD_VERSION,
		origin = origin,
		source = d.id,
		palette = paletteSubset(d, refsUsed),
		tracks = tracks,
	}
end

-- Pastes keyframes at absolute effect time `atTime` onto their source components or onto `targetId`.
function Ops.pasteKeyframes(
	doc: EffectDefinition,
	payload: ClipboardPayload,
	atTime: number,
	targetId: string?
): { KeyframeRef }
	local fn = "pasteKeyframes"
	local d: any = doc
	checkPayload(fn, payload, "keyframes")
	local p: any = payload
	local at = checkTime(fn, atTime, "atTime")
	local target = if targetId ~= nil then getComponent(fn, d, targetId) else nil
	-- Resolve every track first, so nothing is written when one of them cannot be pasted.
	local plan = {}
	for i, ptrack in ipairs(list(p.tracks)) do
		if type(ptrack) ~= "table" or type(ptrack.channel) ~= "string" then
			fail(fn, "clipboard track " .. i .. " is malformed")
		end
		local component = target
		if component == nil then
			component = getComponent(fn, d, ptrack.component)
		end
		local descriptor = descriptorOf(fn, component)
		local spec = Components.channelSpec(descriptor.type, ptrack.channel)
		if spec == nil or (type(ptrack.kind) == "string" and spec.kind ~= ptrack.kind) then
			if target then
				continue -- the target type lacks this channel
			end
			fail(fn, descriptor.type .. " has no " .. tostring(ptrack.kind) .. " channel " .. quote(ptrack.channel))
		end
		table.insert(plan, { component = component, spec = spec :: ChannelSpec, keyframes = list(ptrack.keyframes) })
	end
	if target and #plan == 0 and #list(p.tracks) > 0 then
		fail(fn, "component " .. quote(targetId) .. " has none of the copied channels")
	end
	local refs: { [string]: boolean } = {}
	for _, entry in plan do
		if (entry.spec :: ChannelSpec).kind == "color3" then
			for _, key in entry.keyframes do
				if type(key) == "table" then
					addRefs(refs, "color3", key.value)
				end
			end
		end
	end
	mergePalette(fn, d, refs, p.palette)
	local taken = Ids.collect(d)
	local pasted: { { component: any, track: any, key: any } } = {}
	for _, entry in plan do
		local component = entry.component
		local spec: ChannelSpec = entry.spec
		local start = timeOf({ time = component.startTime })
		local track = ensureTrack(fn, d, component, spec.name, taken)
		for _, pkey in entry.keyframes do
			if type(pkey) ~= "table" or not isFinite(pkey.time) then
				fail(fn, "clipboard keyframe is malformed")
			end
			local localTime = roundTime(math.max(0, at + pkey.time - start))
			local value = channelValue(fn, d, spec, pkey.value, spec.name)
			local easing = easingValue(fn, pkey.easing, "easing")
			local key = insertKey(fn, track, localTime, value, easing, true)
			table.insert(pasted, { component = component, track = track, key = key })
		end
	end
	local out: { KeyframeRef } = {}
	local seen: { [any]: boolean } = {}
	for _, item in pasted do
		if not seen[item.key] then
			seen[item.key] = true
			table.insert(out, refOf(item.component.id, item.track, item.key))
		end
	end
	return out
end

return Ops
