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
## Jump (input.jump): hop ~1 m on a cooldown for a little stamina; steering is weak (`air_steer`) in the air.
## Loops (C21): inside a Track loop zone the chariot rides the road surface (surface gravity, `on_loop`): position
##   = road point at its progress + lateral offset, basis = road frame (upside down at the top), speed from the
##   usual thrust/drag plus `loop_slope_gravity` along the climb; steering only slides it sideways. Slower than
##   `loop_min_speed` with the road past ~70° (overhead) it falls off, tumbles and dies on landing (cause
##   &"loop_fall"). Leaving the zone puts it back on flat-road physics. The cart pitches to follow the road.
## Slopes (C20): the wheels follow the road's height and normal (ground ray). Gravity along the road slows a
##   climb and speeds a descent (`slope_gravity`; downhill the top speed rises, `downhill_top_gain`), a tilted
##   road gives extra sideways grip (`bank_grip`, banked turns). Grounded, the vertical speed is the road's climb
##   rate; where the road drops away faster than gravity can pull the chariot down (a crest taken fast) it lifts
##   off (more than `launch_gap` above the road = airborne) and lands further on. The body stays level (yaw only);
##   the horse and cart models pitch / roll with the road (visual, every peer).
##   vars `slot`, `tuning`, `track`, `velocity`, `stamina`, `wheel_state`, `dead`, `frozen`, `cart_angle`,
##   `cart_ang_vel`, `grounded`, `surface`, `on_loop` (C21)
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
## C21: road normal's y below which a too-slow chariot falls off a loop (~70° up the wall and beyond).
const LOOP_FALL_UP := 0.35
## C20: the ground ray starts this far above the horses, m.
const RAY_UP := 2.5

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
## C21: true while riding a loop's road surface. NET: host / predicting owner (clients see the tilted basis).
var on_loop := false

var _effects: Dictionary = {} # StringName -> [time_left, strength, source_slot]
var _whip_cd := 0.0
var _jump_cd := 0.0
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
var _loop_fall := false # C21: fell off a loop, tumbling until it lands (dies)
var _fall_t := 0.0
var _cart_pitch := 0.0 # C21: visual, cart tilts along the loop's road
var _ground_n := Vector3.UP # C20: road normal under the horses at the last ground check
var _slope_acc := 0.0 # C20: m/s² along the heading from gravity on the slope (+ = downhill), this tick
var _bank_lat := 0.0 # C20: extra sideways grip accel on a tilted road, this tick
var _vis_pitch := 0.0 # C20: visual pitch / roll of the models on slopes and banks
var _vis_roll := 0.0
var _vis_cart_pitch := 0.0

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
	_slope_acc = 0.0
	_bank_lat = 0.0
	if dead or frozen:
		velocity = Vector3.ZERO
		cart_ang_vel = 0.0
		_yaw_rate = 0.0
		_sync_bodies()
		return
	_try_whip(input)
	if _loop_fall:
		_step_loop_fall(delta)
		_sync_bodies()
		return
	if not on_loop and grounded and track and track.has_loops() \
			and track.loop_index_at(track.progress_at(global_position)) >= 0:
		on_loop = true
	if on_loop:
		_step_loop(input, delta)
		_sync_bodies()
		return
	_try_jump(input)
	var t := tuning
	surface = _surface_at(global_position)
	var cart_surface := _surface_at(cart_global_position())
	var old_axle := cart_global_position()
	var old_cart_xf := _cart_body.global_transform
	var stunned := has_effect(Effects.STUN)

	if grounded:
		_slope_from_ground()
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
		# In the air the horses can still twist a little (air_steer): line up the landing.
		var air := -_steer_from(input, stunned) * t.steer_rate * t.air_steer
		_yaw_rate = move_toward(_yaw_rate, air, t.steer_rate * t.steer_response * delta)
	rotate_y(_yaw_rate * delta)
	if grounded:
		# WHY: velocity keeps its old direction after the turn; grip below swings it in line. Low grip = slide.
		var fwd := get_forward()
		var prev_speed := _flat(velocity).length()
		var speed := _flat(velocity).dot(fwd)
		velocity += fwd * (_drive(speed, input, stunned, delta) - speed)
		_apply_grip(fwd, prev_speed, delta)
	# C20: gravity always pulls; on the road _follow_ground() puts the wheels back on it (or lets a crest launch)
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
	var was_dead := dead
	dead = _flags & ChariotSnapshot.FLAG_DEAD != 0
	if dead != was_dead:
		_set_solid(not dead)
	if dead: # C21: a predicting owner forgets its own loop state once the host says it died
		on_loop = false
		_loop_fall = false
	frozen = _flags & ChariotSnapshot.FLAG_FROZEN != 0
	grounded = absf(velocity.y) < 0.01 or global_basis.y.y < 0.99 # C21: on a loop the velocity climbs
	if not grounded and track and track.has_height(): # C20: on a slope the velocity climbs too
		grounded = global_position.y - _ground_height(global_position) < tuning.launch_gap + 0.05
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
	on_loop = false
	_loop_fall = false
	_set_solid(false)
	died.emit(cause, source_slot, item_uid)


## Place the chariot at `xform`, repaired, rested and alive. NET: host (clients follow by snapshot).
## C20: the body is kept level (only the heading of `xform` is used), so a respawn on a slope is fine.
func respawn(xform: Transform3D) -> void:
	var f := -xform.basis.z
	f.y = 0.0
	if f.length_squared() > 0.01 and xform.basis.y.y > 0.0:
		xform.basis = Basis.looking_at(f.normalized(), Vector3.UP)
	global_transform = xform
	velocity = Vector3.ZERO
	cart_angle = 0.0
	cart_ang_vel = 0.0
	wheel_state = 0
	stamina = 1.0
	_exhausted_t = 0.0
	_whip_cd = 0.0
	_jump_cd = 0.0
	_yaw_rate = 0.0
	grounded = true
	dead = false
	on_loop = false
	_loop_fall = false
	_cart_pitch = 0.0
	_ground_n = Vector3.UP
	_set_solid(true)
	_effects.clear()
	_hit_cd.clear()
	_sync_bodies()
	respawned.emit()


## Dead chariots are ghosts: other chariots and item triggers pass through them (C12). Any peer.
func _set_solid(on: bool) -> void:
	if _horse_body == null:
		return
	_horse_body.collision_layer = Layers.HORSES if on else 0
	_cart_body.collision_layer = Layers.CART if on else 0


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
	_jump_cd = maxf(0.0, _jump_cd - delta)
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


## Jump: hop the whole chariot (DESIGN §4, user-approved). Needs ground, a free cooldown, some stamina and at
## least one wheel; stunned horses can't jump. While airborne, surfaces (oil, mud) don't touch the wheels.
func _try_jump(input: ChariotInput) -> void:
	var t := tuning
	if not input.jump or not grounded or _jump_cd > 0.0 or has_effect(Effects.STUN) \
			or has_effect(Effects.TANGLED) or stamina < t.jump_stamina_cost \
			or wheel_state == ChariotSnapshot.WHEEL_LEFT | ChariotSnapshot.WHEEL_RIGHT:
		return
	stamina -= t.jump_stamina_cost
	_jump_cd = t.jump_cooldown
	velocity.y = t.jump_speed
	grounded = false


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
	if _slope_acc > 0.0: # C20: downhill the horses run away with the cart
		top += _slope_acc * t.downhill_top_gain
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
	a += _slope_acc # C20: uphill slows, downhill speeds up (and weakens the brake)
	var s := speed + a * delta
	if s > top:
		s = maxf(top, minf(s, speed - t.overspeed_decel * delta))
	return maxf(s, -t.reverse_speed)


## Sideways speed change that grip removes this tick (same sign as slip). Capped: over the cap it slides.
static func _grip_delta(slip: float, grip: float, rate: float, max_accel: float, delta: float) -> float:
	var mag := minf(absf(slip) * clampf(grip * rate * delta, 0.0, 1.0), grip * max_accel * delta)
	return signf(slip) * mag


## Hooves swing the velocity toward the horses' heading, keeping its speed, but only as fast as the grip's
## max sideways accel allows. Past that the chariot drifts: it slides at an angle and loses just a little
## speed (`drift_scrub`), so you carry momentum through a slide and power out of it.
func _apply_grip(fwd: Vector3, prev_speed: float, delta: float) -> void:
	var t := tuning
	var flat := _flat(velocity)
	var spd := flat.length()
	var grip := t.grip_for(surface)
	if spd < 0.5:
		flat = fwd * flat.dot(fwd) # parked: no sideways creep
	else:
		var aim := fwd if flat.dot(fwd) >= 0.0 else -fwd
		var slip := flat.signed_angle_to(aim, Vector3.UP)
		var turn := minf(absf(slip) * clampf(grip * t.horse_grip_rate * delta, 0.0, 1.0),
			(grip * t.horse_max_lat_accel + _bank_lat) / spd * delta)
		flat = flat.rotated(Vector3.UP, signf(slip) * turn)
		flat *= 1.0 - clampf(t.drift_scrub * grip * absf(sin(slip)) * delta, 0.0, 1.0)
		var cap := maxf(_top_speed(), prev_speed) # throttle mid-drift must not push past top speed
		if flat.length() > cap:
			flat = flat.normalized() * cap
	velocity.x = flat.x
	velocity.z = flat.z


## Cart on the hitch: grip at the axle, hitch spring/damper, jackknife. Also pulls the horses.
func _step_cart(cart_surface: StringName, delta: float) -> void:
	var t := tuning
	var length := t.hitch_length
	var cr := _cart_right()
	var omega := _yaw_rate + cart_ang_vel # cart yaw speed in the world
	if grounded:
		var slip := _hitch_velocity().dot(cr) + omega * length # sideways speed of the axle
		var cg := t.grip_for(cart_surface)
		var dv := _grip_delta(slip, cg, t.cart_grip_rate, t.cart_max_lat_accel + _bank_lat / maxf(cg, 0.05), delta)
		var share := t.cart_pull * t.cart_mass / t.total_mass()
		omega -= dv * (1.0 - share) / length
		# WHY: a sliding cart yanks the horses sideways but barely brakes them (drifts keep momentum).
		var push := cr * dv * share
		var fwd := get_forward()
		velocity -= push - fwd * push.dot(fwd) * (1.0 - t.cart_drag)
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


## C21: one tick riding a loop. Stateless apart from `on_loop`: progress, lateral offset and speed are read back
## from the transform and velocity, so prediction corrections on a client just work. NET: host / owner prediction.
func _step_loop(input: ChariotInput, delta: float) -> void:
	var t := tuning
	surface = Surface.NORMAL
	grounded = true
	var s := track.progress_at(global_position)
	var zi := track.loop_index_at(s)
	var xf := track.road_transform_at(s)
	var u := (global_position - xf.origin).dot(xf.basis.x)
	var fwd := -xf.basis.z
	var v := velocity.dot(fwd)
	var stunned := has_effect(Effects.STUN)
	v = _drive(v, input, stunned, delta)
	v -= t.gravity * t.loop_slope_gravity * fwd.y * delta # climbing slows, the way down speeds up
	var half := track.track_width * 0.5 - 1.5
	u = clampf(u + _steer_from(input, stunned) * t.loop_steer_speed * delta, -half, half)
	s += v * delta
	_yaw_rate = 0.0
	cart_ang_vel = 0.0
	cart_angle = move_toward(cart_angle, 0.0, 2.0 * delta)
	if zi < 0:
		_leave_loop(s, u, v)
		return
	var z: Vector2 = track.loop_zones()[zi]
	if s >= z.y:
		_leave_loop(z.y + 0.05, u, v)
		return
	if s <= z.x:
		_leave_loop(z.x - 0.05, u, v)
		return
	xf = track.road_transform_at(s)
	if xf.basis.y.y < LOOP_FALL_UP and v < t.loop_min_speed:
		_fall_off_loop(xf, u, v)
		return
	global_transform = Transform3D(xf.basis, xf.origin + xf.basis.x * u)
	velocity = -xf.basis.z * v


## Back on flat-road physics at progress `s`, lateral `u`, speed `v` (negative = rolling back out of the entry).
func _leave_loop(s: float, u: float, v: float) -> void:
	on_loop = false
	var xf := track.transform_at(s)
	global_transform = Transform3D(xf.basis, xf.origin + xf.basis.x * u)
	velocity = -xf.basis.z * v
	velocity.y = 0.0
	grounded = true
	_cart_pitch = 0.0


func _fall_off_loop(xf: Transform3D, u: float, v: float) -> void: # NET: host / owner prediction
	on_loop = false
	_loop_fall = true
	_fall_t = 0.0
	grounded = false
	global_transform = Transform3D(xf.basis, xf.origin + xf.basis.x * u)
	velocity = -xf.basis.z * v
	print("[Chariot] LOOP FALL %d at %.1f m/s" % [slot, v])


## Falling off a loop: ballistic, tumbling, dies on landing (or after loop_fall_time / below FALL_KILL_Y).
func _step_loop_fall(delta: float) -> void:
	_fall_t += delta
	velocity.y -= tuning.gravity * delta
	global_position += velocity * delta
	rotate_object_local(Vector3.RIGHT, 1.5 * delta)
	# WHY: right after letting go the chariot is still under the overhead road; give it a moment to drop clear
	var landed := _fall_t > 0.35 and global_position.y <= _ground_height(global_position) + 0.2
	if landed or _fall_t >= tuning.loop_fall_time or global_position.y < FALL_KILL_Y:
		if multiplayer.is_server():
			kill(&"loop_fall")
		else:
			velocity = Vector3.ZERO # predicting client: wait for the host's death snapshot


## Cart pitch (rad about its local X) that puts the axle back on the loop's road. Visual, any peer.
func _loop_cart_pitch() -> float:
	var s := track.progress_at(global_position)
	var xf := track.road_transform_at(s)
	var u := (global_position - xf.origin).dot(xf.basis.x)
	var q := track.road_transform_at(s - HITCH_OFFSET - tuning.hitch_length)
	var local := global_transform.affine_inverse() * (q.origin + q.basis.x * u)
	return clampf(atan2(-local.y, local.z), -0.9, 0.9)


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


## C20: wheels on the road. Below the road (gravity pulled us into it, or it climbs) -> snap onto it and take its
## climb rate as vertical speed. A little above it -> still grounded, just falling towards it. More than
## `launch_gap` above -> airborne (a crest taken fast, a ledge). Airborne and back down -> land.
func _follow_ground() -> void:
	var hit := _ground_hit(global_position)
	var gy: float = hit[0]
	if grounded:
		var gap := global_position.y - gy
		if gap <= 0.0 and gap > -GROUND_SNAP * 2.0:
			global_position.y = gy
			_ground_n = hit[1]
			velocity.y = _climb_rate(_ground_n)
		elif gap > tuning.launch_gap or gap <= -GROUND_SNAP * 2.0:
			grounded = false # drove off a ledge / flew off a crest
			if velocity.y > 0.5:
				print("[Chariot] LAUNCH %d at %.1f m/s up %.1f" % [slot, _flat(velocity).length(), velocity.y])
	elif velocity.y <= 0.0 and global_position.y <= gy:
		global_position.y = gy
		_ground_n = hit[1]
		var rate := _climb_rate(_ground_n)
		var fall := rate - velocity.y # WHY: landing on a downslope is softer than on the flat
		velocity.y = rate
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
	return _ground_hit(p)[0]


## [height, normal] of the WORLD floor under `p` (-INF, UP if none).
func _ground_hit(p: Vector3) -> Array:
	# WHY (C20): start above the wheels, so a road that climbs past a chariot in the air still catches it. Keep it
	#   under Track.CROSS_CLEARANCE minus a chariot's height (roads passing over each other).
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * RAY_UP, p + Vector3.DOWN * 60.0, Layers.WORLD,
		_own_rids)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return [-INF, Vector3.UP]
	var n: Vector3 = r["normal"]
	if n.y < 0.0: # WHY: backface hit on a two-sided road slab
		n = -n
	var y: float = (r["position"] as Vector3).y
	# C20: on the road use its exact surface; the triangle mesh of a twisting (banked) road has small kinks that
	# would kick fast wheels up. The ray still decides whether there is road under us (edges, gaps, loops).
	if track and track.has_height() and track.is_road_body(r.get("collider")):
		var g := track.road_ground(p)
		if absf(float(g[0]) - y) < 0.4 and (g[1] as Vector3).y > 0.2:
			return g
	return [y, n if n.y > 0.2 else Vector3.UP]


## C20: vertical speed that keeps the wheels on a road with normal `n` at the current flat velocity.
func _climb_rate(n: Vector3) -> float:
	if n.y >= 0.9999:
		return 0.0
	return -(n.x * velocity.x + n.z * velocity.z) / maxf(n.y, 0.2)


## C20: slope gravity along the heading and the bank grip bonus from the last ground normal. NET: host / owner.
func _slope_from_ground() -> void:
	var n := _ground_n
	if n.y >= 0.9999:
		return
	var t := tuning
	var fwd := _flat(get_forward()).normalized()
	var right := fwd.cross(Vector3.UP)
	# WHY: gravity's pull along the road = g × (normal's lean towards the heading); + = downhill ahead
	_slope_acc = t.gravity * t.slope_gravity * n.dot(fwd)
	_bank_lat = t.bank_grip * t.gravity * absf(n.dot(right))


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
	var tilted := global_basis.y.y < 0.999 # C21: on a loop
	_cart_pitch = _loop_cart_pitch() if tilted and not dead and not _loop_fall and track and track.has_loops() \
		else 0.0
	_slope_visual(tilted, delta)
	_cart.rotation.x = _cart_pitch if tilted else _vis_cart_pitch
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
		var turn := 0.0 if tilted else wrapf(yaw - _vis_yaw, -PI, PI) / delta # WHY: euler yaw jumps when upside down
		_vis_turn = lerpf(_vis_turn, turn, k)
		_vis_speed = speed
		_vis_yaw = yaw
	var pull := clampf(_vis_acc / 8.0, -1.0, 1.0)
	if _horse_model:
		_horse_model.position.z = -pull * 0.3
		_horse_model.rotation.x = -pull * 0.08 + _vis_pitch
		_horse_model.rotation.z = clampf(_vis_turn * absf(speed) * 0.012, -0.22, 0.22) + _vis_roll
	var gait := clampf(absf(speed) / 6.0, 0.0, 1.0) if grounded else 0.0
	gait *= 1.0 + maxf(pull, 0.0) * 0.8
	_gallop = fmod(_gallop + absf(speed) * delta * 0.45, 2.0)
	for i in 2:
		var h := _horse_l if i == 0 else _horse_r
		if h:
			var ph := (_gallop + i * 0.4) * PI
			h.position.y = absf(sin(ph)) * 0.09 * gait
			h.rotation.x = sin(ph * 2.0) * 0.05 * gait - maxf(pull, 0.0) * 0.12


## C20: horses pitch / roll with the road under them, the cart pitches so its axle sits on the road. Visual only,
## any peer; only on a course with height (two rays).
func _slope_visual(tilted: bool, delta: float) -> void:
	var p := 0.0
	var r := 0.0
	var cp := 0.0
	if not tilted and not dead and grounded and track and track.has_height() and is_inside_tree():
		var hit := _ground_hit(global_position)
		if float(hit[0]) > -INF and global_position.y - float(hit[0]) < 1.0:
			var n: Vector3 = global_basis.inverse() * (hit[1] as Vector3)
			p = atan2(n.z, n.y) # WHY: normal leaning back (+Z) = road climbs ahead = nose up
			r = -atan2(n.x, n.y)
		var axle := cart_global_position()
		var gy := _ground_height(axle)
		if gy > -INF and absf(gy - global_position.y) < 3.0:
			cp = atan2(global_position.y - gy, HITCH_OFFSET + tuning.hitch_length)
	var k := clampf(12.0 * delta, 0.0, 1.0)
	_vis_pitch = lerpf(_vis_pitch, clampf(p, -0.6, 0.6), k)
	_vis_roll = lerpf(_vis_roll, clampf(r, -0.6, 0.6), k)
	_vis_cart_pitch = lerpf(_vis_cart_pitch, clampf(cp, -0.6, 0.6), k)


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
