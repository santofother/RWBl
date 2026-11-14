class_name ChariotSync
extends Node
## Host-authoritative chariot replication: inputs up, snapshots down (DESIGN §8, AGENTS §Conventions).
## Owner: C07. C02 STUB: working but naive. Every peer sends its local ChariotInput to the host each physics
## tick; the host steps every chariot and broadcasts one snapshot packet at SNAPSHOT_HZ; clients apply the
## latest snapshot directly. C07 adds the interpolation buffer, light own-chariot prediction and `--lag-ms`.
## Works with anything "drivable": a node with step(input, delta), get_snapshot(), apply_snapshot(s)
## (Chariot, and the C01 sandbox cube).
## NET: runs on every peer at the same node path. Host: simulation authority. Clients: input + render.
## Public API: match_setup(m), add_chariot(slot, node, owner_peer, is_bot), remove_chariot(slot),
##   get_chariot(slot), get_chariots(), submit_input(slot, input), local_slot, local_input_source,
##   signals chariot_added / chariot_removed.
# CONTRACT: players and bots both reach Chariot.step() only through submit_input() on the host.
# CONTRACT: chariot nodes are named "Chariot<slot>" under MatchMode/Chariots.

## A chariot node was registered (every peer).
signal chariot_added(slot: int, node: Node3D)
## A chariot node was unregistered (every peer).
signal chariot_removed(slot: int)

const CHARIOT_SCENE := preload("res://game/chariot/chariot.tscn")
const SNAPSHOT_HZ := 30.0 # TUNE

## Slot driven by this machine's keyboard/gamepad (-1 = spectator / headless).
var local_slot := -1
## Callable(slot) -> ChariotInput for the local slot. Defaults to PlayerInput.read; tests may replace it.
var local_input_source: Callable

var _chariots: Dictionary = {} # slot -> Node3D
var _owners: Dictionary = {} # slot -> peer id that may send input for it
var _inputs: Dictionary = {} # host: slot -> latest ChariotInput
var _last_counts: Dictionary = {} # host: slot -> Vector2i(whip_count, action_count) already consumed
var _snap_accum := 0.0
var _player_input := PlayerInput.new()
var _m: MatchMode


func _ready() -> void:
	if not local_input_source.is_valid():
		local_input_source = _player_input.read


## Called by MatchMode.setup() on every peer: spawn one chariot per player on the grid.
func match_setup(m: MatchMode) -> void:
	_m = m
	for p in m.players:
		var c := CHARIOT_SCENE.instantiate() as Chariot
		c.name = "Chariot%d" % p.slot
		c.slot = p.slot
		c.track = m.track
		m.chariots_root.add_child(c)
		c.global_transform = m.track.start_transform(p.slot)
		(c.get_node(^"Label") as Label3D).text = p.name
		var mesh := c.get_node(^"Horses") as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p.color
		mesh.material_override = mat
		add_chariot(p.slot, c, p.peer_id, p.is_bot)


## Register a drivable node for `slot`. `owner_peer` may send its input. Every peer calls this.
func add_chariot(slot: int, node: Node3D, owner_peer: int, is_bot: bool = false) -> void:
	_chariots[slot] = node
	_owners[slot] = owner_peer
	if not is_bot and owner_peer == multiplayer.get_unique_id():
		local_slot = slot
	chariot_added.emit(slot, node)


## Unregister a slot (player left). Does not free the node.
func remove_chariot(slot: int) -> void:
	_chariots.erase(slot)
	_owners.erase(slot)
	_inputs.erase(slot)
	_last_counts.erase(slot)
	if local_slot == slot:
		local_slot = -1
	chariot_removed.emit(slot)


## The node driven by `slot`, or null.
func get_chariot(slot: int) -> Node3D:
	return _chariots.get(slot)


## slot -> node for every registered chariot.
func get_chariots() -> Dictionary:
	return _chariots


## Give the host the newest input for `slot` (bots call this directly). NET: host only.
func submit_input(slot: int, input: ChariotInput) -> void:
	if not multiplayer.is_server():
		return
	_inputs[slot] = input.copy()


func _physics_process(delta: float) -> void:
	if _chariots.is_empty():
		return
	var is_host := multiplayer.is_server()
	if local_slot >= 0 and _chariots.has(local_slot):
		var inp: ChariotInput = local_input_source.call(local_slot)
		if is_host:
			submit_input(local_slot, inp)
		elif _connected():
			_rpc_input.rpc_id(1, local_slot, inp.to_bytes())
	if not is_host:
		return
	for slot: int in _chariots:
		var node = _chariots[slot] # WHY: untyped, "drivable" is duck-typed (Chariot or sandbox cube)
		if is_instance_valid(node):
			node.step(_consume_input(slot), delta)
	_snap_accum += delta
	if _snap_accum >= 1.0 / SNAPSHOT_HZ and _connected() and not multiplayer.get_peers().is_empty():
		_snap_accum = 0.0
		var packet := PackedFloat32Array()
		for slot: int in _chariots:
			var node = _chariots[slot]
			if is_instance_valid(node):
				packet.append(slot)
				packet.append_array(node.get_snapshot())
		_rpc_snapshots.rpc(NetClock.now(), packet)


## Turn press counters into one-tick whip/action bools. NET: host.
func _consume_input(slot: int) -> ChariotInput:
	var inp: ChariotInput = _inputs.get(slot, null)
	if inp == null:
		return ChariotInput.new()
	var out := inp.copy()
	var last: Vector2i = _last_counts.get(slot, Vector2i(inp.whip_count, inp.action_count))
	out.whip = inp.whip_count != last.x
	out.action = inp.action_count != last.y
	_last_counts[slot] = Vector2i(inp.whip_count, inp.action_count)
	return out


func _connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_input(slot: int, data: PackedByteArray) -> void: # NET: host
	if not multiplayer.is_server():
		return
	if _owners.get(slot, -1) != multiplayer.get_remote_sender_id():
		return # CONTRACT: a peer may only drive its own slot
	var inp := ChariotInput.from_bytes(data)
	var prev: ChariotInput = _inputs.get(slot, null)
	if prev != null and inp.seq < prev.seq:
		return # late packet
	_inputs[slot] = inp


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshots(_server_time: float, packet: PackedFloat32Array) -> void: # NET: clients
	var stride := 1 + ChariotSnapshot.SIZE
	var i := 0
	while i + stride <= packet.size():
		var node = _chariots.get(int(packet[i]))
		if is_instance_valid(node):
			node.apply_snapshot(packet.slice(i + 1, i + stride))
		i += stride
