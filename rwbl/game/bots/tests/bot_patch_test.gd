extends Node
## C06 test: a bot must steer around an oil patch in the middle of the road (surface patches are only visible to
## the driver through Track.surface_at). Logs `[TEST] BOT PATCH PASSED/FAILED`. NET: offline only.

const PATCH_FROM := 120.0
const PATCH_LEN := 40.0
var _m: MatchMode
var _bad := 0
var _t := 0.0
var _crossed := false # WHY: the grid is just behind the line (progress ~670), ignore it until the bot crosses


func _ready() -> void:
	_m = (load("res://game/match/match.tscn") as PackedScene).instantiate()
	add_child(_m)
	var ps: Array[PlayerInfo] = [PlayerInfo.create(0, 1, "Bot0", true)]
	_m.setup(ps, {"start_phase": Phase.RACE, "laps": 3, "rounds": 1, "race_time": 60.0})
	var patch := Node3D.new()
	_m.add_child(patch)
	patch.global_transform = _m.track.transform_at(PATCH_FROM + PATCH_LEN * 0.5)
	_m.track.register_surface_patch(patch, Surface.OIL, Vector2(3.0, PATCH_LEN * 0.5))
	_m.start()


func _physics_process(delta: float) -> void:
	_t += delta
	var c := _m.chariot_sync.get_chariot(0) as Chariot
	if c == null:
		return
	var p := _m.track.progress_at(c.global_position)
	if p < 100.0:
		_crossed = true
	if not _crossed:
		return
	if p > PATCH_FROM and p < PATCH_FROM + PATCH_LEN and _m.track.surface_at(c.global_position) != Surface.NORMAL:
		_bad += 1
	if p > PATCH_FROM + PATCH_LEN + 20.0 or _t > 40.0:
		var ok := _bad == 0 and p > PATCH_FROM + PATCH_LEN
		print("[TEST] BOT PATCH %s (frames on patch: %d, progress %.0f)" % ["PASSED" if ok else "FAILED", _bad, p])
		get_tree().quit()
