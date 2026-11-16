extends Item
## Spiked log: a studded log sweeping round a post like a windmill (red/black, spikes = deadly). Angle is a
## function of NetClock.now() so all peers agree. A chariot touched by the sweeping log dies
## (`kill(&"spikes", owner, uid)`). The "Trigger" box follows the log. Owner: C25.
## NET: sweep on every peer, kills on the host. Public API: `log_angle()`.

const LOG_LEN := 5.0 ## m, matches the scene

@onready var _arm: Node3D = $Arm
@onready var _trig: Area3D = $Trigger


## Log yaw, radians, at NetClock time `at`.
func log_angle(at: float = NetClock.now()) -> float:
	var phase := float(uid) * 0.61 # WHY: several logs don't sweep in lockstep
	return TAU * (at / Item.tuning().spikelog_period + phase)


func _physics_process(_delta: float) -> void:
	_pose()
	if not multiplayer.is_server():
		return
	for c: Chariot in trigger_chariots():
		if not c.dead:
			print("[Item] SPIKES %d" % uid)
			report_hit(c)
			c.kill(&"spikes", owner_slot, uid)


func _process(_delta: float) -> void:
	_pose()


func _pose() -> void:
	var a := log_angle()
	_arm.rotation.y = a
	_trig.rotation.y = a
