@tool
class_name WandListeningFx
extends Node3D

## Wand E-listen tip FX. Authored under player_wand.tscn → Model/WandListeningFx.

enum ShapeKind { SPHERE, BOX, CAPSULE, PRISM }

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const WARD_BUBBLE_COLOR := Color(0.35, 0.65, 1.0, 0.38)
const WARD_BUBBLE_EDGE := Color(0.18, 0.42, 0.85, 0.7)
const BASEBALL_RADIUS_M := 0.037
const RECOGNITION_SHRINK_SEC := 0.14
const RECOGNITION_GROW_SEC := 0.18
const RECOGNITION_HOLD_SEC := 0.28

@export_group("Editor Preview")
@export var preview_in_editor: bool = false:
	set(value):
		preview_in_editor = value
		if Engine.is_editor_hint() and _ready_done:
			set_active(preview_in_editor)

@export_group("Overall")
@export_range(0.15, 3.0, 0.01) var overall_size: float = 1.0:
	set(value):
		overall_size = value
		_queue_apply()
@export_range(1.0, 120.0, 1.0) var sparks_per_second: float = 48.0:
	set(value):
		sparks_per_second = value
		_queue_apply()

@export_group("Outer Shell")
@export var outer_shape: ShapeKind = ShapeKind.SPHERE:
	set(value):
		outer_shape = value
		_queue_apply()
@export_range(0.006, 0.08, 0.001) var outer_size: float = 0.022:
	set(value):
		outer_size = value
		_queue_apply()
@export var outer_color: Color = Color(0.55, 0.18, 0.78, 1.0):
	set(value):
		outer_color = value
		_queue_apply()
@export_range(0.0, 1.0, 0.01) var outer_transparency: float = 0.4:
	set(value):
		outer_transparency = value
		_queue_apply()
@export_range(0.0, 1.0, 0.01) var outer_veining: float = 0.55:
	set(value):
		outer_veining = value
		_queue_apply()
@export var outer_spin_deg_per_sec: Vector3 = Vector3(66.0, 106.0, 20.0):
	set(value):
		outer_spin_deg_per_sec = value

@export_group("Middle Layer")
@export var middle_shape: ShapeKind = ShapeKind.SPHERE:
	set(value):
		middle_shape = value
		_queue_apply()
@export_range(0.005, 0.07, 0.001) var middle_size: float = 0.018:
	set(value):
		middle_size = 0.018 if value == null else float(value)
		_queue_apply()
@export var middle_color: Color = Color(0.72, 0.28, 0.95, 1.0):
	set(value):
		middle_color = Color(0.72, 0.28, 0.95, 1.0) if value == null else value
		_queue_apply()
@export_range(0.0, 1.0, 0.01) var middle_transparency: float = 0.4:
	set(value):
		middle_transparency = 0.4 if value == null else float(value)
		_queue_apply()
@export_range(0.0, 1.0, 0.01) var middle_veining: float = 0.55:
	set(value):
		middle_veining = 0.55 if value == null else float(value)
		_queue_apply()
@export var middle_spin_deg_per_sec: Vector3 = Vector3(28.0, -78.0, 95.0):
	set(value):
		middle_spin_deg_per_sec = (
			Vector3(28.0, -78.0, 95.0) if value == null else value
		)

@export_group("Inner Core")
@export var inner_shape: ShapeKind = ShapeKind.SPHERE:
	set(value):
		inner_shape = value
		_queue_apply()
@export_range(0.004, 0.06, 0.001) var inner_size: float = 0.014:
	set(value):
		inner_size = value
		_queue_apply()
@export var inner_color: Color = Color(0.04, 0.03, 0.06, 1.0):
	set(value):
		inner_color = value
		_queue_apply()
@export var inner_spot_color: Color = Color(1.0, 0.86, 0.28, 1.0):
	set(value):
		inner_spot_color = value
		_queue_apply()
@export_range(0.0, 1.0, 0.01) var inner_spot_amount: float = 0.45:
	set(value):
		inner_spot_amount = value
		_queue_apply()
@export var inner_spin_deg_per_sec: Vector3 = Vector3(-43.0, -123.0, 14.0):
	set(value):
		inner_spin_deg_per_sec = value
@export_range(0.0, 1.0, 0.01) var pulse_amount: float = 0.55:
	set(value):
		pulse_amount = value
@export_range(0.1, 4.0, 0.05) var pulse_hz: float = 1.15:
	set(value):
		pulse_hz = value

@export_group("Sparks")
@export var spark_color_a: Color = Color(0.25, 0.95, 0.92, 1.0):
	set(value):
		spark_color_a = value
		_queue_apply()
@export var spark_color_b: Color = Color(1.0, 0.85, 0.28, 1.0):
	set(value):
		spark_color_b = value
		_queue_apply()
@export var spark_color_c: Color = Color(0.12, 0.08, 0.18, 1.0):
	set(value):
		spark_color_c = value
		_queue_apply()
@export_range(0.2, 12.0, 0.05) var spark_velocity: float = 3.6:
	set(value):
		spark_velocity = value
		_queue_apply()
@export_range(0.02, 1.5, 0.01) var spark_travel_distance: float = 0.22:
	set(value):
		spark_travel_distance = value
		_queue_apply()
@export_range(0.002, 0.2, 0.001) var spark_size: float = 0.035:
	set(value):
		spark_size = value
		_queue_apply()

var _outer: MeshInstance3D
var _middle: MeshInstance3D
var _inner: MeshInstance3D
var _recognition: Node3D
var _recognition_bubble: MeshInstance3D
var _recognition_rim: MeshInstance3D
var _sparks: Array[CPUParticles3D] = []
var _outer_noise: FastNoiseLite
var _outer_noise_tex: NoiseTexture2D
var _middle_noise: FastNoiseLite
var _middle_noise_tex: NoiseTexture2D
var _inner_noise: FastNoiseLite
var _inner_noise_tex: NoiseTexture2D
var _spark_fade: Gradient
var _active := false
var _recognizing := false
var _cast_charging_fx := false
var _cast_charge_fx: CastChargeFx
var _charge_spell_color := Color(1.0, 1.0, 1.0, 0.4)
var _pulse_phase: float = 0.0
var _inner_base_scale := Vector3.ONE
var _shell_base_scales: Dictionary = {}
var _apply_queued := false
var _ready_done := false
var _recognition_tween: Tween
var _charge_pop_tween: Tween
var _charge_popping := false

func _ready() -> void:
	_ensure_nodes()
	_ready_done = true
	var cam := get_node_or_null("EditorCamera") as Camera3D
	if cam != null:
		cam.current = Engine.is_editor_hint() and is_inside_tree() and (
			get_tree().edited_scene_root == self
		)
	_apply_all()
	set_active(Engine.is_editor_hint() and preview_in_editor)

func is_active() -> bool:
	return _active

func is_recognizing() -> bool:
	return _recognizing

func begin_cast_charge_fx(spell: SpellDefinition) -> void:
	_ensure_nodes()
	_ensure_recognition_nodes()
	_charge_popping = false
	if _charge_pop_tween != null and is_instance_valid(_charge_pop_tween):
		_charge_pop_tween.kill()
		_charge_pop_tween = null
	_cast_charging_fx = true
	_hide_listen_shells()
	_hide_recognition()
	_charge_spell_color = (
		spell.get_display_color() if spell != null else Color(0.75, 0.7, 0.95)
	)
	if spell != null and spell.effect_id == "ward":
		## Ward channels a world beam on the shield, not a wand-tip orb.
		_clear_cast_charge_fx()
	else:
		_spawn_cast_charge_fx(spell)
	visible = true
	set_process(true)
	_apply_cast_charge_sparks(_charge_spell_color)
	set_cast_charge_progress(0.0 if spell == null or not spell.is_channelled() else 1.0)


func set_replicated_charge_progress(t: float) -> void:
	var factor := clampf(t, 0.0, 1.0)
	if factor <= 0.02:
		if _cast_charging_fx:
			end_cast_charge_fx()
		return
	if not _cast_charging_fx:
		begin_cast_charge_fx(null)
	set_cast_charge_progress(factor)

func _spawn_cast_charge_fx(spell: SpellDefinition) -> void:
	_clear_cast_charge_fx()
	var host := _ensure_cast_charge_host()
	var scene := SpellDefinition.CAST_GROWING_ORB
	if spell != null:
		scene = spell.get_cast_charge_scene()
	if scene == null:
		return
	var inst := scene.instantiate()
	host.add_child(inst)
	_cast_charge_fx = inst as CastChargeFx
	if _cast_charge_fx != null:
		_cast_charge_fx.setup_cast_charge(_charge_spell_color, _visual_layers())
	host.visible = true


func _ensure_cast_charge_host() -> Node3D:
	var host := get_node_or_null("CastChargeHost") as Node3D
	if host == null:
		host = Node3D.new()
		host.name = "CastChargeHost"
		add_child(host)
	return host


func _clear_cast_charge_fx() -> void:
	_cast_charge_fx = null
	var host := get_node_or_null("CastChargeHost") as Node3D
	if host == null:
		return
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	host.visible = false


func set_cast_charge_progress(t: float) -> void:
	if _charge_popping or not _cast_charging_fx or _cast_charge_fx == null:
		return
	_cast_charge_fx.set_cast_charge_progress(t)


func pop_cast_charge_fx() -> void:
	if _charge_popping or not _cast_charging_fx or _cast_charge_fx == null:
		return
	if _charge_pop_tween != null and is_instance_valid(_charge_pop_tween):
		_charge_pop_tween.kill()
	_charge_popping = true
	for sparks in _sparks:
		if sparks != null:
			sparks.emitting = false
	var pop_s := Vector3.ONE * maxf(_cast_charge_fx.scale.x * 1.7, 1.25)
	_charge_pop_tween = create_tween()
	_charge_pop_tween.tween_property(_cast_charge_fx, "scale", pop_s, 0.08)
	_charge_pop_tween.tween_property(_cast_charge_fx, "scale", Vector3.ZERO, 0.14)
	_charge_pop_tween.tween_callback(end_cast_charge_fx)


func end_cast_charge_fx() -> void:
	_charge_popping = false
	if _charge_pop_tween != null and is_instance_valid(_charge_pop_tween):
		_charge_pop_tween.kill()
	_charge_pop_tween = null
	_cast_charging_fx = false
	_clear_cast_charge_fx()
	_hide_recognition()
	_apply_sparks()
	set_process(_active)
	if not _active and not _recognizing:
		visible = false

func _hide_listen_shells() -> void:
	for shell in [_outer, _middle, _inner]:
		if shell != null:
			shell.visible = false

func set_active(active: bool) -> void:
	if _recognizing and not active:
		_active = false
		set_process(false)
		for sparks in _sparks:
			if sparks != null:
				sparks.emitting = false
		return
	if _cast_charging_fx and not active:
		_active = false
		set_process(true)
		_hide_listen_shells()
		return
	_active = active
	visible = active or _cast_charging_fx
	set_process(active or _cast_charging_fx)
	if not _cast_charging_fx:
		for sparks in _sparks:
			if sparks != null:
				sparks.emitting = active
				if active and Engine.is_editor_hint():
					sparks.restart()
	if active:
		_pulse_phase = 0.0
		_restore_shell_scales()
		for shell in [_outer, _middle, _inner]:
			if shell != null:
				shell.visible = true
		if not _cast_charging_fx:
			_hide_recognition()
	elif not _recognizing and not _cast_charging_fx:
		_hide_recognition()

func play_recognition(spell: SpellDefinition) -> void:
	if spell == null:
		return
	_ensure_nodes()
	_recognizing = true
	_active = false
	set_process(false)
	visible = true
	for sparks in _sparks:
		if sparks != null:
			sparks.emitting = false
	_cache_shell_scales()
	if _recognition_tween != null and is_instance_valid(_recognition_tween):
		_recognition_tween.kill()
	_recognition_tween = create_tween()
	_recognition_tween.set_parallel(true)
	var tiny := Vector3.ONE * 0.02
	for shell in [_outer, _middle, _inner]:
		if shell == null:
			continue
		_recognition_tween.tween_property(shell, "scale", tiny, RECOGNITION_SHRINK_SEC).set_trans(
			Tween.TRANS_QUAD
		).set_ease(Tween.EASE_IN)
	await _recognition_tween.finished
	if not is_instance_valid(self):
		return
	for shell in [_outer, _middle, _inner]:
		if shell != null:
			shell.visible = false
	await _play_spell_recognition_fx(spell)
	if not is_instance_valid(self):
		return
	_recognizing = false
	_hide_recognition()
	_restore_shell_scales()
	for shell in [_outer, _middle, _inner]:
		if shell != null:
			shell.visible = true
	visible = false

func _visual_layers() -> int:
	if Engine.is_editor_hint():
		return WorldVisualLayersScript.SCENE_LIGHT_MASK
	return WorldVisualLayersScript.PLAYER_SELF

func _process(delta: float) -> void:
	if _cast_charging_fx and _cast_charge_fx != null:
		_cast_charge_fx.tick(delta)
	if not _active:
		return
	if _outer != null:
		_outer.rotate_x(deg_to_rad(outer_spin_deg_per_sec.x) * delta)
		_outer.rotate_y(deg_to_rad(outer_spin_deg_per_sec.y) * delta)
		_outer.rotate_z(deg_to_rad(outer_spin_deg_per_sec.z) * delta)
	if _middle != null:
		var mid_spin: Vector3 = (
			middle_spin_deg_per_sec
			if typeof(middle_spin_deg_per_sec) == TYPE_VECTOR3
			else Vector3(28.0, -78.0, 95.0)
		)
		_middle.rotate_x(deg_to_rad(mid_spin.x) * delta)
		_middle.rotate_y(deg_to_rad(mid_spin.y) * delta)
		_middle.rotate_z(deg_to_rad(mid_spin.z) * delta)
	if _inner != null:
		_inner.rotate_x(deg_to_rad(inner_spin_deg_per_sec.x) * delta)
		_inner.rotate_y(deg_to_rad(inner_spin_deg_per_sec.y) * delta)
		_inner.rotate_z(deg_to_rad(inner_spin_deg_per_sec.z) * delta)
		_pulse_phase += delta * pulse_hz * TAU
		var amp := clampf(pulse_amount, 0.0, 1.0)
		var pulse_min := 1.0 - 0.15 * amp
		var pulse_max := 1.0 + 0.2 * amp
		var pulse := remap(sin(_pulse_phase), -1.0, 1.0, pulse_min, pulse_max)
		_inner.scale = _inner_base_scale * pulse

func _queue_apply() -> void:
	if not _ready_done or _apply_queued:
		return
	_apply_queued = true
	call_deferred("_flush_apply")

func _flush_apply() -> void:
	_apply_queued = false
	_apply_all()

func _ensure_nodes() -> void:
	_outer = get_node_or_null("Outer") as MeshInstance3D
	if _outer == null:
		_outer = MeshInstance3D.new()
		_outer.name = "Outer"
		add_child(_outer)
	_middle = get_node_or_null("Middle") as MeshInstance3D
	if _middle == null:
		_middle = MeshInstance3D.new()
		_middle.name = "Middle"
		add_child(_middle)
	_inner = get_node_or_null("Inner") as MeshInstance3D
	if _inner == null:
		_inner = MeshInstance3D.new()
		_inner.name = "Inner"
		add_child(_inner)
	_sparks.clear()
	for spark_name in ["SparksA", "SparksB", "SparksC"]:
		var sparks := get_node_or_null(spark_name) as CPUParticles3D
		if sparks == null:
			sparks = CPUParticles3D.new()
			sparks.name = spark_name
			add_child(sparks)
		_sparks.append(sparks)
	_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_middle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var layers := _visual_layers()
	_outer.layers = layers
	_middle.layers = layers
	_inner.layers = layers
	_ensure_recognition_nodes()

func _ensure_recognition_nodes() -> void:
	_recognition = get_node_or_null("Recognition") as Node3D
	if _recognition == null:
		_recognition = Node3D.new()
		_recognition.name = "Recognition"
		add_child(_recognition)
	_recognition_bubble = _recognition.get_node_or_null("Bubble") as MeshInstance3D
	if _recognition_bubble == null:
		_recognition_bubble = MeshInstance3D.new()
		_recognition_bubble.name = "Bubble"
		_recognition.add_child(_recognition_bubble)
	_recognition_rim = _recognition.get_node_or_null("Rim") as MeshInstance3D
	if _recognition_rim == null:
		_recognition_rim = MeshInstance3D.new()
		_recognition_rim.name = "Rim"
		_recognition.add_child(_recognition_rim)
	_recognition_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_recognition_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var layers := _visual_layers()
	_recognition_bubble.layers = layers
	_recognition_rim.layers = layers
	_recognition.visible = false

func _cache_shell_scales() -> void:
	_shell_base_scales.clear()
	if _outer != null:
		_shell_base_scales[_outer] = _outer.scale
	if _middle != null:
		_shell_base_scales[_middle] = _middle.scale
	if _inner != null:
		_shell_base_scales[_inner] = _inner.scale
		_inner_base_scale = _inner.scale

func _restore_shell_scales() -> void:
	for shell in _shell_base_scales:
		if is_instance_valid(shell):
			shell.scale = _shell_base_scales[shell]
	if _inner != null:
		_inner_base_scale = _shell_base_scales.get(_inner, Vector3.ONE)

func _hide_recognition() -> void:
	if _recognition != null:
		_recognition.visible = false
	if _recognition_bubble != null:
		_recognition_bubble.scale = Vector3.ONE * 0.01
	if _recognition_rim != null:
		_recognition_rim.scale = Vector3.ONE * 0.01

func _play_spell_recognition_fx(spell: SpellDefinition) -> void:
	_ensure_recognition_nodes()
	var effect_id := spell.effect_id if spell != null else ""
	match effect_id:
		"ward":
			await _play_ward_recognition(spell)
		_:
			await _play_generic_recognition(spell)

func _world_to_local_radius(world_radius: float) -> float:
	var gs := global_transform.basis.get_scale()
	var s := maxf(absf(gs.x), 0.001)
	return world_radius / s

func _play_ward_recognition(spell: SpellDefinition = null) -> void:
	var spell_color := (
		spell.get_display_color() if spell != null else WARD_BUBBLE_COLOR
	)
	var radius := _world_to_local_radius(BASEBALL_RADIUS_M)
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 28
	sphere.rings = 14
	_recognition_bubble.mesh = sphere
	_recognition_bubble.material_override = _make_ward_bubble_material(spell_color)
	var rim_mesh := SphereMesh.new()
	rim_mesh.radius = radius * 1.04
	rim_mesh.height = radius * 2.08
	rim_mesh.radial_segments = 28
	rim_mesh.rings = 14
	_recognition_rim.mesh = rim_mesh
	_recognition_rim.material_override = _make_ward_rim_material(spell_color)
	_recognition.visible = true
	_recognition_bubble.scale = Vector3.ONE * 0.02
	_recognition_rim.scale = Vector3.ONE * 0.02
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_recognition_bubble, "scale", Vector3.ONE, RECOGNITION_GROW_SEC).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(_recognition_rim, "scale", Vector3.ONE, RECOGNITION_GROW_SEC).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	await tween.finished
	if not is_instance_valid(self):
		return
	await get_tree().create_timer(RECOGNITION_HOLD_SEC).timeout

func _make_ward_bubble_material(spell_color: Color = WARD_BUBBLE_COLOR) -> StandardMaterial3D:
	var bubble := Color(spell_color.r, spell_color.g, spell_color.b, 0.38)
	var highlight := Color(
		lerpf(spell_color.r, 1.0, 0.75),
		lerpf(spell_color.g, 1.0, 0.75),
		lerpf(spell_color.b, 1.0, 0.75),
		0.55
	)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = bubble
	mat.metallic = 0.2
	mat.roughness = 0.12
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.emission_enabled = true
	mat.emission = highlight
	mat.emission_energy_multiplier = 0.55
	var highlight_noise := FastNoiseLite.new()
	highlight_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	highlight_noise.frequency = 0.09
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.62, 0.82, 1.0])
	ramp.colors = PackedColorArray([
		bubble,
		bubble.lightened(0.08),
		highlight.darkened(0.05),
		highlight,
	])
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.noise = highlight_noise
	tex.color_ramp = ramp
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(1.6, 1.6, 1.6)
	return mat

func _make_ward_rim_material(spell_color: Color = WARD_BUBBLE_EDGE) -> StandardMaterial3D:
	var edge := Color(spell_color.r * 0.55, spell_color.g * 0.65, spell_color.b * 0.85, 0.7)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = edge
	mat.emission_enabled = true
	mat.emission = edge.lightened(0.15)
	mat.emission_energy_multiplier = 0.7
	return mat

func _play_generic_recognition(spell: SpellDefinition) -> void:
	var radius := _world_to_local_radius(BASEBALL_RADIUS_M * 0.85)
	var base := Color(0.75, 0.7, 0.95)
	if spell != null:
		base = spell.get_display_color()
	var color := Color(base.r, base.g, base.b, 0.4)
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	_recognition_bubble.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.lightened(0.2)
	mat.emission_energy_multiplier = 1.2
	_recognition_bubble.material_override = mat
	_recognition_rim.visible = false
	_recognition.visible = true
	_recognition_bubble.scale = Vector3.ONE * 0.02
	var tween := create_tween()
	tween.tween_property(_recognition_bubble, "scale", Vector3.ONE, RECOGNITION_GROW_SEC).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	await tween.finished
	if not is_instance_valid(self):
		return
	await get_tree().create_timer(RECOGNITION_HOLD_SEC * 0.6).timeout
	if _recognition_rim != null:
		_recognition_rim.visible = true

func _apply_all() -> void:
	if _outer == null or _middle == null or _inner == null:
		_ensure_nodes()
	scale = Vector3.ONE * overall_size
	_apply_outer()
	_apply_middle()
	_apply_inner()
	_apply_sparks()
	_inner_base_scale = _inner.scale

func _apply_outer() -> void:
	if _outer == null:
		return
	_apply_cloudy_shell(
		_outer,
		outer_shape,
		_export_float(outer_size, 0.022),
		_export_color(outer_color, Color(0.55, 0.18, 0.78, 1.0)),
		_export_float(outer_transparency, 0.4),
		_export_float(outer_veining, 0.55),
		true
	)

func _apply_middle() -> void:
	if _middle == null:
		return
	_apply_cloudy_shell(
		_middle,
		middle_shape,
		_export_float(middle_size, 0.018),
		_export_color(middle_color, Color(0.72, 0.28, 0.95, 1.0)),
		_export_float(middle_transparency, 0.4),
		_export_float(middle_veining, 0.55),
		false
	)

func _export_float(value: Variant, fallback: float) -> float:
	return fallback if value == null else float(value)

func _export_color(value: Variant, fallback: Color) -> Color:
	return fallback if typeof(value) != TYPE_COLOR else value

func _apply_cloudy_shell(
	mesh_instance: MeshInstance3D,
	shape: ShapeKind,
	size: float,
	color: Color,
	transparency: float,
	veining: float,
	is_outer: bool
) -> void:
	mesh_instance.mesh = _make_shape_mesh(shape, size)
	var noise: FastNoiseLite
	var noise_tex: NoiseTexture2D
	if is_outer:
		if _outer_noise == null:
			_outer_noise = FastNoiseLite.new()
			_outer_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			_outer_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			_outer_noise.fractal_lacunarity = 2.1
			_outer_noise.fractal_gain = 0.5
		if _outer_noise_tex == null:
			_outer_noise_tex = NoiseTexture2D.new()
			_outer_noise_tex.width = 256
			_outer_noise_tex.height = 256
			_outer_noise_tex.seamless = true
		noise = _outer_noise
		noise_tex = _outer_noise_tex
	else:
		if _middle_noise == null:
			_middle_noise = FastNoiseLite.new()
			_middle_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			_middle_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			_middle_noise.fractal_lacunarity = 2.1
			_middle_noise.fractal_gain = 0.5
			_middle_noise.seed = 17
		if _middle_noise_tex == null:
			_middle_noise_tex = NoiseTexture2D.new()
			_middle_noise_tex.width = 256
			_middle_noise_tex.height = 256
			_middle_noise_tex.seamless = true
		noise = _middle_noise
		noise_tex = _middle_noise_tex
	noise.frequency = lerpf(0.035, 0.16, veining)
	noise.fractal_octaves = int(lerpf(2.0, 5.0, veining))
	noise_tex.noise = noise
	noise_tex.color_ramp = _make_shell_alpha_ramp(color, transparency)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.albedo_texture = noise_tex
	mat.emission_enabled = true
	mat.emission = color.lightened(0.08)
	mat.emission_energy_multiplier = 1.4
	mat.uv1_scale = Vector3.ONE * lerpf(1.1, 2.6, veining)
	mesh_instance.material_override = mat

func _make_shell_alpha_ramp(color: Color, transparency: float) -> Gradient:
	var clear_a := clampf(transparency * 0.95, 0.0, 0.95)
	var mid_a := clampf(lerpf(0.75, 0.28, transparency), 0.1, 0.9)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.32, 0.55, 0.78, 1.0])
	ramp.colors = PackedColorArray([
		Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, clear_a * 0.15),
		Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, clear_a),
		Color(color.r * 0.85, color.g * 0.85, color.b * 0.85, mid_a),
		Color(color.r, color.g, color.b, 0.9),
		Color(color.r * 0.75, color.g * 0.75, color.b * 0.75, 1.0),
	])
	return ramp

func _apply_inner() -> void:
	if _inner == null:
		return
	_inner.mesh = _make_shape_mesh(inner_shape, inner_size)
	var amount := _export_float(inner_spot_amount, 0.45)
	var core_color := _export_color(inner_color, Color(0.04, 0.03, 0.06, 1.0))
	var flake_color := _export_color(inner_spot_color, Color(1.0, 0.86, 0.28, 1.0))
	if _inner_noise == null:
		_inner_noise = FastNoiseLite.new()
		_inner_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		_inner_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		_inner_noise.cellular_jitter = 1.0
	_inner_noise.frequency = lerpf(0.22, 0.55, amount)
	if _inner_noise_tex == null:
		_inner_noise_tex = NoiseTexture2D.new()
		_inner_noise_tex.width = 256
		_inner_noise_tex.height = 256
		_inner_noise_tex.seamless = true
	_inner_noise_tex.noise = _inner_noise
	_inner_noise_tex.color_ramp = _make_inner_flake_albedo_ramp(core_color, flake_color, amount)
	var emission_tex := NoiseTexture2D.new()
	emission_tex.width = 256
	emission_tex.height = 256
	emission_tex.seamless = true
	emission_tex.noise = _inner_noise
	emission_tex.color_ramp = _make_inner_flake_emission_ramp(flake_color, amount)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = _inner_noise_tex
	mat.metallic = 0.92
	mat.roughness = 0.28
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = lerpf(1.4, 3.2, amount)
	mat.emission_texture = emission_tex
	mat.uv1_scale = Vector3.ONE * lerpf(2.4, 4.2, amount)
	_inner.material_override = mat
	_inner.scale = Vector3.ONE
	_inner_base_scale = Vector3.ONE

func _make_inner_flake_albedo_ramp(core: Color, flake: Color, amount: float) -> Gradient:
	var flake_start := clampf(lerpf(0.94, 0.82, amount), 0.8, 0.96)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([
		0.0,
		flake_start,
		minf(flake_start + 0.03, 0.99),
		1.0,
	])
	ramp.colors = PackedColorArray([
		core,
		core,
		flake.darkened(0.4),
		flake,
	])
	return ramp

func _make_inner_flake_emission_ramp(flake: Color, amount: float) -> Gradient:
	var flake_start := clampf(lerpf(0.94, 0.82, amount), 0.8, 0.96)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([
		0.0,
		flake_start,
		minf(flake_start + 0.03, 0.99),
		1.0,
	])
	ramp.colors = PackedColorArray([
		Color(0, 0, 0, 1),
		Color(0, 0, 0, 1),
		flake.darkened(0.2),
		flake,
	])
	return ramp

func _ensure_spark_fade() -> void:
	if _spark_fade != null:
		return
	_spark_fade = Gradient.new()
	_spark_fade.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	_spark_fade.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0.65), Color(1, 1, 1, 0),
	])

func _apply_sparks() -> void:
	_ensure_spark_fade()
	var travel := maxf(spark_travel_distance, 0.02)
	var speed := maxf(spark_velocity, 0.2)
	var damp := clampf(speed / travel, 2.0, 18.0)
	var life := clampf(travel / (speed * 0.28), 0.25, 1.6)
	_configure_spark_emitters([spark_color_a, spark_color_b, spark_color_c], {
		"dir": Vector3.UP, "spread": 180.0, "vmin": speed * 0.75, "vmax": speed * 1.25,
		"dmin": damp * 0.75, "dmax": damp * 1.1, "life": life, "rand": 0.7,
		"radius": maxf(outer_size * 0.45, 0.006),
		"aabb": AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3)),
		"on": _active and not _cast_charging_fx, "rate": 1.0,
	})

func _apply_cast_charge_sparks(spell_color: Color) -> void:
	if _sparks.is_empty():
		_ensure_nodes()
	_ensure_spark_fade()
	var spell := Color(spell_color.r, spell_color.g, spell_color.b, 1.0)
	var speed := maxf(spark_velocity, 0.2) * 1.15
	var near := maxf(spark_travel_distance * 0.35, 0.04)
	var far := maxf(spark_travel_distance * 2.4, near * 2.0)
	var dmin := clampf(speed / far, 1.5, 14.0)
	var dmax := clampf(speed / near, dmin * 1.2, 22.0)
	var life := clampf(far / (speed * 0.22), 0.35, 2.0)
	_configure_spark_emitters([Color.WHITE, spell, spell], {
		"dir": Vector3(0, 0, -1), "spread": 32.0, "vmin": speed * 0.3, "vmax": speed * 1.85,
		"dmin": dmin, "dmax": dmax, "life": life, "rand": 1.0,
		"radius": maxf(outer_size * 0.25, 0.004),
		"aabb": AABB(Vector3(-2, -2, -2.5), Vector3(4, 4, 5)),
		"on": true, "rate": 1.15,
	})

func _configure_spark_emitters(colors: Array, cfg: Dictionary) -> void:
	var life: float = float(cfg.get("life", 0.4))
	var n := maxi(_sparks.size(), 1)
	var rate := float(cfg.get("rate", 1.0))
	var total := maxi(6, int(round(sparks_per_second * rate * life)))
	var per := maxi(2, int(round(float(total) / float(n))))
	var quad := QuadMesh.new()
	quad.size = Vector2(spark_size, spark_size)
	var emitting: bool = bool(cfg.get("on", false))
	var fallback_aabb := AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	for i in _sparks.size():
		var sparks := _sparks[i]
		if sparks == null:
			continue
		var col: Color = colors[i] if i < colors.size() else Color.WHITE
		sparks.layers = _visual_layers()
		sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sparks.amount = per
		sparks.lifetime = life
		sparks.randomness = float(cfg.get("rand", 0.7))
		sparks.local_coords = true
		sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sparks.emission_sphere_radius = float(cfg.get("radius", 0.006))
		sparks.direction = cfg.get("dir", Vector3.UP) as Vector3
		sparks.spread = float(cfg.get("spread", 180.0))
		sparks.gravity = Vector3.ZERO
		sparks.initial_velocity_min = float(cfg.get("vmin", 1.0))
		sparks.initial_velocity_max = float(cfg.get("vmax", 2.0))
		sparks.damping_min = float(cfg.get("dmin", 4.0))
		sparks.damping_max = float(cfg.get("dmax", 8.0))
		sparks.scale_amount_min = 0.7
		sparks.scale_amount_max = 1.35
		sparks.color = col
		sparks.color_ramp = _spark_fade
		sparks.mesh = quad
		sparks.visibility_aabb = cfg.get("aabb", fallback_aabb) as AABB
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.vertex_color_use_as_albedo = true
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.emission_enabled = true
		mat.emission = col.lightened(0.25)
		mat.emission_energy_multiplier = 4.0
		sparks.material_override = mat
		sparks.emitting = emitting
		if emitting:
			sparks.restart()

func _make_shape_mesh(kind: ShapeKind, size: float) -> Mesh:
	if kind == ShapeKind.BOX:
		var box := BoxMesh.new()
		box.size = Vector3.ONE * (size * 2.0)
		return box
	if kind == ShapeKind.PRISM:
		var prism := PrismMesh.new()
		prism.size = Vector3.ONE * (size * 2.0)
		return prism
	if kind == ShapeKind.CAPSULE:
		var capsule := CapsuleMesh.new()
		capsule.radius = size * 0.7
		capsule.height = size * 2.4
		return capsule
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	return sphere
