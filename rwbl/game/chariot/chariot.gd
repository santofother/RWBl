class_name Chariot
extends Node3D
## One chariot: horse pair (this node's transform) + cart trailing on a hitch (DESIGN §4). Owner: C04.
## Two-body model: the horses steer and pull; the cart hangs on a hitch `HITCH_OFFSET` behind them and swings
## with its own yaw (`cart_angle`, relative to the horses). Sideways slip at the cart axle is killed by surface
## grip up to a max lateral accel; past that the cart slides (fishtail), a spring/damper on the hitch pulls it
## back in line, and past `jackknife_angle` it slams into the horses (jackknife, speed loss).
## Collisions: kinematic bodies `HorseBody` (layer HORSES) and `Cart/CartBody` (layer CART) are swept with shape
## casts every step; walls bounce, chariots exchange momentum, items get `chariot_hit()`.
## Visuals: `HorseModel` (art/chariot/horses.glb) + `Cart/CartModel` (cart.glb, Blender source art_src/).
## Surfaces named "TeamColor" take the colour of `$Horses.material_override` (ChariotSync sets it).
## NET: host simulates (`step`). Clients only render (`apply_snapshot`); the owner may predict with `step`
## (C07). Never moved by stock RigidBody3D physics. step() never reads Input and has no RPCs.
## Public API:
##   vars `slot`, `tuning`, `track`, `velocity`, `stamina`, `wheel_state`, `dead`, `frozen`, `cart_angle`,
##   `cart_ang_vel`, `grounded`, `surface`
##   step(input, delta), get_snapshot(), apply_snapshot(s), get_speed(), get_forward(), cart_global_position()
##   add_effect(effect, duration, strength, source_slot), has_effect(effect), effect_strength(effect),
##   apply_impulse(impulse), damage_wheel(side, source_slot), stun(duration, source_slot),
##   kill(cause, source_slot, item_uid), respawn(xform), set_team_color(color), part_of(body),
##   static find_chariot(node). Signals below.
# CONTRACT: root is a Node3D whose transform is the horse pair; forward is -Z. All methods/signals above.
# CONTRACT: on the host, when the horses or cart touch a body that belongs to an Item, the chariot calls
#   `item.chariot_hit(self, part, impact_speed)` (see Item.find_item()). Item triggers (Area3D) call
#   `item.chariot_entered(self)` themselves.
# CONTRACT: children `Horses` (MeshInstance3D, tint carrier), `HorseBody`, `Cart/CartBody`, `Label` (Label3D).

## host · collided with something. part = &"horses" | &"cart". `other` = the collider node (for a chariot:
## its HorseBody / CartBody, use Chariot.find_chariot()). Both chariots of a crash get one.
signal hit(part: StringName, other: Node, impact_speed: float)
## host · a wheel broke (side = ChariotSnapshot.WHEEL_LEFT / WHEEL_RIGHT).
signal wheel_broken(side: int, source_slot: int)
## host · the chariot died. cause e.g. &"pit", &"spike_wall", &"spear", &"wheel", &"fall". -1 = nobody.
signal died(cause: StringName, source_slot: int, item_uid: int)
## host · respawn() finished.
signal respawned()

const TUNING_DEFAULT := preload("res://game/chariot/default_tuning.tres")
## Hitch point behind the horse-pair centre, m (end of the yoke pole in horses.glb).
const HITCH_OFFSET := 1.1
## Axle to the front of the cart, m (where the visual pole meets the cart).
const POLE_FRONT := 0.8
## Visual wheel radius, m (cart.glb).
const WHEEL_RADIUS := 0.55
## What the horse and cart bodies collide with (card C04).
const COLLIDE_MASK := Layers.WORLD | Layers.WALL | Layers.ITEM_SOLID | Layers.HORSES | Layers.CART
## Below this height the chariot dies (fell off the world).
const FALL_KILL_Y := -30.0
## Same collider can't emit hit() again for this long, s.
const HIT_COOLDOWN := 0.3
## Max height difference the wheels stick to the ground over, m.
const GROUND_SNAP := 0.5

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
## Cart yaw relative to the horses, radians (+ = cart swung right).
var cart_angle := 0.0
## Cart yaw speed relative to the horses, rad/s.
var cart_ang_vel := 0.0
## True while the wheels touch the ground (false after a ramp launch until landing).
var grounded := true
## Surface under the horses at the last step (Surface.*). For HUD / debug.
var surface: StringName = Surface.NORMAL

var _effects: Dictionary = {} # StringName -> [time_left, strength, source_slot]
var _whip_cd := 0.0
var _exhausted_t := 0.0
var _flags := 0 # client side: flags from the last snapshot
var _sim_time := 0.0
var _yaw_rate := 0.0 # horse yaw speed this step, rad/s
var _hit_cd: Dictionary = {} # collider instance id -> seconds left
var _own_rids: Array[RID] = []
var _team_mat: Material
var _team_surfaces: Array = [] # [MeshInstance3D, surface index]
var _wheel_spin := 0.0
var _gallop := 0.0
var _vis_speed := 0.0 # visuals: last frame's speed / heading, smoothed accel and turn rate
var _vis_yaw := 0.0
var _vis_acc := 0.0
var _vis_turn := 0.0

@onready var _cart: Node3D = $Cart
@onready var _tint: MeshInstance3D = $Horses
@onready var _horse_body: AnimatableBody3D = $HorseBody
@onready var _horse_shape: CollisionShape3D = $HorseBody/Shape
@onready var _cart_body: AnimatableBody3D = $Cart/CartBody
@onready var _cart_shape: CollisionShape3D = $Cart/CartBody/Shape
@onready var _cart_model: Node3D = get_node_or_null(^"Cart/CartModel/Body")
@onready var _pole: Node3D = get_node_or_null(^"Cart/CartModel/Pole")
@onready var _wheel_l: Node3D = get_node_or_null(^"Cart/CartModel/Body/WheelL")
@onready var _wheel_r: Node3D = get_node_or_null(^"Cart/CartModel/Body/WheelR")
@onready var _horse_l: Node3D = get_node_or_null(^"HorseModel/HorseL")
@onready var _horse_r: Node3D = get_node_or_null(^"HorseModel/HorseR")
@onready var _horse_model: Node3D = get_node_or_null(^"HorseModel")


func _ready() -> void:
	for b: AnimatableBody3D in [_horse_body, _cart_body]:
		b.sync_to_physics = false
		b.collision_mask = COLLIDE_MASK
		_own_rids.append(b.get_rid())
	_horse_body.collision_layer = Layers.HORSES
	_cart_body.collision_layer = Layers.CART
	_horse_body.add_collision_exception_with(_cart_body)
	_collect_team_surfaces()
	TuningPanel.register(tuning, "Chariot")
	_update_cart_visual()


## Advance the simulation one tick. NET: host (and owner prediction). The only thing that moves the chariot.
func step(input: ChariotInput, delta: float) -> void:
	if delta <= 0.0:
		return
	_sim_time += delta
	_tick_timers(delta)
	if dead or frozen:
		velocity = Vector3.ZERO
		cart_ang_vel = 0.0
		_yaw_rate = 0.0
		_sync_bodies()
		return
	_try_whip(input)
	var t := tuning
	surface = _surface_at(global_position)
	var cart_surface := _surface_at(cart_global_position())
	var old_axle := cart_global_position()
	var old_cart_xf := _cart_body.global_transform
	var stunned := has_effect(Effects.STUN)

	# Horses: steering, thrust/brake, sideways grip. Only with hooves on the ground.
	if grounded:
		var speed0 := _flat(velocity).dot(get_forward())
		var authority := clampf(absf(speed0) / t.steer_full_speed, 0.0, 1.0) \
			* lerpf(1.0, t.steer_at_top_speed, clampf(absf(speed0) / t.max_speed, 0.0, 1.0))
		var target := -_steer_from(input, stunned) * t.steer_rate * authority * (1.0 if speed0 >= -0.1 else -1.0)
		# WHY: horses ease into a turn (yaw has inertia) and the cart can yank them off it (_step_cart).
		# Bounded yaw accel: a hard yank from the cart can beat the horses (spin-out).
		_yaw_rate = move_toward(_yaw_rate, target, t.steer_rate * t.steer_response * delta)
	else:
		_yaw_rate *= 1.0 - clampf(0.5 * delta, 0.0, 1.0) # spins on in the air
	rotate_y(_yaw_rate * delta)
	if grounded:
		# WHY: velocity keeps its old direction after the turn; grip below pulls it in line. Low grip = slide.
		var fwd := get_forward()
		var speed := _flat(velocity).dot(fwd)
		velocity += fwd * (_drive(speed, input, stunned, delta) - speed)
		var right := global_basis.x
		velocity -= right * _grip_delta(_flat(velocity).dot(right), t.grip_for(surface), t.horse_grip_rate,
			t.horse_max_lat_accel, delta)
	else:
		velocity.y -= t.gravity * delta

	_step_cart(cart_surface, delta)
	_move_horses(delta)
	_follow_ground()
	_check_cart_contact(old_axle, old_cart_xf)
	if global_position.y < FALL_KILL_Y:
		kill(&"fall")
	_sync_bodies()


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
	grounded = absf(velocity.y) < 0.01
	_sync_bodies()


## Signed forward speed, m/s.
func get_speed() -> float:
	return velocity.dot(get_forward())


## Horse heading (unit, -Z of this node).
func get_forward() -> Vector3:
	return -global_basis.z


## Centre of the cart (axle, ground level) in world space. Pure math, valid any time.
func cart_global_position() -> Vector3:
	return global_position + global_basis.z * HITCH_OFFSET + _cart_back() * tuning.hitch_length


## Put a timed effect on the chariot (Effects.*). Re-adding refreshes the timer. NET: host.
func add_effect(effect: StringName, duration: float, strength: float = 1.0, source_slot: int = -1) -> void:
	_effects[effect] = [duration, strength, source_slot]


## True while `effect` is active (host; on clients only the snapshot flags are known).
func has_effect(effect: StringName) -> bool:
	return _effects.has(effect)


## Strength of an active effect (0 when not active).
func effect_strength(effect: StringName) -> float:
	return float(_effects[effect][1]) if _effects.has(effect) else 0.0


## Instant velocity change (ramp launch, boulder push). An upward part launches the chariot. NET: host.
func apply_impulse(impulse: Vector3) -> void:
	velocity += impulse / maxf(tuning.horse_mass, 0.01)
	if velocity.y > 0.01:
		grounded = false


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


## Place the chariot at `xform`, repaired, rested and alive. NET: host (clients follow by snapshot).
func respawn(xform: Transform3D) -> void:
	global_transform = xform
	velocity = Vector3.ZERO
	cart_angle = 0.0
	cart_ang_vel = 0.0
	wheel_state = 0
	stamina = 1.0
	_exhausted_t = 0.0
	_whip_cd = 0.0
	_yaw_rate = 0.0
	grounded = true
	dead = false
	_effects.clear()
	_hit_cd.clear()
	_sync_bodies()
	respawned.emit()


## Tint every "TeamColor" surface (blankets, plumes, cape, cart stripe). Any peer, visual only.
func set_team_color(color: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	_tint.material_override = m


## &"cart" for this chariot's cart body, else &"horses".
func part_of(body: Node) -> StringName:
	return &"cart" if body == _cart_body else &"horses"


## The Chariot a collider belongs to (the node itself or an ancestor), or null.
static func find_chariot(node: Node) -> Chariot:
	while node:
		if node is Chariot:
			return node
		node = node.get_parent()
	return null


# ---------------------------------------------------------------- simulation helpers

func _tick_timers(delta: float) -> void:
	for e: StringName in _effects.keys():
		_effects[e][0] -= delta
		if _effects[e][0] <= 0.0:
			_effects.erase(e)
	for id: int in _hit_cd.keys():
		_hit_cd[id] -= delta
		if _hit_cd[id] <= 0.0:
			_hit_cd.erase(id)
	_whip_cd = maxf(0.0, _whip_cd - delta)
	if _exhausted_t > 0.0:
		_exhausted_t -= delta # WHY: spamming to zero costs extra recovery time
	else:
		stamina = minf(1.0, stamina + tuning.stamina_regen * delta)


func _try_whip(input: ChariotInput) -> void:
	if not input.whip or _whip_cd > 0.0 or stamina <= 0.01:
		return
	var t := tuning
	# Tired horses (low stamina) give a weaker boost; at zero they ignore the whip.
	var strength := 1.0 if stamina >= t.tired_threshold else stamina / maxf(t.tired_threshold, 0.01)
	stamina = maxf(0.0, stamina - t.whip_stamina_cost)
	_whip_cd = t.whip_cooldown
	if stamina <= 0.0:
		_exhausted_t = t.exhausted_delay
	add_effect(Effects.BOOST, t.whip_duration, strength, slot)


func _steer_from(input: ChariotInput, stunned: bool) -> float:
	var t := tuning
	if stunned or has_effect(Effects.NO_STEER):
		return 0.0
	var s := input.steer
	if has_effect(Effects.REVERSE_STEER):
		s = -s
	if has_effect(Effects.DRUNK):
		s += sin(_sim_time * TAU * t.drunk_freq) * t.drunk_wobble * effect_strength(Effects.DRUNK)
	if has_effect(Effects.SHAKE):
		s *= lerpf(1.0, t.shake_steer_mult, clampf(effect_strength(Effects.SHAKE), 0.0, 1.0))
	if has_effect(Effects.BARBED):
		s *= t.barbed_steer_mult
	var both := ChariotSnapshot.WHEEL_LEFT | ChariotSnapshot.WHEEL_RIGHT
	if wheel_state != 0 and wheel_state != both:
		s *= t.limp_steer_mult
		s += -t.limp_pull if wheel_state == ChariotSnapshot.WHEEL_LEFT else t.limp_pull # pulls to the broken side
	return clampf(s, -1.0, 1.0)


func _top_speed() -> float:
	var t := tuning
	var top := t.max_speed * t.speed_mult_for(surface)
	var both := ChariotSnapshot.WHEEL_LEFT | ChariotSnapshot.WHEEL_RIGHT
	if wheel_state != 0 and wheel_state != both:
		top *= t.limp_speed_mult
	if has_effect(Effects.SLOW):
		top *= 1.0 - 0.5 * clampf(effect_strength(Effects.SLOW), 0.0, 1.0)
	if has_effect(Effects.TANGLED):
		top *= t.tangled_speed_mult
	if has_effect(Effects.BARBED):
		top *= t.barbed_speed_mult
	if stamina < t.tired_threshold:
		top *= lerpf(t.tired_speed_mult, 1.0, stamina / maxf(t.tired_threshold, 0.01))
	if has_effect(Effects.BOOST):
		top += t.whip_boost * effect_strength(Effects.BOOST)
	if wheel_state == both:
		top = minf(top, t.crawl_speed)
	return maxf(top, 0.5)


## New forward speed after thrust, brake/reverse, coasting drag and the top-speed cap.
func _drive(speed: float, input: ChariotInput, stunned: bool, delta: float) -> float:
	var t := tuning
	var top := _top_speed()
	var thrust := t.horse_thrust
	if has_effect(Effects.BOOST):
		thrust *= 1.0 + t.whip_thrust_mult * effect_strength(Effects.BOOST)
	if has_effect(Effects.TANGLED):
		thrust *= t.tangled_speed_mult
	var throttle := 0.0 if stunned else input.throttle
	var brake := 0.0 if stunned else input.brake
	var a := 0.0
	if throttle > 0.0 and speed < top:
		var r := clampf(maxf(speed, 0.0) / top, 0.0, 1.0)
		a += throttle * thrust * (1.0 - r * r * r * r) # fades out near top speed
	if brake > 0.0:
		if speed > 0.5:
			a -= brake * t.brake_decel
		elif speed > -t.reverse_speed:
			a -= brake * thrust * 0.4
	a -= t.drag * speed * (1.0 - throttle)
	var s := speed + a * delta
	if s > top:
		s = maxf(top, minf(s, speed - t.overspeed_decel * delta))
	return maxf(s, -t.reverse_speed)


## Sideways speed change that grip removes this tick (same sign as slip). Capped: over the cap it slides.
static func _grip_delta(slip: float, grip: float, rate: float, max_accel: float, delta: float) -> float:
	var mag := minf(absf(slip) * clampf(grip * rate * delta, 0.0, 1.0), grip * max_accel * delta)
	return signf(slip) * mag


## Cart on the hitch: grip at the axle, hitch spring/damper, jackknife. Also pulls the horses.
func _step_cart(cart_surface: StringName, delta: float) -> void:
	var t := tuning
	var length := t.hitch_length
	var cr := _cart_right()
	var omega := _yaw_rate + cart_ang_vel # cart yaw speed in the world
	if grounded:
		var slip := _hitch_velocity().dot(cr) + omega * length # sideways speed of the axle
		var dv := _grip_delta(slip, t.grip_for(cart_surface), t.cart_grip_rate, t.cart_max_lat_accel, delta)
		var share := t.cart_pull * t.cart_mass / t.total_mass()
		omega -= dv * (1.0 - share) / length
		velocity -= cr * dv * share
	cart_ang_vel = omega - _yaw_rate
	var spring := -t.hitch_stiffness * cart_angle - t.hitch_damping * cart_ang_vel
	cart_ang_vel += spring / t.cart_mass * delta
	# The hitch twists the horses the other way: a cart swinging out drags their heading (spin-outs).
	var yank := -spring * t.hitch_yank * t.cart_mass / t.horse_mass * delta
	_yaw_rate += yank
	cart_ang_vel -= yank # the cart's world yaw is unchanged; only the horses turned
	cart_angle += cart_ang_vel * delta
	if absf(cart_angle) > t.jackknife_angle:
		cart_angle = signf(cart_angle) * t.jackknife_angle
		if absf(cart_ang_vel) > 1.0: # a real slam, not resting against the stop
			velocity.x *= 1.0 - t.jackknife_speed_loss
			velocity.z *= 1.0 - t.jackknife_speed_loss
		cart_ang_vel = -cart_ang_vel * t.bounce


func _move_horses(delta: float) -> void:
	_depenetrate()
	var motion := _flat(velocity) * delta
	for i in 3:
		if motion.length_squared() < 1e-10:
			break
		var c := _cast(_horse_shape, _horse_body.global_transform, motion)
		if c.is_empty():
			global_position += motion
			break
		var safe: float = c["safe"]
		global_position += motion * safe
		var n := _flat_normal(c["normal"])
		if n == Vector3.ZERO:
			global_position += motion * (1.0 - safe)
			break
		_resolve_horses(c["collider"], n)
		var rest := motion * (1.0 - safe)
		motion = rest - n * minf(rest.dot(n), 0.0) # slide along what we hit
	global_position.y += velocity.y * delta


func _follow_ground() -> void:
	var gy := _ground_height(global_position)
	if grounded:
		var gap := global_position.y - gy
		if velocity.y <= 0.01 and gap < GROUND_SNAP and gap > -GROUND_SNAP * 2.0:
			global_position.y = gy
			velocity.y = 0.0
		else:
			grounded = false # drove off a ledge
	elif velocity.y <= 0.0 and global_position.y <= gy:
		global_position.y = gy
		var fall := -velocity.y
		velocity.y = 0.0
		grounded = true
		if fall > tuning.hard_landing_speed: # land safely, just lose some speed and wobble the cart
			velocity *= 1.0 - tuning.landing_speed_loss
			cart_ang_vel += signf(cart_angle + 0.01) * fall * 0.1


func _check_cart_contact(old_axle: Vector3, old_cart_xf: Transform3D) -> void:
	var motion := _flat(cart_global_position() - old_axle)
	var c := _cast(_cart_shape, old_cart_xf, motion)
	if c.is_empty():
		return
	var n := _flat_normal(c["normal"])
	if n != Vector3.ZERO:
		_resolve_cart(c["collider"], n)


func _resolve_horses(collider: Object, n: Vector3) -> void:
	var other := find_chariot(collider as Node)
	var impact := 0.0
	if other and other != self:
		var rel := (_flat(velocity) - _flat(other.velocity)).dot(n)
		if rel < 0.0:
			var m1 := tuning.total_mass()
			var m2 := other.tuning.total_mass()
			var j := -(1.0 + tuning.bounce) * rel / (1.0 / m1 + 1.0 / m2)
			velocity += n * (j / m1)
			other.velocity -= n * (j / m2)
			impact = -rel
	else:
		var vn := _flat(velocity).dot(n)
		if vn < 0.0:
			velocity -= n * vn * (1.0 + tuning.bounce)
			impact = -vn
	_report(&"horses", collider, impact, other)


func _resolve_cart(collider: Object, n: Vector3) -> void:
	var cr := _cart_right()
	var omega := _yaw_rate + cart_ang_vel
	var v_axle := _hitch_velocity() + cr * omega * tuning.hitch_length
	var other := find_chariot(collider as Node)
	if other == self:
		return
	if other:
		v_axle -= _flat(other.velocity)
	var vn := v_axle.dot(n)
	if vn >= 0.0:
		return
	var corr := -(1.0 + tuning.bounce) * vn
	var lat := n.dot(cr)
	cart_ang_vel += corr * lat / tuning.hitch_length # sideways part swings the cart back
	velocity += (n - cr * lat) * corr * tuning.cart_mass / tuning.total_mass() # along-pole part pushes the horses
	if other:
		other.velocity -= n * corr * tuning.cart_mass / other.tuning.total_mass()
	_report(&"cart", collider, -vn, other)


## Emit hit() (and the other chariot's hit, and the item's chariot_hit). NET: host only.
func _report(part: StringName, collider: Object, impact: float, other: Chariot) -> void:
	if impact < tuning.hit_min_speed or not multiplayer.is_server() or not collider is Node:
		return
	var id := collider.get_instance_id()
	if _hit_cd.has(id):
		return
	_hit_cd[id] = HIT_COOLDOWN
	hit.emit(part, collider, impact)
	var item := Item.find_item(collider)
	if item:
		item.chariot_hit(self, part, impact)
	if other and other != self:
		var my_body: Node = _cart_body if part == &"cart" else _horse_body
		other._hit_by(other.part_of(collider), my_body, impact)


func _hit_by(part: StringName, body: Node, impact: float) -> void:
	var id := body.get_instance_id()
	if _hit_cd.has(id):
		return
	_hit_cd[id] = HIT_COOLDOWN
	hit.emit(part, body, impact)


func _depenetrate() -> void:
	var space := get_world_3d().direct_space_state
	var q := _query(_horse_shape, _horse_body.global_transform)
	if space.collide_shape(q, 1).is_empty():
		return
	var info := space.get_rest_info(q)
	var n := _flat_normal(info.get("normal", Vector3.ZERO))
	if n != Vector3.ZERO:
		global_position += n * 0.05


## Shape cast. Returns {} when free, else get_rest_info() at the contact + "safe" (0..1) + "collider".
func _cast(shape: CollisionShape3D, body_xf: Transform3D, motion: Vector3) -> Dictionary:
	if motion.length_squared() < 1e-10:
		return {}
	var space := get_world_3d().direct_space_state
	var q := _query(shape, body_xf)
	q.motion = motion
	var r := space.cast_motion(q)
	if r[0] >= 1.0:
		return {}
	q.transform.origin += motion * r[1]
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	if info.is_empty():
		return {}
	var collider := instance_from_id(info["collider_id"])
	if collider == null:
		return {}
	info["safe"] = r[0]
	info["collider"] = collider
	return info


func _query(shape: CollisionShape3D, body_xf: Transform3D) -> PhysicsShapeQueryParameters3D:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape.shape
	q.transform = body_xf * shape.transform
	# WHY: the ground is handled by _follow_ground(); the boxes sit above it, so skip WORLD in side casts.
	q.collision_mask = COLLIDE_MASK & ~Layers.WORLD
	q.exclude = _own_rids
	return q


func _ground_height(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.DOWN * 60.0, Layers.WORLD, _own_rids)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return (r["position"] as Vector3).y if not r.is_empty() else -INF


func _surface_at(p: Vector3) -> StringName:
	return track.surface_at(p) if track else Surface.NORMAL


## Unit vector from the hitch towards the axle (world, flat).
func _cart_back() -> Vector3:
	var psi := global_rotation.y + cart_angle
	return Vector3(sin(psi), 0.0, cos(psi))


## Cart's right (world, flat).
func _cart_right() -> Vector3:
	var psi := global_rotation.y + cart_angle
	return Vector3(cos(psi), 0.0, -sin(psi))


## Flat world velocity of the hitch point (horse velocity + their yaw swinging the hitch).
func _hitch_velocity() -> Vector3:
	var r := global_basis.z * HITCH_OFFSET
	return _flat(velocity) + Vector3(_yaw_rate * r.z, 0.0, -_yaw_rate * r.x)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _flat_normal(n: Vector3) -> Vector3:
	n.y = 0.0
	return n.normalized() if n.length() > 0.2 else Vector3.ZERO


## Move the cart nodes, then push both body transforms to the physics server now (not at frame end), so
## the next chariot's casts this tick see where we really are.
func _sync_bodies() -> void:
	_update_cart_visual()
	for b: AnimatableBody3D in [_horse_body, _cart_body]:
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, b.global_transform)


func _update_cart_visual() -> void:
	if not is_node_ready():
		return
	var length := tuning.hitch_length
	_cart.rotation.y = cart_angle
	_cart_body.position.z = length
	if _cart_model:
		_cart_model.position.z = length
	if _pole:
		_pole.scale.z = maxf(0.1, length - POLE_FRONT)


# ---------------------------------------------------------------- visuals (every peer, never gameplay)

func _process(delta: float) -> void:
	if _tint.material_override != _team_mat:
		_team_mat = _tint.material_override
		for e: Array in _team_surfaces:
			(e[0] as MeshInstance3D).set_surface_override_material(e[1], _team_mat)
	var speed := get_speed()
	_wheel_spin = fmod(_wheel_spin + speed / WHEEL_RADIUS * delta, TAU)
	if _wheel_l:
		_wheel_l.rotation.x = -_wheel_spin
		_wheel_l.visible = wheel_state & ChariotSnapshot.WHEEL_LEFT == 0
	if _wheel_r:
		_wheel_r.rotation.x = -_wheel_spin
		_wheel_r.visible = wheel_state & ChariotSnapshot.WHEEL_RIGHT == 0
	if _cart_model:
		var tilt := 0.0
		if wheel_state == ChariotSnapshot.WHEEL_LEFT:
			tilt = 0.14
		elif wheel_state == ChariotSnapshot.WHEEL_RIGHT:
			tilt = -0.14
		_cart_model.rotation.z = tilt
		_cart_model.position.y = -0.4 if wheel_state == 3 else 0.0
	# Pull cues (from motion only, so clients see them too): horses lunge ahead and dig in when they
	# accelerate, sit back when braking, lean into turns, gallop harder while pulling.
	if delta > 0.0:
		var yaw := global_rotation.y
		var k := clampf(8.0 * delta, 0.0, 1.0)
		_vis_acc = lerpf(_vis_acc, (speed - _vis_speed) / delta, k)
		_vis_turn = lerpf(_vis_turn, wrapf(yaw - _vis_yaw, -PI, PI) / delta, k)
		_vis_speed = speed
		_vis_yaw = yaw
	var pull := clampf(_vis_acc / 8.0, -1.0, 1.0)
	if _horse_model:
		_horse_model.position.z = -pull * 0.3
		_horse_model.rotation.x = -pull * 0.08
		_horse_model.rotation.z = clampf(_vis_turn * absf(speed) * 0.012, -0.22, 0.22)
	var gait := clampf(absf(speed) / 6.0, 0.0, 1.0) if grounded else 0.0
	gait *= 1.0 + maxf(pull, 0.0) * 0.8
	_gallop = fmod(_gallop + absf(speed) * delta * 0.45, 2.0)
	for i in 2:
		var h := _horse_l if i == 0 else _horse_r
		if h:
			var ph := (_gallop + i * 0.4) * PI
			h.position.y = absf(sin(ph)) * 0.09 * gait
			h.rotation.x = sin(ph * 2.0) * 0.05 * gait - maxf(pull, 0.0) * 0.12


func _collect_team_surfaces() -> void:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name == "TeamColor":
				_team_surfaces.append([mi, i])
