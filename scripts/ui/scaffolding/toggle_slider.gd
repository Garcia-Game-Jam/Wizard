@tool
class_name ToggleSlider
extends Control

## Sliding window over named options. Inspector `options` is the label list.

signal selected_changed(index: int)

const DEFAULT_SLIDER_SIZE := Vector2i(200, 30)
const DEFAULT_OPTIONS := ["Left", "Right"]
const _INSET := 2.0
const _LABEL_FONT_SIZE := 14

@export var slider_size: Vector2i = DEFAULT_SLIDER_SIZE:
	set(value):
		var next := Vector2i(maxi(value.x, 48), maxi(value.y, 20))
		if next == slider_size:
			return
		slider_size = next
		custom_minimum_size = Vector2(slider_size)
		_apply_chrome()

@export var options: PackedStringArray = PackedStringArray(DEFAULT_OPTIONS):
	set(value):
		var next := _normalized_options(value)
		if next == options:
			return
		options = next
		if selected >= _option_count():
			set_selected(_option_count() - 1, false)
			return
		_apply_chrome()

@export_range(0, 32, 1) var selected: int = 0:
	set(value):
		var next := clampi(value, 0, _option_count() - 1)
		var changed := next != selected
		selected = next
		_apply_chrome()
		if (
			changed
			and _emit_selected_changed
			and not Engine.is_editor_hint()
			and is_node_ready()
		):
			selected_changed.emit(selected)

@export var disabled: bool = false:
	set(value):
		disabled = value
		modulate = Color(1, 1, 1, 0.55) if disabled else Color.WHITE

var _window_tween: Tween
var _emit_selected_changed: bool = true
var _option_labels: Array[Label] = []

@onready var _track: Panel = $Track
@onready var _window: Panel = $Track/Window
@onready var _options_row: HBoxContainer = $Track/Options


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(slider_size)
	_apply_chrome()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)


func get_options() -> PackedStringArray:
	return _normalized_options(options)


func set_options(names: PackedStringArray) -> void:
	options = names


func option_count() -> int:
	return _option_count()


func get_option_text(index: int) -> String:
	var names := get_options()
	if index < 0 or index >= names.size():
		return ""
	return names[index]


func find_option(text: String) -> int:
	return get_options().find(text)


func get_selected() -> int:
	return selected


func get_selected_text() -> String:
	return get_option_text(selected)


func set_selected(index: int, emit_change: bool = true) -> void:
	_emit_selected_changed = emit_change
	selected = index
	_emit_selected_changed = true


func set_selected_text(text: String, emit_change: bool = true) -> Error:
	var index := find_option(text)
	if index < 0:
		return ERR_DOES_NOT_EXIST
	set_selected(index, emit_change)
	return OK


func _option_count() -> int:
	return get_options().size()


func _normalized_options(names: PackedStringArray) -> PackedStringArray:
	if names.is_empty():
		return PackedStringArray(DEFAULT_OPTIONS)
	return names.duplicate()


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or disabled:
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var count := float(_option_count())
	var slice := size.x / count
	if slice <= 0.0:
		return
	selected = clampi(int(mouse.position.x / slice), 0, _option_count() - 1)
	accept_event()


func _on_resized() -> void:
	_place_window(false)


func _apply_chrome() -> void:
	if not is_node_ready():
		return
	_sync_option_labels()
	UiPalette.paint_panel_outline(_track, true, UiPalette.Swatch.BRONZE, 1)
	_place_window(not Engine.is_editor_hint() and is_inside_tree())


func _sync_option_labels() -> void:
	var names := get_options()
	while _option_labels.size() > names.size():
		var extra: Label = _option_labels.pop_back()
		if extra != null:
			extra.queue_free()
	while _option_labels.size() < names.size():
		var label := _make_option_label()
		_options_row.add_child(label, false, Node.INTERNAL_MODE_FRONT)
		_option_labels.append(label)
	for index in names.size():
		var label := _option_labels[index]
		label.text = names[index]
		_paint_option_label(label, index == selected)


func _make_option_label() -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"MutedLabel"
	label.add_theme_font_size_override("font_size", _LABEL_FONT_SIZE)
	return label


func _paint_option_label(label: Label, is_selected: bool) -> void:
	label.add_theme_color_override(
		"font_color",
		UiPalette.TEXT_PRIMARY if is_selected else UiPalette.TEXT_MUTED
	)


func _place_window(animate: bool) -> void:
	if _window == null:
		return
	var inner := Rect2(
		Vector2(_INSET, _INSET),
		Vector2(maxf(size.x - _INSET * 2.0, 1.0), maxf(size.y - _INSET * 2.0, 1.0))
	)
	var count := _option_count()
	var slice := inner.size.x / float(count)
	var index := clampi(selected, 0, count - 1)
	_window.size = Vector2(slice, inner.size.y)
	var target := Vector2(inner.position.x + slice * float(index), inner.position.y)
	if _window_tween != null and _window_tween.is_valid():
		_window_tween.kill()
	if animate:
		_window_tween = create_tween()
		_window_tween.tween_property(_window, "position", target, 0.16)
	else:
		_window.position = target
