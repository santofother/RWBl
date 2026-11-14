class_name RaceCamera
extends Camera3D
## Third-person chase camera behind the target chariot (DESIGN §7). Owner: C05 (v1), C13 polishes
## (drift sway, boost pullback, build -> race swing).
## v1: sits behind the chariot's heading (smoothed so it doesn't whip on bumps), looks slightly ahead, FOV widens
## with speed.
## NET: local only. Public API: `target` (Node3D to follow; any chariot when spectating).

## What to follow (the local chariot; any chariot when spectating).
var target: Node3D

const BACK := 9.0 # TUNE: metres behind the chariot
const UP := 4.5 # TUNE: metres above
const LOOK_AHEAD := 5.0 # TUNE
const POS_SMOOTH := 7.0 # TUNE: higher = tighter follow
const HEADING_SMOOTH := 4.0 # TUNE: how fast the camera swings round behind a turning chariot
const FOV_MIN := 68.0 # TUNE: degrees at a standstill
const FOV_MAX := 88.0 # TUNE: degrees at REF_SPEED
const REF_SPEED := 22.0 # TUNE: m/s that counts as "full speed" for the FOV (default max_speed)
const FOV_SMOOTH := 3.0 # TUNE

var _heading := Vector3.FORWARD
var _snap := true


func _process(delta: float) -> void:
	if not current or not is_instance_valid(target):
		_snap = true
		return
	var fwd := -target.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else _heading
	# WHY: smooth the heading by slerp so a hit-spin of the cart doesn't throw the view around
	_heading = fwd if _snap else _heading.slerp(fwd, 1.0 - exp(-HEADING_SMOOTH * delta)).normalized()
	var want := target.global_position - _heading * BACK + Vector3.UP * UP
	global_position = want if _snap else global_position.lerp(want, 1.0 - exp(-POS_SMOOTH * delta))
	look_at(target.global_position + _heading * LOOK_AHEAD + Vector3.UP, Vector3.UP)
	var speed := 0.0
	if target.has_method(&"get_speed"):
		speed = absf(float(target.call(&"get_speed")))
	var want_fov := lerpf(FOV_MIN, FOV_MAX, clampf(speed / REF_SPEED, 0.0, 1.0))
	fov = want_fov if _snap else lerpf(fov, want_fov, 1.0 - exp(-FOV_SMOOTH * delta))
	_snap = false
