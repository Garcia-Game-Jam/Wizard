@tool
class_name ChargerWardAbility
extends "res://scripts/monsters/monster_ability.gd"

## Spawns a player-style ward and parents it to the Charger's ShieldHold.
## Dome tints a little red as HP drops, then bursts on shatter.

const WardShieldScript := preload("res://scripts/spells/ward_shield.gd")
const WardRuntimeScript := preload("res://scripts/spells/ward_runtime.gd")
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")
const FIREBALL_EQUIVALENT := 4

## Dome radius (m) of the ward held during telegraph and the ram.
@export_range(0.4, 1.4, 0.05) var shield_radius: float = 0.7
## Ward HP. Default 80 = four fireballs at 20 damage each. Dome tints red as it drops.
@export_range(20.0, 200.0, 1.0) var shield_hit_points: float = 80.0

var _ward_runtime: Resource = null


static func default_shield_hit_points() -> float:
	return FireballProjectileScript.DEFAULT_HIT_DAMAGE * float(FIREBALL_EQUIVALENT)


func _ready() -> void:
	hand_side = HandSide.RIGHT
	requires_target = true
	requires_chase_target = true
	if ability_id.is_empty():
		ability_id = "charger_ward"
	if display_name == "Ability":
		display_name = "Charge Ward"
	telegraph_color = Color(0.95, 0.2, 0.12, 1.0)
	cooldown_sec = 0.5
	windup_sec = 0.15
	min_cast_range = 0.0
	max_cast_range = 40.0


func spawn_held_ward(monster: Monster) -> Node:
	if monster == null:
		return null
	var holder := monster.get_node_or_null("ShieldHold") as Node3D
	var parent := holder if holder != null else _ward_parent(monster)
	var origin := monster.global_position + Vector3(0.0, 0.45, 0.0)
	if holder != null:
		origin = holder.global_position
	var dir := -monster.global_transform.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	var ward: Node = WardShieldScript.spawn(parent, origin, dir)
	if ward == null:
		return null
	_attach_to_holder(ward, holder, monster)
	_ignore_character_collisions(ward, monster)
	if "radius" in ward:
		ward.set("radius", shield_radius)
	if _ward_runtime == null:
		_ward_runtime = WardRuntimeScript.new()
	_ward_runtime.seed_from_max(
		shield_hit_points,
		WardShieldScript.DEFAULT_REGEN_DELAY_SEC,
		WardShieldScript.DEFAULT_REGEN_PER_SEC
	)
	if ward.has_method("bind_runtime"):
		ward.call("bind_runtime", _ward_runtime)
	elif ward.has_method("set_hit_points"):
		ward.call("set_hit_points", shield_hit_points)
	if ward.has_method("set_duration_sec"):
		ward.call("set_duration_sec", 30.0)
	if ward.has_method("hold_until_broken"):
		ward.call("hold_until_broken")
	return ward


func _fire_cast(monster: Monster, _target: Node3D) -> void:
	spawn_held_ward(monster)


func _ignore_character_collisions(ward: Node, monster: Monster) -> void:
	var body := ward.get_node_or_null("Body") as PhysicsBody3D
	if body == null:
		return
	if monster is CollisionObject3D:
		body.add_collision_exception_with(monster as CollisionObject3D)
	var tree := ward.get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("player"):
		if node is CollisionObject3D and node != monster:
			body.add_collision_exception_with(node as CollisionObject3D)


func _attach_to_holder(ward: Node, holder: Node3D, _monster: Monster) -> void:
	if holder == null:
		return
	if ward.get_parent() != holder:
		var xf := (ward as Node3D).global_transform if ward is Node3D else Transform3D()
		ward.get_parent().remove_child(ward)
		holder.add_child(ward)
		if ward is Node3D:
			(ward as Node3D).global_transform = xf
	if ward is Node3D:
		(ward as Node3D).position = Vector3.ZERO
		(ward as Node3D).rotation = Vector3.ZERO


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
