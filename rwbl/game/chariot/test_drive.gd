extends Node3D
## Offline test drive (F6 on test_drive.tscn): one Chariot on the Track, driven by PlayerInput, chase camera,
## speed / stamina / surface label, and a few surface patches (oil, mud, ice, gravel) to feel the grip.
## Owner: C04. No network: this script calls Chariot.step() itself.
## Keys: W/S throttle/brake, A/D steer, Space whip, R respawn, J jump (test ramp launch), 1/2 break a wheel,
## F2 tuning panel.
## NET: none (local only).
## Public API: none.

## [progress m, surface, half size x/z, colour]
const PATCHES := [
	[40.0, Surface.OIL, Vector2(5, 4), Color(0.05, 0.05, 0.06)],
	[75.0, Surface.MUD, Vector2(6, 5), Color(0.35, 0.22, 0.1)],
	[130.0, Surface.ICE, Vector2(7, 8), Color(0.7, 0.9, 1.0)],
	[215.0, Surface.GRAVEL, Vector2(7, 6), Color(0.5, 0.5, 0.5)],
]

var _input := PlayerInput.new()
var _last_whip := 0

@onready var _track: Track = $Track
@onready var _chariot: Chariot = $Chariot
@onready var _cam: Camera3D = $Camera3D
@onready var _label: Label = $HUD/Label


func _ready() -> void:
	_chariot.slot = 0
	_chariot.track = _track
	_chariot.set_team_color(Color(0.85, 0.15, 0.12))
	_chariot.respawn(_track.start_transform(0))
	for p: Array in PATCHES:
		var quad := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = (p[2] as Vector2) * 2.0
		quad.mesh = plane
		var m := StandardMaterial3D.new()
		m.albedo_color = p[3]
		quad.material_override = m
		add_child(quad)
		quad.global_transform = _track.transform_at(p[0])
		quad.global_position += Vector3.UP * 0.04
		_track.register_surface_patch(quad, p[1], p[2])
	_cam.global_position = _chariot.global_position + Vector3(0, 5, 10)


func _physics_process(delta: float) -> void:
	var inp := _input.read(0).copy()
	inp.whip = inp.whip_count != _last_whip # same one-tick rule as ChariotSync._consume_input()
	_last_whip = inp.whip_count
	_chariot.step(inp, delta)
	if _chariot.dead:
		_chariot.respawn(_track.respawn_transform(_track.progress_at(_chariot.global_position)))


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_R:
			_chariot.respawn(_track.respawn_transform(_track.progress_at(_chariot.global_position)))
		KEY_J:
			_chariot.apply_impulse(Vector3.UP * 10.0 * _chariot.tuning.horse_mass)
		KEY_1:
			_chariot.damage_wheel(ChariotSnapshot.WHEEL_LEFT)
		KEY_2:
			_chariot.damage_wheel(ChariotSnapshot.WHEEL_RIGHT)


func _process(delta: float) -> void:
	var c := _chariot
	var back := c.global_basis.z
	var want := c.global_position + back * 10.0 + Vector3.UP * 4.5
	_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-4.0 * delta))
	_cam.look_at(c.global_position + c.get_forward() * 4.0 + Vector3.UP * 1.2)
	var lines := PackedStringArray([
		"speed %4.1f m/s   stamina %3d%%   surface %s" % [c.get_speed(), int(c.stamina * 100.0), c.surface],
		"cart %+4.0f°   slip %+4.0f°   %s%s" % [rad_to_deg(c.cart_angle), _slip_deg(c),
			"BOOST " if c.has_effect(Effects.BOOST) else "", "" if c.grounded else "AIR"],
		"W/S drive  A/D steer  Space whip  R respawn  J jump  1/2 break wheel  F2 tuning",
	])
	_label.text = "\n".join(lines)


static func _slip_deg(c: Chariot) -> float:
	var v := Vector3(c.velocity.x, 0, c.velocity.z)
	if v.length() < 1.0:
		return 0.0
	return rad_to_deg(c.get_forward().signed_angle_to(v, Vector3.UP))
