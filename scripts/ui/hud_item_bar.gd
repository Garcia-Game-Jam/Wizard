class_name HudItemBar
extends HBoxContainer

## Compact item hotbar matching the spell-slot HUD.

const PlayerInventoryScript := preload("res://scripts/inventory/player_inventory.gd")
const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")
const HudSpellBarScript := preload("res://scripts/ui/hud_spell_bar.gd")

var _inventory: Node
var _cells: Array[PanelContainer] = []
var _key_icons: Array[TextureRect] = []
var _key_labels: Array[Label] = []
var _name_labels: Array[Label] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", HudSpellBarScript.SLOT_GAP)
	_build()


static func bar_width() -> float:
	var n := float(PlayerInventoryScript.HOTBAR_COUNT)
	return (
		HudSpellBarScript.SLOT_SIZE.x * n
		+ float(HudSpellBarScript.SLOT_GAP) * maxf(n - 1.0, 0.0)
	)


func configure(inventory: Node) -> void:
	_inventory = inventory
	refresh()


func refresh() -> void:
	if _cells.is_empty():
		return
	for i in _cells.size():
		var action := "hotbar_%d" % (i + 1)
		InputPromptScript.fill_bind_views(
			_key_icons[i], _key_labels[i], action, str(i + 1)
		)
		var item_id := ""
		if _inventory != null and _inventory.has_method("get_slot"):
			item_id = str(_inventory.call("get_slot", i))
		var item_name := ""
		if not item_id.is_empty() and _inventory != null and _inventory.has_method("display_name"):
			item_name = str(_inventory.call("display_name", item_id))
		elif not item_id.is_empty():
			item_name = item_id.capitalize()
		_name_labels[i].text = item_name
		_apply_slot_style(_cells[i], item_id.is_empty())


func _build() -> void:
	for i in PlayerInventoryScript.HOTBAR_COUNT:
		_add_slot()


func _add_slot() -> void:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = HudSpellBarScript.SLOT_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var icon := InputPromptScript.make_hud_icon(18.0)
	icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	icon.anchor_right = 0.0
	icon.anchor_bottom = 0.0
	icon.offset_left = 3
	icon.offset_top = 3
	icon.offset_right = 21
	icon.offset_bottom = 21
	stack.add_child(icon)
	var key := Label.new()
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.set_anchors_preset(Control.PRESET_FULL_RECT)
	key.offset_left = 4
	key.offset_top = 3
	key.offset_right = -4
	key.offset_bottom = -4
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	key.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	key.add_theme_font_size_override("font_size", 10)
	key.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	stack.add_child(key)
	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.offset_left = 3
	name_label.offset_top = 18
	name_label.offset_right = -3
	name_label.offset_bottom = -4
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(name_label)
	cell.add_child(stack)
	add_child(cell)
	_cells.append(cell)
	_key_icons.append(icon)
	_key_labels.append(key)
	_name_labels.append(name_label)


func _apply_slot_style(cell: PanelContainer, empty: bool) -> void:
	cell.add_theme_stylebox_override("panel", UiPalette.hud_slot_style(false, empty))
