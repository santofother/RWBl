extends Node
## C19 headless track-piece unit test (run by tools/tests/track_piece_test.sh). Owner: C19.
## On the real track.tscn: illegal splices are rejected (start zone, not straight, self-intersection, overlap);
## a hairpin splice keeps the loop closed, grows the length, keeps the start line, checkpoints stay monotonic,
## fires track_changed once; a chicane after it; removing pieces restores the original length.
## Prints `[TEST] ok|FAIL <what>` lines then `[TEST] TRACK PIECE UNIT PASSED|FAILED`. NET: offline only.

var _fails := 0
var _changed := 0


func _ready() -> void:
	GameEvents.track_changed.connect(func() -> void: _changed += 1)
	var t: Track = (load("res://game/track/track.tscn") as PackedScene).instantiate()
	add_child(t)
	await get_tree().process_frame
	var l0 := t.length()
	var start0 := t.point_at(0.0)
	_check(t.check_splice(&"piece_hairpin", 10.0, true) == Track.Splice.START_ZONE, "hairpin on the start line rejected")
	_check(t.check_splice(&"piece_hairpin", l0 - 60.0, true) == Track.Splice.START_ZONE, "hairpin ending near the line rejected")
	_check(t.check_splice(&"piece_hairpin", 200.0, true) == Track.Splice.NOT_STRAIGHT, "hairpin on a corner rejected")
	_check(t.check_splice(&"piece_hairpin", 100.0, false) == Track.Splice.SELF_INTERSECT,
		"hairpin into the S-bend rejected (self-intersection)")
	_check(t.check_splice(&"oil_slick", 100.0, false) == Track.Splice.UNKNOWN, "an item is not a piece")
	var t0 := Time.get_ticks_usec()
	var code := t.check_splice(&"piece_hairpin", 60.0, true)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(code == Track.Splice.OK and ms < 30.0, "hairpin at 60 (left) OK, check %.1f ms" % ms)

	_check(t.splice_piece(&"piece_hairpin", 60.0, true, 7), "splice hairpin")
	var l1 := t.length()
	_check(_changed == 1, "track_changed fired once (%d)" % _changed)
	_check(l1 > l0 + 70.0 and l1 < l0 + 100.0, "length grew %.1f -> %.1f" % [l0, l1])
	var c := t.get_center_curve()
	_check(c.get_point_position(0).distance_to(c.get_point_position(c.point_count - 1)) < 0.01, "curve still closed")
	_check(t.point_at(0.0).distance_to(start0) < 0.05, "start line did not move")
	var mono := true
	for i in range(1, t.checkpoint_count()):
		mono = mono and t.checkpoint_progress(i) > t.checkpoint_progress(i - 1)
	_check(mono and t.checkpoint_progress(t.checkpoint_count() - 1) < l1, "checkpoints monotonic")
	var ps := t.pieces()
	_check(ps.size() == 1 and int(ps[0]["uid"]) == 7 and absf(float(ps[0]["start"]) - 60.0) < 0.01, "pieces() = %s" % [ps])
	var mid := t.point_at(float(ps[0]["start"]) + 63.0) # the far end of the U
	_check(t.piece_at(mid) == 7 and t.is_on_track(mid), "piece_at() finds the hairpin")
	_check(mid.distance_to(t.point_at(60.0)) > 40.0, "the road really detours (%.0f m)" % mid.distance_to(t.point_at(60.0)))
	_check(t.check_splice(&"piece_chicane", 120.0, false) == Track.Splice.OVERLAP, "chicane on the hairpin rejected")
	_check(t.check_splice(&"piece_hairpin", 60.0, true) == Track.Splice.OVERLAP, "same spot twice rejected")
	var chi := 400.0 + (l1 - l0)
	_check(t.splice_piece(&"piece_chicane", chi, false, 8), "splice chicane on the back straight")
	var l2 := t.length()
	_check(l2 > l1 + 1.0, "chicane grew the track %.1f -> %.1f" % [l1, l2])
	_check(t.remove_piece(7), "remove hairpin")
	ps = t.pieces()
	_check(ps.size() == 1 and absf(float(ps[0]["start"]) - 400.0) < 0.05, "chicane slid back to 400 (%s)" % [ps])
	_check(absf(t.length() - (l2 - (l1 - l0))) < 0.5, "length without hairpin %.1f" % t.length())
	_check(t.remove_piece(8) and absf(t.length() - l0) < 0.05, "both removed: length %.2f == %.2f" % [t.length(), l0])
	_check(not t.remove_piece(8), "removing twice fails")
	_check(_changed == 4, "track_changed fired 4 times (%d)" % _changed)
	print("[TEST] TRACK PIECE UNIT %s" % ("PASSED" if _fails == 0 else "FAILED"))
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("[TEST] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
