class_name MonsterCorpse
extends RigidBody3D

## Temporary ragdoll stand-in for Monster death (single rigid body + meshes).
## Lingers, fades, then frees — not a skeletal PhysicalBone ragdoll.

const DEFAULT_LINGER_SEC := 30.0
const DEFAULT_FADE_SEC := 3.0
const TORQUE_STRENGTH := 2.8
const DEFAULT_IMPULSE_SCALE := 1.35

const MonsterCorpseScript := preload("res://scripts/monsters/monster_corpse.gd")

var _fade_sec: float = DEFAULT_FADE_SEC
var _materials: Array[StandardMaterial3D] = []
var _fade_tween: Tween


func _notification(what: int) -> void:
	## A MeshInstance3D that holds the last reference to its material leaves the
	## renderer a dangling RID when it frees (engine #67144), which spams
	## "material_is_animated: Parameter material is null". Our fade duplicates the
	## authored materials, so every corpse mesh is such an owner: drop them first.
	if what == NOTIFICATION_PREDELETE:
		_release_materials()


func begin_death_sequence(
	impulse: Vector3,
	linger_sec: float = DEFAULT_LINGER_SEC,
	fade_sec: float = DEFAULT_FADE_SEC
) -> void:
	_fade_sec = maxf(0.05, fade_sec)
	collision_layer = 0
	collision_mask = 1
	mass = 4.5
	linear_damp = 0.35
	angular_damp = 0.55
	continuous_cd = true
	_collect_materials()
	apply_central_impulse(impulse)
	var torque := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-0.4, 0.4),
		randf_range(-1.0, 1.0)
	).normalized() * TORQUE_STRENGTH
	apply_torque_impulse(torque)

	var wait_sec := maxf(0.0, linger_sec - _fade_sec)
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	tree.create_timer(wait_sec).timeout.connect(_start_fade)


func _collect_materials() -> void:
	_materials.clear()
	var owned_for: Dictionary = {}
	for mesh in _find_mesh_instances(self):
		var mat := _mesh_material(mesh)
		if mat == null:
			continue
		var key := mat.get_instance_id()
		var owned: StandardMaterial3D = owned_for.get(key) as StandardMaterial3D
		if owned == null:
			owned = mat.duplicate() as StandardMaterial3D
			owned_for[key] = owned
			_materials.append(owned)
		if mesh.material_override != null:
			mesh.material_override = owned
		else:
			mesh.set_surface_override_material(0, owned)


func _mesh_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	if mesh.material_override is StandardMaterial3D:
		return mesh.material_override as StandardMaterial3D
	var override_mat := mesh.get_surface_override_material(0)
	if override_mat is StandardMaterial3D:
		return override_mat as StandardMaterial3D
	return null


func _find_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		found.append(root as MeshInstance3D)
	for child in root.get_children():
		found.append_array(_find_mesh_instances(child))
	return found


func _release_materials() -> void:
	for mesh in _find_mesh_instances(self):
		mesh.material_override = null
		for i in mesh.get_surface_override_material_count():
			mesh.set_surface_override_material(i, null)


func _start_fade() -> void:
	if not is_inside_tree():
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	## Drop any materials that were freed mid-linger (can happen if meshes go away).
	var live_mats: Array[StandardMaterial3D] = []
	for mat in _materials:
		if mat != null and is_instance_valid(mat):
			live_mats.append(mat)
	_materials = live_mats
	if _materials.is_empty():
		queue_free()
		return
	for mat in _materials:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mesh in _find_mesh_instances(self):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_IN)
	for mat in _materials:
		var clear := Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 0.0)
		_fade_tween.tween_property(mat, "albedo_color", clear, _fade_sec)
	_fade_tween.set_parallel(false)
	_fade_tween.tween_callback(queue_free)


static func spawn_from_monster(
	monster: Node,
	hit_dir: Vector3,
	linger_sec: float,
	fade_sec: float,
	impulse_scale: float = DEFAULT_IMPULSE_SCALE
) -> void:
	if monster == null or not monster.is_inside_tree():
		return
	var parent_node := monster.get_parent()
	if parent_node == null:
		return
	var corpse := RigidBody3D.new()
	corpse.name = "%sCorpse" % monster.name
	corpse.set_script(MonsterCorpseScript)
	parent_node.add_child(corpse)
	if monster is Node3D:
		corpse.global_transform = (monster as Node3D).global_transform
	for child in monster.get_children():
		if child is CollisionShape3D:
			_reparent_node(child, corpse)
	_reparent_node(monster.get_node_or_null("%Body"), corpse)
	_reparent_node(monster.get_node_or_null("%MidBody"), corpse)
	_reparent_node(monster.get_node_or_null("%Head"), corpse)
	var impulse: Vector3 = Character._knockback_impulse(hit_dir) * impulse_scale
	if corpse.has_method("begin_death_sequence"):
		corpse.call("begin_death_sequence", impulse, linger_sec, fade_sec)


static func _reparent_node(node: Node, corpse: Node) -> void:
	if node == null or corpse == null:
		return
	var xf: Transform3D
	var is_spatial := node is Node3D
	if is_spatial:
		xf = (node as Node3D).global_transform
	var old_parent := node.get_parent()
	if old_parent != null:
		old_parent.remove_child(node)
	corpse.add_child(node)
	if is_spatial:
		(node as Node3D).global_transform = xf
