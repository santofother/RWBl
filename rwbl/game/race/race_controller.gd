class_name RaceController
extends Node
## Race phase: grid, countdown, checkpoints, laps, finish order, race end (DESIGN §3). Owner: C05.
## NET: host only decides laps/finish and emits GameEvents (lap_completed, clean_lap, chariot_finished,
## race_over, then phase_end_requested(RACE) 3 s later). The host pushes lap/place/finish state to clients by
## RPC at STATE_HZ so `progress_of()` / `place_of()` / `lap_of()` / `is_finished()` read the same on every peer.
## Public API: match_setup(m), progress_of(slot), lap_of(slot), place_of(slot), is_finished(slot),
##   finish_time_of(slot), race_time(), countdown_left(), is_racing(), finish_order(), notify_teleport(slot).
## Logs: `[Race] Start`, `[Race] GO`, `[Race] LAP slot lap clean`, `[Race] FINISH slot place time`, `[Race] OVER ...`.
# CONTRACT: checkpoints are crossed in order 1..n-1 then the start line (cp 0) ends the lap; skipping one never
#   counts, so teleporting ahead does not complete a lap. progress_of() = laps_done * length + progress.

## Seconds of frozen countdown before GO.
const COUNTDOWN := 3.0 # TUNE
## Seconds between race_over and the phase end request.
const END_DELAY := 3.0 # TUNE
## Host -> clients HUD sync rate.
const STATE_HZ := 4.0
## A checkpoint only counts when crossed with a per-tick move below this (m); bigger jumps are teleports.
const MAX_STEP := 20.0

var _m: MatchMode
var _start_time := 0.0 # NetClock time the phase began
var _go_time := 0.0 # NetClock time of GO
var _racing := false # GO happened and the race is not over
var _over := false
var _end_at := -1.0
var _laps := 1
var _order: Array[int] = []
## slot -> {lap, place, finished, progress, time}. Host writes it every tick; clients get it by RPC.
var _state: Dictionary = {}
## Host-only per-slot tracking.
var _u: Dictionary = {} # slot -> unwrapped progress (m, negative behind the line)
var _next_target: Dictionary = {} # slot -> unwrapped progress of the next checkpoint to cross
var _next_cp: Dictionary = {} # slot -> next checkpoint index (1..n, n = the start line)
var _laps_done: Dictionary = {}
var _dirty: Dictionary = {} # slot -> true if the chariot was hit this lap
var _hooked: Dictionary = {} # slot -> true once the `hit` signal is connected
var _sync_accum := 0.0


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
	_laps = maxi(int(_m.rules.get("laps", 1)), 1)
	if not multiplayer.is_server():
		return
	_u.clear()
	_next_target.clear()
	_next_cp.clear()
	_laps_done.clear()
	_dirty.clear()
	var total := _m.track.length()
	for p in _m.players:
		var c := _m.chariot_sync.get_chariot(p.slot) as Chariot
		if c == null:
			continue
		c.respawn(_m.track.start_transform(p.slot))
		c.frozen = true
		if not _hooked.has(p.slot):
			_hooked[p.slot] = true
			c.hit.connect(_on_hit.bind(p.slot))
		_u[p.slot] = _wrapped(_m.track.progress_at(c.global_position), total)
		_next_cp[p.slot] = 1
		_laps_done[p.slot] = 0
		_next_target[p.slot] = _target(p.slot, 1)
		_dirty[p.slot] = false
		_state[p.slot] = {"lap": 1, "place": p.slot + 1, "finished": false, "progress": 0.0, "time": 0.0}
	print("[Race] Start (%d chariots, %d laps)" % [_m.players.size(), _laps])


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


## Total distance driven along the track this race (laps * length + progress), m. 0 before the line.
func progress_of(slot: int) -> float:
	return float(_state.get(slot, {}).get("progress", 0.0))


## Current lap, 1-based (stays at the last lap once finished).
func lap_of(slot: int) -> int:
	return int(_state.get(slot, {}).get("lap", 1))


## Current race position, 1 = leading. Finished chariots keep their finishing place.
func place_of(slot: int) -> int:
	return int(_state.get(slot, {}).get("place", slot + 1))


## True once `slot` crossed the finish line on its last lap.
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


## Tell the race a chariot was moved on purpose (respawn): resync its tracked progress without counting
## checkpoints. NET: host. TODO(C12): Combat's respawn should call this.
func notify_teleport(slot: int) -> void:
	var c := _m.chariot_sync.get_chariot(slot) as Chariot if _m else null
	if c and _u.has(slot):
		var total := _m.track.length()
		var cur := _wrapped(_m.track.progress_at(c.global_position), total)
		_u[slot] = _nearest_unwrapped(cur, float(_u[slot]), total)


# ---------------------------------------------------------------- host logic

func _target(slot: int, cp: int) -> float:
	var total := _m.track.length()
	return float(_laps_done[slot]) * total + total * float(cp) / float(_m.track.checkpoint_count())


func _wrapped(p: float, total: float) -> float: # progress 0..total -> -total/2..total/2 (grid spots are behind the line)
	return p - total if p > total * 0.5 else p


func _nearest_unwrapped(cur: float, ref: float, total: float) -> float:
	return cur + roundf((ref - cur) / total) * total


func _on_hit(_part: StringName, _other: Node, _speed: float, slot: int) -> void:
	if _racing:
		_dirty[slot] = true


func _track_chariots(now: float) -> void:
	var total := _m.track.length()
	var n := _m.track.checkpoint_count()
	for slot: int in _u:
		var st: Dictionary = _state[slot]
		if st["finished"]:
			continue
		var c := _m.chariot_sync.get_chariot(slot) as Chariot
		if c == null:
			continue
		var last: float = _u[slot]
		var cur := _nearest_unwrapped(_wrapped(_m.track.progress_at(c.global_position), total), last, total)
		_u[slot] = cur
		var step := absf(cur - last)
		var target: float = _next_target[slot]
		if last < target and cur >= target and step < MAX_STEP:
			var cp: int = _next_cp[slot]
			if cp == n: # crossed the start line: lap done
				_laps_done[slot] = int(_laps_done[slot]) + 1
				var lap: int = _laps_done[slot]
				var clean := not bool(_dirty[slot])
				_dirty[slot] = false
				print("[Race] LAP %d %d %s" % [slot, lap, "clean" if clean else "dirty"])
				GameEvents.lap_completed.emit(slot, lap, clean)
				if clean:
					GameEvents.clean_lap.emit(slot, lap)
				_next_cp[slot] = 1
				if lap >= _laps:
					var t := now - _go_time
					_order.append(slot)
					st["finished"] = true
					st["time"] = t
					st["place"] = _order.size()
					print("[Race] FINISH %d %d %.2f" % [slot, _order.size(), t])
					GameEvents.chariot_finished.emit(slot, _order.size(), t)
					continue
			else:
				_next_cp[slot] = cp + 1
			_next_target[slot] = _target(slot, _next_cp[slot])
		st["progress"] = maxf(0.0, cur)
		st["lap"] = mini(int(_laps_done[slot]) + 1, _laps)


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
