@tool
class_name EmberLobAbility
extends "res://scripts/monsters/monster_ability.gd"

## Right-hand lob fireball: blob windup, then arc and dive at the player.

const EmberLobProjectileScript := preload(
	"res://scripts/monsters/abilities/ember_lob_projectile.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")


func _ready() -> void:
	hand_side = HandSide.RIGHT
	if ability_id.is_empty():
		ability_id = "ember_lob"
	if display_name == "Ability":
		display_name = "Ember Lob"
	telegraph_color = Color(1.0, 0.22, 0.06, 1.0)
	cooldown_sec = 5.0
	min_cast_range = 3.5
	max_cast_range = 13.0


func start_windup_fx(monster: Monster) -> void:
	stop_windup_fx()
	var hand := resolve_hand(monster)
	if hand == null:
		return
	_windup_fx = FxScenesScript.blob(telegraph_color, 1.25)
	_windup_fx.name = "EmberLobWindup"
	hand.add_child(_windup_fx)


func _fire_cast(monster: Monster, target: Node3D) -> void:
	if monster == null or target == null:
		return
	var parent := _projectile_parent(monster)
	var origin := resolve_cast_origin(monster)
	EmberLobProjectileScript.spawn(parent, origin, target, monster)


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
