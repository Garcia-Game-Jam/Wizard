class_name NetSpellWeapon
extends "res://addons/netfox.extras/weapon/network-weapon-3d.gd"

## Predicted spell fire: spawn immediately, host confirms, reconcile.
## One node per effect_id so the host can spawn without client pending state.
## Spawn lives on SpellEffectSync.spawn_predicted — do not add a second match.

const SpellEffectSyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const NetAuthorityScript := preload("res://scripts/net/net_authority.gd")

const HOST_PEER_ID := NetAuthorityScript.HOST_PEER_ID

var effect_id: String = ""
var _pending: Dictionary = {}
var _owner_peer_id: int = 0


func configure(p_effect_id: String, peer_id: int) -> void:
	effect_id = p_effect_id
	_owner_peer_id = peer_id
	distance_threshold = 8.0
	set_multiplayer_authority(HOST_PEER_ID)


func fire_effect(params: Dictionary) -> Node3D:
	_pending = params.duplicate(true)
	var pending_id := str(_pending.get(SpellEffectSyncScript.KEY_EFFECT_ID, ""))
	if pending_id.is_empty() and not effect_id.is_empty():
		_pending[SpellEffectSyncScript.KEY_EFFECT_ID] = effect_id
	return fire()


func _can_fire() -> bool:
	return get_parent() is CharacterBody3D and not effect_id.is_empty()


func _can_peer_use(peer_id: int) -> bool:
	if _owner_peer_id <= 0:
		return true
	return peer_id == _owner_peer_id or peer_id == HOST_PEER_ID


func _spawn() -> Node3D:
	var player := get_parent() as CharacterBody3D
	return SpellEffectSyncScript.spawn_predicted(player, _params_for_spawn(player))


func _after_fire(projectile: Node3D) -> void:
	if projectile != null and projectile.has_method("simulate_from_tick"):
		projectile.call("simulate_from_tick", get_fired_tick())
	_pending.clear()


func _get_data(projectile: Node3D) -> Dictionary:
	var data := super._get_data(projectile)
	data["effect_id"] = effect_id
	data["origin"] = projectile.global_position if projectile != null else Vector3.ZERO
	if projectile != null and "_direction" in projectile:
		data["direction"] = projectile.get("_direction")
	if not _pending.is_empty():
		data["charge"] = float(_pending.get(SpellEffectSyncScript.KEY_CHARGE_FACTOR, 1.0))
	elif projectile != null and "net_charge_factor" in get_parent():
		data["charge"] = float(get_parent().get("net_charge_factor"))
	else:
		data["charge"] = 1.0
	return data


func _apply_data(projectile: Node3D, data: Dictionary) -> void:
	super._apply_data(projectile, data)
	if projectile != null and projectile.has_method("apply_net_launch") and data.has("origin"):
		var dir := Vector3.FORWARD
		if data.has("direction"):
			dir = data["direction"] as Vector3
		projectile.call(
			"apply_net_launch",
			data["origin"] as Vector3,
			dir,
			float(data.get("charge", 1.0))
		)


func _params_for_spawn(player: CharacterBody3D) -> Dictionary:
	if not _pending.is_empty():
		return _pending
	var params := {SpellEffectSyncScript.KEY_EFFECT_ID: effect_id}
	if player != null and player.has_method("get_wand_cast_origin"):
		params[SpellEffectSyncScript.KEY_ORIGIN] = player.call("get_wand_cast_origin")
	if player != null and player.has_method("get_wand_cast_direction"):
		params[SpellEffectSyncScript.KEY_DIRECTION] = player.call("get_wand_cast_direction")
	if player != null and "net_charge_factor" in player:
		params[SpellEffectSyncScript.KEY_CHARGE_FACTOR] = float(player.get("net_charge_factor"))
	return params
