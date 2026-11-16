class_name TrackPiece
extends Node3D
## Base of a track piece shape (DESIGN §5.6, C19, C22). Owner: C22. One scene per piece in `game/track/pieces/`,
## referenced by `ItemDef.piece` (cards) or by id in a course (`start`, `straight`, ...). The root script extends
## this and builds its centre line in code from straights and arcs (`_begin`, `_straight`, `_arc`). Track
## instantiates the scene once, reads `build_points()` and frees it, then chains pieces end to start (C22).
## Local space: starts at (0,0,0) heading -Z; the end may be anywhere with any heading (`end_transform()`).
## +X = right of the driving direction; Track mirrors X when flipped.
## NET: shape data only, identical on every peer.
## Public API: `build_points() -> [PackedVector3Array points, PackedVector3Array tangents]`, `build_curve()`,
##   `chord()`, `end_transform()`, `road_length()`, `flippable`, `line_at`.
# CONTRACT: points start at Vector3.ZERO heading -Z. The next piece starts at end_transform().

## Sample spacing of the built centre line (m).
const STEP := 1.0

## Whether R (flip left/right) makes sense for this shape.
@export var flippable := true
## Start / finish pieces (C22): metres from the piece start where the start or finish line is; -1 = no line.
@export var line_at := -1.0

var _pts := PackedVector3Array()
var _tans := PackedVector3Array()
var _dir := Vector3.FORWARD


## The centre line as dense points + unit tangents (local space). Subclasses override `_shape()`.
func build_points() -> Array:
	_begin()
	_shape()
	return [_pts, _tans]


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
	_dir = Vector3.FORWARD


## Drive `length` m straight ahead.
func _straight(length: float) -> void:
	var n := maxi(1, ceili(length / STEP))
	var start := _pts[_pts.size() - 1]
	for i in range(1, n + 1):
		_pts.append(start + _dir * length * float(i) / n)
		_tans.append(_dir)


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
		_pts.append(centre + (start - centre).rotated(Vector3.UP, a))
		_tans.append(dir0.rotated(Vector3.UP, a))
	_dir = dir0.rotated(Vector3.UP, total)
