# C10 — Item framework + tag interaction table + first 8 items
Agent: **Either** · Wave 2 · Branch: `c10-items`
Model: Codex **GPT-6.1 Sol, high** · or Claude **Opus 5.5, medium**
Depends on: C04, C05

Owns: `rwbl/game/items/**`, `tools/tests/items_test.sh`
Read: `DESIGN.md` §5 intro, §5.1, §5.2 (only Column, Swinging axe, Pit) · `docs/ARCHITECTURE.md` §2, §4 (Items,
Surfaces/effects, Chariot, Clock) · handoffs `C02`, `C04`, `C05` · `rwbl/game/items/*` (your stubs + defs) ·
`rwbl/game/common/item_def.gd`, `tag_rule.gd`, `tag_table.gd`, `effects.gd`, `surface.gd`, `layers.gd` · headers
of `rwbl/game/chariot/chariot.gd`, `rwbl/game/track/track.gd`

## Goal
Eight working, readable items built on a framework where adding item #9 is one def, one scene and maybe one
small script (wave 4 makes each new item its own T3 card).

## Steps
- Real greybox scene per item (clear silhouette + colour per category), replacing `placeholder_item.tscn` in
  each def. Every effect runs on the host; visuals on every peer.
  - Oil slick: `track.register_surface_patch(self, Surface.OIL, half)` (unregister on exit). Mud: `MUD` patch.
    Ice: `ICE` patch + `Effects.NO_STEER` while inside. Laurel pad: `Effects.BOOST`. Ramp: solid wedge on
    `WORLD` (or `apply_impulse` up+forward if C04 prefers; check its handoff).
  - Column: `StaticBody3D` on `ITEM_SOLID`; `chariot_hit`: cart → `damage_wheel`, horses → `stun(1.0)`.
  - Swinging axe: pendulum angle = f(`NetClock.now()`) so every peer agrees; blade hit → stun + knockback.
  - Pit: `Trigger` area → `chariot.kill(&"pit", owner_slot, uid)` (respawn and time penalty are C12).
- Call `report_hit(victim)` once per chariot per item per race whenever an item affects someone (scoring).
- Tag interactions: when an item is placed (and at race start) the host finds overlapping/nearby items, runs
  `ItemDB.tag_table().lookup(a.def.tags, b.def.tags)` and calls `interact(rule, other)` on both. Implement the
  mechanism and the `slide_far` rule (heavy item on a slippery surface); `ignite` waits for the brazier (wave 4).
- `items/README.md`: "How to add an item" in ≤ 15 lines (def fields, scene root extends Item, which hook to use,
  test pattern). This is the template wave 4 cards read instead of the code.

## Tests
- `items_test.sh` + `items/tests/items_test.tscn`: Track + one Chariot driven by scripted `ChariotInput`
  straight through each item, one at a time, real physics frames. Assert per item: oil = large slip angle;
  mud = lower speed; ice = steering has no effect; pad = speed above max; ramp = airborne or impulse; column =
  wheel broken (cart) / stunned (horses); axe = hit inside its swing window; pit = `died`. Each logs
  `[Item] HIT id slot`. `trap_hit` emitted for a chariot whose slot ≠ owner, not for the owner.
- Manual (user): open `game/items/tests/items_test.tscn`, press **F6**, watch the chariot run the item gauntlet.

## Finish
Handoff `docs/handoffs/C10.md` (per-item tuning, README pointer), land per AGENTS.md step 8.
