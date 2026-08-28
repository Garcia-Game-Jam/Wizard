class_name GameOverOverlay
extends CanvasLayer

signal leave_requested

@onready var _stages_value: Label = %StagesValue
@onready var _kills_value: Label = %KillsValue
@onready var _deaths_value: Label = %DeathsValue
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.is_editor_hint():
		visible = false
	$Dimmer.color = UiPalette.SCRIM
	_leave_button.pressed.connect(_on_leave_pressed)


func show_run(stages_cleared: int, enemies_killed: int, deaths: int) -> void:
	_stages_value.text = str(maxi(stages_cleared, 0))
	_kills_value.text = str(maxi(enemies_killed, 0))
	_deaths_value.text = str(maxi(deaths, 0))
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_leave_pressed() -> void:
	leave_requested.emit()
