class_name BuildCamera
extends Camera3D
## Top-down orthographic camera for the build phase (DESIGN §7). Owner: C08.
## frame() fits the whole track; while current: mouse wheel zooms toward the cursor, WASD / arrows or
## middle-drag pans (clamped to the framed area).
## NET: local only. Public API: `frame(bounds: AABB)`.

const HEIGHT := 120.0
const PAN_SPEED := 0.8 # TUNE: fraction of the view height per second
const ZOOM_STEP := 0.88 # TUNE: size factor per wheel notch
const MIN_SIZE := 20.0 # TUNE: m, closest zoom

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
	_max_size = size
	global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), c + Vector3.UP * HEIGHT)
	far = 300.0


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
	var mm := event as InputEventMouseMotion
	if mm and (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		var px := size / maxf(1.0, get_viewport().get_visible_rect().size.y) # m per pixel
		_pan(-mm.relative * px)


func _pan(d: Vector2) -> void:
	var p := global_position + Vector3(d.x, 0.0, d.y)
	var c := _bounds.get_center()
	p.x = clampf(p.x, _bounds.position.x, _bounds.end.x) if _bounds.size.x > 0.0 else p.x
	p.z = clampf(p.z, _bounds.position.z, _bounds.end.z) if _bounds.size.z > 0.0 else p.z
	if size >= _max_size * 0.999:
		p.x = c.x
		p.z = c.z
	global_position = p
