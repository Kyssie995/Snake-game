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

---

## Verifikation (unabhängige Prüfung)

Stand: 2026-10-27 · Prüfer: Verifier-Subagent (skeptische Gegenprüfung). Vorgehen: Primärquellen **selbst neu geladen** (Plugin-README `main` und `master` – identisch; Runtime-README `main`/`master` – identisch; Runtime-`LICENSE.md`; creator-docs `creator-store.md`, `highlighting.md`, `particle-emitters.md`, `NumberSequence.yaml`, `ColorSequence.yaml`, `ParticleFlipbookLayout.yaml`, `AssetService.yaml`; lokaler `API-Dump.json` 0.745) und ca. 20 eigene WebSearch-Abfragen (standard + extended) zu Produkt-Features. Weder `.rbxm` noch Runtime-Quellcode wurden geöffnet. Im Plugin-Repo existieren unter `main` weder `LICENSE(.md)` noch `CHANGELOG.md` (HTTP 404).

Verdikte: **CONFIRMED** (durch Primärquelle bzw. unabhängige Zweitquelle bestätigt) · **PARTIAL** (Kern stimmt, Teilaussage falsch gelabelt/ungestützt/zu stark) · **REFUTED** (Gegenbeleg) · **UNVERIFIABLE** (weder Beleg noch Gegenbeleg).

### Kritische Claims

| ID | Verdikt | Evidenz | Korrektur / Ergänzung |
|---|---|---|---|
| C5 | CONFIRMED | `creator-store.md`, Abschnitt "Asset requirements": restringiert "Obscuring engine features" (LuaVMs, `getfenv`, `setfenv`), "Requiring remote assets" (`require(assetId)`, `loadstring`, `InsertService:LoadAsset`, `AssetService:LoadAssetAsync`, `ModuleScript.LinkedSource`), "Including obfuscated code" und zusätzlich "Extremely large scripts". | Docs formulieren "restricts use of the following practices" (nicht wörtlich "prohibits"). Liste um `AssetService:LoadAssetAsync`, `ModuleScript.LinkedSource` und "extremely large scripts" ergänzen. |
| C7 | CONFIRMED | Runtime-README, Abschnitt "What the module reads from your items": `PartIcleProperties` (Configuration) + `RenderTemplate`; Item-Attribute `Transformed=true`, `EmitCount`, `EmitDelay`, `EmitDuration`, `EmissionMode`, `AnimateLoop`; optional `Link`/`EmitParent` (ObjectValue), `ShapePart`, Ordner `MeshFlipbooks`, `BeamFlipbooks`, `GraphBlender`. | Präzisierung: Der `Events`-Ordner liegt **innerhalb** von `PartIcleProperties` (nicht am Item). README spricht von "60+ attributes" pro Part-Icle. |
| C8 | CONFIRMED | Runtime-README: "If a required piece is missing (most commonly `RenderTemplate`), the emit silently no-ops for that item rather than erroring." und "Older effects set up in earlier versions of the plugin need to be re-saved through the current plugin first." | "Keine Migration" gilt nur für die **Runtime**; das Neuspeichern im Plugin ist faktisch der Migrationspfad (README sagt nicht explizit "does not migrate"). Zweite stille Fehlerquelle unabhängig bestätigt (REPORTED, qp2-docs FAQ): ohne `:Activate()` und bei `Enabled=false` (Standard nach Transform) passiert ebenfalls nichts. |
| C10 | CONFIRMED | Plugin-README, Abschnitt "Nesting" (wörtlich: EmitDelay verschachtelter Klone wird automatisch gelöscht, "No wiring required; nesting is detected at emit time"). Unabhängig bestätigt durch Such-Snippet der Doku-Seite https://qp2-docs.pages.dev/guide/hidden-depths/nesting/ (REPORTED). | **Neue kritische Folge (REPORTED):** Laut Nesting-Doku wird der `EmitDelay` jedes verschachtelten Nachfahren beim Parent-Emit auf 0 gezwungen → **kein Staffeln zwischen Ebenen** möglich; die Doku empfiehlt stattdessen Skript-Aufrufe mit explizitem `task.wait`. Stützt C30 und die Timeline-Idee für ASTRA. |
| C11 | CONFIRMED | Runtime-README: `Events`-Ordner in `PartIcleProperties` mit OnEmit/OnHit/OnDeath/OnDestruction als Configuration-Kinder, die auf ein ModuleScript zeigen; Einrichtung über Events-Panel. Such-Snippet der Doku-Startseite (REPORTED): Events feuern, wenn ein Partikel erzeugt wird, eine Oberfläche trifft, endet oder entfernt wird. | Handler-Signatur (Argumente) ist öffentlich **nicht** dokumentiert – in keiner Suche gefunden. |
| C14 | CONFIRMED | `NumberSequence.yaml`: "with a maximum of 20 keypoints"; `ColorSequence.yaml`: "Must contain at least 2 and no more than 20 keypoints". | Ergänzung: Auch `NumberSequence.new(array)` verlangt **mindestens 2** Keypoints, erster bei Zeit 0, letzter bei Zeit 1, nicht absteigende Zeiten. ASTRA-Bake muss alle drei Regeln erzwingen. |
| C21 | CONFIRMED | Runtime-README: "The source is plaintext Lua" und Abschnitt "Keep the module up to date" ("frozen snapshot … changes don't reach this module until a new `.rbxm` is pushed"; manuell löschen + neu einfügen). | Kleine Inkonsistenz beim Hersteller: README verteilt `PartIclesModule.rbxm`, `LICENSE.md` spricht vom "compiled `.rbxmx` artifact". |
| C22 | CONFIRMED | Runtime-README "Full API"-Tabellen: `AbsoluteEmit(root) → number?` (Custom + native `ParticleEmitter`/`Trail`/`Beam`, `nil` für quasi unendlich), `AbsoluteEmitAt(root, originCF, options?)` (v39+), `AbsoluteEnable/Disable`, `AbsoluteSetTimescale(root, scale, duration?, permanent?)` (`0` friert, `<0` kehrt um), `Preload/Deload`, statisch `.await(n)`, `:Activate()` "once per server or client". | Hinweise: Beispielcode übergibt `hit.Position` (Vector3) an `AbsoluteEmitAt`, obwohl die Signatur `originCF` nennt (Typ-Unschärfe beim Hersteller). Die ältere Doku-Instanz (qp2-docs `/guide/from-script/emission/`, REPORTED) nennt bei `AbsoluteEmit` nur ParticleEmitter/Trail und kein `AbsoluteEmitAt`/Rückgabewert → Doku-Drift. Native Emitter ohne Attribute = 1 Burst (VERIFIED). |
| C23 | CONFIRMED (mit Label-Korrektur) | Runtime-README "Why it's fast": eine Heartbeat-Verbindung; Emit-Loops resümieren auf `RunService.PreRender` (auf dem Server `Heartbeat`); `TotalKeyFrames`-Schritte statt Per-Frame-Lerp; LIFO-Pool pro Quelle mit TTL-Sweep; vorallokierte `pData`-Tabellen + Swap-and-Pop. | "Default 100" steht **nicht** im README, sondern nur auf der Doku-Seite /reference/properties/particle/ – eigene Suche bestätigt "Anim. Steps" = `TotalKeyFrames`, Standard 100, für alle Typen außer Trail; Camera Shake: Wert ≤ 0 läuft als 100. Das ist **REPORTED**, nicht VERIFIED. Weitere REPORTED-Details: Pool-Leerlauf-TTL ca. 5 s; einzige harte Grenze ist eine "Particle Cap" (keine eigene Obergrenze für Rate/Lifetime). |
| C24 | CONFIRMED | Runtime-README: "The plugin's v39 release ships with `Pool` defaulting to false on newly-set-up Custom particles … pool reuse can surface subtle visual edge cases on Beams and Trails under specific configurations". | Präzisierung: gilt für **neu eingerichtete** Custom-Partikel ab v39; ob bestehende Partikel umgestellt wurden, ist nicht dokumentiert. |
| C25 | PARTIAL | Eigene Suche bestätigt (REPORTED, Doku-Seite /guide/hidden-depths/why-meshes-win/, "Last updated" 14.05.2026): pro lebendem Partikel ein Skript-Update; "no saving for distance or off-screen particles" ("A particle behind the camera is updated like any other"); Model-Partikel = ganzes Model; 3 s Lebenszeit bei 100 Steps ≈ 33 Updates/s. Part-Seite: Mesh teurer als Primitive/Block, für hohe Raten Primitive empfohlen. Model-Seite: Skalierung großer Models teuer (Beispiel 50 Nachfahren × 30 Duplikate ≈ 1.500 Property-Updates/Frame). | Das Zitat "the plugin doesn't warn" konnte ich **nicht unabhängig** finden (mehrere Suchen ohne Treffer) → nur Single-Source. Kein Benchmark mit Zahlen gefunden (konsistent mit dem Claim, aber Abwesenheit). Nuance: Die Seite trug früher den Titel "Why Mesh Particles Beat Native ParticleEmitter" (argumentiert u. a. mit Fill-Rate/Overdraw zugunsten von Meshes und verweist auf MicroProfiler), heute "What mesh particles give and what they cost"; laut Snippet sei der native ParticleEmitter für Tausende kleine Partikel besser. Außerdem: Schreibzugriffe nur bei Step-Wechsel (Idle-Frame-Einsparung). |
| C30 | PARTIAL (Absenz, nicht beweisbar) | Eigene Suchen ("timeline", "sequencer", "node graph/editor", Vergleich mit VFX Forge) liefern **keinen** Hinweis auf Timeline oder Node-Graph; ein Vergleichs-Snippet sagt explizit "no sign of a node graph or a timeline track". Indirekte Stütze: Nesting-Doku empfiehlt Staffelung per Skript mit `task.wait` (s. C10). | Bleibt ASSUMPTION. Der angekündigte "Workspace Manager" (X) ist inhaltlich unbekannt und könnte das ändern. "Keyframes" in QP2 bezeichnen nur Abtastschritte (`TotalKeyFrames`), keine Zeitachse. |
| C36 | PARTIAL (Prämisse teilweise falsch) | Empfehlung selbst ist schlüssig und durch C5 gedeckt. Prüfung der Vergleichsprämisse: (a) "obfusziert": genau **ein** Such-Snippet (ältere Install-Seite qp2-docs.pages.dev: nicht auf dem Creator Hub, weil obfusziert) – zwei weitere unabhängige Suchen fanden **keine** Quelle dazu; README sagt nur "decompilation … prohibited". (b) "GitHub-only": widerlegt durch die Creator-Store-Seite Asset 78969824830970 (26 Reviews, Publisher "QwinkleTee's Teashop"; Reviewer: besitzt es "before … uploaded to the store"). (c) "Discord whitelist DRM": nur der Robux-Weg nutzt Discord/Bloxlink; Ko-fi und Gumroad whitelisten automatisch über die Roblox-User-ID. | Formulierung ändern zu: "… statt eines (laut einer Doku-Quelle) obfuszierten Plugins, das primär über GitHub verteilt wird und per User-ID-Whitelist (teils via Discord-Bot) lizenziert ist". |

### Stichproben nicht-kritischer VERIFIED-Claims

| ID | Verdikt | Evidenz | Korrektur / Ergänzung |
|---|---|---|---|
| C1 | CONFIRMED | Plugin-README-Titel "Qwinkle's Part-Icles 2", Modell `Part_IclesV2`, Toolbar-Button "Qwinkle's Part-Icles 2"; Runtime-README "Author: Qwinkle (QwinkleTee on GitHub)". | Gumroad-Titel schreibt "Qwinkle's PartIcles 2" (dritte Schreibweise). |
| C2 | CONFIRMED (Gumroad-Teil REPORTED) | Plugin-README: 7-Tage-Trial, 8000 Robux (Gamepass 1779373735 + öffentliches Inventar + Bloxlink + `/whitelist`), 20 USD Ko-fi/PayPal mit User-ID im Message-Feld. Gumroad nur per Snippet: 20 USD, "Lifetime license — pay once, use forever", User-ID im Checkout, Whitelist "within seconds". | Gumroad wird im README **nicht** erwähnt; Gumroad-Aussagen sind REPORTED, nicht VERIFIED. Den in A4 genannten T-Shirt-Kaufweg konnte ich nicht bestätigen. |
| C3 | CONFIRMED | Plugin-README "Installation" und "Updates" (grüner Banner, neue Version in ServerStorage, erneut "Save as Local Plugin", Neustart). | Die aktuelle Doku-Install-Seite (REPORTED) beschreibt leicht abweichend: in einen Place einfügen, als Local Plugin speichern, danach aus dem Place löschen. |
| C6 | CONFIRMED | Plugin-README "Supported emitter types"; Runtime-README nennt zusätzlich Highlight sowie die Klassennamen BlurEffect/BloomEffect/ColorCorrectionEffect. | Formal ist `SpecialMesh` keine BasePart (Hersteller-Gruppierung). |
| C13 | CONFIRMED | Plugin-README "Graph Editor" – alle Einzelpunkte wörtlich vorhanden. | – |
| C16 | CONFIRMED | Plugin-README "Tools" und "Motion Preview". | **Inkonsistenz:** "Insert Module" legt die Runtime in **ServerScriptService** ab, das Runtime-README sagt "move it to `ReplicatedStorage`" (für Client-Emits nötig). Lehre für ASTRA: Runtime-Ablageort eindeutig festlegen (ReplicatedStorage) und im Plugin genauso einfügen. |
| C17 | CONFIRMED | Plugin-README "Link system"; Runtime-README "LinkService" (Weld/Follow/Pivot/WeldWithoutRotation, Auto-Anchor von `part1`, Wiederherstellung bei `:Clear`). | Ergänzung: `part1` ∈ {BasePart, Model, Attachment}; Ziel zusätzlich `Bone` oder `Camera`. |
| C18 | CONFIRMED | Plugin-README "Animate mode"; Runtime-API `EmitAnimate`. | – |
| C19 | CONFIRMED (9000+ REPORTED) | Plugin-README "Inventory" (7800+, Kategorien, Tabs, Upload, Beta-Features); Gumroad-Snippet unabhängig: "9000+ textures". | Exakter Name des zweiten Beta-Features laut README: "`EditableMesh / EditableImage Static Conversion API`". |
| C20 | CONFIRMED | `API-Dump.json` 0.745: `AssetService.CreateAssetAsync(object, assetType, requestParameters)`, Tags `Yields`, Capability `AssetCreateUpdate`; ebenso `CreateAssetVersionAsync`. | **Neu (VERIFIED, `AssetService.yaml`):** "Currently, this method can only be used in **locally loaded plugins** and uploads assets without prompting first"; `Enum.AssetType.Image` verlangt ein `EditableImage` als Objekt. |
| C26 | CONFIRMED | `highlighting.md`: max. 255 gleichzeitige Highlights clientseitig, weitere still ignoriert. | Ergänzung: auch **deaktivierte** Highlights belegen einen der 255 Slots → für Pooling relevant (Highlights zerstören statt deaktivieren). |
| C27 | CONFIRMED | `ParticleFlipbookLayout.yaml` (None/Grid2x2/Grid4x4/Grid8x8/Custom), `particle-emitters.md` (Low-Memory-Clients deaktivieren Flipbooks). | Ergänzung: `FlipbookFramerate` max. 30 FPS; `Lifetime` nativer Partikel intern auf **20 s** gekappt. |
| C28 | CONFIRMED | `LICENSE.md` (Use/Modify/Embed erlaubt; kein Redistribute/Resell/Repackage/Sublicense; Attribution für monetarisierte Spiele) und Plugin-README "License". | Attribution: "Qwinkle's Part-Icles" **oder** "Qwinkle's Part-Icles 2"; nicht-kommerziell freiwillig; Einbindung in kommerzielle Frameworks/OEM nur mit schriftlicher Erlaubnis. |

### Neu entdeckte Fakten (relevant für ASTRA)

1. **[kritisch, VERIFIED]** `AssetService:CreateAssetAsync` ist laut offizieller API-Doku derzeit **nur in lokal geladenen Plugins** nutzbar und lädt ohne Rückfrage hoch (https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AssetService.yaml). Ein über den Creator Store installiertes ASTRA könnte damit (Stand jetzt) keine Texturen hochladen → Upload-Feature nur mit Feature-Detection und klarer Fehlermeldung.
2. **[kritisch, REPORTED]** QP2-Nesting zwingt `EmitDelay` verschachtelter Emitter auf 0 → keine Staffelung zwischen Ebenen ohne Skript (`task.wait`). ASTRAs Timeline sollte Sub-Emitter-Offsets explizit erlauben (https://qp2-docs.pages.dev/guide/hidden-depths/nesting/).
3. **[kritisch, VERIFIED]** Hersteller-Inkonsistenz beim Runtime-Ablageort (Plugin "Insert Module" → ServerScriptService; Runtime-README → ReplicatedStorage). ASTRA muss den Ablageort der Runtime eindeutig vorgeben, damit Client-Emits funktionieren.
4. **[kritisch, VERIFIED]** Native ParticleEmitter-Grenzen für den Bake-Pfad: `Lifetime` ≤ 20 s (intern gekappt), `FlipbookFramerate` ≤ 30 FPS, Sequenzen 2–20 Keypoints mit Zeiten 0 und 1 (`particle-emitters.md`, `NumberSequence.yaml`, `ColorSequence.yaml`).
5. **[VERIFIED]** Deaktivierte Highlights belegen weiterhin einen der 255 Slots (`highlighting.md`) → Pooling von Highlight-Partikeln muss zerstören statt deaktivieren.
6. **[REPORTED]** Stille Fehlschläge sind ein durchgängiges Muster: fehlendes `:Activate()` in Live-Spielen, `Enabled=false` nach Transform, fehlendes `RenderTemplate`, Model ohne PrimaryPart, Beam ohne Attachments, moderierte/gelöschte Bild-Assets (qp2-docs FAQ "Emitter not emitting").
7. **[REPORTED]** Doku-Drift beim Hersteller ist erheblich (zwei Doku-Instanzen, umbenannte Seiten, abweichende API-Listen) → ASTRA sollte API-Doku aus dem Code/Schema generieren.

### Prüfquellen (zusätzlich zu Abschnitt 6)

- https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AssetService.yaml (VERIFIED)
- https://raw.githubusercontent.com/QwinkleTee/Qwinkles-Particles-2/master/README.md und …-Module/master/README.md (identisch mit `main`)
- https://qp2-docs.pages.dev/guide/hidden-depths/nesting/ (REPORTED, Snippet)
- https://qp2-docs.pages.dev/faq/emitter-not-emitting/ (REPORTED, Snippet)
- https://qp2-docs.pages.dev/guide/from-script/emission/ (REPORTED, Snippet)
- https://www.qwinkleparticles2.com/guide/hidden-depths/why-meshes-win/ , /guide/particiliary/part/ , /guide/particiliary/model/ , /reference/properties/particle/ (REPORTED, Snippets)
- https://qwinkletee.gumroad.com/l/qwinklesparticles2 (REPORTED, Snippet)
- https://create.roblox.com/store/asset/78969824830970/Qwinkles-Particles-2/reviews (REPORTED, Snippet)
- https://devforum.roblox.com/t/plugin-vfx-forge-an-advanced-custom-vfx-system/3867553 (REPORTED, Vergleichs-Snippet)
