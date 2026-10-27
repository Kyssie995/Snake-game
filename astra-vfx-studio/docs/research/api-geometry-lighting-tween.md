# Recherche: Roblox-Engine-APIs für Geometrie, Licht, Tweening und Sound (VFX-Sicht)

Stand: 2026-10-27 · Phase 1 (Research & Architecture) · Autor: Research-Subagent für ASTRA VFX STUDIO
Bezug: `docs/ARCHITECTURE.md` (ADR 2, 4, 5, 7) und `docs/MODULE_CONTRACTS.md` (Scheduler, Curves, Easing).

> **Label-Legende:** **VERIFIED** = offizielle Roblox-Doku (creator-docs-Quelltext über raw.githubusercontent.com) oder
> lokaler API-Dump (`/root/tools/ref/Full-API-Dump.json`, Engine **0.745.0.7451137**) bzw. luau-lsp-Typdefinitionen
> (`/root/tools/ref/globalTypes.d.luau`) · **REPORTED** = DevForum-Posts, Drittseiten, Such-Zusammenfassungen ·
> **ASSUMPTION** = eigene Schlussfolgerung · **IDEA** = eigene Design-Idee für ASTRA.
> ⚑ = *critical* (eine ASTRA-Implementierungsentscheidung hängt daran).

> **Quellenlage:** DevForum/Creator Hub/GitHub-Webseiten waren per HTTP blockiert; DevForum-Inhalte stammen nur aus
> WebSearch-Zusammenfassungen (daher höchstens REPORTED). Die creator-docs-Quelltexte (YAML/MD) und die lokalen
> API-Dumps waren vollständig lesbar. Das **WebSearch-Budget der Sitzung war gegen Ende erschöpft** – zwei geplante
> Nachrecherchen (Ball-Part-Größenverhalten, Datum der MeshId-Sicherheitsänderung) konnten nicht mehr ausgeführt werden
> und stehen unter „Offene Fragen“. Es wurde kein Fremdcode kopiert.

---

## 1. Zusammenfassung

* **Tweening (⚑):** `TweenService` kann laut Doku nur `number`, `bool`, `CFrame`, `Rect`, `Color3`, `UDim`, `UDim2`,
  `Vector2`, `Vector2int16`, `Vector3` und `EnumItem` interpolieren. `NumberSequence`, `ColorSequence`,
  `NumberRange`, `Content/ContentId`, `BrickColor`, `string`, Instanz-Referenzen sind **nicht** tweenbar (VERIFIED durch
  Weglassen in der offiziellen Liste; REPORTED durch die Fehlermeldung „… is not a data type that can be tweened“).
  Ein `Tween` hat **kein Seek/TimePosition** – nur `Play/Pause/Cancel` + `PlaybackState` (VERIFIED). Damit ist ADR 2
  („eigene Zeitauswertung statt TweenService“) bestätigt. `TweenService:GetValue(alpha, style, dir)` ist als
  **Easing-Referenz** nutzbar (thread-safe, klemmt alpha auf [0,1]), wirft aber für die im API-Dump neu
  vorhandenen Styles **`Bezier` (11)** und **`Spring` (12)** einen Fehler – genau wie `TweenInfo.new`.
* **Mesh-Skalierung & -Zuweisung (⚑):** `MeshPart.MeshId`/`MeshContent` haben Write-Security
  **`NotAccessibleSecurity`** – in Engine 0.745 nicht einmal Plugins dürfen sie setzen (VERIFIED). Wege zu einem
  MeshPart mit beliebigem Mesh: `AssetService:CreateMeshPartAsync(Content, options)` (yieldet, kann fehlschlagen)
  plus `MeshPart:ApplyMesh(source)`, oder Klonen einer Vorlage. `SpecialMesh`/`FileMesh.MeshId` ist dagegen von
  **jedem** Skript zur Laufzeit setzbar (VERIFIED). `SpecialMesh.Scale/Offset` zu animieren ist laut Doku
  „relativ günstig“, weil keine Physik/Kollision neu berechnet wird; `Part.Size` pro Frame zu ändern gilt in der
  Community als teuer (REPORTED). Achtung: `Instance.new("SpecialMesh")` hat **`MeshType = Head`** als Default (VERIFIED).
* **Laufzeit- vs. Plugin-Kontext (⚑):** Fast alle VFX-relevanten Properties sind mit Security `None` schreibbar.
  Ausnahmen, die ein Runtime-Builder **nicht** setzen kann: `MeshPart.MeshId/MeshContent` (niemand),
  `Decal/Texture.EmissiveMaskContent`, `NormalMapContent`, `MetalnessMapContent`, `RoughnessMapContent` und alle
  `SurfaceAppearance`-Maps (nur `PluginSecurity`), `TriangleMeshPart.CollisionPrecision` (Plugin). Solche Dinge
  müssen als **Vorlagen-Instanzen** ausgeliefert und geklont werden.
* **Per-Frame-Animation (⚑):** `PreRender` (Ersatz für `RenderStepped`) und `PreSimulation`/`PostSimulation`
  (Ersatz für `Stepped`) sind die aktuellen Events; `RenderStepped`/`Stepped` sind „superseded“, aber im Dump
  **nicht** als `Deprecated` markiert. `Heartbeat` ist aktuell. `PreRender`/`BindToRenderStep` sind **nur
  clientseitig** verwendbar. Für viele Parts: `WorldRoot:BulkMoveTo(parts, cframes, FireCFrameChanged)` (VERIFIED).
  Ob `Heartbeat`/`PreRender` im **Studio-Edit-Modus** für Plugins feuern, ist **nicht offiziell dokumentiert**;
  belegt ist nur, dass sie beim **Pausieren** eines Playtests weiterlaufen („… maintaining normal functionality of …
  plugins“, VERIFIED). Ein alter DevForum-Report sagt, `Stepped` feuert im Edit-Modus nicht (REPORTED).
* **Licht:** Lokale Lichter (`PointLight/SpotLight/SurfaceLight`) müssen **direktes Kind** eines `BasePart` oder
  `Attachment` (in Workspace) sein. `Range` wird auf **120 Studs** geklemmt (VERIFIED, früher 60); `Angle` max. 180
  (VERIFIED); für `Brightness` ist kein Maximum dokumentiert. Schatten von Lichtern sind teuer (VERIFIED, Perf-Guide).
* **Post-Effekte:** `BloomEffect`/`ColorCorrectionEffect` wirken nur unter `Lighting` (alle Spieler) oder
  `Workspace.CurrentCamera` (nur dieser Client). Defaults Bloom: Intensity 0.4, Size 24, Threshold 0.95 (VERIFIED).
* **Highlight:** Limit **255** gleichzeitige Highlights pro Client (VERIFIED, früher 31); deaktivierte belegen
  trotzdem einen Slot; Hinzufügen/Entfernen verursacht Geometry-Rebuild → Properties ändern statt neu erstellen.
* **Sound:** Im Edit-Modus spielt `Sound.Playing = true` **nicht** (VERIFIED für das Properties-Fenster).
  Plugin-Audio-Vorschau im Edit-Modus ist laut DevForum unzuverlässig (`PlayLocalSound` widersprüchlich berichtet);
  die neue Audio-API (`AudioPlayer` → `Wire` → `AudioDeviceOutput`) soll im Edit-Modus funktionieren (REPORTED,
  Staff-Aussage). `Sound.Volume` 0–10, Default 0.5 (VERIFIED).
* **Materialien:** `Neon` „leuchtet“ (VERIFIED, ohne Detailangaben); Glühen hängt von Grafikqualität/Lighting und
  Transparenz ab (REPORTED). `ForceField` braucht laut Enum-Doku eine `MeshPart` mit UVs und `TextureID` (VERIFIED);
  `Glass` blendet halbtransparente Objekte dahinter aus (VERIFIED) – relevant für VFX hinter Glas.

---

## 2. Befunde

### 2.1 BasePart / Part

| # | Befund | Label | Quelle |
|---|---|---|---|
| P1 | `Part.Shape` ist `Enum.PartType`: Ball, Block, Cylinder, Wedge, CornerWedge (Default Block). Cylinder ist entlang der **X-Achse** orientiert. | VERIFIED | [D-PartType], [D-Part] |
| P2 | Der Dump 0.745 enthält zusätzlich `PartType.Capsule = 5` mit Tag `NotBrowsable`; die Doku listet ihn **nicht**. | VERIFIED (Dump) | [API] |
| P3 ⚑ | `Size`-Komponenten: min **0.001**, max **2048**; unter 0.05 wird **physikalisch** wie 0.05 simuliert, gerendert aber in echter Größe. `Size` ist `NotReplicated` (repliziert intern über andere Wege). | VERIFIED | [D-BasePart] |
| P4 | `Size` beeinflusst u. a. Masse, ParticleEmitter-Spawnfläche, `BlockMesh`/`SpecialMesh`-Rendergröße (bestimmte MeshTypes) und `SurfaceLight`-Fläche. | VERIFIED | [D-BasePart] |
| P5 | `Transparency` 0–1; voll transparente Parts werden **gar nicht gerendert**, teiltransparente sind teuer, überlappende teiltransparente Parts haben unvorhersehbare Sortierung. | VERIFIED | [D-BasePart], [D-Perf] |
| P6 | `LocalTransparencyModifier` (Hidden, aber skriptbar, `NotReplicated`): clientlokaler Multiplikator, Formel `1 − (1 − T)·(1 − LTM)`. Existiert auch auf `Decal`, `ParticleEmitter`, `Beam`, `Trail`. | VERIFIED | [D-BasePart], [API] |
| P7 | `CastShadow`: Abschalten kann Artefakte erzeugen; nicht primär als Performance-Schalter gedacht, hilft aber in komplexen Szenen. Perf-Guide: Schatten auf kleinen/bewegten Parts abschalten. | VERIFIED | [D-BasePart], [D-Perf] |
| P8 | `CanCollide`, `CanTouch`, `CanQuery`: `CanQuery` wirkt **nur wenn `CanCollide = false`**. Parts mit `CanTouch = false` **und** `CanCollide = false` sparen Kollisionsberechnung. Perf-Guide empfiehlt alle drei `false` für Parts ohne Kollisionsbedarf. | VERIFIED | [D-BasePart], [D-Perf] |
| P9 | `Anchored`: keine Physikbewegung, per `CFrame` trotzdem verschiebbar; zwei verankerte Parts feuern kein `Touched`. | VERIFIED | [D-BasePart] |
| P10 | `Massless`: zählt nicht zur Assembly-Masse, solange an massebehaftetes Part geschweißt; wird ignoriert, wenn das Part selbst Root ist. | VERIFIED | [D-BasePart] |
| P11 | `Material` (`Enum.Material`): `Neon`, `ForceField`, `Glass`, `SmoothPlastic` (ohne Textur) usw. Neon: „parts will appear to glow“. `Glass`: leichte Spiegelung/Verzerrung auf mittleren Grafikstufen; **halbtransparente Parts hinter Glass sind unsichtbar**. | VERIFIED | [D-BasePart], [D-Parts], [D-Material] |
| P12 | `ForceField`-Material: „Must be used on a MeshPart with UVs … must also have a texture applied to its TextureID … wide value range“. | VERIFIED | [D-Material] |
| P13 | ForceField-Schimmer wird über den **Rotkanal** der Textur gesteuert, die Animation ist zufällig/nicht steuerbar, `Texture`-Instanzen funktionieren damit nicht, auf leerer TextureID gibt es einen generischen Glüh-Look. | REPORTED | [F-FF1], [F-FF2], [F-FF3] |
| P14 | Neon-Glühen hängt von Grafikqualitätsstufe und Lighting-Technologie ab, nimmt mit steigender `Transparency` ab (in Voxel ab ca. 0.35–0.45 berichtet) und skaliert mit der Farbhelligkeit; BloomEffect verstärkt es. | REPORTED | [F-Neon1], [F-Neon2] |
| P15 | `SurfaceAppearance.EmissiveMaskContent` ist die feinere Alternative zum „Alles-oder-nichts“-Neon. | VERIFIED | [D-SurfApp] |
| P16 | `PVInstance:PivotTo(cf)` verschiebt Parts/Models; feuert `Changed` nur für `CFrame` (nicht `Position/Orientation`); bei Models werden Offsets gecacht (kein Float-Drift). `Model.WorldPivot` gilt nur ohne `PrimaryPart`; neues Model nutzt Bounding-Box-Mitte, bis `WorldPivot` erstmals gesetzt wird. | VERIFIED | [D-PVInstance], [D-Model] |
| P17 | `Model:ScaleTo(f)` skaliert um den Pivot relativ zu Skala 1, inkl. Part-Größen, Joint-Längen, **Partikel-Emitter-Größen**, `Sound.RollOffMinDistance`; `GetScale()` liefert den kanonischen Faktor; drift-frei durch Caching. | VERIFIED | [D-Model] |
| P18 ⚑ | `WorldRoot:BulkMoveTo(partList, cframeList, Enum.BulkMoveMode.FireCFrameChanged)` verschiebt viele Parts ohne Einzel-Property-Kosten; Doku: nur nutzen, wenn Bewegung wirklich Engpass ist. | VERIFIED | [D-WorldRoot], [API] |
| P19 | `Attachment.WorldCFrame` ist **schreibbar** (`NotReplicated`), = Eltern-CFrame × `Attachment.CFrame`. `WorldPosition` ebenfalls schreibbar. | VERIFIED | [D-Attachment], [API] |

### 2.2 MeshPart, SpecialMesh, FileMesh

| # | Befund | Label | Quelle |
|---|---|---|---|
| M1 ⚑ | `MeshPart.MeshId` und `MeshPart.MeshContent`: Write-Security **`NotAccessibleSecurity`** (Read: None). Doku: „cannot be changed directly by scripts, as the collision geometry … cannot be recomputed in real time“. Gilt im Dump auch für Plugins/Command Bar. | VERIFIED | [API], [D-MeshPart] |
| M2 | DevForum-Thread mit der Fehlermeldung „The current thread cannot write 'MeshId' (lacking capability NotAccessible)“ bestätigt die neue Sperre auch praktisch; ältere Threads/Seiten nennen noch `PluginSecurity`. | REPORTED | [F-MeshId1], [F-MeshId2] |
| M3 ⚑ | `AssetService:CreateMeshPartAsync(meshContent: Content, options?)` → `MeshPart` (Tag `Yields`, Security `None`), Optionen für CollisionFidelity/RenderFidelity/FluidFidelity, „throws errors if creation fails“. | VERIFIED | [D-AssetService], [API] |
| M4 | `MeshPart:ApplyMesh(sourceMeshPart)` überschreibt MeshContent, TextureContent, RenderFidelity, CollisionFidelity (+ Kollisionsgeometrie), FluidFidelity und MeshSize einer bestehenden MeshPart. | VERIFIED | [D-MeshPart] |
| M5 | `CreateMeshPartAsync` scheitert in der Praxis oft an Asset-Berechtigungen (Mesh muss demselben User/Gruppe wie das Spiel gehören o. ä.); früher war die Methode plugin-only, heute nicht mehr. | REPORTED | [F-CMPA1], [F-CMPA2], [F-RobloxApiAS] |
| M6 | `MeshPart.TextureID`/`TextureContent` sind zur Laufzeit schreibbar (auch `EditableImage` via `Content.fromObject`). `DoubleSided` (bool) rendert beide Polygonseiten. `RenderFidelity`: Automatic (LOD nach Kameradistanz: <250 / 250–500 / >500 Studs), Precise, Performance. | VERIFIED | [D-MeshPart], [D-RenderFid] |
| M7 ⚑ | `FileMesh.MeshId`/`TextureId` (geerbt von `SpecialMesh`) sind mit Security `None` schreibbar; Doku: „The MeshId property of a SpecialMesh can be changed by a Script or LocalScript during runtime. The MeshId property of a MeshPart can not.“ | VERIFIED | [D-SpecialMesh], [API] |
| M8 ⚑ | `SpecialMesh.MeshType` (Default **`Head`**): Head, Torso, Wedge, Sphere, Cylinder, FileMesh, Brick; Prism, Pyramid, ParallelRamp, RightAngleRamp, CornerWedge sind `Deprecated`. `Sphere` ist „freely resized on all axis“ (Ellipsoid möglich). | VERIFIED | [API], [D-MeshType], [D-SpecialMesh] |
| M9 ⚑ | `DataModelMesh.Scale` (Vector3): FileMesh skaliert relativ zur **Originalgröße beim Upload**; Brick/Wedge/Sphere (und `BlockMesh`) skalieren als **Multiplikator von `BasePart.Size`**; Cylinder: Höhe frei, Durchmesser 1:1 nach kleinstem Wert; Head/Torso nicht-standard. | VERIFIED | [D-DataModelMesh] |
| M10 ⚑ | Doku: „Offset and Scale can be animated using TweenService relatively inexpensively as the engine does not need to make any physics/collision calculations as the BasePart is not changed.“ | VERIFIED | [D-DataModelMesh] |
| M11 | `DataModelMesh.VertexColor` ist ein **Vector3** (kein Color3), tönt nur die Textur eines FileMesh. | VERIFIED | [D-DataModelMesh] |
| M12 | SpecialMesh ändert **nur das Aussehen**, die Kollision bleibt die des Parent-Parts; `BasePart.Material` „displays correctly on the mesh when using a MeshPart and not when using a SpecialMesh“. | VERIFIED | [D-SpecialMesh] |
| M13 | `CylinderMesh` ist deprecated, `BlockMesh` nicht. `FileMesh` ist nutzbar, aber `SpecialMesh` ist „the official supported class“. | VERIFIED | [API], [D-FileMesh] |
| M14 | Größe/Scale per Skript zu setzen ist teuer; Community-Benchmarks: `Scale` ca. 2× schneller als `Size` (kein Collider-Resize); Resize+Move in RenderStepped trieb Skriptlast auf 80 %+. | REPORTED | [F-Resize1], [F-Resize2], [F-Resize3] |
| M15 | Draw-Call-Instancing: gleiche `MeshContent` + gleiche TextureContent/SurfaceAppearance (bzw. gleiches Material ohne Textur) → ein Draw Call. Decals, Texturen und Partikel batchen schlecht; **Property-Änderungen an ParticleEmittern können die Performance stark beeinträchtigen**. | VERIFIED | [D-Perf] |

### 2.3 Decal / Texture auf Parts

| # | Befund | Label | Quelle |
|---|---|---|---|
| T1 | `Decal` projiziert ein Bild auf eine `Face` des Parent-Parts (Größe = Flächengröße); `Texture` kachelt mit `StudsPerTileU/V` (Default 2) und `OffsetStudsU/V`. | VERIFIED | [D-Decal], [D-Texture], [API] |
| T2 | Neue Properties: `ColorMapContent` (ersetzt das als deprecated beschriebene `TextureContent`), `UVOffset`/`UVScale` (Vector2), `Rotation` (Grad, im Uhrzeigersinn), `ZIndex`, `EmissiveStrength` (Default 1, negativ = 0), `EmissiveTint` (Color3). Alle mit Security `None` schreibbar und tweenbar. | VERIFIED | [D-Decal], [API] |
| T3 ⚑ | `Decal.EmissiveMaskContent`, `NormalMapContent`, `MetalnessMapContent`, `RoughnessMapContent` (und die ContentId-Varianten): Write **`PluginSecurity`** → Runtime-Skripte können sie nicht setzen. Dasselbe gilt für alle Maps von `SurfaceAppearance`. | VERIFIED | [API] |
| T4 | `Decal.Color3` ist nur ein **Tint** (volle Farbkontrolle nur bei weißem Quellbild). | VERIFIED | [D-Decal] |
| T5 ⚑ | Animierbare UV-Scrolls sind über `Texture.OffsetStudsU/V` bzw. `Decal.UVOffset` per Skript möglich (alles Zahlen/Vector2 → tweenbar). | VERIFIED (Typen) / ASSUMPTION (visuelle Qualität) | [API] |

### 2.4 Highlight

| # | Befund | Label | Quelle |
|---|---|---|---|
| H1 | Properties: `Adornee`, `DepthMode` (AlwaysOnTop/Occluded, Default AlwaysOnTop), `Enabled`, `FillColor` (Default 1,0,0), `FillTransparency` (0.5), `OutlineColor` (1,1,1), `OutlineTransparency` (0). `LineThickness` ist RobloxScriptSecurity (nicht nutzbar). | VERIFIED | [API], [D-Highlight] |
| H2 ⚑ | Limit **255** gleichzeitige Highlights pro Client, Überzählige werden **still ignoriert**; deaktivierte belegen trotzdem einen Slot. | VERIFIED | [D-Highlight], [D-Highlighting] |
| H3 | Erhöhung von 31 auf 255 wurde ca. Mitte November 2025 angekündigt („Lights, Camera, More Highlights!“). | REPORTED | [F-HL] |
| H4 | Hinzufügen/Entfernen eines Highlights kann einen Geometry-Rebuild (Spikes, Draw Calls) auslösen; Properties ändern ist leichtgewichtig; erstes Highlight kostet am meisten (bis ~1 ms GPU mobil); unsichtbare/deaktivierte kosten nichts. | VERIFIED | [D-Highlighting] |

### 2.5 Lichter (PointLight, SpotLight, SurfaceLight)

| # | Befund | Label | Quelle |
|---|---|---|---|
| L1 ⚑ | Ein lokales Licht muss **direktes Kind** eines `BasePart` oder `Attachment` sein, das selbst in `Workspace` liegt. Am Attachment strahlt es von `WorldPosition` aus; SpotLight-`Face` wählt dann die Attachment-Achse (−Z = Front). SurfaceLight an Attachment ≙ SpotLight. | VERIFIED | [D-PointLight], [D-SpotLight], [D-SurfaceLight] |
| L2 ⚑ | Maximale `Range` für alle lokalen Lichter: **120 Studs** („always 120 studs“); die Property `Lighting.ExtendLightRangeTo120` ist ungenutzt/nicht skriptbar. | VERIFIED | [D-Lighting] |
| L3 | Erhöhung 60 → 120 wurde ca. September 2025 vom Rendering-Team angekündigt; Werte darüber werden geklemmt. | REPORTED | [F-Light120], [F-Light60] |
| L4 | `SpotLight.Angle` max **180** (Halbkugel). `SurfaceLight.Angle` 0 = gerade nach außen, 180 = parallel zur Fläche. | VERIFIED | [D-LightSources] |
| L5 | `Brightness` Default 1; höhere Brightness vergrößert **nicht** den Bereich (bleibt an `Range` gebunden). Kein dokumentiertes Maximum gefunden. | VERIFIED (Default/Verhalten) / offen (Max.) | [D-Light], [D-LightSources] |
| L6 | `Shadows` (bool) projiziert Schatten; Perf-Guide: Schatten-Lichter sparsam einsetzen, Range/Angle begrenzen, wenige Lichter, Schatten auf bewegten Objekten vermeiden; unter Qualitätsstufe 4 werden Schatten ganz abgeschaltet. | VERIFIED | [D-Light], [D-Perf] |

### 2.6 Post-Effekte (BloomEffect, ColorCorrectionEffect)

| # | Befund | Label | Quelle |
|---|---|---|---|
| X1 ⚑ | Wirken nur bei `Enabled = true` und Parent `Lighting` (für alle Spieler) oder `Workspace.CurrentCamera` (nur der lokale Spieler). Mehrere Instanzen kombinieren sich. Darstellung hängt von der Studio-Qualitätsstufe ab. | VERIFIED | [D-Bloom], [D-CC], [D-PostFX] |
| X2 | Bloom: `Intensity` (Default 0.4), `Size` (Pixel-Radius, Default 24; 0 deaktiviert das Ausbluten), `Threshold` (Default 0.95; 1 = nur Weiß, 0 = alles). | VERIFIED | [D-Bloom], [API] |
| X3 | ColorCorrection: `Brightness` (−1 schwarz … 1 weiß, Default 0), `Contrast` (Default 0), `Saturation` (−1 = Graustufen, Default 0), `TintColor` (multiplikativ, Default weiß). Alle tweenbar. | VERIFIED | [D-CC], [API] |
| X4 | Neu im Dump: `ColorGradingEffect`, `UIBlur` u. a. (nicht im Scope untersucht). | VERIFIED (Existenz) | [API] |

### 2.7 TweenService / TweenInfo / Easing

| # | Befund | Label | Quelle |
|---|---|---|---|
| W1 ⚑ | Tweenbare Typen laut Doku: number, boolean, CFrame, Rect, Color3, UDim, UDim2, Vector2, Vector2int16, Vector3, **EnumItem**. | VERIFIED | [D-TweenService] |
| W2 ⚑ | **Nicht** in der Liste und damit nicht tweenbar: `NumberSequence`, `ColorSequence`, `NumberRange`, `Content`/`ContentId`, `BrickColor`, `PhysicalProperties`, `string`, Instanz-Refs. Fehlermeldung in der Praxis: „TweenService:Create property named 'Transparency' on object 'Beam' is not a data type that can be tweened“. Workarounds der Community: NumberValue/Color3Value tweenen und Sequenz bei `Changed` neu bauen, oder eigene Module. | VERIFIED (Liste) / REPORTED (Fehlertext, Workarounds) | [D-TweenService], [F-TwSeq1], [F-TwSeq2], [F-TwSeq3] |
| W3 | Konkret nicht tweenbar in VFX-Klassen: `ParticleEmitter.Color/Size/Transparency/Squash/Lifetime/Speed/Rotation/RotSpeed/FlipbookFramerate`, `Beam.Color/Transparency`, `Trail.Color/Transparency/WidthScale`, `Sound.PlaybackRegion/LoopRegion`, alle `*Id`/`*Content`. Tweenbar u. a. `ParticleEmitter.Rate/Brightness/LightEmission/ZOffset/TimeScale/Acceleration/SpreadAngle`, `Beam.Width0/1/CurveSize0/1/TextureSpeed/Brightness`, `Trail.Lifetime/MaxLength/Brightness`. | VERIFIED (aus Dump-Typen + Liste W1 abgeleitet) | [API], [D-TweenService] |
| W4 ⚑ | `Tween`/`TweenBase` haben nur `Play()`, `Pause()`, `Cancel()`, `PlaybackState` (ReadOnly), `Completed(PlaybackState)`, `Instance`, `TweenInfo` – **kein Seek, keine Zeitposition, keine Geschwindigkeit**. Konfiguration nach dem Erstellen unveränderlich. `Pause` nur im Zustand Playing (nicht Delayed); `Completed` feuert nicht bei Pause; `Cancel` setzt die Properties **nicht** zurück. | VERIFIED | [D-TweenBase], [D-Tween], [API] |
| W5 | Zwei Tweens auf dieselbe Property: der frühere wird abgebrochen und überschrieben. Ein Tween ist an genau eine Instanz gebunden. `Instance.new("Tween")` ist nicht vorgesehen. | VERIFIED | [D-TweenService], [D-Tween] |
| W6 | `TweenInfo.new(time=1, easingStyle=Quad, easingDirection=Out, repeatCount=0 (−1 = endlos), reverses=false, delayTime=0)`; Properties nach Erstellung nicht schreibbar. | VERIFIED | [D-TweenInfo], [Types] |
| W7 ⚑ | `Enum.EasingStyle` im Dump 0.745: Linear 0, Sine 1, Back 2, Quad 3, Quart 4, Quint 5, Bounce 6, Elastic 7, Exponential 8, Circular 9, Cubic 10, **Bezier 11, Spring 12**. Die Enum-Doku listet nur 0–10. `Enum.EasingDirection`: In 0, Out 1, InOut 2. | VERIFIED | [API], [D-EasingStyle], [D-EasingDir] |
| W8 ⚑ | `TweenInfo.new` und `TweenService:GetValue` **werfen einen Fehler** bei `Bezier` oder `Spring`. | VERIFIED | [D-TweenInfo], [D-TweenService] |
| W9 ⚑ | `TweenService:GetValue(alpha, style, dir) -> number`: alpha wird auf [0,1] geklemmt; ThreadSafety **Safe** (auch in Parallel Luau). | VERIFIED | [D-TweenService] |
| W10 | `TweenService:SmoothDamp(current, target, velocity, smoothTime, maxSpeed?, dt?) -> (value, velocity)`: kritisch gedämpfte Feder für number, Vector2, Vector3, CFrame; ThreadSafety Safe. | VERIFIED | [D-TweenService], [Types] |
| W11 | Die Doku zu Tween-Easing-Stilen nennt Default-Style Quad, Default-Direction Out; Linear wird von der Richtung nicht beeinflusst. | VERIFIED | [D-UIAnim] |
| W12 | 2020: Ein Studio-Update ließ TweenService im **Edit-Modus** (Plugins/Command Bar) nicht mehr laufen, weil Tweens an `Stepped` hingen; Staff: zurückgerollt, „TweenService should always work, incl plugins“. Aktueller Stand nicht bestätigt. | REPORTED | [F-TwEdit] |
| W13 | `:Lerp` existiert für `CFrame`, `Color3`, `UDim2`, `Vector2`, `Vector3` – **nicht** für `UDim`, `Rect`, `Vector2int16`, `NumberRange`, `NumberSequence`, `ColorSequence`. | VERIFIED | [Types] |
| W14 | Bool-/EnumItem-Tweens: Verhalten (Umschaltzeitpunkt) ist nicht dokumentiert. | offen | – |

### 2.8 RunService

| # | Befund | Label | Quelle |
|---|---|---|---|
| R1 ⚑ | Events (0.745): `PreRender(deltaTimeRender)`, `PreAnimation`, `PreSimulation(deltaTimeSim)`, `PostSimulation(deltaTimeSim)`, `Heartbeat(deltaTime)`, `RenderStepped`, `Stepped(time, dt)`. `PreRender` ist „replacement for RenderStepped“, `PreSimulation` „replacement for Stepped“ – beide Altevents tragen in der Doku eine **Migration Note** („superseded … should be used for new work“), sind im Dump aber **nicht** `Deprecated` getaggt. `Heartbeat` hat keine Migrationsnotiz. | VERIFIED | [D-RunService], [API] |
| R2 ⚑ | `PreRender` (und damit auch `BindToRenderStep`) ist **clientseitig**: nur in LocalScript, davon geladenem ModuleScript oder Script mit `RunContext = Client`. Engine wartet mit dem Rendern, bis der Code fertig ist. | VERIFIED | [D-RunService] |
| R3 | Kontexttabelle: **Edit** → IsStudio true, IsClient true, IsServer true, IsEdit true, IsRunning false. **Run-Modus** → IsClient false, IsServer true. **Collaborative Edit** → IsServer false. Live-Client: IsClient true / IsServer false. | VERIFIED | [D-RunService] |
| R4 | `PreSimulation/PostSimulation`: „deltaTimeSim … may deviate from the actual time between frames **in Studio edit mode** or when framerate is very low.“ (impliziert, dass sie im Edit-Modus feuern können, ohne es zu garantieren). | VERIFIED (Wortlaut) / ASSUMPTION (Interpretation) | [D-RunService] |
| R5 ⚑ | Beim **Pausieren** eines Playtests pausieren nur PreAnimation, PreSimulation, PostSimulation, Stepped; **PreRender, Heartbeat, RenderStepped feuern weiter** („maintaining normal functionality of camera scripts, rendered visualizations, and plugins“). In diesem Zustand liefern IsEdit **und** IsRunning `false`. | VERIFIED | [D-TestModes], [D-RunService] |
| R6 | `Stepped` feuert im Edit-Modus nicht (Grund für den TweenService-Edit-Mode-Bug 2020). | REPORTED | [F-TwEdit] |
| R7 | Ob `Heartbeat`/`PreRender` im **Edit-Modus** (ohne Playtest) für Plugin-Code feuern, ist in den gelesenen offiziellen Quellen **nicht** belegt; Community-Suchen lieferten keine eindeutige Aussage. Plausibel ist ja (task-Scheduler läuft auch im Edit-Modus, viele Plugins nutzen Frame-Loops). | ASSUMPTION | – |
| R8 | `BindToRenderStep(name, priority, fn)`: niedrigere Priorität früher; `Enum.RenderPriority`: First 0, Input 100, Camera 200, Character 300, Last 2000 (`.Value` verwenden). `UnbindFromRenderStep` wirft nicht bei unbekanntem Namen. | VERIFIED | [D-RunService], [API] |
| R9 | `BindToSimulation`/`BindToAnimation` (fixe Frequenz, `Enum.StepFrequency`, Default Hz30) sind für Physik/Prediction gedacht und **werfen Fehler** bei Zugriff auf nicht synchronisierte Properties – ungeeignet für VFX. `BindToSimulation` nur mit `Workspace.UseFixedSimulation`. | VERIFIED | [D-RunService], [API] |
| R10 | Task-Scheduler-Best-Practice: Render-Step nur, wenn nötig (Kamera etc.); für strikte Reihenfolge `BindToRenderStep` statt `PreRender`. | VERIFIED | [D-TaskSched] |

### 2.9 Sound / SoundService / Audio-API

| # | Befund | Label | Quelle |
|---|---|---|---|
| S1 | `Sound` in BasePart/Attachment → positional (Doppler, Distanzdämpfung ab Listener, Default Kamera); sonst „global“. | VERIFIED | [D-Sound] |
| S2 | Defaults (Dump): `Volume` 0.5 (Bereich 0–10), `PlaybackSpeed` 1 (höher = schneller **und** höher), `RollOffMinDistance` 10, `RollOffMaxDistance` 10000, `RollOffMode` Inverse (Inverse, Linear, LinearSquare, InverseTapered), `Looped` false, `PlaybackRegion`/`LoopRegion` NumberRange (0, 60000). | VERIFIED | [API], [D-Sound], [D-RollOff] |
| S3 | `SoundId` (ContentId) bzw. `AudioContent` (Content) frei schreibbar; `IsLoaded`/`Loaded` zum Warten auf das Laden; `TimeLength` ReadOnly; `PlayOnRemove` spielt beim Entfernen (Destroy/Parent=nil). `Sound:Play()` setzt `TimePosition` auf den zuletzt per Skript gesetzten Wert (oder 0). | VERIFIED | [D-Sound] |
| S4 ⚑ | Im Studio-**Edit**-Modus startet `Sound.Playing = true` im Properties-Fenster **keine** Wiedergabe („the sound will begin playing during runtime“). | VERIFIED | [D-Sound] |
| S5 | `SoundService:PlayLocalSound(sound)` (Security None) spielt eine **Kopie** nur für den aufrufenden Client; übernommen werden Volume, TimePosition, PlaybackSpeed, Spatialisierung, Effekte/SoundGroups; nicht übernommen: Looped, AmbientReverb. Kein Stop/Pause-Handle. | VERIFIED | [D-SoundService] |
| S6 ⚑ | Plugin-Audio im Edit-Modus: Berichte widersprechen sich (PlayLocalSound „does nothing“ aus Plugins vs. einzige Möglichkeit); Staff: im Editor ist die Zeit angehalten, TimePosition läuft nicht; `plugin:PlaySound` ist RobloxScriptSecurity. | REPORTED | [F-Snd1], [F-Snd2], [F-Snd3] |
| S7 | Neue Audio-API: `AudioPlayer` (`Play(atTime?)`, `Stop(atTime?)`, `Volume` Default 1, `PlaybackSpeed`, `TimePosition`, `IsReady`, `IsPlaying` nur von Engine schreibbar) muss per `Wire` an `AudioDeviceOutput` (bzw. Emitter/Listener) verdrahtet werden. `atTime` wird gegen `SoundService:GetMixerTime()` **sample-genau** geplant. | VERIFIED | [D-AudioPlayer], [API] |
| S8 | Staff: `AudioPlayer` spielt im Edit-Modus, wenn er bereit und vorab verdrahtet ist (verändert dabei TimePosition); Vorschau-Verhalten wird noch verbessert. | REPORTED | [F-Audio1], [F-Audio2] |

### 2.10 Tweenbarkeit je VFX-Klasse (aus Dump-Typen, skriptbar, nicht ReadOnly/Deprecated)

| Klasse | tweenbar (Auszug) | nicht tweenbar |
|---|---|---|
| Part/MeshPart | CFrame, Position, Orientation, Size, Color, Transparency, Reflectance, LocalTransparencyModifier, Material (Enum), Shape (Enum), CastShadow/CanCollide/… (bool) | BrickColor, CollisionGroup, MaterialVariant, CustomPhysicalProperties, MeshId (gesperrt), TextureID |
| SpecialMesh | Scale, Offset, VertexColor (Vector3), MeshType (Enum) | MeshId, TextureId, *Content |
| Decal/Texture | Transparency, Color3, EmissiveStrength, EmissiveTint, UVOffset, UVScale, Rotation, ZIndex, OffsetStudsU/V, StudsPerTileU/V | ColorMap*, Texture* |
| Highlight | FillColor, FillTransparency, OutlineColor, OutlineTransparency, Enabled, DepthMode | Adornee |
| Point/Spot/SurfaceLight | Brightness, Color, Range, Angle, Enabled, Shadows, Face | – |
| Bloom/ColorCorrection | Intensity, Size, Threshold / Brightness, Contrast, Saturation, TintColor | – |
| Sound | Volume, PlaybackSpeed, TimePosition, RollOffMin/MaxDistance, RollOffMode | SoundId, AudioContent, PlaybackRegion, LoopRegion |
| Attachment | CFrame, WorldCFrame, Position, WorldPosition, Axis, … | – |

(VERIFIED aus [API] + Typliste [D-TweenService]; ob Enum-/Bool-Tweens sinnvoll umschalten, ist offen.)

---

## 3. Einschränkungen / Kritik

1. **Kein Seek in TweenService** – für Timeline-Scrubbing, Loop-Synchronisation und deterministische Vorschau
   unbrauchbar; zudem keine Sequenz-Typen. ADR 2 ist korrekt.
2. **MeshPart ist zur Laufzeit faktisch „read-only“ in Bezug auf das Mesh** – selbst Plugins können `MeshId` nicht
   mehr setzen (Dump 0.745). `CreateMeshPartAsync` yieldet und ist berechtigungsabhängig → ungeeignet für
   „sofortiges“ Effekt-Spawnen und für KI-generierte Effekte mit fremden Mesh-IDs.
3. **SpecialMesh zeigt Materialien nicht korrekt** (laut Doku) – Neon/ForceField auf FileMesh-Effekten sind daher
   unsicher; ForceField benötigt explizit `MeshPart` + `TextureID`.
4. **PBR-/Emissive-Maps nur mit PluginSecurity** – der Runtime-Builder kann keine Emissive-Masken setzen; solche
   Looks erfordern mitgelieferte Vorlagen.
5. **Edit-Modus-Verhalten ist schlecht dokumentiert**: weder Heartbeat/PreRender noch Tweens noch Sound sind
   offiziell für Plugin-Edit-Modus spezifiziert; Community-Aussagen sind alt oder widersprüchlich.
6. **Licht-Limits**: Range ≤ 120, keine dokumentierte Brightness-Grenze, Schatten teuer; Lichter nur als direkte
   Kinder von Part/Attachment.
7. **Post-Effekte sind global** (Lighting) oder pro Client (Camera) – kein „Bloom nur für dieses Objekt“.
   In der Plugin-Vorschau würde ein Effekt in `Lighting` den Place verändern (Undo-/Speicher-Risiko).
8. **Highlight-Slots** sind knapp-ish (255) und Create/Destroy erzeugt Rebuild-Spikes.
9. **Transparenz-Overdraw**: viele teiltransparente Neon-/ForceField-Schichten sind teuer und sortieren
   unvorhersehbar; Glass verdeckt Halbtransparentes dahinter.
10. **Dokulücken**: `PartType.Capsule` und `EasingStyle.Bezier/Spring` existieren im Dump, sind aber nicht (bzw.
    nur als Fehlerfall) dokumentiert.

---

## 4. Konsequenzen für ASTRA

1. ⚑ **Eigene Zeitauswertung beibehalten (ADR 2 bestätigt).** `Curves.evaluate` + eigenes `Easing` (Penner).
   *IDEA:* In einem Studio-Integrationstest die eigenen Easing-Kurven gegen `TweenService:GetValue` für alle 11
   dokumentierten Styles × 3 Richtungen bei z. B. 101 Stützstellen vergleichen (Toleranz 1e-4) – das sichert
   „Formulas follow the Roblox curves“ ab.
2. ⚑ **Easing-Schema:** nur Linear…Cubic (0–10) + ASTRA-eigene (`Constant`, ggf. `Bezier`-Tangenten,
   `Spring`) zulassen. Falls Definitionen `Bezier`/`Spring` enthalten, **nie** an `TweenInfo.new`/`GetValue`
   durchreichen (Fehler!) – eigene Implementierung (Feder z. B. analytisch oder via `TweenService:SmoothDamp`
   als Referenz). Graph-Aktion `Tween` intern über die eigene Override-Auswertung, nicht über `TweenService`.
3. ⚑ **Sequenz-Typen** (`NumberSequence`, `ColorSequence`, `NumberRange`) werden von ASTRA pro Frame selbst
   interpoliert und neu konstruiert. Wegen der Perf-Warnung zu ParticleEmitter-Property-Änderungen:
   *IDEA:* Sequenz-Kanäle nur bei echter Wertänderung schreiben (Dirty-Check mit Epsilon) und eine
   Update-Rate pro Kanal erlauben (z. B. 30 Hz statt jedes Frame); der Performance-Analyzer sollte animierte
   Emitter-Sequenzen gewichten.
4. ⚑ **Lerp-Tabelle im Codec:** `:Lerp` für CFrame/Color3/UDim2/Vector2/Vector3 nutzen; für number, UDim, Rect,
   Vector2int16 (runden), NumberRange, Sequenzen eigene Lerps. `EnumItem`/`bool`-Kanäle als **Step** (Wert springt
   am Keyframe) behandeln, unabhängig vom ungeklärten Tween-Verhalten. *IDEA:* optional Farb-Interpolation in
   Oklab/HSV für Color-Kanäle (Color3:Lerp ist RGB – ASSUMPTION).
5. ⚑ **Meshes (ADR 5 bestätigt und verschärft):** `mesh`-Komponente = `Part` + `SpecialMesh`.
   * Builder **muss** `MeshType` explizit setzen (Default Head!).
   * Skalierung über `SpecialMesh.Scale` animieren, `Part.Size` konstant halten (z. B. 1×1×1 bzw. Basisgröße).
     Für Brick/Wedge/Sphere ist `Scale` ein Faktor auf `Size`; für FileMesh relativ zur Upload-Größe – der Compiler
     muss die Semantik je MeshType kennen (Cylinder: Durchmesser = min der beiden Querachsen).
   * Für prozedurale `shockwave`/`sphere`/`flash`-Typen: statt Ball-/Cylinder-`Part.Size` pro Frame lieber
     `SpecialMesh` (Sphere/Cylinder/Brick) mit animiertem `Scale` (laut Doku günstig, Community: ~2× schneller).
     Achtung: dann rendern Materialien ggf. nicht korrekt (M12) → Neon auf SpecialMesh im Phase-2-Test prüfen;
     Fallback: Part-Size-Animation mit reduzierter Rate.
   * `MeshPart` nur als **Vorlage** (im Effekt-Paket/ReplicatedStorage), per `Clone()`; *IDEA:* optionaler
     Komponenten-Modus `meshPartTemplate` (Pfad/Tag statt MeshId) für ForceField-Meshes und `DoubleSided`.
     `AssetService:CreateMeshPartAsync` nur als **asynchrones Prewarm** (Pool) mit pcall, niemals im Frame.
6. ⚑ **Runtime-Builder-Whitelist:** Validierung soll Properties mit Write-Security ≠ None ablehnen bzw. als
   „nur über Vorlage“ markieren: `MeshPart.MeshId/MeshContent`, `Decal/Texture/SurfaceAppearance`-Maps,
   `CollisionPrecision`, `Highlight.LineThickness`, `AudioPlayer.IsPlaying`. *IDEA:* `tools/` erzeugt diese Liste
   automatisch aus `Full-API-Dump.json`, damit sie mit Engine-Updates mitwandert.
7. ⚑ **Per-Frame-Pipeline (ADR 3/4):** eine Scheduler-Verbindung; Parts verankert, `CanCollide/CanTouch/CanQuery =
   false`, `CastShadow = false` als Default für VFX-Geometrie (Qualitätsprofil kann Schatten erlauben),
   Bewegungen gesammelt per `BulkMoveTo(..., FireCFrameChanged)`. Attachments (für Partikel/Beams/Trails/Lichter)
   per `Attachment.CFrame`/`WorldCFrame` setzen – `BulkMoveTo` nimmt nur BaseParts.
8. ⚑ **Event-Wahl im Scheduler:** Live-Client → `PreRender` (oder `BindToRenderStep` mit Priorität
   `Camera.Value + 1`, damit Effekte am Kamera-Ziel nicht nachhinken – IDEA); Live-Server → **nur** `Heartbeat`
   (PreRender ist clientseitig). Studio-Edit (Plugin-Vorschau) → `Heartbeat` mit Fallback; **Phase-2-Smoke-Test:**
   im Edit-Modus zählen, welche Events (Heartbeat, PreRender, RenderStepped, PreSimulation, Stepped) pro Sekunde
   feuern, und das Ergebnis in `docs/` festhalten. Kontext-Erkennung über die Tabelle R3 (Edit: IsClient **und**
   IsServer true). *IDEA:* Bei pausiertem Playtest (IsEdit = IsRunning = false) Effekt-Zeit optional anhalten,
   da Heartbeat/PreRender weiterlaufen.
9. **Lichter:** `light`-Komponente immer an ein Attachment/Part als **direktes Kind** bauen; Validator klemmt
   `Range` auf [0, 120] und `Angle` auf [0, 180], warnt bei `Shadows = true` (Performance-Analyzer-Kosten),
   Brightness ohne harte Grenze, aber mit Warnschwelle (IDEA, z. B. > 40).
10. **Post-Effekte (`screen`-Kanäle, z. B. Flash/Desaturierung):** zur Laufzeit nur clientseitig unter
    `Workspace.CurrentCamera` erzeugen (betrifft nur den lokalen Spieler, keine globale Lighting-Änderung);
    in der Plugin-Vorschau ebenfalls unter die Kamera, mit `Archivable = false` + `AstraPreview`-Attribut und
    garantiertem Aufräumen. Mehrere Instanzen kombinieren sich – ASTRA sollte pro Effekt eigene Instanzen nutzen und
    deren Werte animieren (Bloom-Defaults 0.4/24/0.95 als Startwerte).
11. **Highlight-Komponente (optional):** pooling statt Create/Destroy, Fade über `FillTransparency/
    OutlineTransparency`; Performance-Analyzer zählt aktive Highlights gegen das 255-Limit.
12. **Sound-Komponente:** Runtime: `Sound` am Attachment, Start über `Play()` mit vorher gesetztem
    `TimePosition` (für Seek), Laden über `IsLoaded`/`Loaded` vorab (Prewarm). Plugin-Vorschau: **nicht** auf
    `Sound:Play()` im Edit-Modus verlassen; Reihenfolge der Versuche: (a) `AudioPlayer` + `Wire` +
    `AudioDeviceOutput`, (b) `SoundService:PlayLocalSound`, (c) Hinweis „Audio nur im Playtest hörbar“.
    *IDEA:* langfristig die Runtime auf `AudioPlayer:Play(atTime)` umstellen, um Audio sample-genau mit der
    Effekt-Zeitachse zu koppeln.
13. **Material-Presets:** `Neon` für Glüh-Kerne mit Hinweis im Inspector („Glühen abhängig von Grafikqualität;
    ab ~0.4 Transparenz schwächer“ – REPORTED), `ForceField` nur mit MeshPart-Vorlage voll steuerbar, sonst
    generischer Look; Warnung, wenn VFX hinter `Glass` liegt.
14. **Skalierung ganzer Effekte:** Für Exporte als Model kann `Model:ScaleTo` Partikelgrößen etc. mitskalieren;
    die ASTRA-Runtime skaliert aber selbst über `scale` im Compiler (deterministisch, ohne Instanz-Caching) –
    beides nicht mischen.
15. **Schema v1:** `PartType.Capsule` und `EasingStyle.Bezier/Spring` (Roblox-Enum) **nicht** freigeben;
    `MeshType` nur Brick, Sphere, Cylinder, Wedge, FileMesh (Head/Torso/deprecated sperren).

---

## 5. Offene Fragen

1. Feuern `Heartbeat`, `PreRender`, `RenderStepped`, `PreSimulation` für **Plugin-Code im Edit-Modus** (ohne
   Playtest)? Mit welchem `dt`? (Phase-2-Smoke-Test, siehe 4.8.)
2. Läuft `TweenService` heute im Edit-Modus (relevant nur für Fremd-Komponenten/Tests, nicht für ASTRA-Core)?
3. Rendert `Neon` (und andere Materialien) auf `Part + SpecialMesh` (Sphere/Cylinder/FileMesh) im aktuellen Client
   korrekt? Doku sagt pauschal „nicht korrekt“.
4. Gibt es eine obere Grenze für `SpecialMesh.Scale` bzw. ein Verhalten bei Scale ≤ 0? (nicht dokumentiert)
5. Wie verhalten sich `bool`/`EnumItem`-Tweens (Umschaltzeitpunkt)? (für ASTRA irrelevant, falls Step-Semantik
   gewählt wird).
6. Funktioniert `SoundService:PlayLocalSound` aus Plugins im Edit-Modus in aktuellen Studio-Versionen?
   Spielt ein vorverdrahteter `AudioPlayer` zuverlässig?
7. Welche genauen Berechtigungsregeln gelten für `AssetService:CreateMeshPartAsync` (eigene Assets, Gruppen-Assets,
   Creator-Store-Assets)?
8. Seit welcher Version ist `MeshPart.MeshId` `NotAccessibleSecurity` (vorher `PluginSecurity`)? (Recherche wegen
   erschöpftem Such-Budget nicht abgeschlossen.)
9. Erzwingt `PartType.Ball` weiterhin gleichförmige Größe auf allen Achsen? (Nicht mehr recherchierbar; in Studio
   testen. SpecialMesh `Sphere` ist laut Doku frei skalierbar.)
10. Gibt es ein dokumentiertes Maximum für `Light.Brightness`?

---

## 6. Quellen

**Offizielle Doku (creator-docs-Quelltext, `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/…`;
öffentliche Entsprechung jeweils `https://create.roblox.com/docs/…`)**

* [D-BasePart] …/reference/engine/classes/BasePart.yaml
* [D-Part] …/reference/engine/classes/Part.yaml · [D-PartType] …/reference/engine/enums/PartType.yaml
* [D-Material] …/reference/engine/enums/Material.yaml · [D-Parts] …/parts/index.md · …/parts/materials.md
* [D-SurfApp] …/art/modeling/surface-appearance.md
* [D-MeshPart] …/reference/engine/classes/MeshPart.yaml · [D-RenderFid] …/reference/engine/enums/RenderFidelity.yaml
* [D-AssetService] …/reference/engine/classes/AssetService.yaml
* [D-SpecialMesh] …/reference/engine/classes/SpecialMesh.yaml · [D-FileMesh] …/reference/engine/classes/FileMesh.yaml
* [D-DataModelMesh] …/reference/engine/classes/DataModelMesh.yaml · [D-MeshType] …/reference/engine/enums/MeshType.yaml
* [D-Decal] …/reference/engine/classes/Decal.yaml · [D-Texture] …/reference/engine/classes/Texture.yaml
* [D-Highlight] …/reference/engine/classes/Highlight.yaml · [D-Highlighting] …/effects/highlighting.md
* [D-Light] …/reference/engine/classes/Light.yaml · [D-PointLight] …/classes/PointLight.yaml ·
  [D-SpotLight] …/classes/SpotLight.yaml · [D-SurfaceLight] …/classes/SurfaceLight.yaml ·
  [D-LightSources] …/effects/light-sources.md · [D-Lighting] …/reference/engine/classes/Lighting.yaml
* [D-Bloom] …/reference/engine/classes/BloomEffect.yaml · [D-CC] …/classes/ColorCorrectionEffect.yaml ·
  [D-PostFX] …/environment/post-processing-effects.md
* [D-TweenService] …/reference/engine/classes/TweenService.yaml · [D-TweenBase] …/classes/TweenBase.yaml ·
  [D-Tween] …/classes/Tween.yaml · [D-TweenInfo] …/reference/engine/datatypes/TweenInfo.yaml ·
  [D-EasingStyle] …/reference/engine/enums/EasingStyle.yaml · [D-EasingDir] …/enums/EasingDirection.yaml ·
  [D-UIAnim] …/ui/animation.md
* [D-RunService] …/reference/engine/classes/RunService.yaml · [D-TestModes] …/studio/testing-modes.md ·
  [D-TaskSched] …/performance-optimization/microprofiler/task-scheduler.md
* [D-WorldRoot] …/reference/engine/classes/WorldRoot.yaml · [D-PVInstance] …/classes/PVInstance.yaml ·
  [D-Model] …/classes/Model.yaml · [D-Attachment] …/classes/Attachment.yaml
* [D-Sound] …/reference/engine/classes/Sound.yaml · [D-SoundService] …/classes/SoundService.yaml ·
  [D-RollOff] …/reference/engine/enums/RollOffMode.yaml · [D-AudioPlayer] …/classes/AudioPlayer.yaml
* [D-Perf] …/performance-optimization/improve.md · …/studio/plugins.md (ChangeHistoryService)

**Lokale, autoritative API-Daten**

* [API] `/root/tools/ref/Full-API-Dump.json` und `/root/tools/ref/API-Dump.json` (Engine 0.745.0.7451137)
* [Types] `/root/tools/ref/globalTypes.d.luau` (luau-lsp Roblox-Typdefinitionen)

**Community (REPORTED, nur über Such-Zusammenfassungen)**

* [F-TwEdit] https://devforum.roblox.com/t/plugins-and-command-bar-can-no-longer-use-tweenservice-in-studio-edit-mode/474500
* [F-TwSeq1] https://devforum.roblox.com/t/tweenservicecreate-property-named-transparency-on-object-beam-is-not-a-data-type-that-can-be-tweened/148063
* [F-TwSeq2] https://devforum.roblox.com/t/tweeninglerping-beam-sequence-properties/1240924
* [F-TwSeq3] https://devforum.roblox.com/t/cannot-tween-transparency-due-to-type-mismatch/1759898
* [F-Light120] https://devforum.roblox.com/t/extended-light-ranges-doubling-the-limit-to-120/3954367
* [F-Light60] https://devforum.roblox.com/t/increase-range-limit-of-lights/68336
* [F-HL] https://devforum.roblox.com/t/lights-camera-more-highlights/4061534 ·
  https://devforum.roblox.com/t/weekly-recap-november-10-14-2025/4071175
* [F-MeshId1] https://devforum.roblox.com/t/the-current-thread-cannot-write-meshid-lacking-capability-notaccessible/3306176/3
* [F-MeshId2] https://devforum.roblox.com/t/modify-meshpartmeshid-through-pluginscommand-bar/140332
* [F-CMPA1] https://devforum.roblox.com/t/createmeshpartasync-doesnt-work/2848207
* [F-CMPA2] https://devforum.roblox.com/t/how-to-allow-players-to-create-mesh-parts-without-causing-an-error/3798571
* [F-RobloxApiAS] https://robloxapi.github.io/ref/class/AssetService.html
* [F-Resize1] https://devforum.roblox.com/t/renderstep-part-resize-cframe-performance-is-kill/25580
* [F-Resize2] https://devforum.roblox.com/t/resizing-baseparts-is-an-incredibly-expensive-operation/946141
* [F-Resize3] https://devforum.roblox.com/t/why-legacy-meshes-are-still-useful-in-2025/3771329
* [F-Neon1] https://devforum.roblox.com/t/neon-material-issues/294943
* [F-Neon2] https://devforum.roblox.com/t/trying-to-get-voxel-neon-to-replicate-legacy-neon/278140
* [F-FF1] https://devforum.roblox.com/t/how-forcefield-texture-animation-works/3041374
* [F-FF2] https://devforum.roblox.com/t/how-to-use-the-new-forcefield-material/423438
* [F-FF3] https://devforum.roblox.com/t/meshpartmaterial-forcefield-unintended-behaviours/301951
* [F-Snd1] https://devforum.roblox.com/t/soundserviceplaylocalsound-does-not-work-with-plugins/1927104
* [F-Snd2] https://devforum.roblox.com/t/play-sound-from-plugin-during-edit-mode-similar-to-properties-panel/2723419
* [F-Snd3] https://devforum.roblox.com/t/how-would-you-go-about-playing-stopping-audio-in-edit-mode/321507
* [F-Audio1] https://devforum.roblox.com/t/audioplayer-not-playing-sound-in-studio/4538689
* [F-Audio2] https://devforum.roblox.com/t/allow-audioplayer-previews-to-play-without-a-connected-output-instance/3959457
