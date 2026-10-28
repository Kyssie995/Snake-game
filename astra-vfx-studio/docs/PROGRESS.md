# Fortschrittsbericht

Statuslegende: **I** = implementiert · **A** = automatisch getestet (Lune) · **S** = in Roblox Studio manuell getestet ·
**N** = noch nicht verifiziert. Roblox Studio ist in der Entwicklungsumgebung nicht verfügbar (Linux-Container ohne
Studio); Spalte **S** kann erst durch einen Menschen mit Studio abgehakt werden (Anleitung: `docs/TESTING.md`).

**Spalte S (Studio):** Es gab noch **keinen** manuellen Studio-Durchlauf – jeder Eintrag „ausstehend“ wartet auf die
Prüfpunkte in Klammern (IDs aus `docs/TESTING.md`: B.x Vorbereitung/Selbsttest, M‹Phase›.‹Nr› Phasen-Prüfpunkte,
U‹Nr› offene Engine-Fragen). Ergebnisse werden im Ergebnisprotokoll (`docs/TESTING.md` Teil C) eingetragen und dann
hier als „✅ ‹Datum›, Studio ‹Version›“ bzw. „❌ ‹Datum›“ übernommen. „–“ = keine Studio-Prüfung nötig.

Letzte Aktualisierung: 2026-10-28 · Automatische Tests: 2452 bestanden, 0 fehlgeschlagen, 3 übersprungen

## Phase 1 – Research & Architecture

| Ergebnis | Status | S (Studio) | Notiz |
|---|---|---|---|
| Recherche-Notizen (9 Themen, je unabhängig verifiziert) | I | – | `docs/research/*.md`; DevForum/Creator Store/YouTube nur über Suchzusammenfassungen erreichbar |
| `docs/RESEARCH.md`, `FEATURE_COMPARISON.md`, `ROBLOX_API_CONSTRAINTS.md` | I | ausstehend (U1–U46, B.7) | 59 Konsequenzen (K1–K59), 46 Studio-Testpunkte (U1–U46) |
| `docs/ARCHITECTURE.md` | I | ausstehend (U1, U4, U10: Annahmen der Vorschau) | inkl. ADRs |
| `docs/MODULE_CONTRACTS.md`, `COMPONENTS_SPEC.md`, `PLUGIN_CONTRACTS.md` | I | – | Implementierungsverträge |

## Werkzeuge & Infrastruktur

| Ergebnis | Status | S (Studio) | Notiz |
|---|---|---|---|
| Rojo-Projekte (Plugin, Runtime) | I, A | ausstehend (B.0, B.1: Builds in Studio öffnen) | `rojo build` in `tools/check.sh` |
| Lune-Test-Harness (Rojo-Baum als echte Instanzen, Engine-Fakes) | I, A | ausstehend (B.1: dieselben Specs in Studio) | `tests/lune/*`; `ctx.readFile` für Repository-Dateien |
| `astra-analyze` (Luau-Typprüfung gegen Roblox-API 0.745) | I, A | – | `tools/analyzer` |
| `tools/check.sh` | I | – | Syntax, Tests, Typen, Lint, Format, Builds |

## Laufzeit (src/Runtime)

| Modul | Status | S (Studio) |
|---|---|---|
| Types, Constants, Signal | I, A | ausstehend (B.1) |
| Json, Random, Env, Codec, Easing | I, A | ausstehend (B.1; Easing gegen `TweenService:GetValue` nur in Studio; U13, U32) |
| Curves, Timeline, Quality, Graph | I, A (adversarial review) | ausstehend (B.1, M3.3, M4.1; Quality-Zuordnung M6.4, U40) |
| Komponenten (17 Typen inkl. cameraShake, screenFlash) | I, A · N (Darstellung in Studio) | ausstehend (M3.1–M3.4, M4.3, M6.5, M6.7; U2, U3, U11–U19, U22–U25, U36, U41) |
| Validation, Migration, Compiler, Builder, Player, Scheduler, Pool, API, Net | I, A (inkl. Zeitfaktor an Engine-Uhren, Licht-Budget, `SetMaxActive`) | ausstehend (M3.3, M4.4, M4.6, M6.1–M6.6; U1, U14, U38) |

## Plugin (src/Plugin)

| Modul | Status | S (Studio) |
|---|---|---|
| UI-Fundament (Theme, New, Maid, Input) | I, A (Konstruktion) · N (Darstellung) | ausstehend (M2.1, M2.9; U6, U42) |
| History (ChangeHistoryService), Settings | I, A (gegen Fakes) · N (Studio) | ausstehend (M2.6, M2.8; U4, U5, U7–U9, U27) |
| Widgets (26), Werte-Editoren (Farbe, Verlauf, Sequenz, Easing, Kurve) | I, A (Konstruktion + simuliertes Verhalten) · N (Darstellung) | ausstehend (M2.5, M4.2; U30) |
| Editor, Storage, Preview, Panels | geplant | ausstehend (M2.2–M2.8, M3.1–M3.8, M4.4–M4.7, M5.1–M5.4; U1, U10, U19–U21, U26, U28, U29, U31) |

## Dokumentation & Beispiele

| Ergebnis | Status | S (Studio) | Notiz |
|---|---|---|---|
| `docs/RUNTIME_API.md` (Spiel-API-Referenz) | I | – | gegen den implementierten Stand von `src/Runtime/init.luau`/`Net.luau` geschrieben |
| `docs/TESTING.md` (automatische Tests, Studio-Protokoll je Phase, U1–U46, Ergebnistabelle) | I | ausstehend (erster Durchlauf, Teil C) | Abnahmekriterien markiert |
| `examples/` (Demo-Place, Server-/Client-Skript, `FireExplosion`-Demo) | I, A (`Examples.spec`, astra-analyze strict, `rojo build`) | ausstehend (M6.1–M6.3) | `build/AstraVFX-Examples.rbxl` |
| `effects/VioletImpact.vfx.json` (Konzeptbeispiel → Schema 1) | I, A (`EffectFiles.spec`) | ausstehend (M4.4, M4.6) | Original: `tests/fixtures/concept-v0.json` |

## Bekannte Einschränkungen (Auszug)

* Partikel lassen sich nicht exakt scrubben/vorspulen (Engine: kein Seed, `FastForward` gesperrt, `TimeScale` ≤ 1).
* ViewportFrame zeigt keine Partikel/Beams/Trails – die Viewport-Vorschau ist nur eine Geometrie-Vorschau.
* `MeshPart.MeshId` ist per Skript/Plugin nicht setzbar – Meshes laufen über `SpecialMesh`.
* Plugins haben keinen Zugriff auf die Zwischenablage und können keine Dateien frei schreiben.
