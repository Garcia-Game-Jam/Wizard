class_name PlayerVoiceList
extends VBoxContainer

## Player mute / mix list for Audio settings. Same row prefab as the lobby.

const LobbyPlayerRowScene := preload("res://scenes/ui/scaffolding/lobby_player_row.tscn")

var _header: Label
var _empty_label: Label
var _rows_root: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 8)
	_header = Label.new()
	_header.text = "Players"
	_header.add_theme_color_override("font_color", Color(0.75, 0.88, 1))
	add_child(_header)

	_empty_label = Label.new()
	_empty_label.add_theme_color_override("font_color", Color(0.65, 0.58, 0.78))
	_empty_label.add_theme_font_size_override("font_size", 13)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.text = "Join a multiplayer session to adjust per-player voice."
	add_child(_empty_label)

	_rows_root = VBoxContainer.new()
	_rows_root.add_theme_constant_override("separation", 6)
	add_child(_rows_root)


func refresh() -> void:
	for child in _rows_root.get_children():
		child.queue_free()

	if not NetworkManager.is_online():
		_empty_label.visible = true
		_empty_label.text = "Join a multiplayer session to adjust per-player voice."
		return

	var peer_ids := NetworkManager.get_lobby_peer_ids()
	if peer_ids.is_empty():
		_empty_label.visible = true
		_empty_label.text = "No other players in this session yet."
		return

	_empty_label.visible = false
	var local_id := multiplayer.get_unique_id()
	for peer_id in peer_ids:
		var row: LobbyPlayerRow = LobbyPlayerRowScene.instantiate()
		_rows_root.add_child(row)
		row.configure(
			peer_id,
			peer_id == local_id,
			NetworkManager.get_lobby_player_label(peer_id)
		)
