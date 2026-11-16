extends Node
## C22 headless course unit test (run by tools/tests/course_test.sh). Owner: C22.
## On the real track.tscn: the default course loads (start..finish, > 300 m); straight / corner / hairpin / chicane
## inserted at a middle joint and at the end grow the course by the piece's road length, later joints and the
## finish move, the road after the joint moves rigidly (last_change delta); inserting inside the start/finish
## piece or a self-crossing course is rejected; removing pieces closes the gap.
## Prints `[TEST] ok|FAIL <what>` lines then `[TEST] COURSE UNIT PASSED|FAILED`. NET: offline only.

var _fails := 0
var _changed := 0


func _ready() -> void:
	GameEvents.track_changed.connect(func() -> void: _changed += 1)
	var t: Track = (load("res://game/track/track.tscn") as PackedScene).instantiate()
	add_child(t)
	await get_tree().process_frame
	var c := t.course()
	var n := c.size()
	var l0 := t.length()
	_check(c[0] == &"start" and c[n - 1] == &"finish", "course %s" % [c])
	_check(l0 > 300.0, "base course length %.1f m" % l0)
	_check(t.joints().size() == n + 1, "%d joints for %d pieces" % [t.joints().size(), n])
	_check(t.point_at(0.0).distance_to(Vector3.ZERO) < 0.05, "start line at the origin")
	_check(t.is_on_track(t.start_transform(4).origin) and t.progress_at(t.start_transform(4).origin) < 0.0,
		"grid spot 4 on the road, behind the line")
	_check(t.is_in_no_build_zone(t.finish_transform().origin) and not t.is_in_no_build_zone(t.point_at(l0 * 0.5)),
		"finish no-build zone")
	var mono := true
	for i in range(1, t.checkpoint_count()):
		mono = mono and t.checkpoint_progress(i) > t.checkpoint_progress(i - 1)
	_check(mono and t.checkpoint_progress(t.checkpoint_count() - 1) < l0, "checkpoints spread start..finish")

	# rejections
	_check(t.check_insert(&"piece_straight", 0) == Track.Insert.BAD_JOINT, "before the start piece rejected")
	_check(t.check_insert(&"piece_straight", n) == Track.Insert.BAD_JOINT, "after the finish piece rejected")
	_check(t.check_insert(&"oil_slick", 3) == Track.Insert.UNKNOWN, "an item is not a piece")
	var t0 := Time.get_ticks_usec()
	var code := t.check_insert(&"piece_hairpin", 5, true)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(code == Track.Insert.OK and ms < 40.0, "hairpin at joint 5 OK, check %.1f ms" % ms)

	# straight in the middle: everything after moves 30 m along
	var j0 := t.joints()
	var after_p := j0[7] + 5.0
	var after_pt := t.point_at(after_p)
	var before_pt := t.point_at(j0[3] - 5.0)
	_check(t.insert_piece(&"piece_straight", 5, false, 11), "insert straight at joint 5")
	var l1 := t.length()
	_check(_changed == 1, "track_changed fired once (%d)" % _changed)
	_check(absf(l1 - l0 - 30.0) < 0.5, "length grew by 30: %.1f -> %.1f" % [l0, l1])
	var j1 := t.joints()
	_check(j1.size() == j0.size() + 1 and absf(j1[8] - j0[7] - 30.0) < 0.5 and absf(j1[3] - j0[3]) < 0.05,
		"joints after shift 30 m, before stay")
	var ch := t.last_change()
	var moved: Vector3 = (ch["delta"] as Transform3D) * after_pt
	_check(moved.distance_to(t.point_at(after_p + 30.0)) < 0.3, "road after the joint moved rigidly (%.2f m)"
		% moved.distance_to(t.point_at(after_p + 30.0)))
	_check(t.point_at(j0[3] - 5.0).distance_to(before_pt) < 0.05, "road before the joint did not move")
	_check(t.pieces().size() == 1 and int(t.pieces()[0]["uid"]) == 11 and int(t.pieces()[0]["joint"]) == 5,
		"pieces() = %s" % [t.pieces()])
	var mid := t.point_at(j1[5] + 15.0)
	_check(t.piece_at(mid) == 11, "piece_at() finds the straight")

	# a corner at the end (just before the finish)
	n = t.course().size()
	var fin0 := t.finish_transform()
	_check(t.insert_piece(&"piece_corner_right", n - 1, false, 12), "insert right corner at the end")
	var l2 := t.length()
	_check(absf(l2 - l1 - 39.27) < 0.6, "length grew by a corner: %.1f -> %.1f" % [l1, l2])
	var fin1 := t.finish_transform()
	_check(fin1.origin.distance_to(fin0.origin) > 20.0 and absf(fin1.basis.z.dot(fin0.basis.x)) > 0.9,
		"finish moved and turned 90°")
	_check(t.course()[t.course().size() - 2] == &"piece_corner_right", "corner sits just before the finish")

	# hairpin and chicane in the middle
	var hp := t.preview_insert(&"piece_hairpin", 3, true)
	_check(hp["code"] == Track.Insert.OK and (hp["piece"] as PackedVector3Array).size() > 50
		and (hp["course"] as PackedVector3Array).size() > (hp["piece"] as PackedVector3Array).size(), "preview hairpin")
	_check(t.insert_piece(&"piece_hairpin", 3, true, 13), "insert hairpin (left) at joint 3")
	var l3 := t.length()
	_check(absf(l3 - l2 - 126.0) < 1.5, "hairpin adds its road: %.1f -> %.1f" % [l2, l3])
	_check(t.insert_piece(&"piece_chicane", 2, false, 14), "insert chicane at joint 2")
	var l4 := t.length()
	_check(absf(l4 - l3 - 55.9) < 1.0, "chicane adds its road: %.1f -> %.1f" % [l3, l4])

	# removal closes the gap
	_check(t.check_remove(13) == Track.Insert.OK and t.remove_piece(13), "remove hairpin")
	_check(absf(t.length() - (l4 - (l3 - l2))) < 0.6, "length without hairpin %.1f" % t.length())
	_check(t.remove_piece(14) and t.remove_piece(12) and t.remove_piece(11), "remove the rest")
	_check(absf(t.length() - l0) < 0.1 and t.course().size() == c.size(), "back to the base course %.2f" % t.length())
	_check(not t.remove_piece(11) and t.check_remove(11) == Track.Insert.NOT_FOUND, "removing twice fails")

	# self-crossing: two right corners after the start make a U, a third turns the course back over the start
	_check(t.insert_piece(&"piece_corner_right", 1, false, 21) and t.insert_piece(&"piece_corner_right", 1, false, 22),
		"two right corners after the start")
	_check(t.check_insert(&"piece_corner_right", 1) == Track.Insert.SELF_INTERSECT, "third one crosses the start: rejected")
	_check(t.remove_piece(21) and t.remove_piece(22), "clean up")
	_check(_changed == 12, "track_changed fired 12 times (%d)" % _changed)
	print("[TEST] COURSE UNIT %s" % ("PASSED" if _fails == 0 else "FAILED"))
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails += 1
