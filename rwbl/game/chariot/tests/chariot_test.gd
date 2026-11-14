extends Node
## C04 headless chariot test (run by tools/tests/chariot_test.sh). Owner: C04.
## Drives real Chariot scenes with scripted ChariotInput on a Track (no network): top speed, turning, oil
## slip, whip/stamina, broken wheels, snapshot round trip, wall/item/chariot collisions, jump + landing,
## effects, and the F2 TuningPanel (sliders, live edit, user:// save + load).
## Prints `[TEST] ok|FAIL <what>` lines, then `[TEST] CHARIOT PASSED` or `[TEST] CHARIOT FAILED`, and quits.
## NET: offline only.

const CHARIOT := preload("res://game/chariot/chariot.tscn")
const DT := 1.0 / 60.0
const BIG := Vector2(2000, 2000)


class TestItem extends Item:
	var hits := 0

	func chariot_hit(_c: Chariot, _part: StringName, _speed: float) -> void:
		hits += 1


var _fails := 0
var _track: Track
var _patch: Node3D
var _t: ChariotTuning


func _ready() -> void:
	_track = Track.new()
	add_child(_track)
	_patch = Node3D.new()
	add_child(_patch)
	_set_surface(Surface.NORMAL)
	_t = ChariotTuning.new() # WHY: script defaults, so a saved default_tuning.tres can't break the test
	await get_tree().physics_frame
	_test_driving()
	_test_snapshot()
	await _test_collisions()
	_test_air_and_effects()
	_test_tuning_panel()
	print("[TEST] CHARIOT %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("[TEST] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _set_surface(s: StringName) -> void:
	_track.unregister_surface_patch(_patch)
	_track.register_surface_patch(_patch, s, BIG)


func _spawn(at: Vector3) -> Chariot:
	var c := CHARIOT.instantiate() as Chariot
	c.tuning = _t
	c.track = _track
	add_child(c)
	c.respawn(Transform3D(Basis.IDENTITY, at))
	return c


func _inp(steer: float, throttle: float = 1.0, brake: float = 0.0) -> ChariotInput:
	var i := ChariotInput.new()
	i.steer = steer
	i.throttle = throttle
	i.brake = brake
	return i


func _run(c: Chariot, secs: float, inp: ChariotInput) -> void:
	for i in int(round(secs / DT)):
		c.step(inp, DT)


func _flat_speed(c: Chariot) -> float:
	return Vector2(c.velocity.x, c.velocity.z).length()


func _slip_deg(c: Chariot) -> float:
	var v := Vector3(c.velocity.x, 0, c.velocity.z)
	return 0.0 if v.length() < 1.0 else rad_to_deg(absf(c.get_forward().signed_angle_to(v, Vector3.UP)))


## Max horse slip angle and max |cart angle| (degrees) while turning hard on `s` at speed.
func _turn_slip(c: Chariot, s: StringName) -> Vector2:
	_set_surface(Surface.NORMAL)
	c.respawn(Transform3D.IDENTITY)
	_run(c, 2.0, _inp(0.0))
	_set_surface(s)
	var out := Vector2.ZERO
	var inp := _inp(1.0)
	for i in 120:
		c.step(inp, DT)
		out.x = maxf(out.x, _slip_deg(c))
		out.y = maxf(out.y, absf(rad_to_deg(c.cart_angle)))
	_set_surface(Surface.NORMAL)
	return out


func _test_driving() -> void:
	var c := _spawn(Vector3.ZERO)
	_run(c, 5.0, _inp(0.0))
	var top := c.get_speed()
	_check(top >= 0.9 * _t.max_speed, "full throttle reaches %.1f m/s (>= 90%% of %.1f)" % [top, _t.max_speed])
	_check(absf(c.cart_angle) < 0.02, "cart trails straight on a straight (%.3f rad)" % c.cart_angle)

	c.respawn(Transform3D.IDENTITY)
	_run(c, 1.0, _inp(0.0))
	var turned := 0.0
	var prev := c.get_forward()
	for i in 180:
		c.step(_inp(1.0), DT)
		turned += prev.signed_angle_to(c.get_forward(), Vector3.UP)
		prev = c.get_forward()
	_check(absf(turned) > PI * 0.5, "full steer turns %.0f° in 3 s (> 90)" % rad_to_deg(absf(turned)))
	_check(turned < 0.0, "steer +1 turns right")

	var normal := _turn_slip(c, Surface.NORMAL)
	var oil := _turn_slip(c, Surface.OIL)
	print("[TEST] slip normal %.1f° cart %.1f° | oil %.1f° cart %.1f°" % [normal.x, normal.y, oil.x, oil.y])
	_check(oil.x > 2.0 * normal.x + 5.0, "oil slip angle much larger than normal")

	# Whip
	c.respawn(Transform3D.IDENTITY)
	_run(c, 5.0, _inp(0.0))
	var v0 := c.get_speed()
	var w := _inp(0.0)
	w.whip = true
	c.step(w, DT)
	_run(c, 0.5, _inp(0.0))
	var v1 := c.get_speed()
	_check(v1 > v0 + 2.0, "whip boosts %.1f -> %.1f m/s" % [v0, v1])
	_check(c.stamina < 1.0 - _t.whip_stamina_cost + 0.1, "whip costs stamina (%.2f)" % c.stamina)
	c.respawn(Transform3D.IDENTITY)
	for i in 6:
		c.step(w, DT)
		_run(c, _t.whip_cooldown + DT, _inp(0.0))
	_check(c.stamina < 0.1, "6 rapid whips exhaust the horses (stamina %.2f)" % c.stamina)
	c.step(w, DT)
	_check(c.effect_strength(Effects.BOOST) < 0.5, "exhausted whip is weak or denied")

	# Wheels
	c.respawn(Transform3D.IDENTITY)
	c.damage_wheel(ChariotSnapshot.WHEEL_LEFT)
	_run(c, 5.0, _inp(0.0))
	var limp := _flat_speed(c)
	_check(limp < 0.9 * top and limp > _t.crawl_speed, "one broken wheel: top %.1f < %.1f" % [limp, top])
	c.damage_wheel(ChariotSnapshot.WHEEL_RIGHT)
	_run(c, 4.0, _inp(0.0))
	_check(_flat_speed(c) <= _t.crawl_speed + 0.2, "two broken wheels crawl (%.1f m/s)" % _flat_speed(c))
	c.free()


func _test_snapshot() -> void:
	var a := _spawn(Vector3.ZERO)
	var b := _spawn(Vector3(60, 0, 60))
	_run(a, 1.5, _inp(0.0))
	_set_surface(Surface.OIL)
	_run(a, 0.8, _inp(0.8))
	_set_surface(Surface.NORMAL)
	b.apply_snapshot(a.get_snapshot())
	_check(a.global_position.distance_to(b.global_position) < 0.01, "snapshot reproduces position")
	_check(a.global_basis.get_rotation_quaternion().angle_to(b.global_basis.get_rotation_quaternion()) < 0.01,
		"snapshot reproduces heading")
	_check(absf(a.cart_angle - b.cart_angle) < 0.001 and absf(a.cart_angle) > 0.05,
		"snapshot reproduces cart angle (%.2f rad)" % a.cart_angle)
	var cart_a := (a.get_node(^"Cart/CartBody") as Node3D).global_position
	var cart_b := (b.get_node(^"Cart/CartBody") as Node3D).global_position
	_check(cart_a.distance_to(cart_b) < 0.01 and cart_a.distance_to(a.cart_global_position()) < 0.01,
		"snapshot reproduces cart pose")
	a.free()
	b.free()


func _test_collisions() -> void:
	# Wall straight ahead.
	var wall := _box(Layers.WALL, Vector3(20, 4, 1), Vector3(0, 2, -30))
	add_child(wall)
	var c := _spawn(Vector3.ZERO)
	var hits: Array = []
	c.hit.connect(func(part: StringName, other: Node, speed: float) -> void: hits.append([part, other, speed]))
	await get_tree().physics_frame
	_run(c, 4.0, _inp(0.0))
	var wall_hit := hits.filter(func(h: Array) -> bool: return h[1] == wall and h[2] > 5.0)
	_check(not wall_hit.is_empty() and wall_hit[0][0] == &"horses", "wall hit emitted (horses, %d hits)" % hits.size())
	_check(c.global_position.z > -30.0, "chariot stopped by the wall (z %.1f)" % c.global_position.z)
	wall.free()

	# Item body.
	var item := TestItem.new()
	add_child(item)
	item.add_child(_box(Layers.ITEM_SOLID, Vector3(4, 3, 1), Vector3(0, 1.5, -30)))
	await get_tree().physics_frame
	c.respawn(Transform3D.IDENTITY)
	_run(c, 4.0, _inp(0.0))
	_check(item.hits >= 1, "item.chariot_hit() called (%d)" % item.hits)
	item.free()

	# Chariot vs chariot: a rams a parked b.
	c.respawn(Transform3D.IDENTITY)
	var b := _spawn(Vector3(0, 0, -25))
	var b_hits: Array = []
	b.hit.connect(func(part: StringName, other: Node, speed: float) -> void: b_hits.append([part, other, speed]))
	hits.clear()
	await get_tree().physics_frame
	var idle := _inp(0.0, 0.0)
	for i in 180:
		c.step(_inp(0.0), DT)
		b.step(idle, DT)
	var ram := hits.filter(func(h: Array) -> bool: return Chariot.find_chariot(h[1]) == b)
	_check(not ram.is_empty(), "rammer gets hit() with the other chariot")
	_check(not b_hits.is_empty() and Chariot.find_chariot(b_hits[0][1]) == c, "rammed chariot gets hit() too")
	_check(b.global_position.z < -26.0, "rammed chariot pushed forward (z %.1f)" % b.global_position.z)
	c.free()
	b.free()


func _test_air_and_effects() -> void:
	var c := _spawn(Vector3.ZERO)
	_run(c, 1.0, _inp(0.0))
	c.apply_impulse(Vector3.UP * 12.0 * _t.horse_mass)
	_run(c, 0.3, _inp(0.0))
	_check(not c.grounded and c.global_position.y > 1.0, "impulse launches (y %.1f)" % c.global_position.y)
	_run(c, 2.5, _inp(0.0))
	_check(c.grounded and absf(c.global_position.y) < 0.01 and not c.dead, "lands safely")

	c.respawn(Transform3D.IDENTITY)
	c.stun(2.0)
	_run(c, 1.0, _inp(1.0))
	_check(c.get_speed() < 0.5, "stun: no thrust")
	c.respawn(Transform3D.IDENTITY)
	_run(c, 1.0, _inp(0.0))
	c.add_effect(Effects.REVERSE_STEER, 3.0)
	var yaw := c.global_rotation.y
	_run(c, 0.5, _inp(1.0))
	_check(c.global_rotation.y > yaw + 0.1, "reverse_steer: steer right turns left")
	c.respawn(Transform3D.IDENTITY)
	c.add_effect(Effects.TANGLED, 10.0)
	_run(c, 4.0, _inp(0.0))
	_check(c.get_speed() < 0.5 * _t.max_speed, "tangled: slow (%.1f)" % c.get_speed())
	c.respawn(Transform3D.IDENTITY)
	c.add_effect(Effects.DRUNK, 10.0)
	_run(c, 3.0, _inp(0.0))
	_check(absf(c.global_rotation.y) > 0.05, "drunk: wobbles off a straight line")
	c.respawn(Transform3D.IDENTITY)
	c.frozen = true
	_run(c, 1.0, _inp(0.0))
	_check(c.global_position.length() < 0.01, "frozen: doesn't move")
	c.free()


func _test_tuning_panel() -> void:
	var panel := TuningPanel
	var found := panel.registered().any(func(e: Dictionary) -> bool: return e["res"] == _t)
	_check(found, "chariot registers its tuning on spawn")
	var expected := 0
	for e: Dictionary in panel.registered():
		for p: Dictionary in (e["res"] as Resource).get_property_list():
			if p["hint"] == PROPERTY_HINT_RANGE and p["usage"] & PROPERTY_USAGE_EDITOR:
				expected += 1
	panel.set_open(true)
	_check(panel.is_open() and panel.slider_count() == expected and expected > 40,
		"panel shows a slider per @export_range field (%d)" % panel.slider_count())
	var slider := panel.find_children("*", "HSlider", true, false)
	if panel.registered()[0]["res"] == _t and not slider.is_empty():
		(slider[0] as HSlider).value = 33.0
		_check(is_equal_approx(_t.horse_thrust, 33.0), "slider edits the resource live")
	panel.set_open(false)

	var r := ChariotTuning.new()
	r.take_over_path("res://game/chariot/tests/_panel_roundtrip.tres")
	var old: bool = panel.use_user_dir
	panel.use_user_dir = false
	_check(panel.save_path_for(r) == r.resource_path, "editor saves to the res:// path")
	panel.use_user_dir = true
	r.max_speed = 31.0
	var path: String = panel.save_resource(r)
	_check(path == "user://tuning/_panel_roundtrip.tres", "exported build saves to user://tuning/")
	r.max_speed = 5.0
	_check(panel.load_override(r) and is_equal_approx(r.max_speed, 31.0), "user:// override loads over defaults")
	DirAccess.remove_absolute(path)
	panel.use_user_dir = old


func _box(layer: int, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	return body
