extends Item
## Column: solid marble pillar on ITEM_SOLID. Cart hit breaks the wheel on the side that hit it, horse hit
## stuns. Tag rule `slide_far` (heavy item on a slippery one, e.g. a column on oil): the next hit shoves the
## column, which then slides far before it stops (or leaves the road). Owner: C10.
## NET: hits on the host. The slide is sent once by RPC (start, direction, distance, duration, NetClock start)
##   and every peer animates it from NetClock.now(), so no snapshots are needed.

@onready var _body: AnimatableBody3D = $Body

var _slide_friction := -1.0 # < 0 = not on anything slippery
var _slide_from := Vector3.ZERO
var _slide_to := Vector3.ZERO
var _slide_t0 := 0.0
var _slide_dur := 0.0


func _ready() -> void:
	super._ready()
	_body.sync_to_physics = false
	_body.collision_layer = Layers.ITEM_SOLID
	_body.collision_mask = 0


## True while the column is sliding (any peer).
func is_sliding() -> bool:
	return _slide_dur > 0.0 and NetClock.now() < _slide_t0 + _slide_dur


func chariot_hit(chariot: Chariot, part: StringName, impact_speed: float) -> void:
	if part == &"cart":
		var right := chariot.global_basis.x # cart's right is close enough to the horses' right
		var side := ChariotSnapshot.WHEEL_RIGHT if (global_position - chariot.cart_global_position()).dot(right) > 0.0 \
			else ChariotSnapshot.WHEEL_LEFT
		chariot.damage_wheel(side, owner_slot)
	else:
		chariot.stun(Item.tuning().column_stun, owner_slot)
	report_hit(chariot)
	if _slide_friction > 0.0 and not is_sliding():
		_start_slide(chariot, impact_speed)


func interact(rule: TagRule, _other: Item) -> void:
	if rule.effect == &"slide_far" and def.has_tag(rule.tag_a):
		_slide_friction = float(rule.params.get("friction_mult", 0.2))


func _start_slide(chariot: Chariot, impact_speed: float) -> void:
	var t := Item.tuning()
	var dir := Vector3(chariot.velocity.x, 0.0, chariot.velocity.z)
	if dir.length() < 0.1:
		dir = chariot.get_forward()
	dir = dir.normalized()
	var v0 := maxf(impact_speed * t.column_push, 1.0)
	var decel := t.column_slide_decel * _slide_friction
	var dist := minf(v0 * v0 / (2.0 * decel), t.column_slide_max)
	var track := get_track()
	if track: # WHY: stop at the road edge instead of sliding through walls
		var half := track.track_width * 0.5 - def.footprint.x * 0.5
		var d := 0.0
		while d < dist:
			var nd := minf(d + 0.5, dist)
			if absf(track.lateral_offset(global_position + dir * nd)) > half:
				break
			d = nd
		dist = d
	if dist < 0.05:
		return
	var dur := 2.0 * dist / v0
	print("[Item] SLIDE %d %.1f m" % [uid, dist])
	_rpc_slide.rpc(global_position, global_position + dir * dist, NetClock.now(), dur)


@rpc("authority", "call_local", "reliable")
func _rpc_slide(from: Vector3, to: Vector3, t0: float, dur: float) -> void: # NET: every peer
	_slide_from = from
	_slide_to = to
	_slide_t0 = t0
	_slide_dur = dur


func _physics_process(_delta: float) -> void:
	if _slide_dur <= 0.0:
		return
	var s := clampf((NetClock.now() - _slide_t0) / _slide_dur, 0.0, 1.0)
	global_position = _slide_from.lerp(_slide_to, 1.0 - (1.0 - s) * (1.0 - s)) # constant deceleration
	if s >= 1.0:
		_slide_dur = 0.0
