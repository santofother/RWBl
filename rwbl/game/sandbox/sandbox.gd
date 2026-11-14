extends Node3D
## Network sandbox (milestone N1): main menu, flat plane, one WASD cube per player. Owner: C02 (was C01).
## Kept as the N1 regression scene for net_test after C03 makes lobby/main.tscn the main scene.
## Menu is built in code to keep the .tscn tiny.
## NET: runs on every peer. Spawning/despawning cubes is server only (MultiplayerSpawner replicates).
## Movement: input up / snapshot down through ChariotSync (host-authoritative, AGENTS §Conventions).
## Public API: none. CLI (after `--`): `--host`, `--join=IP`, `--port=N`, `--name=X`, `--no-steam`,
##   `--test-target=x,z` (local input steers the cube to x,z), `--autotest=SEC` (prints `[TEST] PEERS n`
##   and `[TEST] POS <name> x z`),
##   `--quit-after=SEC`.

const CUBE_SCENE := preload("res://game/sandbox/cube.tscn")
## Spawn spots on the plane, one per player slot.
const SPAWNS: Array[Vector3] = [Vector3(0, 0.5, 0), Vector3(3, 0.5, 0), Vector3(-3, 0.5, 0),
	Vector3(0, 0.5, 3), Vector3(0, 0.5, -3)]

@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var chariot_sync: ChariotSync = $ChariotSync

var _menu: PanelContainer
var _in_game: HBoxContainer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _lobbies: VBoxContainer


func _ready() -> void:
	spawner.spawn_function = _spawn_cube
	NetworkManager.player_registered.connect(_on_player_registered)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.status_changed.connect(_set_status)
	NetworkManager.connection_failed.connect(_set_status)
	SteamManager.status_changed.connect(_set_status)
	SteamManager.lobby_list_updated.connect(_on_lobby_list)
	_build_ui()
	_set_status("Steam: " + SteamManager.init_message)
	if NetworkManager.test_target != null:
		chariot_sync.local_input_source = _seek_input
	_run_cli()


func _process(_delta: float) -> void:
	var in_s := NetworkManager.is_in_session()
	_menu.visible = not in_s
	_in_game.visible = in_s


# ---------------------------------------------------------------- session / spawning

func _run_cli() -> void:
	var a := NetworkManager.args
	var port := int(a.get("port", NetworkManager.DEFAULT_PORT))
	if a.has("host"):
		NetworkManager.host_enet(port)
	elif a.has("join"):
		NetworkManager.join_enet(String(a["join"]), port)
	var t := String(a.get("autotest", ""))
	if not t.is_empty():
		get_tree().create_timer(float(t)).timeout.connect(_autotest_report)
		var q := float(a.get("quit-after", float(t) + 0.1))
		get_tree().create_timer(q).timeout.connect(get_tree().quit)


func _on_player_registered(id: int, pname: String) -> void: # NET: server only
	if players.has_node(str(id)):
		return
	var used: Array[int] = []
	for c in players.get_children():
		used.append(c.slot)
	var slot := 0
	while used.has(slot):
		slot += 1
	spawner.spawn({"id": id, "name": pname, "pos": SPAWNS[slot % SPAWNS.size()], "slot": slot})
	print("[Game] Spawned cube for ", pname, " (", id, ")")


func _spawn_cube(data: Dictionary) -> Node:
	var c := CUBE_SCENE.instantiate()
	c.name = str(data["id"])
	c.peer_id = data["id"]
	c.display_name = data["name"]
	c.position = data["pos"]
	c.slot = data["slot"]
	chariot_sync.add_chariot(c.slot, c, c.peer_id)
	c.tree_exiting.connect(chariot_sync.remove_chariot.bind(c.slot))
	return c


## Test hook input: steer the local cube toward NetworkManager.test_target (x, z).
func _seek_input(slot: int) -> ChariotInput:
	var inp := ChariotInput.new()
	var c := chariot_sync.get_chariot(slot)
	if c:
		var t: Vector2 = NetworkManager.test_target
		var dx := t.x - c.position.x
		var dz := t.y - c.position.z
		inp.steer = clampf(dx, -1.0, 1.0)
		inp.throttle = clampf(-dz, 0.0, 1.0)
		inp.brake = clampf(dz, 0.0, 1.0)
	return inp


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server() and players.has_node(str(id)):
		players.get_node(str(id)).queue_free()


func _on_session_ended(_reason: String) -> void:
	for c in players.get_children():
		c.queue_free()


func _autotest_report() -> void:
	print("[TEST] PEERS %d" % (multiplayer.get_peers().size() if NetworkManager.is_in_session() else 0))
	for c in players.get_children():
		print("[TEST] POS %s %.2f %.2f" % [c.display_name, c.position.x, c.position.z])


# ---------------------------------------------------------------- menu

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_menu = PanelContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.custom_minimum_size = Vector2(360, 0)
	_menu.offset_left = -180
	_menu.offset_top = -170
	layer.add_child(_menu)
	var box := VBoxContainer.new()
	_menu.add_child(box)
	_label(box, "Rome Wasn't Built in a Lap — network sandbox")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.text = SteamManager.persona_name if SteamManager.available else NetworkManager.local_name
	box.add_child(_name_edit)
	_button(box, "Host (LAN)", func() -> void:
		_apply_name()
		NetworkManager.host_enet())
	var row := HBoxContainer.new()
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip_edit)
	_button(row, "Join IP", func() -> void:
		_apply_name()
		NetworkManager.join_enet(_ip_edit.text.strip_edges()))
	_button(box, "Steam Host", func() -> void:
		_apply_name()
		SteamManager.host_lobby())
	_button(box, "Steam Join (find lobbies)", func() -> void:
		_apply_name()
		SteamManager.request_lobby_list())
	_lobbies = VBoxContainer.new()
	box.add_child(_lobbies)
	_status = _label(box, "")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_in_game = HBoxContainer.new()
	_in_game.position = Vector2(12, 12)
	layer.add_child(_in_game)
	_label(_in_game, "WASD to move · F3 debug   ")
	_button(_in_game, "Invite (Steam)", SteamManager.invite_friends)
	_button(_in_game, "Leave", func() -> void: NetworkManager.leave())


func _apply_name() -> void:
	var n := _name_edit.text.strip_edges()
	if not n.is_empty():
		NetworkManager.local_name = n


func _on_lobby_list(lobbies: Array) -> void:
	for c in _lobbies.get_children():
		c.queue_free()
	for l: Dictionary in lobbies:
		var id: int = l["id"]
		_button(_lobbies, "%s (%d/%d)" % [l["name"], l["members"], NetworkManager.MAX_PLAYERS],
			func() -> void: SteamManager.join_lobby(id))


func _set_status(text: String) -> void:
	if _status:
		_status.text = text


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
