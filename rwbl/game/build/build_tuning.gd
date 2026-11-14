class_name BuildTuning
extends Resource
## Build-phase knobs (placement rules, path check, bots, UI). Owner: C08. Default: `build/default_tuning.tres`,
## registered with TuningPanel (F2) by BuildPhase.
## NET: rules are validated on the host; clients use the same numbers for the green/red preview only.
## Public API: exported fields only.
# CONTRACT: tuning resources use @export_range so TuningPanel can build sliders.

@export_group("Rules")
@export_range(1, 20) var budget := 4 # TUNE: total item cost a player may place per build phase
@export_range(0.0, 6.0) var min_gap := 1.5 # TUNE: m between item footprints
@export_range(0.0, 8.0) var edge_reach := 4.0 # TUNE: m outside the road edge for TRACK_EDGE items
@export_range(0.05, 2.0) var max_height_error := 0.4 # TUNE: m an item may sit above/below the road
@export_group("Path check")
@export_range(0.5, 2.0) var cell := 1.0 # TUNE: grid cell size (m)
@export_range(0.0, 3.0) var chariot_half_width := 1.3 # TUNE: drivable area is eroded by this (m)
@export_group("Bots")
@export_range(1, 100) var bot_tries := 30 # TUNE: random positions tried per bot item
@export_range(0, 8) var bot_free_items := 2 # TUNE: items a bot places when free_build gives it no hand
@export_group("Editor")
@export_range(0.25, 4.0) var snap := 1.0 # TUNE: m grid snap of the ghost
@export_range(5.0, 90.0) var rotate_step := 15.0 # TUNE: degrees per Q/E press
