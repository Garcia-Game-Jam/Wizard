class_name HasteCastCharge
extends CastChargeFx

## Cyan motion streaks that spin around the wand tip.

const RADIUS_M := 0.012
const SPIN_DEG := Vector3(0.0, 0.0, 220.0)

var _mat: StandardMaterial3D


func _build(spell_color: Color) -> void:
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.4)
	_mat.emission_enabled = true
	_mat.emission = spell_color
	_mat.emission_energy_multiplier = 1.8
	_mat.set_meta("spell_color", spell_color)
	var radius := _local_radius(RADIUS_M)
	for i in 3:
		var streak := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(radius * 0.18, radius * 0.18, radius * 3.4)
		streak.mesh = box
		streak.material_override = _mat
		streak.rotation_degrees = Vector3(0.0, float(i) * 120.0, 0.0)
		streak.position = Vector3(0.0, 0.0, -radius * 0.4)
		add_child(streak)


func _apply_progress(p: float) -> void:
	if _mat == null:
		return
	var target: Color = _mat.get_meta("spell_color", Color(0.45, 0.78, 1.0, 1.0))
	var col := Color(1.0, 1.0, 1.0, 0.35).lerp(
		Color(target.r, target.g, target.b, 0.7), p
	)
	_mat.albedo_color = col
	_mat.emission = col
	_mat.emission_energy_multiplier = lerpf(1.4, 3.8, p)


func tick(delta: float) -> void:
	rotate_z(deg_to_rad(SPIN_DEG.z) * delta)
