#!/usr/bin/env -S godot --headless --script
extends SceneTree

## Regenerates resources/ui/serious_wiz_biz_theme.tres from UiPalette.


func _init() -> void:
	var err := UiThemeBuilder.save_theme()
	if err != OK:
		push_error("Failed to save UI theme: %s" % error_string(err))
		quit(1)
		return
	print("Wrote ", UiThemeBuilder.THEME_PATH)
	quit(0)
