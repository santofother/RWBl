class_name BuildPhase
extends Node
# FIX(C03, Codex): restore the C02 stub omitted from Git by the build/ ignore pattern.
## Build phase: cursor/ghost/rotate UI, placement RPC, host validation incl. path check, item spawning
## (DESIGN §5.5, §7, §8 N5). Owner: C08. C02 STUB: RPC plumbing + minimal validation (phase, item exists).
## NET: a client calls request_place(); the host validates `(item_id, transform, owner)` with validate(),
##   spawns on every peer with _rpc_spawn_item(), and answers the requester with place_result.
##   Bots: the host calls place_for_slot() directly.
## Public API: match_setup(m), request_place(item_id, xform), place_for_slot(slot, item_id, xform) -> int,
##   validate(slot, item_id, xform) -> int, items() -> Dictionary uid -> Item, signal place_result.
# CONTRACT: placement RPC is (item_id: StringName, xform: Transform3D); owner = sender's slot on the host.
# CONTRACT: result codes are PlaceResult.*; spawned items live under MatchMode/Items named "Item<uid>".

## Requester only: the host's answer to request_place().
signal place_result(code: int, item_id: StringName)

var _m: MatchMode
var _next_uid := 1
var _items: Dictionary = {} # uid -> Item


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m


## Local player: ask the host to place `item_id` at `xform`. Answer arrives as place_result.
func request_place(item_id: StringName, xform: Transform3D) -> void:
	if multiplayer.is_server():
		place_result.emit(place_for_slot(_m.local_slot(), item_id, xform), item_id)
	else:
		_rpc_request_place.rpc_id(1, item_id, xform)


## Host: validate and, if OK, spawn on every peer. Returns a PlaceResult code.
func place_for_slot(slot: int, item_id: StringName, xform: Transform3D) -> int:
	var code := validate(slot, item_id, xform)
	if code == PlaceResult.OK:
		var uid := _next_uid
		_next_uid += 1
		_rpc_spawn_item.rpc(uid, item_id, xform, slot)
	print("[Build] place %s by %d -> %s" % [item_id, slot, PlaceResult.describe(code)])
	return code


## Host: check a placement without doing it. TODO(C08): hand, budget, zones, gap, path check.
func validate(_slot: int, item_id: StringName, _xform: Transform3D) -> int:
	if _m.phase != Phase.BUILD:
		return PlaceResult.WRONG_PHASE
	if ItemDB.get_def(item_id) == null:
		return PlaceResult.UNKNOWN_ITEM
	return PlaceResult.OK


## uid -> Item for every spawned item (every peer).
func items() -> Dictionary:
	return _items


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_place(item_id: StringName, xform: Transform3D) -> void: # NET: host
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := place_for_slot(_m.slot_of_peer(sender), item_id, xform)
	_rpc_place_result.rpc_id(sender, code, item_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_place_result(code: int, item_id: StringName) -> void: # NET: requester
	place_result.emit(code, item_id)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_item(uid: int, item_id: StringName, xform: Transform3D, slot: int) -> void: # NET: every peer
	var d := ItemDB.get_def(item_id)
	if d == null or d.scene == null:
		return
	var item := d.scene.instantiate() as Item
	item.name = "Item%d" % uid
	_m.items_root.add_child(item)
	item.global_transform = xform
	item.placed(d, slot, uid)
	_items[uid] = item
	GameEvents.item_placed.emit(uid, item_id, slot, xform)
