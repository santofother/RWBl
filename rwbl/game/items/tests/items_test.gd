extends Node3D
## C10 item gauntlet (tools/tests/items_test.sh; also F6 to watch it). Owner: C10.
## A Track + one Chariot driven by scripted ChariotInput straight through each item, one at a time, on real
## physics frames (Area3D triggers, shape casts). Checks every item's effect, report_hit / trap_hit (owner
## never scores), and the slide_far tag rule (column on an oil slick).
## Prints `[TEST] ok|FAIL <what>`, then `[TEST] ITEMS PASSED` / `FAILED`, and quits.
## NET: offline (the offline peer is the server).

const CHARIOT := preload("res://game/chariot/chariot.tscn")
const DT := 1.0 / 60.0
const START := 10.0 # progress of the run-up start, m
const OTHER_SLOT := 3 # owner of most test items (not the driver)

## Found by Item.get_track() (ancestor with a `track` property).
var track: Track

var _fails := 0
var _c: Chariot
var _items_root: Node3D
var _uid := 0
var _traps: Array = [] # [uid, owner, victim]
var _deaths: Array = [] # [cause, src, uid]
var _cam: Camera3D


func _ready() -> void:
	track = Track.new()
	add_child(track)
	_items_root = Node3D.new()
	_items_root.name = "Items"
	add_child(_items_root)
	_c = CHARIOT.instantiate() as Chariot
	_c.slot = 0
	_c.tuning = ChariotTuning.new() # WHY: script defaults, so a saved default_tuning.tres can't break this test
	_c.track = track
	add_child(_c)
	_c.died.connect(func(cause: StringName, src: int, id: int) -> void: _deaths.append([cause, src, id]))
	GameEvents.trap_hit.connect(func(id: int, o: int, v: int) -> void: _traps.append([id, o, v]))
	if DisplayServer.get_name() != "headless":
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		add_child(sun)
		_cam = Camera3D.new()
		add_child(_cam)
		_cam.make_current()
	await get_tree().physics_frame
	await _run_all()
	print("[TEST] ITEMS %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	if _cam:
		await get_tree().create_timer(2.0).timeout
	get_tree().quit(0 if _fails == 0 else 1)


func _process(_delta: float) -> void:
	if _cam and _c:
		var back := _c.global_basis.z * 9.0 + Vector3.UP * 4.5
		_cam.global_position = _cam.global_position.lerp(_c.global_position + back, 0.1)
		_cam.look_at(_c.global_position + Vector3.UP, Vector3.UP)


func _check(ok: bool, what: String) -> void:
	print("[TEST] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


## Spawn like BuildPhase does: instance def.scene under Items, set the transform, placed().
func _place(id: StringName, at: float, slot: int = OTHER_SLOT, lateral: float = 0.0) -> Item:
	var d := ItemDB.get_def(id)
	var item := d.scene.instantiate() as Item
	_uid += 1
	item.name = "Item%d" % _uid
	_items_root.add_child(item)
	var xf := track.transform_at(at)
	xf.origin += xf.basis.x * lateral
	item.global_transform = xf
	item.placed(d, slot, _uid)
	return item


func _clear_items() -> void:
	for n in _items_root.get_children():
		n.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


## Respawn the chariot at `progress` facing the track, already rolling at `speed`.
func _start(progress: float, speed: float) -> void:
	_c.respawn(track.transform_at(progress))
	_c.velocity = _c.get_forward() * speed
	_deaths.clear()
	await get_tree().physics_frame


func _inp(steer: float, throttle: float = 1.0, brake: float = 0.0) -> ChariotInput:
	var i := ChariotInput.new()
	i.steer = steer
	i.throttle = throttle
	i.brake = brake
	return i


func _flat_speed() -> float:
	return Vector2(_c.velocity.x, _c.velocity.z).length()


func _slip_deg() -> float:
	var v := Vector3(_c.velocity.x, 0, _c.velocity.z)
	return 0.0 if v.length() < 1.0 else rad_to_deg(absf(_c.get_forward().signed_angle_to(v, Vector3.UP)))


## Step the chariot on real physics frames for `secs`; `each` gets called after every step and may return
## true to stop early. `input` may be a ChariotInput or a Callable returning one.
func _drive(secs: float, input: Variant, each: Callable = Callable()) -> void:
	for f in int(round(secs / DT)):
		await get_tree().physics_frame
		var inp: ChariotInput = input.call() if input is Callable else input
		_c.step(inp, DT)
		if each.is_valid() and each.call():
			return


func _trap_for(uid: int) -> Array:
	return _traps.filter(func(t: Array) -> bool: return t[0] == uid)


func _run_all() -> void:
	await _oil()
	await _mud_owner()
	await _ice()
	await _pad()
	await _ramp()
	await _column_horses()
	await _column_cart()
	await _axe()
	await _pit()
	await _slide_far()
	await _removed_cleanup()


func _oil() -> void:
	# Same steering (full lock while the horses are over the patch area) with and without the oil slick.
	var normal: Vector2 = await _oil_run()
	var it := _place(&"oil_slick", START + 25.0)
	var on := [false]
	var oil: Vector2 = await _oil_run(on)
	_check(on[0], "oil: horses reached the oil patch (surface patch registered)")
	_check(oil.x > 8.0 and oil.x > normal.x * 1.5,
		"oil: large slip angle (%.1f deg on oil vs %.1f on the road)" % [oil.x, normal.x])
	_check(oil.y < normal.y * 0.5,
		"oil: the chariot keeps sliding straight (course change %.1f vs %.1f deg)" % [oil.y, normal.y])
	_check(_trap_for(it.uid).size() == 1 and _trap_for(it.uid)[0] == [it.uid, OTHER_SLOT, 0],
		"oil: one trap_hit for a victim that isn't the owner")
	await _clear_items()


## Returns (max slip deg, course change deg while over the patch area).
func _oil_run(on: Array = [false]) -> Vector2:
	await _start(START, 10.0)
	var lo := START + 25.0 - 2.5
	var hi := START + 25.0 + 2.5
	var max_slip := [0.0]
	var v0 := _c.velocity
	var course := [0.0]
	await _drive(2.5, func() -> ChariotInput:
			var p := track.progress_at(_c.global_position)
			return _inp(1.0 if p > lo and p < hi else 0.0),
		func() -> bool:
			on[0] = on[0] or _c.surface == Surface.OIL
			max_slip[0] = maxf(max_slip[0], _slip_deg())
			var p := track.progress_at(_c.global_position)
			if p > lo and p < hi:
				course[0] = rad_to_deg(absf(Vector3(v0.x, 0, v0.z).signed_angle_to(
					Vector3(_c.velocity.x, 0, _c.velocity.z), Vector3.UP)))
			return false)
	return Vector2(max_slip[0], course[0])


func _mud_owner() -> void:
	var it := _place(&"mud_patch", START + 25.0, 0) # placed by the driver himself
	await _start(START, 20.0)
	var entry := [-1.0]
	var exit_speed := [-1.0]
	await _drive(2.5, _inp(0.0), func() -> bool:
		if _c.surface == Surface.MUD and entry[0] < 0.0:
			entry[0] = _flat_speed()
		if _c.surface != Surface.MUD and entry[0] > 0.0 and exit_speed[0] < 0.0:
			exit_speed[0] = _flat_speed()
		return exit_speed[0] > 0.0)
	_check(entry[0] > 0.0 and exit_speed[0] < entry[0] - 2.0,
		"mud: lower speed (in %.1f, out %.1f m/s)" % [entry[0], exit_speed[0]])
	_check(it._reported.has(0), "mud: report_hit counted the owner's own chariot (logged HIT)")
	_check(_trap_for(it.uid).is_empty(), "mud: no trap_hit when the victim is the owner")
	await _clear_items()


func _ice() -> void:
	var it := _place(&"ice_sheet", START + 25.0)
	await _start(START, 15.0)
	var yaw0 := [INF]
	var turned := [0.0]
	var locked := [false]
	await _drive(2.5, func() -> ChariotInput: return _inp(1.0 if _c.surface == Surface.ICE else 0.0),
		func() -> bool:
			if _c.surface == Surface.ICE:
				if yaw0[0] == INF:
					yaw0[0] = _c.global_rotation.y
				turned[0] = maxf(turned[0], absf(angle_difference(yaw0[0], _c.global_rotation.y)))
				locked[0] = locked[0] or _c.has_effect(Effects.NO_STEER)
			return false)
	_check(yaw0[0] != INF and locked[0], "ice: NO_STEER on the chariot while its horses are on the ice")
	_check(rad_to_deg(turned[0]) < 1.0, "ice: full steering lock has no effect (%.2f deg)" % rad_to_deg(turned[0]))
	_check(_trap_for(it.uid).size() == 1, "ice: trap_hit")
	# Stopped on the ice: steering works again, so the chariot can always get off it.
	_c.respawn(it.global_transform)
	await _drive(1.5, _inp(1.0, 0.4))
	var yaw_turn := rad_to_deg(absf(angle_difference(it.global_rotation.y, _c.global_rotation.y)))
	_check(yaw_turn > 10.0 and _flat_speed() > 1.0,
		"ice: a chariot that stopped on the ice can steer and drive off (turned %.0f deg)" % yaw_turn)
	await _clear_items()


func _pad() -> void:
	var it := _place(&"speed_pad", START + 20.0)
	await _start(START, _c.tuning.max_speed)
	var top := [0.0]
	await _drive(2.0, _inp(0.0), func() -> bool:
		top[0] = maxf(top[0], _flat_speed())
		return false)
	_check(top[0] > _c.tuning.max_speed + 1.0, "pad: speed above max (%.1f > %.1f)" % [top[0], _c.tuning.max_speed])
	_check(_trap_for(it.uid).size() == 1, "pad: trap_hit")
	await _clear_items()


func _ramp() -> void:
	var it := _place(&"ramp", START + 20.0)
	await _start(START, 15.0)
	var peak := [0.0]
	var air := [false]
	await _drive(2.5, _inp(0.0), func() -> bool:
		air[0] = air[0] or not _c.grounded
		peak[0] = maxf(peak[0], _c.global_position.y - track.point_at(START).y)
		return false)
	_check(air[0] and peak[0] > 1.0, "ramp: launched airborne (peak %.1f m)" % peak[0])
	_check(_c.grounded, "ramp: landed again")
	_check(_trap_for(it.uid).size() == 1, "ramp: trap_hit")
	await _clear_items()


func _column_horses() -> void:
	var it := _place(&"column", START + 15.0)
	var at := it.global_position
	await _start(START, 10.0)
	var stunned := [false]
	await _drive(2.0, _inp(0.0), func() -> bool:
		stunned[0] = stunned[0] or _c.has_effect(Effects.STUN)
		return stunned[0])
	_check(stunned[0] and _c.wheel_state == 0, "column: horse hit stuns (wheels intact)")
	_check(it.global_position.distance_to(at) < 0.01, "column: stays put without a slippery item under it")
	_check(_trap_for(it.uid).size() == 1, "column: trap_hit")
	await _clear_items()


func _column_cart() -> void:
	# Column right behind the cart; reversing backs the cart into it.
	var it := _place(&"column", START + 4.0)
	await _start(START + 9.5, 0.0)
	await _drive(2.5, _inp(0.0, 0.0, 1.0), func() -> bool: return _c.wheel_state != 0)
	_check(_c.wheel_state != 0 and not _c.has_effect(Effects.STUN), "column: cart hit breaks a wheel (state %d)" % _c.wheel_state)
	_check(_trap_for(it.uid).size() == 1, "column: trap_hit once per chariot per race")
	await _clear_items()


func _axe() -> void:
	var it := _place(&"swinging_axe", START + 25.0) as Item
	await _start(START, 8.0)
	var hit_angle := [INF]
	var axe_at := it.global_position
	# Roll up to the gantry and stop under it: the blade must sweep through within one period.
	await _drive(8.0, func() -> ChariotInput:
			var under := (_c.global_position - axe_at).dot(_c.get_forward()) > -0.5
			return _inp(0.0, 0.0 if under else 0.4, 1.0 if under else 0.0),
		func() -> bool:
		if (_c.dead or _c.has_effect(Effects.STUN)) and hit_angle[0] == INF:
			hit_angle[0] = rad_to_deg(it.call(&"swing_angle"))
		return hit_angle[0] != INF)
	_check(hit_angle[0] != INF, "axe: blade hit the chariot")
	# C24: the blade is lethal by default
	_check(_c.dead and _deaths.size() >= 1 and _deaths[-1] == [&"axe", OTHER_SLOT, it.uid],
		"axe: lethal, died (axe, owner, uid) %s" % [_deaths])
	_check(absf(hit_angle[0]) < 35.0, "axe: hit inside the swing window (angle %.0f deg)" % hit_angle[0])
	var a1: float = it.call(&"swing_angle", 10.0)
	var a2: float = it.call(&"swing_angle", 10.0 + Item.tuning().axe_period)
	_check(is_equal_approx(a1, a2), "axe: swing is a pure function of NetClock time (periodic)")
	_check(_trap_for(it.uid).size() == 1, "axe: trap_hit")
	await _clear_items()


func _pit() -> void:
	var it := _place(&"pit", START + 20.0)
	await _start(START, 10.0)
	await _drive(3.0, _inp(0.0), func() -> bool: return _c.dead)
	_check(_deaths.size() == 1 and _deaths[0] == [&"pit", OTHER_SLOT, it.uid], "pit: died (pit, owner, uid) %s" % [_deaths])
	_check(_trap_for(it.uid).size() == 1, "pit: trap_hit")
	await _clear_items()


func _slide_far() -> void:
	var col := _place(&"column", START + 20.0)
	await get_tree().physics_frame # column's own placement check (nothing near yet)
	var oil := _place(&"oil_slick", START + 20.0, OTHER_SLOT, 0.5)
	await get_tree().physics_frame # oil's check finds the column
	_check(col.applied_rules.has("%d:slide_far" % oil.uid), "tags: oil placed under a column links them (slide_far)")
	var at := col.global_position
	await _start(START, 14.0)
	await _drive(1.5, _inp(0.0), func() -> bool: return _c.has_effect(Effects.STUN))
	await _drive(4.0, _inp(0.0, 0.0, 1.0))
	var moved := col.global_position.distance_to(at)
	_check(moved > 5.0, "tags: heavy column on oil slides far when hit (%.1f m)" % moved)
	# Race start re-checks pairs but never applies the same rule twice.
	var before := col.applied_rules.size()
	ItemInteractions.check_item(col)
	_check(col.applied_rules.size() == before, "tags: a pair's rule fires once")
	await _clear_items()


## C17 Demolish: a removed surface item gives the road back (patch unregisters on _exit_tree), and the
## Demolish card is a targeting card (no scene).
func _removed_cleanup() -> void:
	_clear_items()
	await get_tree().physics_frame
	var at := 120.0
	var oil := _place(&"oil_slick", at)
	await get_tree().physics_frame
	var p := track.transform_at(at).origin
	_check(track.surface_at(p) == Surface.OIL, "removed: oil patch registered before removal")
	oil.queue_free()
	await get_tree().physics_frame
	_check(track.surface_at(p) == Surface.NORMAL, "removed: road is normal again after the oil is freed")
	var d := ItemDB.get_def(&"demolish")
	_check(d != null and d.scene == null and BuildPhase.is_targeting(d) and d.category == ItemDef.Category.WILDCARD
		and d.rarity == ItemDef.Rarity.UNCOMMON, "demolish def: uncommon wildcard targeting card")
