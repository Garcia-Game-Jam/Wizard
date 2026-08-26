class_name InputRebindCatalog
extends RefCounted

## Player-facing remappable actions. Adding a Controls row = one entry here
## plus an InputMap action. Not every project action.

const GROUP_MOVEMENT := "Movement"
const GROUP_SPELLS := "Spells"
const GROUP_ITEMS := "Items"
const GROUP_WORLD := "World / UI"
const GROUP_VOICE := "Voice"


static func entries() -> Array[Dictionary]:
	return [
		_entry("move_forward", "Move Forward", GROUP_MOVEMENT),
		_entry("move_back", "Move Back", GROUP_MOVEMENT),
		_entry("move_left", "Move Left", GROUP_MOVEMENT),
		_entry("move_right", "Move Right", GROUP_MOVEMENT),
		_entry("jump", "Jump", GROUP_MOVEMENT),
		_entry("dash", "Dash", GROUP_MOVEMENT),
		_entry("crouch", "Crouch", GROUP_MOVEMENT),
		_entry("spell_capture", "Spell Capture", GROUP_SPELLS),
		_entry("spell_slot_1", "Spell Slot 1", GROUP_SPELLS),
		_entry("spell_slot_2", "Spell Slot 2", GROUP_SPELLS),
		_entry("spell_slot_3", "Spell Slot 3", GROUP_SPELLS),
		_entry("spell_slot_4", "Spell Slot 4", GROUP_SPELLS),
		_entry("hotbar_1", "Item 1", GROUP_ITEMS),
		_entry("hotbar_2", "Item 2", GROUP_ITEMS),
		_entry("hotbar_3", "Item 3", GROUP_ITEMS),
		_entry("hotbar_4", "Item 4", GROUP_ITEMS),
		_entry("interact", "Interact", GROUP_WORLD),
		_entry("spellbook", "Spellbook", GROUP_WORLD),
		_entry("guide_menu", "Guide Menu", GROUP_WORLD),
		_entry("book_page_prev", "Book Page Prev", GROUP_WORLD),
		_entry("book_page_next", "Book Page Next", GROUP_WORLD),
		_entry("voice_push", "Voice Push", GROUP_VOICE),
		_entry("radio_push", "Radio Push", GROUP_VOICE),
	]


static func action_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for entry in entries():
		names.append(str(entry.get("action", "")))
	return names


static func has_action(action: String) -> bool:
	return not group_of(action).is_empty()


static func group_of(action: String) -> String:
	for entry in entries():
		if str(entry.get("action", "")) == action:
			return str(entry.get("group", ""))
	return ""


static func is_allowed_bind_overlap(action_a: String, action_b: String) -> bool:
	if action_a == action_b:
		return true
	if _is_book_page_vs_frozen(action_a, action_b):
		return true
	return false


static func _is_book_page_vs_frozen(action_a: String, action_b: String) -> bool:
	var a_page := action_a == "book_page_prev" or action_a == "book_page_next"
	var b_page := action_b == "book_page_prev" or action_b == "book_page_next"
	if a_page == b_page:
		return false
	var other := action_b if a_page else action_a
	var other_group := group_of(other)
	return (
		other_group == GROUP_MOVEMENT
		or other_group == GROUP_SPELLS
		or other_group == GROUP_ITEMS
		or other_group == GROUP_WORLD
	)


static func _entry(action: String, label: String, group: String) -> Dictionary:
	return {"action": action, "label": label, "group": group}
