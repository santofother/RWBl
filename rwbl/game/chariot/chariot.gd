class_name Chariot
extends Node3D
## One chariot: horse pair (this node's transform) + cart trailing on a hitch (DESIGN §4). Owner: C04.
## C02 STUB: simple arcade movement so tracks, bots and items can be built before the real controller.
## C04 replaces the body of step() with the two-body controller (keep the public API).
## NET: host simulates (`step`). Clients only render (`apply_snapshot`); the owner may predict with `step`
## (C07). Never moved by stock RigidBody3D physics.
## Public API:
##   vars `slot`, `tuning`, `track`, `velocity`, `stamina`, `wheel_state`, `dead`, `frozen`, `cart_angle`
##   step(input, delta), get_snapshot(), apply_snapshot(s), get_speed(), get_forward(), cart_global_position()
##   add_effect(effect, duration, strength, source_slot), has_effect(effect), apply_impulse(impulse)
##   damage_wheel(side, source_slot), stun(duration, source_slot), kill(cause, source_slot, item_uid),
##   respawn(xform). Signals below.
# CONTRACT: root is a Node3D whose transform is the horse pair; forward is -Z. All methods/signals above.
# CONTRACT: on the host, when the horses or cart touch a body that belongs to an Item, the chariot calls
#   `item.chariot_hit(self, part, impact_speed)` (see Item.find_item()). Item triggers (Area3D) call
#   `item.chariot_entered(self)` themselves.

## host · collided with something. part = &"horses" | &"cart". `other` = the collider node.
signal hit(part: StringName, other: Node, impact_speed: float)
## host · a wheel broke (side = ChariotSnapshot.WHEEL_LEFT / WHEEL_RIGHT).
signal wheel_broken(side: int, source_slot: int)
## host · the chariot died. cause e.g. &"pit", &"spike_wall", &"spear", &"wheel". source_slot -1 = nobody.
signal died(cause: StringName, source_slot: int, item_uid: int)
## host · respawn() finished.
signal respawned()

const TUNING_DEFAULT := preload("res://game/chariot/default_tuning.tres")

## Player slot driving this chariot (PlayerInfo.slot). Also the node name `Chariot<slot>`.
var slot := -1
## Gameplay numbers. Shared resource: the F2 panel edits it live.
var tuning: ChariotTuning = TUNING_DEFAULT
## Track for surface queries (may be null in test scenes: surface = normal).
var track: Track
## World velocity, m/s.
var velocity := Vector3.ZERO
## 0..1, spent by the whip.
var stamina := 1.0
## Broken wheel bits (ChariotSnapshot.WHEEL_*).
var wheel_state := 0
## True between kill() and respawn(). Dead chariots don't move.
var dead := false
## Set by the race (countdown) to hold the chariot still.
var frozen := false
## Cart yaw relative to the horses, radians.
var cart_angle := 0.0
## Cart yaw speed, rad/s.
var cart_ang_vel := 0.0

var _effects: Dictionary = {} # StringName -> [time_left, strength, source_slot]
var _whip_cd := 0.0
var _flags := 0 # client side: flags from the last snapshot

@onready var _cart: Node3D = $Cart


## Advance the simulation one tick. NET: host (and owner prediction). The only thing that moves the chariot.
func step(input: ChariotInput, delta: float) -> void:
	_tick_effects(delta)
	stamina = minf(1.0, stamina + tuning.stamina_regen * delta)
	_whip_cd = maxf(0.0, _whip_cd - delta)
	if dead or frozen:
		velocity = Vector3.ZERO
		return
	if input.whip and _whip_cd <= 0.0 and stamina >= tuning.whip_stamina_cost:
		stamina -= tuning.whip_stamina_cost
		_whip_cd = tuning.whip_cooldown
		add_effect(Effects.BOOST, tuning.whip_duration, 1.0, slot)
	var surface: StringName = track.surface_at(global_position) if track else Surface.NORMAL
	var steer := input.steer
	if has_effect(Effects.REVERSE_STEER):
		steer = -steer
	var stunned := has_effect(Effects.STUN)
	if stunned or has_effect(Effects.NO_STEER):
		steer = 0.0
	var top := tuning.max_speed * tuning.speed_mult_for(surface)
	if wheel_state == ChariotSnapshot.WHEEL_LEFT | ChariotSnapshot.WHEEL_RIGHT:
		top = minf(top, tuning.crawl_speed)
	elif wheel_state != 0:
		top *= tuning.limp_speed_mult
		steer *= tuning.limp_steer_mult
	if has_effect(Effects.SLOW):
		top *= 1.0 - 0.5 * _effect_strength(Effects.SLOW)
	if has_effect(Effects.BOOST):
		top += tuning.whip_boost * _effect_strength(Effects.BOOST)
	var fwd := get_forward()
	var speed := velocity.dot(fwd)
	var accel := -tuning.drag * speed
	if not stunned:
		accel += input.throttle * tuning.horse_thrust - input.brake * tuning.brake_decel * signf(speed)
	var new_speed := clampf(speed + accel * delta, -3.0, maxf(top, absf(speed) - tuning.brake_decel * delta))
	velocity += fwd * (new_speed - speed)
	rotate_y(-steer * tuning.steer_rate * delta * clampf(absf(new_speed) / 4.0, 0.0, 1.0))
	# Grip only removes sideways slip: low grip (oil, ice) keeps the old direction, so the chariot slides.
	fwd = get_forward()
	var along := velocity.dot(fwd)
	var lateral := velocity - fwd * along
	velocity = fwd * along + lateral * (1.0 - clampf(tuning.grip_for(surface) * 8.0 * delta, 0.0, 1.0))
	global_position += velocity * delta
	global_position.y = 0.0 # TODO(C04): ramps / jumps
	var target_cart := clampf(-steer * 0.35 + velocity.dot(global_basis.x) * 0.05, -1.2, 1.2)
	var prev := cart_angle
	cart_angle = lerpf(cart_angle, target_cart, clampf(4.0 * delta, 0.0, 1.0))
	cart_ang_vel = (cart_angle - prev) / maxf(delta, 0.0001)
	_update_cart_visual()


## Snapshot for clients (layout: ChariotSnapshot). NET: host.
func get_snapshot() -> PackedFloat32Array:
	var flags := 0
	if has_effect(Effects.STUN):
		flags |= ChariotSnapshot.FLAG_STUNNED
	if has_effect(Effects.BOOST):
		flags |= ChariotSnapshot.FLAG_BOOSTING
	if has_effect(Effects.BARBED):
		flags |= ChariotSnapshot.FLAG_BARBED
	if dead:
		flags |= ChariotSnapshot.FLAG_DEAD
	if frozen:
		flags |= ChariotSnapshot.FLAG_FROZEN
	return ChariotSnapshot.make(global_position, global_basis.get_rotation_quaternion(), velocity,
		cart_angle, cart_ang_vel, wheel_state, stamina, flags)


## Show a host snapshot. NET: clients (C07 adds interpolation before calling this).
func apply_snapshot(s: PackedFloat32Array) -> void:
	if s.size() < ChariotSnapshot.SIZE:
		return
	global_transform = Transform3D(Basis(ChariotSnapshot.rot(s)), ChariotSnapshot.pos(s))
	velocity = ChariotSnapshot.vel(s)
	cart_angle = s[ChariotSnapshot.CART_ANGLE]
	cart_ang_vel = s[ChariotSnapshot.CART_ANG_VEL]
	wheel_state = int(s[ChariotSnapshot.WHEELS])
	stamina = s[ChariotSnapshot.STAMINA]
	_flags = int(s[ChariotSnapshot.FLAGS])
	dead = _flags & ChariotSnapshot.FLAG_DEAD != 0
	frozen = _flags & ChariotSnapshot.FLAG_FROZEN != 0
	_update_cart_visual()


## Signed forward speed, m/s.
func get_speed() -> float:
	return velocity.dot(get_forward())


## Horse heading (unit, -Z of this node).
func get_forward() -> Vector3:
	return -global_basis.z


## Centre of the cart in world space.
func cart_global_position() -> Vector3:
	return _cart.global_position if _cart else global_position


## Put a timed effect on the chariot (Effects.*). Re-adding refreshes the timer. NET: host.
func add_effect(effect: StringName, duration: float, strength: float = 1.0, source_slot: int = -1) -> void:
	_effects[effect] = [duration, strength, source_slot]


## True while `effect` is active (host; on clients only the snapshot flags are known).
func has_effect(effect: StringName) -> bool:
	return _effects.has(effect)


## Instant velocity change (ramp launch, boulder push). NET: host.
func apply_impulse(impulse: Vector3) -> void:
	velocity += impulse / maxf(tuning.horse_mass, 0.01)


## Break one wheel (no-op if already broken). NET: host.
func damage_wheel(side: int, source_slot: int = -1) -> void:
	if dead or wheel_state & side:
		return
	wheel_state |= side
	wheel_broken.emit(side, source_slot)


## Stun the horses (no thrust, no steering). NET: host.
func stun(duration: float, source_slot: int = -1) -> void:
	add_effect(Effects.STUN, duration, 1.0, source_slot)


## Kill the chariot. Combat (C12) handles respawn and scoring events. NET: host.
func kill(cause: StringName, source_slot: int = -1, item_uid: int = -1) -> void:
	if dead:
		return
	dead = true
	velocity = Vector3.ZERO
	died.emit(cause, source_slot, item_uid)


## Place the chariot at `xform`, repaired and alive. NET: host (clients follow by snapshot).
func respawn(xform: Transform3D) -> void:
	global_transform = xform
	velocity = Vector3.ZERO
	cart_angle = 0.0
	cart_ang_vel = 0.0
	wheel_state = 0
	dead = false
	_effects.clear()
	_update_cart_visual()
	respawned.emit()


func _tick_effects(delta: float) -> void:
	for e: StringName in _effects.keys():
		_effects[e][0] -= delta
		if _effects[e][0] <= 0.0:
			_effects.erase(e)


func _effect_strength(effect: StringName) -> float:
	return float(_effects[effect][1]) if _effects.has(effect) else 0.0


func _update_cart_visual() -> void:
	if _cart:
		_cart.rotation.y = cart_angle
