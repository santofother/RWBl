extends Node
## C24 headless unit test (run by tools/tests/playtest_fixes_test.sh). Owner: C24.
## A match.tscn with the local human (slot 0) and 2 bots, straight into the Race phase. Checks: a crash waits for
## a rival to pass the crash spot (and the max-wait cap), the race is cut short once every human finished, the
## camera spectates after finishing, Build gives nothing without a drafted card, item ghosts carry no scripts or
## collisions. Prints `[TEST] ok|FAIL <what>` then `[TEST] C24 PASSED|FAILED`. NET: offline only.

var _fails := 0


func _ready() -> void:
	_ghosts()
	var m: MatchMode = (load("res://game/match/match.tscn") as PackedScene).instantiate()
	add_child(m)
	var ps: Array[PlayerInfo] = [PlayerInfo.create(0, multiplayer.get_unique_id(), "Me")]
	for i in [1, 2]:
		ps.append(PlayerInfo.create(i, 1, "Bot%d" % i, true))
	m.setup(ps, {"start_phase": Phase.RACE, "race_time": 120.0})
	m.start()
	await get_tree().create_timer(3.4).timeout # countdown
	_check(m.build.remaining_hand(0).is_empty(), "no drafted card = nothing to place (free build is off by default)")
	var t := m.track
	var c0 := m.chariot_sync.get_chariot(0) as Chariot
	var c1 := m.chariot_sync.get_chariot(1) as Chariot
	var c2 := m.chariot_sync.get_chariot(2) as Chariot
	for c in [c1, c2]:
		(c as Chariot).frozen = true
	# 1) crash in the lead: wait until a rival passes the spot
	c0.respawn(t.transform_at(150.0))
	m.race.notify_teleport(0)
	await get_tree().physics_frame
	c0.frozen = true
	c0.kill(&"fall")
	await get_tree().create_timer(3.0).timeout
	_check(c0.dead, "leader who crashed is still out after 3 s (nobody passed)")
	_check(not m.combat.respawn_wait(0).is_empty(), "respawn_wait() shows the wait")
	c1.respawn(t.transform_at(160.0))
	m.race.notify_teleport(1)
	c1.frozen = true
	await get_tree().create_timer(0.6).timeout
	_check(not c0.dead, "back in once a rival passed the crash spot")
	_check(m.combat.respawn_wait(0).is_empty(), "wait cleared")
	_check(absf(t.progress_at(c0.global_position) - (150.0 - m.combat.tuning.respawn_back)) < 3.0,
		"respawned behind the crash spot (%.0f m)" % t.progress_at(c0.global_position))
	# 2) nobody ever passes: respawn_wait_max caps it
	c0.respawn(t.transform_at(320.0))
	m.race.notify_teleport(0)
	await get_tree().physics_frame
	c0.kill(&"fall")
	var t0 := Time.get_ticks_msec()
	while c0.dead and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	var waited := (Time.get_ticks_msec() - t0) * 0.001
	var cap := m.combat.tuning.respawn_wait_max
	_check(not c0.dead and waited > cap - 0.5 and waited < cap + 1.0, "max wait %.1f s (cap %.1f)" % [waited, cap])
	# 3) the only human finishes: race is cut short, camera spectates
	c0.frozen = false
	var ft := t.transform_at(t.finish_progress() - 4.0)
	c0.respawn(ft)
	m.race.notify_teleport(0)
	c0.velocity = -ft.basis.z * 14.0
	t0 = Time.get_ticks_msec()
	while not m.race.is_finished(0) and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().physics_frame
	_check(m.race.is_finished(0), "human crossed the finish line")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cut := m.race.cut_time()
	_check(cut > 0.0 and absf(cut - NetClock.now() - m.tuning.race_end_after_humans) < 0.5,
		"race cut %.1f s after the last human finished" % (cut - NetClock.now()))
	await get_tree().create_timer(3.0).timeout
	_check(m.cameras.spectating_other(), "camera spectates the others after finishing")
	t0 = Time.get_ticks_msec()
	while m.phase == Phase.RACE and Time.get_ticks_msec() - t0 < 12000:
		await get_tree().physics_frame
	_check(m.phase == Phase.SCORE, "race ended early (bots still on the grid)")
	print("[TEST] C24 %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


## Every item ghost is a visual copy: geometry, no scripts, no collision objects.
func _ghosts() -> void:
	var bad: Array[String] = []
	for d in ItemDB.all_defs():
		if d.scene == null:
			continue
		var g := ItemVisual.ghost(d, Color(0, 1, 0, 0.3))
		if not _clean(g):
			bad.append(String(d.id))
		g.free()
	_check(bad.is_empty(), "item ghosts have no scripts or collisions %s" % [bad])


func _clean(n: Node) -> bool:
	if n.get_script() != null or n is CollisionObject3D:
		return false
	for c in n.get_children():
		if not _clean(c):
			return false
	return true


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", what])
