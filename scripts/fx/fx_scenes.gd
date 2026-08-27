class_name FxScenes
extends RefCounted

## Authored greybox tells. Combat scripts instance these; they do not build meshes.

const BLOB_SCENE := preload("res://scenes/fx/blob.tscn")
const RING_SCENE := preload("res://scenes/fx/ring.tscn")


static func blob(color: Color, mesh_scale: float = 1.0) -> Node3D:
	var root := BLOB_SCENE.instantiate() as Node3D
	if mesh_scale != 1.0:
		root.scale = Vector3.ONE * mesh_scale
	tint(root, color)
	return root


static func ring(color: Color) -> Node3D:
	var root := RING_SCENE.instantiate() as Node3D
	tint(root, color)
	return root


static func tint(root: Node, color: Color) -> void:
	if root == null:
		return
	var mesh := root.get_node_or_null("%Mesh") as MeshInstance3D
	if mesh != null:
		var base: Material = mesh.material_override
		if base == null:
			base = mesh.get_surface_override_material(0)
		if base == null:
			base = mesh.get_active_material(0)
		if base is StandardMaterial3D:
			var sm := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			sm.albedo_color = Color(color.r, color.g, color.b, 0.75)
			sm.emission_enabled = true
			sm.emission = color
			mesh.material_override = sm
	var light := root.get_node_or_null("%Light") as OmniLight3D
	if light != null:
		light.light_color = color
