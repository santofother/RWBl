class_name ScoreAnimTuning
extends Resource
## Score-bar animation numbers (C18, DESIGN §6). Default: `default_score_anim.tres`, registered with TuningPanel
## (F2) as "Score anim" by ScoreScreen. The whole show is sped up to fit inside `score_time`, never overrun.
## NET: local only (presentation).
## Public API: exported fields, `category_color(cat)`.
# CONTRACT: tuning resources use @export_range so TuningPanel can build sliders.

## Categories in the order they are played. Keys of Scoring.get_breakdown() entries.
const CATEGORIES: Array[StringName] = [&"finish", &"kills", &"traps", &"bonus"]

@export_group("Timing")
@export_range(0.2, 2.0, 0.05) var intro_time := 0.6 # TUNE: s, bars sit at last round's totals first
@export_range(0.1, 2.0, 0.05) var chunk_time := 0.55 # TUNE: s, one category growing
@export_range(0.0, 1.0, 0.05) var chunk_gap := 0.3 # TUNE: s, pause between categories
@export_range(0.1, 2.0, 0.05) var resort_time := 0.7 # TUNE: s, columns sliding to the new order
@export_range(0.2, 4.0, 0.1) var finale_time := 1.4 # TUNE: s, match point flags / win burst
@export_range(0.0, 2.0, 0.1) var end_hold := 0.4 # TUNE: s, kept free at the end of score_time
@export_group("Feel")
## Tween.TransitionType: 10 = BACK (bouncy overshoot), 2 = QUINT, 6 = ELASTIC, 9 = BOUNCE.
@export_range(0, 11) var grow_trans := 10 # TUNE
@export_range(0, 11) var slide_trans := 10 # TUNE
@export_range(1.0, 2.5, 0.05) var pop_scale := 1.5 # TUNE: label pop size
@export_range(0.0, 0.5, 0.01) var wobble := 0.12 # TUNE: bar squash and stretch while growing
@export_range(0, 60, 1) var sparkles := 14 # TUNE: sparks per growing chunk (0 = off)
@export_range(0, 400, 10) var confetti := 160 # TUNE: pieces when someone wins
@export_group("Chart")
@export_range(0.5, 1.0, 0.01) var line_height := 0.85 # TUNE: where the win line sits (fraction of chart height)
@export_range(50, 1000, 50) var tick_every := 250 # TUNE: ghost tick spacing
@export_range(40, 300, 5) var bar_max_width := 150 # TUNE: px
@export_group("Colours")
@export var color_finish := Color(1.0, 0.82, 0.25)
@export var color_kills := Color(1.0, 0.35, 0.3)
@export var color_traps := Color(0.75, 0.45, 1.0)
@export var color_bonus := Color(0.4, 0.9, 0.55)
@export var color_loss := Color(1.0, 0.15, 0.15)


## Tint of a breakdown category.
func category_color(cat: StringName) -> Color:
	match cat:
		&"finish": return color_finish
		&"kills": return color_kills
		&"traps": return color_traps
		&"bonus": return color_bonus
	return Color.WHITE
