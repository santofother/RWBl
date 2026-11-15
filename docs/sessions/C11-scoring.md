# C11 — Scoring incl. anti-grief rule + score screen
Agent: **Either** (suggested Codex) · Wave 3 · Branch: `c11-scoring`
Model: Codex **GPT-6.1 Sol, medium (or GPT-6 Luna, high)** · or Claude **Sonnet 5.5, medium**
Depends on: C09, C10

Owns: `rwbl/game/scoring/**`, `tools/tests/score_test.sh`
Read: `DESIGN.md` §6 (Per-round table) · `docs/ARCHITECTURE.md` §2, §4 (Events, Match) · handoffs `C05`, `C09`,
`C10` · `rwbl/game/scoring/scoring.gd` (your stub) · `rwbl/game/common/game_events.gd` · headers of
`rwbl/game/match/match.gd`, `rwbl/game/race/race_controller.gd`, `rwbl/game/build/build_phase.gd`, `rwbl/game/track/track.gd`

## Goal
Points that reward clever-but-fair traps: the DESIGN §6 table, with "nobody passes your item, or everyone dies
to it" paying 0 for that item.

## Steps
- `ScoreTable` resource (finish 5/3/2/1/0, trap hit +1 capped at 3 per round, kill +2 each, self-kill −1, clean
  lap +1, last-to-finish mercy +1, **lap completed +1 each, fewest deaths this round +2 (ties all get it; count
  `chariot_died` per slot)**, Grand Circus ×2) registered with `TuningPanel`. (User decision 2026-11-14: laps,
  fewest deaths and kills are added to the table, not instead of it.)
- Host listens to `chariot_finished, race_over, trap_hit, kill, self_kill, clean_lap, chariot_died,
  item_placed`. Trap hits only count when victim ≠ owner.
- Anti-grief, per item: the item's track progress = `track.progress_at(item pos)`. A slot "passed" it when its
  `race.progress_of(slot)` goes beyond that point while alive. At `race_over`: if no chariot passed the item,
  or every chariot that reached it died to it (`chariot_died` with that `item_uid`), its trap points this
  round are 0. Log `[Score] GRIEF item uid` when that happens.
- At `race_over` compute round points, ×2 if `m.is_grand_circus()`, add to totals, broadcast by RPC →
  `GameEvents.round_scored(round_points, totals)` on every peer. Keep `get_totals()` (C09 uses it for the win
  check and catch-up).
- Score screen (`scoring/score_screen.tscn`, shown during `Phase.SCORE`): per player row: name, colour, round
  breakdown (finish / traps / kills / bonus), round total, match total, sorted by total; "GRAND CIRCUS ×2" banner.

## Tests
- `score_test.sh` + `scoring/tests/score_test.tscn`: a Scoring node with fake players and a fake race
  progress source; emit scripted event sequences and assert totals: finish points; lap points; fewest-deaths
  bonus (incl. a tie); two kills = +4; trap cap at 3; owner hit not counted; self-kill −1; mercy point; clean lap; Grand Circus doubling; anti-grief: (a) item nobody passes →
  0, (b) everyone who reached it died → 0, (c) one passes → trap points count.
- Manual (user): **F6** on `game/match/match.tscn`, play one round, check the score screen reads sensibly.

## Finish
Handoff `docs/handoffs/C11.md`, land per AGENTS.md step 8.
