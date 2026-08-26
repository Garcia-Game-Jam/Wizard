@tool
class_name FlareEffect
extends Area3D

## Signal flare: GPU comet trail while flying, then a pulsing omni beacon.
## Slides on walls, floors, players, and monsters with drag += contact_drag.
## Tune on the Flare root in scenes/spells/flare/flare.tscn (static lookdev).
## Flight + wand launch previews live in scenes/spells/flare/workspace.tscn.

const DEFAULT_DURATION_SEC := 15.0

const FlareFlightScript := preload("res://scripts/spells/flare_flight.gd")
const FlareParticlesScript := preload("res://scripts/spells/flare_particles.gd")
const FireballLightingScript := preload("res://scripts/spells/fireball_lighting.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")

## Cached ammo knobs from scenes/spells/flare.tscn (source of truth for loadout).
static var _authored_ammo_cache: Dictionary = {}

@export_group("Beacon")
## Peak omni brightness while the flare is burning (before fade-out).
@export_range(2.0, 80.0, 0.5) var light_peak_energy: float = 36.0
## How far the red beacon light reaches across the maze.
@export_range(40.0, 480.0, 1.0) var light_range: float = 320.0
## Seconds the beacon stays lit after launch (pulse + fade use this).
@export_range(4.0, 60.0, 0.5) var duration_sec: float = DEFAULT_DURATION_SEC
## Visible thermite core radius (world units).
@export_range(0.01, 0.5, 0.005) var core_radius: float = 0.04:
	set(value):
		core_radius = maxf(value, 0.005)
		_apply_core_visual_size()
## Physics probe radius for floors, walls, players, and monsters during flight.
@export_range(0.05, 1.0, 0.01) var hit_radius: float = FlareFlightScript.HIT_RADIUS:
	set(value):
		hit_radius = maxf(value, 0.02)
		_sync_hit_shape()

@export_group("Flight")
## Initial launch speed along the cast aim (m/s). Affects both hang time and range.
@export_range(1.0, 120.0, 0.5) var launch_speed: float = FlareFlightScript.LAUNCH_SPEED
## Light drag on vertical velocity — slows ascent/descent without killing hang time.
@export_range(0.0, 8.0, 0.01) var drag: float = FlareFlightScript.DRAG
## Strong drag on horizontal (X/Z) — bleed sideways travel while gravity keeps it aloft.
@export_range(0.0, 12.0, 0.05) var horizontal_drag: float = FlareFlightScript.HORIZONTAL_DRAG
## Downward pull while coasting. Lower = longer sky hang;
## raise horizontal_drag if the rocket travels too far sideways.
@export_range(0.0, 40.0, 0.1) var flight_gravity: float = FlareFlightScript.GRAVITY
## Added to `drag` while scraping any surface (walls, floor, players, monsters).
@export_range(0.0, 8.0, 0.05) var contact_drag: float = FlareFlightScript.CONTACT_DRAG

@export_group("Ammo")
## How many flares the player can hold at once.
@export_range(1, 20, 1) var ammo_max: int = 3:
	set(value):
		ammo_max = maxi(value, 1)
		_invalidate_authored_ammo_cache()
## Seconds between refills while below ammo_max.
@export_range(0.05, 30.0, 0.05) var ammo_refill_sec: float = 2.0:
	set(value):
		ammo_refill_sec = maxf(value, 0.05)
		_invalidate_authored_ammo_cache()

@export_group("Comet VFX")
## GPU comet streak while flying. Off during beacon phase (no CPU particles).
@export var comet_sparks_enabled := true:
	set(value):
		comet_sparks_enabled = value
		if is_inside_tree():
			_configure_comet_sparks()
## Live GPU spark count (keep modest — one flare at a time).
@export_range(0, 64, 1) var comet_spark_amount: int = 24:
	set(value):
		comet_spark_amount = value
		if is_inside_tree():
			_configure_comet_sparks()
@export_range(0.05, 1.5, 0.01) var comet_spark_lifetime: float = 0.38:
	set(value):
		comet_spark_lifetime = value
		if is_inside_tree():
			_configure_comet_sparks()
@export_range(0.0, 6.0, 0.05) var comet_spark_velocity_min: float = 0.6:
	set(value):
		comet_spark_velocity_min = value
		if is_inside_tree():
			_configure_comet_sparks()
@export_range(0.0, 8.0, 0.05) var comet_spark_velocity_max: float = 2.2:
	set(value):
		comet_spark_velocity_max = value
		if is_inside_tree():
			_configure_comet_sparks()
@export_range(0.005, 0.2, 0.001) var comet_spark_scale_min: float = 0.018:
	set(value):
		comet_spark_scale_min = value
		if is_inside_tree():
			_configure_comet_sparks()
@export_range(0.005, 0.2, 0.001) var comet_spark_scale_max: float = 0.05:
	set(value):
		comet_spark_scale_max = value
		if is_inside_tree():
			_configure_comet_sparks()
@export var comet_spark_color: Color = Color(1.0, 0.58, 0.12, 0.95):
	set(value):
		comet_spark_color = value
		if is_inside_tree():
			_configure_comet_sparks()

var _thermite_core: MeshInstance3D
var _thermite_material: StandardMaterial3D
var _beacon_light: OmniLight3D
var _comet_sparks: GPUParticles3D
var _collision: CollisionShape3D
var _hit_shape: SphereShape3D
var _pulse_tween: Tween
var _life_tween: Tween
var _runtime := false
var _playing := false
var _flying := false
var _direction := Vector3.UP
var _velocity := Vector3.ZERO
var _caster: Node3D
var _life_t := 0.0
var _pulse_t := 1.0
var _sliding_on_contact := false


static func authored_ammo_max() -> int:
	_ensure_authored_ammo_cache()
	return maxi(int(_authored_ammo_cache.get("max", 3)), 1)


static func authored_ammo_refill_sec() -> float:
	_ensure_authored_ammo_cache()
	return maxf(float(_authored_ammo_cache.get("refill", 2.0)), 0.05)


static func _invalidate_authored_ammo_cache() -> void:
	_authored_ammo_cache.clear()


static func _ensure_authored_ammo_cache() -> void:
	if not _authored_ammo_cache.is_empty():
		return
	var packed := load(SpellDefinition.world_scene_path("flare")) as PackedScene
	if packed == null:
		_authored_ammo_cache = {"max": 3, "refill": 2.0}
		return
	var sample := packed.instantiate() as FlareEffect
	if sample == null:
		_authored_ammo_cache = {"max": 3, "refill": 2.0}
		return
	_authored_ammo_cache = {
		"max": maxi(sample.ammo_max, 1),
		"refill": maxf(sample.ammo_refill_sec, 0.05),
	}
	sample.free()


static func spawn(
	parent: Node,
	world_position: Vector3,
	duration: float = DEFAULT_DURATION_SEC
) -> FlareEffect:
	## Stationary lookdev / tests — no flight.
	return spawn_launched(parent, world_position, Vector3.ZERO, duration, false)


static func spawn_launched(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	duration: float = DEFAULT_DURATION_SEC,
	fly: bool = true,
	caster: Node3D = null,
	template: FlareEffect = null
) -> FlareEffect:
	var packed: PackedScene = load(SpellDefinition.world_scene_path("flare")) as PackedScene
	var flare: FlareEffect = packed.instantiate() as FlareEffect
	flare._runtime = true
	flare.duration_sec = maxf(duration, 1.0)
	flare._flying = fly
	flare._caster = caster
	if template != null:
		template.copy_tuning_to(flare)
	if fly:
		flare._velocity = FlareFlightScript.initial_velocity(direction, flare.launch_speed)
		flare._direction = FlareFlightScript.launch_direction(direction)
	else:
		flare._velocity = Vector3.ZERO
		flare._direction = Vector3.ZERO
	## Place before add_child so `_ready` beacon is not at Match origin.
	SpellEphemeralFxScript.add_child_at(parent, flare, origin)
	flare.play_launch()
	NetLivenessScript.after_spawn(flare)
	return flare


## charge 0 → base launch speed / dimmer beacon; charge 1 → +56.25% speed / full light.
func apply_charge_power(charge_factor: float) -> void:
	var t := clampf(charge_factor, 0.0, 1.0)
	light_peak_energy = light_peak_energy * lerpf(0.55, 1.0, t)
	var speed_max := launch_speed
	launch_speed = speed_max * lerpf(1.0, 1.5625, t)
	if _flying:
		var aim := _direction if _direction.length_squared() > 0.0001 else Vector3.FORWARD
		_velocity = FlareFlightScript.initial_velocity(aim, launch_speed)
	_refresh_visual_state()


func copy_tuning_to(target: FlareEffect) -> void:
	if target == null:
		return
	target.light_peak_energy = light_peak_energy
	target.light_range = light_range
	target.duration_sec = duration_sec
	target.core_radius = core_radius
	target.hit_radius = hit_radius
	target.launch_speed = launch_speed
	target.drag = drag
	target.horizontal_drag = horizontal_drag
	target.flight_gravity = flight_gravity
	target.contact_drag = contact_drag
	target.comet_sparks_enabled = comet_sparks_enabled
	target.comet_spark_amount = comet_spark_amount
	target.comet_spark_lifetime = comet_spark_lifetime
	target.comet_spark_velocity_min = comet_spark_velocity_min
	target.comet_spark_velocity_max = comet_spark_velocity_max
	target.comet_spark_scale_min = comet_spark_scale_min
	target.comet_spark_scale_max = comet_spark_scale_max
	target.comet_spark_color = comet_spark_color


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	_cache_nodes()
	_configure_authored_nodes()
	_sync_hit_shape()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	## Runtime play happens in spawn_launched() after global_position is set.
	if Engine.is_editor_hint() and not _runtime:
		monitoring = false
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if NetLivenessScript.skip_engine_physics():
		return
	_step_flight(delta)


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	_step_flight(delta)


func _rollback_spawn() -> void:
	NetLivenessScript.activate(self)


func _rollback_despawn() -> void:
	NetLivenessScript.deactivate(self)


func _step_flight(delta: float) -> void:
	if not _playing or not _flying:
		return
	var on_contact := _sliding_on_contact
	_velocity = FlareFlightScript.step_velocity(
		_velocity,
		delta,
		drag + (contact_drag if on_contact else 0.0),
		flight_gravity,
		horizontal_drag
	)
	var motion := _velocity * delta
	if _is_lookdev_launch():
		_step_lookdev_flight(motion, delta, on_contact)
		return
	_move_and_slide_flight(motion, delta, on_contact)
	if _velocity.length_squared() > 0.0001:
		_direction = _velocity.normalized()
	_refresh_visual_state()


func _step_lookdev_flight(
	motion: Vector3, delta: float, already_applied_contact_drag: bool
) -> void:
	## Workspace floor has no collider — treat y=0 as a slide plane.
	global_position += motion
	_sliding_on_contact = false
	if global_position.y <= 0.0:
		global_position.y = 0.0
		_velocity = FlareFlightScript.slide_on_contact(_velocity, Vector3.UP)
		if not already_applied_contact_drag:
			_velocity = FlareFlightScript.step_velocity(
				_velocity, delta, contact_drag, 0.0, 0.0
			)
		_sliding_on_contact = true
	if _velocity.length_squared() > 0.0001:
		_direction = _velocity.normalized()
	_refresh_visual_state()


## Legacy editor tool target — use flare_workspace Launch Flare instead.
func replay_launch() -> void:
	pass


func play_launch() -> void:
	if not is_inside_tree():
		return
	_cache_nodes()
	_configure_authored_nodes()
	_sync_hit_shape()
	_stop_tweens()
	_playing = true
	_life_t = 0.0
	_pulse_t = 1.0
	_sliding_on_contact = false

	_reset_core_visuals()
	_configure_comet_sparks()
	_refresh_visual_state()
	_start_beacon_pulse()
	_start_lifespan()
	monitoring = _flying and _runtime and not Engine.is_editor_hint()
	_configure_flight_tick()


func _configure_flight_tick() -> void:
	if not _flying:
		set_physics_process(false)
		set_process(false)
		return
	if _is_lookdev_launch():
		## @tool scenes tick _process in the editor, not _physics_process.
		set_process(true)
		set_physics_process(false)
	else:
		set_process(false)
		set_physics_process(true)


func _is_lookdev_launch() -> bool:
	return _runtime and Engine.is_editor_hint()


func _process(delta: float) -> void:
	if _is_lookdev_launch():
		_step_flight(delta)


func _cache_nodes() -> void:
	_thermite_core = get_node_or_null("ThermiteCore") as MeshInstance3D
	_beacon_light = get_node_or_null("BeaconLight") as OmniLight3D
	_comet_sparks = get_node_or_null("CometSparks") as GPUParticles3D
	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision != null and _collision.shape is SphereShape3D:
		_hit_shape = _collision.shape as SphereShape3D
	_thermite_material = _duplicate_mesh_material(_thermite_core, _thermite_material)


func _duplicate_mesh_material(
	mesh: MeshInstance3D,
	cached: StandardMaterial3D
) -> StandardMaterial3D:
	if mesh == null or not (mesh.material_override is StandardMaterial3D):
		return cached
	if cached != null and mesh.material_override == cached:
		return cached
	var duplicated := (mesh.material_override as StandardMaterial3D).duplicate()
	mesh.material_override = duplicated
	return duplicated


func _configure_authored_nodes() -> void:
	_configure_beacon_lights()
	_harden_core_material()
	_ensure_unit_core_mesh()
	_apply_core_visual_size()


func _configure_beacon_lights() -> void:
	## CRITICAL: volumetric fog energy must stay 0. Non-zero draws a hard red ball
	## in match volumetric fog (omni_range sphere), even with no glow meshes.
	if _beacon_light != null:
		FireballLightingScript.configure_cast_light(
			_beacon_light,
			light_peak_energy,
			light_range,
			_beacon_light.light_color,
			false,
			0.0
		)
		_beacon_light.light_volumetric_fog_energy = 0.0
		_beacon_light.set_param(Light3D.PARAM_VOLUMETRIC_FOG_ENERGY, 0.0)
		_beacon_light.shadow_enabled = false


func _configure_comet_sparks() -> void:
	## Comet sparks only matter during runtime / launch preview, not static lookdev tuning.
	if Engine.is_editor_hint() and not _runtime:
		return
	if not comet_sparks_enabled:
		if _comet_sparks != null:
			_comet_sparks.emitting = false
			_comet_sparks.visible = false
		return
	if _comet_sparks == null:
		_comet_sparks = FlareParticlesScript.make_comet_sparks(_comet_spark_settings())
		if _comet_sparks == null:
			return
		_comet_sparks.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_comet_sparks)
		if Engine.is_editor_hint():
			var root := get_tree().edited_scene_root
			if root != null:
				_comet_sparks.owner = root
	else:
		FlareParticlesScript.apply_comet_sparks(_comet_sparks, _comet_spark_settings())
	_sync_comet_sparks()


func _comet_spark_settings() -> Dictionary:
	return {
		"amount": comet_spark_amount,
		"lifetime": comet_spark_lifetime,
		"velocity_min": minf(comet_spark_velocity_min, comet_spark_velocity_max),
		"velocity_max": maxf(comet_spark_velocity_min, comet_spark_velocity_max),
		"scale_min": minf(comet_spark_scale_min, comet_spark_scale_max),
		"scale_max": maxf(comet_spark_scale_min, comet_spark_scale_max),
		"color": comet_spark_color,
	}


func _sync_comet_sparks() -> void:
	if _comet_sparks == null or not comet_sparks_enabled:
		return
	var active := _playing and _flying
	var was_active := _comet_sparks.visible and _comet_sparks.emitting
	_comet_sparks.visible = active
	_comet_sparks.emitting = active
	if not active:
		return
	if active and not was_active:
		_comet_sparks.restart()
	var trail_dir := -_direction
	if trail_dir.length_squared() < 0.0001:
		trail_dir = Vector3.DOWN
	else:
		trail_dir = trail_dir.normalized()
	var pmat := _comet_sparks.process_material as ParticleProcessMaterial
	if pmat != null:
		pmat.direction = trail_dir
		pmat.spread = 22.0 if _velocity.length_squared() > 4.0 else 32.0


func _sync_hit_shape() -> void:
	if _collision == null:
		_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision == null:
		return
	var shape := _collision.shape as SphereShape3D
	if shape == null:
		shape = SphereShape3D.new()
		_collision.shape = shape
	shape.radius = hit_radius
	_hit_shape = shape


func _ensure_unit_core_mesh() -> void:
	## Unit sphere — visual size comes only from core_radius via node scale.
	if _thermite_core == null:
		_thermite_core = get_node_or_null("ThermiteCore") as MeshInstance3D
	if _thermite_core == null:
		return
	var sphere := _thermite_core.mesh as SphereMesh
	if sphere == null:
		sphere = SphereMesh.new()
		sphere.radial_segments = 12
		sphere.rings = 6
		_thermite_core.mesh = sphere
	sphere.radius = 1.0
	sphere.height = 2.0


func _apply_core_visual_size() -> void:
	if not is_inside_tree():
		return
	if _thermite_core == null:
		_thermite_core = get_node_or_null("ThermiteCore") as MeshInstance3D
	if _thermite_core == null:
		return
	_thermite_core.scale = Vector3.ONE * _core_display_radius()


func _core_display_radius() -> float:
	## core_radius is the authored visual size; life/pulse only shrinks it over time.
	var life_mul := lerpf(1.0, 0.35, clampf(_life_t, 0.0, 1.0))
	var pulse_mul := lerpf(0.96, 1.02, clampf(_pulse_t, 0.0, 1.0))
	return core_radius * life_mul * pulse_mul


func _harden_core_material() -> void:
	if _thermite_material == null:
		return
	## Opaque emissive point — additive/transparent soft discs read as a glow ball.
	_thermite_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_thermite_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_thermite_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_thermite_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_thermite_material.cull_mode = BaseMaterial3D.CULL_BACK
	_thermite_material.no_depth_test = false
	_thermite_material.albedo_texture = null
	_thermite_material.emission_enabled = true
	_thermite_material.emission = Color(1.0, 0.95, 0.8)
	_thermite_material.albedo_color = Color(1.0, 0.97, 0.88, 1.0)


func _reset_core_visuals() -> void:
	if _thermite_core != null:
		_thermite_core.visible = true
	_apply_core_visual_size()
	if _thermite_material != null:
		_thermite_material.emission_energy_multiplier = 4.0
		_thermite_material.albedo_color = Color(1.0, 0.97, 0.88, 1.0)
	if _beacon_light != null:
		_beacon_light.visible = true
		_beacon_light.omni_range = light_range
		_beacon_light.light_volumetric_fog_energy = 0.0
		_beacon_light.set_param(Light3D.PARAM_VOLUMETRIC_FOG_ENERGY, 0.0)


func _move_and_slide_flight(
	motion: Vector3, delta: float, already_applied_contact_drag: bool
) -> void:
	_sliding_on_contact = false
	if _hit_shape == null or not is_inside_tree():
		global_position += motion
		return
	var space_state := get_world_3d().direct_space_state
	var remaining := motion
	var scraped := false
	for _i in 4:
		if remaining.length_squared() < 0.00000001:
			break
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = _hit_shape
		params.transform = global_transform
		params.motion = remaining
		params.exclude = _exclude_rids()
		params.collision_mask = collision_mask
		var contact := space_state.cast_motion(params)
		var safe_fraction: float = contact[0]
		if safe_fraction >= 1.0:
			global_position += remaining
			break
		global_position += remaining * safe_fraction
		var normal := _contact_normal(space_state, remaining, contact)
		_velocity = FlareFlightScript.slide_on_contact(_velocity, normal)
		if not scraped and not already_applied_contact_drag:
			## First contact this tick: flight step used `drag` only; add contact_drag now.
			_velocity = FlareFlightScript.step_velocity(
				_velocity, delta, contact_drag, 0.0, 0.0
			)
		scraped = true
		remaining = remaining.slide(normal) * (1.0 - safe_fraction)
		if remaining.length_squared() < 0.00000001 or _velocity.length_squared() < 0.0001:
			break
	_sliding_on_contact = scraped


func _contact_normal(
	space_state: PhysicsDirectSpaceState3D,
	motion: Vector3,
	contact: PackedFloat32Array
) -> Vector3:
	var rest := _contact_rest(space_state, motion, contact)
	if rest.is_empty():
		if motion.length_squared() > 0.0001:
			return -motion.normalized()
		return Vector3.UP
	var n: Vector3 = rest.get("normal", Vector3.ZERO)
	if n.length_squared() < 0.0001:
		return Vector3.UP
	return n.normalized()


func _contact_rest(
	space_state: PhysicsDirectSpaceState3D,
	motion: Vector3,
	contact: PackedFloat32Array
) -> Dictionary:
	var unsafe_fraction: float = contact[1] if contact.size() > 1 else contact[0]
	var probe := clampf(lerpf(contact[0], unsafe_fraction, 0.6), 0.0, 1.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	var xf := global_transform
	xf.origin += motion * probe
	params.transform = xf
	params.exclude = _exclude_rids()
	params.collision_mask = collision_mask
	return space_state.get_rest_info(params)


func _exclude_rids() -> Array:
	var rids: Array = [get_rid()]
	if is_instance_valid(_caster) and _caster is CollisionObject3D:
		rids.append((_caster as CollisionObject3D).get_rid())
	return rids


func _on_body_entered(_body: Node3D) -> void:
	## Contacts slide in `_move_and_slide_flight`; Area overlap does not plant the beacon.
	pass


func _start_beacon_pulse() -> void:
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_method(_set_pulse_t, 1.0, 0.55, 0.75)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_method(_set_pulse_t, 0.55, 1.0, 0.75)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_lifespan() -> void:
	var life_sec := maxf(duration_sec, 1.0)
	_life_tween = create_tween()
	_life_tween.tween_method(_set_life_t, 0.0, 1.0, life_sec)\
		.set_trans(Tween.TRANS_LINEAR)
	_life_tween.tween_callback(_on_finished)


func _set_pulse_t(value: float) -> void:
	_pulse_t = value
	_refresh_visual_state()


func _set_life_t(value: float) -> void:
	_life_t = value
	_refresh_visual_state()


func _refresh_visual_state() -> void:
	var envelope: float = pow(1.0 - clampf(_life_t, 0.0, 1.0), 1.25)
	var pulse: float = lerpf(0.82, 1.0, clampf(_pulse_t, 0.0, 1.0))
	var strength: float = envelope * pulse

	_apply_core_visual_size()

	if _thermite_material != null:
		_thermite_material.emission_energy_multiplier = 4.0 * strength
		_thermite_material.albedo_color = Color(1.0, 0.97, 0.88, 1.0)

	if _beacon_light != null:
		_beacon_light.light_energy = light_peak_energy * strength
		_beacon_light.omni_range = lerpf(light_range, light_range * 0.7, _life_t)
		## Re-assert every tick — shared light helpers default fog energy to 6.
		_beacon_light.light_volumetric_fog_energy = 0.0
		_beacon_light.set_param(Light3D.PARAM_VOLUMETRIC_FOG_ENERGY, 0.0)

	_sync_comet_sparks()


func _on_finished() -> void:
	_playing = false
	_flying = false
	_stop_tweens()
	if _runtime:
		NetLivenessScript.despawn_or_free(self)


func _stop_tweens() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if _life_tween != null and _life_tween.is_valid():
		_life_tween.kill()
	_life_tween = null
