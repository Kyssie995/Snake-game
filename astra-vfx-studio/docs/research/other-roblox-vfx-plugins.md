# Recherche: Weitere Roblox-VFX-Authoring-Plugins und -Module (Marktüberblick)

Stand: 2026-10-27 · Phase 1 (Research & Architecture) · Autor: Research-Subagent für ASTRA VFX STUDIO
Nicht abgedeckt (eigene Notizen): ROS Particle Editor, Qwinkle's Particles 2.

> **Label-Legende:** **VERIFIED** = offizielle Roblox-Doku (creator-docs-Quelltext) / lokaler API-Dump (Engine 0.745.0.7451137) /
> eigene Produktseite bzw. eigenes README/Paket des Produkts · **REPORTED** = DevForum-Posts, Store-Snippets, Videos,
> Drittseiten, Such-Zusammenfassungen · **ASSUMPTION** = eigene Schlussfolgerung · **IDEA** = eigene Design-Idee für ASTRA.
> ⚑ = *critical* (eine ASTRA-Architekturentscheidung hängt daran).

> **Quellenlage:** DevForum, Creator Store, YouTube, github.com sowie `*.github.io`, `docs.zilibobi.dev`, `effect-designer.igottic.com`
> und `phase-doc.vercel.app` waren aus der Sandbox **nicht** erreichbar (Proxy 403). Lesbar waren: `raw.githubusercontent.com`
> (READMEs/Docs öffentlicher Repos, offizielle creator-docs) und `registry.npmjs.org` (npm-Metadaten/Pakete). Alles, was nur über
> WebSearch-Snippets kam, ist höchstens **REPORTED**. Preise, Ratings und Datumsangaben aus Creator-Store-Snippets sind
> Momentaufnahmen und können veraltet sein. **Es wurde kein Fremdcode übernommen**; bei Paketen/READMEs wurden nur
> Funktionsumfang, Konzepte und öffentliche API-Oberflächen in eigenen Worten beschrieben.

---

## 1. Zusammenfassung

Der Roblox-VFX-Tool-Markt 2023–2026 ist **fragmentiert, aber sehr aktiv**. Es lassen sich fünf Produktklassen unterscheiden:

1. **"All-in-one"-Plugins auf Basis nativer Instanzen** (ParticleEmitter/Beam/Trail + Attribute): VFX Suite (2023, paid),
   VFX Editor (2024, MIT/paid), VFX Forge (2025/26, paid), **VFX Studio von XxOmqxXNerd** (2025, free, 800+ Votes, 96 %),
   Sine VFX, Phase VFX (2026), Effect Designer Suite (2026, open source), "Beziers"/vfxer, EasyVFX (Okt. 2026, MIT).
   Gemeinsame Basis: eigene NumberSequence-/Bezier-Editoren, Emit-Fenster, Retime/Resize/Recolor, Asset-Bibliothek,
   **Emit-Runtime-Modul** und oft eine globale Studio-API über `shared` (`shared.vfx`, `shared.sv`).
2. **Timeline-/Sequencer-Tools**: Moon Animator 2 (de-facto-Standard, auch für VFX-Timing), Eclipse Animator, **Arc**
   (Sept. 2026, VFX-Animation mit Emit-Keyframes und ModuleScript-Export), Motion (Timeline → Luau-Daten), Visulie
   (beliebige Properties inkl. Sequences, Methodenaufrufe wie `Emit()`), dazu **Exporter** (Moon VFX Exporter,
   MoonVFXCompiler), weil das Portieren von Moon-Timings in Spielcode laut einem Autor **4–6 h pro 30–60-s-Effekt** kostet.
3. **Custom-Partikelsysteme** (Parts/Meshes/SurfaceGui statt ParticleEmitter): Lumina (Node-Graph, MIT, WIP), VortexFX
   (3D-Partikel mit Kollision/Audio), Flare Craft (modular, 600 R$, nicht mehr aktiv gepflegt). Durchgängige Kritik:
   **Performance deutlich schlechter als native Emitter**.
4. **UI-Partikel** (ImageLabel-basiert): Emitter2D, UIParticles, 2D Emitter, UIParty, ParticleUI, rParticle u. a. –
   Hauptprobleme: Performance, keine LightEmission/Brightness in GUIs. **Neu:** Die Engine 0.745 enthält eine native,
   noch **nicht veröffentlichte** Klasse `ParticleEmitter2D` (Tag `NotBrowsable`, keine Doku-Seite).
5. **Kleine Helfer**: Emit-Plugins (Jad's Emit Plugin, roblox-particle-util, Shifty's), Scaler, Sequence-Editoren
   (SmoothSequence Graph, CSE Pro), Lightning-Module (Lightning Beams von Quasiduck).

**Wichtigste Erkenntnisse für ASTRA:**

- ⚑ Es existiert eine **de-facto Community-Konvention** für Emit-Daten als Attribute: `EmitCount`, `EmitDelay`,
  `EmitDuration` (teils Alias `DelayTime`), dazu `<Property>Sequence`-NumberSequence-Attribute zum Animieren beliebiger
  Properties. ASTRA sollte diese Konvention **importieren und optional exportieren**, um mit dem Ökosystem kompatibel zu sein.
- ⚑ **Timeline + Runtime-Export ist die größte Lücke** der klassischen Tools (VFX Forge: bewusst kein Sequencer); 2026
  beginnen Arc und Motion, sie zu füllen. ASTRAs Timeline ist also ein echtes, aber nicht mehr exklusives Differenzierungsmerkmal.
- ⚑ **KI-Agent-Integration ist bereits Wettbewerb**: EasyVFX liefert ein Claude-Code-Plugin, headless Lune-Tests und ein
  Render-/Audit-Tooling; für Arc existiert eine Drittanbieter-MCP-Brücke (61 Tools). ASTRA muss sich hier über
  **versioniertes Schema, Validierung und Determinismus** abheben.
- ⚑ Plugins können native Partikel **nicht vorspulen** (`ParticleEmitter:FastForward` ist `RobloxScriptSecurity`). Timeline-Scrubbing
  nativer Emitter braucht eine eigene Strategie (Clear/Emit/TimeScale oder Vorschau-Simulation).
- ⚑ Kurven-Metadaten (Bezier-Handles, Easing) dürfen nicht nur in flüchtigen Attributen liegen (VFX Editor setzt Easing
  zurück, wenn das Attribut verloren geht) – die **JSON-Effektdatei muss Source of Truth** sein; NumberSequences
  (max. 20 Keypoints) sind nur gebackene Ausgabe.

---

## 2. Befunde pro Produkt

### 2.1 VFX Suite (PrimeVoxel) — Evidenz: REPORTED

- Creator-Store-Asset 14328968969, DevForum-Thread 2545686 ("Introducing the VFX Suite Plugin"), Ankündigung auf X im
  August 2023 (x.com/primevoxel/status/1694203050347667935). **REPORTED**
- Feature-Liste laut Thread/Store: "Better Emit" mit **Emit Delay**, **Sequence Copier** (Squash, Size, Transparency, Colour),
  **Bezier Graph Editor mit Presets und steuerbaren Segmenten**, History/Undo (Ctrl+Z), **Re-time**, **Particle/Beam Resizer**,
  **Trail Preview**; alle Features "cross-compatible" zwischen Beams, Trails und ParticleEmitters. **REPORTED**
- Rating laut Store-Snippet ca. 90 % bei 300+ Votes, 51 Reviews; Preis von einem Konkurrenz-Thread mit **4,99 $** angegeben,
  "keine Texture-Library, keine Slider, kein Animation-Util". **REPORTED**
- Kritik: **UI "REALLY small"/beengt**, Wunsch nach skalierbarer UI; Studio wirke "cluttered"; frühe Kritik, ohne Emit-Count/
  Emit-Delay kaum nutzbar; Wunsch, **Einstellungen eines bestehenden Partikels wieder ins Tool zu laden** ("really hard to make
  edits to particles I've already created"). Lob: Workflow mache Explosion-Redesign "enjoyable", Preis fair. **REPORTED**
- VFX Forge nennt VFX Suite ausdrücklich als Inspiration für Layout und Funktionen. **REPORTED**
- Quellen: https://devforum.roblox.com/t/introducing-the-vfx-suite-plugin/2545686 ,
  https://create.roblox.com/store/asset/14328968969/VFX-Suite

### 2.2 VFX Editor – "all your VFX needs, in one" (VirtualButFake, Repo jetzt tijnepema/vfx-editor) — Evidenz: VERIFIED

- Eigenes README, Wiki (Home) und CHANGELOG via raw.githubusercontent gelesen. MIT-Lizenz, Build mit Aftman + **Lune**
  (`lune run build`), UI mit **Fusion / FusionComponents** und eigenem themeFramework, Stories für **Flipbook** (Storybook).
  Creator-Store 18800449515 (laut DevForum 4,99 $; GitHub-Release gratis). **VERIFIED** (Preis REPORTED)
- Features (VERIFIED, README/Wiki):
  - Eigener **NumberSequence-Editor**: "Carbon copy" des Studio-Editors plus Rechtsklick-Kontextmenü für **Easing-Style/-Direction**
    pro Segment und **"bezier" mit ziehbaren Handles**; Werte per Textbox; Envelope-Handle wird an Min/Max geklemmt.
  - **Easing-/Bezier-Daten werden in Attributen gespeichert**; geht das Attribut verloren, werden alle Easing-Daten
    zurückgesetzt und eine neue Kurve aus den aktuellen Punkten generiert.
  - ColorSequence-Editor (nur optischer/funktionaler Refresh, keine neuen Features).
  - **Texture Storage** als simuliertes Dateisystem mit Ordnern beliebiger Tiefe, Flipbook-Anzeige, **Import/Export als JSON**
    sowie Import aus Instanzen (z. B. "VFX-Baseplates"); Flipbook-Vorschau braucht teils HTTP-Requests.
  - Ersatz für das Properties-Fenster: Instanzbaum der Selektion, Suche nach Instanznamen **oder Properties**, Kategorien einklappbar.
  - **Multi-Property-Selektion** mit Strg nur bei passenden Typen (gleicher Primitivtyp **und** gleiche Semantik –
    Size und Transparency sind beide NumberSequence, gelten aber als verschieden); Änderungen replizieren auf alle;
    Copy/Paste von Property-Werten nach denselben Regeln.
  - Undo/Redo für fast alle Aktionen; Light/Dark-Theme.
  - Settings: **Max Instance Depth**, **Max Size/Max Squash** (eigene Obergrenze über Roblox-Default hinaus),
    **Treeview Virtual Scroller** (Properties werden erst beim Sichtbarwerden geladen und gecacht), Default-Graph-Style.
  - **Lightweight Mode**, der das Studio-Properties-Fenster nachahmt (minimale Lernkurve).
- Changelog-Fakten (VERIFIED): 1.0.3 Memory-Leak in eigenen Canvas/Scroller-Komponenten; 1.0.5/1.0.6 rekursive State-Fehler
  in fusionComponents; 1.0.7 Konstantwert-Eingabe neben Graph-Button, Graph skaliert auf Maximalwert; **1.0.9: Attribute heißen
  `EmitCount` und `EmitDelay`** (Issue #7, also Anpassung an die Community-Konvention), ZOffset-Schrittweite 0,1,
  NumberSequence-Werte auf 3 Nachkommastellen gerundet.
- Nutzerfeedback (REPORTED): Wunsch nach **globalen Editoren** statt an ein Partikel gebunden; Bug, dass Eingaben wie ".1" nicht
  akzeptiert werden; Crashs beim Hinzufügen von Texturen (vor allem auf schwachen Systemen); Texturen entladen beim Scrollen;
  Wunsch nach **Graph-Presets** (von A nach B mit gewählter Easing-Kurve und N Punkten); Type-to-select in Dropdowns.
- Quellen: https://raw.githubusercontent.com/VirtualButFake/vfx-editor/main/README.md ,
  https://raw.githubusercontent.com/wiki/VirtualButFake/vfx-editor/Home.md ,
  https://raw.githubusercontent.com/VirtualButFake/vfx-editor/main/CHANGELOG.md ,
  https://devforum.roblox.com/t/vfx-editor-all-your-vfx-needs-in-one/3103467

### 2.3 VFX Forge (zilibobi) — Evidenz: MIXED

- Paid (itch.io ab 16,67 $, Status "In development"; Creator Store 133927382668067, Snippet: 97 % bei 60+ Votes, v2.1.0). **REPORTED**
- Feature-Liste (Store/itch/DevForum 3867553): Partikel, Beams, Trails, **Mesh- und Decal-Flipbooks**, Beam-Flipbooks,
  **3D-Beziers**, **Lightning**, Shockwave, Spin Model, Screen Effects, Camera Shake; **26 eingebaute kubische Bezier-Presets**
  (in/out/in-out) plus eigene Kurven- und Effekt-Presets; globale Studio-API `shared.vfx`; Emit-Modul fürs Spiel. **REPORTED**
- **Kein eingebauter Sequencer**: Laut Autor wäre Moon-Qualität "quite a lot of effort"; stattdessen ein Fenster mit
  **Einzeiler-Emit-Code**, den man in Moon Animator-Events nutzt. **REPORTED**
- **Emit-Modul (VERIFIED, eigenes README + npm-Paket `@zilibobi/forge-vfx` 2.4.0, erstellt 2026-03-19)**: Wally/npm/rbxm;
  muss initialisiert werden und ist danach zusätzlich über `shared.vfx` erreichbar. Öffentliche API-Oberfläche laut
  Typdeklaration (in eigenen Worten): init/deinit; emit auf beliebig viele Instanzen (ParticleEmitter, Beams, Trails, Models,
  getaggte Effekte) mit optionalem **Skalierungsfaktor** oder **Render-Tiefe**, Rückgabe mit "Finished"-Promise und Clear;
  enable/disable rekursiv (für Nicht-Emitter über ein "Enabled"-Attribut); **retime** (Speeds, Lifetimes, Durations, Rates),
  **resize** (Partikelgrößen, Beam-Breiten, Attachment-Abstände), **recolor** im Modus replace oder multiply (HSV, HDR-Faktor
  bleibt erhalten); **Attribut-Caching** (Attribute werden clientseitig entfernt und im Speicher gehalten, nur für Instanzen in
  ReplicatedStorage).
- **Lizenz (VERIFIED)**: "custom source-available copyleft license", nur Nutzung innerhalb von Roblox-Spielen erlaubt.
- Feedback (REPORTED): "tonnes of features that no other plugin has", klare/kompakte UI; Gegenstimmen zu Preis vs. VFX Suite,
  Modul "very hard to understand", Store-Version hinkte der lokalen Version hinterher; Doku anfangs unvollständig.
- Quellen: https://devforum.roblox.com/t/plugin-vfx-forge-an-advanced-custom-vfx-system/3867553 , https://zilibobi.itch.io/vfx-forge ,
  https://raw.githubusercontent.com/zilibobi/forge-vfx/main/README.md , https://registry.npmjs.org/@zilibobi/forge-vfx

### 2.4 VFX Studio (XxOmqxXNerd) — Evidenz: REPORTED  ⚠ Namenskollision mit "ASTRA VFX STUDIO"

- Kostenloses Plugin, Creator Store 135581141962270, erstellt 2025-05-31, Update 2026-09-07, **96 % bei 800+ Votes, 110 Reviews**,
  Beschreibung "AIO (soon to be) vfx tool"; eigener Discord, viele Tutorials; im DevForum als "der Free-One" empfohlen, teils als
  besser als die bezahlte VFX Suite bezeichnet. **REPORTED**
- Eine Doku-Seite (sytranom.github.io/vfx-studio-docs, Zuordnung zum Store-Autor **nicht bestätigt**) beschreibt Bezier-Curve-Editor
  für Property-Änderungen, "Advanced Panel" zum Verketten von Bewegungen, Camera Shakes und Screen Effects, Asset-Bibliothek
  (Texturen, Meshes, SFX, Scripts). **REPORTED**
- Eine **Drittanalyse** (EasyVFX-Repo, docs/vfx-studio-analysis.md, Version 3.9.3; die Autoren geben an, keinen Code kopiert zu haben)
  beschreibt das Effektmodell: **kein eigenes Effektformat**, sondern Attribute auf normalen Instanzen – `EmitDelay`, `EmitDuration`,
  `EmitCount`; `<Property>Sequence`-Attribute (NumberSequence animiert die Property über EmitDuration bzw. Lifetime, danach
  Rücksetzung); Tween-Schritte (Linear, Bogen = quadratischer Bezier, randomisiert, manuelle Bezier-Punkte) in einer Configuration;
  Kamera-Shake-Schritte und Impact Frames als ColorCorrection-Templates; globale **Retime/Scale/Color**-Slider;
  **Code-Generator** für Trigger-Skripte; eine Heartbeat-Verbindung pro getweenter Property; ca. 120 eigene Module/35k Zeilen,
  ~300 gebündelte Fremdbibliotheken, ~570 MeshParts. **REPORTED**
- Quellen: https://create.roblox.com/store/asset/135581141962270/VFX-Studio ,
  https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/docs/vfx-studio-analysis.md

### 2.5 EasyVFX (VuxSussy) — Evidenz: VERIFIED (eigenes README/Docs), sehr jung (1.0.0 am 2026-10-16)

- MIT, Rojo/Lune/luau-lsp/selene via Rokit, CI. Zielgruppe: **Nicht-Programmierer** ("pick object → click effect → tweak → choose trigger").
  45 Presets in Kategorien; "Create"-Tab baut Effekte aus **Blöcken** (Slash, Ring, Burst Lines, Spiral, Orb, Lightning, Projectile,
  Crater, Debris, Sparks, Smoke, Aura, Light, Camera Shake, Impact Frame); **Share-Codes** (`EVFX1:…`) mit Validierung
  (nur bekannte Blöcke, alle Zahlen geklemmt); jede Instanz speichert ihre Definition als Attribut. **VERIFIED**
- Technik: "scharfe" Formen aus **Geometrie statt Texturen** (Ringe aus 4 gekrümmten Bezier-Beams, Slash-Bänder aus verketteten Beams,
  Attachments werden jedes Frame zur Kamera gedreht statt `FaceCamera`); optionales HD-Texturpaket aus Blender-Skript.
  Trigger: Always on, Repeat, Touch, Click, ProximityPrompt-Taste, Script. **VERIFIED**
- Runtime/Performance: Effekte laufen **clientseitig**, Server sendet ein RemoteEvent; **eine einzige Animationsschleife** für alle
  Effekte; temporäre Teile in der Camera mit `Archivable=false`, ohne Kollision/Query/Schatten; **automatische Qualitätsstufen**;
  Rate-Cap 400, max. 64 Rocks/Needles pro Layer; folgt der Konvention **EmitCount/EmitDelay/EmitDuration** und unterstützt
  `<Property>Sequence`-Attribute. **VERIFIED**
- Timeline-Integration: schreibt **Eclipse-Animator-Event-Tracks** (KeyframeSequence + Event-Ordner + exportierte `KeyframeMarker`) und
  bindet Effekte zur Laufzeit an AnimationTrack-Marker ("BindAnimation"). **VERIFIED** (Eclipse-Formatdetails nur laut EasyVFX)
- **KI-Workflow**: liefert ein **Claude-Code-Plugin** (Skills effect/story/components/preview/texture); headless "agentic loop":
  Timeline-Recorder unter **Lune** zeichnet jedes Frame auf, Partikel werden aus Emitter-Properties nachsimuliert, Python rendert
  Strips/Diffs, **Budget-Gates** (Partikel/Beams/Lights, "ends clean", Flash-Dauer/-Rate) gegen Baseline, "Beat Sheets" als JSON.
  Ausdrücklich nur Approximation, nicht der echte Renderer. **VERIFIED**
- Quellen: https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/README.md ,
  https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/docs/agentic-loop.md ,
  https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/docs/eclipse-animator.md

### 2.6 Arc (sevenIIl) — Evidenz: REPORTED

- Kostenloses Plugin, Creator Store 118257542877059, erstellt Ende Sept. 2026, Version 2.0.0, 100 % bei 20+ Votes, 17 Reviews;
  DevForum 4903133 (~2,7k Views). **REPORTED**
- "VFX animieren wie einen Charakter": Keyframes für Position/Rotation/Size/Properties von Parts, Attachments, Partikeln, Beams;
  **Emit-Keyframes mit Emit Count, Duration und Delay**; **Partikel-Vorschau folgt dem Scrubbing vorwärts und rückwärts**;
  Screen Effects (Camera Shake, Flash, Impact Frames, Debris); benannte **Events** (z. B. "Hit") mit generierter Funktion;
  3D-Beziers, **VFX-Forge-Konvertierung**, **Moon-Animator-Sync**, Keyframe-Gruppierung; Export als **ModuleScript mit Start()/Cancel()**,
  jede Wiedergabe unabhängig. **REPORTED**
- Drittanbieter-Erweiterung "Arc VFX MCP" (Joojjuuk/plugin-studio, README gelesen): lokaler Node-MCP-Server mit **61 Tools**,
  authentifizierte Bridge auf 127.0.0.1, Workflow list_studios → connect → create_project → Keyframes/Emits → seek/play →
  export_runtime; benötigt HTTP-Erlaubnis für localhost; für Claude Code konfigurierbar. **VERIFIED** (für die Erweiterung selbst)
- Quellen: https://devforum.roblox.com/t/arc-a-vfx-animation-plugin/4903133 , https://create.roblox.com/store/asset/118257542877059/Arc ,
  https://raw.githubusercontent.com/Joojjuuk/plugin-studio/main/README.md

### 2.7 Moon Animator 2 (xsixx) + VFX-Exporter — Evidenz: MIXED

- Paid (Creator Store 4725618216, erstellt 2020-02-23, häufige Sales) plus offizielle Free-Version (12944524137). Eigene
  `.xsixx`-Dateien, File Explorer, Character Inserter, Tracks ein-/ausklappbar, Keyframe-Gruppierung, Easing pro Keyframe,
  Kamera-Animation, Events mit Code. **REPORTED**
- Bekannte Grenzen (REPORTED): Property-/CFrame-Animationen sind nicht als Roblox-Animation exportierbar (nur über Drittmodule/Exporter);
  Emit()-Events brachen in frühen Exportern; Animation Priority nur über Re-Import im Roblox-Editor.
- Moon Animator 2 ist in der Praxis das **VFX-Timing-Werkzeug** vieler Teams. Belege: VFX Forge verweist auf Moon für Sequencing;
  es existieren mehrere Exporter. **REPORTED/VERIFIED**
- **Moon VFX Exporter** (Games.GG, README VERIFIED): liest die gespeicherte Moon-Animation und erzeugt eine **reine Daten-Cue-Tabelle**
  (Frame → Effekt, Offset relativ zum HumanoidRootPart, optional Parent-Körperteil, Keys mit Moons Easing) plus ein
  Abspiel-/Cleanup-Modul; versteht Emit-Aufrufe von VFX Forge und Part_Icles; Kamera-, Lighting- und Screen-Effekte; Preview im
  Edit-Mode; "Warnungen statt Fehler". **VERIFIED**
- **MoonVFXCompiler/HamVFX** (README VERIFIED): liest Moon- oder Eclipse-Saves und generiert Model + VFXPlayer-Modul in einem Klick;
  speichert nur tatsächlich gekeyte Properties; Moon→Eclipse-Konverter. Motivation laut Autor: manuelles Portieren kostet
  **4–6 Stunden pro 30–60-s-Effekt**. **REPORTED** (Selbstauskunft im README)
- Quellen: https://create.roblox.com/store/asset/4725618216/Moon-Animator-2 ,
  https://devforum.roblox.com/t/getting-started-with-moon-animator-2-unofficial/476330 ,
  https://raw.githubusercontent.com/GamesGG0/Moon-Animator-VFX-Exporter/main/README.md ,
  https://raw.githubusercontent.com/GuHamYaiXD/MoonVFXComplier/main/README.md

### 2.8 Weitere Timeline-Tools: Motion, Visulie, Eclipse Animator — Evidenz: REPORTED

- **Motion** (jaybeemvoid, DevForum 4274872, v1.5.1): Timeline für Parts, Kameras, Rigs, Properties; **Animation als Daten** –
  Export als rohe Luau-Daten statt Animation-Assets; Marker mit Callbacks; Runtime-Engine per "Export Runtime Engine" nach
  ReplicatedStorage; Motion 2.0 als inkompatibles Neuprojekt angekündigt (letzte Antwort 2026-04-28). **REPORTED**
- **Visulie** (DevForum 3582453, Versionen bis 6.1.x): animiert nahezu beliebige Properties und Datentypen, auch nicht tweenbare
  (UDim, Rect, **NumberSequence, ColorSequence**), **Methodenaufrufe** (Emit, Sound:Play), Attribute und Tags; Renderer-Modul mit
  Playback-Speed, Framerate, Animation Events; Scrubbing löst Methodenaufrufe aus (wenn langsam genug); gedacht für
  "atomare Effekte", nicht für Motor6D-Rigs. **REPORTED**
- **Eclipse Animator** (Creator Store 86116556258301): Event-Track mit Emits, Sounds, Code; Exporte als KeyframeMarker. Details nur
  aus Drittprojekten (EasyVFX, MoonVFXCompiler). **REPORTED**
- Quellen: https://devforum.roblox.com/t/motion-151-%E2%80%94-timeline-editor-animator/4274872 ,
  https://devforum.roblox.com/t/visulie-%E2%94%80-a-novel-all-purpose-animation-data-and-effects-suite/3582453 ,
  https://create.roblox.com/store/asset/86116556258301/Eclipse-Animator

### 2.9 Phase VFX (Phase Studio) — Evidenz: REPORTED

- Creator Store 78798609925417, erstellt 2026-04-07, Update 2026-08-04, 84 % bei 30+ Votes. Eigene Doku-Seite: "registry-driven,
  fully in-Studio VFX toolkit with **12 production-ready effect types**, visual curve editor, and **one-click runtime code generation**".
  Features: Partikel, Beams, Trails, Mesh- und Decal-Flipbooks, 3D-Beziers, Lightning, Camera Shake, Screen-Space-Effekte,
  editierbare Mehrpunkt-Kurven mit Presets, globale Studio-API über `shared.vfx` (!), Runtime-Emission, generierter Emit-Code.
  Hinweis "may include licensed third-party assets". **REPORTED**
- Quellen: https://create.roblox.com/store/asset/78798609925417/Phase-VFX , https://phase-doc.vercel.app/

### 2.10 Sine VFX, Effect Designer Suite, "Beziers"/vfxer, VFX Scripter Pro, SteakParticles — Evidenz: REPORTED

- **Sine VFX** (DevForum 4803771, sinevfx.xyz; 5–7 $): Emit-Fenster für jede VFX-Instanz, Color-Picker, globale API `shared.sv`,
  **Partikelzähler**, **Partikelpfad-Visualizer**, **Spawn-Shape-Visualizer**, Trail Preview, 14k+ Assets, 3D-Partikel, transformierte
  Trails/Beams, Screen Effects; "inspiriert von VFX Forge & QP2"; Shirt-Version als lokales Plugin ohne Auto-Update.
- **Effect Designer Suite** (igottic, DevForum 4754553, Store 109890065116916, open source, frei): Emit-Eigenschaften auf allen
  emittierbaren Objekten (Count, Delay, Duration; "kompatibel mit anderen Plugins"), einmalig oder wiederholt; Copy/Paste- und
  Skalier-Tools über Roblox-Grenzen hinaus; Bezier-/Tween-Animation für Attachments und BaseParts; ~7000 Flipbooks/Texturen;
  **ColorSequences im Oklab-Farbraum** für natürlichere Übergänge; v1.2.0 teilt UI in vier Widgets.
- **"Beziers" – Advanced modular VFX Plugin** (DevForum 4180222/3547230, vfxer.gitbook.io): Game-Modul zum Abspielen, Add-ons
  (ImpactFrames, CameraShake, ScreenEffects, MeshVFX), Tweening von Lights/Beams/Sounds/Partikeln/Trails, Repeat-Emit-Attribute,
  **ObjectValues zum Emittieren externer Objekte**, 10k+ Assets, Bezier-Add-on mit Handles in Arbeit, Studio-API für Add-on-Autoren.
- **VFX Scripter Pro** (DevForum 2961973, frei): VFX ohne Play-Test visualisieren und skripten, Script-Bibliothek, Wiederherstellung nach
  Studio-Crash, Looped Mode, Physik auf Selektion.
- **SteakParticles** (DevForum 2908779): Preset-Bibliothek (60+), Texturen, Basis-Einstellungen; kaum Details.
- Quellen: https://devforum.roblox.com/t/plugin-sine-vfx-a-vfx-plugin-for-roblox-studio/4803771 ,
  https://devforum.roblox.com/t/effect-designer-suite-%E2%80%94-vfx-tooling-assets-and-more/4754553 ,
  https://devforum.roblox.com/t/beziers-advanced-modular-vfx-plugin-10000-assets-add-ons/4180222 ,
  https://devforum.roblox.com/t/vfx-scripter-pro-%E2%80%94-an-essential-plugin-for-vfx-scripters/2961973 ,
  https://devforum.roblox.com/t/steakparticles-plugin-for-creating-vfx-and-particle-emitters/2908779

### 2.11 Custom-Partikelsysteme: Lumina, VortexFX, Flare Craft

**Lumina (Mqxsyy) — Evidenz: VERIFIED (README, Docs-Repo, package.json) + REPORTED (Performance)**
- MIT, "open-source custom particle system API … includes a graph editor"; README warnt ausdrücklich vor Produktionseinsatz
  (WIP, buggy, "scuffed" Texteingaben). Plugin in **roblox-ts + @rbxts/react**, Build über rbxtsc + Rojo. **VERIFIED**
- **Node-Gruppen** (Docs): Spawn (Constant/Burst), Initialize (SetColor, SetLifetime), Update (Accelerate, **Bounce**, Drag, LookTowards,
  MoveTowards, Multiply*/Set*OverLife), Render (**PlaneParticle** mit Orientierung FacingCamera/VelocityParallel/VelocityPerpendicular,
  DoubleSided, Spritesheet; **MeshParticle**; **VolumetricParticle** Cube/Sphere), Logic (AliveTime, Clamp, GetParentProperty, Math,
  Random, Remap, Shape, Time, Trig, ValueOut), versteckte "Mixed"-Gruppe. Konzeptionell nah an Unity-VFX-Graph-Kontexten. **VERIFIED**
- Export: ein ModuleScript oder Ordner von ModuleScripts. Rendering per **SurfaceGui** (Autor erwog Wechsel zu Planes); **Lag vor allem durch
  Property-Updates einzelner Parts** (Transparency, Size); Autor: kann nicht mit dem Default-Emitter mithalten; Performance als Ziel für 1.0.0. **REPORTED**
- Repo laut Aggregator seit Monaten ohne Update. **REPORTED**
- Quellen: https://raw.githubusercontent.com/Mqxsyy/Lumina/main/README.md ,
  https://raw.githubusercontent.com/Mqxsyy/LuminaDocs/main/sidebars.ts ,
  https://devforum.roblox.com/t/update-020-lumina-a-custom-particle-system/2963557

**VortexFX (FancyDucc/Aeresei) — Evidenz: VERIFIED (README) + REPORTED**
- 3D-Partikelsystem als Modul (Creator Store 89242445503292), v1.0.65; Konstruktor mit Adornee, Create(Properties), Start. Features:
  Emission von Models/MeshParts, **Kollision pro Partikel** (Abprallen, Ausweichen), **Audio-Reaktion mit Beat-Erkennung**, Pfade,
  Wind/Velocity-Vererbung, "Instability"-Jitter, Flipbooks; nutzt ObjectCache. Eigene "Custom Provision License". **VERIFIED**
- Autor selbst: 2D-Partikel sind **deutlich performanter**, 3D-Partikel nur als Zusatz; Spikes bei vielen Partikeln; clientseitig
  betreiben. Laut späterem Post veraltet, Rewrite "Vortex3D" geplant. **VERIFIED/REPORTED**
- Quellen: https://raw.githubusercontent.com/FancyDucc/3D-Particle-System/main/README.md ,
  https://devforum.roblox.com/t/vortexfx-v106-a-3d-particle-system-for-all-your-3d-particle-needs/3131414

**Flare Craft (Michel2003g) — Evidenz: REPORTED**
- Modulares 3D-Partikelsystem mit Plugin, 600 R$; Module (z. B. Velocity, boxLocation) frei kombinierbar; Kollision mit Events-Template;
  ~**1000 Partikel bei ~30 fps** laut Entwickler; Doku unvollständig; seit Mai 2024 **nicht aktiv gepflegt** (Vollzeitjob des Autors);
  Installationsfehler (fehlende Module) früh berichtet.
- Quelle: https://devforum.roblox.com/t/new-particle-system-flare-craft/2539746

### 2.12 UI-Partikel (Emitter2D, UIParticles, 2D Emitter, UIParty, ParticleUI, rParticle) und native `ParticleEmitter2D`

- **Emitter2D** (DevForum 3742009): Plugin + Modul, UI-Partikel ohne Code, Emitter-Objekte in GUIs analog zu 3D-Emittern,
  **"Convert Emitter"** wandelt bestehende ParticleEmitter um; Eigenschaften wie ZIndex, EmissionShape. Einschränkungen laut Autor:
  **deutlich langsamer** (ImageLabels), **keine LightEmission/Brightness** in GUIs, Team-Create-Netzlast durch Previews; braucht
  Script-Injection-Berechtigung. **REPORTED**
- **UIParticles** (DevForum 3256357, frei): kopiert fast alle ParticleEmitter-Properties, Flipbooks (FPS, ID, Tile-Count), Preset-Preview
  (nur Vorschau, ändert nicht das echte Partikel), Insert-/Update-Modul-Button, Presets überleben Updates. **REPORTED**
- **2D Emitter v2** (Synitx, README VERIFIED): Plugin erzeugt LocalScript; Modul mit Properties Size, Speed, Amount, LifeTime, Color-Liste,
  Acceleration (UDim2), Texture, Rotation; laut Thread nicht mehr gepflegt. **VERIFIED/REPORTED**
- **UIParty** (Novaly-Studios, README VERIFIED): funktionaler Ansatz (Partikeldefinition als Funktion, "Paths" für Sequenzen/Physik),
  Spritesheets; Roadmap u. a. Emissionsformen, framerate-basiertes Downscaling, Multithreading, **Editor-Plugin noch geplant**.
- **ParticleUI** (themwsama, MIT, README VERIFIED): Texturen/Flipbooks, Color/Size/Transparency (fest, Bereich oder Sequence), Burst/Loop.
- **rParticle** (joeldesante, Fork AlexR32; README VERIFIED): minimalistisch, Callbacks OnSpawn/OnUpdate auf RenderStepped.
- ⚑ **Native `ParticleEmitter2D` (VERIFIED, API-Dump 0.745)**: Klasse existiert mit Tag **`NotBrowsable`**, keine Seite in creator-docs (404).
  Properties spiegeln ParticleEmitter in 2D (u. a. Acceleration als Vector2, EmissionMode Point/BoundingBox, EmissionAngle/Offset/Spread,
  Flipbook-Felder inkl. FlipbookSizeX/Y, LockedToParent, ZIndex, Blend, Size-Default 32, Speed-Default 64); Methoden Emit/Clear;
  FastForward nur RobloxScriptSecurity. Eine offizielle Ankündigung wurde **nicht gefunden** → ASSUMPTION: in Entwicklung/unveröffentlicht.
- Quellen: https://devforum.roblox.com/t/emitter2d-convert-any-particleemitter-to-2d-with-the-click-of-a-button/3742009 ,
  https://devforum.roblox.com/t/uiparticles-a-plugin-and-module-for-all-your-ui-particle-needs/3256357 ,
  https://raw.githubusercontent.com/Synitx/2D-Emitter-2/main/README.md , https://raw.githubusercontent.com/Novaly-Studios/UIParticle/main/README.md ,
  https://raw.githubusercontent.com/themwsama/Particle-UI-Module/main/README.md , https://raw.githubusercontent.com/joeldesante/rParticle/master/README.md ,
  /root/tools/ref/Full-API-Dump.json

### 2.13 Lightning Beams (Quasiduck) — Evidenz: VERIFIED (README via npm-Port) + REPORTED (Kritik)

- Procedural Lightning (DevForum 843534, v1.1, 2020), roblox-ts-Port `@rbxts/lightning-beams` 1.1.0-ts.2. **Part-basiert**.
  Features: geschichtetes, bewegtes **Perlin-Noise**, gleichmäßige Disk-Punktverteilung der Kontrollpunkte, **Bezier-Krümmung analog zu
  Beam.CurveSize0/1**, variable Dicke/Länge/Transparenz, ColorSequence mit Laufgeschwindigkeit, Sub-Module **Sparks** und **Explosion**,
  Projektil-Modus. Kinetik über eine **Wellenfunktion** (Pulse Speed/Length, Fade Length, Min/Max Transparency, ContractFrom). Parameter
  u. a. Min/MaxRadius, Frequency, AnimationSpeed, Thickness mit Min/Max-Multiplikator. **VERIFIED**
- Kritik (REPORTED): Destroy-Probleme, Lösch-Loop scheitert bei vielen gleichzeitigen Effekten, Auto-Delete-Loop konterkariert PartCache,
  Heartbeat-Verbindungen kritisiert, FPS-Einbruch bei hohem PartCount + Sparks; Empfehlung: clientseitig über RemoteEvent.
- Quellen: https://registry.npmjs.org/@rbxts/lightning-beams ,
  https://devforum.roblox.com/t/effect-v11-lightning-beams-seamless-smooth-and-procedurally-animated-with-beam-like-properties/843534

### 2.14 Emit-Helfer, Scaler, Sequence-Editoren

- **Jad's Emit Plugin** (DevForum 1986838): emittiert Partikel, Beams, Meshes; EmitDelay auch für Beams; behält **EmitCount/EmitDelay**-Attribute
  bewusst bei, weil Skripter sie nutzen; Bug-Report: emittiert andere Anzahl als im Attribut. **REPORTED**
- **roblox-particle-util** (J1ck, README VERIFIED): Viewport-Overlay bei Selektion, Selektionsmodi Default/Children/Descendants, setzt Emit Count
  und Delay für alle selektierten Partikel ("..." bei gemischten Werten), Attribute heißen **`EmitCount` und `DelayTime`** (abweichend!).
- **Shifty's Particle Emitter Plugin** (DevForum 2661214): UI mit Emit Count, Emit Delay, Emit- und Reset-Button. **REPORTED**
- **ParticleEmitter Scaler** (DevForum 2792643): skaliert Size und Lifetime prozentual über mehrere Emitter; gemischte Reviews. **REPORTED**
- **SmoothSequence Graph** (DevForum 3044286, frei): Keypoints mit **Tangenten**, platziert NumberSequence-Keypoints so, dass der
  **Fehler minimiert** wird; Metadaten als Attribute mit Präfix `SMOOTHSEQUENCE_`. **REPORTED**
- **CSE Pro** (DevForum 2060438): ColorSequence-Editor mit Umkehren und Lua-Export. **REPORTED**
- **"Bezier Sequencer"/"BezierSequence"**: nur als Name in einem YouTube-Tutorial-Listing und in der ROS-Recherche (Konflikt-Plugin) gefunden;
  **keine Feature-Belege** → NOT FOUND.
- **"Particle Emitter Previewer"**: kein Produkt mit diesem Namen gefunden → NOT FOUND. Funktional ähnliche Vorschauen: Roblox' eigenes
  Emit()-Plugin aus dem Explosions-Tutorial, Sine-VFX-Visualizer, VFX Suite Trail Preview, Arc-Scrubbing.

### 2.15 Roblox-Bordmittel (Referenz für UX und Grenzen) — Evidenz: VERIFIED

- **NumberSequence-/ColorSequence-Popups** (creator-docs effects/particle-emitters.md): Klick in den Graph fügt Keypoint ein, Auswahl + Delete
  löscht, **Envelope-Linien** ziehen für Zufallsbereich; ColorSequence: Keypoints mit Farbwähler, ziehen, löschen. **Keine** Bezier-/Easing-,
  Preset-, Multi-Edit- oder Copy/Paste-Funktion dokumentiert. **VERIFIED**
- **ColorSequence: mindestens 2, höchstens 20 Keypoints** (creator-docs datatypes/ColorSequence.yaml). **VERIFIED**. Für NumberSequence wird
  dasselbe Limit im DevForum genannt (Thread 188572 "Increase or remove the NumberSequence Keypoint limit"). **REPORTED**
- Community-Requests (REPORTED): Copy/Paste von Color-/NumberSequences (2795691, 3774862), Multi-Selektion für Sequence-Properties
  (425043, 1071269), vereinfachter Bezier-Modus (3356273), **Plugins sollen eingebaute Value-Editoren nutzen dürfen** (1920538),
  separater Curve Editor + mehr Keypoints (2625485), Curve-Editor-Widget resizable und eigene Min/Max statt Clamping 0–10 (3224754).
- **Animation Editor** (creator-docs animation/editor.md): Media-/Playback-Controls, Track-Liste, Timeline mit Scrubber, Einheit
  **seconds:frames**, Standard **30 fps**, Default-Länge 1 s; Keyframes einfügen/verschieben/duplizieren (Copy/Paste an Scrubber-Position)/löschen;
  Easing-Style und -Direction pro Keyframe (Default Linear, auch Constant); **Animation Events**; **Keyframe-Optimierung** (automatisch: ≥3 gleiche
  Keyframes → nur erster/letzter; on-demand per Slider); **Looping interpoliert nicht** vom letzten zum ersten Keyframe. **VERIFIED**
- **Curve Editor** (creator-docs animation/curve-editor.md): Umschaltung Dope Sheet ↔ Curve Editor, getrennte X/Y/Z-Kanäle, Interpolation
  **Linear / Constant / Cubic** (nur Cubic hat Tangenten), Tangenten-Handles (gesetzt vs. auto), "Set Tangent to Zero", **"Generate Curve"**
  (Bounce/Elastic In/Out/InOut ersetzt Zwischen-Keyframes), KeyframeSequence → CurveAnimation-Konvertierung (Quaternion→Euler irreversibel). **VERIFIED**
- **API-Fakten (VERIFIED, Full-API-Dump 0.745)**: `ParticleEmitter:Emit(particleCount=16)`, `:Clear()` und Property `TimeScale` sind skriptbar
  (Security None); **`:FastForward(numFrames)` ist `RobloxScriptSecurity`** (für Plugins nicht nutzbar). `ParticleFlipbookLayout` enthält
  `Custom` mit `FlipbookSizeX/Y`; `FlipbookBlendFrames` existiert. Klassen `CurveAnimation`, `FloatCurve`, `MarkerCurve`, `KeyframeMarker`
  existieren. Beam: Attachment0/1, CurveSize0/1, Segments, Width0/1, TextureMode/Speed, `SetTextureOffset`; Trail: Lifetime, Min/MaxLength,
  WidthScale, `Clear`.

---

## 3. Querschnittsbefunde

### 3.1 De-facto-Konventionen im Ökosystem
- ⚑ **Emit-Attribute**: `EmitCount` (Burst-Anzahl), `EmitDelay` (Verzögerung), `EmitDuration` (Enabled-Dauer bzw. Klon-Lebensdauer bei
  Beams/Trails). Belegt bei VFX Editor 1.0.9 (VERIFIED), EasyVFX (VERIFIED), VFX Studio (REPORTED, Drittanalyse), Jad's Emit Plugin, Effect
  Designer Suite, "Beziers"-Plugin (REPORTED). **Abweichung**: roblox-particle-util nutzt `DelayTime` (VERIFIED).
- ⚑ **`<Property>Sequence`-Attribute** (NumberSequence auf beliebiger Instanz animiert die gleichnamige Property über die Effektdauer):
  VFX Studio (REPORTED), EasyVFX (VERIFIED).
- **Globale Studio-API über `shared`**: VFX Forge und Phase VFX beide `shared.vfx`, Sine VFX `shared.sv` (REPORTED/VERIFIED). Kollisionsgefahr.
- **Authoring-Metadaten in Attributen**: VFX Editor (Easing/Bezier), SmoothSequence (`SMOOTHSEQUENCE_*`), EasyVFX (`VFX_*`, `VFXBase_*`).
- **Retime/Resize/Recolor** als Standardoperationen (VFX Suite, VFX Forge API, VFX Studio). Semantik laut VFX-Studio-Analyse (REPORTED):
  Lifetime/Rate durch Faktor teilen, Speed/Drag/FlipbookFramerate/RotSpeed/TextureSpeed multiplizieren, Acceleration quadratisch, EmitDelay skalieren.

### 3.2 Funktions-"Baseline" 2026 (was Nutzer inzwischen erwarten) — ASSUMPTION aus 3.1/2.x
Partikel/Beams/Trails + Mesh-/Decal-Flipbooks, 3D-Beziers (Pfade, Beam-Kurven), Lightning, Shockwaves, Camera Shake, Impact Frames/Screen
Effects, Emit-Fenster, Retime/Resize/Recolor, Bezier-Kurveneditor mit Presets, Asset-Bibliothek (tausende Texturen/Flipbooks), Runtime-Emit-Modul,
generierter Trigger-Code, Undo/Redo, Light/Dark-Theme.

### 3.3 Technischer Ansatz: native Instanzen vs. Custom-Systeme
- Native ParticleEmitter/Beam/Trail dominieren bei allen erfolgreichen Authoring-Tools. Custom-Systeme (Lumina, VortexFX, Flare Craft, UI-Partikel)
  liefern Features wie Kollision, Mesh-Partikel, Node-Logik, sind aber durchweg **performance-kritisiert** und oft **unmaintained**. REPORTED
- Part-basierte Spezialeffekte (Lightning Beams, EasyVFX-Geometrie, Debris/Crater) sind verbreitet; gute Praxis: **Client-Rendering**,
  **eine Update-Schleife**, Pooling, Qualitätsstufen, garantierte Aufräumlogik. VERIFIED (EasyVFX) / REPORTED (Lightning-Kritik)

### 3.4 KI-/Agent-Integration im Wettbewerb
- EasyVFX: Claude-Code-Plugin, headless Lune-Recorder + Re-Simulation, Budget-Gates, Baseline-Diffs (VERIFIED).
- Arc: Drittanbieter-MCP-Server mit Localhost-Bridge (VERIFIED für die Erweiterung).
- ASSUMPTION: ASTRA ist mit "Claude kann Effekte als Dateien erzeugen" **nicht mehr allein**; Differenzierung muss über Schema-Qualität,
  Validierung, deterministische Runtime, Timeline und Performance-Analyse kommen.

---

## 4. Einschränkungen / Kritik (gesammelt)

- **UI/UX**: zu kleine, nicht skalierbare UI (VFX Suite); Studio wirkt überladen; Plugins lassen sich nicht deaktivieren (ROS, siehe Nachbar-Notiz);
  Lernkurve → Lightweight-Mode (VFX Editor). REPORTED
- **Re-Editing**: bestehende Effekte lassen sich schwer wieder ins Tool laden (VFX Suite); Editoren an ein einzelnes Partikel gebunden (VFX Editor). REPORTED
- **Datenverlust-Risiko**: Kurvenmetadaten in Attributen gehen verloren/werden zurückgesetzt (VFX Editor, VERIFIED); SmoothSequence warnt vor Re-Edit. REPORTED
- **Eingabe-Bugs**: ".1" nicht akzeptiert, Rundungsprobleme (VFX Editor). REPORTED/VERIFIED
- **Stabilität/Memory**: Memory-Leaks und rekursive State-Fehler in Fusion-UI (VFX Editor Changelog, VERIFIED); Crashs bei Texturen (REPORTED).
- **Performance**: Custom-Partikel deutlich langsamer (Lumina, VortexFX, Flare Craft, Emitter2D); Heartbeat pro Objekt/Property (Lightning Beams,
  VFX Studio-Analyse). REPORTED
- **Timeline-Lücke**: kein Sequencer in VFX Forge; Moon-Exporte erfordern Zusatztools, 4–6 h Portierungsaufwand (REPORTED).
- **Pflege**: Flare Craft, 2D Emitter v2, VortexFX v1, Lumina faktisch inaktiv bzw. im Rewrite. REPORTED
- **Lizenzen**: VFX Forge Emit-Modul nur in Roblox-Spielen nutzbar (VERIFIED); VortexFX eigene Lizenz (VERIFIED); viele Store-Plugins proprietär.
- **Preis/Kauf**: Zurückhaltung beim Kauf bezahlter Plugins wegen Roblox' Echtgeld-Abwicklung; Free-Konkurrenz (VFX Studio, Effect Designer Suite,
  Arc, EasyVFX) setzt Preisdruck. REPORTED

---

## 5. Konsequenzen für ASTRA

1. ⚑ **Interop-Schicht für Community-Konventionen** (IDEA): Importer liest `EmitCount`/`EmitDelay`/`EmitDuration` (+ Alias `DelayTime`) und
   `<Property>Sequence`-Attribute und übersetzt sie in ASTRA-Timeline-Events/Tracks. Exporter kann optional "kompatible Instanzen" schreiben,
   damit ASTRA-Effekte auch mit VFX Forge/VFX Studio/EasyVFX-Emittern abspielbar sind. Die ASTRA-Runtime selbst liest aber **nur das ASTRA-Format**.
2. ⚑ **JSON-Effektdatei als Source of Truth für Kurven** (IDEA): Bezier/Easing-Definitionen werden im Schema gespeichert und erst beim Bauen in
   NumberSequence/ColorSequence (≤ 20 Keypoints) **gebacken** – mit fehlerminimierender Keypoint-Platzierung (adaptive Abtastung) und
   Anzeige des Approximationsfehlers. Attribute dienen höchstens als Cache/Back-Reference, nie als einzige Quelle.
3. ⚑ **Timeline-Scrubbing nativer Emitter ohne FastForward** (IDEA): Strategie aus (a) `TimeScale=0` zum Einfrieren, (b) `Clear()` + deterministisches
   Re-Emittieren der seit Effektstart fälligen Bursts beim Rückwärtsspringen, (c) optionalem "Ghost"-Vorschau-Simulator für exakte Frames (Pfad-Gizmos).
   Muss in Phase 3 prototypisch verifiziert werden (siehe Offene Fragen: wie Arc das löst).
4. ⚑ **Runtime-Architektur** (IDEA, gestützt auf EasyVFX/Lightning-Kritik): clientseitige Wiedergabe, ein zentraler Scheduler (eine RenderStepped/
   Heartbeat-Verbindung für alle laufenden Effekte), Instanz-Pooling, harte Budgets (Partikel, Parts, Beams, Lights), Qualitätsstufen, garantierter
   Cleanup per Handle (Stop/Cancel/Finished), Effekte unabhängig mehrfach abspielbar, `Archivable=false` für temporäre Objekte.
5. **Native zuerst, Custom nur gezielt** (IDEA): Standardpfad ParticleEmitter/Beam/Trail; Part-/Mesh-basierte Layer (Lightning, Shockwave, Debris,
   Mesh-Flipbooks) als eigene Komponententypen mit Budget-Warnungen im Performance-Analyzer; **kein** allgemeines Custom-Partikelsystem in v1.
6. ⚑ **Feature-Parität zur 2026-Baseline** (IDEA): Komponentenliste mindestens Particle, Beam, Trail, Mesh-Flipbook, Decal-Flipbook, Bezier-Pfad,
   Lightning, Shockwave/Ring, Camera Shake, Impact Frame/Screen Effect (ColorCorrection, Blur), Light, Sound; Operationen Retime/Resize/Recolor
   als **reine, getestete Transformationen auf dem JSON-Modell** (Replace/Multiply, HDR-Faktor beachten).
7. **Animation-Kopplung** (IDEA): Runtime-API zum Binden an `AnimationTrack`-Marker (KeyframeMarker/Animation Events) und optional Importer für
   Moon-Animator-2- bzw. Eclipse-Event-Daten in späterer Phase; Effekt-Offsets relativ zu Rig-Teilen (Parent/Offset) im Schema vorsehen.
8. **Namespace-Hygiene** (IDEA): keine Nutzung von `shared.vfx`; falls eine globale Studio-API nötig ist, eindeutiger Name (z. B. `shared.AstraVFX`)
   oder besser ein ModuleScript-Zugriff. Branding nie zu "VFX Studio" verkürzen (Kollision mit XxOmqxXNerds Plugin, 800+ Votes).
9. **Inspector-UX** (IDEA aus VFX Editor/VFX Suite): virtualisierte Listen, Multi-Selektion mit semantischer Typprüfung, Copy/Paste von Sequences,
   Lightweight-Modus, skalierbare UI (UI-Scale-Setting), Opt-in-Aktivierung (Plugin bleibt passiv, bis geöffnet), konsistente Dezimaleingabe
   (".1", Komma/Punkt), konfigurierbare Max-Werte jenseits der Studio-Slider, Kurven-Presets (26+ Easings, "von A nach B mit N Punkten").
10. **Farbinterpolation** (IDEA, inspiriert von Effect Designer Suite): beim Backen von Gradienten Option für Oklab-Interpolation, da Roblox zwischen
    Keypoints linear in RGB interpoliert (ASSUMPTION) – zusätzliche Keypoints erzeugen wahrgenommene Oklab-Verläufe.
11. ⚑ **Claude-Workflow differenzieren** (IDEA): versioniertes JSON-Schema + CLI-Validator + deterministische Runtime unter Lune testbar; headless
    "Census" je Frame (Anzahl Partikel/Beams/Lights, Dauer, Clean-End) als Performance-Gate – konzeptionell ähnlich EasyVFX, aber eigene Umsetzung.
    Eine MCP-/Localhost-Bridge ist optional und darf den dateibasierten Weg nicht ersetzen (HTTP-Permission-Hürde in Studio).
12. **UI-Partikel abstrahieren** (IDEA): ASTRA-Komponente "UIEmitter" mit Backend-Adapter – zunächst ImageLabel-basiert mit strikten Budgets,
    später Umstieg auf native `ParticleEmitter2D`, sobald veröffentlicht; Schema an dessen Property-Namen anlehnen.
13. **Lizenz-/Clean-Room-Regel**: keine Übernahme von Code/Assets aus VFX Forge, VFX Studio, VortexFX oder anderen; auch MIT-Projekte (VFX Editor,
    EasyVFX, Lumina, ParticleUI) nur als Konzeptreferenz. Eigene Texturen/Presets erstellen.

---

## 6. Offene Fragen

- Wie realisiert **Arc** das Rückwärts-Scrubbing der Partikelvorschau (eigene Simulation oder Clear/Re-Emit)? Thread-Inhalt nicht lesbar.
- Wann und in welcher Form wird **`ParticleEmitter2D`** veröffentlicht (Beta? nur UI? LightEmission-Support)?
- Ist das 20-Keypoint-Limit für **NumberSequence** offiziell dokumentiert (für ColorSequence ja)? Zur Sicherheit im Validator per Laufzeittest prüfen.
- Exakte Semantik von `EmitDuration` für Beams/Trails und ob `EmitCount` bei Beams ignoriert wird – Plugins widersprechen sich teils
  (eine Drittdoku beschreibt Attribute fehlerhaft).
- Aktuelle Preise, Versionen und Wartungsstatus (VFX Suite, Sine VFX, Phase VFX, Effect Designer Suite) – Store-Seiten nicht erreichbar.
- Ist die sytranom-Doku die offizielle Doku von VFX Studio (XxOmqxXNerd)?
- Stabilität der **Eclipse-Animator-Event-Datenstruktur** (Schema-Version) und rechtliche Lage beim Lesen von Moon-`.xsixx`-/Eclipse-Saves für einen Importer.
- Gibt es Plugin-APIs, um Studios eingebaute Sequence-Editoren wiederzuverwenden? (Feature-Request 1920538 deutet auf **nein**.)
- Wie viele native ParticleEmitter/Partikel verträgt ein Mobilgerät realistisch – Budgets für den Performance-Analyzer brauchen eigene Messungen.

---

## 7. Quellen

Offiziell / lokal (VERIFIED):
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/particle-emitters.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/editor.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/animation/curve-editor.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/ColorSequence.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/NumberSequence.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/ParticleEmitter2D.yaml (404 = keine Doku)
- /root/tools/ref/Full-API-Dump.json, /root/tools/ref/globalTypes.d.luau (Engine 0.745.0.7451137)

Produkt-eigene Quellen (VERIFIED):
- https://raw.githubusercontent.com/VirtualButFake/vfx-editor/main/README.md , .../CHANGELOG.md , https://raw.githubusercontent.com/wiki/VirtualButFake/vfx-editor/Home.md
- https://raw.githubusercontent.com/zilibobi/forge-vfx/main/README.md , https://registry.npmjs.org/@zilibobi/forge-vfx (Typdeklaration 2.4.0)
- https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/README.md , .../docs/agentic-loop.md , .../docs/eclipse-animator.md , .../docs/vfx-studio-analysis.md , .../CHANGELOG.md
- https://raw.githubusercontent.com/Mqxsyy/Lumina/main/README.md , .../package.json , https://raw.githubusercontent.com/Mqxsyy/LuminaDocs/main/sidebars.ts (+ docs/nodes/*.md)
- https://raw.githubusercontent.com/FancyDucc/3D-Particle-System/main/README.md
- https://registry.npmjs.org/@rbxts/lightning-beams (README des Ports)
- https://raw.githubusercontent.com/GamesGG0/Moon-Animator-VFX-Exporter/main/README.md , https://raw.githubusercontent.com/GuHamYaiXD/MoonVFXComplier/main/README.md
- https://raw.githubusercontent.com/J1ck/roblox-particle-util/main/README.md
- https://raw.githubusercontent.com/Synitx/2D-Emitter-2/main/README.md , https://raw.githubusercontent.com/Novaly-Studios/UIParticle/main/README.md ,
  https://raw.githubusercontent.com/themwsama/Particle-UI-Module/main/README.md , https://raw.githubusercontent.com/joeldesante/rParticle/master/README.md
- https://raw.githubusercontent.com/Joojjuuk/plugin-studio/main/README.md

Community / Store (REPORTED):
- https://devforum.roblox.com/t/introducing-the-vfx-suite-plugin/2545686 · https://create.roblox.com/store/asset/14328968969/VFX-Suite
- https://devforum.roblox.com/t/vfx-editor-all-your-vfx-needs-in-one/3103467 · https://create.roblox.com/store/asset/18800449515/VFX-Editor
- https://devforum.roblox.com/t/plugin-vfx-forge-an-advanced-custom-vfx-system/3867553 · https://zilibobi.itch.io/vfx-forge · https://create.roblox.com/store/asset/133927382668067/VFX-Forge
- https://create.roblox.com/store/asset/135581141962270/VFX-Studio · https://sytranom.github.io/vfx-studio-docs/
- https://devforum.roblox.com/t/arc-a-vfx-animation-plugin/4903133 · https://create.roblox.com/store/asset/118257542877059/Arc
- https://create.roblox.com/store/asset/78798609925417/Phase-VFX · https://phase-doc.vercel.app/
- https://devforum.roblox.com/t/plugin-sine-vfx-a-vfx-plugin-for-roblox-studio/4803771 · https://sinevfx.xyz/
- https://devforum.roblox.com/t/effect-designer-suite-%E2%80%94-vfx-tooling-assets-and-more/4754553
- https://devforum.roblox.com/t/beziers-advanced-modular-vfx-plugin-10000-assets-add-ons/4180222
- https://devforum.roblox.com/t/vfx-scripter-pro-%E2%80%94-an-essential-plugin-for-vfx-scripters/2961973
- https://devforum.roblox.com/t/steakparticles-plugin-for-creating-vfx-and-particle-emitters/2908779
- https://devforum.roblox.com/t/update-020-lumina-a-custom-particle-system/2963557
- https://devforum.roblox.com/t/vortexfx-v106-a-3d-particle-system-for-all-your-3d-particle-needs/3131414
- https://devforum.roblox.com/t/new-particle-system-flare-craft/2539746
- https://devforum.roblox.com/t/emitter2d-convert-any-particleemitter-to-2d-with-the-click-of-a-button/3742009
- https://devforum.roblox.com/t/uiparticles-a-plugin-and-module-for-all-your-ui-particle-needs/3256357
- https://devforum.roblox.com/t/plugin-2demitter-v2-basic-ui-particle-emitter/2156359
- https://devforum.roblox.com/t/effect-v11-lightning-beams-seamless-smooth-and-procedurally-animated-with-beam-like-properties/843534
- https://devforum.roblox.com/t/dear-vfx-makers-i-present-to-you-jads-emit-plugin/1986838
- https://devforum.roblox.com/t/shiftys-particle-emitter-plugin/2661214
- https://devforum.roblox.com/t/scale-particleemitters-uniformly-fast-particleemitter-scaler-plugin/2792643
- https://devforum.roblox.com/t/smoothsequence-graph-the-easiest-way-to-edit-numbersequences/3044286
- https://devforum.roblox.com/t/cse-pro-supercharged-colorsequence-editor/2060438
- https://devforum.roblox.com/t/getting-started-with-moon-animator-2-unofficial/476330 · https://create.roblox.com/store/asset/4725618216/Moon-Animator-2
- https://devforum.roblox.com/t/motion-151-%E2%80%94-timeline-editor-animator/4274872
- https://devforum.roblox.com/t/visulie-%E2%94%80-a-novel-all-purpose-animation-data-and-effects-suite/3582453
- https://create.roblox.com/store/asset/86116556258301/Eclipse-Animator
- Feature-Requests: https://devforum.roblox.com/t/-/2795691 · https://devforum.roblox.com/t/let-us-edit-multiple-sequence-properties-at-a-time/425043 ·
  https://devforum.roblox.com/t/simplified-bezier-curve-editor-mode-for-number-sequence-editing/3356273 ·
  https://devforum.roblox.com/t/allow-plugins-to-use-value-editorspickers/1920538 ·
  https://devforum.roblox.com/t/separate-curve-editor-detached-from-animation-editor/2625485 ·
  https://devforum.roblox.com/t/curve-editor-widget-needs-some-ux-improvements/3224754 ·
  https://devforum.roblox.com/t/increase-or-remove-the-numbersequence-keypoint-limit/188572
- YouTube-Listing mit "BezierSequence": https://m.youtube.com/watch?v=TrFiKIr7K-4
