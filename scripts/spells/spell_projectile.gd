@tool
class_name SpellProjectile
extends Area3D

## Physics-frame flight. World sweep stops travel; pawn hits are the hit sphere
## vs authored capsules at node poses. Motion and impact_fx are authored.

const HIT_RADIUS_FLOOR := 0.16
## ponytail: O(bodies in groups) per flight step; upgrade if dump size makes it hot.
const _HIT_GROUPS: PackedStringArray = ["player", "monster", "combat_target", "corpse"]

const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")

@export_group("Flight")
@export_range(0.0, 120.0, 0.5) var speed: float = 28.0
## Along current velocity: 0 coast, negative drag, positive rocket.
@export_range(-40.0, 40.0, 0.1) var acceleration: float = 0.0
## World drop m/s². Named flight_gravity because Area3D already has gravity.
@export_range(0.0, 80.0, 0.1) var flight_gravity: float = 0.0
@export_range(0.1, 12.0, 0.05) var lifetime: float = 2.5

@export_group("Combat")
@export_range(0.16, 1.5, 0.01) var hit_radius: float = HIT_RADIUS_FLOOR:
	set(value):
		hit_radius = maxf(value, HIT_RADIUS_FLOOR)
		_sync_hit_shape()
@export_range(0.0, 200.0, 1.0) var hit_damage: float = 20.0
@export var payload: CombatPayload
## Spawned at the connect point. Empty = hide mesh only.
@export var impact_fx: PackedScene

var _velocity := Vector3.ZERO
var _direction := Vector3.FORWARD
var _caster: Node3D
var _elapsed := 0.0
var _hit_shape: SphereShape3D
var _collision: CollisionShape3D
var _finished := false


func setup_launch(
	origin: Vector3,
	direction: Vector3,
	caster: Node3D = null,
	_charge_factor: float = 1.0
) -> void:
	global_position = origin
	if direction.length_squared() > 0.0001:
		_direction = direction.normalized()
	else:
		_direction = Vector3.FORWARD
	_velocity = _direction * speed
	_caster = caster
	_elapsed = 0.0
	_finished = false


func apply_net_launch(origin: Vector3, direction: Vector3, charge_factor: float = 1.0) -> void:
	setup_launch(origin, direction, _caster, charge_factor)


func simulate_from_tick(fired_tick: int) -> void:
	if not NetClockScript.is_ticking():
		return
	var tree := get_tree()
	if tree == null:
		return
	var time_node := tree.root.get_node_or_null("NetworkTime")
	if time_node == null:
		return
	var now := int(time_node.get("tick"))
	var tick_time := float(time_node.get("ticktime"))
	for _tick in range(fired_tick, now):
		if _finished:
			break
		_simulate_flight(tick_time)


func _ready() -> void:
	_cache_nodes()
	_sync_hit_shape()
	if Engine.is_editor_hint() and not _is_lookdev_flight():
		set_physics_process(false)
		return
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = CollisionLayersScript.WORLD
	if _velocity.length_squared() < 0.0001:
		_velocity = _direction * speed
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _finished or not is_inside_tree():
		return
	if Engine.is_editor_hint() and not _is_lookdev_flight():
		return
	_simulate_flight(delta)


func _simulate_flight(delta: float) -> void:
	if _finished or not is_inside_tree():
		return
	_elapsed += delta
	if _elapsed >= lifetime:
		_finish(false)
		return
	_integrate_velocity(delta)
	_advance_and_connect(delta)


func _integrate_velocity(delta: float) -> void:
	if acceleration != 0.0 and _velocity.length_squared() > 0.0001:
		_velocity += _velocity.normalized() * acceleration * delta
	if flight_gravity != 0.0:
		_velocity.y -= flight_gravity * delta


## Move one step, then connect. True if this step finished the flyer.
func _advance_and_connect(delta: float) -> bool:
	var prev := global_position
	var motion: Vector3 = _velocity * delta
	var stop_fraction := _cast_motion_fraction(motion)
	global_position += motion * stop_fraction
	if SpellWardBlockScript.try_block_along_path(
		get_tree(), prev, global_position, hit_radius, hit_damage, _caster
	):
		_finish(false)
		return true
	var hits := _overlapping_combat(prev, global_position)
	if not hits.is_empty() or stop_fraction < 1.0:
		_finish(true, hits)
		return true
	return false


func _cast_motion_fraction(motion: Vector3) -> float:
	if not is_inside_tree() or _hit_shape == null or motion.length_squared() < 0.0000001:
		return 1.0
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return 1.0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	params.transform = global_transform
	params.motion = motion
	params.exclude = _exclude_rids()
	params.collision_mask = CollisionLayersScript.WORLD
	var contact := space_state.cast_motion(params)
	if contact.is_empty():
		return 1.0
	return float(contact[0])


func _overlapping_combat(from: Vector3, to: Vector3) -> Array:
	var found: Array = []
	var tree := get_tree()
	if tree == null:
		return found
	var seen: Dictionary = {}
	for group_name in _HIT_GROUPS:
		for node in tree.get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node) or node == _caster:
				continue
			if seen.has(node) or not (node is Node3D):
				continue
			if not _is_hittable(node):
				continue
			var body := node as Node3D
			if not _swept_sphere_hits_body(from, to, hit_radius, body):
				continue
			seen[node] = true
			found.append(body)
	return found


func _is_hittable(node: Node) -> bool:
	if node is Corpse:
		return true
	if Character.is_node_alive(node):
		return true
	return node.is_in_group(Character.CORPSE_GROUP)


func _swept_sphere_hits_body(
	from: Vector3, to: Vector3, radius: float, body: Node3D
) -> bool:
	var col := _body_hit_shape(body)
	if col == null or col.shape == null or col.disabled:
		return false
	var shape := col.shape
	var xf := col.global_transform
	if shape is SphereShape3D:
		return _segment_hits_sphere(from, to, xf.origin, radius + (shape as SphereShape3D).radius)
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var half := maxf(cap.height * 0.5 - cap.radius, 0.0)
		var axis: Vector3 = xf.basis.y.normalized() * half
		return _segments_closer_than(from, to, xf.origin - axis, xf.origin + axis, radius + cap.radius)
	if shape is BoxShape3D:
		var extents: Vector3 = (shape as BoxShape3D).size * 0.5
		return (
			_point_hits_box(from, radius, xf, extents)
			or _point_hits_box(to, radius, xf, extents)
		)
	return false


func _body_hit_shape(body: Node3D) -> CollisionShape3D:
	var named := body.get_node_or_null("%CollisionShape3D") as CollisionShape3D
	if named != null:
		return named
	for child in body.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


func _segment_hits_sphere(from: Vector3, to: Vector3, center: Vector3, reach: float) -> bool:
	if from.distance_squared_to(to) < 0.0000001:
		return from.distance_squared_to(center) <= reach * reach
	var closest := Geometry3D.get_closest_point_to_segment(center, from, to)
	return closest.distance_squared_to(center) <= reach * reach


func _segments_closer_than(
	a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, reach: float
) -> bool:
	var points := Geometry3D.get_closest_points_between_segments(a0, a1, b0, b1)
	if points.size() < 2:
		return a0.distance_squared_to(b0) <= reach * reach
	return points[0].distance_squared_to(points[1]) <= reach * reach


func _point_hits_box(
	point: Vector3, radius: float, xf: Transform3D, extents: Vector3
) -> bool:
	var local: Vector3 = xf.affine_inverse() * point
	var closest := local.clamp(-extents, extents)
	return local.distance_squared_to(closest) <= radius * radius


func _finish(spawn_fx: bool, hits: Variant = null) -> void:
	if _finished or not is_inside_tree():
		return
	_finished = true
	var impact_pos := global_position
	var world_parent := get_parent()
	if spawn_fx:
		var resolved: Array = hits if hits is Array else _overlapping_combat(impact_pos, impact_pos)
		_apply_hits(resolved, impact_pos)
		_spawn_impact_fx(world_parent, impact_pos)
	_clear_projectile_visuals()
	queue_free()


func _apply_hits(hits: Array, impact_pos: Vector3) -> void:
	if not monitoring:
		return
	var spent := _ensure_payload()
	for node in hits:
		_apply_to(node as Node, impact_pos, spent)


func _apply_to(body: Node, impact_pos: Vector3, spent: CombatPayload) -> void:
	if body == null or not is_instance_valid(body) or body == _caster:
		return
	if body is Corpse:
		_apply_knock_only(body as Node3D, impact_pos, spent)
		return
	if not (body is Character):
		return
	if Character.is_node_alive(body):
		var character := body as Character
		character._apply_or_queue_rewind(
			_caster, _aim_knock(spent, impact_pos, character.global_position)
		)
		return
	if body.is_in_group(Character.CORPSE_GROUP):
		_apply_knock_only(body as Node3D, impact_pos, spent)


func _apply_knock_only(body: Node3D, impact_pos: Vector3, spent: CombatPayload) -> void:
	var aimed := _aim_knock(spent, impact_pos, body.global_position)
	for effect in aimed.effects:
		if not (effect is Knock):
			continue
		var impulse := (effect as Knock).impulse
		if body is Corpse:
			(body as Corpse).apply_hit_knock(impulse)
		elif body is Character:
			(body as Character).apply_knockback(impulse, impulse)


func _aim_knock(spent: CombatPayload, origin: Vector3, body_pos: Vector3) -> CombatPayload:
	var needs := false
	for effect in spent.effects:
		if effect is Knock and (effect as Knock).from_impact:
			needs = true
			break
	if not needs:
		return spent
	var copy := spent.duplicate(true) as CombatPayload
	if copy == null:
		return spent
	var dir := body_pos - origin
	for effect in copy.effects:
		if not (effect is Knock):
			continue
		var knock := effect as Knock
		if not knock.from_impact:
			continue
		var horizontal := knock.impulse.x if absf(knock.impulse.x) > 0.0001 else 9.0
		var up := knock.impulse.y if absf(knock.impulse.y) > 0.0001 else 3.5
		knock.impulse = Knock.impulse_from_dir(dir, horizontal, up)
		knock.from_impact = false
	return copy


func _spawn_impact_fx(parent: Node, impact_pos: Vector3) -> void:
	if impact_fx == null or parent == null:
		return
	var fx := impact_fx.instantiate()
	if fx is Node3D:
		SpellEphemeralFxScript.add_child_at(parent, fx as Node3D, impact_pos)
	else:
		parent.add_child(fx)


func _ensure_payload() -> CombatPayload:
	if payload != null:
		return payload
	payload = CombatPayload.new()
	payload.effects.append(Damage.with(hit_damage))
	return payload


func _clear_projectile_visuals() -> void:
	visible = false
	set_physics_process(false)
	set_process(false)


func _exclude_rids() -> Array:
	var rids: Array = [get_rid()]
	if is_instance_valid(_caster) and _caster is CollisionObject3D:
		rids.append((_caster as CollisionObject3D).get_rid())
	return rids


func _cache_nodes() -> void:
	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision == null:
		_collision = get_node_or_null("%HitShape") as CollisionShape3D
	if _collision == null:
		for child in get_children():
			if child is CollisionShape3D:
				_collision = child as CollisionShape3D
				break
	if _collision != null and _collision.shape is SphereShape3D:
		_hit_shape = _collision.shape as SphereShape3D


func _sync_hit_shape() -> void:
	if _collision == null:
		_cache_nodes()
	if _collision == null:
		return
	var shape := _collision.shape as SphereShape3D
	if shape == null:
		shape = SphereShape3D.new()
		_collision.shape = shape
	shape.radius = hit_radius
	_hit_shape = shape


func _is_lookdev_flight() -> bool:
	return bool(get_meta("lookdev_flight", false))
