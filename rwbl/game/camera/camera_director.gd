class_name CameraDirector
extends Node3D
## Picks the active camera per phase and (C13) animates the swing between the build and race views
## (DESIGN §7). Owner: C13. C02 STUB: hard cut. Children: RaceCamera (C05), BuildCamera (C08).
## NET: local only. Public API: match_setup(m), `race_camera`, `build_camera`.

@onready var race_camera: RaceCamera = $RaceCamera
@onready var build_camera: BuildCamera = $BuildCamera

var _m: MatchMode


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	GameEvents.phase_changed.connect(_on_phase_changed)
	build_camera.frame(m.track.get_bounds())
	race_camera.current = true


func _process(_delta: float) -> void:
	if _m and not is_instance_valid(race_camera.target):
		var slot := _m.local_slot()
		race_camera.target = _m.chariot_sync.get_chariot(slot if slot >= 0 else 0)


func _on_phase_changed(phase: int, _round: int) -> void:
	if phase == Phase.BUILD:
		build_camera.frame(_m.track.get_bounds())
		build_camera.current = true
	else:
		race_camera.current = true
