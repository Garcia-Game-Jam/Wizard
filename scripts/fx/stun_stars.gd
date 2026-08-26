@tool
class_name StunStars
extends Node3D

## Cartoon 5-point stars that orbit a host. Shared by Charger wall-stun and
## player ram-stun. Star meshes are authored children; this only transforms them.

enum OrbitMode { HORIZONTAL, FACING }

const BAKED_RADIUS := 1.0

@export_range(0.04, 0.8, 0.01) var orbit_radius: float = 0.28
@export_range(0.5, 10.0, 0.1) var orbit_speed: float = 4.2
@export_range(0.02, 0.2, 0.005) var star_size: float = 0.07
@export var star_color: Color = Color(1.0, 0.92, 0.25, 1.0)
@export var orbit_mode: OrbitMode = OrbitMode.HORIZONTAL
@export_range(0.0, 0.12, 0.005) var bob_amp: float = 0.03

@export_group("Editor preview")
@export_tool_button("Play Animation", "Callable")
var play_animation_action := play_animation
@export_tool_button("Stop Animation", "Callable")
var stop_animation_action := stop_animation

var _stars: Array[MeshInstance3D] = []
var _angle: float = 0.0
var _active: bool = false


func _enter_tree() -> void:
	_bind_authored()


func _ready() -> void:
	visible = false
	_bind_authored()
	_apply_star_color()
	set_process(false)


func play_animation() -> void:
	if not is_inside_tree():
		return
	_bind_authored()
	if Engine.is_editor_hint():
		process_mode = Node.PROCESS_MODE_ALWAYS
	set_active(true)


func stop_animation() -> void:
	set_active(false)


func set_active(on: bool) -> void:
	_active = on
	visible = on
	set_process(on)
	if not on:
		_angle = 0.0


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	_bind_authored()
	_angle += delta * orbit_speed
	var count := maxi(_stars.size(), 1)
	var size := star_size / BAKED_RADIUS
	for i in _stars.size():
		var star := _stars[i]
		if star == null:
			continue
		var a := _angle + float(i) * TAU / float(count)
		star.position = _orbit_point(a)
		var pulse := 1.0 + sin(a * 3.0) * 0.12
		star.scale = Vector3.ONE * size * pulse


func _orbit_point(angle: float) -> Vector3:
	var c := cos(angle) * orbit_radius
	var s := sin(angle) * orbit_radius
	var bob := sin(angle * 2.0) * bob_amp
	if orbit_mode == OrbitMode.FACING:
		return Vector3(c, s, 0.0)
	return Vector3(c, 0.06 + bob, s)


func _bind_authored() -> void:
	if not _stars.is_empty():
		return
	for child in get_children():
		if child is MeshInstance3D:
			_stars.append(child as MeshInstance3D)


func _apply_star_color() -> void:
	for star in _stars:
		if star == null:
			continue
		var mat := star.material_override as StandardMaterial3D
		if mat == null:
			mat = star.get_surface_override_material(0) as StandardMaterial3D
		if mat == null:
			continue
		mat.albedo_color = star_color
		mat.emission = star_color
		return
