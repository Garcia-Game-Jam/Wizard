@tool
extends Control

## Tick marks + auto labels drawn on the value-slider track. Configured by the parent.

const _LABEL_FONT_SIZE := 10

var divisions: int = 0
var lo: float = 0.0
var hi: float = 1.0
var show_labels: bool = true
var show_as_percent: bool = true
var as_int: bool = false
var track_height: float = 0.0
var mark_swatch: UiPalette.Swatch = UiPalette.Swatch.BRONZE
var label_swatch: UiPalette.Swatch = UiPalette.Swatch.SNOW_WHITE


func configure(
	next_divisions: int,
	next_lo: float,
	next_hi: float,
	next_show_labels: bool,
	next_show_as_percent: bool,
	next_as_int: bool,
	next_track_height: float,
	next_mark_swatch: UiPalette.Swatch,
	next_label_swatch: UiPalette.Swatch
) -> void:
	divisions = maxi(next_divisions, 0)
	lo = next_lo
	hi = next_hi
	show_labels = next_show_labels
	show_as_percent = next_show_as_percent
	as_int = next_as_int
	track_height = next_track_height
	mark_swatch = next_mark_swatch
	label_swatch = next_label_swatch
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


func _draw() -> void:
	if divisions < 1 or size.x < 4.0:
		return
	var mark := UiPalette.swatch_color(mark_swatch)
	mark.a = 0.85
	var label_color := UiPalette.swatch_color(label_swatch)
	label_color.a = 0.72
	var track_bottom := track_height if track_height > 0.0 else size.y * 0.55
	var top := 2.0
	var bottom := maxf(track_bottom - 2.0, top + 2.0)
	## Interior dividers only: 1 → midpoint (halves), 2 → thirds, …
	var segments := divisions + 1
	for i in range(1, divisions + 1):
		var ratio := float(i) / float(segments)
		var x := size.x * ratio
		draw_line(Vector2(x, top), Vector2(x, bottom), mark, 1.0)
	if not show_labels:
		return
	var font := ThemeDB.fallback_font
	var span := hi - lo
	## Labels at ends and each divider: 0, 1/(n+1), …, 1.
	for i in range(segments + 1):
		var ratio := float(i) / float(segments)
		var amount := lo + span * ratio
		var caption := _format_tick(amount, ratio)
		var x := size.x * ratio
		var align := HORIZONTAL_ALIGNMENT_CENTER
		var text_x := x - 18.0
		if i == 0:
			align = HORIZONTAL_ALIGNMENT_LEFT
			text_x = x
		elif i == segments:
			align = HORIZONTAL_ALIGNMENT_RIGHT
			text_x = x - 36.0
		draw_string(
			font,
			Vector2(text_x, size.y - 2.0),
			caption,
			align,
			36.0,
			_LABEL_FONT_SIZE,
			label_color
		)


func _format_tick(amount: float, _ratio: float) -> String:
	if show_as_percent:
		## 1.0 = 100% (unity), so a 0–2 mic range labels 0% / 100% / 200%.
		return "%d%%" % roundi(amount * 100.0)
	if as_int:
		return str(roundi(amount))
	var text := "%.2f" % amount
	while text.ends_with("0") and text.contains("."):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text
