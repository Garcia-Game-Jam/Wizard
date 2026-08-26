class_name HudSection
extends VBoxContainer

## Titled HUD cluster: label, flare, then the slotted row.

const TitleFlareScene := preload("res://scenes/ui/scaffolding/title_flare.tscn")


func setup(title: String, body: Control) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	var header := Label.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.text = title
	header.add_theme_font_size_override("font_size", 12)
	header.theme_type_variation = "TitleLabel"
	add_child(header)
	var flare: Control = TitleFlareScene.instantiate()
	flare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flare)
	if body.get_parent() != null:
		body.get_parent().remove_child(body)
	add_child(body)
