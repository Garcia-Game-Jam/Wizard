class_name FlareCastCharge
extends CastChargeFx

## Red signal cone that grows at the wand tip, pointing along the shaft.

const RADIUS_M := 0.011
const SPIN_DEG := Vector3(0.0, 48.0, 0.0)

var _cone: MeshInstance3D
var _mat: StandardMaterial3D


func _build(spell_color: Color) -> void:
	var radius := _local_radius(RADIUS_M)
	_cone = MeshInstance3D.new()
	_cone.name = "Cone"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius * 1.15
	mesh.height = radius * 3.6
	mesh.radial_segments = 18
	_cone.mesh = mesh
	_cone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_cone.position = Vector3(0.0, 0.0, -radius * 1.8)
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.85, 0.4, 1.0)
	_mat.emission_energy_multiplier = 1.6
	_cone.material_override = _mat
	_mat.set_meta("spell_color", spell_color)
	add_child(_cone)


func _apply_progress(p: float) -> void:
	if _mat == null:
		return
	var target: Color = _mat.get_meta("spell_color", Color(1.0, 0.72, 0.22, 1.0))
	var col := Color(1.0, 1.0, 1.0, 0.35).lerp(
		Color(target.r, target.g, target.b, 0.55), p
	)
	_mat.albedo_color = col
	_mat.emission = col.lightened(0.12)
	_mat.emission_energy_multiplier = lerpf(1.6, 3.4, p)


func tick(delta: float) -> void:
	rotate_y(deg_to_rad(SPIN_DEG.y) * delta)
