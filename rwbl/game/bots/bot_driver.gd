class_name BotDriver
extends RefCounted
## AI driver for one bot slot: looks at its chariot and the track and produces a ChariotInput, exactly like a
## player's keyboard would (DESIGN §11 Q6). Owner: C06.
## Follows the centre line with speed-based look-ahead, brakes for curvature ahead, whips on straights, keeps a
## lateral offset around other chariots and `blocks_path` items, and reverses out when stuck.
## Uses only public APIs of Chariot, Track, Item, so C04/C05 changes don't break it.
## NET: host only. Public API: `compute_input(chariot, track, delta) -> ChariotInput`, `tuning`, `seed_slot(slot)`,
##   `stuck_count`.

const SCAN_HZ := 10.0 # WHY: surface_at() is costly (closest-point search); lanes change slowly

## Knobs (shared by all bots, set by BotManager).
var tuning: BotTuning = preload("res://game/bots/default_tuning.tres")
## How many times this bot has got stuck.
var stuck_count := 0

var _out := ChariotInput.new()
var _offset := 0.0 # current lateral offset from the centre line (m, + = right)
var _skill := 1.0 # per-bot corner-speed multiplier
var _bias := 0.0 # per-bot lane preference (m)
var _last_progress := -1.0
var _still := 0.0
var _reverse_left := 0.0
var _reverse_steer := 0.0
var _whip_wait := 0.0
var _lane_bad := PackedInt32Array() # bad-surface samples per candidate lane, refreshed at SCAN_HZ
var _scan_wait := 0.0
var _patch_ahead := false # chosen lane still crosses a bad surface within reach


## Give this bot its personal spread (deterministic per slot).
func seed_slot(slot: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (slot + 1)
	_skill = 1.0 + rng.randf_range(-1.0, 1.0) * tuning.skill_noise * 0.15
	_bias = rng.randf_range(-1.0, 1.0) * tuning.skill_noise * 2.0


## Input for this tick.
func compute_input(chariot: Chariot, track: Track, delta: float) -> ChariotInput:
	_out.seq += 1
	_out.steer = 0.0
	_out.throttle = 0.0
	_out.brake = 0.0
	var speed := chariot.get_speed()
	var p := track.progress_at(chariot.global_position)
	var length := track.length()
	if chariot.dead or chariot.frozen:
		_still = 0.0
		_last_progress = p
		return _out
	if _reverse_left > 0.0:
		_reverse_left -= delta
		_out.brake = 1.0
		_out.steer = _reverse_steer
		if _reverse_left <= 0.0:
			_still = 0.0
		return _out
	_track_stuck(chariot, p, length, speed, delta)

	var t := tuning
	var look := t.look_base + speed * t.look_speed
	_update_offset(chariot, track, p, look, delta)
	var right := track.transform_at(p + look).basis.x
	var target := track.point_at(p + look) + right * _offset
	var local := chariot.global_transform.affine_inverse() * target
	_out.steer = clampf(atan2(local.x, -local.z) * t.steer_gain, -1.0, 1.0)

	# Curvature ahead -> wanted speed.
	var curve := _max_curve(track, p, t.preview)
	var lat := t.corner_lat_accel * _skill * (0.8 + 0.4 * t.aggression)
	var want := clampf(sqrt(lat / maxf(curve, 0.0005)), t.min_corner_speed, 60.0)
	if _patch_ahead: # WHY: no lane is clean, so cross the patch slowly instead of sliding through at full speed
		want = minf(want, t.patch_speed)
	_out.throttle = 1.0 if speed < want else 0.0
	_out.brake = 1.0 if speed > want + t.brake_margin else 0.0

	_whip_wait -= delta
	if _whip_wait <= 0.0 and chariot.stamina > t.whip_stamina and curve < t.whip_max_curve \
			and speed >= want - 0.5 and _out.brake == 0.0:
		_out.press_whip()
		_whip_wait = 0.7 + (1.0 - t.aggression) * 1.5
	return _out


func _track_stuck(chariot: Chariot, p: float, length: float, speed: float, delta: float) -> void:
	var moved := 0.0
	if _last_progress >= 0.0:
		moved = fposmod(p - _last_progress + length * 0.5, length) - length * 0.5
	_last_progress = p
	# WHY: only "no forward progress AND slow" counts; a fast chariot sliding sideways is not stuck.
	if moved < 0.5 * delta * 4.0 and speed < 2.0:
		_still += delta
	else:
		_still = maxf(0.0, _still - delta * 2.0)
	if _still >= tuning.stuck_time:
		stuck_count += 1
		_reverse_left = tuning.reverse_time
		var off := track_side(chariot)
		_reverse_steer = -signf(off) if absf(off) > 0.1 else 1.0
		print("[Bot] STUCK slot %d (%d)" % [chariot.slot, stuck_count])


# Which side of the heading the centre line is on (+ = line is to the right) -> reverse steering uses the opposite.
func track_side(chariot: Chariot) -> float:
	var track := chariot.track
	if track == null:
		return 0.0
	var local := chariot.global_transform.affine_inverse() * track.point_at(track.progress_at(chariot.global_position) + 6.0)
	return local.x


func _max_curve(track: Track, p: float, preview: float) -> float:
	var best := 0.0
	var step := preview / 4.0
	var f0 := -track.transform_at(p).basis.z
	for i in 4:
		var d := step * (i + 1)
		var f1 := -track.transform_at(p + d).basis.z
		best = maxf(best, absf(f0.signed_angle_to(f1, Vector3.UP)) / d)
	return best


func _update_offset(chariot: Chariot, track: Track, p: float, look: float, delta: float) -> void:
	var t := tuning
	var half := track.track_width * 0.5 - t.edge_margin
	var length := track.length()
	var want := clampf(_bias, -half, half)
	var my_off := track.lateral_offset(chariot.global_position)
	# Obstacles ahead: other chariots and path-blocking items, as (lateral offset, half width, distance).
	var obstacles: Array[Vector3] = []
	var parent := chariot.get_parent()
	if parent:
		for n in parent.get_children():
			var o := n as Chariot
			if o == null or o == chariot or o.dead:
				continue
			var d := fposmod(track.progress_at(o.global_position) - p + length * 0.5, length) - length * 0.5
			if d > -2.0 and d < t.traffic_range:
				obstacles.append(Vector3(track.lateral_offset(o.global_position), t.lane_gap * 0.5, d))
	for n in chariot.get_tree().get_nodes_in_group(&"items"):
		var it := n as Item
		if it == null or it.def == null or not it.def.blocks_path:
			continue
		var d := fposmod(track.progress_at(it.global_position) - p + length * 0.5, length) - length * 0.5
		if d > -2.0 and d < t.traffic_range * 1.5:
			var hw := maxf(it.def.footprint.x, it.def.footprint.y) * 0.5 + 1.2
			obstacles.append(Vector3(track.lateral_offset(it.global_position), hw, d))
	_scan_wait -= delta
	if _scan_wait <= 0.0 or _lane_bad.size() != 9:
		_scan_wait = 1.0 / SCAN_HZ
		_lane_bad.resize(9)
		for k in 9:
			_lane_bad[k] = _bad_surface_hits(track, p, lerpf(-half, half, k / 8.0), chariot.get_speed())
	# Pick the free lateral position nearest to the wanted one among candidates.
	var best := want
	var best_cost := INF
	for k in 9:
		var cand := lerpf(-half, half, k / 8.0)
		var blocked := false
		for ob in obstacles:
			if absf(cand - ob.x) < ob.y + t.lane_gap * 0.5:
				blocked = true
				break
		var bad := _lane_bad[k]
		var cost := absf(cand - want) + absf(cand - my_off) * 0.3 + (1000.0 if blocked else 0.0) \
			+ bad * t.patch_cost
		if cost < best_cost:
			best_cost = cost
			best = cand
			_patch_ahead = bad > 0
	_offset = move_toward(_offset, best, t.offset_rate * delta)


# Samples of lane `lateral` (m from the centre line) up to our reach that are not plain
# road. Public Track API only (surface_at), so it sees every patch item without knowing item ids.
func _bad_surface_hits(track: Track, p: float, lateral: float, speed: float) -> int:
	var hits := 0
	var reach := tuning.traffic_range * 1.5 + speed * 1.2 # WHY: a lane change takes ~1.5 s, so look further at speed
	var d := 4.0
	while d <= reach:
		var xf := track.transform_at(p + d)
		for side: float in [-0.9, 0.9]: # chariot is ~2 m wide
			var pos := xf.origin + xf.basis.x * (lateral + side * 1.0)
			if track.surface_at(pos) != Surface.NORMAL:
				hits += 1
				break
		d += 4.0
	return hits
