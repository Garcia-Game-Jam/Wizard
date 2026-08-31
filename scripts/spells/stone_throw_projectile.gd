@tool
class_name StoneThrowProjectile
extends "res://scripts/spells/spell_projectile.gd"

## Forward-thrown rock. Flight/connect live on SpellProjectile.
## Charge is unused (require_full_charge); spin is the look.

const DEFAULT_HIT_DAMAGE := 15.0
const DEFAULT_CHARGE_TIME_SEC := 0.7
const SPIN_SPEED_X := 9.0
const SPIN_SPEED_Z := 5.4

@export_group("Cast timing")
## Hold time until the stone is ready to throw.
@export_range(0.05, 5.0, 0.05) var charge_time_sec: float = DEFAULT_CHARGE_TIME_SEC:
	set(value):
		charge_time_sec = maxf(value, 0.05)

var _mesh: MeshInstance3D


static func spawn(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	caster: Node3D = null,
	lookdev_flight: bool = false
) -> Node:
	## Lookdev. Live pit instantiates via NetSpellWeapon.
	## Lazy-load avoids circular preload with stone_throw.tscn.
	var packed: PackedScene = load(
		"res://scenes/spells/stone_throw/stone_throw.tscn"
	) as PackedScene
	var projectile: Node = packed.instantiate()
	if lookdev_flight:
		projectile.set_meta("lookdev_flight", true)
		projectile.process_mode = Node.PROCESS_MODE_ALWAYS
	if parent != null and projectile is Node3D:
		SpellEphemeralFxScript.add_child_at(parent, projectile as Node3D, origin)
	elif parent != null:
		parent.add_child(projectile)
	if projectile is StoneThrowProjectile:
		(projectile as StoneThrowProjectile).setup_launch(origin, direction, caster)
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


func _ready() -> void:
	_cache_nodes()
	super._ready()
	if Engine.is_editor_hint() and not _is_lookdev_flight():
		return
	set_process(true)


func _cache_nodes() -> void:
	super._cache_nodes()
	_mesh = get_node_or_null("Mesh") as MeshInstance3D


## Tumble while flying — a thrown rock, not a smooth-gliding orb.
func _process(delta: float) -> void:
	if _finished or _mesh == null:
		return
	_mesh.rotate_x(SPIN_SPEED_X * delta)
	_mesh.rotate_z(SPIN_SPEED_Z * delta)


func _ensure_payload() -> CombatPayload:
	if payload != null:
		return payload
	payload = CombatPayload.new()
	payload.effects.append(Damage.with(hit_damage if hit_damage > 0.0 else DEFAULT_HIT_DAMAGE))
	var knock := Knock.new()
	knock.from_impact = true
	knock.impulse = Vector3(Character.KNOCKBACK_HORIZONTAL, Character.KNOCKBACK_UP, 0.0)
	payload.effects.append(knock)
	return payload


func _clear_projectile_visuals() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.visible = false
	super._clear_projectile_visuals()
