# Fortschrittsbericht

Statuslegende: **I** = implementiert · **A** = automatisch getestet (Lune) · **S** = in Roblox Studio manuell getestet ·
**N** = noch nicht verifiziert. Roblox Studio ist in der Entwicklungsumgebung nicht verfügbar (Linux-Container ohne
Studio); Spalte **S** kann erst durch einen Menschen mit Studio abgehakt werden (Anleitung: `docs/TESTING.md`).

Letzte Aktualisierung: 2026-10-28 · Automatische Tests: 2152 bestanden, 0 fehlgeschlagen, 3 übersprungen

## Phase 1 – Research & Architecture

| Ergebnis | Status | Notiz |
|---|---|---|
| Recherche-Notizen (9 Themen, je unabhängig verifiziert) | I | `docs/research/*.md`; DevForum/Creator Store/YouTube nur über Suchzusammenfassungen erreichbar |
| `docs/RESEARCH.md`, `FEATURE_COMPARISON.md`, `ROBLOX_API_CONSTRAINTS.md` | I | 59 Konsequenzen (K1–K59), 46 Studio-Testpunkte (U1–U46) |
| `docs/ARCHITECTURE.md` | I | inkl. ADRs |
| `docs/MODULE_CONTRACTS.md`, `COMPONENTS_SPEC.md`, `PLUGIN_CONTRACTS.md` | I | Implementierungsverträge |

## Werkzeuge & Infrastruktur

| Ergebnis | Status | Notiz |
|---|---|---|
| Rojo-Projekte (Plugin, Runtime) | I, A | `rojo build` in `tools/check.sh` |
| Lune-Test-Harness (Rojo-Baum als echte Instanzen, Engine-Fakes) | I, A | `tests/lune/*` |
| `astra-analyze` (Luau-Typprüfung gegen Roblox-API 0.745) | I, A | `tools/analyzer` |
| `tools/check.sh` | I | Syntax, Tests, Typen, Lint, Format, Builds |

## Laufzeit (src/Runtime)

| Modul | Status |
|---|---|
| Types, Constants, Signal | I, A |
| Json, Random, Env, Codec, Easing | I, A |
| Curves, Timeline, Quality, Graph | I, A (adversarial review) |
| Komponenten (17 Typen inkl. cameraShake, screenFlash) | I, A · N (Darstellung in Studio) |
| Validation, Migration, Compiler, Builder, Player, Scheduler, Pool, API, Net | geplant |

## Plugin (src/Plugin)

| Modul | Status |
|---|---|
| UI-Fundament (Theme, New, Maid, Input) | I, A (Konstruktion) · N (Darstellung) |
| History (ChangeHistoryService), Settings | I, A (gegen Fakes) · N (Studio) |
| Widgets (26), Werte-Editoren (Farbe, Verlauf, Sequenz, Easing, Kurve) | I, A (Konstruktion + simuliertes Verhalten) · N (Darstellung) |
| Editor, Storage, Preview, Panels | geplant |

## Bekannte Einschränkungen (Auszug)

* Partikel lassen sich nicht exakt scrubben/vorspulen (Engine: kein Seed, `FastForward` gesperrt, `TimeScale` ≤ 1).
* ViewportFrame zeigt keine Partikel/Beams/Trails – die Viewport-Vorschau ist nur eine Geometrie-Vorschau.
* `MeshPart.MeshId` ist per Skript/Plugin nicht setzbar – Meshes laufen über `SpecialMesh`.
* Plugins haben keinen Zugriff auf die Zwischenablage und können keine Dateien frei schreiben.
