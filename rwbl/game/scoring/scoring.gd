class_name Scoring
extends Node
## Points per round (DESIGN §6) incl. the anti-grief rule, totals, score screen. Owner: C11.
## C02 STUB: totals stay 0.
## NET: host listens to GameEvents (chariot_finished, race_over, trap_hit, kill, self_kill, clean_lap,
##   item_placed) and computes; at the SCORE phase it broadcasts GameEvents.round_scored to every peer.
## Public API: match_setup(m), get_totals() -> Dictionary slot -> int, get_round_points() -> Dictionary.

var _m: MatchMode
var _totals: Dictionary = {}
var _round: Dictionary = {}


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	for p in m.players:
		_totals[p.slot] = 0
		_round[p.slot] = 0


## slot -> total score (every peer, updated at round_scored).
func get_totals() -> Dictionary:
	return _totals.duplicate()


## slot -> points of the last scored round.
func get_round_points() -> Dictionary:
	return _round.duplicate()
