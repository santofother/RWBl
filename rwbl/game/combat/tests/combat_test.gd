extends Node3D
## C12 combat test (tools/tests/combat_test.sh; also F6 to watch it). Owner: C12.
## A Track (for respawn points) + two chariots driven by scripted ChariotInput into each other on real physics
## frames, away from the track (the ground plane is infinite): side rams break the slower one's wheels (limp,
## then crawl, then wreck = kill), horse-on-horse stuns, kill / self_kill attribution, respawn < 3 s repaired,
## crow drop spawns a mud_patch owned by the crow.
## Prints `[TEST] ok|FAIL <what>`, then `[TEST] COMBAT PASSED` / `FAILED`, and quits.
## NET: offline (the offline peer is the server).

const CHARIOT := preload("res://game/chariot/chariot.tscn")
const DT := 1.0 / 60.0
const ZONE := Vector3(600, 0, 600) # far from the track walls

## Found by Item.get_track() (ancestor with a `track` property).
var track: Track

var _fails := 0
var _a: Chariot # victim, slot 0
var _b: Chariot # rammer, slot 1
var _combat: Combat
var _items_root: Node3D
var _uid := 100
var _died: Array = []
var _kills: Array = []
var _self_kills: Array = []
var _respawned: Array = []
var _cam: Camera3D


func _ready() -> void:
	track = Track.new()
	add_child(track)
	_items_root = Node3D.new()
	_items_root.name = "Items"
	add_child(_items_root)
	_a = _make(0)
	_b = _make(1)
	_combat = Combat.new()
	_combat.name = "Combat"
	add_child(_combat)
	_combat.track = track
	_combat.spawner = _spawn
	_combat.register_chariot(0, _a)
	_combat.register_chariot(1, _b)
	GameEvents.chariot_died.connect(func(s: int, c: StringName, k: int, i: int) -> void: _died.append([s, c, k, i]))
	GameEvents.kill.connect(func(k: int, v: int, c: StringName) -> void: _kills.append([k, v, c]))
	GameEvents.self_kill.connect(func(s: int, i: int) -> void: _self_kills.append([s, i]))
	GameEvents.chariot_respawned.connect(func(s: int) -> void: _respawned.append(s))
	if DisplayServer.get_name() != "headless":
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		add_child(sun)
		_cam = Camera3D.new()
		add_child(_cam)
		_cam.make_current()
	await get_tree().physics_frame
	await _run_all()
	print("[TEST] COMBAT %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	if _cam:
		await get_tree().create_timer(2.0).timeout
	get_tree().quit(0 if _fails == 0 else 1)


func _process(_delta: float) -> void:
	if _cam:
		_cam.global_position = _cam.global_position.lerp(_a.global_position + Vector3(0, 14, 16), 0.1)
		_cam.look_at(_a.global_position, Vector3.UP)


func _make(slot: int) -> Chariot:
	var c := CHARIOT.instantiate() as Chariot
	c.slot = slot
	c.name = "Chariot%d" % slot
	c.tuning = ChariotTuning.new() # WHY: script defaults, so a saved default_tuning.tres can't break this test
	add_child(c)
	return c


func _check(ok: bool, what: String) -> void:
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _input_throttle(t: float) -> ChariotInput:
	var i := ChariotInput.new()
	i.throttle = t
	return i


## Put a chariot at `xf` at rest without repairing it.
func _put(c: Chariot, xf: Transform3D) -> void:
	c.global_transform = xf
	c.velocity = Vector3.ZERO
	c.cart_angle = 0.0
	c.cart_ang_vel = 0.0
	c._sync_bodies()


## Step both chariots on real physics frames (A idle, B full throttle) until `until` is true or `secs` pass.
func _drive(secs: float, until: Callable) -> bool:
	var idle := _input_throttle(0.0)
	var go := _input_throttle(1.0)
	for f in int(round(secs / DT)):
		await get_tree().physics_frame
		_a.step(idle, DT)
		_b.step(go, DT)
		if until.call():
			return true
	return false


## A stands still facing -Z at ZONE; B starts 12 m to A's right of `target` (A's cart or horses), facing it.
func _ram(target_cart: bool, until: Callable) -> bool:
	_put(_a, Transform3D(Basis.IDENTITY, ZONE))
	var aim := _a.cart_global_position() if target_cart else _a.global_position
	_b.respawn(Transform3D(Basis(Vector3.UP, PI * 0.5), aim + Vector3(12, 0, 0)))
	return await _drive(3.0, until)


func _wait_respawn(slot: int, secs: float) -> float: # seconds until chariot_respawned(slot), or -1
	var n := _respawned.count(slot)
	for f in int(round(secs / DT)):
		await get_tree().physics_frame
		if _respawned.count(slot) > n:
			return f * DT
	return -1.0


func _run_all() -> void:
	var top0: float = _a._top_speed()
	# 1) B rams A's cart from the right: right wheel only (immunity: one hit, not three).
	var hit := await _ram(true, func() -> bool: return _a.wheel_state != 0)
	await _drive(0.3, func() -> bool: return false)
	_check(hit and _a.wheel_state == ChariotSnapshot.WHEEL_RIGHT, "cart ram breaks the right wheel (%d)" % _a.wheel_state)
	_check(_b.wheel_state == 0 and not _b.has_effect(Effects.STUN), "rammer unhurt")
	var top1: float = _a._top_speed()
	_check(top1 < top0, "limp: top speed %.1f < %.1f" % [top1, top0])
	await _drive(0.6, func() -> bool: return false) # pair immunity runs out
	# 2) Second ram: the other wheel goes -> crawl.
	hit = await _ram(true, func() -> bool: return _a.wheel_state == 3)
	var top2: float = _a._top_speed()
	_check(hit and _a.wheel_state == 3, "second ram breaks the left wheel too")
	_check(top2 < top1, "crawl: top speed %.1f < %.1f" % [top2, top1])
	await _drive(0.6, func() -> bool: return false)
	# 3) Third ram on a wheel-less cart wrecks it: kill by B, respawn < 3 s, repaired, on the track.
	hit = await _ram(true, func() -> bool: return _a.dead)
	_check(hit and _a.dead, "third ram wrecks the cart")
	_check(_kills.has([1, 0, &"wheel"]), "kill event 1 -> 0 wheel %s" % [_kills])
	_check(_died.size() == 1 and _died[0] == [0, &"wheel", 1, -1], "chariot_died %s" % [_died])
	_check(_a.get_node(^"HorseBody").collision_layer == 0, "dead chariot is not solid")
	var t := await _wait_respawn(0, 3.0)
	_check(t >= 0.0 and t < 3.0, "respawned in %.2f s" % t)
	_check(not _a.dead and _a.wheel_state == 0, "respawn repaired the chariot")
	_check(track.is_on_track(_a.global_position), "respawned on the track")
	_check(_a.get_node(^"HorseBody").collision_layer == Layers.HORSES, "solid again")
	# 4) Horse-on-horse: A's horses get stunned, no wheel lost.
	await _drive(0.6, func() -> bool: return false)
	hit = await _ram(false, func() -> bool: return _a.has_effect(Effects.STUN))
	_check(hit and _a.has_effect(Effects.STUN) and _a.wheel_state == 0, "horse ram stuns, wheels intact")
	_check(not _b.has_effect(Effects.STUN), "rammer not stunned")
	# 5) Attribution: own item = self_kill (pit adds the penalty), other's spear = kill, other's item = neither.
	_a.kill(&"pit", 0, 7)
	_check(_self_kills.has([0, 7]) and _kills.size() == 1, "own pit = self_kill only")
	t = await _wait_respawn(0, 3.0)
	var pit_t := _combat.tuning.respawn_delay + _combat.tuning.pit_penalty
	_check(t > pit_t - 0.1 and t < 3.0, "pit respawn %.2f s (delay + penalty %.2f, < 3)" % [t, pit_t])
	_a.kill(&"spear", 1, -1)
	_check(_kills.has([1, 0, &"spear"]), "spear = kill")
	await _wait_respawn(0, 3.0)
	var kills_before := _kills.size()
	_a.kill(&"pit", 1, 9)
	_check(_kills.size() == kills_before and _self_kills.size() == 1, "other's pit = no kill, no self_kill")
	await _wait_respawn(0, 3.0)
	# 6) Crow: only crows drop; the drop is a mud_patch owned by the crow; cooldown holds the next one.
	var spot := track.point_at(track.length() * 0.3)
	_check(_combat.crow_drop(1, spot) == -1, "a driver can't drop")
	_combat.set_crow(1, true)
	_check(_combat.is_crow(1), "slot 1 is a crow")
	var uid := _combat.crow_drop(1, spot)
	var item := _items_root.get_node_or_null(NodePath("Item%d" % uid)) as Item
	_check(item != null and item.owner_slot == 1 and item.def.id == &"mud_patch", "crow drop = mud_patch owned by 1")
	_check(_combat.crow_drop(1, spot) == -1 and _combat.crow_cooldown_left(1) > 7.0, "crow cooldown")


func _spawn(slot: int, item_id: StringName, xf: Transform3D) -> int: # stands in for BuildPhase.spawn_extra
	var d := ItemDB.get_def(item_id)
	_uid += 1
	var item := d.scene.instantiate() as Item
	item.name = "Item%d" % _uid
	_items_root.add_child(item)
	item.global_transform = xf
	item.placed(d, slot, _uid)
	return _uid
