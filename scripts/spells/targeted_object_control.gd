class_name TargetedObjectControl
extends RefCounted

## Pull / follow / dispell helpers for Target-highlighted objects.

const TargetHighlightScript := preload("res://scripts/spells/target_highlight.gd")
const FloatingFollowPathScript := preload("res://scripts/spells/floating_follow_path.gd")
const HoveringOrbMotionScript := preload("res://scripts/spells/hovering_orb_motion.gd")

const FOLLOW_DRIVER_NAME := "SpellFollowDriver"
const PULL_DRIVER_NAME := "SpellPullDriver"
## Stop cruising once within this flat distance of the player.
const FOLLOW_STOP_DIST := 1.7
## Resume cruising only after the player walks this far away (hysteresis).
const FOLLOW_START_DIST := 2.55
## Match light-ball hover height above ground.
const FOLLOW_HEIGHT := HoveringOrbMotionScript.HEIGHT_LIGHT_BALL
const RELIC_FLOAT_HEIGHT := HoveringOrbMotionScript.HEIGHT_RELIC
## Follow stays on the ground plane; max cruise ≈ brisk walk+.
const FOLLOW_SPEED := 5.0
## Pull: rush in, then ease to a stop in front of the caster.
const PULL_MAX_SPEED := 14.0
const PULL_MIN_SPEED := 1.25
const PULL_SLOW_RADIUS := 2.8
const PULL_ARRIVE_DIST := 0.12
const PULL_DISTANCE := 2.35
const REPATH_INTERVAL_SEC := 0.55
const REPATH_GOAL_MOVE := 1.4
const LOS_ARRIVE_TOLERANCE := 0.45
const WORLD_COLLISION_MASK := 1
const TARGET_KIND_LIGHT_BALL := "light_ball"
const TARGET_KIND_RELIC := "relic"
const TARGET_KIND_RELIC_CLONE := "relic_clone"

const RELIC_CLONE_GROUP := "relic_clone"

const RelicCloneScript := preload("res://scripts/headmaster/relic_clone.gd")
const LightBallOrbScript := preload("res://scripts/spells/light_ball_orb.gd")


static func has_active_follows(tree: SceneTree) -> bool:
	if tree == null:
		return false
	return not tree.get_nodes_in_group("spell_follow_driver").is_empty()


static func pick_looked_at(player: CharacterBody3D, require_los: bool = false) -> Node3D:
	## Pick among currently highlighted objects (after Target).
	if player == null or not player.is_inside_tree():
		return null
	return pick_among_anchors(
		player,
		TargetHighlightScript.get_highlighted_anchors(player.get_tree()),
		require_los
	)


static func pick_targetable(player: CharacterBody3D) -> Node3D:
	## Pick one targetable world object closest to the aim cursor (for Target cast).
	if player == null or not player.is_inside_tree():
		return null
	return pick_among_anchors(
		player,
		TargetHighlightScript.collect_anchors(player.get_tree()),
		false
	)


static func pick_among_anchors(
	player: CharacterBody3D,
	anchors: Array[Node3D],
	require_los: bool = false
) -> Node3D:
	if player == null or anchors.is_empty():
		return null
	var camera := _find_camera(player)
	var cursor := _aim_cursor(player)
	var best: Node3D = null
	var best_score := INF
	for anchor in anchors:
		if anchor == null or not is_instance_valid(anchor):
			continue
		if require_los and not has_clear_line_of_sight(player, anchor):
			continue
		var score := _cursor_proximity_score(camera, cursor, player, anchor)
		if score < best_score:
			best_score = score
			best = anchor
	return best


static func has_clear_line_of_sight(player: CharacterBody3D, target: Node3D) -> bool:
	if player == null or target == null or not player.is_inside_tree():
		return false
	var world_3d := player.get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return true
	var from := _view_origin(player)
	var to := target.global_position
	if from.distance_squared_to(to) < 0.0001:
		return true
	var ray := PhysicsRayQueryParameters3D.create(from, to)
	ray.collision_mask = WORLD_COLLISION_MASK
	ray.hit_from_inside = true
	ray.exclude = _collision_rids(player)
	var hit := world_3d.direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return true
	# Treat a near-target collider (e.g. relic body) as still having LOS.
	return hit.position.distance_to(to) <= LOS_ARRIVE_TOLERANCE


static func _aim_cursor(player: CharacterBody3D) -> Vector2:
	var viewport := player.get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var mouse := viewport.get_mouse_position()
	var rect := viewport.get_visible_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return mouse
	# Captured mouse / FPS aim uses the crosshair at screen center.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return rect.size * 0.5
	return mouse


static func _find_camera(player: CharacterBody3D) -> Camera3D:
	if player == null:
		return null
	if player.has_method("get_view_camera"):
		var cam: Variant = player.call("get_view_camera")
		if cam is Camera3D:
			return cam as Camera3D
	var named := player.find_child("FirstPersonCamera", true, false)
	if named is Camera3D:
		return named as Camera3D
	return player.find_child("Camera3D", true, false) as Camera3D


static func _cursor_proximity_score(
	camera: Camera3D,
	cursor: Vector2,
	player: CharacterBody3D,
	anchor: Node3D
) -> float:
	if camera != null and camera.is_inside_tree():
		if camera.is_position_behind(anchor.global_position):
			return INF
		var screen := camera.unproject_position(anchor.global_position)
		return screen.distance_squared_to(cursor)
	# Fallback without a camera: prefer aim-aligned anchors.
	var origin := _view_origin(player)
	var look := _view_direction(player)
	var to_anchor := anchor.global_position - origin
	var dist := to_anchor.length()
	if dist < 0.15:
		return INF
	var align := to_anchor.normalized().dot(look)
	if align <= 0.0:
		return INF
	return (1.0 - align) * 12.0 + dist * 0.03


static func _collision_rids(root: Node) -> Array:
	var rids: Array = []
	if root == null:
		return rids
	if root is CollisionObject3D:
		rids.append((root as CollisionObject3D).get_rid())
	for child in root.get_children():
		rids.append_array(_collision_rids(child))
	return rids


static func describe_target(node: Node3D) -> Dictionary:
	if node == null:
		return {}
	if node.is_in_group("light_ball") or node is LightBallOrb:
		return {
			"kind": TARGET_KIND_LIGHT_BALL,
			"mark": node.global_position,
		}
	if node.is_in_group(RELIC_CLONE_GROUP) or node is RelicCloneScript:
		return {
			"kind": TARGET_KIND_RELIC_CLONE,
			"mark": node.global_position,
		}
	# Relic root from DeliveryObjective.get_spell_target_nodes().
	return {
		"kind": TARGET_KIND_RELIC,
		"mark": node.global_position,
	}


static func resolve_target(
	tree: SceneTree,
	kind: String,
	mark: Vector3
) -> Node3D:
	if tree == null:
		return null
	if kind == TARGET_KIND_LIGHT_BALL:
		var best: Node3D = null
		var best_dist := INF
		for node in tree.get_nodes_in_group("light_ball"):
			if not node is Node3D:
				continue
			var dist := (node as Node3D).global_position.distance_squared_to(mark)
			if dist < best_dist:
				best_dist = dist
				best = node as Node3D
		return best
	if kind == TARGET_KIND_RELIC:
		for node in tree.get_nodes_in_group("delivery_objective"):
			if node != null and node.has_method("get_spell_target_nodes"):
				var targets: Variant = node.call("get_spell_target_nodes")
				if targets is Array and not targets.is_empty():
					return targets[0] as Node3D
	if kind == TARGET_KIND_RELIC_CLONE:
		var best_clone: Node3D = null
		var best_clone_dist := INF
		for node in tree.get_nodes_in_group(RELIC_CLONE_GROUP):
			if not node is Node3D:
				continue
			var dist := (node as Node3D).global_position.distance_squared_to(mark)
			if dist < best_clone_dist:
				best_clone_dist = dist
				best_clone = node as Node3D
		return best_clone
	return null


static func pull_object(player: CharacterBody3D, target: Node3D) -> void:
	if player == null or target == null:
		return
	if not has_clear_line_of_sight(player, target):
		return
	clear_follows_on(target)
	clear_pulls_on(target)
	var dest := _pull_destination(player)
	var driver := _SpellPullDriver.new()
	driver.name = PULL_DRIVER_NAME
	target.add_child(driver)
	driver.begin(player, dest)


static func start_follow(player: CharacterBody3D, target: Node3D) -> void:
	if player == null or target == null:
		return
	clear_all_follows(player.get_tree())
	clear_pulls_on(target)
	var driver := _SpellFollowDriver.new()
	driver.name = FOLLOW_DRIVER_NAME
	target.add_child(driver)
	driver.begin(player)


static func stop_all(tree: SceneTree) -> void:
	if tree == null:
		return
	TargetHighlightScript.clear_all(tree)
	clear_all_follows(tree)
	clear_all_pulls(tree)


static func clear_all_follows(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group("spell_follow_driver"):
		if is_instance_valid(node):
			node.name = "%s_dying" % str(node.name)
			node.queue_free()


static func clear_all_pulls(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group("spell_pull_driver"):
		if is_instance_valid(node):
			node.name = "%s_dying" % str(node.name)
			node.queue_free()


static func clear_follows_on(target: Node3D) -> void:
	if target == null:
		return
	var existing := target.get_node_or_null(FOLLOW_DRIVER_NAME)
	if existing != null:
		existing.name = "%s_dying" % FOLLOW_DRIVER_NAME
		existing.queue_free()


static func clear_pulls_on(target: Node3D) -> void:
	if target == null:
		return
	var existing := target.get_node_or_null(PULL_DRIVER_NAME)
	if existing != null:
		existing.name = "%s_dying" % PULL_DRIVER_NAME
		existing.queue_free()


static func _pull_destination(player: CharacterBody3D) -> Vector3:
	## Ground-plane point ahead of the caster (XZ only — keeps orbs reachable).
	var look := _facing_horizontal(player)
	var origin := Vector3(
		player.global_position.x,
		player.global_position.y + FOLLOW_HEIGHT,
		player.global_position.z
	)
	var desired := origin + look * PULL_DISTANCE
	var world_3d := player.get_world_3d() if player != null and player.is_inside_tree() else null
	if world_3d == null:
		desired.y = FOLLOW_HEIGHT
		return desired
	desired = LightBallOrbScript.find_clear_point(world_3d, origin, desired)
	return LightBallOrbScript.snap_to_ground(world_3d, desired)


static func _view_origin(player: CharacterBody3D) -> Vector3:
	## Eye / camera origin for LOS checks (matches what the reticle sees).
	if player.has_method("get_view_origin"):
		return player.call("get_view_origin")
	if player.has_method("get_wand_cast_origin"):
		return player.call("get_wand_cast_origin")
	return player.global_position + Vector3(0.0, 1.4, 0.0)


static func _view_direction(player: CharacterBody3D) -> Vector3:
	## Prefer wand→crosshair so pull/follow destinations match projectile aim.
	if player.has_method("get_wand_cast_direction"):
		return player.call("get_wand_cast_direction")
	if player.has_method("get_view_direction"):
		return player.call("get_view_direction")
	return -player.global_transform.basis.z.normalized()


static func _facing_horizontal(player: CharacterBody3D) -> Vector3:
	var forward := _view_direction(player)
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		if player.has_method("get_view_direction"):
			forward = player.call("get_view_direction")
			forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -player.global_transform.basis.z
		forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


static func collect_dispellable_anchors(tree: SceneTree) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if tree == null:
		return out
	for anchor in TargetHighlightScript.get_highlighted_anchors(tree):
		if anchor == null or not is_instance_valid(anchor):
			continue
		if (
			anchor.is_in_group("light_ball")
			or anchor is LightBallOrb
			or anchor.is_in_group(RELIC_CLONE_GROUP)
			or anchor is RelicCloneScript
		):
			out.append(anchor)
	return out


static func pick_dispellable(player: CharacterBody3D) -> Node3D:
	if player == null or not player.is_inside_tree():
		return null
	return pick_among_anchors(
		player,
		collect_dispellable_anchors(player.get_tree()),
		false
	)


static func _delivery_from_relic(relic_root: Node3D) -> Node:
	var node: Node = relic_root
	while node != null:
		if node.is_in_group("delivery_objective"):
			return node
		node = node.get_parent()
	return null


static func _height_above_ground_for(host: Node3D) -> float:
	if host is LightBallOrb:
		return HoveringOrbMotionScript.HEIGHT_LIGHT_BALL
	return HoveringOrbMotionScript.HEIGHT_RELIC


static func _motion_base_position(host: Node3D) -> Vector3:
	## Use the non-bobbing base so pathing doesn't rumble with the hover sine.
	if host is LightBallOrb:
		return (host as LightBallOrb).get_hover_base()
	if host is RelicCloneScript:
		return (host as RelicCloneScript).get_hover_base()
	var objective := _delivery_from_relic(host)
	if objective != null and objective.has_method("get_relic_motion_base"):
		return objective.call("get_relic_motion_base")
	return host.global_position


static func follow_approach_goal(player: CharacterBody3D, height: float) -> Vector3:
	## XZ approach toward the player; height is for ground-plane path queries.
	var goal := player.global_position
	goal.y = height
	return goal


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()


static func _world_3d_for(host: Node3D, player: CharacterBody3D) -> World3D:
	if host != null and host.is_inside_tree():
		return host.get_world_3d()
	if player != null and player.is_inside_tree():
		return player.get_world_3d()
	return null


static func _apply_float_position(host: Node3D, world_pos: Vector3) -> void:
	if host is LightBallOrb:
		(host as LightBallOrb).spell_set_guided_position(world_pos, true)
		return
	if host is RelicCloneScript:
		(host as RelicCloneScript).spell_set_guided_position(world_pos, true)
		return
	var objective := _delivery_from_relic(host)
	if objective != null and objective.has_method("spell_set_guided_relic_position"):
		objective.call("spell_set_guided_relic_position", world_pos, true)
		return
	host.global_position = world_pos


static func _step_along_route(
	from: Vector3,
	waypoint: Vector3,
	speed: float,
	delta: float,
	world_3d: World3D = null,
	height_above_ground: float = FOLLOW_HEIGHT
) -> Vector3:
	return HoveringOrbMotionScript.cruise_base_toward(
		from,
		waypoint,
		delta,
		world_3d,
		height_above_ground,
		speed,
		HoveringOrbMotionScript.CRUISE_SMOOTH
	)


static func pull_speed_for_distance(dist: float) -> float:
	## Rush when far; ease down in front of the caster.
	if dist >= PULL_SLOW_RADIUS:
		return PULL_MAX_SPEED
	if dist <= 0.0:
		return PULL_MIN_SPEED
	var t := dist / PULL_SLOW_RADIUS
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(PULL_MIN_SPEED, PULL_MAX_SPEED, t)


static func _step_pull_toward(
	from: Vector3,
	dest: Vector3,
	delta: float,
	world_3d: World3D,
	height_above_ground: float
) -> Vector3:
	return HoveringOrbMotionScript.cruise_pull_toward(
		from,
		dest,
		delta,
		world_3d,
		height_above_ground,
		pull_speed_for_distance(_flat_distance(from, dest))
	)


static func _build_float_path(
	player: CharacterBody3D,
	from: Vector3,
	goal: Vector3
) -> Array[Vector3]:
	var space: PhysicsDirectSpaceState3D = null
	if player != null and player.is_inside_tree():
		var world_3d := player.get_world_3d()
		if world_3d != null:
			space = world_3d.direct_space_state
	var path := FloatingFollowPathScript.build_path(
		from, goal, null, FOLLOW_HEIGHT, space, false
	)
	return FloatingFollowPathScript.advance_path(path, from)


class _SpellPullDriver extends Node:
	var _player: CharacterBody3D
	var _dest := Vector3.ZERO


	func _ready() -> void:
		add_to_group("spell_pull_driver")
		set_process(true)


	func begin(player: CharacterBody3D, dest: Vector3) -> void:
		_player = player
		_dest = dest


	func _process(delta: float) -> void:
		var host := get_parent() as Node3D
		if host == null or not is_instance_valid(host):
			queue_free()
			return
		var from := TargetedObjectControl._motion_base_position(host)
		var world_3d := TargetedObjectControl._world_3d_for(host, _player)
		var height := TargetedObjectControl._height_above_ground_for(host)
		var next_pos := TargetedObjectControl._step_pull_toward(
			from, _dest, delta, world_3d, height
		)
		TargetedObjectControl._apply_float_position(host, next_pos)
		if (
			TargetedObjectControl._flat_distance(next_pos, _dest)
			<= TargetedObjectControl.PULL_ARRIVE_DIST
		):
			var final_pos := Vector3(_dest.x, from.y, _dest.z)
			final_pos = HoveringOrbMotionScript.snap_base(world_3d, final_pos, height)
			TargetedObjectControl._apply_float_position(host, final_pos)
			queue_free()


class _SpellFollowDriver extends Node:
	var _player: CharacterBody3D
	var _path: Array[Vector3] = []
	var _path_goal := Vector3.ZERO
	var _smoothed_goal := Vector3.ZERO
	var _goal_ready := false
	var _repath_in := 0.0
	## When true, hold still until the player walks beyond FOLLOW_START_DIST.
	var _parked := false


	func _ready() -> void:
		add_to_group("spell_follow_driver")
		set_process(true)


	func begin(player: CharacterBody3D) -> void:
		_player = player
		_repath_in = 0.0
		_parked = false
		_goal_ready = false


	func _process(delta: float) -> void:
		if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
			queue_free()
			return
		var host := get_parent() as Node3D
		if host == null or not is_instance_valid(host):
			queue_free()
			return

		var from := TargetedObjectControl._motion_base_position(host)
		var flat_dist := TargetedObjectControl._flat_distance(from, _player.global_position)

		if _parked:
			if flat_dist < TargetedObjectControl.FOLLOW_START_DIST:
				return
			_parked = false

		if flat_dist <= TargetedObjectControl.FOLLOW_STOP_DIST:
			_parked = true
			_path.clear()
			return

		var ideal := TargetedObjectControl.follow_approach_goal(_player, from.y)
		if not _goal_ready:
			_smoothed_goal = from
			_goal_ready = true
		_smoothed_goal = HoveringOrbMotionScript.smooth_goal(
			_smoothed_goal, ideal, delta
		)

		_repath_in -= delta
		var needs_repath := (
			_path.is_empty()
			or _repath_in <= 0.0
			or _smoothed_goal.distance_to(_path_goal)
			>= TargetedObjectControl.REPATH_GOAL_MOVE
		)
		if needs_repath:
			_path = TargetedObjectControl._build_float_path(
				_player, from, _smoothed_goal
			)
			_path_goal = _smoothed_goal
			_repath_in = TargetedObjectControl.REPATH_INTERVAL_SEC
		else:
			_path = FloatingFollowPathScript.advance_path(_path, from)

		var waypoint := _smoothed_goal if _path.is_empty() else _path[0]
		var world_3d := TargetedObjectControl._world_3d_for(host, _player)
		var height := TargetedObjectControl._height_above_ground_for(host)
		var next_pos := TargetedObjectControl._step_along_route(
			from,
			waypoint,
			TargetedObjectControl.FOLLOW_SPEED,
			delta,
			world_3d,
			height
		)
		TargetedObjectControl._apply_float_position(host, next_pos)

		if (
			TargetedObjectControl._flat_distance(next_pos, _player.global_position)
			<= TargetedObjectControl.FOLLOW_STOP_DIST
		):
			_parked = true
			_path.clear()
