@tool
class_name AshWardAbility
extends "res://scripts/monsters/monster_ability.gd"

## Left-hand ward: same shield as the player spell, lasting 2.5 seconds.

const WardShieldScript := preload("res://scripts/spells/ward_shield.gd")
const WardRuntimeScript := preload("res://scripts/spells/ward_runtime.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")

@export_range(0.5, 10.0, 0.1) var ward_duration_sec: float = 2.5

var _ward_runtime: Resource = null


func _ready() -> void:
	hand_side = HandSide.LEFT
	requires_target = true
	requires_chase_target = true
	if ability_id.is_empty():
		ability_id = "ash_ward"
	if display_name == "Ability":
		display_name = "Ash Ward"
	telegraph_color = Color(0.4, 0.7, 1.0, 1.0)
	cooldown_sec = 7.0
	min_cast_range = 0.0
	max_cast_range = 20.0


func start_windup_fx(monster: Monster) -> void:
	stop_windup_fx()
	var hand := resolve_hand(monster)
	if hand == null:
		return
	_windup_fx = Node3D.new()
	_windup_fx.name = "AshWardWindup"
	hand.add_child(_windup_fx)

	var glow := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	glow.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.7, 1.0, 0.75)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.8, 1.0)
	mat.emission_energy_multiplier = 3.8
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_windup_fx.add_child(glow)

	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.75, 1.0)
	light.light_energy = 2.6
	light.omni_range = 1.2
	light.shadow_enabled = false
	_windup_fx.add_child(light)


func _fire_cast(monster: Monster, target: Node3D) -> void:
	if monster == null:
		return
	var parent := _ward_parent(monster)
	var origin := resolve_cast_origin(monster)
	var dir := -monster.global_transform.basis.z
	if target != null and is_instance_valid(target):
		dir = Vector3(
			target.global_position.x - origin.x,
			0.0,
			target.global_position.z - origin.z
		)
		if dir.length_squared() < 0.0001:
			dir = -monster.global_transform.basis.z
		else:
			dir = dir.normalized()
	var ward: Node = WardShieldScript.spawn(parent, origin, dir, 1, ward_duration_sec)
	if ward != null and ward.has_method("set_caster"):
		ward.call("set_caster", monster)
	if _ward_runtime == null:
		_ward_runtime = WardRuntimeScript.new()
		_ward_runtime.seed_from_max(
			WardShieldScript.DEFAULT_BLOCK_HP,
			WardShieldScript.DEFAULT_REGEN_DELAY_SEC,
			WardShieldScript.DEFAULT_REGEN_PER_SEC
		)
	if ward != null and ward.has_method("bind_runtime"):
		ward.call("bind_runtime", _ward_runtime)


func fire_instant(monster: Monster, target: Node3D) -> void:
	if not can_cast() or monster == null:
		return
	_fire_cast(monster, target)
	begin_cooldown()


func fire_combo_step(monster: Monster, target: Node3D) -> void:
	reset_for_combo()
	stop_windup_fx()
	if monster == null:
		return
	_fire_cast(monster, target)
	begin_cooldown()


func _ward_parent(monster: Monster) -> Node:
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
