@tool
class_name WretchRitualPose
extends Node3D

## Pack ritual FX: green orb between hands. Alert = outer pulse only.
## Chase = full body ritual + deep dark-green orb core.

enum RitualPhase { OFF, ALERT, CHASE }

@export var pulse_min_scale: float = 0.55
@export var pulse_max_scale: float = 1.15
@export var pulse_hz: float = 1.4
@export var straighten_sec: float = 0.45
## Head pitch (degrees). Positive tips face toward +Y / sky (−Z facing characters).
@export var look_up_pitch_deg: float = 45.0
## Spot beam length into the sky (meters).
@export var cone_range: float = 5.0
## Tight cone angle (degrees).
@export_range(4.0, 30.0, 0.5) var cone_angle_deg: float = 9.0
## Start the beam this far along the face-forward axis from each eye/mouth.
@export var cone_forward_offset_m: float = 1.0
@export var glow_color: Color = Color(0.25, 1.0, 0.35, 1.0)
## Inner core used only in chase to distinguish from alert.
@export var chase_core_color: Color = Color(0.83, 0.68, 0.22, 1.0)

var _phase: int = RitualPhase.OFF
var _active: bool = false
var _blend: float = 0.0
var _orb: MeshInstance3D = null
var _orb_core: MeshInstance3D = null
var _orb_light: OmniLight3D = null
var _mouth: MeshInstance3D = null
var _mouth_light: OmniLight3D = null
var _mouth_cone: SpotLight3D = null
var _eye_cones: Array[SpotLight3D] = []
var _eyes_root: Node3D = null
var _head: Node3D = null
var _mid_body: Node3D = null
var _body: Node3D = null
var _pulse_t: float = 0.0
var _built: bool = false
var _orb_charge_mult: float = 1.0
var _orb_charge_target: float = 1.0
var _orb_hidden_for_launch: bool = false

## Captured patrol (hunched) transforms — eyes stay local-forward on the head.
var _head_patrol: Transform3D = Transform3D.IDENTITY
var _mid_patrol: Transform3D = Transform3D.IDENTITY
var _body_patrol: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	_build_if_needed()
	set_ritual_phase(RitualPhase.OFF)
	set_process(true)


func set_active(active: bool) -> void:
	## Back-compat for command-pack / lookdev callers.
	set_ritual_phase(RitualPhase.CHASE if active else RitualPhase.OFF)


func set_ritual_phase(phase: int) -> void:
	_build_if_needed()
	_phase = phase
	_active = phase != RitualPhase.OFF
	_refresh_ritual_visibility()
	## Snap off instantly when leaving so patrol eyes face forward again.
	if not _active:
		_blend = 0.0
		_orb_charge_mult = 1.0
		_orb_charge_target = 1.0
		_orb_hidden_for_launch = false
		_apply_body_blend(0.0)


func set_pack_orb_charge(mult: float) -> void:
	_orb_charge_target = maxf(1.0, mult)


func get_pack_orb_global_position() -> Vector3:
	_build_if_needed()
	_place_orb_between_hands()
	if _orb != null:
		return _orb.global_position
	var monster := get_parent()
	if monster is Node3D:
		return (monster as Node3D).global_position + Vector3(0.0, 0.7, 0.0)
	return global_position


func hide_pack_orb_for_launch() -> void:
	_orb_hidden_for_launch = true
	_refresh_ritual_visibility()


func restore_pack_orb_after_launch() -> void:
	_orb_hidden_for_launch = false
	_orb_charge_mult = 1.0
	_orb_charge_target = 1.0
	_refresh_ritual_visibility()


func is_ritual_active() -> bool:
	return _active


func get_ritual_phase() -> int:
	return _phase


func _refresh_ritual_visibility() -> void:
	var show_orb := _active and not _orb_hidden_for_launch
	var show_chase_fx := _phase == RitualPhase.CHASE
	var show_core := show_orb and show_chase_fx
	if _orb != null:
		_orb.visible = show_orb
	if _orb_core != null:
		_orb_core.visible = show_core
	if _orb_light != null:
		_orb_light.visible = show_orb
	if _mouth != null:
		_mouth.visible = show_chase_fx
	if _mouth_light != null:
		_mouth_light.visible = show_chase_fx
	if _mouth_cone != null:
		_mouth_cone.visible = show_chase_fx
	for cone in _eye_cones:
		if cone != null:
			cone.visible = show_chase_fx


func _process(delta: float) -> void:
	_build_if_needed()
	_place_orb_between_hands()
	## Body straighten only in chase; alert keeps the hunched pose with orb only.
	var target := 1.0 if _phase == RitualPhase.CHASE else 0.0
	var step := delta / maxf(straighten_sec, 0.05)
	if _blend < target:
		_blend = minf(1.0, _blend + step)
	elif _blend > target:
		_blend = maxf(0.0, _blend - step)
	_apply_body_blend(_blend)
	_orb_charge_mult = move_toward(_orb_charge_mult, _orb_charge_target, delta * 3.5)
	if not _active and _blend <= 0.0:
		return
	if _active:
		_pulse_t += delta * TAU * pulse_hz
		var wave := (sin(_pulse_t) + 1.0) * 0.5
		var scale_v := lerpf(pulse_min_scale, pulse_max_scale, wave) * _orb_charge_mult
		if _orb != null:
			_orb.scale = Vector3.ONE * scale_v
		if _orb_core != null:
			## Core stays a bit smaller than the outer shell so it reads as a heart.
			_orb_core.scale = Vector3.ONE * (scale_v * 0.55)
		if _orb_light != null:
			_orb_light.light_energy = lerpf(1.6, 3.8, wave) * _orb_charge_mult
			_orb_light.omni_range = 1.8 * _orb_charge_mult


func _build_if_needed() -> void:
	if _built:
		return
	_built = true
	var monster := get_parent()
	if monster == null:
		return

	_body = monster.get_node_or_null("Body") as Node3D
	_mid_body = monster.get_node_or_null("%MidBody") as Node3D
	if _mid_body == null:
		_mid_body = monster.get_node_or_null("MidBody") as Node3D
	_head = monster.get_node_or_null("Head") as Node3D
	_eyes_root = monster.get_node_or_null("%Eyes") as Node3D
	if _eyes_root == null:
		_eyes_root = monster.get_node_or_null("Head/Eyes") as Node3D

	if _body != null:
		_body_patrol = _body.transform
	if _mid_body != null:
		_mid_patrol = _mid_body.transform
	if _head != null:
		_head_patrol = _head.transform

	_orb = MeshInstance3D.new()
	_orb.name = "PackOrb"
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.11
	orb_mesh.height = 0.22
	_orb.mesh = orb_mesh
	_orb.material_override = _make_glow_mat(0.95)
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)

	_orb_core = MeshInstance3D.new()
	_orb_core.name = "PackOrbCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.11
	core_mesh.height = 0.22
	_orb_core.mesh = core_mesh
	_orb_core.material_override = _make_core_mat()
	_orb_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb_core.visible = false
	_orb.add_child(_orb_core)

	_orb_light = OmniLight3D.new()
	_orb_light.name = "PackOrbLight"
	_orb_light.light_color = glow_color
	_orb_light.light_energy = 2.4
	_orb_light.omni_range = 1.8
	_orb_light.shadow_enabled = false
	add_child(_orb_light)

	## Circular mouth — same sphere language as the eyes.
	_mouth = MeshInstance3D.new()
	_mouth.name = "RitualMouth"
	var mouth_mesh := SphereMesh.new()
	mouth_mesh.radius = 0.04
	mouth_mesh.height = 0.08
	_mouth.mesh = mouth_mesh
	_mouth.material_override = _make_glow_mat(0.95)
	_mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## On the face, below the eyes, facing local −Z with the head.
	_mouth.position = Vector3(0.0, -0.05, -0.175)
	if _head != null:
		_head.add_child(_mouth)
	else:
		add_child(_mouth)

	_mouth_light = OmniLight3D.new()
	_mouth_light.name = "MouthGlow"
	_mouth_light.light_color = glow_color
	_mouth_light.light_energy = 2.0
	_mouth_light.omni_range = 1.2
	_mouth_light.shadow_enabled = false
	_mouth.add_child(_mouth_light)

	_mouth_cone = _make_sky_cone("MouthCone")
	_mouth.add_child(_mouth_cone)

	if _eyes_root != null:
		for eye_name in ["LeftEye", "RightEye"]:
			var eye := _eyes_root.get_node_or_null(eye_name) as Node3D
			if eye == null:
				continue
			var cone := _make_sky_cone("%sCone" % eye_name)
			eye.add_child(cone)
			_eye_cones.append(cone)

	_apply_body_blend(0.0)


func _make_sky_cone(cone_name: String) -> SpotLight3D:
	var cone := SpotLight3D.new()
	cone.name = cone_name
	cone.light_color = glow_color
	cone.light_energy = 4.5
	cone.spot_range = cone_range
	cone.spot_angle = cone_angle_deg
	cone.shadow_enabled = false
	## Origin sits 1m along face-forward (−Z). Beam keeps the same upward angle
	## as the eyes/mouth once the head pitches in ritual.
	cone.position = Vector3(0.0, 0.0, -cone_forward_offset_m)
	return cone


func _make_glow_mat(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, alpha)
	mat.emission_enabled = true
	mat.emission = glow_color
	mat.emission_energy_multiplier = 4.5
	return mat


func _make_core_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = chase_core_color
	mat.metallic = 0.92
	mat.roughness = 0.28
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.emission_enabled = true
	mat.emission = chase_core_color.lightened(0.15)
	mat.emission_energy_multiplier = 0.55
	return mat


func _place_orb_between_hands() -> void:
	var monster := get_parent()
	if monster == null or _orb == null:
		return
	var right := monster.get_node_or_null("%RightHand") as Node3D
	var left := monster.get_node_or_null("%LeftHand") as Node3D
	if right == null or left == null:
		return
	var mid: Vector3 = (right.global_position + left.global_position) * 0.5
	_orb.global_position = mid
	if _orb_light != null:
		_orb_light.global_position = mid


func _chase_mid_transform() -> Transform3D:
	## Stack taller / less hunched forward.
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.72, 0.0))


func _chase_head_transform() -> Transform3D:
	## Tall stack + pitch so local −Z (eyes/mouth) aim at the sky.
	var look_basis := Basis.from_euler(Vector3(deg_to_rad(look_up_pitch_deg), 0.0, 0.0))
	return Transform3D(look_basis, Vector3(0.0, 1.22, 0.02))


func _chase_body_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22, 0.0))


func _apply_body_blend(weight: float) -> void:
	var w := clampf(weight, 0.0, 1.0)
	if _body != null:
		_body.transform = _body_patrol.interpolate_with(_chase_body_transform(), w)
	if _mid_body != null:
		_mid_body.transform = _mid_patrol.interpolate_with(_chase_mid_transform(), w)
	if _head != null:
		_head.transform = _head_patrol.interpolate_with(_chase_head_transform(), w)
