class_name PlaceFx
extends Node3D
## "It landed" effects for placements (C24, user request), on every peer: when an item spawns, a ghost copy in the
## placer's colour drops in and fades, a light beam marks the spot, and "+Name: Item" floats up. When a track piece
## is inserted, its new road glows in the placer's colour (road + walls) and fades. Only during BUILD (bots place
## at BUILD start, so you also see what they put down). Owner: C24.
## NET: local visuals from GameEvents.item_placed / BuildPhase.piece_inserted (both every peer).
## Logs: `[Build] FX item <uid>`, `[Build] FX piece <uid>`.
## Public API: setup(m, build), `life`.

## Seconds an effect lasts.
var life := 1.8 # TUNE

var _m: MatchMode


## Called once by BuildUI on every peer.
func setup(m: MatchMode, build: BuildPhase) -> void:
	_m = m
	top_level = true
	GameEvents.item_placed.connect(_on_item)
	build.piece_inserted.connect(_on_piece)


func _on_item(uid: int, item_id: StringName, slot: int, xf: Transform3D) -> void:
	if _m.phase != Phase.BUILD or not is_inside_tree():
		return
	var d := ItemDB.get_def(item_id)
	if d == null:
		return
	var col := _color(slot)
	print("[Build] FX item %d" % uid)
	var g := ItemVisual.ghost(d, Color(col, 0.6))
	add_child(g)
	g.global_transform = xf
	g.position += Vector3.UP * 3.0
	g.scale = Vector3.ONE * 1.4
	var tw := create_tween()
	tw.tween_property(g, ^"position", xf.origin, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(g, ^"scale", Vector3.ONE, 0.25)
	tw.tween_interval(0.4)
	tw.tween_callback(g.queue_free)
	_beam(xf.origin, col)
	_tag(xf.origin, col, slot, d)


func _on_piece(uid: int, item_id: StringName, slot: int) -> void:
	if _m.phase != Phase.BUILD or not is_inside_tree():
		return
	var track := _m.track
	for e: Dictionary in track.pieces():
		if int(e["uid"]) != uid:
			continue
		var pts := PackedVector3Array()
		var p := float(e["start"])
		while p <= float(e["end"]):
			pts.append(track.point_at(p))
			p += 1.0
		var mesh := ItemVisual.road_ghost(pts, track.track_width + 0.4, 1.6)
		if mesh == null:
			return
		print("[Build] FX piece %d" % uid)
		var col := _color(slot)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(col.lightened(0.3), 0.8)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		add_child(mi)
		var tw := create_tween()
		tw.tween_property(mat, ^"albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
		var mid := pts[pts.size() / 2]
		_beam(mid, col)
		_tag(mid, col, slot, ItemDB.get_def(item_id))
		return


func _beam(at: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 1.2
	cyl.height = 40.0
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col, 0.7)
	mi.material_override = mat
	add_child(mi)
	mi.global_position = at + Vector3.UP * 20.0
	var tw := create_tween()
	tw.tween_property(mat, ^"albedo_color:a", 0.0, life * 0.7)
	tw.tween_callback(mi.queue_free)


func _tag(at: Vector3, col: Color, slot: int, d: ItemDef) -> void:
	var l := Label3D.new()
	var pl := _m.get_player(slot)
	l.text = "+ %s: %s" % [pl.name if pl else "P%d" % slot, (d.display_name if d.display_name != "" else String(d.id)) if d else "?"]
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0025
	l.font_size = 44
	l.outline_size = 12
	l.modulate = col.lightened(0.35)
	add_child(l)
	l.global_position = at + Vector3.UP * 4.0
	var tw := create_tween()
	tw.tween_property(l, ^"position:y", l.position.y + 6.0, life)
	tw.parallel().tween_property(l, ^"modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


func _color(slot: int) -> Color:
	var pl := _m.get_player(slot) if _m else null
	return pl.color if pl else Color.WHITE
