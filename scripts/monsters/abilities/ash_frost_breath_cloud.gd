@tool
class_name AshFrostBreathCloud
extends Area3D

## Geometric frost cloud projectile — grows while traveling toward the player.

const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)
const CloudMeshBuilderScript := preload("res://scripts/environment/cloud_mesh_builder.gd")
const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")
const PlayerFrostBreathScript := preload("res://scripts/characters/player_frost_breath.gd")
const MonsterSpellHitScript := preload("res://scripts/combat/monster_spell_hit.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")

@export_range(0.0, 200.0, 1.0) var hit_damage: float = AshFrostBreathFlightScript.HIT_DAMAGE

var _caster: Node3D = null
var _direction: Vector3 = Vector3.FORWARD
var _age: float = 0.0
var _traveled: float = 0.0
var _finished: bool = false
var _hit_bodies: Dictionary = {}
var _mesh: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _sphere: SphereShape3D = null
var _max_radius: float = AshFrostBreathFlightScript.MAX_RADIUS
var _grow_sec: float = AshFrostBreathFlightScript.GROW_SEC
var _linger_sec: float = AshFrostBreathFlightScript.LINGER_SEC
var _max_travel_sec: float = AshFrostBreathFlightScript.MAX_TRAVEL_SEC


static func spawn(
	parent: Node,
	origin: Vector3,
	toward: Vector3,
	caster: Node3D = null
) -> AshFrostBreathCloud:
	var packed: PackedScene = load(
		"res://scenes/monsters/abilities/ash_frost_breath_cloud.tscn"
	) as PackedScene
	var cloud: AshFrostBreathCloud = packed.instantiate() as AshFrostBreathCloud
	parent.add_child(cloud)
	cloud.process_mode = Node.PROCESS_MODE_ALWAYS
	cloud.setup(origin, toward, caster)
	NetLivenessScript.after_spawn(cloud)
	return cloud


func setup(origin: Vector3, toward: Vector3, caster: Node3D = null) -> void:
	_caster = caster
	_direction = AshFrostBreathFlightScript.travel_direction(origin, toward)
	global_position = origin
	monitoring = true
	monitorable = false
	MonsterSpellHitScript.apply_mask(self)

	var shape_node := CollisionShape3D.new()
	_sphere = SphereShape3D.new()
	_sphere.radius = 0.05
	shape_node.shape = _sphere
	add_child(shape_node)

	_mesh = MeshInstance3D.new()
	var mesh_seed := randi()
	_mesh.mesh = CloudMeshBuilderScript.build_combat(mesh_seed, _max_radius)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.82, 0.9, 0.98, 0.62)
	_mat.emission_enabled = true
	_mat.emission = Color(0.55, 0.78, 1.0)
	_mat.emission_energy_multiplier = 2.8
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.scale = Vector3.ONE * 0.12
	add_child(_mesh)

	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.75, 1.0)
	light.light_energy = 2.4
	light.omni_range = 3.0
	light.shadow_enabled = false
	add_child(light)

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
	var grow_end := _grow_sec
	var min_life := AshFrostBreathFlightScript.total_life_sec(_grow_sec, _linger_sec)
	var life := maxf(_max_travel_sec, min_life)
	if _age >= life:
		_finish()
		return

	var step := AshFrostBreathFlightScript.travel_step(_traveled, delta)
	if step > 0.0:
		global_position += _direction * step
		_traveled += step

	var radius := AshFrostBreathFlightScript.radius_at_age(_age, _grow_sec, _max_radius)
	if _sphere != null:
		_sphere.radius = maxf(radius, 0.05)
	if _mesh != null:
		var scale_t := clampf(radius / maxf(_max_radius, 0.01), 0.12, 1.0)
		_mesh.scale = Vector3.ONE * scale_t

	if _age > grow_end and _mat != null:
		var fade_t := clampf((_age - grow_end) / maxf(_linger_sec, 0.01), 0.0, 1.0)
		_mat.albedo_color.a = lerpf(0.62, 0.0, fade_t)

	_resolve_overlaps()


func _resolve_overlaps() -> void:
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
		var id := hit.get_instance_id()
		if _hit_bodies.has(id):
			continue
		_hit_bodies[id] = true
		_apply_hit(hit)
		_finish()
		return


func _block_if_ward(body: Node) -> bool:
	if not SpellWardBlockScript.try_block(body, hit_damage, _caster):
		return false
	_finish()
	return true


func _apply_hit(body: Node3D) -> void:
	var apply_local := _should_apply_local(body)
	var origin := global_position
	if _caster != null and is_instance_valid(_caster):
		origin = _caster.global_position
	var away := AshFrostBreathFlightScript.flat_direction(origin, body.global_position)
	if away.length_squared() < 0.0001:
		away = Vector3(_direction.x, 0.0, _direction.z)
	if apply_local:
		PlayerFrostBreathScript.apply(body, away)
	if hit_damage > 0.0:
		Character.apply_hit(body, hit_damage, self)


func _should_apply_local(body: Node) -> bool:
	var state := get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
	var mp := state != null and bool(state.get("is_multiplayer"))
	if mp and body is Node:
		return (body as Node).is_multiplayer_authority()
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	NetLivenessScript.despawn_or_free(self)
