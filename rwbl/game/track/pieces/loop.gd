class_name LoopPiece
extends TrackPiece
## Spiral loop (DESIGN §5.6, C21): a lead-in straight, a vertical loop that drifts `offset` m to the side (so the
## way out runs beside the way in), and a run-out straight. Upside down at the top. Inside the loop the chariot
## rides the road with surface gravity while fast enough (Chariot, `ChariotTuning.loop_min_speed`); too slow
## over the top and it falls off. Owner: C21. NET: shape data only.
## Chord = sqrt(offset² + (lead + run_out)²). Flip = drift to the left.

@export_range(6.0, 20.0) var radius := 10.0 # TUNE: m
@export_range(16.0, 30.0) var offset := 18.0 # TUNE: m sideways; keep > track width + both walls
@export_range(5.0, 40.0) var lead := 16.0 # TUNE: m straight before the loop (room to line up)
@export_range(5.0, 40.0) var run_out := 16.0 # TUNE: m straight after it


func _shape() -> void:
	_straight(lead)
	_loop(radius, offset)
	_straight(run_out)
