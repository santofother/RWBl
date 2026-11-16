class_name ItemVisual
extends RefCounted
## Visual-only copies of items and track pieces for build-phase previews (C24): the item's own scene with every
## script and collision stripped, see-through and tinted, so a ghost looks like the real thing. Also the road
## ribbon meshes the piece previews use. Owner: C24.
## NET: local only, never simulated (no scripts, no physics).
## Public API: static ghost(def, tint) -> Node3D, static set_tint(node, tint), static ribbon(pts, width, lift),
##   static road_ghost(pts, width) (road + low walls), static footprint_box(def).

## Alpha of the see-through ghost (GeometryInstance3D.transparency).
const GHOST_TRANSPARENCY := 0.4 # TUNE


## A see-through, tinted copy of `def`'s scene (or a footprint box if it has none). Not in the tree yet.
static func ghost(def: ItemDef, tint: Color) -> Node3D:
	var root: Node3D = null
	if def and def.scene:
		var inst := def.scene.instantiate()
		root = inst as Node3D
		if root == null:
			inst.free()
		else:
			_strip(root)
	if root == null or not _has_geometry(root):
		if root:
			root.free()
		root = Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = footprint_box(def)
		mi.position.y = (mi.mesh as BoxMesh).size.y * 0.5
		root.add_child(mi)
	set_tint(root, tint)
	return root


## Recolour every mesh under `node`: its own materials show through `tint` (alpha = tint strength).
static func set_tint(node: Node, tint: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = tint
	mat.no_depth_test = false
	_apply(node, mat)


## A box the size of `def`'s footprint (tall for blocking obstacles, flat for surface patches).
static func footprint_box(def: ItemDef) -> BoxMesh:
	var box := BoxMesh.new()
	var f := def.footprint if def else Vector2(2, 2)
	box.size = Vector3(maxf(f.x, 0.5), 1.2 if def and def.blocks_path else 0.15, maxf(f.y, 0.5))
	return box


## Flat strip `width` m wide along world points `pts`, lifted a little above the road. null if < 2 points.
static func ribbon(pts: PackedVector3Array, width: float, lift := 0.25) -> ArrayMesh:
	if pts.size() < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	st.set_normal(Vector3.UP)
	for i in pts.size():
		var right := _right(pts, i) * width * 0.5
		var up := Vector3.UP * lift
		st.add_vertex(pts[i] - right + up)
		st.add_vertex(pts[i] + right + up)
	return st.commit()


## The road along `pts` as it will look: a strip plus low walls on both edges and chevrons pointing the
## driving direction every few metres. null if < 2 points.
static func road_ghost(pts: PackedVector3Array, width: float, wall_h := 1.2) -> ArrayMesh:
	if pts.size() < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := Vector3.UP * 0.2
	for i in pts.size() - 1:
		var r0 := _right(pts, i) * width * 0.5
		var r1 := _right(pts, i + 1) * width * 0.5
		var a := pts[i] + lift
		var b := pts[i + 1] + lift
		_quad(st, a - r0, a + r0, b + r1, b - r1) # road
		for side: float in [-1.0, 1.0]: # walls
			var w0: Vector3 = a + r0 * side
			var w1: Vector3 = b + r1 * side
			_quad(st, w0, w1, w1 + Vector3.UP * wall_h, w0 + Vector3.UP * wall_h)
	var step := 6
	for i in range(3, pts.size() - 2, step): # chevrons
		var f := (pts[i + 1] - pts[i - 1]).normalized()
		var r := _right(pts, i) * width * 0.3
		var tip := pts[i] + f * 1.6 + lift * 2.0
		var back := pts[i] + lift * 2.0
		st.add_vertex(back - r)
		st.add_vertex(tip)
		st.add_vertex(back - r + f * 0.8)
		st.add_vertex(back + r + f * 0.8)
		st.add_vertex(tip)
		st.add_vertex(back + r)
	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


static func _right(pts: PackedVector3Array, i: int) -> Vector3:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var r := (b - a).cross(Vector3.UP)
	return r.normalized() if r.length_squared() > 1e-8 else Vector3.RIGHT


static func _strip(node: Node) -> void:
	var doomed: Array[Node] = []
	_collect(node, doomed)
	for n in doomed:
		n.get_parent().remove_child(n)
		n.free()
	_unscript(node)


static func _collect(node: Node, out: Array[Node]) -> void:
	for c in node.get_children():
		if c is CollisionObject3D or c is CollisionShape3D or c is AudioStreamPlayer3D or c is GPUParticles3D:
			out.append(c)
		else:
			_collect(c, out)


static func _unscript(node: Node) -> void:
	node.set_script(null)
	for c in node.get_children():
		_unscript(c)


static func _has_geometry(node: Node) -> bool:
	if node is GeometryInstance3D:
		return true
	for c in node.get_children():
		if _has_geometry(c):
			return true
	return false


static func _apply(node: Node, mat: Material) -> void:
	if node is GeometryInstance3D:
		var g := node as GeometryInstance3D
		g.transparency = GHOST_TRANSPARENCY
		g.material_overlay = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_apply(c, mat)
