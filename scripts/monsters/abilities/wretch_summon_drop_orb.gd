@tool
extends Node3D

## Slow green orb that drops to a ground point, then spawns a rat and vanishes.

signal landed(world_position: Vector3)

const GLOW := Color(0.3, 0.95, 0.4, 1.0)

var _start: Vector3 = Vector3.ZERO
var _end: Vector3 = Vector3.ZERO
var _duration: float = 1.0
var _age: float = 0.0
var _done: bool = false
var _mesh: MeshInstance3D = null
var _light: OmniLight3D = null


static func spawn(
	parent: Node,
	origin: Vector3,
	land_position: Vector3,
	duration_sec: float = 1.0
) -> Node3D:
	var orb = new()
	orb.name = "WretchSummonDropOrb"
	parent.add_child(orb)
	orb._setup(origin, land_position, duration_sec)
	return orb


func _setup(origin: Vector3, land_position: Vector3, duration_sec: float) -> void:
	_start = origin
	_end = land_position
	_duration = maxf(0.2, duration_sec)
	_age = 0.0
	global_position = origin
	_build_visual()
	set_process(true)


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.85)
	mat.emission_enabled = true
	mat.emission = GLOW
	mat.emission_energy_multiplier = 4.0
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.light_energy = 2.2
	_light.omni_range = 1.6
	_light.shadow_enabled = false
	add_child(_light)


func _process(delta: float) -> void:
	if _done:
		return
	_age += delta
	var t := clampf(_age / _duration, 0.0, 1.0)
	## Ease-in drop: hangs a beat, then settles to the ground.
	var eased := t * t
	global_position = _start.lerp(_end, eased)
	var bob := 1.0 + sin(t * PI) * 0.15
	if _mesh != null:
		_mesh.scale = Vector3.ONE * bob
	if t >= 1.0:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	landed.emit(_end)
	queue_free()
