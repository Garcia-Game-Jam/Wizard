class_name GameHud
extends CanvasLayer

## In-game HUD: casting overlay, inventory hotbar, 4-slot spell hotbar,
## Tab player menu (Inventory / Spells / Guide), and the spellbook overlay (B).

const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")
const HudSpellBarScript := preload("res://scripts/ui/hud_spell_bar.gd")
const HudItemBarScript := preload("res://scripts/ui/hud_item_bar.gd")
const HudConjureTipScript := preload("res://scripts/ui/hud_conjure_tip.gd")
const HudSectionScript := preload("res://scripts/ui/hud_section.gd")
const SpellbookPanelScene := preload("res://scenes/ui/book/spell/spell_book.tscn")

## Bottom HUD: spell hotbar (left) + inventory hotbar (right), lifted for 1080p viewport scaling.
const BOTTOM_HUD_MARGIN_PX := 36.0
const BOTTOM_HUD_ROW_HEIGHT_PX := 88.0
const BOTTOM_HUD_BAR_GAP_PX := 16.0

var _loadout: Node
var _inventory: Node
var _selected_spell_id: String = ""
var _active_spell: Resource
var _from_tome := false
var _coaching_countdown := 0.0
var _player_menu_open := false
var _objective_lines: PackedStringArray = PackedStringArray()
var _spell_hotbar: Node
var _spell_bar: HudSpellBarScript
var _item_bar: HudItemBarScript
var _conjure_tip: HudConjureTipScript
var _health_root: Control
var _health_pool: Character
## Typed as Control: the panel is duck-typed (open_book/close_book/is_open).
var _spellbook_panel: Control

@onready var player_menu: Node = $PlayerMenu
@onready var aim_cursor: Control = $AimCursor

@onready var prompt_label: Label = $MarginContainer/PromptLabel
@onready var casting_panel: PanelContainer = $CastingPanel
@onready var casting_title: Label = $CastingPanel/MarginContainer/VBox/TitleLabel
@onready var casting_words: Label = $CastingPanel/MarginContainer/VBox/WordsLabel
@onready var casting_guide: Label = $CastingPanel/MarginContainer/VBox/GuideLabel
@onready var casting_status: Label = $CastingPanel/MarginContainer/VBox/StatusLabel
@onready var mic_level_bar: ProgressBar = $CastingPanel/MarginContainer/VBox/MicLevelBar
@onready var casting_feedback: Label = $CastingPanel/MarginContainer/VBox/FeedbackLabel
@onready var casting_detail: Label = $CastingPanel/MarginContainer/VBox/DetailLabel
@onready var spell_word_banner: Control = $SpellWordBanner
@onready var _health_bar: UiStatusBar = get_node_or_null("HealthBar") as UiStatusBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_hud")
	prompt_label.text = ""
	$MarginContainer.visible = false
	casting_panel.visible = false
	mic_level_bar.min_value = 0.0
	mic_level_bar.max_value = 1.0
	mic_level_bar.value = 0.0
	_setup_spellbook_panel()
	_setup_bottom_hud()
	_bind_health_bar()
	_update_aim_cursor_visibility()


func _input(event: InputEvent) -> void:
	## While open, catch Tab/Esc before TabBar or pause can claim them.
	if not _player_menu_open:
		return
	if event.is_action_pressed("guide_menu") or event.is_action_pressed("ui_cancel"):
		close_player_menu()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _player_menu_open:
		return
	if not event.is_action_pressed("guide_menu"):
		return
	_open_player_menu()
	get_viewport().set_input_as_handled()


func toggle_player_menu() -> void:
	if _player_menu_open:
		close_player_menu()
	else:
		_open_player_menu()


func _open_player_menu() -> void:
	if is_spellbook_open():
		close_spellbook()
	_player_menu_open = true
	player_menu.visible = true
	if _inventory != null and player_menu.has_method("configure_inventory"):
		player_menu.configure_inventory(_inventory)
	if _spell_hotbar != null and player_menu.has_method("configure_spell_hotbar"):
		player_menu.configure_spell_hotbar(_spell_hotbar)
	if player_menu.has_method("reset_to_main"):
		player_menu.reset_to_main()
	_refresh_player_menu_content()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_player_menu_open() -> bool:
	return _player_menu_open


func is_monster_book_open() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("player"):
		var book := node.get_node_or_null("MonsterBook")
		if book != null and book.has_method("is_book_open") and bool(book.call("is_book_open")):
			return true
	return false


func close_monster_book() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("player"):
		var book := node.get_node_or_null("MonsterBook")
		if book != null and book.has_method("cancel_all"):
			book.call("cancel_all")


func close_player_menu() -> void:
	if not _player_menu_open:
		return
	_player_menu_open = false
	player_menu.visible = false
	if player_menu.has_method("reset_to_main"):
		player_menu.reset_to_main()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func configure(
	loadout: Node,
	casting_session: Node = null,
	spell_hotbar: Node = null,
	health: Character = null
) -> void:
	_loadout = loadout
	if _loadout != null and _loadout.has_signal("spell_learned"):
		_loadout.spell_learned.connect(_on_spell_learned)
	if _loadout != null and _loadout.has_signal("loadout_changed"):
		_loadout.loadout_changed.connect(_on_loadout_changed)
	if casting_session != null and casting_session.has_signal("listen_level_changed"):
		casting_session.listen_level_changed.connect(_update_listen_level)
	if casting_session != null and casting_session.has_signal("listen_coaching_changed"):
		casting_session.listen_coaching_changed.connect(_update_listen_coaching)
	if casting_session != null and casting_session.has_signal("tome_retry_tick"):
		casting_session.tome_retry_tick.connect(update_tome_coaching_countdown)
	_bind_spell_hotbar(spell_hotbar)
	_bind_health_pool(health)


func configure_inventory(inventory: Node) -> void:
	if (
		_inventory != null
		and _inventory.has_signal("inventory_changed")
		and _inventory.inventory_changed.is_connected(_refresh_hotbar)
	):
		_inventory.inventory_changed.disconnect(_refresh_hotbar)
	_inventory = inventory
	if _inventory != null and _inventory.has_signal("inventory_changed"):
		_inventory.inventory_changed.connect(_refresh_hotbar)
	if player_menu != null and player_menu.has_method("configure_inventory"):
		player_menu.configure_inventory(_inventory)
	_refresh_hotbar()


func _bind_spell_hotbar(hotbar: Node) -> void:
	var resolved := hotbar
	if resolved == null and _loadout != null:
		var player := _loadout.get_parent()
		if player != null:
			resolved = player.get_node_or_null("%SpellHotbar")
			if resolved == null:
				resolved = player.get_node_or_null("SpellHotbar")
	if (
		_spell_hotbar != null
		and _spell_hotbar.has_signal("slots_changed")
		and _spell_hotbar.slots_changed.is_connected(_refresh_spell_hotbar)
	):
		_spell_hotbar.slots_changed.disconnect(_refresh_spell_hotbar)
	_spell_hotbar = resolved
	if _spell_hotbar != null and _spell_hotbar.has_signal("slots_changed"):
		_spell_hotbar.slots_changed.connect(_refresh_spell_hotbar)
	if player_menu != null and player_menu.has_method("configure_spell_hotbar"):
		player_menu.configure_spell_hotbar(_spell_hotbar)
	_refresh_spell_hotbar()


func set_interaction_prompt(text: String) -> void:
	if prompt_label == null:
		return
	prompt_label.text = text
	var margin := prompt_label.get_parent()
	if margin is Control:
		(margin as Control).visible = not text.is_empty()


func toggle_spellbook() -> void:
	if _spellbook_panel == null:
		return
	if is_spellbook_open():
		close_spellbook()
		return
	if _player_menu_open:
		close_player_menu()
	if _spellbook_panel.has_method("configure_loadout"):
		_spellbook_panel.call("configure_loadout", _loadout)
	if _spellbook_panel.has_method("set_selected_spell_id"):
		_spellbook_panel.call("set_selected_spell_id", _selected_spell_id)
	_spellbook_panel.call("open_book")


func close_spellbook() -> void:
	if is_spellbook_open():
		_spellbook_panel.call("close_book")


func is_spellbook_open() -> bool:
	return (
		_spellbook_panel != null
		and _spellbook_panel.has_method("is_open")
		and bool(_spellbook_panel.call("is_open"))
	)


func _setup_spellbook_panel() -> void:
	_spellbook_panel = SpellbookPanelScene.instantiate()
	_spellbook_panel.name = "SpellbookPanel"
	add_child(_spellbook_panel)
	if _spellbook_panel.has_signal("spell_selected"):
		_spellbook_panel.spell_selected.connect(_on_codex_spell_selected)
	if _spellbook_panel.has_signal("closed"):
		_spellbook_panel.closed.connect(_on_spellbook_closed)


func _on_spellbook_closed() -> void:
	if _player_menu_open or get_tree().paused:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_selected_spell_id() -> String:
	return _selected_spell_id


func reveal_cast_spell(spell: Resource, color: Color = Color(1, 1, 1, 1)) -> void:
	## Typewriter the spell display name above the hotbar (box invisible; glyphs only).
	if spell_word_banner == null or not spell_word_banner.has_method("reveal"):
		return
	var def := spell as SpellDefinitionScript
	if def == null:
		return
	var word := def.display_name.strip_edges()
	if word.is_empty():
		word = def.id.capitalize()
	## Category color from the spell; optional override when caller passes non-white.
	var ink := def.get_word_display_color()
	if not color.is_equal_approx(Color(1, 1, 1, 1)):
		ink = color
	spell_word_banner.call("reveal", word, ink)


func clear_spell_word() -> void:
	if spell_word_banner != null and spell_word_banner.has_method("clear"):
		spell_word_banner.call("clear")


func _bind_health_pool(pool: Character) -> void:
	if (
		_health_pool != null
		and _health_pool.changed.is_connected(_on_health_changed)
	):
		_health_pool.changed.disconnect(_on_health_changed)
	_health_pool = pool
	if _health_pool == null:
		return
	if not _health_pool.changed.is_connected(_on_health_changed):
		_health_pool.changed.connect(_on_health_changed)
	_apply_health_bar(_health_pool.current_health, _health_pool.max_health)


func show_mana(
	current: float,
	maximum: float = 100.0,
	_fill_color: Color = Color(0.35, 0.14, 0.32, 1.0)
) -> void:
	if _health_root != null:
		_health_root.visible = true
	_apply_health_bar(current, maximum)


func set_mana(
	current: float,
	maximum: float = 100.0,
	_fill_color: Color = Color(0.35, 0.14, 0.32, 1.0)
) -> void:
	_apply_health_bar(current, maximum)


func hide_mana() -> void:
	## Mana chrome is gone; keep the HP bar (v11). Callers still invoke this.
	pass


func _on_health_changed(current: float, maximum: float) -> void:
	if _health_pool == null or not is_instance_valid(_health_pool):
		return
	_apply_health_bar(current, maximum)


func _apply_health_bar(current: float, maximum: float) -> void:
	if _health_bar == null:
		return
	_health_bar.tween_amount(current, maximum, 0.15)


func _bind_health_bar() -> void:
	if _health_bar == null:
		return
	_health_root = _health_bar


func _bottom_hud_half_width() -> float:
	var spell_w := HudSpellBarScript.bar_width()
	var inv_w := HudItemBarScript.bar_width()
	var tip_w := 108.0
	return (spell_w + inv_w + tip_w + BOTTOM_HUD_BAR_GAP_PX * 2.0) * 0.5


func _setup_bottom_hud() -> void:
	var half_w := _bottom_hud_half_width()
	var bottom := BOTTOM_HUD_MARGIN_PX
	var top := bottom + BOTTOM_HUD_ROW_HEIGHT_PX
	var anchor := MarginContainer.new()
	anchor.name = "BottomHudMargin"
	anchor.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor.offset_left = -half_w
	anchor.offset_top = -top
	anchor.offset_right = half_w
	anchor.offset_bottom = -bottom
	anchor.grow_horizontal = Control.GROW_DIRECTION_BOTH
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", int(BOTTOM_HUD_BAR_GAP_PX))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(row)

	_spell_bar = HudSpellBarScript.new()
	_spell_bar.name = "HudSpellBar"
	_conjure_tip = HudConjureTipScript.new()
	_conjure_tip.name = "HudConjureTip"
	_item_bar = HudItemBarScript.new()
	_item_bar.name = "HudItemBar"

	var spells_row := HBoxContainer.new()
	spells_row.name = "SpellsRow"
	spells_row.add_theme_constant_override("separation", 10)
	spells_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spells_row.add_child(_spell_bar)
	spells_row.add_child(_conjure_tip)
	var spells_section: HudSectionScript = HudSectionScript.new()
	spells_section.name = "SpellsSection"
	spells_section.setup("Spells", spells_row)
	row.add_child(spells_section)

	var items_section: HudSectionScript = HudSectionScript.new()
	items_section.name = "ItemsSection"
	items_section.setup("Items", _item_bar)
	row.add_child(items_section)
	_refresh_spell_hotbar()
	_refresh_hotbar()


func _refresh_spell_hotbar() -> void:
	if _spell_bar == null:
		return
	_spell_bar.configure(_spell_hotbar, _loadout)
	if _conjure_tip != null:
		_conjure_tip.refresh()


func _refresh_hotbar() -> void:
	if _item_bar == null:
		return
	_item_bar.configure(_inventory)


func show_casting_state(
	state: String,
	spell: Resource,
	from_tome: bool = false,
	free_cast: bool = false
) -> void:
	if spell == null and not free_cast:
		if not _from_tome:
			casting_panel.visible = false
		return
	if free_cast:
		_show_free_cast_state(state)
		return
	var def := spell as SpellDefinitionScript
	if def == null:
		casting_panel.visible = false
		return
	_from_tome = from_tome
	_active_spell = spell
	casting_panel.visible = true
	if from_tome:
		casting_title.text = "Tome: Learning %s" % def.display_name
		casting_words.text = 'Incantation: "%s"' % def.get_incantation_text()
		casting_guide.text = def.get_tome_lesson_text()
	else:
		casting_title.text = "Casting: %s" % def.display_name
		casting_words.text = 'Incantation: "%s"' % def.get_incantation_text()
		var guide_parts: PackedStringArray = []
		var timing: String = def.get_timing_guide_text()
		var pitch: String = def.get_pitch_guide_text()
		if not timing.is_empty():
			guide_parts.append(timing)
		if not pitch.is_empty():
			guide_parts.append(pitch)
		casting_guide.text = "\n".join(guide_parts)
	var leave_hint := "\n\nPress [F] to leave the tome." if from_tome else ""
	match state:
		"arming":
			casting_status.text = "Get ready..."
			casting_detail.text = def.get_listen_coaching_text() + leave_hint
			mic_level_bar.visible = false
			casting_feedback.text = ""
		"listening":
			casting_status.text = "Speak now!"
			casting_detail.text = def.get_listen_coaching_text() + leave_hint
			mic_level_bar.visible = true
			mic_level_bar.value = 0.0
			casting_feedback.text = ""
		"validating":
			casting_status.text = "Checking your cast..."
			casting_detail.text = ""
			mic_level_bar.visible = false
		"coaching":
			casting_status.text = "Not quite — adjust and try again"
			mic_level_bar.visible = false
		_:
			casting_status.text = ""
			if not from_tome:
				casting_detail.text = ""
			mic_level_bar.visible = false
	if state != "coaching":
		casting_feedback.text = ""


func _show_free_cast_state(state: String) -> void:
	_from_tome = false
	casting_panel.visible = true
	casting_title.text = "Voice cast"
	casting_words.text = "Say any spell you know"
	casting_guide.text = _format_known_incantations()
	match state:
		"arming":
			casting_status.text = "Get ready..."
			casting_detail.text = casting_guide.text
			mic_level_bar.visible = false
			casting_feedback.text = ""
		"listening":
			casting_status.text = "Speak now!"
			mic_level_bar.visible = true
			mic_level_bar.value = 0.0
			casting_feedback.text = ""
		"validating":
			casting_status.text = "Identifying your spell..."
			casting_detail.text = ""
			mic_level_bar.visible = false
		_:
			casting_status.text = ""
			casting_detail.text = ""
			mic_level_bar.visible = false


func _format_known_incantations() -> String:
	if _loadout == null:
		return ""
	var known: Array[String] = _loadout.get_known_spell_ids()
	if known.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for spell_id in known:
		var spell: Resource = _loadout.get_spell_definition(spell_id)
		var def := spell as SpellDefinitionScript
		if def != null:
			parts.append('"%s" (%s)' % [def.get_incantation_text(), def.display_name])
	return "Known: " + ", ".join(parts)


func _update_listen_level(level: float) -> void:
	if not casting_panel.visible:
		return
	mic_level_bar.value = clampf(level / 0.08, 0.0, 1.0)


func _update_listen_coaching(message: String) -> void:
	if not casting_panel.visible or message.is_empty():
		return
	if _from_tome:
		casting_detail.text = message + "\n\nPress [F] to leave the tome."
	else:
		casting_detail.text = message


func hide_casting() -> void:
	casting_panel.visible = false
	casting_feedback.text = ""
	casting_detail.text = ""
	_active_spell = null
	_from_tome = false
	_coaching_countdown = 0.0


func show_cast_feedback(result: RefCounted, from_tome: bool = false) -> void:
	if result == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	if result.has_method("get_coaching_lines"):
		lines = result.get_coaching_lines(from_tome)
	elif result.has_method("get_feedback_lines"):
		lines = result.get_feedback_lines()
	if lines.is_empty():
		return
	mic_level_bar.visible = false
	casting_feedback.text = lines[0]
	if lines.size() > 1:
		casting_detail.text = "\n".join(lines.slice(1))
	else:
		casting_detail.text = ""
	if from_tome:
		_coaching_countdown = 2.0


func show_spell_learned(spell: Resource, validation: RefCounted = null) -> void:
	var def := spell as SpellDefinitionScript
	if def == null:
		return
	_from_tome = false
	_active_spell = spell
	casting_panel.visible = true
	casting_title.text = "Spell Learned!"
	casting_words.text = def.display_name
	casting_guide.text = def.get_learned_confirmation_text()
	casting_status.text = "The tome's magic is yours now."
	casting_feedback.text = 'Incantation: "%s"' % def.get_incantation_text()
	if validation != null and validation.has_method("get_speech_match_line") \
			and not validation.heard_text.is_empty():
		casting_detail.text = validation.get_speech_match_line()
	else:
		casting_detail.text = ""
	mic_level_bar.visible = false


func show_cast_success(spell: Resource, validation: RefCounted = null) -> void:
	var def := spell as SpellDefinitionScript
	if def == null:
		return
	_from_tome = false
	_active_spell = spell
	casting_panel.visible = true
	casting_title.text = "Cast successful: %s" % def.display_name
	casting_words.text = 'Incantation: "%s"' % def.get_incantation_text()
	casting_guide.text = ""
	casting_status.text = "Success!"
	casting_feedback.text = def.get_cast_success_text()
	if validation != null and validation.has_method("get_speech_match_line") \
			and not validation.heard_text.is_empty():
		casting_detail.text = validation.get_speech_match_line()
	else:
		casting_detail.text = ""
	mic_level_bar.visible = false


func update_tome_coaching_countdown(seconds_left: float) -> void:
	if not _from_tome or not casting_panel.visible:
		return
	_coaching_countdown = seconds_left
	var countdown_line := "Next attempt in %.0fs..." % maxf(0.0, seconds_left)
	if casting_detail.text.is_empty():
		casting_detail.text = countdown_line
	elif not casting_detail.text.contains("Next attempt"):
		casting_detail.text += "\n" + countdown_line
	else:
		var parts: PackedStringArray = casting_detail.text.split("\n")
		var kept: PackedStringArray = PackedStringArray()
		for part in parts:
			if not str(part).begins_with("Next attempt"):
				kept.append(str(part))
		kept.append(countdown_line)
		casting_detail.text = "\n".join(kept)


func _on_codex_spell_selected(spell_id: String) -> void:
	_selected_spell_id = spell_id


func _on_spell_learned(spell_id: String) -> void:
	_selected_spell_id = spell_id
	if _spellbook_panel == null:
		return
	if _spellbook_panel.has_method("set_selected_spell_id"):
		_spellbook_panel.call("set_selected_spell_id", spell_id)
	if is_spellbook_open() and _spellbook_panel.has_method("refresh_pages"):
		_spellbook_panel.call("refresh_pages")


func _process(_delta: float) -> void:
	_update_aim_cursor_visibility()
	_refresh_spell_hotbar()


func _update_aim_cursor_visibility() -> void:
	if aim_cursor == null:
		return
	# Matches FPS aim: captured mouse uses the screen-center crosshair.
	aim_cursor.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _refresh_player_menu_content() -> void:
	if player_menu != null and player_menu.has_method("refresh"):
		player_menu.refresh(_objective_lines)


func _on_loadout_changed() -> void:
	if is_spellbook_open() and _spellbook_panel.has_method("refresh_pages"):
		_spellbook_panel.call("refresh_pages")
	if _player_menu_open:
		_refresh_player_menu_content()
