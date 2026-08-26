extends RefCounted

const ForceFieldScene := preload("res://scenes/fx/force_field.tscn")


func run() -> int:
	var failures := 0
	failures += _test_scene_has_shader_mesh()
	failures += _test_fit_wall_uses_quad()
	failures += _test_fit_sphere_uses_sphere()
	return failures


func _test_scene_has_shader_mesh() -> int:
	var field: Node = ForceFieldScene.instantiate()
	var mesh := field.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		push_error("ForceField scene must author a Mesh child")
		field.free()
		return 1
	if not (mesh.material_override is ShaderMaterial):
		push_error("ForceField mesh must use the force-field shader")
		field.free()
		return 1
	field.free()
	return 0


func _test_fit_wall_uses_quad() -> int:
	var field: ForceField = ForceFieldScene.instantiate() as ForceField
	field.fit_wall(
		Vector3(0.0, 12.0, -10.0),
		Vector3(20.0, 24.0, 0.9),
		Vector3(0.0, 0.0, 1.0)
	)
	var mesh := field.get_node("Mesh") as MeshInstance3D
	var quad := mesh.mesh as QuadMesh
	if quad == null:
		push_error("fit_wall should swap in a QuadMesh")
		field.free()
		return 1
	if absf(quad.size.x - 20.0) > 0.01 or absf(quad.size.y - 24.0) > 0.01:
		push_error("Expected a 20x24 pane, got %s" % quad.size)
		field.free()
		return 1
	if field.position.z <= -10.0:
		push_error("Pane should sit on the inward face of the wall box")
		field.free()
		return 1
	field.free()
	return 0


func _test_fit_sphere_uses_sphere() -> int:
	var field: ForceField = ForceFieldScene.instantiate() as ForceField
	field.fit_sphere(3.5)
	var mesh := field.get_node("Mesh") as MeshInstance3D
	var sphere := mesh.mesh as SphereMesh
	if sphere == null or absf(sphere.radius - 3.5) > 0.01:
		push_error("fit_sphere should set a SphereMesh radius")
		field.free()
		return 1
	field.free()
	return 0
