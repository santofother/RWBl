# C16 — Match rules v2: no round cap, win by finishing 1st above the win score
Agent: **Either** · Wave 3 · Branch: `c16-win-rule`
Model: Codex **GPT-6.1 Sol, medium** · or Claude **Sonnet 5.5, medium**
Depends on: C09

Owns: `rwbl/game/match/**`, `tools/tests/match_test.sh`
Read: `DESIGN.md` §3 (rounds + winning bullets) · handoff `C09` · `rwbl/game/match/match.gd`,
`match_tuning.gd` · headers of `rwbl/game/race/race_controller.gd`, `rwbl/game/scoring/scoring.gd`

## Goal
User decision 2026-11-14: rounds repeat until someone wins. A player wins when they **finish 1st in a race** and
their total (after that round's points) is **≥ win_score** (30). Reaching 30 alone doesn't end the match.

## Steps
- At the end of each Score phase (host): race winner = slot with finish place 1 (`race.finish_time_of` / finish
  order from `chariot_finished`). If that slot's total ≥ `win_score` → `[Game] WIN slot N score S` and the
  results screen as today. Nobody finished? No winner this round.
- Remove the round cap: `rounds` leaves MatchTuning / rules (or `rounds = 0` means unlimited and is the default;
  keep `--rounds=N` as a test-only cap so tests still end). Log `[Game] MATCH POINT slot N` the first time a
  slot is ≥ win_score at the start of a round (HUD can show it later).
- Grand Circus is **dropped** (user, 2026-11-14): remove `is_grand_circus()`, `grand_circus_extra_laps`, the
  extra-lap logic and the `[Game] GRAND CIRCUS` log. Grep the repo first; if another system still calls
  `is_grand_circus()`, keep it returning false with a `# TODO(C16):` instead of breaking that file.
- Catch-up dealing keeps working with no round cap (it reads totals, not round numbers; check).

## Tests
- Extend `match_test.sh`: with `--test-totals`, (a) a slot at ≥ 30 that doesn't finish 1st → match continues
  to the next round; (b) a slot at ≥ 30 that finishes 1st → `[Game] WIN`; (c) a slot that gets from 28 to 31
  in a round it wins → WIN; (d) no `rounds` → no `MATCH_OVER` after round 6.
- Manual (user): F6 `game/match/match.tscn` with `--test-totals=0:29`, win a race → match ends.

## Finish
Handoff `docs/handoffs/C16.md`, land per AGENTS.md step 8.
