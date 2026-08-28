class_name PlayerGhost
extends RefCounted

## Dead player: same pawn flies, duplicated meshes are the shoveable corpse.
## Camera stays on Head. Not a combat body (layer 0, splash/AI skip is_node_alive).

const GHOST_MESH_ALPHA := 0.18

const NetClockScript := preload("res://scripts/net/net_clock.gd")
const NetAuthorityScript := preload("res://scripts/net/net_authority.gd")
const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")


static func enter(player: Player) -> void:
	if player == null or player.is_alive():
		return
	if player.collision_layer != 0:
		player.saved_collision_layer = player.collision_layer
	player.collision_layer = 0
	player.velocity = Vector3.ZERO
	if not is_instance_valid(player.death_corpse) and not player._pad_rez_pending:
		player.death_corpse = MonsterCorpse.spawn_player_prop(
			player, player._last_hit_dir
		)
	_apply_visuals(player, true)


static func exit(player: Player) -> void:
	if player == null:
		return
	if is_instance_valid(player.death_corpse):
		player.death_corpse.queue_free()
	player.death_corpse = null
	var layer := player.saved_collision_layer
	player.collision_layer = 1 if layer == 0 else layer
	_apply_visuals(player, false)


static func tick(player: Player, delta: float, net_input: Object) -> void:
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
		player.velocity = player.velocity.move_toward(
			Vector3.ZERO, player.move_friction * delta
		)
	NetClockScript.move_character(player)


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
	if not ghost:
		player.call("_apply_character_color", GameState.get_player_color(player.player_index))


static func _set_alpha(player: Player, mesh: MeshInstance3D, alpha: float) -> void:
	if mesh == null:
		return
	var mat: StandardMaterial3D = null
	if player.has_method("_authored_material"):
		mat = player.call("_authored_material", mesh) as StandardMaterial3D
	if mat == null:
		return
	var color := mat.albedo_color
	if alpha < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		color.a = alpha
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		color.a = 1.0
	mat.albedo_color = color
