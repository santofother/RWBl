extends Node
## C20 headless hills unit test (run by tools/tests/track_piece_test.sh). Owner: C20.
## On the real track.tscn: hill, crest and banked turn each insert at joint 2, grow the course by the card's
## piece_length and leave the finish at y ≈ 0 with level joints; the hill climbs > 4 m, the banked turn tilts
## towards its inside, transform_at() follows the road normal there. A chariot at full throttle loses speed
## climbing the hill vs the same distance on the flat and is faster than top speed on the way down; a fast chariot
## leaves the ground on the crest and lands on the road, a slow one stays on it; the banked turn keeps more speed
## with the bank grip than without it (same road).
## Prints `[TEST] ok|FAIL <what>` lines then `[TEST] HILLS UNIT PASSED|FAILED`. NET: offline only.

const DT := 1.0 / 60.0

var _fails := 0


func _ready() -> void:
	var t: Track = (load("res://game/track/track.tscn") as PackedScene).instantiate()
	add_child(t)
	await get_tree().process_frame
	_check(not t.has_height(), "base course is flat")
	var l0 := t.length()
	var uid := 50
	for id: StringName in [&"piece_hill", &"piece_crest", &"piece_banked"]:
		var def := ItemDB.get_def(id)
		_check(def != null and def.is_piece(), "%s card exists" % id)
		var at := _fit(t, id)
		_check(at.x >= 0, "%s fits at joint %d flip %d" % [id, at.x, at.y])
		_check(t.insert_piece(id, at.x, at.y == 1, uid), "insert %s" % id)
		var grown := t.length() - l0
		_check(def != null and absf(grown - def.piece_length) < 1.0, "%s grew by piece_length (%.2f)" % [id, grown])
		_check(t.has_height(), "%s: course has height" % id)
		var fin := t.finish_transform()
		_check(absf(fin.origin.y) < 0.05 and fin.basis.y.y > 0.999, "%s: finish at y %.3f, level" % [id, fin.origin.y])
		var j := t.joints()
		var a := t.transform_at(j[at.x] + 0.2)
		var b := t.transform_at(j[at.x + 1] - 0.2)
		_check(absf(a.origin.y) < 0.05 and absf(b.origin.y) < 0.05 and a.basis.y.y > 0.999 and b.basis.y.y > 0.999,
			"%s: level joints" % id)
		var top := 0.0
		var min_up := 1.0
		var p := j[at.x]
		while p < j[at.x + 1]:
			top = maxf(top, t.point_at(p).y)
			min_up = minf(min_up, t.transform_at(p).basis.y.y)
			p += 1.0
		print("[TEST] %s top %.2f m, min up.y %.3f" % [id, top, min_up])
		if id == &"piece_hill":
			_check(top > 4.0, "hill climbs (%.1f m)" % top)
		if id == &"piece_banked":
			var mid := (j[at.x] + j[at.x + 1]) * 0.5
			var xf := t.transform_at(mid)
			# right turn: the normal leans to the right (towards the centre); flipped = left
			var flat_right := (-xf.basis.z).cross(Vector3.UP).normalized()
			var lean := xf.basis.y.dot(flat_right) * (-1.0 if at.y == 1 else 1.0)
			_check(lean > 0.3, "banked turn tilts inwards (%.2f)" % lean)
		_check(t.remove_piece(uid), "remove %s" % id)
		_check(absf(t.length() - l0) < 0.1 and not t.has_height(), "%s removed, flat again" % id)
		uid += 1

	var c: Chariot = (load("res://game/chariot/chariot.tscn") as PackedScene).instantiate()
	c.slot = 0
	add_child(c)
	c.track = t
	await get_tree().physics_frame
	var full := ChariotInput.new()
	full.throttle = 1.0

	# Hill vs flat: same entry speed and distance.
	t.insert_piece(&"piece_hill", 2, false, 60)
	var j := t.joints()
	var top_speed := c.tuning.max_speed
	var climb := await _run(c, t, j[2] - 5.0, top_speed, full, j[2] + 40.0)
	var flat := await _run(c, t, j[2] - 50.0, top_speed, full, j[2] - 5.0)
	print("[TEST] hill: %.2f m/s after the climb, %.2f on the flat" % [climb["speed"], flat["speed"]])
	_check(float(climb["speed"]) < float(flat["speed"]) - 1.0, "uphill loses speed vs flat (%.1f < %.1f)" %
		[climb["speed"], flat["speed"]])
	var down := await _run(c, t, j[2] + 52.0, top_speed, full, j[3] - 4.0)
	_check(float(down["max_speed"]) > top_speed + 0.5, "downhill beats top speed (%.1f)" % down["max_speed"])
	_check(int(down["air"]) == 0 and int(climb["air"]) == 0, "nobody takes off over the hill (%d, %d)" %
		[climb["air"], down["air"]])
	_check(absf(float(climb["max_y"]) - 0.0) > 3.0, "chariot climbed the hill (%.1f m)" % climb["max_y"])
	t.remove_piece(60)

	# Crest: fast flies and lands on the road, slow stays on it.
	t.insert_piece(&"piece_crest", 2, false, 61)
	j = t.joints()
	var boost := await _run(c, t, j[2] - 10.0, top_speed, full, j[3] - 2.0, true)
	print("[TEST] crest fast: air %d ticks, max gap %.2f m, landed %s, alive %s" % [boost["air"], boost["gap"],
		c.grounded, not c.dead])
	_check(int(boost["air"]) > 10 and float(boost["gap"]) > 0.5, "fast: leaves the ground on the crest")
	_check(c.grounded and not c.dead and t.is_on_track(c.global_position), "fast: landed on the road")
	var slow := await _run(c, t, j[2] - 10.0, 11.0, ChariotInput.new(), j[2] + 45.0)
	_check(int(slow["air"]) == 0, "slow: stays on the road (%d air ticks)" % slow["air"])
	t.remove_piece(61)

	# Banked turn: same road with and without the bank grip. 21 m/s in, full throttle, steer at the road.
	var bat := _fit(t, &"piece_banked")
	t.insert_piece(&"piece_banked", bat.x, bat.y == 1, 62)
	j = t.joints()
	var banked := await _corner(c, t, j[bat.x], j[bat.x + 1])
	var grip := c.tuning.bank_grip
	c.tuning.bank_grip = 0.0
	var plain := await _corner(c, t, j[bat.x], j[bat.x + 1])
	c.tuning.bank_grip = grip
	print("[TEST] banked turn: %.2f m/s out (min %.2f, widest %.2f m); without bank grip %.2f (min %.2f, widest %.2f m)"
		% [banked["out"], banked["min"], banked["wide"], plain["out"], plain["min"], plain["wide"]])
	_check(float(banked["wide"]) < float(plain["wide"]) - 0.5 and float(banked["min"]) >= float(plain["min"]) - 0.1,
		"bank grip holds the line at speed (%.1f m vs %.1f m wide)" % [banked["wide"], plain["wide"]])
	_check(float(banked["min"]) > 18.0, "banked turn near full speed (min %.1f)" % banked["min"])
	t.remove_piece(62)
	_finish()


## Respawn `c` at progress `from`, set `speed`, drive straight with `inp` until progress `to` (or 6 s). Returns
## {speed (at `to`), max_speed, air (ticks not grounded), gap (max height over the road), max_y}.
func _run(c: Chariot, t: Track, from: float, speed: float, inp: ChariotInput, to: float, boost := false) -> Dictionary:
	c.respawn(t.transform_at(from))
	await get_tree().physics_frame
	c.velocity = c.get_forward() * speed
	if boost:
		c.add_effect(Effects.BOOST, 3.0, 1.0, c.slot)
	var air := 0
	var gap := 0.0
	var max_speed := 0.0
	var max_y := -INF
	for i in int(6.0 / DT):
		await get_tree().physics_frame
		# keep it on the centre line (no steering model in the test)
		var p := t.progress_at(c.global_position)
		var ahead := c.global_transform.affine_inverse() * t.point_at(p + 10.0)
		inp.steer = clampf(atan2(ahead.x, -ahead.z) * 2.0, -1.0, 1.0)
		c.step(inp, DT)
		max_speed = maxf(max_speed, c.get_speed())
		max_y = maxf(max_y, c.global_position.y)
		if not c.grounded:
			air += 1
			gap = maxf(gap, c.global_position.y - t.point_at(t.progress_at(c.global_position)).y)
		if p >= to and c.grounded:
			break
	return {"speed": c.get_speed(), "max_speed": max_speed, "air": air, "gap": gap, "max_y": max_y}


## Drive the corner between progress `a` and `b` from 21 m/s with full throttle and a centre-line steer.
## {out (speed at b), min (lowest speed inside), wide (largest |lateral offset| inside)}.
func _corner(c: Chariot, t: Track, a: float, b: float) -> Dictionary:
	c.respawn(t.transform_at(a - 15.0))
	await get_tree().physics_frame
	c.velocity = c.get_forward() * 21.0
	var inp := ChariotInput.new()
	inp.throttle = 1.0
	var lo := INF
	var wide := 0.0
	for i in int(8.0 / DT):
		await get_tree().physics_frame
		var p := t.progress_at(c.global_position)
		var ahead := c.global_transform.affine_inverse() * t.point_at(p + 8.0 + c.get_speed() * 0.25)
		inp.steer = clampf(atan2(ahead.x, -ahead.z) * 2.0, -1.0, 1.0)
		c.step(inp, DT)
		if p > a and p < b:
			lo = minf(lo, c.get_speed())
			wide = maxf(wide, absf(t.lateral_offset(c.global_position)))
		if OS.get_cmdline_user_args().has("--debug") and i % 10 == 0:
			print("[TEST] dbg p %.1f (%.1f..%.1f) v %.2f y %.2f lat %.2f g %s dead %s" % [p, a, b, c.get_speed(),
				c.global_position.y, t.lateral_offset(c.global_position), c.grounded, c.dead])
		if p >= b:
			break
	return {"out": c.get_speed(), "min": lo, "wide": wide}


## First joint (from 2) and flip (0/1) where `id` goes in; (-1, 0) if none.
func _fit(t: Track, id: StringName) -> Vector2i:
	for k in range(2, t.course().size()):
		for f in 2:
			if t.check_insert(id, k, f == 1) == Track.Insert.OK:
				return Vector2i(k, f)
	return Vector2i(-1, 0)


func _check(ok: bool, what: String) -> void:
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _finish() -> void:
	print("[TEST] HILLS UNIT %s" % ("PASSED" if _fails == 0 else "FAILED"))
	get_tree().quit(0 if _fails == 0 else 1)
