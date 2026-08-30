class_name NetDisplayCommit
extends RefCounted

## Bind irreversible presentation to NetworkTime.after_tick_loop (stun/death/impact).

const NetClockScript := preload("res://scripts/net/net_clock.gd")


static func bind(cb: Callable) -> void:
	var nt := _network_time()
	if nt != null and nt.has_signal("after_tick_loop") and not nt.after_tick_loop.is_connected(cb):
		nt.after_tick_loop.connect(cb)


static func unbind(cb: Callable) -> void:
	var nt := _network_time()
	if nt != null and nt.after_tick_loop.is_connected(cb):
		nt.after_tick_loop.disconnect(cb)


## Offline: commit now. Online: wait for the bound after_tick_loop callback.
static func request(cb: Callable) -> void:
	if not NetClockScript.is_ticking():
		cb.call()


static func _network_time() -> Node:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	return (tree as SceneTree).root.get_node_or_null("NetworkTime")
