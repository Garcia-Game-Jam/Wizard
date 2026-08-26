@tool
class_name LobbyPanel
extends Control

## In-session lobby. Edit [code]scenes/ui/lobby.tscn[/code]. Host chrome (network,
## voice, start) is hidden for guests. The join form is [code]scenes/ui/join.tscn[/code].

signal closed
signal start_requested
signal settings_requested

enum EditorLayout { HOST, GUEST }

const LobbyPlayerRowScene := preload("res://scenes/ui/scaffolding/lobby_player_row.tscn")
const ToggleSliderScript := preload("res://scripts/ui/scaffolding/toggle_slider.gd")
const NetworkManagerScript := preload("res://scripts/network/network_manager.gd")

@export var editor_layout: EditorLayout = EditorLayout.HOST:
	set(value):
		editor_layout = value
		if Engine.is_editor_hint() and is_node_ready():
			apply_editor_layout()

var _host_mode: bool = false
var _busy: bool = false
var _in_lobby: bool = false

@onready var _lobby_panel_root: PanelContainer = $Panel
@onready var _title_label: Label = $Panel/MarginContainer/VBox/TitleLabel
@onready var _room_code_host_row: HBoxContainer = (
	$Panel/MarginContainer/VBox/RoomCodeHostRow
)
@onready var _room_code_display: LineEdit = (
	$Panel/MarginContainer/VBox/RoomCodeHostRow/RoomCodeDisplay
)
@onready var _copy_room_code_button: Button = (
	$Panel/MarginContainer/VBox/RoomCodeHostRow/CopyRoomCodeButton
)
@onready var _invite_friends_button: Button = (
	$Panel/MarginContainer/VBox/RoomCodeHostRow/InviteFriendsButton
)
@onready var _host_transport_row: HBoxContainer = (
	$Panel/MarginContainer/VBox/HostTransportRow
)
@onready var _host_transport_slider: ToggleSliderScript = (
	$Panel/MarginContainer/VBox/HostTransportRow/HostTransportSlider
)
@onready var _players_section: VBoxContainer = $Panel/MarginContainer/VBox/PlayersSection
@onready var _player_list_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/PlayersSection/PlayerListScroll/PlayerListVBox
)
@onready var _lobby_voice_row: HBoxContainer = $Panel/MarginContainer/VBox/LobbyVoiceRow
@onready var _lobby_voice_switch: CheckButton = (
	$Panel/MarginContainer/VBox/LobbyVoiceRow/LobbyVoiceSwitch
)
@onready var _back_button: Button = $Panel/MarginContainer/VBox/FooterButtons/BackButton
@onready var _primary_button: Button = (
	$Panel/MarginContainer/VBox/FooterButtons/PrimaryButton
)


func _ready() -> void:
	if Engine.is_editor_hint():
		apply_editor_layout()
		return
	## Inherit GameApp Lobby state's process_mode (disabled while Match/MainMenu).
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = false
	_primary_button.pressed.connect(_on_primary_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_copy_room_code_button.pressed.connect(_on_copy_room_code_pressed)
	_invite_friends_button.pressed.connect(_on_invite_friends_pressed)
	_lobby_voice_switch.toggled.connect(_on_lobby_voice_toggled)
	if _host_transport_slider != null:
		_host_transport_slider.selected_changed.connect(_on_host_transport_selected)
	if not SteamService.api_initialized.is_connected(_on_steam_api_initialized):
		SteamService.api_initialized.connect(_on_steam_api_initialized)
	_refresh_transport_options()
	NetworkManager.status_changed.connect(_on_network_status)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.became_host.connect(_on_became_host)
	NetworkManager.joined_host.connect(_on_joined_host)
	NetworkManager.lobby_roster_changed.connect(_refresh_player_list)
	NetworkManager.lobby_roles_changed.connect(_refresh_player_list)
	NetworkManager.lobby_character_configs_changed.connect(_refresh_player_list)
	NetworkManager.session_ended.connect(_on_session_ended)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	settings_requested.emit()
	get_viewport().set_input_as_handled()


func apply_editor_layout() -> void:
	_host_mode = editor_layout == EditorLayout.HOST
	_apply_session_chrome()
	if not _host_mode:
		return
	_room_code_display.text = "12345"
	_room_code_display.placeholder_text = ""
	_copy_room_code_button.disabled = false
	_invite_friends_button.disabled = false
	_primary_button.disabled = false


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _in_lobby or not visible:
		return
	_refresh_lobby_voice_switch()


func open_host() -> void:
	_reset_panel_state()
	_host_mode = true
	_in_lobby = true
	visible = true
	_refresh_transport_options()
	_sync_transport_slider(NetworkManager.SESSION_MODE_LOCAL)
	_apply_session_chrome()
	_room_code_display.text = ""
	_room_code_display.placeholder_text = "Connecting…"
	_copy_room_code_button.disabled = true
	_invite_friends_button.disabled = true
	_apply_lobby_voice_preference()
	_begin_host_session(NetworkManager.SESSION_MODE_LOCAL)


func open_guest() -> void:
	_reset_panel_state()
	_host_mode = false
	_in_lobby = true
	visible = true
	_apply_session_chrome()
	_refresh_player_list()
	_apply_lobby_voice_preference()


func _apply_session_chrome() -> void:
	_title_label.text = "Lobby"
	_players_section.visible = true
	_room_code_host_row.visible = _host_mode
	_host_transport_row.visible = _host_mode
	_lobby_voice_row.visible = _host_mode
	if _host_transport_slider != null:
		_host_transport_slider.disabled = not _host_mode
	_lobby_voice_switch.disabled = not _host_mode
	if _host_mode:
		_primary_button.visible = true
		_primary_button.text = "Start Game"
		_back_button.text = "Close Lobby"
	else:
		_primary_button.visible = false
		_back_button.text = "Leave"


func _begin_host_session(mode: String) -> void:
	if _busy:
		return
	if (
		NetworkManager.is_host()
		and NetworkManager.get_session_mode() == mode
	):
		_apply_host_session_chrome()
		_update_start_button_state()
		return
	_set_busy(true)
	var options := {"mode": mode}
	var err: Error = await NetworkManager.host_session(options)
	_set_busy(false)
	if not visible or not _host_mode:
		return
	if err != OK:
		_primary_button.disabled = true
		return
	_sync_transport_slider(NetworkManager.get_session_mode())
	_apply_host_session_chrome()
	_update_start_button_state()
	_refresh_player_list()


func _on_host_transport_selected(index: int) -> void:
	if not _host_mode or not _in_lobby or _busy:
		return
	_begin_host_session(NetworkManagerScript.session_mode_from_index(index))


func close_panel() -> void:
	if _busy:
		return
	_leave_to_menu()


func _on_primary_pressed() -> void:
	_on_host_primary_pressed()


func _on_back_pressed() -> void:
	close_panel()


func _on_network_status(_message: String) -> void:
	pass


func _on_host_primary_pressed() -> void:
	if _busy or not _in_lobby:
		return
	if not NetworkManager.is_host():
		return
	var peer_ids := NetworkManager.get_lobby_peer_ids()
	if not NetworkManager.lobby.can_start(peer_ids):
		return
	NetworkManager.start_game()
	start_requested.emit()


func _on_connection_failed(_message: String) -> void:
	_set_busy(false)
	if _host_mode:
		_primary_button.disabled = true


func _on_became_host(room_code: String) -> void:
	if not _host_mode or not visible:
		return
	_sync_transport_slider(NetworkManager.get_session_mode())
	_apply_host_session_chrome(room_code)


func _apply_host_session_chrome(room_code: String = "") -> void:
	var mode := NetworkManager.get_session_mode()
	var code := room_code.strip_edges()
	if code.is_empty():
		code = NetworkManager.get_room_code().strip_edges()
	var is_local := (
		mode == NetworkManager.SESSION_MODE_LOCAL
		or code.is_empty()
		or code == "local"
	)
	if is_local:
		_room_code_display.text = "Local"
		_room_code_display.placeholder_text = ""
		_copy_room_code_button.disabled = true
		_invite_friends_button.disabled = true
		return
	_room_code_display.text = code
	_room_code_display.placeholder_text = ""
	_copy_room_code_button.disabled = false
	_invite_friends_button.disabled = mode != NetworkManager.SESSION_MODE_STEAM
	_room_code_display.grab_focus()
	_room_code_display.select_all()


func _on_steam_api_initialized(_success: bool) -> void:
	_refresh_transport_options()
	if _in_lobby and _host_mode:
		_sync_transport_slider(NetworkManager.get_session_mode())


func _refresh_transport_options() -> void:
	if _host_transport_slider == null:
		return
	_host_transport_slider.set_options(
		NetworkManagerScript.host_transport_option_labels(SteamService.is_ready())
	)


func _sync_transport_slider(mode: String) -> void:
	if _host_transport_slider == null:
		return
	_host_transport_slider.set_selected(NetworkManagerScript.session_index_from_mode(mode), false)


func _on_copy_room_code_pressed() -> void:
	var room_code := _room_code_display.text.strip_edges()
	if room_code.is_empty():
		return
	DisplayServer.clipboard_set(room_code)


func _on_invite_friends_pressed() -> void:
	NetworkManager.invite_friends()


func _on_joined_host() -> void:
	if _in_lobby:
		_refresh_player_list()


func _on_session_ended(_reason: String) -> void:
	if not visible or _host_mode:
		return
	_leave_to_menu()


func _apply_lobby_voice_preference() -> void:
	_set_lobby_voice_enabled(SettingsManager.lobby_voice_default)


func _on_lobby_voice_toggled(enabled: bool) -> void:
	if not _in_lobby or not _host_mode or _lobby_voice_switch.disabled:
		return
	_set_lobby_voice_enabled(enabled)


func _is_lobby_voice_ui_on() -> bool:
	return SteamProximityVoiceHub.get_mode() == SteamProximityVoiceHub.Mode.LOBBY


func _set_lobby_voice_enabled(enabled: bool) -> void:
	if enabled:
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.LOBBY)
	else:
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
	_refresh_lobby_voice_switch()
	if (
		enabled
		and not SteamProximityVoiceHub.is_lobby_voice_active()
	):
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
		_refresh_lobby_voice_switch()


func _refresh_lobby_voice_switch() -> void:
	var enabled := _is_lobby_voice_ui_on()
	_lobby_voice_switch.set_pressed_no_signal(enabled)
	_lobby_voice_switch.disabled = not _host_mode


func _refresh_player_list() -> void:
	if not _in_lobby or not NetworkManager.is_online():
		return
	for child in _player_list_vbox.get_children():
		child.queue_free()
	var local_peer_id := multiplayer.get_unique_id()
	for peer_id in NetworkManager.get_lobby_peer_ids():
		_build_player_row(peer_id, local_peer_id)
	_update_start_button_state()


func _build_player_row(peer_id: int, local_peer_id: int) -> void:
	var row: LobbyPlayerRow = LobbyPlayerRowScene.instantiate()
	_player_list_vbox.add_child(row)
	row.configure(
		peer_id,
		peer_id == local_peer_id,
		NetworkManager.get_lobby_player_label(peer_id)
	)


func _update_start_button_state() -> void:
	if not _host_mode or not _in_lobby:
		return
	var peer_ids := NetworkManager.get_lobby_peer_ids()
	var can_start := NetworkManager.lobby.can_start(peer_ids)
	_primary_button.disabled = not can_start
	_refresh_lobby_voice_switch()


func _leave_to_menu() -> void:
	_in_lobby = false
	SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
	NetworkManager.disconnect_session()
	visible = false
	_reset_panel_state()
	closed.emit()


func _reset_panel_state() -> void:
	_in_lobby = false
	if _host_transport_slider != null:
		_host_transport_slider.disabled = false
	_lobby_voice_switch.disabled = false
	_lobby_panel_root.visible = true
	for child in _player_list_vbox.get_children():
		child.queue_free()
	_invite_friends_button.disabled = true


func _set_busy(busy: bool) -> void:
	_busy = busy
	_back_button.disabled = busy
	if _host_transport_slider != null:
		_host_transport_slider.disabled = busy or not _host_mode
	if not _host_mode:
		return
	if busy:
		_primary_button.disabled = true
	else:
		_update_start_button_state()
