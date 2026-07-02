# Soulbound Battlegrounds — Game Design Document (Alpha)

**Version:** Alpha 0.1 · **Target:** 2–3 month alpha, solo dev or small team · **Platform:** Roblox (PC first, mobile in month 3)

---

## 1. High Concept

Players are **Spirit Hunters** — warriors who awaken a unique **Soul Weapon** bound to their spirit. They fight in a dark spiritual city, chaining sword combos, Soul Dashes, and screen-shaking ultimates called **Final Releases**. The game is a fast, cinematic PvP battleground with fruit-game-style long-term progression: weapons level up by being used, moves unlock over time, and new weapons are earned with **Spirit Tokens** — never gambling for power.

**One-line pitch:** *Awaken your Soul Weapon, master its Releases, and clash blades in a neon spirit city.*

### Design Pillars

1. **Every fight is a highlight clip.** Ragdolls, wall destruction, Soul Clashes, and cinematic ultimates make ordinary fights feel filmable.
2. **Skill beats stats.** Blocking, perfect dodges, and guard breaks decide fights. Levels unlock *options*, not raw stat superiority.
3. **Fair power, flashy cosmetics.** All combat power is earnable at a predictable rate. RNG is reserved for cosmetics (post-alpha).
4. **Small scope, high polish.** One map, four weapons, one game mode — all finished, juicy, and balanced.

---

## 2. Fiction & World

Long ago, the veil between the living world and the **Ashen Realm** cracked. Spirits called **Wraiths** slip through, and the **Spirit Hunter Order** stands against them. Every Hunter's soul manifests as a weapon spirit. A rival faction, the **Lightborn Covenant**, channels pure spirit light through relic bows and blades and believes Hunters are corrupted. (Factions are *flavor only* in alpha — banners, spawn zones, NPC dialogue — no faction mechanics yet.)

**The map — Duskmarket:** a spiritual market district frozen at eternal dusk. Broken towers, glowing rooftop shrines, alleyways lit by soul-lanterns, and cracked concrete leaking cyan spirit light. Two **Spirit Gates** (giant torii-like arches) mark faction spawn zones.

### Terminology (original, safe)

| Concept | Name in game |
|---|---|
| Player class | Spirit Hunter |
| Weapon | Soul Weapon |
| Stage 1 awakening | **First Release** |
| Ultimate awakening | **Final Release** |
| Teleport-dash | **Soul Dash** |
| Energy overdrive meter state | **Soul Surge** |
| Enemy spirits | Wraiths |
| Rival faction | Lightborn |
| XP currency | Soul XP |
| Unlock currency | Spirit Tokens |

---

## 3. Core Combat

Server-authoritative. Client sends *intents* (RemoteEvents); server validates, resolves hits, applies damage/stun/knockback, and replicates VFX.

### 3.1 Basic kit (identical for all weapons)

| Action | Input (PC) | Notes |
|---|---|---|
| M1 combo | LMB ×4 | 3 quick slashes + finisher. Finisher ragdolls + knocks back. Hold W+M1 finisher = forward launch; hold Space+M1 finisher = **air launch** (enables air combos). |
| Block | Hold F | Reduces damage 100% vs M1s, 50% vs abilities. Block HP breaks under pressure → guard break stun. |
| Guard break | Hold M1 (charged heavy) | Breaks block, ragdolls blocking targets. Slow windup — reactable. Heavy attacks trigger **Soul Clash** checks. |
| Dodge / Soul Dash | Q (+direction) | Short i-frame dash, 2s cooldown. **Perfect dodge:** dodging within 0.25s of an incoming hit refunds the cooldown, slows time for you locally (0.3s), and marks attacker briefly vulnerable (1.2s, +20% damage taken). |
| Sprint / Soul-run | Hold Shift | Faster movement, spirit-trail VFX. |
| Abilities | 1 / 2 / 3 / 4 | Weapon moves, cooldown-based. |
| Ultimate — Final Release | G (when charged & unlocked) | Transformation. See §6. |

### 3.2 Damage, stun, ragdoll

- **HP:** 100. Respawn: 3.5s. Spawn protection: 5s or until first attack input.
- **Stun types:** *hitstun* (0.35s per M1, victim can't attack, can dash-cancel out after M1 #2 at cooldown cost), *guard-break stun* (1.5s, full lock), *ragdoll* (physics knockback; recovery 1.2s after landing).
- **True-combo cap:** stun system enforces max ~4.5s of continuous stun, then grants 1s of knockback resistance (anti-infinite).
- **Knockback:** finisher/ability knockback uses BodyVelocity-style impulse + ragdoll; players smashing into **Destructibles** break them (satisfying + comedic).
- **Hit detection:** server-side spatial query hitboxes (`GetPartBoundsInBox`) fired on animation keyframes, with lag-compensated leniency (small box inflation up to ping-scaled cap).

### 3.3 Meters

- **Soul Energy (0–100):** builds from dealing damage (+3/hit), taking damage (+2/hit), and slowly over time in combat (+1/s). At 100 you may activate Final Release (if unlocked). Halved on death.
- **Block HP (0–60):** blocked M1 = −8, blocked ability = −20, charged heavy = instant break. Regenerates 10/s after 2s of not blocking.

---

## 4. Soul Weapon System

Four alpha weapons. Each has: color identity, idle stance, 4 moves (unlock at weapon levels 1/5/15/25), Final Release (level 35), and aura tiers (10/20/30/40/50).

### A. Ashfang — the Fire Wolf Blade 🔥
- **Identity:** ember orange/red. Aggressive brawler; rewards staying in melee range. Applies **Burn** (2 dmg/s, 3s, non-stacking refresh).
- **Moves:**
  - **Ember Slash** (Lv1, 6s CD): fast 270° arcing slash, mid range, applies Burn. Combo-extender.
  - **Wolf Rush** (Lv5, 10s CD): dash forward as a flame-wolf silhouette; first target hit gets 3 rapid bites then a knockback slash.
  - **Flame Counter** (Lv15, 14s CD): 0.6s parry stance. If struck: negate hit, erupt in fire, ragdoll attacker, apply Burn.
  - **Burning Fang** (Lv25, 18s CD): charged heavy overhead slam; ground fire cone; guard-breaks; **Soul Clash eligible**.
- **Final Release — Inferno Pack Release** (Lv35): blade splits into twin fire fangs; 2 spectral wolves orbit and auto-lunge at nearby enemies (weak damage, applies Burn); M1 speed +20%; Wolf Rush cooldown halved. 20s duration, 90s cooldown.

### B. Frostveil — the Ice Mirror Katana ❄️
- **Identity:** pale cyan/white. Zoner/controller; punishes approaches. Applies **Chill** stacks (3 stacks = 1s freeze).
- **Moves:** **Ice Cut** (Lv1) mid-range ice wave projectile · **Frozen Step** (Lv5) dash that leaves a freezing trail · **Mirror Trap** (Lv15) place an invisible mirror that freezes the first enemy to touch it · **Crystal Burst** (Lv25) AoE self-burst, guard-breaks, Soul Clash eligible.
- **Final Release — Winter Domain Release:** 30-stud snow dome slows enemies 25% inside; user's Chill applies double stacks; icy mirror clones flicker at the dome edge. 18s / 90s.

### C. Voidneedle — the Shadow Rapier 🌑
- **Identity:** violet/black. Assassin; low HP-per-trade but high burst and mobility. Bonus damage from behind (+25%).
- **Moves:** **Shadow Pierce** (Lv1) lunging thrust with brief hit-teleport through the target · **Vanish Step** (Lv5) short invisibility + next M1 bonus · **Dark Thread** (Lv15) tether that pulls the victim to you after 1s unless they dash-cancel it · **Backstab Rift** (Lv25) teleport behind target in 25 studs, heavy stab, Soul Clash eligible.
- **Final Release — Eclipse Release:** the arena dims for the user's victims; user gains ghost-trail afterimages, Vanish Step becomes 2-charge, backstab bonus +50%. 15s / 90s.

### D. Thundercrown — the Lightning Greatsword ⚡
- **Identity:** gold/electric blue. Slow, huge damage, stuns. M1s slower (-15% speed) but +30% damage and larger hitboxes.
- **Moves:** **Thunder Cleave** (Lv1) big vertical bolt-slash, small AoE shock · **Storm Leap** (Lv5) jump + crashing AoE landing that pops enemies airborne · **Static Field** (Lv15) 12-stud field for 4s; enemies inside get micro-stunned every 1s · **Crown Breaker** (Lv25) massive charged horizontal cleave, longest windup in the game, guard-breaks, ragdolls through walls (breaks destructibles), Soul Clash eligible.
- **Final Release — Tempest King Release:** a storm crown appears; every 3rd M1 calls a lightning strike; Storm Leap gains double distance; nearby destructibles arc with chain lightning. 20s / 90s.

**Weapon acquisition:** new players pick **Ashfang** free. Other weapons cost **Spirit Tokens** (earned ~1 per 10 min of active play + match bonuses): Frostveil 25, Voidneedle 40, Thundercrown 40. No paid weapons.

---

## 5. Progression

- **Soul XP** per weapon (the *equipped* weapon earns XP): damage dealt (1 XP / 2 dmg), kill (+50), assist (+20), Spirit Echo absorb (+15), training dummies (25% rate, capped 500 XP/day).
- **Weapon level 1→50.** Curve: `XPToNext(level) = 100 + (level^1.8 * 12)` (~40k total to 50; ≈ 20–25 active hours per weapon).
- **Unlocks:** moves at 1/5/15/25 · Final Release at 35 · aura cosmetic tiers at 10/20/30/40/50 (particle density/color evolves; pure flex).
- **Player level** = sum of weapon levels (matchmaking/leaderboard flavor only in alpha).
- **No stat scaling with level.** A level-50 Ashfang does the same damage per move as a level-25 one — it just has the full kit and better-looking aura.

---

## 6. Final Release (Transformation) Flow

1. Soul Energy = 100, press **G** → server validates (unlocked? energy? not stunned? off cooldown?).
2. **Cinematic activation (1.5s):** user is invulnerable + locked; camera pushes in + shakes; screen-space shockwave; music sting; weapon model morphs; aura ignites; nearby loose props get shoved outward.
3. **Buff window (15–20s):** per-weapon moveset modifiers (see §4), unique aura + trail, HUD timer ring.
4. **End:** aura collapses inward, brief 10% movement slow for 2s (vulnerability window = counterplay), 90s cooldown, Soul Energy → 0.

Ultimate activations are **Soul Clash eligible** for their first strike.

---

## 7. Signature Mechanic: Soul Clash ⚔️

When two **clash-eligible** attacks (charged heavies, Lv25 moves, Final Release first-strikes) connect with each other's owners within a 0.25s window and 12 studs:

1. Both players lock in place facing each other, weapons grinding; energy collision VFX (both weapons' colors mixing); camera auto-frames both.
2. **2.0s mash duel:** both players mash the prompted key (E). Mash counts are server-tallied (rate-capped to 12 presses/s to stop autoclickers).
3. **Winner** (≥15% more presses): loser is blasted backward 40 studs, ragdolled, takes the original attack's damage +20%. **Tie:** both explode backward 25 studs, no damage, mutual ragdoll.
4. Per-player Soul Clash cooldown: 20s (attacks land normally during cooldown — no clash spam loops).

Design intent: the "anime beam struggle" moment. Loud, readable, clip-worthy, and rare enough to stay special.

## 8. Second Unique Mechanic: Spirit Echo 👻

On death, a kneeling glowing silhouette (the victim's weapon color) remains for **10s**. Any *other* player can hold E (1s) to absorb it:

- +15 Soul XP, +10 Soul Energy, and a whisper line hinting the victim's weapon ("The echo smells of embers…").
- One absorb per echo; the killer's absorb grants +5 bonus XP (finisher reward).

Cheap to build (one prefab + ProximityPrompt), adds ritual and battlefield storytelling.

---

## 9. Map: Duskmarket (single alpha map)

- **Size:** ~350×350 studs, medium density.
- **Zones:** central market plaza (main PvP pit) · rooftop ring (verticality, Soul Dash routes) · alley maze (assassin territory) · two Spirit Gate spawn zones (spawn protection, no damage in/out) · **training yard** (6 dummies: static, blocking, moving) · **progression hub** (weapon vendor NPC, level boards, cosmetics placeholder shop).
- **Destructibles:** crate/stall/lantern props (break on any knockback impact) and 20–30 tagged **weak walls** (break when a ragdolled player or heavy ability hits them; debris parts fly, fade after 8s, respawn after 60s). Destruction is cosmetic-physical only — no permanent map changes.
- **Atmosphere:** eternal dusk skybox, cyan crack-glow decals, floating spirit motes (global particle emitter), soul-lanterns with point lights, distant Wraith howls (ambient SFX).

---

## 10. Visual & Audio Identity

- **Style:** stylized/anime, not realistic. High-contrast dark environment so weapon VFX pop.
- **Color language:** Ashfang orange · Frostveil cyan · Voidneedle violet · Thundercrown gold. Every trail, hit spark, aura, and UI accent respects the owner's color.
- **VFX kit (alpha):** sword trails (Trail instances), hit sparks + hit-stop (0.06s freeze on M1 hits), ground crack decals, aura particle rigs (3 tiers), ultimate shockwave ring, Soul Clash collision orb.
- **UI:** clean flat anime UI — HP bar with spirit-flame edge, Soul Energy ring around crosshair-dot, ability hotbar with radial cooldowns, weapon level bar, minimal damage numbers (toggleable).
- **Audio:** metallic clash tones per weapon material, whoosh layers on dashes, per-weapon ultimate music sting (3–5s), low ambient drone in map.

---

## 11. Monetization (placeholders only in alpha)

Shop UI exists with "Coming Soon" tabs: sword skins, aura colors, kill effects, emotes, intro animations. Private servers enabled (Roblox native). **Nothing paid affects combat.** Spirit Tokens are *not* purchasable in alpha (evaluate post-alpha; if sold, weapon prices stay low enough that playing remains the normal path).

---

## 12. Technical Architecture Summary

- **Server-authoritative combat.** Client = input + prediction VFX only. All damage, cooldowns, stuns, energy, and XP live on the server.
- **Anti-exploit:** server validates cooldowns, ranges, states, and input rates; remotes are rate-limited; clash mash is rate-capped; teleport moves check server-side distance; NaN/oversized vector guards on all remote args.
- **Data:** ProfileService-style session-locked DataStore wrapper saving XP/levels per weapon, unlocked weapons, equipped weapon, tokens, settings.
- **Modularity:** every weapon = 1 config module + 1 ability module implementing a standard interface. Adding weapon #5 post-alpha touches zero core files.

---

## 13. Out of Scope for Alpha (explicitly)

Multiple maps · faction warfare mechanics · Wraith PvE bosses · ranked mode · trading · RNG cosmetics crates · guilds/clans · weapon skins rendering (UI placeholder only) · voice lines. Written down so scope creep has to fight this list.
