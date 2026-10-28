# Laufzeit-API – Referenz für Spielcode (`AstraVFX`)

Diese Referenz beschreibt die API, die ein Spiel benutzt, um ASTRA-Effekte abzuspielen: das ModuleScript
`AstraVFX` (`src/Runtime/init.luau`) und seine optionale Netzwerkschicht `AstraVFX.Net` (`src/Runtime/Net.luau`).
Sie gibt den **implementierten** Stand wieder (Laufzeitversion `AstraVFX.Version = "0.1.0"`, Schema-Version 1).
Das Effektformat selbst steht in `src/Runtime/Core/Types.luau` und `docs/COMPONENTS_SPEC.md`, die Architektur in
`docs/ARCHITECTURE.md` §5, die Engine-Fakten mit Quellen in `docs/ROBLOX_API_CONSTRAINTS.md`.

Ein fertiges Beispiel-Place mit Server- und Client-Skript liegt in [`examples/`](../examples/README.md).

---

## Inhalt

1. [Einbinden](#1-einbinden)
2. [Schnellstart](#2-schnellstart)
3. [Effekte registrieren](#3-effekte-registrieren)
4. [Abspielen: `Play` und `TryPlay`](#4-abspielen-play-und-tryplay)
5. [Das Handle](#5-das-handle)
6. [Ereignisse (Events)](#6-ereignisse-events)
7. [Lebenszyklus, Aufräumen, Abbruch](#7-lebenszyklus-aufräumen-abbruch)
8. [Qualität](#8-qualität)
9. [Vorladen, Pool und Cache](#9-vorladen-pool-und-cache)
10. [Validieren, Version, Update-Ereignis](#10-validieren-version-update-ereignis)
11. [Netzwerk: `AstraVFX.Net`](#11-netzwerk-astravfxnet)
12. [Sicherheitsmodell](#12-sicherheitsmodell)
13. [StreamingEnabled](#13-streamingenabled)
14. [Performance-Tipps](#14-performance-tipps)
15. [Fehlerbehebung](#15-fehlerbehebung)
16. [Grenzwerte auf einen Blick](#16-grenzwerte-auf-einen-blick)

---

## 1. Einbinden

Die Laufzeit hängt von nichts außerhalb ihres eigenen Ordners ab und braucht das Plugin **nicht**.

1. Laufzeitpaket bauen: `rojo build runtime.project.json -o build/AstraVFX.rbxm` (oder per Rojo synchronisieren).
2. Das ModuleScript **`AstraVFX`** nach **`ReplicatedStorage`** legen. Server und Clients müssen es sehen; die
   Netzwerkschicht legt ihre RemoteEvents unter genau diesem Modul an (§11).
3. Effekte in einen Ordner **`AstraVFX.Effects`** legen (direktes Kind des Moduls). Erlaubt sind
   `StringValue`s mit JSON-Text (so landen `*.vfx.json`-Dateien über die Rojo-`syncRules` `"use": "text"` im Spiel),
   ModuleScripts, die eine Definitionstabelle oder JSON-Text zurückgeben, und Unterordner davon. Alles darin wird
   beim ersten Zugriff automatisch registriert (§3.2).

```
ReplicatedStorage
└── AstraVFX              (ModuleScript, src/Runtime)
    ├── Core/ …           (Laufzeit-Module)
    ├── Net               (ModuleScript)
    ├── Effects           (Folder)
    │   ├── VioletImpact  (StringValue, JSON-Text aus effects/VioletImpact.vfx.json)
    │   └── FireExplosion (StringValue)
    └── AstraVFXNet       (Folder, legt der Server mit Net.Init() an)
```

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AstraVFX = require(ReplicatedStorage:WaitForChild("AstraVFX"))
```

Alle Funktionen sind synchron und **yielden nie** (kein `WaitForChild`, kein `task.wait` in der Laufzeit). Die
Laufzeit ist pro Maschine eine eigene Instanz: Server und jeder Client haben ihre eigene Registry, ihren eigenen
Cache und Pool.

## 2. Schnellstart

**Lokal abspielen (Client oder Server):**

```lua
local AstraVFX = require(game:GetService("ReplicatedStorage"):WaitForChild("AstraVFX"))

local handle = AstraVFX.Play("VioletImpact", {
	Position = Vector3.new(0, 5, 0),
	Scale = 1.5,
	OnEvent = function(name: string)
		print("Effekt-Ereignis", name) -- z. B. "Impact" (Marker mit event = "Impact")
	end,
})
if handle then -- nil nur, wenn die Obergrenze aktiver Effekte voll mit Schleifen ist (§4.3)
	handle.Finished:Connect(function(reason: string)
		print("fertig:", reason) -- "finished" oder "destroyed"
	end)
end
```

**Vom Server an alle Clients (empfohlen für Effekte, die alle sehen sollen):**

```lua
-- Server (Script)
local AstraVFX = require(game:GetService("ReplicatedStorage"):WaitForChild("AstraVFX"))
AstraVFX.Net.Init()
AstraVFX.Net.PlayAll("VioletImpact", { CFrame = workspace.VFXTarget.CFrame })
```

```lua
-- Client (LocalScript, z. B. in StarterPlayerScripts)
local AstraVFX = require(game:GetService("ReplicatedStorage"):WaitForChild("AstraVFX"))
AstraVFX.Net.Listen()
```

## 3. Effekte registrieren

Ein Effekt wird unter seiner `id`, seinem `name` und – bei Instanz-Quellen – dem Instanznamen gefunden. Alle drei
funktionieren in `Play`, `TryPlay`, `Preload`, `IsRegistered`, `Unregister` und auf dem Client in `Net`.

### 3.1 Funktionen

| Funktion | Rückgabe | Beschreibung |
|---|---|---|
| `AstraVFX.Register(source)` | `string` bzw. `{ string }` | Registriert eine Definition. `source` = Definitionstabelle, JSON-Text, ModuleScript (gibt Tabelle oder JSON-Text zurück), StringValue (JSON-Text) → **ein** Name; Folder oder Configuration (rekursiv, Kinder nach Namen sortiert) → **Liste** der Namen. |
| `AstraVFX.Unregister(name)` | `boolean` | Entfernt einen Effekt (per id oder Name); verwirft seine kompilierten Varianten und gepoolten Kopien. `false`, wenn unbekannt. |
| `AstraVFX.IsRegistered(name)` | `boolean` | Auch nach automatischer Registrierung aus `AstraVFX.Effects` (§3.2). |
| `AstraVFX.GetNames()` | `{ string }` | Namen (Feld `name`) aller registrierten Effekte, sortiert. Scannt vorher `AstraVFX.Effects`. |

Regeln (alle implementiert):

* **Migration + Validierung bei jeder Registrierung.** Ältere Dokumente (z. B. das Konzeptformat aus dem
  Projektauftrag, Schema 0) werden mit `Core/Migration` auf Schema 1 gebracht und dann mit `Core/Validation`
  geprüft. Bei Fehlern wirft `Register` einen lesbaren Fehler mit bis zu 12 Diagnosen:

  ```text
  AstraVFX.Register: effect "Simple" is invalid (2 errors):
    error effect.duration duration: …
    error component.type components[1].type: …
  ```

  Warnungen werden still akzeptiert – mit `AstraVFX.Validate` sieht man sie (§10).
* **Ersetzen:** Eine Definition mit bereits registrierter `id` ersetzt die alte. Deren kompilierte Varianten und
  gepoolte Kopien werden verworfen; laufende Effekte spielen mit ihrer alten Kopie zu Ende.
* Modulquellen dürfen nicht yielden (sie werden mit `require` geladen).

```lua
-- Tabelle
AstraVFX.Register({
	schemaVersion = 1, id = "pop", name = "Pop", duration = 0.5,
	components = { { id = "core", name = "Core", type = "flash" } },
})
-- JSON-Text, z. B. aus einem StringValue
AstraVFX.Register(someStringValue.Value)
-- ganzer Ordner
local names = AstraVFX.Register(ReplicatedStorage.MyEffects) --> { "FireExplosion", "VioletImpact" }
```

### 3.2 Automatische Registrierung aus `AstraVFX.Effects`

Die Kinder von `AstraVFX.Effects` werden **beim ersten Nachschlagen** eines unbekannten Namens registriert (auch
`GetNames` scannt). Spätere Fehltreffer registrieren nur Kinder, die noch nicht gesehen wurden – Effekte, die zur
Laufzeit in den Ordner gelegt werden, sind also beim nächsten Fehltreffer verfügbar. Ein kaputtes Kind wird mit
`warn("[AstraVFX] skipped effect …")` gemeldet und übersprungen; die übrigen Effekte funktionieren weiter. Ein
einmal gesehenes Kind wird nicht erneut gelesen: Änderungen an einem bereits registrierten StringValue übernimmt man
mit `AstraVFX.Register(stringValue)`.

**Auf Clients** müssen die Effekte repliziert sein, bevor man sie zum ersten Mal nachschlägt (`Play`, `Preload` …).
Ein LocalScript wartet deshalb vor dem ersten Zugriff auf das Ende der Erstreplikation:

```lua
if not game:IsLoaded() then
	game.Loaded:Wait()
end
```

Trifft ein Name trotzdem zu früh ein, ist das kein Dauerzustand: Der nächste Fehltreffer scannt den Ordner erneut.

## 4. Abspielen: `Play` und `TryPlay`

```lua
AstraVFX.Play(name: string, options: PlayOptions?) -> Handle?
AstraVFX.TryPlay(name: string, options: PlayOptions?) -> (Handle?, string?)
```

`Play` wirft bei unbekanntem Namen (`AstraVFX.Play: unknown effect "X"`) und bei ungültigen Optionen
(`AstraVFX.Play: unknown option "Foo"`, `… Scale must be a finite number > 0, got -1`). `TryPlay` macht dasselbe,
gibt aber `nil, Fehlermeldung` zurück statt zu werfen (auch bei Fehlern beim Kompilieren oder Bauen). Beide yielden
nie. Den einzigen Fall ohne Fehler und ohne Handle regelt die Obergrenze aktiver Effekte (§4.3): `Play` gibt dann
`nil` zurück (mit `warn`), `TryPlay` `nil, "limit"`.

Ablauf eines `Play`: Optionen prüfen → Name nachschlagen (inkl. automatischer Registrierung) → Obergrenze aktiver
Effekte prüfen (§4.3) → kompilierte Variante aus dem Cache holen oder kompilieren (§9) → gepoolte Kopie
wiederverwenden oder neu bauen → unter `Parent` hängen → für die Obergrenze verdrängte Effekte stoppen → abspielen.
Die erste Aktion (Emit, Sound …) läuft frühestens im **nächsten** Frame: Ein `Emit` im selben Frame, in dem die
Instanzen geparentet wurden, kann von der Engine ignoriert werden (Constraints K6). Das kostet höchstens einen Frame
Latenz.

### 4.1 Alle Optionen (`Types.PlayOptions`)

Unbekannte Schlüssel sind Fehler (Tippfehlerschutz).

| Option | Typ | Standard | Bedeutung |
|---|---|---|---|
| `CFrame` | `CFrame` | Identität | Weltursprung des Effekts. Mit `Attach`: nur **Ersatzposition**, solange das Ziel fehlt (z. B. nicht gestreamt) – kein Versatz. |
| `Position` | `Vector3` | – | Kurzform für `CFrame.new(Position)` (ohne Rotation). Wird ignoriert, wenn `CFrame` gesetzt ist. |
| `Attach` | `BasePart` \| `Attachment` \| `Model` | – | Effekt folgt dem Ziel **jeden Frame** (`BasePart.CFrame`, `Attachment.WorldCFrame`, `Model:GetPivot()`). Verlässt das Ziel die Welt (zerstört, entfernt, ausgestreamt), bleibt der Effekt an der letzten Position und spielt zu Ende. |
| `Offset` | `CFrame` | – | Wird auf `Attach` bzw. `CFrame` multipliziert (`basis * Offset`). −Z ist vorne: `CFrame.new(0, 0, -6)` = 6 Studs vor dem Ziel. |
| `Parent` | `Instance` | `Workspace` | Elternteil des Effekt-Containers (`Folder "AstraVFX_<Name>"`). Auf Clients unter Workspace (oder einem clientseitig erzeugten Ordner darin) lassen, **nie** unter server-eigenen Instanzen, die StreamingEnabled entfernen kann (§13). |
| `Scale` | `number` > 0 | 1 | Gleichmäßige Größe: Längen, Größen, Geschwindigkeiten, Breiten, Reichweiten (Eigenschaften mit `scale = "length"`). Wird auf `50` begrenzt. Kompilieroption (eigene Cache-Variante, §9). |
| `Quality` | `"Low"` \| `"Medium"` \| `"High"` \| `"Auto"` | `SetQuality`-Wert, anfangs `"Auto"` | Qualitätsprofil dieses Abspielens (§8). |
| `TimeScale` | `number` ≥ 0 | 1 | Zeitfaktor (multipliziert mit dem `timeScale` der Definition), auf `10` begrenzt. `0` hält die Effektzeit an. Wirkung auf Engine-Partikel siehe §5.2. |
| `Seed` | endliche Zahl | `seed` der Definition bzw. Hash der id | Zufallsvariante prozeduraler Teile (Trümmer, Blitze, Graph-Zufall). **Jeder neue Seed ist eine neue Kompilier-Variante** – für Cache-Treffer weglassen oder aus einer kleinen festen Menge wählen (§14). |
| `Loop` | `boolean` | `loop` der Definition | Endlosschleife. Beenden mit `handle:Stop()` / `handle:SetLoop(false)`. |
| `Palette` | `{ [string]: Color3 }` | – | Überschreibt Palettenfarben (`"$primary"` …) zum Umfärben; neue Schlüssel sind erlaubt. Kompilieroption (eigene Variante pro Farbkombination). |
| `OnEvent` | `(name: string) -> ()` | – | Wird bei jedem Ereignis dieses Abspielens aufgerufen (§6). Fehler darin werden abgefangen und mit `warn` gemeldet. |
| `Autoplay` | `boolean` | `true` | `false`: gebaut und bei t = 0 posiert, aber pausiert, bis `handle:Resume()`. |

### 4.2 Beispiele

```lua
-- An eine Waffe heften, 2 Studs vor dem Griff, halbe Größe, bläulich umgefärbt
local handle = AstraVFX.Play("FireExplosion", {
	Attach = tool.Handle,
	Offset = CFrame.new(0, 0, -2),
	Scale = 0.5,
	Palette = { fire = Color3.fromRGB(80, 160, 255) },
})

-- Vorbereiten und später exakt starten
local charge = AstraVFX.Play("VioletImpact", { Position = spot, Autoplay = false })
task.delay(0.5, function()
	if charge then
		charge:Resume()
	end
end)

-- Ohne Fehler, wenn der Effekt fehlen könnte
local fx, err = AstraVFX.TryPlay(effectName, { Position = hitPosition })
if not fx then
	warn(err) -- z. B. 'AstraVFX.Play: unknown effect "X"' oder "limit"
end
```

### 4.3 Obergrenze aktiver Effekte: `SetMaxActive`

```lua
AstraVFX.SetMaxActive(n: number)   -- ganze Zahl >= 1 oder math.huge (unbegrenzt); Standard 64
AstraVFX.GetMaxActive() -> number
AstraVFX.DEFAULT_MAX_ACTIVE        -- 64
```

Schutz gegen Effekt-Fluten (z. B. ein Dauerfeuer, das pro Treffer einen Effekt startet). Gezählt werden Effekte
dieser Maschine, die über `Play` gestartet wurden und gerade **spielen oder pausieren** (ausklingende, also
gestoppte Effekte zählen nicht mehr – `ActiveCount()` zählt sie dagegen mit).

* Würde ein `Play` die Grenze überschreiten, werden die **ältesten nicht schleifenden** Effekte sanft gestoppt
  (`Stop()`, Partikel klingen aus) – so viele wie nötig, normalerweise einer – und der neue Effekt spielt.
* Füllen schleifende Effekte (`Loop`, `SetLoop(true)` oder `loop` der Definition) die Grenze allein, wird nichts
  gestoppt und das neue `Play` abgelehnt: `warn("[AstraVFX] Play \"X\" refused: …")`, `Play` → `nil`,
  `TryPlay` → `nil, "limit"`.
* Unbekannte Namen und falsche Optionen werfen trotzdem zuerst. Ein Absenken der Grenze stoppt laufende Effekte
  nicht; es gilt ab dem nächsten `Play`.
* Gestoppt wird erst, wenn die neue Kopie fertig gebaut ist: Scheitert ein `Play` unterwegs (z. B. `TryPlay` mit
  einer ungültigen `Palette`-Farbe → `nil, Fehlermeldung`), bleiben alle laufenden Effekte unberührt.

```lua
-- Mobile: weniger gleichzeitige Effekte
if game:GetService("UserInputService").TouchEnabled then
	AstraVFX.SetMaxActive(24)
end
```

## 5. Das Handle

`Play` gibt ein Handle zurück; es gehört zu genau **einem** Abspielvorgang (einer gebauten Kopie).

### 5.1 Felder und Signale

| Feld | Typ | Bedeutung |
|---|---|---|
| `handle.Name` | `string` | Name des Effekts |
| `handle.Id` | `string` | id des Effekts |
| `handle.Finished` | Signal(`reason: string`) | feuert **einmal**: `"finished"` (normal zu Ende, auch nach `Stop`) oder `"destroyed"` (`Destroy`, `StopAll(true)`) |
| `handle.Event` | Signal(`name: string`) | Ereignisse dieses Abspielens (§6) |

Signale: `:Connect(fn)`, `:Once(fn)` → Verbindung mit `.Connected` und `:Disconnect()`. Handler laufen über
`task.spawn` (sofort, in Reihenfolge); ein yieldender Handler hält nur sich selbst an, nicht die Effekte. Nach dem
Ende werden die Signale getrennt.

### 5.2 Methoden

| Methode | Wirkung |
|---|---|
| `handle:Stop(fade: number?)` | **Sanft beenden:** keine neue Emission, keine weiteren Aktionen, lebende Partikel klingen aus; danach aufräumen. Ohne `fade` wartet es die Nachlaufzeit ab (längste Partikel-/Trail-Lebensdauer, bei Zeitlupe entsprechend länger: Lebensdauer / Rate, höchstens 10×), mit `fade` genau so viele echte Sekunden (`0` = sofort). Mehrfach aufrufbar. |
| `handle:Destroy()` | **Sofort entfernen** (Kopie zurück in den Pool oder zerstört). `Finished` feuert mit `"destroyed"`. Idempotent. |
| `handle:Pause()` / `handle:Resume()` | Effektzeit, Spuren, Zeitplan und prozedurale Bewegung frieren ein; das Attach-Ziel wird weiter verfolgt. Die Laufzeit setzt dabei den Zeitfaktor der Komponenten auf 0 (Partikel: `ParticleEmitter.TimeScale = 0`, Beams: `TextureSpeed = 0`; ob die Engine bei `TimeScale = 0` sofort und ohne Verschwinden anhält, ist Studio-Testpunkt U2). `Resume` startet auch einen mit `Autoplay = false` erzeugten Effekt. |
| `handle:SetTimeScale(n)` | Zeitfaktor ändern (≥ 0, max. 10; ersetzt die Play-Option `TimeScale`). Effektuhr × n; `ParticleEmitter.TimeScale` = `timeScale` der Partikel-Komponente × `timeScale` der Definition × n, auf den Engine-Bereich 0..1 begrenzt (Zeitlupe geht, Zeitraffer beschleunigt Partikel nicht über normal); `Beam.TextureSpeed` (auch Blitz-Beams) × `timeScale` der Definition × n. Trails altern in Echtzeit, Sounds behalten ihre Geschwindigkeit. |
| `handle:SetCFrame(cf)` | Neuer fester Ursprung; beendet das Folgen eines `Attach`-Ziels (`Offset` gilt weiter). |
| `handle:SetLoop(loop)` | Schleife ein-/ausschalten (auch während des Abspielens). |
| `handle:Seek(t)` | Springt deterministisch zu Zeit `t` (auf 0..Dauer begrenzt), **ohne** Emission/Sounds; Partikel werden geleert (die Engine kann Partikel nicht vorspulen). Für Werkzeuge/Zwischensequenzen; aus `"playing"` läuft der Effekt ab `t` weiter, ein pausierter bleibt pausiert. Wirkungslos, sobald der Effekt ausklingt (`"stopping"`) oder beendet ist. |
| `handle:Fire(name)` | Löst die Graph-Flüsse `OnEvent(name)` ab der aktuellen Zeit aus (nur während des Abspielens/Pausierens; ohne Graph wirkungslos). |
| `handle:GetTime()` | aktuelle Effektzeit in Sekunden |
| `handle:GetState()` | `"idle"`, `"playing"`, `"paused"`, `"stopping"`, `"finished"` oder `"destroyed"` |
| `handle:IsPlaying()` | `true`, bis der Effekt gestoppt, beendet oder zerstört wurde (auch während er pausiert ist) |

Alle Methoden sind nach dem Ende gefahrlos aufrufbar (sie tun dann nichts); falsche Argumenttypen sind Fehler.

## 6. Ereignisse (Events)

Ein Ereignis ist ein Name (Muster `[A-Za-z_][A-Za-z0-9_-]*`), den ein Effekt zu einer bestimmten Zeit meldet:

| Quelle in der Definition | Beispiel |
|---|---|
| Marker mit `event` | `{ "id": "impact", "time": 0.12, "label": "Impact", "event": "Impact" }` |
| Komponenten-Event mit Aktion `fire` und `name` | `{ "id": "e1", "time": 0.3, "action": "fire", "name": "Hit" }` |
| Graph-Knoten `FireEvent(name)` | auch innerhalb von `Loop`/`Delay`-Flüssen |

Empfang: `OnEvent` in den Play-Optionen **oder** `handle.Event:Connect(...)` – beide bekommen dieselben Namen.

```lua
local handle = AstraVFX.Play("FireExplosion", { Position = hit })
if handle then
	handle.Event:Connect(function(name: string)
		if name == "Impact" then
			cameraKick() -- rein kosmetische Reaktion
		end
	end)
end
```

**Wichtig:** Ereignisse sind für kosmetische Reaktionen gedacht (Kamera, UI, Sound, Folge-Effekt). Gameplay
(Schaden, Treffer) gehört auf den Server mit eigener Zeitsteuerung – ein Client-Ereignis ist weder garantiert
(niedrige Qualität, verworfene Nachricht, Tab im Hintergrund) noch vertrauenswürdig (§12). Das Beispiel
`examples/ServerScriptService/AstraVFXDemo.server.luau` zeigt das Muster.

`handle:Fire(name)` ist die Gegenrichtung: Das Spiel löst `OnEvent(name)`-Flüsse im Node-Graph des Effekts aus
(z. B. „Detonate“ beim Treffer eines Projektils).

## 7. Lebenszyklus, Aufräumen, Abbruch

```
Play ──► playing ──(Ende der Dauer)──► Nachlauf (Partikel klingen aus) ──► finished
           │  ▲                                                              ▲
     Pause │  │ Resume          Stop(fade?) ──► stopping ──(fade/Nachlauf)───┘
           ▼  │
         paused                Destroy() / StopAll(true) ──► destroyed (sofort)
```

* **Automatisches Aufräumen:** Ein nicht schleifender Effekt beendet sich selbst; man muss nichts zerstören. Die
  Nachlaufzeit ist echte Zeit und reicht bis zur längsten Partikel-/Trail-Lebensdauer; bei Zeitlupe altern Partikel
  langsamer, die Nachlaufzeit wächst entsprechend (Lebensdauer / Rate, höchstens 10×).
* **Pool:** Am Ende geht die Kopie in den Pool (zurückgesetzt, `Parent = nil` ⇒ rendert und repliziert nicht),
  sofern ihre Variante noch im Cache ist und ihr Container noch geparentet ist. Wurde der Container von außen
  entfernt (Ordner geleert, Elternteil zerstört – z. B. ein respawnter Charakter als `Parent`), wird die Kopie
  zerstört statt gepoolt.
* **Schleifen** enden nie von selbst: `handle:Stop()` oder `handle:SetLoop(false)`.
* **`AstraVFX.StopAll(immediate: boolean?)`** stoppt alle über `Play` gestarteten Effekte dieser Maschine – sanft
  oder mit `true` sofort. Typisch bei Rundenende/Teleport.
* **`AstraVFX.ActiveCount()`** zählt über `Play` gestartete Effekte, die noch nicht beendet sind (auch pausierte
  und ausklingende).
* **Obergrenze:** Ein `Play`, das mehr als `GetMaxActive()` (Standard 64) spielende oder pausierte Effekte ergäbe,
  stoppt die ältesten nicht schleifenden – oder wird abgelehnt, wenn nur Schleifen laufen (§4.3).
* **Charakter-Respawn:** Mit `Attach = humanoidRootPart` (und Standard-`Parent`) folgt der Effekt dem Teil, solange
  es in der Welt ist; wird der Charakter beim Respawn entfernt, bleibt der Effekt an der letzten Position und spielt
  zu Ende. Mit `Parent = character` wird er beim Entfernen des Charakters mitzerstört.
* **Fehlerisolation:** Wirft eine Komponente während eines Frames, wird nur dieser Effekt entfernt (mit `warn`);
  alle anderen laufen weiter. Es gibt genau **eine** RunService-Verbindung für alle Effekte; sie wird getrennt,
  sobald nichts mehr läuft.

## 8. Qualität

```lua
AstraVFX.SetQuality(level: "Low" | "Medium" | "High" | "Auto")   -- Standard für alle folgenden Play-Aufrufe
AstraVFX.GetQuality() -> "Low" | "Medium" | "High" | "Auto"     -- anfangs "Auto"
```

Die Qualität wird **pro `Play`** aufgelöst (Option `Quality`, sonst der `SetQuality`-Wert). Laufende Effekte
ändern sich nicht nachträglich.

| Profil | Anzahl (`countScale`) | Segmente (`segmentScale`) | Partikelgröße (`sizeCompensation`) | Schatten | max. Lichter pro Effekt |
|---|---|---|---|---|---|
| `Low` | × 0.35 | × 0.5 | × 1.12 | aus | 2 |
| `Medium` | × 0.65 | × 0.75 | × 1.05 | aus | 4 |
| `High` | × 1 | × 1 | × 1 | wie definiert | unbegrenzt |

* „Anzahl“ betrifft Emissionsrate, Burst- und Emit-Anzahlen, Trümmeranzahl (mindestens 1, wenn > 0); „Segmente“
  betrifft prozedurale Unterteilungen (Ringe, Blitze, Schockwellen-Schichten), **nicht** `Beam.Segments`.
* Lichter: Das Budget zählt `light`-Komponenten und die eingebauten Lichter von `sphere`/`flash`. Passt ein
  Licht nicht mehr, verlieren `sphere`/`flash` nur ihr Licht; überzählige `light`-Komponenten entfallen.
* Komponenten mit `minQuality` entfallen unterhalb dieser Stufe; `qualityOverrides` setzen exakte Werte pro Stufe;
  der Abschnitt `quality` der Definition kann die Profilzahlen pro Effekt anpassen.

**`"Auto"`** (`Core/Quality.detect`, bei jedem `Play` neu gelesen):

| Umgebung | Ergebnis |
|---|---|
| Server, Studio (auch Playtest-Clients in Studio), kein Client | `Medium` |
| Live-Client: `UserGameSettings.SavedQualityLevel` = QualityLevel1–3 | `Low` |
| QualityLevel4–7 | `Medium` |
| QualityLevel8–10 | `High` |
| `Automatic` (tatsächliche Stufe ist für Skripte nicht lesbar) | `Medium` |

Diese Zuordnung ist eine **Annahme** (Engine: Schatten ab Stufe < 4 aus; keine offizielle Zuordnung,
Constraints §20). Wer es genauer will, setzt die Qualität selbst, z. B. aus einem Einstellungsmenü:
`AstraVFX.SetQuality("Low")`.

## 9. Vorladen, Pool und Cache

```lua
AstraVFX.Preload(name: string, options: { Count: number?, Quality: string?, Scale: number?,
                 Seed: number?, Palette: { [string]: Color3 }? }?) -> number
```

`Preload` kompiliert die Variante und baut `Count` (Standard 1, ganze Zahl ≥ 0) Kopien in den Pool. Rückgabe: wie
viele Kopien **neu gebaut** wurden (bereits freie Kopien der Variante werden auf `Count` angerechnet). Andere
Optionen sind Fehler.

* **Varianten:** Eine Variante ist (Effektinhalt, aufgelöste Qualität, `Scale`, `Seed`, `Palette`). Nur ein
  `Play` mit **derselben** Variante trifft den vorgewärmten Pool – also `Preload` mit denselben `Scale`/`Seed`/
  `Palette`/`Quality`-Werten aufrufen, die später `Play` benutzt. `"Auto"` wird beim `Preload` aufgelöst.
* **Cache:** höchstens 64 kompilierte Varianten pro Maschine; die älteste wird samt ihren gepoolten Kopien
  verworfen. `Register` derselben id verwirft alle Varianten dieses Effekts.
* **Pool:** pro Variante werden standardmäßig 2 freie Kopien behalten; `Preload` mit größerem `Count` hebt diese
  Kapazität für die Variante an. Freie Kopien liegen mit `Parent = nil` bereit (kein Rendering, keine
  Replikation) und sind beim Wiederverwenden in exakt dem frisch gebauten Zustand.

```lua
-- Client-Start: die häufigsten Effekte vorwärmen (gleiche Optionen wie später beim Play)
AstraVFX.Preload("FireExplosion", { Count = 3 })
AstraVFX.Preload("VioletImpact", { Count = 2, Scale = 0.4 })
```

## 10. Validieren, Version, Update-Ereignis

```lua
AstraVFX.Validate(source) -> (ValidationResult, EffectDefinition?)
```

Migriert und validiert eine Definition (Tabelle oder JSON-Text), **ohne** sie zu registrieren. `ValidationResult`
= `{ ok: boolean, errors: { Diagnostic }, warnings: { Diagnostic }, infos: { Diagnostic } }` inklusive der
Migrationshinweise; die zweite Rückgabe ist die migrierte Definition (bzw. `nil`, wenn es gar kein Dokument ist).
`Diagnostic` = `{ severity, code, path, message, hint?, componentId? }`, Pfade 1-basiert
(`components[2].properties.rate`).

```lua
local result, def = AstraVFX.Validate(stringValue.Value)
if not result.ok then
	for _, d in result.errors do
		warn(d.code, d.path, d.message)
	end
end
```

* `AstraVFX.Version` – Laufzeitversion (`"0.1.0"`).
* `AstraVFX.SetUpdateEvent("Heartbeat" | "PreRender")` – RunService-Ereignis, das alle Effekte antreibt
  (Standard `Heartbeat`). `PreRender` gibt es nur auf Clients; auf dem Server wird gewarnt und `Heartbeat` behalten.

Funktionen mit Unterstrich (`AstraVFX._reset`, `AstraVFX._cacheSize`, `Net._encode` …) sind Test-/Plugin-Hooks und
gehören nicht zur Spiel-API.

## 11. Netzwerk: `AstraVFX.Net`

Server-autoritatives Gameplay, kosmetisches Rendering auf den Clients: Der Server baut **keine**
Effektinstanzen. Er schickt eine kleine Nachricht (Name + Position + wenige Zahlen), jeder Client prüft sie und
spielt den Effekt lokal über `AstraVFX.TryPlay`. Das entspricht der offiziellen Empfehlung, Explosionen und Zauber
nicht serverseitig als Instanzen zu erzeugen (Constraints RE-8).

### 11.1 Server

| Funktion | Beschreibung |
|---|---|
| `Net.Init() -> Folder` | Legt (oder findet) `AstraVFX.AstraVFXNet` mit `RemoteEvent "Play"` und `UnreliableRemoteEvent "PlayUnreliable"` an. Die Remotes entstehen vor dem Parenten des Ordners. Wird von den `Play*`-Funktionen bei Bedarf selbst aufgerufen – früh aufrufen (Serverstart) ist trotzdem empfehlenswert, damit Clients die Remotes vorfinden. |
| `Net.PlayAll(name, options?)` | an alle Clients (`FireAllClients`) |
| `Net.PlayFor(players, name, options?)` | an einen `Player` oder eine Liste von Spielern (`FireClient` je Spieler) |
| `Net.PlayNear(position, radius, name, options?) -> { Player }` | an alle Spieler, deren Charakter-Wurzel (`HumanoidRootPart`, sonst `PrimaryPart`) höchstens `radius` Studs von `position` entfernt ist; gibt die Empfänger zurück. Spieler ohne Charakter bekommen nichts. |

**Optionen** (nur serialisierbare; alles andere ist ein Fehler, weil es nicht sinnvoll repliziert werden kann):

| Option | Typ | Bedeutung |
|---|---|---|
| `CFrame` / `Position` | `CFrame` / `Vector3` | Ursprung |
| `Attach` | `BasePart` \| `Attachment` \| `Model` | Instanzreferenz; ohne `CFrame`/`Position` fügt der Server die **aktuelle** CFrame des Ziels als Ersatz hinzu (§13) |
| `Scale`, `TimeScale`, `Seed` | Zahl | wie bei `Play` |
| `Quality` | `"Low"` \| `"Medium"` \| `"High"` \| `"Auto"` | erzwingt eine Stufe auf allen Empfängern (normalerweise weglassen ⇒ jeder Client nimmt seine eigene) |
| `Unreliable` | `boolean` | `true` ⇒ `UnreliableRemoteEvent` (§11.3) |

Nicht übertragbar: `Offset`, `Parent`, `Loop`, `Palette`, `OnEvent`, `Autoplay`. Wer z. B. umgefärbte Varianten
braucht, registriert sie als eigene Effekte oder spielt sie clientseitig mit eigener Logik.

**Nachricht** (Payload): `{ name, cframe?, position?, attach?, scale?, timeScale?, seed?, quality? }`.

### 11.2 Client

```lua
local listener = AstraVFX.Net.Listen()   -- idempotent, yieldet nie
-- listener.Connected, listener:Disconnect()
```

`Listen` verbindet `OnClientEvent` beider Remotes. Sind Ordner/Remotes noch nicht repliziert, wartet es per
`ChildAdded` und verbindet sich, sobald sie erscheinen – das LocalScript darf also sofort `Listen()` aufrufen.

Prüfung jeder Nachricht auf dem Client: Tabelle; `name` nicht leer, höchstens 100 Zeichen, **registrierter**
Effekt; `cframe`/`position`/`attach` vom richtigen Typ (fehlendes `attach` – ausgestreamt – ist erlaubt);
Zahlen endlich; `quality` gültig. `scale` wird auf **0.05 … 20**, `timeScale` auf **0.05 … 10** geklemmt;
unbekannte Schlüssel werden ignoriert (Vorwärtskompatibilität). Ungültige Nachrichten werden still verworfen und
gezählt – nie ein Fehler. Kann ein gültiger Effekt nicht gestartet werden (z. B. Obergrenze voll mit Schleifen,
§4.3), meldet der Client das per `warn` und zählt die Nachricht ebenfalls als verworfen. Diagnose:
`AstraVFX.Net.stats = { received, played, ignored }`.

### 11.3 Zuverlässig oder unzuverlässig?

| | `RemoteEvent` (Standard) | `Unreliable = true` |
|---|---|---|
| Zustellung | garantiert, geordnet (auch über verschiedene RemoteEvents) | kann verloren gehen, ungeordnet |
| Ohne Listener | wird (begrenzt) gepuffert | wird **verworfen** |
| Überlast | verzögert | verworfen |
| Größe | – | Nachrichten > 1000 Bytes werden verworfen; ASTRA nimmt ab geschätzten **900 Bytes** automatisch das zuverlässige Remote |
| Geeignet für | einmalige, wichtige Effekte (Ultimate, Tod, Treffer-Feedback) | häufige, ersetzbare Effekte (Schritte, Mündungsfeuer, Dauerfeuer-Funken) |

Effekte, die vor dem `Listen()` eines Clients unzuverlässig gesendet werden, kommen bei ihm nie an.

```lua
-- Server: Treffer – zuverlässig, nur für Spieler in Hörweite
AstraVFX.Net.PlayNear(hitPosition, 150, "FireExplosion", { Position = hitPosition })
-- Server: Mündungsfeuer – häufig und ersetzbar
AstraVFX.Net.PlayAll("MuzzleFlash", { Attach = gun.Muzzle, Unreliable = true })
```

## 12. Sicherheitsmodell

* **Gameplay ist server-autoritativ.** Schaden, Treffer, Cooldowns und Zeitpunkte entscheidet der Server mit seiner
  eigenen Uhr. Effekte sind reine Darstellung; ihr Ablauf auf einem Client beeinflusst nie das Spielergebnis.
* **Kosmetisches Rendering auf den Clients.** Jeder Client rendert nur für sich; ein manipulierter Client kann
  höchstens sein eigenes Bild verändern.
* **Kein Pfad Client → Server.** `AstraVFX.Net` hat bewusst keinen `FireServer`-Weg; ein Client kann über ASTRA
  weder Effekte bei anderen auslösen noch den Server belasten. Braucht ein Spiel spielerausgelöste Effekte für
  alle (z. B. eine Fähigkeit), schickt der Client **sein eigenes, vom Spiel validiertes** Remote an den Server
  (Cooldown, Reichweite, Berechtigung prüfen), und erst der Server ruft `Net.PlayAll/PlayNear` auf.
* **Eingaben vom Netz werden geprüft** (§11.2): nur registrierte Effekte, Typprüfung, geklemmte Skalierung und
  Zeitfaktoren, Längengrenze für Namen. Effektdefinitionen kommen nur aus dem Spiel selbst (Registry), nie aus der
  Nachricht.
* `AstraVFX.Play` auf dem **Server** funktioniert, baut aber echte Instanzen, die an alle Clients repliziert werden
  (Netzwerklast, Kamera-Komponenten sind dort wirkungslos). Für Spiele: `Net` benutzen.

## 13. StreamingEnabled

* Eine Nachricht und die Instanz, auf die sie verweist (`Attach`), reisen unabhängig. Fehlt das Ziel beim Client
  (nicht gestreamt), kommt die Referenz als `nil` an; der Client spielt dann an der vom Server mitgeschickten
  CFrame (Ersatzposition des Ziels zum Sendezeitpunkt). Kommt das Ziel an, aber liegt es nicht in der Welt, bleibt
  die Ersatzposition, bis es in der Welt ist.
* Wird ein Attach-Ziel während des Abspielens ausgestreamt oder entfernt, bleibt der Effekt an der letzten
  Position und spielt zu Ende.
* Effekte liegen standardmäßig direkt in `Workspace` (clientseitig erzeugt ⇒ werden **nicht** ausgestreamt,
  Constraints ST-3). Ein `Parent` unter server-eigenen Instanzen ist riskant: Ausgestreamtes wird nach `nil`
  umgehängt, lokale Änderungen daran können verloren gehen (ST-2).
* `Net.PlayNear` filtert über die Charakterposition auf dem Server – passend zu einem Streaming-Radius.

## 14. Performance-Tipps

* **Vorladen:** Häufige Effekte beim Client-Start mit `Preload` vorwärmen – mit denselben Optionen wie später
  (`Scale`, `Seed`, `Palette`, `Quality`). Ein Pool-Treffer kostet nur ein Umhängen statt eines Neubaus.
* **Seeds und Cache:** Jeder neue `Seed`, jede neue `Palette`- oder `Scale`-Kombination ist eine eigene
  Kompilier-Variante (max. 64 im Cache, dann wird verworfen und neu kompiliert). Für Abwechslung eine kleine feste
  Menge verwenden, z. B. `Seed = math.random(1, 4)`, statt jedes Mal einen neuen Zufallswert.
* **Qualität:** Auf schwachen Geräten `SetQuality("Low")` (Mobile) oder dem Spieler eine Einstellung anbieten.
  In den Definitionen teure Schichten mit `minQuality` markieren.
* **Pooling ausnutzen:** Effekte nicht selbst klonen oder zerstören – `Play` und das automatische Ende genügen.
  `Destroy()` nur für echtes Abbrechen; `Stop()` lässt Partikel natürlich ausklingen.
* **Netzwerk:** Häufige, ersetzbare Effekte mit `Unreliable = true`; `PlayNear` statt `PlayAll`, wenn nur die
  Umgebung den Effekt sehen kann. Nachrichten bleiben klein (keine Paletten/Tabellen).
* **Nicht pro Frame abspielen:** Dauereffekte als Schleife (`Loop = true`) einmal starten statt jeden Frame neu.
* **Obergrenze setzen:** `AstraVFX.SetMaxActive(n)` begrenzt gleichzeitig spielende Effekte (Standard 64); auf
  schwachen Geräten niedriger wählen. Bei Überlauf weichen die ältesten nicht schleifenden Effekte sanft.
* Eine einzige RunService-Verbindung treibt alle Effekte; Part-Bewegungen laufen gesammelt über
  `WorldRoot:BulkMoveTo`. Teuer sind vor allem viele gleichzeitige Partikel, große transparente Flächen
  (Overdraw) und Lichter.

## 15. Fehlerbehebung

| Symptom | Ursache | Lösung |
|---|---|---|
| `AstraVFX.Play: unknown effect "X"` | Effekt nicht registriert / Tippfehler / Name ≠ id | `AstraVFX.GetNames()` ausgeben; liegt der Effekt in `AstraVFX.Effects`? Groß-/Kleinschreibung beachten. |
| `unknown effect` nur direkt nach dem Beitritt, später nicht | Client hat vor dem Ende der Erstreplikation nachgeschlagen | im LocalScript zuerst `if not game:IsLoaded() then game.Loaded:Wait() end` (§3.2) |
| `[AstraVFX] skipped effect …` in der Ausgabe | ungültige Definition im Effects-Ordner | Meldung lesen; mit `AstraVFX.Validate(value.Value)` die Diagnosen ansehen. |
| `AstraVFX.Register: effect "…" is invalid (n errors)` | Validierungsfehler | Diagnosen (Code + Pfad) korrigieren, siehe `docs/COMPONENTS_SPEC.md`. |
| `AstraVFX.Play: unknown option "position"` | Optionsnamen sind PascalCase | `Position`, `CFrame`, `Attach`, … |
| Clients sehen nichts nach `Net.PlayAll` | Client ruft `Net.Listen()` nicht auf; Effekt auf dem Client nicht registriert; Nachricht unzuverlässig vor `Listen` gesendet | `Net.Listen()` im LocalScript; `AstraVFX.Net.stats` prüfen (`ignored` steigt bei unbekannten Namen); Effects-Ordner muss in ReplicatedStorage liegen. |
| `Net.Play: option "Palette" cannot be replicated` | nicht serialisierbare Option an `Net` übergeben | nur `CFrame`, `Position`, `Attach`, `Scale`, `TimeScale`, `Seed`, `Quality`, `Unreliable` |
| Effekt erscheint am Weltursprung | weder `CFrame`/`Position` noch `Attach` angegeben | Position übergeben |
| Effekt folgt dem Ziel nicht | `Attach` nicht in der Welt (ausgestreamt, `Parent = nil`) oder `SetCFrame` aufgerufen | Ziel prüfen; `SetCFrame` beendet das Folgen |
| Kamera-Shake/Screen-Flash fehlen | auf dem Server abgespielt | Kamera-Komponenten wirken nur auf Clients (`Net` oder lokales `Play`) |
| `[AstraVFX] Play "X" refused: the limit of 64 active effects (AstraVFX.SetMaxActive) is filled by looping effects …` | die Obergrenze ist voll mit Schleifen-Effekten | Schleifen mit `handle:Stop()` beenden oder `SetMaxActive` erhöhen; `Play` gibt dann `nil` zurück |
| Ältere Effekte verschwinden vorzeitig (klingen aus) | Obergrenze aktiver Effekte erreicht, die ältesten nicht schleifenden werden gestoppt | weniger gleichzeitige Effekte oder `SetMaxActive` erhöhen |
| Erster Effekt ruckelt | Kompilieren + Bauen beim ersten `Play` | `Preload` mit denselben Optionen |
| Speicher/Instanzen wachsen | sehr viele verschiedene Seeds/Paletten/Skalen; endlose Schleifen nie gestoppt | feste Seed-Menge; `ActiveCount()` beobachten; Schleifen mit `Stop()` beenden |
| Partikel laufen in Pause weiter / verschwinden | Engine-Verhalten von `ParticleEmitter.TimeScale = 0` ungeprüft (U2) | in Studio prüfen (`docs/TESTING.md`), ggf. `Stop()` statt `Pause()` |
| Effekt nach Respawn verschwunden | `Parent = character` | Standard-`Parent` und `Attach` verwenden |
| `Quality` immer `Medium` in Studio | `"Auto"` liefert in Studio bewusst `Medium` | zum Testen `SetQuality("Low")`/`("High")` |

## 16. Grenzwerte auf einen Blick

| Wert | Grenze | Quelle |
|---|---|---|
| `Scale` (Play) | > 0, max. 50 | `Constants.MAX_SCALE` |
| `TimeScale` (Play/SetTimeScale) | ≥ 0, max. 10 | `Constants.MAX_TIME_SCALE` |
| `scale` / `timeScale` über `Net` (Client) | 0.05 … 20 / 0.05 … 10 | `Net.SCALE_*`, `Net.TIME_SCALE_*` |
| Effektname über `Net` | 1 … 100 Zeichen | `Net.MAX_NAME_LENGTH` |
| Unzuverlässige Nachricht | geschätzt ≤ 900 Bytes, sonst zuverlässig | `Net.UNRELIABLE_BUDGET` |
| Gleichzeitig spielende Effekte | Standard 64 (`SetMaxActive`, ≥ 1 oder `math.huge`) | `AstraVFX.DEFAULT_MAX_ACTIVE` |
| Kompilierte Varianten | 64 pro Maschine | `init.luau` (`MAX_CACHE`) |
| Freie Pool-Kopien | 2 pro Variante (Preload hebt an) | `Pool.DEFAULT_CAPACITY` |
| Frame-Schritt | dt auf 0 … 0.1 s begrenzt | `Scheduler.MAX_DT` |
| Effektdauer | max. 60 s | `Constants.MAX_DURATION` |
