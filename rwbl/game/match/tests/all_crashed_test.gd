extends Node
## User request (C21 session): no timed respawn; when every racer still out is crashed and nobody can pass anyone's
## crash spot, the round ends at once. Owner: C21. A match.tscn with the local human (slot 0, 5000 test points:
## would win if it finished 1st) and 2 bots, straight into the Race phase. Slot 0 crashes at 300 m, slot 1 at
## 150 m, slot 2 at 100 m: `[Race] ALL CRASHED`, order by distance, nobody finished, points by distance
## (place points × share of the course), no winner, the match goes on to the next round.
## Prints `[TEST] ok|FAIL <what>` then `[TEST] ALL CRASHED PASSED|FAILED`. NET: offline only.

var _fails := 0


func _ready() -> void:
	var m: MatchMode = (load("res://game/match/match.tscn") as PackedScene).instantiate()
	add_child(m)
	var ps: Array[PlayerInfo] = [PlayerInfo.create(0, multiplayer.get_unique_id(), "Me")]
	for i in [1, 2]:
		ps.append(PlayerInfo.create(i, 1, "Bot%d" % i, true))
	m.setup(ps, {"start_phase": Phase.RACE, "race_time": 120.0})
	m.test_totals = {0: 5000}
	var scored := {}
	GameEvents.round_scored.connect(func(pts: Dictionary, _t: Dictionary) -> void: scored.merge(pts))
	m.start()
	await get_tree().create_timer(3.4).timeout # countdown
	var t := m.track
	var spots := [300.0, 150.0, 100.0]
	for slot in 3:
		var c := m.chariot_sync.get_chariot(slot) as Chariot
		c.frozen = true
		c.respawn(t.transform_at(spots[slot]))
		m.race.notify_teleport(slot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for slot in 3:
		(m.chariot_sync.get_chariot(slot) as Chariot).kill(&"fall")
		await get_tree().create_timer(0.5).timeout
		if slot < 2:
			_check(not m.race.all_crashed() and m.phase == Phase.RACE, "slot %d out, race goes on" % slot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(m.race.all_crashed(), "all crashed -> race over")
	_check(m.race.finish_order().is_empty(), "nobody finished")
	var t0 := Time.get_ticks_msec()
	while scored.is_empty() and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().physics_frame
	var f0 := int(m.scoring.get_breakdown().get(0, {}).get("finish", 0))
	print("[TEST] points %s finish0 %d" % [scored, f0])
	_check(not scored.is_empty(), "round scored")
	var first := m.scoring.table.finish_points(1)
	var share := 300.0 / t.length()
	_check(absi(f0 - roundi(first * share)) <= 1, "furthest gets 1st-place points × %.2f of the course (%d)" % [share, f0])
	var bd: Dictionary = m.scoring.get_breakdown()
	var fins := [0, 1, 2].map(func(sl: int) -> int: return int(bd.get(sl, {}).get("finish", 0)))
	_check(fins[0] > fins[1] and fins[1] > fins[2] and fins[2] > 0, "distance points follow distance %s" % [fins])
	t0 = Time.get_ticks_msec()
	while m.phase != Phase.DRAFT and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().physics_frame
	_check(m.phase == Phase.DRAFT and m.round_index == 2, "no winner despite 5000 points: next round")
	print("[TEST] ALL CRASHED %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails += 1
