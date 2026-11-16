# C23 — Race to the finish line (no laps, shortcuts count)
Agent: **Either** · Wave 4 · Branch: `c23-race-finish`
Model: Claude **Opus 5.5, medium** · or Codex **GPT-6.1 Sol, medium**
Depends on: C22

Owns: `rwbl/game/race/**`, `rwbl/game/bots/**`, `rwbl/game/scoring/**` (lap rules only), `rwbl/game/hud/**`
(lap counter only), `rwbl/game/match/match.gd` + `match_tuning.gd` (`laps` rule only), `tools/tests/race_test.sh`,
`bot_race_test.sh`, `bot_soak_test.sh`, `score_test.sh` (update for no laps)
Read: `DESIGN.md` §3, §5.6, §6 (changed 2026-11-15) · handoffs `C05`, `C06`, `C11`, `C22` ·
`race/race_controller.gd`, `bots/bot_manager.gd`, `scoring/scoring.gd` header

## Goal
User decision 2026-11-15: one run from start to finish; **shortcuts are allowed**. Race position = progress along
the course; a chariot finishes when it crosses the finish line (`Track.finish_progress()`), however it got there.

## Steps
- RaceController: no laps, no ordered checkpoints. Progress = `track.progress_at(pos)` with a small guard so a
  chariot can't "finish" by touching the finish piece from the side or from behind (must cross the finish
  line plane inside the road, driving forward). Checkpoints only remember the last respawn spot (max progress
  reached). Keep `chariot_finished`, `race_over`; `lap_completed`/`clean_lap` → emit `clean_lap(slot, 1)` once
  at the finish when the run had no collisions (signal names stay; tell the head engineer if you want new ones).
- Remove the `laps` rule (CLI `--laps` ignored with a warning); race time limit stays.
- Bots: drive to the finish and stop there (brake after the line); `[Bot] LAP` → `[Bot] FINISH slot n`.
- Scoring (DESIGN §6): drop "+25 per lap"; "clean lap" → "clean run" +25 once. HUD: lap counter → "x m to go".
- Update AGENTS.md CLI list (`--laps` removed).

## Tests
- `race_test.sh`: 3 bots finish in order on the default course; a chariot teleported past the middle still
  finishes (shortcuts count); touching the finish piece from the side does not finish.
- `bot_race_test.sh` / soak: every bot finishes, ≤ 2 stuck. `score_test.sh`: clean run +25, no lap points.

## Finish
Handoff `docs/handoffs/C23.md`, land per AGENTS.md step 8.
