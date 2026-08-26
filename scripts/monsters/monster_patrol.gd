class_name MonsterPatrol
extends RefCounted

## Wander inside a patrol rect. Maze path graphs are gone; this is open-floor only.

const SAMPLE_COUNT := 8
const RAY_HEIGHT := 0.45
const RAY_START := 0.28
const WORLD_MASK := 1
const ARRIVE_DIST := 0.45

var graph: Dictionary = {}
var home: Vector3 = Vector3.ZERO
var home_set: bool = false
var radius: float = 8.0
var size: Vector2 = Vector2(16.0, 16.0)
var goal: Vector3 = Vector3.ZERO


func set_home(world_pos: Vector3) -> void:
	home = world_pos
	home_set = true


func begin(body: CharacterBody3D, rng: RandomNumberGenerator, patrol_radius: float) -> void:
	radius = maxf(patrol_radius, 0.5)
	size = Vector2(radius * 2.0, radius * 2.0)
	graph = find_graph(body)
	if body != null and body.has_meta("patrol_home"):
		set_home(body.get_meta("patrol_home"))
	if not home_set and body != null:
		home = body.global_position if body.is_inside_tree() else body.position
		home_set = true
	_sync_routes(body)
	goal = pick_goal(body, radius, rng)


func tick(body: CharacterBody3D, rng: RandomNumberGenerator) -> void:
	if body == null:
		return
	_sync_routes(body)
	if _arrived(body):
		goal = pick_goal(body, radius, rng)


func follow_velocity(body: CharacterBody3D, speed: float) -> Vector3:
	if body == null:
		return Vector3.ZERO
	return _toward(body.global_position, goal, speed, body.velocity.y)


static func find_graph(node: Node) -> Dictionary:
	if node != null and node.has_meta("maze_path_graph"):
		var meta_graph = node.get_meta("maze_path_graph")
		if meta_graph is Dictionary:
			return meta_graph
	return {}


static func sample_dirs(forward: Vector3, count: int = SAMPLE_COUNT) -> PackedVector3Array:
	var fwd := Vector3(forward.x, 0.0, forward.z)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0.0, 0.0, -1.0)
	else:
		fwd = fwd.normalized()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var out := PackedVector3Array()
	out.resize(maxi(count, 1))
	for i in out.size():
		var ang := float(i) * TAU / float(out.size())
		out[i] = (fwd * cos(ang) + right * sin(ang)).normalized()
	return out


static func clear_distance(body: CollisionObject3D, dir: Vector3, max_dist: float) -> float:
	if body == null or not body.is_inside_tree():
		return maxf(max_dist, 0.0)
	var world := body.get_world_3d()
	if world == null or world.direct_space_state == null:
		return maxf(max_dist, 0.0)
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	flat = flat.normalized()
	var from := body.global_position + Vector3(0.0, RAY_HEIGHT, 0.0) + flat * RAY_START
	var span := maxf(max_dist, 0.05)
	var to := from + flat * span
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = WORLD_MASK
	query.exclude = [body.get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return span
	return maxf(from.distance_to(hit.position) - 0.12, 0.0)


static func pick_goal(
	body: CharacterBody3D, patrol_radius: float, rng: RandomNumberGenerator
) -> Vector3:
	if body == null:
		return Vector3.ZERO
	var forward := -body.global_transform.basis.z
	var dirs := sample_dirs(forward)
	var best_i := 0
	var best := -1.0
	for i in dirs.size():
		var clear := clear_distance(body, dirs[i], patrol_radius)
		if clear > best:
			best = clear
			best_i = i
	var factor := 0.7
	if rng != null:
		factor = rng.randf_range(0.45, 0.9)
	return body.global_position + dirs[best_i] * maxf(best * factor, 0.4)


func _arrived(body: CharacterBody3D) -> bool:
	var flat := Vector3(
		goal.x - body.global_position.x, 0.0, goal.z - body.global_position.z
	)
	return flat.length() <= ARRIVE_DIST


func _toward(from: Vector3, to: Vector3, speed: float, y_velocity: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3(0.0, y_velocity, 0.0)
	flat = flat.normalized()
	return Vector3(flat.x * speed, y_velocity, flat.z * speed)


func _sync_routes(body: CharacterBody3D) -> void:
	if body != null and body.has_meta("patrol_size"):
		var raw = body.get_meta("patrol_size")
		if raw is Vector2:
			size = raw
			radius = maxf(size.x, size.y) * 0.5
	elif body != null and "patrol_radius" in body:
		radius = maxf(float(body.patrol_radius), 0.5)
		size = Vector2(radius * 2.0, radius * 2.0)
	if body != null and body.has_meta("patrol_home"):
		set_home(body.get_meta("patrol_home"))
