class_name PlayerStun
extends Node

## Player/Stun: rewindable lock + launch. Stars follow _stunned after the tick loop.

const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")

const POST_LAND_STUN_SEC := 1.5
const MIN_AIR_SEC := 0.2

var _player: CharacterBody3D = null
var _stunned: bool = false
var _airborne: bool = false
var _post_land_left: float = 0.0
var _launch_vel: Vector3 = Vector3.ZERO
var _min_air_left: float = 0.0
var _saved_floor_snap: float = 0.1
var _overlay_root: Node3D = null
var _world_stars: Node = null
var _cam_stars: Node = null


func _ready() -> void:
	_ensure_player()
	var nt := get_tree().root.get_node_or_null("NetworkTime") if is_inside_tree() else null
	if nt != null and nt.has_signal("after_tick_loop"):
		nt.after_tick_loop.connect(_sync_visuals)
	_sync_visuals()


func _exit_tree() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var nt := tree.root.get_node_or_null("NetworkTime")
	if nt != null and nt.after_tick_loop.is_connected(_sync_visuals):
		nt.after_tick_loop.disconnect(_sync_visuals)


func _ensure_player() -> CharacterBody3D:
	if not is_instance_valid(_player):
		_player = get_parent() as CharacterBody3D
		_cache_fx_nodes()
	return _player if is_instance_valid(_player) else null


func is_stunned() -> bool:
	return _stunned


func is_launching() -> bool:
	return _stunned and _airborne


func begin_charger_hit(launch_vel: Vector3, _gravity: float = 18.0) -> void:
	_ensure_player()
	if not is_instance_valid(_player):
		return
	if GameState.is_multiplayer and not _player.is_multiplayer_authority():
		return
	if _player.has_method("_cancel_spell_fire_charge"):
		_player.call("_cancel_spell_fire_charge", true)
	_launch_vel = launch_vel
	_player.velocity = launch_vel
	_saved_floor_snap = _player.floor_snap_length
	_player.floor_snap_length = 0.0
	_stunned = true
	_airborne = true
	_min_air_left = MIN_AIR_SEC
	_post_land_left = 0.0
	if not NetClockScript.is_ticking():
		_sync_visuals()


func tick_physics(player: CharacterBody3D, delta: float, gravity: float) -> void:
	if not _stunned or player == null:
		return
	_player = player
	if _airborne:
		player.velocity.y -= gravity * delta
		_min_air_left -= delta
		return
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta
	_post_land_left -= delta
	if _post_land_left <= 0.0:
		_end_stun()


func after_slide(player: CharacterBody3D) -> void:
	if not _stunned or not _airborne or player == null:
		return
	if _min_air_left > 0.0:
		return
	if SlideSurfaceScript.hit_walkable_floor(player) or player.is_on_floor():
		_airborne = false
		_min_air_left = 0.0
		_launch_vel = Vector3.ZERO
		_post_land_left = POST_LAND_STUN_SEC
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		player.floor_snap_length = _saved_floor_snap


func _end_stun() -> void:
	_stunned = false
	_airborne = false
	_post_land_left = 0.0
	_min_air_left = 0.0
	_launch_vel = Vector3.ZERO
	if is_instance_valid(_player):
		_player.floor_snap_length = _saved_floor_snap
	if not NetClockScript.is_ticking():
		_sync_visuals()


func _cache_fx_nodes() -> void:
	_world_stars = null
	_cam_stars = null
	_overlay_root = null
	if not is_instance_valid(_player):
		return
	_world_stars = _player.get_node_or_null("StunStars")
	var cam := _player.get_node_or_null("%FirstPersonCamera") as Camera3D
	if cam == null:
		return
	_overlay_root = cam.get_node_or_null("StunOverlay") as Node3D
	if _overlay_root == null:
		return
	_cam_stars = _overlay_root.get_node_or_null("StunStars")
	var word := _overlay_root.get_node_or_null("StunnedWord") as Label3D
	if word != null:
		word.text = "stunned"


func _sync_visuals() -> void:
	_ensure_player()
	if not is_instance_valid(_overlay_root):
		_overlay_root = null
	if not is_instance_valid(_cam_stars):
		_cam_stars = null
	if not is_instance_valid(_world_stars):
		_world_stars = null
	var on := _stunned
	var local_view := on and is_instance_valid(_player) and (
		bool(_player.call("_uses_local_view")) if _player.has_method("_uses_local_view") else true
	)
	if is_instance_valid(_overlay_root):
		_overlay_root.visible = local_view
	if is_instance_valid(_cam_stars) and _cam_stars.has_method("set_active"):
		_cam_stars.call("set_active", local_view)
	if is_instance_valid(_world_stars) and _world_stars.has_method("set_active"):
		_world_stars.call("set_active", on and not local_view)
