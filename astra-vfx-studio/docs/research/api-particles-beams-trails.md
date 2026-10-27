# Recherche: Roblox Engine API – ParticleEmitter, Beam, Trail, Attachment, Flipbooks

Stand: 2026-10-27 · Phase-1-Recherche für ASTRA VFX STUDIO · Engine-Stand der lokalen Daten: **0.745.0.7451137**

Label-Legende: **VERIFIED** (offizielle creator-docs, lokaler API-Dump 0.745, Roblox-eigene Dateien wie `ReflectionMetadata.xml`/`rbxManifest.txt` über den Roblox-Client-Tracker-Mirror) · **REPORTED** (DevForum-Posts, Such-Snippets, Drittseiten) · **ASSUMPTION** (eigene Schlussfolgerung) · **IDEA** (eigener Designvorschlag für ASTRA). Befunde mit **[kritisch]** bestimmen direkt, wie der ASTRA-Builder Instanzen aus Daten erzeugt oder pro Frame animiert.

Methodik / Zugriff:
- Lokal ausgewertet (VERIFIED): `/root/tools/ref/Full-API-Dump.json` (Defaults), `/root/tools/ref/API-Dump.json`, `/root/tools/ref/globalTypes.d.luau` (luau-lsp-Typen); Version 0.745.0.7451137.
- Per `raw.githubusercontent.com` gelesen (VERIFIED): creator-docs-Quellen (`effects/*.md`, `reference/engine/classes/*.yaml`, `enums/*.yaml`, `datatypes/*.yaml`, Tutorials). Aus dem Repo `MaximumADHD/Roblox-Client-Tracker` (Branch `roblox`, gleiche Version 0.745.0.7451137): `rbxManifest.txt` (Dateiliste der Studio-Installation), `ReflectionMetadata.xml` (Studio-UI-Metadaten: Slider-Bereiche, PreferredParent, FFlags). Der Tracker ist ein Drittanbieter-Mirror, die Dateien selbst stammen von Roblox; ich behandle sie als VERIFIED für Studio 0.745.
- DevForum-, YouTube- und Creator-Store-Seiten sind im Sandbox blockiert; alle Aussagen von dort stammen aus WebSearch-Zusammenfassungen und sind REPORTED.
- Code von Dritten wurde nicht kopiert. Die Lua-Beispiele in den Docs habe ich nur gelesen.

---

## 1. Zusammenfassung

Die drei nativen VFX-Primitive sind klar spezifiziert und gut aus Daten baubar. Für Timeline und Preview gibt es aber harte Grenzen, die die ASTRA-Architektur bestimmen:

1. **ParticleEmitter** (39 Properties, Methoden `Emit(count=16)` und `Clear()`): Er braucht als Parent einen `BasePart` (Emission im Bounding-Box-Volumen bzw. in der `Shape`) oder ein `Attachment` in einem solchen Part (Emission vom Punkt aus). Die Sequenzen `Color`, `Size`, `Transparency` und `Squash` wirken über die **Lebenszeit jedes Partikels**. Eine Änderung zur Laufzeit trifft **alle aktiven** Partikel. `Speed`, `Lifetime`, `Rotation`, `RotSpeed` und `Rate` gelten dagegen nur für **neue** Partikel. Es gibt **keinen Seed, keinen Zugriff auf einzelne Partikel, keine Death-/Collision-Events**. `FastForward` ist `RobloxScriptSecurity` und damit für Plugins und Spiele nicht nutzbar. `TimeScale` reicht nur von 0 bis 1. **Eine Partikelsimulation lässt sich also nicht deterministisch seeken oder vorspulen.** Das ist die wichtigste Konsequenz für die ASTRA-Timeline. **[kritisch]**
2. **Sequenzen**: Höchstens **20 Keypoints**, der erste bei Zeit 0 und der letzte bei 1, die Zeiten nicht absteigend. Interpoliert wird **linear**, bei Farben linear in RGB. Bezier- oder Easing-Kurven aus dem ASTRA-Kurveneditor müssen deshalb auf ≤ 20 lineare Keypoints gebacken werden. **[kritisch]**
3. **Flipbooks**: Die Layouts sind `None/Grid2x2/Grid4x4/Grid8x8/Custom` (Custom mit `FlipbookSizeX/Y`), die Modi `Loop/OneShot/PingPong/Random`. Die Framerate ist laut Docs auf **max. 30 fps** begrenzt. Bei OneShot ergibt sich die Framerate aus Lifetime ÷ Frames. Zur zulässigen Texturgröße widersprechen sich die Quellen: Docs, Enum-Doku und der Default-String im API-Dump nennen **1024×1024**. Der Release-Post von 2022 nennt quadratische Zweierpotenzen von 8 bis 1024. Die Client-Beta „Custom Layouts“ (~Okt. 2025) nennt rechteckige Grids und ein Beispiel mit 4096². Sicherer Standard: **1024×1024**. **[kritisch]**
4. **Beam**: Eine kubische Bezier-Kurve aus 4 Kontrollpunkten. P1 liegt `CurveSize0` Studs entlang **+X von Attachment0**, P2 liegt `CurveSize1` Studs entlang **−X von Attachment1**. Die Breite läuft **nur linear** von `Width0` nach `Width1`, eine Breitenkurve gibt es nicht. `Color`/`Transparency` laufen entlang der Länge und brauchen ≥ n−1 `Segments`. Welche Attachment-Achse bei `FaceCamera=false` die Breitenrichtung bestimmt, ist **nicht dokumentiert** (offene Frage, Test nötig). **[kritisch]**
5. **Trail**: Er zeichnet nur bei **Bewegung** (Abstand ≥ `MinLength`, Default 0.1). Die Breite ist der **Abstand der beiden Attachments × `WidthScale`** (NumberSequence über die Segment-Lebenszeit, 0–1, zentriert). `Lifetime` reicht von 0.01 bis 20. Ein Wechsel der Attachments löscht den Trail.
6. **Edit Mode**: Partikel emittieren laut Docs „sofort“ nach dem Einfügen im Explorer. Roblox' eigenes Tutorial testet Bursts in Studio mit einem `Emit()`-Plugin. Emit aus einem Plugin im Edit Mode funktioniert also. Trails zeichnen laut Guide, wenn man das Part bewegt. Studio rendert dabei mit der „Editor Quality Level“ und kann deshalb mehr Partikel zeigen als ein Spieler mit niedrigen Grafikeinstellungen (REPORTED).
7. **Default-Texturen**: Die Default-Texture des ParticleEmitter ist `rbxasset://textures/particles/sparkles_main.dds`. Beam und Trail haben `""` und werden dann einfarbig gerendert. Studio 0.745 liefert **28 Dateien** in `content/textures/particles/` aus (Liste in 2.13), dazu u. a. `textures/sparkle.png`, `glow.png`, `explosion.png`, `gradient.png` und `noise.dds`.
8. **Instance.new vs. Studio-Insert**: `ParticleEmitter.LightInfluence` ist 0 bei `Instance.new`, aber 1 beim Einfügen über Studio-Tools (VERIFIED). Ein Builder muss **alle** Properties explizit setzen und darf sich nicht auf Defaults verlassen. **[kritisch]**

---

## 2. Befunde

### 2.1 Datenbasis

| # | Befund | Label | Quelle |
|---|---|---|---|
| D1 | Lokale Dumps und luau-lsp-Typen entsprechen Engine **0.745.0.7451137**. Der Client-Tracker-Branch `roblox` hat dieselbe Version. | VERIFIED | `/root/tools/ref/version.txt`, https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/version.txt |
| D2 | Alle Properties von ParticleEmitter/Beam/Trail haben Security `None` (lesen/schreiben), sind `ReadSafe` und mit Ausnahme der unten markierten serialisierbar. | VERIFIED | Full-API-Dump.json |
| D3 | `ReflectionMetadata.xml` liefert Studio-**UI**-Bereiche (`UIMinimum`/`UIMaximum`, z. B. für Slider und Sequenz-Editor). Das sind **keine Engine-Clamps**: So ist `Rate` im UI auf 0..100 begrenzt, die Docs nennen aber bis zu 400/s. | VERIFIED (Werte) / ASSUMPTION (Interpretation „nur UI“) | https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml |

### 2.2 ParticleEmitter – vollständige Property-Liste

Defaults stammen aus dem Full-API-Dump (= `Instance.new`-Werte), UI-Bereiche aus ReflectionMetadata. Spalte „Wirkung“: **live** = eine Änderung trifft auch aktive Partikel, **neu** = gilt nur für neu emittierte Partikel (laut Docs). „?“ bedeutet: nicht dokumentiert.

| Property | ValueType | Default | Studio-UI-Bereich | Engine-Regel / Doku-Grenze | Wirkung | Label |
|---|---|---|---|---|---|---|
| `Acceleration` | Vector3 | 0,0,0 | – | Studs/s², **globale** Achsen | live | VERIFIED |
| `Brightness` | float | 1 | 0..10 | skaliert das Licht, wenn `LightInfluence` = 0 | ? | VERIFIED |
| `Color` | ColorSequence | weiß→weiß | – | linear über Alter/Lifetime | live | VERIFIED |
| `Drag` | float | 0 | 0..5 | Halbwertszeit der Geschwindigkeit in s (exponentiell); negativ → exponentielles Wachstum | ? | VERIFIED |
| `EmissionDirection` | Enum.NormalId | Top | – | Fläche des Parents; bei Attachment stattdessen das Attachment rotieren | neu (ASSUMPTION) | VERIFIED |
| `Enabled` | bool | true | – | false stoppt nur das Nachspawnen; vorhandene Partikel leben weiter | – | VERIFIED |
| `FlipbookBlendFrames` | bool | true | – | linearer Crossfade zwischen Frames statt hartem Wechsel | ? | VERIFIED |
| `FlipbookFramerate` | NumberRange | 1..1 | 0..30 | **max. 30 fps** laut Docs; Min/Max randomisiert pro Partikel | ? | VERIFIED |
| `FlipbookIncompatible` | string | "Particle texture must be 1024 by 1024 to use flipbooks." | – | Fehlermeldungstext; laut Doku muss die Texturgröße „ein exaktes Vielfaches der Layoutgröße“ sein | – | VERIFIED |
| `FlipbookLayout` | ParticleFlipbookLayout | None | – | None/Grid2x2/Grid4x4/Grid8x8/Custom | ? | VERIFIED |
| `FlipbookMode` | ParticleFlipbookMode | Loop | – | Loop/OneShot/PingPong/Random | ? | VERIFIED |
| `FlipbookSizeX` | int | 1 | – | Spalten, nur bei `Custom` | ? | VERIFIED |
| `FlipbookSizeY` | int | 1 | – | Zeilen, nur bei `Custom` | ? | VERIFIED |
| `FlipbookStartRandom` | bool | false | – | zufälliger Startframe pro Partikel; mit Framerate 0 → statischer Zufallsframe | neu (ASSUMPTION) | VERIFIED |
| `Lifetime` | NumberRange | 5..10 | 0..5 | **max. 20 s** (intern gekappt); 0 → keine Emission | neu | VERIFIED |
| `LightEmission` | float | 0 | 0..1 | 0 = normales Blending, 1 = additiv | live | VERIFIED |
| `LightInfluence` | float | **0** (Instance.new) / **1** (Studio-Insert) | 0..1 | muss 0..1 sein, sonst undefiniert | ? | VERIFIED |
| `LocalTransparencyModifier` | float | 0 | – | Hidden, NotReplicated, **CanSave=false**; Formel `1-((1-T)*(1-LTM))` | live (ASSUMPTION) | VERIFIED |
| `LockedToPart` | bool | false | – | aktive Partikel bewegen sich starr mit dem Parent (Part oder Attachment) | live | VERIFIED |
| `Orientation` | ParticleOrientation | FacingCamera | – | 4 Modi (2.11) | ? | VERIFIED |
| `Rate` | float | 20 | 0..100 | Docs: **max. 400/s pro Emitter (100/s auf Mobile)** | neu | VERIFIED |
| `RotSpeed` | NumberRange | 0..0 | -360..360 | °/s, beim Emit gewürfelt; sehr hohe Werte aliasieren mit der Framerate | neu | VERIFIED |
| `Rotation` | NumberRange | 0..0 | -180..180 | Grad, **positiv = im Uhrzeigersinn**, z. B. [0,360] für zufällig | neu | VERIFIED |
| `Shape` | ParticleEmitterShape | Box | – | Box/Sphere/Cylinder/Disc | neu (ASSUMPTION) | VERIFIED |
| `ShapeInOut` | ParticleEmitterShapeInOut | Outward | – | Outward/Inward/InAndOut | neu (ASSUMPTION) | VERIFIED |
| `ShapePartial` | float | 1 | 0..1 | Cylinder: Radiusanteil oben (0 = Kegel); Disc: Innenradius (1 = nur Rand); Sphere: Halbkugelwinkel (0.5 = Kuppel, 0 = Nordpol-Punkt) | neu (ASSUMPTION) | VERIFIED |
| `ShapeStyle` | ParticleEmitterShapeStyle | Volume | – | Volume/Surface | neu (ASSUMPTION) | VERIFIED |
| `Size` | NumberSequence | 1→1 | 0..10 | Weltgröße (Studs) der quadratischen Textur; Envelope pro Keypoint und Partikel beim Emit gewürfelt | live | VERIFIED |
| `Speed` | NumberRange | 5..5 | 0..100 | Studs/s in Emissionsrichtung; negativ = rückwärts | neu | VERIFIED |
| `SpreadAngle` | Vector2 | 0,0 | – | Grad auf den beiden Querachsen; 360 auf einer Achse = Kreis, auf beiden = Kugel | neu (ASSUMPTION) | VERIFIED |
| `Squash` | NumberSequence | 0→0 | -3..3 | >0: schmaler und höher; <0: breiter und flacher | live (ASSUMPTION) | VERIFIED |
| `Texture` | ContentId | `rbxasset://textures/particles/sparkles_main.dds` | – | Asset-URI-String | live (ASSUMPTION) | VERIFIED |
| `TextureContent` | Content | (none) | – | Content-Äquivalent; Setzen aktualisiert `Texture` | live (ASSUMPTION) | VERIFIED |
| `TimeScale` | float | 1 | 0..1 | „0 bis 1“: 1 = normal, 0.5 = halbe Geschwindigkeit, 0 = eingefroren | live (ASSUMPTION) | VERIFIED |
| `Transparency` | NumberSequence | 0→0 | 0..1 | 0 = opak, 1 = unsichtbar; Envelope wie bei Size | live (ASSUMPTION) | VERIFIED |
| `VelocityInheritance` | float | 0 | 0..1 | Anteil der Part-`Velocity` des Parents beim Emit | neu | VERIFIED |
| `VelocitySpread` | float | 0 | – | **Deprecated**, NotReplicated, CanSave=false → `SpreadAngle` verwenden | – | VERIFIED |
| `WindAffectsDrag` | bool | false | – | folgt `Workspace.GlobalWind` nur, wenn `Drag` > 0 | ? | VERIFIED |
| `ZOffset` | float | 0 | – | Studs zur Kamera (+) bzw. weg (−), ohne die Bildschirmgröße zu ändern; stark negativ → hinter dem Parent | live | VERIFIED |

Quellen: Full-API-Dump.json; https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/ParticleEmitter.yaml; https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/particle-emitters.md; ReflectionMetadata.xml (s. o.).

Ergänzungen:
- Die luau-lsp-Typen enthalten alle Members, auch `FastForward` und die versteckten Events. Für den ASTRA-Typecheck fehlt also nichts. (VERIFIED, `globalTypes.d.luau` ab Zeile ~15926)
- Ein Teil der Doku widerspricht sich: `ParticleEmitter.Brightness` wirkt „wenn LightInfluence 0 ist“, bei Beam und Trail dagegen „wenn LightInfluence < 1“. Beam/Trail-Brightness ist dokumentiert mit 0..10000. (VERIFIED, Doku-Texte)
- Laut einem DevForum-Thread von 2021 war die Size-NumberSequence zeitweise auf 1 gekappt (Bug). Das aktuelle Tutorial nutzt Size 3→10. (REPORTED, https://devforum.roblox.com/t/particleemitter-size-property-number-sequence-has-max-of-1/1506337; VERIFIED Tutorial https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/tutorials/use-case-tutorials/vfx/custom-particle-effects.md)

### 2.3 ParticleEmitter – Methoden und Events

| Member | Signatur | Security | Bedeutung | Label |
|---|---|---|---|---|
| `Emit` | `Emit(particleCount: int = 16): ()` | None | emittiert sofort `particleCount` Partikel | VERIFIED |
| `Clear` | `Clear(): ()` | None | entfernt sofort alle emittierten Partikel (aus Rate und Emit) | VERIFIED |
| `FastForward` | `FastForward(numFrames: int): ()` | **RobloxScriptSecurity** | nicht in den creator-docs; für Plugins und Spielskripte nicht aufrufbar **[kritisch]** | VERIFIED (Tag) / REPORTED (Bedeutung der Security-Stufen: https://devforum.roblox.com/t/a-current-explanation-of-normal-identities-and-security-tags/219471) |
| `OnEmitRequested(count)`, `OnClearRequested()` | Events | None, Hidden | intern (Replikation); keine dokumentierte Nutzung | VERIFIED (Dump) / ASSUMPTION (Zweck) |

- Es gibt **keine** Events für Spawn, Tod oder Kollision einzelner Partikel, keinen Zugriff auf Partikelpositionen und keinen Seed. (VERIFIED: fehlen im Dump) **[kritisch]**
- Mehrere DevForum-Threads berichten, dass `Emit()` direkt im selben Frame nach dem Parenten oder Klonen nichts emittiert. Ein Yield davor (`task.wait()`/`task.defer`) hilft. (REPORTED, https://devforum.roblox.com/t/particle-emitters-must-yield-after-being-parented-before-using-emit/34752) **[kritisch für die Runtime]**
- Ob `Emit()` von der Grafikqualität skaliert wird, ist widersprüchlich berichtet. (REPORTED, https://devforum.roblox.com/t/graphics-quality-lowering-particle-emission-rates/1241979)

### 2.4 ParticleEmitter – Verhalten

| # | Befund | Label | Quelle |
|---|---|---|---|
| P1 | Zum Emittieren und Rendern muss der Emitter Kind eines `BasePart` oder eines `Attachment` **in einem solchen Part** sein. Bei einem BasePart spawnen Partikel zufällig in dessen **Bounding Box** bzw. der `Shape`, bei einem Attachment an dessen Position. **[kritisch]** | VERIFIED | ParticleEmitter.yaml, particle-emitters.md |
| P2 | `Terrain` erbt von `BasePart` (Kette Terrain › BasePart › PVInstance). Attachments unter `workspace.Terrain` sind deshalb gültige Welt-Ankerpunkte ohne eigenes Part. | VERIFIED (Vererbung) / ASSUMPTION (Emitter funktioniert dort) | API-Dump.json |
| P3 | `Bone` erbt von `Attachment`. Ein Emitter an einem Bone ist damit typ-formal zulässig. | VERIFIED (Vererbung) / ASSUMPTION (Verhalten) | API-Dump.json, Bone.yaml |
| P4 | Mit Attachment als Parent werden die Shapes **Sphere und Cylinder nicht korrekt dargestellt** und sollen nur mit BasePart-Parent genutzt werden. **[kritisch]** | VERIFIED | particle-emitters.md (Warnhinweis) |
| P5 | `EmissionDirection` wählt die Parent-Fläche. Ein Rotieren des Parent-Parts ändert die Richtung mit. Beim Attachment rotiert man statt dessen das Attachment selbst. | VERIFIED | particle-emitters.md, ParticleEmitter.yaml |
| P6 | Die Shape-Größe ergibt sich aus der Part-Größe (`BasePart.Size`). Für MeshParts und Wedges wird die **Bounding Box** genutzt, nicht die echte Geometrie. Dass Sphere/Cylinder/Disc als Ellipsoid bzw. elliptische Form in die Part-Box eingepasst werden und die Zylinderachse entlang `EmissionDirection` läuft, ist eine Schlussfolgerung aus der ShapePartial-Doku („top radius“, „on the side of its EmissionDirection“). | VERIFIED (Bounding Box) / REPORTED (MeshPart/Wedge: https://devforum.roblox.com/t/particleswedges-being-weird/3792199) / ASSUMPTION (Ellipsoid, Achse) | ParticleEmitter.yaml |
| P7 | Studio fügt `ParticleEmitter` und `Beam` bevorzugt unter `BasePart` ein, `Trail` unter `Model` (Insert-Hinweis), `Attachment` unter `PVInstance`. | VERIFIED | ReflectionMetadata.xml (`PreferredParent`) |
| P8 | `LockedToPart=true` lässt aktive Partikel starr mit der Emissionsquelle mitlaufen. Als Alternative nennen die Docs `VelocityInheritance=1`. | VERIFIED | ParticleEmitter.yaml |
| P9 | `VelocityInheritance` übernimmt die `Velocity` des **Parent-Parts** beim Emit. Ob ein **anchored** Part, das per CFrame bewegt wird, dabei eine Geschwindigkeit liefert, ist nicht dokumentiert. Wahrscheinlich liefert es keine, weil eine CFrame-Zuweisung ein Teleport ist. **[kritisch für Runtime-Animation]** | VERIFIED (Definition) / ASSUMPTION (CFrame-Teleport ohne Wirkung) | ParticleEmitter.yaml; Kontext: https://devforum.roblox.com/t/velocityinheritance-overshoots/1023366 |
| P10 | `WindAffectsDrag` wirkt nur bei `Drag > 0` und nutzt `Workspace.GlobalWind` (Vector3). Fire und Smoke folgen dem Wind standardmäßig. | VERIFIED | environment/global-wind.md, Workspace.yaml |
| P11 | Docs: max. **400 Partikel/s pro Emitter (100/s auf Mobile)**; maximale Lebenszeit **20 s**. | VERIFIED | particle-emitters.md |
| P12 | Die Grafikqualität skaliert die effektive Rate (Community-Formel: `Rate × QualityLevel / 10`). Berichtet werden globale Partikel-Caps von ca. **16000 (PC) / 3600 (Mobile/Konsole)**. Beides ist inoffiziell. | REPORTED | https://devforum.roblox.com/t/graphics-quality-lowering-particle-emission-rates/1241979, https://devforum.roblox.com/t/particle-emitter-limit-on-low-graphics-is-impacting-my-game/2159584, https://devforum.roblox.com/t/a-way-to-make-particleemitter-rate-ignore-graphics-quality/474762 |
| P13 | Größe und Anzahl der Partikel kosten GPU-Fillrate bzw. Overdraw. Die Docs raten, Effekte bei niedrigster und höchster „Editor Quality Level“ zu prüfen. | VERIFIED | particle-emitters.md |
| P14 | `Color` multipliziert die Textur und nutzt deren Alpha zusammen mit `Transparency`. Bei `LightEmission > 0` wirken dunkle Farben transparenter. Bei Graustufen-Texturen ohne Alpha hilft `LightEmission = 1`. | VERIFIED | ParticleEmitter.yaml, particle-emitters.md |
| P15 | `LightEmission` beleuchtet die Umgebung **nicht**; dafür ist ein `PointLight` nötig. | VERIFIED | ParticleEmitter.yaml |

### 2.5 Flipbooks

| # | Befund | Label | Quelle |
|---|---|---|---|
| F1 | Die Layout-Enumwerte sind None(0), Grid2x2(1, 4 Frames), Grid4x4(2, 16), Grid8x8(3, 64) und Custom(4, `FlipbookSizeX`×`FlipbookSizeY`). | VERIFIED | ParticleFlipbookLayout.yaml, API-Dump |
| F2 | Die Modi sind Loop(0), OneShot(1), PingPong(2) und Random(3). Bei **OneShot gilt `FlipbookFramerate` nicht**: Die Frames werden gleichmäßig auf die Lifetime des Partikels verteilt. Random spielt zufällige Frames mit Crossfade. | VERIFIED | ParticleFlipbookMode.yaml, ParticleEmitter.yaml |
| F3 | `FlipbookFramerate` ist eine NumberRange in fps mit **max. 30** (Docs; UI 0..30). | VERIFIED | ParticleEmitter.yaml, ReflectionMetadata.xml |
| F4 | Mit `FlipbookStartRandom=true` und Framerate 0 bekommt jeder Partikel einen zufälligen statischen Frame („Textur-Varianten aus einem Atlas“). | VERIFIED | ParticleEmitter.yaml |
| F5 | **Texturgröße, Stand der Docs:** Das Enum `ParticleFlipbookTextureCompatible` sagt, Flipbook-Playback benötige eine **1024×1024**-Textur, sonst `NotCompatible` und Playback aus. Startzustand ist `Unknown`, der Wert wird von der Engine gesetzt und ist nicht skriptbar. Der Default-String von `FlipbookIncompatible` im Dump lautet ebenfalls „must be 1024 by 1024“. Die Property-Doku von `FlipbookIncompatible` sagt dagegen „exaktes Vielfaches der Layoutgröße“. **[kritisch]** | VERIFIED (widersprüchlich) | ParticleFlipbookTextureCompatible.yaml, ParticleEmitter.yaml, Full-API-Dump |
| F6 | Das Enum `ParticleFlipbookTextureCompatible` wird von **keinem** öffentlichen Member des Dumps als Typ verwendet. Ein Plugin kann die Kompatibilität also **nicht abfragen**. | VERIFIED (Dump-Suche) / ASSUMPTION (keine Abfrage möglich) | Full-API-Dump.json |
| F7 | Der Release-Post (Okt. 2022) erlaubt quadratische Zweierpotenzen von **8×8 bis 1024×1024**. Bei 1024² sind die Frames bei 2x2 512², bei 4x4 256² und bei 8x8 128² groß. | REPORTED | https://devforum.roblox.com/t/particles’-flipbook-release/2029388 |
| F8 | Die Client-Beta „custom flipbook layouts“ (~Okt. 2025) erlaubt **rechteckige** Grids (z. B. 16x4). `FlipbookSizeX/Y` werden bei Standard-Layouts ignoriert. Das Beispiel nennt **4096×4096 mit 32x8 Frames à 128×512**, mit dem Hinweis „as we move towards supporting larger texture sizes“. Ob die Beta inzwischen allgemein freigegeben ist, ist unklar. | REPORTED | https://devforum.roblox.com/t/client-beta-optimize-your-particle-animations-with-custom-flipbook-layouts/4005128 |
| F9 | Zwischen den Frames sollte Abstand (Padding) liegen, sonst gibt es Mip-Bleeding. | VERIFIED | particle-emitters.md |
| F10 | Flipbooks kosten Speicher. Clients mit wenig Speicher (ältere Handys) **deaktivieren Flipbooks automatisch**. Wiederverwendete Texturen sparen Speicher. **[kritisch für den Performance Analyzer]** | VERIFIED | particle-emitters.md |
| F11 | Bei einer inkompatiblen Textur ist `FlipbookLayout` in Studio ausgegraut und es erscheint die Warnung „Flipbook only supports particle Textures of sizes…“, u. a. bei Emittern in ReplicatedStorage. Die Engine prüft beim Setzen der Textur und nutzt dann intern kein Flipbook. | REPORTED | https://devforum.roblox.com/t/flipbook-only-supports-particle-textures-of-sizes-in-replicatedstorage/3118761 |
| F12 | Die Reihenfolge der Frames im Atlas (vermutlich zeilenweise von links oben) ist nicht dokumentiert. | ASSUMPTION | – |
| F13 | Hochgeladene Bilder werden nach Community-Berichten auf max. 1024×1024 herunterskaliert. Das ist der praktische Grund für die 1024-Grenze. | REPORTED | https://devforum.roblox.com/t/why-is-the-max-image-resolution-1024x1024/1679078 |
| F14 | `BuiltInStandalonePlugins/Flipbook.rbxm` in der Studio-Dateiliste ist sehr wahrscheinlich das UI-Storybook-Tool „flipbook“ und **kein** Partikel-Flipbook-Generator. Nicht verwechseln. | VERIFIED (Datei existiert) / ASSUMPTION (Zweck) | rbxManifest.txt |

### 2.6 Beam – vollständige Property-Liste

| Property | ValueType | Default | Studio-UI-Bereich | Regel | Label |
|---|---|---|---|---|---|
| `Attachment0` | Attachment (Ref) | nil | – | Start = P0; Orientierung + `CurveSize0` → P1 | VERIFIED |
| `Attachment1` | Attachment (Ref) | nil | – | Ende = P3; Orientierung + `CurveSize1` → P2 | VERIFIED |
| `Brightness` | float | 1 | 0..10 | Docs: 0..10000; wirkt bei `LightInfluence` < 1 | VERIFIED |
| `Color` | ColorSequence | weiß | – | entlang der **Länge**; braucht ≥ n−1 Segments | VERIFIED |
| `CurveSize0` | float | 0 | -10..10 | Studs entlang **+X** (`Axis`) von Attachment0 | VERIFIED |
| `CurveSize1` | float | 0 | -10..10 | Studs entlang **−X** von Attachment1 | VERIFIED |
| `Enabled` | bool | true | – | Sichtbarkeit | VERIFIED |
| `FaceCamera` | bool | false | – | true: Band dreht sich immer zur `CurrentCamera` | VERIFIED |
| `LightEmission` | float | 0 | 0..1 | 0 normal, 1 additiv | VERIFIED |
| `LightInfluence` | float | 0 | 0..1 | auf 0..1 geklemmt | VERIFIED |
| `LocalTransparencyModifier` | float | 0 | – | Hidden, NotReplicated, CanSave=false | VERIFIED |
| `Segments` | int | 10 | – | gerade Teilstücke; ≥ n−1 für n Keypoints; **Maximum nicht dokumentiert** | VERIFIED / offen |
| `Texture` | ContentId | "" | – | leer, ungültig oder noch nicht geladen → einfarbiger Strahl | VERIFIED |
| `TextureContent` | Content | none | – | Content-Äquivalent | VERIFIED |
| `TextureLength` | float | 1 | 0..5 | Wrap: Wiederholungen = Länge/TextureLength; Stretch: Textur wird TextureLength-mal wiederholt | VERIFIED |
| `TextureMode` | TextureMode | Stretch | – | Stretch/Wrap; **Static wird bei Beams wie Wrap behandelt** | VERIFIED |
| `TextureSpeed` | float | 1 | -1..1 | Texturzyklen pro Sekunde; + = A0→A1, − = umgekehrt, 0 = statisch | VERIFIED |
| `Transparency` | NumberSequence | **0.5** konstant | – | entlang der Länge; braucht ≥ n−1 Segments | VERIFIED |
| `Width0` | float | 1 | – | Studs am Start; Studio setzt Werte < 0 auf 0 | VERIFIED |
| `Width1` | float | 1 | – | Studs am Ende; **linearer** Verlauf von Width0 | VERIFIED |
| `ZOffset` | float | 0 | -1..1 | Studs Versatz relativ zur Kamera (gegen Z-Fighting) | VERIFIED |

Methode: `SetTextureOffset(offset: float = 0)` setzt die Phase des Texturzyklus (0 und 1 sind identisch). Ein positiver Offset bewegt die Textur entgegen der `TextureSpeed`-Richtung. Ohne Texture tut die Methode nichts. Beam hat **kein** `Clear`, **kein** `TimeScale` und keine Events. (VERIFIED, Beam.yaml, API-Dump)

### 2.7 Beam – Geometrie und Darstellung

| # | Befund | Label | Quelle |
|---|---|---|---|
| B1 | Ein Beam ist eine kubische Bezier-Kurve: P0 = `Attachment0.WorldPosition`, P1 = P0 + `CurveSize0` × (+X-Achse von A0), P2 = `Attachment1.WorldPosition` − `CurveSize1` × (X-Achse von A1), P3 = `Attachment1.WorldPosition`. Das Code-Beispiel der Docs nutzt dafür `CFrame.RightVector` (= X). **[kritisch]** | VERIFIED (Docs) / REPORTED (Code-Beispiel via Snippet) | Beam.yaml, beams.md |
| B2 | Der Beam ist nur sichtbar, wenn er selbst Nachfahre von `Workspace` ist und **beide** Attachments ebenfalls in Workspace liegen. Fehlt ein Attachment, wird nichts gerendert. Der Beam selbst darf z. B. in einem Model liegen. | VERIFIED | Beam.yaml, beams.md |
| B3 | Gerendert werden pro Segment zwei Dreiecke. Die Segmente werden „zwischen den Orientierungen der beiden Attachments“ ausgelegt; rotieren die Attachments unterschiedlich, verdrillen sich die Segmente. | VERIFIED | beams.md |
| B4 | **Breitenrichtung bei `FaceCamera=false`**: Dokumentiert ist nur, dass die Attachment-Orientierung das Band dreht. Welche lokale Achse (Y oder Z) die Breite aufspannt, steht **nirgends**. In der Community empfiehlt man, die Attachments um 90° zu rollen (z. B. per `CFrame.lookAt(...) * CFrame.Angles(0,0,±90°)`). **[kritisch – Studio-Test nötig]** | REPORTED / offen | https://devforum.roblox.com/t/how-to-make-a-beam-always-straight/3076533, https://devforum.roblox.com/t/how-would-i-stop-beam-orientation-with-parts/3323908 |
| B5 | Eine Breitenkurve entlang der Länge gibt es nicht, nur `Width0` → `Width1` linear. Taper- oder Bauch-Formen brauchen mehrere hintereinander verkettete Beams oder Mesh-Lösungen. | VERIFIED (Fehlen) / IDEA (Verkettung) | Beam.yaml |
| B6 | Bei niedriger Grafikqualität reduziert die Engine `Segments`, gemeldet wird ein Faktor bis ca. 1/10 (20 → 2). Es gibt Workarounds, die `Segments` pro Frame neu setzen. | REPORTED | https://devforum.roblox.com/t/bypassing-forced-beam-lod/2426888, https://devforum.roblox.com/t/beam-optimization-is-wronglypoorly-implemented/2939171 |
| B7 | Im September 2024 gab es einen Studio-Bug, bei dem Beams und Trails unsichtbar waren; laut Staff behoben. | REPORTED | https://devforum.roblox.com/t/beams-and-trails-dont-show-up/3145864 |

### 2.8 Trail – Properties und Verhalten

| Property | ValueType | Default | Studio-UI-Bereich | Regel | Label |
|---|---|---|---|---|---|
| `Attachment0`/`Attachment1` | Attachment (Ref) | nil | – | Positionen werden **jeden Frame** aufgezeichnet und mit dem Vorframe zu Polygonen verbunden; ein Wechsel löscht alle bisherigen Segmente | VERIFIED |
| `Brightness` | float | 1 | 0..10 | Docs 0..10000; wirkt bei LightInfluence < 1 | VERIFIED |
| `Color` | ColorSequence | weiß | – | über die **Segment-Lebenszeit**; eine Änderung aktualisiert auch alte Segmente | VERIFIED |
| `Enabled` | bool | true | – | false: keine neuen Segmente, alte laufen aus (sofort weg nur mit `Clear()`) | VERIFIED |
| `FaceCamera` | bool | false | – | wirkt sofort auf alle Segmente | VERIFIED |
| `Lifetime` | float | 2 | 0..20 | **0.01..20 s**; eine Änderung wirkt rückwirkend (zu alte Segmente verschwinden sofort) | VERIFIED |
| `LightEmission` | float | 0 | 0..1 | sofort für alle Segmente | VERIFIED |
| `LightInfluence` | float | 0 | 0..1 | auf 0..1 geklemmt; sofort | VERIFIED |
| `LocalTransparencyModifier` | float | 0 | – | Hidden, NotReplicated, CanSave=false | VERIFIED |
| `MaxLength` | float | 0 | – | Studs; 0 = unbegrenzt, sonst werden die ältesten Segmente entfernt | VERIFIED |
| `MinLength` | float | 0.1 | 0..1 | Studs; erst ab dieser Bewegung entsteht ein neues Segment, sonst werden nur die Endpunkte nachgezogen; gilt nur für neue Segmente | VERIFIED |
| `Texture` | ContentId | "" | – | leer → einfarbige Fläche; die Skalierung hängt vom Attachment-Abstand, TextureMode, TextureLength und WidthScale ab | VERIFIED |
| `TextureContent` | Content | none | – | Content-Äquivalent | VERIFIED |
| `TextureLength` | float | 1 | 0..5 | sofort für alle Segmente | VERIFIED |
| `TextureMode` | TextureMode | Stretch | – | Stretch: dehnt sich über die Lifetime und schrumpft im Stillstand; Wrap: kachelt, stationär relativ zu den Attachments; **Static**: „gestempelt“ (Fußspuren, Reifenspuren) | VERIFIED |
| `Transparency` | NumberSequence | **0.5** konstant | – | über die Segment-Lebenszeit | VERIFIED |
| `WidthScale` | NumberSequence | 1→1 | – | **0..1**, Multiplikator auf den Attachment-Abstand, zentriert (Abstand 2 Studs × 0.5 = 1 Stud Breite) | VERIFIED |

Methode `Clear()` löscht alle Segmente. Trail hat **kein** `TextureSpeed`, **kein** `TimeScale` und **keine** Width-Property: Die Breite kommt ausschließlich aus dem Attachment-Abstand. (VERIFIED, Trail.yaml, API-Dump) **[kritisch]**

Weitere Trail-Befunde:
- Laut Guide sieht man den Trail, wenn man das Part bewegt. Ein Trail braucht also Bewegung der Attachments. (VERIFIED, trails.md)
- Ein Trail mit LightInfluence = 0 und Textur mit transparentem Hintergrund war in einem Fall unsichtbar. Das ist eine Einzelmeldung. (REPORTED, https://devforum.roblox.com/t/trails-not-visible-not-working-when-in-roblox-studio/3146228)
- Trails bei sehr schnellen Bewegungen und Rotationen per CFrame um einen Ursprung rendern laut Berichten fehlerhaft. (REPORTED, https://devforum.roblox.com/t/trails-do-not-render-properly-if-rotated-about-an-origin/2613978, https://devforum.roblox.com/t/fast-moving-trails-do-not-render/1853349)

### 2.9 Attachment (und Bone)

| # | Befund | Label | Quelle |
|---|---|---|---|
| A1 | Ein Attachment definiert Punkt und Orientierung relativ zu einem Vorfahren `PVInstance`, `Bone` **oder einem anderen Attachment** (verschachtelbar). Ohne solchen Vorfahren sind `CFrame` und `WorldCFrame` gleich. | VERIFIED | Attachment.yaml |
| A2 | **Serialisiert wird nur `CFrame`** (und `Visible`). `Position`, `Orientation`, `WorldPosition`, `WorldOrientation`, `Axis`, `SecondaryAxis`, `WorldAxis`, `WorldSecondaryAxis` und `WorldCFrame` sind abgeleitet (CanSave=false bzw. Hidden). `Rotation`/`WorldRotation` sind deprecated. **[kritisch für das Datenformat]** | VERIFIED | Full-API-Dump.json |
| A3 | `Axis` ist die lokale **X**-Achse (Default 1,0,0), `SecondaryAxis` die lokale **Y**-Achse (Default 0,1,0). Beim Setzen werden sie orthogonalisiert. `Orientation` nutzt die Reihenfolge Z, X, Y. | VERIFIED | Attachment.yaml |
| A4 | `Visible=true` rendert im Spiel eine grüne Kugel (Debug). | VERIFIED | Attachment.yaml |
| A5 | Alle Transform-Properties haben `simulationAccess`. Das Schreiben von `CFrame` pro Frame ist der normale Weg, Beam- und Trail-Geometrie zu animieren. | VERIFIED (Tag) / ASSUMPTION (Empfehlung) | Attachment.yaml |
| A6 | Ein Bone ist ein Attachment-Subtyp und wird weder repliziert noch serialisiert (der Pose-Offset wird nicht repliziert). | VERIFIED | Bone.yaml |

### 2.10 Datentypen

| # | Befund | Label | Quelle |
|---|---|---|---|
| S1 | `NumberSequence.new({...})`: Keypoints nicht absteigend sortiert, **mindestens 2, höchstens 20**, erster bei Time 0, letzter bei Time 1. Kurzformen sind `new(n)` und `new(n0, n1)`. **[kritisch]** | VERIFIED | NumberSequence.yaml, NumberSequenceKeypoint.yaml |
| S2 | `ColorSequence.new({...})`: gleiche Regeln (2..20 Keypoints, Time 0 und 1). Die Color3-Komponenten müssen in 0..1 liegen; interpoliert wird linear in **RGB**. **[kritisch]** | VERIFIED | ColorSequence.yaml, ColorSequenceKeypoint.yaml |
| S3 | `NumberSequenceKeypoint.Envelope` ≥ 0. Der Wert streut zufällig in [Value−Envelope, Value+Envelope]; Werte **und** Envelopes werden zwischen Keypoints linear interpoliert. Bei Partikeln wird pro Keypoint und Partikel beim Emit gewürfelt. | VERIFIED | NumberSequenceKeypoint.yaml, ParticleEmitter.yaml |
| S4 | „Nicht absteigend“ erlaubt **gleiche Zeiten** zweier Keypoints, also harte Sprünge (Step-Kurven). | VERIFIED (Wortlaut) / ASSUMPTION (Engine akzeptiert Duplikate) | NumberSequence.yaml |
| S5 | `NumberRange.new(min[, max])`, wobei min ≤ max sein muss; gespeichert als **float32**. | VERIFIED | NumberRange.yaml |
| S6 | Es gibt keine eingebaute Auswertungsmethode für Sequenzen; die Docs zeigen eigene Lineare-Interpolation-Funktionen. ASTRA braucht einen eigenen Evaluator (identisch für Preview, Analyzer und Runtime). | VERIFIED | NumberSequence.yaml, ColorSequence.yaml |
| S7 | `Content`: `Content.fromUri(uri)`, `Content.fromAssetId(id)` (≙ `rbxassetid://id`, 0 → none), `Content.fromObject(obj)` und `Content.none`. **Object-Contents (EditableImage/EditableMesh) replizieren nicht**: Clients sehen ein Schachbrett-Placeholder-Objekt. | VERIFIED | Content.yaml, globalTypes.d.luau |
| S8 | `EditableImage` funktioniert in jeder Content-Property, die ein Bild nimmt, und damit vermutlich auch in `ParticleEmitter/Beam/Trail.TextureContent`. In veröffentlichten Spielen ist es standardmäßig gesperrt („Allow Mesh / Image APIs“), hat Memory-Budgets und aktualisiert nur ein angezeigtes EditableImage pro Frame. | VERIFIED (allgemein) / ASSUMPTION (konkrete Klassen) | EditableImage.yaml |
| S9 | Asset-URIs: `rbxassetid://` (hochgeladenes Asset), `rbxasset://` (lokaler Content-Ordner des Clients), `rbxthumb://`, `rbxgameasset://` (nur im aktuellen Spiel). | VERIFIED | projects/assets/index.md |

### 2.11 Enums (Name = Wert)

| Enum | Items | Label |
|---|---|---|
| `ParticleEmitterShape` | Box=0, Sphere=1, Cylinder=2, Disc=3 | VERIFIED |
| `ParticleEmitterShapeStyle` | Volume=0, Surface=1 | VERIFIED |
| `ParticleEmitterShapeInOut` | Outward=0, Inward=1, InAndOut=2 (zufällig pro Partikel) | VERIFIED |
| `ParticleOrientation` | FacingCamera=0 (Billboard), FacingCameraWorldUp=1 (nur um Welt-Y), VelocityParallel=2, VelocityPerpendicular=3 | VERIFIED |
| `ParticleFlipbookLayout` | None=0, Grid2x2=1, Grid4x4=2, Grid8x8=3, Custom=4 | VERIFIED |
| `ParticleFlipbookMode` | Loop=0, OneShot=1, PingPong=2, Random=3 | VERIFIED |
| `ParticleFlipbookTextureCompatible` | NotCompatible=0, Compatible=1, Unknown=2 (nur engine-intern) | VERIFIED |
| `TextureMode` | Stretch=0, Wrap=1, Static=2 (Beam: Static = Wrap) | VERIFIED |
| `NormalId` | Right=0, Top=1, Back=2, Left=3, Bottom=4, Front=5 | VERIFIED |
| `ParticleEmitter2DEmissionMode` | Point=0, BoundingBox=1 (nur für unveröffentlichtes `ParticleEmitter2D`) | VERIFIED |

Quellen: `reference/engine/enums/*.yaml` unter https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/ ; API-Dump.

Hinweis zum Rain-Tipp der Docs: Bei `VelocityParallel` soll `Squash` **negativ** sein, damit die Streifen in Flugrichtung zeigen. (VERIFIED, particle-emitters.md)

### 2.12 Verhalten in Studio im Edit Mode (nicht laufend)

| # | Befund | Label | Quelle |
|---|---|---|---|
| E1 | Laut Guide „emittiert der ParticleEmitter sofort Partikel“, sobald er über den Explorer eingefügt wird. Das ist ein Edit-Mode-Arbeitsschritt, die Simulation läuft also auch ohne Playtest. **[kritisch]** | VERIFIED (Aussage) / ASSUMPTION (Kontext Edit Mode) | particle-emitters.md |
| E2 | Roblox' eigenes Tutorial lässt einen Burst in Studio vor dem Scripting mit dem Plugin „ParticleEmitter:Emit(n)“ (Marketplace-ID 303835976) testen. **`Emit()` aus einem Plugin funktioniert im Edit Mode.** **[kritisch]** | VERIFIED | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/tutorials/use-case-tutorials/vfx/use-particles-for-explosions.md |
| E3 | Trail-Guide: „To see the trail, move the part in any direction“. Mit dem Move-Tool in Studio zeichnet der Trail also auch im Edit Mode. | VERIFIED (Aussage) / ASSUMPTION (Edit Mode) | trails.md |
| E4 | Beams rendern im Edit Mode, sobald beide Attachments gesetzt sind (Guide-Workflow). | VERIFIED (Workflow) / ASSUMPTION | beams.md |
| E5 | Im Edit Mode ist die Darstellung von der Studio-Einstellung „Editor Quality Level“ abhängig und zeigt oft mehr Partikel als ein Spieler bei niedriger Qualität. Gemeldet werden auch FPS-Abhängigkeit und verzögerter Start. | REPORTED | https://devforum.roblox.com/t/why-do-particle-emitters-appear-differently-in-studio-than-when-testing/95781, https://devforum.roblox.com/t/particles-in-studio-rely-on-fps/2719243, https://devforum.roblox.com/t/particles-have-a-delay-when-enabling/3181609 |
| E6 | `RunService:IsEdit()` ist im Edit Mode true und `IsRunning()` false. Bei pausierter Simulation sind beide false. Ob `Heartbeat`/`PreRender` im Edit Mode feuern, sagt die Doku nicht explizit. Erwartet wird ja, weil Plugins das üblicherweise nutzen. | VERIFIED (Tabelle) / ASSUMPTION (Frame-Events im Edit Mode) | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/RunService.yaml |

### 2.13 Mitgelieferte `rbxasset://`-Texturen (Studio 0.745, Windows-Manifest)

Inhalt von `content\textures\particles\` laut `rbxManifest.txt`, 28 Dateien (VERIFIED, https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/rbxManifest.txt):

`common_alpha.dds`, `explosion_alpha.dds`, `explosion_color.dds`, `explosion01_core_alpha.png`, `explosion01_core_main.dds`, `explosion01_implosion_color.png`, `explosion01_implosion_main.dds`, `explosion01_shockwave_main.dds`, `explosion01_smoke_alpha.dds`, `explosion01_smoke_color_new.dds`, `explosion01_smoke_main.dds`, `fire_alpha.dds`, `fire_color.dds`, `fire_main.dds`, `fire_sparks_color.dds`, `fire_sparks_main.dds`, `forcefield_alpha.dds`, `forcefield_glow_alpha.dds`, `forcefield_glow_color.dds`, `forcefield_glow_main.dds`, `forcefield_vortex_color.dds`, `forcefield_vortex_main.dds`, `legacy_fire_alpha_color.dds`, `smoke_color.dds`, `smoke_main.dds`, `sparkles_color.dds`, `sparkles_main.dds`, `SquareParticle.png`.

Weitere einzelne Texturen direkt in `content\textures\`, die sich als Partikel- oder Beam-Texturen eignen könnten: `sparkle.png`, `glow.png`, `explosion.png`, `gradient.png`, `noise.dds`, `whiteCircle.png`, `smallWhiteCircle.png`, `ui\traildot.png`. (VERIFIED: Existenz)

Einschränkungen:
- Der Pfad wird als `rbxasset://textures/particles/<datei>` angesprochen; das Default-Beispiel ist `sparkles_main.dds`. (VERIFIED)
- Das Manifest beschreibt die **Studio**-Installation unter Windows. Dass die gleichen Dateien auf Player-Clients (Windows/Mac/Mobile/Konsole) vorhanden sind, ist eine ASSUMPTION; die Docs sagen nur, dass `rbxasset` auf den lokalen Content-Ordner zeigt.
- Die `*_alpha`/`*_color`/`*_main`-Dateien gehören wahrscheinlich zu den Legacy-Effekten Fire/Smoke/Sparkles/ForceField/Explosion und können ungewöhnliche Kanal-Packings haben. Aussehen und Auflösung konnte ich nicht prüfen, weil die Binärdateien nicht im Tracker liegen. (ASSUMPTION)
- Rechtlich sind `rbxasset://`-Referenzen Verweise auf Client-Dateien. ASTRA sollte diese Dateien **nicht** kopieren oder neu hochladen. (ASSUMPTION/IDEA)

### 2.14 Verwandte bzw. unveröffentlichte Klassen

| # | Befund | Label | Quelle |
|---|---|---|---|
| R1 | `ParticleEmitter2D` (UI-Partikel) existiert im Dump mit Tag `NotBrowsable`. ReflectionMetadata nennt `PreferredParent=GuiObject` und **`FFlag=UIParticles`**. Eine creator-docs-Seite gibt es nicht (404). Die Members ähneln dem 3D-Emitter: Vector2-Acceleration, `EmissionAngle/Offset/Spread`, `EmissionMode` (Point/BoundingBox), `ZIndex`, `Blend`, `LockedToParent`, Size-Default 32 (Pixel?) und dieselben Flipbook-Properties. **Noch nicht verwenden.** | VERIFIED (Existenz/Flag) / ASSUMPTION (unveröffentlicht) | API-Dump, ReflectionMetadata.xml |
| R2 | Die Legacy-Klassen `Fire`, `Smoke` und `Sparkles` haben `TimeScale` und ebenfalls `FastForward` (RobloxScriptSecurity). Mehrere Properties sind NotReplicated mit `*_xml`-Serialisierungs-Duplikaten. | VERIFIED | API-Dump |

---

## 3. Einschränkungen und Kritik

1. **Kein Seeking und kein Determinismus**: Es gibt keinen Seed, keinen Zugriff auf Partikelzustände, `FastForward` ist gesperrt und `TimeScale` reicht nur bis 1. Eine Timeline kann native Partikel weder exakt zu einem Zeitpunkt springen lassen noch rückwärts scrubben. Möglich sind nur „von vorn neu abspielen“ oder `TimeScale=0` (einfrieren). (ASSUMPTION auf Basis von VERIFIED-Fakten)
2. **Sequenz-Modulation ist global**: Wer `Size`/`Color`/`Transparency` pro Frame überschreibt, verändert **alle** lebenden Partikel gleichzeitig. Animierte Werte pro Partikel über die Effektzeit sind nicht möglich, nur über die Lebenszeit. (VERIFIED + ASSUMPTION)
3. **Nur lineare Kurven mit ≤ 20 Keypoints**: Weiche Kurven müssen approximiert werden. Envelopes sind symmetrisch (±), asymmetrische Zufallsbereiche gibt es nicht. (VERIFIED)
4. **Kein Zeitfaktor für Beam und Trail**: Für globale Slow-Motion muss ASTRA `TextureSpeed` und `Lifetime` selbst skalieren. Echte Trail-Zeitlupe ist unmöglich, weil Trails in Echtzeit altern. (VERIFIED Fehlen + ASSUMPTION)
5. **Beam-Breite nur linear**, **Breitenrichtung undokumentiert** (B4/B5).
6. **Trail-Breite ist an den Attachment-Abstand gekoppelt**: Ein „Width“-Parameter im ASTRA-Format muss in Attachment-Positionen übersetzt werden. `WidthScale` kann nur verkleinern (0..1). (VERIFIED)
7. **Flipbook-Regeln uneinheitlich** (F5–F8). Die Kompatibilität ist nicht abfragbar, und auf schwachen Geräten werden Flipbooks ohne Rückmeldung deaktiviert. (VERIFIED/REPORTED)
8. **Qualitätsabhängigkeit**: Die Rate wird auf Clients per Grafiklevel skaliert, Beam-Segmente reduziert, und es gibt globale Caps. Was Studio zeigt, ist nicht das, was ein Mobile-Spieler sieht. (REPORTED)
9. **Studio- vs. Script-Defaults** unterscheiden sich mindestens bei `LightInfluence`. Weitere Abweichungen sind nicht dokumentiert. (VERIFIED/offen)
10. **Doku-Widersprüche**: Brightness-Bedingung (LightInfluence = 0 vs. < 1), Flipbook-Texturgröße (1024 fix vs. Vielfaches vs. 8..1024 vs. 4096 Beta). (VERIFIED)
11. **Emit-Timing**: Ein `Emit()` direkt nach dem Parenten kann verloren gehen (REPORTED). Das Runtime-Modul muss das abfangen.

---

## 4. Konsequenzen für ASTRA

### 4.1 Builder (Daten → Instanzen) **[kritisch]**
- **IDEA**: Der Builder setzt **jede** Property explizit aus dem Schema-Default von ASTRA und verlässt sich nie auf `Instance.new`- oder Studio-Defaults (Beispiel `LightInfluence`). Die ASTRA-Defaults werden einmal aus dem Full-API-Dump generiert und versioniert (`engineVersion: 0.745`).
- **IDEA**: Reihenfolge beim Bau: 1) Ankerpart bzw. Attachments mit `CFrame` erzeugen, 2) Emitter/Beam/Trail mit allen Properties bauen, **`Texture` vor `FlipbookLayout`** setzen und `Attachment0/1` zuletzt, 3) erst dann parenten, 4) in der Runtime vor dem ersten `Emit()` einen Frame yielden.
- **IDEA**: Nicht serialisieren: `LocalTransparencyModifier`, `VelocitySpread`, `FlipbookIncompatible`, alle abgeleiteten Attachment-Properties. Attachments nur über `CFrame` speichern, im JSON als Position + Rotation (z. B. Quaternion oder Euler mit festgelegter Reihenfolge) und beim Bau in `CFrame` umrechnen.
- **IDEA**: Texturen im Format als String-URI (`rbxassetid://…` oder `rbxasset://…`) speichern; der Builder setzt `Texture` bzw. `TextureContent = Content.fromUri(...)`. `Content.fromObject(EditableImage)` nur für lokale Editor-Previews verwenden, nie in replizierten Instanzen.
- **IDEA**: Validator-Regeln im JSON-Schema und in `astra-analyze`:
  - Sequenzen: 2..20 Keypoints, t[0]=0, t[last]=1, monoton nicht fallend, Envelope ≥ 0, Farbkomponenten in 0..1.
  - NumberRange: min ≤ max.
  - `Lifetime.max` ≤ 20 (Warnung), `Lifetime` > 0.
  - `FlipbookFramerate.max` ≤ 30.
  - `LightInfluence`/`LightEmission` in 0..1, `TimeScale` in 0..1, `Trail.Lifetime` in 0.01..20, `WidthScale` in 0..1, `Width0/1` ≥ 0.
  - `Beam.Segments` ≥ max(nColorKP, nTransparencyKP) − 1.
  - Sphere/Cylinder-Shape mit Attachment-Parent → Warnung.
  - `WindAffectsDrag` ohne `Drag > 0` → Hinweis.
  - Flipbook-Layout ≠ None ohne bekannte 1024²-Textur → Warnung.
- **IDEA**: Enums im Format als **Namen** (`"Grid8x8"`) speichern, nicht als Zahlen. Das ist robust gegen spätere Enum-Erweiterungen und für Claude besser lesbar.

### 4.2 Kurveneditor und Datenformat
- **IDEA**: Kurven im ASTRA-Format reich halten (Bezier, Easing) und **für die Engine backen**: adaptives Sampling plus Ramer-Douglas-Peucker bzw. Fehler-minimierende Vereinfachung auf ≤ 20 Keypoints, mit sichtbarer Fehlermarke im Editor. Für Partikel ein „Envelope“-Band pro Keypoint unterstützen (symmetrisch, wie die Engine).
- **IDEA**: Step-Kurven über doppelte Zeitstempel abbilden (S4, vorher im Studio-Test bestätigen).
- **IDEA**: Einen eigenen Luau-Evaluator für Sequenzen in einem gemeinsamen Modul pflegen, das Runtime, Preview und Performance-Analyzer nutzen.

### 4.3 Timeline und Preview **[kritisch]**
- **IDEA**: Zwei Arten von Tracks unterscheiden:
  - **Emission-Events** (Burst `Emit(n)` zur Zeit t, Enable-Fenster [t0, t1], Rate-Kurve über die Effektzeit). Sie wirken nur auf neue Partikel.
  - **Live-Property-Tracks** (Emitter-weite Modulation von Color/Size/Transparency/LightEmission/Acceleration/ZOffset/TimeScale, Beam-Width/Curve/TextureSpeed, Attachment-CFrames). Sie treffen alle lebenden Partikel.
  Im UI sollte erklärt werden, warum „Size über die Effektzeit“ etwas anderes ist als „Size über die Partikel-Lebenszeit“.
- **IDEA**: Scrubbing: Bei jedem Rückwärts-Scrub `Clear()` aufrufen, Beams und Trails zurücksetzen und den Effekt ab t=0 **in Echtzeit** bis zum Zielzeitpunkt abspielen, dann mit `TimeScale=0` einfrieren. Für Vorwärts-Scrub inkrementell weiterlaufen lassen. Der Hinweis „native Partikel sind nicht exakt seekbar“ gehört ins UI. Optional gibt es einen „Ghost“-Modus mit eigener CPU-Partikelsimulation (Proxy-Billboards) für deterministisches Scrubbing; der Look ist dann nur näherungsweise gleich.
- **IDEA**: Der Preview läuft im Edit Mode direkt mit nativen Instanzen in einem Preview-Folder in Workspace (E1–E4). Trails brauchen animierte Attachment-CFrames im Preview-Loop. Für Beams pro Frame `SetTextureOffset` setzen, wenn TextureSpeed timeline-synchron sein soll. Alle Preview-Instanzen müssen aus ChangeHistory und Speichern herausgehalten werden; das gehört in eine separate Plugin-Recherche.
- **IDEA**: „Quality-Preview“: einen Schalter, der die Rate (und Beam-Segments) gemäß der berichteten Formel `Rate × Q/10` simuliert, damit Autoren Mobile-Low-Settings abschätzen können. Als Schätzung kennzeichnen.

### 4.4 Runtime-Modul
- **IDEA**: Welt-Anker als Attachments unter `workspace.Terrain` (P2), Effekte an Charakteren an vorhandenen Attachments oder Bones. Bewegte Effekte über `LockedToPart` oder animierte Attachment-CFrames umsetzen; `VelocityInheritance` nur mit physikalisch bewegten Parts (P9).
- **IDEA**: Eine globale „Master-Opacity“ pro Effekt über `LocalTransparencyModifier` auf allen Emittern, Beams und Trails (Formel dokumentiert). So muss man keine Sequenzen neu bauen. Nur clientseitig sinnvoll.
- **IDEA**: Einen globalen Zeitfaktor anbieten: `ParticleEmitter.TimeScale` (≤ 1), `Beam.TextureSpeed × f`, Trail-Lifetime anpassen und Timeline-Clock skalieren. Begrenzungen dokumentieren.
- **IDEA**: Sub-Emitter, On-Death- und Kollisions-Logik des Node-Graphs nur als **zeitbasierte Approximation** (z. B. Burst nach Lifetime-Mittelwert) oder mit Custom-Partikeln umsetzen, weil die Engine keine Partikel-Events liefert.
- **IDEA**: Vor `Emit()` nach dem Parenten immer einen Frame yielden (REPORTED-Bug).

### 4.5 Performance Analyzer
- **IDEA**: Kennzahlen pro Effekt berechnen und mit Grenzwerten vergleichen:
  - erwartete gleichzeitige Partikel ≈ Σ(Rate × mittlere Lifetime + Burst-Summen im Lifetime-Fenster), verglichen mit Rate ≤ 400 (Mobile 100) und mit den berichteten Caps 16000/3600;
  - Overdraw-Score ≈ Partikel × (mittlere Size)² × (1 − mittlere Transparency) × Faktor bei `LightEmission`;
  - Anzahl eindeutiger Texturen und Flipbooks (Speicher, Deaktivierung auf Mobile);
  - Beam-Segments und Trail-Lifetime × Framerate (Segmentanzahl).

### 4.6 Presets und Texturen
- **IDEA**: Die Preset-Bibliothek darf auf die 28 mitgelieferten `rbxasset://textures/particles/*`-Pfade und die Einzeltexturen verweisen, als „engine-built-in, nicht garantiert auf allen Plattformen“ markiert, bis die Player-Verfügbarkeit geprüft ist. Eigene ASTRA-Texturen werden selbst erstellt und vom Nutzer hochgeladen (`rbxassetid`).

---

## 5. Offene Fragen (mit vorgeschlagenem Studio-Test)

1. **Beam-Breitenrichtung bei FaceCamera=false**: Spannt die Breite die lokale Y- oder Z-Achse der Attachments auf, und wie wird zwischen A0 und A1 interpoliert? *Test:* Beam zwischen zwei Default-Attachments, A0 nacheinander um X/Y/Z rotieren, Draufsicht und Seitenansicht vergleichen. **[kritisch]**
2. **Flipbook-Texturgrößen heute (0.745)**: 1024² Pflicht, Zweierpotenzen 8..1024 oder rechteckig bzw. 4096 (Custom-Beta live?). Welche Grenzen haben `FlipbookSizeX/Y`, und in welcher Reihenfolge laufen die Frames? *Test:* 512²-, 256²- und 2048×512-Atlanten mit nummerierten Frames. **[kritisch]**
3. **Engine-Clamps** außerhalb der UI-Bereiche: Rate > 400, Lifetime > 20 (dokumentiert gekappt), TimeScale > 1, Size > 10, Squash außerhalb ±3, `Beam.Segments` max (oft wird 1000 vermutet, unbelegt), Width0 < 0 per Script, `FlipbookFramerate` > 30. *Test:* Wert setzen, zurücklesen, visuell prüfen.
4. **Emit-Obergrenze pro Aufruf** und ob `Emit()` vom Grafiklevel skaliert wird (widersprüchliche Berichte).
5. **Studio-Insert-Defaults** von Beam und Trail (gibt es weitere Abweichungen wie bei `LightInfluence`?).
6. **VelocityInheritance** bei anchored Parts mit gesetztem `AssemblyLinearVelocity` bzw. bei CFrame-Animation; bei Attachment-Parent: wessen Velocity zählt?
7. **Shape-Geometrie**: Werden Sphere, Cylinder und Disc als Ellipsoid bzw. elliptische Form in `Part.Size` eingepasst, und welche Achse ist die Zylinder- bzw. Disc-Normale? Was macht Box oder Disc mit Attachment-Parent?
8. **Edit-Mode-Details**: Feuern `RunService.Heartbeat`/`PreRender` im Edit Mode zuverlässig? Gilt `TimeScale=0` dort sofort? Verhalten bei pausierter Simulation?
9. **Doppelte Keypoint-Zeiten** (Step-Kurven) werden vom Konstruktor akzeptiert?
10. **`rbxasset://textures/particles/*` auf Player-Clients** (Mobile/Konsole) vorhanden? Aussehen und Auflösung der Dateien?
11. **EditableImage als `TextureContent`** von ParticleEmitter, Beam und Trail im Edit Mode (für Previews nicht hochgeladener Texturen)?
12. Wird `ParticleEmitter2D` (FFlag `UIParticles`) bald veröffentlicht? Relevant für UI-VFX in einer späteren ASTRA-Phase.

---

## 6. Quellen

Offiziell / Roblox-eigene Dateien (VERIFIED):
- Lokal: `/root/tools/ref/Full-API-Dump.json`, `/root/tools/ref/API-Dump.json`, `/root/tools/ref/globalTypes.d.luau`, `/root/tools/ref/version.txt` (0.745.0.7451137)
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/particle-emitters.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/beams.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/trails.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/index.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/ParticleEmitter.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Beam.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Trail.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Attachment.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Bone.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Workspace.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/RunService.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/EditableImage.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/ParticleEmitterShape.yaml (sowie ParticleEmitterShapeStyle, ParticleEmitterShapeInOut, ParticleOrientation, ParticleFlipbookLayout, ParticleFlipbookMode, ParticleFlipbookTextureCompatible, TextureMode, NormalId im selben Verzeichnis)
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/NumberSequence.yaml (sowie NumberSequenceKeypoint, ColorSequence, ColorSequenceKeypoint, NumberRange, Content)
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/environment/global-wind.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/projects/assets/index.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/tutorials/use-case-tutorials/vfx/use-particles-for-explosions.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/tutorials/use-case-tutorials/vfx/custom-particle-effects.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/tutorials/use-case-tutorials/vfx/laser-traps-with-beams.md
- https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/rbxManifest.txt
- https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml
- https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/rbxPkgManifest.txt
- https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/version.txt

Community / Snippets (REPORTED):
- https://devforum.roblox.com/t/particles’-flipbook-release/2029388
- https://devforum.roblox.com/t/animated-particles-with-the-particle-flipbooks-beta/1718023
- https://devforum.roblox.com/t/client-beta-optimize-your-particle-animations-with-custom-flipbook-layouts/4005128
- https://devforum.roblox.com/t/flipbook-only-supports-particle-textures-of-sizes-in-replicatedstorage/3118761
- https://devforum.roblox.com/t/why-is-the-max-image-resolution-1024x1024/1679078
- https://devforum.roblox.com/t/particle-emitters-must-yield-after-being-parented-before-using-emit/34752
- https://devforum.roblox.com/t/graphics-quality-lowering-particle-emission-rates/1241979
- https://devforum.roblox.com/t/a-way-to-make-particleemitter-rate-ignore-graphics-quality/474762
- https://devforum.roblox.com/t/particle-emitter-limit-on-low-graphics-is-impacting-my-game/2159584
- https://devforum.roblox.com/t/bypassing-forced-beam-lod/2426888
- https://devforum.roblox.com/t/beam-optimization-is-wronglypoorly-implemented/2939171
- https://devforum.roblox.com/t/beams-and-trails-dont-show-up/3145864
- https://devforum.roblox.com/t/trails-not-visible-not-working-when-in-roblox-studio/3146228
- https://devforum.roblox.com/t/trails-do-not-render-properly-if-rotated-about-an-origin/2613978
- https://devforum.roblox.com/t/fast-moving-trails-do-not-render/1853349
- https://devforum.roblox.com/t/how-to-make-a-beam-always-straight/3076533
- https://devforum.roblox.com/t/how-would-i-stop-beam-orientation-with-parts/3323908
- https://devforum.roblox.com/t/why-do-particle-emitters-appear-differently-in-studio-than-when-testing/95781
- https://devforum.roblox.com/t/particles-in-studio-rely-on-fps/2719243
- https://devforum.roblox.com/t/particles-have-a-delay-when-enabling/3181609
- https://devforum.roblox.com/t/particleswedges-being-weird/3792199
- https://devforum.roblox.com/t/velocityinheritance-overshoots/1023366
- https://devforum.roblox.com/t/particleemitter-size-property-number-sequence-has-max-of-1/1506337
- https://devforum.roblox.com/t/studio-beta-major-updates-to-in-experience-mesh-image-apis/3225681
- https://devforum.roblox.com/t/a-current-explanation-of-normal-identities-and-security-tags/219471
