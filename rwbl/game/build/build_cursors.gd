class_name BuildCursors
extends Node3D
## Build phase: everyone sees where the other human players are pointing and what they hold (C24, user request).
## Each peer sends its own cursor (ground point, held card, ghost transform, piece joint + flip) about SEND_HZ times
## a second; every other peer draws a marker in that player's colour, a name tag "Name · Item", and a see-through
## ghost of the held item (or the road of the held track piece at its joint, or a red ring for Demolish).
## Created by BuildUI as `Match/Build/Cursors` on every peer (same path, RPCs depend on it). Owner: C24.
## NET: any peer -> all peers (unreliable). Purely visual: nothing here changes the game.
## Test hook: `--test-cursor=<item_id>` (client or host with a local player): report a cursor on the course
##   holding <item_id> during BUILD without a mouse.
## Logs: `[Build] CURSOR <slot> <item_id|none>` when a remote player's held card changes.
## Public API: setup(m, build), report(pos, item_id, xform, joint, flip), remote_cursors() -> Dictionary.

const SEND_HZ := 12.0 # TUNE
## A cursor that sent nothing for this long is hidden.
const STALE := 1.5 # TUNE

var _m: MatchMode
var _build: BuildPhase
var _accum := 0.0
var _mine: Dictionary = {} # what this peer reports next
var _remote: Dictionary = {} # slot -> {pos, item, xf, joint, flip, t}
var _views: Dictionary = {} # slot -> {root, marker, label, ghost, key}
var _test_item: StringName = &""


## Called once by BuildUI on every peer.
func setup(m: MatchMode, build: BuildPhase) -> void:
	_m = m
	_build = build
	top_level = true
	_test_item = StringName(String(NetworkManager.args.get("test-cursor", "")))
	GameEvents.phase_changed.connect(func(_p: int, _r: int) -> void:
		_remote.clear()
		_mine.clear())


## This peer's cursor right now (BuildUI calls it every frame while the build panel is up).
func report(pos: Vector3, item_id: StringName, xform: Transform3D, joint: int, flip: bool) -> void:
	_mine = {"pos": pos, "item": item_id, "xf": xform, "joint": joint, "flip": flip}


## slot -> last cursor state of every other human (for tests and debugging).
func remote_cursors() -> Dictionary:
	return _remote


func _process(delta: float) -> void:
	if _m == null:
		return
	if _m.phase != Phase.BUILD:
		for s: int in _views:
			(_views[s]["root"] as Node3D).visible = false
		return
	if _test_item != &"" and _m.local_slot() >= 0:
		var xf := _m.track.transform_at(40.0)
		report(xf.origin, _test_item, xf, 1, false)
	_accum += delta
	if _accum >= 1.0 / SEND_HZ and not _mine.is_empty() and not multiplayer.get_peers().is_empty():
		_accum = 0.0
		_rpc_cursor.rpc(_mine["pos"], _mine["item"], _mine["xf"], _mine["joint"], _mine["flip"])
	var now := Time.get_ticks_msec() * 0.001
	for s: int in _remote:
		_draw(s, _remote[s], now - float(_remote[s]["t"]) < STALE)
	for s: int in _views:
		if not _remote.has(s):
			(_views[s]["root"] as Node3D).visible = false


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_cursor(pos: Vector3, item_id: StringName, xf: Transform3D, joint: int, flip: bool) -> void: # NET: all
	if _m == null or _m.phase != Phase.BUILD:
		return
	var slot := _m.slot_of_peer(multiplayer.get_remote_sender_id())
	if slot < 0 or slot == _m.local_slot():
		return
	var old: Dictionary = _remote.get(slot, {})
	if old.get("item", &"?") != item_id:
		print("[Build] CURSOR %d %s" % [slot, item_id if item_id != &"" else &"none"])
	_remote[slot] = {"pos": pos, "item": item_id, "xf": xf, "joint": joint, "flip": flip,
		"t": Time.get_ticks_msec() * 0.001}


func _draw(slot: int, c: Dictionary, fresh: bool) -> void:
	var v: Dictionary = _views.get(slot, {})
	if v.is_empty():
		v = _make_view(slot)
		_views[slot] = v
	var root: Node3D = v["root"]
	root.visible = fresh
	if not fresh:
		return
	var pos: Vector3 = c["pos"]
	(v["marker"] as Node3D).global_position = pos
	var label: Label3D = v["label"]
	label.global_position = pos + Vector3.UP * 3.5
	var id: StringName = c["item"]
	var d := ItemDB.get_def(id)
	var pl := _m.get_player(slot)
	label.text = "%s · %s" % [pl.name if pl else "P%d" % slot, (d.display_name if d.display_name != "" else String(id)) if d else "looking"]
	var key := "%s %d %s %.2f" % [id, int(c["joint"]), c["flip"], _m.track.length()]
	if key != v["key"]:
		v["key"] = key
		if v["ghost"]:
			(v["ghost"] as Node).queue_free()
		v["ghost"] = _make_ghost(slot, d, c)
		if v["ghost"]:
			root.add_child(v["ghost"])
	var g: Node3D = v["ghost"]
	if g and d and not d.is_piece() and not BuildPhase.is_targeting(d):
		g.global_transform = c["xf"]
	elif g and d and BuildPhase.is_targeting(d):
		g.global_position = pos + Vector3.UP * 0.2


func _make_view(slot: int) -> Dictionary:
	var col := _color(slot)
	var root := Node3D.new()
	root.name = "Cursor%d" % slot
	add_child(root)
	var marker := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.9
	cone.bottom_radius = 0.0
	cone.height = 2.4
	marker.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.no_depth_test = true
	marker.material_override = mat
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(marker)
	marker.position = Vector3.UP * 2.0
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.1
	tm.outer_radius = 1.5
	ring.mesh = tm
	ring.material_override = mat
	holder.add_child(ring)
	ring.position = Vector3.UP * 0.3
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0025
	label.font_size = 40
	label.outline_size = 12
	label.modulate = col.lightened(0.3)
	label.offset = Vector2(0, 60) # WHY: keeps the tag off the marker in the top-down build view too
	root.add_child(label)
	return {"root": root, "marker": holder, "label": label, "ghost": null, "key": ""}


func _make_ghost(slot: int, d: ItemDef, c: Dictionary) -> Node3D:
	if d == null:
		return null
	var col := _color(slot)
	if BuildPhase.is_targeting(d):
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 2.0
		tm.outer_radius = 2.6
		mi.mesh = tm
		ItemVisual.set_tint(mi, Color(1.0, 0.15, 0.1, 0.8))
		return mi
	if d.is_piece():
		if int(c["joint"]) < 1:
			return null
		var pv := _m.track.preview_insert(d.id, int(c["joint"]), bool(c["flip"]))
		var mesh := ItemVisual.road_ghost(pv["piece"], _m.track.track_width)
		if mesh == null:
			return null
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.top_level = true
		ItemVisual.set_tint(mi, Color(col, 0.45))
		mi.transparency = 0.5
		return mi
	return ItemVisual.ghost(d, Color(col, 0.45))


func _color(slot: int) -> Color:
	var pl := _m.get_player(slot) if _m else null
	return pl.color if pl else Color.WHITE
