# Component Specification (engineering spec, schema v1)

> Implementer-facing (English). Every component type is one descriptor module in
> `src/Runtime/Core/Components/<Type>.luau` (file name PascalCase, `type` camelCase). The descriptor is the single
> source of truth: the Inspector, Validation, the JSON schema, `docs/EFFECT_FORMAT.md` and the generator all read it.
> Engine facts referenced here are sourced in `docs/research/*.md` and `docs/ROBLOX_API_CONSTRAINTS.md`.

## 0. Shared rules

* JSON keys are camelCase. Defaults follow Roblox's `Instance.new` defaults for 1:1 mapped properties unless stated.
* `scale = "length"` marks studs/speeds/widths/ranges: multiplied by the effect scale at compile time (the Compiler
  does this; descriptors receive already-scaled `props`). The component's own `scale` channel / `transform.scale` is a
  runtime multiplier the controller applies itself (`component.scale` is the rest value).
* `quality = "count"` → × `countScale` (rounded, keeps ≥ 1 when > 0); `quality = "segments"` → × `segmentScale`
  (rounded, min given by the property's `min`). Applied by the Compiler.
* Particles additionally multiply `size` by `quality.sizeCompensation` themselves (keeps silhouette when counts drop).
* Every instance is created through `Common.newPart` / `Common.newAttachment` (physics-free, tagged) or tagged with
  `ctx.tagInstance`. Instances must be invisible / disabled until `setActive(true)`.
* Controllers cache the last applied value per channel and skip identical writes (property writes cost).
* Moving parts go through `frame.moveParts`/`frame.moveCFrames` (one `BulkMoveTo` per frame). Attachments are
  positioned by setting `Attachment.CFrame` (relative to the effect Root part).
* Procedural components are pure functions of `(localTime, seed, props, channel values)`. `update(localTime, frame)`
  must produce the same visual state for the same `localTime` regardless of the frame history (scrubbing).
* `setActive(false)` hides everything (parts `Transparency = 1`, emitters/beams/trails/lights `Enabled = false`).
* `reset()` restores the freshly built state (used by the pool); particles/trails `Clear()`.
* `estimateCost` returns a heuristic `CostEstimate` (counts are exact for the built instances; per-frame and
  overdraw numbers are heuristics and must be labelled as such in the Analyzer).
* `supportsViewport`: only geometry types (`group`, `part`, `mesh`, `sphere`, `flash`, `shockwave`, `ring`,
  `radialBurst`, `debris`, `lightning` in `part` render mode). Particles, beams, trails and lights do not render in a
  ViewportFrame (REPORTED, see constraints doc).
* Camera types (`cameraShake`, `screenFlash`, §17–18) are client-only: they act on `workspace.CurrentCamera`, never
  build anything in the container, are a no-op without `Players.LocalPlayer` (servers, Studio edit mode outside the
  preview) and reach services only through Core/Env (`Common.tryService`, `Common.hasLocalPlayer`,
  `Common.currentCamera`), so specs can substitute clients, servers and cameras.
* `spin` (vector3, deg/s) is applied by the Player generically (`rotation += spin × localTime`) for every component
  whose `props.spin` is a Vector3; descriptors just declare it (`Common.spinProperty()`).
* Channels common to positioned types: `position` (vector3, length), `rotation` (vector3 deg), `scale` (number ≥ 0).
  Channel value semantics for appearance:
  * Part-like types: `transparency` = Part.Transparency (overrides the property while tracked), `color` = Part.Color.
  * Sequence-based types (particles, beam, trail): `transparency` = fade combined with the authored sequence
    (`Common.fadeSequence`), `tint` multiplies the authored colour sequence (`Common.tintSequence`).

## 1. `group` (Structure) — implemented

Properties: `spin`. Channels: `position`, `rotation`. No instances at runtime; in preview a visible Attachment gizmo.

## 2. `particles` (Particles) → ParticleEmitter

Instances: if `shape == "Point"`: Attachment on Root + ParticleEmitter in it. Otherwise: invisible host Part
(`Common.newPart`, size `emitterSize × scale`) placed via `moveParts`, ParticleEmitter in it with `Shape` set
(Sphere/Cylinder shapes require a BasePart parent — engine fact).

| key | kind | default | range / notes | Roblox |
|---|---|---|---|---|
| texture | asset | `"rbxasset://textures/particles/sparkles_main.dds"` | | Texture |
| color | colorSequence | `"#FFFFFF"` | | Color |
| transparency | numberSequence | `0` | 0..1 | Transparency |
| size | numberSequence | `1` | 0..100, length | Size (× scale × sizeCompensation) |
| squash | numberSequence | `0` | −3..3, advanced | Squash |
| lifetime | numberRange | `[1, 2]` | 0..20 | Lifetime |
| rate | number | `20` | 0..400, count | Rate (continuous emission while active; 0 = bursts only) |
| burst | integer | `0` | 0..10000, count | particles emitted once when the component becomes active |
| speed | numberRange | `[5, 5]` | −1000..1000, length | Speed |
| spreadAngle | vector2 | `[0, 0]` | −360..360 | SpreadAngle |
| acceleration | vector3 | `[0, 0, 0]` | length | Acceleration |
| drag | number | `0` | 0..100 | Drag |
| rotation | numberRange | `[0, 0]` | −360..360 | Rotation |
| rotSpeed | numberRange | `[0, 0]` | −3600..3600 | RotSpeed |
| emissionDirection | enum NormalId | `"Top"` | | EmissionDirection |
| shape | enum | `"Point"` | Point, Box, Sphere, Cylinder, Disc | (Point = attachment) Shape |
| emitterSize | vector3 | `[1, 1, 1]` | 0..2048, length | host part Size |
| shapeStyle | enum ParticleEmitterShapeStyle | `"Volume"` | | ShapeStyle |
| shapeInOut | enum ParticleEmitterShapeInOut | `"Outward"` | | ShapeInOut |
| shapePartial | number | `1` | 0..1 | ShapePartial |
| orientation | enum ParticleOrientation | `"FacingCamera"` | | Orientation |
| lightEmission | number | `0` | 0..1 | LightEmission |
| lightInfluence | number | `0` | 0..1 | LightInfluence |
| brightness | number | `1` | 0..100 | Brightness |
| zOffset | number | `0` | −100..100 | ZOffset |
| timeScale | number | `1` | 0..1 (engine range) | TimeScale (× min(1, effect timeScale)) |
| lockedToPart | boolean | `false` | | LockedToPart |
| velocityInheritance | number | `0` | 0..1, advanced | VelocityInheritance |
| windAffectsDrag | boolean | `false` | advanced | WindAffectsDrag |
| flipbookLayout | enum ParticleFlipbookLayout | `"None"` | texture must be 1024×1024 | FlipbookLayout |
| flipbookMode | enum ParticleFlipbookMode | `"Loop"` | | FlipbookMode |
| flipbookFramerate | numberRange | `[1, 1]` | 0..30 | FlipbookFramerate |
| flipbookStartRandom | boolean | `false` | | FlipbookStartRandom |
| spin | vector3 | `[0,0,0]` | | (Player) |

Channels: transform + `transparency` (fade), `tint`, `rate`, `brightness`, `lightEmission`, `acceleration` (vector3,
length), `timeScale` (0..1). Events: `emit` (count, quality-scaled by Compiler), `clear`, `enable`, `disable`.
`tailTime = lifetime.Max`. `release()` sets `Enabled = false` (live particles finish). Continuous emission =
`Enabled = (active and rate > 0)`. Bursts: `burst` on activation and `emit` events call `Emit(n)` (engine caps:
400/s per emitter; an Emit in the same frame the emitter was parented can be ignored by the engine — the Player
never executes actions in the frame the effect was built).

## 3. `beam` (Beams & Trails) → Beam + 2 Attachments

Attachment0/1 on Root at `from`/`to` (component space × component transform). Beam parented to the Root part
(beams render only under Workspace). Geometry is a cubic Bézier: P1 = A0 + A0.Axis·CurveSize0, P2 = A1 −
A1.Axis·CurveSize1. ASTRA orients A0 with +X = `curveDirection` and A1 with +X = −`curveDirection`, so equal
`curveSize0/1` bend the beam into an arch towards `curveDirection`. `roll` rotates both attachments about the beam
axis (controls the ribbon plane when `faceCamera = false`; the engine does not document which axis is used, so
roll is empirical).

| key | kind | default | range | Roblox |
|---|---|---|---|---|
| from | vector3 | `[0, 0, 0]` | length | Attachment0 |
| to | vector3 | `[0, 0, -10]` | length | Attachment1 |
| curveDirection | vector3 | `[0, 1, 0]` | unit-ish | attachment axes |
| roll | number | `0` | −360..360 | attachment roll |
| texture | asset | `""` | | Texture |
| color | colorSequence | `"#FFFFFF"` | | Color |
| transparency | numberSequence | `0` | 0..1 | Transparency |
| width0 / width1 | number | `1` | 0..1000, length | Width0/Width1 (linear only — no width curve along the length) |
| curveSize0 / curveSize1 | number | `0` | −1000..1000, length | CurveSize0/1 |
| segments | integer | `10` | 1..1000 (NO quality scaling — the engine reduces beam segments itself; gradients need ≥ keypoints − 1) | Segments |
| textureLength | number | `1` | 0.01..1000, length | TextureLength |
| textureMode | enum TextureMode | `"Stretch"` | | TextureMode |
| textureSpeed | number | `1` | −100..100 | TextureSpeed |
| faceCamera | boolean | `true` | | FaceCamera |
| lightEmission | number | `0` | 0..1 | LightEmission |
| lightInfluence | number | `0` | 0..1 | LightInfluence |
| brightness | number | `1` | 0..100 | Brightness |
| zOffset | number | `0` | | ZOffset |
| spin | vector3 | `[0,0,0]` | | (Player) |

Channels: transform, `scale` (width multiplier), `transparency` (fade), `tint`, `width0`, `width1`, `curveSize0`,
`curveSize1`, `from`, `to`, `brightness`, `textureSpeed`. Events: `enable`, `disable`.

## 4. `trail` (Beams & Trails) → Trail + 2 Attachments

Attachments on Root at ±`width/2` along `widthDirection` around the component's position; the trail draws when the
component moves (animate `position`, use a spinning parent group, or attach the effect to a moving part).
Changing an attachment clears drawn segments (engine), so ASTRA only moves attachments via CFrame.

| key | kind | default | range | Roblox |
|---|---|---|---|---|
| width | number | `1` | 0..100, length | attachment separation |
| widthDirection | vector3 | `[0, 1, 0]` | | attachment axis |
| lifetime | number | `0.5` | 0.01..20 | Lifetime |
| minLength | number | `0.1` | 0..100, length | MinLength |
| maxLength | number | `0` | 0..10000, length (0 = unlimited) | MaxLength |
| widthScale | numberSequence | `1` | 0..1 | WidthScale |
| color | colorSequence | `"#FFFFFF"` | | Color |
| transparency | numberSequence | `0` | 0..1 | Transparency |
| texture | asset | `""` | | Texture |
| textureLength | number | `1` | length | TextureLength |
| textureMode | enum TextureMode | `"Stretch"` | | TextureMode |
| faceCamera | boolean | `false` | | FaceCamera |
| lightEmission | number | `0` | 0..1 | LightEmission |
| lightInfluence | number | `0` | 0..1 | LightInfluence |
| brightness | number | `1` | 0..100 | Brightness |
| clearOnStart | boolean | `true` | | `Clear()` when activated |
| spin | vector3 | `[0,0,0]` | | (Player) |

Channels: transform, `scale` (width multiplier), `width`, `transparency` (fade), `tint`, `brightness`.
Events: `enable`, `disable`, `clear`. `tailTime = lifetime`. Validation lint `lint.trail_static` when neither the
trail nor an ancestor has a position/rotation track or spin.

## 5. `part` (Geometry) → Part

| key | kind | default | range | Roblox |
|---|---|---|---|---|
| shape | enum PartType | `"Block"` | Block, Ball, Cylinder, Wedge, CornerWedge | Shape (PartType includes Wedge/CornerWedge in 0.745) |
| size | vector3 | `[1, 1, 1]` | 0.001..2048, length | Size (× scale) |
| color | color3 | `"#FFFFFF"` | | Color |
| material | enum Material | `"Neon"` | | Material |
| transparency | number | `0` | 0..1 | Transparency |
| reflectance | number | `0` | 0..1, advanced | Reflectance |
| castShadow | boolean | `false` | advanced | CastShadow |
| spin | vector3 | `[0,0,0]` | | (Player) |

Channels: transform, `size` (vector3 absolute, length), `transparency`, `color`. Size writes are costlier than CFrame
writes (REPORTED); the Analyzer counts them.

## 6. `mesh` (Geometry) → Part + SpecialMesh

`MeshPart.MeshId` is not writable by scripts or plugins (engine fact), so ASTRA uses `SpecialMesh` on an invisible-
collision Part. `SpecialMesh.Scale` is cheap to animate. For `Brick`/`Sphere`/`Wedge` the Scale multiplies the
part size; for `FileMesh` it is relative to the uploaded mesh. `BasePart.Material` does not render correctly on a
SpecialMesh (engine doc) — use `color`/`textureId`/`vertexColor`.

| key | kind | default | range | Roblox |
|---|---|---|---|---|
| meshType | enum MeshType | `"Sphere"` | Sphere, Cylinder, Brick, Wedge, FileMesh | SpecialMesh.MeshType |
| meshId | asset | `""` | required for FileMesh | MeshId |
| textureId | asset | `""` | | TextureId |
| partSize | vector3 | `[1, 1, 1]` | length | host Part Size |
| meshScale | vector3 | `[1, 1, 1]` | 0..10000 | SpecialMesh.Scale (× scale) |
| offset | vector3 | `[0, 0, 0]` | length | Offset |
| vertexColor | color3 | `"#FFFFFF"` | | VertexColor (as Vector3 r,g,b) |
| color | color3 | `"#FFFFFF"` | | Part.Color |
| material | enum Material | `"SmoothPlastic"` | | Part.Material |
| transparency | number | `0` | 0..1 | Part.Transparency |
| spin | vector3 | `[0,0,0]` | | (Player) |

Channels: transform, `meshScale`, `offset`, `transparency`, `color`, `vertexColor`. Validation: `FileMesh` without
`meshId` → warning.

## 7. `light` (Lighting) → Point/Spot/SurfaceLight

Point/Spot: Attachment on Root + light inside. Surface: invisible host Part (`surfaceSize`) + SurfaceLight. Local
lights only illuminate as direct children of a BasePart/Attachment under Workspace. Range max 120.

| key | kind | default | range | Roblox |
|---|---|---|---|---|
| lightType | enum | `"Point"` | Point, Spot, Surface | class |
| color | color3 | `"#FFFFFF"` | | Color |
| brightness | number | `1` | 0..100 | Brightness |
| range | number | `8` | 0..120, length (clamped to 120 after scaling) | Range |
| angle | number | `90` | 0..180 (Spot/Surface) | Angle |
| face | enum NormalId | `"Front"` | Spot/Surface | Face |
| shadows | boolean | `false` | only when quality.lightShadows | Shadows |
| surfaceSize | vector3 | `[4, 4, 0.2]` | length, Surface only | host Part Size |

Channels: `position`, `rotation`, `brightness`, `range`, `color`, `angle`. Events: `enable`, `disable`.
Quality: the Compiler drops lights beyond `quality.maxLights` (in component order).

## 8. `sound` (Audio) → Sound

Attachment on Root + Sound inside (positional audio). In Studio edit mode `Sound.Playing` does not start playback
(engine doc); the editor preview uses `SoundService:PlayLocalSound` (best effort, documented as unverified).

| key | kind | default | range | Roblox |
|---|---|---|---|---|
| soundId | asset | `""` | | SoundId |
| volume | number | `0.5` | 0..10 | Volume |
| playbackSpeed | number | `1` | 0.01..10 | PlaybackSpeed |
| rollOffMinDistance | number | `10` | 0..10000, length | RollOffMinDistance |
| rollOffMaxDistance | number | `100` | 0..10000, length | RollOffMaxDistance |
| looped | boolean | `false` | | Looped |
| playOnStart | boolean | `true` | | Play() on activation |

Channels: `position`, `volume`, `playbackSpeed`. Events: `play`, `stop`. Not supported in viewport.

## 9. `sphere` (Procedural) — energy sphere

Core Ball part + shell Ball part (+ optional PointLight on an Attachment). Pulse: radius × (1 + pulseAmplitude ×
sin(2π·pulseFrequency·t)).

| key | kind | default | range |
|---|---|---|---|
| radius | number | `1` | 0.01..500, length |
| coreColor | color3 | `"#FFFFFF"` | |
| shellColor | color3 | `"#8A5CFF"` | |
| coreMaterial | enum Material | `"Neon"` | |
| shellMaterial | enum Material | `"ForceField"` | |
| shellScale | number | `1.4` | 1..10 |
| coreTransparency | number | `0` | 0..1 |
| shellTransparency | number | `0.3` | 0..1 |
| pulseAmplitude | number | `0.05` | 0..1 |
| pulseFrequency | number | `4` | 0..60 Hz |
| light | boolean | `true` | |
| lightBrightness | number | `2` | 0..100 |
| lightRange | number | `8` | 0..120, length |
| spin | vector3 | `[0,0,0]` | |

Channels: transform, `radius`, `transparency` (fade applied to both layers: t' = 1−(1−t)(1−v)), `coreColor`,
`shellColor`, `lightBrightness`.

## 10. `flash` (Procedural) — impact flash

Neon Ball + PointLight with a built-in envelope over local time: attack → hold → decay. Size grows from `startSize`
to `size`; transparency 0 at peak → 1 at the end of decay; light brightness follows the same envelope.

| key | kind | default | range |
|---|---|---|---|
| color | color3 | `"#FFFFFF"` | |
| size | number | `6` | 0..500, length (final diameter) |
| startSize | number | `1` | 0..500, length |
| attack | number | `0.03` | 0..5 s |
| hold | number | `0.02` | 0..5 s |
| decay | number | `0.25` | 0.01..10 s |
| material | enum Material | `"Neon"` | |
| light | boolean | `true` | |
| peakBrightness | number | `10` | 0..100 |
| range | number | `16` | 0..120, length |

Channels: `position`, `color`. (Duration of the component should be ≥ attack+hold+decay; Validation warns.)

## 11. `shockwave` (Procedural) — expanding disc

`layers` flattened Cylinder parts (cylinder axis rotated to local Y) expanding from `startRadius` to `endRadius`
over the component duration with `expandEasing`, fading from `startTransparency` to 1 with `fadeEasing`. Layer i
starts `i × layerDelay` later and is `layerThinning` thinner. ForceField/Glass materials give a refractive look.

| key | kind | default | range |
|---|---|---|---|
| startRadius | number | `0.5` | 0..2000, length |
| endRadius | number | `12` | 0..2000, length |
| height | number | `0.3` | 0.01..100, length |
| color | color3 | `"#FFFFFF"` | |
| material | enum Material | `"ForceField"` | |
| startTransparency | number | `0` | 0..1 |
| expandEasing | string (easing) | `"Quart.Out"` | Easing def |
| fadeEasing | string (easing) | `"Quad.In"` | Easing def |
| layers | integer | `1` | 1..4, segments |
| layerDelay | number | `0.05` | 0..2 s |
| layerThinning | number | `0.6` | 0.05..1 |

Channels: `position`, `rotation`, `color`.

## 12. `ring` (Procedural) — rings, polygons, stars, spokes (magic circles)

Thin Block parts in the local XZ plane. `ring`: `segments` chords around the circle (slight overlap); `polygon`:
`points` edges; `star`: edges i → i+`starStep` ({points/starStep} star polygon); `spokes`: `points` radial lines from
`innerRadius` to `radius`.

| key | kind | default | range |
|---|---|---|---|
| style | enum | `"ring"` | ring, polygon, star, spokes |
| segments | integer | `24` | 3..128, segments (ring style) |
| points | integer | `5` | 3..32 |
| starStep | integer | `2` | 1..15 |
| radius | number | `4` | 0..2000, length |
| innerRadius | number | `0` | 0..2000, length (spokes) |
| thickness | number | `0.2` | 0.001..100, length (radial width of the line) |
| height | number | `0.1` | 0.001..100, length |
| color | color3 | `"#FFFFFF"` | |
| material | enum Material | `"Neon"` | |
| transparency | number | `0` | 0..1 |
| spin | vector3 | `[0,0,0]` | |

Channels: transform, `radius`, `thickness`, `transparency`, `color`. Geometry updates only when radius/thickness/
scale change (dirty flag).

## 13. `radialBurst` (Procedural) — impact lines / spikes

`count` thin parts shooting outward along deterministic directions; head distance eases out from `startRadius` to
`endRadius`, tail eases in (spike length rises then shrinks), width tapers to 0 at the end.

| key | kind | default | range |
|---|---|---|---|
| count | integer | `12` | 1..256, count |
| distribution | enum | `"sphere"` | sphere, hemisphere, ring, cone |
| coneAngle | number | `45` | 0..180 (cone) |
| startRadius | number | `0.5` | 0..2000, length |
| endRadius | number | `10` | 0..2000, length |
| width | number | `0.3` | 0.001..100, length |
| jitter | number | `0.3` | 0..1 (direction randomness) |
| color | color3 | `"#FFFFFF"` | |
| material | enum Material | `"Neon"` | |
| transparency | number | `0` | 0..1 |

Channels: `position`, `rotation`, `transparency`, `color`.

## 14. `debris` (Procedural) — kinematic fragments

`count` small parts with deterministic initial velocity in a cone around `direction`. Exact linear-drag ballistic
motion: `v(t) = v0·e^(−k t)`; `p(t) = p0 + v0·(1−e^(−kt))/k + g·(t/k − (1−e^(−kt))/k²)` (k = drag; k = 0 → p0 + v0 t +
½ g t²). Optional floor: y clamped to `floorHeight` (pieces stop falling and stop spinning). Pieces fade during the
last `fadeTime` seconds of the component span and shrink with them.

| key | kind | default | range |
|---|---|---|---|
| count | integer | `12` | 1..200, count |
| shape | enum | `"Mixed"` | Block, Wedge, Ball, Mixed |
| size | numberRange | `[0.3, 0.8]` | 0.01..50, length |
| speed | numberRange | `[20, 40]` | 0..2000, length |
| direction | vector3 | `[0, 1, 0]` | |
| spreadAngle | number | `60` | 0..180 |
| gravity | vector3 | `[0, -80, 0]` | length |
| drag | number | `0` | 0..20 |
| spinSpeed | numberRange | `[90, 360]` | 0..3600 deg/s |
| color | color3 | `"#6B5B4B"` | |
| colorVariance | number | `0.15` | 0..1 |
| material | enum Material | `"Slate"` | |
| transparency | number | `0` | 0..1 |
| fadeTime | number | `0.3` | 0..10 s |
| floor | boolean | `false` | |
| floorHeight | number | `0` | length (local Y) |

Channels: `position`, `rotation`, `color`, `transparency`.

## 15. `lightning` (Procedural) — bolts and arcs

Zig-zag polyline from `from` to `to` with `segments` points; perpendicular offsets up to `jitter` with a sin(π·u)
envelope (endpoints fixed); `branches` side bolts of `branchLength` × main length starting at random points.
Shape seed = hash(component seed, regenerateCount, floor(localTime × flickerRate)) → deterministic flicker
(flickerRate 0 = static). `render = "beam"`: Beams between consecutive Attachments (FaceCamera, LightEmission);
`render = "part"`: Neon Block parts between points (renders in viewport).

| key | kind | default | range |
|---|---|---|---|
| from | vector3 | `[0, 10, 0]` | length |
| to | vector3 | `[0, 0, 0]` | length |
| segments | integer | `12` | 2..64, segments |
| jitter | number | `1.5` | 0..500, length |
| branches | integer | `2` | 0..8, count |
| branchLength | number | `0.35` | 0..1 |
| flickerRate | number | `20` | 0..120 Hz |
| thickness | number | `0.3` | 0.01..50, length |
| color | color3 | `"#A8DCFF"` | |
| render | enum | `"beam"` | beam, part |
| lightEmission | number | `1` | 0..1 (beam) |
| brightness | number | `2` | 0..100 (beam) |
| texture | asset | `""` | (beam) |
| transparency | number | `0` | 0..1 |
| material | enum Material | `"Neon"` | (part) |

Channels: `position`, `rotation`, `from`, `to`, `thickness`, `transparency`, `color`. Events: `regenerate`.

## 16. Built-in textures

Presets must only use textures that exist without uploads. The Studio 0.745 client manifest
(`rbxManifest.txt`, Roblox-Client-Tracker; see docs/research/api-particles-beams-trails.md §2.13) lists these files
under `rbxasset://textures/particles/` (VERIFIED existence in Studio; availability on every player platform is an
ASSUMPTION, appearance/channel packing unverified):

`common_alpha.dds`, `explosion_alpha.dds`, `explosion_color.dds`, `explosion01_core_alpha.png`,
`explosion01_core_main.dds`, `explosion01_implosion_color.png`, `explosion01_implosion_main.dds`,
`explosion01_shockwave_main.dds`, `explosion01_smoke_alpha.dds`, `explosion01_smoke_color_new.dds`,
`explosion01_smoke_main.dds`, `fire_alpha.dds`, `fire_color.dds`, `fire_main.dds`, `fire_sparks_color.dds`,
`fire_sparks_main.dds`, `forcefield_alpha.dds`, `forcefield_glow_alpha.dds`, `forcefield_glow_color.dds`,
`forcefield_glow_main.dds`, `forcefield_vortex_color.dds`, `forcefield_vortex_main.dds`,
`legacy_fire_alpha_color.dds`, `smoke_color.dds`, `smoke_main.dds`, `sparkles_color.dds`, `sparkles_main.dds`,
`SquareParticle.png`.

Also present directly under `rbxasset://textures/`: `sparkle.png`, `glow.png`, `explosion.png`, `gradient.png`,
`noise.dds`, `whiteCircle.png`, `smallWhiteCircle.png`, `ui/traildot.png`.

Never invent `rbxassetid://` numbers. User assets are entered by the user (asset fields accept any id).

## 17. `cameraShake` (Camera) — client-side camera shake

Shakes the local player's camera while active. Offset each frame = amplitude × envelope(localTime) ×
noise(localTime × frequency), where noise is a deterministic sum of 3 sines per axis with seed-derived phases
(smooth, repeatable), envelope = attack (linear up), sustain, then decay with an easing (`decayEasing`) over the last
`decay` seconds of the component span. Distance falloff from the camera to the component's world position: 1 inside
`innerRadius`, linear to 0 at `outerRadius`. Rotation offset in degrees (pitch/yaw/roll weights) plus positional
offset in studs.

Runtime (clients only — `Players.LocalPlayer` exists): uses
`RunService:BindToRenderStep("AstraVFX_Shake_<unique>", Enum.RenderPriority.Camera.Value + 1, fn)` while active (this
is the documented way to run after the default camera scripts; PreRender/BindToRenderStep are client-only) and
`UnbindFromRenderStep` on deactivate/release/destroy; multiplies `workspace.CurrentCamera.CFrame` by the offset each
render step (camera scripts recompute the CFrame each frame, so no accumulation). Server: no-op (no instances, no
bindings). Preview (`ctx.isPreview`): apply only when `workspace.CurrentCamera` exists AND the property
`previewInStudio` is true (default false). In preview, capture the camera CFrame at activation and set
`camera.CFrame = base * offset` in `update()` each frame (Studio's edit camera is not driven by camera scripts, so
offsets would accumulate otherwise), restoring base at deactivation/destroy.

| key | kind | default | range |
|---|---|---|---|
| amplitude | number | `0.6` | 0..20 (degrees of rotation at full strength) |
| positionAmplitude | number | `0.15` | 0..10, length |
| frequency | number | `18` | 0.1..60 Hz |
| attack | number | `0.02` | 0..5 s |
| decay | number | `0.35` | 0..10 s |
| decayEasing | string (easing) | `"Quad.Out"` | |
| rotationWeights | vector3 | `[1, 0.6, 0.3]` | 0..1 (pitch, yaw, roll) |
| innerRadius | number | `20` | 0..10000, length |
| outerRadius | number | `120` | 0..10000, length |
| previewInStudio | boolean | `false` | |

Channels: `position`, `amplitude`. `supportsViewport = false`. Cost: 0 instances, propertyUpdates 1 while active.

**Implementation notes** (`src/Runtime/Core/Components/CameraShake.luau`, specs in
`tests/specs/ComponentsCamera.spec.luau`, end to end through `AstraVFX.Play` on a simulated client and a server in
`tests/specs/ComponentsCameraRuntime.spec.luau`; deviations from the text above are marked ⚑):

* Envelope (S = span): `min(rise, fall)` clamped to 0..1, `rise = min(t / attack, 1)` (attack 0 → 1),
  `fall = 1 − decayEasing(p)` with `p = (t − (S − decay)) / decay` during the last `decay` seconds; 0 for t < 0 and
  t ≥ S. Overlapping attack and decay take the smaller value. `decayEasing` = `"Quad.Out"` therefore drops fast and
  tails off; invalid easings fall back to Linear (Validation reports them, the key ends in `Easing`).
* Noise per axis (pitch, yaw, roll, x, y, z): `Σ w_k sin(2π (r_k u + φ_k)) / Σ w_k`, u = t × frequency,
  w = (1, 0.6, 0.35), r = (1, 0.59, 0.31) × (1 ± 0.1 seed-derived), φ seed-derived (Core/Random, component seed).
  |noise| ≤ 1; the fastest component runs at `frequency`. Offset =
  `CFrame.new(positionAmplitude·s·n_xyz) * CFrame.fromOrientation(rad(amplitude·s·weights·n_pyr))`,
  s = envelope × falloff. `outerRadius <= innerRadius` gives a hard edge at `innerRadius`.
* `amplitude` channel = rotation amplitude in degrees (rest value = the property, clamped 0..20); positionAmplitude
  is not animated. `transform.scale` multiplies positionAmplitude and both radii (Compiler already applied the effect
  scale). The distance is measured from the camera's unshaken CFrame.
* Strength `s = envelope × falloff` is used only when `s > 0`; anything else — including NaN from a non-finite world
  position (an Attach target flung by physics) — is "no offset", so `Camera.CFrame` never becomes NaN (a NaN camera
  never equals the last write, the undo step could not repair it and the camera scripts would keep reading a NaN
  LookVector).
* ⚑ Undo step: besides the apply step at `Camera.Value + 1`, an undo step at `Camera.Value − 1` puts the unshaken
  CFrame back before the camera scripts run (only if `Camera.CFrame` still holds ASTRA's last write). Reason: the
  default PlayerModule cameras derive the next look direction from `Camera.CFrame.LookVector` (ASSUMPTION, from the
  PlayerModule source, not verified in this repository), so a rotation left in place feeds back and drifts the view
  (spec "does not drift a camera script that reads back Camera.CFrame.LookVector": ~3.7° after 2 s without the undo).
  It also prevents accumulation on Scriptable cameras nobody updates. ⚑ Cost: `propertyUpdates = 2`
  (undo + apply; the preview writes once).
* ⚑ Mixer: all active client shakes share ONE binding pair (`AstraVFX_Shake_<token>_<n>` /
  `AstraVFX_ShakeUndo_<token>_<n>`, `<token>` per runtime module copy, `<n>` per bind) instead of one binding per
  component, and the offsets of concurrent shakes are composed into one write (`base × o₁ × o₂ …`, activation order).
  Per-component undo steps would otherwise run in an undefined order and corrupt each other's base. Bound when the
  first client shake activates, unbound (camera restored) when the last one deactivates / is released / reset /
  destroyed. Preview shakes use a second mixer without bindings.
* Preview: the base is captured at activation; if the author moves the Studio camera during the preview
  (`Camera.CFrame` no longer equals the last write) the moved CFrame without the last composed offset
  (`current × offset⁻¹`) becomes the base instead of being snapped back, and deactivation does not overwrite the
  author's camera. Taking the offset out matters if Studio's navigation moves relative to the CFrame the camera
  shows (ASSUMPTION, unverified): adopting the shaken CFrame as-is would fold the offset into the base every frame
  (spec "preview never accumulates the shake while the author moves the camera relative to it": 1.2 rad after 40
  frames). For an absolute move the error is at most one offset, so it stays bounded in both models. A changed
  `CurrentCamera` restores the old camera first.
* After each write the value read back from `Camera.CFrame` is remembered (property storage may round — Lune's does),
  so "still holds the last write" compares like with like.

## 18. `screenFlash` (Camera) — impact frame / screen flash

A `ColorCorrectionEffect` parented to `workspace.CurrentCamera` (local to the player; works only under Lighting or the
current camera — VERIFIED in docs/ROBLOX_API_CONSTRAINTS.md) whose Brightness/Contrast/Saturation/TintColor follow an
attack → hold → decay envelope over local time (pure function). Classic anime impact frame: high contrast,
desaturated, short. Clients only at runtime; in preview applied to the Studio camera when `previewInStudio` (default
true — a short colour pulse is harmless; but the effect must always be removed on deactivate/destroy and created
with `Archivable = false`).

| key | kind | default | range |
|---|---|---|---|
| brightness | number | `0.35` | −1..2 |
| contrast | number | `0.8` | −1..3 |
| saturation | number | `-0.6` | −1..2 |
| tint | color3 | `"#FFFFFF"` | |
| attack | number | `0.02` | 0..2 s |
| hold | number | `0.05` | 0..2 s |
| decay | number | `0.18` | 0.01..5 s |
| previewInStudio | boolean | `true` | |

Channels: `tint`. `supportsViewport = false`. Cost: 1 instance (post effect), propertyUpdates 4 while active, notes
"post effect: full-screen pass".

**Implementation notes** (`src/Runtime/Core/Components/ScreenFlash.luau`, specs in
`tests/specs/ComponentsCamera.spec.luau` and `tests/specs/ComponentsCameraRuntime.spec.luau`):

* Envelope as `flash` (§10): e = t/A during the attack (A = 0: peak at once), 1 while holding, linear 1 → 0 over the
  decay, 0 otherwise. Brightness/Contrast/Saturation = value × e, TintColor = white + (tint − white) × e, so e = 0 is
  the neutral ColorCorrection (0 / 0 / 0 / white). The `tint` channel replaces the `tint` property (baseProperty).
* The effect exists only while the component is active, not released AND e > 0 (no idle full-screen pass after the
  flash; scrubbing back re-creates it). Created with Name `AstraVFX_<name>`, `Archivable = false`, `Enabled = true`,
  tagged via `ctx.tagInstance` (the Builder adds `AstraPreview` in preview), values written before parenting. While
  it exists it is the only entry of `controller.instances` (empty otherwise) — it never lives in the container.
  Each property is written only when it changes (4 writes per frame during attack/decay, none while holding).
* A changed `CurrentCamera` (or an effect destroyed with the old camera) gets a fresh effect under the current
  camera. Lighting is never touched. Viewport builds never create it (no post-processing in a ViewportFrame).
* Brightness is documented as −1..1 (VERIFIED); authored values up to 2 are written as authored — what the engine
  does above 1 is unverified. The cost note "Component span is shorter than attack + hold + decay; the flash is cut
  off." is added when applicable (no Validation lint yet).
* No distance falloff: every client that plays the effect sees the flash — game code decides who plays it.
