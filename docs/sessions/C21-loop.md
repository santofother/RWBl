# C21 — Track piece: spiral loop
Agent: **Claude only** · Wave 4 · Branch: `c21-loop`
Model: Claude **Opus 5.5, high**
Depends on: C20

Owns: `rwbl/game/track/**`, `rwbl/game/items/defs/piece_loop.tres`, `rwbl/game/chariot/**` (surface gravity),
`rwbl/game/camera/**` (roll only), `rwbl/game/bots/**` (loop speed), `tools/tests/track_piece_test.sh` (add cases)
Read: `DESIGN.md` §4, §5.6, §7 · handoffs `C13`, `C19`, `C20`

## Goal
A rare piece: drive up and around a vertical loop (with a sideways offset so it doesn't hit itself), upside
down at the top. Too slow and you fall off.

## Steps
- Loop curve with a lateral offset; road normal points inward. Inside a loop zone the chariot's gravity is
  `-road_normal × g` while speed > `loop_min_speed` (`# TUNE`); below it normal gravity takes over → falls.
- Chariot orientation follows the road normal smoothly; horses/cart don't flip weirdly at the joints.
- Race camera rolls with the road inside the loop and returns to level after (C13 owns the camera; roll only).
- Bots speed up before the loop (skip boosting = fall). Net: snapshots carry orientation already; check
  interpolation across the 360° roll (use quaternions/slerp).

## Tests
- `track_piece_test.sh`: a chariot at full speed completes the loop and keeps its progress; one at low speed
  falls and respawns; bots finish a lap with a loop; client sees the roll without snapping.
- Manual (user): `--free-build`, place Loop, drive it fast and slow.

## Finish
Handoff `docs/handoffs/C21.md`, land per AGENTS.md step 8.
