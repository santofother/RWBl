class_name BuildPhase
extends Node
## Build phase: placement RPC, host validation incl. path check, item spawning, bot placing, local build UI
## (DESIGN §5.5, §7, §8 N5). Owner: C08.
## NET: a client calls request_place(); the host validates `(item_id, transform, owner)` with validate(),
##   spawns on every peer with _rpc_spawn_item(), and answers the requester with place_result.
##   Bots: the host places their hands at random valid spots on BUILD. Clients call validate() locally only for
##   the green/red ghost preview (BuildUI); the host's answer is what counts.
## Hand: `m.draft.hand_of(slot)`, each entry placeable once. If that is empty and `rules.free_build` (default
##   true until Draft is real) every ItemDB item is in the hand once. Budget = BuildTuning.budget cost per phase.
## A slot is finished when it pressed Done or nothing left in its hand fits the budget. All finished -> the host
##   ends the phase early (GameEvents.phase_end_requested(BUILD)). Items stay for the rest of the match.
## Test hook (CLI, host or client): `--test-place=item@progress,lateral,deg[,slot];item@...` places in order at
##   BUILD start (prints `[TEST] PLACE <i> <item> -> <CODE>`). `slot` only on a host without a local player
##   (standalone --no-human, default 0); otherwise the local player's slot is used. Then the host places bots.
## Public API: match_setup(m), request_place(item_id, xform), request_done(), place_for_slot(slot, item_id,
##   xform) -> int, validate(slot, item_id, xform) -> int, remaining_hand(slot), budget_left(slot),
##   is_finished(slot), items() -> Dictionary uid -> Item, `tuning`, `path`, signal place_result.
# CONTRACT: placement RPC is (item_id: StringName, xform: Transform3D); owner = sender's slot on the host.
# CONTRACT: result codes are PlaceResult.*; spawned items live under MatchMode/Items named "Item<uid>".

## Requester only: the host's answer to request_place().
signal place_result(code: int, item_id: StringName)

## Code names for logs/tests (index = PlaceResult value).
const CODE_NAMES: Array[String] = ["OK", "WRONG_PHASE", "UNKNOWN_ITEM", "NOT_IN_HAND", "OVER_BUDGET",
	"OFF_TRACK", "NO_BUILD_ZONE", "TOO_CLOSE", "BLOCKS_PATH", "OUT_OF_BOUNDS", "BAD_TRANSFORM"]

## Build knobs (F2 panel "Build").
var tuning: BuildTuning = preload("res://game/build/default_tuning.tres")
## The drivable-lap checker (base grid built on the first BUILD).
var path := PathValidator.new()

var _m: MatchMode
var _next_uid := 1
var _items: Dictionary = {} # uid -> Item
var _placed: Dictionary = {} # slot -> Array[StringName] placed this phase
var _spent: Dictionary = {} # slot -> int cost spent this phase
var _done: Dictionary = {} # slot -> true (pressed Done / bot finished)
var _path_ready := false
var _ui: BuildUI


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	var panel := get_node_or_null(^"/root/TuningPanel")
	if panel:
		panel.register(tuning, "Build")
	GameEvents.phase_changed.connect(_on_phase_changed)
	_ui = BuildUI.new()
	_ui.name = "BuildUI"
	add_child(_ui)
	_ui.setup(m, self)


## Local player: ask the host to place `item_id` at `xform`. Answer arrives as place_result.
func request_place(item_id: StringName, xform: Transform3D) -> void:
	if multiplayer.is_server():
		place_result.emit(place_for_slot(_m.local_slot(), item_id, xform), item_id)
	else:
		_rpc_request_place.rpc_id(1, item_id, xform)


## Local player: "I'm done placing" (the phase ends early once every slot is finished).
func request_done() -> void:
	if multiplayer.is_server():
		_mark_done(_m.local_slot())
	else:
		_rpc_request_done.rpc_id(1)


## Host: validate and, if OK, spawn on every peer. Returns a PlaceResult code.
func place_for_slot(slot: int, item_id: StringName, xform: Transform3D) -> int: # NET: host
	var code := validate(slot, item_id, xform)
	if code == PlaceResult.OK:
		var uid := _next_uid
		_next_uid += 1
		_rpc_spawn_item.rpc(uid, item_id, xform, slot)
	print("[Build] place %s by %d -> %s" % [item_id, slot, _code_name(code)])
	if code == PlaceResult.OK:
		_check_all_finished.call_deferred()
	return code


## Check a placement without doing it (host: authoritative; client: preview). Returns the first failing
## PlaceResult code, in this order: phase, item, hand, budget, transform, bounds, placement, no-build zone,
## gap, path.
func validate(slot: int, item_id: StringName, xform: Transform3D) -> int:
	if _m == null or _m.phase != Phase.BUILD:
		return PlaceResult.WRONG_PHASE
	var d := ItemDB.get_def(item_id)
	if d == null:
		return PlaceResult.UNKNOWN_ITEM
	if slot < 0 or not remaining_hand(slot).has(item_id):
		return PlaceResult.NOT_IN_HAND
	if d.cost > budget_left(slot):
		return PlaceResult.OVER_BUDGET
	var track := _m.track
	if not _sane(xform):
		return PlaceResult.BAD_TRANSFORM
	var pos := xform.origin
	var b := track.get_bounds()
	if pos.x < b.position.x or pos.z < b.position.z or pos.x > b.end.x or pos.z > b.end.z:
		return PlaceResult.OUT_OF_BOUNDS
	var lat := absf(track.lateral_offset(pos))
	var half := track.track_width * 0.5
	match d.placement:
		ItemDef.Placement.ON_TRACK:
			if lat > half:
				return PlaceResult.OFF_TRACK
		ItemDef.Placement.TRACK_EDGE:
			if lat <= half or lat > half + tuning.edge_reach:
				return PlaceResult.OFF_TRACK
	if track.is_in_no_build_zone(pos, d.footprint.length() * 0.5):
		return PlaceResult.NO_BUILD_ZONE
	for it: Item in _items.values():
		if is_instance_valid(it) and it.def and _footprint_gap(xform, d.footprint, it.global_transform,
				it.def.footprint) < tuning.min_gap:
			return PlaceResult.TOO_CLOSE
	if d.blocks_path:
		_ensure_path()
		var blockers: Array = [[xform, d.footprint]]
		for it: Item in _items.values():
			if is_instance_valid(it) and it.def and it.def.blocks_path:
				blockers.append([it.global_transform, it.def.footprint])
		var ok := path.has_path(blockers)
		print("[Build] PATH %s %d blockers %.1f ms" % ["ok" if ok else "BLOCKED", blockers.size(), path.last_ms])
		if not ok:
			return PlaceResult.BLOCKS_PATH
	return PlaceResult.OK


## Items `slot` may still place this phase (hand minus what it already placed, one entry each).
func remaining_hand(slot: int) -> Array[StringName]:
	var hand: Array[StringName] = _m.draft.hand_of(slot)
	if hand.is_empty() and bool(_m.rules.get("free_build", true)):
		hand = ItemDB.ids()
	for id: StringName in _placed.get(slot, []):
		hand.erase(id) # erase() removes one occurrence
	return hand


## Cost `slot` may still spend this phase.
func budget_left(slot: int) -> int:
	return tuning.budget - int(_spent.get(slot, 0))


## True when `slot` pressed Done or nothing left in its hand fits its budget.
func is_finished(slot: int) -> bool:
	if _done.has(slot):
		return true
	var left := budget_left(slot)
	for id: StringName in remaining_hand(slot):
		var d := ItemDB.get_def(id)
		if d and d.cost <= left:
			return false
	return true


## uid -> Item for every spawned item (every peer).
func items() -> Dictionary:
	return _items


# ---------------------------------------------------------------- phase, bots, test hook

func _on_phase_changed(phase: int, _round: int) -> void: # NET: every peer
	if phase != Phase.BUILD:
		return
	_placed.clear()
	_spent.clear()
	_done.clear()
	_ensure_path() # WHY: every peer (clients preview blocks_path items too); ~0.3 s once per match
	if NetworkManager.args.has("test-place"):
		_run_test_places.call_deferred()
	elif multiplayer.is_server():
		_place_bots.call_deferred()


func _ensure_path() -> void:
	if _path_ready:
		return
	path.build_base(_m.track, tuning.cell, tuning.chariot_half_width)
	_path_ready = true
	print("[Build] PATH base grid %.0f ms" % path.base_ms)


func _place_bots() -> void: # NET: host
	if _m.phase != Phase.BUILD:
		return
	for p in _m.players:
		if not p.is_bot:
			continue
		var hand := remaining_hand(p.slot)
		if _m.draft.hand_of(p.slot).is_empty(): # free build: a few random items, not the whole catalogue
			hand.shuffle()
			hand = hand.slice(0, tuning.bot_free_items)
		for id in hand:
			var xf: Variant = _bot_spot(p.slot, id)
			if xf != null:
				place_for_slot(p.slot, id, xf)
			else:
				print("[Build] bot %d found no spot for %s" % [p.slot, id])
		_done[p.slot] = true
		print("[Build] BOT %d placed %d" % [p.slot, (_placed.get(p.slot, []) as Array).size()])
	_check_all_finished()


func _bot_spot(slot: int, id: StringName) -> Variant: # NET: host. Transform3D or null
	var d := ItemDB.get_def(id)
	if d == null:
		return null
	var track := _m.track
	var half := track.track_width * 0.5
	for i in tuning.bot_tries:
		var t := track.transform_at(randf() * track.length())
		var lat := 0.0
		if d.placement == ItemDef.Placement.TRACK_EDGE:
			lat = randf_range(half + 0.5, half + tuning.edge_reach) * (1.0 if randf() < 0.5 else -1.0)
		else:
			var room := maxf(0.0, half - maxf(d.footprint.x, d.footprint.y) * 0.5)
			lat = randf_range(-room, room)
		var yaw := 0.0
		if d.rotatable:
			yaw = deg_to_rad(tuning.rotate_step * randi_range(-2, 2))
		var xf := Transform3D(t.basis.rotated(Vector3.UP, yaw), t.origin + t.basis.x * lat)
		if validate(slot, id, xf) == PlaceResult.OK:
			return xf
	return null


func _run_test_places() -> void:
	var list := String(NetworkManager.args["test-place"]).split(";", false)
	var answers: Array[int] = []
	var on_result := func(code: int, _id: StringName) -> void: answers.append(code)
	place_result.connect(on_result)
	for i in list.size():
		var parts := list[i].split("@")
		var nums := parts[1].split(",") if parts.size() > 1 else PackedStringArray()
		if nums.size() < 3:
			print("[TEST] FAIL bad --test-place entry '%s'" % list[i])
			continue
		var t := _m.track.transform_at(float(nums[0]))
		var xf := Transform3D(t.basis.rotated(Vector3.UP, deg_to_rad(float(nums[2]))),
			t.origin + t.basis.x * float(nums[1]))
		var id := StringName(parts[0])
		var code: int
		if multiplayer.is_server() and _m.local_slot() < 0:
			code = place_for_slot(int(nums[3]) if nums.size() > 3 else 0, id, xf)
		elif multiplayer.is_server():
			code = _local_place(id, xf)
		else:
			request_place(id, xf)
			var deadline := Time.get_ticks_msec() + 5000
			while answers.size() <= i and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			code = answers[i] if answers.size() > i else -1
		print("[TEST] PLACE %d %s -> %s" % [i, id, _code_name(code)])
	place_result.disconnect(on_result)
	if multiplayer.is_server():
		_place_bots()


func _local_place(id: StringName, xf: Transform3D) -> int: # host with a human slot
	var code := place_for_slot(_m.local_slot(), id, xf)
	place_result.emit(code, id)
	return code


func _mark_done(slot: int) -> void: # NET: host
	if slot < 0 or _m.phase != Phase.BUILD:
		return
	_done[slot] = true
	print("[Build] DONE %d" % slot)
	_check_all_finished()


func _check_all_finished() -> void: # NET: host
	if not multiplayer.is_server() or _m.phase != Phase.BUILD:
		return
	for p in _m.players:
		if not is_finished(p.slot):
			return
	print("[Build] ALL PLACED")
	GameEvents.phase_end_requested.emit(Phase.BUILD)


# ---------------------------------------------------------------- geometry helpers

func _sane(x: Transform3D) -> bool:
	if not x.is_finite():
		return false
	var b := x.basis
	for axis: Vector3 in [b.x, b.y, b.z]:
		if absf(axis.length() - 1.0) > 0.01:
			return false
	if b.y.dot(Vector3.UP) < 0.999 or b.determinant() < 0.0:
		return false
	var ground := _m.track.point_at(_m.track.progress_at(x.origin)).y
	return absf(x.origin.y - ground) <= tuning.max_height_error


static func _corners(x: Transform3D, f: Vector2) -> PackedVector2Array:
	var c := Vector2(x.origin.x, x.origin.z)
	var ax := Vector2(x.basis.x.x, x.basis.x.z).normalized() * f.x * 0.5
	var az := Vector2(x.basis.z.x, x.basis.z.z).normalized() * f.y * 0.5
	return PackedVector2Array([c - ax - az, c + ax - az, c + ax + az, c - ax + az])


## Ground distance between two footprint rectangles (0 if they overlap).
static func _footprint_gap(xa: Transform3D, fa: Vector2, xb: Transform3D, fb: Vector2) -> float:
	var a := _corners(xa, fa)
	var b := _corners(xb, fb)
	if not Geometry2D.intersect_polygons(a, b).is_empty():
		return 0.0
	var best := INF
	for i in 4:
		for j in 4:
			var pts := Geometry2D.get_closest_points_between_segments(a[i], a[(i + 1) % 4], b[j], b[(j + 1) % 4])
			best = minf(best, pts[0].distance_to(pts[1]))
	return best


static func _code_name(code: int) -> String:
	return CODE_NAMES[code] if code >= 0 and code < CODE_NAMES.size() else "NO_ANSWER(%d)" % code


# ---------------------------------------------------------------- RPCs

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_place(item_id: StringName, xform: Transform3D) -> void: # NET: host
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := place_for_slot(_m.slot_of_peer(sender), item_id, xform)
	_rpc_place_result.rpc_id(sender, code, item_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_done() -> void: # NET: host
	if multiplayer.is_server():
		_mark_done(_m.slot_of_peer(multiplayer.get_remote_sender_id()))


@rpc("authority", "call_remote", "reliable")
func _rpc_place_result(code: int, item_id: StringName) -> void: # NET: requester
	place_result.emit(code, item_id)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_item(uid: int, item_id: StringName, xform: Transform3D, slot: int) -> void: # NET: every peer
	var d := ItemDB.get_def(item_id)
	if d == null or d.scene == null:
		return
	if not _placed.has(slot):
		_placed[slot] = [] as Array[StringName]
	(_placed[slot] as Array).append(item_id)
	_spent[slot] = int(_spent.get(slot, 0)) + d.cost
	var item := d.scene.instantiate() as Item
	item.name = "Item%d" % uid
	_m.items_root.add_child(item)
	item.global_transform = xform
	item.placed(d, slot, uid)
	_items[uid] = item
	print("[Build] SPAWN %d %s slot=%d at %.1f %.1f" % [uid, item_id, slot, xform.origin.x, xform.origin.z])
	GameEvents.item_placed.emit(uid, item_id, slot, xform)
