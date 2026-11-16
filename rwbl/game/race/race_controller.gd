class_name RaceController
extends Node
## Race phase: grid, countdown, one run from the start line to the finish line, finish order, race end
## (DESIGN §3, §5.6; C23: no laps, shortcuts count). Owner: C05 (C23 rules).
## NET: host only decides finish and emits GameEvents (clean_lap once at the finish for a run without collisions,
## chariot_finished, race_over, then phase_end_requested(RACE) 3 s later). The host pushes place/finish state to
## clients by RPC at STATE_HZ so `progress_of()` / `place_of()` / `is_finished()` read the same on every peer.
## Public API: match_setup(m), progress_of(slot), lap_of(slot) (always 1), place_of(slot), is_finished(slot),
##   finish_time_of(slot), race_time(), countdown_left(), is_racing(), finish_order(), notify_teleport(slot),
##   to_go(slot) (m left to the finish line).
## Logs: `[Race] Start`, `[Race] GO`, `[Race] CLEAN slot`, `[Race] FINISH slot place time`, `[Race] OVER ...`.
# CONTRACT: race position = Track.progress_at (how far along the course), however the chariot got there
#   (shortcuts count). A chariot finishes when it crosses the finish line plane (Track.finish_progress()) driving
#   forward, inside the road, in one normal tick (a teleport across the line does not count).

## Seconds of frozen countdown before GO.
const COUNTDOWN := 3.0 # TUNE
## Seconds between race_over and the phase end request.
const END_DELAY := 3.0 # TUNE
## Host -> clients HUD sync rate.
const STATE_HZ := 4.0
## The finish line only counts when crossed with a per-tick move below this (m); bigger jumps are teleports.
const MAX_STEP := 20.0
## Seconds a dead chariot waits before this controller puts it back on the track. TODO(C12): Combat's respawn
## replaces this; remove `_respawn_dead()` then.
const RESPAWN_DELAY := 2.0 # TUNE

var _m: MatchMode
var _start_time := 0.0 # NetClock time the phase began
var _go_time := 0.0 # NetClock time of GO
var _racing := false # GO happened and the race is not over
var _over := false
var _end_at := -1.0
var _order: Array[int] = []
## slot -> {lap, place, finished, progress, time}. Host writes it every tick; clients get it by RPC.
var _state: Dictionary = {}
## Host-only per-slot tracking.
var _u: Dictionary = {} # slot -> progress along the course (m, negative behind the line)
var _dirty: Dictionary = {} # slot -> true if the chariot was hit this run
var _hooked: Dictionary = {} # slot -> true once the `hit` signal is connected
var _sync_accum := 0.0
var _dead_since: Dictionary = {} # slot -> NetClock time it was seen dead


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	GameEvents.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase: int, _round: int) -> void:
	_racing = false
	if phase != Phase.RACE:
		return
	_start_time = NetClock.now()
	_go_time = _start_time + COUNTDOWN
	_over = false
	_end_at = -1.0
	_order.clear()
	_state.clear()
	if not multiplayer.is_server():
		return
	_u.clear()
	_dirty.clear()
	_dead_since.clear()
	for p in _m.players:
		var c := _m.chariot_sync.get_chariot(p.slot) as Chariot
		if c == null:
			continue
		c.respawn(_m.track.start_transform(p.slot))
		c.frozen = true
		if not _hooked.has(p.slot):
			_hooked[p.slot] = true
			c.hit.connect(_on_hit.bind(p.slot))
		_u[p.slot] = _m.track.progress_at(c.global_position)
		_dirty[p.slot] = false
		_state[p.slot] = {"lap": 1, "place": p.slot + 1, "finished": false, "progress": 0.0, "time": 0.0}
	print("[Race] Start (%d chariots, %.0f m to the finish)" % [_m.players.size(), _m.track.finish_progress()])


func _physics_process(_delta: float) -> void:
	if _m == null or _m.phase != Phase.RACE or not multiplayer.is_server():
		return
	var now := NetClock.now()
	if not _racing and not _over and now >= _go_time:
		_racing = true
		for p in _m.players:
			var c := _m.chariot_sync.get_chariot(p.slot) as Chariot
			if c:
				c.frozen = false
		print("[Race] GO")
	if _racing:
		_track_chariots(now)
	_update_places()
	if _racing and not _over:
		if _order.size() >= _state.size() and not _state.is_empty():
			_end_race()
		elif now >= _m.phase_end_time - 0.2: # WHY: MatchMode times the phase out itself; report before it does
			_end_race()
			_end_at = now
	if _end_at >= 0.0 and now >= _end_at:
		_end_at = -1.0
		GameEvents.phase_end_requested.emit(Phase.RACE)
	_sync_accum += _delta
	if _sync_accum >= 1.0 / STATE_HZ:
		_sync_accum = 0.0
		_push_state()


## How far along the course `slot` is (m from the start line, 0 before it).
func progress_of(slot: int) -> float:
	return float(_state.get(slot, {}).get("progress", 0.0))


## Always 1 (C23: one run per race, no laps). Kept for old callers.
func lap_of(slot: int) -> int:
	return int(_state.get(slot, {}).get("lap", 1))


## Current race position, 1 = leading. Finished chariots keep their finishing place.
func place_of(slot: int) -> int:
	return int(_state.get(slot, {}).get("place", slot + 1))


## Metres left to the finish line (0 once finished).
func to_go(slot: int) -> float:
	if is_finished(slot) or _m == null:
		return 0.0
	return maxf(0.0, _m.track.finish_progress() - progress_of(slot))


## True once `slot` crossed the finish line.
func is_finished(slot: int) -> bool:
	return bool(_state.get(slot, {}).get("finished", false))


## Race time (s, from GO) at which `slot` finished, or 0.
func finish_time_of(slot: int) -> float:
	return float(_state.get(slot, {}).get("time", 0.0))


## Seconds since the race phase began (NetClock based, same on all peers).
func race_time() -> float:
	return NetClock.now() - _start_time


## Seconds of countdown left (0 once GO happened). Same on all peers (NetClock).
func countdown_left() -> float:
	return maxf(0.0, _go_time - NetClock.now()) if _m and _m.phase == Phase.RACE else 0.0


## True between GO and the end of the race.
func is_racing() -> bool:
	return _racing


## Slots that finished, in order (host; clients see `is_finished` / `place_of`).
func finish_order() -> Array[int]:
	return _order


## Tell the race a chariot was moved on purpose (respawn): resync its tracked progress without crossing the
## finish line. NET: host.
func notify_teleport(slot: int) -> void:
	var c := _m.chariot_sync.get_chariot(slot) as Chariot if _m else null
	if c and _u.has(slot):
		_u[slot] = _m.track.progress_at(c.global_position)


# ---------------------------------------------------------------- host logic

func _on_hit(_part: StringName, _other: Node, _speed: float, slot: int) -> void:
	if _racing:
		_dirty[slot] = true


func _track_chariots(now: float) -> void:
	var track := _m.track
	var finish := track.finish_progress()
	for slot: int in _u:
		var st: Dictionary = _state[slot]
		if st["finished"]:
			continue
		var c := _m.chariot_sync.get_chariot(slot) as Chariot
		if c == null:
			continue
		if c.dead:
			continue # FIX(C12, Claude): Combat respawns dead chariots now
		var last: float = _u[slot]
		var cur := track.progress_at(c.global_position)
		_u[slot] = cur
		if last < finish and cur >= finish and absf(cur - last) < MAX_STEP and _crossed_finish(c):
			var t := now - _go_time
			_order.append(slot)
			st["finished"] = true
			st["time"] = t
			st["place"] = _order.size()
			st["progress"] = finish
			if not bool(_dirty[slot]):
				print("[Race] CLEAN %d" % slot)
				GameEvents.clean_lap.emit(slot, 1)
			print("[Race] FINISH %d %d %.2f" % [slot, _order.size(), t])
			GameEvents.chariot_finished.emit(slot, _order.size(), t)
			continue
		st["progress"] = clampf(cur, 0.0, finish)


## Inside the road at the line and moving forward (not touching the finish piece from the side or from behind).
func _crossed_finish(c: Chariot) -> bool:
	var track := _m.track
	var ft := track.finish_transform()
	if absf((c.global_position - ft.origin).dot(ft.basis.x)) > track.track_width * 0.5 + 1.0:
		return false
	return c.velocity.dot(-ft.basis.z) > 0.0


func _update_places() -> void:
	var slots: Array = _state.keys()
	var running: Array = slots.filter(func(s: int) -> bool: return not _state[s]["finished"])
	running.sort_custom(func(a: int, b: int) -> bool:
		var pa: float = _state[a]["progress"]
		var pb: float = _state[b]["progress"]
		return pa > pb if not is_equal_approx(pa, pb) else a < b)
	for i in running.size():
		_state[running[i]]["place"] = _order.size() + i + 1


func _end_race() -> void:
	_over = true
	_racing = false
	var out: Array = _order.duplicate()
	var rest: Array = _state.keys().filter(func(s: int) -> bool: return not _state[s]["finished"])
	rest.sort_custom(func(a: int, b: int) -> bool: return _state[a]["progress"] > _state[b]["progress"])
	out.append_array(rest)
	print("[Race] OVER order=%s finished=%d" % [str(out), _order.size()])
	GameEvents.race_over.emit(out)
	_end_at = NetClock.now() + END_DELAY
	_push_state()


# ---------------------------------------------------------------- HUD sync

func _push_state() -> void: # NET: host
	if multiplayer.get_peers().is_empty():
		return
	var packet := PackedFloat32Array()
	for slot: int in _state:
		var s: Dictionary = _state[slot]
		packet.append_array([slot, s["lap"], s["place"], 1.0 if s["finished"] else 0.0, s["progress"], s["time"]])
	_rpc_state.rpc(_go_time, packet)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_state(go_time: float, packet: PackedFloat32Array) -> void: # NET: clients
	_go_time = go_time
	for i in range(0, packet.size() - 5, 6):
		_state[int(packet[i])] = {"lap": int(packet[i + 1]), "place": int(packet[i + 2]),
			"finished": packet[i + 3] > 0.5, "progress": packet[i + 4], "time": packet[i + 5]}
