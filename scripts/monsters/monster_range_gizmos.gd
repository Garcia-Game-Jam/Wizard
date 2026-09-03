class_name MonsterRangeGizmos
extends RefCounted

## Editor combat-range disc helpers for Monster.


## Rebuild one flat translucent disc per spec ({name, radius, color}). Frees the
## previous batch first; returns the new mesh refs. Editor-only, so simple.
static func refresh_specs(
	host: Node3D, show: bool, specs: Array, cache: Array, disc_height: float
) -> Array:
	for mesh_inst in cache:
		free_gizmo(mesh_inst as MeshInstance3D)
	if not show:
		return []
	var out: Array = []
	for spec in specs:
		var radius := float(spec.get("radius", 0.0))
		if radius <= 0.05:
			continue
		var color: Color = spec.get("color", Color(1, 1, 1, 0.2))
		out.append(ensure_disc(
			host, null, str(spec.get("name", "RangeGizmo")), radius, color, disc_height
		))
	return out


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
