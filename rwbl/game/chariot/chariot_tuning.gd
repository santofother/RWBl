class_name ChariotTuning
extends Resource
## Every chariot gameplay number (DESIGN §4 tuning list). Owner: C04. Default: `chariot/default_tuning.tres`.
## The F2 panel (TuningPanel) edits every `@export_range` float/int here live and saves the .tres.
## NET: the host's copy is the one that matters (host simulates); clients use it for prediction only.
## Public API: exported fields, `grip_for()`, `speed_mult_for()`, `total_mass()`.
# CONTRACT: tuning resources use @export_range so TuningPanel can build sliders. Field set is C04's to change,
#   but `grip_for()` / `speed_mult_for()` are read by other cards.

@export_group("Horses")
@export_range(0.0, 80.0) var horse_thrust := 10.0 # TUNE: m/s² at full throttle (fades out near top speed)
@export_range(1.0, 60.0) var max_speed := 22.0 # TUNE: m/s
@export_range(0.0, 80.0) var brake_decel := 25.0 # TUNE: m/s²
@export_range(0.0, 15.0) var reverse_speed := 5.0 # TUNE: m/s, brake held while stopped
@export_range(0.0, 5.0) var drag := 0.4 # TUNE: per second, only while off the throttle (coasting)
@export_range(0.0, 40.0) var overspeed_decel := 10.0 # TUNE: m/s² back down to top speed after a boost
@export_range(0.0, 6.0) var steer_rate := 1.9 # TUNE: rad/s at full lock
@export_range(0.5, 20.0) var steer_full_speed := 5.0 # TUNE: m/s at which steering reaches full strength
@export_range(0.5, 20.0) var steer_response := 5.0 # TUNE: how fast the horses ease into a turn (1/s)
@export_range(0.0, 1.0) var steer_at_top_speed := 0.55 # TUNE: steering multiplier at max speed
@export_range(0.0, 30.0) var horse_grip_rate := 6.0 # TUNE: how fast hooves kill sideways slip (1/s)
@export_range(0.0, 80.0) var horse_max_lat_accel := 12.0 # TUNE: m/s², over this the chariot drifts
@export_range(0.0, 3.0) var drift_scrub := 0.35 # TUNE: speed lost per s while sliding sideways (x sin slip)
@export_group("Cart")
@export_range(0.5, 6.0) var hitch_length := 2.0 # TUNE: m, hitch point to cart axle
@export_range(0.0, 40.0) var hitch_stiffness := 6.0 # TUNE: spring pulling the cart back in line
@export_range(0.0, 20.0) var hitch_damping := 1.2 # TUNE: damper on the cart swing
@export_range(0.1, 10.0) var cart_mass := 1.2 # TUNE: heavier cart = lazier swing
@export_range(0.1, 10.0) var horse_mass := 2.0 # TUNE: also divides apply_impulse()
@export_range(0.0, 30.0) var cart_grip_rate := 6.0 # TUNE: how fast wheels kill sideways slip (1/s)
@export_range(0.0, 80.0) var cart_max_lat_accel := 8.0 # TUNE: m/s², over this the cart slides (fishtail)
@export_range(0.0, 1.0) var cart_pull := 0.8 # TUNE: how much a sliding cart yanks the horses
@export_range(0.0, 1.0) var cart_drag := 0.15 # TUNE: how much a sliding cart brakes the horses
@export_range(0.0, 5.0) var hitch_yank := 1.5 # TUNE: how hard a swinging cart twists the horses (spin-outs)
@export_range(0.5, 3.0) var jackknife_angle := 1.75 # TUNE: rad, cart hits the horses here
@export_range(0.0, 1.0) var jackknife_speed_loss := 0.5 # TUNE: fraction of speed lost on a jackknife
@export_group("Grip per surface")
@export_range(0.0, 2.0) var grip_normal := 1.0 # TUNE
@export_range(0.0, 2.0) var grip_oil := 0.05 # TUNE
@export_range(0.0, 2.0) var grip_mud := 0.8 # TUNE
@export_range(0.0, 2.0) var grip_ice := 0.1 # TUNE
@export_range(0.0, 2.0) var grip_gravel := 0.7 # TUNE
@export_range(0.0, 2.0) var grip_offtrack := 0.6 # TUNE
@export_group("Speed per surface")
@export_range(0.0, 1.5) var speed_mud := 0.5 # TUNE: top speed multiplier
@export_range(0.0, 1.5) var speed_gravel := 0.85 # TUNE
@export_range(0.0, 1.5) var speed_offtrack := 0.6 # TUNE
@export_group("Whip")
@export_range(0.0, 30.0) var whip_boost := 8.0 # TUNE: extra top speed m/s
@export_range(0.0, 3.0) var whip_thrust_mult := 0.8 # TUNE: extra thrust while boosting (x strength)
@export_range(0.0, 3.0) var whip_duration := 0.8 # TUNE: s
@export_range(0.0, 1.0) var whip_stamina_cost := 0.3 # TUNE: of 1.0
@export_range(0.0, 3.0) var whip_cooldown := 0.6 # TUNE: s
@export_range(0.0, 1.0) var stamina_regen := 0.15 # TUNE: per s
@export_range(0.0, 1.0) var tired_threshold := 0.35 # TUNE: below this the boost is weaker, horses slower
@export_range(0.0, 1.0) var tired_speed_mult := 0.8 # TUNE: top speed at 0 stamina
@export_range(0.0, 5.0) var exhausted_delay := 1.5 # TUNE: s without regen after stamina hits 0
@export_group("Jump")
@export_range(0.0, 20.0) var jump_speed := 7.5 # TUNE: m/s up (≈1.1 m high, ≈0.6 s in the air)
@export_range(0.0, 3.0) var jump_cooldown := 0.8 # TUNE: s between jumps
@export_range(0.0, 1.0) var jump_stamina_cost := 0.1 # TUNE: of 1.0 (shares the whip's stamina)
@export_range(0.0, 1.0) var air_steer := 0.35 # TUNE: steering in the air (pre-rotate for the landing)
@export_group("Air")
@export_range(0.0, 60.0) var gravity := 25.0 # TUNE: m/s² (arcade, heavier than 9.8)
@export_range(0.0, 1.0) var landing_speed_loss := 0.15 # TUNE: on a hard landing
@export_range(0.0, 20.0) var hard_landing_speed := 6.0 # TUNE: m/s down
@export_group("Loop")
## C21: inside a loop the road holds the chariot (surface gravity) while it is faster than this; slower with the
## road past vertical (overhead) and it falls off.
@export_range(0.0, 30.0) var loop_min_speed := 10.0 # TUNE: m/s
@export_range(0.0, 1.0) var loop_slope_gravity := 0.7 # TUNE: share of gravity that slows the climb / speeds the drop (0.7: full speed or a whip makes it; 0.8: only a whip)
@export_range(0.0, 10.0) var loop_steer_speed := 3.0 # TUNE: m/s sideways at full steer inside a loop
@export_range(0.5, 5.0) var loop_fall_time := 2.5 # TUNE: s of falling off a loop before it counts as a crash anyway
@export_group("Collisions")
@export_range(0.0, 1.0) var bounce := 0.3 # TUNE: restitution vs walls and chariots
@export_range(0.0, 10.0) var hit_min_speed := 1.0 # TUNE: m/s, slower touches don't emit hit()
@export_group("Effects")
@export_range(0.0, 1.0) var drunk_wobble := 0.6 # TUNE: steering added by DRUNK
@export_range(0.0, 3.0) var drunk_freq := 0.6 # TUNE: wobbles per second
@export_range(0.0, 1.0) var shake_steer_mult := 0.6 # TUNE: steering under SHAKE
@export_range(0.0, 1.0) var tangled_speed_mult := 0.35 # TUNE: top speed under TANGLED
@export_range(0.0, 1.0) var barbed_speed_mult := 0.85 # TUNE: top speed with BARBED wheels
@export_range(0.0, 1.0) var barbed_steer_mult := 0.75 # TUNE
@export_group("Damage")
@export_range(0.0, 1.0) var limp_steer_mult := 0.6 # TUNE: one wheel lost
@export_range(0.0, 1.0) var limp_speed_mult := 0.75 # TUNE
@export_range(0.0, 0.5) var limp_pull := 0.12 # TUNE: steering pull toward the broken side
@export_range(0.0, 10.0) var crawl_speed := 3.0 # TUNE: both wheels lost, m/s


## Lateral grip for a Surface name (1 = normal).
func grip_for(surface: StringName) -> float:
	match surface:
		Surface.OIL: return grip_oil
		Surface.MUD: return grip_mud
		Surface.ICE: return grip_ice
		Surface.GRAVEL: return grip_gravel
		Surface.OFFTRACK: return grip_offtrack
	return grip_normal


## Top speed multiplier for a Surface name.
func speed_mult_for(surface: StringName) -> float:
	match surface:
		Surface.MUD: return speed_mud
		Surface.GRAVEL: return speed_gravel
		Surface.OFFTRACK: return speed_offtrack
	return 1.0


## Horses + cart, used for chariot-vs-chariot pushes.
func total_mass() -> float:
	return horse_mass + cart_mass
