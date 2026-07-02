# ⚔️ Soulbound Battlegrounds

An original anime-battlegrounds game for Roblox. Players are **Spirit Hunters** who awaken unique **Soul Weapons**, chain sword combos and Soul Dashes through a dark spirit city, and unleash cinematic **Final Release** transformations. Original IP — no copyrighted anime names, characters, moves, or assets.

**Status:** Alpha in development (2–3 month scope, see [docs/Roadmap.md](docs/Roadmap.md))

## What's in this repo

| Path | Contents |
|---|---|
| `docs/GameDesignDocument.md` | Full alpha GDD: combat, weapons, progression, Soul Clash, Spirit Echo, map, monetization |
| `docs/StudioFolderStructure.md` | The Roblox Studio instance tree and conventions |
| `docs/Roadmap.md` | Week-by-week 3-month alpha plan |
| `docs/TestingChecklist.md` | Pre-release QA checklist (incl. exploit tests) |
| `default.project.json` | [Rojo](https://rojo.space) project mapping |
| `src/ReplicatedStorage/Modules/` | Shared core: Net, CombatConstants, Hitbox, Cooldowns, Stun, Ragdoll, StatusEffects, VFXUtil, WeaponConfigs |
| `src/ServerScriptService/Services/` | Server: Data, Progression, Combat, Ability, SoulClash, SpiritEcho, Destruction, TrainingDummy, Admin |
| `src/ServerScriptService/Abilities/` | Weapon movesets — **Ashfang and Frostveil are complete**; Voidneedle and Thundercrown are working templates |
| `src/StarterPlayer/.../Controllers/` | Client: Input, CombatClient (VFX), Camera, UI |

## Getting started

1. Install [Rojo](https://rojo.space/docs/) (`aftman add rojo-rbx/rojo` or the VS Code extension).
2. `rojo serve` in this folder, then connect from Roblox Studio with the Rojo plugin.
3. In Studio, build/import the map into `Workspace` and:
   - Tag breakable parts with CollectionService tag **`Destructible`**
   - Tag dummy rigs (Models with Humanoids) with **`TrainingDummy`** (optional attribute `DummyMode = "Blocking"`)
   - Add SpawnLocations inside your spawn zones
4. Enable **Studio Access to API Services** (Game Settings → Security) so DataStores work.
5. Press Play. In Studio you're automatically an admin: chat `;xp 5000`, `;level 35`, `;energy`, `;weapon Frostveil`, `;hitboxdebug` etc. (see `AdminService.lua`).

## Controls (PC)

| Input | Action |
|---|---|
| LMB (tap) | M1 combo — 4th hit ragdolls; hold **Space** on finisher = air launch |
| LMB (hold 0.35s+) | Charged heavy — guard break, **Soul Clash** eligible |
| F | Block |
| Q | Soul Dash (i-frames; perfectly-timed = refund + punish window) |
| 1–4 | Soul Weapon moves |
| G | Final Release (level 35 + full Soul Energy) |
| E | Mash during Soul Clash / absorb Spirit Echoes |
| M | Weapon menu |

## Architecture in one paragraph

The client only ever sends *intents* (`CombatRequest`, `AbilityRequest`, `ClashInput`); the server validates state, cooldowns, ranges, and rate limits, resolves all hits via spatial-query hitboxes, and owns HP/energy/XP/data. Visuals replicate as tiny `{fx = "Name", ...}` payloads on one `CombatFX` remote, played back locally by `CombatClient`. Each weapon is one config module (numbers) + one ability module (behavior) implementing a fixed interface — weapon #5 requires zero core changes. See `Abilities/_WeaponTemplate.lua` for the how-to.
