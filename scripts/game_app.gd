@tool
extends Node

## Root app: exclusive MainMenu / Join / Lobby / Match states + shared VoiceEngine.
## Per-state VoiceSession nodes configure how voice works for that player group.
## Match world (arena.tscn) is instantiated under States/Match only when a match
## starts (or, in the editor, while the Match state is selected for preview).
## In the editor, selecting a state (or its children) previews that state's UI/world.

signal state_changed(state: int)

enum AppState { MAIN_MENU, JOIN, LOBBY, MATCH }

## Path only. GameApp is @tool; preloading arena.tscn at parse time
## pulls the match world into every editor load of the main menu.
const MATCH_SCENE := "res://scenes/arena.tscn"
const MicCaptureBrokerScript := preload("res://scripts/voice/mic_capture_broker.gd")

@export var debug_voice: bool = false

var state: AppState = AppState.MAIN_MENU
var _match_instance: Node = null
var _local_transmit_muted: bool = false
var _editor_preview_state: AppState = AppState.MAIN_MENU

@onready var mic_broker: Node = $MicCaptureBroker
@onready var voice_engine: Node = $VoiceEngine
@onready var main_menu: Node = $States/MainMenu
@onready var lobby: Node = $States/Lobby
@onready var join_state: Node = $States/Join
@onready var match_state: Node = $States/Match
@onready var lobby_voice: Node = $States/Lobby/VoiceSession
@onready var match_voice: Node = $States/Match/VoiceSession
@onready var lobby_panel: LobbyPanel = $States/Lobby/LobbyPanel
@onready var join_menu: JoinMenu = $States/Join/JoinMenu
@onready var menu_screen: Control = $States/MainMenu
@onready var settings_panel: SettingsPanel = $SettingsPanel


func _enter_tree() -> void:
	## Match world is never authored under GameApp. Drop a leftover editor-preview
	## instance before play so STT/match systems do not boot on the main menu.
	if Engine.is_editor_hint():
		return
	var world := get_node_or_null("States/Match/Match")
	if world != null:
		world.free()


func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_setup_preview()
		return

	add_to_group("game_app")
	_bind_voice_sessions()
	_wire_menu()
	_wire_lobby()
	if settings_panel != null:
		settings_panel.closed.connect(_on_settings_closed)
	if NetworkManager.peer_connected.is_connected(_on_peer_changed):
		NetworkManager.peer_connected.disconnect(_on_peer_changed)
	NetworkManager.peer_connected.connect(_on_peer_changed)
	if NetworkManager.peer_disconnected.is_connected(_on_peer_changed):
		NetworkManager.peer_disconnected.disconnect(_on_peer_changed)
	NetworkManager.peer_disconnected.connect(_on_peer_changed)
	if NetworkManager.lobby_roster_changed.is_connected(_on_peer_changed):
		NetworkManager.lobby_roster_changed.disconnect(_on_peer_changed)
	NetworkManager.lobby_roster_changed.connect(_on_peer_changed)
	if NetworkManager.session_ended.is_connected(_on_session_ended):
		NetworkManager.session_ended.disconnect(_on_session_ended)
	NetworkManager.session_ended.connect(_on_session_ended)
	set_state(AppState.MAIN_MENU)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_sync_preview_from_selection()


func get_active_voice_session() -> Node:
	match state:
		AppState.LOBBY:
			return lobby_voice
		AppState.MATCH:
			return match_voice
		_:
			return null


func set_state(next: AppState) -> void:
	_stop_all_voice()
	_set_state_process(main_menu, false)
	_set_state_process(join_state, false)
	_set_state_process(lobby, false)
	_set_state_process(match_state, false)

	if state == AppState.MATCH and next != AppState.MATCH:
		_unload_match()

	state = next
	match next:
		AppState.MAIN_MENU:
			_set_state_process(main_menu, true)
			_show_menu_chrome(true)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		AppState.JOIN:
			_set_state_process(join_state, true)
			_show_menu_chrome(false)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		AppState.LOBBY:
			_set_state_process(lobby, true)
			_show_menu_chrome(false)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		AppState.MATCH:
			_set_state_process(match_state, true)
			_show_menu_chrome(false)
			_load_match()
			## Wand STT shares MicCaptureBroker — enable match fan-out as soon as
			## we enter match so solo casts are not stuck on CHAT_ONLY.
			if mic_broker != null and mic_broker.has_method("set_fanout_policy"):
				mic_broker.call(
					"set_fanout_policy",
					MicCaptureBrokerScript.FanoutPolicy.MATCH_FANOUT
				)
	state_changed.emit(state)
	TomeDebug.log("GameApp", "State → %s" % _state_label(state))


func open_lobby_host() -> void:
	set_state(AppState.LOBBY)
	lobby_panel.open_host()


func open_join() -> void:
	set_state(AppState.JOIN)
	join_menu.open()


func open_settings(from_lobby: bool = false) -> void:
	if from_lobby:
		lobby_panel.visible = false
	else:
		_show_menu_chrome(false)
	settings_panel.set_meta("return_to_lobby", from_lobby)
	settings_panel.open()


func get_match_root() -> Node:
	return _match_instance


func enter_match() -> void:
	if lobby_panel != null:
		lobby_panel.visible = false
	set_state(AppState.MATCH)


func return_to_main_menu() -> void:
	if get_tree() != null:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_state(AppState.MAIN_MENU)


func is_voice_active() -> bool:
	var session := get_active_voice_session()
	return session != null and bool(session.call("is_session_active"))


func is_lobby_voice_active() -> bool:
	return state == AppState.LOBBY and is_voice_active()


func set_lobby_voice_enabled(enabled: bool) -> void:
	if state != AppState.LOBBY:
		return
	if enabled:
		_local_transmit_muted = SettingsManager.mic_muted
		if mic_broker != null:
			mic_broker.set("debug_logging", debug_voice)
		lobby_voice.set("debug_logging", debug_voice)
		lobby_voice.call("start_session")
		lobby_voice.call("set_transmit_muted", _local_transmit_muted)
	else:
		lobby_voice.call("stop_session")


func set_match_voice_enabled(enabled: bool) -> void:
	if state != AppState.MATCH:
		return
	if enabled:
		_local_transmit_muted = SettingsManager.mic_muted
		if mic_broker != null:
			mic_broker.set("debug_logging", debug_voice)
		match_voice.set("debug_logging", debug_voice)
		match_voice.call("start_session")
		match_voice.call("set_transmit_muted", _local_transmit_muted)
	else:
		match_voice.call("stop_session")


func stop_voice() -> void:
	_stop_all_voice()


func refresh_voice_peers() -> void:
	var session := get_active_voice_session()
	if session != null:
		session.call("refresh_peers")


func _on_peer_changed(_arg = null) -> void:
	refresh_voice_peers()


func _on_session_ended(_reason: String) -> void:
	if state == AppState.MAIN_MENU:
		return
	return_to_main_menu()


func deliver_voice_frame(peer_id: int, packet: PackedByteArray) -> void:
	if voice_engine != null and voice_engine.has_method("deliver_voice_frame"):
		voice_engine.call("deliver_voice_frame", peer_id, packet)


func is_peer_speaking(peer_id: int, timeout_ms: int = 350) -> bool:
	if peer_id <= 0:
		return false
	var session := get_active_voice_session()
	if session == null:
		return false
	if peer_id == multiplayer.get_unique_id():
		if _local_transmit_muted:
			return false
		return bool(session.call("is_local_speaking", timeout_ms))
	return bool(session.call("is_remote_speaking", peer_id, timeout_ms))


func is_peer_muted(peer_id: int) -> bool:
	if peer_id <= 0:
		return false
	if peer_id == multiplayer.get_unique_id():
		return _local_transmit_muted
	var session := get_active_voice_session()
	if session == null:
		return false
	return bool(session.call("is_peer_muted", peer_id))


func set_peer_muted(peer_id: int, muted: bool) -> void:
	if peer_id <= 0:
		return
	var session := get_active_voice_session()
	if peer_id == multiplayer.get_unique_id():
		_local_transmit_muted = muted
		if SettingsManager.mic_muted != muted:
			SettingsManager.mic_muted = muted
			SettingsManager.save_settings()
		if session != null:
			session.call("set_transmit_muted", muted)
		return
	if session != null:
		session.call("set_peer_muted", peer_id, muted)


func get_peer_volume(peer_id: int) -> float:
	if peer_id <= 0 or peer_id == multiplayer.get_unique_id():
		return 1.0
	var session := get_active_voice_session()
	if session == null:
		return 1.0
	return float(session.call("get_peer_volume", peer_id))


func set_peer_volume(peer_id: int, linear: float) -> void:
	if peer_id <= 0 or peer_id == multiplayer.get_unique_id():
		return
	var session := get_active_voice_session()
	if session != null:
		session.call("set_peer_volume", peer_id, linear)


func _bind_voice_sessions() -> void:
	if mic_broker != null:
		mic_broker.add_to_group("mic_capture_broker")
		mic_broker.set("debug_logging", debug_voice)
	if lobby_voice != null:
		lobby_voice.call("bind_engine", voice_engine)
		lobby_voice.set("debug_logging", debug_voice)
	if match_voice != null:
		match_voice.call("bind_engine", voice_engine)
		match_voice.set("debug_logging", debug_voice)


func _wire_menu() -> void:
	if menu_screen == null:
		return
	if menu_screen.has_signal("host_pressed"):
		menu_screen.host_pressed.connect(open_lobby_host)
	if menu_screen.has_signal("join_pressed"):
		menu_screen.join_pressed.connect(open_join)
	if menu_screen.has_signal("settings_pressed"):
		menu_screen.settings_pressed.connect(func() -> void: open_settings(false))


func _wire_lobby() -> void:
	if join_menu != null:
		join_menu.closed.connect(_on_join_closed)
		join_menu.joined.connect(_on_join_succeeded)
	if lobby_panel == null:
		return
	lobby_panel.closed.connect(_on_lobby_closed)
	lobby_panel.settings_requested.connect(func() -> void: open_settings(true))


func _on_join_closed() -> void:
	set_state(AppState.MAIN_MENU)


func _on_join_succeeded() -> void:
	set_state(AppState.LOBBY)
	lobby_panel.open_guest()


func _on_lobby_closed() -> void:
	set_state(AppState.MAIN_MENU)


func _on_settings_closed() -> void:
	var back_to_lobby := bool(settings_panel.get_meta("return_to_lobby", false))
	settings_panel.remove_meta("return_to_lobby")
	if back_to_lobby and state == AppState.LOBBY:
		lobby_panel.visible = true
		return
	if state == AppState.MAIN_MENU:
		_show_menu_chrome(true)


func _show_menu_chrome(show_buttons: bool) -> void:
	if menu_screen != null and menu_screen.has_method("set_menu_visible"):
		menu_screen.call("set_menu_visible", show_buttons)


func _set_state_process(node: Node, enabled: bool) -> void:
	if node == null:
		return
	if node is CanvasItem or node is Node3D:
		(node as Node).set("visible", enabled)
	node.process_mode = (
		Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	)


func _load_match() -> void:
	if _match_instance != null and is_instance_valid(_match_instance):
		return
	## Drop a leftover preview/world node so play always starts a fresh instance.
	var existing := match_state.get_node_or_null("Match")
	if existing != null:
		match_state.remove_child(existing)
		existing.free()
	_match_instance = _instantiate_match_world()
	if _match_instance == null:
		return
	_match_instance.name = "Match"
	match_state.add_child(_match_instance)


func _instantiate_match_world() -> Node:
	var packed := load(MATCH_SCENE) as PackedScene
	if packed == null:
		push_error("GameApp: could not load %s" % MATCH_SCENE)
		return null
	return packed.instantiate()


func _unload_match() -> void:
	if _match_instance != null and is_instance_valid(_match_instance):
		_match_instance.queue_free()
	_match_instance = null


func _stop_all_voice() -> void:
	if lobby_voice != null:
		lobby_voice.call("stop_session")
	if match_voice != null:
		match_voice.call("stop_session")


func _state_label(value: AppState) -> String:
	match value:
		AppState.MAIN_MENU:
			return "main_menu"
		AppState.JOIN:
			return "join"
		AppState.LOBBY:
			return "lobby"
		AppState.MATCH:
			return "match"
		_:
			return "?"


func _editor_setup_preview() -> void:
	set_process(true)
	_editor_hide_app_settings()
	_editor_apply_preview_state(AppState.MAIN_MENU)


func _editor_hide_app_settings() -> void:
	var panel := get_node_or_null("SettingsPanel") as CanvasItem
	if panel != null:
		panel.visible = false


func _editor_sync_preview_from_selection() -> void:
	var editor_interface := Engine.get_singleton("EditorInterface")
	if editor_interface == null:
		return
	var selection: Object = editor_interface.get_selection()
	if selection == null:
		return
	var selected: Array = selection.get_selected_nodes()
	if selected.is_empty():
		return
	var node: Node = selected[0] as Node
	if node == null:
		return

	var lobby_node := get_node_or_null("States/Lobby")
	var join_node := get_node_or_null("States/Join")
	var match_node := get_node_or_null("States/Match")
	var menu_node := get_node_or_null("States/MainMenu")
	var settings_node := get_node_or_null("SettingsPanel")

	var show_settings := false
	var next := _editor_preview_state
	var cursor: Node = node
	while cursor != null and cursor != self:
		if settings_node != null and (cursor == settings_node or settings_node.is_ancestor_of(cursor)):
			## Only the GameApp SettingsPanel — not PauseMenu's copy under Main.
			if not _editor_is_under_match_world(cursor):
				show_settings = true
				next = AppState.MAIN_MENU
				break
		if join_node != null and (cursor == join_node or join_node.is_ancestor_of(cursor)):
			next = AppState.JOIN
			break
		if lobby_node != null and (cursor == lobby_node or lobby_node.is_ancestor_of(cursor)):
			next = AppState.LOBBY
			break
		if match_node != null and (cursor == match_node or match_node.is_ancestor_of(cursor)):
			next = AppState.MATCH
			break
		if menu_node != null and (cursor == menu_node or menu_node.is_ancestor_of(cursor)):
			next = AppState.MAIN_MENU
			break
		cursor = cursor.get_parent()

	if next != _editor_preview_state:
		_editor_apply_preview_state(next)
	if settings_node is CanvasItem:
		(settings_node as CanvasItem).visible = show_settings
	if next == AppState.MATCH or _editor_preview_state == AppState.MATCH:
		_editor_apply_match_overlay_preview(node)


func _editor_apply_match_overlay_preview(selected: Node) -> void:
	var world := get_node_or_null("States/Match/Match")
	if world == null or selected == null:
		return
	var pause := world.get_node_or_null("PauseMenu") as CanvasLayer
	var hud := world.get_node_or_null("GameHUD")
	var player_menu: CanvasItem = null
	if hud != null:
		player_menu = hud.get_node_or_null("PlayerMenu") as CanvasItem
	var under_pause := pause != null and (selected == pause or pause.is_ancestor_of(selected))
	var under_player := (
		player_menu != null
		and (selected == player_menu or player_menu.is_ancestor_of(selected))
	)
	if pause != null:
		pause.visible = under_pause
		var pause_settings := pause.get_node_or_null("SettingsPanel") as CanvasItem
		if pause_settings != null:
			pause_settings.visible = (
				under_pause
				and (selected == pause_settings or pause_settings.is_ancestor_of(selected))
			)
	if player_menu != null:
		player_menu.visible = under_player


func _editor_is_under_match_world(node: Node) -> bool:
	var world := get_node_or_null("States/Match/Match")
	if world == null:
		return false
	return node == world or world.is_ancestor_of(node)


func _editor_apply_preview_state(next: AppState) -> void:
	_editor_preview_state = next
	var menu_node := get_node_or_null("States/MainMenu")
	var join_node := get_node_or_null("States/Join")
	var lobby_node := get_node_or_null("States/Lobby")
	var match_node := get_node_or_null("States/Match")
	var join_ui := get_node_or_null("States/Join/JoinMenu") as CanvasItem
	var lobby_ui := get_node_or_null("States/Lobby/LobbyPanel") as CanvasItem

	_set_state_process(menu_node, next == AppState.MAIN_MENU)
	_set_state_process(join_node, next == AppState.JOIN)
	_set_state_process(lobby_node, next == AppState.LOBBY)
	_set_state_process(match_node, next == AppState.MATCH)
	if join_ui != null:
		join_ui.visible = next == AppState.JOIN
	if lobby_ui != null:
		lobby_ui.visible = next == AppState.LOBBY

	if next == AppState.MATCH:
		_editor_ensure_match_preview()
	else:
		_editor_teardown_match_preview()
	_editor_set_match_preview_visible(next == AppState.MATCH)
	_editor_hide_app_settings()

	if next == AppState.MATCH:
		var match_preview := get_node_or_null("States/Match/Match")
		if match_preview != null and match_preview.has_method("editor_refresh_environment_preview"):
			match_preview.call_deferred("editor_refresh_environment_preview")


func _editor_ensure_match_preview() -> void:
	## Instantiate arena.tscn only while previewing Match. owner stays null so
	## Godot does not write the world back into game_app.tscn.
	var parent := get_node_or_null("States/Match")
	if parent == null or parent.get_node_or_null("Match") != null:
		return
	var world := _instantiate_match_world()
	if world == null:
		return
	world.name = "Match"
	parent.add_child(world)
	world.owner = null


func _editor_teardown_match_preview() -> void:
	var world := get_node_or_null("States/Match/Match")
	if world != null:
		world.free()


func _editor_set_match_preview_visible(enabled: bool) -> void:
	## Match is a plain Node (no visible). Hide the 3D world and especially CanvasLayers
	## (PauseMenu embeds SettingsPanel and draws above MainMenu/Lobby in the 2D editor).
	var world := get_node_or_null("States/Match/Match") as Node3D
	if world == null:
		return
	world.visible = enabled
	for child in world.get_children():
		if child is CanvasLayer:
			## Keep pause/settings overlays off while editing; HUD only in Match preview.
			if child.name == "PauseMenu":
				(child as CanvasLayer).visible = false
			else:
				(child as CanvasLayer).visible = enabled
