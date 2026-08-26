class_name SpellEffectApplier
extends Node

## Applies spell gameplay and visual effects locally or via multiplayer sync.

const SyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const SpellSyncLaneScript := preload("res://scripts/spells/spell_sync_lane.gd")
const NetWorldEventScript := preload("res://scripts/net/net_world_event.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")


func apply_effect(player: CharacterBody3D, spell: SpellDefinition) -> void:
	if spell == null or player == null:
		return
	var params := SyncScript.build_params(spell, player)
	if params.is_empty():
		push_warning("SpellEffectApplier: unsupported spell '%s'" % spell.id)
		return
	SyncScript.apply(player, params)


func cast_spell(player: CharacterBody3D, spell: SpellDefinition) -> void:
	if spell == null or player == null:
		return
	var params := SyncScript.build_params(spell, player)
	if params.is_empty():
		push_warning("SpellEffectApplier: cannot cast unsupported spell '%s'" % spell.id)
		return
	_dispatch_cast(player, spell, params)


func cast_spell_with_params(
	player: CharacterBody3D,
	spell: SpellDefinition,
	params: Dictionary
) -> void:
	if spell == null or player == null or params.is_empty():
		return
	var resolved := params.duplicate(true)
	if str(resolved.get("effect_id", "")) != spell.effect_id:
		resolved["effect_id"] = spell.effect_id
	_dispatch_cast(player, spell, resolved)


func _dispatch_cast(
	player: CharacterBody3D,
	spell: SpellDefinition,
	params: Dictionary
) -> void:
	var effect_id := str(params.get("effect_id", ""))
	if NetClockScript.is_ticking() and SpellSyncLaneScript.predicts_locally(effect_id):
		NetWorldEventScript.dispatch_spell(player, params)
		return
	if not GameState.is_multiplayer:
		SyncScript.apply(player, params)
		return
	if not MatchStateManager.allows_gameplay_actions():
		return
	var wire_params := SyncScript.pack_for_network(params)
	if wire_params.is_empty():
		return
	if multiplayer.is_server():
		NetworkManager.broadcast_spell_cast(multiplayer.get_unique_id(), spell.id, wire_params)
	else:
		NetworkManager.request_spell_cast.rpc_id(1, spell.id, wire_params)


func apply_synced_cast(
	player: CharacterBody3D,
	spell: SpellDefinition,
	params: Dictionary
) -> void:
	if player == null or spell == null:
		return
	var resolved := SyncScript.resolve_network_params(spell, player, params)
	if resolved.is_empty():
		return
	if NetClockScript.is_ticking():
		NetWorldEventScript.dispatch_spell(player, resolved)
		return
	SyncScript.apply(player, resolved)
