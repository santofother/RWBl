class_name ChicanePiece
extends TrackPiece
## Chicane / S-bend (DESIGN §5.6): a quick left-right jink that comes back onto the old line. Owner: C19.
## Four arcs of `radius` m: left a, right a, right a, left a (a = `angle`). Chord = 4 * radius * sin(a);
## sideways shift = 2 * radius * (1 - cos(a)). NET: shape data only.

@export_range(10.0, 60.0) var radius := 20.0 # TUNE: m
@export_range(10.0, 60.0) var angle := 40.0 # TUNE: degrees per arc


func _shape() -> void:
	_arc(radius, angle, false)
	_arc(radius, angle, true)
	_arc(radius, angle, true)
	_arc(radius, angle, false)
