@tool
class_name AshRetreatDashAbility
extends "res://scripts/monsters/monster_ability.gd"

## Quick backdash away from the player, then a chase strafe. 5s cooldown.

const ARRIVE_EPS := 0.4
const MAX_DASH_SEC := 2.5
const BACKDASH_DISTANCE := 4.0
const COMBO_CLOSE_RANGE := 2.5
const COMBO_AWAY_DISTANCE := 4.0

@export_range(1.0, 5.0, 0.05) var speed_multiplier: float = 4.05

var _dashing := false
var _dash_dir := Vector3.ZERO
var _dash_goal := Vector3.ZERO
var _dash_time_left := 0.0
var _dash_look: Node3D = null
var _pending_strafe_side: float = 1.0
var _inbound_dash_dir := Vector3.ZERO


func _ready() -> void:
	participates_in_cast_rotation = false
	if ability_id.is_empty():
		ability_id = "ash_retreat_dash"
	if display_name == "Ability":
		display_name = "Ash Retreat Dash"
	description = (
		"Dash backward away from the player, then strafe. Used instead of a slow walk-back."
	)
	telegraph_color = Color(0.45, 0.75, 1.0, 1.0)
	cooldown_sec = 5.0
	windup_sec = 0.0
	requires_target = true
	requires_chase_target = true
	min_cast_range = 0.0
	max_cast_range = 40.0


func reset_for_combo() -> void:
	## Locomotion cooldown is independent of spell combo resets.
	pass


func is_dashing() -> bool:
	return _dashing


func fire_instant(monster: Monster, target: Node3D) -> void:
	if monster == null or target == null or not is_instance_valid(target):
		return
	try_backdash(monster, target)


func try_backdash(monster: Monster, target: Node3D, side_sign: float = 1.0) -> bool:
	if _dashing:
		return true
	if not can_cast():
		return false
	if monster == null or target == null or not is_instance_valid(target):
		return false
	_pending_strafe_side = 1.0 if side_sign >= 0.0 else -1.0
	start_backdash(monster, target)
	return _dashing


func start_backdash(monster: Monster, target: Node3D) -> void:
	var max_dist := _monster_float(monster, "chase_range", 11.0)
	max_dist = MonsterAIScript.max_aggro_move_distance(max_dist)
	var goal := MonsterAIScript.pick_dash_landing_away(
		monster.global_position, target, BACKDASH_DISTANCE, max_dist
	)
	_begin_dash(monster, goal, target)


func fire_combo_close_dash(monster: Monster, target: Node3D) -> void:
	if monster == null or target == null or not is_instance_valid(target):
		return
	var toward := Vector3(
		target.global_position.x - monster.global_position.x,
		0.0,
		target.global_position.z - monster.global_position.z
	)
	if toward.length_squared() > 0.0001:
		_inbound_dash_dir = toward.normalized()
	var max_dist := _monster_float(monster, "chase_range", 11.0)
	max_dist = MonsterAIScript.max_aggro_move_distance(max_dist)
	var goal := MonsterAIScript.pick_dash_landing_at_range(
		monster.global_position, target, COMBO_CLOSE_RANGE, max_dist
	)
	_begin_dash(monster, goal, target, false)


func fire_combo_away_dash(monster: Monster, target: Node3D) -> void:
	if monster == null or target == null or not is_instance_valid(target):
		return
	var inbound := _inbound_dash_dir
	if inbound.length_squared() < 0.0001:
		inbound = Vector3(
			target.global_position.x - monster.global_position.x,
			0.0,
			target.global_position.z - monster.global_position.z
		)
	var max_dist := _monster_float(monster, "chase_range", 11.0)
	max_dist = MonsterAIScript.max_aggro_move_distance(max_dist)
	var goal := MonsterAIScript.pick_dash_landing_sidestep(
		monster.global_position, target, inbound, COMBO_AWAY_DISTANCE, max_dist
	)
	_begin_dash(monster, goal, target, false)


func tick_dash(monster: CharacterBody3D, delta: float) -> bool:
	if not _dashing or monster == null:
		return false
	if _is_blocked_ahead(monster, delta):
		_end_dash(monster)
		return false
	_dash_time_left -= delta
	var speed := _monster_float(monster, "move_speed", 2.8) * speed_multiplier
	monster.velocity.x = _dash_dir.x * speed
	monster.velocity.z = _dash_dir.z * speed
	_face_during_dash(monster)
	var to_goal := _dash_goal - monster.global_position
	to_goal.y = 0.0
	if to_goal.length() <= ARRIVE_EPS or _dash_time_left <= 0.0:
		_end_dash(monster)
	return true


func _begin_dash(
	monster: Monster, goal: Vector3, look: Node3D, spend_cooldown: bool = true
) -> void:
	_dash_goal = goal
	var flat := _dash_goal - monster.global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	_dash_dir = flat.normalized()
	if spend_cooldown:
		_inbound_dash_dir = _dash_dir
	_dash_look = look
	_dashing = true
	_dash_time_left = MAX_DASH_SEC
	if spend_cooldown:
		begin_cooldown()


func _end_dash(monster: Monster) -> void:
	var look := _dash_look
	_dashing = false
	_dash_look = null
	if not is_instance_valid(look):
		look = null
	if monster != null:
		monster.velocity.x = 0.0
		monster.velocity.z = 0.0
	_start_follow_strafe(monster, look)


func _start_follow_strafe(monster: Monster, look: Node3D) -> void:
	if monster == null or not monster.has_method("start_chase_strafe"):
		return
	var caster := monster.get_node_or_null("CasterCombat")
	if (
		caster != null
		and caster.has_method("is_combo_active")
		and bool(caster.call("is_combo_active"))
	):
		return
	var target := _resolve_strafe_target(monster, look)
	if target == null:
		return
	var min_sec := _monster_float(monster, "chase_strafe_min_sec", 1.2)
	var max_sec := _monster_float(monster, "chase_strafe_max_sec", 2.0)
	var duration := randf_range(minf(min_sec, max_sec), maxf(min_sec, max_sec))
	monster.call("start_chase_strafe", target, _pending_strafe_side, duration)


func _resolve_strafe_target(monster: Monster, look: Node3D) -> Node3D:
	var aggro := monster.get_aggro_player_target()
	if aggro != null:
		return aggro
	return MonsterAIScript.live_node3d(look)


func _face_during_dash(monster: Monster) -> void:
	if not monster.has_method("_face_horizontal"):
		return
	if _dash_look != null and is_instance_valid(_dash_look):
		var toward := Vector3(
			_dash_look.global_position.x - monster.global_position.x,
			0.0,
			_dash_look.global_position.z - monster.global_position.z
		)
		if toward.length_squared() > 0.0001:
			monster.call("_face_horizontal", toward)
			return
	monster.call("_face_horizontal", _dash_dir)


func _is_blocked_ahead(monster: CharacterBody3D, delta: float) -> bool:
	var world := monster.get_world_3d()
	if world == null:
		return false
	var speed := _monster_float(monster, "move_speed", 2.8) * speed_multiplier
	var from := monster.global_position + Vector3(0.0, 0.35, 0.0)
	var to := from + _dash_dir * speed * delta * 1.25
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [monster.get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _monster_float(monster: Object, prop: String, fallback: float) -> float:
	if monster != null and prop in monster:
		var value: Variant = monster.get(prop)
		if value is float or value is int:
			return float(value)
	return fallback
