class_name MonsterChaseMove
extends RefCounted

## Chase wait → strafe/retreat reposition controller owned by Monster.

enum Reposition { NONE, STRAFE, RETREAT }

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const STRAFE_RADIAL_BLEND := 0.28
const RETREAT_LATERAL_BLEND := 0.38

var wait_left: float = 0.0
var wait_armed: bool = false
var move_left: float = 0.0
var reposition: int = Reposition.NONE
var move_dir: Vector3 = Vector3.ZERO

var wait_min_sec: float = 1.0
var wait_max_sec: float = 3.0
var strafe_min_sec: float = 1.2
var strafe_max_sec: float = 2.0
var retreat_min_sec: float = 1.2
var retreat_max_sec: float = 3.2
var optimal_eps: float = 0.55
## When set, called on too-close before retreat/strafe. Return true to skip default move.
var custom_too_close_cb: Callable = Callable()
var strafe_radial_blend: float = STRAFE_RADIAL_BLEND

var _rng: RandomNumberGenerator = null


func configure(
	rng: RandomNumberGenerator,
	p_wait_min: float,
	p_wait_max: float,
	p_strafe_min: float,
	p_strafe_max: float,
	p_retreat_min: float,
	p_retreat_max: float,
	p_optimal_eps: float
) -> void:
	_rng = rng
	wait_min_sec = p_wait_min
	wait_max_sec = p_wait_max
	strafe_min_sec = p_strafe_min
	strafe_max_sec = p_strafe_max
	retreat_min_sec = p_retreat_min
	retreat_max_sec = p_retreat_max
	optimal_eps = p_optimal_eps


func clear() -> void:
	wait_left = 0.0
	wait_armed = false
	move_left = 0.0
	reposition = Reposition.NONE
	move_dir = Vector3.ZERO


func is_retreating() -> bool:
	return reposition == Reposition.RETREAT and move_left > 0.0


func is_moving() -> bool:
	return reposition != Reposition.NONE and move_left > 0.0


func arm_wait() -> void:
	wait_armed = true
	wait_left = MonsterAIScript.pick_chase_wait_sec(_rng, wait_min_sec, wait_max_sec)
	reposition = Reposition.NONE
	move_left = 0.0
	move_dir = Vector3.ZERO


func ensure_wait_armed() -> void:
	if wait_armed or reposition != Reposition.NONE:
		return
	arm_wait()


func start_strafe(host: Node3D, target: Node3D, side_sign: float, duration_sec: float) -> void:
	if target == null or not is_instance_valid(target):
		arm_wait()
		return
	reposition = Reposition.STRAFE
	move_left = maxf(duration_sec, 0.05)
	move_dir = MonsterAIScript.angled_strafe_dir(
		host.global_position, target.global_position, side_sign, strafe_radial_blend
	)
	wait_armed = false


func start_retreat(
	host: Node3D, target: Node3D, side_sign: float, duration_sec: float, max_dist: float
) -> void:
	if target == null or not is_instance_valid(target):
		arm_wait()
		return
	if not MonsterAIScript.can_retreat_farther(
		host.global_position, target.global_position, max_dist
	):
		start_strafe(host, target, side_sign, duration_sec)
		return
	reposition = Reposition.RETREAT
	move_left = maxf(duration_sec, 0.05)
	move_dir = MonsterAIScript.angled_retreat_dir(
		host.global_position, target.global_position, side_sign, RETREAT_LATERAL_BLEND
	)
	wait_armed = false


func tick_wait_and_decide(
	delta: float,
	host: Node3D,
	target: Node3D,
	dist: float,
	optimal: float,
	max_dist: float
) -> bool:
	## True when a reposition starts this frame.
	wait_left -= delta
	if wait_left > 0.0:
		return false
	_decide(host, target, dist, optimal, max_dist)
	return is_moving()


func _decide(
	host: Node3D, target: Node3D, dist: float, optimal: float, max_dist: float
) -> void:
	if target == null or not is_instance_valid(target):
		arm_wait()
		return
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var too_close := dist < optimal - optimal_eps
	if too_close and custom_too_close_cb.is_valid():
		if custom_too_close_cb.call(host, target, side):
			wait_armed = false
			return
	if (
		too_close
		and MonsterAIScript.can_retreat_farther(
			host.global_position, target.global_position, max_dist
		)
	):
		start_retreat(
			host,
			target,
			side,
			MonsterAIScript.pick_chase_retreat_sec(_rng, retreat_min_sec, retreat_max_sec),
			max_dist
		)
		return
	start_strafe(
		host,
		target,
		side,
		MonsterAIScript.pick_chase_strafe_sec(_rng, strafe_min_sec, strafe_max_sec)
	)


func tick_move(
	delta: float,
	host: CharacterBody3D,
	target: Node3D,
	move_speed: float,
	attack_range: float,
	max_dist: float,
	face_cb: Callable,
	touch_cb: Callable
) -> bool:
	## Applies velocity/facing on host. True when reposition is active this frame.
	if not is_moving():
		return false
	move_left -= delta
	if target == null or not is_instance_valid(target):
		arm_wait()
		host.velocity.x = 0.0
		host.velocity.z = 0.0
		return true

	var toward := Vector3(
		target.global_position.x - host.global_position.x,
		0.0,
		target.global_position.z - host.global_position.z
	)
	if reposition == Reposition.RETREAT:
		_tick_retreat_move(host, target, move_speed, max_dist, toward, face_cb)
	else:
		_tick_strafe_move(host, target, move_speed, attack_range, toward, face_cb, touch_cb)

	if move_left <= 0.0:
		arm_wait()
	return true


func _tick_retreat_move(
	host: CharacterBody3D,
	target: Node3D,
	move_speed: float,
	max_dist: float,
	_toward: Vector3,
	face_cb: Callable
) -> void:
	var desired: Vector3 = MonsterAIScript.retreat_velocity_clamped(
		host.global_position,
		target.global_position,
		move_dir,
		move_speed,
		host.velocity.y,
		max_dist
	)
	host.velocity.x = desired.x
	host.velocity.z = desired.z
	if move_dir.length_squared() > 0.0001:
		face_cb.call(move_dir)
	elif desired.length_squared() > 0.0001:
		face_cb.call(desired)
	if (
		desired.x * desired.x + desired.z * desired.z < 0.0001
		or not MonsterAIScript.can_retreat_farther(
			host.global_position, target.global_position, max_dist
		)
	):
		arm_wait()


func _tick_strafe_move(
	host: CharacterBody3D,
	target: Node3D,
	move_speed: float,
	attack_range: float,
	toward: Vector3,
	face_cb: Callable,
	touch_cb: Callable
) -> void:
	var flat_dir := Vector3(move_dir.x, 0.0, move_dir.z)
	if flat_dir.length_squared() > 0.0001:
		flat_dir = flat_dir.normalized()
		host.velocity.x = flat_dir.x * move_speed
		host.velocity.z = flat_dir.z * move_speed
	else:
		host.velocity.x = 0.0
		host.velocity.z = 0.0
	face_cb.call(toward)
	if toward.length() <= attack_range:
		touch_cb.call(target)
