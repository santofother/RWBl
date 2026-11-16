# C22 — Modular point-to-point course (track built from pieces)
Agent: **Claude preferred** · Wave 4 · Branch: `c22-modular-course`
Model: Claude **Opus 5.5, high** · or Codex **GPT-6.1 Sol, high**
Depends on: C19

Owns: `rwbl/game/track/**`, `rwbl/game/build/**`, `rwbl/game/items/defs/piece_*.tres`, `docs/ARCHITECTURE.md` §4
Track/Items lines, new `tools/tests/course_test.sh`; `tools/tests/track_piece_test.sh` (rewrite for the new model)
Read: `DESIGN.md` §5.6 (changed 2026-11-15) · `docs/ARCHITECTURE.md` §4 · handoffs `C08`, `C17`, `C19` ·
`rwbl/game/track/track.gd`, `track/pieces/track_piece.gd`, `build/build_phase.gd`, `build/build_ui.gd`

## Goal
User decision 2026-11-15: the track is an **open course** made of pieces, raced once from a start line to a
separate finish line. Round 1 = start + a few straights/corners + finish. In Build, a player **inserts a piece at
any joint between two pieces, or at the end before the finish**; everything after the joint moves along.
Replaces C19's "splice over a straight stretch" model (the user could not place pieces with it).

## Contract (approved by head engineer for this card)
- `Track` keeps every public call; `progress` = metres from the start line, `length()` = progress of the finish
  line. New: `course() -> Array[StringName]` (piece ids in order), `joints() -> Array[float]` (progress of every
  joint, start and finish included), `insert_piece(def_id, joint_index, flip) -> bool` (host validates),
  `apply_insert(uid, def_id, joint_index, flip)` (every peer, same order), `remove_piece(uid)`, `pieces()`,
  `finish_progress()`, `finish_transform()`, `is_in_no_build_zone` also covers the finish line.
  `checkpoint_progress(i)` stays (evenly spread start..finish), used for respawn only.
- `GameEvents.track_changed()` unchanged. Remove the C19 splice API (`splice_piece`, `check_splice`, ...); update
  C19's callers in `build/` only.
- `TrackPiece` unchanged (local start at 0 heading -Z) except the end may be anywhere/any heading: add
  `end_transform() -> Transform3D`. New pieces: `start.tscn`, `finish.tscn` (straights with a line and gate),
  `straight.tscn`, `corner_left.tscn`, `corner_right.tscn` (common). Keep hairpin and chicane.
- Base course: `track/default_course.tres` (a `Resource` with `pieces: Array[StringName]`), loaded by Track.
  `track.tscn` drops the hand-made loop curve. `Track.new()` (tests) loads the default course.

## Steps
- Compose the centre line by chaining each piece's points through its predecessor's `end_transform()`; road,
  side walls (pit: slab only), start line and a finish gate generated as today. Open ends: cap the road.
- Insert: reject inside the start/finish pieces, and when the new course runs into itself (2D, min distance
  `track_width + 2·wall` between non-neighbouring samples — reuse C19's `_self_intersects`).
- Items after the joint move rigidly with the course (same transform as the pieces after it); items need no
  re-validation except the gap/no-build check against the inserted piece's road (invalid → removed,
  `[Build] PIECE displaced uid`). Demolish removes a piece and closes the gap (items on it removed).
- Build UI: holding a piece, show a marker on every joint; the joint nearest the mouse highlights and the ghost
  shows the whole course as it would be after the insert (green/red + reason). R flips. LMB places.
  Make sure LMB really places (the C19 ghost had to sit exactly on a straight; test the click path headless
  through `request_piece`). Build camera re-frames to the new bounds on `track_changed`
  (`# FIX(C22, agent):` in `camera/camera_director.gd`).
- Free-build bots insert pieces at random valid joints.

## Tests
- `course_test.sh`: default course loads (start..finish, length > 300 m); insert straight/corner/hairpin/chicane
  at a middle joint and at the end → length grows by the piece length, later joints shift, finish moves; insert
  inside start/finish or a self-crossing course rejected; host + client identical `course()` and length after
  insert + client RPC insert + demolish; an item after the joint moves with the course.
- Manual (user): `--free-build --bots=3`, F6 `match.tscn`, pick Hairpin, hover the joints, click → course grows.

## Finish
Handoff `docs/handoffs/C22.md` (final API for C23/C20), land per AGENTS.md step 8.
