class_name RaceCamera
extends Camera3D
## Third-person chase camera behind the target chariot (DESIGN §7). Owner: C05 (v1), C13 (polish).
## Smoothed heading chase, speed FOV, drift sway from `cart_angle`, boost pullback, shake (Effects.SHAKE and
## velocity jumps, so clients see hits too), look-ahead into turns.
## C21: rolls with the road inside a loop (the view's up follows the chariot's up, smoothed by `roll_smooth`) and
## levels out after; on flat road up is exactly UP, so nothing changes there.
## The pose is updated every frame even when not `current`, so the director can swing onto it.
## NET: local only. Public API: `target`, `tuning`, `snap()`, `fov_for_speed(speed, t)`.

## What to follow (the local chariot; any chariot when spectating).
var target: Node3D
var tuning: CameraTuning = preload("res://game/camera/default_tuning.tres")

var _heading := Vector3.FORWARD
var _snap := true
var _boost := 0.0 # 0..1 smoothed
var _turn := 0.0 # smoothed signed turn rate, -1..1
var _shake := 0.0 # hit shake strength 0..1
var _last_vel := Vector3.ZERO
var _shake_t := 0.0
var _up := Vector3.UP # C21: smoothed view up (road normal in a loop)


## Forget smoothing so the next frame lands exactly on the chariot.
func snap() -> void:
	_snap = true


## FOV for a forward speed (unit-tested).
static func fov_for_speed(speed: float, t: CameraTuning) -> float:
	return lerpf(t.fov_min, t.fov_max, clampf(absf(speed) / t.ref_speed, 0.0, 1.0))


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		_snap = true
		return
	var t := tuning
	var want_up := target.global_basis.y.normalized()
	if want_up.y > 0.999 or target.get(&"_loop_fall") == true or target.get(&"dead") == true:
		want_up = Vector3.UP # WHY: exact UP on flat road keeps the old behaviour bit for bit; no roll while tumbling
	_up = want_up if _snap else _slerp_unit(_up, want_up, 1.0 - exp(-t.roll_smooth * delta))
	var fwd := -target.global_basis.z
	fwd -= _up * fwd.dot(_up)
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else _heading
	# WHY: smooth the heading by slerp so a hit-spin of the cart doesn't throw the view around
	var prev := _heading
	# FIX(C24, Claude): slerp between near-opposite or near-equal vectors errors ("axis must be normalized"); just take fwd.
	var d := _heading.dot(fwd)
	var flip := d < -0.999 or d > 0.99999
	_heading = fwd if _snap or flip else _heading.slerp(fwd, 1.0 - exp(-t.heading_smooth * delta)).normalized()
	var on_plane := _heading - _up * _heading.dot(_up)
	_heading = on_plane.normalized() if on_plane.length_squared() > 0.001 else fwd
	var yaw_rate := 0.0 # rad/s of how fast the chariot swings away from the camera heading
	if not _snap and delta > 0.0:
		yaw_rate = prev.cross(fwd).dot(_up) * t.heading_smooth
	_turn = lerpf(_turn, clampf(yaw_rate / 1.5, -1.0, 1.0), 1.0 - exp(-4.0 * delta))
	var boosting := _is_boosting()
	_boost = move_toward(_boost, 1.0 if boosting else 0.0, t.boost_smooth * delta)
	var cart := float(target.get(&"cart_angle")) if target.get(&"cart_angle") != null else 0.0
	var right := _heading.cross(_up)
	var back := t.back + t.boost_pullback * _boost
	var want := target.global_position - _heading * back + _up * t.up + right * (cart * t.sway_lateral)
	global_position = want if _snap else global_position.lerp(want, 1.0 - exp(-t.pos_smooth * delta))
	var look := target.global_position + _heading * t.look_ahead + right * (_turn * t.turn_look) + _up
	if (look - global_position).cross(_up).length_squared() > 0.0001:
		look_at(look, _up)
	rotate_object_local(Vector3.BACK, -cart * t.sway_roll)
	_update_shake(delta)
	var speed := 0.0
	if target.has_method(&"get_speed"):
		speed = float(target.call(&"get_speed"))
	var want_fov := fov_for_speed(speed, t) + t.boost_fov * _boost
	fov = want_fov if _snap else lerpf(fov, want_fov, 1.0 - exp(-t.fov_smooth * delta))
	_snap = false


static func _slerp_unit(a: Vector3, b: Vector3, w: float) -> Vector3:
	var d := a.dot(b)
	if d > 0.99999 or d < -0.999: # WHY: slerp errors on (near) equal / opposite vectors
		return b
	return a.slerp(b, w).normalized()


func _is_boosting() -> bool:
	if target.has_method(&"has_effect") and target.call(&"has_effect", Effects.BOOST):
		return true
	var f: Variant = target.get(&"_flags") # client side: flags from the last snapshot
	return f != null and (int(f) & ChariotSnapshot.FLAG_BOOSTING) != 0


func _update_shake(delta: float) -> void:
	var t := tuning
	var vel: Variant = target.get(&"velocity")
	if vel != null:
		var v: Vector3 = vel
		# WHY: `hit` only fires on the host; a sudden velocity change is visible on every peer
		if not _snap and (v - _last_vel).length() > t.shake_jump_speed:
			_shake = 1.0
		_last_vel = v
	_shake = maxf(0.0, _shake - delta / t.shake_decay)
	var s := _shake
	if target.has_method(&"has_effect") and target.call(&"has_effect", Effects.SHAKE):
		s = maxf(s, clampf(float(target.call(&"effect_strength", Effects.SHAKE)), 0.0, 1.0))
	if s > 0.0:
		_shake_t += delta * 40.0
		var o := Vector3(sin(_shake_t * 1.3), sin(_shake_t * 1.9 + 1.0), 0.0) * (s * t.shake_amount)
		global_position += global_basis * o
