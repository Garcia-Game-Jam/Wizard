class_name HudSpellBar
extends HBoxContainer

## Compact bottom spell slots.

const SpellHotbarScript := preload("res://scripts/spells/spell_hotbar.gd")
const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")
const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")

const SLOT_SIZE := Vector2(64, 64)
const SLOT_GAP := 4

var _hotbar: Node
var _loadout: Node
var _cells: Array[PanelContainer] = []
var _fills: Array[ColorRect] = []
var _washes: Array[ColorRect] = []
var _key_icons: Array[TextureRect] = []
var _key_labels: Array[Label] = []
var _name_labels: Array[Label] = []
var _meta_labels: Array[Label] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", SLOT_GAP)
	_build()


static func bar_width() -> float:
	var n := float(SpellHotbarScript.SLOT_COUNT)
	return SLOT_SIZE.x * n + float(SLOT_GAP) * maxf(n - 1.0, 0.0)


func configure(hotbar: Node, loadout: Node) -> void:
	_hotbar = hotbar
	_loadout = loadout
	refresh()


func refresh() -> void:
	if _cells.is_empty():
		return
	var pending := (
		_hotbar != null
		and _hotbar.has_method("has_pending")
		and bool(_hotbar.call("has_pending"))
	)
	var selected := -1
	if _hotbar != null and _hotbar.has_method("get_selected_index"):
		selected = int(_hotbar.call("get_selected_index"))
	for i in _cells.size():
		_refresh_slot(i, pending, i == selected)


func _build() -> void:
	for i in SpellHotbarScript.SLOT_COUNT:
		_add_slot(i)


func _add_slot(_index: int) -> void:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = SLOT_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var wash := ColorRect.new()
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(0, 0, 0, 0)
	stack.add_child(wash)
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.visible = false
	fill.color = Color(0.08, 0.06, 0.12, 0.72)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(fill)
	var icon := InputPromptScript.make_hud_icon(18.0)
	icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	icon.anchor_right = 0.0
	icon.anchor_bottom = 0.0
	icon.offset_left = 3
	icon.offset_top = 3
	icon.offset_right = 21
	icon.offset_bottom = 21
	stack.add_child(icon)
	var key := _make_overlay_label(HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, 10)
	key.offset_left = 4
	key.offset_top = 3
	key.offset_right = -4
	key.offset_bottom = -4
	stack.add_child(key)
	var meta := _make_overlay_label(HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP, 10)
	meta.offset_left = 4
	meta.offset_top = 3
	meta.offset_right = -4
	meta.offset_bottom = -4
	stack.add_child(meta)
	var name_label := _make_overlay_label(HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_BOTTOM, 11)
	name_label.offset_left = 3
	name_label.offset_top = 18
	name_label.offset_right = -3
	name_label.offset_bottom = -4
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(name_label)
	cell.add_child(stack)
	add_child(cell)
	_cells.append(cell)
	_fills.append(fill)
	_washes.append(wash)
	_key_icons.append(icon)
	_key_labels.append(key)
	_name_labels.append(name_label)
	_meta_labels.append(meta)


func _make_overlay_label(
	h_align: HorizontalAlignment, v_align: VerticalAlignment, font_px: int
) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = h_align
	label.vertical_alignment = v_align
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	return label


func _refresh_slot(index: int, pending: bool, selected: bool) -> void:
	var action := SpellHotbarScript.SLOT_ACTIONS[index]
	var fallback := "?"
	if index < SpellHotbarScript.SLOT_FALLBACKS.size():
		fallback = SpellHotbarScript.SLOT_FALLBACKS[index]
	InputPromptScript.fill_bind_views(
		_key_icons[index], _key_labels[index], action, fallback
	)
	var spell_id := ""
	if _hotbar != null and _hotbar.has_method("get_slot"):
		spell_id = str(_hotbar.call("get_slot", index))
	var spell_name := ""
	var spell_color := Color(0.18, 0.14, 0.22, 1)
	if not spell_id.is_empty() and _hotbar != null and _hotbar.has_method("display_name"):
		spell_name = str(_hotbar.call("display_name", spell_id))
	if not spell_id.is_empty() and _hotbar != null and _hotbar.has_method("get_spell_at"):
		var spell: SpellDefinitionScript = _hotbar.call("get_spell_at", index) as SpellDefinitionScript
		if spell != null:
			spell_color = spell.get_display_color()
	var ammo := 0
	var ammo_cap := 0
	var remaining := 0.0
	var total_cd := 0.0
	var refill_left := 0.0
	if not spell_id.is_empty() and _loadout != null:
		if _loadout.has_method("ammo_max"):
			ammo_cap = int(_loadout.ammo_max(spell_id))
		if ammo_cap > 0:
			if _loadout.has_method("ammo_count"):
				ammo = int(_loadout.ammo_count(spell_id))
			if _loadout.has_method("remaining_ammo_refill_sec"):
				refill_left = float(_loadout.remaining_ammo_refill_sec(spell_id))
			if _loadout.has_method("ammo_refill_sec"):
				total_cd = float(_loadout.ammo_refill_sec(spell_id))
			remaining = refill_left if ammo <= 0 else 0.0
		elif _loadout.has_method("remaining_cooldown_sec"):
			remaining = float(_loadout.remaining_cooldown_sec(spell_id))
			if remaining > 0.0 and _loadout.has_method("get_spell_definition"):
				var def: Resource = _loadout.get_spell_definition(spell_id)
				if def != null:
					total_cd = float(def.get("cooldown_sec"))
	var empty_ammo := ammo_cap > 0 and ammo <= 0
	var cooling := remaining > 0.0 or empty_ammo
	_name_labels[index].text = spell_name
	if ammo_cap > 0 and ammo > 0:
		_meta_labels[index].text = str(ammo)
	elif remaining > 0.0:
		_meta_labels[index].text = "%.1f" % remaining
	else:
		_meta_labels[index].text = ""
	var ink := UiPalette.TEXT_MUTED if cooling else UiPalette.TEXT_PRIMARY
	_name_labels[index].add_theme_color_override("font_color", ink)
	_meta_labels[index].add_theme_color_override("font_color", ink)
	_washes[index].color = (
		Color(spell_color.r, spell_color.g, spell_color.b, 0.22)
		if not spell_id.is_empty()
		else Color(0, 0, 0, 0)
	)
	_apply_slot_style(_cells[index], pending, selected, cooling, spell_id.is_empty())
	if ammo_cap > 0 and ammo < ammo_cap and total_cd > 0.0:
		_apply_fill(index, refill_left, total_cd)
	else:
		_apply_fill(index, remaining, total_cd)


func _apply_slot_style(
	cell: PanelContainer,
	pending: bool,
	selected: bool,
	cooling: bool,
	empty: bool
) -> void:
	var style := UiPalette.hud_slot_style(pending or selected, empty or cooling)
	cell.add_theme_stylebox_override("panel", style)


func _apply_fill(index: int, remaining: float, total_sec: float) -> void:
	var fill := _fills[index]
	if remaining <= 0.0 or total_sec <= 0.0:
		fill.visible = false
		return
	fill.visible = true
	var fraction := clampf(remaining / total_sec, 0.0, 1.0)
	fill.anchor_top = 1.0 - fraction
	fill.anchor_bottom = 1.0
	fill.offset_top = 0.0
	fill.offset_bottom = 0.0
	fill.offset_left = 0.0
	fill.offset_right = 0.0
