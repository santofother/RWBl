extends Node
## C21 headless loop unit test (run by tools/tests/track_piece_test.sh). Owner: C21.
## On the real track.tscn: piece_loop inserted at joint 2 grows the course by its road length (= the card's
## piece_length), the loop zone is upside down in the middle and flat at both ends, items / respawns are kept out
## of it, the build path check still finds a way through. A chariot at full speed rides the whole loop (upside
## down at the top) and keeps its progress; a slow one falls off and dies (&"loop_fall") and its respawn spot is
## before the loop. A "client" interpolating the fast run's 20 Hz snapshots never jumps more than the snapshot
## step (no 360° snap through the roll).
## Prints `[TEST] ok|FAIL <what>` lines then `[TEST] LOOP UNIT PASSED|FAILED`. NET: offline only.

const DT := 1.0 / 60.0

var _fails := 0


func _ready() -> void:
	var t: Track = (load("res://game/track/track.tscn") as PackedScene).instantiate()
	add_child(t)
	await get_tree().process_frame
	var l0 := t.length()
	var def := ItemDB.get_def(&"piece_loop")
	_check(def != null and def.is_piece(), "piece_loop card exists")
	_check(t.check_insert(&"piece_loop", 2) == Track.Insert.OK, "loop at joint 2 OK")
	_check(t.check_insert(&"piece_loop", 2, true) == Track.Insert.OK, "flipped loop at joint 2 OK")
	_check(t.insert_piece(&"piece_loop", 2, false, 7), "insert loop")
	var grown := t.length() - l0
	print("[TEST] loop road length %.2f (card piece_length %.1f)" % [grown, def.piece_length if def else -1.0])
	_check(def != null and absf(grown - def.piece_length) < 1.0, "length grew by piece_length (%.2f)" % grown)
	var zones := t.loop_zones()
	_check(zones.size() == 1, "one loop zone (%d)" % zones.size())
	if zones.is_empty():
		_finish()
		return
	var z: Vector2 = zones[0]
	var mid := (z.x + z.y) * 0.5
	_check(t.road_transform_at(mid).basis.y.y < -0.95, "upside down at the top (%.2f)" % t.road_transform_at(mid).basis.y.y)
	_check(t.road_transform_at(mid).origin.y > 15.0, "top is high (%.1f m)" % t.road_transform_at(mid).origin.y)
	_check(t.road_transform_at(z.x).basis.y.y > 0.99 and t.road_transform_at(z.y).basis.y.y > 0.99, "flat at both ends")
	var tw := t.transform_at(z.y + 8.0)
	_check(tw.basis.y.is_equal_approx(Vector3.UP), "flat transform after the loop")
	_check(t.is_in_no_build_zone(t.point_at(mid)) and t.is_in_no_build_zone(t.point_at(z.x + 2.0)),
		"no items on the loop")
	_check(t.respawn_transform(mid).origin.distance_to(t.point_at(z.x - Track.LOOP_MARGIN - 2.0)) < 0.5,
		"respawn moved before the loop")
	var pv := PathValidator.new()
	pv.build_base(t, 1.0, 1.3)
	_check(pv.has_path([]), "build path check gets through the loop")

	# fast chariot: full speed + throttle -> rides the loop
	var c: Chariot = (load("res://game/chariot/chariot.tscn") as PackedScene).instantiate()
	c.slot = 0
	add_child(c)
	c.track = t
	await get_tree().physics_frame
	var r := await _drive(c, t, z, 21.0, 1.0, 9.0)
	_check(not c.dead and float(r["min_up"]) < -0.9, "fast: upside down at the top, alive (min up %.2f)" % r["min_up"])
	_check(float(r["progress"]) > z.y + 20.0 and not c.on_loop, "fast: through and %.0f m past the loop" %
		(float(r["progress"]) - z.y))
	_check(absf(t.lateral_offset(c.global_position)) < t.track_width * 0.5 and c.global_basis.y.y > 0.99,
		"fast: back on the road, level")
	_check(int(r["tilted_cart"]) > 0, "cart pitched along the loop (%d frames)" % r["tilted_cart"])
	_check_interp(r["snaps"])

	if OS.get_cmdline_user_args().has("--sweep"):
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--slope="):
				c.tuning.loop_slope_gravity = float(arg.substr(8))
		for boost in [false, true]:
			for sp: float in [14.0, 18.0, 22.0]:
				var falls := []
				var cb := func(cause: StringName, _s: int, _u: int) -> void: falls.append(cause)
				c.died.connect(cb)
				var rs := await _drive(c, t, z, sp, 1.0, 10.0, 3.0, boost)
				c.died.disconnect(cb)
				print("[TEST] SWEEP %.0f m/s boost=%s: min_up %.2f got %.1f died %s" % [sp, boost, rs["min_up"], float(rs["progress"]) - z.x, falls])
	# slow chariot: 15 m/s at the entry, no whip -> falls off
	var died := []
	c.died.connect(func(cause: StringName, _s: int, _u: int) -> void: died.append(cause))
	var r2 := await _drive(c, t, z, 15.0, 1.0, 8.0, 3.0)
	print("[TEST] slow run min_up %.2f progress %.1f zone %s" % [r2["min_up"], r2["progress"], z])
	_check(died.size() == 1 and died[0] == &"loop_fall", "slow: fell off and died (%s)" % [died])
	_check(float(r2["progress"]) < z.y, "slow: never made it round")
	var back := t.respawn_transform(t.progress_at(c.global_position) - 10.0)
	_check(t.progress_at(back.origin) < z.x, "slow: respawn spot before the loop")
	c.respawn(back)
	_check(not c.dead and not c.on_loop and c.global_basis.y.is_equal_approx(Vector3.UP), "slow: respawned level")
	_finish()


## Respawn `c` 25 m before the loop at `speed`, drive with `throttle` for up to `secs`. Returns
## {min_up, progress, tilted_cart, snaps (20 Hz snapshots)}.
func _drive(c: Chariot, t: Track, z: Vector2, speed: float, throttle: float, secs: float, run_up := 25.0,
		boost := false) -> Dictionary:
	c.respawn(t.transform_at(z.x - run_up))
	c.velocity = c.get_forward() * speed
	if boost:
		c.add_effect(Effects.BOOST, c.tuning.whip_duration, 1.0, c.slot)
	var inp := ChariotInput.new()
	inp.throttle = throttle
	var min_up := 1.0
	var tilted := 0
	var snaps: Array = []
	var n := int(secs / DT)
	for i in n:
		await get_tree().physics_frame
		c.step(inp, DT)
		min_up = minf(min_up, c.global_basis.y.y)
		if absf(c.get_node(^"Cart").rotation.x) > 0.05:
			tilted += 1
		if i % 3 == 0:
			snaps.append(c.get_snapshot())
		if c.dead or t.progress_at(c.global_position) > z.y + 25.0:
			break
	return {"min_up": min_up, "progress": t.progress_at(c.global_position), "tilted_cart": tilted, "snaps": snaps}


## Client interpolation (ChariotSync) halfway between consecutive snapshots: the rotation never turns more than
## the step itself (slerp takes the short way round the roll).
func _check_interp(snaps: Array) -> void:
	var worst := 0.0
	var biggest := 0.0
	for i in range(1, snaps.size()):
		var a: PackedFloat32Array = snaps[i - 1]
		var b: PackedFloat32Array = snaps[i]
		var mid := ChariotSync._lerp_snapshot(a, b, 0.5)
		var qa := ChariotSnapshot.rot(a)
		var step := qa.angle_to(ChariotSnapshot.rot(b))
		biggest = maxf(biggest, step)
		worst = maxf(worst, qa.angle_to(ChariotSnapshot.rot(mid)) - step * 0.5)
	_check(snaps.size() > 10 and worst < 0.02 and biggest < 0.6,
		"client interpolation smooth through the roll (step max %.2f rad, overshoot %.3f)" % [biggest, worst])


func _check(ok: bool, what: String) -> void:
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _finish() -> void:
	print("[TEST] LOOP UNIT %s" % ("PASSED" if _fails == 0 else "FAILED"))
	get_tree().quit(0 if _fails == 0 else 1)
