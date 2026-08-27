extends RefCounted

## Stage-lifetime corpses, no mid-fight respawn, host game-over overlay stats.

const PlayerScene := preload("res://scenes/characters/player.tscn")
const WretchScene := preload("res://scenes/monsters/evaluating/wretch.tscn")
const GameOverOverlayScene := preload("res://scenes/ui/game_over_overlay.tscn")
const ARENA_SCENE_SCRIPT := "res://scripts/arena/arena_scene.gd"


func run() -> int:
	var failures := 0
	failures += _test_player_stays_dead_until_revive()
	failures += _test_rewind_revive_stops_limp()
	failures += _test_game_over_overlay_stats()
	failures += _test_arena_has_no_midfight_respawn()
	failures += _test_arena_game_over_is_host_rpc()
	return failures


func _test_player_stays_dead_until_revive() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var player := PlayerScene.instantiate() as Player
	holder.add_child(player)
	player.kill()
	var stayed := (
		not player.is_alive()
		and player.is_death_physics()
		and is_instance_valid(player)
		and not player.is_queued_for_deletion()
	)
	holder.queue_free()
	if not stayed:
		push_error("Player death must limp in place with no auto-free")
		return 1
	return 0


func _test_rewind_revive_stops_limp() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var player := PlayerScene.instantiate() as Player
	holder.add_child(player)
	player.current_health = 0.0
	if not player.is_death_physics():
		holder.queue_free()
		push_error("HP 0 should start death physics")
		return 1
	player.current_health = player.max_health
	var ok := player.is_alive() and not player.is_death_physics()
	holder.queue_free()
	if not ok:
		push_error("Rewind restoring HP must stop death physics")
		return 1
	return 0


func _test_game_over_overlay_stats() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var overlay := GameOverOverlayScene.instantiate() as CanvasLayer
	holder.add_child(overlay)
	overlay.call("show_run", 2, 14, 5)
	var stages := overlay.get_node("%StagesValue") as Label
	var kills := overlay.get_node("%KillsValue") as Label
	var deaths := overlay.get_node("%DeathsValue") as Label
	var ok := (
		overlay.visible
		and stages != null and stages.text == "2"
		and kills != null and kills.text == "14"
		and deaths != null and deaths.text == "5"
	)
	holder.queue_free()
	if not ok:
		push_error("Game-over overlay should show stages/kills/deaths from the host RPC")
		return 1
	return 0


func _test_arena_has_no_midfight_respawn() -> int:
	var src := FileAccess.get_file_as_string(ARENA_SCENE_SCRIPT)
	if src.contains("RESPAWN_SEC") or src.contains("_respawn_player"):
		push_error("Arena must not revive players on a mid-fight timer")
		return 1
	if not src.contains("rpc_stage_between"):
		push_error("Arena should still revive on rpc_stage_between")
		return 1
	if not src.contains("CORPSE_BEAT_SEC"):
		push_error("Arena must linger after the last kill so corpses can limp")
		return 1
	return 0


func _test_arena_game_over_is_host_rpc() -> int:
	var src := FileAccess.get_file_as_string(ARENA_SCENE_SCRIPT)
	if not src.contains("func rpc_game_over"):
		push_error("Match end must be a host rpc_game_over, not a local died inference")
		return 1
	if src.contains("rpc_player_died"):
		push_error("Do not add a guest death RPC; HP is the death channel")
		return 1
	return 0


func _holder() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		push_error("Expected a SceneTree for arena death tests")
		return null
	var holder := Node.new()
	tree.root.add_child(holder)
	return holder
