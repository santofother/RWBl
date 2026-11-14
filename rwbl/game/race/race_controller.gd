class_name RaceController
extends Node
## Race phase: grid, countdown, checkpoints, laps, finish order, race end (DESIGN §3). Owner: C05.
## C02 STUB: on RACE puts every chariot on the grid; progress = distance along the track (no laps yet).
## NET: host only decides laps/finish and emits GameEvents (lap_completed, clean_lap, chariot_finished,
## race_over, then phase_end_requested(RACE)). Clients read `progress_of()` / `place_of()` from host data (C05
## syncs them for the HUD).
## Public API: match_setup(m), progress_of(slot), lap_of(slot), place_of(slot), is_finished(slot),
##   race_time(), finish_order().

var _m: MatchMode
var _start_time := 0.0


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	GameEvents.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase: int, _round: int) -> void:
	if phase != Phase.RACE:
		return
	_start_time = NetClock.now()
	if not multiplayer.is_server():
		return
	for p in _m.players:
		var c := _m.chariot_sync.get_chariot(p.slot) as Chariot
		if c:
			c.respawn(_m.track.start_transform(p.slot))
	print("[Race] Start (%d chariots)" % _m.players.size())


## Total distance driven along the track this race (laps * length + progress). TODO(C05): laps.
func progress_of(slot: int) -> float:
	var c := _m.chariot_sync.get_chariot(slot) as Chariot if _m else null
	return _m.track.progress_at(c.global_position) if c else 0.0


## Current lap, 1-based. TODO(C05)
func lap_of(_slot: int) -> int:
	return 1


## Current race position, 1 = leading. TODO(C05)
func place_of(slot: int) -> int:
	return slot + 1


## True once `slot` crossed the finish line on its last lap. TODO(C05)
func is_finished(_slot: int) -> bool:
	return false


## Seconds since the race phase began (NetClock based, same on all peers).
func race_time() -> float:
	return NetClock.now() - _start_time


## Slots that finished, in order. TODO(C05)
func finish_order() -> Array[int]:
	return []
