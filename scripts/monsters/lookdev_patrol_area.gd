@tool
extends MeshInstance3D

## Authored 2D patrol rectangle. Move on XZ and scale X/Z in the viewport.
## Independent of Spawn Monster so return-to-patrol can be tested.

const FILL_COLOR := Color(0.25, 1.0, 0.45, 0.22)
const FLOOR_Y := 0.04

@export var lock_square: bool = true:
	set(value):
		lock_square = value
		if lock_square and not _applying:
			_applying = true
			var side := maxf(absf(scale.x), absf(scale.z))
			scale = Vector3(side, 1.0, side)
			_applying = false
			_notify_workspace()

@export_range(1.0, 80.0, 0.1, "or_greater", "suffix:m") var width: float = 12.0:
	set(value):
		width = maxf(value, 1.0)
		if _applying:
			return
		_applying = true
		scale.x = width
		if lock_square:
			depth = width
			scale.z = width
		_applying = false
		_notify_workspace()

@export_range(1.0, 80.0, 0.1, "or_greater", "suffix:m") var depth: float = 12.0:
	set(value):
		depth = maxf(value, 1.0)
		if _applying:
			return
		_applying = true
		scale.z = depth
		if lock_square:
			width = depth
			scale.x = depth
		_applying = false
		_notify_workspace()

var _applying: bool = false
var _last_xz: Vector4 = Vector4.ZERO


func _enter_tree() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ensure_mesh()
	set_notify_transform(true)
	_flatten()
	_sync_exports_from_scale()


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED:
		return
	if _applying:
		return
	_applying = true
	_flatten()
	_sync_exports_from_scale()
	_applying = false
	_notify_workspace()


func rect_home() -> Vector3:
	var pos := global_position
	pos.y = FLOOR_Y
	return pos


func rect_size() -> Vector2:
	return Vector2(maxf(absf(scale.x), 1.0), maxf(absf(scale.z), 1.0))


func set_rect(home: Vector3, size: Vector2) -> void:
	_applying = true
	global_position = Vector3(home.x, FLOOR_Y, home.z)
	var w := maxf(size.x, 1.0)
	var d := maxf(size.y, 1.0)
	if lock_square:
		var side := maxf(w, d)
		w = side
		d = side
	scale = Vector3(w, 1.0, d)
	width = w
	depth = d
	_applying = false
	_notify_workspace()


func _flatten() -> void:
	rotation = Vector3.ZERO
	position.y = FLOOR_Y
	var sx := maxf(absf(scale.x), 1.0)
	var sz := maxf(absf(scale.z), 1.0)
	if lock_square:
		var side := maxf(sx, sz)
		sx = side
		sz = side
	scale = Vector3(sx, 1.0, sz)


func _sync_exports_from_scale() -> void:
	width = absf(scale.x)
	depth = absf(scale.z)


func _ensure_mesh() -> void:
	if mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.06, 1.0)
		mesh = box
	if material_override != null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = FILL_COLOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat


func _notify_workspace() -> void:
	var key := Vector4(global_position.x, global_position.z, scale.x, scale.z)
	if key.is_equal_approx(_last_xz):
		return
	_last_xz = key
	var main := get_parent()
	if main != null and main.has_method("on_patrol_area_changed"):
		main.call("on_patrol_area_changed")
