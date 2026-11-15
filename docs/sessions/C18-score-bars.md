# C18 — Score screen v2: vertical stacked bars climbing to the 1000 line
Agent: **Either** · Wave 4 · Branch: `c18-score-bars`
Model: Codex **GPT-6.1 Sol, high** · or Claude **Sonnet 5.5, high**
Depends on: C16

Owns: `rwbl/game/scoring/score_screen.gd`, `score_screen.tscn`, new `rwbl/game/scoring/score_bars.gd`,
new `rwbl/game/scoring/score_anim_tuning.gd` + `default_score_anim.tres`, `tools/tests/score_test.sh` (add a case)
Read: `DESIGN.md` §3, §6 · handoffs `C11`, `C14`, `C16` · `rwbl/game/scoring/score_screen.gd`, header of
`scoring.gd` (breakdown + totals shape) · `rwbl/game/hud/hud_theme.tres`

## Goal
User request 2026-11-14: after every round a fun animation shows each player's point gain and the gap between
players. **Vertical bar chart**, one column per player (their colour + name below), with a horizontal **win line
at `win_score`** (1000) across the chart. Bars visibly rise toward the line.

## Steps
- Layout: chart area sized so the win line sits at ~85% height (taller bars than 1000 just poke above it; scale
  the y axis to max(win_score, top total) × 1.1). Ghost tick marks every 250.
- Sequence (local only, after `GameEvents.round_scored`):
  1. Bars appear at last round's totals (instant).
  2. For each category in order **finish → kills → traps → bonuses (laps, clean, mercy, fewest deaths)**, every
     player's bar grows by that chunk at once (tween, ease-out, ~0.5 s), the chunk in that category's colour
     (lighter shade of the player colour, or a fixed per-category tint; pick what reads best) with a popping
     `+150` label above it. Negative chunks (own trap) shrink the bar with a red `−30`.
  3. Column order re-sorts by total with a slide tween if anyone overtook; a "▲ OVERTAKE" pop on the climber.
  4. Bars ≥ win line glow/pulse and get a "MATCH POINT" flag; on a WIN round the winner's bar bursts past the
     line with confetti-ish particles (simple `CPUParticles2D` is fine) and "WINS!" text.
  5. Totals count up as numbers under each bar the whole time.
- Category colours, per-step durations, pop scale, ease all in `ScoreAnimTuning` (`# TUNE`, `@export_range`).
- Any key / click skips to the final state. The whole thing fits inside `score_time` (10 s); if
  it can't, speed up steps rather than overrun.
- Keep a compact table of the breakdown (current C11 rows) as a toggle (Tab) or small panel; don't lose the info.
- Keep `rows()` for tests; add `bars() -> Array` (slot, from, to, chunks) for headless checks.

## Tests
- `score_test.sh`: with `--test-totals`, after a Score phase `bars()` has one entry per player, `to == total`, chunk
  sums equal round points, order sorted by total; `[Score] BARS done` logged before the phase ends.
- Manual (user): F6 `game/match/match.tscn` with `-- --bots=3 --phase-time=20`, race, watch the bars climb;
  press Space to skip. Then `--test-totals=0:900` and win → your bar crosses the 1000 line with MATCH POINT.

## Finish
Handoff `docs/handoffs/C18.md` with a short screenshot description, land per AGENTS.md step 8.
