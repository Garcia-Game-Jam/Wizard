@tool
class_name MonsterCasterCombat
extends Node3D

## Charge-hold-release caster combat + scripted combo patterns for caster monsters.

enum State { NEUTRAL, CHARGING, CHARGED, RETREATING_CHARGED, COMBO_ACTIVE }

enum ComboPhase { WAIT_DELAY, CHARGING, CHARGED, WAIT_DASH }

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterChaseLocomotionScript := preload("res://scripts/monsters/monster_chase_locomotion.gd")
const MonsterComboStepScript := preload("res://scripts/monsters/monster_combo_step.gd")
const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)

const STANDSTILL_SPEED_EPS := 0.08
const FROST_TELEGRAPH_META := &"frost_breath_telegraph_fx"

@export var combo_steps: Array = []
@export var debug_force_combo: bool = false
@export_range(0.0, 20.0, 0.1) var combo_trigger_max_range: float = 8.0
@export_range(0.0, 30.0, 0.1) var combo_lockout_sec: float = 0.0

var _state: State = State.NEUTRAL
var _held_ability: Node = null
var _charge_left: float = 0.0
var _prefer_index: int = 0
var _combo_step_index: int = 0
var _combo_delay_left: float = 0.0
var _combo_phase: int = ComboPhase.WAIT_DELAY
var _combo_charge_ability: Node = null
var _monster: Monster = null
var _rng := RandomNumberGenerator.new()
var _combo_lockout_left: float = 0.0
var _charged_retreat_rolled: bool = false


func _ready() -> void:
	_rng.randomize()
	_monster = get_parent() as Monster


func uses_caster_combat() -> bool:
	return _monster != null and is_inside_tree()


func tick(delta: float, ai_state: int, target: Node3D) -> void:
	if not uses_caster_combat():
		return
	if _combo_lockout_left > 0.0:
		_combo_lockout_left = maxf(0.0, _combo_lockout_left - delta)
	if _is_dashing():
		_tick_active_dash(delta)
		if _is_dashing():
			return
	if ai_state != MonsterAIScript.State.CHASE:
		_reset_charge_state()
		return
	target = _resolve_target(target)
	if not _interest_actionable():
		_reset_charge_state()
		_zero_velocity()
		return
	match _state:
		State.COMBO_ACTIVE:
			_tick_combo(delta, target)
		State.CHARGING:
			_tick_charging(delta, target)
		State.CHARGED:
			_tick_charged(delta, target)
		State.RETREATING_CHARGED:
			_tick_retreating_charged(delta, target)
		_:
			_tick_neutral(delta, target)


func configure_combo(steps: Array) -> void:
	combo_steps = steps


func is_combo_active() -> bool:
	return _state == State.COMBO_ACTIVE


func try_combo_instead_of_retreat(target: Node3D) -> bool:
	if _state == State.COMBO_ACTIVE:
		return true
	target = _resolve_target(target)
	var chance := _get_retreat_combo_chance(target)
	if chance < 0.0:
		return false
	return try_trigger_combo(target, chance)


func try_trigger_combo(
	target: Node3D, chance: float, require_range: bool = true
) -> bool:
	if _state == State.COMBO_ACTIVE:
		return true
	if _combo_lockout_left > 0.0 and not debug_force_combo:
		return false
	target = _resolve_target(target)
	if require_range and not _can_start_combo_at_range(target):
		return false
	if debug_force_combo or chance >= 1.0:
		return _start_combo(target, require_range)
	if chance <= 0.0:
		return false
	return _start_combo(target, require_range) if _rng.randf() <= chance else false


func has_active_charge() -> bool:
	return (
		_state == State.CHARGING
		or _state == State.CHARGED
		or _state == State.RETREATING_CHARGED
	)


func request_combo() -> void:
	if _state == State.COMBO_ACTIVE:
		return
	var target := _resolve_target(null)
	if target != null:
		try_trigger_combo(target, 1.0)


static func tick_monster_if_present(
	monster: Node, delta: float, ai_state: int, target: Node3D
) -> bool:
	var caster := monster.get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("uses_caster_combat"):
		return false
	if not bool(caster.call("uses_caster_combat")):
		return false
	caster.call("tick", delta, ai_state, target)
	return ai_state == MonsterAIScript.State.CHASE


static func try_combo_instead_of_retreat_on(monster: Node, target: Node3D) -> bool:
	var caster := monster.get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("try_combo_instead_of_retreat"):
		return false
	return bool(caster.call("try_combo_instead_of_retreat", target))


static func is_standing_still_velocity(horiz: Vector2, eps: float = STANDSTILL_SPEED_EPS) -> bool:
	return horiz.length_squared() <= eps * eps


func _tick_neutral(delta: float, target: Node3D) -> void:
	if debug_force_combo and _try_start_combo(target):
		return
	if _uses_offensive_spacing() and _monster.has_method("try_close_range_sidestep"):
		if bool(_monster.call("try_close_range_sidestep", target)):
			return
	if (
		_uses_offensive_spacing()
		and _monster.has_method("tick_occasional_chase_walk")
		and bool(_monster.call("tick_occasional_chase_walk", delta, target))
	):
		_tick_locomotion(delta, target)
		return
	if _can_start_charge():
		var ability := _pick_charge_ability(target)
		if ability != null:
			_begin_charge(ability)
			return
	_tick_locomotion(delta, target)


func _tick_charging(delta: float, target: Node3D) -> void:
	_zero_velocity()
	_face_target(target)
	_charge_left -= delta
	if _charge_left > 0.0:
		return
	_state = State.CHARGED


func _tick_charged(delta: float, target: Node3D) -> void:
	_zero_velocity()
	_face_target(target)
	if _held_ability != null and _ability_in_range(_held_ability, target):
		_release_held(target)
		return
	if _uses_offensive_spacing():
		if _monster.has_method("try_close_range_sidestep"):
			if bool(_monster.call("try_close_range_sidestep", target)):
				return
		_tick_locomotion(delta, target, true)
		return
	if _should_retreat_with_charge(target):
		_start_retreat_with_charge(target)
		return
	_tick_locomotion(delta, target)


func _tick_retreating_charged(delta: float, target: Node3D) -> void:
	_face_target(target)
	if _held_ability != null and _ability_in_range(_held_ability, target):
		_release_held(target)
		return
	if not _monster.is_chase_retreating() and not _is_dashing():
		_state = State.CHARGED
		return
	_tick_locomotion(delta, target, true)


func _tick_combo(delta: float, target: Node3D) -> void:
	if combo_steps.is_empty():
		_finish_combo()
		return
	if _combo_step_index >= combo_steps.size():
		_finish_combo()
		return
	var step: Resource = combo_steps[_combo_step_index] as Resource
	if step == null:
		_advance_combo_step()
		return
	match _combo_phase:
		ComboPhase.WAIT_DELAY:
			_zero_velocity()
			_face_target(target)
			if _combo_delay_left > 0.0:
				_combo_delay_left -= delta
				if _combo_delay_left > 0.0:
					return
			_run_combo_step(step, target)
		ComboPhase.CHARGING:
			_zero_velocity()
			_face_target(target)
			_charge_left -= delta
			if _charge_left > 0.0:
				return
			_combo_phase = ComboPhase.CHARGED
		ComboPhase.CHARGED:
			_zero_velocity()
			_face_target(target)
			var charged_step: Resource = combo_steps[_combo_step_index] as Resource
			if (
				charged_step != null
				and charged_step.step_type == MonsterComboStepScript.StepType.CHARGE_THROW
				and _combo_charge_ability != null
			):
				_fire_release(_combo_charge_ability, target)
			_combo_charge_ability = null
			_advance_combo_step()
		ComboPhase.WAIT_DASH:
			_tick_active_dash(delta)
			_face_target(target)
			if _is_dashing():
				return
			_advance_combo_step()


func _run_combo_step(step: Resource, target: Node3D) -> void:
	var ability := _find_ability(step.ability_id)
	if ability == null:
		_advance_combo_step()
		return
	match step.step_type:
		MonsterComboStepScript.StepType.INSTANT:
			_fire_instant_step(ability, target, str(step.get("combo_variant")))
			if _is_dashing():
				_combo_phase = ComboPhase.WAIT_DASH
			else:
				_advance_combo_step()
		MonsterComboStepScript.StepType.CHARGE_THROW, MonsterComboStepScript.StepType.CHARGE_HOLD:
			_combo_charge_ability = ability
			_begin_charge(ability, false, false)
			_combo_phase = ComboPhase.CHARGING


func _fire_instant_step(ability: Node, target: Node3D, variant: String = "") -> void:
	if str(ability.get("ability_id")) == "ash_frost_breath":
		_stop_cloud_pre_fx()
	if variant == "close" and ability.has_method("fire_combo_close_dash"):
		ability.call("fire_combo_close_dash", _monster, target)
	elif variant == "away" and ability.has_method("fire_combo_away_dash"):
		ability.call("fire_combo_away_dash", _monster, target)
	elif ability.has_method("fire_combo_step"):
		ability.call("fire_combo_step", _monster, target)
	elif ability.has_method("fire_instant"):
		ability.call("fire_instant", _monster, target)
	elif ability.has_method("start_dash"):
		ability.call("start_dash", _monster, target)


func _advance_combo_step() -> void:
	_combo_step_index += 1
	if _combo_step_index >= combo_steps.size():
		_finish_combo()
		return
	var step: Resource = combo_steps[_combo_step_index] as Resource
	_combo_delay_left = step.delay_after_prev_sec if step != null else 0.0
	_combo_phase = ComboPhase.WAIT_DELAY
	if (
		step != null
		and str(step.ability_id) == "ash_frost_breath"
		and _combo_delay_left > 0.0
	):
		_start_cloud_pre_fx()


func _start_combo(target: Node3D, require_range: bool = true) -> bool:
	if require_range and not _can_start_combo_at_range(target):
		return false
	if _monster.has_method("select_combo_steps"):
		var picked: Variant = _monster.call("select_combo_steps", target)
		if picked is Array and (picked as Array).size() > 0:
			combo_steps = picked as Array
	if combo_steps.is_empty():
		return false
	_cancel_charge()
	_reset_combo_abilities()
	_state = State.COMBO_ACTIVE
	_combo_step_index = 0
	_combo_phase = ComboPhase.WAIT_DELAY
	_combo_delay_left = 0.0
	_combo_charge_ability = null
	_combo_lockout_left = combo_lockout_sec
	if combo_steps.size() > 0 and combo_steps[0] != null:
		_combo_delay_left = combo_steps[0].delay_after_prev_sec
	if _monster.has_method("on_combo_started"):
		_monster.call("on_combo_started")
	return true


func _finish_combo() -> void:
	_stop_frost_telegraph()
	_stop_cloud_pre_fx()
	if _monster.has_method("on_combo_finished"):
		_monster.call("on_combo_finished")
	_state = State.NEUTRAL
	_combo_step_index = 0
	_combo_phase = ComboPhase.WAIT_DELAY
	_combo_delay_left = 0.0
	_combo_charge_ability = null


func _try_start_combo(target: Node3D) -> bool:
	if _state == State.COMBO_ACTIVE:
		return true
	return try_trigger_combo(target, 1.0)


func _get_retreat_combo_chance(target: Node3D) -> float:
	if _monster.has_method("get_retreat_combo_chance"):
		return float(_monster.call("get_retreat_combo_chance", target))
	return -1.0


func _can_start_combo_at_range(target: Node3D) -> bool:
	if combo_steps.is_empty() or target == null:
		return false
	var dist := MonsterAIScript.horizontal_distance(
		_monster.global_position, target.global_position
	)
	return dist <= combo_trigger_max_range


func _begin_charge(ability: Node, set_state: bool = true, track_held: bool = true) -> void:
	if track_held:
		_held_ability = ability
		_charged_retreat_rolled = false
	_charge_left = float(ability.get("windup_sec")) if "windup_sec" in ability else 0.55
	if ability.has_method("start_windup_fx"):
		ability.call("start_windup_fx", _monster)
	if set_state:
		_state = State.CHARGING


func _release_held(target: Node3D) -> void:
	if _held_ability == null:
		_state = State.NEUTRAL
		return
	var ability := _held_ability
	_held_ability = null
	_fire_release(ability, target)
	_state = State.NEUTRAL


func _fire_release(ability: Node, target: Node3D) -> void:
	if _state == State.COMBO_ACTIVE and ability.has_method("release_combo_step"):
		ability.call("release_combo_step", _monster, target)
	elif ability.has_method("release_charge"):
		ability.call("release_charge", _monster, target)
	elif ability.has_method("begin_cast"):
		ability.call("begin_cast", _monster, target)
	if _monster.has_method("_on_ability_cast_fired"):
		_monster.call("_on_ability_cast_fired", ability)


func _reset_combo_abilities() -> void:
	var root := _monster.get_node_or_null("Abilities")
	if root == null:
		return
	for child in root.get_children():
		if child.has_method("reset_for_combo"):
			child.call("reset_for_combo")
		elif child.has_method("reset_cooldown"):
			child.call("reset_cooldown")


func _cancel_charge() -> void:
	if _held_ability != null and is_instance_valid(_held_ability):
		if _held_ability.has_method("stop_windup_fx"):
			_held_ability.call("stop_windup_fx")
	_held_ability = null
	_charge_left = 0.0


func _reset_charge_state() -> void:
	if _state == State.COMBO_ACTIVE:
		_finish_combo()
	_cancel_charge()
	_state = State.NEUTRAL


func _start_retreat_with_charge(target: Node3D) -> void:
	if target == null:
		return
	if try_combo_instead_of_retreat(target):
		return
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var min_sec := float(_monster.get("chase_retreat_min_sec"))
	var max_sec := float(_monster.get("chase_retreat_max_sec"))
	var duration := _rng.randf_range(min_sec, max_sec)
	if _monster.has_method("_begin_chase_retreat_move"):
		_monster.call("_begin_chase_retreat_move", target, side, duration)
	_state = State.RETREATING_CHARGED


func _should_retreat_with_charge(target: Node3D) -> bool:
	if _held_ability == null or target == null:
		return false
	if _ability_too_close(_held_ability, target):
		return true
	if _charged_retreat_rolled:
		return false
	_charged_retreat_rolled = true
	return _rng.randf() < 0.35


func _uses_offensive_spacing() -> bool:
	return (
		_monster.has_method("uses_offensive_spacing")
		and bool(_monster.call("uses_offensive_spacing"))
	)


func _can_start_charge() -> bool:
	if _monster.is_chase_retreating() or _is_dashing():
		return false
	if _monster.has_method("is_chase_moving") and _monster.is_chase_moving():
		return false
	return _is_standing_still()


func _is_standing_still() -> bool:
	var vel := Vector3(_monster.velocity.x, 0.0, _monster.velocity.z)
	return vel.length_squared() <= STANDSTILL_SPEED_EPS * STANDSTILL_SPEED_EPS


func _pick_charge_ability(target: Node3D) -> Node:
	if _monster.has_method("pick_charge_ability"):
		var custom: Variant = _monster.call("pick_charge_ability", target)
		if custom is Node and is_instance_valid(custom as Node):
			return custom as Node
	var abilities := _get_chargeable_abilities()
	if abilities.is_empty():
		return null
	var count := abilities.size()
	for i in count:
		var idx := (_prefer_index + i) % count
		var ability: Node = abilities[idx]
		if not bool(ability.call("can_cast")):
			continue
		_prefer_index = (idx + 1) % count
		return ability
	return null


func _get_chargeable_abilities() -> Array[Node]:
	return _monster.get_combat_abilities()


func _find_ability(ability_id: String) -> Node:
	var root := _monster.get_node_or_null("Abilities")
	if root == null:
		return null
	for child in root.get_children():
		if str(child.get("ability_id")) == ability_id:
			return child
	return null


func _ability_in_range(ability: Node, target: Node3D) -> bool:
	if ability.has_method("is_ready_to_cast"):
		return bool(ability.call("is_ready_to_cast", _monster, target))
	if not bool(ability.call("can_cast")):
		return false
	return bool(ability.call("is_target_in_range", _monster, target))


func _ability_too_close(ability: Node, target: Node3D) -> bool:
	if "min_cast_range" not in ability:
		return false
	var min_r := float(ability.get("min_cast_range"))
	if min_r <= 0.5:
		return false
	var dist := MonsterAIScript.horizontal_distance(
		_monster.global_position, target.global_position
	)
	return dist < min_r


func _tick_locomotion(delta: float, target: Node3D, allow_move: bool = false) -> void:
	if not allow_move and has_active_charge() and _state != State.RETREATING_CHARGED:
		return
	MonsterChaseLocomotionScript.tick(_monster, delta, target)


func _resolve_target(target: Node3D) -> Node3D:
	var aggro := _monster.get_aggro_player_target()
	if aggro != null:
		return aggro
	return MonsterAIScript.live_node3d(target)


func _interest_actionable() -> bool:
	if _monster.has_method("_interest_is_actionable"):
		return bool(_monster.call("_interest_is_actionable", _monster.get("_interest")))
	return true


func _face_target(target: Node3D) -> void:
	var live := MonsterAIScript.live_node3d(target)
	if not live:
		return
	var toward := Vector3(
		live.global_position.x - _monster.global_position.x,
		0.0,
		live.global_position.z - _monster.global_position.z
	)
	if toward.length_squared() < 0.0001:
		return
	if _monster.has_method("_face_horizontal"):
		_monster.call("_face_horizontal", toward)


func _zero_velocity() -> void:
	_monster.velocity.x = 0.0
	_monster.velocity.z = 0.0


func _is_dashing() -> bool:
	return _find_dashing_ability() != null


func _tick_active_dash(delta: float) -> void:
	var dash := _find_dashing_ability()
	if dash != null and dash.has_method("tick_dash") and _monster is CharacterBody3D:
		dash.call("tick_dash", _monster as CharacterBody3D, delta)


func _find_dashing_ability() -> Node:
	var root := _monster.get_node_or_null("Abilities")
	if root == null:
		return null
	for child in root.get_children():
		if child.has_method("is_dashing") and bool(child.call("is_dashing")):
			return child
	return null


func _stop_frost_telegraph() -> void:
	var frost := _find_ability("ash_frost_breath")
	if frost != null and frost.has_method("stop_retreat_telegraph"):
		frost.call("stop_retreat_telegraph", _monster)


func _start_cloud_pre_fx() -> void:
	var frost := _find_ability("ash_frost_breath")
	if frost != null and frost.has_method("start_cloud_pre_fx"):
		frost.call("start_cloud_pre_fx", _monster)


func _stop_cloud_pre_fx() -> void:
	var frost := _find_ability("ash_frost_breath")
	if frost != null and frost.has_method("stop_cloud_pre_fx"):
		frost.call("stop_cloud_pre_fx", _monster)
