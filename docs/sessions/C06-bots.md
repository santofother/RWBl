# C06 — Bot drivers + headless race harness
Agent: **Either** (suggested Codex) · Tier: **T3** · Wave 1 · Branch: `c06-bots`
Depends on: C02

Owns: `rwbl/game/bots/**`, `tools/tests/bot_race_test.sh`, `tools/tests/bot_soak_test.sh` (optional, long)
Read: `DESIGN.md` §4, §11 Q6 · `docs/ARCHITECTURE.md` §1, §2 · handoff `C02` · `rwbl/game/bots/*.gd` (your stubs) ·
headers of `rwbl/game/chariot/chariot.gd`, `rwbl/game/track/track.gd`, `rwbl/game/common/chariot_input.gd`,
`rwbl/game/net/chariot_sync.gd`, `rwbl/game/build/build_phase.gd` (`items()`), `rwbl/game/common/item_def.gd`

## Goal
Bots fill empty slots and replace dropouts, and let one machine test a 5-chariot race headless. They drive
through the exact same `ChariotInput` path as players.

## Steps
- `BotDriver.compute_input()`: follow the centre curve with speed-based look-ahead, brake before sharp turns
  (curvature ahead), whip on straights when stamina is high, keep a lateral offset from nearby chariots, steer
  around items whose def has `blocks_path` (footprint from `ItemDef`), and get unstuck (no progress for 2 s →
  reverse/brake + steer for 1 s, log `[Bot] STUCK slot`).
- `BotTuning` resource (look-ahead, brake factor, aggression, skill noise) registered with `TuningPanel`; small
  per-bot noise so bots aren't identical.
- `BotManager`: keep driving bot slots on `roster_changed` (dropouts become bots). Log `[Bot] LAP slot n` from
  your own progress tracking (race laps belong to C05, which runs in parallel).
- Today the track and chariot are C02 stubs (oval, arcade). C04/C05 replace them in parallel: keep the driver
  generic (only the public APIs) so it survives that.

## Tests
- `bot_race_test.sh`: `match.tscn --no-human --bots=5 --phase=race --rounds=1 --phase-time=90 --autotest=85` →
  every bot logs ≥ 2 `[Bot] LAP`, no bot `STUCK` more than twice, no errors.
- `bot_soak_test.sh` (skipped by `--quick`): 5 bots, 5 minutes, no errors, every bot keeps lapping.
- Manual: none.

## Finish
Handoff `docs/handoffs/C06.md` (tuning knobs, known weak spots), land per AGENTS.md step 8.
