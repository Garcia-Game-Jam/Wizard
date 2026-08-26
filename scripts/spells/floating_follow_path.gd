class_name FloatingFollowPath
extends RefCounted

## Builds leash waypoints for floating follow targets around maze walls.

const WORLD_COLLISION_MASK := 1
const MAX_BFS_NODES := 1200
const WAYPOINT_REACH_DIST := 0.7


static func has_line_of_sight(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3
) -> bool:
	if space == null:
		return true
	if from.distance_squared_to(to) < 0.0001:
		return true
	var ray := PhysicsRayQueryParameters3D.create(from, to)
	ray.collision_mask = WORLD_COLLISION_MASK
	ray.hit_from_inside = true
	return space.intersect_ray(ray).is_empty()


static func build_path(
	from: Vector3,
	goal: Vector3,
	maze: Node,
	float_height: float,
	space: PhysicsDirectSpaceState3D = null,
	use_world_heights: bool = false
) -> Array[Vector3]:
	## When use_world_heights is true, keep from/goal Y (air Follow). Otherwise
	## flatten both to float_height for ground-locked Pull / corridor cruise.
	var path: Array[Vector3] = []
	var query_from := from
	var query_goal := goal
	if use_world_heights:
		query_goal.y = goal.y
	else:
		query_from.y = float_height
		query_goal.y = float_height
	if space != null and has_line_of_sight(space, query_from, query_goal):
		path.append(query_goal)
		return path

	if (
		maze == null
		or not maze.has_method("world_to_cell")
		or not maze.has_method("grid_to_world")
		or not maze.has_method("is_grid_open")
		or not maze.has_method("get_wall_grid")
	):
		path.append(query_goal)
		return path

	var wall_grid: Array = maze.call("get_wall_grid")
	if wall_grid.is_empty():
		path.append(query_goal)
		return path

	var start_cell: Vector2i = _nearest_open_cell(
		maze.call("world_to_cell", query_from), maze
	)
	var goal_cell: Vector2i = _nearest_open_cell(
		maze.call("world_to_cell", query_goal), maze
	)
	if start_cell.x < 0 or goal_cell.x < 0:
		path.append(query_goal)
		return path

	var cells := find_grid_path(wall_grid, start_cell, goal_cell)
	if cells.is_empty():
		path.append(query_goal)
		return path

	var waypoint_y := query_goal.y if use_world_heights else float_height
	# Skip the cell we already occupy; keep corridor centers as waypoints.
	for i in range(1, cells.size()):
		var world: Vector3 = maze.call("grid_to_world", cells[i].x, cells[i].y)
		world.y = waypoint_y
		path.append(world)
	if path.is_empty() or path[path.size() - 1].distance_squared_to(query_goal) > 0.05:
		path.append(query_goal)
	return path


static func advance_path(path: Array[Vector3], current: Vector3) -> Array[Vector3]:
	## Drop waypoints the follower has already reached.
	var remaining: Array[Vector3] = path.duplicate()
	while remaining.size() > 1:
		if current.distance_to(remaining[0]) <= WAYPOINT_REACH_DIST:
			remaining.remove_at(0)
		else:
			break
	return remaining


static func find_grid_path(
	wall_grid: Array,
	start: Vector2i,
	goal: Vector2i
) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if wall_grid.is_empty():
		return empty
	if not _cell_open(wall_grid, start) or not _cell_open(wall_grid, goal):
		return empty
	if start == goal:
		return [start]

	var came_from: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	came_from[start] = start
	var visited := 0
	while not queue.is_empty() and visited < MAX_BFS_NODES:
		var current: Vector2i = queue.pop_front()
		visited += 1
		if current == goal:
			break
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + offset
			if came_from.has(next):
				continue
			if not _cell_open(wall_grid, next):
				continue
			came_from[next] = current
			queue.append(next)

	if not came_from.has(goal):
		return empty

	var reversed: Array[Vector2i] = []
	var walk := goal
	while walk != start:
		reversed.append(walk)
		walk = came_from[walk]
	reversed.append(start)
	reversed.reverse()
	return reversed


static func _nearest_open_cell(cell: Vector2i, maze: Node) -> Vector2i:
	if bool(maze.call("is_grid_open", cell.x, cell.y)):
		return cell
	for radius in range(1, 6):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate := Vector2i(cell.x + dx, cell.y + dy)
				if bool(maze.call("is_grid_open", candidate.x, candidate.y)):
					return candidate
	return Vector2i(-1, -1)


static func _cell_open(wall_grid: Array, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= wall_grid.size():
		return false
	var row: Array = wall_grid[cell.x]
	if cell.y >= row.size():
		return false
	return int(row[cell.y]) == 0
