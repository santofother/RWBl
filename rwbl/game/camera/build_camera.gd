class_name BuildCamera
extends Camera3D
## Top-down orthographic-style camera for the build phase (DESIGN §7). Owner: C08.
## C02 STUB: frames the whole track from above. C08 adds pan/zoom if needed.
## NET: local only. Public API: `frame(bounds: AABB)`.


## Look straight down so `bounds` fills the view.
func frame(bounds: AABB) -> void:
	projection = PROJECTION_ORTHOGONAL
	var c := bounds.get_center()
	size = maxf(bounds.size.z, bounds.size.x * 9.0 / 16.0) * 1.05
	global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), c + Vector3.UP * 120.0)
	far = 300.0
