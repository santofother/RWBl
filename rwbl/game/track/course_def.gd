class_name CourseDef
extends Resource
## A course: the ordered list of track pieces from the start piece to the finish piece (DESIGN §5.6, C22).
## Owner: C22. Ids are piece scene names in `game/track/pieces/` (`start`, `straight`, `corner_left`, ...) or
## piece card ids (`piece_hairpin`). Track loads `default_course.tres` as round 1's course.
## NET: shipped data, identical on every peer.
# CONTRACT: the first piece is `start`, the last is `finish`.

## Piece ids in driving order.
@export var pieces: Array[StringName] = []
