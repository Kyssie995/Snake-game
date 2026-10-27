# Recherche: Roblox-Studio-Plugin-APIs und Studio-Verhalten für einen andockbaren Editor

Stand: 2026-10-27 · Phase 1 (Research & Architecture) für ASTRA VFX STUDIO · Engine-Stand der lokalen Daten: **0.745.0.7451137**

> **Label-Legende:** **VERIFIED** = offizielle creator-docs (per `raw.githubusercontent.com/Roblox/creator-docs`), lokaler API-Dump 0.745 (`/root/tools/ref/API-Dump.json`, `Full-API-Dump.json`), luau-lsp-Typen (`globalTypes.d.luau`) oder der eigene Quelltext eines Produkts · **REPORTED** = DevForum-Posts und Drittseiten, hier nur über WebSearch-Zusammenfassungen gelesen · **ASSUMPTION** = eigene Schlussfolgerung · **IDEA** = eigener Designvorschlag für ASTRA. **⚑ = kritisch**: Eine ASTRA-Architekturentscheidung hängt daran.

> **Quellenlage:** DevForum, create.roblox.com, GitHub-Weboberfläche und YouTube waren aus der Sandbox nicht erreichbar. DevForum-Aussagen stammen deshalb ausschließlich aus Such-Snippets und sind höchstens **REPORTED**. **Während dieser Recherche war das WebSearch-Budget der Sitzung erschöpft** (geteiltes Limit aller Agents). Einige Punkte (Größenlimit von `SetSetting`, Clipboard-Workarounds, Team-Create-Verhalten von `Archivable=false`) konnten deshalb nicht mehr im Web gesucht werden und stehen unter „Offene Fragen“. Code von Dritten wurde nur gelesen, nicht kopiert: Rojo-Plugin-Quelltext nur zur Bestätigung von Host, Port und WebSocket-Nutzung.

---

## 1. Zusammenfassung

1. **Dock-Widgets ⚑**: Neu wird `plugin:CreateDockWidgetPluginGuiAsync(id, DockWidgetPluginGuiInfo)` verwendet. `CreateDockWidgetPluginGui` ist im API-Dump 0.745 als `Deprecated` markiert (`PreferredDescriptorName = CreateDockWidgetPluginGuiAsync`). Beide yielden. Dock-Zustand, Größe und Sichtbarkeit merkt sich Studio pro `pluginGuiId`, und dieser gespeicherte Zustand hat Vorrang vor `InitialDockState`. `BindToClose` kann das Schließen **nicht verhindern**. `plugin.Unloading` räumt Widgets, Toolbar-Buttons und PluginGuis automatisch auf, eigene Instanzen im DataModel aber **nicht**.
2. **Eingabe in Widgets ⚑**: `UserInputService` funktioniert in Widgets **nicht** (offizieller Guide). Die Widget-eigenen Events `PluginGui.InputBegan`, `InputChanged`, `InputEnded`, `MouseEnter`, `MouseLeave` und `PointerAction` sind `RobloxScriptSecurity` und damit für Plugins gesperrt. Plugins nutzen nur die `GuiObject`-Events (`InputBegan`/`InputChanged`/`InputEnded`, `MouseWheelForward`/`Backward`, `MouseMoved`), `PluginGui:GetRelativeMousePosition()` sowie `WindowFocused`/`WindowFocusReleased`. Tastatureingaben kommen über `GuiObject.InputBegan`, nachdem der Nutzer in den Frame geklickt hat. Studio-Aktionen lassen sich nicht überschreiben (`OverrideStudioAction` ist `RobloxScriptSecurity`).
3. **Undo/Redo ⚑**: `ChangeHistoryService:TryBeginRecording(name, displayName?) -> id?` und `FinishRecording(id, Commit|Cancel|Append, finalOptions?)`. Pro Plugin ist höchstens **eine** Recording aktiv. Beim Solo-Playtest schlägt sie fehl. Ein Plugin-Reload bricht sie **nicht** ab. `SetWaypoint` gilt laut Doku als „bald deprecated“, ist im Dump aber noch nicht so markiert. `Undo()`, `Redo()`, `GetCanUndo()`, `GetCanRedo()`, `IsRecordingInProgress()`, `OnUndo`/`OnRedo` sowie `OnRecordingStarted`/`OnRecordingFinished` stehen Plugins zur Verfügung. Laut DevForum ignoriert der Service Instanzen mit `Archivable=false` (REPORTED).
4. **Dateien ⚑**: Lesen geht per Dialog: `StudioService:PromptImportFileAsync({"json"})` → `File:GetBinaryContents()`, maximal 100 MB. **Beliebige Dateien schreiben geht nicht.** Möglich sind nur Dialoge: `Plugin:PromptSaveSelectionAsync()` speichert die Selektion als Modell, `PluginManager:ExportSelection/ExportPlace` als `.obj`. Die Zwischenablage ist für Plugins nicht lesbar und nicht schreibbar (`UserInputService:GetPasteText` und `StudioService:CopyToClipboard` sind `RobloxScriptSecurity`). Der einzige programmatische Kanal nach außen ist **`HttpService` zu `localhost`/`127.0.0.1`**, inklusive **WebSocket** über `HttpService:CreateWebStreamClient` (nur in Studio, höchstens 4 Clients).
5. **Preview ⚑**: `ViewportFrame` rendert offiziell keine Schatten und kein Post-Processing. Laut mehreren DevForum-Threads rendert er auch **keine ParticleEmitter, Beams und Trails** (REPORTED). Eine Live-Vorschau der nativen VFX-Primitive im Widget ist damit ausgeschlossen. Die Vorschau muss im **3D-Viewport (Workspace) im Edit Mode** laufen. Dort emittieren ParticleEmitter laut Doku sofort, und `Emit()` funktioniert aus Plugins.
6. **Skripte und Assets**: `Script.Source` dürfen Plugins lesen und schreiben (Capability `PluginOrOpenCloud`). Für Skripte, die womöglich im Editor offen sind, empfiehlt Roblox `ScriptEditorService:UpdateSourceAsync`. `MeshPart.MeshId` und `MeshContent` haben `Write = NotAccessibleSecurity` und sind auch für Plugins **nicht schreibbar**. Der Weg führt über `AssetService:CreateMeshPartAsync` und `MeshPart:ApplyMesh`. `SpecialMesh.MeshId` bleibt frei schreibbar.

---

## 2. Befunde

### 2.1 Dock-Widgets, Lebenszyklus, Settings

| # | Befund | Label | Quelle |
|---|---|---|---|
| W1 | `Plugin:CreateDockWidgetPluginGuiAsync(pluginGuiId: string, info: DockWidgetPluginGuiInfo) -> DockWidgetPluginGui`, Tags `Yields`, `PluginSecurity`. `CreateDockWidgetPluginGui` (gleiche Signatur) hat die Tags `Yields`, `Deprecated` und `PreferredDescriptorName = CreateDockWidgetPluginGuiAsync`. Die Doku nennt die alte Methode „superseded“. **⚑** | VERIFIED | API-Dump 0.745; Plugin.yaml |
| W2 | Die Umbenennung gehört zu einer Roblox-PSA („Several common yielding methods have been renamed“), laut Drittseite in Version 702 (Dez. 2025). Die alten Namen sollen weder geändert noch entfernt werden. Der Guide `build-studio-widgets.md` zeigt noch den alten Namen. | REPORTED (PSA) / VERIFIED (Guide-Stand) | devforum.roblox.com/t/psa-several-common-yielding-methods-have-been-renamed/4257585; build-studio-widgets.md |
| W3 | Auch andere Plugin-Methoden haben jetzt Async-Nachfolger: `PromptSaveSelection` → `PromptSaveSelectionAsync`, `ImportFbxRig/Animation` → `…Async`, `StudioService:PromptImportFile(s)` → `PromptImportFile(s)Async`. `PromptForExistingAssetId` und `…Async` existieren beide, die alte Variante noch ohne Deprecated-Tag. | VERIFIED | API-Dump 0.745 |
| W4 | `DockWidgetPluginGuiInfo.new(InitialDockState=Right, InitialEnabled=false, InitialEnabledShouldOverrideRestore=false, FloatingXSize=0, FloatingYSize=0, MinWidth=0, MinHeight=0)`. Die Parameter sind **positional** und optional (luau-lsp: alle `?`). `FloatingX/YSize` gelten nur bei `Float`. `MinWidth` hat ein plattformabhängiges absolutes Minimum (Mac ca. 80 px). | VERIFIED | DockWidgetPluginGuiInfo.yaml; build-studio-widgets.md; globalTypes.d.luau Z. 20384 |
| W5 | `Enum.InitialDockState`: Top=0, Bottom=1, Left=2, Right=3, Float=4. Gibt es zum Widget einen gespeicherten Layout-Eintrag, wird `InitialDockState` ignoriert und `DockWidgetPluginGui.HostWidgetWasRestored` ist `true`. Der gespeicherte Enabled-Zustand wird nur überschrieben, wenn `InitialEnabledShouldOverrideRestore=true`. **⚑** (IDs dürfen sich nie ändern) | VERIFIED | InitialDockState.yaml; DockWidgetPluginGuiInfo.yaml |
| W6 | Sichtbarkeit steuert `LayerCollector.Enabled`, den Titel `PluginGui.Title`. `DockWidgetPluginGui:RequestRaise()` (Widget nach vorne holen) ist `RobloxScriptSecurity`, für Plugins also nicht nutzbar. | VERIFIED | API-Dump 0.745 |
| W7 | `PluginGui:BindToClose(fn?)` läuft, wenn der Nutzer auf das Schließen-Kreuz klickt. Das Widget schließt trotzdem und `Enabled` wird `false`. Die Funktion kann das Schließen **weder verhindern noch verzögern**. Ein Aufruf ohne Argument entfernt die Bindung. | VERIFIED | PluginGui.yaml |
| W8 | `plugin.Unloading` feuert unmittelbar, bevor das Plugin stoppt: beim Deaktivieren, Deinstallieren, vor einem Update und beim Schließen des Places. `PluginToolbarButton`s, `DockWidgetPluginGui`s und `PluginGui`s werden automatisch entfernt. **Eigene Instanzen im DataModel**, etwa Preview-Objekte, muss das Plugin selbst entfernen, sonst bleiben alte Kopien stehen. **⚑** | VERIFIED | Plugin.yaml (Unloading) |
| W9 | `plugin:Activate(exclusiveMouse)` macht dieses Plugin zum einzigen aktiven. Alle anderen Plugins erhalten `Deactivation`, und die Buttons in ihren Toolbars springen auf „aus“. Sind alle Buttons einer Toolbar aus, wird deren Plugin deaktiviert. `plugin:Deactivate()` gibt die `PluginMouse` frei. `IsActivated()` und `IsActivatedWithExclusiveMouse()` existieren. | VERIFIED | Plugin.yaml; PluginToolbarButton.yaml |
| W10 | `plugin:SetSetting(key, value)` und `GetSetting(key)` speichern dauerhaft (auch über Studio-Neustarts) als **JSON-Map mit String-Keys**. Arrays werden zu Maps mit String-Schlüsseln. Erlaubte Werte: string, number, boolean, table, nil, also **kein** Color3, Vector3 oder EnumItem. Diese Zeichen können die Settings-Datei **korrumpieren**: Backslash in Keys **oder Werten** (besonders `\"`), Newline in Keys, `"` in Keys, **`.` in Keys**. Beide Methoden können **still fehlschlagen**, wenn mehrere Studio-Fenster dasselbe Plugin gleichzeitig nutzen. `GetSetting` liefert dann `nil`. **⚑** | VERIFIED | Plugin.yaml (GetSetting/SetSetting) |
| W11 | Ein Größenlimit für Settings ist **nicht dokumentiert**. Gefunden wurde keines; die Websuche war erschöpft. | — (nicht gefunden) | — |
| W12 | `Plugin.HostDataModelType` (`Enum.StudioDataModelType`: Edit, PlayClient, PlayServer, Standalone, None) existiert, ist aber `RobloxScriptSecurity`. Plugins können so nicht direkt erfragen, in welchem DataModel sie laufen. Als Ersatz dienen `RunService:IsEdit()`, `IsRunning()`, `IsClient()` und `IsServer()`. | VERIFIED | API-Dump 0.745; RunService.yaml |
| W13 | Plugins laufen während eines Playtests auch in den Play-DataModels (Client/Server) erneut. | ASSUMPTION (verbreitetes Wissen, in dieser Sitzung nicht belegt) | — |

### 2.2 Toolbar, PluginAction, PluginMenu

| # | Befund | Label | Quelle |
|---|---|---|---|
| T1 | `plugin:CreateToolbar(name) -> PluginToolbar`. Danach `toolbar:CreateButton(buttonId, tooltip, iconname, text="") -> PluginToolbarButton`. `CreatePopupButton` (Dropdown-Button) ist `RobloxScriptSecurity`. | VERIFIED | API-Dump 0.745; PluginToolbar.yaml |
| T2 | `PluginToolbarButton`: Event `Click`, `SetActive(bool)` (gedrückter Zustand), `Enabled`, `ClickableWhenViewportHidden`, `Icon` (ContentId), `IconContent` (Content, PluginSecurity, nur Asset-URIs). Ist der 3D-Viewport verborgen (etwa ein Skript-Tab offen), sind Buttons deaktiviert, außer `ClickableWhenViewportHidden=true`. Für einen „Widget öffnen“-Button empfiehlt die Doku ausdrücklich `true`. | VERIFIED | PluginToolbarButton.yaml |
| T3 | Toolbar-Buttons **und** `PluginAction`s kann der Nutzer selbst unter **File ⟩ Customize Shortcuts** mit Tastenkürzeln belegen. | VERIFIED | PluginToolbarButton.yaml; PluginAction.yaml |
| T4 | `plugin:CreatePluginAction(actionId, text, statusTip, iconName="", allowBinding=true) -> PluginAction`. Event `Triggered`. Lesbar sind `ActionId`, `AllowBinding`, `StatusTip` und `Text`. **Gesperrt** (`RobloxScriptSecurity`) sind: `Text` schreiben, `Enabled`, `Checked`, `Visible` und `DefaultShortcut`. Plugins können also **kein Standard-Kürzel vorgeben**, Actions nicht deaktivieren oder abhaken und den Text nachträglich nicht ändern. **⚑** | VERIFIED | API-Dump 0.745; PluginAction.yaml |
| T5 | `plugin:CreatePluginMenu(id, title="", icon="") -> PluginMenu`. Methoden: `AddAction(action)`, `AddNewAction(actionId, text, icon="")` (temporäre Action, im Shortcut-Fenster verborgen), `AddMenu(menu)` (Untermenü mit dessen `Title`/`Icon`; die Doku-Zusammenfassung „as a separator“ ist offensichtlich ein Fehler), `AddSeparator()`, `Clear()`, `ShowAsync()`. `ShowAsync` yieldet, öffnet **am Mauszeiger** und gibt die gewählte `PluginAction` oder `nil` zurück. Die gewählte Action feuert zusätzlich `Triggered`. `PluginMenu.Visible` ist `RobloxScriptSecurity`. | VERIFIED | API-Dump 0.745; PluginMenu.yaml |
| T6 | Grenzen der Kontextmenüs: keine frei wählbare Position, keine Häkchen, keine deaktivierten Einträge, keine eigenen Widgets im Menü. Dynamische Menüs gehen nur per `Clear()` und `AddNewAction`. | VERIFIED (aus T4/T5 abgeleitet) | API-Dump 0.745 |
| T7 | In der `Unloading`-Doku werden nur Toolbar-Buttons, DockWidgets und PluginGuis als automatisch aufgeräumt genannt. Ob `PluginAction`s und `PluginMenu`s mitentfernt werden, ist offen. Eine doppelte `actionId` nach einem Reload kann Konflikte auslösen. | ASSUMPTION | Plugin.yaml |

### 2.3 ChangeHistoryService (Undo/Redo)

| # | Befund | Label | Quelle |
|---|---|---|---|
| C1 | Plugins **müssen** CHS benutzen. Vor Änderungen kommt `TryBeginRecording(name, displayName?) -> string?`, danach `FinishRecording(identifier, operation, finalOptions?)`. Die Doku verlangt den Aufruf vor Änderungen ausdrücklich, „to avoid future warnings or errors“. **⚑** | VERIFIED | ChangeHistoryService.yaml; studio/plugins.md |
| C2 | `TryBeginRecording` liefert `nil`, wenn das Plugin schon eine Recording offen hat (**höchstens eine pro Plugin**) oder wenn der Nutzer im **Solo-Playtest** ist. **⚑** | VERIFIED | ChangeHistoryService.yaml |
| C3 | `Enum.FinishRecordingOperation`: `Cancel=0` verwirft die Recording und macht die erfassten Änderungen **automatisch rückgängig**; der Identifier wird dabei ignoriert, das Plugin kann also die eigene laufende Recording ohne ID abbrechen. `Commit=1` legt einen neuen Waypoint an. `Append=2` committet und **verschmilzt mit dem vorherigen Waypoint**, „wenn möglich“. `FinishRecording` wirft einen Fehler, wenn keine Recording läuft oder (außer bei Cancel) die ID nicht passt. Es wirkt nicht, solange der Service deaktiviert ist oder gerade ein Undo/Redo läuft. **⚑** | VERIFIED | ChangeHistoryService.yaml; FinishRecordingOperation.yaml |
| C4 | Ein Plugin-Reload bricht laufende Recordings **nicht** ab. Roblox empfiehlt, die letzte Recording-ID z. B. in Attributen zu speichern und nach dem Reload abzubrechen. Ein DevForum-Bugreport bestätigt, dass Studio Recordings entladener Plugins nicht aufräumt. **⚑** | VERIFIED (Doku-Warnung) / REPORTED (Bug) | studio/plugins.md; devforum.roblox.com/t/studio-doesnt-clean-up-changehistoryservice-recordings-for-unloaded-plugins/4108638 |
| C5 | `IsRecordingInProgress(identifier?) -> bool`: Ohne Argument fragt es, ob **irgendeine** Recording dieses Plugins läuft, mit Argument, ob genau diese. | VERIFIED | ChangeHistoryService.yaml |
| C6 | `Undo()` und `Redo()` dürfen Plugins aufrufen (PluginSecurity). Sie werfen einen Fehler, wenn gerade ein Play läuft, der Service deaktiviert ist oder es nichts rückgängig zu machen bzw. zu wiederholen gibt. Vorher `GetCanUndo()`/`GetCanRedo()` prüfen; sie liefern ein Tupel `(bool, name?)`. | VERIFIED | ChangeHistoryService.yaml |
| C7 | `OnUndo(waypoint: string)` und `OnRedo(waypoint: string)` feuern **nach** jedem Undo bzw. Redo, egal ob der Nutzer es auslöst oder ein Skript. `OnRecordingStarted(name, displayName?)` und `OnRecordingFinished(name, displayName?, identifier?, operation, finalOptions?)` feuern für Recordings. Offen ist, ob `waypoint` bei Recordings `name` oder `displayName` enthält. **⚑** (ASTRA muss den internen Zustand nach Undo neu laden.) | VERIFIED (Events) / offen (Namensinhalt) | ChangeHistoryService.yaml |
| C8 | `SetWaypoint(name)` ist laut Doku „will be deprecated soon“, trägt im API-Dump 0.745 aber **keinen** Deprecated-Tag. Die Doku beschreibt das Modell als „Strom von Property-Änderungen“. Ein Waypoint schneidet diesen Strom und setzt damit die Grenze für Undo und Redo. | VERIFIED | ChangeHistoryService.yaml; API-Dump |
| C9 | **Änderungen außerhalb einer Recording**: Nach dem Strom-Modell (C8) landen sie im nächsten Waypoint, auch in dem einer fremden oder vom Nutzer ausgelösten Aktion. Ein Undo dieser Aktion nimmt sie dann mit zurück. Die Doku kündigt dafür Warnungen oder Fehler an. Den genauen Warntext habe ich nicht gefunden. **⚑** | ASSUMPTION (aus C1/C8) | ChangeHistoryService.yaml |
| C10 | Instanzen mit `Archivable=false` zeichnet CHS nicht auf. Gemeldet wird das als Fix für Plugin-Previews, die beim Undo gelöscht und neu angelegt wurden. **⚑** (Grundlage für das Preview-Konzept) | REPORTED | devforum.roblox.com/t/archivable-and-changehistoryservice/11953; devforum.roblox.com/t/problems-with-plugins-selection-and-changehistoryservice/311724 |
| C11 | `SetEnabled(false)` **löscht** die Undo-Liste. `ResetWaypoints()` fasst die ganze Historie in einen Waypoint `base` zusammen. Beides zerstört die Historie des Nutzers. Zur Laufzeit (im Spiel) ist CHS deaktiviert. | VERIFIED | ChangeHistoryService.yaml |
| C12 | Die Multi-line Command Bar nutzt ebenfalls CHS-Recordings. Dort sollte kein Code dauerhaft laufen. | VERIFIED | studio/plugins.md |

### 2.4 Selection

| # | Befund | Label | Quelle |
|---|---|---|---|
| S1 | `Selection:Get() -> {Instance}`, `Set({Instance})`, `Add({Instance})`, `Remove({Instance})` (alle PluginSecurity). Event `SelectionChanged()` **ohne Parameter**, die neue Selektion holt man mit `Get()`. `Set` feuert nicht, wenn die neue Selektion identisch ist. | VERIFIED | Selection.yaml; API-Dump |
| S2 | `Selection.SelectionThickness` (lesbar, Default 0,02) eignet sich, um eigene Overlays an die Studio-Optik anzupassen. `ActiveInstance`, `RenderMode`, `SelectionChangedThisFrame` und `AddFocusCallback` sind `RobloxScriptSecurity`. | VERIFIED | Selection.yaml; API-Dump |
| S3 | Selektionsänderungen werden in CHS-Recordings **nicht** zuverlässig erfasst und in der Doku dazu nicht erwähnt. Selection getrennt von Undo behandeln. | ASSUMPTION | — |

### 2.5 Dateien, Zwischenablage, Serialisierung

| # | Befund | Label | Quelle |
|---|---|---|---|
| F1 | `StudioService:PromptImportFileAsync(fileTypeFilter={}) -> File?` öffnet einen Dateidialog für eine Datei. Rückgabe `nil` bei Abbruch oder bei mehr als **100 MB**. Filter ohne Punkt, z. B. `{"json"}`. `PromptImportFilesAsync` (mehrere Dateien) liefert eine Liste, `nil`, wenn eine Datei zu groß ist, und wirft laut Doku bei einer **leeren** Filterliste einen Fehler. Die alten Namen ohne `Async` sind deprecated. **⚑** | VERIFIED | StudioService.yaml; API-Dump |
| F2 | `File:GetBinaryContents() -> string` liefert die Rohbytes und eignet sich für JSON-Import per `HttpService:JSONDecode`. `File:GetTemporaryId() -> ContentId` liefert eine `rbxtemp://`-ID, die wie `rbxassetid://` nutzbar ist (Doku-Beispiel: `ImageLabel.Image`). Sie gilt nur in dieser Studio-Sitzung, wird mit dem `File` zerstört und **nicht** in Collaborative Sessions geteilt. `File.Size` ist Hidden, PluginSecurity. | VERIFIED | File.yaml |
| F3 | **Beliebige Dateien schreiben: nicht möglich.** Im API-Dump gibt es für Plugins nur dialoggesteuerte Exporte: `Plugin:PromptSaveSelectionAsync(suggestedFileName) -> bool` speichert die aktuelle Selektion, `PluginManager:ExportSelection/ExportPlace` exportiert Geometrie als `.obj` (der Pfadparameter wird ignoriert, der Nutzer wählt im Dialog). **⚑** | VERIFIED (Dump-Durchsuchung nach Save/Export/Write/File) | API-Dump 0.745; Plugin.yaml; PluginManager.yaml |
| F4 | `PromptSaveSelectionAsync` erzeugt `.rbxm` bzw. `.rbxmx`. Eine reine `.json`-Datei lässt sich so nicht schreiben. | ASSUMPTION | — |
| F5 | **Zwischenablage**: `StudioService:CopyToClipboard` und `UserInputService:GetPasteText` sind `RobloxScriptSecurity`. Plugins haben **keinen** Clipboard-Zugriff. Was bleibt, ist der Nutzer selbst: Ctrl+V in eine `TextBox` und Kopieren aus einer TextBox. **⚑** | VERIFIED (Sperre) / ASSUMPTION (TextBox-Weg) | API-Dump 0.745 |
| F6 | `SerializationService:SerializeInstancesAsync({Instance}) -> buffer` und `DeserializeInstancesAsync(buffer) -> {Instance}` serialisieren in den `.rbxm`-Binärformat. Nutzbar nur in Studio-Plugins und Open-Cloud-Luau-Execution (`PluginOrOpenCloud`). Für das Format gibt es **keine Stabilitätszusage**. | VERIFIED | SerializationService.yaml; API-Dump |

### 2.6 ScriptEditorService vs. `Script.Source`

| # | Befund | Label | Quelle |
|---|---|---|---|
| SE1 | `Script.Source` und `ModuleScript.Source` (`ProtectedString`) haben Security None/None mit Capability `PluginOrOpenCloud` für Lesen und Schreiben. Plugins dürfen beides, normale Spielskripte nicht (Fehler). Die Doku rät vom direkten Editieren ab, wenn der Nutzer das Skript offen hat. | VERIFIED | Full-API-Dump; Script.yaml |
| SE2 | `ScriptEditorService:UpdateSourceAsync(script, callback(oldSource) -> newSource?)` yieldet. Ist das Skript im Editor offen, schickt es eine Update-Anfrage an den Editor. Der Editor kann sie ablehnen, wenn `Source` veraltet war; dann wird der Callback **erneut** aufgerufen. Der Callback darf **nicht yielden**. Gibt er `nil` zurück, bricht die Operation ab. Ist das Skript nicht offen, wird die Source direkt gesetzt. **⚑** (für generierte Runtime-ModuleScripts) | VERIFIED | ScriptEditorService.yaml |
| SE3 | `GetEditorSource(script)` liefert die **Edit-Time-Source**, also den Editor-Text. Sie kann von `Script.Source` abweichen. Weitere Methoden: `OpenScriptDocumentAsync(script, options?)`, `FindScriptDocument`, `GetScriptDocuments`, Events `TextDocumentDidOpen`, `DidChange`, `DidClose`, Autocomplete- und ScriptAnalysis-Callbacks. `Plugin:OpenScript` ist deprecated zugunsten von `OpenScriptDocumentAsync`. | VERIFIED | ScriptEditorService.yaml; Plugin.yaml; API-Dump |
| SE4 | In Team Create gibt es „Live Scripting“ (Standard) und optional einen Drafts-Modus. Wie `Script.Source`-Schreibzugriffe von Plugins mit Drafts zusammenspielen, ist nicht dokumentiert. | VERIFIED (Modi) / offen (Plugin-Verhalten) | projects/collaboration.md |

### 2.7 Studio-Theme

| # | Befund | Label | Quelle |
|---|---|---|---|
| TH1 | `settings().Studio.Theme` (`StudioTheme`, PluginSecurity) → `Theme:GetColor(Enum.StudioStyleGuideColor, Enum.StudioStyleGuideModifier = Default) -> Color3`. Ein Themenwechsel feuert `settings().Studio.ThemeChanged` (PluginSecurity). Zusätzlich gibt es `Studio:GetAvailableThemes()`. `Studio["UI Theme"]` ist deprecated. **⚑** (Theming-Schicht) | VERIFIED | StudioTheme.yaml; Studio.yaml; API-Dump |
| TH2 | `StudioStyleGuideColor` hat in 0.745 **130** Einträge, darunter MainBackground, Titlebar, Dropdown, Tooltip, ScrollBar, ScrollBarBackground, Tab, Button, MainButton, InputFieldBackground, InputFieldBorder, Item, TableItem, CategoryItem, Border, Separator, DropShadow, MainText, SubText, DimmedText, BrightText, LinkText, WarningText, ErrorText, InfoText, CheckedFieldBackground/Border/Indicator, HeaderSection, Midlight, Light, Dark, Mid, ViewPortBackground, ColorPickerFrame, CurrentMarker, DialogButton/DialogMainButton(+Text/Border), StatusBar, ScriptEditorCurrentLine sowie Diff- und Script-Syntaxfarben. `StudioStyleGuideModifier`: Default, Selected, Pressed, Disabled, Hover. | VERIFIED | API-Dump 0.745 |
| TH3 | `Studio.Theme` lässt sich mit PluginSecurity auch **setzen**. Ein Plugin sollte das nie tun. | VERIFIED | Studio.yaml |
| TH4 | `StudioService:GetClassIcon(className) -> {Image, ImageRectOffset, ImageRectSize}` liefert die Explorer-Icons. Für einen eigenen Effect Explorer ist das ideal. | VERIFIED | StudioService.yaml |

### 2.8 Eingabe in DockWidgetPluginGui

| # | Befund | Label | Quelle |
|---|---|---|---|
| I1 | `UserInputService` funktioniert in Widgets **nicht**, weil der Dienst den Fokus im Hauptspielfenster erwartet. `TextBox` und `TextButton` funktionieren normal. Für generische Eingabe empfiehlt Roblox einen transparenten Vollflächen-`Frame`: Nach einem Klick darauf liefert `GuiObject.InputBegan` Tastatureingaben, bis der Nutzer woanders hinklickt. **⚑** | VERIFIED | build-studio-widgets.md |
| I2 | `PluginGui.InputBegan`, `InputChanged`, `InputEnded`, `MouseEnter`, `MouseLeave`, `PointerAction` (Wheel/Pan/Pinch) sowie `PluginGui:OverrideStudioAction` sind `RobloxScriptSecurity` und für Drittplugins **nicht nutzbar**. Nutzbar sind `GetRelativeMousePosition()`, `WindowFocused`, `WindowFocusReleased` und die vier `PluginDrag*`-Events. **⚑** | VERIFIED | API-Dump 0.745 |
| I3 | `PluginGui:GetRelativeMousePosition() -> Vector2` gibt die Mausposition relativ zur linken oberen Ecke des Widgets zurück. Der Wert ändert sich nur, wenn eine Mauseingabe **im** Widget begann oder die Maus über dem Fenster ist. Für Drags, die den Rand überschreiten, ist das brauchbar. | VERIFIED | PluginGui.yaml |
| I4 | `WindowFocused` feuert, bevor `GuiObject.InputBegan` Maustasten-Events liefert. Wechselt der Fokus zwischen PluginGuis, kommt erst `FocusReleased` des alten, dann `Focused` des neuen Widgets. | VERIFIED | PluginGui.yaml |
| I5 | `GuiObject`-Events, alle Security None: `InputBegan`, `InputChanged`, `InputEnded` (InputObject), `MouseEnter`, `MouseLeave`, `MouseMoved` (x, y), `MouseWheelForward`, `MouseWheelBackward` (x, y). Bei `UserInputType.MouseWheel` steht die Richtung in `InputObject.Position.Z` (>0 vorwärts, <0 rückwärts). `GuiButton`: `MouseButton1Down/Up/Click`, `MouseButton2…`, `Activated(input, clickCount)`. | VERIFIED | API-Dump; GuiObject.yaml; InputObject.yaml |
| I6 | Mausereignisse feuern über Widgets nicht über UIS. Der Workaround mit Frame plus `InputChanged` funktioniert, solange das Widget fokussiert ist. | REPORTED | devforum.roblox.com/t/mouse-events-do-not-fire-when-a-mouse-is-on-the-plugin-widget/1549608; devforum.roblox.com/t/plugins-need-a-way-to-listen-to-app-input/479597 |
| I7 | Studio-eigene Shortcuts (z. B. Ctrl+Z, Delete, Ctrl+D) greifen wahrscheinlich auch, während ein Plugin-Widget fokussiert ist. Plugins können sie nicht abfangen (siehe I2). Delete im Timeline-Widget könnte also gleichzeitig die in Studio selektierte Instanz löschen. **⚑** | ASSUMPTION (abgeleitet aus `OverrideStudioAction`=RobloxScriptSecurity) | API-Dump |
| I8 | TextBox-Fokus: `CaptureFocus()`, `ReleaseFocus(submitted=false)`, `IsFocused()`, Events `Focused` und `FocusLost(enterPressed, inputThatCausedFocusLoss)`. `ClearTextOnFocus` ist standardmäßig `true` und muss für Property-Felder auf `false`. | VERIFIED | API-Dump; TextBox.yaml |
| I9 | Drag & Drop zwischen Widgets: `plugin:StartDrag({Sender, MimeType, Data: string, MouseIcon, DragIcon, HotSpot})`, auf dem Ziel-Widget dann `PluginDragEntered`, `PluginDragMoved`, `PluginDragLeft`, `PluginDragDropped`. Die Events feuern nur für Drags, die **`Plugin:StartDrag`** gestartet hat. Ein Drag aus dem Studio-Explorer ins Widget wird darüber nicht gemeldet (ASSUMPTION aus dem Wortlaut). | VERIFIED / ASSUMPTION | Plugin.yaml; PluginGui.yaml; build-studio-widgets.md |
| I10 | Widerspruch: Laut API-Dump ist der Parameter der Drag-Events ein `Dictionary`. Laut `PluginDragEvent.yaml` wird eine `PluginDragEvent`-Instanz mit `Data`, `MimeType`, `Position`, `Sender` übergeben. Feldzugriff per Name funktioniert mit beidem. | VERIFIED (Widerspruch) | API-Dump; PluginDragEvent.yaml |
| I11 | Cursor-Icons: `plugin:GetMouse().Icon = "rbxasset://SystemCursors/<Name>"` (Arrow, PointingHand, OpenHand, ClosedHand, IBeam, SizeNS, SizeEW, SizeNESW, SizeNWSE, SizeAll, SplitNS, SplitEW, Forbidden, Wait, Busy, Cross). Sie bilden nur die OS-Cursor nach. | VERIFIED | build-studio-widgets.md |
| I12 | `PluginMouse` (über `plugin:GetMouse()`) ist nur nach `plugin:Activate()` voll nutzbar. Zusätzliches Event: `DragEnter(instances)` für Instanzen, die per Drag in den 3D-Viewport eingefügt werden. | VERIFIED | PluginMouse.yaml |

### 2.9 ViewportFrame und WorldModel

| # | Befund | Label | Quelle |
|---|---|---|---|
| V1 | Offizielle Einschränkungen: **keine Schatten, kein Post-Processing**. `Neon` und `Glass` rendern in niedrigster Qualität. Verschachtelte GuiObjects werden nicht unterstützt. Ohne `Sky`-Kind verhält sich die Beleuchtung wie `EnvironmentSpecularScale` und `EnvironmentDiffuseScale` = 0. Mit `Sky`-Kind (nur die sechs `Skybox*`-Texturen zählen) wirkt es wie beide = 1. | VERIFIED | ViewportFrame.yaml; ui/viewport-frames.md |
| V2 | Licht-Properties: `Ambient` (Default RGB 200,200,200), `LightColor` (Default 140,140,140), `LightDirection` (Default −1,−1,−1). Darstellung: `ImageColor3`, `ImageTransparency`. `CurrentCamera` muss eine `Camera` sein, typischerweise als Kind des Frames. | VERIFIED | ViewportFrame.yaml; Full-API-Dump (Defaults) |
| V3 | **ParticleEmitter, Beam und Trail rendern im ViewportFrame nicht.** Ebenfalls genannt werden BillboardGui, SurfaceGui und bestimmte Materialien. In der offiziellen Doku steht das **nicht** ausdrücklich. **⚑** | REPORTED | devforum.roblox.com/t/particleemitters-in-viewportframes/252266; devforum.roblox.com/t/trail-in-a-viewport/2133446; devforum.roblox.com/t/particles-in-viewport-frame/599553; devforum.roblox.com/t/how-to-workaround-beams-not-showing-on-viewportframes/3151410 |
| V4 | Fire, Smoke, Sparkles (partikelbasiert), Explosion und die Lichtquellen PointLight, SpotLight und SurfaceLight rendern bzw. leuchten im ViewportFrame vermutlich ebenfalls nicht. Dort gibt es nur das eigene gerichtete Licht plus Ambient. Ein Beleg fehlt, das muss getestet werden. | ASSUMPTION | — |
| V5 | `WorldModel` als Kind eines ViewportFrames erlaubt Animation (inkl. Humanoid-Joints) und räumliche Abfragen (Raycasts), aber **keine Physiksimulation**. `UseWorkspaceCollisionGroups` existiert. Die Doku rät, WorldModels nur bei Bedarf zu erzeugen und unbenutzte zu löschen. | VERIFIED | WorldModel.yaml |

### 2.10 HttpService in Plugins

| # | Befund | Label | Quelle |
|---|---|---|---|
| H1 | Plugins dürfen `HttpService` nutzen. Beim ersten Zugriff auf eine Adresse fragt Studio den Nutzer womöglich nach der Erlaubnis für genau diese Adresse. Erlauben, Verweigern und Widerrufen geht jederzeit im Fenster **Plugin Management**. **⚑** | VERIFIED | cloud-services/http-service.md („Use in plugins“) |
| H2 | Plugins dürfen ausdrücklich mit Software auf demselben Rechner sprechen, über **`localhost` und `127.0.0.1`**, etwa um aufs Dateisystem zuzugreifen. Diese Software muss getrennt vom Plugin verteilt werden. **⚑** (Claude-Bridge) | VERIFIED | cloud-services/http-service.md |
| H3 | Die Freigabe gilt pro Domain, Subdomains brauchen eine eigene. Für Plugins wird `HttpEnabled` laut Beitrag nicht mehr genutzt. Lokale Plugins umgehen die Abfrage laut Ankündigung (Stand 2020, möglicherweise veraltet). | REPORTED | devforum.roblox.com/t/introducing-plugin-http-permissions/493269 |
| H4 | `HttpService.HttpEnabled` hat Write = `LocalUserSecurity`, Default false. Laut Guide müssen **Spiele** „Allow HTTP Requests“ in den Experience Settings aktivieren. Für Plugins nennt die Doku diese Bedingung nicht. | VERIFIED | API-Dump; http-service.md |
| H5 | Das Rojo-Plugin (aktueller `master`) verbindet sich standardmäßig mit **`localhost:34872`** über `http://`. Für Live-Updates baut es per `HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, …)` eine **`ws://`**-Verbindung auf. Unverschlüsseltes HTTP und WebSocket zu localhost funktionieren aus Plugins also. **⚑** | VERIFIED (Produktquelltext) | raw.githubusercontent.com/rojo-rbx/rojo/master/plugin/src/Config.lua; …/ApiContext.lua |
| H6 | `HttpService:CreateWebStreamClient(type, requestOptions) -> WebStreamClient` mit den Typen SSE, RawStream und WebSocket. Läuft **nur in Studio**, höchstens **4 Clients** gleichzeitig. `WebStreamClient`: `Send(string)` (nur WebSocket), `Close()`, `ConnectionState`, Events `Opened`, `MessageReceived`, `Error`, `Closed`. **⚑** | VERIFIED | HttpService.yaml; WebStreamClient.yaml; API-Dump |
| H7 | Grenzen laut Guide: 500 HTTP-Requests pro Minute (allgemein, „pro Game-Server“). HTTPS-only und die Port-Sperre (unter 1024 außer 80/443, außerdem 1194) stehen im **Open-Cloud-Abschnitt**. Ob sie für Plugin-Requests an localhost gelten, ist nicht eindeutig. Rojo nutzt HTTP auf Port 34872. | VERIFIED (Text) / ASSUMPTION (Geltungsbereich) | http-service.md |
| H8 | 2020 wurde bei localhost-Zugriff ein Fehler „Trust check failed“ gemeldet. Das ist veraltet, weil Doku und Rojo heute localhost belegen. | REPORTED | devforum.roblox.com/t/how-to-access-localhost-using-httpservice-in-roblox-studio/1496085 |

### 2.11 Edit Mode: Partikel und RunService

| # | Befund | Label | Quelle |
|---|---|---|---|
| R1 | Im Edit Mode gilt `IsStudio=true`, `IsClient=true`, `IsServer=true`, `IsEdit=true`, `IsRunning=false`. Bei pausierter Simulation sind `IsEdit` und `IsRunning` beide `false`. `RunService.RunState` (Stopped, Running, Paused) dürfen Plugins schreiben (PluginSecurity). | VERIFIED | RunService.yaml (Tabelle); API-Dump |
| R2 | Beim **Pausieren** eines Playtests pausieren nur `PreAnimation`, `PreSimulation`, `PostSimulation` und `Stepped`. `PreRender`, `Heartbeat` und `RenderStepped` feuern weiter, „maintaining normal functionality of … rendered visualizations, and plugins“. | VERIFIED | studio/testing-modes.md |
| R3 | Die Doku zu `PreSimulation` und `PostSimulation` sagt, `deltaTimeSim` könne „in Studio edit mode“ vom tatsächlichen Frame-Abstand abweichen. Daraus folgt, dass diese Events im Edit Mode feuern. Dass `Heartbeat` und `PreRender` im Edit Mode für Plugins jeden Frame feuern, ist naheliegend (siehe R2), aber nicht ausdrücklich dokumentiert. **⚑** (Timeline-Playback) | VERIFIED (Text) / ASSUMPTION (Heartbeat im Edit Mode) | RunService.yaml |
| R4 | `RenderStepped` feuert laut Bugreport nicht, wenn Studio minimiert ist oder ein Skript-Tab offen ist. Die Timeline-Uhr sollte deshalb über `os.clock()` laufen, nicht über aufsummierte Frame-Deltas. | REPORTED | devforum.roblox.com/t/renderstepped-doesnt-fire-when-minimized-or-script-tab-open/1095186 |
| R5 | Ein ParticleEmitter emittiert laut Guide **sofort**, sobald man ihn einfügt. Das ist ein Edit-Mode-Arbeitsschritt. Roblox' eigenes Tutorial testet Bursts per `Emit()`-Plugin im Edit Mode. **⚑** | VERIFIED | effects/particle-emitters.md; tutorials/use-case-tutorials/vfx/use-particles-for-explosions.md (siehe `api-particles-beams-trails.md` E1/E2) |
| R6 | Die Darstellung im Edit Mode hängt vom „Editor Quality Level“ ab und unterscheidet sich vom Playtest. `Emit()` ignoriert dabei die Grafikqualität. | REPORTED | devforum.roblox.com/t/why-do-particle-emitters-appear-differently-in-studio-than-when-testing/95781 |

### 2.12 Archivable und Preview-Objekte

| # | Befund | Label | Quelle |
|---|---|---|---|
| A1 | `Instance.Archivable=false` nimmt die Instanz **mitsamt Nachfahren** aus Speichern und Veröffentlichen aus und auch aus `Clone()` eines Vorfahren. Ein direktes `Clone()` liefert `nil`. **⚑** | VERIFIED | Instance.yaml |
| A2 | **Duplicate** bzw. **Copy/Paste** in Studio ignoriert `Archivable=false` und setzt die Kopie auf `true`. Dupliziert der Nutzer ein Preview-Objekt, landet die Kopie also im gespeicherten Place. **⚑** | VERIFIED | Instance.yaml |
| A3 | CHS ignoriert nicht-archivierbare Instanzen (siehe C10). Preview-Änderungen erzeugen dann keine Undo-Schritte und werden bei Undo nicht gelöscht und neu erzeugt. | REPORTED | siehe C10 |
| A4 | Ein Konkurrenzprodukt legt temporäre Teile mit `Archivable=false` in die `Camera`. | REPORTED | `other-roblox-vfx-plugins.md` |
| A5 | 3D-Objekte (BaseParts mit Emittern) rendern nur unter einem `WorldRoot` (Workspace bzw. Camera im Workspace, oder `WorldModel` im ViewportFrame). `CoreGui` taugt nur für GUIs und Adornments. Ob nicht-archivierbare Instanzen in Team Create zu anderen Mitarbeitern repliziert werden, ist unbekannt. | ASSUMPTION / offen | CoreGui.yaml |

### 2.13 Sicherheitsstufen und Capabilities

| # | Befund | Label | Quelle |
|---|---|---|---|
| SEC1 | `PluginSecurity`-APIs stehen Plugins und der Command Bar zur Verfügung, `RobloxScriptSecurity` nur Roblox-eigenen Plugins. Die für ASTRA relevanten gesperrten Member listet Abschnitt 3. | VERIFIED | API-Dump 0.745 |
| SEC2 | `MeshPart.MeshId` und `MeshPart.MeshContent`: Write = **`NotAccessibleSecurity`**, auch Plugins können sie nicht setzen. Der Weg: `AssetService:CreateMeshPartAsync(Content, options?)` (yieldet) und dann `existingMeshPart:ApplyMesh(newMeshPart)`. `MeshPart.TextureID`/`TextureContent` sind frei schreibbar. **⚑** | VERIFIED | API-Dump; MeshPart.yaml |
| SEC3 | `SpecialMesh` (über `FileMesh`): `MeshId`, `MeshContent` und `TextureId` sind frei schreibbar. Mesh-VFX (Shockwaves, Slashes) sollten deshalb SpecialMesh nutzen oder vorhandene MeshParts klonen. **⚑** | VERIFIED (Security) / IDEA (Empfehlung) | API-Dump |
| SEC4 | `ParticleEmitter.Texture`, `FlipbookLayout` und ähnliche haben Security None/None und sind frei schreibbar. | VERIFIED | Full-API-Dump |
| SEC5 | `CoreGui` steht laut Doku auch Plugins zur Verfügung. `CoreGui:TakeScreenshot` ist `RobloxScriptSecurity`. | VERIFIED | CoreGui.yaml; API-Dump |
| SEC6 | `Script.Source` hat Capability `PluginOrOpenCloud` (siehe SE1). Auch `SerializationService` sowie `RunService:IsEdit` und `RunState` tragen `PluginOrOpenCloud`. | VERIFIED | Full-API-Dump |
| SEC7 | `ChangeHistoryService`, `Selection` (Get/Set/Add/Remove), `StudioService`-Prompts, `ScriptEditorService` und `File` sind alle `PluginSecurity`. `Selection.SelectionChanged` hat Security None, ist aber nur in Studio sinnvoll. | VERIFIED | API-Dump |

---

## 3. Einschränkungen und Kritik

**Für Drittplugins gesperrt (`RobloxScriptSecurity`, VERIFIED, API-Dump 0.745):**
- Widget: `PluginGui.InputBegan`, `InputChanged`, `InputEnded`, `MouseEnter`, `MouseLeave`, `PointerAction`, `PluginGui:OverrideStudioAction`, `DockWidgetPluginGui:RequestRaise`, `Plugin:CreateQWidgetPluginGui`, `Plugin.HostDataModelType`
- Menüs und Actions: `PluginAction.Enabled`, `Checked`, `Visible`, `DefaultShortcut` sowie `Text` schreiben, `PluginMenu.Visible`, `PluginToolbar:CreatePopupButton`, `PluginToolbarButton:SetDropdownActive`, `DropdownClick`
- Zwischenablage: `StudioService:CopyToClipboard`, `UserInputService:GetPasteText`
- Sonstiges: `Selection.ActiveInstance`, `SelectionChangedThisFrame`, `HttpService:SetHttpEnabled`, `GetHttpEnabled`, `CoreGui:TakeScreenshot`, `Plugin:PlaySound`, `PauseSound`, `StopAllSounds`; dazu die Plugin-Viewport-Drag-Events `ViewportDragEntered`, `ViewportDragDropped`, `ViewportDragLeft`
- Für ASTRA bedeutet das: **kein Standard-Kürzel**, **keine deaktivierbaren Menüpunkte**, **kein Abfangen von Studio-Shortcuts**, **keine Zwischenablage**, **keine Datei-Schreibzugriffe**, **kein Widget-Raise**.

**Dokumentationslücken und Widersprüche:**
- Dass ViewportFrame keine Partikel, Beams und Trails rendert, steht nicht in der offiziellen Doku, nur im DevForum (V3).
- Ob `RunService.Heartbeat` im Edit Mode feuert, ist nicht ausdrücklich dokumentiert (R3).
- Die Drag-Event-Payload ist laut Dump ein `Dictionary`, laut Doku eine `PluginDragEvent`-Instanz (I10).
- Laut `PluginMenu:AddMenu` fügt es „as a separator“ hinzu; der Parametertext beschreibt aber ein Untermenü.
- Der Parametertext von `CreatePluginAction` zu `allowBinding` („hidden from shortcuts view“) widerspricht der Property-Beschreibung (`true` heißt „belegbar“).
- `PromptImportFilesAsync` wirft laut Doku bei einer leeren Filterliste, obwohl `{}` der Default ist.
- Der Widget-Guide nutzt noch die deprecated Methode `CreateDockWidgetPluginGui`.
- `SetWaypoint` gilt als „bald deprecated“, ist im Dump aber nicht markiert.
- Für Plugin-Settings ist kein Größenlimit dokumentiert, und sie können bei mehreren Studio-Fenstern still fehlschlagen.

**Verhaltensrisiken:**
- Laufende CHS-Recordings überleben einen Plugin-Reload (C4).
- Änderungen ohne Recording vermischen sich mit fremden Undo-Schritten (C9).
- Kopiert der Nutzer Preview-Objekte, werden die Kopien archivierbar (A2).
- Studio-Shortcuts können während der Widget-Bedienung greifen (I7).
- `.`, `"`, Newline und `\` in Setting-Keys bzw. `\` in Werten können die Settings-Datei zerstören (W10). Windows-Pfade und JSON-Strings enthalten oft Backslashes.

---

## 4. Konsequenzen für ASTRA

### 4.1 Widget-Architektur ⚑
- **IDEA**: Ein Modul `WidgetHost` erzeugt **alle** Widgets über `CreateDockWidgetPluginGuiAsync`, mit **festen, versionsunabhängigen IDs** wie `"ASTRA_Explorer"`, `"ASTRA_Inspector"`, `"ASTRA_Timeline"`, `"ASTRA_NodeGraph"` und `"ASTRA_Preview"`. Da die Methode yieldet, laufen die Aufrufe in einer Startsequenz und blockieren keine Event-Handler. Eine ID nachträglich umzubenennen hieße, das gespeicherte Layout aller Nutzer zu verlieren (W5).
- **IDEA**: Ein Toolbar-Button pro Haupt-Widget, oder ein Button für den gesamten Editor plus Menü. `ClickableWhenViewportHidden = true` (T2). Den Button-Zustand per `SetActive` mit `widget.Enabled` synchron halten und dafür `widget:GetPropertyChangedSignal("Enabled")` beobachten, weil `BindToClose` das Schließen nicht verhindert (W7).
- **IDEA**: Alle Tastenkürzel als `PluginAction`s mit `allowBinding=true` anlegen (Play/Pause, Keyframe setzen, Frame vor/zurück, Duplicate Keyframe). Da kein Standard-Kürzel möglich ist (T4), braucht ASTRA zusätzlich **widget-interne Shortcuts** über `GuiObject.InputBegan` auf einem Fokus-Frame (I1). Wo es geht, werden Tasten vermieden, die Studio global belegt hat (Delete, Ctrl+Z, Ctrl+D, Ctrl+C/V), oder ASTRA leert vor solchen Aktionen gezielt die Studio-Selektion (I7, Studio-Test nötig).
- **IDEA**: Kontextmenüs pro Kontext einmal anlegen und cachen, für dynamische Listen `Clear()` + `AddNewAction`. Deaktivierte Einträge werden weggelassen, statt sie auszugrauen (T6). Actions und Menüs in `Unloading` selbst zerstören (T7).
- **IDEA**: In `plugin.Unloading` einen idempotenten `Shutdown()` aufrufen. Er entfernt den Preview-Folder, trennt alle Connections, bricht eine eventuell offene CHS-Recording mit `FinishRecording("", Cancel)` ab und schreibt Settings ein letztes Mal (W8, C3).
- **IDEA**: Den vollen Editor nur initialisieren, wenn `RunService:IsEdit()` true ist. In Play-DataModels startet höchstens eine schlanke Runtime-Vorschau ohne Widgets, um doppelte Widget-IDs und Recordings zu vermeiden (W12, W13, C2).

### 4.2 Undo/Redo und Datenmodell ⚑
- **IDEA**: **Single Source of Truth im DataModel.** Das Effekt-Dokument liegt als Instanz im Place, z. B. als `Folder` mit Attributen oder als ModuleScript bzw. StringValue mit JSON. Die Lua-Strukturen im Plugin sind nur ein Cache. `OnUndo`/`OnRedo` sowie `Changed`-Signale auf den Dokument-Instanzen lösen ein Neuladen des Caches aus (C7). Ohne das laufen Inspector, Timeline und Node-Graph nach einem Undo auseinander.
- **IDEA**: Jede Nutzeraktion läuft als Command `{name, displayName, apply()}` über einen `HistoryAdapter`. Der prüft `TryBeginRecording`, führt bei `nil` einen Fallback aus (Toast „Undo nicht verfügbar im Playtest“) und ruft `FinishRecording(Commit)` im `pcall`/`finally`, bei Fehlern `Cancel`.
- **IDEA**: Kontinuierliche Gesten wie Slider-, Kurven- und Keyframe-Drags: Bei MouseDown eine Recording beginnen, während des Drags live ändern, bei MouseUp committen. Dann entsteht **ein** Undo-Schritt. Alternativ entsteht jedes Teil-Update mit `Append` (C3); die Doku sagt dazu aber nur „wenn möglich“, deshalb hat die erste Variante Vorrang.
- **IDEA**: Während eine Recording offen ist, dürfen nur Preview-Instanzen mit `Archivable=false` animiert werden. Sonst landen Preview-Ticks im Undo-Schritt (C10, A3).
- **IDEA**: Beim Start `IsRecordingInProgress()` prüfen und gegebenenfalls abbrechen (C4). Die aktuelle Recording-ID zusätzlich als Attribut am Dokument-Root ablegen.

### 4.3 Preview-Strategie ⚑
- **IDEA**: Die **Hauptvorschau läuft im 3D-Viewport**. Ein Folder `ASTRA_Preview` (`Archivable=false`, alle Nachfahren ebenfalls, BaseParts `Locked=true`) liegt unter `workspace.CurrentCamera` oder `Workspace` (A1, A4). Darin baut ASTRA die nativen Instanzen auf. Die Timeline-Uhr läuft über `os.clock()` und `Heartbeat` bzw. `PreRender` (R3, R4) und steuert `Emit()`, `Enabled`, `TimeScale` und Property-Tweens.
- **IDEA**: Das **Preview-Widget** (ViewportFrame) zeigt keine Partikel, Beams oder Trails (V3). Es dient für Mesh- und Part-Teile, Kamera-Framing und Thumbnails. Für Preset-Thumbnails nutzt ASTRA vorab erzeugte Bilder oder eine 2D-Approximation (ImageLabels oder EditableImage) und kennzeichnet sie in der UI als „Approximation“.
- **IDEA**: Als Schutz gegen A2 prüft ein `SelectionChanged`-Wächter, ob Preview-Objekte selektiert werden. Dann setzt er die Selektion auf das zugehörige Dokument-Element um. Beim Speichern oder Öffnen werden verwaiste `ASTRA_Preview`-Kopien in Workspace gesucht und gemeldet.
- **IDEA**: Lokale Texturen vor dem Upload per `PromptImportFileAsync` + `File:GetTemporaryId()` (`rbxtemp://`) zeigen, mit dem Hinweis, dass das nur in der aktuellen Sitzung funktioniert. Ob `rbxtemp://` in `ParticleEmitter.Texture` greift, ist zu testen. Beim Export blockiert ASTRA jede `rbxtemp://`-Referenz (F2).

### 4.4 Datei- und Claude-Integration ⚑
- **IDEA**: Beim Import gibt es drei Wege: (1) `PromptImportFileAsync({"json"})` → `GetBinaryContents` → `JSONDecode` → Schema-Validierung, (2) ein Paste-Feld (`TextBox`, `MultiLine`, `ClearTextOnFocus=false`) für JSON, das Claude im Terminal ausgegeben hat, (3) die Bridge.
- **IDEA**: Beim Export gibt es kein direktes Schreiben (F3). Die primären Wege sind (a) die **localhost-Bridge** (CLI `astra bridge` oder Rojo-ähnlicher Daemon) über HTTP bzw. WebSocket (H2, H5, H6) und (b) **Rojo-Sync**: Effekte liegen als Dateien im Repo, Rojo synchronisiert sie in den Place, ASTRA liest und schreibt die Instanzen. Fallbacks sind (c) ein Kopier-Feld (TextBox mit dem JSON, Nutzer kopiert manuell) und (d) `PromptSaveSelectionAsync` auf einen temporären Container (`.rbxm`/`.rbxmx`).
- **IDEA**: Bridge-Protokoll per **WebSocket**, eine Verbindung (Limit 4, H6). Fallback ist Long-Polling über `RequestAsync`. Port über 1024, nicht 1194, konfigurierbar (H7). Die einmalige HTTP-Freigabe im Plugin Management wird in Onboarding und Doku erklärt (H1). Die Bridge bleibt optional, denn der dateibasierte Weg über Rojo und JSON muss ohne sie funktionieren.
- **IDEA**: Generierte Runtime- oder Daten-ModuleScripts per `ScriptEditorService:UpdateSourceAsync` aktualisieren (SE2). Der Callback berechnet die neue Source rein funktional ohne Yield. Neu erzeugte, nie geöffnete Skripte dürfen direkt `Source` setzen (SE1). Diese Updates laufen innerhalb einer CHS-Recording.

### 4.5 Settings ⚑
- **IDEA**: Ein `SettingsStore` mit flachen ASCII-Keys **ohne Punkte**, etwa `astra_v1_layout` oder `astra_v1_recent`. Werte nur als Tables, Zahlen, Booleans und Strings **ohne Backslash**. Strings mit möglichen Sonderzeichen (Pfade, JSON) speichert er Base64- oder Hex-kodiert. Typen wie Color3 und Vector3 zerlegt er selbst. Nach dem Schreiben liest er gegen (W10). Größere Daten (Presets, Bibliotheken) gehören nicht in Settings, sondern in den Place oder die Bridge (W11 offen).

### 4.6 Theming
- **IDEA**: Ein `Theme`-Modul bildet semantische ASTRA-Tokens (`bg`, `panel`, `text`, `accent`, `border`, `hover`, `selected`, `disabled`, `warning`, `error`) auf `StudioStyleGuideColor` plus Modifier ab und aktualisiert sie bei `ThemeChanged` (TH1, TH2). Feste Farben gibt es nur für Daten-Visualisierung wie Kurvenfarben und Spurfarben; sie sind in beiden Themes kontrastgeprüft. Explorer-Icons kommen über `GetClassIcon` (TH4).

### 4.7 Eingabe in Timeline und Node-Graph ⚑
- **IDEA**: Jedes interaktive Widget bekommt einen Vollflächen-„Input-Catcher“-Frame (I1). Mausrad über `InputChanged` + `Position.Z` (I5). Drags laufen über `InputBegan` auf dem Element, dann `GetRelativeMousePosition()` per `PreRender`/`Heartbeat`, bis `InputEnded` kommt oder der Fokus verloren geht (I3, I4). Bei `WindowFocusReleased` werden laufende Drags abgebrochen bzw. committet.
- **IDEA**: Drag & Drop zwischen ASTRA-Widgets per `plugin:StartDrag` mit `MimeType = "application/x-astra-<kind>+json"` und `Data` als JSON-String (I9). Für Drags aus dem Studio-Explorer gibt es einen Button „Selektion übernehmen“ (S1).

---

## 5. Offene Fragen (mit vorgeschlagenem Studio-Test)

1. **ViewportFrame-Renderliste ⚑**: Für ParticleEmitter, Beam, Trail, Fire, Smoke, Sparkles, Explosion, PointLight, SpotLight, SurfaceLight, Highlight, Decal, Texture und SurfaceAppearance in ViewportFrame + WorldModel innerhalb eines DockWidgets prüfen, was gerendert wird.
2. **Heartbeat und PreRender im Edit Mode ⚑**: Frequenz und `deltaTime` messen, und zwar bei minimiertem Studio, bei offenem Skript-Tab und wenn das Widget im Hintergrund liegt (R3, R4).
3. **`Archivable=false` + CHS ⚑**: Ignoriert CHS 0.745 Änderungen an nicht-archivierbaren Instanzen wirklich (REPORTED aus 2015–2019)? Gilt das auch für Nachfahren eines nicht-archivierbaren Folders, deren eigenes `Archivable` true ist?
4. **Team Create**: Werden nicht-archivierbare Preview-Objekte in Workspace bzw. Camera zu Mitarbeitern repliziert? Ist die Camera pro Nutzer lokal?
5. **Änderungen ohne Recording**: Welcher Warn- oder Fehlertext erscheint, und landen die Änderungen im nächsten Waypoint (C9)?
6. **`OnUndo`-Parameter**: Enthält er `name` oder `displayName` der Recording? Und wie verhält sich `Append` nach einem fremden Waypoint?
7. **Studio-Shortcuts bei fokussiertem Widget ⚑**: Löst Delete, Ctrl+Z oder Ctrl+D im Widget die Studio-Aktion aus? Feuern gebundene `PluginAction`s, während eine TextBox im Widget den Fokus hat?
8. **`SetSetting`-Größenlimit** und Speicherort der Settings-Datei.
9. **`rbxtemp://` als `ParticleEmitter.Texture`, `Beam.Texture` und `Trail.Texture`** im Edit Mode.
10. **HTTP-Freigabe für localhost** bei Creator-Store-Plugins gegenüber lokalen Plugins. Kommt der Dialog bei `ws://` erneut? Gelten Port-Sperre und HTTPS-only für localhost?
11. **Doppelte `actionId`/Menü-ID** nach einem Plugin-Reload: Fehler oder Wiederverwendung? Werden `PluginAction`s automatisch aufgeräumt?
12. **`UpdateSourceAsync`**: Entsteht ein eigener Undo-Schritt, und wie verhält es sich im Drafts-Modus?
13. **Plugin-Instanzen pro DataModel** im Playtest: Lädt `CreateDockWidgetPluginGuiAsync` mit derselben ID im Play-DataModel einen Konflikt aus?
14. **`TextBox`-Paste großer JSON-Blöcke** (über 100 KB): Gibt es ein Längenlimit und wie ist die Performance?
15. **UIDragDetector** in Plugin-Widgets als Alternative für Keyframe- und Node-Drags (die Property `Plugin.DisableUIDragDetectorDrags` existiert, ist aber `RobloxScriptSecurity`).

*Hinweis: Das Web-Such-Budget dieser Sitzung war erschöpft. Fragen 3–5, 8, 10 und 14 lassen sich teilweise auch mit weiteren DevForum-Suchen klären.*

---

## 6. Quellen

**Offizielle Doku (VERIFIED, gelesen über `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/…`):**
- studio/plugins.md · studio/build-studio-widgets.md · studio/testing-modes.md · studio/script-editor.md · projects/collaboration.md
- reference/engine/classes/Plugin.yaml · DockWidgetPluginGui.yaml · PluginGui.yaml · PluginDragEvent.yaml · PluginToolbar.yaml · PluginToolbarButton.yaml · PluginAction.yaml · PluginMenu.yaml · PluginMouse.yaml · PluginManager.yaml
- reference/engine/datatypes/DockWidgetPluginGuiInfo.yaml · enums/InitialDockState.yaml · enums/FinishRecordingOperation.yaml · enums/StudioStyleGuideColor.yaml · enums/StudioStyleGuideModifier.yaml
- reference/engine/classes/ChangeHistoryService.yaml · Selection.yaml · StudioService.yaml · File.yaml · ScriptEditorService.yaml · Script.yaml · SerializationService.yaml
- reference/engine/classes/Studio.yaml · StudioTheme.yaml · GuiObject.yaml · TextBox.yaml · InputObject.yaml
- reference/engine/classes/ViewportFrame.yaml · WorldModel.yaml · ui/viewport-frames.md
- reference/engine/classes/HttpService.yaml · WebStreamClient.yaml · cloud-services/http-service.md
- reference/engine/classes/RunService.yaml · Instance.yaml · MeshPart.yaml · CoreGui.yaml · effects/particle-emitters.md
- tutorials/use-case-tutorials/vfx/use-particles-for-explosions.md (über die Schwesternotiz `api-particles-beams-trails.md`)

**Lokal (VERIFIED):** `/root/tools/ref/API-Dump.json`, `/root/tools/ref/Full-API-Dump.json` (Version 0.745.0.7451137), `/root/tools/ref/globalTypes.d.luau`

**Produktquelltext (VERIFIED für Rojo, nur gelesen):** https://raw.githubusercontent.com/rojo-rbx/rojo/master/plugin/src/Config.lua · https://raw.githubusercontent.com/rojo-rbx/rojo/master/plugin/src/ApiContext.lua

**DevForum (REPORTED, nur Such-Snippets):**
- https://devforum.roblox.com/t/psa-several-common-yielding-methods-have-been-renamed/4257585
- https://devforum.roblox.com/t/particleemitters-in-viewportframes/252266
- https://devforum.roblox.com/t/trail-in-a-viewport/2133446
- https://devforum.roblox.com/t/particles-in-viewport-frame/599553
- https://devforum.roblox.com/t/how-to-workaround-beams-not-showing-on-viewportframes/3151410
- https://devforum.roblox.com/t/introducing-plugin-http-permissions/493269
- https://devforum.roblox.com/t/how-to-access-localhost-using-httpservice-in-roblox-studio/1496085
- https://devforum.roblox.com/t/archivable-and-changehistoryservice/11953
- https://devforum.roblox.com/t/problems-with-plugins-selection-and-changehistoryservice/311724
- https://devforum.roblox.com/t/studio-doesnt-clean-up-changehistoryservice-recordings-for-unloaded-plugins/4108638
- https://devforum.roblox.com/t/2512500 (Recordings in Change History Service)
- https://devforum.roblox.com/t/mouse-events-do-not-fire-when-a-mouse-is-on-the-plugin-widget/1549608
- https://devforum.roblox.com/t/plugins-need-a-way-to-listen-to-app-input/479597
- https://devforum.roblox.com/t/renderstepped-doesnt-fire-when-minimized-or-script-tab-open/1095186
- https://devforum.roblox.com/t/why-do-particle-emitters-appear-differently-in-studio-than-when-testing/95781

**Schwesternotizen:** `docs/research/api-particles-beams-trails.md` (Edit-Mode-Partikel E1–E6), `docs/research/other-roblox-vfx-plugins.md` (Camera + `Archivable=false` bei einem Konkurrenten, localhost-HTTP-Erlaubnis)
