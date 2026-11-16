class_name PathValidator
extends RefCounted
## "Is there still a drivable lap?" check for the build phase (DESIGN §5.5 track validation). Owner: C08.
## Grid of `cell` m over `track.get_bounds()`. A cell is drivable when its centre is on the road at least
## `half_width` from the edge (= the road eroded by half a chariot) and outside every blocker footprint grown by
## `half_width`. The start line is a cut: a flood fill from the cells just after it must reach the cells just
## before it (going the whole lap). The road part of the grid is computed once (`build_base()`), each check
## only stamps the blockers and floods.
## NET: host validates; clients run the same check for the ghost preview.
## Public API: `build_base(track, cell, half_width)`, `has_path(blockers) -> bool`, `last_ms`, `base_ms`.

## Milliseconds the last has_path() took.
var last_ms := 0.0
## Milliseconds build_base() took.
var base_ms := 0.0

var _track: Track
var _cell := 1.0
var _half := 1.3
var _origin := Vector2.ZERO # world x/z of the grid corner
var _nx := 0
var _nz := 0
var _len := 0.0
var _base := PackedByteArray() # 1 = drivable road cell
var _prog := PackedFloat32Array() # progress of each cell centre (only meaningful on road cells)


## Precompute the road cells of `track`. Call again if the track changes.
func build_base(track: Track, cell: float, half_width: float) -> void:
	var t0 := Time.get_ticks_usec()
	_track = track
	_cell = cell
	_half = half_width
	_len = track.length()
	var b := track.get_bounds()
	_origin = Vector2(b.position.x, b.position.z)
	_nx = int(ceil(b.size.x / cell))
	_nz = int(ceil(b.size.z / cell))
	_base.resize(_nx * _nz)
	_base.fill(0)
	_prog.resize(_nx * _nz)
	_prog.fill(0.0)
	var limit := track.track_width * 0.5 - half_width
	var y := track.global_position.y
	for k in _nz:
		for i in _nx:
			var pos := Vector3(_origin.x + (i + 0.5) * cell, y, _origin.y + (k + 0.5) * cell)
			var p := track.progress_at(pos)
			var t := track.transform_at(p)
			var d := pos - t.origin
			d.y = 0.0
			if absf(d.dot(t.basis.x)) <= limit and absf(d.dot(t.basis.z)) <= cell:
				var idx := k * _nx + i
				_base[idx] = 1
				_prog[idx] = p
	_bridge_loops(track, limit)
	base_ms = (Time.get_ticks_usec() - t0) / 1000.0


# FIX(C21, Claude): a loop's ground footprint isn't a flat lane, so the flood couldn't get from its entry to its
# exit. Mark a straight corridor (road width) from the loop's entry point to its exit point as drivable. Items
# can't go on a loop (Track no-build zone), so nothing ever needs to block it.
func _bridge_loops(track: Track, limit: float) -> void:
	for z: Vector2 in track.loop_zones():
		var a := track.point_at(z.x)
		var b := track.point_at(z.y)
		var n := maxi(2, ceili(a.distance_to(b) / (_cell * 0.5)))
		for s in n + 1:
			var f := float(s) / n
			var c := a.lerp(b, f)
			var r := maxf(limit, _cell)
			for k in range(int(floor((c.z - r - _origin.y) / _cell)), int(floor((c.z + r - _origin.y) / _cell)) + 1):
				for i in range(int(floor((c.x - r - _origin.x) / _cell)), int(floor((c.x + r - _origin.x) / _cell)) + 1):
					if i < 0 or k < 0 or i >= _nx or k >= _nz:
						continue
					var cc := Vector2(_origin.x + (i + 0.5) * _cell, _origin.y + (k + 0.5) * _cell)
					if cc.distance_to(Vector2(c.x, c.z)) <= r:
						_base[k * _nx + i] = 1
						_prog[k * _nx + i] = lerpf(z.x, z.y, f)


## True if a lap is still drivable with `blockers` = Array of [Transform3D, Vector2 footprint] in place.
func has_path(blockers: Array) -> bool:
	var t0 := Time.get_ticks_usec()
	var mask := _base.duplicate()
	for b: Array in blockers:
		_stamp(mask, b[0], b[1])
	var ok := _flood(mask)
	last_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return ok


func _stamp(mask: PackedByteArray, xform: Transform3D, footprint: Vector2) -> void:
	var hx := footprint.x * 0.5 + _half
	var hz := footprint.y * 0.5 + _half
	var r := Vector2(hx, hz).length()
	var c := Vector2(xform.origin.x, xform.origin.z)
	var i0 := maxi(0, int(floor((c.x - r - _origin.x) / _cell)))
	var i1 := mini(_nx - 1, int(floor((c.x + r - _origin.x) / _cell)))
	var k0 := maxi(0, int(floor((c.y - r - _origin.y) / _cell)))
	var k1 := mini(_nz - 1, int(floor((c.y + r - _origin.y) / _cell)))
	# Footprint axes on the ground (items are upright, so only yaw matters).
	var ax := Vector2(xform.basis.x.x, xform.basis.x.z).normalized()
	var az := Vector2(xform.basis.z.x, xform.basis.z.z).normalized()
	for k in range(k0, k1 + 1):
		for i in range(i0, i1 + 1):
			var idx := k * _nx + i
			if mask[idx] == 0:
				continue
			var d := Vector2(_origin.x + (i + 0.5) * _cell, _origin.y + (k + 0.5) * _cell) - c
			if absf(d.dot(ax)) <= hx and absf(d.dot(az)) <= hz:
				mask[idx] = 0


func _flood(mask: PackedByteArray) -> bool:
	var cut := 3.0 * _cell # WHY: "just after / just before the line" band, a few cells deep
	var seen := PackedByteArray()
	seen.resize(mask.size())
	seen.fill(0)
	var queue := PackedInt32Array()
	for idx in mask.size():
		if mask[idx] == 1 and _prog[idx] < cut:
			queue.append(idx)
			seen[idx] = 1
	var head := 0
	var half_len := _len * 0.5
	while head < queue.size():
		var a := queue[head]
		head += 1
		var pa := _prog[a]
		if pa > _len - cut:
			return true
		var ai := a % _nx
		for n: int in [a - 1, a + 1, a - _nx, a + _nx]:
			if n < 0 or n >= mask.size() or seen[n] == 1 or mask[n] == 0:
				continue
			if (n == a - 1 and ai == 0) or (n == a + 1 and ai == _nx - 1):
				continue
			if absf(_prog[n] - pa) > half_len: # the start line cut: never step across it
				continue
			seen[n] = 1
			queue.append(n)
	return false
