extends Node
## C05 full-race test: match.tscn with 3 pilot bots, 2 laps, race phase only. Logs `[Race] ...` lines and
## `[TEST] RACE FULL DONE` when the match reaches the score phase. NET: offline only.

func _ready() -> void:
	var m: MatchMode = (load("res://game/match/match.tscn") as PackedScene).instantiate()
	add_child(m)
	var ps: Array[PlayerInfo] = []
	for i in 3:
		ps.append(PlayerInfo.create(i, 1, "Bot%d" % i, true))
	m.setup(ps, {"start_phase": Phase.RACE, "laps": 2, "rounds": 1, "race_time": 150.0, "score_time": 3.0})
	for p in ps:
		m.bots._drivers[p.slot] = RaceTestPilot.new() # WHY: test-only swap, see test_pilot.gd
	GameEvents.phase_changed.connect(func(ph: int, _r: int) -> void:
		if ph == Phase.SCORE:
			print("[TEST] RACE FULL DONE")
			get_tree().quit())
	m.start()
