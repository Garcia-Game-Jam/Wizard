class_name MonsterBook
extends Node

## Dev summon book: open pages → pick a monster → aim spawn ghost.

const BookPanelScene := preload("res://scenes/ui/book/monster/monster_book.tscn")
const MonsterSpawnPlacementScript := preload(
	"res://scripts/headmaster/monster_spawn_placement.gd"
)

var _player: CharacterBody3D
var _panel: Control
## Typed as Node so headless warning probe can load this script before
## monster_spawn_placement.gd registers its class_name (alpha load order).
var _placement: Node
var _pending_select := false


func configure(player: CharacterBody3D) -> void:
	_player = player


func is_book_open() -> bool:
	return _panel != null and _panel.has_method("is_open") and bool(_panel.call("is_open"))


func is_placing() -> bool:
	return _placement != null and _placement.is_active()


func is_busy() -> bool:
	return is_book_open() or is_placing()


func open() -> bool:
	if _player == null:
		return false
	if _player.has_method("is_local_owner"):
		if not bool(_player.call("is_local_owner")):
			return false
	elif not _player.is_multiplayer_authority():
		return false
	if is_placing():
		_placement.cancel()
	_ensure_panel()
	_ensure_placement()
	if _panel.has_method("open_book"):
		_panel.call("open_book")
	return true


func close_book() -> void:
	if _panel != null and _panel.has_method("close_book"):
		_panel.call("close_book")
	_restore_mouse_if_idle()


func cancel_all() -> void:
	if is_placing():
		_placement.cancel()
	close_book()
	_restore_mouse_if_idle()


func get_prompt() -> String:
	if is_placing() and _placement != null:
		return _placement.get_prompt()
	return ""


func _ensure_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		return
	var hud := _find_hud()
	if hud == null:
		push_warning("MonsterBook: GameHUD missing; cannot open book UI")
		return
	_panel = BookPanelScene.instantiate()
	_panel.name = "MonsterBookPanel"
	hud.add_child(_panel)
	if _panel.has_signal("monster_selected"):
		_panel.monster_selected.connect(_on_monster_selected)
	if _panel.has_signal("closed"):
		_panel.closed.connect(_on_book_closed)


func _ensure_placement() -> void:
	if _placement != null and is_instance_valid(_placement):
		return
	_placement = MonsterSpawnPlacementScript.new()
	_placement.name = "MonsterSpawnPlacement"
	add_child(_placement)
	_placement.configure(_player)
	_placement.placement_finished.connect(_on_placement_finished)


func _on_monster_selected(entry: Dictionary) -> void:
	_pending_select = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ensure_placement()
	_placement.begin(entry)
	_pending_select = false


func _on_book_closed() -> void:
	if _pending_select:
		return
	_restore_mouse_if_idle()


func _on_placement_finished(_confirmed: bool) -> void:
	_restore_mouse_if_idle()


func _restore_mouse_if_idle() -> void:
	if is_book_open() or is_placing():
		return
	var hud := _find_hud()
	if hud != null and hud.has_method("is_player_menu_open") and bool(hud.call("is_player_menu_open")):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _find_hud() -> Node:
	if _player == null or not _player.is_inside_tree():
		return null
	return _player.get_tree().get_first_node_in_group("game_hud")
