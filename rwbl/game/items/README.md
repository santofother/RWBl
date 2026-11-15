# How to add an item
1. **Def** `defs/<id>.tres` (copy one; file name = `id`): `display_name`, `description`, `rarity`, `category`,
   `tags` (`flammable slippery heavy hot living`), `footprint` (x = local X, y = local Z, m), `placement`,
   `blocks_path`, `cost`, `scene`. ItemDB finds it by itself.
2. **Scene** `scenes/<id>.tscn`: root `Node3D`, script extends `Item` (or reuse `surface_item.gd` for ground
   patches: set `surface`, `lock_steer`). Local -Z = driving direction when placed along the track. Greybox meshes.
3. **Hook** (all effects on the host; visuals on every peer):
   - Area3D child named `Trigger` (+ CollisionShape3D) → `chariot_entered(chariot)` once on entry, or poll
     `trigger_chariots()` in `_physics_process` for "while inside" effects (ice, pit).
   - Solid body on `Layers.ITEM_SOLID` → `chariot_hit(chariot, part, speed)` (`part` = `&"horses"`/`&"cart"`).
   - Time-driven motion: compute from `NetClock.now()` (see `swinging_axe.gd`); one-off events: `trigger()`.
   - Tag rule: add a `TagRule` to `tag_table.tres`, react in `interact(rule, other)` by `rule.effect` + own tags.
4. Use `Chariot` API (`add_effect`, `stun`, `damage_wheel`, `apply_impulse`, `kill(cause, owner_slot, uid)`),
   call `report_hit(chariot)` whenever it affects someone. Numbers go in `item_tuning.gd` (`Item.tuning()`).
5. **Test**: add a `_<id>()` run to `tests/items_test.gd` (`_place`, `_start`, `_drive`, `_check`) and its id to
   the HIT loop in `tools/tests/items_test.sh`.
