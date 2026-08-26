extends Control

## Main menu screen (Host / Join / Settings / Exit). Navigation is owned by GameApp.

signal host_pressed()
signal join_pressed()
signal settings_pressed()

const UiScaleScript := preload("res://scripts/ui/ui_scale.gd")

const TITLE_FONT_BASE := 48
const BUTTON_FONT_BASE := 20
const BUTTON_WIDTH_BASE := 280.0
const BUTTON_HEIGHT_BASE := 64.0
const VBOX_SEPARATION_BASE := 18

@onready var _center_container: CenterContainer = $CenterContainer
@onready var _menu_vbox: VBoxContainer = $CenterContainer/VBoxContainer
@onready var _title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var _play_button: Button = $CenterContainer/VBoxContainer/PlayButton
@onready var _join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var _settings_button: Button = $CenterContainer/VBoxContainer/SettingsButton
@onready var _exit_button: Button = $CenterContainer/VBoxContainer/ExitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$Background.color = UiPalette.BACKGROUND_DEEP
	_play_button.pressed.connect(func() -> void: host_pressed.emit())
	_join_button.pressed.connect(func() -> void: join_pressed.emit())
	_settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	_exit_button.pressed.connect(_on_exit_pressed)
	get_viewport().size_changed.connect(_apply_menu_layout)
	_apply_menu_layout()


func set_menu_visible(show_buttons: bool) -> void:
	_center_container.visible = show_buttons
	if show_buttons:
		_apply_menu_layout()


func _apply_menu_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var button_width := UiScaleScript.scaled(BUTTON_WIDTH_BASE, viewport_size, 160.0)
	var button_height := UiScaleScript.scaled(BUTTON_HEIGHT_BASE, viewport_size, 36.0)
	var button_font := UiScaleScript.scaled(float(BUTTON_FONT_BASE), viewport_size, 14.0)
	var title_font := UiScaleScript.scaled(float(TITLE_FONT_BASE), viewport_size, 28.0)
	var separation := UiScaleScript.scaled(float(VBOX_SEPARATION_BASE), viewport_size, 10.0)

	_menu_vbox.add_theme_constant_override("separation", separation)
	_title_label.add_theme_font_size_override("font_size", title_font)

	for button in [_play_button, _join_button, _settings_button, _exit_button]:
		button.add_theme_font_size_override("font_size", button_font)
		button.custom_minimum_size = Vector2(button_width, button_height)


func _on_exit_pressed() -> void:
	SteamService.request_app_quit()
