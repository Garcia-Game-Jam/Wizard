@tool
class_name MonsterSightSense
extends MonsterSense

## Proximity + optional LOS / vision-cone player detection under Monster/Senses.

const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")
## Default player capsule width used when sizing a narrow vision cone.
const DEFAULT_PLAYER_WIDTH_M := 0.55

## Max distance (m) a player can be seen. Walls block this; hearing does not.
@export var sight_range: float = 10.0
## If on, a ray from eye_height must be clear. LOS gizmo is red when blocked.
@export var require_line_of_sight: bool = true
## Ray origin height (m) above the monster origin. Green sphere on the gizmo.
@export var eye_height: float = 0.55
## How strongly this sense pulls AI vs hearing. Higher wins interest ties.
@export var sight_urgency: float = 1.4
## If on, only players inside the forward wedge are seen (not a full disc).
@export var use_vision_cone: bool = false
## Full horizontal FOV of the vision cone, in degrees. When > 0 this wins over
## Cone Width At Max Range. ~110-160 reads as a convincing "looking that way".
@export_range(0.0, 340.0, 1.0, "suffix:°") var cone_angle_deg: float = 0.0
## Legacy wedge width (m) at sight_range. Used only when Cone Angle Deg is 0
## (Wretch keeps this at a player-thin 0.55 m).
@export_range(0.05, 40.0, 0.01) var cone_width_at_max_range: float = DEFAULT_PLAYER_WIDTH_M
## If on, this sense is ignored until the monster is already ALERT or CHASE.
@export var only_when_alert_or_chase: bool = false


func append_interest_candidates(monster: CharacterBody3D, out: Array) -> void:
	if not enabled or monster == null:
		return
	if only_when_alert_or_chase and not _monster_is_alert_or_chasing(monster):
		return
	var tree := monster.get_tree()
	if tree == null:
		return
	var origin := monster.global_position
	for node in tree.get_nodes_in_group("player"):
		if not (node is Node3D):
			continue
		var player := node as Node3D
		if not Character.is_node_alive(player):
			continue
		var flat := Vector3(
			player.global_position.x - origin.x,
			0.0,
			player.global_position.z - origin.z
		)
		var dist := flat.length()
		if dist > sight_range:
			continue
		if use_vision_cone and not _in_vision_cone(monster, flat):
			continue
		if require_line_of_sight and not _has_line_of_sight(monster, player):
			continue
		var urgency := sight_urgency * (1.0 - (dist / maxf(sight_range, 0.01)) * 0.35)
		out.append(MonsterInterestScript.from_target(player, urgency, &"sight"))


func _monster_is_alert_or_chasing(monster: CharacterBody3D) -> bool:
	var chasing := (
		monster.has_method("is_ai_chasing") and bool(monster.call("is_ai_chasing"))
	)
	var alert := monster.has_method("is_ai_alert") and bool(monster.call("is_ai_alert"))
	return chasing or alert


func _in_vision_cone(monster: CharacterBody3D, flat_to_player: Vector3) -> bool:
	if flat_to_player.length_squared() < 0.0001:
		return true
	var forward := -monster.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return true
	forward = forward.normalized()
	var dir := flat_to_player.normalized()
	return forward.angle_to(dir) <= effective_half_angle(
		sight_range, cone_width_at_max_range, cone_angle_deg
	)


static func cone_half_angle(range_m: float, width_at_max_m: float) -> float:
	var half_width := maxf(width_at_max_m, 0.05) * 0.5
	return atan(half_width / maxf(range_m, 0.01))


## Cone half-angle (rad). A positive angle_deg (full FOV) wins over the legacy
## width-at-range form. Shared by the AI check and the sense gizmos.
static func effective_half_angle(
	range_m: float, width_at_max_m: float, angle_deg: float
) -> float:
	if angle_deg > 0.0:
		return deg_to_rad(clampf(angle_deg, 0.0, 340.0) * 0.5)
	return cone_half_angle(range_m, width_at_max_m)


func _has_line_of_sight(monster: CharacterBody3D, target: Node3D) -> bool:
	var world := monster.get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var from := monster.global_position + Vector3(0.0, eye_height, 0.0)
	var to := target.global_position + Vector3(0.0, eye_height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = CollisionLayersScript.CHARACTER_AND_WORLD
	var exclude: Array = [monster.get_rid()]
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	query.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(query)
	return hit.is_empty()


static func occlude_distance(
	world: World3D, from: Vector3, to: Vector3, exclude: Array
) -> float:
	## Distance along from→to until a world blocker, or the full span if clear.
	if world == null or world.direct_space_state == null:
		return from.distance_to(to)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = CollisionLayersScript.CHARACTER_AND_WORLD
	query.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return from.distance_to(to)
	return from.distance_to(hit.position)
