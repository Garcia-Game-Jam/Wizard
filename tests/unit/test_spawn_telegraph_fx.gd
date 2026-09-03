class_name TestSpawnTelegraphFx
extends RefCounted

## The position-based "yellow light" spawn telegraph (spawn_telegraph_fx.gd)
## that arena_scene.gd plays per-monster for level-driven encounters, since
## the pad-indexed SpotN/OmniN/BeamN/RingN cluster has no pad to key off of
## for a free-placed spawn (see docs/design/arena.md).

const SpawnTelegraphFxScript := preload("res://scripts/arena/spawn_telegraph_fx.gd")
const ArenaSceneScript := preload("res://scripts/arena/arena_scene.gd")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += await _test_fx_fades_in(tree)
	failures += _test_monster_entry_spawn_animation()
	failures += await _test_arena_scene_plays_fx_per_monster(tree)
	return failures


func _test_fx_fades_in(tree: SceneTree) -> int:
	var failures := 0
	var fx: Node3D = SpawnTelegraphFxScript.new()
	fx.fade_sec = 0.2
	tree.root.add_child(fx)
	## _ready() (which builds Spot/Omni/Beam/Ring) runs synchronously inside
	## add_child() — no frame needs to elapse to reach it. Stop automatic
	## _process() immediately so the engine's own real, uncontrolled frame
	## delta can't tick the fade before this test drives it manually with
	## exact values; awaiting a frame here caused a flaky failure deep into
	## a full suite run where real elapsed time was no longer near-zero.
	fx.set_process(false)

	var spot := fx.get_child(0) as SpotLight3D
	var omni := fx.get_child(1) as OmniLight3D
	var beam := fx.get_child(2) as MeshInstance3D
	var ring := fx.get_child(3) as MeshInstance3D
	if spot == null or omni == null or beam == null or ring == null:
		push_error("Expected SpawnTelegraphFx to build Spot/Omni/Beam/Ring children")
		fx.free()
		return failures + 1

	if spot.light_energy != 0.0:
		push_error("Expected spot energy to start at 0, got %f" % spot.light_energy)
		failures += 1

	fx.call("_process", 0.1)
	if spot.light_energy <= 0.0 or spot.light_energy >= SpawnTelegraphFxScript.ENERGY_SPOT:
		push_error("Expected partial fade-in energy mid-way through fade_sec, got %f" % spot.light_energy)
		failures += 1

	fx.call("_process", 0.2)
	if not is_equal_approx(spot.light_energy, SpawnTelegraphFxScript.ENERGY_SPOT):
		push_error("Expected full spot energy once fade_sec has elapsed, got %f" % spot.light_energy)
		failures += 1
	if not is_equal_approx(omni.light_energy, SpawnTelegraphFxScript.ENERGY_OMNI):
		push_error("Expected full omni energy once fade_sec has elapsed, got %f" % omni.light_energy)
		failures += 1

	fx.free()
	return failures


func _test_monster_entry_spawn_animation() -> int:
	var failures := 0
	var script := load("res://scripts/arena/monster_spawn_entry.gd")
	var entry: Resource = script.new()
	if entry.get("spawn_animation") != "classic_beam":
		push_error(
			"Expected default spawn_animation='classic_beam', got '%s'" % entry.get("spawn_animation")
		)
		failures += 1
	entry.set("spawn_animation", "Classic Beam:classic_beam")
	if entry.get("spawn_animation") != "classic_beam":
		push_error(
			"Expected a leaked 'Label:value' enum hint to sanitize to 'classic_beam', got '%s'"
			% entry.get("spawn_animation")
		)
		failures += 1
	return failures


func _test_arena_scene_plays_fx_per_monster(tree: SceneTree) -> int:
	var failures := 0
	var game_state := tree.root.get_node("/root/GameState")
	var prior_level_id: String = game_state.selected_level_id
	game_state.selected_level_id = "default_level"

	## Needs to be genuinely inside the tree (SpawnTelegraphFx positioning
	## requires it), but arena_scene.gd's real _ready() needs a full match
	## world (Players/Monsters/Cover/... all present) that this bare node
	## doesn't have — enter the tree BEFORE attaching the script so _ready()
	## never fires for it (that notification only ever goes out once, right
	## when a node enters the tree).
	var node := Node3D.new()
	tree.root.add_child(node)
	node.set_script(ArenaSceneScript)

	node.call("rpc_show_telegraph", 0)
	var fx_root := node.get_node_or_null("LevelTelegraphFx")
	if fx_root == null or fx_root.get_child_count() != 1:
		push_error(
			(
				"Expected LevelTelegraphFx to hold 1 FX for default_level's "
				+ "encounter 0 (1 monster), got count=%d"
			) % (fx_root.get_child_count() if fx_root != null else -1)
		)
		failures += 1
	else:
		var fx := fx_root.get_child(0) as Node3D
		if not fx.global_position.is_equal_approx(Vector3(-14.0, 0.05, -10.0)):
			push_error("Expected the FX at encounter 0's monster position, got %s" % fx.global_position)
			failures += 1

	node.call("_clear_level_telegraph_fx")
	await tree.process_frame
	if fx_root.get_child_count() != 0:
		push_error(
			"Expected _clear_level_telegraph_fx() to remove all FX, got %d left"
			% fx_root.get_child_count()
		)
		failures += 1

	node.free()
	game_state.selected_level_id = prior_level_id
	return failures
