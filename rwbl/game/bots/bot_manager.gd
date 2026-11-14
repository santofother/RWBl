class_name BotManager
extends Node
## Drives every bot slot during the race through ChariotSync.submit_input() (same path as players).
## Owner: C06. NET: host only. Bot draft picks are C09's, bot item placement is C08's.
## Public API: match_setup(m), driver_for(slot), tuning, laps_of(slot).
## Logs `[Bot] LAP slot n` from its own progress tracking (independent of RaceController).

## Shared driving knobs, registered with the F2 TuningPanel.
var tuning: BotTuning = preload("res://game/bots/default_tuning.tres")

var _m: MatchMode
var _drivers: Dictionary = {} # slot -> BotDriver
var _cum: Dictionary = {} # slot -> unwrapped progress (m), grid starts behind the line (negative)
var _last: Dictionary = {} # slot -> last wrapped progress
var _laps: Dictionary = {} # slot -> laps completed


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	var panel := get_node_or_null(^"/root/TuningPanel")
	if panel:
		panel.register(tuning, "Bots")
	_refresh()
	GameEvents.roster_changed.connect(_refresh)
	GameEvents.phase_changed.connect(_on_phase_changed)


## BotDriver for a bot slot (null for humans).
func driver_for(slot: int) -> BotDriver:
	return _drivers.get(slot)


## Laps this manager has seen a bot complete in the current race.
func laps_of(slot: int) -> int:
	return _laps.get(slot, 0)


func _refresh() -> void:
	for p in _m.players:
		if p.is_bot and not _drivers.has(p.slot):
			var d := BotDriver.new()
			d.tuning = tuning
			d.seed_slot(p.slot)
			_drivers[p.slot] = d
		elif not p.is_bot:
			_drivers.erase(p.slot)


func _on_phase_changed(phase: int, _round: int) -> void:
	if phase == Phase.RACE:
		_cum.clear()
		_last.clear()
		_laps.clear()


func _physics_process(delta: float) -> void:
	if _m == null or not multiplayer.is_server() or _m.phase != Phase.RACE:
		return
	for slot: int in _drivers:
		var c := _m.chariot_sync.get_chariot(slot) as Chariot
		if c:
			_m.chariot_sync.submit_input(slot, _drivers[slot].compute_input(c, _m.track, delta))
			_track_laps(slot, c)


func _track_laps(slot: int, c: Chariot) -> void:
	var length := _m.track.length()
	var p := _m.track.progress_at(c.global_position)
	if p > length * 0.5 and not _last.has(slot):
		p -= length # grid spots are behind the line
	if not _last.has(slot):
		_cum[slot] = p
	else:
		var d := fposmod(p - float(_last[slot]) + length * 0.5, length) - length * 0.5
		if absf(d) < length * 0.25: # WHY: ignore respawn teleports
			_cum[slot] = float(_cum[slot]) + d
		else:
			_cum[slot] = p + floorf(float(_cum[slot]) / length) * length
	_last[slot] = p
	var done := int(floorf(float(_cum[slot]) / length))
	while _laps.get(slot, 0) < done:
		_laps[slot] = _laps.get(slot, 0) + 1
		print("[Bot] LAP slot %d %d" % [slot, _laps[slot]])
