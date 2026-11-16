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
@export_range(0.0, 1.0) var side_hit_min := 0.5 # TUNE: cart hits break a wheel only this side-on (|cos| to the axle); rear-end taps don't
@export_range(1.0, 15.0) var crawl_wreck_time := 4.0 # TUNE: s crawling on no wheels before the chariot wrecks and respawns
@export_group("Respawn")
@export_range(0.3, 3.0) var respawn_delay := 2.0 # TUNE: s dead before respawn (DESIGN: back in < 3 s)
## C24 (user): in a race you also wait until another racer has passed the spot where you died, so crashing
## out of the lead costs the lead. 0 = off (plain respawn_delay).
@export var respawn_wait_for_pass := true # TUNE
## User (C21 session): no timed auto-respawn in a race: 0 = wait for a pass however long it takes (if everyone
## left is crashed, the race ends: RaceController). > 0 = respawn anyway after that many seconds (old C24 cap).
@export_range(0.0, 30.0) var respawn_wait_max := 0.0 # TUNE: s
@export_range(0.0, 0.95) var pit_penalty := 0.8 # TUNE: extra s after a pit death (keep delay + this < 3)
@export_range(0.0, 40.0) var respawn_back := 10.0 # TUNE: m behind the death spot along the track
## User request (C21 session): when a rival passing your crash spot is what lets you back in, you respawn right
## behind that rival (same lane) instead of `respawn_back` behind the crash spot.
@export var respawn_behind_rival := true # TUNE
@export_range(4.0, 30.0) var respawn_rival_gap := 9.0 # TUNE: m behind the rival's horses (its cart is ~4 m long)
@export_group("Crow")
@export_range(1.0, 30.0) var crow_drop_cooldown := 8.0 # TUNE: s between a crow's mud drops
@export_range(0.0, 60.0) var crow_death_time_left := 10.0 # TUNE: s of race left under which a death makes a crow
@export_range(5.0, 80.0) var crow_bot_lead := 25.0 # TUNE: m ahead of the race leader a bot crow drops at
@export var bot_crows_drop := true # TUNE: bot crows drop mud on their own
@export_group("Visuals")
@export_range(0.5, 6.0) var wheel_fx_life := 2.5 # TUNE: s a popped wheel bounces before it fades
@export_range(1.0, 15.0) var wheel_fx_kick := 6.0 # TUNE: m/s sideways kick of a popped wheel
