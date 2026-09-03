class_name TestEncounterDesignWorkshop
extends RefCounted

## The @tool encounter design workshop (scenes/arenas/encounter_design_workshop.tscn):
## loads the default level, previews the selected encounter's monsters/
## obstacles as markers against the real map geometry, and its add/delete/
## sync actions mutate the underlying LevelDefinition correctly.

const WorkshopScene := preload("res://scenes/arenas/encounter_design_workshop.tscn")
const WorkshopScript := preload("res://scripts/arena/encounter_design_workshop.gd")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_loads_default_level(tree)
	failures += _test_add_delete_actions(tree)
	failures += _test_player_spawn_scaffolding_is_noop_when_present(tree)
	return failures


func _test_loads_default_level(tree: SceneTree) -> int:
	var failures := 0
	var workshop := WorkshopScene.instantiate()
	tree.root.add_child(workshop)

	var level: Resource = workshop.get("level")
	if level == null:
		push_error("Expected default_level.tres to load into `level`")
		workshop.free()
		return failures + 1

	if str(level.get("map_id")) != "pit":
		push_error("Expected default level map_id='pit', got '%s'" % level.get("map_id"))
		failures += 1

	var encounters: Array = level.get("encounters")
	if encounters.size() != 6:
		push_error("Expected 6 encounters in the default level, got %d" % encounters.size())
		failures += 1

	var map_preview := workshop.get_node_or_null("MapPreview")
	if map_preview == null or map_preview.get_child_count() == 0:
		push_error("Expected MapPreview to hold an instantiated pit arena")
		failures += 1

	## Encounter 0 is a single charger at Pad0 = (-14, 0.05, -10).
	var marker_root := workshop.get_node_or_null("EncounterPreview")
	var monster0 := marker_root.get_node_or_null("Monster0") as Node3D if marker_root != null else null
	if monster0 == null:
		push_error("Expected a Monster0 preview marker for encounter 0")
		failures += 1
	elif not monster0.position.is_equal_approx(Vector3(-14.0, 0.05, -10.0)):
		push_error("Expected Monster0 marker at Pad0 position, got %s" % monster0.position)
		failures += 1

	workshop.free()
	return failures


func _test_add_delete_actions(tree: SceneTree) -> int:
	var failures := 0
	var workshop := WorkshopScene.instantiate()
	tree.root.add_child(workshop)

	var level: Resource = workshop.get("level")
	var starting_count: int = (level.get("encounters") as Array).size()

	workshop.call("_action_add_encounter")
	var encounters_after_add: Array = level.get("encounters")
	if encounters_after_add.size() != starting_count + 1:
		push_error(
			"Expected encounter count to grow by 1 after Add Encounter, got %d -> %d"
			% [starting_count, encounters_after_add.size()]
		)
		failures += 1
	if int(workshop.get("selected_encounter_index")) != encounters_after_add.size() - 1:
		push_error("Expected Add Encounter to select the newly added encounter")
		failures += 1

	workshop.call("_action_add_monster")
	workshop.call("_action_add_obstacle")
	var new_enc: Resource = encounters_after_add[encounters_after_add.size() - 1]
	var monsters: Array = new_enc.get("monsters")
	var obstacles: Array = new_enc.get("obstacle_positions")
	if monsters.size() != 1:
		push_error("Expected 1 monster after Add Monster, got %d" % monsters.size())
		failures += 1
	if obstacles.size() != 1:
		push_error("Expected 1 obstacle after Add Obstacle, got %d" % obstacles.size())
		failures += 1

	var marker_root := workshop.get_node_or_null("EncounterPreview")
	var moved_marker := marker_root.get_node_or_null("Monster0") as Node3D if marker_root != null else null
	if moved_marker == null:
		push_error("Expected a Monster0 marker for the newly added monster")
		failures += 1
	else:
		moved_marker.position = Vector3(3.0, 4.0, 5.0)
		workshop.call("_sync_positions_from_markers")
		var synced_pos: Vector3 = (monsters[0] as Resource).get("position")
		if not synced_pos.is_equal_approx(Vector3(3.0, 4.0, 5.0)):
			push_error(
				"Expected Sync Positions From Markers to write the moved position back, got %s"
				% synced_pos
			)
			failures += 1

	workshop.call("_action_delete_selected_encounter")
	var encounters_after_delete: Array = level.get("encounters")
	if encounters_after_delete.size() != starting_count:
		push_error(
			"Expected encounter count back to %d after delete, got %d"
			% [starting_count, encounters_after_delete.size()]
		)
		failures += 1

	workshop.free()
	return failures


## Both registered maps already have PlayerSpawn_0..3 — running the
## first-encounter scaffolding pass must be a silent no-op, not rewrite
## either scene file.
func _test_player_spawn_scaffolding_is_noop_when_present(tree: SceneTree) -> int:
	var failures := 0
	var workshop := Node3D.new()
	workshop.set_script(WorkshopScript)
	tree.root.add_child(workshop)

	var arena_path := ProjectSettings.globalize_path("res://scenes/arena.tscn")
	var colosseum_path := ProjectSettings.globalize_path("res://scenes/arenas/arena_bulls.tscn")
	var arena_mtime_before := FileAccess.get_modified_time(arena_path)
	var colosseum_mtime_before := FileAccess.get_modified_time(colosseum_path)

	workshop.call("_ensure_player_spawns_for_all_maps")

	if FileAccess.get_modified_time(arena_path) != arena_mtime_before:
		push_error("Expected arena.tscn to be untouched (already has PlayerSpawn_0..3)")
		failures += 1
	if FileAccess.get_modified_time(colosseum_path) != colosseum_mtime_before:
		push_error("Expected arena_bulls.tscn to be untouched (already has PlayerSpawn_0..3)")
		failures += 1

	workshop.free()
	return failures
