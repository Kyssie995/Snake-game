# Recherche: ROS Particle Editor ("Ros Particle Editor")

Stand: 2026-10-27 · Phase 1 (Research & Architecture) · Autor: Research-Subagent für ASTRA VFX STUDIO

> **Label-Legende:** **VERIFIED** = offizielle Roblox-Doku / lokaler API-Dump (Engine 0.745) / eigene Produktseite ·
> **REPORTED** = DevForum-Posts, Videos, Drittseiten, Such-Snippets · **ASSUMPTION** = eigene Schlussfolgerung ·
> **IDEA** = eigene Design-Idee für ASTRA. ⚑ = *critical* (eine ASTRA-Architekturentscheidung hängt daran).

> **Wichtiger Hinweis zur Quellenlage:** DevForum, Creator Store, YouTube und GitHub waren aus der Sandbox per HTTP
> **nicht** erreichbar (Proxy 403). Alle Aussagen über das Produkt stammen aus **Such-Snippets** (WebSearch) des
> DevForum-Threads, der Video-Beschreibungen und einer Drittanbieter-Doku. Das macht jede Produktaussage per Definition
> höchstens **REPORTED**. Screenshots, das Video-Tutorial und die Creator-Store-Seite (Preis, Rating, Update-Datum) konnten
> **nicht** eingesehen werden. Es wurde kein Code des Plugins gelesen oder kopiert.

---

## 1. Zusammenfassung

Der **ROS Particle Editor** ist ein kleines, früh (Februar 2022) veröffentlichtes Roblox-Studio-Plugin von
**roasted_shrimps** (DevForum-Thread zeigt teilweise den Namen *dododorororo* als OP – vermutlich derselbe Account
nach Umbenennung, ASSUMPTION). Creator-Store-Asset-ID **8813198599**. Kernidee: Ein **viewport-zentrierter
"Particle Edit Mode"**, der

1. **Size / Transparency / Squash** (alle `NumberSequence`) **mehrerer ParticleEmitter gleichzeitig** anpasst,
2. dabei **keine Wertebegrenzung** für Size und Squash hat (Studio-eigener Sequence-Editor kappte historisch bei 10),
3. die **erwartete Flugbahn** der Partikel als Linien im 3D-Viewport zeigt ("Blue lines … expected movements"),
4. den **Spawn-Bereich** (Emissionsvolumen) als aquafarbene Linien um das Part zeichnet.

Es ist damit eher ein **Visualisierungs- und Multi-Edit-Hilfswerkzeug** als ein vollständiger VFX-Editor: Es gibt
**keine Belege** für eigene Curve-Editoren (Bezier/Tangenten), Presets, Emit-/Burst-Preview, Color-Editing, Timeline,
Beams/Trails-Unterstützung oder Export. Gelobt wird der **Lerneffekt** ("visualisiert genau, was jede Einstellung tut")
und die **gut lesbare UI-Größe**. Kritisiert werden **Fehler beim Klick auf Size/Transparency** (vom Autor auf einen
Konflikt mit dem Fremd-Plugin **"Bezier Sequencer"/BezierSequence** zurückgeführt), Fälle, in denen das Plugin
**gar nicht erscheint**, sowie (Jan. 2026) dass es sich **nicht abschalten lässt**, wenn man nicht an VFX arbeitet.
Preis/Bezahlmodell konnte **nicht** ermittelt werden.

Für ASTRA ist ROS vor allem als **Beleg für Nutzerbedürfnisse** wichtig: Multi-Emitter-Sequence-Editing,
unbegrenzte Wertebereiche, Trajektorien- und Spawn-Volumen-Gizmos, robuste Koexistenz mit anderen Plugins und
Opt-in-Aktivierung. ASTRA kann alle diese Punkte unabhängig und deutlich robuster umsetzen (siehe Abschnitt 4).

---

## 2. Befunde

### 2.1 Identität, Herkunft, Verbreitung

| # | Befund | Label | Quelle |
|---|--------|-------|--------|
| B1 | Plugin-Name "Ros Particle Editor" / "ROS Particle Editor", Creator-Store-/Library-Asset **8813198599** (`roblox.com/library/8813198599/ROS-Particle-Editor`, `create.roblox.com/store/asset/8813198599/...`). | REPORTED | Video-Beschreibungen [S7][S8][S9], Matt-Empire-Doku [S6] |
| B2 | Autor **roasted_shrimps** (DevForum-Profil existiert). Der Thread-OP wird in manchen Snippets als *dododorororo* angezeigt. | REPORTED | [S1][S6][S19] |
| B3 | Thread "The World's Best Particle Editor Plugin! (99% SURE)" in *Community Resources*, gepostet **15. Feb. 2022**; Autor-Update am **16. Feb. 2022**. | REPORTED | [S1] |
| B4 | Thread-Statistik laut Tag-Listing/Snippets: **20–21 Replies**, **~35 000–37 000 Views**, **165 Likes** auf dem Post, letzte Aktivität **8. Feb. 2026** (Thread hat eine Seite 2). | REPORTED | [S4][S1][S2] |
| B5 | Wird in mehreren YouTube-VFX-Tutorials als empfohlenes Plugin verlinkt ("ROS Editor"), u. a. zusammen mit einem Emit+Delay-Plugin und dem **BezierSequence**-Plugin (Asset 8133535339). | REPORTED | [S8][S9][S11] |
| B6 | Es existiert ein Video "How to use Ros Particle Editor" (laut Snippet vom Autor). Inhalt konnte nicht eingesehen werden. | REPORTED | [S7] |
| B7 | Eine Drittanbieter-Doku (Matt Empire, Archiv-Bereich) empfiehlt es als nützliches Plugin, das "das Endergebnis visualisiert" und "ein paar nützliche Extras" bietet. | REPORTED | [S6] |
| B8 | **Preis/Bezahlmodell: nicht ermittelbar.** Keine Quelle nennt einen Robux- oder USD-Preis. Eine Such-Zusammenfassung "vermutet" kostenlos – das ist unbelegt. Achtung: Die in einem Snippet auftauchende Aussage "war einen Tag kostenlos, danach kostenpflichtig" bezieht sich auf **VFX Suite**, nicht auf ROS. | NOT FOUND / ASSUMPTION | [S10] |
| B9 | Kein aktuelles Update-Datum, keine Versionsnummer, kein Creator-Store-Rating auffindbar. | NOT FOUND | – |

### 2.2 Features (laut Autor-Post, sinngemäß)

| # | Befund | Label | Quelle |
|---|--------|-------|--------|
| F1 | **Multi-Emitter-Editing** von **Size, Transparency, Squash** ("Adjusting Size/Transparency/Squash of multiple particle emitter"). | REPORTED ⚑ | [S1] |
| F2 | **"No limits for size and squash"** – keine Wertebegrenzung. | REPORTED | [S1] |
| F3 | **Trajektorien-Vorschau**: "Expect the movement of particles" – blaue Linien zeigen die erwartete Bewegung der Partikel. | REPORTED ⚑ | [S1] |
| F4 | **Spawn-Bereich-Anzeige**: aquafarbene Linien um das Part markieren den Bereich der Partikelerzeugung. | REPORTED | [S1] |
| F5 | **Update 16.02.2022**: Bewegungslinien von `ConeHandleAdornment` (im Post als "ConHandleAdornment" vertippt) auf `LineHandleAdornment` umgestellt ("klarer"), Linienfarbe = Partikelfarbe. | REPORTED | [S1] |
| F6 | **Update**: funktioniert auch, wenn der Emitter an einem **Attachment oder Bone** hängt (nicht nur an einem Part). | REPORTED | [S1] |
| F7 | **Abgelehnter Feature-Request**: Partikel einer **Bezier-Kurve folgen lassen**. Autor: Der Pfad werde durch CFrame, Speed, Acceleration und Drag bestimmt, daher sei Bezier-Pfadfolgen (mit nativen Emittern) nicht möglich. | REPORTED ⚑ | [S1] |
| F8 | **Keine Belege gefunden** für: eigenen Curve-Editor mit Tangenten/Bezier, Envelope-Editing, Presets/Bibliothek, Emit-/Burst-Button, Color/ColorSequence-Editing, Beams/Trails, Undo-Integration, Export/Import, Timeline. | NOT FOUND | – |

### 2.3 UI-Layout und Workflow

| # | Befund | Label | Quelle |
|---|--------|-------|--------|
| U1 | **Aktivierung kontextuell**: Wird ein ParticleEmitter selektiert, erscheint **rechts am Bildschirmrand ein Button**; Klick aktiviert den **"Particle Edit Mode"**. | REPORTED | [S1] |
| U2 | Im Edit Mode: **Buttons links** für **Size, Transparency, Squash**. | REPORTED | [S1] |
| U3 | Wie die eigentliche Werteeingabe aussieht (Graph? Drag im Viewport? Zahlenfelder?) ist aus den Snippets **nicht** ersichtlich. | NOT FOUND | – |
| U4 | Vermutlich eine Overlay-`ScreenGui` über dem Viewport statt eines `DockWidgetPluginGui` (Button "auf dem Bildschirm" rechts, Toolbuttons links), gesteuert über `Selection.SelectionChanged`. | ASSUMPTION | abgeleitet aus U1/U2 |
| U5 | Nutzer im VFX-Suite-Thread loben, dass ROS eine **"gute Größe"** habe, um zu sehen, was man tut (VFX-Suite-UI sei zu klein). | REPORTED | [S10] |
| U6 | Workflow (rekonstruiert): Emitter(s) selektieren → Button rechts → Edit Mode → Property links wählen → Werte anpassen, während Trajektorien- und Spawn-Linien im Viewport live das Ergebnis zeigen. | ASSUMPTION | aus U1–U2, F3–F4 |

### 2.4 Nutzer-Feedback, Bugs, Feature-Requests

| # | Befund | Label | Quelle |
|---|--------|-------|--------|
| K1 | **Lob**: Das Plugin "visualisiert genau, was jede Einstellung tut", bringt "Klarheit und Situational Awareness" – nützlich zum Lernen. Ein weiterer Nutzer: "hat mich genau zu dem geführt, was ich gesucht habe". | REPORTED | [S1][S3] |
| K2 | **Bug**: "Funktioniert nicht – Fehler beim Klick auf Size, Transparency usw." | REPORTED ⚑ | [S1] |
| K3 | **Konflikt mit "Bezier Sequencer"**: Laut Thread wirft der Bezier Sequencer einen Fehler, wenn ein ParticleEmitter durch einen *externen* Editor geändert wird; das fehlerwerfende Plugin sei nicht vom ROS-Autor, er könne es nicht beheben. Ein Kommentar präzisiert: Bei gemeinsamer Nutzung geht der **Bezier Sequencer** kaputt, nicht ROS. | REPORTED ⚑ | [S1] |
| K4 | Mit "Bezier Sequencer" ist sehr wahrscheinlich das Plugin **BezierSequence** (Asset 8133535339) gemeint, das in denselben Tutorials verlinkt wird. | ASSUMPTION | [S8][S11] |
| K5 | Wahrscheinlicher Mechanismus des Konflikts: Ein Plugin hält einen eigenen Zustand (z. B. Kurvendaten) zu einer `NumberSequence` und reagiert auf `Changed`; ändert ein anderes Plugin die Property, passt der gespeicherte Zustand nicht mehr zur Ist-Sequence und der Handler läuft auf einen Fehler. | ASSUMPTION ⚑ | abgeleitet aus K3 |
| K6 | **Bug/Support**: Ein Nutzer berichtet, das Plugin "erscheint überhaupt nicht", und fragt, ob es "dauerhaft kaputt" sei. Keine Antwort im Snippet sichtbar. | REPORTED | [S1] |
| K7 | **Feature-Request (11. Jan. 2026)**: Plugin soll sich **abschalten** lassen, damit es nicht ständig läuft/erscheint, wenn man nicht an VFX arbeitet. Keine Autor-Antwort sichtbar. | REPORTED ⚑ | [S2] |
| K8 | **Feature-Request**: Bezier-Pfad für Partikelbewegung (abgelehnt, siehe F7). | REPORTED | [S1] |
| K9 | Der Autor der späteren **VFX Suite** (PrimeVoxel, Aug. 2023) schreibt, die meisten Utilities von ROS würden in VFX Suite **nicht** implementiert – ROS besetzt also eine eigene Nische (Viewport-Visualisierung). | REPORTED | [S10] |
| K10 | Im VFX-Suite-Thread wird bemängelt, man könne Einstellungen bestehender Partikel (Size/Squash) schwer auslesen/weiterbearbeiten – das betrifft **VFX Suite**, zeigt aber ein allgemeines Nutzerbedürfnis: **verlustfreies Laden vorhandener Emitter**. | REPORTED | [S10] |
| K11 | Wartungsstatus: Letzte erkennbare Autor-Aktivität sind die Updates vom Feb. 2022; spätere Bug-Reports und der Request von 2026 zeigen keine sichtbare Antwort. Das Plugin wirkt **unmaintained**. | ASSUMPTION | [S1][S2] |

### 2.5 Engine-/Studio-Kontext (warum ROS' Features gefragt sind)

| # | Befund | Label | Quelle |
|---|--------|-------|--------|
| E1 | `ParticleEmitter.Size`, `.Transparency`, `.Squash` sind `NumberSequence`; Defaults laut Full-API-Dump: Size `0 1 0 1 1 0` (konstant 1), Transparency/Squash konstant 0. Squash > 0 = horizontal schmaler/vertikal länger, < 0 umgekehrt. | VERIFIED | API-Dump 0.745; [D2] |
| E2 | `NumberSequence.new`: Keypoints aufsteigend, erster bei Time 0, letzter bei Time 1, **maximal 20 Keypoints**. `NumberSequenceKeypoint.Envelope` ≥ 0, Wert wird pro Partikel zufällig in [value − envelope, value + envelope] gewählt. Interpolation zwischen Keypoints ist **linear**. | VERIFIED ⚑ | [D3][D4][D2] |
| E3 | Der Studio-eigene NumberSequence-Editor war historisch bei **Size = 10** gekappt, obwohl die Engine größere Werte (berichtet: bis 200) erlaubt; Workaround war Setzen per Skript/Command Bar. Erklärt das ROS-Feature "No limits". Ob die Kappung in Studio 2026 noch existiert: unbekannt. | REPORTED | [S16][S17] |
| E4 | Studio's Properties-Fenster konnte **Sequence-Properties bei Mehrfachauswahl nicht bearbeiten** (Reports 2016, 2021, 2022; Staff: "fehlendes Feature, kein Bug" bzw. "kein sinnvoller Startwert für den Curve-Editor bei Multi-Edit"). Ein älterer Staff-Post meldet eine Änderung, die Multi-Edit erlaubt – Berichte widersprechen sich, aktueller Stand unklar. | REPORTED ⚑ | [S12][S13][S14][S15] |
| E5 | Particle-Bewegung wird bestimmt durch Emissionsrichtung/Shape, `Speed` (NumberRange), `SpreadAngle`, `Acceleration` (global), `Drag` (Halbwertszeit der Geschwindigkeit in s, exponentiell; negativ = Wachstum), `VelocityInheritance`, `LockedToPart`, `WindAffectsDrag`, `TimeScale`. Lifetime ist intern auf **20 s** gedeckelt. | VERIFIED ⚑ | [D1][D2], API-Dump |
| E6 | ParticleEmitter emittiert nur, wenn er unter einem `BasePart` oder einem `Attachment` (in einem Part) hängt; bei Attachment spawnen Partikel an der Attachment-Position. `Bone` erbt von `Attachment`. | VERIFIED | [D2], API-Dump |
| E7 | `LineHandleAdornment` (Length, Thickness) und `ConeHandleAdornment` existieren (Superclass `HandleAdornment`). Zusätzlich gibt es **`WireframeHandleAdornment`** mit `AddLine`, `AddLines`, `AddPath(points, loop)`, `AddText`, `Clear` – ein einzelnes Instance kann viele Liniensegmente zeichnen. | VERIFIED ⚑ | API-Dump 0.745; [D5] |
| E8 | Plugin-Grundlagen: `Selection` (Get/Set, `SelectionChanged`), `ChangeHistoryService:TryBeginRecording/FinishRecording` für Undo/Redo (nur eine aktive Recording pro Plugin), `Plugin:GetSetting/SetSetting`, `Plugin.Unloading`. `Plugin:CreateDockWidgetPluginGui` ist im Dump 0.745 als **Deprecated** markiert, Nachfolger `CreateDockWidgetPluginGuiAsync`. | VERIFIED ⚑ | [D6], API-Dump |
| E9 | Ein anderes Community-Plugin ("SmoothSequence Graph") speichert Kurvenmetadaten als **Attributes mit Präfix** am Emitter und **sampelt** die glatte Kurve in NumberSequence-Keypoints mit Fehlerminimierung – ein Ansatz, der zeigt, wie man glatte Kurven trotz linearer 20-Keypoint-Grenze abbildet. | REPORTED | [S18] |

---

## 3. Einschränkungen / Kritik (Bewertung)

**Stärken (REPORTED/ASSUMPTION):**
- Sehr klarer Fokus: das, was Studio fehlt (Multi-Edit von Sequences, Werte über die Editor-Kappung hinaus).
- **Viewport-First**: Trajektorien- und Spawn-Volumen-Gizmos machen abstrakte Parameter (Speed, Drag, Acceleration, Shape) sofort verständlich → hoher Lernwert.
- Große, gut lesbare UI; kontextuelle Aktivierung ohne Panel-Suche.
- Unterstützung von Emittern an Attachments/Bones (wichtig für Character-VFX).

**Schwächen (REPORTED/ASSUMPTION):**
- **Sehr kleiner Funktionsumfang** – nur 3 Properties; keine Color-, Rotation-, Speed-/Lifetime-Bearbeitung im Plugin selbst nachweisbar.
- **Keine erkennbare Kurvenqualität** (Tangenten/Bezier/Easing) und kein Preset-System.
- **Statische Vorhersage**: Trajektorie ist eine Näherung; Zufallsanteile (Speed-Range, SpreadAngle, Envelope), Wind, VelocityInheritance und bewegte Parents lassen sich so nur grob darstellen (ASSUMPTION).
- **Robustheit**: Fehler beim Klick auf Properties; Konflikt mit anderem Sequence-Plugin; "erscheint nicht"-Reports.
- **Immer aktiv**: Kein Opt-out/Toggle (Request 2026) → Overlay/Listener stören Nicht-VFX-Arbeit.
- **Unmaintained**: Seit Feb. 2022 keine sichtbaren Updates; offene Reports unbeantwortet.
- Kein Undo-Nachweis, keine Persistenz außerhalb der Instances, kein Datenformat/Export.
- Preis, Lizenz, aktuelle Studio-Kompatibilität: **unbekannt**.

---

## 4. Konsequenzen für ASTRA

Alle Punkte sind **eigene Designideen (IDEA)**, unabhängig entwickelt; es wird nichts von ROS übernommen außer der
Erkenntnis, welche Bedürfnisse Nutzer haben.

### 4.1 Multi-Emitter-Editing als First-Class-Feature ⚑
- **IDEA:** Inspector und Curve-Editor arbeiten nativ auf **Mehrfachauswahl** (Effect-Explorer-Selektion, nicht nur
  Studio-Selection). Bei gleichen Werten → normaler Editor; bei abweichenden Werten → "Mixed"-Zustand mit
  Overlay aller Kurven (halbtransparent) und klarer Wahl der Operation:
  - *Absolute*: eine Kurve auf alle schreiben,
  - *Relative*: Operationen wie **Scale (×)**, **Offset (+)**, **Retime** (Zeitachse stauchen), **Invert**, **Normalize**
    auf jede Kurve einzeln anwenden – löst das von Roblox-Staff genannte Problem "kein sinnvoller Startwert bei Multi-Edit".
- **IDEA:** "Link Curves": mehrere Emitter teilen eine Kurven-Ressource im Effect-JSON (Referenz statt Kopie).

### 4.2 Wertebereiche und Datenmodell ⚑
- **IDEA:** Keine UI-Kappung bei 10; stattdessen **Soft-Ranges** (Slider-Bereich) + **Hard-Validation** gegen
  dokumentierte Engine-Grenzen. Der Validator (auch für Claude-generierte JSON-Dateien) prüft: Time 0/1, aufsteigend,
  **≤ 20 Keypoints**, Envelope ≥ 0, Lifetime ≤ 20 s (Warnung), Size-Obergrenze als Warnung (exakter Engine-Wert noch zu
  verifizieren, berichtet 200).
- **IDEA:** **Kurven-Source-of-Truth im ASTRA-Format** (Bezier/Easing-Segmente, beliebig viele Kontrollpunkte),
  deterministisch **gebacken** in ≤ 20 lineare Keypoints mit Fehlerminimierung (adaptive Subdivision). Das JSON speichert
  beides: `curve` (editierbar) und `baked` (für Runtime ohne Plugin), plus Bake-Hash.

### 4.3 Viewport-Gizmos (Trajektorie + Spawn-Volumen) ⚑
- **IDEA:** **Trajectory Preview** analytisch/numerisch aus Speed (min/max), SpreadAngle, EmissionDirection,
  Acceleration und Drag (exponentielle Halbwertszeit) berechnen; Lifetime-Bereich als Längenbegrenzung.
  Statt einer Linie: **Fächer** (Min-/Mittel-/Max-Bahn + Kegel der SpreadAngle) und optional N gesampelte Zufallsbahnen
  mit festem Seed → zeigt Streuung ehrlich statt Scheingenauigkeit.
- **IDEA:** Rendering mit **einem `WireframeHandleAdornment` pro Emitter** (`AddPath`) statt vieler
  `LineHandleAdornment`-Instanzen → weniger Instances, ein `Clear()` pro Update; Farbe aus `Color`-Sequence (Start/Ende)
  und Breite optional aus Size. Gizmo-Instanzen nicht archivierbar (`Archivable = false`), in einem Plugin-eigenen
  Container, beim Deaktivieren/`Unloading` vollständig entfernt.
- **IDEA:** **Spawn-Volume-Gizmo** für Shape (Box/Sphere/Cylinder/Disc), ShapeStyle (Volume/Surface), ShapeInOut,
  ShapePartial; bei Attachment/Bone-Parent Punkt-Gizmo + Richtungspfeil.
- **IDEA:** Ergänzend zum statischen Gizmo: **Live-Preview** über `Emit()`/`Clear()` und Timeline-Scrubbing
  (Phase 3), sodass Vorhersage und echtes Rendering nebeneinander vergleichbar sind.

### 4.4 Robustheit & Koexistenz mit anderen Plugins ⚑
- **IDEA:** ASTRA darf **nie** davon ausgehen, alleiniger Schreiber einer Property zu sein:
  - Jeder Schreibzugriff in `pcall` + Validierung; Fehler werden im ASTRA-Log angezeigt, nicht als ungefangene Exceptions.
  - Externe Änderungen erkennen (`GetPropertyChangedSignal` + Vergleich mit zuletzt geschriebenem Bake-Hash) →
    Status "extern geändert" mit Optionen *Übernehmen (Re-Import)* / *ASTRA-Kurve wiederherstellen*.
  - Kein Crash, wenn eine Sequence nicht aus ASTRA-Kurven stammt (Import erzeugt lineare Kurve aus Keypoints,
    inkl. Envelope – verlustfrei).
  - Eigene Metadaten nur in **namespaced Attributes** (z. B. Präfix `ASTRA_`) oder im Effect-JSON – nie Fremd-Attribute
    anfassen.
- **IDEA:** Alle Änderungen über **`ChangeHistoryService:TryBeginRecording/FinishRecording`** (undo-fähig, eine Recording
  pro Geste, Drag = eine Recording); laufende Recording-ID beim Reload aufräumen.
- **IDEA:** Kompatibilitätstests in der Test-Harness: "fremdes Plugin ändert Size während ASTRA-Drag" (simuliert).

### 4.5 Opt-in-Aktivierung & UX ⚑
- **IDEA:** Kein Always-on-Overlay. **Toolbar-Toggle** (Zustand per `plugin:SetSetting` persistent), Gizmos nur im aktiven
  Modus und nur für ASTRA-Effekte bzw. explizit gewählte Emitter; Listener (`SelectionChanged` etc.) im inaktiven
  Zustand trennen.
- **IDEA:** UI in `DockWidgetPluginGui` über **`CreateDockWidgetPluginGuiAsync`** (nicht-deprecated API).
- **IDEA:** **UI-Scale-Einstellung** (Nutzer schätzen große, gut lesbare UI) und Theme-Support.
- **IDEA:** **Lernmodus/Tooltips**: Beim Hover über eine Property den passenden Gizmo-Teil hervorheben
  (z. B. Drag → Bahnkrümmung) – übernimmt das gelobte "visualisiert, was jede Einstellung tut" als bewusstes Feature.

### 4.6 Pfadfolgende Partikel ⚑
- **IDEA:** Native Emitter können keiner Bezier-Kurve folgen (laut Autor; konsistent mit der dokumentierten
  Bewegungsphysik, VERIFIED E5). ASTRA kann das im **Runtime-Modul** als eigenen Komponententyp anbieten,
  z. B. "Path Emitter": Attachment wird entlang einer Bezier-Kurve animiert (Timeline-Track) und emittiert per
  `Emit()`/Rate mit `LockedToPart`-Varianten, oder Sub-Emitter entlang gesampelter Pfadpunkte. Performance-Analyzer
  muss die Kosten (Instance-Anzahl, Emit-Rate) ausweisen.

---

## 5. Offene Fragen

1. **Preis/Bezahlmodell** von ROS (Asset 8813198599) – kostenlos oder Robux? (Creator Store nicht erreichbar.)
2. **Aktueller Stand**: letztes Update, Funktioniert es in Studio 2026 (neues Properties-Panel, neue UI)?
3. **Exakte Edit-Interaktion**: Graph, Viewport-Drag oder Zahlenfelder? Absolute oder relative Multi-Edit-Semantik?
   (Video "How to use Ros Particle Editor" konnte nicht angesehen werden.)
4. **Undo-Unterstützung** von ROS (ChangeHistoryService) – unbekannt.
5. Wurde der Konflikt mit BezierSequence je behoben, und ist "Bezier Sequencer" wirklich BezierSequence (8133535339)?
6. **Studio-Stand 2026**: Unterstützt das aktuelle Properties-Fenster Multi-Select-Editing von NumberSequence/
   ColorSequence? Ist die Size-Kappung (10) im Sequence-Editor noch aktiv? → In Studio manuell prüfen (betrifft die
   Gewichtung von ASTRA-Feature 4.1/4.2).
7. **Exakte Engine-Obergrenzen** für Size und Squash (nicht in offizieller Doku gefunden) → per Skript in Studio testen.
8. Exakte Drag-/Acceleration-Integrationsformel der Engine (Doku sagt nur "Halbwertszeit der Geschwindigkeit") →
   empirisch kalibrieren, bevor der Trajectory-Gizmo als "genau" beworben wird.

---

## 6. Quellen

**Produkt / Community (REPORTED, nur via Such-Snippets eingesehen):**
- [S1] DevForum: "The World's Best Particle Editor Plugin! (99% SURE)" – https://devforum.roblox.com/t/the-worlds-best-particle-editor-plugin-99-sure/1668424
- [S2] Dito, Seite 2 – https://devforum.roblox.com/t/the-worlds-best-particle-editor-plugin-99-sure/1668424?page=2
- [S3] Dito, Post #2 (https_KingPie) – https://devforum.roblox.com/t/the-worlds-best-particle-editor-plugin-99-sure/1668424/2
- [S4] DevForum Tag-Listing "particleemitter" – https://devforum.roblox.com/tag/particleemitter
- [S5] Creator Store / Library (nicht erreichbar) – https://create.roblox.com/store/asset/8813198599 · https://www.roblox.com/library/8813198599/ROS-Particle-Editor
- [S6] Matt Empire Doku (Archiv) – https://themattempire.gitbook.io/documentation/archive/roblox/visual-effects-vfx/particle-emitters
- [S7] YouTube "How to use Ros Particle Editor" – https://www.youtube.com/watch?v=kUNxF9gmAMs
- [S8] YouTube "Roblox Particles/VFX Tutorial: The Basics + Plugins (PART 1)" – https://www.youtube.com/watch?v=TrFiKIr7K-4
- [S9] YouTube "Roblox Particles/VFX Tutorial: Best Plugins (PART 2)" – https://www.youtube.com/watch?v=3vZBg-YnV-c
- [S10] DevForum: "Introducing the VFX Suite Plugin" – https://devforum.roblox.com/t/introducing-the-vfx-suite-plugin/2545686
- [S11] BezierSequence (laut Video-Beschreibung) – https://www.roblox.com/library/8133535339/BezierSequence
- [S12] DevForum: "Unable to mass edit sequence properties (ie from particles)" – https://devforum.roblox.com/t/unable-to-mass-edit-sequence-properties-ie-from-particles/2083516
- [S13] DevForum: "Particle Editing Bug On Multiple ParticleEmitters" – https://devforum.roblox.com/t/particle-editing-bug-on-multiple-particleemitters/23034
- [S14] DevForum: "Multiple NumberSequence/ColorSequence can't be edited through the Properties panel" – https://devforum.roblox.com/t/multiple-numbersequencecolorsequence-cant-be-edited-through-the-properties-panel/1071269
- [S15] DevForum: "Let us edit multiple sequence properties at a time" – https://devforum.roblox.com/t/let-us-edit-multiple-sequence-properties-at-a-time/425043
- [S16] DevForum: "Particle Size can't be animated above 10. Despite size limit being 200" – https://devforum.roblox.com/t/particle-size-cant-be-animated-above-10-despite-size-limit-being-200/26161
- [S17] DevForum: "Increase ParticleEmitter size limit" – https://devforum.roblox.com/t/increase-particleemitter-size-limit/79122
- [S18] DevForum: "SmoothSequence Graph" – https://devforum.roblox.com/t/smoothsequence-graph-the-easiest-way-to-edit-numbersequences/3044286
- [S19] DevForum-Profil roasted_shrimps – https://devforum.roblox.com/u/roasted_shrimps

**Offiziell (VERIFIED, per raw.githubusercontent.com geladen):**
- [D1] https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/particle-emitters.md
- [D2] https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/ParticleEmitter.yaml
- [D3] https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/NumberSequence.yaml
- [D4] https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/NumberSequenceKeypoint.yaml
- [D5] https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/WireframeHandleAdornment.yaml
- [D6] https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/studio/plugins.md
- Lokaler API-Dump Engine 0.745: `/root/tools/ref/Full-API-Dump.json`, `/root/tools/ref/API-Dump.json`
