class_name Draft
extends Node
## Draft phase: deal 3 cards per player weighted by rarity with catch-up, every player keeps exactly 1
## (DESIGN §3, §5.5). Owner: C09. The card UI is C14's (hud/): it shows `hand_dealt` and calls submit_pick([i]).
## Dealing: weights `MatchTuning.weight_*`, distinct cards per hand while the pool allows. Catch-up from round
##   `catchup_from_round` (by `m.totals()`, only when not everyone is tied): last place gets at least
##   `last_place_rares` cards of the best rarity that exists (RARE; UNCOMMON while no RARE item exists), the
##   leader draws only COMMON cards. Ties: every slot on the lowest / highest total counts.
## `rules.free_build` (`--free-build`): no deal, the phase ends at once, Build gives everyone every item.
## Timeout: MatchMode calls finish_draft() when DRAFT ends; whoever has not picked keeps their first card.
## NET: host deals and sends each human only its own cards (RPC to that peer -> hand_dealt there); bots are dealt
##   and pick on the host. Clients send picks with submit_pick(); the host checks them and, at the end of the
##   phase, broadcasts every kept card (hands_final on all peers). Hands are cleared when SCORE starts.
## C24: a client that has no cards `RESEND_AFTER` s into DRAFT asks the host to send them again
##   (`[Draft] RESEND slot`), so a late or lost deal never leaves a player without a draft screen.
## Logs: `[Draft] DEAL slot id,id,id rarity=r,r,r [leader|last]`, `[Draft] KEEP slot id [timeout]`,
##   `[Draft] CATCHUP last=[..] leader=[..] best_rarity=N`, `[Draft] ALL PICKED`.
## Public API: match_setup(m), cards_of(slot), hand_of(slot), has_picked(slot), submit_pick(indices),
##   finish_draft() (MatchMode), KEEP, signals below.

## Fires on the peer that owns `slot` (host for bots): these are your 3 cards (ItemDef ids).
signal hand_dealt(slot: int, cards: Array)
## all · the kept items of every player are final for this round. hands: slot -> Array[StringName].
signal hands_final(hands: Dictionary)
## host · `slot` kept `item_id` (bots, humans, timeout). For a "picked" tick in the HUD use has_picked().
signal picked(slot: int, item_id: StringName)

## Cards every player keeps per round (DESIGN §3, changed 2026-11-14).
const KEEP := 1

var _m: MatchMode
var _cards: Dictionary = {} # slot -> Array[StringName] dealt this round (host: all; client: own slot)
var _hands: Dictionary = {} # slot -> Array[StringName] kept this round
var _rng := RandomNumberGenerator.new()
## C24: seconds into DRAFT before a client without cards asks the host again (then every RESEND_AFTER s).
const RESEND_AFTER := 1.0
var _ask_at := 0.0 # local clock time of the next resend request (client)


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	_rng.randomize()
	GameEvents.phase_changed.connect(_on_phase_changed)
	GameEvents.roster_changed.connect(_on_roster_changed)


## The dealt cards of `slot` this round (only known on the owner's peer and the host).
func cards_of(slot: int) -> Array[StringName]:
	var c: Array[StringName] = []
	c.assign(_cards.get(slot, []))
	return c


## Kept items of `slot` this round (what BuildPhase lets them place). Known on every peer after hands_final;
## on the host as soon as the slot picked.
func hand_of(slot: int) -> Array[StringName]:
	var h: Array[StringName] = []
	h.assign(_hands.get(slot, []))
	return h


## True once `slot` kept its card this round (host; other peers after hands_final).
func has_picked(slot: int) -> bool:
	return _hands.has(slot)


## Local player keeps the card at `indices[0]` (exactly KEEP indices of 0..2). NET: any peer -> host.
func submit_pick(indices: Array[int]) -> void:
	var slot := _m.local_slot()
	if slot < 0:
		return
	if multiplayer.is_server():
		_pick(slot, indices)
	else:
		_rpc_pick.rpc_id(1, indices)


## End of DRAFT: auto-keep the first card for everyone who did not pick, broadcast hands_final.
## NET: host (MatchMode._advance), before BUILD is announced.
func finish_draft() -> void:
	if not multiplayer.is_server():
		return
	for p in _m.players:
		if not _hands.has(p.slot) and not cards_of(p.slot).is_empty():
			_keep(p.slot, cards_of(p.slot)[0], true)
	var out := {}
	for s: int in _hands:
		out[s] = _hands[s]
	_rpc_hands_final.rpc(out)


func _process(_delta: float) -> void:
	if _m == null or multiplayer.is_server() or _m.phase != Phase.DRAFT:
		return
	var slot := _m.local_slot()
	var now := Time.get_ticks_msec() * 0.001
	if slot < 0 or _cards.has(slot) or now < _ask_at or bool(_m.rules.get("free_build", false)):
		return
	_ask_at = now + RESEND_AFTER
	_rpc_resend.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_resend() -> void: # NET: host. A client is missing its cards: send them again.
	var slot := _m.slot_of_peer(multiplayer.get_remote_sender_id())
	if slot < 0 or _m.phase != Phase.DRAFT or not _cards.has(slot):
		return
	print("[Draft] RESEND %d" % slot)
	_rpc_dealt.rpc_id(multiplayer.get_remote_sender_id(), slot, _cards[slot])


func _on_phase_changed(p: int, r: int) -> void:
	if p == Phase.DRAFT:
		_ask_at = Time.get_ticks_msec() * 0.001 + RESEND_AFTER
	if p == Phase.SCORE:
		_cards.clear()
		_hands.clear()
	elif p == Phase.DRAFT and multiplayer.is_server():
		_deal(r)


func _on_roster_changed() -> void: # a dropped player became a bot: it picks now
	if multiplayer.is_server() and _m.phase == Phase.DRAFT:
		for p in _m.players:
			if p.is_bot and not _hands.has(p.slot) and _cards.has(p.slot):
				_bot_pick(p.slot)


# ---------------------------------------------------------------- host: dealing

func _deal(r: int) -> void: # NET: host
	_cards.clear()
	_hands.clear()
	if bool(_m.rules.get("free_build", false)):
		# WHY: BuildPhase gives every item only to an empty hand, so free build means no deal at all.
		print("[Draft] FREE BUILD (no deal)")
		GameEvents.phase_end_requested.emit(Phase.DRAFT)
		return
	var defs := ItemDB.all_defs()
	if defs.is_empty():
		push_warning("[Draft] no ItemDefs to deal")
		return
	var t: MatchTuning = _m.tuning
	var best := 0
	for d in defs:
		best = maxi(best, d.rarity)
	var last: Array[int] = []
	var leader: Array[int] = []
	if r >= t.catchup_from_round:
		_rank(_m.totals(), last, leader)
		if not last.is_empty():
			print("[Draft] CATCHUP last=%s leader=%s best_rarity=%d" % [last, leader, best])
	for p in _m.players:
		var is_leader := leader.has(p.slot) and t.leader_commons_only > 0
		var is_last := last.has(p.slot)
		var cards := _deal_hand(defs, t, is_leader, is_last, best)
		_cards[p.slot] = cards
		var rar: PackedStringArray = []
		for id in cards:
			rar.append(str(ItemDB.get_def(id).rarity))
		print("[Draft] DEAL %d %s rarity=%s%s" % [p.slot, ",".join(PackedStringArray(cards)), ",".join(rar),
			" leader" if is_leader else (" last" if is_last else "")])
		if p.is_bot or p.peer_id == multiplayer.get_unique_id():
			hand_dealt.emit(p.slot, cards)
		else:
			_rpc_dealt.rpc_id(p.peer_id, p.slot, cards)
	for p in _m.players:
		if p.is_bot:
			_bot_pick(p.slot)


## Fills `last` / `leader` with the slots on the lowest / highest total. Empty when everyone is tied.
func _rank(totals: Dictionary, last: Array[int], leader: Array[int]) -> void:
	var lo := 1 << 30
	var hi := -(1 << 30)
	for p in _m.players:
		var v := int(totals.get(p.slot, 0))
		lo = mini(lo, v)
		hi = maxi(hi, v)
	if lo == hi:
		return
	for p in _m.players:
		var v := int(totals.get(p.slot, 0))
		if v == lo:
			last.append(p.slot)
		elif v == hi:
			leader.append(p.slot)


func _deal_hand(defs: Array[ItemDef], t: MatchTuning, leader: bool, last: bool, best: int) -> Array[StringName]:
	var pool: Array[ItemDef] = []
	if leader:
		pool.assign(defs.filter(func(d: ItemDef) -> bool: return d.rarity == ItemDef.Rarity.COMMON))
	if pool.is_empty():
		pool = defs
	var hand: Array[StringName] = []
	for i in t.cards_per_hand:
		hand.append(_draw(pool, t, hand))
	if last:
		var best_pool: Array[ItemDef] = []
		best_pool.assign(defs.filter(func(d: ItemDef) -> bool: return d.rarity == best))
		var have := 0
		for id in hand:
			if ItemDB.get_def(id).rarity == best:
				have += 1
		for i in hand.size():
			if have >= t.last_place_rares:
				break
			if ItemDB.get_def(hand[i]).rarity != best:
				hand[i] = _draw(best_pool, t, hand)
				have += 1
	return hand


## One weighted card from `pool`, avoiding ids already in `hand` while the pool has others.
func _draw(pool: Array[ItemDef], t: MatchTuning, hand: Array[StringName]) -> StringName:
	var cand: Array[ItemDef] = []
	cand.assign(pool.filter(func(d: ItemDef) -> bool: return not hand.has(d.id)))
	if cand.is_empty():
		cand = pool
	var total := 0.0
	for d in cand:
		total += maxf(t.rarity_weight(d.rarity), 0.0)
	if total <= 0.0:
		return cand[_rng.randi() % cand.size()].id
	var x := _rng.randf() * total
	for d in cand:
		x -= maxf(t.rarity_weight(d.rarity), 0.0)
		if x < 0.0:
			return d.id
	return cand[-1].id


# ---------------------------------------------------------------- host: picks

func _bot_pick(slot: int) -> void: # NET: host. Bots keep their rarest card (random among equals).
	var cards := cards_of(slot)
	if cards.is_empty():
		return
	var best_i := 0
	var best_r := -1
	var ties := 0
	for i in cards.size():
		var rr := ItemDB.get_def(cards[i]).rarity
		if rr > best_r:
			best_r = rr
			best_i = i
			ties = 1
		elif rr == best_r:
			ties += 1
			if _rng.randi() % ties == 0:
				best_i = i
	_pick(slot, [best_i])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pick(indices: Array) -> void: # NET: client -> host
	var slot := _m.slot_of_peer(multiplayer.get_remote_sender_id())
	if slot >= 0:
		_pick(slot, indices)


func _pick(slot: int, indices: Array) -> void: # NET: host. Checks phase, count, range, not picked yet.
	if _m.phase != Phase.DRAFT or _hands.has(slot) or indices.size() != KEEP:
		return
	var cards := cards_of(slot)
	var i := int(indices[0])
	if i < 0 or i >= cards.size():
		return
	_keep(slot, cards[i], false)
	for p in _m.players:
		if not _hands.has(p.slot):
			return
	print("[Draft] ALL PICKED")
	GameEvents.phase_end_requested.emit(Phase.DRAFT)


func _keep(slot: int, id: StringName, timeout: bool) -> void: # NET: host
	var h: Array[StringName] = [id]
	_hands[slot] = h
	print("[Draft] KEEP %d %s%s" % [slot, id, " timeout" if timeout else ""])
	picked.emit(slot, id)


# ---------------------------------------------------------------- every peer

@rpc("authority", "call_remote", "reliable")
func _rpc_dealt(slot: int, cards: Array) -> void: # NET: the owner's peer
	var c: Array[StringName] = []
	c.assign(cards)
	_cards[slot] = c
	hand_dealt.emit(slot, c)


@rpc("authority", "call_local", "reliable")
func _rpc_hands_final(hands: Dictionary) -> void: # NET: every peer
	_hands.clear()
	for s: int in hands:
		var h: Array[StringName] = []
		h.assign(hands[s])
		_hands[s] = h
	hands_final.emit(_hands.duplicate())
