class_name EmberDashTrailSegment
extends Area3D

## Flat ground burn segment left by Ember Caster dash. Slow + DPS stub on overlap.

const MonsterSpellHitScript := preload("res://scripts/combat/monster_spell_hit.gd")
const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")
const SCENE := preload("res://scenes/monsters/abilities/ember_dash_trail_segment.tscn")

const GROUND_Y := 0.045

var _lifetime_sec: float = 4.0
var _burn_dps: float = 6.0
var _burn_slow_multiplier: float = 0.75
var _burn_refresh_sec: float = 0.5
var _age: float = 0.0
var _caster: Node3D = null
var _ward_hit: Dictionary = {}


static func spawn(
	parent: Node,
	world_position: Vector3,
	direction: Vector3,
	width: float,
	length: float,
	lifetime_sec: float,
	burn_dps: float,
	burn_slow_multiplier: float,
	burn_refresh_sec: float,
	caster: Node3D = null,
	visual_only: bool = false
) -> Area3D:
	if parent == null:
		return null
	var seg: EmberDashTrailSegment = SCENE.instantiate() as EmberDashTrailSegment
	seg._lifetime_sec = lifetime_sec
	seg._burn_dps = burn_dps
	seg._burn_slow_multiplier = burn_slow_multiplier
	seg._burn_refresh_sec = burn_refresh_sec
	seg._caster = caster
	parent.add_child(seg)
	seg.apply_size(width, length)
	seg.global_position = Vector3(world_position.x, GROUND_Y, world_position.z)
	if direction.length_squared() > 0.0001:
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		seg.rotation.y = atan2(flat.x, flat.z)
	seg.monitoring = not visual_only
	seg.monitorable = false
	MonsterSpellHitScript.apply_mask(seg)
	seg.set_physics_process(true)
	if not visual_only:
		var extra := {
			"dir_x": direction.x,
			"dir_y": direction.y,
			"dir_z": direction.z,
			"width": width,
			"length": length,
			"lifetime": lifetime_sec,
		}
		NetLivenessScript.replicate_world_fx(
			"ember_dash",
			Vector3(world_position.x, GROUND_Y, world_position.z),
			extra
		)
	NetLivenessScript.after_spawn(seg)
	return seg


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func apply_size(width: float, length: float) -> void:
	var depth := maxf(length, 0.2)
	var mesh_inst := get_node_or_null("%Mesh") as MeshInstance3D
	if mesh_inst != null and mesh_inst.mesh is BoxMesh:
		var box := (mesh_inst.mesh as BoxMesh).duplicate() as BoxMesh
		box.size = Vector3(width, 0.02, depth)
		mesh_inst.mesh = box
		mesh_inst.position = Vector3(0.0, 0.01, depth * 0.5)
	var shape_node := get_node_or_null("%HitShape") as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var shape := (shape_node.shape as BoxShape3D).duplicate() as BoxShape3D
		shape.size = Vector3(width, 0.35, depth)
		shape_node.shape = shape
		shape_node.position = Vector3(0.0, 0.12, depth * 0.5)


func _physics_process(delta: float) -> void:
	if NetLivenessScript.skip_engine_physics():
		return
	_tick_motion(delta)


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	_tick_motion(delta)


func _rollback_spawn() -> void:
	NetLivenessScript.activate(self)
	_age = 0.0


func _rollback_despawn() -> void:
	NetLivenessScript.deactivate(self)


func _tick_motion(delta: float) -> void:
	if _caster != null and not is_instance_valid(_caster):
		_caster = null
	_age += delta
	if _age >= _lifetime_sec:
		NetLivenessScript.despawn_or_free(self)
		return
	if not NetLivenessScript.can_query_overlaps(self):
		return
	for body in get_overlapping_bodies():
		_apply_burn(body)


func _on_body_entered(body: Node3D) -> void:
	_apply_burn(body)


func _apply_burn(body: Node3D) -> void:
	var kind := MonsterSpellHitScript.kind(body, _caster)
	if kind == MonsterSpellHitScript.Kind.WARD:
		var id := body.get_instance_id()
		if _ward_hit.has(id):
			return
		_ward_hit[id] = true
		SpellWardBlockScript.try_block(body, _burn_dps * _burn_refresh_sec, _caster)
		return
	if kind != MonsterSpellHitScript.Kind.COMBAT:
		return
	var apply_local := true
	var state := get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
	var mp := state != null and bool(state.get("is_multiplayer"))
	if mp and body is Node:
		apply_local = (body as Node).is_multiplayer_authority()
	if not apply_local:
		return
	if body.has_method("apply_ember_trail_burn"):
		body.call(
			"apply_ember_trail_burn",
			_burn_dps,
			_burn_slow_multiplier,
			_burn_refresh_sec
		)
		return
	if _burn_dps > 0.0:
		Character.apply_hit(body, _burn_dps * get_physics_process_delta_time(), self)
	if body.has_method("apply_speed_boost"):
		body.call("apply_speed_boost", _burn_refresh_sec, _burn_slow_multiplier)
