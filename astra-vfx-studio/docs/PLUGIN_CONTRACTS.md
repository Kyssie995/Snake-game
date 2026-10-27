# Plugin Contracts (engineering spec)

> Implementer-facing (English). Overview in [`ARCHITECTURE.md`](ARCHITECTURE.md) §7. Studio facts with sources in
> `docs/research/api-studio-plugin.md` (sections 2.1–2.13, 4.x) — read §2.8 (input) and §4 before writing UI code.

## 0. Hard facts that shape the plugin (VERIFIED unless noted)

* Widgets: `plugin:CreateDockWidgetPluginGuiAsync(id, DockWidgetPluginGuiInfo.new(...))` (non-Async is deprecated;
  both yield). Stable ids — renaming loses users' saved layouts.
* `UserInputService` does **not** work inside widgets. Use `GuiObject.InputBegan/InputChanged/InputEnded`,
  `MouseEnter/MouseLeave/MouseMoved/MouseWheelForward/Backward` and `PluginGui:GetRelativeMousePosition()`.
  Keyboard input reaches `GuiObject.InputBegan` of a focused, `Active` full-size "input catcher" Frame after the user
  clicked it. Modifiers: `InputObject:IsModifierKeyDown(Enum.ModifierKey.Ctrl|Shift|Alt)`. Mouse wheel:
  `InputChanged` with `UserInputType.MouseWheel`, direction in `input.Position.Z`.
* `PluginGui.InputBegan/…`, `OverrideStudioAction` are RobloxScriptSecurity → Studio's global shortcuts (Delete,
  Ctrl+Z/C/V/D) probably still act on the Studio selection while an ASTRA widget is focused (ASSUMPTION).
  Mitigation: `SelectionSync` stashes and clears `Selection` when an ASTRA widget gains focus and restores it on
  focus release if the user did not select something else meanwhile (setting, default on).
* PluginActions/toolbar buttons cannot have default shortcuts (user binds them in File → Customize Shortcuts).
  PluginMenus: `CreatePluginMenu`, `AddNewAction/AddAction/AddMenu/AddSeparator/Clear`, `ShowAsync()` (yields,
  returns the chosen PluginAction or nil).
* `plugin.Unloading` auto-cleans toolbar buttons and widgets, NOT DataModel instances, connections to services, or
  open ChangeHistoryService recordings → idempotent `App:shutdown()`.
* Plugins also run inside Play DataModels during playtests: initialise the editor only when `RunService:IsEdit()`.
* ChangeHistoryService: `TryBeginRecording(name, displayName?) -> id?` (nil when a recording of this plugin is open or
  during playtests), `FinishRecording(id, Enum.FinishRecordingOperation.Commit|Cancel|Append)`, `Undo/Redo` (error
  when nothing to undo), `OnUndo/OnRedo(waypointName)`. Changes to `Archivable = false` instances are ignored by
  undo history (REPORTED) — preview instances are non-archivable.
* `plugin:SetSetting/GetSetting`: JSON-backed; keys must avoid `.` `"` `\` and newlines; values without `\`.
* No clipboard API and no arbitrary file writes for plugins. Import: `StudioService:PromptImportFileAsync({"json"})`
  → `File:GetBinaryContents()`. Export: copyable TextBox, `plugin:PromptSaveSelectionAsync(name)` (.rbxm),
  localhost Bridge (optional), Rojo.
* `HttpService` from plugins may call localhost/127.0.0.1; Studio asks the user once per domain.
* `Script.Source` is writable by plugins; prefer `ScriptEditorService:UpdateSourceAsync` when the script may be open.
* Sound preview in edit mode: `Sound.Playing` does not play; use `SoundService:PlayLocalSound(sound)` (best effort).
* ViewportFrame: no particles/beams/trails (REPORTED), no local lights (ASSUMPTION), no shadows/post-processing,
  Neon/Glass at lowest quality (VERIFIED).

## 1. Module map (`src/Plugin`)

```
init.server.luau     Bootstrap. if not RunService:IsEdit() then return end. Creates App, wires plugin.Unloading.
App.luau             App.new(plugin) -> App ; app:start() ; app:shutdown()  (idempotent)
Editor.luau          controller + state (§2)
Studio/History.luau  ChangeHistoryService wrapper (§3)
Studio/Storage.luau  documents in the place (§4)
Studio/Settings.luau plugin settings with safe keys (§5)
Studio/SelectionSync.luau  Studio Selection <-> component selection; stash/restore on widget focus
Studio/Bridge.luau   optional localhost bridge client (§8)
Studio/Shortcuts.luau PluginActions + in-widget key handling (§7)
Preview/PreviewEngine.luau   workspace preview (§6)
Preview/Stage.luau           isolated stage, mannequin, camera presets
Preview/ViewportPreview.luau geometry-only viewport preview
UI/Theme.luau, UI/New.luau, UI/Maid.luau, UI/Input.luau, UI/Widgets/*, UI/Editors/*, UI/Panels/*  (§9)
```

## 2. Editor (controller + state)

```lua
Editor.new(deps: { storage: Storage, history: History, settings: Settings }) -> Editor

-- read-only accessors (never mutate returned tables)
editor:getDocument() -> EffectDefinition?      ; editor:getDocumentId() -> string?
editor:getSelection() -> Selection
editor:getPlayback() -> Playback
editor:getView(panel: string) -> { [string]: any }
editor:getDiagnostics() -> ValidationResult     -- of the current document (recomputed on change)
editor:getAnalysis(quality: QualityLevel?) -> AnalysisReport?   -- lazy, cached per document version
editor:getVersion() -> number                   -- increments on every document change (incl. gestures)

-- documents
editor:open(id) -> boolean ; editor:close()
editor:newDocument(options: { name: string?, preset: string?, prompt: string?, definition: EffectDefinition? }) -> string
editor:importJson(text: string) -> (boolean, { Diagnostic })   -- migrate + validate + store as new document
editor:exportJson() -> string                                   -- canonical JSON of the current document
editor:duplicateDocument(id) -> string ; editor:deleteDocument(id) ; editor:renameDocument(id, name)

-- mutations (all go through Authoring/Ops)
editor:transact(label: string, mutate: (doc: EffectDefinition) -> any) -> any   -- ONE undo step
editor:beginGesture(label: string) ; editor:updateGesture(mutate) ; editor:endGesture(commit: boolean)
editor:undo() ; editor:redo()

-- selection
Selection = { components: { string }, keyframes: { KeyframeRef }, events: { EventRef }, markers: { string },
              nodes: { string }, links: { string }, primary: string? }   -- primary = last selected component
editor:select(kind: "components"|"keyframes"|"events"|"markers"|"nodes"|"links", items: { any },
              mode: "replace"|"add"|"toggle"|"remove"?)
editor:clearSelection(kind: string?)

-- playback (state only; PreviewEngine listens and drives the Player)
Playback = { playing: boolean, time: number, loop: boolean, loopStart: number, loopEnd: number,
             timeScale: number, quality: QualityLevel }
editor:play() ; editor:pause() ; editor:togglePlay() ; editor:stop() ; editor:restart() ; editor:seek(t)
editor:setLoop(b) ; editor:setLoopRange(a, b) ; editor:setTimeScale(n) ; editor:setPreviewQuality(level)
editor:reportTime(t)   -- PreviewEngine -> Editor while playing; fires changed("time") only

-- view state per panel ("timeline", "graph", "explorer", "inspector", "preview")
editor:setView(panel, patch: { [string]: any })

-- clipboard (in-memory; no OS clipboard API exists for plugins)
editor:copy(kind: "components"|"keyframes"|"nodes") -> boolean ; editor:paste(kind, options?) -> boolean

-- notifications
editor:notify(message: string, severity: "info"|"warning"|"error"?)

-- signals
editor.changed: Signal(kind: "document"|"selection"|"playback"|"time"|"view"|"diagnostics"|"library")
editor.notified: Signal(message, severity)
```
Rules: `transact` deep-copies the document, runs `mutate`, validates, and if the result has no *new* structural errors
(Validation errors that did not exist before) writes it through `History.record(label, storage:write)`. A mutation
that raises → nothing is written, `notify(error)`. Gestures keep a working copy, update preview/panels each call
(`changed("document")`), and write once in `endGesture(true)`; `endGesture(false)` restores the original. External
document changes (`storage.changed` with reason "external", e.g. Studio undo) reload the document, drop invalid
selection entries and fire `changed("document")`. Selection is pruned when items disappear.

## 3. History

```lua
History.new(service: ChangeHistoryService?) -> History
history:record(label: string, fn: () -> ()) -> (boolean, string?)   -- Try/FinishRecording(Commit); on error Cancel
history:undo() -> boolean ; history:redo() -> boolean                -- pcall-wrapped, false when nothing to undo
history:canUndo() -> boolean ; history:canRedo() -> boolean
history.undone: Signal(name) ; history.redone: Signal(name)          -- from OnUndo/OnRedo
history:cancelStale()                                                 -- on startup: cancel recordings left open
```
If `TryBeginRecording` returns nil (another recording open / playtest), `fn` still runs but `record` returns
`false, "no-recording"` and the Editor shows a warning toast ("Undo für diese Änderung nicht verfügbar").

## 4. Storage

Documents live in `ServerStorage.AstraVFX.Effects` as `StringValue`s named after the effect, value = canonical JSON
(`Exporter.toJson`), attributes `AstraId`, `AstraSchemaVersion`, `AstraUpdated` (os.time() at write — metadata only).
```lua
Storage.new() -> Storage
storage:list() -> { LibraryEntry }      -- documents + presets (Authoring/PresetLibrary) + synced sources
LibraryEntry = { id: string, name: string, description: string?, tags: { string }?,
                 kind: "document"|"preset"|"synced", instance: Instance?, updated: number? }
storage:read(id) -> (EffectDefinition?, { Diagnostic })   -- migrate + validate
storage:write(def: EffectDefinition)                      -- must be called inside History.record
storage:delete(id) ; storage:exists(id) -> boolean
storage:readSource(entry) -> (EffectDefinition?, { Diagnostic })  -- synced ModuleScript/StringValue/JSON
storage.changed: Signal(id: string, reason: "external"|"added"|"removed"|"written")
storage:destroy()
```
Synced sources: ModuleScripts/StringValues with the CollectionService tag `AstraEffectSource`, or children of
`ServerStorage.AstraVFX.Sources` / `ReplicatedStorage.AstraVFX.Effects` (exported effects). ModuleScripts are read
with `require(module:Clone())` (fresh require), StringValues/`.json` text with `Json.decode`. Storage watches its
folders (ChildAdded/ChildRemoved, `Changed` on values) and compares the value with the last text it wrote itself to
classify changes as "external". Values above 190 000 characters are rejected with a diagnostic.

## 5. Settings

```lua
Settings.new(plugin) -> Settings ; settings:get(key, default) ; settings:set(key, value)
```
Keys are prefixed `astra_v1_` and contain only `[A-Za-z0-9_]`; strings are hex-encoded when they contain `\` or
quotes. Known keys: `previewLocation`, `previewDistance`, `previewCharacter`, `previewQuality`, `timeScale`,
`loop`, `snap`, `bridgeEnabled`, `bridgeUrl`, `bridgeToken`, `stashStudioSelection`, `recentDocuments`.

## 6. Preview

```lua
PreviewEngine.new(editor: Editor) -> PreviewEngine
engine:setEnabled(boolean)                -- builds/destroys the preview
engine:setOptions(PreviewOptions)         -- location, distance, character, quality, showGizmos
PreviewOptions = { location: "camera"|"origin"|"selection"|"stage", distance: number,
                   character: "none"|"mannequin"|"selection", attachToCharacter: boolean }
engine:focusCamera(distance: number?)     -- moves workspace.CurrentCamera to look at the preview origin
engine:rebuild()                          -- force rebuild
engine:destroy()                          -- removes everything it created (idempotent)
PreviewEngine.cleanupStale()              -- removes leftover instances with attribute AstraPreview (crash recovery)
```
Behaviour: listens to `editor.changed` ("document" → debounced 0.1 s recompile + rebuild; "playback" → play/pause/
seek/loop/timeScale/quality). Builds with `Builder.build(compiled, { parent = previewFolder, isPreview = true })`
into `Workspace.AstraVFX_Preview` (`Archivable = false`). Drives the Player with its own RunService.Heartbeat
connection only while playing (disconnects when paused/stopped), reports time via `editor:reportTime(t)`, applies
`loop`/`loopStart`/`loopEnd` (seek to loopStart when passing loopEnd). Scrubbing → `player:seek(t)`. Stage:
anchored dark floor plate + backdrop far from the scene (y = 5000), camera moved there and restored on exit.
Mannequin: simple R15-proportioned block figure (Parts) as size reference / attach target.
ViewportPreview: separate geometry-only build (`viewport = true`) inside a ViewportFrame + WorldModel with an
orbit camera (drag to orbit, wheel to zoom); shows a permanent notice "Partikel, Beams, Trails und Lichter werden
im ViewportFrame von Roblox nicht dargestellt – Platzhalter".

## 7. Shortcuts

PluginActions (bindable by the user): `astra_play_pause`, `astra_stop`, `astra_restart`, `astra_add_keyframe`,
`astra_delete`, `astra_duplicate`, `astra_copy`, `astra_paste`, `astra_frame_preview`, `astra_toggle_loop`,
`astra_next_key`, `astra_prev_key`, `astra_undo`, `astra_redo`. In-widget keys (focused input catcher):
Space play/pause, Home/End jump, Left/Right step 1/60 s (Shift = 0.1 s), K add keyframe, Delete/Backspace delete,
Ctrl+D duplicate, Ctrl+C/Ctrl+V copy/paste, F frame, L loop, Ctrl+Z/Ctrl+Y undo/redo (also handled by Studio).

## 8. Bridge (optional, default OFF)

Lune server `tools/bridge.luau` on `http://localhost:34873` (configurable), token printed at start.
```
GET  /v1/status                 -> { name: "astra-bridge", version, effectsDir }
GET  /v1/effects                -> [ { name, file, hash } ]
GET  /v1/effects/<name>         -> effect JSON (text)
PUT  /v1/effects/<name>         -> body = effect JSON; validated with Core/Validation; written canonically
                                   -> { ok, diagnostics }
```
Header `X-Astra-Token` required. The plugin polls `/v1/effects` every 2 s while enabled, offers "Laden" for new/
changed files, and "Zur Bridge speichern" writes the current document.

## 9. UI toolkit

* `Theme`: dark anthracite palette tokens (fixed, does not follow the Studio theme — product requirement):
  `bg0 #17181B` (window), `bg1 #1F2024` (panel), `bg2 #27292E` (raised/input), `bg3 #30333A` (hover),
  `border #34373E`, `borderStrong #454952`, `text #E4E6EB`, `textDim #A1A5AE`, `textMuted #6C717B`,
  `accent #8B6CFF`, `accentDim #3B2F6E`, `teal #33C3B0`, `warning #F0B54A`, `error #F2555A`, `success #48C08A`,
  `keyframe #F2C14E`, `playhead #FF4F6E`, `loop #2E7DFF`; pin kind colours (exec white, number #7FD1FF,
  vector3 #FFC857, color3 #FF7AB6, boolean #E36A6A, string #B5E48C, component #8B6CFF, any #A1A5AE).
  Fonts: `Font.fromEnum(Enum.Font.BuilderSans)` (+Medium/Bold), mono `Enum.Font.RobotoMono`. Sizes: text 13/12/11,
  row 24, padding 6/8, corner 4. No blur.
* `New(className, props, children?) -> Instance` — props set in order; keys `On<Event>` connect
  `inst[Event]` (e.g. `OnActivated`, `OnInputBegan`), `OnChange<Prop>` connects `GetPropertyChangedSignal(Prop)`,
  `Parent` applied last. Children: array of instances (or nil holes).
* `Maid`: `Maid.new()`, `maid:give(task)` (connection, instance, function, or object with `Destroy`/`destroy`),
  `maid:clean()`. Every panel owns a Maid and cleans it in `destroy()`.
* `Input`: `Input.catcher(parent) -> Frame` (full size, Active, transparent, receives keyboard after click);
  `Input.onKey(catcher, fn(keyCode, mods: { ctrl, shift, alt }))`; `Input.drag(host, guiObject, handlers)` with
  `handlers.onStart(pos)/onMove(pos, delta)/onEnd(pos, cancelled)`, implemented with InputBegan + polling
  `host.widget:GetRelativeMousePosition()` each Heartbeat until InputEnded / WindowFocusReleased; `Input.wheel(gui,
  fn(direction, pos))`; `Input.doubleClick` detection via `Activated(input, clickCount)`.
* Host object passed to panels: `Host = { plugin: Plugin, widget: DockWidgetPluginGui, root: Frame, editor: Editor,
  menus: Menus }`. Panels: `Panel.new(host) -> Panel` with `panel:destroy()`. Panels must be constructible in Lune
  with fake `plugin`/`widget` objects (tests construct every panel to validate instance properties).
* Widgets (UI/Widgets): Button, IconButton, Label, TextInput (ClearTextOnFocus = false), NumberInput (drag-scrub),
  Slider, Checkbox, Dropdown (in-widget popup), ColorSwatch, Vector3Input, Vector2Input, NumberRangeInput,
  AssetInput (+ `plugin:PromptForExistingAssetIdAsync`), SearchBox, ScrollList (virtualised rows), Tree,
  Splitter, Tabs, Tooltip, Toast, Dialog (confirm / prompt / long text with selectable TextBox), PropertyRow.
* Editors (UI/Editors): ColorPicker (HSV square + hue bar + hex + RGB), GradientEditor (ColorSequence; UIGradient
  preview; ≤ 20 keypoints), SequenceEditor (NumberSequence curve with envelope, presets, bezier-style smoothing baked
  to ≤ 20 linear keys via `Curves.bakeToSequenceKeypoints`), EasingPicker (style × direction thumbnails + bezier),
  CurveGraph (track value curves in the timeline; drawn with `Path2D` or line Frames).
* Panels (UI/Panels): Library, Explorer, Inspector, Timeline, Graph, Preview (controls + ViewportPreview),
  Performance (analyzer report, labelled "heuristisch"), Diagnostics.

Widget ids (stable): `AstraVFX_Library`, `AstraVFX_Explorer`, `AstraVFX_Inspector`, `AstraVFX_Timeline`,
`AstraVFX_Graph`, `AstraVFX_Preview`, `AstraVFX_Performance`. Toolbar "ASTRA VFX": `Studio` (open all main panels),
one button per panel (active state mirrors `widget.Enabled`), `Export`, `Self-Test`.
