# C05 — Greybox loop track, checkpoints, laps, finish order, race camera v1
Agent: **Either** (suggested Codex) · Wave 1 · Branch: `c05-track-race`
Model: Codex **GPT-6.1 Sol, medium (or GPT-6 Luna, high)** · or Claude **Sonnet 5.5, medium**
Depends on: C02

Owns: `rwbl/game/track/**`, `rwbl/game/race/**`, `rwbl/game/camera/race_camera.gd`, `rwbl/game/camera/race_camera.tscn`,
`tools/tests/race_test.sh`
Read: `DESIGN.md` §3 (Race row), §5.5, §7 (race camera line) · `docs/ARCHITECTURE.md` §1, §4 (Track, Match,
Events) · handoff `C02` · `rwbl/game/track/track.gd`, `rwbl/game/race/race_controller.gd` (your stubs) · headers of
`rwbl/game/match/match.gd`, `rwbl/game/common/game_events.gd`, `rwbl/game/chariot/chariot.gd`, `rwbl/game/net/chariot_sync.gd`

## Goal
One greybox loop track (DESIGN §11 Q5: one loop to start) and a race that counts laps and produces a finish order.

## Steps
- Track: replace the stub oval with a loop authored as a `Path3D` curve inside `track.tscn` (so the user can edit
  it in the editor later): two long straights, one hairpin, one S-bend, width ~14 m. Road mesh generated from the
  curve, walls on layer `WALL` (`StaticBody3D`) both sides, ground on `WORLD`, a start/finish line, room for a
  5-car grid. Keep every public function of `Track` working (contract test checks them).
- `RaceController` (host): on `Phase.RACE` put chariots on `start_transform(slot)`, `frozen = true`, 3 s countdown
  (`[Race] GO`), then unfreeze. Checkpoints in order (`checkpoint_progress(i)`, skipping is not counted), laps
  = `rules.laps`. Emit `lap_completed` / `clean_lap` (clean = no `Chariot.hit` during the lap),
  `chariot_finished(slot, place, time)` (`[Race] FINISH slot place time`). When everyone finished (or the race
  timer runs out) emit `race_over(order)` (DNFs by progress) and `phase_end_requested(RACE)` after 3 s.
- `progress_of(slot)` = laps × length + progress; `place_of`, `lap_of`, `is_finished`. Sync lap/place/finish to
  clients by RPC at ~4 Hz for the HUD (C14).
- Race camera v1 (`camera/race_camera.gd`): chase behind the target, smooth, speed-based FOV. C13 polishes later.

## Tests
- `race_test.sh`: `match.tscn --no-human --bots=3 --phase=race --rounds=1 --laps=2 --phase-time=150` → 3
  `[Race] FINISH` lines with places 1–3, `race_over`, the race phase ends early (`PHASE score` well before 150 s).
  Bots are C06's (parallel). If the C02 stub bot can't get round your track, add a test-only autopilot under
  `race/tests/` instead of editing `bots/`.
- A checkpoint unit test: a chariot teleported past checkpoint 4 without 1–3 does not complete a lap.
- Manual (user): open `game/match/match.tscn`, press **F6**: you + 3 bots; drive 1 lap (W/A/S/D), see the lap
  complete in the Output panel.

## Finish
Handoff `docs/handoffs/C05.md` (track numbers C08 needs: length, width, no-build zone), land per AGENTS.md step 8.
