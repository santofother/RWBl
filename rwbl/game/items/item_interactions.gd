class_name ItemInteractions
extends RefCounted
## Tag interactions between placed items (DESIGN §5, "oil plus brazier makes a fire lane"). Owner: C10.
## When an item is placed, and at race start, the host looks for items close to it (footprints touching),
## runs ItemDB.tag_table().lookup(a.def.tags, b.def.tags) and calls interact(rule, other) on both items.
## Each pair + effect fires once per match (Item.applied_rules). Logs `[Item] INTERACT <effect> <uid> <uid>`.
## NET: host only. Items that change visibly because of a rule replicate that themselves (RPC / NetClock).
## Public API: static `check_item(item)`, `near(a, b)`.
# CONTRACT: items react to rule.effect + their own tags, never to the other item's id.

## Extra gap (m) between footprints that still counts as "nearby".
const NEAR_MARGIN := 0.5 # TUNE


## Host: run every tag rule between `item` and the items near it.
static func check_item(item: Item) -> void:
	if not is_instance_valid(item) or not item.is_inside_tree() or item.def == null:
		return
	if not item.multiplayer.is_server():
		return
	var table := ItemDB.tag_table()
	if table == null:
		return
	for n in item.get_tree().get_nodes_in_group(&"items"):
		var other := n as Item
		if other == null or other == item or other.def == null or not near(item, other):
			continue
		for rule: TagRule in table.lookup(item.def.tags, other.def.tags):
			var key_a := "%d:%s" % [other.uid, rule.effect]
			if item.applied_rules.has(key_a):
				continue
			item.applied_rules[key_a] = true
			other.applied_rules["%d:%s" % [item.uid, rule.effect]] = true
			print("[Item] INTERACT %s %d %d" % [rule.effect, item.uid, other.uid])
			item.interact(rule, other)
			other.interact(rule, item)


## True if the two footprints (as circles round their centres, flat) touch or nearly touch.
static func near(a: Item, b: Item) -> bool:
	var pa := a.global_position
	var pb := b.global_position
	var d := Vector2(pa.x - pb.x, pa.z - pb.z).length()
	return d <= (a.def.footprint.length() + b.def.footprint.length()) * 0.5 + NEAR_MARGIN
