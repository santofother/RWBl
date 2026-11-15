class_name ItemTuning
extends Resource
## Gameplay numbers of the wave 2 items (C10). Default values: `item_tuning.tres`; editable live in the F2
## panel ("Items"). Wave 4 item cards add their own fields at the end. Owner: C10.
## NET: host reads them (effects are host side), except the axe swing which every peer reads.
## Public API: exported fields.

@export_group("Ice")
@export_range(0.05, 1.0) var ice_no_steer_refresh := 0.15 # TUNE: NO_STEER lasts this long after leaving, s
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
