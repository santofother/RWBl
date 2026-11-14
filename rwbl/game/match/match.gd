class_name MatchMode
extends GameMode
## RWBL's GameMode: one match = 6-8 rounds of Draft -> Build -> Race -> Score (DESIGN §3, §9). Owner: C09.
## Host runs the phase loop: each phase ends on its timer or early on `GameEvents.phase_end_requested`. After
## SCORE: someone >= `win_score` or the last round -> results. The last round is the Grand Circus (+laps; Scoring
## doubles its own points). A client that leaves mid-match becomes a bot on every peer (`roster_changed`).
## Numbers: MatchTuning (`match/default_tuning.tres`, F2 "Match"); the `rules` dict overrides them per match.
## Scene: match.tscn. Its children are the match systems, fixed names (see CONTRACT below). Each system has
## `match_setup(m: MatchMode)`, called in SYSTEMS order on every peer from setup(); systems then react to
## GameEvents.phase_changed. Systems reach each other through the typed vars below (e.g. `m.track`).
## NET: setup() on every peer; start() and the phase loop on the host; phases are broadcast by RPC.
## Standalone (scene run directly, tests): CLI `--bots=N` `--no-human` `--phase=draft|build|race|score`
##   `--rounds=N` `--laps=N` `--phase-time=SEC` `--autotest=SEC` `--quit-after=SEC`. Offline = host.
## Any scene (read in setup, host): `--free-build` (rules.free_build = true: Build ignores the draft, also implied
##   by C08's `--test-place`), `--test-totals=slot:points,...` (added to the Scoring totals; tests catch-up + win).
## Public API: players, rules, phase, round_index, setup(), start(), local_slot(), slot_of_peer(peer),
##   get_player(slot), phase_time_left(), is_grand_circus(), totals(), tuning, signal finished (GameMode).
# CONTRACT: child node names Track, Items, Chariots, ChariotSync, Race, Draft, Build, Scoring, Combat, Bots,
#   Cameras, Hud. The match node is at the same path on every peer (RPCs depend on it).
# CONTRACT: rules keys: rounds, laps, win_score, draft_time, build_time, race_time, score_time, start_phase.
#   C09 adds: free_build (C08 reads it), grand_circus_extra_laps. `laps` is raised on every peer in the final round.

const SYSTEMS: Array[StringName] = [&"Track", &"ChariotSync", &"Race", &"Draft", &"Build", &"Scoring",
	&"Combat", &"Bots", &"Cameras", &"Hud"]
## Rules that are not numbers. The numbers come from `tuning.to_rules()`.
const DEFAULT_RULES := {"start_phase": Phase.DRAFT, "free_build": false}

## Match numbers (F2 "Match"). Read once in setup(); edits apply to the next match.
var tuning: MatchTuning = preload("res://game/match/default_tuning.tres")
## `--test-totals` points per slot, added to the Scoring totals (tests only).
var test_totals: Dictionary = {}

@onready var track: Track = $Track
@onready var items_root: Node3D = $Items
@onready var chariots_root: Node3D = $Chariots
@onready var chariot_sync: ChariotSync = $ChariotSync
@onready var race: RaceController = $Race
@onready var draft: Draft = $Draft
@onready var build: BuildPhase = $Build
@onready var scoring: Scoring = $Scoring
@onready var combat: Combat = $Combat
@onready var bots: BotManager = $Bots
@onready var cameras: CameraDirector = $Cameras
@onready var hud: Hud = $Hud

## Every slot in the match (humans and bots), index = slot.
var players: Array[PlayerInfo] = []
## DEFAULT_RULES merged with the lobby's rules.
var rules: Dictionary = {}
## Current Phase.*.
var phase := Phase.NONE
## Current round, 1-based (0 before the first).
var round_index := 0
## NetClock time when the current phase ends.
var phase_end_time := 0.0

var _base_laps := 1
var _end_requested := Phase.NONE # NET: host. Handled in _physics_process (never inside a phase_changed handler).


func _ready() -> void:
	GameEvents.phase_end_requested.connect(_on_phase_end_requested)
	if get_tree().current_scene == self:
		_standalone.call_deferred()


## GameMode: receive players + rules and set up every system. NET: every peer, same arguments.
func setup(p: Array[PlayerInfo], r: Dictionary) -> void:
	players = p
	var panel := get_node_or_null(^"/root/TuningPanel")
	if panel:
		panel.register(tuning, "Match")
	rules = tuning.to_rules()
	rules.merge(DEFAULT_RULES, true)
	rules.merge(r, true)
	var a := NetworkManager.args
	if a.has("free-build") or a.has("test-place"):
		rules["free_build"] = true
	_base_laps = int(rules["laps"])
	test_totals = _parse_totals(String(a.get("test-totals", "")))
	if multiplayer.is_server() and not NetworkManager.peer_left.is_connected(_on_peer_left):
		NetworkManager.peer_left.connect(_on_peer_left)
	for s in SYSTEMS:
		var n := get_node(NodePath(s))
		if n.has_method(&"match_setup"):
			n.match_setup(self)
	print("[Game] Match setup: %d players, %d rounds" % [players.size(), int(rules["rounds"])])


## GameMode: begin round 1. NET: host only.
func start() -> void:
	if multiplayer.is_server():
		_enter_phase(int(rules["start_phase"]), 1)


## Slot of this machine's human player, or -1 (spectator / headless).
func local_slot() -> int:
	return slot_of_peer(multiplayer.get_unique_id())


## Human slot driven by `peer_id`, or -1.
func slot_of_peer(peer_id: int) -> int:
	for p in players:
		if p.peer_id == peer_id and not p.is_bot:
			return p.slot
	return -1


## PlayerInfo of `slot`, or null.
func get_player(slot: int) -> PlayerInfo:
	for p in players:
		if p.slot == slot:
			return p
	return null


## Seconds until the current phase times out (same on every peer).
func phase_time_left() -> float:
	return maxf(0.0, phase_end_time - NetClock.now())


## True in the final "Grand Circus" round (double points, +laps). Never in a 1-round match (tests, quick games).
func is_grand_circus() -> bool:
	var n := int(rules.get("rounds", 6))
	return n > 1 and round_index == n


## slot -> total points: Scoring's totals plus `--test-totals`. What catch-up dealing and the win check use.
func totals() -> Dictionary:
	var t := scoring.get_totals()
	for s: int in test_totals:
		t[s] = int(t.get(s, 0)) + int(test_totals[s])
	return t


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or phase == Phase.NONE or phase == Phase.MATCH_OVER:
		return
	if _end_requested == phase or NetClock.now() >= phase_end_time:
		_advance()


func _on_phase_end_requested(p: int) -> void:
	# WHY: systems often request the end from inside their phase_changed handler (everyone picked at once);
	# advancing right there would nest phase_changed emissions. _physics_process advances next tick.
	if multiplayer.is_server() and p == phase:
		_end_requested = p


func _advance() -> void: # NET: host
	match phase:
		Phase.DRAFT:
			draft.finish_draft()
			_enter_phase(Phase.BUILD, round_index)
		Phase.BUILD: _enter_phase(Phase.RACE, round_index)
		Phase.RACE: _enter_phase(Phase.SCORE, round_index)
		Phase.SCORE:
			var t := totals()
			var best := -1
			for s: int in t:
				if int(t[s]) >= int(rules["win_score"]) and (best < 0 or int(t[s]) > int(t[best])):
					best = s
			if best >= 0:
				print("[Game] WIN slot %d score %d (win_score %d)" % [best, int(t[best]), int(rules["win_score"])])
				_finish()
			elif round_index >= int(rules["rounds"]):
				_finish()
			else:
				_enter_phase(Phase.DRAFT, round_index + 1)


func _duration(p: int) -> float:
	var key: String = {Phase.DRAFT: "draft_time", Phase.BUILD: "build_time", Phase.RACE: "race_time",
		Phase.SCORE: "score_time"}.get(p, "")
	return float(rules.get(key, 10.0))


func _enter_phase(p: int, r: int) -> void: # NET: host
	_rpc_phase.rpc(p, r, NetClock.now() + _duration(p))


@rpc("authority", "call_local", "reliable")
func _rpc_phase(p: int, r: int, end_time: float) -> void: # NET: every peer
	phase = p
	round_index = r
	phase_end_time = end_time
	_end_requested = Phase.NONE
	rules["laps"] = _base_laps + (int(rules.get("grand_circus_extra_laps", 1)) if is_grand_circus() else 0)
	print("[Game] PHASE %s %d" % [Phase.name_of(p), r])
	if p == Phase.DRAFT and is_grand_circus():
		print("[Game] GRAND CIRCUS round %d laps %d" % [r, int(rules["laps"])])
	GameEvents.phase_changed.emit(p, r)


func _finish() -> void: # NET: host
	var t := totals()
	var order: Array[PlayerInfo] = players.duplicate()
	order.sort_custom(func(a: PlayerInfo, b: PlayerInfo) -> bool:
		var sa := int(t.get(a.slot, 0))
		var sb := int(t.get(b.slot, 0))
		return sa > sb or (sa == sb and a.slot < b.slot))
	var out: Array = []
	for i in order.size():
		var res := PlayerResult.new()
		res.slot = order[i].slot
		res.name = order[i].name
		res.score = int(t.get(res.slot, 0))
		res.place = i + 1
		out.append(res.to_dict())
	_rpc_finished.rpc(out)


@rpc("authority", "call_local", "reliable")
func _rpc_finished(dicts: Array) -> void: # NET: every peer
	phase = Phase.MATCH_OVER
	GameEvents.phase_changed.emit(Phase.MATCH_OVER, round_index)
	var results: Array = []
	for d: Dictionary in dicts:
		var res := PlayerResult.from_dict(d)
		results.append(res)
		print("[Game] RESULT %d %s score=%d place=%d" % [res.slot, res.name, res.score, res.place])
	print("[Game] MATCH FINISHED")
	finished.emit(results)


# ---------------------------------------------------------------- dropouts

func _on_peer_left(peer_id: int) -> void: # NET: host
	if phase == Phase.MATCH_OVER or not is_inside_tree():
		return
	for p in players:
		if p.peer_id == peer_id and not p.is_bot:
			_rpc_slot_to_bot.rpc(p.slot)


@rpc("authority", "call_local", "reliable")
func _rpc_slot_to_bot(slot: int) -> void: # NET: every peer
	var p := get_player(slot)
	if p == null or p.is_bot:
		return
	p.is_bot = true
	p.peer_id = 1
	print("[Game] DROPOUT slot %d -> bot" % slot)
	GameEvents.roster_changed.emit()


static func _parse_totals(spec: String) -> Dictionary:
	var out := {}
	for part in spec.split(",", false):
		var kv := part.split(":")
		if kv.size() == 2:
			out[int(kv[0])] = int(kv[1])
	return out


# ---------------------------------------------------------------- standalone (tests, F6 on this scene)

func _standalone() -> void:
	var a := NetworkManager.args
	var ps: Array[PlayerInfo] = []
	if not a.has("no-human"):
		ps.append(PlayerInfo.create(0, multiplayer.get_unique_id(), NetworkManager.local_name))
	for i in int(a.get("bots", 3 if ps.size() > 0 else 4)): # F6 in the editor: you + 3 bots
		var s := ps.size()
		if s >= NetworkManager.MAX_PLAYERS:
			break
		ps.append(PlayerInfo.create(s, 1, "Bot%d" % s, true))
	var r := {}
	if a.has("rounds"):
		r["rounds"] = int(a["rounds"])
	if a.has("laps"):
		r["laps"] = int(a["laps"])
	if a.has("phase"):
		r["start_phase"] = Phase.from_name(String(a["phase"]))
	if a.has("phase-time"):
		for k in ["draft_time", "build_time", "race_time", "score_time"]:
			r[k] = float(a["phase-time"])
	setup(ps, r)
	start()
	var t := String(a.get("autotest", ""))
	if not t.is_empty():
		get_tree().create_timer(float(t)).timeout.connect(_autotest_report)
	if a.has("quit-after"):
		get_tree().create_timer(float(a["quit-after"])).timeout.connect(get_tree().quit)


func _autotest_report() -> void:
	for p in players:
		var c := chariot_sync.get_chariot(p.slot) as Chariot
		if c:
			print("[TEST] CHARIOT %d %.2f %.2f progress=%.1f" % [p.slot, c.global_position.x,
				c.global_position.z, track.progress_at(c.global_position)])
