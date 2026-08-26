class_name MonsterRangeGizmos
extends RefCounted

## Editor combat-range disc helpers for Monster.


static func refresh(
	host: Node3D,
	show: bool,
	chase_mesh: MeshInstance3D,
	attack_mesh: MeshInstance3D,
	chase_range: float,
	attack_range: float,
	disc_height: float
) -> Dictionary:
	## Returns {chase, attack} mesh refs after refresh.
	if not show:
		free_gizmo(chase_mesh)
		free_gizmo(attack_mesh)
		return {"chase": null, "attack": null}
	return {
		"chase": ensure_disc(
			host, chase_mesh, "ChaseRangeGizmo", chase_range, Color(1.0, 0.35, 0.2, 0.22), disc_height
		),
		"attack": ensure_disc(
			host,
			attack_mesh,
			"AttackRangeGizmo",
			attack_range,
			Color(1.0, 0.85, 0.2, 0.28),
			disc_height
		),
	}


static func apply_unshaded(mesh_inst: MeshInstance3D, color: Color) -> void:
	if mesh_inst == null:
		return
	var mat := mesh_inst.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_inst.material_override = mat
	mat.albedo_color = color


static func ensure_disc(
	host: Node3D,
	existing: MeshInstance3D,
	node_name: String,
	radius: float,
	color: Color,
	disc_height: float,
	set_editor_owner: bool = true
) -> MeshInstance3D:
	var mesh_inst := existing
	if mesh_inst == null or not is_instance_valid(mesh_inst):
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = node_name
		host.add_child(mesh_inst)
		if set_editor_owner and Engine.is_editor_hint() and host.get_tree() != null:
			var edited := host.get_tree().edited_scene_root
			if edited != null:
				mesh_inst.owner = edited
	var cyl := mesh_inst.mesh as CylinderMesh
	if cyl == null:
		cyl = CylinderMesh.new()
		cyl.radial_segments = 48
		mesh_inst.mesh = cyl
	cyl.top_radius = maxf(0.05, radius)
	cyl.bottom_radius = cyl.top_radius
	cyl.height = disc_height
	apply_unshaded(mesh_inst, color)
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.position = Vector3(0.0, disc_height * 0.5, 0.0)
	apply_debug_aabb(mesh_inst)
	return mesh_inst


static func apply_debug_aabb(mesh_inst: MeshInstance3D) -> void:
	## Keep editor selection on the monster body, not the 20m+ disc/cone.
	if mesh_inst == null:
		return
	mesh_inst.custom_aabb = AABB(Vector3(-0.35, 0.0, -0.35), Vector3(0.7, 0.9, 0.7))
	mesh_inst.extra_cull_margin = 48.0


static func free_gizmo(mesh_inst: MeshInstance3D) -> void:
	if mesh_inst != null and is_instance_valid(mesh_inst):
		mesh_inst.queue_free()
