extends Node
## C05/C23 headless race unit test (run by tools/tests/race_test.sh). Owner: C05 (C23 rules).
## Builds a match.tscn with 2 bots straight into the Race phase and checks: frozen countdown then GO, grid behind
## the start line, a chariot teleported past the middle leads and still finishes (shortcuts count), the finish
## line only counts inside the road and driving forward, falling into the pit kills and respawns on the road.
## Prints `[TEST] ok|FAIL <what>` lines then `[TEST] RACE UNIT PASSED|FAILED`. NET: offline only.

var _fails := 0


func _ready() -> void:
	var m: MatchMode = (load("res://game/match/match.tscn") as PackedScene).instantiate()
	add_child(m)
	var ps: Array[PlayerInfo] = []
	for i in 2:
		ps.append(PlayerInfo.create(i, 1, "Bot%d" % i, true))
	m.setup(ps, {"start_phase": Phase.RACE, "race_time": 100.0})
	m.start()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var t := m.track
	var c0 := m.chariot_sync.get_chariot(0) as Chariot
	var c1 := m.chariot_sync.get_chariot(1) as Chariot
	_check(c0.frozen and c1.frozen, "chariots frozen during the countdown")
	_check(m.race.countdown_left() > 2.0, "countdown running")
	_check(t.progress_at(c0.global_position) < 0.0, "slot 0 grid spot is behind the start line")
	_check(t.is_on_track(c0.global_position) and t.is_on_track(c1.global_position), "grid spots on the track")
	_check(t.finish_progress() > 300.0, "course %.0f m to the finish" % t.finish_progress())
	# finish guard: only inside the road and driving forward
	var probe := (load("res://game/chariot/chariot.tscn") as PackedScene).instantiate() as Chariot
	add_child(probe)
	var ft := t.finish_transform()
	probe.global_position = ft.origin
	probe.velocity = -ft.basis.z * 10.0
	_check(m.race._crossed_finish(probe), "crossing the finish line forward counts")
	probe.velocity = ft.basis.z * 10.0
	_check(not m.race._crossed_finish(probe), "crossing it backwards does not")
	probe.global_position = ft.origin + ft.basis.x * (t.track_width * 0.5 + 4.0)
	probe.velocity = -ft.basis.z * 10.0
	_check(not m.race._crossed_finish(probe), "passing beside the finish piece does not")
	probe.queue_free()
	# shortcut: slot 0 jumps past the middle of the course
	c0.respawn(t.transform_at(t.finish_progress() * 0.6))
	await get_tree().create_timer(3.3).timeout
	_check(not c0.frozen, "GO unfroze the chariots")
	await get_tree().create_timer(3.0).timeout
	_check(m.race.place_of(0) == 1 and m.race.place_of(1) == 2, "the chariot that took the shortcut leads (%d, %d)"
		% [m.race.place_of(0), m.race.place_of(1)])
	_check(m.race.to_go(0) < m.race.to_go(1), "to_go follows progress (%.0f < %.0f)" % [m.race.to_go(0), m.race.to_go(1)])
	# pit: no floor beside the road, falling kills, combat puts the chariot back
	var off := t.point_at(100.0) + t.transform_at(100.0).basis.x * (t.track_width * 0.5 + 6.0)
	var q := PhysicsRayQueryParameters3D.create(off + Vector3.UP * 5.0, off + Vector3.DOWN * 50.0, Layers.WORLD | Layers.WALL)
	_check(get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty(), "no floor or wall beside the road (pit)")
	var on := t.point_at(100.0)
	q = PhysicsRayQueryParameters3D.create(on + Vector3.UP * 5.0, on + Vector3.DOWN * 5.0, Layers.WORLD)
	_check(not get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty(), "road is solid")
	c1.global_position = Vector3(off.x, 3.0, off.z)
	await get_tree().create_timer(3.6).timeout # ~2.6 s to fall 30 m, respawn 2 s after that
	_check(c1.dead, "chariot over the pit fell and died")
	await get_tree().create_timer(2.5).timeout
	_check(not c1.dead and c1.global_position.y > -1.0 and t.is_on_track(c1.global_position), "chariot respawned on the road")
	var deadline := Time.get_ticks_msec() + 20000
	while not m.race.is_finished(0) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(m.race.is_finished(0) and m.race.finish_order().size() >= 1 and m.race.finish_order()[0] == 0,
		"the shortcut chariot finished first")
	print("[TEST] RACE UNIT %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", what])
