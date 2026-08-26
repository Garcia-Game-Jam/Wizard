class_name SelectionStyle
extends RefCounted

## Shared selected/unselected styling for lobby toggle buttons.

static func style_choice(button: Button, selected: bool) -> void:
	button.disabled = false
	button.toggle_mode = false
	if selected:
		button.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72))
		button.add_theme_color_override("font_hover_color", Color(0.95, 0.90, 0.72))
		button.add_theme_color_override("font_pressed_color", Color(0.95, 0.90, 0.72))
		button.add_theme_stylebox_override(
			"normal",
			_make_stylebox(Color(0.16, 0.12, 0.08, 1), Color(0.86, 0.72, 0.34, 1))
		)
		button.add_theme_stylebox_override(
			"hover",
			_make_stylebox(Color(0.20, 0.16, 0.10, 1), Color(0.90, 0.78, 0.42, 1))
		)
		button.add_theme_stylebox_override(
			"pressed",
			_make_stylebox(Color(0.16, 0.12, 0.08, 1), Color(0.86, 0.72, 0.34, 1))
		)
	else:
		button.add_theme_color_override("font_color", Color(0.78, 0.74, 0.62))
		button.add_theme_color_override("font_hover_color", Color(0.95, 0.90, 0.72))
		button.add_theme_color_override("font_pressed_color", Color(0.95, 0.90, 0.72))
		button.add_theme_stylebox_override(
			"normal",
			_make_stylebox(Color(0.10, 0.08, 0.10, 1), Color(0.42, 0.36, 0.28, 1))
		)
		button.add_theme_stylebox_override(
			"hover",
			_make_stylebox(Color(0.14, 0.11, 0.10, 1), Color(0.82, 0.70, 0.38, 1))
		)
		button.add_theme_stylebox_override(
			"pressed",
			_make_stylebox(Color(0.14, 0.11, 0.10, 1), Color(0.82, 0.70, 0.38, 1))
		)


static func _make_stylebox(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style
