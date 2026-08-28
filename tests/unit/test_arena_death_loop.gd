extends RefCounted

## Stage-lifetime corpses, no mid-fight respawn, host game-over overlay stats.

const PlayerScene := preload("res://scenes/characters/player.tscn")
const ChargerScene := preload("res://scenes/monsters/charger.tscn")
const WretchScene := preload("res://scenes/monsters/evaluating/wretch.tscn")
const GameOverOverlayScene := preload("res://scenes/ui/game_over_overlay.tscn")
const ARENA_SCENE_SCRIPT := "res://scripts/arena/arena_scene.gd"


func run() -> int:
	var failures := 0
	failures += _test_player_stays_dead_until_revive()
	failures += _test_rewind_revive_stops_limp()
	failures += _test_game_over_overlay_stats()
	failures += _test_arena_has_no_midfight_respawn()
	failures += _test_pad_rez_stands_the_body()
	failures += _test_arena_game_over_is_host_rpc()
	failures += _test_ghost_leaves_a_shoveable_corpse()
	failures += _test_charger_death_is_same_node()
	failures += _test_quiet_slump_unless_knock()
	failures += _test_killing_knock_lands_on_corpse()
	failures += _test_splash_skips_dead_player()
	failures += _test_monsters_ignore_ghosts()
	failures += _test_ghost_forward_matches_living()
	failures += _test_stage_revive_clears_burn_and_corpse()
	failures += _test_double_ghost_enter_keeps_living_layer()
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
		push_error("Player death must stay in tree with no auto-free")
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
	var revive_at := src.find("func _revive_at")
	if revive_at < 0:
		push_error("Stage clear must revive through _revive_at")
		return 1
	var revive_end := src.find("\nfunc ", revive_at + 1)
	var revive_body := src.substr(revive_at)
	if revive_end > revive_at:
		revive_body = src.substr(revive_at, revive_end - revive_at)
	if not revive_body.contains("queue_pad_rez"):
		push_error("Stage revive must stand up on the movement tick, not in _process")
		return 1
	return 0


func _test_pad_rez_stands_the_body() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var player := PlayerScene.instantiate() as Player
	holder.add_child(player)
	player.kill()
	player.queue_pad_rez(Vector3(4.0, 1.0, 0.0))
	var leftover := _corpse_child(holder)
	var stood := (
		player.is_alive()
		and not player.is_death_physics()
		and player.collision_layer == 1
		and player.global_position.is_equal_approx(Vector3(4.0, 1.0, 0.0))
		and (leftover == null or leftover.is_queued_for_deletion())
	)
	var src := FileAccess.get_file_as_string("res://scripts/characters/player.gd")
	var on_tick := src.contains("_stand_up_at_pad(is_fresh)")
	holder.queue_free()
	if not stood:
		push_error("Pad rez must move the ghost to the pad and stand a living body")
		return 1
	if not on_tick:
		push_error("LAN pad rez must apply on _rollback_tick, not in Arena._process")
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


func _test_ghost_leaves_a_shoveable_corpse() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var player := PlayerScene.instantiate() as Player
	holder.add_child(player)
	player.kill()
	var corpse := _corpse_child(holder)
	var blocked := bool(player.call("_wand_controls_blocked"))
	var ghosted := (
		not player.is_alive()
		and player.collision_layer == 0
		and player.collision_mask == 1
		and not player.is_in_group("combat_target")
		and blocked
		and corpse != null
		and corpse is RigidBody3D
		and corpse.collision_layer == 1
		and corpse.is_in_group(Character.CORPSE_GROUP)
	)
	player.revive()
	var leftover := _corpse_child(holder)
	var cleared := (
		(leftover == null or leftover.is_queued_for_deletion())
		and player.collision_layer == 1
		and player.is_alive()
		and not player.is_death_physics()
	)
	holder.queue_free()
	if not ghosted:
		push_error("Dead player must fly untargetable and leave a shoveable corpse")
		return 1
	if not cleared:
		push_error("Revive must free the corpse and restore the living collision layer")
		return 1
	return 0


func _test_charger_death_is_same_node() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var charger := ChargerScene.instantiate() as Charger
	holder.add_child(charger)
	var id := charger.get_instance_id()
	charger.kill()
	var clone := charger.death_corpse
	var body := charger.get_node_or_null("%Body") as Node3D
	var ok := (
		is_instance_valid(charger)
		and charger.get_instance_id() == id
		and charger.is_death_physics()
		and charger.collision_layer == 0
		and clone != null
		and clone is RigidBody3D
		and clone.collision_layer == 1
		and clone.is_in_group(Character.CORPSE_GROUP)
		and (body == null or not body.visible)
	)
	holder.queue_free()
	if not ok:
		push_error("Dead charger must stay in tree and flop as a RigidBody clone")
		return 1
	return 0


func _test_quiet_slump_unless_knock() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var slump := ChargerScene.instantiate() as Charger
	var knocked := ChargerScene.instantiate() as Charger
	holder.add_child(slump)
	holder.add_child(knocked)
	slump.kill()
	knocked.apply_knockback(Vector3.RIGHT)
	var knock_speed := Vector3(knocked.velocity.x, 0.0, knocked.velocity.z).length()
	knocked.kill()
	var slump_body := slump.death_corpse
	var knocked_body := knocked.death_corpse
	var slump_speed := 0.0
	var death_speed := 0.0
	if slump_body != null:
		slump_speed = Vector3(
			slump_body.linear_velocity.x, 0.0, slump_body.linear_velocity.z
		).length()
	if knocked_body != null:
		death_speed = Vector3(
			knocked_body.linear_velocity.x, 0.0, knocked_body.linear_velocity.z
		).length()
	var ok := (
		slump_body != null
		and knocked_body != null
		and slump_speed < 1.0
		and knock_speed >= Character.KNOCKBACK_HORIZONTAL - 0.05
		and death_speed >= knock_speed - 0.05
		and death_speed <= knock_speed + 0.05
	)
	holder.queue_free()
	if not ok:
		push_error(
			"Damage-only death must slump; knock-active death must keep knock speed"
			+ " (slump=%.2f knock=%.2f death=%.2f)"
			% [slump_speed, knock_speed, death_speed]
		)
		return 1
	return 0


func _test_killing_knock_lands_on_corpse() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var shove := Vector3(4.5, 2.0, 0.0)
	var charger := ChargerScene.instantiate() as Charger
	var player := PlayerScene.instantiate() as Player
	holder.add_child(charger)
	holder.add_child(player)
	var dump_hit := CombatPayload.new()
	dump_hit.effects.append(Damage.with(charger.max_health))
	dump_hit.effects.append(Knock.with(shove))
	charger.apply(null, dump_hit)
	var player_hit := CombatPayload.new()
	player_hit.effects.append(Damage.with(player.max_health))
	player_hit.effects.append(Knock.with(shove))
	player.apply(null, player_hit)
	var clone := _corpse_child(holder)
	var dump_ok := (
		charger.death_corpse != null
		and charger.death_corpse.linear_velocity.is_equal_approx(shove)
	)
	var clone_ok := (
		clone != null
		and clone is RigidBody3D
		and (clone as RigidBody3D).linear_velocity.is_equal_approx(shove)
	)
	holder.queue_free()
	if not dump_ok:
		push_error("Killing knock must replace dump slump (%s)" % charger.death_corpse)
		return 1
	if not clone_ok:
		push_error("Killing knock must land on the player corpse, not the ghost")
		return 1
	return 0


func _test_splash_skips_dead_player() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var tree := holder.get_tree()
	var live := PlayerScene.instantiate() as Player
	var ghost := PlayerScene.instantiate() as Player
	holder.add_child(live)
	holder.add_child(ghost)
	live.global_position = Vector3.ZERO
	ghost.global_position = Vector3(0.2, 0.0, 0.0)
	ghost.kill()
	var live_hp := live.current_health
	var payload := CombatPayload.new()
	payload.effects.append(Damage.with(8.0))
	CombatSplash.apply_at(tree, Vector3.ZERO, 1.0, live, payload)
	var ok := (
		not is_equal_approx(live.current_health, live_hp)
		and is_equal_approx(ghost.current_health, 0.0)
		and ghost.is_death_physics()
	)
	holder.queue_free()
	if not ok:
		push_error("Splash must hit the living caster-skip target and ignore the ghost")
		return 1
	return 0


func _test_monsters_ignore_ghosts() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var charger := ChargerScene.instantiate() as Charger
	var live := PlayerScene.instantiate() as Player
	var ghost := PlayerScene.instantiate() as Player
	holder.add_child(charger)
	holder.add_child(live)
	holder.add_child(ghost)
	## Scene chase_range is 3 m — keep the living player inside it, farther than the ghost.
	charger.chase_range = 8.0
	charger.global_position = Vector3(80.0, 0.0, 80.0)
	ghost.global_position = Vector3(80.4, 0.0, 80.0)
	live.global_position = Vector3(82.5, 0.0, 80.0)
	ghost.kill()
	var sight := MonsterSightSense.new()
	sight.require_line_of_sight = false
	var seen: Array = []
	sight.append_interest_candidates(charger, seen)
	var prefers_living := charger.get_aggro_player_target() == live
	var ram_skips_ghost := (
		not Charger.is_player_charge_target(ghost)
		and Charger.is_player_charge_target(live)
	)
	var sight_hit: MonsterInterest = seen[0] as MonsterInterest if not seen.is_empty() else null
	var sight_skips_ghost := sight_hit != null and sight_hit.target == live and seen.size() == 1
	live.kill()
	var none_when_all_dead := charger.get_aggro_player_target() == null
	holder.queue_free()
	if not prefers_living:
		push_error("Aggro must pick the living player, not the closer ghost")
		return 1
	if not ram_skips_ghost:
		push_error("Ram must skip ghosts even when the ghost is closer")
		return 1
	if not sight_skips_ghost:
		push_error("Sight must skip ghosts even when the ghost is closer")
		return 1
	if not none_when_all_dead:
		push_error("Aggro must be empty when every player is a ghost")
		return 1
	return 0


func _test_ghost_forward_matches_living() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var player := PlayerScene.instantiate() as Player
	holder.add_child(player)
	var net := PlayerNetInput.new()
	net.movement = Vector2(0.0, -1.0)
	var ghost_wish: Vector3 = PlayerGhost._wish_dir(player, net)
	var living := SlideSurface.camera_relative_move_direction(player.head, net)
	var flipped := Vector3(living.x, living.y, -living.z)
	var ok := (
		living.length_squared() > 0.5
		and ghost_wish.dot(living) > 0.9
		and ghost_wish.dot(flipped) < 0.0
	)
	holder.queue_free()
	if not ok:
		push_error("Ghost W must match living camera-forward, not the opposite")
		return 1
	return 0


func _test_stage_revive_clears_burn_and_corpse() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var player := PlayerScene.instantiate() as Player
	holder.add_child(player)
	player.kill()
	player.apply_burn(200.0, 8.0)
	player.global_position = Vector3(8.0, 1.0, 0.0)
	player.revive()
	player.restore_after_revive()
	player.tick_burn(1.0)
	var leftover := _corpse_child(holder)
	var ok := (
		player.is_alive()
		and is_equal_approx(player.current_health, player.max_health)
		and not player.is_death_physics()
		and player.collision_layer == 1
		and (leftover == null or leftover.is_queued_for_deletion())
	)
	holder.queue_free()
	if not ok:
		push_error("Stage revive must stand a full-HP body, not a burned ragdoll")
		return 1
	return 0


func _test_double_ghost_enter_keeps_living_layer() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var player := PlayerScene.instantiate() as Player
	holder.add_child(player)
	player.kill()
	PlayerGhost.enter(player)
	player.revive()
	var ok := player.collision_layer == 1
	holder.queue_free()
	if not ok:
		push_error("A second ghost enter must not restore collision_layer 0 on revive")
		return 1
	return 0


func _corpse_child(holder: Node) -> MonsterCorpse:
	for child in holder.get_children():
		if child is MonsterCorpse:
			return child as MonsterCorpse
	return null


func _holder() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		push_error("Expected a SceneTree for arena death tests")
		return null
	var holder := Node.new()
	tree.root.add_child(holder)
	return holder
