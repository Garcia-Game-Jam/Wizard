class_name SpellEffectSync
extends RefCounted

## Generic spell effect params for solo play and multiplayer RPC payloads.
## Persistence model: see SpellSyncLane (player_bound / ephemeral / world_object /
## targeted). Ephemeral spawns use SpellEphemeralFx; lasting props use SpellWorldSync.

const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")
const FlareEffectScript := preload("res://scripts/spells/flare_effect.gd")
const WardShieldScript := preload("res://scripts/spells/ward_shield.gd")
const LightBallOrbScript := preload("res://scripts/spells/light_ball_orb.gd")
const TargetHighlightScript := preload("res://scripts/spells/target_highlight.gd")
const TargetedObjectControlScript := preload("res://scripts/spells/targeted_object_control.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")
const SpellWorldSyncScript := preload("res://scripts/spells/spell_world_sync.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const SpellSyncLaneScript := preload("res://scripts/spells/spell_sync_lane.gd")
const RelicCloneScript := preload("res://scripts/headmaster/relic_clone.gd")

const KEY_EFFECT_ID := "effect_id"
const KEY_ORIGIN := "origin"
const KEY_WAND_ORIGIN := "wand_origin"
const KEY_DIRECTION := "direction"
const KEY_DURATION := "duration"
const KEY_MULTIPLIER := "multiplier"
const KEY_TARGET_KIND := "target_kind"
const KEY_CHARGE_FACTOR := "charge_factor"

const EFFECT_HASTE := "haste"
const EFFECT_FIREBALL := "fireball"
const EFFECT_FLARE := "flare"
const EFFECT_WARD := "ward"
const EFFECT_FLASHLIGHT_TOGGLE := "flashlight_toggle"
const EFFECT_LIGHT_BALL := "light_ball"
const EFFECT_TARGET := "target"
const EFFECT_PULL := "pull"
const EFFECT_FOLLOW := "follow"
const EFFECT_STOP := "stop"
const EFFECT_DISPELL := "dispell"
const EFFECT_CLONE := "clone"

const KEY_GRID_X := "grid_x"
const KEY_GRID_Y := "grid_y"
const KEY_SPAWN_ID := "spawn_id"
const KEY_SOURCE_KIND := "source_kind"
const KEY_SOURCE_ID := "source_id"

const META_HAS_BEEN_CLONED := "spell_has_been_cloned"
const META_IS_CLONE := "spell_is_clone"
const SOURCE_ID_RELIC := "relic"

const DEFAULT_HASTE_DURATION := 4.0
const DEFAULT_HASTE_MULTIPLIER := 1.65
const DEFAULT_WARD_DURATION := 1.0
const DEFAULT_LIGHT_BALL_DURATION := 30.0
const DEFAULT_TARGET_DURATION := 10.0
const CLONE_OFFSET_DIST := 0.55


static func get_effect_duration_sec(spell: SpellDefinition, _params: Dictionary = {}) -> float:
	if spell == null:
		return 0.0
	## Durations live on the world effect (ward fade, haste aura, flare).
	## HUD no longer shows a top-right timeout strip.
	return 0.0


static func build_params(spell: SpellDefinition, player: CharacterBody3D) -> Dictionary:
	if spell == null or player == null:
		return {}
	var params := {
		KEY_EFFECT_ID: spell.effect_id,
		KEY_CHARGE_FACTOR: _player_charge_factor(player),
	}
	match spell.effect_id:
		EFFECT_FIREBALL, EFFECT_FLARE, EFFECT_WARD:
			params[KEY_ORIGIN] = _fireball_origin(player)
			params[KEY_DIRECTION] = _fireball_direction(player)
			if spell.effect_id == EFFECT_WARD:
				params[KEY_DURATION] = DEFAULT_WARD_DURATION
			elif spell.effect_id == EFFECT_FLARE:
				params[KEY_DURATION] = FlareEffectScript.DEFAULT_DURATION_SEC
		EFFECT_HASTE:
			params[KEY_DURATION] = DEFAULT_HASTE_DURATION
			params[KEY_MULTIPLIER] = DEFAULT_HASTE_MULTIPLIER
		EFFECT_LIGHT_BALL:
			params[KEY_ORIGIN] = _light_ball_origin(player)
			params[KEY_WAND_ORIGIN] = _fireball_origin(player)
			params[KEY_DURATION] = DEFAULT_LIGHT_BALL_DURATION
			params[KEY_SPAWN_ID] = SpellWorldSyncScript.make_spawn_id(player)
		EFFECT_FLASHLIGHT_TOGGLE:
			pass
		EFFECT_TARGET:
			params[KEY_DURATION] = DEFAULT_TARGET_DURATION
			_append_targetable(params, player)
		EFFECT_PULL:
			_append_looked_at_target(params, player, true)
		EFFECT_FOLLOW:
			_append_looked_at_target(params, player, false)
		EFFECT_STOP:
			pass
		EFFECT_DISPELL:
			var tree := player.get_tree() if player.is_inside_tree() else null
			if tree != null and not TargetHighlightScript.has_active_highlights(tree):
				return {}
			_append_dispell_target(params, player)
		EFFECT_CLONE:
			var tree := player.get_tree() if player.is_inside_tree() else null
			if tree != null and not TargetHighlightScript.has_active_highlights(tree):
				return {}
			if not _append_clone_params(params, player):
				return {}
		_:
			return {}
	return params


static func _player_charge_factor(player: CharacterBody3D) -> float:
	if player == null:
		return 1.0
	var wand: Node = player.get_node_or_null("Head/CameraPivot/Wand")
	if wand == null:
		wand = player.get_node_or_null("Head/CameraPivot/FirstPersonCamera/Wand")
	if wand != null and wand.has_method("get_cast_power_factor"):
		return clampf(float(wand.call("get_cast_power_factor")), 0.0, 1.0)
	return 1.0


static func _append_targetable(params: Dictionary, player: CharacterBody3D) -> void:
	var target := TargetedObjectControlScript.pick_targetable(player)
	if target == null:
		return
	var desc: Dictionary = TargetedObjectControlScript.describe_target(target)
	if desc.is_empty():
		return
	params[KEY_TARGET_KIND] = str(desc.get("kind", ""))
	params[KEY_ORIGIN] = desc.get("mark", Vector3.ZERO)


static func _append_looked_at_target(
	params: Dictionary,
	player: CharacterBody3D,
	require_los: bool = false
) -> void:
	var target := TargetedObjectControlScript.pick_looked_at(player, require_los)
	if target == null:
		return
	var desc: Dictionary = TargetedObjectControlScript.describe_target(target)
	if desc.is_empty():
		return
	params[KEY_TARGET_KIND] = str(desc.get("kind", ""))
	params[KEY_ORIGIN] = desc.get("mark", Vector3.ZERO)


static func _append_dispell_target(params: Dictionary, player: CharacterBody3D) -> void:
	if player == null or not player.is_inside_tree():
		return
	## Dispell only acts on Target outlines, picked by crosshair proximity.
	var target: Node3D = TargetedObjectControlScript.pick_dispellable(player)
	if target == null:
		return
	var desc: Dictionary = TargetedObjectControlScript.describe_target(target)
	if desc.is_empty():
		return
	params[KEY_TARGET_KIND] = str(desc.get("kind", ""))
	params[KEY_ORIGIN] = desc.get("mark", Vector3.ZERO)
	var cell: Variant = target.get("grid_cell")
	if cell is Vector2i:
		params[KEY_GRID_X] = cell.x
		params[KEY_GRID_Y] = cell.y
	var object_id := SpellWorldSyncScript.get_id(target)
	if object_id.is_empty() and cell is Vector2i:
		object_id = SpellWorldSyncScript.make_cell_id(cell)
	if not object_id.is_empty():
		params[KEY_SPAWN_ID] = object_id


static func _append_clone_params(params: Dictionary, player: CharacterBody3D) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	var source := TargetedObjectControlScript.pick_looked_at(player, false)
	if source == null or not _is_cloneable_source(source):
		return false
	var desc: Dictionary = TargetedObjectControlScript.describe_target(source)
	var source_kind := str(desc.get("kind", ""))
	var spawn_kind := ""
	match source_kind:
		"light_ball":
			spawn_kind = SpellWorldSyncScript.KIND_LIGHT_BALL
		"relic":
			spawn_kind = SpellWorldSyncScript.KIND_RELIC_CLONE
		_:
			return false
	var source_id := _clone_source_id(source, source_kind)
	if source_id.is_empty():
		return false
	var source_pos := coerce_vector3(desc.get("mark", source.global_position))
	if source.has_method("get_hover_base"):
		source_pos = source.call("get_hover_base")
	var clone_pos := _clone_spawn_position(player, source_pos, spawn_kind)
	params[KEY_TARGET_KIND] = spawn_kind
	params[KEY_ORIGIN] = clone_pos
	params[KEY_SPAWN_ID] = SpellWorldSyncScript.make_spawn_id(player)
	params[KEY_SOURCE_KIND] = source_kind
	params[KEY_SOURCE_ID] = source_id
	if spawn_kind == SpellWorldSyncScript.KIND_LIGHT_BALL:
		params[KEY_DURATION] = DEFAULT_LIGHT_BALL_DURATION
		params[KEY_WAND_ORIGIN] = clone_pos
	return true


static func _is_cloneable_source(source: Node3D) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if bool(source.get_meta(META_IS_CLONE, false)):
		return false
	if bool(source.get_meta(META_HAS_BEEN_CLONED, false)):
		return false
	if source.is_in_group(SpellWorldSyncScript.KIND_RELIC_CLONE):
		return false
	return true


static func _clone_source_id(source: Node3D, source_kind: String) -> String:
	if source_kind == TargetedObjectControlScript.TARGET_KIND_RELIC:
		return SOURCE_ID_RELIC
	var object_id := SpellWorldSyncScript.get_id(source)
	if not object_id.is_empty():
		return object_id
	var spawn_id: Variant = source.get("spawn_id")
	if spawn_id is String:
		return str(spawn_id)
	return ""


static func _resolve_clone_source(
	tree: SceneTree,
	source_kind: String,
	source_id: String,
	mark: Vector3
) -> Node3D:
	if tree == null or source_kind.is_empty():
		return null
	if source_kind == TargetedObjectControlScript.TARGET_KIND_RELIC:
		return TargetedObjectControlScript.resolve_target(
			tree, TargetedObjectControlScript.TARGET_KIND_RELIC, mark
		)
	if not source_id.is_empty():
		var by_id := SpellWorldSyncScript.find(tree, source_kind, source_id)
		if by_id != null:
			return by_id
	return TargetedObjectControlScript.resolve_target(tree, source_kind, mark)


static func _mark_clone_source_spent(source: Node3D) -> void:
	if source == null or not is_instance_valid(source):
		return
	source.set_meta(META_HAS_BEEN_CLONED, true)


static func _mark_spawned_clone(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.set_meta(META_IS_CLONE, true)
	node.set_meta(META_HAS_BEEN_CLONED, true)


static func _clone_spawn_position(
	player: CharacterBody3D,
	source_pos: Vector3,
	spawn_kind: String
) -> Vector3:
	## Offset sideways relative to look/crosshair, not the body capsule facing.
	var right := Vector3.RIGHT
	if player != null and player.is_inside_tree():
		var look := Vector3.FORWARD
		if player.has_method("get_wand_cast_direction"):
			look = player.call("get_wand_cast_direction")
		elif player.has_method("get_view_direction"):
			look = player.call("get_view_direction")
		look.y = 0.0
		if look.length_squared() > 0.0001:
			right = Vector3.UP.cross(look.normalized())
			if right.length_squared() < 0.0001:
				right = Vector3.RIGHT
			else:
				right = right.normalized()
	var clone_pos := source_pos + right * CLONE_OFFSET_DIST
	var world_3d: World3D = null
	if player != null and player.is_inside_tree():
		world_3d = player.get_world_3d()
	if spawn_kind == SpellWorldSyncScript.KIND_LIGHT_BALL:
		return LightBallOrbScript.snap_to_ground(world_3d, clone_pos)
	return RelicCloneScript.snap_to_ground(world_3d, clone_pos)


static func pack_for_network(params: Dictionary) -> Dictionary:
	var local := normalize_params(params)
	if local.is_empty():
		return {}
	var wire := {KEY_EFFECT_ID: str(local.get(KEY_EFFECT_ID, ""))}
	match str(wire[KEY_EFFECT_ID]):
		EFFECT_FIREBALL, EFFECT_FLARE, EFFECT_WARD:
			var origin := coerce_vector3(local.get(KEY_ORIGIN, Vector3.ZERO))
			var direction := coerce_vector3(local.get(KEY_DIRECTION, Vector3.FORWARD))
			SpellEphemeralFxScript.pack_ray(wire, origin, direction)
			wire[KEY_CHARGE_FACTOR] = float(local.get(KEY_CHARGE_FACTOR, 1.0))
			if str(wire[KEY_EFFECT_ID]) == EFFECT_WARD:
				wire[KEY_DURATION] = float(local.get(KEY_DURATION, DEFAULT_WARD_DURATION))
			elif str(wire[KEY_EFFECT_ID]) == EFFECT_FLARE:
				wire[KEY_DURATION] = float(
					local.get(KEY_DURATION, FlareEffectScript.DEFAULT_DURATION_SEC)
				)
		EFFECT_HASTE:
			wire[KEY_DURATION] = float(local.get(KEY_DURATION, DEFAULT_HASTE_DURATION))
			wire[KEY_MULTIPLIER] = float(local.get(KEY_MULTIPLIER, DEFAULT_HASTE_MULTIPLIER))
		EFFECT_TARGET:
			wire[KEY_DURATION] = float(local.get(KEY_DURATION, DEFAULT_TARGET_DURATION))
			wire[KEY_TARGET_KIND] = str(local.get(KEY_TARGET_KIND, ""))
			var mark := coerce_vector3(local.get(KEY_ORIGIN, Vector3.ZERO))
			wire["origin_x"] = mark.x
			wire["origin_y"] = mark.y
			wire["origin_z"] = mark.z
		EFFECT_PULL, EFFECT_FOLLOW:
			wire[KEY_TARGET_KIND] = str(local.get(KEY_TARGET_KIND, ""))
			var mark := coerce_vector3(local.get(KEY_ORIGIN, Vector3.ZERO))
			wire["origin_x"] = mark.x
			wire["origin_y"] = mark.y
			wire["origin_z"] = mark.z
		EFFECT_STOP:
			pass
		EFFECT_DISPELL:
			wire[KEY_TARGET_KIND] = str(local.get(KEY_TARGET_KIND, ""))
			var mark := coerce_vector3(local.get(KEY_ORIGIN, Vector3.ZERO))
			wire["origin_x"] = mark.x
			wire["origin_y"] = mark.y
			wire["origin_z"] = mark.z
			wire[KEY_GRID_X] = int(local.get(KEY_GRID_X, -1))
			wire[KEY_GRID_Y] = int(local.get(KEY_GRID_Y, -1))
			wire[KEY_SPAWN_ID] = str(local.get(KEY_SPAWN_ID, ""))
		EFFECT_CLONE:
			wire[KEY_TARGET_KIND] = str(local.get(KEY_TARGET_KIND, ""))
			var clone_origin := coerce_vector3(local.get(KEY_ORIGIN, Vector3.ZERO))
			wire["origin_x"] = clone_origin.x
			wire["origin_y"] = clone_origin.y
			wire["origin_z"] = clone_origin.z
			wire[KEY_SPAWN_ID] = str(local.get(KEY_SPAWN_ID, ""))
			wire[KEY_DURATION] = float(local.get(KEY_DURATION, DEFAULT_LIGHT_BALL_DURATION))
			wire[KEY_SOURCE_KIND] = str(local.get(KEY_SOURCE_KIND, ""))
			wire[KEY_SOURCE_ID] = str(local.get(KEY_SOURCE_ID, ""))
		EFFECT_LIGHT_BALL:
			var origin := coerce_vector3(local.get(KEY_ORIGIN, Vector3.ZERO))
			var wand_origin := coerce_vector3(local.get(KEY_WAND_ORIGIN, Vector3.ZERO))
			wire["origin_x"] = origin.x
			wire["origin_y"] = origin.y
			wire["origin_z"] = origin.z
			wire["wand_x"] = wand_origin.x
			wire["wand_y"] = wand_origin.y
			wire["wand_z"] = wand_origin.z
			wire[KEY_DURATION] = float(local.get(KEY_DURATION, DEFAULT_LIGHT_BALL_DURATION))
			wire[KEY_SPAWN_ID] = str(local.get(KEY_SPAWN_ID, ""))
		EFFECT_FLASHLIGHT_TOGGLE:
			pass
		_:
			return {}
	return wire


static func unpack_from_network(wire: Dictionary) -> Dictionary:
	if wire.is_empty():
		return {}
	var effect_id := str(wire.get(KEY_EFFECT_ID, ""))
	var params := {KEY_EFFECT_ID: effect_id}
	match effect_id:
		EFFECT_FIREBALL, EFFECT_FLARE, EFFECT_WARD:
			var ray := SpellEphemeralFxScript.unpack_ray(wire)
			params[KEY_ORIGIN] = ray[SpellEphemeralFxScript.KEY_ORIGIN]
			params[KEY_DIRECTION] = ray[SpellEphemeralFxScript.KEY_DIRECTION]
			params[KEY_CHARGE_FACTOR] = float(wire.get(KEY_CHARGE_FACTOR, 1.0))
			if effect_id == EFFECT_WARD:
				params[KEY_DURATION] = float(wire.get(KEY_DURATION, DEFAULT_WARD_DURATION))
			elif effect_id == EFFECT_FLARE:
				params[KEY_DURATION] = float(
					wire.get(KEY_DURATION, FlareEffectScript.DEFAULT_DURATION_SEC)
				)
		EFFECT_HASTE:
			params[KEY_DURATION] = float(wire.get(KEY_DURATION, DEFAULT_HASTE_DURATION))
			params[KEY_MULTIPLIER] = float(wire.get(KEY_MULTIPLIER, DEFAULT_HASTE_MULTIPLIER))
		EFFECT_TARGET:
			params[KEY_DURATION] = float(wire.get(KEY_DURATION, DEFAULT_TARGET_DURATION))
			params[KEY_TARGET_KIND] = str(wire.get(KEY_TARGET_KIND, ""))
			params[KEY_ORIGIN] = Vector3(
				float(wire.get("origin_x", 0.0)),
				float(wire.get("origin_y", 0.0)),
				float(wire.get("origin_z", 0.0))
			)
		EFFECT_PULL, EFFECT_FOLLOW:
			params[KEY_TARGET_KIND] = str(wire.get(KEY_TARGET_KIND, ""))
			params[KEY_ORIGIN] = Vector3(
				float(wire.get("origin_x", 0.0)),
				float(wire.get("origin_y", 0.0)),
				float(wire.get("origin_z", 0.0))
			)
		EFFECT_STOP:
			pass
		EFFECT_DISPELL:
			params[KEY_TARGET_KIND] = str(wire.get(KEY_TARGET_KIND, ""))
			params[KEY_ORIGIN] = Vector3(
				float(wire.get("origin_x", 0.0)),
				float(wire.get("origin_y", 0.0)),
				float(wire.get("origin_z", 0.0))
			)
			params[KEY_GRID_X] = int(wire.get(KEY_GRID_X, -1))
			params[KEY_GRID_Y] = int(wire.get(KEY_GRID_Y, -1))
			params[KEY_SPAWN_ID] = str(wire.get(KEY_SPAWN_ID, ""))
		EFFECT_CLONE:
			params[KEY_TARGET_KIND] = str(wire.get(KEY_TARGET_KIND, ""))
			params[KEY_ORIGIN] = Vector3(
				float(wire.get("origin_x", 0.0)),
				float(wire.get("origin_y", 0.0)),
				float(wire.get("origin_z", 0.0))
			)
			params[KEY_SPAWN_ID] = str(wire.get(KEY_SPAWN_ID, ""))
			params[KEY_DURATION] = float(wire.get(KEY_DURATION, DEFAULT_LIGHT_BALL_DURATION))
			params[KEY_SOURCE_KIND] = str(wire.get(KEY_SOURCE_KIND, ""))
			params[KEY_SOURCE_ID] = str(wire.get(KEY_SOURCE_ID, ""))
		EFFECT_LIGHT_BALL:
			params[KEY_ORIGIN] = Vector3(
				float(wire.get("origin_x", 0.0)),
				float(wire.get("origin_y", 0.0)),
				float(wire.get("origin_z", 0.0))
			)
			params[KEY_WAND_ORIGIN] = Vector3(
				float(wire.get("wand_x", 0.0)),
				float(wire.get("wand_y", 0.0)),
				float(wire.get("wand_z", 0.0))
			)
			params[KEY_DURATION] = float(wire.get(KEY_DURATION, DEFAULT_LIGHT_BALL_DURATION))
			params[KEY_SPAWN_ID] = str(wire.get(KEY_SPAWN_ID, ""))
		EFFECT_FLASHLIGHT_TOGGLE:
			pass
		_:
			return {}
	return params


static func normalize_params(params: Dictionary) -> Dictionary:
	if params.is_empty():
		return {}
	if is_network_format(params):
		return unpack_from_network(params)
	return params.duplicate(true)


static func is_network_format(params: Dictionary) -> bool:
	var effect_id := str(params.get(KEY_EFFECT_ID, ""))
	if (
		(
			effect_id == EFFECT_FIREBALL
			or effect_id == EFFECT_FLARE
			or effect_id == EFFECT_WARD
		)
		and SpellEphemeralFxScript.is_ray_wire(params)
	):
		return true
	if effect_id == EFFECT_LIGHT_BALL and params.has("origin_x") and not params.has(KEY_ORIGIN):
		return true
	if (
		(
			effect_id == EFFECT_PULL
			or effect_id == EFFECT_FOLLOW
			or effect_id == EFFECT_TARGET
			or effect_id == EFFECT_DISPELL
			or effect_id == EFFECT_CLONE
		)
		and params.has("origin_x")
		and not params.has(KEY_ORIGIN)
	):
		return true
	return false


static func resolve_network_params(
	spell: SpellDefinition,
	player: CharacterBody3D,
	wire_or_local: Dictionary
) -> Dictionary:
	var params := normalize_params(wire_or_local)
	if spell == null or params.is_empty():
		return {}
	if str(params.get(KEY_EFFECT_ID, "")) != spell.effect_id:
		params[KEY_EFFECT_ID] = spell.effect_id
	if spell.effect_id == EFFECT_DISPELL and player != null:
		## Require an active Target outline; refill destroy id if the wire omitted it.
		if not TargetHighlightScript.has_active_highlights(player.get_tree()):
			return {}
		var has_kind := not str(params.get(KEY_TARGET_KIND, "")).is_empty()
		if not has_kind:
			_append_dispell_target(params, player)
	if (
		spell.effect_id != EFFECT_FIREBALL
		and spell.effect_id != EFFECT_FLARE
		and spell.effect_id != EFFECT_WARD
	):
		return params
	if not is_valid_ray_spell_params(params, spell.effect_id):
		if player == null:
			return {}
		return build_params(spell, player)
	if player != null and not _fireball_origin_plausible(params, player):
		return build_params(spell, player)
	return params


static func is_valid_fireball_params(params: Dictionary) -> bool:
	return is_valid_ray_spell_params(params, EFFECT_FIREBALL)


static func is_valid_ray_spell_params(params: Dictionary, effect_id: String) -> bool:
	if str(params.get(KEY_EFFECT_ID, "")) != effect_id:
		return false
	var direction := coerce_vector3(params.get(KEY_DIRECTION, Vector3.ZERO))
	return direction.length_squared() > 0.01


static func coerce_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("z", 0.0))
		)
	return Vector3.ZERO


static func apply(player: CharacterBody3D, params: Dictionary) -> void:
	if player == null or params.is_empty():
		return
	match str(params.get(KEY_EFFECT_ID, "")):
		EFFECT_HASTE:
			player.apply_speed_boost(
				float(params.get(KEY_DURATION, DEFAULT_HASTE_DURATION)),
				float(params.get(KEY_MULTIPLIER, DEFAULT_HASTE_MULTIPLIER))
			)
		EFFECT_FIREBALL:
			_apply_fireball(player, params)
		EFFECT_FLARE:
			_apply_flare(player, params)
		EFFECT_WARD:
			_apply_ward(player, params)
		EFFECT_FLASHLIGHT_TOGGLE:
			_toggle_flashlight(player)
		EFFECT_LIGHT_BALL:
			_apply_light_ball(player, params)
		EFFECT_TARGET:
			_apply_target(player, params)
		EFFECT_PULL:
			_apply_pull(player, params)
		EFFECT_FOLLOW:
			_apply_follow(player, params)
		EFFECT_STOP:
			_apply_stop(player)
		EFFECT_DISPELL:
			_apply_dispell(player, params)
		EFFECT_CLONE:
			_apply_clone(player, params)
		_:
			push_warning(
				"SpellEffectSync: unknown effect '%s'" % str(params.get(KEY_EFFECT_ID, ""))
			)


static func _apply_target(player: CharacterBody3D, params: Dictionary) -> void:
	if player == null or not player.is_inside_tree():
		return
	var duration := float(params.get(KEY_DURATION, DEFAULT_TARGET_DURATION))
	var target := _resolve_targeted_object(player, params, false)
	if target == null:
		target = TargetedObjectControlScript.pick_targetable(player)
	if target == null:
		return
	TargetHighlightScript.apply_single(player.get_tree(), target, duration)


static func _apply_pull(player: CharacterBody3D, params: Dictionary) -> void:
	var target := _resolve_targeted_object(player, params, true)
	if target == null:
		return
	TargetedObjectControlScript.pull_object(player, target)


static func _apply_follow(player: CharacterBody3D, params: Dictionary) -> void:
	var target := _resolve_targeted_object(player, params, false)
	if target == null:
		return
	TargetedObjectControlScript.start_follow(player, target)


static func _apply_stop(player: CharacterBody3D) -> void:
	## Clears Follow/Pull channels (and Target outlines) for every peer that
	## receives the cast — not just the caster's own drivers.
	var scene_tree: SceneTree = null
	if player != null and player.is_inside_tree():
		scene_tree = player.get_tree()
	else:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			scene_tree = loop as SceneTree
	if scene_tree == null:
		return
	TargetedObjectControlScript.stop_all(scene_tree)


static func _apply_dispell(player: CharacterBody3D, params: Dictionary) -> void:
	var scene_tree: SceneTree = null
	if player != null and player.is_inside_tree():
		scene_tree = player.get_tree()
	else:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			scene_tree = loop as SceneTree
	if scene_tree == null:
		return
	var mark := coerce_vector3(params.get(KEY_ORIGIN, Vector3.ZERO))
	var kind := str(params.get(KEY_TARGET_KIND, ""))
	var object_id := str(params.get(KEY_SPAWN_ID, ""))
	var destroyed := false
	if not kind.is_empty() or not object_id.is_empty():
		var resolved := SpellWorldSyncScript.resolve(scene_tree, kind, object_id, mark)
		if resolved != null and resolved.has_method("destroy_from_spell"):
			resolved.call("destroy_from_spell", true)
			destroyed = true
	if not destroyed:
		## Fallback when the cast wire has no target: remove highlighted
		## dispellable objects and broadcast so peers still clear them.
		_dispell_highlighted_objects(scene_tree)
	TargetedObjectControlScript.stop_all(scene_tree)


static func _dispell_highlighted_objects(tree: SceneTree) -> void:
	if tree == null:
		return
	for anchor in TargetHighlightScript.get_highlighted_anchors(tree):
		if anchor == null:
			continue
		if (
			anchor.is_in_group(SpellWorldSyncScript.KIND_LIGHT_BALL)
			or anchor.is_in_group(SpellWorldSyncScript.KIND_RELIC_CLONE)
		):
			if anchor.has_method("destroy_from_spell"):
				anchor.call("destroy_from_spell", false)


static func _resolve_targeted_object(
	player: CharacterBody3D,
	params: Dictionary,
	require_los: bool = false
) -> Node3D:
	if player == null or not player.is_inside_tree():
		return null
	var kind := str(params.get(KEY_TARGET_KIND, ""))
	if kind.is_empty():
		return TargetedObjectControlScript.pick_looked_at(player, require_los)
	var mark := coerce_vector3(params.get(KEY_ORIGIN, Vector3.ZERO))
	var resolved := TargetedObjectControlScript.resolve_target(
		player.get_tree(), kind, mark
	)
	if (
		require_los
		and resolved != null
		and not TargetedObjectControlScript.has_clear_line_of_sight(player, resolved)
	):
		return null
	return resolved


static func is_supported_effect(effect_id: String) -> bool:
	return SpellSyncLaneScript.is_known(effect_id)


static func sync_lane_for(effect_id: String) -> String:
	return SpellSyncLaneScript.for_effect(effect_id)


static func _fireball_direction(player: CharacterBody3D) -> Vector3:
	## Shared aim for fireball / flare / any ray spell: wand → crosshair.
	if player.has_method("get_wand_cast_direction"):
		return player.call("get_wand_cast_direction")
	if player.has_method("get_view_direction"):
		return player.call("get_view_direction")
	var camera_pivot: Node3D = player.get_node_or_null("Head/CameraPivot")
	if camera_pivot != null:
		var basis := camera_pivot.global_transform.basis if camera_pivot.is_inside_tree() \
			else camera_pivot.transform.basis
		return (-basis.z).normalized()
	return -player.transform.basis.z.normalized()


static func _fireball_origin(player: CharacterBody3D) -> Vector3:
	if player.has_method("get_wand_cast_origin"):
		return player.call("get_wand_cast_origin")
	var head: Node3D = player.get_node_or_null("Head")
	var forward := _fireball_direction(player)
	if head != null:
		var head_origin := head.global_position if head.is_inside_tree() else head.position
		return head_origin + forward * 0.6 + Vector3(0.0, 0.1, 0.0)
	var player_origin := player.global_position if player.is_inside_tree() else player.position
	return player_origin + forward * 0.6 + Vector3(0.0, 0.1, 0.0)


static func _apply_fireball(player: CharacterBody3D, params: Dictionary) -> void:
	var origin := coerce_vector3(params.get(KEY_ORIGIN, Vector3.ZERO))
	var direction := coerce_vector3(params.get(KEY_DIRECTION, Vector3.FORWARD))
	var charge := clampf(float(params.get(KEY_CHARGE_FACTOR, 1.0)), 0.0, 1.0)
	SpellEphemeralFxScript.spawn_at(
		player,
		origin,
		direction,
		func(parent: Node, spawn_origin: Vector3, spawn_dir: Vector3) -> Node:
			return FireballProjectileScript.spawn(
				parent, spawn_origin, spawn_dir, player, false, charge
			)
	)


static func _apply_flare(player: CharacterBody3D, params: Dictionary) -> void:
	var origin := coerce_vector3(params.get(KEY_ORIGIN, Vector3.ZERO))
	var direction := coerce_vector3(params.get(KEY_DIRECTION, Vector3.FORWARD))
	var duration := float(
		params.get(KEY_DURATION, FlareEffectScript.DEFAULT_DURATION_SEC)
	)
	var charge := clampf(float(params.get(KEY_CHARGE_FACTOR, 1.0)), 0.0, 1.0)
	## Same ephemeral cast wire as fireball — every peer spawns + simulates locally.
	SpellEphemeralFxScript.spawn_at(
		player,
		origin,
		direction,
		func(parent: Node, spawn_origin: Vector3, spawn_dir: Vector3) -> Node:
			var fly := true
			var caster: Node3D = player
			var flare: Node = FlareEffectScript.spawn_launched(
				parent, spawn_origin, spawn_dir, duration, fly, caster
			)
			if flare != null and flare.has_method("apply_charge_power"):
				flare.call("apply_charge_power", charge)
			return flare
	)


static func _apply_ward(player: CharacterBody3D, params: Dictionary) -> void:
	## Hold plants a following beam locally; skip a second spawn.
	if player != null and player.has_method("consume_channel_ward"):
		var channeled: Node = player.call("consume_channel_ward") as Node
		if channeled != null:
			return
	var origin := coerce_vector3(params.get(KEY_ORIGIN, Vector3.ZERO))
	var direction := coerce_vector3(params.get(KEY_DIRECTION, Vector3.FORWARD))
	var forward := direction
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	## Nudge every ward slightly ahead of the cast point.
	var spawn_origin := origin + forward * 0.4
	SpellEphemeralFxScript.spawn_at(
		player,
		spawn_origin,
		forward,
		func(parent: Node, placed_origin: Vector3, spawn_dir: Vector3) -> Node:
			return WardShieldScript.spawn(parent, placed_origin, spawn_dir, 1)
	)


static func _apply_clone(player: CharacterBody3D, params: Dictionary) -> void:
	if player == null or not player.is_inside_tree():
		return
	var tree := player.get_tree()
	var spawn_kind := str(params.get(KEY_TARGET_KIND, ""))
	var clone_pos := coerce_vector3(params.get(KEY_ORIGIN, Vector3.ZERO))
	var clone_id := str(params.get(KEY_SPAWN_ID, ""))
	var source_kind := str(params.get(KEY_SOURCE_KIND, ""))
	var source_id := str(params.get(KEY_SOURCE_ID, ""))
	if spawn_kind.is_empty() or clone_pos == Vector3.ZERO:
		return
	if clone_id.is_empty():
		clone_id = SpellWorldSyncScript.make_spawn_id(player)
	var world: Node = GameWorldScript.find_match_root(tree)
	if world == null:
		world = player.get_parent()
	if world == null:
		return
	## Idempotent on every peer: same spawn_id from the cast wire.
	if SpellWorldSyncScript.find(tree, spawn_kind, clone_id) != null:
		var existing_source := _resolve_clone_source(tree, source_kind, source_id, clone_pos)
		_mark_clone_source_spent(existing_source)
		return
	var source := _resolve_clone_source(tree, source_kind, source_id, clone_pos)
	if source != null and not _is_cloneable_source(source):
		return
	var spawned: Node = null
	match spawn_kind:
		SpellWorldSyncScript.KIND_LIGHT_BALL:
			var ball_bucket := SpellWorldSyncScript.ensure_bucket(
				world, SpellWorldSyncScript.BUCKET_LIGHT_BALLS
			)
			var duration := float(params.get(KEY_DURATION, DEFAULT_LIGHT_BALL_DURATION))
			spawned = LightBallOrbScript.spawn_cast(
				ball_bucket, clone_pos, clone_pos, duration, clone_id
			)
		SpellWorldSyncScript.KIND_RELIC_CLONE:
			var relic_bucket := SpellWorldSyncScript.ensure_bucket(
				world, SpellWorldSyncScript.BUCKET_RELIC_CLONES
			)
			spawned = RelicCloneScript.spawn(relic_bucket, clone_pos, clone_id)
		_:
			return
	_mark_spawned_clone(spawned)
	_mark_clone_source_spent(source)


static func _toggle_flashlight(player: CharacterBody3D) -> void:
	if player.has_method("toggle_flashlight"):
		player.call("toggle_flashlight")
		return
	if not player.has_method("set_flashlight_enabled"):
		return
	var active := false
	if player.has_method("is_flashlight_enabled"):
		active = bool(player.call("is_flashlight_enabled"))
	player.call("set_flashlight_enabled", not active)


static func _light_ball_origin(player: CharacterBody3D) -> Vector3:
	return LightBallOrbScript.resolve_placement(player, _player_charge_factor(player))


static func _apply_light_ball(player: CharacterBody3D, params: Dictionary) -> void:
	var target := coerce_vector3(params.get(KEY_ORIGIN, Vector3.ZERO))
	if target == Vector3.ZERO:
		target = _light_ball_origin(player)
	var wand_origin := coerce_vector3(params.get(KEY_WAND_ORIGIN, Vector3.ZERO))
	if wand_origin == Vector3.ZERO:
		wand_origin = _fireball_origin(player)
	var world: Node = null
	if player.is_inside_tree():
		world = GameWorldScript.find_match_root(player.get_tree())
	if world == null:
		world = player.get_parent()
	if world == null:
		return
	var bucket := SpellWorldSyncScript.ensure_bucket(
		world, SpellWorldSyncScript.BUCKET_LIGHT_BALLS
	)
	var orb_spawn_id := str(params.get(KEY_SPAWN_ID, ""))
	if orb_spawn_id.is_empty():
		orb_spawn_id = SpellWorldSyncScript.make_spawn_id(player)
	LightBallOrbScript.spawn_cast(
		bucket,
		wand_origin,
		target,
		float(params.get(KEY_DURATION, DEFAULT_LIGHT_BALL_DURATION)),
		orb_spawn_id
	)


static func _fireball_origin_plausible(params: Dictionary, player: CharacterBody3D) -> bool:
	var origin := coerce_vector3(params.get(KEY_ORIGIN, Vector3.ZERO))
	var player_pos := (
		player.global_position if player.is_inside_tree() else player.position
	)
	return player_pos.distance_squared_to(origin) <= 9.0
