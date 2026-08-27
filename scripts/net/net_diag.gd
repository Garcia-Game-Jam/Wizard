extends Node

## Netcode / CPU diagnostics capture. Autoload.
##
## Slice 1: per-frame budget + rollback-depth + clock-health stream, written to
## user://diag/<timestamp>/frame.csv, with a self-describing meta.json. Nothing
## here touches gameplay code — it hooks NetworkTime signals and the Performance
## monitors only. Toggle with the "Netcode diagnostics" Developer setting, or
## force on for headless runs with WIZARD_NET_DIAG=1.
##
## Per-pawn correction data (predicted vs authoritative) lands in a later slice.

const ENV_FORCE_KEY := "WIZARD_NET_DIAG"
const SESSION_ROOT := "user://diag"
const FLUSH_EVERY := 240
const FRAME_HEADER := (
	"t_ms,frame,net_tick,tickloop_us,rb_depth,proc_ms,phys_ms,fps,"
	+ "clock_stretch,clock_offset,node_count,coll_pairs,active_objs,peers"
)

var _armed := false
var _capturing := false
var _session_dir := ""
var _frame_file: FileAccess = null
var _frame_rows: PackedStringArray = []
var _context: Dictionary = {}

var _tickloop_start_us := 0
var _last_tickloop_us := 0
var _ticks_this_loop := 0
var _last_loop_ticks := 0
var _signals_bound := false

var _overlay: CanvasLayer = null
var _overlay_label: Label = null
var _proc_ms_peak := 0.0
var _rb_depth_peak := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	if OS.get_environment(ENV_FORCE_KEY) == "1":
		set_enabled(true)


## Arm/disarm from the Developer setting. Arming alone does not open files —
## begin_session() (called when a match starts) does.
func set_enabled(value: bool) -> void:
	if _armed == value:
		return
	_armed = value
	if not _armed and _capturing:
		end_session()


func is_armed() -> bool:
	return _armed


func is_capturing() -> bool:
	return _capturing


## Open a capture folder for one match. context: {scenario, role, ...}.
func begin_session(context: Dictionary = {}) -> void:
	if not _armed or _capturing:
		return
	_context = context.duplicate(true)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_session_dir = "%s/%s" % [SESSION_ROOT, stamp]
	if DirAccess.make_dir_recursive_absolute(_session_dir) != OK:
		push_warning("NetDiag: could not create %s" % _session_dir)
		return
	_frame_file = FileAccess.open("%s/frame.csv" % _session_dir, FileAccess.WRITE)
	if _frame_file == null:
		push_warning("NetDiag: could not open frame.csv")
		return
	_frame_file.store_line(FRAME_HEADER)
	_frame_rows.clear()
	_write_meta()
	_bind_signals()
	_capturing = true
	_proc_ms_peak = 0.0
	_rb_depth_peak = 0
	_ensure_overlay()
	set_process(true)
	print("[NetDiag] capturing -> %s" % _session_dir)


## Flush and close the current capture folder.
func end_session() -> void:
	if not _capturing:
		return
	_capturing = false
	set_process(false)
	_flush_frames()
	if _frame_file != null:
		_frame_file.close()
		_frame_file = null
	_clear_overlay()
	print("[NetDiag] capture closed -> %s" % _session_dir)
	_session_dir = ""


func _process(_delta: float) -> void:
	if not _capturing:
		return
	var net_time := _autoload("NetworkTime")
	var tick := 0
	var stretch := 1.0
	var offset := 0.0
	if net_time != null:
		tick = int(net_time.get("tick"))
		stretch = float(net_time.get("clock_stretch_factor"))
		offset = _safe_clock_offset(net_time)

	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var rb_depth := _rollback_depth()

	var row := "%d,%d,%d,%d,%d,%.3f,%.3f,%.1f,%.4f,%.4f,%d,%d,%d,%d" % [
		Time.get_ticks_msec(),
		Engine.get_process_frames(),
		tick,
		_last_tickloop_us,
		rb_depth,
		proc_ms,
		phys_ms,
		Performance.get_monitor(Performance.TIME_FPS),
		stretch,
		offset,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		_peer_count(),
	]
	_frame_rows.append(row)
	if _frame_rows.size() >= FLUSH_EVERY:
		_flush_frames()

	_proc_ms_peak = maxf(_proc_ms_peak * 0.97, proc_ms)
	_rb_depth_peak = maxi(int(_rb_depth_peak * 0.9), rb_depth)
	_last_tickloop_us = 0
	_update_overlay(tick, rb_depth, stretch)


func _flush_frames() -> void:
	if _frame_file == null or _frame_rows.is_empty():
		return
	for line in _frame_rows:
		_frame_file.store_line(line)
	_frame_file.flush()
	_frame_rows.clear()


func _bind_signals() -> void:
	if _signals_bound:
		return
	var net_time := _autoload("NetworkTime")
	if net_time == null:
		return
	net_time.before_tick_loop.connect(_on_before_tick_loop)
	net_time.before_tick.connect(_on_before_tick)
	net_time.after_tick_loop.connect(_on_after_tick_loop)
	_signals_bound = true


func _on_before_tick_loop() -> void:
	_tickloop_start_us = Time.get_ticks_usec()
	_ticks_this_loop = 0


func _on_before_tick(_delta: float, _tick: int) -> void:
	_ticks_this_loop += 1


func _on_after_tick_loop() -> void:
	_last_tickloop_us = Time.get_ticks_usec() - _tickloop_start_us
	_last_loop_ticks = _ticks_this_loop


func _rollback_depth() -> int:
	var perf := _autoload("NetworkPerformance")
	if perf != null and perf.has_method("get_rollback_ticks"):
		return int(perf.call("get_rollback_ticks"))
	return _last_loop_ticks


func _safe_clock_offset(net_time: Node) -> float:
	## clock_offset's getter reaches into NetworkTimeSynchronizer and can throw
	## before the first sync. Guard it.
	if not bool(net_time.call("is_initial_sync_done")):
		return 0.0
	return float(net_time.get("clock_offset"))


func _peer_count() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 0
	return multiplayer.get_peers().size() + 1


func _write_meta() -> void:
	var meta := {
		"created": Time.get_datetime_string_from_system(),
		"context": _context,
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"model": OS.get_model_name(),
		"processor": OS.get_processor_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"physics_ticks_per_second": ProjectSettings.get_setting(
			"physics/common/physics_ticks_per_second", 60
		),
		"netfox": {
			"sync_to_physics": ProjectSettings.get_setting(
				"netfox/time/sync_to_physics", false
			),
			"tickrate": ProjectSettings.get_setting("netfox/time/tickrate", 30),
			"max_ticks_per_frame": ProjectSettings.get_setting(
				"netfox/time/max_ticks_per_frame", 8
			),
			"rollback_enabled": ProjectSettings.get_setting(
				"netfox/rollback/enabled", true
			),
			"enable_diff_states": ProjectSettings.get_setting(
				"netfox/rollback/enable_diff_states", true
			),
			"enable_input_broadcast": ProjectSettings.get_setting(
				"netfox/rollback/enable_input_broadcast", false
			),
		},
	}
	var file := FileAccess.open("%s/meta.json" % _session_dir, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(meta, "  "))
	file.close()


func _autoload(node_name: String) -> Node:
	return get_tree().root.get_node_or_null(node_name)


func _ensure_overlay() -> void:
	if _overlay != null:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 128
	add_child(_overlay)
	_overlay_label = Label.new()
	_overlay_label.position = Vector2(12.0, 10.0)
	_overlay_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_overlay_label.add_theme_font_size_override("font_size", 13)
	_overlay.add_child(_overlay_label)


func _update_overlay(tick: int, rb_depth: int, stretch: float) -> void:
	if _overlay_label == null:
		return
	_overlay_label.text = (
		"◉ NET DIAG  tick %d  rb %d (pk %d)  proc %.1fms  x%.2f"
		% [tick, rb_depth, _rb_depth_peak, _proc_ms_peak, stretch]
	)


func _clear_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
	_overlay = null
	_overlay_label = null
