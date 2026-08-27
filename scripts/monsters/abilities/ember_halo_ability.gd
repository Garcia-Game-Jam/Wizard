@tool
class_name EmberHaloAbility
extends "res://scripts/monsters/monster_ability.gd"

## Left-hand expanding halo ring: red ring above hand during windup.

const EmberHaloProjectileScript := preload(
	"res://scripts/monsters/abilities/ember_halo_projectile.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")


func _ready() -> void:
	hand_side = HandSide.LEFT
	if ability_id.is_empty():
		ability_id = "ember_halo"
	if display_name == "Ability":
		display_name = "Ember Halo"
	telegraph_color = Color(1.0, 0.18, 0.08, 1.0)
	cooldown_sec = 7.5
	min_cast_range = 2.5
	max_cast_range = 11.0


func start_windup_fx(monster: Monster) -> void:
	stop_windup_fx()
	var hand := resolve_hand(monster)
	if hand == null:
		return
	_windup_fx = FxScenesScript.ring(telegraph_color)
	_windup_fx.name = "EmberHaloWindup"
	_windup_fx.position = Vector3(0.0, 0.18, 0.0)
	hand.add_child(_windup_fx)


func _fire_cast(monster: Monster, target: Node3D) -> void:
	if monster == null or target == null:
		return
	var parent := _projectile_parent(monster)
	var origin := resolve_cast_origin(monster)
	EmberHaloProjectileScript.spawn(parent, origin, target.global_position, monster)


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
