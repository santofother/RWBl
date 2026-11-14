class_name ItemDef
extends Resource
## Data for one placeable item (DESIGN §5). One `.tres` per item in `game/items/defs/`. Owner: C02 (contract);
## the defs themselves belong to C10 and later item cards.
## NET: identical on every peer (shipped data); only `id` goes over the network.
## Public API: exported fields, `has_tag()`. Known tags: flammable, slippery, heavy, hot, living.
# CONTRACT: field names and enums. Add fields at the end only.

enum Rarity { COMMON, UNCOMMON, RARE }
enum Category { TERRAIN, OBSTACLE, ROMAN, PICKUP, WILDCARD }
## ON_TRACK: centre must be on the drivable surface. TRACK_EDGE: within 4 m outside the edge (ballista).
## ANYWHERE: inside the track bounds.
enum Placement { ON_TRACK, TRACK_EDGE, ANYWHERE }

## Unique id, also the file name (`oil_slick` -> defs/oil_slick.tres).
@export var id: StringName
## Name on the draft card.
@export var display_name := ""
## One-line effect text on the draft card.
@export_multiline var description := ""
## Draft weight bucket (DESIGN §5.5).
@export var rarity: Rarity = Rarity.COMMON
## Draft card colour / grouping.
@export var category: Category = Category.TERRAIN
## Interaction tags, matched through the TagTable (never by item id).
@export var tags: Array[StringName] = []
## Size on the ground in metres: x = item local X, y = item local Z. Used by placement gap + path check.
@export var footprint := Vector2(2, 2)
## Where it may be placed.
@export var placement: Placement = Placement.ON_TRACK
## True if chariots cannot drive through it (column, pit). The path check treats its footprint as a wall.
@export var blocks_path := false
## Whether the player may rotate it in the build phase.
@export var rotatable := true
## Placement cost (budget per player per build phase, see C08).
@export var cost := 1
## Scene instanced on every peer. Its root script extends Item (game/items/item.gd).
@export var scene: PackedScene
## Card art (optional).
@export var icon: Texture2D


## True if this item carries `tag`.
func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
