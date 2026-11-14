class_name Item
extends Node3D
## Base class of every placed item scene (DESIGN §5). Owner: C10 (hooks are a C02 contract).
## Lifecycle (who calls what):
##   placed(def, owner_slot, uid)        every peer, right after BuildPhase spawns it under MatchMode/Items
##   race_started() / race_ended()       every peer, from GameEvents.phase_changed (base class wires this)
##   triggered()                         every peer, via trigger() on the host (tripwire, timed traps)
##   chariot_entered(chariot)            host, when a chariot enters a child Area3D named "Trigger"
##   chariot_hit(chariot, part, speed)   host, called by Chariot when its body touches this item's body
##   interact(rule, other)               host, when a TagTable rule links this item and another one
## NET: the host decides every effect on chariots. Visual-only motion that depends on time (axe, gate) uses
##   NetClock.now() so all peers agree without snapshots. One-off events go through trigger() (RPC).
## Public API: the hooks above, `def`, `owner_slot`, `uid`, `report_hit(victim)`, `trigger()`,
##   static `find_item(node)`.
# CONTRACT: hook names/arguments. Subclasses override the hooks; they never check other items' ids
#   (use TagTable via interact()).

## The ItemDef this item was spawned from.
var def: ItemDef
## Slot of the player who placed it (-1 = map / crow).
var owner_slot := -1
## Unique id in the match (assigned by the host's BuildPhase).
var uid := -1


func _ready() -> void:
	add_to_group(&"items")
	GameEvents.phase_changed.connect(_on_phase_changed)
	var trig := get_node_or_null(^"Trigger") as Area3D
	if trig:
		trig.collision_layer = Layers.ITEM_TRIGGER
		trig.collision_mask = Layers.CHARIOT
		trig.body_entered.connect(_on_trigger_body)
		trig.area_entered.connect(_on_trigger_body)


## Every peer, once, right after spawning.
func placed(d: ItemDef, slot: int, id: int) -> void:
	def = d
	owner_slot = slot
	uid = id


## Every peer, when a race starts.
func race_started() -> void:
	pass


## Every peer, when a race ends (reset moving parts).
func race_ended() -> void:
	pass


## Every peer, when the host called trigger().
func triggered() -> void:
	pass


## Host: a chariot entered the "Trigger" area.
func chariot_entered(_chariot: Chariot) -> void:
	pass


## Host: a chariot body touched this item's body. part = &"horses" | &"cart".
func chariot_hit(_chariot: Chariot, _part: StringName, _impact_speed: float) -> void:
	pass


## Host: a TagTable rule links this item with `other` (e.g. effect &"ignite").
func interact(_rule: TagRule, _other: Item) -> void:
	pass


## Host: tell scoring this item affected `victim` (only counts if victim isn't the owner).
func report_hit(victim: Chariot) -> void:
	if multiplayer.is_server() and victim and victim.slot != owner_slot:
		GameEvents.trap_hit.emit(uid, owner_slot, victim.slot)


## Host: fire the item's one-off event on every peer (calls triggered() everywhere).
func trigger() -> void:
	if multiplayer.is_server():
		_rpc_triggered.rpc()


## The Item a collider belongs to (the collider itself or an ancestor), or null.
static func find_item(node: Node) -> Item:
	while node:
		if node is Item:
			return node
		node = node.get_parent()
	return null


@rpc("authority", "call_local", "reliable")
func _rpc_triggered() -> void:
	triggered()


func _on_phase_changed(phase: int, _round: int) -> void:
	if phase == Phase.RACE:
		race_started()
	elif phase == Phase.SCORE:
		race_ended()


func _on_trigger_body(body: Node) -> void:
	if not multiplayer.is_server():
		return
	var n := body
	while n and not n is Chariot:
		n = n.get_parent()
	if n:
		chariot_entered(n as Chariot)
