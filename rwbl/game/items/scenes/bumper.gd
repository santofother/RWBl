extends Item
## Bouncy bumper: a pinball-style red/gold drum. A chariot that touches it is shoved away from its centre
## (flat), so chariots ping-pong between bumpers and into each other. Not solid. Owner: C25.
## NET: host applies the shove; the drum squashes on every peer via trigger() (visual).

var _squash := 0.0


func chariot_entered(chariot: Chariot) -> void:
	var t := Item.tuning()
	var away := chariot.global_position - global_position
	away.y = 0.0
	if away.length() < 0.1:
		away = chariot.get_forward()
	chariot.apply_impulse(away.normalized() * t.bumper_push * chariot.tuning.horse_mass)
	if t.bumper_stun > 0.0:
		chariot.stun(t.bumper_stun, owner_slot)
	print("[Item] BUMP %d" % uid)
	report_hit(chariot)
	trigger()


func triggered() -> void:
	_squash = 1.0


func _process(delta: float) -> void:
	_squash = maxf(_squash - delta * 4.0, 0.0)
	var drum := get_node_or_null(^"Drum") as Node3D
	if drum:
		var s := 1.0 + 0.25 * _squash
		drum.scale = Vector3(s, 1.0 - 0.3 * _squash, s)
