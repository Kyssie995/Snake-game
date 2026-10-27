# Tooling für einen AI-nativen Workflow (Claude Code ↔ Roblox Studio)

Phase-1-Recherche für ASTRA VFX STUDIO. Frage: Wie kann ein AI-Agent (Claude Code), der nur auf Dateien in einem
git-Repo arbeitet und **keinen direkten Zugriff auf Studio** hat, Effekte erzeugen/bearbeiten, die zuverlässig in
Roblox Studio (Plugin-Preview) und im veröffentlichten Spiel (Runtime-Modul) landen – ohne externe AI-API?

Stand: 2026-10-27. Engine-API-Daten: lokaler API-Dump 0.745 (`/root/tools/ref`).

**Labels:** VERIFIED = offizielle Doku / API-Dump / eigene Seite bzw. Changelog des Produkts / im Sandbox lokal
nachgestellt (Kommando angegeben) · REPORTED = Foren, Reviews, Dritte · ASSUMPTION = eigene Schlussfolgerung ·
IDEA = eigener Designvorschlag für ASTRA. **[KRITISCH]** = eine ASTRA-Architekturentscheidung hängt daran.

> **Methodik-Hinweis (wichtig für die Einordnung):** Das WebSearch-Budget dieses Workflow-Laufs war bereits
> erschöpft, bevor diese Recherche starten konnte (alle Suchanfragen wurden abgewiesen). DevForum-Threads,
> YouTube-Videos und Nutzerfeedback konnten daher **nicht** ausgewertet werden; es gibt in dieser Notiz praktisch
> keine REPORTED-Befunde. Stattdessen wurden offizielle Quellen über `raw.githubusercontent.com`
> (Roblox/creator-docs inkl. Open-Cloud-OpenAPI-Spec, rojo.space-Docs, Repos/Changelogs der Tools, Luau-RFCs)
> gelesen und die lokal installierten Tools (Rojo 7.7.1, Lune 0.11.1, selene 0.31.0, StyLua 2.6.0) **empirisch
> getestet**. Alle Testprojekte lagen im Scratchpad, nicht im Repo.

---

## 1. Zusammenfassung

1. **Rojo bleibt das Rückgrat für Repo → Studio.** Rojo 7.7.1 bildet `.json` auf ModuleScripts ab, die eine Tabelle
   zurückgeben, `.txt` auf `StringValue`, `.model.json` auf beliebige Instances (inkl. `ColorSequence`,
   `NumberSequence`, `NumberRange`, Attributes), `*.meta.json` setzt `className`/`properties`/`attributes`.
   Neu und für ASTRA zentral: **`syncRules`** (seit 7.5) erlauben, z. B. `*.vfx.json` als **`StringValue` mit dem
   rohen JSON-Text** zu synchronisieren – lokal verifiziert. Die JSON→ModuleScript-Abbildung ist dagegen
   **verlustbehaftet** (`null` verschwindet, `{}` und `[]` werden identisch, Schlüssel werden sortiert).
2. **Zurück (Studio → Repo) gibt es keinen verlustfreien Standardweg.** `rojo syncback` (neu in 7.7) überspringt
   bestehende JSON-Module („Cannot syncback Json … skipping“) und wandelt neue in `.luau` um; Rojos Two-Way-Sync ist
   „optional“/auf „supported edits“ beschränkt. Für einen AI-Loop, in dem Änderungen im Editor zurück ins Repo
   müssen, braucht ASTRA **eine eigene lokale Bridge** (Lune-HTTP/WebSocket-Server auf `127.0.0.1`) oder nutzt
   Studios eingebautes **Script Sync** (nur Skripte, aber zweiseitig).
3. **Lune 0.11.1 ist der Headless-Werkzeugkasten**: `@lune/roblox` (rbxm/rbxl lesen/schreiben, Instances mit
   Reflection-DB-Typprüfung, aber **keine Events, keine Engine-Methoden wie `Emit`, keine Simulation**),
   `@lune/net` (HTTP + WebSocket-Server, Default-Bind `127.0.0.1`, lokal getestet), `@lune/serde`
   (json/jsonc/yaml/toml, deterministische Schlüsselsortierung), `@lune/fs`, `@lune/process`, `@lune/luau`
   (`load` mit Custom-Environment). Require-by-string (`./`, `@self`, `.luaurc`-Aliases) funktioniert;
   `.config.luau`-Aliases werden in 0.11.1 **nicht** erkannt.
4. **Roblox hat einen eingebauten Studio-MCP-Server** (Assistant → Manage MCP Servers, stdio, Quick-Connect auch für
   Claude Code) mit u. a. `execute_luau`, `multi_edit`, `inspect_instance`, `screen_capture`, `start_stop_play`,
   `get_console_output`. Das alte `Roblox/studio-rust-mcp-server` ist offiziell nicht mehr aktiv entwickelt.
   **Aber:** Studio läuft nur auf Windows/macOS – in Cloud-/Linux-Sandboxes (wie dieser) ist MCP nicht nutzbar.
   MCP ist daher ein **optionaler Beschleuniger**, nicht die Basis.
5. **Open Cloud Luau Execution** führt Luau headless in einer veröffentlichten Place-Version aus (keine Physik,
   Skripte laufen nicht automatisch, Änderungen nicht persistent, 5 Task-Erstellungen/Minute pro Key-Owner,
   4 MB Skript/Rückgabe, 5 min). Brauchbar für **Engine-echte CI-Tests** der Runtime (Jest Roblox unterstützt das
   explizit), erfordert aber API-Key + Universe/Place.
6. **Plugin-HTTP zu localhost ist offiziell vorgesehen** („communicate with other software running on the same
   computer through localhost and 127.0.0.1“); beim ersten Zugriff *kann* ein Berechtigungsdialog pro Web-Adresse
   kommen. Zusätzlich gibt es `HttpService:CreateWebStreamClient` (Studio-only, SSE/Chunked/WebSocket, max.
   4 Clients) – Rojo 7.7 nutzt laut Changelog selbst WebSockets.
7. **Require-by-string ist in Engine und Lune kompatibel** zu Rojos `init.luau`-Konvention (Luau-RFC „Abstract
   module paths and init.luau“, Status Implemented; `@self`). Relative String-Requires ohne Aliases sind damit
   portabel; Aliases sind es (noch) nicht sicher.
8. **Toolchain:** Rokit (empfohlen in Roblox-Doku und Wally-README; kompatibel zu Foreman/Aftman; Aftman
   unmaintained), Wally (letztes Release 0.3.2, 2023), selene/StyLua/luau-lsp. **Tests:** Jest Roblox 3.20.x
   (aktiv, läuft in Roblox und via Luau Execution), TestEZ (letztes Release 2022), run-in-roblox 0.3.0 (öffnet
   Studio, also nur Windows/macOS).

**Empfohlener zuverlässigster Workflow ohne externe AI-API (Details in Kap. 4):**
Repo-JSON ist die Quelle der Wahrheit → `lune run` CLI validiert/normalisiert (gleicher Luau-Code wie Plugin) →
Rojo `syncRules` bringt die Dateien als rohe JSON-`StringValue`s nach Studio → ASTRA-Plugin beobachtet und
rendert live → Rückweg (Editor-Änderungen) über optionale ASTRA-Bridge (Lune, 127.0.0.1) oder manuellen Export.
MCP und Luau Execution sind Zusatzstufen für Verifikation.

---

## 2. Befunde

### 2.1 Rojo 7.x – Sync-Details, Build, Sourcemap, Rückweg

**Versionen.** Rojo 7.7.1 vom 2026-10-01 ist aktuell (VERIFIED, Rojo CHANGELOG); lokal installiert und im
Projekt in `rokit.toml` gepinnt.

**Dateiabbildung** (VERIFIED, rojo.space `sync-details.md`, plus lokaler Build `rojo build -o out.rbxmx` mit
Testprojekt):

| Datei | Instance | Anmerkung |
|---|---|---|
| Verzeichnis | `Folder` | `init.luau`/`init.server.luau`/`init.client.luau` macht das Verzeichnis selbst zum Skript; `init.meta.json` mit `className` macht es zu beliebiger Klasse (lokal: `Configuration`) |
| `*.luau`/`*.lua` | `ModuleScript` | `.luau` seit 7.2 (Changelog #552) |
| `*.server.luau` / `*.client.luau` | `Script` / `LocalScript` | mit `"emitLegacyScripts": false` stattdessen `Script` mit `RunContext` Server/Client (lokal: `RunContext=1`) |
| `*.plugin.luau` | `Script` mit `RunContext = Plugin` | seit 7.5 (lokal: `RunContext=3`); `init.plugin.luau` seit 7.7 |
| `*.json` | `ModuleScript`, das die Tabelle zurückgibt | sofern nicht `.model.json`/`.project.json`/`.meta.json` |
| `*.toml`, `*.yaml`/`*.yml` | `ModuleScript` (wie JSON) | YAML seit 7.6 |
| `*.txt` | `StringValue` | Inhalt → `Value` |
| `*.csv` | `LocalizationTable` | |
| `*.model.json` | beliebige Instance(s) | handgeschriebene Modelle |
| `*.rbxm`/`*.rbxmx` | Inhalt des Modells | Typabdeckung laut rbx-dom-Tabelle |
| `*.meta.json` | Zusatzdaten | `className` (nur `init.meta.json`), `properties`, `attributes`, `ignoreUnknownInstances` |
| `*.project.json` | eingebettetes Projekt | `default.project.json` in einem Ordner ersetzt dessen Inhalt |

Seit 7.6.1 sind Kommentare und Trailing-Commas in Project/Meta/Model-JSON erlaubt, seit 7.7.0-rc.1 auch
`.jsonc`-Varianten; seit 7.5 `$schema`-Feld (VERIFIED, Changelog; Kommentar im Test-`default.project.json`
lokal akzeptiert).

**JSON → ModuleScript ist verlustbehaftet** [KRITISCH] (VERIFIED, lokal mit Rojo 7.7.1):

- Schlüssel werden alphabetisch sortiert, als Luau-Tabellenliteral ausgegeben.
- `"n": null` wird zu `n = nil` → der Schlüssel existiert zur Laufzeit nicht.
- `[1, null, 3]` wird zu `{1, nil, 3}` (Tabelle mit Loch, `#` unzuverlässig).
- `[]` und `{}` werden beide `{}` – zur Laufzeit nicht unterscheidbar.
- Große Ganzzahlen verlieren Präzision (`9007199254740993` → `9007199254740992`), wie bei jedem Double.
- Die ursprüngliche Formatierung und eine eventuelle `$schema`-/Versionsangabe bleiben nur als Daten erhalten,
  nicht als Text.

**`syncRules` – rohe JSON als `StringValue`** [KRITISCH] (VERIFIED, Changelog 7.5.0 #813 und lokal):
```json
"syncRules": [ { "pattern": "*.vfx.json", "use": "text", "suffix": ".vfx.json" } ]
```
ergibt `Blast.vfx.json` → `StringValue` „Blast“ mit dem unveränderten JSON-Text als `Value`. Ohne Regel wird
dieselbe Datei zu einem ModuleScript namens „Blast.vfx“. Weitere `use`-Werte: `serverScript`, `clientScript`,
`moduleScript`, `json`, `toml`, `csv`, `text`, `jsonModel`, `rbxm`, `rbxmx`, `project`, `ignore`,
`pluginScript`, `runContextServerScript` usw. Sync-Rules gelten **pro Projektdatei** (werden bei verschachtelten
Projekten zurückgesetzt).

**Grenze `StringValue`** [KRITISCH] (VERIFIED, creator-docs `StringValue.yaml`): maximal **200 000 Zeichen**,
darüber Fehler „String too long“.

**`.model.json`** (VERIFIED, rojo.space `properties.md` + lokal): `ColorSequence`/`NumberSequence` nur explizit
(`{"ColorSequence": {"keypoints": [{"time":0,"color":[1,0,0]}, …]}}`), `NumberRange` explizit, `attributes`
werden als `AttributesSerialize` geschrieben. Lokal wurde `"Texture": "rbxassetid://123"` an einem
`ParticleEmitter` beim Build automatisch als **`TextureContent`** (Content-Typ) serialisiert – rbx-dom migriert
die alte `ContentId`-Property. Im API-Dump 0.745 existieren beide Properties (`Texture: ContentId`,
`TextureContent: Content`) an `ParticleEmitter`, `Beam`, `Trail` (VERIFIED, API-Dump).

**Projektformat** (VERIFIED, `project-format.md`, Changelog): `name` (seit 7.4.1 optional), `tree`, `servePort`
(Default 34872), `servePlaceIds`, `blockedPlaceIds` (7.5), `placeId`/`gameId`, `serveAddress`,
`globIgnorePaths` (7.7: gitignore-artige Negation), `emitLegacyScripts` (Default `true`), `syncRules`,
`syncbackRules`, `serveAllowedHosts` (7.7). Instance-Beschreibung: `$className`, `$path`, `$properties`,
`$attributes` (7.3), `$ignoreUnknownInstances`, `$id`/`Rojo_Target_*`-Attribute für Ref-Properties (7.5).

**Doppelte Namen** (VERIFIED, lokal): `conf.toml` und `conf.yaml` im selben Ordner erzeugen ohne Fehler zwei
ModuleScripts „conf“. `rojo syncback` weicht dann für den Ordner auf eine `.rbxm` aus.

**Build** (VERIFIED, `rojo build --help` + lokal): `rojo build [PROJECT] -o X.rbxm|.rbxmx|.rbxl|.rbxlx`,
`--watch`. `--plugin <NAME>` schreibt direkt in den Studio-Plugins-Ordner (seit 7.4) – **auf Linux schlägt das
fehl** („Your platform is not currently supported“), ebenso `rojo plugin install` (lokal getestet) [KRITISCH für
Sandbox/CI]. `-o build/AstraVFXStudio.rbxmx` funktioniert überall. Seit 7.4.4 ist `Archivable` in Binärbuilds
standardmäßig `true`.

**Sourcemap** (VERIFIED, `rojo sourcemap --help` + lokal): JSON-Baum aus `name`, `className`, `filePaths`,
`children`; Optionen `--include-non-scripts`, `--watch`, `--absolute` (7.6), `-o sourcemap.json`. Wird von
luau-lsp zur Auflösung von Instance-Requires genutzt (VERIFIED, luau-lsp README). `sourcemap.json` steht in
Rojos Default-`.gitignore` (7.6.1) und im ASTRA-`.gitignore`.

**Serve/Plugin-Protokoll** (VERIFIED, lokal + Changelog): `rojo serve` lauscht standardmäßig auf
`127.0.0.1`/`localhost:34872`; `/api/rojo` liefert MessagePack (kein JSON). Seit 7.7.0 werden `Host`/`Origin`
gegen DNS-Rebinding geprüft (lokal: falscher `Host`-Header → 404); seit 7.7.0-rc.1 kommuniziert das Plugin per
**WebSockets** statt Long-Polling. Seit 7.4 setzt Rojo Skriptquellen über `ScriptEditorService`, damit offene
Editoren aktualisiert werden. Seit 7.6 gibt es einen Fallback (Instance löschen/neu erstellen) für sonst nicht
synchronisierbare Instances; Achtung: bricht unbekannte Referenzen.

**Rückweg Studio → Dateien** [KRITISCH]:
- `rojo syncback --input <Datei> [PROJECT]` (neu in 7.7.0-rc.1; `--dry-run`, `--list`, `-y`) zieht Instances aus
  einer rbxl/rbxm in die Projektstruktur (VERIFIED, Changelog + `--help`). Lokal getestet: In ein **leeres**
  Projekt wurde `Fire.json` zu **`Fire.luau`**, `PluginMain.plugin.luau` zu `PluginMain.server.luau` + `meta.json`.
  In ein **bestehendes** Projekt: `[WARN] Cannot syncback Json at Effects/Fire, skipping` – geänderte JSON-Module
  kommen also **nicht** zurück; `.model.json` (geänderte `Rate`) wurde dagegen korrekt aktualisiert.
- Two-Way-Sync im Plugin: README nennt eine „optional two-way sync setting … for syncing supported Studio edits
  back to the filesystem“ (VERIFIED, README). Ältere Changelog-Einträge bezeichnen es als „EXPERIMENTAL“ bzw.
  „very broken“ (0.6/7.0-Ära). Welche Edits heute unterstützt sind, ist nicht dokumentiert (offene Frage).

**Live-Sync-Grenzen** (VERIFIED, `sync-details.md`): Binärdaten (Terrain, CSG), `MeshPart.MeshId`,
`HttpService.HttpEnabled` sind live nicht synchronisierbar; Typabdeckung siehe rbx-dom-Tabelle (alle für VFX
relevanten Typen – ColorSequence, NumberSequence, NumberRange, Content, Enum, Vector3, CFrame, Color3, Font –
sind in rbx_xml/rbx_binary/rbx_dom_lua implementiert; `UniqueId`/`SecurityCapabilities` nicht in rbx_dom_lua).

### 2.2 Lune (lune-org/lune) – Standalone-Luau-Runtime

**Version.** 0.11.1 vom 2026-10-21 (Security-Fix für HTTPS-Zertifikate), 0.11.0 vom 2026-10-11 mit
**Breaking Change** `handle.stop()` → `handle:stop()` bei `net.serve`; gebündelte rbx-dom-Datenbank 0.741,
Luau 0.740 (VERIFIED, Lune CHANGELOG; `roblox.getReflectionDatabase().Version` lokal = `0.741.19.7411056`,
Engine-Dump = 0.745). Non-Goal laut README: „Running full Roblox games outside of Roblox“ (VERIFIED).

**`@lune/roblox`** [KRITISCH] (VERIFIED, Typdefinitionen aus `lune setup` + lokale Tests):
- `deserializePlace/deserializeModel(contents)` und `serializePlace/serializeModel(…, xml?)` (binär Default).
  Rojo-gebaute `.rbxm` wurde gelesen; von Lune geschriebene `.rbxmx` lässt sich wieder als `$path` in einem
  Rojo-Projekt verwenden (Roundtrip lokal OK, inkl. Attributes und Sequenzen).
- Instance-API: `Clone`, `Destroy`, `ClearAllChildren`, `GetChildren`, `GetDescendants`, `GetFullName`,
  `QueryDescendants` (0.10.5), `FindFirstChild…`/`FindFirstAncestor…`, `IsA`, `IsAncestorOf`, `IsDescendantOf`,
  Attributes, Tags; `DataModel:GetService/FindService`.
- Property-Zugriffe werden gegen die Reflection-DB geprüft: unbekannte Property → „is not a valid member“,
  falscher Typ → „Failed to convert from 'string' into 'Float32'“ (lokal). Laut Typdefinition sind in Lune
  **alle** Properties les-/schreibbar, auch wenn sie in Roblox nicht scriptable sind – Lune-Tests können also
  Zugriffe durchlassen, die in der Engine scheitern.
- **Keine Events/Signals** (`p.Changed` → „not a valid member“), **keine Engine-Methoden** (`ParticleEmitter:Emit`
  → „not a valid member“), keine Simulation/kein Rendering. Fehlende Methoden lassen sich mit
  `roblox.implementMethod`/`implementProperty` nachrüsten; unbekannte Klassen/Services mit
  `registerClass`/`registerService` (0.10.5).
- Datentypen vorhanden: Vector2/3(int16), CFrame, Color3, ColorSequence(+Keypoint), NumberSequence(+Keypoint),
  NumberRange, UDim/UDim2, Rect, Font, Enum, BrickColor, PhysicalProperties, Ray, Region3(int16), Faces, Axes,
  Content. **Nicht vorhanden** (lokal `roblox[name] == nil`): `TweenInfo`, `DateTime`, `Random`,
  `RaycastParams`, `OverlapParams`.
- **Texture/TextureContent-Falle** [KRITISCH] (lokal): Bei neuem `ParticleEmitter` liefert `p.Texture` den Fehler
  „missing default value“; `p.Texture = "rbxassetid://5"` ändert `p.TextureContent` **nicht** (bleibt
  Sparkles-Default). Die Kopplung migrierter Properties ist erst im Abschnitt „Unreleased“ des Changelogs als
  experimentell angekündigt. Folge: In Lune serialisierte Modelle können widersprüchliche `Texture`/`TextureContent`
  enthalten.
- `getAuthCookie`, `studioPluginPath` etc. existieren; `studioPluginPath()` schlägt auf Linux fehl (lokal).

**`@lune/net`** [KRITISCH] (VERIFIED, Typdefinitionen + lokaler Test): `net.serve(port, {address?,
handleRequest, handleWebSocket})` bzw. `net.http.serve`; `ServeHandle` mit `ip`, `port`, `:stop()`. Ohne
`address` lauscht der Server lokal getestet auf **`127.0.0.1`**. Request-Objekt: `path`, `query`, `method`,
`headers`, `body`; Response: `status` (Default 200 seit 0.11), `headers`, `body`. WebSocket-Handler: `send`,
`next`, `close`. Client: `net.request`/`net.http.request`, `net.ws.connect`, `net.tcp.connect`. Lokal: HTTP-GET
mit Query und WebSocket-Echo funktionierten.

**`@lune/serde`** (VERIFIED, lokal): `encode/decode` für `json`, `jsonc` (0.10.4), `yaml`, `toml`; Kompression
(brotli/gzip/lz4/zlib/zstd), Hash/HMAC. `serde.encode("json", t, pretty)` **sortiert Schlüssel alphabetisch**
(deterministisch, gut für git-Diffs), Pretty-Print mit 2 Leerzeichen, **leere Tabelle → `{}`** (nicht `[]`),
`1e20` → `1e+20`. `decode` von `null` → `nil`.

**`@lune/fs`** (VERIFIED, Typdefinitionen): `readFile`, `readDir`, `writeFile`, `writeDir`, `removeFile`,
`removeDir`, `metadata` (mit `size` seit 0.11), `isFile`, `isDir`, `move`, `copy`. Kein File-Watcher in der API
(nicht gefunden) – ein Bridge-Server müsste per Polling (`metadata`) oder über externe Tools beobachten.

**`@lune/process`** (VERIFIED, Typdefinitionen): `os`, `arch`, `args`, `cwd`, `env`, `exit`, `exec`
(mit `cwd`, `env`, `shell`, `stdio`), `create` (Kindprozess mit stdin/stdout-Streams). Damit kann eine Lune-CLI
z. B. `rojo build` aufrufen.

**`@lune/luau`** (VERIFIED, Typdefinitionen): `compile(source, opts)`, `load(sourceOrBytecode, {debugName,
environment, injectGlobals, codegenEnabled})`. Ein Custom-`environment` **deoptimiert den Chunk und schaltet Codegen
ab**. Das bestehende ASTRA-`tests/lune/Loader.luau` nutzt genau diesen Mechanismus, um `script`/`require` wie in
Roblox bereitzustellen.

**Require in Lune** [KRITISCH] (VERIFIED, lokal mit 0.11.1; Changelog 0.10.0 „proper require-by-string APIs“):
- `require("./x")` relativ zur Datei; in `pkg/init.luau` zeigt `./foo` auf das **äußere** `foo.luau`,
  `@self/foo` auf `pkg/foo.luau` – exakt wie Rojo/Engine.
- `.luaurc` mit `"aliases"` funktioniert (`@Lib/util`); **`.config.luau` mit `luau.aliases` wird nicht erkannt**
  („@lib2 is not a valid alias“).
- `require("./data.json")` ist nicht möglich („could not resolve child component“) → JSON nur via `fs` + `serde`.
- Requires werden gecacht (gleiche Referenz); dynamische String-Requires (Variable) funktionieren zur Laufzeit.
- Globale `script` und `game` existieren nicht (nil).

### 2.3 Roblox Studio MCP-Server (eingebaut) und das alte Rust-Repo

**Eingebauter Studio-MCP-Server** [KRITISCH] (VERIFIED, creator-docs `studio/mcp.md`):
- „built into Roblox Studio“, läuft als lokaler Prozess, Transport **stdio**. Aktivierung: **Assistant → … →
  Manage MCP Servers → „Enable Studio as MCP server“**; grüner Indikator zeigt verbundene Clients.
- Quick Connect u. a. für **Claude Code**, Claude Desktop, Codex CLI, Cursor, Gemini CLI, VS Code, Antigravity;
  sonst JSON-Konfiguration: Windows `cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat`, macOS
  `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`. Nur diese beiden Plattformen sind dokumentiert.
- Werkzeuge: Skripte (`script_read`, `multi_edit` – legt Skript an, falls Pfad fehlt, `datamodel_type` Edit,
  `script_search`, `script_grep`), Assets (`generate_mesh`, `generate_material`, `generate_procedural_model`,
  `wait_job_finished`, `search_asset`, `insert_asset`, `upload_image`, `store_image`), DataModel
  (`subagent` explore/playtest, `search_game_tree`, `inspect_instance` – alle lesbaren Properties + Attributes),
  **`execute_luau`** (Edit/Client/Server), Playtest (`get_studio_state`, `start_stop_play`,
  `get_console_output`, **`screen_capture`** mit optionaler Kameraposition), Input-Simulation
  (`character_navigation`, `user_keyboard_input`, `user_mouse_input`), Doku (`http_get` auf erlaubte
  Roblox-Doku-URLs, `skill`), `list_roblox_studios`. Jeder Call nimmt eine `studio_id`; mehrere Studio-Instanzen
  gleichzeitig möglich.
- Warnhinweis der Doku: MCP-Clients können offene Places lesen und ändern.
- Assistant kann zusätzlich eigene LLM-Keys (Anthropic/OpenAI/Gemini, „BYOK“) nutzen (VERIFIED,
  `assistant/mcp.md`) – für ASTRA irrelevant, da keine externe AI-API gewünscht. Assistant hat einen
  Screen-Capture-Subagent; über MCP bleibt das Screenshot-Tool direkt verfügbar (VERIFIED, `assistant/guide.md`).

**`Roblox/studio-rust-mcp-server`** (VERIFIED, README): Hinweis „no longer being actively developed“ –
Investitionen gehen in den eingebauten Server. Architektur: Rust-Prozess (axum-Webserver, den ein Studio-Plugin
long-pollt, + rmcp-stdio-Server). Tools: `run_code`, `insert_model`, `get_console_output`, `start_stop_play`,
`run_script_in_play_mode`, `get_studio_mode`. Releases für Windows/macOS.

**Studio-Plattform** [KRITISCH] (VERIFIED, `studio/setup.md`): Studio ist „available on Windows and Mac“. Die
Cloud-Sandbox (Linux) kann weder Studio noch MCP noch Rojo-Live-Sync testen.

**Weitere Studio-Automatisierung** (VERIFIED, `StudioTestService.yaml` + API-Dump):
`StudioTestService:ExecutePlayModeAsync/ExecuteRunModeAsync/ExecuteMultiplayerTestAsync` (PluginSecurity,
yieldend) starten Tests aus einem Plugin heraus, `GetTestArgs`/`EndTest(result)` übergeben Argumente/Ergebnis.

### 2.4 Open Cloud APIs für Automatisierung

**Luau Execution** [KRITISCH] (VERIFIED, `reference/cloud/openapi.json` in creator-docs):
- `POST /cloud/v2/universes/{universe_id}/places/{place_id}/luau-execution-session-tasks` (oder
  `…/versions/{version_id}/…`), Body `{ script, timeout?, binaryInput?, enableBinaryOutput? }`;
  Status per `GET …/luau-execution-sessions/{session}/tasks/{task}` (`QUEUED`/`PROCESSING`/`COMPLETE`/`FAILED`/
  `CANCELLED`), Logs per `…/logs`. Stabilität „STABLE“.
- Scope `universe.place.luau-execution-session:write` (Lesen: `:read`).
- Semantik: „physics simulation does not run. Server and local scripts within the place also do not
  automatically run“; DataModel darf gelesen/geändert und ModuleScripts dürfen required werden, Änderungen werden
  **nicht persistiert**; Cloud-APIs (DataStores) sind erreichbar.
- Limits: Skript ≤ 4 MB, Laufzeit ≤ 5 min (Default-Timeout 5 min), Rückgabewerte als JSON ≤ 4 MB, Logs ≤ 450 KB,
  Task-Info 24 h, ≤ 10 unvollständige Tasks pro Place (sonst 429). Rate-Limits pro API-Key-Owner: **5
  Task-Erstellungen/Minute**, 200 Status-GETs/Minute, 45 Log-Abfragen/Minute. Binärinput ≤ 100 MiB (15 min
  gültig), Binäroutput ≤ 256 MiB.

**Place Publishing** (VERIFIED, OpenAPI + `cloud/guides/usage-place-publishing.md`):
`POST /universes/v1/{universeId}/places/{placeId}/versions?versionType=Saved|Published` mit `.rbxl`
(`application/octet-stream`) oder `.rbxlx` (`application/xml`); Antwort `{ "versionNumber": n }`; Scope
`universe-places:write`; 30/Minute; Größenlimit 10 MiB; Stabilität BETA. `Saved` speichert ohne zu
veröffentlichen. Die API aktualisiert u. a. `EditableImage`, `EditableMesh`, `PartOperation`,
`SurfaceAppearance`, `BaseWrap` nicht. `rojo upload --api_key … --universe_id … --asset_id …` nutzt diese
Open-Cloud-API (nur Places) (VERIFIED, `rojo upload --help`).

**API-Keys** (VERIFIED, `cloud/auth/api-keys.md`): Erstellung im Creator Dashboard; Zugriff entspricht den
Rechten des Besitzers; optional „Restrict by Experience“, IP-Allowlist (CIDR), Ablaufdatum; für Gruppen wird
ein separater Automationsaccount empfohlen.

**Assets API** (VERIFIED, OpenAPI): `POST /assets/v1/assets` (Scopes `asset:read`/`asset:write`, 120/min,
BETA) – relevant nur, falls ASTRA später Texturen/Flipbooks automatisiert hochladen will.

### 2.5 Plugin-HttpService zu localhost (Bridge)

- [KRITISCH] „You can use HttpService in Studio plugins … The first time a plugin attempts to use the service,
  the user **might** be prompted to give the plugin permission to communicate with the particular web address.
  Users can accept, deny, and revoke these permissions at any time through the **Plugin Management** window.“
  (VERIFIED, `cloud-services/http-service.md`, Abschnitt „Use in plugins“)
- [KRITISCH] „Plugins can also communicate with other software running on the same computer through the
  `localhost` and `127.0.0.1` hosts … such as interacting with your computer's file system. Beware that such
  software must be distributed separately from the plugin itself and can pose security risks.“ (VERIFIED, ebd.)
- Die HTTPS-only- und Port-Beschränkungen (keine Ports < 1024 außer 80/443, nicht 1194) stehen im Abschnitt
  „Use with Open Cloud“ und beziehen sich auf Open-Cloud-Aufrufe aus Spielservern (VERIFIED, ebd.). Für Plugins
  zu localhost ist das in der Doku nicht explizit; Rojo selbst arbeitet mit `http://localhost:34872`
  (ASSUMPTION: unkritisch, da Rojo das seit Jahren so nutzt).
- `HttpService.HttpEnabled` (Write: `LocalUserSecurity`) gilt für Spielskripte; dass Plugins es nicht brauchen,
  ist nicht explizit dokumentiert (ASSUMPTION, gestützt darauf, dass Rojo ohne diese Einstellung funktioniert).
- [KRITISCH] `HttpService:CreateWebStreamClient(WebStreamClientType, requestOptions)`: „available in Studio
  only“, SSE, chunked transfer, **WebSocket**; „limit of four total clients allowed at one time“;
  `WebStreamClient:Send` nur bei WebSocket; Events für Open/Close/Error/Messages (VERIFIED, `HttpService.yaml`,
  `WebStreamClient.yaml`). Rojo 7.7.0-rc.1 hat seine Plugin-Server-Kommunikation auf WebSockets umgestellt
  (VERIFIED, Rojo-Changelog #1142) – praktischer Beleg, dass WebSocket zu localhost aus Plugins funktioniert
  (ASSUMPTION als Schluss).
- Plugins haben keine API zum direkten Schreiben lokaler Dateien; vorhanden sind nur benutzergesteuerte Dialoge:
  `StudioService:PromptImportFileAsync/PromptImportFilesAsync` (liefert `File` mit `GetBinaryContents`) und
  `Plugin:PromptSaveSelectionAsync` (VERIFIED: diese Members im API-Dump 0.745; ASSUMPTION: dass es keine
  weitere Schreib-API gibt).

### 2.6 Require-by-string: Engine, Lune, Tools

- [KRITISCH] Engine (VERIFIED, `LuaGlobals.yaml`, `require`): String-Pfade werden relativ zum aufrufenden
  Skript aufgelöst: `./` → `script.Parent`, `../` → `script.Parent.Parent`, `@self/` → `script`, `@game/` →
  `game`; jede weitere Komponente = Kind-Instance, `..` = Parent. **Nicht blockierend**: fehlt das Modul beim
  Aufruf, wird sofort ein Fehler geworfen (kein implizites `WaitForChild`). Parameter-Typ `ModuleScript | string |
  number`.
- Luau-RFCs (VERIFIED, luau-lang/rfcs): „Require by String with Relative Paths“ (Implemented), „Require by String
  with Aliases“ (Implemented; Aliases sind case-insensitive, `@`-Präfix, Zeichensatz `[A-Za-z0-9.\-_]`),
  „Abstract module paths and init.luau“ (Implemented: `foo/init.luau` *ist* das Modul `foo`; `./` aus init.luau
  zeigt auf Geschwister des Ordners; `@self` reserviert für Kinder) – ausdrücklich zur Kompatibilität mit Rojo.
  „Support Luau-syntax configuration files“ (`.config.luau`, Implemented in Luau).
- `ScriptService:ResolveModulePath(relativeTo: Instance, path: string): Instance` existiert im API-Dump 0.745
  (Security None) (VERIFIED), ist in den creator-docs aber **nicht** beschrieben (Seite nennt ScriptService
  „unimplemented service“). Jest Roblox (Unreleased-Changelog) nutzt sie, „so every path native require
  understands (**including `.config` aliases**) also works under Jest“ (VERIFIED als Aussage des Produkts; ob und
  wie die Engine Aliases unterstützt, ist offiziell nicht dokumentiert → offene Frage).
- Lune: siehe 2.2 – `./`, `@self`, `.luaurc`-Aliases ja, `.config.luau` nein (VERIFIED, lokal).
- luau-lsp: „built-in support for Luau's generalised require-by-string semantics“; Rojo-Nutzer bekommen
  Instance-Auflösung über `sourcemap.json` (VERIFIED, README).
- darklua (seaofvoices) transformiert Luau-Code per Regeln und ist via Rokit installierbar (VERIFIED, README);
  die konkreten Require-Umwandlungsregeln wurden nicht geprüft.

### 2.7 Toolchain-Manager, Pakete, Linter/Formatter

- **Rokit** (rojo-rbx/rokit, 1.2.0 vom 2025-09-30): „Next-generation toolchain manager for Roblox projects“,
  „Drop-in compatibility with projects that already use Foreman or Aftman“, `rokit init/add/install`, Self-Update
  (VERIFIED, README/CHANGELOG). Die Roblox-Doku „Third-party tools“ empfiehlt Rokit für Rojo/Wally/Lune
  (VERIFIED, `projects/external-tools.md`). ASTRA nutzt bereits `rokit.toml`.
- **Aftman**: „⚠️ Aftman is no longer maintained“, Empfehlung mise-en-place (VERIFIED, README).
- **Foreman** (Roblox/foreman): Toolchain-Manager, inspiriert von rustup/asdf, GitHub-Action `setup-foreman`
  (VERIFIED, README).
- **Wally**: Paketmanager mit CLI + Registry; empfiehlt Rokit zur Installation; letztes Release 0.3.2
  (2023-06-05), `main` steht auf `0.4.0-alpha.1` (VERIFIED, README/CHANGELOG/Cargo.toml). Alternative **pesde**
  („package manager for the Luau programming language, designed to prevent runtime lock-in“) (VERIFIED, README).
- **selene** (Linter): `std = "roblox"` generiert die Roblox-Std automatisch und **benötigt dafür Internet**;
  alternativ `roblox-std-source = "pinned"` bzw. `selene generate-roblox-std` → `roblox.yml` (VERIFIED,
  selene-Doku `roblox.md`). Aktuell 0.32.0 (2026-10-01); ASTRA pinnt 0.31.0 (VERIFIED, Changelog). ASTRA umgeht
  den Netzbedarf mit eigener Std `astra.yml`.
- **StyLua** (Formatter): 2.6.0 vom 2026-10-10 (VERIFIED, Changelog), ASTRA nutzt `syntax = "Luau"`.
- **luau-lsp**: Language-Server + `luau-lsp analyze` für CI mit Rojo-Auflösung; Companion-Plugin für
  DataModel-Infos außerhalb des Rojo-Baums (VERIFIED, README). In dieser Sandbox nicht installiert (Downloads von
  github.com blockiert) – ASTRA hat dafür `tools/analyzer` (astra-analyze).
- **Studio Script Sync** (eingebaut) [KRITISCH als Alternative] (VERIFIED, `scripting/sync.md`): synchronisiert
  ausgewählte Ordner **zweiseitig** mit lokalen Dateien; nur `Script`, `LocalScript`, `ModuleScript`, `Folder`
  („All other instances in a synced folder are ignored“); **Attributes und Tags werden ignoriert** (Warnung vor
  Datenverlust); Namenskonventionen `name.luau` (Module), `name.server.luau`/`name.client.luau` (Script mit
  RunContext), `name.local.luau` (LocalScript), `name.legacy.luau`, `name.plugin.luau`, `init.*.luau`; Limits
  10 000 Skripte pro Wurzel, 128 Wurzeln; Konfliktdialog beim Start; funktioniert mit Team Create. Die Doku
  positioniert Rojo als bessere Wahl, wenn das Dateisystem die Quelle der Wahrheit sein soll.

### 2.8 Testframeworks

- **Jest Roblox** (Roblox/jest-roblox, 3.20.1 vom 2026-08-30): Port von Jest 27.4.7; „can run within Roblox
  itself, including via Roblox's OCALE (Open Cloud API for Luau Execution) for testing on CI systems“;
  Installation via Wally (`roblox/jest@=3.20.0`, 34 Pakete seit 3.20.0) oder Creator Store (Asset 16031830738
  laut README); Specs als `.spec.lua(u)` unter `__tests__/` (VERIFIED, README/CHANGELOG). 3.15.0: „Use
  rocale-cli for running OCALE tests“.
- **Jest Lua** (jsdotlua/jest-lua): „can currently only run inside of Roblox“, Hilfe für Lune gesucht (VERIFIED,
  README).
- **TestEZ** (Roblox/testez): BDD-Framework, läuft in Roblox bzw. im (veralteten) Lemur; letztes Release 0.4.2
  vom 2022-01-05 (VERIFIED, README/CHANGELOG). selene hat eine `roblox+testez`-Std (VERIFIED).
- **run-in-roblox** (rojo-rbx/run-in-roblox 0.3.0): öffnet eine Place in Roblox Studio, führt ein Skript aus,
  leitet Output nach stdout (VERIFIED, README/Cargo.toml) → setzt Studio (Windows/macOS) voraus.
- ASTRA hat bereits einen eigenen Lune-basierten Runner (`tests/lune/run.luau`, `Loader.luau`, `Fakes.luau`,
  `tests/framework/TestFramework.luau`).

---

## 3. Einschränkungen / Kritik

1. **Keine Community-Stimmen.** Mangels WebSearch-Budget fehlen DevForum-Erfahrungen (z. B. zu MCP-Stabilität,
   Plugin-HTTP-Prompts, Two-Way-Sync-Qualität, Script-Sync-Bugs). Alle Aussagen dazu sind Doku-basiert oder lokal
   nachgestellt; Laufzeitverhalten **in Studio** konnte nirgends getestet werden (kein Studio auf Linux).
2. **Rojo-JSON-Module sind für ein Datenformat ungeeignet**, wenn `null`, leere Arrays vs. Objekte oder exakte
   Zahlen semantisch relevant sind; außerdem cacht `require` (Plugin sieht Updates nicht automatisch).
3. **`StringValue`-Limit 200 000 Zeichen** begrenzt den „rohes JSON“-Weg; sehr große Effekte (lange Timelines,
   viele Keyframes) brauchen Kompaktformat, Aufteilung oder die Bridge.
4. **Rückweg ist der schwache Punkt**: syncback überspringt JSON, Two-Way-Sync ist unklar, Script Sync ignoriert
   Attributes und Nicht-Skript-Instances, Plugins können keine Dateien schreiben.
5. **Lune ist kein Engine-Ersatz**: Reflection-DB hinkt (0.741 vs. 0.745), keine Events/Methoden/Simulation,
   migrierte Properties (`Texture`/`TextureContent`) verhalten sich anders, und Lune erlaubt Zugriffe auf
   nicht-scriptable Properties. Grüne Lune-Tests beweisen nicht, dass Code in Studio läuft.
6. **Studio-MCP** ist mächtig, aber an eine laufende Studio-Session auf Windows/macOS gebunden; Werkzeugumfang und
   Namen können sich ändern (Doku ist neu, altes Repo bereits abgekündigt). Sicherheitsrisiko laut Roblox selbst.
7. **Luau Execution** braucht API-Key, veröffentlichte Place und hat enges Rate-Limit (5/min) – für schnelle
   Iteration ungeeignet, für nächtliche/CI-Läufe okay. Kein Rendering → visuelle Qualität nicht prüfbar.
8. **Plattformfallen in CI/Sandbox**: `rojo build --plugin`, `rojo plugin install`, `roblox.studioPluginPath()`
   funktionieren unter Linux nicht.
9. **Lune 0.11 Breaking Change** (`handle:stop()`); Lune 0.11.1 ist ein Security-Release → Pin auf ≥ 0.11.1
   sinnvoll (ASTRA pinnt 0.11.1).
10. **Aliases** sind zwischen Lune (`.luaurc` ja, `.config.luau` nein), Engine (undokumentiert) und Tools nicht
    einheitlich.

---

## 4. Konsequenzen für ASTRA

**K1 – Quelle der Wahrheit = versionierte JSON-Dateien im Repo** (IDEA, [KRITISCH]). Claude Code bearbeitet nur
`effects/*.vfx.json` (Dateiendung bewusst eigen, damit `syncRules` greifen). Das Format verzichtet auf
semantisches `null` (fehlender Schlüssel = Default) und unterscheidet Array/Objekt über das Schema, nicht über den
Laufzeittyp – dann ist es auch gegen Rojo-/serde-Verluste robust.

**K2 – Repo → Studio über Rojo `syncRules` als rohe JSON-`StringValue`s** (IDEA, [KRITISCH]):
```json
"syncRules": [ { "pattern": "*.vfx.json", "use": "text", "suffix": ".vfx.json" } ]
```
Das Plugin beobachtet einen festen Container (z. B. einen Folder unter `ServerStorage`), dekodiert mit
`HttpService:JSONDecode` (reine Daten, kein Code-Ausführen, kein `require`-Cache-Problem) und baut die Preview neu.
Die CLI prüft eine Größen-Obergrenze (z. B. Warnung ab 150 000, Fehler ab 200 000 Zeichen). Rojo-JSON-Module
(`.json` → ModuleScript) nur für unkritische Konfiguration.

**K3 – Ein gemeinsamer Luau-Kern für Validierung/Normalisierung/Serialisierung** (IDEA, [KRITISCH]): dieselben
Module laufen im Plugin, im Runtime-Modul und in einer Lune-CLI (`lune run tools/astra -- validate|fmt|build`).
ASTRA braucht einen **eigenen deterministischen JSON-Encoder** (feste Schlüsselreihenfolge, Zahlenformat, leere
Arrays als `[]`), weil `serde.encode` leere Tabellen als `{}` schreibt und die Engine-Encodierung davon abweichen
kann (ASSUMPTION zur Engine). So erzeugen Agent, CLI und Plugin byte-identische Dateien → saubere git-Diffs.

**K4 – Studio → Repo über eine optionale ASTRA-Bridge** (IDEA, [KRITISCH]): `lune run tools/bridge` startet
`net.serve` auf `127.0.0.1:<port>` (nie `0.0.0.0`), mit zufälligem Session-Token und Host/Origin-Prüfung (Rojo
7.7 macht das gegen DNS-Rebinding). Plugin → Bridge per `HttpService:RequestAsync` (POST Effekt-JSON; Bridge
schreibt atomar mit dem K3-Formatter) und optional `CreateWebStreamClient(WebSocket)` für Push-Benachrichtigungen
(max. 4 Clients beachten; Rojo belegt evtl. selbst einen). Der Berechtigungsdialog für localhost muss in der
UI erklärt werden. Ohne Bridge: manueller Export (Text zum Kopieren) und Import über
`StudioService:PromptImportFileAsync`.

**K5 – Script Sync als zweite, Rojo-freie Transportoption prüfen** (IDEA): Effekte zusätzlich als
`.luau`-ModuleScript (`return [==[ … JSON … ]==]`) exportierbar machen; Script Sync würde Änderungen zweiseitig
spiegeln. Einschränkungen: nur Skripte, Attributes/Tags gehen verloren, Namenskonventionen weichen von Rojos
Default (`emitLegacyScripts: true`) ab. Nicht als Default, aber als „kein-Zusatztool“-Modus dokumentieren.

**K6 – MCP als Verifikations-Turbo, nicht als Pflicht** (IDEA): In `docs/` eine Claude-Code-Anleitung: Studio-MCP
aktivieren, dann kann der Agent `execute_luau` (Edit) nutzen, um z. B. das Runtime-Modul eine Datei abspielen zu
lassen, `get_console_output` für Fehler und `screen_capture` für eine visuelle Kontrolle. Die ASTRA-Kernpipeline
darf davon nicht abhängen (Linux/CI, fehlende Studio-Session).

**K7 – Build-Ziele** (VERIFIED + IDEA): `rojo build default.project.json -o build/AstraVFXStudio.rbxmx` (Plugin)
und `rojo build runtime.project.json -o build/AstraVFX.rbxm` (Runtime) wie bereits im Projekt; das Kopieren in den
lokalen Plugins-Ordner (bzw. `rojo build --plugin` auf Windows/macOS) dokumentieren, nicht in CI voraussetzen.

**K8 – Requires** (IDEA, [KRITISCH]): Beide Wege sind möglich. Empfehlung:
- Für **Runtime- und Plugin-Code nur relative Pfade** – entweder weiterhin Instance-Requires
  (`require(script.Parent.X)`, funktioniert mit dem bestehenden Lune-Loader und astra-analyze) **oder**
  String-Requires beschränkt auf `./`, `../`, `@self/`. Beide sind in Engine, Lune und luau-lsp konsistent mit
  Rojos `init.luau`.
- **Keine Aliases** (`@Lib/…`) und kein `@game/` im Runtime-Modul (nicht portabel bzw. an den Ablageort im
  Spiel gekoppelt).
- Datendateien nie per `require` laden (in Lune unmöglich, in Roblox verlustbehaftet), sondern als String/Tabelle
  hereinreichen.
- Da der Code bereits Instance-Requires nutzt und der Loader Rojo-Regeln nachbaut, ist ein Wechsel kein Muss;
  ein Wechsel zu String-Requires würde reine Logikmodule ohne Loader direkt unter Lune testbar machen.

**K9 – Testpyramide** (IDEA): (1) Lune-Unit-Tests (Format, Validierung, Interpolation, Timeline-Logik) mit Fakes;
Lune-Instances zusätzlich zur Property-Namen/Typ-Prüfung, aber mit Liste bekannter Abweichungen
(`Texture`/`TextureContent`, fehlende Datentypen, nicht-scriptable Properties). (2) Optional Engine-Tests via
Open Cloud Luau Execution (Place mit `versionType=Saved` hochladen, Test-Skript als Task, Ergebnis als JSON) –
Jest Roblox unterstützt das; Schlüssel nur als Secret, nie im Repo. (3) In-Studio-Smoke-Tests über Plugin +
`StudioTestService` oder MCP `start_stop_play`.

**K10 – Property-Wahl Texture vs. TextureContent** (IDEA): Runtime setzt in der Engine eine Property konsequent
(z. B. `TextureContent = Content.fromUri(...)`, im API-Dump/Typdefs vorhanden) oder `Texture` – aber nie beide;
Lune-Fakes müssen die Kopplung nachbilden, sonst testen sie Falsches.

**K11 – Toolchain festhalten** (IDEA): Rokit bleibt; selene ggf. auf 0.32.0 heben; Lune ≥ 0.11.1; Wally nur falls
wirklich Pakete (z. B. Jest Roblox) gebraucht werden – das Runtime-Modul sollte abhängigkeitsfrei bleiben.

---

## 5. Offene Fragen

1. Zeigt Studio den HTTP-Berechtigungsdialog auch für **lokal installierte** Plugins (Datei im Plugins-Ordner)
   oder nur für Creator-Store-Plugins? Gibt es einen separaten Dialog für „Script Injection“, wenn ein Plugin
   Skripte anlegt/ändert? (Nicht dokumentiert gefunden; Test in Studio nötig.)
2. Welche Edits unterstützt Rojos heutiger Two-Way-Sync konkret (nur Script-Source? Properties von
   `.model.json`?), und ist er in 7.7 noch als experimentell markiert?
3. Feuert `StringValue.Changed`/`GetPropertyChangedSignal("Value")` zuverlässig bei Rojo-Live-Updates, und wie
   verhält sich Rojos Fallback (Instance ersetzen) – verliert das Plugin dann seine Referenz?
4. Unterstützt die Engine Require-Aliases (z. B. über ein `.config`-ModuleScript, wie der Jest-Changelog
   andeutet)? Welche Semantik hat `ScriptService:ResolveModulePath`?
5. Laufen String-Requires auch in Plugin-Kontext (RunContext Plugin) identisch? (Erwartet ja, nicht verifiziert.)
6. Hat `execute_luau` des Studio-MCP Plugin-Security-Rechte, und gibt es Größenlimits für Code/Rückgaben? Kann
   ein Agent damit gezielt Funktionen eines installierten Plugins aufrufen (z. B. über eine `BindableFunction`),
   ohne das DataModel zu verschmutzen?
7. Lädt Studio lokale Plugins automatisch neu, wenn die `.rbxmx` im Plugins-Ordner überschrieben wird
   (`rojo build --watch`)?
8. Wie kodiert `HttpService:JSONEncode` leere Tabellen, `NaN`/`inf` und große Zahlen – genau genug, um den
   Lune-Encoder abzugleichen?
9. Welche Größenlimits gelten für `HttpService:RequestAsync`-Antworten/-Bodies aus Plugins und für
   `WebStreamClient`-Nachrichten?
10. Gibt es Erfahrungsberichte (DevForum) zu Stabilität und Latenz des eingebauten MCP-Servers mit Claude Code?
    (Nicht recherchierbar in diesem Lauf.)
11. Lokale Plugins-Ordner-Pfade (Windows `%LOCALAPPDATA%\Roblox\Plugins`, macOS `~/Documents/Roblox/Plugins`)
    sind gängiges Wissen, wurden hier aber nicht aus offizieller Doku bestätigt.

---

## 6. Quellen

Offizielle Roblox-Doku (gelesen als Quelltext von `Roblox/creator-docs`, Pfad → veröffentlichte URL):
- Studio MCP: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/studio/mcp.md (https://create.roblox.com/docs/studio/mcp)
- Assistant MCP/BYOK: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/assistant/mcp.md
- Assistant Guide: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/assistant/guide.md
- Plugins: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/studio/plugins.md
- HTTP in Plugins/Spielen: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/cloud-services/http-service.md
- HttpService (CreateWebStreamClient): https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/HttpService.yaml
- WebStreamClient: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/WebStreamClient.yaml
- StringValue (200 000 Zeichen): https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/StringValue.yaml
- require (LuaGlobals): https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/globals/LuaGlobals.yaml
- ModuleScript: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/ModuleScript.yaml
- ScriptService: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/ScriptService.yaml
- StudioTestService: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/StudioTestService.yaml
- StudioService: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/StudioService.yaml
- Script Sync: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/scripting/sync.md
- Third-party tools (Rojo/Rokit/Wally): https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/projects/external-tools.md
- Studio Setup (Windows/Mac): https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/studio/setup.md
- Place Publishing Guide: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/cloud/guides/usage-place-publishing.md
- API Keys: https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/cloud/auth/api-keys.md
- Open Cloud OpenAPI (Luau Execution, Places, Assets): https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/cloud/openapi.json (Doku: https://create.roblox.com/docs/cloud/reference/features/luau-execution, https://create.roblox.com/docs/cloud/reference/features/places)

Rojo:
- Sync Details: https://raw.githubusercontent.com/rojo-rbx/rojo.space/master/docs/sync-details.md (https://rojo.space/docs/v7/sync-details/)
- Project Format: https://raw.githubusercontent.com/rojo-rbx/rojo.space/master/docs/project-format.md
- Properties: https://raw.githubusercontent.com/rojo-rbx/rojo.space/master/docs/properties.md
- README / CHANGELOG: https://raw.githubusercontent.com/rojo-rbx/rojo/master/README.md, https://raw.githubusercontent.com/rojo-rbx/rojo/master/CHANGELOG.md
- rbx-dom Typabdeckung: https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/README.md
- Lokal: `rojo --help`, `rojo build|syncback|sourcemap|serve|upload --help`, Testbuilds (Rojo 7.7.1)

Lune:
- README / CHANGELOG: https://raw.githubusercontent.com/lune-org/lune/main/README.md, https://raw.githubusercontent.com/lune-org/lune/main/CHANGELOG.md
- Typdefinitionen 0.11.1 via `lune setup` (roblox, net, fs, serde, process, luau); lokale Tests mit Lune 0.11.1

Luau-RFCs:
- https://raw.githubusercontent.com/luau-lang/rfcs/master/docs/new-require-by-string-semantics.md
- https://raw.githubusercontent.com/luau-lang/rfcs/master/docs/require-by-string-aliases.md
- https://raw.githubusercontent.com/luau-lang/rfcs/master/docs/abstract-module-paths-and-init-dot-luau.md
- https://raw.githubusercontent.com/luau-lang/rfcs/master/docs/config-luauconfig.md

MCP-Referenzimplementierung:
- https://raw.githubusercontent.com/Roblox/studio-rust-mcp-server/main/README.md

Toolchain/Tests:
- Rokit: https://raw.githubusercontent.com/rojo-rbx/rokit/main/README.md, …/CHANGELOG.md
- Aftman: https://raw.githubusercontent.com/LPGhatguy/aftman/main/README.md
- Foreman: https://raw.githubusercontent.com/Roblox/foreman/main/README.md
- Wally: https://raw.githubusercontent.com/UpliftGames/wally/main/README.md, …/CHANGELOG.md, …/Cargo.toml
- pesde: https://raw.githubusercontent.com/pesde-pkg/pesde/main/README.md
- darklua: https://raw.githubusercontent.com/seaofvoices/darklua/main/README.md
- selene: https://raw.githubusercontent.com/Kampfkarren/selene/main/docs/src/roblox.md, …/CHANGELOG.md
- StyLua: https://raw.githubusercontent.com/JohnnyMorganz/StyLua/main/CHANGELOG.md
- luau-lsp: https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/README.md
- Jest Roblox: https://raw.githubusercontent.com/Roblox/jest-roblox/master/README.md, …/CHANGELOG.md
- Jest Lua: https://raw.githubusercontent.com/jsdotlua/jest-lua/main/README.md
- TestEZ: https://raw.githubusercontent.com/Roblox/testez/master/README.md, …/CHANGELOG.md
- run-in-roblox: https://raw.githubusercontent.com/rojo-rbx/run-in-roblox/master/README.md, …/Cargo.toml

Lokale Referenzdaten:
- `/root/tools/ref/API-Dump.json`, `/root/tools/ref/Full-API-Dump.json` (Engine 0.745.0.7451137),
  `/root/tools/ref/globalTypes.d.luau`
