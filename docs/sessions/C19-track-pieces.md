# C19 — Track pieces framework + hairpin and chicane
Agent: **Claude preferred** · Wave 4 · Branch: `c19-track-pieces`
Model: Claude **Opus 5.5, high** · or Codex **GPT-6.1 Sol, high**
Depends on: C17 (both edit the Build phase), C16

Owns: `rwbl/game/track/**`, new `rwbl/game/track/pieces/**`, `rwbl/game/build/**` (piece placement only),
`rwbl/game/items/defs/piece_*.tres`, `rwbl/game/common/item_def.gd` + `game_events.gd` (append-only, see
Contract), `docs/ARCHITECTURE.md` §4 Track/Items lines for the new API, new `tools/tests/track_piece_test.sh`
Read: `DESIGN.md` §5.5, §5.6 · `docs/ARCHITECTURE.md` §4 · handoffs `C05`, `C06`, `C08`, `C17` ·
`rwbl/game/track/track.gd`, `rwbl/game/build/build_phase.gd`, `path_validator.gd` · header of `bots/bot_driver.gd`

## Goal
Cards that change how the track looks (user, 2026-11-14). A **track piece** card replaces a section of road.
Drafted like items (same hand, rarity weights), placed in Build, stays for the rest of the match.

## Contract (approved by head engineer for this card)
- `ItemDef`: append `piece: PackedScene = null` and `piece_length := 0.0` (m of centre line it replaces). A def with
  `piece != null` is a track piece; `category` = new enum value `PIECE` appended at the end.
- `Track`: `splice_piece(def_id, start_progress) -> bool` (host validates, every peer applies the same splice in
  the same order), `pieces() -> Array` (for late joiners/tests). After a splice: rebuild road, walls, checkpoints,
  bounds; `progress` stays metres from the start line along the new curve.
- `GameEvents.track_changed()` (every peer, after a splice). Bots, race progress and cameras re-read the curve on it.

## Steps
- A piece = a short local `Curve3D` (in `pieces/<id>.tres` or built in code) that starts and ends on the old
  centre line's heading, so the loop stays closed. Splice: cut `[start, start+piece_length]`, insert the piece's
  points (transformed), smooth the joints. Start/finish straight and the no-build zone can't be replaced.
- Build: holding a piece card, the ghost is a translucent road outline that snaps along the centre line (mouse →
  `progress_at`), R flips left/right where it makes sense. Host checks: not in no-build zone, doesn't overlap
  another piece, new road doesn't self-intersect (min distance between non-adjacent samples > track_width).
- Items on the replaced section: move them to the same progress + lateral offset on the new road; if that's
  invalid, remove them (`item_removed`) and log `[Build] PIECE displaced uid`.
- Pieces: **hairpin** (≈180° tight U and back, rare) and **chicane** (left-right S, uncommon). Greybox meshes from
  the existing road generator.
- Demolish can remove a piece (resolve C17's `# TODO(T1):`): restore the original section.
- `PathValidator`, bots (`compute_input` follows the curve), checkpoints and respawn follow the new shape; fix
  where they cache the curve (`# FIX(C19, agent):` if outside owned files).

## Tests
- `track_piece_test.sh`: splice hairpin → curve still closed, length grew, checkpoints monotonic; illegal splices
  (start line, overlap, self-intersection) rejected; host + client have identical `pieces()` and length; 3 bots
  finish a lap on the spliced track (`bot_race` style); an item on the section is moved or removed.
- Manual (user): F6 `game/match/match.tscn` with `-- --free-build --bots=3`, pick Hairpin, drag it along the
  road, click → road reshapes; race it.

## Finish
Handoff `docs/handoffs/C19.md` (list the final API so C20 can build on it), land per AGENTS.md step 8.
