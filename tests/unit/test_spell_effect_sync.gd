class_name TestSpellEffectSync
extends RefCounted

const SyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")
const FireballSpell := preload("res://scenes/spells/fireball/fireball.tres")
const HasteSpell := preload("res://scenes/spells/evaluating/haste/haste.tres")
const LightSpell := preload("res://scenes/spells/evaluating/light/light.tres")
const LightBallSpell := preload("res://scenes/spells/evaluating/light_ball/light_ball.tres")
const TargetSpell := preload("res://scenes/spells/evaluating/target/target.tres")
const PullSpell := preload("res://scenes/spells/evaluating/pull/pull.tres")
const FollowSpell := preload("res://scenes/spells/evaluating/follow/follow.tres")
const StopSpell := preload("res://scenes/spells/evaluating/stop/stop.tres")
const DispellSpell := preload("res://scenes/spells/evaluating/dispell/dispell.tres")
const CloneSpell := preload("res://scenes/spells/evaluating/clone/clone.tres")
const FlareSpell := preload("res://scenes/spells/evaluating/flare/flare.tres")
const WardSpell := preload("res://scenes/spells/ward/ward.tres")


func run() -> int:
	var failures := 0
	failures += _test_all_spells_are_supported()
	failures += _test_build_fireball_params()
	failures += _test_build_haste_params()
	failures += _test_unsupported_spell_returns_empty_params()
	failures += _test_apply_haste_from_wire_params()
	failures += _test_fireball_params_spawn_projectile()
	failures += _test_fireball_network_round_trip()
	failures += _test_fireball_wire_params_spawn_projectile()
	failures += _test_apply_flashlight_toggle()
	failures += _test_build_light_ball_params()
	failures += _test_build_target_params()
	failures += _test_build_pull_follow_dispell_params()
	failures += _test_build_stop_params()
	failures += _test_dispell_wire_preserves_light_ball_id()
	failures += _test_light_ball_network_round_trip()
	failures += _test_clone_requires_target_highlight()
	failures += _test_clone_network_round_trip()
	failures += _test_clone_source_eligibility_meta()
	failures += _test_flare_is_supported()
	failures += _test_flare_params_spawn_projectile()
	failures += _test_flare_wire_params_spawn_projectile()
	failures += _test_build_ward_params()
	return failures


func _scene_root() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


func _make_world_root() -> Node3D:
	## Attach under the live engine tree so Node3D global transforms work.
	var root := Node3D.new()
	var tree_root := _scene_root()
	if tree_root != null:
		tree_root.add_child(root)
	return root


func _free_world_root(root: Node) -> void:
	if root == null:
		return
	if root.get_parent() != null:
		root.get_parent().remove_child(root)
	root.free()


func _make_tracking_player() -> _EffectTrackingPlayer:
	var player := _EffectTrackingPlayer.new()
	var head := Node3D.new()
	head.name = "Head"
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	head.add_child(pivot)
	player.add_child(head)
	player.position = Vector3(1.0, 2.0, 3.0)
	pivot.position = Vector3(0.0, 0.5, 1.0)
	return player


func _test_unsupported_spell_returns_empty_params() -> int:
	var player := _make_player_stub()
	var unknown := SpellDefinition.new()
	unknown.id = "debug"
	unknown.effect_id = "teleport"
	var params := SyncScript.build_params(unknown, player)
	player.queue_free()
	if not params.is_empty():
		push_error("Expected unsupported spell to produce empty sync params")
		return 1
	return 0


func _test_apply_haste_from_wire_params() -> int:
	var player := _make_tracking_player()
	var params := {
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_HASTE,
		SyncScript.KEY_DURATION: 5.0,
		SyncScript.KEY_MULTIPLIER: 1.8,
	}
	SyncScript.apply(player, params)
	player.queue_free()
	if player.speed_boost_calls.size() != 1:
		push_error("Expected synced haste params to apply speed boost")
		return 1
	return 0


func _make_player_stub() -> CharacterBody3D:
	return _make_tracking_player()


func _test_all_spells_are_supported() -> int:
	for spell in [
		FireballSpell,
		HasteSpell,
		LightSpell,
		LightBallSpell,
		TargetSpell,
		PullSpell,
		FollowSpell,
		StopSpell,
		DispellSpell,
		CloneSpell,
		FlareSpell,
		WardSpell,
	]:
		if not SyncScript.is_supported_effect(spell.effect_id):
			push_error("Expected effect '%s' to be supported for sync" % spell.effect_id)
			return 1
	return 0


func _test_build_fireball_params() -> int:
	var root := _make_world_root()
	var player := _make_player_stub()
	root.add_child(player)
	var params := SyncScript.build_params(FireballSpell, player)
	_free_world_root(root)
	if str(params.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_FIREBALL:
		push_error("Expected fireball effect id in params")
		return 1
	if not params.has(SyncScript.KEY_ORIGIN) or not params.has(SyncScript.KEY_DIRECTION):
		push_error("Expected fireball origin and direction in params")
		return 1
	return 0


func _test_build_haste_params() -> int:
	var player := _make_player_stub()
	var params := SyncScript.build_params(HasteSpell, player)
	player.queue_free()
	if str(params.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_HASTE:
		push_error("Expected haste effect id in params")
		return 1
	if float(params.get(SyncScript.KEY_DURATION, 0.0)) <= 0.0:
		push_error("Expected haste duration in params")
		return 1
	if SyncScript.get_effect_duration_sec(HasteSpell, params) != 0.0:
		push_error("Expected haste to hide HUD active timer")
		return 1
	return 0


func _test_fireball_params_spawn_projectile() -> int:
	var root := _make_world_root()
	var player := _make_player_stub()
	root.add_child(player)

	var params := {
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_FIREBALL,
		SyncScript.KEY_ORIGIN: Vector3(1.0, 2.0, 3.0),
		SyncScript.KEY_DIRECTION: Vector3(0.0, 0.0, -1.0),
	}
	SyncScript.apply(player, params)

	var projectile_count := _count_fireball_projectiles(root)
	_free_world_root(root)

	if projectile_count != 1:
		push_error("Expected synced fireball params to spawn one projectile")
		return 1
	return 0


func _count_fireball_projectiles(root: Node) -> int:
	var count := 0
	var bucket := root.get_node_or_null("SpellProjectiles")
	var nodes: Array[Node] = [root]
	if bucket != null:
		nodes.append(bucket)
	for node in nodes:
		for child in node.get_children():
			if child.get_script() == FireballProjectileScript:
				count += 1
	return count


func _test_fireball_network_round_trip() -> int:
	var params := {
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_FIREBALL,
		SyncScript.KEY_ORIGIN: Vector3(1.0, 2.0, 3.0),
		SyncScript.KEY_DIRECTION: Vector3(0.0, 0.5, -1.0),
	}
	var wire := SyncScript.pack_for_network(params)
	var restored := SyncScript.unpack_from_network(wire)
	var origin: Vector3 = restored.get(SyncScript.KEY_ORIGIN, Vector3.ZERO)
	var direction: Vector3 = restored.get(SyncScript.KEY_DIRECTION, Vector3.ZERO)
	if not origin.is_equal_approx(Vector3(1.0, 2.0, 3.0)):
		push_error("Expected fireball origin to round-trip through network params")
		return 1
	if not direction.is_equal_approx(Vector3(0.0, 0.5, -1.0).normalized()):
		push_error("Expected fireball direction to round-trip through network params")
		return 1
	return 0


func _test_fireball_wire_params_spawn_projectile() -> int:
	var root := _make_world_root()
	var player := _make_player_stub()
	root.add_child(player)

	var wire := SyncScript.pack_for_network({
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_FIREBALL,
		SyncScript.KEY_ORIGIN: Vector3(4.0, 5.0, 6.0),
		SyncScript.KEY_DIRECTION: Vector3(1.0, 0.0, 0.0),
	})
	SyncScript.apply(player, SyncScript.resolve_network_params(FireballSpell, player, wire))

	var projectile_count := _count_fireball_projectiles(root)
	_free_world_root(root)

	if projectile_count != 1:
		push_error("Expected wire-format fireball params to spawn one projectile")
		return 1
	return 0


func _test_apply_flashlight_toggle() -> int:
	var player := _make_tracking_player()
	SyncScript.apply(player, {SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_FLASHLIGHT_TOGGLE})
	if player.toggle_calls != 1 or not player.flashlight_on:
		player.queue_free()
		push_error("Expected flashlight_toggle to turn wand beam on")
		return 1
	SyncScript.apply(player, {SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_FLASHLIGHT_TOGGLE})
	if player.toggle_calls != 2 or player.flashlight_on:
		player.queue_free()
		push_error("Expected second flashlight_toggle to turn wand beam off")
		return 1
	var params := SyncScript.build_params(LightSpell, player)
	player.queue_free()
	if str(params.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_FLASHLIGHT_TOGGLE:
		push_error("Expected light to build flashlight_toggle params")
		return 1
	return 0


func _test_build_light_ball_params() -> int:
	var player := _make_player_stub()
	var params := SyncScript.build_params(LightBallSpell, player)
	player.queue_free()
	if str(params.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_LIGHT_BALL:
		push_error("Expected light_ball effect id in params")
		return 1
	if not params.has(SyncScript.KEY_ORIGIN):
		push_error("Expected light_ball origin in params")
		return 1
	if not params.has(SyncScript.KEY_WAND_ORIGIN):
		push_error("Expected light_ball wand_origin in params")
		return 1
	if float(params.get(SyncScript.KEY_DURATION, 0.0)) != SyncScript.DEFAULT_LIGHT_BALL_DURATION:
		push_error("Expected light_ball duration to be 30 seconds")
		return 1
	return 0


func _test_build_target_params() -> int:
	var player := _make_player_stub()
	var params := SyncScript.build_params(TargetSpell, player)
	player.queue_free()
	if str(params.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_TARGET:
		push_error("Expected target effect id in params")
		return 1
	if float(params.get(SyncScript.KEY_DURATION, 0.0)) != SyncScript.DEFAULT_TARGET_DURATION:
		push_error("Expected target duration to match DEFAULT_TARGET_DURATION")
		return 1
	if SyncScript.get_effect_duration_sec(TargetSpell, params) != 0.0:
		push_error("Expected target to hide HUD active timer")
		return 1
	return 0


func _test_build_pull_follow_dispell_params() -> int:
	var player := _make_player_stub()
	var pull_params := SyncScript.build_params(PullSpell, player)
	var follow_params := SyncScript.build_params(FollowSpell, player)
	var dispell_params := SyncScript.build_params(DispellSpell, player)
	player.queue_free()
	var ok := (
		str(pull_params.get(SyncScript.KEY_EFFECT_ID, "")) == SyncScript.EFFECT_PULL
		and str(follow_params.get(SyncScript.KEY_EFFECT_ID, "")) == SyncScript.EFFECT_FOLLOW
		and str(dispell_params.get(SyncScript.KEY_EFFECT_ID, "")) == SyncScript.EFFECT_DISPELL
		and SyncScript.get_effect_duration_sec(PullSpell, pull_params) == 0.0
		and SyncScript.get_effect_duration_sec(FollowSpell, follow_params) == 0.0
		and SyncScript.get_effect_duration_sec(DispellSpell, dispell_params) == 0.0
	)
	if not ok:
		push_error("Expected pull/follow/dispell params and zero HUD durations")
		return 1
	var pull_wire := SyncScript.pack_for_network(pull_params)
	var unpacked := SyncScript.unpack_from_network(pull_wire)
	if str(unpacked.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_PULL:
		push_error("Expected pull network round-trip to keep effect id")
		return 1
	return 0


func _test_build_stop_params() -> int:
	var player := _make_player_stub()
	var stop_params := SyncScript.build_params(StopSpell, player)
	player.queue_free()
	if str(stop_params.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_STOP:
		push_error("Expected stop params to carry effect id")
		return 1
	if SyncScript.get_effect_duration_sec(StopSpell, stop_params) != 0.0:
		push_error("Expected stop to hide HUD active timer")
		return 1
	var wire := SyncScript.pack_for_network(stop_params)
	var unpacked := SyncScript.unpack_from_network(wire)
	if str(unpacked.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_STOP:
		push_error("Expected stop network round-trip to keep effect id")
		return 1
	return 0


func _test_dispell_wire_preserves_light_ball_id() -> int:
	var local := {
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_DISPELL,
		SyncScript.KEY_TARGET_KIND: "light_ball",
		SyncScript.KEY_ORIGIN: Vector3(2.0, 1.5, 4.0),
		SyncScript.KEY_SPAWN_ID: "1_99",
	}
	var wire := SyncScript.pack_for_network(local)
	var unpacked := SyncScript.unpack_from_network(wire)
	var ok := (
		str(unpacked.get(SyncScript.KEY_EFFECT_ID, "")) == SyncScript.EFFECT_DISPELL
		and str(unpacked.get(SyncScript.KEY_TARGET_KIND, "")) == "light_ball"
		and str(unpacked.get(SyncScript.KEY_SPAWN_ID, "")) == "1_99"
	)
	if not ok:
		push_error("Expected dispell wire to preserve light ball spawn id")
		return 1
	return 0


func _test_light_ball_network_round_trip() -> int:
	var local := {
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_LIGHT_BALL,
		SyncScript.KEY_ORIGIN: Vector3(1.0, 1.5, 2.0),
		SyncScript.KEY_WAND_ORIGIN: Vector3(0.5, 1.4, 1.0),
		SyncScript.KEY_DURATION: SyncScript.DEFAULT_LIGHT_BALL_DURATION,
		SyncScript.KEY_SPAWN_ID: "42_99",
	}
	var wire := SyncScript.pack_for_network(local)
	var unpacked := SyncScript.unpack_from_network(wire)
	var ok := (
		str(unpacked.get(SyncScript.KEY_EFFECT_ID, "")) == SyncScript.EFFECT_LIGHT_BALL
		and str(unpacked.get(SyncScript.KEY_SPAWN_ID, "")) == "42_99"
		and SyncScript.coerce_vector3(unpacked.get(SyncScript.KEY_ORIGIN, Vector3.ZERO)).is_equal_approx(
			Vector3(1.0, 1.5, 2.0)
		)
	)
	if not ok:
		push_error("Expected light_ball network round-trip to preserve spawn_id/origin")
		return 1
	var dispell_local := {
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_DISPELL,
		SyncScript.KEY_TARGET_KIND: "light_ball",
		SyncScript.KEY_ORIGIN: Vector3(1.0, 1.5, 2.0),
		SyncScript.KEY_SPAWN_ID: "42_99",
	}
	var dispell_wire := SyncScript.pack_for_network(dispell_local)
	var dispell_unpacked := SyncScript.unpack_from_network(dispell_wire)
	if str(dispell_unpacked.get(SyncScript.KEY_SPAWN_ID, "")) != "42_99":
		push_error("Expected dispell wire to preserve light ball spawn_id")
		return 1
	return 0


func _test_clone_requires_target_highlight() -> int:
	var player := _make_player_stub()
	var params := SyncScript.build_params(CloneSpell, player)
	player.queue_free()
	if not params.is_empty():
		push_error("Expected clone without Target outline to produce empty params")
		return 1
	if SyncScript.get_effect_duration_sec(CloneSpell, {}) != 0.0:
		push_error("Expected clone to hide HUD active timer")
		return 1
	return 0


func _test_clone_network_round_trip() -> int:
	var local := {
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_CLONE,
		SyncScript.KEY_TARGET_KIND: "relic_clone",
		SyncScript.KEY_ORIGIN: Vector3(5.0, 1.1, -2.0),
		SyncScript.KEY_SPAWN_ID: "7_123",
		SyncScript.KEY_DURATION: 30.0,
		SyncScript.KEY_SOURCE_KIND: "relic",
		SyncScript.KEY_SOURCE_ID: SyncScript.SOURCE_ID_RELIC,
	}
	var wire := SyncScript.pack_for_network(local)
	if wire.is_empty():
		push_error("Expected clone pack_for_network to produce wire params")
		return 1
	var unpacked := SyncScript.unpack_from_network(wire)
	var ok := (
		str(unpacked.get(SyncScript.KEY_EFFECT_ID, "")) == SyncScript.EFFECT_CLONE
		and str(unpacked.get(SyncScript.KEY_TARGET_KIND, "")) == "relic_clone"
		and str(unpacked.get(SyncScript.KEY_SPAWN_ID, "")) == "7_123"
		and str(unpacked.get(SyncScript.KEY_SOURCE_KIND, "")) == "relic"
		and str(unpacked.get(SyncScript.KEY_SOURCE_ID, "")) == SyncScript.SOURCE_ID_RELIC
		and SyncScript.coerce_vector3(
			unpacked.get(SyncScript.KEY_ORIGIN, Vector3.ZERO)
		).is_equal_approx(Vector3(5.0, 1.1, -2.0))
	)
	if not ok:
		push_error("Expected clone network round-trip to preserve kind/origin/source/id")
		return 1
	return 0


func _test_build_ward_params() -> int:
	var player := _make_player_stub()
	var params := SyncScript.build_params(WardSpell, player)
	player.queue_free()
	if str(params.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_WARD:
		push_error("Expected ward build_params to set effect id")
		return 1
	if not params.has(SyncScript.KEY_ORIGIN) or not params.has(SyncScript.KEY_DIRECTION):
		push_error("Expected ward aim origin and direction")
		return 1
	if SyncScript.get_effect_duration_sec(WardSpell, params) != 0.0:
		push_error("Expected ward to hide HUD active timer")
		return 1
	var wire := SyncScript.pack_for_network(params)
	var unpacked := SyncScript.unpack_from_network(wire)
	if str(unpacked.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_WARD:
		push_error("Expected ward network round-trip to keep effect id")
		return 1
	return 0


func _test_flare_is_supported() -> int:
	var player := _make_player_stub()
	var params := SyncScript.build_params(FlareSpell, player)
	player.queue_free()
	if str(params.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_FLARE:
		push_error("Expected flare build_params to set effect id")
		return 1
	if float(params.get(SyncScript.KEY_DURATION, 0.0)) <= 0.0:
		push_error("Expected flare build_params to include beacon duration")
		return 1
	if SyncScript.get_effect_duration_sec(FlareSpell, params) != 0.0:
		push_error("Expected flare to hide HUD active timer")
		return 1
	var wire := SyncScript.pack_for_network(params)
	var unpacked := SyncScript.unpack_from_network(wire)
	if str(unpacked.get(SyncScript.KEY_EFFECT_ID, "")) != SyncScript.EFFECT_FLARE:
		push_error("Expected flare network round-trip to keep effect id")
		return 1
	if float(unpacked.get(SyncScript.KEY_DURATION, 0.0)) <= 0.0:
		push_error("Expected flare wire to carry beacon duration for all peers")
		return 1
	return 0


func _test_flare_params_spawn_projectile() -> int:
	var root := _make_world_root()
	var player := _make_player_stub()
	root.add_child(player)

	var params := {
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_FLARE,
		SyncScript.KEY_ORIGIN: Vector3(1.0, 2.0, 3.0),
		SyncScript.KEY_DIRECTION: Vector3(0.0, 0.0, -1.0),
		SyncScript.KEY_DURATION: 20.0,
	}
	SyncScript.apply(player, params)

	var projectile_count := _count_flare_projectiles(root)
	_free_world_root(root)

	if projectile_count != 1:
		push_error("Expected synced flare params to spawn one projectile")
		return 1
	return 0


func _test_flare_wire_params_spawn_projectile() -> int:
	var root := _make_world_root()
	var player := _make_player_stub()
	root.add_child(player)

	var local_params := {
		SyncScript.KEY_EFFECT_ID: SyncScript.EFFECT_FLARE,
		SyncScript.KEY_ORIGIN: Vector3(2.0, 1.5, -1.0),
		SyncScript.KEY_DIRECTION: Vector3(0.2, 0.8, -0.4).normalized(),
		SyncScript.KEY_DURATION: 20.0,
	}
	var wire := SyncScript.pack_for_network(local_params)
	var resolved := SyncScript.resolve_network_params(FlareSpell, player, wire)
	SyncScript.apply(player, resolved)

	var projectile_count := _count_flare_projectiles(root)
	_free_world_root(root)

	if projectile_count != 1:
		push_error("Expected wire-format flare params to spawn one projectile on peers")
		return 1
	return 0


func _count_flare_projectiles(root: Node) -> int:
	const FlareEffectScript := preload("res://scripts/spells/flare_effect.gd")
	var count := 0
	var bucket := root.get_node_or_null("SpellProjectiles")
	var nodes: Array[Node] = [root]
	if bucket != null:
		nodes.append(bucket)
	for node in nodes:
		for child in node.get_children():
			if child.get_script() == FlareEffectScript:
				count += 1
	return count


func _test_clone_source_eligibility_meta() -> int:
	var source := Node3D.new()
	if not SyncScript._is_cloneable_source(source):
		source.queue_free()
		push_error("Expected fresh source to be cloneable")
		return 1
	SyncScript._mark_clone_source_spent(source)
	if SyncScript._is_cloneable_source(source):
		source.queue_free()
		push_error("Expected spent source to reject further clones")
		return 1
	var clone_node := Node3D.new()
	SyncScript._mark_spawned_clone(clone_node)
	if SyncScript._is_cloneable_source(clone_node):
		source.queue_free()
		clone_node.queue_free()
		push_error("Expected spawned clone to reject further clones")
		return 1
	source.queue_free()
	clone_node.queue_free()
	return 0


class _EffectTrackingPlayer extends CharacterBody3D:
	var speed_boost_calls: Array[Dictionary] = []
	var toggle_calls := 0
	var flashlight_on := false


	func apply_speed_boost(duration: float, multiplier: float) -> void:
		speed_boost_calls.append({
			"duration": duration,
			"multiplier": multiplier,
		})


	func is_flashlight_enabled() -> bool:
		return flashlight_on


	func set_flashlight_enabled(active: bool) -> void:
		flashlight_on = active


	func toggle_flashlight() -> void:
		toggle_calls += 1
		flashlight_on = not flashlight_on
