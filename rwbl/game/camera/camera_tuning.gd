class_name CameraTuning
extends Resource
## Camera knobs (race chase camera, build -> race swing, spectator). Owner: C13. Default: `camera/default_tuning.tres`,
## registered with TuningPanel (F2) as "Camera" by CameraDirector.
## NET: local only. Public API: exported fields only.
# CONTRACT: tuning resources use @export_range so TuningPanel can build sliders.

@export_group("Follow")
@export_range(3.0, 20.0) var back := 9.0 # TUNE: m behind the chariot
@export_range(1.0, 12.0) var up := 4.5 # TUNE: m above
@export_range(0.0, 15.0) var look_ahead := 5.0 # TUNE: m ahead of the chariot the camera looks at
@export_range(1.0, 20.0) var pos_smooth := 7.0 # TUNE: higher = tighter follow
@export_range(0.5, 12.0) var heading_smooth := 4.0 # TUNE: how fast the view swings round behind a turn
@export_group("Speed")
@export_range(40.0, 100.0) var fov_min := 68.0 # TUNE: degrees at a standstill
@export_range(40.0, 120.0) var fov_max := 88.0 # TUNE: degrees at ref_speed
@export_range(5.0, 60.0) var ref_speed := 22.0 # TUNE: m/s counted as full speed
@export_range(0.5, 10.0) var fov_smooth := 3.0 # TUNE
@export_group("Boost")
@export_range(0.0, 8.0) var boost_pullback := 3.0 # TUNE: extra m behind while boosting
@export_range(0.0, 20.0) var boost_fov := 8.0 # TUNE: extra degrees while boosting
@export_range(0.5, 10.0) var boost_smooth := 4.0 # TUNE
@export_group("Sway and turns")
@export_range(0.0, 8.0) var sway_lateral := 2.5 # TUNE: m the camera slides sideways at cart_angle = 1 rad
@export_range(0.0, 0.6) var sway_roll := 0.15 # TUNE: radians of camera roll at cart_angle = 1 rad
@export_range(0.0, 12.0) var turn_look := 4.0 # TUNE: m the look point shifts into a turn at full turn rate
@export_range(0.5, 20.0) var roll_smooth := 6.0 # TUNE: how fast the view rolls with a loop's road (C21)
@export_group("Shake")
@export_range(0.0, 1.0) var shake_amount := 0.35 # TUNE: m of positional shake at strength 1
@export_range(1.0, 30.0) var shake_jump_speed := 5.0 # TUNE: m/s velocity jump in one frame that counts as a hit
@export_range(0.1, 3.0) var shake_decay := 1.0 # TUNE: seconds for a hit shake to fade
@export_group("Swing")
@export_range(0.3, 2.8) var swing_time := 1.5 # TUNE: s of the build -> race swing (must end before GO)
@export_range(20.0, 90.0) var swing_start_fov := 45.0 # TUNE: degrees at the start of the swing
