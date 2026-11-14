extends Node3D
## One player's cube in the network sandbox (milestone N1). Owner: C02 (was C01).
## Since C02 it follows the real authority model: the owner sends ChariotInput, the host moves the cube
## (step), clients show host snapshots (apply_snapshot). Same "drivable" interface as Chariot, driven by
## ChariotSync. NET: host simulates; every peer renders.
## Public API: `peer_id`, `slot`, `display_name` (set by the spawner), step(), get_snapshot(), apply_snapshot().

# TUNE: sandbox only.
const SPEED := 6.0
const HALF_EXTENT := 19.0 ## keep the cube on the 40 x 40 plane

## Peer that drives this cube. Also the node name.
var peer_id := 1
## ChariotSync slot.
var slot := 0
## Player name shown above the cube and printed by the autotest.
var display_name := "Player"


func _ready() -> void:
	($Label as Label3D).text = display_name
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PlayerInfo.color_for_slot(slot)
	($Mesh as MeshInstance3D).material_override = mat


## Host: move by input. steer = x axis, throttle/brake = -z/+z.
func step(input: ChariotInput, delta: float) -> void:
	position.x = clampf(position.x + input.steer * SPEED * delta, -HALF_EXTENT, HALF_EXTENT)
	position.z = clampf(position.z + (input.brake - input.throttle) * SPEED * delta, -HALF_EXTENT, HALF_EXTENT)


## Host: snapshot in the ChariotSnapshot layout (position only).
func get_snapshot() -> PackedFloat32Array:
	return ChariotSnapshot.make(position, Quaternion.IDENTITY, Vector3.ZERO, 0.0, 0.0, 0, 1.0, 0)


## Clients: show a host snapshot.
func apply_snapshot(s: PackedFloat32Array) -> void:
	position = ChariotSnapshot.pos(s)
