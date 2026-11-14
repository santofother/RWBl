# C08 — Build phase: top-down camera, grid/snap, ghost, rotate, placement RPC, host validation (N5)
Agent: **Either** (suggested Codex) · Tier: **T2** · Wave 2 · Branch: `c08-build-phase`
Depends on: C05

Owns: `rwbl/game/build/**`, `rwbl/game/camera/build_camera.gd`, `rwbl/game/camera/build_camera.tscn`,
`tools/tests/build_test.sh`
Read: `DESIGN.md` §5.5, §7 (Build row), §8 (build-phase line) · `docs/ARCHITECTURE.md` §2, §4 (Items, Placement,
Track) · handoffs `C02`, `C05` · `rwbl/game/build/build_phase.gd` (your stub) · `rwbl/game/common/item_def.gd`,
`place_result.gd` · headers of `rwbl/game/track/track.gd`, `rwbl/game/draft/draft.gd`, `rwbl/game/items/item.gd`,
`rwbl/game/items/item_db.gd`, `rwbl/game/match/match.gd`

## Goal
All players place their drafted items at the same time on a top-down view; the host rejects bad placements,
including any that would leave no drivable path.

## Steps
- Validation (host, `validate()` returns the first failing `PlaceResult`): phase; item in the player's hand
  (`m.draft.hand_of(slot)`, each item once; if the hand is empty because Draft is still a stub, allow any item
  when `rules.free_build` is true); budget; `ItemDef.placement`; `track.is_in_no_build_zone(pos, radius)`;
  min gap between footprints (`# TUNE` 1.5 m); sane transform (upright, on the ground, no scale).
- Path check (`build/path_validator.gd`): 1 m grid over `track.get_bounds()`, drivable = `is_on_track` minus
  footprints of every `blocks_path` item (plus the candidate), eroded by half a chariot width (~1.3 m). Treat the
  start line as a cut: flood fill from the cells just after it must reach the cells just before it. Return
  `BLOCKS_PATH` if not. Must take < 50 ms on the C05 track (log the time).
- Client UI (local only): mouse ray on `Layers.WORLD` → ghost of the selected hand item (green/red from a local
  call to the same `validate()` for preview; the host still decides), snap to a 1 m grid, Q/E rotate 15°,
  LMB place, RMB cancel, simple hand list with item names. Toast the `place_result` text
  (`PlaceResult.describe`). C14 restyles the HUD later; keep UI in `build/` scenes.
- `BuildCamera.frame(track.get_bounds())` on BUILD (already wired by `CameraDirector`). Add pan/zoom if needed.
- Bots: on BUILD the host places each bot's hand at random valid spots (try ~30 positions per item).
- Everyone placed everything → `GameEvents.phase_end_requested(BUILD)`. Items stay for the rest of the match.

## Tests
- `build_test.sh`: standalone `match.tscn --no-human --bots=2 --phase=build` plus your `--test-place=` hook
  (list of `item@progress,lateral,deg`). Expect: a valid oil slick → `OK` and `[Build] SPAWN`; on the start
  line → `NO_BUILD_ZONE`; overlapping → `TOO_CLOSE`; a row of columns across the road → the closing one
  `BLOCKS_PATH`; bots placed their items. If C03 has landed, add a host + client case where the client's request
  goes over RPC and both peers see the same items.
- Manual (user): open `game/match/match.tscn`, press **F6**, wait for the Build phase (top view), click an item,
  move the mouse (green/red ghost), Q/E rotate, click to place; try placing on the start line (red, message).

## Finish
Handoff `docs/handoffs/C08.md` (validation rules + numbers, test hook syntax), land per AGENTS.md step 8.
