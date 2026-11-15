class_name DamageFx
extends RefCounted
## Cosmetic damage effects (DESIGN §6 "Stylized gore": cartoonish, nothing lingers). Owner: C12.
## Combat calls these on every peer when a snapshot shows a newly broken wheel or a new death.
## Nothing here touches gameplay: popped wheels only collide with the track (WORLD, WALL).
## NET: every peer, visual only.
## Public API: static wheel_pop(parent, chariot, side, tuning), static burst(parent, pos, color).

const WHEEL_RADIUS := 0.55
const FADE_TIME := 0.6


## Spawn a copy of the chariot's wheel as a RigidBody3D that bounces away from `side` and fades out.
static func wheel_pop(parent: Node, c: Chariot, side: int, t: CombatTuning) -> RigidBody3D:
	var left := side == ChariotSnapshot.WHEEL_LEFT
	var src := c.get_node_or_null(^"Cart/CartModel/Body/WheelL" if left else ^"Cart/CartModel/Body/WheelR") as Node3D
	var body := RigidBody3D.new()
	body.name = "WheelFx"
	body.collision_layer = 0
	body.collision_mask = Layers.WORLD | Layers.WALL
	body.mass = 8.0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.5
	body.physics_material_override = mat
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = WHEEL_RADIUS
	cyl.height = 0.15
	shape.shape = cyl
	shape.rotation.z = PI * 0.5 # WHY: cylinder axis is Y; the axle is X
	body.add_child(shape)
	var xf := c.global_transform
	if src:
		var vis := src.duplicate() as Node3D
		vis.visible = true
		body.add_child(vis)
		vis.transform = Transform3D.IDENTITY
		xf = src.global_transform
	else:
		var mi := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = WHEEL_RADIUS
		m.bottom_radius = WHEEL_RADIUS
		m.height = 0.15
		mi.mesh = m
		mi.rotation.z = PI * 0.5
		body.add_child(mi)
	parent.add_child(body)
	body.global_transform = xf
	var cart := c.get_node_or_null(^"Cart") as Node3D
	var right := cart.global_basis.x if cart else c.global_basis.x
	var out := -right if left else right
	body.linear_velocity = c.velocity * 0.6 + out * t.wheel_fx_kick + Vector3.UP * 4.0
	body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-3, 3), randf_range(-8, 8))
	_fade_and_free(body, t.wheel_fx_life)
	return body


## Confetti-style burst at `pos` (death): bright cubes in the team colour and red, gone in ~1.5 s.
static func burst(parent: Node, pos: Vector3, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "BurstFx"
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 80
	p.lifetime = 1.3
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0, -14, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.16, 0.04)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = m
	p.mesh = box
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(0.9, 0.08, 0.1))
	g.add_point(0.5, Color(1.0, 0.85, 0.2))
	p.color_initial_ramp = g
	parent.add_child(p)
	p.global_position = pos + Vector3.UP * 1.0
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)
	return p


static func _fade_and_free(body: Node3D, life: float) -> void:
	var tw := body.create_tween()
	tw.tween_interval(life)
	tw.tween_callback(func() -> void:
		var tw2 := body.create_tween().set_parallel(true)
		for g: Node in body.find_children("*", "GeometryInstance3D", true, false):
			tw2.tween_property(g, ^"transparency", 1.0, FADE_TIME)
		tw2.chain().tween_callback(body.queue_free))
