extends RefCounted

const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")


func run() -> int:
	var failures := 0
	failures += _test_middle_mouse_uses_scroll_glyph()
	failures += _test_left_right_mouse_glyphs()
	failures += _test_letter_key_glyph()
	failures += _test_xbox_button_glyph()
	failures += _test_spell_capture_texture_loads()
	failures += _test_space_glyph_stays_wide()
	return failures


func _test_middle_mouse_uses_scroll_glyph() -> int:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	var path := InputPromptScript.texture_path_for_event(event)
	if not path.ends_with("mouse_scroll.png"):
		push_error("Middle mouse should map to Kenney mouse_scroll.png, got %s" % path)
		return 1
	if InputPromptScript.texture_for_event(event) == null:
		push_error("Middle mouse glyph failed to load")
		return 1
	return 0


func _test_left_right_mouse_glyphs() -> int:
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	if not InputPromptScript.texture_path_for_event(left).ends_with("mouse_left.png"):
		push_error("Left mouse should map to mouse_left.png")
		return 1
	if not InputPromptScript.texture_path_for_event(right).ends_with("mouse_right.png"):
		push_error("Right mouse should map to mouse_right.png")
		return 1
	return 0


func _test_letter_key_glyph() -> int:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_Q
	var path := InputPromptScript.texture_path_for_event(event)
	if not path.ends_with("keyboard_q.png"):
		push_error("Q should map to keyboard_q.png, got %s" % path)
		return 1
	if InputPromptScript.texture_for_event(event) == null:
		push_error("keyboard_q.png failed to load")
		return 1
	return 0


func _test_xbox_button_glyph() -> int:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	var path := InputPromptScript.texture_path_for_event(event)
	if not path.ends_with("xbox_button_a.png"):
		push_error("Gamepad A should map to xbox_button_a.png, got %s" % path)
		return 1
	if InputPromptScript.texture_for_event(event) == null:
		push_error("xbox_button_a.png failed to load")
		return 1
	return 0


func _test_spell_capture_texture_loads() -> int:
	if not InputMap.has_action("spell_capture"):
		push_error("Expected spell_capture in InputMap")
		return 1
	var tex := InputPromptScript.action_texture("spell_capture")
	if tex == null:
		push_error("spell_capture should resolve to a Kenney prompt texture")
		return 1
	return 0


func _test_space_glyph_stays_wide() -> int:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	var raw := InputPromptScript.texture_for_event(event)
	var tex := InputPromptScript.trimmed_texture(raw)
	if tex == null:
		push_error("Space glyph failed to load")
		return 1
	if tex.get_width() <= tex.get_height():
		push_error(
			"Trimmed space key should be wider than tall, got %dx%d"
			% [tex.get_width(), tex.get_height()]
		)
		return 1
	return 0
