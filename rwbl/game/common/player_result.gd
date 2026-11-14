class_name PlayerResult
extends RefCounted
## Final result of one player at the end of a match (DESIGN §9 `finished(results)`). Owner: C02 (contract).
## NET: built on the host by MatchMode, sent to every peer with to_dict().
## Public API: fields, `to_dict()`, `from_dict()`.

## Slot of the player (see PlayerInfo).
var slot := 0
## Display name (copied so the hub does not need the PlayerInfo).
var name := ""
## Total match score.
var score := 0
## Final rank, 1 = winner.
var place := 0
## Free-form stats for the results screen (e.g. {"kills": 2, "trap_hits": 5}).
var stats: Dictionary = {}


## RPC-safe form.
func to_dict() -> Dictionary:
	return {"slot": slot, "name": name, "score": score, "place": place, "stats": stats}


## Inverse of to_dict().
static func from_dict(d: Dictionary) -> PlayerResult:
	var r := PlayerResult.new()
	r.slot = int(d.get("slot", 0))
	r.name = String(d.get("name", ""))
	r.score = int(d.get("score", 0))
	r.place = int(d.get("place", 0))
	r.stats = d.get("stats", {})
	return r
