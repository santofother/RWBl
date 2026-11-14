# C04 — Chariot controller + F2 tuning panel (offline)
Agent: **Either** (suggested Claude) · Wave 1 · Branch: `c04-chariot`
Model: Claude **Opus 5.5, high** · or Codex **GPT-6 Astra, low–medium**
Depends on: C02

Owns: `rwbl/game/chariot/**`, `rwbl/game/tuning/**`, `tools/tests/chariot_test.sh`
Read: `DESIGN.md` §2, §4 · `docs/ARCHITECTURE.md` §2, §4 (Chariot, Surfaces, Tuning) · handoff `C02` ·
`rwbl/game/chariot/*.gd` (your stubs) · headers of `rwbl/game/common/chariot_input.gd`, `chariot_snapshot.gd`,
`effects.gd`, `surface.gd`, `layers.gd`, `rwbl/game/track/track.gd`, `rwbl/game/items/item.gd`

## Goal
Pillar 1: slippery, heavy, funny driving where a bad turn is your fault. The user tunes it with F2 sliders.

## Steps
- Replace the stub body of `Chariot.step()` with the DESIGN §4 two-body model, keeping the public API:
  horse pair (this node, thrust + steering) and a cart on a hitch (`hitch_length`, spring/damper
  `hitch_stiffness`) that trails with lateral slip, fishtails and can jackknife. Lateral grip from
  `tuning.grip_for(track.surface_at(...))` (sample horses and cart separately).
- Collisions: horses and cart are kinematic bodies on layers `HORSES` / `CART`, colliding with
  `WORLD | WALL | ITEM_SOLID | HORSES | CART`. On each collision (host) emit `hit(part, other, impact_speed)` and
  call `Item.find_item(collider).chariot_hit(...)` when it's an item. No stock `RigidBody3D` driving.
- Gravity + ground following so ramps (C10 `apply_impulse`) can launch the chariot; land safely.
- Whip: tap = short boost (`Effects.BOOST`), stamina cost, cooldown; spamming tires the horses (boost weaker or
  denied under a stamina threshold). Handle every `Effects.*` and `wheel_state` (limp / crawl).
- `step()` must not read `Input` or rely on being called from its own `_physics_process`: ChariotSync calls it
  (host and, in C07, owner prediction). Keep it free of RPCs.
- `chariot/test_drive.tscn`: a Track + one Chariot driven by `PlayerInput` with a chase camera, no network
  (F6 in the editor). Show speed / stamina / surface in a corner label.
- `tuning/tuning_panel.gd`: F2 opens a panel with a slider per `@export_range` field of every registered
  resource (grouped by `@export_group`), live. **Save** writes the `.tres` to its `res://` path when run from
  the editor; in exported builds to `user://tuning/<file>.tres`, which is loaded over the default at startup.
  Register `ChariotTuning` on chariot spawn.
- Put every number in `ChariotTuning` (`# TUNE`). Add fields freely; don't remove fields other cards read
  (`grip_for`, `speed_mult_for`).

## Tests
- `chariot_test.sh` (headless, scripted `ChariotInput`, no network): full throttle reaches ≥ 90 % `max_speed`;
  full steer turns > 90° in N s; on an oil patch the slip angle is much larger than on normal; whip boosts and
  costs stamina, 6 rapid whips exhaust it; one broken wheel lowers top speed, two = crawl; `get_snapshot()` →
  `apply_snapshot()` on a second chariot reproduces pose and cart angle. `contract_test` still passes.
- Manual (user), the C04 checkpoint: 1) Open the project in Godot. 2) In the FileSystem dock open
  `game/chariot/test_drive.tscn`, press **F6**. 3) Drive: W/S, A/D, Space = whip. 4) Press **F2**, drag sliders
  (e.g. grip, hitch stiffness) while driving. 5) Click **Save**. Tell us: is it fun? What feels off?

## Finish
Handoff `docs/handoffs/C04.md` with the tuning fields and their feel, land per AGENTS.md step 8.
