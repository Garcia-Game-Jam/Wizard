@tool
class_name EmberLobProjectile
extends Area3D

## Lob arc, then dive at the player's position snapped at apex.
## Hits are a splash-radius group scan (same contract as stone throw): Area3D
## body_entered does not fire on the rollback tick path, and the dive often
## detonates at the pawn root — below the capsule — so overlap-only misses.

const EmberLobFlightScript := preload("res://scripts/monsters/abilities/ember_lob_flight.gd")
const FireballExplosionEffectScript := preload(
	"res://scripts/spells/fireball_explosion_effect.gd"
)
const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")
const MonsterSpellHitScript := preload("res://scripts/combat/monster_spell_hit.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")
const HIT_DAMAGE := 20.0
const MAX_LIFE_SEC := 4.0
const SPLASH_RADIUS := 1.0

@export_range(0.0, 200.0, 1.0) var hit_damage: float = HIT_DAMAGE
@export var payload: CombatPayload

var _caster: Node3D = null
var _target: Node3D = null
var _velocity: Vector3 = Vector3.ZERO
var _diving: bool = false
var _dive_point: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _finished: bool = false
var _tick_fresh: bool = true


static func spawn(
	parent: Node,
	origin: Vector3,
	target: Node3D,
	caster: Node3D = null,
	visual_only: bool = false,
	aim: Vector3 = Vector3.ZERO
) -> EmberLobProjectile:
	if parent == null:
		return null
	var packed: PackedScene = load(
		"res://scenes/monsters/abilities/ember_lob_projectile.tscn"
	) as PackedScene
	var proj: EmberLobProjectile = packed.instantiate() as EmberLobProjectile
	parent.add_child(proj)
	proj.process_mode = Node.PROCESS_MODE_ALWAYS
	proj.global_position = origin
	var aim_point := aim
	if aim_point == Vector3.ZERO and target != null:
		aim_point = target.global_position
	proj.setup(target, caster, aim_point)
	if visual_only:
		proj.monitoring = false
		proj.monitorable = false
	else:
		var extra := {"aim_x": aim_point.x, "aim_y": aim_point.y, "aim_z": aim_point.z}
		NetLivenessScript.replicate_world_fx("ember_lob", proj.global_position, extra)
	NetLivenessScript.after_spawn(proj)
	return proj


func setup(target: Node3D, caster: Node3D = null, aim_point: Vector3 = Vector3.ZERO) -> void:
	_target = target
	_caster = caster
	monitoring = true
	monitorable = false
	MonsterSpellHitScript.apply_mask(self)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	var aim := aim_point
	if aim == Vector3.ZERO:
		aim = target.global_position if target != null else global_position + Vector3.FORWARD
	_velocity = EmberLobFlightScript.initial_lob_velocity(global_position, aim)
	set_physics_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_physics_process(delta)


func _physics_process(delta: float) -> void:
	if NetLivenessScript.skip_engine_physics():
		return
	_tick_fresh = true
	_tick_motion(delta)


func _rollback_tick(delta: float, _tick: int, is_fresh: bool) -> void:
	_tick_fresh = is_fresh
	_tick_motion(delta)


func _rollback_spawn() -> void:
	NetLivenessScript.activate(self)
	_age = 0.0


func _rollback_despawn() -> void:
	NetLivenessScript.deactivate(self)


func _tick_motion(delta: float) -> void:
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
		if _blocked_or_hit(dive_prev):
			return
		if global_position.distance_to(_dive_point) <= 0.35 or global_position.y <= _dive_point.y:
			_finish(true)
		return

	var prev_vy := _velocity.y
	_velocity = EmberLobFlightScript.step_lob_velocity(_velocity, delta)
	var lob_prev := global_position
	global_position += _velocity * delta
	if _blocked_or_hit(lob_prev):
		return
	if EmberLobFlightScript.crossed_apex(prev_vy, _velocity.y):
		_diving = true
		if _target != null and is_instance_valid(_target):
			_dive_point = _target.global_position
		else:
			_dive_point = global_position + Vector3(0.0, -2.0, 0.0)
		_velocity = EmberLobFlightScript.dive_velocity(global_position, _dive_point)


func _blocked_or_hit(prev: Vector3) -> bool:
	if SpellWardBlockScript.try_block_along_path(
		get_tree(), prev, global_position, 0.18, hit_damage, _caster
	):
		_finish(false)
		return true
	if _combat_in_splash(global_position):
		_finish(true)
		return true
	return false


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
		_finish(true)
		return
	_finish(true)


func _block_if_ward(body: Node) -> bool:
	if not SpellWardBlockScript.try_block(body, hit_damage, _caster):
		return false
	## Ward eats the spell — vanish with no ground impact burst.
	_finish(false)
	return true


func _finish(spawn_impact: bool = false) -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	if spawn_impact:
		_apply_splash_at(global_position)
	if spawn_impact and _tick_fresh and is_inside_tree():
		var world_parent := get_parent()
		var impact_pos := global_position
		if world_parent != null:
			FireballExplosionEffectScript.spawn(world_parent, impact_pos)
	NetLivenessScript.despawn_or_free(self)


func _combat_in_splash(origin: Vector3) -> bool:
	return not CombatSplash.bodies_near(get_tree(), origin, SPLASH_RADIUS, _caster).is_empty()


func _apply_splash_at(impact_pos: Vector3) -> void:
	if not monitoring:
		return
	CombatSplash.apply_at(get_tree(), impact_pos, SPLASH_RADIUS, self, _ensure_payload(), _caster)


func _ensure_payload() -> CombatPayload:
	if payload != null:
		return payload
	payload = CombatPayload.new()
	payload.effects.append(Damage.with(hit_damage))
	return payload
