extends Item
## Lion dung: a brown swirl with flies. Stepping in it (horses) makes the chariot slip: a sideways kick, no
## steering for a moment and a drunk wobble. Single use per race: it vanishes for everyone via trigger() and
## comes back when the race ends. Owner: C25.
## NET: host applies the effect; the vanish is visual + trigger disable on every peer.

var _used := false


func chariot_entered(chariot: Chariot) -> void:
	if _used or chariot.dead:
		return
	var t := Item.tuning()
	var side := chariot.global_basis.x
	side.y = 0.0
	# WHY: kick direction from the uid so the slip isn't always to the same side
	var dir := 1.0 if (uid + chariot.slot) % 2 == 0 else -1.0
	chariot.apply_impulse(side.normalized() * dir * t.dung_spin_kick * chariot.tuning.horse_mass)
	chariot.add_effect(Effects.NO_STEER, t.dung_nosteer_time, 1.0, owner_slot)
	chariot.add_effect(Effects.DRUNK, t.dung_drunk_time, 1.0, owner_slot)
	print("[Item] DUNG %d" % uid)
	report_hit(chariot)
	_used = true
	trigger()


func triggered() -> void:
	_used = true
	_show(false)


func race_ended() -> void:
	_used = false
	_show(true)


func _show(on: bool) -> void:
	visible = on
	var trig := get_node_or_null(^"Trigger") as Area3D
	if trig:
		trig.set_deferred(&"monitoring", on)
