# RWBL architecture

Owner: head engineer (C02). The code is the detailed spec: every contract file starts with a `##` header
listing its public API, and `# CONTRACT:` marks what other cards rely on. This page is the map.
If a card disagrees with this page, this page wins.

## 1. What runs where

```
Main (lobby/main.tscn, C03)            menu, LAN/Steam lobby, ready-up; later the hub shell
└─ Game
   └─ Match (match/match.tscn, MatchMode extends GameMode, C09)   same path on every peer
      Track · Items · Chariots · ChariotSync · Race · Draft · Build · Scoring · Combat · Bots · Cameras · Hud
```
- The lobby builds `Array[PlayerInfo]` (slots 0–4, bots fill empty slots), instances `match.tscn` on every
  peer, calls `setup(players, rules)` everywhere, then `start()` on the host. `finished(results)` fires on
  every peer, then the lobby comes back (DESIGN §9 contract, `common/game_mode.gd`).
- `setup()` calls `match_setup(m: MatchMode)` on each system in `MatchMode.SYSTEMS` order. Systems reach each
  other through typed vars on the match (`m.track`, `m.chariot_sync`, `m.race`, ...) and react to
  `GameEvents.phase_changed`. No system walks the tree or uses `get_node` on another system's children.
- **Standalone match** (all headless tests and F6 in the editor): run `match.tscn` directly. Offline counts
  as host. CLI: `--bots=N --no-human --phase=draft|build|race|score --rounds=N --laps=N --phase-time=SEC
  --autotest=SEC --quit-after=SEC`. Example: `--no-human --bots=4 --phase=race --rounds=1`.
- `game/sandbox/` (cube N1 scene) stays as the `net_test` regression scene. Main scene stays the sandbox
  until C03 switches `run/main_scene` to `lobby/main.tscn`.

## 2. Authority (different from LastMage)

| Thing | Who decides | How others see it |
|---|---|---|
| Chariots | host runs `Chariot.step(input)` | snapshots 30 Hz → clients (C07: interpolate ~100 ms, predict own lightly) |
| Inputs | each peer reads its own pad/keys (`PlayerInput`); host runs bots (`BotDriver`) | 10-byte `ChariotInput` → host `ChariotSync.submit_input()` (the only input path) |
| Phases, timers | host `MatchMode` | reliable RPC `(phase, round, end_time)`; `GameEvents.phase_changed` on all |
| Draft, placement | host validates | RPCs; host spawns items on every peer |
| Items, combat, laps, score | host | GameEvents (host) → scoring → `round_scored` RPC to all |
| Time-driven visuals (axe, gate) | nobody | every peer computes from `NetClock.now()` (host clock) |

Godot physics isn't deterministic: no lockstep, no rollback. Identity inside a match is the **slot**, never the
peer id. A peer may only send input for its own slot (host checks). Host leaving ends the match (no migration);
a client leaving turns its slot into a bot (C09). Transport: `NetworkManager` + `SteamManager` already are the
DESIGN §8 `Transport` (same signals for ENet and Steam), so there is no extra wrapper.

## 3. Folder map and owners (`rwbl/game/`)

| Folder | Owner | What | Key public API |
|---|---|---|---|
| `common/` | C02 (head) | contracts + autoloads `GameEvents`, `NetClock`; contract test | see §4 |
| `lobby/` | C03 | main menu, LAN discovery, Steam lobby, slots, ready, match launch | `main.tscn` |
| `chariot/` | C04 (C12: damage funcs + visuals) | `Chariot` controller, `ChariotTuning`, `PlayerInput`, test drive | §4 Chariot |
| `tuning/` | C04 | F2 panel autoload `TuningPanel` | `register(res, title)` |
| `track/` | C05 | `Track`: shape, surfaces, grid, checkpoints, no-build zones | §4 Track |
| `race/` | C05 | `RaceController`: countdown, laps, finish order, race end | `progress_of`, `place_of`, `lap_of` |
| `camera/` | C05 `race_camera.*`, C08 `build_camera.*`, C13 the rest (all in wave 3) | cameras + swing | `CameraDirector` |
| `bots/` | C06 | `BotManager`, `BotDriver` | `compute_input(chariot, track, delta)` |
| `net/` | C07 | `ChariotSync`: input up, snapshots down, interpolation, prediction, `--lag-ms` | §4 Sync |
| `build/` | C08 (C24: cursors, ghosts, fx) | `BuildPhase`: cursor/ghost UI, placement RPC, validation, path check, bot placing; C24 `BuildCursors` (`Match/Build/Cursors`, other players' cursors), `ItemVisual` (script-free ghosts), `PlaceFx` | §4 Items |
| `match/`, `draft/` | C09 | `MatchMode` phase loop, rounds (no cap, C16), dropouts; `Draft` dealing | §1 |
| `items/` | C10 (+ wave 4 item cards) | `Item` base, `ItemDB`, `defs/*.tres`, `tag_table.tres`, item scenes | §4 Items |
| `scoring/` | C11 | `Scoring`, score screen, anti-grief | `get_totals()` |
| `combat/` | C12 | chariot-vs-chariot rules, death → respawn, crow | GameEvents kill/self_kill |
| `hud/` | C14 | race HUD, draft cards UI, build hand + toasts | — |
| `sandbox/` | C02 (head) | N1 cube scene for `net_test` | — |

Stubs written by C02 already compile and run (oval track, arcade chariot, centre-line bots, timer phase loop),
so wave-1 cards can work in parallel. The owner replaces the stub body and keeps the API.

## 4. Contracts (files in `game/common/` unless noted)

- **Input** `chariot_input.gd`: `steer -1..1, throttle 0..1, brake 0..1, whip, action` (one-tick bools the
  sim reads), plus `whip_count/action_count/jump_count` press counters (survive packet loss) and `seq`; `jump` too.
  Wire: 10 bytes (jump_count is byte 9, added by C04 with the user's OK).
- **Snapshot** `chariot_snapshot.gd`: 15 floats `pos(3) rot quat(4) vel(3) cart_angle cart_ang_vel wheels
  stamina flags`. Packet = `[slot, 15 floats]*`. Add fields only at the end.
- **Chariot** `chariot/chariot.gd`: root `Node3D` = horse pair, forward `-Z`, named `Chariot<slot>` under
  `Match/Chariots`. `step(input, delta)` is the only mover (host; owner prediction). `get_snapshot/apply_snapshot`,
  `add_effect(Effects.*, duration, strength, source)`, `apply_impulse`, `damage_wheel(side, src)`, `stun`,
  `kill(cause, src, item_uid)`, `respawn(xform)`, `frozen`, `dead`. Signals `hit(part, other, speed)`,
  `wheel_broken`, `died(cause, src, item_uid)`, `respawned`. On host collisions with an item body it calls
  `Item.find_item(collider).chariot_hit(self, part, speed)`.
- **Surfaces / effects** `surface.gd` (`normal oil mud ice gravel offtrack`), `effects.gd` (`boost slow stun
  no_steer reverse_steer drunk shake tangled barbed`). Items pick these; only C04's controller interprets them.
- **Track** `track/track.gd` (C22): an open **course** of TrackPiece scenes chained end to start, raced once from
  the start line (progress 0, at the Track origin heading -Z) to a separate finish line. Positions are world space,
  `progress` = metres along the centre line from the start line (negative on the grid, `length()` =
  `finish_progress()` = the finish line, more in the run-off; sampling clamps at both open ends). `progress_at,
  point_at, transform_at, lateral_offset, is_on_track, surface_at, register_surface_patch(node, surface,
  half_extents), start_transform(i), checkpoint_progress(i)` (evenly spread start..finish, respawn only),
  `respawn_transform(progress), is_in_no_build_zone(pos, r)` (start and finish), `get_bounds, get_center_curve,
  finish_transform`. Course: `course() -> [piece ids]`, `joints() -> [progress]` (n + 1), `check_insert(def_id,
  joint, flip) -> Track.Insert.*` (OK UNKNOWN BAD_JOINT SELF_INTERSECT NOT_FOUND), `apply_insert(uid, def_id,
  joint, flip)` (every peer, host order), `check_remove(uid)`, `remove_piece(uid)`, `has_piece`, `piece_at`,
  `pieces() -> [{uid id start end flip joint}]`, `preview_insert`, `last_change() -> {kind from to delta
  piece_from piece_to}` (the rigid transform everything after the change moved by). Inserts go at joints
  1..n-1 only; the start/finish pieces are never removed. Base course: `track/default_course.tres`
  (`CourseDef.pieces`). After each change road/walls/caps/bounds are rebuilt and `GameEvents.track_changed()`
  fires on that peer; anything caching the curve or item progress re-reads it then.
- **Match** `game_mode.gd`, `phase.gd` (`NONE DRAFT BUILD RACE SCORE MATCH_OVER`), `match/match.gd`: rules keys
  `rounds laps win_score draft_time build_time race_time score_time start_phase`. Host drives; any system ends
  a phase early with `GameEvents.phase_end_requested(phase)`.
- **Players** `player_info.gd` (`slot peer_id name color is_bot steam_id`, bots: `peer_id 1`),
  `player_result.gd` (`slot name score place stats`). Both have `to_dict/from_dict` for RPCs.
- **Events** `game_events.gd` (autoload): `phase_changed, phase_end_requested, roster_changed, item_placed,
  item_removed, lap_completed, clean_lap, chariot_finished, race_over, trap_hit, chariot_died, kill,
  self_kill, chariot_respawned, round_scored`. Each line in the file says who emits it and on which peers.
- **Items** `item_def.gd` (`id rarity category tags footprint placement blocks_path rotatable cost scene icon
  piece piece_length`; C19/C22: `piece != null` = track piece card, `category` PIECE, `scene` null,
  `piece_length` = its road length, inserted with `BuildPhase.request_piece(id, joint, flip)`, shares the item
  uid counter so Demolish removes it and the gap closes),
  `tag_rule.gd`/`tag_table.gd` (`lookup(tags_a, tags_b) -> rules`, order-insensitive), `items/item.gd` hooks
  `placed, race_started, race_ended, triggered, chariot_entered (Area3D "Trigger"), chariot_hit, interact`,
  helpers `report_hit(victim)` (→ `trap_hit`), `trigger()` (RPC to all). `items/item_db.gd` finds every
  `items/defs/<id>.tres`: adding an item = one def + one scene.
- **Placement** `build/build_phase.gd` + `place_result.gd`: client `request_place(item_id, xform)` → host
  `validate()` → `PlaceResult.*` code back to the requester; OK spawns `Item<uid>` under `Match/Items` on every
  peer and emits `item_placed`. Bots: host `place_for_slot(slot, item_id, xform)`.
- **Clock** `net_clock.gd` (autoload): `now()` = host seconds on every peer.
- **Tuning**: every gameplay number lives in a `Resource` with `@export_range` fields (`ChariotTuning`,
  later `MatchTuning`, `ScoreTable`, `BotTuning`, `CameraTuning`) registered with `TuningPanel.register()`.

## 5. Project settings (C02 owns `project.godot`; C03 may change `run/main_scene` only)

- **Autoloads:** NetworkManager, SteamManager, VoiceManager, DebugOverlay, GraphicsSettings (`core/`),
  GameEvents, NetClock (`game/common/`), TuningPanel (`game/tuning/`). `core/` never references `game/`.
- **Input map:** `steer_left/right` (A/D, ←/→, left stick X), `throttle` (W, ↑, RT), `brake` (S, ↓, LT),
  `whip` (Shift, pad A), `jump` (Space, pad Y), `action` (F, pad X), `build_rotate_left/right` (Q/E, LB/RB), `build_place` (LMB,
  Enter, pad A), `build_cancel` (RMB, Esc, pad B), `toggle_tuning` (F2). F3 = debug overlay (core, hard-coded).
- **Physics layers** (`common/layers.gd`): 1 world, 2 wall, 3 horses, 4 cart, 5 item_solid, 6 item_trigger,
  7 projectile, 8 pickup.

## 6. Tests

`tools/run_tests.sh` runs everything. `contract_test.sh` checks every class/signal above exists and the stubs
behave, then runs a 4-bot standalone match to `MATCH FINISHED`. Builders add their own `tools/tests/<x>_test.sh`
and may add contract checks, never remove them. Use `[Race] [Build] [Draft] [Score] [Item] [Bot] [Game] [Net]`
log prefixes; tests grep them.
