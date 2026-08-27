extends Node

## Netcode / CPU diagnostics capture. Autoload.
##
## Slice 1: per-frame budget + rollback-depth + clock-health stream, written to
## user://diag/<stamp>_<role>_<pid>/frame.csv with a self-describing meta.json.
##
## Backend-neutral: everything netcode-specific is read through NetProbe, so a
## future backend swap (Photon, custom ENet) is one NetProbe subclass, not a
## NetDiag rewrite. The CSV schema is fixed so tools/analyze_netdiag.py and any
## saved baselines keep comparing like for like.
##
## Toggle with the "Netcode diagnostics capture" Developer setting, or force on
## for headless runs with WIZARD_NET_DIAG=1. Per-pawn correction data (predicted
## vs authoritative) lands in a later slice.

const ENV_FORCE_KEY := "WIZARD_NET_DIAG"
const SESSION_ROOT := "user://diag"
const FLUSH_EVERY := 240
const FRAME_HEADER := (
	"t_ms,frame,net_tick,tickloop_us,rb_depth,proc_ms,phys_ms,fps,"
	+ "clock_stretch,clock_offset,rtt,node_count,coll_pairs,active_objs,peers"
)

var _armed := false
var _capturing := false
var _session_dir := ""
var _frame_file: FileAccess = null
var _frame_rows: PackedStringArray = []
var _context: Dictionary = {}
var _probe: NetProbe = null

var _last_tickloop_us := 0
var _overlay: CanvasLayer = null
var _overlay_label: Label = null
var _proc_ms_peak := 0.0
var _rb_depth_peak := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_probe = NetProbe.create(get_tree())
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
	if _probe == null:
		_probe = NetProbe.create(get_tree())
	_context = context.duplicate(true)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	## PID keeps two instances on one machine (LAN test) in separate folders even
	## when both matches start in the same second.
	var role := str(_context.get("role", "p"))
	_session_dir = "%s/%s_%s_%d" % [SESSION_ROOT, stamp, role, OS.get_process_id()]
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
	_capturing = true
	_proc_ms_peak = 0.0
	_rb_depth_peak = 0
	_ensure_overlay()
	set_process(true)
	print("[NetDiag] capturing (%s) -> %s" % [_probe.backend_id(), _session_dir])


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
	var tick := _probe.current_tick()
	var clock := _probe.clock_health()
	var rb_depth := _probe.rollback_depth()
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var loop: Dictionary = _probe.pop_tick_loop()
	_last_tickloop_us = int(loop.get("us", 0))

	var row := "%d,%d,%d,%d,%d,%.3f,%.3f,%.1f,%.4f,%.4f,%.4f,%d,%d,%d,%d" % [
		Time.get_ticks_msec(),
		Engine.get_process_frames(),
		tick,
		_last_tickloop_us,
		rb_depth,
		proc_ms,
		phys_ms,
		Performance.get_monitor(Performance.TIME_FPS),
		float(clock.get("stretch", 1.0)),
		float(clock.get("offset", 0.0)),
		float(clock.get("rtt", 0.0)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		_probe.peer_count(),
	]
	_frame_rows.append(row)
	if _frame_rows.size() >= FLUSH_EVERY:
		_flush_frames()

	_proc_ms_peak = maxf(_proc_ms_peak * 0.97, proc_ms)
	_rb_depth_peak = maxi(int(_rb_depth_peak * 0.9), rb_depth)
	_update_overlay(tick, rb_depth, float(clock.get("stretch", 1.0)))


func _flush_frames() -> void:
	if _frame_file == null or _frame_rows.is_empty():
		return
	for line in _frame_rows:
		_frame_file.store_line(line)
	_frame_file.flush()
	_frame_rows.clear()


func _write_meta() -> void:
	var meta := {
		"created": Time.get_datetime_string_from_system(),
		"context": _context,
		"backend": _probe.backend_id(),
		"backend_config": _probe.config_snapshot(),
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"model": OS.get_model_name(),
		"processor": OS.get_processor_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
	}
	var file := FileAccess.open("%s/meta.json" % _session_dir, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(meta, "  "))
	file.close()


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
		"◉ NET DIAG [%s]  tick %d  rb %d (pk %d)  proc %.1fms  x%.2f"
		% [_probe.backend_id(), tick, rb_depth, _rb_depth_peak, _proc_ms_peak, stretch]
	)


func _clear_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
	_overlay = null
	_overlay_label = null
