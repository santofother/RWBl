class_name TrackPiece
extends Node3D
## Base of a track piece shape (DESIGN §5.6, C19). Owner: C19. One scene per piece in `game/track/pieces/`,
## referenced by `ItemDef.piece`; the root script extends this and builds its centre line in code from straights
## and arcs (`_begin`, `_straight`, `_arc`). Track instantiates the scene once, reads `build_points()` and frees it.
## Local space: starts at (0,0,0) heading -Z, ends at (0,0,-chord()) heading -Z, so the piece replaces `chord()` m
## of straight road and the loop stays closed. +X = right of the driving direction; Track mirrors X when flipped.
## NET: shape data only, identical on every peer.
## Public API: `build_points() -> [PackedVector3Array points, PackedVector3Array tangents]`, `build_curve()`,
##   `chord()`, `flippable`.
# CONTRACT: points start at Vector3.ZERO heading -Z and end at (0, 0, -chord()) heading -Z.

## Sample spacing of the built centre line (m).
const STEP := 1.0

## Whether R (flip left/right) makes sense for this shape.
@export var flippable := true

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
