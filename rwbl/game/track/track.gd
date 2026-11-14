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
# CONTRACT: API above. Progress increases in the driving direction; the start/finish line is progress 0.

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

var _curve: Curve3D
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
		add_child(abyss)
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
		add_child(ground)

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
	add_child(road_mi)

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
	add_child(walls)

	var line := MeshInstance3D.new()
	line.name = "StartLine"
	var box := BoxMesh.new()
	box.size = Vector3(track_width, 0.05, 1.0)
	line.mesh = box
	line.material_override = _mat(Color.WHITE)
	line.transform = Transform3D(_local_t(0.0).basis, _local_t(0.0).origin + Vector3.UP * 0.04)
	add_child(line)


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
