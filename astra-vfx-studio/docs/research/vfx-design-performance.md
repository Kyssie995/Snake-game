# Recherche: VFX-Design-Handwerk (A) und Roblox-VFX-Performance & Networking (B)

Stand: 2026-10-27 · Phase-1-Recherche für ASTRA VFX STUDIO · Engine-Stand der lokalen Daten: **0.745.0.7451137**

Label-Legende: **VERIFIED** (offizielle creator-docs, lokaler API-Dump 0.745 bzw. luau-lsp-Typen) · **REPORTED**
(DevForum-Posts, Drittseiten, Fachartikel, Such-Snippets) · **ASSUMPTION** (eigene Schlussfolgerung) · **IDEA**
(eigener Designvorschlag für ASTRA). Befunde mit **[kritisch]** bestimmen direkt eine ASTRA-Entscheidung
(Performance-Analyzer, Qualitätsprofile, Runtime, Net-Schicht, Builder, Presets).

Methodik / Zugriff:
- Offizielle Doku über `raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/...` gelesen (VERIFIED):
  Performance-Optimierung (`improve`, `design`, `identify`, `test-on-hardware`, `scene-analysis`, MicroProfiler
  inkl. `tag-table`), `effects/*`, `workspace/streaming/{index,techniques}`, `scripting/events/remote`, Klassen-YAMLs
  (`Stats`, `UserGameSettings`, `DataModel`, `RenderSettings`, `UnreliableRemoteEvent`, `RemoteEvent`, `WorldRoot`,
  `SceneAnalysisService`, `Debris`, `ContentProvider`, `BloomEffect`, `RunService`, `ParticleEmitter`, `Beam`,
  `BasePart`, `Light`), Enums (`SavedQualitySetting`, `BulkMoveMode`, `StepFrequency`, `GraphicsOptimizationMode`),
  offizielle Tutorials (Explosion-Burst, Basic Visual Effects, Artist-Curriculum).
- Lokal ausgewertet (VERIFIED): `/root/tools/ref/Full-API-Dump.json`, `API-Dump.json`, `globalTypes.d.luau`
  (Security, Tags, Capabilities).
- DevForum, YouTube, realtimevfx, gamedeveloper.com, LoL-Styleguide usw. sind im Sandbox blockiert; alles von dort
  stammt aus WebSearch-Zusammenfassungen und ist **REPORTED** (Snippets können verkürzt oder veraltet sein).
- Kein Fremdcode kopiert; Module/Techniken nur konzeptionell beschrieben. **Keine eigenen FPS-Zahlen.** Wo Foren
  FPS-Werte nennen, wird nur die Tendenz wiedergegeben.
- Abgrenzung: Property-Details zu ParticleEmitter/Beam/Trail stehen in `api-particles-beams-trails.md`, Parts/Licht/
  Tween in `api-geometry-lighting-tween.md`. Hier geht es um Design-Regeln, Kosten, Qualitätsstufen und Netzwerk.

---

## 1. Zusammenfassung

**A – Design-Handwerk**

1. Erfahrene VFX-Leute beschreiben Effekte als **Intensitätskurve über die Zeit**: Wind-up/Anticipation → Crescendo/
   Climax (Impact) → Follow-through/Secondary → Dissipation. Es gibt „Impulse“-Effekte (sofort, ohne lange
   Ankündigung) und „Rhythm“-Effekte (fließend, oft geloopt). (REPORTED, VFX Apprentice)
2. **Gameplay vor Stil**: Lesbarkeit (Form, Wert/Kontrast, Farbe, Timing = Bedrohungsstufe) steht über Thematik. Der
   hellste Wert gehört auf den spielrelevanten Fokuspunkt. 100 % Weiß wird für die größten Momente reserviert.
   (REPORTED, LoL-Styleguide/GDC 2017)
3. **Layering** ist der Standard für Impacts und Explosionen: Instant-Flash (nur ca. 2–3 Frames), Core/Burst, Ring/
   Shockwave, Sparks (klein, gebündelt, gestreckt), Rauch (länger, mit gebrochener Silhouette), optional
   Distortion. Die meisten Layer sind kurzlebig. Der gesamte Impact soll innerhalb von etwa einer Sekunde lesbar sein.
   (REPORTED)
4. Roblox-native Bausteine der Community: **Neon + Bloom** für Glühen, **additive Partikel** (`LightEmission = 1`),
   Mesh-VFX über **SpecialMesh.Scale-Tweens**, **ForceField**-Material für Schimmer und Schilde, **Beams** mit
   `CurveSize` für Slashes, **Attachment-Ketten + Beams** für Blitze, **Flipbooks**, **Highlight + ColorCorrection**
   für Impact Frames, **Glass mit Transparency > 1** für Distortion (nicht auf Mobile!), Kamera-Shake-Module
   (Trauma-Modell). Alles REPORTED außer den dokumentierten Mechanismen (LightEmission, Bloom, Flipbooks, Mesh-Scale).

**B – Performance & Networking**

5. Offiziell (VERIFIED): Partikel kosten über **Fill-Rate** (Bildschirmfläche) und **Overdraw** (überlappende
   Transparenz). Partikel **batchen schlecht** (eigene Draw Calls), und **Property-Änderungen an ParticleEmittern
   können die Performance dramatisch beeinflussen**. Pro Emitter gelten **max. 400 Partikel/s (100/s auf Mobile)**.
   Die MicroProfiler-Doku nennt als Hebel: weniger Emitter, kleinere Rate und Lifetime, **wenig Emitter-Bewegung**.
   **[kritisch]**
6. Offiziell (VERIFIED): Schatten werden **unter Qualitätsstufe 4 ganz abgeschaltet**. Parts werfen Schatten
   **unabhängig von ihrer Transparenz** (die Engine nimmt Decals an). Unsichtbare Träger-Parts sollen deshalb
   `CastShadow = false` haben. Teiltransparenz (0.01–1) läuft über einen eigenen Transparent-Pass. **[kritisch]**
7. **Grafikqualität**: `UserGameSettings.SavedQualityLevel` (Automatic, 1–10) ist per LocalScript lesbar.
   `GraphicsQualityLevel` ist `RobloxScriptSecurity`. Bei „Automatic“ gibt es laut Doku **keinen zuverlässigen Weg**,
   die tatsächliche Stufe zu lesen. `Stats:GetHarmonyQualityLevel()` existiert, braucht aber die Capability
   `InternalTest`. **[kritisch]**
8. Die Engine **skaliert Effekte selbst** nach Grafikqualität und teils nach Kameradistanz (REPORTED): Partikel-Rate
   ≈ `Rate × Level/10`, Beam-`Segments` bis auf 1, berichtete globale Partikel-Caps. Ein Bug-Report von ca. Aug. 2026
   sagt, dass die Rate-Skalierung derzeit nicht greift. Ob `Emit(n)` skaliert wird, ist umstritten. ASTRA darf nicht
   blind zusätzlich herunterskalieren. **[kritisch]**
9. **Mess-APIs für Skripte** (VERIFIED, Security None): `Stats.FrameTime` (nur Client), `RenderCPUFrameTime`,
   `RenderGPUFrameTime`, `SceneDrawcallCount`, `SceneTriangleCount`, `Shadows*Count`, `InstanceCount`,
   `GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.GraphicsParticles)` (nur bei `MemoryTrackingEnabled`).
   `SceneAnalysisService:GetTriangleCompositionAsync()` liefert Dreiecke und Draw Calls **pro Render-Pass inkl.
   „Particles“**. Plugins können über `settings().Rendering` (`RenderSettings`, PluginSecurity) die
   Studio-Qualitätsstufe lesen und setzen. **[kritisch]**
10. **Netzwerk** (VERIFIED): Roblox empfiehlt ausdrücklich, Explosionen und Zauber **nicht auf dem Server als
    Instanzen zu erzeugen**: Der Server kennt nur Ort und Ergebnis, die Clients erzeugen die Visuals lokal.
    Serverseitiges TweenService repliziert jeden Frame. `UnreliableRemoteEvent`: Payload > **1000 Bytes** wird
    verworfen (die Ankündigung nannte 900), keine Reihenfolge, kein Queueing ohne Listener. Client→Server ca.
    **500 Requests/s pro Client** und Remote-Typ. **[kritisch]**
11. **StreamingEnabled** (VERIFIED): Ein Remote-Signal und die Instanz, auf die es verweist, reisen **unabhängig**.
    Instanzreferenzen können beim Client `nil` sein oder später kommen. Ausgestreamte Instanzen werden nach `nil`
    umgehängt, **lokale Änderungen** an ihnen können verloren gehen, und Positionswerte können veraltet sein.
    Streaming ist für neue Places Standard und per Skript nicht änderbar. **[kritisch]**
12. **Aufräumen/Pooling**: `Debris` hat ein **hartes Limit von 1000 Objekten**. Ältere Einträge werden sofort
    zerstört (VERIFIED). Community-Pools (PartCache, ObjectCache mit `BulkMoveTo`) berichten Vorteile gegenüber
    Create/Destroy. Belastbare offizielle Benchmarks gibt es nicht (REPORTED). Für Highlights empfiehlt die Doku:
    einmal anlegen und Properties ändern statt Instanzen zu erzeugen. Studio zeigt max. **255 Highlights**
    gleichzeitig (VERIFIED).

---

## 2. Befunde

### Teil A – VFX-Design-Handwerk

#### 2.1 Phasen, Timing, Spacing

| # | Befund | Label | Quelle |
|---|---|---|---|
| A1 | Effekte lassen sich nach ihrem Intensitätsverlauf in zwei Muster einteilen: **Impulse** (sofortig/Crescendo; starker Ausbruch, ebenso schnelles Verschwinden) und **Rhythm** (fließend/disruptiv; graduell, oft geloopt). Bei sofortigen Effekten entfällt die Anticipation, sie starten mit hoher Intensität. Auch sie sollen aber sauber ausklingen. | REPORTED | [G-Timing] |
| A2 | Phasenfolge: **Wind-up → Crescendo/Climax („Pop“) → Follow-through → Dissipation**. Anticipation sind kleinere vorbereitende Bewegungen vor der Hauptaktion. Wie lang Anticipation und Dissipation sein dürfen, bestimmt oft das Gameplay. | REPORTED | [G-Timing], [G-CA] |
| A3 | Rhythmus „Telegraph → Impact → Resolve“: Die Reihenfolge wird nie vertauscht, auch wenn sie schneller ablaufen darf. Ein Guide (geringe Autorität) nennt für Gegner-Telegraphs ein Onset von ca. 120–220 ms und ein Halten von ca. 250–550 ms je nach Gegnerstufe. | REPORTED (Zahlen schwach belegt) | [G-Telegraph], [G-FF7] |
| A4 | **Hit-Stop** (beidseitiges Einfrieren beim Treffer) ist ein systematischer Wert pro Spiel. Capcoms SFV-Kolumne nutzt 8 Frames als Beispiel. Blogs nennen 2–5 Frames als typisch für leichte Treffer und warnen, dass > 20 Frames wie ein Bug wirken. Eine Studie (2024) testete 0–0,7 s und fand kein quantitatives Optimum. | REPORTED | [G-HitStop] |
| A5 | Bei Explosionen dauert der **Instant-Flash nur ca. 2–3 Frames**, die meisten Layer sind kurzlebig, und das Gesamtbild soll als Impact in etwa einer Sekunde lesbar sein. | REPORTED | [G-Explosion] |
| A6 | Easing für „schnell raus, langsam aus“ (Shockwaves, Bursts): `EasingDirection.Out` startet schnell und bremst ab. Quint ist die schärfste Polynomkurve (vor Quart, dann Quad). `Circular` beschleunigt laut Doku noch abrupter und bremst graduell. `Back` gibt Overshoot. | VERIFIED (Enum/Doku) / REPORTED (Ranking) | [D-Easing], [F-Easing] |
| A7 | Ein langes Wind-up lässt die folgende Aktion schneller wirken. Die Pausen zwischen den Beats sind so wichtig wie die Beats selbst. | REPORTED (schwache Quelle) | [G-Anim] |

#### 2.2 Form, Silhouette, Lesbarkeit

| # | Befund | Label | Quelle |
|---|---|---|---|
| A8 | **Form** ist oft das zuerst wahrgenommene Attribut eines Effekts und dient als Wiedererkennungsmerkmal (z. B. Mündungsfeuer je Waffe in Halo Infinite). Shape Language kann zudem **Richtung** signalisieren. | REPORTED | [G-Gil] |
| A9 | Die Prinzipienliste des GDC-2017-Bootcamps (Riot/Blizzard): **Gameplay**, **Shape & Area of Effect**, **Contrast & Focal Point**, **Color & Identity**, **Timing & Threat Level**. Gameplay kommt vor Stil. Effekte müssen bei Bedarf heruntergeskaliert werden können. | REPORTED | [G-GDC2017], [G-LoLGuide] |
| A10 | Riot priorisiert bei VFX-Updates **Lesbarkeit vor thematischer Wirkung** und korrigiert vor allem ungenaue oder fehlende Hitbox-Indikatoren. | REPORTED | [G-Readable] |
| A11 | Anfängerregel aus Roblox-nahen Guides: Erst eine **erkennbare Außenform** bauen. Ist die Aktion auf einen Blick nicht erkennbar, **Details reduzieren**, statt weitere Layer hinzuzufügen. | REPORTED (geringe Autorität) | [F-Tripo] |
| A12 | Checkliste aus einer Community-Quelle: Für jeden Effekt eine **Silhouette auf Kameradistanz**, eine Farbhierarchie, ein **Spawn-Cap** und ein Reduced-Motion-Äquivalent festlegen. Telegraph, Contact, Success, Failure und Lingering-Status visuell trennen. | REPORTED (geringe Autorität) | [G-Telegraph] |

#### 2.3 Wert, Kontrast, Farbe

| # | Befund | Label | Quelle |
|---|---|---|---|
| A13 | Ein höherer **Wertebereich zieht Aufmerksamkeit**. Kontrast erzeugt den Fokuspunkt und kann die Wirkungsfläche definieren. Der Wert wird zum spielrelevanten Zentrum geschoben (LoL-Beispiel: Bombe mit hellem Zentrum). Reines 100 % Weiß oder 0 % Schwarz wird vermieden, weil es mit Umgebung oder UI verwechselt werden kann. | REPORTED | [G-LoLGuide] |
| A14 | Projektil-Anatomie: Die schadensrelevante Front ist **heller, gesättigter und hat die schärfsten Formen**. 100 % Weiß wird für Ultimates reserviert. | REPORTED | [G-LoLMissile] |
| A15 | „Heller Kern, gesättigte Ränder“: Es gibt keine einzelne autoritative Quelle für dieses Rezept. Community-Tipps: Outlines über Texturen mit opakem Rand und transparenterem Inneren; helle Spots per HDR bzw. additiv, damit die Farben gesättigt bleiben. | REPORTED | [G-RTVFXColor] |
| A16 | Roblox-Mechanik dazu: `ParticleEmitter.LightEmission` = 0 bedeutet normales Blending, 1 additives Blending. Bei `LightEmission > 0` erscheinen **dunklere Farben transparenter**. Eine Änderung wirkt sofort auf alle Partikel. Das offizielle Tutorial setzt `LightEmission = 1`, damit sich überlappende Partikel aufhellen. | VERIFIED | [D-PE], [D-TutBasicVFX] |
| A17 | `BloomEffect.Threshold`: Bei 1 bloomt **nur reines Weiß**, bei 0 alles. Bloom wirkt wie Neon auf allem inkl. Sky. Mehrere BloomEffects kombinieren sich. Das Rendering hängt von der Studio-Qualitätsstufe ab. | VERIFIED | [D-Bloom], [D-PostFX] |
| A18 | Neon-Teile glühen mit Bloom sichtbar, ein normal weißes Teil nicht. Für subtilen „Glare“ wird ein hoher Threshold empfohlen. Es gibt **keine Emissive-Textures** in Roblox. | REPORTED | [F-Bloom] |

#### 2.4 Layering-Bausteine

| # | Befund | Label | Quelle |
|---|---|---|---|
| A19 | Ein Overwatch-inspiriertes Explosions-Breakdown hat **18 Layer** in den Gruppen Shockwave, Smoke, Instant Flash, Burst Ring, Burst Core und Sparks. Allgemein: Core-Flash, Fireball, Smoke, Sparks und Shockwave sind getrennte Rollen. Ohne Layering wirkt der Effekt „wie Spielzeug“. | REPORTED | [G-Explosion] |
| A20 | **Sparks**: klein (wenige Pixel), in „Jets/Spears“ gruppiert (ähnliche Richtungen), oft **gestreckt** oder mit Trails. **Smoke**: verweilt länger; spitze Flipbook-Formen brechen die Rundheit des Feuerballs. Die Core-Größe wird pro Instanz variiert. **Distortion** verkauft den Effekt, wird aber leicht übertrieben. | REPORTED | [G-Explosion] |
| A21 | Roblox-Mechanik für gestreckte Sparks: `Orientation = VelocityParallel` mit **negativem Squash** (laut Doku), alternativ Trails. | VERIFIED (Mechanik) | [D-Particles] |
| A22 | Glow wird oft in die Textur eingebaut (Backlit-/Inner-Glow-Rauch) statt allein dem Bloom überlassen. | REPORTED | [G-Explosion] |

#### 2.5 Kamera- und Screen-Effekte

| # | Befund | Label | Quelle |
|---|---|---|---|
| A23 | **Kamera-Shake nach dem Trauma-Modell** (Eiserloh, GDC 2016, Sekundärquellen): Gameplay addiert Trauma (0..1), das über die Zeit abklingt. Die Shake-Stärke ist Trauma^2 oder Trauma^3. Die Auslenkung kommt aus **Perlin-Noise** pro Achse mit Offset statt aus Frame-Zufall, gedeckelt durch eine Maximalauslenkung bzw. einen Maximalwinkel. | REPORTED | [G-Shake] |
| A24 | Roblox-Community: RbxCameraShaker (Port von EZ Camera Shake; Start/Stop/StopSustained mit Fade-out, One-shot-Shakes) ist verbreitet. Berichtet wird, dass `Stop` Sustained-Shakes nicht aus der aktiven Liste entfernt, sodass sie sich stapeln. Neuere Alternativen: CameraShakeUpdated, GG Camera Shake (Wunsch nach 3D-Ursprung). | REPORTED | [F-CamShake] |
| A25 | **Impact Frames** in Roblox: ColorCorrection mit Saturation 0 bzw. −1 und angepasstem Kontrast, dazu Highlights in Kontrastfarbe auf den sichtbaren Teilen. Highlight- und Korrekturwerte werden kurz invertiert, Schritte im Abstand von ca. 0,1 s, Partikel per `Emit()` dazwischen. Problem: ColorCorrection verschluckt Partikel. Ein Workaround nutzt eine schwarze Skybox plus Highlights. Ein Open-Source-Modul bietet White/Black/Custom-Presets. | REPORTED | [F-ImpactFrame] |
| A26 | In Anime sind Impact Frames einzelne Frames mit vertauschter oder Schwarz-Weiß-Palette, laut einer schwachen Quelle typ. 1–3 Frames. Ein UE5-Beispiel nutzt 7 Post-Process-Materialien für je einen Frame. | REPORTED (schwach) | [G-ImpactFrames] |
| A27 | Highlight-Flash als Treffer-Feedback: Die offizielle Doku empfiehlt, Highlights **nicht dauernd anzulegen oder zu entfernen** (Geometrie-Rebuild, Spikes, Extra-Draw-Calls), sondern Properties zu ändern. `Enabled` umschalten kostet nichts. Das **erste sichtbare Highlight** kostet bis ca. 1 ms GPU auf Mobile, weitere wenig. Auf Mobile steigen die Kosten mit der Bildschirmfläche. Unsichtbare Highlights kosten nichts. Studio zeigt clientseitig max. **255** gleichzeitig, weitere werden still ignoriert. | VERIFIED | [D-Highlight] |

#### 2.6 Roblox-native Techniken (Community-Praxis)

| # | Technik | Umsetzung (Konzept) | Einschränkungen | Label | Quelle |
|---|---|---|---|---|---|
| A28 | Neon + Bloom | Neon-Parts oder -Meshes als Kern, Bloom in Lighting verstärkt das Glühen | Bloom ist global und spielerseitig nicht gezielt steuerbar; Neon „frisst“ die Oberfläche | REPORTED / VERIFIED (Bloom-Mechanik) | [F-Bloom], [D-Bloom] |
| A29 | Mesh-VFX mit SpecialMesh | `SpecialMesh.Scale`/`Offset` (und `VertexColor`) per TweenService animieren; Transparenz über das Part. FileMesh skaliert relativ zur Originalgröße beim Upload, Brick/Sphere relativ zur Part-Größe; Kollision ändert sich nicht | Wer `MeshPart.Size` tweent, berichtet von Verzerrung oder Streckung | VERIFIED (Scale-Semantik) / REPORTED (Praxis) | [D-SpecialMesh], [F-Shockwave] |
| A30 | ForceField-Material | Schimmer und Schild-Look; mit Textur wird der **Rotkanal** zum Schimmermuster; höhere Transparenz betont das innere Leuchten; Reflectance steuert den Fresnel-Anteil | Gemeldeter Bug: Eine ForceField-MeshPart sieht zur Laufzeit wie Neon aus | REPORTED | [F-FF] |
| A31 | Beams für Slashes | Gekrümmter Beam via `CurveSize0/1` zwischen zwei Attachments, Attachments vom Griff zur Spitze tweenen, FaceCamera; Texturen stapeln, Breiten und Kurven variieren, auf einen Keyframe der Schwert-Animation synchronisieren | Manche raten bei Schwertschwüngen zu Spritesheets bzw. Texture-Offset | REPORTED / VERIFIED (Bezier-Mechanik) | [F-Slash], [D-Beam] |
| A32 | Trails für Schwünge | Trail am Blatt mit kurzer Lifetime | Gemeldet: **Trail-Lifetime ist FPS-abhängig** (höhere FPS → kürzere Trails) | REPORTED | [F-Slash], [F-TrailFPS] |
| A33 | Blitze | Kette von (echten oder „virtuellen“) Attachments mit zufälligen senkrechten Offsets, dazwischen Beams; regelmäßig neu würfeln | Attachments müssen in einem BasePart (oder Terrain) liegen | REPORTED | [F-Lightning] |
| A34 | Gestapelte Beams als Pseudo-3D | Mehrere Beams übereinander mit scrollender Textur imitieren ein 3D-Mesh | – | REPORTED | [F-Runup] |
| A35 | Distortion via Glass | Glass-Kugel mit `Transparency > 1` (z. B. 1.6), teils mit Highlight | Funktioniert **nicht auf Mobile**, braucht **Grafik ≥ 8**, Effekt „wandert“ bei hoher Transparenz; Roblox-Staff rät ab | REPORTED | [F-Glass], [F-Runup] |
| A36 | Dome/Domain-Expansion | Kuppel aus Neon-Parts, deren Größe getweent wird, oder Kugel-Emitter mit `ShapePartial` 0→1 | – | REPORTED | [F-Dome] |
| A37 | Charge-up | Partikel nach innen ziehen und Kernlicht oder Neon-Helligkeit hochfahren, danach Burst. Die Engine bietet `ShapeInOut = Inward` (Enum `ParticleEmitterShapeInOut`: Outward, Inward, InAndOut) | – | REPORTED (Rezept) / VERIFIED (Enum) | [F-Charge], [API] |
| A38 | Flipbook-Partikel | Native Flipbooks (Layouts/Modi siehe API-Note); fertige Packs wie Impact-Frames und Clashes als Flipbooks | Kosten Speicher; bei Speicherknappheit **deaktiviert der Client Flipbooks automatisch** (ältere Phones) | VERIFIED (Speicherwarnung) | [D-Particles] |
| A39 | Mesh-Flipbooks | Nicht nativ: Meshes/Texturen nacheinander zeigen; besser mehrere vorbereitete Mesh-Instanzen statt schnellem Textur-Tausch (Double-Buffer) | MeshPart-Transparenz wirkt auf das ganze Mesh | REPORTED | [F-MeshFlip] |
| A40 | Partikel statt Blender-Geometrie | Community-Tenor: In-Engine-Partikel wirken glatter als importierte Blender-Animationen; bei komplexen Meshes leidet die Performance | – | REPORTED | [F-LearnVFX] |

#### 2.7 Rezeptsammlung (wiederverwendbar, mit Herkunft)

| # | Rezept | Werte | Label | Quelle |
|---|---|---|---|---|
| R1 | Spark-Burst (offizielles Tutorial) | `Lifetime 0.2–0.6`, `Speed 20–40`, `Drag 10`, `SpreadAngle 180,180`, `Enabled = false`, Auslösung per `Emit(100)`; Color-Gradient, Transparency als weich steigende Kurve | VERIFIED (Tutorialwerte) | [D-TutExplosion] |
| R2 | Ambient-Flare (offizielles Tutorial) | `LightEmission 1`, `ZOffset 1`, `Lifetime 10`, `Rate 0.45`, Size 0 → langsam → schnell auf 10, Transparency nahe 0 und am Ende flackernd → 1; PointLight `Brightness 2`, `Range 36` | VERIFIED | [D-TutBasicVFX] |
| R3 | Impact-Flash | Sichtbarer Peak ca. 2–3 Frames (≈ 33–50 ms bei 60 fps), danach Abklingen; der ASTRA-Default `flash` (attack 0.03 / hold 0.02 / decay 0.25 s) liegt in diesem Rahmen | REPORTED (Frames) / ASSUMPTION (Umrechnung, Einordnung) | [G-Explosion], COMPONENTS_SPEC §10 |
| R4 | Hit-Stop | leicht ≈ 2–5 Frames, schwer länger (SFV-Beispiel 8 Frames), nicht > ca. 20 Frames | REPORTED | [G-HitStop] |
| R5 | Impact Frame | Saturation −1/0 + Kontrast-Highlight, Invertierung in ca. 0,1-s-Schritten; anime-typisch 1–3 Frames | REPORTED | [F-ImpactFrame], [G-ImpactFrames] |
| R6 | Kamera-Shake | Trauma 0..1, Stärke = Trauma²–³, Perlin-Noise je Achse, Abklingen, Maximalauslenkung deckeln | REPORTED | [G-Shake] |
| R7 | Shockwave | Expansion mit `Quart/Quint/Circular Out`, Fade mit `In`-Kurve; Mesh über `SpecialMesh.Scale` statt `MeshPart.Size`; Schaden getrennt über unsichtbare Hitbox oder Distanzprüfung | VERIFIED (Easing) / REPORTED (Praxis). **Für die Dauer fand ich keine belastbare Zahl.** | [D-Easing], [F-Shockwave] |
| R8 | Explosion-Layer-Stack | Flash (2–3 Fr.) → Burst-Core → Ring/Shockwave → Sparks (Jets, gestreckt) → Smoke (lang, gebrochene Silhouette) → optional Distortion; Gesamtlesbarkeit ≤ ca. 1 s | REPORTED | [G-Explosion] |
| R9 | Additive Farbführung | `LightEmission 1`; ColorSequence von fast weiß (Kern, frühes Alter) über gesättigte Hauptfarbe zu dunkel (Ende). Dunkel wirkt additiv transparent und dient als natürliches Ausblenden | VERIFIED (Mechanik) / ASSUMPTION (Rezept) | [D-PE] |
| R10 | Telegraph | Onset ca. 120–220 ms, Halten ca. 250–550 ms je nach Bedrohungsstufe | REPORTED (schwach) | [G-Telegraph] |

### Teil B – Roblox-VFX-Performance & Networking

#### 2.8 Rendering-Kosten von Partikeln

| # | Befund | Label | Quelle |
|---|---|---|---|
| B1 | **Fill-Rate**: Je mehr Pixel Partikel auf dem Bildschirm belegen, desto teurer auf der GPU. | VERIFIED | [D-Particles] |
| B2 | **Overdraw**: Die Partikelanzahl kostet über Overdraw, besonders bei Überlappung. Mehr transparente Schichten bedeuten höhere GPU-Kosten. Allgemein: Teiltransparente Objekte nah beieinander zwingen zum mehrfachen Rendern derselben Pixel („high transparency overdraw“). | VERIFIED | [D-Particles], [D-Improve], [D-EnvOpt] |
| B3 | **Rate-Grenze pro Emitter: max. 400 Partikel/s (100/s auf Mobile).** Für beste Performance die Rate so niedrig wie möglich halten und lieber mit Size u. a. arbeiten. | VERIFIED | [D-Particles] |
| B4 | Widerspruch in der Doku: Das offizielle „Basic visual effects“-Tutorial setzt für Staub `Rate = 50000` in einem großen Volumen-Part. Vermutlich klemmt die Engine intern (nicht dokumentiert). | VERIFIED (Werte) / ASSUMPTION (Klemmung) | [D-TutBasicVFX], [D-Particles] |
| B5 | Decals, Texturen und **Partikel batchen schlecht** und erzeugen zusätzliche Draw Calls. **Property-Änderungen an ParticleEmittern können die Performance dramatisch beeinflussen.** | VERIFIED | [D-Improve] |
| B6 | MicroProfiler-Tag `Perform/Scene/UpdateView/updateParticles, updateParticleBoundings` (Partikel-Positionen und -Bounds). Abhilfe laut Doku: weniger Emitter, kleinere Rate und Lifetime, **Bewegung der Emitter begrenzen**. `Prepare/UpdatePrepare/updateDynamicParts` bereitet Beams, Emitter und Humanoids vor; Abhilfe: weniger sichtbare davon. | VERIFIED | [D-MPTags] |
| B7 | Flipbooks und andere Custom-Textur-Features kosten Speicher. Bei Speicherknappheit deaktivieren Clients Flipbooks automatisch. Empfehlung: weniger unterschiedliche animierte Effekte, kleinere Texturen, Texturen wiederverwenden. | VERIFIED | [D-Particles] |
| B8 | Grafikspeicher einer Textur hängt von der **Pixelzahl** ab, nicht von der Dateigröße: 1024² kostet 4× so viel wie 512². Bilder werden transkodiert, Kompression oder ein fehlender Alpha-Kanal sparen keinen Speicher. Faustregel: ≤ 512² außer bei großer Bildschirmfläche, kleine Bilder < 256². | VERIFIED | [D-Improve] |
| B9 | Große transparente Partikel nahe oder um die Kamera erzeugen deutliche FPS-Einbrüche (Overdraw). `Emit()` in Kameranähe soll Lag-Spikes verursachen. Ein Feature-Request bemängelt die generelle CPU-Last von Emittern auch bei statischen Effekten. | REPORTED | [F-EmitClose], [F-PEPerf] |
| B10 | Partikeleffekte erscheinen verzögert, wenn sie selten genutzt werden. Vermutung im Forum: Roblox entlädt Texturen aggressiv, wenn kein Emitter sie nutzt. Offiziell: `ContentProvider:PreloadAsync` auf unsichtbaren Instanzen lädt in den Disk-Cache, die Engine **kann die Texturen danach wieder aus dem Speicher entladen**. | REPORTED / VERIFIED (Preload-Verhalten) | [F-TexDelay], [D-ContentProvider] |
| B11 | Szene-Analyse: Ein Instanz-Kompositions-View zeigt unbeabsichtigte Mengen (Doku-Beispiel „25.000 Particle Emitter“). Die Triangle-Komposition hat einen eigenen Pass **„Particles“**. | VERIFIED | [D-SceneAnalysis] |

#### 2.9 Beams und Trails

| # | Befund | Label | Quelle |
|---|---|---|---|
| B12 | Beam = gerade Segmente, Default `Segments = 10`. `Color`/`Transparency` brauchen ≥ n−1 Segmente (n = Keypoints). Eine dokumentierte Obergrenze für `Segments` fand ich nicht. | VERIFIED / (Obergrenze: nicht gefunden) | [D-Beam] |
| B13 | Die Engine **reduziert Beam-Segments je nach Grafikqualität bis auf 1** (gerade Linie). Beobachtet wurde ein Teiler von ca. 10 auf Stufe 1, und Beams mit wenigen Segmenten werden flach oder verschwinden. Workaround: Segmente großzügig setzen (ein Entwickler: ×5), Zwangs-LOD gibt es nicht. Die Doku sagt nur allgemein, dass sich die Beam-Qualität mit den Grafikeinstellungen ändert. | REPORTED / VERIFIED (allgemeiner Hinweis) | [F-BeamLOD], [D-Beams] |
| B14 | **Trail-Lifetime ist FPS-abhängig** (höhere FPS → schnelleres Verschwinden); Workaround: Lifetime nach dt skalieren. | REPORTED | [F-TrailFPS] |
| B15 | Viele erzeugte und zerstörte Trail-Marker-Parts führen nach einiger Zeit zu Lag. Empfehlung im Forum: cachen statt neu erzeugen. | REPORTED | [F-TrailLag] |

#### 2.10 Parts, Meshes, Bewegung

| # | Befund | Label | Quelle |
|---|---|---|---|
| B16 | `WorldRoot:BulkMoveTo(partList, cframeList, eventMode)` verschiebt viele BaseParts ohne Einzel-Property-Kosten. Mit `Enum.BulkMoveMode.FireCFrameChanged` feuert nur `CFrame`-Changed. Laut Doku nur nutzen, wenn Bewegung wirklich ein Engpass ist; einzelne CFrame-Sets reichen meist. | VERIFIED | [D-WorldRoot], [D-BulkMoveMode], [API] |
| B17 | Community-Messungen zu BulkMoveTo vs. CFrame widersprechen sich, der Vorteil bei großen Batches ist real, aber moderat. Ein Bericht misst bei ca. 5000 Parts `.Transform` als schneller. Kontrollierte Benchmarks fehlen. | REPORTED | [F-BulkMove] |
| B18 | Physik: Teile ohne Simulationsbedarf **anchoren**. Precise-CollisionFidelity ist am teuersten; bei Objekten ohne Kollision Box/Hull wählen, weil die Kollisionsgeometrie trotzdem im Speicher liegt. `CanTouch` und `CanCollide` aus bringt einen kleinen Gewinn. | VERIFIED | [D-Improve], [D-BasePart] |
| B19 | Teiltransparenz (0.01..1) läuft in eigenen Passes (`Id_Transparent`). Designregel der Doku: **nur 0 oder 1 verwenden**, wenn möglich, bei Teiltransparenz Overdraw vermeiden. | VERIFIED | [D-MPTags], [D-Design] |
| B20 | Instancing: Identische Meshes (gleicher MeshContent und gleiche Textur/Material) werden in einem Draw Call gerendert. Dieselben Asset-IDs mehrfach nutzen statt Duplikate hochzuladen. | VERIFIED | [D-Improve] |
| B21 | Bewegte **skinned MeshParts** ohne Humanoid lösen Rebuilds der FastCluster aus. Zu viele Parts in einem Model können ebenfalls Rebuilds verursachen. | VERIFIED | [D-Improve] |
| B22 | Laufzeit-Hinweis: Code auf RunService-Frame-Events (PreRender, PreSimulation, PostSimulation, Heartbeat) sparsam halten. Ein Frame hat bei 60 FPS 16,67 ms Budget. Große Arbeit per `task.wait()` aufteilen und event-getrieben statt per Frame rechnen. `BindToSimulation` mit `StepFrequency` (60/30/15/10/5/1 Hz) ist für Physik und Prediction gedacht und verlangt synchronisierte Properties, für VFX also nicht geeignet. | VERIFIED | [D-Improve], [D-Design], [D-RunService], [D-StepFrequency] |

#### 2.11 Licht und Schatten

| # | Befund | Label | Quelle |
|---|---|---|---|
| B23 | Schatten sind teuer. Die Engine verschlechtert die Schattenqualität mit sinkender Grafikstufe und **schaltet Schatten unter Stufe 4 komplett ab** (`ShadowMapSystem`, `Scene/Shadows` werden dann nicht ausgeführt). Hebel: `Light.Shadows` aus, `BasePart.CastShadow` aus bei kleinen, bewegten oder unwichtigen Teilen, weniger Lichter, Range und Angle begrenzen, entfernte Lichter abschalten. | VERIFIED | [D-Improve], [D-MPTags] |
| B24 | „Parts werfen **unabhängig von ihrer Transparenz** Schatten, weil die Engine Decals annimmt.“ Voll transparente Parts ohne Decals sollen `CastShadow = false` haben. Laut BasePart-Doku ist `CastShadow` nicht als Performance-Schalter gedacht (Artefakte möglich), hilft aber in komplexen Szenen. | VERIFIED | [D-MPTags], [D-BasePart] |
| B25 | `computeLightingPerform`/`LightGridCPU`: Lichtquellen und bewegte, schattenwerfende Geometrie invalidieren das Voxel-Licht. Abhilfe: weniger Lichter, nicht schattenwerfende Geometrie für bewegte Objekte. | VERIFIED | [D-MPTags] |
| B26 | Unter Future-Lighting sind **schattenwerfende PointLights** ein Hauptkostenfaktor (Repro: 16+ Shadow-Lights, Shadow-Neuberechnung bei Bewegung oder Erscheinen). Roblox-Staff räumt hohe Kosten ein. Ob die Last auf CPU oder GPU liegt, ist umstritten. | REPORTED | [F-Future] |

#### 2.12 Grafikqualität, Geräte, Engine-eigene Skalierung

| # | Befund | Label | Quelle |
|---|---|---|---|
| B27 | `UserSettings():GetService("UserGameSettings").SavedQualityLevel` → `Enum.SavedQualitySetting` (`Automatic` = 0, `QualityLevel1..10`). Security None, Capability `Players`, nur clientseitig sinnvoll. In Studio spiegelt der Wert die eigenen Einstellungen. | VERIFIED | [D-UGS], [D-SQS], [API] |
| B28 | `UserGameSettings.GraphicsQualityLevel` (die tatsächlich genutzte Stufe) und `MaxQualityEnabled` sind **RobloxScriptSecurity**. Die Doku zum Event `DataModel.GraphicsQualityChangeRequest(betterQuality)` sagt: Es feuert **nur bei F10 / Shift+F10**, nicht bei Änderungen im Escape-Menü, und „es gibt derzeit keinen Weg, die aktuelle Grafikqualität eines Nutzers zuverlässig zu lesen“ (bei Automatic). | VERIFIED | [D-DataModel], [API] |
| B29 | `Stats:GetHarmonyQualityLevel()` (dynamisches Qualitätsniveau 0–100) steht im Dump mit Security None, verlangt laut Doku aber die Capability **`InternalTest`** und ist für normale Skripte nicht aufrufbar. | VERIFIED | [D-Stats], [API] |
| B30 | `UserGameSettings.GraphicsOptimizationMode` (Performance/Balanced/Quality) gilt nur bei manueller Qualität und ist RobloxScriptSecurity. Im Automatik-Modus regelt der **Frame Rate Manager** die Qualität dynamisch. Zum Messen empfiehlt die Doku, die Qualität manuell auf Maximum zu setzen. | VERIFIED | [D-GOM], [D-Identify], [API] |
| B31 | Community-Lage: Die Effektivstufe ist nur bei manueller Einstellung bekannt, bei Automatic nur „unbekannt“. Änderungen lassen sich per `GetPropertyChangedSignal("SavedQualityLevel")` erkennen. Feature-Requests für eine API laufen weiter. | REPORTED | [F-GQDetect] |
| B32 | Die Engine **skaliert Partikel-Raten** nach Grafikqualität, beobachtete Formel ≈ `Rate × Level / 10`. Ein Engine-Bug-Report (ca. Aug. 2026) sagt, dass das **nicht mehr greift**, auch in Studio, seit einem Update. Eine Staff-Antwort fand ich nicht. | REPORTED | [F-GQRate], [F-RateBug] |
| B33 | Ob `ParticleEmitter:Emit(n)` nach Qualität skaliert wird, ist **umstritten**: Mehrere sagen nein (häufiger Workaround), andere ja. Ein Bypass-Modul rechnet die Rate jeden Frame aus Qualität und **Kameradistanz** zurück, verliert aber auf Distanz an Präzision und ist auf Mobile ungenau. | REPORTED | [F-IgnoreGQ], [F-OptLowGfx], [F-LODBypass] |
| B34 | Berichtete **globale Partikel-Caps**: ca. 16000 (PC/Xbox) und ca. 3500–3600 (Mobile/Konsole). Bei Überschreitung verschwinden Partikel spontan oder flackern auf Distanz. Offiziell steht nur, dass große Flächen die Limits schnell erreichen und **Mobile deutlich niedrigere Limits** hat. | REPORTED (Zahlen) / VERIFIED (qualitativ) | [F-EmitLimit], [D-Particles] |
| B35 | `Enum.QualityLevel` hat **21 Stufen** (+ Automatic) für Studio/RenderSettings, der Spieler-Slider dagegen 10. Eine offizielle Zuordnung gibt es nicht. Eine inoffizielle FastFlag-Tabelle listet eine nicht monotone Zuordnung 1→3, 2→2, 3→6 … 10→21. | VERIFIED (Enums) / REPORTED (Mapping) | [API], [D-RenderSettings], [F-FRMTable], [F-QLDocReq] |
| B36 | `RenderSettings` (über `settings().Rendering`) hat `QualityLevel`, `EditQualityLevel`, `EnableFRM`, `AutoFRMLevel`, `FrameRateManager`, `MeshPartDetailLevel` und `GetMaxQualityLevel()` (= 22). Alle sind **PluginSecurity**, also für Plugins lesbar und schreibbar. Die Doku empfiehlt, jeden Effekt über „Editor Quality Level“ bei niedrigster und höchster Stufe zu prüfen. | VERIFIED | [D-RenderSettings], [API], [D-Particles], [D-Beams] |
| B37 | Gerätebasis (offiziell): Android ist ca. 65 % eines typischen Player-Base, davon haben ~60 % 2–4 GB RAM. Über 50 % der Spieler nutzen Geräte mit 10.000–20.000 Passmark. Die Mehrheit spielt auf schwächeren Mobilgeräten, Thermal Throttling ist zu testen. | VERIFIED | [D-TestHW] |
| B38 | Beispiel-Budget aus der Doku (ausdrücklich nur als Beispiel für ein Basisgerät): unter 1.000 Draw Calls und 1.000.000 Dreiecken bleiben. Das ist **kein offizielles Limit**. | VERIFIED (als Beispiel) | [D-Design] |

#### 2.13 Mess-APIs (was ein Skript oder Plugin lesen kann)

| # | Befund | Label | Quelle |
|---|---|---|---|
| B39 | `Stats` (Security None, ReadOnly, NotReplicated): `FrameTime` (s, **nur Client**, 1/FrameTime = FPS), `RenderCPUFrameTime`, `RenderGPUFrameTime`, `HeartbeatTime`, `PhysicsStepTime`, `InstanceCount`, `PrimitivesCount`, `MovingPrimitivesCount`, `ContactsCount`, `SceneDrawcallCount`, `SceneTriangleCount`, `ShadowsDrawcallCount`, `ShadowsTriangleCount`, `UI2D*`/`UI3D*`, `DataSendKbps`/`DataReceiveKbps`, `Physics*Kbps`. `HeartbeatTimeMs`/`PhysicsStepTimeMs` sind deprecated. | VERIFIED | [D-Stats], [API] |
| B40 | Speicher: `GetTotalMemoryUsageMb()` (aus Sicht des OS), `GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag)`, z. B. `GraphicsParticles`, `GraphicsTexture`, `GraphicsParts`, `GraphicsMeshParts`, `Instances`. Gibt 0 und eine Warnung zurück, wenn `MemoryTrackingEnabled = false` (ändert sich nur beim Client-Neustart). | VERIFIED | [D-Stats], [API] |
| B41 | `SceneAnalysisService` (Security None, yields): `GetTriangleCompositionAsync()` liefert Dreiecke und Draw Calls je Pass (Opaque, Transparent, Decal, **Particles**, Shadows, UI, …), `GetInstanceCompositionAsync()` Instanzzahlen je Kategorie und Klasse. Zugriff ist auch über den Studio-MCP-Server möglich. Die Werte entsprechen nicht dem, was Spieler auf schwächeren Geräten sehen. Ob die API außerhalb von Studio funktioniert, ist nicht dokumentiert. | VERIFIED / offen | [D-SceneAnalysis], [D-SceneAnalysisSvc], [API] |
| B42 | `debug.profilebegin(label)` / `debug.profileend()` markieren eigene Bereiche im MicroProfiler. `debug.setmemorycategory(tag)` / `resetmemorycategory()` ordnen Luau-Speicher einer eigenen Kategorie zu. | VERIFIED | [D-debug], [API] |
| B43 | MicroProfiler und Developer Console laufen **auf Client-Geräten** (Ctrl+Alt+F6, F9). Frame-Farben: orange = Jobs > Render, blau = Render > Jobs, rot = Render-bound **und** GPU-Wait > 2,5 ms (oft Objektkomplexität, Texturgröße, **visuelle Effekte**). | VERIFIED | [D-TestHW], [D-MP] |

#### 2.14 Pooling und Aufräumen

| # | Befund | Label | Quelle |
|---|---|---|---|
| B44 | `Debris:AddItem` hat ein **hart codiertes Maximum von 1000 Objekten**. Darüber werden die ältesten **sofort** zerstört. `MaxItems` ist deprecated und gesperrt. Vorteil von Debris gegenüber `task.delay`: Es läuft außerhalb des Skriptkontexts, das Zerstören ist also auch garantiert, wenn das Skript endet. | VERIFIED | [D-Debris] |
| B45 | Community-Pools: PartCache (Teile recyceln statt Destroy), ObjectCache (Nachfolger, parkt per `BulkMoveTo`), GenericPool, PoolerPlus. Die Aussagen widersprechen sich: „weit wegsetzen“ ist schneller als Umparenten, „Parent = nil“ ist günstiger als Wegsetzen. Leistungsangaben stammen von den Autoren selbst. | REPORTED | [F-PartCache], [F-ObjectCache] |
| B46 | Debris vs. `task.delay` + Destroy: laut Community etwa gleich schnell (Mikro-Optimierung). Für sehr viele Objekte gilt Batch- oder Pool-Cleanup als glaubwürdiger Weg. | REPORTED | [F-Debris] |
| B47 | Beim Ausstreamen werden Instanzen nach `nil` umgehängt und nicht zerstört, Luau-Zustand verbindet sich beim erneuten Einstreamen wieder (relevant für Pools, die mit `Parent = nil` arbeiten). | VERIFIED | [D-Stream] |

#### 2.15 Networking-Muster für VFX

| # | Befund | Label | Quelle |
|---|---|---|---|
| B48 | Offizielle Empfehlung: **Unnötige Instanz-Replikation vermeiden**, „z. B. Explosionen oder Zauber: Der Server muss nur den Ort kennen, um das Ergebnis zu bestimmen, die Clients erzeugen die Visuals lokal“. Ebenso Tweens auf dem Client statt auf dem Server: **Server-TweenService repliziert die Property jeden Frame** (Jitter und Traffic). Erzeugen oder Zerstören großer Instanzbäume ist netzwerkintensiv. | VERIFIED | [D-Improve] |
| B49 | `RemoteEvent`: zuverlässig und geordnet, auch **über verschiedene RemoteEvent-Instanzen hinweg**. Ohne Handler wird gequeued (Queue nach Anzahl und Speicher begrenzt). Ordnung gilt für den Start der Handler; yieldende Handler können sich überholen. | VERIFIED | [D-Remote] |
| B50 | `UnreliableRemoteEvent`: ungeordnet und unzuverlässig, gedacht für **kurzlebige Effekte** und kontinuierliche Daten. Verwurf bei Verlust, Überlast, **Payload > 1000 Bytes**, Client-Rate über dem Throttle (dann **Drop statt Verzögerung**) oder fehlendem Listener (kein Queueing). Keine Ordnungsbeziehung zu RemoteEvents. Für die Reihenfolge eigene Sequenznummern oder Timestamps nutzen. Buffers werden komprimiert, die Payload-Größe ist deshalb vor dem Feuern schwer prüfbar. | VERIFIED | [D-URE], [D-Remote] |
| B51 | Die Ankündigung bzw. ältere Doku nannte **900 Bytes**. Community-Tests: ca. 908 Byte effektiv, Buffers deutlich mehr (bis ~3,8 KB berichtet). Kostenschätzungen: number ≈ 9 B, bool ≈ 2 B, Vector3 ≈ 13 B, CFrame ≈ 14–20 B, Instance-Ref ≈ 6 B, String ≈ 1 B/Zeichen + 2–3 B. | REPORTED | [F-URE] |
| B52 | Throttle: RemoteEvents und UnreliableRemoteEvents **Client→Server ca. 500 Requests/s pro Client**, geteilt über alle Remotes desselben Typs. | VERIFIED | [D-RE], [D-URE] |
| B53 | Bandbreite: Die oft zitierten ~50 KB/s pro Client stammen aus älterer Doku und Community-Tests (weiches Limit, Physik wird zuerst gedrosselt). Aktuell nicht offiziell dokumentiert. | REPORTED | [F-50KB] |
| B54 | Wird über ein Remote eine Instanz übergeben, die beim Empfänger **nicht repliziert** ist, kommt `nil` an. Nicht-String-Tabellenschlüssel werden zu Strings, gemischte Tabellen und `nil`-Löcher sind zu vermeiden, Metatabellen gehen verloren, Funktionen kommen als `nil` an. | VERIFIED | [D-Remote] |
| B55 | **Streaming**: Ein Remote-Signal und die referenzierte Instanz reisen unabhängig. Das Signal kann vor der Instanz ankommen, oder die Instanz kommt nie (außerhalb des Streaming-Radius). Auch String-Pfade lösen sich dann nicht auf. Strategien: `WaitForChild` **mit Timeout**, oder vorab `Player:RequestStreamAroundAsync()` (wahrscheinlich, nicht garantiert). | VERIFIED | [D-StreamTech] |
| B56 | Ausgestreamte Instanzen erhalten keine Property-Updates mehr, gelesene Positionen können „beliebig veraltet“ sein. **Lokale Änderungen** an server-eigenen Instanzen gehen beim Aus- und Wiedereinstreamen eventuell verloren. Lokal von ReplicatedStorage nach Workspace umgehängte oder geklonte Instanzen werden streaming-fähig bzw. sind vom Server entkoppelt. Die Doku nennt Client-Desync „eine Ausnahme, kein Standardmuster“. | VERIFIED | [D-Stream], [D-StreamTech] |
| B57 | Streaming gilt nur für Workspace-Nachfahren, ist für neue Places **Standard** und `Workspace.StreamingEnabled` ist **per Skript nicht setzbar**. Verankerte Assemblies streamen nur die Parts im Radius (mit ihren Attachments und Constraints). Client-Physik läuft nur in gestreamten Bereichen, auch für lokal erzeugte Instanzen. | VERIFIED | [D-Stream] |
| B58 | Community-Muster für VFX-Replikation: Client→Server→alle Clients mit **serverseitiger Validierung** (darf der Spieler den Effekt auslösen?), dem Auslöser nicht zurücksenden (er spielt lokal sofort), oder strikt „nur der Server triggert“. Hitboxen, Cooldowns und Schaden bleiben serverseitig. Unter Streaming lieber IDs oder Attribute statt Instanzreferenzen schicken. | REPORTED | [F-ClientRep], [F-AnimeGuide], [F-StreamNil] |

---

## 3. Einschränkungen / Kritik

- **Design-Quellen**: Die stärksten Quellen (LoL-Styleguide-PDF, GDC-Vault, VFX Apprentice, gamedeveloper.com) waren
  nur über Such-Snippets erreichbar. Konkrete Zahlen zu Flash-Dauer, Hit-Stop und Telegraph stammen aus wenigen,
  teils schwachen Quellen (Blogs, KI-generierte „Skill“-Seiten). Sie taugen als **Startwerte für Presets**, nicht als
  Regeln. Für Shockwave-Expansionsdauer und typische Partikelanzahlen je Effekttyp fand ich **keine belastbaren
  Zahlen**.
- Viele Suchtreffer zu „Roblox VFX“ sind SEO-Spam (`*.pages.dev`, fremde Domains mit Kopien). Sie wurden verworfen.
  Echte Roblox-VFX-Tutorials auf YouTube ließen sich nur über Titel bestätigen, nicht über ihren Inhalt.
- **Engine-LOD ist intransparent**: Wie Rate, Emit, Beam-Segments und globale Caps skaliert werden, ist nur aus
  Forenbeobachtungen bekannt und hat sich mehrfach geändert (siehe Bug-Report Aug. 2026). ASTRA kann das Verhalten
  auf Spielergeräten **weder auslesen noch abschalten**.
- **Kein Weg zur Effektivqualität bei „Automatic“** (offiziell bestätigt). Jede Auto-Qualität in ASTRA ist eine
  Heuristik, etwa aus Frame-Zeit und Gerätetyp.
- **Partikel-Kosten pro Instanz** sind nicht dokumentiert. Die Doku nennt nur qualitative Treiber (Fläche, Overdraw,
  Anzahl, Bewegung, Property-Writes). Ein Analyzer kann nur relative Heuristiken liefern.
- `SceneAnalysisService` und `Stats` liefern **szenenweite** Zahlen. Kosten pro Effekt lassen sich nur durch
  Differenzmessung abschätzen (vorher/nachher), und auf dem Dev-PC sind die Werte laut Doku nicht repräsentativ.
- Die offizielle Doku widerspricht sich bei der Rate (400/s-Grenze vs. Tutorial mit 50 000) und bei der
  Unreliable-Payload (aktuell 1000 B, Ankündigung 900 B). ASTRA sollte jeweils den konservativen Wert nehmen.
- Kamera-Shake, Impact Frames und Hit-Stop sind **Spieler-Komfort-Themen**: Starkes Flackern und Wackeln kann
  stören. `UserGameSettings.ReducedMotion` ist RobloxScriptSecurity (API-Dump), also nicht lesbar.

---

## 4. Konsequenzen für ASTRA

### 4.1 Performance-Analyzer (heuristisch, klar als solcher gekennzeichnet)

1. **Kostenmodell je Komponente** (IDEA, auf B1–B7, B19, B23–B25 gestützt): Für jede Qualitätsstufe ausweisen
   - Partikel: *gleichzeitig lebende Partikel* ≈ Σ(rate × mittlere Lifetime) + Bursts, und ein
     **Overdraw-/Fill-Proxy** ≈ Σ(lebende Partikel × mittlere Size² × (1 − mittlere Transparency)). Getrennt zählen
     und ausweisen: die Zahl der Emitter, bewegte Emitter (B6) und **Property-Writes pro Sekunde auf Emittern**
     (B5, Warnung bei Kurven/Tweens auf Emitter-Properties pro Frame). **[kritisch]**
   - Beams: Anzahl × Segments, mit dem Hinweis, dass die Engine Segments auf Low reduziert (B13).
   - Parts: Anzahl, bewegte Parts pro Frame, teiltransparente Parts (B19), `CastShadow = true` bei transparenten
     Trägern (B24 → Lint-Fehler), Lichter mit `Shadows = true` (B23/B26 → Warnung).
   - Highlights: Anzahl; Warnung bei Neuerzeugung pro Play statt Wiederverwendung (A27). Hartes Limit 255 (VERIFIED).
2. **Harte Lints** (VERIFIED-Grundlage): Rate > 400 (Desktop) bzw. > 100 (Mobile-Profil) pro Emitter (B3).
   Beam-Segments < Keypoints − 1 (B12). Lifetime > 20 (siehe API-Note). Debris-Nutzung im Runtime-Code (B44).
   Glass-Distortion ohne `minQuality = High` (A35, REPORTED → Warnung statt Fehler).
3. **Messmodus im Play-Test** (IDEA): Ein Plugin-Panel misst Effekte isoliert per Differenzmessung aus `Stats`
   (`RenderCPUFrameTime`, `RenderGPUFrameTime`, `SceneDrawcallCount`, `SceneTriangleCount`, `InstanceCount`),
   `GetMemoryUsageMbForTag(GraphicsParticles/GraphicsTexture)` und
   `SceneAnalysisService:GetTriangleCompositionAsync()` (Pass „Particles“, „Transparent“, „Shadows“). Die Ergebnisse
   werden mit dem Hinweis versehen, dass Werte auf dem Dev-PC nicht repräsentativ sind (B41, D-Design). **Keine
   FPS-Versprechen** im UI. **[kritisch]**
4. **Quality-Preview im Editor** (IDEA): Das Plugin setzt vorübergehend `settings().Rendering.EditQualityLevel`
   (bzw. `QualityLevel` bei FRM) auf niedrige und hohe Werte, damit Engine-LOD und Schattenabschaltung (< Stufe 4)
   sichtbar werden, wie es die Doku empfiehlt (B36). Der ursprüngliche Wert wird immer wiederhergestellt. Weil das
   Mapping 1–10 → 1–21 inoffiziell ist (B35), werden nur „niedrig/mittel/hoch“-Presets angeboten, keine exakte
   Spielerstufe.

### 4.2 Qualitätsprofile (Abgleich mit ARCHITECTURE §5.4)

5. **Doppelte Skalierung vermeiden** (ASSUMPTION aus B13/B32/B33): Die Engine reduziert selbst (Rate, Beam-Segments,
   evtl. Caps), wenn auch derzeit möglicherweise fehlerhaft. Daraus folgt:
   - `segmentScale < 1` für **Beam.Segments** auf Low ist riskant: Engine-LOD plus ASTRA-Reduktion kann Beams flach
     machen oder verschwinden lassen. Empfehlung: Beam-Segments **nicht** herunterskalieren (Profil-Override
     `segmentScale = 1` für Beams) oder sogar einen Mindestwert erzwingen. `segmentScale` nur auf ASTRA-eigene
     Geometrie anwenden (Ring-Chords, Lightning-Punkte). **[kritisch]**
   - Für Rate-basierte Emitter nicht blind zusätzlich skalieren. Lieber Spawn-Caps und die Zahl gleichzeitiger
     Instanzen begrenzen. `countScale` vor allem auf Bursts (`Emit`), Debris, RadialBurst-Spikes und Layer-Anzahl
     anwenden, deren Engine-Skalierung ungeklärt ist (B33).
6. **Low-Profil = Mobile-Realität** (B3, B23, B34, B37): Rate ≤ 100/s pro Emitter, keine Schatten (die Engine schaltet
   sie unter Stufe 4 ohnehin ab), Glass-Distortion und Flipbook-lastige Layer weglassen (B7: Flipbooks werden bei
   Speicherknappheit ohnehin deaktiviert, Fallback-Textur einplanen). Partikel-Size moderat halten, weil Fill-Rate
   auf Mobile zählt (`sizeCompensation` 1.12 wirkt gegen Fill-Rate; ASSUMPTION: der Analyzer sollte den Netto-Effekt
   zeigen). **[kritisch]**
7. **`Quality.detect()`** (B27–B31): `SavedQualityLevel` per `pcall` lesen; `Automatic` (häufig) = „unbekannt“ →
   nicht pauschal High oder Medium annehmen, sondern eine **adaptive Heuristik** (IDEA): Startprofil aus Plattform
   (Touch/Mobile → Low/Medium), danach geglättete `Stats.FrameTime`/`RenderGPUFrameTime` über einige Sekunden; bei
   dauerhaft hoher Frame-Zeit eine Stufe herunter, mit Hysterese, und nur zwischen Effekten wechseln, nie mitten
   im Effekt. `GetPropertyChangedSignal("SavedQualityLevel")` für manuelle Änderungen, `GraphicsQualityChangeRequest`
   nur als Zusatzsignal (feuert nur bei F10). Mapping manuell: 1–3 → Low, 4–7 → Medium, 8–10 → High (ASSUMPTION; die
   Schwelle 4 folgt der dokumentierten Schattengrenze, die Schwelle 8 dem berichteten Glass-Limit). **[kritisch]**
8. Komponenten-Metadaten (IDEA): `minQuality` für Distortion (High), Lichter mit Schatten (High), Flipbook-Rauch
   (Medium). `qualityOverrides` für Rate- und Size-Paare.

### 4.3 Runtime-Modul

9. **Keine Debris-Nutzung**; eigenes Cleanup über den Scheduler und Pool (B44). Pool-Release mit `Parent = nil`
   ist konsistent mit dem Streaming-Verhalten (B47). Für geparkte Parts optional ein Sammel-`BulkMoveTo` (B16).
   Pool-Größe pro Effekt begrenzen; Community-Benchmarks sind nicht belastbar (B45), eigene Messung in Phase 6.
10. **Property-Writes minimieren** (B5/B6): Der „skip identical writes“-Grundsatz (COMPONENTS_SPEC §0) ist richtig.
    Zusätzlich keine per-Frame-Kurven auf ParticleEmitter-Properties wie `Rate` oder `Color`, wenn sich das über
    Sequences (Lebenszeit) ausdrücken lässt. Emitter möglichst nicht jeden Frame bewegen. Eine Analyzer-Warnung bei
    Kanälen auf Emitter-Properties. **[kritisch]**
11. **Träger-Parts**: `CastShadow = false`, `CanCollide/CanTouch/CanQuery = false`, `Anchored = true`,
    `Transparency = 1` (B18, B24). Das bestätigt den Ansatz in `api-geometry-lighting-tween.md`. VFX-Geometrie mit
    Teiltransparenz sparsam und kurz halten (B19).
12. **Texturen vorwärmen** (B10): `AstraVFX.Preload` sollte neben dem Pool auch `ContentProvider:PreloadAsync` auf
    die Effekt-Instanzen aufrufen. Weil die Engine vorgeladene, unsichtbare Texturen wieder entladen kann, ist ein
    kurzer unsichtbarer „Warm-up“-Emit beim ersten Play denkbar (IDEA, muss gemessen werden).
13. **Highlights wiederverwenden** (A27): Flash-, Impact-Frame- und Treffer-Highlights als vorab angelegte Instanzen,
    nur `Enabled` und Farben ändern. Pro Client eine kleine Highlight-Pool-Obergrenze (≪ 255).
14. **Trails**: Weil die Lifetime laut Berichten FPS-abhängig ist (B14), sollte die Preview auf unterschiedlichen
    FPS geprüft werden; optional eine dt-Kompensation (IDEA, erst nach Verifikation).
15. **Kamera-Effekte als eigene, opt-out-fähige Spur** (IDEA, gestützt auf A23–A26): `cameraShake` (Trauma-Modell
    mit Perlin-Noise, Stärke ∝ Trauma², Distanzabfall zur Kamera, globaler Spieler-Multiplikator 0..1),
    `hitStop` (nur als Event/Marker, weil Gameplay-Zeit Sache des Spiels ist), `impactFrame` (ColorCorrection plus
    gepoolte Highlights, 1–3 Frames, mit Hinweis, dass Partikel unter ColorCorrection verschwinden können).
    Standardmäßig gedämpft.

### 4.4 Net-Schicht (Abgleich mit ARCHITECTURE §5.3 `AstraVFX.Net`)

16. Das Design „Server spielt nichts, Clients rendern“ entspricht der offiziellen Empfehlung (B48). Beibehalten,
    dazu ein Lint im Analyzer: Warnung, wenn `AstraVFX.Play` auf dem Server ohne `Net` aufgerufen wird. **[kritisch]**
17. **`Attach` als Instanzreferenz** (B54–B56): Unter Streaming kann sie `nil` sein oder später kommen. Der geplante
    CFrame-Fallback ist richtig; zusätzlich (IDEA) eine optionale Attach-ID (Attribut, z. B. `AstraAttachId`) mit
    kurzem `WaitForChild`-Timeout. Danach mit dem gesendeten CFrame spielen, nicht warten. Ist das Ziel ausgestreamt,
    weiter mit dem letzten CFrame laufen (Positionswerte können veraltet sein). Effekte, die lokal an
    server-eigene Instanzen gehängt werden, können beim Ausstreamen verschwinden. Deshalb Effekt-Root als eigenes,
    lokales Part in Workspace (oder Camera) und das Ziel per CFrame verfolgen, statt das Effekt-Modell unter das
    Server-Part zu hängen. **[kritisch]**
18. **Unreliable-Pfad** (B50–B52): Payload-Budget im Code **≤ 900 Bytes** (konservativ, unter dem offiziellen
    Wert von 1000), kompakt kodieren (Effekt-ID als kleiner Integer statt Name, Position als 3 Zahlen bzw. Buffer).
    Bei Überschreitung automatisch auf das zuverlässige RemoteEvent ausweichen. Sequenznummer oder Servertime
    mitsenden, damit Clients veraltete Ereignisse verwerfen (z. B. älter als 0,5 s; ASSUMPTION). Unreliable nur
    für rein kosmetische, ersetzbare Effekte (Treffer-Funken), nie für Effekte mit Gameplay-Bedeutung
    (Telegraphs!). **[kritisch]**
19. `PlayNear`: serverseitige Distanzfilterung spart Traffic. Unter Streaming erhalten weit entfernte Clients
    ohnehin keine Instanzen (B57), passt also.
20. Kein Client→Server-Pfad im Modul (wie geplant). Spiele, die Client-Auslösung wollen, brauchen eigene
    Validierung (B58). In der Doku auf den Throttle von 500/s pro Client hinweisen (B52).

### 4.5 Presets, Lehrinhalte, Claude-Generierung

21. Presets nach dem **Phasenmodell** strukturieren (A1–A5): Spuren „anticipation/charge“, „impact“ (Flash +
    Burst), „secondary“ (Sparks/Debris/Shockwave), „dissipation“ (Rauch/Fade). Marker `Impact` als Anker für
    Gameplay-Events. Das macht Effekte für Claude Code beim Generieren und Bearbeiten nachvollziehbar (IDEA).
22. **Design-Lints** für generierte Effekte (IDEA, heuristisch): Fehlt ein Flash oder Peak am Impact-Marker? Ist
    der Peak länger als ca. 5 Frames (zu weich)? Sind alle Layer gleich lang (kein Kontrast in der Geschwindigkeit)?
    Hat der hellste Wert keinen Fokus (alle Layer weiß)? Gibt es reines Weiß in Nicht-Ultimate-Presets? Fehlt eine
    Dissipation? Sind die Werte als „Stilhinweise“ und nicht als Fehler zu kennzeichnen?
23. Rezepttabelle 2.7 als Startwerte in `src/Presets` (R1/R2 aus offiziellen Tutorials; R3–R10 als
    REPORTED/ASSUMPTION markiert, im Preset-Metadatenfeld `notes` vermerken).
24. Farb-Hilfen im Inspector (IDEA, aus A13–A17): Paletten-Vorlage „Kern hell → Rand gesättigt → Ende dunkel“ für
    additive Emitter. Warnhinweis, wenn `LightEmission = 1` und die Farbe dunkel ist (wirkt transparent).

---

## 5. Offene Fragen

1. Skaliert die Engine `Rate` (aktuell) und `Emit(n)` nach Grafikqualität und/oder Kameradistanz? Wie sind die
   aktuellen globalen Partikel-Caps? → Test auf echten Geräten (Mobile Low vs. PC Max) mit `Stats` und Zählung im
   Play-Test.
2. Genaues Beam-LOD: Teiler pro Stufe, Mindestwert, Einfluss der Distanz? Gibt es eine Obergrenze für
   `Beam.Segments`?
3. Funktioniert `SceneAnalysisService` (und `GetTriangleCompositionAsync`) in Live-Spielen oder nur in Studio?
   Wie teuer ist ein Aufruf?
4. Wie verhalten sich `RenderCPUFrameTime`/`RenderGPUFrameTime` auf Mobile (Messgenauigkeit, Verzögerung)? Taugen
   sie als Auto-Qualitätssignal?
5. Offizielles Mapping Slider 1–10 ↔ `QualityLevel` 1–21? Welche Stufe nutzt Studio im Play-Test standardmäßig?
6. Wie sieht ein Flipbook-Emitter aus, wenn der Client Flipbooks wegen Speichermangels deaktiviert (erster Frame,
   ganze Textur, unsichtbar)?
7. Ist die Trail-Lifetime-FPS-Abhängigkeit in 0.745 noch vorhanden?
8. ForceField-Material auf Part-Zylindern (Shockwave-Default) und SpecialMeshes: Tritt der gemeldete „sieht zur
   Laufzeit wie Neon aus“-Bug auch dort auf, oder nur bei MeshParts?
9. Gilt der Hinweis zur Glass-Distortion (nicht auf Mobile, ≥ 8) noch? Wird `Transparency > 1` weiter akzeptiert?
10. Wie stark kosten `Highlight` + `ColorCorrectionEffect` für Impact Frames auf Mobile, wenn sie nur 1–3 Frames
    aktiv sind (erste Highlight-Kosten ≈ 1 ms GPU laut Doku)?
11. Reale Payload-Kosten für `buffer` und typische ASTRA-Net-Nachrichten im UnreliableRemoteEvent (Studio-Output
    meldet Überschreitungen)?
12. Belastbare Zahlen zu Shockwave-Dauer und Partikelanzahlen je Effekttyp: Lassen sie sich aus eigenen
    Messungen oder einer Analyse veröffentlichter Effekte gewinnen (ohne fremde Assets zu kopieren)?

---

## 6. Quellen

### Offizielle Doku (VERIFIED) – Quelltext jeweils unter `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/<pfad>`

- [D-Improve] https://create.roblox.com/docs/performance-optimization/improve (`performance-optimization/improve.md`)
- [D-Design] https://create.roblox.com/docs/performance-optimization/design
- [D-Identify] https://create.roblox.com/docs/performance-optimization/identify
- [D-TestHW] https://create.roblox.com/docs/performance-optimization/test-on-hardware
- [D-SceneAnalysis] https://create.roblox.com/docs/performance-optimization/scene-analysis
- [D-MP] https://create.roblox.com/docs/performance-optimization/microprofiler
- [D-MPTags] https://create.roblox.com/docs/performance-optimization/microprofiler/tag-table
- [D-Analytics] https://create.roblox.com/docs/production/analytics/performance
- [D-Particles] https://create.roblox.com/docs/effects/particle-emitters
- [D-Beams] https://create.roblox.com/docs/effects/beams
- [D-Highlight] https://create.roblox.com/docs/effects/highlighting
- [D-PostFX] https://create.roblox.com/docs/environment/post-processing-effects
- [D-EnvOpt] https://create.roblox.com/docs/tutorials/curriculums/environmental-art/optimize-your-experience
- [D-TutExplosion] https://create.roblox.com/docs/tutorials/use-case-tutorials/vfx/use-particles-for-explosions
- [D-TutBasicVFX] https://create.roblox.com/docs/tutorials/curriculums/core/building/create-basic-visual-effects
- [D-Artist] https://create.roblox.com/docs/tutorials/curriculums/artist/work-with-particle-emitters
- [D-Remote] https://create.roblox.com/docs/scripting/events/remote
- [D-URE] https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent
- [D-RE] https://create.roblox.com/docs/reference/engine/classes/RemoteEvent
- [D-Stream] https://create.roblox.com/docs/workspace/streaming
- [D-StreamTech] https://create.roblox.com/docs/workspace/streaming/techniques
- [D-Stats] https://create.roblox.com/docs/reference/engine/classes/Stats
- [D-UGS] https://create.roblox.com/docs/reference/engine/classes/UserGameSettings
- [D-SQS] https://create.roblox.com/docs/reference/engine/enums/SavedQualitySetting
- [D-GOM] https://create.roblox.com/docs/reference/engine/enums/GraphicsOptimizationMode
- [D-DataModel] https://create.roblox.com/docs/reference/engine/classes/DataModel (Event `GraphicsQualityChangeRequest`)
- [D-RenderSettings] https://create.roblox.com/docs/reference/engine/classes/RenderSettings
- [D-WorldRoot] https://create.roblox.com/docs/reference/engine/classes/WorldRoot (BulkMoveTo)
- [D-BulkMoveMode] https://create.roblox.com/docs/reference/engine/enums/BulkMoveMode
- [D-SceneAnalysisSvc] https://create.roblox.com/docs/reference/engine/classes/SceneAnalysisService
- [D-Debris] https://create.roblox.com/docs/reference/engine/classes/Debris
- [D-ContentProvider] https://create.roblox.com/docs/reference/engine/classes/ContentProvider
- [D-PE] https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter
- [D-Beam] https://create.roblox.com/docs/reference/engine/classes/Beam
- [D-BasePart] https://create.roblox.com/docs/reference/engine/classes/BasePart
- [D-Bloom] https://create.roblox.com/docs/reference/engine/classes/BloomEffect
- [D-SpecialMesh] https://create.roblox.com/docs/reference/engine/classes/SpecialMesh , https://create.roblox.com/docs/reference/engine/classes/DataModelMesh
- [D-Easing] https://create.roblox.com/docs/reference/engine/enums/EasingStyle
- [D-debug] https://create.roblox.com/docs/reference/engine/libraries/debug
- [D-RunService] https://create.roblox.com/docs/reference/engine/classes/RunService
- [D-StepFrequency] https://create.roblox.com/docs/reference/engine/enums/StepFrequency
- [API] lokal: `/root/tools/ref/Full-API-Dump.json`, `/root/tools/ref/API-Dump.json`, `/root/tools/ref/globalTypes.d.luau` (0.745.0.7451137)

### Roblox-Community (REPORTED)

- [F-GQRate] https://devforum.roblox.com/t/graphics-quality-lowering-particle-emission-rates/1241979
- [F-RateBug] https://devforum.roblox.com/t/particle-emitters-no-longer-change-rate-with-graphics-quality/4834736
- [F-EmitLimit] https://devforum.roblox.com/t/particle-emitter-limit-on-low-graphics-is-impacting-my-game/2159584
- [F-IgnoreGQ] https://devforum.roblox.com/t/a-way-to-make-particleemitter-rate-ignore-graphics-quality/474762 , https://devforum.roblox.com/t/graphics-quality-affects-particle-emitters/2657543
- [F-OptLowGfx] https://devforum.roblox.com/t/how-to-optimize-vfx-and-retain-quality-at-low-graphics/2804870
- [F-LODBypass] https://devforum.roblox.com/t/bypassing-particle-lod-rate-throttle/2446042 , https://devforum.roblox.com/t/particlefix-steady-particle-emission-rate/339946
- [F-BeamLOD] https://devforum.roblox.com/t/beam-optimization-is-wronglypoorly-implemented/2939171 , https://devforum.roblox.com/t/beams-effects-gets-reduced-at-lower-graphics/1732819 , https://devforum.roblox.com/t/being-able-to-force-the-amount-of-segments-or-lod-for-beams/82214
- [F-PEPerf] https://devforum.roblox.com/t/improve-the-performance-of-particleemitters/3547121
- [F-EmitClose] https://devforum.roblox.com/t/particleemitteremit-causes-huge-lag-spikes-when-camera-is-close-to-particleemitter/2543010 , https://devforum.roblox.com/t/insane-gpu-utulization-issue-when-camera-is-inside-or-player-is-near-particle-effects/3051577
- [F-TexDelay] https://devforum.roblox.com/t/significant-delay-on-displaying-particle-effects-even-after-first-load-and-on-repeated-reuse/2718982
- [F-TrailFPS] https://devforum.roblox.com/t/trail-lifetime-is-tied-to-fps/821708
- [F-TrailLag] https://devforum.roblox.com/t/creating-longer-trails-w-parts-beams/2784082
- [F-PartCache] https://devforum.roblox.com/t/partcache-for-all-your-quick-part-creation-needs/246641 , https://devforum.roblox.com/t/part-pooling-increase-performance-with-many-parts/518433
- [F-ObjectCache] https://devforum.roblox.com/t/objectcache-a-modern-blazing-fast-model-and-part-cache/3104112 , https://devforum.roblox.com/t/genericpool-high-performance-instance-pooling-update-11/3952399
- [F-BulkMove] https://devforum.roblox.com/t/bulkmoveto-vs-normal-cframe-ing/1278502 , https://devforum.roblox.com/t/how-we-are-developing-an-rts-game-with-good-performance-for-more-than-200-units/3281168
- [F-Debris] https://devforum.roblox.com/t/hello-ive-been-wondering-if-its-better-to-use-debrisadditem-or-taskdelay/2997135 , https://devforum.roblox.com/t/debrisgobbler-a-much-more-performant-alternative-to-debrisservice/2184366
- [F-ClientRep] https://devforum.roblox.com/t/client-replication-101-the-guide-to-replicating-effects-to-clients/1789487 , https://devforum.roblox.com/t/need-help-on-client-sided-replication-for-vfx/2503157 , https://devforum.roblox.com/t/how-should-i-prevent-exploiters-spamming-my-remoteevent-for-vfx-replication/4749010
- [F-URE] https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155 , https://devforum.roblox.com/t/what-are-real-limits-of-data-being-sent-when-using-unreliableremoteevent/3038324 , https://devforum.roblox.com/t/incorrect-size-of-data-being-sent-limit-specified-when-using-unreliableremoteevent/3048788 , https://devforum.roblox.com/t/unreliable-remote-events-for-visuals/3072430
- [F-50KB] https://devforum.roblox.com/t/does-the-50kbps-data-limit-only-apply-to-remote-events-or-also-server-side-object-creation/580567 , https://devforum.roblox.com/t/remote-limits-per-remote-or-overall-whered-the-limit-even-come-from/2873609
- [F-StreamNil] https://devforum.roblox.com/t/part-is-null-on-the-client/3177820 , https://devforum.roblox.com/t/hitbox-supposedly-doesnt-exist-when-sent-to-the-client/3395374
- [F-Future] https://devforum.roblox.com/t/severe-fps-drops-due-to-aggressive-shadow-recalculations-during-object-movementappearance/3875739 , https://devforum.roblox.com/t/very-poor-performance-with-future-lighting-technology/1439704
- [F-GQDetect] https://devforum.roblox.com/t/need-a-way-to-detect-effective-graphics-level/2719633 , https://devforum.roblox.com/t/ability-to-query-the-savedqualitylevel-when-its-set-to-auto/2947801 , https://devforum.roblox.com/t/how-would-i-read-the-localplayers-current-graphics-level-and-detect-when-it-is-changed/81935
- [F-FRMTable] https://fastflagforge.github.io/Docs/fast-flags/graphical-settings (inoffiziell)
- [F-QLDocReq] https://devforum.roblox.com/t/we-need-documentation-on-edit-quality-level-and-quality-level/792183
- [F-Glass] https://devforum.roblox.com/t/hidden-glass-distortion-effect-with-real-time-reflections-tutorial/2338789 , https://devforum.roblox.com/t/glass-refraction-effect-breaks-at-high-transparency-values/2319086 , https://devforum.roblox.com/t/separate-the-glass-materials-distortion-effect-from-its-transparency/2940835
- [F-FF] https://devforum.roblox.com/t/control-the-fresnel-effect-of-forcefield-material-using-the-reflection-property/258289 , https://devforum.roblox.com/t/documentation-regarding-the-new-force-field-material/280851 , https://devforum.roblox.com/t/why-does-this-forcefield-material-meshpart-look-different-at-runtime/2392057
- [F-Bloom] https://devforum.roblox.com/t/how-to-have-functioning-emissive-textures/319192
- [F-Runup] https://devforum.roblox.com/t/runup-vfx-breakdown-part-4/3669430
- [F-ImpactFrame] https://devforum.roblox.com/t/advanced-impact-frames/2468478 , https://devforum.roblox.com/t/open-source-impactframe-module/2963136 , https://devforum.roblox.com/t/2652420
- [F-CamShake] https://devforum.roblox.com/t/ez-camera-shake-ported-to-roblox/98482 , https://github.com/Sleitnick/RbxCameraShaker , https://devforum.roblox.com/t/camerashakeupdated-simple-camerascreen-shaking-module/3621709 , https://devforum.roblox.com/t/gg-camera-shake-screenshake-that-doesnt-suck/4731267
- [F-Lightning] https://devforum.roblox.com/t/effect-v11-lightning-beams-seamless-smooth-and-procedurally-animated-with-beam-like-properties/843534 , https://devforum.roblox.com/t/how-to-make-an-lighting-bolt-effect/1516280
- [F-Slash] https://devforum.roblox.com/t/crecent-sword-slash-effect/1113871 , https://devforum.roblox.com/t/creating-an-unkown-sword-slash-effect/927925 , https://youtubesummary.com/summary/zlKdwujvP2A (Video: https://www.youtube.com/watch?v=zlKdwujvP2A)
- [F-Shockwave] https://devforum.roblox.com/t/how-do-i-prevent-mesh-distortion/3172303 , https://devforum.roblox.com/t/how-could-i-recreate-this-effect/2131510 , https://devforum.roblox.com/t/battlegrounds-crater-module/3370194
- [F-Dome] https://devforum.roblox.com/t/how-to-make-a-creating-domain-expansion-effect/2863076
- [F-Charge] Such-Snippet zu Charge-up-Mustern (DevForum-Thread [F-Dome] und generische Guides; geringe Autorität)
- [F-MeshFlip] https://devforum.roblox.com/t/open-source-mesh-flipbook-pack/3635032 , https://devforum.roblox.com/t/what-are-mesh-flipbooks/2656999
- [F-AnimeGuide] https://devforum.roblox.com/t/full-beginners-guide-on-scripting-animefighting-vfxvisual-effects-part-1/1610853
- [F-IntroVFX] https://devforum.roblox.com/t/introduction-to-vfx-particles/2068650
- [F-LearnVFX] https://devforum.roblox.com/t/how-can-i-learn-vfx/2805022 , https://devforum.roblox.com/t/what-are-good-ways-to-learn-vfx/725749
- [F-Easing] https://devforum.roblox.com/t/understanding-easing-styles/937281
- [F-Tripo] https://www.tripo3d.ai/blog/roblox-vfx (geringe Autorität)

### Allgemeines Game-VFX-Handwerk (REPORTED)

- [G-LoLGuide] https://nexus.leagueoflegends.com/en-us/2017/10/dev-leagues-vfx-style-guide/ (PDF: https://nexus.leagueoflegends.com/wp-content/uploads/2017/10/VFX_Styleguide_final_public_hidpjqwx7lqyx0pjj3ss.pdf), https://www.vfxapprentice.com/blog/10-league-of-legends-vfx-design-tips
- [G-LoLMissile] https://realtimevfx.com/t/anatomy-of-a-league-of-legends-missile-part-1-creating-areas-of-focus/11614 , https://realtimevfx.com/t/anatomy-of-a-league-of-legends-missile-part-2-what-are-we-communicating-with-our-vfx/13062
- [G-GDC2017] https://gdcvault.com/play/1023943/Visual-Effects-Bootcamp-Artistic-Principles , https://3dreference.notion.site/Visual-Effects-Bootcamp-Artistic-Principles-of-VFX-GDC-2017-fcd0698c31cf4621a70ed8a7621e17da
- [G-Timing] https://www.vfxapprentice.com/blog/the-soul-of-effects-what-is-timing-in-vfx , https://www.vfxapprentice.com/timing-workshop-learn-vfx-timing
- [G-CA] https://creative-assembly.com/node/4446
- [G-Gil] https://gamedeveloper.com/design/vfx-as-game-design-tools-the-ludology-of-vfx-in-god-of-war-ragnarok-and-halo-infinite
- [G-Explosion] https://realtimevfx.com/t/stylized-frag-launcher-explosion-overwatch-inspiration-breakdown-posted/1894 , https://simonschreibt.de/gat/battlefront-ii-layered-explosion/ , https://realtimevfx.com/t/custom-explosion-feedback/16005 , https://realtimevfx.com/t/explosion-effect-help-needed/16021 , https://www.pcgamer.com/how-great-game-explosions-are-made
- [G-RTVFXColor] https://realtimevfx.com/t/diving-into-color-tips-tricks-i-use-for-using-color/16220 , https://www.vfxapprentice.com/blog/color-101-vfx-artists
- [G-HitStop] https://game.capcom.com/cfn/sfv/column/131545?lang=en , https://www.scitepress.org/Papers/2024/124614/124614.pdf , https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/ , https://uhiyama-lab.com/en/notes/unity/unity-game-feel-hit-feedback/
- [G-Shake] https://bevy.org/examples/camera/2d-screen-shake/ , https://kidscancode.org/godot_recipes/3.x/2d/screen_shake/ (Sekundärquellen zu Eiserloh, GDC 2016 „Juicing Your Cameras With Math“)
- [G-Readable] https://gdcvault.com/play/1034360/Attention-Overload-Creating-Readable-VFX , https://leagueoflegends.com/en-au/news/dev/dev-behind-the-scenes-of-vfx-updates
- [G-Telegraph] https://gamineai.com/blog/top-down-combat-vfx-readability-2026-color-timing-system-busy-screens (geringe Autorität)
- [G-FF7] https://studios-groundzero.pages.dev/journal/breakdowns/final-fantasy-vii (geringe Autorität)
- [G-Anim] https://playbooks.com/skills/dylantarre/animation-principles/rhythm-pacing (KI-generierte Skill-Seite, geringe Autorität)
- [G-ImpactFrames] https://www.arhfoundation.org/impact-frames-meaning (geringe Autorität), https://80.lv/articles/my-hero-academia-style-attack-vfx-in-unreal-engine-5
