class_name GrowingOrbCastCharge
extends CastChargeFx

## Default growing golf-ball charge. Tint comes from the spell color.

const RADIUS_M := 0.0105
const START_COLOR := Color(1.0, 1.0, 1.0, 0.4)
const SPIN_DEG := Vector3(52.0, 88.0, 24.0)

var _bubble: MeshInstance3D
var _mat: StandardMaterial3D
var _spell_color := Color(0.75, 0.7, 0.95, 0.4)


func _build(spell_color: Color) -> void:
	_spell_color = Color(spell_color.r, spell_color.g, spell_color.b, 0.4)
	_bubble = MeshInstance3D.new()
	_bubble.name = "Bubble"
	var radius := _local_radius(RADIUS_M)
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	_bubble.mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = START_COLOR
	_mat.emission_enabled = true
	_mat.emission = START_COLOR.lightened(0.15)
	_mat.emission_energy_multiplier = 1.2
	_bubble.material_override = _mat
	add_child(_bubble)


func _apply_progress(p: float) -> void:
	if _mat == null:
		return
	var col := START_COLOR.lerp(_spell_color, p)
	col.a = 0.4
	_mat.albedo_color = col
	_mat.emission = col.lightened(0.2)


func tick(delta: float) -> void:
	if _bubble != null:
		_bubble.rotate_x(deg_to_rad(SPIN_DEG.x) * delta)
		_bubble.rotate_y(deg_to_rad(SPIN_DEG.y) * delta)
		_bubble.rotate_z(deg_to_rad(SPIN_DEG.z) * delta)
