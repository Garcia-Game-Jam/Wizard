@tool
class_name AshWretch
extends Monster

## Ice Caster: charge-hold-release caster combat with a ward-block combo.

const MonsterComboStepScript := preload("res://scripts/monsters/monster_combo_step.gd")
const MonsterComboTriggersScript := preload("res://scripts/monsters/monster_combo_triggers.gd")
const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)
const LAST_AGGRO_SOURCE := &"last_aggro"
const LAST_AGGRO_URGENCY := 1.2

const COMBO_TRIGGER_RANGE := AshFrostBreathFlightScript.MAX_TRAVEL_RANGE
const WARD_BLOCK_COMBO_CHANCE := 0.5
const COMBO_SPLIT_RANGE := 5.0
const COMBO_LOCKOUT_SEC := 8.0
const COMBO_GLOW_META := &"ash_combo_hand_fx"
const COMBO_EYE_ENERGY := 3.8
const COMBO_EYE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const WALK_PAUSE_MIN_SEC := 1.2
const WALK_PAUSE_MAX_SEC := 2.4

var _last_aggro_player_pos: Vector3 = Vector3.ZERO
var _has_last_aggro_player: bool = false
var _combo_glow_active: bool = false
var _walk_pause_left: float = 0.0


func _ready() -> void:
	super._ready()
	_configure_caster_combo()


func _configure_caster_combo() -> void:
	var caster := get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("configure_combo"):
		return
	caster.call("configure_combo", build_close_combo_steps())
	if caster.has_method("set"):
		caster.set("combo_trigger_max_range", COMBO_TRIGGER_RANGE)
		caster.set("combo_lockout_sec", COMBO_LOCKOUT_SEC)


func uses_offensive_spacing() -> bool:
	## Walk/strafe between ice charges instead of planting as a turret.
	return true


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
	var side := 1.0 if randf() < 0.5 else -1.0
	var duration := randf_range(chase_strafe_min_sec, chase_strafe_max_sec)
	start_chase_strafe(target, side, duration)
	_walk_pause_left = randf_range(WALK_PAUSE_MIN_SEC, WALK_PAUSE_MAX_SEC)
	return true


func pick_charge_ability(target: Node3D) -> Node:
	## Ice is the primary rotation spell; ward when ice is cooling down or out of band.
	var ice := get_node_or_null("Abilities/IceBolt")
	if ice != null and _ability_ready_for_charge(ice, target):
		return ice
	var ward := get_node_or_null("Abilities/AshWard")
	if ward != null and _ability_ready_for_charge(ward, target):
		return ward
	return null


func _ability_ready_for_charge(ability: Node, target: Node3D) -> bool:
	if not bool(ability.call("can_cast")):
		return false
	if ability.has_method("is_ready_to_cast"):
		return bool(ability.call("is_ready_to_cast", self, target))
	return bool(ability.call("is_target_in_range", self, target))


func select_combo_steps(target: Node3D) -> Array:
	var dist := 0.0
	if target != null and is_instance_valid(target):
		dist = MonsterAIScript.horizontal_distance(global_position, target.global_position)
	return build_combo_steps_for_distance(dist)


static func build_combo_steps_for_distance(dist: float) -> Array:
	if dist <= COMBO_SPLIT_RANGE:
		return build_close_combo_steps()
	return build_far_combo_steps()


static func build_close_combo_steps() -> Array:
	var steps: Array = []
	steps.append(_combo_step("ash_ward", MonsterComboStepScript.StepType.INSTANT))
	steps.append(
		_combo_step(
			"ash_frost_breath",
			MonsterComboStepScript.StepType.INSTANT,
			AshFrostBreathFlightScript.COMBO_WARD_DELAY_SEC
		)
	)
	steps.append(
		_combo_step(
			"ash_retreat_dash",
			MonsterComboStepScript.StepType.INSTANT,
			AshFrostBreathFlightScript.COMBO_AFTER_CLOUD_DELAY_SEC,
			"away"
		)
	)
	steps.append(_combo_step("ash_ice", MonsterComboStepScript.StepType.INSTANT))
	return steps


static func build_far_combo_steps() -> Array:
	var steps: Array = []
	steps.append(
		_combo_step("ash_retreat_dash", MonsterComboStepScript.StepType.INSTANT, 0.0, "close")
	)
	steps.append(
		_combo_step(
			"ash_frost_breath",
			MonsterComboStepScript.StepType.INSTANT,
			AshFrostBreathFlightScript.COMBO_WARD_DELAY_SEC
		)
	)
	steps.append(
		_combo_step(
			"ash_retreat_dash",
			MonsterComboStepScript.StepType.INSTANT,
			AshFrostBreathFlightScript.COMBO_AFTER_CLOUD_DELAY_SEC,
			"away"
		)
	)
	steps.append(_combo_step("ash_ice", MonsterComboStepScript.StepType.INSTANT))
	return steps


static func _combo_step(
	ability_id: String,
	step_type: MonsterComboStepScript.StepType,
	delay_sec: float = 0.0,
	variant: String = ""
) -> Resource:
	var step := MonsterComboStepScript.new()
	step.ability_id = ability_id
	step.step_type = step_type
	step.delay_after_prev_sec = delay_sec
	step.combo_variant = variant
	return step


func on_combo_started() -> void:
	_combo_glow_active = true
	_set_chase_eyes_active(true)
	_apply_combo_eye_glow()
	_start_combo_hand_glow()


func on_combo_finished() -> void:
	_combo_glow_active = false
	_stop_combo_hand_glow()
	_tint_optional_hands()
	_apply_eye_glow_from_health()


func _apply_eye_glow_from_health() -> void:
	if _combo_glow_active:
		_apply_combo_eye_glow()
		return
	super._apply_eye_glow_from_health()


func _apply_combo_eye_glow() -> void:
	_apply_eye_glow_color(COMBO_EYE_COLOR, COMBO_EYE_ENERGY)


func _start_combo_hand_glow() -> void:
	_stop_combo_hand_glow()
	var fx_nodes: Array[Node] = []
	for path in ["%RightHand", "%LeftHand", "Body/Hands/RightHand", "Body/Hands/LeftHand"]:
		var hand := get_node_or_null(path) as Node3D
		if hand == null:
			continue
		var already := false
		for existing in fx_nodes:
			if existing.get_parent() == hand:
				already = true
				break
		if already:
			continue
		if hand is MeshInstance3D:
			_brighten_hand_mesh(hand as MeshInstance3D)
		var fx := _build_combo_hand_glow()
		hand.add_child(fx)
		fx_nodes.append(fx)
	if not fx_nodes.is_empty():
		set_meta(COMBO_GLOW_META, fx_nodes)


func _stop_combo_hand_glow() -> void:
	if not has_meta(COMBO_GLOW_META):
		return
	var fx_nodes: Variant = get_meta(COMBO_GLOW_META)
	if fx_nodes is Array:
		for fx in fx_nodes:
			if fx is Node and is_instance_valid(fx):
				(fx as Node).queue_free()
	remove_meta(COMBO_GLOW_META)


func _brighten_hand_mesh(hand: MeshInstance3D) -> void:
	var src := hand.material_override
	var mat := StandardMaterial3D.new()
	if src is StandardMaterial3D:
		mat = (src as StandardMaterial3D).duplicate()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 10.0
	hand.material_override = mat


func _build_combo_hand_glow() -> Node3D:
	var root := Node3D.new()
	root.name = "AshComboHandGlow"
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.22
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 12.0
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sphere)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 1.0, 1.0)
	light.light_energy = 10.0
	light.omni_range = 2.4
	light.shadow_enabled = false
	root.add_child(light)
	return root


func on_own_ward_blocked(blocked_from: Node = null) -> void:
	if _is_combo_active():
		return
	var player := MonsterComboTriggersScript.resolve_attacking_player(blocked_from, null)
	if player == null:
		return
	var caster := get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("try_trigger_combo"):
		return
	caster.call("try_trigger_combo", player, WARD_BLOCK_COMBO_CHANCE, false)


func _gather_interest() -> MonsterInterest:
	_update_last_aggro_player()
	var interest := super._gather_interest()
	if _interest_is_actionable(interest):
		return interest
	if _ai_state == MonsterAIScript.State.CHASE and _has_last_aggro_player:
		return MonsterInterestScript.from_position(
			_last_aggro_player_pos, LAST_AGGRO_URGENCY, LAST_AGGRO_SOURCE
		)
	return interest


func get_last_aggro_player_aim() -> Variant:
	if _has_last_aggro_player:
		return _last_aggro_player_pos
	return null


func _update_last_aggro_player() -> void:
	var target := get_aggro_player_target()
	if target == null:
		return
	_last_aggro_player_pos = target.global_position
	_has_last_aggro_player = true


func _sync_chase_move_config() -> void:
	super._sync_chase_move_config()
	if _chase_move != null:
		_chase_move.custom_too_close_cb = Callable(self, "_on_chase_too_close")


func _on_chase_too_close(_host: Node3D, target: Node3D, side_sign: float) -> bool:
	var duration := randf_range(chase_strafe_min_sec, chase_strafe_max_sec)
	_begin_chase_retreat_move(target, side_sign, duration)
	return true


func _begin_chase_retreat_move(
	target: Node3D, side_sign: float, duration_sec: float
) -> void:
	if try_retreat_dash(target, side_sign):
		return
	var strafe_sec := duration_sec
	if strafe_sec <= 0.0:
		strafe_sec = randf_range(chase_strafe_min_sec, chase_strafe_max_sec)
	start_chase_strafe(target, side_sign, strafe_sec)


func try_retreat_dash(target: Node3D, side_sign: float = 1.0) -> bool:
	if _is_combo_active():
		return false
	var dash := _get_dash_ability()
	if dash == null or not dash.has_method("try_backdash"):
		return false
	return bool(dash.call("try_backdash", self, target, side_sign))


func _is_combo_active() -> bool:
	var caster := get_node_or_null("CasterCombat")
	return (
		caster != null
		and caster.has_method("is_combo_active")
		and bool(caster.call("is_combo_active"))
	)


func _get_dash_ability() -> Node:
	return get_node_or_null("Abilities/AshRetreatDash")


func _move_toward_cast_range(target: Node3D, ability: Node) -> void:
	var aggro := get_aggro_player_target()
	if aggro != null:
		target = aggro
	if target == null:
		super._move_toward_cast_range(target, ability)
		return
	if not _should_turnaround_retreat(target, ability):
		super._move_toward_cast_range(target, ability)
		return
	if is_chase_retreating() or is_chase_moving():
		return
	var dash := _get_dash_ability()
	if dash != null and dash.has_method("is_dashing") and dash.is_dashing():
		return
	var side := 1.0 if randf() < 0.5 else -1.0
	var duration := randf_range(chase_retreat_min_sec, chase_retreat_max_sec)
	start_chase_retreat(target, side, duration)


func _should_turnaround_retreat(target: Node3D, ability: Node) -> bool:
	return _is_cast_band_too_close(target, ability)


func _is_cast_band_too_close(target: Node3D, ability: Node) -> bool:
	var min_r := float(ability.get("min_cast_range")) if "min_cast_range" in ability else 3.0
	var ideal := MonsterCombatSpacingScript.preferred_cast_ideal(ability)
	var dist := MonsterAIScript.horizontal_distance(global_position, target.global_position)
	return dist < min_r or dist < ideal - 0.45
