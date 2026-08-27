@tool
class_name EmberHaloProjectile
extends Area3D

## Flat expanding ring toward the player. Rim = knockback + slow; center = jump pad.

const EmberHaloFlightScript := preload("res://scripts/monsters/abilities/ember_halo_flight.gd")
const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")
const MonsterSpellHitScript := preload("res://scripts/combat/monster_spell_hit.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")
const SCENE := preload("res://scenes/monsters/abilities/ember_halo_projectile.tscn")
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
	caster: Node3D = null,
	visual_only: bool = false
) -> EmberHaloProjectile:
	if parent == null:
		return null
	var proj: EmberHaloProjectile = SCENE.instantiate() as EmberHaloProjectile
	parent.add_child(proj)
	proj.process_mode = Node.PROCESS_MODE_ALWAYS
	proj.global_position = Vector3(origin.x, origin.y, origin.z)
	proj.setup(toward, caster)
	if visual_only:
		proj.monitoring = false
		proj.monitorable = false
	else:
		var extra := {"toward_x": toward.x, "toward_y": toward.y, "toward_z": toward.z}
		NetLivenessScript.replicate_world_fx("ember_halo", proj.global_position, extra)
	NetLivenessScript.after_spawn(proj)
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
	_shape = get_node_or_null("%HitShape") as CollisionShape3D
	if _shape != null and _shape.shape is CylinderShape3D:
		_cyl_shape = (_shape.shape as CylinderShape3D).duplicate() as CylinderShape3D
		_cyl_shape.height = 2.5
		_cyl_shape.radius = _radius
		_shape.shape = _cyl_shape
	_mesh = get_node_or_null("%Mesh") as MeshInstance3D
	if _mesh != null and _mesh.mesh is TorusMesh:
		_mesh.mesh = (_mesh.mesh as TorusMesh).duplicate()
	_sync_radius_visual()
	set_physics_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_physics_process(delta)


func _physics_process(delta: float) -> void:
	if NetLivenessScript.skip_engine_physics():
		return
	_tick_motion(delta)


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	_tick_motion(delta)


func _rollback_spawn() -> void:
	NetLivenessScript.activate(self)


func _rollback_despawn() -> void:
	NetLivenessScript.deactivate(self)


func _tick_motion(delta: float) -> void:
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
	if _finished or not NetLivenessScript.can_query_overlaps(self):
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
	NetLivenessScript.despawn_or_free(self)
