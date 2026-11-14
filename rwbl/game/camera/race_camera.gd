class_name RaceCamera
extends Camera3D
## Third-person chase camera behind the local chariot (DESIGN §7). Owner: C05 (v1), C13 polishes
## (speed FOV, drift sway, boost pullback). C02 STUB: plain smoothed chase.
## NET: local only. Public API: `target` (Node3D to follow).

## What to follow (the local chariot; any chariot when spectating).
var target: Node3D

const BACK := 9.0 # TUNE
const UP := 4.5 # TUNE
const SMOOTH := 6.0 # TUNE


func _process(delta: float) -> void:
	if not current or not is_instance_valid(target):
		return
	var fwd := -target.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var want := target.global_position - fwd * BACK + Vector3.UP * UP
	global_position = global_position.lerp(want, clampf(SMOOTH * delta, 0.0, 1.0))
	look_at(target.global_position + fwd * 4.0 + Vector3.UP, Vector3.UP)
