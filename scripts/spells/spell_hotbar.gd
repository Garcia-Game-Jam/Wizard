class_name SpellHotbar
extends Node

## Per-player 4-slot spell bar. Voice confirm starts pending assignment;
## LMB / RMB / Q / E store and fire a slot. Middle mouse captures a new spell.

signal slots_changed()
signal pending_changed()
signal slot_selected(slot_index: int, spell: SpellDefinition)

const SLOT_COUNT := 4
const SLOT_ACTIONS: PackedStringArray = [
	"spell_slot_1",
	"spell_slot_2",
	"spell_slot_3",
	"spell_slot_4",
]
const SLOT_FALLBACKS: PackedStringArray = ["LMB", "RMB", "Q", "E"]

const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")

var _loadout: Node
var _slots: Array[String] = []
var _pending_spell: SpellDefinition
var _selected_index := -1


func _ready() -> void:
	_ensure_slot_array()
	set_process_unhandled_input(true)
	var parent := get_parent()
	if parent == null:
		return
	if _loadout == null:
		configure(parent.get_node_or_null("CharacterSpellLoadout"))
	var session := parent.get_node_or_null("SpellCastingSession")
	if session != null and session.has_signal("spell_selected"):
		if not session.spell_selected.is_connected(_on_voice_spell_selected):
			session.spell_selected.connect(_on_voice_spell_selected)


func configure(loadout: Node) -> void:
	_loadout = loadout
	_ensure_slot_array()


func get_slot(index: int) -> String:
	_ensure_slot_array()
	if index < 0 or index >= SLOT_COUNT:
		return ""
	return _slots[index]


func get_slots() -> Array[String]:
	_ensure_slot_array()
	return _slots.duplicate()


func get_selected_index() -> int:
	return _selected_index


func has_pending() -> bool:
	return _pending_spell != null


func get_pending_spell() -> SpellDefinition:
	return _pending_spell


func get_spell_at(index: int) -> SpellDefinition:
	return _spell_def(get_slot(index))


func display_name(spell_id: String) -> String:
	if spell_id.is_empty():
		return ""
	var spell := _spell_def(spell_id)
	if spell != null and not spell.display_name.is_empty():
		return spell.display_name
	return spell_id.capitalize()


func assignment_prompt() -> String:
	if _pending_spell == null:
		return ""
	var spell_name := _pending_spell.display_name.strip_edges()
	if spell_name.is_empty():
		spell_name = _pending_spell.id.capitalize()
	var parts: PackedStringArray = ["Assign %s" % spell_name]
	for i in SLOT_ACTIONS.size():
		var fallback := "?"
		if i < SLOT_FALLBACKS.size():
			fallback = SLOT_FALLBACKS[i]
		parts.append(InputPromptScript.bracket(SLOT_ACTIONS[i], fallback))
	return "  ".join(parts)


func begin_pending(spell: SpellDefinition) -> void:
	_pending_spell = spell
	_selected_index = -1
	pending_changed.emit()
	slots_changed.emit()
	_clear_owner_armed()


func clear_pending() -> void:
	if _pending_spell == null:
		return
	_pending_spell = null
	pending_changed.emit()
	slots_changed.emit()


func clear_selection() -> void:
	if _selected_index < 0:
		return
	_selected_index = -1
	slots_changed.emit()


func set_slot(index: int, spell_id: String) -> void:
	_ensure_slot_array()
	if index < 0 or index >= SLOT_COUNT:
		return
	if _slots[index] == spell_id:
		return
	_slots[index] = spell_id
	if spell_id.is_empty() and _selected_index == index:
		_selected_index = -1
	slots_changed.emit()


func swap_slots(slot_a: int, slot_b: int) -> void:
	_ensure_slot_array()
	if slot_a < 0 or slot_a >= SLOT_COUNT:
		return
	if slot_b < 0 or slot_b >= SLOT_COUNT or slot_a == slot_b:
		return
	var tmp := _slots[slot_a]
	_slots[slot_a] = _slots[slot_b]
	_slots[slot_b] = tmp
	if _selected_index == slot_a:
		_selected_index = slot_b
	elif _selected_index == slot_b:
		_selected_index = slot_a
	slots_changed.emit()


func assign_pending_to(index: int) -> bool:
	_ensure_slot_array()
	if _pending_spell == null:
		return false
	if index < 0 or index >= SLOT_COUNT:
		return false
	var spell := _pending_spell
	_slots[index] = spell.id
	_pending_spell = null
	_selected_index = index
	pending_changed.emit()
	slots_changed.emit()
	slot_selected.emit(index, spell)
	return true


func try_activate_slot(index: int) -> bool:
	if has_pending():
		return assign_pending_to(index)
	var spell := get_spell_at(index)
	if spell == null:
		return false
	_selected_index = index
	slots_changed.emit()
	slot_selected.emit(index, spell)
	return true


func _clear_owner_armed() -> void:
	var player := get_parent()
	if player != null and player.has_method("_cancel_slot_cast"):
		player.call("_cancel_slot_cast")


func _begin_owner_slot_fire(index: int) -> bool:
	var player := get_parent()
	if player == null or not player.has_method("_try_begin_slot_fire"):
		return try_activate_slot(index)
	if not bool(player.call("_try_begin_slot_fire", index)):
		return false
	_selected_index = index
	slots_changed.emit()
	return true


func _release_owner_slot_fire(index: int) -> bool:
	var player := get_parent()
	if player == null or not player.has_method("_try_release_slot_fire"):
		return false
	return bool(player.call("_try_release_slot_fire", index))


func _on_voice_spell_selected(spell: SpellDefinition) -> void:
	begin_pending(spell)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_authority():
		return
	if event.is_echo():
		return
	if _is_input_blocked():
		return
	for i in SLOT_COUNT:
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			if has_pending():
				if assign_pending_to(i):
					get_viewport().set_input_as_handled()
			elif _begin_owner_slot_fire(i):
				get_viewport().set_input_as_handled()
			return
		if event.is_action_released(SLOT_ACTIONS[i]):
			if _release_owner_slot_fire(i):
				get_viewport().set_input_as_handled()
			return


func _is_local_authority() -> bool:
	var player := get_parent()
	if player == null:
		return false
	if player.has_method("_uses_local_view"):
		return bool(player.call("_uses_local_view"))
	return player.is_multiplayer_authority()


func _is_input_blocked() -> bool:
	var tree := get_tree()
	if tree == null or tree.paused:
		return true
	var hud := tree.get_first_node_in_group("game_hud")
	if hud != null and hud.has_method("is_spellbook_open"):
		if bool(hud.call("is_spellbook_open")):
			return true
	if hud != null and hud.has_method("is_monster_book_open"):
		if bool(hud.call("is_monster_book_open")):
			return true
	if has_pending():
		return false
	if hud != null and hud.has_method("is_player_menu_open"):
		return bool(hud.call("is_player_menu_open"))
	return false


func _spell_def(spell_id: String) -> SpellDefinition:
	if spell_id.is_empty() or _loadout == null:
		return null
	if not _loadout.has_method("get_spell_definition"):
		return null
	return _loadout.get_spell_definition(spell_id) as SpellDefinition


func _ensure_slot_array() -> void:
	if _slots.size() == SLOT_COUNT:
		return
	_slots.clear()
	_slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		_slots[i] = ""
