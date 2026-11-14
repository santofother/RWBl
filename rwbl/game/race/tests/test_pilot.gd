class_name RaceTestPilot
extends BotDriver
## Test-only autopilot (C05): steers along the centre line and brakes for corners so a bot stays on the pit-edged
## track. WHY: the C02 stub driver is flat out and falls off the hairpin; C06 owns the real bots.
## NET: host only. Same `compute_input()` API as BotDriver.

const LOOK := 9.0
const PREVIEW := 30.0
const LAT_ACCEL := 8.0 # m/s² we allow in corners

var _o := ChariotInput.new()


func compute_input(chariot: Chariot, track: Track, _delta: float) -> ChariotInput:
	_o.seq += 1
	var p := track.progress_at(chariot.global_position)
	var target := track.point_at(p + LOOK + chariot.get_speed() * 0.25)
	var local := chariot.global_transform.affine_inverse() * target
	var steer := atan2(local.x, -local.z) * 2.0
	var f0 := track.transform_at(p).basis.z * -1.0
	var f1 := track.transform_at(p + PREVIEW).basis.z * -1.0
	var curve := absf(f0.signed_angle_to(f1, Vector3.UP)) / PREVIEW
	var want := clampf(sqrt(LAT_ACCEL / maxf(curve, 0.001)), 8.0, 40.0)
	var speed := chariot.get_speed()
	_o.steer = clampf(steer, -1.0, 1.0)
	_o.throttle = 1.0 if speed < want else 0.0
	_o.brake = 1.0 if speed > want + 2.0 else 0.0
	return _o
