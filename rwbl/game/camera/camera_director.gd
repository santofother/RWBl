class_name CameraDirector
extends Node3D
## Picks the active camera per phase (DESIGN §7): top-down BuildCamera in Build, a ~1.5 s swing down onto the local
## chariot at the start of Race, the RaceCamera chase in Race, a cut elsewhere. Spectator (dead / no local chariot):
## left/right arrows cycle the followed chariot. Owner: C13. Children: RaceCamera (C05), BuildCamera (C08),
## SwingCamera (created here).
## NET: local only. Logs `[Game] CAMERA build|swing|race|spectate N`.
## Public API: match_setup(m), `race_camera`, `build_camera`, `tuning`, `swinging`, `spectate_slot`.

@onready var race_camera: RaceCamera = $RaceCamera
@onready var build_camera: BuildCamera = $BuildCamera

var tuning: CameraTuning = preload("res://game/camera/default_tuning.tres")
## True while the build -> race swing runs.
var swinging := false
## Slot being watched (-1 = own chariot).
var spectate_slot := -1

var _m: MatchMode
var _swing_cam: Camera3D
var _swing_t := 0.0
var _from := Transform3D.IDENTITY
var _from_fov := 45.0


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	race_camera.tuning = tuning
	_swing_cam = Camera3D.new()
	_swing_cam.name = "SwingCamera"
	add_child(_swing_cam)
	var panel := get_node_or_null(^"/root/TuningPanel")
	if panel:
		panel.register(tuning, "Camera")
	GameEvents.phase_changed.connect(_on_phase_changed)
	build_camera.frame(m.track.get_bounds())
	race_camera.current = true


func _process(delta: float) -> void:
	if not _m:
		return
	_update_target()
	if swinging:
		_swing_t += delta
		var k := clampf(_swing_t / tuning.swing_time, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k) # smoothstep
		var to := race_camera.global_transform
		_swing_cam.global_transform = Transform3D(
			_from.basis.slerp(to.basis, k), _from.origin.lerp(to.origin, k))
		_swing_cam.fov = lerpf(_from_fov, race_camera.fov, k)
		if _swing_t >= tuning.swing_time:
			_end_swing()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not k or not k.pressed or k.echo or not _spectating():
		return
	if k.physical_keycode == KEY_RIGHT:
		_cycle(1)
	elif k.physical_keycode == KEY_LEFT:
		_cycle(-1)


## Local player has nothing of their own to drive right now.
func _spectating() -> bool:
	if not _m or _m.phase == Phase.BUILD:
		return false
	var slot := _m.local_slot()
	var c := _m.chariot_sync.get_chariot(slot) if slot >= 0 else null
	return c == null or bool(c.get(&"dead"))


func _update_target() -> void:
	var slot := _m.local_slot()
	var mine := _m.chariot_sync.get_chariot(slot) if slot >= 0 else null
	var want: Node3D = mine
	if _spectating():
		if spectate_slot < 0 or not is_instance_valid(_m.chariot_sync.get_chariot(spectate_slot)):
			spectate_slot = _first_other(slot)
			if spectate_slot >= 0:
				print("[Game] CAMERA spectate %d" % spectate_slot)
		want = _m.chariot_sync.get_chariot(spectate_slot) if spectate_slot >= 0 else null
		if want == null:
			want = mine
	else:
		spectate_slot = -1
	if want == null:
		want = _m.chariot_sync.get_chariot(0)
	if want != race_camera.target:
		race_camera.target = want
		race_camera.snap()


func _slots() -> Array:
	var keys: Array = _m.chariot_sync.get_chariots().keys()
	keys.sort()
	return keys


func _first_other(own: int) -> int:
	for s: int in _slots():
		if s != own and not bool(_m.chariot_sync.get_chariot(s).get(&"dead")):
			return s
	return -1


func _cycle(dir: int) -> void:
	var s := _slots()
	if s.is_empty():
		return
	var i := s.find(spectate_slot)
	spectate_slot = s[posmod(i + dir, s.size())]
	print("[Game] CAMERA spectate %d" % spectate_slot)


func _on_phase_changed(phase: int, _round: int) -> void:
	if phase == Phase.BUILD:
		swinging = false
		build_camera.frame(_m.track.get_bounds())
		build_camera.current = true
		print("[Game] CAMERA build")
	elif phase == Phase.RACE and build_camera.current:
		_start_swing()
	else:
		swinging = false
		race_camera.snap()
		race_camera.current = true
		if phase == Phase.RACE:
			print("[Game] CAMERA race")


func _start_swing() -> void:
	_update_target()
	_from = build_camera.global_transform
	_from_fov = tuning.swing_start_fov
	_swing_t = 0.0
	swinging = true
	race_camera.snap()
	_swing_cam.global_transform = _from
	_swing_cam.fov = _from_fov
	_swing_cam.far = 400.0
	_swing_cam.current = true
	print("[Game] CAMERA swing")


func _end_swing() -> void:
	swinging = false
	race_camera.current = true
	print("[Game] CAMERA race")
