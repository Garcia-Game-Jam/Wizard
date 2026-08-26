class_name WorldHealthBar
extends Node3D

## Billboard HP bar for stationary world targets (e.g. Gnome Den).

const BAR_WIDTH := 1.2
const BAR_HEIGHT := 0.12

var _host: Node = null
var _mesh: MeshInstance3D
var _fill_mesh: MeshInstance3D
var _fill_mat: StandardMaterial3D


func _ready() -> void:
	_build_meshes()
	set_process(true)


func bind_to(host: Node) -> void:
	_host = host


func _process(_delta: float) -> void:
	if _host == null or not is_instance_valid(_host):
		visible = false
		return
	var ratio := 1.0
	if _host.has_method("get_health_ratio"):
		ratio = float(_host.call("get_health_ratio"))
	elif "current_health" in _host and "max_health" in _host:
		var max_h := maxf(float(_host.get("max_health")), 0.001)
		ratio = clampf(float(_host.get("current_health")) / max_h, 0.0, 1.0)
	var alive := true
	if "is_alive" in _host:
		alive = bool(_host.get("is_alive"))
	visible = alive and ratio < 0.999
	if _fill_mesh != null:
		_fill_mesh.scale.x = maxf(ratio, 0.02)
		_fill_mesh.position.x = -BAR_WIDTH * 0.5 * (1.0 - ratio)
	if _host is Node3D:
		global_position = (_host as Node3D).global_position + Vector3(0.0, 1.4, 0.0)
	look_at(global_position + Vector3(0.0, 0.0, -1.0), Vector3.UP)


func _build_meshes() -> void:
	var bg := MeshInstance3D.new()
	var bg_box := BoxMesh.new()
	bg_box.size = Vector3(BAR_WIDTH, BAR_HEIGHT, 0.02)
	bg.mesh = bg_box
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.85)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.material_override = bg_mat
	add_child(bg)

	_fill_mesh = MeshInstance3D.new()
	var fill_box := BoxMesh.new()
	fill_box.size = Vector3(BAR_WIDTH, BAR_HEIGHT * 0.7, 0.03)
	_fill_mesh.mesh = fill_box
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.albedo_color = Color(0.2, 0.85, 0.35, 0.95)
	_fill_mesh.material_override = _fill_mat
	_fill_mesh.position = Vector3(-BAR_WIDTH * 0.5, 0.0, 0.01)
	add_child(_fill_mesh)
