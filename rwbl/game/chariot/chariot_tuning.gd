class_name ChariotTuning
extends Resource
## Every chariot gameplay number (DESIGN §4 tuning list). Owner: C04. Default: `chariot/default_tuning.tres`.
## The F2 panel (TuningPanel) edits every `@export_range` float/int here live and saves the .tres.
## NET: the host's copy is the one that matters (host simulates); clients use it for prediction only.
## Public API: exported fields, `grip_for()`, `speed_mult_for()`.
# CONTRACT: tuning resources use @export_range so TuningPanel can build sliders. Field set is C04's to change.

@export_group("Horses")
@export_range(0.0, 80.0) var horse_thrust := 18.0 # TUNE: m/s² at full throttle
@export_range(1.0, 60.0) var max_speed := 22.0 # TUNE: m/s
@export_range(0.0, 80.0) var brake_decel := 25.0 # TUNE
@export_range(0.0, 5.0) var drag := 0.4 # TUNE: per second, proportional to speed
@export_range(0.0, 6.0) var steer_rate := 2.2 # TUNE: rad/s at full lock
@export_group("Cart")
@export_range(0.5, 6.0) var hitch_length := 2.4 # TUNE: m
@export_range(0.0, 40.0) var hitch_stiffness := 8.0 # TUNE
@export_range(0.1, 10.0) var cart_mass := 1.0 # TUNE
@export_range(0.1, 10.0) var horse_mass := 2.0 # TUNE
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
@export_range(0.0, 3.0) var whip_duration := 0.8 # TUNE: s
@export_range(0.0, 1.0) var whip_stamina_cost := 0.3 # TUNE: of 1.0
@export_range(0.0, 3.0) var whip_cooldown := 0.6 # TUNE: s
@export_range(0.0, 1.0) var stamina_regen := 0.15 # TUNE: per s
@export_group("Damage")
@export_range(0.0, 1.0) var limp_steer_mult := 0.6 # TUNE: one wheel lost
@export_range(0.0, 1.0) var limp_speed_mult := 0.75 # TUNE
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
