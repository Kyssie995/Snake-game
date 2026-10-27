# Recherche: Professionelle VFX- und Animations-Tools als UX- und Workflow-Vorbild

Stand: 2026-10-27 · Phase 1 (Research & Architecture) · Autor: Research-Subagent für ASTRA VFX STUDIO
Betrachtet: Unity Visual Effect Graph, Unreal Engine Niagara, Blender Geometry Nodes / Node Editor, Blender Dope Sheet /
Graph Editor / Timeline, Adobe After Effects, Unreal Sequencer. Es geht **nur um Konzepte**. Es wurde kein
Fremdcode, kein proprietäres Asset und kein proprietäres Design übernommen. Alle Beschreibungen sind in eigenen Worten.

> **Label-Legende:** **VERIFIED** = offizielle Dokumentation (hier: der Quelltext der offiziellen Unity-Doku im
> öffentlichen Unity-Repository), Quelltext oder Keymap des Produkts selbst (Blender-Mirror) oder lokaler Roblox-API-Dump
> 0.745 · **REPORTED** = Drittquellen, z. B. der community-gepflegte After-Effects-Scripting-Guide (docsforadobe) ·
> **ASSUMPTION** = eigene Schlussfolgerung **oder Modellwissen, das in dieser Sitzung nicht gegen eine Quelle geprüft
> werden konnte** (immer mit „Modellwissen“ markiert) · **IDEA** = eigene Design-Idee für ASTRA.
> ⚑ = *critical*: Eine ASTRA-Entscheidung hängt daran.

> **Quellenlage – bitte beachten:**
> 1. Das **WebSearch-Budget dieser Sitzung war bereits erschöpft**: Der erste Suchaufruf meldete das Limit von
>    200 Suchen pro Turn, das alle Agenten teilen. Es gab deshalb **keine einzige Websuche**. Suchmaschinen,
>    Reader-Dienste oder Archive wurden bewusst nicht als Umweg genutzt.
> 2. `docs.unity3d.com`, `dev.epicgames.com`, `docs.blender.org` und `helpx.adobe.com` waren per curl **nicht
>    erreichbar** (je ein Versuch, Verbindungsfehler).
> 3. Erreichbar und genutzt wurde **raw.githubusercontent.com**:
>    - **Unity**: der Markdown-Quelltext der offiziellen VFX-Graph-Doku in `Unity-Technologies/Graphics`
>      (`Packages/com.unity.visualeffectgraph/Documentation~/*.md`, Branch `master`; die neueste „What's new“-Seite dort
>      ist 17.1 / Unity 6.1). Dieselben Seiten erscheinen unter `docs.unity3d.com/Packages/com.unity.visualeffectgraph@17.x/manual/<Seite>.html`.
>    - **Blender**: Quelltext-Mirror `blender/blender`, Branch `main` (= **Blender 5.4 alpha**, siehe
>      `BKE_blender_version.h`): Default-Keymap, RNA-Definitionen und Node-Zeichencode. Das Handbuch-Repository
>      (`blender-manual`) hat keinen GitHub-Mirror (404).
>    - **After Effects**: der community-gepflegte *After Effects Scripting Guide* (`docsforadobe/after-effects-scripting-guide`).
>      Er ist kein offizielles Adobe-Dokument, darum **REPORTED**.
> 4. **Unreal Niagara und Sequencer**: Es war **keine** Quelle erreichbar. Die Unreal-Quellen auf GitHub sind privat
>    (404), und die Epic-Doku ist blockiert. Alles zu Niagara und Sequencer ist darum **ASSUMPTION (Modellwissen)**
>    und vor einer Architekturentscheidung gegen `dev.epicgames.com` zu prüfen (siehe Offene Fragen).
> 5. Die Roblox-Fakten stammen aus dem lokalen API-Dump 0.745.0.7451137 und `globalTypes.d.luau` sowie aus den
>    früheren ASTRA-Recherchenotizen in diesem Ordner.

---

## 1. Zusammenfassung

Die Profi-Tools teilen fünf Muster, die sich gut auf ASTRA übertragen lassen. Mehrere davon hat ASTRA im
Architekturentwurf schon angelegt (`docs/ARCHITECTURE.md`):

1. **Zwei Achsen der Logik.** Unity trennt ausdrücklich den vertikalen **Ablauf-Fluss** (Contexts Spawn →
   Initialize → Update → Output, darin Blocks von oben nach unten) vom horizontalen **Daten-Fluss** (Operators,
   die Werte für Block-Ports berechnen). Niagara folgt laut Modellwissen derselben Idee als Modul-Stack mit
   Stage-Gruppen. Für ASTRA heißt das: Die Timeline (Zeit und Ablauf) und der Node-Graph (Logik und Daten) sind zwei
   Sichten auf **ein** Datenmodell. Der Graph wird beim Kompilieren in den Zeitplan entrollt. Das passt zum
   ASTRA-Entwurf (Abschnitt 6).
2. **Typisierte, sichtbar kodierte Ports.** Unity dokumentiert eine feste Farbe pro Typ. Blender kodiert Typen per
   **Farbe** und die Datenstruktur per **Form** (Kreis, Raute, Quadrat, jeweils auch mit Punkt). Feld-Links zeichnet
   Blender gestrichelt und dünner, **ungültige Links rot**. Ausgegraute Sockets zeigen an, dass ein Eingang keine
   Wirkung auf das Ergebnis hat. ⚑ Für den ASTRA-Graph-Editor folgt daraus: Typfarbe plus Pin-Form plus sofortige
   Validierung direkt am Link.
3. **Exponierte Parameter mit Instanz-Overrides.** In Unity gibt es Blackboard-Properties mit dem Flag „Exposed“.
   Sie erscheinen im Inspector jeder Instanz, und eine Checkbox zeigt den Override an und setzt ihn zurück. Dazu kommen
   Property Binder (Szenenwert → Parameter). Niagara kennt laut Modellwissen „User Parameters“. ⚑ ASTRA hat bisher nur
   `palette` als Spezialfall. Ein allgemeines, typisiertes `parameters`-Objekt ist der fehlende Baustein für
   wiederverwendbare Effekte und für Claude-Edits.
4. **Wiederverwendung über Vorlagen, Vererbung und Subgraphen.** Unity hat Templates mit Name, Kategorie,
   Beschreibung, Icon, Thumbnail und Favoriten sowie Subgraphen für System, Block und Operator. Ein
   System-Subgraph wird laut Doku **tief kopiert** und verursacht dadurch Kosten. Niagara bietet laut Modellwissen
   Parent-Emitter-Vererbung und einen Scratch Pad. Blender hat Node Groups und **verlinkte Duplikate** (Alt+D).
   Unity hat „Duplicate with Link“. ASTRA sollte Preset-Vererbung als **Daten-Diff** (`extends` plus Overrides)
   modellieren und beim Kompilieren flach auflösen.
5. **Timeline-Konventionen** aus After Effects, Blender und (laut Modellwissen) Sequencer: Ebenen und Komponenten als
   Balken mit In-/Out-Point, Zeiten relativ zum Ebenenstart, Marker mit Dauer, Kommentar und Labelfarbe, ein
   **Arbeits- bzw. Vorschaubereich** getrennt von der Effektdauer, Interpolation Linear/Bezier/Hold, Ease als
   Speed/Influence, Box-Auswahl, Spaltenauswahl, Snapping und Ansicht-auf-alles bzw. Ansicht-auf-Auswahl.
   Blenders Keymap aus dem Quelltext liefert ein konsistentes, belegtes Shortcut-Set.

**Nicht übertragbar** (⚑): Die gesamte **GPU- und Per-Partikel-Ebene**. Dazu gehören Partikel-Attribute,
GPU-Events („spawne bei Tod oder Kollision eines Partikels“), Custom HLSL und eigene Shader, Vector Fields, SDFs,
Point Caches, Sortier- und Bounds-Kontrolle, Instancing-Batches, Prewarm und exaktes Rückwärts-Scrubbing nativer
Partikel. Roblox' `ParticleEmitter` hat **keinen Seed**, keine Per-Partikel-Events, und `FastForward` ist
`RobloxScriptSecurity`. ASTRA kann nur auf der **Emitter- und Instanz-Ebene** autorisieren und muss echte
Per-Element-Logik über eigene prozedurale Komponenten lösen (Parts und Beams als reine Funktionen von Zeit und Seed;
im Entwurf schon vorhanden). Das UI muss diese Grenze sichtbar machen, statt Profi-Features vorzutäuschen.

---

## 2. Befunde

### 2.1 Unity Visual Effect Graph – Evidenz: VERIFIED (offizielle Doku-Quelltexte)

Basis-URL der gelesenen Dateien:
`https://raw.githubusercontent.com/Unity-Technologies/Graphics/master/Packages/com.unity.visualeffectgraph/Documentation~/`
(im Folgenden nur der Dateiname)

| # | Befund | Label | Quelle |
|---|---|---|---|
| U1 | Zwei Workflows: Der **Processing-Workflow (vertikal)** verbindet Contexts über Flow-Ports oben und unten. Der **Property-Workflow (horizontal)** verbindet Operator-Netzwerke mit den Property-Ports der Blocks (links Eingang, rechts Ausgang). ⚑ | VERIFIED | GraphLogicAndPhilosophy.md |
| U2 | Ein **System** ist eine Folge von Contexts und wird im Graph als gestrichelter Rahmen gezeichnet. Typen: Spawn-System (ein Spawn-Context), Particle-System (Initialize → Update → Output), Mesh-Output-System. Ein Spawn-System kann andere Spawn-Systeme an- und abschalten („Master-Spawner“). | VERIFIED | Systems.md |
| U3 | Die vier Standard-Contexts: **Spawn** (pro Frame: wie viele Partikel), **Initialize** (bei der Geburt jedes Partikels), **Update** (pro Frame für alle Partikel, z. B. Kräfte und Kollision), **Output** (pro Frame: Form, Transformation vor dem Rendern). Ein Initialize-Context kann direkt an einen Output gehen, ohne Simulation. | VERIFIED | GraphLogicAndPhilosophy.md; Contexts.md |
| U4 | **Flow-Kompatibilitätsregeln** sind als Tabelle dokumentiert: Datentypen SpawnEvent, GPUSpawnEvent und Particle. Nur **ein** Initialize darf an **ein** Update. Initialize nimmt entweder SpawnEvents oder GPU-SpawnEvents, beides zusammen ist ausgeschlossen. Der Static Mesh Output ist eigenständig. ⚑ (Vorbild für die ASTRA-Graph-Validierung) | VERIFIED | Contexts.md |
| U5 | **Blocks** sind stapelbare Knoten in einem Context. Sie laufen **von oben nach unten**, lassen sich per Drag umsortieren oder in kompatible Contexts verschieben. Eine Checkbox deaktiviert einen Block. Ein Block, der statisch inaktiv ist, wird ausgegraut und **beim Kompilieren entfernt** (null Laufzeitkosten). Jeder Block hat zusätzlich einen **Activation-Port** (bool), um ihn per Logik bedingt zu aktivieren. | VERIFIED | Blocks.md |
| U6 | Es gibt **Settings** und **Properties**. Settings haben keinen Port, sind nicht verbindbar und erfordern Neukompilieren. Properties sind editierbar **und** verbindbar. Settings können die Form eines Knotens ändern: Composition „Blend“ benennt z. B. „Set Velocity“ in „Blend Velocity“ um und fügt einen Blend-Port hinzu. | VERIFIED | GraphLogicAndPhilosophy.md; Blocks.md |
| U7 | **Composition-Modi** für Attribut-Blocks: Set, Add, Multiply, Blend (mit Faktor 0–1). **Sample-Modi** für Curve- und Gradient-Blocks: OverLife (Alter/Lebenszeit), BySpeed (Speed Range), Random, RandomConstantPerParticle, Custom (eigener Sample-Eingang). ⚑ | VERIFIED | Block-SetAttributeFromCurve.md |
| U8 | Operator-Varianten: **Uniform** (ein variabler Typ, die Ausgabe folgt dem Eingang), **Unified** (mehrere variable Typen mit Constraints), **Cascaded** (variable Eingangsanzahl; ein grauer letzter Eingang erzeugt beim Verbinden einen neuen Eingang). Ein Konfigurationsmodus erlaubt das Umbenennen, Umtypisieren und Umsortieren der Eingänge. | VERIFIED | Operators.md |
| U9 | **Typfarben** sind dokumentiert: float `#84e4e6`, int `#9480e6`, uint `#6e55db`, bool `#d9b3ff`, Vector2 `#9aef92`, Vector3 `#f6ff9a`, Vector4 und Color `#fbcbf4`, AnimationCurve und Gradient `#FFAA6B`, Texturen `#FF8B8B`, Mesh `#7AA3EA`, „spaceable“ Position/Vector/Direction `#FCD76E`. (Nur Referenz, ASTRA wählt eigene Farben.) | VERIFIED | VisualEffectGraphTypeReference.md |
| U10 | **Casts**: HLSL-Regeln; bool ist nicht castbar. Ein Skalar wird zum Vektor (alle Komponenten), ein Vektor wird auf seine ersten N Komponenten gekürzt. Verbundtypen (z. B. Sphere = Position + Radius) lassen sich aufklappen, Komponenten sind einzeln verbindbar. **Spaceable Properties** tragen Local/World/None mit und werden automatisch in den Simulationsraum umgerechnet. | VERIFIED | Properties.md; Blocks.md |
| U11 | **Blackboard**: Graph-weite Properties und Attribute (Shift+1). Properties mit **Exposed** erscheinen im Inspector der Komponente. Ein **grüner Punkt** am Property-Knoten zeigt „exposed“. Hover im Blackboard hebt alle Verwendungen im Graph hervor und umgekehrt. Es gibt „Select Unused Properties“, „Convert to Property/Inline“ (Shift+X) und Kategorien. | VERIFIED | Properties.md; Blackboard.md; Attributes.md |
| U12 | **Instanz-Override**: Ändert man ein exponiertes Property im Inspector, wird automatisch eine Checkbox gesetzt. Entfernt man das Häkchen, kehrt der Wert zum Blackboard-Default zurück. Bei einem Asset-Wechsel bleiben Overrides erhalten, wenn Name **und** Typ übereinstimmen. ⚑ | VERIFIED | Properties.md; ComponentAPI.md |
| U13 | **Events** sind nur Namen (Strings). Die Default-Events sind `OnPlay` und `OnStop`. Sie werden implizit an Start und Stop eines Spawn-Contexts gebunden, solange dort nichts verbunden ist. Events können **Attribut-Payloads** mitführen (z. B. position, color), die über Spawn bis Initialize „durchreisen“ („Get Source Attribute“, „Inherit Attribute“). Pro Asset und pro Instanz ist ein „Initial Event Name“ einstellbar (leer = nichts startet automatisch). | VERIFIED | Events.md; VisualEffectComponent.md; VisualEffectGraphAsset.md |
| U14 | **GPU Events**: Partikel spawnen Partikel in anderen Systemen. Trigger Event Block mit den Modi Always, OverTime, OverDistance, OnDie, OnCollide. Der GPU-Event-Context nimmt keine Blocks auf, und das Kind liest die Attribute des Elternpartikels. Trigger-Blocks laufen immer am Ende des Update-Contexts. | VERIFIED | Events.md; Block-Trigger-Event.md; Context-GPUEvent.md |
| U15 | **Spawn-Context-Zustandsmaschine**: Loop Duration (Infinite/Constant/Random), Loop Count (Infinite/Constant/Random), Delay Before/After (None/Constant/Random). Zustände: Finished, DelayingBeforeLoop, Looping, DelayingAfterLoop. Wann welcher Wert ausgewertet wird, ist festgelegt (Count bei Start, Duration bei jedem Loop-Start, Delays bei jedem Delay-Start). ⚑ | VERIFIED | Contexts.md; Context-Spawn.md |
| U16 | **Burst-Blocks**: Single oder Periodic, Count und Delay jeweils konstant oder zufällig in [min, max]. Ein Burst erhöht `spawnCount` sofort. | VERIFIED | Block-Burst.md |
| U17 | **Subgraphen**: System-Subgraph (ganze Systeme als Context mit exponierten Properties und Events), Block-Subgraph (Blocks und Operatoren als **ein** Block; „Suitable Contexts“ bestimmt, wo er erlaubt ist), Operator-Subgraph (Ein- und Ausgänge über das Blackboard; Ausgänge in der „Output Category“). „Convert to Subgraph“ ersetzt die Auswahl durch einen Subgraph-Knoten. Die Menükategorie ist mit `/` hierarchisch, `#n` sortiert. **System-Subgraphen werden tief kopiert**, kosten also Import-Zeit und Speicher. | VERIFIED | Subgraph.md |
| U18 | **Groups und Sticky Notes**: Gruppen haben einen Titel und lassen sich gemeinsam verschieben (Shift+G). Sticky Notes haben Titel und Text, die Farben Gelb (Default), Blau und Rot, vier Schriftgrößen und „Fit to text“ (Shift+N). | VERIFIED | GraphLogicAndPhilosophy.md; StickyNotes.md; Shortcuts.md |
| U19 | **Knotensuche**: Leertaste, Rechtsklick oder das Ziehen eines Links ins Leere öffnet ein **kontextsensitives** Menü, das nur kompatible Elemente zeigt. Seit 17.x hat es eine hierarchische Baumansicht, ein Seitenpanel, Filter, **Favoriten** und **Ordnerfarben**. „Insert Node on Link“ ist Shift+R. ⚑ | VERIFIED | VisualEffectGraphWindow.md; whats-new-17.md; Shortcuts.md |
| U20 | **Navigation**: Pan per Mittelklick-Drag oder Alt+Drag, Zoom per Mausrad. Rechteck-Auswahl erfasst alle berührten Elemente, Ctrl ergänzt bzw. entfernt. **Shift+Drag** zieht einen Lasso-Pfad. F rahmt die Auswahl ein, ohne Auswahl den ganzen Graph. | VERIFIED | VisualEffectGraphWindow.md |
| U21 | **Shortcuts** (Auszug): A = alles einrahmen, F = Auswahl einrahmen, O = Ursprung, `[` und `]` = vorheriger/nächster Knoten, Shift+D = alles abwählen, Shift+C = kompilieren, Shift+A = Auto-Compile, `/` = VFX neu starten, Ctrl+D = duplizieren, Alt+Shift+D = **duplizieren mit Links**, Shift+P = Auswahl einklappen, Shift+Backspace = unverbundene Operatoren löschen, Shift+1/3/4/5 = Panels umschalten, F1 = Doku. Alt+Buchstabe fügt häufige Operatoren direkt ein (Alt+A Add, Alt+M Multiply, Alt+L Lerp, Alt+R Remap …). Alle Shortcuts sind im Shortcut-Manager umbelegbar. | VERIFIED | Shortcuts.md; VisualEffectGraphWindow.md |
| U22 | **Toolbar**: Compile, Auto Compile, **Auto Reinit** (Neustart der angehängten Instanz bei Änderungen an Spawn/Init) mit Prewarm-Zeit, Runtime Mode. Das Graph-Fenster wird an eine **Szeneninstanz „angehängt“** (Auto Attach/Lock). Erst dann wirken Control-Panel und Debug-Panels. | VERIFIED | VisualEffectGraphWindow.md; GettingStarted.md |
| U23 | **Play Controls** im Scene View: Stop (zurücksetzen und pausieren), Play/Pause, **Step** (ein Frame), Restart, **Rate** in Prozent, Show Bounds, **Event Tester**, Send Play/Stop Event, Gizmos. | VERIFIED | VisualEffectComponent.md |
| U24 | **Seeds**: Jede Instanz hat einen Random Seed mit „Reseed“-Knopf und „Reseed On Play“. Der Random-Number-Operator hat die Scopes Per Particle, Per VFX Component und Per Particle Strip und ist optional **konstant** über einen eigenen Seed. Mit gleichem globalen Seed verhält sich der Effekt laut Doku **deterministisch**. ⚑ | VERIFIED | VisualEffectComponent.md; ComponentAPI.md; Operator-RandomNumber.md |
| U25 | **Timeline-Integration**: Ein Control-Track enthält Control-Clips. Clip-Optionen: **Scrubbing** (vorwärts und rückwärts, dafür wird die Simulation neu berechnet), Reinit-Modi, **Start Seed** pro Clip, Prewarm (Total Time / Step Count / Delta Time). **Clip Events** (Enter/Exit) und **Single Events** werden mit einem **Time Space** verankert: After Clip Start, Before Clip End, Percentage oder Absolute. Single Events haben eine Editor-Farbe. Grenzen: Max Scrub Time; Rückwärtsspielen erzeugt GPU-Spitzen (es nutzt `Simulate`). ⚑ | VERIFIED | Timeline.md; VisualEffectProjectSettings.md |
| U26 | **Profiling- und Debug-Panels**: CPU- und GPU-Zeiten pro Graph, System und Context, Texturspeicher, **Alive/Capacity** pro System, Zustände Playing/Paused, Awake/Asleep und Visible/Culled. Eine **Heatmap-Schwelle** (ms) färbt teure Teile rot. Die Doku warnt selbst: nur Richtwerte, auf Zielgeräten profilieren. | VERIFIED | performance-debug-panel.md |
| U27 | **Bounds**: Manual, **Recorded** (Aufnahme während der Wiedergabe, dann „Apply Bounds“) oder Automatic (teuer). Dazu Bounds Padding. Falsche Bounds führen zu Verschwendung (zu groß) oder zu falschem Culling (zu klein). | VERIFIED | visual-effect-bounds.md |
| U28 | **Asset-Ebene**: Fixed Delta Time, Exact Fixed Time, Ignore Time Scale, Culling Flags, Instancing-Modus und Batch-Kapazität, Prewarm, **Output Render Order** (umsortierbare Liste der Outputs), Template-Metadaten (Name, Kategorie, Beschreibung, Icon, Thumbnail). | VERIFIED | VisualEffectGraphAsset.md; Instancing.md |
| U29 | **Template-Fenster**: Liste, Detailansicht mit Bild und Beschreibung, Suche, Kategorie-Filter, Sortierung (Name, Standard, Änderungsdatum, **zuletzt benutzt**, **Favoriten**). „Insert template“ fügt eine Vorlage in den offenen Graph ein, an der Rechtsklick-Position. | VERIFIED | Templates-window.md |
| U30 | **Property und Event Binder** (MonoBehaviours): Sie verbinden Szenenwerte mit exponierten Properties (Transform, Position, Velocity, Light, Raycast, Audio-Spektrum, UI-Slider …) bzw. Szenenereignisse (Maus, Trigger, Kollision, Sichtbarkeit) mit Events samt Payload. Das Muster ist eine Prüffunktion („gültig?“) plus eine Update-Funktion pro Frame. | VERIFIED | PropertyBinders.md; EventBinders.md |

### 2.2 Unreal Engine Niagara – Evidenz: keine Quelle erreichbar → ASSUMPTION (Modellwissen)

Alle Punkte stammen aus dem Modellwissen und sind **nicht** gegen `dev.epicgames.com` geprüft. Sie dienen nur als
Konzept-Inspiration. Konkrete Zahlen, Menünamen oder Versionsangaben bitte nicht übernehmen, bevor sie verifiziert sind.

| # | Befund (Konzept) | Label | Quelle |
|---|---|---|---|
| N1 | Hierarchie: Ein **System** (Asset, in der Welt per Niagara Component) enthält **Emitter**, Emitter enthalten **Module**. Diese stehen in einem vertikalen **Stack**, gruppiert nach Stages: System Spawn/Update, Emitter Spawn/Update, Particle Spawn/Update, Event Handler, (GPU-)Simulation Stages und die **Render**-Sektion mit Renderern wie Sprite, Mesh, Ribbon, Light und Component. Module laufen innerhalb einer Stage von oben nach unten. ⚑ | ASSUMPTION (Modellwissen) | – |
| N2 | Parameter haben **Namespaces** (z. B. `Engine.`, `System.`, `Emitter.`, `Particles.`, `User.`). Daraus ergibt sich, wer einen Wert schreiben oder lesen darf und wie lange er lebt. | ASSUMPTION (Modellwissen) | – |
| N3 | **User Parameters**: Sie sind auf der Komponente exponiert, von Gameplay-Code und Sequencer setzbar und an Modul-Eingänge bindbar. Modul-Eingänge sind außerdem über „Dynamic Inputs“ treibbar (Kurven, Zufallsbereiche, andere Parameter, Ausdrücke). ⚑ | ASSUMPTION (Modellwissen) | – |
| N4 | **Emitter-Vererbung**: Ein Emitter kann von einem Parent-Emitter erben. Änderungen am Parent fließen nach. Geerbte Module lassen sich im Kind deaktivieren, aber nicht löschen. Geänderte Werte bekommen eine „auf Parent zurücksetzen“-Möglichkeit. | ASSUMPTION (Modellwissen) | – |
| N5 | **Scratch Pad**: Lokale Module und Dynamic Inputs werden direkt im System als Node-Graph gebaut und bei Bedarf später in ein wiederverwendbares Asset umgewandelt. | ASSUMPTION (Modellwissen) | – |
| N6 | **Effect Types / Scalability**: Ein Effect-Type-Asset bündelt Scalability-Regeln pro Qualitätsstufe und Plattform, etwa Distanz-Culling, Instanzlimits, Sichtbarkeits-Culling, Significance (wichtigste Instanzen zuerst) und eine globale **Budget-Skalierung** nach gemessener Laufzeit. Emitter können zusätzlich Spawn-Mengen pro Stufe skalieren. ⚑ | ASSUMPTION (Modellwissen) | – |
| N7 | **Niagara Debugger**: ein Werkzeug mit HUD-Overlay (aktive Systeme, Partikelanzahlen, Zustände) und einem „FX Outliner“ für Snapshots und Performance. Dazu Debug-Zeichnen in der Szene. | ASSUMPTION (Modellwissen) | – |
| N8 | **Determinismus und Warmup**: Emitter haben eine Determinismus-Option mit festem Random Seed. Systeme haben Warmup (Vorsimulation) und feste Bounds. Sim-Target ist CPU oder GPU pro Emitter. | ASSUMPTION (Modellwissen) | – |
| N9 | **Sequencer-Integration**: Ein Niagara-Komponenten-Track hat einen Life-Cycle-Track (Aktivieren/Deaktivieren und Alter an die Sequencer-Zeit koppeln, damit Scrubbing möglich ist) sowie Parameter-Tracks für User Parameters. ⚑ | ASSUMPTION (Modellwissen) | – |
| N10 | **Emitter-Lebenszyklus**: Loop-Verhalten (einmal, mehrfach, endlos), Loop-Dauer und Loop-Verzögerung, ein „Inactive Response“ (Partikel sofort weg vs. ausklingen lassen). | ASSUMPTION (Modellwissen) | – |

### 2.3 Blender Geometry Nodes und Node Editor – Evidenz: VERIFIED (Quelltext und Keymap, Blender main = 5.4 alpha)

Basis: `https://raw.githubusercontent.com/blender/blender/main/` + Pfad. Die Bedeutung der Formen (Kreis = Einzelwert,
Raute = Feld) steht im Blender-Handbuch, das hier nicht erreichbar war. Die Zuordnung ist daher teils ASSUMPTION.

| # | Befund | Label | Quelle |
|---|---|---|---|
| B1 | **Socket-Formen** (Enum `display_shape`): Circle, Square, Diamond, je **mit innerem Punkt**, außerdem Line, Volume Grid und List. Default ist Circle. | VERIFIED | source/blender/makesrna/intern/rna_node_socket.cc |
| B2 | **Struktur-Typen** von Sockets: Auto („automatisch aus der Verwendung erkennen“), Dynamic („kann mit verschiedenen Strukturen arbeiten“), Field, Grid, List, Single („erwartet einen Einzelwert“). Damit ist neben dem *Datentyp* auch die *Datenstruktur* Teil der Typprüfung. ⚑ | VERIFIED | source/blender/makesrna/intern/rna_node_tree_interface.cc |
| B3 | Zuordnung der Formen zur Bedeutung: Kreis = Einzelwert, Raute = Feld, Raute mit Punkt = „könnte ein Feld sein, ist aber gerade ein Einzelwert“. | ASSUMPTION (Modellwissen, Handbuch nicht erreichbar) | – |
| B4 | **Socket-Farben pro Datentyp** sind fest im Code hinterlegt. Grob: float grau, vector blau-violett, color gelb, shader grün, boolean hellrosa, int dunkelgrün, string hellblau, object orange, geometry türkisgrün, rotation violett, matrix magenta, menu dunkelgrau, int-vector graublau (Blender 5.x). | VERIFIED | source/blender/editors/space_node/drawnode.cc (`std_node_socket_colors`) |
| B5 | **Link-Darstellung**: Im Geometry-Nodes-Editor werden **Feld-Links gestrichelt** gezeichnet und mit 70 % Breite. **Ungültige Links** bekommen die Theme-Farbe „Red Alert“, **stummgeschaltete Links** ebenfalls rot, mit eigener Muted-Darstellung. Zieht man einen Knoten über einen Link, wird der Ziel-Link als Einfüge-Ziel hervorgehoben. Ein optionales Overlay „Wire Colors“ färbt Links nach Socket-Typ. Links zwischen zwei Reroutes zeigen eine **Richtungsmarkierung**. ⚑ | VERIFIED | drawnode.cc (`node_draw_link`, `node_link_is_field_link`) |
| B6 | **Validitäts-Zustände** in der API: `NodeLink.is_valid` („Link is valid“), `NodeLink.is_muted`, `NodeSocket.is_inactive` (ausgegraut, weil **ohne Wirkung auf die Ausgabe**), `is_unavailable`, `is_multi_input` (mehrere **geordnete** Eingangslinks), `hide_value`. Knoten haben `mute`, `hide` (Collapse), Color Tags nach Kategorie und **Warning Propagation** (welche Meldungen zur Elterngruppe hochgereicht werden). ⚑ | VERIFIED | rna_nodetree.cc; rna_node_socket.cc |
| B7 | **Mute-Semantik**: „Delete with Reconnect“ entfernt Knoten und verbindet so neu, „als wäre die Löschung gemutet“. Ein gemuteter Knoten reicht also seine Eingänge an die Ausgänge durch (Bypass). | VERIFIED (Wortlaut der Operator-Beschreibung) | source/blender/editors/space_node/node_edit.cc |
| B8 | **Frames**: „Join Nodes in Frame“ hängt die Auswahl an einen neuen gemeinsamen Frame. „Join in Named Frame“ (Taste **F** in 5.4) macht dasselbe und öffnet sofort ein Namensfeld. Ctrl+P hängt an einen Frame, Alt+P löst. „Insert Offset“ schiebt Nachbarknoten beim Einfügen automatisch beiseite. | VERIFIED | node_relationships.cc; node_ops.cc; blender_default.py |
| B9 | **Node-Editor-Keymap 5.4** (Auszug): Shift+A Add-Menü, Shift+S Swap-Menü, **J** Make Links (Shift+J ersetzend), Ctrl+J Join Nodes (verschmilzt Group-Input-Knoten), **M** Mute, H Collapse, Ctrl+H unbenutzte Sockets verstecken, Shift+H Preview, Ctrl+G Gruppe bilden, Ctrl+Alt+G auflösen, Tab Gruppe betreten/verlassen, Shift+D duplizieren, **Alt+D verlinkt duplizieren**, Ctrl+F Knoten suchen, X/Entf löschen, Ctrl+X löschen und neu verbinden, L bzw. Shift+L verbundene Knoten auswählen, Home alles zeigen, Numpad-Punkt Auswahl zeigen, B Box-Auswahl, C Kreis-Auswahl, Ctrl+Alt+Drag Lasso, F2/Doppelklick umbenennen. | VERIFIED | scripts/presets/keyconfig/keymap_data/blender_default.py |
| B10 | **Link-Gesten**: Ctrl+Rechtsdrag **schneidet** Links, Shift+Rechtsdrag fügt einen **Reroute** auf gekreuzten Links ein, Ctrl+Alt+Rechtsdrag **mutet** Links (im Legacy-Keymap mit linker Maustaste). Ctrl+Linksdrag von einem verbundenen Eingang **löst** den Link ab und nimmt ihn mit. Ctrl+Shift+Klick verbindet mit dem Viewer bzw. Ausgang. | VERIFIED | blender_default.py |
| B11 | **Zonen** (Simulation, Repeat, For-Each-Element, Closure) sind eigene, farbig hinterlegte Bereiche im Graph (Theme-Farben). Schleifen und Zustände werden damit als **begrenzte Region** dargestellt, nicht als freie Rückkante. | VERIFIED (Existenz und Farben im Theme) / ASSUMPTION (Deutung) | release/datafiles/userdef/userdef_default_theme.c |
| B12 | **Node-Header-Farben nach Kategorie** (Theme `nodeclass_*`: output, filter, vector, texture, shader, script, geometry, attribute …). Die Kategorie ist am Header sofort erkennbar. | VERIFIED | userdef_default_theme.c |

### 2.4 Blender Dope Sheet, Graph Editor und Timeline – Evidenz: VERIFIED (Default-Keymap 5.4 alpha)

| # | Befund | Label | Quelle |
|---|---|---|---|
| D1 | **Wiedergabe**: Leertaste Play, Ctrl+Shift+Leertaste rückwärts, **Esc bricht ab** (Wiedergabe-Abbruch), Links/Rechts ein Frame, Shift+Links/Rechts zu Anfang/Ende, **Hoch/Runter zum nächsten/vorigen Keyframe**, Alt+Mausrad ein Frame, Ctrl+Links/Rechts Zeitsprung. ⚑ | VERIFIED | blender_default.py (`km_frames`) |
| D2 | **Bereiche**: P setzt den **Preview-Range** (Arbeitsbereich), Alt+P löscht ihn, Ctrl+Alt+P setzt ihn auf die ausgewählten Keys. Ctrl+Pos1/Ende setzen Start bzw. Ende. Ctrl+T schaltet die Anzeige **Sekunden/Frames** um (`show_seconds`). | VERIFIED | blender_default.py (`km_animation`, `km_dopesheet`, `km_graph_editor`) |
| D3 | **Auswahl im Dope Sheet und Graph Editor**: Klick, Shift-Klick (ergänzen), **Drag = Box-Auswahl** (Shift ergänzt, Ctrl entfernt), B Box, C Kreis, Ctrl-Drag Lasso, **K Spaltenauswahl** (alle Keys auf demselben Frame; Varianten mit Ctrl/Shift/Alt), `[` bzw. `]` alles links/rechts vom Playhead, L verknüpfte Keys, Ctrl+Numpad+/− Auswahl erweitern/verkleinern. ⚑ | VERIFIED | blender_default.py (`km_dopesheet`, `km_graph_editor`) |
| D4 | **Keyframe-Bearbeitung**: G verschieben, S skalieren (zeitlich um den Playhead), E Extend, Shift+D duplizieren, Ctrl+C/Ctrl+V kopieren und einfügen (Ctrl+Shift+V gespiegelt), I Key einfügen, **T Interpolationstyp**, **V Handle-Typ**, **Ctrl+E Easing-Typ**, Shift+E Extrapolation, **R Keyframe-Typ** (Dope Sheet), **Shift+S Snap-Menü** (Pie), Ctrl+M spiegeln, Shift+Alt+O Keys backen, Alt+O glätten (Graph Editor), X/Entf löschen. | VERIFIED | blender_default.py |
| D5 | **Ansicht**: Pos1 alles, Numpad-Punkt Auswahl, Numpad-0 aktuellen Frame zentrieren, Akzent-Taste View-Pie, `/` Local View (Graph Editor: nur ausgewählte Kurven). Ctrl+Klick fügt im Graph Editor einen Key an der Mausposition ein. | VERIFIED | blender_default.py |
| D6 | **Marker**: M fügt hinzu, G verschiebt, Shift+D dupliziert, X/Entf löscht, B oder Drag für Box-Auswahl, `[` und `]` links/rechts, Ctrl+B bindet an eine Kamera. Kanäle: Doppelklick benennt um, Ctrl+F filtert, Shift+W schaltet Kanal-Settings um. | VERIFIED | blender_default.py (`km_markers`, `km_animation_channels`) |
| D7 | **NLA** (Clip-Ebene über Actions): Tab betritt den Tweak-Modus eines Strips, um dessen Keys zu bearbeiten. Shift+A fügt Tracks hinzu. Konzept: Animation als wiederverwendbarer Clip, der auf Spuren verschoben, gestreckt und überlagert wird. | VERIFIED (Keymap) / ASSUMPTION (Konzeptdeutung) | blender_default.py (`km_nla_*`) |

### 2.5 Adobe After Effects – Evidenz: MIXED (Scripting Guide = REPORTED; UI-Details = ASSUMPTION)

Basis: `https://raw.githubusercontent.com/docsforadobe/after-effects-scripting-guide/master/docs/` + Pfad. Das ist
eine Community-Ausgabe des Adobe Scripting Guides (Site: ae-scripting.docsforadobe.dev).

| # | Befund | Label | Quelle |
|---|---|---|---|
| A1 | **Keyframe-Interpolation** pro Key getrennt für **In und Out**: `LINEAR`, `BEZIER`, `HOLD`. Zusätzlich die Flags temporal **Continuous** und **Auto-Bezier**. Beide wirken nur, wenn In und Out auf BEZIER stehen. ⚑ | REPORTED | property/property.md (`setInterpolationTypeAtKey`, `keyTemporalContinuous`, `keyTemporalAutoBezier`) |
| A2 | **Temporal Ease** ist ein Paar aus **Speed** (Einheit abhängig vom Property-Typ) und **Influence** (0,1–100 %), getrennt für In und Out, **pro Dimension** bei 2D/3D-Werten (1–3 Objekte). ⚑ | REPORTED | other/keyframeease.md; property/property.md (`setTemporalEaseAtKey`) |
| A3 | **Roving Keyframes**: Bei räumlichen Properties dürfen Keys „wandern“, damit die Geschwindigkeit über mehrere Keys gleichmäßig wird. Erster und letzter Key können nicht roven. | REPORTED | property/property.md (`setRovingAtKey`) |
| A4 | **Keyframe-Labels** in 17 Farben (0 = keine, 1–16 = Presets) gibt es seit AE 22.6. Dieselbe Label-Logik gilt für Layer und Marker. | REPORTED | property/property.md (`setLabelAtKey`); layer/layer.md; other/markervalue.md |
| A5 | **Layer-Zeitmodell**: `inPoint`, `outPoint` und `startTime` stehen in Kompositionszeit (Sekunden). `stretch` in Prozent (100 = keine Dehnung; negativ = rückwärts). Schalter: `shy` (im Timeline-Panel ausblendbar via „Hide Shy Layers“), `solo`, `locked`, `enabled`. `parent` für Hierarchie. Time Remapping pro Layer. ⚑ | REPORTED | layer/layer.md; layer/avlayer.md; item/compitem.md |
| A6 | **Marker** haben comment (sichtbar in der Timeline), **duration** (als Balken gezeichnet), label, chapter, url, cue points und „protected region“ (Komposition). Es gibt Layer- und Kompositionsmarker. ⚑ | REPORTED | other/markervalue.md |
| A7 | **Work Area**: `workAreaStart` und `workAreaDuration` je Komposition, getrennt von deren Dauer. Vorschau und Render beziehen sich darauf. | REPORTED | item/compitem.md |
| A8 | **Precomps/Verschachtelung**: Eine Komposition kann als Layer in einer anderen liegen (`AVLayer.source` = CompItem). Optionen „Preserve nested frame rate/resolution“, `collapseTransformation`. Konzept: Teil-Animationen kapseln und als eine Einheit timen. | REPORTED (API) / ASSUMPTION (Workflow-Deutung) | layer/avlayer.md; item/compitem.md |
| A9 | **Graph Editor** mit zwei Modi: **Value Graph** (Wert über Zeit) und **Speed Graph** (Änderungsrate über Zeit). Ease wird im Speed Graph über Influence-Griffe geformt. **Easy Ease** (F9), Easy Ease In (Shift+F9), Easy Ease Out (Ctrl+Shift+F9). Key-Symbole zeigen die Interpolation (Raute linear, Sanduhr-Form Ease, Quadrat Hold, Kreis Auto-Bezier). | ASSUMPTION (Modellwissen) | – |
| A10 | **Timeline-Shortcuts**: J/K vorheriger/nächster Key oder Marker, U zeigt animierte Properties (UU geänderte), B/N setzen Anfang/Ende der Work Area, Ctrl+Shift+C precompose, Alt+[ bzw. Alt+] trimmen In/Out, Numpad-* setzt Marker, Shift beim Ziehen aktiviert Snapping. | ASSUMPTION (Modellwissen) | – |

### 2.6 Unreal Sequencer – Evidenz: keine Quelle erreichbar → ASSUMPTION (Modellwissen)

| # | Befund (Konzept) | Label | Quelle |
|---|---|---|---|
| S1 | Links ein **Outliner**-Baum aus Bindings (Objekte) mit Unter-Tracks (Transform, Properties, Events, Audio, Unter-Sequenzen). Rechts die Track-Lanes mit **Sections** (Clips mit In/Out und Ease In/Out an den Rändern) und Keyframes. Zusätzlich ein separates Curve-Editor-Fenster für die Kurven der ausgewählten Kanäle. | ASSUMPTION (Modellwissen) | – |
| S2 | **Playback-Range** (grüne und rote Begrenzer) und **Selection-Range** sind getrennte Zeitbereiche. Marker gibt es auf Sequenzebene. Snapping auf Frames, Keys und Sektionsgrenzen ist umschaltbar. Die Zeitanzeige wechselt zwischen Frames, Sekunden und Timecode. | ASSUMPTION (Modellwissen) | – |
| S3 | Key-Interpolation: Cubic (Auto, User, Break), Linear, Constant. Event-Tracks lösen Gameplay-Events zu Zeitpunkten aus („Trigger“) oder über Bereiche („Repeater“). | ASSUMPTION (Modellwissen) | – |

### 2.7 Roblox-Abgleich: Was trägt die Engine? – Evidenz: VERIFIED (API-Dump 0.745 / globalTypes)

| # | Befund | Label | Quelle |
|---|---|---|---|
| R1 | `ParticleEmitter` hat **keinen Seed**. Die Members mit „eed“ im Namen sind nur `Speed` und `RotSpeed`. Es gibt keine Per-Partikel-Events und keinen Zugriff auf Partikelzustände. Methoden: `Emit`, `Clear`, `FastForward`, wobei **FastForward `RobloxScriptSecurity`** ist. ⚑ | VERIFIED | /root/tools/ref/API-Dump.json; frühere Notiz api-particles-beams-trails.md |
| R2 | Ausrichtungen nativer Partikel: `FacingCamera`, `FacingCameraWorldUp`, `VelocityParallel`, `VelocityPerpendicular`. Formen: Box, Sphere, Cylinder, Disc. Flipbook: Layouts None/2×2/4×4/8×8/Custom und Modi Loop/OneShot/PingPong/Random. **Keine Mesh-Partikel, keine eigenen Shader**: Das Aussehen steuern nur Textur, `LightEmission`, `LightInfluence`, `Brightness` und `ZOffset`. | VERIFIED | API-Dump (Enums ParticleOrientation, ParticleEmitterShape, ParticleFlipbookLayout, ParticleFlipbookMode) |
| R3 | `ZOffset` gibt es bei `ParticleEmitter` und `Beam`, **nicht** bei `Trail`. Das ist das einzige, grobe Mittel für eine „Render Order“. | VERIFIED | API-Dump |
| R4 | Qualität: `UserGameSettings.SavedQualityLevel` (Enum `SavedQualitySetting`: Automatic, 1–10) ist für Skripte lesbar. `GraphicsQualityLevel` ist `RobloxScriptSecurity`. ⚑ | VERIFIED | API-Dump |
| R5 | `Random.new(seed?)` mit `NextNumber`, `NextInteger`, `NextUnitVector`, `Shuffle` und `Clone`. Damit sind **eigene** prozedurale Komponenten deterministisch, native Partikel nicht. | VERIFIED | /root/tools/ref/globalTypes.d.luau |
| R6 | Plugins können `PluginAction`s **kein Default-Shortcut** geben. Der Nutzer belegt sie selbst unter „Customize Shortcuts“. Widget-lokale Tasten kommen nur über einen fokussierten Input-Catcher-Frame (`GuiObject.InputBegan`). Studio-eigene Shortcuts lassen sich nicht abfangen. ⚑ | VERIFIED (aus früherer Notiz, API-Dump) / ASSUMPTION (Kollisionsverhalten) | api-studio-plugin.md (T3, T4, I1, I2, I7) |

### 2.8 Shortcut-Konventionen im Vergleich (Basis für ASTRA)

| Aktion | Unity VFX Graph (VERIFIED) | Blender 5.4 (VERIFIED) | After Effects (ASSUMPTION) | Vorschlag ASTRA (IDEA) |
|---|---|---|---|---|
| Abspielen/Pause | `/` = Neustart; Play-Controls im Scene View | Leertaste | Leertaste | **Leertaste** |
| Stopp, zurück zum Start | – | Esc = Abbruch | – | **Esc** = Stopp, Playhead zurück auf Startposition |
| Ein Frame vor/zurück | Step-Knopf | Links/Rechts | Bild↑/Bild↓ | **Links/Rechts** (Shift = 10 Frames) |
| Anfang/Ende | – | Shift+Links/Rechts | Pos1/Ende | **Pos1/Ende** in der Timeline (Shift+Links/Rechts als Alias) |
| Nächster/vorheriger Key | – | Hoch/Runter | J/K | **J/K** (Hoch/Runter bleiben für die Spurnavigation frei) |
| Arbeits-/Loop-Bereich | – | P / Alt+P | B/N | **B/N** setzen Anfang/Ende, **Alt+B** löscht |
| Alles bzw. Auswahl zeigen | A / F | Pos1 / Numpad-Punkt | – | **A** = alles, **F** = Auswahl (wie Unity und Studio-„Focus“) |
| Suche/Knoten hinzufügen | Leertaste | Shift+A | – | **Leertaste** im Graph, **Tab** als Alias |
| Mute/Bypass | Checkbox am Block | M | – | **M** |
| Rahmen/Gruppe | Shift+G | F (benannter Frame) | – | **Shift+G** |
| Notiz | Shift+N | – | – | **Shift+N** |
| Duplizieren (verlinkt) | Ctrl+D (Alt+Shift+D mit Links) | Shift+D (Alt+D verlinkt) | Ctrl+D | **Ctrl+D**; **Alt+D** = verlinktes Duplikat ⚑ (Kollision mit Studio-Ctrl+D prüfen) |
| Box-Auswahl / Spalte | Drag | Drag, B / K | Drag | **Drag** / **K** = alle Keys auf dem Frame |
| Interpolation / Easing | – | T / Ctrl+E | F9 (Easy Ease) | **T** = Interpolationsmenü, **F9** = Easy-Ease-Preset |
| Snap | – | Shift+S | Shift beim Ziehen | Snap per Standard **an**, **Shift beim Ziehen** = aus |
| Marker | – | M | Numpad-* | **Shift+M** (M ist für Mute vergeben) |

---

## 3. Einschränkungen und Kritik

### 3.1 Nicht übertragbar auf Roblox (⚑)

| Profi-Feature | Warum nicht in Roblox | Folge für ASTRA |
|---|---|---|
| **GPU-Partikelsimulation, Capacity, Instancing-Batches** (U26, U28) | Die Engine simuliert native Partikel intern. Es gibt keine Kapazität, keine Batches und keine Zählerabfrage. | Analyzer zeigt **Schätzungen** (Rate × Lifetime), keine Messwerte (IDEA). |
| **Per-Partikel-Attribute und Per-Partikel-Logik** (U7 BySpeed/Random-per-Particle, U14 GPU Events, N1 Particle Update) | Es gibt keine Partikel-Callbacks und keine Attribute (R1). Nur `NumberSequence` und `ColorSequence` über die Lebenszeit. | Nur „OverLife“ ist nativ. „BySpeed“, „OnDie“ und „OnCollide“ sind **nicht** anbietbar. Für Sub-Emitter-artige Effekte bleiben zeitgeplante Folge-Emits auf Emitter-Ebene. |
| **Custom Shader und HLSL, Lit/Six-Way-Lighting, Decals, Distortion** | Roblox hat keine eigenen Shader für Partikel (R2). | Ausblenden statt „ausgegraut anbieten“. Gestalterisch über Flipbooks, LightEmission und Layering lösen. |
| **Exaktes Scrubbing und Prewarm nativer Partikel** (U25, N8, N9) | `FastForward` ist gesperrt (R1), es gibt keinen Seed. | Der Weg aus `ARCHITECTURE.md` bleibt richtig: Bei `seek` werden Partikel geleert. Im UI kennzeichnen. Prewarm ist nur für prozedurale Komponenten möglich. |
| **Deterministische Zufallswerte in nativen Emittern** (U24) | Kein Seed (R1). | Der ASTRA-Seed steuert **nur** ASTRA-eigene Zufallsentscheidungen (Zeitplan, prozedurale Formen). Im Inspector bekommen native Felder einen Hinweis „engine-randomisiert“. |
| **Bounds- und Culling-Kontrolle** (U27, N6) | Culling verwaltet die Engine. | Ersatz ist **Distanz-Culling auf Effektebene** in der Runtime (IDEA, Effektklassen). |
| **Vector Fields, SDF, Point Caches, Mesh-Partikel** | Gibt es nicht (R2). | Keine Übernahme. Mesh-artige Effekte decken die vorhandenen `mesh`- und `debris`-Komponenten ab. |
| **Fixed Delta Time, Exact Fixed Time** (U28) | Native Partikel laufen frameabhängig. | Nur ASTRA-Komponenten rechnen mit `dt`. Dokumentieren. |
| **Echte Render Order** (U28 Output Render Order) | Nur `ZOffset` für Emitter und Beam, nicht für Trail (R3). | Eine „Draw Order“-Liste darf nur als Abbildung auf `ZOffset` angeboten werden, mit Hinweis. |

### 3.2 Kritik und Fallstricke der Vorbilder (übertragbare Lehren)

- **Komplexität**: Unity trennt Settings (Neukompilieren nötig) und Properties (live). Für Laien ist die Grenze
  unsichtbar. Für ASTRA gilt: Alles ist live, und es gibt keinen manuellen Kompilierschritt. Die Kompilierung ist billig
  und läuft automatisch. (ASSUMPTION aus U6 und U22)
- **Tiefe Kopien** von System-Subgraphen kosten laut Unity-Doku Speicher und Importzeit (U17). Für ASTRA heißt das:
  Vererbte Presets **beim Kompilieren flach auflösen**, aber in der Datei nur den **Diff** speichern. (IDEA)
- **Scrubbing ist teuer bzw. unvollständig**, selbst in Unity (Max Scrub Time, GPU-Spitzen beim Rückwärtsspielen,
  U25). In Roblox ist es grundsätzlich unmöglich (3.1). Die Erwartung muss im UI klar sein.
- **Profiling-Werte sind Richtwerte** (U26, Unity-Doku). ASTRA muss Analyzer-Werte ausdrücklich als Heuristik
  kennzeichnen (steht schon in ARCHITECTURE 7.4).
- **Shortcut-Drift**: Blender hat in 5.x Node-Shortcuts geändert (J = Make Links, F = Join in Named Frame, Ctrl+J =
  Join Nodes; B8/B9). Viele Tutorials beschreiben noch das ältere Schema (laut Modellwissen F = Make Links, Ctrl+J =
  Frame). Eine eigene Konvention sollte darum **dokumentiert und anzeigbar** sein (Cheat-Sheet-Overlay). (ASSUMPTION)
- **Quellenlage dieser Notiz**: Niagara, Sequencer und die After-Effects-Oberfläche sind nur Modellwissen (siehe
  Quellenlage oben). Keine Architekturentscheidung sollte allein darauf beruhen.

---

## 4. Konsequenzen für ASTRA

Die Punkte beziehen sich auf den bestehenden Entwurf (`docs/ARCHITECTURE.md`, `src/Runtime/Core/Types.luau`).

### 4.1 Datenmodell (Schema v1/v2) ⚑

- **IDEA – Typisierte Effekt-Parameter (`parameters`)**: `parameters: { [name]: { kind, default, min?, max?,
  category?, description?, exposed? } }`, wobei `kind` aus `PropertyKind` stammt (number, color3, vector3, boolean,
  numberRange, numberSequence, colorSequence). Verwendung in Properties und Keyframes über eine Referenz `"@name"`
  (analog zu `"$palette"`), zur Laufzeit `Play(…, { Params = { … } })`. `palette` wird zum Spezialfall
  (Parameter vom Typ color3). Vorbild: U11, U12, N3.
- **IDEA – Override-Semantik wie Unity (U12)**: Im Preview und im Inspector einer Instanz zeigt eine Checkbox
  „überschrieben“ an. Entfernt man das Häkchen, gilt wieder der Default. Beim Effektwechsel bleiben Werte erhalten,
  wenn Name und Typ passen.
- **IDEA – Preset-Vererbung als Diff (`extends`)**: `extends: "presetId@version"` plus nur geänderte Felder (per
  `id` adressierte Komponenten-Overrides, `removed: [ids]`). Der Compiler löst sie flach auf. Der Inspector zeigt
  geerbt, überschrieben und lokal unterschiedlich an, mit „Auf Vorlage zurücksetzen“. Die Validierung warnt, wenn
  die Vorlage eine neuere Version hat. Vorbild: N4, U17 (Kosten tiefer Kopien vermeiden). **Vorteil für Claude**:
  kleine, lesbare Diffs.
- **IDEA – Verlinkte Duplikate (`instanceOf`)**: Eine Komponente kann `instanceOf: "<componentId>"` plus Overrides
  tragen, etwa acht gleiche Splitter mit unterschiedlicher Transformation. Ändert man das Original, ändern sich alle
  Duplikate. Vorbild: Blender Alt+D und Unity Alt+Shift+D (B9, U21).
- **IDEA – Track-Komposition (`blend`)**: `TrackDef.blend: "set" | "add" | "multiply"` (Default "set"). Eine Kurve
  kann so einen Basiswert oder Parameter **modulieren** (z. B. Rate × Kurve), statt ihn zu überschreiben. Vorbild: U7.
- **IDEA – Emissions-Zyklus**: Partikel-Komponenten bekommen optional `loop: { count, duration, delayBefore,
  delayAfter }`, jeweils als Zahl oder `[min, max]` (`JsonNumberRange` gibt es schon). Die Auswertungszeitpunkte folgen
  U15: Count beim Start, Duration pro Loop, Delays pro Delay. Alles wird mit dem Seed in den Zeitplan entrollt, ist
  also deterministisch.
- **IDEA – Zeitanker für Events (`anchor`)**: `EventDef.anchor: "start" | "end" | "percent"` (Default "start"). Ein
  Event „0,1 s vor Ende“ bleibt beim Trimmen der Komponente am Ende kleben. Vorbild: Unity Time Space (U25).
- **IDEA – Event-Payloads**: `handle:Fire("Detonate", { position = …, color = … })` und ein Graph-Knoten
  `EventData(key)`. Vorbild: U13.
- **IDEA – Editor-Metadaten getrennt von der Runtime**: `editor: { label (0–8), solo, shy, locked, collapsed,
  graphFrames, notes }` pro Komponente bzw. Graph. Der Compiler ignoriert diese Daten, und ein Diff kann sie gezielt
  ausblenden. Vorbild: A4, A5, U18.

### 4.2 Explorer und Inspector (Komponenten-Stack)

- **ASSUMPTION/IDEA**: Native Roblox-Komponenten haben **feste** Property-Sätze. Ein frei umsortierbarer
  Modul-Stack wie in Niagara (N1) oder Unity (U5) würde eine Ausführungsreihenfolge vortäuschen, die es nicht gibt.
  ASTRA übernimmt nur die **Stack-Optik**: einklappbare, farbcodierte Gruppen (Emission, Spawn-Form, Bewegung,
  Aussehen, Über die Lebenszeit, Events, Qualität), eine Aktiv-Checkbox pro Komponente und ein Punkt für
  „weicht vom Default bzw. von der Vorlage ab“, mit Reset-Pfeil.
- **IDEA**: Ein grüner Punkt (Unity-Konvention U11) markiert Felder, die an einen exponierten Parameter gebunden sind.
  Ein Klick springt zum Parameter. Hover hebt alle Verwendungen hervor, in beide Richtungen.
- **IDEA**: Native Felder, die die Engine zufällig belegt (Lifetime- und Speed-Bereiche, Rotation), tragen ein
  kleines Badge „engine-random“ mit Tooltip „nicht über den ASTRA-Seed steuerbar“ (R1).

### 4.3 Timeline und Kurveneditor ⚑

- **IDEA – Layer-Modell wie After Effects** (A5) bestätigt die bestehende Konvention „Keyframes relativ zu
  `startTime`“. Ergänzungen: **Solo**, **Shy** (in der Timeline ausblenden), **Lock** und **Labelfarbe** pro
  Komponente, als reine Editor-Metadaten.
- **IDEA – Getrennter Loop- bzw. Arbeitsbereich** (A7, D2, S2): `editor.workArea = [start, end]` für Preview-Loops,
  unabhängig von `duration` und `loop` des Effekts. Shortcuts B/N, Alt+B löscht.
- **IDEA – Marker mit Dauer und Kommentar** (A6): `MarkerDef` bekommt `duration?` und `comment?`. Ein Marker mit Dauer
  wird als Balken gezeichnet, z. B. „Charge 0,2–0,6 s“ und passt zu den ASTRA-`phase`-Werten.
- **IDEA – Interpolationsmodell**: Die ASTRA-Easing-Werte bilden sauber auf AE ab: `"Linear"` = LINEAR, `"Constant"` =
  HOLD, `{bezier}` = BEZIER. Im Kurveneditor gibt es zwei Ansichten: **Wert** (Value Graph) und **Geschwindigkeit**
  (Speed Graph, Ableitung der Bezier-Kurve, rein darstellend). Dazu ein **Easy-Ease-Preset** (F9) und ein Dialog mit
  „Influence %“ für In und Out, der intern auf Bezier-Kontrollpunkte abgebildet wird. Die Abbildung
  Influence → x1/x2 ist eine eigene Annahme und zu testen.
- **IDEA – Keyframe-Auswahl** (D3): Drag = Box-Auswahl (Shift ergänzt, Ctrl entfernt), **K** = Spalte (alle Keys auf
  diesem Zeitpunkt über alle Spuren), `[` bzw. `]` = alles links/rechts vom Playhead, Ctrl+A = alles, Ziehen der
  Auswahl mit Snapping auf Frames, Marker, Keys und Komponentengrenzen. Alt beim Skalieren = um den Playhead
  skalieren (D4).
- **IDEA – Zeitanzeige** (D2): Umschalten zwischen Sekunden und Frames (Ctrl+T) bei wählbarer Vorschau-Framerate
  (30/60). Gespeichert wird immer in Sekunden (wie in ARCHITECTURE).
- **IDEA – Unity-Play-Controls** (U23) für das Preview-Panel: Stop, Play/Pause, **Step** (ein Frame bei 60 Hz),
  Restart, **Rate %** (an `timeScale`), Bounds bzw. Hilfsgeometrie anzeigen und ein **Event-Tester** (sendet benannte
  Events an `handle:Fire`).

### 4.4 Node Graph ⚑

- **IDEA – Pins mit Farbe *und* Form** (U9, B1, B4): Exec-Pins als Pfeil bzw. Dreieck und weiß; Daten-Pins als Kreis
  in Typfarbe (number, vector3, color3, boolean, string, component). `component`-Referenzen als Quadrat. Die Farben
  wählt ASTRA selbst, abgestimmt auf das Studio-Theme (hell/dunkel), mit genug Kontrast, und **nicht** von Unity oder
  Blender kopiert.
- **IDEA – Link-Zustände sichtbar** (B5, B6): ungültig = rot mit Diagnose-Tooltip (Code und Hinweis aus `Diagnostic`),
  gemutet = rot gestrichelt. Daten-Links, die erst zur Laufzeit ausgewertet werden (`OnEvent`-Flüsse), gestrichelt
  (Analogie zu Feld-Links). **Unerreichbare** Knoten (nicht von `OnPlay`, `OnMarker` oder `OnEvent` erreichbar)
  werden ausgegraut wie `is_inactive`.
- **IDEA – Mute/Bypass (M)** (B7): Ein gemuteter Exec-Knoten reicht den Fluss durch, ein gemuteter Daten-Knoten gibt
  seinen ersten typgleichen Eingang weiter (oder den Default). Gespeichert als `params.muted = true`. Die Validierung
  meldet das als Info.
- **IDEA – Organisation** (U18, B8): Frames bzw. Gruppen mit Titel und Farbe (Shift+G), Sticky Notes mit Titel und
  Text in drei Farben (Shift+N), Reroute-Knoten (Doppelklick auf einen Link oder Shift+Drag über einen Link). Alles
  liegt in `graph.frames` und `graph.notes`, die Runtime ignoriert es.
- **IDEA – Suche** (U19): Leertaste oder ein Link ins Leere öffnet eine **kontextgefilterte** Suche, die nur
  kompatible Knoten und Pins zeigt. Mit Favoriten, „zuletzt benutzt“ und Kategorien. „Knoten auf Link einfügen“
  (Shift+R). Alt+Buchstabe für die fünf häufigsten Knoten (Delay, Emit, Tween, Random, Math).
- **IDEA – Flow-Regeln als Tabelle** (U4): Die bestehenden Regeln aus ARCHITECTURE 6 (max. eine Verbindung pro
  Daten-Eingang, keine Zyklen, Komponententyp prüfen) werden als **datengetriebene Kompatibilitätstabelle** in der
  Knoten-Registry geführt. Der Editor (Live-Feedback beim Ziehen) und `Validation` (Claude/CLI) nutzen dieselbe
  Quelle.
- **IDEA – Subgraph und Makro** (U17, N5): „Auswahl → Makro“ speichert Knoten als wiederverwendbares Graph-Fragment
  mit eigenen Ein- und Ausgängen. Der Compiler löst es flach auf (keine Laufzeitkosten).

### 4.5 Performance, Skalierbarkeit und Budgets ⚑

- **IDEA – Effektklassen** (Vorbild N6, ASSUMPTION): `effectClass: "ambient" | "combat" | "cinematic" | "ui"` mit
  runtime-seitigen Regeln pro Klasse und Qualitätsstufe: `maxInstances` (älteste oder entfernteste zuerst beenden),
  `cullDistance` (Studs zur Kamera; dann nicht starten bzw. Emission stoppen) und `priority`. Die bestehenden
  Qualitätsprofile (countScale, segmentScale …) bleiben auf Komponentenebene. `AstraVFX.Play` liefert bei
  Budget-Ablehnung ein „no-op handle“ (kein Fehler).
- **IDEA – Analyzer im Unity-Stil** (U26): Werte pro Komponente und Qualitätsstufe (geschätzte aktive Partikel =
  Rate × mittlere Lifetime + Bursts, Parts, Beams, Lichter, Schatten), eine **Heatmap-Schwelle** (konfigurierbar) und
  „Select Unused“: unbenutzte Parameter, Graph-Knoten ohne Wirkung, deaktivierte Komponenten.
- **IDEA – „Peak aufnehmen“** (Analogie zu U27 Bounds Recording): Während einer Preview-Wiedergabe zählt ASTRA die
  echten Instanzen (Parts, Beams, Lichter) und die gemeinsame Ausdehnung der eigenen Komponenten. Das Ergebnis landet in
  `metadata.recordedPeak` für Analyzer und Culling-Radius. Native Partikel bleiben geschätzt (R1).
- **ASSUMPTION/IDEA – Qualität auf Clients**: `SavedQualityLevel` (1–10, Automatic) ist lesbar (R4). Ist er
  „Automatic“, braucht es einen Fallback (z. B. Plattform-Heuristik). Siehe die Constraints-Notiz.

### 4.6 Claude- und JSON-Workflow

- **IDEA**: Alle oben genannten Editor-Konzepte (Parameter, `extends`, `instanceOf`, `blend`, `anchor`, `workArea`,
  Marker-Dauer, Frames und Notes) sind **reine JSON-Daten** mit stabilen IDs. Claude kann sie ohne Plugin schreiben,
  und die Validierung meldet Fehler mit `path` (z. B. `graph.nodes[3].params.count`). Der Graph-Editor zeigt dieselbe
  Diagnose als Badge am Knoten (U4, B6).
- **IDEA**: Template-Metadaten wie in Unity (U28, U29): `metadata.template = { name, category, description, thumbnail,
  tags }`, damit Preset-Browser **und** Claude Vorlagen finden („gib mir alle combat/impact-Vorlagen“).

### 4.7 Tastatur ⚑

- **IDEA**: Die Tabelle in 2.8 ist der Vorschlag für die Standardbelegung. Umsetzung: widget-lokal über den
  Input-Catcher-Frame (R6). Für globale Aktionen zusätzlich `PluginAction`s **ohne** Default-Shortcut, die der Nutzer
  selbst belegen kann. Ein Overlay „?“ zeigt alle aktiven Kürzel (gegen die Shortcut-Drift, 3.2).
- **ASSUMPTION ⚑**: Ctrl+D, Ctrl+Z und Entf feuern vermutlich **auch** in Studio (R6, I7 der Plugin-Notiz). ASTRA sollte
  diese Tasten im Widget nur nutzen, wenn ein Studio-Test zeigt, dass keine Studio-Selektion mitbetroffen ist.
  Andernfalls weicht ASTRA auf X (löschen, Blender-Konvention) und Shift+D (duplizieren, Blender) aus.

---

## 5. Offene Fragen

1. **Niagara und Sequencer verifizieren** (Folgeauftrag mit funktionierender Websuche): Stimmen die Konzepte N1–N10
   und S1–S3, vor allem Effect Types/Scalability (Budget, Significance, Cull Reactions), Emitter-Vererbung (Verhalten
   beim Löschen geerbter Module) und die Life-Cycle-Track-Semantik (Desired Age, Seek)? Zu prüfen auf
   `dev.epicgames.com/documentation/en-us/unreal-engine/` (Niagara-Übersicht, Scalability and Best Practices, Niagara
   Debugger, Sequencer).
2. **After-Effects-Oberfläche verifizieren** (A9, A10): Easy-Ease-Werte (Influence-Default), Speed-Graph-Verhalten und
   die Shortcut-Liste auf `helpx.adobe.com/after-effects/` (Keyboard shortcuts, Speed graph, Keyframe interpolation).
3. **Blender-Formsemantik** (B3): Kreis, Raute und Raute mit Punkt im Handbuch (`docs.blender.org/manual/…/geometry_nodes/fields.html`) prüfen.
   Gilt die Keymap aus `main` (5.4 alpha) auch für die aktuelle stabile Version?
4. **Studio-Test**: Lösen Ctrl+D, Entf und Ctrl+Z im fokussierten ASTRA-Widget **gleichzeitig** Studio-Aktionen aus?
   (Entscheidet die Shortcut-Belegung, 4.7.)
5. **Influence → Bezier**: Wie bildet man AE-artige Speed/Influence-Ease verlustfrei auf ASTRA-Bezier
   (`[x1, y1, x2, y2]`) ab, wenn der Wertebereich der Kurve normiert ist? Prototyp im Kurveneditor nötig.
6. **Parameter-Referenzen**: Reicht ein String-Präfix `"@name"`, oder braucht es ein Objekt `{ "param": "name" }`,
   damit Schema-Validierung und JSON-Schema-Tooling (Claude) es eindeutig erkennen? (Eine Kollision mit Asset-IDs oder
   Text-Properties wäre beim Präfix möglich.)
7. **Effektklassen**: Wer setzt die Grenzen, der Effekt (Datei) oder das Spiel (`AstraVFX.Configure`)? Vermutlich
   Defaults im Spiel, der Effekt wählt nur die Klasse.
8. **Mute-Semantik im ASTRA-Graph**: Was gibt ein gemuteter Datenknoten aus, wenn kein typgleicher Eingang existiert
   (Default des Ausgangs oder ein Validierungsfehler)?

---

## 6. Quellen

**Unity Visual Effect Graph (VERIFIED, offizieller Doku-Quelltext, Branch master, gelesen 2026-10-27)**
Basis: `https://raw.githubusercontent.com/Unity-Technologies/Graphics/master/Packages/com.unity.visualeffectgraph/Documentation~/`
- TableOfContents.md, GraphLogicAndPhilosophy.md, Systems.md, Contexts.md, Context-Spawn.md, Context-GPUEvent.md,
  Context-Event.md, Context-Initialize.md, Context-Update.md, Blocks.md, Block-SetAttributeFromCurve.md, Block-Burst.md,
  Block-Trigger-Event.md, Operators.md, Operator-RandomNumber.md, Properties.md, Events.md, Attributes.md, Subgraph.md,
  Blackboard.md, StickyNotes.md, Shortcuts.md, VisualEffectGraphWindow.md, VisualEffectComponent.md, ComponentAPI.md,
  VisualEffectGraphAsset.md, Templates-window.md, PropertyBinders.md, EventBinders.md, OutputEventHandlers.md,
  Timeline.md, performance-debug-panel.md, visual-effect-bounds.md, Instancing.md, VisualEffectProjectSettings.md,
  VisualEffectPreferences.md, VisualEffectGraphTypeReference.md, GettingStarted.md, whats-new-17.md
- Entsprechende Online-Seiten: `https://docs.unity3d.com/Packages/com.unity.visualeffectgraph@17.0/manual/<Seite>.html`
  (nicht direkt erreichbar)

**Blender (VERIFIED, Quelltext-Mirror `blender/blender`, Branch main = 5.4 alpha, gelesen 2026-10-27)**
- https://raw.githubusercontent.com/blender/blender/main/scripts/presets/keyconfig/keymap_data/blender_default.py
- https://raw.githubusercontent.com/blender/blender/main/source/blender/makesrna/intern/rna_node_socket.cc
- https://raw.githubusercontent.com/blender/blender/main/source/blender/makesrna/intern/rna_node_tree_interface.cc
- https://raw.githubusercontent.com/blender/blender/main/source/blender/makesrna/intern/rna_nodetree.cc
- https://raw.githubusercontent.com/blender/blender/main/source/blender/editors/space_node/drawnode.cc
- https://raw.githubusercontent.com/blender/blender/main/source/blender/editors/space_node/node_relationships.cc
- https://raw.githubusercontent.com/blender/blender/main/source/blender/editors/space_node/node_edit.cc
- https://raw.githubusercontent.com/blender/blender/main/source/blender/editors/space_node/node_group.cc
- https://raw.githubusercontent.com/blender/blender/main/source/blender/editors/space_node/node_add.cc
- https://raw.githubusercontent.com/blender/blender/main/source/blender/editors/space_node/node_ops.cc
- https://raw.githubusercontent.com/blender/blender/main/release/datafiles/userdef/userdef_default_theme.c
- https://raw.githubusercontent.com/blender/blender/main/source/blender/blenkernel/BKE_blender_version.h

**After Effects (REPORTED, Community-Scripting-Guide)**
- https://raw.githubusercontent.com/docsforadobe/after-effects-scripting-guide/master/mkdocs.yml
- …/docs/property/property.md, …/docs/other/keyframeease.md, …/docs/other/markervalue.md,
  …/docs/item/compitem.md, …/docs/layer/layer.md, …/docs/layer/avlayer.md (Präfix
  `https://raw.githubusercontent.com/docsforadobe/after-effects-scripting-guide/master`)

**Roblox (VERIFIED, lokal)**
- /root/tools/ref/API-Dump.json (0.745.0.7451137), /root/tools/ref/globalTypes.d.luau
- Frühere ASTRA-Notizen: docs/research/api-particles-beams-trails.md, docs/research/api-studio-plugin.md

**Unreal Niagara und Sequencer, AE-Oberfläche**: keine Quelle in dieser Sitzung erreichbar (WebSearch-Budget
erschöpft, `dev.epicgames.com` und `helpx.adobe.com` blockiert). Die Aussagen sind Modellwissen und als ASSUMPTION
markiert.
