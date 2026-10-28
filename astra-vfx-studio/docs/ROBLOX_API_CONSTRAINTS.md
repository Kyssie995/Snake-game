# ROBLOX_API_CONSTRAINTS – Verbindliche Engine- und Studio-Referenz für ASTRA VFX STUDIO

Stand: 2026-10-27 · Phase 1 (Research & Architecture) · Engine-/API-Stand: **0.745.0.7451137** (`/root/tools/ref/version.txt`)
Status: **autoritativ.** Implementierer richten sich nach diesem Dokument. Ein Punkt wird nur geändert, wenn ein
Studio-Test ihn widerlegt oder bestätigt. Das Ergebnis wird dann in Abschnitt 26 und in `docs/PROGRESS.md` eingetragen.

Grundlage sind die API-Notizen `docs/research/api-particles-beams-trails.md`, `api-geometry-lighting-tween.md`,
`api-studio-plugin.md`, `tooling-claude-integration.md` und `vfx-design-performance.md`, jeweils mit ihrem Abschnitt
„Verifikation“. Einzelne Fakten stammen aus `pro-vfx-tools.md`, `other-roblox-vfx-plugins.md`,
`qwinkle-particles2.md` und `ros-particle-editor.md`. Alle Member, Typen, Defaults, Security-Stufen, Tags und
Capabilities in den Klassenabschnitten habe ich am 2026-10-27 per Skript erneut aus
`/root/tools/ref/Full-API-Dump.json` gelesen (Version 0.745.0.7451137).

---

## 0. Lesehilfe

### 0.1 Labels

| Label | Bedeutung |
|---|---|
| **VERIFIED** | offizielle creator-docs, lokaler API-Dump 0.745, luau-lsp-Typen, Roblox-eigene Dateien oder ein lokal nachgestellter Tool-Test (Rojo 7.7.1 / Lune 0.11.1) |
| **REPORTED** | DevForum-Posts, Drittseiten, Such-Snippets (DevForum war nur über WebSearch-Zusammenfassungen lesbar, deshalb höchstens REPORTED) |
| **ASSUMPTION** | Schlussfolgerung ohne direkten Beleg, auch eine aus Doku-Wortlaut abgeleitete Verhaltensaussage |
| **UNVERIFIABLE** | Der Verifier fand weder Beleg noch Gegenbeleg. Muss in Studio getestet werden (Abschnitt 26). |
| **IDEA** | ASTRA-Designentscheidung. Erscheint **nur** in Abschnitt 24 und in den „→ K“-Verweisen. |

Regeln:
1. **Verifier-Korrekturen haben Vorrang** vor dem Originalbefund der Notiz. Bei PARTIAL-Verdikten übernehme ich die
   korrigierte Fassung.
2. **Kein Label wird hochgestuft.** Belegt der Dump nur ein Tag oder eine Security-Stufe, ist das *Verhalten* höchstens
   ASSUMPTION.
3. **Fakten und Design sind getrennt:** Die Abschnitte 1–23 beschreiben Roblox und die Tools. ASTRA-Entscheidungen
   stehen in Abschnitt 24 (IDEA). Ein Verweis wie „→ K12“ zeigt auf die passende Zeile dort.
4. **Default** heißt: Wert im Full-API-Dump, also der `Instance.new`-Wert. Dass Dump-Default und `Instance.new`
   übereinstimmen, ist eine Annahme über das Dump-Werkzeug; für `LightInfluence` stützt sie die Doku. Abstrakte
   oder übersprungene Klassen wie `BasePart`, `Light` und `UserGameSettings` haben im Dump **keine** Defaults. Dort
   gebe ich nur Defaults an, die in der Doku stehen.
5. **Security-Schreibweise:** `R/W` steht für Read- bzw. Write-Security. `None` = jedes Skript. `PluginSecurity` =
   Plugins und Command Bar. `RobloxScriptSecurity`, `RobloxSecurity` und `NotAccessibleSecurity` = für ASTRA
   **gesperrt**. Capabilities wie `PluginOrOpenCloud` oder `InternalTest` gelten zusätzlich. Was die Stufen für
   Plugins bedeuten, ist REPORTED (DF:219471, DF:2269097). Eine offizielle Tabelle gibt es nicht.
6. **Studio-UI-Bereiche** (`ReflectionMetadata.xml`, `UIMinimum`/`UIMaximum`) sind **keine Engine-Clamps**. Die
   Werte sind VERIFIED, die Deutung „nur UI“ ist eine ASSUMPTION.

### 0.2 Quellenkürzel

| Kürzel | Auflösung |
|---|---|
| `DUMP` | `/root/tools/ref/Full-API-Dump.json` und `API-Dump.json`, Engine 0.745.0.7451137 |
| `TYPES` | `/root/tools/ref/globalTypes.d.luau` (luau-lsp-Typdefinitionen) |
| `DOCS:<pfad>` | `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/<pfad>` (öffentlich: `https://create.roblox.com/docs/<pfad ohne Endung>`) |
| `cls/X.yaml` · `enum/X.yaml` · `dt/X.yaml` | Kurzform für `DOCS:reference/engine/classes/X.yaml`, `…/enums/X.yaml`, `…/datatypes/X.yaml` |
| `DF:<id>` | DevForum-Thread `https://devforum.roblox.com/t/<id>` (Discourse leitet die numerische ID auf den Thread weiter) |
| `RFM` | `https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml` (Roblox-Datei über einen Drittanbieter-Mirror, Version 0.745.0.7451137) |
| `MAN` | `https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/rbxManifest.txt` |
| `LOCAL` | lokal nachgestellter Test mit Rojo 7.7.1 / Lune 0.11.1 aus `tooling-claude-integration.md` bzw. dessen Verifikation |
| `RN:apb` · `RN:glt` · `RN:sp` · `RN:tc` · `RN:dp` | Research-Notizen `api-particles-beams-trails.md` · `api-geometry-lighting-tween.md` · `api-studio-plugin.md` · `tooling-claude-integration.md` · `vfx-design-performance.md` (IDs wie „C29“ beziehen sich auf deren Verifikationstabelle) |
| `RN:pro` · `RN:other` · `RN:qp2` · `RN:ros` | `pro-vfx-tools.md` · `other-roblox-vfx-plugins.md` · `qwinkle-particles2.md` · `ros-particle-editor.md` |

---

## 1. ParticleEmitter

### 1.1 Parent, Shape und Grundregeln

| # | Regel | Label | Quelle |
|---|---|---|---|
| PE-1 | Der Emitter emittiert und rendert nur als Kind eines `BasePart` oder eines `Attachment` in einem solchen Part. Bei einem Part entstehen die Partikel zufällig in der **Bounding Box** bzw. `Shape`, bei einem Attachment an dessen Position. | VERIFIED | cls/ParticleEmitter.yaml, DOCS:effects/particle-emitters.md |
| PE-2 | Mit Attachment-Parent werden die Shapes **Sphere und Cylinder nicht korrekt dargestellt**. Sie sind nur für BasePart-Parents gedacht. | VERIFIED | DOCS:effects/particle-emitters.md |
| PE-3 | `Terrain` erbt von `BasePart` (Terrain › BasePart › PVInstance). Attachments unter `workspace.Terrain` sind also typ-formal gültige Welt-Anker. Ob ein Emitter dort emittiert, ist nicht getestet. | VERIFIED (Vererbung) / ASSUMPTION (Verhalten) | DUMP |
| PE-4 | `Bone` erbt von `Attachment`. Ein Emitter an einem Bone ist damit zulässig, sein Verhalten ist nicht belegt. | VERIFIED (Vererbung) / ASSUMPTION | DUMP, cls/Bone.yaml |
| PE-5 | Die Shape-Größe kommt aus `BasePart.Size` (Bounding Box). Bei MeshParts und Wedges zählt die Box, nicht die Geometrie. Ob Sphere/Cylinder/Disc als Ellipsoid in die Box eingepasst werden und an welcher Achse sie liegen, ist nicht dokumentiert. | VERIFIED (Box) / REPORTED (MeshPart/Wedge, DF:3792199) / ASSUMPTION (Ellipsoid, Achse) | cls/ParticleEmitter.yaml |
| PE-6 | `EmissionDirection` wählt die Fläche des Parent-Parts. Bei einem Attachment wird stattdessen das Attachment gedreht. | VERIFIED | DOCS:effects/particle-emitters.md |
| PE-7 | Studio fügt `ParticleEmitter` bevorzugt unter `BasePart` ein (`PreferredParent`). | VERIFIED | RFM |

### 1.2 Properties (vollständig, 39 Stück)

„live“ heißt: wirkt auch auf bereits lebende Partikel. „neu“ heißt: gilt nur für neu emittierte Partikel. Alle
Properties haben `R/W None`.

| Property | Typ | Default | Grenze / Clamp | Wirkung · Hinweis | Label |
|---|---|---|---|---|---|
| `Acceleration` | Vector3 | 0,0,0 | – | Studs/s², **Weltachsen**. live („current and future“) | VERIFIED |
| `Brightness` | float | 1 | UI 0..10, kein Engine-Max dokumentiert | wirkt laut Doku „wenn LightInfluence 0 ist“ (bei Beam/Trail: „< 1“, Doku-Widerspruch) | VERIFIED |
| `Color` | ColorSequence | weiß→weiß | 2–20 Keypoints (§2) | über das Alter jedes Partikels; live („both current and future“) | VERIFIED |
| `Drag` | float | 0 | UI 0..5; negativ = exponentielles Wachstum | Halbwertszeit der Geschwindigkeit (s). Laut Speed-Doku wirkt es auf aktive Partikel | VERIFIED |
| `EmissionDirection` | NormalId | Top | – | siehe PE-6. neu (ASSUMPTION) | VERIFIED |
| `Enabled` | bool | true | – | `false` stoppt nur das Nachspawnen, lebende Partikel bleiben | VERIFIED |
| `FlipbookBlendFrames` | bool | true | – | linearer Crossfade zwischen Frames | VERIFIED |
| `FlipbookFramerate` | NumberRange | 1..1 | **max. 30 fps** (Doku), UI 0..30 | pro Partikel aus [min,max] gewürfelt; bei `OneShot` wirkungslos | VERIFIED |
| `FlipbookIncompatible` | string | „Particle texture must be 1024 by 1024 to use flipbooks.“ | – | nur ein Meldungstext. **CanSave=true, CanLoad=true** (wird serialisiert, Verifier-Korrektur RN:apb C29) | VERIFIED |
| `FlipbookLayout` | ParticleFlipbookLayout | None | None/Grid2x2/Grid4x4/Grid8x8/Custom | §1.4 | VERIFIED |
| `FlipbookMode` | ParticleFlipbookMode | Loop | Loop/OneShot/PingPong/Random | §1.4 | VERIFIED |
| `FlipbookSizeX` / `FlipbookSizeY` | int | 1 / 1 | **Maximum nicht dokumentiert** | nur bei `Custom` wirksam | VERIFIED |
| `FlipbookStartRandom` | bool | false | – | zufälliger Startframe; mit Framerate 0 ein statischer Zufallsframe | VERIFIED |
| `Lifetime` | NumberRange | 5..10 | **max. 20 s** (intern gekappt); **0 → keine Emission** | neu (pro Partikel gespeichert) | VERIFIED |
| `LightEmission` | float | 0 | 0..1 (0 normal, 1 additiv; Zwischenwerte als Übergang = ASSUMPTION) | live. Bei > 0 wirken **dunkle Farben transparenter** | VERIFIED |
| `LightInfluence` | float | **0** (`Instance.new`) / **1** (Studio-Insert) | muss 0..1 sein, sonst **undefiniert** (beim Emitter nicht als Clamp dokumentiert) | – | VERIFIED |
| `LocalTransparencyModifier` | float | 0 | – | `Hidden`, `NotReplicated`, CanSave=false. Formel `1-(1-T)*(1-LTM)`. Im Properties-Fenster unsichtbar | VERIFIED |
| `LockedToPart` | bool | false | – | aktive Partikel laufen starr mit dem Parent mit | VERIFIED |
| `Orientation` | ParticleOrientation | FacingCamera | FacingCamera/FacingCameraWorldUp/VelocityParallel/VelocityPerpendicular | gestreckte Streifen: `VelocityParallel` + **negatives** `Squash` | VERIFIED |
| `Rate` | float | 20 | Doku: **max. 400/s pro Emitter, 100/s auf Mobile**; UI 0..100. Das offizielle Tutorial setzt 50 000, ob die Engine klemmt, ist undokumentiert (ASSUMPTION) | neu („no affect on any active particles“) | VERIFIED |
| `RotSpeed` | NumberRange | 0..0 | UI −360..360 | °/s, beim Emit gewürfelt. neu | VERIFIED |
| `Rotation` | NumberRange | 0..0 | UI −180..180 | Grad, **positiv = im Uhrzeigersinn**. neu | VERIFIED |
| `Shape` | ParticleEmitterShape | Box | Box/Sphere/Cylinder/Disc | PE-2, PE-5 | VERIFIED |
| `ShapeInOut` | ParticleEmitterShapeInOut | Outward | Outward/Inward/InAndOut | – | VERIFIED |
| `ShapePartial` | float | 1 | 0..1 | Cylinder: oberer Radiusanteil (oben = Seite der EmissionDirection); Disc: Innenradius; Sphere: Halbkugelwinkel | VERIFIED |
| `ShapeStyle` | ParticleEmitterShapeStyle | Volume | Volume/Surface | – | VERIFIED |
| `Size` | NumberSequence | 1 (konstant) | UI 0..10 | Weltgröße in Studs. Doku: „all active particles over their individual lifetimes“. Live-Wirkung ist daraus **abgeleitet** (Verifier RN:apb C3) | VERIFIED (Typ) / ASSUMPTION (live) |
| `Speed` | NumberRange | 5..5 | negativ = rückwärts | neu | VERIFIED |
| `SpreadAngle` | Vector2 | 0,0 | Grad je Querachse; 360 = Kreis bzw. Kugel | neu (ASSUMPTION) | VERIFIED |
| `Squash` | NumberSequence | 0 (konstant) | UI −3..3 | > 0 schmaler und höher, < 0 breiter und flacher. live (ASSUMPTION) | VERIFIED |
| `Texture` | ContentId | `rbxasset://textures/particles/sparkles_main.dds` | – | Asset-URI-String | VERIFIED |
| `TextureContent` | Content | (none) | – | **Ein Setzen aktualisiert `Texture`** (Doku). Write-Capability `Basic` | VERIFIED |
| `TimeScale` | float | 1 | Doku: „between 0 and 1“, 0 friert ein. **Werte > 1: Verhalten undokumentiert** (ASSUMPTION, dass es nicht geht) | Studio-Bugs siehe §1.6 | VERIFIED |
| `Transparency` | NumberSequence | 0 (konstant) | 0..1 | live, wie bei Size abgeleitet (ASSUMPTION) | VERIFIED (Typ) |
| `VelocityInheritance` | float | 0 | 0..1 | übernimmt beim Emit die `BasePart.Velocity` des Parent-Parts (diese Property ist im Dump `Hidden`+`Deprecated`). Die Doku widerspricht sich: Die Speed-Doku nennt VelocityInheritance als Einfluss auf aktive Partikel. | VERIFIED (Definition) |
| `VelocitySpread` | float | 0 | – | **Deprecated** (→ `SpreadAngle`), NotReplicated, CanSave=false | VERIFIED |
| `WindAffectsDrag` | bool | false | – | folgt `Workspace.GlobalWind` **nur bei `Drag > 0`** | VERIFIED |
| `ZOffset` | float | 0 | – | Studs zur Kamera hin (+) oder weg (−), ohne die Bildgröße zu ändern; live. Das **einzige** Mittel für eine Render-Reihenfolge (gibt es auch bei Beam, **nicht** bei Trail) | VERIFIED |

Quellen: DUMP; cls/ParticleEmitter.yaml; DOCS:effects/particle-emitters.md; RFM (UI-Bereiche); Details in RN:apb §2.2
und Verifikation C3, C6, C9, C10, C29.

Offen ist (Verifier RN:apb C3), ob die beim Emit gewürfelten Envelope-Werte nach einem Sequenzwechsel weiterverwendet
werden (U41).

### 1.3 Methoden und Events

| Member | Signatur | Security | Bedeutung | Label |
|---|---|---|---|---|
| `Emit` | `Emit(particleCount: int = 16): ()` | None | emittiert sofort n Partikel (Alter 0) | VERIFIED |
| `Clear` | `Clear(): ()` | None | entfernt sofort alle Partikel (aus Rate und Emit) | VERIFIED |
| `FastForward` | `FastForward(numFrames: int): ()` | **RobloxScriptSecurity** | für Plugins und Spiele **gesperrt**, nicht in den Docs | VERIFIED |
| `OnEmitRequested(particleCount)`, `OnClearRequested()` | Events | None, `Hidden` (nur im Full-Dump) | intern und undokumentiert, **keine** Events pro Partikel. Nicht verwenden. | VERIFIED (Existenz) / ASSUMPTION (Zweck) |

- **Es gibt keinen Seed, keinen Zugriff auf einzelne Partikel (Position, Alter, Geschwindigkeit) und keine Spawn-,
  Death- oder Collision-Events.** VERIFIED (fehlen im DUMP; RN:pro R1).
- `Emit()` setzt Partikel immer mit Alter 0. Ein Partikelalter lässt sich nicht setzen. VERIFIED (kein Member,
  RN:other C37).
- **Emit direkt nach dem Parenten oder Klonen** kann wirkungslos sein. Nach ein bis zwei Frames oder `task.wait`
  funktioniert es. REPORTED (DF:34752, DF:2888715, DF:3325717). → K6
- **Emit außerhalb des Sichtfelds** wird angeblich aufgeschoben, bis der Emitter sichtbar ist, und startet dann bei
  t = 0. Emitter emittieren nicht, bevor sie einmal gesehen wurden, und die Simulation wird zurückgesetzt, wenn der
  Emitter das Bild verlässt. REPORTED (DF:188745, DF:1757317, DF:3550728). → K7
- Ob `Emit()` mit der Grafikqualität skaliert wird, ist **umstritten**. REPORTED (DF:1241979, DF:474762). Ob die
  400/s-Grenze auch für `Emit`-Bursts gilt, ist nicht dokumentiert (RN:dp C2).

### 1.4 Flipbooks

| # | Regel | Label | Quelle |
|---|---|---|---|
| FB-1 | Layouts: None=0, Grid2x2=1 (4 Frames), Grid4x4=2 (16), Grid8x8=3 (64), Custom=4 (`FlipbookSizeX`×`FlipbookSizeY`). | VERIFIED | enum/ParticleFlipbookLayout.yaml, DUMP |
| FB-2 | Modi: Loop=0, OneShot=1, PingPong=2, Random=3. Bei **OneShot** werden die Frames gleichmäßig über die Lifetime verteilt, `FlipbookFramerate` gilt nicht. | VERIFIED | enum/ParticleFlipbookMode.yaml |
| FB-3 | **Texturgröße, widersprüchlich:** Enum-Doku `ParticleFlipbookTextureCompatible` und Dump-Default verlangen **1024×1024**. Die Property-Doku verlangt ein „exaktes Vielfaches der Layoutgröße“. | VERIFIED (Widerspruch) | enum/ParticleFlipbookTextureCompatible.yaml, cls/ParticleEmitter.yaml, DUMP |
| FB-4 | Der Release-Post von 2022 erlaubt quadratische Zweierpotenzen von 8 bis 1024. Die Client-Beta „Custom Layouts“ (ca. Okt. 2025) erlaubt rechteckige Grids und zeigt ein Beispiel mit 4096² (32×8 Frames à 128×512). Ob die Beta allgemein freigegeben ist, ist unbekannt. | REPORTED | DF:2029388, DF:4005128 |
| FB-5 | Die Kompatibilität ist **nicht abfragbar**: Kein öffentlicher Member verwendet `ParticleFlipbookTextureCompatible`, laut Doku „set automatically by the engine“. | VERIFIED (Dump-Suche) / ASSUMPTION (keine indirekte Abfrage) | DUMP, enum/ParticleFlipbookTextureCompatible.yaml |
| FB-6 | Bei inkompatibler Textur ist `FlipbookLayout` in Studio ausgegraut und eine Warnung erscheint. Die Engine prüft beim Setzen der Textur. | REPORTED | DF:3118761 |
| FB-7 | Flipbooks kosten Speicher. Clients mit wenig Speicher (ältere Handys) **deaktivieren Flipbooks automatisch**. Wiederverwendete Texturen sparen Speicher. | VERIFIED | DOCS:effects/particle-emitters.md |
| FB-8 | Zwischen den Frames Abstand lassen, weil Mip-Filtering sonst überblutet. | VERIFIED | DOCS:effects/particle-emitters.md |
| FB-9 | Die Frame-Reihenfolge im Atlas ist nicht dokumentiert (vermutlich zeilenweise von links oben). | ASSUMPTION | – |
| FB-10 | Hochgeladene Bilder werden auf max. 1024² herunterskaliert. | REPORTED | DF:1679078 |
| FB-11 | Grafikspeicher hängt von der Pixelzahl ab (1024² = 4 × 512²). Kompression oder ein fehlender Alpha-Kanal sparen nichts. Faustregel ≤ 512². | VERIFIED | DOCS:performance-optimization/improve.md |

### 1.5 Edit Mode

| # | Verhalten | Label | Quelle |
|---|---|---|---|
| PE-E1 | Ein über den Explorer eingefügter Emitter „emittiert sofort“. Die Simulation läuft im Edit Mode ohne Playtest. | VERIFIED (Aussage) / ASSUMPTION (Kontext Edit Mode) | DOCS:effects/particle-emitters.md |
| PE-E2 | **`Emit()` aus einem Plugin funktioniert im Edit Mode.** Roblox' eigenes Tutorial testet Bursts mit dem Roblox-Plugin 303835976. Eine API-Aussage dazu fehlt, das Tutorial reicht als Grundlage. | VERIFIED | DOCS:tutorials/use-case-tutorials/vfx/use-particles-for-explosions.md |
| PE-E3 | Die Darstellung hängt von der Studio-Einstellung „Editor Quality Level“ ab (Doku). Studio zeigt oft mehr Partikel als ein Spieler mit niedriger Qualität. | VERIFIED (Doku-Hinweis) / REPORTED (Unterschiede, DF:95781, DF:2719243, DF:3181609) | DOCS:effects/particle-emitters.md |

### 1.6 Bekannte Engine-Bugs und Qualitäts-LOD

| # | Befund | Label | Quelle |
|---|---|---|---|
| PE-B1 | `TimeScale` ist in Studio fehleranfällig: (a) 2023 zeigte `TimeScale=0` bei manchen Nutzern keine Wirkung, (b) im Nov. 2023 ignorierten Size/Transparency TimeScale (Regression, zurückgenommen), (c) im Feb. 2024 verschwanden Partikel bei einer TimeScale-Änderung mitten im Effekt (Fix „almost ready“). | REPORTED | DF:2221218, DF:2720182, DF:2824385 |
| PE-B2 | Die Grafikqualität skaliert die effektive Rate, Community-Formel ≈ `Rate × Level / 10`. Ein Bug-Report von ca. Ende Aug. 2026 sagt, das greife nicht mehr (auch in Studio). Eine Staff-Antwort fehlt. | REPORTED | DF:1241979, DF:4834736 |
| PE-B3 | Berichtete globale Partikel-Caps: ca. 16 000 (PC/Xbox) und ca. 3 500–3 600 (Mobile/Konsole). Offiziell steht nur, dass Mobile „much lower limits“ hat und die Partikel-Render-Limits mit der QualityLevel steigen. | REPORTED (Zahlen) / VERIFIED (qualitativ) | DF:2159584, DF:1585054; DOCS:effects/particle-emitters.md; enum/QualityLevel.yaml |
| PE-B4 | Partikel kosten über **Fill-Rate und Overdraw**, **batchen schlecht**, und **Property-Änderungen an ParticleEmittern können die Performance dramatisch beeinflussen**. Hebel laut MicroProfiler-Doku: weniger Emitter, kleinere Rate und Lifetime, **Emitter-Bewegung begrenzen**. | VERIFIED | DOCS:effects/particle-emitters.md, DOCS:performance-optimization/improve.md, DOCS:performance-optimization/microprofiler/tag-table.md |
| PE-B5 | `LightEmission` beleuchtet die Umgebung nicht. Dafür braucht es ein Licht. | VERIFIED | cls/ParticleEmitter.yaml |
| PE-B6 | 2021 war die Size-Sequenz zeitweise auf 1 gekappt (Bug). Das aktuelle Tutorial nutzt Size 3→10. | REPORTED / VERIFIED (Tutorial) | DF:1506337 |
| PE-B7 | `QualityLevel.yaml`: Die Wirkung der Qualitätsstufe je Feature ist „platform- and device-specific and can not be relied upon“. | VERIFIED | enum/QualityLevel.yaml |

### 1.7 Mitgelieferte Texturen, verwandte Klassen

- Studio 0.745 (Windows-Manifest) liefert genau **28 Dateien** in `content/textures/particles/` aus, darunter
  `sparkles_main.dds`, `fire_main.dds`, `smoke_main.dds`, `explosion01_*`, `forcefield_*` und `SquareParticle.png`.
  Dazu kommen `textures/sparkle.png`, `glow.png`, `explosion.png`, `gradient.png` und `noise.dds`. Sie werden als
  `rbxasset://textures/particles/<datei>` angesprochen. VERIFIED (MAN). Ob die Dateien auf Player-Clients
  (Mobile/Konsole) vorhanden sind, ist eine ASSUMPTION (U25).
- `ParticleEmitter2D` (UI-Partikel) trägt den Tag `NotBrowsable`, ist an FFlag `UIParticles` gebunden und hat keine
  Doku-Seite (404). Die Klasse steht trotzdem in `CREATABLE_INSTANCES` der luau-lsp-Typen. **Nicht verwenden.**
  VERIFIED (Existenz/Flag) / ASSUMPTION (unveröffentlicht).
- `Fire`, `Smoke` und `Sparkles` haben ebenfalls `TimeScale` und ein gesperrtes `FastForward`
  (RobloxScriptSecurity). VERIFIED (DUMP).

---

## 2. Datentypen: NumberSequence, ColorSequence, NumberRange, Content, Lerp, Random

| # | Regel | Label | Quelle |
|---|---|---|---|
| DT-1 | `NumberSequence.new({...})`: **mindestens 2, höchstens 20 Keypoints**, erster bei Time 0, letzter bei Time 1, Zeiten nicht absteigend. Kurzformen `new(n)` und `new(n0, n1)`. | VERIFIED | dt/NumberSequence.yaml, dt/NumberSequenceKeypoint.yaml |
| DT-2 | `ColorSequence.new({...})`: dieselben Regeln (2..20, Time 0/1). Color3-Komponenten 0..1, Interpolation **linear in RGB**. | VERIFIED | dt/ColorSequence.yaml, dt/ColorSequenceKeypoint.yaml |
| DT-3 | **Doppelte Zeitstempel (Step-Kurven) sind nicht gesichert:** Der Konstruktor sagt „non-descending“, `NumberSequenceKeypoint.Time` verlangt für Zwischen-Keypoints „ascending“. | VERIFIED (Widerspruch) / UNVERIFIABLE (Engine-Verhalten) → U13 | RN:apb C11, N8 |
| DT-4 | `Envelope ≥ 0`, symmetrisch: Der Wert streut in [Value−Envelope, Value+Envelope]. Werte und Envelopes werden linear interpoliert. Bei Partikeln wird pro Keypoint und Partikel beim Emit gewürfelt. Asymmetrische Bereiche gibt es nicht. | VERIFIED | dt/NumberSequenceKeypoint.yaml, cls/ParticleEmitter.yaml |
| DT-5 | Es gibt **keine eingebaute Auswertungsmethode** für Sequenzen. Die Docs zeigen eigene Interpolationsfunktionen. | VERIFIED | dt/NumberSequence.yaml |
| DT-6 | `NumberRange.new(min[, max])` mit min ≤ max, gespeichert als float32. | VERIFIED | dt/NumberRange.yaml |
| DT-7 | `Content.fromUri(uri)`, `Content.fromAssetId(id)` (0 → none), `Content.fromObject(obj)`, `Content.none`. **Object-Contents (EditableImage/EditableMesh) replizieren nicht**, Clients sehen ein Platzhalter-Schachbrett. | VERIFIED | dt/Content.yaml, TYPES |
| DT-8 | `EditableImage` funktioniert in Content-Properties, die ein Bild nehmen. In veröffentlichten Spielen ist es standardmäßig gesperrt („Allow Mesh / Image APIs“). Beim Publishen wird das Bild als Image-Asset veröffentlicht. Ob es konkret in `ParticleEmitter/Beam/Trail.TextureContent` wirkt, ist eine ASSUMPTION (U24). | VERIFIED (allgemein) / ASSUMPTION | cls/EditableImage.yaml |
| DT-9 | Asset-URIs: `rbxassetid://` (hochgeladen), `rbxasset://` (lokaler Content-Ordner des Clients), `rbxthumb://`, `rbxgameasset://` (nur im aktuellen Spiel). Dazu `rbxtemp://` aus `File:GetTemporaryId()` (§16). | VERIFIED | DOCS:projects/assets/index.md, cls/File.yaml |
| DT-10 | `:Lerp` gibt es nur für `CFrame`, `Color3`, `UDim2`, `Vector2` und `Vector3`. **Nicht** für UDim, Rect, Vector2int16, Vector3int16, NumberRange, NumberSequence und ColorSequence. Die kleingeschriebenen `lerp`-Aliase sind `@deprecated`. `Color3:Lerp` interpoliert in RGB (ASSUMPTION). | VERIFIED | TYPES, RN:glt C10 |
| DT-11 | `Random.new(seed?)` mit `NextNumber`, `NextInteger`, `NextUnitVector`, `Shuffle` und `Clone` macht **eigene** Logik deterministisch. Native Partikel bleiben es nicht. | VERIFIED | TYPES, RN:pro R5 |

---

## 3. Beam

### 3.1 Properties (alle `R/W None`)

| Property | Typ | Default | Grenze / Clamp | Hinweis | Label |
|---|---|---|---|---|---|
| `Attachment0` / `Attachment1` | Attachment (Ref) | nil | – | P0/P3 der Kurve. Fehlt eines, wird nichts gerendert | VERIFIED |
| `Brightness` | float | 1 | Doku **0..10000**, UI 0..10 | wirkt bei `LightInfluence < 1` | VERIFIED |
| `Color` | ColorSequence | weiß | 2–20 Keypoints | entlang der **Länge**; braucht ≥ n−1 `Segments` | VERIFIED |
| `CurveSize0` | float | 0 | UI −10..10 | Studs entlang **+X** von Attachment0 → P1 | VERIFIED |
| `CurveSize1` | float | 0 | UI −10..10 | Studs entlang **−X** von Attachment1 → P2 | VERIFIED |
| `Enabled` | bool | true | – | – | VERIFIED |
| `FaceCamera` | bool | false | – | true: Das Band dreht sich zur `CurrentCamera` | VERIFIED |
| `LightEmission` | float | 0 | 0..1 | 1 = additiv | VERIFIED |
| `LightInfluence` | float | 0 | **auf 0..1 geklemmt** (Doku) | – | VERIFIED |
| `LocalTransparencyModifier` | float | 0 | – | Hidden, NotReplicated, CanSave=false | VERIFIED |
| `Segments` | int | 10 | **Maximum nicht dokumentiert** (die oft genannten „1000“ sind unbelegt) | ≥ n−1 für n Keypoints ist nur eine **Untergrenze**. Bei ungleich verteilten Keypoint-Zeiten reicht das nicht für ein exaktes Bild (ASSUMPTION, RN:apb C21/N6) | VERIFIED / ASSUMPTION |
| `Texture` | ContentId | "" | – | leer, ungültig oder nicht geladen → einfarbig | VERIFIED |
| `TextureContent` | Content | none | – | Content-Äquivalent | VERIFIED |
| `TextureLength` | float | 1 | UI 0..5 | Wrap: Wiederholungen = Länge/TextureLength. Stretch: Textur TextureLength-mal | VERIFIED |
| `TextureMode` | TextureMode | Stretch | Stretch/Wrap/Static | **Static wird bei Beams wie Wrap behandelt** | VERIFIED |
| `TextureSpeed` | float | 1 | UI −1..1 | Texturzyklen pro Sekunde; + = A0→A1 | VERIFIED |
| `Transparency` | NumberSequence | **0.5 konstant** | – | entlang der Länge; ≥ n−1 Segments | VERIFIED |
| `Width0` / `Width1` | float | 1 / 1 | **Studio** setzt Werte < 0 auf 0 (per Skript unbelegt) | Breite verläuft **nur linear** von Width0 nach Width1 | VERIFIED |
| `ZOffset` | float | 0 | UI −1..1 | Versatz zur Kamera | VERIFIED |

Methode: `SetTextureOffset(offset: float = 0)` setzt die Phase des Texturzyklus (0 und 1 sind gleich). Ein **größerer
Offset bewegt die Textur gegen die `TextureSpeed`-Richtung.** Es gibt **keinen Getter**, und ohne Textur tut die
Methode nichts. Beam hat **kein `Clear`, kein `TimeScale` und keine Events.** VERIFIED (cls/Beam.yaml, DUMP).

### 3.2 Geometrie und Darstellung

| # | Regel | Label | Quelle |
|---|---|---|---|
| BM-1 | Kubische Bezier-Kurve: P0 = `A0.WorldPosition`, P1 = P0 + `CurveSize0` × (+X von A0), P2 = `A1.WorldPosition` − `CurveSize1` × (X von A1), P3 = `A1.WorldPosition`. | VERIFIED | cls/Beam.yaml, DOCS:effects/beams.md |
| BM-2 | Sichtbar ist der Beam nur, wenn er selbst **und beide** Attachments Nachfahren von `Workspace` sind. | VERIFIED | cls/Beam.yaml |
| BM-3 | Pro Segment werden zwei Dreiecke gerendert. Die Segmente liegen „zwischen den Orientierungen“ der Attachments; rotieren diese unterschiedlich, verdrillt sich das Band. | VERIFIED | DOCS:effects/beams.md |
| BM-4 | **Welche lokale Attachment-Achse bei `FaceCamera=false` die Breite aufspannt, ist nicht dokumentiert.** Die Community rollt die Attachments um 90°. | REPORTED (DF:3076533, DF:3323908) / UNVERIFIABLE → U3 | RN:apb C22 |
| BM-5 | Eine Breitenkurve entlang der Länge gibt es nicht. | VERIFIED (Fehlen) | cls/Beam.yaml |
| BM-6 | Die Engine reduziert `Segments` je nach Grafikqualität, berichtet bis Faktor ~1/10 (20 → 2) bzw. bis 1. Die Doku sagt nur allgemein, dass sich die Beam-Qualität mit den Grafikeinstellungen ändert. Ein erzwungenes LOD gibt es nicht. | REPORTED (DF:2939171, DF:1732819, DF:2426888, DF:2225384) / VERIFIED (allgemein) | DOCS:effects/beams.md |
| BM-7 | Edit Mode: Beams rendern, sobald beide Attachments gesetzt sind (Guide-Workflow). | VERIFIED (Workflow) / ASSUMPTION | DOCS:effects/beams.md |
| BM-8 | Im Sept. 2024 gab es einen Studio-Bug mit unsichtbaren Beams und Trails, laut Staff behoben. | REPORTED | DF:3145864 |
| BM-9 | Studio fügt `Beam` bevorzugt unter `BasePart` ein. | VERIFIED | RFM |

---

## 4. Trail

### 4.1 Properties (alle `R/W None`)

| Property | Typ | Default | Grenze / Clamp | Hinweis | Label |
|---|---|---|---|---|---|
| `Attachment0` / `Attachment1` | Attachment (Ref) | nil | – | Positionen werden **jeden Frame** aufgezeichnet. **Ein Attachment-Wechsel löscht alle Segmente** | VERIFIED |
| `Brightness` | float | 1 | Doku 0..10000 | wirkt bei LightInfluence < 1 | VERIFIED |
| `Color` | ColorSequence | weiß | 2–20 KP | über die **Segment-Lebenszeit**; ändert auch alte Segmente | VERIFIED |
| `Enabled` | bool | true | – | false: keine neuen Segmente, alte laufen aus | VERIFIED |
| `FaceCamera` | bool | false | – | wirkt sofort auf alle Segmente | VERIFIED |
| `Lifetime` | float | 2 | **0.01..20 s** | wirkt rückwirkend: zu alte Segmente verschwinden sofort | VERIFIED |
| `LightEmission` | float | 0 | 0..1 | sofort für alle Segmente | VERIFIED |
| `LightInfluence` | float | 0 | **auf 0..1 geklemmt** | sofort | VERIFIED |
| `LocalTransparencyModifier` | float | 0 | – | Hidden, NotReplicated, CanSave=false | VERIFIED |
| `MaxLength` | float | 0 | 0 = unbegrenzt | entfernt die ältesten Segmente | VERIFIED |
| `MinLength` | float | 0.1 | UI 0..1 | erst ab dieser Bewegung entsteht ein neues Segment, sonst werden nur die Endpunkte nachgezogen; gilt nur für **neue** Segmente | VERIFIED |
| `Texture` / `TextureContent` | ContentId / Content | "" / none | – | leer → einfarbig | VERIFIED |
| `TextureLength` | float | 1 | UI 0..5 | sofort für alle Segmente | VERIFIED |
| `TextureMode` | TextureMode | Stretch | Stretch/Wrap/Static | Static = „gestempelt“ (Spuren) | VERIFIED |
| `Transparency` | NumberSequence | **0.5 konstant** | – | über die Segment-Lebenszeit. Ob eine Änderung alte Segmente trifft, ist undokumentiert | VERIFIED |
| `WidthScale` | NumberSequence | 1 | **0..1** | Multiplikator auf den **Attachment-Abstand**, zentriert. Werte > 1 wirken laut Bericht nicht (DF:3296080, REPORTED) | VERIFIED |

Methode `Clear()` löscht alle Segmente. Trail hat **kein `Width`, kein `TextureSpeed`, kein `TimeScale` und kein
`ZOffset`.** Die Breite ergibt sich nur aus dem Abstand der Attachments × `WidthScale`. VERIFIED (cls/Trail.yaml,
DUMP). Das versteckte Event `OnClearRequested` (Hidden) wird nicht verwendet.

### 4.2 Verhalten

| # | Regel | Label | Quelle |
|---|---|---|---|
| TR-1 | Ein Trail zeichnet nur bei **Bewegung** der Attachments (≥ `MinLength`). | VERIFIED | cls/Trail.yaml, DOCS:effects/trails.md |
| TR-2 | Edit Mode: „To see the trail, move the part“, mit dem Move-Tool zeichnet er also. Ein **per Skript** pro Frame bewegter Trail im Edit Mode ist nicht belegt. | VERIFIED (Aussage) / ASSUMPTION (Skript-Bewegung) → U17 | DOCS:effects/trails.md, RN:apb C31 |
| TR-3 | Die Trail-Lifetime ist FPS-abhängig: Höhere FPS ergeben kürzere Trails. | REPORTED | DF:821708 |
| TR-4 | Rotationen per CFrame um einen Ursprung und sehr schnelle Bewegungen rendern fehlerhaft (mit Studio-Handles korrekt). | REPORTED | DF:2613978, DF:1853349 |
| TR-5 | Die Engine hat auch für Trails ein LOD („fidelity of trail effects“ steigt mit der QualityLevel), ohne Zahlen. | VERIFIED (qualitativ) | enum/QualityLevel.yaml |
| TR-6 | Studio fügt `Trail` bevorzugt unter `Model` ein. | VERIFIED | RFM |

---

## 5. Attachment (und Bone)

| Property | Typ | Default | Serialisiert | Tags | Hinweis | Label |
|---|---|---|---|---|---|---|
| `CFrame` | CFrame | Identität | **ja** | – | einzige gespeicherte Transform-Property | VERIFIED |
| `Visible` | bool | false | ja | – | grüne Debug-Kugel | VERIFIED |
| `WorldCFrame` | CFrame | Identität | nein (CanLoad=true) | NotReplicated | **schreibbar**, = Parent-CFrame × `CFrame` | VERIFIED |
| `Axis` / `SecondaryAxis` | Vector3 | (1,0,0) / (0,1,0) | nein | NotReplicated | lokale **X** bzw. **Y**-Achse, werden beim Setzen orthogonalisiert | VERIFIED |
| `WorldAxis` / `WorldSecondaryAxis` | Vector3 | – | nein | NotReplicated | abgeleitet | VERIFIED |
| `Position`, `Orientation`, `WorldPosition`, `WorldOrientation` | Vector3 | – | nein (CanLoad=false) | **Hidden**, NotReplicated | abgeleitet und skriptbar; `Orientation` in der Reihenfolge Z, X, Y | VERIFIED |
| `Rotation`, `WorldRotation` | Vector3 | – | nein | **Deprecated** (→ Orientation) | nicht verwenden | VERIFIED |
| `GetAxis`/`SetAxis`/`GetSecondaryAxis`/`SetSecondaryAxis` | Methoden | – | – | **Deprecated** | Properties verwenden | VERIFIED |

- Ein Attachment liegt relativ zu einem Vorfahren `PVInstance`, `Bone` **oder einem anderen Attachment**
  (verschachtelbar). Ohne einen solchen Vorfahren sind `CFrame` und `WorldCFrame` gleich. VERIFIED (cls/Attachment.yaml).
- `CFrame` pro Frame zu schreiben ist der normale Weg, Beam- und Trail-Geometrie zu animieren. VERIFIED (Tag
  `simulationAccess`) / ASSUMPTION (Empfehlung).
- `Bone` ist ein Attachment-Subtyp. Der Pose-Offset wird weder repliziert noch serialisiert. VERIFIED (cls/Bone.yaml).
- `WorldRoot:BulkMoveTo` nimmt nur BaseParts. Attachments setzt man über `CFrame`/`WorldCFrame`. VERIFIED (DUMP).
- Studio fügt Attachments bevorzugt unter `PVInstance` ein. VERIFIED (RFM).

---

## 6. BasePart / Part

`BasePart` ist abstrakt, der Dump enthält keine Defaults. Alle hier genannten Properties haben `R/W None`.

| Property / Member | Typ | Grenze / Regel | Tags · Hinweis | Label | Quelle |
|---|---|---|---|---|---|
| `Size` | Vector3 | jede Komponente **0.001..2048**; unter 0.05 wird **physikalisch** wie 0.05 simuliert, gerendert aber in echter Größe | `NotReplicated`, CanSave=false (wird intern über einen anderen Weg repliziert bzw. serialisiert: ASSUMPTION). Bestimmt das Partikel-Spawnvolumen und die Rendergröße von `SpecialMesh` (Brick/Wedge/Sphere) | VERIFIED | cls/BasePart.yaml, DUMP |
| `CFrame` | CFrame | – | Verschiebung auch bei `Anchored=true` möglich | VERIFIED | cls/BasePart.yaml |
| `Anchored` | bool | – | keine Physikbewegung. Ein verankertes Part **kann trotzdem eine `AssemblyLinearVelocity` ≠ 0 haben** (Förderband-Muster) | VERIFIED | cls/BasePart.yaml (RN:apb C34) |
| `AssemblyLinearVelocity` | Vector3 | – | NotReplicated. Ersetzt das `Hidden`+`Deprecated` `Velocity` | VERIFIED | DUMP |
| `CanCollide` / `CanTouch` / `CanQuery` | bool | `CanQuery` wirkt **nur bei `CanCollide=false`** | alle drei `false` sparen Kollisionsarbeit (Perf-Guide) | VERIFIED | cls/BasePart.yaml, DOCS:performance-optimization/improve.md |
| `CastShadow` | bool | – | **Parts werfen unabhängig von ihrer Transparenz Schatten** (die Engine nimmt Decals an), unsichtbare Träger also auf `false`. Laut BasePart-Doku ist `CastShadow` aber **kein Performance-Schalter** (Artefakte möglich) | VERIFIED | DOCS:performance-optimization/microprofiler/tag-table.md, cls/BasePart.yaml (RN:dp C9) |
| `Transparency` | float | dokumentiert **0..1**; Werte > 1 sind undokumentiert | bei 1 wird das Part **gar nicht gerendert**. Teiltransparenz (0.01..1) läuft in einem eigenen Pass, ist teuer und überlappende Parts sortieren unvorhersehbar. Designregel der Doku: nach Möglichkeit nur 0 oder 1 | VERIFIED | cls/BasePart.yaml, DOCS:performance-optimization/design.md |
| `LocalTransparencyModifier` | float | – | Hidden, NotReplicated, nur clientlokal. Formel wie beim Emitter | VERIFIED | DUMP |
| `Material` | Enum.Material | – | §6.1 | VERIFIED | – |
| `Color` | Color3 | – | Dump: NotReplicated, CanSave=false (Serialisierung über einen internen Weg: ASSUMPTION) | VERIFIED (Tags) | DUMP |
| `BrickColor` | BrickColor | – | nicht tweenbar (REPORTED, §11) | VERIFIED (Typ) | DUMP |
| `Locked` | bool | – | verhindert das Anklicken/Selektieren im 3D-Viewport von Studio (Semantik: ASSUMPTION, nicht in den gelesenen Quellen) | VERIFIED (Existenz) | DUMP |
| `Massless` | bool | – | nur wirksam, wenn an ein massebehaftetes Part geschweißt | VERIFIED | cls/BasePart.yaml |
| `Part.Shape` | PartType | Ball=0, Block=1 (Default), Cylinder=2, Wedge=3, CornerWedge=4, **Capsule=5 (`NotBrowsable`, nicht dokumentiert)** | **Cylinder liegt entlang der X-Achse.** Ob `Ball` eine gleichförmige Größe erzwingt, ist offen (U23) | VERIFIED | enum/PartType.yaml, DUMP |
| `PVInstance:PivotTo(cf)` | – | feuert `Changed` nur für `CFrame`; Offsets im Model werden gecacht (kein Drift) | – | VERIFIED | cls/PVInstance.yaml |
| `Model:ScaleTo(f)` / `GetScale()` | – | skaliert um den Pivot, inklusive Part-Größen, Joints, **Partikel-Emitter-Größen** und `Sound.RollOffMinDistance`; driftfrei | – | VERIFIED | cls/Model.yaml |
| `WorldRoot:BulkMoveTo(partList, cframeList, eventMode = FireAllEvents)` | – | **Default `FireAllEvents`**. Mit `Enum.BulkMoveMode.FireCFrameChanged` (=1) feuert nur `Changed(CFrame)`. Nur BaseParts. Doku: nur nutzen, wenn Bewegung wirklich ein Engpass ist, einzelne CFrame-Sets reichen meist | Security None | VERIFIED | cls/WorldRoot.yaml, enum/BulkMoveMode.yaml, DUMP |

Weitere Befunde:
- `Part.Size` pro Frame zu ändern gilt als teuer. `SpecialMesh.Scale` soll etwa 2× schneller sein (kein
  Collider-Resize). REPORTED (DF:25580, DF:946141, DF:3771329).
- Identische Meshes (gleicher MeshContent und gleiche Textur bzw. gleiches Material) werden in einem Draw Call
  gerendert. VERIFIED (DOCS:performance-optimization/improve.md).
- Bewegte, schattenwerfende Geometrie invalidiert das Voxel-Licht (`computeLightingPerform`). VERIFIED (tag-table.md).

### 6.1 Materialien (VFX-relevant)

| Material | Regel | Label | Quelle |
|---|---|---|---|
| `Neon` | „parts will appear to glow“, ohne Detailangaben. | VERIFIED | cls/BasePart.yaml, DOCS:parts/materials.md |
| `Neon` | Das Glühen hängt von Grafikqualität und Lighting-Technologie ab, nimmt mit steigender Transparenz ab (ab ca. 0.35–0.45) und wird von Bloom verstärkt. | REPORTED | DF:294943, DF:278140 |
| `ForceField` | „Must be used on a MeshPart with UVs … must also have a texture applied to its TextureID“. Auf einer leeren TextureID gibt es einen generischen Glüh-Look. | VERIFIED | enum/Material.yaml |
| `ForceField` | Der Schimmer wird über den **Rotkanal** der Textur gesteuert, seine Animation ist zufällig. `Texture`-Instanzen wirken nicht. Eine ForceField-MeshPart soll zur Laufzeit wie Neon aussehen (Bug). | REPORTED | DF:3041374, DF:423438, DF:301951, DF:2392057 |
| `Glass` | **Halbtransparente Objekte hinter Glass sind unsichtbar.** | VERIFIED | cls/BasePart.yaml |
| `Glass` | „Refraction … is not supported on mobile devices“. | VERIFIED | DOCS:parts/materials.md, enum/Material.yaml |
| `Glass` | Distortion über `Transparency > 1` braucht Grafikstufe ≥ 8. `Transparency > 1` ist undokumentiert. | REPORTED (DF:2338789, DF:2319086, DF:3666977) / VERIFIED (nur 0..1 dokumentiert) | RN:dp C39 |

---

## 7. MeshPart

| Member | Typ | Security / Capability | Regel | Label |
|---|---|---|---|---|
| `MeshId` (ContentId), `MeshContent` (Content) | – | **W: `NotAccessibleSecurity`** (R: None) | **auch Plugins und die Command Bar können sie nicht setzen.** Doku: „cannot be changed directly by scripts, as the collision geometry … cannot be recomputed in real time“ | VERIFIED |
| `MeshID` | ContentId | `Hidden`, `NotScriptable`, **Deprecated** | nicht verwenden | VERIFIED |
| `TextureID` / `TextureContent` | ContentId / Content | None | zur Laufzeit schreibbar (auch `Content.fromObject(EditableImage)`) | VERIFIED |
| `DoubleSided` | bool | None | rendert beide Polygonseiten | VERIFIED |
| `RenderFidelity` | RenderFidelity | **Write-Capability `PluginOrOpenCloud`** | zur Laufzeit **nicht** setzbar. `Automatic` = LOD nach Kameradistanz (< 250 / 250–500 / > 500 Studs) | VERIFIED |
| `CollisionFidelity`, `FluidFidelity` (von `TriangleMeshPart`) | Enums | **Write-Capability `PluginOrOpenCloud`** | „cannot be read or manipulated by scripts during runtime“ | VERIFIED |
| `CollisionPrecision` (von `TriangleMeshPart`) | float | **W: PluginSecurity** | – | VERIFIED |
| `MeshSize` | Vector3 | ReadOnly | – | VERIFIED |
| `ApplyMesh(meshPart)` | Methode | None, **kein `Yields`-Tag → synchron** | überschreibt MeshContent, TextureContent, Render-, Collision- und FluidFidelity (inklusive Kollisionsgeometrie) und MeshSize | VERIFIED (RN:glt C12, Verifier-Korrektur) |
| `AssetService:CreateMeshPartAsync(meshContent: Content, options?)` | → MeshPart | None, **`Yields`** | Optionen für Collision-, Render- und FluidFidelity; „throws errors if creation fails“. Nicht mehr plugin-only | VERIFIED |
| (dasselbe) | – | – | scheitert in der Praxis oft an Asset-Rechten (Asset muss dem Experience-Owner gehören oder mit ihm geteilt sein) | REPORTED (DF:2848207, DF:3798571) |
| `AssetService:LoadAssetAsync(assetId)` | → Instance | None, `Yields`, Capability `LoadUnownedAsset` | moderner Loader. Lädt mit „Allow Loading Third Party Assets“ auch Fremd-Assets. Der Creator Store **beschränkt** ihn in verteilten Assets (§13.11) | VERIFIED |

- Seit wann `MeshId` `NotAccessibleSecurity` ist (früher `PluginSecurity`), ist offen. Ältere Threads nennen noch
  PluginSecurity. REPORTED (DF:3306176, DF:140332).
- Rojo kann `MeshPart.MeshId` nicht live synchronisieren. VERIFIED (rojo.space `sync-details.md`).
- Bewegte skinned MeshParts ohne Humanoid lösen FastCluster-Rebuilds aus. VERIFIED (improve.md).

---

## 8. SpecialMesh / FileMesh / DataModelMesh

| Member | Typ | Default | Security | Regel | Label |
|---|---|---|---|---|---|
| `SpecialMesh.MeshType` | MeshType | **`Head`** | None | Head=0, Torso=1, Wedge=2, Sphere=3, Cylinder=4, FileMesh=5, Brick=6. **Deprecated:** Prism=7, Pyramid=8, ParallelRamp=9, RightAngleRamp=10, CornerWedge=11. Torso „due to be deprecated“. `Sphere` ist „freely resized on all axis“ (Ellipsoid möglich) | VERIFIED |
| `FileMesh.MeshId` / `TextureId` | ContentId | "" | **W: None** | „can be changed by a Script or LocalScript during runtime. The MeshId … of a MeshPart can not.“ | VERIFIED |
| `FileMesh.MeshContent` / `TextureContent` | Content | – | W: None (Write-Capability `Basic`) | Content-Äquivalente | VERIFIED |
| `DataModelMesh.Scale` | Vector3 | – | None | **FileMesh**: relativ zur Originalgröße beim Upload. **Brick/Wedge/Sphere** (und `BlockMesh`): Multiplikator auf `BasePart.Size`. **Cylinder**: Höhe frei, der Durchmesser bleibt 1:1 nach dem kleineren Querwert. Head/Torso skalieren „non standard“ | VERIFIED |
| `DataModelMesh.Offset` | Vector3 | – | None | Render-Versatz | VERIFIED |
| `DataModelMesh.VertexColor` | **Vector3** (kein Color3) | – | None | tönt nur die Textur eines FileMesh | VERIFIED |

- „Offset and Scale can be animated using TweenService relatively inexpensively as the engine does not need to
  make any physics/collision calculations.“ VERIFIED (cls/DataModelMesh.yaml).
- Ein SpecialMesh ändert **nur das Aussehen**, die Kollision bleibt die des Parts. **`BasePart.Material` „displays
  correctly … when using a MeshPart and not when using a SpecialMesh“.** VERIFIED (cls/SpecialMesh.yaml). Ob Neon
  auf Part+SpecialMesh trotzdem brauchbar aussieht, ist offen (U22).
- Legacy-Meshes haben **kein LOD**. Für hohen Polycount sind MeshParts besser. REPORTED (RN:glt C18).
- `CylinderMesh` ist deprecated, `BlockMesh` nicht. `SpecialMesh` ist „the official supported class“. VERIFIED.
- Obergrenze von `Scale` und Verhalten bei Scale ≤ 0: undokumentiert (U23).

---

## 9. Lichter, Post-Effekte, Highlight

### 9.1 PointLight / SpotLight / SurfaceLight

`Light` ist abstrakt, der Dump enthält für alle Lichtklassen keine Defaults. Alle Properties haben `R/W None`.

| Member | Klasse | Typ | Regel | Label | Quelle |
|---|---|---|---|---|---|
| `Brightness` | Light | float | Default 1 (Doku). **Kein Maximum dokumentiert.** Höhere Brightness vergrößert die beleuchtete Fläche nicht | VERIFIED (Default/Verhalten) / offen (Max.) | cls/Light.yaml, DOCS:effects/light-sources.md |
| `Color`, `Enabled` | Light | Color3, bool | – | VERIFIED | DUMP |
| `Shadows` | Light | bool | Schatten-Lichter sind teuer. Unter Qualitätsstufe 4 werden Schatten ganz abgeschaltet (§20) | VERIFIED | cls/Light.yaml, improve.md |
| `Range` | Point/Spot/Surface | float | **max. 120 Studs** („always 120 studs“), Werte darüber werden geklemmt. `Lighting.ExtendLightRangeTo120` ist `NotScriptable` | VERIFIED | cls/Lighting.yaml, DUMP |
| `Angle` | Spot/Surface | float | **max. 180**. SurfaceLight: 0 = gerade nach außen, 180 = parallel zur Fläche | VERIFIED | DOCS:effects/light-sources.md |
| `Face` | Spot/Surface | NormalId | an einem Attachment ist **−Z die Front** | VERIFIED | cls/SpotLight.yaml |

- Ein lokales Licht muss **direktes Kind** eines `BasePart` oder `Attachment` sein, das selbst in `Workspace` liegt.
  Am Attachment strahlt es von `WorldPosition` aus. Ein SurfaceLight an einem Attachment verhält sich wie ein
  SpotLight. VERIFIED (cls/PointLight.yaml, cls/SpotLight.yaml, cls/SurfaceLight.yaml).
- Das Maximum stieg ca. Sept. 2025 von 60 auf 120 Studs. REPORTED (DF:3954367).
- Unter Future-Lighting sind schattenwerfende PointLights ein Hauptkostenfaktor. REPORTED (DF:3875739, DF:1439704).

### 9.2 BloomEffect / ColorCorrectionEffect

| Member | Default (DUMP) | Regel | Label |
|---|---|---|---|
| `BloomEffect.Intensity` / `Size` / `Threshold` | 0.4 / 24 / 0.95 | Size ist der Pixel-Radius (0 = kein Ausbluten). Threshold 1 = nur reines Weiß, 0 = alles | VERIFIED |
| `ColorCorrectionEffect.Brightness` / `Contrast` / `Saturation` / `TintColor` | 0 / 0 / 0 / (1,1,1) | Brightness −1..1. Saturation −1 = Graustufen. TintColor multiplikativ | VERIFIED |

- Post-Effekte wirken **nur bei `Enabled=true` und mit Parent `Lighting` (alle Spieler) oder
  `Workspace.CurrentCamera` (nur der lokale Spieler)**. Mehrere Instanzen kombinieren sich. VERIFIED
  (cls/BloomEffect.yaml, cls/ColorCorrectionEffect.yaml, cls/PostEffect.yaml, DOCS:environment/post-processing-effects.md).
- Auf niedrigen Qualitätsstufen können Post-Effekte ganz entfallen. VERIFIED (enum/QualityLevel.yaml).
- Im ViewportFrame gibt es kein Post-Processing. VERIFIED (cls/ViewportFrame.yaml).
- ColorCorrection „verschluckt“ bei Impact Frames Partikel. REPORTED (DF:2468478, DF:2963136).
- Der Dump enthält weitere Post-Effekte wie `ColorGradingEffect` (nur Existenz VERIFIED, nicht untersucht).

### 9.3 Highlight

| Property | Typ | Default | Security | Label |
|---|---|---|---|---|
| `Adornee` | Instance | nil | None | VERIFIED |
| `DepthMode` | HighlightDepthMode | AlwaysOnTop | None | VERIFIED |
| `Enabled` | bool | true | None | VERIFIED |
| `FillColor` / `FillTransparency` | Color3 / float | (1,0,0) / 0.5 | None | VERIFIED |
| `OutlineColor` / `OutlineTransparency` | Color3 / float | (1,1,1) / 0 | None | VERIFIED |
| `LineThickness` | int | 1 | **RobloxScriptSecurity** (gesperrt) | VERIFIED |

- **Maximal 255** gleichzeitige Highlights pro Client. Weitere werden **still ignoriert**. **Auch deaktivierte
  Highlights belegen einen Slot.** VERIFIED (cls/Highlight.yaml, DOCS:effects/highlighting.md).
- Hinzufügen oder Entfernen löst einen Geometry-Rebuild aus (Spikes, Draw Calls). Properties ändern (auch `Adornee`)
  und `Enabled` umschalten ist leichtgewichtig. Das **erste sichtbare** Highlight kostet bis ca. 1 ms GPU auf Mobile.
  VERIFIED (highlighting.md).
- Das Limit stieg ca. Nov. 2025 von 31 auf 255. REPORTED (DF:4061534).

---

## 10. Sound / SoundService / AudioPlayer

### 10.1 Sound (Capability `LegacySound`, alle `R/W None`)

| Property | Typ | Default | Regel | Label |
|---|---|---|---|---|
| `Volume` | float | 0.5 | Bereich 0..10 | VERIFIED |
| `PlaybackSpeed` | float | 1 | höher = schneller **und** höher. `NotReplicated` | VERIFIED |
| `Playing` | bool | false | Dump: `NotReplicated`. Doku: „will always replicate“ (Widerspruch, unkritisch) | VERIFIED |
| `TimePosition` | double | 0 | NotReplicated. `Play()` startet bei der zuletzt per Skript gesetzten Position (oder 0) | VERIFIED |
| `Looped` | bool | false | – | VERIFIED |
| `SoundId` / `AudioContent` | ContentId / Content | "" / – | frei schreibbar | VERIFIED |
| `PlaybackRegion` / `LoopRegion` | NumberRange | (0, 60000) | nicht tweenbar | VERIFIED |
| `RollOffMode` / `RollOffMinDistance` / `RollOffMaxDistance` | Enum / float / float | Inverse / 10 / 10000 | Inverse, Linear, LinearSquare, InverseTapered | VERIFIED |
| `PlayOnRemove` | bool | false | spielt bei Destroy oder `Parent=nil` | VERIFIED |
| `IsLoaded` / `TimeLength` | bool / double | false / 0 | ReadOnly | VERIFIED |

Methoden: `Play`, `Pause`, `Resume`, `Stop`. Events: `Loaded(soundId)`, `Ended(soundId)`. Ein Sound in einem BasePart
oder Attachment ist positional (Doppler, Distanzdämpfung), sonst global. VERIFIED (cls/Sound.yaml, DUMP).

### 10.2 Edit Mode und Plugin-Vorschau

| # | Befund | Label | Quelle |
|---|---|---|---|
| SND-1 | Im **Properties-Fenster** startet `Playing = true` im Edit Mode **keine** Wiedergabe. Die Doku sagt das **nur** für diesen Toggle. | VERIFIED (nur dieser Fall) | cls/Sound.yaml (RN:glt C38) |
| SND-2 | `Sound:Play()` per Plugin-Skript bleibt im Edit Mode stumm. | REPORTED (nicht VERIFIED) | DF:1927104, DF:2723419, DF:321507 |
| SND-3 | **Ausnahme:** Sounds, die Nachfahren eines `PluginGui`/`DockWidgetPluginGui` sind, spielen im Edit Mode per `:Play()`. Staff-Antwort; das Rojo-Plugin nutzt den Trick. | REPORTED (Staff) | DF:2706107, DF:3579146, DF:1598720 |
| SND-4 | Im Editor läuft `TimePosition` nicht weiter (Staff). `plugin:PlaySound` ist **RobloxScriptSecurity**. | REPORTED / VERIFIED (Security) | DF:321507, DUMP |
| SND-5 | `RunService:Run()` macht Audio hörbar, startet aber die Simulation und deaktiviert Undo. | REPORTED | DF:3579146 |
| SND-6 | Keine dieser Varianten bildet Raumklang (3D-Position) korrekt ab. | ASSUMPTION | – |

### 10.3 SoundService und AudioPlayer

- `SoundService:PlayLocalSound(sound)` (Security None, Capability `Audio`) spielt eine Kopie nur für den aufrufenden
  Client. Übernommen werden Volume, TimePosition, PlaybackSpeed, Spatialisierung und Effekte/SoundGroups, **nicht**
  Looped und AmbientReverb. Die Methode gibt **nichts zurück, also kein Stop-Handle**. VERIFIED (cls/SoundService.yaml,
  DUMP). Aus Plugins sind die Berichte widersprüchlich. REPORTED (DF:1927104).
- `AudioPlayer` (Capability `Audio`): `Asset` (ContentId; `AssetId` ist deprecated), `Volume` (Default **1**),
  `PlaybackSpeed` (double), `TimePosition`, `Looping`, `IsReady` (ReadOnly), `IsPlaying` (**W: RobloxSecurity**).
  `Play(atTime?)` und `Stop(atTime?)` geben `int64?` zurück und werden gegen `SoundService:GetMixerTime()`
  **sample-genau** geplant. Der Player muss per `Wire` an `AudioDeviceOutput` (oder einen Emitter/Listener)
  verdrahtet sein. VERIFIED (cls/AudioPlayer.yaml, DUMP).
- `AudioPlayer` spielt im Edit Mode, wenn er bereit und vorab verdrahtet ist. REPORTED (Staff, DF:4538689, DF:3959457).

---

## 11. TweenService / TweenInfo / EasingStyle

| # | Regel | Label | Quelle |
|---|---|---|---|
| TW-1 | Die Doku listet als tweenbare Typen **„including“** number, boolean, CFrame, Rect, Color3, UDim, UDim2, Vector2, Vector2int16, Vector3 und EnumItem. Die Liste ist **nicht** als abschließend formuliert (Verifier RN:glt C1). | VERIFIED | cls/TweenService.yaml |
| TW-2 | `NumberSequence`, `ColorSequence`, `NumberRange` und `BrickColor` scheitern in der Praxis („… is not a data type that can be tweened“ bzw. „cannot be tweened due to type mismatch“). | REPORTED (Fehlermeldungen) / VERIFIED (fehlen in der Liste) | DF:148063, DF:1240924, DF:1759898, DF:1214259, DF:2035448 |
| TW-3 | Für `PhysicalProperties`, `Content`/`ContentId` und `string` gibt es keinen direkten Beleg. Sie fehlen nur in einer nicht abschließenden Liste. | ASSUMPTION | RN:glt C2 |
| TW-4 | `Tween`/`TweenBase`: nur `Play()`, `Pause()`, `Cancel()`, `PlaybackState` (ReadOnly), `Completed(PlaybackState)`, `Instance` und `TweenInfo` (beide ReadOnly). **Kein Seek, keine Zeitposition, keine Geschwindigkeit.** Die Konfiguration ist nach dem Erstellen unveränderlich. `Pause` wirkt nur im Zustand Playing (nicht Delayed), `Completed` feuert nicht bei Pause, `Cancel` setzt die Properties **nicht** zurück. | VERIFIED | cls/TweenBase.yaml, cls/Tween.yaml, DUMP |
| TW-5 | Zwei Tweens auf dieselbe Property: Der frühere wird abgebrochen und überschrieben. Ein Tween gehört zu genau einer Instanz. | VERIFIED | cls/TweenService.yaml |
| TW-6 | `TweenInfo.new(time=1, easingStyle=Quad, easingDirection=Out, repeatCount=0 (−1 = endlos), reverses=false, delayTime=0)`. Nach dem Erstellen nicht schreibbar. | VERIFIED | dt/TweenInfo.yaml, DUMP |
| TW-7 | `Enum.EasingStyle` in 0.745: Linear 0, Sine 1, Back 2, Quad 3, Quart 4, Quint 5, Bounce 6, Elastic 7, Exponential 8, Circular 9, Cubic 10, **Bezier 11, Spring 12** (im Dump ohne Tags). Die Enum-Doku listet nur 0–10. `EasingDirection`: In 0, Out 1, InOut 2. | VERIFIED | DUMP, enum/EasingStyle.yaml |
| TW-8 | **`TweenInfo.new` und `TweenService:GetValue` werfen einen Fehler bei `Bezier` oder `Spring`.** | VERIFIED | dt/TweenInfo.yaml, cls/TweenService.yaml |
| TW-9 | `TweenService:GetValue(alpha, style, direction) -> number`: klemmt alpha auf [0,1], ThreadSafety **Safe**. | VERIFIED | cls/TweenService.yaml |
| TW-10 | `TweenService:SmoothDamp(current, target, velocity, smoothTime, maxSpeed?, dt?) -> (value, velocity)`: kritisch gedämpfte Feder für number, Vector2, Vector3 und CFrame. | VERIFIED | cls/TweenService.yaml |
| TW-11 | Serverseitiges TweenService repliziert die Property **jeden Frame** (Traffic, Jitter). | VERIFIED | DOCS:performance-optimization/improve.md |
| TW-12 | 2020 lief TweenService in Studio-Edit-Mode-Plugins zeitweise nicht (hing an `Stepped`). Laut Staff zurückgerollt; der aktuelle Stand ist unbestätigt. | REPORTED | DF:474500 |
| TW-13 | Wann Bool- und EnumItem-Tweens umschalten, ist undokumentiert. | offen | – |

Tweenbar oder nicht in den VFX-Klassen (aus Dump-Typen und TW-1/TW-2 abgeleitet): **nicht** tweenbar sind
`ParticleEmitter.Color/Size/Transparency/Squash/Lifetime/Speed/Rotation/RotSpeed/FlipbookFramerate`,
`Beam.Color/Transparency`, `Trail.Color/Transparency/WidthScale`, `Sound.PlaybackRegion/LoopRegion` sowie alle
`*Id`/`*Content`. Tweenbar sind u. a. `ParticleEmitter.Rate/Brightness/LightEmission/ZOffset/TimeScale/Acceleration/SpreadAngle`,
`Beam.Width0/1/CurveSize0/1/TextureSpeed`, `Trail.Lifetime/MaxLength`, `SpecialMesh.Scale/Offset`, die Licht-Properties
und die Bloom/ColorCorrection-Werte. VERIFIED (Typen) / REPORTED (Sequenz-Fehler).

---

## 12. RunService

| Member | Signatur | Security | Regel | Label |
|---|---|---|---|---|
| `PreRender` | `(deltaTimeRender: double)` | None | „replacement for RenderStepped“. **Nur clientseitig** (LocalScript, davon geladenes ModuleScript oder `RunContext = Client`). Das Rendern wartet, bis der Handler fertig ist | VERIFIED |
| `PreAnimation`, `PreSimulation`, `PostSimulation` | `(deltaTimeSim: double)` | None | `PreSimulation` = „replacement for Stepped“. Doku: deltaTimeSim „may deviate … **in Studio edit mode**“ | VERIFIED (Wortlaut) |
| `Heartbeat` | `(deltaTime: double)` | None | aktuell, ohne Migrationsnotiz. Läuft auf Client und Server | VERIFIED |
| `RenderStepped` / `Stepped` | `(deltaTime)` / `(time, deltaTime)` | None | in der Doku „superseded“ (Migration Note), im Dump **nicht** `Deprecated` | VERIFIED |
| `BindToRenderStep(name, priority, fn)` / `UnbindFromRenderStep(name)` | – | None | nur Client. Niedrigere Priorität läuft früher. `Enum.RenderPriority`: First 0, Input 100, Camera 200, Character 300, Last 2000 (`.Value` nutzen). Unbind wirft nicht bei unbekanntem Namen | VERIFIED |
| `BindToSimulation` / `BindToAnimation` (+ `…Parallel`) | `(fn, frequency = Hz30, priority = 2000)` | None | feste Frequenz (`Enum.StepFrequency`). `BindToSimulation` nur mit `Workspace.UseFixedSimulation`. **Wirft bei Zugriff auf nicht synchronisierte Properties** → für VFX ungeeignet | VERIFIED |
| `IsStudio`, `IsClient`, `IsServer`, `IsRunning`, `IsRunMode` | – | None | – | VERIFIED |
| `IsEdit` | – | None, Capability `PluginOrOpenCloud` | – | VERIFIED |
| `RunState` | RunState | **W: PluginSecurity** | Stopped/Running/Paused | VERIFIED |
| `Run()`, `Pause()`, `Stop()` | – | PluginSecurity | `Run()` startet Simulation und Skripte und deaktiviert Undo (REPORTED) | VERIFIED (Security) |

Kontexttabelle (VERIFIED, cls/RunService.yaml):

| Kontext | IsStudio | IsClient | IsServer | IsEdit | IsRunning |
|---|---|---|---|---|---|
| Studio Edit | true | **true** | **true** | true | false |
| Studio Collaborative Edit | true | – | **false** | true | false |
| Run-Modus | true | false | true | – | – |
| Playtest pausiert | – | – | – | **false** | **false** |
| Live-Client | – | true | false | – | – |

„–“ = in den Quellen dieser Recherche nicht erfasst. Nicht raten, bei Bedarf im Test messen.

Verhalten:
- **Pausierter Playtest:** Nur PreAnimation, PreSimulation, PostSimulation und Stepped pausieren. **PreRender,
  Heartbeat und RenderStepped feuern weiter** („maintaining normal functionality of … plugins“). VERIFIED
  (DOCS:studio/testing-modes.md). Doku-Widerspruch: `RunService:Pause` sagt „suspending physics and scripts“,
  testing-modes.md sagt „no effect on running scripts“.
- **Ob `Heartbeat`/`PreRender` im reinen Edit Mode für Plugin-Code jeden Frame feuern, ist nicht dokumentiert.**
  UNVERIFIABLE (RN:glt C35, RN:sp R2, RN:apb N7). Indiz dafür: Der Wortlaut zu PreSimulation/PostSimulation erwähnt
  den Edit Mode (ASSUMPTION). Indiz dagegen: Ein Report von 2020 sagt, `Stepped` feuere im Edit Mode nicht (REPORTED,
  DF:474500). → U1
- `RenderStepped` feuert nicht, wenn Studio minimiert ist oder ein **Script-Tab offen** ist. Heartbeat und Stepped
  laufen dann weiter. REPORTED (DF:1095186).
- Im Run-Modus starten Plugins, bevor `IsRunning()` true liefert. REPORTED (DF:1627560, 2022).
- Frame-Budget bei 60 FPS: 16,67 ms. Frame-Event-Code sparsam halten. VERIFIED (improve.md, design.md).

---

## 13. Plugin / DockWidget / Toolbar / Actions / Menus

### 13.1 Lebenszyklus und DataModel-Erkennung

| # | Regel | Label | Quelle |
|---|---|---|---|
| PL-1 | `plugin.Unloading` (PluginSecurity) feuert direkt vor dem Stoppen: beim Deaktivieren, Deinstallieren, vor einem Update und beim Schließen des Place. **Automatisch entfernt werden nur** `PluginToolbarButton`s, `DockWidgetPluginGui`s und `PluginGui`s, **nicht** eigene Instanzen im DataModel. | VERIFIED | cls/Plugin.yaml |
| PL-2 | In einem älteren Thread feuerte `Unloading` beim Schließen des Place nicht. | REPORTED | DF:1064071 |
| PL-3 | Ob `PluginAction`s und `PluginMenu`s automatisch aufgeräumt werden, ist offen. Eine doppelte `actionId` nach einem Reload könnte kollidieren. | ASSUMPTION → U28 | RN:sp T7 |
| PL-4 | **Plugins laufen auch in den Play-DataModels** (Client/Server) eines Tests. | VERIFIED (indirekt, StudioTestService.yaml, Verifier RN:sp P1) / REPORTED (DF:154621) | cls/StudioTestService.yaml |
| PL-5 | `Plugin.HostDataModelType` ist **RobloxScriptSecurity**, ein Plugin kann es nicht lesen. | VERIFIED | DUMP |
| PL-6 | **`StudioTestService.EditModeActive`** (R/W PluginSecurity, Default true) ist im Edit-DataModel im Leerlauf `true`. Während eines Play- oder Team-Tests ist es `false`, auch im Edit-DataModel. In Client- und Server-DataModels ist es immer `false`. | VERIFIED | cls/StudioTestService.yaml, DUMP |
| PL-7 | `plugin:Activate(exclusiveMouse)` macht das Plugin zum einzigen aktiven. Alle anderen bekommen `Deactivation`. `GetMouse()` liefert eine `PluginMouse`, die erst nach `Activate` voll nutzbar ist. | VERIFIED | cls/Plugin.yaml, cls/PluginMouse.yaml |
| PL-8 | `StudioTestService:ExecutePlayModeAsync/ExecuteRunModeAsync` (PluginSecurity, Yields) starten Tests aus einem Plugin. `GetTestArgs`/`EndTest(result)` übergeben Daten. | VERIFIED | DUMP |

### 13.2 DockWidgetPluginGui

| # | Regel | Label | Quelle |
|---|---|---|---|
| DW-1 | `plugin:CreateDockWidgetPluginGuiAsync(pluginGuiId: string, info: DockWidgetPluginGuiInfo) -> DockWidgetPluginGui` (PluginSecurity, **Yields**). Die Variante ohne Async hat dieselbe Signatur und die Tags `Yields` und **`Deprecated`**. Das Feld `PreferredDescriptorName` steht nur im Full-Dump. | VERIFIED | DUMP (RN:sp W1) |
| DW-2 | Die Umbenennung gehört zur PSA „Several common yielding methods have been renamed“ (laut Drittseite Version 702). Die alten Namen sollen erhalten bleiben. Der Guide `build-studio-widgets.md` zeigt noch den alten Namen. | REPORTED (DF:4257585) / VERIFIED (Guide-Stand) | DOCS:studio/build-studio-widgets.md |
| DW-3 | `DockWidgetPluginGuiInfo.new(initDockState=Right, initEnabled=false, overrideEnabledRestore=false, floatXSize=0, floatYSize=0, minWidth=0, minHeight=0)`: 7 **positionale**, optionale Parameter. FloatingX/YSize gelten nur bei `Float`. `MinWidth` hat ein plattformabhängiges Minimum (Mac ca. 80 px). | VERIFIED | dt/DockWidgetPluginGuiInfo.yaml, TYPES |
| DW-4 | `Enum.InitialDockState`: Top 0, Bottom 1, Left 2, Right 3, Float 4. **Gibt es einen gespeicherten Layout-Eintrag, gewinnt er** über `InitialDockState`, und `HostWidgetWasRestored` (ReadOnly) ist true. Der gespeicherte Enabled-Zustand wird pro `pluginGuiId` geladen, außer bei `InitialEnabledShouldOverrideRestore=true`. | VERIFIED | enum/InitialDockState.yaml, dt/DockWidgetPluginGuiInfo.yaml |
| DW-5 | Dass auch die **Größe** pro ID gespeichert wird und eine umbenannte ID das Layout verwirft, steht nicht in der Doku. | ASSUMPTION (Verifier RN:sp W3) | – |
| DW-6 | Sichtbarkeit über `Enabled` (LayerCollector), Titel über `PluginGui.Title`. `DockWidgetPluginGui:RequestRaise()` ist **RobloxScriptSecurity**. `Plugin:CreateQWidgetPluginGui` ist RobloxScriptSecurity. | VERIFIED | DUMP |
| DW-7 | `PluginGui:BindToClose(fn?)` (Security None) läuft beim Klick aufs Schließen-Kreuz, kann das Schließen aber **weder verhindern noch verzögern**. `Enabled` wird false. | VERIFIED | cls/PluginGui.yaml |

### 13.3 PluginToolbar / PluginToolbarButton

- `plugin:CreateToolbar(name) -> PluginToolbar` und `toolbar:CreateButton(buttonId, tooltip, iconname, text = "")`
  (PluginSecurity). **`CreatePopupButton` ist RobloxScriptSecurity.** VERIFIED (DUMP).
- `PluginToolbarButton`: Event `Click`, `SetActive(bool)`, `Enabled`, `ClickableWhenViewportHidden`, `Icon`
  (ContentId), `IconContent` (Content, **R/W PluginSecurity**, nur Asset-URIs). `SetDropdownActive` und
  `DropdownClick` sind RobloxScriptSecurity. Ist der 3D-Viewport verborgen (z. B. bei offenem Script-Tab), sind
  Buttons deaktiviert, außer mit `ClickableWhenViewportHidden=true`. Für „Widget öffnen“ empfiehlt die Doku `true`.
  VERIFIED (cls/PluginToolbarButton.yaml, DUMP).

### 13.4 PluginAction

- `plugin:CreatePluginAction(actionId, text, statusTip, iconName = "", allowBinding = true) -> PluginAction`
  (PluginSecurity). Event `Triggered`. VERIFIED (DUMP).
- `ActionId`, `AllowBinding` und `StatusTip` sind ReadOnly. **`Text` hat W: RobloxScriptSecurity. `Enabled`,
  `Checked`, `Visible` und `DefaultShortcut` sind R/W RobloxScriptSecurity.** Ein Plugin kann also **kein
  Standard-Kürzel vorgeben**, Actions weder deaktivieren noch abhaken und den Text nicht nachträglich ändern. VERIFIED
  (DUMP, cls/PluginAction.yaml).
- Toolbar-Buttons und PluginActions belegt der **Nutzer** selbst unter **File ⟩ Customize Shortcuts**. VERIFIED.
- PluginAction-Shortcuts sollen nur feuern, solange ein PluginGui des Plugins fokussiert ist. REPORTED, unbestätigt
  (DF:479597) → U6.
- Doku-Widerspruch: Der Parametertext zu `allowBinding` („hidden from shortcuts view“) passt nicht zur
  Property-Beschreibung (true = belegbar). VERIFIED.

### 13.5 PluginMenu

- `plugin:CreatePluginMenu(id, title = "", icon = "")`. Methoden: `AddAction(action)`, `AddNewAction(actionId, text,
  icon = "")` (temporäre Action, im Shortcut-Fenster verborgen), `AddMenu(menu)` (Untermenü; die Doku-Zusammenfassung
  „as a separator“ ist ein Fehler), `AddSeparator()`, `Clear()` und **`ShowAsync()` (Yields)**. ShowAsync öffnet das
  Menü **am Mauszeiger** und gibt die gewählte `PluginAction` oder `nil` zurück. Die Action feuert zusätzlich
  `Triggered`. `PluginMenu.Visible` ist RobloxScriptSecurity. VERIFIED (DUMP, cls/PluginMenu.yaml).
- Folge: keine frei wählbare Position, keine Häkchen, keine deaktivierten Einträge und keine eigenen Widgets im Menü.
  Dynamische Menüs gehen nur über `Clear()` und `AddNewAction`. VERIFIED (abgeleitet aus den Security-Stufen).

### 13.6 Plugin-Settings

- `plugin:SetSetting(key, value)` und `GetSetting(key)` (PluginSecurity) speichern dauerhaft als **JSON-Map mit
  String-Keys**. Arrays werden zu Maps mit String-Schlüsseln. Erlaubte Werte sind string, number, boolean, table und
  nil, **also kein Color3, Vector3 oder EnumItem**. VERIFIED (cls/Plugin.yaml).
- **Diese Zeichen können die Settings-Datei korrumpieren:** ein Backslash in Keys **oder Werten** (besonders `\"`),
  Newline, `"` und **`.` in Keys**. VERIFIED.
- Beide Methoden können **still fehlschlagen**, wenn mehrere Studio-Fenster dasselbe Plugin nutzen. `GetSetting`
  liefert dann `nil`; die Doku rät, „after a short while“ erneut zu prüfen. VERIFIED.
- Ein Größenlimit ist **nicht dokumentiert** (U27).

### 13.7 Eingabe in Widgets

| # | Regel | Label | Quelle |
|---|---|---|---|
| IN-1 | **`UserInputService` funktioniert in Widgets nicht**, weil es den Fokus im Hauptfenster erwartet. TextBox und TextButton funktionieren normal. Für generische Eingabe empfiehlt Roblox einen transparenten Vollflächen-Frame: Nach einem Klick liefert `GuiObject.InputBegan` Tastatureingaben, bis der Nutzer woanders hinklickt. | VERIFIED | DOCS:studio/build-studio-widgets.md |
| IN-2 | **RobloxScriptSecurity, also gesperrt:** `PluginGui.InputBegan/InputChanged/InputEnded`, `MouseEnter`, `MouseLeave`, `PointerAction` und `PluginGui:OverrideStudioAction`. | VERIFIED | DUMP |
| IN-3 | Nutzbar sind: `GuiObject.InputBegan/InputChanged/InputEnded`, `MouseEnter`, `MouseLeave`, `MouseMoved(x,y)`, `MouseWheelForward/Backward(x,y)` (alle Security None). Bei `UserInputType.MouseWheel` steht die Richtung in `InputObject.Position.Z` (> 0 vorwärts). Dazu `PluginGui:GetRelativeMousePosition()` (PluginSecurity) und die Events `WindowFocused` und `WindowFocusReleased`. | VERIFIED | DUMP, cls/GuiObject.yaml, cls/InputObject.yaml |
| IN-4 | `GetRelativeMousePosition()` ändert sich nur, wenn eine Mauseingabe im Widget begann oder die Maus über dem Fenster ist. `WindowFocused` feuert vor `GuiObject.InputBegan`. Bei einem Wechsel zwischen PluginGuis kommt zuerst `FocusReleased` des alten Widgets. | VERIFIED | cls/PluginGui.yaml |
| IN-5 | `TextBox.ClearTextOnFocus` hat den Default **true**. `CaptureFocus`, `ReleaseFocus`, `IsFocused`, `Focused`, `FocusLost(enterPressed, input)`. | VERIFIED | DUMP, cls/TextBox.yaml |
| IN-6 | **Ob Studio-Shortcuts (Delete, Ctrl+Z, Ctrl+D, Ctrl+C/V) auslösen, während ein Input-Catcher-Frame fokussiert ist, ist unbelegt.** Plugins können sie nicht abfangen (IN-2). | UNVERIFIABLE / ASSUMPTION → U6 | RN:sp I4, RN:pro R7 |
| IN-7 | Ist eine TextBox in einem DockWidget **programmatisch** fokussiert, hat das Widget keinen Fokus und Tippen löst Studio-Keybinds aus. | REPORTED (Einzelthread) | DF:266552 |
| IN-8 | Cursor: `plugin:GetMouse().Icon = "rbxasset://SystemCursors/<Name>"` (Arrow, PointingHand, OpenHand, ClosedHand, IBeam, SizeNS, SizeEW, SizeNESW, SizeNWSE, SizeAll, SplitNS, SplitEW, Forbidden, Wait, Busy, Cross). | VERIFIED | DOCS:studio/build-studio-widgets.md |
| IN-9 | `Plugin.DisableUIDragDetectorDrags` ist RobloxScriptSecurity. Ob `UIDragDetector` in Widgets brauchbar ist, ist offen. | VERIFIED (Security) / offen → U42 | DUMP |

### 13.8 Drag & Drop

- `plugin:StartDrag(dragData: Dictionary)` (PluginSecurity) mit `{Sender, MimeType, Data: string, MouseIcon, DragIcon,
  HotSpot}`. Auf dem Ziel-Widget feuern `PluginDragEntered`, `PluginDragMoved`, `PluginDragLeft` und
  `PluginDragDropped` (PluginSecurity), **nur für Drags, die `StartDrag` gestartet hat**. VERIFIED. Drags aus dem
  Studio-Explorer werden darüber vermutlich nicht gemeldet (ASSUMPTION).
- Widerspruch: Laut Dump ist der Parameter ein `Dictionary`, laut `PluginDragEvent.yaml` eine Instanz mit `Data`,
  `MimeType`, `Position` und `Sender`. Ein Feldzugriff per Name funktioniert mit beidem. VERIFIED.
- Die Viewport-Drag-Events (`ViewportDragEntered/Dropped/Left`) sind RobloxScriptSecurity. `PluginMouse.DragEnter(instances)`
  meldet Instanzen, die in den 3D-Viewport gezogen werden. VERIFIED.

### 13.9 Theme und Icons

- `settings().Studio.Theme` (StudioTheme, PluginSecurity) → `Theme:GetColor(Enum.StudioStyleGuideColor,
  Enum.StudioStyleGuideModifier = Default) -> Color3`. `StudioStyleGuideColor` hat in 0.745 **130** Einträge.
  Die Modifier sind Default, Selected, Pressed, Disabled und Hover. Ein Themenwechsel feuert
  `settings().Studio.ThemeChanged`. `Studio["UI Theme"]` ist deprecated. `Studio.Theme` ist mit PluginSecurity auch
  **schreibbar**, ein Plugin darf es trotzdem nie setzen. VERIFIED (DUMP, cls/StudioTheme.yaml, cls/Studio.yaml).
- `StudioService:GetClassIcon(className) -> {Image, ImageRectOffset, ImageRectSize}` (PluginSecurity) liefert die
  Explorer-Icons. VERIFIED.

### 13.10 Gizmos im 3D-Viewport

- `WireframeHandleAdornment` (Security None): `AddLine(from, to)`, `AddLines(points)`, `AddPath(points, loop)`,
  `AddText(point, text, size = 12)`, `Clear()`, Properties `Scale` und `Thickness`. `LineHandleAdornment` und
  `ConeHandleAdornment` existieren ebenfalls. VERIFIED (DUMP).
- Die Punkte sind **relativ zur Mitte des `Adornee`**, nicht in Weltkoordinaten. `Color3`, `Thickness` und
  `Transparency` wirken **nur auf später gezeichnete Linien**; Umfärben heißt `Clear()` und neu zeichnen.
  `Thickness` ist in Pixeln und skaliert nicht mit der Distanz. VERIFIED (cls/WireframeHandleAdornment.yaml, RN:ros C28).

### 13.11 Verteilung (Creator Store) und Upload

- Die Creator-Store-Asset-Regeln **beschränken**: obfuszierten Code, „obscuring engine features“ (LuaVMs, `getfenv`,
  `setfenv`), „requiring remote assets“ (`require(assetId)`, `loadstring`, `InsertService:LoadAsset`,
  `AssetService:LoadAssetAsync`, `ModuleScript.LinkedSource`) und „extremely large scripts“. VERIFIED
  (DOCS:production/creator-store.md, RN:qp2 A7/C5).
- `AssetService:CreateAssetAsync(object, assetType, requestParameters?)` (Yields, Capability `AssetCreateUpdate`) ist
  laut Doku derzeit **nur in lokal geladenen Plugins** nutzbar und lädt ohne Rückfrage hoch. VERIFIED
  (cls/AssetService.yaml, RN:qp2).
- Für Plugins, die Skripte anlegen oder ändern, gibt es einen eigenen Berechtigungsdialog „Script Injection“.
  REPORTED (DF:877312).
- `CoreGui` ist laut Doku auch für Plugins nutzbar. `CoreGui:TakeScreenshot` ist RobloxScriptSecurity. VERIFIED.

---

## 14. ChangeHistoryService (Undo/Redo)

Alle Methoden und Events haben **PluginSecurity**. VERIFIED (DUMP).

| Member | Signatur | Regel | Label |
|---|---|---|---|
| `TryBeginRecording` | `(name: string, displayName: string?) -> string?` | liefert **`nil`**, wenn das Plugin schon eine Recording offen hat (**höchstens eine pro Plugin**) oder der Nutzer im **Solo-Playtest** ist. Die Doku verlangt den Aufruf vor Änderungen, „to avoid future warnings or errors“ | VERIFIED |
| `FinishRecording` | `(identifier: string, operation: FinishRecordingOperation, finalOptions: Dictionary?)` | `Cancel=0`: verwirft und **macht die Änderungen automatisch rückgängig**, ignoriert den Identifier. `Commit=1`: neuer Waypoint. `Append=2`: committet und verschmilzt mit dem vorherigen Waypoint, „if possible“. Wirft, wenn keine Recording läuft oder (außer bei Cancel) die ID nicht passt. **Wirkt nicht, solange der Service deaktiviert ist oder gerade ein Undo/Redo läuft.** | VERIFIED |
| `IsRecordingInProgress` | `(identifier: string?) -> bool` | ohne Argument: irgendeine Recording dieses Plugins | VERIFIED |
| `Undo` / `Redo` | `()` | werfen bei laufendem Play, deaktiviertem Service oder leerer Historie | VERIFIED |
| `GetCanUndo` / `GetCanRedo` | `() -> (bool, name?)` (Tuple) | vorher prüfen | VERIFIED |
| `OnUndo` / `OnRedo` | `(waypoint: string)` | feuern **nach** jedem Undo/Redo, egal ob vom Nutzer oder per Skript. Ob `waypoint` den `name` oder `displayName` einer Recording enthält, ist offen (U9) | VERIFIED |
| `OnRecordingStarted` / `OnRecordingFinished` | `(name, displayName?)` / `(name, displayName?, identifier?, operation, finalOptions?)` | – | VERIFIED |
| `SetWaypoint` | `(name: string)` | laut Doku „will be deprecated soon“, im Dump **ohne** Deprecated-Tag | VERIFIED |
| `SetEnabled(false)` | – | **löscht die Undo-Liste** | VERIFIED |
| `ResetWaypoints` | – | fasst die ganze Historie zu `base` zusammen | VERIFIED |

Weitere Regeln:
- Zur Laufzeit (im Spiel) ist CHS deaktiviert. Die Multi-line Command Bar nutzt ebenfalls Recordings. VERIFIED.
- **Ein Plugin-Reload bricht laufende Recordings nicht ab.** Roblox empfiehlt, die letzte Recording-ID in Attributen zu
  speichern und nach dem Reload abzubrechen. VERIFIED (DOCS:studio/plugins.md). Studio räumt Recordings entladener
  oder gelöschter Plugins nicht auf. Gemeldet wird nur ein Studio-Neustart als Workaround. REPORTED (DF:4108638,
  DF:2944637). Ob das neu geladene Plugin die alte Recording noch sieht, ist offen (U7).
- **Änderungen außerhalb einer Recording:** Im Waypoint-Modell fließen ungeschnittene Änderungen in den nächsten
  Waypoint (der SetWaypoint-Text sagt, ein Aufruf „before a set of changes may clean up another misbehaving plugin“).
  VERIFIED für das Waypoint-Modell. Für das Recording-Modell ist das undokumentiert. Plugin-Aktionen sollen mit
  späteren manuellen Aktionen zu einem Undo-Schritt verschmelzen. REPORTED (DF:2821409, Verifier RN:sp C5) → U8.
- **CHS ignoriert Instanzen mit `Archivable=false`.** REPORTED aus mehreren Threads, keine Doku (DF:11953,
  DF:311724, DF:2179861) → U4.
- **Änderungen an `Source` von Skripten erfasst CHS absichtlich nicht** (Staff: „Working as Designed“, ca. April
  2026). REPORTED (DF:4590702).
- **`Destroy()` ist nicht rückgängig zu machen**, denn danach ist `Parent` gesperrt. Plugins löschen innerhalb einer
  Recording mit `Parent = nil`. REPORTED (DF:3479165, DF:549497).
- Ältere Threads melden, dass CHS Änderungen an `TextLabel/TextBox/TextButton.Text` nicht rückgängig macht und dass
  Attribute im Properties-Widget fehlerhaft mit CHS zusammenspielen. REPORTED, eventuell veraltet (DF:473720,
  DF:1343162) → U5.
- Selektionsänderungen werden in Recordings vermutlich nicht zuverlässig erfasst. ASSUMPTION.

---

## 15. Selection

- `Selection:Get() -> {Instance}`, `Set({Instance})`, `Add({Instance})`, `Remove({Instance})`: **PluginSecurity**.
  VERIFIED (DUMP).
- `SelectionChanged()` hat Security None und **keine Parameter**; die neue Selektion holt man mit `Get()`. `Set` feuert
  nicht, wenn die neue Selektion identisch ist. VERIFIED (cls/Selection.yaml).
- `SelectionThickness` (ReadOnly, Default 0,02 laut Doku) eignet sich, um eigene Overlays an die Studio-Optik
  anzupassen. VERIFIED.
- **Gesperrt** (RobloxScriptSecurity): `ActiveInstance`, `RenderMode`, `SelectionBoxThickness`,
  `SelectionLineThickness`, `ShowActiveInstanceHighlight`, `SelectionChangedThisFrame`, `AddFocusCallback`. VERIFIED.

---

## 16. StudioService / File / Export / Zwischenablage

| # | Regel | Label | Quelle |
|---|---|---|---|
| IO-1 | `StudioService:PromptImportFileAsync(fileTypeFilter = {}) -> File?` (PluginSecurity, Yields) öffnet einen Dateidialog. Gibt `nil` zurück bei Abbruch oder einer Datei **> 100 MB**. Filter ohne Punkt, z. B. `{"json"}`. | VERIFIED | cls/StudioService.yaml, DUMP |
| IO-2 | `PromptImportFilesAsync` liefert eine Liste, **`nil`, wenn irgendeine gewählte Datei zu groß ist**, und `{}` bei Abbruch. Bei einer **leeren Filterliste wirft** sie laut Doku, obwohl `{}` der Default ist (Widerspruch). Die Varianten ohne Async sind `Deprecated`. | VERIFIED | cls/StudioService.yaml (RN:sp F1) |
| IO-3 | `File:GetBinaryContents() -> string` liefert die Rohbytes (Capability `AssetRead`). `File:GetTemporaryId() -> ContentId` liefert eine `rbxtemp://`-ID, die wie `rbxassetid://` nutzbar ist. Sie gilt nur in dieser Studio-Sitzung, wird mit dem `File` zerstört und **nicht in Collaborative Sessions geteilt**. `File.Size` ist Hidden und PluginSecurity. | VERIFIED | cls/File.yaml |
| IO-4 | **Beliebige Dateien schreiben geht nicht.** Plugin-zugänglich sind nur Dialog-Exporte: `Plugin:PromptSaveSelectionAsync(suggestedFileName = "") -> bool` (Yields; die alte Variante ist Deprecated), `PluginManager:ExportSelection/ExportPlace` (nur Geometrie als `.obj`; der Pfadparameter wird ignoriert, es öffnet sich ein Dialog) und `Plugin:SaveSelectedToRoblox` (Upload, nicht auf die Festplatte). `CustomLog` ist InternalTest-only, `FileManagerService` ist RobloxScriptSecurity. | VERIFIED (systematische Dump-Suche) | DUMP, cls/PluginManager.yaml |
| IO-5 | `PromptSaveSelectionAsync` erzeugt `.rbxm`/`.rbxmx`, kein JSON. | ASSUMPTION (Originalnotiz F4), vom Verifier inhaltlich mitgetragen | RN:sp F2 |
| IO-6 | **Zwischenablage: keine.** `StudioService:CopyToClipboard` und `UserInputService:GetPasteText` sind RobloxScriptSecurity. Möglich bleibt nur, dass der Nutzer selbst in eine TextBox einfügt oder aus einer kopiert. | VERIFIED (Sperre) / ASSUMPTION (TextBox-Weg) | DUMP |
| IO-7 | `SerializationService:SerializeInstancesAsync({Instance}) -> buffer` und `DeserializeInstancesAsync(buffer)` (Yields, Capability `PluginOrOpenCloud`) nutzen das `.rbxm`-Binärformat. Für das Format gibt es **keine Stabilitätszusage**. | VERIFIED | cls/SerializationService.yaml, DUMP |

---

## 17. ScriptEditorService und `Script.Source`

- `Script.Source` und `ModuleScript.Source` (ProtectedString) haben Security None/None, aber die **Capability
  `PluginOrOpenCloud`** für Lesen und Schreiben. Plugins dürfen beides, normale Spielskripte bekommen einen Fehler.
  Die Doku rät vom direkten Editieren ab, wenn das Skript im Editor offen ist. VERIFIED (DUMP, cls/Script.yaml).
- `ScriptEditorService:UpdateSourceAsync(script, callback(oldSource) -> newSource?)` (PluginSecurity, **Yields**):
  Ist das Skript offen, schickt die Methode eine Update-Anfrage an den Editor. Lehnt der Editor ab (veraltete Source),
  wird der Callback **erneut** aufgerufen. Der Callback **darf nicht yielden**; `nil` bricht ab. Ist das Skript nicht
  offen, wird die Source direkt gesetzt. VERIFIED (cls/ScriptEditorService.yaml).
- `GetEditorSource(script)` liefert den Editor-Text und kann von `Source` abweichen. Weitere PluginSecurity-Member:
  `OpenScriptDocumentAsync`, `FindScriptDocument`, `GetScriptDocuments`, `TextDocumentDidOpen/DidChange/DidClose`,
  Autocomplete- und ScriptAnalysis-Callbacks. `Plugin:OpenScript` ist deprecated. `OpenStringValueDocumentAsync`,
  `OpenTemporaryDocumentAsync`, `EditSourceAsyncWithRanges`, `SetUriScript` und `ForceReloadSource` sind
  **RobloxScriptSecurity**. VERIFIED (DUMP).
- `Source`-Änderungen erscheinen **nicht** in der Undo-Historie. REPORTED (Staff, DF:4590702).
- Effektive Längengrenze von `Script.Source`: 200 000 bzw. 199 999 Zeichen. REPORTED (DF:227797, DF:23520).
- Wie Source-Schreibzugriffe von Plugins mit dem Team-Create-Drafts-Modus zusammenspielen, ist nicht dokumentiert
  (U29). VERIFIED (Modi existieren, DOCS:projects/collaboration.md).
- **Require-by-string in der Engine:** `./` → `script.Parent`, `../` → `script.Parent.Parent`, `@self/` → `script`,
  `@game/` → `game`. **Nicht blockierend**: Fehlt das Modul, wird sofort ein Fehler geworfen (kein implizites
  WaitForChild). VERIFIED (DOCS:reference/engine/globals/LuaGlobals.yaml). Ob die Engine Aliases unterstützt
  (`.config.luau`), ist undokumentiert. `ScriptService:ResolveModulePath` existiert (Security None, Tag
  `CustomLuaState`), ist aber undokumentiert. VERIFIED (Existenz) / offen (U43).

---

## 18. HttpService in Plugins

| # | Regel | Label | Quelle |
|---|---|---|---|
| HT-1 | Plugins dürfen `HttpService` nutzen. Beim ersten Zugriff auf eine Adresse **kann** Studio um Erlaubnis für genau diese Adresse fragen. Erlauben, Verweigern und Widerrufen geht im Fenster **Plugin Management**. | VERIFIED | DOCS:cloud-services/http-service.md („Use in plugins“) |
| HT-2 | Plugins dürfen ausdrücklich mit Software auf demselben Rechner über **`localhost` und `127.0.0.1`** sprechen, z. B. für Dateisystemzugriff. Diese Software muss getrennt vom Plugin verteilt werden. | VERIFIED | ebd. |
| HT-3 | `HttpService.HttpEnabled`: W **LocalUserSecurity**, Default false. Die Doku formuliert „Allow HTTP Requests“ **allgemein**, nicht nur für Spiele; der Plugin-Abschnitt erwähnt es nur nicht. **Dass Plugins ohne HttpEnabled funktionieren, ist REPORTED bzw. gängige Praxis** (Rojo, DF:493269 von 2020). | VERIFIED (Security, Doku-Text) / REPORTED (Plugin-Praxis) | DUMP, http-service.md (Verifier RN:sp H1) |
| HT-4 | Lokal installierte Plugins umgehen die Berechtigungsdialoge. Die Freigabe gilt pro Domain, Subdomains brauchen eine eigene. | REPORTED (2020, eventuell veraltet) | DF:493269 |
| HT-5 | `RequestAsync(requestOptions)` (Yields, Capability `Network`): Die URL muss `http` oder `https` nutzen. Grenze laut Doku: 500 externe HTTP-Requests pro Minute (pro Game-Server). Ob das für Plugins gilt, ist unklar. | VERIFIED (Text) / ASSUMPTION (Geltung) | cls/HttpService.yaml |
| HT-6 | Die Regeln HTTPS-only und Port-Sperre (< 1024 außer 80/443, außerdem 1194) stehen in einem eigenen Abschnitt „Limitations“ nach „Use with Open Cloud“. Ob sie für Plugin-Requests an localhost gelten, ist formal mehrdeutig. Rojo nutzt `http://localhost:34872`. | VERIFIED (Text) / ASSUMPTION (Geltung) | http-service.md (RN:tc C30) |
| HT-7 | `HttpService:CreateWebStreamClient(streamClientType: WebStreamClientType, requestOptions) -> WebStreamClient` (Security None, Capability Network): Typen SSE=0, RawStream=1, WebSocket=2. **Nur in Studio**, **höchstens 4 Clients gleichzeitig**. | VERIFIED | cls/HttpService.yaml, DUMP |
| HT-8 | `WebStreamClient` erbt von **`Object`**, nicht von Instance. `Send(data: string)` funktioniert nur bei WebSocket, sonst „does nothing“. Dazu `Close()`, `ConnectionState` (Connecting/Open/Error/Closed) und die Events `Opened(statusCode, headers)`, `MessageReceived(message)`, `Error(statusCode, errorMessage)` und `Closed()`. | VERIFIED | cls/WebStreamClient.yaml, DUMP |
| HT-9 | Das Rojo-Plugin verbindet sich standardmäßig mit `localhost:34872` über `http://` und baut seit 7.7.0-rc.1 eine `ws://`-Verbindung per `CreateWebStreamClient` auf. Die DevForum-Ankündigung zeigt ein Beispiel mit `ws://localhost:8080`. | VERIFIED (Produktquelltext, Changelog) / REPORTED (Ankündigung, DF:4021932) | `https://raw.githubusercontent.com/rojo-rbx/rojo/master/plugin/src/Config.lua`, `…/ApiContext.lua` |
| HT-10 | `JSONEncode` und `JSONDecode` (Security None, Tag `CustomLuaState`) existieren. Wie `JSONEncode` leere Tabellen, NaN/inf und große Zahlen kodiert, ist hier nicht geprüft (U32). Größenlimits für Request- bzw. WebStream-Nachrichten aus Plugins sind undokumentiert (U33). | VERIFIED (Existenz) / offen | DUMP |
| HT-11 | `HttpService:SetHttpEnabled` und `GetHttpEnabled` sind RobloxScriptSecurity. | VERIFIED | DUMP |

---

## 19. ViewportFrame / WorldModel

| # | Regel | Label | Quelle |
|---|---|---|---|
| VP-1 | Offiziell **keine Schatten, kein Post-Processing**. Neon und Glass rendern in niedrigster Qualität, verschachtelte GuiObjects werden nicht unterstützt. Ohne `Sky`-Kind ist die Beleuchtung wie `EnvironmentSpecularScale`/`EnvironmentDiffuseScale` = 0, mit Sky-Kind (nur die sechs Skybox-Texturen) wie = 1. | VERIFIED | cls/ViewportFrame.yaml, DOCS:ui/viewport-frames.md |
| VP-2 | Defaults: `Ambient` (200,200,200), `LightColor` (140,140,140), `LightDirection` (−1,−1,−1), `ImageColor3` weiß, `ImageTransparency` 0. `CurrentCamera` muss eine `Camera` sein (typisch als Kind). | VERIFIED | DUMP |
| VP-3 | **`ViewportFrame:CaptureSnapshotAsync()` ist RobloxScriptSecurity.** Ein Plugin kann damit keine Thumbnails rendern. | VERIFIED | DUMP |
| VP-4 | **ParticleEmitter, Beam und Trail rendern im ViewportFrame nicht.** Die Doku schweigt dazu. Ein Feature-Request vom Juni 2026 bestätigt den Stand. | REPORTED | DF:252266, DF:599553, DF:2133446, DF:3151410, DF:4706068 |
| VP-5 | Fire, Smoke, Sparkles, Explosion und lokale Lichter rendern bzw. leuchten dort vermutlich auch nicht; es gibt nur das eigene gerichtete Licht plus Ambient. | ASSUMPTION → U19 | RN:sp V4 |
| VP-6 | `WorldModel` als Kind eines ViewportFrames erlaubt Animation (inklusive Humanoid-Joints) und räumliche Abfragen, aber **keine Physiksimulation**. `UseWorkspaceCollisionGroups` existiert. Die Doku rät, WorldModels nur bei Bedarf zu erzeugen. | VERIFIED | cls/WorldModel.yaml |
| VP-7 | 3D-Objekte rendern nur unter einem `WorldRoot` (Workspace, Camera in Workspace oder WorldModel). `CoreGui` taugt nur für GUIs und Adornments. | ASSUMPTION | RN:sp A5 |

---

## 20. UserGameSettings, RenderSettings, Stats, SceneAnalysisService (Qualität und Messung)

### 20.1 Spieler-Grafikqualität

| Member | Typ | Security | Regel | Label |
|---|---|---|---|---|
| `UserSettings():GetService("UserGameSettings").SavedQualityLevel` | SavedQualitySetting | R/W None, Capability `Players` | Automatic=0, QualityLevel1..QualityLevel10 = 1..10. Nur clientseitig sinnvoll; in Studio spiegelt der Wert die eigenen Einstellungen | VERIFIED |
| `GraphicsQualityLevel` (die tatsächlich genutzte Stufe), `MaxQualityEnabled`, `GraphicsOptimizationMode` | – | **RobloxScriptSecurity** | nicht lesbar | VERIFIED |
| `ReducedMotion` | bool | **RobloxScriptSecurity**, Hidden | Spieler-Wunsch „weniger Bewegung“ **nicht lesbar** | VERIFIED |
| `DataModel.GraphicsQualityChangeRequest(betterQuality)` | Event | – | feuert **nur bei F10 / Shift+F10**, nicht bei Änderungen im Escape-Menü. Doku: „There is currently no way for developers to reliably get the current graphics quality level“ (bei Automatic) | VERIFIED |
| `Stats:GetHarmonyQualityLevel()` | → int | Security None, aber Capability **`InternalTest`** | für normale Skripte nicht aufrufbar | VERIFIED |

- Änderungen lassen sich mit `GetPropertyChangedSignal("SavedQualityLevel")` erkennen. Bei Automatic bleibt die
  effektive Stufe unbekannt. REPORTED (DF:2719633, DF:2947801).
- Im Automatik-Modus regelt der Frame Rate Manager die Qualität dynamisch. VERIFIED (enum/GraphicsOptimizationMode.yaml).

### 20.2 Qualitätsskalen und Engine-LOD

- `Enum.QualityLevel` hat **22 Einträge** (Automatic + Level01..Level21), `RenderSettings:GetMaxQualityLevel()` = 22.
  Der Spieler-Slider hat 10 Stufen. **Eine offizielle Zuordnung 1–10 ↔ 1–21 gibt es nicht.** Eine inoffizielle
  FastFlag-Tabelle nennt eine nicht monotone Zuordnung. VERIFIED (Enums) / REPORTED (Mapping,
  https://fastflagforge.github.io/Docs/fast-flags/graphical-settings, DF:792183).
- `enum/QualityLevel.yaml`: Mit steigender Stufe steigen „rendering distance, shading quality, apparent geometry and
  texture resolution, limits on particles that are being rendered, fidelity of trail effects, post-effect quality“.
  Die Wirkung je Feature ist „platform- and device-specific and **can not be relied upon**“. VERIFIED.
- **Schatten werden unter Qualitätsstufe 4 ganz abgeschaltet.** Welche Skala „4“ meint, ist **nicht dokumentiert**.
  VERIFIED (Aussage, improve.md, tag-table.md) / offen (Skala, RN:dp C8).
- `Lighting.PrioritizeLightingQuality` (Default true; Write-Capability `PluginOrOpenCloud`) entscheidet, ob bei
  sinkender Qualität zuerst Schatten/Shader oder die Sichtweite reduziert werden. VERIFIED (cls/Lighting.yaml, DUMP).

### 20.3 RenderSettings (Studio)

- `settings().Rendering` (`RenderSettings`): `QualityLevel`, `EditQualityLevel` (beide `Enum.QualityLevel`),
  `EnableFRM` (Hidden), `AutoFRMLevel`, `FrameRateManager`, `MeshPartDetailLevel` und `GetMaxQualityLevel()`. Alle
  sind **R/W PluginSecurity**. `EditQualityLevel` gilt bei `EnableFRM = false`. VERIFIED (DUMP, cls/RenderSettings.yaml).
- Die Doku empfiehlt, jeden Effekt bei niedrigster und höchster „Editor Quality Level“ zu prüfen (wortgleich in
  particle-emitters.md, beams.md, trails.md). VERIFIED.
- Ein Schreibzugriff ändert die Studio-Einstellung des Nutzers. ASSUMPTION (RN:dp C21).

### 20.4 Mess-APIs

- `Stats` (Security None, ReadOnly, NotReplicated): `FrameTime` (s, **nur Client**), `RenderCPUFrameTime`,
  `RenderGPUFrameTime`, `HeartbeatTime`, `PhysicsStepTime`, `InstanceCount`, `PrimitivesCount`,
  `MovingPrimitivesCount`, `SceneDrawcallCount`, `SceneTriangleCount`, `ShadowsDrawcallCount`,
  `ShadowsTriangleCount`, Netzwerk-Kbps. `HeartbeatTimeMs` und `PhysicsStepTimeMs` sind deprecated. VERIFIED.
- `Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.GraphicsParticles | GraphicsTexture | …)` liefert 0 plus eine
  Warnung, wenn `MemoryTrackingEnabled = false` (ändert sich nur beim Client-Neustart). `GetTotalMemoryUsageMb()`
  braucht keine Capability, `GetMemoryUsageMbAllCategories` u. Ä. brauchen `InternalTest`. VERIFIED.
- `SceneAnalysisService:GetTriangleCompositionAsync()` (Security None, Yields) liefert Dreiecke und Draw Calls **pro
  Render-Pass** (Opaque, Transparent, Decal, **Particles**, Shadows, UI …). `GetInstanceCompositionAsync()` liefert
  Instanzzahlen. Die Werte gelten **szenenweit, nicht pro Effekt**. „Designed for use during play and test
  sessions“, die Werte „don't necessarily match what players see“. Ob die API in Live-Spielen funktioniert, ist
  undokumentiert. VERIFIED / offen (U35).
- `debug.profilebegin/profileend` und `debug.setmemorycategory/resetmemorycategory` markieren eigene Bereiche.
  VERIFIED.
- Das Beispiel-Budget der Doku (unter 1 000 Draw Calls und 1 000 000 Dreiecken) ist **kein Limit**. Gerätebasis:
  Android ist ca. 65 % eines typischen Player-Base, davon ~60 % mit 2–4 GB RAM. VERIFIED (design.md, test-on-hardware.md).

---

## 21. RemoteEvent, UnreliableRemoteEvent, Streaming

### 21.1 Remotes

| # | Regel | Label | Quelle |
|---|---|---|---|
| RE-1 | `RemoteEvent` und `UnreliableRemoteEvent`: `FireServer`, `FireClient(player, …)`, `FireAllClients`, `OnServerEvent(player, …)` und `OnClientEvent` (Security None, Capability `RemoteEvent`). | VERIFIED | DUMP |
| RE-2 | `RemoteEvent` ist zuverlässig und geordnet, **auch über verschiedene RemoteEvent-Instanzen hinweg** (bezogen auf den Start der Handler; yieldende Handler können sich überholen). Ohne Handler wird begrenzt gequeued. Überschuss beim Throttle wird verzögert. | VERIFIED | DOCS:scripting/events/remote.md |
| RE-3 | `UnreliableRemoteEvent` ist ungeordnet und unzuverlässig. **Payloads > 1000 Bytes werden verworfen.** Über dem Throttle werden Nachrichten **verworfen statt verzögert**. Ohne Listener gibt es **kein Queueing**. Zu RemoteEvents besteht keine Ordnungsbeziehung. Buffer werden komprimiert, die Größe ist deshalb vor dem Senden schwer prüfbar. | VERIFIED | cls/UnreliableRemoteEvent.yaml, remote.md |
| RE-4 | Die Ankündigung nannte 900 Bytes (der Verifier konnte das nicht prüfen). Community-Tests: ca. 908 B effektiv, mit Buffern bis ~3,8 KB. Kostenschätzungen: number ≈ 9 B, bool ≈ 2 B, Vector3 ≈ 13 B, CFrame ≈ 14–20 B, Instance-Ref ≈ 6 B, String ≈ 1 B/Zeichen + 2–3 B. | REPORTED | DF:2724155, DF:3038324, DF:3048788 |
| RE-5 | Throttle: **ca. 500 Requests/s pro Client** Client→Server, geteilt über alle Remotes desselben Typs. | VERIFIED | cls/RemoteEvent.yaml, cls/UnreliableRemoteEvent.yaml |
| RE-6 | Argumente: Eine beim Empfänger nicht replizierte Instanz kommt als `nil` an. Nicht-String-Schlüssel werden zu Strings. Gemischte Tabellen und `nil`-Löcher sind zu vermeiden. Metatabellen gehen verloren, Funktionen kommen als `nil` an. | VERIFIED | remote.md |
| RE-7 | Die oft zitierten ~50 KB/s pro Client stammen aus älterer Doku und Tests und sind aktuell nicht offiziell dokumentiert. | REPORTED | DF:580567, DF:2873609 |
| RE-8 | Offizielle Empfehlung: Explosionen und Zauber nicht serverseitig als Instanzen erzeugen. „The server only needs to know the location“, die Clients erzeugen die Visuals. Große Instanzbäume zu erzeugen oder zu zerstören ist netzwerkintensiv. | VERIFIED | DOCS:performance-optimization/improve.md |

### 21.2 StreamingEnabled

| # | Regel | Label | Quelle |
|---|---|---|---|
| ST-1 | Ein Remote-Signal und die Instanz, auf die es verweist, reisen **unabhängig**. Die Referenz kann `nil` sein, später kommen oder nie (außerhalb des Radius). Auch String-Pfade lösen sich dann nicht auf. Strategien: `WaitForChild` **mit Timeout**, `Player:RequestStreamAroundAsync()` („likely (though not guaranteed)“) oder ein nil-Check. | VERIFIED | DOCS:workspace/streaming/techniques.md |
| ST-2 | Ausgestreamte Instanzen werden nach `nil` umgehängt, **nicht** zerstört. **Lokale Änderungen** an server-eigenen Instanzen können verloren gehen, gelesene Positionen können „beliebig veraltet“ sein. | VERIFIED | DOCS:workspace/streaming/index.md, techniques.md |
| ST-3 | **Clientseitig erzeugte oder geklonte Instanzen werden nicht ausgestreamt**, außer sie hängen unter einer server-erzeugten Instanz. | VERIFIED | streaming/index.md (RN:dp C31) |
| ST-4 | Streaming gilt nur für Workspace-Nachfahren und ist für neue Places Standard. `Workspace.StreamingEnabled` ist **per Spielskript nicht setzbar** (Dump: Write-Capability nur `PluginOrOpenCloud`). Verankerte Assemblies streamen nur die Parts im Radius. Client-Physik läuft nur in gestreamten Bereichen. | VERIFIED | streaming/index.md, DUMP |

---

## 22. Weitere Engine-Bausteine

| Baustein | Regel | Label | Quelle |
|---|---|---|---|
| `Instance.Archivable` | `false` nimmt die Instanz **mitsamt Nachfahren** aus Speichern und Veröffentlichen heraus und aus dem `Clone()` eines Vorfahren. Ein direktes `Clone()` liefert `nil`. **Studio-Duplicate und Copy/Paste ignorieren das Flag und setzen die Kopie auf `true`.** | VERIFIED | cls/Instance.yaml |
| `Instance.Archivable` + Team Create | Ob nicht-archivierbare Instanzen in Workspace zu Mitarbeitern repliziert werden, ist unbekannt. | offen → U20 | RN:sp A5, A2 |
| `Camera` | Die Klasse trägt den Tag **`NotReplicated`**. Laut Staff werden Kameras in Team Create nicht repliziert. Ein Ordner unter `workspace.CurrentCamera` bleibt also wahrscheinlich lokal pro Collaborator. | VERIFIED (Tag) / REPORTED (DF:3438378) / ASSUMPTION (Kinder) | DUMP |
| Rojo-Builds | Seit Rojo 7.4.4 ist `Archivable` in Binärbuilds standardmäßig `true`. | VERIFIED | Rojo-Changelog |
| `Debris:AddItem(item, lifetime = 10)` | **Hartes Maximum von 1000 Objekten.** Darüber werden die ältesten **sofort** zerstört. `MaxItems` ist deprecated, `SetLegacyMaxItems` hat LocalUserSecurity. Debris läuft außerhalb des Skriptkontexts und zerstört auch noch, wenn das Skript endet. | VERIFIED | cls/Debris.yaml, DUMP |
| `StringValue.Value` | **max. 200 000 Zeichen**, darüber der Fehler „String too long“. `Changed(value)` übergibt den neuen Wert. | VERIFIED | cls/StringValue.yaml |
| `StringValue.Value` | effektive Grenze **199 999** (genau 200 000 scheitert). | REPORTED | DF:227797, DF:23520 |
| `EncodingService` | Security None: `Base64Encode/Base64Decode(buffer)`, `CompressBuffer/DecompressBuffer` (`Enum.CompressionAlgorithm.Zstd`), `GetDecompressedBufferSize`, `ComputeStringHash/ComputeBufferHash` (`Enum.HashAlgorithm`: Blake2b, Blake3, Md5, Sha1, Sha256). | VERIFIED | DUMP |
| `ContentProvider:PreloadAsync(list, cb?)` | Yields, Capability `AssetManagement`. Lädt in den Disk-Cache; die Engine **kann die Texturen danach wieder aus dem Speicher entladen**. | VERIFIED | cls/ContentProvider.yaml |
| Partikel-Texturen | Selten genutzte Partikeleffekte erscheinen verzögert. | REPORTED | DF:2718982 |
| `Workspace.GlobalWind` | Vector3, steuert `WindAffectsDrag` (nur bei Drag > 0). Fire und Smoke folgen dem Wind standardmäßig. | VERIFIED | DOCS:environment/global-wind.md |

---

## 23. Toolchain-Grenzen (Rojo 7.7.1, Lune 0.11.1, Script Sync, Studio MCP, Open Cloud)

| # | Regel | Label | Quelle |
|---|---|---|---|
| TC-1 | Rojo `syncRules` (seit 7.5) `{ "pattern": "*.vfx.json", "use": "text", "suffix": ".vfx.json" }` erzeugt eine `StringValue` mit dem **unveränderten JSON-Text** (inklusive `null` und `[]`). Sync-Rules werden zwischen Projektdateien zurückgesetzt. | VERIFIED (LOCAL, Changelog 7.5.0 #813) | RN:tc C3 |
| TC-2 | **`.json` → ModuleScript ist verlustbehaftet:** Schlüssel werden sortiert, `null` verschwindet, `[]` und `{}` werden gleich, große Ganzzahlen verlieren Präzision. Außerdem cacht `require`. | VERIFIED (LOCAL) | RN:tc C2 |
| TC-3 | `rojo syncback` (7.7) überspringt bestehende JSON-Module („Cannot syncback Json … skipping“). **Mit der `syncRules`-Text-Regel schreibt syncback eine geänderte StringValue byte-genau in die vorhandene `*.vfx.json` zurück.** Neue StringValues landen als `Name.txt`. Der Weg braucht eine aus Studio gespeicherte `.rbxm`/`.rbxl` und ist nicht live. | VERIFIED (LOCAL, Verifier-Korrektur RN:tc C7/N1) | RN:tc |
| TC-4 | syncback normalisiert `.model.json`: Default-Werte entfallen (`"Rate": 20` wird gelöscht), `Texture` wird zu `TextureContent`, Zahlen werden als Floats geschrieben (`1.0`). | VERIFIED (LOCAL) | RN:tc N2 |
| TC-5 | `rojo build --plugin` und `rojo plugin install` schlagen unter **Linux** fehl („Your platform is not currently supported“). `-o build/X.rbxmx` funktioniert überall. | VERIFIED (LOCAL) | RN:tc C6 |
| TC-6 | `rojo serve` lauscht auf `127.0.0.1:34872`, `/api/rojo` liefert MessagePack. Seit 7.7.0 prüft Rojo Host/Origin gegen DNS-Rebinding, bei `0.0.0.0`-Binds ohne `--allowed-hosts` aber nicht. Seit 7.7.0-rc.1 nutzt das Plugin WebSockets. Live nicht synchronisierbar: Binärdaten, `MeshPart.MeshId`, `HttpEnabled`. Two-Way-Sync ist „optional“ und war als experimentell markiert; welche Edits unterstützt werden, ist undokumentiert. | VERIFIED (LOCAL, Changelog, sync-details.md) / offen (Two-Way) | RN:tc C8, C9 |
| TC-7 | Lune 0.11.1: Die Reflection-DB ist **0.741** (Engine 0.745). Es gibt **keine Events/Signals, keine Engine-Methoden** (`ParticleEmitter:Emit` → „not a valid member“) und keine Simulation. **Alle Properties sind les- und schreibbar, auch nicht-skriptbare.** Es fehlen `TweenInfo`, `DateTime`, `Random`, `RaycastParams` und `OverlapParams`. | VERIFIED (LOCAL, Typdefinitionen) | RN:tc C11, C12 |
| TC-8 | Lune-Falle: Ein neuer `ParticleEmitter` wirft beim Lesen von `p.Texture` („missing default value“), und `p.Texture = …` ändert `TextureContent` nicht. Beim Serialisieren migriert Lune ein allein gesetztes `Texture` zu `TextureContent`. Sind beide gesetzt, entstehen **zwei** `TextureContent`-Einträge. | VERIFIED (LOCAL) | RN:tc C13, N5 |
| TC-9 | `@lune/serde` json: sortierte Schlüssel, leere Tabelle → `{}`, **gemischte Tabellen verlieren still die String-Schlüssel**, **NaN/inf → `null`**, `null` → nil. | VERIFIED (LOCAL) | RN:tc C15, N6 |
| TC-10 | `@lune/net`: `net.serve` bindet ohne `address` an **127.0.0.1**. HTTP und WebSocket funktionieren. Breaking Change in 0.11.0: `handle:stop()`. | VERIFIED (LOCAL) | RN:tc C14 |
| TC-11 | Requires in Lune: `./`, `../`, `@self/` und `.luaurc`-Aliases funktionieren, **`.config.luau`-Aliases nicht**. `require("./data.json")` ist unmöglich. `script` und `game` sind nil. In `X/init.luau` zeigt `./Kind` auf ein Geschwister des Ordners, eigene Kinder erreicht man mit `@self/Kind`. | VERIFIED (LOCAL) | RN:tc C17, C39 |
| TC-12 | Studio **Script Sync** (eingebaut) synchronisiert zweiseitig, aber **nur Script, LocalScript, ModuleScript und Folder**. **Attributes und Tags werden ignoriert.** Limits: 10 000 Skripte pro Wurzel, 128 Wurzeln. `InstanceFileSyncService` und `LiveSyncService` (PluginSecurity) erlauben die Abfrage des Zustands. | VERIFIED | DOCS:scripting/sync.md, DUMP |
| TC-13 | Studio hat einen **eingebauten MCP-Server** (stdio, Quick Connect auch für Claude Code) mit Tools wie `execute_luau`, `multi_edit`, `script_read`, `inspect_instance`, `screen_capture`, `start_stop_play` und `get_console_output`. Laut Doku können MCP-Clients offene Places lesen und ändern. `Roblox/studio-rust-mcp-server` wird nicht mehr entwickelt. | VERIFIED | DOCS:studio/mcp.md |
| TC-14 | **Studio läuft nur unter Windows und macOS.** In Linux/CI-Sandboxes gibt es kein Studio, kein MCP und keinen Live-Sync. | VERIFIED | DOCS:studio/setup.md |
| TC-15 | Open Cloud Luau Execution: keine Physik, Skripte im Place laufen nicht automatisch, Änderungen werden nicht persistiert. Grenzen: Skript ≤ 4 MB, Laufzeit ≤ 5 min, JSON-Rückgabe ≤ 4 MB, Logs ≤ 450 KB, **5 Task-Erstellungen pro Minute** pro Key-Owner, ≤ 10 unvollständige Tasks pro Place. Braucht einen API-Key und einen veröffentlichten Place. Place Publishing: ≤ 10 MiB, 30/min, BETA. | VERIFIED | DOCS:reference/cloud/openapi.json, DOCS:cloud/guides/usage-place-publishing.md |

---

## 24. Konsequenzen für ASTRA

Alle Einträge in der Spalte „Designentscheidung“ sind **IDEA**. Die Spalte „Constraint“ trägt das Label des
zugrunde liegenden Fakts. Das Label der Entscheidung wird dadurch nicht höher.

| K | Constraint (Label, §) | Designentscheidung (IDEA) | Betrifft |
|---|---|---|---|
| K1 | Kein Seed, kein Partikelalter, `FastForward` gesperrt, `TimeScale` nur 0..1 (VERIFIED, §1.3) | Native Partikel sind **nicht exakt seekbar**. `seek(t)` = `Clear()` + „replay-to-t“ (Effekt ab 0 in Echtzeit abspielen, bei t mit `TimeScale=0` einfrieren; Latenz ≈ t) **oder** eine ASTRA-eigene Vorschausimulation. Deterministisch ist nur der Burst-Zeitplan. UI-Hinweis „engine-randomisiert“. | Player.seek, Timeline, Preview |
| K2 | TimeScale-Bugs in Studio (REPORTED, §1.6) | Pause und Zeitlupe per TimeScale erst nach U2 freigeben. Fallback: Clear + Replay. Stand: der Player setzt für Pause/Zeitlupe `TimeScale` über `setTimeScale` (MODULE_CONTRACTS §10/§17) – U2 ist weiterhin offen. | Preview, Player |
| K3 | ≤ 20 lineare Keypoints, Time 0/1, symmetrische Envelopes (VERIFIED, §2) | Kurven im ASTRA-Format reich halten (Bezier, Easing) und **backen**: adaptives Sampling + Ramer-Douglas-Peucker auf ≤ 20 KP, Fehlermarke im Editor. Step-Kurven bis zu U13 mit ε-Versatz statt doppelter Zeit. Ein gemeinsamer Sequenz-Evaluator für Runtime, Preview und Analyzer (DT-5). | Curves, Compiler |
| K4 | Color/Acceleration/LightEmission/ZOffset live (VERIFIED), Size/Transparency/Squash live (ASSUMPTION), Rate/Speed/Lifetime/Rotation nur neu (VERIFIED) (§1.2) | Zwei Spurarten: **Emissions-Events** (Burst, Enable-Fenster, Rate-Kurve) und **Live-Property-Spuren** (treffen alle lebenden Partikel). Das UI erklärt den Unterschied „über die Effektzeit“ vs. „über die Partikel-Lebenszeit“. | Timeline, Compiler |
| K5 | Property-Writes an Emittern sind teuer, Emitter-Bewegung kostet (VERIFIED, §1.6) | Dirty-Check mit ε pro Kanal, optionale Update-Rate pro Kanal (z. B. 30 Hz). Lieber Lebenszeit-Sequenzen als Per-Frame-Kanäle. Der Analyzer zählt Emitter-Writes/s und bewegte Emitter. | Player, Analyzer |
| K6 | `Instance.new`-Defaults ≠ Studio-Defaults (`LightInfluence`, VERIFIED). Emit direkt nach dem Parenten kann verpuffen (REPORTED). Texturprüfung beim Setzen (REPORTED, FB-6) | Der Builder setzt **jede** Property explizit aus einer aus dem Dump generierten Default-Tabelle (`engineVersion: "0.745"`). Reihenfolge: Anker/Attachments (`CFrame`) → Instanz mit allen Properties, **`TextureContent` vor `FlipbookLayout`**, `Attachment0/1` zuletzt → parenten → **≥ 1 Frame warten** vor dem ersten `Emit`. | Builder, Player |
| K7 | Off-screen-Emit verzögert bzw. zurückgesetzt (REPORTED, §1.3) | Die Timeline nimmt nicht an, dass `Emit` sofort sichtbar wird. Gameplay-Events nie an Partikel-Sichtbarkeit koppeln. Gerätetest U14. | Player |
| K8 | Rate ≤ 400/s (Mobile 100/s) laut Doku; für Emit undokumentiert (VERIFIED/offen) | Harter Lint nur für `Rate`. Für Burst-Summen eine Warnung. Low-Profil: Rate ≤ 100/s pro Emitter. | Analyzer, Quality |
| K9 | Klassenspezifische Grenzen (VERIFIED, §1–4): Lifetime ≤ 20 und > 0, FlipbookFramerate ≤ 30, LightEmission 0..1, Emitter-LightInfluence außerhalb 0..1 **undefiniert**, Beam/Trail-LightInfluence geklemmt, Beam/Trail-Brightness 0..10000, TimeScale 0..1, Trail-Lifetime 0.01..20, WidthScale 0..1, Width ≥ 0, NumberRange min ≤ max | Validator-Regeln **pro Klasse**: Emitter-LightInfluence außerhalb 0..1 = Fehler, bei Beam/Trail = Warnung (Clamp). | Validation |
| K10 | Flipbook-Texturregeln widersprüchlich, Kompatibilität nicht abfragbar, Abschaltung bei Speichermangel (VERIFIED/REPORTED, §1.4) | Sicherer Standard **1024²** mit Padding. Warnung bei Layout ≠ None ohne bekannte 1024²-Textur. Flipbook-Layer bekommen einen Fallback und `minQuality` Medium. | Validation, Presets |
| K11 | `FlipbookIncompatible` wird serialisiert, ist aber nur Text. LTM/VelocitySpread CanSave=false. Abgeleitete Attachment-Properties (VERIFIED) | Nicht ins ASTRA-Format: `FlipbookIncompatible` (**Designentscheidung**, kein API-Fakt), `LocalTransparencyModifier`, `VelocitySpread`, alle abgeleiteten Attachment-Properties. | Format |
| K12 | `TextureContent` aktualisiert `Texture` (VERIFIED). In Lune nicht gekoppelt (VERIFIED LOCAL) | Runtime und Plugin schreiben **nur `TextureContent = Content.fromUri(uri)`**. Das Format speichert den URI-String. Die Lune-Fakes bilden die Kopplung nach. | Builder, Tests |
| K13 | `rbxtemp://` nur sitzungslokal. Object-Content repliziert nicht. EditableImage im Live-Spiel gesperrt (VERIFIED, §2, §16) | `rbxtemp://` und `Content.fromObject` nur für lokale Editor-Previews. Export und Runtime-Build lehnen sie ab. | Validation, Export |
| K14 | Beam-Breite nur linear, Breitenachse undokumentiert, Segments-LOD (REPORTED), n−1 nur Untergrenze (§3) | Taper/Bauch über verkettete Beams. Attachment-Roll-Konvention erst nach U3 festlegen. Beam-Sequenzen mit **gleichmäßigen** Keypoint-Zeiten backen. Segments ≥ n−1 als Warnung. **Beam.Segments im Low-Profil nicht herunterskalieren** (`segmentScale = 1` für Beams, abweichend von ARCHITECTURE §5.4). | Builder, Quality |
| K15 | Beam/Trail ohne TimeScale, Trails altern in Echtzeit, Trail-Breite = Attachment-Abstand × WidthScale ≤ 1 (VERIFIED, §3–4) | Slow-Mo: Beam über `TextureSpeed=0` + `SetTextureOffset` pro Frame aus der Effektzeit (deterministisch). Trail-Lifetime nur näherungsweise skalieren. Ein `width`-Parameter im Format wird in Attachment-Offsets übersetzt. | Player, Builder |
| K16 | Trail braucht Bewegung, ein Attachment-Wechsel löscht ihn, FPS-abhängige Lifetime (VERIFIED/REPORTED, §4) | Die Preview animiert Attachment-CFrames. Attachments eines Trails nie mitten im Effekt tauschen. dt-Kompensation erst nach U17. | Player |
| K17 | Bei Attachments wird nur `CFrame` serialisiert (VERIFIED, §5) | Das Format speichert Position + Rotation (Grad, `CFrame.fromOrientation`), der Builder rechnet in `CFrame` um. Abgeleitete Properties nie in Dateien. | Format, Builder |
| K18 | Sphere/Cylinder an einem Attachment fehlerhaft (VERIFIED, PE-2) | Volumen-Shapes nur mit unsichtbarem Hilfs-Part (wie ARCHITECTURE §4). Validator-Warnung. | Builder |
| K19 | VelocityInheritance bei CFrame-animierten Ankern ungetestet (UNVERIFIABLE). Verankerte Parts können eine AssemblyLinearVelocity tragen (VERIFIED) | Bewegte Effekte über `LockedToPart` oder animierte Attachments. Optional setzt die Runtime `AssemblyLinearVelocity` am Anker, erst nach U15. | Runtime |
| K20 | Kein Tween-Seek, Sequenzen nicht tweenbar, Bezier/Spring werfen (VERIFIED/REPORTED, §11) | Eigene Zeitauswertung (ADR 2). Kein TweenService in Timeline und Runtime. ASTRA-eigene `bezier`/Spring-Easings nie an `TweenInfo.new`/`GetValue` geben. `GetValue` nur als Test-Referenz für die Styles 0–10 (Toleranz 1e-4). Die TweenService-Typliste dient nur als konservative Allow-List, nicht als Roblox-Fakt. | Curves, Easing, Tests |
| K21 | `:Lerp` nur für 5 Typen (VERIFIED, DT-10) | Lerp-Tabelle im Codec: eigene Lerps für number, UDim, Rect, Vector2int16 (runden), NumberRange und Sequenzen. Bool- und Enum-Kanäle als Step. | Codec |
| K22 | `MeshPart.MeshId` nicht schreibbar, Fidelity-Properties nur `PluginOrOpenCloud`, `ApplyMesh` synchron (VERIFIED, §7) | `mesh` = Part + SpecialMesh (ADR 5). MeshPart nur als **Vorlage** (Clone). `CreateMeshPartAsync` nur als asynchrones Prewarm mit pcall, nie im Frame. Runtime-Builder-Whitelist lehnt Properties mit Write-Security ≠ None oder einschränkender Capability ab; die Liste wird aus dem Dump generiert. | Builder, Validation, tools |
| K23 | SpecialMesh-Default `Head`, Scale-Semantik je Typ, Material auf SpecialMesh nicht korrekt (VERIFIED, §8) | Der Builder setzt `MeshType` immer. Allow-List: Brick, Sphere, Cylinder, Wedge, FileMesh. Der Compiler kennt die Scale-Semantik je Typ. `Part.Size` bleibt konstant, animiert wird `SpecialMesh.Scale`. Neon auf SpecialMesh erst nach U22. | Builder, Compiler |
| K24 | Decal- und SurfaceAppearance-Maps PluginSecurity, ContentId-Map-Varianten sogar lesend PluginSecurity (VERIFIED, DUMP) | PBR/Emissive-Looks nur über mitgelieferte Vorlagen. Animierbar bleiben `EmissiveStrength`, `EmissiveTint`, `Color` und UV-Properties. | Builder |
| K25 | `PartType.Capsule` (NotBrowsable), `EasingStyle.Bezier/Spring` undokumentiert bzw. werfend (VERIFIED) | In Schema v1 nicht freigeben. | Schema |
| K26 | Schatten unabhängig von Transparenz; CastShadow kein Perf-Schalter; CanQuery nur bei CanCollide=false (VERIFIED, §6) | Träger-Parts: `Anchored`, `CanCollide/CanTouch/CanQuery = false`, `Transparency = 1`, `CastShadow = false`. Lint: unsichtbarer Träger mit CastShadow = Fehler, sichtbare VFX-Geometrie = Hinweis. | Builder, Analyzer |
| K27 | `BulkMoveTo` ist standardmäßig `FireAllEvents`, nur BaseParts (VERIFIED, §6) | Immer `Enum.BulkMoveMode.FireCFrameChanged` übergeben. Attachments per `CFrame`. | Player |
| K28 | PreRender nur auf dem Client; Heartbeat im Edit Mode unbelegt (UNVERIFIABLE); RenderStepped stoppt bei offenem Script-Tab (REPORTED); Edit: IsClient **und** IsServer true (VERIFIED, §12) | Scheduler: Live-Client `PreRender` (oder `BindToRenderStep`, Priorität `Camera.Value + 1`), Live-Server **nur `Heartbeat`**, Plugin-Vorschau `Heartbeat`. Effektzeit aus `os.clock()`, nicht aus summierten dt. **Smoke-Test U1 als erste Phase-2-Aufgabe.** Das Runtime-Modul verzweigt nicht über `IsServer`/`IsClient`, sondern bekommt den Kontext übergeben. | Scheduler |
| K29 | Bei Pause feuern Heartbeat und PreRender weiter (VERIFIED) | Bei `IsEdit()==false and IsRunning()==false` die Effektzeit optional anhalten. | Scheduler |
| K30 | Lichter direktes Kind; Range ≤ 120; Angle ≤ 180; kein Brightness-Maximum (VERIFIED, §9.1) | `light` immer als direktes Kind eines Attachments oder Parts. Validator klemmt Range und Angle, warnt bei `Shadows = true` und ab einer Brightness-Schwelle (z. B. > 40). | Validation, Builder |
| K31 | Post-Effekte nur unter Lighting oder CurrentCamera (VERIFIED, §9.2) | Runtime: clientseitig unter `Workspace.CurrentCamera`, eigene Instanzen pro Effekt. Vorschau ebenfalls unter der Kamera, mit `Archivable = false` und dem Attribut `AstraPreview`. Nie `Lighting` des Places ändern. | Builder, Preview |
| K32 | Highlight: 255 Slots inklusive deaktivierter, Rebuild bei Add/Remove (VERIFIED, §9.3) | Kleiner, konfigurierbarer Pool (≪ 255). Properties und `Enabled` ändern, lange ungenutzte zerstören. Der Analyzer zählt Highlights. | Runtime, Analyzer |
| K33 | Sound im Edit Mode: Properties-Toggle spielt nicht (VERIFIED), Skript-`Play` stumm (REPORTED), PluginGui-Ausnahme (REPORTED) (§10) | Vorschau-Reihenfolge: (a) Sound-Klon unter dem ASTRA-DockWidget, (b) `AudioPlayer` + `Wire` + `AudioDeviceOutput`, (c) `PlayLocalSound`, (d) Hinweis „Audio nur im Playtest“. **Nie `RunService:Run()`.** Runtime: Sound am Attachment, `TimePosition` vor `Play()` setzen, über `IsLoaded`/`Loaded` vorwärmen. | Preview, Runtime |
| K34 | ViewportFrame: keine Partikel/Beams/Trails (REPORTED), kein Post-FX, kein `CaptureSnapshotAsync` (VERIFIED) (§19) | Workspace-Vorschau primär (ADR 7). Der Viewport zeigt nur Geometrie und markiert den Rest als Platzhalter. Thumbnails sind vorab erzeugt oder eine 2D-Näherung, als „Approximation“ gekennzeichnet. | Preview |
| K35 | `Archivable=false` wird nicht gespeichert; CHS ignoriert es (REPORTED); Duplicate macht es archivierbar (VERIFIED); Camera NotReplicated (VERIFIED) | Preview-Ordner mit `Archivable = false` und Attribut `AstraPreview`, BaseParts `Locked = true`. Ort: `workspace.CurrentCamera` (Team-Create-lokal, ASSUMPTION) oder Workspace; Entscheidung nach U20. Ein `SelectionChanged`-Wächter lenkt die Selektion auf das Dokument-Element um. Beim Start und Speichern verwaiste Kopien suchen und melden. | Preview |
| K36 | `Unloading` räumt nur Widgets und Buttons auf und feuert eventuell nicht (VERIFIED/REPORTED, §13.1) | Idempotentes `Shutdown()`: Preview entfernen, Connections trennen, offene Recording mit `FinishRecording("", Cancel)` abbrechen, `RenderSettings` wiederherstellen. Beim Start Reste über das Attribut aufräumen. Persistenz nie an `Unloading` hängen. | Plugin |
| K37 | Plugins laufen in Play-DataModels (VERIFIED/REPORTED); `IsEdit()` beim Start im Run-Modus unzuverlässig (REPORTED); `EditModeActive` (VERIFIED) | Den Editor nur bei `StudioTestService.EditModeActive == true` (plus `IsEdit()`) initialisieren und auf Änderungen reagieren. In Play-DataModels keine Widgets und keine Recordings. `EditModeActive` nur lesen. **Abweichend von ARCHITECTURE §7.3** (dort nur `IsEdit()`). | Plugin |
| K38 | Widget-API (VERIFIED, §13.2–13.3) | Nur `CreateDockWidgetPluginGuiAsync` in einer Startsequenz (yieldet). Feste, nie umbenannte IDs (`ASTRA_Explorer`, …). `ClickableWhenViewportHidden = true`. Button-Zustand über das `Enabled`-Signal synchron halten, weil `BindToClose` nicht verhindert. | WidgetHost |
| K39 | Keine Default-Shortcuts, kein Disable/Check, Studio-Shortcuts nicht abfangbar (VERIFIED/UNVERIFIABLE, §13.4–13.7) | PluginActions mit `allowBinding = true` ohne Default. Widget-lokale Tasten über einen Input-Catcher-Frame. **Delete, Ctrl+Z, Ctrl+D und Ctrl+C/V nicht binden, bis U6 geklärt ist.** Menüs lassen deaktivierte Einträge weg. Kontextmenüs werden gecacht und dynamisch per `Clear` + `AddNewAction` gefüllt. | Input, Menus |
| K40 | Settings: JSON, verbotene Zeichen, stilles Scheitern (VERIFIED, §13.6) | SettingsStore mit flachen ASCII-Keys ohne Punkt (`astra_v1_layout`). Strings mit Sonderzeichen Base64 über `EncodingService`. Color3/Vector3 selbst zerlegen. Nach dem Schreiben gegenlesen. Keine großen Daten. | Settings |
| K41 | CHS-Recording-Modell (VERIFIED, §14) | HistoryAdapter: eine Recording zur Zeit, Beginn beim Start einer Geste, Commit am Ende, `Cancel` bei Fehlern (pcall). `nil` → Toast „Undo im Playtest nicht verfügbar“. **Keine Commands aus `OnUndo`/`OnRedo`-Handlern.** Beim Start `IsRecordingInProgress()` prüfen und die Recording-ID als Attribut speichern. **Dokument-Instanzen nie `Destroy()`en**, sondern `Parent = nil` (REPORTED). Preview-Instanzen während einer Recording nur, wenn `Archivable=false`. | History |
| K42 | `Source`-Änderungen nicht undo-fähig (REPORTED, §14/17) | Das editierbare Dokument liegt **nicht** in `ModuleScript.Source`, sondern als `StringValue` (ADR 6). Ob `StringValue.Value` und `SetAttribute` sauber undo-fähig sind, klärt U5 vor Phase 2. Generierte Runtime-Module per `UpdateSourceAsync` (Callback ohne Yield), außerhalb der Undo-Historie. | Storage |
| K43 | Kein Datei-Schreiben, kein Clipboard (VERIFIED, §16) | Import: `PromptImportFileAsync({"json"})` → `GetBinaryContents` → `JSONDecode` → Validierung, oder ein Paste-Feld (`ClearTextOnFocus = false`). Export: (a) localhost-Bridge, (b) Rojo `syncRules` + `syncback` (ohne Bridge: `PromptSaveSelectionAsync` → `.rbxm` → `rojo syncback`), (c) Kopierfeld. | IO |
| K44 | localhost erlaubt, Prompt möglich, ≤ 4 WebStreamClients, Port-Regel mehrdeutig (VERIFIED/ASSUMPTION, §18) | Die Bridge bindet nur an `127.0.0.1`, Port ≥ 1024 und ≠ 1194, mit Session-Token. Host/Origin-Prüfung immer, auch unabhängig vom Bind. Höchstens **eine** WebSocket-Verbindung (Rojo belegt eventuell eine). Fallback: `RequestAsync`-Polling unter 500/min. Onboarding erklärt den Berechtigungsdialog. Die Bridge bleibt optional. | Bridge |
| K45 | StringValue ≤ 200 000 (VERIFIED), effektiv 199 999 (REPORTED); Rojo/Lune prüfen nicht (VERIFIED LOCAL) | Die CLI zählt **Bytes** (`#s`): Warnung ab 150 000, harter Fehler über 199 999. | CLI, Validation |
| K46 | JSON→ModuleScript verlustbehaftet; serde-Fallen (VERIFIED LOCAL, §23) | Effekte als `*.vfx.json` über `syncRules` (Text) synchronisieren, **nicht** JSON→ModuleScript (**abweichend von ARCHITECTURE §8(a)**). Das Format kennt kein semantisches `null`; ob Array oder Objekt, bestimmt das Schema. Eigener deterministischer Encoder. Der Validator lehnt gemischte Tabellen und NaN/inf vor jedem Encode ab. | Json, CLI |
| K47 | Lune ≠ Engine (VERIFIED LOCAL, TC-7/8) | Testpyramide mit einer Liste bekannter Abweichungen. Grüne Lune-Tests heißen nicht „in Studio verifiziert“; Statusführung getrennt in PROGRESS.md. | Tests |
| K48 | Require-Semantik (VERIFIED, §17, TC-11) | Instance-Requires (ADR 11) oder nur `./`, `../`, `@self/`. Keine Aliases, kein `@game/` im Runtime-Modul. Daten nie per `require` laden. | Code |
| K49 | Effektive Grafikqualität bei Automatic unlesbar, ReducedMotion gesperrt, keine offizielle Skalenzuordnung (VERIFIED, §20) | `Quality.detect()`: `SavedQualityLevel` per pcall. Bei Automatic eine Heuristik (Plattform-Startprofil, geglättete `FrameTime`/`RenderGPUFrameTime` mit Hysterese, Wechsel nur zwischen Effekten). `SavedQualityLevel` **nie schreiben**. Die Zuordnung 1–3/4–7/8–10 ist Konfiguration (ASSUMPTION). Kamera-Shake und Flash haben einen Spieler-Multiplikator und sind standardmäßig gedämpft. | Quality |
| K50 | Engine-LOD intransparent (REPORTED/VERIFIED qualitativ, §1.6, §20.2) | Der Analyzer rechnet Engine-LOD **nicht** nach und ist ausdrücklich heuristisch. Quality-Preview über `EditQualityLevel` mit Presets niedrig/mittel/hoch; den Originalwert immer wiederherstellen (auch in `Shutdown`). | Analyzer, Preview |
| K51 | Client-Visuals, Unreliable ≤ 1000 B, Streaming-Regeln (VERIFIED, §21) | Der Server baut nie VFX-Instanzen. Net-Payload ≤ 900 B (konservativ), bei Überschreitung zuverlässiges RemoteEvent. Sequenznummer oder Servertime mitsenden. Unreliable nur für ersetzbare, kosmetische Effekte (nie Telegraphs). Effekt-Root als **lokales** Part, das dem Ziel per CFrame folgt. Optionale Attach-ID + `WaitForChild`-Timeout, sonst mit dem gesendeten CFrame spielen. | Net, Runtime |
| K52 | Debris-Cap 1000 (VERIFIED, §22) | Kein Debris im Runtime-Code. Eigenes Cleanup über Scheduler und Pool (`Parent = nil`), dazu ein Fallback: alle Instanzen unter einem Root, der beim Entladen zerstört wird. | Runtime |
| K53 | Creator-Store-Regeln; `CreateAssetAsync` nur lokal (VERIFIED, §13.11) | Kein obfuszierter Code, kein `loadstring`/`require(assetId)`/`LoadAssetAsync` in Plugin oder Runtime. Textur-Upload nur mit Feature-Detection und klarer Fehlermeldung. | Distribution |
| K54 | `shared.vfx` wird von VFX Forge und Phase VFX belegt (REPORTED/VERIFIED, RN:other) | Keine `shared`-Globals. Falls nötig, nur `shared.AstraVFX`. | Runtime, Plugin |
| K55 | ZOffset nur bei Emitter und Beam (VERIFIED) | Eine „Draw Order“-UI bildet nur auf `ZOffset` ab, mit Hinweis. Trails haben keine Reihenfolge. | Inspector |
| K56 | Glass-Refraktion nicht auf Mobile (VERIFIED); `Transparency > 1` undokumentiert | Distortion-Komponente mit `minQuality = High`, auf Mobile ausgeschlossen, mit Fallback-Layer. | Components |
| K57 | WireframeHandleAdornment-Semantik (VERIFIED, §13.10) | Trajektorien- und Spawn-Gizmos mit einem Adornment pro Emitter (`AddPath`), Koordinaten im Adornee-Raum. Umfärben = `Clear()` + neu zeichnen. | Plugin-Gizmos |
| K58 | PreloadAsync kann wieder entladen (VERIFIED) | `AstraVFX.Preload` ruft `PreloadAsync` und wärmt den Pool vor. Ein unsichtbarer Warm-up-Emit ist optional und muss gemessen werden. | Runtime |
| K59 | MCP und Open Cloud brauchen Windows/macOS bzw. einen API-Key (VERIFIED, §23) | Nur optionale Verifikationsstufen. Die Kernpipeline (JSON → Lune-CLI → Rojo) muss ohne sie funktionieren. | Workflow |

**Abweichungen zur aktuellen `docs/ARCHITECTURE.md`, die nachgezogen werden müssen (IDEA):** §5.4 `segmentScale` nicht
auf `Beam.Segments` anwenden (K14). §7.3 Editor-Gate über `EditModeActive` statt nur `IsEdit()` (K37); den Ort des
Preview-Ordners nach U20 festlegen (K35). §7.3 sagt, der Viewport zeige „keine dynamischen Lichter“; das ist laut
VP-5 nur eine ASSUMPTION (U19) und sollte so gekennzeichnet werden. §8(a) Rojo-Sync über `syncRules`-Text statt
JSON→ModuleScript (K46).

---

## 25. Nicht unterstützt / nicht erfinden

Diese Dinge gibt es in Engine 0.745 **nicht** oder sie sind für ASTRA **gesperrt**. Code, Schema, Doku und
Claude-Generierung dürfen sie nicht voraussetzen. Labels in Klammern.

**Partikel**
- Kein `ParticleEmitter.Seed` und keine andere Seed-Property (VERIFIED).
- Kein Zugriff auf einzelne Partikel (Position, Alter, Velocity), kein `GetParticles()` o. Ä. (VERIFIED).
- Keine Spawn-, Death- oder Collision-Events pro Partikel und keine Sub-Emitter. `OnEmitRequested`/`OnClearRequested`
  sind versteckte interne Events (VERIFIED).
- Kein `FastForward` und kein Prewarm (RobloxScriptSecurity, VERIFIED). Kein Setzen des Partikelalters (VERIFIED).
- Kein `TimeScale > 1` laut Doku, Verhalten undokumentiert (VERIFIED/ASSUMPTION). Kein Rückwärtslaufen.
- Keine Mesh-Partikel, keine eigenen Shader oder Materialien für Partikel (VERIFIED, RN:pro R2).
- Keine Pfadverfolgung oder Bezier-Bahnen: Die Bewegung kommt nur aus Speed, Acceleration, Drag, VelocityInheritance
  und LockedToPart (VERIFIED, RN:ros C14).
- Keine nicht-lineare Sequenz-Interpolation, nicht mehr als 20 Keypoints, keine asymmetrischen Envelopes und keine
  eingebaute Sequenz-Auswertung (VERIFIED).
- Keine Abfrage der Flipbook-Kompatibilität (VERIFIED, FB-5).
- Keine Render-Reihenfolge außer `ZOffset` (VERIFIED).
- `ParticleEmitter2D` nicht verwenden (NotBrowsable, FFlag, VERIFIED).

**Beam / Trail**
- Beam: keine Breitenkurve (nur Width0→Width1), kein `Clear`, kein `TimeScale`, keine Events, kein Getter für den
  Textur-Offset. `TextureMode.Static` wird wie Wrap behandelt. Kein dokumentiertes Segments-Maximum (VERIFIED).
- Trail: kein `Width`, kein `TextureSpeed`, kein `TimeScale`, kein `ZOffset`, keine Wirkung von `WidthScale > 1`
  (VERIFIED/REPORTED). Kein Zeichnen ohne Bewegung (VERIFIED).

**Geometrie, Licht, Effekte**
- Kein Schreiben von `MeshPart.MeshId`/`MeshContent`, auch nicht als Plugin (VERIFIED). Kein Laufzeit-Schreiben von
  `RenderFidelity`, `CollisionFidelity`, `FluidFidelity` und `CollisionPrecision` (VERIFIED).
- Keine Laufzeit-Zuweisung von Decal- und SurfaceAppearance-Maps (PluginSecurity, VERIFIED).
- Keine korrekten Materialien auf SpecialMesh laut Doku (VERIFIED).
- Keine Licht-Range über 120. Lichter nur als direktes Kind eines Part oder Attachments. Kein Bloom pro Objekt
  (VERIFIED).
- Kein `Highlight.LineThickness`, nicht mehr als 255 Highlights (VERIFIED).
- `PartType.Capsule` und `EasingStyle.Bezier/Spring` nicht verwenden (VERIFIED).

**Tween / Zeit**
- Kein Tween-Seek, keine Zeitposition, keine Geschwindigkeitsänderung. Keine Tweens auf NumberSequence,
  ColorSequence oder NumberRange (VERIFIED/REPORTED). Kein `Instance.new("Tween")` (VERIFIED).
- Kein `PreRender` und kein `BindToRenderStep` auf dem Server (VERIFIED). **Keine dokumentierte Garantie, dass
  `Heartbeat` im Edit Mode feuert** (UNVERIFIABLE). `RunService:Run()` nicht für die Vorschau (REPORTED: Undo aus).
- `BindToSimulation`/`BindToAnimation` nicht für VFX (VERIFIED).

**Sound**
- Kein zuverlässiges `Sound:Play()` im Edit Mode außerhalb eines PluginGui (REPORTED). `plugin:PlaySound` ist gesperrt
  (VERIFIED). `PlayLocalSound` liefert kein Handle und kein Looped (VERIFIED). `AudioPlayer.IsPlaying` ist nicht
  schreibbar (VERIFIED).

**Plugin / Studio**
- Kein Default-Shortcut; `PluginAction` lässt sich nicht deaktivieren, abhaken, verstecken oder umbenennen
  (VERIFIED).
- Kein `CreatePopupButton` und kein Dropdown-Button, kein `RequestRaise`, kein `CreateQWidgetPluginGui`, keine
  `PluginGui.Input*`-, `MouseEnter/Leave`- oder `PointerAction`-Events, kein `OverrideStudioAction`, kein Veto in
  `BindToClose` (VERIFIED).
- Kein `UserInputService` in Widgets (VERIFIED). Kein Abfangen von Studio-Shortcuts (VERIFIED, Security).
- Keine Zwischenablage, kein Schreiben beliebiger Dateien, kein Lesen ohne Dialog (VERIFIED).
- Kein `Plugin.HostDataModelType`, kein `Selection.ActiveInstance`, keine Viewport-Drag-Events, kein
  `ViewportFrame:CaptureSnapshotAsync`, kein `CoreGui:TakeScreenshot`, kein `SetHttpEnabled`/`GetHttpEnabled`
  (VERIFIED).
- Keine zweite parallele Recording pro Plugin und keine Recording im Solo-Playtest (VERIFIED). Kein Undo von
  `Source`-Änderungen und kein Undo nach `Destroy()` (REPORTED).
- Plugin-Settings: keine Color3/Vector3/EnumItem-Werte, keine Keys mit `.`, `"`, Newline oder `\` (VERIFIED).
- Kein ViewportFrame-Rendering von Partikeln, Beams, Trails (REPORTED), Post-FX und Schatten (VERIFIED).
- Nicht mehr als 4 WebStreamClients. `Send` nur bei WebSocket (VERIFIED).

**Qualität / Netzwerk**
- Kein Lesen von `GraphicsQualityLevel`, `ReducedMotion` oder der effektiven Stufe bei Automatic. Kein
  `GetHarmonyQualityLevel`. Keine offizielle Zuordnung 1–10 ↔ 1–21 (VERIFIED).
- Keine Unreliable-Payload über 1000 B, keine Ordnung und kein Queueing bei Unreliable (VERIFIED). Keine Garantie,
  dass Instanzreferenzen unter Streaming ankommen (VERIFIED). Kein Setzen von `StreamingEnabled` aus Spielskripten
  (VERIFIED).
- Kein Debris über 1000 Objekte, keine StringValue über 199 999 Zeichen (VERIFIED/REPORTED).

**Toolchain**
- Kein verlustfreies JSON→ModuleScript in Rojo. Kein `rojo build --plugin` unter Linux. Kein Live-Rückweg über
  syncback (VERIFIED LOCAL).
- Lune: keine Events, kein `Emit`, kein `TweenInfo`/`Random`/`DateTime`, keine Texture↔TextureContent-Kopplung,
  keine `.config.luau`-Aliases (VERIFIED LOCAL).
- Kein Studio, kein MCP und kein Live-Sync unter Linux/CI (VERIFIED).

**Häufige Halluzinationen – explizit verboten:** `ParticleEmitter.Seed`, `ParticleEmitter:GetParticles()`,
`ParticleEmitter.OnParticleDied`, `ParticleEmitter:Prewarm()`, `Beam.WidthSequence`, `Beam.TimeScale`, `Trail.Width`,
`Trail.TextureSpeed`, `Trail.ZOffset`, `Tween.TimePosition`, `Tween:Seek()`, `TweenService:Create` auf
`NumberSequence`, `PluginAction.DefaultShortcut =` (existiert, ist aber gesperrt), `plugin:SetClipboard`,
`plugin:WriteFile`, `StudioService:CopyToClipboard` (gesperrt), `UserGameSettings.GraphicsQualityLevel` (gesperrt).

---

## 26. Ungeklärt – muss in Studio manuell geprüft werden

Status: UNVERIFIABLE = der Verifier fand weder Beleg noch Gegenbeleg. ASSUMPTION/REPORTED = Behauptung ohne
offizielle Bestätigung. Priorität: **P0** blockiert die Phase-2/3-Architektur, **P1** muss vor der betroffenen
Komponente geklärt sein, **P2/P3** sind Feinschliff. Ergebnisse kommen mit Datum, Studio-Version und OS in
`docs/PROGRESS.md` bzw. `docs/TESTING.md` und in diese Tabelle.

| ID | Frage | Stand | Testvorschlag | Blockiert | Prio |
|---|---|---|---|---|---|
| U1 | Feuern `Heartbeat`, `PreRender`, `RenderStepped`, `PreSimulation` und `Stepped` für **Plugin-Code im reinen Edit Mode**? Mit welcher Frequenz und welchem dt? Bei minimiertem Studio, offenem Script-Tab, Widget im Hintergrund? | UNVERIFIABLE (RN:glt C35, RN:sp R2, RN:apb N7) | Plugin zählt 10 s lang die Events pro Sekunde in allen Zuständen und loggt dt-Statistiken | Scheduler, Preview, Timeline-Uhr | **P0** |
| U2 | Wirkt `ParticleEmitter.TimeScale = 0` (und Zwischenwerte) im Edit Mode 0.745 sofort und ohne Verschwinden der Partikel? | REPORTED (Bugs 2023/24) | Emitter mit Rate 50, TimeScale 1 → 0 → 0.3 → 1 im laufenden Effekt; Sichtprüfung und Screenshots | Pause/Slow-Mo der Timeline | **P0** |
| U3 | Beam-Breitenachse bei `FaceCamera=false`: lokale Y- oder Z-Achse der Attachments? Wie wird zwischen A0 und A1 interpoliert? | UNVERIFIABLE (RN:apb C22) | Beam zwischen Default-Attachments; A0 nacheinander um X/Y/Z drehen, Drauf- und Seitenansicht | Beam-Builder, Slash-Presets | **P0** |
| U4 | Ignoriert CHS in 0.745 Änderungen an `Archivable=false`-Instanzen? Gilt das auch für Nachfahren mit eigenem `Archivable=true`? | REPORTED (DF:11953, 311724, 2179861) | In einer Recording Preview-Ordner anlegen und ändern, dann Undo/Redo. Prüfen, ob die Preview verschwindet oder doppelt entsteht | Preview-Konzept, HistoryAdapter | **P0** |
| U5 | Werden `SetAttribute`, `StringValue.Value` und Reparenting mit `Parent=nil` innerhalb einer Recording sauber rückgängig gemacht und wiederhergestellt? | REPORTED (ältere Bugs DF:473720, 1343162) | Recording → Änderungen → Commit → Undo/Redo je Typ, Werte vergleichen | Storage (ADR 6) | **P0** |
| U6 | Lösen Delete, Ctrl+Z, Ctrl+D und Ctrl+C/V die Studio-Aktion aus, während ein Input-Catcher-Frame bzw. eine TextBox im Widget fokussiert ist? Feuern gebundene PluginActions ohne Widget-Fokus? | UNVERIFIABLE (RN:sp I4) / REPORTED (DF:266552, DF:479597) | Part selektieren, Widget-Frame anklicken, Tasten drücken, Explorer und Undo-Liste beobachten | Timeline-/Graph-Shortcuts | **P0** |
| U7 | Sieht ein neu geladenes Plugin seine alte, offene Recording (`IsRecordingInProgress()`), und gelingt `FinishRecording("", Cancel)`? | offen (RN:sp C2) | Recording öffnen, Plugin neu laden, prüfen | HistoryAdapter-Startcheck | P1 |
| U8 | Was passiert mit Änderungen ohne Recording (Warntext, landen sie im nächsten Waypoint)? | ASSUMPTION / REPORTED (DF:2821409) | Änderung ohne Recording, dann eine Nutzeraktion, dann Undo | HistoryAdapter | P1 |
| U9 | Enthält `OnUndo(waypoint)` den `name` oder `displayName`? Wie verhält sich `Append` nach einem fremden Waypoint? | offen | Recording mit unterschiedlichem name/displayName, Undo, Payload loggen | History-Reload | P1 |
| U10 | Liefern `EditModeActive` und `IsEdit()` beim Plugin-Start im Run-Modus und im Playtest die erwarteten Werte? | REPORTED (DF:1627560) | Werte beim Start und per `GetPropertyChangedSignal` in allen Testmodi loggen | Editor-Gate (K37) | P1 |
| U11 | Flipbook-Texturen in 0.745: nur 1024²? Zweierpotenzen 8..1024? Rechteckig bzw. 4096 (ist die Custom-Beta allgemein freigegeben)? Grenzen von `FlipbookSizeX/Y`, Frame-Reihenfolge, ändert sich `FlipbookIncompatible` bei kompatibler Textur? Was rendert bei Speicher-Abschaltung? | VERIFIED-widersprüchlich / REPORTED | Atlanten 256², 512², 1024², 2048×512 und 4096² mit nummerierten Frames | Flipbook-Komponente, Presets | P1 |
| U12 | Engine-Clamps jenseits der UI-Bereiche: Rate > 400, maximale Partikelzahl pro `Emit()`-Aufruf, Lifetime > 20 (zurücklesen), TimeScale > 1, Size > 10, Squash ±3, `Beam.Segments`-Maximum, `Width0 < 0` per Skript, `FlipbookFramerate > 30`, Emitter-`LightInfluence` außerhalb 0..1 | offen (RN:apb C40) | Wert setzen, zurücklesen, sichtprüfen | Validator-Grenzen | P1 |
| U13 | Akzeptieren `NumberSequence.new`/`ColorSequence.new` doppelte Keypoint-Zeiten (Step-Kurven)? | UNVERIFIABLE (Doku widersprüchlich) | Konstruktor mit `{0,a},{0.5,a},{0.5,b},{1,b}` in Command Bar und Runtime | Curve-Baker | P1 |
| U14 | Braucht `Emit()` direkt nach Parent/Clone einen Frame? Wird off-screen-Emit verzögert? Wird `Emit` mit der Qualität skaliert? Greift die Rate-Skalierung (Bug Aug. 2026)? Wie hoch sind die globalen Partikel-Caps? | REPORTED | Studio + echtes Mobile Low vs. PC Max; Partikel zählen, Stats-Differenz | Player-Timing, Quality-Profile | P1 |
| U15 | `VelocityInheritance` mit verankertem Part plus explizit gesetzter `AssemblyLinearVelocity` bzw. bei CFrame-Animation; bei Attachment-Parent: wessen Velocity zählt? | UNVERIFIABLE (RN:apb C34) | Anker mit Velocity, VelocityInheritance = 1, Partikelbahn vergleichen | K19 | P2 |
| U16 | Shape-Geometrie: Werden Sphere/Cylinder/Disc als Ellipsoid in `Part.Size` eingepasst? Welche Achse? Was machen Box/Disc mit Attachment-Parent? Emittiert ein Emitter an einem Attachment unter `workspace.Terrain` bzw. an einem Bone? | ASSUMPTION | Nicht-uniforme Parts, Spawn-Visualisierung | Shape-Gizmos, Builder | P2 |
| U17 | Zeichnen Trails bei Attachment-CFrames, die **per Skript** im Edit Mode bewegt werden? Ist die Trail-Lifetime in 0.745 noch FPS-abhängig? Treffen Änderungen an Transparency/WidthScale bestehende Segmente? | ASSUMPTION / REPORTED (DF:821708) | Preview-Loop bewegt Attachments; FPS-Cap 30/60/144 | Trail-Komponente | P1 |
| U18 | Weichen weitere Studio-Insert-Defaults von `Instance.new` ab (Beam, Trail, Lichter)? | offen | Über Explorer einfügen und alle Properties gegen die Dump-Defaults diffen | Default-Tabelle | P2 |
| U19 | Was rendert ein ViewportFrame + WorldModel im DockWidget wirklich (ParticleEmitter, Beam, Trail, Fire, Smoke, Sparkles, Explosion, Lichter, Highlight, Decal, Texture, SurfaceAppearance)? | REPORTED / ASSUMPTION | Testszene je Klasse | Viewport-Preview | P2 |
| U20 | Werden `Archivable=false`-Preview-Objekte in Workspace bzw. unter `CurrentCamera` in **Team Create** zu Mitarbeitern repliziert? | offen (RN:sp A2) | Zwei Accounts im Team Create | Ort des Preview-Ordners (K35) | P1 |
| U21 | Spielt ein Sound-Klon unter dem ASTRA-DockWidget im Edit Mode 0.745? Spielt ein vorverdrahteter AudioPlayer? Funktioniert `PlayLocalSound` aus einem Plugin? | REPORTED | Drei Varianten mit demselben Asset | Sound-Preview (K33) | P2 |
| U22 | Rendern Neon und ForceField auf Part + SpecialMesh (Sphere, Cylinder, FileMesh) brauchbar? Tritt der „ForceField sieht wie Neon aus“-Bug auch bei Part-Zylindern auf? | VERIFIED (Doku: Material auf SpecialMesh nicht korrekt) / REPORTED | Vergleichsszene in Edit und Play | mesh/shockwave/sphere-Komponenten | P2 |
| U23 | Obergrenze von `SpecialMesh.Scale`, Verhalten bei Scale ≤ 0. Erzwingt `PartType.Ball` eine gleichförmige Größe? | offen | Werte setzen und zurücklesen | Compiler-Clamps | P3 |
| U24 | Funktioniert `rbxtemp://` als `ParticleEmitter/Beam/Trail.Texture`? Wirkt `EditableImage` als `TextureContent` im Edit Mode? | ASSUMPTION | Import-Dialog, temporäre ID zuweisen | Lokale Textur-Preview | P2 |
| U25 | Sind `rbxasset://textures/particles/*` auf Player-Clients (Mobile/Konsole) vorhanden, und wie sehen sie aus? | ASSUMPTION | Testplace auf Gerät | Preset-Bibliothek | P2 |
| U26 | HTTP-Berechtigungsdialog: lokales Plugin vs. Creator-Store-Plugin, erneut bei `ws://`? Gelten Port- und HTTPS-Regeln für localhost? Erscheint der „Script Injection“-Dialog beim Anlegen von ModuleScripts? | REPORTED (DF:493269, DF:877312) | Plugin lokal und als Store-Asset installieren | Bridge, Export generierter Module | P1 |
| U27 | Größenlimit von `SetSetting` und Ort der Settings-Datei | offen | Wachsende Payload schreiben und gegenlesen | SettingsStore | P3 |
| U28 | Doppelte `actionId`/Menü-ID nach einem Reload; werden PluginActions und Menus automatisch aufgeräumt? `CreateDockWidgetPluginGuiAsync` mit derselben ID im Play-DataModel? | ASSUMPTION | Reload-Zyklen und Playtest | WidgetHost, Menus | P2 |
| U29 | Erzeugt `UpdateSourceAsync` einen Undo-Schritt? Wie verhält es sich im Drafts-Modus? | offen | Generiertes Modul aktualisieren, Undo-Liste prüfen | Runtime-Export | P3 |
| U30 | Längenlimit und Performance beim Einfügen großer JSON-Blöcke (> 100 KB) in eine TextBox | offen | 50/100/190 KB einfügen | Paste-Import | P2 |
| U31 | Feuert `StringValue.Changed` zuverlässig bei Rojo-Live-Updates? Verliert das Plugin seine Referenz, wenn Rojo per Fallback die Instanz ersetzt? | offen (RN:tc) | `rojo serve` und Datei ändern | Rojo-Watcher | P1 |
| U32 | Wie kodiert `HttpService:JSONEncode` leere Tabellen, NaN/inf und große Zahlen? | offen | Command Bar | Encoder-Abgleich | P2 |
| U33 | Größenlimits für `RequestAsync`-Bodies bzw. Antworten und für `WebStreamClient`-Nachrichten aus Plugins | offen | wachsende Payloads | Bridge-Protokoll | P3 |
| U34 | Gilt die Glass-Distortion-Grenze (Grafik ≥ 8) noch? Wird `Transparency > 1` weiter akzeptiert? | REPORTED | Qualitätsstufen durchschalten | Distortion-Komponente | P3 |
| U35 | Funktioniert `SceneAnalysisService` außerhalb von Studio, und wie teuer ist ein Aufruf? | offen | Live-Testplace | Messmodus | P3 |
| U36 | Kosten von Highlight + ColorCorrection für 1–3-Frame-Impact-Frames auf Mobile; verschwinden Partikel unter ColorCorrection? | REPORTED | Gerätetest | impactFrame-Spur | P3 |
| U37 | Mehrfachbearbeitung von Sequenz-Properties im Studio-Properties-Fenster (Staff: „never supported“ vs. ein Post „enabled a change“) | PARTIAL (RN:ros C23) | Zwei Emitter selektieren, Size-Sequenz ändern | Inspector-UX (nur Vergleich) | P3 |
| U38 | Reale Unreliable-Payload-Grenzen mit `buffer` und typischen ASTRA-Net-Nachrichten | REPORTED | Studio-Output meldet Überschreitungen | Net-Encoder | P3 |
| U39 | Hat MCP-`execute_luau` Plugin-Security? Gibt es Größenlimits für Code und Rückgaben? | offen | MCP-Session | MCP-Anleitung | P3 |
| U40 | Zuordnung der Spieler-Stufen 1–10 zu `QualityLevel` 1–21; welche Stufe nutzt der Studio-Playtest? | REPORTED (inoffiziell) | `RenderSettings` lesen, Gerätetest | Quality-Mapping | P3 |
| U41 | Bleiben beim Emit gewürfelte Envelope-Werte nach einem Sequenzwechsel erhalten? | offen (RN:apb C3) | Size-Envelope groß, mitten im Leben neue Sequenz setzen | Live-Property-Spuren | P2 |
| U42 | Ist `UIDragDetector` in Plugin-Widgets für Keyframe- und Node-Drags nutzbar? | offen | Prototyp | Timeline/Graph-Input | P3 |
| U43 | Unterstützt die Engine Require-Aliases (`.config.luau`)? Welche Semantik hat `ScriptService:ResolveModulePath`? | offen (RN:tc) | Testmodul | nur relevant bei Abkehr von ADR 11 | P3 |
| U44 | Welche Edits unterstützt der Rojo-7.7-Two-Way-Sync? Ist er weiterhin experimentell? | offen | Rojo-Plugin-Option testen | Rückweg ohne Bridge | P3 |
| U45 | Wie teuer ist `MeshPart:ApplyMesh` auf gepoolten Parts (Kollisionsgeometrie)? | offen (RN:glt Neu 2) | MicroProfiler-Messung | Mesh-Vorlagen-Pool | P3 |
| U46 | Welche Berechtigungsregeln gelten genau für `AssetService:CreateMeshPartAsync` (eigene, Gruppen-, Store-Assets)? | REPORTED | Assets verschiedener Besitzer | Mesh-Prewarm | P3 |

---

## 27. Quellen

**Lokal (VERIFIED):** `/root/tools/ref/Full-API-Dump.json`, `/root/tools/ref/API-Dump.json`,
`/root/tools/ref/globalTypes.d.luau`, `/root/tools/ref/version.txt` (0.745.0.7451137). Lokale Tests mit Rojo 7.7.1 und
Lune 0.11.1 laut `docs/research/tooling-claude-integration.md` und dessen Verifikation.

**Roblox creator-docs** (Basis `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/`):
- Klassen (`reference/engine/classes/`): ParticleEmitter, Beam, Trail, Attachment, Bone, BasePart, Part, PVInstance,
  Model, WorldRoot, Workspace, MeshPart, TriangleMeshPart, AssetService, SpecialMesh, FileMesh, DataModelMesh, Decal,
  Texture, SurfaceAppearance, Light, PointLight, SpotLight, SurfaceLight, Lighting, BloomEffect,
  ColorCorrectionEffect, PostEffect, Highlight, Sound, SoundService, AudioPlayer, TweenService, TweenBase, Tween,
  RunService, Plugin, PluginGui, DockWidgetPluginGui, PluginToolbar, PluginToolbarButton, PluginAction, PluginMenu,
  PluginMouse, PluginManager, PluginDragEvent, StudioTestService, ChangeHistoryService, Selection, StudioService,
  File, SerializationService, ScriptEditorService, Script, ScriptService, Studio, StudioTheme, GuiObject, TextBox,
  InputObject, WireframeHandleAdornment, HttpService, WebStreamClient, ViewportFrame, WorldModel, Instance, CoreGui,
  StringValue, Debris, ContentProvider, EditableImage, UserGameSettings, DataModel, RenderSettings, Stats,
  SceneAnalysisService, RemoteEvent, UnreliableRemoteEvent, InstanceFileSyncService (jeweils `<Klasse>.yaml`)
- Enums (`reference/engine/enums/`): ParticleEmitterShape, ParticleEmitterShapeStyle, ParticleEmitterShapeInOut,
  ParticleOrientation, ParticleFlipbookLayout, ParticleFlipbookMode, ParticleFlipbookTextureCompatible, TextureMode,
  NormalId, PartType, Material, MeshType, RenderFidelity, EasingStyle, EasingDirection, BulkMoveMode, StepFrequency,
  InitialDockState, FinishRecordingOperation, StudioStyleGuideColor, StudioStyleGuideModifier, SavedQualitySetting,
  QualityLevel, GraphicsOptimizationMode, RollOffMode
- Datentypen (`reference/engine/datatypes/`): NumberSequence, NumberSequenceKeypoint, ColorSequence,
  ColorSequenceKeypoint, NumberRange, Content, TweenInfo, DockWidgetPluginGuiInfo
- Globals: `reference/engine/globals/LuaGlobals.yaml`
- Guides: `effects/particle-emitters.md`, `effects/beams.md`, `effects/trails.md`, `effects/highlighting.md`,
  `effects/light-sources.md`, `environment/post-processing-effects.md`, `environment/global-wind.md`,
  `parts/materials.md`, `projects/assets/index.md`, `projects/collaboration.md`, `production/creator-store.md`,
  `studio/plugins.md`, `studio/build-studio-widgets.md`, `studio/testing-modes.md`, `studio/mcp.md`,
  `studio/setup.md`, `scripting/sync.md`, `scripting/events/remote.md`, `cloud-services/http-service.md`,
  `ui/viewport-frames.md`, `workspace/streaming/index.md`, `workspace/streaming/techniques.md`,
  `performance-optimization/improve.md`, `performance-optimization/design.md`,
  `performance-optimization/scene-analysis.md`, `performance-optimization/test-on-hardware.md`,
  `performance-optimization/microprofiler/tag-table.md`, `cloud/guides/usage-place-publishing.md`,
  `reference/cloud/openapi.json`, `tutorials/use-case-tutorials/vfx/use-particles-for-explosions.md`,
  `tutorials/use-case-tutorials/vfx/custom-particle-effects.md`,
  `tutorials/curriculums/core/building/create-basic-visual-effects.md`

**Roblox-Dateien über Mirror (VERIFIED für Studio 0.745):**
`https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml`,
`…/rbxManifest.txt`, `…/version.txt`

**Produktquellen (VERIFIED, nur gelesen, kein Code übernommen):**
`https://raw.githubusercontent.com/rojo-rbx/rojo/master/CHANGELOG.md`, `…/README.md`,
`https://raw.githubusercontent.com/rojo-rbx/rojo/master/plugin/src/Config.lua`, `…/plugin/src/ApiContext.lua`,
`https://raw.githubusercontent.com/rojo-rbx/rojo.space/master/docs/sync-details.md`,
`https://raw.githubusercontent.com/lune-org/lune/main/CHANGELOG.md`,
`https://raw.githubusercontent.com/Roblox/studio-rust-mcp-server/main/README.md`,
Luau-RFCs `https://raw.githubusercontent.com/luau-lang/rfcs/master/docs/` (`new-require-by-string-semantics.md`,
`require-by-string-aliases.md`, `abstract-module-paths-and-init-dot-luau.md`, `config-luauconfig.md`)

**DevForum (REPORTED, nur über Such-Zusammenfassungen gelesen; `https://devforum.roblox.com/t/<id>`):**
Partikel/Flipbook: 34752, 2888715, 3325717, 188745, 1757317, 3550728, 1241979, 474762, 4834736, 2159584, 1585054,
2221218, 2720182, 2824385, 1506337, 2029388, 4005128, 3118761, 1679078, 95781, 2719243, 3181609, 3792199, 2718982 ·
Beam/Trail: 3076533, 3323908, 2939171, 1732819, 2426888, 2225384, 3145864, 3296080, 821708, 2613978, 1853349 ·
Geometrie/Material/Licht: 25580, 946141, 3771329, 294943, 278140, 3041374, 423438, 301951, 2392057, 2338789, 2319086,
3666977, 3306176, 140332, 2848207, 3798571, 3954367, 4061534, 3875739, 1439704, 2468478, 2963136 ·
Tween/Sound: 148063, 1240924, 1759898, 1214259, 2035448, 474500, 1927104, 2723419, 321507, 2706107, 3579146, 1598720,
4538689, 3959457 ·
Plugin/Studio: 219471, 2269097, 4257585, 1064071, 154621, 1627560, 1095186, 479597, 266552, 11953, 311724, 2179861,
4590702, 3479165, 549497, 473720, 1343162, 4108638, 2944637, 2821409, 3438378, 252266, 599553, 2133446, 3151410,
4706068, 227797, 23520, 877312, 493269, 4021932 ·
Qualität/Netzwerk: 2719633, 2947801, 792183, 2724155, 3038324, 3048788, 580567, 2873609 ·
Inoffiziell: `https://fastflagforge.github.io/Docs/fast-flags/graphical-settings`
