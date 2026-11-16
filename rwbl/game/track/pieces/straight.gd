class_name StraightPiece
extends TrackPiece
## Straight road (DESIGN §5.6, C22). Owner: C22. Also the start piece (grid behind `line_at`) and the finish
## piece (finish line at `line_at`, run-off after it). NET: shape data only.

@export_range(5.0, 200.0) var length := 30.0 # TUNE: m


func _shape() -> void:
	_straight(length)
