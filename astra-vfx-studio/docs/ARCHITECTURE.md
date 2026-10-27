# ASTRA VFX Studio – Architektur

Stand: Phase 1 (Architekturentscheidung). Dieses Dokument ist verbindlich für alle Implementierungsphasen.
Technische Rahmenbedingungen und ihre Quellen stehen in [`ROBLOX_API_CONSTRAINTS.md`](ROBLOX_API_CONSTRAINTS.md),
die Marktanalyse in [`RESEARCH.md`](RESEARCH.md) und [`FEATURE_COMPARISON.md`](FEATURE_COMPARISON.md).

---

## 1. Ziele und Leitprinzipien

1. **Daten zuerst.** Ein Effekt ist ein reines, JSON-kompatibles Datenobjekt (`EffectDefinition`). Editor, Claude,
   CLI, Runtime und Tests arbeiten alle mit demselben Format. Es gibt keine versteckten Zustände in Roblox-Instanzen.
2. **Eine Laufzeit für alles.** Die Studio-Vorschau benutzt exakt denselben Runtime-Code (`AstraVFX`), der später im
   Spiel läuft. Was in der Vorschau funktioniert, funktioniert auch im Export.
3. **Laufzeit ohne Plugin.** `AstraVFX` (src/Runtime) hängt von nichts außerhalb seines eigenen Ordners ab und wird
   beim Export unverändert in das Spiel kopiert.
4. **Deterministisch.** Gleiche Definition + gleicher Seed ⇒ gleiche Instanzen, gleiche Zeitpläne, gleiche
   prozedurale Formen, byte-identische JSON-/Luau-Exporte. Partikelsimulation selbst ist Engine-Sache und nicht
   deterministisch.
5. **Ehrlich gegenüber der Engine.** Nur dokumentierte Roblox-APIs. Was die Engine nicht kann (z. B. Partikel im
   ViewportFrame, `MeshPart.MeshId` per Skript setzen), wird umgangen oder klar als Einschränkung dokumentiert.
6. **Testbar ohne Studio.** Alle Kernmodule laufen in Lune (mit echten Roblox-Datentypen und Reflection-Datenbank).
   Engine-Verhalten (Emit, Heartbeat, …) wird in Tests über `tests/lune/Fakes.luau` nachgebildet und protokolliert.

## 2. Gesamtbild

```
            ┌────────────── Claude Code / Mensch ───────────────┐
            │  effects/*.json  (versioniertes Effektformat)     │
            └──────┬───────────────────────┬────────────────────┘
                   │ lune run tools/astra  │ Rojo-Sync / Bridge / Datei-Import
                   ▼                       ▼
     ┌───────────────────────┐   ┌──────────────────────────────────────────────┐
     │ CLI (Lune)            │   │ Roblox Studio Plugin (src/Plugin)            │
     │ validate/format/      │   │ Explorer · Inspector · Timeline · Node Graph │
     │ analyze/build/generate│   │ Library · Performance · Preview              │
     └─────────┬─────────────┘   └──────────────┬───────────────────────────────┘
               │ benutzt                          │ benutzt
               ▼                                  ▼
     ┌──────────────────────────────────────────────────────────────────────────┐
     │ Authoring (src/Authoring): Ops · Analyzer · Generator · Exporter · Ids    │
     └──────────────────────────────┬───────────────────────────────────────────┘
                                    ▼
     ┌──────────────────────────────────────────────────────────────────────────┐
     │ Runtime "AstraVFX" (src/Runtime) – wird ins Spiel exportiert              │
     │ Core: Types · Json · Codec · Validation · Migration · Easing · Curves ·   │
     │       Timeline · Graph · Components/* · Quality · Compiler · Builder ·    │
     │       Player · Scheduler · Pool · Signal · Random · Env                   │
     │ API:  AstraVFX.Play / Register / Preload / SetQuality · Net               │
     └──────────────────────────────────────────────────────────────────────────┘
```

### Abhängigkeitsregeln (werden per Test geprüft)

| Schicht | darf benutzen | darf **nicht** benutzen |
|---|---|---|
| `src/Runtime/**` | nur `src/Runtime/**` | Authoring, Plugin, Presets, Tests |
| `src/Authoring/**` | Runtime, Authoring, Presets | Plugin |
| `src/Plugin/**` | alles | – |
| `tests/specs/**` | alles (über `use("…")`) | – |

Innerhalb von `Runtime/Core` gilt eine azyklische Reihenfolge (niedrig → hoch):
`Types, Constants → Signal, Random, Env, Json → Codec, Easing → Curves → Timeline → Components/* → Graph →
Migration → Validation → Quality → Compiler → Builder → Player → Scheduler, Pool → Runtime init`.
Ein Modul darf nur Module **links** von sich benötigen. Zyklen erkennt der Loader (`Cyclic require detected`).

## 3. Verzeichnisstruktur

```
astra-vfx-studio/
  default.project.json      Rojo: Plugin-Build (AstraVFXStudio.rbxmx)
  runtime.project.json      Rojo: Runtime-Paket für Spiele (AstraVFX.rbxm)
  src/
    Runtime/                ModuleScript "AstraVFX" (Spiel-Laufzeit, ohne Plugin lauffähig)
      init.luau             öffentliche API
      Net.luau              optionale Server→Client-Replikation von Effekten
      Core/                 Datenmodell, Auswertung, Bau, Abspielen (siehe §5)
        Components/         ein Modul pro Komponententyp + Common + Registry (init)
        Graph/              Node-Graph: Knotentypen, Validierung, Compiler
    Authoring/              Editor-/CLI-Logik (nicht im Spiel nötig)
    Presets/                *.json – mitgelieferte Beispiel-Effekte (Rojo: JSON → ModuleScript)
    Plugin/                 Studio-Plugin (init.server.luau = Bootstrap-Script)
  tests/
    framework/              TestFramework.luau (läuft in Lune und Studio)
    specs/                  *.spec.luau (automatische Tests)
    lune/                   Loader, Fakes, Runner (nur Lune)
  tools/                    CLI (astra.luau), Bridge, Schema-Generator, Analyzer (C++), Prüfskripte
  schema/                   astra-effect.schema.json (generiert)
  effects/                  Arbeitsordner für Effekt-Dateien (Claude/Rojo)
  examples/                 Beispiel-Spielskripte (Server/Client)
  docs/                     Dokumentation
```

## 4. Datenmodell (Schema-Version 1)

Die Typen sind in `src/Runtime/Core/Types.luau` definiert. Die vollständige Referenz für Autoren (Mensch und
Claude) ist `docs/EFFECT_FORMAT.md`, die maschinenlesbare Form `schema/astra-effect.schema.json` – beide werden aus der
Komponenten-Registry generiert, damit Dokumentation und Code nicht auseinanderlaufen.

Drei Repräsentationen werden strikt getrennt:

| Stufe | Typ | Inhalt | Erzeugt von |
|---|---|---|---|
| Definition | `EffectDefinition` | JSON-Daten: `"#RRGGBB"`, `[x,y,z]`, Enum-Namen, relative Zeiten | Mensch, Claude, Editor (Ops), Migration |
| Kompiliert | `CompiledEffect` | dekodierte Roblox-Datentypen, Defaults, Qualität & Skalierung angewandt, sortierte Keyframes, aufgelöste Easing-Funktionen, statischer Zeitplan | `Core/Compiler` |
| Gebaut | `BuiltEffect` | Roblox-Instanzen einer abspielenden Kopie + Controller pro Komponente | `Core/Builder` |

Wesentliche Konventionen:

* **Zeit:** Sekunden. Keyframes und Events sind relativ zum `startTime` ihrer Komponente (wie Ebenen in After
  Effects – verschiebt man die Komponente, wandert die Animation mit). Marker und Zeitplan sind absolut.
* **Raum:** +Y oben, −Z vorne (`CFrame.LookVector`), +X rechts. Positionen in Studs relativ zur Eltern-Komponente,
  Rotation in Grad in Roblox-`Orientation`-Reihenfolge (`CFrame.fromOrientation`).
* **IDs:** `id` von Effekt, Komponente, Track, Event, Marker, Knoten: `[A-Za-z0-9_-]{1,64}`, eindeutig, stabil
  (Umbenennen ändert nur `name`).
* **Farben:** `"#RRGGBB"` oder `"$palettenName"` (Verweis auf `palette`). Paletten erlauben Umfärben zur Laufzeit
  (`Play(…, { Palette = { primary = Color3… } })`).
* **Sequenzen:** `NumberSequence` als Zahl oder `[[t, v, envelope?], …]`, `ColorSequence` als Farbe oder
  `[[t, "#RRGGBB"], …]`. Maximal 20 Keypoints, erste Zeit 0, letzte Zeit 1 (Roblox-Regeln).
* **Easing:** `"Linear"`, `"Constant"`, `"Quad"` (= `Quad.Out`), `"Back.InOut"`, … (Roblox-`EasingStyle`-Namen) oder
  `{ "bezier": [x1, y1, x2, y2] }` (CSS-artige kubische Bézierkurve).
* **Kanonische Ausgabe:** `Json.encode` sortiert Schlüssel nach einer festen Prioritätsliste, danach alphabetisch,
  formatiert Zahlen stabil und erzeugt so reproduzierbare, diff-freundliche Dateien.

### Komponententypen (v1)

| Typ | Roblox-Basis | Zweck |
|---|---|---|
| `group` | (nur Transformation) | Hierarchie, Orbits, Rotation |
| `particles` | `ParticleEmitter` an Attachment oder Hilfs-Part (für Shape-Volumen) | kontinuierliche & Burst-Emission, Flipbooks |
| `beam` | `Beam` + 2 `Attachment`s | Strahlen, Slashes, Bögen |
| `trail` | `Trail` + 2 `Attachment`s | Bewegungsspuren (braucht Bewegung) |
| `part` | `Part` (Block/Ball/Cylinder/Wedge/CornerWedge) | Geometrie, Neon/ForceField-Effekte |
| `mesh` | `Part` + `SpecialMesh` (FileMesh/Sphere/…) | Mesh-VFX mit skalierbarem `SpecialMesh.Scale` |
| `light` | `PointLight`/`SpotLight`/`SurfaceLight` an Attachment/Part | Lichtimpulse |
| `sound` | `Sound` | Audio-Akzente |
| `sphere` | Ball-Parts (Kern + Hülle) + Licht | Energiekugeln |
| `flash` | Neon-Ball + PointLight mit eingebauter Hüllkurve | Impact-Flash |
| `shockwave` | flache Zylinder-Parts | expandierende Druckwelle (Scheibe/Ring) |
| `ring` | Segment-Parts | Ringe, Polygone, Sterne, Speichen (magische Kreise) |
| `radialBurst` | Keil-/Block-Parts | radiale Strahlen-/Stachel-Explosion |
| `debris` | kleine Parts, kinematisch | Trümmer mit ballistischer Bahn (ohne Physik, deterministisch) |
| `lightning` | Beams oder Neon-Parts zwischen Zickzack-Punkten | Blitze, elektrische Bögen |

Prozedurale Typen sind **reine Funktionen der lokalen Zeit + Seed** (z. B. Trümmerposition = p₀ + v·t + ½·g·t²,
Blitzform = f(seed, floor(t·flickerRate))). Dadurch funktionieren Scrubbing und Vorschau exakt, und es gibt keine
Physik-/Netzwerk-Abhängigkeit.

## 5. Laufzeit (src/Runtime)

### 5.1 Ablauf

```
Definition ──Migration.migrate──► v1 ──Validation.validate──► gültig
        ──Compiler.compile(def, {quality, scale, palette, seed})──► CompiledEffect (gecacht)
        ──Builder.build(compiled, {parent, preview, viewport})──► BuiltEffect (Instanzen + Controller)
        ──Player.new(compiled, built, options)──► step(dt) / seek(t) / stop() / destroy()
Scheduler: genau EINE RunService-Verbindung für alle aktiven Player, wird bei Leerlauf getrennt.
```

### 5.2 Player-Frame (`Player:step(dt)`)

1. Zeit fortschreiben (`dt × timeScale`), Loop-Umbruch behandeln (Zeitplan pro Durchlauf neu, Seed + Durchlauf).
2. Wurzel-CFrame bestimmen (`Attach`-Ziel × `Offset` oder fester `CFrame`).
3. Für jede Komponente in topologischer Reihenfolge: aktiv? → `setActive` bei Wechsel; Kanäle auswerten
   (`Curves.evaluate`) → `apply`; Transformation aus Ruhelage × Kanälen × Spin × Eltern berechnen → `setTransform`
   (Parts sammeln für ein einziges `WorldRoot:BulkMoveTo`); prozedurales `update`.
4. Fällige Aktionen aus dem Zeitplan im Intervall (t_prev, t] ausführen (`emit`, `enable`, `fire`, Graph-Aktionen …).
5. Gesammelte Part-CFrames per `BulkMoveTo` anwenden.
6. Ende: Emitter stoppen, Nachlaufzeit (`maxTail` = längste Partikel-/Trail-Lebensdauer) abwarten, dann aufräumen
   bzw. an den Pool zurückgeben.

`Player:seek(t)` wertet denselben Zustand ohne Emission aus (Scrubbing). Partikel werden dabei geleert, weil die
Engine keine Partikelsimulation „vorspulen“ kann: `ParticleEmitter.FastForward` ist RobloxScriptSecurity,
`TimeScale` reicht nur von 0 bis 1, es gibt keinen Seed (verifiziert, siehe Constraints).

Weitere Engine-Fakten, die der Player berücksichtigt: Aktionen werden nie im selben Frame ausgeführt, in dem die
Instanzen gebaut wurden (ein `Emit` direkt nach dem Parenten kann wirkungslos sein – berichtet); `Color`/`Size`/
`Transparency` eines Emitters wirken auf alle lebenden Partikel, `Rate`/`Speed`/`Lifetime` nur auf neue; Beams und
Trails haben keinen Zeitfaktor (Slow-Motion skaliert `TextureSpeed`, Trails altern in Echtzeit).

### 5.3 Öffentliche API (`require(ReplicatedStorage.AstraVFX)`)

```lua
local AstraVFX = require(ReplicatedStorage.AstraVFX)

AstraVFX.Register(definitionOrModuleOrFolder) --> name(s)   -- Effects-Ordner wird automatisch registriert
local handle = AstraVFX.Play("VioletImpact", {
	CFrame = targetCFrame,      -- oder Position = Vector3 / Attach = BasePart|Attachment (+ Offset)
	Scale = 1.5,
	Quality = "High",           -- "Low" | "Medium" | "High" | "Auto" (Standard: Auto auf Clients)
	TimeScale = 1, Seed = 42, Loop = false,
	Palette = { primary = Color3.fromRGB(80, 160, 255) },
	OnEvent = function(name) end,  -- Marker-/Graph-Events, z. B. "Impact"
})
handle:Stop()            -- sanft: Emission stoppen, Partikel ausklingen lassen, dann aufräumen
handle:Destroy()         -- sofort entfernen
handle:Pause() / handle:Resume() / handle:SetTimeScale(n) / handle:SetCFrame(cf)
handle:Fire("Detonate")  -- löst Graph-Trigger "OnEvent(Detonate)" aus
handle.Finished:Connect(fn); handle.Event:Connect(function(name) end)
AstraVFX.Preload("VioletImpact", { Count = 2, Quality = "Medium" })  -- Pool vorwärmen
AstraVFX.SetQuality("Auto"); AstraVFX.StopAll(); AstraVFX.ActiveCount()
```

**Netzwerk (`AstraVFX.Net`):** Gameplay bleibt serverseitig autoritativ; Effekte sind kosmetisch und werden auf
Clients gerendert. Der Server ruft `Net.PlayAll/PlayFor/PlayNear(name, options)` auf; Clients (`Net.Listen()`)
validieren Name (nur registrierte Effekte), klemmen Skalierung/Zeitfaktor und spielen lokal. Es gibt bewusst
**keinen** Client→Server-Pfad. `Attach`-Ziele, die durch StreamingEnabled beim Client fehlen, fallen auf den
übertragenen CFrame zurück.

### 5.4 Qualitätsprofile

| Profil | countScale | segmentScale | sizeCompensation | Schatten | maxLights |
|---|---|---|---|---|---|
| Low (Mobile) | 0.35 | 0.5 | 1.12 | aus | 2 |
| Medium | 0.65 | 0.75 | 1.05 | aus | 4 |
| High (Desktop) | 1.0 | 1.0 | 1.0 | wie definiert | unbegrenzt |

`count`-Eigenschaften (Rate, Burst-Anzahl, Trümmeranzahl) werden mit `countScale` multipliziert, `segments` mit
`segmentScale` (nur prozedurale Segmente wie Ring-, Blitz- und Schockwellen-Unterteilungen – **nicht**
`Beam.Segments`: die Engine reduziert Beam-Segmente bei niedriger Grafikqualität selbst, und Farbverläufe brauchen
mindestens n−1 Segmente, siehe Constraints K14). Weniger, dafür etwas größere Partikel (`sizeCompensation`) halten die Silhouette. Komponenten mit
`minQuality` werden unterhalb dieser Stufe weggelassen; `qualityOverrides` erlaubt gezielte Werte pro Stufe.
`"Auto"` liest auf Clients die Grafikqualität des Spielers (siehe Constraints-Dokument); Server und Studio
verwenden Medium bzw. die Editor-Einstellung.

## 6. Node Graph

Der Graph ergänzt die Timeline um Logik. Er erzeugt **geplante Aktionen** auf der Effekt-Zeitachse statt eigene
Threads zu starten (kein `task.wait`, keine unbegrenzten Schleifen):

* Exec-Pins (Kontrollfluss) und Daten-Pins (`number`, `vector3`, `color3`, `boolean`, `string`, `component`).
* Kernknoten: `OnPlay`, `OnMarker`, `OnEvent`, `Delay`, `Sequence`, `Parallel`, `Loop` (max. 100 Iterationen),
  `RandomBranch`, `RandomNumber`, `Number`, `Color`, `Vector`, `Math`, `Component`, `Emit`, `SetEnabled`, `Tween`,
  `SetProperty`, `FireEvent`, `PlaySound`, `Regenerate`.
* Validierung: Pin-Typen müssen passen, ein Daten-Eingang hat höchstens eine Verbindung, ein Exec-Ausgang höchstens
  eine (Verzweigung nur über `Parallel`/`Sequence`), **keine Zyklen** (weder Exec noch Daten), Komponentenverweise
  müssen existieren und den richtigen Typ haben.
* Ausführung: `OnPlay`/`OnMarker`-Flüsse werden beim Kompilieren in den statischen Zeitplan entrollt (mit Seed ⇒
  deterministisch, Scrubbing-fähig, in der Timeline als Spur sichtbar). `OnEvent`-Flüsse werden zur Laufzeit beim
  Auslösen ab der aktuellen Zeit entrollt. Harte Grenze: 10 000 erzeugte Aktionen pro Auslösung.

## 7. Studio-Plugin (src/Plugin)

### 7.1 Module

```
Plugin/
  init.server.luau        Bootstrap: Toolbar, Widgets, App starten, Unloading → vollständiges Aufräumen
  App.luau                verdrahtet Editor, Storage, History, Preview, Panels, Shortcuts
  Editor.luau             zentraler Controller + Zustand (siehe 7.2)
  Studio/
    History.luau          ChangeHistoryService-Aufnahmen (TryBeginRecording/FinishRecording)
    Storage.luau          Effekte im Place speichern/laden (ServerStorage.AstraVFX.Effects)
    Settings.luau         plugin:GetSetting/SetSetting mit Defaults
    Bridge.luau           optionale localhost-Brücke zur CLI (HttpService, standardmäßig AUS)
    SelectionSync.luau    Studio-Selektion ↔ Komponentenauswahl
    Shortcuts.luau        PluginActions + fensterinterne Tastenkürzel
  Preview/
    PreviewEngine.luau    Workspace-Vorschau (primär), Stage, Kamera, Charakter-Dummy
    ViewportPreview.luau  isolierte Geometrie-Vorschau im ViewportFrame (mit klarer Einschränkung)
  UI/
    Theme.luau, New.luau (deklarativer Instanz-Builder), Widgets/*, Editors/*, Panels/*
```

### 7.2 Editor-Zustand und Undo/Redo

* **Quelle der Wahrheit** für gespeicherte Effekte ist der Place: `ServerStorage.AstraVFX.Effects.<Name>` als
  `StringValue` mit kanonischem JSON (Attribute `AstraId`, `AstraSchemaVersion`). Effekte werden mit dem Place
  gespeichert, ohne dass das Plugin im Spiel gebraucht wird.
* Jede Änderung läuft über `editor:transact(label, mutator)`: Kopie des Dokuments → `Authoring/Ops`-Funktion →
  Validierung → `History.record(label, function() storage:write(doc) end)`. Dadurch landet jede Änderung als ein
  Undo-Schritt im **Studio-eigenen** Undo/Redo (Strg+Z wirkt auch im Explorer/Properties von Studio).
* Undo/Redo durch Studio ändert den `StringValue`; `Storage` erkennt fremde Änderungen (Vergleich mit zuletzt
  geschriebenem Text) und lädt das Dokument neu. Die Toolbar-Schaltflächen rufen `ChangeHistoryService:Undo/Redo`.
* **Gesten** (Ziehen von Keyframes, Slidern, Knoten): `beginGesture` → beliebig viele `updateGesture` (nur Speicher
  + Vorschau) → `endGesture(commit)` schreibt genau einmal ⇒ ein Undo-Schritt pro Geste.
* Signale: `editor.changed(kind)` mit `kind ∈ {"document","selection","playback","view","diagnostics","library"}`.
  Panels abonnieren nur, was sie brauchen, und aktualisieren gezielt (keine komplette Neuzeichnung pro Frame).

### 7.3 Vorschau

* Das Plugin initialisiert den Editor nur, wenn `StudioTestService.EditModeActive == true` **und**
  `RunService:IsEdit()` gilt (Plugins laufen während Playtests auch in den Play-DataModels; `IsEdit()` allein ist beim
  Start unzuverlässig – Constraints K37). Während eines Playtests im Edit-DataModel pausiert der Editor.
* Die Vorschau-Uhr läuft über `RunService.Heartbeat`. Dass Heartbeat im reinen Edit-Modus für Plugins feuert, ist
  nicht offiziell dokumentiert (Annahme, breite Praxis) und steht als erster Punkt in der manuellen Studio-Testliste.
* **Primär: Workspace-Vorschau.** Effekt wird mit dem Runtime-Builder (Preview-Modus) in einen eigenen Ordner
  `Workspace.AstraVFX_Preview` gebaut (`Archivable = false` ⇒ wird nicht mit dem Place gespeichert; alle
  Instanzen tragen das Attribut `AstraPreview`). Positionen: vor der Kamera, Ursprung, Auswahl oder isolierte
  „Stage“ (eigene Bodenplatte weit abseits). Optionaler Block-Dummy als Größenreferenz/Anheftziel, Kamera-Distanz-
  Voreinstellungen, Zeitfaktor, Loop, Neustart. Aufräumen bei Schließen, Dokumentwechsel, `plugin.Unloading` und
  beim Start (Reste eines Absturzes werden über das Attribut gefunden und entfernt).
* **Sekundär: isolierte Viewport-Vorschau** im Plugin-Fenster (`ViewportFrame` + `WorldModel`). Roblox rendert dort
  keine Partikel, Beams und Trails und keine dynamischen Lichter (siehe Constraints) – deshalb zeigt sie nur
  Geometrie-Komponenten exakt und markiert die übrigen als Platzhalter. Sie dient für Timing/Silhouette und
  Thumbnails, nicht als vollwertige Vorschau.

### 7.4 Panels

| Panel | Inhalt |
|---|---|
| Library | Effekte im Place, Presets, synchronisierte Dateien; Neu (leer/Preset/Textbeschreibung), Duplizieren, Löschen, Import, Export |
| Explorer | Komponentenbaum, Suche, Mehrfachauswahl, Umbenennen, Duplizieren, Aktivieren/Deaktivieren, Löschen, Drag & Drop (Umordnen/Eltern), Kontextmenüs |
| Inspector | aus `PropertySpec` generierte Felder je Typ, Mehrfachbearbeitung, Reset, Keyframe-Knopf, Spezialeditoren (Farbverlauf, Kurven, Bereiche, Vektoren, Enums, Assets) |
| Timeline | Lineal, Playhead/Scrubbing, Zoom/Pan, Loop-Bereich, Marker, Komponenten-Balken (verschieben/trimmen), Kanal-Spuren mit Keyframes (Mehrfachauswahl, Box-Auswahl, Kopieren/Einfügen, Snapping, Easing-Menü), Events, Graph-Spur, Kurvenansicht |
| Node Graph | Pan/Zoom, Knoten verschieben, Verbinden per Drag, Typ-Farben, Live-Validierung, Suchmenü, Kontextmenüs |
| Performance | Analyzer-Bericht je Qualitätsstufe, Budgets, Warnungen (ausdrücklich heuristisch) |
| Preview | Wiedergabesteuerung, Vorschau-Optionen, Viewport-Vorschau |

## 8. Claude-nativer Workflow

Zuverlässigster Weg ohne externe KI-API und ohne Studio-Zugriff für Claude:

1. **Dateien als Schnittstelle.** Claude schreibt `effects/<Name>.vfx.json` nach `docs/EFFECT_FORMAT.md` (bzw. dem
   JSON-Schema) und prüft lokal: `lune run tools/astra validate effects/X.vfx.json`, `… analyze`, `… format`.
2. **CLI erzeugt echte Roblox-Dateien.** `lune run tools/astra build effects/X.json -o build/X.rbxm` baut mit dem
   **selben** Builder wie die Runtime ein Modell (Laufzeitpaket + Effektmodul bzw. statisches Modell), das man in
   Studio einfügt.
3. **Wege nach Studio** (vom Nutzer gewählt): (a) Rojo synchronisiert `effects/*.vfx.json` per `syncRules`
   (`"use": "text"`) als `StringValue` mit dem **unveränderten JSON-Text** in `ServerStorage.AstraVFX.Sources`; die
   Library erkennt diese Quellen. Rückweg ohne Bridge: `rojo syncback` schreibt geänderte StringValues byte-genau in
   die `*.vfx.json` zurück. (JSON → ModuleScript wird bewusst **nicht** genutzt: verlustbehaftet – Schlüssel sortiert,
   `[]`/`{}` ununterscheidbar, `null` verloren; Constraints TC-2/K46.) (b) Datei-Import im Plugin (`StudioService:PromptImportFileAsync`);
   (c) optionale, ausdrücklich aktivierte localhost-Bridge (`lune run tools/astra bridge`) mit Token – das Plugin
   kann Effekte live laden und zurückschreiben.
4. **Strukturierte Generierung.** `Authoring/Generator` setzt Textbeschreibungen regelbasiert in mehrschichtige
   Effekte nach dem Phasenmodell (Anticipation → Charge → Action → Impact → Secondary → Dissipation) um; Claude kann
   das Ergebnis als Ausgangspunkt nehmen und gezielt verfeinern.

Eine direkte Text-to-VFX-Anbindung an eine externe KI-API ist **nicht** Teil von v1 (braucht API-Schlüssel und
HTTP-Freigaben); der Generator und die Datei-Schnittstelle decken den Anwendungsfall ohne externe Dienste ab.

## 9. Qualitätssicherung

| Ebene | Werkzeug | Was es beweist |
|---|---|---|
| Syntax | `lune run tools/syntax-check.luau` | alle Dateien kompilieren |
| Typen | `tools/analyzer` (`astra-analyze`, Luau-Typprüfer + Roblox-Definitionen) | Typfehler, unbekannte Roblox-Member |
| Lint/Format | `selene`, `stylua --check` | Stil, ungenutzte Variablen |
| Unit/Integration | `lune run tests/lune/run.luau` | Logik, Datenfluss, Instanz-Eigenschaften gegen Reflection-DB |
| Build | `rojo build` | Plugin- und Runtime-Paket lassen sich bauen |
| Studio | `docs/TESTING.md` (manuelle Anleitung) + Plugin-Selbsttest | echtes Rendering/Engine-Verhalten |

Status wird in `docs/PROGRESS.md` immer getrennt nach **implementiert / automatisch getestet / in Studio manuell
getestet / nicht verifiziert** geführt.

## 10. Architekturentscheidungen (ADR-Kurzform)

| # | Entscheidung | Begründung | Alternativen (verworfen) |
|---|---|---|---|
| 1 | JSON-kompatible Definition als einzige Wahrheit | Claude/Diff/Tests/Export gleich | Instanzbaum als Wahrheit (nicht diffbar, nicht Claude-tauglich) |
| 2 | Eigene Zeitauswertung statt TweenService | Scrubbing, Pausieren, Sequenz-Typen (NumberSequence/ColorSequence sind nicht tweenbar), Determinismus | TweenService (kein Seek, keine Sequenzen) |
| 3 | Eine Scheduler-Verbindung für alle Effekte | keine Verbindungs-Lecks, geringe Last | eine Verbindung pro Effekt |
| 4 | Anchored Parts + `BulkMoveTo`, Attachments am Root-Part | keine Physik, funktioniert im Edit-Modus und auf Clients | unverankerte Welds (Physik, Netzwerkbesitz) |
| 5 | `Part + SpecialMesh` für Meshes | `MeshPart.MeshId` ist per Skript nicht schreibbar | MeshPart (nur mit vorgefertigten Vorlagen) |
| 6 | Dokumente als `StringValue` im Place + ChangeHistoryService | natives Undo/Redo, Speichern mit dem Place | eigener Undo-Stack (inkonsistent mit Studio) |
| 7 | Workspace-Vorschau primär, Viewport sekundär | ViewportFrame rendert keine Partikel/Beams/Trails | Viewport-only |
| 8 | Prozedurale Komponenten als Funktionen der Zeit | exaktes Scrubbing, deterministisch, ohne Physik | Physik-Trümmer, `task.wait`-Animationen |
| 9 | Graph → geplante Aktionen auf der Zeitachse | begrenzt, deterministisch, in Timeline sichtbar | frei laufende Coroutines |
| 10 | Lune + Rojo-kompatibler Loader für Tests/CLI | echte Datentypen & Reflection-DB ohne Studio | reine Mocks |
| 11 | Instanz-`require(script…)` statt String-Requires | überall in Roblox unterstützt, von Analyzer/Loader auflösbar | require-by-string (Semantik-/Versionsrisiko) |
| 12 | Eigenes leichtgewichtiges UI-Toolkit | keine Fremdabhängigkeiten im Plugin, volle Kontrolle | React-Lua/Fusion (zusätzliche Pakete) |

## 11. Konventionen

* `--!strict` in jeder Datei; Typen aus `Core/Types` importieren statt neu zu definieren.
* Module geben eine Tabelle zurück; Klassen über `setmetatable` + `ClassName.new`. Keine globalen Variablen.
* Keine Yields in Laufzeit-Hot-Paths; keine `while true`-Schleifen; jede `RBXScriptConnection` wird gespeichert und
  getrennt (Plugin: beim `Unloading`).
* Fehler: Validierungsfehler als `Diagnostic` (kein `error`), Programmierfehler als `error`/`assert` mit Kontext.
* Benennung: Module `PascalCase`, Funktionen/Variablen `camelCase`, JSON-Schlüssel `camelCase`, öffentliche
  Runtime-API `PascalCase` (Roblox-Konvention), Konstanten `UPPER_SNAKE`.
* Kommentare auf Englisch, Dokumentation auf Deutsch.
