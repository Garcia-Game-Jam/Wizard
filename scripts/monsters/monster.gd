@tool
class_name Monster
extends Character

## Combat-ready AI. Senses → IDLE/PATROL/CHASE/ALERT. Eyes glow while chasing.

enum ChaseStyle { CLOSE_IN, KEEP_AWAY }

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")
const MonsterCorpseScript := preload("res://scripts/monsters/monster_corpse.gd")
const MonsterChaseMoveScript := preload("res://scripts/monsters/monster_chase_move.gd")
const MonsterCombatSpacingScript := preload("res://scripts/monsters/monster_combat_spacing.gd")
const MonsterCasterCombatScript := preload("res://scripts/monsters/monster_caster_combat.gd")
const MonsterRangeGizmosScript := preload("res://scripts/monsters/monster_range_gizmos.gd")
const MonsterPatrolScript := preload("res://scripts/monsters/monster_patrol.gd")
const Profiles := preload("res://scripts/net/net_rewindable_profiles.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")

const DEFAULT_TINT := Color(0.72, 0.28, 0.22, 1.0)
const DEFAULT_PLAYER_SOURCE := &"player"
const DEATH_IMPULSE_SCALE := 1.35
const RANGE_DISC_HEIGHT := 0.02

@export_group("Appearance")
@export var body_tint: Color = DEFAULT_TINT:
	set(value):
		if body_tint.is_equal_approx(value):
			return
		body_tint = value
		if is_inside_tree():
			_refresh_appearance()

@export_group("Lookdev")
## When true, lookdev_pose drives eyes instead of live AI (workspace / editor preview).
@export var lookdev_override: bool = false:
	set(value):
		lookdev_override = value
		if is_inside_tree():
			_refresh_lookdev_eyes()

## Patrol hides chase eyes; Chase shows them. Workspace pose buttons set this.
@export var lookdev_pose: MonsterAIScript.LookdevPose = MonsterAIScript.LookdevPose.PATROL:
	set(value):
		lookdev_pose = value
		if is_inside_tree():
			_refresh_lookdev_eyes()

@export_group("Gizmos")
## Orange chase disc and yellow attack disc (meters = Combat chase/attack range).
@export var show_combat_ranges: bool = false:
	set(value):
		show_combat_ranges = value
		if is_inside_tree():
			_refresh_range_gizmos()

## Cyan hearing, green sight, yellow light, LOS ray — reads live Senses/ children.
@export var show_sense_ranges: bool = false:
	set(value):
		show_sense_ranges = value
		if is_inside_tree():
			var giz := get_node_or_null("SenseGizmos") as MonsterSenseGizmos
			if giz != null:
				giz.sync_enabled(value)

@export_group("Combat")
@export var move_speed: float = 3.2
@export var chase_range: float = 12.0:
	set(value):
		chase_range = value
		if is_inside_tree() and show_combat_ranges:
			_refresh_range_gizmos()

@export var attack_range: float = 1.4:
	set(value):
		attack_range = value
		if is_inside_tree() and show_combat_ranges:
			_refresh_range_gizmos()

@export var touch_damage: float = 8.0
@export var gravity: float = 18.0
@export var idle_duration_sec: float = 1.2
@export var patrol_speed: float = 2.4
@export var patrol_radius: float = 8.0
## After chase loses all sight/hearing interest for this long → ALERT.
@export_range(0.5, 30.0, 0.25) var lost_chase_to_alert_sec: float = 4.0
## How long ALERT lasts with no detection before returning to PATROL.
@export_range(1.0, 60.0, 0.25) var alert_duration_sec: float = 12.0
@export var death_linger_sec: float = 30.0
@export var death_fade_sec: float = 3.0
## CLOSE_IN rushes melee. KEEP_AWAY holds at keep_away_range.
@export var chase_style: ChaseStyle = ChaseStyle.CLOSE_IN
@export_range(1.0, 40.0, 0.5) var keep_away_range: float = 20.0
## Yaw turn rate (rad/s). Fast default so retreat/re-face reads as fluid.
@export_range(1.0, 24.0, 0.1) var face_turn_speed_rad: float = 10.0

@export_group("Chase move")
@export_range(0.25, 10.0, 0.05) var chase_wait_min_sec: float = 1.0
@export_range(0.25, 12.0, 0.05) var chase_wait_max_sec: float = 3.0
@export_range(0.25, 6.0, 0.05) var chase_strafe_min_sec: float = 1.2
@export_range(0.25, 6.0, 0.05) var chase_strafe_max_sec: float = 2.0
@export_range(0.25, 8.0, 0.05) var chase_retreat_min_sec: float = 1.2
@export_range(0.25, 8.0, 0.05) var chase_retreat_max_sec: float = 3.2
@export_range(0.1, 3.0, 0.05) var chase_optimal_eps: float = 0.55

var _ai_state: int = MonsterAIScript.State.IDLE
var _idle_timer: float = 0.0
var _undetected_sec: float = 0.0
var _alert_timer: float = 0.0
var _patrol: RefCounted = null
var _interest: MonsterInterest = null
var _rng := RandomNumberGenerator.new()
var _senses_root: Node = null
var _chase_range_mesh: MeshInstance3D = null
var _attack_range_mesh: MeshInstance3D = null
var _cast_windup_left: float = 0.0
var _casting_ability: Node = null
var _cast_prefer_index: int = 0
var _chase_move: MonsterChaseMove = null
var _lookdev_aggro: Node3D = null

func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint():
		add_to_group("monster")
		add_to_group("combat_target")
	_rng.randomize()
	_chase_move = MonsterChaseMoveScript.new() as MonsterChaseMove
	_sync_chase_move_config()
	_senses_root = get_node_or_null("Senses")
	_cache_eyes()
	_refresh_appearance()
	var live_ai := bool(get_meta("lookdev_live_ai", false))
	if lookdev_override or (Engine.is_editor_hint() and not live_ai):
		_refresh_lookdev_eyes()
	else:
		_set_chase_eyes_active(false)
	_refresh_range_gizmos()
	if Engine.is_editor_hint() and not live_ai:
		set_physics_process(false)
		return
	if Engine.is_editor_hint() and live_ai:
		set_physics_process(false)
		set_process(true)
		call_deferred("_begin_patrol")
		return
	_enter_idle()
	set_physics_process(true)


func _net_rewind_profile() -> String:
	# Telegraph+ram pose interpolates Head/Body; other monsters are root pose only.
	if ":net_phase" in _net_state_extra():
		return Profiles.CHARGE
	return Profiles.WORLD_PROP


func _bind_rewindable() -> void:
	if Engine.is_editor_hint():
		return
	NetLivenessScript.attach(self, _net_rewind_profile())


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and bool(get_meta("lookdev_live_ai", false)):
		_physics_process(delta)


func _sync_chase_move_config() -> void:
	if _chase_move == null:
		return
	_chase_move.configure(
		_rng, chase_wait_min_sec, chase_wait_max_sec,
		chase_strafe_min_sec, chase_strafe_max_sec,
		chase_retreat_min_sec, chase_retreat_max_sec, chase_optimal_eps
	)


func apply_summon_appearance(tint: Color, p_eye_glow_color: Color = DEFAULT_EYE_GLOW) -> void:
	body_tint = tint
	eye_glow_color = p_eye_glow_color
	_refresh_appearance()


func set_lookdev_pose(pose: MonsterAIScript.LookdevPose, enable_override: bool = true) -> void:
	lookdev_override = enable_override
	lookdev_pose = pose

func set_lookdev_aggro(target: Node3D) -> void:
	_lookdev_aggro = target
	lookdev_override = lookdev_override and not is_instance_valid(target)
	set_physics_process(not Engine.is_editor_hint() or is_instance_valid(target))


func get_ability_placeholders() -> Array[Node]:
	var out: Array[Node] = []
	var root := get_node_or_null("Abilities")
	if root == null:
		return out
	for child in root.get_children():
		if child.has_method("preview_cast"):
			out.append(child)
	return out


func get_combat_abilities() -> Array[Node]:
	## Abilities that support chase casting (can_cast / begin_cast / range check).
	var out: Array[Node] = []
	var root := get_node_or_null("Abilities")
	if root == null:
		return out
	for child in root.get_children():
		if "participates_in_cast_rotation" in child:
			if not bool(child.get("participates_in_cast_rotation")):
				continue
		if (
			child.has_method("can_cast")
			and child.has_method("begin_cast")
			and child.has_method("is_target_in_range")
		):
			out.append(child)
	return out


func is_ai_chasing() -> bool:
	return _ai_state == MonsterAIScript.State.CHASE


func is_ai_alert() -> bool:
	return _ai_state == MonsterAIScript.State.ALERT


## Live chase interest target, or null if freed / position-only interest.
func get_chase_target() -> Node3D:
	if _interest == null:
		return null
	return _interest.get_live_target()


func get_chase_goal(fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if _interest == null:
		return fallback
	return _interest.resolved_goal_position(fallback)


func _combat_groups() -> Array[StringName]:
	return [&"monster", &"combat_target"]


func _on_death(_from: Node3D) -> void:
	_end_ai_for_death()
	MonsterCorpseScript.spawn_from_monster(
		self, _last_hit_dir, death_linger_sec, death_fade_sec, DEATH_IMPULSE_SCALE
	)
	queue_free()


## Drop every AI intent so nothing keeps ticking between death and free.
func _end_ai_for_death() -> void:
	_ai_state = MonsterAIScript.State.IDLE
	_interest = null
	_undetected_sec = 0.0
	_alert_timer = 0.0
	_cancel_cast()
	_kill_owned_summons()
	_set_chase_eyes_active(false)


func get_summon_host() -> Node:
	return get_node_or_null("SummonHost")


func _kill_owned_summons() -> void:
	var host := get_summon_host()
	if host != null and host.has_method("kill_all"):
		host.call("kill_all")


func _refresh_appearance() -> void:
	_ensure_mesh_refs()
	if _body_mesh != null and _head_mesh != null:
		_character_color = body_tint
		_apply_character_color(body_tint)
	_tint_optional_body_parts()
	_apply_eye_glow_from_health()


func _tint_optional_body_parts() -> void:
	## Type scenes may author MidBody / hand spheres that should match body_tint.
	_tint_mesh_instance(get_node_or_null("%MidBody") as MeshInstance3D, body_tint)
	_tint_optional_hands()


func _tint_optional_hands() -> void:
	for path in ["%RightHand", "%LeftHand"]:
		_tint_mesh_instance(get_node_or_null(path) as MeshInstance3D, body_tint)


func _tint_mesh_instance(mesh_inst: MeshInstance3D, color: Color) -> void:
	var mat := _authored_material(mesh_inst)
	if mat == null:
		return
	mat.albedo_color = color


func _refresh_lookdev_eyes() -> void:
	if not lookdev_override and not Engine.is_editor_hint():
		return
	_set_chase_eyes_active(MonsterAIScript.lookdev_eyes_visible(lookdev_pose))


func _refresh_range_gizmos() -> void:
	var result: Dictionary = MonsterRangeGizmosScript.refresh(
		self, show_combat_ranges, _chase_range_mesh, _attack_range_mesh,
		chase_range, attack_range, RANGE_DISC_HEIGHT
	)
	_chase_range_mesh = result.get("chase") as MeshInstance3D
	_attack_range_mesh = result.get("attack") as MeshInstance3D


## Collects candidates (default players + senses) and prefers one. Override to replace.
func _gather_interest() -> MonsterInterest:
	if _lookdev_aggro != null and is_instance_valid(_lookdev_aggro):
		return MonsterInterestScript.from_target(_lookdev_aggro, 2.0, &"lookdev")
	var candidates: Array = []
	_append_default_interest_candidates(candidates)
	_append_sense_interest_candidates(candidates)
	return _prefer_interest(candidates)


## Default: nearest living player in chase_range as a proximity-scored interest.
func _append_default_interest_candidates(out: Array) -> void:
	var target := get_aggro_player_target()
	if target == null:
		return
	var urgency: float = MonsterAIScript.proximity_urgency(
		global_position, target.global_position, chase_range
	)
	out.append(
		MonsterInterestScript.from_target(target, urgency, DEFAULT_PLAYER_SOURCE)
	)


## Nearest living player inside chase_range, or null. The shared aggro question
## every ability and combo asks — override to change who this monster hunts.
func get_aggro_player_target() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var positions: Array = []
	var alive_flags: Array = []
	var nodes: Array = []
	for node in tree.get_nodes_in_group("player"):
		if node is Node3D:
			var n3 := node as Node3D
			positions.append(n3.global_position)
			alive_flags.append(Character.is_node_alive(n3))
			nodes.append(n3)
	var idx: int = MonsterAIScript.pick_nearest_target_index(
		global_position, positions, alive_flags, chase_range
	)
	if idx < 0:
		return null
	return nodes[idx] as Node3D


func has_aggro_player() -> bool:
	return get_aggro_player_target() != null


## Last known aggro position for monsters that keep hunting after losing sight.
## Vector3 when remembered, null otherwise.
func get_last_aggro_player_aim() -> Variant:
	return null


## Reads MonsterSense children under Senses/.
func _append_sense_interest_candidates(out: Array) -> void:
	if _senses_root == null:
		_senses_root = get_node_or_null("Senses")
	if _senses_root == null:
		return
	for child in _senses_root.get_children():
		if MonsterSense.can_append_from(child):
			child.call("append_interest_candidates", self, out)


## Default preferencing: highest urgency. Children override to weight sources.
func _prefer_interest(candidates: Array) -> MonsterInterest:
	return MonsterAIScript.prefer_highest_urgency(candidates) as MonsterInterest

func _physics_process(delta: float) -> void:
	if NetClockScript.is_ticking():
		return
	_simulate_monster(delta)


func _rollback_tick(delta: float, _tick: int, is_fresh: bool) -> void:
	if GameState.is_multiplayer and not is_multiplayer_authority():
		return
	if is_fresh:
		_simulate_monster(delta)
		return
	## Resim restores pose/velocity; do not re-run senses or RNG.
	_replay_restored_motion(delta)


func _replay_restored_motion(delta: float) -> void:
	if not is_alive():
		return
	MonsterAIScript.apply_gravity(self, delta, gravity)
	_apply_knockback_bleed(delta)
	MonsterAIScript.apply_move(self, delta)


func _simulate_monster(delta: float) -> void:
	if not is_alive():
		return
	if Engine.is_editor_hint() and not bool(get_meta("lookdev_live_ai", false)):
		return
	MonsterAIScript.apply_gravity(self, delta, gravity)

	_interest = _gather_interest()
	var has_interest := _interest_is_actionable(_interest)
	_ai_state = MonsterAIScript.resolve_state(_ai_state, has_interest)
	_update_alert_timers(delta, has_interest)

	var chase_target := get_chase_target()

	var caster_chase := MonsterCasterCombatScript.tick_monster_if_present(
		self, delta, _ai_state, chase_target
	)
	if caster_chase:
		pass
	elif _casting_ability != null:
		_tick_cast_windup(delta, chase_target)
	elif _try_start_cast(chase_target):
		pass
	else:
		match _ai_state:
			MonsterAIScript.State.IDLE:
				_tick_idle(delta)
			MonsterAIScript.State.PATROL:
				_tick_patrol(delta)
			MonsterAIScript.State.CHASE:
				_tick_chase(delta)
			MonsterAIScript.State.ALERT:
				_tick_alert(delta)

	if lookdev_override:
		_refresh_lookdev_eyes()
	else:
		var want_eyes := MonsterAIScript.chase_eyes_visible(_ai_state)
		if want_eyes != _eyes_chasing:
			_set_chase_eyes_active(want_eyes)

	_apply_knockback_bleed(delta)
	MonsterAIScript.apply_move(self, delta)


func _update_alert_timers(delta: float, has_interest: bool) -> void:
	## 4s fully undetected after chase → ALERT; 12s more undetected → PATROL.
	if has_interest:
		_undetected_sec = 0.0
		_alert_timer = 0.0
		return
	if _ai_state == MonsterAIScript.State.CHASE:
		_undetected_sec += delta
		if _undetected_sec >= lost_chase_to_alert_sec:
			_enter_alert()
	elif _ai_state == MonsterAIScript.State.ALERT:
		_alert_timer += delta
		if _alert_timer >= alert_duration_sec:
			_undetected_sec = 0.0
			_alert_timer = 0.0
			_begin_patrol()
	else:
		_undetected_sec = 0.0
		_alert_timer = 0.0


func _interest_is_actionable(interest: MonsterInterest) -> bool:
	return interest != null and interest.is_actionable()


func _enter_idle() -> void:
	_ai_state = MonsterAIScript.State.IDLE
	_idle_timer = 0.0
	_undetected_sec = 0.0
	_alert_timer = 0.0
	_clear_chase_move()
	velocity.x = 0.0
	velocity.z = 0.0


func _enter_alert() -> void:
	_cancel_cast()
	_ai_state = MonsterAIScript.State.ALERT
	_undetected_sec = 0.0
	_alert_timer = 0.0
	_clear_chase_move()
	velocity.x = 0.0
	velocity.z = 0.0


func _tick_idle(delta: float) -> void:
	_idle_timer += delta
	velocity.x = 0.0
	velocity.z = 0.0
	if _idle_timer >= idle_duration_sec:
		_begin_patrol()


func _ensure_patrol() -> RefCounted:
	if _patrol == null:
		_patrol = MonsterPatrolScript.new()
	return _patrol


func _begin_patrol() -> void:
	_ai_state = MonsterAIScript.State.PATROL
	_undetected_sec = 0.0
	_alert_timer = 0.0
	_clear_chase_move()
	_ensure_patrol().call("begin", self, _rng, patrol_radius)


func _tick_patrol(_delta: float) -> void:
	var patrol := _ensure_patrol()
	patrol.call("tick", self, _rng)
	var desired: Vector3 = patrol.call("follow_velocity", self, patrol_speed)
	velocity.x = desired.x
	velocity.z = desired.z
	_face_horizontal(desired)


func _tick_alert(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _tick_chase(delta: float) -> void:
	if not _interest_is_actionable(_interest):
		## Grace window before ALERT: hold position, keep eyes on.
		_cancel_cast()
		_clear_chase_move()
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var goal := get_chase_goal(global_position)
	var target := get_chase_target()

	if _try_tick_chase_reposition(delta, target):
		return

	if _tick_chase_reposition_wait(delta, target):
		return

	_tick_chase_approach(goal, target)


func _tick_chase_reposition_wait(delta: float, target: Node3D) -> bool:
	## Continuous kite loop while near optimal range. Returns true if handled.
	if not _uses_continuous_chase_move_timer():
		return false
	if not target:
		return false
	_ensure_chase_wait_armed()
	var dist := MonsterAIScript.horizontal_distance(
		global_position, target.global_position
	)
	var optimal := _optimal_combat_range()
	if dist > optimal + chase_optimal_eps:
		return false
	if _tick_chase_wait_and_decide(delta, target, dist, optimal):
		if _try_tick_chase_reposition(delta, target):
			return true
	_hold_chase_while_waiting(target)
	return true


func _tick_chase_approach(goal: Vector3, target: Node3D) -> void:
	if (
		chase_style == ChaseStyle.CLOSE_IN
		and target
		and _has_ranged_spacing_abilities()
	):
		if _tick_ranged_cast_chase(target):
			return

	if chase_style == ChaseStyle.KEEP_AWAY and target:
		_move_keep_away(target)
		return

	var to_goal := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if to_goal.length() <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		if target:
			_try_touch_damage(target)
		return
	var desired: Vector3 = MonsterAIScript.horizontal_velocity_toward(
		global_position, goal, move_speed, velocity.y
	)
	velocity.x = desired.x
	velocity.z = desired.z
	_face_horizontal(desired)


func _uses_continuous_chase_move_timer() -> bool:
	## Children (e.g. Rat Queen) can disable the free 1–3s kite loop.
	return true


func is_chase_retreating() -> bool:
	return _chase_move != null and _chase_move.is_retreating()


func is_chase_moving() -> bool:
	return _chase_move != null and _chase_move.is_moving()


func _clear_chase_move() -> void:
	if _chase_move != null:
		_chase_move.clear()


func _ensure_chase_wait_armed() -> void:
	_sync_chase_move_config()
	if _chase_move != null:
		_chase_move.ensure_wait_armed()


func _arm_chase_wait() -> void:
	_sync_chase_move_config()
	if _chase_move != null:
		_chase_move.arm_wait()


func _optimal_combat_range() -> float:
	if chase_style == ChaseStyle.KEEP_AWAY:
		return keep_away_range
	if _has_ranged_spacing_abilities():
		var ability := MonsterCombatSpacingScript.preferred_spacing(get_combat_abilities())
		if ability != null:
			return MonsterCombatSpacingScript.preferred_cast_ideal(ability)
	return attack_range


func _max_chase_reposition_distance() -> float:
	return MonsterAIScript.max_aggro_move_distance(chase_range)


func _tick_chase_wait_and_decide(
	delta: float, target: Node3D, dist: float, optimal: float
) -> bool:
	_sync_chase_move_config()
	if _chase_move == null:
		return false
	return _chase_move.tick_wait_and_decide(
		delta, self, target, dist, optimal, _max_chase_reposition_distance()
	)


func start_chase_strafe(target: Node3D, side_sign: float, duration_sec: float) -> void:
	_sync_chase_move_config()
	if _chase_move != null:
		_chase_move.start_strafe(self, target, side_sign, duration_sec)


func start_chase_retreat(target: Node3D, side_sign: float, duration_sec: float) -> void:
	if MonsterCasterCombatScript.try_combo_instead_of_retreat_on(self, target):
		return
	_begin_chase_retreat_move(target, side_sign, duration_sec)


func _begin_chase_retreat_move(
	target: Node3D, side_sign: float, duration_sec: float
) -> void:
	_sync_chase_move_config()
	if _chase_move != null:
		_chase_move.start_retreat(
			self, target, side_sign, duration_sec, _max_chase_reposition_distance()
		)


func _try_tick_chase_reposition(delta: float, target: Node3D) -> bool:
	_sync_chase_move_config()
	if _chase_move == null:
		return false
	return _chase_move.tick_move(
		delta,
		self,
		target,
		move_speed,
		attack_range,
		_max_chase_reposition_distance(),
		Callable(self, "_face_horizontal"),
		Callable(self, "_try_touch_damage")
	)


func _hold_chase_while_waiting(target: Node3D) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not target:
		return
	var toward := Vector3(
		target.global_position.x - global_position.x,
		0.0,
		target.global_position.z - global_position.z
	)
	_face_horizontal(toward)
	if toward.length() <= attack_range:
		_try_touch_damage(target)


func _has_ranged_spacing_abilities() -> bool:
	for ability in get_combat_abilities():
		if "requires_target" in ability and not bool(ability.get("requires_target")):
			continue
		if "min_cast_range" in ability and float(ability.get("min_cast_range")) > 0.5:
			return true
	return false


func _move_keep_away(target: Node3D) -> void:
	MonsterCombatSpacingScript.apply_keep_away(
		self, target, keep_away_range, move_speed, Callable(self, "_face_horizontal")
	)


func _try_start_cast(target: Node3D) -> bool:
	if is_chase_retreating():
		return false
	var ready_ability := _pick_ready_ability(target)
	if ready_ability == null:
		return false
	_begin_ability_windup(ready_ability)
	_tick_cast_windup(0.0, target)
	return true


## Keep cast spacing and fire when in band. Returns true when chase is handled.
func _tick_ranged_cast_chase(target: Node3D) -> bool:
	var ready_ability := _pick_ready_ability(target)
	if ready_ability != null:
		_begin_ability_windup(ready_ability)
		_tick_cast_windup(0.0, target)
		return true

	var awaiting := MonsterCombatSpacingScript.first_ranged_castable(get_combat_abilities())
	if awaiting != null:
		_move_toward_cast_range(target, awaiting)
		return true

	var spacer := MonsterCombatSpacingScript.preferred_spacing(get_combat_abilities())
	if spacer != null:
		_move_toward_cast_range(target, spacer)
		return true
	return false


func _move_toward_cast_range(target: Node3D, ability: Node) -> void:
	MonsterCombatSpacingScript.apply_cast_band(
		self, target, ability, move_speed, Callable(self, "_face_horizontal")
	)


func _pick_ready_ability(target: Node3D) -> Node:
	var abilities := get_combat_abilities()
	if abilities.is_empty():
		return null
	var count := abilities.size()
	for i in count:
		var idx := (_cast_prefer_index + i) % count
		var ability: Node = abilities[idx]
		if ability.has_method("is_ready_to_cast"):
			if not bool(ability.call("is_ready_to_cast", self, target)):
				continue
		else:
			if not bool(ability.call("can_cast")):
				continue
			if not bool(ability.call("is_target_in_range", self, target)):
				continue
		_cast_prefer_index = (idx + 1) % count
		return ability
	return null


func _begin_ability_windup(ability: Node) -> void:
	_casting_ability = ability
	_cast_windup_left = 0.55
	if "windup_sec" in ability:
		_cast_windup_left = float(ability.get("windup_sec"))
	velocity.x = 0.0
	velocity.z = 0.0
	if ability.has_method("start_windup_fx"):
		ability.call("start_windup_fx", self)


func _tick_cast_windup(delta: float, target: Node3D) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if target:
		var toward := Vector3(
			target.global_position.x - global_position.x,
			0.0,
			target.global_position.z - global_position.z
		)
		_face_horizontal(toward)
	_cast_windup_left -= delta
	if _cast_windup_left > 0.0:
		return
	var ability := _casting_ability
	_casting_ability = null
	_cast_windup_left = 0.0
	if ability == null or not is_instance_valid(ability):
		return
	var needs_target := true
	if "requires_target" in ability:
		needs_target = bool(ability.get("requires_target"))
	if needs_target and not target:
		if ability.has_method("stop_windup_fx"):
			ability.call("stop_windup_fx")
		return
	if ability.has_method("begin_cast"):
		ability.call("begin_cast", self, target)
		_on_ability_cast_fired(ability)


func _on_ability_cast_fired(_ability: Node) -> void:
	## Override in children (e.g. Rat Queen post-Command-Pack retreat).
	pass


func _cancel_cast() -> void:
	if _casting_ability != null and is_instance_valid(_casting_ability):
		if _casting_ability.has_method("stop_windup_fx"):
			_casting_ability.call("stop_windup_fx")
	_casting_ability = null
	_cast_windup_left = 0.0


func _try_touch_damage(target: Node3D) -> void:
	if is_chase_retreating() or target == null:
		return
	if touch_damage <= 0.0:
		return
	Character.apply_hit(target, touch_damage * get_physics_process_delta_time(), self)


func _face_horizontal(desired_vel: Vector3) -> void:
	## Strafe keeps facing the player; retreat/approach turn at face_turn_speed_rad.
	_face_horizontal_at_speed(
		desired_vel, get_physics_process_delta_time(), face_turn_speed_rad
	)


func _face_horizontal_at_speed(desired: Vector3, delta: float, speed_rad: float) -> void:
	rotation.y = MonsterAIScript.rotate_yaw_toward(rotation.y, desired, speed_rad, delta)
