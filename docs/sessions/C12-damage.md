# C12 — Damage: wheels, collisions, stun, respawn, crow spectator
Agent: **Either** (suggested Claude) · Wave 3 · Branch: `c12-damage`
Model: Claude **Opus 5.5, medium** · or Codex **GPT-6.1 Sol, high**
Depends on: C07, C10

Owns: `rwbl/game/combat/**`, `tools/tests/combat_test.sh`, and in `rwbl/game/chariot/`: the damage functions
(`damage_wheel`, `kill`, `respawn`) and damage visuals only (not the driving model, that stays C04's)
Read: `DESIGN.md` §4 (Damage model, Collisions), §6 (Death and respawn, Stylized gore) · `docs/ARCHITECTURE.md`
§2, §4 (Chariot, Events) · handoffs `C04`, `C07`, `C10` · `rwbl/game/combat/combat.gd` (your stub) · headers of
`rwbl/game/chariot/chariot.gd`, `rwbl/game/track/track.gd`, `rwbl/game/race/race_controller.gd`, `rwbl/game/common/game_events.gd`

## Goal
Crashes matter but never sideline anyone for long: wheels pop off, horses get stunned, dead players are back
in under 3 s or haunt the track as a crow.

## Steps
- Chariot-vs-chariot (host, from `Chariot.hit` where `other` is another chariot): the heavier/faster one wins
  (compare mass × speed along the impact); loser's cart hit → `damage_wheel(side, winner_slot)` (side from the
  impact point), horse hit → `stun(0.8)`. Short immunity (~0.5 s) per pair so one scrape isn't three hits.
- Deaths: keep the C02 forwarding (`chariot_died`, `kill` when another player caused it without an item,
  `self_kill` for own items). Respawn after `CombatTuning.respawn_delay` (< 3 s total, `# TUNE`) at
  `track.respawn_transform(progress − 10 m)`, pit adds its time penalty; emit `chariot_respawned`.
- Crow spectator: a player who finished the race (or is dead with the race nearly over) becomes a crow: free
  (the camera side is C13's spectator mode, write no camera code here) and every 8 s may drop one minor hazard (`mud_patch`) via a host RPC in
  `combat/`; it spawns like a placed item with `owner_slot` = the crow so scoring counts it.
- Visuals on every peer, driven by snapshot changes (wheel bits, dead flag): wheel pops off as a cosmetic
  `RigidBody3D` that bounces away and fades; confetti-style burst on death (DESIGN: cartoonish, no lingering gore).
- `CombatTuning` resource registered with `TuningPanel`.

## Tests
- `combat_test.sh` + `combat/tests/combat_test.tscn`: two chariots driven into each other by scripted input:
  slower one's wheel breaks, top speed drops (limp), second wheel → crawl; horse-on-horse → stun; `kill` →
  `chariot_died` → `chariot_respawned` within 3 s, repaired; self-kill vs kill attribution; crow drop spawns an
  item owned by the crow slot.
- Manual (user): **F6** on `game/match/match.tscn`, ram a bot side-on: a wheel flies off and handling gets worse;
  drive into a pit: back on track in under 3 s.

## Finish
Handoff `docs/handoffs/C12.md`, land per AGENTS.md step 8.
