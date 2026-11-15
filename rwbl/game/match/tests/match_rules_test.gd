extends Node
## C16 win-rule unit test (run from tools/tests/match_test.sh). Owner: C16.
## MatchMode.winner_slot(): win = finish 1st AND pre-race total >= win_score. Prints `[TEST] ok|FAIL`, then PASSED/FAILED.
## NET: offline.

var _fails := 0


func _ready() -> void:
	var w := 1000
	_eq("(a) >= win_score but not 1st -> no win", MatchMode.winner_slot([2, 0], {0: 1100, 2: 400}, w), -1)
	_eq("(b) >= win_score and 1st -> win", MatchMode.winner_slot([0, 2], {0: 1100, 2: 400}, w), 0)
	# (c) 900 before the race, wins it (-> 1100): no WIN. Next race the pre-race total is 1100: winning wins.
	_eq("(c) 900 before + 1st -> match goes on", MatchMode.winner_slot([0], {0: 900}, w), -1)
	_eq("(c) next race 1100 before + 1st -> win", MatchMode.winner_slot([0], {0: 1100}, w), 0)
	_eq("(d) nobody finished -> no win", MatchMode.winner_slot([], {0: 1500}, w), -1)
	_eq("(e) exactly win_score wins", MatchMode.winner_slot([3], {3: 1000}, w), 3)
	print("[TEST] MATCH RULES %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _eq(what: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("[TEST] ok %s" % what)
	else:
		print("[TEST] FAIL %s: got %s want %s" % [what, str(got), str(want)])
		_fails += 1
