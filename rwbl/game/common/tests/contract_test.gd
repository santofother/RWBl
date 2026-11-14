extends Node
## Contract checks (C02): every contract class/signal exists and the stubs behave. Owner: C02 (head engineer).
## Builders may ADD checks here for new contracts; never delete one to make a test pass.
## NET: standalone local test. Prints `[TEST] CONTRACT PASSED` or `[TEST] FAIL <what>`.

const CLASSES: Array[String] = ["ChariotInput", "ChariotSnapshot", "PlayerInfo", "PlayerResult", "GameMode",
	"Phase", "ItemDef", "TagRule", "TagTable", "PlaceResult", "Surface", "Effects", "Layers", "Chariot",
	"ChariotTuning", "PlayerInput", "Track", "RaceController", "ChariotSync", "BotDriver", "BotManager",
	"BuildPhase", "Draft", "Scoring", "Combat", "Item", "ItemDB", "RaceCamera", "BuildCamera",
	"CameraDirector", "Hud", "MatchMode"]
const EVENTS := {"phase_changed": 2, "phase_end_requested": 1, "roster_changed": 0, "item_placed": 4,
	"item_removed": 1, "lap_completed": 3, "clean_lap": 2, "chariot_finished": 3, "race_over": 1,
	"trap_hit": 3, "chariot_died": 4, "kill": 3, "self_kill": 2, "chariot_respawned": 1, "round_scored": 2}
const CHARIOT_METHODS: Array[String] = ["step", "get_snapshot", "apply_snapshot", "get_speed", "get_forward",
	"cart_global_position", "add_effect", "has_effect", "apply_impulse", "damage_wheel", "stun", "kill",
	"respawn"]
const CHARIOT_SIGNALS: Array[String] = ["hit", "wheel_broken", "died", "respawned"]
const TRACK_METHODS: Array[String] = ["length", "get_center_curve", "progress_at", "point_at", "transform_at",
	"lateral_offset", "is_on_track", "surface_at", "register_surface_patch", "unregister_surface_patch",
	"start_transform", "checkpoint_count", "checkpoint_progress", "respawn_transform", "is_in_no_build_zone",
	"get_bounds"]
const ITEM_HOOKS: Array[String] = ["placed", "race_started", "race_ended", "triggered", "chariot_entered",
	"chariot_hit", "interact", "report_hit", "trigger"]
const MATCH_CHILDREN: Array[String] = ["Track", "Items", "Chariots", "ChariotSync", "Race", "Draft", "Build",
	"Scoring", "Combat", "Bots", "Cameras", "Hud"]

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("[TEST] FAIL ", what)


func _ready() -> void:
	_classes()
	_events()
	_input_and_snapshot()
	_items()
	await _match_and_stubs()
	print("[TEST] CONTRACT PASSED" if _fails == 0 else "[TEST] CONTRACT FAILED (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _classes() -> void:
	var names: Array[String] = []
	for c: Dictionary in ProjectSettings.get_global_class_list():
		names.append(String(c["class"]))
	for c in CLASSES:
		_check(names.has(c), "class %s missing" % c)


func _events() -> void:
	var sigs := {}
	for s: Dictionary in GameEvents.get_signal_list():
		sigs[s["name"]] = (s["args"] as Array).size()
	for e: String in EVENTS:
		_check(sigs.get(e, -1) == EVENTS[e], "GameEvents.%s missing or wrong arg count" % e)


func _input_and_snapshot() -> void:
	var i := ChariotInput.new()
	i.steer = -0.5
	i.throttle = 1.0
	i.brake = 0.25
	i.press_whip()
	i.press_whip()
	i.press_action()
	i.seq = 123456
	var b := i.to_bytes()
	_check(b.size() == 9, "ChariotInput wire size 9")
	var o := ChariotInput.from_bytes(b)
	_check(absf(o.steer + 0.5) < 0.01 and o.throttle == 1.0 and absf(o.brake - 0.25) < 0.01, "input roundtrip axes")
	_check(o.whip_count == 2 and o.action_count == 1 and o.seq == 123456, "input roundtrip counters")
	_check(ChariotSnapshot.SIZE == 15, "snapshot SIZE 15")
	var s := ChariotSnapshot.make(Vector3(1, 2, 3), Quaternion.IDENTITY, Vector3(4, 5, 6), 0.1, 0.2, 3, 0.5, 7)
	_check(s.size() == ChariotSnapshot.SIZE and ChariotSnapshot.pos(s) == Vector3(1, 2, 3), "snapshot make/pos")
	_check(ChariotSnapshot.vel(s) == Vector3(4, 5, 6) and int(s[ChariotSnapshot.FLAGS]) == 7, "snapshot vel/flags")
	var p := PlayerInfo.from_dict(PlayerInfo.create(3, 42, "Ann", true).to_dict())
	_check(p.slot == 3 and p.peer_id == 42 and p.name == "Ann" and p.is_bot, "PlayerInfo roundtrip")
	_check(Phase.name_of(Phase.RACE) == "race" and Phase.from_name("build") == Phase.BUILD, "Phase names")
	_check(PlaceResult.describe(PlaceResult.BLOCKS_PATH) != "", "PlaceResult text")


func _items() -> void:
	var ids := ItemDB.ids()
	for id in [&"oil_slick", &"mud_patch", &"ice_sheet", &"speed_pad", &"ramp", &"column", &"swinging_axe", &"pit"]:
		_check(ids.has(id), "ItemDef %s missing" % id)
	for d in ItemDB.all_defs():
		_check(d.scene != null and d.footprint.x > 0.0 and d.footprint.y > 0.0, "ItemDef %s scene/footprint" % d.id)
		var inst := d.scene.instantiate()
		_check(inst is Item, "ItemDef %s scene root extends Item" % d.id)
		inst.free()
	var table := ItemDB.tag_table()
	_check(table != null, "tag table loads")
	if table:
		var a: Array[StringName] = [&"flammable", &"slippery"]
		var b: Array[StringName] = [&"hot"]
		var r := table.lookup(a, b)
		_check(r.size() == 1 and r[0].effect == &"ignite", "tag table: flammable + hot = ignite")
		_check(table.lookup(b, a).size() == 1, "tag table order-insensitive")


func _match_and_stubs() -> void:
	var m := (load("res://game/match/match.tscn") as PackedScene).instantiate() as MatchMode
	add_child(m)
	for c in MATCH_CHILDREN:
		_check(m.has_node(c), "match child %s" % c)
	var ps: Array[PlayerInfo] = [PlayerInfo.create(0, 1, "Bot0", true), PlayerInfo.create(1, 1, "Bot1", true)]
	m.setup(ps, {"rounds": 2})
	_check(int(m.rules["rounds"]) == 2 and m.rules.has("race_time"), "rules merged with defaults")
	var c := m.chariot_sync.get_chariot(1) as Chariot
	_check(c != null and c.name == "Chariot1" and c.get_parent() == m.chariots_root, "chariot spawned per player")
	if c == null:
		return
	for f in CHARIOT_METHODS:
		_check(c.has_method(f), "Chariot.%s" % f)
	for sname in CHARIOT_SIGNALS:
		_check(c.has_signal(sname), "Chariot signal %s" % sname)
	for f in TRACK_METHODS:
		_check(m.track.has_method(f), "Track.%s" % f)
	var item := Item.new()
	for f in ITEM_HOOKS:
		_check(item.has_method(f), "Item.%s" % f)
	item.free()

	# Track stub behaves.
	var t := m.track
	_check(t.length() > 100.0, "track length")
	_check(t.surface_at(t.point_at(50.0)) == Surface.NORMAL, "centre is normal surface")
	_check(t.surface_at(t.point_at(50.0) + t.transform_at(50.0).basis.x * 30.0) == Surface.OFFTRACK, "off track")
	_check(t.is_on_track(t.start_transform(4).origin), "grid spot 4 on track")
	_check(t.is_in_no_build_zone(t.point_at(0.0)) and not t.is_in_no_build_zone(t.point_at(120.0)), "no-build zone")
	var patch := Node3D.new()
	add_child(patch)
	patch.global_position = t.point_at(80.0)
	t.register_surface_patch(patch, Surface.OIL, Vector2(2, 2))
	_check(t.surface_at(t.point_at(80.0)) == Surface.OIL, "surface patch")
	t.unregister_surface_patch(patch)
	patch.queue_free()

	# Chariot stub drives forward and snapshots.
	c.respawn(t.start_transform(0))
	var start := c.global_position
	var inp := ChariotInput.new()
	inp.throttle = 1.0
	for i in 60:
		c.step(inp, 1.0 / 60.0)
	_check(c.global_position.distance_to(start) > 3.0 and c.get_speed() > 3.0, "chariot stub moves with throttle")
	var other := m.chariot_sync.get_chariot(0) as Chariot
	other.apply_snapshot(c.get_snapshot())
	_check(other.global_position.distance_to(c.global_position) < 0.01, "snapshot applies position")
	var died := [false]
	c.died.connect(func(_a: StringName, _b: int, _c: int) -> void: died[0] = true)
	c.kill(&"pit", -1, 5)
	_check(died[0] and c.dead, "kill emits died")
	c.respawn(t.start_transform(0))
	_check(not c.dead, "respawn revives")
	await get_tree().process_frame
	m.queue_free()
