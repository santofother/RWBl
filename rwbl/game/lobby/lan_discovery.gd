class_name LanDiscovery
extends Node
## UDP advertisements and expiring LAN host list. Owner: C03. Runs locally on every peer.
## Public API: listen(), advertise(), stop(), signal hosts_changed; no game/ dependencies.
## Packets contain only game, name, port and players; sender IP comes from the socket.

## Emitted with [{ip, name, port, players}] when the discovered host list changes.
signal hosts_changed(hosts: Array[Dictionary])

const ANNOUNCE_INTERVAL := 1.0
const HOST_TIMEOUT_MS := 3500
const MAX_PACKET_BYTES := 1024

var _listener: PacketPeerUDP
var _sender: PacketPeerUDP
var _discovery_port := 0
var _packet: Dictionary = {}
var _hosts: Dictionary = {}
var _elapsed := 0.0


## Listen on the discovery port (normally the transport's default port + 1).
func listen(port: int) -> Error:
	stop()
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(port, "*")
	if err != OK:
		_listener.close()
		_listener = null
	return err


## Advertise this host once a second; repeat calls update its player count without rebinding.
func advertise(discovery_port: int, host_name: String, game_port: int, players: int) -> Error:
	_packet = {"game": "rwbl", "name": host_name.left(80), "port": game_port, "players": players}
	_discovery_port = discovery_port
	if _sender == null:
		stop()
		_sender = PacketPeerUDP.new()
		_sender.set_broadcast_enabled(true)
		_elapsed = ANNOUNCE_INTERVAL
	return OK


## Close sockets and discard discovered hosts. Safe during a session change or shutdown.
func stop() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	if _sender != null:
		_sender.close()
		_sender = null
	_hosts.clear()


func _process(delta: float) -> void:
	if _sender != null:
		_elapsed += delta
		if _elapsed >= ANNOUNCE_INTERVAL:
			_elapsed = 0.0
			var bytes := JSON.stringify(_packet).to_utf8_buffer()
			_sender.set_dest_address("255.255.255.255", _discovery_port)
			_sender.put_packet(bytes)
			# WHY: also allow two instances on a machine with no active LAN interface.
			_sender.set_dest_address("127.0.0.1", _discovery_port)
			_sender.put_packet(bytes)
	if _listener == null:
		return
	var changed := false
	# WHY: bound work per frame even if unrelated UDP traffic reaches this port.
	for _i in mini(_listener.get_available_packet_count(), 32):
		var bytes := _listener.get_packet()
		var ip := _listener.get_packet_ip()
		if bytes.size() > MAX_PACKET_BYTES:
			continue
		var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not value is Dictionary:
			continue
		var d: Dictionary = value
		if d.get("game") != "rwbl" or not d.get("name") is String:
			continue
		if not (d.get("port") is float or d.get("port") is int):
			continue
		if not (d.get("players") is float or d.get("players") is int):
			continue
		var port := int(d["port"])
		var players := int(d["players"])
		if port < 1 or port > 65535 or players < 1 or players > 5:
			continue
		var key := "%s:%d" % [ip, port]
		var host := {"ip": ip, "name": String(d["name"]).left(80), "port": port, "players": players}
		if not _hosts.has(key) or _hosts[key]["host"] != host:
			changed = true
		_hosts[key] = {"host": host, "seen": Time.get_ticks_msec()}
	for key: String in _hosts.keys():
		if Time.get_ticks_msec() - int(_hosts[key]["seen"]) > HOST_TIMEOUT_MS:
			_hosts.erase(key)
			changed = true
	if changed:
		var hosts: Array[Dictionary] = []
		for entry: Dictionary in _hosts.values():
			hosts.append(entry["host"])
		hosts_changed.emit(hosts)


func _exit_tree() -> void:
	stop()
