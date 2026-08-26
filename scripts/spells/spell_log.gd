class_name SpellLog
extends RefCounted

## Logging helper for spell/STT code paths that must compile before autoloads init.

## Test hook: true when debug() routed through TomeDebug on the main thread.
static var last_used_scene_tree: bool = false


static func debug(tag: String, message: String) -> void:
	last_used_scene_tree = false
	if not Thread.is_main_thread():
		print("[TomeDebug:%s] %s" % [tag, message])
		return
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var tome: Node = loop.root.get_node_or_null("/root/TomeDebug")
		if tome != null and tome.has_method("log"):
			tome.call("log", tag, message)
			last_used_scene_tree = true
			return
	print("[TomeDebug:%s] %s" % [tag, message])
