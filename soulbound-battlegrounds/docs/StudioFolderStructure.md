# Roblox Studio Folder Structure

This maps 1:1 to `default.project.json` (Rojo). If you build directly in Studio without Rojo, recreate this tree by hand and paste the module sources in.

```
ReplicatedStorage
├── Remotes                    (Folder — created at runtime by Net module)
│   ├── AbilityRequest         (RemoteEvent)  client → server: ability keypress intents
│   ├── CombatRequest          (RemoteEvent)  client → server: M1 / block / dash / heavy intents
│   ├── ClashInput             (RemoteEvent)  client → server: mash presses during Soul Clash
│   ├── CombatFX               (RemoteEvent)  server → clients: replicated VFX/SFX/hit-stop cues
│   ├── HUDUpdate              (RemoteEvent)  server → client: HP/energy/cooldown/level pushes
│   ├── ClashState             (RemoteEvent)  server → clients: clash start/progress/resolve
│   └── ShopRequest            (RemoteFunction) client → server: weapon purchase / equip
├── Modules                    (shared ModuleScripts)
│   ├── Net                    remote creation + typed accessors + client rate hints
│   ├── CombatConstants        every tunable number in the game (single balance file)
│   ├── HitboxModule           spatial-query hitboxes with debug view
│   ├── CooldownManager        per-player keyed cooldowns
│   ├── StunManager            hitstun / guard-break / ragdoll states + anti-infinite
│   ├── RagdollModule          ragdoll on/off + knockback impulses
│   ├── StatusEffects          Burn / Chill / Vulnerable / Slow tickers
│   ├── VFXUtil                emit helpers, trails, shockwaves, hit-stop, camera shake spec
│   └── WeaponConfigs          (Folder)
│       ├── init               index + validation of all weapon configs
│       ├── Ashfang
│       ├── Frostveil
│       ├── Voidneedle
│       └── Thundercrown
├── Assets                     (Folder) weapon models, echo prefab, debris prefabs
├── VFX                        (Folder) particle prefabs per weapon color + clash orb
└── Animations                 (Folder) Animation instances (id-swappable)

ServerScriptService
├── Main                       (Script) bootstraps all services in dependency order
├── Services                   (Folder of ModuleScripts)
│   ├── DataService            session-locked DataStore profiles
│   ├── ProgressionService     XP, levels, unlock gating, tokens
│   ├── CombatService          M1s, block, dash, guard break, damage pipeline
│   ├── AbilityService         validates + routes ability intents to weapon modules
│   ├── SoulClashService       clash eligibility, lock, mash duel, resolve
│   ├── SpiritEchoService      death echoes + absorb rewards
│   ├── DestructionService     weak walls, props, debris lifecycle
│   ├── TrainingDummyService   dummy spawn/reset/XP-capped rewards
│   └── AdminService           dev/test chat commands (whitelisted user ids)
└── Abilities                  (Folder of ModuleScripts, one per weapon)
    ├── Ashfang                COMPLETE reference implementation
    ├── Frostveil              template (moves stubbed to pattern)
    ├── Voidneedle             template
    └── Thundercrown           template

StarterPlayer
└── StarterPlayerScripts
    ├── ClientMain             (LocalScript) bootstraps client controllers
    └── Controllers            (Folder of ModuleScripts)
        ├── InputController    keyboard/mouse/touch → intent remotes
        ├── CombatClient       prediction VFX, hit-stop, clash mash UI hooks
        ├── CameraController   shake, ultimate push-in, clash framing
        └── UIController       HUD, weapon menu, level bar, clash prompt

StarterGui
├── MainHUD                    (ScreenGui) HP / energy ring / hotbar / level bar
├── WeaponMenu                 (ScreenGui) selection, purchase, unlock states
└── LevelProgressUI            (ScreenGui) per-weapon progress + aura tier display

Workspace
├── Map                        Duskmarket geometry
├── SpawnZones                 SpiritGate_A, SpiritGate_B (SpawnLocations + protection parts)
├── Destructibles              tagged weak walls + props (CollectionService tag: "Destructible")
└── TrainingDummies            tagged dummy rigs (tag: "TrainingDummy")
```

**Conventions**

- Everything gameplay-tunable lives in `CombatConstants` or a `WeaponConfigs/*` module — never hardcode numbers in services.
- Server → client visuals always go through the single `CombatFX` remote with a small payload `{fx = "HitSpark", pos = ..., color = ...}`; clients look effects up locally. Never replicate instances for VFX.
- Tag-driven world objects (`Destructible`, `TrainingDummy`) via CollectionService, so map artists just tag parts and services find them.
