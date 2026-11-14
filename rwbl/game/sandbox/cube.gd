extends Node3D
## One player's cube in the C01 network sandbox. Owner: C01. Temporary: C02/C07 replace it with the
## host-authoritative chariot (clients send ChariotInput, host simulates).
## NET: owner client, authoritative over its own position (LastMage pattern). The MultiplayerSynchronizer
## child replicates `position` from the owning peer to everyone else.
## Public API: `peer_id`, `display_name` (set by the spawner before the node enters the tree).

# TUNE: sandbox only.
const SPEED := 6.0
const HALF_EXTENT := 19.0 ## keep the cube on the 40 x 40 plane

## Peer that owns (drives) this cube. Also the node name.
var peer_id := 1
## Player name shown above the cube and printed by the autotest.
var display_name := "Player"


func _enter_tree() -> void:
	# NET: must run before the synchronizer is ready so it picks up the right authority.
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	($Label as Label3D).text = display_name
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(float(peer_id % 97) * 0.173, 1.0), 0.7, 0.95)
	($Mesh as MeshInstance3D).material_override = mat


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if NetworkManager.test_target != null: # headless test hook: park at a known spot
		var t: Vector2 = NetworkManager.test_target
		position = Vector3(t.x, position.y, t.y)
		return
	var dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	position.x = clampf(position.x + dir.x * SPEED * delta, -HALF_EXTENT, HALF_EXTENT)
	position.z = clampf(position.z + dir.y * SPEED * delta, -HALF_EXTENT, HALF_EXTENT)
