class_name BotManager
extends Node
## Drives every bot slot during the race through ChariotSync.submit_input() (same path as players).
## Owner: C06. NET: host only. Bot draft picks are C09's, bot item placement is C08's.
## Public API: match_setup(m), driver_for(slot).

var _m: MatchMode
var _drivers: Dictionary = {} # slot -> BotDriver


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	_refresh()
	GameEvents.roster_changed.connect(_refresh)


## BotDriver for a bot slot (null for humans).
func driver_for(slot: int) -> BotDriver:
	return _drivers.get(slot)


func _refresh() -> void:
	for p in _m.players:
		if p.is_bot and not _drivers.has(p.slot):
			_drivers[p.slot] = BotDriver.new()
		elif not p.is_bot:
			_drivers.erase(p.slot)


func _physics_process(delta: float) -> void:
	if _m == null or not multiplayer.is_server() or _m.phase != Phase.RACE:
		return
	for slot: int in _drivers:
		var c := _m.chariot_sync.get_chariot(slot) as Chariot
		if c:
			_m.chariot_sync.submit_input(slot, _drivers[slot].compute_input(c, _m.track, delta))
