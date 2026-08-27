@tool
class_name EmberWretch
extends Monster

## Ember Caster: charge-hold-release caster combat with halo→dash→lob combo.

const MonsterComboStepScript := preload("res://scripts/monsters/monster_combo_step.gd")
const MonsterComboTriggersScript := preload("res://scripts/monsters/monster_combo_triggers.gd")

const COMBO_TRIGGER_RANGE := 8.0
const WARD_BLOCK_COMBO_CHANCE := 0.35
const LOW_HP_COMBO_RATIO := 0.35
const SIDESTEP_RANGE := 8.0
const STRAFE_FURTHER_WEIGHT := 0.7
const WALK_PAUSE_MIN_SEC := 1.6
const WALK_PAUSE_MAX_SEC := 3.2

var _used_low_hp_combo: bool = false
var _walk_pause_left: float = 0.0


func _ready() -> void:
	super._ready()
	_configure_caster_combo()
	_walk_pause_left = randf_range(WALK_PAUSE_MIN_SEC, WALK_PAUSE_MAX_SEC)
	if _chase_move != null:
		_chase_move.strafe_radial_blend = 0.0


func _configure_caster_combo() -> void:
	var caster := get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("configure_combo"):
		return
	var steps: Array = []
	var halo := MonsterComboStepScript.new()
	halo.ability_id = "ember_halo"
	halo.step_type = MonsterComboStepScript.StepType.CHARGE_THROW
	steps.append(halo)
	var dash := MonsterComboStepScript.new()
	dash.ability_id = "ember_dash"
	dash.step_type = MonsterComboStepScript.StepType.INSTANT
	steps.append(dash)
	var lob := MonsterComboStepScript.new()
	lob.ability_id = "ember_lob"
	lob.step_type = MonsterComboStepScript.StepType.CHARGE_THROW
	steps.append(lob)
	caster.call("configure_combo", steps)
	if caster.has_method("set"):
		caster.set("combo_trigger_max_range", COMBO_TRIGGER_RANGE)


func uses_offensive_spacing() -> bool:
	return true


func _sync_chase_move_config() -> void:
	super._sync_chase_move_config()
	if _chase_move != null:
		_chase_move.strafe_radial_blend = 0.0


func _uses_continuous_chase_move_timer() -> bool:
	return false


func _on_hurt(amount: float, from: Node3D) -> void:
	if not is_alive():
		return
	var before := ratio_before(amount)
	var dash := _get_dash_ability()
	if dash != null:
		if before >= LOW_HP_COMBO_RATIO and health_ratio() < LOW_HP_COMBO_RATIO:
			dash.reset_cooldown()
	_try_low_hp_combo(from, before)


func on_spell_ward_blocked(blocked_by: Node = null) -> void:
	var caster := get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("try_trigger_combo"):
		return
	if _is_combo_active():
		return
	var player := MonsterComboTriggersScript.resolve_attacking_player(blocked_by, self)
	if player == null:
		return
	caster.call("try_trigger_combo", player, WARD_BLOCK_COMBO_CHANCE, false)


func try_close_range_sidestep(target: Node3D) -> bool:
	if _is_combo_active():
		return false
	if is_chase_moving():
		return false
	var dash := _get_dash_ability()
	if dash == null or not dash.has_method("try_sidestep"):
		return false
	return bool(dash.call("try_sidestep", self, target))


func tick_occasional_chase_walk(delta: float, target: Node3D) -> bool:
	if _is_combo_active():
		return false
	var dash := _get_dash_ability()
	if dash != null and dash.has_method("is_dashing") and dash.is_dashing():
		return false
	if is_chase_moving():
		return true
	_walk_pause_left -= delta
	if _walk_pause_left > 0.0:
		return false
	if target == null or not is_instance_valid(target):
		_walk_pause_left = randf_range(WALK_PAUSE_MIN_SEC, WALK_PAUSE_MAX_SEC)
		return false
	_start_weighted_chase_walk(target)
	_walk_pause_left = randf_range(WALK_PAUSE_MIN_SEC, WALK_PAUSE_MAX_SEC)
	return true


func _start_weighted_chase_walk(target: Node3D) -> void:
	var further := MonsterAIScript.strafe_sign_further_from_player(
		global_position, target.global_position
	)
	var side := MonsterAIScript.pick_weighted_strafe_sign(
		further, randf(), STRAFE_FURTHER_WEIGHT
	)
	var duration := randf_range(chase_strafe_min_sec, chase_strafe_max_sec)
	if _chase_move != null:
		_chase_move.strafe_radial_blend = 0.0
	start_chase_strafe(target, side, duration)


func _try_low_hp_combo(from: Node3D, ratio_before: float) -> void:
	if _used_low_hp_combo:
		return
	if ratio_before < LOW_HP_COMBO_RATIO or health_ratio() >= LOW_HP_COMBO_RATIO:
		return
	var caster := get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("try_trigger_combo"):
		return
	var player := MonsterComboTriggersScript.resolve_attacking_player(from, self)
	if player == null:
		return
	_used_low_hp_combo = true
	caster.call("try_trigger_combo", player, 1.0)


func _move_toward_cast_range(target: Node3D, ability: Node) -> void:
	if target == null or not is_instance_valid(target):
		super._move_toward_cast_range(target, ability)
		return
	var dist := MonsterAIScript.horizontal_distance(global_position, target.global_position)
	if dist <= SIDESTEP_RANGE:
		if try_close_range_sidestep(target):
			return
		var dash := _get_dash_ability()
		if dash != null and dash.has_method("is_dashing") and dash.is_dashing():
			return
	_hold_or_close_to_cast_band(target, ability)


func _hold_or_close_to_cast_band(target: Node3D, ability: Node) -> void:
	var max_r := float(ability.get("max_cast_range")) if "max_cast_range" in ability else 12.0
	var ideal := MonsterCombatSpacingScript.preferred_cast_ideal(ability)
	var to_target := Vector3(
		target.global_position.x - global_position.x,
		0.0,
		target.global_position.z - global_position.z
	)
	var dist := to_target.length()
	_face_horizontal(to_target)
	if dist > max_r or dist > ideal + 0.45:
		if dist < 0.05:
			velocity.x = 0.0
			velocity.z = 0.0
			return
		var radial := to_target.normalized()
		var approach_goal := target.global_position - radial * ideal
		var desired: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			global_position, approach_goal, combat_speed(move_speed), velocity.y
		)
		velocity.x = desired.x
		velocity.z = desired.z
		return
	velocity.x = 0.0
	velocity.z = 0.0


func _is_combo_active() -> bool:
	var caster := get_node_or_null("CasterCombat")
	return (
		caster != null
		and caster.has_method("is_combo_active")
		and bool(caster.call("is_combo_active"))
	)


func _get_dash_ability() -> Node:
	return get_node_or_null("Abilities/EmberDash")
