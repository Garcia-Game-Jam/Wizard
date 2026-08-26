class_name MonsterBookPanel
extends BaseBook

## Dev summon tome — one pre-baked monster page per leaf.

signal monster_selected(entry: Dictionary)

const PAGE_SCENES: Array[PackedScene] = [
	preload("res://scenes/ui/book/monster/pages/wretch.tscn"),
	preload("res://scenes/ui/book/monster/pages/ash_wretch.tscn"),
	preload("res://scenes/ui/book/monster/pages/ember_wretch.tscn"),
	preload("res://scenes/ui/book/monster/pages/charger.tscn"),
]


func _ready() -> void:
	super._ready()
	_set_default_cover_title("Summoning Codex", "Call a hunter into the pit")


func page_scenes() -> Array[PackedScene]:
	return PAGE_SCENES


func _on_spread_shown(
	_spread_index_shown: int, left: Control, right: Control
) -> void:
	_wire_page(left)
	_wire_page(right)


func _input(event: InputEvent) -> void:
	super._input(event)
	if not _open or _opening_cover or _turning:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_confirm_focused_page()
		get_viewport().set_input_as_handled()


func _wire_page(page: Control) -> void:
	if page == null or not page.has_signal("select_pressed"):
		return
	if page.select_pressed.is_connected(_on_page_select_pressed):
		return
	page.select_pressed.connect(_on_page_select_pressed.bind(page))


func _on_page_select_pressed(page: Control) -> void:
	_emit_selection(page)


func _confirm_focused_page() -> void:
	## Prefer the right page under the cursor when both are shown; else left.
	var page := _page_under_cursor()
	if page == null:
		page = _left_instance
	_emit_selection(page)


func _page_under_cursor() -> Control:
	var mouse := get_global_mouse_position()
	for page in [_right_instance, _left_instance]:
		if page != null and page.get_global_rect().has_point(mouse):
			return page
	return null


func _emit_selection(page: Control) -> void:
	if not _open or page == null:
		return
	var entry: Dictionary = {}
	if page.has_method("get_catalog_entry"):
		entry = page.get_catalog_entry()
	if entry.is_empty():
		return
	_open = false
	_kill_tweens()
	_turning = false
	_opening_cover = false
	visible = false
	set_process_input(false)
	monster_selected.emit(entry)


func _set_default_cover_title(title: String, subtitle: String) -> void:
	var cover := _cover_slot.get_node_or_null("ClosedCover")
	if cover == null:
		return
	var title_label := cover.get_node_or_null("Row/Margin/VBox/TitlePlate/CoverTitle") as Label
	var sub_label := cover.get_node_or_null("Row/Margin/VBox/CoverSubtitle") as Label
	if title_label != null:
		title_label.text = title
	if sub_label != null:
		sub_label.text = subtitle
