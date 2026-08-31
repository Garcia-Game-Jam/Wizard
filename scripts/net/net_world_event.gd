class_name NetWorldEvent
extends RefCounted

## Thin dispatcher onto netfox primitives. Not a parallel lockstep simulator.
## Predicted projectiles: authored NetSpellWeapon under the wand. Flare/ward still
## use spawn_predicted. Bind happens from bind_player(); node names from the lane.

const SpellSyncLaneScript := preload("res://scripts/spells/spell_sync_lane.gd")
const SpellEffectSyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const NetRewindableMoverScript := preload("res://scripts/net/net_rewindable_mover.gd")
const NetSpellActionScript := preload("res://scripts/net/net_spell_action.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")

const KIND_WEAPON := "weapon"
const KIND_ACTION := "action"
const KIND_WORLD_PROP := "world_prop"


static func primitive_for_effect(effect_id: String) -> String:
	var lane := SpellSyncLaneScript.for_effect(effect_id)
	match lane:
		SpellSyncLaneScript.PLAYER_BOUND:
			return KIND_ACTION
		SpellSyncLaneScript.EPHEMERAL:
			return KIND_WEAPON
		SpellSyncLaneScript.WORLD_OBJECT:
			return KIND_WORLD_PROP
		_:
			return ""


static func bind_player(player: Node, owner_peer_id: int, local_view: bool = false) -> void:
	if player == null or not player.is_inside_tree():
		return
	NetRewindableMoverScript.apply_playable(player, owner_peer_id, local_view)
	for effect_id in SpellSyncLaneScript.BY_EFFECT.keys():
		var node_name := SpellSyncLaneScript.player_node_name(str(effect_id))
		if node_name.is_empty():
			continue
		var kind := primitive_for_effect(str(effect_id))
		if kind == KIND_WEAPON:
			_configure_weapon(player, node_name, str(effect_id), owner_peer_id)
		elif kind == KIND_ACTION:
			_ensure_action(player, node_name, str(effect_id), owner_peer_id)


static func dispatch_spell(player: CharacterBody3D, params: Dictionary) -> void:
	if player == null or params.is_empty():
		return
	var effect_id := str(params.get(SpellEffectSyncScript.KEY_EFFECT_ID, ""))
	var kind := primitive_for_effect(effect_id)
	match kind:
		KIND_WEAPON:
			_fire_weapon(player, params)
		KIND_ACTION:
			if NetClockScript.is_ticking():
				_apply_action(player, params)
			else:
				SpellEffectSyncScript.apply(player, params)
		_:
			SpellEffectSyncScript.apply(player, params)


static func _configure_weapon(
	player: Node,
	node_name: String,
	effect_id: String,
	peer_id: int
) -> void:
	var weapon := _find_weapon(player, node_name)
	if weapon == null:
		return
	if weapon.has_method("configure"):
		weapon.call("configure", effect_id, peer_id)


static func _find_weapon(player: Node, node_name: String) -> Node:
	if player == null or node_name.is_empty():
		return null
	var wand := player.get_node_or_null("Head/CameraPivot/Wand")
	if wand != null:
		var under_wand := wand.get_node_or_null(node_name)
		if under_wand != null:
			return under_wand
	return player.get_node_or_null(node_name)


static func _ensure_action(
	player: Node,
	node_name: String,
	effect_id: String,
	peer_id: int
) -> void:
	var action := player.get_node_or_null(node_name)
	if action == null:
		action = NetSpellActionScript.new()
		action.name = node_name
		player.add_child(action)
	if action.has_method("configure"):
		action.call("configure", effect_id, peer_id)


static func _fire_weapon(player: CharacterBody3D, params: Dictionary) -> void:
	var effect_id := str(params.get(SpellEffectSyncScript.KEY_EFFECT_ID, ""))
	var node_name := SpellSyncLaneScript.player_node_name(effect_id)
	var weapon := _find_weapon(player, node_name)
	if weapon != null and weapon.has_method("fire_effect"):
		weapon.call("fire_effect", params)
		return
	SpellEffectSyncScript.apply(player, params)


static func _apply_action(player: CharacterBody3D, params: Dictionary) -> void:
	var effect_id := str(params.get(SpellEffectSyncScript.KEY_EFFECT_ID, ""))
	var node_name := SpellSyncLaneScript.player_node_name(effect_id)
	if not node_name.is_empty():
		var action := player.get_node_or_null(node_name)
		if action != null and action.has_method("queue_cast"):
			action.call("queue_cast", params)
			return
	SpellEffectSyncScript.apply(player, params)
