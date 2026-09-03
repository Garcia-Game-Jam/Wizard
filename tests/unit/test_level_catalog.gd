class_name TestLevelCatalog
extends RefCounted

## LevelCatalog (scripts/arena/level_catalog.gd) scans scenes/arenas/levels/
## for LevelDefinition .tres files, and arena_scene.gd resolves fights/cover
## from whichever one GameState.selected_level_id names, falling back to the
## classic ArenaEncounters table when none is selected.

const LevelCatalogScript := preload("res://scripts/arena/level_catalog.gd")
const ArenaSceneScript := preload("res://scripts/arena/arena_scene.gd")

const DEFAULT_LEVEL_ID := "default_level"


func run() -> int:
	var failures := 0
	failures += _test_catalog_finds_default_level()
	failures += _test_settings_manager_resolve()
	failures += _test_arena_scene_falls_back_with_no_level()
	failures += _test_arena_scene_resolves_from_level()
	return failures


func _test_catalog_finds_default_level() -> int:
	var failures := 0
	var ids := LevelCatalogScript.all_ids()
	if not ids.has(DEFAULT_LEVEL_ID):
		push_error("Expected LevelCatalog.all_ids() to include '%s', got %s" % [DEFAULT_LEVEL_ID, ids])
		failures += 1
	if LevelCatalogScript.default_id() != DEFAULT_LEVEL_ID:
		push_error("Expected LevelCatalog.default_id() == '%s'" % DEFAULT_LEVEL_ID)
		failures += 1
	if not LevelCatalogScript.is_known_id(DEFAULT_LEVEL_ID):
		push_error("Expected '%s' to be a known id" % DEFAULT_LEVEL_ID)
		failures += 1
	if LevelCatalogScript.is_known_id("not_a_real_level_xyz"):
		push_error("Expected an unregistered id to not be known")
		failures += 1
	var level: Resource = LevelCatalogScript.load_level(DEFAULT_LEVEL_ID)
	if level == null:
		push_error("Expected default_level to load")
		return failures + 1
	if str(level.get("map_id")).is_empty():
		push_error("Expected default_level to have a non-empty map_id")
		failures += 1
	var encounters: Array = level.get("encounters")
	if encounters.is_empty():
		push_error("Expected default_level to have at least one encounter")
		failures += 1
	return failures


func _test_settings_manager_resolve() -> int:
	var failures := 0
	var settings: Node = Engine.get_main_loop().root.get_node("/root/SettingsManager")
	var prior_random: bool = settings.dev_random_level
	var prior_selected: String = settings.dev_selected_level_id

	settings.dev_random_level = false
	settings.dev_selected_level_id = "not_a_real_level_xyz"
	if not LevelCatalogScript.is_known_id(settings.resolve_match_level_id()):
		push_error("Expected resolve_match_level_id() to fall back to a known id when pinned id is bogus")
		failures += 1

	settings.dev_selected_level_id = DEFAULT_LEVEL_ID
	if settings.resolve_match_level_id() != DEFAULT_LEVEL_ID:
		push_error("Expected resolve_match_level_id() to honor a valid pinned id")
		failures += 1

	settings.dev_random_level = prior_random
	settings.dev_selected_level_id = prior_selected
	return failures


func _test_arena_scene_falls_back_with_no_level() -> int:
	var failures := 0
	var game_state: Node = Engine.get_main_loop().root.get_node("/root/GameState")
	var prior_level_id: String = game_state.selected_level_id
	game_state.selected_level_id = ""

	var node := Node3D.new()
	node.set_script(ArenaSceneScript)
	if node.call("_active_level") != null:
		push_error("Expected _active_level() to be null with no selected_level_id")
		failures += 1
	var dump: Array = node.call("_resolve_dump", 0)
	if dump.size() != 1 or (dump[0] as Dictionary).has("position"):
		push_error(
			"Expected _resolve_dump(0) with no level to return the classic pad-based dict, got %s" % dump
		)
		failures += 1
	var cover: Array = node.call("_resolve_cover_positions", 0)
	if cover.size() != 3:
		push_error(
			"Expected _resolve_cover_positions(0) with no level to return the classic 3-entry table, got %d"
			% cover.size()
		)
		failures += 1
	node.free()

	game_state.selected_level_id = prior_level_id
	return failures


func _test_arena_scene_resolves_from_level() -> int:
	var failures := 0
	var game_state: Node = Engine.get_main_loop().root.get_node("/root/GameState")
	var prior_level_id: String = game_state.selected_level_id
	game_state.selected_level_id = DEFAULT_LEVEL_ID

	## _active_level() caches for a node's lifetime (matches real play — set
	## once per match, never changes), so this needs its own fresh node
	## rather than reusing the one from the no-level scenario above.
	var node := Node3D.new()
	node.set_script(ArenaSceneScript)

	var level: Resource = LevelCatalogScript.load_level(DEFAULT_LEVEL_ID)
	var expected_encounters: Array = level.get("encounters")
	var expected0: Resource = expected_encounters[0]
	var expected0_monster: Resource = (expected0.get("monsters") as Array)[0]

	var dump: Array = node.call("_resolve_dump", 0)
	if dump.size() != (expected0.get("monsters") as Array).size():
		push_error(
			"Expected level-driven _resolve_dump(0) to match default_level's encounter 0 monster count, got %d vs %d"
			% [dump.size(), (expected0.get("monsters") as Array).size()]
		)
		failures += 1
	elif dump.size() > 0:
		var m: Dictionary = dump[0]
		if str(m.get("kind")) != str(expected0_monster.get("kind")):
			push_error("Expected level-driven dump kind to match the resource, got '%s'" % m.get("kind"))
			failures += 1
		if not (m.get("position") as Vector3).is_equal_approx(expected0_monster.get("position")):
			push_error("Expected level-driven dump position to match the resource")
			failures += 1

	var cover: Array = node.call("_resolve_cover_positions", 0)
	var expected_obstacles: Array = expected0.get("obstacle_positions")
	if cover.size() != expected_obstacles.size():
		push_error(
			"Expected level-driven cover count to match encounter 0's obstacle_positions, got %d vs %d"
			% [cover.size(), expected_obstacles.size()]
		)
		failures += 1

	## Looping: encounter_count (mod back to 0) must match encounter 0 again.
	var looped_dump: Array = node.call("_resolve_dump", expected_encounters.size())
	if looped_dump.size() != dump.size():
		push_error("Expected the encounter sequence to loop back to encounter 0 once exhausted")
		failures += 1

	node.free()
	game_state.selected_level_id = prior_level_id
	return failures
