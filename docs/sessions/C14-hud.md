# C14 — HUD: lap, position, stamina, ammo, phase timer, draft cards UI
Agent: **Either** (suggested Codex; Terra for the screenshot check) · Tier: **T3** · Wave 3 · Branch: `c14-hud`
Depends on: C09

Owns: `rwbl/game/hud/**`, `tools/tests/hud_test.sh`
Read: `DESIGN.md` §3, §4 (whip/stamina, damage), §5.5 (draft) · `docs/ARCHITECTURE.md` §1, §4 · handoffs `C05`,
`C08`, `C09` · `rwbl/game/hud/hud.gd` (your stub) · headers of `rwbl/game/match/match.gd`,
`rwbl/game/race/race_controller.gd`, `rwbl/game/draft/draft.gd`, `rwbl/game/build/build_phase.gd`,
`rwbl/game/chariot/chariot.gd`, `rwbl/game/common/item_def.gd`

## Goal
Readable at a glance at 1080p while racing (pillar 3), and a draft screen that makes picking cards fun.

## Steps
- Race HUD: lap x/y, position 1st–5th, stamina bar (flashes when too tired to whip), wheel icons (2 = fine,
  broken = red), spear ammo placeholder (0 until wave 4), phase name + time left, big countdown 3-2-1-GO.
- Draft UI (on `Draft.hand_dealt` for the local slot): 3 cards with name, rarity colour, category, description,
  icon if any; click to select 1–2, Confirm → `Draft.submit_pick(indices)`; timer bar; "waiting for others".
- Build HUD: restyle C08's hand list and `place_result` toast to match (read BuildPhase signals; don't edit
  `build/`, ask C08's owner via "Contract change requested" if a hook is missing).
- Style: one theme resource (`hud/hud_theme.tres`), big outlined text, player colours from `PlayerInfo.color`.
- `--screenshot=PATH` CLI on a `hud/tests/hud_preview.tscn` with fake data: renders race, draft and build HUD
  states (non-headless, 1920×1080) and saves PNGs for a visual check.

## Tests
- `hud_test.sh` (headless): `hud_preview.tscn` cycles every state with fake data, no errors, labels contain the
  expected text (`[TEST] HUD lap=2/3 pos=1st`).
- Visual (agent, few and small): run the preview with `--screenshot`, check 3 PNGs at 1080p are readable.
- Manual (user): **F6** on `game/match/match.tscn`: pick cards in the draft, race with the HUD visible.

## Finish
Handoff `docs/handoffs/C14.md`, land per AGENTS.md step 8.
