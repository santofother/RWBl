class_name HairpinPiece
extends TrackPiece
## Hairpin (DESIGN §5.6): a detour to one side that ends in a tight 180° U and comes back. Owner: C19.
## Turn 90° out (`entry_radius`), run `leg` m, U-turn (`hairpin_radius`), run back, turn 90° in.
## Chord = 2 * entry_radius + 2 * hairpin_radius. NET: shape data only.

@export_range(6.0, 30.0) var entry_radius := 10.0 # TUNE: m, the two 90° turns
@export_range(8.0, 30.0) var hairpin_radius := 11.0 # TUNE: m, the U (legs are 2x this apart)
@export_range(5.0, 60.0) var leg := 30.0 # TUNE: m out and back


func _shape() -> void:
	_arc(entry_radius, 90.0, true)
	_straight(leg)
	_arc(hairpin_radius, 180.0, false)
	_straight(leg)
	_arc(entry_radius, 90.0, true)
