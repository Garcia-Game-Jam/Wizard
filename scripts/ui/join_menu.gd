@tool
class_name JoinMenu
extends Control

## Enter a lobby code and connect. The in-session room is [LobbyPanel].

signal closed
signal joined

var _busy: bool = false

@onready var _code_edit: LineEdit = $Panel/MarginContainer/VBox/RoomCodeEdit
@onready var _back_button: Button = $Panel/MarginContainer/VBox/FooterButtons/BackButton
@onready var _connect_button: Button = $Panel/MarginContainer/VBox/FooterButtons/ConnectButton


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = false
	_connect_button.pressed.connect(_try_connect)
	_back_button.pressed.connect(close_menu)
	_code_edit.text_submitted.connect(func(_text: String) -> void: _try_connect())
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.steam_lobby_invite_received.connect(_on_steam_lobby_invite_received)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	close_menu()
	get_viewport().set_input_as_handled()


func open() -> void:
	_busy = false
	visible = true
	_code_edit.text = ""
	_code_edit.placeholder_text = (
		"Steam lobby ID or IP:port"
		if SteamService.is_ready()
		else "IP:port or LAN port"
	)
	_set_busy(false)
	_code_edit.grab_focus()


func close_menu() -> void:
	if _busy:
		return
	visible = false
	closed.emit()


func _try_connect() -> void:
	if _busy:
		return
	var room_code := _code_edit.text.strip_edges()
	if room_code.is_empty():
		return
	_set_busy(true)
	var err := await NetworkManager.join_session(room_code, {})
	_set_busy(false)
	if err != OK:
		return
	visible = false
	joined.emit()


func _on_connection_failed(_message: String) -> void:
	_set_busy(false)


func _on_steam_lobby_invite_received(lobby_id: int) -> void:
	if not visible or _busy:
		return
	_code_edit.text = str(lobby_id)
	_connect_button.grab_focus()


func _set_busy(busy: bool) -> void:
	_busy = busy
	_back_button.disabled = busy
	_connect_button.disabled = busy
	_code_edit.editable = not busy
