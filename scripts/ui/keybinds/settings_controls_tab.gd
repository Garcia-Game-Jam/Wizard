class_name SettingsControlsTab
extends VBoxContainer

## Catalog-driven keybind list. Owns listen-mode for the Controls tab.

signal binds_changed

const CatalogScript := preload("res://scripts/ui/keybinds/input_rebind_catalog.gd")
const StoreScript := preload("res://scripts/ui/keybinds/input_rebind_store.gd")
const RowScene := preload("res://scenes/ui/keybinds/keybind_row.tscn")
const KeybindRowScript := preload("res://scripts/ui/keybinds/keybind_row.gd")

var _listening_action: String = ""
var _ignore_activating_click: bool = false
var _rows: Dictionary = {}

@onready var _list: VBoxContainer = $MarginContainer/ScrollContainer/List
@onready var _hint: Label = $FooterRow/HintLabel
@onready var _restore_defaults_button: Button = $FooterRow/RestoreDefaultsButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_restore_defaults_button.pressed.connect(_on_restore_defaults_pressed)
	rebuild()


func is_listening() -> bool:
	return not _listening_action.is_empty()


func cancel_listen() -> void:
	_listening_action = ""
	_ignore_activating_click = false
	_refresh_rows()


func rebuild() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	var last_group := ""
	var group_box: VBoxContainer = null
	for entry in CatalogScript.entries():
		var group := str(entry.get("group", ""))
		if group != last_group:
			group_box = _add_group_section(group)
			last_group = group
		var row: KeybindRowScript = RowScene.instantiate()
		group_box.add_child(row)
		row.setup(str(entry.get("action", "")), str(entry.get("label", "")))
		row.rebind_pressed.connect(_on_rebind_pressed)
		_rows[row.action_name] = row
	_refresh_rows()


func _add_group_section(group: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.12, 0.72)
	style.border_color = Color(0.82, 0.70, 0.38, 0.95)
	style.border_width_left = 4
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	_list.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	panel.add_child(inner)
	var header := Label.new()
	header.text = group.to_upper()
	header.add_theme_color_override("font_color", Color(0.90, 0.84, 0.68, 1))
	header.add_theme_font_size_override("font_size", 15)
	inner.add_child(header)
	var rule := HSeparator.new()
	rule.modulate = Color(0.82, 0.70, 0.38, 0.75)
	inner.add_child(rule)
	return inner


func _input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		return
	if _ignore_activating_click and event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			_ignore_activating_click = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.physical_keycode == KEY_ESCAPE:
			cancel_listen()
			get_viewport().set_input_as_handled()
			return
		_finish_listen(key)
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed:
			return
		_finish_listen(mouse)


func _finish_listen(event: InputEvent) -> void:
	var packed := StoreScript.pack_event(event)
	if packed.is_empty():
		return
	StoreScript.apply_packed(_listening_action, packed)
	_listening_action = ""
	_ignore_activating_click = false
	_refresh_rows()
	binds_changed.emit()
	get_viewport().set_input_as_handled()


func _on_rebind_pressed(action: String) -> void:
	if action.is_empty():
		return
	_listening_action = action
	_ignore_activating_click = true
	_refresh_rows()


func _on_restore_defaults_pressed() -> void:
	cancel_listen()
	StoreScript.apply_snapshot(SettingsManager.get_input_project_defaults())
	_refresh_rows()
	binds_changed.emit()


func _refresh_rows() -> void:
	var conflicts := StoreScript.conflict_action_names()
	for action in _rows.keys():
		var row: KeybindRowScript = _rows[action]
		row.set_listening(action == _listening_action)
		if action != _listening_action:
			row.refresh()
		row.set_conflict(conflicts.has(action))
	if _hint == null:
		return
	if not _listening_action.is_empty():
		_hint.text = "Press a key or mouse button. Esc cancels."
	elif not conflicts.is_empty():
		_hint.text = "Yellow binds are used by more than one action. That is allowed."
	else:
		_hint.text = "Click a bind to remap it."
