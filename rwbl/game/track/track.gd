class_name Track
extends Node3D
## The race track: ground, centre line, surfaces, start grid, checkpoints, build zones (DESIGN §5.5, §7).
## Owner: C05. C02 STUB: a flat stadium oval built in code (two straights + two half circles).
## C05 replaces the shape/visuals (greybox loop with walls); keep the public API.
## NET: identical on every peer (static data + item surface patches, which every peer registers itself).
## Public API (all positions world space, `progress` = metres along the centre line from the start line):
##   track_width, length(), get_center_curve(), progress_at(pos), point_at(progress), transform_at(progress),
##   lateral_offset(pos), is_on_track(pos), surface_at(pos), register_surface_patch(node, surface, half),
##   unregister_surface_patch(node), start_transform(grid_index), checkpoint_count(),
##   checkpoint_progress(i), respawn_transform(progress), is_in_no_build_zone(pos, radius), get_bounds()
# CONTRACT: API above. Progress increases in the driving direction; the start/finish line is progress 0.

## Drivable width in metres.
@export var track_width := 14.0 # TUNE
## Stub shape: straight length and turn radius.
@export var straight_length := 70.0
@export var turn_radius := 28.0

## No items between NO_BUILD_BEFORE metres before the start line (grid) and NO_BUILD_AFTER after it.
const NO_BUILD_BEFORE := 28.0
const NO_BUILD_AFTER := 10.0
const CHECKPOINTS := 8
const GRID_ROW_GAP := 5.0
const GRID_FIRST_ROW := 5.0

var _curve := Curve3D.new()
var _patches: Dictionary = {} # Node3D -> [surface, half_extents]


func _ready() -> void:
	_build_curve()
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
	var half_x := straight_length * 0.5 + turn_radius + track_width
	var half_z := turn_radius + track_width
	return AABB(global_position + Vector3(-half_x, -1.0, -half_z), Vector3(half_x * 2.0, 2.0, half_z * 2.0))


# ---------------------------------------------------------------- stub shape

func _stadium_point(s: float) -> Vector3:
	var l := straight_length
	var r := turn_radius
	var per := 2.0 * l + 2.0 * PI * r
	s = fposmod(s + l * 0.5, per) # start line in the middle of the first straight
	if s < l:
		return Vector3(-l * 0.5 + s, 0.0, r)
	s -= l
	if s < PI * r:
		var a := s / r
		return Vector3(l * 0.5 + r * sin(a), 0.0, r * cos(a))
	s -= PI * r
	if s < l:
		return Vector3(l * 0.5 - s, 0.0, -r)
	var b := (s - l) / r
	return Vector3(-l * 0.5 - r * sin(b), 0.0, -r * cos(b))


func _build_curve() -> void:
	_curve.clear_points()
	_curve.bake_interval = 0.5
	var per := 2.0 * straight_length + 2.0 * PI * turn_radius
	var n := 160
	for i in n + 1: # last point = first point closes the loop
		_curve.add_point(_stadium_point(per * float(i) / n))


func _build_visuals() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	var sand := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	var b := get_bounds()
	plane.size = Vector2(b.size.x + 40.0, b.size.z + 40.0)
	sand.mesh = plane
	sand.material_override = _mat(Color(0.82, 0.72, 0.52))
	ground.add_child(sand)
	add_child(ground)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := int(length() / 2.0)
	for i in steps:
		var t0 := transform_at(length() * i / steps)
		var t1 := transform_at(length() * (i + 1) / steps)
		var h := track_width * 0.5
		var a := to_local(t0.origin - t0.basis.x * h) + Vector3.UP * 0.02
		var c := to_local(t0.origin + t0.basis.x * h) + Vector3.UP * 0.02
		var d := to_local(t1.origin - t1.basis.x * h) + Vector3.UP * 0.02
		var e := to_local(t1.origin + t1.basis.x * h) + Vector3.UP * 0.02
		st.set_normal(Vector3.UP)
		for v in [a, d, c, c, d, e]:
			st.add_vertex(v)
	var road := MeshInstance3D.new()
	road.name = "Road"
	road.mesh = st.commit()
	road.material_override = _mat(Color(0.55, 0.5, 0.45))
	add_child(road)

	var line := MeshInstance3D.new()
	line.name = "StartLine"
	var box := BoxMesh.new()
	box.size = Vector3(track_width, 0.05, 1.0)
	line.mesh = box
	line.material_override = _mat(Color.WHITE)
	line.transform = transform_at(0.0)
	line.position += Vector3.UP * 0.03
	add_child(line)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m
