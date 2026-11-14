class_name ChariotInput
extends RefCounted
## One tick of driving input. The ONLY thing clients send to the host; bots fill it too. Owner: C02 (contract).
## NET: built on the driving peer (a player's machine, or the host for bots), sent to the host, consumed by
## `Chariot.step()` on the host (and by the owner's prediction in C07).
## Public API: fields below, `press_whip()`, `press_action()`, `press_jump()`, `to_bytes()`, `from_bytes()`, `copy()`.
# CONTRACT: fields and the 10-byte wire format below (jump added in C04 round 4, user-approved design change). Changing them needs the head engineer.

## -1 = full left, +1 = full right.
var steer := 0.0
## 0..1 forward drive.
var throttle := 0.0
## 0..1 brake.
var brake := 0.0
## True for exactly one host tick after a whip press. Set by ChariotSync from `whip_count`; the sim reads it.
var whip := false
## True for exactly one host tick after an action press (spear / pickup, wave 4).
var action := false
## True for exactly one host tick after a jump press.
var jump := false
## Press counters (wrap at 256). Producers call press_whip()/press_action(); the host turns changes into
## `whip`/`action`.
# WHY: a counter survives lost unreliable packets; a one-tick bool would drop taps.
var whip_count := 0
## See `whip_count`.
var action_count := 0
## See `whip_count`.
var jump_count := 0
## Increases by one per input the producer sends. Used by prediction / reconciliation (C07).
var seq := 0


## Register one whip tap.
func press_whip() -> void:
	whip_count = (whip_count + 1) & 0xFF


## Register one action-button tap.
func press_action() -> void:
	action_count = (action_count + 1) & 0xFF


## Register one jump tap.
func press_jump() -> void:
	jump_count = (jump_count + 1) & 0xFF


## Wire format: s8 steer, u8 throttle, u8 brake, u8 whip_count, u8 action_count, u32 seq, u8 jump_count (10 bytes).
func to_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(10)
	b.encode_s8(0, int(roundf(clampf(steer, -1.0, 1.0) * 127.0)))
	b.encode_u8(1, int(roundf(clampf(throttle, 0.0, 1.0) * 255.0)))
	b.encode_u8(2, int(roundf(clampf(brake, 0.0, 1.0) * 255.0)))
	b.encode_u8(3, whip_count & 0xFF)
	b.encode_u8(4, action_count & 0xFF)
	b.encode_u32(5, seq)
	b.encode_u8(9, jump_count & 0xFF)
	return b


## Inverse of to_bytes(). Returns a neutral input for malformed data.
static func from_bytes(b: PackedByteArray) -> ChariotInput:
	var i := ChariotInput.new()
	if b.size() < 9:
		return i
	i.steer = b.decode_s8(0) / 127.0
	i.throttle = b.decode_u8(1) / 255.0
	i.brake = b.decode_u8(2) / 255.0
	i.whip_count = b.decode_u8(3)
	i.action_count = b.decode_u8(4)
	i.seq = b.decode_u32(5)
	if b.size() >= 10:
		i.jump_count = b.decode_u8(9)
	return i


## Field-by-field copy.
func copy() -> ChariotInput:
	var i := ChariotInput.new()
	i.steer = steer
	i.throttle = throttle
	i.brake = brake
	i.whip = whip
	i.action = action
	i.jump = jump
	i.whip_count = whip_count
	i.action_count = action_count
	i.jump_count = jump_count
	i.seq = seq
	return i
