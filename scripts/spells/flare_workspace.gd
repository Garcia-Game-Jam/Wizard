@tool
extends Node3D

## Flare look-dev studio — select FlareWorkspace root in scenes/spells/flare_workspace.tscn.
## Tune the instanced Flare child, then Launch Flare on this root for flight preview.

const FlareEffectScript := preload("res://scripts/spells/flare_effect.gd")
const FlareSpell := preload("res://scenes/spells/evaluating/flare/flare.tres")

@export_group("Launch preview")
## Hide the lookdev Flare instance while a launch preview rocket is in the air.
@export var hide_lookdev_during_cast := true
## Extra offset along the shot direction from the wand cast origin.
@export_range(0.0, 1.5, 0.05) var tip_forward_nudge: float = 0.0
## Launch elevation (5 = nearly flat, 85 = nearly straight up). Shot heads toward -Z.
@export_range(5.0, 85.0, 1.0) var launch_pitch_deg: float = 35.0
@export_tool_button("Launch Flare", "Callable")
var launch_flare_action := launch_flare_preview
@export_tool_button("Clear Launch", "Callable")
var clear_launch_action := clear_launch_preview

var _preview_flare: FlareEffect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bucket("LaunchPreview")
	_refresh_lookdev_visibility()
	_force_wand_tip_visible()


func launch_flare_preview() -> void:
	if not is_inside_tree():
		return
	clear_launch_preview()
	var wand := _wand()
	var origin := Vector3(0.15, 1.05, 1.15)
	if wand != null:
		origin = _resolve_cast_origin(wand)
		if wand.has_method("play_cast_success"):
			var spell_for_fx: SpellDefinition = null if Engine.is_editor_hint() else FlareSpell
			wand.call("play_cast_success", spell_for_fx, true)
	var direction := _preview_launch_direction()
	origin += direction * tip_forward_nudge
	var bucket := _ensure_bucket("LaunchPreview")
	bucket.process_mode = Node.PROCESS_MODE_ALWAYS
	var template := _lookdev_flare()
	var burn_sec := FlareEffectScript.DEFAULT_DURATION_SEC
	if template != null:
		burn_sec = template.duration_sec
	_preview_flare = FlareEffectScript.spawn_launched(
		bucket, origin, direction, burn_sec, true, null, template
	)
	if _preview_flare != null:
		_preview_flare.process_mode = Node.PROCESS_MODE_ALWAYS
		for child in _preview_flare.get_children():
			if child is GPUParticles3D:
				child.process_mode = Node.PROCESS_MODE_ALWAYS
		if Engine.is_editor_hint():
			var root := get_tree().edited_scene_root
			if root != null:
				_preview_flare.owner = root
		_preview_flare.tree_exited.connect(_on_preview_exited, CONNECT_ONE_SHOT)
	_refresh_lookdev_visibility()


func _preview_launch_direction() -> Vector3:
	var pitch := deg_to_rad(clampf(launch_pitch_deg, 5.0, 85.0))
	return Vector3(0.0, sin(pitch), -cos(pitch)).normalized()


func clear_launch_preview() -> void:
	_clear_bucket("LaunchPreview")
	_preview_flare = null
	_refresh_lookdev_visibility()


func _on_preview_exited() -> void:
	_preview_flare = null
	_refresh_lookdev_visibility()


func _wand() -> Node3D:
	return get_node_or_null("Wand") as Node3D


func _lookdev_flare() -> FlareEffect:
	return get_node_or_null("Flare") as FlareEffect


func _resolve_cast_origin(wand: Node3D) -> Vector3:
	var tip := wand.get_node_or_null("Model/CastOrigin") as Node3D
	if tip == null:
		tip = wand.get_node_or_null("CastOrigin") as Node3D
	if tip != null:
		return tip.global_position
	return wand.global_position


func _force_wand_tip_visible() -> void:
	var wand := _wand()
	if wand == null:
		return
	var tip := wand.get_node_or_null("Model/Tip") as Node3D
	if tip == null:
		tip = wand.get_node_or_null("Tip") as Node3D
	if tip != null:
		tip.visible = true


func _ensure_bucket(bucket_name: String) -> Node3D:
	var bucket := get_node_or_null(bucket_name) as Node3D
	if bucket != null:
		bucket.process_mode = Node.PROCESS_MODE_ALWAYS
		return bucket
	bucket = Node3D.new()
	bucket.name = bucket_name
	bucket.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bucket)
	if Engine.is_editor_hint():
		var root := get_tree().edited_scene_root
		if root != null:
			bucket.owner = root
	return bucket


func _clear_bucket(bucket_name: String) -> void:
	var bucket := get_node_or_null(bucket_name)
	if bucket == null:
		return
	for child in bucket.get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()


func _refresh_lookdev_visibility() -> void:
	var lookdev := _lookdev_flare()
	if lookdev == null:
		return
	var preview_live := _preview_flare != null and is_instance_valid(_preview_flare)
	lookdev.visible = not (hide_lookdev_during_cast and preview_live)
