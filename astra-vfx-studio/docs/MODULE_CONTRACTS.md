# Module Contracts (engineering spec)

> Implementer-facing specification (English, so signatures and identifiers stay exact). The German overview is
> [`ARCHITECTURE.md`](ARCHITECTURE.md); engine facts are in [`ROBLOX_API_CONSTRAINTS.md`](ROBLOX_API_CONSTRAINTS.md).
> Central types live in `src/Runtime/Core/Types.luau` — import them, never redefine them.

## 0. Rules for every module

* `--!strict` at the top. Use types from `Core/Types`. Keep public functions documented with a one-line comment.
* Requires are instance-relative (`require(script.Parent.Json)`), never string requires.
* Respect the dependency order in ARCHITECTURE.md §2. `src/Runtime` must never require outside `src/Runtime`.
* No yielding in runtime code paths. No `while true` loops. No `wait()`/`spawn()`/`delay()` (use `task` only where
  needed). Never call `game:GetService` at module load in Runtime/Core; go through `Core/Env` lazily.
* Validation problems are returned as `Types.Diagnostic`s; `error()` only for programmer errors.
* Deterministic: no `math.random`, no `os.time()` in logic. Use `Core/Random`.
* Every module gets a spec file `tests/specs/<Module>.spec.luau` (see `tests/specs/Harness.spec.luau` for the
  format). Specs must pass in Lune: `lune run tests/lune/run.luau -- <filter>`.
* Engine methods that Lune lacks (ParticleEmitter:Emit, Trail:Clear, RunService events, BulkMoveTo, Sound:Play…)
  are implemented by `tests/lune/Fakes.luau` and recorded there (`ctx.fakes`). Do not invent other engine members.

## 1. Core/Constants

```lua
Constants.VERSION = "0.1.0"
Constants.SCHEMA_VERSION = 1
Constants.MAX_DURATION = 60            -- seconds
Constants.MAX_COMPONENTS = 256
Constants.MAX_TRACKS_PER_COMPONENT = 32
Constants.MAX_KEYFRAMES_PER_TRACK = 256
Constants.MAX_EVENTS_PER_COMPONENT = 256
Constants.MAX_MARKERS = 128
Constants.MAX_SEQUENCE_KEYPOINTS = 20  -- Roblox limit for NumberSequence/ColorSequence
Constants.MAX_EMIT_COUNT = 10000
Constants.MAX_GRAPH_NODES = 256
Constants.MAX_GRAPH_ACTIONS = 10000    -- per trigger
Constants.MAX_LOOP_ITERATIONS = 100
Constants.ID_PATTERN = "^[A-Za-z0-9_%-]+$"
Constants.ID_MAX_LENGTH = 64
Constants.NAME_MAX_LENGTH = 100
Constants.ATTR_EFFECT = "AstraEffect"        -- attribute on every built container
Constants.ATTR_COMPONENT = "AstraComponent"  -- attribute on every built instance (component id)
Constants.ATTR_PREVIEW = "AstraPreview"      -- attribute on preview-only instances
Constants.PREVIEW_FOLDER = "AstraVFX_Preview"
Constants.QUALITY_LEVELS = { "Low", "Medium", "High" }
Constants.PHASES = { "anticipation", "charge", "action", "impact", "secondary", "dissipation" }
-- Canonical JSON key order (keys not listed are sorted alphabetically after these):
Constants.KEY_ORDER = { "schemaVersion", "id", "name", "type", "description", "tags", "duration", "loop", "seed",
  "timeScale", "palette", "parent", "enabled", "startTime", "phase", "minQuality", "transform", "position",
  "rotation", "scale", "properties", "tracks", "channel", "keyframes", "time", "value", "easing", "events",
  "action", "count", "markers", "label", "event", "components", "graph", "nodes", "links", "from", "to",
  "params", "quality", "qualityOverrides", "notes", "metadata" }
```

## 2. Core/Signal

```lua
Signal.new() -> Signal            -- generic; typed via Types.Signal<T...>
signal:Connect(fn) -> Connection  -- Connection.Connected, Connection:Disconnect()
signal:Once(fn) -> Connection
signal:Fire(...)                  -- handlers run synchronously in connection order; a handler error is caught
                                  -- (pcall) and reported with warn() so one bad listener cannot break the caller
signal:DisconnectAll()
```

## 3. Core/Random (deterministic, no Roblox `Random` — Lune lacks it)

```lua
Random.new(seed: number) -> Rng        -- 32-bit integer state; seed is hashed if not an integer
rng:next() -> number                   -- [0, 1)
rng:range(min, max) -> number          -- [min, max)
rng:int(min, max) -> number            -- inclusive
rng:sign() -> number                   -- -1 or 1
rng:unitVector() -> Vector3            -- uniform on sphere
rng:inCone(direction: Vector3, angleDeg) -> Vector3
rng:pick(list) -> any
rng:clone() -> Rng
Random.hash(...: string | number) -> number   -- FNV-1a 32-bit over the tostring() of all parts
```
Implementation with `bit32` (e.g. xorshift32 or mulberry32). Same seed ⇒ same sequence on every platform.

## 4. Core/Env

```lua
Env.getService(name: string) -> Instance   -- override table first, else game:GetService(name)
Env.override(name: string, value: any)      -- tests
Env.reset()
Env.isStudio() / Env.isRunning() / Env.isClient() / Env.isServer() -> boolean  -- pcall-wrapped RunService calls
Env.now() -> number                         -- os.clock()
```

## 5. Core/Json (canonical encoder + strict parser)

```lua
Json.encode(value: any, options: { pretty: boolean?, keyOrder: { string }? }?) -> string
Json.decode(text: string) -> (boolean, any)  -- (true, value) | (false, "line L, column C: message")
Json.EMPTY_OBJECT   -- sentinel table, encodes as {}
Json.NULL           -- sentinel; decode() yields it for null inside arrays, omits null object members
Json.isArray(t) -> boolean
```
* Arrays: tables with keys exactly 1..n (n ≥ 1). Empty table encodes as `[]` (use `EMPTY_OBJECT` for `{}`).
  Mixed/sparse tables → error.
* Object keys must be strings. Order: `options.keyOrder` (default `Constants.KEY_ORDER`) then alphabetical.
* Numbers: integers (|x| < 2^53) without decimals; otherwise rounded to 6 decimals, trailing zeros stripped
  (`0.1`, `2.5`, `1e-7` → `0`). `-0` → `0`. NaN/±inf → error.
* Strings: escape `"` `\` and control characters (`\n`, `\t`, `\r`, `\b`, `\f`, others `\u00XX`); keep UTF-8.
* Pretty (default `true`): 2-space indent; arrays of only scalars with ≤ 8 elements on one line (`[1, 2, 3]`);
  arrays whose elements are all such short scalar arrays print one element per line. Non-pretty: no whitespace.
* Decode: RFC 8259 strict (no comments, no trailing commas), `\uXXXX` incl. surrogate pairs → UTF-8, leading UTF-8
  BOM ignored, depth limit 200, error messages with line/column.
* Round trip: `decode(encode(x))` deep-equals `x` for all supported values; `encode(decode(s))` is canonical.

## 6. Core/Codec (JSON form ⇄ Roblox datatypes)

```lua
Codec.check(kind, value, spec: PropertySpec?) -> (boolean, string?)   -- JSON form only, pure Luau
Codec.decode(kind, value, spec: PropertySpec?, palette: { [string]: Color3 }?) -> any
Codec.encode(kind, robloxValue, spec: PropertySpec?) -> any            -- canonical JSON form
Codec.normalize(kind, value, spec: PropertySpec?) -> any               -- canonical JSON form of a JSON value
Codec.default(spec: PropertySpec) -> any                               -- deep copy of spec.default
Codec.parseColor(value, palette?) -> Color3?   ;  Codec.toHex(Color3) -> "#RRGGBB"
Codec.lerp(kind: ChannelKind, a, b, alpha) -> any                     -- number/Vector3/Color3; boolean = step
```
JSON forms per kind (decode clamps to `spec.min/max` where given):

| kind | accepted JSON | canonical | decoded |
|---|---|---|---|
| number | finite number | number | number |
| integer | whole number | number | number |
| boolean | true/false | bool | boolean |
| string | string | string | string |
| enum | name ∈ spec.enum | name | `Enum[spec.enumType][name]` (string if no enumType) |
| color3 | `"#RRGGBB"`, `"#RGB"`, `[r,g,b]` 0–255, `"$key"` | `"#RRGGBB"` / `"$key"` | Color3 |
| vector3 | `[x,y,z]` or number | `[x,y,z]` | Vector3 |
| vector2 | `[x,y]` or number | `[x,y]` | Vector2 |
| numberRange | n or `[min,max]` (min ≤ max) | n if min==max else `[min,max]` | NumberRange |
| numberSequence | n or `[[t,v,(e)],…]` 2..20 keys, t ascending, first 0, last 1, e ≥ 0 | same | NumberSequence |
| colorSequence | colour or `[[t,colour],…]` same rules | same | ColorSequence |
| asset | `"rbxassetid://123"`, `"rbxasset://…"`, `"http(s)://www.roblox.com/asset/?id=123"`, `""`, integer 123 | string | string |
| componentRef | component id string or `""` | same | string |

## 7. Core/Easing

```lua
Easing.STYLES = { "Linear","Constant","Sine","Quad","Cubic","Quart","Quint","Exponential","Circular","Back","Elastic","Bounce" }
Easing.DIRECTIONS = { "In", "Out", "InOut" }   -- Enum.EasingDirection has no OutIn
Easing.check(def: EasingDef?) -> (boolean, string?)
Easing.parse(def: EasingDef?) -> (EasingFn, boolean)   -- (fn, isConstant); nil => Linear; invalid => error
Easing.get(style: string, direction: string?) -> EasingFn   -- direction default "Out"
Easing.bezier(x1, y1, x2, y2) -> EasingFn              -- x in [0,1]; Newton + bisection; monotone in x
Easing.normalize(def) -> EasingDef                     -- canonical ("Quad" -> "Quad" ; "quad.out" invalid)
```
Formulas follow the Roblox `Enum.EasingStyle` curves (Penner equations; Back s = 1.70158; Exponential uses
2^(10(t−1)) with exact endpoints; Elastic: amplitude 1, period 0.3 for In/Out). `f(0)=0`, `f(1)=1` exactly for
every style. `Constant` returns 0 until the segment ends (step).

## 8. Core/Curves

```lua
Curves.compileTrack(def: TrackDef, spec: ChannelSpec, palette, scale: number) -> CompiledTrack
  -- decodes values with Codec, multiplies "length" channels by `scale`, stable-sorts keys by time,
  -- resolves easing via Easing.parse
Curves.evaluate(track: CompiledTrack, localTime: number) -> any
  -- before first key: first value; after last: last value; between: lerp(a, b, ease(alpha)); constant: a
Curves.evaluateNumberSequence(seq: NumberSequence, t: number) -> number
Curves.evaluateColorSequence(seq: ColorSequence, t: number) -> Color3
Curves.sample(track: CompiledTrack, t0: number, t1: number, n: number) -> { any }
```
Binary search on keys (tracks may have up to 256 keys).

## 9. Core/Timeline

```lua
Timeline.span(def: EffectDefinition, comp: ComponentDef) -> (number, number)  -- absolute [start, end), clamped
Timeline.isActive(c: CompiledComponent, t: number) -> boolean
Timeline.staticSchedule(components: { CompiledComponent }, markers: { MarkerDef }) -> { ScheduledAction }
  -- component events (absolute time = start + event.time, events outside the span dropped)
  -- + marker events (action "fire", name = marker.event) ; sorted (time, order)
Timeline.sort(actions)                     -- stable: time, then order
Timeline.range(actions, t0, t1, includeStart: boolean) -> (number, number)  -- index range with t0 < time <= t1
Timeline.snap(t, options: { grid: number?, targets: { number }?, tolerance: number? }) -> number
Timeline.format(t: number) -> string       -- "1.25s"
```

## 10. Core/Components (registry) — already implemented

See `src/Runtime/Core/Components/init.luau`, `Common.luau` and the reference `Group.luau`. Each descriptor module
returns a `Types.ComponentDescriptor`. Descriptor rules:

* `properties`: every JSON key the component reads, with kind, default, description, ranges, `scale = "length"`
  for distances/sizes/speeds/widths/ranges, `quality = "count"|"segments"` where quality scaling applies.
  `"segments"` marks procedural subdivisions only (ring segments, lightning points, shockwave layers):
  `beam.segments` (Beam.Segments) is deliberately NOT quality-scaled — the engine lowers beam segments itself at low
  graphics quality, and a gradient with n keypoints needs at least n − 1 segments (constraints K14, ARCHITECTURE
  §5.4); the beam controller enforces that floor.
* `channels`: animatable channels. Positioned components include `Common.transformChannels()`. Semantics:
  * part-like (`part`, `mesh`, `sphere`, `flash`, `shockwave`, `ring`, `radialBurst`, `debris`, `lightning` in part
    mode): `transparency` sets Part.Transparency directly; `color` sets Part.Color.
  * sequence-based (`particles`, `beam`, `trail`): `transparency` is a fade combined with the authored sequence
    (`Common.fadeSequence`), `tint` multiplies the authored colour sequence (`Common.tintSequence`).
  * `scale`: uniform multiplier of the component's own size-like values.
* `events`: actions the component accepts (`emit`, `clear`, `enable`, `disable`, `play`, `stop`, `regenerate`, …).
* `build(ctx, component)`: create instances with `Common.newPart/newAttachment`, return a controller from
  `Common.controller`. The controller must be invisible/non-emitting until `setActive(true)`, must apply channel
  values only when they change (cache last values), and must append moving parts to `frame.moveParts` instead of
  setting `CFrame` directly.
* `estimateCost(component, quality)`: heuristic `CostEstimate` (counts of instances, emitters, beams, parts…, rates).
  Its `lights` count is exact and authoritative: the Compiler's light budget (§15) uses it. A component that builds
  an optional light of its own (`sphere`, `flash`) declares a boolean property `light`, so the budget can switch the
  light off instead of dropping the component.
* `tailTime(component)`: seconds visuals outlive the span (particles: `lifetime.Max`, trails: `lifetime`).
* Components must work in Studio edit mode (no physics, no `Touched`, no yields).
* `setTimeScale(scale)` (optional controller method, `Types.ComponentInstance`): `scale` is the effect's effective
  time scale — definition `timeScale` × Play option `TimeScale` × `handle:SetTimeScale`, and 0 while paused. Components
  whose engine instances run on their own clock scale their authored values with it: `particles`
  ParticleEmitter.TimeScale = clamp(clamp(timeScale, 0, 1) × scale, 0, 1) — the engine range ends at 1, so slow motion
  and pause work but particles can never run faster than normal speed —, `beam` TextureSpeed = textureSpeed × scale,
  `lightning` (beam render) TextureSpeed = 1 (engine default) × scale. A build starts at the definition's
  `timeScale`, `reset()` returns to it, invalid values (negative, NaN, ±inf) are ignored, writes happen only when the
  value changes. The Player calls it in `start()`, on `pause()` / `resume()` / `setTimeScale()` / `stop()` when the
  value changed (never per frame) and after `seek()` (§17). Trails have no time factor (they age in real time) and
  sounds keep their PlaybackSpeed, so they do not implement it.
* Camera components (`cameraShake`, `screenFlash`; COMPONENTS_SPEC §17–18) are client-only and own nothing in the
  container: the shake holds `RunService:BindToRenderStep` bindings while active (shared by all active shakes), the
  flash a `ColorCorrectionEffect` under `workspace.CurrentCamera` while it shows (listed in `controller.instances`
  only then). The Player must therefore call `setActive(false)` / `release()` / `destroy()` reliably and `update()`
  every frame while they are active.

## 11. Core/Graph

```lua
Graph.NodeTypes.get(type) -> NodeType? ; Graph.NodeTypes.list() -> { NodeType }
NodeType = { type, displayName, category, description, inputs: { Pin }, outputs: { Pin }, params: { PropertySpec } }
Pin = { name, kind: "exec"|"number"|"vector3"|"color3"|"boolean"|"string"|"component"|"any", label: string?,
        componentTypes: { string }? }
Graph.parseRef("node.pin") -> (nodeId, pinName)?
Graph.validate(graph: GraphDef, def: EffectDefinition) -> { Diagnostic }
Graph.canConnect(graph, def, from: string, to: string) -> (boolean, string?)   -- live editor check
Graph.findCycle(graph) -> { string }?                                          -- node ids of one cycle
Graph.compile(graph, def) -> CompiledGraph      -- assumes validate() passed
Graph.run(compiled: CompiledGraph, trigger: { kind: "play"|"marker"|"event", id: string? },
          startTime: number, seed: number, cycle: number, effect: CompiledEffect?) -> (ActionList, RunInfo)
Graph.staticSchedule(compiled, seed, cycle, effect?) -> (ActionList, RunInfo)   -- play at 0 + every marker trigger
```
Semantics (time-based unrolling, no threads): `OnPlay` fires at 0; `OnMarker(marker)` at the marker time;
`OnEvent(name)` at the runtime trigger time; `Delay(seconds)` adds time; `Sequence(count, interval)` fires `then1..N`
at t + (i−1)·interval; `Parallel(count)` fires `out1..N` at t; `Loop(count ≤ 100, interval)` fires `body` per
iteration (data output `index`, 0-based) and `completed` at t + count·interval; `RandomBranch(count, weights?)`
fires one output; `RandomNumber(min, max)`; `Number/Vector/Color(value)`; `Math(op ∈ add,sub,mul,div,min,max,pow,
lerp(a,b,t))`; `Component(component)` outputs a component id; actions `Emit(target, count)`,
`SetEnabled(target, enabled)`, `Tween(target, channel, value, duration, easing)` (outputs `out` now and `done` after
duration), `SetProperty(target, channel, value)`, `FireEvent(name)`, `PlaySound(target)`, `Regenerate(target)`.
Unlinked data inputs fall back to the param with the same name, then the pin default. Random values are
deterministic per (seed, cycle, trigger, node id, invocation index) — the trigger key keeps flows of different
triggers (and repeated event fires) independent. Exceeding `MAX_GRAPH_ACTIONS` (or the work budget
`Graph.MAX_WORK` / queue bound `Graph.MAX_PENDING`) stops unrolling: the returned list (an `ActionList` — a plain
array of ScheduledActions) is flagged `list.truncated`, and the second return value `RunInfo = { truncated, actions,
work, diagnostics }` carries a `graph.action_limit` warning. Further extensions (see `Core/Graph/init.luau`):
`Graph.triggers`, `Graph.resolveParamSpec`, `Graph.pinKind`, and `canConnect` returns a third value, the diagnostic
code of the failed rule.

Quality and scale of graph values: when `run()` gets the compiled effect, `Emit` counts are × `effect.quality
.countScale` (rounded, at least 1; 0 emits nothing), Tween / SetProperty values of number channels whose base
property has `quality = "count"` (particles `rate`) get the Compiler's count rule (v × countScale, at least min(v, 1)
when v > 0) and "length" channels are × `effect.scale` — graph values share the compiled domain of the channel's
tracks (§15).

`SetEnabled(target, enabled)` works on every component type, as the Player executes it (§17): types that declare
the `enable` / `disable` events (particles, beam, trail, light) receive the action through `onAction` (emission /
visibility toggles while the span stays active); every other type is switched off by the Player (`setActive(false)`
at once; the component stays dark) and back on with the next evaluation (`enable`: it activates again inside its
span, so its activation behaviour — bursts, `playOnStart`, `clearOnStart` — runs again). Loop cycles and `seek()`
clear the switched-off state. `Graph.validate` therefore reports `graph.action_unsupported` for SetEnabled only on
structure types (`group`): a group has no visuals of its own and SetEnabled does not switch its children.

## 12. Core/Migration

```lua
Migration.CURRENT -> number   (= Constants.SCHEMA_VERSION)
Migration.migrate(raw: any) -> (EffectDefinition?, { Diagnostic })
```
Never mutates the input (deep copy). Missing `schemaVersion` ⇒ treated as version 0 (info diagnostic).
`schemaVersion > CURRENT` ⇒ error diagnostic, nil. Version 0 is the pre-release "concept" format (the example in the
project brief): components without ids get slug ids, `properties.color: [r,g,b]` → `"#RRGGBB"`,
`sphere` `initialScale/finalScale` → a `scale` track from initialScale to finalScale over the component duration,
missing `id` ⇒ slug of `name`. Each migration step appends info diagnostics describing what changed.
Extension: `raw` may also be JSON text (decoded with Core/Json; invalid text ⇒ `migration.json` error, nil).

## 13. Core/Validation

```lua
Validation.validate(def: any, options: { strict: boolean? }?) -> ValidationResult
```
Pure (no Roblox instances) and total: it never throws, whatever `def` is. Uses the registry specs, `Codec.check`,
`Easing.check`, `Graph.validate`. Codes (stable; the complete table with severities is the header of
`Core/Validation.luau` and, machine-readable, `Validation.CODES` — the source of docs/EFFECT_FORMAT.md): `effect.*`
(including `effect.internal` — the validator itself failed on part of the input, reported instead of thrown — and
`effect.json` — a value that is not plain JSON where no specific check looks; reported once, only without other
errors), `component.*`, `property.unknown|type|range|ref`, `track.*`, `keyframe.*`, `event.*`, `marker.*`,
`quality.*`, every `graph.*` code of `Graph.validate` unchanged, lints `lint.trail_static`, `lint.particles_silent`,
`lint.zero_width`, `lint.outside_duration`, `lint.flash_short`, `lint.filemesh_no_id`. Unknown properties are
warnings (errors when `strict`). Paths use 1-based indices: `components[3].tracks[1].keyframes[2].value`.

## 14. Core/Quality

```lua
Quality.PROFILES: { Low: QualityProfile, Medium: QualityProfile, High: QualityProfile }   -- see ARCHITECTURE §5.4
Quality.resolve(level: (QualityLevel | "Auto")?, overrides: { [string]: QualityProfileOverride }?) -> QualityProfile
Quality.detect() -> QualityLevel     -- client: UserGameSettings.SavedQualityLevel (pcall), else "Medium"
Quality.rank(level) -> number        -- Low 1, Medium 2, High 3
Quality.includes(level, minQuality: QualityLevel?) -> boolean
```
High's unlimited `maxLights` is `math.huge`. Extension: `resolve` also accepts a `QualityProfile` table as the base
(Compiler `options.quality`); see the header of `Core/Quality.luau` for the override rules and the detect() mapping.

## 15. Core/Compiler

```lua
Compiler.compile(def: EffectDefinition, options: { quality: (QualityLevel | "Auto" | QualityProfile)?, scale: number?,
                 palette: { [string]: Color3 }?, seed: number? }?) -> (CompiledEffect, { Diagnostic })
Compiler.scheduleForCycle(compiled, cycle: number) -> { ScheduledAction }   -- read-only; the Player's loop cycles
Compiler.key(def, options?, contentHash: string?) -> string   -- cache key (id + content hash + options)
Compiler.contentHash(def) -> string                           -- callers with immutable definitions compute it once
```
Assumes a migrated + validated definition (defensive anyway: on unvalidated input it skips what it cannot use).
Steps: palette (definition + overrides) → topological order (parents first, otherwise definition order) → component
filter (enabled, minQuality; children of removed parents are removed) → per component: defaults + decode
(`Codec.decode`), `qualityOverrides`, quality rules (count/segments; not for values that come from
`qualityOverrides`), effect scale for `scale = "length"` properties/channels/positions → light budget (below) →
tracks (`Curves.compileTrack`; a number channel whose base property has a quality rule — particles `rate` — gets the
same rule on every keyframe value, so tracks, graph values and the rest value share the compiled domain) → events
(emit counts × countScale, min 1; 0 stays 0) → schedule = `scheduleForCycle(compiled, 0)` (`Timeline.staticSchedule`
merged with `Graph.staticSchedule`; at equal times timeline actions first, `order` renumbered) → `maxTail`.
`seed` = options.seed or def.seed or `Random.hash(def.id)`; per component `Random.hash(seed, component.id)`.

Light budget (`quality.maxLights`, skipped when unlimited): in component order, every built component's lights are
counted with its descriptor's `estimateCost(component, quality).lights` — `light` components and the built-in
PointLights of `sphere` / `flash`. A component whose lights no longer fit is built without them when its descriptor
declares a boolean property `light` (`props.light = false`), otherwise (`light` components) it is dropped together
with its descendants. The budget is a hard cap (a `qualityOverrides` value `light = true` is switched off too).

`scheduleForCycle(compiled, cycle)`: the static schedule of loop cycle `cycle` (graph random values depend on
(seed, cycle)); without a graph, or for cycle 0, it returns `compiled.schedule` itself, otherwise a fresh list.

The second return value of `compile()` lists warnings: graph unrolling limits (`graph.action_limit`) and, on
unvalidated input, skipped components / tracks (`compiler.component_id`, `compiler.parent`, `compiler.component_type`,
`compiler.parent_cycle`, `compiler.track_channel`, `compiler.track_duplicate`). The runtime ignores them (definitions
are validated at registration); tools can show them.

## 16. Core/Builder

```lua
Builder.build(compiled: CompiledEffect, options: { parent: Instance?, isPreview: boolean?, viewport: boolean?,
              name: string? }?) -> BuiltEffect
BuiltEffect = { container: Folder, root: BasePart, controllers: { [string]: ComponentInstance },
                order: { string }, destroy: (self) -> () }
-- extensions: effect: CompiledEffect, isPreview, viewport, destroyed: boolean,
--             reset: (self) -> ()   -- controller:reset() in build order (Core/Pool, Player:seek)
```
Container `Folder` "AstraVFX_<name>" with attribute `AstraEffect`; preview: `Archivable = false` on every created
instance + attribute `AstraPreview`. Root: anchored invisible 0.2-stud Part "Root" (same physics-free settings as
`Common.newPart`). Every instance gets `AstraComponent = <id>`. In viewport mode, components whose descriptor has
`supportsViewport = false` get a placeholder controller (small neon marker, visible while active).

## 17. Core/Player

```lua
Player.new(compiled, built, options: { cframe: CFrame?, attach: Instance?, offset: CFrame?, timeScale: number?,
           loop: boolean?, onEvent: ((string) -> ())?,
           release: ((built) -> boolean)?,   -- extension: hands the copy back (Core/Pool); true = taken
           autoRelease: boolean? }) -> Player -- extension (default true): false keeps the copy after the end
player:start() ; player:step(dt) -> boolean (alive) ; player:seek(t) ; player:pause() ; player:resume()
player:stop(fade: number?) ; player:destroy() ; player:setTimeScale(n) ; player:setCFrame(cf) ; player:setLoop(b)
player:fire(name)                       -- graph OnEvent trigger
player:isLooping() ; player:getRootCFrame() ; player:isAlive() ; player:lastMoveCount()   -- extensions
player.time, player.state (Types.PlayerState), player.cycle
player.finished: Signal(reason: "finished" | "destroyed") ; player.event: Signal(name)
player.actionExecuted: Signal(ScheduledAction)
```
Frame algorithm: ARCHITECTURE §5.2; the full rules are in the header of `Core/Player.luau`. Transform: if a
`position`/`rotation` track exists its value replaces the rest value; `spin × localTime` is added to rotation;
`local = parentLocal * CFrame.new(pos) * fromOrientation(rot)`. Graph `tween`/`set` actions create per-(component,
channel) overrides evaluated after tracks. `start()` only poses the copy at t = 0; the first `step()` activates
components and runs the actions at 0 (never in the frame the copy was built, K6). `seek(t)` resets the copy
(`built:reset()`), replays the state-changing actions before `t` (overrides, enable/disable, clear, regenerate,
stop; never emit, play or fire) and evaluates the complete state at `t` with `frame.seeking = true` and no emission;
particles are cleared. The instance state depends only on (t, cycle) — except the engine clock values
(ParticleEmitter.TimeScale, Beam.TextureSpeed), which follow the play state (0 while paused).

`SetEnabled` / `enable` / `disable` on a type that does not declare the event switch the component off / on through
its activation (§11).

Time scale: the effective rate is `options.timeScale / setTimeScale(n)` × `compiled.timeScale` (clamped to
`Constants.MAX_TIME_SCALE`); 0 while paused. It advances the effect clock and reaches the engine clocks of the copy
through `controller:setTimeScale(rate)` (§10) in `start()`, on `pause()` (0) / `resume()` / `setTimeScale()` /
`stop()` when it changes (stopping a paused copy thaws it, so its live particles can finish), and after `seek()`.
Pause freezes the effect time and, through that hook, live particles and texture scrolling; activation does not
change while paused.

End and stop: after `duration` (no loop) the player waits for the tail, then finishes; `stop(fade?)` `release()`s
every controller (no new emission, live particles finish), runs no more actions and finishes after `fade` real
seconds (default: the tail at the current rate; 0 = now). The tail is REAL seconds:
`maxTail / clamp(rate, 0.1, 1)` (particles age at most at the rate), recomputed by `setTimeScale`. Finishing hands
the copy to `options.release` (pool) or destroys it.

Loop: when the time reaches `duration`, the components are evaluated at `duration` first (end-of-cycle evaluation,
like the last frame of a one-shot effect: spans ending there deactivate, a span lying inside the frame is still
activated once), the remaining actions (t_prev, duration] run, `cycle` increments, the schedule becomes
`Compiler.scheduleForCycle(compiled, cycle)` and the time wraps. The cycle state is reset: active components are
deactivated (they re-activate, so bursts and `playOnStart` happen every cycle), overrides and SetEnabled states are
cleared, components disabled by a `disable` event get a synthetic `enable`, pending runtime actions move back by one
duration. At most 64 wraps per step (`Player.MAX_WRAPS`).

User callbacks — `options.onEvent` and the handlers of `finished` / `event` / `actionExecuted` — are dispatched with
`task.spawn`: immediately and in order (non-yielding handlers behave exactly like a synchronous call), but a
handler that yields suspends only its own thread, never the Scheduler frame. (Core/Signal's own `Fire` stays
synchronous, §2.) `onEvent` errors are caught and reported with `warn()`; controller errors propagate (the Scheduler
isolates failing players).

## 18. Core/Scheduler & Core/Pool

```lua
Scheduler.add(player) ; Scheduler.remove(player) ; Scheduler.count() -> number
Scheduler.step(dt)                      -- manual stepping (tests / editor)
Scheduler.setEventName("Heartbeat" | "PreRender")
```
Exactly one RunService connection while ≥ 1 player is registered; disconnected when empty. dt is clamped to
[0, 0.1]. A failing player is removed and destroyed (error reported with warn), others continue. A player added in
a frame is activated at the end of the next `step()` and stepped from the one after it, so it is never stepped in
the frame its copy was built (K6). Extensions: `Scheduler.getEventName()`, `isConnected()`, `players()`, `clear()`.
```lua
Pool.acquire(key) -> BuiltEffect? ; Pool.release(key, built) -> boolean ; Pool.prewarm(key, factory, count)
Pool.clear(key?) ; Pool.setCapacity(n, key?)   -- default 2 per key; released copies are reset() and parented to nil
Pool.capacity(key?) ; Pool.count(key?)
```
`release` returns false when it does not take the copy (pool full, copy destroyed, already pooled, reset failed);
the caller then destroys it — the pool never destroys what it did not take. `acquire` is LIFO.

## 19. Runtime API (src/Runtime/init.luau) and Net

Public API as in ARCHITECTURE §5.3 (the full contract is the header of `src/Runtime/init.luau`). `Play` errors on
unknown names and invalid options (`TryPlay` returns `nil, err`). Effects found in `script.Effects` (ModuleScripts
returning definitions, StringValues with JSON text, folders of them) are registered lazily. Registration migrates +
validates and errors with a readable diagnostic summary on invalid definitions.

Compiled variants are cached by `Compiler.key` (content hash computed once per registration, at most 64 variants;
the oldest is dropped with its pooled copies). An effect copy goes back to the pool when it ends (finish, Stop,
Destroy) only while its cache entry exists and its container is still parented: a container removed from the outside
(cleared folder, destroyed parent such as a respawned character) is destroyed, never pooled.

Active-effect cap: `AstraVFX.SetMaxActive(n)` (whole number ≥ 1 or `math.huge` = unlimited; default 64,
`AstraVFX.DEFAULT_MAX_ACTIVE`) / `AstraVFX.GetMaxActive()`. An effect counts while it is playing or paused (not once
it is stopping, finished or destroyed; `ActiveCount()` also includes the stopping ones that linger for their tail).
When a `Play` would make more than n effects count, the oldest counting effects that do not loop
(`Player:isLooping()`) are stopped gracefully with `Stop()` — as many as needed, normally one — and the new effect
plays. When the looping effects alone fill the cap, nothing is stopped and the new play is refused: `warn()`, `Play`
returns nil (its return type is `Handle?`), `TryPlay` returns `(nil, "limit")`. Lowering the cap does not touch
running effects; it applies to the next `Play`. Name and option errors are checked before the cap. The cap decides
before compiling (a refused play builds nothing); the evicted effects are stopped only once the new copy and its
player exist, so a play that fails on the way (compile / build error) stops nothing.

`Net` (src/Runtime/Net.luau): server `Net.Init()`, `Net.PlayAll(name, opts)`, `Net.PlayFor(players, name, opts)`,
`Net.PlayNear(position, radius, name, opts)`; client `Net.Listen()`. Uses a RemoteEvent (and an
UnreliableRemoteEvent for `opts.Unreliable`) created by the server under the module. Serializable options only:
`CFrame`, `Position`, `Attach` (Instance reference), `Scale`, `TimeScale`, `Seed`, `Quality`. Client clamps `Scale`
to [0.05, 20], `TimeScale` to [0.05, 10] and ignores unknown names. A play the client's cap refuses is counted in
`Net.stats.ignored` (the runtime has warned already).

## 20. Authoring

```lua
Ids.slug(text) -> string ; Ids.unique(base, taken: { [string]: boolean }) -> string
Ops.newEffect(name: string, options: { duration: number?, id: string? }?) -> EffectDefinition
Ops.clone(doc) -> EffectDefinition ; Ops.find(doc, id) -> (ComponentDef?, number?)
Ops.children(doc, id?) -> { ComponentDef } ; Ops.descendants(doc, id) -> { ComponentDef }
Ops.addComponent(doc, type, options: { name: string?, parent: string?, startTime: number?, duration: number?,
                 properties: { [string]: any }?, index: number? }?) -> string
Ops.removeComponents(doc, ids: { string })        -- also removes descendants, graph refs become "" (warned)
Ops.duplicateComponents(doc, ids) -> { string }    -- new ids, keeps hierarchy, name suffix " Copy"
Ops.renameComponent(doc, id, name) ; Ops.setEnabled(doc, ids, enabled) ; Ops.setParent(doc, id, parentId?)
Ops.moveComponent(doc, id, newIndex) ; Ops.setTiming(doc, id, startTime?, duration?)
Ops.setTransform(doc, id, field: "position"|"rotation"|"scale", value)
Ops.setProperty(doc, ids, name, jsonValue) ; Ops.resetProperty(doc, ids, name)
Ops.addKeyframe(doc, id, channel, time, value, easing?) -> { trackId: string, index: number }
Ops.removeKeyframes(doc, refs: { KeyframeRef }) ; Ops.moveKeyframes(doc, refs, dt) -> { KeyframeRef }
Ops.setKeyframe(doc, ref, fields: { time: number?, value: any?, easing: EasingDef? }) -> KeyframeRef
Ops.addEvent(doc, id, action, time, fields?) -> string ; Ops.removeEvents(doc, refs) ; Ops.moveEvent(doc, ref, time)
Ops.addMarker(doc, time, label, fields?) -> string ; Ops.removeMarker(doc, id) ; Ops.setMarker(doc, id, fields)
Ops.setEffectField(doc, field, value)   -- name, description, duration, loop, seed, timeScale, palette, tags
Ops.addNode(doc, type, position) -> string ; Ops.removeNodes(doc, ids) ; Ops.moveNodes(doc, ids, delta)
Ops.setNodeParam(doc, id, name, value) ; Ops.connect(doc, from, to) -> (boolean, string?) ; Ops.disconnect(doc, from?, to)
Ops.copyComponents(doc, ids) -> ClipboardPayload ; Ops.pasteComponents(doc, payload, parent?) -> { string }
Ops.copyKeyframes(doc, refs) -> ClipboardPayload ; Ops.pasteKeyframes(doc, payload, atTime, targetId?) -> { KeyframeRef }
KeyframeRef = { component: string, track: string, index: number }
```
All Ops mutate the passed document (callers pass a working copy) and keep it valid where possible (ids unique,
keyframes sorted, times clamped ≥ 0). Unknown ids are programmer errors (`error`).

```lua
Analyzer.analyze(def, options: { quality: QualityLevel?, sampleRate: number? }?) -> AnalysisReport
Exporter.toJson(def) -> string                 -- canonical, pretty, trailing newline
Exporter.toLuau(def) -> string                 -- "return { ... }" canonical Luau module source with header comment
Exporter.buildRuntimePackage(runtimeModule: ModuleScript, defs: { EffectDefinition }) -> ModuleScript
Exporter.buildStaticModel(def, options: { time: number?, quality: QualityLevel? }?) -> Model
Generator.generate(prompt: string, options: { name: string?, seed: number? }?) -> (EffectDefinition, GeneratorReport)
PresetLibrary.list() -> { PresetInfo } ; PresetLibrary.get(nameOrId) -> EffectDefinition?
  -- presets are src/Presets/<Name>.vfx.json, synced by Rojo syncRules as StringValues (raw JSON text)
Diagnostics.format(list: { Diagnostic }) -> string ; Diagnostics.summary(result: ValidationResult) -> string
```
