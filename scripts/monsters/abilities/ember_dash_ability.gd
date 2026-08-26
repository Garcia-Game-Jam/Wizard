@tool
class_name EmberDashAbility
extends "res://scripts/monsters/monster_ability.gd"

## Chase sidestep + combo dash behind the player with a burning ground trail.

const EmberDashTrailSegmentScript := preload(
	"res://scripts/monsters/abilities/ember_dash_trail_segment.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")

const ARRIVE_EPS := 0.4
const MAX_DASH_SEC := 2.5
const MONSTER_BODY_RADIUS := 0.2
const SIDESTEP_TRIGGER_RANGE := 8.0
const SIDESTEP_DISTANCE_MULT := 0.5

@export_range(1.0, 5.0, 0.05) var speed_multiplier: float = 4.05
@export_range(0.0, 1.0, 0.05) var post_cast_dash_chance: float = 0.75
@export_range(0.0, 1.0, 0.05) var reposition_dash_chance: float = 0.3
@export_range(0.2, 1.0, 0.05) var landing_distance_mult: float = 0.7
@export_range(0.05, 0.95, 0.01) var low_health_reset_ratio: float = 0.35
@export_range(1.0, 2.0, 0.05) var trail_width_mult: float = 1.35
@export_range(0.1, 1.5, 0.05) var trail_segment_spacing: float = 0.35
@export_range(0.5, 12.0, 0.25) var trail_lifetime_sec: float = 4.0
@export_range(0.0, 30.0, 0.5) var burn_dps: float = 6.0
@export_range(0.05, 1.0, 0.05) var burn_slow_multiplier: float = 0.75
@export_range(0.1, 2.0, 0.05) var burn_refresh_sec: float = 0.5

var _dashing := false
var _sidestep := false
var _dash_dir := Vector3.ZERO
var _dash_goal := Vector3.ZERO
var _dash_time_left := 0.0
var _trail_dist_accum := 0.0
var _dash_look: Node3D = null
var _last_sidestep_sign: float = 1.0


func _ready() -> void:
	participates_in_cast_rotation = false
	if ability_id.is_empty():
		ability_id = "ember_dash"
	if display_name == "Ability":
		display_name = "Ember Dash"
	description = (
		"Sidestep opposite the player's movement at close range, or dash behind "
		+ "them during combo, leaving a burning trail."
	)
	telegraph_color = Color(1.0, 0.15, 0.05, 1.0)
	cooldown_sec = 5.0
	windup_sec = 0.0
	requires_target = true
	requires_chase_target = true
	min_cast_range = 0.0
	max_cast_range = 40.0


func try_sidestep(monster: Monster, target: Node3D) -> bool:
	if _dashing:
		return true
	if not can_sidestep(monster, target):
		return false
	start_sidestep(monster, target)
	return _dashing


func can_sidestep(monster: Monster, target: Node3D) -> bool:
	if not can_cast():
		return false
	if monster == null or target == null or not is_instance_valid(target):
		return false
	if not monster.has_method("is_ai_chasing") or not monster.is_ai_chasing():
		return false
	var dist := MonsterAIScript.horizontal_distance(
		monster.global_position, target.global_position
	)
	if dist > SIDESTEP_TRIGGER_RANGE:
		return false
	var landing := _compute_sidestep_landing(monster, target)
	var flat := landing - monster.global_position
	flat.y = 0.0
	return flat.length_squared() > 0.25


func can_dash(monster: Monster, target: Node3D) -> bool:
	if not can_cast():
		return false
	if monster == null or target == null or not is_instance_valid(target):
		return false
	if not monster.has_method("is_ai_chasing") or not monster.is_ai_chasing():
		return false
	var landing := _compute_landing(monster, target)
	var flat := landing - monster.global_position
	flat.y = 0.0
	return flat.length_squared() > 0.25


func is_dashing() -> bool:
	return _dashing


func fire_instant(monster: Monster, target: Node3D) -> void:
	if monster == null or target == null or not is_instance_valid(target):
		return
	if not can_cast():
		return
	if has_meta("lookdev_preview_parent"):
		start_dash(monster, target)
		return
	if not can_dash(monster, target):
		return
	start_dash(monster, target)


func fire_combo_step(monster: Monster, target: Node3D) -> void:
	reset_for_combo()
	if monster == null or target == null or not is_instance_valid(target):
		return
	start_dash(monster, target)


func start_dash(monster: Monster, target: Node3D) -> void:
	_begin_dash(monster, _compute_landing(monster, target), false, null)


func start_sidestep(monster: Monster, target: Node3D) -> void:
	var goal := _compute_sidestep_landing(monster, target)
	_begin_dash(monster, goal, true, target)
	if _dashing:
		_last_sidestep_sign *= -1.0


func _begin_dash(
	monster: Monster, goal: Vector3, sidestep: bool, look: Node3D
) -> void:
	_dash_goal = goal
	var flat := _dash_goal - monster.global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	_dash_dir = flat.normalized()
	_sidestep = sidestep
	_dash_look = look
	_dashing = true
	_dash_time_left = MAX_DASH_SEC
	_trail_dist_accum = 0.0
	begin_cooldown()


func tick_dash(monster: CharacterBody3D, delta: float) -> bool:
	if not _dashing or monster == null:
		return false
	if _is_blocked_ahead(monster, delta):
		_end_dash(monster)
		return false
	_dash_time_left -= delta
	var speed := _monster_float(monster, "move_speed", 3.2) * speed_multiplier
	monster.velocity.x = _dash_dir.x * speed
	monster.velocity.z = _dash_dir.z * speed
	_face_during_dash(monster)
	_spawn_trail_along_path(monster, delta, speed)
	var to_goal := _dash_goal - monster.global_position
	to_goal.y = 0.0
	if to_goal.length() <= ARRIVE_EPS or _dash_time_left <= 0.0:
		_end_dash(monster)
	return true


func _end_dash(monster: Monster) -> void:
	_dashing = false
	_sidestep = false
	_dash_look = null
	if monster != null:
		monster.velocity.x = 0.0
		monster.velocity.z = 0.0


func _face_during_dash(monster: Monster) -> void:
	if not monster.has_method("_face_horizontal"):
		return
	if _sidestep and _dash_look != null and is_instance_valid(_dash_look):
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
	var speed := _monster_float(monster, "move_speed", 3.2) * speed_multiplier
	var from := monster.global_position + Vector3(0.0, 0.35, 0.0)
	var to := from + _dash_dir * speed * delta * 1.25
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [monster.get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _spawn_trail_along_path(monster: Monster, delta: float, speed: float) -> void:
	var step := speed * delta
	_trail_dist_accum += step
	if _trail_dist_accum < trail_segment_spacing:
		return
	_trail_dist_accum = 0.0
	var parent := _trail_parent(monster)
	var width := MONSTER_BODY_RADIUS * 2.0 * trail_width_mult
	EmberDashTrailSegmentScript.spawn(
		parent,
		monster.global_position,
		_dash_dir,
		width,
		trail_segment_spacing,
		trail_lifetime_sec,
		burn_dps,
		burn_slow_multiplier,
		burn_refresh_sec,
		monster
	)


func _compute_landing(monster: Monster, target: Node3D) -> Vector3:
	var max_cast := _max_combat_range(monster) * landing_distance_mult
	var chase_range := _monster_float(monster, "chase_range", 12.0)
	var max_dist := MonsterAIScript.max_aggro_move_distance(chase_range)
	return MonsterAIScript.pick_dash_landing_behind(
		monster.global_position, target, max_cast, max_dist
	)


func _compute_sidestep_landing(monster: Monster, target: Node3D) -> Vector3:
	var distance := _max_combat_range(monster) * landing_distance_mult * SIDESTEP_DISTANCE_MULT
	return pick_sidestep_landing(
		monster.global_position, target, distance, _last_sidestep_sign
	)


static func pick_sidestep_landing(
	monster_pos: Vector3,
	player: Node3D,
	distance: float,
	fallback_sign: float = 1.0
) -> Vector3:
	if player == null:
		return monster_pos
	var toward := Vector3(
		player.global_position.x - monster_pos.x,
		0.0,
		player.global_position.z - monster_pos.z
	)
	var radial := Vector3.FORWARD
	if toward.length_squared() > 0.0001:
		radial = toward.normalized()
	var right := Vector3(-radial.z, 0.0, radial.x)
	var player_vel := Vector3.ZERO
	if "velocity" in player:
		var vel: Variant = player.get("velocity")
		if vel is Vector3:
			player_vel = Vector3((vel as Vector3).x, 0.0, (vel as Vector3).z)
	var lateral_dot := right.dot(player_vel)
	var side := fallback_sign
	if absf(lateral_dot) > 0.01:
		side = -1.0 if lateral_dot > 0.0 else 1.0
	elif absf(fallback_sign) < 0.01:
		side = 1.0
	var landing := monster_pos + right * side * maxf(distance, 0.0)
	landing.y = monster_pos.y
	return landing


func _monster_float(monster: Object, prop: String, fallback: float) -> float:
	if monster != null and prop in monster:
		var value: Variant = monster.get(prop)
		if value is float or value is int:
			return float(value)
	return fallback


func _max_combat_range(monster: Monster) -> float:
	var best := 13.0
	var root := monster.get_node_or_null("Abilities")
	if root == null:
		return best
	for child in root.get_children():
		if child == self:
			continue
		if "max_cast_range" in child and bool(child.get("participates_in_cast_rotation")):
			best = maxf(best, float(child.get("max_cast_range")))
	return best


func _trail_parent(monster: Monster) -> Node:
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
