class_name NetSpellWeapon
extends "res://addons/netfox.extras/weapon/network-weapon-3d.gd"

## Wand gun: authored under PlayerWand. Instantiates `projectile_scene` at CastOrigin.

const SpellEffectSyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const NetAuthorityScript := preload("res://scripts/net/net_authority.gd")

const HOST_PEER_ID := NetAuthorityScript.HOST_PEER_ID

@export var effect_id: String = ""
@export var projectile_scene: PackedScene
@export var charge_clip: StringName = &""
@export var release_clip: StringName = &""
@export var fizzle_clip: StringName = &""

var _pending: Dictionary = {}
var _owner_peer_id: int = 0


## A non-host cast only ever reaches _is_reconcilable() (host casts skip it
## entirely — the weapon's own multiplayer authority is always the host, so
## fire() takes the call_local _accept_projectile branch for them, never
## _request_projectile). It declines the shot outright if the host's replica
## of the caster's wand disagrees with the reported origin by more than this
## — and Player.dash_speed is 20 m/s, so even a single ~100ms round trip
## while dashing covers ~2m, well past a tight threshold. 1.5m only ever
## worked because the pit is small enough that players are usually
## stationary at engagement range; the colosseum's much larger floor means
## guests are routinely still moving (or just dashed) when they fire, so
## every one of their shots was getting silently discarded before it could
## ever hit anything. Sized to comfortably clear a dash-speed sprint across a
## realistic worst-case round trip instead of a walking-pace guess.
const _WAND_RECONCILE_DISTANCE := 8.0


func configure(p_effect_id: String, peer_id: int) -> void:
	if not p_effect_id.is_empty():
		effect_id = p_effect_id
	_owner_peer_id = peer_id
	distance_threshold = _WAND_RECONCILE_DISTANCE
	set_multiplayer_authority(HOST_PEER_ID)


func fire_effect(params: Dictionary) -> Node3D:
	_pending = params.duplicate(true)
	var pending_id := str(_pending.get(SpellEffectSyncScript.KEY_EFFECT_ID, ""))
	if pending_id.is_empty() and not effect_id.is_empty():
		_pending[SpellEffectSyncScript.KEY_EFFECT_ID] = effect_id
	return fire()


func _can_fire() -> bool:
	return _player() != null and not effect_id.is_empty()


func _can_peer_use(peer_id: int) -> bool:
	if _owner_peer_id <= 0:
		return true
	return peer_id == _owner_peer_id or peer_id == HOST_PEER_ID


func _spawn() -> Node3D:
	var player := _player()
	var params := _params_for_spawn(player)
	if projectile_scene != null:
		return _spawn_packed(player, params)
	return SpellEffectSyncScript.spawn_predicted(player, params)


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
	elif player_has_charge():
		data["charge"] = float(_player().get("net_charge_factor"))
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


func _spawn_packed(player: CharacterBody3D, params: Dictionary) -> Node3D:
	var origin := SpellEffectSyncScript.coerce_vector3(
		params.get(SpellEffectSyncScript.KEY_ORIGIN, Vector3.ZERO)
	)
	var direction := SpellEffectSyncScript.coerce_vector3(
		params.get(SpellEffectSyncScript.KEY_DIRECTION, Vector3.FORWARD)
	)
	var charge := clampf(float(params.get(SpellEffectSyncScript.KEY_CHARGE_FACTOR, 1.0)), 0.0, 1.0)
	var parent := SpellEphemeralFxScript.resolve_parent(player)
	var projectile: Node = projectile_scene.instantiate()
	if projectile is Node3D:
		SpellEphemeralFxScript.add_child_at(parent, projectile as Node3D, origin)
	elif parent != null:
		parent.add_child(projectile)
	if projectile != null and projectile.has_method("setup_launch"):
		projectile.call("setup_launch", origin, direction, player, charge)
	elif projectile != null and projectile.has_method("apply_net_launch"):
		projectile.call("apply_net_launch", origin, direction, charge)
	return projectile as Node3D


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


func _player() -> CharacterBody3D:
	var walk: Node = get_parent()
	while walk != null:
		if walk is CharacterBody3D:
			return walk as CharacterBody3D
		walk = walk.get_parent()
	return null


func player_has_charge() -> bool:
	var player := _player()
	return player != null and "net_charge_factor" in player
