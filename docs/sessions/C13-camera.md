# C13 — Camera swing Build → Race, race camera polish (FOV, sway, pullback)
Agent: **Either** · Wave 3 · Branch: `c13-camera`
Model: Codex **GPT-6.1 Sol, medium (or GPT-6 Luna, high)** · or Claude **Sonnet 5.5, medium**
Depends on: C05, C08

Owns: `rwbl/game/camera/**` (all files, including C05's race camera and C08's build camera), `tools/tests/camera_test.sh`
Read: `DESIGN.md` §7 · `docs/ARCHITECTURE.md` §1, §4 (Chariot, Snapshot flags, Effects) · handoffs `C05`, `C08` ·
`rwbl/game/camera/*.gd` · headers of `rwbl/game/chariot/chariot.gd`, `rwbl/game/match/match.gd`

## Goal
The player connects the traps they placed from above with what they then drive through, and speed feels fast.

## Steps
- `CameraDirector`: Build → Race swing (~1.5 s, `# TUNE`): tween from the build camera down over the track to
  the race camera behind the local chariot (start the tween at `phase_changed(RACE)`; it ends before the
  countdown's GO). Race → Score/Draft: simple cut or short pull-up.
- Race camera polish: speed-based FOV, drift sway from `cart_angle`, slight pullback while `FLAG_BOOSTING`,
  shake on `Effects.SHAKE`/collisions (`hit` on the host isn't visible to clients: use snapshot velocity jumps),
  look-ahead in turns. Spectator mode (dead / no local player): cycle targets with ←/→.
- `CameraTuning` resource registered with `TuningPanel`.

## Tests
- `camera_test.sh`: headless match with 2 bots and a fake local slot: director logs `[Game] CAMERA build`,
  `swing`, `race` in order on phase changes; race camera FOV rises with target speed (unit check).
- Manual (user): **F6** on `game/match/match.tscn`, place an item in Build, watch the swing down to your chariot,
  whip on a straight (FOV widens, camera pulls back).

## Finish
Handoff `docs/handoffs/C13.md`, land per AGENTS.md step 8.
