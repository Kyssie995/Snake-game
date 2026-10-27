# Recherche: Qwinkle's Particles 2 ("Qwinkle's Part-Icles 2", "QP2")

Stand: 2026-10-27 · Phase-1-Recherche für ASTRA VFX STUDIO · Autor: Research-Subagent

Label-Legende: **VERIFIED** (Produktseite/README des Herstellers, offizielle Roblox-Docs, lokaler API-Dump 0.745) · **REPORTED** (Such-Snippets, Reviews, X-Posts, Drittseiten) · **ASSUMPTION** (eigene Schlussfolgerung) · **IDEA** (eigener Designvorschlag für ASTRA). Mit **[kritisch]** markierte Befunde beeinflussen ASTRA-Architekturentscheidungen direkt.

Methodik / Zugriff:
- Direkt gelesen (VERIFIED): `README.md` des Plugin-Release-Repos `QwinkleTee/Qwinkles-Particles-2` und `README.md` + `LICENSE.md` des Runtime-Repos `QwinkleTee/Qwinkles-Particles-2-Module` über raw.githubusercontent.com; Roblox creator-docs (Creator Store, Highlighting, Particle Emitters, NumberSequence/ColorSequence, ParticleFlipbookLayout); lokaler API-Dump.
- Nur über WebSearch-Snippets (REPORTED): die offizielle Doku-Website qwinkleparticles2.com (bzw. ältere Instanz qp2-docs.pages.dev), Gumroad-Seite, Creator-Store-Review-Seite, X-Posts des Autors, YouTube-Videos. Diese Seiten sind im Sandbox-Proxy blockiert; Inhalte stammen aus Such-Zusammenfassungen und sind entsprechend vorsichtig zu lesen.
- Die Plugin-Datei (`QwinklesParticles2.rbxm`) wurde bewusst **nicht** heruntergeladen oder inspiziert: Die Lizenz verbietet Decompilation/Reverse Engineering, und die ASTRA-Regeln verbieten das Übernehmen fremden Codes. Auch der (laut README lesbare) Runtime-Quellcode wurde nicht geöffnet; alle Aussagen zur Runtime stammen aus deren README.

---

## 1. Zusammenfassung

Qwinkle's Particles 2 (offizieller Schreibname im Repo: **"Qwinkle's Part-Icles 2"**, intern `Part_IclesV2`, Kürzel **QP2**) ist ein kommerzielles Roblox-Studio-Plugin des Entwicklers **Qwinkle / QwinkleTee** (Store-Name "QwinkleTee's Teashop"). Kernidee: **beliebige reguläre Instanzen** (BasePart/MeshPart, Model, Attachment, Beam, Trail, PointLight, Highlight, Post-Processing-Effekte, Atmosphere, ImageLabel) per "Transform" in **skriptgetriebene Custom-Emitter** verwandeln, deren Eigenschaften über die Partikel-Lebenszeit per **Graph-Editor** (Bezier/Linear, Envelope = Zufallsstreuung, Presets, RDP-Vereinfachung) animiert werden. Dazu kommen **Nesting** (Emitter in Emittern = Sub-Emitter), **Events** (OnEmit/OnHit/OnDeath/OnDestruction mit ModuleScript-Handlern), **Link-System** (Weld/Follow/Pivot, auch an die Kamera), **Animate-Mode** (In-place-Loop ohne Klone), ein **Inventory** mit großer Textur-/Flipbook-Bibliothek, Spritesheet-Zerlegung und Upload, Batch-Tools (Resize, Retime, Hue, Shifter, Clipboard, Scan), **Emit-Code-Generator** (auch für Moon Animator 2) sowie ein separat verteiltes **Runtime-ModuleScript** zum Abspielen im Live-Spiel.

Preis: **20 USD** (Gumroad / Ko-fi) oder **8000 Robux** (Gamepass), lebenslange Lizenz, **7-Tage-Trial**, Freischaltung per Whitelist an die Roblox-User-ID (teils über Discord/Bloxlink-Bot). Verteilung **über GitHub als .rbxm** (nicht bzw. nicht mehr regulär über den Creator Store), Plugin laut Doku **obfusziert**, Lizenz "All rights reserved". Eine Creator-Store-Seite mit 26 Reviews existiert (Asset 78969824830970), Reviews sind kurz und positiv ("gut für Einsteiger", "jetzt viel smoother"). Fundierte negative Nutzerkritik wurde **nicht gefunden**; die meisten Schwächen ergeben sich aus der Hersteller-Doku selbst (stille Fehlschläge, Performance-Kosten von Mesh-Partikeln, Attribut-Format ohne Migration, manuelles Update von Plugin und Runtime).

Eine **Timeline** (Mehrspur, Keyframes über die Effektzeit) oder ein **Node-Graph** wurden in keiner Quelle erwähnt; Zeitsteuerung erfolgt pro Item über `EmitDelay`/`EmitDuration`/`EmitCount` und Lebenszeit-Graphen. Ein **dateibasiertes/versioniertes Austauschformat** existiert nur in Form eines "Text Based AssetSharing" (Copy/Paste-Text); Details dazu sind nicht öffentlich. Hier liegen die klarsten Differenzierungschancen für ASTRA.

Version 1 ("Qwinkle's Part-Icles | A MeshFX and Utility Plugin") wurde am 2025-09-08 auf X angekündigt; zu ihren Features ließ sich **nichts Belastbares** finden.

---

## 2. Befunde

### 2.1 Identität, Autor, Distribution, Preis

| # | Befund | Label | Quelle |
|---|---|---|---|
| A1 | Offizieller Name im Repo: "Qwinkle's Part-Icles 2"; in Videos/X/Doku auch "Qwinkle's Particles 2" bzw. "QP2". Toolbar-Button heißt "Qwinkle's Part-Icles 2", das installierte Modell `Part_IclesV2`. | VERIFIED | https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2/main/README.md |
| A2 | Autor: Qwinkle, GitHub-Handle **QwinkleTee**; X-Account @qwinkletee; Support via Discord. | VERIFIED (README Runtime-Modul "Author") / REPORTED (X) | https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2-Module/main/README.md, https://x.com/qwinkletee |
| A3 | Preis: 7-Tage-Trial ab erstem Start; danach **8000 Robux** (Gamepass 1779373735 + öffentliches Inventar + Bloxlink-Verifizierung + `/whitelist` im Discord) **oder 20 USD** via Ko-fi/PayPal (Roblox-User-ID in der Nachricht angeben). | VERIFIED | Plugin-README (s. A1) |
| A4 | Gumroad-Seite: 20 USD, "Lifetime license — pay once, use forever", Roblox-User-ID im Checkout, Whitelist "within seconds". Gumroad-Text erwähnt zusätzlich einen Kaufweg über ein Roblox-T-Shirt (widerspricht README-Gamepass-Weg → aktueller Weg unklar). | REPORTED | https://qwinkletee.gumroad.com/l/qwinklesparticles2 |
| A5 | Distribution: `.rbxm` aus dem GitHub-Release-Repo → in ServerStorage einfügen → "Save as Local Plugin" → Studio-Neustart. Updates: Plugin lädt neue Version selbst in ServerStorage (grüner Banner), Nutzer muss erneut "Save as Local Plugin" + Neustart. | VERIFIED | Plugin-README |
| A6 | Doku-Seite (Install-Seite) sagt: nicht auf dem Creator Hub, weil Plugin obfusziert ausgeliefert wird und Roblox obfuszierte Plugins entfernt. (Snippet der älteren Instanz qp2-docs.pages.dev; dort zudem `.rbxmx`/"kein Neustart nötig" – widerspricht README.) | REPORTED | https://qp2-docs.pages.dev/setup/install/, https://www.qwinkleparticles2.com/setup/install/ |
| A7 | Roblox Creator Store untersagt in öffentlich geteilten Assets u. a. obfuszierten Code, `getfenv/setfenv`/LuaVMs und das Nachladen entfernter Assets (`require(assetId)`, `loadstring`, `InsertService:LoadAsset` …). **[kritisch]** | VERIFIED | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/production/creator-store.md |
| A8 | Es existiert trotzdem eine Creator-Store-Seite "Qwinkle's Particles 2" (Asset 78969824830970, Publisher "QwinkleTee's Teashop", 26 Reviews, "Not enough ratings"). Ein Reviewer schreibt, er besitze es "since release, before it was added to the plugins store". Preis/Status dort nicht ermittelbar. | REPORTED | https://create.roblox.com/store/asset/78969824830970/Qwinkles-Particles-2/reviews |
| A9 | Widerspruch A6 vs. A8: Ob die Store-Seite aktiv ist, ein Wrapper/Loader ist oder entfernt wurde, ist offen. | ASSUMPTION | – |
| A10 | Lizenz Plugin: "All rights reserved", Weitergabe, Decompilation, Reverse Engineering verboten. | VERIFIED | Plugin-README |
| A11 | Versionen: Runtime-README nennt "v39"-Features; Such-Snippet nennt Release-Ordner v41.1 bis v42.3 im Repo. Kein öffentlicher Changelog gefunden. | VERIFIED (v39) / REPORTED (v41–v42.3) | Runtime-README; https://github.com/QwinkleTee/Qwinkles-Particles-2 |
| A12 | Doku: qwinkleparticles2.com, als "Manual" mit **20 Übungen** ("Exercise 1: First emission" … "Exercise 17: Fire the explosion with a key"), "Particiliary" (Referenz pro Emittertyp), "Hidden Depths", Toolbench, FAQ, Property Reference; lokalisierte Seiten (es, zh) existieren. Offizielle YouTube-Videos "Basics — Official Tutorial" und "How to install". | REPORTED | https://www.qwinkleparticles2.com/, https://www.qwinkleparticles2.com/guide/exercises/01-first-emission/, https://www.youtube.com/watch?v=nAXbqUM1feo, https://www.youtube.com/watch?v=qxhShY5WJrw |

### 2.2 Emittertypen und Datenmodell

| # | Befund | Label | Quelle |
|---|---|---|---|
| B1 | Transformierbar: BaseParts (Part, MeshPart, SpecialMesh – emittieren echte 3D-Geometrie), Models (mit Scale über Lebenszeit), Attachments (parent-lokale CFrame, Nesting), Beams (mehrstufiger Transparency/Color-"Blender", Breite pro Segment), Trails, PointLights (Range/Brightness/Color animiert), Blur/Bloom/ColorCorrection/Atmosphere (Screen-Space, einmalig oder animiert), ImageLabels (2D-Partikel mit Spritesheet-Flipbook). | VERIFIED | Plugin-README |
| B2 | Runtime-README nennt zusätzlich **Highlight** als Custom-Particle-Typ; Doku hat eigene Seiten zu Highlight (Farbe/Transparenz über Lebenszeit, Adornee-Picker, keine eigene Bewegung), Camera Shake und "Trail emitter" (dupliziert vorhandenen Trail, Bewegung kommt von den Attachments). | VERIFIED (Highlight in Runtime-README) / REPORTED (Seiten) | Runtime-README; https://www.qwinkleparticles2.com/guide/particiliary/highlight/, https://www.qwinkleparticles2.com/guide/particiliary/trail-emitter/, https://www.qwinkleparticles2.com/es/guide/particiliary/camera-shake/ |
| B3 | **Datenmodell = Instanzbaum + Attribute.** Jedes transformierte Item bekommt ein `PartIcleProperties` (Configuration) mit allen Graph-/Range-Attributen (Lifetime, Rate, Color, Speed, Acceleration, Displacement, Timescale …) und ein `RenderTemplate`-Kind (die pro Partikel duplizierte Vorlage). Am Item selbst: `Transformed=true`, `EmitCount`, `EmitDelay`, `EmitDuration`, `EmissionMode`, `AnimateLoop`. Optional: `Link`/`EmitParent` (ObjectValue), `ShapePart`, Ordner `MeshFlipbooks`, `BeamFlipbooks`, `GraphBlender`, `Events`. **[kritisch]** | VERIFIED | Runtime-README |
| B4 | Fehlt ein Pflichtteil (meist `RenderTemplate`), wird der Emit für dieses Item **still ignoriert** (kein Fehler). **[kritisch]** | VERIFIED | Runtime-README |
| B5 | "V2 attribute format": Effekte aus älteren Plugin-Versionen müssen **im aktuellen Plugin neu gespeichert** werden, bevor das Modul sie liest – keine automatische Migration im Runtime. **[kritisch]** | VERIFIED | Runtime-README |
| B6 | Transform auf einem Part macht ihn unsichtbar (Transparency = 1), öffnet HUD und Properties-Panel, legt die Kinder an; RenderTemplate standardmäßig `Anchored=true`, `CanCollide=false`; Transform läuft durch Studios Undo-History. Bei Trails ist Transform praktisch nur ein Label (kein RenderTemplate, keine Configuration). | REPORTED | https://qp2-docs.pages.dev/guide/what-just-happened/, https://www.qwinkleparticles2.com/guide/particiliary/trail/ |
| B7 | Nach Transform ist `Enabled` standardmäßig **aus** – laut FAQ häufigste Ursache für "Emitter emittiert nicht". | REPORTED | https://www.qwinkleparticles2.com/faq/emitter-not-emitting/ |
| B8 | `EmissionMode`: Emit (Standard) oder Animate (Atmosphere: Standard Animate); Trail unterstützt es nicht. `TotalKeyFrames` ("Anim. Steps", Standard 100) = Abtastschritte pro Partikel-Lebenszeit. Part: `Shape` (Standard Box) bestimmt Spawn-Volumen, wirkt nur mit `UseShape`. | REPORTED | https://www.qwinkleparticles2.com/reference/properties/particle/ |
| B9 | "Über 70" animierbare Eigenschaften über alle Typen, u. a. Beam Width0/1, CurveSize0/1, Segments, TextureSpeed; Bloom Intensity/Size/Threshold; ColorCorrection Brightness/Contrast/Saturation/TintColor; Atmosphere Density/Offset/Glare/Haze/Color/Decay; ImageLabel-Größen/Rotation; Model-Scale; Part-Brightness. | VERIFIED | Plugin-README |

### 2.3 Nesting, Events, Link, Animate

| # | Befund | Label | Quelle |
|---|---|---|---|
| C1 | **Nesting**: Jedes transformierte Item kann in einem anderen liegen; der emittierte Klon trägt die verschachtelten Emitter mit und jeder durchläuft seinen eigenen Lebenszyklus (z. B. Beam in Part = Mesh mit Beam-Schweif; Attachment mit ParticleEmitters in Model). `EmitDelay` verschachtelter Klone wird automatisch genullt; Erkennung zur Emit-Zeit, keine Verdrahtung nötig. **[kritisch]** | VERIFIED | Plugin-README |
| C2 | **Events**: Ordner `Events` in `PartIcleProperties` mit Handlern **OnEmit, OnHit, OnDeath, OnDestruction** als Configuration-Kinder, die je auf ein ModuleScript zeigen; Einrichtung über ein Events-Panel. **[kritisch]** | VERIFIED | Runtime-README |
| C3 | OnHit: Raycast von der vorherigen zur aktuellen Partikelposition gegen die Welt; Reaktion entfernen/stoppen/abprallen. Event-Skripte werden einmal geladen und gecacht; **max. 256 Events pro Frame**. Bloom/Camera Shake haben kein OnHit. | REPORTED | https://www.qwinkleparticles2.com/es/guide/particiliary/bloom/, https://www.qwinkleparticles2.com/reference/properties/particle/ |
| C4 | **Link-System**: Modi Weld (volle CFrame jedes Frame), Follow (nur Position), Pivot (Rotation beim Spawn eingebacken); Runtime kennt zusätzlich WeldWithoutRotation. LinkSource kann die Workspace-Kamera (Cutscenes, HUD) oder ein beliebiges Objekt sein; `LinkService` auch standalone nutzbar (verankert `part1` automatisch und stellt Anchored wieder her). | VERIFIED | Plugin-README, Runtime-README |
| C5 | **Animate-Mode**: nicht-destruktives Looping (Orbits, Pulse, Motion Graphics) am Quell-Item selbst, ohne Klone; Item bleibt während des Abspielens editierbar; Loop pro Instanz umschaltbar. Nicht für Trail-Emitter. | VERIFIED (README) / REPORTED (Trail-Ausnahme) | Plugin-README; https://www.qwinkleparticles2.com/guide/particiliary/model/ |

### 2.4 Graph-Editor und Werkzeuge

| # | Befund | Label | Quelle |
|---|---|---|---|
| D1 | Graph-Editor: Bezier und Linear im selben Graphen, Handles pro Keypoint an/aus; **Envelope** pro Partikel (Zufallsstreuung um die Kurve) in beiden Modi; **20 Presets** (Linear, Ramp Down, Bell, Step, Bounce + 13 Easing-Kurven wie Sine/Quad/Cubic/Expo In/Out/InOut, Smooth); **Simplify-Panel** mit Ramer-Douglas-Peucker-Schieberegler und Auto-Minimize (kleinste Keypoint-Anzahl innerhalb 5 % Abweichung); 50-Schritt-Undo/Redo; Copy/Paste von Graphen zwischen Properties mit automatischer Skalierung auf den Zielbereich; "Env +" (Skalar auf alle Envelopes); Box-Multiselect, Ghost-Preview vor dem Einfügen, Tastatur-Nudging (Shift grob/fein). | VERIFIED | Plugin-README |
| D2 | **Native Editing**: Nicht transformierte Standard-ParticleEmitter/Trail/Beam lassen sich im gleichen Panel mit Graph-Editor, ColorSequence-Editor, Presets, Envelope, Simplify bearbeiten (kuratierte Teilmenge der Properties, schreibt direkt z. B. `Trail.Color`, `Trail.WidthScale`). Empfehlung der Doku: einfache flache Sprites nativ lassen, für Mesh-Partikel, 3-Achsen-Size/Rotation, Animate, Link transformieren. | REPORTED | https://www.qwinkleparticles2.com/guide/hidden-depths/native-editing/ |
| D3 | Native `NumberSequence` erlaubt max. **20 Keypoints**, `ColorSequence` 2–20 Keypoints – erklärt den Nutzen von Simplify/Auto-Minimize beim Schreiben auf native Emitter. **[kritisch]** | VERIFIED | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/NumberSequence.yaml, …/ColorSequence.yaml |
| D4 | Q-Menu-Tools: **Resize** (0,5×–2×, optional Spawn-Volumen und Nachfahren), **Retime** (Dauer strecken/stauchen inkl. Envelope), **Hue** (HSV-Shift auf ColorSequences inkl. Beam-Blender), **Clipboard** (Werte zwischen Items kopieren, mit Typfilter), **Shifter** (Bulk-Arithmetik + − × ÷), **Scan** (strukturelle Fehler finden/beheben), **Insert Module** (Runtime nach ServerScriptService), **Emit Code** (fertige Lua-Snippets für **Moon Animator 2** und In-Game-Skripte). | VERIFIED | Plugin-README |
| D5 | **Motion Preview**: Live-3D-Trajektorien von **20 Envelope-Varianten** auf Basis der echten Emit-Simulation, aktualisiert beim Editieren. | VERIFIED | Plugin-README |
| D6 | **Theme-Editor**: 10 Presets (u. a. Dracula, Nord), 6 Farbslots, 60+ Fonts, Panel-/Blob-Opazität, Fontskala 50–200 %, Import/Export als JSON. | VERIFIED | Plugin-README |
| D7 | X-Posts des Autors: "Flipbook Dissector" (Batch-Zerlegung von Spritesheets/rbxassetids, beliebige Grids), "Text Based AssetSharing" (VFX, Decal-Flipbooks, Meshes, Animationen, Models per Copy/Paste teilen), "Workspace Manager" (angekündigt, ohne Details). | REPORTED | https://x.com/qwinkletee/status/2040458438451634513, https://x.com/qwinkletee/status/2040781351528570958, https://x.com/qwinkletee |

### 2.5 Inventory / Texturen / Flipbooks

| # | Befund | Label | Quelle |
|---|---|---|---|
| E1 | Remote-Bibliothek: **7800+ Texturen** (README) bzw. **9000+** (Gumroad) in Kategorien (Shapes, Combat, Elements, Radiance, Misc, Other), Live-Suche über Name/ID/Keywords, Tabs All/Static/Flipbook/Favourites/Recent (letzte 20). | VERIFIED (7800+) / REPORTED (9000+) | Plugin-README; Gumroad |
| E2 | Lokales Inventory: PNG-Upload direkt aus Studio (File-Picker), Spritesheets als Assets, automatisches Hochladen ins Roblox-Konto, Persistenz in Plugin-Settings + ServerStorage-Backup. Voraussetzung: Studio-Beta-Features `CreateAssetAsync` und "EditableMesh / EditableImage Static Conversion API". | VERIFIED | Plugin-README |
| E3 | `AssetService:CreateAssetAsync` existiert im API-Dump 0.745 (Yields, Capability `AssetCreateUpdate`). | VERIFIED | /root/tools/ref/API-Dump.json |
| E4 | MeshFlipbook-Bibliothek: 50+ vorgefertigte Flipbook-Sequenzen, 24-FPS-Vorschau, One-Click-Insert. Spritesheet-Dissection (Spalten/Zeilen wählen → Einzelframes; Batch-Modus); Runtime erkennt native Sheet-Dimensionen zur Laufzeit. | VERIFIED | Plugin-README |
| E5 | Inventory-Eigenheiten laut Doku: nur quadratische Grids (≥2) erlaubt, ungültige Eingabe wird **ohne Meldung** zurückgesetzt; Löschen eines Eintrags lässt das Bild im Roblox-Konto; Insert kann Erfolg melden, obwohl nichts Passendes selektiert war. Inventory-Panel mit Größenregler 0,30×–1,50×, Details-Panel rechts/links. | REPORTED | https://www.qwinkleparticles2.com/guide/toolbench/inventory/ |
| E6 | Native ParticleEmitter-Flipbooks: Layouts None/Grid2x2/Grid4x4/Grid8x8/Custom; Clients mit wenig Speicher **deaktivieren Flipbooks automatisch**. | VERIFIED | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/particle-emitters.md, …/enums/ParticleFlipbookLayout.yaml |

### 2.6 UI-Layout und Workflow

| # | Befund | Label | Quelle |
|---|---|---|---|
| F1 | Workflow: ein Partikel als gewöhnliche Roblox-Instanz bauen → **Transform** → Properties/Graphen einstellen → Emit-Button / Motion Preview → Effekt als Model/Folder speichern → im Spiel per Runtime `AbsoluteEmit(root)`. | VERIFIED (Runtime-README) / REPORTED (Doku "Build one particle as an ordinary Roblox instance. Transform it.") | Runtime-README; https://www.qwinkleparticles2.com/guide/hidden-depths/why-meshes-win/ |
| F2 | Layout: Toolbar mit einem Toggle-Button; bei selektiertem Emitter **HUD oben links** und **Properties-Panel oben rechts**; **≡-Menü unten rechts** im Viewport; **Partikelzähler unten links**. Properties-Sektionen (z. B. Decals, Flipbook) einklappbar. | REPORTED | https://www.qwinkleparticles2.com/guide/exercises/01-first-emission/, https://www.qwinkleparticles2.com/setup/install/ |
| F3 | Das im Viewport verankerte Layout deutet auf eigene Overlay-GUIs statt Studio-DockWidgets hin (eigenes Theme-System statt Studio-Theme). | ASSUMPTION | abgeleitet aus F2/D6 |
| F4 | In Studio aktiviert sich die Engine automatisch; im veröffentlichten Spiel muss `:Activate()` einmal pro Maschine aufgerufen werden, sonst bleiben Emits **ohne Fehlermeldung wirkungslos**. | REPORTED | https://www.qwinkleparticles2.com/faq/emitter-not-emitting/, https://www.qwinkleparticles2.com/guide/exercises/17-fire-the-explosion-with-a-key/ |
| F5 | Keine Mehrspur-**Timeline** und kein **Node-Graph** in irgendeiner gefundenen Quelle; Zeitsteuerung über EmitDelay/EmitDuration/EmitCount pro Item + Lebenszeit-Graphen + Retime-Tool. **[kritisch]** | ASSUMPTION (Abwesenheit in allen Quellen; nicht beweisbar) | – |

### 2.7 Runtime-Modul (Live-Spiel)

| # | Befund | Label | Quelle |
|---|---|---|---|
| G1 | Separates Repo `Qwinkles-Particles-2-Module`, `PartIclesModule.rbxm` → ModuleScript `Part_Icles` in ReplicatedStorage. Quelltext laut README **Klartext-Lua** (lesbar, für eigenes Spiel forkbar, nicht weiterverteilbar). **Eingefrorener Snapshot**: Plugin-Updates erreichen das Modul erst mit neuem Release; Aktualisierung manuell (löschen + neu einfügen), API "stabil". **[kritisch]** | VERIFIED | Runtime-README |
| G2 | API (rekursiv): `AbsoluteEmit(root) → number?` (feuert alle Custom- **und** nativen ParticleEmitter/Trail/Beam im Baum, liefert Gesamtdauer in Sekunden, `nil` = quasi unendlich), `AbsoluteEmitAt(root, originCF, options?)` (Origin-Override; native Emitter werden geklont/verschoben/zerstört), `AbsoluteEnable/Disable`, `AbsoluteSetTimescale(root, scale, duration?, permanent?)` (0 = einfrieren, <0 = rückwärts), `AbsoluteClearTimescale`. Einzel-API: `Emit`, `EmitAnimate`, `Enable`, `Disable`, `EnableEmit`, `EnableEmitAt`, `SetTimescale`, `ClearTimescale`. Engine: `Activate`, `Deactivate`, `Preload/Deload` (Texturen pinnen gegen First-Emit-Stutter), `GetFolder` (Live-Klone unter `workspace.Terrain`), `GetPoolFolder`, statisch `.await(n)`, `.LinkService`. Native Emitter ohne Attribute: Default 1 Burst. **[kritisch]** | VERIFIED | Runtime-README |
| G3 | Performance-Konzept laut Hersteller: **eine** Heartbeat-Verbindung für alle Partikel; Emit-Loops resümieren auf `PreRender` (Client) für korrekte Trail-Erstsamples; **diskrete Animationsschritte** (`TotalKeyFrames`) statt Per-Frame-Lerp; **Clone-Pooling** (LIFO pro Quelle, TTL-Sweep); "zero-allocation inner loop" mit vorallokierten Tabellen und Swap-and-Pop. **[kritisch]** | VERIFIED (Herstelleraussage) | Runtime-README |
| G4 | Pooling ist seit v39 **standardmäßig aus**, weil Wiederverwendung "subtile visuelle Randfälle bei Beams und Trails" erzeugen kann. **[kritisch]** | VERIFIED | Runtime-README |
| G5 | Doku zu Kosten: jedes Mesh-Partikel ist eine volle Instanz (Model = viele Parts), jedes lebende Partikel bekommt pro Schritt ein Skript-Update, **keine Einsparung für Distanz/Offscreen**; MeshPart-Emitter teurer als Block-Parts; Model-Scaling auf großen Models teuer – "the plugin doesn't warn, and your frame rate will". Ein Partikel mit 3 s Lebenszeit bei 100 Steps wird ~33×/s aktualisiert. **Kein veröffentlichter Benchmark** gegen den nativen ParticleEmitter. **[kritisch]** | REPORTED | https://www.qwinkleparticles2.com/guide/hidden-depths/why-meshes-win/, https://www.qwinkleparticles2.com/guide/particiliary/part/, https://www.qwinkleparticles2.com/guide/particiliary/model/ |
| G6 | Runtime-Lizenz: Nutzung/Modifikation/Einbettung in eigene Spiele erlaubt; keine Weitergabe/Resale/Repackaging/Sublizenz; **kommerzielle Spiele müssen sichtbar "Qwinkle's Part-Icles (2)" attribuieren** (Credits, Beschreibung oder In-Game-Label). | VERIFIED | https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2-Module/main/LICENSE.md |
| G7 | Highlight-Limit: Client zeigt max. **255 gleichzeitige Highlights**, weitere werden still ignoriert – relevant für Highlight-"Partikel". | VERIFIED | https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/highlighting.md |

### 2.8 Nutzerfeedback und Marktposition

| # | Befund | Label | Quelle |
|---|---|---|---|
| H1 | Creator-Store-Reviews (26): kurz, positiv; "für Einsteiger in VFX empfehlenswert", "awesome", "now a lot smoother". Keine konkreten Bug-/Lag-/Preiskritiken in den sichtbaren Snippets. | REPORTED | https://create.roblox.com/store/asset/78969824830970/Qwinkles-Particles-2/reviews |
| H2 | Drittanbieter-Tutorial (doublecats auf X: "Make Trail Effects with Qwinkle's Particles 2", "another super useful plugin"). | REPORTED | https://x.com/doublecats1/status/2052351771587313711 |
| H3 | DevForum: kein eigener QP2-Thread gefunden; Konkurrent **Sine VFX** nennt sich "inspired by vfx forge & qp2" (Emit-Fenster für beliebige VFX-Instanzen, Runtime-Modul, ~5 USD). | REPORTED | https://devforum.roblox.com/t/plugin-sine-vfx-a-vfx-plugin-for-roblox-studio/4803771 |
| H4 | Autor-Pinned-Post: Plugin "heavily optimized and usable in game"; am 11. Mai seit ~2 Monaten öffentlich (Jahr nicht sichtbar). | REPORTED | https://x.com/qwinkletee |
| H5 | Version 1: X-Post vom 2025-09-08 "Introducing Qwinkle's Part-Icles | A MeshFX and Utility Plugin" mit Store-Link und Discord. Feature-Unterschiede v1→v2 **nicht auffindbar**; belegt ist nur, dass V2 ein neues Attributformat nutzt (B5). | REPORTED | https://x.com/qwinkletee/status/1965100364157636654 |
| H6 | Feature-Requests/Bugs laufen über Discord (und laut FAQ GitHub-Issues); öffentlich einsehbare Request-Listen wurden nicht gefunden. | VERIFIED (Discord im README) / REPORTED (FAQ) | Plugin-README; FAQ-Link oben |

---

## 3. Einschränkungen / Kritik

1. **Stille Fehlschläge als Muster** (VERIFIED/REPORTED): fehlendes `RenderTemplate` → No-op; fehlendes `:Activate()` → No-op; `Enabled` nach Transform aus; ungültiges Grid wird ohne Meldung zurückgesetzt; Insert meldet ggf. falschen Erfolg. Für Einsteiger ist das die wahrscheinlichste Frustquelle (die FAQ-Seite "Emitter not emitting" existiert genau dafür).
2. **Datenmodell = Instanz-Attribute** (VERIFIED): Effektzustand ist über 60+ Attribute, Configuration-Kinder und ObjectValues im DataModel verteilt. Folgen: schwer diffbar, schwer per Skript/KI zu erzeugen, keine Schema-Validierung, Formatwechsel (V2) erfordert manuelles Neuspeichern (keine Migration).
3. **Kein Timeline-/Sequencer-Konzept** (ASSUMPTION, F5): Komplexe Sequenzen (Charge → Release → Impact) werden über Delays/Durations und Nesting gebaut; Emit-Code für Moon Animator 2 deutet darauf hin, dass Sequenzierung an externe Tools delegiert wird.
4. **Performance-Kosten der Mesh-Partikel** (REPORTED vom Hersteller selbst): jede Partikel-Instanz ist eine echte Instanz mit Skript-Update, kein Distanz-/Offscreen-Culling, keine Warnung im Plugin; kein Benchmark veröffentlicht. "Heavily optimized" ist eine Herstelleraussage.
5. **Pooling-Randfälle** (VERIFIED): Pool standardmäßig aus wegen Beam/Trail-Artefakten → Durchsatz-Feature, das Nutzer manuell aktivieren und selbst testen müssen.
6. **Distribution/Vertrauen** (VERIFIED/REPORTED): obfusziertes Plugin, außerhalb des Creator Store (der obfuszierten Code verbietet), Whitelist/DRM über Discord-Bot oder Zahlungsnachricht, Update = Neuspeichern als Local Plugin + Neustart. Runtime separat, eingefroren, manuelle Updates, Attributionspflicht in kommerziellen Spielen.
7. **Proprietäre Bibliothek**: Der große Texturbestand (7800+/9000+, Zahl widersprüchlich) ist an das Plugin gebunden; Herkunft/Lizenz der Texturen ist öffentlich nicht dokumentiert (ASSUMPTION: Risiko für Nutzer bei Rechtefragen).
8. **Beta-Abhängigkeit**: Lokaler Upload benötigt Studio-Beta-Features (`CreateAssetAsync`, EditableImage Static Conversion) – kann sich mit Engine-Updates ändern.
9. **Doku-Drift** (REPORTED): ältere Doku-Instanz widerspricht README (.rbxmx vs. .rbxm, Neustart nötig vs. nicht), README vs. Gumroad (7800+ vs. 9000+ Texturen; Gamepass vs. T-Shirt).
10. **Wenig unabhängige Bewertung**: Nur 26 kurze Store-Reviews, kein DevForum-Thread, keine kritischen Reviews auffindbar – die Aussagekraft des positiven Feedbacks ist begrenzt.

---

## 4. Konsequenzen für ASTRA

1. **IDEA – Format statt Attribute-Soup [kritisch]:** ASTRA speichert die Effekt-Quelle als **versioniertes JSON** (`formatVersion`, Schema, explizite Migrationsfunktionen `vN → vN+1`). Der Instanzbaum in Studio ist ein *kompiliertes* Artefakt bzw. eine Vorschau. Runtime prüft `formatVersion` und migriert oder meldet klar – nie stille No-ops (Lehre aus B4/B5).
2. **IDEA – Laute Validierung [kritisch]:** Jede Ladung/jedes Play validiert (fehlende Texturen, fehlende Templates, unbekannte Felder, `Activate` vergessen) und meldet per `warn` mit Pfad + Ursache; in Studio zusätzlich ein Problems-Panel. Ein `Scan`-artiges Tool wird damit überflüssig, weil Fehler gar nicht erst unsichtbar entstehen.
3. **IDEA – Timeline + Node-Graph als Differenzierer [kritisch]:** QP2 hat (soweit belegbar) weder Timeline noch Node-Graph. ASTRA: Mehrspur-Timeline (Emitter-Spuren, Property-Keyframes über Effektzeit, Events), Node-Graph für Logik (OnSpawn/OnHit/OnDeath → Sub-Emitter, Kamera-Shake, Licht). Nesting/Sub-Emitter (C1) und Events (C2/C3) sind die Feature-Messlatte, die ASTRA abdecken muss – aber als **explizite, sichtbare** Verbindungen statt implizitem Hierarchie-Nesting.
4. **IDEA – Runtime-API [kritisch]:** Ähnliche Ergonomie wie `AbsoluteEmit(root)` (ein Aufruf für einen ganzen Effekt inkl. nativer Emitter), aber mit **Handle-Objekt**: `Astra.play(effect, {origin=CFrame, link=..., timescale=...}) → handle` mit `handle.Duration`, `handle.Completed` (Signal), `handle:Stop()`, `handle:SetTimescale()`. Origin-Override (G2) und Timescale inkl. Freeze sind Pflicht; Reverse optional.
5. **IDEA – Runtime-Performance [kritisch]:** Allgemein bekannte Engine-Muster übernehmen (eigene Implementierung, kein Code-Transfer): ein zentraler Update-Loop, quantisierte/vorab gesampelte Kurven-LUTs, Pooling mit **expliziten Reset-Routinen pro Instanztyp** (Beam/Trail-Zustand vollständig zurücksetzen – G4 zeigt die Falle), vorallokierte Arrays mit Swap-and-Pop, Preload von Texturen. Zusätzlich, was QP2 laut Doku fehlt: **Distanz-/Frustum-Culling und LOD** für Mesh-Partikel, globale Budgets (max. Mesh-Partikel/Highlights pro Client).
6. **IDEA – Performance-Analyzer mit Vorwarnung [kritisch]:** QP2 "warnt nicht" (G5). ASTRA-Analyzer schätzt vor dem Abspielen: Peak-Instanzen, Mesh-Partikel × Parts pro Model, Updates/s (Lebenszeit × Steps), Anzahl gleichzeitiger Highlights vs. 255-Limit (G7), Flipbook-Speicher (E6: Flipbooks werden auf Low-Memory-Clients deaktiviert), Post-Processing-Effekte. Ampel + konkrete Optimierungsvorschläge.
7. **IDEA – Kurveneditor [kritisch]:** Bezier/Linear-Mix, Envelope, Presets, Copy/Paste mit Bereichs-Skalierung und automatische Reduktion sind Standard-Erwartung (D1). Beim Backen auf native `NumberSequence`/`ColorSequence` muss ASTRA **automatisch auf ≤20 Keypoints** reduzieren (D3) und den Fehler anzeigen; Custom-Emitter dürfen höher aufgelöste Kurven nutzen.
8. **IDEA – Native-first-Hybrid:** QP2 zeigt, dass Nutzer native ParticleEmitter/Beam/Trail **ohne Umbau** bearbeiten wollen (D2). ASTRA sollte native Instanzen als erstklassige Komponenten im JSON abbilden (Import vorhandener Effekte → JSON) und Custom-/Mesh-Partikel nur dort einsetzen, wo native nicht reichen.
9. **IDEA – Distribution & Vertrauen [kritisch]:** Kein obfuszierter Code, kein Remote-`require`/`loadstring`, Runtime-Modul lesbar und mit klarer, attributionsarmer Lizenz (Entscheidung beim Nutzer) → Creator-Store-konform (A7). Updates über den Store statt "Save as Local Plugin + Neustart". Runtime-Version und Plugin-Version koppeln (Runtime meldet "Effekt braucht Runtime ≥ x.y").
10. **IDEA – KI-/Datei-Workflow als Alleinstellung:** QP2s "Text Based AssetSharing" (D7) belegt Bedarf an textuellem Austausch. ASTRA geht weiter: dokumentiertes JSON-Schema, CLI-Validierung, Claude-Code-generierbare Presets, Diffs in Git.
11. **IDEA – Bulk-Tools als Befehle:** Resize/Retime/Hue/Shifter (D4) als deterministische Commands, die sowohl im UI als auch über CLI/JSON-Transform (für Claude) laufen, mit Undo über `ChangeHistoryService`.
12. **IDEA – Motion Preview:** Deterministische, geseedete Simulation erlaubt Trajektorien-Vorschau mehrerer Zufallsvarianten (vgl. D5) *und* headless Tests/Analyse außerhalb von Studio.
13. **IDEA – Studio-native UI:** DockWidgetPluginGui + Studio-Theme-Sync statt eigener Overlay-UI/Themes; Theme-Editor ist nettes Extra, keine Priorität.
14. **IDEA – Assets:** Keine fremde Texturbibliothek bündeln; ASTRA referenziert Asset-IDs im JSON, bietet optional eigene, rechtlich saubere Starter-Texturen und eine Spritesheet-Konfiguration (Grid/Frames/FPS) statt Zerlegung in Einzelbilder als Standard. `CreateAssetAsync`-Upload nur als optionales Feature hinter Feature-Detection (Beta-Abhängigkeit, E2/E3).
15. **IDEA – Onboarding:** Übungsbasierte Doku (20 Exercises) ist ein starkes Muster; ASTRA kann geführte Tutorials mit Presets kombinieren, die sich als JSON öffnen und verändern lassen.

---

## 5. Offene Fragen

1. Ist die Creator-Store-Seite (Asset 78969824830970) aktiv, ein Loader, oder entfernt? Welcher Preis dort? (Seite im Sandbox nicht abrufbar.)
2. Funktionsumfang von Version 1 ("Part-Icles | A MeshFX and Utility Plugin") und konkrete Unterschiede zu V2 – nicht gefunden.
3. Format des "Text Based AssetSharing" (eigener Serialisierer? Base64? JSON?) – nicht öffentlich.
4. Gibt es tatsächlich keine Timeline/Sequencer-Ansicht (z. B. im angekündigten "Workspace Manager")? Bestätigung nur über Videos/Discord möglich.
5. Wie verhält sich die Runtime bei Client/Server-Replikation (wer klont, wo laufen Events)? Runtime-README sagt nur "Activate einmal pro Server oder Client".
6. Herkunft/Lizenzlage der 7800+/9000+ Bibliothekstexturen.
7. Echte Performance-Zahlen (Mesh-Partikel vs. nativer ParticleEmitter) – laut Doku existiert kein Benchmark; ASTRA sollte eigene Messungen planen.
8. Benötigt die Lizenzprüfung HttpService/Netzwerkzugriff in Studio (ASSUMPTION: ja, wegen Whitelist und Auto-Update)?

---

## 6. Quellen

Direkt gelesen (VERIFIED):
- https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2/main/README.md (Plugin-README; identisch auf `master`)
- https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2-Module/main/README.md (Runtime-README)
- https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2-Module/main/LICENSE.md (Runtime-Lizenz)
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/production/creator-store.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/highlighting.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/effects/particle-emitters.md
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/NumberSequence.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/ColorSequence.yaml
- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/ParticleFlipbookLayout.yaml
- Lokal: /root/tools/ref/API-Dump.json, /root/tools/ref/Full-API-Dump.json (Engine 0.745.0.7451137)

Nur über Such-Snippets (REPORTED):
- https://www.qwinkleparticles2.com/ (Doku-Startseite) und Unterseiten: /setup/install/, /guide/exercises/01-first-emission/, /guide/exercises/17-fire-the-explosion-with-a-key/, /guide/hidden-depths/native-editing/, /guide/hidden-depths/why-meshes-win/, /guide/particiliary/part/, /guide/particiliary/model/, /guide/particiliary/trail/, /guide/particiliary/trail-emitter/, /guide/particiliary/highlight/, /guide/particiliary/image-label/, /guide/particiliary/blur/, /guide/toolbench/inventory/, /reference/properties/particle/, /faq/emitter-not-emitting/, /es/guide/particiliary/bloom/, /es/guide/particiliary/camera-shake/
- https://qp2-docs.pages.dev/ , https://qp2-docs.pages.dev/setup/install/ , https://qp2-docs.pages.dev/guide/what-just-happened/ (ältere Doku-Instanz)
- https://qwinkletee.gumroad.com/l/qwinklesparticles2
- https://create.roblox.com/store/asset/78969824830970/Qwinkles-Particles-2/reviews
- https://github.com/QwinkleTee/Qwinkles-Particles-2 , https://github.com/QwinkleTee
- https://x.com/qwinkletee , https://x.com/qwinkletee/status/1965100364157636654 , https://x.com/qwinkletee/status/2040458438451634513 , https://x.com/qwinkletee/status/2040781351528570958
- https://x.com/doublecats1/status/2052351771587313711
- https://www.youtube.com/watch?v=nAXbqUM1feo , https://www.youtube.com/watch?v=qxhShY5WJrw
- https://devforum.roblox.com/t/plugin-sine-vfx-a-vfx-plugin-for-roblox-studio/4803771
