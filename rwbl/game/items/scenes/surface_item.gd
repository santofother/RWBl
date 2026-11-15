extends Item
## Flat ground patch that changes the Surface under it: oil slick, mud patch, ice sheet. Owner: C10.
## placed(): registers a Track surface patch the size of the def footprint (every peer, so prediction and the
## HUD agree); removed again when the item leaves the tree. The chariot controller does the handling.
## `lock_steer` (ice): host puts Effects.NO_STEER on chariots whose horses are inside, refreshed every tick.
## NET: patch on every peer; effects + report_hit on the host.

## Surface.* this patch reports.
@export var surface: StringName = Surface.OIL
## Ice: no steering while the horses are on it.
@export var lock_steer := false


func placed(d: ItemDef, slot: int, id: int) -> void:
	super.placed(d, slot, id)
	var t := get_track()
	if t:
		t.register_surface_patch(self, surface, d.footprint * 0.5)


func _exit_tree() -> void:
	if _track and is_instance_valid(_track):
		_track.unregister_surface_patch(self)


func chariot_entered(chariot: Chariot) -> void:
	report_hit(chariot)


func _physics_process(_delta: float) -> void:
	if not lock_steer or not multiplayer.is_server():
		return
	var inside := trigger_chariots()
	for c: Chariot in inside:
		if (inside[c] as Array).has(&"horses"):
			c.add_effect(Effects.NO_STEER, Item.tuning().ice_no_steer_refresh, 1.0, owner_slot)
