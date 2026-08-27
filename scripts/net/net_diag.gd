extends Node

## Netcode / CPU diagnostics capture. Autoload.
##
## Per match, writes user://diag/<stamp>_<role>_<pid>/:
##   frame.csv  - one row per rendered frame (real frame time, rollback depth,
##                tick-loop cost, clock health, physics-step count)
##   events.csv - named markers (clock_start, encounter_begin, dump_spawn, ...) so spikes are
##                attributable instead of guessed from net_tick
##   pawn.csv   - per fresh tick per pawn: position, vy, is_on_floor (the
##                floor-state check that hypothesis 1 hinges on)
##   render.csv - per render frame, the interpolated (on-screen) pose of each
##                player pawn. Sub-tick stutter/freeze/warp lives here only.
##   meta.json  - self-describing header (backend + config + machine)
##
## Backend-neutral: all netcode reads go through NetProbe. Toggle with the
## "Netcode diagnostics capture" Developer setting or WIZARD_NET_DIAG=1.

const ENV_FORCE_KEY := "WIZARD_NET_DIAG"
const SESSION_ROOT := "user://diag"
const FLUSH_EVERY := 240
const FRAME_HEADER := (
	"t_ms,frame,net_tick,frame_ms,tickloop_us,rb_depth,phys_steps,"
	+ "proc_ms_smooth,phys_ms_smooth,fps,tick_factor,tick_factor_delta,"
	+ "clock_stretch,clock_offset,rtt,node_count,island_count,active_objs,peers"
)
const EVENT_HEADER := "t_ms,frame,net_tick,event,detail"
const PAWN_HEADER := "t_ms,net_tick,pawn,owner,px,py,pz,vy,on_floor,speed"
## Per render frame, the displayed (interpolated) pose of each player pawn. This
## is what the player's eye tracks; sub-tick stutter/freeze/warp lives here and
## nowhere else. pawn.csv is per tick and cannot show it.
const RENDER_HEADER := "t_ms,frame,net_tick,pawn,px,py,pz"

var _armed := false
var _capturing := false
var _session_dir := ""
var _frame_file: FileAccess = null
var _event_file: FileAccess = null
var _pawn_file: FileAccess = null
var _render_file: FileAccess = null
var _frame_rows: PackedStringArray = []
var _pawn_rows: PackedStringArray = []
var _render_rows: PackedStringArray = []
var _context: Dictionary = {}
var _probe: NetProbe = null

var _phys_steps := 0
var _last_tickloop_us := 0
var _prev_tick_factor := 0.0
var _overlay: CanvasLayer = null
var _overlay_label: Label = null
var _frame_ms_peak := 0.0
var _rb_depth_peak := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_probe = NetProbe.create(get_tree())
	if OS.get_environment(ENV_FORCE_KEY) == "1":
		set_enabled(true)


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
	## PID keeps two instances on one machine (LAN test) in separate folders.
	var role := str(_context.get("role", "p"))
	_session_dir = "%s/%s_%s_%d" % [SESSION_ROOT, stamp, role, OS.get_process_id()]
	if DirAccess.make_dir_recursive_absolute(_session_dir) != OK:
		push_warning("NetDiag: could not create %s" % _session_dir)
		return
	_frame_file = _open_csv("frame.csv", FRAME_HEADER)
	_event_file = _open_csv("events.csv", EVENT_HEADER)
	_pawn_file = _open_csv("pawn.csv", PAWN_HEADER)
	_render_file = _open_csv("render.csv", RENDER_HEADER)
	if _frame_file == null:
		return
	_frame_rows.clear()
	_pawn_rows.clear()
	_render_rows.clear()
	_write_meta()
	_capturing = true
	_frame_ms_peak = 0.0
	_rb_depth_peak = 0
	_ensure_overlay()
	set_process(true)
	set_physics_process(true)
	print("[NetDiag] capturing (%s) -> %s" % [_probe.backend_id(), _session_dir])
	mark("session_begin", role)


func end_session() -> void:
	if not _capturing:
		return
	mark("session_end")
	_capturing = false
	set_process(false)
	set_physics_process(false)
	_flush()
	for file in [_frame_file, _event_file, _pawn_file, _render_file]:
		if file != null:
			file.close()
	_frame_file = null
	_event_file = null
	_pawn_file = null
	_render_file = null
	_clear_overlay()
	print("[NetDiag] capture closed -> %s" % _session_dir)
	_session_dir = ""


## Timeline marker. Cheap no-op when not capturing — safe to call from anywhere.
func mark(event: String, detail: String = "") -> void:
	if not _capturing or _event_file == null:
		return
	_event_file.store_line("%d,%d,%d,%s,%s" % [
		Time.get_ticks_msec(), Engine.get_process_frames(),
		_probe.current_tick(), event, detail,
	])
	_event_file.flush()


## One row per fresh sim tick per pawn. Call from the pawn's tick with
## is_fresh == true. Cheap no-op when not capturing.
func pawn_sample(pawn: Node3D, is_owner: bool) -> void:
	if not _capturing or pawn == null:
		return
	var vel: Vector3 = pawn.get("velocity") if "velocity" in pawn else Vector3.ZERO
	var on_floor := false
	if pawn.has_method("is_on_floor"):
		on_floor = bool(pawn.call("is_on_floor"))
	var pos := pawn.global_position
	_pawn_rows.append("%d,%d,%s,%d,%.3f,%.3f,%.3f,%.3f,%d,%.3f" % [
		Time.get_ticks_msec(), _probe.current_tick(), pawn.name, int(is_owner),
		pos.x, pos.y, pos.z, vel.y, int(on_floor),
		Vector2(vel.x, vel.z).length(),
	])
	if _pawn_rows.size() >= FLUSH_EVERY:
		_flush()


func _physics_process(_delta: float) -> void:
	_phys_steps += 1


func _process(delta: float) -> void:
	if not _capturing:
		return
	var tick := _probe.current_tick()
	var clock := _probe.clock_health()
	var rb_depth := _probe.rollback_depth()
	var frame_ms := delta * 1000.0
	var loop: Dictionary = _probe.pop_tick_loop()
	_last_tickloop_us = int(loop.get("us", 0))

	## tick_factor sweeps 0->1 between ticks then resets. Logged raw; the analyzer
	## separates a legitimate reset from a mid-rise regression (small backward
	## step) -- render.csv is the real smoothness signal.
	var tick_factor := float(clock.get("tick_factor", 0.0))
	var tf_delta := tick_factor - _prev_tick_factor
	_prev_tick_factor = tick_factor

	_frame_rows.append(
		"%d,%d,%d,%.3f,%d,%d,%d,%.3f,%.3f,%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%d,%d,%d" % [
		Time.get_ticks_msec(),
		Engine.get_process_frames(),
		tick,
		frame_ms,
		_last_tickloop_us,
		rb_depth,
		_phys_steps,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_FPS),
		tick_factor,
		tf_delta,
		float(clock.get("stretch", 1.0)),
		float(clock.get("offset", 0.0)),
		float(clock.get("rtt", 0.0)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		_probe.peer_count(),
	])
	_phys_steps = 0
	_sample_render(tick)
	if _frame_rows.size() >= FLUSH_EVERY or _render_rows.size() >= FLUSH_EVERY * 4:
		_flush()

	_frame_ms_peak = maxf(_frame_ms_peak * 0.95, frame_ms)
	_rb_depth_peak = maxi(int(_rb_depth_peak * 0.9), rb_depth)
	_update_overlay(tick, rb_depth, float(clock.get("stretch", 1.0)))


## The displayed pose of each player pawn this render frame. TickInterpolator
## has already written its interpolated value onto the node by the time _process
## runs, so global_position here is exactly what is on screen.
func _sample_render(tick: int) -> void:
	if _render_file == null:
		return
	var t_ms := Time.get_ticks_msec()
	var frame := Engine.get_process_frames()
	for node in get_tree().get_nodes_in_group("player"):
		if not (node is Node3D):
			continue
		var pos := (node as Node3D).global_position
		_render_rows.append("%d,%d,%d,%s,%.4f,%.4f,%.4f" % [
			t_ms, frame, tick, node.name, pos.x, pos.y, pos.z,
		])


func _flush() -> void:
	if _frame_file != null and not _frame_rows.is_empty():
		for line in _frame_rows:
			_frame_file.store_line(line)
		_frame_file.flush()
		_frame_rows.clear()
	if _pawn_file != null and not _pawn_rows.is_empty():
		for line in _pawn_rows:
			_pawn_file.store_line(line)
		_pawn_file.flush()
		_pawn_rows.clear()
	if _render_file != null and not _render_rows.is_empty():
		for line in _render_rows:
			_render_file.store_line(line)
		_render_file.flush()
		_render_rows.clear()


func _open_csv(basename: String, header: String) -> FileAccess:
	var file := FileAccess.open("%s/%s" % [_session_dir, basename], FileAccess.WRITE)
	if file == null:
		push_warning("NetDiag: could not open %s" % basename)
		return null
	file.store_line(header)
	return file


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
		"◉ NET DIAG [%s]  tick %d  rb %d (pk %d)  frame pk %.0fms  x%.2f"
		% [_probe.backend_id(), tick, rb_depth, _rb_depth_peak, _frame_ms_peak, stretch]
	)


func _clear_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
	_overlay = null
	_overlay_label = null
