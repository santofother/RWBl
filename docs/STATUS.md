# Status board

Builders edit **only their own row** when they land on `main` (and may flip TODO→READY for cards whose
dependencies are all DONE). The merge log is written only by merge sessions. See AGENTS.md step 8.

Legend: TODO · READY (can start) · IN PROGRESS (branch) · REVIEW (needs merge session: reason) ·
DONE (on main, date) · BLOCKED (reason)

## Board
| Card | Title | Wave | Agent · Tier | Depends on | Status | Branch / note |
|---|---|---|---|---|---|---|
| C01 | Project + LastMage net core + cube sync (N1) | 0 | Claude only · T2 | — | DONE 2026-11-13 | main |
| C02 | Architecture, contracts, stubs, cards C03–C14 | 0 | Claude only · T1 | C01 | DONE 2026-11-13 | c02-architecture |
| C03 | Lobby: LAN discovery, Steam, ready-up (N2, N3) | 1 | Either (Codex) · T2 | C02 | DONE 2026-11-13 | c03-lobby |
| C04 | Chariot controller + F2 tuning panel | 1 | Either (Claude) · T1 | C02 | DONE 2026-11-13 | c04-chariot |
| C05 | Greybox loop track, laps, race camera v1 | 1 | Either (Codex) · T3 | C02 | DONE 2026-11-14 | c05-track-race |
| C06 | Bot drivers + headless race harness | 1 | Either (Codex) · T3 | C02 | DONE 2026-11-14 | c06-bots |
| C07 | Host-authoritative chariot netcode (N4) | 2 | Either (Claude) · T1 | C03, C04 | DONE 2026-11-14 | c07-netcode |
| C08 | Build phase + placement validation (N5) | 2 | Either (Codex) · T2 | C05 | DONE 2026-11-14 | c08-build-phase |
| C09 | Match flow: draft/build/race/score rounds | 2 | Either (Codex) · T2 | C05, C06 | DONE 2026-11-14 | c09-match-flow |
| C10 | Item framework + first 8 items | 2 | Either · T2 | C04, C05 | DONE 2026-11-14 | c10-items |
| C11 | Scoring + score screen | 3 | Either (Codex) · T3 | C09, C10 | DONE 2026-11-14 | c11-scoring |
| C12 | Damage, wheels, respawn, crow | 3 | Either (Claude) · T2 | C07, C10 | DONE 2026-11-14 | c12-damage |
| C13 | Camera swing + race camera polish | 3 | Either · T3 | C05, C08 | DONE 2026-11-14 | c13-camera |
| C14 | HUD + draft cards UI | 3 | Either (Codex) · T3 | C09 | DONE 2026-11-14 | c14-hud |
| C16 | Match rules v2: no round cap, win at 1000 by finishing 1st, points ×30 | 4 | Either · T3 | C09, C11 | DONE 2026-11-14 | c16-win-rule |
| C17 | Demolish card (remove a placed item) | 4 | Either · T2 | C08, C10 | DONE 2026-11-14 | c17-demolish (user OK to land; ItemDef.targets_placed still to approve) |
| C18 | Score screen v2: vertical stacked bars to the 1000 line | 4 | Either · T2 | C16 | DONE 2026-11-14 | c18-score-bars |
| C19 | Track pieces framework + hairpin, chicane | 4 | Claude pref · T1 | C16, C17 | DONE 2026-11-14 | c19-track-pieces |
| C22 | Modular point-to-point course (pieces at joints) | 4 | Claude pref · T1 | C19 | DONE 2026-11-15 | c22-modular-course |
| C23 | Race to the finish line (no laps, shortcuts count) | 4 | Either · T2 | C22 | DONE 2026-11-15 | c22-modular-course (with C22) |
| C24 | Playtest fixes: draft, build pan/cursors/previews, deadly pit/axe, respawn wait, spectate, scoring | 4 | Claude (head) · T2 | C23 | DONE 2026-11-15 | c24-playtest-fixes |
| C25 | Chaos items: bumper, lion dung, whirlwind, catapult, spiked log | 4 | Claude Sonnet · T3 | C10 | DONE 2026-11-15 | c25-chaos-items (merged via c24) |
| C20 | Track pieces: hills, crest, banked turn | 4 | Claude pref · T2 | C22, C23 | READY | |
| C21 | Track piece: spiral loop | 4 | Claude only · T1 | C20 | DONE 2026-11-15 | c21-loop (built before C20; + compact finish card, respawn behind passer) |
| P1 | Playtest 1 (user + friends) | — | user | wave 3 | TODO | |
| C15 | Triage + plan waves 4+ | — | Claude only · T1 | P1 | TODO | |

Depends-on confirmed by C02 (full cards in `docs/sessions/`). Wave 1 (C03–C06) runs in parallel, max 3 at once.

## Merge log
| Date | Card | Merged by | Notes |
|---|---|---|---|
