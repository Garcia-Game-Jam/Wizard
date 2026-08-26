class_name ArenaCover
extends StaticBody3D

## Greybox pit block. Rises and sinks on the netfox tick so cover restage
## agrees on every peer. Collision is off until the cube is almost seated.
## Move intent is sticky (not rewindable); pose is derived from that intent
## so history restore cannot cancel a restage.

const NetClockScript := preload("res://scripts/net/net_clock.gd")

const EXIT_SEC := 0.75
const ENTER_SEC := 0.75
const BURIED_Y := -4.0
const SEATED_T := 0.92

var home: Vector3 = Vector3.ZERO
var queued_home: Vector3 = Vector3.ZERO
var cover_t: float = 1.0
var cover_dir: int = 0
var has_queued: int = 0

var _intent_from: Vector3 = Vector3.ZERO
var _intent_to: Vector3 = Vector3.ZERO
var _intent_start_tick: int = -1
var _intent_elapsed: float = 0.0

@onready var _collision: CollisionShape3D = get_node_or_null("Collision") as CollisionShape3D


func _ready() -> void:
	home = position
	queued_home = home
	cover_t = 1.0
	cover_dir = 0
	has_queued = 0
	_intent_start_tick = -1
	_intent_elapsed = 0.0
	_apply_pose()


func _physics_process(delta: float) -> void:
	if NetClockScript.is_ticking():
		return
	_rollback_tick(delta, 0, true)


func net_state_paths() -> Array[String]:
	return [
		":position",
		":rotation",
		":home",
		":queued_home",
		":cover_t",
		":cover_dir",
		":has_queued",
	]


func is_busy() -> bool:
	return cover_dir != 0 or has_queued != 0


func restage_to(world_pos: Vector3) -> void:
	var local_home := world_pos
	if get_parent() is Node3D:
		local_home = (get_parent() as Node3D).to_local(world_pos)
	if local_home.distance_squared_to(home) < 0.01 and cover_t >= 0.99 and cover_dir == 0:
		return
	_intent_from = home
	_intent_to = local_home
	_intent_elapsed = 0.0
	_intent_start_tick = _network_tick()
	if _intent_start_tick < 0:
		_intent_start_tick = 0
	queued_home = local_home
	has_queued = 1
	cover_dir = -1


func _rollback_tick(delta: float, tick: int, _is_fresh: bool) -> void:
	if _intent_start_tick < 0:
		_step_accum(delta)
		_apply_pose()
		return
	if NetClockScript.is_ticking():
		_eval_elapsed((tick - _intent_start_tick) * delta)
		return
	_intent_elapsed += delta
	_eval_elapsed(_intent_elapsed)


func _step_accum(delta: float) -> void:
	if cover_dir < 0:
		cover_t = maxf(0.0, cover_t - delta / EXIT_SEC)
		if cover_t <= 0.0:
			if has_queued != 0:
				home = queued_home
				has_queued = 0
				cover_dir = 1
			else:
				cover_dir = 0
	elif cover_dir > 0:
		cover_t = minf(1.0, cover_t + delta / ENTER_SEC)
		if cover_t >= 1.0:
			cover_t = 1.0
			cover_dir = 0


func _eval_elapsed(elapsed: float) -> void:
	if elapsed < 0.0:
		home = _intent_from
		cover_t = 1.0
		cover_dir = 0
		has_queued = 1
	elif elapsed < EXIT_SEC:
		home = _intent_from
		cover_t = 1.0 - elapsed / EXIT_SEC
		cover_dir = -1
		has_queued = 1
	elif elapsed < EXIT_SEC + ENTER_SEC:
		home = _intent_to
		cover_t = (elapsed - EXIT_SEC) / ENTER_SEC
		cover_dir = 1
		has_queued = 0
	else:
		home = _intent_to
		queued_home = _intent_to
		cover_t = 1.0
		cover_dir = 0
		has_queued = 0
	_apply_pose()


func _apply_pose() -> void:
	var buried := Vector3(home.x, BURIED_Y, home.z)
	position = buried.lerp(home, cover_t)
	if _collision != null:
		_collision.disabled = cover_t < SEATED_T


func _network_tick() -> int:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return -1
	var nt := (tree as SceneTree).root.get_node_or_null("NetworkTime")
	if nt == null or not bool(nt.call("is_initial_sync_done")):
		return -1
	return int(nt.get("tick"))
