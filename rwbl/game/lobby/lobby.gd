class_name Lobby
extends Node
## LAN/Steam menu, five ready-up slots and GameMode lifecycle. Owner: C03.
## NET: every peer runs the UI; host owns membership, readiness, rules and match loading.
## Public API: start_match() -> bool; later hubs may request a start through the same ready gate.
## CLI: --auto-ready --lobby-autostart=N --discover --discovery-port=N --rounds=N --laps=N
##   --phase-time=SEC --no-fill-bots --quit-after=SEC, plus NetworkManager transport/name flags.
# CONTRACT: every peer instances the game as Main/Game/Match before the host calls GameMode.start().

const MATCH_SCENE := preload("res://game/match/match.tscn")
const RESULTS_SECONDS := 5.0

var _discovery: LanDiscovery
var _members: Array[Dictionary] = []
var _fill_bots := true
var _rounds := 6
var _match: GameMode
var _loading := false
var _generation := 0
var _loaded: Dictionary = {}
var _auto_ready_sent := false
var _autostart_used := false
var _results_showing := false
var _joining := false
var _session_epoch := 0

var _menu: VBoxContainer
var _room: VBoxContainer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _slots: VBoxContainer
var _lan_list: VBoxContainer
var _steam_list: VBoxContainer
var _fill_check: CheckBox
var _rounds_spin: SpinBox
var _ready_button: Button
var _start_button: Button
var _invite_button: Button
var _results: Label


func _ready() -> void:
	# WHY: ping loops see transport connectivity before lobby admission completes.
	NetworkManager.set_process(false)
	NetClock.set_process(false)
	multiplayer.auth_callback = _authenticate
	multiplayer.peer_authenticating.connect(_on_authenticating)
	multiplayer.peer_authentication_failed.connect(_on_auth_failed)
	_build_ui()
	_discovery = LanDiscovery.new()
	add_child(_discovery)
	_discovery.hosts_changed.connect(_on_hosts_changed)
	NetworkManager.player_registered.connect(_on_player_registered)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.hosting_started.connect(_on_hosting_started)
	NetworkManager.connected.connect(_on_connected)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.status_changed.connect(_set_status)
	SteamManager.status_changed.connect(_set_status)
	SteamManager.lobby_list_updated.connect(_on_steam_list)
	_rounds = clampi(int(NetworkManager.args.get("rounds", 6)), 1, 99)
	_fill_bots = not NetworkManager.args.has("no-fill-bots")
	_set_status("Steam: " + SteamManager.init_message)
	_listen()
	_render()
	_run_cli()


# WHY: pending peers are excluded from game RPC broadcasts until the lobby admits them.
# See https://docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html#class-scenemultiplayer-property-auth-callback
func _on_authenticating(id: int) -> void:
	multiplayer.send_auth(id, "rwbl-lobby-v1".to_utf8_buffer())


func _authenticate(id: int, data: PackedByteArray) -> void:
	var message := data.get_string_from_utf8()
	if multiplayer.is_server():
		if message != "rwbl-lobby-v1":
			return
		var reason := ""
		if _match != null or _loading:
			reason = "Match already in progress. Try again after the race."
		elif multiplayer.get_peers().size() >= NetworkManager.MAX_PLAYERS - 1:
			reason = "Lobby is full."
		if not reason.is_empty():
			print("[Lobby] REFUSED %d: %s" % [id, reason])
			multiplayer.send_auth(id, ("reject:" + reason).to_utf8_buffer())
			return
		multiplayer.send_auth(id, "accept".to_utf8_buffer())
		multiplayer.complete_auth(id)
	elif id == 1:
		if message == "accept":
			multiplayer.complete_auth(id)
		elif message.begins_with("reject:"):
			var reason := message.trim_prefix("reject:")
			print("[Lobby] REJECTED ", reason)
			NetworkManager.leave.call_deferred(reason)
	else:
		# WHY: peer relays are already admitted by the host.
		multiplayer.complete_auth(id)


func _on_auth_failed(id: int) -> void:
	if multiplayer.is_server():
		_render.call_deferred()
		_maybe_autostart.call_deferred()
	elif not multiplayer.is_server() and id == 1 and NetworkManager.mode != NetworkManager.Mode.OFFLINE:
		NetworkManager.leave.call_deferred("Lobby connection timed out or was refused.")


func _run_cli() -> void:
	var args := NetworkManager.args
	if args.has("host"):
		_host_lan()
	elif args.has("join"):
		_join_ip(String(args["join"]), _game_port())
	if args.has("quit-after"):
		get_tree().create_timer(maxf(0.1, float(args["quit-after"]))).timeout.connect(get_tree().quit)


func _game_port() -> int:
	return clampi(int(NetworkManager.args.get("port", NetworkManager.DEFAULT_PORT)), 1, 65535)


func _discovery_port() -> int:
	return clampi(int(NetworkManager.args.get("discovery-port", NetworkManager.DEFAULT_PORT + 1)), 1, 65535)


func _listen() -> void:
	_clear_list(_lan_list)
	var err := _discovery.listen(_discovery_port())
	if err != OK:
		_set_status("LAN discovery unavailable: " + error_string(err))


func _apply_name() -> void:
	var pname := _name_edit.text.strip_edges().left(20)
	NetworkManager.local_name = pname if not pname.is_empty() else "Player"


func _host_lan() -> void:
	if _joining or NetworkManager.is_in_session():
		return
	_apply_name()
	NetworkManager.host_enet(_game_port())


func _join_ip(ip: String, port: int) -> void:
	if _joining or NetworkManager.is_in_session():
		return
	_apply_name()
	_joining = true
	_discovery.stop()
	NetworkManager.join_enet(ip, port)
	_render()


func _host_steam() -> void:
	if _joining or NetworkManager.is_in_session():
		return
	_apply_name()
	_joining = true
	SteamManager.host_lobby()
	_render()


func _join_steam(id: int) -> void:
	if _joining or NetworkManager.is_in_session():
		return
	_apply_name()
	_joining = true
	_discovery.stop()
	SteamManager.join_lobby(id)
	_render()


func _on_hosting_started() -> void:
	_joining = false
	_members.clear()
	_discovery.stop()
	_render()


func _on_connected() -> void:
	NetworkManager.set_process(true)
	NetClock.set_process(true)
	_joining = false
	_discovery.stop()
	_render()


func _on_connection_failed(reason: String) -> void:
	_joining = false
	_set_status(reason)
	if not NetworkManager.is_in_session():
		_listen()
	_render()


func _on_player_registered(id: int, pname: String) -> void: # NET: host only
	if _match != null or _loading:
		_refuse_join.rpc_id(id, "Match already in progress. Try again after the race.")
		print("[Lobby] REFUSED %d: match in progress" % id)
		return
	if _member_index(id) >= 0:
		return
	var slot := _first_free_slot()
	if slot < 0:
		_refuse_join.rpc_id(id, "Lobby is full.")
		return
	var ready := id == 1 and (NetworkManager.args.has("auto-ready") or NetworkManager.args.has("lobby-autostart"))
	_members.append({"slot": slot, "peer_id": id, "name": pname, "ready": ready})
	print("[Lobby] JOIN %s slot=%d" % [pname, slot])
	_broadcast_lobby()
	_maybe_autostart()


func _on_peer_left(id: int) -> void:
	if not NetworkManager.is_in_session() or not multiplayer.is_server():
		return
	var index := _member_index(id)
	if index >= 0:
		_members.remove_at(index)
		print("[Lobby] LEFT slot freed peer=%d" % id)
		_broadcast_lobby()
		_try_begin_match()
		_maybe_autostart()


@rpc("authority", "call_remote", "reliable")
func _refuse_join(reason: String) -> void:
	NetworkManager.leave(reason)


func _member_index(id: int) -> int:
	for i in _members.size():
		if int(_members[i]["peer_id"]) == id:
			return i
	return -1


func _first_free_slot() -> int:
	for slot in NetworkManager.MAX_PLAYERS:
		var used := false
		for member in _members:
			if int(member["slot"]) == slot:
				used = true
		if not used:
			return slot
	return -1


func _broadcast_lobby() -> void: # NET: host only
	# WHY: send only to admitted humans, so a late join never receives scene RPCs.
	for member in _members:
		var id := int(member["peer_id"])
		if id != 1:
			_sync_lobby.rpc_id(id, _members, _fill_bots, _rounds)
	_render()
	_update_advertisement()


@rpc("authority", "call_remote", "reliable")
func _sync_lobby(members: Array, fill_bots: bool, rounds: int) -> void:
	_members.assign(members)
	_fill_bots = fill_bots
	_rounds = rounds
	_render()
	if NetworkManager.args.has("auto-ready") and not _auto_ready_sent and _member_index(multiplayer.get_unique_id()) >= 0:
		_auto_ready_sent = true
		_set_ready.rpc_id(1, true)


@rpc("any_peer", "call_remote", "reliable")
func _set_ready(value: bool) -> void: # NET: host validates sender; clients only set their own readiness
	if not multiplayer.is_server() or _match != null or _loading:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var index := _member_index(id)
	if index < 0:
		return
	_members[index]["ready"] = value
	print("[Lobby] READY %s %s" % [_members[index]["name"], value])
	_broadcast_lobby()
	_maybe_autostart()


func _toggle_ready() -> void:
	var index := _member_index(multiplayer.get_unique_id())
	if index < 0:
		return
	var value := not bool(_members[index]["ready"])
	if multiplayer.is_server():
		_set_ready(value)
	else:
		_set_ready.rpc_id(1, value)


func _all_ready() -> bool:
	if _members.is_empty():
		return false
	if multiplayer.is_server() and (_members.size() != multiplayer.get_peers().size() + 1 or not multiplayer.get_authenticating_peers().is_empty()):
		return false
	for member in _members:
		if not bool(member["ready"]):
			return false
	return true


func _maybe_autostart() -> void:
	if _autostart_used or not NetworkManager.args.has("lobby-autostart"):
		return
	var count := clampi(int(NetworkManager.args["lobby-autostart"]), 1, NetworkManager.MAX_PLAYERS)
	if _members.size() >= count and _all_ready():
		_autostart_used = start_match()


## Start with current slots/rules if every human is ready. Returns false when the host gate fails.
## NET: host only. setup() runs on every peer; acknowledgment barrier precedes host-only start().
func start_match() -> bool:
	if not NetworkManager.is_in_session() or not multiplayer.is_server() or _match != null or _loading or not _all_ready():
		return false
	var players: Array = []
	for slot in NetworkManager.MAX_PLAYERS:
		var found := false
		for member in _members:
			if int(member["slot"]) == slot:
				players.append(PlayerInfo.create(slot, int(member["peer_id"]), String(member["name"])).to_dict())
				found = true
				break
		if not found and _fill_bots:
			players.append(PlayerInfo.create(slot, 1, "Bot %d" % (slot + 1), true).to_dict())
	var rules := {"rounds": _rounds}
	var args := NetworkManager.args
	if args.has("laps"):
		rules["laps"] = maxi(1, int(args["laps"]))
	if args.has("phase-time"):
		for key in ["draft_time", "build_time", "race_time", "score_time"]:
			rules[key] = maxf(0.1, float(args["phase-time"]))
	_generation += 1
	_loading = true
	_loaded.clear()
	_discovery.stop()
	print("[Lobby] START humans=%d players=%d" % [_members.size(), players.size()])
	for member in _members:
		if int(member["peer_id"]) != 1:
			_load_match.rpc_id(int(member["peer_id"]), players, rules, _generation)
	_load_match(players, rules, _generation)
	return true


@rpc("authority", "call_remote", "reliable")
func _load_match(dicts: Array, rules: Dictionary, generation: int) -> void:
	_generation = generation
	_loading = true
	var players: Array[PlayerInfo] = []
	for d: Dictionary in dicts:
		players.append(PlayerInfo.from_dict(d))
	_match = MATCH_SCENE.instantiate() as GameMode
	_match.name = "Match"
	$Game.add_child(_match)
	_match.finished.connect(_on_finished)
	_match.process_mode = Node.PROCESS_MODE_DISABLED
	_match.setup(players, rules)
	_results_showing = false
	_render()
	if multiplayer.is_server():
		_loaded[1] = true
		_try_begin_match.call_deferred()
	else:
		_match_loaded.rpc_id(1, generation)


@rpc("any_peer", "call_remote", "reliable")
func _match_loaded(generation: int) -> void:
	if not multiplayer.is_server() or not _loading or generation != _generation:
		return
	var id := multiplayer.get_remote_sender_id()
	if _member_index(id) >= 0:
		_loaded[id] = true
		_try_begin_match()


func _try_begin_match() -> void:
	if not _loading or _match == null:
		return
	for member in _members:
		if not _loaded.has(int(member["peer_id"])):
			return
	for member in _members:
		if int(member["peer_id"]) != 1:
			_activate_match.rpc_id(int(member["peer_id"]), _generation)
	_activate_match(_generation)
	_match.start()


@rpc("authority", "call_remote", "reliable")
func _activate_match(generation: int) -> void:
	if generation == _generation and _match != null:
		_loading = false
		_match.process_mode = Node.PROCESS_MODE_INHERIT


func _on_finished(results: Array) -> void:
	# WHY: drain in-flight snapshots/inputs during results before removing RPC nodes.
	_match.process_mode = Node.PROCESS_MODE_DISABLED
	_results_showing = true
	var lines := PackedStringArray(["Results"])
	for result: PlayerResult in results:
		lines.append("%d. %s — %d" % [result.place, result.name, result.score])
	_results.text = "\n".join(lines)
	_render()
	if multiplayer.is_server():
		var generation := _generation
		var epoch := _session_epoch
		get_tree().create_timer(RESULTS_SECONDS).timeout.connect(func() -> void:
			if NetworkManager.is_in_session() and multiplayer.is_server() and _match != null and generation == _generation and epoch == _session_epoch:
				for member in _members:
					if int(member["peer_id"]) != 1:
						_return_to_lobby.rpc_id(int(member["peer_id"]), generation)
				_return_to_lobby(generation)
				_broadcast_lobby())


@rpc("authority", "call_remote", "reliable")
func _return_to_lobby(generation: int) -> void:
	if generation != _generation:
		return
	_free_match()
	for member in _members:
		member["ready"] = false
	print("[Lobby] RETURNED")
	_set_status("Match finished. Ready up for another race.")
	_render()


func _free_match() -> void:
	_loading = false
	_loaded.clear()
	_results_showing = false
	if is_instance_valid(_match):
		$Game.remove_child(_match)
		_match.queue_free()
	_match = null


func _on_session_ended(reason: String) -> void:
	NetworkManager.set_process(false)
	NetClock.set_process(false)
	_session_epoch += 1
	_free_match()
	_members.clear()
	_joining = false
	_auto_ready_sent = false
	_autostart_used = false
	_listen()
	_set_status(reason)
	_render()


func _update_advertisement() -> void:
	if NetworkManager.mode == NetworkManager.Mode.ENET and multiplayer.is_server() and _match == null:
		_discovery.advertise(_discovery_port(), NetworkManager.local_name + "'s game", _game_port(), _members.size())


func _on_hosts_changed(hosts: Array[Dictionary]) -> void:
	_clear_list(_lan_list)
	for host in hosts:
		var ip := String(host["ip"])
		var port := int(host["port"])
		_button(_lan_list, "%s (%d/5) — %s:%d" % [host["name"], host["players"], ip, port],
			func() -> void: _join_ip(ip, port))
	if not hosts.is_empty() and NetworkManager.args.has("discover") and not _joining and not NetworkManager.is_in_session():
		print("[Lobby] Found host %s:%d" % [hosts[0]["ip"], hosts[0]["port"]])
		_join_ip(String(hosts[0]["ip"]), int(hosts[0]["port"]))


func _on_steam_list(lobbies: Array) -> void:
	_clear_list(_steam_list)
	for lobby: Dictionary in lobbies:
		var id := int(lobby["id"])
		_button(_steam_list, "%s (%d/5)" % [lobby["name"], lobby["members"]], func() -> void: _join_steam(id))


func _options_changed(_value: Variant = null) -> void:
	if not NetworkManager.is_in_session() or not multiplayer.is_server() or _match != null:
		return
	_fill_bots = _fill_check.button_pressed
	_rounds = int(_rounds_spin.value)
	# WHY: humans must consent again when the host changes the advertised rules.
	for member in _members:
		member["ready"] = false
	_broadcast_lobby()


func _render() -> void:
	var in_session := NetworkManager.is_in_session()
	var host := in_session and multiplayer.is_server()
	_menu.visible = not in_session
	_room.visible = in_session and (_match == null or _results_showing)
	_name_edit.editable = not _joining
	_results.visible = _results_showing
	_slots.visible = not _results_showing
	_clear_list(_slots)
	for slot in NetworkManager.MAX_PLAYERS:
		var text := "%d. %s" % [slot + 1, "Bot" if _fill_bots else "Empty"]
		for member in _members:
			if int(member["slot"]) == slot:
				text = "%d. %s  %s" % [slot + 1, member["name"], "✓ Ready" if member["ready"] else "Waiting"]
		var label := _label(_slots, text)
		label.modulate = PlayerInfo.color_for_slot(slot)
	_fill_check.set_pressed_no_signal(_fill_bots)
	_fill_check.disabled = not host or _match != null
	_rounds_spin.set_value_no_signal(_rounds)
	_rounds_spin.editable = host and _match == null
	_start_button.visible = host
	_start_button.disabled = not host or not _all_ready() or _match != null or _loading
	_ready_button.disabled = _match != null or _loading
	var index := _member_index(multiplayer.get_unique_id()) if in_session else -1
	_ready_button.text = "Unready" if index >= 0 and bool(_members[index]["ready"]) else "Ready"
	_invite_button.disabled = NetworkManager.mode != NetworkManager.Mode.STEAM


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(600, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_label(box, "Rome Wasn't Built in a Lap")
	_menu = VBoxContainer.new()
	box.add_child(_menu)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.text = SteamManager.persona_name if SteamManager.available and not NetworkManager.args.has("name") else NetworkManager.local_name
	_menu.add_child(_name_edit)
	_button(_menu, "Host (LAN)", _host_lan)
	var row := HBoxContainer.new()
	_menu.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip_edit)
	_button(row, "Join IP", func() -> void: _join_ip(_ip_edit.text.strip_edges(), _game_port()))
	_label(_menu, "LAN games (found automatically)")
	_lan_list = _scroll_list(_menu)
	var steam_host := _button(_menu, "Steam Host", _host_steam)
	steam_host.disabled = not SteamManager.available
	var steam_join := _button(_menu, "Steam Join (find lobbies)", SteamManager.request_lobby_list)
	steam_join.disabled = not SteamManager.available
	_steam_list = _scroll_list(_menu)
	_room = VBoxContainer.new()
	box.add_child(_room)
	_slots = VBoxContainer.new()
	_room.add_child(_slots)
	_fill_check = CheckBox.new()
	_fill_check.text = "Fill empty slots with bots"
	_fill_check.toggled.connect(_options_changed)
	_room.add_child(_fill_check)
	var options := HBoxContainer.new()
	_room.add_child(options)
	_label(options, "Rounds: ")
	_rounds_spin = SpinBox.new()
	_rounds_spin.min_value = 1
	_rounds_spin.max_value = 99
	_rounds_spin.value_changed.connect(_options_changed)
	options.add_child(_rounds_spin)
	_ready_button = _button(_room, "Ready", _toggle_ready)
	_start_button = _button(_room, "Start", func() -> void: start_match())
	_invite_button = _button(_room, "Invite (Steam)", SteamManager.invite_friends)
	_results = _label(_room, "")
	_button(_room, "Leave", func() -> void: NetworkManager.leave())
	_status = _label(box, "")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(box, "Quit", get_tree().quit)


func _scroll_list(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 70)
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


func _clear_list(list: Control) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _set_status(text: String) -> void:
	_status.text = text
