class_name Combat
extends Node
## Chariot-vs-chariot collisions (heavier/faster wins, cart hits break wheels, horse hits stun), deaths,
## respawn penalty, crow spectator (DESIGN §4, §6). Owner: C12.
## C02 STUB: forwards Chariot.died to GameEvents (chariot_died + kill / self_kill). No respawn yet.
## NET: host only. Public API: match_setup(m), `respawn_delay`.

## Seconds a dead chariot waits before respawn. # TUNE (C12 moves it to a tuning resource)
var respawn_delay := 2.0

var _m: MatchMode


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	m.chariot_sync.chariot_added.connect(_on_chariot_added)
	for slot: int in m.chariot_sync.get_chariots():
		_on_chariot_added(slot, m.chariot_sync.get_chariot(slot))


func _on_chariot_added(slot: int, node: Node3D) -> void:
	var c := node as Chariot
	if c and not c.died.is_connected(_on_died):
		c.died.connect(_on_died.bind(slot))


func _on_died(cause: StringName, source_slot: int, item_uid: int, slot: int) -> void: # NET: host
	if not multiplayer.is_server():
		return
	GameEvents.chariot_died.emit(slot, cause, source_slot, item_uid)
	if source_slot == slot and item_uid >= 0:
		GameEvents.self_kill.emit(slot, item_uid)
	elif source_slot >= 0 and source_slot != slot and item_uid < 0:
		GameEvents.kill.emit(source_slot, slot, cause)
	# TODO(C12): respawn after respawn_delay at track.respawn_transform(progress), crow spectator.
