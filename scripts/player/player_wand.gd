@tool
class_name PlayerWand
extends Node3D

## Slim hand-held wand with tip glow for casting and optional flashlight beam.
## @tool so spell_cast_workshop (and other studios) can drive pose/FX in the editor.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const WandListeningFxScript := preload("res://scripts/player/wand_listening_fx.gd")
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")

const WORLD_LIGHT_CULL_MASK := WorldVisualLayersScript.WORLD_LIGHT_MASK

const TIP_EMISSION_ARMED := 0.4
const TIP_EMISSION_LISTEN_MAX := 10.0
const TIP_SCALE_LISTEN_BOOST := 0.38
const LISTEN_LEVEL_REFERENCE := 0.08
const LISTEN_PEAK_DECAY := 0.68
const LISTEN_VISUAL_CURVE := 0.62
const SHAFT_LENGTH := 0.28
const SHAFT_TOP_RADIUS := 0.008
const SHAFT_BOTTOM_RADIUS := 0.008
const TIP_RADIUS := 0.012
const FLASHLIGHT_ENERGY := 3.6
const FLASHLIGHT_RANGE := 14.0
const FLASHLIGHT_HALF_ANGLE_DEG := 28.0
const FLASHLIGHT_ATTENUATION := 1.05
const FLASHLIGHT_LIGHT_SIZE := 0.35
const FLASHLIGHT_COLOR := Color(1.0, 0.86, 0.56)
const FLASHLIGHT_TIP_EMISSION := 1.0
const FLAME_GLOW_COLOR := Color(0.72, 0.08, 0.04)
const FLAME_GLOW_EMISSION := 3.2

@export var raised_position_offset: Vector3 = Vector3(-0.04, 0.10, -0.02)
@export var raised_basis_euler_deg: Vector3 = Vector3(28.0, -8.0, -4.0)
@export_range(0.05, 1.0, 0.01) var raise_tween_sec: float = 0.25

## Tip lift while holding a spell-slot hotkey; spell fires on release as the wand returns forward.
## Pitch sign matches E-raise (+X): tip is on local −Z, so +pitch lifts the lit end.
@export_range(0.05, 0.8, 0.01) var cast_charge_sec: float = 0.14
## Flipped-P release: large tip arc left/up, brief pause, then fast drop. Fire awaits all.
@export_range(0.08, 0.8, 0.01) var cast_release_arc_sec: float = 0.28
@export_range(0.0, 0.25, 0.01) var cast_release_pause_sec: float = 0.05
@export_range(0.04, 0.4, 0.01) var cast_release_drop_sec: float = 0.16
## Max apex offset (full charge). Scaled down when released earlier.
@export var cast_release_apex_position_offset: Vector3 = Vector3(-0.09, 0.15, 0.0)
## Max tip up (+X) / left (+Y) at full charge.
@export var cast_release_apex_basis_euler_deg: Vector3 = Vector3(52.0, 48.0, 8.0)
@export var cast_charge_position_offset: Vector3 = Vector3.ZERO
@export var cast_charge_basis_euler_deg: Vector3 = Vector3(21.0, 0.0, 0.0)
## Defensive lift: tip up and slightly toward screen-right while charging.
@export var defensive_lift_position_offset: Vector3 = Vector3(0.045, 0.09, 0.0)
@export var defensive_lift_basis_euler_deg: Vector3 = Vector3(22.0, -14.0, 4.0)
@export_range(0.05, 0.4, 0.01) var shake_wand_fx_sec: float = 0.14
@export_range(0.05, 0.5, 0.01) var defensive_return_sec: float = 0.18

var _shaft_mesh: MeshInstance3D
var _tip_mesh: MeshInstance3D
var _flashlight_light: SpotLight3D
var _cast_origin: Marker3D
var _fizzle_particles: CPUParticles3D
var _success_particles: CPUParticles3D
var _listen_fx: WandListeningFxScript
var _armed := false
var _flashlight_active := false
var _flame_glow_active := false
var _listen_level: float = 0.0
var _listen_peak: float = 0.0
var _tip_base_scale := Vector3.ONE
var _default_held_transform: Transform3D = Transform3D.IDENTITY
var _has_default_held := false
var _idle_transform: Transform3D = Transform3D.IDENTITY
var _cast_pre_click_transform: Transform3D = Transform3D.IDENTITY
var _tip_rest_local: Vector3 = Vector3(0.0, 0.0, -0.28)
var _raised := false
var _pose_tween: Tween
var _cast_charging := false
var _cast_charge_spell: SpellDefinition
var _cast_charge_duration: float = 0.0
var _cast_charge_elapsed: float = 0.0
var _cast_charge_ready := false
var _cast_fx_started := false
var _cast_power_factor: float = 1.0
var _cast_fx_kind: int = 0


func _ready() -> void:
	ensure_preview_ready()


func ensure_preview_ready() -> void:
	if _cast_origin != null and _success_particles != null:
		return
	if (
		has_node("Model/Shaft")
		or (has_node("Shaft") and has_node("Tip") and has_node("CastOrigin"))
	):
		_bind_existing_meshes()
	else:
		_build_wand_meshes()
	if _success_particles == null:
		_build_particles()
	_tip_rest_local = _resolve_tip_rest_local()
	if not _raised and not _cast_charging and not _has_default_held:
		_capture_default_held_transform()
	set_armed(_armed)
	_refresh_process_enabled()


func is_raised() -> bool:
	return _raised


func set_raised(raised: bool, instant: bool = false) -> void:
	if raised == _raised and not instant:
		return
	if _cast_charging:
		_end_cast_charge_fx()
	_cast_charging = false
	_cast_charge_ready = false
	_cast_fx_started = false
	_raised = raised
	var target := _raised_transform() if raised else _default_held_transform
	if not raised:
		_idle_transform = _default_held_transform
		_cast_pre_click_transform = _default_held_transform
	if _pose_tween != null and is_instance_valid(_pose_tween):
		_pose_tween.kill()
	if instant or raise_tween_sec <= 0.001:
		transform = target
		return
	_pose_tween = create_tween()
	_pose_tween.set_trans(Tween.TRANS_QUAD)
	_pose_tween.set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(self, "transform", target, raise_tween_sec)
	if not raised:
		_pose_tween.tween_callback(_restore_default_held_pose)


func cache_idle_transform() -> void:
	## Call after scene pose is final (before any raise). Locks the default hold.
	if not _raised:
		_capture_default_held_transform()
	_tip_rest_local = _resolve_tip_rest_local()


func _capture_default_held_transform() -> void:
	_default_held_transform = transform
	_idle_transform = _default_held_transform
	_cast_pre_click_transform = _default_held_transform
	_has_default_held = true


func _restore_default_held_pose() -> void:
	if not _has_default_held:
		_capture_default_held_transform()
	if _pose_tween != null and is_instance_valid(_pose_tween):
		_pose_tween.kill()
		_pose_tween = null
	transform = _default_held_transform
	_idle_transform = _default_held_transform
	_cast_pre_click_transform = _default_held_transform


func _raised_transform() -> Transform3D:
	## Compose on the authored default so raise never stacks on a drifted pose.
	var raise_basis := Basis.from_euler(Vector3(
		deg_to_rad(raised_basis_euler_deg.x),
		deg_to_rad(raised_basis_euler_deg.y),
		deg_to_rad(raised_basis_euler_deg.z)
	))
	return Transform3D(
		_default_held_transform.basis * raise_basis,
		_default_held_transform.origin + raised_position_offset
	)


func _process(delta: float) -> void:
	if _cast_charging:
		_tick_cast_charge(delta)
	if _flashlight_active:
		_aim_flashlight_to_crosshair()


func _bind_existing_meshes() -> void:
	var model := get_node_or_null("Model")
	var shaft_path := "Model/Shaft" if model != null else "Shaft"
	var tip_path := "Model/Tip" if model != null else "Tip"
	var origin_path := "Model/CastOrigin" if model != null else "CastOrigin"
	_shaft_mesh = get_node(shaft_path) as MeshInstance3D
	_tip_mesh = get_node(tip_path) as MeshInstance3D
	_cast_origin = get_node(origin_path) as Marker3D
	_flashlight_light = _cast_origin.get_node_or_null("FlashlightBeam") as SpotLight3D
	if _flashlight_light != null:
		## Keep the beam under the wand root so look-at isn't warped by Model scale.
		if _flashlight_light.get_parent() != self:
			_flashlight_light.reparent(self, false)
		_apply_flashlight_beam_settings(_flashlight_light)
		_configure_flashlight_light(_flashlight_light)
	_shaft_mesh.layers = WorldVisualLayersScript.PLAYER_SELF
	_tip_mesh.layers = WorldVisualLayersScript.PLAYER_SELF
	_shaft_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_tip_base_scale = _tip_mesh.scale
	_configure_grip_visual_layers(model)
	_bind_listen_fx(model)


func _configure_grip_visual_layers(model: Node) -> void:
	## Hand / sleeve are authored under Model in player_wand.tscn.
	var hand_path := "Model/Hand" if model != null else "Hand"
	var sleeve_path := "Model/Sleeve" if model != null else "Sleeve"
	for path in [hand_path, sleeve_path]:
		var mesh := get_node_or_null(path) as MeshInstance3D
		if mesh == null:
			continue
		mesh.layers = WorldVisualLayersScript.PLAYER_SELF
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _bind_listen_fx(model: Node) -> void:
	var fx_path := "Model/WandListeningFx" if model != null else "WandListeningFx"
	_listen_fx = get_node_or_null(fx_path) as WandListeningFxScript
	## Runtime starts hidden; editor preview is owned by WandListeningFx.preview_in_editor.
	if _listen_fx != null and not Engine.is_editor_hint():
		_listen_fx.set_active(false)


func set_armed(active: bool) -> void:
	_armed = active
	if not active:
		_listen_level = 0.0
		_listen_peak = 0.0
	if _listen_fx != null:
		## Keep recognition morph alive after session goes idle.
		if active or not bool(_listen_fx.call("is_recognizing")):
			_listen_fx.set_active(active)
	_refresh_process_enabled()
	_refresh_tip_light()


## Shrink listen orbs then play the spell tip recognition FX (before wand lowers).
func play_spell_recognition(spell: SpellDefinition) -> void:
	if _listen_fx != null and _listen_fx.has_method("play_recognition"):
		await _listen_fx.play_recognition(spell)


func _refresh_process_enabled() -> void:
	## Listen FX processes itself; wand process for flashlight aim + cast charge.
	set_process(_flashlight_active or _cast_charging)


func set_listen_level(level: float) -> void:
	var normalized := clampf(level / LISTEN_LEVEL_REFERENCE, 0.0, 1.0)
	_listen_peak = maxf(_listen_peak * LISTEN_PEAK_DECAY, normalized)
	_listen_level = _listen_peak
	_refresh_tip_light()


func get_cast_origin() -> Vector3:
	return _cast_origin.global_position if _cast_origin != null else global_position


func get_cast_direction() -> Vector3:
	## Prefer crosshair aim (same as projectiles); fall back to wand shaft.
	return _resolve_aim_direction()


func play_cast_success(spell: SpellDefinition = null, keep_armed: bool = false) -> void:
	if not keep_armed:
		set_armed(false)
	## Ward already has tip→shield beam FX; tip spark burst reads as a second ball.
	if spell == null or spell.effect_id != "ward":
		_emit_burst(_success_particles, _success_color_for_spell(spell))
	_pulse_tip(_success_pulse_color_for_spell(spell), 0.35)


## Slot press: hold builds tip charge; spells with require_full_charge must finish before fire.
func begin_cast_charge(spell: SpellDefinition = null) -> void:
	if _raised:
		return
	## Always start from the authored hold — never snapshot a mid-flourish pose.
	_restore_default_held_pose()
	_tip_rest_local = _resolve_tip_rest_local()
	_cast_charging = true
	_cast_fx_started = false
	_cast_charge_spell = spell
	_cast_fx_kind = (
		spell.get_wand_fx_kind() if spell != null else SpellDefinition.WandFxKind.P_SHAPED
	)
	_cast_charge_duration = spell.get_charge_time_sec() if spell != null else 1.0
	_cast_charge_elapsed = 0.0
	_cast_charge_ready = not (spell != null and spell.requires_full_charge())
	_cast_power_factor = 1.0 if _cast_charge_duration <= 0.001 else 0.0
	_start_cast_charge_visuals()
	_refresh_process_enabled()


func _start_cast_charge_visuals() -> void:
	if _cast_fx_started or not _cast_charging:
		return
	_cast_fx_started = true
	if _pose_tween != null and is_instance_valid(_pose_tween):
		_pose_tween.kill()
		_pose_tween = null
	match _cast_fx_kind:
		SpellDefinition.WandFxKind.SHAKE:
			_play_shake_wand_fx(false)
		SpellDefinition.WandFxKind.LIFT_DEFENSIVE:
			if not _ward_skips_defensive_lift():
				_apply_lift_defensive_progress(get_cast_power_factor())
		_:
			_start_p_shaped_charge_lift()
	if _listen_fx != null and _listen_fx.has_method("begin_cast_charge_fx"):
		_listen_fx.begin_cast_charge_fx(_cast_charge_spell)
		_listen_fx.set_cast_charge_progress(get_cast_power_factor())


func _start_p_shaped_charge_lift() -> void:
	var apex := _cast_charge_transform(_cast_pre_click_transform)
	var pose_sec := cast_charge_sec
	if _cast_charge_spell != null and _cast_charge_spell.effect_id == "fireball":
		pose_sec = FireballProjectileScript.authored_wand_charge_pose_sec()
	if pose_sec <= 0.001:
		transform = apex
		return
	_pose_tween = create_tween()
	_pose_tween.set_trans(Tween.TRANS_QUAD)
	_pose_tween.set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(self, "transform", apex, pose_sec)


func _tick_cast_charge(delta: float) -> void:
	if not _cast_charging:
		return
	_cast_charge_elapsed += delta
	if (
		_cast_charge_spell != null
		and _cast_charge_spell.requires_full_charge()
	):
		_cast_charge_ready = _cast_charge_elapsed >= _cast_charge_duration
	else:
		_cast_charge_ready = true
	var power := get_cast_power_factor()
	if _cast_fx_started and _listen_fx != null and _listen_fx.has_method("set_cast_charge_progress"):
		_listen_fx.set_cast_charge_progress(power)
	if _cast_fx_started and _cast_fx_kind == SpellDefinition.WandFxKind.LIFT_DEFENSIVE:
		if not _ward_skips_defensive_lift():
			_apply_lift_defensive_progress(power)


func _ward_skips_defensive_lift() -> bool:
	return _cast_charge_spell != null and _cast_charge_spell.effect_id == "ward"


func is_cast_charge_ready() -> bool:
	return _cast_charging and _cast_charge_ready


## 0..1 power from hold time up to spell charge_time (capped). Instant release = 0.
func get_cast_power_factor() -> float:
	if _cast_charging:
		return _compute_cast_power_factor()
	return _cast_power_factor


func _compute_cast_power_factor() -> float:
	if _cast_charge_duration <= 0.001:
		return 1.0
	return clampf(_cast_charge_elapsed / _cast_charge_duration, 0.0, 1.0)


func _end_cast_charge_fx() -> void:
	if _listen_fx != null and _listen_fx.has_method("end_cast_charge_fx"):
		_listen_fx.end_cast_charge_fx()


## End charge and play release FX (p_shaped / shake await; lift_defensive is fire-and-forget).
func return_from_cast_charge() -> void:
	_cast_power_factor = _compute_cast_power_factor()
	var height_t := _cast_power_factor
	var kind := _cast_fx_kind
	var had_fx := _cast_fx_started
	_cast_charging = false
	_cast_charge_ready = false
	_cast_fx_started = false
	_end_cast_charge_fx()
	_refresh_process_enabled()
	if not had_fx:
		_snap_to_pre_click_pose()
		return
	match kind:
		SpellDefinition.WandFxKind.SHAKE:
			await _play_shake_wand_fx(true)
			_snap_to_pre_click_pose()
		SpellDefinition.WandFxKind.LIFT_DEFENSIVE:
			_start_defensive_return_to_idle()
		_:
			_start_p_shaped_wand_fx(height_t)
			await _await_pose_tween()
			_pose_tween = null
			_snap_to_pre_click_pose()


func _await_pose_tween() -> void:
	var tween := _pose_tween
	if tween == null or not is_instance_valid(tween):
		return
	while tween.is_valid() and tween.is_running():
		await get_tree().process_frame


## Workshop: return tip, then tip FX when idle again.
func release_cast(spell: SpellDefinition = null, keep_armed: bool = true) -> void:
	await return_from_cast_charge()
	if not is_instance_valid(self):
		return
	play_cast_success(spell, keep_armed)


func cancel_cast_charge(instant: bool = false, end_fx: bool = true) -> void:
	_cast_power_factor = _compute_cast_power_factor() if _cast_charging else _cast_power_factor
	var height_t := _cast_power_factor
	var kind := _cast_fx_kind
	var had_fx := _cast_fx_started
	_cast_charging = false
	_cast_charge_ready = false
	_cast_fx_started = false
	if end_fx:
		_end_cast_charge_fx()
	_refresh_process_enabled()
	if not had_fx:
		_snap_to_pre_click_pose()
		return
	if instant:
		_snap_to_pre_click_pose()
		return
	match kind:
		SpellDefinition.WandFxKind.LIFT_DEFENSIVE:
			_start_defensive_return_to_idle()
		SpellDefinition.WandFxKind.SHAKE:
			_snap_to_pre_click_pose()
		_:
			_start_p_shaped_wand_fx(height_t)


func fizzle_cast_charge(_instant: bool = false) -> void:
	var had_fx := _cast_fx_started
	var spell := _cast_charge_spell
	## Failed charge: snap the wand home. No P-swing flourish.
	cancel_cast_charge(true, false)
	if had_fx:
		play_fizzle(true, spell)
	else:
		_end_cast_charge_fx()


func _cast_release_duration() -> float:
	return (
		maxf(cast_release_arc_sec, 0.0)
		+ maxf(cast_release_pause_sec, 0.0)
		+ maxf(cast_release_drop_sec, 0.0)
	)


## p_shaped_wand_fx — flipped-P tip path back to the pre-click pose.
func _start_p_shaped_wand_fx(height_t: float = 1.0) -> void:
	if _pose_tween != null and is_instance_valid(_pose_tween):
		_pose_tween.kill()
		_pose_tween = null
	var idle_xf := _cast_pre_click_transform
	if _cast_release_duration() <= 0.001:
		_snap_to_pre_click_pose()
		return
	var from_xf := transform
	var apex_xf := _cast_release_apex_transform(height_t)
	var arc_sec := maxf(cast_release_arc_sec, 0.01)
	var pause_sec := maxf(cast_release_pause_sec, 0.0)
	var drop_sec := maxf(cast_release_drop_sec, 0.01)
	_pose_tween = create_tween()
	_pose_tween.tween_method(
		_sample_cast_release_arc.bind(from_xf, apex_xf),
		0.0,
		1.0,
		arc_sec
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pose_tween.tween_callback(func() -> void:
		if is_instance_valid(self):
			transform = _tip_matched_transform(apex_xf.basis, apex_xf * _tip_rest_local)
	)
	if pause_sec > 0.001:
		_pose_tween.tween_interval(pause_sec)
	_pose_tween.tween_method(
		_sample_cast_release_drop.bind(apex_xf, idle_xf),
		0.0,
		1.0,
		drop_sec
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_pose_tween.tween_callback(_snap_to_pre_click_pose)


## shake_wand_fx — brief tip jitter (channel / drain spells).
func _play_shake_wand_fx(awaitable: bool = false) -> void:
	if _pose_tween != null and is_instance_valid(_pose_tween):
		_pose_tween.kill()
		_pose_tween = null
	var base := _default_held_transform if _has_default_held else transform
	var total := maxf(shake_wand_fx_sec, 0.06)
	var step := total / 5.0
	_pose_tween = create_tween()
	for _i in 4:
		var jitter := Vector3(
			randf_range(-0.01, 0.01),
			randf_range(-0.008, 0.008),
			randf_range(-0.004, 0.004)
		)
		var xf := Transform3D(base.basis, base.origin + base.basis * jitter)
		_pose_tween.tween_property(self, "transform", xf, step)
	_pose_tween.tween_property(self, "transform", base, step)
	if awaitable and _pose_tween != null:
		await _pose_tween.finished
		_pose_tween = null
		_restore_default_held_pose()


## lift_defensive_wand_fx — tip rises up/right with charge progress.
func _apply_lift_defensive_progress(t: float) -> void:
	var u := clampf(t, 0.0, 1.0)
	var base := _cast_pre_click_transform
	var euler := Vector3.ZERO.lerp(defensive_lift_basis_euler_deg, u)
	var pos := Vector3.ZERO.lerp(defensive_lift_position_offset, u)
	var lift_basis := Basis.from_euler(Vector3(
		deg_to_rad(euler.x),
		deg_to_rad(euler.y),
		deg_to_rad(euler.z)
	))
	transform = Transform3D(
		base.basis * lift_basis,
		base.origin + base.basis * pos
	)


func _start_defensive_return_to_idle() -> void:
	if _pose_tween != null and is_instance_valid(_pose_tween):
		_pose_tween.kill()
		_pose_tween = null
	var idle_xf := _cast_pre_click_transform
	if defensive_return_sec <= 0.001:
		_snap_to_pre_click_pose()
		return
	_pose_tween = create_tween()
	_pose_tween.set_trans(Tween.TRANS_QUAD)
	_pose_tween.set_ease(Tween.EASE_IN)
	_pose_tween.tween_property(self, "transform", idle_xf, defensive_return_sec)
	_pose_tween.tween_callback(_snap_to_pre_click_pose)


func _snap_to_pre_click_pose() -> void:
	if not is_instance_valid(self):
		return
	_restore_default_held_pose()


## Apex of the flipped-P bowl; height_t scales size up to the full-charge maximum.
func _cast_release_apex_transform(height_t: float) -> Transform3D:
	## Partial charge → smaller P; full charge → max authored apex.
	var h := lerpf(0.4, 1.0, clampf(height_t, 0.0, 1.0))
	var euler := cast_charge_basis_euler_deg.lerp(cast_release_apex_basis_euler_deg, h)
	var pos := cast_charge_position_offset.lerp(cast_release_apex_position_offset, h)
	var apex_basis := Basis.from_euler(Vector3(
		deg_to_rad(euler.x),
		deg_to_rad(euler.y),
		deg_to_rad(euler.z)
	))
	var base := _cast_pre_click_transform
	return Transform3D(
		base.basis * apex_basis,
		base.origin + base.basis * pos
	)


## Tip draws a semicircle from charge → apex (left/up bulge).
func _sample_cast_release_arc(t: float, from_xf: Transform3D, apex_xf: Transform3D) -> void:
	var tip_local := _tip_rest_local
	var p0 := from_xf * tip_local
	var p1 := apex_xf * tip_local
	var mid := (p0 + p1) * 0.5
	var radius_vec := p0 - mid
	var chord := p1 - p0
	var left_up := (_cast_pre_click_transform.basis * Vector3(-1.0, 1.0, 0.0)).normalized()
	var perp := chord.cross(left_up)
	if perp.length_squared() < 0.0000001:
		perp = chord.cross(_cast_pre_click_transform.basis.y)
	perp = perp.cross(chord)
	## Slightly fatter than a flat semicircle so the bowl reads larger.
	var bulge := radius_vec.length() * 1.35
	if perp.length_squared() < 0.0000001:
		perp = left_up * bulge
	else:
		perp = perp.normalized() * bulge
	if perp.dot(left_up) < 0.0:
		perp = -perp
	var tip := mid + radius_vec * cos(PI * t) + perp * sin(PI * t)
	var pose_basis := from_xf.basis.slerp(apex_xf.basis, clampf(t, 0.0, 1.0)).orthonormalized()
	transform = _tip_matched_transform(pose_basis, tip)


## Straight tip drop from apex to the exact pre-click tip / pose.
func _sample_cast_release_drop(t: float, apex_xf: Transform3D, idle_xf: Transform3D) -> void:
	var tip_local := _tip_rest_local
	var p0 := apex_xf * tip_local
	var p1 := idle_xf * tip_local
	var u := clampf(t, 0.0, 1.0)
	var tip := p0.lerp(p1, u)
	var pose_basis := apex_xf.basis.slerp(idle_xf.basis, u).orthonormalized()
	transform = _tip_matched_transform(pose_basis, tip)


func _tip_matched_transform(pose_basis: Basis, tip_parent: Vector3) -> Transform3D:
	return Transform3D(pose_basis, tip_parent - pose_basis * _tip_rest_local)


func play_cast_animation(spell: SpellDefinition, keep_armed: bool = true) -> void:
	begin_cast_charge(spell)
	var wait := 0.35
	if spell != null:
		wait = maxf(spell.get_charge_time_sec(), 0.35)
	await get_tree().create_timer(wait, true, true).timeout
	if not is_instance_valid(self):
		return
	await release_cast(spell, keep_armed)


func _cast_charge_transform(base: Transform3D) -> Transform3D:
	var flourish_basis := Basis.from_euler(Vector3(
		deg_to_rad(cast_charge_basis_euler_deg.x),
		deg_to_rad(cast_charge_basis_euler_deg.y),
		deg_to_rad(cast_charge_basis_euler_deg.z)
	))
	return Transform3D(
		base.basis * flourish_basis,
		base.origin + base.basis * cast_charge_position_offset
	)


func play_fizzle(keep_armed: bool = false, spell: SpellDefinition = null) -> void:
	if not keep_armed:
		set_armed(false)
	if _listen_fx != null and _listen_fx.has_method("pop_cast_charge_fx"):
		_listen_fx.pop_cast_charge_fx()
	else:
		_end_cast_charge_fx()
	if spell != null and spell.effect_id == "fireball":
		_pulse_tip(Color(0.55, 0.48, 0.42), 0.28)
		return
	_emit_burst(_fizzle_particles, Color(0.55, 0.5, 0.65))
	_pulse_tip(Color(0.65, 0.55, 0.75), 0.2)


func set_flashlight_enabled(active: bool) -> void:
	_flashlight_active = active
	_refresh_process_enabled()
	if _flashlight_light == null:
		return
	_flashlight_light.visible = active
	_flashlight_light.light_energy = FLASHLIGHT_ENERGY if active else 0.0
	if active:
		_aim_flashlight_to_crosshair()
	_refresh_tip_light()


func is_flashlight_active() -> bool:
	return _flashlight_active


func _aim_flashlight_to_crosshair() -> void:
	if _flashlight_light == null or not is_instance_valid(_flashlight_light):
		return
	var tip := get_cast_origin()
	var dir := _resolve_aim_direction()
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.RIGHT
	## SpotLight aims along local -Z; pin origin to tip every frame.
	_flashlight_light.global_transform = Transform3D(Basis.looking_at(dir, up), tip)


func _resolve_aim_direction() -> Vector3:
	var player := _owner_playable()
	if (
		player != null
		and player.is_multiplayer_authority()
		and player.has_method("get_wand_cast_direction")
	):
		return player.call("get_wand_cast_direction") as Vector3
	var pivot := _camera_pivot()
	if pivot != null:
		return -pivot.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


func _owner_playable() -> CharacterBody3D:
	var node: Node = self
	while node != null:
		if node is CharacterBody3D and node.has_method("get_wand_cast_direction"):
			return node as CharacterBody3D
		node = node.get_parent()
	return null


func _camera_pivot() -> Node3D:
	var node: Node = get_parent()
	while node != null:
		if node.name == "CameraPivot" and node is Node3D:
			return node as Node3D
		node = node.get_parent()
	return null


func set_flame_glow_enabled(active: bool) -> void:
	_flame_glow_active = active
	_refresh_tip_light()


func is_flame_glow_active() -> bool:
	return _flame_glow_active


func _build_wand_meshes() -> void:
	var tip_offset := _tip_local_position()

	_shaft_mesh = MeshInstance3D.new()
	_shaft_mesh.name = "Shaft"
	var shaft := CylinderMesh.new()
	shaft.top_radius = SHAFT_TOP_RADIUS
	shaft.bottom_radius = SHAFT_BOTTOM_RADIUS
	shaft.height = SHAFT_LENGTH
	_shaft_mesh.mesh = shaft
	_shaft_mesh.position = tip_offset * 0.5
	_shaft_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	shaft_mat.albedo_color = Color(0.18, 0.12, 0.1)
	shaft_mat.roughness = 0.55
	shaft_mat.metallic = 0.35
	_shaft_mesh.material_override = shaft_mat
	_shaft_mesh.layers = WorldVisualLayersScript.PLAYER_SELF
	_shaft_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_shaft_mesh)

	_tip_mesh = MeshInstance3D.new()
	_tip_mesh.name = "Tip"
	var tip := SphereMesh.new()
	tip.radius = TIP_RADIUS
	tip.height = TIP_RADIUS * 2.0
	_tip_mesh.mesh = tip
	_tip_mesh.position = tip_offset
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.85, 0.88, 0.95)
	tip_mat.emission_enabled = true
	tip_mat.emission = Color.WHITE
	tip_mat.emission_energy_multiplier = 0.0
	tip_mat.roughness = 0.15
	tip_mat.metallic = 0.2
	_tip_mesh.material_override = tip_mat
	_tip_mesh.layers = WorldVisualLayersScript.PLAYER_SELF
	add_child(_tip_mesh)
	_tip_base_scale = _tip_mesh.scale

	_cast_origin = Marker3D.new()
	_cast_origin.name = "CastOrigin"
	_cast_origin.position = tip_offset + Vector3(0.0, 0.0, -0.025)
	add_child(_cast_origin)

	_flashlight_light = SpotLight3D.new()
	_flashlight_light.name = "FlashlightBeam"
	_apply_flashlight_beam_settings(_flashlight_light)
	_flashlight_light.light_energy = 0.0
	_flashlight_light.visible = false
	_configure_flashlight_light(_flashlight_light)
	add_child(_flashlight_light)


func _build_particles() -> void:
	_fizzle_particles = _make_burst_particles("FizzleParticles", Color(0.55, 0.5, 0.65))
	_success_particles = _make_burst_particles("SuccessParticles", Color(1.0, 0.92, 0.75))
	add_child(_fizzle_particles)
	add_child(_success_particles)


func _make_burst_particles(node_name: String, color: Color) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.position = _tip_local_position()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 16
	particles.lifetime = 0.4
	particles.local_coords = true
	particles.direction = Vector3(0.0, 0.0, -1.0)
	particles.spread = 35.0
	particles.initial_velocity_min = 0.6
	particles.initial_velocity_max = 1.6
	particles.gravity = Vector3(0.0, -2.0, 0.0)
	particles.scale_amount_min = 0.025
	particles.scale_amount_max = 0.06
	particles.color = color
	return particles


func _refresh_tip_light() -> void:
	if _armed:
		var visual := _listen_visual_strength(_listen_level)
		var emission := TIP_EMISSION_ARMED + visual * TIP_EMISSION_LISTEN_MAX
		_apply_tip_visual(visual, emission)
		_set_tip_visible(true)
		return
	if _flame_glow_active:
		_apply_flame_glow_visual()
		_set_tip_visible(true)
		return
	if _flashlight_active:
		_apply_flashlight_tip_visual()
		_set_tip_visible(true)
		return
	_apply_tip_visual(0.0, 0.0)
	_set_tip_visible(false)


static func _listen_visual_strength(listen_level: float) -> float:
	return pow(clampf(listen_level, 0.0, 1.0), LISTEN_VISUAL_CURVE)


func _apply_tip_visual(visual: float, emission: float) -> void:
	if _tip_mesh == null:
		return
	if _tip_mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _tip_mesh.material_override
		## Dim when armed / quiet; brighten with voice volume.
		var dim := Color(0.55, 0.62, 0.78)
		var bright := Color(1.0, 0.98, 0.92)
		mat.albedo_color = dim.lerp(bright, visual)
		var glow := Color(0.72, 0.82, 1.0).lerp(Color(1.0, 0.94, 0.78), visual)
		mat.emission = glow
		mat.emission_energy_multiplier = emission
	_tip_mesh.scale = _tip_base_scale * (1.0 + visual * TIP_SCALE_LISTEN_BOOST)


func _apply_flashlight_tip_visual() -> void:
	if _tip_mesh == null:
		return
	if _tip_mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _tip_mesh.material_override
		mat.albedo_color = FLASHLIGHT_COLOR.lightened(0.15)
		mat.emission = FLASHLIGHT_COLOR
		mat.emission_energy_multiplier = FLASHLIGHT_TIP_EMISSION
	_tip_mesh.scale = _tip_base_scale


func _apply_flame_glow_visual() -> void:
	if _tip_mesh == null:
		return
	if _tip_mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _tip_mesh.material_override
		mat.albedo_color = FLAME_GLOW_COLOR.lightened(0.12)
		mat.emission = FLAME_GLOW_COLOR
		mat.emission_energy_multiplier = FLAME_GLOW_EMISSION
	_tip_mesh.scale = _tip_base_scale


func _pulse_tip(color: Color, duration: float) -> void:
	_set_tip_visible(true)
	_set_tip_emission(color, 2.0)
	var tween := create_tween()
	tween.tween_method(
		func(energy: float) -> void:
			_set_tip_emission(color, energy),
		2.0,
		0.0,
		duration
	)
	tween.tween_callback(_refresh_tip_light)


func _set_tip_visible(tip_on: bool) -> void:
	if _tip_mesh != null:
		_tip_mesh.visible = tip_on


func _emit_burst(particles: CPUParticles3D, color: Color) -> void:
	if particles == null:
		return
	particles.color = color
	particles.position = _tip_local_position()
	var aim := _resolve_aim_direction()
	if aim.length_squared() > 0.0001:
		particles.direction = (global_transform.basis.inverse() * aim.normalized()).normalized()
	else:
		particles.direction = Vector3(0.0, 0.0, -1.0)
	particles.restart()
	particles.emitting = true


func _configure_world_light(light: Light3D) -> void:
	light.light_cull_mask = WORLD_LIGHT_CULL_MASK
	light.shadow_caster_mask = WORLD_LIGHT_CULL_MASK
	light.light_specular = 0.55
	light.shadow_enabled = true
	light.shadow_bias = 0.04
	light.shadow_normal_bias = 1.0


func _configure_flashlight_light(light: Light3D) -> void:
	light.light_cull_mask = WORLD_LIGHT_CULL_MASK
	light.shadow_caster_mask = WORLD_LIGHT_CULL_MASK
	light.light_specular = 0.22
	## Shadows so the beam and fog scatter stop at maze walls.
	light.shadow_enabled = true
	light.shadow_bias = 0.04
	light.shadow_normal_bias = 1.0
	light.light_volumetric_fog_energy = 8.0


func _apply_flashlight_beam_settings(light: SpotLight3D) -> void:
	## spot_angle is degrees in Godot 4 — never pass radians.
	light.spot_range = FLASHLIGHT_RANGE
	light.spot_angle = FLASHLIGHT_HALF_ANGLE_DEG
	light.spot_attenuation = FLASHLIGHT_ATTENUATION
	light.light_size = FLASHLIGHT_LIGHT_SIZE
	light.light_color = FLASHLIGHT_COLOR
	light.light_energy = FLASHLIGHT_ENERGY if _flashlight_active else 0.0


func _set_tip_emission(color: Color, energy: float) -> void:
	if _tip_mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _tip_mesh.material_override
		mat.emission = color
		mat.emission_energy_multiplier = energy


func _tip_local_position() -> Vector3:
	return _tip_rest_local


## Authored tip offset in wand space via child transforms (stable during pose tweens).
func _resolve_tip_rest_local() -> Vector3:
	if _cast_origin == null or not is_instance_valid(_cast_origin):
		var model := get_node_or_null("Model") as Node3D
		if model != null:
			return model.transform * Vector3(0.0, 0.0, -SHAFT_LENGTH)
		return Vector3(0.0, 0.0, -SHAFT_LENGTH)
	var xf := Transform3D.IDENTITY
	var node: Node = _cast_origin
	while node != null and node != self:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	return xf.origin


func _success_color_for_spell(spell: SpellDefinition) -> Color:
	if spell == null:
		return Color(1.0, 0.95, 0.85)
	return spell.color


func _success_pulse_color_for_spell(spell: SpellDefinition) -> Color:
	if spell == null:
		return Color(1.0, 0.98, 0.92)
	return spell.color.lightened(0.2)
