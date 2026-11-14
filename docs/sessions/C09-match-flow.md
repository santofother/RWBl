# C09 — Match flow: Draft → Build → Race → Score, rounds, Grand Circus, catch-up dealing
Agent: **Either** (suggested Codex) · Wave 2 · Branch: `c09-match-flow`
Model: Codex **GPT-6.1 Sol, high** · or Claude **Opus 5.5, medium**
Depends on: C05, C06

Owns: `rwbl/game/match/**`, `rwbl/game/draft/**`, `tools/tests/match_test.sh`
Read: `DESIGN.md` §3, §5.5 (draft bullets), §6 (win condition only) · `docs/ARCHITECTURE.md` §1, §2, §4 (Match,
Players, Events) · handoffs `C02`, `C05`, `C06` (and `C03` if done) · `rwbl/game/match/match.gd`, `rwbl/game/draft/draft.gd`
(your stubs) · `rwbl/game/common/phase.gd`, `game_events.gd`, `game_mode.gd`, `item_def.gd` · headers of
`rwbl/game/scoring/scoring.gd`, `rwbl/game/items/item_db.gd`

## Goal
A whole match runs by itself: 6–8 rounds of the four phases, early phase ends, the Grand Circus finale and a
winner, identically on every peer.

## Steps
- `MatchTuning` resource (phase durations, rounds, win score 30, Grand Circus extra laps, rarity weights,
  catch-up rules) registered with `TuningPanel`; replace `DEFAULT_RULES` numbers with it (rules dict still
  overrides; keep the rules keys contract and the standalone CLI).
- Draft (host): deal 3 cards per player from `ItemDB.all_defs()` weighted by rarity. Catch-up: last place
  (by `m.scoring.get_totals()`) gets at least one `RARE`, the leader only `COMMON`s; round 1 = no catch-up.
  Send each human its cards only (RPC to that peer → `hand_dealt`), bots pick on the host. Players keep 1 or
  2 (`submit_pick`). Timeout → auto-keep the first card. All picked → `phase_end_requested(DRAFT)`.
  `hands_final` to all; `hand_of(slot)` returns the kept ids. Log `[Draft] DEAL slot ids`, `[Draft] KEEP slot ids`.
- Phase loop: keep the host-driven RPC; honour `phase_end_requested` for every phase. After SCORE: someone ≥
  `win_score` or last round → `_finish()`. Last round = Grand Circus (`is_grand_circus()`, +1 lap; scoring
  doubles points itself).
- Dropouts: `NetworkManager.peer_left` during a match → that slot becomes a bot on every peer (RPC updates the
  PlayerInfo, then `GameEvents.roster_changed`). Host leaving is the lobby's job (C03).
- Test hook `--test-totals=slot:points,...` so the catch-up dealing and the 30-point win can be tested before
  Scoring (C11) exists.

## Tests
- `match_test.sh`: `match.tscn --no-human --bots=5 --rounds=6 --phase-time=2` → 6 rounds × 4 phases logged
  in order, 3 cards dealt and 1–2 kept per bot per round, `[Game] MATCH FINISHED` with 5 results. Second case
  with `--test-totals=0:29,1:0 ...`: last place's deal contains a rare, leader's only commons, and a total ≥ 30
  ends the match early. If C03 landed: host + 1 client, client sees the same phase sequence; kill the client
  mid-match → its slot becomes a bot and the match continues.
- Manual: none (C14 makes the draft visible).

## Finish
Handoff `docs/handoffs/C09.md` (MatchTuning fields, draft API for C14), land per AGENTS.md step 8.
