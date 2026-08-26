class_name SpellSlotButton
extends Button

## Tab-menu spell cell using Control's built-in drag-and-drop API.

const SpellHotbarScript := preload("res://scripts/spells/spell_hotbar.gd")
const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")

const _SLOT_EMPTY := Color(0.14, 0.12, 0.22, 0.95)
const _SLOT_FILLED := Color(0.18, 0.16, 0.30, 0.95)

var slot_index := 0
var hotbar: Node


func setup(bar: Node, index: int) -> void:
	hotbar = bar
	slot_index = index
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(120, 72)
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	refresh()


func refresh() -> void:
	var spell_id := _spell_id()
	var spell_name := _display_name(spell_id)
	var key := _slot_key_label()
	if spell_name.is_empty():
		text = key
	else:
		text = "%s\n%s" % [key, spell_name]
	var style := StyleBoxFlat.new()
	style.bg_color = _SLOT_FILLED if not spell_id.is_empty() else _SLOT_EMPTY
	style.set_corner_radius_all(6)
	UiPalette.apply_outline(style, true, UiPalette.Swatch.BRONZE, 1)
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_font_size_override("font_size", 13)


func _get_drag_data(_at_position: Vector2) -> Variant:
	var spell_id := _spell_id()
	if spell_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = _display_name(spell_id)
	preview.add_theme_font_size_override("font_size", 14)
	preview.add_theme_color_override("font_color", Color(0.92, 0.96, 1, 1))
	set_drag_preview(preview)
	return {"type": "spell_slot", "slot": slot_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = data
	if str(payload.get("type", "")) != "spell_slot":
		return false
	var from_index := int(payload.get("slot", -1))
	return from_index >= 0 and from_index < SpellHotbarScript.SLOT_COUNT


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_at_position, data) or hotbar == null:
		return
	if not hotbar.has_method("swap_slots"):
		return
	var from_index := int((data as Dictionary).get("slot", -1))
	if from_index == slot_index:
		return
	hotbar.call("swap_slots", from_index, slot_index)


func _spell_id() -> String:
	if hotbar == null or not hotbar.has_method("get_slot"):
		return ""
	return str(hotbar.call("get_slot", slot_index))


func _display_name(spell_id: String) -> String:
	if spell_id.is_empty():
		return ""
	if hotbar != null and hotbar.has_method("display_name"):
		return str(hotbar.call("display_name", spell_id))
	return spell_id.capitalize()


func _slot_key_label() -> String:
	if slot_index < 0 or slot_index >= SpellHotbarScript.SLOT_ACTIONS.size():
		return "?"
	var action := SpellHotbarScript.SLOT_ACTIONS[slot_index]
	return InputPromptScript.action_label(action, "?")
