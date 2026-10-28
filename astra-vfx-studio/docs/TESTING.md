# Testen – automatische Prüfungen und manuelles Studio-Protokoll

ASTRA VFX Studio wird in einer Linux-Umgebung **ohne Roblox Studio** entwickelt. Alles, was sich ohne Engine
prüfen lässt, prüfen automatische Tests (Teil A). Was nur die echte Engine zeigen kann – Darstellung, Studio-Edit-
Mode, Undo, Eingaben, Netzwerk, Geräte –, prüft ein Mensch nach dem Protokoll in Teil B und trägt das Ergebnis in
die Tabelle in Teil C ein. Statusspalte **S** in [`PROGRESS.md`](PROGRESS.md) wird erst danach abgehakt.

* [Teil A – Automatische Tests](#teil-a--automatische-tests)
* [Teil B – Manuelles Studio-Protokoll](#teil-b--manuelles-studio-protokoll)
  * [B.0 Vorbereitung](#b0-vorbereitung)
  * [B.1 Selbsttest im Plugin](#b1-selbsttest-im-plugin-self-test)
  * [B.2 Phase 2 – Editor-Grundlage](#b2-phase-2--editor-grundlage)
  * [B.3 Phase 3 – Vorschau & Timeline](#b3-phase-3--vorschau--timeline)
  * [B.4 Phase 4 – Node Graph, Editoren, Presets, Import/Export](#b4-phase-4--node-graph-editoren-presets-importexport)
  * [B.5 Phase 5 – Claude-Integration](#b5-phase-5--claude-integration)
  * [B.6 Phase 6 – Performance, QA, Spiel-Laufzeit](#b6-phase-6--performance-qa-spiel-laufzeit)
  * [B.7 Offene Engine-Fragen U1–U46](#b7-offene-engine-fragen-u1u46)
* [Teil C – Ergebnisprotokoll](#teil-c--ergebnisprotokoll)

---

## Teil A – Automatische Tests

### A.1 Befehle (im Ordner `astra-vfx-studio/`)

```bash
tools/check.sh                                  # alles; Exit-Code != 0, wenn eine Prüfung fehlschlägt
tools/check.sh --quick                          # nur Syntax + Tests
lune run tests/lune/run.luau                    # alle Specs
lune run tests/lune/run.luau -- Net             # nur Tests, deren voller Name "Net" enthält
lune run tests/lune/run.luau -- --verbose       # jeden Test einzeln auflisten
/root/tools/bin/astra-analyze --defs /root/tools/ref/globalTypes.d.luau --project default.project.json
selene src tests/framework tests/specs tools
stylua --check src tests tools
```

`tools/check.sh` führt nacheinander aus:

| Schritt | Werkzeug | Inhalt |
|---|---|---|
| syntax | `lune run tools/syntax-check.luau -- src tests tools` | jede Luau-Datei kompiliert |
| tests | `lune run tests/lune/run.luau` | alle `tests/specs/*.spec.luau` |
| types | `astra-analyze --project default.project.json` | Luau-Typprüfung (strict) gegen die Roblox-API-Definitionen der Engine 0.745; wird übersprungen, wenn Binary oder Definitionen fehlen |
| lint | `selene` | Stil, ungenutzte Variablen, verbotene Globals |
| format | `stylua --check` | einheitliche Formatierung |
| build plugin / runtime | `rojo build` | `build/AstraVFXStudio.rbxmx` und `build/AstraVFX.rbxm` lassen sich bauen |

Zusätzlich für die Beispiele (noch nicht Teil von `check.sh`):

```bash
/root/tools/bin/astra-analyze --defs /root/tools/ref/globalTypes.d.luau --project examples/default.project.json \
    examples/ServerScriptService examples/StarterPlayerScripts
rojo build examples/default.project.json -o build/AstraVFX-Examples.rbxl
```

### A.2 Was die Tests tun

* **Loader** (`tests/lune/Loader.luau`) baut den Rojo-Baum aus `default.project.json` als echte Lune-Instanzen
  nach (Ordner → Folder, `init.luau` → ModuleScript, `*.vfx.json` → StringValue mit Rohtext …) und stellt ein
  Roblox-kompatibles `require(instance)` bereit. Lune-Instanzen prüfen Eigenschaftsnamen und Werttypen gegen die
  echte Reflection-Datenbank – ein erfundenes Property ist ein Testfehler.
* **Fakes** (`tests/lune/Fakes.luau`) bilden die wenigen Engine-Mitglieder nach, die Lune fehlen
  (`RunService.Heartbeat`/`PreRender`/`BindToRenderStep`, `ParticleEmitter:Emit/Clear`, `Trail:Clear`,
  `Sound:Play/Stop`, `WorldRoot:BulkMoveTo`, `Model:GetPivot`, Instanz-Ereignisse …) und **protokollieren** jeden
  Aufruf (`ctx.fakes.emits`, `ctx.fakes.sounds`, `ctx.fakes.renderLog` …). `ctx.fakes:step(dt)` treibt einen Frame.
* **Specs** decken ab: Kernmodule (Json, Codec, Easing, Curves, Timeline, Graph, Migration, Validation, Quality,
  Compiler, Builder, Player, Scheduler, Pool), alle 17 Komponententypen, die öffentliche API (`Runtime.spec`,
  `Net.spec`, `EndToEnd.spec`), Abhängigkeitsregeln der Schichten (`Dependencies.spec`), Plugin-Bausteine (UI-
  Fundament, Widgets, Werte-Editoren, History, Settings gegen Fakes), die Effektdateien im Repository
  (`EffectFiles.spec`: `tests/fixtures/concept-v0.json` migriert exakt zu `effects/VioletImpact.vfx.json`, die Datei
  ist kanonisch und gültig) und das Beispiel-Place (`Examples.spec`: lädt `examples/default.project.json` und führt
  Server- und Client-Skript gegen Fakes aus).
* `ctx.environment` ist `"lune"` oder `"studio"`; Tests, die Fakes oder Dateizugriff brauchen, laufen nur in Lune
  (`T.itIf(ctx.environment == "lune", …)`). `ctx.readFile(path)` (nur Lune) liest Dateien relativ zum
  Projektordner.

### A.3 Was die automatischen Tests beweisen – und was nicht

| Beweisen | Beweisen **nicht** |
|---|---|
| Logik und Datenfluss (Migration, Validierung, Kompilieren, Zeitplan, Kurven, Graph-Entrollen) | wie ein Effekt **aussieht** (Lune rendert nichts) |
| Determinismus (gleiche Definition + Seed ⇒ gleiche Instanzen und CFrames) | Partikelsimulation, Licht, Materialien, Transparenz-Sortierung |
| dass gebaute Instanzen nur existierende Eigenschaften mit gültigen Werttypen setzen (Reflection-DB) | dass die Engine diese Werte so **verwendet** wie angenommen (z. B. Beam-Breitenachse U3, `TimeScale = 0` U2) |
| Aufrufreihenfolge gegen Engine-Fakes (wann `Emit`, `BindToRenderStep`, `BulkMoveTo` …) | echtes Engine-Timing (Emit im Bau-Frame K6/U14, Heartbeat im Edit Mode U1) |
| Typkorrektheit gegen die Roblox-API 0.745 (`astra-analyze`) | Laufzeitverhalten neuerer Engine-Versionen; Typen von `any`-Werten (z. B. `require(...) :: any`) |
| dass Plugin-UI-Bausteine konstruierbar sind und auf simulierte Eingaben reagieren | Layout, Lesbarkeit, Fokus, echte Maus-/Tastatureingaben in Widgets (U6) |
| History/Settings gegen Fakes | echtes Undo/Redo von Studio (ChangeHistoryService, U4/U5/U7–U9) |
| Net-Nachrichten, Prüfung, Klemmen, Fake-Remotes | Replikation, Paketverlust, Throttle, Streaming (U38, ST-1) |
| Rojo-Builds gelingen | dass Studio die Dateien fehlerfrei öffnet und das Plugin lädt |
| – | Performance auf echten Geräten (Mobile, Konsole), Speicher, Draw Calls |

Die Fakes sind selbst Annahmen (im Kopf von `Fakes.luau` dokumentiert): Sie belegen *Aufrufe*, nicht *Wirkung*.
Bekannte Lune-Unterschiede: abgeleitete Properties wie `BasePart.Position` sind nicht lesbar (`CFrame.Position`
benutzen), `WaitForChild` und Remote-Methoden fehlen, Lune rundet CFrame-Properties beim Schreiben (~1e-5).

---

## Teil B – Manuelles Studio-Protokoll

**Format:** Jeder Prüfpunkt hat eine ID (`M<Phase>.<Nr>` bzw. `U<Nr>`), nummerierte Schritte, eine Erwartung und ein
Kästchen. Ergebnis jedes Punktes in Teil C eintragen (✅ bestanden, ❌ fehlgeschlagen, ⚠️ teilweise/abweichend), bei
❌/⚠️ mit Screenshot oder Output-Text. Prüfpunkte, deren Phase noch nicht implementiert ist, als „n/a“ markieren.
Die Abnahmekriterien des Projektauftrags sind mit **[Abnahme]** gekennzeichnet.

### B.0 Vorbereitung

1. Studio-Version notieren: Command Bar (*View → Command Bar*) → `print(version())`. Betriebssystem notieren.
2. *View → Output* öffnen (alle Meldungen sichtbar lassen).
3. Plugin bauen: `rojo build default.project.json -o build/AstraVFXStudio.rbxmx`. Datei in den lokalen
   Plugin-Ordner kopieren (Studio: *Plugins → Plugins Folder*) und Studio neu starten.
4. Testplace: neues *Baseplate*-Template, nicht in einem echten Projekt testen.
5. Für Laufzeit-Prüfungen ohne Plugin: `rojo build examples/default.project.json -o build/AstraVFX-Examples.rbxl`
   (siehe [`examples/README.md`](../examples/README.md)).

- [ ] B.0 Vorbereitung erledigt (Version, OS, Plugin-Build-Datum in Teil C eingetragen)

### B.1 Selbsttest im Plugin (Self-Test)

Der Toolbar-Knopf **Self-Test** (Toolbar „ASTRA VFX“, `docs/PLUGIN_CONTRACTS.md` §9) führt die mitgelieferten Specs
(`Tests.Specs` im Plugin-Build) in Studio mit `ctx.environment = "studio"` aus: Tests, die Lune-Fakes brauchen,
werden übersprungen; Tests wie „Easing stimmt mit `TweenService:GetValue` überein“ laufen **nur** dort gegen die
echte Engine.

1. Leeres Baseplate öffnen, Toolbar **ASTRA VFX → Self-Test** klicken.
2. Output beobachten.

Erwartung: eine Zusammenfassung `N passed, 0 failed, M skipped`; keine Fehler außerhalb der Testausgabe; danach
keine Reste in Workspace (`AstraVFX_*`-Ordner) oder unter `CurrentCamera`.

Solange der Plugin-Bootstrap (`src/Plugin/init.server.luau`, Phase 2) fehlt, dieselben Specs über die Command Bar
starten: `build/AstraVFXStudio.rbxmx` per *Rechtsklick ServerStorage → Insert from File* einfügen, dann:

```lua
local root = game:GetService("ServerStorage"):FindFirstChild("AstraVFXStudio")
local TestFramework = require(root.Tests.Framework)
local function use(path)
	local node = root
	for part in string.gmatch(path, "[^%.]+") do
		node = node:FindFirstChild(part) or error("not found: " .. path)
	end
	return require(node)
end
local specs = {}
for _, m in root.Tests.Specs:GetDescendants() do
	if m:IsA("ModuleScript") and string.match(m.Name, "%.spec$") then
		table.insert(specs, { name = (string.gsub(m.Name, "%.spec$", "")), fn = require(m) })
	end
end
table.sort(specs, function(a, b) return a.name < b.name end)
local report = TestFramework.run(specs, use, { environment = "studio" })
print(TestFramework.format(report, false))
```

- [ ] B.1 Selbsttest: 0 failed (Anzahl passed/skipped notieren; jede Fehlermeldung vollständig in Teil C)

### B.2 Phase 2 – Editor-Grundlage

Voraussetzung: Plugin-Bootstrap, Editor, Storage, Explorer, Inspector (Phase 2).

**M2.1 Plugin lädt sauber**
1. Studio mit installiertem Plugin starten, Baseplate öffnen.
2. Toolbar „ASTRA VFX“ suchen; Knopf **Studio** klicken.

Erwartung: Toolbar mit den Knöpfen Studio, je Panel ein Knopf, Export, Self-Test; Panels öffnen sich als
DockWidgets; Output ohne Fehler/Warnungen von ASTRA.
- [ ] M2.1

**M2.2 Kein Editor im Playtest** (Constraints K37, U10)
1. Editor offen lassen, *Play* (F5) starten, nach 5 s stoppen.
2. Während des Playtests Output und Panels beobachten.

Erwartung: Im Play-DataModel startet kein zweiter Editor (keine doppelten Widgets, keine Fehler); der Editor im
Edit-DataModel pausiert und arbeitet nach dem Stopp normal weiter.
- [ ] M2.2

**M2.3 [Abnahme] Neuen Effekt anlegen**
1. Panel *Library* → **Neu** → leerer Effekt, Name `TestEffect`.
2. Im Studio-Explorer `ServerStorage.AstraVFX.Effects` öffnen.

Erwartung: Der Effekt ist geöffnet (Explorer-Panel zeigt ihn); in `ServerStorage.AstraVFX.Effects` liegt ein
`StringValue` `TestEffect` mit JSON-Text (`"schemaVersion": 1`) und den Attributen `AstraId`,
`AstraSchemaVersion`.
- [ ] M2.3

**M2.4 [Abnahme] ParticleEmitter-Komponente hinzufügen**
1. Im ASTRA-Explorer **+** → *Particles* wählen.
2. Die neue Komponente anklicken.

Erwartung: Komponente erscheint im Baum; der Inspector zeigt die Partikel-Eigenschaften (Texture, Color, Size,
Rate, Lifetime, Speed …, siehe `docs/COMPONENTS_SPEC.md` §2); der StringValue enthält eine Komponente mit
`"type": "particles"`.
- [ ] M2.4

**M2.5 Inspector schreibt ins Dokument**
1. Im Inspector `rate` auf `50` setzen, Enter.
2. Den StringValue im Properties-Fenster ansehen.

Erwartung: `"rate": 50` steht im JSON; der Diagnose-Bereich zeigt keine Fehler.
- [ ] M2.5

**M2.6 Undo/Redo über Studio** (U5, U8, U9)
1. Nach M2.5 **Strg+Z** (bzw. Studio-Undo-Knopf), dann **Strg+Y**.
2. Studio-Undo-Liste (Pfeil neben dem Undo-Knopf) ansehen.

Erwartung: Undo stellt `rate` auf den alten Wert zurück (Inspector und JSON), Redo wieder auf 50; genau **ein**
Undo-Schritt pro Änderung mit lesbarem Namen; auch ein Slider-Ziehen ergibt nur einen Schritt.
- [ ] M2.6

**M2.7 [Abnahme] Gespeicherter Effekt öffnet wieder**
1. Place speichern (*File → Save to File*), Studio komplett schließen.
2. Studio starten, Place öffnen, *Library* öffnen, `TestEffect` öffnen.

Erwartung: Effekt mit allen Komponenten und Werten (rate 50) ist wieder da; Diagnosen leer.
- [ ] M2.7

**M2.8 Plugin neu laden / entladen** (U7, U28)
1. Plugin über *Plugins → Manage Plugins* deaktivieren und wieder aktivieren (oder neue Build-Datei einspielen).
2. Workspace, CurrentCamera und Output prüfen.

Erwartung: keine Reste (`AstraVFX_Preview`, Instanzen mit Attribut `AstraPreview`), keine verwaisten
RenderStep-Bindungen, keine doppelten PluginActions/Menüs, keine offene Undo-Aufnahme.
- [ ] M2.8

**M2.9 Tastenkürzel bei fokussiertem Widget** (U6) → Ablauf unter U6 in B.7.
- [ ] M2.9

### B.3 Phase 3 – Vorschau & Timeline

Voraussetzung: PreviewEngine, Timeline. **Zuerst U1 (B.7) prüfen** – davon hängt die Vorschau-Uhr ab.

**M3.1 Vorschau zeigt den Effekt**
1. `TestEffect` öffnen, im Preview-Panel **Play**.
2. Im Studio-Explorer `Workspace.AstraVFX_Preview` öffnen.

Erwartung: Partikel sind im Viewport sichtbar; der Ordner existiert, `Archivable = false`, alle Instanzen tragen
das Attribut `AstraPreview`; die Timeline-Zeit läuft mit (U1).
- [ ] M3.1

**M3.2 [Abnahme] Farbänderung ist in der Vorschau sichtbar**
1. Während die Vorschau läuft, im Inspector `color` der Partikel auf Rot (`#FF0000`) setzen.
2. Danach einen Farbverlauf Gelb → Blau im Verlaufseditor setzen.

Erwartung: Spätestens nach dem Neubau (~0,1 s) haben neu emittierte **und** lebende Partikel die neue Farbe
(Engine: `Color` wirkt auf lebende Partikel); keine Fehler; kein zweiter Vorschau-Ordner.
- [ ] M3.2

**M3.3 [Abnahme] Keyframes werden zur richtigen Zeit ausgewertet**
1. Eine *Part*-Komponente hinzufügen. Kanal `transparency`: Keyframe 0 s = 0 (Easing Linear), Keyframe 1 s = 1.
2. Playhead auf **0,25 s**, **0,5 s**, **1,0 s** ziehen; jeweils das Part im Studio-Explorer unter
   `AstraVFX_Preview` wählen und `Transparency` im Properties-Fenster ablesen.
3. Easing des ersten Keyframes auf `Quad` (= Quad.Out) stellen, erneut bei 0,25 s und 0,5 s ablesen.

Erwartung: Linear 0.25 / 0.5 / 1.0; Quad.Out **0.4375 / 0.75**; Timeline-Anzeige und gelesene Werte stimmen
überein; zweimaliges Scrubben auf dieselbe Zeit ergibt identische Werte.

Gegenprobe ohne Plugin (Laufzeit, Command Bar im Beispiel-Place oder mit `AstraVFX` in ReplicatedStorage):

```lua
local A = require(game:GetService("ReplicatedStorage").AstraVFX)
A.Register({ schemaVersion = 1, id = "keytest", name = "KeyTest", duration = 2, components = {
	{ id = "core", name = "Core", type = "part", tracks = { { id = "lin", channel = "transparency",
		keyframes = { { time = 0, value = 0 }, { time = 1, value = 1 } } } } },
	{ id = "eased", name = "Eased", type = "part", tracks = { { id = "quad", channel = "transparency",
		keyframes = { { time = 0, value = 0, easing = "Quad" }, { time = 1, value = 1 } } } } },
} })
local h = A.Play("KeyTest", { Autoplay = false })
for _, t in { 0.25, 0.5, 1 } do
	h:Seek(t)
	for _, d in workspace.AstraVFX_KeyTest:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("AstraComponent") then
			print(t, d:GetAttribute("AstraComponent"), d.Transparency)
		end
	end
end
h:Destroy()
```

Erwartung (in Lune bereits so gemessen): `core` 0.25 / 0.5 / 1, `eased` 0.4375 / 0.75 / 1; nach `Destroy` kein
`AstraVFX_KeyTest` mehr in Workspace.
- [ ] M3.3

**M3.4 Scrubbing, Loop, Zeitfaktor** (U2)
1. Effekt mit Partikeln: Loop an, Zeitfaktor 0.25, dann Pause, dann Scrubben.

Erwartung: Zeitlupe verlangsamt Partikel (TimeScale ≤ 1); Pause friert sie ein (siehe U2); Scrubben leert Partikel
und zeigt Geometrie exakt; Loop wiederholt nahtlos.
- [ ] M3.4

**M3.5 [Abnahme] Vorschau-Objekte bleiben nach dem Schließen nicht zurück**
1. Vorschau laufen lassen, dann nacheinander: (a) Preview-Panel schließen, (b) anderen Effekt öffnen,
   (c) Plugin deaktivieren, (d) Place speichern, schließen und neu öffnen.
2. Jeweils Workspace und `Workspace.CurrentCamera` im Explorer prüfen.

Erwartung: Nach (a)–(c) kein `AstraVFX_Preview` und keine Instanz mit Attribut `AstraPreview`; nach (d) enthält die
gespeicherte Datei keine Vorschau-Objekte (`Archivable = false`). Absturz-Simulation: Studio während der Vorschau
per Task-Manager beenden, Place (Autosave/Recovery) öffnen → das Plugin entfernt Reste beim Start.
- [ ] M3.5

**M3.6 Undo berührt die Vorschau nicht** (U4) → Ablauf U4.
- [ ] M3.6

**M3.7 Viewport-Vorschau** (U19)
1. Preview-Panel → Viewport-Vorschau eines Effekts mit Partikeln, Beam, Part und Licht.

Erwartung: Parts/Geometrie sichtbar, Partikel/Beams/Trails/Lichter als Platzhalter markiert; Hinweistext
sichtbar. Was tatsächlich gerendert wird, unter U19 notieren.
- [ ] M3.7

**M3.8 Sound-Vorschau** (U21) → Ablauf U21.
- [ ] M3.8

### B.4 Phase 4 – Node Graph, Editoren, Presets, Import/Export

**M4.1 Graph steuert die Timeline**
1. Graph: `OnPlay → Delay(0.5) → Emit(target = Partikel, count = 30)`.
2. Effekt abspielen; einen Zyklus `A → B → A` zu verbinden versuchen.

Erwartung: Burst genau bei 0,5 s (Graph-Spur in der Timeline zeigt die Aktion); die Zyklus-Verbindung wird
abgelehnt (Meldung), das Dokument bleibt gültig.
- [ ] M4.1

**M4.2 Werte-Editoren**
1. Farbverlauf mit 5 Stopps, Sequenz-Editor für `size` mit Envelope, Easing-Picker, Kurvenansicht.

Erwartung: Vorschau übernimmt jede Änderung; höchstens 20 Keypoints; ein Ziehen = ein Undo-Schritt.
- [ ] M4.2

**M4.3 Presets** (U25)
1. Jedes Preset aus der Library öffnen und bei Qualität Low, Medium und High abspielen.

Erwartung: alle spielen ohne Fehler; Low sichtbar sparsamer, Silhouette bleibt; mitgelieferte Texturen werden
angezeigt.
- [ ] M4.3

**M4.4 Import**
1. *Library → Import* → `effects/VioletImpact.vfx.json` wählen (Dialog `StudioService:PromptImportFileAsync`).
2. Danach `tests/fixtures/concept-v0.json` importieren.

Erwartung: Beide ergeben den Effekt `VioletImpact` (Kugel, `scale` 1 → 8 über 1,2 s, Farbe `#9641FF`); beim
Konzeptformat erscheinen Migrationshinweise, keine Fehler.
- [ ] M4.4

**M4.5 [Abnahme] Export erzeugt echte, benutzbare Roblox-Objekte** (U26, U29)
1. `VioletImpact` öffnen → **Export** (Laufzeitpaket).
2. Im Explorer `ReplicatedStorage.AstraVFX` prüfen; zusätzlich *Export → statisches Modell* (falls angeboten).

Erwartung: `ReplicatedStorage.AstraVFX` ist ein ModuleScript mit `Core`, `Net` und `Effects` (darin der Effekt als
ModuleScript oder StringValue); ein statisches Modell enthält echte Parts/Emitter/Beams mit den gewählten Werten
und lässt sich frei verschieben. Ein evtl. „Script Injection“-Dialog wird notiert (U26).
- [ ] M4.5

**M4.6 [Abnahme] Exportierter Effekt läuft ohne installiertes Plugin**
1. Nach M4.5 Place speichern. Plugin deaktivieren (*Manage Plugins*), Studio neu starten, Place öffnen.
2. LocalScript in `StarterPlayerScripts` (erst die Erstreplikation abwarten, `docs/RUNTIME_API.md` §3.2):
   `if not game:IsLoaded() then game.Loaded:Wait() end; require(game.ReplicatedStorage:WaitForChild("AstraVFX")).Play("VioletImpact", { Position = Vector3.new(0, 5, 0) })`
3. *Play* (F5).

Erwartung: Die violette Kugel erscheint und wächst; Output ohne Fehler; nach ~2,5 s ist der Container weg
(gepoolt, `Parent = nil`). Zusätzlich gilt: Das Beispiel-Place aus B.6/M6.1 enthält gar kein Plugin und ist der
Referenzfall.
- [ ] M4.6

**M4.7 Rojo-Synchronisation** (U31, U44) → Abläufe U31/U44.
- [ ] M4.7

### B.5 Phase 5 – Claude-Integration

**M5.1 Effektdateien per Rojo**
1. Projekt mit `syncRules` für `*.vfx.json` per `rojo serve` verbinden; `effects/VioletImpact.vfx.json` im Editor
   ändern (z. B. `duration` 3) und speichern.

Erwartung: `ServerStorage.AstraVFX.Sources.VioletImpact` (StringValue) enthält sofort den neuen Text; die Library
zeigt die Änderung (U31).
- [ ] M5.1

**M5.2 Bridge** (U26, U33)
1. `lune run tools/astra bridge` starten, Token kopieren; im Plugin Bridge aktivieren, URL + Token eintragen.
2. Effekt laden, ändern, „Zur Bridge speichern“.

Erwartung: einmaliger HTTP-Berechtigungsdialog für localhost; Laden/Speichern funktioniert; die Datei ist
kanonisch formatiert; ohne Token antwortet die Bridge mit Fehler.
- [ ] M5.2

**M5.3 CLI-Build in Studio** (TC-8)
1. `lune run tools/astra build effects/VioletImpact.vfx.json -o build/VioletImpact.rbxm`, in Studio einfügen.

Erwartung: Modell lädt; Texturen von Emittern/Beams sind gesetzt (Serialisierung `Texture` vs. `TextureContent`);
Effekt spielt wie im Editor.
- [ ] M5.3

**M5.4 Große Texte und JSON** (U30, U32) → Abläufe U30/U32.
- [ ] M5.4

### B.6 Phase 6 – Performance, QA, Spiel-Laufzeit

**M6.1 Beispiel-Place** (ohne Plugin; [`examples/README.md`](../examples/README.md))
1. `build/AstraVFX-Examples.rbxl` öffnen, *Play*.
2. 12 s warten; dann zum Würfel `VFXTarget` laufen und dort 8 s stehen.
3. Mit der Maus auf den Boden zeigen, **F** drücken; dann **G** drücken und herumlaufen.
4. Chat öffnen (`/`), im Textfeld F tippen.

Erwartung: (2) alle 4 s eine violette Kugel am Würfel; am Würfel 10 Schaden pro Zyklus, jeweils ~0,6 s nach dem
Erscheinen (Lebensanzeige). (3) Feuerexplosion genau am Mauspunkt, kurzer FOV-Kick beim Aufblitzen; G: Kugel 6 Studs
vor dem Charakter, folgt beim Laufen. (4) im Chat getipptes F löst **nichts** aus. Output ohne Fehler.
- [ ] M6.1

**M6.2 Server und mehrere Clients**
1. *Test → Clients and Servers*, 2 Spieler, *Start*.
2. Auf Client 1 F/G drücken; auf beiden Clients die Würfel-Effekte beobachten; im Server-Fenster Workspace
   ansehen.

Erwartung: Beide Clients sehen die Server-Effekte (zeitgleich ± Latenz); F/G sieht nur Client 1; im
Server-Workspace entstehen **keine** `AstraVFX_*`-Container; `AstraVFX.Net.stats` (Command Bar, Ansicht des Clients:
`local s = require(game.ReplicatedStorage.AstraVFX).Net.stats; print(s.received, s.played, s.ignored)`) zeigt
`played` steigend, `ignored` 0.
- [ ] M6.2

**M6.3 StreamingEnabled** (ST-1–ST-4)
1. `Workspace.StreamingEnabled = true`, `StreamingTargetRadius` klein (z. B. 64); `VFXTarget` auf 400 Studs
   Entfernung verschieben; Server-Skript auf `{ Attach = target }` statt `{ CFrame = … }` umstellen.
2. Abspielen, weit weg stehen, dann hinlaufen.

Erwartung: Weit weg: Effekt erscheint trotzdem an der Ersatz-CFrame (oder gar nicht sichtbar wegen Distanz), keine
Fehler; nah: Effekt folgt dem Ziel. `ignored` bleibt 0.
- [ ] M6.3

**M6.4 Qualitätsstufen** (U14, U40)
1. Live-Test (veröffentlichtes Place) mit Grafikqualität 1, 5 und 10 im Spielmenü; in der Client-Konsole (F9)
   Partikelanzahl/Optik vergleichen.
2. In Studio-Playtest: `print(require(game.ReplicatedStorage.AstraVFX.Core.Quality).detect())`.

Erwartung: Stufen 1–3 → Low, 4–7 → Medium, 8–10 → High (Annahme, `Core/Quality`), Automatic → Medium; in Studio
immer Medium.
- [ ] M6.4

**M6.5 Last und Geräte** (U14, U25, U36)
1. Command Bar im Playtest (Ansicht des Clients): 30× `FireExplosion` an zufälligen Punkten innerhalb von 2 s:

   ```lua
   local A = require(game:GetService("ReplicatedStorage").AstraVFX)
   for i = 1, 30 do
   	task.delay(i / 15, function()
   		A.Play("FireExplosion", { Position = Vector3.new(math.random(-40, 40), 0, math.random(-40, 40)) })
   	end)
   end
   ```

2. MicroProfiler (Strg+F6) und *View → Stats*/`Stats.InstanceCount` beobachten; auf einem Mobilgerät wiederholen.

Erwartung: keine Fehler; Frametime-Spitzen notieren; nach dem Abklingen sinkt `InstanceCount` wieder auf den
Ausgangswert plus die gepoolten Kopien (höchstens 2 freie Kopien pro Variante, ohne Parent); `ActiveCount()` ist 0;
auf Mobile mit niedriger Grafikstufe sichtbar weniger Partikel (`"Auto"` → Low).
- [ ] M6.5

**M6.6 Obergrenze aktiver Effekte**
1. Command Bar im Playtest (Ansicht des Clients):
   `local A = require(game.ReplicatedStorage.AstraVFX); A.SetMaxActive(5); for i = 1, 10 do A.Play("FireExplosion", { Position = Vector3.new(i * 6, 0, 0) }) end; print(A.ActiveCount())`
2. Danach: `local A = require(game.ReplicatedStorage.AstraVFX); A.StopAll(true); for i = 1, 5 do A.Play("VioletImpact", { Position = Vector3.new(i * 6, 4, 0), Loop = true }) end; print(A.Play("FireExplosion"))`

Erwartung: (1) Ausgabe `10` – `ActiveCount()` zählt auch ausklingende Effekte; die ersten fünf werden für die
letzten fünf sofort gestoppt und zeigen nichts mehr, sichtbar sind nur die letzten fünf Explosionen. (2) Ausgabe
`nil` mit der Warnung `[AstraVFX] Play "FireExplosion" refused: the limit of 5 active effects … is filled by
looping effects …`. Zum Schluss (eigene Zeile, gleiches `local A = …` davor) `A.StopAll(true); A.SetMaxActive(A.DEFAULT_MAX_ACTIVE)`.
- [ ] M6.6

**M6.7 Kamera-Komponenten**
1. Effekt mit `cameraShake` und `screenFlash` im Playtest-Client 20× hintereinander abspielen, Kamera dabei drehen.

Erwartung: Shake ohne Drift der Blickrichtung (Annahme aus `COMPONENTS_SPEC.md` §17), Kamera danach exakt wie
vorher; `ColorCorrectionEffect` unter der Kamera verschwindet nach jedem Flash.
- [ ] M6.7

**M6.8 Unzuverlässige Nachrichten** (U38) → Ablauf U38.
- [ ] M6.8

### B.7 Offene Engine-Fragen U1–U46

Quelle: `docs/ROBLOX_API_CONSTRAINTS.md` §26 (dort: Frage, Stand, Blockiert). Reihenfolge = Priorität. Ergebnisse
mit Datum und Studio-Version in Teil C **und** in die Spalte „Stand“ der Constraints-Tabelle übernehmen.

#### P0 – blockiert die Architektur (zuerst prüfen)

**U1 – Feuern Heartbeat & Co. für Plugin-/Studio-Code im reinen Edit Mode?** (Scheduler, Vorschau, Timeline-Uhr)

1. Baseplate im Edit Mode (kein Play), Command Bar, Startskript ausführen:

   ```lua
   local RunService = game:GetService("RunService")
   local u = { stats = {}, conns = {}, t0 = os.clock() }
   for _, name in { "Heartbeat", "PreRender", "RenderStepped", "PreSimulation", "Stepped", "PostSimulation" } do
   	local s = { n = 0, sum = 0, max = 0 }
   	u.stats[name] = s
   	local ok, c = pcall(function()
   		return RunService[name]:Connect(function(a, b)
   			local dt = if name == "Stepped" then b else a
   			s.n += 1
   			s.sum += dt
   			s.max = math.max(s.max, dt)
   		end)
   	end)
   	if ok then table.insert(u.conns, c) else s.err = tostring(c) end
   end
   _G.AstraU1 = u
   print("U1 läuft – nach ~10 s das Stoppskript ausführen")
   ```

2. ~10 s warten (Studio im Vordergrund, Viewport sichtbar), dann Stoppskript:

   ```lua
   local u = _G.AstraU1
   for _, c in u.conns do c:Disconnect() end
   local elapsed = os.clock() - u.t0
   for name, s in u.stats do
   	print(string.format("U1 %-14s %6d Events in %.1f s = %6.1f/s  dt mittel %.4f  max %.4f %s",
   		name, s.n, elapsed, s.n / elapsed, if s.n > 0 then s.sum / s.n else 0, s.max, s.err or ""))
   end
   _G.AstraU1 = nil
   ```

3. Wiederholen mit: (a) Studio minimiert, (b) ein Script-Tab aktiv statt des Viewports, (c) ein anderes
   Programm im Vordergrund, (d) ein ASTRA-Widget (oder beliebiges DockWidget) im Vordergrund.
4. Sobald das Plugin läuft: dieselbe Messung aus Plugin-Code (Vorschau-Uhr; Timeline-Zeit gegen eine Stoppuhr).

Notieren: Events/s und dt (mittel/max) je Event und Zustand. Erwartung (Annahme): Heartbeat ≈ Bildrate (≈ 60/s,
dt ≈ 0,017) im Edit Mode. **Wenn Heartbeat im Edit Mode nicht feuert**, ist die Vorschau-Uhr (ARCHITECTURE §7.3)
umzubauen – sofort melden.
- [ ] U1

**U2 – `ParticleEmitter.TimeScale = 0` und Zwischenwerte im Edit Mode** (Pause/Zeitlupe)

1. Command Bar:
   `local p = Instance.new("Part"); p.Anchored = true; p.Position = Vector3.new(0, 5, 0); p.Parent = workspace; local e = Instance.new("ParticleEmitter"); e.Rate = 50; e.Lifetime = NumberRange.new(3); e.Parent = p; _G.U2 = e`
2. Nach 2 s: `_G.U2.TimeScale = 0` – 5 s beobachten. Dann `0.3`, dann `1`. Danach dasselbe im Playtest.

Notieren: Frieren Partikel sofort ein? Verschwinden sie? Entstehen bei 0 neue? Wirkt 0.3 als Zeitlupe? Screenshots.
- [ ] U2

**U3 – Beam-Breitenachse bei `FaceCamera = false`** (Beam-Builder, Slash-Presets)

1. Command Bar: zwei verankerte Parts 10 Studs auseinander, je ein Attachment `A0`/`A1`, Beam mit
   `FaceCamera = false`, `Width0 = Width1 = 3`, `Attachment0/1` gesetzt.
2. `A0.Orientation` nacheinander auf `(90, 0, 0)`, `(0, 90, 0)`, `(0, 0, 90)` setzen (A1 gleich mitdrehen), jeweils
   Drauf- und Seitenansicht.

Notieren: Welche lokale Achse (X/Y/Z) des Attachments gibt die Breitenrichtung vor? Wie wird zwischen A0 und A1
interpoliert, wenn sie verschieden gedreht sind?
- [ ] U3

**U4 – Ignoriert ChangeHistoryService `Archivable = false`-Instanzen?** (Vorschau-Konzept)

1. Command Bar:

   ```lua
   local CHS = game:GetService("ChangeHistoryService")
   local id = CHS:TryBeginRecording("AstraU4")
   local f = Instance.new("Folder"); f.Name = "U4_Preview"; f.Archivable = false; f.Parent = workspace
   local p = Instance.new("Part"); p.Name = "U4_Child"; p.Anchored = true; p.Parent = f -- Archivable = true
   local q = Instance.new("Part"); q.Name = "U4_Normal"; q.Anchored = true; q.Parent = workspace
   CHS:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
   ```

   (Verweigert die Command Bar `TryBeginRecording`, dasselbe in einem lokalen Test-Plugin ausführen.)
2. Strg+Z, Strg+Y, nochmal Strg+Z.

Notieren: Verschwindet/erscheint `U4_Preview` bzw. `U4_Child` mit Undo/Redo, oder nur `U4_Normal`? Entstehen
Duplikate?
- [ ] U4

**U5 – Undo/Redo von `SetAttribute`, `StringValue.Value`, `Parent = nil`** (Storage)

1. Command Bar: StringValue `U5` in ServerStorage anlegen (`Value = "a"`). Dann in **einer** Aufnahme
   (`TryBeginRecording` … `FinishRecording(…, Commit)`): `Value = "b"`, `SetAttribute("AstraId", "x")`, einen
   zweiten StringValue `U5b` auf `Parent = nil` setzen.
2. Undo, Werte ausgeben; Redo, Werte ausgeben.

Erwartung: Undo stellt `"a"`, kein Attribut und `U5b` wieder her; Redo umgekehrt. Abweichungen je Typ notieren.
- [ ] U5

**U6 – Studio-Kürzel bei fokussiertem Widget** (Timeline-/Graph-Kürzel)

1. Ein Part im Workspace selektieren. In ein ASTRA-Widget (Input-Catcher-Fläche, z. B. Timeline) klicken.
2. Nacheinander Entf, Strg+Z, Strg+D, Strg+C/Strg+V drücken; Explorer und Undo-Liste beobachten.
3. Dasselbe mit Fokus in einer TextBox des Widgets; dann eine gebundene PluginAction-Taste ohne Widget-Fokus.

Notieren: Welche Kürzel wirken auf die Studio-Selektion (Part gelöscht/dupliziert?), welche erreichen das Widget?
- [ ] U6

#### P1 – vor der betroffenen Komponente klären

| ☐ | ID | Frage (kurz) | So testen | Notieren |
|---|---|---|---|---|
| ☐ | U7 | Sieht ein neu geladenes Plugin seine offene Recording? | Im Plugin `TryBeginRecording` ohne Finish, Plugin neu laden; `IsRecordingInProgress()` und `FinishRecording(id, Cancel)` aufrufen | Rückgaben, Fehlermeldungen |
| ☐ | U8 | Änderungen ohne Recording | Property per Plugin ohne Recording ändern, dann eine normale Nutzeraktion, dann Undo | Warntext? Landet die Änderung im nächsten Waypoint? |
| ☐ | U9 | `OnUndo(waypoint)`-Inhalt; `Append` nach fremdem Waypoint | Recording mit `name ≠ displayName`, Undo, Payload loggen; `Append` nach einer Nutzeraktion | name oder displayName? Append-Verhalten |
| ☐ | U10 | `EditModeActive` / `IsEdit()` beim Start | Im Plugin-Start und per `GetPropertyChangedSignal("EditModeActive")` in Edit, Play, Run, Clients-and-Servers loggen | Werte je Modus und Zeitpunkt |
| ☐ | U11 | Flipbook-Texturgrößen | Atlanten 256², 512², 1024², 2048×512, 4096² mit nummerierten Frames als Emitter-Textur, `FlipbookLayout` Grid4/8 | Was rendert? `FlipbookIncompatible`? Frame-Reihenfolge |
| ☐ | U12 | Engine-Clamps | Per Command Bar setzen und zurücklesen: `Rate = 1000`, `Lifetime = NumberRange.new(30)`, `TimeScale = 2`, `Squash` ±5, `Beam.Segments = 5000`, `Width0 = -1`, `FlipbookFramerate = NumberRange.new(60)`, `LightInfluence = 2`; sichtprüfen | gelesene Werte, Sichtbares |
| ☐ | U13 | Doppelte Keypoint-Zeiten | `print(pcall(NumberSequence.new, { NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) }))`, ebenso `ColorSequence`; im Edit Mode und im Playtest | ok/Fehlertext; Stufe sichtbar? |
| ☐ | U14 | Emit-Timing, Qualitäts-Skalierung, Caps | Emitter klonen + parenten + sofort `Emit(100)` vs. einen Frame später; Mobile Low vs. PC Max: Partikel zählen | Wird das sofortige Emit ignoriert? Skaliert Emit mit Qualität? |
| ☐ | U17 | Trails an per Skript bewegten Attachments (Edit Mode) | Vorschau eines Trail-Effekts mit Positions-Spur; FPS-Cap 30/60/144 (Studio-Einstellung) | Zeichnet der Trail? Länge FPS-abhängig? Wirkt Transparency auf alte Segmente? |
| ☐ | U20 | Vorschau-Objekte in Team Create | Zwei Accounts im Team Create; A startet die Vorschau | Sieht B den Vorschau-Ordner (Workspace oder unter CurrentCamera)? |
| ☐ | U26 | HTTP- und Script-Injection-Dialoge | Plugin lokal und als Store-Asset; Bridge aktivieren; Export legt ModuleScripts an | Dialog wann/wie oft; erneut bei `ws://`? |
| ☐ | U31 | `StringValue.Changed` bei Rojo-Live-Updates | `rojo serve`, `.vfx.json` ändern; Plugin-Log von `Changed`; Referenz nach Rojo-Fallback (Instanz ersetzt) | feuert zuverlässig? Referenz noch gültig? |

#### P2 – Feinschliff

| ☐ | ID | Frage (kurz) | So testen | Notieren |
|---|---|---|---|---|
| ☐ | U15 | `VelocityInheritance` bei verankertem Part / CFrame-Animation | Part verankert, `AssemblyLinearVelocity` setzen bzw. per Skript bewegen, Emitter `VelocityInheritance = 1`; bei Attachment-Parent | Partikelbahn mit/ohne Erbe |
| ☐ | U16 | Shape-Geometrie | Nicht-uniforme Parts (z. B. 10×2×4) mit Shape Sphere/Cylinder/Disc/Box; Emitter an Attachment, unter Terrain, an Bone | Form der Spawn-Wolke, Achse |
| ☐ | U18 | Insert-Defaults vs. `Instance.new` | Beam, Trail, Point/Spot/SurfaceLight über den Explorer einfügen und per Skript erzeugen; alle Properties vergleichen | abweichende Defaults |
| ☐ | U19 | Was rendert ViewportFrame + WorldModel im DockWidget? | Testszene je Klasse: ParticleEmitter, Beam, Trail, Fire, Smoke, Sparkles, Explosion, Lichter, Highlight, Decal, Texture, SurfaceAppearance | sichtbar ja/nein je Klasse |
| ☐ | U21 | Sound-Vorschau im Edit Mode | Sound-Klon unter dem Widget `:Play()`, vorverdrahteter AudioPlayer, `SoundService:PlayLocalSound` aus dem Plugin | was ist hörbar |
| ☐ | U22 | Neon/ForceField auf Part + SpecialMesh | Sphere-, Cylinder-, FileMesh-SpecialMesh mit Neon/ForceField in Edit und Play nebeneinander | Optik, Neon-Bug bei Zylindern |
| ☐ | U24 | `rbxtemp://` / `EditableImage` als Textur | Import-Dialog, temporäre ID an `ParticleEmitter.Texture` | sichtbar im Edit Mode? |
| ☐ | U25 | `rbxasset://textures/particles/*` auf Geräten | Testplace mit allen Texturen aus `COMPONENTS_SPEC.md` §16 auf Mobile/Konsole | vorhanden, Aussehen |
| ☐ | U28 | PluginActions/Menüs nach Reload; Widget-ID im Play-DataModel | Reload-Zyklen, Playtest | doppelte IDs, Fehler |
| ☐ | U30 | Große JSON-Texte in TextBox | 50/100/190 KB in die Import-TextBox einfügen | Abschneiden, Dauer |
| ☐ | U32 | `HttpService:JSONEncode` | Command Bar: `local H = game:GetService("HttpService"); print(H:JSONEncode({}), H:JSONEncode({ a = {} }), pcall(H.JSONEncode, H, 0/0), pcall(H.JSONEncode, H, math.huge), H:JSONEncode(2^53 + 1))` | Ausgaben |
| ☐ | U41 | Envelope-Werte nach Sequenzwechsel | `Size`-Envelope groß, mitten in der Lebenszeit neue `Size`-Sequenz setzen | behalten Partikel ihre gewürfelte Abweichung? |

#### P3 – später

| ☐ | ID | Frage (kurz) | So testen | Notieren |
|---|---|---|---|---|
| ☐ | U23 | `SpecialMesh.Scale`-Grenzen; Ball erzwingt Uniform? | `Scale = Vector3.new(1e6, 0, -1)` setzen/zurücklesen; Ball-Part mit Size 2×4×6 | gelesene Werte, Form |
| ☐ | U27 | `SetSetting`-Größenlimit, Ort der Datei | wachsende Payload (1 KB … 10 MB) schreiben/lesen | Grenze, Fehlermeldung |
| ☐ | U29 | `UpdateSourceAsync` und Undo; Drafts-Modus | generiertes Modul aktualisieren, Undo-Liste prüfen (mit/ohne Collaborative Editing) | Undo-Schritt ja/nein |
| ☐ | U33 | Größenlimits `RequestAsync` / `WebStreamClient` | Bridge mit wachsenden Bodies | Grenze |
| ☐ | U34 | Glass-Distortion ab Grafik ≥ 8; `Transparency > 1` | Glass-Part, Qualitätsstufen durchschalten | Distortion ab Stufe; Transparency-Rücklesewert |
| ☐ | U35 | `SceneAnalysisService` live | im veröffentlichten Place `GetTriangleCompositionAsync()` aufrufen, Zeit messen | funktioniert? Dauer |
| ☐ | U36 | Kosten Highlight + ColorCorrection (Impact Frames) auf Mobile | `screenFlash`-Effekt 1–3 Frames auf Gerät, MicroProfiler | Frametime; verschwinden Partikel? |
| ☐ | U37 | Mehrfachbearbeitung von Sequenzen im Properties-Fenster | zwei Emitter selektieren, `Size` ändern | übernommen ja/nein |
| ☐ | U38 | Unreliable-Grenzen realer ASTRA-Nachrichten | `Net.PlayAll(…, { Unreliable = true, … })` mit langen Namen/allen Feldern; Studio-Output auf Überschreitungs-Meldungen; Stats-Netzwerk | Meldungen, Verluste |
| ☐ | U39 | MCP-`execute_luau`-Sicherheitsstufe, Limits | Studio-MCP-Session: `print(pcall(function() return game:GetService("ChangeHistoryService"):TryBeginRecording("x") end))`, große Rückgaben | Rechte, Grenzen |
| ☐ | U40 | Spielerstufen 1–10 ↔ `QualityLevel` 1–21; Studio-Playtest-Stufe | `settings().Rendering.QualityLevel` lesen (Plugin/Command Bar), Gerätetest | Zuordnung |
| ☐ | U42 | `UIDragDetector` in Plugin-Widgets | Prototyp: Keyframe-Drag im DockWidget | funktioniert? Eingabekoordinaten |
| ☐ | U43 | Require-Aliase (`.config.luau`), `ScriptService:ResolveModulePath` | Testmodul mit Alias | unterstützt? |
| ☐ | U44 | Rojo-7.7-Two-Way-Sync | Rojo-Plugin-Option aktivieren, StringValue in Studio ändern | welche Änderungen landen in Dateien? |
| ☐ | U45 | Kosten `MeshPart:ApplyMesh` auf gepoolten Parts | MicroProfiler bei 50 Aufrufen | ms pro Aufruf |
| ☐ | U46 | Berechtigungen `AssetService:CreateMeshPartAsync` | eigene, Gruppen-, Store-Mesh-IDs | Erfolg/Fehler je Besitzer |

---

## Teil C – Ergebnisprotokoll

Eine Zeile pro Prüfpunkt und Durchlauf (neue Durchläufe unten anhängen, alte Zeilen nicht löschen). Ergebnis:
✅ bestanden · ❌ fehlgeschlagen · ⚠️ teilweise/abweichend · n/a noch nicht implementiert.

| Datum | Studio-Version | OS | Tester | Prüfpunkt | Ergebnis | Notizen |
|---|---|---|---|---|---|---|
| | | | | B.0 | | Plugin-Build vom … |
| | | | | B.1 | | passed / failed / skipped |
| | | | | U1 | | Heartbeat …/s, dt …; minimiert …; Script-Tab …; Widget … |
| | | | | U2 | | |
| | | | | U3 | | |
| | | | | U4 | | |
| | | | | U5 | | |
| | | | | U6 | | |
| | | | | M2.1 | | |
| | | | | M2.2 | | |
| | | | | M2.3 | | |
| | | | | M2.4 | | |
| | | | | M2.5 | | |
| | | | | M2.6 | | |
| | | | | M2.7 | | |
| | | | | M2.8 | | |
| | | | | M2.9 | | |
| | | | | M3.1 | | |
| | | | | M3.2 | | |
| | | | | M3.3 | | |
| | | | | M3.4 | | |
| | | | | M3.5 | | |
| | | | | M3.6 | | |
| | | | | M3.7 | | |
| | | | | M3.8 | | |
| | | | | M4.1 | | |
| | | | | M4.2 | | |
| | | | | M4.3 | | |
| | | | | M4.4 | | |
| | | | | M4.5 | | |
| | | | | M4.6 | | |
| | | | | M4.7 | | |
| | | | | M5.1 | | |
| | | | | M5.2 | | |
| | | | | M5.3 | | |
| | | | | M5.4 | | |
| | | | | M6.1 | | |
| | | | | M6.2 | | |
| | | | | M6.3 | | |
| | | | | M6.4 | | |
| | | | | M6.5 | | |
| | | | | M6.6 | | |
| | | | | M6.7 | | |
| | | | | M6.8 | | |
| | | | | U7–U46 | | je ID eine eigene Zeile |

Nach einem Durchlauf:

1. Bestandene Punkte in [`PROGRESS.md`](PROGRESS.md) in der Spalte **S** von „ausstehend“ auf „✅ <Datum>, Studio
   <Version>“ setzen; fehlgeschlagene als „❌ <Datum>“ mit Verweis auf die Notiz.
2. Ergebnisse der U-Punkte in `docs/ROBLOX_API_CONSTRAINTS.md` §26 (Spalte „Stand“) übernehmen, mit Datum und
   Studio-Version; widerlegte Annahmen als Fehler/Aufgabe melden (betroffene Komponente steht in „Blockiert“).
