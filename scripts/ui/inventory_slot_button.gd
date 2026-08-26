class_name InventorySlotButton
extends Button

## Inventory cell using Control's built-in drag-and-drop API.

const PlayerInventoryScript := preload("res://scripts/inventory/player_inventory.gd")

const _SLOT_NORMAL := Color(0.14, 0.12, 0.22, 0.95)
const _SLOT_HOTBAR := Color(0.18, 0.16, 0.28, 0.95)

var slot_index := 0
var inventory: Node


func setup(inv: Node, index: int) -> void:
	inventory = inv
	slot_index = index
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(96, 72)
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	clip_text = true
	refresh()


func refresh() -> void:
	var item_id := _item_id()
	var label := slot_index + 1
	var item_name := _display_name(item_id)
	text = "%d\n—" % label if item_name.is_empty() else "%d\n%s" % [label, item_name]
	var style := StyleBoxFlat.new()
	style.bg_color = (
		_SLOT_HOTBAR if slot_index < PlayerInventoryScript.HOTBAR_COUNT else _SLOT_NORMAL
	)
	style.set_corner_radius_all(8)
	UiPalette.apply_outline(style, true, UiPalette.Swatch.BRONZE, 1)
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_font_size_override("font_size", 13)


func _get_drag_data(_at_position: Vector2) -> Variant:
	var item_id := _item_id()
	if item_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = _display_name(item_id)
	preview.add_theme_font_size_override("font_size", 14)
	preview.add_theme_color_override("font_color", Color(0.92, 0.96, 1, 1))
	set_drag_preview(preview)
	return {"type": "inventory_slot", "slot": slot_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = data
	if str(payload.get("type", "")) != "inventory_slot":
		return false
	var from_index := int(payload.get("slot", -1))
	return from_index >= 0 and from_index < PlayerInventoryScript.SLOT_COUNT


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_at_position, data) or inventory == null:
		return
	if not inventory.has_method("swap_slots"):
		return
	var from_index := int((data as Dictionary).get("slot", -1))
	if from_index == slot_index:
		return
	inventory.call("swap_slots", from_index, slot_index)


func _item_id() -> String:
	if inventory == null or not inventory.has_method("get_slot"):
		return ""
	return str(inventory.call("get_slot", slot_index))


func _display_name(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	if inventory != null and inventory.has_method("display_name"):
		return str(inventory.call("display_name", item_id))
	return item_id.capitalize()
