@tool
extends Node3D

## Live monster AI on a greybox floor. Patrol size/origin on this node.

const MONSTER_PICK_WRETCH := 0
const MONSTER_PICK_ASH_WRETCH := 1
const MONSTER_PICK_EMBER_WRETCH := 2
const MONSTER_PICK_CHARGER := 3
const PAD_NW := 0
const PAD_NE := 1
const PAD_SW := 2
const PAD_SE := 3
const PAD_CENTER := 4
const PAD_CLEARING := 5

const WretchScene := preload("res://scenes/monsters/wretch.tscn")
const AshWretchScene := preload("res://scenes/monsters/ash_wretch.tscn")
const EmberWretchScene := preload("res://scenes/monsters/ember_wretch.tscn")
const ChargerScene := preload("res://scenes/monsters/charger.tscn")
const PlayableScene := preload("res://scenes/characters/playable_character.tscn")

@export_tool_button("Rebuild Arena", "Callable")
var rebuild_arena_action := rebuild_arena

@export_group("Patrol")
## Top-down rect. Height is Z on the floor. Independent of spawn.
@export var lock_patrol_square: bool = true:
	set(value):
		lock_patrol_square = value
		if _syncing_patrol:
			return
		if lock_patrol_square:
			var side := maxf(patrol_width, patrol_height)
			_syncing_patrol = true
			patrol_width = side
			patrol_height = side
			_syncing_patrol = false
		_apply_patrol_inspector()
@export_range(-80.0, 80.0, 0.1, "or_greater", "or_less", "suffix:m")
var patrol_origin_x: float = 0.0:
	set(value):
		patrol_origin_x = value
		_apply_patrol_inspector()
@export_range(-80.0, 80.0, 0.1, "or_greater", "or_less", "suffix:m")
var patrol_origin_z: float = 0.0:
	set(value):
		patrol_origin_z = value
		_apply_patrol_inspector()
@export_range(1.0, 80.0, 0.1, "or_greater", "suffix:m") var patrol_width: float = 12.0:
	set(value):
		patrol_width = maxf(value, 1.0)
		if _syncing_patrol:
			return
		if lock_patrol_square:
			_syncing_patrol = true
			patrol_height = patrol_width
			_syncing_patrol = false
		_apply_patrol_inspector()
@export_range(1.0, 80.0, 0.1, "or_greater", "suffix:m") var patrol_height: float = 12.0:
	set(value):
		patrol_height = maxf(value, 1.0)
		if _syncing_patrol:
			return
		if lock_patrol_square:
			_syncing_patrol = true
			patrol_width = patrol_height
			_syncing_patrol = false
		_apply_patrol_inspector()
## Select the PatrolArea node: move XZ, scale X/Z. Independent of spawn.
@export_tool_button("Move Patrol To Spawn", "Callable")
var center_patrol_action := center_patrol_on_spawn

@export_group("Spawn")
## Type instanced by Spawn Monster.
@export_enum("Wretch", "Ash Wretch", "Ember Wretch", "Charger")
var monster_type: int = MONSTER_PICK_WRETCH
## Spawn pad for Spawn Monster.
@export_enum("Northwest", "Northeast", "Southwest", "Southeast", "Center", "Clearing")
var monster_spawn: int = 0:
	set(value):
		monster_spawn = value
		_on_spawn_tweaked()
## Spawn pad for Spawn Player.
@export_enum("Northwest", "Northeast", "Southwest", "Southeast", "Center", "Clearing")
var player_spawn: int = 5:
	set(value):
		player_spawn = value
		_on_spawn_tweaked()
@export_tool_button("Spawn Monster", "Callable")
var spawn_monster_action := spawn_monster
@export_tool_button("Spawn Player", "Callable")
var spawn_player_action := spawn_player
@export_tool_button("Clear Spawned", "Callable")
var clear_spawned_action := clear_spawned
## Orange chase disc + yellow attack disc on spawned monsters.
@export var show_combat_ranges: bool = true
## Cyan hearing, green sight, yellow light, LOS ray from Senses/.
@export var show_sense_ranges: bool = true
## Magenta landing pad + orange range ring + yellow hop arc for Charger knockup.
@export var show_knockup_preview: bool = true

@export_group("Charger Lookdev")
## Last spawned Charger: lock, ward, bow, turn red, then ram if a player is spawned.
@export_tool_button("Preview Telegraph", "Callable")
var preview_charger_telegraph_action := preview_charger_telegraph
## Skip telegraph: locked ram toward the spawned player (or current facing).
@export_tool_button("Preview Charge", "Callable")
var preview_charger_charge_action := preview_charger_charge
## Force wall stun, then frantic search, then patrol if nobody is in sight.
@export_tool_button("Preview Wall Stun", "Callable")
var preview_charger_wall_stun_action := preview_charger_wall_stun
## Frantic look for players, then wander back onto the patrol path.
@export_tool_button("Preview Search", "Callable")
var preview_charger_search_action := preview_charger_search
## Launch the spawned player along the Charger's knockup arc (see KnockupGizmo).
@export_tool_button("Preview Knockup", "Callable")
var preview_charger_knockup_action := preview_charger_knockup

var _spawn_index: int = 0
var _rebuilding: bool = false
var _syncing_patrol: bool = false
var _patrol_ready: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pull_patrol_inspector()
	_patrol_ready = true
	rebuild_arena()
	set_process_unhandled_input(true)


func editor_refresh_environment_preview() -> void:
	rebuild_arena()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() and not _is_playing():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	match key:
		KEY_F1:
			monster_type = MONSTER_PICK_WRETCH
			spawn_monster()
		KEY_F2:
			monster_type = MONSTER_PICK_ASH_WRETCH
			spawn_monster()
		KEY_F3:
			monster_type = MONSTER_PICK_EMBER_WRETCH
			spawn_monster()
		KEY_F4:
			monster_type = MONSTER_PICK_CHARGER
			spawn_monster()
		KEY_F9:
			spawn_player()
		KEY_F10:
			clear_spawned()
		_:
			return
	get_viewport().set_input_as_handled()


func rebuild_arena() -> void:
	if not is_inside_tree() or _rebuilding:
		return
	_rebuilding = true
	_clear_node("SpawnRoot")
	_clear_node("PlayerRoot")
	_spawn_index = 0
	_set_overview_current(true)
	_aim_overview_camera()
	_show_lookdev_gizmos()
	_rebuilding = false


func spawn_monster() -> void:
	var packed := _monster_scene(monster_type)
	if packed == null:
		return
	if packed.resource_path != "":
		packed = load(packed.resource_path) as PackedScene
	var monster: Node = packed.instantiate()
	var spawn := _monster_spawn_point()
	monster.set_meta("lookdev_live_ai", true)
	monster.set_meta("patrol_home", spawn)
	if "lookdev_override" in monster:
		monster.set("lookdev_override", false)
	if "show_combat_ranges" in monster:
		monster.set("show_combat_ranges", show_combat_ranges)
	if "show_sense_ranges" in monster:
		monster.set("show_sense_ranges", show_sense_ranges)
	monster.process_mode = Node.PROCESS_MODE_ALWAYS
	var root := _ensure_bucket("SpawnRoot")
	root.add_child(monster)
	if monster is Node3D:
		(monster as Node3D).global_position = spawn
	_configure_patrol_area(monster, spawn)
	_spawn_index += 1


func spawn_player() -> void:
	clear_player()
	var player := PlayableScene.instantiate() as Node3D
	if player == null:
		push_error("Monster workspace Spawn Player failed to instance playable_character.tscn")
		return
	var playing := _is_playing()
	player.name = "PlayableCharacter"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	var root := _ensure_bucket("PlayerRoot")
	root.add_child(player)
	_prepare_sandbox_player(player, playing)
	var spawn := _pad_point(player_spawn)
	player.global_position = spawn
	var monster := _last_spawned_monster()
	if monster != null:
		_face_toward(player, monster.global_position)
		_face_toward(monster, player.global_position)
	_set_overview_current(not playing)


func preview_charger_telegraph() -> void:
	var charger := _charger_actor()
	if charger == null:
		return
	var player := _last_spawned_player()
	if player != null and charger.has_method("begin_lock_on"):
		charger.call("begin_lock_on", player, false)
	elif charger.has_method("preview_telegraph"):
		charger.call("preview_telegraph")


func preview_charger_charge() -> void:
	var charger := _charger_actor()
	if charger == null or not charger.has_method("begin_charge_now"):
		return
	charger.call("begin_charge_now", false, _last_spawned_player())


func preview_charger_wall_stun() -> void:
	var charger := _charger_actor()
	if charger == null or not charger.has_method("begin_wall_stun_now"):
		return
	charger.call("begin_wall_stun_now")


func preview_charger_search() -> void:
	var charger := _charger_actor()
	if charger == null or not charger.has_method("begin_search_now"):
		return
	charger.call("begin_search_now")


func preview_charger_knockup() -> void:
	var charger := _charger_actor()
	var player := _last_spawned_player()
	if charger == null or player == null:
		return
	if charger.has_method("preview_knockup"):
		charger.call("preview_knockup", player)


func _prepare_sandbox_player(player: Node3D, playing: bool) -> void:
	## Editor does not run PlayableCharacter._ready (script is not @tool).
	if not player.is_in_group("player"):
		player.add_to_group("player")
	if player is CollisionObject3D:
		(player as CollisionObject3D).collision_layer = 1
		(player as CollisionObject3D).collision_mask = 1
	if playing:
		return
	var cam := player.find_child("FirstPersonCamera", true, false) as Camera3D
	if cam != null:
		cam.current = false
	var sync := player.get_node_or_null("MultiplayerSynchronizer")
	if sync != null:
		sync.process_mode = Node.PROCESS_MODE_DISABLED


func clear_spawned() -> void:
	_spawn_index = 0
	_clear_node("SpawnRoot")
	clear_player()


func clear_player() -> void:
	_clear_node("PlayerRoot")
	_set_overview_current(true)


func center_patrol_on_spawn() -> void:
	var area := _patrol_area()
	if area == null or not area.has_method("set_rect"):
		return
	area.call("set_rect", _monster_spawn_point(), _patrol_size())


func on_patrol_area_changed() -> void:
	if not is_inside_tree() or _rebuilding or _syncing_patrol:
		return
	_pull_patrol_inspector()
	_refresh_pathing_overlay()


func _monster_scene(pick: int) -> PackedScene:
	match pick:
		MONSTER_PICK_ASH_WRETCH:
			return AshWretchScene
		MONSTER_PICK_EMBER_WRETCH:
			return EmberWretchScene
		MONSTER_PICK_CHARGER:
			return ChargerScene
		_:
			return WretchScene


func _monster_spawn_point() -> Vector3:
	return _pad_point(monster_spawn)


func _pad_point(pad: int) -> Vector3:
	var home := _patrol_home()
	var size := _patrol_size()
	var hx := size.x * 0.35
	var hz := size.y * 0.35
	var offset := Vector3.ZERO
	match pad:
		PAD_NW:
			offset = Vector3(-hx, 0.0, -hz)
		PAD_NE:
			offset = Vector3(hx, 0.0, -hz)
		PAD_SW:
			offset = Vector3(-hx, 0.0, hz)
		PAD_SE:
			offset = Vector3(hx, 0.0, hz)
		PAD_CENTER, PAD_CLEARING:
			offset = Vector3.ZERO
	return Vector3(home.x + offset.x, 0.05, home.z + offset.z)


func _configure_patrol_area(monster: Node, _spawn: Vector3) -> void:
	var home := _patrol_home()
	var size := _patrol_size()
	if "patrol_radius" in monster:
		monster.set("patrol_radius", maxf(size.x, size.y) * 0.5)
	## Meta works on editor placeholders; do not call monster methods here.
	monster.set_meta("patrol_home", home)
	monster.set_meta("patrol_size", size)
	_refresh_pathing_overlay()


func _last_spawned_monster() -> CharacterBody3D:
	var root := get_node_or_null("SpawnRoot")
	if root == null or root.get_child_count() < 1:
		return null
	var last := root.get_child(root.get_child_count() - 1)
	return last as CharacterBody3D


func _last_spawned_player() -> Node3D:
	var root := get_node_or_null("PlayerRoot")
	if root == null or root.get_child_count() < 1:
		return null
	return root.get_child(root.get_child_count() - 1) as Node3D


func _charger_actor() -> Node:
	var monster := _last_spawned_monster()
	if monster != null and monster.has_method("begin_lock_on"):
		return monster
	return null


func _face_toward(node: Node3D, world_xz: Vector3) -> void:
	var at := Vector3(world_xz.x, node.global_position.y, world_xz.z)
	if node.global_position.distance_squared_to(at) < 0.0001:
		return
	node.look_at(at, Vector3.UP)


func _aim_overview_camera() -> void:
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	var home := _patrol_home()
	var size := _patrol_size()
	var span := maxf(size.x, size.y)
	var dist := maxf(span * 0.9, 12.0)
	cam.position = Vector3(home.x + dist * 0.55, dist * 0.7, home.z + dist)
	var look := Vector3(home.x, 0.4, home.z)
	if cam.global_position.distance_squared_to(look) > 0.0001:
		cam.look_at(look, Vector3.UP)


func _set_overview_current(enabled: bool) -> void:
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.current = enabled


func _show_lookdev_gizmos() -> void:
	var area := _patrol_area()
	if area != null:
		area.visible = true
	_refresh_pathing_overlay()


func _on_spawn_tweaked() -> void:
	if not is_inside_tree():
		return
	_refresh_pathing_overlay()


func _refresh_pathing_overlay() -> void:
	if not is_inside_tree():
		return
	var monster := _last_spawned_monster()
	if monster == null:
		return
	var home := _patrol_home()
	var size := _patrol_size()
	if "patrol_radius" in monster:
		monster.set("patrol_radius", maxf(size.x, size.y) * 0.5)
	monster.set_meta("patrol_home", home)
	monster.set_meta("patrol_size", size)


func _patrol_area() -> Node3D:
	return get_node_or_null("PatrolArea") as Node3D


func _patrol_home() -> Vector3:
	var area := _patrol_area()
	if area != null and area.has_method("rect_home"):
		return area.call("rect_home")
	return Vector3(0.0, 0.04, 0.0)


func _patrol_size() -> Vector2:
	var area := _patrol_area()
	if area != null and area.has_method("rect_size"):
		return area.call("rect_size")
	return Vector2(maxf(patrol_width, 1.0), maxf(patrol_height, 1.0))


func _apply_patrol_inspector() -> void:
	if _syncing_patrol or not _patrol_ready or not is_inside_tree():
		return
	_syncing_patrol = true
	var area := _patrol_area()
	if area != null:
		if "lock_square" in area:
			area.set("lock_square", lock_patrol_square)
		if area.has_method("set_rect"):
			area.call(
				"set_rect",
				Vector3(patrol_origin_x, 0.04, patrol_origin_z),
				Vector2(patrol_width, patrol_height)
			)
	_syncing_patrol = false
	_refresh_pathing_overlay()


func _pull_patrol_inspector() -> void:
	_syncing_patrol = true
	var home := _patrol_home()
	var size := _patrol_size()
	patrol_origin_x = home.x
	patrol_origin_z = home.z
	patrol_width = size.x
	patrol_height = size.y
	var area := _patrol_area()
	if area != null and "lock_square" in area:
		lock_patrol_square = bool(area.get("lock_square"))
	_syncing_patrol = false


func _is_playing() -> bool:
	return not Engine.is_editor_hint() or (
		get_tree() != null and get_tree().edited_scene_root == null
	)


func _ensure_bucket(bucket_name: String) -> Node3D:
	var bucket := get_node_or_null(bucket_name) as Node3D
	if bucket != null:
		return bucket
	bucket = Node3D.new()
	bucket.name = bucket_name
	bucket.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bucket)
	return bucket


func _clear_node(node_name: String) -> void:
	var node := get_node_or_null(node_name)
	if node == null:
		return
	var kids := node.get_children()
	for child in kids:
		node.remove_child(child)
		child.free()
