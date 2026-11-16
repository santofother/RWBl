class_name ItemTuning
extends Resource
## Gameplay numbers of the wave 2 items (C10). Default values: `item_tuning.tres`; editable live in the F2
## panel ("Items"). Wave 4 item cards add their own fields at the end. Owner: C10.
## NET: host reads them (effects are host side), except the axe swing which every peer reads.
## Public API: exported fields.

@export_group("Ice")
@export_range(0.05, 1.0) var ice_no_steer_refresh := 0.15 # TUNE: NO_STEER lasts this long after leaving, s
@export_range(0.0, 15.0) var ice_steer_below := 4.0 # TUNE: m/s; slower than this you can steer on ice (never trapped)
@export_group("Laurel pad")
@export_range(0.1, 5.0) var pad_boost_time := 1.5 # TUNE: s
@export_range(0.1, 3.0) var pad_boost_strength := 1.0 # TUNE: x whip boost
@export_group("Ramp")
@export_range(0.0, 20.0) var ramp_launch_up := 10.0 # TUNE: m/s upward
@export_range(0.0, 15.0) var ramp_launch_forward := 3.0 # TUNE: m/s extra along the ramp
@export_group("Column")
@export_range(0.0, 5.0) var column_stun := 1.0 # TUNE: s, horse hit
@export_range(0.0, 2.0) var column_push := 0.7 # TUNE: slide speed = impact x this (slide_far only)
@export_range(0.5, 40.0) var column_slide_decel := 10.0 # TUNE: m/s², x rule friction_mult
@export_range(1.0, 100.0) var column_slide_max := 40.0 # TUNE: m
@export_group("Swinging axe")
@export_range(0.5, 8.0) var axe_period := 2.4 # TUNE: s per full swing
@export_range(5.0, 85.0) var axe_swing_deg := 60.0 # TUNE: amplitude
@export_range(0.0, 5.0) var axe_stun := 1.0 # TUNE: s
@export_range(0.0, 20.0) var axe_knockback := 6.0 # TUNE: m/s sideways
@export_group("Chaos items (C25)")
@export_range(0.0, 40.0) var bumper_push := 16.0 # TUNE: m/s shove away from the bumper centre
@export_range(0.0, 3.0) var bumper_stun := 0.3 # TUNE: s of lost control after a bump
@export_range(0.5, 10.0) var dung_drunk_time := 3.0 # TUNE: s of DRUNK wobble after stepping in lion dung
@export_range(0.0, 3.0) var dung_nosteer_time := 0.8 # TUNE: s of no steering after stepping in it
@export_range(0.0, 20.0) var dung_spin_kick := 6.0 # TUNE: m/s sideways shove (the slip)
@export_range(0.0, 40.0) var catapult_up := 14.0 # TUNE: m/s upward lob
@export_range(0.0, 50.0) var catapult_forward := 14.0 # TUNE: m/s extra forward
@export_range(0.0, 3.0) var whirlwind_stun := 0.4 # TUNE: s stun on first contact
@export_range(0.0, 3.0) var whirlwind_drunk_time := 2.0 # TUNE: s of DRUNK refreshed while inside
@export_range(0.0, 60.0) var whirlwind_swirl := 22.0 # TUNE: m/s² sideways swirl push while inside
@export_range(0.0, 20.0) var whirlwind_lift := 3.0 # TUNE: m/s upward hop on first contact
@export_range(0.5, 10.0) var spikelog_period := 3.0 # TUNE: s per full turn of the spiked log
