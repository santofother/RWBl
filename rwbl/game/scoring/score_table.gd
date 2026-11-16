class_name ScoreTable
extends Resource
## Points per round (DESIGN §6). Owner: C11. Default: `default_score_table.tres`, registered with TuningPanel
## (F2) as "Score" by Scoring.
## NET: host only reads it when scoring a round.
## Public API: exported fields, `finish_points(place)`.
# CONTRACT: tuning resources use @export_range so TuningPanel can build sliders.

@export_group("Finish")
@export_range(-100, 600, 1) var finish_1st := 300 # TUNE: C24 (user): race win x2 (was 150)
@export_range(-100, 600, 1) var finish_2nd := 120 # TUNE: C24: everything but the win x1.2 (was 100)
@export_range(-100, 600, 1) var finish_3rd := 84 # TUNE (was 70)
@export_range(-100, 600, 1) var finish_4th := 48 # TUNE (was 40)
@export_range(-100, 600, 1) var finish_5th := 0 # TUNE
@export_group("Traps and combat")
@export_range(0, 200, 1) var trap_hit := 36 # TUNE: your item hit another player
@export_range(0, 500, 1) var trap_cap := 108 # TUNE: max trap points per round
@export_range(0, 500, 1) var kill := 72 # TUNE: per kill (spear, wheel, ram)
@export_range(-200, 0, 1) var self_kill := -36 # TUNE: died to your own trap
@export_group("Laps and bonuses")
@export_range(0, 200, 5) var lap := 25 # TUNE: unused since C23 (no laps); kept so old .tres files load
@export_range(0, 200, 1) var clean_lap := 30 # TUNE: clean run (no collisions start -> finish), once
@export_range(0, 200, 1) var mercy := 30 # TUNE: last to finish
@export_range(0, 500, 1) var fewest_deaths := 60 # TUNE: fewest deaths this round (ties all get it)
@export_group("Anti-grief")
## Items that are help, not traps: hitting a rival with them pays nothing.
@export var non_trap_items: Array[StringName] = [&"speed_pad"] # TUNE


## Points for finishing in `place` (1-based); 0 beyond 5th.
func finish_points(place: int) -> int:
	match place:
		1: return finish_1st
		2: return finish_2nd
		3: return finish_3rd
		4: return finish_4th
		5: return finish_5th
	return 0
