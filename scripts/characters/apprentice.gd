class_name Apprentice
extends PlayableCharacter

## Snail-cursed apprentice — smoke trail footprint and wand casting UX.


func _on_player_initialized() -> void:
	var trail := get_node_or_null("PositionTrailRecorder")
	if trail != null and trail.has_method("setup"):
		trail.setup(self)
