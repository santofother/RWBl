class_name Track
extends Node3D
## The race track: ground, centre line, surfaces, start grid, checkpoints, build zones (DESIGN §5.5, §7).
## Owner: C05. Greybox loop: the centre line is the `Path3D` child "Path" in track.tscn (edit it in the editor;
## the last point must equal the first so the loop closes). Road mesh, walls and ground are generated from it.
## NET: identical on every peer (static data + item surface patches, which every peer registers itself).
## Public API (all positions world space, `progress` = metres along the centre line from the start line):
##   track_width, length(), get_center_curve(), progress_at(pos), point_at(progress), transform_at(progress),
##   lateral_offset(pos), is_on_track(pos), surface_at(pos), register_surface_patch(node, surface, half),
##   unregister_surface_patch(node), start_transform(grid_index), checkpoint_count(),
##   checkpoint_progress(i), respawn_transform(progress), is_in_no_build_zone(pos, radius), get_bounds()
## Track pieces (C19, DESIGN §5.6): splice_piece(def_id, start, flip, uid) -> bool, check_splice(...) -> Splice.*,
##   apply_splice(uid, def_id, base_start, flip) (no checks), remove_piece(uid), has_piece(uid), piece_at(pos),
##   pieces() -> Array of {uid, id, start, end, flip, base_start}, to_base_progress(p), piece_world_points(...),
##   static splice_text(code), static points_to_curve(points, tangents).
##   A piece replaces `ItemDef.piece_length` m of a straight stretch of the ORIGINAL road with the piece's own
##   centre line (TrackPiece). Pieces never overlap, so each one is stored in base-curve progress and the curve is
##   recomposed from the base + all pieces (removing one restores the original section). After every change the
##   road, walls, bounds and checkpoints are rebuilt and GameEvents.track_changed fires (on this peer).
# CONTRACT: API above. Progress increases in the driving direction; the start/finish line is progress 0.
# CONTRACT: pieces never touch [0, PIECE_KEEP_AFTER] or the last PIECE_KEEP_BEFORE m, so the start line, the grid
#   and progress 0 never move.

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

## No items between NO_BUILD_BEFORE metres before the start line (grid) and NO_BUILD_AFTER after it.
const NO_BUILD_BEFORE := 28.0
const NO_BUILD_AFTER := 10.0
const CHECKPOINTS := 8
const GRID_ROW_GAP := 5.0
const GRID_FIRST_ROW := 5.0
const MESH_STEP := 2.0 # metres between road/wall mesh slices

## check_splice() codes.
enum Splice { OK, UNKNOWN, START_ZONE, NOT_STRAIGHT, OVERLAP, SELF_INTERSECT }
const SPLICE_TEXT: Array[String] = ["OK", "Not a track piece", "Too close to the start straight",
	"Needs a straight stretch of road", "Overlaps another track piece", "The new road would cross the track"]
const PIECE_KEEP_AFTER := 40.0 # TUNE: m after the start line where no piece may start
const PIECE_KEEP_BEFORE := 40.0 # TUNE: m before the start line where no piece may end
const PIECE_GAP := 4.0 # TUNE: m of untouched road between two pieces
const PIECE_STRAIGHT_TOL := 0.3 # m the replaced section may bend away from a straight line
const PIECE_SAMPLE := 1.0 # m between centre-line points of a recomposed curve
const SELF_ARC := 24.0 # m along the road under which two points are neighbours, not a crossing

var _curve: Curve3D
var _base_curve: Curve3D # the original centre line (never modified)
var _pieces: Array[Dictionary] = [] # sorted by base_start: {uid, id, base_start, flip, cut, grow}
var _shapes: Dictionary = {} # piece def id -> [points, tangents, length] in piece space
var _auto_uid := 1000000
var _visuals: Array[Node] = []
var _bounds_local := AABB()
var _patches: Dictionary = {} # Node3D -> [surface, half_extents]


func _ready() -> void:
	var path := get_node_or_null(^"Path") as Path3D
	if path and path.curve:
		_curve = path.curve
	else: # WHY: Track.new() in a test has no scene children; borrow the curve from track.tscn
		var packed := load("res://game/track/track.tscn") as PackedScene
		var tmp := packed.instantiate()
		_curve = (tmp.get_node(^"Path") as Path3D).curve
		tmp.free()
	_curve.bake_interval = 0.5
	_base_curve = _curve
	_compute_bounds()
	_build_visuals()


## Total centre-line length (m).
func length() -> float:
	return _curve.get_baked_length()


## The centre line in this node's local space (bots, validation). Don't modify it.
func get_center_curve() -> Curve3D:
	return _curve


## Progress (m from the start line, 0..length) of the centre-line point closest to `pos`.
func progress_at(pos: Vector3) -> float:
	return _curve.get_closest_offset(to_local(pos))


## Centre-line point at `progress` (wraps around).
func point_at(progress: float) -> Vector3:
	return to_global(_curve.sample_baked(fposmod(progress, length())))


## Transform on the centre line at `progress`, -Z facing the driving direction.
func transform_at(progress: float) -> Transform3D:
	var p := point_at(progress)
	var ahead := point_at(progress + 1.0)
	var dir := ahead - p
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), p)


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


## Number of checkpoints (checkpoint 0 = start/finish line).
func checkpoint_count() -> int:
	return CHECKPOINTS


## Progress of checkpoint `i`. Checkpoints are crossed in order 0..n-1, then 0 again ends the lap.
func checkpoint_progress(i: int) -> float:
	return length() * float(posmod(i, CHECKPOINTS)) / CHECKPOINTS


## Safe spot to respawn near `progress` (centre line, facing forward).
func respawn_transform(progress: float) -> Transform3D:
	return transform_at(progress)


## True if a circle at `pos` with `radius` touches the start/finish no-build zone.
func is_in_no_build_zone(pos: Vector3, radius: float = 0.0) -> bool:
	var p := progress_at(pos)
	var before := length() - p # distance behind the line
	return p <= NO_BUILD_AFTER + radius or before <= NO_BUILD_BEFORE + radius


## World-space box containing the whole track (build camera, validation grid).
func get_bounds() -> AABB:
	return AABB(global_position + _bounds_local.position, _bounds_local.size)


func _compute_bounds() -> void:
	var pts := _curve.get_baked_points()
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	for p in pts:
		lo.x = minf(lo.x, p.x)
		lo.z = minf(lo.z, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.z = maxf(hi.z, p.z)
	var m := track_width * 0.5 + wall_thickness + 1.0
	_bounds_local = AABB(Vector3(lo.x - m, -1.0, lo.z - m), Vector3(hi.x - lo.x + 2.0 * m, 2.0, hi.z - lo.z + 2.0 * m))


# ---------------------------------------------------------------- track pieces (C19)

## Validate (check_splice) and, if OK, splice piece `def_id` in starting at `start_progress` (current progress).
## `flip` mirrors it to the left. `uid` -1 = pick one. NET: host validates; peers use apply_splice().
func splice_piece(def_id: StringName, start_progress: float, flip := false, uid := -1) -> bool:
	if check_splice(def_id, start_progress, flip) != Splice.OK:
		return false
	apply_splice(uid, def_id, to_base_progress(start_progress), flip)
	return true


## Would splicing `def_id` at `start_progress` work? Returns a Splice code (OK first fail wins, in this order:
## unknown, start zone, overlap, not straight, self-intersection). NET: host (authoritative) and clients (ghost).
func check_splice(def_id: StringName, start_progress: float, flip := false) -> int:
	var d := ItemDB.get_def(def_id)
	if d == null or not d.is_piece() or _shape(def_id).is_empty() or d.piece_length <= 0.0:
		return Splice.UNKNOWN
	var cut := d.piece_length
	var s := start_progress
	if not is_finite(s) or s < PIECE_KEEP_AFTER or s + cut > length() - PIECE_KEEP_BEFORE:
		return Splice.START_ZONE
	for i in _pieces.size():
		var ps := _cur_start(i)
		var pe := ps + float(_pieces[i]["cut"]) + float(_pieces[i]["grow"])
		if s < pe + PIECE_GAP and s + cut + PIECE_GAP > ps:
			return Splice.OVERLAP
	var b := to_base_progress(s)
	if not _base_straight(b, cut):
		return Splice.NOT_STRAIGHT
	var trial := _pieces.duplicate()
	var entry := _entry(-1, def_id, b, flip)
	trial.append(entry)
	trial.sort_custom(_by_base)
	if _self_intersects(_compose(trial), trial.find(entry)):
		return Splice.SELF_INTERSECT
	return Splice.OK


## Splice without any checks (every peer applies what the host validated). Returns the uid used.
func apply_splice(uid: int, def_id: StringName, base_start: float, flip := false) -> int:
	if uid < 0:
		uid = _auto_uid
		_auto_uid += 1
	_pieces.append(_entry(uid, def_id, base_start, flip))
	_pieces.sort_custom(_by_base)
	_rebuild()
	var i := _index_of(uid)
	print("[Track] SPLICE %d %s at %.1f (base %.1f) flip=%s length %.1f" % [uid, def_id, _cur_start(i), base_start,
		flip, length()])
	return uid


## Remove piece `uid` and restore the original section. False if there is no such piece. NET: every peer.
func remove_piece(uid: int) -> bool:
	var i := _index_of(uid)
	if i < 0:
		return false
	_pieces.remove_at(i)
	_rebuild()
	print("[Track] UNSPLICE %d length %.1f" % [uid, length()])
	return true


## True if a piece with this uid is spliced in.
func has_piece(uid: int) -> bool:
	return _index_of(uid) >= 0


## uid of the piece whose road covers `pos`, or -1.
func piece_at(pos: Vector3) -> int:
	if not is_on_track(pos):
		return -1
	var p := progress_at(pos)
	for i in _pieces.size():
		var ps := _cur_start(i)
		if p >= ps and p <= ps + float(_pieces[i]["cut"]) + float(_pieces[i]["grow"]):
			return int(_pieces[i]["uid"])
	return -1


## Every spliced piece in driving order: {uid, id, start, end (current progress), flip, base_start}.
func pieces() -> Array:
	var out: Array = []
	for i in _pieces.size():
		var e: Dictionary = _pieces[i]
		var ps := _cur_start(i)
		out.append({"uid": e["uid"], "id": e["id"], "start": ps, "end": ps + float(e["cut"]) + float(e["grow"]),
			"flip": e["flip"], "base_start": e["base_start"]})
	return out


## Current progress -> progress on the original centre line (only meaningful outside pieces).
func to_base_progress(p: float) -> float:
	var off := 0.0
	for i in _pieces.size():
		var ps := _cur_start(i)
		if p >= ps + float(_pieces[i]["cut"]) + float(_pieces[i]["grow"]):
			off += float(_pieces[i]["grow"])
		elif p > ps:
			return float(_pieces[i]["base_start"]) + minf(p - ps, float(_pieces[i]["cut"]))
		else:
			break
	return p - off


## World-space centre line `def_id` would have if spliced at `start_progress` (build ghost). Empty if unknown.
func piece_world_points(def_id: StringName, start_progress: float, flip := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	var d := ItemDB.get_def(def_id)
	var sh := _shape(def_id)
	if d == null or sh.is_empty():
		return out
	var xf := _piece_xform(to_base_progress(start_progress), d.piece_length)
	for lp: Vector3 in sh[0]:
		out.append(to_global(xf * (Vector3(-lp.x, lp.y, lp.z) if flip else lp)))
	return out


## Player-facing text for a Splice code.
static func splice_text(code: int) -> String:
	return SPLICE_TEXT[code] if code >= 0 and code < SPLICE_TEXT.size() else "Rejected"


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


func _entry(uid: int, def_id: StringName, base_start: float, flip: bool) -> Dictionary:
	var d := ItemDB.get_def(def_id)
	var sh := _shape(def_id)
	return {"uid": uid, "id": def_id, "base_start": base_start, "flip": flip, "cut": d.piece_length,
		"grow": float(sh[2]) - d.piece_length}


static func _by_base(a: Dictionary, b: Dictionary) -> bool:
	return float(a["base_start"]) < float(b["base_start"])


func _index_of(uid: int) -> int:
	for i in _pieces.size():
		if int(_pieces[i]["uid"]) == uid:
			return i
	return -1


func _cur_start(i: int) -> float:
	var off := 0.0
	for j in i:
		off += float(_pieces[j]["grow"])
	return float(_pieces[i]["base_start"]) + off


## Piece-space shape of `def_id`: [points, tangents, length], cached. Empty if it has no TrackPiece scene.
func _shape(def_id: StringName) -> Array:
	if _shapes.has(def_id):
		return _shapes[def_id]
	var out: Array = []
	var d := ItemDB.get_def(def_id)
	if d and d.piece:
		var inst := d.piece.instantiate()
		var tp := inst as TrackPiece
		if tp:
			var pt: Array = tp.build_points()
			var pts: PackedVector3Array = pt[0]
			var len := 0.0
			for k in range(1, pts.size()):
				len += pts[k].distance_to(pts[k - 1])
			out = [pts, pt[1], len]
			var chord := pts[pts.size() - 1].length()
			if absf(chord - d.piece_length) > 0.05:
				push_warning("[Track] piece %s chord %.2f != piece_length %.2f" % [def_id, chord, d.piece_length])
		inst.free()
	_shapes[def_id] = out
	return out


## Transform that puts piece space on the base road at `base_start` (-Z along the chord, origin at the start).
func _piece_xform(base_start: float, cut: float) -> Transform3D:
	var l := _base_curve.get_baked_length()
	var p0 := _base_curve.sample_baked(fposmod(base_start, l))
	var p1 := _base_curve.sample_baked(fposmod(base_start + cut, l))
	var f := p1 - p0
	f.y = 0.0
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	return Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), p0)


func _base_straight(b: float, cut: float) -> bool:
	var l := _base_curve.get_baked_length()
	var p0 := _base_curve.sample_baked(fposmod(b, l))
	var p1 := _base_curve.sample_baked(fposmod(b + cut, l))
	if absf(p0.distance_to(p1) - cut) > PIECE_STRAIGHT_TOL * 2.0:
		return false
	var n := maxi(2, ceili(cut / 2.0))
	for k in range(1, n):
		var q := _base_curve.sample_baked(fposmod(b + cut * k / n, l))
		var on := Geometry3D.get_closest_point_to_segment(q, p0, p1)
		if q.distance_to(on) > PIECE_STRAIGHT_TOL:
			return false
	# both ends must already run along the chord, or the joints would kink
	var dir := (p1 - p0).normalized()
	for e: float in [b, b + cut]:
		if _base_tangent(e).dot(dir) < 0.9986: # cos 3°
			return false
	return true


func _base_tangent(s: float) -> Vector3:
	var l := _base_curve.get_baked_length()
	var t := _base_curve.sample_baked(fposmod(s + 0.25, l)) - _base_curve.sample_baked(fposmod(s - 0.25, l))
	return t.normalized() if t.length_squared() > 0.0 else Vector3.FORWARD


## Base curve + `list` (sorted pieces) as dense points: {pos, tan, own (index into list, -1 = base road)}.
## The last point repeats the first, so the loop is closed.
func _compose(list: Array) -> Dictionary:
	var pos := PackedVector3Array()
	var tan := PackedVector3Array()
	var own := PackedInt32Array()
	var cursor := 0.0
	for i in list.size():
		var e: Dictionary = list[i]
		_append_base(pos, tan, own, cursor, float(e["base_start"]))
		var sh := _shape(e["id"])
		var xf := _piece_xform(float(e["base_start"]), float(e["cut"]))
		var pts: PackedVector3Array = sh[0]
		var tans: PackedVector3Array = sh[1]
		for k in pts.size() - 1: # the end point is the base road's next point
			var lp := pts[k]
			var lt := tans[k]
			if e["flip"]:
				lp.x = -lp.x
				lt.x = -lt.x
			pos.append(xf * lp)
			tan.append((xf.basis * lt).normalized())
			own.append(i)
		cursor = float(e["base_start"]) + float(e["cut"])
	_append_base(pos, tan, own, cursor, _base_curve.get_baked_length())
	pos.append(pos[0])
	tan.append(tan[0])
	own.append(-1)
	return {"pos": pos, "tan": tan, "own": own}


func _append_base(pos: PackedVector3Array, tan: PackedVector3Array, own: PackedInt32Array, a: float,
		b: float) -> void:
	if b - a < 0.01:
		return
	var n := maxi(1, ceili((b - a) / PIECE_SAMPLE))
	var l := _base_curve.get_baked_length()
	for k in n:
		var s := a + (b - a) * k / n
		pos.append(_base_curve.sample_baked(fposmod(s, l)))
		tan.append(_base_tangent(s))
		own.append(-1)


## True if any point of piece `idx` comes closer than a road width (+ walls) to a non-neighbouring part of the road.
func _self_intersects(o: Dictionary, idx: int) -> bool:
	var pos: PackedVector3Array = o["pos"]
	var own: PackedInt32Array = o["own"]
	var n := pos.size() - 1
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	for k in range(1, n + 1):
		cum[k] = cum[k - 1] + pos[k].distance_to(pos[k - 1])
	var total := cum[n]
	var sep := track_width + 2.0 * wall_thickness
	var sep2 := sep * sep
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var mine := PackedInt32Array()
	for k in range(0, n, 2):
		if own[k] == idx:
			mine.append(k)
			lo = Vector2(minf(lo.x, pos[k].x), minf(lo.y, pos[k].z))
			hi = Vector2(maxf(hi.x, pos[k].x), maxf(hi.y, pos[k].z))
	lo -= Vector2(sep, sep)
	hi += Vector2(sep, sep)
	for j in range(0, n, 2):
		var q := pos[j]
		if q.x < lo.x or q.z < lo.y or q.x > hi.x or q.z > hi.y:
			continue
		for k in mine:
			var arc := absf(cum[k] - cum[j])
			if minf(arc, total - arc) <= SELF_ARC:
				continue
			var dx := pos[k].x - q.x
			var dz := pos[k].z - q.z
			if dx * dx + dz * dz < sep2:
				return true
	return false


func _rebuild() -> void:
	if _pieces.is_empty():
		_curve = _base_curve
	else:
		var o := _compose(_pieces)
		_curve = points_to_curve(o["pos"], o["tan"])
	var path := get_node_or_null(^"Path") as Path3D
	if path:
		path.curve = _curve
	_compute_bounds()
	_clear_visuals()
	_build_visuals()
	GameEvents.track_changed.emit()


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

	var steps := maxi(int(length() / MESH_STEP), 8)
	var h := track_width * 0.5
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slab := SurfaceTool.new()
	slab.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var t0 := _local_t(length() * i / steps)
		var t1 := _local_t(length() * (i + 1) / steps)
		_quad(road, t0.origin - t0.basis.x * h, t1.origin - t1.basis.x * h, t0.origin + t0.basis.x * h,
			t1.origin + t1.basis.x * h, Vector3.UP, 0.02)
		if pit: # slab sides + underside so the road reads as a floating bridge
			var down := Vector3.DOWN * slab_depth
			for side: float in [-1.0, 1.0]:
				var e0: Vector3 = t0.origin + t0.basis.x * side * h
				var e1: Vector3 = t1.origin + t1.basis.x * side * h
				_strip(slab, e0 + down, e1 + down, -down, t0.basis.x * side)
			_quad(slab, t0.origin - t0.basis.x * h + Vector3.DOWN * slab_depth, t1.origin - t1.basis.x * h + Vector3.DOWN * slab_depth,
				t0.origin + t0.basis.x * h + Vector3.DOWN * slab_depth, t1.origin + t1.basis.x * h + Vector3.DOWN * slab_depth, Vector3.DOWN, 0.0)
			continue
		for side: float in [-1.0, 1.0]:
			var in0: Vector3 = t0.origin + t0.basis.x * side * h
			var in1: Vector3 = t1.origin + t1.basis.x * side * h
			var out0: Vector3 = t0.origin + t0.basis.x * side * (h + wall_thickness)
			var out1: Vector3 = t1.origin + t1.basis.x * side * (h + wall_thickness)
			var up := Vector3.UP * wall_height
			var n: Vector3 = -t0.basis.x * side # faces the road
			_strip(wall, in0, in1, up, n)
			_strip(wall, out1, out0, up, -n)
			_quad(wall, in0 + up, in1 + up, out0 + up, out1 + up, Vector3.UP, 0.0)
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
	_add_visual(walls)

	var line := MeshInstance3D.new()
	line.name = "StartLine"
	var box := BoxMesh.new()
	box.size = Vector3(track_width, 0.05, 1.0)
	line.mesh = box
	line.material_override = _mat(Color.WHITE)
	line.transform = Transform3D(_local_t(0.0).basis, _local_t(0.0).origin + Vector3.UP * 0.04)
	_add_visual(line)


func _add_visual(n: Node) -> void:
	_visuals.append(n)
	add_child(n)


func _clear_visuals() -> void:
	for n in _visuals:
		if is_instance_valid(n):
			remove_child(n) # WHY: frees the names "Road"/"Walls" now, so the rebuilt ones keep them
			n.queue_free()
	_visuals.clear()


## Transform on the centre line in this node's local space (-Z = driving direction).
func _local_t(progress: float) -> Transform3D:
	var l := length()
	var p := _curve.sample_baked(fposmod(progress, l))
	var dir := _curve.sample_baked(fposmod(progress + 1.0, l)) - p
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, lift: float) -> void:
	# a,b = near/far left; c,d = near/far right (counter-clockwise seen from +Y when n is UP)
	var up := Vector3.UP * lift
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
