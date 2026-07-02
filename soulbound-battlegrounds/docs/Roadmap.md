# Soulbound Battlegrounds — Alpha Roadmap (10–12 weeks)

Assumes 1 developer @ ~20–30 hrs/week using AI assistance, or a 2–3 person team splitting code / build / VFX. Each week ends with a playable build. **Rule: if a week slips, cut from the "polish" column, never from combat feel.**

---

## Month 1 — Core Combat & Vertical Slice

### Week 1 — Project skeleton + movement
- [ ] Rojo project, folder structure, Git repo
- [ ] Net module (remotes), service bootstrap, client controller bootstrap
- [ ] Sprint, Soul Dash with cooldown + i-frames (server-validated)
- [ ] Graybox Duskmarket blockout: plaza, 2 spawn zones, training yard (no art)
- [ ] DataService skeleton with session locking (save/load stub data)

### Week 2 — Hitboxes, M1s, stun
- [ ] HitboxModule (spatial query, keyframe-driven, debug visualizer)
- [ ] M1 combo chain ×4 with finisher knockback, hit-stop, hit sparks
- [ ] StunManager (hitstun / guard-break / ragdoll states, anti-infinite cap)
- [ ] RagdollModule (knockback impulse, recovery)
- [ ] Training dummy v1 (static, HP bar, resets)

### Week 3 — Defense layer + Ashfang moves 1–2
- [ ] Block, Block HP, guard break (charged heavy)
- [ ] Perfect dodge (timing window, attacker vulnerability mark)
- [ ] Air launch finisher + basic air combo gravity tuning
- [ ] CooldownManager + AbilityService pipeline (input → validate → execute)
- [ ] Ashfang: Ember Slash + Wolf Rush working end-to-end with placeholder VFX

### Week 4 — Ashfang complete + data + basic UI
- [ ] Ashfang: Flame Counter + Burning Fang, Burn status effect
- [ ] Soul Energy meter (gain rules, HUD ring)
- [ ] ProgressionService: Soul XP earn + weapon level curve + unlock gating
- [ ] DataStore saving live: XP, levels, unlocked/equipped weapon, tokens
- [ ] HUD v1: HP, energy, hotbar cooldowns, level bar
- [ ] **Milestone: two testers can duel with full Ashfang kits and progress saves**

## Month 2 — Content, Progression Depth, Signature Mechanics

### Week 5 — Frostveil + Thundercrown
- [ ] Frostveil 4 moves + Chill/freeze status (built from weapon template)
- [ ] Thundercrown 4 moves + heavy M1 modifiers
- [ ] Weapon selection menu + Spirit Token unlock flow + vendor NPC

### Week 6 — Voidneedle + destructibles
- [ ] Voidneedle 4 moves (teleport validation server-side!) + backstab bonus
- [ ] DestructionService: weak walls, crates, debris, respawn timers
- [ ] Ragdoll-through-wall interactions (Crown Breaker, finishers)

### Week 7 — Final Releases (ultimates)
- [ ] Transformation flow: cinematic lock, camera push/shake, music sting
- [ ] All 4 Final Release buff kits (modifier system on AbilityService)
- [ ] Aura tier system (levels 10–50 particle rigs, 3 visual tiers reused per color)

### Week 8 — Soul Clash + Spirit Echo
- [ ] SoulClashService: eligibility windows, lock, mash duel, resolve, cooldown
- [ ] Clash camera + collision VFX + tie explosion
- [ ] SpiritEchoService: echo prefab, absorb prompt, rewards, weapon hint lines
- [ ] **Milestone: full 4-weapon build with ultimates and both signature mechanics**

## Month 3 — Polish, Balance, Release

### Week 9 — Balance + anti-exploit pass
- [ ] Damage/cooldown spreadsheet pass; true-combo audit per weapon
- [ ] Remote rate limits, teleport/range validation audit, NaN guards
- [ ] Admin commands final (give XP/tokens, reset data, spawn dummy, killpart)
- [ ] Private-server config

### Week 10 — Map art + VFX/SFX polish
- [ ] Duskmarket art pass: lighting, skybox, crack decals, spirit motes, lanterns
- [ ] Sword trails, hit sparks, aura rigs final; per-weapon SFX set
- [ ] Ultimate music stings; ambient soundscape

### Week 11 — Mobile + tutorial + shop placeholder
- [ ] Mobile controls: hotbar buttons, dash button, block toggle, clash mash button
- [ ] UI scaling pass for phone/tablet
- [ ] 3-minute tutorial: move → M1 → block → dash → ability → dummy kill → echo absorb
- [ ] Shop UI with "Coming Soon" cosmetic tabs; kill effect/emote placeholders

### Week 12 — Playtesting + release
- [ ] Closed playtest (10–20 players), crash/exploit hotfixes
- [ ] Full testing checklist run (see TestingChecklist.md)
- [ ] Icon/thumbnails, game page copy, group setup
- [ ] **Alpha release** 🎉

---

## Post-Alpha Backlog (do NOT build during alpha)
Weapon #5+ · second map · Wraith PvE events · ranked · cosmetic RNG crates (fair-odds, cosmetics only) · faction war weekends · emote/kill-effect store · clan system.
