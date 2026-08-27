class_name TestGameState
extends RefCounted

const GameStateScript := preload("res://scripts/game_state.gd")
const PlayerCharacterConfigScript := preload("res://scripts/match/player_character_config.gd")


func run() -> int:
	var failures := 0
	failures += _test_reset_for_new_game()
	failures += _test_prepare_match()
	failures += _test_get_team_for_peer()
	failures += _test_get_player_color_wraps()
	return failures


func _make_state() -> GameStateScript:
	return GameStateScript.new()


func _test_reset_for_new_game() -> int:
	var state := _make_state()
	state.is_multiplayer = true
	state.run_seed = 42

	state.reset_for_new_game()

	if state.is_multiplayer:
		push_error("Expected solo reset to clear is_multiplayer")
		return 1
	if state.run_seed < 0:
		push_error("Expected solo reset to assign a run seed")
		return 1
	return 0


func _test_prepare_match() -> int:
	var state := _make_state()
	state.reset_for_new_game()

	var roles := {
		1: GameStateScript.PlayerRole.APPRENTICE,
		2: GameStateScript.PlayerRole.APPRENTICE,
		3: GameStateScript.PlayerRole.APPRENTICE,
	}
	var config_dict := PlayerCharacterConfigScript.create_default(
		GameStateScript.PlayerRole.APPRENTICE
	).to_dict()
	state.prepare_match(12345, roles, {1: config_dict})

	if not state.is_multiplayer:
		push_error("Expected prepare_match to enable multiplayer")
		return 1
	if state.run_seed != 12345:
		push_error("Expected prepare_match to set run_seed")
		return 1
	if state.get_role_for_peer(1) != GameStateScript.PlayerRole.APPRENTICE:
		push_error("Expected peer 1 to be Apprentice")
		return 1
	var restored := state.get_character_config_for_peer(1)
	if restored.role != GameStateScript.PlayerRole.APPRENTICE:
		push_error("Expected prepare_match to store character configs")
		return 1
	return 0


func _test_get_team_for_peer() -> int:
	var state := _make_state()
	var apprentice_config := PlayerCharacterConfigScript.create_default(
		GameStateScript.PlayerRole.APPRENTICE
	)
	apprentice_config.team_id = 1
	state.prepare_match(
		99,
		{
			1: GameStateScript.PlayerRole.APPRENTICE,
			2: GameStateScript.PlayerRole.APPRENTICE,
			3: GameStateScript.PlayerRole.APPRENTICE,
		},
		{
			2: apprentice_config.to_dict(),
		}
	)
	if state.get_team_for_peer(1) != 0:
		push_error("Expected default apprentice team_id to be 0")
		return 1
	if state.get_team_for_peer(2) != 1:
		push_error("Expected apprentice team_id from character config")
		return 1
	if state.get_team_for_peer(3) != 0:
		push_error("Expected default apprentice team_id to be 0")
		return 1
	return 0


func _test_get_player_color_wraps() -> int:
	var state := _make_state()
	var first := state.get_player_color(0)
	var wrapped := state.get_player_color(GameStateScript.PLAYER_COLORS.size())
	if first != wrapped:
		push_error("Expected player color palette to wrap by player index")
		return 1
	return 0
