class_name LightBallCastCharge
extends CastChargeFx

## Nested orb plus equatorial ring for the hanging light-ball charge.

const RADIUS_M := 0.012
const SPIN_DEG := Vector3(18.0, 70.0, 12.0)

var _orb: MeshInstance3D
var _ring: MeshInstance3D
var _orb_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D


func _build(spell_color: Color) -> void:
	var radius := _local_radius(RADIUS_M)
	_orb = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	_orb.mesh = sphere
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.45)
	_orb_mat.emission_enabled = true
	_orb_mat.emission = spell_color
	_orb_mat.emission_energy_multiplier = 1.6
	_orb_mat.set_meta("spell_color", spell_color)
	_orb.material_override = _orb_mat
	add_child(_orb)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.72
	torus.outer_radius = radius * 1.18
	_ring.mesh = torus
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = spell_color.lightened(0.2)
	_ring_mat.emission_energy_multiplier = 2.0
	_ring.material_override = _ring_mat
	_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(_ring)


func _apply_progress(p: float) -> void:
	if _orb_mat == null:
		return
	var target: Color = _orb_mat.get_meta("spell_color", Color(1.0, 0.9, 0.5, 1.0))
	_orb_mat.albedo_color = Color(1.0, 1.0, 1.0, lerpf(0.3, 0.65, p))
	_orb_mat.emission = Color.WHITE.lerp(target, p)
	_orb_mat.emission_energy_multiplier = lerpf(1.4, 3.6, p)
	if _ring_mat != null:
		_ring_mat.emission_energy_multiplier = lerpf(1.6, 4.0, p)


func tick(delta: float) -> void:
	if _orb != null:
		_orb.rotate_y(deg_to_rad(SPIN_DEG.y) * delta)
	if _ring != null:
		_ring.rotate_z(deg_to_rad(SPIN_DEG.y) * delta)
