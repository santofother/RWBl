class_name TagRule
extends Resource
## One row of the tag interaction table (DESIGN §5: "oil plus brazier makes a fire lane"). Owner: C02 (contract).
## Order of tag_a/tag_b doesn't matter. Items react to `effect`, never to the other item's id.
## Public API: exported fields, `matches()`.
# CONTRACT: field names.

## First tag (e.g. &"flammable").
@export var tag_a: StringName
## Second tag (e.g. &"hot").
@export var tag_b: StringName
## What happens, read by Item.interact() (e.g. &"ignite", &"slide_far").
@export var effect: StringName
## Effect parameters (e.g. {"duration": 6.0}).
@export var params: Dictionary = {}


## True if one side has tag_a and the other has tag_b (either way round).
func matches(tags_1: Array[StringName], tags_2: Array[StringName]) -> bool:
	return (tags_1.has(tag_a) and tags_2.has(tag_b)) or (tags_1.has(tag_b) and tags_2.has(tag_a))
