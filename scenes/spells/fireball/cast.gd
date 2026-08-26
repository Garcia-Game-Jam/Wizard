class_name FireballCastCharge
extends CastChargeFx

## Fire-noise core + additive shell at the wand tip.

const RADIUS_M := 0.0105
const BUBBLE_SPIN_DEG := Vector3(52.0, 88.0, 24.0)
const RIM_SPIN_DEG := Vector3(-40.0, -96.0, 30.0)

var _bubble: MeshInstance3D
var _rim: MeshInstance3D
var _core_mat: StandardMaterial3D
var _shell_mat: StandardMaterial3D


func _build(_spell_color: Color) -> void:
	_bubble = MeshInstance3D.new()
	_bubble.name = "Bubble"
	_rim = MeshInstance3D.new()
	_rim.name = "Rim"
	add_child(_bubble)
	add_child(_rim)
	FireballParticles.configure_wand_charge_fireball(
		_bubble, _rim, _local_radius(RADIUS_M)
	)
	_core_mat = _bubble.material_override as StandardMaterial3D
	_shell_mat = _rim.material_override as StandardMaterial3D


func _apply_progress(p: float) -> void:
	FireballParticles.apply_wand_charge_fire_progress(_core_mat, _shell_mat, p)


func tick(delta: float) -> void:
	if _bubble != null:
		_bubble.rotate_x(deg_to_rad(BUBBLE_SPIN_DEG.x) * delta)
		_bubble.rotate_y(deg_to_rad(BUBBLE_SPIN_DEG.y) * delta)
		_bubble.rotate_z(deg_to_rad(BUBBLE_SPIN_DEG.z) * delta)
	if _rim != null:
		_rim.rotate_x(deg_to_rad(RIM_SPIN_DEG.x) * delta)
		_rim.rotate_y(deg_to_rad(RIM_SPIN_DEG.y) * delta)
		_rim.rotate_z(deg_to_rad(RIM_SPIN_DEG.z) * delta)
	FireballParticles.scroll_wand_charge_fire(_core_mat, delta)
