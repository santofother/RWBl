class_name ItemDB
extends RefCounted
## Finds every ItemDef in `game/items/defs/` (one .tres per item, file name = id). Owner: C10.
## NET: identical on every peer. Public API: static `get_def(id)`, `all_defs()`, `ids()`, `tag_table()`.
# CONTRACT: adding an item = adding defs/<id>.tres (+ its scene). Nothing else registers items.

const DEFS_DIR := "res://game/items/defs/"
const TAG_TABLE_PATH := "res://game/items/tag_table.tres"

static var _defs: Dictionary = {} # StringName -> ItemDef
static var _loaded := false


## The ItemDef for `id`, or null.
static func get_def(id: StringName) -> ItemDef:
	_ensure()
	return _defs.get(id)


## Every ItemDef, sorted by id.
static func all_defs() -> Array[ItemDef]:
	_ensure()
	var out: Array[ItemDef] = []
	for id: StringName in ids():
		out.append(_defs[id])
	return out


## Every item id, sorted.
static func ids() -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for k: StringName in _defs:
		out.append(k)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## The game's tag interaction table.
static func tag_table() -> TagTable:
	return load(TAG_TABLE_PATH) as TagTable


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	# WHY: ResourceLoader.list_directory also works in exported builds (where files are remapped).
	for f in ResourceLoader.list_directory(DEFS_DIR):
		if not f.ends_with(".tres"):
			continue
		var d := load(DEFS_DIR + f) as ItemDef
		if d and d.id != &"":
			_defs[d.id] = d
