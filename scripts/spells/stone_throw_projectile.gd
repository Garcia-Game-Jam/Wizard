@tool
class_name StoneThrowProjectile
extends Area3D

## Forward-thrown rock that knocks back whatever it lands near.
## Open scenes/spells/stone_throw/stone_throw.tscn to tune look.
## Simpler cousin of FireballProjectile: no charge-power scaling — require_full_charge
## on the spell means charge_factor is always ~1.0 by the time this fires, so it is
## accepted (for apply_net_launch parity) but unused.
## Impact still uses a splash-radius group scan like Fireball, just a tighter one —
## a creature's collision capsule sits well above its root position (feet-to-head),
## so a precise-only hit sphere routinely flies straight through a target that is
## clearly in the way. The scan (by group + distance, not shape overlap) is what
## actually connects the hit; the flight sphere only decides when to stop flying.

const SPEED := 24.0
const DEFAULT_HIT_DAMAGE := 15.0
const DEFAULT_CHARGE_TIME_SEC := 0.7
const MAX_LIFETIME_SEC := 2.0
const SPIN_SPEED_X := 9.0
const SPIN_SPEED_Z := 5.4

const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")
const StoneImpactEffectScript := preload("res://scripts/spells/stone_impact_effect.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")

@export_group("Cast timing")
## Hold time until the stone is ready to throw.
@export_range(0.05, 5.0, 0.05) var charge_time_sec: float = DEFAULT_CHARGE_TIME_SEC:
	set(value):
		charge_time_sec = maxf(value, 0.05)

@export_group("Combat")
@export_range(0.05, 1.0, 0.01) var hit_radius: float = 0.2:
	set(value):
		hit_radius = maxf(value, 0.02)
		_sync_shape()

@export_range(0.0, 200.0, 1.0) var hit_damage: float = DEFAULT_HIT_DAMAGE
## Damage + knockback radius around the impact point — this, not hit_radius, is what
## actually has to reach a target. Kept well below Fireball's so it still reads as a
## targeted throw rather than an AoE burst.
@export_range(0.25, 4.0, 0.05) var splash_radius: float = 1.0

var _direction := Vector3.FORWARD
var _caster: Node3D
var _elapsed := 0.0
var _hit_shape: SphereShape3D
var _collision: CollisionShape3D
var _mesh: MeshInstance3D
var _finished := false


static func spawn(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	caster: Node3D = null,
	lookdev_flight: bool = false,
	charge_factor: float = 1.0
) -> Node:
	## Lazy-load avoids circular preload with stone_throw.tscn.
	var packed: PackedScene = load(
		"res://scenes/spells/stone_throw/stone_throw.tscn"
	) as PackedScene
	var projectile: Node = packed.instantiate()
	if lookdev_flight:
		projectile.set_meta("lookdev_flight", true)
		projectile.process_mode = Node.PROCESS_MODE_ALWAYS
	if projectile is StoneThrowProjectile:
		var stone := projectile as StoneThrowProjectile
		stone._direction = direction.normalized()
		stone._caster = caster
	## charge_factor accepted for spawn()/apply_net_launch() signature parity, unused —
	## require_full_charge means this only ever fires near-fully charged.
	## Place before add_child so `_ready` is not at Match origin.
	if parent != null and projectile is Node3D:
		SpellEphemeralFxScript.add_child_at(parent, projectile as Node3D, origin)
	elif parent != null:
		parent.add_child(projectile)
	if projectile is Node3D:
		NetLivenessScript.after_spawn(projectile as Node3D)
	return projectile


static func authored_charge_time_sec() -> float:
	return _authored_float("charge_time_sec", DEFAULT_CHARGE_TIME_SEC, 0.05)


static func _authored_float(property_name: String, fallback: float, min_value: float) -> float:
	var packed: PackedScene = load(SpellDefinition.world_scene_path("stone_throw")) as PackedScene
	if packed == null:
		return maxf(fallback, min_value)
	var state := packed.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == property_name:
			return maxf(float(state.get_node_property_value(0, i)), min_value)
	return maxf(fallback, min_value)


func _is_lookdev_flight() -> bool:
	return bool(get_meta("lookdev_flight", false))


func _ready() -> void:
	_cache_nodes()
	_sync_shape()
	if Engine.is_editor_hint() and not _is_lookdev_flight():
		set_physics_process(false)
		return

	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	set_physics_process(true)
	set_process(true)


func _cache_nodes() -> void:
	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	if _collision != null and _collision.shape is SphereShape3D:
		_hit_shape = _collision.shape as SphereShape3D


func _sync_shape() -> void:
	if _collision == null:
		_cache_nodes()
	if _collision != null:
		var shape := _collision.shape as SphereShape3D
		if shape == null:
			shape = SphereShape3D.new()
			_collision.shape = shape
		shape.radius = hit_radius
		_hit_shape = shape


## Tumble while flying — a thrown rock, not a smooth-gliding orb.
func _process(delta: float) -> void:
	if _finished or _mesh == null:
		return
	_mesh.rotate_x(SPIN_SPEED_X * delta)
	_mesh.rotate_z(SPIN_SPEED_Z * delta)


func _physics_process(delta: float) -> void:
	if _finished or not is_inside_tree():
		return
	if Engine.is_editor_hint() and not _is_lookdev_flight():
		return
	if NetLivenessScript.skip_engine_physics():
		return
	_simulate_flight(delta, true)


func _rollback_tick(delta: float, _tick: int, is_fresh: bool) -> void:
	_simulate_flight(delta, is_fresh)


func _rollback_spawn() -> void:
	_finished = false
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
	for t in range(fired_tick, now):
		if _finished:
			break
		_simulate_flight(tick_time, t == now - 1)


func apply_net_launch(origin: Vector3, direction: Vector3, _charge_factor: float = 1.0) -> void:
	global_position = origin
	if direction.length_squared() > 0.0001:
		_direction = direction.normalized()


func _simulate_flight(delta: float, is_fresh: bool) -> void:
	if _finished or not is_inside_tree():
		return
	_elapsed += delta
	if _elapsed >= MAX_LIFETIME_SEC:
		## Fizzled mid-air — no target was ever close enough to warrant a splash.
		_finish(false, is_fresh)
		return

	var prev_pos := global_position
	var motion: Vector3 = _direction * SPEED * delta
	var stop_fraction := 1.0
	if _hit_shape != null:
		var space_state := get_world_3d().direct_space_state
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = _hit_shape
		params.transform = global_transform
		params.motion = motion
		params.exclude = _exclude_rids()
		params.collision_mask = collision_mask
		var contact := space_state.cast_motion(params)
		stop_fraction = float(contact[0])
	global_position += motion * stop_fraction

	if SpellWardBlockScript.try_block_along_path(
		get_tree(), prev_pos, global_position, hit_radius, hit_damage, _caster
	):
		_finish(false, is_fresh)
		return
	if _overlaps_combat_body():
		_finish(true, is_fresh)
		return
	if stop_fraction < 1.0:
		## Hit solid geometry — still splash in case a target is standing right there.
		_finish(true, is_fresh)


func _exclude_rids() -> Array:
	var rids: Array = [get_rid()]
	if is_instance_valid(_caster) and _caster is CollisionObject3D:
		rids.append((_caster as CollisionObject3D).get_rid())
	return rids


## Precise early-out only — decides when the stone stops flying. Actual damage/
## knockback comes from the splash-radius group scan in _apply_splash_at(),
## which is forgiving of the flight sphere never quite reaching the target's shape.
func _overlaps_combat_body() -> bool:
	if not is_inside_tree() or _hit_shape == null:
		return false
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	params.transform = global_transform
	params.exclude = _exclude_rids()
	params.collision_mask = collision_mask
	for hit in space_state.intersect_shape(params, 8):
		var collider: Variant = hit.get("collider")
		if collider is Node3D and _is_combat_body(collider as Node3D):
			return true
	return false


func _is_combat_body(body: Node3D) -> bool:
	if body == null or body == _caster:
		return false
	return (
		body.is_in_group("player")
		or body.is_in_group("monster")
		or body.is_in_group("combat_target")
	)


func _finish(apply_splash: bool, is_fresh: bool) -> void:
	if _finished or not is_inside_tree():
		return
	_finished = true
	var world_parent := get_parent()
	var impact_pos := global_position
	if apply_splash:
		_apply_splash_at(impact_pos)
	_clear_projectile_visuals()
	if is_fresh:
		StoneImpactEffectScript.spawn(world_parent, impact_pos)
	NetLivenessScript.despawn_or_free(self)


func _apply_splash_at(impact_pos: Vector3) -> void:
	if hit_damage <= 0.0 or splash_radius <= 0.0:
		return
	var tree := get_tree()
	if tree == null:
		return
	var radius_sq := splash_radius * splash_radius
	var seen: Dictionary = {}
	for group_name in ["monster", "combat_target", "player"]:
		for node in tree.get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node) or node == _caster:
				continue
			if seen.has(node):
				continue
			if not (node is Node3D):
				continue
			var body := node as Node3D
			if body.global_position.distance_squared_to(impact_pos) > radius_sq:
				continue
			seen[node] = true
			_apply_hit_to_body(body, impact_pos)


## Same knockback contract every projectile in this codebase uses — reuse the
## method name so Character's shared reaction handles it, do not invent a new one.
func _apply_hit_to_body(body: Node3D, impact_pos: Vector3) -> void:
	var dir := body.global_position - impact_pos
	if dir.length_squared() < 0.0001:
		dir = _direction
	else:
		dir = dir.normalized()
	if body.has_method("apply_fireball_knockback"):
		var apply_local := not _is_multiplayer_match()
		if body is Node:
			apply_local = apply_local or (body as Node).is_multiplayer_authority()
		if apply_local:
			body.call("apply_fireball_knockback", dir)
	if hit_damage > 0.0:
		Character.apply_hit(body, hit_damage, self)


func _clear_projectile_visuals() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.visible = false
	visible = false
	set_process(false)


func _is_multiplayer_match() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var state := tree.root.get_node_or_null("GameState")
	return state != null and bool(state.get("is_multiplayer"))
