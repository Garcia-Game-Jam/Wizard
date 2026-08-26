class_name TestUiScale
extends RefCounted

const UiScaleScript := preload("res://scripts/ui/ui_scale.gd")


func run() -> int:
	if UiScaleScript.scale_factor(Vector2(1920, 1080)) != 1.0:
		push_error("Expected 1080p viewport to use scale factor 1.0")
		return 1
	if UiScaleScript.scale_factor(Vector2(3840, 2160)) != 2.0:
		push_error("Expected 4K viewport to use scale factor 2.0")
		return 1
	if UiScaleScript.scaled(20.0, Vector2(3840, 2160), 14.0) != 40:
		push_error("Expected scaled button font to double at 4K")
		return 1
	return 0
