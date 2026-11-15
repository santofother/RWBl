extends Item
## Laurel pad: a chariot whose horses cross it gets Effects.BOOST (above normal top speed). Owner: C10.
## NET: host applies the boost; the pad's laurel ring spins on every peer (visual only).


func chariot_entered(chariot: Chariot) -> void:
	var t := Item.tuning()
	chariot.add_effect(Effects.BOOST, t.pad_boost_time, t.pad_boost_strength, owner_slot)
	report_hit(chariot)


func _process(delta: float) -> void:
	var ring := get_node_or_null(^"Ring") as Node3D
	if ring:
		ring.rotate_y(delta * 1.5)
