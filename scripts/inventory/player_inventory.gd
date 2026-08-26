class_name PlayerInventory
extends Node

## Per-player bag: 10 slots. Indices 0–3 are hotbar keys 1–4 (UI is 1-based).

signal inventory_changed()
signal item_used(item_id: String, slot_index: int)

const SLOT_COUNT := 10
const HOTBAR_COUNT := 4
const ITEM_SPELLBOOK := "spellbook"
const ITEM_BOOK := "book"

## Slot-indexed loadout: index 0 = hotbar key 1, etc. Empty string leaves the slot empty.
@export var starting_items: Array[String] = []

var _slots: Array[String] = []


func _ready() -> void:
	_ensure_slot_array()
	_apply_starting_items()
	set_process_unhandled_input(true)


func _apply_starting_items() -> void:
	## Place by slot index so loadouts can pin items (e.g. spellbook in slot 2).
	var changed := false
	for i in starting_items.size():
		if i >= SLOT_COUNT:
			break
		var item_id := starting_items[i]
		if item_id.is_empty() or _slots[i] == item_id:
			continue
		_slots[i] = item_id
		changed = true
	if changed:
		inventory_changed.emit()


func _ensure_slot_array() -> void:
	if _slots.size() == SLOT_COUNT:
		return
	_slots.clear()
	_slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		_slots[i] = ""


func has(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	return _slots.has(item_id)


func add(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	_ensure_slot_array()
	for i in SLOT_COUNT:
		if _slots[i].is_empty():
			_slots[i] = item_id
			inventory_changed.emit()
			return true
	return false


func remove(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	_ensure_slot_array()
	for i in SLOT_COUNT:
		if _slots[i] == item_id:
			_slots[i] = ""
			inventory_changed.emit()
			return true
	return false


func get_slot(index: int) -> String:
	_ensure_slot_array()
	if index < 0 or index >= SLOT_COUNT:
		return ""
	return _slots[index]


func set_slot(index: int, item_id: String) -> void:
	_ensure_slot_array()
	if index < 0 or index >= SLOT_COUNT:
		return
	var next := item_id
	if _slots[index] == next:
		return
	_slots[index] = next
	inventory_changed.emit()


func swap_slots(a: int, b: int) -> void:
	_ensure_slot_array()
	if a < 0 or a >= SLOT_COUNT or b < 0 or b >= SLOT_COUNT or a == b:
		return
	var tmp := _slots[a]
	_slots[a] = _slots[b]
	_slots[b] = tmp
	inventory_changed.emit()


func get_slots() -> Array[String]:
	_ensure_slot_array()
	return _slots.duplicate()


func find_slot(item_id: String) -> int:
	if item_id.is_empty():
		return -1
	_ensure_slot_array()
	for i in SLOT_COUNT:
		if _slots[i] == item_id:
			return i
	return -1


func use_slot(index: int) -> bool:
	_ensure_slot_array()
	if index < 0 or index >= SLOT_COUNT:
		return false
	var item_id := _slots[index]
	if item_id.is_empty():
		return false
	if not _use_item(item_id):
		return false
	item_used.emit(item_id, index)
	return true


func display_name(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	match item_id:
		ITEM_SPELLBOOK:
			return "Spellbook"
		ITEM_BOOK:
			return "Summoning Book"
		_:
			return item_id.capitalize()


func _use_item(item_id: String) -> bool:
	match item_id:
		ITEM_SPELLBOOK:
			return _toggle_spellbook()
		ITEM_BOOK:
			return _open_monster_book()
		_:
			return false


func _toggle_spellbook() -> bool:
	var player := get_parent() as CharacterBody3D
	if player == null or not has(ITEM_SPELLBOOK):
		return false
	var tree := player.get_tree()
	if tree == null:
		return false
	var hud := tree.get_first_node_in_group("game_hud")
	if hud != null and hud.has_method("toggle_spellbook"):
		hud.call("toggle_spellbook")
		return true
	return false


func _open_monster_book() -> bool:
	var player := get_parent() as CharacterBody3D
	if player == null:
		return false
	if not has(ITEM_BOOK):
		return false
	var book := player.get_node_or_null("MonsterBook")
	if book == null:
		var MonsterBookScript := load("res://scripts/headmaster/monster_book.gd")
		if MonsterBookScript == null:
			return false
		book = MonsterBookScript.new()
		book.name = "MonsterBook"
		player.add_child(book)
		if book.has_method("configure"):
			book.call("configure", player)
	if book.has_method("is_busy") and bool(book.call("is_busy")):
		if book.has_method("cancel_all"):
			book.call("cancel_all")
		return true
	if book.has_method("open"):
		return bool(book.call("open"))
	return false


func _unhandled_input(event: InputEvent) -> void:
	var player := get_parent() as Node
	if player == null:
		return
	if player.has_method("is_local_owner"):
		if not bool(player.call("is_local_owner")):
			return
	elif not player.is_multiplayer_authority():
		return
	if _is_menu_blocking():
		return
	for i in HOTBAR_COUNT:
		var action := "hotbar_%d" % (i + 1)
		if event.is_action_pressed(action):
			use_slot(i)
			get_viewport().set_input_as_handled()
			return


func _is_menu_blocking() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	if tree.paused:
		return true
	var hud := tree.get_first_node_in_group("game_hud")
	if hud != null and hud.has_method("is_player_menu_open") and bool(hud.call("is_player_menu_open")):
		return true
	return false
