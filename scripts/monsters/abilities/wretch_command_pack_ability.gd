@tool
class_name WretchCommandPackAbility
extends "res://scripts/monsters/monster_ability.gd"

## Left-hand: ritualize, charge the pack orb 2x, linear launch at last-known aim.

const WretchCommandOrbProjectileScript := preload(
	"res://scripts/monsters/abilities/wretch_command_orb_projectile.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")

@export var launch_speed: float = 28.0
@export var orb_charge_mult: float = 2.0

var _pending_aim: Vector3 = Vector3.ZERO
var _has_pending_aim: bool = false


func _ready() -> void:
	hand_side = HandSide.LEFT
	## Player target preferred; sound aim uses pending aim / monster helper.
	requires_target = false
	requires_chase_target = false
	min_cast_range = 0.0
	max_cast_range = 0.0
	if ability_id.is_empty():
		ability_id = "command_pack"
	if display_name == "Ability":
		display_name = "Command Pack"
	telegraph_color = Color(0.45, 0.9, 0.35, 1.0)
	cooldown_sec = 8.0
	## Long enough for ritual straighten + orb charge before launch.
	windup_sec = 1.0


func can_cast() -> bool:
	return super.can_cast()


func is_ready_to_cast(monster: Monster, target: Node3D) -> bool:
	if not can_cast():
		return false
	if target != null and is_instance_valid(target) and target.is_in_group("player"):
		return true
	if _has_pending_aim:
		return true
	if monster != null and monster.has_method("get_hearing_command_aim"):
		var aim = monster.call("get_hearing_command_aim")
		return aim is Vector3
	return false


func set_pending_aim(world_position: Vector3) -> void:
	_pending_aim = world_position
	_has_pending_aim = true


func clear_pending_aim() -> void:
	_has_pending_aim = false


func start_windup_fx(monster: Monster) -> void:
	stop_windup_fx()
	var ritual := _resolve_ritual(monster)
	if ritual != null:
		if ritual.has_method("set_active"):
			ritual.call("set_active", true)
		if ritual.has_method("set_pack_orb_charge"):
			ritual.call("set_pack_orb_charge", orb_charge_mult)
		return
	## Fallback telegraph if ritual node is missing.
	var hand := resolve_hand(monster)
	if hand == null:
		return
	_windup_fx = _build_default_windup_fx()
	hand.add_child(_windup_fx)


func begin_cast(monster: Monster, target: Node3D) -> void:
	stop_windup_fx()
	begin_cooldown()
	_fire_cast(monster, target)
	clear_pending_aim()


func _fire_cast(monster: Monster, target: Node3D) -> void:
	if monster == null:
		return
	var host := _resolve_summon_host(monster)
	if host == null:
		return
	var ritual := _resolve_ritual(monster)
	var origin := resolve_cast_origin(monster)
	if ritual != null and ritual.has_method("get_pack_orb_global_position"):
		origin = ritual.call("get_pack_orb_global_position") as Vector3
	if ritual != null and ritual.has_method("hide_pack_orb_for_launch"):
		ritual.call("hide_pack_orb_for_launch")
	var parent := _projectile_parent(monster)
	var proj: Area3D = null
	if target != null and is_instance_valid(target) and target.is_in_group("player"):
		proj = WretchCommandOrbProjectileScript.spawn(
			parent,
			origin,
			target,
			monster,
			host,
			launch_speed,
			orb_charge_mult
		)
	else:
		var aim := _resolve_aim_point(monster, target)
		proj = WretchCommandOrbProjectileScript.spawn_toward_point(
			parent,
			origin,
			aim,
			monster,
			host,
			launch_speed,
			orb_charge_mult
		)
	if proj != null and ritual != null and ritual.has_method("restore_pack_orb_after_launch"):
		proj.tree_exiting.connect(
			func() -> void:
				if is_instance_valid(ritual) and ritual.has_method("restore_pack_orb_after_launch"):
					ritual.call("restore_pack_orb_after_launch")
		)


func _resolve_aim_point(monster: Monster, target: Node3D) -> Vector3:
	if _has_pending_aim:
		return _pending_aim
	if target != null and is_instance_valid(target):
		return target.global_position
	if monster != null and monster.has_method("get_hearing_command_aim"):
		var aim = monster.call("get_hearing_command_aim")
		if aim is Vector3:
			return aim as Vector3
	return monster.global_position + (-monster.global_transform.basis.z * 6.0)


func _resolve_ritual(monster: Monster) -> Node:
	if monster == null:
		return null
	return monster.get_node_or_null("Ritual")


func _resolve_summon_host(monster: Monster) -> Node:
	if monster == null:
		return null
	if monster.has_method("get_summon_host"):
		return monster.call("get_summon_host") as Node
	return monster.get_node_or_null("SummonHost")


func _projectile_parent(monster: Monster) -> Node:
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
