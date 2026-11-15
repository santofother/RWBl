extends Node
## C13 unit check: speed FOV rises with speed and stays within the tuned range; shake and swing knobs sane.
## Run via tools/tests/camera_test.sh. Logs `[TEST] CAMERA PASSED`.

func _ready() -> void:
	var t: CameraTuning = load("res://game/camera/default_tuning.tres")
	var fails := 0
	var last := -1.0
	for s in [0.0, 5.0, 10.0, 15.0, 22.0]:
		var f := RaceCamera.fov_for_speed(s, t)
		if f <= last:
			fails += 1
			print("[TEST] FAIL fov not rising at speed %s: %s <= %s" % [s, f, last])
		last = f
	if not is_equal_approx(RaceCamera.fov_for_speed(0.0, t), t.fov_min) \
			or not is_equal_approx(RaceCamera.fov_for_speed(999.0, t), t.fov_max) \
			or not is_equal_approx(RaceCamera.fov_for_speed(-22.0, t), t.fov_max):
		fails += 1
		print("[TEST] FAIL fov range")
	if t.swing_time >= 3.0:
		fails += 1
		print("[TEST] FAIL swing must end before GO (3 s)")
	print("[TEST] CAMERA PASSED" if fails == 0 else "[TEST] CAMERA FAILED")
	get_tree().quit(1 if fails else 0)
