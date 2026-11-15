extends Item
## Pit: a grounded chariot over the hole dies (`kill(&"pit", owner_slot, uid)`). Jumping over it is safe.
## Respawn and the time penalty are C12's job. Owner: C10.
## NET: host.


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	for c: Chariot in trigger_chariots():
		if c.grounded and not c.dead:
			report_hit(c)
			c.kill(&"pit", owner_slot, uid)
