@tool
extends HBoxContainer

## Settings-style value slider: HSlider + clickable number field.
## Dividers, max, int/float, percent, default, and tick labels are Inspector knobs.

signal value_changed(value: float)

enum ValueKind {
	FLOAT,
	INT,
}

const DEFAULT_SLIDER_SIZE := Vector2i(200, 36)
const DEFAULT_VALUE_FIELD_WIDTH := 56
const _TRACK_PAD := 4.0

@export var slider_size: Vector2i = DEFAULT_SLIDER_SIZE:
	set(value):
		var next := Vector2i(maxi(value.x, 80), maxi(value.y, 28))
		if next == slider_size:
			return
		slider_size = next
		_apply_chrome()

@export var value_field_width: int = DEFAULT_VALUE_FIELD_WIDTH:
	set(value):
		var next := maxi(value, 32)
		if next == value_field_width:
			return
		value_field_width = next
		_apply_chrome()

@export var min_value: float = 0.0:
	set(value):
		if is_equal_approx(value, min_value):
			return
		min_value = value
		_apply_chrome()

@export var max_value: float = 1.0:
	set(value):
		if is_equal_approx(value, max_value):
			return
		max_value = value
		_apply_chrome()

@export var value: float = 1.0:
	set(next):
		var clamped := _clamp_value(next)
		if is_equal_approx(clamped, value):
			_sync_value_to_controls()
			return
		value = clamped
		_sync_value_to_controls()

## Factory / reset point. Use the tool buttons below to copy either direction.
@export var default_value: float = 1.0:
	set(next):
		var clamped := _clamp_range(next)
		if is_equal_approx(clamped, default_value):
			return
		default_value = clamped

@export_tool_button("Set Current as Default")
var set_default_action: Callable = set_current_as_default
@export_tool_button("Reset to Default")
var reset_default_action: Callable = reset_to_default

## Interior dividers (0 = none). 1 = midpoint (halves), 2 = thirds, 3 = quarters, …
@export_range(0, 32, 1) var tick_divisions: int = 0:
	set(next):
		var clamped := maxi(next, 0)
		if clamped == tick_divisions:
			return
		tick_divisions = clamped
		_apply_chrome()

@export var show_tick_labels: bool = true:
	set(next):
		if next == show_tick_labels:
			return
		show_tick_labels = next
		_apply_chrome()

## When true and tick_divisions > 0, the grabber snaps to ends and each divider.
@export var snap_to_divisions: bool = false:
	set(next):
		if next == snap_to_divisions:
			return
		snap_to_divisions = next
		_apply_chrome()

@export var value_kind: ValueKind = ValueKind.FLOAT:
	set(next):
		if next == value_kind:
			return
		value_kind = next
		_apply_chrome()

@export var show_as_percent: bool = true:
	set(next):
		if next == show_as_percent:
			return
		show_as_percent = next
		_apply_chrome()

## 0 = auto step from kind / divisions. Otherwise the HSlider step.
@export var step_size: float = 0.0:
	set(next):
		var clamped := maxf(next, 0.0)
		if is_equal_approx(clamped, step_size):
			return
		step_size = clamped
		_apply_chrome()

@export var tick_swatch: UiPalette.Swatch = UiPalette.Swatch.BRONZE:
	set(next):
		if next == tick_swatch:
			return
		tick_swatch = next
		_apply_chrome()

@export var tick_label_swatch: UiPalette.Swatch = UiPalette.Swatch.SNOW_WHITE:
	set(next):
		if next == tick_label_swatch:
			return
		tick_label_swatch = next
		_apply_chrome()

var _editing_text := false
var _syncing := false
var _track_height: float = 22.0

@onready var _track_area: Control = $TrackArea
@onready var _slider: HSlider = $TrackArea/Slider
@onready var _ticks: Control = $TrackArea/TickMarks
@onready var _value_edit: LineEdit = $ValueEdit


func _ready() -> void:
	if not _slider.value_changed.is_connected(_on_slider_changed):
		_slider.value_changed.connect(_on_slider_changed)
	if not _value_edit.text_submitted.is_connected(_on_value_submitted):
		_value_edit.text_submitted.connect(_on_value_submitted)
	if not _value_edit.focus_entered.is_connected(_on_value_focus_entered):
		_value_edit.focus_entered.connect(_on_value_focus_entered)
	if not _value_edit.focus_exited.is_connected(_on_value_focus_exited):
		_value_edit.focus_exited.connect(_on_value_focus_exited)
	if not _track_area.resized.is_connected(_on_track_resized):
		_track_area.resized.connect(_on_track_resized)
	_apply_chrome()


func get_value() -> float:
	return value


func set_value_no_signal(next: float) -> void:
	_syncing = true
	value = next
	_syncing = false


func set_current_as_default() -> void:
	default_value = value


func reset_to_default() -> void:
	var next := _clamp_value(default_value)
	if is_equal_approx(next, value):
		_sync_value_to_controls()
		return
	value = next
	if not _syncing and is_node_ready():
		value_changed.emit(value)


func _apply_chrome() -> void:
	if not is_node_ready():
		return
	custom_minimum_size = Vector2(slider_size)
	_track_area.custom_minimum_size = Vector2(0, slider_size.y)
	_value_edit.custom_minimum_size = Vector2(value_field_width, slider_size.y)
	var lo := minf(min_value, max_value)
	var hi := maxf(min_value, max_value)
	if is_equal_approx(lo, hi):
		hi = lo + 1.0
	_slider.min_value = lo
	_slider.max_value = hi
	_slider.step = _resolved_step(lo, hi)
	## Native HSlider ticks sit under the bar — we draw into the track instead.
	_slider.tick_count = 0
	_slider.ticks_on_borders = false
	var clamped := _clamp_value(value)
	if not is_equal_approx(clamped, value):
		value = clamped
	var default_clamped := _clamp_range(default_value)
	if not is_equal_approx(default_clamped, default_value):
		default_value = default_clamped
	_paint_slider_outline()
	_layout_track()
	_refresh_ticks(lo, hi)
	_sync_value_to_controls()


func _layout_track() -> void:
	var label_band := 14.0 if show_tick_labels and tick_divisions > 0 else 0.0
	var track_h := maxf(float(slider_size.y) - label_band, 16.0)
	_slider.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_slider.offset_left = 0.0
	_slider.offset_right = 0.0
	_slider.offset_top = 0.0
	_slider.offset_bottom = track_h
	_ticks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ticks.offset_left = _TRACK_PAD
	_ticks.offset_right = -_TRACK_PAD
	_ticks.offset_top = 0.0
	_ticks.offset_bottom = 0.0
	_track_height = track_h


func _refresh_ticks(lo: float, hi: float) -> void:
	if _ticks.has_method("configure"):
		_ticks.call(
			"configure",
			tick_divisions,
			lo,
			hi,
			show_tick_labels,
			show_as_percent,
			value_kind == ValueKind.INT,
			_track_height,
			tick_swatch,
			tick_label_swatch
		)


func _sync_value_to_controls() -> void:
	if not is_node_ready():
		return
	_slider.set_block_signals(true)
	_slider.value = value
	_slider.set_block_signals(false)
	if not _editing_text:
		_value_edit.text = _format_value(value)


func _resolved_step(lo: float, hi: float) -> float:
	if step_size > 0.0:
		return step_size
	if snap_to_divisions and tick_divisions > 0:
		return (hi - lo) / float(tick_divisions + 1)
	if value_kind == ValueKind.INT:
		return 1.0
	return 0.01


func _clamp_range(next: float) -> float:
	var lo := minf(min_value, max_value)
	var hi := maxf(min_value, max_value)
	if is_equal_approx(lo, hi):
		hi = lo + 1.0
	return clampf(next, lo, hi)


func _clamp_value(next: float) -> float:
	var lo := minf(min_value, max_value)
	var hi := maxf(min_value, max_value)
	if is_equal_approx(lo, hi):
		hi = lo + 1.0
	var clamped := clampf(next, lo, hi)
	var step := _resolved_step(lo, hi)
	if step > 0.0:
		clamped = lo + round((clamped - lo) / step) * step
		clamped = clampf(clamped, lo, hi)
	if value_kind == ValueKind.INT:
		clamped = float(roundi(clamped))
	return clamped


func _paint_slider_outline() -> void:
	if _slider.has_theme_stylebox_override("slider"):
		_slider.remove_theme_stylebox_override("slider")
	var src := _slider.get_theme_stylebox("slider")
	if not src is StyleBoxFlat:
		return
	var box := (src as StyleBoxFlat).duplicate() as StyleBoxFlat
	## Taller track so division marks sit inside the bar, not under it.
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	UiPalette.apply_outline(box, true, UiPalette.Swatch.BRONZE, 1)
	_slider.add_theme_stylebox_override("slider", box)


func _format_value(amount: float) -> String:
	if show_as_percent:
		## 1.0 = 100% (unity). Mic boost past midpoint can show >100%.
		return "%d%%" % roundi(amount * 100.0)
	if value_kind == ValueKind.INT:
		return str(roundi(amount))
	var text := "%.2f" % amount
	while text.ends_with("0") and text.contains("."):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text


func _parse_value_text(raw: String) -> Variant:
	var text := raw.strip_edges()
	if text.is_empty():
		return null
	var as_percent := text.ends_with("%") or show_as_percent
	if text.ends_with("%"):
		text = text.substr(0, text.length() - 1).strip_edges()
	if not text.is_valid_float():
		return null
	var parsed := text.to_float()
	if as_percent:
		return parsed / 100.0
	return parsed


func _commit_value_text() -> void:
	_editing_text = false
	var parsed: Variant = _parse_value_text(_value_edit.text)
	if parsed == null:
		_sync_value_to_controls()
		return
	var next := _clamp_value(float(parsed))
	if is_equal_approx(next, value):
		_sync_value_to_controls()
		return
	value = next
	if not _syncing:
		value_changed.emit(value)


func _on_slider_changed(amount: float) -> void:
	var next := _clamp_value(amount)
	if is_equal_approx(next, value):
		_sync_value_to_controls()
		return
	value = next
	if not _syncing:
		value_changed.emit(value)


func _on_value_submitted(_text: String) -> void:
	_commit_value_text()
	_value_edit.release_focus()


func _on_value_focus_entered() -> void:
	_editing_text = true
	_value_edit.select_all()


func _on_value_focus_exited() -> void:
	if _editing_text:
		_commit_value_text()


func _on_track_resized() -> void:
	_layout_track()
	_ticks.queue_redraw()
