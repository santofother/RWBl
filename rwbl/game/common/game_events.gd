extends Node
## Game-wide event bus (autoload `GameEvents`). Owner: C02 (contract). Systems emit here instead of knowing
## each other; scoring (C11), HUD (C14) and the camera (C13) mostly listen.
## Each signal says who emits it and on which peers it fires. "host" = only on the host (simulation and
## scoring are host-only); "all" = the emitter broadcasts by RPC so it fires on every peer.
## Public API: the signals below. No functions.
# CONTRACT: signal names and arguments. Add new signals freely (tell the head engineer); don't change these.

# ---------------------------------------------------------------- match flow
## all · MatchMode (C09). A new phase began (Phase.*). `round` starts at 1.
signal phase_changed(phase: int, round: int)
## host · any system. Ask MatchMode to end `phase` early (everyone picked, race over, ...).
signal phase_end_requested(phase: int)
## all · MatchMode (C09). The players array changed (e.g. a dropped player became a bot).
signal roster_changed()

# ---------------------------------------------------------------- build
## all · BuildPhase (C08). An item was spawned on the track. `uid` is unique per match.
signal item_placed(uid: int, item_id: StringName, owner_slot: int, xform: Transform3D)
## all · BuildPhase (C08) or the item itself. An item was removed (destroyed, match reset).
signal item_removed(uid: int)
## all · Track (C19). The centre line changed (a track piece was spliced in or removed). Road, walls,
## checkpoints and bounds are already rebuilt; anything caching the curve or progress values re-reads it.
signal track_changed()

# ---------------------------------------------------------------- race
## host · RaceController (C05). `slot` finished `lap` (1-based). `clean` = no collisions during that lap.
signal lap_completed(slot: int, lap: int, clean: bool)
## host · RaceController (C05). Emitted together with lap_completed when the lap was clean (+1 point).
signal clean_lap(slot: int, lap: int)
## host · RaceController (C05). `slot` crossed the finish line. `place` starts at 1.
signal chariot_finished(slot: int, place: int, race_time: float)
## host · RaceController (C05). The race ended. `finish_order` = slots in finishing order; DNFs last, by progress.
signal race_over(finish_order: Array)

# ---------------------------------------------------------------- items and combat
## host · Item (C10). The item owned by `owner_slot` affected `victim_slot` (scoring caps it per round).
signal trap_hit(item_uid: int, owner_slot: int, victim_slot: int)
## host · Combat (C12). Any chariot death. `killer_slot` = -1 when nobody; `item_uid` = -1 when no item.
signal chariot_died(slot: int, cause: StringName, killer_slot: int, item_uid: int)
## host · Combat (C12). Another player's spear or wheel attack killed `victim_slot` (+2 for the killer).
signal kill(killer_slot: int, victim_slot: int, cause: StringName)
## host · Combat (C12). `slot` died to an item it placed itself (-1).
signal self_kill(slot: int, item_uid: int)
## host · Combat (C12). A dead chariot is back on the track.
signal chariot_respawned(slot: int)

# ---------------------------------------------------------------- scoring
## all · Scoring (C11). Points of the round that just ended and the new totals. Keys are slots.
signal round_scored(round_points: Dictionary, totals: Dictionary)
