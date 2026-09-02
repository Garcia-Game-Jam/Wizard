class_name ChargerPursuit
extends RefCounted

## The Charger's hunt loop: stalk the player, feint, ram, then either wall-stun
## (dodged into an open lane) or skid-recover (whiffed) and search. Split out of
## charger.gd so the scene script stays focused on pose / net / telegraph.
## Every entry point takes the live Charger; state lives on the Charger and its
## `_charge` (ChargerCharge) helper so rollback resim stays deterministic.

const ChargerChargeScript := preload("res://scripts/monsters/charger_charge.gd")
const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")


## --- Stalk: prowl toward the player, wait for a clean charge lane ---

static func begin_stalk(c: Charger, target: Node3D) -> void:
	c.lookdev_override = false
	c._phase = Charger.ChargePhase.STALK
	c._charge.begin_stalk()
	c._charge_target = target
	c._telegraph_scale = 1.0
	c._stalk_lost_sec = 0.0
	c._stalk_dwell = 0.0
	c._stalk_still_sec = 0.0
	c._stalk_feint_planned = c._charge.roll_feint(c._rng, c.feint_chance)
	if is_instance_valid(target):
		c._stalk_last_target_pos = target.global_position
	c._cancel_cast()
	c._clear_chase_move()
	c._shatter_ward()
	c._apply_charge_tint(0.0)
	c._set_body_lean(0.0)
	c._set_head_pitch_goal(0.0, c.head_return_speed_rad)
	c._set_chase_eyes_active(true)


static func tick_stalk(c: Charger, delta: float) -> void:
	c._charge.tick(delta)
	if c._charge.pose_only:
		c.velocity.x = 0.0
		c.velocity.z = 0.0
		return
	var target := reacquire_sight_target(c)
	if not Charger.is_player_charge_target(target):
		c._stalk_lost_sec += delta
		var brake := c.combat_speed(c.stalk_speed) * delta * 4.0
		c.velocity.x = move_toward(c.velocity.x, 0.0, brake)
		c.velocity.z = move_toward(c.velocity.z, 0.0, brake)
		if c._stalk_lost_sec >= c.lost_chase_to_alert_sec * 0.5:
			c._reset_to_idle()
		return
	c._stalk_lost_sec = 0.0
	c._charge_target = target

	var tp := target.global_position
	var flat := Vector3(tp.x - c.global_position.x, 0.0, tp.z - c.global_position.z)
	var dist := flat.length()
	c._face_horizontal_at_speed(flat, delta, c.lock_on_turn_speed_rad * 1.6)

	var lane_clear := lane_to_target_clear(c, flat)
	var in_band := ChargerChargeScript.in_charge_band(
		dist, c.charge_band_min_m, c.charge_band_max_m
	)
	if in_band and lane_clear:
		c._stalk_dwell += delta
	else:
		c._stalk_dwell = 0.0

	var moved := c._stalk_last_target_pos.distance_to(tp)
	c._stalk_last_target_pos = tp
	if moved <= c.combat_speed(c.stalk_speed) * delta * 0.35:
		c._stalk_still_sec += delta
	else:
		c._stalk_still_sec = 0.0

	var ready := in_band and lane_clear and c._stalk_dwell >= c.stalk_dwell_sec
	var impatient := in_band and lane_clear and c._stalk_still_sec >= c.stalk_patience_sec
	if ready or impatient:
		enter_charge_sequence(c, target)
		return

	_drive_stalk_move(c, flat, dist)


static func _drive_stalk_move(c: Charger, flat: Vector3, dist: float) -> void:
	var spd := c.combat_speed(c.stalk_speed)
	var dir := Vector3.ZERO
	if flat.length_squared() > 0.0001:
		var to := flat.normalized()
		if dist > c.charge_band_max_m:
			dir = to
		elif dist < c.charge_band_min_m:
			dir = -to * 0.7
		else:
			var anchor := c.global_position + flat
			var side := MonsterAIScript.strafe_sign_further_from_player(
				c.global_position, anchor
			)
			dir = MonsterAIScript.angled_strafe_dir(c.global_position, anchor, side, 0.2) * 0.85
	c.velocity.x = dir.x * spd
	c.velocity.z = dir.z * spd


static func enter_charge_sequence(c: Charger, target: Node3D) -> void:
	if c._stalk_feint_planned and not c._charge.feint_used:
		begin_feint(c, target)
		return
	c.begin_lock_on(target, false)


## --- Feint: short fake windup + hop, then resolve into a real telegraph ---

static func begin_feint(c: Charger, target: Node3D) -> void:
	c.lookdev_override = false
	c._phase = Charger.ChargePhase.FEINT
	c._charge.begin_feint()
	if Charger.is_player_charge_target(target):
		c._charge_target = target
		c._snap_yaw(c._flat_to_target())
	c._cancel_cast()
	c._clear_chase_move()
	c._apply_charge_tint(0.4)
	c._set_body_lean(0.12)


static func tick_feint(c: Charger, delta: float) -> void:
	c._charge.tick(delta)
	var t := c._charge.telegraph_progress(ChargerChargeScript.DEFAULT_FEINT_SEC)
	c._apply_charge_tint(0.15 + 0.35 * (1.0 - t))
	c._set_body_lean(0.12 * (1.0 - t))
	if not c._charge.pose_only and c._target_is_valid():
		c._face_horizontal_at_speed(c._flat_to_target(), delta, c.lock_on_turn_speed_rad)
	if t < 0.5 and not c._charge.pose_only:
		var f := c._locked_forward()
		c.velocity.x = f.x * ChargerChargeScript.FEINT_HOP_SPEED
		c.velocity.z = f.z * ChargerChargeScript.FEINT_HOP_SPEED
	else:
		c.velocity.x = 0.0
		c.velocity.z = 0.0
	if c._charge.pose_only:
		return
	if c._charge.feint_ready(ChargerChargeScript.DEFAULT_FEINT_SEC):
		if c._target_is_valid():
			c.begin_lock_on(c._charge_target, false)
		else:
			c._reset_to_idle()


## --- Recover: vulnerable skid-stop after a whiffed charge (no wall needed) ---

static func begin_recover(c: Charger) -> void:
	c._clear_ram_ghosts()
	c._shatter_ward()
	c._phase = Charger.ChargePhase.RECOVER
	c._charge.begin_recover()
	c._recover_double_planned = ChargerChargeScript.roll_chance(c._rng, c.double_charge_chance)
	c._apply_charge_tint(0.0)
	c._set_body_lean(0.16)
	c._set_head_pitch_goal(0.0, c.head_return_speed_rad)


static func tick_recover(c: Charger, delta: float) -> void:
	c._charge.tick(delta)
	var t := c._charge.telegraph_progress(c.recover_sec)
	c._set_body_lean(0.16 * (1.0 - t))
	c.velocity.x = move_toward(c.velocity.x, 0.0, delta * 22.0)
	c.velocity.z = move_toward(c.velocity.z, 0.0, delta * 22.0)
	if c._charge.pose_only:
		return
	if not c._charge.recover_ready(c.recover_sec):
		return
	var target := reacquire_sight_target(c)
	if Charger.is_player_charge_target(target):
		c._charge_target = target
		if c._recover_double_planned:
			c._snap_yaw(c._flat_to_target())
			c.begin_lock_on(target, false, 0.45)
		else:
			begin_stalk(c, target)
		return
	begin_search(c)


## --- Wall stun: the dodged-into-open-lane reward window ---

static func begin_wall_stun(c: Charger) -> void:
	c._clear_ram_ghosts()
	c._shatter_ward()
	c._phase = Charger.ChargePhase.WALL_STUN
	c._charge.begin_wall_stun()
	c.velocity.x = 0.0
	c.velocity.z = 0.0
	c._apply_charge_tint(0.0)
	c._set_body_lean(0.0)
	c._set_head_pitch_goal(0.0, c.head_return_speed_rad)
	c._set_stun_stars(true)


static func tick_wall_stun(c: Charger, delta: float) -> void:
	c.velocity.x = 0.0
	c.velocity.z = 0.0
	c._charge.tick(delta)
	if c._charge.wall_stun_ready(c.self_stun_sec):
		begin_search(c)


## --- Search: about-face then sweep, relock on sight ---

static func begin_search(c: Charger) -> void:
	c._shatter_ward()
	c._set_stun_stars(false)
	c._apply_charge_tint(0.0)
	c._set_body_lean(0.0)
	c._phase = Charger.ChargePhase.SEARCH
	c._charge.begin_search()
	c._search_base_yaw = c.rotation.y
	c._search_about_faced = false
	c._charge_target = null
	c._interest = null
	c.velocity.x = 0.0
	c.velocity.z = 0.0
	c._set_chase_eyes_active(true)


static func tick_search(c: Charger, delta: float) -> void:
	c.velocity.x = 0.0
	c.velocity.z = 0.0
	if not c._search_about_faced:
		_tick_search_about_face(c, delta)
		return
	c._charge.tick(delta)
	var yaw_off := ChargerChargeScript.search_yaw_offset(
		c._charge.age, ChargerChargeScript.SEARCH_YAW_AMP_RAD, ChargerChargeScript.SEARCH_YAW_HZ
	)
	var sweep := ChargerChargeScript.heading_from_yaw(c._search_base_yaw + yaw_off)
	c._face_horizontal_at_speed(sweep, delta, c.search_turn_speed_rad)
	c._head_pitch = ChargerChargeScript.search_head_pitch(
		c._charge.age, ChargerChargeScript.SEARCH_PITCH_AMP_RAD, ChargerChargeScript.SEARCH_YAW_HZ
	)
	c._apply_head_pitch()
	if c._charge.pose_only:
		return
	if try_search_lock(c):
		return
	if c._charge.search_ready(c.search_sec):
		finish_search_to_patrol(c)


static func _tick_search_about_face(c: Charger, delta: float) -> void:
	var back := ChargerChargeScript.about_face_heading(c._search_base_yaw)
	c._face_horizontal_at_speed(back, delta, c.search_turn_speed_rad)
	c._head_pitch = 0.0
	c._apply_head_pitch()
	if not ChargerChargeScript.about_face_done(c.rotation.y, c._search_base_yaw):
		return
	c._search_about_faced = true
	c._search_base_yaw = c.rotation.y
	c._charge.age = 0.0


static func try_search_lock(c: Charger) -> bool:
	var target := reacquire_sight_target(c)
	if not Charger.is_player_charge_target(target):
		return false
	begin_stalk(c, target)
	return true


static func finish_search_to_patrol(c: Charger) -> void:
	c._shatter_ward()
	c._set_stun_stars(false)
	c._apply_charge_tint(0.0)
	c._set_body_lean(0.0)
	c._head_pitch = 0.0
	c._head_pitch_goal = 0.0
	c._apply_head_pitch()
	c._phase = Charger.ChargePhase.NONE
	c._charge.reset()
	c._telegraph_scale = 1.0
	c._charge_target = null
	c._clear_ram_ghosts()
	c._tick_ram_hits.clear()
	c._begin_patrol()


## --- Ram contact / wall / whiff detection ---

static func try_ram_contacts(c: Charger) -> void:
	for i in c.get_slide_collision_count():
		var col := c.get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Node:
			var corpse := Corpse.resolve_from(collider as Node)
			if corpse != null:
				Corpse.ram_if_new(corpse, c._tick_ram_hits, c._ram_launch_velocity())
			else:
				c._try_hit_player(collider as Node)
	try_ram_proximity_hit(c)
	if not c._charge.can_read_walls():
		return
	## Wall detection does not trust the substepped slide list: sweep the capsule
	## one ram-step ahead, plus a stall fallback for wedged-in-a-corner cases.
	if probe_wall_ahead(c) or charge_stalled(c):
		begin_wall_stun(c)
		return
	if ChargerChargeScript.whiffed(charge_travelled(c), c.charge_max_dist_m):
		begin_recover(c)


static func try_ram_proximity_hit(c: Charger) -> void:
	var range_m := c.RAM_HIT_RANGE
	if c._target_is_valid() and c._flat_to_target().length() <= range_m:
		c._try_hit_player(c._charge_target)
		Corpse.ram_nearby(c, range_m, c._tick_ram_hits, c._ram_launch_velocity())
		return
	if not c.is_inside_tree():
		return
	for node in c.get_tree().get_nodes_in_group("player"):
		if not (node is Node3D):
			continue
		var body := node as Node3D
		if not Charger.is_player_charge_target(body):
			continue
		var flat := Vector3(
			body.global_position.x - c.global_position.x,
			0.0,
			body.global_position.z - c.global_position.z
		)
		if flat.length() <= range_m:
			c._try_hit_player(body)
	Corpse.ram_nearby(c, range_m, c._tick_ram_hits, c._ram_launch_velocity())


static func charge_radius(c: Charger) -> float:
	var col := c.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is CapsuleShape3D:
		return maxf((col.shape as CapsuleShape3D).radius, 0.05)
	return 0.25


static func charge_travelled(c: Charger) -> float:
	return Vector3(
		c.global_position.x - c._charge_start_pos.x,
		0.0,
		c.global_position.z - c._charge_start_pos.z
	).length()


## Sweep the real capsule one ram-step ahead. Independent of the slide list and
## of floor_block_on_wall, so it fires the same on every peer and under resim.
static func probe_wall_ahead(c: Charger) -> bool:
	if not c.is_inside_tree():
		return false
	var dir := c._charge.locked_dir
	if dir.length_squared() < 0.0001:
		return false
	var step := ChargerChargeScript.charge_speed(Player.SPRINT_SPEED, c.charge_speed_mult)
	step *= maxf(c._sim_delta, 1.0 / 60.0)
	var reach := maxf(charge_radius(c) + step + 0.08, 0.2)
	var probe := KinematicCollision3D.new()
	if not c.test_move(c.global_transform, dir.normalized() * reach, probe):
		return false
	return ChargerChargeScript.is_wall_collider(probe.get_collider(), probe.get_normal())


## Belt-and-suspenders: several ticks of near-zero forward progress = wedged.
static func charge_stalled(c: Charger) -> bool:
	var moved := Vector3(
		c.global_position.x - c._charge_prev_pos.x,
		0.0,
		c.global_position.z - c._charge_prev_pos.z
	).length()
	c._charge_prev_pos = c.global_position
	var intended := ChargerChargeScript.charge_speed(
		Player.SPRINT_SPEED, c.charge_speed_mult
	) * maxf(c._sim_delta, 1.0 / 60.0)
	if intended <= 0.001:
		return false
	if moved < intended * ChargerChargeScript.STALL_PROGRESS_FRAC:
		c._charge_stall_ticks += 1
	else:
		c._charge_stall_ticks = 0
	return c._charge_stall_ticks >= ChargerChargeScript.STALL_TICKS


static func reacquire_sight_target(c: Charger) -> Node3D:
	c._interest = c._gather_interest()
	if c._interest_source() != Charger.SIGHT_SOURCE:
		return null
	var target := c.get_chase_target()
	if not Charger.is_player_charge_target(target):
		return null
	return target


static func lane_to_target_clear(c: Charger, flat_to_target: Vector3) -> bool:
	if not c.is_inside_tree():
		return true
	var world := c.get_world_3d()
	if world == null:
		return true
	var flat := Vector3(flat_to_target.x, 0.0, flat_to_target.z)
	var span := flat.length()
	if span < 0.2:
		return true
	var from := c.global_position + Vector3(0.0, 0.45, 0.0)
	var to := from + flat
	var exclude: Array = ChargerChargeScript.collect_wall_excludes(c, c._held_ward)
	for node in c.get_tree().get_nodes_in_group("player"):
		if node is CollisionObject3D:
			exclude.append((node as CollisionObject3D).get_rid())
	var hit_dist := MonsterSightSense.occlude_distance(world, from, to, exclude)
	return hit_dist + 0.5 >= span
