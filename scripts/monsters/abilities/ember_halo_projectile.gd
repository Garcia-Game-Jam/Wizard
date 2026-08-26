@tool
class_name EmberHaloProjectile
extends Area3D

## Flat expanding ring toward the player. Rim = knockback + slow; center = jump pad.

const EmberHaloFlightScript := preload("res://scripts/monsters/abilities/ember_halo_flight.gd")
const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")
const MonsterSpellHitScript := preload("res://scripts/combat/monster_spell_hit.gd")
const MAX_LIFE_SEC := 3.5

@export var travel_speed: float = EmberHaloFlightScript.TRAVEL_SPEED
@export var start_radius: float = EmberHaloFlightScript.START_RADIUS
@export var max_radius: float = EmberHaloFlightScript.MAX_RADIUS
@export var expand_per_meter: float = EmberHaloFlightScript.EXPAND_PER_METER

var _caster: Node3D = null
var _direction: Vector3 = Vector3.FORWARD
var _distance: float = 0.0
var _radius: float = EmberHaloFlightScript.START_RADIUS
var _age: float = 0.0
var _finished: bool = false
var _ring_hit_bodies: Dictionary = {}
var _jump_pad_bodies: Dictionary = {}
var _mesh: MeshInstance3D = null
var _shape: CollisionShape3D = null
var _cyl_shape: CylinderShape3D = null


static func spawn(
	parent: Node,
	origin: Vector3,
	toward: Vector3,
	caster: Node3D = null
) -> EmberHaloProjectile:
	var packed: PackedScene = load(
		"res://scenes/monsters/abilities/ember_halo_projectile.tscn"
	) as PackedScene
	var proj: EmberHaloProjectile = packed.instantiate() as EmberHaloProjectile
	parent.add_child(proj)
	proj.process_mode = Node.PROCESS_MODE_ALWAYS
	proj.global_position = Vector3(origin.x, origin.y, origin.z)
	proj.setup(toward, caster)
	return proj


func setup(toward: Vector3, caster: Node3D = null) -> void:
	_caster = caster
	_direction = EmberHaloFlightScript.flat_direction(global_position, toward)
	## Keep the ring gliding parallel to the ground at a stable height.
	if caster != null:
		global_position.y = caster.global_position.y + 0.12
	_radius = start_radius
	monitoring = true
	monitorable = false
	MonsterSpellHitScript.apply_mask(self)

	_shape = CollisionShape3D.new()
	_cyl_shape = CylinderShape3D.new()
	_cyl_shape.height = 2.5
	_cyl_shape.radius = _radius
	_shape.shape = _cyl_shape
	add_child(_shape)

	_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = EmberHaloFlightScript.inner_radius(_radius)
	torus.outer_radius = _radius
	torus.rings = 16
	torus.ring_segments = 24
	_mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.2, 0.08, 0.75)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.1)
	mat.emission_energy_multiplier = 3.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## TorusMesh is authored around +Y, so it already lies flat on the XZ ground plane.
	_mesh.rotation_degrees = Vector3.ZERO
	add_child(_mesh)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.1)
	light.light_energy = 2.2
	light.omni_range = 2.5
	light.shadow_enabled = false
	add_child(light)

	set_physics_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_physics_process(delta)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	if _caster != null and not is_instance_valid(_caster):
		_caster = null
	_age += delta
	if _age >= MAX_LIFE_SEC:
		_finish()
		return
	var step := travel_speed * delta
	var next := global_position + _direction * step
	next.y = global_position.y
	global_position = next
	_distance += step
	_radius = EmberHaloFlightScript.radius_at_distance(
		_distance, start_radius, max_radius, expand_per_meter
	)
	_sync_radius_visual()
	_resolve_overlaps()


func _sync_radius_visual() -> void:
	if _cyl_shape != null:
		_cyl_shape.radius = _radius
	if _mesh != null and _mesh.mesh is TorusMesh:
		var torus := _mesh.mesh as TorusMesh
		torus.outer_radius = _radius
		torus.inner_radius = EmberHaloFlightScript.inner_radius(_radius)
		_mesh.scale.y = 1


func _resolve_overlaps() -> void:
	if _finished:
		return
	for body in get_overlapping_bodies():
		if not body is Node3D:
			continue
		var hit := body as Node3D
		var kind := MonsterSpellHitScript.kind(hit, _caster)
		if kind == MonsterSpellHitScript.Kind.WARD:
			if _block_if_ward(hit):
				return
			continue
		if kind == MonsterSpellHitScript.Kind.WALL:
			_finish()
			return
		if kind != MonsterSpellHitScript.Kind.COMBAT:
			continue
		var flat_dist := EmberHaloFlightScript.flat_distance(global_position, hit.global_position)
		var id := hit.get_instance_id()
		if EmberHaloFlightScript.is_in_center(flat_dist, _radius):
			if _jump_pad_bodies.has(id):
				continue
			_jump_pad_bodies[id] = true
			_apply_jump_pad(hit)
		elif EmberHaloFlightScript.is_in_ring(flat_dist, _radius):
			if _ring_hit_bodies.has(id):
				continue
			_ring_hit_bodies[id] = true
			_apply_ring_hit(hit)


func _should_apply_local(body: Node) -> bool:
	var state := get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
	var mp := state != null and bool(state.get("is_multiplayer"))
	if mp and body is Node:
		return (body as Node).is_multiplayer_authority()
	return true


func _apply_jump_pad(body: Node3D) -> void:
	if not _should_apply_local(body):
		return
	if body.has_method("apply_ember_halo_jump_pad"):
		body.call("apply_ember_halo_jump_pad")
	elif body.has_method("apply_ember_halo_hit"):
		## Fallback for stubs without jump-pad hook.
		body.call("apply_ember_halo_hit", Vector3.ZERO)


func _apply_ring_hit(body: Node3D) -> void:
	if not _should_apply_local(body):
		return
	if body.has_method("apply_ember_halo_hit"):
		body.call("apply_ember_halo_hit", _direction)
	elif body.has_method("apply_fireball_knockback"):
		body.call("apply_fireball_knockback", _direction * 0.35)
		if body.has_method("apply_speed_boost"):
			body.call(
				"apply_speed_boost",
				EmberHaloFlightScript.SLOW_DURATION_SEC,
				EmberHaloFlightScript.SLOW_MULTIPLIER
			)


func _block_if_ward(body: Node) -> bool:
	if not SpellWardBlockScript.try_block(body, 0.0, _caster):
		return false
	_finish()
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	queue_free()
