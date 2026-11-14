class_name Effects
extends RefCounted
## Timed status effects items and combat put on a chariot with `Chariot.add_effect()`. Owner: C02 (contract).
## The chariot controller (C04) decides how each one changes handling; items just pick one.
## Public API: constants, `ALL`.
# CONTRACT: names. Add new effects here and handle them in Chariot.step().

const BOOST := &"boost" ## extra top speed and thrust (whip, speed pad). strength = multiplier of whip_boost
const SLOW := &"slow" ## top speed times (1 - 0.5 * strength) (mud keeps it while inside)
const STUN := &"stun" ## no thrust, no steering (horse hit, net)
const NO_STEER := &"no_steer" ## steering ignored (ice)
const REVERSE_STEER := &"reverse_steer" ## steering inverted (reverse zone)
const DRUNK := &"drunk" ## steering wobble + camera wobble (wine fountain)
const SHAKE := &"shake" ## camera shake, reduced turning (rumble gravel)
const TANGLED := &"tangled" ## horses slowed hard (net gladiator)
const BARBED := &"barbed" ## shredder wheels: slower, harder to steer, wheel hits break wheels

const ALL: Array[StringName] = [BOOST, SLOW, STUN, NO_STEER, REVERSE_STEER, DRUNK, SHAKE, TANGLED, BARBED]
