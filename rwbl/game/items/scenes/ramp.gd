extends Item
## Ramp: launches a grounded chariot up and along the ramp's forward (-Z) with Chariot.apply_impulse()
## (C04: the cart height follows the horses, so the wedge is visual only, no WORLD collider). Owner: C10.
## NET: host.


func chariot_entered(chariot: Chariot) -> void:
	if not chariot.grounded:
		return
	var t := Item.tuning()
	var fwd := -global_basis.z
	fwd.y = 0.0
	var dv := Vector3.UP * t.ramp_launch_up + fwd.normalized() * t.ramp_launch_forward
	chariot.apply_impulse(dv * chariot.tuning.horse_mass)
	report_hit(chariot)
