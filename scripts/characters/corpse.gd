class_name Corpse
extends RigidBody3D

## Stage death prop: greybox RigidBody limp (impulse + torque, no skeleton).
## All corpses spawn through Corpse.spawn(); stage clear calls despawn().
## Multiplayer: host tick sim + RollbackSynchronizer; guests display interpolated pose.

const DEFAULT_LINGER_SEC := 30.0
const DEFAULT_FADE_SEC := 3.0
const TORQUE_STRENGTH := 1.6
const WALK_NUDGE_MPS := 1.6
const GRAVITY := 18.0

const CorpseScript := preload("res://scripts/characters/corpse.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")
const NetAuthorityScript := preload("res://scripts/net/net_authority.gd")
const Profiles := preload("res://scripts/net/net_rewindable_profiles.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")

## Rewindable sim velocity — frozen RigidBody engine vel is not reliable in MP.
var net_linear_velocity: Vector3 = Vector3.ZERO
var net_angular_velocity: Vector3 = Vector3.ZERO

var _fade_sec: float = DEFAULT_FADE_SEC
var _materials: Array[StandardMaterial3D] = []
var _fade_tween: Tween
var _hit_dir: Vector3 = Vector3.FORWARD
var _net_enrolled := false


func _notification(what: int) -> void:
	## A MeshInstance3D that holds the last reference to its material leaves the
	## renderer a dangling RID when it frees (engine #67144), which spams
	## "material_is_animated: Parameter material is null". Our fade duplicates the
	## authored materials, so every corpse mesh is such an owner: drop them first.
	if what == NOTIFICATION_PREDELETE:
		_release_materials()


func net_state_paths() -> Array[String]:
	return Profiles.state_paths(Profiles.CORPSE)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if NetClockScript.is_session_multiplayer():
		return
	state.linear_velocity += Vector3.DOWN * GRAVITY * state.step


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	if not NetClockScript.is_session_multiplayer():
		return
	if not NetAuthorityScript.should_simulate(self):
		return
	_simulate_corpse(delta, true)


## Netfox liveness: hide on ticks before spawn_tick so death resims do not flash a corpse.
func _rollback_spawn() -> void:
	visible = true


func _rollback_despawn() -> void:
	visible = false


## Stage clear / explicit teardown. Later: play an outro, then free.
func despawn() -> void:
	queue_free()


static func request_multiplayer_spawn(
	source: Node3D,
	hit_dir: Vector3,
	opts: Dictionary
) -> void:
	if source == null or not source.is_inside_tree():
		return
	if not NetClockScript.is_session_multiplayer():
		return
	var mp := source.get_multiplayer()
	if mp == null or not mp.is_server():
		return
	var arena: Node = GameWorldScript.find_match_root(source.get_tree())
	if arena != null and arena.has_method("request_corpse_spawn"):
		arena.call("request_corpse_spawn", source, hit_dir, opts)


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
	var fading := opts.has("linger_sec")
	var layer := 0 if fading else 1
	var in_group := not fading
	var slump := Character.death_slump_velocity(flat_hit)
	var knock: Vector3 = opts.get("impulse", Vector3.ZERO)
	var carry: Vector3 = opts.get("carry", Vector3.ZERO)
	var body := corpse as Corpse
	body._hit_dir = flat_hit
	if fading and knock.length_squared() > 0.0001:
		body._setup_rigidbody(knock, layer, in_group)
	elif knock.length_squared() > 0.0001:
		body._setup_rigidbody(slump, layer, in_group)
		body._set_net_knock(knock)
	else:
		body._setup_rigidbody(slump, layer, in_group)
		if carry.length_squared() > 0.0001:
			if NetClockScript.is_session_multiplayer():
				body._set_net_carry(carry)
			else:
				corpse.linear_velocity = carry
	if fading:
		body._schedule_fade(
			float(opts.get("linger_sec", DEFAULT_LINGER_SEC)),
			float(opts.get("fade_sec", DEFAULT_FADE_SEC))
		)
	if NetClockScript.is_session_multiplayer():
		body._enroll_net()
	return body


func _setup_rigidbody(impulse: Vector3, layer: int, in_corpse_group: bool) -> void:
	collision_layer = layer
	collision_mask = 1
	mass = 4.5
	linear_damp = 0.35
	angular_damp = 0.55
	continuous_cd = true
	if in_corpse_group:
		add_to_group(Character.CORPSE_GROUP)
		_collect_materials()
	if NetClockScript.is_session_multiplayer():
		custom_integrator = false
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		if impulse.length_squared() > 0.0001:
			net_linear_velocity = impulse
		net_angular_velocity = _tumble_angular_velocity(_hit_dir, TORQUE_STRENGTH)
	else:
		custom_integrator = true
		if impulse.length_squared() > 0.0001:
			apply_central_impulse(impulse)
		apply_torque_impulse(Character.death_tumble_spin(TORQUE_STRENGTH))


func _enroll_net() -> void:
	if _net_enrolled or not NetClockScript.is_session_multiplayer():
		return
	_net_enrolled = true
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	custom_integrator = false
	NetLivenessScript.attach(self, Profiles.CORPSE)
	NetLivenessScript.commit_pose(self)


func _set_net_knock(impulse: Vector3) -> void:
	net_linear_velocity = impulse
	net_angular_velocity = _tumble_angular_velocity(_hit_dir, TORQUE_STRENGTH)


func _set_net_carry(carry: Vector3) -> void:
	net_linear_velocity = carry


func _simulate_corpse(delta: float, use_net_state: bool) -> void:
	if delta <= 0.0:
		return
	var vel := net_linear_velocity if use_net_state else linear_velocity
	var ang := net_angular_velocity if use_net_state else angular_velocity
	vel.y -= GRAVITY * delta
	vel *= maxf(0.0, 1.0 - linear_damp * delta)
	ang *= maxf(0.0, 1.0 - angular_damp * delta)
	var motion := vel * delta
	vel = _move_with_collision(motion, vel)
	if ang.length_squared() > 0.0001:
		rotation += ang * delta
	if use_net_state:
		net_linear_velocity = vel
		net_angular_velocity = ang
	else:
		linear_velocity = vel
		angular_velocity = ang
		_sync_physics_server()


func _move_with_collision(motion: Vector3, vel: Vector3) -> Vector3:
	if motion.length_squared() < 0.000001:
		return vel
	var params := PhysicsTestMotionParameters3D.new()
	params.from = global_transform
	params.motion = motion
	var result := PhysicsTestMotionResult3D.new()
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		global_position += result.get_travel()
		return vel.slide(result.get_collision_normal())
	global_position += motion
	return vel


func _sync_physics_server() -> void:
	if not is_inside_tree():
		return
	var rid := get_rid()
	if not rid.is_valid():
		return
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	if NetClockScript.is_session_multiplayer():
		PhysicsServer3D.body_set_state(
			rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, net_linear_velocity
		)
		PhysicsServer3D.body_set_state(
			rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, net_angular_velocity
		)
	else:
		PhysicsServer3D.body_set_state(
			rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, linear_velocity
		)
		PhysicsServer3D.body_set_state(
			rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, angular_velocity
		)


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
	if not NetAuthorityScript.should_simulate(self):
		return
	if NetClockScript.is_session_multiplayer():
		_set_net_knock(impulse)
	else:
		linear_velocity = impulse
		apply_torque_impulse(Character.death_tumble_spin(TORQUE_STRENGTH))


func apply_walk_nudge(dir: Vector3) -> void:
	if not NetAuthorityScript.should_simulate(self):
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	if NetClockScript.is_session_multiplayer():
		net_linear_velocity += flat.normalized() * WALK_NUDGE_MPS
	else:
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
	if NetClockScript.is_session_multiplayer() and not NetAuthorityScript.should_simulate(corpse):
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


static func _tumble_angular_velocity(hit_dir: Vector3, strength: float) -> Vector3:
	var spin_axis := Vector3(hit_dir.z, 0.35, -hit_dir.x)
	if spin_axis.length_squared() < 0.0001:
		spin_axis = Vector3(1.0, 0.35, 0.0)
	return spin_axis.normalized() * strength


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


## Corpse dup runs after ghost visuals on guests; never copy the pawn's alpha fade.
func _ensure_opaque_greybox() -> void:
	for mesh in _find_mesh_instances(self):
		var mat := _mesh_material(mesh)
		if mat == null:
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
