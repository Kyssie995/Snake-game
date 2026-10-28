# Beispiele – ASTRA VFX im eigenen Spiel

Dieser Ordner enthält ein minimales, lauffähiges Spiel-Setup für die ASTRA-Laufzeit (`AstraVFX`) – **ohne** das
Studio-Plugin. Die vollständige API-Referenz steht in [`docs/RUNTIME_API.md`](../docs/RUNTIME_API.md).

```
examples/
  default.project.json                         Rojo-Projekt: komplettes Demo-Place (DataModel)
  ServerScriptService/AstraVFXDemo.server.luau Server: Net.Init, alle 4 s VioletImpact an alle Clients, eigener Schadens-Timer
  StarterPlayerScripts/AstraVFXClient.client.luau
                                               Client: Net.Listen, Taste F = FireExplosion am Mauspunkt,
                                               "Impact"-Ereignis = Kamera-FOV-Kick, Taste G = VioletImpact am Charakter
  Effects/FireExplosion.vfx.json               kompakter Demo-Effekt (Blitz, Feuerball, Funken, Druckwelle, Rauch, Licht)
```

Zusätzlich benutzt das Place `effects/VioletImpact.vfx.json` (das Konzeptbeispiel aus dem Projektauftrag, mit
`Core/Migration` auf Schema 1 gebracht) und die Laufzeit aus `src/Runtime`.

## Fertiges Demo-Place

```bash
# im Ordner astra-vfx-studio/
rojo build examples/default.project.json -o build/AstraVFX-Examples.rbxl
```

`build/AstraVFX-Examples.rbxl` in Roblox Studio öffnen – fertig. Inhalt:

| Ort | Inhalt |
|---|---|
| `ReplicatedStorage.AstraVFX` | Laufzeit (`src/Runtime`) |
| `ReplicatedStorage.AstraVFX.Effects` | `FireExplosion`, `VioletImpact` als StringValues mit dem unveränderten JSON-Text (Rojo-`syncRules` `"use": "text"`) – werden beim ersten Zugriff automatisch registriert |
| `ServerScriptService.AstraVFXDemo` | Server-Skript |
| `StarterPlayer.StarterPlayerScripts.AstraVFXClient` | Client-Skript |
| `Workspace` | Baseplate, SpawnLocation, schwebender Neon-Würfel `VFXTarget` (24 Studs vor dem Spawn) |

Live-Sync statt Datei: `rojo serve examples/default.project.json` und in Studio mit dem Rojo-Plugin verbinden.

### Ausprobieren

1. **Play** (F5). Alle 4 Sekunden erscheint am `VFXTarget` die violette Kugel (`VioletImpact`) – gesendet vom
   Server über `AstraVFX.Net.PlayAll`, gerendert vom Client.
2. Zum Würfel laufen: 0,6 s nach jedem Effektstart zieht der **Server** allen Charakteren im Umkreis von 10 Studs
   10 Lebenspunkte ab – mit seiner eigenen Uhr, unabhängig davon, ob oder wie der Client den Effekt zeigt.
3. Mit der Maus auf den Boden zeigen und **F** drücken: `FireExplosion` am Mauspunkt (nur lokal sichtbar). Beim
   Marker-Ereignis `"Impact"` (0,12 s) springt das Sichtfeld kurz auf und federt zurück.
4. **G** drücken: `VioletImpact` (40 % Größe) erscheint 6 Studs vor dem Charakter und **folgt** ihm (`Attach` +
   `Offset`). Wird der Charakter währenddessen entfernt (Respawn), bleibt der Effekt an der letzten Stelle und
   spielt zu Ende.
5. Für echtes Server/Client-Verhalten: *Test → Clients and Servers → Start* mit 2 Spielern. Beide sehen die
   Server-Effekte; F/G sieht nur der Spieler, der drückt.

Die genaue Prüfliste mit erwarteten Ergebnissen steht in [`docs/TESTING.md`](../docs/TESTING.md) (Phase 6).

## Was die Skripte zeigen

* **Server-autoritatives Gameplay, kosmetische Clients.** Der Server baut keine Effekt-Instanzen; er schickt nur
  Name und CFrame. Schaden und Timing entscheidet er selbst (`task.delay(IMPACT_DELAY, applyDamage, …)`), nie ein
  Effekt-Ereignis.
* **Kein Client → Server-Pfad.** `AstraVFX.Net` hat keinen. Effekte, die ein Client für sich abspielt (Taste F),
  sieht niemand sonst. Soll eine Spieleraktion für alle sichtbar sein, schickt das Spiel ein eigenes, validiertes
  Remote an den Server, und der Server ruft `Net.PlayAll`/`PlayNear` auf.
* **Ereignisse:** `handle.Event:Connect(function(name) … end)` (gleichwertig: Play-Option `OnEvent`).
* **Erstreplikation abwarten:** `if not game:IsLoaded() then game.Loaded:Wait() end` vor dem ersten Zugriff, damit
  `ReplicatedStorage.AstraVFX.Effects` auf dem Client vollständig ist.
* **Vorladen:** `AstraVFX.Preload("FireExplosion", { Count = 2 })` baut beim Start zwei Kopien in den Pool, damit
  der erste Tastendruck nicht ruckelt.
* **Fehlertolerantes Abspielen:** `AstraVFX.TryPlay` gibt `nil, Meldung` zurück statt zu werfen.

## In ein eigenes Spiel übernehmen

1. `rojo build runtime.project.json -o build/AstraVFX.rbxm` und das Modell als `ReplicatedStorage.AstraVFX`
   einfügen (oder per Rojo synchronisieren).
2. Effekte als StringValues (JSON-Text) oder ModuleScripts in `ReplicatedStorage.AstraVFX.Effects` legen. Mit Rojo
   genügt die `syncRules`-Regel aus `examples/default.project.json` für `*.vfx.json`.
3. Die beiden Skripte kopieren und `EFFECT`/`EXPLOSION`/`ATTACHED` auf die eigenen Effektnamen ändern.

Der Ausdruck `require(ReplicatedStorage:WaitForChild("AstraVFX")) :: any` enthält den Cast `:: any` nur für die
statische Typprüfung (`astra-analyze` kann Requires über Services nicht verfolgen). In Roblox funktioniert er
unverändert; ohne `--!strict` kann man ihn weglassen.

`FireExplosion` ist hier ein **kompakter Demo-Effekt** (`id` `fire-explosion-demo`). Die ausführlichere
Preset-Version aus der Effektbibliothek (`src/Presets`) kann ihn ersetzen – gleicher Name, einfach die Datei
austauschen; das Client-Skript braucht nur einen Marker mit `"event": "Impact"`.

## Automatisch geprüft

| Prüfung | Befehl |
|---|---|
| Typen der Beispielskripte (strict, gegen die Roblox-API 0.745) | `/root/tools/bin/astra-analyze --defs /root/tools/ref/globalTypes.d.luau --project examples/default.project.json examples/ServerScriptService examples/StarterPlayerScripts` |
| Place baut | `rojo build examples/default.project.json -o build/AstraVFX-Examples.rbxl` |
| Verhalten mit Engine-Fakes (Lune) | `lune run tests/lune/run.luau -- Examples` (`tests/specs/Examples.spec.luau`) |

Die Lune-Spec lädt das Place wie Rojo, registriert beide Effekte, lässt `FireExplosion` auf allen
Qualitätsstufen durchlaufen und führt **beide Skripte** gegen kleine Fakes aus (Players, UserInputService,
TweenService, Raycast, `Humanoid:TakeDamage`, `task.wait`/`task.delay`, Remotes): Nachricht des Servers, eigener
Schadens-Timer und -Radius, Raycast-Filter des Clients, Effektposition, FOV-Kick beim `"Impact"`, Attach-Verfolgung,
Rückgabe in den Pool. Sie beweist **nicht** Darstellung, echte Eingaben oder echtes Netzwerk – das deckt die
manuelle Studio-Prüfung in `docs/TESTING.md` ab.
