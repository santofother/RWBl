class_name BotTuning
extends Resource
## Bot driving knobs. Owner: C06. Default: `bots/default_tuning.tres`, registered with TuningPanel (F2) by BotManager.
## NET: host only (bots are simulated on the host).
## Public API: exported fields only.
# CONTRACT: tuning resources use @export_range so TuningPanel can build sliders.

@export_group("Steering")
@export_range(2.0, 30.0) var look_base := 8.0 # TUNE: m ahead on the centre line at standstill
@export_range(0.0, 1.0) var look_speed := 0.28 # TUNE: extra look-ahead seconds (m per m/s)
@export_range(0.5, 6.0) var steer_gain := 2.0 # TUNE: radians of heading error -> full lock multiplier
@export_group("Corners")
@export_range(2.0, 30.0) var corner_lat_accel := 8.0 # TUNE: m/s² we allow in corners (lower = safer)
@export_range(10.0, 80.0) var preview := 40.0 # TUNE: m of road checked for curvature
@export_range(3.0, 20.0) var min_corner_speed := 8.0 # TUNE: m/s floor
@export_range(0.0, 8.0) var brake_margin := 2.0 # TUNE: m/s over the wanted speed before braking hard
@export_group("Whip")
@export_range(0.0, 1.0) var whip_stamina := 0.7 # TUNE: whip on straights above this stamina
@export_range(0.0, 0.01) var whip_max_curve := 0.004 # TUNE: rad/m, no whipping into corners
@export_group("Traffic")
@export_range(1.0, 10.0) var lane_gap := 3.0 # TUNE: m of lateral clearance kept from other chariots
@export_range(5.0, 40.0) var traffic_range := 18.0 # TUNE: m ahead we react to chariots / items
@export_range(0.5, 10.0) var offset_rate := 3.0 # TUNE: m/s the lateral offset moves
@export_range(0.5, 6.0) var edge_margin := 2.5 # TUNE: m kept from the road edge
@export_group("Personality")
@export_range(0.0, 1.0) var aggression := 0.5 # TUNE: higher = takes corners faster, whips more
@export_range(0.0, 1.0) var skill_noise := 0.25 # TUNE: per-bot spread of speed/steer choices
@export_group("Unstuck")
@export_range(0.5, 6.0) var stuck_time := 2.0 # TUNE: s without progress before reversing
@export_range(0.2, 3.0) var reverse_time := 1.0 # TUNE: s spent reversing
