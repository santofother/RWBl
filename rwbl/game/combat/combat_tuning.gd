class_name CombatTuning
extends Resource
## Combat numbers: chariot-vs-chariot rams, respawn, crow spectator (DESIGN §4, §6). Owner: C12.
## Default: `combat/default_tuning.tres`, registered with TuningPanel (F2) as "Combat" by Combat.
## NET: host only (combat runs on the host); the visual fields are read on every peer.
## Public API: exported fields.
# CONTRACT: tuning resources use @export_range so TuningPanel can build sliders.

@export_group("Rams")
@export_range(0.0, 15.0) var min_ram_speed := 2.0 # TUNE: m/s closing speed below which a bump does nothing
@export_range(0.0, 3.0) var horse_stun := 0.8 # TUNE: s, loser's horses were hit
@export_range(0.0, 2.0) var pair_immunity := 0.5 # TUNE: s, same two chariots can't trade hits again sooner
@export_range(1.0, 3.0) var win_margin := 1.1 # TUNE: winner's mass x speed must beat the loser's by this factor
@export_group("Respawn")
@export_range(0.3, 3.0) var respawn_delay := 1.5 # TUNE: s dead before respawn (DESIGN: back in < 3 s)
@export_range(0.0, 1.4) var pit_penalty := 1.0 # TUNE: extra s after a pit death (keep delay + this < 3)
@export_range(0.0, 40.0) var respawn_back := 10.0 # TUNE: m behind the death spot along the track
@export_group("Crow")
@export_range(1.0, 30.0) var crow_drop_cooldown := 8.0 # TUNE: s between a crow's mud drops
@export_range(0.0, 60.0) var crow_death_time_left := 10.0 # TUNE: s of race left under which a death makes a crow
@export_range(5.0, 80.0) var crow_bot_lead := 25.0 # TUNE: m ahead of the race leader a bot crow drops at
@export var bot_crows_drop := true # TUNE: bot crows drop mud on their own
@export_group("Visuals")
@export_range(0.5, 6.0) var wheel_fx_life := 2.5 # TUNE: s a popped wheel bounces before it fades
@export_range(1.0, 15.0) var wheel_fx_kick := 6.0 # TUNE: m/s sideways kick of a popped wheel
