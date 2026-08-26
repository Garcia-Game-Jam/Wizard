@tool
extends EditorPlugin

## Editor-only combat numbers dock. Not shipped in the player HUD.

const DockScript := preload("res://addons/combat_balance/combat_balance_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.name = "Combat Balance"
	var filesystem: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	_dock.set_meta("editor_filesystem", filesystem)
	add_control_to_bottom_panel(_dock, "Combat Balance")
	if filesystem != null and not filesystem.sources_changed.is_connected(_on_sources_changed):
		filesystem.sources_changed.connect(_on_sources_changed)


func _on_sources_changed(_exist: bool) -> void:
	if _dock != null and _dock.has_method("reload_if_spells_empty"):
		_dock.call("reload_if_spells_empty")


func _exit_tree() -> void:
	var filesystem: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if filesystem != null and filesystem.sources_changed.is_connected(_on_sources_changed):
		filesystem.sources_changed.disconnect(_on_sources_changed)
	if _dock == null:
		return
	remove_control_from_bottom_panel(_dock)
	_dock.queue_free()
	_dock = null
