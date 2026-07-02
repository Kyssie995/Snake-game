# Soulbound Battlegrounds — Alpha Testing Checklist

Run the full list before every public build. Items marked **[2P]** need two test clients (Studio "Local Server" with 2 players works). Items marked **[EXPLOIT]** should be attempted with a hacked client mindset (fire remotes manually from the command bar).

## 1. Core Movement & Defense
- [ ] Walk/sprint speeds correct; sprint trail appears and stops
- [ ] Soul Dash: moves correct distance, 2s cooldown enforced, i-frames active during dash **[2P]**
- [ ] Perfect dodge: dodging within window refunds cooldown and marks attacker vulnerable (+20% damage) **[2P]**
- [ ] Dash-cancel out of hitstun works only after M1 #2 and consumes dash cooldown **[2P]**
- [ ] Block reduces M1 to 0 and abilities by 50% **[2P]**
- [ ] Block HP drains and regenerates at spec rates; empty Block HP = guard-break stun **[2P]**
- [ ] Charged heavy breaks block and ragdolls **[2P]**
- [ ] Spawn protection: no damage in/out for 5s or until attacking **[2P]**

## 2. M1 Combat
- [ ] 4-hit chain timing feels responsive (<80ms perceived input delay on 100ms simulated ping)
- [ ] Finisher ragdolls and knocks back; W-finisher launches forward; Space-finisher air-launches **[2P]**
- [ ] Air combo: launched target can be followed and hit airborne **[2P]**
- [ ] Hit-stop (0.06s) triggers on every landed M1
- [ ] Anti-infinite: after ~4.5s continuous stun, target gains knockback resistance **[2P]**
- [ ] Hitting a blocking target from behind still damages (block is directional, 120° front arc) **[2P]**
- [ ] M1s cannot hit through walls **[2P]**

## 3. Per-Weapon (repeat for Ashfang, Frostveil, Voidneedle, Thundercrown)
- [ ] All 4 moves: correct damage, cooldown, range, status effect
- [ ] Moves locked below their unlock level; unlock at 1/5/15/25 works
- [ ] Move VFX/SFX play for all nearby clients, not just attacker **[2P]**
- [ ] Final Release: requires level 35 + 100 energy; cinematic lock + invulnerability during activation; buffs apply; duration timer and 90s cooldown correct; end-slow applies **[2P]**
- [ ] Voidneedle teleports rejected if server-side distance/visibility check fails **[EXPLOIT]**
- [ ] Ashfang Flame Counter only triggers on real incoming hits within its 0.6s window **[2P]**

## 4. Soul Clash **[2P]**
- [ ] Two eligible heavies within 0.25s and 12 studs trigger clash; ineligible attacks never do
- [ ] Both players locked exactly 2.0s; camera frames both; VFX mixes both weapon colors
- [ ] Mash counting server-side; >12 presses/s clamped **[EXPLOIT]**
- [ ] Winner knockback +20% damage; tie = mutual explosion, no damage
- [ ] 20s per-player clash cooldown; attacks during cooldown resolve normally
- [ ] Clash aborts safely if one player dies/leaves mid-clash

## 5. Spirit Echo **[2P]**
- [ ] Echo spawns at death spot in victim's weapon color; despawns at exactly 10s
- [ ] Absorb (hold E, 1s) grants +15 XP, +10 energy, weapon hint line; killer gets +5 bonus
- [ ] Only one player can absorb; simultaneous holds resolve to exactly one winner
- [ ] Victim cannot absorb their own echo

## 6. Progression & Data
- [ ] XP from damage/kills/assists/echoes/dummies matches spec; dummy XP daily cap enforced
- [ ] Level curve gates unlocks at 1/5/15/25/35; auras at 10/20/30/40/50
- [ ] Data persists across rejoin: XP, levels, unlocked weapons, equipped weapon, tokens
- [ ] Session lock: second server can't overwrite an active session; data survives server crash (BindToClose flush)
- [ ] Spirit Token earn rate correct; weapon purchase deducts and unlocks; can't buy twice or with insufficient tokens **[EXPLOIT]**

## 7. Destruction
- [ ] Ragdolled player hitting weak wall breaks it; debris fades 8s; wall respawns 60s
- [ ] Crates/stalls/lanterns break on knockback impact
- [ ] Destruction replicates to all clients; no debris accumulation after 10 minutes of fighting (part count stable)

## 8. Anti-Exploit **[EXPLOIT]**
- [ ] Firing ability remotes off-cooldown / while stunned / while dead / for a locked move → rejected, no effect
- [ ] Firing remotes with NaN/huge vectors → rejected, no server error spam
- [ ] Remote spam (100/s) → rate limiter kicks in, player not crashed, server not lagged
- [ ] Damage remote does not exist client-side (grep: client never sends damage numbers)
- [ ] Speed/teleport exploiter is still bounded by server hit validation (can't hit from 100 studs)

## 9. UI / UX
- [ ] HUD: HP, Soul Energy ring, hotbar cooldown radials, level bar all live-update
- [ ] Weapon menu: select, purchase, locked states, level display
- [ ] Damage numbers toggle works; clash mash prompt appears/disappears correctly
- [ ] Tutorial completable in <5 min by a new tester without help
- [ ] Mobile: all actions reachable, UI readable on phone, clash mashing possible

## 10. Performance & Stability
- [ ] 60 FPS on mid PC with 8 players fighting in plaza; no <30 FPS spikes during ultimates
- [ ] Server memory stable over 1-hour soak with dummies auto-fighting
- [ ] No Output errors/warnings during a full duel session
- [ ] Respawn always ≤4s; no stuck-in-ragdoll or stuck-in-clash states after 30-min chaos test **[2P]**
