## Builds the Serious Wiz Biz Theme from UiPalette tokens.
## Edit colors in ui_palette.gd / palette.json, then rebuild via the editor dock
## or: godot --headless --path . --script res://tools/generate_ui_theme.gd
class_name UiThemeBuilder
extends RefCounted

const THEME_PATH := "res://resources/ui/serious_wiz_biz_theme.tres"


static func build() -> Theme:
	var theme := Theme.new()
	_apply_colors(theme)
	_apply_constants(theme)
	_apply_button(theme)
	_apply_panel(theme)
	_apply_label(theme)
	_apply_tab_container(theme)
	_apply_slider(theme)
	_apply_line_edit(theme)
	_apply_option_button(theme)
	_apply_check_button(theme)
	_apply_progress_bar(theme)
	_apply_separators(theme)
	return theme


static func save_theme(path: String = THEME_PATH) -> Error:
	var theme := build()
	return ResourceSaver.save(theme, path)


static func _flat(
	bg: Color,
	border: Color = Color(0, 0, 0, 0),
	border_w: int = 0,
	radius: int = 0,
	content: int = 0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(radius)
	if content > 0:
		box.set_content_margin_all(float(content))
	return box


static func _apply_colors(theme: Theme) -> void:
	theme.set_color("font_color", "Label", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	theme.set_color("font_color", "Button", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "Button", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "Button", UiPalette.TEXT_DISABLED)
	theme.set_color("font_focus_color", "Button", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_color", "TabBar", UiPalette.TEXT_MUTED)
	theme.set_color("font_selected_color", "TabBar", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_hovered_color", "TabBar", UiPalette.ACCENT_PRIMARY)
	theme.set_color("font_disabled_color", "TabBar", UiPalette.TEXT_DISABLED)
	theme.set_color("font_outline_color", "TabBar", Color(0, 0, 0, 0))
	theme.set_color("font_color", "LineEdit", UiPalette.TEXT_PRIMARY)
	theme.set_color("caret_color", "LineEdit", UiPalette.ACCENT_PRIMARY)
	theme.set_color("font_color", "OptionButton", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "OptionButton", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "OptionButton", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_color", "CheckButton", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "CheckButton", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "CheckButton", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "CheckButton", UiPalette.TEXT_DISABLED)


static func _apply_constants(theme: Theme) -> void:
	theme.set_constant("h_separation", "Button", 12)
	theme.set_constant("icon_max_width", "Button", 40)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_constant("h_separation", "TabBar", 16)


static func _apply_button(theme: Theme) -> void:
	var normal := _flat(
		UiPalette.BUTTON_FILL,
		UiPalette.BORDER_DEFAULT,
		UiPalette.PANEL_BORDER_WIDTH,
		UiPalette.BUTTON_CORNER_RADIUS,
		14
	)
	var hover := _flat(
		UiPalette.BUTTON_HOVER,
		UiPalette.BORDER_HOVER,
		UiPalette.PANEL_BORDER_WIDTH,
		UiPalette.BUTTON_CORNER_RADIUS,
		14
	)
	var pressed := _flat(
		UiPalette.BACKGROUND_DEEP,
		UiPalette.BORDER_DEFAULT,
		UiPalette.PANEL_BORDER_WIDTH,
		UiPalette.BUTTON_CORNER_RADIUS,
		14
	)
	var disabled := _flat(
		Color(UiPalette.BUTTON_FILL, 0.45),
		Color(UiPalette.BORDER_DEFAULT, 0.35),
		UiPalette.PANEL_BORDER_WIDTH,
		UiPalette.BUTTON_CORNER_RADIUS,
		14
	)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = UiPalette.BORDER_HOVER
	focus.border_width_left = 3
	focus.border_width_top = 3
	focus.border_width_right = 3
	focus.border_width_bottom = 3
	for type_name in ["Button", "ColorPickerButton"]:
		theme.set_stylebox("normal", type_name, normal)
		theme.set_stylebox("hover", type_name, hover)
		theme.set_stylebox("pressed", type_name, pressed)
		theme.set_stylebox("disabled", type_name, disabled)
		theme.set_stylebox("focus", type_name, focus)
	theme.set_color("font_color", "ColorPickerButton", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "ColorPickerButton", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "ColorPickerButton", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "ColorPickerButton", UiPalette.TEXT_DISABLED)
	theme.set_color("font_focus_color", "ColorPickerButton", UiPalette.TEXT_PRIMARY)

	## Filled CTA (e.g. Apply / Save)
	var primary_normal := _flat(
		UiPalette.ACCENT_PRIMARY,
		UiPalette.ACCENT_PRIMARY,
		0,
		UiPalette.BUTTON_CORNER_RADIUS,
		14
	)
	var primary_hover := _flat(
		UiPalette.BORDER_HOVER,
		UiPalette.BORDER_HOVER,
		0,
		UiPalette.BUTTON_CORNER_RADIUS,
		14
	)
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_color("font_color", "PrimaryButton", UiPalette.BACKGROUND_DEEP)
	theme.set_color("font_hover_color", "PrimaryButton", UiPalette.BACKGROUND_DEEP)
	theme.set_color("font_pressed_color", "PrimaryButton", UiPalette.BACKGROUND_DEEP)
	theme.set_stylebox("normal", "PrimaryButton", primary_normal)
	theme.set_stylebox("hover", "PrimaryButton", primary_hover)
	theme.set_stylebox("pressed", "PrimaryButton", primary_normal)
	theme.set_stylebox("disabled", "PrimaryButton", disabled)
	theme.set_stylebox("focus", "PrimaryButton", primary_hover)

	## Danger / dirty exit
	var danger := _flat(
		UiPalette.BUTTON_FILL,
		Color("eb3838"),
		UiPalette.PANEL_BORDER_WIDTH,
		UiPalette.BUTTON_CORNER_RADIUS,
		14
	)
	theme.set_type_variation("DangerButton", "Button")
	theme.set_stylebox("normal", "DangerButton", danger)
	theme.set_stylebox("hover", "DangerButton", danger)
	theme.set_stylebox("pressed", "DangerButton", danger)
	theme.set_stylebox("disabled", "DangerButton", disabled)
	theme.set_stylebox("focus", "DangerButton", danger)
	theme.set_color("font_color", "DangerButton", UiPalette.TEXT_PRIMARY)


static func _apply_panel(theme: Theme) -> void:
	var panel := UiPalette.panel_style()
	panel.set_content_margin_all(8.0)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var empty := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "TabContainer", empty)
	var track := _flat(UiPalette.BACKGROUND_DEEP, UiPalette.BORDER_DEFAULT, 1, 4, 2)
	theme.set_type_variation("BarTrack", "PanelContainer")
	theme.set_stylebox("panel", "BarTrack", track)
	theme.set_type_variation("HudSlot", "PanelContainer")
	theme.set_stylebox("panel", "HudSlot", UiPalette.hud_slot_style())


static func _apply_label(theme: Theme) -> void:
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_color("font_color", "TitleLabel", UiPalette.ACCENT_PRIMARY)
	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", UiPalette.TEXT_MUTED)
	theme.set_type_variation("CaptionLabel", "Label")
	theme.set_color("font_color", "CaptionLabel", UiPalette.TEXT_DISABLED)


static func _apply_tab_container(theme: Theme) -> void:
	var tab_unselected := _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 10)
	var tab_selected := _flat(Color(0, 0, 0, 0), UiPalette.ACCENT_PRIMARY, 0, 0, 10)
	tab_selected.border_width_bottom = 3
	tab_selected.border_color = UiPalette.ACCENT_PRIMARY
	var tab_hover := tab_unselected.duplicate() as StyleBoxFlat
	theme.set_stylebox("tab_unselected", "TabBar", tab_unselected)
	theme.set_stylebox("tab_selected", "TabBar", tab_selected)
	theme.set_stylebox("tab_hovered", "TabBar", tab_hover)
	theme.set_stylebox("tab_disabled", "TabBar", tab_unselected)
	theme.set_stylebox("button_highlight", "TabBar", StyleBoxEmpty.new())
	theme.set_color("font_selected_color", "TabContainer", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_hovered_color", "TabContainer", UiPalette.ACCENT_PRIMARY)
	theme.set_color("font_unselected_color", "TabContainer", UiPalette.TEXT_MUTED)
	theme.set_color("font_disabled_color", "TabContainer", UiPalette.TEXT_DISABLED)


static func _apply_slider(theme: Theme) -> void:
	var slider := _flat(UiPalette.BACKGROUND_DEEP, UiPalette.BORDER_DEFAULT, 1, 4, 0)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	theme.set_stylebox("slider", "HSlider", slider)
	var grabber_area := _flat(UiPalette.ACCENT_PRIMARY, Color(0, 0, 0, 0), 0, 4, 0)
	var grabber_hi := _flat(UiPalette.BORDER_HOVER, Color(0, 0, 0, 0), 0, 4, 0)
	theme.set_stylebox("grabber_area", "HSlider", grabber_area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_hi)
	theme.set_icon("grabber", "HSlider", _make_grabber_texture())
	theme.set_icon("grabber_highlight", "HSlider", _make_grabber_texture())


static func _make_grabber_texture() -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(14):
		for x in range(14):
			var dx := float(x) - 6.5
			var dy := float(y) - 6.5
			if dx * dx + dy * dy <= 36.0:
				img.set_pixel(x, y, UiPalette.ACCENT_PRIMARY)
	return ImageTexture.create_from_image(img)


static func _apply_line_edit(theme: Theme) -> void:
	var normal := _flat(
		UiPalette.BACKGROUND_DEEP,
		UiPalette.BORDER_DEFAULT,
		1,
		6,
		8
	)
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", normal)
	theme.set_stylebox("read_only", "LineEdit", normal)


static func _apply_option_button(theme: Theme) -> void:
	var normal := UiPalette.button_style()
	normal.set_content_margin_all(10.0)
	var hover := UiPalette.button_style(UiPalette.BUTTON_HOVER, UiPalette.BORDER_HOVER)
	hover.set_content_margin_all(10.0)
	theme.set_stylebox("normal", "OptionButton", normal)
	theme.set_stylebox("hover", "OptionButton", hover)
	theme.set_stylebox("pressed", "OptionButton", hover)
	theme.set_stylebox("disabled", "OptionButton", normal)
	theme.set_stylebox("focus", "OptionButton", hover)


static func _apply_check_button(theme: Theme) -> void:
	## Visual weight comes from MenuToggleSwitch where used; theme covers stock CheckButton.
	theme.set_color("font_color", "CheckBox", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "CheckBox", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "CheckBox", UiPalette.TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "CheckBox", UiPalette.TEXT_DISABLED)


static func _apply_progress_bar(theme: Theme) -> void:
	var bg := _flat(UiPalette.BACKGROUND_DEEP, UiPalette.BORDER_DEFAULT, 1, 4, 2)
	var fill := _flat(UiPalette.ACCENT_PRIMARY, Color(0, 0, 0, 0), 0, 3, 0)
	theme.set_stylebox("background", "ProgressBar", bg)
	theme.set_stylebox("fill", "ProgressBar", fill)
	var health_fill := _flat(UiPalette.HEALTH_FILL, Color(0, 0, 0, 0), 0, 3, 0)
	theme.set_type_variation("HealthBar", "ProgressBar")
	theme.set_stylebox("background", "HealthBar", bg)
	theme.set_stylebox("fill", "HealthBar", health_fill)
	theme.set_type_variation("ResourceBar", "ProgressBar")
	theme.set_stylebox("background", "ResourceBar", bg)
	theme.set_stylebox("fill", "ResourceBar", fill)


static func _apply_separators(theme: Theme) -> void:
	var sep := _flat(UiPalette.ACCENT_PRIMARY, Color(0, 0, 0, 0), 0, 0, 0)
	sep.content_margin_top = 1
	sep.content_margin_bottom = 1
	theme.set_stylebox("separator", "HSeparator", sep)
	theme.set_constant("separation", "HSeparator", 2)
