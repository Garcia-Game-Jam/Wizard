@tool
class_name EmberLobProjectile
extends Area3D

## Lob arc, then dive at the player's position snapped at apex. Fireball hit contract.

const EmberLobFlightScript := preload("res://scripts/monsters/abilities/ember_lob_flight.gd")
const FireballExplosionEffectScript := preload(
	"res://scripts/spells/fireball_explosion_effect.gd"
)
const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")
const MonsterSpellHitScript := preload("res://scripts/combat/monster_spell_hit.gd")
const HIT_DAMAGE := 20.0
const MAX_LIFE_SEC := 4.0

@export_range(0.0, 200.0, 1.0) var hit_damage: float = HIT_DAMAGE

var _caster: Node3D = null
var _target: Node3D = null
var _velocity: Vector3 = Vector3.ZERO
var _diving: bool = false
var _dive_point: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _finished: bool = false


static func spawn(
	parent: Node,
	origin: Vector3,
	target: Node3D,
	caster: Node3D = null
) -> EmberLobProjectile:
	var packed: PackedScene = load(
		"res://scenes/monsters/abilities/ember_lob_projectile.tscn"
	) as PackedScene
	var proj: EmberLobProjectile = packed.instantiate() as EmberLobProjectile
	parent.add_child(proj)
	proj.process_mode = Node.PROCESS_MODE_ALWAYS
	proj.global_position = origin
	proj.setup(target, caster)
	return proj


func setup(target: Node3D, caster: Node3D = null) -> void:
	_target = target
	_caster = caster
	monitoring = true
	monitorable = false
	MonsterSpellHitScript.apply_mask(self)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)

	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.16
	ball.height = 0.32
	mesh.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.35, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.05)
	mat.emission_energy_multiplier = 4.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.4, 0.1)
	light.light_energy = 3.5
	light.omni_range = 3.5
	light.shadow_enabled = false
	add_child(light)

	var smoke := GPUParticles3D.new()
	smoke.amount = 18
	smoke.lifetime = 0.45
	smoke.emitting = true
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 40.0
	pmat.initial_velocity_min = 0.4
	pmat.initial_velocity_max = 1.2
	pmat.gravity = Vector3(0, 1.5, 0)
	pmat.scale_min = 0.08
	pmat.scale_max = 0.18
	pmat.color = Color(0.25, 0.22, 0.2, 0.65)
	smoke.process_material = pmat
	var smesh := SphereMesh.new()
	smesh.radius = 0.06
	smesh.height = 0.12
	smoke.draw_pass_1 = smesh
	add_child(smoke)

	var aim := target.global_position if target != null else global_position + Vector3.FORWARD
	_velocity = EmberLobFlightScript.initial_lob_velocity(global_position, aim)
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
		_finish(true)
		return

	if _diving:
		_velocity = EmberLobFlightScript.dive_velocity(global_position, _dive_point)
		var dive_prev := global_position
		global_position += _velocity * delta
		if SpellWardBlockScript.try_block_along_path(
			get_tree(), dive_prev, global_position, 0.18, hit_damage, _caster
		):
			_finish(false)
			return
		if global_position.distance_to(_dive_point) <= 0.35 or global_position.y <= _dive_point.y:
			_finish(true)
		return

	var prev_vy := _velocity.y
	_velocity = EmberLobFlightScript.step_lob_velocity(_velocity, delta)
	var lob_prev := global_position
	global_position += _velocity * delta
	if SpellWardBlockScript.try_block_along_path(
		get_tree(), lob_prev, global_position, 0.18, hit_damage, _caster
	):
		_finish(false)
		return
	if EmberLobFlightScript.crossed_apex(prev_vy, _velocity.y):
		_diving = true
		if _target != null and is_instance_valid(_target):
			_dive_point = _target.global_position
		else:
			_dive_point = global_position + Vector3(0.0, -2.0, 0.0)
		_velocity = EmberLobFlightScript.dive_velocity(global_position, _dive_point)


func _on_body_entered(body: Node3D) -> void:
	if _finished:
		return
	var kind := MonsterSpellHitScript.kind(body, _caster)
	if kind == MonsterSpellHitScript.Kind.IGNORE:
		return
	if kind == MonsterSpellHitScript.Kind.WARD:
		_block_if_ward(body)
		return
	if kind == MonsterSpellHitScript.Kind.COMBAT:
		_try_hit(body)
		return
	_finish(true)


func _block_if_ward(body: Node) -> bool:
	if not SpellWardBlockScript.try_block(body, hit_damage, _caster):
		return false
	## Ward eats the spell — vanish with no ground impact burst.
	_finish(false)
	return true


func _try_hit(body: Node3D) -> bool:
	if MonsterSpellHitScript.kind(body, _caster) != MonsterSpellHitScript.Kind.COMBAT:
		return false
	var dir := _velocity
	if dir.length_squared() < 0.0001:
		dir = Vector3.DOWN
	else:
		dir = dir.normalized()
	_finish(true)
	var apply_local := true
	if body is Node:
		var state := get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
		var mp := state != null and bool(state.get("is_multiplayer"))
		apply_local = (not mp) or (body as Node).is_multiplayer_authority()
	if apply_local and body.has_method("apply_fireball_knockback"):
		body.call("apply_fireball_knockback", dir)
	if hit_damage > 0.0:
		Character.apply_hit(body, hit_damage, self)
	return true


func _finish(spawn_impact: bool = false) -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	if spawn_impact and is_inside_tree():
		var world_parent := get_parent()
		var impact_pos := global_position
		if world_parent != null:
			FireballExplosionEffectScript.spawn(world_parent, impact_pos)
	queue_free()
