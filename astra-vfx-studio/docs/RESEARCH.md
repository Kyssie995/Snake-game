# ASTRA VFX Studio – Recherche (Phase 1)

Stand: 2026-10-27 · Phase 1 (Research & Architecture) · Engine-Stand der lokalen API-Daten: **0.745.0.7451137**

Dieses Dokument fasst neun geprüfte Recherchenotizen zusammen. Die Detailbelege stehen in den Notizen unter
[`docs/research/`](research/). Die harten Engine- und Studio-Grenzen mit allen Einzelbelegen stehen in
[`ROBLOX_API_CONSTRAINTS.md`](ROBLOX_API_CONSTRAINTS.md), der Funktionsvergleich in
[`FEATURE_COMPARISON.md`](FEATURE_COMPARISON.md), die verbindliche Architektur in [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Lesehilfe: Evidenz-Labels

| Label | Bedeutung |
|---|---|
| **VERIFIED** (Verifiziert) | Offizielle Roblox-Doku (Quelltext von `Roblox/creator-docs`), lokaler API-Dump 0.745 bzw. luau-lsp-Typen, Roblox-eigene Dateien (`ReflectionMetadata.xml`, `rbxManifest.txt`), README/Changelog/Paket des jeweiligen Produkts selbst oder ein lokal nachgestellter Test (Rojo 7.7.1, Lune 0.11.1). |
| **REPORTED** (Berichtet) | DevForum, Creator-Store-Seiten, Videos, X, Drittseiten, Such-Zusammenfassungen. |
| **ASSUMPTION** (Annahme) | Eigene Schlussfolgerung oder Modellwissen, das gegen keine Quelle geprüft werden konnte. |
| **IDEA** (Eigene Idee) | Eigener Designvorschlag für ASTRA. Kein Fakt. |
| **NOT FOUND** | Gesucht, nichts gefunden. |
| **MIXED** | Produkt mit teils VERIFIED-, teils REPORTED-Belegen. |

Regeln für dieses Dokument:

1. Jede Notiz enthält einen Abschnitt „Verifikation“ eines unabhängigen Prüfers. **Wo der Prüfer korrigiert, gilt die
   Korrektur.** Solche Stellen sind mit *(Verifikation)* markiert.
2. Kein Label wird gegenüber der Notiz angehoben. Wo der Prüfer selbst eine offizielle Quelle nachgereicht hat, ist das
   ausdrücklich vermerkt.
3. Abschnitt 2 und 3 beschreiben **fremde Produkte, die Engine und Fremdquellen**. Eigene Vorschläge für ASTRA stehen
   gesammelt in Abschnitt 4 und tragen immer das Label **IDEA**.
4. ⚑ = entscheidungsrelevant (eine ASTRA-Architektur- oder Implementierungsentscheidung hängt daran).

---

## 1. Zweck und Methode

### 1.1 Zweck

Die Recherche soll fünf Fragen beantworten, bevor ASTRA implementiert wird:

1. Was gibt es schon? Welche Roblox-VFX-Plugins und -Module existieren, was können sie, was loben und kritisieren
   Nutzer?
2. Was lässt sich von Profi-Werkzeugen (Unity VFX Graph, Unreal Niagara, Blender Geometry Nodes, After Effects)
   übernehmen, und was ist auf Roblox nicht übertragbar?
3. Welche Grenzen setzen Engine und Studio-Plugin-API? Sie bestimmen Datenformat, Vorschau, Timeline und Runtime.
4. Mit welcher Werkzeugkette kann Claude Code ohne externe AI-API und ohne direkten Studio-Zugriff Effekte als Dateien
   erzeugen, die zuverlässig in Studio und im Spiel ankommen?
5. Welche Regeln aus dem VFX-Handwerk und welche Performance- und Netzwerkregeln brauchen Presets,
   Performance-Analyzer, Qualitätsprofile und Net-Schicht?

### 1.2 Vorgehen

- Neun Themen, je ein Research-Subagent. Danach hat je ein **unabhängiger Verifier** versucht, die kritischen Claims
  aktiv zu widerlegen, und eine Stichprobe der übrigen VERIFIED-Claims nachgeprüft (Verdikte CONFIRMED / PARTIAL /
  REFUTED / UNVERIFIABLE). **Kein Claim wurde widerlegt (REFUTED).** Zahlreiche Claims sind PARTIAL; ihre Korrekturen
  sind hier eingearbeitet.
- Die Notizen:

| Thema | Notiz | Evidenzschwerpunkt |
|---|---|---|
| ROS Particle Editor | [`research/ros-particle-editor.md`](research/ros-particle-editor.md) | nur REPORTED (Snippets) |
| Qwinkle's Part-Icles 2 (QP2) | [`research/qwinkle-particles2.md`](research/qwinkle-particles2.md) | README VERIFIED, Rest REPORTED |
| Weitere Roblox-VFX-Plugins (20+) | [`research/other-roblox-vfx-plugins.md`](research/other-roblox-vfx-plugins.md) | gemischt |
| API: ParticleEmitter, Beam, Trail, Attachment, Flipbooks | [`research/api-particles-beams-trails.md`](research/api-particles-beams-trails.md) | überwiegend VERIFIED |
| API: Geometrie, Licht, Tween, Sound | [`research/api-geometry-lighting-tween.md`](research/api-geometry-lighting-tween.md) | überwiegend VERIFIED |
| API: Studio-Plugin | [`research/api-studio-plugin.md`](research/api-studio-plugin.md) | überwiegend VERIFIED |
| Tooling für den Claude-Workflow | [`research/tooling-claude-integration.md`](research/tooling-claude-integration.md) | VERIFIED (Doku + lokale Tests) |
| Profi-VFX-Tools | [`research/pro-vfx-tools.md`](research/pro-vfx-tools.md) | Unity/Blender VERIFIED, AE REPORTED, Niagara/Sequencer ASSUMPTION |
| VFX-Design und Performance | [`research/vfx-design-performance.md`](research/vfx-design-performance.md) | Design REPORTED, Performance überwiegend VERIFIED |

### 1.3 Quellenlage und Einschränkungen der Sandbox ⚑

- **Nicht erreichbar** (Proxy 403 oder Verbindungsfehler): `devforum.roblox.com`, `create.roblox.com` (Creator Store
  und Creator Hub), `roblox.com/library`, YouTube, die GitHub-Weboberfläche, `*.github.io`, die Doku-Seiten mehrerer
  Plugin-Hersteller (u. a. `qwinkleparticles2.com`, `docs.zilibobi.dev`, `phase-doc.vercel.app`,
  `effect-designer.igottic.com`), außerdem `docs.unity3d.com`, `dev.epicgames.com`, `docs.blender.org` und
  `helpx.adobe.com`.
  **Folge:** DevForum-, Creator-Store- und YouTube-Inhalte kennen wir **nur aus WebSearch-Zusammenfassungen**. Sie sind
  höchstens REPORTED. Screenshots und Videos wurden nicht gesehen. Preise, Ratings und Datumsangaben aus Store-Snippets
  sind Momentaufnahmen.
- **Erreichbar:** `raw.githubusercontent.com`. Darüber lief die **offizielle Roblox-Doku als Quelltext** von
  `Roblox/creator-docs` (inklusive Open-Cloud-OpenAPI-Spec), READMEs und Changelogs öffentlicher Repos, der Quelltext
  der Unity-VFX-Graph-Doku, der Blender-Quelltext-Mirror und der Community-Scripting-Guide zu After Effects. Dazu kamen
  `registry.npmjs.org` und der Mirror `MaximumADHD/Roblox-Client-Tracker` (Branch `roblox`, ebenfalls Version
  0.745.0.7451137) für `ReflectionMetadata.xml` und `rbxManifest.txt`.
- **Lokal:** `Full-API-Dump.json`, `API-Dump.json` und `globalTypes.d.luau` für **Engine 0.745.0.7451137**. Rojo 7.7.1,
  Lune 0.11.1, selene 0.31.0 und StyLua 2.6.0 wurden empirisch getestet; die Testprojekte lagen im Scratchpad, nicht im
  Repo.
- **WebSearch-Budget:** Das Budget ist geteilt und war mehrfach erschöpft. Die Originalläufe zu Tooling und Profi-Tools
  hatten **keine einzige Websuche**, die Verifier konnten teilweise nachsuchen. Bei den API-Notizen zu Geometrie und
  Studio-Plugin war das Budget gegen Ende erschöpft, beim Verifier der Design- und Performance-Notiz ebenfalls.
- **Kein Roblox Studio.** Die Umgebung ist ein Linux-Container; Studio gibt es nur für Windows und macOS. **Kein
  Studio-Verhalten wurde selbst getestet.** Alle Edit-Mode-Aussagen stammen aus Doku oder Forum. Was in Studio zu prüfen
  ist, steht in Abschnitt 5.
- **Unreal Niagara, Unreal Sequencer und die After-Effects-Oberfläche:** keine Quelle erreichbar. Diese Aussagen sind
  **ASSUMPTION (Modellwissen)** und dürfen allein keine Entscheidung tragen.
- **Widersprüchliche Snippets:** Such-Zusammenfassungen ordnen Posts im selben Thread teils verschiedenen Autoren zu
  (deutlich im ROS-Thread). Aussagen der Form „der Autor sagte X“ sind deshalb nur mit Vorbehalt verwendbar.
- **Clean Room:** Es wurde kein Fremdcode kopiert. Die QP2-Plugin-Datei wurde bewusst nicht geladen (die Lizenz
  verbietet Decompilation), der QP2-Runtime-Quelltext nicht geöffnet. MIT-Projekte dienen nur als Konzeptreferenz.
  `forge-vfx` darf laut Lizenz ohnehin nicht von Plugins oder Entwickler-Tools geladen werden (VERIFIED, siehe 2.1.5).

---

## 2. Befunde pro Thema

### 2.1 Bestehende Roblox-VFX-Plugins

#### 2.1.1 Marktbild

Der Markt 2023–2026 ist fragmentiert, aber sehr aktiv. Die Notizen unterscheiden fünf Produktklassen
(Einordnung: ASSUMPTION auf Basis der Einzelbefunde):

1. **All-in-one-Plugins auf nativen Instanzen** (ParticleEmitter, Beam, Trail plus Attribute): VFX Suite, VFX Editor,
   VFX Forge, VFX Studio (XxOmqxXNerd), Sine VFX, Phase VFX, Effect Designer Suite, „Beziers“/vfxer, EasyVFX.
   Gemeinsam haben sie eigene Sequence- und Bezier-Editoren, ein Emit-Fenster, Retime/Resize/Recolor, eine
   Asset-Bibliothek, ein Emit-Runtime-Modul und oft eine globale Studio-API über `shared`.
2. **Timeline- und Sequencer-Tools:** Moon Animator 2 (in der Praxis das VFX-Timing-Werkzeug), Eclipse Animator, Arc,
   Motion, Visulie, dazu Exporter, die Moon-Timings in Spieldaten übersetzen.
3. **Eigene Partikelsysteme** aus Parts, Meshes oder SurfaceGuis: Lumina (Node-Graph), VortexFX, Flare Craft.
   Durchgängige Kritik: deutlich langsamer als native Emitter, oft nicht mehr gepflegt.
4. **UI-Partikel** auf ImageLabel-Basis (Emitter2D, UIParticles, 2D Emitter, UIParty, ParticleUI, rParticle). Die
   Engine 0.745 enthält zusätzlich eine native, **unveröffentlichte** Klasse `ParticleEmitter2D` (VERIFIED: Dump-Tag
   `NotBrowsable`, FFlag `UIParticles`, keine Doku-Seite).
5. **Kleine Helfer:** Emit-Plugins, Scaler, Sequence-Editoren, das Lightning-Beams-Modul.

#### 2.1.2 Produktübersicht

| Produkt | Klasse | Preis / Lizenz | Kern | Evidenz |
|---|---|---|---|---|
| ROS Particle Editor (roasted_shrimps, 2022) | Helfer, Visualisierung | unbekannt | Multi-Emitter-Edit von Size/Transparency/Squash, Trajektorien- und Spawn-Gizmos | REPORTED |
| Qwinkle's Part-Icles 2 (QP2, QwinkleTee) | Custom-Emitter auf beliebigen Instanzen | 20 USD oder 8000 R$, 7-Tage-Trial, „All rights reserved“; Runtime mit Attributionspflicht | 70+ animierbare Properties, Graph-Editor, Nesting, Events, Runtime-Modul | MIXED |
| VFX Suite (PrimeVoxel, 2023) | All-in-one | ca. 4,99 $ laut Konkurrenz-Thread | Better Emit, Sequence Copier, Bezier-Graph mit Presets, Retime, Resizer, Trail Preview | REPORTED |
| VFX Editor (VirtualButFake, jetzt tijnepema) | All-in-one | MIT; Store-Version ca. 4,99 $ (REPORTED) | eigener NumberSequence-Editor mit Easing/Bezier, Properties-Ersatz, Multi-Property-Edit, Texture Storage mit JSON | VERIFIED |
| VFX Forge (zilibobi) | All-in-one | kostenpflichtig; Emit-Modul unter VFX-DL-1.1 | Mesh-/Decal-Flipbooks, 3D-Beziers, Lightning, Camera Shake, 26 Bezier-Presets, `shared.vfx`, kein Sequencer | MIXED |
| VFX Studio (XxOmqxXNerd) | All-in-one | kostenlos | 96 % bei 800+ Votes; Effektmodell nur aus einer Drittanalyse bekannt | REPORTED |
| EasyVFX (VuxSussy, 1.0.0 am 2026-10-16) | All-in-one für Nicht-Programmierer | MIT | Presets, Effekt-Blöcke, Share-Codes, Client-Rendering, Claude-Code-Plugin (nur auf `main`, unveröffentlicht) | VERIFIED |
| Arc (sevenIIl, Sept. 2026) | Timeline | kostenlos | Emit-Keyframes, Scrubbing-Vorschau, Events, ModuleScript-Export | REPORTED |
| Moon Animator 2 (xsixx) + Moon VFX Exporter, MoonVFXCompiler | Timeline, Exporter | kostenpflichtig + Free-Version | De-facto-Timing-Tool; Exporter erzeugen Cue-Tabellen | MIXED |
| Motion, Visulie, Eclipse Animator | Timeline | – | Animation als Daten, Methodenaufrufe, Event-Tracks | REPORTED |
| Phase VFX (2026) | All-in-one | – | 12 Effekttypen, `shared.vfx`, Code-Generierung | REPORTED |
| Sine VFX | All-in-one | 5–7 $ | Emit-Fenster, Pfad- und Spawn-Visualizer, Partikelzähler, `shared.sv` | REPORTED |
| Effect Designer Suite (igottic) | All-in-one | kostenlos, Open Source | Emit-Attribute, ColorSequences im Oklab-Raum | REPORTED |
| „Beziers“/vfxer, VFX Scripter Pro, SteakParticles | diverse | – | Add-ons, Script-Bibliothek, Presets | REPORTED |
| Lumina (Mqxsyy) | eigenes Partikelsystem mit Node-Graph | MIT, WIP | Node-Gruppen Spawn/Initialize/Update/Render/Logic | VERIFIED (Repo) / REPORTED (Performance) |
| VortexFX (FancyDucc) | eigenes 3D-Partikelsystem | Custom Provision License | Kollision, Audio-Reaktion | VERIFIED (README) / REPORTED |
| Flare Craft | eigenes Partikelsystem | 600 R$ | modular, seit 2024 nicht gepflegt | REPORTED |
| UI-Partikel-Module | UI | diverse | ImageLabel-basiert | MIXED |
| Lightning Beams (Quasiduck) | Modul | MIT (Port) | prozedurale Blitze mit Perlin-Noise | VERIFIED (README) / REPORTED (Kritik) |
| Emit-Helfer und Sequence-Tools | Helfer | – | Emit-Count/-Delay, Scaler, Tangenten-Editor | MIXED |
| Studio-Bordmittel (Sequence-Popups, Animation Editor, Curve Editor) | – | – | Referenz für UX und Grenzen | VERIFIED |
| „Bezier Sequencer“ / „Particle Emitter Previewer“ | – | – | – | NOT FOUND |

#### 2.1.3 ROS Particle Editor (alle Produktaussagen REPORTED)

- Studio-Plugin von **roasted_shrimps**, Creator-Store-Asset **8813198599**. Vorgestellt am **15.02.2022** im
  DevForum-Thread „The World's Best Particle Editor Plugin! (99% SURE)“. Rund 20–21 Antworten (Seite 2 zeigt Posts bis
  #23), ca. 35–37k Aufrufe, 165 Likes, letzte Aktivität Februar 2026. Preis, Lizenz und Update-Stand: **nicht
  ermittelbar**.
- **Viewport-zentrierter „Particle Edit Mode“:** Bei selektiertem Emitter erscheint rechts ein Button, links liegen
  Buttons für Size, Transparency und Squash. Diese drei Werte lassen sich laut Selbstbeschreibung für **mehrere Emitter
  gleichzeitig** ändern, ohne Obergrenze für Size und Squash. Ob die Multi-Edit-Semantik absolut oder relativ ist,
  bleibt unbekannt *(Verifikation)*.
- **Trajektorien- und Spawn-Gizmos:** Linien zeigen die erwartete Flugbahn, aquafarbene Linien den Spawn-Bereich. Mit
  dem Update vom 16.02.2022 wechselte das Plugin von `ConeHandleAdornment` zu `LineHandleAdornment`, und die Linien
  übernehmen seitdem die Partikelfarbe; „blaue Linien“ ist veraltet *(Verifikation)*. Emitter an Attachments und Bones
  werden unterstützt.
- **Lob:** Lerneffekt („zeigt genau, was jede Einstellung tut“) und eine große, gut lesbare UI. Belegt sind nur 2–3
  positive Kommentare; „nachweislich hoher Lernwert“ wäre überzogen *(Verifikation)*.
- **Kritik:** Fehler beim Klick auf Size/Transparency. Konflikt mit einem Fremd-Plugin „Bezier Sequencer“ (vermutlich
  BezierSequence, Asset 8133535339; ASSUMPTION). Wer was wann sagte, ist in den Snippets widersprüchlich. Ein Nutzer
  ohne Bezier Sequencer meldet am 11.01.2026, dass das Plugin trotzdem nicht erscheint; der Konflikt erklärt also
  **nicht alle** Ausfälle *(Verifikation)*. Am selben Tag kam der Wunsch, das Plugin abschalten zu können, wenn man
  nicht an VFX arbeitet.
- **Abgelehnter Wunsch** nach Partikeln, die einer Bezier-Kurve folgen. Dass der **Autor** abgelehnt hat, ist **nicht
  gesichert**; drei Snippets nennen die Antwort einen Kommentar *(Verifikation)*. Die technische Aussage stimmt aber:
  Native Partikelbewegung entsteht nur aus Speed, Acceleration, Drag, VelocityInheritance und LockedToPart; es gibt
  keine Pfad-Property (VERIFIED, `ParticleEmitter.yaml`).
- **Vertrauens-Report:** Im Thread berichtet jemand von einem „verdächtigen“ Skript namens „There's a scary monster in
  here“ im Plugin. Zuordnung unklar, Auflösung nicht sichtbar (REPORTED, *Verifikation*).
- **Preview-Runtime-Abweichung:** Ein Thread meldet unterschiedliche Ergebnisse zwischen „RosParticle“-Vorschau und
  Skript, erklärt mit `Emit()` statt `Enabled = true`. Ob ROS gemeint ist, ist unbestätigt (REPORTED, schwach,
  *Verifikation*).
- Für einen eigenen Curve-Editor, Presets, Color-Editing, Beams/Trails, Undo oder Export gab es keine Belege (NOT
  FOUND). Wartungsstatus: wirkt seit 2022 ungepflegt; wegen der widersprüchlichen Zuordnung bleibt das ASSUMPTION.
- **Studio-Kontext, der ROS' Nische erklärt:** Das Properties-Fenster konnte Sequence-Properties bei Mehrfachauswahl
  nicht bearbeiten. Staff nannte das „known limitation (missing feature, rather than a bug)“ bzw. „working as
  designed“. Die Begründung „kein sinnvoller Startwert“ wurde **so nicht gefunden**. Am nächsten kommt: Eine Änderung
  würde alle Sequences überschreiben, und Reset könnte die Einzelwerte nicht wiederherstellen. In Thread 425043 steht
  zudem ein Post „I just enabled a change …“ ohne bestätigten Autor oder Datum, und 2023 fragte ein Nutzer trotzdem noch
  danach. **Stand 2026 in Studio testen** (REPORTED, *Verifikation*). Der Studio-Curve-Editor kappt Size bei 10; das wird
  noch um 2024 berichtet (Thread 3224754). Die Engine-Grenze 200 nennt nur ein alter Staff-Post (REPORTED).

#### 2.1.4 Qwinkle's Part-Icles 2 (QP2)

**Identität, Preis, Verteilung**

- „Qwinkle's Part-Icles 2“, Autor Qwinkle/QwinkleTee. **20 USD** über Ko-fi/PayPal oder **8000 Robux** per Gamepass,
  7-Tage-Trial, Whitelist an die Roblox-User-ID (VERIFIED, README). Gumroad-Angaben (20 USD, Lifetime-Lizenz) sind
  REPORTED. Discord/Bloxlink braucht nur der Robux-Weg; Ko-fi und Gumroad whitelisten automatisch über die User-ID
  *(Verifikation)*.
- Verteilt als `.rbxm` über GitHub, Update über „Save as Local Plugin“ plus Studio-Neustart (VERIFIED, README).
  „Obfusziert“ stützt sich auf **ein einziges** Snippet einer älteren Doku-Seite; das README verbietet nur Decompilation.
  „Nur GitHub“ ist widerlegt: Es gibt eine Creator-Store-Seite (Asset 78969824830970, 26 Reviews, Publisher „QwinkleTee's
  Teashop“) *(Verifikation)*.
- Die Creator-Store-Regeln **beschränken** obfuszierten Code, `getfenv`/`setfenv`/LuaVMs, das Nachladen entfernter
  Assets (`require(assetId)`, `loadstring`, `InsertService:LoadAsset`, `AssetService:LoadAssetAsync`,
  `ModuleScript.LinkedSource`) und „extremely large scripts“ (VERIFIED, `creator-store.md`; Wortlaut „restricts“, nicht
  „prohibits“, *Verifikation*).

**Funktionen (VERIFIED, Hersteller-README, sofern nicht anders markiert)**

- Verwandelt Part, MeshPart, Model, Attachment, Beam, Trail, PointLight, Highlight, Blur, Bloom, ColorCorrection,
  Atmosphere und ImageLabel in skriptgetriebene Emitter. Über 70 Properties lassen sich über die Partikel-Lebenszeit
  animieren.
- **Graph-Editor:** Bezier- und Linear-Segmente in einem Graphen, Envelope als Zufallsstreuung, 20 Presets,
  Vereinfachung per Ramer-Douglas-Peucker mit Auto-Minimize (kleinste Keypoint-Zahl innerhalb 5 % Abweichung), 50 Schritte
  Undo/Redo, Copy/Paste zwischen Properties mit automatischer Skalierung auf den Zielbereich.
- **Nesting:** Emittierte Klone tragen eigene Kind-Emitter mit. Der `EmitDelay` verschachtelter Klone wird automatisch
  auf 0 gesetzt. Laut Doku lässt sich dadurch **nicht zwischen Ebenen staffeln**, empfohlen werden Skripte mit
  `task.wait` (REPORTED, *Verifikation*).
- **Events** OnEmit, OnHit, OnDeath, OnDestruction mit ModuleScript-Handlern. Die Handler-Signatur ist öffentlich nicht
  dokumentiert *(Verifikation)*. Maximal 256 Events pro Frame (REPORTED).
- **Link-System** Weld, Follow, Pivot (Runtime zusätzlich WeldWithoutRotation); Ziel kann auch die Kamera sein.
- **Animate-Mode** (In-place-Loop ohne Klone), Textur-Inventory mit **7800+** Einträgen (9000+ laut Gumroad, REPORTED),
  Spritesheet-Zerlegung, PNG-Upload (braucht Studio-Beta-Features), Bulk-Tools (Resize, Retime, Hue, Shifter,
  Clipboard, Scan), **Emit-Code-Generator** auch für Moon Animator 2, **Motion Preview** mit 20 Envelope-Varianten,
  Theme-Editor.
- Bearbeitung nicht transformierter, nativer Emitter im selben Panel (REPORTED, Doku-Seite).

**Datenmodell und Fehlermuster** ⚑

- Effekte liegen als Instanz-Attribute (60+ pro Item), `Configuration`-Kinder (`PartIcleProperties`, darin `Events`)
  und `ObjectValue`s. Fehlt ein Pflichtteil (meist `RenderTemplate`), wird der Emit **still ignoriert** (VERIFIED).
  Weitere stille Fehlerquellen: fehlendes `:Activate()` im Live-Spiel, `Enabled = false` nach dem Transform (REPORTED,
  FAQ).
- Das V2-Attributformat verlangt, ältere Effekte **im Plugin neu zu speichern**. Die Runtime migriert nicht; das
  Neuspeichern ist faktisch der Migrationspfad (VERIFIED, *Verifikation*).

**Runtime-Modul** (VERIFIED, README)

- Lesbarer Lua-Quelltext, eingefrorener Snapshot, manuelles Update. API u. a. `AbsoluteEmit(root) → number?` (Dauer
  in Sekunden, `nil` = quasi endlos; feuert auch native Emitter), `AbsoluteEmitAt(root, originCF, options?)`,
  `AbsoluteSetTimescale` (0 friert ein, < 0 kehrt um), `Preload/Deload`, `Activate`.
- Performance-Konzept laut Hersteller: **eine** Heartbeat-Verbindung, Emit-Loops resümieren auf dem Client auf
  `PreRender`, gestufte Abtastung (`TotalKeyFrames`; Default 100 nur laut Doku-Seite, REPORTED), LIFO-Pool mit
  TTL-Sweep, allokationsfreie innere Schleifen. **Pooling ist seit v39 für neu eingerichtete Partikel standardmäßig
  aus**, weil Wiederverwendung „subtile visuelle Randfälle bei Beams und Trails“ erzeugt.
- Kosten laut Doku-Seite: ein Skript-Update pro lebendem Partikel und Schritt, **keine** Einsparung für Distanz oder
  Off-Screen, Model-Partikel = ganzes Model, 3 s Lebenszeit bei 100 Steps ≈ 33 Updates/s; Schreibzugriffe nur bei
  Step-Wechsel (REPORTED). Das Zitat „the plugin doesn't warn“ hat nur **eine** Quelle, und es gibt keinen Benchmark
  *(Verifikation)*.
- Widersprüchlicher Ablageort: „Insert Module“ legt die Runtime nach ServerScriptService, das Runtime-README verlangt
  ReplicatedStorage (VERIFIED, *Verifikation*).
- Runtime-Lizenz: Nutzung und Änderung im eigenen Spiel erlaubt, keine Weitergabe; **monetarisierte Spiele müssen
  sichtbar attribuieren** (VERIFIED, `LICENSE.md`).

**Lücken und Feedback**

- In keiner Quelle fand sich eine **Timeline** oder ein **Node-Graph**. Das bleibt ASSUMPTION, weil sich Abwesenheit
  nicht beweisen lässt; der angekündigte „Workspace Manager“ ist inhaltlich unbekannt *(Verifikation)*. „Keyframes“
  meint bei QP2 nur Abtastschritte.
- 26 kurze, positive Store-Reviews; keine substanzielle Kritik gefunden (REPORTED). Version 1 wurde am 2025-09-08
  angekündigt; ihre Funktionen ließen sich nicht ermitteln.
- `AssetService:CreateAssetAsync` ist laut offizieller Doku derzeit **nur in lokal geladenen Plugins** nutzbar und lädt
  ohne Rückfrage hoch (VERIFIED, `AssetService.yaml`, *Verifikation*).

#### 2.1.5 Weitere Produkte (Auszug)

- **VFX Editor** (VERIFIED, README, Wiki, Changelog): Eigener NumberSequence-Editor als „Carbon copy“ des Studio-Editors
  plus Easing-Style/-Direction pro Segment und Bezier-Handles. **Easing- und Bezier-Daten liegen in Attributen; geht das
  Attribut verloren, werden alle Easing-Daten zurückgesetzt.** Properties-Fenster-Ersatz mit Suche nach Namen oder
  Properties, Multi-Property-Edit nur bei gleichem Typ **und** gleicher Semantik, virtualisierte Listen,
  konfigurierbare Max Size/Max Squash, „Lightweight Mode“. Changelog: 1.0.3 Memory Leak in eigenen Canvas- und
  Scroller-Komponenten, 1.0.5 Absturz bei Property-Feldern, 1.0.6/1.0.9 rekursive State-Fehler in der Fusion-UI, 1.0.8
  Absturz durch kaputten Texturpfad, 1.0.9 Umbenennung der Attribute auf `EmitCount`/`EmitDelay`. Der „.1“-Eingabefehler
  ist nur REPORTED *(Verifikation)*.
- **VFX Forge** (Store/itch REPORTED; Emit-Modul VERIFIED über README und npm `@zilibobi/forge-vfx` 2.4.0): Mesh- und
  Decal-Flipbooks, 3D-Beziers, Lightning, Shockwave, Screen Effects, Camera Shake, 26 Bezier-Presets. Der Autor plant
  **keinen Sequencer** und bietet stattdessen Einzeiler-Emit-Code für Moon-Events (REPORTED). Das Emit-Modul kennt emit
  mit Skalierung oder Render-Tiefe, ein „Finished“-Promise, enable/disable über ein `Enabled`-Attribut auch für
  Nicht-Emitter, retime, resize, recolor (replace/multiply, HDR-Faktor bleibt) und Attribut-Caching auf dem Client.
  **Lizenz VFX-DL-1.1:** Nutzung nur eingebettet in die Runtime einer Experience, **ausdrücklich nicht durch Studio-Plugins
  oder Entwickler-Tools** (VERIFIED, *Verifikation*). Das Modul setzt `shared.vfx` **auch zur Laufzeit im Spiel**
  (VERIFIED, *Verifikation*).
- **VFX Studio (XxOmqxXNerd)** (REPORTED): kostenlos, 96 % bei 800+ Votes, 110 Reviews, Update 2026-09-07. Das
  Effektmodell (kein eigenes Format, `EmitDelay`/`EmitDuration`/`EmitCount`, `<Property>Sequence`-Attribute,
  Tween-Schritte, Camera-Shake- und Impact-Frame-Templates, Code-Generator, eine Heartbeat-Verbindung pro getweenter
  Property) kennen wir **nur aus einer Drittanalyse** im EasyVFX-Repo. Die Doku-Seite unter `sytranom.github.io` markiert
  ihre Referenzseiten selbst als „generated by AI … for demonstration purposes“ und taugt **nicht als Beleg** (VERIFIED,
  *Verifikation*).
- **EasyVFX** (VERIFIED, README/Docs/Changelog, MIT): Zielgruppe Nicht-Programmierer, Effekte aus Blöcken (Slash, Ring,
  Lightning, Debris, Camera Shake, Impact Frame u. a.), Share-Codes mit Validierung, scharfe Formen aus Geometrie statt
  Texturen, Client-Rendering mit **einer** Animationsschleife, temporäre Teile in der Camera mit `Archivable = false`,
  automatische Qualitätsstufen, Rate-Cap 400, Eclipse-Animator-Event-Tracks. **KI-Workflow:** Claude-Code-Plugin
  (Skills effect/story/components/preview/texture), headless Lune-Timeline-Recorder mit Partikel-Nachsimulation,
  Strips/Diffs und Budget-Gates (`budget.particles/beams/pieces/lights`, `ends_clean`, `flash.frames/rate`) gegen
  `baseline.json`; ausdrücklich nur eine Approximation. Diese KI-Teile stehen laut Changelog unter **[Unreleased] auf
  `main`, nicht im Release 1.0.0** *(Verifikation)*.
- **Arc** (REPORTED): Emit-Keyframes mit Count, Duration und Delay, Vorschau folgt dem Scrubber (rückwärts nur in einem
  Snippet), benannte Events mit je einer Funktion im Export, VFX-Forge-Konvertierung, Moon-Sync, Keyframe-Gruppen,
  ModuleScript-Export mit `Start()` und einem Handle mit `Cancel()`. v2.0.0, erstellt 2026-09-29, Update 2026-10-07.
  **3D-Beziers unbestätigt**; ein Snippet nennt `Animation.Play()` statt `Start()`; laut DevForum Open Source mit Lizenz
  gegen Weiterverkauf und Umbenennung *(Verifikation)*. Eine inoffizielle **„Arc VFX MCP“**-Erweiterung eines Dritten
  (README VERIFIED) bietet 61 MCP-Tools über eine Bridge auf `127.0.0.1:41573`; sie baut aus dem Original-`Plugin.rbxm`
  des Nutzers eine modifizierte Fassung.
- **Moon Animator 2 und Exporter:** Moon ist in der Praxis das Timing-Werkzeug vieler Teams (REPORTED). Der **Moon VFX
  Exporter** erzeugt eine reine Daten-Cue-Tabelle (Frame → Effekt, Offsets relativ zum HumanoidRootPart) und meldet
  Warnungen statt Fehler (VERIFIED, README). **MoonVFXCompiler** erzeugt aus Moon- oder Eclipse-Saves Model plus
  Player-Modul und setzt im Spiel das ForgeVFX-Modul voraus (VERIFIED, README). Motivation laut Autor: manuelles
  Portieren kostet **4–6 Stunden pro 30–60-s-Effekt** (REPORTED, Selbstauskunft).
- **Motion, Visulie, Eclipse Animator** (REPORTED): Animation als rohe Luau-Daten mit Runtime-Engine; Visulie animiert
  auch NumberSequence/ColorSequence und Methodenaufrufe wie `Emit()`.
- **Eigene Partikelsysteme:** Lumina (MIT, WIP; Node-Gruppen ähnlich Unitys Contexts; VERIFIED) rendert laut Autor über
  SurfaceGuis, laggt vor allem durch Property-Updates und „can not compete with the default particle emitter“
  (REPORTED). VortexFX nennt 2D-Partikel selbst „much more performant“ (VERIFIED, README); der Rewrite ist REPORTED.
  Flare Craft: ca. 1000 Partikel bei ca. 30 fps laut Entwickler, nicht gepflegt (REPORTED).
- **Lightning Beams:** geschichtetes Perlin-Noise, Bezier-Krümmung wie `Beam.CurveSize0/1`, Pulse-Welle, Sparks- und
  Explosion-Untermodule (VERIFIED, README des Ports). Kritik an Destroy-Problemen und Heartbeat-Verbindungen (REPORTED).
- **Helfer:** roblox-particle-util nutzt `EmitCount` und **`DelayTime`** statt `EmitDelay` (VERIFIED, README).
  SmoothSequence Graph speichert Tangenten als Attribute mit Präfix `SMOOTHSEQUENCE_` und platziert Keypoints
  fehlerminimierend (REPORTED).
- **Studio-Bordmittel** (VERIFIED): Die NumberSequence-/ColorSequence-Popups können Keypoints hinzufügen, verschieben,
  löschen und Envelopes ziehen; Bezier, Presets, Multi-Edit oder Copy/Paste gibt es dort nicht. Der Animation Editor
  nutzt seconds:frames bei 30 fps, Animation Events und Keyframe-Optimierung; beim Looping wird nicht vom letzten zum
  ersten Key interpoliert. Der Curve Editor kennt Linear/Constant/Cubic und „Generate Curve“. Plugins können Studios
  eingebaute Value-Editoren nicht nutzen (VERIFIED, keine API im Dump; Feature-Request 1920538 REPORTED).

#### 2.1.6 Querschnitt: Konventionen im Ökosystem ⚑

- **Emit-Attribute:** `EmitCount`, `EmitDelay`, `EmitDuration` sind eine De-facto-Konvention (VERIFIED bei VFX Editor
  1.0.9 und EasyVFX; REPORTED bei VFX Forge, QP2, vfxer und weiteren). **Nur die Namen sind gleich, Typen und Semantik
  nicht:** `number` oder `NumberRange`, bei QP2-Trails ein String „min,max“; `EmitDuration` meint je nach Tool etwas
  anderes; `EmitCount`-Defaults weichen ab (REPORTED, *Verifikation*). Abweichender Name: `DelayTime`
  (roblox-particle-util, VERIFIED).
- **`<Property>Sequence`-Attribute** animieren die gleichnamige Property über die Effektdauer: bei EasyVFX VERIFIED, bei
  VFX Studio nur aus der Drittanalyse, also Single-Source *(Verifikation)*.
- **Globale Namensräume über `shared`:** VFX Forge und Phase VFX belegen beide `shared.vfx`, vfxer zusätzlich `shared.fx`,
  Sine VFX `shared.sv`. Forge setzt `shared.vfx` auch **im laufenden Spiel**, und der Moon VFX Exporter ruft dort
  `shared.vfx.emit` auf, wenn vorhanden *(Verifikation)*. Es gibt also echte Kollisionen.
- **Authoring-Metadaten in Attributen** (VFX Editor, SmoothSequence, EasyVFX). Wenn die Attribute verloren gehen, sind die
  Kurven weg (VERIFIED bei VFX Editor).
- **Retime/Resize/Recolor** sind Standardoperationen. Semantik laut VFX-Studio-Analyse: Lifetime und Rate durch den
  Faktor teilen, Speed, Drag, FlipbookFramerate, RotSpeed und TextureSpeed multiplizieren, Acceleration quadratisch
  (REPORTED).
- **Funktions-Baseline 2026**, die Nutzer erwarten (ASSUMPTION aus den Produktlisten): Partikel/Beams/Trails, Mesh- und
  Decal-Flipbooks, 3D-Beziers, Lightning, Shockwaves, Camera Shake, Impact Frames, Retime/Resize/Recolor,
  Kurven-Presets, Asset-Bibliothek, Runtime-Emit-Modul, generierter Trigger-Code, Undo/Redo, Light/Dark-Theme. Die
  Konvergenz der Feature-Listen gilt für VFX Forge und Phase VFX (und laut Analyse VFX Studio), **nicht** für Sine VFX
  *(Verifikation)*.
- **Native vs. eigene Systeme:** Alle erfolgreichen Authoring-Tools bauen auf nativen Emittern; eigene Systeme werden
  durchweg wegen Performance kritisiert (REPORTED).
- **Timeline und KI sind keine Alleinstellungsmerkmale mehr** (ASSUMPTION): Arc und Motion füllen seit 2026 die
  Timeline-Lücke; EasyVFX (auf `main`) und die Arc-MCP-Erweiterung zeigen KI-Agent-Integration.
- **Namenskollision:** „VFX Studio“ ist ein verbreitetes kostenloses Plugin mit 800+ Votes (REPORTED).

### 2.2 Profi-Tools: Niagara, VFX Graph, Geometry Nodes, After Effects

#### 2.2.1 Unity Visual Effect Graph (VERIFIED, offizieller Doku-Quelltext, Paket 17.x)

- **Zwei Logikachsen:** Der vertikale Ablauf-Fluss verbindet Contexts (Spawn → Initialize → Update → Output), darin
  laufen Blocks von oben nach unten. Der horizontale Daten-Fluss verbindet Operatoren mit Block-Ports.
- **Flow-Kompatibilität als dokumentierte Tabelle** (nur ein Initialize an ein Update, SpawnEvent und GPUSpawnEvent
  schließen sich aus). Statisch inaktive Blocks werden ausgegraut und beim Kompilieren entfernt. **Subgraph-Blocks haben
  keinen Activation-Port** *(Verifikation)*.
- **Settings vs. Properties:** Settings brauchen Neukompilieren, Properties sind live und verbindbar. Composition-Modi
  Set/Add/Multiply/Blend; Sample-Modi OverLife, BySpeed, Random, RandomConstantPerParticle, Custom.
- **Exponierte Parameter mit Instanz-Override:** Ein grüner Punkt markiert exponierte Properties, eine Checkbox zeigt den
  Override an, Abwählen setzt auf den Default zurück. Bei einem Asset-Wechsel bleiben Overrides erhalten, wenn Name und
  Typ passen. Property- und Event-Binder koppeln Szenenwerte an Parameter.
- **Events** sind nur Strings (Default `OnPlay`/`OnStop`) und können Attribut-Payloads tragen. **GPU-Events** (OnDie,
  OnCollide u. a.) lassen Partikel Partikel spawnen.
- **Spawn-Zustandsmaschine:** Loop Duration, Loop Count, Delay Before/After, jeweils konstant oder zufällig; laut
  Lifecycle werden die Werte pro Loop-Durchlauf neu ausgewertet *(Verifikation)*. Burst-Blocks Single/Periodic.
- **Subgraphen** für System, Block und Operator. **Nur System-Subgraphen** werden tief kopiert und kosten dadurch
  Importzeit und Speicher *(Verifikation)*. Templates mit Name, Kategorie, Beschreibung, Icon, Thumbnail, Favoriten.
- **Seeds:** Random Seed pro Instanz mit „Reseed On Play“. Die Doku verspricht „deterministic behavior **in random number
  generations**“, nicht einen insgesamt deterministischen Effekt *(Verifikation)*.
- **Timeline-Integration:** Control-Clips mit Scrubbing (Neuberechnung der Simulation), Start-Seed pro Clip, Prewarm,
  Events mit „Time Space“ (After Clip Start, Before Clip End, Percentage, Absolute). Grenzen: Max Scrub Time,
  GPU-Spitzen beim Rückwärtsspielen. REPORTED (Unity Issue Tracker): Aktivierungs-Events unter 0,3 s können „by design“
  übersprungen werden *(Verifikation)*.
- **Profiling-Panels** zeigen CPU/GPU pro System, Alive/Capacity und eine Heatmap-Schwelle; die Doku nennt die Werte
  selbst „general indicators“.

#### 2.2.2 Unreal Niagara und Sequencer (ASSUMPTION, Modellwissen, keine Quelle erreichbar)

- System → Emitter → Module in einem vertikalen Stack mit Stages; Parameter-Namespaces; **User Parameters**;
  Emitter-Vererbung; Scratch Pad; **Effect Types/Scalability** (Distanz-Culling, Instanzlimits, Significance,
  Budget-Skalierung); Debugger; Determinismus-Option; Life-Cycle-Track im Sequencer.
- Sequencer: Outliner mit Tracks, Sections mit Ease an den Rändern, getrennte Playback- und Selection-Range,
  Event-Tracks als Trigger oder Repeater.
- Vor jeder Entscheidung gegen `dev.epicgames.com` prüfen (Abschnitt 5.4).

#### 2.2.3 Blender Geometry Nodes, Node Editor, Dope Sheet (VERIFIED, Quelltext-Mirror; `main` = 5.4 alpha)

- **Sockets** haben eine Farbe pro Datentyp und eine Form (Circle, Square, Diamond, jeweils auch mit Punkt). Die
  Datenstruktur (Single, Field, Grid, List, Dynamic, Auto) ist Teil der Typprüfung. Die Bedeutung der Formen
  (Kreis = Einzelwert, Raute = Feld) ist ASSUMPTION, weil das Handbuch nicht erreichbar war.
- **Link-Sprache:** gestrichelt und dünner = **Feld-Link**; ungültig **und** gemutet = rot. Gestrichelt heißt in Blender
  also nicht „gemutet“ *(Verifikation)*. Inaktive Sockets werden ausgegraut, wenn sie keine Wirkung auf die Ausgabe haben.
  Gemutete Knoten reichen ihre Eingänge durch (Bypass).
- **Shortcut-Drift:** Blender hat Node- und Timeline-Shortcuts in 4.5/5.0 geändert. In 5.0 wurde die
  Keyframe-Sprungrichtung von Hoch/Runter vertauscht; auf `main` ist Ctrl+X „Ausschneiden mit Neuverbinden“, Shift+X
  „Löschen mit Neuverbinden“ *(Verifikation)*. Profi-Shortcuts sind also keine stabile Referenz.
- **Dope Sheet/Graph Editor:** Box-, Spalten- (K) und Lasso-Auswahl, Preview-Range (P/Alt+P), Sekunden/Frames
  umschaltbar (Ctrl+T), Interpolation (T), Easing (Ctrl+E). R = Keyframe-Typ gilt nur im Dope Sheet *(Verifikation)*.

#### 2.2.4 Adobe After Effects (Scripting Guide REPORTED, Oberfläche ASSUMPTION)

- Interpolation pro Key getrennt für In und Out: LINEAR, BEZIER, HOLD. Temporal Ease = Speed + Influence (0,1–100 %).
  **Pro Dimension** gilt Ease nur bei nicht-räumlichen 2D/3D-Werten wie Scale; räumliche Werte wie Position haben ein
  Ease je Seite *(Verifikation)*.
- Layer mit In/Out-Point und Start-Time in Kompositionszeit, Stretch, Shy/Solo/Lock, Labels. Marker mit Kommentar,
  **Dauer** und Label. **Work Area** getrennt von der Kompositionsdauer.
- Dass sich Keyframe-Zeiten auf den Layer-Start beziehen, belegt der Guide **nicht** *(Verifikation)*. Graph Editor
  (Value/Speed), Easy Ease (F9) und die Timeline-Shortcuts sind Modellwissen.

#### 2.2.5 Was auf Roblox nicht übertragbar ist ⚑

GPU-Simulation, Capacity und Instancing, Per-Partikel-Attribute und -Logik (BySpeed, OnDie, OnCollide), Custom HLSL und
Shader, Mesh-Partikel, Vector Fields, SDFs, Point Caches, Bounds- und Culling-Kontrolle, Fixed Delta Time, Prewarm und
exaktes Scrubbing nativer Partikel. Grund: `ParticleEmitter` hat keinen Seed, keine Per-Partikel-Events, und
`FastForward` ist `RobloxScriptSecurity` (VERIFIED, Dump). Render-Reihenfolge gibt es nur über `ZOffset`, und zwar an
ParticleEmitter und Beam, nicht an Trail (VERIFIED). **Teilersatz:** Der Envelope der Sequence-Keypoints ist eine native
Zufallsvariation pro Partikel und Keypoint, aber kein zufälliger Sample-Zeitpunkt (VERIFIED, *Verifikation*).

### 2.3 Roblox-APIs (Kurzfassung)

Alle Einzelbelege und Quellen stehen in [`ROBLOX_API_CONSTRAINTS.md`](ROBLOX_API_CONSTRAINTS.md). Hier nur die Punkte,
die ASTRAs Architektur direkt prägen:

**Partikel, Beams, Trails**

- ⚑ Kein Seed, kein Zugriff auf einzelne Partikel, keine Spawn-, Death- oder Collision-Events (VERIFIED).
  `FastForward` trägt den Tag `RobloxScriptSecurity` (VERIFIED); dass Plugins diese Stufe nicht haben, ist REPORTED
  (keine offizielle Tabelle der Identity-Stufen gefunden). `TimeScale` ist laut Doku ein Wert von 0 bis 1 (VERIFIED);
  ob die Engine Werte über 1 ablehnt, ist undokumentiert. **Native Partikel lassen sich nicht deterministisch seeken.**
- `Emit()` erzeugt Partikel mit Alter 0. Clear plus Re-Emit beim Rückwärts-Seek zeigt deshalb nicht den Zustand zum
  Zeitpunkt t. Korrekt sind nur „Replay-to-t“ (vom Effektstart neu abspielen und bei t einfrieren, Latenz ≈ t) oder eine
  eigene Vorschausimulation; deterministisch ist nur der Burst-Zeitplan (*Verifikation*, auf VERIFIED-Fakten).
- `TimeScale` hatte 2023–2024 mehrere Studio-Bugs (keine sichtbare Wirkung, Regression bei Size/Transparency,
  verschwindende Partikel) (REPORTED).
- `Color`, `Acceleration`, `LightEmission`, `ZOffset` wirken laut Doku auf aktive **und** neue Partikel; `Rate`,
  `Lifetime`, `Rotation`, `RotSpeed`, `Speed` nur auf neue. Für `Size`/`Transparency` ist die Live-Wirkung aus dem
  Wortlaut abgeleitet (VERIFIED, *Verifikation*).
- ⚑ NumberSequence und ColorSequence: **2 bis 20 Keypoints**, erster bei 0, letzter bei 1, Interpolation linear (Farben in
  RGB), Envelopes symmetrisch und ebenfalls linear interpoliert (VERIFIED). Der Konstruktor sagt „non-descending“,
  `NumberSequenceKeypoint.Time` sagt „ascending“; ob doppelte Zeiten (Stufen) zulässig sind, ist **ungesichert**
  *(Verifikation)*.
- Dokumentierte Grenzen: Lifetime max. 20 s, Rate max. 400/s pro Emitter (100/s auf Mobile), FlipbookFramerate max. 30
  (VERIFIED). Die Studio-UI-Bereiche aus `ReflectionMetadata.xml` sind keine Engine-Clamps (Interpretation:
  ASSUMPTION).
- `LightInfluence` ist 0 bei `Instance.new`, aber 1 beim Einfügen über Studio (VERIFIED). Defaults sind also nicht
  verlässlich.
- Flipbooks: Die Quellen zur Texturgröße widersprechen sich (1024² in Doku und Dump-Default, „exaktes Vielfaches des
  Layouts“ in der Property-Doku, 8–1024 Zweierpotenzen im Release-Post, 4096 in einer Client-Beta). Sicherer Standard:
  1024². Kompatibilität ist nicht abfragbar; Clients mit wenig Speicher deaktivieren Flipbooks automatisch (VERIFIED,
  Release-Post und Beta REPORTED).
- Beam: kubische Bezier-Kurve; Breite nur linear (`Width0` → `Width1`); `Segments ≥ n − 1` ist nur eine **Untergrenze**;
  Static verhält sich wie Wrap; kein `Clear`, kein `TimeScale` (VERIFIED). Welche Attachment-Achse bei
  `FaceCamera = false` die Breite aufspannt, ist undokumentiert (Studio-Test).
- Trail: zeichnet nur bei Bewegung ≥ `MinLength`; Breite = Attachment-Abstand × `WidthScale` (0–1); Lifetime 0,01–20 s;
  ein Attachment-Wechsel löscht den Trail (VERIFIED). Trail-Lifetime soll FPS-abhängig sein (REPORTED).
- Attachment: Serialisiert wird nur `CFrame` (VERIFIED).
- `Emit()` direkt im Frame nach dem Parenten kann verloren gehen (REPORTED). Ein `Emit()` an einem Emitter außerhalb
  des Bildes soll aufgeschoben werden, bis er sichtbar ist (REPORTED, *Verifikation*).
- Edit Mode: Ein eingefügter Emitter emittiert sofort, und Roblox' eigenes Tutorial testet Bursts mit einem
  `Emit()`-Plugin. **Plugin-`Emit()` funktioniert also im Edit Mode** (VERIFIED aus Guide und Tutorial).
- Das Setzen von `TextureContent` aktualisiert `Texture` (VERIFIED, `ParticleEmitter.yaml`).

**Zeit und Tweening**

- ⚑ `TweenService` hat kein Seek und keine Zeitposition. Die Doku listet die tweenbaren Typen mit „including“, also
  **nicht abschließend**; NumberSequence, ColorSequence, NumberRange und BrickColor sind nach Forenberichten nicht
  tweenbar (VERIFIED/REPORTED, *Verifikation*). `EasingStyle.Bezier` (11) und `Spring` (12) existieren im Dump, aber
  `TweenInfo.new` und `GetValue` werfen bei ihnen einen Fehler (VERIFIED).
- ⚑ `RunService`: `PreRender` und `BindToRenderStep` nur auf dem Client. Im Edit-Kontext sind `IsClient()` **und**
  `IsServer()` true, in Collaborative Edit ist `IsServer()` false (VERIFIED). **Ob `Heartbeat`/`PreRender` für
  Plugin-Code im reinen Edit Mode feuern, ist nicht dokumentiert** (UNVERIFIABLE). `RenderStepped` soll bei minimiertem
  Fenster oder offenem Script-Tab nicht feuern (REPORTED).

**Geometrie, Licht, Post-Effekte**

- ⚑ `MeshPart.MeshId`/`MeshContent` haben Write-Security `NotAccessibleSecurity`, auch für Plugins (VERIFIED).
  `AssetService:CreateMeshPartAsync` yieldet und scheitert in der Praxis oft an Asset-Rechten (REPORTED);
  `MeshPart:ApplyMesh` ist **synchron** (VERIFIED, kein `Yields`-Tag, *Verifikation*). `SpecialMesh.MeshId` ist frei
  schreibbar; `SpecialMesh.MeshType` ist per Default `Head`; Materialien rendern auf SpecialMesh laut Doku nicht korrekt
  (VERIFIED).
- `RenderFidelity`, `CollisionFidelity`, `FluidFidelity` sind nur für Plugins/Open Cloud schreibbar; Emissive- und
  PBR-Maps an Decal und SurfaceAppearance nur mit PluginSecurity (VERIFIED). Die Runtime braucht dafür Vorlagen.
- Lichter: nur als direktes Kind von BasePart oder Attachment; `Range` max. 120 Studs; `Angle` max. 180 (VERIFIED).
- Bloom und ColorCorrection wirken nur unter `Lighting` (alle Spieler) oder `CurrentCamera` (lokal) (VERIFIED).
- Highlight: 255 pro Client; **auch deaktivierte belegen einen Slot**; Create/Destroy löst einen Geometry-Rebuild aus
  (VERIFIED).

**Studio-Plugin**

- ⚑ Widgets über `CreateDockWidgetPluginGuiAsync` (die Nicht-Async-Variante ist deprecated). `UserInputService`
  funktioniert in Widgets nicht; die PluginGui-Input-Events und `OverrideStudioAction` sind `RobloxScriptSecurity`.
  Plugins können **keine Default-Shortcuts** vergeben und Actions weder deaktivieren noch abhaken (VERIFIED). Ob
  Studio-Shortcuts (Delete, Ctrl+Z, Ctrl+D) bei fokussiertem Widget mitfeuern, ist unbelegt (ASSUMPTION, Studio-Test).
- ⚑ ChangeHistoryService: höchstens eine Recording pro Plugin, scheitert im Solo-Playtest, ein Plugin-Reload bricht sie
  nicht ab (VERIFIED). Instanzen mit `Archivable = false` werden ignoriert (REPORTED). **Änderungen an `Source` von
  Skripten erfasst CHS absichtlich nicht** (REPORTED, Staff „Working as Designed“, ca. April 2026, *Verifikation*).
  `Destroy()` ist nicht rückgängig zu machen; Plugins sollen `Parent = nil` nutzen (REPORTED, *Verifikation*).
- ⚑ Plugins können **keine Dateien frei schreiben** und haben **keinen Clipboard-Zugriff** (VERIFIED). Erlaubt ist HTTP
  zu `localhost`/`127.0.0.1`; beim ersten Zugriff kann ein Berechtigungsdialog kommen (VERIFIED). WebSocket über
  `CreateWebStreamClient`, nur in Studio, max. 4 Clients (VERIFIED).
- ⚑ `ViewportFrame` rendert offiziell keine Schatten und kein Post-Processing (VERIFIED) und laut DevForum **keine
  ParticleEmitter, Beams und Trails**, bestätigt durch einen Feature-Request vom Juni 2026 (REPORTED).
- `Archivable = false` hält Instanzen aus Speichern und Clone heraus, aber Studios Duplicate und Copy/Paste machen die
  Kopie archivierbar (VERIFIED). `Camera` ist `NotReplicated` (VERIFIED); ein Vorschau-Ordner unter `CurrentCamera` ist
  in Team Create daher sehr wahrscheinlich lokal (ASSUMPTION).
- `StudioTestService.EditModeActive` ist das offizielle Signal „kein Test läuft“ (VERIFIED, *Verifikation*).
  `EncodingService` bietet Base64, Zstd und Hashes (Blake3, SHA-256 u. a.) mit Security None (VERIFIED).
- Settings: JSON mit String-Keys; Punkte, Anführungszeichen oder Zeilenumbrüche in Keys und Backslashes in Keys oder
  Werten können die Datei korrumpieren; stilles Scheitern bei mehreren Studio-Fenstern (VERIFIED).

**Audio**

- Das Umschalten von `Playing` im Properties-Fenster startet im Edit Mode keine Wiedergabe (VERIFIED, nur für diesen
  Fall). Sounds unter einem `PluginGui`/`DockWidgetPluginGui` spielen im Edit Mode per `:Play()` (REPORTED,
  Staff-bestätigt, *Verifikation*). Ein vorverdrahteter `AudioPlayer` soll im Edit Mode spielen (REPORTED, Staff).
  `AudioPlayer:Play(atTime)` plant sample-genau (VERIFIED).

### 2.4 Tooling für den Claude-Workflow

- ⚑ **Rojo 7.7.1 ist der zuverlässigste Weg Repo → Studio** (VERIFIED, Doku und lokale Tests). Die Standardabbildung
  `.json` → ModuleScript ist **verlustbehaftet**: Schlüssel werden sortiert, `null` verschwindet, `[]` und `{}` werden
  gleich, große Ganzzahlen verlieren Präzision (VERIFIED, lokal). Mit **`syncRules`** (seit 7.5) wird `*.vfx.json` zu
  einem `StringValue` mit dem **unveränderten JSON-Text** (VERIFIED, lokal).
- ⚑ **Rückweg Studio → Repo:** `rojo syncback` überspringt bestehende JSON-Module. **Mit derselben `syncRules`-Regel
  schreibt `syncback` eine geänderte StringValue aber byte-genau in die vorhandene `*.vfx.json` zurück** (VERIFIED,
  lokal, *Verifikation*). Einschränkungen: Es braucht eine aus Studio gespeicherte `.rbxm`/`.rbxl`, es ist kein
  Live-Weg, neue StringValues landen als `Name.txt`, und `syncback` normalisiert `.model.json` (Defaults entfallen,
  `Texture` → `TextureContent`, Floats als `1.0`). Rojos Two-Way-Sync ist laut Changelog experimentell. Für einen
  Live-Rückweg braucht es also eine eigene Bridge.
- ⚑ **`StringValue` hält höchstens 200 000 Zeichen** (VERIFIED, Doku); effektiv sollen es 199 999 sein (REPORTED).
  **Weder Rojo noch Lune prüfen die Grenze** (VERIFIED, lokal, *Verifikation*).
- **Lune 0.11.1** liest und schreibt rbxm/rbxl, prüft Properties gegen eine Reflection-DB (0.741, Engine ist 0.745),
  hat aber **keine Events, keine Engine-Methoden wie `Emit` und keine Simulation**; laut Typdefinition sind in Lune alle
  Properties les- und schreibbar, auch wo die Engine das verbietet (VERIFIED). Fallen: `Texture` aktualisiert in Lune
  nicht `TextureContent`, und sind beide gesetzt, schreibt Lune zwei `TextureContent`-Einträge (VERIFIED, lokal).
  **Lune kennt keinen `Random`-Datentyp**, und Roblox garantiert die Zahlenfolge von `Random` über Engine-Versionen nicht
  ausdrücklich (VERIFIED, *Verifikation*).
- ⚑ `@lune/serde` sortiert Schlüssel deterministisch, schreibt leere Tabellen als `{}`, **verwirft bei gemischten
  Tabellen die Nicht-Array-Schlüssel stillschweigend** und macht aus `NaN`/`inf` ein `null` (VERIFIED, lokal,
  *Verifikation*). `@lune/net` bietet HTTP- und WebSocket-Server, Default-Bind `127.0.0.1` (VERIFIED, lokal).
- **Eingebauter Studio-MCP-Server** (stdio, Quick Connect für Claude Code) mit u. a. `execute_luau`, `multi_edit`,
  `inspect_instance`, `screen_capture`, `start_stop_play`, `get_console_output` (VERIFIED, `studio/mcp.md`). Das alte
  `studio-rust-mcp-server` wird nicht mehr entwickelt (VERIFIED). Studio und damit MCP gibt es nur unter Windows und
  macOS (VERIFIED). Erfahrungsberichte zur MCP-Stabilität mit Claude Code fehlen.
- **Open Cloud Luau Execution** führt Luau headless gegen eine Place-Version aus: keine Physik, Skripte laufen nicht von
  selbst, Änderungen werden nicht gespeichert; Skript ≤ 4 MB, ≤ 5 min, 5 Task-Erstellungen/Minute pro Key-Owner;
  braucht API-Key und eine veröffentlichte Place. Jest Roblox unterstützt diesen Weg für CI (VERIFIED).
- **Studio Script Sync** synchronisiert zweiseitig, aber nur Skripte und Ordner, und ignoriert Attribute und Tags
  (VERIFIED). `InstanceFileSyncService` lässt Plugins den Sync-Zustand abfragen (VERIFIED, *Verifikation*).
- **Plugin-HTTP:** Lokal installierte Plugins sollen den Berechtigungsdialog umgehen, und es gibt einen eigenen Dialog
  „Script Injection“ für Plugins, die Skripte anlegen oder ändern (REPORTED, 2020, *Verifikation*). Rojos Host/Origin-Schutz
  gegen DNS-Rebinding ist bei `0.0.0.0`-Binds ohne `--allowed-hosts` aus (VERIFIED, *Verifikation*).
- **Require-by-string** (`./`, `../`, `@self/`) verhält sich in Engine, Lune und luau-lsp gleich und passt zu Rojos
  `init.luau` (VERIFIED). Aliases sind uneinheitlich: Lune kennt `.luaurc`, aber keine `.config.luau`-Aliases; die Engine
  dokumentiert Aliases nicht (VERIFIED/offen).
- **Toolchain:** Rokit (empfohlen, Aftman unmaintained), Wally (letztes Release 0.3.2 von 2023), selene (braucht für die
  Roblox-Std das Internet), StyLua, luau-lsp. Tests: Jest Roblox (aktiv), TestEZ (letztes Release 2022), run-in-roblox
  (braucht Studio) (VERIFIED).
- **Plattformfallen:** `rojo build --plugin`, `rojo plugin install` und Lunes `studioPluginPath()` scheitern unter Linux
  (VERIFIED, lokal).

### 2.5 VFX-Design-Handwerk (überwiegend REPORTED)

- **Intensität über die Zeit:** Wind-up/Anticipation → Crescendo/Climax (Impact) → Follow-through → Dissipation. Zwei
  Muster: **Impulse** (sofort, ohne lange Ankündigung) und **Rhythm** (fließend, oft geloopt). Auch sofortige Effekte
  sollen sauber ausklingen. Telegraph → Impact → Resolve wird nie vertauscht (REPORTED).
- **Gameplay vor Stil:** Form wird zuerst wahrgenommen; der hellste Wert gehört auf den spiel- oder schadensrelevanten
  Punkt; reines Weiß ist für die größten Momente reserviert. Prinzipien des GDC-2017-Bootcamps: Gameplay, Shape & Area of
  Effect, Contrast & Focal Point, Color & Identity, Timing & Threat Level (REPORTED).
- **Layering bei Impacts:** Instant-Flash (ca. 2–3 Frames), Burst-Core, Ring/Shockwave, Sparks (klein, in Jets
  gruppiert, gestreckt), Rauch (länger, gebrochene Silhouette), optional Distortion. Der Impact soll in etwa 1 s
  lesbar sein (REPORTED).
- **Rezepte** (Startwerte, keine Regeln):

| Rezept | Werte | Evidenz |
|---|---|---|
| Spark-Burst (offizielles Tutorial) | Lifetime 0,2–0,6, Speed 20–40, Drag 10, SpreadAngle 180/180, `Enabled = false`, `Emit(100)` | VERIFIED |
| Ambient-Flare (offizielles Tutorial) | LightEmission 1, ZOffset 1, Lifetime 10, Rate 0,45, Size 0 → 10; PointLight Brightness 2, Range 36 | VERIFIED |
| Impact-Flash | sichtbarer Peak ca. 2–3 Frames | REPORTED |
| Hit-Stop | leicht ca. 2–5 Frames, schwer länger (SFV-Beispiel 8), nicht über ca. 20 Frames | REPORTED |
| Impact Frame | ColorCorrection (Saturation 0/−1, Kontrast) plus Highlights, ca. 1–3 Frames; ColorCorrection kann Partikel verschlucken | REPORTED |
| Kamera-Shake | Trauma 0..1, Stärke ∝ Trauma² bis ³, Perlin-Noise pro Achse, Abklingen, Maximalauslenkung | REPORTED |
| Telegraph | Onset ca. 120–220 ms, Halten ca. 250–550 ms | REPORTED (schwach) |
| Shockwave | Expansion mit Quart/Quint/Circular Out, SpecialMesh.Scale statt MeshPart.Size; **keine belastbare Dauer gefunden** | VERIFIED (Easing) / REPORTED |

- **Roblox-native Techniken der Community:** Neon + Bloom; additive Partikel mit `LightEmission = 1` (dunkle Farben
  wirken dann transparent, VERIFIED); `SpecialMesh.Scale`-Tweens; ForceField-Schimmer (Rotkanal der Textur steuert das
  Muster); Beams mit `CurveSize` für Slashes; Attachment-Ketten mit Beams für Blitze; gestapelte Beams; Flipbooks;
  `VelocityParallel` mit negativem Squash für gestreckte Sparks (VERIFIED, Mechanik). **Glass-Distortion:** Refraktion wird
  auf Mobilgeräten nicht unterstützt (laut Verifikation offiziell belegt, `Material.yaml`/`materials.md`); „Grafik ≥ 8“ ist
  REPORTED; `Transparency > 1` ist undokumentiert und kann jederzeit brechen *(Verifikation)*.
- Für Shockwave-Dauer und typische Partikelzahlen je Effekttyp fanden sich **keine belastbaren Zahlen**. Viele
  Suchtreffer zu „Roblox VFX“ waren SEO-Spam und wurden verworfen.

### 2.6 Performance und Networking

**Rendering-Kosten** (VERIFIED, sofern nicht anders markiert)

- Partikel kosten über **Fill-Rate** und **Overdraw**, batchen schlecht, und **Property-Änderungen an ParticleEmittern
  können die Performance dramatisch beeinflussen**. Hebel laut MicroProfiler-Doku: weniger Emitter, kleinere Rate und
  Lifetime, **Emitter wenig bewegen**.
- Texturspeicher hängt von der Pixelzahl ab (1024² kostet 4 × 512²); Faustregel ≤ 512². Flipbooks kosten Speicher und
  werden auf Low-Memory-Clients abgeschaltet.
- Teiltransparenz läuft über einen eigenen Pass; die Doku rät zu 0 oder 1, wo möglich.
- **Schatten werden unterhalb von Qualitätsstufe 4 abgeschaltet.** Welche Skala „4“ meint (intern 21 Stufen, Spieler 10),
  ist **nicht dokumentiert** *(Verifikation)*. Parts werfen Schatten unabhängig von ihrer Transparenz; unsichtbare
  Träger-Parts brauchen `CastShadow = false`. `CastShadow` ist laut Doku aber kein Performance-Schalter; bei sichtbarer
  Geometrie nur Hinweis *(Verifikation)*.
- Das erste sichtbare Highlight kostet bis ca. 1 ms GPU auf Mobile; `Enabled` umschalten kostet nichts; deaktivierte
  Highlights belegen trotzdem einen der 255 Slots.
- `Debris` hat ein hartes Limit von 1000 Objekten, garantiert aber Zerstörung auch nach Skript-Ende.
- `BulkMoveTo` nur nutzen, wenn Bewegung wirklich der Engpass ist; der Default-Modus ist `FireAllEvents` und muss
  explizit überschrieben werden *(Verifikation)*.

**Grafikqualität und Engine-LOD**

- `UserGameSettings.SavedQualityLevel` (Automatic, 1–10) ist auf dem Client lesbar; `GraphicsQualityLevel` ist
  `RobloxScriptSecurity`; bei „Automatic“ gibt es laut Doku **keinen zuverlässigen Weg**, die echte Stufe zu lesen;
  `Stats:GetHarmonyQualityLevel()` braucht die Capability `InternalTest` (VERIFIED).
- `QualityLevel.yaml` bestätigt allgemein, dass Partikel-Render-Limits, Trail-Fidelity und Post-Effekt-Qualität mit der
  Stufe steigen, und nennt die Wirkung „platform- and device-specific and can not be relied upon“ (VERIFIED,
  *Verifikation*). Konkret berichtet: Rate ≈ `Rate × Level / 10`, Beam-Segments bis herunter auf 1 bis 2, globale Caps
  ca. 16000 (PC) bzw. 3500–3600 (Mobile/Konsole); ein Bug-Report von ca. Ende August 2026 sagt, die Rate-Skalierung greife
  derzeit nicht; ob `Emit(n)` skaliert wird, ist umstritten (alles REPORTED).
- Plugins können `settings().Rendering` (`QualityLevel`, `EditQualityLevel`) lesen und setzen (VERIFIED). Die Doku
  empfiehlt, jeden Effekt bei niedrigster und höchster Editor-Qualität zu prüfen.
- Mess-APIs mit Security None: `Stats.FrameTime` (nur Client), Render-CPU/GPU-Frame-Time, Draw Calls, Dreiecke,
  `GetMemoryUsageMbForTag(GraphicsParticles)` (nur mit `MemoryTrackingEnabled`), `SceneAnalysisService:GetTriangleCompositionAsync()`
  mit eigenem Pass „Particles“. Die Werte sind **szenenweit**, nur per Differenzmessung pro Effekt zu schätzen und auf dem
  Entwickler-PC nicht repräsentativ (VERIFIED, *Verifikation*).

**Networking**

- ⚑ Roblox empfiehlt ausdrücklich, Explosionen und Zauber **nicht serverseitig als Instanzen** zu erzeugen; der Server
  kennt nur Ort und Ergebnis, die Clients erzeugen die Visuals. Server-Tweens replizieren jeden Frame (VERIFIED).
- `UnreliableRemoteEvent` verwirft Payloads über **1000 Bytes** (900 B laut Ankündigung, nicht nachprüfbar), hat keine
  Reihenfolge und kein Queueing ohne Listener; Client→Server ca. 500 Requests/s pro Client und Remote-Typ (VERIFIED).
- ⚑ **StreamingEnabled:** Signal und referenzierte Instanz reisen unabhängig; Instanzargumente können `nil` sein oder
  später kommen; ausgestreamte Instanzen werden nach `nil` umgehängt, lokale Änderungen daran können verloren gehen.
  **Client-erzeugte Instanzen werden nicht ausgestreamt**, außer sie hängen unter einer Server-Instanz (VERIFIED,
  *Verifikation*).

---

## 3. Nutzer-Pain-Points und Feature-Requests (plugin-übergreifend)

Die Belege sind fast durchweg REPORTED und oft nur 1–2 Kommentare. Sie zeigen Bedarf, keine repräsentative Meinung.

| # | Pain Point / Wunsch | Betroffen | Evidenz | Quelle |
|---|---|---|---|---|
| P1 | UI zu klein, nicht skalierbar; Wunsch nach Scale-Option | VFX Suite (1–2 Kommentare); ROS wird für große UI gelobt | REPORTED | DevForum 2545686, 1668424 |
| P2 | Bestehende Effekte lassen sich schwer wieder ins Tool laden und nachbearbeiten (Size/Squash nicht ablesbar) | VFX Suite | REPORTED | 2545686 |
| P3 | Plugin läuft immer; Wunsch nach Abschalten, wenn man nicht an VFX arbeitet | ROS (Jan. 2026) | REPORTED | 1668424?page=2 |
| P4 | Plugin erscheint nicht / wirft Fehler beim Klick; Konflikte mit anderen Sequence-Plugins | ROS, „Bezier Sequencer“ | REPORTED | 1668424 |
| P5 | Kurven-Metadaten in Attributen gehen verloren oder werden zurückgesetzt | VFX Editor | VERIFIED (Wiki) | VFX-Editor-Wiki |
| P6 | Stille Fehlschläge (fehlendes Template, `:Activate()` vergessen, `Enabled` aus) | QP2 | VERIFIED / REPORTED | QP2-README, FAQ |
| P7 | Formatwechsel verlangt manuelles Neuspeichern, keine Migration in der Runtime | QP2 V2 | VERIFIED | QP2-Runtime-README |
| P8 | Memory Leaks, rekursive State-Fehler, Abstürze bei Texturen und Property-Feldern | VFX Editor | VERIFIED (Changelog) | VFX-Editor-Changelog |
| P9 | Dezimaleingabe „.1“ wird nicht akzeptiert; Texturen entladen beim Scrollen | VFX Editor | REPORTED | 3103467 |
| P10 | Eigene Partikelsysteme deutlich langsamer als native Emitter | Lumina, VortexFX, Flare Craft, Emitter2D | REPORTED (VortexFX: VERIFIED, README) | 2963557, 3131414, 2539746, 3742009 |
| P11 | Keine Timeline; Moon-Timings von Hand in Spielcode portieren, 4–6 h pro 30–60-s-Effekt | VFX Forge, Moon-Workflow | REPORTED (Selbstauskunft) | 3867553, MoonVFXCompiler-README |
| P12 | Runtime-Modul schwer verständlich; Store-Version hinkt der lokalen hinterher; Doku unvollständig | VFX Forge | REPORTED | 3867553 |
| P13 | Sequence-Properties bei Mehrfachauswahl nicht editierbar | Studio | REPORTED (Staff: „known limitation“; widersprüchlicher Post) | 2083516, 1071269, 425043 |
| P14 | Studio-Curve-Editor kappt Size bei 10, kein eigenes Min/Max, nicht resizable | Studio | REPORTED (noch ca. 2024) | 26161, 79122, 983469, 3224754 |
| P15 | Copy/Paste von Number-/ColorSequences, separater Curve Editor, mehr als 20 Keypoints, vereinfachter Bezier-Modus | Studio | REPORTED | 2795691, 2625485, 188572, 3356273 |
| P16 | Plugins sollen Studios eingebaute Value-Editoren und Picker nutzen dürfen | Studio | REPORTED (Request) / VERIFIED (keine API) | 1920538 |
| P17 | Partikel sollen einem Bezier-Pfad folgen | ROS-Thread | REPORTED | 1668424 |
| P18 | Graph-Presets „von A nach B mit Easing und N Punkten“, globale statt partikelgebundene Editoren, Type-to-select in Dropdowns | VFX Editor | REPORTED | 3103467 |
| P19 | Vertrauen: obfuszierter Code, verdächtige versteckte Skripte, Whitelist-DRM, Update per Neuspeichern + Neustart | ROS, QP2 | REPORTED / VERIFIED (QP2-Update-Weg) | 1668424, QP2-README |
| P20 | Vorschau und Runtime verhalten sich unterschiedlich (Emit vs. Enabled) | „RosParticle“ | REPORTED (schwach) | 2441406 |
| P21 | Zurückhaltung beim Kauf; kostenlose Konkurrenz setzt Preisdruck | Markt | REPORTED | 2545686, Store-Snippets |
| P22 | Kamera-Shake-Module stapeln Sustained-Shakes; Wunsch nach 3D-Ursprung | RbxCameraShaker, GG Camera Shake | REPORTED | 98482, 4731267 |

---

## 4. Chancen für ASTRA (alle Punkte: IDEA)

Alles in diesem Abschnitt sind **eigene Designvorschläge**. Sie stützen sich auf die genannten Befunde, sind aber nicht
selbst belegt. Nichts davon übernimmt Code oder Assets anderer Produkte.

### 4.1 Positionierung

- **O1 (IDEA):** ASTRA kann sich nicht allein über „Timeline“ oder „Claude erzeugt Effekte als Dateien“ abheben
  (Arc, Motion, EasyVFX `main`, Arc-MCP; 2.1.6). Die Differenzierung kommt aus der **Kombination**: versioniertes,
  validiertes Schema als einzige Wahrheit, deterministische Runtime ohne Plugin, ehrliche Vorschau mit dokumentierten
  Grenzen, Performance-Analyzer mit Vorwarnung und offene, Creator-Store-konforme Verteilung.
- **O2 (IDEA):** Nie zu „VFX Studio“ verkürzen; immer „ASTRA“ voranstellen (P-Namenskollision, 2.1.6).

### 4.2 Datenformat und Validierung

- **O3 (IDEA) ⚑:** Versioniertes JSON mit `formatVersion`, Schema und expliziten Migrationsfunktionen `vN → vN+1`. Die
  Runtime prüft die Version und migriert oder meldet laut, nie stille No-ops (P6, P7).
- **O4 (IDEA) ⚑:** Kurven sind im JSON reich (Bezier, Easing, beliebig viele Punkte) und werden deterministisch auf
  **≤ 20 lineare Keypoints** gebacken, fehlerminimierend (adaptive Abtastung + Vereinfachung), mit sichtbarer
  Fehlermarke. Attribute sind höchstens Cache, nie die einzige Quelle (P5). Doppelte Keypoint-Zeiten erst nach Studio-Test
  verwenden (2.3).
- **O5 (IDEA):** Ein Validator für Editor, CLI und Claude: 2–20 Keypoints, Zeiten 0 und 1, nicht fallend, Envelope ≥ 0,
  Farbkomponenten 0–1, `NumberRange` min ≤ max, Lifetime ≤ 20, FlipbookFramerate ≤ 30, klassenspezifische Clamps (Beam/Trail
  `LightInfluence` geklemmt, beim Emitter undefiniert), `Beam.Segments` als Warnung, Sphere/Cylinder an Attachment als
  Warnung, Properties mit Write-Security ≠ None als „nur über Vorlage“. Zusätzlich vor jedem Encode: keine gemischten
  Tabellen, keine nicht-endlichen Zahlen (2.4, serde-Falle).
- **O6 (IDEA):** Typisiertes `parameters`-Objekt mit Instanz-Overrides (Vorbild Unity exposed properties; `palette` wird
  Spezialfall), Preset-Vererbung als Diff (`extends`), verlinkte Duplikate (`instanceOf`), Track-Komposition (`blend`:
  set/add/multiply), Event-Anker (start/end/percent), Emissions-Loops, Marker mit Dauer und Kommentar, getrennte
  `editor`-Metadaten (Label, Solo, Shy, Lock, Notizen), Template-Metadaten für Preset-Browser und Claude (2.2.1, 2.2.4).
  Vererbung beim Kompilieren flach auflösen.
- **O7 (IDEA):** Enums als Namen speichern; jede Property explizit aus versionierten ASTRA-Defaults setzen
  (`LightInfluence`-Falle); Attachments nur als CFrame-Äquivalent; nur `TextureContent` schreiben, nie beide
  Textur-Properties (2.3, 2.4).
- **O8 (IDEA):** Eigener **PRNG in purem Luau** und eigener **deterministischer JSON-Encoder**, damit CLI (Lune), Plugin
  und Runtime byte-identische Ergebnisse liefern (Lune ohne `Random`, serde-Eigenheiten; 2.4).

### 4.3 Editor-UX

- **O9 (IDEA) ⚑:** Multi-Emitter-Editing als Grundfunktion: gleiche Werte → normaler Editor; abweichende Werte → „Mixed“
  mit überlagerten Kurven und expliziter Wahl zwischen **absolut** (eine Kurve für alle) und **relativ** (Scale, Offset,
  Retime, Invert, Normalize pro Kurve). Reset pro Emitter auf den eigenen Vorwert; ein Multi-Edit = eine Undo-Recording.
  Das adressiert genau die von Staff genannten Probleme (P13, ROS-Nische).
- **O10 (IDEA):** Soft-Ranges für Slider plus harte Validierung gegen Engine-Grenzen statt fester UI-Kappung bei 10;
  konfigurierbare Max-Werte (P14).
- **O11 (IDEA):** Verlustfreier **Import** vorhandener nativer Emitter in das JSON (inkl. Envelope), damit „bestehende
  Effekte nachbearbeiten“ funktioniert (P2).
- **O12 (IDEA):** Opt-in statt Always-on: Toolbar-Toggle mit gespeicherter Einstellung, Gizmos und Listener nur im aktiven
  Modus; UI-Scale-Setting; Studio-Theme-Sync über `StudioStyleGuideColor`; robuste Dezimaleingabe (`.1`, Komma/Punkt);
  Kurven-Presets inkl. „A → B mit Easing und N Punkten“; Copy/Paste von Sequences über ein eigenes Clipboard im Plugin
  (Plugins haben keinen Zugriff auf die System-Zwischenablage) (P1, P3, P9, P15, P18).
- **O13 (IDEA):** Viewport-Gizmos für Trajektorie und Spawn-Volumen über **ein** `WireframeHandleAdornment` pro Emitter
  (`AddPath`): Fächer aus Min/Mittel/Max-Bahn plus SpreadAngle-Kegel, optional gesampelte Bahnen mit festem Seed;
  Punkte relativ zur Adornee-Mitte, Umfärben = `Clear()` und neu zeichnen (VERIFIED-Semantik). Drag-Formel vorher
  empirisch kalibrieren, sonst „Näherung“ anzeigen. Lernmodus: Hover über eine Property hebt den betroffenen Gizmo-Teil
  hervor (ROS-Lob, P17).
- **O14 (IDEA):** Koexistenz mit Fremd-Plugins: jeder Schreibzugriff in `pcall`, externe Änderungen über
  `GetPropertyChangedSignal` und einen quantisierten Bake-Hash erkennen (float32-Speicherung beachten), Re-Entrancy-Guard,
  eigene Metadaten nur namespaced (`ASTRA_…`), nie Fremd-Attribute anfassen; Robustheitstests auch ohne Fremd-Plugin (P4).
- **O15 (IDEA):** Tastatur: widget-lokal über einen Input-Catcher-Frame; globale Aktionen als `PluginAction`s ohne
  Default-Shortcut; Overlay „?“ mit allen Kürzeln. Vorschlag: Leertaste Play/Pause, Esc Stopp, Links/Rechts Frame
  (Shift = 10), Pos1/Ende, J/K vorheriger/nächster Key, B/N Arbeitsbereich, A/F Ansicht, K Spaltenauswahl, M Mute,
  Shift+G Gruppe, Shift+N Notiz, Shift+M Marker. **Ctrl+D, Entf, Ctrl+Z erst nach Studio-Test belegen**, sonst X und
  Shift+D (2.2.3, 2.3).

### 4.4 Timeline, Vorschau, Scrubbing

- **O16 (IDEA) ⚑:** Zwei Track-Arten sichtbar trennen: **Emission-Events** (Burst, Enable-Fenster, Rate über die
  Effektzeit; wirken nur auf neue Partikel) und **Live-Property-Tracks** (emitter-weite Modulation, trifft alle lebenden
  Partikel). Das UI erklärt den Unterschied zwischen „über die Effektzeit“ und „über die Partikel-Lebenszeit“.
- **O17 (IDEA) ⚑:** Scrubbing nativer Partikel ehrlich lösen: vorwärts inkrementell; rückwärts **Replay-to-t** (Clear,
  ab 0 in Echtzeit abspielen, bei t einfrieren); optional ein „Ghost“-Modus mit eigener, geseedeter Simulation für
  framegenaue, aber nur näherungsweise gleich aussehende Darstellung. Hinweis „native Partikel sind nicht exakt seekbar“
  im UI. `TimeScale = 0` als Pause erst nach Studio-Test, Fallback Clear + Replay (2.3).
- **O18 (IDEA):** Vorschau im 3D-Viewport in einem nicht archivierbaren Ordner unter `workspace.CurrentCamera`;
  `Archivable = false` auch für Nachfahren; Selektionswächter gegen Duplikate von Vorschau-Objekten; vollständiges
  Aufräumen in `Unloading`. Das Viewport-Widget nur für Mesh/Part-Teile und Thumbnails (2.3).
- **O19 (IDEA):** Vorschau-Takt auf `Heartbeat` (nicht `PreRender`/`RenderStepped`), Uhr über `os.clock()`; Editor-Init
  und Vorschau über `StudioTestService.EditModeActive` steuern (2.3).
- **O20 (IDEA):** Vorschau und Runtime nutzen **denselben Emit-Pfad**, damit P20 nicht auftreten kann; erster `Emit()`
  nach dem Parenten einen Frame später.
- **O21 (IDEA):** Play-Controls wie Unity (Stop, Play/Pause, Step, Restart, Rate %, Event-Tester); getrennter
  Arbeitsbereich für Loops; Events über Zeitstempel-Überquerung auslösen, nicht über Bereichsprüfung pro Frame
  (Unity-0,3-s-Lehre).
- **O22 (IDEA):** Audio-Vorschau in dieser Reihenfolge versuchen: Sound-Klon unter dem eigenen DockWidget, `AudioPlayer`
  + `Wire` + `AudioDeviceOutput`, `PlayLocalSound`, Hinweis „nur im Playtest“. Nie `RunService:Run()` (startet die
  Simulation, deaktiviert Undo) (2.3).

### 4.5 Node-Graph

- **O23 (IDEA):** Graph und Timeline als zwei Sichten auf **ein** Datenmodell; der Graph wird beim Kompilieren in den
  Zeitplan entrollt. „OnDeath“/„OnHit“ für native Partikel nur als zeitbasierte Approximation oder für eigene
  Komponenten, klar gekennzeichnet (2.2.5).
- **O24 (IDEA):** Pins mit Farbe **und** Form; Link-Zustände sichtbar (ungültig = rot mit Diagnose, gemutet = rot/gedimmt,
  Laufzeit-Flüsse gestrichelt), unerreichbare Knoten ausgegraut, Mute/Bypass, Frames, Sticky Notes, Reroutes,
  kontextgefilterte Suche. Kompatibilitätsregeln als datengetriebene Tabelle, die Editor und Validator teilen. Eigene
  Farben, nicht von Unity oder Blender kopiert (2.2.1, 2.2.3).
- **O25 (IDEA):** Sub-Emitter-Offsets explizit erlauben (QP2 zwingt `EmitDelay` verschachtelter Emitter auf 0) und
  „Path Emitter“ als eigene Komponente (Attachment entlang einer Bezier-Kurve, emittiert per Rate oder `Emit()`), weil
  native Partikel keinem Pfad folgen (P17).

### 4.6 Runtime und Netzwerk

- **O26 (IDEA) ⚑:** Runtime-API mit Handle: ein Aufruf für einen ganzen Effekt inklusive nativer Emitter, Origin-Override,
  Timescale inklusive Freeze, `Duration`, `Completed`-Signal, `Stop()`; Effekte unabhängig mehrfach abspielbar (Vorbilder
  QP2 `AbsoluteEmit`, Arc `Start()/Cancel()`, Forge „Finished“).
- **O27 (IDEA):** Ein zentraler Scheduler, vorab gesampelte Kurven, vorallokierte Arrays, Pooling mit **expliziter
  Reset-Routine pro Instanztyp** (QP2-Lehre bei Beams/Trails), Highlights nur in kleinem, einstellbarem Pool und
  dauerhaft ungenutzte zerstören (Slots!), kein Debris im Runtime-Code, aber ein Fallback-Aufräumpfad über einen
  gemeinsamen Effekt-Root.
- **O28 (IDEA):** Property-Writes minimieren: Dirty-Check mit Epsilon, Update-Rate pro Kanal, Emitter möglichst nicht
  jeden Frame bewegen, Sequence-Kanäle nur bei echter Änderung neu bauen (2.6).
- **O29 (IDEA) ⚑:** Clients rendern, Server sendet nur Ort und Parameter; lokaler Effekt-Root, der einem Ziel per CFrame
  folgt (streaming-sicher), statt unter Server-Instanzen zu hängen; optionale Attach-ID mit kurzem Timeout, danach mit
  dem gesendeten CFrame spielen; Unreliable-Pfad mit Budget ≤ 900 Bytes, Sequenznummer und automatischem Ausweichen auf
  RemoteEvent, nur für kosmetische Effekte (2.6).
- **O30 (IDEA):** Kein `shared.vfx`/`shared.fx`/`shared.sv`, am besten gar keine `shared`-Globals; Zugriff per `require`.
  Runtime-Ablageort eindeutig ReplicatedStorage, im Plugin genauso einfügen (2.1.4, 2.1.6).
- **O31 (IDEA):** Kamera-Effekte als eigene, standardmäßig gedämpfte, opt-out-fähige Spur (Trauma-Shake, Impact Frame,
  Hit-Stop nur als Marker/Event, globaler Spieler-Multiplikator), weil `ReducedMotion` nicht lesbar ist (2.5).

### 4.7 Performance-Analyzer und Qualitätsprofile

- **O32 (IDEA) ⚑:** Analyzer, der **vor** dem Abspielen warnt (QP2 „warnt nicht“, Single-Source): geschätzte
  gleichzeitige Partikel (Rate × mittlere Lifetime + Bursts), Overdraw-Proxy, Emitter-Anzahl, bewegte Emitter,
  Property-Writes pro Sekunde, Beams × Segments, Parts, teiltransparente Parts, Lichter mit Schatten, Highlights gegen 255,
  Flipbook-Speicher. Ampel plus konkrete Vorschläge; alles als **Heuristik** gekennzeichnet, keine FPS-Versprechen.
  Harte Lints: Rate > 400 (Mobile-Profil > 100) nur für `Rate`, nicht für `Emit`.
- **O33 (IDEA):** Messmodus im Playtest per Differenzmessung aus `Stats` und `SceneAnalysisService`, mit Hinweis
  „Dev-PC nicht repräsentativ“; optional automatisiert über den Studio-MCP-Server (2.4, 2.6).
- **O34 (IDEA):** Quality-Preview im Editor über `settings().Rendering.EditQualityLevel` (niedrig/mittel/hoch, Originalwert
  immer wiederherstellen, auch bei `Unloading`).
- **O35 (IDEA) ⚑:** Keine doppelte Skalierung: Beam-Segments auf Low **nicht** zusätzlich reduzieren; bei Rate-Emittern
  lieber Spawn-Caps und Instanzlimits; `countScale` vor allem auf Bursts und eigene Geometrie. Mapping 1–10 → Profile als
  Konfiguration, nicht hart kodiert; adaptive Heuristik bei „Automatic“ mit Hysterese, Wechsel nur zwischen Effekten.
- **O36 (IDEA):** Effektklassen (`ambient`, `combat`, `cinematic`, `ui`) mit `maxInstances`, `cullDistance`, `priority`
  pro Qualitätsstufe; bei Budget-Ablehnung ein No-op-Handle statt Fehler (Vorbild Niagara Scalability, ASSUMPTION).

### 4.8 Claude-Workflow

- **O37 (IDEA) ⚑:** Pipeline ohne externe AI-API: JSON-Dateien im Repo sind die Wahrheit → `lune run` CLI validiert und
  formatiert mit demselben Luau-Kern wie das Plugin → Rojo bringt die Dateien per `syncRules` als rohe JSON-StringValues
  nach Studio → das Plugin beobachtet sie und baut die Vorschau neu. Eigene Dateiendung, damit die Regel greift:

  ```json
  "syncRules": [ { "pattern": "*.vfx.json", "use": "text", "suffix": ".vfx.json" } ]
  ```

  Die CLI erzwingt die Größengrenze (≤ 199 999 Bytes, Warnung deutlich früher).
- **O38 (IDEA):** Rückweg: optionale Bridge (Lune, nur `127.0.0.1`, Session-Token, Host/Origin-Prüfung immer aktiv,
  Port > 1024 und ≠ 1194, WebSocket mit Long-Polling-Fallback, 4-Client-Limit beachten). Fallback ohne Bridge:
  `PromptSaveSelectionAsync` → `.rbxm` → `rojo syncback`, Kopier-Feld, Datei-Import per `PromptImportFileAsync`.
  Der dateibasierte Weg muss ohne Bridge funktionieren.
- **O39 (IDEA):** MCP und Open Cloud Luau Execution nur als Verifikationsstufen (Engine-echte Tests, Screenshots,
  Konsolenausgabe), nie als Pflicht (Linux/CI ohne Studio).
- **O40 (IDEA):** Headless „Census“ pro Frame unter Lune (Anzahl Partikel/Beams/Lichter, Dauer, sauberes Ende) als
  Performance-Gate; Design-Lints für generierte Effekte (fehlender Peak am Impact-Marker, alle Layer gleich lang, alles
  weiß, keine Dissipation) als Stilhinweise; Presets nach dem Phasenmodell strukturiert (2.5). Konzeptionell ähnlich
  EasyVFX, aber eigene Umsetzung.
- **O41 (IDEA):** Lune-Tests mit einer Liste bekannter Abweichungen zur Engine (Texture/TextureContent, fehlende
  Datentypen, nicht-scriptable Properties, Reflection-DB 0.741), damit grüne Tests nicht falsch beruhigen.

### 4.9 Interop und Import

- **O42 (IDEA):** Importer für Community-Konventionen: `EmitCount`/`EmitDelay`/`EmitDuration` mit Alias `DelayTime`,
  Typ-Normalisierung (number, NumberRange, String), Semantik pro Quell-Tool, Forge-`Enabled`-Attribut, `<Property>Sequence`.
  Ein „kompatibler Export“ trägt nur die Basis-Emit-Attribute; tool-spezifische Tweens, Kamera und Sequences gehen nicht
  verlustfrei mit. VFX-Studio-Konvention vor dem Bau an einer echten Datei prüfen. forge-vfx wird nie geladen.
- **O43 (IDEA):** Später: Binden an `AnimationTrack`-Marker und Importer für Moon-/Eclipse-Event-Daten (rechtliche Lage
  vorher klären); Effekt-Offsets relativ zu Rig-Teilen im Schema vorsehen.
- **O44 (IDEA):** UI-Emitter mit Backend-Adapter: zuerst ImageLabel mit strikten Budgets, später `ParticleEmitter2D`,
  sobald veröffentlicht; Schema an dessen Property-Namen anlehnen.
- **O45 (IDEA):** Optionale Oklab-Interpolation beim Backen von Farbverläufen (zusätzliche RGB-Keypoints), weil die
  Engine linear in RGB interpoliert (Vorbild Effect Designer Suite).

### 4.10 Distribution und Vertrauen

- **O46 (IDEA) ⚑:** Lesbarer, nicht obfuszierter Code, kein Remote-`require`/`loadstring`, keine versteckten Skripte,
  Runtime ohne Seiteneffekte und ohne Attributionspflicht (Lizenz beim Nutzer) → Creator-Store-konform; Updates über den
  Store; Runtime meldet „Effekt braucht Runtime ≥ x.y“ (P19, 2.1.4).
- **O47 (IDEA):** Keine fremde Texturbibliothek bündeln; Asset-IDs im JSON; eigene, rechtlich saubere Starter-Texturen;
  `rbxasset://textures/particles/*` nur als „engine-built-in, Plattformverfügbarkeit ungeprüft“ referenzieren, nie
  kopieren; Upload über `CreateAssetAsync` nur hinter Feature-Detection (nur lokal geladene Plugins).
- **O48 (IDEA):** Übungsbasiertes Onboarding (Vorbild QP2-„Exercises“) mit Presets, die sich als JSON öffnen und ändern
  lassen; API-Doku aus Code und Schema generieren (Lehre aus der Doku-Drift bei QP2).

### 4.11 Abgleich mit den ADRs in `ARCHITECTURE.md`

| ADR | Befund der Recherche | Bewertung |
|---|---|---|
| 1 JSON als einzige Wahrheit | QP2 stille Fehlschläge und fehlende Migration (VERIFIED), VFX-Editor-Attributverlust (VERIFIED), Rojo-JSON-Module verlustbehaftet (VERIFIED) | gestützt |
| 2 Eigene Zeitauswertung | kein Seek in TweenService, Sequenzen nicht tweenbar, Bezier/Spring werfen (VERIFIED/REPORTED) | gestützt |
| 3 Ein Scheduler | QP2 und EasyVFX nutzen laut eigener Doku je eine Schleife; Kritik an Heartbeat pro Objekt (REPORTED) | gestützt (Herstelleraussagen) |
| 4 Anchored + `BulkMoveTo` | Doku: nur bei echtem Engpass; Default-Modus `FireAllEvents` überschreiben | gestützt mit Präzisierung |
| 5 `Part + SpecialMesh` | `MeshId` NotAccessibleSecurity; `MeshType`-Default `Head`; Materialien auf SpecialMesh laut Doku fehlerhaft; `ApplyMesh` synchron als Pool-Alternative | gestützt, verschärft; Neon-Test nötig |
| 6 Dokumente als `StringValue` + CHS | `Script.Source` nicht undo-fähig (REPORTED, Staff) spricht für StringValue; Undo von `StringValue.Value`/`SetAttribute` in einer Recording nur aus alten Threads (REPORTED); Grenze ≤ 199 999 | gestützt, **Studio-Test Pflicht** |
| 7 Workspace-Vorschau primär | ViewportFrame ohne Partikel/Beams/Trails (REPORTED, Juni 2026) | gestützt |
| 8/9 Prozedurale Komponenten, Graph → Zeitplan | keine Per-Partikel-Events (VERIFIED); Unity-Seeds nur für Zufallszahlen | gestützt |
| 10 Lune-Tests | kein `Random`, Texture-Kopplung, Reflection-DB 0.741, alle Properties schreibbar | gestützt, Abweichungsliste nötig (O41) |
| 11 Instanz-`require` | String-Requires mit `./`, `../`, `@self/` wären ebenfalls portabel; Aliases nicht | gestützt (kein Wechsel nötig) |
| 12 Eigenes UI-Toolkit | Memory Leaks und State-Fehler in Fremd-UI eines Konkurrenten (VERIFIED, Changelog) | schwach gestützt (ASSUMPTION) |

Hinweis: `ARCHITECTURE.md` nennt `effects/*.json`; für `syncRules` empfiehlt die Tooling-Notiz die eigene Endung
`*.vfx.json` (IDEA, O37).

---

## 5. Offene Fragen

### 5.1 Pflicht-Tests in Roblox Studio (vor bzw. in Phase 2/3)

1. ⚑ Feuern `Heartbeat`, `PreRender`, `RenderStepped`, `PreSimulation`, `Stepped` für Plugin-Code im **Edit Mode**? Mit
   welchem `dt`, bei minimiertem Studio, offenem Script-Tab und Widget im Hintergrund?
2. ⚑ ChangeHistoryService: Werden `StringValue.Value`, `SetAttribute` und Reparenting mit `Parent = nil` innerhalb
   einer Recording sauber rückgängig gemacht? Ignoriert CHS 0.745 nicht archivierbare Instanzen, auch deren Nachfahren?
   Sieht ein neu geladenes Plugin seine alte Recording (`IsRecordingInProgress`, `FinishRecording("", Cancel)`)? Enthält
   `OnUndo` den `name` oder `displayName`?
3. ⚑ Lösen Delete, Ctrl+Z, Ctrl+D bei fokussiertem Input-Catcher-Frame zusätzlich Studio-Aktionen aus? Feuern
   `PluginAction`-Shortcuts ohne Widget-Fokus?
4. ⚑ Wirkt `ParticleEmitter.TimeScale = 0` im Edit Mode zuverlässig (frühere Bugs)?
5. ⚑ Welche Attachment-Achse spannt die Beam-Breite bei `FaceCamera = false` auf?
6. Welche Texturgrößen und Grid-Formen akzeptieren Flipbooks heute, in welcher Reihenfolge laufen die Frames, und wie sieht
   ein Emitter aus, wenn der Client Flipbooks abschaltet?
7. Akzeptiert `NumberSequence.new` doppelte Keypoint-Zeiten (Stufen)?
8. Rendern Neon und ForceField auf `Part + SpecialMesh` (Sphere, Cylinder, FileMesh) korrekt?
9. Was rendert ein ViewportFrame mit WorldModel im DockWidget (ParticleEmitter, Beam, Trail, Fire/Smoke/Sparkles,
   Lichter, Highlight, Decal, SurfaceAppearance)?
10. Audio-Vorschau: Spielt ein Sound-Klon unter dem eigenen DockWidget, ein vorverdrahteter `AudioPlayer`,
    `PlayLocalSound`?
11. HTTP: Kommt der Berechtigungsdialog für localhost bei lokal installierten bzw. Store-Plugins, auch für `ws://`? Gibt
    es den „Script Injection“-Dialog noch?
12. Feuert `StringValue.Changed` zuverlässig bei Rojo-Live-Updates, und verliert das Plugin bei Rojos
    Instanz-ersetzen-Fallback seine Referenz?
13. Unterscheiden sich `StudioTestService.EditModeActive` und `RunService:IsEdit()` beim Start im Run Mode?
14. Engine-Clamps außerhalb der UI-Bereiche: Size > 10, Squash außerhalb ±3, Rate > 400, `TimeScale` > 1,
    `Beam.Segments`-Maximum, Partikel pro `Emit()`-Aufruf.
15. Kann das aktuelle Properties-Fenster Sequences bei Mehrfachauswahl bearbeiten, und gilt die Size-Kappung 10 noch?
16. Übernehmen Partikel eine explizit gesetzte `AssemblyLinearVelocity` eines verankerten, per CFrame bewegten Ankers
    (`VelocityInheritance`)?
17. Funktionieren `rbxtemp://` und `EditableImage` als Textur von ParticleEmitter, Beam und Trail im Edit Mode?
18. Exakte Drag-/Acceleration-Integration der Engine (für einen „genauen“ Trajektorien-Gizmo).
19. Team Create: Werden nicht archivierbare Vorschau-Objekte in Workspace bzw. Camera zu anderen Mitarbeitern
    repliziert? Erzeugen doppelte Widget- oder Action-IDs nach einem Reload oder im Play-DataModel Konflikte?

### 5.2 Gerätetests (echte Clients, Mobile Low vs. PC Max)

- Skaliert die Engine aktuell `Rate` und `Emit(n)` nach Qualität und Kameradistanz? Wie hoch sind die globalen
  Partikel-Caps? Wie stark reduziert sie Beam-Segments?
- Werden `Emit()`-Aufrufe an Emittern außerhalb des Bildes aufgeschoben oder zurückgesetzt (Desync zwischen Layern)?
- Ist die Trail-Lifetime noch FPS-abhängig?
- Kosten von Highlight + ColorCorrection für 1–3-Frame-Impact-Frames auf Mobile.
- Reale Payload-Kosten typischer ASTRA-Net-Nachrichten im `UnreliableRemoteEvent`.
- Taugen `RenderCPUFrameTime`/`RenderGPUFrameTime` auf Mobile als Auto-Qualitätssignal? Welche Stufe meint „Schatten
  unter 4“? Wirkt `Lighting.PrioritizeLightingQuality` darauf ein?
- Gilt „Glass-Refraktion ab Grafik 8“ noch, und wird `Transparency > 1` weiter akzeptiert?
- Funktioniert `SceneAnalysisService` außerhalb von Studio?
- Sind die `rbxasset://textures/particles/*`-Dateien auf Mobile und Konsole vorhanden?

### 5.3 Produkt- und Marktfragen

- Wie realisiert Arc das (Rückwärts-)Scrubbing der Partikelvorschau? Hat Arc 3D-Beziers?
- Wann und in welcher Form erscheint `ParticleEmitter2D`?
- Status der QP2-Store-Seite, Inhalt des angekündigten „Workspace Manager“ (Timeline?), Format des „Text Based
  AssetSharing“, Funktionsumfang von QP2 Version 1, Herkunft und Lizenz der QP2-Texturen.
- Echte VFX-Studio-Effektdatei prüfen (Attribut-Konvention ist Single-Source); exakte `EmitDuration`-Semantik pro Tool.
- Preis, Lizenz und Update-Stand von ROS; aktuelle Preise und Wartung von VFX Suite, Sine VFX, Phase VFX, Effect
  Designer Suite.
- Stabilität und rechtliche Lage der Eclipse-Event-Datenstruktur und der Moon-`.xsixx`-Saves für einen Importer.
- Benchmark Mesh-Partikel vs. native Emitter (es gibt keinen veröffentlichten); eigene Messung in Phase 6.

### 5.4 Externe Quellen nachprüfen

- Niagara und Sequencer gegen `dev.epicgames.com` (Effect Types/Scalability, Emitter-Vererbung, Life-Cycle-Track).
- After-Effects-Oberfläche gegen `helpx.adobe.com` (Easy-Ease-Defaults, Speed Graph, Shortcuts).
- Blender-Formsemantik der Sockets im Handbuch; gilt die 5.4-alpha-Keymap für die stabile Version?
- Abbildung AE-artiger Speed/Influence-Ease auf ASTRA-Bezier (Prototyp).

### 5.5 Tooling-Fragen

- Welche Edits unterstützt Rojos Two-Way-Sync heute konkret?
- Unterstützt die Engine Require-Aliases, und was macht `ScriptService:ResolveModulePath` genau?
- Wie kodiert `HttpService:JSONEncode` leere Tabellen, `NaN`/`inf` und große Zahlen (Abgleich mit dem ASTRA-Encoder)?
- Größenlimits für `RequestAsync`-Bodies aus Plugins, `WebStreamClient`-Nachrichten und große `TextBox`-Pastes.
- Hat `execute_luau` des Studio-MCP Plugin-Rechte, und kann ein Agent damit gezielt Plugin-Funktionen aufrufen?
- Lädt Studio lokale Plugins neu, wenn die `.rbxmx` im Plugins-Ordner überschrieben wird?
- Gibt es Erfahrungsberichte zu Stabilität und Latenz des Studio-MCP mit Claude Code?

---

## 6. Konsolidierte Quellenliste

Die vollständigen Belegzuordnungen je Aussage stehen in den Notizen unter `docs/research/`. Hier sind die Quellen
dedupliziert und nach Art gruppiert.

### 6.1 Offizielle Roblox-Doku (VERIFIED)

Quelltext unter `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/<Pfad>`
(öffentliche Entsprechung `https://create.roblox.com/docs/<Pfad ohne Endung>`).

- **Effekte und Umgebung:** `effects/particle-emitters.md`, `effects/beams.md`, `effects/trails.md`, `effects/index.md`,
  `effects/highlighting.md`, `effects/light-sources.md`, `environment/global-wind.md`,
  `environment/post-processing-effects.md`
- **Klassen (`reference/engine/classes/`):** `ParticleEmitter`, `Beam`, `Trail`, `Attachment`, `Bone`, `BasePart`,
  `Part`, `MeshPart`, `TriangleMeshPart`, `SpecialMesh`, `FileMesh`, `DataModelMesh`, `Decal`, `Texture`, `Highlight`,
  `Light`, `PointLight`, `SpotLight`, `SurfaceLight`, `Lighting`, `BloomEffect`, `ColorCorrectionEffect`, `PostEffect`,
  `TweenService`, `TweenBase`, `Tween`, `RunService`, `WorldRoot`, `PVInstance`, `Model`, `Workspace`, `Sound`,
  `SoundService`, `AudioPlayer`, `AssetService`, `EditableImage`, `WireframeHandleAdornment`, `Plugin`, `Instance`,
  `DockWidgetPluginGui`, `PluginGui`, `PluginDragEvent`, `PluginToolbar`, `PluginToolbarButton`, `PluginAction`,
  `PluginMenu`, `PluginMouse`, `PluginManager`, `ChangeHistoryService`, `Selection`, `StudioService`, `File`,
  `ScriptEditorService`, `Script`, `ModuleScript`, `ScriptService`, `SerializationService`, `Studio`, `StudioTheme`,
  `StudioTestService`, `InstanceFileSyncService`, `CustomLog`, `GuiObject`, `TextBox`, `InputObject`, `ViewportFrame`,
  `WorldModel`, `CoreGui`, `HttpService`, `WebStreamClient`, `StringValue`, `Stats`, `UserGameSettings`, `DataModel`,
  `RenderSettings`, `SceneAnalysisService`, `Debris`, `ContentProvider`, `RemoteEvent`, `UnreliableRemoteEvent`
  (jeweils `.yaml`)
- **Datentypen (`reference/engine/datatypes/`):** `NumberSequence`, `NumberSequenceKeypoint`, `ColorSequence`,
  `ColorSequenceKeypoint`, `NumberRange`, `Content`, `TweenInfo`, `DockWidgetPluginGuiInfo`, `Random`
- **Enums (`reference/engine/enums/`):** `ParticleEmitterShape`, `ParticleEmitterShapeStyle`, `ParticleEmitterShapeInOut`,
  `ParticleOrientation`, `ParticleFlipbookLayout`, `ParticleFlipbookMode`, `ParticleFlipbookTextureCompatible`,
  `TextureMode`, `NormalId`, `PartType`, `Material`, `MeshType`, `RenderFidelity`, `EasingStyle`, `EasingDirection`,
  `RollOffMode`, `InitialDockState`, `FinishRecordingOperation`, `StudioStyleGuideColor`, `StudioStyleGuideModifier`,
  `QualityLevel`, `SavedQualitySetting`, `BulkMoveMode`, `StepFrequency`, `GraphicsOptimizationMode`
- **Globals:** `reference/engine/globals/LuaGlobals.yaml` (`require`)
- **Studio und Assistant:** `studio/plugins.md`, `studio/build-studio-widgets.md`, `studio/testing-modes.md`,
  `studio/script-editor.md`, `studio/mcp.md`, `studio/setup.md`, `assistant/mcp.md`, `assistant/guide.md`
- **Scripting, Cloud, Projekte:** `scripting/attributes.md`, `scripting/sync.md`, `scripting/events/remote.md`,
  `cloud-services/http-service.md`, `cloud/auth/api-keys.md`, `cloud/guides/usage-place-publishing.md`,
  `reference/cloud/openapi.json`, `projects/collaboration.md`, `projects/assets/index.md`, `projects/external-tools.md`,
  `production/creator-store.md`
- **Parts, Art, UI, Animation:** `parts/index.md`, `parts/materials.md`, `art/modeling/surface-appearance.md`,
  `ui/viewport-frames.md`, `ui/animation.md`, `animation/editor.md`, `animation/curve-editor.md`
- **Performance und Streaming:** `performance-optimization/improve.md`, `performance-optimization/design.md`,
  `performance-optimization/identify.md`, `performance-optimization/test-on-hardware.md`,
  `performance-optimization/scene-analysis.md`, `performance-optimization/microprofiler` (Übersichtsseite),
  `performance-optimization/microprofiler/tag-table.md`, `performance-optimization/microprofiler/task-scheduler.md`,
  `production/analytics/performance.md`, `workspace/streaming/index.md`, `workspace/streaming/techniques.md`
- **Tutorials:** `tutorials/use-case-tutorials/vfx/use-particles-for-explosions.md`,
  `tutorials/use-case-tutorials/vfx/custom-particle-effects.md`, `tutorials/use-case-tutorials/vfx/laser-traps-with-beams.md`,
  `tutorials/curriculums/core/building/create-basic-visual-effects.md`,
  `tutorials/curriculums/artist/work-with-particle-emitters.md`,
  `tutorials/curriculums/environmental-art/optimize-your-experience.md`

### 6.2 Lokale und Roblox-eigene Referenzdaten (VERIFIED)

- `/root/tools/ref/API-Dump.json`, `/root/tools/ref/Full-API-Dump.json`, `/root/tools/ref/globalTypes.d.luau`,
  `/root/tools/ref/version.txt` (Engine 0.745.0.7451137)
- Roblox-Client-Tracker-Mirror (Dateien von Roblox, Branch `roblox`, 0.745.0.7451137):
  https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml ·
  https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/rbxManifest.txt ·
  https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/rbxPkgManifest.txt ·
  https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/version.txt
- Lokale Tests: Rojo 7.7.1 (`build`, `syncback`, `serve`, `sourcemap`, `upload --help`), Lune 0.11.1 (`lune setup`-Typen,
  Tests zu roblox/net/serde/require), selene 0.31.0, StyLua 2.6.0

### 6.3 Produkt-eigene Quellen (VERIFIED für die jeweilige Selbstauskunft)

- QP2: https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2/main/README.md ·
  https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2-Module/main/README.md ·
  https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2-Module/main/LICENSE.md
- VFX Editor: https://raw.githubusercontent.com/VirtualButFake/vfx-editor/main/README.md ·
  https://raw.githubusercontent.com/VirtualButFake/vfx-editor/main/CHANGELOG.md ·
  https://raw.githubusercontent.com/wiki/VirtualButFake/vfx-editor/Home.md
- VFX Forge: https://raw.githubusercontent.com/zilibobi/forge-vfx/main/README.md ·
  https://registry.npmjs.org/@zilibobi/forge-vfx (Tarball 2.4.0: `out/index.d.ts`, `LICENSE`)
- EasyVFX: https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/README.md · …/docs/agentic-loop.md ·
  …/docs/eclipse-animator.md · …/docs/vfx-studio-analysis.md · …/CHANGELOG.md · …/LICENSE
  (Präfix `https://raw.githubusercontent.com/VuxSussy/EasyVFX/main`)
- VFX Studio (Doku-Platzhalter, als Beleg unbrauchbar):
  https://raw.githubusercontent.com/sytranom/vfx-studio-docs/gh-pages/docs/reference-advanced.html
- Lumina: https://raw.githubusercontent.com/Mqxsyy/Lumina/main/README.md · …/package.json · …/LICENSE ·
  https://raw.githubusercontent.com/Mqxsyy/LuminaDocs/main/sidebars.ts
- VortexFX: https://raw.githubusercontent.com/FancyDucc/3D-Particle-System/main/README.md
- Lightning Beams (Port): https://registry.npmjs.org/@rbxts/lightning-beams
- Moon-Exporter: https://raw.githubusercontent.com/GamesGG0/Moon-Animator-VFX-Exporter/main/README.md ·
  https://raw.githubusercontent.com/GuHamYaiXD/MoonVFXComplier/main/README.md
- Helfer und UI-Partikel: https://raw.githubusercontent.com/J1ck/roblox-particle-util/main/README.md ·
  https://raw.githubusercontent.com/Synitx/2D-Emitter-2/main/README.md ·
  https://raw.githubusercontent.com/Novaly-Studios/UIParticle/main/README.md ·
  https://raw.githubusercontent.com/themwsama/Particle-UI-Module/main/README.md ·
  https://raw.githubusercontent.com/joeldesante/rParticle/master/README.md
- Arc-MCP-Erweiterung (Dritter): https://raw.githubusercontent.com/Joojjuuk/plugin-studio/main/README.md
- Rojo-Plugin (nur gelesen): https://raw.githubusercontent.com/rojo-rbx/rojo/master/plugin/src/Config.lua ·
  https://raw.githubusercontent.com/rojo-rbx/rojo/master/plugin/src/ApiContext.lua

### 6.4 Tooling (VERIFIED)

- Rojo: https://raw.githubusercontent.com/rojo-rbx/rojo/master/README.md ·
  https://raw.githubusercontent.com/rojo-rbx/rojo/master/CHANGELOG.md ·
  https://raw.githubusercontent.com/rojo-rbx/rojo.space/master/docs/sync-details.md ·
  https://raw.githubusercontent.com/rojo-rbx/rojo.space/master/docs/project-format.md ·
  https://raw.githubusercontent.com/rojo-rbx/rojo.space/master/docs/properties.md ·
  https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/README.md · https://dom.rojo.space/attributes.html (REPORTED)
- Lune: https://raw.githubusercontent.com/lune-org/lune/main/README.md ·
  https://raw.githubusercontent.com/lune-org/lune/main/CHANGELOG.md
- Luau-RFCs: https://raw.githubusercontent.com/luau-lang/rfcs/master/docs/new-require-by-string-semantics.md ·
  …/require-by-string-aliases.md · …/abstract-module-paths-and-init-dot-luau.md · …/config-luauconfig.md
- MCP: https://raw.githubusercontent.com/Roblox/studio-rust-mcp-server/main/README.md
- Toolchain und Tests: https://raw.githubusercontent.com/rojo-rbx/rokit/main/README.md (+ CHANGELOG) ·
  https://raw.githubusercontent.com/LPGhatguy/aftman/main/README.md ·
  https://raw.githubusercontent.com/Roblox/foreman/main/README.md ·
  https://raw.githubusercontent.com/UpliftGames/wally/main/README.md (+ CHANGELOG, Cargo.toml) ·
  https://raw.githubusercontent.com/pesde-pkg/pesde/main/README.md ·
  https://raw.githubusercontent.com/seaofvoices/darklua/main/README.md ·
  https://raw.githubusercontent.com/Kampfkarren/selene/main/docs/src/roblox.md (+ CHANGELOG) ·
  https://raw.githubusercontent.com/JohnnyMorganz/StyLua/main/CHANGELOG.md ·
  https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/README.md ·
  https://raw.githubusercontent.com/Roblox/jest-roblox/master/README.md (+ CHANGELOG) ·
  https://raw.githubusercontent.com/jsdotlua/jest-lua/main/README.md ·
  https://raw.githubusercontent.com/Roblox/testez/master/README.md (+ CHANGELOG) ·
  https://raw.githubusercontent.com/rojo-rbx/run-in-roblox/master/README.md (+ Cargo.toml)

### 6.5 Profi-Tools

- **Unity VFX Graph (VERIFIED):** Basis
  `https://raw.githubusercontent.com/Unity-Technologies/Graphics/master/Packages/com.unity.visualeffectgraph/Documentation~/`
  mit TableOfContents.md, GraphLogicAndPhilosophy.md, Systems.md, Contexts.md, Context-Spawn.md, Context-GPUEvent.md,
  Context-Event.md, Context-Initialize.md, Context-Update.md, Blocks.md, Block-SetAttributeFromCurve.md, Block-Burst.md,
  Block-Trigger-Event.md, Operators.md, Operator-RandomNumber.md, Properties.md, Events.md, Attributes.md, Subgraph.md,
  Blackboard.md, StickyNotes.md, Shortcuts.md, VisualEffectGraphWindow.md, VisualEffectComponent.md, ComponentAPI.md,
  VisualEffectGraphAsset.md, Templates-window.md, PropertyBinders.md, EventBinders.md, OutputEventHandlers.md,
  Timeline.md, performance-debug-panel.md, visual-effect-bounds.md, Instancing.md, VisualEffectProjectSettings.md,
  VisualEffectPreferences.md, VisualEffectGraphTypeReference.md, GettingStarted.md, whats-new-17.md.
  REPORTED: https://issuetracker.unity3d.com/issues/vfx-graph-timeline-vfx-activation-events-can-get-skipped-if-their-duration-is-below-0-dot-3-sec
- **Blender (VERIFIED, Quelltext `main` = 5.4 alpha; Vergleich mit 4.2/4.5/5.0-Release-Branches):**
  https://raw.githubusercontent.com/blender/blender/main/scripts/presets/keyconfig/keymap_data/blender_default.py ·
  …/source/blender/makesrna/intern/rna_node_socket.cc · …/rna_node_tree_interface.cc · …/rna_nodetree.cc ·
  …/source/blender/editors/space_node/drawnode.cc · …/node_relationships.cc · …/node_edit.cc · …/node_group.cc ·
  …/node_add.cc · …/node_ops.cc · …/source/blender/editors/screen/screen_ops.cc ·
  …/release/datafiles/userdef/userdef_default_theme.c · …/source/blender/blenkernel/BKE_blender_version.h
  (Präfix `https://raw.githubusercontent.com/blender/blender/main`).
  REPORTED: https://developer.blender.org/docs/release_notes/5.0/animation_rigging/ ·
  https://projects.blender.org/blender/blender/pulls/140301
- **After Effects (REPORTED, Community-Scripting-Guide):**
  https://raw.githubusercontent.com/docsforadobe/after-effects-scripting-guide/master/mkdocs.yml ·
  …/docs/property/property.md · …/docs/other/keyframeease.md · …/docs/other/markervalue.md · …/docs/item/compitem.md ·
  …/docs/layer/layer.md · …/docs/layer/avlayer.md (Präfix
  `https://raw.githubusercontent.com/docsforadobe/after-effects-scripting-guide/master`) ·
  https://ae-scripting.docsforadobe.dev/other/keyframeease/ ·
  https://community.adobe.com/t5/after-effects-discussions/how-to-copy-and-paste-keyframeease-to-another-property/m-p/13123629
- **Unreal Niagara und Sequencer:** keine Quelle erreichbar (ASSUMPTION, Modellwissen).

### 6.6 Creator Store, Hersteller-Websites, X, YouTube (REPORTED, nur Such-Snippets)

- Creator Store / Library: https://create.roblox.com/store/asset/8813198599 ·
  https://www.roblox.com/library/8813198599/ROS-Particle-Editor ·
  https://www.roblox.com/library/8133535339/BezierSequence ·
  https://create.roblox.com/store/asset/78969824830970/Qwinkles-Particles-2/reviews ·
  https://create.roblox.com/store/asset/14328968969/VFX-Suite · https://create.roblox.com/store/asset/18800449515/VFX-Editor ·
  https://create.roblox.com/store/asset/133927382668067/VFX-Forge · https://create.roblox.com/store/asset/135581141962270/VFX-Studio ·
  https://create.roblox.com/store/asset/118257542877059/Arc · https://create.roblox.com/store/asset/4725618216/Moon-Animator-2 ·
  https://create.roblox.com/store/asset/86116556258301/Eclipse-Animator · https://create.roblox.com/store/asset/78798609925417/Phase-VFX
- QP2-Doku und Verkauf: https://www.qwinkleparticles2.com/ (u. a. /setup/install/, /guide/exercises/01-first-emission/,
  /guide/exercises/17-fire-the-explosion-with-a-key/, /guide/hidden-depths/native-editing/,
  /guide/hidden-depths/why-meshes-win/, /guide/particiliary/part/, /guide/particiliary/model/, /guide/particiliary/trail/,
  /guide/particiliary/trail-emitter/, /guide/particiliary/highlight/, /guide/toolbench/inventory/,
  /reference/properties/particle/, /faq/emitter-not-emitting/, /es/guide/particiliary/bloom/,
  /es/guide/particiliary/camera-shake/) · https://qp2-docs.pages.dev/ (u. a. /setup/install/, /guide/what-just-happened/,
  /guide/hidden-depths/nesting/, /faq/emitter-not-emitting/, /faq/type-differences/, /guide/from-script/emission/,
  /reference/properties/particle/) · https://qwinkletee.gumroad.com/l/qwinklesparticles2 ·
  https://github.com/QwinkleTee/Qwinkles-Particles-2 · https://github.com/QwinkleTee
- Weitere Hersteller-Seiten: https://zilibobi.itch.io/vfx-forge · https://zilibobi.github.io/forge-docs/effects/particle ·
  https://sytranom.github.io/vfx-studio-docs/ · https://phase-doc.vercel.app/ · https://sinevfx.xyz/ ·
  https://vfxer.gitbook.io/plugin/attributes · https://vfxer.gitbook.io/plugin/module ·
  https://themattempire.gitbook.io/documentation/archive/roblox/visual-effects-vfx/particle-emitters ·
  https://robloxapi.github.io/ref/class/AssetService.html · https://fastflagforge.github.io/Docs/fast-flags/graphical-settings (inoffiziell) ·
  https://github.com/Sleitnick/RbxCameraShaker
- X: https://x.com/qwinkletee · https://x.com/qwinkletee/status/1965100364157636654 ·
  https://x.com/qwinkletee/status/2040458438451634513 · https://x.com/qwinkletee/status/2040781351528570958 ·
  https://x.com/doublecats1/status/2052351771587313711 · https://x.com/primevoxel/status/1694203050347667935
- YouTube: https://www.youtube.com/watch?v=kUNxF9gmAMs · https://www.youtube.com/watch?v=TrFiKIr7K-4 ·
  https://www.youtube.com/watch?v=3vZBg-YnV-c · https://www.youtube.com/watch?v=nAXbqUM1feo ·
  https://www.youtube.com/watch?v=qxhShY5WJrw · https://www.youtube.com/watch?v=zlKdwujvP2A
  (Zusammenfassung: https://youtubesummary.com/summary/zlKdwujvP2A)

### 6.7 DevForum (REPORTED, nur Such-Snippets)

Alle unter `https://devforum.roblox.com/t/…`.

- **Produkt-Threads:** [the-worlds-best-particle-editor-plugin-99-sure/1668424](https://devforum.roblox.com/t/the-worlds-best-particle-editor-plugin-99-sure/1668424)
  (inkl. [?page=2](https://devforum.roblox.com/t/the-worlds-best-particle-editor-plugin-99-sure/1668424?page=2),
  [/2](https://devforum.roblox.com/t/the-worlds-best-particle-editor-plugin-99-sure/1668424/2)) ·
  [introducing-the-vfx-suite-plugin/2545686](https://devforum.roblox.com/t/introducing-the-vfx-suite-plugin/2545686) ·
  [vfx-editor-all-your-vfx-needs-in-one/3103467](https://devforum.roblox.com/t/vfx-editor-all-your-vfx-needs-in-one/3103467) ·
  [plugin-vfx-forge-an-advanced-custom-vfx-system/3867553](https://devforum.roblox.com/t/plugin-vfx-forge-an-advanced-custom-vfx-system/3867553) ·
  [arc-a-vfx-animation-plugin/4903133](https://devforum.roblox.com/t/arc-a-vfx-animation-plugin/4903133) ·
  [getting-started-with-moon-animator-2-unofficial/476330](https://devforum.roblox.com/t/getting-started-with-moon-animator-2-unofficial/476330) ·
  [motion-151-—-timeline-editor-animator/4274872](https://devforum.roblox.com/t/motion-151-%E2%80%94-timeline-editor-animator/4274872) ·
  [visulie-…-effects-suite/3582453](https://devforum.roblox.com/t/visulie-%E2%94%80-a-novel-all-purpose-animation-data-and-effects-suite/3582453) ·
  [plugin-sine-vfx-a-vfx-plugin-for-roblox-studio/4803771](https://devforum.roblox.com/t/plugin-sine-vfx-a-vfx-plugin-for-roblox-studio/4803771) ·
  [effect-designer-suite-…/4754553](https://devforum.roblox.com/t/effect-designer-suite-%E2%80%94-vfx-tooling-assets-and-more/4754553) ·
  [beziers-advanced-modular-vfx-plugin-10000-assets-add-ons/4180222](https://devforum.roblox.com/t/beziers-advanced-modular-vfx-plugin-10000-assets-add-ons/4180222) ·
  [3547230](https://devforum.roblox.com/t/3547230) ·
  [vfx-scripter-pro-…/2961973](https://devforum.roblox.com/t/vfx-scripter-pro-%E2%80%94-an-essential-plugin-for-vfx-scripters/2961973) ·
  [steakparticles-plugin-for-creating-vfx-and-particle-emitters/2908779](https://devforum.roblox.com/t/steakparticles-plugin-for-creating-vfx-and-particle-emitters/2908779) ·
  [update-020-lumina-a-custom-particle-system/2963557](https://devforum.roblox.com/t/update-020-lumina-a-custom-particle-system/2963557) ·
  [vortexfx-v106-…/3131414](https://devforum.roblox.com/t/vortexfx-v106-a-3d-particle-system-for-all-your-3d-particle-needs/3131414)
  (und [v1065 ?page=4](https://devforum.roblox.com/t/vortexfx-v1065-a-3d-particle-system-for-all-your-3d-particle-needs/3131414?page=4)) ·
  [new-particle-system-flare-craft/2539746](https://devforum.roblox.com/t/new-particle-system-flare-craft/2539746) ·
  [emitter2d-…/3742009](https://devforum.roblox.com/t/emitter2d-convert-any-particleemitter-to-2d-with-the-click-of-a-button/3742009) ·
  [uiparticles-…/3256357](https://devforum.roblox.com/t/uiparticles-a-plugin-and-module-for-all-your-ui-particle-needs/3256357) ·
  [plugin-2demitter-v2-basic-ui-particle-emitter/2156359](https://devforum.roblox.com/t/plugin-2demitter-v2-basic-ui-particle-emitter/2156359) ·
  [effect-v11-lightning-beams-…/843534](https://devforum.roblox.com/t/effect-v11-lightning-beams-seamless-smooth-and-procedurally-animated-with-beam-like-properties/843534) ·
  [dear-vfx-makers-i-present-to-you-jads-emit-plugin/1986838](https://devforum.roblox.com/t/dear-vfx-makers-i-present-to-you-jads-emit-plugin/1986838) ·
  [shiftys-particle-emitter-plugin/2661214](https://devforum.roblox.com/t/shiftys-particle-emitter-plugin/2661214) ·
  [scale-particleemitters-uniformly-fast-particleemitter-scaler-plugin/2792643](https://devforum.roblox.com/t/scale-particleemitters-uniformly-fast-particleemitter-scaler-plugin/2792643) ·
  [smoothsequence-graph-…/3044286](https://devforum.roblox.com/t/smoothsequence-graph-the-easiest-way-to-edit-numbersequences/3044286) ·
  [cse-pro-supercharged-colorsequence-editor/2060438](https://devforum.roblox.com/t/cse-pro-supercharged-colorsequence-editor/2060438) ·
  [vfx-difference-in-rosparticle-and-emitparticle/2441406](https://devforum.roblox.com/t/vfx-difference-in-rosparticle-and-emitparticle/2441406) ·
  [Profil roasted_shrimps](https://devforum.roblox.com/u/roasted_shrimps) · [Tag particleemitter](https://devforum.roblox.com/tag/particleemitter)
- **Studio-Sequence-Editoren und Feature-Requests:** [2083516](https://devforum.roblox.com/t/unable-to-mass-edit-sequence-properties-ie-from-particles/2083516) ·
  [23034](https://devforum.roblox.com/t/particle-editing-bug-on-multiple-particleemitters/23034) ·
  [1071269](https://devforum.roblox.com/t/multiple-numbersequencecolorsequence-cant-be-edited-through-the-properties-panel/1071269) ·
  [425043](https://devforum.roblox.com/t/let-us-edit-multiple-sequence-properties-at-a-time/425043) ·
  [26161](https://devforum.roblox.com/t/particle-size-cant-be-animated-above-10-despite-size-limit-being-200/26161) ·
  [79122](https://devforum.roblox.com/t/increase-particleemitter-size-limit/79122) ·
  [983469](https://devforum.roblox.com/t/is-there-an-easier-way-to-make-a-size-sequence-goal-higher-than-10/983469) ·
  [3224754](https://devforum.roblox.com/t/curve-editor-widget-needs-some-ux-improvements/3224754) ·
  [188572](https://devforum.roblox.com/t/increase-or-remove-the-numbersequence-keypoint-limit/188572) ·
  [2795691](https://devforum.roblox.com/t/-/2795691) · [3774862](https://devforum.roblox.com/t/3774862) ·
  [3356273](https://devforum.roblox.com/t/simplified-bezier-curve-editor-mode-for-number-sequence-editing/3356273) ·
  [1920538](https://devforum.roblox.com/t/allow-plugins-to-use-value-editorspickers/1920538) ·
  [2625485](https://devforum.roblox.com/t/separate-curve-editor-detached-from-animation-editor/2625485) ·
  [876765](https://devforum.roblox.com/t/how-does-robloxs-particle-emitter-drag-affect-the-acceleration-of-the-particle-is-there-a-way-to-trace-the-path/876765) ·
  [1506337](https://devforum.roblox.com/t/particleemitter-size-property-number-sequence-has-max-of-1/1506337)
- **Partikel, Flipbooks, Beams, Trails:** [34752](https://devforum.roblox.com/t/particle-emitters-must-yield-after-being-parented-before-using-emit/34752) ·
  [2888715](https://devforum.roblox.com/t/particles-do-not-emit-in-a-newly-generated-part/2888715) ·
  [3325717](https://devforum.roblox.com/t/issues-with-particleemitteremit/3325717) ·
  [2221218](https://devforum.roblox.com/t/particleemitters-timescale-does-not-visibly-change-in-studio/2221218) ·
  [2720182](https://devforum.roblox.com/t/particle-timescale-is-broken/2720182) ·
  [2824385](https://devforum.roblox.com/t/particles-disappear-when-adjusting-particleemittertimescale/2824385) ·
  [2029388](https://devforum.roblox.com/t/particles’-flipbook-release/2029388) ·
  [1718023](https://devforum.roblox.com/t/animated-particles-with-the-particle-flipbooks-beta/1718023) ·
  [4005128](https://devforum.roblox.com/t/client-beta-optimize-your-particle-animations-with-custom-flipbook-layouts/4005128) ·
  [3118761](https://devforum.roblox.com/t/flipbook-only-supports-particle-textures-of-sizes-in-replicatedstorage/3118761) ·
  [1679078](https://devforum.roblox.com/t/why-is-the-max-image-resolution-1024x1024/1679078) ·
  [1241979](https://devforum.roblox.com/t/graphics-quality-lowering-particle-emission-rates/1241979) ·
  [474762](https://devforum.roblox.com/t/a-way-to-make-particleemitter-rate-ignore-graphics-quality/474762) ·
  [2159584](https://devforum.roblox.com/t/particle-emitter-limit-on-low-graphics-is-impacting-my-game/2159584) ·
  [1585054](https://devforum.roblox.com/t/why-do-they-partially-start-disappearing-when-i-use-a-lot-of-particle-emitter/1585054) ·
  [2426888](https://devforum.roblox.com/t/bypassing-forced-beam-lod/2426888) ·
  [2939171](https://devforum.roblox.com/t/beam-optimization-is-wronglypoorly-implemented/2939171) ·
  [1732819](https://devforum.roblox.com/t/beams-effects-gets-reduced-at-lower-graphics/1732819) ·
  [82214](https://devforum.roblox.com/t/being-able-to-force-the-amount-of-segments-or-lod-for-beams/82214) ·
  [2225384](https://devforum.roblox.com/t/2225384) ·
  [3145864](https://devforum.roblox.com/t/beams-and-trails-dont-show-up/3145864) ·
  [3146228](https://devforum.roblox.com/t/trails-not-visible-not-working-when-in-roblox-studio/3146228) ·
  [2613978](https://devforum.roblox.com/t/trails-do-not-render-properly-if-rotated-about-an-origin/2613978) ·
  [1853349](https://devforum.roblox.com/t/fast-moving-trails-do-not-render/1853349) ·
  [3296080](https://devforum.roblox.com/t/is-it-possible-to-make-a-trail-longer-than-1-stud/3296080) ·
  [821708](https://devforum.roblox.com/t/trail-lifetime-is-tied-to-fps/821708) ·
  [2784082](https://devforum.roblox.com/t/creating-longer-trails-w-parts-beams/2784082) ·
  [3076533](https://devforum.roblox.com/t/how-to-make-a-beam-always-straight/3076533) ·
  [3323908](https://devforum.roblox.com/t/how-would-i-stop-beam-orientation-with-parts/3323908) ·
  [95781](https://devforum.roblox.com/t/why-do-particle-emitters-appear-differently-in-studio-than-when-testing/95781) ·
  [2719243](https://devforum.roblox.com/t/particles-in-studio-rely-on-fps/2719243) ·
  [3181609](https://devforum.roblox.com/t/particles-have-a-delay-when-enabling/3181609) ·
  [3792199](https://devforum.roblox.com/t/particleswedges-being-weird/3792199) ·
  [1023366](https://devforum.roblox.com/t/velocityinheritance-overshoots/1023366) ·
  [188745](https://devforum.roblox.com/t/188745) · [1757317](https://devforum.roblox.com/t/1757317) ·
  [3550728](https://devforum.roblox.com/t/3550728) ·
  [3225681](https://devforum.roblox.com/t/studio-beta-major-updates-to-in-experience-mesh-image-apis/3225681) ·
  [219471](https://devforum.roblox.com/t/a-current-explanation-of-normal-identities-and-security-tags/219471) ·
  [2269097](https://devforum.roblox.com/t/2269097)
- **Geometrie, Licht, Tween, Audio:** [474500](https://devforum.roblox.com/t/plugins-and-command-bar-can-no-longer-use-tweenservice-in-studio-edit-mode/474500) ·
  [148063](https://devforum.roblox.com/t/tweenservicecreate-property-named-transparency-on-object-beam-is-not-a-data-type-that-can-be-tweened/148063) ·
  [1240924](https://devforum.roblox.com/t/tweeninglerping-beam-sequence-properties/1240924) ·
  [1759898](https://devforum.roblox.com/t/cannot-tween-transparency-due-to-type-mismatch/1759898) ·
  [1214259](https://devforum.roblox.com/t/1214259) · [2035448](https://devforum.roblox.com/t/2035448) ·
  [3954367](https://devforum.roblox.com/t/extended-light-ranges-doubling-the-limit-to-120/3954367) ·
  [68336](https://devforum.roblox.com/t/increase-range-limit-of-lights/68336) ·
  [4061534](https://devforum.roblox.com/t/lights-camera-more-highlights/4061534) ·
  [4071175](https://devforum.roblox.com/t/weekly-recap-november-10-14-2025/4071175) ·
  [3306176](https://devforum.roblox.com/t/the-current-thread-cannot-write-meshid-lacking-capability-notaccessible/3306176/3) ·
  [140332](https://devforum.roblox.com/t/modify-meshpartmeshid-through-pluginscommand-bar/140332) ·
  [2848207](https://devforum.roblox.com/t/createmeshpartasync-doesnt-work/2848207) ·
  [3798571](https://devforum.roblox.com/t/how-to-allow-players-to-create-mesh-parts-without-causing-an-error/3798571) ·
  [25580](https://devforum.roblox.com/t/renderstep-part-resize-cframe-performance-is-kill/25580) ·
  [946141](https://devforum.roblox.com/t/resizing-baseparts-is-an-incredibly-expensive-operation/946141) ·
  [3771329](https://devforum.roblox.com/t/why-legacy-meshes-are-still-useful-in-2025/3771329) ·
  [294943](https://devforum.roblox.com/t/neon-material-issues/294943) ·
  [278140](https://devforum.roblox.com/t/trying-to-get-voxel-neon-to-replicate-legacy-neon/278140) ·
  [3041374](https://devforum.roblox.com/t/how-forcefield-texture-animation-works/3041374) ·
  [423438](https://devforum.roblox.com/t/how-to-use-the-new-forcefield-material/423438) ·
  [301951](https://devforum.roblox.com/t/meshpartmaterial-forcefield-unintended-behaviours/301951) ·
  [1927104](https://devforum.roblox.com/t/soundserviceplaylocalsound-does-not-work-with-plugins/1927104) ·
  [2723419](https://devforum.roblox.com/t/play-sound-from-plugin-during-edit-mode-similar-to-properties-panel/2723419) ·
  [321507](https://devforum.roblox.com/t/how-would-you-go-about-playing-stopping-audio-in-edit-mode/321507) ·
  [4538689](https://devforum.roblox.com/t/audioplayer-not-playing-sound-in-studio/4538689) ·
  [3959457](https://devforum.roblox.com/t/allow-audioplayer-previews-to-play-without-a-connected-output-instance/3959457) ·
  [2706107](https://devforum.roblox.com/t/plugins-should-not-require-a-dock-widget-to-play-sounds/2706107) ·
  [3579146](https://devforum.roblox.com/t/plugins-cant-play-sounds-without-runservicerun/3579146) ·
  [1598720](https://devforum.roblox.com/t/is-there-a-way-to-play-a-sound-using-a-plugin/1598720)
- **Studio-Plugin-Verhalten:** [4257585](https://devforum.roblox.com/t/psa-several-common-yielding-methods-have-been-renamed/4257585) ·
  [252266](https://devforum.roblox.com/t/particleemitters-in-viewportframes/252266) ·
  [2133446](https://devforum.roblox.com/t/trail-in-a-viewport/2133446) ·
  [599553](https://devforum.roblox.com/t/particles-in-viewport-frame/599553) ·
  [3151410](https://devforum.roblox.com/t/how-to-workaround-beams-not-showing-on-viewportframes/3151410) ·
  [2226548](https://devforum.roblox.com/t/2226548) ·
  [4706068](https://devforum.roblox.com/t/add-support-for-particle-emitters-in-viewportframes/4706068) ·
  [493269](https://devforum.roblox.com/t/introducing-plugin-http-permissions/493269) ·
  [877312](https://devforum.roblox.com/t/introducing-plugin-script-modification-permissions/877312) ·
  [1496085](https://devforum.roblox.com/t/how-to-access-localhost-using-httpservice-in-roblox-studio/1496085) ·
  [4021932](https://devforum.roblox.com/t/websockets-support-in-studio-is-now-available/4021932) ·
  [11953](https://devforum.roblox.com/t/archivable-and-changehistoryservice/11953) ·
  [311724](https://devforum.roblox.com/t/problems-with-plugins-selection-and-changehistoryservice/311724) ·
  [2179861](https://devforum.roblox.com/t/how-to-block-something-from-being-affected-by-undoredo/2179861) ·
  [4108638](https://devforum.roblox.com/t/studio-doesnt-clean-up-changehistoryservice-recordings-for-unloaded-plugins/4108638) ·
  [2944637](https://devforum.roblox.com/t/plugin-is-always-recording/2944637) ·
  [2512500](https://devforum.roblox.com/t/2512500) ·
  [2821409](https://devforum.roblox.com/t/undoredo-yielding-unexpected-results-toward-plugin-actions/2821409) ·
  [4590702](https://devforum.roblox.com/t/changes-to-luasourcecontainersource-are-not-captured-by-changehistoryservice/4590702) ·
  [3479165](https://devforum.roblox.com/t/using-destroy-with-changehistoryservice-for-a-plugin/3479165) ·
  [549497](https://devforum.roblox.com/t/plugin-how-would-i-destroy-something-that-can-be-undo-without-using-instancedestroy/549497) ·
  [473720](https://devforum.roblox.com/t/changehistoryservice-does-not-undo-or-redo-changes-made-to-textlabeltext-textboxtext-or-textbuttontext/473720) ·
  [1343162](https://devforum.roblox.com/t/properties-widget-attributes-behave-badly-with-changehistoryservice/1343162) ·
  [1549608](https://devforum.roblox.com/t/mouse-events-do-not-fire-when-a-mouse-is-on-the-plugin-widget/1549608) ·
  [479597](https://devforum.roblox.com/t/plugins-need-a-way-to-listen-to-app-input/479597) ·
  [266552](https://devforum.roblox.com/t/the-ability-to-capture-textbox-focus-in-pluginguis/266552) ·
  [3484130](https://devforum.roblox.com/t/plugin-widget-docking-pain-points/3484130) ·
  [1095186](https://devforum.roblox.com/t/renderstepped-doesnt-fire-when-minimized-or-script-tab-open/1095186) ·
  [1064071](https://devforum.roblox.com/t/pluginunloading-not-firing-when-closing-place/1064071) ·
  [3438378](https://devforum.roblox.com/t/camera-instances-do-not-save-when-team-create-is-enabled/3438378) ·
  [154621](https://devforum.roblox.com/t/plugin-how-do-i-prevent-it-running-when-testing-a-game-in-studio/154621) ·
  [1627560](https://devforum.roblox.com/t/in-run-mode-plugins-are-now-started-before-runserviceisrunning-returns-true/1627560) ·
  [227797](https://devforum.roblox.com/t/string-too-long-trying-to-edit-source-of-script/227797) ·
  [23520](https://devforum.roblox.com/t/remove-string-size-limit-for-scriptsource-in-plugins/23520) ·
  [3176649](https://devforum.roblox.com/t/looking-for-way-to-enable-rojo-two-way-sync/3176649) ·
  [3707071](https://devforum.roblox.com/t/3707071)
- **Performance, Qualität, Netzwerk:** [4834736](https://devforum.roblox.com/t/particle-emitters-no-longer-change-rate-with-graphics-quality/4834736) ·
  [2657543](https://devforum.roblox.com/t/graphics-quality-affects-particle-emitters/2657543) ·
  [2804870](https://devforum.roblox.com/t/how-to-optimize-vfx-and-retain-quality-at-low-graphics/2804870) ·
  [2446042](https://devforum.roblox.com/t/bypassing-particle-lod-rate-throttle/2446042) ·
  [339946](https://devforum.roblox.com/t/particlefix-steady-particle-emission-rate/339946) ·
  [106704](https://devforum.roblox.com/t/106704) ·
  [3547121](https://devforum.roblox.com/t/improve-the-performance-of-particleemitters/3547121) ·
  [2543010](https://devforum.roblox.com/t/particleemitteremit-causes-huge-lag-spikes-when-camera-is-close-to-particleemitter/2543010) ·
  [3051577](https://devforum.roblox.com/t/insane-gpu-utulization-issue-when-camera-is-inside-or-player-is-near-particle-effects/3051577) ·
  [2718982](https://devforum.roblox.com/t/significant-delay-on-displaying-particle-effects-even-after-first-load-and-on-repeated-reuse/2718982) ·
  [246641](https://devforum.roblox.com/t/partcache-for-all-your-quick-part-creation-needs/246641) ·
  [518433](https://devforum.roblox.com/t/part-pooling-increase-performance-with-many-parts/518433) ·
  [3104112](https://devforum.roblox.com/t/objectcache-a-modern-blazing-fast-model-and-part-cache/3104112) ·
  [3952399](https://devforum.roblox.com/t/genericpool-high-performance-instance-pooling-update-11/3952399) ·
  [1278502](https://devforum.roblox.com/t/bulkmoveto-vs-normal-cframe-ing/1278502) ·
  [3281168](https://devforum.roblox.com/t/how-we-are-developing-an-rts-game-with-good-performance-for-more-than-200-units/3281168) ·
  [2997135](https://devforum.roblox.com/t/hello-ive-been-wondering-if-its-better-to-use-debrisadditem-or-taskdelay/2997135) ·
  [2184366](https://devforum.roblox.com/t/debrisgobbler-a-much-more-performant-alternative-to-debrisservice/2184366) ·
  [1789487](https://devforum.roblox.com/t/client-replication-101-the-guide-to-replicating-effects-to-clients/1789487) ·
  [2503157](https://devforum.roblox.com/t/need-help-on-client-sided-replication-for-vfx/2503157) ·
  [4749010](https://devforum.roblox.com/t/how-should-i-prevent-exploiters-spamming-my-remoteevent-for-vfx-replication/4749010) ·
  [2724155](https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155) ·
  [3038324](https://devforum.roblox.com/t/what-are-real-limits-of-data-being-sent-when-using-unreliableremoteevent/3038324) ·
  [3048788](https://devforum.roblox.com/t/incorrect-size-of-data-being-sent-limit-specified-when-using-unreliableremoteevent/3048788) ·
  [3072430](https://devforum.roblox.com/t/unreliable-remote-events-for-visuals/3072430) ·
  [580567](https://devforum.roblox.com/t/does-the-50kbps-data-limit-only-apply-to-remote-events-or-also-server-side-object-creation/580567) ·
  [2873609](https://devforum.roblox.com/t/remote-limits-per-remote-or-overall-whered-the-limit-even-come-from/2873609) ·
  [3177820](https://devforum.roblox.com/t/part-is-null-on-the-client/3177820) ·
  [3395374](https://devforum.roblox.com/t/hitbox-supposedly-doesnt-exist-when-sent-to-the-client/3395374) ·
  [3875739](https://devforum.roblox.com/t/severe-fps-drops-due-to-aggressive-shadow-recalculations-during-object-movementappearance/3875739) ·
  [1439704](https://devforum.roblox.com/t/very-poor-performance-with-future-lighting-technology/1439704) ·
  [2719633](https://devforum.roblox.com/t/need-a-way-to-detect-effective-graphics-level/2719633) ·
  [2947801](https://devforum.roblox.com/t/ability-to-query-the-savedqualitylevel-when-its-set-to-auto/2947801) ·
  [81935](https://devforum.roblox.com/t/how-would-i-read-the-localplayers-current-graphics-level-and-detect-when-it-is-changed/81935) ·
  [101291](https://devforum.roblox.com/t/how-do-you-read-what-quality-settings-a-player-has-set-if-they-have-automatic-on/101291) ·
  [792183](https://devforum.roblox.com/t/we-need-documentation-on-edit-quality-level-and-quality-level/792183)
- **VFX-Techniken der Community:** [2338789](https://devforum.roblox.com/t/hidden-glass-distortion-effect-with-real-time-reflections-tutorial/2338789) ·
  [2319086](https://devforum.roblox.com/t/glass-refraction-effect-breaks-at-high-transparency-values/2319086) ·
  [2940835](https://devforum.roblox.com/t/separate-the-glass-materials-distortion-effect-from-its-transparency/2940835) ·
  [3666977](https://devforum.roblox.com/t/3666977) ·
  [258289](https://devforum.roblox.com/t/control-the-fresnel-effect-of-forcefield-material-using-the-reflection-property/258289) ·
  [280851](https://devforum.roblox.com/t/documentation-regarding-the-new-force-field-material/280851) ·
  [2392057](https://devforum.roblox.com/t/why-does-this-forcefield-material-meshpart-look-different-at-runtime/2392057) ·
  [319192](https://devforum.roblox.com/t/how-to-have-functioning-emissive-textures/319192) ·
  [3669430](https://devforum.roblox.com/t/runup-vfx-breakdown-part-4/3669430) ·
  [2468478](https://devforum.roblox.com/t/advanced-impact-frames/2468478) ·
  [2963136](https://devforum.roblox.com/t/open-source-impactframe-module/2963136) ·
  [2652420](https://devforum.roblox.com/t/2652420) ·
  [98482](https://devforum.roblox.com/t/ez-camera-shake-ported-to-roblox/98482) ·
  [3621709](https://devforum.roblox.com/t/camerashakeupdated-simple-camerascreen-shaking-module/3621709) ·
  [4731267](https://devforum.roblox.com/t/gg-camera-shake-screenshake-that-doesnt-suck/4731267) ·
  [1516280](https://devforum.roblox.com/t/how-to-make-an-lighting-bolt-effect/1516280) ·
  [1113871](https://devforum.roblox.com/t/crecent-sword-slash-effect/1113871) ·
  [927925](https://devforum.roblox.com/t/creating-an-unkown-sword-slash-effect/927925) ·
  [3172303](https://devforum.roblox.com/t/how-do-i-prevent-mesh-distortion/3172303) ·
  [2131510](https://devforum.roblox.com/t/how-could-i-recreate-this-effect/2131510) ·
  [3370194](https://devforum.roblox.com/t/battlegrounds-crater-module/3370194) ·
  [2863076](https://devforum.roblox.com/t/how-to-make-a-creating-domain-expansion-effect/2863076) ·
  [3635032](https://devforum.roblox.com/t/open-source-mesh-flipbook-pack/3635032) ·
  [2656999](https://devforum.roblox.com/t/what-are-mesh-flipbooks/2656999) ·
  [1610853](https://devforum.roblox.com/t/full-beginners-guide-on-scripting-animefighting-vfxvisual-effects-part-1/1610853) ·
  [2068650](https://devforum.roblox.com/t/introduction-to-vfx-particles/2068650) ·
  [2805022](https://devforum.roblox.com/t/how-can-i-learn-vfx/2805022) ·
  [725749](https://devforum.roblox.com/t/what-are-good-ways-to-learn-vfx/725749) ·
  [937281](https://devforum.roblox.com/t/understanding-easing-styles/937281)

### 6.8 Allgemeines Game-VFX-Handwerk (REPORTED, nur Such-Snippets)

- League of Legends VFX Style Guide: https://nexus.leagueoflegends.com/en-us/2017/10/dev-leagues-vfx-style-guide/ (PDF:
  https://nexus.leagueoflegends.com/wp-content/uploads/2017/10/VFX_Styleguide_final_public_hidpjqwx7lqyx0pjj3ss.pdf) ·
  https://www.vfxapprentice.com/blog/10-league-of-legends-vfx-design-tips ·
  https://leagueoflegends.com/en-au/news/dev/dev-behind-the-scenes-of-vfx-updates
- realtimevfx: https://realtimevfx.com/t/anatomy-of-a-league-of-legends-missile-part-1-creating-areas-of-focus/11614 ·
  https://realtimevfx.com/t/anatomy-of-a-league-of-legends-missile-part-2-what-are-we-communicating-with-our-vfx/13062 ·
  https://realtimevfx.com/t/stylized-frag-launcher-explosion-overwatch-inspiration-breakdown-posted/1894 ·
  https://realtimevfx.com/t/custom-explosion-feedback/16005 · https://realtimevfx.com/t/explosion-effect-help-needed/16021 ·
  https://realtimevfx.com/t/diving-into-color-tips-tricks-i-use-for-using-color/16220
- GDC: https://gdcvault.com/play/1023943/Visual-Effects-Bootcamp-Artistic-Principles ·
  https://3dreference.notion.site/Visual-Effects-Bootcamp-Artistic-Principles-of-VFX-GDC-2017-fcd0698c31cf4621a70ed8a7621e17da ·
  https://gdcvault.com/play/1034360/Attention-Overload-Creating-Readable-VFX
- Timing, Farbe, Explosionen: https://www.vfxapprentice.com/blog/the-soul-of-effects-what-is-timing-in-vfx ·
  https://www.vfxapprentice.com/timing-workshop-learn-vfx-timing · https://www.vfxapprentice.com/blog/color-101-vfx-artists ·
  https://creative-assembly.com/node/4446 ·
  https://gamedeveloper.com/design/vfx-as-game-design-tools-the-ludology-of-vfx-in-god-of-war-ragnarok-and-halo-infinite ·
  https://simonschreibt.de/gat/battlefront-ii-layered-explosion/ · https://www.pcgamer.com/how-great-game-explosions-are-made
- Hit-Stop, Kamera, Impact Frames: https://game.capcom.com/cfn/sfv/column/131545?lang=en ·
  https://www.scitepress.org/Papers/2024/124614/124614.pdf ·
  https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/ ·
  https://uhiyama-lab.com/en/notes/unity/unity-game-feel-hit-feedback/ · https://bevy.org/examples/camera/2d-screen-shake/ ·
  https://kidscancode.org/godot_recipes/3.x/2d/screen_shake/ ·
  https://80.lv/articles/my-hero-academia-style-attack-vfx-in-unreal-engine-5
- Geringe Autorität (nur als Hinweis): https://gamineai.com/blog/top-down-combat-vfx-readability-2026-color-timing-system-busy-screens ·
  https://studios-groundzero.pages.dev/journal/breakdowns/final-fantasy-vii ·
  https://playbooks.com/skills/dylantarre/animation-principles/rhythm-pacing ·
  https://www.arhfoundation.org/impact-frames-meaning · https://www.tripo3d.ai/blog/roblox-vfx
