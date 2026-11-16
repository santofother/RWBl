class_name CrestPiece
extends TrackPiece
## Crest / jump (DESIGN §5.6, C20): a ramp up, a sharp crest, a short steep drop and a long level run-out to land
## on. Over the crest a fast chariot leaves the ground (its vertical speed beats gravity: about v² / R > g, with R
## the crest's radius ≈ `flip` / (rise + fall) — 16 m/s and up with the defaults and gravity 25); slower ones stay
## on the road. Owner: C20. NET: shape data only. Ends at the height it started.

@export_range(0.05, 0.5) var rise := 0.25 # TUNE: dy/dx of the ramp
@export_range(0.05, 0.6) var fall := 0.3 # TUNE: dy/dx of the drop (steeper than the ramp = it falls away)
@export_range(2.0, 20.0) var ramp := 12.0 # TUNE: m at the full ramp grade
@export_range(2.0, 20.0) var flip := 6.0 # TUNE: m to go from rise to fall (the crest; shorter = launches slower)
@export_range(2.0, 20.0) var ease_len := 8.0 # TUNE: m to bend into the ramp / out of the drop
@export_range(5.0, 30.0) var lead := 8.0 # TUNE: m level before
@export_range(10.0, 60.0) var run_out := 30.0 # TUNE: m level after (landing)


func _shape() -> void:
	_straight(lead)
	var a := ease_len
	var b := a + ramp
	var c := b + flip
	# the drop's full-grade length, so the profile ends at height 0
	var up := rise * 0.5 * ease_len + rise * ramp + (rise - fall) * 0.5 * flip
	var hold := maxf(0.0, (up - fall * 0.5 * ease_len) / fall)
	var d := c + hold
	var e := d + ease_len
	_slopes([Vector2(0, 0), Vector2(a, rise), Vector2(b, rise), Vector2(c, -fall), Vector2(d, -fall), Vector2(e, 0)])
	_straight(run_out)
