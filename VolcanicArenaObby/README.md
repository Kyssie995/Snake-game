# 🌋 Volcanic Arena Obby

A stylized lava-arena obby for Roblox Studio with a **fully modular cartoon
death/reset animation** — no realistic gore, just comic-book red paint splats,
poof stars, smoke, camera shake and a boom.

The **entire map is built by script** when the server starts (spawn platform,
floating rock islands, obby jumps, moving platforms, checkpoints, lava ocean,
treasure platform, lighting and ambience), so setup is just: paste 5 scripts,
press Play.

---

## Folder structure

This is where every file in `src/` goes inside Roblox Studio
(the **Instance type matters** — Script vs LocalScript vs ModuleScript):

```
game
├── ServerScriptService
│   ├── MapBuilder            (Script)        ← src/ServerScriptService/MapBuilder.server.lua
│   ├── CheckpointService     (Script)        ← src/ServerScriptService/CheckpointService.server.lua
│   └── DeathHandler          (Script)        ← src/ServerScriptService/DeathHandler.server.lua
│
├── ReplicatedStorage
│   ├── Modules               (Folder)
│   │   ├── ObbyConfig        (ModuleScript)  ← src/ReplicatedStorage/Modules/ObbyConfig.lua
│   │   └── CartoonBurst      (ModuleScript)  ← src/ReplicatedStorage/Modules/CartoonBurst.lua
│   ├── Remotes               (Folder)        ← created automatically by DeathHandler
│   │   ├── PlayDeathFX       (RemoteEvent)   ← auto-created
│   │   ├── RequestReset      (RemoteEvent)   ← auto-created
│   │   └── CheckpointReached (RemoteEvent)   ← auto-created
│   └── Assets                (Folder)        ← OPTIONAL, made by you
│       └── SplatMeshes       (Folder)        ← your custom splat MeshParts (see below)
│
└── StarterPlayer
    └── StarterPlayerScripts
        ├── ResetButtonHook    (LocalScript)  ← src/StarterPlayer/StarterPlayerScripts/ResetButtonHook.client.lua
        └── DeathEffectsClient (LocalScript)  ← src/StarterPlayer/StarterPlayerScripts/DeathEffectsClient.client.lua
```

---

## Step-by-step Roblox Studio setup

1. **New place** — open Roblox Studio → *New* → **Baseplate**. Delete the
   `Baseplate` part from Workspace (the map builds its own floor of lava).

2. **ReplicatedStorage modules**
   1. In the Explorer, right-click **ReplicatedStorage** → *Insert Object* → **Folder**, name it `Modules`.
   2. Right-click `Modules` → *Insert Object* → **ModuleScript**, name it `ObbyConfig`,
      and paste in the contents of `src/ReplicatedStorage/Modules/ObbyConfig.lua`.
   3. Add a second **ModuleScript** named `CartoonBurst` and paste in
      `src/ReplicatedStorage/Modules/CartoonBurst.lua`.

3. **Server scripts** — right-click **ServerScriptService** → *Insert Object* →
   **Script** three times, named `MapBuilder`, `CheckpointService` and
   `DeathHandler`, pasting in the matching files from `src/ServerScriptService/`.

4. **Client scripts** — in **StarterPlayer → StarterPlayerScripts**, insert two
   **LocalScripts** named `ResetButtonHook` and `DeathEffectsClient`, pasting in
   the matching files from `src/StarterPlayer/StarterPlayerScripts/`.

5. **Sounds (optional but recommended)** — open `ObbyConfig` and fill in the
   empty sound IDs (`Boom`, `VolcanoLoop`, `Victory`). In the Toolbox choose
   *Audio*, tick **"Roblox created"** (those are free to use in any experience),
   search e.g. `cartoon explosion`, right-click a result → *Copy Asset ID*, and
   paste it as `"rbxassetid://<id>"`. The splat/pop/checkpoint sounds already
   use built-in `rbxasset://` files and work with zero setup.

6. **Press Play.** The volcanic arena builds itself in ~1 second (look for
   `[VolcanicArena] Map built ...` in the Output window). Jump across the
   islands, touch a blue checkpoint pad, then jump into the lava — you should
   freeze, shake, puff up, pop red splats, **burst** with smoke and camera
   shake, and respawn on your checkpoint.

> **Rojo users:** `default.project.json` maps `src/` onto the services above —
> just run `rojo serve` and connect from Studio instead of copy-pasting.

---

## Custom splat MeshParts (optional)

Out of the box the burst uses stylized spheres, so everything works with no
assets. To use your own comic splat meshes:

1. In **ReplicatedStorage**, create a Folder `Assets`, and inside it a Folder
   `SplatMeshes`.
2. Insert MeshParts into `SplatMeshes`:
   - *Home tab → Import 3D* to bring in your own `.fbx`/`.obj` splat models, **or**
   - insert a **MeshPart** and set its `MeshId` to any stylized blob/splat mesh
     you own in the *Properties* panel.
3. Style rules that keep it cartoon-safe (matching what the code does):
   - Set **Material** = `SmoothPlastic` (the code enforces this on clones).
   - Colors are overridden to the two config reds, so any mesh color works.
   - Good shapes: paint blobs, stars, lightning bolts, "POW" text meshes,
     droplets. Avoid anything resembling anatomy — this system is strictly
     stylized paint.
4. That's it — `CartoonBurst` automatically clones random MeshParts from that
   folder for both the pop-out splats and the flying burst chunks. If the
   folder is missing or empty, it silently falls back to generated spheres.

---

## How the pieces talk to each other

```
Player touches Lava ──────────────┐
Player clicks Reset (Esc menu) ───┤   RequestReset (RemoteEvent, client → server)
Humanoid dies some other way ─────┤
                                  ▼
                     DeathHandler.killPlayer()          [server]
                                  ▼
                     CartoonBurst.Play(character)       [server module]
                       1. freeze character
                       2. shake + inflate (R15)
                       3. pop red splat MeshParts
                       4. cartoon BURST (chunks/stars/smoke/paint)
                       5. PlayDeathFX (RemoteEvent, server → all clients)
                                  ▼                        ▼
                       6. respawn callback        DeathEffectsClient [client]
                                  ▼                 camera shake, red flash,
                     player:LoadCharacter()         distance-based boom
                                  ▼
                     CheckpointService moves the new
                     character to the last claimed pad
                     (CheckpointReached RemoteEvent → toast UI)
```

### RemoteEvents (all auto-created in `ReplicatedStorage/Remotes`)

| RemoteEvent         | Direction        | Purpose                                        |
|---------------------|------------------|------------------------------------------------|
| `RequestReset`      | client → server  | Custom reset button asks for a cartoon death (server rate-limits it) |
| `PlayDeathFX`       | server → clients | "A burst happened at position X" → camera shake / flash / boom |
| `CheckpointReached` | server → client  | Progress ping for the "CHECKPOINT!" toast       |

### Checkpoint system

- A checkpoint is **any BasePart** with the CollectionService tag `Checkpoint`
  and a number attribute `Order` (1, 2, 3, …). `MapBuilder` places them every
  third island; add your own anywhere with the Tag Editor + Attributes panel.
- Progress only moves **forward** (touching an older pad does nothing) and is
  stored as the `CheckpointOrder` attribute on the Player.
- Lava is any BasePart tagged `Lava` — tag extra kill bricks with it and they
  instantly get the full cartoon-death treatment.

---

## Reusing the death animation in other maps

The animation is one self-contained ModuleScript. In any other place:

1. Copy `Modules/ObbyConfig` and `Modules/CartoonBurst` into ReplicatedStorage.
2. Copy `DeathHandler` into ServerScriptService (it creates the remotes) and
   the two LocalScripts into StarterPlayerScripts.
3. Trigger it from any server code:

```lua
local CartoonBurst = require(game.ReplicatedStorage.Modules.CartoonBurst)

CartoonBurst.Play(somePlayer.Character, function()
    somePlayer:LoadCharacter() -- or your own respawn logic
end)
```

No map dependencies — `MapBuilder` and `CheckpointService` are optional extras.

## Tuning

Every timing, count, colour and sound lives in `ObbyConfig.lua`:
shake length/intensity, inflate scale, splat/chunk/star counts, respawn delay,
camera-shake strength, island rise/gap sizes, moving-platform speed, and all
sound IDs. Tweak there; no other file needs editing.

## Content-safety notes

- The death effect is deliberately non-realistic: characters vanish in a puff
  and are replaced by plain red **paint** spheres/meshes, white poof stars and
  grey smoke. There are no gore textures, body-part meshes, or damage decals,
  and nothing in the code references anatomy.
- Keep any custom `SplatMeshes` you add in the same spirit (blobs, stars,
  comic shapes) to stay within Roblox community standards.
