class_name Track
extends Node3D
## The race course: a chain of track pieces from a start line to a separate finish line (DESIGN §5.6, C22),
## plus surfaces, start grid, checkpoints and build zones. Owner: C22 (was C05/C19).
## The base course is `course_def` (default `default_course.tres`: start, straights, corners, finish). Each piece
## is a TrackPiece scene; the next piece starts at the previous one's `end_transform()`. The centre line, road,
## walls (pit: slab only), end caps, start line and finish gate are generated from the chain. The start line is at
## this node's origin heading -Z.
## NET: identical on every peer (static data, pieces applied in the host's order, item surface patches).
## Public API (positions world space, `progress` = metres along the centre line from the start line; negative
## behind it on the grid, `length()` = progress of the finish line, more than that in the run-off):
##   track_width, length(), get_center_curve(), progress_at(pos), point_at(progress), transform_at(progress),
##   lateral_offset(pos), is_on_track(pos), surface_at(pos), register_surface_patch(node, surface, half),
##   unregister_surface_patch(node), start_transform(grid_index), checkpoint_count(), checkpoint_progress(i),
##   respawn_transform(progress), is_in_no_build_zone(pos, radius), get_bounds(), finish_progress(),
##   finish_transform().
## Course (C22): course() -> piece ids in order, joints() -> progress of every joint (n + 1 values, the course's
##   two open ends included), check_insert(def_id, joint, flip) -> Insert.*, insert_piece(def_id, joint, flip, uid)
##   -> bool (checks), apply_insert(uid, def_id, joint, flip) (every peer, no checks), check_remove(uid),
##   remove_piece(uid) (every peer), has_piece(uid), piece_at(pos), pieces() -> [{uid id start end flip joint}],
##   preview_insert(def_id, joint, flip) -> {code, course, piece} (world points, build ghost), last_change(),
##   static insert_text(code), static points_to_curve(points, tangents).
## Loops (C21): has_loops(), loop_zones() -> [Vector2(start, end) progress], loop_index_at(progress) -> int (-1 =
##   none), road_transform_at(progress) (full 3D road frame: -Z along the road, +Y = road normal, so upside down at
##   a loop's top). Inside a loop zone transform_at() returns that same frame; everywhere else it is flat as
##   before. No items, respawns or crow drops inside a loop (is_in_no_build_zone, respawn_transform).
## Height (C20): pieces may climb, dip and bank (hill, crest, banked turn); joints stay level and height pieces end
##   where they started, so the finish stays at y = 0. has_height() -> bool. transform_at() returns the road
##   frame everywhere (+Y = road normal, -Z along the road, so it pitches on slopes and rolls on banks): items
##   placed with it sit on the road surface. Without `pit` the road gets a WORLD floor too once the course has
##   height (the flat ground stays below). road_ground(pos) -> [height, normal] (exact road surface, for wheels),
##   is_road_body(body).
##   Joint k is the boundary before piece k. Inserting is allowed at joints 1 .. n-1 (after the start piece, up to
##   just before the finish piece). Everything after the joint moves rigidly; last_change() gives that transform.
# CONTRACT: API above. Progress increases in the driving direction; the start line is progress 0 and never moves.
# CONTRACT: the start and finish pieces can't be removed or have anything inserted inside them.

## Drivable width in metres.
@export var track_width := 14.0 # TUNE
## True = the road floats over a bottomless pit: no walls, no ground, falling kills (Chariot FALL_KILL_Y).
## track.tscn sets this; Track.new() in tests keeps a flat ground and walls.
@export var pit := false
## Thickness of the floating road slab (m), pit mode only.
@export var slab_depth := 2.0
## Wall height (m) and thickness (m).
@export var wall_height := 1.6 # TUNE
@export var wall_thickness := 0.8 # TUNE
## Round 1's course (piece ids from start to finish).
@export var course_def: CourseDef = preload("res://game/track/default_course.tres")

## No items closer than NO_BUILD_AFTER m after the start line (and nowhere behind it, the grid), nor within
## NO_BUILD_FINISH m of the finish line (and nowhere after it, the run-off).
const NO_BUILD_AFTER := 10.0
const NO_BUILD_FINISH := 10.0
const CHECKPOINTS := 8
const GRID_ROW_GAP := 5.0
const GRID_FIRST_ROW := 5.0
const MESH_STEP := 2.0 # metres between road/wall mesh slices

## check_insert() / check_remove() codes.
enum Insert { OK, UNKNOWN, BAD_JOINT, SELF_INTERSECT, NOT_FOUND }
const INSERT_TEXT: Array[String] = ["OK", "Not a track piece", "Pieces go between two pieces, or just before the finish",
	"The course would run into itself", "No such piece"]
const SELF_ARC := 24.0 # m along the road under which two points are neighbours, not a crossing
const CAP_HEIGHT := 3.0 # m, the walls closing both open ends of the road
const CROSS_CLEARANCE := 5.0 # m (C21): two road parts this far apart in height don't cross (the loop's sides)
const LOOP_MARGIN := 4.0 # m (C21): no items / respawns this close to a loop

var _curve: Curve3D
var _course: Array[Dictionary] = [] # {uid, id, flip} in driving order; base pieces have uid -1
var _shapes: Dictionary = {} # "id|flip" -> {pts, tans, end, len, line, flippable} in piece space
var _auto_uid := 1000000
var _visuals: Array[Node] = []
var _bounds_local := AABB()
var _patches: Dictionary = {} # Node3D -> [surface, half_extents]
var _frames: Array[Transform3D] = [] # local frame at every joint (n + 1)
var _joint_off := PackedFloat32Array() # curve offset of every joint (n + 1)
var _start_off := 0.0 # curve offset of the start line
var _finish_off := 0.0 # curve offset of the finish line
var _curve_len := 0.0
var _last_change: Dictionary = {}
var _dense_off := PackedFloat32Array() # C21: curve offset of every composed point
var _dense_up := PackedVector3Array() # C21: road normal at every composed point (local)
var _loop_zones: Array[Vector2] = [] # C21: progress spans with loop flags
var _has_height := false # C20: some point off y = 0 or tilted
var _low_y := 0.0 # C20: lowest road edge (local), <= 0
var _road_bodies: Array[Object] = [] # C20: StaticBody3Ds whose collision is the road surface


func _ready() -> void:
	_course.clear()
	if course_def:
		for id: StringName in course_def.pieces:
			_course.append({"uid": -1, "id": id, "flip": false})
	if _course.size() < 2:
		push_error("[Track] course needs at least a start and a finish piece")
	_recompose()
	_build_visuals()


## Progress of the finish line (m from the start line).
func length() -> float:
	return _finish_off - _start_off


## Same as length(): where the finish line is.
func finish_progress() -> float:
	return length()


## Transform on the finish line, -Z = driving direction.
func finish_transform() -> Transform3D:
	return transform_at(length())


## The centre line in this node's local space (curve offset = progress + the start line's offset). Don't modify.
func get_center_curve() -> Curve3D:
	return _curve


## Progress (m from the start line) of the centre-line point closest to `pos`.
func progress_at(pos: Vector3) -> float:
	return _curve.get_closest_offset(to_local(pos)) - _start_off


## Centre-line point at `progress` (clamped to the two open ends).
func point_at(progress: float) -> Vector3:
	return to_global(_curve.sample_baked(_off(progress)))


## Transform on the centre line at `progress`, -Z facing the driving direction, +Y = road normal (C20: the road
## frame, same as road_transform_at(); UP on level road, pitched on slopes, rolled on banks, upside down at a
## loop's top).
func transform_at(progress: float) -> Transform3D:
	return road_transform_at(progress)


## Signed distance from the centre line (+ = right of the driving direction).
func lateral_offset(pos: Vector3) -> float:
	var t := transform_at(progress_at(pos))
	return (pos - t.origin).dot(t.basis.x)


## True if `pos` is on the drivable surface.
func is_on_track(pos: Vector3) -> bool:
	return absf(lateral_offset(pos)) <= track_width * 0.5


## Surface at `pos` (Surface.*): item patches first (last registered wins), then track / off-track.
func surface_at(pos: Vector3) -> StringName:
	var found: StringName = &""
	for n: Node3D in _patches.keys():
		if not is_instance_valid(n):
			_patches.erase(n)
			continue
		var local := n.global_transform.affine_inverse() * pos
		var half: Vector2 = _patches[n][1]
		if absf(local.x) <= half.x and absf(local.z) <= half.y:
			found = _patches[n][0]
	if found != &"":
		return found
	return Surface.NORMAL if is_on_track(pos) else Surface.OFFTRACK


## Make a rectangle around `node` (half extents x/z in node space) report `surface`. NET: every peer.
func register_surface_patch(node: Node3D, surface: StringName, half_extents: Vector2) -> void:
	_patches[node] = [surface, half_extents]


## Remove a patch added with register_surface_patch().
func unregister_surface_patch(node: Node3D) -> void:
	_patches.erase(node)


## Start grid spot `grid_index` (0 = pole), two per row behind the start line, facing forward.
func start_transform(grid_index: int) -> Transform3D:
	var row := grid_index / 2
	var t := transform_at(-(GRID_FIRST_ROW + row * GRID_ROW_GAP))
	var side := -1.0 if grid_index % 2 == 0 else 1.0
	t.origin += t.basis.x * side * track_width * 0.22
	return t


## Number of checkpoints (respawn spots, spread evenly from the start line to the finish line).
func checkpoint_count() -> int:
	return CHECKPOINTS


## Progress of checkpoint `i` (0 = start line).
func checkpoint_progress(i: int) -> float:
	return length() * float(posmod(i, CHECKPOINTS)) / CHECKPOINTS


## Safe spot to respawn near `progress` (centre line, facing forward). C21: never inside or right after a loop:
## moved back to LOOP_MARGIN + 2 m before the loop's entry.
func respawn_transform(progress: float) -> Transform3D:
	for z: Vector2 in _loop_zones:
		if progress > z.x - LOOP_MARGIN - 2.0 and progress < z.y + LOOP_MARGIN:
			progress = z.x - LOOP_MARGIN - 2.0
	return transform_at(progress)


## True if a circle at `pos` with `radius` touches the start or finish no-build zone, or a loop (C21).
func is_in_no_build_zone(pos: Vector3, radius: float = 0.0) -> bool:
	var p := progress_at(pos)
	for z: Vector2 in _loop_zones:
		if p > z.x - LOOP_MARGIN - radius and p < z.y + LOOP_MARGIN + radius:
			return true
	return p <= NO_BUILD_AFTER + radius or p >= length() - NO_BUILD_FINISH - radius


# ---------------------------------------------------------------- loops (C21)

## True if the course has at least one loop.
func has_loops() -> bool:
	return not _loop_zones.is_empty()


## Progress spans [start, end] of every loop (where the road leaves the ground), in driving order.
func loop_zones() -> Array[Vector2]:
	return _loop_zones


## Index into loop_zones() of the loop at `progress`, or -1.
func loop_index_at(progress: float) -> int:
	for i in _loop_zones.size():
		if progress >= _loop_zones[i].x and progress <= _loop_zones[i].y:
			return i
	return -1


## Full road frame at `progress` (world): -Z along the road (climbs in a loop), +Y = road normal, +X = right.
## Equals transform_at() on flat road.
func road_transform_at(progress: float) -> Transform3D:
	return global_transform * _local_road_t(_off(progress))


## C20: true if any part of the course leaves y = 0 or tilts (hills, crests, banked turns, loops).
func has_height() -> bool:
	return _has_height


## C20: the exact road surface under `pos` (world): [height (float), normal (Vector3)], from the road frame at
## progress_at(pos). Smooth, unlike the road's triangle mesh (a banked road's quads are twisted). Off the road
## the plane just continues.
func road_ground(pos: Vector3) -> Array:
	var xf := road_transform_at(progress_at(pos))
	var n := xf.basis.y
	if n.y < 0.2:
		return [xf.origin.y, n]
	# plane through xf.origin with normal n, solved for y at pos.x / pos.z
	var y := xf.origin.y - (n.x * (pos.x - xf.origin.x) + n.z * (pos.z - xf.origin.z)) / n.y
	return [y, n]


## C20: true if `body` is the road's own collision (pit slab / RoadFloor), not the flat ground or an item.
func is_road_body(body: Object) -> bool:
	return body != null and _road_bodies.has(body)


## World-space box containing the whole course (build camera, validation grid).
func get_bounds() -> AABB:
	return AABB(global_position + _bounds_local.position, _bounds_local.size)


# ---------------------------------------------------------------- course (C22)

## Piece ids in driving order, start piece first, finish piece last.
func course() -> Array[StringName]:
	var out: Array[StringName] = []
	for e: Dictionary in _course:
		out.append(e["id"])
	return out


## Progress of every joint: joints()[k] = start of piece k; the last value is the far end of the finish piece.
func joints() -> Array[float]:
	var out: Array[float] = []
	for o: float in _joint_off:
		out.append(o - _start_off)
	return out


## Can `def_id` go in at joint `joint`? Returns an Insert code. NET: host (authoritative) and clients (ghost).
func check_insert(def_id: StringName, joint: int, flip := false) -> int:
	if not _is_card(def_id):
		return Insert.UNKNOWN
	if joint < 1 or joint > _course.size() - 1:
		return Insert.BAD_JOINT
	var trial := _course.duplicate()
	trial.insert(joint, {"uid": -2, "id": def_id, "flip": _flip_ok(def_id, flip)})
	var o := _compose(trial)
	if o.is_empty():
		return Insert.UNKNOWN
	return Insert.SELF_INTERSECT if _self_intersects(o) else Insert.OK


## Validate (check_insert) and, if OK, insert. `uid` -1 = pick one. NET: host validates; peers use apply_insert().
func insert_piece(def_id: StringName, joint: int, flip := false, uid := -1) -> bool:
	if check_insert(def_id, joint, flip) != Insert.OK:
		return false
	apply_insert(uid, def_id, joint, flip)
	return true


## Insert without checks (every peer applies what the host validated, in the same order). Returns the uid used.
func apply_insert(uid: int, def_id: StringName, joint: int, flip := false) -> int:
	if uid < 0:
		uid = _auto_uid
		_auto_uid += 1
	joint = clampi(joint, 1, _course.size() - 1)
	var old_frame := _frames[joint]
	var from := float(_joint_off[joint]) - _start_off
	_course.insert(joint, {"uid": uid, "id": def_id, "flip": _flip_ok(def_id, flip)})
	_recompose()
	var delta := _frames[joint + 1] * old_frame.affine_inverse()
	_last_change = {"kind": &"insert", "uid": uid, "from": from, "to": from, "delta": _to_world(delta),
		"piece_from": float(_joint_off[joint]) - _start_off, "piece_to": float(_joint_off[joint + 1]) - _start_off}
	print("[Track] INSERT %d %s at joint %d flip=%s length %.1f" % [uid, def_id, joint, _course[joint]["flip"],
		length()])
	_refresh()
	return uid


## Could piece `uid` be removed (the gap closed)? Returns an Insert code (NOT_FOUND if there is no such piece).
func check_remove(uid: int) -> int:
	var i := _index_of(uid)
	if uid < 0 or i < 0:
		return Insert.NOT_FOUND
	var trial := _course.duplicate()
	trial.remove_at(i)
	return Insert.SELF_INTERSECT if _self_intersects(_compose(trial)) else Insert.OK


## Remove placed piece `uid` and close the gap (everything after it moves back). False if there is no such piece.
## NET: every peer, after the host checked check_remove().
func remove_piece(uid: int) -> bool:
	var i := _index_of(uid)
	if uid < 0 or i < 0:
		return false
	var from := float(_joint_off[i]) - _start_off
	var to := float(_joint_off[i + 1]) - _start_off
	var next_frame := _frames[i + 1]
	_course.remove_at(i)
	_recompose()
	var delta := _frames[i] * next_frame.affine_inverse()
	_last_change = {"kind": &"remove", "uid": uid, "from": from, "to": to, "delta": _to_world(delta),
		"piece_from": from, "piece_to": from}
	print("[Track] REMOVE %d length %.1f" % [uid, length()])
	_refresh()
	return true


## What the last apply_insert()/remove_piece() did, for moving items: {kind, uid, from, to (old progress: the joint,
## or the removed piece's span), delta (world Transform3D for everything that was after `to`), piece_from,
## piece_to (new progress span of the inserted piece)}. Empty before the first change.
func last_change() -> Dictionary:
	return _last_change


## True if a placed piece with this uid is in the course.
func has_piece(uid: int) -> bool:
	return uid >= 0 and _index_of(uid) >= 0


## uid of the placed piece whose road covers `pos`, or -1 (base pieces have no uid).
func piece_at(pos: Vector3) -> int:
	if not is_on_track(pos):
		return -1
	var p := progress_at(pos)
	for e: Dictionary in pieces():
		if p >= float(e["start"]) and p <= float(e["end"]):
			return int(e["uid"])
	return -1


## Every placed piece in driving order: {uid, id, start, end (progress), flip, joint (its index in course())}.
func pieces() -> Array:
	var out: Array = []
	for i in _course.size():
		var e: Dictionary = _course[i]
		if int(e["uid"]) < 0:
			continue
		out.append({"uid": e["uid"], "id": e["id"], "start": float(_joint_off[i]) - _start_off,
			"end": float(_joint_off[i + 1]) - _start_off, "flip": e["flip"], "joint": i})
	return out


## Build ghost: the course as it would be with `def_id` at `joint`: {code (Insert.*), course (world centre-line
## points of the whole new course), piece (world points of the new piece only)}. Empty point arrays if unknown.
func preview_insert(def_id: StringName, joint: int, flip := false) -> Dictionary:
	var out := {"code": check_insert(def_id, joint, flip), "course": PackedVector3Array(), "piece": PackedVector3Array()}
	if out["code"] == Insert.UNKNOWN or out["code"] == Insert.BAD_JOINT:
		return out
	var trial := _course.duplicate()
	trial.insert(joint, {"uid": -2, "id": def_id, "flip": _flip_ok(def_id, flip)})
	var o := _compose(trial)
	var pos: PackedVector3Array = o["pos"]
	var own: PackedInt32Array = o["own"]
	var all := PackedVector3Array()
	var mine := PackedVector3Array()
	for k in pos.size():
		var w := to_global(pos[k])
		all.append(w)
		if own[k] == joint or (k + 1 < pos.size() and own[k + 1] == joint):
			mine.append(w)
	out["course"] = all
	out["piece"] = mine
	return out


## True if `def_id` is a piece card whose R (flip) does something.
func is_flippable(def_id: StringName) -> bool:
	var sh := _shape(def_id, false)
	return not sh.is_empty() and bool(sh["flippable"])


## Player-facing text for an Insert code.
static func insert_text(code: int) -> String:
	return INSERT_TEXT[code] if code >= 0 and code < INSERT_TEXT.size() else "Rejected"


## Smooth Curve3D through `points` with unit `tangents` (cubic Hermite handles).
static func points_to_curve(points: PackedVector3Array, tangents: PackedVector3Array) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = 0.5
	var n := points.size()
	for i in n:
		var hp := points[i].distance_to(points[i - 1]) if i > 0 else 0.0
		var hn := points[i + 1].distance_to(points[i]) if i < n - 1 else 0.0
		c.add_point(points[i], -tangents[i] * hp / 3.0, tangents[i] * hn / 3.0)
	return c


func _is_card(def_id: StringName) -> bool:
	var d := ItemDB.get_def(def_id)
	return d != null and d.is_piece() and not _shape(def_id, false).is_empty()


func _flip_ok(def_id: StringName, flip: bool) -> bool:
	return flip and is_flippable(def_id)


func _index_of(uid: int) -> int:
	for i in _course.size():
		if int(_course[i]["uid"]) == uid:
			return i
	return -1


func _off(progress: float) -> float:
	return clampf(progress + _start_off, 0.0, _curve_len)


func _to_world(local: Transform3D) -> Transform3D:
	return global_transform * local * global_transform.affine_inverse()


## Piece-space shape of `id` (a card id or a scene name in pieces/), mirrored if `flip`:
## {pts, tans, end (Transform3D), len, line, flippable}. Cached. Empty if there is no TrackPiece scene.
func _shape(id: StringName, flip: bool) -> Dictionary:
	var key := "%s|%s" % [id, flip]
	if _shapes.has(key):
		return _shapes[key]
	var out := {}
	var scene: PackedScene = null
	var d := ItemDB.get_def(id)
	if d and d.piece:
		scene = d.piece
	elif ResourceLoader.exists("res://game/track/pieces/%s.tscn" % id):
		scene = load("res://game/track/pieces/%s.tscn" % id) as PackedScene
	if scene:
		var inst := scene.instantiate()
		var tp := inst as TrackPiece
		if tp:
			var pt: Array = tp.build_points()
			var pts: PackedVector3Array = (pt[0] as PackedVector3Array).duplicate()
			var tans: PackedVector3Array = (pt[1] as PackedVector3Array).duplicate()
			var ups := PackedVector3Array()
			var loop := PackedByteArray()
			if pt.size() > 3: # C21: road normals + loop flags
				ups = (pt[2] as PackedVector3Array).duplicate()
				loop = (pt[3] as PackedByteArray).duplicate()
			if ups.size() != pts.size() or loop.size() != pts.size():
				ups.resize(pts.size())
				ups.fill(Vector3.UP)
				loop.resize(pts.size())
				loop.fill(0)
			if flip:
				for k in pts.size():
					pts[k].x = -pts[k].x
					tans[k].x = -tans[k].x
					ups[k].x = -ups[k].x
			var n := pts.size()
			var end := Transform3D(Basis.looking_at(tans[n - 1].normalized(), Vector3.UP), pts[n - 1])
			out = {"pts": pts, "tans": tans, "ups": ups, "loop": loop, "end": end, "len": tp.road_length(), "line": tp.line_at,
				"flippable": tp.flippable}
		inst.free()
	if out.is_empty():
		push_error("[Track] unknown track piece '%s'" % id)
	_shapes[key] = out
	return out


## Chain `list` ({id, flip}) into dense local points: {pos, tan, up, loop, own (index into list), cum (m along),
## joint_pts (point index of each joint, n + 1), frames (local frame at each joint, n + 1)}. Empty if a piece is
## unknown.
## The start piece is placed so its line sits at the local origin heading -Z.
func _compose(list: Array) -> Dictionary:
	var pos := PackedVector3Array()
	var tan := PackedVector3Array()
	var up := PackedVector3Array()
	var loop := PackedByteArray()
	var own := PackedInt32Array()
	var joint_pts := PackedInt32Array()
	var frames: Array[Transform3D] = []
	var frame := Transform3D()
	if not list.is_empty():
		var first := _shape(list[0]["id"], bool(list[0]["flip"]))
		if not first.is_empty() and float(first["line"]) > 0.0:
			frame.origin = Vector3(0.0, 0.0, float(first["line"]))
	for i in list.size():
		var sh := _shape(list[i]["id"], bool(list[i]["flip"]))
		if sh.is_empty():
			return {}
		joint_pts.append(0 if i == 0 else pos.size() - 1)
		frames.append(frame)
		var pts: PackedVector3Array = sh["pts"]
		var tans: PackedVector3Array = sh["tans"]
		var ups: PackedVector3Array = sh["ups"]
		var lf: PackedByteArray = sh["loop"]
		for k in range(0 if i == 0 else 1, pts.size()): # the first point repeats the previous piece's end
			pos.append(frame * pts[k])
			tan.append((frame.basis * tans[k]).normalized())
			up.append((frame.basis * ups[k]).normalized())
			loop.append(lf[k])
			own.append(i)
		frame = frame * (sh["end"] as Transform3D)
	joint_pts.append(pos.size() - 1)
	frames.append(frame)
	var cum := PackedFloat32Array()
	cum.resize(pos.size())
	for k in range(1, pos.size()):
		cum[k] = cum[k - 1] + pos[k].distance_to(pos[k - 1])
	return {"pos": pos, "tan": tan, "up": up, "loop": loop, "own": own, "cum": cum, "joint_pts": joint_pts,
		"frames": frames}


## True if two parts of the course that are more than SELF_ARC m apart along the road come closer than a road
## width plus both walls. Parts more than CROSS_CLEARANCE m apart in height pass over each other (C21: a loop's
## sides, later bridges). Hash grid on x/z, every 2nd point.
func _self_intersects(o: Dictionary) -> bool:
	if o.is_empty():
		return true
	var pos: PackedVector3Array = o["pos"]
	var cum: PackedFloat32Array = o["cum"]
	var sep := track_width + 2.0 * wall_thickness
	var sep2 := sep * sep
	var grid := {}
	var idx := PackedInt32Array()
	for k in range(0, pos.size(), 2):
		idx.append(k)
	if pos.size() > 0 and (pos.size() - 1) % 2 != 0:
		idx.append(pos.size() - 1)
	for k in idx:
		var key := Vector2i(floori(pos[k].x / sep), floori(pos[k].z / sep))
		if not grid.has(key):
			grid[key] = [] # WHY: a PackedInt32Array read out of a Dictionary is a copy; append would be lost
		(grid[key] as Array).append(k)
	for k in idx:
		var cx := floori(pos[k].x / sep)
		var cz := floori(pos[k].z / sep)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cell: Variant = grid.get(Vector2i(cx + dx, cz + dz))
				if cell == null:
					continue
				for j: int in cell:
					if j <= k or cum[j] - cum[k] <= SELF_ARC or absf(pos[j].y - pos[k].y) > CROSS_CLEARANCE:
						continue
					var ddx := pos[j].x - pos[k].x
					var ddz := pos[j].z - pos[k].z
					if ddx * ddx + ddz * ddz < sep2:
						return true
	return false


## Rebuild the centre line and joint data from _course (no visuals, no signal).
func _recompose() -> void:
	var o := _compose(_course)
	if o.is_empty():
		_curve = Curve3D.new()
		_curve.add_point(Vector3.ZERO)
		_curve.add_point(Vector3.FORWARD)
		_curve_len = 1.0
		return
	var pos: PackedVector3Array = o["pos"]
	_curve = points_to_curve(pos, o["tan"])
	_curve_len = _curve.get_baked_length()
	_frames = o["frames"]
	_joint_off.resize(0)
	var joint_pts: PackedInt32Array = o["joint_pts"]
	for k in joint_pts:
		_joint_off.append(_curve.get_closest_offset(pos[k]))
	_joint_off[0] = 0.0
	_joint_off[_joint_off.size() - 1] = _curve_len
	_index_dense(o)
	var first := _shape(_course[0]["id"], bool(_course[0]["flip"]))
	_start_off = _curve.get_closest_offset(_frames[0] * Vector3(0.0, 0.0, -maxf(float(first["line"]), 0.0)))
	var last := _course.size() - 1
	var fin := _shape(_course[last]["id"], bool(_course[last]["flip"]))
	var fl := float(fin["line"]) if float(fin["line"]) >= 0.0 else float(fin["len"])
	_finish_off = _curve.get_closest_offset(_frames[last] * Vector3(0.0, 0.0, -fl))
	for i in _loop_zones.size():
		_loop_zones[i] -= Vector2(_start_off, _start_off)
	var path := get_node_or_null(^"Path") as Path3D
	if path:
		path.curve = _curve
	_compute_bounds()


## C21: curve offset + road normal of every composed point, and the loop zones (curve offsets; _recompose shifts
## them to progress once _start_off is known).
func _index_dense(o: Dictionary) -> void:
	var cum: PackedFloat32Array = o["cum"]
	var n := cum.size()
	var k_len := _curve_len / maxf(cum[n - 1], 0.001) # WHY: baked length differs from the point chain by << 1 %
	_dense_off.resize(n)
	for k in n:
		_dense_off[k] = cum[k] * k_len
	_dense_up = o["up"]
	_has_height = false
	_low_y = 0.0
	var pos: PackedVector3Array = o["pos"]
	for j in n:
		var u := _dense_up[j]
		if absf(pos[j].y) > 0.05 or u.y < 0.999:
			_has_height = true
		# lowest road edge (a banked road's inside edge dips below its centre line)
		_low_y = minf(_low_y, pos[j].y - track_width * 0.5 * Vector2(u.x, u.z).length())
	_loop_zones.clear()
	var loop: PackedByteArray = o["loop"]
	var k := 0
	while k < n:
		if loop[k] == 0:
			k += 1
			continue
		var a := k
		while k < n and loop[k] != 0:
			k += 1
		_loop_zones.append(Vector2(_dense_off[a], _dense_off[k - 1]))


## After a change: rebuild visuals and tell everyone.
func _refresh() -> void:
	_clear_visuals()
	_build_visuals()
	GameEvents.track_changed.emit()


func _compute_bounds() -> void:
	var pts := _curve.get_baked_points()
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var m := track_width * 0.5 + wall_thickness + 1.0
	# C20: y spans the course's height (at least -1 .. 1 as before)
	var y0 := minf(lo.y, 0.0) - 1.0
	var y1 := maxf(hi.y, 0.0) + 1.0
	_bounds_local = AABB(Vector3(lo.x - m, y0, lo.z - m), Vector3(hi.x - lo.x + 2.0 * m, y1 - y0, hi.z - lo.z + 2.0 * m))


# ---------------------------------------------------------------- generated visuals + collision

func _build_visuals() -> void:
	var b := _bounds_local
	if pit:
		var abyss := MeshInstance3D.new() # visual only: a dark floor far below, no collision
		abyss.name = "Abyss"
		var ap := PlaneMesh.new()
		ap.size = Vector2(b.size.x + 600.0, b.size.z + 600.0)
		abyss.mesh = ap
		abyss.position = Vector3(b.position.x + b.size.x * 0.5, -60.0, b.position.z + b.size.z * 0.5)
		abyss.material_override = _mat(Color(0.05, 0.04, 0.05))
		_add_visual(abyss)
	else:
		var ground := StaticBody3D.new()
		ground.name = "Ground"
		# C20: below the lowest road edge (a banked turn's inside edge dips under y = 0)
		ground.position.y = minf(0.0, _low_y - 0.3) if _has_height else 0.0
		ground.collision_layer = Layers.WORLD
		ground.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = WorldBoundaryShape3D.new()
		ground.add_child(shape)
		var sand := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(b.size.x + 120.0, b.size.z + 120.0)
		sand.mesh = plane
		sand.position = Vector3(b.position.x + b.size.x * 0.5, 0.0, b.position.z + b.size.z * 0.5)
		sand.material_override = _mat(Color(0.82, 0.72, 0.52))
		ground.add_child(sand)
		_add_visual(ground)

	_road_bodies.clear()
	var steps := maxi(int(_curve_len / MESH_STEP), 8)
	var h := track_width * 0.5
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slab := SurfaceTool.new()
	slab.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		# C21: the road frame (normal = road up) so a loop's road stands up and turns over
		var t0 := _local_road_t(_curve_len * i / steps)
		var t1 := _local_road_t(_curve_len * (i + 1) / steps)
		# C20: two halves meeting on the centre line, so a twisting (banked) road stays close to its true surface
		_quad(road, t0.origin - t0.basis.x * h, t1.origin - t1.basis.x * h, t0.origin, t1.origin, t0.basis.y, 0.02)
		_quad(road, t0.origin, t1.origin, t0.origin + t0.basis.x * h, t1.origin + t1.basis.x * h, t0.basis.y, 0.02)
		if pit: # slab sides + underside so the road reads as a floating bridge
			var down := -t0.basis.y * slab_depth
			for side: float in [-1.0, 1.0]:
				var e0: Vector3 = t0.origin + t0.basis.x * side * h
				var e1: Vector3 = t1.origin + t1.basis.x * side * h
				_strip(slab, e0 + down, e1 + down, -down, t0.basis.x * side)
			var down1 := -t1.basis.y * slab_depth
			_quad(slab, t0.origin - t0.basis.x * h + down, t1.origin - t1.basis.x * h + down1,
				t0.origin + t0.basis.x * h + down, t1.origin + t1.basis.x * h + down1, -t0.basis.y, 0.0)
			continue
		for side: float in [-1.0, 1.0]:
			var in0: Vector3 = t0.origin + t0.basis.x * side * h
			var in1: Vector3 = t1.origin + t1.basis.x * side * h
			var out0: Vector3 = t0.origin + t0.basis.x * side * (h + wall_thickness)
			var out1: Vector3 = t1.origin + t1.basis.x * side * (h + wall_thickness)
			var up := t0.basis.y * wall_height
			var n: Vector3 = -t0.basis.x * side # faces the road
			_strip(wall, in0, in1, up, n)
			_strip(wall, out1, out0, up, -n)
			_quad(wall, in0 + up, in1 + up, out0 + up, out1 + up, t0.basis.y, 0.0)
	var road_mi := MeshInstance3D.new()
	road_mi.name = "Road"
	road_mi.mesh = road.commit()
	road_mi.material_override = _mat(Color(0.55, 0.5, 0.45))
	_add_visual(road_mi)

	var walls := StaticBody3D.new()
	walls.name = "Walls" if not pit else "Slab"
	walls.collision_mask = 0
	walls.collision_layer = Layers.WORLD if pit else Layers.WALL
	var wall_mesh := (slab if pit else wall).commit()
	var wall_mi := MeshInstance3D.new()
	wall_mi.mesh = wall_mesh
	wall_mi.material_override = _mat(Color(0.45, 0.4, 0.37) if pit else Color(0.7, 0.62, 0.55))
	walls.add_child(wall_mi)
	if not pit: # pit mode: the road itself is the only floor (below)
		var wall_shape := CollisionShape3D.new()
		wall_shape.shape = wall_mesh.create_trimesh_shape()
		walls.add_child(wall_shape)
	else:
		var floor_shape := CollisionShape3D.new()
		var tri := road_mi.mesh.create_trimesh_shape()
		tri.backface_collision = true
		floor_shape.shape = tri
		walls.add_child(floor_shape)
		_road_bodies.append(walls)
	_add_visual(walls)
	if not pit and _has_height: # C20: the flat ground can't carry a hill; the road itself is the floor
		var floor_body := StaticBody3D.new()
		floor_body.name = "RoadFloor"
		floor_body.collision_layer = Layers.WORLD
		floor_body.collision_mask = 0
		var fs := CollisionShape3D.new()
		var ftri := road_mi.mesh.create_trimesh_shape()
		ftri.backface_collision = true
		fs.shape = ftri
		floor_body.add_child(fs)
		_add_visual(floor_body)
		_road_bodies.append(floor_body)

	_add_line("StartLine", _start_off, Color.WHITE)
	_add_line("FinishLine", _finish_off, Color(0.1, 0.1, 0.1))
	_add_gate(_finish_off)
	_add_cap("CapStart", _local_off_t(0.0), 1.0)
	_add_cap("CapEnd", _local_off_t(_curve_len), -1.0)


func _add_line(nm: String, off: float, c: Color) -> void:
	var t := _local_off_t(off)
	var line := MeshInstance3D.new()
	line.name = nm
	var box := BoxMesh.new()
	box.size = Vector3(track_width, 0.05, 1.0)
	line.mesh = box
	line.material_override = _mat(c)
	line.transform = Transform3D(t.basis, t.origin + Vector3.UP * 0.04)
	_add_visual(line)


## Finish gate: two posts beside the road and a bar over it (visual only).
func _add_gate(off: float) -> void:
	var t := _local_off_t(off)
	var gate := Node3D.new()
	gate.name = "FinishGate"
	gate.transform = t
	var w := track_width * 0.5 + 0.6
	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.8, 6.0, 0.8)
		post.mesh = pm
		post.position = Vector3(side * w, 3.0, 0.0)
		post.material_override = _mat(Color(0.85, 0.7, 0.2))
		gate.add_child(post)
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w * 2.0 + 0.8, 1.2, 0.6)
	bar.mesh = bm
	bar.position = Vector3(0.0, 6.0, 0.0)
	bar.material_override = _mat(Color(0.75, 0.15, 0.12))
	gate.add_child(bar)
	_add_visual(gate)


## A wall across an open end of the road so nobody drives off it. `out` = +1 at the start, -1 at the far end
## (the side the wall sits on, along -Z).
func _add_cap(nm: String, t: Transform3D, out: float) -> void:
	var cap := StaticBody3D.new()
	cap.name = nm
	cap.collision_layer = Layers.WALL
	cap.collision_mask = 0
	var size := Vector3(track_width + 2.0 * wall_thickness, CAP_HEIGHT, 1.0)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	cap.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(Color(0.7, 0.62, 0.55))
	cap.add_child(mi)
	cap.transform = Transform3D(t.basis, t.origin + t.basis.z * out * 0.5 + Vector3.UP * CAP_HEIGHT * 0.5)
	_add_visual(cap)


func _add_visual(n: Node) -> void:
	_visuals.append(n)
	add_child(n)


func _clear_visuals() -> void:
	for n in _visuals:
		if is_instance_valid(n):
			remove_child(n) # WHY: frees the names "Road"/"Walls" now, so the rebuilt ones keep them
			n.queue_free()
	_visuals.clear()


## Transform on the centre line at curve offset `off`, local space (-Z = driving direction). Works at both ends.
func _local_off_t(off: float) -> Transform3D:
	off = clampf(off, 0.0, _curve_len)
	var p := _curve.sample_baked(off)
	var a := maxf(off - 0.5, 0.0)
	var b := minf(off + 0.5, _curve_len)
	if b - a < 0.5:
		a = maxf(b - 1.0, 0.0)
	var dir := _curve.sample_baked(b) - _curve.sample_baked(a)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), p)


## C21: full road frame at curve offset `off` (local): -Z along the 3D tangent, +Y = road normal (UP on flat road).
func _local_road_t(off: float) -> Transform3D:
	off = clampf(off, 0.0, _curve_len)
	var p := _curve.sample_baked(off)
	var a := maxf(off - 0.5, 0.0)
	var b := minf(off + 0.5, _curve_len)
	if b - a < 0.5:
		a = maxf(b - 1.0, 0.0)
	var fwd := _curve.sample_baked(b) - _curve.sample_baked(a)
	fwd = fwd.normalized() if fwd.length_squared() > 0.000001 else Vector3.FORWARD
	var up := _up_at_off(off)
	var right := fwd.cross(up)
	if right.length_squared() < 0.0001:
		right = fwd.cross(Vector3.UP) if absf(fwd.y) < 0.99 else Vector3.RIGHT
	right = right.normalized()
	return Transform3D(Basis(right, right.cross(fwd).normalized(), -fwd), p)


## Road normal at curve offset `off`, interpolated between composed points (local).
func _up_at_off(off: float) -> Vector3:
	var n := _dense_off.size()
	if n < 2 or _dense_up.size() != n:
		return Vector3.UP
	var i := clampi(_dense_off.bsearch(off), 1, n - 1)
	var a := _dense_off[i - 1]
	var f := clampf((off - a) / maxf(_dense_off[i] - a, 0.0001), 0.0, 1.0)
	var u := _dense_up[i - 1].lerp(_dense_up[i], f)
	return u.normalized() if u.length_squared() > 0.0001 else _dense_up[i]


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, lift: float) -> void:
	# a,b = near/far left; c,d = near/far right (counter-clockwise seen from +Y when n is UP)
	var up := n * lift
	st.set_normal(n)
	for v in [a, b, c, c, b, d]:
		st.add_vertex(v + up)


func _strip(st: SurfaceTool, a: Vector3, b: Vector3, up: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	for v in [a, b, a + up, a + up, b, b + up]:
		st.add_vertex(v)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED # WHY: greybox, winding of every face is not worth the bugs
	return m
