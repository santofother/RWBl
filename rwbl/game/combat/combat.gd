class_name Combat
extends Node
## Chariot-vs-chariot collisions, deaths, respawn and the crow spectator (DESIGN §4, §6). Owner: C12.
## Rams (host): on `Chariot.hit` between two chariots, the one with more mass × speed along the impact wins
##   (by `win_margin`). Loser's cart hit → `damage_wheel(side, winner)` (side from the impact point; a cart
##   with no wheels left dies, cause &"wheel"). Loser's horses hit → `stun(horse_stun)`. Each pair is immune
##   for `pair_immunity` s afterwards, so one scrape is one hit. Only side-on cart hits (`side_hit_min`) break
##   wheels, so rear-end taps don't punish the leader. Crawling on no wheels for `crawl_wreck_time` s wrecks the
##   chariot (kill &"wheel", credited to whoever broke the last wheel) so it respawns.
## Deaths (host): forwards `Chariot.died` to GameEvents (chariot_died; kill when another player caused it
##   without an item; self_kill for an item the victim placed). Respawn after `respawn_delay` (+ `pit_penalty`
##   for &"pit") at `track.respawn_transform(death progress − respawn_back)`, then `chariot_respawned`.
## Crow (all peers know who): a slot that finished the race, or died with < `crow_death_time_left` s of race
##   left (no respawn then), is a crow until the next race. Every `crow_drop_cooldown` s it may drop one
##   `mud_patch` (owner = the crow, so Scoring counts it): local player presses `action` (aimed at the screen
##   centre on the track; the camera is C13's spectator mode), bot crows drop ahead of the leader. Crow drops
##   are removed when the race phase ends.
## Visuals (every peer, from snapshot state): a newly broken wheel pops off (DamageFx.wheel_pop); a death
##   bursts confetti and hides the chariot until it respawns.
## Numbers: CombatTuning (`combat/default_tuning.tres`, F2 "Combat").
## NET: rams, deaths, respawn, crow decisions on the host; crow state + drops broadcast by RPC; visuals on all.
## Public API: match_setup(m), register_chariot(slot, c), is_crow(slot), crows(), crow_cooldown_left(slot),
##   request_crow_drop(pos), crow_drop(slot, pos) -> uid (host), set_crow(slot, on) (host), `tuning`,
##   `respawn_delay` (read-only), `track`, `spawner`, signal crow_changed.
## Logs: `[Combat] RAM <winner> > <loser> <part> <what>`, `[Combat] DIED`, `[Combat] RESPAWN`, `[Combat] CROW`,
##   `[Combat] CROW_DROP <slot> <uid>`.

## all · a slot became a crow (on) or stopped being one (next race).
signal crow_changed(slot: int, on: bool)

const TUNING_DEFAULT := preload("res://game/combat/default_tuning.tres")
## The minor hazard a crow drops.
const CROW_ITEM := &"mud_patch"
const BOTH_WHEELS := ChariotSnapshot.WHEEL_LEFT | ChariotSnapshot.WHEEL_RIGHT

## Combat numbers. Shared resource: the F2 panel edits it live.
var tuning: CombatTuning = TUNING_DEFAULT
## Seconds a dead chariot waits before respawn (without the pit penalty).
var respawn_delay: float:
	get:
		return tuning.respawn_delay
## Track for respawn points and crow drops (set by match_setup; tests set it directly).
var track: Track
## Host: spawns a crow drop. func(slot: int, item_id: StringName, xform: Transform3D) -> int uid (-1 = failed).
## Default: BuildPhase.spawn_extra. Tests replace it.
var spawner: Callable

var _m: MatchMode
var _time := 0.0
var _chariots: Dictionary = {} # slot -> Chariot
var _prev_vel: Dictionary = {} # slot -> velocity before this tick's steps (host)
var _pair_cd: Dictionary = {} # "a:b" -> seconds of immunity left (host)
var _respawn_at: Dictionary = {} # slot -> _time to respawn (host)
var _crawl: Dictionary = {} # slot -> [seconds on no wheels, last wheel breaker] (host)
var _death_progress: Dictionary = {} # slot -> track progress at death (host)
var _crows: Dictionary = {} # slot -> true (all peers)
var _crow_ready_at: Dictionary = {} # slot -> _time of the next allowed drop (all peers, own clock)
var _crow_items: Array[int] = [] # uids of crow drops this race (all peers)
var _seen_wheels: Dictionary = {} # slot -> wheel bits already shown (visuals)
var _seen_dead: Dictionary = {} # slot -> dead already shown (visuals)


func _ready() -> void:
	process_physics_priority = -100 # WHY: record pre-step velocities before ChariotSync steps the chariots
	var panel := get_node_or_null(^"/root/TuningPanel")
	if panel:
		panel.register(tuning, "Combat")


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	track = m.track
	if not spawner.is_valid():
		spawner = m.build.spawn_extra
	m.chariot_sync.chariot_added.connect(register_chariot)
	for slot: int in m.chariot_sync.get_chariots():
		register_chariot(slot, m.chariot_sync.get_chariot(slot))
	GameEvents.phase_changed.connect(_on_phase_changed)
	GameEvents.chariot_finished.connect(func(slot: int, _p: int, _t: float) -> void: set_crow(slot, true))


## Start handling a chariot's hits and deaths (every peer; the handlers act on the host only).
func register_chariot(slot: int, node: Node3D) -> void:
	var c := node as Chariot
	if c == null:
		return
	_chariots[slot] = c
	if not c.died.is_connected(_on_died):
		c.died.connect(_on_died.bind(slot))
		c.hit.connect(_on_hit.bind(slot))


## True if `slot` is a crow this race (every peer).
func is_crow(slot: int) -> bool:
	return _crows.has(slot)


## Slots that are crows right now.
func crows() -> Array:
	return _crows.keys()


## Seconds until `slot` may drop again (0 = ready). Every peer (HUD).
func crow_cooldown_left(slot: int) -> float:
	return maxf(0.0, float(_crow_ready_at.get(slot, 0.0)) - _time)


## Local crow player: drop mud near `pos` (the host clamps it onto the track).
func request_crow_drop(pos: Vector3) -> void:
	if multiplayer.is_server():
		crow_drop(_m.local_slot() if _m else -1, pos)
	else:
		_rpc_request_crow_drop.rpc_id(1, pos)


## Host: crow `slot` drops a mud patch near `pos`. Returns the item uid or -1 (not a crow, cooling down,
## no-build zone, no track).
func crow_drop(slot: int, pos: Vector3) -> int: # NET: host
	if not multiplayer.is_server() or not is_crow(slot) or crow_cooldown_left(slot) > 0.0 or track == null \
			or not spawner.is_valid():
		return -1
	var p := track.progress_at(pos)
	var base := track.transform_at(p)
	var half := track.track_width * 0.5 - 3.0
	var lat := clampf(track.lateral_offset(pos), -half, half)
	var xf := Transform3D(base.basis, base.origin + base.basis.x * lat)
	if track.is_in_no_build_zone(xf.origin, 3.5):
		return -1
	var uid: int = spawner.call(slot, CROW_ITEM, xf)
	if uid >= 0:
		_rpc_crow_dropped.rpc(slot, uid)
	return uid


## Host: make `slot` a crow (on) or a driver again. Broadcast to every peer.
func set_crow(slot: int, on: bool) -> void: # NET: host
	if multiplayer.is_server() and is_crow(slot) != on:
		_rpc_crow.rpc(slot, on)


# ---------------------------------------------------------------- host simulation

func _physics_process(delta: float) -> void:
	_time += delta
	if not multiplayer.is_server():
		return
	for slot: int in _chariots.keys():
		var c: Chariot = _chariots[slot]
		if not is_instance_valid(c):
			_chariots.erase(slot)
			continue
		_prev_vel[slot] = c.velocity
		if c.wheel_state == BOTH_WHEELS and not c.dead and not c.frozen:
			var cr: Array = _crawl.get(slot, [0.0, -1])
			cr[0] = float(cr[0]) + delta
			_crawl[slot] = cr
			if cr[0] >= tuning.crawl_wreck_time: # WHY: a crawl lasts "until respawn"; never sideline anyone for long
				_crawl.erase(slot)
				c.kill(&"wheel", int(cr[1]))
		elif _crawl.has(slot) and c.wheel_state != BOTH_WHEELS:
			_crawl.erase(slot)
	for k: String in _pair_cd.keys():
		_pair_cd[k] = float(_pair_cd[k]) - delta
		if _pair_cd[k] <= 0.0:
			_pair_cd.erase(k)
	for slot: int in _respawn_at.keys():
		if _time >= float(_respawn_at[slot]):
			_respawn(slot)
	if tuning.bot_crows_drop and _m and _m.phase == Phase.RACE:
		for slot: int in _crows:
			var p := _m.get_player(slot)
			if p and p.is_bot and crow_cooldown_left(slot) <= 0.0:
				var pos: Variant = _bot_drop_pos()
				if pos != null:
					crow_drop(slot, pos)


func _on_hit(part: StringName, other: Node, _speed: float, slot: int) -> void: # NET: host
	if not multiplayer.is_server():
		return
	var a: Chariot = _chariots.get(slot)
	var b := Chariot.find_chariot(other)
	if a == null or b == null or b == a or a.dead or b.dead:
		return
	var key := "%d:%d" % [mini(a.slot, b.slot), maxi(a.slot, b.slot)]
	if _pair_cd.has(key):
		return
	var part_b := b.part_of(other)
	var pa := a.global_position if part == &"horses" else a.cart_global_position()
	var pb := b.global_position if part_b == &"horses" else b.cart_global_position()
	var dir := pb - pa
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else a.get_forward()
	var va: Vector3 = _prev_vel.get(a.slot, a.velocity)
	var vb: Vector3 = _prev_vel.get(b.slot, b.velocity)
	if va.dot(dir) - vb.dot(dir) < tuning.min_ram_speed:
		return
	_pair_cd[key] = tuning.pair_immunity
	var fa := a.tuning.total_mass() * maxf(va.dot(dir), 0.0)
	var fb := b.tuning.total_mass() * maxf(-vb.dot(dir), 0.0)
	if fa >= fb * tuning.win_margin:
		_damage(b, part_b, a, pa)
	elif fb >= fa * tuning.win_margin:
		_damage(a, part, b, pb)
	else:
		print("[Combat] RAM %d = %d even" % [a.slot, b.slot])


func _damage(loser: Chariot, part: StringName, winner: Chariot, from: Vector3) -> void: # NET: host
	var what := ""
	if part == &"cart":
		if loser.wheel_state == BOTH_WHEELS:
			what = "wrecked"
			loser.kill(&"wheel", winner.slot)
		else:
			var cart := loser.get_node(^"Cart") as Node3D
			var to := from - loser.cart_global_position()
			to.y = 0.0
			if absf(to.normalized().dot(cart.global_basis.x)) < tuning.side_hit_min:
				print("[Combat] RAM %d > %d cart glancing" % [winner.slot, loser.slot])
				return
			var right := to.dot(cart.global_basis.x) > 0.0
			var side := ChariotSnapshot.WHEEL_RIGHT if right else ChariotSnapshot.WHEEL_LEFT
			if loser.wheel_state & side:
				side = BOTH_WHEELS & ~side
			what = "wheel_%s" % ("right" if side == ChariotSnapshot.WHEEL_RIGHT else "left")
			loser.damage_wheel(side, winner.slot)
			if loser.wheel_state == BOTH_WHEELS:
				_crawl[loser.slot] = [0.0, winner.slot]
	else:
		what = "stun"
		loser.stun(tuning.horse_stun, winner.slot)
	print("[Combat] RAM %d > %d %s %s" % [winner.slot, loser.slot, part, what])


func _on_died(cause: StringName, source_slot: int, item_uid: int, slot: int) -> void: # NET: host
	if not multiplayer.is_server():
		return
	GameEvents.chariot_died.emit(slot, cause, source_slot, item_uid)
	if source_slot == slot and item_uid >= 0:
		GameEvents.self_kill.emit(slot, item_uid)
	elif source_slot >= 0 and source_slot != slot and item_uid < 0:
		GameEvents.kill.emit(source_slot, slot, cause)
	var c: Chariot = _chariots.get(slot)
	if c and track:
		_death_progress[slot] = track.progress_at(c.global_position)
	var crow := _m != null and _m.phase == Phase.RACE and _m.phase_time_left() < tuning.crow_death_time_left
	if crow:
		set_crow(slot, true)
	else:
		_respawn_at[slot] = _time + tuning.respawn_delay + (tuning.pit_penalty if cause == &"pit" else 0.0)
	print("[Combat] DIED %d %s by %d item %d%s" % [slot, cause, source_slot, item_uid, " -> crow" if crow else ""])


func _respawn(slot: int) -> void: # NET: host
	_respawn_at.erase(slot)
	var c: Chariot = _chariots.get(slot)
	if c == null or not c.dead:
		return
	var xf := c.global_transform
	if track:
		xf = track.respawn_transform(float(_death_progress.get(slot, 0.0)) - tuning.respawn_back)
	c.respawn(xf)
	if _m:
		_m.race.notify_teleport(slot)
	print("[Combat] RESPAWN %d" % slot)
	GameEvents.chariot_respawned.emit(slot)


func _bot_drop_pos() -> Variant: # NET: host. Vector3 ahead of the leading racer, or null
	var best := -1
	var best_p := -INF
	for slot: int in _chariots:
		var c: Chariot = _chariots[slot]
		if is_crow(slot) or c.dead or _m.race.is_finished(slot):
			continue
		var p := _m.race.progress_of(slot)
		if p > best_p:
			best_p = p
			best = slot
	if best < 0:
		return null
	var xf := track.transform_at(best_p + tuning.crow_bot_lead)
	return xf.origin + xf.basis.x * randf_range(-3.0, 3.0)


func _on_phase_changed(phase: int, _round: int) -> void: # NET: every peer
	if phase == Phase.RACE:
		for slot: int in _crows.keys():
			_crows.erase(slot)
			crow_changed.emit(slot, false)
		_crow_ready_at.clear()
		_respawn_at.clear()
		_pair_cd.clear()
	elif not _crow_items.is_empty():
		for uid in _crow_items:
			var it := _m.items_root.get_node_or_null(NodePath("Item%d" % uid)) if _m else null
			if it:
				it.queue_free()
				GameEvents.item_removed.emit(uid)
		_crow_items.clear()


# ---------------------------------------------------------------- local input and visuals (every peer)

func _unhandled_input(event: InputEvent) -> void:
	if _m and event.is_action_pressed(&"action") and is_crow(_m.local_slot()):
		var pos: Variant = _aim_point()
		if pos != null:
			request_crow_drop(pos)


func _aim_point() -> Variant: # where the screen centre looks at the ground, else ahead of the leader
	var cam := get_viewport().get_camera_3d()
	if cam:
		var centre := get_viewport().get_visible_rect().size * 0.5
		var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(centre),
			cam.project_ray_normal(centre))
		if hit != null:
			return hit
	return _bot_drop_pos() if multiplayer.is_server() else null


func _process(_delta: float) -> void:
	for slot: int in _chariots:
		var c: Chariot = _chariots[slot]
		if not is_instance_valid(c):
			continue
		var w := c.wheel_state
		var fresh := w & ~int(_seen_wheels.get(slot, 0))
		for side in [ChariotSnapshot.WHEEL_LEFT, ChariotSnapshot.WHEEL_RIGHT]:
			if fresh & side:
				DamageFx.wheel_pop(self, c, side, tuning)
				print("[Combat] FX wheel %d %d" % [slot, side])
		_seen_wheels[slot] = w
		if c.dead != bool(_seen_dead.get(slot, false)):
			_seen_dead[slot] = c.dead
			c.visible = not c.dead
			if c.dead:
				DamageFx.burst(self, c.global_position, _team_color(c))
				print("[Combat] FX burst %d" % slot)


static func _team_color(c: Chariot) -> Color:
	var mi := c.get_node_or_null(^"Horses") as GeometryInstance3D
	var m := mi.material_override as StandardMaterial3D if mi else null
	return m.albedo_color if m else Color(1.0, 0.85, 0.3)


# ---------------------------------------------------------------- RPCs

@rpc("authority", "call_local", "reliable")
func _rpc_crow(slot: int, on: bool) -> void: # NET: every peer
	if on:
		_crows[slot] = true
	else:
		_crows.erase(slot)
	print("[Combat] CROW %d %s" % [slot, "on" if on else "off"])
	crow_changed.emit(slot, on)


@rpc("authority", "call_local", "reliable")
func _rpc_crow_dropped(slot: int, uid: int) -> void: # NET: every peer
	_crow_items.append(uid)
	_crow_ready_at[slot] = _time + tuning.crow_drop_cooldown
	print("[Combat] CROW_DROP %d %d" % [slot, uid])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_crow_drop(pos: Vector3) -> void: # NET: host
	if multiplayer.is_server() and _m:
		crow_drop(_m.slot_of_peer(multiplayer.get_remote_sender_id()), pos)
