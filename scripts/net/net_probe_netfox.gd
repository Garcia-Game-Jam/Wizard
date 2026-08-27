class_name NetProbeNetfox
extends NetProbe

## netfox binding for NetProbe. The only file in the diagnostics path that knows
## netfox signal names, autoloads, and ProjectSettings keys.

var _loop_start_us := 0
var _loop_us := 0
var _loop_ticks := 0
var _pending := false
var _bound := false


func _setup() -> void:
	var net_time := autoload("NetworkTime")
	if net_time == null or _bound:
		return
	net_time.before_tick_loop.connect(_on_before_tick_loop)
	net_time.before_tick.connect(_on_before_tick)
	net_time.after_tick_loop.connect(_on_after_tick_loop)
	_bound = true


func backend_id() -> String:
	return "netfox"


func is_running() -> bool:
	var net_time := autoload("NetworkTime")
	return net_time != null and bool(net_time.call("is_initial_sync_done"))


func current_tick() -> int:
	var net_time := autoload("NetworkTime")
	return int(net_time.get("tick")) if net_time != null else 0


func rollback_depth() -> int:
	var perf := autoload("NetworkPerformance")
	if perf != null and perf.has_method("get_rollback_ticks"):
		return int(perf.call("get_rollback_ticks"))
	return _loop_ticks


func clock_health() -> Dictionary:
	var net_time := autoload("NetworkTime")
	if net_time == null:
		return super.clock_health()
	var offset := 0.0
	if bool(net_time.call("is_initial_sync_done")):
		offset = float(net_time.get("clock_offset"))
	return {
		"stretch": float(net_time.get("clock_stretch_factor")),
		"offset": offset,
		"rtt": float(net_time.get("remote_rtt")),
	}


func pop_tick_loop() -> Dictionary:
	if not _pending:
		return {}
	_pending = false
	return {"us": _loop_us, "ticks": _loop_ticks}


func config_snapshot() -> Dictionary:
	return {
		"physics_ticks_per_second": ProjectSettings.get_setting(
			"physics/common/physics_ticks_per_second", 60
		),
		"sync_to_physics": ProjectSettings.get_setting("netfox/time/sync_to_physics", false),
		"tickrate": ProjectSettings.get_setting("netfox/time/tickrate", 30),
		"max_ticks_per_frame": ProjectSettings.get_setting(
			"netfox/time/max_ticks_per_frame", 8
		),
		"rollback_enabled": ProjectSettings.get_setting("netfox/rollback/enabled", true),
		"enable_diff_states": ProjectSettings.get_setting(
			"netfox/rollback/enable_diff_states", true
		),
		"enable_input_broadcast": ProjectSettings.get_setting(
			"netfox/rollback/enable_input_broadcast", false
		),
	}


func _on_before_tick_loop() -> void:
	_loop_start_us = Time.get_ticks_usec()
	_loop_ticks = 0


func _on_before_tick(_delta: float, _tick: int) -> void:
	_loop_ticks += 1


func _on_after_tick_loop() -> void:
	_loop_us = Time.get_ticks_usec() - _loop_start_us
	_pending = true
