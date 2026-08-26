class_name EmberDashTrailSegment
extends Area3D

## Flat ground burn segment left by Ember Caster dash. Slow + DPS stub on overlap.

const SegmentScript := preload("res://scripts/monsters/abilities/ember_dash_trail_segment.gd")
const MonsterSpellHitScript := preload("res://scripts/combat/monster_spell_hit.gd")
const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")

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
	caster: Node3D = null
) -> Area3D:
	var seg: Area3D = SegmentScript.new()
	seg._lifetime_sec = lifetime_sec
	seg._burn_dps = burn_dps
	seg._burn_slow_multiplier = burn_slow_multiplier
	seg._burn_refresh_sec = burn_refresh_sec
	seg._caster = caster
	parent.add_child(seg)
	seg._build_visual(width, length)
	seg.global_position = Vector3(world_position.x, GROUND_Y, world_position.z)
	if direction.length_squared() > 0.0001:
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		seg.rotation.y = atan2(flat.x, flat.z)
	seg.monitoring = true
	seg.monitorable = false
	MonsterSpellHitScript.apply_mask(seg)
	seg.set_physics_process(true)
	return seg


func _build_visual(width: float, length: float) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.02, maxf(length, 0.2))
	mesh_inst.mesh = box
	mesh_inst.position = Vector3(0.0, 0.01, box.size.z * 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.12, 0.06, 0.82)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.05)
	mat.emission_energy_multiplier = 2.2
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)

	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.35, maxf(length, 0.2))
	shape_node.shape = shape
	shape_node.position = Vector3(0.0, 0.12, box.size.z * 0.5)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _caster != null and not is_instance_valid(_caster):
		_caster = null
	_age += delta
	if _age >= _lifetime_sec:
		queue_free()
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
