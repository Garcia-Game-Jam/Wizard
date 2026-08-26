class_name MonsterBookPage
extends PanelContainer

## Pre-baked summon-book leaf. Content is authored in the scene for editor preview.

signal select_pressed

@export var summon_entry: Resource

@onready var _select_button: Button = $Margin/VBox/SelectButton


func _ready() -> void:
	if _select_button != null:
		_select_button.pressed.connect(func() -> void: select_pressed.emit())


func get_catalog_entry() -> Dictionary:
	if summon_entry != null and summon_entry.has_method("to_catalog_entry"):
		return summon_entry.to_catalog_entry()
	return {}
