class_name PlayerGhost
extends RefCounted

## Dead player: same pawn flies; corpse RigidBody is presentation (Death.commit).

const GHOST_MESH_ALPHA := 0.18
const GHOST_MAT_META := &"ghost_material"

const NetClockScript := preload("res://scripts/net/net_clock.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")
const NetAuthorityScript := preload("res://scripts/net/net_authority.gd")
const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")


## Ghost phases through characters; pit geometry stays on the world layer.
static func begin_mechanics(player: Player) -> void:
	if player == null or player.is_alive():
		return
	if (
		player.collision_layer == 0
		and player.collision_mask == CollisionLayersScript.GHOST_MASK
	):
		return
	player.saved_collision_layer = player.collision_layer
	player.saved_collision_mask = player.collision_mask
	player.collision_layer = 0
	player.collision_mask = CollisionLayersScript.GHOST_MASK


## Corpse + ghost meshes. Called from Death after the tick loop (or immediately offline).
static func commit(player: Player, pending_knock: Vector3 = Vector3.ZERO) -> void:
	if player == null or player.is_alive():
		return
	begin_mechanics(player)
	var opts := {}
	if pending_knock.length_squared() > 0.0001:
		opts["impulse"] = pending_knock
	elif not player._pad_rez_pending:
		opts["carry"] = player.velocity
	player.velocity = Vector3.ZERO
	if NetClockScript.is_session_multiplayer():
		NetLivenessScript.commit_pose(player)
	if not player._pad_rez_pending and not is_instance_valid(player.death_corpse):
		player.death_corpse = Corpse.spawn(player, player._last_hit_dir, opts)
	## Corpse dup reads player meshes; isolate ghost mats after the prop exists.
	_apply_visuals(player, true)


static func end_mechanics(player: Player) -> void:
	if player == null:
		return
	var layer := player.saved_collision_layer
	player.collision_layer = CollisionLayersScript.CHARACTER if layer == 0 else layer
	var mask := player.saved_collision_mask
	if mask == 0 or mask == CollisionLayersScript.GHOST_MASK:
		mask = CollisionLayersScript.CHARACTER_AND_WORLD
	player.collision_mask = mask


## Living look + collision. Stage owns freeing the shoveable corpse prop.
static func end_ghost(player: Player) -> void:
	if player == null:
		return
	_apply_visuals(player, false)
	end_mechanics(player)


static func clear(player: Player) -> void:
	end_ghost(player)


## Offline / test helper: mechanics + presentation in one step.
static func enter(player: Player) -> void:
	commit(player)


static func exit(player: Player) -> void:
	end_ghost(player)


static func tick(player: Player, _delta: float, net_input: Object) -> void:
	_ensure_ghost_collision(player)
	if net_input != null and player.has_method("_apply_net_look"):
		player.call("_apply_net_look", net_input)
	if player.has_method("_sync_body_yaw_to_head"):
		player.call("_sync_body_yaw_to_head")
	if GameState.is_multiplayer and not NetAuthorityScript.should_predict_or_simulate(player):
		return
	SlideSurfaceScript.prepare(player)
	player.floor_snap_length = 0.0
	var wish := _wish_dir(player, net_input)
	if wish.length_squared() > 0.0001:
		player.velocity = wish * player.move_speed
	else:
		## Killing knock is on the corpse prop; do not bleed restored rollback vel.
		player.velocity = Vector3.ZERO
	NetClockScript.move_character(player)


static func _ensure_ghost_collision(player: Player) -> void:
	if player == null or player.is_alive():
		return
	if (
		player.collision_layer != 0
		or player.collision_mask != CollisionLayersScript.GHOST_MASK
	):
		begin_mechanics(player)


static func _wish_dir(player: Player, net_input: Object) -> Vector3:
	var basis_node: Node3D = player.head
	var wish := Vector3.ZERO
	if basis_node != null:
		wish = SlideSurfaceScript.camera_relative_move_direction(basis_node, net_input)
	var jump_on := false
	var crouch_on := false
	if net_input != null:
		if "jump" in net_input:
			jump_on = bool(net_input.get("jump"))
		if "crouch" in net_input:
			crouch_on = bool(net_input.get("crouch"))
	else:
		jump_on = Input.is_action_pressed("jump")
		crouch_on = Input.is_action_pressed("crouch")
	if jump_on:
		wish.y += 1.0
	if crouch_on:
		wish.y -= 1.0
	if wish.length_squared() < 0.0001:
		return Vector3.ZERO
	return wish.normalized()


static func _apply_visuals(player: Player, ghost: bool) -> void:
	var body := player.get_node_or_null("%Body") as MeshInstance3D
	var head_mesh := player.get_node_or_null("%HeadMesh") as MeshInstance3D
	var wand := player.get_node_or_null("Head/CameraPivot/Wand") as Node3D
	if ghost and player.is_local_owner():
		if body != null:
			body.visible = false
		if head_mesh != null:
			head_mesh.visible = false
	else:
		if body != null:
			body.visible = true
		if head_mesh != null:
			head_mesh.visible = true
		_set_alpha(player, body, GHOST_MESH_ALPHA if ghost else 1.0)
		_set_alpha(player, head_mesh, GHOST_MESH_ALPHA if ghost else 1.0)
	if wand != null:
		wand.visible = not ghost
	if ghost:
		return
	_clear_ghost_materials(player)
	player.call("_apply_character_color", GameState.get_player_color(player.player_index))


static func _set_alpha(player: Player, mesh: MeshInstance3D, alpha: float) -> void:
	if mesh == null:
		return
	if alpha >= 0.99:
		_clear_ghost_material(mesh)
		var living: StandardMaterial3D = null
		if player.has_method("_authored_material"):
			living = player.call("_authored_material", mesh) as StandardMaterial3D
		if living != null:
			living.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			var opaque := living.albedo_color
			opaque.a = 1.0
			living.albedo_color = opaque
		return
	var mat := _ghost_material_for(player, mesh)
	if mat == null:
		return
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var color := mat.albedo_color
	color.a = alpha
	mat.albedo_color = color


static func _ghost_material_for(player: Player, mesh: MeshInstance3D) -> StandardMaterial3D:
	if mesh.has_meta(GHOST_MAT_META):
		return mesh.get_meta(GHOST_MAT_META) as StandardMaterial3D
	var src: StandardMaterial3D = null
	if player.has_method("_authored_material"):
		src = player.call("_authored_material", mesh) as StandardMaterial3D
	if src == null:
		return null
	var owned := src.duplicate() as StandardMaterial3D
	mesh.material_override = owned
	mesh.set_meta(GHOST_MAT_META, owned)
	return owned


static func _clear_ghost_material(mesh: MeshInstance3D) -> void:
	if mesh == null or not mesh.has_meta(GHOST_MAT_META):
		return
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = null
	mesh.remove_meta(GHOST_MAT_META)


static func _clear_ghost_materials(player: Player) -> void:
	_clear_ghost_material(player.get_node_or_null("%Body") as MeshInstance3D)
	_clear_ghost_material(player.get_node_or_null("%HeadMesh") as MeshInstance3D)
