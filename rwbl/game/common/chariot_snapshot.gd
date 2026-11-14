class_name ChariotSnapshot
extends RefCounted
## Layout of one chariot's network snapshot (a PackedFloat32Array of SIZE floats). Owner: C02 (contract).
## NET: built by `Chariot.get_snapshot()` on the host, applied by `Chariot.apply_snapshot()` on clients.
## ChariotSync sends all chariots in one packet: [slot, SIZE floats, slot, SIZE floats, ...].
## Public API: index constants, flag/wheel bits, `make()`, `pos()`, `rot()`, `vel()`.
# CONTRACT: indices, SIZE and bit values. Add fields only at the end and bump SIZE (head engineer).

const POS := 0 ## 3 floats: horse pair world position
const ROT := 3 ## 4 floats: horse pair world rotation quaternion (x, y, z, w)
const VEL := 7 ## 3 floats: world velocity
const CART_ANGLE := 10 ## cart yaw relative to the horses (radians, + = cart swung right)
const CART_ANG_VEL := 11 ## rad/s
const WHEELS := 12 ## broken-wheel bits (WHEEL_*)
const STAMINA := 13 ## 0..1
const FLAGS := 14 ## FLAG_* bits
const SIZE := 15

const WHEEL_LEFT := 1
const WHEEL_RIGHT := 2

const FLAG_STUNNED := 1
const FLAG_BOOSTING := 2
const FLAG_DEAD := 4
const FLAG_FROZEN := 8
const FLAG_BARBED := 16


## Build a snapshot array from its parts.
static func make(p: Vector3, r: Quaternion, v: Vector3, cart_angle: float, cart_ang_vel: float,
		wheels: int, stamina: float, flags: int) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(SIZE)
	s[POS] = p.x; s[POS + 1] = p.y; s[POS + 2] = p.z
	s[ROT] = r.x; s[ROT + 1] = r.y; s[ROT + 2] = r.z; s[ROT + 3] = r.w
	s[VEL] = v.x; s[VEL + 1] = v.y; s[VEL + 2] = v.z
	s[CART_ANGLE] = cart_angle
	s[CART_ANG_VEL] = cart_ang_vel
	s[WHEELS] = wheels
	s[STAMINA] = stamina
	s[FLAGS] = flags
	return s


## Position part of a snapshot.
static func pos(s: PackedFloat32Array) -> Vector3:
	return Vector3(s[POS], s[POS + 1], s[POS + 2])


## Rotation part of a snapshot.
static func rot(s: PackedFloat32Array) -> Quaternion:
	return Quaternion(s[ROT], s[ROT + 1], s[ROT + 2], s[ROT + 3])


## Velocity part of a snapshot.
static func vel(s: PackedFloat32Array) -> Vector3:
	return Vector3(s[VEL], s[VEL + 1], s[VEL + 2])
