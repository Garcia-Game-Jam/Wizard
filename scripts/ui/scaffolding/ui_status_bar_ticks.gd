@tool
class_name UiStatusBarTicks
extends Control

## Increment marks or numbers. Redraws on resize / export change — not every frame.

@export var divisions: int = 4:
	set(value):
		divisions = maxi(value, 1)
		queue_redraw()

@export var draw_lines: bool = true:
	set(value):
		draw_lines = value
		queue_redraw()

@export var draw_labels: bool = false:
	set(value):
		draw_labels = value
		queue_redraw()

var max_value: float = 100.0:
	set(value):
		max_value = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


func _draw() -> void:
	if divisions < 1 or size.x < 2.0:
		return
	var ink := Color(UiPalette.TEXT_PRIMARY, 0.4)
	if draw_lines:
		var top := 1.0
		var bottom := size.y - 1.0
		for i in range(1, divisions):
			var x := size.x * (float(i) / float(divisions))
			draw_line(Vector2(x, top), Vector2(x, bottom), ink, 1.0)
	if not draw_labels:
		return
	var font := ThemeDB.fallback_font
	var font_size := 10
	for i in range(divisions + 1):
		var ratio := float(i) / float(divisions)
		var x := size.x * ratio
		var caption := str(roundi(max_value * ratio))
		draw_string(
			font,
			Vector2(x - 16.0, 11.0),
			caption,
			HORIZONTAL_ALIGNMENT_CENTER,
			32.0,
			font_size,
			ink
		)
