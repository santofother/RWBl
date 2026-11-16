class_name BuildCamera
extends Camera3D
## Top-down orthographic camera for the build phase (DESIGN §7). Owner: C08.
## frame() fits the whole track; while current: mouse wheel zooms toward the cursor, WASD / arrows, right- or
## middle-drag pan, and left-drag too while `left_drag_pans` (BuildUI sets it when no item is held). C24: panning
## works at every zoom (clamped to the framed area plus half a view) and you can zoom out past the full course.
## NET: local only. Public API: `frame(bounds: AABB)`, `update_bounds(bounds)`, `left_drag_pans`, `dragged_px`.

const HEIGHT := 120.0
const PAN_SPEED := 0.8 # TUNE: fraction of the view height per second
const ZOOM_STEP := 0.88 # TUNE: size factor per wheel notch
const MIN_SIZE := 20.0 # TUNE: m, closest zoom
const ZOOM_OUT := 1.5 # TUNE: x the full-course size, farthest zoom (C24)

## C24: left-drag pans as well (BuildUI: true while no item is selected).
var left_drag_pans := true
## C24: pixels the mouse moved while the current drag button is held (BuildUI: a right-click that dragged
## is a pan, not a cancel).
var dragged_px := 0.0

var _bounds := AABB()
var _max_size := 100.0


## Look straight down so `bounds` fills the view.
func frame(bounds: AABB) -> void:
	_bounds = bounds
	projection = PROJECTION_ORTHOGONAL
	var c := bounds.get_center()
	var aspect := 16.0 / 9.0
	if is_inside_tree():
		var vs := get_viewport().get_visible_rect().size
		if vs.y > 0.0:
			aspect = vs.x / vs.y
	size = maxf(bounds.size.z, bounds.size.x / aspect) * 1.05
	_max_size = size * ZOOM_OUT
	global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), c + Vector3.UP * HEIGHT)
	far = 300.0


## C24: the course changed mid-build (a piece was inserted): widen the pan / zoom limits, keep the view.
func update_bounds(bounds: AABB) -> void:
	var old := _bounds
	_bounds = bounds
	if old.size == Vector3.ZERO:
		frame(bounds)
		return
	var aspect := 16.0 / 9.0
	var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	if vs.y > 0.0:
		aspect = vs.x / vs.y
	_max_size = maxf(bounds.size.z, bounds.size.x / aspect) * 1.05 * ZOOM_OUT


func _process(delta: float) -> void:
	if not current:
		return
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if v != Vector2.ZERO:
		_pan(v * size * PAN_SPEED * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var before := project_position(mb.position, HEIGHT)
		size = clampf(size * (ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP),
			MIN_SIZE, _max_size)
		var after := project_position(mb.position, HEIGHT)
		_pan(Vector2(before.x - after.x, before.z - after.z))
		get_viewport().set_input_as_handled()
	if mb and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		dragged_px = 0.0
	var mm := event as InputEventMouseMotion
	var mask := MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT | (MOUSE_BUTTON_MASK_LEFT if left_drag_pans else 0)
	if mm and (mm.button_mask & mask):
		var px := size / maxf(1.0, get_viewport().get_visible_rect().size.y) # m per pixel
		dragged_px += mm.relative.length()
		_pan(-mm.relative * px)


func _pan(d: Vector2) -> void:
	var p := global_position + Vector3(d.x, 0.0, d.y)
	var m := size * 0.5 # WHY (C24): reach the course edges even zoomed out; never lose the course entirely
	p.x = clampf(p.x, _bounds.position.x - m, _bounds.end.x + m) if _bounds.size.x > 0.0 else p.x
	p.z = clampf(p.z, _bounds.position.z - m, _bounds.end.z + m) if _bounds.size.z > 0.0 else p.z
	global_position = p
