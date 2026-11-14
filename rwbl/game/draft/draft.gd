class_name Draft
extends Node
## Draft phase: deal 3 cards per player weighted by rarity with catch-up, players keep 1 or 2 (DESIGN §3, §5.5).
## Owner: C09. C02 STUB: API only. The card UI is C14's (hud/), it calls submit_pick().
## NET: host deals and sends each player its own cards (hand_dealt fires on that player's peer; on the host
##   for bots). Clients send picks with submit_pick(); the host stores hands and broadcasts them.
## Public API: match_setup(m), cards_of(slot), hand_of(slot), submit_pick(indices), signals below.

## Fires on the peer that owns `slot` (host for bots): these are your 3 cards (ItemDef ids).
signal hand_dealt(slot: int, cards: Array)
## all · the kept items of every player are final for this round. hands: slot -> Array[StringName].
signal hands_final(hands: Dictionary)

var _m: MatchMode
var _hands: Dictionary = {} # slot -> Array[StringName] kept items for this round


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m


## The 3 dealt cards of `slot` this round (only known on the owner's peer and the host). TODO(C09)
func cards_of(_slot: int) -> Array[StringName]:
	return []


## Kept items of `slot` this round (what BuildPhase lets them place). TODO(C09)
func hand_of(slot: int) -> Array[StringName]:
	var h: Array[StringName] = []
	h.assign(_hands.get(slot, []))
	return h


## Local player keeps the cards at `indices` (1 or 2 of 0..2). TODO(C09): RPC to host.
func submit_pick(_indices: Array[int]) -> void:
	pass
