class_name GameMode
extends Node
## DESIGN §9 game contract between a hub/lobby and one game. Owner: C02 (contract).
## RWBL's implementation is `MatchMode` (game/match/match.gd).
## NET: the lobby instances the game scene on every peer at the same node path, calls `setup()` on every
## peer with identical arguments, then calls `start()` on the host only. `finished` fires on every peer.
## Public API: `setup()`, `start()`, signal `finished`.
# CONTRACT: these three members. The hub (wave 6) relies on them.

## Fired on every peer when the game is over.
signal finished(results: Array)


## Receive the players and the rules. Runs on every peer before start(). `players` are PlayerInfo.
func setup(_players: Array[PlayerInfo], _rules: Dictionary) -> void:
	pass


## Begin the game. NET: host only; the host then drives every peer.
func start() -> void:
	pass
