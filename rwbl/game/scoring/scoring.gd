class_name Scoring
extends Node
## Points per round (DESIGN §6) incl. the anti-grief rule, totals, score screen. Owner: C11.
## NET: host listens to GameEvents (chariot_finished, race_over, trap_hit, kill, self_kill, clean_lap, lap_completed,
##   chariot_died, chariot_respawned, item_placed, item_removed) and computes at race_over; it broadcasts by RPC, and
##   every peer then updates totals and emits GameEvents.round_scored. Clients only read.
## Public API: match_setup(m), get_totals() -> Dictionary slot -> int, get_round_points() -> Dictionary slot -> int,
##   get_breakdown() -> Dictionary slot -> {finish, traps, kills, bonus, total}, configure(slots, progress_fn,
##   item_progress_fn) (tests), score_round(finish_order).
## Logs: `[Score] ROUND r slot:pts ...`, `[Score] GRIEF item uid`.
# CONTRACT: get_totals() is what MatchMode uses for the win check and catch-up dealing.
# WHY: anti-grief: an item pays trap points only if some chariot passed it alive without dying to it. That covers
#   "nobody passes" and "everyone who reached it died to it" (a respawned victim passing later doesn't count).

const TABLE_DEFAULT := preload("res://game/scoring/default_score_table.tres")

## Points table (F2 panel "Score").
var table: ScoreTable = TABLE_DEFAULT

var _m: MatchMode
var _totals: Dictionary = {}
var _round: Dictionary = {}
var _breakdown: Dictionary = {}
var _slots: Array[int] = []
var _progress_fn: Callable # slot -> unwrapped race progress (m)
var _item_progress_fn: Callable # Vector3 world pos -> track progress (m)

# host-only state
var _racing := false
var _scored := false
var _round_no := 0
var _items: Dictionary = {} # uid -> {owner, id, progress}
var _hits: Dictionary = {} # uid -> Array of victim slots
var _passed: Dictionary = {} # uid -> {slot: true} (passed while alive)
var _died_to: Dictionary = {} # uid -> {slot: true}
var _dead: Dictionary = {} # slot -> true while dead
var _deaths: Dictionary = {} # slot -> count
var _finish_place: Dictionary = {} # slot -> place
var _laps: Dictionary = {}
var _clean: Dictionary = {}
var _kills: Dictionary = {}
var _self_kills: Dictionary = {}


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	var slots: Array[int] = []
	for p in m.players:
		slots.append(p.slot)
	configure(slots, func(s: int) -> float: return m.race.progress_of(s),
		func(pos: Vector3) -> float: return m.track.progress_at(pos))
	var panel := get_node_or_null(^"/root/TuningPanel")
	if panel:
		panel.register(table, "Score")
	GameEvents.phase_changed.connect(_on_phase_changed)
	var screen := get_node_or_null(^"ScoreScreen") as ScoreScreen
	if screen:
		screen.match_setup(m, self)


## Wires the score state to its inputs. `progress_fn(slot) -> float`, `item_progress_fn(pos) -> float`.
## Also connects the GameEvents the host listens to. Tests call this instead of match_setup.
func configure(slots: Array[int], progress_fn: Callable, item_progress_fn: Callable) -> void:
	_slots = slots
	_progress_fn = progress_fn
	_item_progress_fn = item_progress_fn
	for s in slots:
		_totals[s] = 0
		_round[s] = 0
	if GameEvents.item_placed.is_connected(_on_item_placed):
		return
	GameEvents.item_placed.connect(_on_item_placed)
	GameEvents.item_removed.connect(func(uid: int) -> void: _items.erase(uid))
	GameEvents.chariot_finished.connect(func(slot: int, place: int, _t: float) -> void: _finish_place[slot] = place)
	GameEvents.lap_completed.connect(func(slot: int, _l: int, _c: bool) -> void: _bump(_laps, slot))
	GameEvents.clean_lap.connect(func(slot: int, _l: int) -> void: _bump(_clean, slot))
	GameEvents.trap_hit.connect(_on_trap_hit)
	GameEvents.kill.connect(func(k: int, _v: int, _c: StringName) -> void: _bump(_kills, k))
	GameEvents.self_kill.connect(func(s: int, _u: int) -> void: _bump(_self_kills, s))
	GameEvents.chariot_died.connect(_on_died)
	GameEvents.chariot_respawned.connect(func(slot: int) -> void: _dead.erase(slot))
	GameEvents.race_over.connect(func(order: Array) -> void: score_round(order))


## slot -> total score (every peer, updated at round_scored).
func get_totals() -> Dictionary:
	return _totals.duplicate()


## slot -> points of the last scored round.
func get_round_points() -> Dictionary:
	return _round.duplicate()


## slot -> {finish, traps, kills, bonus, total} of the last scored round (for the score screen).
func get_breakdown() -> Dictionary:
	return _breakdown.duplicate(true)


## Host: compute the round (once per race) from the events seen so far and broadcast it.
## `finish_order` = slots in finishing order, DNFs last.
func score_round(finish_order: Array) -> void: # NET: host only
	if not multiplayer.is_server() or _scored:
		return
	_scored = true
	var bd: Dictionary = {}
	var min_deaths := 1 << 30
	for s in _slots:
		min_deaths = mini(min_deaths, int(_deaths.get(s, 0)))
	var grief := {}
	for uid: int in _items:
		if not _clean_pass(uid):
			grief[uid] = true
			print("[Score] GRIEF item %d" % uid)
	for s in _slots:
		var fin: int = table.finish_points(int(_finish_place[s])) if _finish_place.has(s) else 0
		var traps := 0
		for uid: int in _hits:
			if grief.has(uid) or not _items.has(uid) or int(_items[uid]["owner"]) != s:
				continue
			traps += (_hits[uid] as Array).size() * table.trap_hit
		traps = mini(traps, table.trap_cap)
		var kills: int = int(_kills.get(s, 0)) * table.kill
		var bonus: int = int(_laps.get(s, 0)) * table.lap + int(_clean.get(s, 0)) * table.clean_lap \
			+ int(_self_kills.get(s, 0)) * table.self_kill
		if int(_deaths.get(s, 0)) == min_deaths:
			bonus += table.fewest_deaths
		if finish_order.size() > 1 and int(finish_order[finish_order.size() - 1]) == s:
			bonus += table.mercy
		bd[s] = {"finish": fin, "traps": traps, "kills": kills, "bonus": bonus, "total": fin + traps + kills + bonus}
	var pts := {}
	var tot := {}
	for s in _slots:
		pts[s] = int(bd[s]["total"])
		tot[s] = int(_totals.get(s, 0)) + int(pts[s])
	_rpc_scored.rpc(pts, tot, bd)


@rpc("authority", "call_local", "reliable")
func _rpc_scored(pts: Dictionary, tot: Dictionary, bd: Dictionary) -> void: # NET: every peer
	_round = pts
	_totals = tot
	_breakdown = bd
	var parts: PackedStringArray = []
	for s: int in pts:
		parts.append("%d:%d" % [s, int(pts[s])])
	print("[Score] ROUND %d %s" % [_round_no, " ".join(parts)])
	GameEvents.round_scored.emit(pts, tot)


func _on_phase_changed(phase: int, round_no: int) -> void: # NET: every peer
	_round_no = round_no
	if phase == Phase.RACE:
		_begin_race()
	elif phase == Phase.SCORE and multiplayer.is_server() and not _scored:
		# WHY: the race timed out without race_over; still score what happened.
		score_round(_m.race.finish_order() if _m else [])


func _begin_race() -> void:
	_racing = true
	_scored = false
	_hits.clear()
	_passed.clear()
	_died_to.clear()
	_dead.clear()
	_deaths.clear()
	_finish_place.clear()
	_laps.clear()
	_clean.clear()
	_kills.clear()
	_self_kills.clear()


func _physics_process(_delta: float) -> void: # NET: host only
	if not _racing or not multiplayer.is_server():
		return
	check_passes()


## Host: record which alive chariots are now beyond each item. Called every physics tick during the race.
func check_passes() -> void:
	for slot in _slots:
		if _dead.has(slot):
			continue
		var p: float = _progress_fn.call(slot)
		for uid: int in _items:
			if p > float(_items[uid]["progress"]):
				if not _passed.has(uid):
					_passed[uid] = {}
				_passed[uid][slot] = true


func _clean_pass(uid: int) -> bool:
	var pass_set: Dictionary = _passed.get(uid, {})
	var died: Dictionary = _died_to.get(uid, {})
	for s: int in pass_set:
		if not died.has(s):
			return true
	return false


func _on_item_placed(uid: int, item_id: StringName, owner_slot: int, xform: Transform3D) -> void:
	_items[uid] = {"owner": owner_slot, "id": item_id, "progress": float(_item_progress_fn.call(xform.origin))}


func _on_trap_hit(uid: int, owner_slot: int, victim_slot: int) -> void:
	if victim_slot == owner_slot or not multiplayer.is_server():
		return
	if _items.has(uid) and table.non_trap_items.has(_items[uid]["id"]):
		return
	if not _hits.has(uid):
		_hits[uid] = []
	_hits[uid].append(victim_slot)


func _on_died(slot: int, _cause: StringName, _killer: int, item_uid: int) -> void:
	_dead[slot] = true
	_bump(_deaths, slot)
	if item_uid >= 0:
		if not _died_to.has(item_uid):
			_died_to[item_uid] = {}
		_died_to[item_uid][slot] = true


func _bump(d: Dictionary, slot: int) -> void:
	d[slot] = int(d.get(slot, 0)) + 1
