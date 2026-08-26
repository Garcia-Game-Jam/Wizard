class_name MonsterSpawnPlacement
extends Node

## After picking a book page: aim a ghost at the crosshair, LMB spawn, Esc cancel.

signal placement_finished(confirmed: bool)

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")
const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")

const WORLD_COLLISION_MASK := 1
const PLACE_FORWARD := 6.0
const GHOST_HEIGHT := 1.1
const GHOST_RADIUS := 0.35

var _player: CharacterBody3D
var _entry: Dictionary = {}
var _active := false
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _spawn_pos := Vector3.ZERO
var _target_valid := false


func configure(player: CharacterBody3D) -> void:
	_player = player


func is_active() -> bool:
	return _active


func begin(entry: Dictionary) -> bool:
	if _player == null or entry.is_empty():
		return false
	if _active:
		cancel()
	_entry = entry.duplicate(true)
	_active = true
	_ensure_ghost()
	_tint_ghost()
	_ghost.visible = true
	set_process(true)
	set_process_input(true)
	_update_target()
	return true


func cancel() -> void:
	if not _active:
		return
	_teardown(false)


func try_confirm() -> bool:
	if not _active or not _target_valid:
		return false
	var entry := _entry.duplicate(true)
	var pos := _spawn_pos
	_teardown(true)
	_spawn_monster(entry, pos)
	return true


func get_prompt() -> String:
	if not _active:
		return ""
	if _target_valid:
		return "LMB — Summon  ·  Esc — Cancel"
	return "Aim at open ground  ·  Esc — Cancel"


func _process(_delta: float) -> void:
	if not _active:
		return
	_update_target()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		## Always consume LMB while placing so wand cast cannot start.
		try_confirm()
		get_viewport().set_input_as_handled()


func _update_target() -> void:
	_target_valid = false
	if _ghost == null:
		return
	var hit := _aim_ground_point()
	if hit == Vector3.INF:
		_ghost.visible = false
		return
	_spawn_pos = hit + Vector3(0.0, 0.05, 0.0)
	_target_valid = true
	_ghost.global_position = _spawn_pos + Vector3(0.0, GHOST_HEIGHT * 0.5, 0.0)
	_ghost.visible = true


func _aim_ground_point() -> Vector3:
	if _player == null or not _player.is_inside_tree():
		return Vector3.INF
	var origin := Vector3.ZERO
	var direction := Vector3.FORWARD
	if _player.has_method("get_view_origin") and _player.has_method("get_view_direction"):
		origin = _player.call("get_view_origin")
		direction = _player.call("get_view_direction")
	elif _player.has_method("get_wand_cast_origin") and _player.has_method("get_wand_cast_direction"):
		origin = _player.call("get_wand_cast_origin")
		direction = _player.call("get_wand_cast_direction")
	else:
		origin = _player.global_position + Vector3(0.0, 1.4, 0.0)
		direction = -_player.global_transform.basis.z
	if direction.length_squared() < 0.0001:
		return Vector3.INF
	direction = direction.normalized()
	var space := _player.get_world_3d().direct_space_state
	var to := origin + direction * 40.0
	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.collision_mask = WORLD_COLLISION_MASK
	query.exclude = [_player.get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		## Soft fallback ahead of the player on the floor plane.
		var flat := direction
		flat.y = 0.0
		if flat.length_squared() < 0.0001:
			flat = Vector3.FORWARD
		flat = flat.normalized()
		var guess := _player.global_position + flat * PLACE_FORWARD
		guess.y = _player.global_position.y
		return guess
	var pos: Vector3 = result["position"]
	var normal: Vector3 = result.get("normal", Vector3.UP)
	## Prefer floor-like hits; still allow near-vertical if nothing else.
	if normal.y < 0.35:
		var drop_from := pos + Vector3(0.0, 0.4, 0.0)
		var drop_to := pos + Vector3(0.0, -6.0, 0.0)
		var drop := PhysicsRayQueryParameters3D.create(drop_from, drop_to)
		drop.collision_mask = WORLD_COLLISION_MASK
		drop.exclude = [_player.get_rid()]
		var floor_hit := space.intersect_ray(drop)
		if not floor_hit.is_empty():
			return floor_hit["position"]
	return pos


func _spawn_monster(entry: Dictionary, world_pos: Vector3) -> void:
	var scene_path := str(entry.get("scene_path", ""))
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var monster := packed.instantiate()
	if monster == null:
		return
	var parent := _monster_parent()
	parent.add_child(monster)
	if monster is Node3D:
		var spawned := monster as Node3D
		spawned.global_position = world_pos
		_face_spawned_monster_toward_player(spawned)
	if monster.has_method("apply_summon_appearance"):
		var tint: Color = entry.get("tint", Color.WHITE)
		var eye_glow: Color = entry.get("eye_glow_color", Color(0.2, 0.55, 1.0, 1.0))
		monster.call("apply_summon_appearance", tint, eye_glow)


func _face_spawned_monster_toward_player(spawned: Node3D) -> void:
	if _player == null or spawned == null:
		return
	var face := _player.global_position
	face.y = spawned.global_position.y
	var flat := Vector3(face.x - spawned.global_position.x, 0.0, face.z - spawned.global_position.z)
	if flat.length_squared() < 0.04:
		return
	spawned.look_at(face, Vector3.UP)


func _monster_parent() -> Node:
	var match_root := GameWorldScript.find_match_root(_player.get_tree())
	var root: Node = match_root if match_root != null else _player.get_tree().current_scene
	if root == null:
		return _player
	var bucket := root.get_node_or_null("Monsters")
	if bucket != null:
		return bucket
	bucket = Node3D.new()
	bucket.name = "Monsters"
	root.add_child(bucket)
	return bucket


func _teardown(confirmed: bool) -> void:
	_active = false
	set_process(false)
	set_process_input(false)
	if _ghost != null:
		_ghost.visible = false
	_target_valid = false
	_entry.clear()
	placement_finished.emit(confirmed)


func _ensure_ghost() -> void:
	if _ghost != null:
		return
	_ghost = MeshInstance3D.new()
	_ghost.name = "MonsterSpawnGhost"
	var capsule := CapsuleMesh.new()
	capsule.radius = GHOST_RADIUS
	capsule.height = GHOST_HEIGHT
	_ghost.mesh = capsule
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.85, 0.35, 0.3, 0.4)
	_ghost_material.emission_enabled = true
	_ghost_material.emission = Color(0.9, 0.35, 0.25)
	_ghost_material.emission_energy_multiplier = 1.1
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_material
	_ghost.layers = WorldVisualLayersScript.WORLD
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	var match_root := GameWorldScript.find_match_root(_player.get_tree())
	var parent: Node = match_root if match_root != null else _player
	parent.add_child(_ghost)


func _tint_ghost() -> void:
	if _ghost_material == null:
		return
	var tint: Color = _entry.get("tint", Color(0.85, 0.35, 0.3, 1.0))
	_ghost_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.4)
	_ghost_material.emission = Color(tint.r, tint.g, tint.b)
