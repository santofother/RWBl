extends Node
## Test driver for tools/tests/chariot_net_test.sh, added under ChariotSync by CLI `--net-autotest`. Owner: C07.
## Host: prints `[TEST] POSAT t slot x z` for every chariot at each SAMPLE_STEP multiple of NetClock.now()
##   during the race (interpolated between physics ticks), and `[TEST] FINAL slot x z` at GO + FINAL_AT.
## Client: drives its own chariot with a script (bot steering from GO + START_AT to GO + DRIVE_UNTIL, then brakes
##   to a stop and idles), prints POSAT for the *remote* chariots from ChariotSync.sample_remote() at the same
##   NetClock grid times, `[TEST] RESPONSE ticks=N` (physics ticks from the first throttle input to the first
##   predicted movement), FINAL for its own slot and `[TEST] NETSTATS ...`.
## NET: every peer (test only). Public API: setup(sync, m).

const SAMPLE_STEP := 0.25
const START_AT := 0.5
const DRIVE_UNTIL := 4.0
const FINAL_AT := 6.6

var _sync: ChariotSync
var _m: MatchMode
var _go := -1.0
var _next_g := 0.0
var _done := false
var _bot := BotDriver.new()
var _out := ChariotInput.new()
var _prev_t := -1.0
var _prev_pos: Dictionary = {} # host: slot -> Vector3 at _prev_t
var _resp_tick := -1
var _resp_pos := Vector3.ZERO
var _resp_done := false


## Hook into the match; clients take over their own input source.
func setup(sync: ChariotSync, m: MatchMode) -> void:
	_sync = sync
	_m = m
	if not multiplayer.is_server():
		_sync.local_input_source = _script_input
		_bot.seed_slot(_sync.local_slot)


func _physics_process(_delta: float) -> void:
	if _done or _m == null or _m.phase != Phase.RACE:
		return
	var now := NetClock.now()
	if _go < 0.0:
		_go = now + _m.race.countdown_left()
		_next_g = ceilf((_go + START_AT) / SAMPLE_STEP) * SAMPLE_STEP
	if multiplayer.is_server():
		_host_samples(now)
	else:
		_client_samples()
		_check_response()
	if now >= _go + FINAL_AT:
		_done = true
		_final()


func _host_samples(now: float) -> void:
	var cur: Dictionary = {}
	for slot: int in _sync.get_chariots():
		cur[slot] = (_sync.get_chariot(slot) as Node3D).global_position
	if _prev_t > 0.0:
		while _next_g <= now and _next_g <= _go + FINAL_AT:
			var f := clampf((_next_g - _prev_t) / maxf(now - _prev_t, 0.0001), 0.0, 1.0)
			for slot: int in cur:
				var p: Vector3 = (_prev_pos.get(slot, cur[slot]) as Vector3).lerp(cur[slot], f)
				print("[TEST] POSAT %.2f %d %.3f %.3f" % [_next_g, slot, p.x, p.z])
			_next_g += SAMPLE_STEP
	_prev_t = now
	_prev_pos = cur


func _client_samples() -> void:
	while _sync.render_time() >= _next_g + 0.02 and _next_g <= _go + FINAL_AT:
		for slot: int in _sync.get_chariots():
			if slot == _sync.local_slot:
				continue
			var s := _sync.sample_remote(slot, _next_g)
			if s.size() >= ChariotSnapshot.SIZE:
				var p := ChariotSnapshot.pos(s)
				print("[TEST] POSAT %.2f %d %.3f %.3f" % [_next_g, slot, p.x, p.z])
		_next_g += SAMPLE_STEP


func _check_response() -> void:
	if _resp_done or _resp_tick < 0:
		return
	var c := _sync.get_chariot(_sync.local_slot)
	if c and c.global_position.distance_to(_resp_pos) > 0.001:
		_resp_done = true
		print("[TEST] RESPONSE ticks=%d" % (Engine.get_physics_frames() - _resp_tick))


func _final() -> void:
	for slot: int in _sync.get_chariots():
		if multiplayer.is_server() or slot == _sync.local_slot:
			var p := (_sync.get_chariot(slot) as Node3D).global_position
			print("[TEST] FINAL %d %.3f %.3f" % [slot, p.x, p.z])
	print("[TEST] NETSTATS rtt=%.0f interp=%.0f in=%.2f out=%.2f" % [_sync.rtt_ms, _sync.interp_delay * 1000.0,
		_sync.kbps_in, _sync.kbps_out])


## Scripted driving for the own slot (client). Press counters are kept across phases (no fake taps).
func _script_input(slot: int) -> ChariotInput:
	var c := _sync.get_chariot(slot) as Chariot
	_out.steer = 0.0
	_out.throttle = 0.0
	_out.brake = 0.0
	if c == null or _go < 0.0:
		return _out
	var t := NetClock.now() - _go
	if t >= START_AT and t < DRIVE_UNTIL:
		var b := _bot.compute_input(c, _m.track, get_physics_process_delta_time())
		_out.steer = b.steer
		_out.throttle = b.throttle
		_out.brake = b.brake
		if _resp_tick < 0 and b.throttle > 0.0:
			_resp_tick = Engine.get_physics_frames()
			_resp_pos = c.global_position
	elif t >= DRIVE_UNTIL and c.get_speed() > 0.6:
		_out.brake = 1.0
	return _out
