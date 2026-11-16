extends Item
## Whirlwind: a spinning dust funnel. A chariot inside gets hopped, stunned briefly on entry, wobbles (DRUNK)
## and is swirled sideways around the funnel while it stays, so it spits chariots out across the road. Owner: C25.
## NET: host applies it every physics tick; funnel spins on every peer from NetClock.now().


func chariot_entered(chariot: Chariot) -> void:
	var t := Item.tuning()
	chariot.stun(t.whirlwind_stun, owner_slot)
	chariot.apply_impulse(Vector3.UP * t.whirlwind_lift * chariot.tuning.horse_mass)
	print("[Item] WHIRL %d" % uid)
	report_hit(chariot)


func _physics_process(delta: float) -> void:
	_spin()
	if not multiplayer.is_server():
		return
	var t := Item.tuning()
	for c: Chariot in trigger_chariots():
		var rel := c.global_position - global_position
		rel.y = 0.0
		var swirl := Vector3(-rel.z, 0.0, rel.x)
		if swirl.length() < 0.1:
			swirl = global_basis.x
		c.apply_impulse(swirl.normalized() * t.whirlwind_swirl * delta * c.tuning.horse_mass)
		c.add_effect(Effects.DRUNK, t.whirlwind_drunk_time, 1.0, owner_slot)


func _process(_delta: float) -> void:
	_spin()


func _spin() -> void:
	var f := get_node_or_null(^"Funnel") as Node3D
	if f:
		f.rotation.y = fmod(NetClock.now() * 6.0, TAU)
