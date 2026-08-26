class_name LightCastCharge
extends CastChargeFx

## Bright lantern chip for wand-beam / flashlight toggles.

const RADIUS_M := 0.009

var _core: MeshInstance3D
var _mat: StandardMaterial3D


func _build(spell_color: Color) -> void:
	var radius := _local_radius(RADIUS_M)
	_core = MeshInstance3D.new()
	_core.name = "Core"
	var prism := PrismMesh.new()
	prism.size = Vector3(radius * 1.6, radius * 2.2, radius * 1.6)
	_core.mesh = prism
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_mat.emission_enabled = true
	_mat.emission = spell_color
	_mat.emission_energy_multiplier = 2.2
	_mat.set_meta("spell_color", spell_color)
	_core.material_override = _mat
	add_child(_core)


func _apply_progress(p: float) -> void:
	if _mat == null:
		return
	var target: Color = _mat.get_meta("spell_color", Color(1.0, 0.9, 0.5, 1.0))
	_mat.emission = Color.WHITE.lerp(target, p)
	_mat.emission_energy_multiplier = lerpf(2.0, 5.5, p)


func tick(delta: float) -> void:
	if _core != null:
		_core.rotate_y(deg_to_rad(90.0) * delta)
