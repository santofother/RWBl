# C02 — Architecture, contracts, stubs, wave 1–3 cards
Agent: **Claude only** (head engineer) · Tier: **T1** · Claude: Opus 5.5, high · Wave 0 · Branch: `c02-architecture`
Depends on: C01 · Run in a worktree once the GitHub repo exists (otherwise main folder, on the branch)

Owns: `docs/ARCHITECTURE.md`, `docs/sessions/`, `docs/STATUS.md`, `rwbl/game/**` (stubs only),
`rwbl/project.godot` (autoloads, input map, physics layers), `tools/tests/contract_test.sh`
Read: `DESIGN.md` (all, it's the input) · `docs/PLAN.md` §5 · `docs/handoffs/C01.md` · `rwbl/core/*.gd` (API only)

## Goal
Every later card can be built in parallel without talking to the others, because the folders, ownership and
contracts are fixed here. Keep `ARCHITECTURE.md` to about 2 pages: the user reads it at this checkpoint.

## Decide and write down
- **Folder map + owner card** for each `game/` system: `chariot/`, `track/`, `build/`, `draft/`, `match/`,
  `items/`, `scoring/`, `bots/`, `camera/`, `hud/`, `lobby/`, `common/` (shared types, event bus).
- **Contracts** (GDScript stubs that compile, with `# CONTRACT:` tags):
  - `ChariotInput` (steer, throttle, brake, whip, action) — the only thing clients send; bots fill it too.
  - Chariot public API + snapshot format (pos, rot, vel, cart angle, wheel state, stamina) and the
    authority model (AGENTS.md §Conventions).
  - `PlayerInfo`, `PlayerResult`, and the `GameMode` contract from DESIGN §9 (`setup`, `start`, `finished`).
  - Round phase state machine (Draft → Build → Race → Score), its signals, and who drives it (host).
  - `ItemDef` resource (id, rarity, tags, footprint, scene, cost) + tag interaction table format + item
    lifecycle hooks (placed, triggered, chariot_entered, chariot_hit).
  - Placement RPC `(item_id, transform, owner)` + validation result codes.
  - Track API: surface type at a point, checkpoints, path for bots and validation.
  - `GameEvents` bus signals for scoring (finish, trap_hit, kill, self_kill, clean_lap).
  - Tuning resources (`ChariotTuning` etc.) the F2 panel edits.
- **Input map** and **physics layers** in `project.godot`.
- Replace the C01 cube sync with a stub that already follows input-up / snapshot-down.

## Cards
Write full cards `docs/sessions/C03…C14` from `docs/PLAN.md` §5 (format: `docs/sessions/README.md`), each with
Owns (non-overlapping), Read (exact sections), Goal, Steps, Tests, and a click-by-click manual test where a human
is needed. Fix the Depends-on column in `STATUS.md` and set wave 1 cards to `READY`. If something in PLAN.md
turns out wrong, change PLAN.md and say so in the handoff.

## Tests
`contract_test.sh`: loads every stub, checks the contract classes/signals exist. `net_test` still passes.

## Finish
Handoff `docs/handoffs/C02.md` including "Things the user should look at in ARCHITECTURE.md" (max 5 bullets),
then land per AGENTS.md step 8.
