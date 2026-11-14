class_name BotDriver
extends RefCounted
## AI driver for one bot slot: looks at its chariot and the track and produces a ChariotInput, exactly like a
## player's keyboard would (DESIGN §11 Q6). Owner: C06.
## C02 STUB: steer toward a point LOOKAHEAD metres ahead on the centre line, full throttle.
## NET: host only. Public API: `compute_input(chariot, track, delta) -> ChariotInput`.

const LOOKAHEAD := 10.0 # TUNE

var _out := ChariotInput.new()


## Input for this tick.
func compute_input(chariot: Chariot, track: Track, _delta: float) -> ChariotInput:
	_out.seq += 1
	var target := track.point_at(track.progress_at(chariot.global_position) + LOOKAHEAD)
	var local := chariot.global_transform.affine_inverse() * target
	_out.steer = clampf(atan2(local.x, -local.z) * 2.0, -1.0, 1.0)
	_out.throttle = 1.0
	_out.brake = 0.0
	return _out
