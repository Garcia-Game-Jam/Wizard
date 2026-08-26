class_name KeybindRow
extends HBoxContainer

## One remappable action: label and current bind.

signal rebind_pressed(action: String)

const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")

var action_name: String = ""

@onready var _label: Label = $Label
@onready var _icon: TextureRect = $BindWrap/Icon
@onready var _listen_label: Label = $BindWrap/ListenLabel
@onready var _bind_button: Button = $BindWrap/BindButton


func _ready() -> void:
	_flatten_bind_button()
	_bind_button.pressed.connect(func() -> void: rebind_pressed.emit(action_name))


func setup(action: String, display_label: String) -> void:
	action_name = action
	if _label != null:
		_label.text = display_label
	refresh()


func refresh() -> void:
	if _icon == null or _listen_label == null:
		return
	InputPromptScript.fill_bind_views(_icon, _listen_label, action_name, "—")


func set_listening(listening: bool) -> void:
	if _icon == null or _listen_label == null:
		return
	if listening:
		_icon.visible = false
		_listen_label.visible = true
		_listen_label.text = "Press a key…"
	else:
		refresh()


func set_conflict(is_conflict: bool) -> void:
	if _icon == null:
		return
	modulate = Color(1.0, 0.82, 0.35) if is_conflict else Color.WHITE


func _flatten_bind_button() -> void:
	if _bind_button == null:
		return
	var empty := StyleBoxEmpty.new()
	_bind_button.add_theme_stylebox_override("normal", empty)
	_bind_button.add_theme_stylebox_override("hover", empty)
	_bind_button.add_theme_stylebox_override("pressed", empty)
	_bind_button.add_theme_stylebox_override("disabled", empty)
	_bind_button.add_theme_stylebox_override("focus", empty)
	_bind_button.flat = true
	_bind_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
