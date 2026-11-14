class_name ChariotSync
extends Node
## Host-authoritative chariot replication (DESIGN §8, milestone N4). Owner: C07.
## Inputs up: every peer sends its local ChariotInput each physics tick (unreliable, the last
##   INPUT_REDUNDANCY inputs per packet so one lost packet costs nothing). The host queues them per slot,
##   ignores old `seq`, and feeds one per tick through submit_input().
## Snapshots down: the host steps every chariot and broadcasts one packet at SNAPSHOT_HZ (format below).
## Remote chariots (clients): a buffer keyed by host time (NetClock), rendered `interp_delay` behind the
##   host clock: position lerp, rotation slerp, cart angle lerp; extrapolated up to MAX_EXTRAPOLATE on gaps.
##   `interp_delay` is at least INTERP_DELAY and grows with the measured snapshot age (latency + jitter).
## Own chariot (clients): light prediction. The client runs step() locally with its own inputs and keeps the
##   predicted state per input seq. Each snapshot carries the last seq the host consumed for that slot; the
##   client compares host state vs its prediction at that seq and removes CORRECTION_RATE of the error per
##   snapshot (from the live state and the newer history), snapping if the error is > SNAP_DISTANCE.
##   Remote chariots are never predicted. `--no-predict` renders the own chariot like a remote one.
## Lag sim: `--lag-ms=N` delays and `--loss=PCT` drops this peer's input and snapshot sends.
## Stats: rtt_ms (input -> ack), interp_delay, kB/s in/out; label toggled with F3 next to DebugOverlay.
## Works with anything "drivable": step(input, delta), get_snapshot(), apply_snapshot(s) (Chariot, sandbox cube).
## Packet (snapshot, PackedByteArray): f64 host_time, then per chariot: u8 slot, u32 ack_seq, 15 × f32
##   ChariotSnapshot = 65 bytes. Input packet: up to 3 × 10-byte ChariotInput, newest first.
## NET: runs on every peer at the same node path. Host: simulation authority. Clients: input + render.
## Public API: match_setup(m), add_chariot(slot, node, owner_peer, is_bot), remove_chariot(slot),
##   get_chariot(slot), get_chariots(), submit_input(slot, input), sample_remote(slot, host_time),
##   render_time(), local_slot, local_input_source, prediction, lag_ms, loss_pct, rtt_ms, interp_delay,
##   kbps_in, kbps_out, signals chariot_added / chariot_removed.
# CONTRACT: players and bots both reach Chariot.step() only through submit_input() on the host.
# CONTRACT: chariot nodes are named "Chariot<slot>" under MatchMode/Chariots.

## A chariot node was registered (every peer).
signal chariot_added(slot: int, node: Node3D)
## A chariot node was unregistered (every peer).
signal chariot_removed(slot: int)

const CHARIOT_SCENE := preload("res://game/chariot/chariot.tscn")
const SNAPSHOT_HZ := 30.0 # TUNE
const INTERP_DELAY := 0.1 # TUNE: minimum render delay behind the host clock, s
const MAX_INTERP_DELAY := 0.5 # TUNE
const MAX_EXTRAPOLATE := 0.15 # TUNE: s past the newest snapshot before remote chariots stop
const BUFFER_SECONDS := 1.0
const TELEPORT_DISTANCE := 5.0 # WHY: two snapshots this far apart = respawn, don't draw a streak
const SNAP_DISTANCE := 3.0 # TUNE: prediction error above this snaps instead of blending, m
const CORRECTION_RATE := 0.35 # TUNE: share of the prediction error removed per snapshot
const INPUT_REDUNDANCY := 3
const MAX_INPUT_QUEUE := 4 # host: older queued inputs are dropped beyond this (catch up after a burst)
const HISTORY_TICKS := 240
const ENTRY_BYTES := 65
const KIND_INPUT := 0
const KIND_SNAP := 1

## Slot driven by this machine's keyboard/gamepad (-1 = spectator / headless).
var local_slot := -1
## Callable(slot) -> ChariotInput for the local slot. Defaults to PlayerInput.read; tests may replace it.
var local_input_source: Callable
## Clients: predict the own chariot (false = render it interpolated like the others). CLI `--no-predict`.
var prediction := true
## Simulated one-way delay on this peer's input/snapshot sends, ms. CLI `--lag-ms=N`.
var lag_ms := 0
## Simulated drop chance on this peer's input/snapshot sends, percent. CLI `--loss=PCT`.
var loss_pct := 0.0
## Clients: smoothed round trip input -> host ack, ms.
var rtt_ms := 0.0
## Clients: current render delay behind the host clock, s.
var interp_delay := INTERP_DELAY
## Payload kB/s received / sent over the last second.
var kbps_in := 0.0
## See kbps_in.
var kbps_out := 0.0

var _chariots: Dictionary = {} # slot -> Node3D
var _owners: Dictionary = {} # slot -> peer id that may send input for it
var _inputs: Dictionary = {} # host: slot -> latest ChariotInput
var _last_counts: Dictionary = {} # host: slot -> Vector3i(whip_count, action_count, jump_count) already consumed
var _queues: Dictionary = {} # host: slot -> Array[ChariotInput] received, not yet stepped
var _queue_min: Dictionary = {} # host: slot -> smallest queue length this second
var _last_recv: Dictionary = {} # host: slot -> newest seq received
var _acks: Dictionary = {} # host: slot -> seq of the input last stepped
var _snap_accum := 0.0
var _player_input := PlayerInput.new()
var _m: MatchMode
# client
var _next_seq := 0
var _recent: Array[PackedByteArray] = [] # last sent inputs, newest first
var _sent_ms: Dictionary = {} # seq -> local msec when sent
var _history: Dictionary = {} # seq -> predicted snapshot after stepping that input
var _pred_counts := Vector3i(-1, -1, -1)
var _last_ack := 0
var _buffers: Dictionary = {} # slot -> Array of [host_time, PackedFloat32Array], oldest first
var _age_avg := 0.0
var _age_jitter := 0.0
var _age_init := false
# lag sim + stats
var _lag_queue: Array = [] # [release_msec, kind, slot, data]
var _rng := RandomNumberGenerator.new()
var _bytes_in := 0
var _bytes_out := 0
var _stats_t := 0.0
var _label: Label


func _ready() -> void:
	if not local_input_source.is_valid():
		local_input_source = _player_input.read
	var a := NetworkManager.args
	lag_ms = maxi(0, int(a.get("lag-ms", 0)))
	loss_pct = clampf(float(a.get("loss", 0.0)), 0.0, 100.0)
	prediction = not a.has("no-predict")
	_rng.randomize()
	if lag_ms > 0 or loss_pct > 0.0:
		print("[Net] Lag sim: %d ms one-way, %.0f%% loss" % [lag_ms, loss_pct])
	if DisplayServer.get_name() != "headless":
		_build_label()


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
	GameEvents.roster_changed.connect(_on_roster_changed)
	if NetworkManager.args.has("net-autotest"):
		var d: Node = load("res://game/net/tests/net_test_driver.gd").new()
		d.name = "NetTestDriver"
		add_child(d)
		d.setup(self, m)


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
	_forget_inputs(slot)
	_buffers.erase(slot)
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


## Host time remote chariots are drawn at on this client (NetClock.now() - interp_delay).
func render_time() -> float:
	return NetClock.now() - interp_delay


## Interpolated host snapshot of `slot` at `host_time` from this client's buffer (empty if none).
## NET: clients (the host has no buffer).
func sample_remote(slot: int, host_time: float) -> PackedFloat32Array:
	var buf: Array = _buffers.get(slot, [])
	if buf.is_empty():
		return PackedFloat32Array()
	if host_time <= buf[0][0]:
		return buf[0][1]
	var i := buf.size() - 1
	while i > 0 and buf[i][0] > host_time:
		i -= 1
	var a: Array = buf[i]
	if i == buf.size() - 1:
		var out: PackedFloat32Array = (a[1] as PackedFloat32Array).duplicate()
		var dt := minf(host_time - float(a[0]), MAX_EXTRAPOLATE)
		var p := ChariotSnapshot.pos(out) + ChariotSnapshot.vel(out) * dt
		out[ChariotSnapshot.POS] = p.x
		out[ChariotSnapshot.POS + 1] = p.y
		out[ChariotSnapshot.POS + 2] = p.z
		return out
	var b: Array = buf[i + 1]
	var f := clampf((host_time - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), 0.0, 1.0)
	return _lerp_snapshot(a[1], b[1], f)


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	_flush_lag()
	if _chariots.is_empty():
		return
	var is_host := multiplayer.is_server()
	if local_slot >= 0 and _chariots.has(local_slot):
		var inp := (local_input_source.call(local_slot) as ChariotInput).copy()
		_next_seq += 1
		inp.seq = _next_seq # WHY: ChariotSync is the sender; test sources don't number their inputs
		if is_host:
			submit_input(local_slot, inp)
		elif _connected():
			_send_input(inp)
			if prediction:
				_predict(inp, delta)
	if is_host:
		_host_tick(delta)


func _process(delta: float) -> void:
	_flush_lag()
	_stats_t += delta
	if _stats_t >= 1.0:
		kbps_in = _bytes_in / 1024.0 / _stats_t
		kbps_out = _bytes_out / 1024.0 / _stats_t
		_bytes_in = 0
		_bytes_out = 0
		_stats_t = 0.0
		_update_label()
		for slot: int in _queue_min:
			var q: Array = _queues.get(slot, [])
			if int(_queue_min[slot]) >= 2 and not q.is_empty():
				q.pop_front() # WHY: a queue that never drains adds latency; drop one input per second
			_queue_min[slot] = 1 << 20
	if multiplayer.is_server() or _buffers.is_empty():
		return
	var synced := NetClock.is_synced()
	var rt := render_time()
	for slot: int in _buffers:
		if slot == local_slot and prediction:
			continue
		var node = _chariots.get(slot)
		if not is_instance_valid(node):
			continue
		var buf: Array = _buffers[slot]
		if buf.is_empty():
			continue
		node.apply_snapshot(sample_remote(slot, rt) if synced else buf[-1][1])


## NET: host. Feed queued client inputs, step every chariot, broadcast snapshots.
func _host_tick(delta: float) -> void:
	for slot: int in _queues:
		var q: Array = _queues[slot]
		while q.size() > MAX_INPUT_QUEUE:
			q.pop_front()
		_queue_min[slot] = mini(int(_queue_min.get(slot, 1 << 20)), q.size())
		if not q.is_empty():
			var inp: ChariotInput = q.pop_front()
			_acks[slot] = inp.seq
			submit_input(slot, inp)
	for slot: int in _chariots:
		var node = _chariots[slot] # WHY: untyped, "drivable" is duck-typed (Chariot or sandbox cube)
		if is_instance_valid(node):
			node.step(_consume_input(slot), delta)
	_snap_accum += delta
	if _snap_accum < 1.0 / SNAPSHOT_HZ:
		return
	_snap_accum = minf(_snap_accum - 1.0 / SNAPSHOT_HZ, 1.0 / SNAPSHOT_HZ)
	if not _connected() or multiplayer.get_peers().is_empty():
		return
	var buf := PackedByteArray()
	buf.resize(8 + _chariots.size() * ENTRY_BYTES)
	buf.encode_double(0, NetClock.now())
	var off := 8
	for slot: int in _chariots:
		var node = _chariots[slot]
		if not is_instance_valid(node):
			continue
		var s: PackedFloat32Array = node.get_snapshot()
		buf.encode_u8(off, slot)
		buf.encode_u32(off + 1, int(_acks.get(slot, 0)))
		for k in ChariotSnapshot.SIZE:
			buf.encode_float(off + 5 + k * 4, s[k])
		off += ENTRY_BYTES
	buf.resize(off)
	_lag_send(KIND_SNAP, -1, buf)


## Turn press counters into one-tick whip/action bools. NET: host.
func _consume_input(slot: int) -> ChariotInput:
	var inp: ChariotInput = _inputs.get(slot, null)
	if inp == null:
		return ChariotInput.new()
	var out := inp.copy()
	# FIX(C04, Claude): jump counter added to ChariotInput (user-approved jump move).
	var last: Vector3i = _last_counts.get(slot, Vector3i(inp.whip_count, inp.action_count, inp.jump_count))
	out.whip = inp.whip_count != last.x
	out.action = inp.action_count != last.y
	out.jump = inp.jump_count != last.z
	_last_counts[slot] = Vector3i(inp.whip_count, inp.action_count, inp.jump_count)
	return out


func _forget_inputs(slot: int) -> void:
	_inputs.erase(slot)
	_last_counts.erase(slot)
	_queues.erase(slot)
	_queue_min.erase(slot)
	_last_recv.erase(slot)
	_acks.erase(slot)


## A dropped player became a bot (C09): the host stops expecting that peer's inputs. NET: every peer.
func _on_roster_changed() -> void:
	if _m == null:
		return
	for p in _m.players:
		if not _chariots.has(p.slot):
			continue
		var owner_peer := 1 if p.is_bot else p.peer_id
		if int(_owners.get(p.slot, -1)) != owner_peer or p.is_bot:
			_forget_inputs(p.slot)
		_owners[p.slot] = owner_peer
		if p.slot == local_slot and (p.is_bot or p.peer_id != multiplayer.get_unique_id()):
			local_slot = -1


# ---------------------------------------------------------------- client: input + prediction

## NET: client. Send this input plus the previous ones (redundancy against loss).
func _send_input(inp: ChariotInput) -> void:
	_recent.push_front(inp.to_bytes())
	if _recent.size() > INPUT_REDUNDANCY:
		_recent.resize(INPUT_REDUNDANCY)
	var data := PackedByteArray()
	for b in _recent:
		data.append_array(b)
	_sent_ms[inp.seq] = Time.get_ticks_msec()
	_lag_send(KIND_INPUT, local_slot, data)


## NET: owner client. Step the own chariot locally and remember the predicted state for this seq.
func _predict(inp: ChariotInput, delta: float) -> void:
	var node = _chariots[local_slot]
	if not is_instance_valid(node):
		return
	var p := inp.copy()
	var counts := Vector3i(inp.whip_count, inp.action_count, inp.jump_count)
	if _pred_counts.x >= 0:
		p.whip = counts.x != _pred_counts.x
		p.action = counts.y != _pred_counts.y
		p.jump = counts.z != _pred_counts.z
	_pred_counts = counts
	node.step(p, delta)
	_history[inp.seq] = node.get_snapshot()
	_history.erase(inp.seq - HISTORY_TICKS)


## NET: owner client. Move the predicted chariot toward the host state at `ack`.
func _reconcile(ack: int, host: PackedFloat32Array) -> void:
	var node = _chariots.get(local_slot)
	if not is_instance_valid(node):
		return
	if ack > _last_ack:
		_last_ack = ack
		if _sent_ms.has(ack):
			var r := float(Time.get_ticks_msec() - int(_sent_ms[ack]))
			rtt_ms = r if rtt_ms <= 0.0 else lerpf(rtt_ms, r, 0.1)
		for s: int in _sent_ms.keys():
			if s <= ack:
				_sent_ms.erase(s)
	elif ack < _last_ack:
		return # older than a snapshot already used
	var cur: PackedFloat32Array = node.get_snapshot()
	var hist: PackedFloat32Array = _history.get(ack, PackedFloat32Array())
	var k := CORRECTION_RATE
	if hist.is_empty():
		# Nothing predicted for that seq (match start, or the host hasn't stepped our input yet).
		if ChariotSnapshot.pos(host).distance_to(ChariotSnapshot.pos(cur)) <= SNAP_DISTANCE:
			_take_flags(cur, host)
			node.apply_snapshot(cur)
			return
		hist = cur
		k = 1.0
	var err_p := ChariotSnapshot.pos(host) - ChariotSnapshot.pos(hist)
	if err_p.length() > SNAP_DISTANCE:
		k = 1.0
	var err := _snapshot_error(hist, host)
	for s: int in _history.keys():
		if s <= ack:
			_history.erase(s)
		else:
			_history[s] = _corrected(_history[s], err, k)
	var out := _corrected(cur, err, k)
	_take_flags(out, host)
	node.apply_snapshot(out)


## Error terms host - predicted: [pos, rot quat, vel, cart_angle, cart_ang_vel, stamina].
static func _snapshot_error(pred: PackedFloat32Array, host: PackedFloat32Array) -> Array:
	return [ChariotSnapshot.pos(host) - ChariotSnapshot.pos(pred),
		ChariotSnapshot.rot(host) * ChariotSnapshot.rot(pred).inverse(),
		ChariotSnapshot.vel(host) - ChariotSnapshot.vel(pred),
		wrapf(host[ChariotSnapshot.CART_ANGLE] - pred[ChariotSnapshot.CART_ANGLE], -PI, PI),
		host[ChariotSnapshot.CART_ANG_VEL] - pred[ChariotSnapshot.CART_ANG_VEL],
		host[ChariotSnapshot.STAMINA] - pred[ChariotSnapshot.STAMINA]]


## `s` with share `k` of `err` removed.
static func _corrected(s: PackedFloat32Array, err: Array, k: float) -> PackedFloat32Array:
	var out := s.duplicate()
	var p := ChariotSnapshot.pos(s) + (err[0] as Vector3) * k
	var q := (Quaternion.IDENTITY.slerp(err[1] as Quaternion, k) * ChariotSnapshot.rot(s)).normalized()
	var v := ChariotSnapshot.vel(s) + (err[2] as Vector3) * k
	out[ChariotSnapshot.POS] = p.x
	out[ChariotSnapshot.POS + 1] = p.y
	out[ChariotSnapshot.POS + 2] = p.z
	out[ChariotSnapshot.ROT] = q.x
	out[ChariotSnapshot.ROT + 1] = q.y
	out[ChariotSnapshot.ROT + 2] = q.z
	out[ChariotSnapshot.ROT + 3] = q.w
	out[ChariotSnapshot.VEL] = v.x
	out[ChariotSnapshot.VEL + 1] = v.y
	out[ChariotSnapshot.VEL + 2] = v.z
	out[ChariotSnapshot.CART_ANGLE] += float(err[3]) * k
	out[ChariotSnapshot.CART_ANG_VEL] += float(err[4]) * k
	out[ChariotSnapshot.STAMINA] = clampf(out[ChariotSnapshot.STAMINA] + float(err[5]) * k, 0.0, 1.0)
	return out


## Wheels and flags (dead, frozen, stunned...) are the host's decision, never predicted.
static func _take_flags(out: PackedFloat32Array, host: PackedFloat32Array) -> void:
	out[ChariotSnapshot.WHEELS] = host[ChariotSnapshot.WHEELS]
	out[ChariotSnapshot.FLAGS] = host[ChariotSnapshot.FLAGS]


static func _lerp_snapshot(a: PackedFloat32Array, b: PackedFloat32Array, f: float) -> PackedFloat32Array:
	if ChariotSnapshot.pos(a).distance_to(ChariotSnapshot.pos(b)) > TELEPORT_DISTANCE:
		return b if f > 0.0 else a
	var out := (a if f < 0.5 else b).duplicate() # discrete fields (wheels, flags) from the nearer one
	var p := ChariotSnapshot.pos(a).lerp(ChariotSnapshot.pos(b), f)
	var q := ChariotSnapshot.rot(a).slerp(ChariotSnapshot.rot(b), f)
	var v := ChariotSnapshot.vel(a).lerp(ChariotSnapshot.vel(b), f)
	out[ChariotSnapshot.POS] = p.x
	out[ChariotSnapshot.POS + 1] = p.y
	out[ChariotSnapshot.POS + 2] = p.z
	out[ChariotSnapshot.ROT] = q.x
	out[ChariotSnapshot.ROT + 1] = q.y
	out[ChariotSnapshot.ROT + 2] = q.z
	out[ChariotSnapshot.ROT + 3] = q.w
	out[ChariotSnapshot.VEL] = v.x
	out[ChariotSnapshot.VEL + 1] = v.y
	out[ChariotSnapshot.VEL + 2] = v.z
	out[ChariotSnapshot.CART_ANGLE] = lerp_angle(a[ChariotSnapshot.CART_ANGLE], b[ChariotSnapshot.CART_ANGLE], f)
	out[ChariotSnapshot.CART_ANG_VEL] = lerpf(a[ChariotSnapshot.CART_ANG_VEL], b[ChariotSnapshot.CART_ANG_VEL], f)
	out[ChariotSnapshot.STAMINA] = lerpf(a[ChariotSnapshot.STAMINA], b[ChariotSnapshot.STAMINA], f)
	return out


# ---------------------------------------------------------------- transport + lag sim

func _connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _lag_send(kind: int, slot: int, data: PackedByteArray) -> void:
	if loss_pct > 0.0 and _rng.randf() * 100.0 < loss_pct:
		return
	if lag_ms <= 0:
		_dispatch(kind, slot, data)
	else:
		_lag_queue.append([Time.get_ticks_msec() + lag_ms, kind, slot, data])


func _flush_lag() -> void:
	var now := Time.get_ticks_msec()
	while not _lag_queue.is_empty() and int(_lag_queue[0][0]) <= now:
		var e: Array = _lag_queue.pop_front()
		_dispatch(int(e[1]), int(e[2]), e[3])


func _dispatch(kind: int, slot: int, data: PackedByteArray) -> void:
	if not _connected():
		return
	if kind == KIND_INPUT:
		_bytes_out += data.size()
		_rpc_input.rpc_id(1, slot, data)
	else:
		_bytes_out += data.size() * multiplayer.get_peers().size()
		_rpc_snapshots.rpc(data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_input(slot: int, data: PackedByteArray) -> void: # NET: host
	if not multiplayer.is_server():
		return
	if _owners.get(slot, -1) != multiplayer.get_remote_sender_id():
		return # CONTRACT: a peer may only drive its own slot
	_bytes_in += data.size()
	var last := int(_last_recv.get(slot, 0))
	var fresh: Array[ChariotInput] = []
	var i := 0
	while i + 10 <= data.size():
		var inp := ChariotInput.from_bytes(data.slice(i, i + 10))
		if inp.seq > last:
			fresh.append(inp)
		i += 10
	if fresh.is_empty():
		return # duplicates or late packet
	fresh.sort_custom(func(x: ChariotInput, y: ChariotInput) -> bool: return x.seq < y.seq)
	var q: Array = _queues.get(slot, [])
	q.append_array(fresh)
	_queues[slot] = q
	_last_recv[slot] = fresh[-1].seq


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshots(packet: PackedByteArray) -> void: # NET: clients
	_bytes_in += packet.size()
	if packet.size() < 8:
		return
	var t := packet.decode_double(0)
	if NetClock.is_synced():
		var age := NetClock.now() - t
		if not _age_init:
			_age_avg = age
			_age_init = true
		_age_jitter = lerpf(_age_jitter, absf(age - _age_avg), 0.1)
		_age_avg = lerpf(_age_avg, age, 0.1)
		var want := clampf(_age_avg + 2.0 * _age_jitter + 1.0 / SNAPSHOT_HZ, INTERP_DELAY, MAX_INTERP_DELAY)
		interp_delay = lerpf(interp_delay, want, 0.1)
	var off := 8
	while off + ENTRY_BYTES <= packet.size():
		var slot := packet.decode_u8(off)
		var ack := packet.decode_u32(off + 1)
		var s := PackedFloat32Array()
		s.resize(ChariotSnapshot.SIZE)
		for k in ChariotSnapshot.SIZE:
			s[k] = packet.decode_float(off + 5 + k * 4)
		off += ENTRY_BYTES
		if not _chariots.has(slot):
			continue
		if slot == local_slot and prediction:
			_reconcile(ack, s)
			continue
		var buf: Array = _buffers.get(slot, [])
		if not buf.is_empty() and t <= float(buf[-1][0]):
			continue
		buf.append([t, s])
		while buf.size() > 2 and float(buf[0][0]) < t - BUFFER_SECONDS:
			buf.pop_front()
		_buffers[slot] = buf


# ---------------------------------------------------------------- stats label (F3, next to DebugOverlay)

func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -330
	_label.offset_right = -10
	_label.offset_top = 10
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.visible = false
	layer.add_child(_label)


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if _label and k and k.pressed and not k.echo and k.keycode == KEY_F3:
		_label.visible = not _label.visible
		_update_label()


func _update_label() -> void:
	if _label == null or not _label.visible:
		return
	var sim := "" if lag_ms <= 0 and loss_pct <= 0.0 else "\nsim lag %d ms, loss %.0f%%" % [lag_ms, loss_pct]
	if multiplayer.is_server():
		_label.text = "Net host · out %.1f kB/s · in %.1f kB/s%s" % [kbps_out, kbps_in, sim]
	else:
		_label.text = "Net · RTT %.0f ms · interp %.0f ms · in %.1f kB/s · out %.1f kB/s · predict %s%s" % [
			rtt_ms, interp_delay * 1000.0, kbps_in, kbps_out, "on" if prediction else "off", sim]
