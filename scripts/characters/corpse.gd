class_name Corpse
extends RigidBody3D

## Local death VFX: greybox RigidBody limp, fades out, then frees.
## Each peer spawns its own copy; not replicated in multiplayer.

const DEFAULT_LINGER_SEC := 4.0
const DEFAULT_FADE_SEC := 2.0
const TORQUE_STRENGTH := 1.6
const WALK_NUDGE_MPS := 1.6
const GRAVITY := 18.0

const CorpseScript := preload("res://scripts/characters/corpse.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")

var _fade_sec: float = DEFAULT_FADE_SEC
var _materials: Array[StandardMaterial3D] = []
var _fade_tween: Tween
var _hit_dir: Vector3 = Vector3.FORWARD


func _notification(what: int) -> void:
	## A MeshInstance3D that holds the last reference to its material leaves the
	## renderer a dangling RID when it frees (engine #67144), which spams
	## "material_is_animated: Parameter material is null". Our fade duplicates the
	## authored materials, so every corpse mesh is such an owner: drop them first.
	if what == NOTIFICATION_PREDELETE:
		_release_materials()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	state.linear_velocity += Vector3.DOWN * GRAVITY * state.step


## Stage clear / explicit teardown.
func despawn() -> void:
	queue_free()


## opts: impulse (Vector3), carry (Vector3), linger_sec, fade_sec, reparent (bool).
static func spawn(
	source: Node3D,
	hit_dir: Vector3 = Vector3.FORWARD,
	opts: Dictionary = {}
) -> Corpse:
	if source == null or not source.is_inside_tree():
		return null
	var parent_node := _stage_corpses_root(source)
	if parent_node == null:
		return null
	var corpse_name := "%sCorpse" % source.name
	var existing := parent_node.get_node_or_null(corpse_name)
	if existing is Corpse:
		return existing as Corpse
	var corpse := RigidBody3D.new()
	corpse.name = corpse_name
	corpse.set_script(CorpseScript)
	parent_node.add_child(corpse)
	_apply_spawn_pose(corpse as Corpse, source)
	if bool(opts.get("reparent", false)):
		_reparent_greybox(source, corpse)
	else:
		_duplicate_greybox(source, corpse)
		(corpse as Corpse)._ensure_opaque_greybox()
	var flat_hit := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if flat_hit.length_squared() < 0.0001:
		flat_hit = Vector3.FORWARD
	else:
		flat_hit = flat_hit.normalized()
	var summon_style := opts.has("linger_sec")
	var layer := 0 if summon_style else 1
	var in_group := not summon_style
	var slump := Character.death_slump_velocity(flat_hit)
	var knock: Vector3 = opts.get("impulse", Vector3.ZERO)
	var carry: Vector3 = opts.get("carry", Vector3.ZERO)
	var body := corpse as Corpse
	body._hit_dir = flat_hit
	if knock.length_squared() > 0.0001:
		body._setup_rigidbody(slump, layer, in_group)
		body.apply_hit_knock(knock)
	else:
		body._setup_rigidbody(slump, layer, in_group)
		if carry.length_squared() > 0.0001:
			body.linear_velocity = carry
	body._schedule_fade(
		float(opts.get("linger_sec", DEFAULT_LINGER_SEC)),
		float(opts.get("fade_sec", DEFAULT_FADE_SEC))
	)
	return body


func _setup_rigidbody(impulse: Vector3, layer: int, in_corpse_group: bool) -> void:
	collision_layer = layer
	collision_mask = CollisionLayersScript.CHARACTER_AND_WORLD
	mass = 4.5
	linear_damp = 0.35
	angular_damp = 0.55
	continuous_cd = true
	custom_integrator = true
	if in_corpse_group:
		add_to_group(Character.CORPSE_GROUP)
	_collect_materials()
	if impulse.length_squared() > 0.0001:
		apply_central_impulse(impulse)
	apply_torque_impulse(Character.death_tumble_spin(TORQUE_STRENGTH))


func _schedule_fade(linger_sec: float, fade_sec: float) -> void:
	_fade_sec = maxf(0.05, fade_sec)
	var wait_sec := maxf(0.0, linger_sec - _fade_sec)
	var tree := get_tree()
	if tree == null:
		despawn()
		return
	tree.create_timer(wait_sec).timeout.connect(_start_fade)


## Killing knock: Character treats impulse as velocity. Replace the slump.
func apply_hit_knock(impulse: Vector3) -> void:
	linear_velocity = impulse
	apply_torque_impulse(Character.death_tumble_spin(TORQUE_STRENGTH))


func apply_walk_nudge(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	linear_velocity += flat.normalized() * WALK_NUDGE_MPS


## After a living slide. ponytail: O(slide collisions) per mover.
static func nudge_from_slide(walker: CharacterBody3D) -> void:
	if walker == null:
		return
	for i in walker.get_slide_collision_count():
		var col := walker.get_slide_collision(i)
		var hit := col.get_collider()
		if not (hit is Corpse):
			continue
		var n := col.get_normal()
		var push := Vector3(-n.x, 0.0, -n.z)
		if push.length_squared() < 0.0001:
			push = Vector3(walker.velocity.x, 0.0, walker.velocity.z)
		(hit as Corpse).apply_walk_nudge(push)


static func resolve_from(node: Node) -> Corpse:
	var n := node
	while n != null:
		if n is Corpse:
			return n as Corpse
		n = n.get_parent()
	return null


static func ram_if_new(corpse: Corpse, hits: Dictionary, vel: Vector3) -> void:
	if corpse == null:
		return
	var id := corpse.get_instance_id()
	if hits.has(id):
		return
	hits[id] = true
	corpse.apply_hit_knock(vel)


static func ram_nearby(from: Node3D, hit_range: float, hits: Dictionary, vel: Vector3) -> void:
	if from == null or not from.is_inside_tree() or hit_range <= 0.0:
		return
	var range_sq := hit_range * hit_range
	for node in from.get_tree().get_nodes_in_group(Character.CORPSE_GROUP):
		var corpse := resolve_from(node)
		if corpse == null:
			continue
		var dx := corpse.global_position.x - from.global_position.x
		var dz := corpse.global_position.z - from.global_position.z
		if dx * dx + dz * dz <= range_sq:
			ram_if_new(corpse, hits, vel)


static func _apply_spawn_pose(corpse: Corpse, source: Node3D) -> void:
	if source is Character:
		var body := source as Character
		corpse.global_position = body.global_position
		corpse.global_rotation = body.global_rotation
		return
	corpse.global_transform = source.global_transform


func _collect_materials() -> void:
	_materials.clear()
	var owned_for: Dictionary = {}
	for mesh in _find_mesh_instances(self):
		var mat := _mesh_material(mesh)
		if mat == null:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		despawn()
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
	_fade_tween.tween_callback(despawn)


static func _stage_corpses_root(from: Node) -> Node:
	var n := from
	while n != null:
		var c := n.get_node_or_null("Corpses")
		if c != null:
			return c
		n = n.get_parent()
	return from.get_parent() if from != null else null


static func _duplicate_greybox(source: Node3D, corpse: Node) -> void:
	_duplicate_node(source.get_node_or_null("%CollisionShape3D"), corpse)
	_duplicate_node(source.get_node_or_null("%Body"), corpse)
	_duplicate_node(source.get_node_or_null("%HeadMesh"), corpse)


## Corpse dup runs after ghost visuals; never copy the pawn's alpha fade.
func _ensure_opaque_greybox() -> void:
	for mesh in _find_mesh_instances(self):
		var mat := _mesh_material(mesh)
		if mat == null:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		var owned := mat.duplicate() as StandardMaterial3D
		owned.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		var color := owned.albedo_color
		color.a = 1.0
		owned.albedo_color = color
		mesh.material_override = owned


static func _reparent_greybox(source: Node3D, corpse: Node) -> void:
	for child in source.get_children():
		if child is CollisionShape3D:
			_reparent_node(child, corpse)
	_reparent_node(source.get_node_or_null("%Body"), corpse)
	var mid := source.get_node_or_null("%MidBody")
	if mid != null:
		_reparent_node(mid, corpse)
	_reparent_node(source.get_node_or_null("%Head"), corpse)


static func _duplicate_node(node: Node, corpse: Node) -> void:
	if node == null or corpse == null:
		return
	var copy := node.duplicate() as Node
	if copy == null:
		return
	corpse.add_child(copy)
	if node is Node3D and copy is Node3D:
		(copy as Node3D).global_transform = (node as Node3D).global_transform


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
