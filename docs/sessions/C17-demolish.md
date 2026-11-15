# C17 — Demolish card: remove a placed item in the Build phase
Agent: **Either** · Wave 3 · Branch: `c17-demolish`
Model: Codex **GPT-6.1 Sol, high** · or Claude **Opus 5.5, medium**
Depends on: C08, C10

Owns: `rwbl/game/build/**`, `rwbl/game/items/defs/demolish.tres`, `rwbl/game/items/tests/**` (add a case),
`tools/tests/build_test.sh`
Read: `DESIGN.md` §5.4 (Demolish) · `docs/ARCHITECTURE.md` §4 (Items, Placement, Events) · handoffs `C08`, `C10`
· `rwbl/game/items/README.md` · `rwbl/game/build/build_phase.gd`, `build_ui.gd` · `rwbl/game/common/item_def.gd`,
`place_result.gd`, `game_events.gd`

## Goal
User decision 2026-11-14: one draft card is **Demolish** (uncommon, category WILDCARD). Instead of placing, the
holder clicks any placed item (later: track piece) during Build and the host removes it on every peer.

## Steps
- Def `defs/demolish.tres` with no scene. It needs a way to say "this card targets, it doesn't place":
  **Contract change requested** for the head engineer: add `ItemDef.targets_placed := false` at the end of
  ItemDef (CONTRACT: fields at the end only). Until approved, detect it by `scene == null`.
- Build UI: holding Demolish, the ghost becomes a red highlight over the item under the mouse; click → client
  `request_demolish(uid)` RPC → host validates (holder has the card, uid exists, phase is BUILD) → removes it on
  every peer (`queue_free`, `GameEvents.item_removed(uid)`, `[Build] DEMOLISH uid by slot`) and spends the card.
  Nothing under the mouse = no-op, the card is kept. Items placed this same Build phase can be demolished too.
- Bots holding Demolish target the item nearest the leader's racing line (or skip if there are no items).
- Track pieces (wave 4 T1) can be demolished once they exist; leave a `# TODO(T1):` where that hooks in.
- Removing an item must clean up after itself: surface patches unregister on `_exit_tree` (C10 already does).

## Tests
- `build_test.sh`: place an item, demolish it from another slot → gone on host and client, `item_removed`
  emitted once; demolish without the card / outside Build / unknown uid → rejected.
- Manual (user): F6 `game/match/match.tscn` with `--free-build`, pick Demolish, click an item → it vanishes.

## Finish
Handoff `docs/handoffs/C17.md`, land per AGENTS.md step 8.
