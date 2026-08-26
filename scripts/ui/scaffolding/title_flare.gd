@tool
extends Control

## Bronze rule with a diamond. Hide the rule and pin the gem for side flares.

enum Align { LEFT, CENTER, RIGHT }

@export var show_rule: bool = true:
	set(value):
		show_rule = value
		_apply_chrome()

@export var diamond_align: Align = Align.CENTER:
	set(value):
		diamond_align = value
		_apply_chrome()

@export var diamond_swatch: UiPalette.Swatch = UiPalette.Swatch.BRONZE:
	set(value):
		diamond_swatch = value
		_apply_chrome()


func _ready() -> void:
	_apply_chrome()


func _apply_chrome() -> void:
	var rule := get_node_or_null("Rule") as Control
	var diamond := get_node_or_null("Diamond") as ColorRect
	if rule != null:
		rule.visible = show_rule
	if diamond == null:
		return
	diamond.color = UiPalette.swatch_color(diamond_swatch)
	diamond.anchor_top = 0.5
	diamond.anchor_bottom = 0.5
	diamond.offset_top = -4.0
	diamond.offset_bottom = 4.0
	match diamond_align:
		Align.LEFT:
			diamond.anchor_left = 0.0
			diamond.anchor_right = 0.0
			diamond.offset_left = 0.0
			diamond.offset_right = 8.0
			diamond.grow_horizontal = Control.GROW_DIRECTION_END
		Align.RIGHT:
			diamond.anchor_left = 1.0
			diamond.anchor_right = 1.0
			diamond.offset_left = -8.0
			diamond.offset_right = 0.0
			diamond.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_:
			diamond.anchor_left = 0.5
			diamond.anchor_right = 0.5
			diamond.offset_left = -4.0
			diamond.offset_right = 4.0
			diamond.grow_horizontal = Control.GROW_DIRECTION_BOTH
