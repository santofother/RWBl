extends Node
## C18 score bars test (tools/tests/score_test.sh). Owner: C18.
## Feeds a ScoreScreen fake players / breakdown / totals and checks `bars()`, the order, the overtake case, the
## win round, skip, and that the animation ends inside its budget (`[Score] BARS done`).
## Prints `[TEST] ok|FAIL <what>`, then `[TEST] SCOREBARS PASSED` / `FAILED`, and quits.
## With `--screenshot=PATH` (needs a window, not --headless) it saves PATH_<n>.png at four moments of the show.
## NET: offline.

var _fails := 0
var _screen: ScoreScreen
var _shot := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			_shot = a.trim_prefix("--screenshot=")
	_screen = (load("res://game/scoring/score_screen.tscn") as PackedScene).instantiate() as ScoreScreen
	add_child(_screen)
	await get_tree().process_frame
	await _round_case()
	await _skip_case()
	await _win_case()
	print("[TEST] SCOREBARS %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _players() -> Array[PlayerInfo]:
	var out: Array[PlayerInfo] = []
	for i in 5:
		out.append(PlayerInfo.create(i, 1, ["Marcus", "Livia", "Cato", "Julia", "Nero"][i], i > 0))
	return out


func _bd(fin: int, traps: int, kills: int, bonus: int) -> Dictionary:
	return {"finish": fin, "traps": traps, "kills": kills, "bonus": bonus, "total": fin + traps + kills + bonus}


func _check(what: String, ok: bool, extra := "") -> void:
	if ok:
		print("[TEST] ok %s" % what)
	else:
		print("[TEST] FAIL %s %s" % [what, extra])
		_fails += 1


func _wait_done(limit: float, shots: Array[float] = [], tag := "") -> float:
	var t := 0.0
	var next := 0
	while not _screen.bars_done() and t < limit:
		await get_tree().process_frame
		t += get_process_delta_time()
		if _shot != "" and next < shots.size() and t >= shots[next]:
			get_viewport().get_texture().get_image().save_png("%s_%s%d.png" % [_shot, tag, next])
			next += 1
	return t


# Round with an overtake (slot 4 passes slot 0) and a negative bonus (slot 3 hit its own trap).
func _round_case() -> void:
	var before := {0: 600, 1: 400, 2: 300, 3: 100, 4: 500}
	var bd := {0: _bd(40, 0, 0, 10), 1: _bd(100, 30, 60, 25), 2: _bd(70, 60, 0, 50),
		3: _bd(0, 0, 0, -30), 4: _bd(150, 90, 60, 75)}
	var totals := {}
	for s in before:
		totals[s] = before[s] + int(bd[s]["total"])
	_screen.show_scores(_players(), bd, totals, 1000, -1, 7.0)
	var bars := _screen.bars()
	_check("one bar per player", bars.size() == 5)
	var sorted := true
	for i in bars.size():
		var b: Dictionary = bars[i]
		var sum := 0
		for k in ["finish", "kills", "traps", "bonus"]:
			sum += int(b["chunks"][k])
		_check("slot %d to == total" % b["slot"], int(b["to"]) == int(totals[b["slot"]]))
		_check("slot %d chunks == round points" % b["slot"], sum == int(bd[b["slot"]]["total"]))
		_check("slot %d from + chunks == to" % b["slot"], int(b["from"]) + sum == int(b["to"]))
		if i > 0 and int(bars[i - 1]["to"]) < int(b["to"]):
			sorted = false
	_check("bars sorted by total", sorted)
	_check("slot 4 leads (overtook slot 0)", int(bars[0]["slot"]) == 4)
	_check("rows() still sorted, 5 rows", _screen.rows().size() == 5 and int(_screen.rows()[0][0]) == 4)
	_check("not done at start", not _screen.bars_done())
	var took := await _wait_done(9.0, [0.4, 1.4, 2.6, 4.5], "round")
	_check("animation done inside its budget", _screen.bars_done() and took < 7.0, "took %.2f" % took)


func _skip_case() -> void:
	var bd := {0: _bd(150, 30, 0, 25), 1: _bd(0, 0, 0, 0)}
	var ps: Array[PlayerInfo] = [_players()[0], _players()[1]]
	_screen.show_scores(ps, bd, {0: 205, 1: 10}, 1000, -1, 10.0)
	await get_tree().process_frame
	_check("skip case running", not _screen.bars_done())
	_screen.skip()
	_check("skip jumps to done", _screen.bars_done())


# Slot 0 already at 1000+, finishes 1st: WINS!, confetti; budget 3 s forces the speed-up.
func _win_case() -> void:
	var bd := {0: _bd(150, 60, 60, 25), 1: _bd(100, 0, 0, 0), 2: _bd(0, 0, 0, 0)}
	var ps: Array[PlayerInfo] = [_players()[0], _players()[1], _players()[2]]
	_screen.show_scores(ps, bd, {0: 1295, 1: 600, 2: 50}, 1000, 0, 3.0)
	var took := await _wait_done(6.0, [0.7, 1.4, 2.0], "win")
	_check("win round done inside a 3 s budget", _screen.bars_done() and took < 3.0, "took %.2f" % took)
