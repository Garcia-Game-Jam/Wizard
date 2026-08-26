class_name PlayerSpawnLayout
extends RefCounted

## Roster spawn placement: headmaster at maze center; each apprentice team in a corner cluster.

const PLAYER_Y := 0.5
## Center-to-center gap for co-located teammates. Apprentice capsule radius ≈ 0.24, so
## this stays above 2×radius (+ safe_margin) and fits three players in a 3.0 maze cell.
const TEAMMATE_SPAWN_SPACING := 1.0
## Team spawn corner targets (NW, NE, SW). SE is reserved for the exit crystal.
const APPRENTICE_CORNER_TARGETS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
]


## Centered row offsets so teammates do not stack or clip capsules at spawn.
static func teammate_offsets(count: int) -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	if count <= 0:
		return offsets
	var start_x := -0.5 * float(count - 1) * TEAMMATE_SPAWN_SPACING
	for i in count:
		offsets.append(Vector3(start_x + float(i) * TEAMMATE_SPAWN_SPACING, 0.0, 0.0))
	return offsets


static func compute_positions(
	_spawn_cell: Vector2i,
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	cell_to_world: Callable,
	player_count: int
) -> Array[Vector3]:
	## Legacy helper for tests: first player at NW corner cell, then other corners.
	if player_count <= 0:
		return []
	var cells := collect_roster_spawn_cells(wall_grid, maze_width, maze_height)
	var positions: Array[Vector3] = []
	for i in player_count:
		var cell: Vector2i = cells[mini(i, cells.size() - 1)]
		var pos: Vector3 = cell_to_world.call(cell.x, cell.y)
		pos.y = PLAYER_Y
		positions.append(pos)
	return positions


## Every maze cell whose center is open floor (no wall).
static func collect_open_spawn_cells(
	wall_grid: Array,
	maze_width: int,
	maze_height: int
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in maze_width:
		for y in maze_height:
			var cell := Vector2i(x, y)
			if _is_open_floor_cell(wall_grid, cell):
				cells.append(cell)
	return cells


## [headmaster_center, apprentice_corner_0, apprentice_corner_1, apprentice_corner_2]
static func collect_roster_spawn_cells(
	wall_grid: Array,
	maze_width: int,
	maze_height: int
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.append(resolve_headmaster_cell(wall_grid, maze_width, maze_height))
	for i in 3:
		cells.append(resolve_apprentice_cell(wall_grid, maze_width, maze_height, i))
	return cells


static func resolve_headmaster_cell(
	wall_grid: Array,
	maze_width: int,
	maze_height: int
) -> Vector2i:
	var center := Vector2i(int(maze_width * 0.5), int(maze_height * 0.5))
	return _nearest_open_cell(wall_grid, maze_width, maze_height, center)


static func resolve_apprentice_cell(
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	corner_index: int
) -> Vector2i:
	var target := _apprentice_corner_target(maze_width, maze_height, corner_index)
	return _nearest_open_cell(wall_grid, maze_width, maze_height, target)


static func world_position_for_roster_slot(
	is_headmaster: bool,
	apprentice_corner_index: int,
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	cell_to_world: Callable
) -> Vector3:
	var cell: Vector2i
	if is_headmaster:
		cell = resolve_headmaster_cell(wall_grid, maze_width, maze_height)
	else:
		cell = resolve_apprentice_cell(
			wall_grid,
			maze_width,
			maze_height,
			apprentice_corner_index
		)
	var pos: Vector3 = cell_to_world.call(cell.x, cell.y)
	pos.y = PLAYER_Y
	return pos


static func _apprentice_corner_target(
	maze_width: int,
	maze_height: int,
	corner_index: int
) -> Vector2i:
	var idx := clampi(corner_index, 0, 2)
	var spec: Vector2i = APPRENTICE_CORNER_TARGETS[idx]
	return Vector2i(
		0 if spec.x == 0 else maze_width - 1,
		0 if spec.y == 0 else maze_height - 1
	)


static func _nearest_open_cell(
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	target: Vector2i
) -> Vector2i:
	var best := target
	var best_score := 0x3fffffff
	var found := false
	for x in maze_width:
		for y in maze_height:
			var cell := Vector2i(x, y)
			if not _is_open_floor_cell(wall_grid, cell):
				continue
			var score := absi(cell.x - target.x) + absi(cell.y - target.y)
			if score < best_score:
				best_score = score
				best = cell
				found = true
			elif score == best_score and found:
				if cell.x < best.x or (cell.x == best.x and cell.y < best.y):
					best = cell
	if found:
		return best
	return Vector2i(
		clampi(target.x, 0, maze_width - 1),
		clampi(target.y, 0, maze_height - 1)
	)


static func _is_open_floor_cell(wall_grid: Array, cell: Vector2i) -> bool:
	var gx: int = cell.x * 2 + 1
	var gy: int = cell.y * 2 + 1
	if gx < 0 or gy < 0 or gx >= wall_grid.size():
		return false
	if gy >= wall_grid[gx].size():
		return false
	return wall_grid[gx][gy] == 0
