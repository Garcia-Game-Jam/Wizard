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
const NetDisplayCommitScript := preload("res://scripts/net/net_display_commit.gd")

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
## Damage + knock radius around the impact point — this, not hit_radius, is what
## actually has to reach a target. Kept well below Fireball's so it still reads as a
## targeted throw rather than an AoE burst.
@export_range(0.25, 4.0, 0.05) var splash_radius: float = 1.0
@export var payload: CombatPayload

var _direction := Vector3.FORWARD
var _caster: Node3D
var _elapsed := 0.0
var _hit_shape: SphereShape3D
var _collision: CollisionShape3D
var _mesh: MeshInstance3D
var _finished := false
## Catch-up from NetworkWeapon must not spend the payload — rollback will.
var _combat_enabled := true
var _fx_committed := false
var _impact_fx_parent: Node = null
var _impact_fx_pos := Vector3.ZERO


static func spawn(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	caster: Node3D = null,
	lookdev_flight: bool = false
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
	NetDisplayCommitScript.bind(_commit_impact_fx)
	if Engine.is_editor_hint() and not _is_lookdev_flight():
		set_physics_process(false)
		return

	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	set_physics_process(true)
	set_process(true)


func _exit_tree() -> void:
	NetDisplayCommitScript.unbind(_commit_impact_fx)


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


func apply_net_launch(origin: Vector3, direction: Vector3, _charge_factor: float = 1.0) -> void:
	global_position = origin
	if direction.length_squared() > 0.0001:
		_direction = direction.normalized()


func _simulate_flight(delta: float) -> void:
	if _finished or not is_inside_tree():
		return
	_elapsed += delta
	if _elapsed >= MAX_LIFETIME_SEC:
		## Fizzled mid-air — no target was ever close enough to warrant a splash.
		_finish(false)
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
		_finish(false)
		return
	var combat := _overlapping_combat_body()
	if combat != null:
		_finish(true, combat)
		return
	if stop_fraction < 1.0:
		## Hit solid geometry — still splash in case a target is standing right there.
		_finish(true)


func _exclude_rids() -> Array:
	var rids: Array = [get_rid()]
	if is_instance_valid(_caster) and _caster is CollisionObject3D:
		rids.append((_caster as CollisionObject3D).get_rid())
	return rids


## Precise early-out only — decides when the stone stops flying. Actual damage
## and knock come from the splash-radius group scan in _apply_splash_at(),
## which is forgiving of the flight sphere never quite reaching the target's shape.
func _overlapping_combat_body() -> Node3D:
	if not is_inside_tree() or _hit_shape == null:
		return null
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	params.transform = global_transform
	params.exclude = _exclude_rids()
	params.collision_mask = collision_mask
	for hit in space_state.intersect_shape(params, 8):
		var collider: Variant = hit.get("collider")
		if collider is Node3D and _is_combat_body(collider as Node3D):
			return collider as Node3D
	return null


func _is_combat_body(body: Node3D) -> bool:
	if body == null or body == _caster:
		return false
	if not Character.is_node_alive(body):
		return false
	return (
		body.is_in_group("player")
		or body.is_in_group("monster")
		or body.is_in_group("combat_target")
	)


func _finish(apply_splash: bool, hit: Node = null) -> void:
	if _finished or not is_inside_tree():
		return
	_finished = true
	_impact_fx_parent = get_parent()
	_impact_fx_pos = global_position
	if apply_splash and _combat_enabled:
		_apply_splash_at(_impact_fx_pos, hit)
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
	StoneImpactEffectScript.spawn(parent, _impact_fx_pos)


func _apply_splash_at(impact_pos: Vector3, hit: Node = null) -> void:
	if splash_radius <= 0.0:
		return
	CombatSplash.apply_at(
		get_tree(), impact_pos, splash_radius, self, _ensure_payload(), _caster, hit
	)


func _ensure_payload() -> CombatPayload:
	if payload != null:
		return payload
	payload = CombatPayload.new()
	payload.effects.append(Damage.with(hit_damage))
	var knock := Knock.new()
	knock.from_impact = true
	knock.impulse = Vector3(Character.KNOCKBACK_HORIZONTAL, Character.KNOCKBACK_UP, 0.0)
	payload.effects.append(knock)
	return payload


func _clear_projectile_visuals() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.visible = false
	visible = false
	set_process(false)
