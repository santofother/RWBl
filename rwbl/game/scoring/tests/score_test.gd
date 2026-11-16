extends Node
## C11 score test (tools/tests/score_test.sh). Owner: C11.
## A Scoring node with fake players and a fake progress source; scripted GameEvents sequences, asserted points.
## Prints `[TEST] ok|FAIL <what>`, then `[TEST] SCORE PASSED` / `FAILED`, and quits.
## NET: offline (the offline peer is the server).

var _fails := 0
var _sc: Scoring
var _prog: Dictionary = {}
var _round_no := 0
var _got: Dictionary = {}


func _ready() -> void:
	GameEvents.round_scored.connect(func(p: Dictionary, _t: Dictionary) -> void: _got = p)
	_sc = Scoring.new()
	add_child(_sc)
	var slots: Array[int] = [0, 1, 2, 3, 4]
	# item world x = progress
	_sc.configure(slots, func(s: int) -> float: return _prog.get(s, -5.0), func(pos: Vector3) -> float: return pos.x)
	await get_tree().process_frame
	_basic()
	_traps()
	_grief()
	print("[TEST] SCORE %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _begin() -> void:
	_round_no += 1
	_prog.clear()
	_sc._begin_race()
	GameEvents.phase_changed.emit(Phase.RACE, _round_no)


func _finish(order: Array) -> void:
	for i in order.size():
		GameEvents.chariot_finished.emit(order[i], i + 1, 10.0 + i)
	GameEvents.race_over.emit(order)


func _eq(what: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("[TEST] ok %s" % what)
	else:
		print("[TEST] FAIL %s: got %s want %s" % [what, str(got), str(want)])
		_fails += 1


func _place(uid: int, owner: int, at: float, id: StringName = &"column") -> void:
	GameEvents.item_placed.emit(uid, id, owner, Transform3D(Basis.IDENTITY, Vector3(at, 0, 0)))


func _basic() -> void:
	_begin()
	# C23: laps earn nothing now (lap_completed still emitted to prove it); slot 0 had a clean run; slot 4 dies once
	for s in [0, 1]:
		GameEvents.lap_completed.emit(s, 1, true)
		GameEvents.lap_completed.emit(s, 2, false)
	GameEvents.clean_lap.emit(0, 1)
	GameEvents.lap_completed.emit(2, 1, false)
	GameEvents.chariot_died.emit(4, &"fall", -1, -1)
	GameEvents.chariot_died.emit(3, &"spear", 0, -1)
	GameEvents.kill.emit(0, 3, &"spear")
	GameEvents.kill.emit(0, 4, &"wheel")
	GameEvents.self_kill.emit(2, 99)
	GameEvents.chariot_died.emit(2, &"item", 2, 99)
	_finish([1, 0, 2, 3, 4])
	var bd := _sc.get_breakdown()
	# slot 1: 1st=300 + fewest deaths(0 deaths: 0 and 1 tie) 60 = 360 (no lap points) (C24 numbers)
	_eq("finish 1st + fewest deaths, no lap points", bd[1]["total"], 360)
	# slot 0: 2nd=120 + clean run 30 + fewest 60 + 2 kills 144 = 354
	_eq("two kills = +144, clean run, tie gets fewest-deaths", bd[0]["total"], 354)
	_eq("kills column", bd[0]["kills"], 144)
	# slot 2: 3rd=84 + self-kill -36 (1 death, no fewest) = 48
	_eq("self-kill -1", bd[2]["total"], 48)
	# slot 3: 4th=48 + died once = 48; slot 4: 5th=0 + mercy 30 = 30
	_eq("4th place", bd[3]["total"], 48)
	_eq("last place mercy", bd[4]["total"], 30)
	_eq("round_scored fired", _got.get(1), 360)
	_eq("totals accumulate", _sc.get_totals()[0], 354)


func _traps() -> void:
	_begin()
	# 5 distinct items by owner 0, each hits one rival; everything passed by slot 1 -> cap 108. Owner hit ignored.
	for i in 5:
		_place(10 + i, 0, 100.0 + i)
	_place(20, 1, 120.0)
	for i in 5:
		GameEvents.trap_hit.emit(10 + i, 0, 1 + (i % 4))
	GameEvents.trap_hit.emit(20, 1, 1) # owner hits own: not a trap_hit event normally, defensive
	_prog = {1: 500.0}
	_sc.check_passes()
	_finish([1])
	var bd := _sc.get_breakdown()
	_eq("trap points capped at 108", bd[0]["traps"], 108)
	_eq("owner hit not counted", bd[1]["traps"], 0)


func _grief() -> void:
	# (a) nobody passes -> 0
	_begin()
	_place(30, 0, 300.0)
	GameEvents.trap_hit.emit(30, 0, 1)
	_prog = {1: 250.0}
	_sc.check_passes()
	_finish([1])
	_eq("(a) item nobody passes pays 0", _sc.get_breakdown()[0]["traps"], 0)
	# (b) everyone who reached it died to it -> 0 (slot 1 died to it, respawned beyond it, slot 2 died to it)
	_begin()
	_place(31, 0, 300.0)
	GameEvents.trap_hit.emit(31, 0, 1)
	GameEvents.trap_hit.emit(31, 0, 2)
	_prog = {1: 310.0, 2: 290.0}
	GameEvents.chariot_died.emit(1, &"item", 0, 31)
	GameEvents.chariot_died.emit(2, &"item", 0, 31)
	GameEvents.chariot_respawned.emit(1)
	_sc.check_passes()
	_finish([1, 2])
	_eq("(b) everyone died to it pays 0", _sc.get_breakdown()[0]["traps"], 0)
	# (c) one passes alive -> counts
	_begin()
	_place(32, 0, 300.0)
	GameEvents.trap_hit.emit(32, 0, 1)
	GameEvents.trap_hit.emit(32, 0, 2)
	_prog = {1: 310.0, 2: 290.0}
	GameEvents.chariot_died.emit(2, &"item", 0, 32)
	_sc.check_passes()
	_finish([1, 2])
	_eq("(c) one passes -> trap points count", _sc.get_breakdown()[0]["traps"], 72)
