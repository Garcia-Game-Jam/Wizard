@tool
class_name ForceField
extends Node3D

## Translucent rim-lit field with crackling energy. Authored Mesh child owns
## the look; this script fits that mesh and pushes inspector params into the
## shader. Open scenes/fx/force_field.tscn to preview a sphere.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const SHADER := preload("res://shaders/fx/force_field.gdshader")

@export var rim_color: Color = Color(0.42, 0.78, 1.0, 1.0):
	set(value):
		rim_color = value
		_apply_params()

@export var energy_color: Color = Color(0.95, 0.98, 1.0, 1.0):
	set(value):
		energy_color = value
		_apply_params()

@export_range(0.5, 6.0, 0.05) var fresnel_power: float = 2.8:
	set(value):
		fresnel_power = value
		_apply_params()

@export_range(0.0, 0.4, 0.005) var base_alpha: float = 0.05:
	set(value):
		base_alpha = value
		_apply_params()

@export_range(0.0, 2.0, 0.01) var rim_strength: float = 0.92:
	set(value):
		rim_strength = value
		_apply_params()

@export_range(0.0, 2.0, 0.01) var energy_amount: float = 1.15:
	set(value):
		energy_amount = value
		_apply_params()

@export_range(0.05, 8.0, 0.01) var pattern_scale: float = 0.28:
	set(value):
		pattern_scale = value
		_apply_params()

@export_range(0.0, 1.0, 0.01) var scroll_speed: float = 0.11:
	set(value):
		scroll_speed = value
		_apply_params()

@export_range(0.0, 4.0, 0.05) var proximity_fade: float = 1.2:
	set(value):
		proximity_fade = value
		_apply_params()

@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0:
	set(value):
		opacity = value
		_apply_params()

var _mesh: MeshInstance3D = null
var _material: ShaderMaterial = null


static func make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("rim_color", Color(0.42, 0.78, 1.0, 1.0))
	mat.set_shader_parameter("energy_color", Color(0.95, 0.98, 1.0, 1.0))
	mat.set_shader_parameter("fresnel_power", 2.8)
	mat.set_shader_parameter("base_alpha", 0.05)
	mat.set_shader_parameter("rim_strength", 0.92)
	mat.set_shader_parameter("energy_amount", 1.15)
	mat.set_shader_parameter("pattern_scale", 0.28)
	mat.set_shader_parameter("scroll_speed", 0.11)
	mat.set_shader_parameter("proximity_fade", 1.2)
	mat.set_shader_parameter("opacity", 1.0)
	return mat


func _ready() -> void:
	_bind_mesh()
	_apply_params()


func fit_sphere(radius: float) -> void:
	_bind_mesh()
	if _mesh == null:
		return
	var sphere := SphereMesh.new()
	var r := maxf(radius, 0.05)
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_mesh.mesh = sphere
	position = Vector3.ZERO
	rotation = Vector3.ZERO


func fit_wall(center: Vector3, wall_size: Vector3, inward: Vector3) -> void:
	_bind_mesh()
	if _mesh == null:
		return
	var along_x := wall_size.x >= wall_size.z
	var width := wall_size.x if along_x else wall_size.z
	var height := wall_size.y
	var quad := QuadMesh.new()
	quad.size = Vector2(maxf(width, 0.1), maxf(height, 0.1))
	_mesh.mesh = quad
	var dir := Vector3(inward.x, 0.0, inward.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	var thick := minf(wall_size.x, wall_size.z)
	position = center + dir * (thick * 0.5)
	var x_axis := Vector3.UP.cross(dir)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.RIGHT
	else:
		x_axis = x_axis.normalized()
	transform.basis = Basis(x_axis, dir.cross(x_axis), dir)


func _bind_mesh() -> void:
	if _mesh != null:
		return
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	if _mesh == null:
		return
	_mesh.layers = WorldVisualLayersScript.WORLD
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = _mesh.material_override as ShaderMaterial
	if _material != null:
		_material = _material.duplicate() as ShaderMaterial
		_mesh.material_override = _material


func _apply_params() -> void:
	if not is_node_ready():
		return
	if _material == null:
		_bind_mesh()
	if _material == null:
		return
	_material.set_shader_parameter("rim_color", rim_color)
	_material.set_shader_parameter("energy_color", energy_color)
	_material.set_shader_parameter("fresnel_power", fresnel_power)
	_material.set_shader_parameter("base_alpha", base_alpha)
	_material.set_shader_parameter("rim_strength", rim_strength)
	_material.set_shader_parameter("energy_amount", energy_amount)
	_material.set_shader_parameter("pattern_scale", pattern_scale)
	_material.set_shader_parameter("scroll_speed", scroll_speed)
	_material.set_shader_parameter("proximity_fade", proximity_fade)
	_material.set_shader_parameter("opacity", opacity)
