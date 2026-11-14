extends Node
## C05 headless race unit test (run by tools/tests/race_test.sh). Owner: C05.
## Builds a match.tscn with 2 bots straight into the Race phase and checks: frozen countdown then GO, grid on the
## track, an ordered checkpoint is counted, and a chariot teleported past checkpoint 4 does NOT complete a lap.
## Prints `[TEST] ok|FAIL <what>` lines then `[TEST] RACE UNIT PASSED|FAILED`. NET: offline only.

var _fails := 0
var _laps_seen: Array[int] = []


func _ready() -> void:
	GameEvents.lap_completed.connect(func(slot: int, _l: int, _c: bool) -> void: _laps_seen.append(slot))
	var m: MatchMode = (load("res://game/match/match.tscn") as PackedScene).instantiate()
	add_child(m)
	var ps: Array[PlayerInfo] = []
	for i in 2:
		ps.append(PlayerInfo.create(i, 1, "Bot%d" % i, true))
	m.setup(ps, {"start_phase": Phase.RACE, "laps": 2, "race_time": 100.0})
	m.start()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var t := m.track
	var c0 := m.chariot_sync.get_chariot(0) as Chariot
	var c1 := m.chariot_sync.get_chariot(1) as Chariot
	_check(c0.frozen and c1.frozen, "chariots frozen during the countdown")
	_check(m.race.countdown_left() > 2.0, "countdown running")
	_check(t.progress_at(c0.global_position) > t.length() - 40.0, "slot 0 grid spot is behind the start line")
	_check(t.is_on_track(c0.global_position) and t.is_on_track(c1.global_position), "grid spots on the track")
	_check(t.length() > 400.0 and t.checkpoint_count() >= 4, "track length %.0f m, %d checkpoints" % [t.length(), t.checkpoint_count()])
	# teleport slot 0 past checkpoint 4 without 1..3
	c0.respawn(t.transform_at(t.checkpoint_progress(4) + 3.0))
	await get_tree().create_timer(3.3).timeout
	_check(not c0.frozen, "GO unfroze the chariots")
	await get_tree().create_timer(6.0).timeout
	_check(not _laps_seen.has(0), "no lap for the teleported chariot")
	_check(int(m.race._next_cp[0]) == 1, "teleported chariot is still waiting for checkpoint 1 (next=%d)" % int(m.race._next_cp[0]))
	_check(int(m.race._next_cp[1]) >= 2, "bot driving normally passed checkpoint 1 (next=%d)" % int(m.race._next_cp[1]))
	_check(m.race.place_of(1) == 1 and m.race.place_of(0) == 2, "places follow progress (%d, %d)" % [m.race.place_of(0), m.race.place_of(1)])
	# pit: no floor beside the road, falling kills, the race puts the chariot back
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
	print("[TEST] RACE UNIT %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", what])
