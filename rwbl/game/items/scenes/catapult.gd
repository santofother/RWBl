extends Item
## Catapult: a wooden throwing arm. A grounded chariot driving over it is lobbed high and far forward (-Z),
## then lands (maybe on someone). The arm flips on every peer via trigger(). Owner: C25.
## NET: host launches; arm animation is visual.

var _flip := 0.0


func chariot_entered(chariot: Chariot) -> void:
	if not chariot.grounded:
		return
	var t := Item.tuning()
	var fwd := -global_basis.z
	fwd.y = 0.0
	chariot.apply_impulse((Vector3.UP * t.catapult_up + fwd.normalized() * t.catapult_forward) * chariot.tuning.horse_mass)
	print("[Item] CATAPULT %d" % uid)
	report_hit(chariot)
	trigger()


func triggered() -> void:
	_flip = 1.0


func race_ended() -> void:
	_flip = 0.0


func _process(delta: float) -> void:
	_flip = maxf(_flip - delta * 1.5, 0.0)
	var arm := get_node_or_null(^"Arm") as Node3D
	if arm:
		arm.rotation.x = deg_to_rad(lerpf(-35.0, 55.0, _flip))
