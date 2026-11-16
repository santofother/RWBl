class_name CameraDirector
extends Node3D
## Picks the active camera per phase (DESIGN §7): top-down BuildCamera in Build, a ~1.5 s swing down onto the local
## chariot at the start of Race, the RaceCamera chase in Race, a cut elsewhere. Spectator (dead / no local chariot):
## left/right arrows cycle the followed chariot. C24: after finishing the race the camera switches to spectating
## the others `FINISH_SPECTATE_AFTER` s later (V toggles back to your own chariot); while dead and waiting to
## respawn it first follows the rival closest behind your crash spot. Owner: C13. Children: RaceCamera (C05), BuildCamera (C08),
## SwingCamera (created here).
## NET: local only. Logs `[Game] CAMERA build|swing|race|spectate N`.
## Public API: match_setup(m), `race_camera`, `build_camera`, `tuning`, `swinging`, `spectate_slot`,
##   spectating_other() (C24).

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
## C24: seconds after the local player finishes before the camera starts spectating the others.
const FINISH_SPECTATE_AFTER := 2.5 # TUNE
var _finished_at := -1.0 # local clock time the local player was first seen finished, -1 = not finished
var _own_view := false # V pressed after finishing: watch your own chariot


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
	# FIX(C22, Claude): the course grows when a piece is inserted; keep the whole course in the build view.
	GameEvents.track_changed.connect(func() -> void:
		if _m.phase == Phase.BUILD:
			build_camera.update_bounds(_m.track.get_bounds())) # C24: keep the player's pan / zoom
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
	if not k or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_V and _m and _m.phase == Phase.RACE and _m.race.is_finished(_m.local_slot()):
		_own_view = not _own_view
		if _own_view:
			_finished_at = 0.0 # WHY: V again later goes straight back to spectating
		return
	if not _spectating():
		return
	if k.physical_keycode == KEY_RIGHT:
		_cycle(1)
	elif k.physical_keycode == KEY_LEFT:
		_cycle(-1)


## True while the camera follows someone else's chariot (dead, finished, or no chariot of your own).
func spectating_other() -> bool:
	return _spectating() and spectate_slot >= 0 and spectate_slot != _m.local_slot()


## Local player has nothing of their own to drive right now (dead, no chariot, or finished a while ago).
func _spectating() -> bool:
	if not _m or _m.phase == Phase.BUILD:
		return false
	var slot := _m.local_slot()
	var c := _m.chariot_sync.get_chariot(slot) if slot >= 0 else null
	if c == null or bool(c.get(&"dead")):
		return true
	if _m.phase != Phase.RACE or not _m.race.is_finished(slot):
		_finished_at = -1.0
		_own_view = false
		return false
	var now := Time.get_ticks_msec() * 0.001
	if _finished_at < 0.0:
		_finished_at = now
	return not _own_view and now - _finished_at >= FINISH_SPECTATE_AFTER


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
	# C24: dead and waiting to respawn -> watch the rival closest behind the crash spot (the one you wait for)
	var w: Dictionary = _m.combat.respawn_wait(own) if own >= 0 else {}
	if not w.is_empty():
		var best := -1
		var best_p := -INF
		for s: int in _slots():
			var ch := _m.chariot_sync.get_chariot(s)
			var p := _m.race.progress_of(s)
			if s != own and not bool(ch.get(&"dead")) and not _m.race.is_finished(s) and p < float(w["progress"]) \
					and p > best_p:
				best_p = p
				best = s
		if best >= 0:
			return best
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
