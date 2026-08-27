class_name NetSpellAction
extends Node

## Peer-owned RewindableAction for player-bound casts (haste, flashlight).

const SpellEffectSyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const NetAuthorityScript := preload("res://scripts/net/net_authority.gd")

const HOST_PEER_ID := NetAuthorityScript.HOST_PEER_ID

var effect_id: String = ""
var _queued: bool = false
var _action: Node


func configure(p_effect_id: String, owner_peer_id: int) -> void:
	effect_id = p_effect_id
	if _action == null:
		var script := load("res://addons/netfox/rewindable-action.gd") as GDScript
		if script != null:
			_action = script.new() as Node
		if _action == null:
			push_error("NetSpellAction: RewindableAction missing")
			return
		_action.name = "RewindableAction"
		add_child(_action)
	var peer := owner_peer_id if owner_peer_id > 0 else HOST_PEER_ID
	set_multiplayer_authority(peer)
	_action.set_multiplayer_authority(peer)
	var player := get_parent()
	if player != null:
		_action.mutate(player)


func queue_cast(_params: Dictionary = {}) -> void:
	_queued = true


func _rollback_tick(_delta: float, tick: int, _is_fresh: bool) -> void:
	if _action == null or effect_id.is_empty():
		return
	if _queued and is_multiplayer_authority():
		_action.set_active(true, tick)
		_queued = false
	if not _action.is_active(tick):
		return
	var player := get_parent() as CharacterBody3D
	if player == null:
		return
	if effect_id == SpellEffectSyncScript.EFFECT_FLASHLIGHT_TOGGLE:
		## Invert restored pose state so resims of this tick stay idempotent.
		var currently := false
		if "net_flashlight" in player:
			currently = bool(player.get("net_flashlight"))
		if player.has_method("set_flashlight_enabled"):
			player.call("set_flashlight_enabled", not currently)
		return
	var params := {SpellEffectSyncScript.KEY_EFFECT_ID: effect_id}
	if effect_id == SpellEffectSyncScript.EFFECT_HASTE:
		params[SpellEffectSyncScript.KEY_DURATION] = SpellEffectSyncScript.DEFAULT_HASTE_DURATION
		params[SpellEffectSyncScript.KEY_MULTIPLIER] = SpellEffectSyncScript.DEFAULT_HASTE_MULTIPLIER
	SpellEffectSyncScript.apply(player, params)
