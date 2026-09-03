class_name ChargerCharge
extends RefCounted

## Stalk → lock-on telegraph → locked ram → (wall stun | skid recovery) → search.
## Shared by charger.tscn lookdev, monster workspace, and the match. Pose-only
## previews never auto-stun. FEINT is a short fake windup that resolves back into
## a real TELEGRAPH once per engagement.

enum Phase { IDLE, TELEGRAPH, CHARGE, WALL_STUN, SEARCH, STALK, RECOVER, FEINT }

const CHARGE_SPEED_MULT := 2.3
const DEFAULT_TELEGRAPH_SEC := 1.2
const DEFAULT_WALL_STUN_SEC := 3.0
const WALL_GRACE_SEC := 0.35
const HEAD_READY_RAD := 0.05
const WALL_UP_DOT := 0.45
const SEARCH_YAW_AMP_RAD := 0.55
const SEARCH_YAW_HZ := 0.28
const SEARCH_PITCH_AMP_RAD := 0.1
const SEARCH_ABOUT_FACE_EPS := 0.08
const WARD_GROUP := &"spell_ward"

## Forward lunge speed during the first half of a feint. (All the tunable
## charge/stalk/feint values live as exports on charger.gd / charger.tscn.)
const FEINT_HOP_SPEED := 4.0
## Belt-and-suspenders wedged check: N consecutive charge ticks making less than
## FRAC of the intended forward progress → treat as blocked → wall stun.
const STALL_TICKS := 5
const STALL_PROGRESS_FRAC := 0.15


var phase: Phase = Phase.IDLE
var age: float = 0.0
var pose_only: bool = false
var locked_dir: Vector3 = Vector3.FORWARD
## One pre-charge feint per engagement; cleared by reset().
var feint_used: bool = false


func reset() -> void:
	phase = Phase.IDLE
	age = 0.0
	pose_only = false
	locked_dir = Vector3.FORWARD
	feint_used = false


func begin_telegraph() -> void:
	phase = Phase.TELEGRAPH
	age = 0.0


func begin_stalk() -> void:
	phase = Phase.STALK
	age = 0.0


func begin_feint() -> void:
	phase = Phase.FEINT
	age = 0.0
	feint_used = true


func begin_charge(dir: Vector3) -> void:
	phase = Phase.CHARGE
	age = 0.0
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		locked_dir = Vector3.FORWARD
	else:
		locked_dir = flat.normalized()


func begin_wall_stun() -> void:
	phase = Phase.WALL_STUN
	age = 0.0


func begin_recover() -> void:
	phase = Phase.RECOVER
	age = 0.0


func begin_search() -> void:
	phase = Phase.SEARCH
	age = 0.0


func tick(delta: float) -> void:
	age += maxf(delta, 0.0)


func telegraph_progress(duration_sec: float) -> float:
	return clampf(age / maxf(duration_sec, 0.05), 0.0, 1.0)


func telegraph_ready(duration_sec: float, head_pitch: float, plunge_pitch: float) -> bool:
	if telegraph_progress(duration_sec) < 1.0:
		return false
	return absf(head_pitch - plunge_pitch) <= HEAD_READY_RAD


func wall_stun_ready(duration_sec: float) -> bool:
	return age + 0.0001 >= maxf(duration_sec, 0.05)


func recover_ready(duration_sec: float) -> bool:
	return age + 0.0001 >= maxf(duration_sec, 0.05)


func feint_ready(duration_sec: float) -> bool:
	return age + 0.0001 >= maxf(duration_sec, 0.05)


func search_ready(duration_sec: float) -> bool:
	return age + 0.0001 >= maxf(duration_sec, 0.05)


## --- Commit window / whiff / band (pure, distance-driven so rollback is safe) ---

## Steer locked_dir toward a flat world direction, capped at max_turn_rad/s.
func steer_locked_dir(toward_flat: Vector3, max_turn_rad: float, delta: float) -> void:
	var flat := Vector3(toward_flat.x, 0.0, toward_flat.z)
	if flat.length_squared() < 0.0001:
		return
	var cur := locked_dir
	if cur.length_squared() < 0.0001:
		cur = Vector3.FORWARD
	var cur_yaw := atan2(-cur.x, -cur.z)
	var want_yaw := atan2(-flat.x, -flat.z)
	var next_yaw := rotate_toward(
		cur_yaw, want_yaw, maxf(max_turn_rad, 0.0) * maxf(delta, 0.0)
	)
	locked_dir = Vector3(-sin(next_yaw), 0.0, -cos(next_yaw)).normalized()


static func is_committed(dist_travelled: float, commit_m: float) -> bool:
	return dist_travelled >= maxf(commit_m, 0.0)


static func whiffed(dist_travelled: float, max_m: float) -> bool:
	return dist_travelled >= maxf(max_m, 0.5)


static func in_charge_band(dist: float, band_min_m: float, band_max_m: float) -> bool:
	return dist >= minf(band_min_m, band_max_m) and dist <= maxf(band_min_m, band_max_m)


## True (once) when a pre-charge feint should fire this engagement.
func roll_feint(rng: RandomNumberGenerator, chance: float) -> bool:
	if feint_used or rng == null or chance <= 0.0:
		return false
	if rng.randf() >= chance:
		return false
	return true


static func roll_chance(rng: RandomNumberGenerator, chance: float) -> bool:
	return rng != null and chance > 0.0 and rng.randf() < chance


static func heading_from_yaw(yaw_rad: float) -> Vector3:
	return Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad))


static func about_face_heading(base_yaw: float) -> Vector3:
	return heading_from_yaw(base_yaw + PI)


static func about_face_remaining(current_yaw: float, base_yaw: float) -> float:
	var want := wrapf(base_yaw + PI, -PI, PI)
	return absf(wrapf(want - current_yaw, -PI, PI))


static func about_face_done(current_yaw: float, base_yaw: float) -> bool:
	return about_face_remaining(current_yaw, base_yaw) <= SEARCH_ABOUT_FACE_EPS


static func search_yaw_offset(age_sec: float, amp_rad: float, hz: float) -> float:
	## Slow single-sine sweep after the about-face.
	var t := maxf(age_sec, 0.0)
	return sin(t * maxf(hz, 0.05) * TAU) * maxf(amp_rad, 0.0)


static func search_head_pitch(age_sec: float, amp_rad: float, hz: float) -> float:
	var t := maxf(age_sec, 0.0)
	var rate := maxf(hz, 0.05) * TAU * 0.85
	return sin(t * rate) * maxf(amp_rad, 0.0)


func can_read_walls() -> bool:
	return not pose_only and phase == Phase.CHARGE and age >= WALL_GRACE_SEC


func charge_velocity(speed: float) -> Vector3:
	var spd := maxf(speed, 0.0)
	return Vector3(locked_dir.x * spd, 0.0, locked_dir.z * spd)


static func charge_speed(sprint_speed: float, mult: float = CHARGE_SPEED_MULT) -> float:
	return maxf(0.0, sprint_speed) * maxf(mult, 0.0)


static func is_wall_collider(collider: Object, normal: Vector3) -> bool:
	if collider == null:
		return false
	if collider is Node and _is_ignored_wall_node(collider as Node):
		return false
	return normal.y < WALL_UP_DOT


static func collect_wall_excludes(body: CollisionObject3D, ward: Node) -> Array:
	var out: Array = []
	if body != null:
		out.append(body.get_rid())
	_collect_body_rids(ward, out)
	return out


static func _is_ignored_wall_node(node: Node) -> bool:
	var n := node
	while n != null:
		if n.is_in_group("player") or n.is_in_group("monster") or n.is_in_group(WARD_GROUP):
			return true
		if n is CharacterBody3D:
			return true
		var name_s := str(n.name).to_lower()
		if name_s == "floor" or name_s.begins_with("floor"):
			return true
		n = n.get_parent()
	return false


static func _collect_body_rids(node: Node, out: Array) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		if child is Node:
			_collect_body_rids(child as Node, out)
