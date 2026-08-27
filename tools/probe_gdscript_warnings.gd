extends SceneTree

## Forces project scripts/scenes to compile so Godot emits GDScript WARNINGs.
## Used by tools/check_gdscript_warnings.py — not for gameplay.

const SCAN_ROOTS := [
	"res://scripts",
	"res://tests",
]

const EXTRA_SCENES := [
	"res://scenes/arena.tscn",
	"res://scenes/menu.tscn",
	"res://scenes/characters/character.tscn",
	"res://scenes/characters/player.tscn",
]


func _init() -> void:
	call_deferred("_probe_and_quit")


func _probe_and_quit() -> void:
	for root_path in SCAN_ROOTS:
		_load_scripts_recursive(root_path)
	for scene_path in EXTRA_SCENES:
		if ResourceLoader.exists(scene_path):
			ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	quit(0)


func _load_scripts_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var child_path := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_load_scripts_recursive(child_path)
		elif entry.ends_with(".gd"):
			ResourceLoader.load(child_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		entry = dir.get_next()
	dir.list_dir_end()
