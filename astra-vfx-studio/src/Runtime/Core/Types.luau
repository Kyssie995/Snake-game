--!strict
--[[
	Types — central type definitions for ASTRA VFX Studio.

	Three representations of an effect exist; keep them apart:

	1. EffectDefinition ("definition", "doc")   — plain JSON-compatible data. This is what JSON files, StringValues
	   and exported ModuleScripts contain. Colours are "#RRGGBB" strings, vectors are arrays, enums are names.
	   Edited by the plugin (Authoring/Ops) and by Claude (files). Never contains Roblox datatypes.
	2. CompiledEffect                          — produced by Core/Compiler from a validated definition for one
	   (quality, scale, palette) combination. Values are decoded into Roblox datatypes, defaults are filled in,
	   keyframes are sorted and easing functions resolved. Immutable once created; cached and shared.
	3. Built effect (Builder.BuiltEffect)      — the Roblox Instances of one playing copy, plus per-component
	   ComponentInstance controllers. Owned by exactly one Player.

	Time: all definition times are seconds. Component keyframes and events are RELATIVE to the component's
	startTime (like layers in After Effects); markers and the schedule use ABSOLUTE effect time.

	Space: +Y is up, -Z is forward (CFrame.LookVector), +X is right. Positions are studs relative to the parent
	component (or the effect origin). Rotations are degrees in Roblox "Orientation" order (CFrame.fromOrientation).
]]

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared enums (string unions)
-- ─────────────────────────────────────────────────────────────────────────────

export type QualityLevel = "Low" | "Medium" | "High"

-- Design phases used by markers, components and the generator (see docs/EFFECT_FORMAT.md).
export type Phase = "anticipation" | "charge" | "action" | "impact" | "secondary" | "dissipation"

export type Severity = "error" | "warning" | "info"

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Definition (JSON-compatible). "Json*" types describe the encoded value shapes.
-- ─────────────────────────────────────────────────────────────────────────────

export type JsonVector3 = { number } -- [x, y, z]
export type JsonVector2 = { number } -- [x, y]
export type JsonColor = string -- "#RRGGBB" or "$paletteKey"; importers also accept {r, g, b} arrays 0-255
export type JsonNumberRange = number | { number } -- n or [min, max]
export type JsonNumberSequence = number | { { number } } -- n or [[time, value, envelope?], ...]
export type JsonColorSequence = JsonColor | { { any } } -- colour or [[time, colour], ...]

-- Easing: "Linear" | "Constant" | "<Style>" | "<Style>.<In|Out|InOut>" | { bezier = {x1, y1, x2, y2} }
-- Styles are Roblox Enum.EasingStyle names (Sine, Quad, Cubic, Quart, Quint, Exponential, Circular, Back,
-- Elastic, Bounce, Linear). A style without a direction means ".Out" (Roblox's default direction).
export type EasingDef = string | { bezier: { number } }

export type TransformDef = {
	position: JsonVector3?,
	rotation: JsonVector3?, -- degrees, Orientation order
	scale: number?, -- uniform multiplier for this component's own size-like values (not inherited)
}

export type KeyframeDef = {
	time: number, -- seconds, relative to component startTime
	value: any, -- JSON form of the channel kind
	easing: EasingDef?, -- interpolation from this keyframe to the next one; default "Linear"
}

export type TrackDef = {
	id: string,
	channel: string, -- channel name declared by the component descriptor ("transparency", "position", ...)
	keyframes: { KeyframeDef },
	enabled: boolean?,
}

export type EventDef = {
	id: string,
	time: number, -- seconds, relative to component startTime
	action: string, -- declared by the component descriptor ("emit", "clear", "enable", "disable", "play", ...)
	count: number?, -- "emit": particle count
	name: string?, -- "fire": event name forwarded to game code
}

export type ComponentDef = {
	id: string, -- stable id, [A-Za-z0-9_-]{1,64}, unique inside the effect
	name: string, -- display name
	type: string, -- registry type ("particles", "beam", ...)
	parent: string?, -- id of the parent component (transform hierarchy)
	enabled: boolean?, -- default true; disabled components are not built
	startTime: number?, -- default 0
	duration: number?, -- default: effect duration - startTime
	phase: Phase?,
	minQuality: QualityLevel?, -- component is omitted below this quality level
	transform: TransformDef?,
	properties: { [string]: any }?, -- JSON-form values, keys declared by the descriptor
	tracks: { TrackDef }?,
	events: { EventDef }?,
	qualityOverrides: { [string]: { [string]: any } }?, -- [QualityLevel] -> partial properties
	notes: string?, -- free text for humans / Claude
}

export type MarkerDef = {
	id: string,
	time: number, -- absolute seconds
	label: string,
	phase: Phase?,
	event: string?, -- if set, the runtime fires this named event at the marker time
	color: string?,
}

-- Node graph (see Core/Graph). Pins are addressed as "nodeId.pinName".
export type NodeDef = {
	id: string,
	type: string,
	position: JsonVector2?, -- editor canvas position
	params: { [string]: any }?,
}

export type LinkDef = {
	from: string, -- "nodeId.outputPin"
	to: string, -- "nodeId.inputPin"
}

export type GraphDef = {
	nodes: { NodeDef },
	links: { LinkDef },
}

export type QualityProfileOverride = {
	countScale: number?,
	segmentScale: number?,
	sizeCompensation: number?,
	lightShadows: boolean?,
	maxLights: number?,
}

export type EffectDefinition = {
	schemaVersion: number,
	id: string,
	name: string,
	description: string?,
	tags: { string }?,
	duration: number, -- seconds (0 < duration <= Constants.MAX_DURATION)
	loop: boolean?,
	seed: number?, -- integer; default derived from id
	timeScale: number?,
	palette: { [string]: string }?, -- name -> "#RRGGBB"; referenced as "$name"
	markers: { MarkerDef }?,
	components: { ComponentDef },
	graph: GraphDef?,
	quality: { [string]: QualityProfileOverride }?, -- [QualityLevel] -> override
	metadata: { [string]: any }?,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Diagnostics (validation, migration, graph, analyzer)
-- ─────────────────────────────────────────────────────────────────────────────

export type Diagnostic = {
	severity: Severity,
	code: string, -- stable machine-readable code, e.g. "property.range"
	path: string, -- location with 1-based indices, e.g. "components[2].properties.rate"
	message: string,
	hint: string?,
	componentId: string?,
}

export type ValidationResult = {
	ok: boolean, -- true when there are no errors (warnings allowed)
	errors: { Diagnostic },
	warnings: { Diagnostic },
	infos: { Diagnostic },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Component registry contract (Core/Components/*)
-- ─────────────────────────────────────────────────────────────────────────────

export type PropertyKind =
	"number"
	| "integer"
	| "boolean"
	| "string"
	| "enum"
	| "color3"
	| "vector3"
	| "vector2"
	| "numberRange"
	| "numberSequence"
	| "colorSequence"
	| "asset"
	| "componentRef"

-- How the runtime Scale option and the component's transform.scale affect a value.
-- "length": multiplied by scale (sizes, distances, speeds, widths, ranges). nil: unaffected.
export type ScaleRule = "length"

-- How quality profiles affect a value. "count": × countScale (rates, burst counts, debris counts);
-- "segments": × segmentScale (rounded, min 1). nil: unaffected.
export type QualityRule = "count" | "segments"

export type PropertySpec = {
	name: string, -- JSON key (camelCase)
	kind: PropertyKind,
	default: any, -- JSON-form default
	label: string?,
	category: string?, -- inspector group ("Emission", "Motion", "Appearance", ...)
	description: string, -- one-line doc; used for tooltips and generated docs
	min: number?, -- numeric clamp (applies to numbers, sequence values, vector components, ranges)
	max: number?,
	step: number?, -- UI hint
	enum: { string }?, -- allowed names for "enum"
	enumType: string?, -- Roblox Enum name for "enum" (e.g. "ParticleEmitterShape")
	componentTypes: { string }?, -- allowed target types for "componentRef"
	scale: ScaleRule?,
	quality: QualityRule?,
	advanced: boolean?, -- collapsed under "Advanced" in the inspector
	maxKeypoints: number?, -- sequences; Roblox limit is 20
}

export type ChannelKind = "number" | "vector3" | "color3" | "boolean"

export type ChannelSpec = {
	name: string,
	kind: ChannelKind,
	label: string?,
	description: string,
	min: number?,
	max: number?,
	scale: ScaleRule?,
	-- Property whose (decoded) value is the channel's resting value when the channel has no track, if any.
	baseProperty: string?,
}

export type EventSpec = {
	action: string,
	description: string,
	usesCount: boolean?,
	usesName: boolean?,
}

-- A scheduled action produced from component events, markers and the node graph.
export type ScheduledAction = {
	time: number, -- absolute effect time
	action: string,
	componentId: string?,
	count: number?,
	name: string?,
	source: "event" | "marker" | "graph",
	sourceId: string?, -- event id / marker id / node id
	-- graph-only payloads
	channel: string?,
	value: any?, -- decoded channel value
	duration: number?,
	easing: EasingFn?,
	order: number, -- stable tie-breaker for equal times
}

export type EasingFn = (alpha: number) -> number

export type CompiledKeyframe = {
	time: number, -- relative to component start
	value: any, -- decoded (number / Vector3 / Color3 / boolean)
	ease: EasingFn, -- from this key to the next
	constant: boolean, -- true for "Constant" (step) segments
}

export type CompiledTrack = {
	id: string,
	channel: string,
	kind: ChannelKind,
	keys: { CompiledKeyframe }, -- sorted by time, at least one
}

export type CompiledEvent = {
	id: string,
	time: number, -- relative
	action: string,
	count: number?,
	name: string?,
}

export type CompiledComponent = {
	id: string,
	name: string,
	type: string,
	parentId: string?,
	depth: number, -- 0 for roots
	startTime: number, -- absolute
	endTime: number, -- absolute (exclusive)
	props: { [string]: any }, -- decoded values with defaults, quality and scale applied
	position: Vector3, -- rest transform (already scaled)
	rotation: Vector3, -- degrees
	scale: number, -- component's own scale (transform.scale)
	tracks: { [string]: CompiledTrack }, -- by channel
	events: { CompiledEvent },
	seed: number, -- per-component deterministic seed
}

export type QualityProfile = {
	level: QualityLevel,
	countScale: number,
	segmentScale: number,
	sizeCompensation: number,
	lightShadows: boolean,
	maxLights: number,
}

export type CompiledEffect = {
	id: string,
	name: string,
	duration: number,
	loop: boolean,
	timeScale: number,
	seed: number,
	scale: number,
	quality: QualityProfile,
	palette: { [string]: Color3 },
	components: { CompiledComponent }, -- topological order (parents before children), built components only
	byId: { [string]: CompiledComponent },
	markers: { MarkerDef },
	schedule: { ScheduledAction }, -- static actions (events + markers + graph OnPlay/OnMarker), sorted
	graph: any?, -- Core/Graph compiled graph for runtime triggers (OnEvent), or nil
	maxTail: number, -- seconds to keep instances alive after the end (particle/trail lifetimes)
	definition: EffectDefinition, -- the source definition (migrated, validated). Do not mutate.
}

-- Context passed to descriptor.build.
export type BuildContext = {
	effect: CompiledEffect,
	container: Instance, -- Folder that owns every instance of this effect copy
	root: BasePart, -- anchored, invisible root part at the effect origin (attachments live here)
	parentOf: (componentId: string) -> ComponentInstance?, -- already-built parent controller, if any
	isPreview: boolean,
	viewport: boolean, -- true when building into a ViewportFrame (geometry only)
	tagInstance: (inst: Instance, componentId: string) -> (), -- marks an instance as owned by a component
}

-- Context passed to per-frame controller calls.
export type FrameContext = {
	time: number, -- absolute effect time
	dt: number, -- scaled delta time (0 while seeking)
	seeking: boolean, -- true for scrub/seek evaluation (no emission, deterministic state)
	rootCFrame: CFrame, -- world CFrame of the effect origin (after attach/offset)
	moveParts: { BasePart }, -- append parts + cframes here to batch through WorldRoot:BulkMoveTo
	moveCFrames: { CFrame },
	fire: (name: string) -> (), -- forwards a named event to the handle
}

--[[
	ComponentInstance — controller for one built component. Created by descriptor.build().
	Lifecycle (driven by Runtime/Core/Player):
		build → setActive(false) → [setActive(true) → (apply* / setTransform / update)* → setActive(false)]* → destroy
	All methods must be cheap: they are called every frame while the component is active.
]]
export type ComponentInstance = {
	component: CompiledComponent,
	-- Instances owned by this component (used for counting, tagging, cleanup). First entry is the main one.
	instances: { Instance },
	-- Reserved (v1 composes child transforms in the Player, so this is normally nil).
	anchor: Attachment?,
	-- Activates/deactivates (component span start/end). Inactive components must be invisible and not emit.
	setActive: (self: ComponentInstance, active: boolean, frame: FrameContext) -> (),
	-- Applies one channel value (decoded). Unknown channels must be ignored silently.
	apply: (self: ComponentInstance, channel: string, value: any) -> (),
	-- Places the component. `localCFrame` is relative to the effect origin (composed with parents);
	-- `worldCFrame = frame.rootCFrame * localCFrame`. Parts should append to frame.moveParts/moveCFrames.
	setTransform: (self: ComponentInstance, localCFrame: CFrame, worldCFrame: CFrame, frame: FrameContext) -> (),
	-- Executes a scheduled action targeted at this component (e.g. "emit").
	onAction: (self: ComponentInstance, action: ScheduledAction, frame: FrameContext) -> (),
	-- Optional per-frame procedural update while active. localTime is relative to the component start.
	update: ((self: ComponentInstance, localTime: number, frame: FrameContext) -> ())?,
	-- Called when the effect is stopping gracefully: stop emitting, let existing particles finish.
	release: (self: ComponentInstance) -> (),
	-- Restores the freshly-built state (authored property values, no particles) so a pooled copy can replay.
	reset: (self: ComponentInstance) -> (),
	destroy: (self: ComponentInstance) -> (),
}

-- Heuristic cost estimate used by Authoring/Analyzer. Values are per component, at the given quality.
export type CostEstimate = {
	instances: number,
	parts: number,
	attachments: number,
	emitters: number,
	beams: number,
	trails: number,
	lights: number,
	shadowLights: number,
	sounds: number,
	-- particles
	continuousRate: number, -- particles/second while active (after quality)
	burstCount: number, -- total particles emitted by events (after quality)
	maxLifetime: number, -- seconds
	-- per-frame work while active
	movingParts: number, -- parts whose CFrame changes every frame while active
	propertyUpdates: number, -- property writes per frame while active (estimate)
	-- transparency layering (heuristic): number of overlapping transparent surfaces this component adds
	transparentLayers: number,
	-- approximate screen-area weight of transparent particles (size² × count), heuristic
	overdrawWeight: number,
	notes: { string }?,
}

export type ComponentDescriptor = {
	type: string,
	displayName: string,
	category: string, -- "Particles" | "Beams & Trails" | "Geometry" | "Lighting" | "Audio" | "Procedural" | "Structure"
	description: string,
	icon: string?, -- short glyph or rbxasset icon path for the UI
	properties: { PropertySpec },
	channels: { ChannelSpec },
	events: { EventSpec },
	canParent: boolean, -- may other components use this one as parent
	supportsViewport: boolean, -- renders inside a ViewportFrame (see docs/ROBLOX_API_CONSTRAINTS.md)
	build: (ctx: BuildContext, component: CompiledComponent) -> ComponentInstance,
	estimateCost: (component: CompiledComponent, quality: QualityProfile) -> CostEstimate,
	-- Seconds the component's visuals outlive its span (particle / trail lifetimes). nil = 0.
	tailTime: ((component: CompiledComponent) -> number)?,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Runtime API
-- ─────────────────────────────────────────────────────────────────────────────

export type PlayOptions = {
	CFrame: CFrame?, -- world origin (default: identity or Position)
	Position: Vector3?,
	Attach: Instance?, -- BasePart or Attachment to follow every frame
	Offset: CFrame?, -- applied on top of Attach / CFrame
	Parent: Instance?, -- container parent (default workspace)
	Scale: number?, -- uniform size multiplier (default 1)
	Quality: (QualityLevel | "Auto")?,
	TimeScale: number?,
	Seed: number?,
	Loop: boolean?,
	Palette: { [string]: Color3 }?, -- overrides palette entries by name
	OnEvent: ((name: string) -> ())?,
	Autoplay: boolean?, -- default true
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type PlayerState = "idle" | "playing" | "paused" | "stopping" | "finished" | "destroyed"

return {}
