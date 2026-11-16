class_name BuildPhase
extends Node
## Build phase: placement RPC, host validation incl. path check, item spawning, bot placing, local build UI
## (DESIGN §5.5, §7, §8 N5). Owner: C08.
## NET: a client calls request_place(); the host validates `(item_id, transform, owner)` with validate(),
##   spawns on every peer with _rpc_spawn_item(), and answers the requester with place_result.
##   Bots: the host places their hands at random valid spots on BUILD. Clients call validate() locally only for
##   the green/red ghost preview (BuildUI); the host's answer is what counts.
## Hand: `m.draft.hand_of(slot)`, each entry placeable once. If that is empty and `rules.free_build` (default
##   false; `--free-build` turns it on) every ItemDB item is in the hand once. Budget = BuildTuning.budget cost per phase.
## A slot is finished when it pressed Done or nothing left in its hand fits the budget. All finished -> the host
##   ends the phase early (GameEvents.phase_end_requested(BUILD)). Items stay for the rest of the match.
## Test hook (CLI, host or client): `--test-place=item@progress,lateral,deg[,slot];item@...` places in order at
##   BUILD start (prints `[TEST] PLACE <i> <item> -> <CODE>`). `slot` only on a host without a local player
##   (standalone --no-human, default 0); otherwise the local player's slot is used. Then the host places bots.
## Targeting cards (C17, Demolish): a def with no scene targets a placed item instead of placing. The holder
##   calls request_demolish(uid); the host checks validate_demolish() and removes the item on every peer
##   (`[Build] DEMOLISH <uid> by <slot>`, GameEvents.item_removed once per peer); the card is spent like a
##   placement (hand + cost). The answer comes back as place_result(code, card_id).
##   Test hook: a `--test-place` entry `demolish@uid[,slot]` demolishes uid; `--test-race-demolish=uid,slot`
##   tries it on the host once RACE starts (prints `[TEST] RACE DEMOLISH <uid> -> <CODE>`).
## Track pieces (C19, C22): a def with `piece` is inserted into the course at a joint (Track.apply_insert). The
##   holder calls request_piece(id, joint, flip); the host checks validate_piece() (phase, item, hand, budget,
##   then Track.check_insert mapped to PlaceResult: BAD_JOINT -> NO_BUILD_ZONE, SELF_INTERSECT -> BLOCKS_PATH,
##   UNKNOWN -> UNKNOWN_ITEM; `last_insert_code` keeps the Track code for the UI) and inserts it on every peer
##   (`[Build] PIECE <uid> <id> slot=N joint=<k> flip=<b>`). Pieces take uids from the item counter, so Demolish
##   removes them like items (the gap closes; rejected with BLOCKS_PATH if the course would cross itself). Items
##   after the joint move rigidly with the course (`[Build] PIECE moved <uid>`); items that end up on the new
##   piece's road, on a demolished piece, or on a spot that breaks a rule are removed (`[Build] PIECE displaced
##   <uid>`, item_removed). The host decides, peers apply.
##   Test hook: a `--test-place` entry `piece_hairpin@joint,side,0[,slot]` (side < 0 = flipped to the left).
##   `--no-bot-build`: bots place nothing (tests).
## Public API: match_setup(m), request_place(item_id, xform), request_done(), place_for_slot(slot, item_id,
##   xform) -> int, validate(slot, item_id, xform) -> int, request_demolish(uid), demolish_for_slot(slot, uid)
##   -> int, validate_demolish(slot, uid) -> int, demolish_card(slot), item_at(pos) -> int, static
##   is_targeting(def), remaining_hand(slot), budget_left(slot), is_finished(slot), items() -> Dictionary
##   uid -> Item, `tuning`, `path`, signal place_result. C22: request_piece(id, joint, flip),
##   place_piece_for_slot(slot, id, joint, flip) -> int, validate_piece(slot, id, joint, flip) -> int,
##   `last_insert_code`. C24: signal piece_inserted(uid, id, slot); children `Cursors` (BuildCursors) and `PlaceFx`.
# CONTRACT: placement RPC is (item_id: StringName, xform: Transform3D); owner = sender's slot on the host.
# CONTRACT: result codes are PlaceResult.*; spawned items live under MatchMode/Items named "Item<uid>".
# CONTRACT: demolish RPC is (uid: int); owner = sender's slot on the host. Rejections reuse PlaceResult:
#   WRONG_PHASE, NOT_IN_HAND (no targeting card left), OVER_BUDGET, UNKNOWN_ITEM (no item with that uid).

## all · a track piece was inserted into the course (C24: PlaceFx flashes it). After Track.apply_insert.
signal piece_inserted(uid: int, item_id: StringName, slot: int)
## Requester only: the host's answer to request_place().
signal place_result(code: int, item_id: StringName)

## Code names for logs/tests (index = PlaceResult value).
const CODE_NAMES: Array[String] = ["OK", "WRONG_PHASE", "UNKNOWN_ITEM", "NOT_IN_HAND", "OVER_BUDGET",
	"OFF_TRACK", "NO_BUILD_ZONE", "TOO_CLOSE", "BLOCKS_PATH", "OUT_OF_BOUNDS", "BAD_TRANSFORM"]

## Build knobs (F2 panel "Build").
var tuning: BuildTuning = preload("res://game/build/default_tuning.tres")
## The start-to-finish drivable-path checker (base grid built on the first BUILD, again after the track changed).
var path := PathValidator.new()
## Track.Insert code of the last validate_piece() that got as far as the track check (BuildUI reason text).
var last_insert_code := Track.Insert.OK

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
	GameEvents.track_changed.connect(func() -> void: _path_ready = false) # WHY: the road grid is stale
	if NetworkManager.args.has("test-place"): # tests compare this line between host and client
		GameEvents.track_changed.connect(func() -> void:
			var ps: Array = []
			for e: Dictionary in _m.track.pieces():
				ps.append("%d:%s@%d" % [int(e["uid"]), e["id"], int(e["joint"])])
			print("[TEST] TRACK length=%.1f pieces=%s" % [_m.track.length(), ",".join(PackedStringArray(ps))]))
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


## Local player: ask the host to remove placed item `uid` with the Demolish card. Answer arrives as place_result.
func request_demolish(uid: int) -> void:
	if multiplayer.is_server():
		var slot := _m.local_slot()
		var card := demolish_card(slot)
		place_result.emit(demolish_for_slot(slot, uid), card if card != &"" else &"demolish")
	else:
		_rpc_request_demolish.rpc_id(1, uid)


## True for cards that target a placed item instead of placing one (Demolish).
# TODO(C02): switch to `ItemDef.targets_placed` once the head engineer approves the field (C17 handoff).
static func is_targeting(d: ItemDef) -> bool:
	return d != null and d.scene == null and d.piece == null


## The first targeting card `slot` still holds this phase, or &"".
func demolish_card(slot: int) -> StringName:
	for id: StringName in remaining_hand(slot):
		if is_targeting(ItemDB.get_def(id)):
			return id
	return &""


## Check a demolish without doing it. Order: phase, uid, card, budget. Returns a PlaceResult code.
func validate_demolish(slot: int, uid: int) -> int:
	if _m == null or _m.phase != Phase.BUILD:
		return PlaceResult.WRONG_PHASE
	# C19: track pieces share the uid counter; the base track and the start line have no uid.
	if (not _items.has(uid) or not is_instance_valid(_items[uid])) and not _m.track.has_piece(uid):
		return PlaceResult.UNKNOWN_ITEM
	if _m.track.has_piece(uid) and _m.track.check_remove(uid) != Track.Insert.OK: # C22: closing the gap crosses
		return PlaceResult.BLOCKS_PATH
	var card := demolish_card(slot) if slot >= 0 else &""
	if card == &"":
		return PlaceResult.NOT_IN_HAND
	if ItemDB.get_def(card).cost > budget_left(slot):
		return PlaceResult.OVER_BUDGET
	return PlaceResult.OK


## Host: validate and, if OK, remove `uid` on every peer and spend the card. Returns a PlaceResult code.
func demolish_for_slot(slot: int, uid: int) -> int: # NET: host
	var code := validate_demolish(slot, uid)
	if code == PlaceResult.OK:
		var is_piece := _m.track.has_piece(uid)
		var snap := _snapshot_items() if is_piece else []
		_rpc_demolish.rpc(uid, slot, demolish_card(slot))
		if is_piece: # the gap closed: the rest of the course (and its items) moved back
			_follow_course(snap)
		_check_all_finished.call_deferred()
	print("[Build] demolish %d by %d -> %s" % [uid, slot, _code_name(code)])
	return code


## uid of the placed item whose footprint covers ground point `pos` (closest centre wins), or -1.
func item_at(pos: Vector3) -> int:
	var best := -1
	var best_d := INF
	var probe := Transform3D(Basis(), pos)
	for uid: int in _items:
		var it: Item = _items[uid]
		if not is_instance_valid(it) or it.def == null:
			continue
		if _footprint_gap(probe, Vector2(0.1, 0.1), it.global_transform, it.def.footprint) > 0.0:
			continue
		var d := Vector2(pos.x - it.global_position.x, pos.z - it.global_position.z).length()
		if d < best_d:
			best_d = d
			best = uid
	return best


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


## Host: spawn `item_id` for `slot` outside the build rules (crow drops, C12). Returns the uid.
# FIX(C12, Claude): crows need to spawn items mid-race like a placed item; _rpc_spawn_item is private.
func spawn_extra(slot: int, item_id: StringName, xform: Transform3D) -> int: # NET: host
	if not multiplayer.is_server() or ItemDB.get_def(item_id) == null or ItemDB.get_def(item_id).scene == null:
		return -1 # FIX(C19): pieces and targeting cards have no scene
	var uid := _next_uid
	_next_uid += 1
	_rpc_spawn_item.rpc(uid, item_id, xform, slot)
	return uid


## Check a placement without doing it (host: authoritative; client: preview). Returns the first failing
## PlaceResult code, in this order: phase, item, hand, budget, transform, bounds, placement, no-build zone,
## gap, path.
func validate(slot: int, item_id: StringName, xform: Transform3D) -> int:
	if _m == null or _m.phase != Phase.BUILD:
		return PlaceResult.WRONG_PHASE
	var d := ItemDB.get_def(item_id)
	if d == null or is_targeting(d) or d.is_piece(): # targeting cards: validate_demolish(); pieces: validate_piece()
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


## Local player: ask the host to insert track piece `item_id` at course joint `joint` (mirrored if `flip`).
## The answer arrives as place_result.
func request_piece(item_id: StringName, joint: int, flip: bool) -> void:
	if multiplayer.is_server():
		place_result.emit(place_piece_for_slot(_m.local_slot(), item_id, joint, flip), item_id)
	else:
		_rpc_request_piece.rpc_id(1, item_id, joint, flip)


## Check a track piece without placing it (host: authoritative; client: ghost preview). Order: phase, item,
## hand, budget, then the track's own check (joint inside start/finish, self-intersection).
func validate_piece(slot: int, item_id: StringName, joint: int, flip: bool) -> int:
	if _m == null or _m.phase != Phase.BUILD:
		return PlaceResult.WRONG_PHASE
	var d := ItemDB.get_def(item_id)
	if d == null or not d.is_piece():
		return PlaceResult.UNKNOWN_ITEM
	if slot < 0 or not remaining_hand(slot).has(item_id):
		return PlaceResult.NOT_IN_HAND
	if d.cost > budget_left(slot):
		return PlaceResult.OVER_BUDGET
	last_insert_code = _m.track.check_insert(item_id, joint, flip)
	match last_insert_code:
		Track.Insert.OK:
			return PlaceResult.OK
		Track.Insert.BAD_JOINT:
			return PlaceResult.NO_BUILD_ZONE
		Track.Insert.SELF_INTERSECT:
			return PlaceResult.BLOCKS_PATH
	return PlaceResult.UNKNOWN_ITEM


## Host: validate and, if OK, insert the piece on every peer and move/remove the items after the joint.
## Returns a PlaceResult code.
func place_piece_for_slot(slot: int, item_id: StringName, joint: int, flip: bool) -> int: # NET: host
	var code := validate_piece(slot, item_id, joint, flip)
	if code == PlaceResult.OK:
		var uid := _next_uid
		_next_uid += 1
		var snap := _snapshot_items()
		_rpc_place_piece.rpc(uid, item_id, joint, flip, slot)
		_follow_course(snap)
		_check_all_finished.call_deferred()
	print("[Build] place %s by %d -> %s" % [item_id, slot, _code_name(code)])
	return code


## Items `slot` may still place this phase (hand minus what it already placed, one entry each).
func remaining_hand(slot: int) -> Array[StringName]:
	var hand: Array[StringName] = _m.draft.hand_of(slot)
	if hand.is_empty() and bool(_m.rules.get("free_build", false)):
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
		if d and d.cost <= left and (not is_targeting(d) or not _items.is_empty() or not _m.track.pieces().is_empty()):
			return false
	return true


## uid -> Item for every spawned item (every peer).
func items() -> Dictionary:
	return _items


# ---------------------------------------------------------------- phase, bots, test hook

func _on_phase_changed(phase: int, _round: int) -> void: # NET: every peer
	if phase == Phase.RACE and multiplayer.is_server() and NetworkManager.args.has("test-race-demolish"):
		var a := String(NetworkManager.args["test-race-demolish"]).split(",")
		var uid := int(a[0])
		print("[TEST] RACE DEMOLISH %d -> %s" % [uid, _code_name(demolish_for_slot(int(a[1]) if a.size() > 1
			else 0, uid))])
	if phase != Phase.BUILD:
		return
	_placed.clear()
	_spent.clear()
	_done.clear()
	_prune_items()
	_ensure_path() # WHY: every peer (clients preview blocks_path items too); ~0.3 s once per match
	if NetworkManager.args.has("test-place"):
		_run_test_places.call_deferred()
	elif multiplayer.is_server():
		_place_bots.call_deferred()


func _prune_items() -> void:
	for uid: int in _items.keys():
		if not is_instance_valid(_items[uid]) or (_items[uid] as Node).is_queued_for_deletion():
			_items.erase(uid)


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
		if NetworkManager.args.has("no-bot-build"): # tests: keep the track as the test built it
			_done[p.slot] = true
			continue
		var hand := remaining_hand(p.slot)
		if _m.draft.hand_of(p.slot).is_empty(): # free build: a few random items, not the whole catalogue
			hand.shuffle()
			hand = hand.slice(0, tuning.bot_free_items)
		# WHY: place first, demolish last, so a bot never wastes Demolish on an empty track.
		hand.sort_custom(func(a: StringName, b: StringName) -> bool:
			return not is_targeting(ItemDB.get_def(a)) and is_targeting(ItemDB.get_def(b)))
		for id in hand:
			if is_targeting(ItemDB.get_def(id)):
				var target := _bot_target(p.slot)
				if target >= 0:
					demolish_for_slot(p.slot, target)
				else:
					print("[Build] bot %d has no target for %s" % [p.slot, id])
				continue
			if ItemDB.get_def(id).is_piece():
				var spot: Variant = _bot_piece_spot(p.slot, id)
				if spot != null:
					place_piece_for_slot(p.slot, id, spot[0], spot[1])
				else:
					print("[Build] bot %d found no spot for %s" % [p.slot, id])
				continue
			var xf: Variant = _bot_spot(p.slot, id)
			if xf != null:
				place_for_slot(p.slot, id, xf)
			else:
				print("[Build] bot %d found no spot for %s" % [p.slot, id])
		_done[p.slot] = true
		print("[Build] BOT %d placed %d" % [p.slot, (_placed.get(p.slot, []) as Array).size()])
	_check_all_finished()


## Host: the item a bot demolishes: not its own, nearest the leader's racing line (approximated by the
## centre line, where the leader drives), preferring items in front of the start (lower progress = sooner).
## -1 if there is none.
func _bot_target(slot: int) -> int: # NET: host
	var best := -1
	var best_score := INF
	for uid: int in _items:
		var it: Item = _items[uid]
		if not is_instance_valid(it) or it.is_queued_for_deletion() or it.owner_slot == slot:
			continue
		var score := absf(_m.track.lateral_offset(it.global_position))
		if score < best_score:
			best_score = score
			best = uid
	return best


func _bot_piece_spot(slot: int, id: StringName) -> Variant: # NET: host. [joint, flip] or null
	var n := _m.track.course().size()
	for i in mini(tuning.bot_tries, 2 * n):
		var joint := randi_range(1, n - 1)
		var flip := randf() < 0.5
		if validate_piece(slot, id, joint, flip) == PlaceResult.OK:
			return [joint, flip]
	return null


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
	if not GameEvents.item_removed.is_connected(_on_test_item_removed):
		GameEvents.item_removed.connect(_on_test_item_removed)
	for i in list.size():
		var parts := list[i].split("@")
		var nums := parts[1].split(",") if parts.size() > 1 else PackedStringArray()
		var id := StringName(parts[0])
		var code: int
		if is_targeting(ItemDB.get_def(id)) and nums.size() >= 1:
			code = await _test_demolish(int(nums[0]), int(nums[1]) if nums.size() > 1 else 0, answers, i)
			print("[TEST] PLACE %d %s -> %s" % [i, id, _code_name(code)])
			continue
		if ItemDB.get_def(id) and ItemDB.get_def(id).is_piece() and nums.size() >= 1:
			code = await _test_piece(id, int(nums[0]), nums.size() > 1 and float(nums[1]) < 0.0,
				int(nums[3]) if nums.size() > 3 else 0, answers, i)
			print("[TEST] PLACE %d %s -> %s" % [i, id, _code_name(code)])
			continue
		if nums.size() < 3:
			print("[TEST] FAIL bad --test-place entry '%s'" % list[i])
			continue
		var t := _m.track.transform_at(float(nums[0]))
		var xf := Transform3D(t.basis.rotated(Vector3.UP, deg_to_rad(float(nums[2]))),
			t.origin + t.basis.x * float(nums[1]))
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


## Test hook: demolish `uid` as `slot` (no-human host), the local player (host) or over RPC (client; the
## answer arrives in `answers[i]` through the place_result listener).
func _test_demolish(uid: int, slot: int, answers: Array[int], i: int) -> int:
	if multiplayer.is_server() and _m.local_slot() < 0:
		return demolish_for_slot(slot, uid)
	request_demolish(uid)
	var deadline := Time.get_ticks_msec() + 5000
	while answers.size() <= i and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame # let queue_free run before the gone check
	var code := answers[i] if answers.size() > i else -1
	if code == PlaceResult.OK:
		print("[TEST] ITEM %d gone=%s" % [uid, _m.items_root.get_node_or_null(NodePath("Item%d" % uid)) == null])
	return code


## Test hook: insert piece `id` at `joint` as `slot` (no-human host), the local player (host) or over RPC (client).
func _test_piece(id: StringName, joint: int, flip: bool, slot: int, answers: Array[int], i: int) -> int:
	if multiplayer.is_server() and _m.local_slot() < 0:
		return place_piece_for_slot(slot, id, joint, flip)
	request_piece(id, joint, flip)
	if multiplayer.is_server():
		return answers[i] if answers.size() > i else -1
	var deadline := Time.get_ticks_msec() + 5000
	while answers.size() <= i and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return answers[i] if answers.size() > i else -1


func _on_test_item_removed(uid: int) -> void:
	print("[TEST] ITEM_REMOVED %d" % uid)


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


# ---------------------------------------------------------------- track pieces: items follow the course

## Host, before the course changes: [uid, progress, lateral offset] of every live item.
func _snapshot_items() -> Array: # NET: host
	var out: Array = []
	var track := _m.track
	for uid: int in _items:
		var it: Item = _items[uid]
		if not is_instance_valid(it) or it.is_queued_for_deletion():
			continue
		out.append([uid, track.progress_at(it.global_position), track.lateral_offset(it.global_position)])
	out.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) < float(y[1]))
	return out


## Host, right after an insert/remove (Track.last_change()): items after the change move with the course; items on
## a removed piece, items now on the inserted piece's road, and moved items whose new spot breaks a placement rule
## are removed. Broadcasts the result.
func _follow_course(snap: Array) -> void: # NET: host
	var ch := _m.track.last_change()
	if snap.is_empty() or ch.is_empty():
		return
	var track := _m.track
	var from := float(ch["from"])
	var to := float(ch["to"])
	var delta: Transform3D = ch["delta"]
	var removing: bool = ch["kind"] == &"remove"
	var moves: Array = [] # [uid, Transform3D]
	var removed: Array = [] # uids
	var pending := {} # moved uids not decided yet (ignored by the gap check)
	var todo: Array = [] # [uid, new xf, old lateral]
	for a: Array in snap:
		var uid := int(a[0])
		var it: Item = _items.get(uid)
		if it == null or not is_instance_valid(it):
			continue
		var p := float(a[1])
		if removing and p >= from and p <= to:
			removed.append(uid) # it was on the demolished piece
		elif p >= to:
			pending[uid] = true
			todo.append([uid, delta * it.global_transform, float(a[2])])
		elif not removing:
			var np := track.progress_at(it.global_position)
			if np > float(ch["piece_from"]) + 0.5 and np < float(ch["piece_to"]) - 0.5:
				removed.append(uid) # the new piece's road runs over it
	var moved := {} # uid -> new Transform3D
	for a: Array in todo:
		var uid := int(a[0])
		pending.erase(uid)
		var xf: Transform3D = a[1]
		if _relocation_ok(uid, _items[uid].def, xf, float(a[2]), pending, moved, removed):
			moved[uid] = xf
			moves.append([uid, xf])
		else:
			removed.append(uid)
	if not moves.is_empty() or not removed.is_empty():
		_rpc_piece_items.rpc(moves, removed)


func _relocation_ok(uid: int, d: ItemDef, xf: Transform3D, lat: float, pending: Dictionary, moved: Dictionary,
		removed: Array) -> bool: # NET: host
	var track := _m.track
	var real_lat := track.lateral_offset(xf.origin)
	if absf(real_lat - lat) > 1.0: # WHY: the spot is nearer another stretch of road than the one it was moved to
		return false
	var half := track.track_width * 0.5
	if d.placement == ItemDef.Placement.ON_TRACK and absf(real_lat) > half:
		return false
	if d.placement == ItemDef.Placement.TRACK_EDGE and (absf(real_lat) <= half or absf(real_lat) > half + tuning.edge_reach):
		return false
	if track.is_in_no_build_zone(xf.origin, d.footprint.length() * 0.5):
		return false
	var blockers: Array = [[xf, d.footprint]] if d.blocks_path else []
	for o: int in _items:
		var other: Item = _items[o]
		if o == uid or pending.has(o) or removed.has(o) or not is_instance_valid(other) or other.def == null:
			continue
		var oxf: Transform3D = moved.get(o, other.global_transform)
		if _footprint_gap(xf, d.footprint, oxf, other.def.footprint) < tuning.min_gap:
			return false
		if d.blocks_path and other.def.blocks_path:
			blockers.append([oxf, other.def.footprint])
	if d.blocks_path:
		_ensure_path()
		if not path.has_path(blockers):
			return false
	return true


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
func _rpc_request_piece(item_id: StringName, joint: int, flip: bool) -> void: # NET: host
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := place_piece_for_slot(_m.slot_of_peer(sender), item_id, joint, flip)
	_rpc_place_result.rpc_id(sender, code, item_id)


@rpc("authority", "call_local", "reliable")
func _rpc_place_piece(uid: int, item_id: StringName, joint: int, flip: bool, slot: int) -> void: # NET: every peer
	var d := ItemDB.get_def(item_id)
	if d == null or not d.is_piece():
		return
	if not _placed.has(slot):
		_placed[slot] = [] as Array[StringName]
	(_placed[slot] as Array).append(item_id)
	_spent[slot] = int(_spent.get(slot, 0)) + d.cost
	_m.track.apply_insert(uid, item_id, joint, flip)
	print("[Build] PIECE %d %s slot=%d joint=%d flip=%s" % [uid, item_id, slot, joint, flip])
	piece_inserted.emit(uid, item_id, slot)


@rpc("authority", "call_local", "reliable")
func _rpc_piece_items(moves: Array, removed: Array) -> void: # NET: every peer
	for mv: Array in moves:
		var it: Item = _items.get(int(mv[0]))
		if it and is_instance_valid(it):
			it.global_transform = mv[1]
			print("[Build] PIECE moved %d" % int(mv[0]))
	for uid: int in removed:
		var it: Item = _items.get(uid)
		_items.erase(uid)
		if it and is_instance_valid(it):
			it.queue_free()
		print("[Build] PIECE displaced %d" % uid)
		GameEvents.item_removed.emit(uid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_done() -> void: # NET: host
	if multiplayer.is_server():
		_mark_done(_m.slot_of_peer(multiplayer.get_remote_sender_id()))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_demolish(uid: int) -> void: # NET: host
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var slot := _m.slot_of_peer(sender)
	var card := demolish_card(slot)
	var code := demolish_for_slot(slot, uid)
	_rpc_place_result.rpc_id(sender, code, card if card != &"" else &"demolish")


@rpc("authority", "call_local", "reliable")
func _rpc_demolish(uid: int, slot: int, card: StringName) -> void: # NET: every peer
	var d := ItemDB.get_def(card)
	if not _placed.has(slot):
		_placed[slot] = [] as Array[StringName]
	(_placed[slot] as Array).append(card)
	_spent[slot] = int(_spent.get(slot, 0)) + (d.cost if d else 0)
	if _m.track.has_piece(uid): # C19/C22: a track piece; the gap closes (no item_removed: it was no item)
		_m.track.remove_piece(uid)
		print("[Build] DEMOLISH %d by %d" % [uid, slot])
		return
	var it: Item = _items.get(uid)
	_items.erase(uid) # WHY: erase before freeing; validate() loops _items typed and a freed one errors
	if it and is_instance_valid(it):
		it.queue_free() # surface patches unregister in _exit_tree (C10)
	print("[Build] DEMOLISH %d by %d" % [uid, slot])
	GameEvents.item_removed.emit(uid)


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
