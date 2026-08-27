@tool
class_name WardShield
extends Node3D

## HP wards absorb spell damage. Low HP tints the dome red; empty HP GPU-shatters.
## Open scenes/spells/ward/ward.tscn — Ward root: linger, hold distance, beam width, dome shape.
## Select child Beam only for force-field shader knobs (rim, veins, scroll).

const WardMeshBuilderScript := preload("res://scripts/spells/ward_mesh_builder.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const ForceFieldScript := preload("res://scripts/fx/force_field.gd")
const WardBurstScript := preload("res://scripts/spells/ward_burst.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")

const GROUP := "spell_ward"
const DURATION_SEC := 8.0
const DEFAULT_BLOCK_HP := 40.0
const DEFAULT_REGEN_DELAY_SEC := 1.0
const DEFAULT_REGEN_PER_SEC := 10.0
## Kept for tests / callers that expect a class-level default size.
const RADIUS := 1.35
## Beam must read as immediate once the voice match resolves.
const CAST_TRAVEL_SEC := 0.05
const FORM_SEC := 0.08
## Camera-forward distance of the dome while the slot is held.
const HOLD_FORWARD := 1.55
const DEFAULT_BEAM_DIAMETER := 0.05
## Keep-in wall shader, but thinner so the dome stays mostly see-through.
const FIELD_BASE_ALPHA := 0.02
const FIELD_RIM_STRENGTH := 0.42
const FIELD_ENERGY := 0.48
const DOME_PATTERN_SCALE := 1.45
const SHIELD_BLUE := Color(0.35, 0.65, 1.0, 0.38)
const SHIELD_EDGE := Color(0.55, 0.85, 1.0, 0.72)
const SHIELD_STRESS := Color(0.92, 0.12, 0.08, 0.42)
const SHIELD_STRESS_EDGE := Color(1.0, 0.25, 0.1, 1.0)

@export_group("Dome shape")
@export_range(0.25, 4.0, 0.05, "or_greater") var radius: float = RADIUS:
	set(value):
		var next := maxf(value, 0.05)
		if is_equal_approx(radius, next):
			return
		radius = next
		_rebuild_geometry()

@export_range(0.1, 0.9, 0.01) var surface_fraction: float = 0.333:
	set(value):
		var next := clampf(value, 0.05, 0.95)
		if is_equal_approx(surface_fraction, next):
			return
		surface_fraction = next
		_rebuild_geometry()

@export_range(2, 32, 1) var ring_count: int = 10:
	set(value):
		var next := maxi(value, 2)
		if ring_count == next:
			return
		ring_count = next
		_rebuild_geometry()

@export_range(3, 64, 1) var segment_count: int = 28:
	set(value):
		var next := maxi(value, 3)
		if segment_count == next:
			return
		segment_count = next
		_rebuild_geometry()

@export_group("Lifetime")
## Seconds the planted dome stays up after you release the slot.
@export_range(0.15, 8.0, 0.05, "or_greater", "suffix:s") var duration_sec: float = DURATION_SEC:
	set(value):
		duration_sec = maxf(value, 0.05)

@export_group("Block")
## Incoming spell damage absorbed before shatter.
@export_range(1.0, 400.0, 1.0) var block_hp: float = DEFAULT_BLOCK_HP:
	set(value):
		block_hp = maxf(value, 1.0)

@export_group("Regen")
## Seconds after the most recent cast before HP starts restoring.
@export_range(0.0, 10.0, 0.05, "suffix:s") var regen_delay_sec: float = DEFAULT_REGEN_DELAY_SEC
## HP restored per second after the timeout, up to block_hp.
@export_range(0.0, 50.0, 0.5) var regen_per_sec: float = DEFAULT_REGEN_PER_SEC

@export_group("Hold pose")
## Camera-forward meters from the view to the dome while the slot is held.
## Beam runs wand tip → dome, so this also sets beam length.
@export_range(0.4, 4.0, 0.05, "or_greater", "suffix:m") var hold_forward: float = HOLD_FORWARD:
	set(value):
		var next := maxf(value, 0.2)
		if is_equal_approx(hold_forward, next):
			return
		hold_forward = next
		if _follow_attached:
			position = Vector3(0.0, 0.0, -hold_forward)
		_sync_lookdev_beam()

## Mean visual width of the wand cylinder. Mesh taper is kept.
@export_range(0.01, 0.2, 0.005, "suffix:m") var beam_diameter: float = DEFAULT_BEAM_DIAMETER:
	set(value):
		var next := maxf(value, 0.005)
		if is_equal_approx(beam_diameter, next):
			return
		beam_diameter = next
		_sync_lookdev_beam()

var _body: StaticBody3D
var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D
var _material: ShaderMaterial
var _hits_remaining := 1
var _max_hp := 0.0
var _hp := 0.0
var _lifetime := 0.0
var _lifetime_active := false
var _wand_origin := Vector3.ZERO
var _body_collision_layer := 1
var _beam_fx: ForceField
var _beam_mean_radius := DEFAULT_BEAM_DIAMETER * 0.5
var _rim: MeshInstance3D
var _rim_mat: StandardMaterial3D
var _cast_tween: Tween
var _block_listener: Callable = Callable()
var _persist_through_blocks := false
var _caster: Node3D = null
var _held := false
var _following := false
var _follow_attached := false
var _follow_home: Node = null
var _dissolving := false
var _time_since_cast := 0.0
var _regen_wait_sec := DEFAULT_REGEN_DELAY_SEC
var _runtime: Resource = null


func set_block_listener(listener: Callable) -> void:
	_block_listener = listener


func set_persist_through_blocks(enabled: bool) -> void:
	_persist_through_blocks = enabled


func set_caster(caster: Node3D) -> void:
	_caster = caster
	_apply_caster_collision_exception()


func is_owned_by(node: Variant = null) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return _caster != null and is_instance_valid(_caster) and node == _caster


func _apply_caster_collision_exception() -> void:
	if _body == null or not is_instance_valid(_caster):
		return
	if _caster is CollisionObject3D:
		_body.add_collision_exception_with(_caster as CollisionObject3D)


static func spawn(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	hit_capacity: int = 1,
	linger_sec: float = -1.0
) -> Node:
	## Lazy-load avoids circular preload with ward.tscn (which attaches this script).
	var packed: PackedScene = load(SpellDefinition.world_scene_path("ward")) as PackedScene
	var ward: Node = packed.instantiate()
	if parent != null and ward is Node3D:
		SpellEphemeralFxScript.add_child_at(parent, ward as Node3D, origin)
	elif parent != null:
		parent.add_child(ward)
	if linger_sec > 0.0 and ward.has_method("set_duration_sec"):
		ward.call("set_duration_sec", linger_sec)
	if ward.has_method("setup_cast"):
		ward.call("setup_cast", origin, direction, hit_capacity)
	if ward is Node3D:
		if NetClockScript.is_ticking():
			NetLivenessScript.after_spawn(ward as Node3D)
		else:
			NetLivenessScript.attach(ward)
	return ward


func set_duration_sec(seconds: float) -> void:
	duration_sec = seconds


func hold_until_broken() -> void:
	## Keep the shield up until shatter() — used by the Charger ram.
	_held = true
	_lifetime_active = false


func set_hit_points(hp: float) -> void:
	_max_hp = maxf(hp, 0.01)
	_hp = _max_hp
	_time_since_cast = 0.0
	_sync_runtime()
	_apply_integrity_color()


func bind_runtime(runtime: Resource) -> void:
	_runtime = runtime
	if runtime == null:
		return
	runtime.regen_per_sec = regen_per_sec
	if runtime.has_method("apply_shatter_regen_delay"):
		_regen_wait_sec = float(runtime.call("apply_shatter_regen_delay", regen_delay_sec))
	else:
		_regen_wait_sec = regen_delay_sec
		runtime.regen_delay_sec = regen_delay_sec
	runtime.reset_hp()
	block_hp = maxf(float(runtime.get("max_hp")), 1.0)
	_max_hp = block_hp
	_hp = float(runtime.get("hp"))
	_time_since_cast = float(runtime.get("time_since_cast"))
	_apply_integrity_color()


func shatter() -> void:
	_held = false
	_dissolve(false)


func _ready() -> void:
	_regen_wait_sec = regen_delay_sec
	_cache_nodes()
	if not _has_baked_geometry():
		_rebuild_geometry()
	add_to_group(GROUP)
	if _body != null:
		_body.add_to_group(GROUP)
		_body_collision_layer = _body.collision_layer
	if Engine.is_editor_hint() and not _lifetime_active:
		## Look-dev instance: stay static until setup_cast runs (workspace preview).
		set_process(false)
		_sync_lookdev_beam()
		return
	_ensure_runtime_material()


func _cache_nodes() -> void:
	_mesh_instance = get_node_or_null("Dome") as MeshInstance3D
	_body = get_node_or_null("Body") as StaticBody3D
	if _body != null:
		_collision_shape = _body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_beam_fx = get_node_or_null("Beam") as ForceField
	if _beam_fx != null:
		_beam_fx.process_mode = Node.PROCESS_MODE_ALWAYS
		if not Engine.is_editor_hint():
			## Scene pose is look-dev (along the dome). Game poses world-space.
			_beam_fx.visible = false
		_ensure_beam_cylinder()
		_cache_beam_mean_radius()


func _ensure_beam_cylinder() -> void:
	if _beam_fx == null:
		return
	var mesh_inst := _beam_fx.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_inst == null:
		return
	if mesh_inst.mesh is CylinderMesh:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.032
	cyl.height = 1.0
	cyl.radial_segments = 16
	mesh_inst.mesh = cyl
	mesh_inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_beam_fx.scale = Vector3.ONE


func _cache_beam_mean_radius() -> void:
	_beam_mean_radius = DEFAULT_BEAM_DIAMETER * 0.5
	if _beam_fx == null:
		return
	var mesh := _beam_fx.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var cyl := mesh.mesh as CylinderMesh
	if cyl == null:
		return
	_beam_mean_radius = (cyl.top_radius + cyl.bottom_radius) * 0.5


func _beam_xy_scale() -> float:
	return (beam_diameter * 0.5) / maxf(_beam_mean_radius, 0.001)


func _sync_lookdev_beam() -> void:
	if not Engine.is_editor_hint() or _following:
		return
	if not is_inside_tree():
		return
	if _beam_fx == null:
		_beam_fx = get_node_or_null("Beam") as ForceField
	if _beam_fx == null:
		return
	_ensure_beam_cylinder()
	_cache_beam_mean_radius()
	_beam_fx.visible = true
	_beam_fx.top_level = false
	var to := _beam_end_local()
	var length := maxf(absf(to.z), 0.04)
	var xy := _beam_xy_scale()
	_beam_fx.position = Vector3(0.0, 0.0, to.z * 0.5)
	_beam_fx.rotation = Vector3.ZERO
	_beam_fx.scale = Vector3(xy, xy, length)


func _has_baked_geometry() -> bool:
	if _mesh_instance == null or _collision_shape == null:
		_cache_nodes()
	if _mesh_instance == null or _mesh_instance.mesh == null:
		return false
	return _collision_shape != null and _collision_shape.shape != null


func _rebuild_geometry() -> void:
	if not is_inside_tree() and not Engine.is_editor_hint():
		return
	if _mesh_instance == null or _collision_shape == null:
		_cache_nodes()
	if _mesh_instance == null:
		return
	_mesh_instance.mesh = WardMeshBuilderScript.build_mesh(
		radius, surface_fraction, ring_count, segment_count
	)
	if _collision_shape != null:
		_collision_shape.shape = WardMeshBuilderScript.build_collision_shape(
			radius, surface_fraction, ring_count, segment_count
		)


func setup_cast(origin: Vector3, direction: Vector3, hit_capacity: int = 1) -> void:
	_place_from_aim(origin, direction)
	_lifetime = 0.0
	_hits_remaining = maxi(hit_capacity, 1)
	if _max_hp <= 0.0:
		set_hit_points(block_hp)
	_time_since_cast = 0.0
	_lifetime_active = false
	## Editor look-dev trees are often paused; keep cast FX + lifetime ticking.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_ensure_runtime_material()
	_prepare_for_cast_fx()
	_play_cast_sequence()


func start_wand_follow(
	origin: Vector3,
	direction: Vector3,
	hit_capacity: int = 1,
	attach_to: Node3D = null
) -> void:
	## Instant channel: dome rides the hold host; cylinder runs wand-tip → dome.
	_lifetime = 0.0
	_wand_origin = origin
	_hits_remaining = maxi(hit_capacity, 1)
	if _max_hp <= 0.0:
		set_hit_points(block_hp)
	_time_since_cast = 0.0
	_lifetime_active = false
	_following = true
	_held = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_ensure_runtime_material()
	_prepare_for_cast_fx()
	_kill_cast_tween()
	_clear_cast_fx()
	if attach_to != null:
		_attach_to_follow_host(attach_to)
	else:
		_follow_attached = false
		_place_from_camera_aim(origin, direction)
	_build_beam()
	_snap_formed(false)
	_orient_channel_beam(_wand_tip())
	_enable_collision()


func follow_wand(origin: Vector3, direction: Vector3, wand_tip: Vector3 = Vector3.INF) -> void:
	if not _following or _is_broken():
		return
	if not _follow_attached:
		_place_from_camera_aim(origin, direction)
	var tip := _wand_tip()
	if not is_inf(wand_tip.x):
		tip = wand_tip
	_orient_channel_beam(tip)


func plant() -> void:
	if not _following:
		return
	_following = false
	_held = false
	_follow_attached = false
	_detach_follow_host()
	_lifetime = 0.0
	_lifetime_active = true
	set_process(true)
	_enable_collision()
	_fade_channel_beam()


func is_channel_following() -> bool:
	return _following


func _place_from_aim(origin: Vector3, direction: Vector3) -> void:
	var dir := _aim_dir(direction)
	_wand_origin = origin
	var pos := origin + dir * (radius * 0.2)
	global_transform = Transform3D(_aim_basis(dir), pos)


func _place_from_camera_aim(origin: Vector3, direction: Vector3) -> void:
	var dir := _aim_dir(direction)
	_wand_origin = origin
	global_transform = Transform3D(_aim_basis(dir), origin + dir * hold_forward)


func _aim_dir(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return direction.normalized()


func _aim_basis(dir: Vector3) -> Basis:
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.RIGHT
	return Basis.looking_at(dir, up)


func _attach_to_follow_host(host: Node3D) -> void:
	if host == null:
		_follow_attached = false
		return
	_follow_home = get_parent()
	if get_parent() != host:
		var xf := global_transform
		if get_parent() != null:
			get_parent().remove_child(self)
		host.add_child(self)
		global_transform = xf
	_follow_attached = true
	position = Vector3(0.0, 0.0, -hold_forward)
	rotation = Vector3.ZERO


func _detach_follow_host() -> void:
	var home := _follow_home
	if home == null or not is_instance_valid(home):
		if _caster != null and is_instance_valid(_caster):
			home = SpellEphemeralFxScript.resolve_parent(_caster)
	_follow_home = null
	_follow_attached = false
	if home == null or get_parent() == home:
		return
	var xf := global_transform
	get_parent().remove_child(self)
	home.add_child(self)
	global_transform = xf


func _beam_end_local() -> Vector3:
	## Inner pole of the cap. Pull back so the cylinder does not pierce the mesh.
	var inset := maxf(beam_diameter * 0.35, 0.02)
	return Vector3(0.0, 0.0, -maxf(radius - inset, 0.05))


func _dome_center() -> Vector3:
	return global_transform * _beam_end_local()


func _wand_tip() -> Vector3:
	if _caster != null and is_instance_valid(_caster):
		if _caster.has_method("get_wand_cast_origin"):
			return _caster.call("get_wand_cast_origin") as Vector3
		if _caster.has_method("get_cast_origin"):
			return _caster.call("get_cast_origin") as Vector3
	return _wand_origin


func setup_sphere_cast(origin: Vector3, hit_capacity: int, sphere_radius: float) -> void:
	radius = maxf(sphere_radius, 0.05)
	surface_fraction = 0.95
	_rebuild_geometry()
	_wand_origin = origin
	global_transform = Transform3D(Basis.IDENTITY, origin)
	_lifetime = 0.0
	_hits_remaining = maxi(hit_capacity, 1)
	if _max_hp <= 0.0:
		set_hit_points(block_hp)
	_time_since_cast = 0.0
	_lifetime_active = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_ensure_runtime_material()
	_prepare_for_cast_fx()
	_play_cast_sequence()


func _make_cast_tween() -> Tween:
	var tween := create_tween()
	## Bound tweens freeze while the editor scene tree is paused.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


func _ensure_runtime_material() -> void:
	if _mesh_instance == null:
		_cache_nodes()
	if _mesh_instance == null:
		return
	if _material != null:
		return
	_material = _make_field_material(DOME_PATTERN_SCALE, FIELD_ENERGY, 0.9)
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_integrity_color()


func _make_field_material(
	pattern_scale: float, energy_amount: float, proximity: float
) -> ShaderMaterial:
	var mat := ForceFieldScript.make_material()
	mat.set_shader_parameter("rim_color", SHIELD_EDGE)
	mat.set_shader_parameter("energy_color", Color(0.95, 0.98, 1.0, 1.0))
	mat.set_shader_parameter("base_alpha", FIELD_BASE_ALPHA)
	mat.set_shader_parameter("rim_strength", FIELD_RIM_STRENGTH)
	mat.set_shader_parameter("energy_amount", energy_amount)
	mat.set_shader_parameter("pattern_scale", pattern_scale)
	mat.set_shader_parameter("proximity_fade", proximity)
	mat.set_shader_parameter("opacity", 1.0)
	return mat


func _set_field_opacity(mat: ShaderMaterial, amount: float) -> void:
	if mat != null:
		mat.set_shader_parameter("opacity", clampf(amount, 0.0, 1.0))


func _set_beam_fade(amount: float) -> void:
	if _beam_fx != null:
		_beam_fx.opacity = clampf(amount, 0.0, 1.0)


func _set_dome_fade(amount: float) -> void:
	_set_field_opacity(_material, amount)


func _prepare_for_cast_fx() -> void:
	if _body != null:
		_body_collision_layer = maxi(_body.collision_layer, 1)
		_body.collision_layer = 0
	if _mesh_instance != null:
		_mesh_instance.visible = true
		_mesh_instance.scale = Vector3.ONE * 0.05
	_set_field_opacity(_material, 0.0)


func _play_cast_sequence() -> void:
	_kill_cast_tween()
	_clear_cast_fx()
	_build_beam()
	## Collision goes live with the cast — beam is FX only; ward must protect on detect.
	_enable_collision()
	var skip_travel := _wand_origin.distance_squared_to(global_position) < 0.01
	_cast_tween = _make_cast_tween()
	if skip_travel:
		_set_beam_progress(1.0)
		_cast_tween.tween_callback(_form_shield)
		return
	_set_beam_progress(0.0)
	_cast_tween.tween_method(
		_set_beam_progress,
		0.0,
		1.0,
		CAST_TRAVEL_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cast_tween.tween_callback(_form_shield)


func _build_beam() -> void:
	if _beam_fx == null:
		_cache_nodes()
	if _beam_fx == null:
		return
	_beam_fx.opacity = 1.0
	_beam_fx.visible = true
	_beam_fx.top_level = true
	_beam_fx.process_mode = Node.PROCESS_MODE_ALWAYS


func _set_beam_progress(t: float) -> void:
	var pos := _wand_origin.lerp(global_position, clampf(t, 0.0, 1.0))
	_orient_beam(_wand_origin, pos)
	_set_beam_fade(lerpf(0.9, 0.2, t))


func _orient_channel_beam(wand_tip: Vector3) -> void:
	_wand_origin = wand_tip
	_orient_beam(wand_tip, _dome_center())


func _orient_beam(from_pos: Vector3, to_pos: Vector3) -> void:
	if _beam_fx == null or not is_instance_valid(_beam_fx):
		return
	var length := maxf(from_pos.distance_to(to_pos), 0.04)
	var to := to_pos
	if from_pos.distance_squared_to(to_pos) < 0.0001:
		to = from_pos + Vector3(0.0, 0.0, -length)
	var up := Vector3.UP
	var dir := (to - from_pos).normalized()
	if absf(dir.dot(up)) > 0.92:
		up = Vector3.RIGHT
	_beam_fx.global_position = from_pos.lerp(to, 0.5)
	## Mesh is baked along local -Z (look_at forward). Stretch Z, not Y.
	_beam_fx.look_at(to, up)
	var xy := _beam_xy_scale()
	_beam_fx.scale = Vector3(xy, xy, length)


func _form_shield() -> void:
	_clear_cast_fx()
	_spawn_rim_bloom()
	_enable_collision()
	_lifetime = 0.0
	_lifetime_active = not _held
	set_process(true)
	if _mesh_instance != null:
		_mesh_instance.visible = true
		_mesh_instance.scale = Vector3.ONE * 0.2
	_cast_tween = _make_cast_tween()
	_cast_tween.set_parallel(true)
	if _mesh_instance != null:
		_cast_tween.tween_property(_mesh_instance, "scale", Vector3.ONE, FORM_SEC).set_trans(
			Tween.TRANS_QUAD
		).set_ease(Tween.EASE_OUT)
	if _material != null:
		_cast_tween.tween_method(_set_form_material, 0.0, 1.0, FORM_SEC).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_OUT)
	if _rim != null and is_instance_valid(_rim):
		_cast_tween.tween_property(_rim, "scale", Vector3.ONE * 1.08, FORM_SEC).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_OUT)
		if _rim_mat != null:
			_cast_tween.tween_property(_rim_mat, "albedo_color:a", 0.0, FORM_SEC)
			_cast_tween.tween_property(_rim_mat, "emission_energy_multiplier", 0.2, FORM_SEC)
	_cast_tween.chain().tween_callback(_finish_form)


func _set_form_material(t: float) -> void:
	_set_field_opacity(_material, clampf(t, 0.0, 1.0))


func _spawn_rim_bloom() -> void:
	if _mesh_instance == null or _mesh_instance.mesh == null:
		return
	_rim = MeshInstance3D.new()
	_rim.name = "RimBloom"
	_rim.mesh = _mesh_instance.mesh
	_rim.scale = Vector3.ONE * 0.08
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim_mat.albedo_color = Color(0.65, 0.9, 1.0, 0.55)
	_rim_mat.emission_enabled = true
	_rim_mat.emission = Color(0.7, 0.95, 1.0)
	_rim_mat.emission_energy_multiplier = 3.2
	_rim.material_override = _rim_mat
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim.layers = WorldVisualLayersScript.WORLD
	add_child(_rim)


func _snap_formed(enable_collision: bool = true) -> void:
	if enable_collision:
		_enable_collision()
	if _mesh_instance != null:
		_mesh_instance.visible = true
		_mesh_instance.scale = Vector3.ONE
	_set_field_opacity(_material, 1.0)
	_apply_integrity_color()


func _fade_channel_beam() -> void:
	if _beam_fx == null or not is_instance_valid(_beam_fx):
		_clear_cast_fx()
		return
	_kill_cast_tween()
	_cast_tween = _make_cast_tween()
	_cast_tween.tween_method(_set_beam_fade, 1.0, 0.0, 0.18)
	_cast_tween.tween_callback(_clear_cast_fx)


func _finish_form() -> void:
	if _rim != null and is_instance_valid(_rim):
		_free_node(_rim)
		_rim = null
	_rim_mat = null
	if _mesh_instance != null:
		_mesh_instance.scale = Vector3.ONE
	_set_field_opacity(_material, 1.0)
	_apply_integrity_color()
	_enable_collision()


func _enable_collision() -> void:
	if _body != null:
		_body.collision_layer = _body_collision_layer
		_apply_caster_collision_exception()


func _process(delta: float) -> void:
	_tick_regen(delta)
	if _following:
		_orient_channel_beam(_wand_tip())
		return
	if _held or not _lifetime_active or _is_broken():
		return
	_lifetime += delta
	var duration := maxf(duration_sec, 0.05)
	if _material != null:
		var fade := clampf(1.0 - (_lifetime / duration), 0.0, 1.0)
		_set_field_opacity(_material, fade)
	if _lifetime >= duration and not _is_broken():
		_dissolve(false)


func _tick_regen(delta: float) -> void:
	if _dissolving or _is_broken() or _max_hp <= 0.0:
		return
	_time_since_cast += delta
	_sync_runtime()
	if regen_per_sec <= 0.0 or _time_since_cast < _regen_wait_sec:
		return
	if _hp >= _max_hp:
		return
	_hp = minf(_max_hp, _hp + regen_per_sec * delta)
	_sync_runtime()
	_apply_integrity_color()


func notify_spell_blocked(damage: float = 0.0, incoming_from: Variant = null) -> void:
	if _is_broken():
		return
	if incoming_from != null and not is_instance_valid(incoming_from):
		incoming_from = null
	if _max_hp > 0.0:
		if damage > 0.0:
			_hp -= damage
			_sync_runtime()
			_apply_integrity_color()
		if _hp <= 0.0:
			_dissolve(true)
			return
		if _block_listener.is_valid():
			_block_listener.call(damage)
		_notify_owner_blocked(incoming_from as Node)
		return
	if not _persist_through_blocks and _hits_remaining <= 0:
		return
	if _block_listener.is_valid():
		_block_listener.call(damage)
	_notify_owner_blocked(incoming_from as Node)
	if _persist_through_blocks:
		return
	_hits_remaining -= 1
	if _hits_remaining <= 0:
		_dissolve(true)


func _notify_owner_blocked(incoming_from: Node) -> void:
	if is_instance_valid(_caster) and _caster is Character:
		(_caster as Character).on_own_ward_blocked(incoming_from)


func _is_broken() -> bool:
	if _max_hp > 0.0:
		return _hp <= 0.0
	return _hits_remaining <= 0


func integrity_ratio() -> float:
	if _max_hp <= 0.001:
		return 1.0
	return clampf(_hp / _max_hp, 0.0, 1.0)


static func integrity_tint(integrity: float) -> Color:
	var t := 1.0 - clampf(integrity, 0.0, 1.0)
	return SHIELD_BLUE.lerp(SHIELD_STRESS, t)


static func integrity_edge(integrity: float) -> Color:
	var t := 1.0 - clampf(integrity, 0.0, 1.0)
	return SHIELD_EDGE.lerp(SHIELD_STRESS_EDGE, t)


func _sync_runtime() -> void:
	if _runtime == null:
		return
	_runtime.hp = _hp
	_runtime.time_since_cast = _time_since_cast


func _apply_integrity_color() -> void:
	if _material == null or _max_hp <= 0.0:
		return
	var integrity := integrity_ratio()
	var fill := integrity_tint(integrity)
	_material.set_shader_parameter("rim_color", fill)
	_material.set_shader_parameter("energy_color", integrity_edge(integrity))
	_material.set_shader_parameter(
		"energy_amount", lerpf(FIELD_ENERGY, FIELD_ENERGY * 0.22, 1.0 - integrity)
	)


func _dissolve(from_shatter: bool = false) -> void:
	if _dissolving:
		return
	_dissolving = true
	_hits_remaining = 0
	_hp = 0.0
	_sync_runtime()
	_lifetime_active = false
	set_process(false)
	_kill_cast_tween()
	_clear_cast_fx()
	if from_shatter:
		_notify_owner_shattered()
		_spawn_shatter_burst()
	if _rim != null and is_instance_valid(_rim):
		_free_node(_rim)
		_rim = null
	if _body != null:
		_body.collision_layer = 0
	var tween := _make_cast_tween()
	if _material != null:
		tween.tween_method(_set_dome_fade, 1.0, 0.0, 0.12)
	tween.tween_callback(_free_self)


func _notify_owner_shattered() -> void:
	if _caster == null or not is_instance_valid(_caster):
		return
	var loadout: Node = null
	if _caster.has_method("get_spell_loadout"):
		loadout = _caster.call("get_spell_loadout") as Node
	if loadout != null and loadout.has_method("arm_ward_shatter_penalty"):
		loadout.call("arm_ward_shatter_penalty")
	elif _runtime != null:
		_runtime.shatter_regen_scale = 2.0


func _spawn_shatter_burst() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent == null:
		return
	var burst := WardBurstScript.new()
	parent.add_child(burst)
	burst.global_transform = global_transform
	if burst.has_method("setup"):
		burst.call("setup", radius, SHIELD_EDGE)


func _kill_cast_tween() -> void:
	if _cast_tween != null and _cast_tween.is_valid():
		_cast_tween.kill()
	_cast_tween = null


func _clear_cast_fx() -> void:
	if _beam_fx != null and is_instance_valid(_beam_fx):
		_beam_fx.visible = false
		_beam_fx.opacity = 1.0


func _free_node(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _free_self() -> void:
	queue_free()


func _exit_tree() -> void:
	_kill_cast_tween()
	_clear_cast_fx()
