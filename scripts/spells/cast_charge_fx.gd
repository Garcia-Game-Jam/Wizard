class_name CastChargeFx
extends Node3D

## Wand-tip charge visual. Each spell can instance its own scene from SpellDefinition.

const START_SCALE := 0.02


func setup_cast_charge(spell_color: Color, layers: int) -> void:
	_build(spell_color)
	_apply_layers(layers)
	scale = Vector3.ONE * START_SCALE


func set_cast_charge_progress(t: float) -> void:
	var p := clampf(t, 0.0, 1.0)
	scale = Vector3.ONE * lerpf(START_SCALE, 1.0, p)
	_apply_progress(p)


func tick(_delta: float) -> void:
	pass


func _build(_spell_color: Color) -> void:
	pass


func _apply_progress(_p: float) -> void:
	pass


func _local_radius(world_m: float) -> float:
	var gs := global_transform.basis.get_scale()
	return world_m / maxf(absf(gs.x), 0.001)


func _apply_layers(layers: int) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.layers = layers
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
