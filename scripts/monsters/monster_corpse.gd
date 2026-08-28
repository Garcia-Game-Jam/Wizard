class_name MonsterCorpse
extends RigidBody3D

## Player death clone: duplicated capsule + meshes. Engine rigid limp (impulse + torque).
## Summon linger/fade still uses begin_death_sequence (not live-roster dumps).

const DEFAULT_LINGER_SEC := 30.0
const DEFAULT_FADE_SEC := 3.0
const DEFAULT_IMPULSE_SCALE := 1.35
const TORQUE_STRENGTH := 1.6

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
	_arm_ragdoll(impulse, 0, false)
	_fade_sec = maxf(0.05, fade_sec)
	var wait_sec := maxf(0.0, linger_sec - _fade_sec)
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	tree.create_timer(wait_sec).timeout.connect(_start_fade)


func begin_player_limp(hit_dir: Vector3) -> void:
	_arm_ragdoll(Character.death_slump_velocity(hit_dir), 1, true)


func _arm_ragdoll(impulse: Vector3, layer: int, in_corpse_group: bool) -> void:
	collision_layer = layer
	collision_mask = 1
	mass = 4.5
	linear_damp = 0.35
	angular_damp = 0.55
	continuous_cd = true
	if in_corpse_group:
		add_to_group(Character.CORPSE_GROUP)
	_collect_materials()
	apply_central_impulse(impulse)
	apply_torque_impulse(Character.death_tumble_spin(TORQUE_STRENGTH))


## Killing knock: Character treats impulse as velocity. Replace the slump.
func apply_hit_knock(impulse: Vector3) -> void:
	linear_velocity = impulse
	apply_torque_impulse(Character.death_tumble_spin(TORQUE_STRENGTH))


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


## Duplicate meshes + capsule. Do not reparent Head — the camera lives there.
static func spawn_player_prop(player: Node3D, hit_dir: Vector3) -> MonsterCorpse:
	return spawn_prop(player, hit_dir, false)


## Dump death: same rigid flop as the player corpse. Living node stays for rewind.
static func spawn_dump_prop(monster: Node3D, hit_dir: Vector3) -> MonsterCorpse:
	return spawn_prop(monster, hit_dir, true)


static func spawn_prop(source: Node3D, hit_dir: Vector3, include_head: bool) -> MonsterCorpse:
	if source == null or not source.is_inside_tree():
		return null
	var parent_node := source.get_parent()
	if parent_node == null:
		return null
	var corpse := RigidBody3D.new()
	corpse.name = "%sCorpse" % source.name
	corpse.set_script(MonsterCorpseScript)
	parent_node.add_child(corpse)
	corpse.global_transform = source.global_transform
	_duplicate_node(source.get_node_or_null("%CollisionShape3D"), corpse)
	_duplicate_node(source.get_node_or_null("%Body"), corpse)
	if include_head:
		_duplicate_node(source.get_node_or_null("%Head"), corpse)
	else:
		_duplicate_node(source.get_node_or_null("%HeadMesh"), corpse)
	if corpse.has_method("begin_player_limp"):
		corpse.call("begin_player_limp", hit_dir)
	return corpse as MonsterCorpse


static func _duplicate_node(node: Node, corpse: Node) -> void:
	if node == null or corpse == null:
		return
	var copy := node.duplicate() as Node
	if copy == null:
		return
	corpse.add_child(copy)
	if node is Node3D and copy is Node3D:
		(copy as Node3D).global_transform = (node as Node3D).global_transform


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
