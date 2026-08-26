class_name InputPrompt
extends RefCounted

## Builds HUD prompts from InputMap so rebinding updates the displayed key.

const _KM_DIR := "res://assets/ui/input_prompts/keyboard_mouse/"
const _XB_DIR := "res://assets/ui/input_prompts/xbox/"

const _MOUSE_STEMS := {
	MOUSE_BUTTON_LEFT: "mouse_left",
	MOUSE_BUTTON_RIGHT: "mouse_right",
	MOUSE_BUTTON_MIDDLE: "mouse_scroll",
	MOUSE_BUTTON_WHEEL_UP: "mouse_scroll_up",
	MOUSE_BUTTON_WHEEL_DOWN: "mouse_scroll_down",
	MOUSE_BUTTON_WHEEL_LEFT: "mouse_horizontal",
	MOUSE_BUTTON_WHEEL_RIGHT: "mouse_horizontal",
	MOUSE_BUTTON_XBUTTON1: "mouse_side",
	MOUSE_BUTTON_XBUTTON2: "mouse_side",
}

const _JOY_BUTTON_STEMS := {
	JOY_BUTTON_A: "xbox_button_a",
	JOY_BUTTON_B: "xbox_button_b",
	JOY_BUTTON_X: "xbox_button_x",
	JOY_BUTTON_Y: "xbox_button_y",
	JOY_BUTTON_BACK: "xbox_button_view",
	JOY_BUTTON_GUIDE: "xbox_guide",
	JOY_BUTTON_START: "xbox_button_menu",
	JOY_BUTTON_LEFT_STICK: "xbox_stick_l_press",
	JOY_BUTTON_RIGHT_STICK: "xbox_stick_r_press",
	JOY_BUTTON_LEFT_SHOULDER: "xbox_lb",
	JOY_BUTTON_RIGHT_SHOULDER: "xbox_rb",
	JOY_BUTTON_DPAD_UP: "xbox_dpad_up",
	JOY_BUTTON_DPAD_DOWN: "xbox_dpad_down",
	JOY_BUTTON_DPAD_LEFT: "xbox_dpad_left",
	JOY_BUTTON_DPAD_RIGHT: "xbox_dpad_right",
	JOY_BUTTON_MISC1: "xbox_button_share",
}

const _JOY_AXIS_STEMS := {
	JOY_AXIS_LEFT_X: "xbox_stick_l_horizontal",
	JOY_AXIS_LEFT_Y: "xbox_stick_l_vertical",
	JOY_AXIS_RIGHT_X: "xbox_stick_r_horizontal",
	JOY_AXIS_RIGHT_Y: "xbox_stick_r_vertical",
	JOY_AXIS_TRIGGER_LEFT: "xbox_lt",
	JOY_AXIS_TRIGGER_RIGHT: "xbox_rt",
}

const _KEY_STEMS := {
	KEY_SPACE: "keyboard_space",
	KEY_ESCAPE: "keyboard_escape",
	KEY_TAB: "keyboard_tab",
	KEY_BACKSPACE: "keyboard_backspace",
	KEY_ENTER: "keyboard_enter",
	KEY_KP_ENTER: "keyboard_numpad_enter",
	KEY_SHIFT: "keyboard_shift",
	KEY_CTRL: "keyboard_ctrl",
	KEY_META: "keyboard_win",
	KEY_ALT: "keyboard_alt",
	KEY_CAPSLOCK: "keyboard_capslock",
	KEY_INSERT: "keyboard_insert",
	KEY_DELETE: "keyboard_delete",
	KEY_HOME: "keyboard_home",
	KEY_END: "keyboard_end",
	KEY_PAGEUP: "keyboard_page_up",
	KEY_PAGEDOWN: "keyboard_page_down",
	KEY_UP: "keyboard_arrow_up",
	KEY_DOWN: "keyboard_arrow_down",
	KEY_LEFT: "keyboard_arrow_left",
	KEY_RIGHT: "keyboard_arrow_right",
	KEY_MINUS: "keyboard_minus",
	KEY_EQUAL: "keyboard_equals",
	KEY_BRACKETLEFT: "keyboard_bracket_open",
	KEY_BRACKETRIGHT: "keyboard_bracket_close",
	KEY_BACKSLASH: "keyboard_slash_back",
	KEY_SEMICOLON: "keyboard_semicolon",
	KEY_APOSTROPHE: "keyboard_apostrophe",
	KEY_QUOTELEFT: "keyboard_tilde",
	KEY_COMMA: "keyboard_comma",
	KEY_PERIOD: "keyboard_period",
	KEY_SLASH: "keyboard_slash_forward",
	KEY_PRINT: "keyboard_printscreen",
	KEY_SCROLLLOCK: "keyboard_scroll_lock",
	KEY_PAUSE: "keyboard_pause",
	KEY_NUMLOCK: "keyboard_numlock",
	KEY_KP_ADD: "keyboard_numpad_plus",
	KEY_KP_SUBTRACT: "keyboard_minus",
	KEY_KP_MULTIPLY: "keyboard_asterisk",
	KEY_KP_DIVIDE: "keyboard_slash_forward",
}

static var _texture_cache: Dictionary = {}
static var _trimmed_cache: Dictionary = {}


static func action_label(action_name: String, fallback: String = "?") -> String:
	var events := InputMap.action_get_events(action_name)
	for event in events:
		if event == null:
			continue
		var text := _event_label(event)
		if not text.is_empty():
			return text
	return fallback


static func action_texture(action_name: String) -> Texture2D:
	var events := InputMap.action_get_events(action_name)
	for event in events:
		if event == null:
			continue
		var tex := texture_for_event(event)
		if tex != null:
			return tex
	return null


static func texture_for_event(event: InputEvent) -> Texture2D:
	var path := texture_path_for_event(event)
	if path.is_empty():
		return null
	return _load_texture(path)


static func texture_path_for_event(event: InputEvent) -> String:
	var stem := _event_stem(event)
	if stem.is_empty():
		return ""
	var folder := _KM_DIR
	if stem.begins_with("xbox_") or stem.begins_with("controller_"):
		folder = _XB_DIR
	return folder + stem + ".png"


static func fill_bind_views(
	icon: TextureRect, label: Label, action_name: String, fallback: String = "?"
) -> void:
	var tex := trimmed_texture(action_texture(action_name))
	if icon != null:
		icon.texture = tex
		icon.visible = tex != null
	if label == null:
		return
	if tex != null:
		label.text = ""
		label.visible = false
		return
	label.visible = true
	label.text = action_label(action_name, fallback)


static func trimmed_texture(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var key := tex.resource_path
	if key.is_empty():
		key = str(tex.get_instance_id())
	if _trimmed_cache.has(key):
		return _trimmed_cache[key] as Texture2D
	var image := tex.get_image()
	if image == null:
		_trimmed_cache[key] = tex
		return tex
	if image.is_compressed():
		image.decompress()
	var used := image.get_used_rect()
	var fitted := tex
	if used.size.x > 0 and used.size.y > 0:
		fitted = ImageTexture.create_from_image(image.get_region(used))
	_trimmed_cache[key] = fitted
	return fitted


static func make_hud_icon(size_px: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


static func _event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code := (
			key_event.physical_keycode
			if key_event.physical_keycode != 0
			else key_event.keycode
		)
		if code != 0:
			return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
	return _shorten_as_text(event.as_text())


static func _shorten_as_text(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return ""
	var dash_idx := trimmed.find(" - ")
	if dash_idx >= 0:
		trimmed = trimmed.substr(0, dash_idx).strip_edges()
	var paren_idx := trimmed.find(" (")
	if paren_idx >= 0:
		trimmed = trimmed.substr(0, paren_idx).strip_edges()
	return trimmed


static func bracket(action_name: String, fallback: String = "?") -> String:
	return "[%s]" % action_label(action_name, fallback)


static func with_action(action_name: String, message: String, fallback: String = "?") -> String:
	return "%s %s" % [message, bracket(action_name, fallback)]


static func _event_stem(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		return str(
			_MOUSE_STEMS.get((event as InputEventMouseButton).button_index, "")
		)
	if event is InputEventKey:
		return _key_stem(event as InputEventKey)
	if event is InputEventJoypadButton:
		return str(
			_JOY_BUTTON_STEMS.get((event as InputEventJoypadButton).button_index, "")
		)
	if event is InputEventJoypadMotion:
		return str(_JOY_AXIS_STEMS.get((event as InputEventJoypadMotion).axis, ""))
	return ""


static func _key_stem(event: InputEventKey) -> String:
	var code := (
		event.physical_keycode if event.physical_keycode != 0 else event.keycode
	)
	var stem := ""
	if code == KEY_NONE or code == 0:
		stem = ""
	elif _KEY_STEMS.has(code):
		stem = str(_KEY_STEMS[code])
	elif code >= KEY_A and code <= KEY_Z:
		stem = "keyboard_%s" % String.chr(code).to_lower()
	elif code >= KEY_0 and code <= KEY_9:
		stem = "keyboard_%s" % String.chr(code)
	elif code >= KEY_F1 and code <= KEY_F12:
		stem = "keyboard_f%d" % (int(code) - int(KEY_F1) + 1)
	return stem


static func _load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			tex = ImageTexture.create_from_image(image)
	_texture_cache[path] = tex
	return tex
