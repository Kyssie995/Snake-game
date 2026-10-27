# Feature-Vergleich: Roblox-VFX-Werkzeuge, Profi-Referenzen und ASTRA (geplant)

Stand: 2026-10-27 · Phase 1 (Research & Architecture) · Grundlage: die neun Recherche-Notizen in `docs/research/`
inklusive ihrer Abschnitte „Verifikation (unabhängige Prüfung)“. **Wo der Verifier eine Aussage korrigiert hat, gilt
die Korrektur.** Kein Evidenz-Label wurde gegenüber den Notizen hochgestuft.

## 1. Zweck und Quellenlage

Dieses Dokument ist eine **prüfbare** Merkmalsmatrix. Jede Zelle außer „?“ ist in Abschnitt 9 („Belege je Spalte“)
mit Zeilennummer, Aussage und Quelle hinterlegt. Die Matrix vergleicht

- alle in der Recherche untersuchten Roblox-Plugins und -Module, **für die es Belege gibt**,
- die Roblox-Studio-Bordmittel als Basislinie,
- Unity Visual Effect Graph und Unreal Niagara als Profi-Referenz,
- „ASTRA (geplant)“: den Plan aus `docs/ARCHITECTURE.md` plus Ideen aus der Recherche. Diese Spalte enthält
  **keine Fakten über ein existierendes Produkt**, sondern Absichten (Marker I bzw. I\*). Laut `docs/PROGRESS.md` ist
  davon fast nichts implementiert und nichts in Studio getestet.

**Quellenlage.** DevForum, Creator Store, YouTube, itch.io, github.com-Webseiten und mehrere Doku-Seiten (`*.github.io`,
`qwinkleparticles2.com`, `phase-doc.vercel.app` u. a.) waren aus der Sandbox gesperrt. Alles von dort stammt aus
WebSearch-Snippets und ist höchstens **B (berichtet)**. Direkt lesbar waren `raw.githubusercontent.com` (READMEs,
CHANGELOGs, Lizenzen, Roblox creator-docs, Unity-Doku-Quelltext), die npm-Registry und der lokale API-Dump
`0.745.0.7451137`. Für **Niagara** war keine Quelle erreichbar: Alle Niagara-Zellen sind Modellwissen (A) und vor einer
Entscheidung gegen `https://dev.epicgames.com/documentation/en-us/unreal-engine/` zu prüfen.

Nicht aufgenommen, weil keine Feature-Belege existieren: „Bezier Sequencer“/„BezierSequence“ (nur als Name und
Asset 8133535339 in einem Video-Listing) und „Particle Emitter Previewer“ (kein Produkt gefunden).

## 2. Legende

| Zeichen | Bedeutung |
|---|---|
| ✓ | Merkmal vorhanden (laut Beleg) |
| ✗ | Merkmal fehlt – nur gesetzt, wenn eine Quelle das Fehlen aussagt (B/V) oder die Abwesenheit in allen Quellen als Annahme festgehalten ist (A) |
| teilweise | eingeschränkt vorhanden; die Einschränkung steht im Beleg |
| ? | unbekannt, kein Beleg in die eine oder andere Richtung. **Fehlende Erwähnung ist kein ✗.** Es wird nie geraten. |
| n. a. | nicht anwendbar (z. B. „native ParticleEmitter“ bei Unity/Unreal) |

| Marker | Bedeutung |
|---|---|
| **V** | VERIFIED / verifiziert: eigenes README, Paket oder Produktseite des Herstellers, offizielle Roblox- oder Unity-Doku, lokaler API-Dump 0.745 |
| **B** | REPORTED / berichtet: DevForum, Store-Snippets, Drittanalysen, Such-Zusammenfassungen, X-Posts |
| **A** | ASSUMPTION / Annahme: eigene Schlussfolgerung oder ungeprüftes Modellwissen |
| **I** | IDEA / eigene Idee – **nur in der ASTRA-Spalte**: in `ARCHITECTURE.md` festgelegter Plan |
| **I\*** | IDEA – nur als Idee in den Recherche-Notizen, **noch nicht** in `ARCHITECTURE.md` |

Regeln: Eine Zelle trägt das Label der Aussage, auf der ihr Wert beruht; stützen mehrere Aussagen den Wert, gilt die
schwächste, die für den Wert nötig ist. Zeile 30 (Preis/Lizenz) enthält Kurztext plus Marker, Details in Abschnitt 6.
Sammelspalten (UI-Partikel-Module) bedeuten „mindestens ein Modul der Gruppe“; der Beleg nennt das Modul.

## 3. Gemeinsame Engine-Grenzen (gelten für alle Roblox-Spalten)

Diese Fakten erklären viele „teilweise“-Zellen. Details: `docs/research/api-particles-beams-trails.md`,
`api-geometry-lighting-tween.md`, `api-studio-plugin.md`, `vfx-design-performance.md`.

| Grenze | Label | betrifft Zeilen | Quelle |
|---|---|---|---|
| `ParticleEmitter` hat keinen Seed, keine Per-Partikel-Events, keinen Zugriff auf Partikelzustände; `FastForward` ist `RobloxScriptSecurity`; `TimeScale` reicht von 0 bis 1. Native Partikel lassen sich daher weder exakt seeken noch rückwärts scrubben. | V | 13, 16, 17 | API-Dump 0.745; https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/ParticleEmitter.yaml |
| `NumberSequence`/`ColorSequence`: mindestens 2, höchstens 20 Keypoints, erste Zeit 0, letzte 1, nicht absteigend; lineare Interpolation (Farben in RGB); Envelope symmetrisch, ≥ 0 | V | 4, 5 | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/NumberSequence.yaml, …/ColorSequence.yaml |
| Lifetime intern auf 20 s gekappt; bis 400 Partikel/s pro Emitter (100/s auf Mobile, laut Doku im `Rate`-Abschnitt); `FlipbookFramerate` max. 30 fps; Clients mit wenig Speicher deaktivieren Flipbooks | V | 7, 27, 28 | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/particle-emitters.md |
| Flipbook-Texturgröße widersprüchlich dokumentiert (1024² vs. „exaktes Vielfaches“ vs. 8–1024 vs. 4096-Beta); Kompatibilität für Plugins nicht abfragbar | V (Widerspruch) / B (Beta) | 7 | ParticleFlipbookTextureCompatible.yaml; https://devforum.roblox.com/t/client-beta-optimize-your-particle-animations-with-custom-flipbook-layouts/4005128 |
| Beam-Breite nur linear (`Width0`→`Width1`); Trail-Breite = Attachment-Abstand × `WidthScale` (0–1); Beam und Trail haben kein `TimeScale` | V | 8, 9, 13 | Beam.yaml, Trail.yaml (creator-docs) |
| `MeshPart.MeshId`/`MeshContent` haben Write-Security `NotAccessibleSecurity` (auch für Plugins); `SpecialMesh.MeshId` ist frei schreibbar | V | 10 | API-Dump 0.745; MeshPart.yaml, SpecialMesh.yaml |
| `Tween` hat kein Seek; die Doku-Liste tweenbarer Typen ist nicht abschließend („including“), Sequenz-Typen stehen nicht darin | V | 13, 14 | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/TweenService.yaml |
| `ViewportFrame` rendert keine ParticleEmitter, Beams, Trails (noch im Juni 2026 als Feature-Request) | B | 18 | https://devforum.roblox.com/t/add-support-for-particle-emitters-in-viewportframes/4706068 |
| Plugins: keine Zwischenablage, kein freies Dateischreiben (nur Dialoge); HTTP zu `localhost`/`127.0.0.1` ausdrücklich erlaubt; `CreateWebStreamClient` (WebSocket) nur in Studio, max. 4 Clients | V | 22, 23, 29 | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/cloud-services/http-service.md; HttpService.yaml |
| Ob `Heartbeat`/`PreRender` im reinen Edit Mode für Plugin-Code feuern, ist nicht dokumentiert; `TimeScale`-Fehler in Studio wurden 2023/2024 gemeldet | A (unbelegt) / B | 17 | RunService.yaml; https://devforum.roblox.com/t/particleemitters-timescale-does-not-visibly-change-in-studio/2221218 |
| Highlights: max. 255 pro Client, auch deaktivierte belegen einen Slot | V | 12, 27 | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/highlighting.md |
| Engine-eigenes LOD für Rate und Beam-Segmente (Formel inoffiziell; Bug-Report Aug. 2026: Rate-Skalierung greift nicht); Effektivqualität bei „Automatic“ nicht lesbar | B / V | 28 | https://devforum.roblox.com/t/particle-emitters-no-longer-change-rate-with-graphics-quality/4834736; DataModel.yaml |
| Creator Store beschränkt obfuszierten Code, `require(assetId)`, `loadstring`, `InsertService:LoadAsset` u. a. | V | 30 | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/production/creator-store.md |
| Änderungen an `Script.Source` erfasst `ChangeHistoryService` absichtlich nicht (Staff „Working as Designed“) | B | 19, 22 | https://devforum.roblox.com/t/changes-to-luasourcecontainersource-are-not-captured-by-changehistoryservice/4590702 |

## 4. Merkmalsdefinitionen (Zeilen)

| Nr. | Merkmal | ✓ bedeutet |
|---|---|---|
| 1 | Native ParticleEmitter | Das Werkzeug bearbeitet Properties echter `ParticleEmitter`-Instanzen (nicht nur eigene Custom-Partikel). |
| 2 | Multi-Emitter-Edit | Gleiche Property mehrerer Emitter in einem Schritt ändern (Inspector-Mehrfachauswahl oder Werkzeug, das auf alle Selektierten wirkt). |
| 3 | Emit-/Burst-Steuerung | Bursts auslösen bzw. Emit-Parameter (Anzahl, Verzögerung, Dauer) verwalten, z. B. `EmitCount`/`EmitDelay`/`EmitDuration`. |
| 4 | Sequenz-Kurveneditor | Editor für `NumberSequence`/`ColorSequence` (bzw. Lebenszeit-Kurven bei Profi-Tools). |
| 5 | Bezier-/Easing-Kurven | Werteverläufe mit Bezier-Handles oder Easing-Stilen (statt nur linearer Keypoints). |
| 6 | 3D-Bezier-Pfade | Räumliche Kurven für Bewegung oder Formen (z. B. Bewegungsbahnen, gekrümmte Beams). |
| 7–11 | Flipbooks, Beams, Trails, Mesh-VFX, Lichter | Das Werkzeug unterstützt diesen VFX-Baustein ausdrücklich. |
| 12 | Kamera-/Screen-Effekte | Camera Shake, Impact Frames, Bloom/ColorCorrection/Blur als Effekt-Bausteine. |
| 13 | Timeline/Sequencing | Zeitachse über die **Effektzeit** mit mehreren Spuren bzw. Keyframes (nicht nur Lebenszeit-Kurven einzelner Partikel). |
| 14 | Keyframes beliebiger Properties | Beliebige Properties über die Effektzeit animieren. |
| 15 | Node-Graph-Logik | Visueller Graph für Ablauf- oder Datenlogik. |
| 16 | Events/Trigger | Benannte Events, Marker oder Trigger, die Logik auslösen (inkl. Partikel-Events wie OnHit/OnDeath). |
| 17 | Live-Vorschau (Workspace) | Vorschau im 3D-Viewport bzw. in der Szene, inklusive Emit/Wiedergabe oder Bahn-Gizmos. |
| 18 | Isolierte Vorschau | Vorschau in einem eigenen Fenster (ViewportFrame o. ä.). |
| 19 | Undo/Redo | Rückgängig/Wiederholen für Werkzeug-Aktionen. |
| 20 | Presets/Bibliothek | Effekt-, Kurven- oder Texturvorlagen bzw. Asset-Bibliothek. |
| 21 | Bulk-Ops | Retime, Resize, Recolor oder Bulk-Arithmetik über Effektteile hinweg. |
| 22 | Speichern/Laden, Re-Edit | Kompositionen speichern und bestehende Effekte verlustfrei wieder bearbeiten. |
| 23 | JSON-/Textformat | Effekt (oder Teile) als Text austauschbar (JSON, Share-Code, Luau-Daten). |
| 24 | Runtime-Player-Modul | Modul, das Effekte im veröffentlichten Spiel abspielt. |
| 25 | Export als Model | Effekt als Roblox-Model/`.rbxm` exportierbar bzw. selbst ein Model. |
| 26 | Scripting-API | Dokumentierte API zum Auslösen/Steuern aus eigenem Code (inkl. Code-Generator). |
| 27 | Performance-Analyse | Kosten anzeigen, warnen oder messen (Zähler, Budgets, Profiler). |
| 28 | Qualitätsprofile/LOD | Qualitätsstufen, Skalierung oder LOD/Culling für Effekte. |
| 29 | KI-/Agent-Workflow | Integration für KI-Agenten (Claude-Code-Plugin, MCP, headless Prüf-Loop). |
| 30 | Preis/Lizenz | Kurzangabe; Details in Abschnitt 6. |

## 5. Merkmalsmatrix

Aus Platzgründen ist die Matrix in sechs Blöcke mit **identischen Zeilen** geteilt. Der Link im Spaltenkopf führt
zum Beleg der Spalte (Abschnitt 9).

### 5.1 Block M1 – etablierte All-in-one-Plugins

| Nr. | Merkmal | ROS Particle Editor [F1](#f1) | Qwinkle's Particles 2 (QP2) [F2](#f2) | VFX Suite [F3](#f3) | VFX Editor [F4](#f4) | VFX Forge [F5](#f5) | VFX Studio (XxOmqxXNerd) [F6](#f6) |
|---|---|---|---|---|---|---|---|
| 1 | Native ParticleEmitter | teilweise B | teilweise B | ✓ B | ✓ V | ✓ B | teilweise B |
| 2 | Multi-Emitter-Edit | ✓ B | teilweise V | ? | ✓ V | ? | ? |
| 3 | Emit-/Burst-Steuerung | ? | ✓ V | ✓ B | ✓ V | ✓ V | ✓ B |
| 4 | Sequenz-Kurveneditor | ? | ✓ V | ✓ B | ✓ V | ? | ? |
| 5 | Bezier-/Easing-Kurven | ? | ✓ V | ✓ B | ✓ V | ✓ B | ? |
| 6 | 3D-Bezier-Pfade | ? | ? | ? | ? | ✓ B | ✓ B |
| 7 | Flipbooks | ? | ✓ V | ? | teilweise V | ✓ B | ? |
| 8 | Beams | ? | ✓ V | ✓ B | ? | ✓ B | ? |
| 9 | Trails | ? | ✓ V | ✓ B | ? | ✓ B | ? |
| 10 | Mesh-VFX | ? | ✓ V | ? | ? | ✓ B | ? |
| 11 | Lichter | ? | ✓ V | ? | ? | ? | ? |
| 12 | Kamera-/Screen-Effekte | ? | ✓ V | ? | ? | ✓ B | ✓ B |
| 13 | Timeline/Sequencing | ? | ✗ A | ? | ? | ✗ B | ? |
| 14 | Keyframes beliebiger Properties | ? | teilweise V | ? | ? | ? | teilweise B |
| 15 | Node-Graph-Logik | ? | ✗ A | ? | ? | ? | ? |
| 16 | Events/Trigger | ? | ✓ V | ? | ? | ? | ? |
| 17 | Live-Vorschau (Workspace) | teilweise B | ✓ V | teilweise B | ? | ? | ? |
| 18 | Isolierte Vorschau | ? | ? | ? | ? | ? | ? |
| 19 | Undo/Redo | ? | ✓ V | ✓ B | ✓ V | ? | ? |
| 20 | Presets/Bibliothek | ? | ✓ V | teilweise B | teilweise V | ✓ B | ? |
| 21 | Bulk-Ops | ? | ✓ V | ✓ B | ? | ✓ V | ✓ B |
| 22 | Speichern/Laden, Re-Edit | ? | teilweise V | ✗ B | teilweise V | ? | teilweise B |
| 23 | JSON-/Textformat | ? | teilweise B | ? | teilweise V | ? | ✗ B |
| 24 | Runtime-Player-Modul | ? | ✓ V | ? | ? | ✓ V | ? |
| 25 | Export als Model | ? | ✓ V | ? | ? | ? | ? |
| 26 | Scripting-API | ? | ✓ V | ? | ? | ✓ V | teilweise B |
| 27 | Performance-Analyse | ? | teilweise B | ? | ? | ? | ? |
| 28 | Qualitätsprofile/LOD | ? | ? | ? | ? | ? | ? |
| 29 | KI-/Agent-Workflow | ? | ? | ? | ? | ? | ? |
| 30 | Preis/Lizenz | ? | kostenpfl., proprietär V | kostenpfl. B | frei, MIT V | kostenpfl. B | frei B |

### 5.2 Block M2 – neuere All-in-one-Plugins und KI-orientierte Werkzeuge

| Nr. | Merkmal | Phase VFX [F7](#f7) | Sine VFX [F8](#f8) | Effect Designer Suite [F9](#f9) | Beziers (vfxer) [F10](#f10) | EasyVFX [F11](#f11) | VFX Scripter Pro [F12](#f12) | SteakParticles [F13](#f13) |
|---|---|---|---|---|---|---|---|---|
| 1 | Native ParticleEmitter | ✓ B | ✓ B | teilweise B | teilweise B | teilweise V | ? | teilweise B |
| 2 | Multi-Emitter-Edit | ? | ? | ? | ? | ? | ? | ? |
| 3 | Emit-/Burst-Steuerung | ✓ B | ✓ B | ✓ B | ✓ B | ✓ V | ? | ? |
| 4 | Sequenz-Kurveneditor | ✓ B | ✓ B | teilweise B | ? | ? | ? | ? |
| 5 | Bezier-/Easing-Kurven | ? | ? | ? | ? | ? | ? | ? |
| 6 | 3D-Bezier-Pfade | ✓ B | ? | ✓ B | teilweise B | teilweise V | ? | ? |
| 7 | Flipbooks | ✓ B | ? | ✓ B | ? | ? | ? | ? |
| 8 | Beams | ✓ B | ✓ B | ? | ✓ B | ✓ V | ? | ? |
| 9 | Trails | ✓ B | ✓ B | ? | ✓ B | ? | ? | ? |
| 10 | Mesh-VFX | ✓ B | teilweise B | ? | ✓ B | ✓ V | ? | ? |
| 11 | Lichter | ? | ? | ? | ✓ B | ✓ V | ? | ? |
| 12 | Kamera-/Screen-Effekte | ✓ B | ? | ? | ✓ B | ✓ V | ? | ? |
| 13 | Timeline/Sequencing | ? | ? | ? | ? | teilweise V | ? | ? |
| 14 | Keyframes beliebiger Properties | ? | ? | ? | teilweise B | teilweise V | ? | ? |
| 15 | Node-Graph-Logik | ? | ? | ? | ? | ? | ? | ? |
| 16 | Events/Trigger | ? | ? | ? | ? | ✓ V | ? | ? |
| 17 | Live-Vorschau (Workspace) | ? | ✓ B | ? | ? | ? | ✓ B | ? |
| 18 | Isolierte Vorschau | ? | ? | ? | ? | ? | ? | ? |
| 19 | Undo/Redo | ? | ? | ? | ? | ? | ? | ? |
| 20 | Presets/Bibliothek | ✓ B | ✓ B | ✓ B | ✓ B | ✓ V | ? | ✓ B |
| 21 | Bulk-Ops | ? | ✓ B | teilweise B | ? | ? | ? | ? |
| 22 | Speichern/Laden, Re-Edit | ? | ? | ? | ? | teilweise V | ? | ? |
| 23 | JSON-/Textformat | ? | ? | ? | ? | ✓ V | ? | ? |
| 24 | Runtime-Player-Modul | ✓ B | ✓ B | ? | ✓ B | ✓ V | ? | ? |
| 25 | Export als Model | ? | ? | ? | ? | ? | ? | ? |
| 26 | Scripting-API | ✓ B | ✓ B | ? | ✓ B | ✓ V | teilweise B | ? |
| 27 | Performance-Analyse | ? | teilweise B | ? | ? | teilweise V | ? | ? |
| 28 | Qualitätsprofile/LOD | ? | ? | ? | ? | ✓ V | ? | ? |
| 29 | KI-/Agent-Workflow | ? | ? | ? | ? | teilweise V | ? | ? |
| 30 | Preis/Lizenz | ? | kostenpfl. B | frei, Open Source B | ? | frei, MIT V | frei B | ? |

### 5.3 Block M3 – Timeline- und Sequencer-Werkzeuge

| Nr. | Merkmal | Moon Animator 2 (+ Exporter) [F14](#f14) | Arc [F15](#f15) | Motion [F16](#f16) | Visulie [F17](#f17) | Eclipse Animator [F18](#f18) |
|---|---|---|---|---|---|---|
| 1 | Native ParticleEmitter | ? | ✓ B | ? | teilweise B | ? |
| 2 | Multi-Emitter-Edit | ? | ? | ? | ? | ? |
| 3 | Emit-/Burst-Steuerung | teilweise B | ✓ B | ? | ✓ B | ✓ B |
| 4 | Sequenz-Kurveneditor | ? | ? | ? | ? | ? |
| 5 | Bezier-/Easing-Kurven | ✓ B | ? | ? | ? | ? |
| 6 | 3D-Bezier-Pfade | ? | ? | ? | ? | ? |
| 7 | Flipbooks | ? | ? | ? | ? | ? |
| 8 | Beams | ? | ✓ B | ? | ? | ? |
| 9 | Trails | ? | ? | ? | ? | ? |
| 10 | Mesh-VFX | ? | ? | ? | ? | ? |
| 11 | Lichter | ? | ? | ? | ? | ? |
| 12 | Kamera-/Screen-Effekte | teilweise V | ✓ B | teilweise B | ? | ? |
| 13 | Timeline/Sequencing | ✓ B | ✓ B | ✓ B | ✓ B | ✓ B |
| 14 | Keyframes beliebiger Properties | ✓ B | ✓ B | ✓ B | ✓ B | ? |
| 15 | Node-Graph-Logik | ? | ? | ? | ? | ? |
| 16 | Events/Trigger | ✓ B | ✓ B | ✓ B | ✓ B | ✓ B |
| 17 | Live-Vorschau (Workspace) | teilweise V | ✓ B | ? | ✓ B | ? |
| 18 | Isolierte Vorschau | ? | ? | ? | ? | ? |
| 19 | Undo/Redo | ? | ? | ? | ? | ? |
| 20 | Presets/Bibliothek | ? | ? | ? | ? | ? |
| 21 | Bulk-Ops | ? | ? | ? | ? | ? |
| 22 | Speichern/Laden, Re-Edit | ✓ B | ? | ? | ? | ? |
| 23 | JSON-/Textformat | teilweise V | ? | teilweise B | ? | ? |
| 24 | Runtime-Player-Modul | ✓ V | ✓ B | ✓ B | ✓ B | teilweise B |
| 25 | Export als Model | ✓ V | ? | ? | ? | ? |
| 26 | Scripting-API | ✓ V | ✓ B | teilweise B | ✓ B | ? |
| 27 | Performance-Analyse | ? | ? | ? | ? | ? |
| 28 | Qualitätsprofile/LOD | ? | ? | ? | ? | ? |
| 29 | KI-/Agent-Workflow | ? | teilweise V | ? | ? | ? |
| 30 | Preis/Lizenz | kostenpfl. (+ Free-Version) B | frei B | ? | ? | ? |

### 5.4 Block M4 – Custom-Partikelsysteme, Module und Studio-Bordmittel

| Nr. | Merkmal | Lumina [F19](#f19) | VortexFX [F20](#f20) | Flare Craft [F21](#f21) | Lightning Beams [F22](#f22) | UI-Partikel-Module (Sammelspalte) [F23](#f23) | Roblox-Studio-Bordmittel [F24](#f24) |
|---|---|---|---|---|---|---|---|
| 1 | Native ParticleEmitter | ? | ? | ? | ? | teilweise B | ✓ V |
| 2 | Multi-Emitter-Edit | ? | ? | ? | ? | ? | teilweise B |
| 3 | Emit-/Burst-Steuerung | ✓ V | teilweise V | ? | ? | ✓ V | teilweise V |
| 4 | Sequenz-Kurveneditor | ? | ? | ? | ? | teilweise V | ✓ V |
| 5 | Bezier-/Easing-Kurven | ? | ? | ? | ? | ? | teilweise V |
| 6 | 3D-Bezier-Pfade | ? | teilweise V | ? | ✓ V | ? | teilweise V |
| 7 | Flipbooks | ✓ V | ✓ V | ? | ? | ✓ V | ✓ V |
| 8 | Beams | ? | ? | ? | ? | ? | ✓ V |
| 9 | Trails | ? | ? | ? | ? | ? | ✓ V |
| 10 | Mesh-VFX | ✓ V | ✓ V | teilweise B | teilweise V | ? | teilweise V |
| 11 | Lichter | ? | ? | ? | ? | ? | ✓ V |
| 12 | Kamera-/Screen-Effekte | ? | ? | ? | ? | ? | teilweise V |
| 13 | Timeline/Sequencing | ? | ? | ? | ? | ? | teilweise V |
| 14 | Keyframes beliebiger Properties | ? | ? | ? | ? | ? | ? |
| 15 | Node-Graph-Logik | ✓ V | ? | ? | ? | ? | ? |
| 16 | Events/Trigger | ? | teilweise V | ✓ B | ? | teilweise V | teilweise V |
| 17 | Live-Vorschau (Workspace) | ? | ? | ? | ? | ? | ✓ V |
| 18 | Isolierte Vorschau | ? | ? | ? | ? | ? | ? |
| 19 | Undo/Redo | ? | ? | ? | ? | ? | ✓ V |
| 20 | Presets/Bibliothek | ? | ? | ? | ? | teilweise B | ? |
| 21 | Bulk-Ops | ? | ? | ? | ? | ? | ? |
| 22 | Speichern/Laden, Re-Edit | ? | ? | ? | ? | ? | ✓ V |
| 23 | JSON-/Textformat | ? | ? | ? | ? | ? | teilweise V |
| 24 | Runtime-Player-Modul | ✓ B | ✓ V | ✓ B | ✓ V | ✓ V | n. a. |
| 25 | Export als Model | ? | ? | ? | ? | ? | ✓ V |
| 26 | Scripting-API | ✓ V | ✓ V | ? | ✓ V | ✓ V | ✓ V |
| 27 | Performance-Analyse | ? | ? | ? | ? | ? | ✓ V |
| 28 | Qualitätsprofile/LOD | ? | ? | ? | ? | ? | teilweise V |
| 29 | KI-/Agent-Workflow | ? | ? | ? | ? | ? | ✓ V |
| 30 | Preis/Lizenz | frei, MIT V | Eigenlizenz V | kostenpfl. B | frei, MIT V | gemischt V/B | frei V |

### 5.5 Block M5 – kleine Helfer (Emit, Skalierung, Sequenzen)

| Nr. | Merkmal | Jad's Emit Plugin [F25](#f25) | roblox-particle-util [F26](#f26) | Shifty's Particle Emitter Plugin [F27](#f27) | ParticleEmitter Scaler [F28](#f28) | SmoothSequence Graph [F29](#f29) | CSE Pro [F30](#f30) |
|---|---|---|---|---|---|---|---|
| 1 | Native ParticleEmitter | ? | ? | ? | teilweise B | teilweise B | teilweise B |
| 2 | Multi-Emitter-Edit | ? | ✓ V | ? | ✓ B | ? | ? |
| 3 | Emit-/Burst-Steuerung | ✓ B | ✓ V | ✓ B | ? | ? | ? |
| 4 | Sequenz-Kurveneditor | ? | ? | ? | ? | ✓ B | teilweise B |
| 5 | Bezier-/Easing-Kurven | ? | ? | ? | ? | ✓ B | ? |
| 6 | 3D-Bezier-Pfade | ? | ? | ? | ? | ? | ? |
| 7 | Flipbooks | ? | ? | ? | ? | ? | ? |
| 8 | Beams | teilweise B | ? | ? | ? | ? | ? |
| 9 | Trails | ? | ? | ? | ? | ? | ? |
| 10 | Mesh-VFX | teilweise B | ? | ? | ? | ? | ? |
| 11 | Lichter | ? | ? | ? | ? | ? | ? |
| 12 | Kamera-/Screen-Effekte | ? | ? | ? | ? | ? | ? |
| 13 | Timeline/Sequencing | ? | ? | ? | ? | ? | ? |
| 14 | Keyframes beliebiger Properties | ? | ? | ? | ? | ? | ? |
| 15 | Node-Graph-Logik | ? | ? | ? | ? | ? | ? |
| 16 | Events/Trigger | ? | ? | ? | ? | ? | ? |
| 17 | Live-Vorschau (Workspace) | teilweise B | teilweise V | teilweise B | ? | ? | ? |
| 18 | Isolierte Vorschau | ? | ? | ? | ? | ? | ? |
| 19 | Undo/Redo | ? | ? | ? | ? | ? | ? |
| 20 | Presets/Bibliothek | ? | ? | ? | ? | ? | ? |
| 21 | Bulk-Ops | ? | ? | ? | teilweise B | ? | ? |
| 22 | Speichern/Laden, Re-Edit | ? | ? | ? | ? | teilweise B | ? |
| 23 | JSON-/Textformat | ? | ? | ? | ? | ? | teilweise B |
| 24 | Runtime-Player-Modul | ? | ? | ? | ? | ? | ? |
| 25 | Export als Model | ? | ? | ? | ? | ? | ? |
| 26 | Scripting-API | ? | ? | ? | ? | ? | ? |
| 27 | Performance-Analyse | ? | ? | ? | ? | ? | ? |
| 28 | Qualitätsprofile/LOD | ? | ? | ? | ? | ? | ? |
| 29 | KI-/Agent-Workflow | ? | ? | ? | ? | ? | ? |
| 30 | Preis/Lizenz | ? | ? | ? | ? | frei B | ? |

### 5.6 Block M6 – Profi-Referenzen und ASTRA (geplant)

| Nr. | Merkmal | Unity VFX Graph [F31](#f31) | Unreal Niagara [F32](#f32) | **ASTRA (geplant)** [F33](#f33) |
|---|---|---|---|---|
| 1 | Native ParticleEmitter | n. a. | n. a. | ✓ I |
| 2 | Multi-Emitter-Edit | ? | ? | ✓ I |
| 3 | Emit-/Burst-Steuerung | ✓ V | ✓ A | ✓ I |
| 4 | Sequenz-Kurveneditor | ✓ V | ✓ A | ✓ I |
| 5 | Bezier-/Easing-Kurven | ? | ? | ✓ I |
| 6 | 3D-Bezier-Pfade | ? | ? | teilweise I\* |
| 7 | Flipbooks | ? | ? | ✓ I |
| 8 | Beams | ? | ? | ✓ I |
| 9 | Trails | ? | teilweise A | ✓ I |
| 10 | Mesh-VFX | ✓ V | ✓ A | ✓ I |
| 11 | Lichter | ? | ✓ A | ✓ I |
| 12 | Kamera-/Screen-Effekte | ? | ? | ✓ I\* |
| 13 | Timeline/Sequencing | ✓ V | ✓ A | ✓ I |
| 14 | Keyframes beliebiger Properties | ? | teilweise A | ✓ I |
| 15 | Node-Graph-Logik | ✓ V | ✓ A | ✓ I |
| 16 | Events/Trigger | ✓ V | ✓ A | teilweise I |
| 17 | Live-Vorschau (Workspace/Szene) | ✓ V | ? | ✓ I |
| 18 | Isolierte Vorschau | ? | ? | teilweise I |
| 19 | Undo/Redo | ? | ? | ✓ I |
| 20 | Presets/Bibliothek | ✓ V | teilweise A | ✓ I |
| 21 | Bulk-Ops | ? | ? | ✓ I\* |
| 22 | Speichern/Laden, Re-Edit | ✓ V | ✓ A | ✓ I |
| 23 | JSON-/Textformat | ? | ? | ✓ I |
| 24 | Runtime-Player-Modul | ✓ V | ✓ A | ✓ I |
| 25 | Export als Model | n. a. | n. a. | ✓ I |
| 26 | Scripting-API | ✓ V | ✓ A | ✓ I |
| 27 | Performance-Analyse | ✓ V | ✓ A | ✓ I |
| 28 | Qualitätsprofile/LOD | ? | ✓ A | ✓ I |
| 29 | KI-/Agent-Workflow | ? | ? | ✓ I |
| 30 | Preis/Lizenz | ? | ? | offen |

## 6. Zeile 30 im Detail: Preis, Lizenz, Vertrieb

Preise aus Store-Snippets sind Momentaufnahmen und können veraltet sein.

| Produkt | Preis | Lizenz / Vertrieb | Label | Quelle |
|---|---|---|---|---|
| ROS Particle Editor | nicht ermittelbar | Creator-Store-Asset 8813198599; Lizenz unbekannt | – | https://create.roblox.com/store/asset/8813198599 |
| QP2 | 20 USD (Ko-fi/PayPal) oder 8000 Robux (Gamepass); 7-Tage-Trial. Gumroad: 20 USD, „Lifetime license“ (B) | Plugin „All rights reserved“, Decompilation/Reverse Engineering verboten (V). Freischaltung per Whitelist an die Roblox-User-ID; nur der Robux-Weg nutzt Discord/Bloxlink (V/B). Verteilung primär als `.rbxm` über GitHub (V); eine Creator-Store-Seite mit 26 Reviews existiert, Status unklar (B). Laut **einer** älteren Doku-Quelle obfusziert (B, Single-Source). Runtime-Modul: Nutzung/Modifikation/Einbettung erlaubt, keine Weitergabe, sichtbare Attribution in monetarisierten Spielen (V) | V / B | Plugin-README, Runtime-LICENSE (s. F2), https://qwinkletee.gumroad.com/l/qwinklesparticles2 |
| VFX Suite | ca. 4,99 $ (Angabe eines Konkurrenz-Threads); laut Such-Snippet zum Start einen Tag kostenlos | Creator-Store-Asset 14328968969; Lizenz unbekannt | B | https://devforum.roblox.com/t/introducing-the-vfx-suite-plugin/2545686 |
| VFX Editor | GitHub-Release gratis (V); Creator Store 4,99 $ laut DevForum (B) | MIT (V) | V / B | https://raw.githubusercontent.com/VirtualButFake/vfx-editor/main/README.md |
| VFX Forge | itch.io ab 16,67 $, Status „In development“ | Plugin-Lizenz nicht recherchiert. Emit-Modul: „VFX-DL-1.1“, source-available copyleft, nur eingebettet in die Runtime einer Roblox-Experience, **nicht** ladbar durch Studio-Plugins oder Entwickler-Tools (V) | B / V | https://zilibobi.itch.io/vfx-forge, https://registry.npmjs.org/@zilibobi/forge-vfx |
| VFX Studio (XxOmqxXNerd) | kostenlos | Creator-Store-Asset 135581141962270 | B | https://create.roblox.com/store/asset/135581141962270/VFX-Studio |
| Phase VFX | nicht ermittelt | Hinweis „may include licensed third-party assets“ | B | https://create.roblox.com/store/asset/78798609925417/Phase-VFX |
| Sine VFX | 5–7 $ | Shirt-Version als lokales Plugin ohne Auto-Update | B | https://devforum.roblox.com/t/plugin-sine-vfx-a-vfx-plugin-for-roblox-studio/4803771 |
| Effect Designer Suite | kostenlos | Open Source (Lizenzname nicht recherchiert) | B | https://devforum.roblox.com/t/effect-designer-suite-%E2%80%94-vfx-tooling-assets-and-more/4754553 |
| Beziers (vfxer) | nicht ermittelt | – | – | https://devforum.roblox.com/t/beziers-advanced-modular-vfx-plugin-10000-assets-add-ons/4180222 |
| EasyVFX | kostenlos | MIT | V | https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/LICENSE |
| VFX Scripter Pro | kostenlos | – | B | https://devforum.roblox.com/t/vfx-scripter-pro-%E2%80%94-an-essential-plugin-for-vfx-scripters/2961973 |
| SteakParticles | nicht ermittelt | – | – | https://devforum.roblox.com/t/steakparticles-plugin-for-creating-vfx-and-particle-emitters/2908779 |
| Moon Animator 2 | kostenpflichtig (häufige Sales) plus offizielle Free-Version (Asset 12944524137) | Exporter-Lizenzen nicht recherchiert | B | https://create.roblox.com/store/asset/4725618216/Moon-Animator-2 |
| Arc | kostenlos | laut DevForum „free and open source“, Lizenz verbietet Weiterverkauf/Umbenennung; Beta | B | https://devforum.roblox.com/t/arc-a-vfx-animation-plugin/4903133 |
| Motion, Visulie, Eclipse Animator | nicht ermittelt | – | – | s. F16–F18 |
| Lumina | kostenlos | MIT (2024 Mqxsyy) | V | https://raw.githubusercontent.com/Mqxsyy/Lumina/main/LICENSE |
| VortexFX | nicht ermittelt | „Custom Provision License“ | V | https://raw.githubusercontent.com/FancyDucc/3D-Particle-System/main/README.md |
| Flare Craft | 600 R$ | – | B | https://devforum.roblox.com/t/new-particle-system-flare-craft/2539746 |
| Lightning Beams | kostenlos | MIT (roblox-ts-Port `@rbxts/lightning-beams`) | V | https://registry.npmjs.org/@rbxts/lightning-beams |
| UI-Partikel-Module | ParticleUI frei (V), UIParticles frei (B), übrige nicht ermittelt | ParticleUI MIT (V) | V / B | s. F23 |
| Roblox Studio | kostenlos (Windows, macOS) | – | V | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/studio/setup.md |
| SmoothSequence Graph | kostenlos | – | B | https://devforum.roblox.com/t/smoothsequence-graph-the-easiest-way-to-edit-numbersequences/3044286 |
| Übrige Helfer, Unity VFX Graph, Unreal Niagara | nicht recherchiert | – | – | – |
| ASTRA (geplant) | offen | **offen (IDEA)**: lesbarer, nicht obfuszierter Code ohne Remote-Loads (Creator-Store-konform); die Lizenz entscheidet der Projektinhaber | I\* | `docs/research/qwinkle-particles2.md` §4 Nr. 9 |

## 7. Stärken und Schwächen je Produkt

Nur Aussagen über existierende Produkte; jede Aussage trägt ihr Label. Eigene Folgerungen für ASTRA stehen in Abschnitt 8.

**ROS Particle Editor** (F1)
- Stärken: Multi-Edit von Size/Transparency/Squash ohne Wertekappung (B); Viewport-Gizmos für erwartete Flugbahn (seit 16.02.2022 als `LineHandleAdornment` in Partikelfarbe) und Spawn-Bereich (B); Emitter an Attachments und Bones (B); große, gut lesbare UI (B). Von 2–3 Nutzern als lehrreich gelobt (B; „nachweislich hoher Lernwert“ ist laut Verifikation überzogen).
- Schwächen: sehr kleiner Funktionsumfang (B/A); Fehler beim Klick auf Size/Transparency (B); ein Konflikt mit dem Fremd-Plugin „Bezier Sequencer“ wird berichtet, erklärt aber nicht alle Ausfälle – im Jan. 2026 erscheint das Plugin bei einem Nutzer auch ohne dieses Plugin nicht (B); nicht abschaltbar (Wunsch vom 11.01.2026, B); wirkt seit 2022 ungepflegt (A); ein Nutzer meldete ein verdächtiges Skript im Plugin, Auflösung unbekannt (B).

**Qwinkle's Particles 2 (QP2)** (F2)
- Stärken: breiteste Palette transformierbarer Instanztypen inkl. Mesh, Licht, Highlight, Post-Processing (V); reifer Graph-Editor mit Bezier/Linear, Envelope, 20 Presets, RDP-Vereinfachung, 50-Schritt-Undo (V); Nesting und Events OnEmit/OnHit/OnDeath/OnDestruction (V); Runtime mit Freeze und Rückwärts-Timescale (V); dokumentiertes Performance-Konzept (eine Heartbeat-Verbindung, gestufte Abtastung, allokationsfreie innere Schleife – Herstelleraussage, V); großes Textur-Inventar (V); übungsbasierte Doku (B).
- Schwächen: stille Fehlschläge (fehlendes `RenderTemplate` ⇒ No-op, V; fehlendes `:Activate()`, `Enabled=false` nach Transform, B); Datenmodell aus 60+ Attributen, Configurations und ObjectValues, alte Effekte müssen im Plugin neu gespeichert werden (V); keine Timeline und kein Node-Graph gefunden (A); Nesting setzt `EmitDelay` verschachtelter Klone auf 0, Staffelung nur per Skript (B); Mesh-Partikel kosten je ein Skript-Update pro Partikel ohne Distanz-/Offscreen-Einsparung (B); Pooling standardmäßig aus wegen Beam/Trail-Randfällen (V); widersprüchlicher Runtime-Ablageort (ServerScriptService vs. ReplicatedStorage, V); Attributionspflicht in monetarisierten Spielen (V); Doku-Drift zwischen zwei Doku-Instanzen (B).

**VFX Suite** (F3)
- Stärken (B): Bezier-Graph-Editor mit Presets und steuerbaren Segmenten, Emit mit Delay, Re-time, Resizer, Sequence Copier, Undo; Workflow laut Nutzern „enjoyable“, Preis als fair bewertet.
- Schwächen (B, jeweils 1–2 Kommentare): UI „REALLY small“, Wunsch nach Skalierung; bestehende Werte (Size, Squash) schwer wieder ins Tool zu laden; laut Konkurrenz-Thread keine Texturbibliothek. Die Kritik „clutters Studio“ ließ sich nicht bestätigen.

**VFX Editor** (F4)
- Stärken (V): MIT, Build mit Lune; Properties-Ersatz mit Suche über Namen und Properties; Multi-Selektion mit semantischer Typprüfung; Easing/Bezier pro Segment; Undo/Redo; Lightweight-Modus; Max-Size/Max-Squash-Einstellungen; virtualisierte Baumansicht; Anpassung an die Community-Attribute (1.0.9).
- Schwächen: Easing-/Bezier-Daten nur in Attributen, bei Verlust zurückgesetzt (V); Memory-Leak und rekursive State-Fehler laut Changelog (V); Absturz bei kaputtem Texturpfad (V); Eingabefehler „.1“ (nur B); Crashs beim Hinzufügen von Texturen (B).

**VFX Forge** (F5)
- Stärken: sehr breite Feature-Liste (Flipbooks inkl. Mesh/Decal/Beam, 3D-Beziers, Lightning, Camera Shake, Screen Effects, 26 Bezier-Presets) (B); typisiertes Emit-Modul mit retime/resize/recolor, Finished-Promise, Attribut-Caching (V); „tonnes of features that no other plugin has“ (B).
- Schwächen: bewusst kein Sequencer, Timing über Moon Animator (B); `shared.vfx` wird auch zur Laufzeit belegt (V); Lizenz des Moduls verbietet die Nutzung in Plugins und Entwickler-Tools (V); Modul „very hard to understand“, Store-Version hinkte der lokalen hinterher, Doku anfangs lückenhaft (B).

**VFX Studio (XxOmqxXNerd)** (F6)
- Stärken (B): kostenlos und sehr verbreitet (96 % bei 800+ Votes, 110 Reviews); globale Retime/Scale/Color-Slider; Kamera-Shake- und Impact-Frame-Vorlagen; Code-Generator für Trigger-Skripte.
- Schwächen: kein eigenes Effektformat, Daten nur als Attribute (B, Drittanalyse); eine Heartbeat-Verbindung pro getweenter Property (B); ca. 300 gebündelte Fremdbibliotheken (B); die gefundene Doku-Seite ist laut eigenem Hinweis KI-generierter Platzhalter (V) und eine Zuordnung zum Store-Autor ist nicht bestätigt; Namenskollision mit „ASTRA VFX STUDIO“.

**Phase VFX** (F7)
- Stärken (B): 12 Effekttypen, Kurveneditor mit Presets, 3D-Beziers, Lightning, Screen-Space-Effekte, „one-click runtime code generation“.
- Schwächen (B): globale API unter demselben Namen `shared.vfx` wie VFX Forge (Kollisionsgefahr); „may include licensed third-party assets“; 84 % bei 30+ Votes.

**Sine VFX** (F8)
- Stärken (B): Partikelpfad- und Spawn-Shape-Visualizer, Partikelzähler, Trail Preview, Graph-/Gradient-Editor, Retimer/Resizer, günstiger Preis.
- Schwächen (B): globale Studio-API `shared.sv`; Shirt-Version ohne Auto-Update; Feature-Angaben widersprechen sich zwischen Hauptnotiz und eigenem DevForum-Post (Screen Effects).

**Effect Designer Suite** (F9)
- Stärken (B): kostenlos, Open Source; Emit-Eigenschaften „kompatibel mit anderen Plugins“; Skalier-Tools über Roblox-Grenzen hinaus; ColorSequences im Oklab-Farbraum; ca. 7000 Flipbooks/Texturen.
- Schwächen: keine Kritik gefunden (Abwesenheit, keine Aussage).

**Beziers (vfxer)** (F10)
- Stärken (B): modulare Add-on-Architektur (ImpactFrames, CameraShake, ScreenEffects, MeshVFX) mit Studio-API für Add-on-Autoren; ObjectValues zum Emittieren externer Objekte; 10k+ Assets.
- Schwächen (B): setzt beim `require` des Spielmoduls `shared.vfx` und `shared.fx`; Bezier-Add-on mit Handles noch in Arbeit.

**EasyVFX** (F11)
- Stärken (V): MIT, Rojo/Lune/selene-Toolchain mit CI; 45 Presets und Bausteine; scharfe Formen aus Geometrie statt Texturen; clientseitige Wiedergabe mit einer Animationsschleife; automatische Qualitätsstufen; Share-Codes mit Validierung; Kopplung an Eclipse-Event-Tracks und AnimationTrack-Marker; Claude-Code-Plugin mit headless Lune-Prüfschleife und Budget-Gates.
- Schwächen: sehr jung (Release 1.0.0 am 2026-10-16, V); das KI-Tooling steht laut CHANGELOG nur unter [Unreleased] auf main (V); die Re-Simulation ist ausdrücklich nur eine Näherung des Renderers (V); auf Nicht-Programmierer ausgerichtet, daher vermutlich wenig Feinkontrolle (A).

**VFX Scripter Pro / SteakParticles** (F12, F13)
- Stärken (B): Visualisieren ohne Play-Test, Looped Mode, Crash-Wiederherstellung (Scripter Pro); 60+ Presets (SteakParticles).
- Schwächen: kaum Details öffentlich (B).

**Moon Animator 2 + Exporter** (F14)
- Stärken: de-facto VFX-Timing-Werkzeug vieler Teams (B); Easing pro Keyframe, Keyframe-Gruppierung, Events mit Code, Kamera-Animation (B); Exporter erzeugen reine Daten-Cue-Tabellen bzw. Model + `VFXPlayer`-Modul und verstehen Emit-Aufrufe von VFX Forge und Part_Icles (V).
- Schwächen: Property-/CFrame-Animationen nicht als Roblox-Animation exportierbar (B); frühe Exporter brachen bei Emit-Events (B); manuelles Portieren laut einem Autor 4–6 h pro 30–60-s-Effekt (B, Selbstauskunft); MoonVFXCompiler setzt im Spiel das ForgeVFX-Modul voraus (V).

**Arc** (F15)
- Stärken (B): VFX-Timeline mit Emit-Keyframes, Partikel-Vorschau beim Scrubbing, benannte Events im Export, Moon-Sync, VFX-Forge-Konvertierung, unabhängige Wiedergaben; kostenlos. Eine Drittanbieter-MCP-Brücke mit 61 Tools existiert (V für die Erweiterung).
- Schwächen (B): Beta, erst seit Ende Sept. 2026 verfügbar, wenige Bewertungen; ob und wie Rückwärts-Scrubbing funktioniert, ist nur durch ein Snippet belegt; 3D-Beziers unbestätigt; die MCP-Brücke ist eine inoffizielle lokale Modifikation.

**Motion, Visulie, Eclipse Animator** (F16–F18)
- Stärken (B): Animation als Daten mit Runtime-Export (Motion); Animation nicht tweenbarer Typen inkl. `NumberSequence`/`ColorSequence` und Methodenaufrufen wie `Emit()` (Visulie); Event-Track mit Emits/Sounds/Code (Eclipse).
- Schwächen (B): Motion 2.0 als inkompatibles Neuprojekt angekündigt; Visulie nicht für Motor6D-Rigs gedacht; Eclipse-Details nur aus Drittprojekten bekannt.

**Lumina, VortexFX, Flare Craft** (F19–F21)
- Stärken: echter Node-Graph mit Spawn/Initialize/Update/Render/Logic (Lumina, V); Mesh- und Volumen-Partikel (Lumina, V); Kollision pro Partikel, Audio-Reaktion, Pfade (VortexFX, V); Kollisions-Events (Flare Craft, B).
- Schwächen: Lumina warnt selbst vor Produktionseinsatz (V), kann laut Autor nicht mit dem nativen Emitter mithalten, Lag durch Property-Updates (B); VortexFX laut Autor bei 3D-Partikeln mit Spikes, 2D deutlich performanter (V), Rewrite geplant (B); Flare Craft ca. 1000 Partikel bei ca. 30 fps, seit Mai 2024 nicht gepflegt (B). Durchgängig: Custom-Systeme sind performance-kritisiert und oft ungepflegt (B).

**Lightning Beams** (F22)
- Stärken (V): prozedurale Blitze mit geschichtetem Perlin-Noise, Bezier-Krümmung wie `Beam.CurveSize0/1`, Pulse-Wave, Sub-Module Sparks/Explosion; MIT.
- Schwächen (B): Destroy- und Lösch-Loop-Probleme bei vielen Effekten, Konflikt mit PartCache, Heartbeat-Verbindungen, FPS-Einbruch bei hohem PartCount.

**UI-Partikel-Module** (F23)
- Stärken: UI-Partikel ohne Code und „Convert Emitter“ (Emitter2D, B); Flipbooks, Burst/Loop (ParticleUI, V).
- Schwächen: deutlich langsamer (ImageLabels), keine LightEmission/Brightness in GUIs (B); teils ungepflegt (B). Kontext: Die native Klasse `ParticleEmitter2D` existiert im API-Dump 0.745 als `NotBrowsable` hinter FFlag `UIParticles`, ohne Doku (V); ob sie erscheint, ist offen (A).

**Roblox-Studio-Bordmittel** (F24)
- Stärken (V): kostenlos und nativ; Emitter emittieren im Edit Mode sofort; Studio-Undo; Mess-APIs (Stats, SceneAnalysisService, MicroProfiler); eingebauter MCP-Server.
- Schwächen: Sequenz-Popups ohne Bezier, Presets, Multi-Edit und Copy/Paste (V); Multi-Edit von Sequenzen laut Staff nicht unterstützt, Stand 2026 ungeklärt (B); Size im Sequenz-Editor noch ca. 2024 auf 0–10 gekappt (B); keine VFX-Timeline (die Eignung des Animation Editors für VFX-Properties ist nicht belegt).

**Kleine Helfer** (F25–F30)
- Stärken: fokussierte Einzelfunktionen – Emit/Delay-Panels, Multi-Selektion mit „...“ bei gemischten Werten (roblox-particle-util, V), prozentuale Skalierung, fehlerminimierende Keypoint-Platzierung mit Tangenten (SmoothSequence, B), ColorSequence-Umkehr und Lua-Export (CSE Pro, B).
- Schwächen: abweichende Attributnamen (`DelayTime` statt `EmitDelay`, V); Bug „emittiert andere Anzahl als im Attribut“ (Jad's, B); gemischte Reviews (Scaler, B); Re-Edit-Warnung (SmoothSequence, B).

**Unity Visual Effect Graph** (F31)
- Stärken (V): Trennung von Ablauf-Fluss (Contexts/Blocks) und Daten-Fluss (Operators); dokumentierte Flow-Kompatibilitätsregeln; typisierte, farbcodierte Ports; exponierte Properties mit Instanz-Override; Subgraphen und Templates mit Metadaten; Timeline-Clips mit Scrubbing, Start Seed und Prewarm; Seeds für Zufallszahlen (laut Doku „deterministic behavior in random number generations“, nicht für den ganzen Effekt); Profiling- und Debug-Panels mit Heatmap-Schwelle.
- Schwächen/Grenzen: Scrubbing berechnet die Simulation neu, hat eine Max Scrub Time und erzeugt GPU-Spitzen beim Rückwärtsspielen (V); System-Subgraphen werden tief kopiert (V); Settings vs. Properties ist für Laien schwer durchschaubar (A); Aktivierungs-Events unter 0,3 s können laut Issue Tracker übersprungen werden (B).

**Unreal Niagara** (F32)
- Laut Modellwissen (A, ungeprüft): Modul-Stack mit Stages, User Parameters, Emitter-Vererbung, Scratch Pad, Effect Types/Scalability mit Budgets und Significance, Debugger/FX Outliner, Sequencer-Lifecycle-Track, Determinismus-Option. Schwächen: keine belegt; die gesamte Spalte ist vor einer Entscheidung zu verifizieren.

## 8. Abgeleitete Anforderungen für ASTRA

Alle Einträge der Spalte „ASTRA-Anforderung“ sind **eigene Ideen (IDEA)**. Die Spalte „Befund“ enthält nur belegte
Aussagen über bestehende Produkte oder die Engine, jeweils mit Label. Die letzte Spalte gleicht mit
`docs/ARCHITECTURE.md` ab und markiert, wo die Recherche eine Anpassung nahelegt.

**Positionierung (ASSUMPTION):** In den Belegen kombiniert kein Roblox-Werkzeug Timeline (Z13), Node-Graph (Z15),
versioniertes Textformat (Z23), Runtime-Modul (Z24) und Performance-Analyse (Z27). Viele Zellen sind aber „?“, daher ist
das nur eine Annahme. Einzelne Bausteine sind **nicht** exklusiv: Timelines bieten Moon Animator 2, Arc, Motion,
Visulie (B); einen Node-Graph Lumina (V); KI-Agent-Integration EasyVFX (V, unveröffentlicht) und eine Arc-MCP-Brücke (V).

| Nr. | Befund (Markt/Engine) | Zeilen | ASTRA-Anforderung (IDEA) | Abgleich mit ARCHITECTURE.md |
|---|---|---|---|---|
| R1 | VFX Forge hat bewusst keinen Sequencer (B); bei QP2 keine Timeline gefunden (A), Nesting nullt `EmitDelay` (B); Moon-Timings müssen per Exporter oder manuell portiert werden, 4–6 h pro Effekt (B). Arc und Motion füllen die Lücke seit 2026 (B). | 13, 14, 24 | Mehrspur-Timeline über die Effektzeit; Emissions-Ereignisse (Burst, Enable-Fenster) getrennt von Live-Property-Spuren (wirken auf alle lebenden Partikel); explizite Offsets für Sub-Emitter; Export zur eigenen Runtime ohne Fremdmodul. Im UI erklären, dass „Size über die Effektzeit“ etwas anderes ist als „Size über die Partikel-Lebenszeit“. | §5, §7.4 decken Timeline und Runtime ab; UI-Erklärung ergänzen. |
| R2 | Arc zeigt Partikel beim Scrubbing (B, Verfahren unbekannt); Unity simuliert beim Scrubbing neu (V). Engine: kein Seed, `FastForward` gesperrt, `TimeScale` 0–1 (V); `Emit()` erzeugt Partikel mit Alter 0, Clear + Re-Emit reproduziert den Zustand bei t nicht (V, Verifikation); TimeScale-Bugs in Studio (B); Off-Screen-`Emit` angeblich verzögert (B). | 13, 17 | Seek nativer Partikel per „Replay-to-t“ (ab Effektstart in Echtzeit bis t abspielen, dann mit `TimeScale = 0` einfrieren, Fallback Clear + Replay); optional eigene Ghost-Simulation als Näherung; UI-Hinweis „native Partikel sind nicht exakt seekbar“. Determinismus nur für ASTRA-eigene Komponenten über einen eigenen PRNG in purem Luau (Lune 0.11.1 kennt `Random` nicht, V). | §5.2 sieht „seek leert Partikel“ vor; Replay-to-t als Option ergänzen. Studio-Tests zu TimeScale im Edit Mode vor Phase 3. |
| R3 | VFX Editor setzt Easing-Daten zurück, wenn das Attribut verloren geht (V); SmoothSequence warnt vor Re-Edit (B); 20-Keypoint-Grenze (V). | 4, 5, 22 | Bezier-/Easing-Kurven als Quelle der Wahrheit im JSON; deterministischer Bake auf ≤ 20 lineare Keypoints (adaptive Abtastung plus fehlerminimierende Reduktion) mit sichtbarer Fehleranzeige. Validator: ≥ 2 Keypoints, t₀ = 0, tₙ = 1, nicht absteigend, Envelope ≥ 0, Farbkomponenten 0–1. Step-Kurven über doppelte Zeitstempel erst nach Studio-Test („ascending“ vs. „non-descending“ widersprüchlich, V). | §4 Sequenzregeln vorhanden; Bake-Fehleranzeige ergänzen. |
| R4 | Studio kann Sequenz-Properties bei Mehrfachauswahl laut Staff nicht bearbeiten, Stand 2026 unklar (B); ROS (B), VFX Editor (V), roblox-particle-util (V), Scaler (B) lösen das je nur teilweise. | 2, 21 | Inspector-Mehrfachbearbeitung mit „Mixed“-Zustand und Wahl zwischen absolut (eine Kurve auf alle) und relativ (Scale, Offset, Retime, Invert pro Kurve); eine Undo-Recording pro Geste; Reset auf den individuellen Vorwert. Retime/Resize/Recolor als reine, getestete Transformationen auf dem JSON-Modell (Replace/Multiply, HDR-Faktor beachten), auch per CLI nutzbar. | §7.4 nennt Mehrfachbearbeitung; Bulk-Ops sind nur Recherche-Idee (I\*) und gehören in `Authoring/Ops`. |
| R5 | Re-Edit bestehender Effekte ist ein Kritikpunkt (VFX Suite, B). Die Community nutzt `EmitCount`/`EmitDelay`/`EmitDuration` (V/B), aber mit abweichenden Namen (`DelayTime`, V), Typen (number, NumberRange, String, B) und Semantik (QP2 vs. Forge, B); `<Property>Sequence` (EasyVFX V, VFX Studio nur Single-Source B). forge-vfx darf nicht von Plugins geladen werden (V). | 3, 22 | Verlustfreier Import nativer Emitter (Keypoints inkl. Envelope werden lineare ASTRA-Kurven) und Importer für Community-Attribute mit Typ-Normalisierung, Alias-Tabelle und Semantik je Quell-Tool. Optionaler „kompatibler Export“ nur der Basis-Emit-Attribute. Forge-Effekte clean-room interpretieren, das Modul nie laden. VFX-Studio-Konvention vor dem Bau an einer echten Datei prüfen. | Importer in §7.4 (Library-Import) nicht spezifiziert; ergänzen. |
| R6 | Stille Fehlschläge bei QP2: fehlendes `RenderTemplate`, fehlendes `:Activate()`, `Enabled = false` nach Transform (V/B). | 22, 24 | Laute Validierung beim Laden und Abspielen: Diagnostics mit Pfad (z. B. `components[3].rate`), Problems-Panel im Plugin, `warn` in der Runtime; `formatVersion` mit expliziten Migrationen, Runtime meldet „Effekt braucht Runtime ≥ x.y“. | §5.1 Migration und Validation vorhanden; Versions-Kopplung ergänzen. |
| R7 | `shared.vfx` wird von VFX Forge (auch zur Laufzeit, V), Phase VFX (B) und dem Moon VFX Exporter (B) benutzt, vfxer setzt zusätzlich `shared.fx` (B), Sine VFX `shared.sv` (B). | 26 | Keine `shared`-Globals in Plugin und Runtime; nur `require`-basierte API; eigene Metadaten nur mit Präfix (z. B. `ASTRA_`/`Astra…`), fremde Attribute nie verändern. | §5.3 nutzt `require`; ausdrückliches Verbot ergänzen. |
| R8 | Camera Shake, Impact Frames und Screen Effects gehören zur 2026-Baseline: VFX Forge, Phase VFX, vfxer, Arc (B), EasyVFX und QP2 (V). | 12 | Komponenten `cameraShake` (Trauma-Modell mit Stärke ∝ Trauma², Perlin-Noise, Distanzabfall, Spieler-Multiplikator; Werte als REPORTED-Startwerte) und `impactFrame`/`screen` (ColorCorrection/Bloom nur clientseitig unter `CurrentCamera`, gepoolte Highlights; kleine Pools, weil auch deaktivierte Highlights einen der 255 Slots belegen, V). Standardmäßig gedämpft und abschaltbar. | **Lücke:** Die Komponentenliste v1 in §4 enthält das nicht (nur `flash`). |
| R9 | 3D-Bezier-Pfade bieten VFX Forge, Phase VFX, EDS (B), VFX Studio als Tween-Schritte (B) und Lightning Beams (V). Native Emitter folgen keinem Pfad (V). | 6 | Pfad-Komponente bzw. Pfad-Spur: Attachments oder Gruppen laufen entlang einer Bezier-Kurve; Emitter folgen per `LockedToPart` oder emittieren entlang gesampelter Punkte. Der Analyzer weist die Kosten (Instanzen, Emit-Rate) aus. | **Lücke:** in §4 nicht vorhanden (nur Beam-Krümmung). |
| R10 | Per-Partikel-Events gibt es bei QP2 für Custom-Partikel (V), bei Unity als GPU Events (V) und bei VortexFX als Kollision (V); `ParticleEmitter` hat keine Partikel-Events (V). | 16 | Graph bietet Events nur auf Emitter- und Effektebene (`OnPlay`, `OnMarker`, `OnEvent`); „OnDeath“-artige Folge-Bursts nur als zeitbasierte Näherung (z. B. nach mittlerer Lifetime), klar so benannt. Unmögliches wird ausgeblendet statt vorgetäuscht. | §6 kompatibel. |
| R11 | QP2 warnt laut einer Doku-Quelle nicht vor Kosten (B, Single-Source), Zähler gibt es bei QP2 und Sine VFX (B); EasyVFX hat Budget-Gates nur auf main (V); Unity bietet Profiling-Panels mit Heatmap (V). | 27 | Heuristischer Analyzer je Qualitätsstufe: lebende Partikel ≈ Σ(Rate × mittlere Lifetime) + Bursts, Overdraw-Proxy, Emitter-Property-Writes pro Sekunde, Beams × Segments, Highlights gegen 255, Schatten-Lichter. Harte Lints aus V-Grenzen (Rate ≤ 400 bzw. 100 auf Mobile nur für `Rate`, Lifetime ≤ 20, FlipbookFramerate ≤ 30, Highlights ≤ 255) und Warnungen (Beam-Segments < Keypoints − 1 ist nur eine Untergrenze). Messmodus im Playtest per Differenzmessung mit `Stats` und `SceneAnalysisService`; ausdrücklich als Heuristik gekennzeichnet, ohne FPS-Versprechen. | §7.4 Performance-Panel vorhanden. |
| R12 | EasyVFX hat automatische Qualitätsstufen (V), Niagara Scalability-Regeln (A). Die Engine skaliert Rate und Beam-Segmente selbst (B; Bug-Report Aug. 2026), „Automatic“-Qualität ist nicht lesbar (V), „unter Stufe 4 keine Schatten“ ist skalenunklar (V). | 28 | Qualitätsprofile ohne Doppelskalierung: `Beam.Segments` auf Low **nicht** zusätzlich reduzieren; `countScale` vor allem auf Bursts, Trümmer und eigene Geometrie anwenden; Auto-Qualität adaptiv aus Plattform und geglätteter Frame-Zeit mit Hysterese; Zuordnung Nutzerstufe → Profil als Konfiguration. Optional Effektklassen mit `maxInstances`/`cullDistance` (Niagara-Analogie, A). | **Anpassung:** §5.4 sieht `segmentScale` 0.5 für Low vor. |
| R13 | KI-Integration ist Wettbewerb: EasyVFX Claude-Code-Plugin mit Lune-Loop (V, unveröffentlicht), Arc-MCP-Brücke (V, Drittanbieter); Studio-MCP nur auf Windows/macOS (V). `serde.encode` verwirft bei gemischten Tabellen Schlüssel und macht NaN/inf zu `null` (V). | 29, 23 | Differenzierung über versioniertes JSON-Schema, CLI (`validate`, `format`, `analyze`, `build`) mit demselben Luau-Code wie Plugin und Runtime, eigenen deterministischen Encoder (lehnt gemischte Tabellen und nicht-endliche Zahlen vor dem Encode ab), headless „Census“-Gates je Frame. MCP nur als optionaler Verifikationsschritt. | §8 vorhanden. |
| R14 | Rojo bildet `.json` verlustbehaftet auf ModuleScripts ab (`null` fällt weg, `[]` = `{}`, V lokal getestet); `syncRules` können `*.vfx.json` als StringValue mit rohem JSON syncen und `rojo syncback` schreibt sie verlustfrei zurück (V, dateibasiert); StringValue max. 200 000 Zeichen (V), effektiv 199 999 (B); `Script.Source` nicht undo-fähig (B); `Destroy()` nicht rückgängig zu machen (B). | 22, 23, 19 | Effekte als `*.vfx.json` per `syncRules` (`use: "text"`) als StringValue; CLI erzwingt ≤ 199 999 Bytes; Live-Rückweg über die optionale Bridge, ohne Bridge `PromptSaveSelectionAsync` → `.rbxm` → `rojo syncback`. Dokumente nie in `ModuleScript.Source`; Löschen in Recordings per `Parent = nil` statt `Destroy`. | **Anpassung:** §8 Nr. 3a nennt „JSON → ModuleScript“; ADR 6 (StringValue) passt. |
| R15 | `ViewportFrame` ohne Partikel/Beams/Trails (B); Emit im Edit Mode funktioniert (V); `Camera` ist `NotReplicated` (V); ob Heartbeat im Edit Mode feuert, ist unbelegt. | 17, 18 | Workspace-Vorschau primär, Viewport nur für Geometrie und Thumbnails mit Platzhaltern; Preview-Ordner `Archivable = false`, bevorzugt unter `workspace.CurrentCamera` (in Team Create sehr wahrscheinlich lokal, A); Heartbeat/PreRender im Edit Mode als erster Studio-Test. | §7.3 passt; Ablage unter `CurrentCamera` prüfen. |
| R16 | ROS lässt sich nicht abschalten und kollidiert mit anderen Plugins (B); VFX Suite UI zu klein (B, 1–2 Kommentare); QP2 nutzt eigene Overlay-UI (A). | 2, 17, 19 | Opt-in per Toolbar-Toggle (Zustand per `SetSetting`), Listener nur im aktiven Modus; Widgets über `CreateDockWidgetPluginGuiAsync` mit festen IDs; UI-Scale-Einstellung; jeder Schreibzugriff in `pcall`; Fremdänderungen per Bake-Hash erkennen (quantisiert wegen float32-Speicherung, B) mit Re-Entrancy-Guard; Optionen „übernehmen“ oder „ASTRA-Kurve wiederherstellen“. | §7 teilweise; UI-Scale, Opt-in und Fremdänderungs-Erkennung ergänzen. |
| R17 | QP2 laut einer Doku-Quelle obfusziert, Lizenz per User-ID-Whitelist (B/V); im ROS-Thread wurde ein verdächtiges Skript gemeldet (B); Creator Store beschränkt obfuszierten Code und Remote-Loads (V); QP2-Runtime-Ablageort widersprüchlich (V); QP2-Runtime verlangt Attribution (V). | 24, 30 | Lesbarer Code ohne Remote-`require`/`loadstring`, Creator-Store-konform; Runtime fest in `ReplicatedStorage`, das Plugin fügt sie genau dort ein; Runtime ohne Seiteneffekte. Lizenz ohne Attributionspflicht erwägen (Entscheidung des Projektinhabers). | Lizenz in ARCHITECTURE.md offen. |
| R18 | Große Bibliotheken sind Verkaufsargument (QP2 7800+ V, Sine 14k+, vfxer 10k+, EDS ca. 7000, B), Herkunft teils unklar (Phase VFX, B). `AssetService:CreateAssetAsync` ist derzeit nur in lokal geladenen Plugins nutzbar (V). | 20 | Eigene, rechtlich saubere Presets nach dem Phasenmodell (Anticipation → Impact → Secondary → Dissipation) mit Template-Metadaten (Name, Kategorie, Tags; Unity-Analogie, V). Die 28 mitgelieferten `rbxasset://textures/particles/*`-Texturen nur mit Hinweis „Player-Verfügbarkeit unbelegt“; keine fremden Texturen bündeln; Upload nur mit Feature-Detection. | §7.4 Library vorhanden; Metadaten ergänzen. |
| R19 | Unity: exponierte Properties mit Instanz-Override und Property Binder (V); Niagara: User Parameters und Emitter-Vererbung (A). | 20, 26 | Typisiertes `parameters`-Objekt (number, color3, vector3, boolean, Sequenzen) mit Referenzen aus Properties/Keyframes; `extends` als Diff auf ein Preset und `instanceOf` für verlinkte Duplikate, beim Kompilieren flach aufgelöst. | Bisher nur `palette` (§4); Schema v2 prüfen. |
| R20 | EasyVFX bindet Effekte an AnimationTrack-Marker (V); Moon-Exporter (V) und Eclipse-Event-Tracks (B) zeigen den Bedarf. | 13, 26 | Runtime-API zum Binden an `KeyframeMarker`/Animation Events; Effekt-Offsets relativ zu Rig-Teilen im Schema; Importer für Moon/Eclipse-Daten erst nach rechtlicher Prüfung. | Nicht in §5.3; ergänzen. |
| R21 | Audio-Vorschau im Edit Mode: Sounds unter einem `PluginGui`/`DockWidgetPluginGui` spielen mit `:Play()` (B, Staff); `AudioPlayer` mit `Wire` → `AudioDeviceOutput` soll funktionieren (B); der Properties-Toggle `Playing` startet im Edit Mode nicht (V). | 17 | Vorschau-Reihenfolge: Sound-Klon unter dem eigenen DockWidget → `AudioPlayer` + `Wire` + `AudioDeviceOutput` → `PlayLocalSound` → Hinweis „nur im Playtest hörbar“. `RunService:Run()` nicht verwenden. | `sound`-Komponente vorhanden; Vorschauweg ergänzen. |
| R22 | „VFX Studio“ ist ein verbreitetes Fremdprodukt (800+ Votes, B). | – | Markennamen nie zu „VFX Studio“ verkürzen. | – |

## 9. Belege je Spalte

Format: **Zeile – Wert** – Aussage [Quellenkürzel]. Zeilen ohne Eintrag sind „?“. Erläuterungen zu wichtigen „?“-Zellen
stehen mit dabei. Notiz-Verweise beziehen sich auf `docs/research/`.

<a id="f1"></a>
### F1 – ROS Particle Editor (Notiz: `ros-particle-editor.md`)

Quellen (alle B, nur Such-Snippets): [S1] https://devforum.roblox.com/t/the-worlds-best-particle-editor-plugin-99-sure/1668424 ·
[S2] …/1668424?page=2 · [S5] https://create.roblox.com/store/asset/8813198599 ·
[S20] https://devforum.roblox.com/t/vfx-difference-in-rosparticle-and-emitparticle/2441406

- **Z1 – teilweise B** – bearbeitet nur Size, Transparency und Squash; Emitter an Part, Attachment oder Bone (Update 16.02.2022) [S1].
- **Z2 – ✓ B** – „Adjusting Size/Transparency/Squash of multiple particle emitter“, „No limits for size and squash“; Selbstbeschreibung, absolute oder relative Semantik unbekannt [S1].
- Z3 – ? – kein Emit-Button belegt; ein Thread „RosParticle vs. emitParticle“ deutet auf eine `Emit()`-Vorschau hin, die Zuordnung zu ROS ist unbestätigt [S20].
- Z4/Z5 – ? – die Eingabeform (Graph, Drag, Zahlenfelder) ist nicht ersichtlich; keine Belege für Tangenten, Bezier oder ColorSequence.
- Z6 – ? – ein Wunsch nach Partikeln entlang einer Bezier-Kurve wurde mit „Pfad ergibt sich aus CFrame, Speed, Acceleration, Drag“ beantwortet; laut Verifikation ist **nicht gesichert**, dass der Autor das schrieb [S1].
- **Z17 – teilweise B** – Linien der erwarteten Flugbahn (seit 16.02.2022 `LineHandleAdornment` in Partikelfarbe; „blau“ ist veraltet) und aquafarbene Spawn-Bereich-Linien im 3D-Viewport; „Particle Edit Mode“ per Button bei Selektion [S1].
- Z19 – ? – Undo-Unterstützung unbekannt (offene Frage der Notiz).
- Z30 – ? – Preis und Lizenz nicht ermittelbar [S5].

<a id="f2"></a>
### F2 – Qwinkle's Particles 2 / „Qwinkle's Part-Icles 2“ (Notiz: `qwinkle-particles2.md`)

Quellen: [PR] Plugin-README https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2/main/README.md (V) ·
[RT] Runtime-README https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2-Module/main/README.md (V) ·
[RL] https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2-Module/main/LICENSE.md (V) ·
[D-NE] https://www.qwinkleparticles2.com/guide/hidden-depths/native-editing/ (B) ·
[D-WM] https://www.qwinkleparticles2.com/guide/hidden-depths/why-meshes-win/ (B) ·
[D-EX] https://www.qwinkleparticles2.com/guide/exercises/01-first-emission/ (B) ·
[D-NS] https://qp2-docs.pages.dev/guide/hidden-depths/nesting/ (B) · [D-WJH] https://qp2-docs.pages.dev/guide/what-just-happened/ (B) ·
[D-CS] https://www.qwinkleparticles2.com/es/guide/particiliary/camera-shake/ (B) ·
[X] https://x.com/qwinkletee/status/2040458438451634513, https://x.com/qwinkletee/status/2040781351528570958 (B)

- **Z1 – teilweise B** – nicht transformierte ParticleEmitter/Trail/Beam sind im selben Panel bearbeitbar, aber nur eine kuratierte Teilmenge der Properties; Schwerpunkt sind transformierte Custom-Emitter [D-NE]. Die Runtime feuert native Emitter mit (V) [RT].
- **Z2 – teilweise V** – Bulk-Werkzeuge Shifter (+ − × ÷), Clipboard (Werte zwischen Items mit Typfilter), Resize inkl. Nachfahren; eine Inspector-Mehrfachauswahl ist nicht belegt [PR].
- **Z3 – ✓ V** – Item-Attribute `EmitCount`, `EmitDelay`, `EmitDuration`, `EmissionMode`; native Emitter ohne Attribute = 1 Burst [RT].
- **Z4 – ✓ V** – Graph-Editor für 70+ Properties über die Partikel-Lebenszeit; Envelope; Simplify mit Ramer-Douglas-Peucker und Auto-Minimize (≤ 5 % Abweichung); Copy/Paste mit Skalierung auf den Zielbereich [PR]. ColorSequence-Editor für native Emitter (B) [D-NE].
- **Z5 – ✓ V** – Bezier und Linear im selben Graphen, Handles pro Keypoint; 20 Presets (u. a. 13 Easing-Kurven) [PR].
- **Z7 – ✓ V** – Ordner `MeshFlipbooks`/`BeamFlipbooks` [RT]; Spritesheet-Zerlegung, 50+ MeshFlipbook-Sequenzen, ImageLabel-Spritesheet-Flipbooks [PR].
- **Z8–Z12 – ✓ V** – transformierbar: Beam (Width0/1, CurveSize0/1, Segments, TextureSpeed animierbar), Trail, Part/MeshPart/Model (echte 3D-Geometrie), PointLight, Blur/Bloom/ColorCorrection/Atmosphere [PR]; Highlight [RT]. Camera Shake hat eine eigene Doku-Seite (B) [D-CS].
- **Z13 – ✗ A** – in keiner Quelle Timeline oder Sequencer; Nesting setzt `EmitDelay` verschachtelter Nachfahren auf 0, die Doku empfiehlt Staffelung per Skript mit `task.wait` (B) [D-NS]; „Keyframes“ meint nur Abtastschritte (`TotalKeyFrames`, Default 100, B). Abwesenheit ist nicht beweisbar; der angekündigte „Workspace Manager“ ist inhaltlich unbekannt [X].
- **Z14 – teilweise V** – 70+ Properties über die **Partikel-Lebenszeit** animierbar; Animate-Mode als Loop am Quell-Item [PR]. Keyframes über die Effektzeit nicht gefunden (A).
- **Z15 – ✗ A** – kein Node-Graph in einer Quelle; ein Vergleichs-Snippet: „no sign of a node graph or a timeline track“ (Absenz, ASSUMPTION).
- **Z16 – ✓ V** – Ordner `Events` in `PartIcleProperties` mit OnEmit/OnHit/OnDeath/OnDestruction, die auf ModuleScripts zeigen [RT]; OnHit per Raycast, max. 256 Events pro Frame (B). Handler-Signatur nicht dokumentiert.
- **Z17 – ✓ V** – Motion Preview: Live-3D-Trajektorien von 20 Envelope-Varianten auf Basis der Emit-Simulation [PR]; in Studio aktiviert sich die Engine automatisch (B).
- **Z19 – ✓ V** – 50-Schritt-Undo/Redo im Graph-Editor [PR]; Transform läuft durch Studios Undo-History (B) [D-WJH].
- **Z20 – ✓ V** – 20 Kurven-Presets; Inventory mit 7800+ Texturen (Gumroad: 9000+, B), Tabs, Favoriten; PNG-Upload braucht Studio-Beta-Features [PR].
- **Z21 – ✓ V** – Resize (0,5×–2×), Retime (inkl. Envelope), Hue (HSV-Shift), Shifter, Clipboard, Scan [PR].
- **Z22 – teilweise V** – Effektzustand als Attribute, Configuration-Kinder und ObjectValues im Instanzbaum; fehlt ein Pflichtteil, wird still nichts emittiert; Effekte älterer Versionen müssen im aktuellen Plugin neu gespeichert werden (die Runtime migriert nicht) [RT].
- **Z23 – teilweise B** – „Text Based AssetSharing“ (Teilen per Copy/Paste-Text) laut X-Post, Format nicht öffentlich [X]. Theme-Import/Export als JSON betrifft nur das UI-Theme [PR].
- **Z24 – ✓ V** – separates Runtime-Repo, ModuleScript `Part_Icles`; Klartext-Lua, eingefrorener Snapshot, manuelle Updates [RT].
- **Z25 – ✓ V** – Effekte sind gewöhnliche Instanzbäume (Model/Folder), die die Runtime liest [RT].
- **Z26 – ✓ V** – `AbsoluteEmit(root) → number?` (Dauer), `AbsoluteEmitAt`, `AbsoluteSetTimescale` (0 = Freeze, < 0 = rückwärts), `Preload/Deload`, `:Activate()` einmal pro Maschine [RT]; Emit-Code-Generator inkl. Moon Animator 2 [PR].
- **Z27 – teilweise B** – Partikelzähler unten links im Viewport [D-EX]; die Doku-Seite nennt Kosten (ein Skript-Update pro lebendem Partikel, keine Einsparung für Distanz oder Offscreen); das Zitat „the plugin doesn't warn“ ist nur Single-Source; kein Benchmark [D-WM].
- Z28 – ? – kein Qualitätsprofil belegt; laut Doku keine Distanz-/Offscreen-Einsparung (B) [D-WM].
- **Z30 – kostenpfl., proprietär V** – siehe Abschnitt 6 [PR][RL].

<a id="f3"></a>
### F3 – VFX Suite (PrimeVoxel) (Notiz: `other-roblox-vfx-plugins.md` §2.1)

Quellen (B): [VS-DF] https://devforum.roblox.com/t/introducing-the-vfx-suite-plugin/2545686 · [VS-CS] https://create.roblox.com/store/asset/14328968969/VFX-Suite

- **Z1 – ✓ B** – alle Features „cross-compatible“ zwischen ParticleEmitter, Beam und Trail [VS-DF][VS-CS].
- **Z3 – ✓ B** – „Better Emit“ mit Emit Delay [VS-DF].
- **Z4/Z5 – ✓ B** – Bezier Graph Editor mit Presets und steuerbaren Segmenten [VS-DF].
- **Z8/Z9 – ✓ B** – Particle/Beam Resizer, Trail Preview [VS-DF].
- **Z17 – teilweise B** – Emit und Trail Preview; eine Wiedergabesteuerung ist nicht belegt [VS-DF].
- **Z19 – ✓ B** – History/Undo (Ctrl+Z) [VS-DF].
- **Z20 – teilweise B** – Kurven-Presets; laut Konkurrenz-Thread „keine Texture-Library“ [VS-DF].
- **Z21 – ✓ B** – Sequence Copier (Squash, Size, Transparency, Colour), Re-time, Resizer [VS-DF].
- **Z22 – ✗ B** – Kommentare: bestehende Werte (Size, Squash) lassen sich nicht anzeigen bzw. weiterbearbeiten; laut Verifikation 1–2 Kommentare, kein Konsens, aktueller Stand unbekannt [VS-DF].
- **Z30 – kostenpfl. B** – siehe Abschnitt 6.

<a id="f4"></a>
### F4 – VFX Editor (VirtualButFake, jetzt tijnepema/vfx-editor) (Notiz: §2.2)

Quellen: [VE-R] https://raw.githubusercontent.com/VirtualButFake/vfx-editor/main/README.md (V) ·
[VE-W] https://raw.githubusercontent.com/wiki/VirtualButFake/vfx-editor/Home.md (V) ·
[VE-C] https://raw.githubusercontent.com/VirtualButFake/vfx-editor/main/CHANGELOG.md (V) ·
[VE-DF] https://devforum.roblox.com/t/vfx-editor-all-your-vfx-needs-in-one/3103467 (B)

- **Z1 – ✓ V** – Ersatz für das Properties-Fenster (Instanzbaum der Selektion, Suche nach Namen oder Properties); Lightweight-Modus im Stil des Studio-Properties-Fensters [VE-R][VE-W].
- **Z2 – ✓ V** – Multi-Property-Selektion mit Strg nur bei gleichem Typ **und** gleicher Semantik; Änderungen werden auf alle repliziert; Copy/Paste von Property-Werten nach denselben Regeln [VE-W].
- **Z3 – ✓ V** – Attribute heißen ab 1.0.9 `EmitCount` und `EmitDelay` (Issue #7) [VE-C].
- **Z4 – ✓ V** – NumberSequence-Editor („Carbon copy“ des Studio-Editors plus Kontextmenü), ColorSequence-Editor; einstellbare Max Size/Max Squash [VE-W].
- **Z5 – ✓ V** – Easing-Style/-Direction pro Segment, „bezier“ mit ziehbaren Handles [VE-W].
- **Z7 – teilweise V** – Flipbook-Anzeige in der Texture Storage; die Vorschau braucht teils HTTP-Requests [VE-W].
- **Z19 – ✓ V** – Undo/Redo für fast alle Aktionen [VE-R].
- **Z20 – teilweise V** – Texture Storage als simuliertes Dateisystem [VE-W]; Graph-Presets nur als Nutzerwunsch (B) [VE-DF].
- **Z22 – teilweise V** – arbeitet auf vorhandenen Instanzen; Easing-/Bezier-Daten liegen in Attributen und werden bei deren Verlust zurückgesetzt [VE-W].
- **Z23 – teilweise V** – JSON-Import/-Export nur für die Texture Storage [VE-W].
- **Z30 – frei, MIT V** – Creator Store 4,99 $ laut DevForum (B) [VE-R][VE-DF].

<a id="f5"></a>
### F5 – VFX Forge (zilibobi) (Notiz: §2.3)

Quellen: [VF-DF] https://devforum.roblox.com/t/plugin-vfx-forge-an-advanced-custom-vfx-system/3867553 (B) ·
[VF-IT] https://zilibobi.itch.io/vfx-forge (B) · [VF-R] https://raw.githubusercontent.com/zilibobi/forge-vfx/main/README.md (V) ·
[VF-NPM] https://registry.npmjs.org/@zilibobi/forge-vfx (2.4.0, `out/index.d.ts` und `LICENSE`, V) ·
[VF-D] https://zilibobi.github.io/forge-docs/effects/particle (B)

- **Z1 – ✓ B** – Partikel, Beams, Trails laut Feature-Liste [VF-IT][VF-DF].
- **Z3 – ✓ V** – Emit-Modul emittiert auf beliebig viele Instanzen (ParticleEmitter, Beams, Trails, Models, getaggte Effekte), optional mit Skalierungsfaktor oder Render-Tiefe [VF-NPM]; Attribute `EmitCount`/`EmitDelay`/`EmitDuration`, auch als NumberRange (B) [VF-D]; Fenster mit Einzeiler-Emit-Code (B) [VF-DF].
- **Z5 – ✓ B** – 26 eingebaute kubische Bezier-Presets (in/out/in-out) und eigene Kurven-Presets [VF-IT]. Z4 bleibt „?“, weil ein Sequenz-Editor nicht ausdrücklich genannt ist.
- **Z6, Z7, Z8, Z9, Z10, Z12 – ✓ B** – 3D-Beziers; Mesh-, Decal- und Beam-Flipbooks; Beams, Trails; Mesh-VFX und Spin Model; Camera Shake, Screen Effects, Shockwave, Lightning [VF-IT].
- **Z13 – ✗ B** – kein eingebauter Sequencer: „matching the editor quality of Moon would take quite a lot of effort“; Timing über Moon-Animator-Events [VF-DF].
- **Z20 – ✓ B** – 26 Bezier-Presets plus eigene Kurven- und Effekt-Presets [VF-IT].
- **Z21 – ✓ V** – `retime` (Speeds, Lifetimes, Durations, Rates), `resize` (Partikelgrößen, Beam-Breiten, Attachment-Abstände), `recolor` replace/multiply (HDR-Faktor bleibt) [VF-NPM].
- **Z24 – ✓ V** – Emit-Modul über Wally, npm oder rbxm; `init/deinit`; Ergebnis mit `Finished`-Promise und `Clear()`; Attribut-Caching (nur Client, nur ReplicatedStorage) [VF-R][VF-NPM].
- **Z26 – ✓ V** – öffentliche Typdeklaration; nach `init()` zusätzlich über `shared.vfx` erreichbar, auch zur Laufzeit im Spiel [VF-R].
- **Z30 – kostenpfl. B** – itch.io ab 16,67 $ [VF-IT]; Modul-Lizenz VFX-DL-1.1 (V), siehe Abschnitt 6.

<a id="f6"></a>
### F6 – VFX Studio (XxOmqxXNerd) (Notiz: §2.4) ⚠ Namenskollision mit „ASTRA VFX STUDIO“

Quellen: [VST-CS] https://create.roblox.com/store/asset/135581141962270/VFX-Studio (B) ·
[EV-A] https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/docs/vfx-studio-analysis.md (Drittanalyse von v3.9.3 durch die
EasyVFX-Autoren, B, Single-Source). Die Doku-Seite sytranom.github.io/vfx-studio-docs ist laut eigenem Hinweis „generated by AI …
for demonstration purposes“ und wird **nicht** als Beleg verwendet.

- **Z1 – teilweise B** – arbeitet mit Attributen auf normalen Instanzen; der Umfang der Property-Bearbeitung ist nicht belegt [EV-A].
- **Z3 – ✓ B** – `EmitDelay`, `EmitDuration`, `EmitCount` [EV-A].
- **Z6 – ✓ B** – Tween-Schritte: Linear, Bogen (quadratischer Bezier), randomisiert, manuelle Bezier-Punkte [EV-A].
- **Z12 – ✓ B** – Kamera-Shake-Schritte, Impact Frames als ColorCorrection-Templates [EV-A].
- **Z14 – teilweise B** – `<Property>Sequence`-Attribute animieren die gleichnamige Property über EmitDuration bzw. Lifetime, danach Rücksetzung; vor einem Importer an einer echten Datei prüfen [EV-A].
- **Z21 – ✓ B** – globale Retime/Scale/Color-Slider [EV-A].
- **Z22 – teilweise B** – Effekte als attributierte Instanzen im Place [EV-A].
- **Z23 – ✗ B** – kein eigenes Effektformat [EV-A].
- **Z26 – teilweise B** – Code-Generator für Trigger-Skripte; eine Heartbeat-Verbindung pro getweenter Property [EV-A].
- **Z30 – frei B** – kostenlos, 96 % bei 800+ Votes, 110 Reviews, Update 2026-09-07 [VST-CS].

<a id="f7"></a>
### F7 – Phase VFX (Phase Studio) (Notiz: §2.9)

Quellen (B): [PH-CS] https://create.roblox.com/store/asset/78798609925417/Phase-VFX · [PH-D] https://phase-doc.vercel.app/

- **Z1, Z7–Z10, Z12 – ✓ B** – Partikel, Beams, Trails, Mesh- und Decal-Flipbooks, Lightning, Camera Shake, Screen-Space-Effekte [PH-CS][PH-D].
- **Z3 – ✓ B** – Runtime-Emission, generierter Emit-Code [PH-CS].
- **Z4 – ✓ B** – „visual curve editor“, editierbare Mehrpunkt-Kurven mit Presets [PH-D]. Z5 bleibt „?“: Bezier/Easing nicht ausdrücklich genannt.
- **Z6 – ✓ B** – 3D-Beziers [PH-CS].
- **Z20 – ✓ B** – „12 production-ready effect types“, Kurven-Presets; „may include licensed third-party assets“ [PH-CS][PH-D].
- **Z24 – ✓ B / Z26 – ✓ B** – Runtime-Emission; globale Studio-API `shared.vfx`; „one-click runtime code generation“ [PH-CS][PH-D].
- Z30 – ? – Preis nicht ermittelt; erstellt 2026-04-07, Update 2026-08-04, 84 % bei 30+ Votes [PH-CS].

<a id="f8"></a>
### F8 – Sine VFX (Notiz: §2.10)

Quellen (B): [SV-DF] https://devforum.roblox.com/t/plugin-sine-vfx-a-vfx-plugin-for-roblox-studio/4803771 · [SV-W] https://sinevfx.xyz/

- **Z1 – ✓ B / Z3 – ✓ B** – Emit-Fenster für jede VFX-Instanz, Color Picker [SV-DF].
- **Z4 – ✓ B** – Graph-/Gradient-Editor [SV-DF].
- **Z8/Z9 – ✓ B** – transformierte Trails/Beams, Trail Preview [SV-DF].
- **Z10 – teilweise B** – „3D-Partikel“ laut Hauptnotiz; Mesh-Flipbooks fand die Verifikation im eigenen Post nicht [SV-DF].
- Z12 – ? – die Hauptnotiz nennt Screen Effects; der eigene DevForum-Post enthält laut Verifikation weder Screen Effects noch Camera Shake noch Lightning. Wegen des Widerspruchs „?“.
- **Z17 – ✓ B** – Partikelpfad-Visualizer, Spawn-Shape-Visualizer, Trail Preview [SV-DF].
- **Z20 – ✓ B** – 14k+ Assets (Hauptnotiz) [SV-DF].
- **Z21 – ✓ B** – Retimer/Resizer [SV-DF].
- **Z24 – ✓ B / Z26 – ✓ B** – Runtime-Modul; globale Studio-API `shared.sv` [SV-DF].
- **Z27 – teilweise B** – Partikelzähler [SV-DF].
- **Z30 – kostenpfl. B** – 5–7 $; „inspiriert von VFX Forge & QP2“ [SV-DF][SV-W].

<a id="f9"></a>
### F9 – Effect Designer Suite (igottic) (Notiz: §2.10)

Quelle (B): [EDS] https://devforum.roblox.com/t/effect-designer-suite-%E2%80%94-vfx-tooling-assets-and-more/4754553 (Store 109890065116916)

- **Z1 – teilweise B / Z3 – ✓ B** – Emit-Eigenschaften (Count, Delay, Duration) auf allen emittierbaren Objekten, einmalig oder wiederholt, „kompatibel mit anderen Plugins“; ein vollständiger Inspector ist nicht belegt.
- **Z4 – teilweise B** – ColorSequences im Oklab-Farbraum.
- **Z6 – ✓ B** – Bezier-/Tween-Animation für Attachments und BaseParts.
- **Z7 – ✓ B / Z20 – ✓ B** – ca. 7000 Flipbooks/Texturen.
- **Z21 – teilweise B** – Copy/Paste- und Skalier-Tools über Roblox-Grenzen hinaus.
- **Z30 – frei, Open Source B** – v1.2.0 teilt die UI in vier Widgets.

<a id="f10"></a>
### F10 – „Beziers – Advanced modular VFX Plugin“ (vfxer) (Notiz: §2.10 und Verifikation C1/C4)

Quellen (B): [VX-DF] https://devforum.roblox.com/t/beziers-advanced-modular-vfx-plugin-10000-assets-add-ons/4180222 ·
[VX-GB] https://vfxer.gitbook.io/plugin/attributes, https://vfxer.gitbook.io/plugin/module

- **Z1 – teilweise B / Z8, Z9, Z11 – ✓ B** – Tweening von Lights, Beams, Sounds, Partikeln und Trails [VX-DF].
- **Z3 – ✓ B** – Repeat-Emit-Attribute; `EmitDelay`/`EmitDuration` als number oder NumberRange; ObjectValues zum Emittieren externer Objekte [VX-DF][VX-GB].
- **Z6 – teilweise B** – Bezier-Add-on mit Handles „in Arbeit“ [VX-DF].
- **Z10 – ✓ B / Z12 – ✓ B** – Add-ons MeshVFX, ImpactFrames, CameraShake, ScreenEffects [VX-DF].
- **Z14 – teilweise B** – Property-Tweens auf den genannten Klassen [VX-DF].
- **Z20 – ✓ B** – 10k+ Assets [VX-DF].
- **Z24 – ✓ B / Z26 – ✓ B** – Spielmodul zum Abspielen, Studio-API für Add-on-Autoren; das Spielmodul setzt beim `require` `shared.vfx` und `shared.fx` [VX-DF][VX-GB].
- Z30 – ? – Preis nicht ermittelt.

<a id="f11"></a>
### F11 – EasyVFX (VuxSussy) (Notiz: §2.5 und Verifikation C13/C15)

Quellen (V): [EV-R] https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/README.md ·
[EV-AL] https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/docs/agentic-loop.md ·
[EV-EA] https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/docs/eclipse-animator.md ·
[EV-CL] https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/CHANGELOG.md · [EV-L] https://raw.githubusercontent.com/VuxSussy/EasyVFX/main/LICENSE

- **Z1 – teilweise V** – Effekte entstehen aus Presets und Bausteinen; folgt `EmitCount`/`EmitDelay`/`EmitDuration` und `<Property>Sequence`; Emitter-Rate auf 400 gekappt. Ein allgemeiner Emitter-Inspector ist nicht belegt [EV-R].
- **Z3 – ✓ V / Z16 – ✓ V** – Emit-Attribut-Konvention; Trigger Always on, Repeat, Touch, Click, ProximityPrompt-Taste, Script [EV-R].
- **Z6 – teilweise V** – Ringe aus 4 gekrümmten Bezier-Beams, Slash-Bänder aus verketteten Beams (als interne Formbausteine) [EV-R].
- **Z8 – ✓ V** – Beam-basierte Geometrie; Attachments werden jedes Frame zur Kamera gedreht statt `FaceCamera` [EV-R].
- **Z10 – ✓ V** – Geometrie-Bausteine (Crater, Debris, Orb, Ring, Rocks/Needles ≤ 64 pro Layer) [EV-R].
- **Z11 – ✓ V / Z12 – ✓ V** – Bausteine Light, Camera Shake, Impact Frame [EV-R].
- **Z13 – teilweise V** – schreibt Eclipse-Animator-Event-Tracks (KeyframeSequence, Event-Ordner, exportierte `KeyframeMarker`) und bindet Effekte zur Laufzeit an AnimationTrack-Marker („BindAnimation“); eine eigene Timeline ist nicht belegt [EV-EA].
- **Z14 – teilweise V** – `<Property>Sequence`-Attribute über EmitDuration/Lifetime/AnimDuration/1 s, danach Rücksetzung [EV-R].
- **Z20 – ✓ V** – 45 Presets in Kategorien (README, main); das Release 1.0.0 hatte laut CHANGELOG 30 Effekte; optionales HD-Texturpaket aus einem Blender-Skript [EV-R][EV-CL].
- **Z22 – teilweise V** – jede Instanz speichert ihre Definition als Attribut [EV-R].
- **Z23 – ✓ V** – Share-Codes `EVFX1:…` mit Validierung (nur bekannte Bausteine, alle Zahlen geklemmt) [EV-R].
- **Z24 – ✓ V** – Wiedergabe clientseitig, Server sendet ein RemoteEvent; eine Animationsschleife für alle Effekte; temporäre Teile in der Camera mit `Archivable = false`, ohne Kollision, Query und Schatten [EV-R].
- **Z26 – ✓ V** – Trigger „Script“, `EasyVFX.Quality`, BindAnimation [EV-R][EV-EA].
- **Z27 – teilweise V** – Budget-Gates (`budget.particles/beams/pieces/lights`, `ends_clean`, `flash.frames/rate`) gegen `baseline.json`, laut CHANGELOG nur unter [Unreleased] auf main; im Release nur harte Caps [EV-AL][EV-CL].
- **Z28 – ✓ V** – automatische Qualitätsstufen [EV-R].
- **Z29 – teilweise V** – Claude-Code-Plugin (Skills effect/story/components/preview/texture), headless Lune-Timeline-Recorder mit Partikel-Re-Simulation, Strips/Diffs, „Beat Sheets“ als JSON; ausdrücklich nur Näherung des Renderers; laut CHANGELOG **[Unreleased] auf main, nicht im Release 1.0.0 vom 2026-10-16** [EV-AL][EV-CL].
- **Z30 – frei, MIT V** [EV-L].

<a id="f12"></a>
### F12 – VFX Scripter Pro (Notiz: §2.10)

Quelle (B): https://devforum.roblox.com/t/vfx-scripter-pro-%E2%80%94-an-essential-plugin-for-vfx-scripters/2961973

- **Z17 – ✓ B** – VFX ohne Play-Test visualisieren, Looped Mode.
- **Z26 – teilweise B** – VFX skripten mit Script-Bibliothek; außerdem Wiederherstellung nach Studio-Crash und Physik auf Selektion.
- **Z30 – frei B**.

<a id="f13"></a>
### F13 – SteakParticles (Notiz: §2.10)

Quelle (B): https://devforum.roblox.com/t/steakparticles-plugin-for-creating-vfx-and-particle-emitters/2908779

- **Z1 – teilweise B** – Basis-Einstellungen für Partikel-Emitter. **Z20 – ✓ B** – Preset-Bibliothek (60+), Texturen. Sonst kaum Details.

<a id="f14"></a>
### F14 – Moon Animator 2 (xsixx) + Moon VFX Exporter + MoonVFXCompiler (Notiz: §2.7)

Quellen: [MA-CS] https://create.roblox.com/store/asset/4725618216/Moon-Animator-2 (B) ·
[MA-DF] https://devforum.roblox.com/t/getting-started-with-moon-animator-2-unofficial/476330 (B) ·
[MVE] https://raw.githubusercontent.com/GamesGG0/Moon-Animator-VFX-Exporter/main/README.md (V) ·
[MVC] https://raw.githubusercontent.com/GuHamYaiXD/MoonVFXComplier/main/README.md (V)

- **Z3 – teilweise B** – Emits laufen über Events mit Code; Emit()-Events brachen in frühen Exportern [MA-DF].
- **Z5 – ✓ B** – Easing pro Keyframe [MA-DF].
- **Z12 – teilweise V** – Kamera-Animation in Moon (B) [MA-DF]; der Exporter übersetzt Kamera-, Lighting- und Screen-Effekte (V) [MVE].
- **Z13 – ✓ B** – Tracks (ein-/ausklappbar), Keyframe-Gruppierung; in der Praxis das VFX-Timing-Werkzeug vieler Teams (VFX Forge verweist darauf) [MA-DF][VF-DF] (Kürzel aus F5).
- **Z14 – ✓ B** – Property- und CFrame-Animationen (laut Grenzen-Beschreibung nicht als Roblox-Animation exportierbar) [MA-DF].
- **Z16 – ✓ B** – Events mit Code [MA-DF].
- **Z17 – teilweise V** – der Moon VFX Exporter bietet eine Preview im Edit Mode [MVE]; Moons eigene Wiedergabe wurde nicht recherchiert.
- **Z22 – ✓ B** – eigene `.xsixx`-Dateien, File Explorer [MA-DF].
- **Z23 – teilweise V** – der Exporter erzeugt eine reine Daten-Cue-Tabelle (Frame → Effekt, Offset relativ zum HumanoidRootPart, optional Parent-Körperteil, Keys mit Moons Easing) [MVE]; das `.xsixx`-Format selbst wurde nicht recherchiert.
- **Z24 – ✓ V** – Abspiel- und Cleanup-Modul (Exporter) bzw. `VFXPlayer`-Modul (Compiler) [MVE][MVC]; MoonVFXCompiler setzt im Spiel das ForgeVFX-Modul voraus (Verifikation C11).
- **Z25 – ✓ V** – MoonVFXCompiler liest Moon- oder Eclipse-Saves und erzeugt Model + `VFXPlayer` in einem Klick, speichert nur gekeyte Properties; Moon→Eclipse-Konverter [MVC].
- **Z26 – ✓ V** – Exporter-Module; der Moon VFX Exporter versteht Emit-Aufrufe von VFX Forge und Part_Icles, „Warnungen statt Fehler“ [MVE].
- **Z30 – kostenpfl. B** – häufige Sales, offizielle Free-Version (Asset 12944524137) [MA-CS]. Motivation des Compilers laut Autor: manuelles Portieren 4–6 h pro 30–60-s-Effekt (Selbstauskunft, B) [MVC].

<a id="f15"></a>
### F15 – Arc (sevenIIl) (Notiz: §2.6 und Verifikation C12/C14)

Quellen: [ARC-DF] https://devforum.roblox.com/t/arc-a-vfx-animation-plugin/4903133 (B) ·
[ARC-CS] https://create.roblox.com/store/asset/118257542877059/Arc (B) ·
[ARC-MCP] https://raw.githubusercontent.com/Joojjuuk/plugin-studio/main/README.md (V für die Drittanbieter-Erweiterung)

- **Z1 – ✓ B / Z8 – ✓ B / Z14 – ✓ B** – Keyframes für Position, Rotation, Size und Properties von Parts, Attachments, Partikeln und Beams [ARC-DF][ARC-CS].
- **Z3 – ✓ B** – Emit-Keyframes mit Emit Count, Duration und Delay [ARC-DF].
- Z6 – ? – die Hauptnotiz nennt 3D-Beziers; die Verifikation fand keinen unabhängigen Beleg.
- **Z12 – ✓ B** – Camera Shake, Flash, Impact Frames, Debris [ARC-DF].
- **Z13 – ✓ B** – Timeline, Keyframe-Gruppierung, Moon-Animator-Sync, Konvertierung von VFX-Forge-Projekten [ARC-DF][ARC-CS].
- **Z16 – ✓ B** – benannte Events (z. B. „Hit“), im Export eine Funktion pro Event [ARC-DF].
- **Z17 – ✓ B** – die Partikel-Vorschau folgt dem Scrubber; rückwärts nur in einem Snippet belegt, Verfahren unbekannt [ARC-DF].
- **Z24 – ✓ B / Z26 – ✓ B** – Export als ModuleScript; `Start({...})` liefert ein Handle mit `Cancel()` (ein Snippet nennt `Animation.Play()`); jede Wiedergabe unabhängig [ARC-DF][ARC-MCP].
- **Z29 – teilweise V** – Drittanbieter-Erweiterung „Arc VFX MCP“: lokaler Node-MCP-Server mit 61 Tools über stdio, authentifizierte Bridge auf `127.0.0.1:41573`, `.mcp.json` für Claude Code; inoffizielle lokale Modifikation (braucht das Original-`Plugin.rbxm`), nicht vom Arc-Autor [ARC-MCP].
- **Z30 – frei B** – kostenlos; laut DevForum „free and open source“ mit Lizenz gegen Weiterverkauf/Umbenennung; Beta; v2.0.0, erstellt 2026-09-29, Update 2026-10-07, 100 % bei 20+ Votes [ARC-DF][ARC-CS].

<a id="f16"></a>
### F16 – Motion (jaybeemvoid) (Notiz: §2.8)

Quelle (B): https://devforum.roblox.com/t/motion-151-%E2%80%94-timeline-editor-animator/4274872 (v1.5.1)

- **Z12 – teilweise B** – Kamera-Animation. **Z13 – ✓ B / Z14 – ✓ B** – Timeline für Parts, Kameras, Rigs und Properties.
- **Z16 – ✓ B / Z26 – teilweise B** – Marker mit Callbacks.
- **Z23 – teilweise B** – Export als rohe Luau-Daten statt Animation-Assets. **Z24 – ✓ B** – „Export Runtime Engine“ nach ReplicatedStorage.
- Hinweis: Motion 2.0 ist als inkompatibles Neuprojekt angekündigt (letzte Antwort 2026-04-28).

<a id="f17"></a>
### F17 – Visulie (Notiz: §2.8)

Quelle (B): https://devforum.roblox.com/t/visulie-%E2%94%80-a-novel-all-purpose-animation-data-and-effects-suite/3582453 (bis 6.1.x)

- **Z1 – teilweise B / Z14 – ✓ B** – animiert nahezu beliebige Properties und Datentypen, auch nicht tweenbare (UDim, Rect, NumberSequence, ColorSequence), dazu Attribute und Tags.
- **Z3 – ✓ B** – Methodenaufrufe wie `Emit` und `Sound:Play`. **Z13 – ✓ B / Z17 – ✓ B** – Scrubbing löst Methodenaufrufe aus (wenn langsam genug).
- **Z16 – ✓ B / Z24 – ✓ B / Z26 – ✓ B** – Renderer-Modul mit Playback-Speed, Framerate und Animation Events. Gedacht für „atomare Effekte“, nicht für Motor6D-Rigs.

<a id="f18"></a>
### F18 – Eclipse Animator (Notiz: §2.8)

Quellen: https://create.roblox.com/store/asset/86116556258301/Eclipse-Animator (B); Formatdetails nur aus Drittprojekten [EV-EA] (F11) und [MVC] (F14).

- **Z3 – ✓ B / Z16 – ✓ B** – Event-Track mit Emits, Sounds und Code. **Z13 – ✓ B** – Animator mit Tracks.
- **Z24 – teilweise B** – Exporte als `KeyframeMarker`; abgespielt wird über AnimationTrack-Marker (z. B. EasyVFX „BindAnimation“).

<a id="f19"></a>
### F19 – Lumina (Mqxsyy) (Notiz: §2.11 und Verifikation C25)

Quellen: [LU-R] https://raw.githubusercontent.com/Mqxsyy/Lumina/main/README.md (V) ·
[LU-S] https://raw.githubusercontent.com/Mqxsyy/LuminaDocs/main/sidebars.ts (+ docs/nodes/*.md, V) ·
[LU-L] https://raw.githubusercontent.com/Mqxsyy/Lumina/main/LICENSE, …/package.json (V) ·
[LU-DF] https://devforum.roblox.com/t/update-020-lumina-a-custom-particle-system/2963557 (B)

- Z1 – ? – eigenes Partikelsystem statt ParticleEmitter; ob native Emitter bearbeitet werden, ist nicht belegt.
- **Z3 – ✓ V** – Spawn-Knoten Constant und Burst [LU-S].
- **Z7 – ✓ V** – PlaneParticle mit Spritesheet [LU-S].
- **Z10 – ✓ V** – MeshParticle und VolumetricParticle (Cube/Sphere) [LU-S].
- **Z15 – ✓ V** – Node-Gruppen Spawn, Initialize, Update (u. a. Accelerate, Bounce, Drag, LookTowards, MoveTowards, Multiply/Set…OverLife), Render, Logic sowie eine versteckte Mixed-Gruppe [LU-S]; „includes a graph editor“ [LU-R].
- **Z24 – ✓ B** – Export als ModuleScript oder Ordner von ModuleScripts mit `.Start()`/`.Stop()` [LU-DF].
- **Z26 – ✓ V** – „open-source custom particle system API“ [LU-R]. Plugin in roblox-ts + `@rbxts/react` [LU-L].
- **Z30 – frei, MIT V** [LU-L]. README warnt vor Produktionseinsatz (V); Rendering per SurfaceGui, Lag durch Property-Updates, „can not compete with the default particle emitter“ (B) [LU-DF].

<a id="f20"></a>
### F20 – VortexFX (FancyDucc/Aeresei) (Notiz: §2.11 und Verifikation C26)

Quellen: [VX-R] https://raw.githubusercontent.com/FancyDucc/3D-Particle-System/main/README.md (v1.0.65, V) ·
[VX-DF2] https://devforum.roblox.com/t/vortexfx-v106-a-3d-particle-system-for-all-your-3d-particle-needs/3131414 (B)

- **Z3 – teilweise V** – Konstruktor mit Adornee, `Create(Properties)`, `Start` [VX-R].
- **Z6 – teilweise V** – „Pfade“; ob Bezier, ist nicht angegeben [VX-R].
- **Z7 – ✓ V / Z10 – ✓ V** – Flipbooks; Emission von Models und MeshParts [VX-R].
- **Z16 – teilweise V** – Kollision pro Partikel (Abprallen, Ausweichen), Audio-Reaktion mit Beat-Erkennung; benannte Events nicht belegt [VX-R].
- **Z24 – ✓ V / Z26 – ✓ V** – Modul-API, nutzt ObjectCache [VX-R].
- **Z30 – Eigenlizenz V** – „Custom Provision License“; Preis nicht ermittelt [VX-R]. Autor: 2D-Partikel deutlich performanter, Spikes bei vielen Partikeln (V); Rewrite „Vortex3D“ geplant (B) [VX-DF2].

<a id="f21"></a>
### F21 – Flare Craft (Michel2003g) (Notiz: §2.11)

Quelle (B): https://devforum.roblox.com/t/new-particle-system-flare-craft/2539746

- **Z10 – teilweise B** – modulares 3D-Partikelsystem. **Z16 – ✓ B** – Kollision mit Events-Template.
- **Z24 – ✓ B** – Partikelsystem mit Plugin; Module wie Velocity oder boxLocation sind frei kombinierbar.
- **Z30 – kostenpfl. B** – 600 R$. Laut Entwickler ca. 1000 Partikel bei ca. 30 fps; Doku unvollständig; seit Mai 2024 nicht aktiv gepflegt.

<a id="f22"></a>
### F22 – Lightning Beams (Quasiduck) (Notiz: §2.13 und Verifikation C29)

Quellen: [LB-NPM] https://registry.npmjs.org/@rbxts/lightning-beams (README des Ports 1.1.0-ts.2, V) ·
[LB-DF] https://devforum.roblox.com/t/effect-v11-lightning-beams-seamless-smooth-and-procedurally-animated-with-beam-like-properties/843534 (B)

- **Z6 – ✓ V** – Bezier-Krümmung analog zu `Beam.CurveSize0/1` [LB-NPM].
- Z8 – ? – Part-basiert mit „beam-like properties“; eine Unterstützung nativer Beams ist nicht belegt [LB-NPM].
- **Z10 – teilweise V** – Part-basierte Geometrie (Bolt, Sub-Module LightningSparks und LightningExplosion) [LB-NPM].
- **Z24 – ✓ V / Z26 – ✓ V** – `LightningBolt.new(A0, A1, PartCount)`, geschichtetes Perlin-Noise, Pulse-Wave, ColorSequence mit `ColorOffsetSpeed`, Projektil-Modus [LB-NPM].
- **Z30 – frei, MIT V** [LB-NPM]. Kritik (B): Destroy-Probleme, Heartbeat-Verbindungen, FPS-Einbruch bei hohem PartCount [LB-DF].

<a id="f23"></a>
### F23 – UI-Partikel-Module (Sammelspalte) (Notiz: §2.12)

Quellen: [U-E2D] Emitter2D https://devforum.roblox.com/t/emitter2d-convert-any-particleemitter-to-2d-with-the-click-of-a-button/3742009 (B) ·
[U-UIP] UIParticles https://devforum.roblox.com/t/uiparticles-a-plugin-and-module-for-all-your-ui-particle-needs/3256357 (B) ·
[U-2DE] 2D Emitter v2 https://raw.githubusercontent.com/Synitx/2D-Emitter-2/main/README.md (V) ·
[U-UPY] UIParty https://raw.githubusercontent.com/Novaly-Studios/UIParticle/main/README.md (V) ·
[U-PUI] ParticleUI https://raw.githubusercontent.com/themwsama/Particle-UI-Module/main/README.md (V) ·
[U-RP] rParticle https://raw.githubusercontent.com/joeldesante/rParticle/master/README.md (V)

- **Z1 – teilweise B** – Emitter2D „Convert Emitter“ wandelt bestehende ParticleEmitter in UI-Emitter um [U-E2D].
- **Z3 – ✓ V** – ParticleUI Burst/Loop [U-PUI].
- **Z4 – teilweise V** – ParticleUI Color/Size/Transparency fest, als Bereich oder als Sequence [U-PUI].
- **Z7 – ✓ V** – ParticleUI Texturen/Flipbooks, UIParty Spritesheets [U-PUI][U-UPY]; UIParticles Flipbooks (B) [U-UIP].
- **Z16 – teilweise V** – rParticle Callbacks `OnSpawn`/`OnUpdate` auf RenderStepped [U-RP].
- **Z20 – teilweise B** – UIParticles Preset-Preview, Presets überleben Updates [U-UIP].
- **Z24 – ✓ V / Z26 – ✓ V** – Module (2D Emitter v2, UIParty, ParticleUI, rParticle) [U-2DE][U-UPY][U-PUI][U-RP].
- **Z30 – gemischt V/B** – ParticleUI MIT (V), UIParticles frei (B), Rest nicht ermittelt.
- Kontext (V, API-Dump 0.745): native Klasse `ParticleEmitter2D` mit Tag `NotBrowsable`, FFlag `UIParticles`, ohne Doku-Seite. Ob und wann sie erscheint, ist offen (A).

<a id="f24"></a>
### F24 – Roblox-Studio-Bordmittel (Notizen: `other-roblox-vfx-plugins.md` §2.15, `api-*.md`, `vfx-design-performance.md`, `tooling-claude-integration.md`)

Quellen (V, creator-docs-Quelltext unter `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/`):
[D-PE] effects/particle-emitters.md · [D-BM] effects/beams.md · [D-TR] effects/trails.md · [D-LS] effects/light-sources.md ·
[D-PP] environment/post-processing-effects.md · [D-AE] animation/editor.md · [D-CE] animation/curve-editor.md ·
[D-TUT] tutorials/use-case-tutorials/vfx/use-particles-for-explosions.md · [D-BY] reference/engine/classes/Beam.yaml ·
[D-CHS] reference/engine/classes/ChangeHistoryService.yaml · [D-PL] reference/engine/classes/Plugin.yaml ·
[D-MCP] studio/mcp.md · [D-PERF] performance-optimization/improve.md, performance-optimization/scene-analysis.md,
reference/engine/classes/Stats.yaml · [D-RS] reference/engine/classes/RenderSettings.yaml · [D-SET] studio/setup.md ·
[D-MP] reference/engine/classes/MeshPart.yaml. DevForum (B): [MS] https://devforum.roblox.com/t/unable-to-mass-edit-sequence-properties-ie-from-particles/2083516,
https://devforum.roblox.com/t/multiple-numbersequencecolorsequence-cant-be-edited-through-the-properties-panel/1071269,
https://devforum.roblox.com/t/let-us-edit-multiple-sequence-properties-at-a-time/425043 ·
[CAP] https://devforum.roblox.com/t/curve-editor-widget-needs-some-ux-improvements/3224754 ·
[VPF] https://devforum.roblox.com/t/add-support-for-particle-emitters-in-viewportframes/4706068

- **Z1 – ✓ V** – alle ParticleEmitter-Properties im Properties-Fenster [D-PE].
- **Z2 – teilweise B** – Sequence-Properties bei Mehrfachauswahl laut Staff „known limitation (missing feature, rather than a bug)“ bzw. „working as designed“; ein Post in 425043 meldet eine Freischaltung (Autor/Datum unbestätigt); Stand 2026 in Studio prüfen [MS].
- **Z3 – teilweise V** – Emitter emittieren nach dem Einfügen sofort; das Roblox-Tutorial testet Bursts mit Roblox' Plugin „ParticleEmitter:Emit(n)“ (Asset 303835976); keine Emit-Attribute [D-PE][D-TUT].
- **Z4 – ✓ V** – Sequenz-Popups: Keypoint per Klick einfügen, verschieben, löschen, Envelope ziehen; ColorSequence mit Farbwähler; **keine** Bezier-, Preset-, Multi-Edit- oder Copy/Paste-Funktion dokumentiert [D-PE]. Size-Kappung 0–10 im Editor noch ca. 2024 berichtet (B) [CAP].
- **Z5 – teilweise V** – Easing-Style/-Direction pro Keyframe im Animation Editor, Linear/Constant/Cubic mit Tangenten im Curve Editor; nicht in den Sequenz-Popups [D-AE][D-CE].
- **Z6 – teilweise V** – nur die Beam-Krümmung als kubische Bezier-Kurve (`CurveSize0/1`) [D-BY].
- **Z7, Z8, Z9, Z11 – ✓ V** – Flipbook-Properties, Beam, Trail und Lichtquellen direkt editierbar [D-PE][D-BM][D-TR][D-LS].
- **Z10 – teilweise V** – Part/SpecialMesh/MeshPart; `MeshPart.MeshId` ist für Skripte und Plugins nicht schreibbar [D-MP].
- **Z12 – teilweise V** – BloomEffect/ColorCorrectionEffect unter Lighting oder CurrentCamera; kein Camera-Shake-Werkzeug [D-PP].
- **Z13 – teilweise V** – Animation Editor mit Timeline, Scrubber, seconds:frames (Standard 30 fps), Keyframe-Optimierung; Curve Editor. Fokus Rig-Animation, Eignung für VFX-Properties nicht belegt [D-AE][D-CE].
- **Z16 – teilweise V** – Animation Events [D-AE].
- **Z17 – ✓ V** – Vorschau direkt im Edit Mode; Darstellung hängt vom „Editor Quality Level“ ab [D-PE].
- Z18 – ? – kein isoliertes VFX-Vorschaufenster; ViewportFrame rendert laut DevForum keine Partikel/Beams/Trails (B) [VPF].
- **Z19 – ✓ V** – Studio-Undo über ChangeHistoryService [D-CHS].
- **Z22 – ✓ V / Z25 – ✓ V** – Speichern im Place bzw. als Modell; `Plugin:PromptSaveSelectionAsync` speichert die Selektion als `.rbxm`/`.rbxmx` [D-PL].
- **Z23 – teilweise V** – `.rbxmx` ist ein textbasiertes Modellformat, aber kein VFX-Format; Plugins können keine beliebigen Dateien schreiben [D-PL].
- Z24 – n. a. – die Engine spielt Instanzen selbst ab; ein Effekt-Player gehört nicht zu den Bordmitteln.
- **Z26 – ✓ V** – Engine-API (`Emit`, `Clear`, alle Properties) [D-PE].
- **Z27 – ✓ V** – MicroProfiler, `Stats`, `SceneAnalysisService` mit Pass „Particles“; Werte szenenweit, nicht pro Effekt, auf dem Dev-PC nicht repräsentativ [D-PERF].
- **Z28 – teilweise V** – Editor Quality Level bzw. `RenderSettings.QualityLevel/EditQualityLevel` (PluginSecurity) für die Vorschau; keine Effekt-Profile [D-RS].
- **Z29 – ✓ V** – eingebauter Studio-MCP-Server (stdio, Quick Connect u. a. für Claude Code; `execute_luau`, `screen_capture`, `get_console_output`, `start_stop_play`); Studio nur auf Windows/macOS [D-MCP][D-SET].
- **Z30 – frei V** – „a free application available on Windows and Mac“ [D-SET].

<a id="f25"></a>
### F25 – Jad's Emit Plugin (Notiz: §2.14)

Quelle (B): https://devforum.roblox.com/t/dear-vfx-makers-i-present-to-you-jads-emit-plugin/1986838

- **Z3 – ✓ B** – emittiert Partikel, Beams und Meshes; behält `EmitCount`/`EmitDelay` bewusst bei, weil Skripter sie nutzen. **Z8 – teilweise B** – EmitDelay auch für Beams. **Z10 – teilweise B** – Meshes emittieren. **Z17 – teilweise B** – Emit in Studio. Bug-Report: emittiert eine andere Anzahl als im Attribut.

<a id="f26"></a>
### F26 – roblox-particle-util (J1ck) (Notiz: §2.14)

Quelle (V): https://raw.githubusercontent.com/J1ck/roblox-particle-util/main/README.md

- **Z2 – ✓ V** – setzt Emit Count und Delay für alle selektierten Partikel, „...“ bei gemischten Werten; Selektionsmodi Default/Children/Descendants.
- **Z3 – ✓ V** – Attribute `EmitCount` und **`DelayTime`** (abweichend von `EmitDelay`). **Z17 – teilweise V** – Viewport-Overlay bei Selektion.

<a id="f27"></a>
### F27 – Shifty's Particle Emitter Plugin (Notiz: §2.14)

Quelle (B): https://devforum.roblox.com/t/shiftys-particle-emitter-plugin/2661214

- **Z3 – ✓ B** – UI mit Emit Count, Emit Delay, Emit- und Reset-Button. **Z17 – teilweise B** – Emit/Reset in Studio.

<a id="f28"></a>
### F28 – ParticleEmitter Scaler (Notiz: §2.14)

Quelle (B): https://devforum.roblox.com/t/scale-particleemitters-uniformly-fast-particleemitter-scaler-plugin/2792643

- **Z1 – teilweise B / Z2 – ✓ B / Z21 – teilweise B** – skaliert Size und Lifetime prozentual über mehrere Emitter; gemischte Reviews.

<a id="f29"></a>
### F29 – SmoothSequence Graph (Notiz: §2.14; `ros-particle-editor.md` E9)

Quelle (B): https://devforum.roblox.com/t/smoothsequence-graph-the-easiest-way-to-edit-numbersequences/3044286

- **Z1 – teilweise B / Z4 – ✓ B / Z5 – ✓ B** – Keypoints mit Tangenten; platziert NumberSequence-Keypoints so, dass der Fehler minimiert wird.
- **Z22 – teilweise B** – Metadaten als Attribute mit Präfix `SMOOTHSEQUENCE_`; warnt vor Re-Edit. **Z30 – frei B**.

<a id="f30"></a>
### F30 – CSE Pro (Notiz: §2.14)

Quelle (B): https://devforum.roblox.com/t/cse-pro-supercharged-colorsequence-editor/2060438

- **Z1 – teilweise B / Z4 – teilweise B** – ColorSequence-Editor mit Umkehren. **Z23 – teilweise B** – Lua-Export.

<a id="f31"></a>
### F31 – Unity Visual Effect Graph (Notiz: `pro-vfx-tools.md` §2.1 und Verifikation)

Quellen (V): offizieller Doku-Quelltext, Paket 17.x, Basis
`https://raw.githubusercontent.com/Unity-Technologies/Graphics/master/Packages/com.unity.visualeffectgraph/Documentation~/` + Dateiname.
Online-Entsprechung `https://docs.unity3d.com/Packages/com.unity.visualeffectgraph@17.0/manual/<Seite>.html` (nicht direkt erreichbar).

- Z1, Z25 – n. a. (kein Roblox).
- **Z3 – ✓ V** – Spawn-Context mit Loop/Delay-Zustandsmaschine; Burst-Blocks Single oder Periodic mit konstanter oder zufälliger Anzahl [Contexts.md, Context-Spawn.md, Block-Burst.md].
- **Z4 – ✓ V** – Attribut-Blocks „from Curve“ mit AnimationCurve/Gradient und Sample-Modi OverLife, BySpeed, Random, RandomConstantPerParticle, Custom [Block-SetAttributeFromCurve.md, VisualEffectGraphTypeReference.md]. Z5 bleibt „?“: Tangenten/Bezier der Kurven wurden nicht recherchiert.
- Z9 – ? – „Per Particle Strip“ existiert als Scope des Random-Number-Operators [Operator-RandomNumber.md]; der Funktionsumfang von Strips wurde nicht recherchiert.
- **Z10 – ✓ V** – Mesh-Output-System, Static Mesh Output [Systems.md, Contexts.md].
- **Z13 – ✓ V** – Timeline-Integration: Control Track mit Clips, Scrubbing vorwärts und rückwärts (die Simulation wird neu berechnet), Start Seed pro Clip, Prewarm, Clip- und Single-Events mit Time Space; Grenzen Max Scrub Time und GPU-Spitzen beim Rückwärtsspielen [Timeline.md, VisualEffectProjectSettings.md].
- **Z15 – ✓ V** – Contexts, Blocks (oben nach unten), Operators; Subgraphen für System, Block, Operator; Flow-Kompatibilitätstabelle [GraphLogicAndPhilosophy.md, Blocks.md, Operators.md, Subgraph.md, Contexts.md]. Subgraph-Blocks haben keinen Activation-Port (Verifikation U5).
- **Z16 – ✓ V** – Events als Strings (OnPlay/OnStop) mit Attribut-Payloads; GPU Events mit Always, OverTime, OverDistance, OnDie, OnCollide [Events.md, Block-Trigger-Event.md, Context-GPUEvent.md].
- **Z17 – ✓ V** – Graph an eine Szeneninstanz angehängt; Play Controls im Scene View (Stop, Play/Pause, Step, Restart, Rate, Event Tester) [VisualEffectGraphWindow.md, VisualEffectComponent.md].
- **Z20 – ✓ V** – Template-Fenster mit Name, Kategorie, Beschreibung, Icon, Thumbnail, Favoriten, „zuletzt benutzt“ [Templates-window.md, VisualEffectGraphAsset.md].
- **Z22 – ✓ V** – VFX-Graph-Assets mit Asset-Einstellungen [VisualEffectGraphAsset.md].
- **Z24 – ✓ V / Z26 – ✓ V** – Visual-Effect-Komponente in der Szene, Component API (u. a. `resetSeedOnPlay`, `startSeed`), Property- und Event-Binder, Instanz-Overrides exponierter Properties [VisualEffectComponent.md, ComponentAPI.md, PropertyBinders.md, EventBinders.md, Properties.md].
- **Z27 – ✓ V** – Profiling-/Debug-Panels: CPU-/GPU-Zeit pro Graph/System/Context, Texturspeicher, Alive/Capacity, Heatmap-Schwelle; laut Doku nur Richtwerte; GPU-Timings fehlen auf Apple Silicon [performance-debug-panel.md].
- Z28 – ? – Culling Flags und Instancing sind Asset-Einstellungen [VisualEffectGraphAsset.md, Instancing.md]; Qualitäts-/Scalability-Systeme wurden nicht recherchiert.
- Z30 – ? – nicht recherchiert.
- Determinismus (keine eigene Zeile): Seeds und konstante Zufallszahlen; die Doku verspricht „deterministic behavior in random number generations“, nicht einen deterministischen Gesamteffekt [VisualEffectComponent.md, Operator-RandomNumber.md].

<a id="f32"></a>
### F32 – Unreal Engine Niagara (Notiz: `pro-vfx-tools.md` §2.2)

**Keine Quelle erreichbar** (Epic-Doku blockiert, Unreal-Quellen privat, WebSearch-Budget erschöpft). Alle Zellen sind Modellwissen
(A) aus den Befunden N1–N10 und vor jeder Architekturentscheidung gegen
https://dev.epicgames.com/documentation/en-us/unreal-engine/ zu prüfen. Konkrete Menünamen und Zahlen nicht übernehmen.

- **Z3 – ✓ A** – Stages Emitter Spawn/Update, Particle Spawn; Loop-Verhalten (einmal, mehrfach, endlos) (N1, N10).
- **Z4 – ✓ A** – Modul-Eingänge über Dynamic Inputs treibbar (Kurven, Zufallsbereiche, Parameter, Ausdrücke) (N3).
- **Z9 – teilweise A** – Ribbon-Renderer (N1). **Z10 – ✓ A** – Mesh-Renderer (N1). **Z11 – ✓ A** – Light-Renderer (N1).
- **Z13 – ✓ A / Z14 – teilweise A** – Sequencer-Integration mit Life-Cycle-Track und Parameter-Tracks für User Parameters (N9).
- **Z15 – ✓ A** – Modul-Stack plus Scratch Pad (lokale Module als Node-Graph) (N1, N5).
- **Z16 – ✓ A** – Event-Handler-Stage (N1).
- **Z20 – teilweise A** – Emitter-Vererbung von Parent-Emittern (N4).
- **Z22 – ✓ A / Z24 – ✓ A** – System-Asset, in der Welt per Niagara Component (N1).
- **Z26 – ✓ A** – User Parameters, von Gameplay-Code setzbar (N3).
- **Z27 – ✓ A** – Niagara Debugger mit HUD und FX Outliner (N7).
- **Z28 – ✓ A** – Effect Types/Scalability: Distanz-Culling, Instanzlimits, Significance, Budget-Skalierung (N6).
- Z1, Z25 – n. a.; übrige Zeilen „?“ (nicht einmal als Modellwissen in den Notizen).

<a id="f33"></a>
### F33 – ASTRA (geplant)

Grundlage: `docs/ARCHITECTURE.md` (Marker I) und die Abschnitte „Konsequenzen für ASTRA“ der Recherche-Notizen (Marker I\*).
**Alles in dieser Spalte ist Absicht, kein Fakt.** Laut `docs/PROGRESS.md` sind die meisten Module „geplant“ oder „in Arbeit“,
nichts davon ist in Studio getestet.

- **Z1, Z7 – ✓ I** – Komponente `particles` (ParticleEmitter an Attachment oder Hilfs-Part, Flipbooks) (§4).
- **Z2 – ✓ I** – Inspector mit Mehrfachbearbeitung (§7.4); Semantik absolut/relativ siehe R4.
- **Z3 – ✓ I** – Aktionen `emit`/`enable` im Zeitplan (§5.2).
- **Z4, Z5 – ✓ I** – Sequenzen ≤ 20 Keypoints, Easing-Namen oder `{ "bezier": [x1, y1, x2, y2] }` (§4); Spezialeditoren für Farbverläufe und Kurven, Kurvenansicht in der Timeline (§7.4).
- **Z6 – teilweise I\*** – Beam-Krümmung über die `beam`-Komponente (§4); Pfad-Komponente nur als Idee (`ros-particle-editor.md` §4.6), siehe R9.
- **Z8–Z11 – ✓ I** – Komponenten `beam`, `trail`, `mesh` (Part + SpecialMesh, ADR 5), `light`; dazu prozedurale Typen `shockwave`, `ring`, `radialBurst`, `debris`, `lightning` (§4).
- **Z12 – ✓ I\*** – Camera Shake und Impact Frames nur als Recherche-Idee (`vfx-design-performance.md` §4.3 Nr. 15; `api-geometry-lighting-tween.md` §4 Nr. 10), nicht in der Komponentenliste v1 (siehe R8).
- **Z13, Z14 – ✓ I** – Timeline mit Komponenten-Balken, Kanal-Spuren mit Keyframes, Markern, Events (§7.4); Live-Kanäle auf Emitter-Sequenzen treffen alle lebenden Partikel (Engine, V).
- **Z15 – ✓ I** – Node-Graph, beim Kompilieren in den Zeitplan entrollt (§6, ADR 9).
- **Z16 – teilweise I** – `OnPlay`, `OnMarker`, `OnEvent`, `handle:Fire` (§5.3, §6); Per-Partikel-Events sind mit nativen Emittern nicht möglich (V).
- **Z17 – ✓ I / Z18 – teilweise I** – Workspace-Vorschau primär; Viewport-Vorschau nur für Geometrie, weil Partikel/Beams/Trails dort nicht rendern (B) (§7.3, ADR 7).
- **Z19 – ✓ I** – jede Änderung als ChangeHistoryService-Recording, eine Geste = ein Undo-Schritt (§7.2, ADR 6).
- **Z20 – ✓ I** – Library mit Effekten, Presets und synchronisierten Dateien (§7.4).
- **Z21 – ✓ I\*** – Retime/Resize/Recolor als JSON-Transformationen (`other-roblox-vfx-plugins.md` §5 Nr. 6; `qwinkle-particles2.md` §4 Nr. 11).
- **Z22, Z23 – ✓ I** – kanonisches JSON als `StringValue` im Place, versioniertes Schema (§4, §7.2, ADR 1, ADR 6).
- **Z24, Z26 – ✓ I** – Runtime `AstraVFX` ohne Plugin-Abhängigkeit, `Play`/`Stop`/`Fire`/`Preload`/`SetQuality`, Net-Schicht (§5).
- **Z25 – ✓ I** – `lune run tools/astra build … -o build/X.rbxm` (§8 Nr. 2).
- **Z27 – ✓ I** – Performance-Panel mit Analyzer-Bericht je Qualitätsstufe, ausdrücklich heuristisch (§7.4).
- **Z28 – ✓ I** – Qualitätsprofile Low/Medium/High, `minQuality`, `qualityOverrides` (§5.4); Anpassung siehe R12.
- **Z29 – ✓ I** – Dateien als Schnittstelle, CLI, optionale localhost-Bridge, regelbasierter Generator (§8).
- **Z30 – offen** – keine Lizenz festgelegt.

## 10. Offene Prüfpunkte, die Zellen ändern können

| Prüfpunkt | betroffene Zellen | Weg |
|---|---|---|
| Multi-Edit von Sequenzen im Studio-Properties-Fenster (Stand 2026) | F24 Z2 | Studio-Test |
| Heartbeat/PreRender und `TimeScale = 0` im reinen Edit Mode | F33 Z13, Z17 | Phase-2-Smoke-Test |
| Wie Arc Partikel beim Rückwärts-Scrubbing zeigt; 3D-Beziers in Arc | F15 Z6, Z17 | Arc in Studio testen |
| Inhalt des angekündigten QP2-„Workspace Manager“ | F2 Z13, Z15 | Hersteller-Doku/Videos |
| `<Property>Sequence`-Konvention von VFX Studio an einer echten Datei | F6 Z14 | Studio, Effektdatei untersuchen |
| Sine VFX: Screen Effects ja oder nein | F8 Z12 | aktuellen DevForum-Post lesen |
| Alle Niagara-Zellen | F32 | Epic-Doku |
| Unity: Kurven-Tangenten, Particle Strips, Scalability, Lizenz | F31 Z5, Z9, Z28, Z30 | Unity-Doku |
| Preise und Lizenzen (Phase VFX, vfxer, Motion, Visulie, Eclipse, Helfer) | Z30 mehrerer Spalten | Store-Seiten |
| ROS: Preis, Undo, Eingabeform, Status in Studio 2026 | F1 | Plugin installieren und testen |
