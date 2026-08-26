class_name HudConjureTip
extends VBoxContainer

## Spell-capture bind glyph stacked over "New Spell".

const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")

var _icon: TextureRect
var _key: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 4)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(108, 64)
	_icon = InputPromptScript.make_hud_icon(25.0)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_icon)
	_key = Label.new()
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key.add_theme_font_size_override("font_size", 11)
	_key.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72, 1))
	_key.text = "MMB"
	add_child(_key)
	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size = Vector2(108, 0)
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color(0.78, 0.74, 0.62, 1))
	caption.text = "New Spell"
	add_child(caption)
	refresh()


func refresh() -> void:
	InputPromptScript.fill_bind_views(_icon, _key, "spell_capture", "MMB")
