@tool
class_name FireballProjectile
extends Area3D

## Forward-moving fireball that explodes on impact. Payload is [Damage] only.
## Open scenes/spells/fireball/fireball.tscn to tune look + preview FX.

const SPEED := 28.0
const DEFAULT_HIT_DAMAGE := 20.0
const DEFAULT_CHARGE_TIME_SEC := 0.8
const DEFAULT_WAND_CHARGE_POSE_SEC := 0.14
## Min charge combat values; max uses authored hit_damage / splash / radii.
const CHARGE_DAMAGE_MIN := 5.0
const CHARGE_AOE_MIN_RADIUS := 0.037
const CHARGE_SPEED_MIN_MULT := 0.75
const CHARGE_SPEED_MAX_MULT := 1.5625

const FireballExplosionEffectScript := preload("res://scripts/spells/fireball_explosion_effect.gd")
const FireballSmokeTrailScript := preload("res://scripts/spells/fireball_smoke_trail.gd")
const FireballParticlesScript := preload("res://scripts/spells/fireball_particles.gd")
const FireballLightingScript := preload("res://scripts/spells/fireball_lighting.gd")
const FireballFlightScript := preload("res://scripts/spells/fireball_flight.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")
const NetDisplayCommitScript := preload("res://scripts/net/net_display_commit.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")

@export_group("Cast timing")
## Hold time until the tip orb is ready to launch. Drives charge animation too.
@export_range(0.05, 5.0, 0.05) var charge_time_sec: float = DEFAULT_CHARGE_TIME_SEC:
	set(value):
		charge_time_sec = maxf(value, 0.05)
## Wand lift into the charge pose. Independent of charge_time_sec.
@export_range(0.02, 1.0, 0.01) var wand_charge_pose_sec: float = DEFAULT_WAND_CHARGE_POSE_SEC:
	set(value):
		wand_charge_pose_sec = maxf(value, 0.02)

@export_group("Radii")
@export_range(0.05, 1.5, 0.01, "or_greater") var core_radius: float = 0.22:
	set(value):
		core_radius = maxf(value, 0.02)
		_sync_orb_shape()

@export_range(0.04, 1.2, 0.01, "or_greater") var hit_radius: float = 0.16:
	set(value):
		hit_radius = maxf(value, 0.02)
		_sync_orb_shape()

@export_range(0.05, 2.0, 0.01, "or_greater") var shell_radius: float = 0.3:
	set(value):
		shell_radius = maxf(value, 0.02)
		_sync_orb_shape()

@export_range(0.02, 1.0, 0.01) var smoke_emission_radius: float = 0.14:
	set(value):
		smoke_emission_radius = maxf(value, 0.01)
		_configure_smoke_trail()

@export_range(0.05, 1.2, 0.01) var smoke_puff_radius: float = 0.14:
	set(value):
		smoke_puff_radius = maxf(value, 0.02)
		_configure_smoke_trail()

@export_range(0.02, 1.0, 0.01) var ember_emission_radius: float = 0.08:
	set(value):
		ember_emission_radius = maxf(value, 0.01)
		_configure_ember_sparks()

@export_range(0.005, 0.2, 0.001) var ember_puff_radius: float = 0.02:
	set(value):
		ember_puff_radius = maxf(value, 0.002)
		_configure_ember_sparks()

@export_range(0.5, 16.0, 0.1) var light_radius: float = 4.8:
	set(value):
		light_radius = maxf(value, 0.1)
		_configure_travel_light()

@export_group("Combat")
@export_range(0.0, 200.0, 1.0) var hit_damage: float = DEFAULT_HIT_DAMAGE
## Damage radius on ground / monster / player impact (not midair timeout).
@export_range(0.25, 8.0, 0.05) var splash_radius: float = 2.0
@export var payload: CombatPayload

@export_group("Editor preview")
@export var preview_smoke: bool = true:
	set(value):
		preview_smoke = value
		_apply_preview_fx()

@export var preview_embers: bool = true:
	set(value):
		preview_embers = value
		_apply_preview_fx()

@export var preview_glow: bool = true:
	set(value):
		preview_glow = value
		_apply_preview_fx()

@export_group("Fire animation")
@export var animate_fire_texture: bool = true:
	set(value):
		animate_fire_texture = value
		_update_process_state()

@export_range(0.0, 2.5, 0.01) var fire_scroll_x: float = 0.35:
	set(value):
		fire_scroll_x = maxf(value, 0.0)

@export_range(0.0, 2.5, 0.01) var fire_scroll_y: float = 0.55:
	set(value):
		fire_scroll_y = maxf(value, 0.0)

@export_range(0.5, 8.0, 0.05) var fire_emission_base: float = 2.2:
	set(value):
		fire_emission_base = maxf(value, 0.1)
		_restart_glow_pulse()

@export_range(0.5, 10.0, 0.05) var fire_emission_peak: float = 3.2:
	set(value):
		fire_emission_peak = maxf(value, 0.1)
		_restart_glow_pulse()

@export_group("Glow pulse")
@export var animate_glow: bool = true:
	set(value):
		animate_glow = value
		_apply_preview_fx()

@export_range(0.1, 2.0, 0.01) var glow_half_period_sec: float = 0.42:
	set(value):
		glow_half_period_sec = maxf(value, 0.05)
		_restart_glow_pulse()

@export_range(0.2, 6.0, 0.05) var glow_light_base: float = 1.05:
	set(value):
		glow_light_base = maxf(value, 0.0)
		_restart_glow_pulse()

@export_range(0.2, 8.0, 0.05) var glow_light_peak: float = 1.75:
	set(value):
		glow_light_peak = maxf(value, 0.0)
		_restart_glow_pulse()

@export_group("Flame shell")
@export var shell_visible: bool = true:
	set(value):
		shell_visible = value
		_sync_shell_visibility()

@export var animate_shell: bool = true:
	set(value):
		animate_shell = value
		_update_process_state()

@export_range(0.0, 1.0, 0.01) var shell_alpha_min: float = 0.12:
	set(value):
		shell_alpha_min = clampf(value, 0.0, 1.0)

@export_range(0.0, 1.0, 0.01) var shell_alpha_max: float = 0.32:
	set(value):
		shell_alpha_max = clampf(value, 0.0, 1.0)

@export_range(0.2, 8.0, 0.05) var shell_pulse_hz: float = 1.3:
	set(value):
		shell_pulse_hz = maxf(value, 0.05)

@export_group("Smoke")
@export_range(8, 200, 1) var smoke_amount: int = 48:
	set(value):
		smoke_amount = clampi(value, 8, 200)
		_configure_smoke_trail()

@export_range(0.4, 4.0, 0.05) var smoke_lifetime: float = 1.6:
	set(value):
		smoke_lifetime = maxf(value, 0.2)
		_configure_smoke_trail()

@export_range(0.05, 1.5, 0.01) var smoke_scale_min: float = 0.18:
	set(value):
		smoke_scale_min = maxf(value, 0.02)
		_configure_smoke_trail()

@export_range(0.05, 2.0, 0.01) var smoke_scale_max: float = 0.42:
	set(value):
		smoke_scale_max = maxf(value, 0.02)
		_configure_smoke_trail()

@export_range(0.0, 3.0, 0.05) var smoke_speed_min: float = 0.25:
	set(value):
		smoke_speed_min = maxf(value, 0.0)
		_configure_smoke_trail()

@export_range(0.0, 4.0, 0.05) var smoke_speed_max: float = 0.95:
	set(value):
		smoke_speed_max = maxf(value, 0.0)
		_configure_smoke_trail()

@export_range(0.05, 1.0, 0.01) var smoke_opacity: float = 0.45:
	set(value):
		smoke_opacity = clampf(value, 0.0, 1.0)
		_configure_smoke_trail()

@export_group("Embers")
@export_range(0, 160, 1) var ember_amount: int = 64:
	set(value):
		ember_amount = clampi(value, 0, 160)
		_configure_ember_sparks()

@export_range(0.15, 2.0, 0.05) var ember_lifetime: float = 0.45:
	set(value):
		ember_lifetime = maxf(value, 0.1)
		_configure_ember_sparks()

@export_range(0.005, 0.3, 0.001) var ember_scale_min: float = 0.02:
	set(value):
		ember_scale_min = maxf(value, 0.002)
		_configure_ember_sparks()

@export_range(0.005, 0.4, 0.001) var ember_scale_max: float = 0.055:
	set(value):
		ember_scale_max = maxf(value, 0.002)
		_configure_ember_sparks()

@export_range(0.0, 6.0, 0.05) var ember_speed_min: float = 0.8:
	set(value):
		ember_speed_min = maxf(value, 0.0)
		_configure_ember_sparks()

@export_range(0.0, 8.0, 0.05) var ember_speed_max: float = 2.8:
	set(value):
		ember_speed_max = maxf(value, 0.0)
		_configure_ember_sparks()

var _glow_restart_queued := false

var _direction := Vector3.FORWARD
var _elapsed := 0.0
var _speed: float = SPEED
var _smoke_trail: CPUParticles3D
var _ember_sparks: CPUParticles3D
var _hit_shape: SphereShape3D
var _travel_light: OmniLight3D
var _core_material: StandardMaterial3D
var _shell_material: StandardMaterial3D
var _core_mesh: MeshInstance3D
var _flame_shell: MeshInstance3D
var _collision: CollisionShape3D
var _glow_tween: Tween
var _caster: Node3D
var _finished := false
## Catch-up from NetworkWeapon must not spend the payload — rollback will.
var _combat_enabled := true
var _preview_material_ready := false
## 0..1 visual scale driven by charge (trails + impact FX).
var _charge_fx_scale := 1.0
var _fx_committed := false
var _impact_fx_parent: Node = null
var _impact_fx_pos := Vector3.ZERO


static func spawn(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	caster: Node3D = null,
	lookdev_flight: bool = false,
	charge_factor: float = 1.0
) -> Node:
	## Lazy-load avoids circular preload with fireball.tscn.
	var packed: PackedScene = load("res://scenes/spells/fireball/fireball.tscn") as PackedScene
	var projectile: Node = packed.instantiate()
	if lookdev_flight:
		projectile.set_meta("lookdev_flight", true)
		projectile.process_mode = Node.PROCESS_MODE_ALWAYS
	if projectile is FireballProjectile:
		var ball := projectile as FireballProjectile
		ball._direction = direction.normalized()
		ball._caster = caster
		ball.apply_charge_power(charge_factor)
	## Place before add_child so `_ready` light/particles are not at Match origin.
	if parent != null and projectile is Node3D:
		SpellEphemeralFxScript.add_child_at(parent, projectile as Node3D, origin)
	elif parent != null:
		parent.add_child(projectile)
	if projectile is Node3D:
		NetLivenessScript.after_spawn(projectile as Node3D)
	return projectile


static func authored_charge_time_sec() -> float:
	return _authored_float("charge_time_sec", DEFAULT_CHARGE_TIME_SEC, 0.05)


static func authored_wand_charge_pose_sec() -> float:
	return _authored_float("wand_charge_pose_sec", DEFAULT_WAND_CHARGE_POSE_SEC, 0.02)


static func _authored_float(property_name: String, fallback: float, min_value: float) -> float:
	var packed: PackedScene = load(SpellDefinition.world_scene_path("fireball")) as PackedScene
	if packed == null:
		return maxf(fallback, min_value)
	var state := packed.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == property_name:
			return maxf(float(state.get_node_property_value(0, i)), min_value)
	return maxf(fallback, min_value)


## charge 0 → min damage / baseball AoE / base speed; charge 1 → authored max + speed boost.
func apply_charge_power(charge_factor: float) -> void:
	var t := clampf(charge_factor, 0.0, 1.0)
	_speed = SPEED * lerpf(CHARGE_SPEED_MIN_MULT, CHARGE_SPEED_MAX_MULT, t)
	var splash_max := splash_radius
	var core_max := core_radius
	var hit_max := hit_radius
	var shell_max := shell_radius
	var light_max := light_radius
	var smoke_emit_max := smoke_emission_radius
	var smoke_puff_max := smoke_puff_radius
	var smoke_amt_max := smoke_amount
	var ember_emit_max := ember_emission_radius
	var ember_puff_max := ember_puff_radius
	var ember_amt_max := ember_amount
	_scale_payload_damage(t)
	splash_radius = lerpf(CHARGE_AOE_MIN_RADIUS, splash_max, t)
	core_radius = lerpf(CHARGE_AOE_MIN_RADIUS, core_max, t)
	hit_radius = lerpf(CHARGE_AOE_MIN_RADIUS, hit_max, t)
	shell_radius = lerpf(CHARGE_AOE_MIN_RADIUS * 1.15, shell_max, t)
	light_radius = lerpf(CHARGE_AOE_MIN_RADIUS * 2.0, light_max, t)
	## Trail + impact FX track projectile scale (baseball → full).
	_charge_fx_scale = lerpf(CHARGE_AOE_MIN_RADIUS / maxf(core_max, 0.01), 1.0, t)
	smoke_emission_radius = smoke_emit_max * _charge_fx_scale
	smoke_puff_radius = smoke_puff_max * _charge_fx_scale
	smoke_amount = maxi(2, int(round(float(smoke_amt_max) * _charge_fx_scale)))
	ember_emission_radius = ember_emit_max * _charge_fx_scale
	ember_puff_radius = ember_puff_max * _charge_fx_scale
	ember_amount = maxi(1, int(round(float(ember_amt_max) * _charge_fx_scale)))
	if is_inside_tree():
		_sync_orb_shape()


func _scale_payload_damage(charge_t: float) -> void:
	payload = _ensure_payload().duplicate(true) as CombatPayload
	for effect in payload.effects:
		if effect is Damage:
			var dmg := effect as Damage
			dmg.amount = lerpf(CHARGE_DAMAGE_MIN, dmg.amount, charge_t)
			hit_damage = dmg.amount


func _ensure_payload() -> CombatPayload:
	if payload != null:
		return payload
	payload = CombatPayload.new()
	payload.effects.append(Damage.with(hit_damage))
	return payload


func _is_lookdev_flight() -> bool:
	return bool(get_meta("lookdev_flight", false))


func _ready() -> void:
	_cache_nodes()
	_sync_orb_shape()
	_prepare_runtime_materials()
	_apply_preview_fx()
	_update_process_state()
	NetDisplayCommitScript.bind(_commit_impact_fx)
	if Engine.is_editor_hint() and not _is_lookdev_flight():
		set_physics_process(false)
		return

	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = CollisionLayersScript.CHARACTER_AND_WORLD

	_configure_travel_light()

	if animate_glow:
		_start_glow_pulse()
	_ensure_smoke_trail(true)
	_ensure_ember_sparks(true)
	_position_trail_emitters()

	set_physics_process(true)


func _exit_tree() -> void:
	NetDisplayCommitScript.unbind(_commit_impact_fx)


func _process(delta: float) -> void:
	if _finished:
		return
	if animate_fire_texture and _core_material != null:
		_core_material.uv1_offset.x = fmod(
			_core_material.uv1_offset.x + delta * fire_scroll_x,
			1.0
		)
		_core_material.uv1_offset.y = fmod(
			_core_material.uv1_offset.y + delta * fire_scroll_y,
			1.0
		)
	if animate_shell and _shell_material != null:
		var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * shell_pulse_hz * TAU)
		_shell_material.albedo_color.a = lerpf(shell_alpha_min, shell_alpha_max, wave)


func _cache_nodes() -> void:
	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_core_mesh = get_node_or_null("Core") as MeshInstance3D
	_flame_shell = get_node_or_null("FlameShell") as MeshInstance3D
	_travel_light = get_node_or_null("TravelCastLight") as OmniLight3D
	_smoke_trail = get_node_or_null("SmokeTrail") as CPUParticles3D
	_ember_sparks = get_node_or_null("EmberSparks") as CPUParticles3D
	if _collision != null and _collision.shape is SphereShape3D:
		_hit_shape = _collision.shape as SphereShape3D
	if _core_mesh != null and _core_mesh.material_override is StandardMaterial3D:
		_core_material = _core_mesh.material_override as StandardMaterial3D
	if _flame_shell != null and _flame_shell.material_override is StandardMaterial3D:
		_shell_material = _flame_shell.material_override as StandardMaterial3D


func _prepare_runtime_materials() -> void:
	## Duplicate so UV scroll / glow pulse never dirty the packed scene material.
	if _core_mesh != null:
		_core_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_core_mesh.layers = WorldVisualLayers.WORLD
		if _core_mesh.material_override is StandardMaterial3D:
			_core_material = (_core_mesh.material_override as StandardMaterial3D).duplicate()
			_ensure_additive_fire_material(_core_material)
			_core_mesh.material_override = _core_material
	if _flame_shell != null:
		_flame_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame_shell.layers = WorldVisualLayers.WORLD
		if _flame_shell.material_override is StandardMaterial3D:
			_shell_material = (_flame_shell.material_override as StandardMaterial3D).duplicate()
			_ensure_additive_fire_material(_shell_material, false)
			_flame_shell.material_override = _shell_material
	_preview_material_ready = true


func _ensure_additive_fire_material(
	mat: StandardMaterial3D,
	keep_albedo_texture: bool = true
) -> void:
	## Opaque cores read as a black disc under game tonemapping; keep fire additive.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.emission_enabled = true
	var emission_strength := mat.emission.r + mat.emission.g + mat.emission.b
	if mat.emission.a <= 0.0 or emission_strength < 0.15:
		mat.emission = Color(1.0, 0.55, 0.12, 1.0)
	if mat.emission_energy_multiplier < 1.0:
		mat.emission_energy_multiplier = 3.4
	if keep_albedo_texture and mat.albedo_texture != null and mat.emission_texture == null:
		mat.emission_texture = mat.albedo_texture


func _sync_orb_shape() -> void:
	if _core_mesh == null or _collision == null:
		_cache_nodes()
	if _core_mesh != null:
		var mesh := _core_mesh.mesh as SphereMesh
		if mesh == null:
			mesh = SphereMesh.new()
			_core_mesh.mesh = mesh
		mesh.radius = core_radius
		mesh.height = core_radius * 2.0
	if _flame_shell != null:
		var shell_mesh := _flame_shell.mesh as SphereMesh
		if shell_mesh == null:
			shell_mesh = SphereMesh.new()
			_flame_shell.mesh = shell_mesh
		shell_mesh.radius = shell_radius
		shell_mesh.height = shell_radius * 2.0
	_sync_shell_visibility()
	if _collision != null:
		var shape := _collision.shape as SphereShape3D
		if shape == null:
			shape = SphereShape3D.new()
			_collision.shape = shape
		shape.radius = hit_radius
		_hit_shape = shape
	_configure_smoke_trail()
	_configure_ember_sparks()
	_configure_travel_light()
	_position_trail_emitters()


func _configure_travel_light() -> void:
	if _travel_light == null:
		_cache_nodes()
	if _travel_light == null:
		if Engine.is_editor_hint() or not is_inside_tree():
			return
		_travel_light = FireballLightingScript.make_travel_cast_light()
		_travel_light.name = "TravelCastLight"
		add_child(_travel_light)
	FireballLightingScript.configure_cast_light(
		_travel_light,
		1.35,
		light_radius,
		Color(1.0, 0.5, 0.14),
		true
	)


func _sync_shell_visibility() -> void:
	if _flame_shell == null:
		_cache_nodes()
	if _flame_shell != null:
		_flame_shell.visible = shell_visible


func _apply_preview_fx() -> void:
	if not is_inside_tree():
		return
	if not _preview_material_ready and Engine.is_editor_hint():
		_cache_nodes()
		_prepare_runtime_materials()
	if Engine.is_editor_hint():
		_ensure_smoke_trail(preview_smoke)
		_ensure_ember_sparks(preview_embers)
		_position_trail_emitters()
		if preview_glow and animate_glow:
			_start_glow_pulse()
		else:
			_stop_glow_pulse()
	elif animate_glow:
		_start_glow_pulse()
	else:
		_stop_glow_pulse()
	_update_process_state()


func _update_process_state() -> void:
	var need_process := animate_fire_texture or animate_shell
	if Engine.is_editor_hint():
		need_process = need_process or (preview_glow and animate_glow)
	else:
		need_process = true
	set_process(need_process)


func _ensure_smoke_trail(enabled: bool) -> void:
	_smoke_trail = get_node_or_null("SmokeTrail") as CPUParticles3D
	if not enabled:
		if _smoke_trail != null and is_instance_valid(_smoke_trail):
			_smoke_trail.emitting = false
			_smoke_trail.visible = false
		return
	if _smoke_trail == null:
		_smoke_trail = FireballSmokeTrailScript.create_emitter()
		_smoke_trail.name = "SmokeTrail"
		add_child(_smoke_trail)
	_configure_smoke_trail()
	_smoke_trail.visible = true
	_smoke_trail.emitting = true
	_smoke_trail.restart()


func _ensure_ember_sparks(enabled: bool) -> void:
	_ember_sparks = get_node_or_null("EmberSparks") as CPUParticles3D
	if not enabled:
		if _ember_sparks != null and is_instance_valid(_ember_sparks):
			_ember_sparks.emitting = false
			_ember_sparks.visible = false
		return
	if _ember_sparks == null:
		_ember_sparks = FireballParticlesScript.make_comet_spark_emitter()
		_ember_sparks.name = "EmberSparks"
		add_child(_ember_sparks)
	_configure_ember_sparks()
	_ember_sparks.visible = true
	_ember_sparks.emitting = ember_amount > 0
	if _ember_sparks.emitting:
		_ember_sparks.restart()


func _configure_smoke_trail() -> void:
	if _smoke_trail == null or not is_instance_valid(_smoke_trail):
		return
	_smoke_trail.amount = smoke_amount
	_smoke_trail.lifetime = smoke_lifetime
	_smoke_trail.emission_sphere_radius = smoke_emission_radius
	_smoke_trail.scale_amount_min = minf(smoke_scale_min, smoke_scale_max)
	_smoke_trail.scale_amount_max = maxf(smoke_scale_min, smoke_scale_max)
	_smoke_trail.initial_velocity_min = minf(smoke_speed_min, smoke_speed_max)
	_smoke_trail.initial_velocity_max = maxf(smoke_speed_min, smoke_speed_max)
	var smoke_color := _smoke_trail.color
	smoke_color.a = smoke_opacity
	_smoke_trail.color = smoke_color
	var puff := _smoke_trail.mesh as QuadMesh
	if puff == null:
		puff = QuadMesh.new()
		_smoke_trail.mesh = puff
	var puff_size := smoke_puff_radius * 2.0
	puff.size = Vector2(puff_size, puff_size)


func _configure_ember_sparks() -> void:
	if _ember_sparks == null or not is_instance_valid(_ember_sparks):
		return
	_ember_sparks.amount = maxi(ember_amount, 1)
	_ember_sparks.lifetime = ember_lifetime
	_ember_sparks.emission_sphere_radius = ember_emission_radius
	_ember_sparks.scale_amount_min = minf(ember_scale_min, ember_scale_max)
	_ember_sparks.scale_amount_max = maxf(ember_scale_min, ember_scale_max)
	_ember_sparks.initial_velocity_min = minf(ember_speed_min, ember_speed_max)
	_ember_sparks.initial_velocity_max = maxf(ember_speed_min, ember_speed_max)
	_ember_sparks.emitting = ember_amount > 0
	var spark := _ember_sparks.mesh as QuadMesh
	if spark == null:
		spark = QuadMesh.new()
		_ember_sparks.mesh = spark
	var spark_size := ember_puff_radius * 2.0
	spark.size = Vector2(spark_size, spark_size)


func _position_trail_emitters() -> void:
	var back := -_direction
	if back.length_squared() < 0.0001:
		back = Vector3(0.0, 0.0, 1.0)
	else:
		back = back.normalized()
	## In the editor there is no travel direction — drift smoke behind + slightly up.
	if Engine.is_editor_hint():
		back = Vector3(0.15, 0.05, 0.85).normalized()
	if _smoke_trail != null and is_instance_valid(_smoke_trail):
		_smoke_trail.position = back * (core_radius + smoke_emission_radius * 0.5)
	if _ember_sparks != null and is_instance_valid(_ember_sparks):
		_ember_sparks.position = back * (core_radius * 0.45)


func _restart_glow_pulse() -> void:
	if not is_inside_tree() or _glow_restart_queued:
		return
	_glow_restart_queued = true
	call_deferred("_restart_glow_pulse_now")


func _restart_glow_pulse_now() -> void:
	_glow_restart_queued = false
	if not is_inside_tree():
		return
	var glow_on := animate_glow
	if Engine.is_editor_hint():
		glow_on = glow_on and preview_glow
	if glow_on:
		_start_glow_pulse()
	else:
		_stop_glow_pulse()


func _start_glow_pulse() -> void:
	_stop_glow_pulse()
	if not animate_glow:
		return
	if _travel_light == null or _core_material == null:
		_cache_nodes()
	if _travel_light == null or _core_material == null:
		return
	var light_lo := minf(glow_light_base, glow_light_peak)
	var light_hi := maxf(glow_light_base, glow_light_peak)
	var emit_lo := minf(fire_emission_base, fire_emission_peak)
	var emit_hi := maxf(fire_emission_base, fire_emission_peak)
	var half := glow_half_period_sec
	var pulse := create_tween()
	pulse.set_loops()
	pulse.tween_method(
		func(intensity: float) -> void:
			if _travel_light != null:
				_travel_light.light_energy = lerpf(light_lo, light_hi, intensity)
			if _core_material != null:
				_core_material.emission_energy_multiplier = lerpf(emit_lo, emit_hi, intensity),
		0.0,
		1.0,
		half
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_method(
		func(intensity: float) -> void:
			if _travel_light != null:
				_travel_light.light_energy = lerpf(light_hi, light_lo, intensity)
			if _core_material != null:
				_core_material.emission_energy_multiplier = lerpf(emit_hi, emit_lo, intensity),
		0.0,
		1.0,
		half
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween = pulse


func _stop_glow_pulse() -> void:
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = null


func _physics_process(delta: float) -> void:
	if _finished or not is_inside_tree():
		return
	if Engine.is_editor_hint() and not _is_lookdev_flight():
		return
	if NetLivenessScript.skip_engine_physics():
		return
	_simulate_flight(delta)


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	_simulate_flight(delta)


func _rollback_spawn() -> void:
	_finished = false
	_fx_committed = false
	NetLivenessScript.activate(self)


func _rollback_despawn() -> void:
	NetLivenessScript.deactivate(self)


func simulate_from_tick(fired_tick: int) -> void:
	if not NetClockScript.is_ticking():
		return
	var nt := Engine.get_main_loop()
	if not (nt is SceneTree):
		return
	var time_node := (nt as SceneTree).root.get_node_or_null("NetworkTime")
	if time_node == null:
		return
	var now := int(time_node.get("tick"))
	var tick_time := float(time_node.get("ticktime"))
	_combat_enabled = false
	for _tick in range(fired_tick, now):
		if _finished:
			break
		_simulate_flight(tick_time)
	_combat_enabled = true


func _simulate_flight(delta: float) -> void:
	if _finished or not is_inside_tree():
		return
	_elapsed += delta
	if FireballFlightScript.should_finish_normal(_elapsed):
		_finish(null, false)
		return

	var motion: Vector3 = _direction * _speed * delta
	if _try_block_ward_overlap():
		return
	if _cast_motion_hit(motion):
		return
	global_position += motion
	_probe_players()


func apply_net_launch(origin: Vector3, direction: Vector3, charge_factor: float = 1.0) -> void:
	global_position = origin
	if direction.length_squared() > 0.0001:
		_direction = direction.normalized()
	apply_charge_power(charge_factor)


func _cast_motion_hit(motion: Vector3) -> bool:
	if not is_inside_tree() or _hit_shape == null:
		return false
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	params.transform = global_transform
	params.motion = motion
	params.exclude = _exclude_rids()
	params.collision_mask = collision_mask
	var contact := space_state.cast_motion(params)
	var safe_fraction: float = contact[0]
	if safe_fraction >= 1.0:
		return false
	var ward := _find_ward_along_motion(params, motion * safe_fraction)
	global_position += motion * safe_fraction
	if ward == null:
		ward = _find_ward_in_group_proximity()
	if ward != null:
		_finish(ward, true)
		return true
	if _try_block_ward_overlap():
		return true
	if _probe_players():
		return true
	_finish(null, true)
	return true


func _try_block_ward_overlap() -> bool:
	## Wards win over monster/player overlap at the impact point (ash ward charge, etc.).
	if not is_inside_tree() or _hit_shape == null or _finished:
		return false
	var ward := _find_ward_hit()
	if ward == null:
		return false
	_finish(ward, true)
	return true


func _exclude_rids() -> Array:
	var rids: Array = [get_rid()]
	if is_instance_valid(_caster) and _caster is CollisionObject3D:
		rids.append((_caster as CollisionObject3D).get_rid())
	return rids


func _probe_players() -> bool:
	if not is_inside_tree() or _hit_shape == null:
		return false
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	params.transform = global_transform
	params.exclude = _exclude_rids()
	params.collision_mask = collision_mask
	var hits := space_state.intersect_shape(params, 8)
	for hit in hits:
		var collider: Variant = hit.get("collider")
		if collider is Node3D and _try_hit_player(collider as Node3D):
			return true
	return false


func _finish(blocked_by: Node = null, apply_splash: bool = false) -> void:
	if _finished or not is_inside_tree():
		return
	_finished = true
	_notify_ward_blocked(blocked_by)
	_impact_fx_parent = get_parent()
	_impact_fx_pos = global_position
	var ward := _ward_from_node(blocked_by) if blocked_by != null else null
	if apply_splash and _combat_enabled and ward == null:
		_apply_splash_at(_impact_fx_pos, blocked_by)
	_clear_projectile_visuals()
	NetDisplayCommitScript.request(_commit_impact_fx)
	NetLivenessScript.despawn_or_free(self)


func _commit_impact_fx() -> void:
	if _fx_committed or not _finished:
		return
	_fx_committed = true
	var parent := _impact_fx_parent
	if parent == null or not is_instance_valid(parent):
		parent = get_parent()
	if parent == null:
		return
	FireballExplosionEffectScript.spawn(parent, _impact_fx_pos, _charge_fx_scale)


func _apply_splash_at(impact_pos: Vector3, hit: Node = null) -> void:
	if splash_radius <= 0.0:
		return
	CombatSplash.apply_at(
		get_tree(), impact_pos, splash_radius, self, _ensure_payload(), _caster, hit
	)


func _find_ward_hit() -> Node:
	var ward := _find_ward_along_motion(_shape_query_params(), Vector3.ZERO)
	if ward != null:
		return ward
	return _find_ward_in_group_proximity()


func _find_ward_in_group_proximity() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node = null
	var best_dist_sq := INF
	for node in tree.get_nodes_in_group("spell_ward"):
		if node == null or not node.has_method("notify_spell_blocked"):
			continue
		if not (node is Node3D):
			continue
		var ward_node := node as Node3D
		var ward_radius := 1.35
		if "radius" in ward_node:
			ward_radius = float(ward_node.get("radius"))
		var reach := hit_radius + ward_radius * 1.2
		var dist_sq := global_position.distance_squared_to(ward_node.global_position)
		if dist_sq <= reach * reach and dist_sq < best_dist_sq:
			best = ward_node
			best_dist_sq = dist_sq
	return best


func _shape_query_params() -> PhysicsShapeQueryParameters3D:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	params.transform = global_transform
	params.exclude = _exclude_rids()
	params.collision_mask = collision_mask
	return params


func _find_ward_along_motion(params: PhysicsShapeQueryParameters3D, motion: Vector3) -> Node:
	if not is_inside_tree() or _hit_shape == null:
		return null
	var space_state := get_world_3d().direct_space_state
	if motion.length_squared() > 0.0001:
		var origin: Vector3 = params.transform.origin
		var end: Vector3 = origin + motion
		var ray := PhysicsRayQueryParameters3D.create(origin, end)
		ray.exclude = params.exclude
		ray.collision_mask = params.collision_mask
		ray.hit_from_inside = true
		var hit: Dictionary = space_state.intersect_ray(ray)
		if not hit.is_empty():
			var ward := _ward_from_collider(hit.get("collider"))
			if ward != null:
				return ward
	for hit_dict in space_state.intersect_shape(params, 8):
		var ward := _ward_from_collider(hit_dict.get("collider"))
		if ward != null:
			return ward
	return null


func _ward_from_collider(collider: Variant) -> Node:
	if collider is Node:
		return _ward_from_node(collider as Node)
	return null


func _ward_from_node(node: Node) -> Node:
	var walk: Node = node
	while walk != null:
		if walk.is_in_group("spell_ward") and walk.has_method("notify_spell_blocked"):
			return walk
		walk = walk.get_parent()
	return null


func _notify_ward_blocked(blocked_by: Node) -> void:
	var ward := _ward_from_node(blocked_by) if blocked_by != null else _find_ward_hit()
	if ward != null:
		ward.call("notify_spell_blocked", hit_damage, _caster)


func _clear_projectile_visuals() -> void:
	_stop_glow_pulse()
	if _smoke_trail != null and is_instance_valid(_smoke_trail):
		_smoke_trail.queue_free()
		_smoke_trail = null
	if _ember_sparks != null and is_instance_valid(_ember_sparks):
		_ember_sparks.queue_free()
		_ember_sparks = null
	if _core_mesh != null and is_instance_valid(_core_mesh):
		_core_mesh.visible = false
	if _flame_shell != null and is_instance_valid(_flame_shell):
		_flame_shell.visible = false
	if _travel_light != null and is_instance_valid(_travel_light):
		_travel_light.visible = false
		_travel_light.light_energy = 0.0
	visible = false
	set_process(false)


func _try_hit_player(body: Node3D) -> bool:
	## Name kept for call sites; also hits monsters / combat_target (not player-only).
	if body == null or body == _caster:
		return false
	if not (
		body.is_in_group("player")
		or body.is_in_group("monster")
		or body.is_in_group("combat_target")
	):
		return false
	if not Character.is_node_alive(body):
		return false
	if _try_block_ward_overlap():
		return true
	## Named connect: this body, even if its root sits outside splash_radius.
	_finish(body, true)
	return true
