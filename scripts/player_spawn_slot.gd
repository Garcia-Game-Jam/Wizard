@tool
class_name PlayerSpawnSlot
extends Marker3D

## Roster spawn marker. Its spawn_cell / transform are the in-game spawn source.
## auto_place=true → snap to default corner/center when the maze rebuilds.
## Move the marker in the 3D view (or edit spawn_cell) to override; that disables auto_place.

enum Role {
	APPRENTICE,
	HEADMASTER,
}

const GIZMO_NAME := "SlotGizmo"
const RING_NAME := "SlotSelectRing"
const PREVIEW_NAME := "RolePreview"
const SPAWN_SLOT_GROUP := "player_spawn_slot"
const PlayerSpawnLayoutScript := preload("res://scripts/player_spawn_layout.gd")
## Runtime load() — avoid preload() of apprentice/headmaster (circular with PlayableCharacter).
const APPRENTICE_SCENE_PATH := "res://scenes/characters/apprentice.tscn"

@export var role: Role = Role.APPRENTICE:
	set(value):
		role = value
		_refresh_visuals()
		if Engine.is_editor_hint() and auto_place and not _syncing_pose:
			_request_parent_resnap()

## When true, maze rebuilds place this slot at the default center/corner for its role.
@export var auto_place: bool = true:
	set(value):
		auto_place = value
		if Engine.is_editor_hint() and auto_place and not _syncing_pose:
			_request_parent_resnap()

## Maze cell used for the real match spawn. Edit in inspector or by moving this marker.
@export var spawn_cell: Vector2i = Vector2i.ZERO:
	set(value):
		if spawn_cell == value:
			return
		spawn_cell = value
		if not _syncing_pose:
			auto_place = false
			_apply_spawn_cell_to_transform()

@export_group("Auto defaults")
@export var spawn_slot_index: int = 0:
	set(value):
		## Matches PlayerCharacterConfig.team_id; auto_place corners: 0=NW, 1=NE, 2=SW.
		spawn_slot_index = maxi(value, 0)
		_refresh_visuals()
		if Engine.is_editor_hint() and auto_place and not _syncing_pose:
			_request_parent_resnap()

var _editor_selected: bool = false
var _syncing_pose: bool = false
var _last_synced_origin: Vector3 = Vector3(INF, INF, INF)


func _enter_tree() -> void:
	add_to_group(SPAWN_SLOT_GROUP)


func _ready() -> void:
	set_notify_transform(true)
	if Engine.is_editor_hint():
		set_process(true)
		_ensure_role_preview()
		_refresh_visuals()
	else:
		set_process(false)
		_free_role_preview()
		_free_editor_meshes()


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED:
		return
	if not Engine.is_editor_hint() or _syncing_pose or not is_inside_tree():
		return
	if global_position.distance_squared_to(_last_synced_origin) < 0.0001:
		return
	_on_editor_moved()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	var selected := _is_selected_in_editor()
	if selected == _editor_selected:
		return
	_editor_selected = selected
	_refresh_visuals()


func get_game_role() -> int:
	if role == Role.HEADMASTER:
		return 1
	return 0


func get_spawn_world_position() -> Vector3:
	return global_position


func apply_world_position(world_pos: Vector3) -> void:
	_syncing_pose = true
	global_position = world_pos
	_last_synced_origin = world_pos
	_syncing_pose = false


## Called by Main after maze generate. Honors auto_place vs manual spawn_cell.
func sync_to_maze(maze: Node) -> void:
	if maze == null or not maze.has_method("get_wall_grid"):
		return
	if auto_place:
		var is_headmaster := role == Role.HEADMASTER
		var cell := (
			PlayerSpawnLayoutScript.resolve_headmaster_cell(
				maze.get_wall_grid(), maze.maze_width, maze.maze_height
			)
			if is_headmaster
			else PlayerSpawnLayoutScript.resolve_apprentice_cell(
				maze.get_wall_grid(),
				maze.maze_width,
				maze.maze_height,
				spawn_slot_index
			)
		)
		_set_spawn_cell_preserving_auto(cell)
		_place_at_maze_cell(maze, cell)
	else:
		_place_at_maze_cell(maze, spawn_cell)


func _set_spawn_cell_preserving_auto(cell: Vector2i) -> void:
	_syncing_pose = true
	var keep_auto := auto_place
	spawn_cell = cell
	auto_place = keep_auto
	_syncing_pose = false


func _place_at_maze_cell(maze: Node, cell: Vector2i) -> void:
	var clamped := Vector2i(
		clampi(cell.x, 0, maze.maze_width - 1),
		clampi(cell.y, 0, maze.maze_height - 1)
	)
	var world: Vector3 = maze.cell_to_world(clamped.x, clamped.y)
	world.y = PlayerSpawnLayoutScript.PLAYER_Y
	apply_world_position(world)


func _on_editor_moved() -> void:
	auto_place = false
	var maze := _find_maze()
	if maze == null:
		_last_synced_origin = global_position
		return
	var cell: Vector2i = maze.world_position_to_maze_cell(global_position)
	_syncing_pose = true
	spawn_cell = cell
	_syncing_pose = false
	## Snap to cell center so the marker stays on open maze cells.
	_place_at_maze_cell(maze, cell)
	_request_parent_preview_refresh()


func _apply_spawn_cell_to_transform() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var maze := _find_maze()
	if maze == null:
		return
	_place_at_maze_cell(maze, spawn_cell)
	_request_parent_preview_refresh()


func _find_maze() -> Node:
	return null


func _request_parent_resnap() -> void:
	var main := get_parent()
	if main == null:
		return
	main = main.get_parent()
	if main != null and main.has_method("_snap_player_spawn_slots"):
		main.call_deferred("_snap_player_spawn_slots")


func _request_parent_preview_refresh() -> void:
	var main := get_parent()
	if main == null:
		return
	main = main.get_parent()
	if main != null and main.has_method("_refresh_spawn_zone_preview_from_slots"):
		main.call_deferred("_refresh_spawn_zone_preview_from_slots")


func _free_editor_meshes() -> void:
	for child_name in [GIZMO_NAME, RING_NAME]:
		var existing := get_node_or_null(child_name)
		if existing != null:
			existing.free()


func _ensure_role_preview() -> void:
	## Editor-only Apprentice stand-in. Never present during match play.
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var existing := get_node_or_null(PREVIEW_NAME)
	if existing != null and int(existing.get_meta("spawn_preview_role", -1)) == int(role):
		return
	if existing != null:
		existing.free()
	var packed: PackedScene = load(APPRENTICE_SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("PlayerSpawnSlot: missing preview scene for role %s" % role)
		return
	var preview := packed.instantiate() as Node3D
	preview.name = PREVIEW_NAME
	preview.set_meta("spawn_preview_role", int(role))
	preview.set_meta("_edit_lock_", true)
	add_child(preview)


func _free_role_preview() -> void:
	var existing := get_node_or_null(PREVIEW_NAME)
	if existing != null:
		existing.free()


func _refresh_visuals() -> void:
	if not Engine.is_editor_hint():
		_free_editor_meshes()
		_free_role_preview()
		return
	if not is_inside_tree():
		return
	_ensure_role_preview()
	_update_pillar_gizmo()
	_update_select_ring()


func _update_pillar_gizmo() -> void:
	## Prefer the nested character scene as the 3D stand-in; keep a thin pole only if missing.
	if _has_character_preview():
		var existing := get_node_or_null(GIZMO_NAME)
		if existing != null:
			existing.free()
		return

	var gizmo := get_node_or_null(GIZMO_NAME) as MeshInstance3D
	if gizmo == null:
		gizmo = MeshInstance3D.new()
		gizmo.name = GIZMO_NAME
		gizmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.set_meta("_edit_lock_", true)
		add_child(gizmo)

	var is_headmaster := role == Role.HEADMASTER
	var base_radius := 1.25 if is_headmaster else 1.05
	var base_height := 2.8 if is_headmaster else 2.1
	if _editor_selected:
		base_radius *= 1.35
		base_height *= 1.25

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = base_radius
	cylinder.bottom_radius = base_radius
	cylinder.height = base_height
	gizmo.mesh = cylinder
	gizmo.position = Vector3(0.0, base_height * 0.5, 0.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if is_headmaster:
		mat.albedo_color = Color(0.9, 0.3, 1.0, 0.9 if _editor_selected else 0.75)
		mat.emission = Color(0.85, 0.2, 1.0)
	else:
		mat.albedo_color = Color(0.3, 0.85, 1.0, 0.9 if _editor_selected else 0.75)
		mat.emission = Color(0.2, 0.7, 1.0)
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 5.5 if _editor_selected else 2.0
	mat.disable_fog = true
	gizmo.material_override = mat


func _update_select_ring() -> void:
	var ring := get_node_or_null(RING_NAME) as MeshInstance3D
	if not _editor_selected:
		if ring != null:
			ring.free()
		return

	if ring == null:
		ring = MeshInstance3D.new()
		ring.name = RING_NAME
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.set_meta("_edit_lock_", true)
		add_child(ring)

	var torus := TorusMesh.new()
	torus.inner_radius = 1.6
	torus.outer_radius = 2.1
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.08, 0.0)
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)

	var is_headmaster := role == Role.HEADMASTER
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if is_headmaster:
		mat.albedo_color = Color(1.0, 0.85, 0.2, 0.95)
		mat.emission = Color(1.0, 0.9, 0.2)
	else:
		mat.albedo_color = Color(1.0, 0.95, 0.35, 0.95)
		mat.emission = Color(1.0, 0.95, 0.4)
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 6.0
	mat.disable_fog = true
	ring.material_override = mat


func _is_selected_in_editor() -> bool:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return false
	var selection = _editor_selection()
	if selection == null:
		return false
	var selected: Array = selection.get_selected_nodes()
	for node in selected:
		if node == self:
			return true
		if node is Node and (self as Node).is_ancestor_of(node):
			## Gizmo meshes should select the slot; nested character previews may stay selected.
			if node is MeshInstance3D and (
				node.name == GIZMO_NAME or node.name == RING_NAME
			):
				if not selected.has(self):
					selection.clear()
					selection.add_node(self)
			return true
	return false


func _has_character_preview() -> bool:
	return get_node_or_null(PREVIEW_NAME) != null


func _editor_selection():
	var root := get_tree().root
	if root == null:
		return null
	for child in root.get_children():
		if child.get_class() == "EditorNode" and child.has_method("get_editor_selection"):
			return child.get_editor_selection()
	return null
