extends Item
## Swinging axe: a blade on a pendulum under a gantry, swinging across the item's X axis (the road, when placed
## facing along the track). Angle = f(NetClock.now()) so every peer shows the same swing without snapshots.
## The "Trigger" area follows the blade; a chariot it touches dies (`axe_lethal`, C24) or, with that off, is
## stunned and knocked sideways. Owner: C10 (C24: lethal, bigger blade).
## NET: swing on every peer (NetClock); hits on the host. Public API: `swing_angle()`.

## Pivot height above the ground and pivot-to-blade-centre length, m (matches the scene).
const PIVOT_HEIGHT := 5.2
const ARM := 4.2

@onready var _arm: Node3D = $Arm
@onready var _trig: Area3D = $Trigger


## Current pendulum angle, radians (0 = blade straight down; + = towards local +X).
func swing_angle(at: float = NetClock.now()) -> float:
	var t := Item.tuning()
	var phase := float(uid) * 0.37 # WHY: several axes don't swing in lockstep
	return deg_to_rad(t.axe_swing_deg) * sin(TAU * (at / t.axe_period + phase))


func _physics_process(_delta: float) -> void:
	_pose()


func _process(_delta: float) -> void:
	_pose()


func _pose() -> void:
	var a := swing_angle()
	_arm.rotation = Vector3(0, 0, a)
	# The trigger is a direct child (Item wires "Trigger"), so move it to where the blade is.
	_trig.position = Vector3(0, PIVOT_HEIGHT, 0) + Vector3(sin(a), -cos(a), 0) * ARM
	_trig.rotation = Vector3(0, 0, a)


## Host: the blade touched `chariot`.
func chariot_entered(chariot: Chariot) -> void:
	var t := Item.tuning()
	var now := NetClock.now()
	var swing_dir := signf(swing_angle(now + 0.01) - swing_angle(now)) # which way the blade moves
	var side := global_basis.x
	side.y = 0.0
	if chariot.dead:
		return
	chariot.apply_impulse(side.normalized() * swing_dir * t.axe_knockback * chariot.tuning.horse_mass)
	print("[Item] AXE %d angle=%.0f%s" % [uid, rad_to_deg(swing_angle(now)), " kill" if t.axe_lethal else ""])
	report_hit(chariot)
	if t.axe_lethal:
		chariot.kill(&"axe", owner_slot, uid) # C24: the blade is deadly, time your run
	else:
		chariot.stun(t.axe_stun, owner_slot)
