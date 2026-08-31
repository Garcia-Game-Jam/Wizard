@tool
class_name Charger
extends Monster

## Sight-cone rammer: lock-on telegraph, then a locked ram, then wall stun.

enum ChargePhase { NONE, TELEGRAPH, CHARGE, WALL_STUN, SEARCH }

const ChargerChargeScript := preload("res://scripts/monsters/charger_charge.gd")
const ChargerLaunchScript := preload("res://scripts/monsters/charger_launch.gd")
const SIGHT_SOURCE := &"sight"
const RAM_HIT_RANGE := 0.55
const RAM_WALL_RAY := 1.15
const GORE_TOSS_SPEED_RAD := 10.0
const EYE_REST := Color(0.96, 0.96, 0.94, 1.0)
const EYE_REST_ENERGY := 0.32

@export_group("Charge")
## Pose only: lock, ward, bow, turn red. Holds when the telegraph is finished.
@export_tool_button("Preview Telegraph", "Callable")
var preview_telegraph_action := preview_telegraph
## Pose only: locked red ram in place. Does not wall-stun. Does not steer.
@export_tool_button("Preview Charge", "Callable")
var preview_charge_action := preview_charge_pose
## Pose only: wall stars, then 180° about-face and a slow search sweep.
@export_tool_button("Preview Wall Stun", "Callable")
var preview_wall_stun_action := preview_wall_stun
## Pose only: turn 180°, then slowly look around for players.
@export_tool_button("Preview Search", "Callable")
var preview_search_action := preview_search
## Seconds locked on the player, bowing and turning red, before the ram.
@export_range(0.4, 3.0, 0.05, "suffix:s") var telegraph_sec: float = 1.2
## How fast it turns to face the locked player during telegraph. Lower = slower.
@export_range(0.2, 12.0, 0.1, "suffix:rad/s")
var lock_on_turn_speed_rad: float = 2.2
## How fast it turns while walking the patrol path. Lower = slower.
@export_range(0.2, 12.0, 0.1, "suffix:rad/s")
var patrol_turn_speed_rad: float = 1.4
## How fast it about-faces and sweeps during search. Lower = slower.
@export_range(0.2, 8.0, 0.1, "suffix:rad/s")
var search_turn_speed_rad: float = 1.1
## Ram speed as a multiple of player sprint. Higher = faster.
@export_range(1.5, 6.0, 0.05, "suffix:x sprint") var charge_speed_mult: float = 3.2
## Seconds stunned with orbiting stars after the ram hits a wall.
@export_range(1.0, 8.0, 0.1, "suffix:s") var self_stun_sec: float = 3.0
## Seconds of looking after the 180° about-face, before returning to patrol.
@export_range(0.6, 8.0, 0.1, "suffix:s") var search_sec: float = 3.2
## Head tuck before the ram. 360 = level, 330 = 30° down. Finishes as running starts.
@export_range(330.0, 360.0, 0.5) var charge_head_plunge_deg: float = 338.0
## Head toss (degrees up) when a player is gored during the ram.
@export_range(30.0, 90.0, 1.0) var charge_head_toss_deg: float = 60.0
## How fast the head eases back to rest after a wall (rad/s). Does not snap.
@export_range(0.4, 8.0, 0.1) var head_return_speed_rad: float = 2.8
## Body color while idle / patrol / after stun.
@export var rest_tint: Color = Color(0.22, 0.72, 0.28, 1.0)
## Body color at full telegraph and during the ram.
@export var charge_tint: Color = Color(0.88, 0.12, 0.1, 1.0)
@export_group("Knockup")
## Live: launch the nearest sandbox player along the current knockup arc.
@export_tool_button("Preview Knockup", "Callable")
var preview_knockup_action := preview_knockup
## Horizontal throw distance in maze cells (converted to launch speed).
@export_range(2, 24, 1, "suffix:cells") var knockup_cells: int = 6
## Extra height above maze walls at the apex so the hop never tunnels.
@export_range(0.8, 8.0, 0.1, "suffix:m") var knockup_over_wall_m: float = 3.5
## HP spent on a successful ram. 0 = launch only (old pit).
@export_range(0.0, 200.0, 1.0) var ram_damage: float = 40.0

var _phase: ChargePhase = ChargePhase.NONE
var _charge := ChargerChargeScript.new()
var _charge_target: Node3D = null
var _held_ward: Node = null
## Cleared at the start of each rollback tick. Not history.
var _tick_ram_hits: Dictionary = {}
var _stun_stars: Node = null
var _los_eye: Color = Color(0.95, 0.08, 0.05, 1.0)
var _body_lean: Node3D = null
var _head_lean: Node3D = null
var _head_rest_pitch: float = 0.0
var _head_pitch: float = 0.0
var _head_pitch_goal: float = 0.0
var _head_pitch_speed: float = 3.0
var _lookdev_launch_stuns: Array[Node] = []
var _search_base_yaw: float = 0.0
var _search_about_faced: bool = false
var _painted_tint: Color = Color(0, 0, 0, 0)


func _ready() -> void:
	super._ready()
	patrol_speed = ChargerLaunchScript.patrol_speed(Player.WALK_SPEED)
	_los_eye = eye_glow_color
	rest_tint = body_tint
	_body_lean = get_node_or_null("%Body") as Node3D
	_head_lean = get_node_or_null("%Head") as Node3D
	if _head_lean != null:
		_head_rest_pitch = _head_lean.rotation.x
	_stun_stars = get_node_or_null("Head/StunStars")
	_set_stun_stars(false)
	_set_chase_eyes_active(true)
	_sync_los_eyes()
	if Engine.is_editor_hint() and _phase == ChargePhase.NONE:
		_sanitize_rest_pose()
		_apply_rest_visuals()
	if bool(get_meta("lookdev_live_ai", false)):
		set_process(true)


func _sandbox_charge_tick() -> bool:
	return Engine.is_editor_hint() and bool(get_meta("lookdev_live_ai", false))


func apply_summon_appearance(tint: Color, p_eye_glow_color: Color = DEFAULT_EYE_GLOW) -> void:
	super.apply_summon_appearance(tint, p_eye_glow_color)
	rest_tint = tint
	_los_eye = p_eye_glow_color
	_sync_los_eyes()


func _on_death(from: Node3D) -> void:
	_shatter_ward()
	_set_stun_stars(false)
	super._on_death(from)


func apply_knockback(dir: Vector3, impulse: Vector3 = Vector3.ZERO) -> void:
	if _phase == ChargePhase.TELEGRAPH or _phase == ChargePhase.CHARGE:
		return
	super.apply_knockback(dir, impulse)


func _append_default_interest_candidates(_out: Array) -> void:
	## Vision cone (and weak hearing) own aggro — no wide proximity detect.
	pass


func _try_start_cast(_target: Node3D) -> bool:
	return false


func preview_telegraph() -> void:
	## Inspector pose: lock, ward, bow, turn red. Holds when finished.
	begin_lock_on(null, true)


func preview_charge_pose() -> void:
	## Inspector pose: locked red ram in place. No wall stun. No steering.
	begin_charge_now(true, null)


func preview_wall_stun() -> void:
	## Inspector pose: wall stars, then 180° about-face and a slow search.
	if not is_inside_tree() or not is_alive():
		return
	_charge.pose_only = true
	set_process(true)
	_begin_wall_stun()


func preview_search() -> void:
	## Inspector pose: turn 180°, then slowly look around. Loops until another preview.
	if not is_inside_tree() or not is_alive():
		return
	_charge.pose_only = true
	set_process(true)
	_begin_search()


func preview_knockup(player: Node3D = null) -> void:
	## Launch a playable along the knockup arc from current facing.
	if not is_inside_tree() or not is_alive():
		return
	var victim := player
	if not is_player_charge_target(victim):
		victim = _find_sandbox_player()
	if not is_player_charge_target(victim):
		return
	_charge.locked_dir = _locked_forward()
	_launch_player(victim as Node3D)


func preview_charge(target: Node3D) -> void:
	## Live lock-on toward `target` (workspace / match helpers).
	begin_lock_on(target, false)


func begin_lock_on(target: Node3D, pose_only: bool = false) -> void:
	if not is_inside_tree() or not is_alive():
		return
	if target != null and not pose_only and not is_player_charge_target(target):
		return
	lookdev_override = false
	_charge.pose_only = pose_only
	_charge.begin_telegraph()
	_phase = ChargePhase.TELEGRAPH
	_charge_target = target
	_cancel_cast()
	_clear_chase_move()
	velocity.x = 0.0
	velocity.z = 0.0
	_set_chase_eyes_active(true)
	_shatter_ward()
	_held_ward = _spawn_held_ward()
	var down := ChargerLaunchScript.plunge_pitch_rad(charge_head_plunge_deg)
	var tuck_speed := absf(down) / maxf(telegraph_sec, 0.05)
	_set_head_pitch_goal(down, maxf(tuck_speed, 0.4))
	_arm_charge_ticks(pose_only)


func begin_charge_now(pose_only: bool = false, target: Node3D = null) -> void:
	if not is_inside_tree() or not is_alive():
		return
	lookdev_override = false
	_charge.pose_only = pose_only
	if is_player_charge_target(target):
		_charge_target = target
		_snap_yaw(_flat_to_target())
	_cancel_cast()
	_clear_chase_move()
	if _held_ward == null or not is_instance_valid(_held_ward):
		_held_ward = _spawn_held_ward()
	_begin_charging()
	_arm_charge_ticks(pose_only)


func begin_wall_stun_now() -> void:
	if not is_inside_tree() or not is_alive():
		return
	lookdev_override = false
	_charge.pose_only = false
	_arm_charge_ticks(false)
	_begin_wall_stun()


func begin_search_now() -> void:
	if not is_inside_tree() or not is_alive():
		return
	lookdev_override = false
	_charge.pose_only = false
	_arm_charge_ticks(false)
	_begin_search()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_apply_rest_visuals()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_reapply_charge_visuals()


func _arm_charge_ticks(pose_only: bool) -> void:
	if pose_only or _sandbox_charge_tick():
		set_process(true)
		if pose_only:
			set_physics_process(false)
	else:
		set_physics_process(true)


func _process(delta: float) -> void:
	if GameState.is_multiplayer and not is_multiplayer_authority():
		_apply_replicated_eyes()
	if Engine.is_editor_hint():
		_tick_lookdev_launches(delta)
	if _phase == ChargePhase.NONE:
		super._process(delta)
		return
	if _charge.pose_only or _sandbox_charge_tick():
		_tick_locked_phase(delta)
		_sync_los_eyes()


func _validate_property(property: Dictionary) -> void:
	## Charger ignores kite/KEEP_AWAY timers — hide them so Combat stays readable.
	var hidden := PackedStringArray([
		"chase_style",
		"keep_away_range",
		"chase_wait_min_sec",
		"chase_wait_max_sec",
		"chase_strafe_min_sec",
		"chase_strafe_max_sec",
		"chase_retreat_min_sec",
		"chase_retreat_max_sec",
		"chase_optimal_eps",
		"face_turn_speed_rad",
	])
	if hidden.has(property.name):
		property.usage = (
			PROPERTY_USAGE_STORAGE
			| PROPERTY_USAGE_SCRIPT_VARIABLE
			| PROPERTY_USAGE_NO_EDITOR
		)


func _uses_continuous_chase_move_timer() -> bool:
	return false


func _net_state_extra() -> PackedStringArray:
	return PackedStringArray([
		":net_phase", ":net_telegraph", ":_head_pitch", "Head:rotation", "Body:rotation"
	])


func _face_horizontal(desired_vel: Vector3) -> void:
	_face_horizontal_at_speed(desired_vel, _face_delta(), patrol_turn_speed_rad)


func _physics_process(delta: float) -> void:
	if tick_death_physics_if_active(delta):
		return
	if NetClockScript.is_ticking() and get_node_or_null("RollbackSynchronizer") != null:
		_sync_charge_net_pose()
		return
	_simulate_charger(delta)


func _rollback_tick(delta: float, _tick: int, is_fresh: bool) -> void:
	if rollback_tick_death_if_active(delta):
		return
	_tick_ram_hits.clear()
	if GameState.is_multiplayer and not is_multiplayer_authority():
		_sync_charge_net_pose()
		return
	if _phase != ChargePhase.NONE:
		_simulate_charger(delta)
		return
	if is_fresh:
		_simulate_charger(delta)
		return
	_replay_restored_motion(delta)
	_sync_los_eyes()
	_sync_charge_net_pose()


func _simulate_charger(delta: float) -> void:
	_sim_delta = delta
	if not is_alive() or _charge.pose_only:
		return
	if _phase != ChargePhase.NONE:
		if _sandbox_charge_tick():
			return
		_tick_locked_phase(delta)
		_sync_los_eyes()
		_sync_charge_net_pose()
		return
	if Engine.is_editor_hint() and not bool(get_meta("lookdev_live_ai", false)):
		return
	_simulate_monster(delta)
	_sync_los_eyes()
	_sync_charge_net_pose()


func _sync_charge_net_pose() -> void:
	if GameState.is_multiplayer and not is_multiplayer_authority():
		_phase = net_phase as ChargePhase
		var tell := 0.0
		if _phase == ChargePhase.TELEGRAPH:
			tell = net_telegraph
		elif _phase == ChargePhase.CHARGE:
			tell = 1.0
		_apply_charge_tint(tell)
		return
	net_phase = int(_phase)
	if _phase == ChargePhase.TELEGRAPH:
		net_telegraph = _charge.telegraph_progress(telegraph_sec)
	else:
		net_telegraph = 0.0


func _tick_chase(delta: float) -> void:
	if not _interest_is_actionable(_interest):
		super._tick_chase(delta)
		return
	if _interest_source() == SIGHT_SOURCE:
		var target := get_chase_target()
		if is_player_charge_target(target):
			begin_lock_on(target, false)
			return
	super._tick_chase(delta)


func _tick_locked_phase(delta: float) -> void:
	if not _charge.pose_only:
		if _sandbox_charge_tick():
			velocity.y = 0.0
		elif not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
	match _phase:
		ChargePhase.TELEGRAPH:
			_tick_telegraph(delta)
		ChargePhase.CHARGE:
			_tick_charging(delta)
		ChargePhase.WALL_STUN:
			_tick_wall_stun(delta)
		ChargePhase.SEARCH:
			_tick_search(delta)
	if _phase != ChargePhase.SEARCH:
		_tick_head_pitch(delta)
	if _charge.pose_only:
		return
	if _sandbox_charge_tick():
		if _phase == ChargePhase.CHARGE:
			velocity.y = 0.0
			global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
			_try_ram_contacts()
			_sync_ram_ghosts()
		else:
			MonsterAIScript.apply_move(self, delta)
		return
	NetClockScript.move_character(self)
	if _phase == ChargePhase.CHARGE:
		_try_ram_contacts()
		_sync_ram_ghosts()


func _tick_telegraph(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_charge.tick(delta)
	if not _charge.pose_only:
		if not _target_is_valid():
			_reset_to_idle()
			return
		_face_horizontal_at_speed(_flat_to_target(), delta, lock_on_turn_speed_rad)
	var t := _charge.telegraph_progress(telegraph_sec)
	_apply_charge_tint(t)
	_set_body_lean(t * 0.28)
	var plunge := ChargerLaunchScript.plunge_pitch_rad(charge_head_plunge_deg)
	if (
		not _charge.pose_only
		and _charge.telegraph_ready(telegraph_sec, _head_pitch, plunge)
	):
		_begin_charging()


func _begin_charging() -> void:
	_phase = ChargePhase.CHARGE
	_charge.begin_charge(_locked_forward())
	_clear_ram_ghosts()
	_tick_ram_hits.clear()
	_apply_charge_tint(1.0)
	_set_body_lean(0.32)
	var plunge := ChargerLaunchScript.plunge_pitch_rad(charge_head_plunge_deg)
	_head_pitch = plunge
	_set_head_pitch_goal(plunge, 8.0)
	_apply_head_pitch()
	if _charge.pose_only:
		velocity.x = 0.0
		velocity.z = 0.0


func _tick_charging(delta: float) -> void:
	_charge.tick(delta)
	_apply_charge_tint(1.0)
	_set_body_lean(0.32)
	if _charge.pose_only:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var speed := ChargerChargeScript.charge_speed(
		Player.SPRINT_SPEED, charge_speed_mult
	)
	var ram := _charge.charge_velocity(speed)
	velocity.x = ram.x
	velocity.z = ram.z
	_face_horizontal_at_speed(_charge.locked_dir, delta, lock_on_turn_speed_rad * 4.0)


func _begin_wall_stun() -> void:
	_clear_ram_ghosts()
	_shatter_ward()
	_phase = ChargePhase.WALL_STUN
	_charge.begin_wall_stun()
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_charge_tint(0.0)
	_set_body_lean(0.0)
	_set_head_pitch_goal(0.0, head_return_speed_rad)
	_set_stun_stars(true)


func _tick_wall_stun(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_charge.tick(delta)
	if _charge.wall_stun_ready(self_stun_sec):
		_begin_search()


func _begin_search() -> void:
	_shatter_ward()
	_set_stun_stars(false)
	_apply_charge_tint(0.0)
	_set_body_lean(0.0)
	_phase = ChargePhase.SEARCH
	_charge.begin_search()
	_search_base_yaw = rotation.y
	_search_about_faced = false
	_charge_target = null
	_interest = null
	velocity.x = 0.0
	velocity.z = 0.0
	_set_chase_eyes_active(true)


func _tick_search(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not _search_about_faced:
		_tick_search_about_face(delta)
		return
	_charge.tick(delta)
	var yaw_off := ChargerChargeScript.search_yaw_offset(
		_charge.age,
		ChargerChargeScript.SEARCH_YAW_AMP_RAD,
		ChargerChargeScript.SEARCH_YAW_HZ
	)
	var sweep := ChargerChargeScript.heading_from_yaw(_search_base_yaw + yaw_off)
	_face_horizontal_at_speed(sweep, delta, search_turn_speed_rad)
	_head_pitch = ChargerChargeScript.search_head_pitch(
		_charge.age,
		ChargerChargeScript.SEARCH_PITCH_AMP_RAD,
		ChargerChargeScript.SEARCH_YAW_HZ
	)
	_apply_head_pitch()
	if _charge.pose_only:
		return
	if _try_search_lock():
		return
	if _charge.search_ready(search_sec):
		_finish_search_to_patrol()


func _tick_search_about_face(delta: float) -> void:
	var back := ChargerChargeScript.about_face_heading(_search_base_yaw)
	_face_horizontal_at_speed(back, delta, search_turn_speed_rad)
	_head_pitch = 0.0
	_apply_head_pitch()
	if not ChargerChargeScript.about_face_done(rotation.y, _search_base_yaw):
		return
	_search_about_faced = true
	_search_base_yaw = rotation.y
	_charge.age = 0.0


func _try_search_lock() -> bool:
	_interest = _gather_interest()
	if _interest_source() != SIGHT_SOURCE:
		return false
	var target := get_chase_target()
	if not is_player_charge_target(target):
		return false
	begin_lock_on(target, false)
	return true


func _finish_search_to_patrol() -> void:
	_shatter_ward()
	_set_stun_stars(false)
	_apply_charge_tint(0.0)
	_set_body_lean(0.0)
	_head_pitch = 0.0
	_head_pitch_goal = 0.0
	_apply_head_pitch()
	_phase = ChargePhase.NONE
	_charge.reset()
	_charge_target = null
	_clear_ram_ghosts()
	_tick_ram_hits.clear()
	_begin_patrol()


func _reset_to_idle() -> void:
	_shatter_ward()
	_set_stun_stars(false)
	_apply_charge_tint(0.0)
	_set_body_lean(0.0)
	_head_pitch = 0.0
	_head_pitch_goal = 0.0
	_apply_head_pitch()
	_phase = ChargePhase.NONE
	_charge.reset()
	_charge_target = null
	_clear_ram_ghosts()
	_tick_ram_hits.clear()
	_enter_idle()


func _spawn_held_ward() -> Node:
	var ability := _charge_ward_ability()
	if ability != null and ability.has_method("spawn_held_ward"):
		return ability.call("spawn_held_ward", self)
	return null


func _charge_ward_ability() -> Node:
	for ability in get_combat_abilities():
		if str(ability.get("ability_id")) == "charger_ward":
			return ability
	var abilities := get_combat_abilities()
	if abilities.is_empty():
		return null
	return abilities[0]


func _shatter_ward() -> void:
	if _held_ward != null and is_instance_valid(_held_ward):
		if _held_ward.has_method("shatter"):
			_held_ward.call("shatter")
		else:
			_held_ward.queue_free()
	_held_ward = null


func _try_ram_contacts() -> void:
	var hit_wall := false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Node:
			var corpse := Corpse.resolve_from(collider as Node)
			if corpse != null:
				Corpse.ram_if_new(corpse, _tick_ram_hits, _ram_launch_velocity())
			else:
				_try_hit_player(collider as Node)
		if (
			_charge.can_read_walls()
			and ChargerChargeScript.is_wall_collider(collider, col.get_normal())
		):
			hit_wall = true
	_try_ram_proximity_hit()
	if hit_wall:
		_begin_wall_stun()
		return
	if _sandbox_charge_tick():
		_try_editor_wall_stun()


func _try_ram_proximity_hit() -> void:
	if _target_is_valid() and _flat_to_target().length() <= RAM_HIT_RANGE:
		_try_hit_player(_charge_target)
		Corpse.ram_nearby(self, RAM_HIT_RANGE, _tick_ram_hits, _ram_launch_velocity())
		return
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("player"):
		if not (node is Node3D):
			continue
		var body := node as Node3D
		if not is_player_charge_target(body):
			continue
		var flat := Vector3(
			body.global_position.x - global_position.x,
			0.0,
			body.global_position.z - global_position.z
		)
		if flat.length() <= RAM_HIT_RANGE:
			_try_hit_player(body)
	Corpse.ram_nearby(self, RAM_HIT_RANGE, _tick_ram_hits, _ram_launch_velocity())


func _try_editor_wall_stun() -> void:
	if not _charge.can_read_walls():
		return
	var world := get_world_3d()
	if world == null:
		return
	var from := global_position + Vector3(0.0, 0.45, 0.0)
	var ahead := from + _charge.locked_dir * RAM_WALL_RAY
	var exclude: Array = ChargerChargeScript.collect_wall_excludes(self, _held_ward)
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("player"):
			if node is CollisionObject3D:
				exclude.append((node as CollisionObject3D).get_rid())
	var hit_dist := MonsterSightSense.occlude_distance(world, from, ahead, exclude)
	if hit_dist + 0.02 < from.distance_to(ahead):
		_begin_wall_stun()


func _try_hit_corpse(body: Node) -> void:
	Corpse.ram_if_new(
		Corpse.resolve_from(body), _tick_ram_hits, _ram_launch_velocity()
	)


func _try_hit_player(body: Node) -> void:
	var victim := resolve_playable_hit_body(body)
	if victim == null or victim == self:
		return
	if victim.has_method("is_stunned") and bool(victim.call("is_stunned")):
		_ghost_ram_victim(victim)
		return
	var id := victim.get_instance_id()
	if _tick_ram_hits.has(id):
		return
	_tick_ram_hits[id] = true
	_begin_player_gore_pose()
	_launch_player(victim as Node3D)
	if victim.has_method("is_stunned") and bool(victim.call("is_stunned")):
		_ghost_ram_victim(victim)


func _begin_player_gore_pose() -> void:
	_set_head_pitch_goal(
		ChargerLaunchScript.toss_pitch_rad(charge_head_toss_deg), GORE_TOSS_SPEED_RAD
	)


func _ram_launch_velocity() -> Vector3:
	var away := _charge.locked_dir
	if away.length_squared() < 0.0001:
		away = _locked_forward()
	var wall_h := ChargerLaunchScript.wall_height_from_node(self)
	var cell_size := ChargerLaunchScript.cell_size_from_node(self)
	return ChargerLaunchScript.knockup_velocity(
		away,
		gravity,
		wall_h,
		knockup_over_wall_m,
		ChargerLaunchScript.horiz_speed(knockup_cells, cell_size),
		_rng
	)


func _launch_player(player: Node3D) -> void:
	_apply_player_hit(player, _ram_launch_velocity())


func _apply_player_hit(player: Node, launch_vel: Vector3) -> void:
	if player is Character:
		var ram := CombatPayload.new()
		if ram_damage > 0.0:
			ram.effects.append(Damage.with(ram_damage))
		ram.effects.append(Knock.with(launch_vel))
		ram.effects.append(Stun.with(launch_vel))
		(player as Character).apply(self, ram)
	if player is Character and not (player as Character).is_alive():
		return
	var stun := player.get_node_or_null("Stun")
	if stun == null:
		return
	if Engine.is_editor_hint() and not _lookdev_launch_stuns.has(stun):
		_lookdev_launch_stuns.append(stun)


func _ghost_ram_victim(victim: Node) -> void:
	if victim == null or not (victim is CollisionObject3D):
		return
	var body := victim as CollisionObject3D
	add_collision_exception_with(body)
	body.add_collision_exception_with(self)


func _unghost_ram_victim(victim: Node) -> void:
	if victim == null or not (victim is CollisionObject3D):
		return
	var body := victim as CollisionObject3D
	remove_collision_exception_with(body)
	body.remove_collision_exception_with(self)


func _sync_ram_ghosts() -> void:
	if not is_inside_tree():
		return
	var charging := _phase == ChargePhase.CHARGE
	for node in get_tree().get_nodes_in_group("player"):
		if not (node is CollisionObject3D):
			continue
		var stunned := node.has_method("is_stunned") and bool(node.call("is_stunned"))
		if charging and stunned:
			_ghost_ram_victim(node)
		else:
			_unghost_ram_victim(node)


func _clear_ram_ghosts() -> void:
	for other in get_collision_exceptions():
		if not (other is Node) or not (other as Node).is_in_group("player"):
			continue
		remove_collision_exception_with(other)
		if other is CollisionObject3D:
			(other as CollisionObject3D).remove_collision_exception_with(self)


func _tick_lookdev_launches(delta: float) -> void:
	var i := _lookdev_launch_stuns.size() - 1
	while i >= 0:
		var stun := _lookdev_launch_stuns[i]
		if stun == null or not is_instance_valid(stun):
			_lookdev_launch_stuns.remove_at(i)
		elif stun.has_method("is_stunned") and not bool(stun.call("is_stunned")):
			_lookdev_launch_stuns.remove_at(i)
		elif stun.has_method("tick_physics"):
			var body := stun.get_parent()
			stun.call("tick_physics", body, delta, gravity)
			if body is CharacterBody3D:
				(body as CharacterBody3D).move_and_slide()
			if stun.has_method("after_slide"):
				stun.call("after_slide", body)
		i -= 1


func _find_sandbox_player() -> Node3D:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("player"):
		if is_player_charge_target(node) and node is Node3D:
			return node as Node3D
	return null


func _interest_source() -> StringName:
	if _interest == null:
		return &""
	return _interest.get("source") as StringName


func _target_is_valid() -> bool:
	## Freed refs are not null — check before any typed Node param call.
	if not is_instance_valid(_charge_target):
		_charge_target = null
		return false
	return is_player_charge_target(_charge_target)


static func is_player_charge_target(node: Node) -> bool:
	## Charge only at living Player.
	if node == null or not is_instance_valid(node):
		return false
	if not node.is_in_group("player"):
		return false
	if not Character.is_node_alive(node):
		return false
	if node is Player:
		return true
	return script_extends_player(node.get_script() as Script)


static func resolve_playable_hit_body(node: Node) -> Node:
	var n := node
	while n != null:
		if is_player_charge_target(n):
			return n
		n = n.get_parent()
	return null


static func script_extends_player(scr: Script) -> bool:
	while scr != null:
		if scr.resource_path.ends_with("player.gd"):
			return true
		scr = scr.get_base_script()
	return false


func _flat_to_target() -> Vector3:
	if not _target_is_valid():
		return _charge.locked_dir
	return Vector3(
		_charge_target.global_position.x - global_position.x,
		0.0,
		_charge_target.global_position.z - global_position.z
	)


func _locked_forward() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _snap_yaw(desired: Vector3) -> void:
	var flat := Vector3(desired.x, 0.0, desired.z)
	if flat.length_squared() < 0.0001:
		return
	var at := global_position + flat
	if global_position.distance_squared_to(at) > 0.0001:
		look_at(at, Vector3.UP)


func _apply_charge_tint(t: float) -> void:
	var next := rest_tint.lerp(charge_tint, clampf(t, 0.0, 1.0))
	if _painted_tint.is_equal_approx(next):
		return
	_painted_tint = next
	body_tint = next


func _set_chase_eyes_active(_active: bool) -> void:
	## White eyes stay visible; red glow is LOS, not the generic chase hide/show.
	super._set_chase_eyes_active(true)


func _apply_eye_glow_from_health() -> void:
	if eye_glow_color.is_equal_approx(EYE_REST):
		_apply_eye_glow_color(EYE_REST, EYE_REST_ENERGY)
		return
	super._apply_eye_glow_from_health()


func _sync_los_eyes() -> void:
	var want := _los_eye if _has_los_lock() else EYE_REST
	if not eye_glow_color.is_equal_approx(want):
		eye_glow_color = want


func _has_los_lock() -> bool:
	if _phase == ChargePhase.TELEGRAPH or _phase == ChargePhase.CHARGE:
		return true
	if _phase == ChargePhase.WALL_STUN:
		return false
	return _interest_source() == SIGHT_SOURCE


func _set_body_lean(pitch: float) -> void:
	if _body_lean != null:
		_body_lean.rotation.x = pitch * 0.4


func _sanitize_rest_pose() -> void:
	## Editor saves can bake windup into Head/Body. Rest is untilted.
	if _head_lean != null and absf(_head_lean.rotation.x) > deg_to_rad(25.0):
		_head_lean.rotation.x = 0.0
		_head_rest_pitch = 0.0
	if _body_lean != null and absf(_body_lean.rotation.x) > 0.2:
		_body_lean.rotation.x = 0.0


func _apply_rest_visuals() -> void:
	_set_body_lean(0.0)
	_head_pitch = 0.0
	_head_pitch_goal = 0.0
	_apply_head_pitch()
	_apply_charge_tint(0.0)


func _reapply_charge_visuals() -> void:
	if _phase == ChargePhase.NONE:
		return
	if _phase == ChargePhase.TELEGRAPH:
		var t := _charge.telegraph_progress(telegraph_sec)
		_apply_charge_tint(t)
		_set_body_lean(t * 0.28)
	elif _phase == ChargePhase.CHARGE:
		_apply_charge_tint(1.0)
		_set_body_lean(0.32)
	else:
		_apply_charge_tint(0.0)
		_set_body_lean(0.0)
	_apply_head_pitch()


func _set_head_pitch_goal(offset_rad: float, speed_rad: float) -> void:
	_head_pitch_goal = offset_rad
	_head_pitch_speed = maxf(speed_rad, 0.05)


func _tick_head_pitch(delta: float) -> void:
	if is_equal_approx(_head_pitch, _head_pitch_goal):
		return
	_head_pitch = move_toward(_head_pitch, _head_pitch_goal, _head_pitch_speed * delta)
	_apply_head_pitch()


func _apply_head_pitch() -> void:
	if _head_lean != null:
		_head_lean.rotation.x = _head_rest_pitch + _head_pitch


func _set_stun_stars(on: bool) -> void:
	if not is_instance_valid(_stun_stars):
		_stun_stars = null
		return
	if _stun_stars.has_method("set_active"):
		_stun_stars.call("set_active", on)
