class_name WardCastCharge
extends CastChargeFx

## Thin wand-tip beam used if a charge scene is instanced; live channel VFX is on WardShield.

const LENGTH_M := 0.22
const RADIUS_M := 0.006


func _build(spell_color: Color) -> void:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = _local_radius(RADIUS_M * 0.45)
	cyl.bottom_radius = _local_radius(RADIUS_M)
	cyl.height = _local_radius(LENGTH_M)
	beam.mesh = cyl
	beam.position = Vector3(0.0, 0.0, -cyl.height * 0.5)
	beam.rotation.x = -PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(spell_color.r, spell_color.g, spell_color.b, 0.5)
	mat.emission_enabled = true
	mat.emission = spell_color.lightened(0.2)
	mat.emission_energy_multiplier = 2.2
	beam.material_override = mat
	add_child(beam)
