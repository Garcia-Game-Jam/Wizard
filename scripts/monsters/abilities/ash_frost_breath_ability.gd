@tool
class_name AshFrostBreathAbility
extends "res://scripts/monsters/monster_ability.gd"

## Close-range frost projectile during chase retreat (ward combo). Not in cast rotation.

const AshFrostBreathCloudScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_cloud.gd"
)
const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")

const _TELEGRAPH_META := &"frost_breath_telegraph_fx"
const _CLOUD_PRE_FX_META := &"ash_cloud_pre_fx"

@export_range(0.0, 1.0, 0.05) var retreat_combo_chance: float = 0.85


func _ready() -> void:
	participates_in_cast_rotation = false
	requires_target = true
	requires_chase_target = true
	if ability_id.is_empty():
		ability_id = "ash_frost_breath"
	if display_name == "Ability":
		display_name = "Frost Breath"
	description = (
		"Combo step: frost cloud projectile toward the player. "
		+ "Knockback, slow, mana drain if spell armed. No HP damage."
	)
	telegraph_color = Color(0.55, 0.82, 1.0, 1.0)
	cooldown_sec = 10.0
	windup_sec = 0.25
	min_cast_range = 0.0
	max_cast_range = AshFrostBreathFlightScript.MAX_TRAVEL_RANGE


func can_cast() -> bool:
	return _cooldown_left <= 0.0 and is_inside_tree()


func is_ready_to_cast(monster: Monster, target: Node3D) -> bool:
	if not can_cast():
		return false
	return _is_in_range(monster, _resolve_target_pos(monster, target))


func is_target_in_range(monster: Monster, target: Node3D) -> bool:
	return _is_in_range(monster, _resolve_target_pos(monster, target))


func start_retreat_telegraph(monster: Monster) -> void:
	stop_retreat_telegraph(monster)
	if monster == null:
		return
	var fx_nodes: Array[Node] = []
	for hand in _resolve_both_hands(monster):
		var fx := _build_hand_telegraph_fx()
		hand.add_child(fx)
		fx_nodes.append(fx)
	if not fx_nodes.is_empty():
		monster.set_meta(_TELEGRAPH_META, fx_nodes)


func stop_retreat_telegraph(monster: Monster) -> void:
	if monster == null or not monster.has_meta(_TELEGRAPH_META):
		return
	var fx_nodes: Variant = monster.get_meta(_TELEGRAPH_META)
	if fx_nodes is Array:
		for fx in fx_nodes:
			if fx is Node and is_instance_valid(fx):
				(fx as Node).queue_free()
	monster.remove_meta(_TELEGRAPH_META)


func start_cloud_pre_fx(monster: Monster) -> void:
	stop_cloud_pre_fx(monster)
	if monster == null:
		return
	var fx := _build_cloud_pre_fx()
	monster.add_child(fx)
	var origin := _cast_origin_between_hands(monster)
	fx.global_position = origin + Vector3(0.0, 0.08, 0.0)
	monster.set_meta(_CLOUD_PRE_FX_META, fx)


func stop_cloud_pre_fx(monster: Monster) -> void:
	if monster == null or not monster.has_meta(_CLOUD_PRE_FX_META):
		return
	var fx: Variant = monster.get_meta(_CLOUD_PRE_FX_META)
	if fx is Node and is_instance_valid(fx):
		(fx as Node).queue_free()
	monster.remove_meta(_CLOUD_PRE_FX_META)


func _build_cloud_pre_fx() -> Node3D:
	var root := Node3D.new()
	root.name = "AshCloudPreFx"
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 14.0
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sphere)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 1.0, 1.0)
	light.light_energy = 12.0
	light.omni_range = 3.2
	light.shadow_enabled = false
	root.add_child(light)
	return root


func fire_instant(monster: Monster, target: Node3D) -> void:
	if monster == null or not can_cast():
		return
	var aim := _resolve_target_pos(monster, target)
	if not _is_in_range(monster, aim):
		return
	_spawn_cloud(monster, aim)
	begin_cooldown()


func fire_combo_step(monster: Monster, target: Node3D) -> void:
	reset_for_combo()
	stop_cloud_pre_fx(monster)
	if monster == null:
		return
	var aim := _resolve_target_pos(monster, target)
	_spawn_cloud(monster, aim)
	begin_cooldown()


func _resolve_target_pos(monster: Monster, target: Node3D) -> Vector3:
	var live := MonsterAI.live_node3d(target)
	if live:
		return live.global_position
	if monster == null:
		return Vector3.ZERO
	var aggro := monster.get_aggro_player_target()
	if aggro != null:
		return aggro.global_position
	var last: Variant = monster.get_last_aggro_player_aim()
	if last is Vector3:
		return last as Vector3
	return monster.global_position


func _is_in_range(monster: Monster, aim: Vector3) -> bool:
	if monster == null:
		return false
	var flat := Vector3(
		aim.x - monster.global_position.x,
		0.0,
		aim.z - monster.global_position.z
	)
	var dist := flat.length()
	return dist >= min_cast_range and dist <= max_cast_range


func _spawn_cloud(monster: Monster, aim: Vector3) -> void:
	var parent := _effect_parent(monster)
	var origin := _cast_origin_between_hands(monster)
	var launch_pos := AshFrostBreathFlightScript.launch_position(origin, aim)
	AshFrostBreathCloudScript.spawn(parent, launch_pos, aim, monster)


func _cast_origin_between_hands(monster: Monster) -> Vector3:
	var hands := _resolve_both_hands(monster)
	if hands.is_empty():
		return monster.global_position + Vector3(0.0, 0.55, 0.0)
	var sum := Vector3.ZERO
	for hand in hands:
		sum += hand.global_position
	return sum / float(hands.size())


func _resolve_both_hands(monster: Monster) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if monster == null:
		return out
	var path_groups := [
		["%RightHand", "Body/Hands/RightHand", "MidBody/Hands/RightHand"],
		["%LeftHand", "Body/Hands/LeftHand", "MidBody/Hands/LeftHand"],
	]
	for group in path_groups:
		for path in group:
			var hand := monster.get_node_or_null(path) as Node3D
			if hand != null:
				out.append(hand)
				break
	return out


func _build_hand_telegraph_fx() -> Node3D:
	var root := Node3D.new()
	root.name = "FrostBreathTelegraph"
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b, 0.75)
	mat.emission_enabled = true
	mat.emission = telegraph_color
	mat.emission_energy_multiplier = 4.0
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sphere)
	var light := OmniLight3D.new()
	light.light_color = telegraph_color
	light.light_energy = 3.0
	light.omni_range = 1.4
	light.shadow_enabled = false
	root.add_child(light)
	return root


func _effect_parent(monster: Monster) -> Node:
	if has_meta("lookdev_preview_parent"):
		var preview_parent = get_meta("lookdev_preview_parent")
		if preview_parent is Node and is_instance_valid(preview_parent):
			return preview_parent as Node
	var tree := monster.get_tree() if monster != null else get_tree()
	if tree != null:
		var match_root := GameWorldScript.find_match_root(tree)
		if match_root != null:
			return match_root
		if tree.current_scene != null:
			return tree.current_scene
	return monster.get_parent() if monster != null else self
