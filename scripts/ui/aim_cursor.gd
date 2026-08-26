class_name AimCursor
extends Control

## Screen-center aim marker for FPS cursor / captured mouse aim.

const OUTER_RADIUS := 6.0
const DOT_RADIUS_BASE := 1.2

## When true (HUD default), stretch to fill the parent. Settings preview sizes via layout.
@export var fill_parent := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fill_parent:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = 0.0
		offset_top = 0.0
		offset_right = 0.0
		offset_bottom = 0.0
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		grow_vertical = Control.GROW_DIRECTION_BOTH
	SettingsManager.settings_applied.connect(queue_redraw)


func _draw() -> void:
	var color := SettingsManager.crosshair_color
	color.a = clampf(SettingsManager.crosshair_opacity, 0.0, 1.0)
	var thickness := clampf(SettingsManager.crosshair_thickness, 0.5, 5.0)
	var center := size * 0.5
	if SettingsManager.crosshair_show_outer:
		draw_arc(center, OUTER_RADIUS, 0.0, TAU, 48, color, thickness, true)
	if SettingsManager.crosshair_show_dot:
		var dot_radius := maxf(DOT_RADIUS_BASE, thickness * 0.65)
		draw_circle(center, dot_radius, color)
