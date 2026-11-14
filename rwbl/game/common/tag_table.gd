class_name TagTable
extends Resource
## The tag interaction table: a list of TagRule rows. The game's table is `game/items/tag_table.tres` (C10).
## Owner: C02 (contract). Public API: `rules`, `lookup()`.
# CONTRACT: items find interactions only through lookup().

## All rows.
@export var rules: Array[TagRule] = []


## Every rule that applies between two tag sets (empty if none).
func lookup(tags_1: Array[StringName], tags_2: Array[StringName]) -> Array[TagRule]:
	var out: Array[TagRule] = []
	for r in rules:
		if r != null and r.matches(tags_1, tags_2):
			out.append(r)
	return out
