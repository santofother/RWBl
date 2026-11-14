extends SceneTree
## One-off generator for track.tscn's Path3D curve (run: $GODOT --headless --path rwbl --script res://game/track/tools/gen_track.gd).
## Owner: C05. Builds the greybox loop from straights + arcs with bezier handles, then saves track.tscn.
## After this the curve is plain editable data in the scene; you never need to run this again.

const K := 0.5522847498 # bezier circle constant for a 90 degree arc

var _pts: Array = [] # [pos, in_handle, out_handle]
var _pos := Vector3.ZERO
var _dir := Vector3.RIGHT


func _init() -> void:
	_pts.append([_pos, Vector3.ZERO, Vector3.ZERO])
	_line(190.0)
	_arc(180.0, 24.0, 1.0)  # hairpin (right)
	_line(60.0)
	_arc(45.0, 41.0, -1.0)  # S-bend: left then right
	_arc(45.0, 41.0, 1.0)
	_line(122.0)
	_arc(180.0, 36.0, 1.0)  # wide sweeper (right)
	_line(50.0)              # ends on the start line again
	print("closing error: ", _pos.distance_to(Vector3.ZERO))
	var curve := Curve3D.new()
	curve.bake_interval = 0.5
	for i in _pts.size():
		var p: Array = _pts[i]
		curve.add_point(p[0], p[1], p[2])
	# last point == first point closes the loop; carry the first point's out handle to it
	curve.set_point_position(_pts.size() - 1, Vector3.ZERO)
	var scene := load("res://game/track/track.tscn") as PackedScene
	var root := scene.instantiate()
	var path := root.get_node_or_null("Path") as Path3D
	if path == null:
		path = Path3D.new()
		path.name = "Path"
		root.add_child(path)
		path.owner = root
	path.curve = curve
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://game/track/track.tscn")
	quit()


func _line(l: float) -> void:
	_pos += _dir * l
	_pts.append([_pos, Vector3.ZERO, Vector3.ZERO])
	# straight: zero handles (the previous point's out handle stays zero)


## Turn `deg` degrees with radius `r`. `side` +1 = right (+Z when heading +X), -1 = left.
func _arc(deg: float, r: float, side: float) -> void:
	var left := -side # unused name kept for clarity of maths below
	var remaining := deg
	while remaining > 0.001:
		var a := minf(remaining, 90.0)
		remaining -= a
		var rad := deg_to_rad(a)
		var right := _dir.cross(Vector3.UP) * -1.0 # right of heading
		right = Vector3.UP.cross(_dir) * -1.0
		right = _dir.rotated(Vector3.UP, -PI * 0.5) # heading +X -> -90deg about Y -> +Z
		var center := _pos + right * side * r
		var h := 4.0 / 3.0 * tan(rad / 4.0) * r
		var new_dir := _dir.rotated(Vector3.UP, -rad * side)
		var radial := _pos - center
		var new_pos := center + radial.rotated(Vector3.UP, -rad * side)
		var last: Array = _pts[_pts.size() - 1]
		last[2] = _dir * h
		_pts.append([new_pos, -new_dir * h, Vector3.ZERO])
		_pos = new_pos
		_dir = new_dir
