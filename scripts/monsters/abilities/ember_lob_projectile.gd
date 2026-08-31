@tool
class_name EmberLobProjectile
extends "res://scripts/spells/spell_projectile.gd"

## Lob arc, then dive at the aim point captured at spawn (no live retarget).
## Guest copies stay visual_only through replicate_world_fx — not NetworkWeapon.

const EmberLobFlightScript := preload("res://scripts/monsters/abilities/ember_lob_flight.gd")
const MonsterSpellHitScript := preload("res://scripts/combat/monster_spell_hit.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")
const HIT_DAMAGE := 20.0

var _aim_point := Vector3.ZERO
var _diving := false


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
	proj.setup(caster, aim_point)
	if visual_only:
		proj.monitoring = false
		proj.monitorable = false
	else:
		var extra := {"aim_x": aim_point.x, "aim_y": aim_point.y, "aim_z": aim_point.z}
		NetLivenessScript.replicate_world_fx("ember_lob", proj.global_position, extra)
	return proj


func setup(caster: Node3D = null, aim_point: Vector3 = Vector3.ZERO) -> void:
	_caster = caster
	_aim_point = aim_point
	if _aim_point == Vector3.ZERO:
		_aim_point = global_position + Vector3.FORWARD
	MonsterSpellHitScript.apply_mask(self)
	_velocity = EmberLobFlightScript.initial_lob_velocity(global_position, _aim_point)
	_diving = false
	set_physics_process(true)


func _simulate_flight(delta: float) -> void:
	if _finished or not is_inside_tree():
		return
	if _caster != null and not is_instance_valid(_caster):
		_caster = null
	_elapsed += delta
	if _elapsed >= lifetime:
		_finish(false)
		return

	if _diving:
		_velocity = EmberLobFlightScript.dive_velocity(global_position, _aim_point)
	else:
		var prev_vy := _velocity.y
		if flight_gravity != 0.0:
			_velocity.y -= flight_gravity * delta
		if EmberLobFlightScript.crossed_apex(prev_vy, _velocity.y):
			_diving = true
			_velocity = EmberLobFlightScript.dive_velocity(global_position, _aim_point)

	if _advance_and_connect(delta):
		return
	if _diving and (
		global_position.distance_to(_aim_point) <= 0.35
		or global_position.y <= _aim_point.y
	):
		_finish(true)
