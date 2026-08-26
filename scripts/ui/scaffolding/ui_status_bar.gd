@tool
class_name UiStatusBar
extends VBoxContainer

## Resource bar (HP, etc.). Ticks/labels are editor exports; play only sets value.

@export var title: String = "Resource":
	set(value):
		title = value
		_apply_chrome()

@export var show_title: bool = true:
	set(value):
		show_title = value
		_apply_chrome()

@export var show_value_label: bool = false:
	set(value):
		show_value_label = value
		_apply_chrome()

@export var show_tick_labels: bool = false:
	set(value):
		show_tick_labels = value
		_apply_chrome()

@export_range(1, 20, 1) var tick_divisions: int = 4:
	set(value):
		tick_divisions = maxi(value, 1)
		_apply_chrome()

@export var bar_theme_variation: String = "":
	set(value):
		bar_theme_variation = value
		_apply_chrome()

@export var track_swatch: UiPalette.Swatch = UiPalette.Swatch.INK:
	set(value):
		track_swatch = value
		_apply_chrome()

@export var fill_swatch: UiPalette.Swatch = UiPalette.Swatch.BRONZE:
	set(value):
		fill_swatch = value
		_apply_chrome()

@export var flare_above: bool = false:
	set(value):
		flare_above = value
		_apply_chrome()

@export var flare_below: bool = false:
	set(value):
		flare_below = value
		_apply_chrome()

@export var flare_left: bool = false:
	set(value):
		flare_left = value
		_apply_chrome()

@export var flare_right: bool = false:
	set(value):
		flare_right = value
		_apply_chrome()

@export var flare_swatch: UiPalette.Swatch = UiPalette.Swatch.BRONZE:
	set(value):
		flare_swatch = value
		_apply_chrome()

var _bar_tween: Tween

@onready var _title_label: Label = $Header/Title
@onready var _value_label: Label = $Header/Value
@onready var _bar: ProgressBar = $Bar
@onready var _ticks: UiStatusBarTicks = $Bar/Ticks
@onready var _tick_labels: UiStatusBarTicks = $TickLabels
@onready var _flare_above: Control = $FlareAbove
@onready var _flare_below: Control = $FlareBelow
@onready var _flare_left: Control = $Bar/FlareLeft
@onready var _flare_right: Control = $Bar/FlareRight


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_chrome()
	if not Engine.is_editor_hint():
		set_amount(_bar.value, _bar.max_value)


func get_value() -> float:
	if _bar == null:
		return 0.0
	return _bar.value


func get_maximum() -> float:
	if _bar == null:
		return 0.0
	return _bar.max_value


func set_value(current: float) -> void:
	if _bar == null:
		return
	_stop_bar_tween()
	_bar.value = clampf(current, 0.0, _bar.max_value)
	_apply_value_text()


func set_maximum(maximum: float) -> void:
	if _bar == null:
		return
	_stop_bar_tween()
	var ratio := 0.0
	if _bar.max_value > 0.0:
		ratio = _bar.value / _bar.max_value
	_bar.max_value = maxf(maximum, 0.001)
	_bar.value = clampf(ratio * _bar.max_value, 0.0, _bar.max_value)
	_apply_value_text()
	_sync_tick_scale()


func set_amount(current: float, maximum: float) -> void:
	if _bar == null:
		return
	_stop_bar_tween()
	_bar.max_value = maxf(maximum, 0.001)
	_bar.value = clampf(current, 0.0, _bar.max_value)
	_apply_value_text()
	_sync_tick_scale()


func tween_amount(current: float, maximum: float, duration: float = 0.2) -> void:
	if _bar == null:
		return
	_stop_bar_tween()
	_bar.max_value = maxf(maximum, 0.001)
	_sync_tick_scale()
	var target := clampf(current, 0.0, _bar.max_value)
	if Engine.is_editor_hint() or duration <= 0.0:
		_bar.value = target
		_apply_value_text()
		return
	_bar_tween = create_tween()
	_bar_tween.tween_method(_set_bar_value, _bar.value, target, duration)


func tween_value(current: float, duration: float = 0.2) -> void:
	if _bar == null:
		return
	tween_amount(current, _bar.max_value, duration)


func _set_bar_value(current: float) -> void:
	if _bar == null:
		return
	_bar.value = current
	_apply_value_text()


func _stop_bar_tween() -> void:
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = null


func _apply_chrome() -> void:
	if _title_label == null or _bar == null:
		return
	_title_label.text = title
	_title_label.visible = show_title
	_value_label.visible = show_value_label
	_bar.theme_type_variation = bar_theme_variation
	_bar.show_percentage = false
	_apply_track_color()
	_apply_flares()
	_ticks.draw_lines = true
	_ticks.draw_labels = false
	_ticks.divisions = tick_divisions
	_tick_labels.draw_lines = false
	_tick_labels.draw_labels = show_tick_labels
	_tick_labels.visible = show_tick_labels
	_tick_labels.divisions = tick_divisions
	_sync_tick_scale()
	_apply_value_text()


func _apply_track_color() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiPalette.swatch_color(track_swatch)
	bg.set_corner_radius_all(4)
	bg.set_content_margin_all(2)
	UiPalette.apply_outline(bg, true, UiPalette.Swatch.BRONZE, 1)
	_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiPalette.swatch_color(fill_swatch)
	fill.set_corner_radius_all(3)
	fill.set_expand_margin_all(-1)
	_bar.add_theme_stylebox_override("fill", fill)


func _apply_flares() -> void:
	_show_flare(_flare_above, flare_above, true)
	_show_flare(_flare_below, flare_below, true)
	_show_flare(_flare_left, flare_left, false)
	_show_flare(_flare_right, flare_right, false)


func _show_flare(node: Control, enabled: bool, with_rule: bool) -> void:
	if node == null:
		return
	node.visible = enabled
	node.set("show_rule", with_rule)
	node.set("diamond_swatch", flare_swatch)


func _apply_value_text() -> void:
	if _value_label == null or _bar == null:
		return
	_value_label.text = "%d / %d" % [roundi(_bar.value), roundi(_bar.max_value)]


func _sync_tick_scale() -> void:
	if _bar == null:
		return
	_ticks.max_value = _bar.max_value
	_tick_labels.max_value = _bar.max_value
