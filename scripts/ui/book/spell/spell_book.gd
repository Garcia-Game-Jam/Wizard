class_name SpellBook
extends BaseBook

## Browse-only spell tome — one pre-baked page scene per character spell.

signal spell_selected(spell_id: String)

const GuideContentScript := preload("res://scripts/ui/guide_content.gd")

const PAGE_SCENES: Array[PackedScene] = [
	preload("res://scenes/ui/book/spell/pages/dispell.tscn"),
	preload("res://scenes/ui/book/spell/pages/fireball.tscn"),
	preload("res://scenes/ui/book/spell/pages/flare.tscn"),
	preload("res://scenes/ui/book/spell/pages/follow.tscn"),
	preload("res://scenes/ui/book/spell/pages/haste.tscn"),
	preload("res://scenes/ui/book/spell/pages/light.tscn"),
	preload("res://scenes/ui/book/spell/pages/light_ball.tscn"),
	preload("res://scenes/ui/book/spell/pages/pull.tscn"),
	preload("res://scenes/ui/book/spell/pages/stop.tscn"),
	preload("res://scenes/ui/book/spell/pages/target.tscn"),
	preload("res://scenes/ui/book/spell/pages/ward.tscn"),
]

const COOLDOWN_REFRESH_SEC := 0.15

var _loadout: Node
var _restore_spell_id := ""
var _cooldown_refresh_left := 0.0


func _ready() -> void:
	super._ready()
	set_process(false)
	_set_default_cover_title("Spellbook", "Known arts of the voice")


func configure_loadout(loadout: Node) -> void:
	_loadout = loadout


func set_selected_spell_id(spell_id: String) -> void:
	_restore_spell_id = spell_id
	if not _open or _opening_cover:
		return
	var page_i := _find_page_index(spell_id)
	if page_i < 0:
		return
	var spread_i := int(page_i / 2.0)
	if spread_i == _spread_index:
		return
	_spread_index = spread_i
	_show_spread(_spread_index)


func open_book() -> void:
	super.open_book()
	set_process(true)


func close_book() -> void:
	set_process(false)
	super.close_book()


func refresh_pages() -> void:
	if not _open or _opening_cover:
		return
	_refresh_cooldown_labels()


func page_scenes() -> Array[PackedScene]:
	return PAGE_SCENES


func _initial_spread_index() -> int:
	var page_i := _find_page_index(_restore_spell_id)
	if page_i < 0:
		return 0
	return int(page_i / 2.0)


func _on_spread_shown(
	_spread_index_shown: int, left: Control, right: Control
) -> void:
	_refresh_cooldown_on_page(left)
	_refresh_cooldown_on_page(right)
	var spell_id := _spell_id_from_page(left)
	if spell_id.is_empty():
		spell_id = _spell_id_from_page(right)
	if not spell_id.is_empty():
		spell_selected.emit(spell_id)


func _process(delta: float) -> void:
	_cooldown_refresh_left -= delta
	if _cooldown_refresh_left > 0.0:
		return
	_cooldown_refresh_left = COOLDOWN_REFRESH_SEC
	if _turning or _opening_cover:
		return
	_refresh_cooldown_labels()


func _refresh_cooldown_labels() -> void:
	_refresh_cooldown_on_page(_left_instance)
	_refresh_cooldown_on_page(_right_instance)


func _refresh_cooldown_on_page(page: Control) -> void:
	if page == null:
		return
	var spell_id := _spell_id_from_page(page)
	var label := page.get_node_or_null("Margin/VBox/CooldownLabel") as Label
	if label == null:
		return
	var remaining := _remaining_cooldown_sec(spell_id)
	var text := GuideContentScript.format_cooldown_countdown(remaining)
	label.visible = not text.is_empty()
	label.text = text


func _remaining_cooldown_sec(spell_id: String) -> float:
	if spell_id.is_empty():
		return 0.0
	if _loadout == null or not _loadout.has_method("remaining_cooldown_sec"):
		return 0.0
	return float(_loadout.remaining_cooldown_sec(spell_id))


func _find_page_index(spell_id: String) -> int:
	if spell_id.is_empty():
		return -1
	var scenes := page_scenes()
	for i in scenes.size():
		## Match by filename stem (page scene name == spell id).
		var path := scenes[i].resource_path.get_file().get_basename()
		if path == spell_id:
			return i
	return -1


func _spell_id_from_page(page: Control) -> String:
	if page == null:
		return ""
	if "spell_id" in page:
		return str(page.get("spell_id"))
	return ""


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
