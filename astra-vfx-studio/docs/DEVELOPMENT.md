# Entwicklung – Arbeitsweise, Befehle, Konventionen

Dieses Dokument richtet sich an alle, die am Code von ASTRA VFX Studio arbeiten (Menschen und Coding-Agenten).

## Werkzeuge

| Werkzeug | Version | Zweck |
|---|---|---|
| Rojo | 7.7.1 | Plugin/Runtime bauen (`rojo build`), optional Live-Sync |
| Lune | 0.11.1 | Tests, CLI, Bridge (Luau außerhalb von Roblox) |
| Selene | 0.31.0 | Lint (`selene.toml`, Roblox-Globals in `astra.yml`) |
| StyLua | 2.6.0 | Formatierung (`stylua.toml`) |
| astra-analyze | 0.1.0 | Luau-Typprüfung gegen Roblox-API-Definitionen ([tools/analyzer](../tools/analyzer/README.md)) |

Installation über [Rokit](https://github.com/rojo-rbx/rokit): `rokit install` (liest `rokit.toml`). `astra-analyze`
wird aus `tools/analyzer` gebaut (siehe dortige README).

## Befehle (im Ordner `astra-vfx-studio/`)

```bash
tools/check.sh                                   # alles: Syntax, Tests, Typen, Lint, Format, Builds
tools/check.sh --quick                           # nur Syntax + Tests
lune run tests/lune/run.luau                     # alle Tests
lune run tests/lune/run.luau -- Json             # nur Tests, deren Name "Json" enthält
lune run tests/lune/run.luau -- --verbose        # jeden Test auflisten
astra-analyze --defs <globalTypes.d.luau> --project default.project.json   # Typprüfung
selene src tests/framework tests/specs tools     # Lint
stylua src tests tools                           # formatieren
rojo build default.project.json -o build/AstraVFXStudio.rbxmx   # Plugin bauen
rojo build runtime.project.json -o build/AstraVFX.rbxm          # Runtime-Paket bauen
rojo build examples/default.project.json -o build/AstraVFX-Examples.rbxl   # Beispiel-Place (examples/README.md)
```

Spiel-API: `docs/RUNTIME_API.md`. Automatische Tests vs. manuelles Studio-Protokoll: `docs/TESTING.md`.

In dieser Entwicklungsumgebung liegen `astra-analyze` unter `/root/tools/bin/astra-analyze` und die Roblox-Definitionen
unter `/root/tools/ref/globalTypes.d.luau` (luau-lsp, Engine 0.745); der lokale API-Dump unter
`/root/tools/ref/API-Dump.json` bzw. `Full-API-Dump.json` (mit Defaults).

## Tests schreiben

* Eine Spec-Datei pro Modul: `tests/specs/<Modul>.spec.luau`, Format wie `tests/specs/Signal.spec.luau`:
  `return function(T, use, ctx) … end`. Module holt man mit `use("AstraVFX.Core.Json")` (Pfad im Rojo-Baum).
* `ctx.environment` ist `"lune"` oder `"studio"`. Engine-Fakes (nur Lune) unter `ctx.fakes`
  (`tests/lune/Fakes.luau`): `fakes:step(dt)` feuert Heartbeat & Co., `fakes.emits` protokolliert
  `ParticleEmitter:Emit`, `fakes.sounds`, `fakes.clears`, `fakes:reset()`. `RunService:BindToRenderStep` /
  `UnbindFromRenderStep` werden in `fakes.renderBindings` und `fakes.renderLog` protokolliert, `fakes:renderStep(dt)`
  führt die Bindungen nach Priorität aus (`fakes:step` ebenfalls). Tests, die Fakes brauchen, mit
  `T.itIf(ctx.environment == "lune", …)` markieren.
* `ctx.readFile(path)` (nur Lune) liest eine Repository-Datei relativ zum Projektordner (z. B.
  `tests/fixtures/*.json`, `effects/*.vfx.json`). Ein anderes Rojo-Projekt als eigenen Instanzbaum lädt
  `ctx.loader.new(ctx.loader.projectDir .. "/examples", "default.project.json")` (siehe `Examples.spec.luau`).
* `Players.LocalPlayer` lässt sich in Lune nicht faken; Clients/Server simuliert man mit
  `Env.override("Players", { LocalPlayer = … })` bzw. `{}`. Lunes Workspace hat eine Standard-`CurrentCamera`, und
  `CurrentCamera = nil` lehnt Lune ab – Kameras deshalb über `Env.override("Workspace", { CurrentCamera = … })`.
  Lune rundet CFrame-Properties beim ersten Schreiben (~1e-5).
* Lune-Instanzen prüfen Eigenschaftsnamen und Werttypen gegen die echte Reflection-Datenbank – Tests sollen echte
  Instanzen bauen, wo sinnvoll. Lune kennt aber kein Rendering und keine Physik.
* Matcher: `toBe`, `toEqual` (tief), `toBeCloseTo(x, eps)` (auch Vector3/Color3/CFrame), `toBeNil`, `toBeTruthy`,
  `toBeFalsy`, `toThrow(substr?)`, `toContain`, `toHaveLength`, `toMatch`, `toBeGreaterThan(OrEqual)`,
  `toBeLessThan(OrEqual)`, `toBeA(typeName)`, `never.*`.

## Typisierung – bekannte Stolpersteine (astra-analyze, alter Solver)

* `local ok, err = pcall(f)` mit `f: () -> ()` meldet *CountMismatch*. Schreibweise: `pcall(f :: any, …)`.
* Parameter anonymer Funktionen in Specs annotieren, wenn mit ihnen gerechnet/verkettet wird (`use()` liefert `any`).
* `options or {}` bei optionalen Tabellenparametern: Ziel explizit typisieren (`local o: Options = options or {}`).
* `require` nur instanzrelativ (`script.Parent.X`); `script` ist im Analyzer `any`.

## Regeln

* Abhängigkeiten nur entlang der Schichten aus `docs/ARCHITECTURE.md` §2 (`src/Runtime` niemals nach außen).
* `--!strict` in jeder Datei, zentrale Typen aus `src/Runtime/Core/Types.luau`.
* Keine Roblox-APIs erfinden: im Zweifel im API-Dump nachsehen; Fakten mit Quellen in
  `docs/ROBLOX_API_CONSTRAINTS.md` bzw. `docs/research/*.md`.
* Vor dem Abschluss einer Aufgabe: `tools/check.sh` muss grün sein.
