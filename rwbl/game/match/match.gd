class_name MatchMode
extends GameMode
## RWBL's GameMode: one match = 6-8 rounds of Draft -> Build -> Race -> Score (DESIGN §3, §9). Owner: C09.
## C02 STUB: setup + timer-driven phase loop + results. C09 adds early phase ends, Grand Circus, 30-point win,
## catch-up dealing (Draft), dropouts -> bots, MatchTuning.
## Scene: match.tscn. Its children are the match systems, fixed names (see CONTRACT below). Each system has
## `match_setup(m: MatchMode)`, called in SYSTEMS order on every peer from setup(); systems then react to
## GameEvents.phase_changed. Systems reach each other through the typed vars below (e.g. `m.track`).
## NET: setup() on every peer; start() and the phase loop on the host; phases are broadcast by RPC.
## Standalone (scene run directly, tests): CLI `--bots=N` `--no-human` `--phase=draft|build|race|score`
##   `--rounds=N` `--laps=N` `--phase-time=SEC` `--autotest=SEC` `--quit-after=SEC`. Offline = host.
## Public API: players, rules, phase, round_index, setup(), start(), local_slot(), slot_of_peer(peer),
##   get_player(slot), phase_time_left(), is_grand_circus(), signal finished (GameMode).
# CONTRACT: child node names Track, Items, Chariots, ChariotSync, Race, Draft, Build, Scoring, Combat, Bots,
#   Cameras, Hud. The match node is at the same path on every peer (RPCs depend on it).
# CONTRACT: rules keys: rounds, laps, win_score, draft_time, build_time, race_time, score_time, start_phase.

const SYSTEMS: Array[StringName] = [&"Track", &"ChariotSync", &"Race", &"Draft", &"Build", &"Scoring",
	&"Combat", &"Bots", &"Cameras", &"Hud"]
const DEFAULT_RULES := {"rounds": 6, "laps": 1, "win_score": 30, "draft_time": 10.0, "build_time": 25.0,
	"race_time": 90.0, "score_time": 10.0, "start_phase": Phase.DRAFT} # TUNE (C09 -> MatchTuning)

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


func _ready() -> void:
	GameEvents.phase_end_requested.connect(_on_phase_end_requested)
	if get_tree().current_scene == self:
		_standalone.call_deferred()


## GameMode: receive players + rules and set up every system. NET: every peer, same arguments.
func setup(p: Array[PlayerInfo], r: Dictionary) -> void:
	players = p
	rules = DEFAULT_RULES.duplicate()
	rules.merge(r, true)
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


## True in the final "Grand Circus" round (double points).
func is_grand_circus() -> bool:
	return round_index == int(rules.get("rounds", 6))


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or phase == Phase.NONE or phase == Phase.MATCH_OVER:
		return
	if NetClock.now() >= phase_end_time:
		_advance()


func _on_phase_end_requested(p: int) -> void:
	if multiplayer.is_server() and p == phase:
		_advance()


func _advance() -> void: # NET: host
	match phase:
		Phase.DRAFT: _enter_phase(Phase.BUILD, round_index)
		Phase.BUILD: _enter_phase(Phase.RACE, round_index)
		Phase.RACE: _enter_phase(Phase.SCORE, round_index)
		Phase.SCORE:
			if round_index >= int(rules["rounds"]):
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
	print("[Game] PHASE %s %d" % [Phase.name_of(p), r])
	GameEvents.phase_changed.emit(p, r)


func _finish() -> void: # NET: host
	var totals := scoring.get_totals()
	var order: Array[PlayerInfo] = players.duplicate()
	order.sort_custom(func(a: PlayerInfo, b: PlayerInfo) -> bool:
		return int(totals.get(a.slot, 0)) > int(totals.get(b.slot, 0)))
	var out: Array = []
	for i in order.size():
		var res := PlayerResult.new()
		res.slot = order[i].slot
		res.name = order[i].name
		res.score = int(totals.get(res.slot, 0))
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
