class_name PlayerPreview
extends RefCounted

## Editor spawn-slot / character preview helpers for Player.


static func should_use_preview_mode(character: Node) -> bool:
	if is_under_spawn_slot(character):
		return true
	if not character.is_inside_tree():
		return false
	var scene := character.get_tree().current_scene
	return scene != null and scene.has_meta("character_preview_scene")


static func is_under_spawn_slot(character: Node) -> bool:
	var node := character.get_parent()
	while node != null:
		if node.is_in_group("player_spawn_slot"):
			return true
		node = node.get_parent()
	return false


static func enter_editor_preview_mode(character: CharacterBody3D) -> void:
	character.process_mode = Node.PROCESS_MODE_DISABLED
	character.collision_layer = 0
	character.collision_mask = 0
	var sync := character.get_node_or_null("MultiplayerSynchronizer")
	if sync != null:
		sync.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := character.get_node_or_null("%FirstPersonCamera") as Camera3D
	if cam != null:
		cam.current = false
	if Engine.is_editor_hint():
		character.visible = true
		if character.has_method("_apply_character_color"):
			character.call("_apply_character_color", preview_tint(character))
	else:
		character.visible = false
		character.queue_free()


static func preview_tint(_character: Node) -> Color:
	return Color(0.25, 0.65, 0.95)
