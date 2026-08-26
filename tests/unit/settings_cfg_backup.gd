extends RefCounted

## Shared user://settings.cfg backup/restore for settings unit tests.


static func backup(path: String, backup_path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var bytes := FileAccess.get_file_as_bytes(path)
	var out := FileAccess.open(backup_path, FileAccess.WRITE)
	if out == null:
		return false
	out.store_buffer(bytes)
	out.close()
	return true


static func restore(path: String, backup_path: String, had_cfg: bool) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if had_cfg and FileAccess.file_exists(backup_path):
		var bytes := FileAccess.get_file_as_bytes(backup_path)
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out != null:
			out.store_buffer(bytes)
			out.close()
		DirAccess.remove_absolute(backup_path)
	elif FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
