class_name PlayerInfo
extends RefCounted
## One player slot in a match (human or bot). Owner: C02 (contract, DESIGN §9).
## NET: built by the lobby (C03) on the host, sent to every peer with to_dict(); identical on all peers.
## Public API: fields, `to_dict()`, `from_dict()`, `color_for_slot()`.
# CONTRACT: `slot` (0..4) is the identity of a player inside a match. Chariots, scores and items use the slot,
# never the peer id. Bots have `is_bot = true` and `peer_id = 1` (the host drives them).

## 0..NetworkManager.MAX_PLAYERS-1, unique in the match.
var slot := 0
## Multiplayer peer that sends this slot's input (1 = host, also for bots).
var peer_id := 1
## Display name.
var name := "Player"
## Chariot / UI colour.
var color := Color.WHITE
## True when the host's AI drives this slot.
var is_bot := false
## Steam id when known (0 on LAN).
var steam_id := 0

const SLOT_COLORS: Array[Color] = [Color(0.85, 0.2, 0.2), Color(0.2, 0.45, 0.9), Color(0.95, 0.75, 0.15),
	Color(0.25, 0.7, 0.3), Color(0.65, 0.3, 0.8)]


## Default colour for a slot.
static func color_for_slot(s: int) -> Color:
	return SLOT_COLORS[posmod(s, SLOT_COLORS.size())]


## Convenience constructor.
static func create(s: int, peer: int, pname: String, bot: bool = false) -> PlayerInfo:
	var p := PlayerInfo.new()
	p.slot = s
	p.peer_id = peer
	p.name = pname
	p.is_bot = bot
	p.color = color_for_slot(s)
	return p


## RPC-safe form.
func to_dict() -> Dictionary:
	return {"slot": slot, "peer_id": peer_id, "name": name, "color": color, "is_bot": is_bot, "steam_id": steam_id}


## Inverse of to_dict().
static func from_dict(d: Dictionary) -> PlayerInfo:
	var p := PlayerInfo.new()
	p.slot = int(d.get("slot", 0))
	p.peer_id = int(d.get("peer_id", 1))
	p.name = String(d.get("name", "Player"))
	p.color = d.get("color", color_for_slot(p.slot))
	p.is_bot = bool(d.get("is_bot", false))
	p.steam_id = int(d.get("steam_id", 0))
	return p
