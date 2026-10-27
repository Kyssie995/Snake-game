# astra-analyze – statischer Luau-Typecheck gegen die Roblox-API

`astra-analyze` prüft die Luau-Dateien eines Rojo-Projekts mit dem originalen Luau-Typechecker gegen die
Roblox-API-Typdefinitionen. Da Roblox Studio in der Linux-Umgebung nicht verfügbar ist, ist das unser
wichtigstes Werkzeug, um falsche Property-Namen, falsche Typen und nil-Fehler in Plugin-/Runtime-Code zu finden.

```
src/Effects/Broken.luau:10:1: error: Key 'Ratee' not found in external type 'ParticleEmitter' (did you mean 'Rate'?) [UnknownProperty]
src/Effects/Broken.luau:14:14: error: Expected this to be 'ColorSequence', but got 'Color3' [TypeMismatch]
src/Effects/Broken.luau:16:1: error: Expected this to be 'string', but got 'number' [TypeMismatch]
```

## Benutzung

```sh
# Echtes Projekt (Instanzbaum aus der Rojo-Projektdatei):
cd astra-vfx-studio
/root/tools/bin/astra-analyze --defs /root/tools/ref/globalTypes.d.luau --project default.project.json

# Alternativ: ein Quellverzeichnis ist direkt die Wurzelinstanz
/root/tools/bin/astra-analyze --defs /root/tools/ref/globalTypes.d.luau --root src/Runtime

# Nur einzelne Dateien/Verzeichnisse prüfen (Abhängigkeiten werden trotzdem geladen):
/root/tools/bin/astra-analyze --defs /root/tools/ref/globalTypes.d.luau --project default.project.json src/Runtime/Core
```

```
astra-analyze --defs <globalTypes.d.luau> (--root <dir> | --project <default.project.json>) [Optionen] [Pfade...]
```

| Option | Bedeutung |
|---|---|
| `--defs <datei>` | Roblox-Definitionsdatei im luau-lsp-Format (Pflicht) |
| `--project <datei>` | Rojo-Projektdatei; `$path` ist relativ zum Verzeichnis der Projektdatei. Ersetzt `--root` |
| `--root <dir>` | Quellverzeichnis; das Verzeichnis selbst ist die Wurzelinstanz |
| `Pfade...` | Dateien oder Verzeichnisse; Standard: alle Luau-Skripte im Instanzbaum |
| `--json` | maschinenlesbare Ausgabe auf stdout (`diagnostics[]` mit `file, line, column, endLine, endColumn, severity, code, message`, plus `summary`) |
| `--strict` / `--mode=strict` | Dateien ohne `--!strict`/`--!nonstrict` strict prüfen (Standard: nonstrict bzw. `.luaurc`) |
| `--force-strict` | jede Datei strict prüfen, auch mit `--!nonstrict`/`--!nocheck` |
| `--solver=old\|new` | Luau-Solver (Standard `old`, siehe unten) |
| `--no-lint` | keine Lint-Warnungen |
| `--warnings-as-errors` | Exit-Code 1 auch bei reinen Warnungen |
| `--script-typed` | `script` nicht als `any` typisieren |
| `--no-datamodel-services` | keine `game.Players`/`game.ReplicatedStorage`/…-Abkürzungen |
| `--fflags=Name=true,Name2=123` | Luau-Fast-Flags (bool und int) setzen |
| `-jN` | Anzahl Worker-Threads (Standard: min(Kerne, 8)) |
| `--dump-tree` | den berechneten Instanzbaum ausgeben (braucht kein `--defs`) |
| `--quiet` | keine Zusammenfassung auf stderr |

Ausgabeformat: `datei:zeile:spalte: error|warning: meldung [Code]` auf stdout (Typfehler/Syntaxfehler =
`error`, Lints = `warning`, außer `.luaurc` stuft sie als Fehler ein). Exit-Code: `0` keine Fehler, `1` Fehler
gefunden, `2` Aufruf- oder Definitionsdatei-Fehler.

Datei-Modi: `--!strict`, `--!nonstrict`, `--!nocheck` pro Datei sowie `.luaurc` (`languageMode`, `lint`, …)
werden wie in Luau ausgewertet. **Empfehlung: alle Dateien `--!strict`** (bzw. `.luaurc` mit
`"languageMode": "strict"`, wie im Projekt vorhanden). Im nonstrict-Modus sind unannotierte Locals beim alten
Solver `any`, beim neuen Solver werden nur sichere Laufzeitfehler gemeldet – dort fällt z.B. `local w = workspace;
w.Foo = 1` nicht auf.

## Was geprüft wird

* **Roblox-API** aus `globalTypes.d.luau` im globalen Scope (`Frontend::loadDefinitionFile`): `game`,
  `workspace`, `plugin` (Klasse `Plugin`), `Enum`, `task`, Datentypen (`Color3`, `NumberSequence`, `TweenInfo`,
  `CFrame`, …), alle Klassen mit Properties, Methoden und Events, `@deprecated`-Markierungen (Lint `DeprecatedApi`).
* **Magische Funktionen wie in luau-lsp** (die Definitionsdatei deklariert z.B. nur
  `Instance.new(className: string): Instance`; luau-lsp ergänzt die Typen zur Laufzeit, das wird hier nachgebaut,
  für beide Solver):
  `Instance.new("ParticleEmitter")` → `ParticleEmitter` (ungültige/nicht erzeugbare Klassennamen sind Fehler, mit
  Vorschlag), `game:GetService("TweenService")` → `TweenService` (ungültige Service-Namen sind Fehler),
  `x:IsA("BasePart")` verfeinert `x` zu `BasePart`, `FindFirstChildWhichIsA`/`FindFirstChildOfClass`/
  `FindFirstAncestorWhichIsA`/`FindFirstAncestorOfClass` → `Klasse?`, `inst:Clone()` → Typ von `inst`,
  `GetPropertyChangedSignal("Prop")` prüft, ob die Property existiert.
* `Enum.Material` etc. als **Typannotation** (`(state: Enum.PlaybackState)`), wie in Studio.
* `game.Players`, `game.ReplicatedStorage`, `game.Lighting`, … (feste Liste immer vorhandener Services) sind
  als Properties von `DataModel` verfügbar.
* `script` ist `any` (Navigation wie `script.Parent.Types` erzeugt keine Fehler).
* Bei `UnknownProperty` wird der ähnlichste Name vorgeschlagen (`did you mean 'Rate'?`).

### require-Auflösung (Rojo-Konventionen)

Instanz-Requires werden über den Instanzbaum aufgelöst; die **Rückgabetypen der Module werden über die
Requires hinweg übernommen** (inkl. exportierter Typen, `typeof(require(...))`, Zyklen-Erkennung).

| Datei/Verzeichnis | Instanz |
|---|---|
| Verzeichnis | `Folder` |
| Verzeichnis mit `init.luau` | das Verzeichnis **ist** das ModuleScript, übrige Einträge sind Kinder |
| Verzeichnis mit `init.server.luau` / `init.client.luau` | `Script` / `LocalScript` |
| Verzeichnis mit `default.project.json` | verschachteltes Projekt |
| `X.luau` | `ModuleScript` `X` |
| `X.server.luau` / `X.client.luau` | `Script` / `LocalScript` `X` (require → Fehler „not a ModuleScript“) |
| `X.json`, `X.toml` | `ModuleScript` `X`, Typ `any` |
| `X.project.json` | verschachteltes Projekt `X` |
| `X.model.json`, `X.rbxm(x)`, `X.txt`, `X.csv` | Instanz `X` (nicht require-bar) |
| `*.meta.json`, versteckte Dateien | ignoriert |

`.lua` ist überall gleichwertig zu `.luau`. Unterstützte Ausdrücke (auch über lokale Variablen):
`script`, `.Parent`, `.Name`, `["Name mit Leerzeichen"]`, `:WaitForChild("Name")`, `:FindFirstChild("Name")`.
Nicht existierende Kinder sind in jedem Modus ein Fehler
(`Unknown require: 'DoesNotExist' is not a child of ModuleScript 'Effects' …`).

**`--project`** (Teilmenge des Rojo-Formats): verschachtelte Baumknoten, Schlüssel = Instanzname, `$path`
(Datei oder Verzeichnis, auch `{"optional": "…"}`) und `$className`. Der Instanzname eines `$path`-Knotens ist sein
Schlüssel, nicht der Verzeichnisname. Im echten Projekt ist z.B. `src/Runtime` die Instanz `AstraVFX`, daher
löst `require(script.Parent.Parent.AstraVFX.Core.Types)` aus `src/Authoring` zu `src/Runtime/Core/Types.luau` auf,
während `…Parent.Runtime…` ein Fehler ist. `Tests` ist ein reiner `$className`-Folder mit den Kindern `Framework`
(Einzeldatei `tests/framework/TestFramework.luau`) und `Specs` (Verzeichnis `tests/specs`). Ohne Pfadangaben werden
alle Luau-Skripte geprüft, die im Baum vorkommen (z.B. nicht `tests/lune/*`). Andere `$`-Felder
(`$properties`, `$ignoreUnknownInstances`, …) und `globIgnorePaths` werden ignoriert.

Stand echtes Projekt (`--project default.project.json`): 6 Dateien, **0 Fehler, 0 Warnungen** (alter Solver).
Mit `--solver=new` kommen derzeit 7 Meldungen in `Core/Components/init.luau` (`<`-Vergleich im Sortier-Callback
ohne Annotation) und `tests/framework/TestFramework.luau` (strengere Inferenz des neuen Solvers).

## Bauen

Voraussetzungen: CMake ≥ 3.18, C++17-Compiler (g++ oder clang++), ein Luau-Quellbaum.

```sh
cmake -S tools/analyzer -B /root/tools/build/astra-analyze \
      -DLUAU_SOURCE_DIR=/root/tools/src-luau-analyzer-sys/luau-analyzer-sys-0.1.1/luau \
      -DCMAKE_BUILD_TYPE=Release
cmake --build /root/tools/build/astra-analyze --target astra-analyze -j4   # ca. 1,5 min auf 4 Kernen
cmake --install /root/tools/build/astra-analyze --prefix /root/tools --strip   # -> /root/tools/bin/astra-analyze
./tools/analyzer/run_fixtures.sh   # Selbsttest, siehe unten
```

Gebaut werden nur die Luau-Bibliotheken (Ast, Analysis, Config, VM, Compiler, CLI.lib), keine Luau-Tools/Tests.
Die Namen der Fehlercodes (`[TypeMismatch]` …) erzeugt CMake aus `Analysis/include/Luau/Error.h` der verwendeten
Luau-Version.

### Herkunft der Quellen

* **Luau** (MIT-Lizenz, Roblox Corporation): kompletter Quellbaum aus dem crates.io-Crate
  `luau-analyzer-sys` 0.1.1 (`/root/tools/luau-analyzer-sys.crate`, entpackt nach
  `/root/tools/src-luau-analyzer-sys/luau-analyzer-sys-0.1.1/luau`). github.com ist in der Umgebung gesperrt,
  crates.io nicht. Die Luau-Version ist im Crate nicht getaggt; es ist eine aktuelle Version mit
  `declare extern type`-Syntax und neuem Solver. Ein anderer Luau-Quellbaum (z.B. ein Release von
  github.com/luau-lang/luau) kann über `-DLUAU_SOURCE_DIR` verwendet werden, solange die Frontend-API passt.
  Der Luau-Quellbaum wird **nicht** ins Repo kopiert.
* **Abgeleiteter Code**: `src/main.cpp` basiert auf Luau `CLI/src/Analyze.cpp` (ConfigResolver, TaskScheduler,
  Grundgerüst); die MIT-Lizenznotiz steht im Dateikopf.
* **Roblox-Definitionen**: `/root/tools/ref/globalTypes.d.luau` aus dem luau-lsp-Projekt (main-Branch,
  Roblox-Engine 0.745 laut `/root/tools/ref/version.txt`, inkl. Plugin-APIs). Die Datei lädt mit dieser
  Luau-Version **ohne Vorverarbeitung**; es gibt daher kein Patch-Skript. Einzige Besonderheit: beim Laden
  scheitert Luau am Standard-Limit `LuauTarjanChildLimit` (10000) mit „Code is too complex“, deshalb wird das
  Limit nur während `loadDefinitionFile` aufgehoben. Die Metadatenzeile `--#METADATA#` (Listen der erzeugbaren
  Klassen und Services) wird für `Instance.new`/`GetService` ausgewertet. `/root/tools/ref/API-Dump.json` wird
  nicht benötigt.

## Fixtures / Selbsttest

`fixtures/` ist ein kleines Rojo-Projekt (`src/init.luau` als Wurzelmodul, `Shared/` als Folder, `Shared/Util/`
als Verzeichnis-Modul mit Kind, `.lua`-Datei, JSON-Modul, Server-Skript mit `plugin`, nonstrict-Datei) plus
`default.project.json` für den `--project`-Modus.

* `src/Effects/Spark.luau` verwendet ParticleEmitter, Beam, TweenService, Color3, ColorSequence,
  NumberSequence, IsA-Verfeinerung, FindFirstChildWhichIsA, Clone, GetPropertyChangedSignal korrekt → 0 Fehler.
* `src/Effects/Broken.luau` enthält absichtlich 12 Fehlerstellen (Tippfehler in Property, falscher Typ,
  modulübergreifender Typfehler, fehlendes Feld eines anderen Moduls, nil-Zugriff, ungültiger Klassen-/Service-Name,
  fehlendes Modul, …), jede mit `-- EXPECT <Code>` markiert.
* `project/Misnamed.luau` benutzt den Verzeichnisnamen statt des Instanznamens → `UnknownRequire`.

`run_fixtures.sh` prüft für beide Solver: gute Dateien ohne Diagnosen und Exit 0; im Gesamtlauf Exit 1 und die
Menge (Datei, Zeile, Code) aller Fehler exakt gleich den `EXPECT`-Markierungen; erwartete Textfragmente;
`--!nonstrict` vs. `--force-strict`; gültiges `--json`; `--project`-Modus. Binary/Definitionen lassen sich über
`ASTRA_ANALYZE` und `ASTRA_DEFS` überschreiben.

## Laufzeit

Das Laden der ~20 000 Zeilen Definitionen dauert ca. 1,6–1,9 s pro Aufruf (ohne Cache). Die eigentliche Prüfung
ist schnell: 400 generierte strict-Module (~11 000 Zeilen, gegenseitige Requires) brauchen zusätzlich
ca. 0,1–0,25 s; das echte Projekt und die Fixtures dauern insgesamt ~2 s.

## Einschränkungen

* **Nur `script`-basierte Requires.** Nicht aufgelöst werden `require(game:GetService("ReplicatedStorage").X)`,
  `require(game.ReplicatedStorage.X)`, String-Requires (`require("./x")`, `@alias`), Asset-IDs und dynamische
  Namen. Ebenso Pfade, die den Baum nach oben verlassen. Solche Requires sind in strict-Dateien ein Fehler
  `Unknown require: unsupported path`, in nonstrict-Dateien `any`. `require(x) :: any` ist der Ausweg.
* **Kinder von Instanzen sind außerhalb von Requires unbekannt**: `workspace.Baseplate` oder
  `ReplicatedStorage.Shared` ergeben `Key 'Shared' not found in external type 'ReplicatedStorage'` (Studio kennt
  den Live-Baum, wir nicht). `:WaitForChild("…")`/`:FindFirstChild("…")` + `IsA` verwenden. Umgekehrt ist
  `script` `any`, dort wird nichts geprüft.
* Projektdateien: nur die oben genannte Teilmenge; `.meta.json` (z.B. `className`-Überschreibungen) werden
  ignoriert; Kinder von `.model.json`/`.rbxm` sind unbekannt. Doppelte Instanznamen: der erste gewinnt (Warnung).
* JSON-/TOML-Module sind `any`.
* Alter Solver: Wenn eine magische Funktion greift (z.B. `Instance.new("Part", …)`), überspringt Luau die normale
  Argumentprüfung dieses Aufrufs; nur das `parent`-Argument von `Instance.new` wird zusätzlich geprüft.
* Enum-Properties mit Strings zuzuweisen (`part.Material = "Neon"`) wird als Fehler gemeldet, obwohl Roblox das
  zur Laufzeit akzeptiert.
* Die Definitionen sind ein Schnappschuss (Engine 0.745); neuere Roblox-APIs fehlen bis zum Update der Datei.
  Wenn eine neuere `globalTypes.d.luau` Syntax nutzt, die diese Luau-Version nicht kennt, schlägt das Laden mit
  Zeilenangabe fehl (Exit 2); dann braucht es ein Vorverarbeitungsskript oder einen neueren Luau-Quellbaum.
* `--solver=new` ist strenger und meldet teils andere Dinge als der Standard-Solver; der Standard (`old`) entspricht
  dem Luau-CLI-Default dieser Version.
