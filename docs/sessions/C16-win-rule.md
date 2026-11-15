# C16 — Match rules v2: no round cap, win at 1000 by finishing 1st, points ×30
Agent: **Either** · Wave 4 · Branch: `c16-win-rule`
Model: Codex **GPT-6.1 Sol, medium** · or Claude **Sonnet 5.5, medium**
Depends on: C09, C11

Owns: `rwbl/game/match/**`, `tools/tests/match_test.sh`, `rwbl/game/scoring/score_table.gd`,
`rwbl/game/scoring/default_score_table.tres`, `rwbl/game/scoring/tests/score_test.gd` (expected numbers only),
`rwbl/game/hud/hud.gd` (only the round label, ~line 411, and a MATCH POINT badge)
Read: `DESIGN.md` §3 (rounds + winning) and §6 (points table) · handoffs `C09`, `C11` · `rwbl/game/match/match.gd`,
`match_tuning.gd` · headers of `rwbl/game/race/race_controller.gd`, `rwbl/game/scoring/scoring.gd`

## Goal
User decisions 2026-11-14: rounds repeat until someone wins. Win score is **1000**. A player wins when they
**finish 1st in a race** and their total (after that round's points) is **≥ win_score**. Being over 1000 alone
doesn't end the match: e.g. 900 → wins a race → 1100, match goes on; next race they win → WIN. Someone else
who is ≥ 1000 and wins a race also ends it. Points scale ~×30 so a match reaches match point in ~4–5 rounds.

## Steps
- End of each Score phase (host): race winner = finish place 1. If that slot's total ≥ `win_score` →
  `[Game] WIN slot N score S` and the results screen as today. Nobody finished → no winner this round.
- `win_score := 1000` (`@export_range(100, 5000, 50)`). Remove the round cap: `rounds = 0` = unlimited, the
  default; `--rounds=N` stays a test-only cap so tests end. Log `[Game] MATCH POINT slot N` the first time a slot
  is ≥ win_score at the start of a round.
- Drop Grand Circus: `is_grand_circus()`, `grand_circus_extra_laps`, extra-lap logic, `[Game] GRAND CIRCUS`. Grep
  first; if another file calls `is_grand_circus()`, keep it returning false with `# TODO(C16):`.
- New defaults in `score_table.gd` (widen every `@export_range` to fit, e.g. `(-100, 500, 5)`):
  finish 150/100/70/40/0 · trap hit 30 (cap 90) · kill 60 · own trap −30 · lap 25 · clean lap 25 · mercy 25 ·
  fewest deaths 50. Keep `.tres` free of overrides so the script defaults apply.
- HUD: round label `Round %d · <phase>` with no max (`hud.gd` ~411). Players ≥ win_score get a small
  "MATCH POINT" tag next to their name in the HUD standings/leader line (whatever C14 shows; keep it minimal).
- Catch-up dealing keeps working without a cap (it reads totals; check `catchup_from_round`).

## Tests
- `match_test.sh` with `--test-totals`: (a) slot at ≥1000 not finishing 1st → next round; (b) ≥1000 finishing 1st →
  `[Game] WIN`; (c) 900 + a race win that lands it ≥1000 → **no** WIN yet, next round, then WIN on its next 1st;
  (d) no `--rounds` → no match end after round 6. Update `score_test.gd` expected values to the new table.
- Manual (user): F6 `game/match/match.tscn` with `-- --test-totals=0:990`, win a race → you're at ~1140, the
  match goes on and the HUD says MATCH POINT; win the next race → results screen.

## Finish
Handoff `docs/handoffs/C16.md`, land per AGENTS.md step 8.
