class_name CornerPiece
extends TrackPiece
## Corner (DESIGN §5.6, C22): one arc of `radius` m turning `degrees`, to the right if `right`. Owner: C22.
## NET: shape data only.

@export_range(8.0, 80.0) var radius := 25.0 # TUNE: m
@export_range(10.0, 180.0) var degrees := 90.0 # TUNE
@export var right := true


func _shape() -> void:
	_arc(radius, degrees, right)
