extends MeshInstance3D

const TrailSampleScript := preload("res://scripts/trails/trail_sample.gd")

## One ground footprint in a player's path. Hidden until Show Me reveals trails.

const MAX_FOOTPRINT_SCALE := 0.62
const MIN_FOOTPRINT_SCALE := 0.14
const GROUND_Y := 0.045
const BASE_ALPHA := 0.88
const FOOT_LATERAL_OFFSET := 0.11
const AGED_FOOTPRINT_GREY := Color(0.36, 0.35, 0.38)
const GREY_BLEND_CURVE := 0.55

var _spawn_msec: int = 0
var _trail_color: Color = Color.WHITE
var _footprint_pos: Vector2 = Vector2.ZERO
var _move_direction: Vector2 = Vector2(0.0, 1.0)
var _foot_side: int = 0


func setup_from_sample(
	sample: Dictionary,
	trail_color: Color,
	move_direction: Vector2,
	foot_side: int
) -> void:
	_trail_color = trail_color
	_spawn_msec = TrailSampleScript.time_msec(sample)
	_footprint_pos = TrailSampleScript.position(sample)
	_foot_side = foot_side
	if move_direction.length_squared() > 0.0001:
		_move_direction = move_direction.normalized()
	mesh = _build_foot_mesh()
	material_override = _build_material(trail_color)
	_apply_footprint_transform(_current_scale())
	_update_visual()


func _process(_delta: float) -> void:
	var lifetime := TrailRegistry.get_node_lifetime_sec()
	var age := (Time.get_ticks_msec() - _spawn_msec) / 1000.0
	if age >= lifetime:
		queue_free()
		return
	_apply_footprint_transform(_current_scale())
	_update_visual()


func _current_scale() -> float:
	var lifetime := TrailRegistry.get_node_lifetime_sec()
	var age := (Time.get_ticks_msec() - _spawn_msec) / 1000.0
	var age_ratio := clampf(age / lifetime, 0.0, 1.0)
	return lerpf(MAX_FOOTPRINT_SCALE, MIN_FOOTPRINT_SCALE, age_ratio)


func _apply_footprint_transform(footprint_scale: float) -> void:
	var lateral := Vector2(-_move_direction.y, _move_direction.x)
	if _foot_side % 2 == 1:
		lateral = -lateral
	var offset := lateral * FOOT_LATERAL_OFFSET * footprint_scale
	global_position = Vector3(
		_footprint_pos.x + offset.x,
		GROUND_Y,
		_footprint_pos.y + offset.y
	)
	rotation.y = atan2(_move_direction.x, _move_direction.y)
	scale = Vector3(footprint_scale, footprint_scale * 0.22, footprint_scale)


func _update_visual() -> void:
	var lifetime := TrailRegistry.get_node_lifetime_sec()
	var age := (Time.get_ticks_msec() - _spawn_msec) / 1000.0
	var age_ratio := clampf(age / lifetime, 0.0, 1.0)

	var revealed := TrailRegistry.is_revealed()
	var grey_blend := pow(age_ratio, GREY_BLEND_CURVE)
	var alpha := 0.0
	if revealed:
		alpha = lerpf(BASE_ALPHA, BASE_ALPHA * 0.22, age_ratio)

	if material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = material_override
		var footprint_color := _trail_color.lerp(AGED_FOOTPRINT_GREY, grey_blend)
		footprint_color = footprint_color.darkened(age_ratio * 0.28)
		mat.albedo_color = Color(footprint_color.r, footprint_color.g, footprint_color.b, alpha)
		mat.emission = footprint_color * lerpf(0.82, 0.06, grey_blend)
		mat.emission_energy_multiplier = lerpf(2.4, 0.12, grey_blend) if revealed else 0.0


func _build_material(trail_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(trail_color.r, trail_color.g, trail_color.b, 0.0)
	material.emission_enabled = true
	material.emission = trail_color * 0.4
	material.emission_energy_multiplier = 0.0
	material.roughness = 0.95
	material.metallic = 0.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _build_foot_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := PackedVector2Array([
		Vector2(0.11, 0.34),
		Vector2(0.17, 0.20),
		Vector2(0.13, 0.04),
		Vector2(0.09, -0.14),
		Vector2(0.10, -0.26),
		Vector2(0.0, -0.30),
		Vector2(-0.10, -0.26),
		Vector2(-0.09, -0.14),
		Vector2(-0.13, 0.04),
		Vector2(-0.17, 0.20),
		Vector2(-0.11, 0.34),
	])
	var center := Vector3.ZERO
	for i in outline.size() - 1:
		var p0 := Vector3(outline[i].x, 0.0, outline[i].y)
		var p1 := Vector3(outline[i + 1].x, 0.0, outline[i + 1].y)
		surface_tool.set_normal(Vector3.UP)
		surface_tool.add_vertex(center)
		surface_tool.add_vertex(p0)
		surface_tool.add_vertex(p1)
	return surface_tool.commit()
