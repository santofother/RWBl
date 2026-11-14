class_name PlayerInput
extends RefCounted
## Reads the local keyboard/gamepad into a ChariotInput (input map actions from project.godot). Owner: C04.
## NET: local peer only; ChariotSync calls `read()` once per physics tick for the local player's slot.
## Public API: `read(slot) -> ChariotInput`.

var _out := ChariotInput.new()
var _seq := 0


## Current input for this tick. Keeps press counters between calls, so reuse one PlayerInput per player.
func read(_slot: int) -> ChariotInput:
	_seq += 1
	_out.seq = _seq
	_out.steer = Input.get_axis(&"steer_left", &"steer_right")
	_out.throttle = Input.get_action_strength(&"throttle")
	_out.brake = Input.get_action_strength(&"brake")
	if Input.is_action_just_pressed(&"whip"):
		_out.press_whip()
	if Input.is_action_just_pressed(&"action"):
		_out.press_action()
	return _out
