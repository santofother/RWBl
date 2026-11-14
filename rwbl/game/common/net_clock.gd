extends Node
## Shared match clock (autoload `NetClock`). Owner: C02. `now()` returns the host's clock in seconds on every
## peer, so timers (phase end times) and time-driven items (swinging axe, moving gate) agree without snapshots.
## NET: host = reference clock. Clients ping once a second and smooth the offset (half round trip).
## Public API: `now() -> float`, `is_synced() -> bool`.
# CONTRACT: anything that must look the same on every peer and only depends on time uses NetClock.now().

const SYNC_INTERVAL := 1.0
const SMOOTHING := 0.2 # TUNE: weight of each new sample

var _offset := 0.0
var _synced := false
var _timer := 0.0


## Host clock in seconds (same value on every peer, within a few ms).
func now() -> float:
	if _is_host():
		return _local()
	return _local() + _offset


## True on the host, and on clients after the first sync reply.
func is_synced() -> bool:
	return _is_host() or _synced


func _local() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server() \
		or multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func _process(delta: float) -> void:
	if _is_host():
		_synced = false
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_synced = false
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = SYNC_INTERVAL if _synced else 0.2
		_rpc_request.rpc_id(1, _local())


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_request(client_t: float) -> void: # NET: host
	_rpc_reply.rpc_id(multiplayer.get_remote_sender_id(), client_t, _local())


@rpc("authority", "call_remote", "unreliable")
func _rpc_reply(client_t: float, host_t: float) -> void: # NET: client
	var now_t := _local()
	var sample := host_t + (now_t - client_t) * 0.5 - now_t
	_offset = sample if not _synced else lerpf(_offset, sample, SMOOTHING)
	_synced = true
