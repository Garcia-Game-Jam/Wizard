@tool
extends Node3D

## Lit studio for fireball look-dev. Forces preview FX on the instanced Fireball.

@export var force_preview_fx: bool = true:
	set(value):
		force_preview_fx = value
		_apply_to_fireball()


func _ready() -> void:
	call_deferred("_apply_to_fireball")


func _apply_to_fireball() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var fireball := get_node_or_null("Fireball")
	if fireball == null:
		return
	if force_preview_fx:
		fireball.set("preview_smoke", true)
		fireball.set("preview_embers", true)
		fireball.set("preview_glow", true)
		fireball.set("animate_fire_texture", true)
