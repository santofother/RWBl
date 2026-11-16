class_name HillPiece
extends TrackPiece
## Hill (DESIGN §5.6, C20): uphill then downhill, so the course ends at the height it started (the finish stays at
## y = 0). Climbing slows the chariot, the way down speeds it up past top speed (`ChariotTuning.slope_gravity`,
## `downhill_top_gain`). Gentle enough that nobody takes off at the top. Owner: C20. NET: shape data only.
## Slope profile (see TrackPiece._slopes): bend in over `ease_len` m, hold `grade` for `climb` m, bend out, a level
## top of `top` m, then the same down. Height = grade × (ease_len + climb).

@export_range(0.05, 0.3) var grade := 0.16 # TUNE: dy/dx of the steep part (0.16 ≈ 9°)
@export_range(4.0, 30.0) var ease_len := 14.0 # TUNE: m to bend from level to the full grade
@export_range(0.0, 40.0) var climb := 14.0 # TUNE: m at the full grade
@export_range(0.0, 40.0) var top := 10.0 # TUNE: m level at the top
@export_range(0.0, 20.0) var lead := 5.0 # TUNE: m level before and after


func _shape() -> void:
	_straight(lead)
	var a := ease_len
	var b := a + climb
	var c := b + ease_len
	var d := c + top
	var e := d + ease_len
	var f := e + climb
	var g := f + ease_len
	_slopes([Vector2(0, 0), Vector2(a, grade), Vector2(b, grade), Vector2(c, 0), Vector2(d, 0), Vector2(e, -grade),
		Vector2(f, -grade), Vector2(g, 0)])
	_straight(lead)
