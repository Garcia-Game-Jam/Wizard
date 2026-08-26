@tool
class_name MonsterAbilityPlaceholder
extends Node3D

## Authored placeholder ability under Monster/Abilities.
## Inspector Preview Cast plays ephemeral local FX — no damage / AI yet.

const PREVIEW_DURATION_SEC := 0.85
const PREVIEW_MAX_RADIUS := 1.35

@export var ability_id: String = ""
@export var display_name: String = "Ability"
@export_multiline var description: String = ""
@export_range(0.0, 60.0, 0.1) var cooldown_sec: float = 4.0
@export var telegraph_color: Color = Color(0.9, 0.45, 0.2, 1.0)
## Forward offset for lunge-style telegraphs (local -Z).
@export_range(0.0, 3.0, 0.05) var forward_offset: float = 0.0
@export_range(0.2, 3.0, 0.05) var preview_radius: float = PREVIEW_MAX_RADIUS

@export_tool_button("Preview Cast", "Callable")
var preview_cast_action := preview_cast

var _preview_bucket: Node3D = null
var _preview_tween: Tween = null


func preview_cast() -> void:
	if not is_inside_tree():
		return
	_clear_preview()
	_preview_bucket = Node3D.new()
	_preview_bucket.name = "CastPreview"
	add_child(_preview_bucket)
	if Engine.is_editor_hint() and get_tree() != null:
		var edited := get_tree().edited_scene_root
		if edited != null:
			_preview_bucket.owner = edited
	_preview_bucket.position = Vector3(0.0, 0.45, -forward_offset)

	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b, 0.55)
	mat.emission_enabled = true
	mat.emission = telegraph_color
	mat.emission_energy_multiplier = 2.8
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_bucket.add_child(sphere)

	var light := OmniLight3D.new()
	light.light_color = telegraph_color
	light.light_energy = 3.2
	light.omni_range = preview_radius * 1.4
	light.shadow_enabled = false
	_preview_bucket.add_child(light)

	if Engine.is_editor_hint() and get_tree() != null:
		var root := get_tree().edited_scene_root
		if root != null:
			sphere.owner = root
			light.owner = root

	_preview_tween = create_tween()
	_preview_tween.set_parallel(true)
	_preview_tween.tween_property(
		sphere, "scale", Vector3.ONE * (preview_radius / 0.12), PREVIEW_DURATION_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_preview_tween.tween_property(
		mat, "albedo_color:a", 0.0, PREVIEW_DURATION_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_preview_tween.tween_property(
		light, "light_energy", 0.0, PREVIEW_DURATION_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_preview_tween.chain().tween_callback(_clear_preview)


func _clear_preview() -> void:
	if _preview_tween != null and is_instance_valid(_preview_tween):
		_preview_tween.kill()
	_preview_tween = null
	if _preview_bucket != null and is_instance_valid(_preview_bucket):
		_preview_bucket.queue_free()
	_preview_bucket = null


func _exit_tree() -> void:
	_clear_preview()
