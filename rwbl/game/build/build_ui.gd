class_name BuildUI
extends CanvasLayer
## Local build-phase editor: hand list, ghost under the mouse (green = the local validate() says OK, red = no,
## with the reason), snap to a grid, Q/E rotate, LMB place, RMB cancel, Done button, result toast. Owner: C08.
## C14 restyles it later (hand + toasts). Created by BuildPhase in match_setup().
## Targeting cards (Demolish, C17): no ghost; a red box highlights the placed item under the mouse, LMB asks
## the host to remove it (BuildPhase.request_demolish). Nothing under the mouse = nothing happens.
## Track pieces (C19): the ghost is a translucent road outline that snaps along the centre line (centred on the
## mouse), R (or Q/E) flips it left/right, LMB asks the host to splice it (BuildPhase.request_piece). Demolish
## also highlights a placed piece's road.
## NET: local only. The host's answer (place_result) is what counts; the colour is only a preview.
## Public API: setup(m, build), `selected` (item id or &"").

## Item id under the cursor, or &"" when nothing is selected.
var selected: StringName = &""

var _m: MatchMode
var _build: BuildPhase
var _panel: PanelContainer
var _list: VBoxContainer
var _title: Label
var _reason: Label
var _toast: Label
var _toast_left := 0.0
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _yaw_steps := 0
var _ghost_xf := Transform3D()
var _last_key := ""
var _last_code := -1
var _hand_key := ""
var _target_uid := -1 # Demolish: item under the mouse, or -1
var _flip := false # track piece mirrored to the left
var _piece_start := 0.0 # track piece: start progress under the mouse


## Wire to the match. Called once by BuildPhase.
func setup(m: MatchMode, build: BuildPhase) -> void:
	_m = m
	_build = build
	layer = 5
	_build_widgets()
	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	_ghost.top_level = true
	build.add_child.call_deferred(_ghost)
	build.place_result.connect(_on_place_result)
	GameEvents.phase_changed.connect(_on_phase_changed)
	_set_active(false)


func _build_widgets() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 64)
	_panel.custom_minimum_size = Vector2(230, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_title = Label.new()
	box.add_child(_title)
	_list = VBoxContainer.new()
	box.add_child(_list)
	var done := Button.new()
	done.text = "Done placing"
	done.pressed.connect(func() -> void:
		_select(&"")
		_build.request_done())
	box.add_child(done)
	var hint := Label.new()
	hint.text = "Click an item, then:\nLMB place · RMB cancel\nDemolish: click a placed item\nQ / E rotate · R flip a track piece\nwheel zoom · WASD / middle-drag pan"
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	_reason = Label.new()
	_reason.modulate = Color(1.0, 0.55, 0.5)
	box.add_child(_reason)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-150, 60)
	_toast.custom_minimum_size = Vector2(300, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override(&"font_size", 26)
	_toast.visible = false
	add_child(_toast)


func _on_phase_changed(phase: int, _round: int) -> void:
	_set_active(phase == Phase.BUILD and _m.local_slot() >= 0)


func _set_active(on: bool) -> void:
	_panel.visible = on
	if not on:
		_select(&"")
	_hand_key = ""


func _select(id: StringName) -> void:
	selected = id
	_yaw_steps = 0
	_last_key = ""
	_reason.text = ""
	_target_uid = -1
	_flip = false
	if _ghost:
		_ghost.visible = false
		var d := ItemDB.get_def(id)
		if d and d.is_piece():
			_ghost.mesh = null # built per position in _update_piece()
		elif d and not BuildPhase.is_targeting(d):
			var box := BoxMesh.new()
			var h := 1.2 if d.blocks_path else 0.15
			box.size = Vector3(d.footprint.x, h, d.footprint.y)
			_ghost.mesh = box


func _refresh_hand() -> void:
	var slot := _m.local_slot()
	var hand := _build.remaining_hand(slot)
	var key := "%s|%d" % [hand, _build.budget_left(slot)]
	if key == _hand_key:
		return
	_hand_key = key
	_title.text = "Your items · budget %d/%d" % [_build.budget_left(slot), _build.tuning.budget]
	for c in _list.get_children():
		c.queue_free()
	for id: StringName in hand:
		var d := ItemDB.get_def(id)
		if d == null:
			continue
		var btn := Button.new()
		btn.text = "%s (%d)" % [d.display_name if d.display_name != "" else String(id), d.cost]
		btn.disabled = d.cost > _build.budget_left(slot)
		btn.toggle_mode = true
		btn.button_pressed = id == selected
		btn.pressed.connect(_select.bind(id))
		_list.add_child(btn)
	if selected != &"" and not hand.has(selected):
		_select(&"")


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0
	if not _panel.visible:
		return
	_refresh_hand()
	if selected == &"":
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var hit: Variant = _ground_point(cam, get_viewport().get_mouse_position())
	if hit == null:
		_ghost.visible = false
		return
	var pos: Vector3 = hit
	if BuildPhase.is_targeting(ItemDB.get_def(selected)):
		_update_target(pos)
		return
	if ItemDB.get_def(selected) and ItemDB.get_def(selected).is_piece():
		_update_piece(pos)
		return
	var s := _build.tuning.snap
	pos.x = snappedf(pos.x, s)
	pos.z = snappedf(pos.z, s)
	var track := _m.track
	var along := track.transform_at(track.progress_at(pos))
	pos.y = along.origin.y
	var d := ItemDB.get_def(selected)
	var yaw := deg_to_rad(_build.tuning.rotate_step * _yaw_steps) if d and d.rotatable else 0.0
	# WHY: items face along the road by default; Q/E turn them from there.
	var basis := along.basis.rotated(Vector3.UP, yaw)
	_ghost_xf = Transform3D(basis, pos)
	var h := (_ghost.mesh as BoxMesh).size.y if _ghost.mesh else 0.1
	_ghost.global_transform = Transform3D(basis, pos + Vector3.UP * h * 0.5)
	_ghost.visible = true
	var key := "%s %s %d" % [selected, pos, _yaw_steps]
	if key != _last_key:
		_last_key = key
		_last_code = _build.validate(_m.local_slot(), selected, _ghost_xf)
		var ok := _last_code == PlaceResult.OK
		_ghost_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.55) if ok else Color(1.0, 0.2, 0.2, 0.55)
		_reason.text = "" if ok else PlaceResult.describe(_last_code)


func _update_piece(pos: Vector3) -> void:
	var track := _m.track
	var d := ItemDB.get_def(selected)
	_piece_start = snappedf(track.progress_at(pos) - d.piece_length * 0.5, _build.tuning.snap)
	var key := "%s %.2f %s" % [selected, _piece_start, _flip]
	if key == _last_key:
		return
	_last_key = key
	_last_code = _build.validate_piece(_m.local_slot(), selected, _piece_start, _flip)
	var ok := _last_code == PlaceResult.OK
	_ghost.mesh = _ribbon(track.piece_world_points(selected, _piece_start, _flip), track.track_width)
	_ghost.global_transform = Transform3D()
	_ghost_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.45) if ok else Color(1.0, 0.2, 0.2, 0.45)
	_ghost.visible = true
	if ok:
		_reason.text = "R flips it"
	elif _last_code in [PlaceResult.NO_BUILD_ZONE, PlaceResult.OFF_TRACK, PlaceResult.TOO_CLOSE, PlaceResult.BLOCKS_PATH]:
		_reason.text = Track.splice_text(_build.last_splice_code)
	else:
		_reason.text = PlaceResult.describe(_last_code)


## Flat translucent road strip `width` m wide along world points `pts`, lifted a little above the road.
static func _ribbon(pts: PackedVector3Array, width: float) -> ArrayMesh:
	if pts.size() < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	st.set_normal(Vector3.UP)
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var right := (b - a).cross(Vector3.UP).normalized() * width * 0.5
		var up := Vector3.UP * 0.25
		st.add_vertex(pts[i] - right + up)
		st.add_vertex(pts[i] + right + up)
	return st.commit()


func _update_target(pos: Vector3) -> void:
	_target_uid = _build.item_at(pos)
	var it: Item = _build.items().get(_target_uid)
	if _target_uid < 0 and _target_piece(pos):
		return
	if it == null or not is_instance_valid(it) or it.def == null:
		_target_uid = -1
		_ghost.visible = false
		_reason.text = "Point at a placed item"
		return
	var box := _ghost.mesh as BoxMesh
	if box == null:
		box = BoxMesh.new()
		_ghost.mesh = box
	var h := 1.6 if it.def.blocks_path else 0.3
	box.size = Vector3(it.def.footprint.x + 0.3, h, it.def.footprint.y + 0.3)
	_ghost.global_transform = Transform3D(it.global_basis.orthonormalized(), it.global_position + Vector3.UP * h * 0.5)
	_ghost_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.6)
	_ghost.visible = true
	var name_txt := it.def.display_name if it.def.display_name != "" else String(it.def.id)
	_reason.text = "Click to remove %s" % name_txt


## Demolish over a track piece's road: highlight the whole piece. False if there is none under `pos`.
func _target_piece(pos: Vector3) -> bool:
	var track := _m.track
	var uid := track.piece_at(pos)
	if uid < 0:
		return false
	for e: Dictionary in track.pieces():
		if int(e["uid"]) != uid:
			continue
		var pts := PackedVector3Array()
		var p := float(e["start"])
		while p <= float(e["end"]):
			pts.append(track.point_at(p))
			p += 1.0
		_target_uid = uid
		_ghost.mesh = _ribbon(pts, track.track_width + 0.6)
		_ghost.global_transform = Transform3D()
		_ghost_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.5)
		_ghost.visible = true
		var d := ItemDB.get_def(e["id"])
		_reason.text = "Click to remove %s (restores the road)" % (d.display_name if d else String(e["id"]))
		return true
	return false


func _ground_point(cam: Camera3D, mouse: Vector2) -> Variant:
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1000.0, Layers.WORLD)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		return r["position"]
	# Pit track: nothing below the road edge, so fall back to the road's height plane.
	var plane := Plane(Vector3.UP, _m.track.global_position.y)
	return plane.intersects_ray(from, dir)


func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible or selected == &"":
		return
	var piece := ItemDB.get_def(selected) != null and ItemDB.get_def(selected).is_piece()
	var flip_key: bool = event is InputEventKey and event.pressed and not event.echo \
		and (event as InputEventKey).keycode == KEY_R
	if piece and (flip_key or event.is_action_pressed(&"build_rotate_left") or event.is_action_pressed(&"build_rotate_right")):
		_flip = not _flip
	elif piece and event.is_action_pressed(&"build_place"):
		if _ghost.visible:
			_build.request_piece(selected, _piece_start, _flip)
	elif event.is_action_pressed(&"build_rotate_left"):
		_yaw_steps += 1
	elif event.is_action_pressed(&"build_rotate_right"):
		_yaw_steps -= 1
	elif event.is_action_pressed(&"build_cancel"):
		_select(&"")
		_hand_key = ""
	elif event.is_action_pressed(&"build_place") and BuildPhase.is_targeting(ItemDB.get_def(selected)):
		if _target_uid >= 0:
			_build.request_demolish(_target_uid)
	elif event.is_action_pressed(&"build_place") and _ghost.visible:
		_build.request_place(selected, _ghost_xf)
	else:
		return
	get_viewport().set_input_as_handled()


func _on_place_result(code: int, item_id: StringName) -> void:
	_toast.text = "%s: %s" % [ItemDB.get_def(item_id).display_name if ItemDB.get_def(item_id) else String(item_id),
		("removed it" if BuildPhase.is_targeting(ItemDB.get_def(item_id)) else "placed") if code == PlaceResult.OK
			else PlaceResult.describe(code)]
	_toast.modulate = Color(0.6, 1.0, 0.6) if code == PlaceResult.OK else Color(1.0, 0.5, 0.45)
	_toast_left = 2.5
	_toast.visible = true
	_last_key = ""
	_hand_key = ""
	_target_uid = -1
