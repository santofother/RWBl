extends Item
## Grey box sized to the def footprint, used by every def until its real scene exists. Owner: C10.
## NET: every peer. No gameplay effect.


func placed(d: ItemDef, slot: int, id: int) -> void:
	super.placed(d, slot, id)
	var mesh := $Mesh as MeshInstance3D
	var box := BoxMesh.new()
	var h := 1.2 if d.blocks_path else 0.1
	box.size = Vector3(d.footprint.x, h, d.footprint.y)
	mesh.mesh = box
	mesh.position.y = h * 0.5
