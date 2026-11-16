class_name TrackPiece
extends Node3D
## Base of a track piece shape (DESIGN §5.6, C19, C22). Owner: C22. One scene per piece in `game/track/pieces/`,
## referenced by `ItemDef.piece` (cards) or by id in a course (`start`, `straight`, ...). The root script extends
## this and builds its centre line in code from straights and arcs (`_begin`, `_straight`, `_arc`). Track
## instantiates the scene once, reads `build_points()` and frees it, then chains pieces end to start (C22).
## Local space: starts at (0,0,0) heading -Z; the end may be anywhere with any heading (`end_transform()`).
## +X = right of the driving direction; Track mirrors X when flipped.
## NET: shape data only, identical on every peer.
## Public API: `build_points() -> [PackedVector3Array points, PackedVector3Array tangents, PackedVector3Array ups,
##   PackedByteArray loop]`, `build_curve()`, `chord()`, `end_transform()`, `road_length()`, `flippable`, `line_at`.
## C21: `ups` = road normal at every point (UP on flat road), `loop` = 1 where the chariot rides the road surface
##   with surface gravity (`_loop()`, a vertical loop). Old callers read only [0] and [1].
## C20: `_slopes()` (straight ahead with height, from a slope profile) and `_banked_arc()` (a turn tilted towards
##   its inside). Track takes the road normal from `ups` rotated to stay square to the tangent, so slopes can
##   leave `ups` at UP.
# CONTRACT: points start at Vector3.ZERO heading -Z. The next piece starts at end_transform().
# CONTRACT (C21): the road normal is UP at the first and last point of every piece (joints are flat).
# CONTRACT (C20): the first and last tangent are level (y = 0), so the next piece starts level; height pieces end at
#   the height they started (the finish stays at y = 0).

## Sample spacing of the built centre line (m).
const STEP := 1.0

## Whether R (flip left/right) makes sense for this shape.
@export var flippable := true
## Start / finish pieces (C22): metres from the piece start where the start or finish line is; -1 = no line.
@export var line_at := -1.0

var _pts := PackedVector3Array()
var _tans := PackedVector3Array()
var _ups := PackedVector3Array()
var _flags := PackedByteArray()
var _dir := Vector3.FORWARD


## The centre line as dense points + unit tangents + road normals + loop flags (local space). Subclasses override
## `_shape()`.
func build_points() -> Array:
	_begin()
	_shape()
	return [_pts, _tans, _ups, _flags]


## The centre line as a smooth Curve3D (local space), for the editor and debugging.
func build_curve() -> Curve3D:
	var pt: Array = build_points()
	return Track.points_to_curve(pt[0], pt[1])


## Start-to-end distance in metres. Must equal the ItemDef's `piece_length`.
func chord() -> float:
	var pt: Array = build_points()
	var p: PackedVector3Array = pt[0]
	return p[p.size() - 1].length()


## Where the next piece starts (local space): the last point, -Z along the last tangent.
func end_transform() -> Transform3D:
	var pt: Array = build_points()
	var p: PackedVector3Array = pt[0]
	var t: PackedVector3Array = pt[1]
	return Transform3D(Basis.looking_at(t[t.size() - 1], Vector3.UP), p[p.size() - 1])


## Centre-line length in metres.
func road_length() -> float:
	var pt: Array = build_points()
	var p: PackedVector3Array = pt[0]
	var len := 0.0
	for i in range(1, p.size()):
		len += p[i].distance_to(p[i - 1])
	return len


## Override: call _straight() / _arc() to draw the shape.
func _shape() -> void:
	pass


func _begin() -> void:
	_pts = PackedVector3Array([Vector3.ZERO])
	_tans = PackedVector3Array([Vector3.FORWARD])
	_ups = PackedVector3Array([Vector3.UP])
	_flags = PackedByteArray([0])
	_dir = Vector3.FORWARD


func _add(p: Vector3, tan: Vector3, up := Vector3.UP, loop := 0) -> void:
	_pts.append(p)
	_tans.append(tan)
	_ups.append(up)
	_flags.append(loop)


## Drive `length` m straight ahead.
func _straight(length: float) -> void:
	var n := maxi(1, ceili(length / STEP))
	var start := _pts[_pts.size() - 1]
	for i in range(1, n + 1):
		_add(start + _dir * length * float(i) / n, _dir)


## Turn `degrees` along a circle of `radius` m, to the right if `right` (seen from above).
func _arc(radius: float, degrees: float, right: bool) -> void:
	var side := _dir.cross(Vector3.UP) * (1.0 if right else -1.0) # unit vector towards the centre
	var start := _pts[_pts.size() - 1]
	var centre := start + side * radius
	var total := deg_to_rad(degrees) * (-1.0 if right else 1.0) # WHY: +angle about UP turns left
	var n := maxi(2, ceili(radius * deg_to_rad(degrees) / STEP))
	var dir0 := _dir
	for i in range(1, n + 1):
		var a := total * float(i) / n
		_add(centre + (start - centre).rotated(Vector3.UP, a), dir0.rotated(Vector3.UP, a))
	_dir = dir0.rotated(Vector3.UP, total)


## C21: a vertical loop of `radius` m straight ahead, drifting `offset` m sideways (+ = right) over the turn so the
## way out passes beside the way in. Upside down at the top. The road normal points at the loop's centre. Ends
## where it started heading the same way, `offset` m to the side.
func _loop(radius: float, offset: float) -> void:
	var start := _pts[_pts.size() - 1]
	var fwd := _dir
	var right := fwd.cross(Vector3.UP)
	var n := maxi(16, ceili(TAU * radius / STEP))
	_flags[_flags.size() - 1] = 1
	for i in range(1, n + 1):
		var th := TAU * float(i) / n
		# WHY: the side drift follows (1 - cos(th / 2)) / 2: slow at the bottom, so the way in and out stay apart
		var p := start + fwd * radius * sin(th) + Vector3.UP * radius * (1.0 - cos(th)) \
			+ right * offset * (1.0 - cos(th * 0.5)) * 0.5
		var tan := (fwd * radius * cos(th) + Vector3.UP * radius * sin(th) + right * offset * sin(th * 0.5) * 0.25)
		tan = tan.normalized()
		var up := -fwd * sin(th) + Vector3.UP * cos(th)
		up = (up - tan * up.dot(tan)).normalized()
		if i == n:
			up = Vector3.UP
		_add(p, tan, up, 1)


## C20: drive straight ahead with height. `knots` = Vector2(s m from here, slope dy/ds), s rising from 0; the slope
## is linear between knots (so the road bends up/down in arcs of constant curvature). Height = the exact integral.
## Use slope 0 at the first and last knot (CONTRACT: level joints).
func _slopes(knots: Array[Vector2]) -> void:
	var length := knots[knots.size() - 1].x
	var n := maxi(1, ceili(length / STEP))
	var start := _pts[_pts.size() - 1]
	for i in range(1, n + 1):
		var s := length * float(i) / n
		var h := _height(knots, s)
		var k := _slope_at(knots, s)
		_add(start + _dir * s + Vector3.UP * h, (_dir + Vector3.UP * k).normalized())


## Height of a slope profile at `s` (see _slopes).
static func _height(knots: Array[Vector2], s: float) -> float:
	var h := 0.0
	for i in range(1, knots.size()):
		var a := knots[i - 1]
		var b := knots[i]
		if s <= a.x:
			break
		var e := minf(s, b.x)
		var f := (e - a.x) / maxf(b.x - a.x, 0.0001)
		var k_e := lerpf(a.y, b.y, f)
		h += (a.y + k_e) * 0.5 * (e - a.x) # trapezoid = exact for a linear slope
	return h


static func _slope_at(knots: Array[Vector2], s: float) -> float:
	for i in range(1, knots.size()):
		if s <= knots[i].x:
			var a := knots[i - 1]
			var b := knots[i]
			return lerpf(a.y, b.y, (s - a.x) / maxf(b.x - a.x, 0.0001))
	return knots[knots.size() - 1].y


## C20: a banked turn: `ease_len` m straight while the road tilts in, an arc of `radius` m turning `degrees` (to the
## right if `right`) tilted `bank_deg` towards its inside (outside edge higher), and `ease_len` m straight tilting
## back to level. The centre line rises by `lift` × sin(tilt) (0 = the road rolls about its centre line).
## WHY: the tilt-in is a straight of its own: tilting within a few metres bends the outside lane upward so sharply
## that fast chariots take off.
func _banked_arc(radius: float, degrees: float, right: bool, bank_deg: float, ease_len: float, lift: float) -> void:
	var bank := deg_to_rad(bank_deg)
	var to_centre := _dir.cross(Vector3.UP) * (1.0 if right else -1.0)
	_tilt_straight(ease_len, bank, to_centre, lift, true)
	var start := _pts[_pts.size() - 1]
	var centre := start + to_centre * radius
	var total := deg_to_rad(degrees) * (-1.0 if right else 1.0)
	var n := maxi(2, ceili(radius * deg_to_rad(degrees) / STEP))
	var dir0 := _dir
	for i in range(1, n + 1):
		var a := total * float(i) / n
		var p := centre + (start - centre).rotated(Vector3.UP, a)
		var inward := Vector3(centre.x - p.x, 0.0, centre.z - p.z).normalized()
		_add(p, dir0.rotated(Vector3.UP, a), (Vector3.UP * cos(bank) + inward * sin(bank)).normalized())
	_dir = dir0.rotated(Vector3.UP, total)
	_tilt_straight(ease_len, bank, _dir.cross(Vector3.UP) * (1.0 if right else -1.0), lift, false)


## Straight ahead while the tilt goes 0 -> `bank` (`tilt_in`) or `bank` -> 0, leaning towards `side`.
func _tilt_straight(length: float, bank: float, side: Vector3, lift: float, tilt_in: bool) -> void:
	var n := maxi(1, ceili(length / STEP))
	var start := _pts[_pts.size() - 1]
	var y0 := start.y - (0.0 if tilt_in else lift * sin(bank))
	for i in range(1, n + 1):
		var f := float(i) / n
		var e := _ease01(f if tilt_in else 1.0 - f)
		var b := bank * e
		var de := _ease_slope(f if tilt_in else 1.0 - f) * (1.0 if tilt_in else -1.0) / maxf(length, 0.001)
		var p := start + _dir * length * f
		p.y = y0 + lift * sin(b)
		var tan := (_dir + Vector3.UP * lift * cos(b) * bank * de).normalized()
		var last := not tilt_in and i == n
		_add(p, _dir if last else tan, Vector3.UP if last else (Vector3.UP * cos(b) + side * sin(b)).normalized())


## Smoothstep 0..1 (clamped), and its derivative.
static func _ease01(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _ease_slope(x: float) -> float:
	if x <= 0.0 or x >= 1.0:
		return 0.0
	return 6.0 * x * (1.0 - x)
