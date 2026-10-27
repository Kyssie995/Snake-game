# UI-Widgets – Katalog

Bausteine der Plugin-Oberfläche unter `src/Plugin/UI/Widgets/` (ein Widget pro Datei; jede Datei beginnt mit einem
Kopfkommentar samt Beispiel). Grundlage sind `Theme`, `New`, `Maid` und `Input` aus `src/Plugin/UI/`
(siehe [`PLUGIN_CONTRACTS.md`](PLUGIN_CONTRACTS.md) §9). Tests: `tests/specs/WidgetsControls.spec.luau`,
`WidgetsLayout.spec.luau` und `WidgetsContract.spec.luau` (widgetübergreifender Vertrag).

## 1. Gemeinsamer Vertrag

**Konstruktion.** `local w = Widget.new(props)` liefert ein Objekt. `w.instance` ist die Wurzel (ein `GuiObject`).
Sie ist **nicht** geparentet, außer `props.parent` ist gesetzt. Gemeinsame Props:

| Prop | Bedeutung |
|---|---|
| `name`, `layoutOrder`, `position`, `size` | landen auf `w.instance`, soweit das Widget sie anbietet (Panel ohne `layoutOrder`; Toolbar, Section und PropertyRow ohne `size`). `size` ist immer `UDim2`; `IconButton` akzeptiert zusätzlich eine Kantenlänge als Zahl |
| `anchorPoint` | bei den Eingabe-Widgets (Button … SearchBox) |
| `enabled` | `false` erzeugt das Widget deaktiviert (gleichbedeutend mit `w:setEnabled(false)`) |
| `host` | `{ plugin, widget, root }`, nötig für Ziehen, Popups, Tooltips, Cursor und den Asset-Picker |
| `parent` | wird zuletzt gesetzt |

**Methoden.** Alle Widgets haben `w:setEnabled(b)` und `w:destroy()`. Wert-Widgets haben zusätzlich `w:setValue(v)`
und `w:getValue()`.
* `setValue` aktualisiert nur die Anzeige und ruft **nie** Callbacks auf. Das gilt auch für die Text-Change-Signale,
  die die Engine beim Schreiben von `TextBox.Text` feuert.
* `destroy` ist idempotent. Es räumt den Maid ab, trennt alle Verbindungen und zerstört `w.instance`. Ein laufender
  Drag verliert dabei seine Heartbeat-Verbindung. Ein laufendes Scrubben endet mit `onChange(v, true)`, damit eine
  Editor-Geste nicht offen bleibt.

**Callbacks** kommen über die Props:
* `onChange(value, final)`: `final = false` für Zwischenwerte beim Ziehen oder Scrubben, danach genau einmal
  `final = true`. Widgets ohne Gesten (Checkbox, Dropdown, TextInput, SearchBox, Tabs …) senden immer `final = true`.
  So kann der Editor `beginGesture` / `updateGesture` / `endGesture` zu **einem** Undo-Schritt bündeln.
* `onActivate()` meldet einen Klick (Button, IconButton, ColorSwatch).
* Andere Namen nur dort, wo kein Wert entsteht: `onToggle`, `onSelect`, `onReset`, `onKeyframe`, `onResult` und so
  weiter.

**Fokus und externe Änderungen.** Bekommt ein fokussiertes Feld per `setValue` einen neuen Wert (z. B. Studio-Undo
während der Eingabe), gilt:
* Hat der Nutzer noch nichts getippt, zeigt das Feld den neuen Wert. Verlässt er es ohne Eingabe, wird nichts
  übernommen.
* Hat er schon getippt, bleibt sein Text stehen und wird beim Verlassen übernommen.

Das gilt für TextInput, NumberInput und das Wertfeld des Sliders. Escape verwirft die Eingabe.

**Eingabe in DockWidgets.** `UserInputService` funktioniert in Widgets nicht (`research/api-studio-plugin.md` §2.8).
* Maus: `GuiObject`-Events und `Input.drag`. Dieses fragt während eines Drags in jedem Heartbeat
  `host.widget:GetRelativeMousePosition()` ab. Die Heartbeat-Verbindung besteht nur, solange gezogen wird. Der Drag
  endet bei `UserInputState.End`, bei `InputEnded` oder bei `WindowFocusReleased`.
* Tastatur: über einen Input-Catcher des Panels (`Input.catcher` / `Input.onKey`), der die Tasten z. B. an
  `Tree:handleKey` weiterreicht.

**Ebenen.** Popups, Tooltips, Toasts und Dialoge sind Kinder von `host.root` und liegen dort über dem Panel-Inhalt.
* `host.root` muss ein schlichter Frame **ohne** Layout-Objekte sein (UIListLayout, UIPadding). Das ist
  `Panel.instance`, nicht `panel.body`.
* Das Widget nutzt `ZIndexBehavior.Sibling`. `Panel.new` setzt das selbst, wenn es direkt in einen
  `LayerCollector` gehängt wird. Sonst ruft man einmal `ControlKit.useSiblingZIndex(dockWidget)` auf.
* Reihenfolge der Ebenen (`ControlKit.Z`): Inhalt (< 800) < Dialog 800 (+20 je Stapeltiefe) < Toast 1100 < Popup
  1200 < Tooltip 1300. `ControlKit.raise` setzt den ZIndex zusätzlich auf den ganzen Teilbaum, damit es auch unter
  `Global` funktioniert.
* Wird der Besitzer zerstört, ohne dass `destroy()` läuft (`Destroying`), schließen sich Dropdown-Popups und
  Tooltips von selbst.

**Gestaltung.**
* Farben nur aus `Theme.colors` und abgeleiteten Zuständen in `ControlKit.derived` (gedrückt/deaktiviert). Ein Test
  prüft jede sichtbare Farbe.
* Zeilenhöhe `Theme.metrics.rowHeight` (24), Ecken 4 px, Rahmen als 1-px-`UIStroke` in `border`, Hover auf `bg3`,
  Text 12–13 px BuilderSans.
* Ausnahmen: Nutzerinhalte (Farbchip der ColorSwatch, Asset-Vorschau) und der weiße Gradient-Chip, denn
  `UIGradient` multipliziert mit der Hintergrundfarbe.

**Tests (Lune).** Lune hat kein Layout. `ControlKit.geometry` meldet daher Position (0, 0) und die Size-Offsets
(100 px für Achsen ohne Offset). Ereignisse feuert man mit `ctx.fakes:signalFor(inst, "Activated"):Fire(...)`, z. B.
`"FocusLost"` oder `"Changed:Text"`. Für Drags setzt man `widget.mouse`, feuert `InputBegan` mit einem
Fake-InputObject, ruft `ctx.fakes:step(1/60)` auf und setzt am Ende `UserInputState = End`.

## 2. Eingabe-Widgets

### Button
Textknopf in den Varianten `"primary"`, `"secondary"` (Standard), `"ghost"` und `"danger"`. Ohne `size` passt sich
die Breite dem Text an.
* **Props:** `text`, `variant`, `icon` (Glyphe vor dem Text), `tooltip` (braucht `host`), `size`, `width`, `enabled`.
* **Callback:** `onActivate()`.
* **Methoden:** `setText`, `setIcon`, `setVariant`, `isEnabled`, `setTooltip`.
```lua
Button.new({ text = "Speichern", variant = "primary", onActivate = save, parent = footer })
```

### IconButton
Quadratischer Knopf mit Glyphe oder Bild, optional als Umschalter.
* **Props:** `glyph` oder `image`, `size` (Zahl oder UDim2), `glyphSize`, `tooltip`, `host`, `toggle`, `toggled`,
  `enabled`.
* **Callbacks:** `onActivate()`, `onChange(toggled, true)`.
* **Methoden:** `setValue(toggled)`, `getValue`, `setGlyph`, `setTooltip`.
```lua
IconButton.new({ glyph = "↻", toggle = true, tooltip = "Schleife", host = host, onChange = function(on) editor:setLoop(on) end })
```

### Label
Einzeilig mit „…“ am Ende oder umbrechend mit automatischer Höhe.
* **Props:** `text`, `variant` (`normal`, `dim`, `muted`, `title`, `mono`, `error`), `size`, `textSize`, `alignX`,
  `alignY`, `wrap`, `rich`, `color` (nur Theme-Token), `enabled`.
* **Methoden:** `setText`/`setValue`, `getText`, `setVariant`, `setColor`.
```lua
Label.new({ text = "Keine Komponente ausgewählt", variant = "muted", wrap = true, parent = body })
```

### TextInput
Gerahmte TextBox mit `ClearTextOnFocus = false`.
* Übernimmt bei FocusLost oder Enter, und nur bei echter Änderung. Escape setzt zurück.
* Mit `validate` wird ungültiger Text rot umrandet und nicht übernommen. Der Fehler erscheint als Tooltip, wenn
  `host` gesetzt ist.
* **Props:** `value`, `placeholder`, `multiline` (+`height`), `mono`, `textSize`, `validate(text) -> Fehler?`,
  `tooltip`, `host`, `enabled`.
* **Callbacks:** `onChange(text, true)`, `onSubmit(text)` (Enter mit gültigem Text), `onInput(text)` (bei jedem
  Tastendruck).
* **Methoden:** `commit`, `getText` (roher Text), `getError`, `setError`, `focus(selectAll?)`, `setPlaceholder`.
```lua
TextInput.new({ value = def.name, validate = function(t) return if t == "" then "Name fehlt" else nil end,
	onChange = function(name) editor:renameDocument(id, name) end })
```

### NumberInput
Zahlenfeld mit einer Scrub-Zone links (Beschriftung oder schmaler Griff) und einem Tippfeld rechts.
* Ziehen ändert den Wert um `step` je `pixelsPerStep` px. Shift multipliziert mit 10, Ctrl mit 0,1; die Modifier
  werden beim Drücken gelesen.
* Ein Klick ohne Bewegung fokussiert das Tippfeld. Tippen erlaubt Ausdrücke (`2*3`, `1,5`, `(4+2)/3`). Der Wert wird
  auf `min`/`max` begrenzt und auf `precision` gerundet.
* **Props:** `value`, `min`, `max`, `step`, `precision` (2), `label`, `labelColor`, `labelWidth`, `suffix`,
  `pixelsPerStep`, `host` (zum Scrubben), `tooltip`, `enabled`.
* **Callback:** `onChange(v, final)`.
* **Methoden:** `setMixed` („—“), `setRange`, `setStep`, `isDragging`, `focus`.
```lua
NumberInput.new({ label = "Rate", value = 20, min = 0, step = 1, precision = 0, suffix = "/s", host = host,
	onChange = function(v, final) if final then editor:endGesture(true) else editor:updateGesture(...) end end })
```

### Slider
Spur mit Daumen und optionalem Wertfeld rechts (`showValue`, Standard an).
* Drücken springt an die Stelle (`final = false`), Ziehen folgt, Loslassen meldet einmal `final = true`. Getippte
  Werte kommen mit `final = true`.
* **Props:** `value`, `min` (0), `max` (1), `step` (Raster), `precision`, `showValue`, `valueWidth`, `host` (für
  Maus), `enabled`.
* **Callback:** `onChange(v, final)`.
* **Methoden:** `setRange`, `isDragging`.
```lua
Slider.new({ value = 0.5, min = 0, max = 1, step = 0.05, host = host, onChange = setOpacity })
```

### Checkbox
Ganze Zeile klickbar, mit Zustand „gemischt“ (–).
* **Props:** `value`, `text`, `tooltip`, `host`, `enabled`.
* **Callback:** `onChange(checked, true)`.
* **Methoden:** `toggle`, `setMixed`, `setText` (legt die Beschriftung bei Bedarf an).
```lua
Checkbox.new({ value = true, text = "Schleife", onChange = function(on) editor:setLoop(on) end })
```

### Dropdown
Knopf mit einer Popup-Liste in `host.root`.
* Ab `searchThreshold` (8) Optionen gibt es ein Suchfeld.
* Das Popup schließt bei einer Wahl, einem Klick außerhalb (transparentes Overlay), einem Rechtsklick, Fokusverlust
  des Widgets, einem zweiten Klick, `setEnabled(false)`, `destroy()` und wenn der Besitzer zerstört wird.
* **Props:** `options` (`{ value, label?, description? }`, positional `{ value, label, desc }` oder Strings),
  `value`, `placeholder` („Auswählen…“), `host`, `popupWidth`, `maxVisible`, `searchThreshold`, `enabled`.
* **Callback:** `onChange(value, true)`.
* **Methoden:** `open`, `close`, `isOpen`, `choose(value)` (wie ein Klick), `setOptions`.
```lua
Dropdown.new({ options = { { value = "Additive", label = "Additiv", description = "Hellt auf" }, "Normal" },
	value = "Normal", host = host, onChange = function(v) editor:transact("Blend", ...) end })
```

### SearchBox
Suchfeld mit Lupe (aus Frames gezeichnet) und ×-Knopf zum Leeren. Escape leert das Feld.
* **Props:** `value`, `placeholder` („Suchen…“), `enabled`.
* **Callbacks:** `onChange(text, true)` bei jeder Textänderung, `onSubmit(text)` bei Enter.
* **Methoden:** `clear` (feuert `onChange("")`), `focus`.
```lua
SearchBox.new({ placeholder = "Komponenten suchen…", onChange = function(text) library:filter(text) end })
```

### ColorSwatch
Farbvorschau (Chip + Hex- oder Palettentext) oder Verlauf (`UIGradient`).
* Ein Klick ruft `onPick(swatch, value)` auf. Der Farbwähler meldet sich über `swatch:commit(v, final)` zurück, das
  `onChange` auslöst.
* **Props:** `value` (`"#RRGGBB"`, `"$key"`, `{r,g,b}`, `Color3`, `ColorSequence`, `[[t, farbe], …]`), `palette`,
  `showText`, `tooltip`, `host`, `enabled`.
* **Callbacks:** `onPick`, `onActivate`, `onChange(value, final)`.
* **Methoden:** `getColor`, `getSequence`, `commit`, `activate`, `setPalette`, `geometry`.
* **Statische Helfer:** `ColorSwatch.toColor`, `ColorSwatch.toSequence`.
```lua
ColorSwatch.new({ value = "#FF8A3D", onPick = function(sw, v) openPicker(sw, v) end, onChange = setColor })
```

### AssetInput
Vorschaubild, Textfeld und Knopf „Wählen…“, der `plugin:PromptForExistingAssetIdAsync` öffnet (in `task.spawn`, mit
`pcall` abgesichert).
* Eingaben werden über `Codec` kanonisiert (`123` wird zu `rbxassetid://123`); ungültiger Text bekommt einen roten
  Rahmen.
* **Props:** `value`, `assetType` (`"Image"`), `placeholder`, `previewSize`, `host`, `enabled`.
* **Callback:** `onChange(asset, true)`.
* **Methoden:** `pick`, `isPicking`.
* **Statische Helfer:** `AssetInput.parse(text)`, `AssetInput.thumbnail(asset)`.
```lua
AssetInput.new({ value = "rbxassetid://243660364", host = host, onChange = setTexture })
```

### Vector3Input / Vector2Input / NumberRangeInput
Mehrere NumberInputs nebeneinander. Die Achsenbeschriftungen sind farbig (X `error`, Y `success`, Z `loop`).
* Werte sind JSON-Arrays. `setValue` nimmt auch `Vector3`, `Vector2` oder `NumberRange` an.
* `NumberRangeInput` hält `min <= max` (`NumberRangeInput.constrain`).
* **Props:** `value`, `min`, `max`, `step`, `precision`, `labels`, `spacing`, `host`, `enabled`.
* **Callback:** `onChange(values, final, axis)`. Ein frisches Array und der Index der bearbeiteten Achse, damit
  Mehrfachauswahlen nur diese Komponente übernehmen.
* **Methoden:** `setMixed(bool | {bool})`, `setRange`, `isDragging`; Feld `fields` (die NumberInputs).
```lua
Vector3Input.new({ value = { 0, 2, 0 }, step = 0.1, precision = 3, host = host, onChange = function(v, final, axis) ... end })
```

## 3. Layout und Listen

### Panel
Standard-Wurzel jedes Panels: Kopfzeile (Icon, Titel, Toolbar-Slot rechts) über einem gepolsterten Body (`scroll =
true` macht daraus einen ScrollingFrame).
* `panel.instance` dient als `host.root`. In einem `LayerCollector` setzt es `ZIndexBehavior.Sibling`.
* **Props:** `title`, `icon`, `toolbar`, `header` (false blendet aus), `padding`, `scroll`, `enabled`.
* **Felder:** `header`, `titleLabel`, `toolbarSlot`, `body`.
* **Methoden:** `setTitle`, `setToolbar` (übernimmt Besitz), `getToolbar`, `give(task)`.
```lua
local panel = Panel.new({ title = "Explorer", icon = "◆", parent = dockWidget })
local host = { plugin = plugin, widget = dockWidget, root = panel.instance }
```

### Toolbar
Horizontale Leiste aus Widgets oder GuiObjects mit `"separator"` und `"spacer"` (`UIFlexItem` Fill). Die Leiste
besitzt ihre Einträge.
* **Props:** `items`, `height`, `autoWidth` (für Kopfzeilen-Slots), `padding`, `background`, `enabled`.
* **Methoden:** `add`, `addSeparator`, `addSpacer`, `clear`; `setEnabled` reicht an alle Einträge weiter.
```lua
panel:setToolbar(Toolbar.new({ autoWidth = true, items = { IconButton.new({ glyph = "+", tooltip = "Neu", host = host }) } }))
```

### Section
Einklappbare Gruppe für den Inspector: 24-px-Kopf (Pfeil, Titel, Badge) über einem Body mit `UIListLayout`.
* **Props:** `title`, `expanded` (true), `badge`, `spacing`, `padding`, `enabled`.
* **Callback:** `onToggle(expanded)`.
* **Methoden:** `add` (übernimmt Besitz), `clear`, `isExpanded`/`getValue`, `setExpanded`/`setValue`, `toggle`,
  `setTitle`, `setBadge`.
```lua
local s = Section.new({ title = "Emission", parent = inspectorList }); s:add(PropertyRow.new({ ... }))
```

### PropertyRow
Inspector-Zeile: Beschriftung (`Theme.metrics.labelWidth`), Feld-Slot, Reset-Knopf (sichtbar, solange der Wert vom
Standard abweicht, tiefer Vergleich) und optional ein Keyframe-Diamant (`none`, `has-track`, `key-at-playhead`).
* **Props:** `label`, `description` (Tooltip), `field` (Widget, übernimmt Besitz), `value`, `default`,
  `resettable`, `keyframe`, `host`, `labelWidth`, `indent`, `height`, `enabled`.
* **Callbacks:** `onReset()`, `onKeyframe(state)`.
* **Methoden:** `setValue` (reicht an `field:setValue` weiter), `setDefault`, `setModified`, `isModified`,
  `setMixed`, `reset`, `setKeyframeState`, `setField`, `setLabel`, `setDescription`.
```lua
PropertyRow.new({ label = "Rate", field = NumberInput.new({ value = 20, host = host, onChange = setRate }),
	value = 20, default = 20, onReset = resetRate, keyframe = "none", onKeyframe = toggleKey, host = host })
```

### Tabs
Tab-Leiste mit einer Seite (Frame) je Tab; nur die gewählte Seite ist sichtbar.
* **Props:** `tabs` (`{ id, text, icon?, badge? }`), `selected`, `stripHeight`, `enabled`.
* **Callback:** `onChange(id, true)`.
* **Methoden:** `addTab` (liefert die Seite), `removeTab`, `page(id)`, `tabIds`, `setValue` (ohne Callback), `select`
  (mit Callback), `setText`, `setBadge`.
```lua
local tabs = Tabs.new({ tabs = { { id = "props", text = "Eigenschaften" }, { id = "events", text = "Events" } } })
list.Parent = tabs:page("props")
```

### Splitter
Zwei Bereiche mit ziehbarem Trenner (`"horizontal"`: nebeneinander, `"vertical"`: übereinander). Ein Doppelklick
stellt das Startverhältnis wieder her. Mindestgrößen werden eingehalten.
* **Props:** `direction`, `ratio`, `minFirst`, `minSecond`, `dividerSize`, `host`, `enabled`.
* **Callback:** `onChange(ratio, final)`.
* **Felder:** `first`, `second`, `divider`.
* **Methoden:** `getRatio`/`getValue`, `setRatio`/`setValue`, `isDragging`.
```lua
local split = Splitter.new({ ratio = 0.3, minFirst = 160, host = host, parent = panel.body })
```

### ScrollList
Virtualisierte Liste: Es existieren nur die sichtbaren Zeilen plus `buffer` (4) als gepoolte TextButtons, auch bei
10 000+ Einträgen.
* `render` muss eine Zeile vollständig beschreiben, weil Zeilen wiederverwendet werden.
* **Props:** `render(row, index, list)` (Pflicht), `count`, `rowHeight` (24), `createRow(row, list)`, `buffer`,
  `viewportHeight` (Fallback), `enabled`.
* **Callbacks:** `onRowActivated(index, input, clickCount)`, `onRowInput(index, input, row)`,
  `onHoverChanged(index?)`.
* **Methoden:** `setCount`, `refresh`, `refreshIndex`, `scrollToIndex(i, "nearest"|"top"|"center")`,
  `getVisibleRange`, `rowAt`, `indexOf(row)`, `indexAtCanvasY`, `toCanvas`, `isHovered`, `visibleRowCount`,
  `createdRowCount`.
```lua
ScrollList.new({ count = #entries, render = function(row, i) row.Label.Text = entries[i].name end, parent = panel.body })
```

### Tree
Virtualisierter Baum auf Basis von ScrollList. Der Aufrufer besitzt die Daten: `items()` liefert die
**flachgeklopften sichtbaren** Zeilen. Nach jedem Callback liest der Baum `items()` neu.
* **Item-Felder:** `{ id, label, icon?, color?, depth?, expandable?, expanded?, selected?, muted?, hint?,
  renamable?, droppable? }`.
* **Auswahl:** Klick `replace`, Ctrl `toggle`, Shift ergibt einen Bereich (`replace`), Ctrl+Shift `add`.
* **Bedienung:** Doppelklick oder F2 benennt um. Rechtsklick wählt aus und öffnet das Kontextmenü.
* **Drag & Drop** (braucht `host` und `onDragDrop`): Gezogen wird die ganze Auswahl, abgelegt `before`, `after` oder
  `inside`. Ziele unter einer gezogenen Zeile sind gesperrt; die Sperrliste wird einmal je Drag in O(n) berechnet.
* **Props:** `items`, `host`, `rowHeight`, `indent`, `canDrop`, `emptyText`, `enabled`.
* **Callbacks:** `onToggle(id, expanded)`, `onSelect(ids, mode, clickedId, mods)`, `onActivate(id)`,
  `onRename(id, text)`, `onContext(id?, input)`, `onDragDrop(ids, targetId, position)`.
* **Methoden:** `refresh`, `getItems`, `indexOf`, `scrollTo`, `handleKey(keyCode, mods)`, `beginRename`,
  `endRename(commit)`, `isRenaming`, `dropTargetAt(pos)`, `isDragging`.
```lua
Tree.new({ items = flatten, host = host, onSelect = function(ids, mode) editor:select("components", ids, mode) end,
	onDragDrop = function(ids, target, pos) editor:transact("Verschieben", ...) end, parent = panel.body })
```

## 4. Overlays und Menüs

### Tooltip
Kleines Textfeld an der Maus nach `Tooltip.DELAY` (0,5 s). Es wird über ein abbrechbares `task.delay` ausgelöst und
höchstens einmal je Host angezeigt.
* Verschwindet bei MouseLeave, einem Mausklick und wenn das Ziel zerstört wird.
* **API:** `Tooltip.attach(host, gui, text | () -> string?, { delay? })` liefert ein Handle
  `{ Disconnect, destroy, setText }`, das man einem Maid übergeben kann.
* Außerdem `Tooltip.show(host, text, owner?)`, `Tooltip.hide(host)` und `Tooltip.current(host)`.
```lua
maid:give(Tooltip.attach(host, button.instance, "Effekt abspielen"))
```

### Toast
Kurze Meldungen unten rechts in `host.root`, mit Farbbalken je Schweregrad (`info`, `success`, `warning`, `error`)
und ×-Knopf.
* Standarddauer 3, 3, 5 bzw. 7 s. `duration <= 0` bedeutet: bleibt offen, bis man es schließt.
* Höchstens `Toast.MAX_VISIBLE` (4) Meldungen; die älteste weicht zuerst.
* **API:** `Toast.show(host, message, severity?, duration?)` liefert `{ instance, message, severity, dismiss(),
  isOpen() }`. Dazu `Toast.list(host)` und `Toast.clear(host)`.
```lua
editor.notified:Connect(function(msg, severity) Toast.show(host, msg, severity) end)
```

### Dialog
Modale Dialoge in `host.root`: ein abgedunkelter Hintergrund blockiert das Panel, mehrere Dialoge stapeln sich.
`handle:close()` zählt als Abbrechen.
* `Dialog.confirm(host, title, message, confirmText?, onResult(ok), { cancelText?, danger? })`
* `Dialog.prompt(host, title, label?, default?, onResult(text?), { validate?, placeholder?, confirmText?,
  cancelText? })`: Enter oder OK übernimmt, Abbrechen liefert `nil`.
* `Dialog.text(host, title, longText, { readOnly? (true), confirmText?, closeText?, hint?, onResult? })`: Monospace-
  TextBox zum Markieren und Kopieren (Plugins haben keine Zwischenablage-API). Schreibgeschützt stellt sie
  Änderungen sofort zurück; editierbar liefert sie den Text.
* `Dialog.count(host)`.
```lua
Dialog.confirm(host, "Effekt löschen?", "„Feuerball“ wird entfernt.", "Löschen", function(ok) ... end, { danger = true })
```

### Menus
Gecachte Studio-Kontextmenüs (`PluginMenu`). Ein Menü wird nur neu gebaut, wenn sich die Einträge ändern.
* Aktions-IDs lauten `"<menuId>/<itemId>"`. Deaktivierte Einträge fallen weg, `checked` bekommt das Präfix „✓ “
  (Studio-Menüs kennen beides nicht).
* **API:** `Menus.new(plugin)`, dazu `menus:show(menuId, items) -> itemId?` (**blockiert**, nur in `task.spawn`
  aufrufen), `menus:open(menuId, items, onChoose?)` (startet selbst einen Thread), `build`, `isShowing` und
  `destroy`.
* **Einträge:** `{ id, text, icon?, items? (Untermenü), separator?, disabled?, checked?, onActivate? }`.
```lua
menus:open("explorer_row", { { id = "rename", text = "Umbenennen" }, { separator = true }, { id = "delete", text = "Löschen" } }, onChoose)
```

## 5. ControlKit (intern)

Gemeinsame Helfer der Widgets:
* Bausteine: `corner`, `stroke`, `padding`, `applyCommon`.
* Geometrie und Maus: `geometry` (mit Lune-Fallback), `mouseInRoot`.
* Ebenen: `useSiblingZIndex`, `raise`, `overlay`, `Z`.
* Text und Cursor: `measure` (TextService), `setCursor` (PluginMouse-Icon, best effort).
* Zustand: `cancel` (task.delay-Threads), `hostState` (Zustand je `host.root`, schwach referenziert), `bindStates`
  (Hover/Gedrückt).
* Zahlen: `round`, `decimals`, `clamp`, `format`, `evaluate` (sicherer Rechenausdruck ohne `load`).
* Farben: `derived` (aus Theme abgeleitete Zustandsfarben).

## 6. Nicht in Studio verifiziert

* Pixelgenaue Platzierung (Popups, Tooltips, Slider-Klick) und das Ziehen selbst. Lune prüft nur das
  Geometrie-Fallback.
* Ob `PluginMouse.Icon` über einem DockWidget wirkt, solange das Plugin nicht aktiviert ist.
* Glyphen in den Studio-Schriften (▾ ✓ – × ▶ ↺).
* Ob ein Klick auf den Ausklapp-Pfeil eines Tree-Eintrags die Zeile zusätzlich auswählt.
* Ob zerstörte `PluginAction`s ihre ID für ein neu gebautes Menü freigeben.
* Ob Studio bei `inputThatCausedFocusLoss` wirklich das Escape-InputObject übergibt (davon hängt „Escape setzt
  zurück“ ab).
* Das Dropdown ist nicht virtualisiert: Bei sehr langen Listen das Suchfeld nutzen oder einen Tree verwenden.
