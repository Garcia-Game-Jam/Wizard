class_name PageTurnLeaf
extends Control

## Subdivided mesh leaf that peels with a Soja-style page curl.

const PAGE_SIZE := Vector2(320, 440)
const GRID_X := 28
const GRID_Y := 36
const CurlShader := preload("res://shaders/ui/page_curl.gdshader")

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_apply_progress()

var direction: float = 1.0:
	set(value):
		direction = 1.0 if value >= 0.0 else -1.0
		_apply_progress()

var _mesh_instance: MeshInstance2D
var _material: ShaderMaterial
var _viewport: SubViewport
var _source_page: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PAGE_SIZE
	size = PAGE_SIZE
	clip_contents = false
	_ensure_visuals()
	_apply_progress()


func setup_from_page(page: Control, turn_direction: float) -> void:
	direction = turn_direction
	_ensure_visuals()
	if _source_page != null and is_instance_valid(_source_page):
		_source_page.free()
		_source_page = null
	var dup := page.duplicate() as Control
	if dup == null:
		return
	dup.set_meta("flip_ghost", true)
	_disable_live_viewports(dup)
	dup.position = Vector2.ZERO
	dup.custom_minimum_size = PAGE_SIZE
	dup.size = PAGE_SIZE
	_viewport.add_child(dup)
	_source_page = dup
	_material.set_shader_parameter("front_tex", _viewport.get_texture())
	_apply_progress()


func is_past_midpoint() -> bool:
	return progress >= 0.5


func _ensure_visuals() -> void:
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = "PageSnapshot"
		_viewport.size = Vector2i(PAGE_SIZE)
		_viewport.transparent_bg = true
		_viewport.handle_input_locally = false
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_viewport)
	if _mesh_instance == null:
		_mesh_instance = MeshInstance2D.new()
		_mesh_instance.name = "CurlMesh"
		_mesh_instance.mesh = _build_grid_mesh()
		_material = ShaderMaterial.new()
		_material.shader = CurlShader
		_material.set_shader_parameter("page_size", PAGE_SIZE)
		_material.set_shader_parameter("spine_gap", 14.0)
		_material.set_shader_parameter("curl_radius", 0.12)
		_material.set_shader_parameter("corner_pull", 0.72)
		_mesh_instance.material = _material
		add_child(_mesh_instance)


func _apply_progress() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("progress", progress)
	_material.set_shader_parameter("direction", direction)


func _disable_live_viewports(root: Node) -> void:
	for node in root.find_children("*", "SubViewport", true, false):
		var vp := node as SubViewport
		if vp == null:
			continue
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		for child in vp.get_children():
			vp.remove_child(child)
			child.free()


func _build_grid_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for y in range(GRID_Y + 1):
		var v := float(y) / float(GRID_Y)
		for x in range(GRID_X + 1):
			var u := float(x) / float(GRID_X)
			verts.append(Vector2(u * PAGE_SIZE.x, v * PAGE_SIZE.y))
			uvs.append(Vector2(u, v))
			colors.append(Color.WHITE)
	for y in range(GRID_Y):
		for x in range(GRID_X):
			var i0 := y * (GRID_X + 1) + x
			var i1 := i0 + 1
			var i2 := i0 + (GRID_X + 1)
			var i3 := i2 + 1
			indices.append_array([i0, i1, i3, i0, i3, i2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
