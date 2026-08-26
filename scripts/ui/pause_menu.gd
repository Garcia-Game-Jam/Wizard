class_name PauseMenu
extends CanvasLayer

signal quit_to_menu_requested

var _paused := false
var _spellbook_was_open := false

@onready var _menu_panel: Control = $MenuPanel
@onready var _settings_panel: SettingsPanel = $SettingsPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _end_game_button: Button = %EndGameButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.is_editor_hint():
		visible = false
	_menu_panel.visible = true
	$Dimmer.color = UiPalette.SCRIM
	_resume_button.pressed.connect(_on_resume_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_end_game_button.pressed.connect(_on_end_game_pressed)
	_settings_panel.closed.connect(_on_settings_closed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings_panel.is_open():
		_settings_panel.close_panel()
		get_viewport().set_input_as_handled()
		return
	## Prefer closing the in-match player menu / summon book over opening pause.
	if _is_player_menu_open():
		_close_player_menu()
		get_viewport().set_input_as_handled()
		return
	if _is_monster_book_busy():
		_cancel_monster_book()
		get_viewport().set_input_as_handled()
		return
	if _paused:
		resume()
	else:
		pause()
	get_viewport().set_input_as_handled()


func is_paused() -> bool:
	return _paused


func pause() -> void:
	if _paused:
		return
	_paused = true
	visible = true
	_menu_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_spellbook_was_open = _is_spellbook_open()
	if _is_player_menu_open():
		_close_player_menu()
	if _spellbook_was_open:
		_close_spellbook()
	_cancel_casting()


func resume() -> void:
	if not _paused:
		return
	if _settings_panel.is_open():
		_settings_panel.close_panel()
	_paused = false
	visible = false
	get_tree().paused = false
	if _spellbook_was_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume_pressed() -> void:
	resume()


func _on_settings_pressed() -> void:
	_menu_panel.visible = false
	_settings_panel.open()


func _on_settings_closed() -> void:
	if _paused:
		_menu_panel.visible = true


func _on_end_game_pressed() -> void:
	if _settings_panel.is_open():
		_settings_panel.close_panel()
	get_tree().paused = false
	_paused = false
	visible = false
	quit_to_menu_requested.emit()


func _cancel_casting() -> void:
	var session: Node = get_tree().get_first_node_in_group("casting_session")
	if session != null and session.has_method("cancel"):
		session.cancel()


func _is_player_menu_open() -> bool:
	var hud: Node = get_tree().get_first_node_in_group("game_hud")
	if hud != null and hud.has_method("is_player_menu_open"):
		return bool(hud.call("is_player_menu_open"))
	return false


func _close_player_menu() -> void:
	var hud: Node = get_tree().get_first_node_in_group("game_hud")
	if hud != null and hud.has_method("close_player_menu"):
		hud.call("close_player_menu")


func _is_monster_book_busy() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("player"):
		var book := node.get_node_or_null("MonsterBook")
		if book != null and book.has_method("is_busy") and bool(book.call("is_busy")):
			return true
	return false


func _cancel_monster_book() -> void:
	var hud: Node = get_tree().get_first_node_in_group("game_hud")
	if hud != null and hud.has_method("close_monster_book"):
		hud.call("close_monster_book")
		return
	for node in get_tree().get_nodes_in_group("player"):
		var book := node.get_node_or_null("MonsterBook")
		if book != null and book.has_method("cancel_all"):
			book.call("cancel_all")


func _is_spellbook_open() -> bool:
	var hud: Node = get_tree().get_first_node_in_group("game_hud")
	if hud != null and hud.has_method("is_spellbook_open"):
		return hud.is_spellbook_open()
	return false


func _close_spellbook() -> void:
	var hud: Node = get_tree().get_first_node_in_group("game_hud")
	if hud != null and hud.has_method("close_spellbook"):
		hud.close_spellbook()