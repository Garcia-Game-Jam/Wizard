class_name MicCaptureBroker
extends Node

## Sole owner of MicCapture drain. Fans mono PCM out to named subscribers
## ([code]chat[/code], [code]spellcasting[/code], …) so match voice chat + wand
## STT can share the mic without pause.
##
## FanoutPolicy:
## - CHAT_ONLY (lobby): single subscriber pipeline — chat only; spellcasting rejected
## - MATCH_FANOUT (match): chat + spellcasting may both receive the same PCM copies

signal log_message(event: String, detail: String)
signal subscriber_changed(subscriber_id: StringName, subscribed: bool, count: int)
signal fanout_policy_changed(policy: int)

enum FanoutPolicy { CHAT_ONLY, MATCH_FANOUT }

const LOG_PREFIX := "[friend-slop-mic-broker]"
const MIC_BUS_NAME := "MicCapture"
const MicGainUtilScript := preload("res://scripts/voice/mic_gain_util.gd")
const HEARTBEAT_MSEC := 2000
const DRAIN_CHUNK := 256
const SUB_CHAT := &"chat"
const SUB_SPELLCASTING := &"spellcasting"
const SUB_METER := &"meter"
## Peak below this is treated as digital silence (WASAPI zeros), not quiet speech.
const DIGITAL_SILENCE_PEAK := 0.00005
## Gap between closing and reopening the capture client on a device switch.
## Godot runs AudioStreamPlaybackMicrophone.stop() -> input_stop() on the audio
## thread, so a same-frame reopen can be undone by the outgoing stream and leave
## the new one playing but permanently silent.
const DEVICE_SWITCH_GAP_SEC := 0.25

@export var debug_logging: bool = false
@export var mic_bus_name: String = MIC_BUS_NAME
## Lobby = CHAT_ONLY; match gameplay = MATCH_FANOUT (set by GameVoiceSession).
@export var fanout_policy: FanoutPolicy = FanoutPolicy.CHAT_ONLY

## Test/telemetry: chunks delivered via inject_pcm or live drain fanout.
var debug_fanout_chunks: int = 0

## subscriber_id (StringName) -> Callable(mono: PackedFloat32Array, mix_rate: int)
var _subscribers: Dictionary = {}
var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _capturing: bool = false
var _last_rms: float = 0.0
var _last_peak_abs: float = 0.0
## Device the open AudioStreamMicrophone was created under.
var _bound_input_device: String = ""
## Latest Settings selection, even when no stream is open yet.
var _requested_input_device: String = ""
## True between closing the old stream and opening the replacement.
var _restart_pending: bool = false
var _debug_frames: int = 0
var _debug_samples: int = 0
var _debug_last_msec: int = 0
var _debug_fanout_log_msec: int = 0
var _silence_probe_msec: int = 0
var _silence_probe_done: bool = false
## When true, play drained PCM locally via AudioStreamGenerator (chat sidetone).
## Never route MicCapture→Master — bus send to Master loops hearback; capture uses empty send.
var _output_monitor: bool = false
var _hearback_player: AudioStreamPlayer
var _hearback_playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	add_to_group("mic_capture_broker")
	## Capture must survive the pause menu. A pausable broker stops draining
	## AudioEffectCapture *and* lets Godot set stream_paused on the child
	## AudioStreamPlayer, which wedges the WASAPI handle for the rest of the
	## session — the mic never recovers after the player resumes.
	process_mode = Node.PROCESS_MODE_ALWAYS
	## Adopt the authored Mic node once; from here the player is tracked by
	## reference so a closing stream can never be mistaken for the live one.
	_mic_player = get_node_or_null("Mic") as AudioStreamPlayer
	_output_monitor = SettingsManager.hear_myself
	_ensure_mic_bus()
	set_process(false)
	if not _subscribers.is_empty():
		_ensure_capturing()
	elif _output_monitor:
		## Saved Hear Myself preference needs the stream up before any subscriber.
		_ensure_mic_open()


func _enter_tree() -> void:
	if not _subscribers.is_empty():
		_ensure_capturing()


func set_fanout_policy(policy: FanoutPolicy) -> void:
	if fanout_policy == policy:
		return
	fanout_policy = policy
	_emit_log("fanout_policy", "policy=%s" % _policy_name(policy))
	fanout_policy_changed.emit(int(policy))
	if policy == FanoutPolicy.CHAT_ONLY and has_subscriber(SUB_SPELLCASTING):
		## Lobby must stay single-pipeline — drop wand spellcasting if still attached.
		unsubscribe(SUB_SPELLCASTING)


func is_spellcasting_fanout_allowed() -> bool:
	return fanout_policy == FanoutPolicy.MATCH_FANOUT


func subscribe(subscriber_id: StringName, on_pcm: Callable) -> bool:
	if subscriber_id == StringName():
		push_warning("MicCaptureBroker: refuse empty subscriber id")
		return false
	if not on_pcm.is_valid():
		push_warning("MicCaptureBroker: refuse invalid callback for '%s'" % subscriber_id)
		return false
	if subscriber_id == SUB_SPELLCASTING and not is_spellcasting_fanout_allowed():
		_emit_log("subscribe_rejected", "id=spellcasting reason=chat_only_policy")
		push_warning("MicCaptureBroker: spellcasting fan-out only allowed in MATCH_FANOUT policy")
		return false
	var replacing := _subscribers.has(subscriber_id)
	_subscribers[subscriber_id] = on_pcm
	_emit_log(
		"subscribe",
		"id=%s replacing=%s count=%d policy=%s"
		% [subscriber_id, replacing, _subscribers.size(), _policy_name(fanout_policy)]
	)
	subscriber_changed.emit(subscriber_id, true, _subscribers.size())
	_sync_authored_listeners(subscriber_id, true)
	_ensure_capturing()
	return true


func unsubscribe(subscriber_id: StringName) -> void:
	if not _subscribers.has(subscriber_id):
		return
	_subscribers.erase(subscriber_id)
	_emit_log("unsubscribe", "id=%s count=%d" % [subscriber_id, _subscribers.size()])
	subscriber_changed.emit(subscriber_id, false, _subscribers.size())
	_sync_authored_listeners(subscriber_id, false)
	if _subscribers.is_empty():
		_stop_capturing()


func has_subscriber(subscriber_id: StringName) -> bool:
	return _subscribers.has(subscriber_id)


func get_subscriber_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in _subscribers.keys():
		ids.append(key as StringName)
	return ids


func get_subscriber_count() -> int:
	return _subscribers.size()


func is_capturing() -> bool:
	return _capturing and _mic_player != null and _mic_player.playing


func get_last_rms() -> float:
	return _last_rms


func get_last_peak_abs() -> float:
	return _last_peak_abs


## Enable local mic hearback via PCM playback (not bus send — Master send
## zeroes capture on this Windows/Godot build).
func set_output_monitor(enabled: bool) -> void:
	var changed := _output_monitor != enabled
	_output_monitor = enabled
	_ensure_mic_bus()
	if enabled:
		## Sidetone reads drained PCM, so it needs a live stream even when no
		## subscriber (chat/spellcasting/meter) is asking for capture.
		_ensure_mic_open()
	else:
		_stop_hearback_player()
	if changed:
		_emit_log("output_monitor", "enabled=%s" % enabled)


## Create/configure MicCapture (unmuted, empty send — capture-safe).
func ensure_mic_bus_configured() -> void:
	_ensure_mic_bus()


## Ensure the shared mic player is live. Never tears down an open stream — device
## changes go through [method set_input_device_from_settings].
func ensure_mic_live() -> bool:
	_ensure_capturing()
	_ensure_mic_open()
	return is_capturing()


## Device name the open AudioStreamMicrophone was created under.
func get_bound_input_device() -> String:
	return _bound_input_device


## Settings is the only thing that picks a capture device. Reopens the stream
## when — and only when — the selection actually changed. Returns true if a
## restart was started.
func set_input_device_from_settings(device_name: String) -> bool:
	if device_name.is_empty() or device_name == _requested_input_device:
		return false
	_requested_input_device = device_name
	if not _is_mic_stream_open():
		## Nothing open yet — the next open uses this device.
		return false
	_restart_mic_stream()
	return true


## Settings calls this immediately before it reinitialises the audio driver.
## A live AudioStreamMicrophone holds a WASAPI capture handle that the reinit
## invalidates for good, so the stream closes now and reopens after the gap —
## on whichever device the driver ends up on.
func close_for_device_switch() -> void:
	if not _is_mic_stream_open():
		return
	_restart_mic_stream()


## Force a stream rotation. Debug tooling only; normal device changes come from
## [method set_input_device_from_settings].
func rebind_mic_stream() -> void:
	_restart_mic_stream()


func _is_mic_stream_open() -> bool:
	return (
		_mic_player != null
		and is_instance_valid(_mic_player)
		and _mic_player.playing
		and _mic_player.stream is AudioStreamMicrophone
	)


## Settings selection if known; otherwise whatever AudioServer reports.
## Never read back AudioServer to *verify* a selection: WASAPI applies
## set_input_device on the audio thread, so it lags by a frame or more.
func _active_device_name() -> String:
	if not _requested_input_device.is_empty():
		return _requested_input_device
	return AudioServer.get_input_device()


## Open the capture stream if it is not already up. Cheap to call repeatedly.
func _ensure_mic_open() -> void:
	if not is_inside_tree() or _restart_pending:
		return
	_ensure_mic_bus()
	_capture = _find_capture_effect()
	_ensure_capture_effect_enabled()
	if not _is_mic_stream_open():
		_open_mic_stream()
	set_process(true)


func _open_mic_stream() -> void:
	_discard_mic_player()
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "Mic"
	_mic_player.bus = mic_bus_name
	_mic_player.volume_db = 0.0
	_mic_player.stream = AudioStreamMicrophone.new()
	add_child(_mic_player)
	_mic_player.play()
	_bound_input_device = _active_device_name()
	if _capture != null:
		_capture.clear_buffer()
	_last_rms = 0.0
	_last_peak_abs = 0.0
	_silence_probe_msec = Time.get_ticks_msec()
	_silence_probe_done = false
	set_process(true)
	_emit_log(
		"mic_open",
		"device='%s' playing=%s" % [_bound_input_device, _mic_player.playing]
	)


## Close the capture client. queue_free (not free) lets the audio thread finish
## with the playback, and the rename frees the "Mic" name for the replacement.
func _discard_mic_player() -> void:
	if _mic_player == null or not is_instance_valid(_mic_player):
		_mic_player = null
		return
	var outgoing := _mic_player
	_mic_player = null
	outgoing.name = "MicClosing"
	if outgoing.playing:
		outgoing.stop()
	outgoing.queue_free()


## Close now, reopen after a gap. See DEVICE_SWITCH_GAP_SEC for why the two
## halves cannot share a frame.
func _restart_mic_stream() -> void:
	if not is_inside_tree() or _restart_pending:
		return
	_restart_pending = true
	var from_device := _bound_input_device
	_discard_mic_player()
	_emit_log(
		"mic_restart",
		"from='%s' to='%s' gap=%.2fs"
		% [from_device, _active_device_name(), DEVICE_SWITCH_GAP_SEC]
	)
	get_tree().create_timer(DEVICE_SWITCH_GAP_SEC).timeout.connect(
		_finish_mic_restart, CONNECT_ONE_SHOT
	)


func _finish_mic_restart() -> void:
	_restart_pending = false
	if not is_inside_tree():
		return
	_ensure_mic_open()


## Inject mono PCM as if drained from MicCapture. Used by unit tests (and debug tools).
func inject_pcm(mono: PackedFloat32Array, mix_rate: int = 0) -> void:
	if mono.is_empty():
		return
	var rate := mix_rate if mix_rate > 0 else int(AudioServer.get_mix_rate())
	var sum_sq := 0.0
	var peak_abs := 0.0
	for sample in mono:
		sum_sq += sample * sample
		peak_abs = maxf(peak_abs, absf(sample))
	_last_rms = sqrt(sum_sq / float(mono.size()))
	_last_peak_abs = peak_abs
	_fanout(mono, rate)
	debug_fanout_chunks += 1
	_debug_frames += 1
	_debug_samples += mono.size()


func _process(_delta: float) -> void:
	## Always drain while the mic player is live. Stopping the drain while
	## AudioStreamMicrophone keeps playing wedges WASAPI on Windows (bus peak
	## -200 forever) — confirmed by debug session 2c05d7 H3.
	if _restart_pending:
		return
	if _mic_player == null or not is_instance_valid(_mic_player) or not _mic_player.playing:
		return
	if _capture == null:
		_capture = _find_capture_effect()
		if _capture == null:
			return
	var mix_rate := int(AudioServer.get_mix_rate())
	var sum_sq := 0.0
	var sample_count := 0
	var peak_abs := 0.0
	var fanout_chunks := 0
	var do_fanout := _capturing and not _subscribers.is_empty()
	while _capture.can_get_buffer(DRAIN_CHUNK):
		var chunk: PackedVector2Array = _capture.get_buffer(DRAIN_CHUNK)
		if chunk.is_empty():
			break
		var mono := PackedFloat32Array()
		mono.resize(chunk.size())
		for i in chunk.size():
			var sample := (chunk[i].x + chunk[i].y) * 0.5
			mono[i] = sample
			sum_sq += sample * sample
			peak_abs = maxf(peak_abs, absf(sample))
			sample_count += 1
		## Sidetone from drained PCM — never MicCapture→Master bus send.
		if _output_monitor:
			_push_hearback(mono, mix_rate)
		if do_fanout:
			_fanout(mono, mix_rate)
			fanout_chunks += 1
	if sample_count > 0:
		_last_rms = sqrt(sum_sq / float(sample_count))
		_last_peak_abs = peak_abs
		_debug_frames += maxi(fanout_chunks, 1)
		_debug_samples += sample_count
		if do_fanout:
			_maybe_log_fanout(fanout_chunks, sample_count)
	if do_fanout:
		_maybe_silence_probe()
		_maybe_heartbeat()


func _fanout(mono: PackedFloat32Array, mix_rate: int) -> void:
	## Snapshot keys so a subscriber can unsubscribe mid-fanout safely.
	var ids: Array = _subscribers.keys()
	for key in ids:
		## CHAT_ONLY must never deliver to spellcasting even if a stale sub lingered.
		if key == SUB_SPELLCASTING and not is_spellcasting_fanout_allowed():
			continue
		var callback: Callable = _subscribers.get(key, Callable()) as Callable
		if not callback.is_valid():
			_emit_log("fanout_skip", "id=%s invalid_callback" % key)
			continue
		## Give each subscriber its own buffer so one consumer cannot mutate
		## PCM seen by another (chat + spellcasting share this fan-out).
		callback.call(mono.duplicate(), mix_rate)


## Push subscribe state onto authored Listeners under the *active* VoiceSession
## only — Lobby and Match both author Listeners/Chat in the tree.
func _sync_authored_listeners(subscriber_id: StringName, subscribed: bool) -> void:
	if not is_inside_tree():
		return
	var session := _active_voice_session()
	if session == null or not session.has_method("get_authored_listeners"):
		return
	var authored_list: Array = session.call("get_authored_listeners")
	for authored in authored_list:
		if authored == null or not authored.has_method("get_subscriber_id"):
			continue
		if authored.call("get_subscriber_id") != subscriber_id:
			continue
		if authored.has_method("set_listening_state"):
			authored.call("set_listening_state", subscribed)
		if subscribed and authored.has_method("reset_stats"):
			authored.call("reset_stats")


func _active_voice_session() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var app := tree.get_first_node_in_group("game_app")
	if app != null and app.has_method("get_active_voice_session"):
		return app.call("get_active_voice_session") as Node
	return null


func _policy_name(policy: FanoutPolicy) -> String:
	match policy:
		FanoutPolicy.CHAT_ONLY:
			return "chat_only"
		FanoutPolicy.MATCH_FANOUT:
			return "match_fanout"
		_:
			return "unknown"


func _ensure_capturing() -> void:
	if _subscribers.is_empty():
		return
	var becoming_active := not _capturing
	if becoming_active:
		_capturing = true
		_debug_frames = 0
		_debug_samples = 0
		_debug_last_msec = Time.get_ticks_msec()
		_silence_probe_msec = Time.get_ticks_msec()
		_silence_probe_done = false
	_ensure_mic_open()
	if becoming_active:
		_emit_log(
			"capture_started",
			"device=%s mix_rate=%d subscribers=%s playing=%s"
			% [
				AudioServer.get_input_device(),
				int(AudioServer.get_mix_rate()),
				str(get_subscriber_ids()),
				_mic_player != null and _mic_player.playing,
			]
		)


func _stop_capturing() -> void:
	if not _capturing:
		return
	_capturing = false
	## Keep _process draining+discarding. Pausing the drain while the mic player
	## stays up is what killed capture after Settings (debug H3).
	if is_inside_tree():
		set_process(true)
	## Do not clear_buffer here — that raced with a live stream and is unnecessary
	## when keepalive drain is active.
	_emit_log(
		"capture_idle",
		"subscribers=0 keepalive_drain=%s peak=%.4f"
		% [
			str(_mic_player != null and _mic_player.playing),
			_last_peak_abs,
		]
	)


func _ensure_mic_bus() -> void:
	var bus_idx := AudioServer.get_bus_index(mic_bus_name)
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_idx, mic_bus_name)
		AudioServer.add_bus_effect(bus_idx, AudioEffectCapture.new())
	_configure_mic_bus(bus_idx)
	## Orphan MicHearback from earlier builds — mute so it cannot loop audio.
	var orphan := AudioServer.get_bus_index("MicHearback")
	if orphan >= 0:
		AudioServer.set_bus_mute(orphan, true)
		AudioServer.set_bus_send(orphan, &"")


## MicCapture stays muted so the live mic never reaches speakers. Capture effect
## samples before mute (Godot). Hear Myself uses AudioStreamGenerator on Master.
func _configure_mic_bus(bus_idx: int) -> void:
	AudioServer.set_bus_mute(bus_idx, true)
	AudioServer.set_bus_volume_db(bus_idx, 0.0)
	AudioServer.set_bus_send(bus_idx, &"")
	if _find_capture_effect() == null:
		AudioServer.add_bus_effect(bus_idx, AudioEffectCapture.new())


func _push_hearback(mono: PackedFloat32Array, mix_rate: int) -> void:
	if mono.is_empty():
		return
	_ensure_hearback_player(mix_rate)
	if _hearback_playback == null or _hearback_player == null:
		return
	## Drive loudness with player volume so boost uses mixer gain (audible in
	## mic test). Leave PCM near full-scale; baking 5× into samples just clips.
	var gain: float = MicGainUtilScript.from_settings()
	_hearback_player.volume_db = linear_to_db(maxf(gain, 0.0001))
	var frames := PackedVector2Array()
	frames.resize(mono.size())
	for i in mono.size():
		var sample := mono[i]
		frames[i] = Vector2(sample, sample)
	var available := _hearback_playback.get_frames_available()
	if available <= 0:
		return
	if frames.size() > available:
		_hearback_playback.push_buffer(frames.slice(0, available))
	else:
		_hearback_playback.push_buffer(frames)


func _ensure_hearback_player(mix_rate: int) -> void:
	var rate := float(mix_rate if mix_rate > 0 else int(AudioServer.get_mix_rate()))
	if _hearback_player != null and is_instance_valid(_hearback_player):
		var current := _hearback_player.stream as AudioStreamGenerator
		if current != null and is_equal_approx(current.mix_rate, rate):
			if not _hearback_player.playing:
				_hearback_player.play()
				_hearback_playback = (
					_hearback_player.get_stream_playback() as AudioStreamGeneratorPlayback
				)
			return
		## An output device switch moved the mix rate. A generator left on the old
		## rate replays sidetone pitch-shifted, so rebuild it at the new rate.
		_discard_hearback_player()
	_hearback_player = AudioStreamPlayer.new()
	_hearback_player.name = "Hearback"
	_hearback_player.bus = &"Master"
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = rate
	stream.buffer_length = 0.25
	_hearback_player.stream = stream
	add_child(_hearback_player)
	_hearback_player.play()
	_hearback_playback = _hearback_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _stop_hearback_player() -> void:
	_hearback_playback = null
	if _hearback_player == null or not is_instance_valid(_hearback_player):
		_hearback_player = null
		return
	if _hearback_player.playing:
		_hearback_player.stop()


## Free it outright, so the replacement can reuse the "Hearback" name.
func _discard_hearback_player() -> void:
	_hearback_playback = null
	if _hearback_player == null or not is_instance_valid(_hearback_player):
		_hearback_player = null
		return
	var outgoing := _hearback_player
	_hearback_player = null
	outgoing.name = "HearbackClosing"
	if outgoing.playing:
		outgoing.stop()
	outgoing.queue_free()


## Stage-by-stage capture diagnosis. Prints once when live capture stays silent.
func diagnose_capture() -> String:
	var bus_idx := AudioServer.get_bus_index(mic_bus_name)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("--- mic capture diagnose ---")
	lines.append(
		"input_device='%s' enable_input=%s mix_rate=%d"
		% [
			AudioServer.get_input_device(),
			str(ProjectSettings.get_setting("audio/driver/enable_input", false)),
			int(AudioServer.get_mix_rate()),
		]
	)
	lines.append("devices=%s" % str(AudioServer.get_input_device_list()))
	if bus_idx < 0:
		lines.append("bus='%s' MISSING" % mic_bus_name)
	else:
		var peak_l := AudioServer.get_bus_peak_volume_left_db(bus_idx, 0)
		var peak_r := AudioServer.get_bus_peak_volume_right_db(bus_idx, 0)
		lines.append(
			(
				"bus='%s' idx=%d mute=%s vol_db=%.1f send='%s' "
				+ "peak_l_db=%.1f peak_r_db=%.1f effects=%d"
			)
			% [
				mic_bus_name,
				bus_idx,
				AudioServer.is_bus_mute(bus_idx),
				AudioServer.get_bus_volume_db(bus_idx),
				AudioServer.get_bus_send(bus_idx),
				peak_l,
				peak_r,
				AudioServer.get_bus_effect_count(bus_idx),
			]
		)
		for i in AudioServer.get_bus_effect_count(bus_idx):
			var effect := AudioServer.get_bus_effect(bus_idx, i)
			lines.append(
				"  effect[%d]=%s enabled=%s"
				% [
					i,
					effect.get_class() if effect != null else "null",
					AudioServer.is_bus_effect_enabled(bus_idx, i),
				]
			)
	if _mic_player == null:
		lines.append("mic_player=MISSING")
	else:
		lines.append(
			(
				"mic_player playing=%s paused=%s bus='%s' vol_db=%.1f "
				+ "stream=%s in_tree=%s"
			)
			% [
				_mic_player.playing,
				_mic_player.stream_paused,
				_mic_player.bus,
				_mic_player.volume_db,
				(
					_mic_player.stream.get_class()
					if _mic_player.stream != null
					else "null"
				),
				_mic_player.is_inside_tree(),
			]
		)
	var frames_avail := 0
	if _capture != null:
		frames_avail = _capture.get_frames_available()
	lines.append(
		(
			"capture_effect=%s frames_available=%d last_rms=%.4f "
			+ "last_peak_abs=%.4f drained_samples=%d verdict=%s"
		)
		% [
			_capture != null,
			frames_avail,
			_last_rms,
			_last_peak_abs,
			_debug_samples,
			_silence_verdict(bus_idx),
		]
	)
	var report := "\n".join(lines)
	print("%s\n%s" % [LOG_PREFIX, report])
	_emit_log("diagnose", _silence_verdict(bus_idx))
	return report


func _silence_verdict(bus_idx: int) -> String:
	var verdict := "UNKNOWN_SILENCE"
	if _mic_player == null or not _mic_player.playing:
		verdict = "PLAYER_NOT_PLAYING"
	elif bus_idx < 0:
		verdict = "BUS_MISSING"
	elif _capture == null:
		verdict = "CAPTURE_EFFECT_MISSING"
	elif _last_peak_abs > DIGITAL_SILENCE_PEAK:
		verdict = "OK_HAS_SIGNAL"
	else:
		## Bus peak is post-mute (always muted); trust drained PCM instead.
		verdict = "MIC_OR_ROUTE_SILENT"
	return verdict


## Report-only: print one diagnosis if capture stays silent after starting.
## Deliberately does not "recover" — every automatic teardown we tried here made
## a working stream worse, and a quiet room looks identical to a dead mic.
func _maybe_silence_probe() -> void:
	if _silence_probe_done or not _capturing:
		return
	if _last_peak_abs > DIGITAL_SILENCE_PEAK:
		_silence_probe_done = true
		return
	if Time.get_ticks_msec() - _silence_probe_msec < 750:
		return
	_silence_probe_done = true
	diagnose_capture()


func _find_capture_effect() -> AudioEffectCapture:
	var bus_idx := AudioServer.get_bus_index(mic_bus_name)
	if bus_idx < 0:
		return null
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var effect := AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectCapture:
			return effect as AudioEffectCapture
	return null


func _ensure_capture_effect_enabled() -> void:
	var bus_idx := AudioServer.get_bus_index(mic_bus_name)
	if bus_idx < 0 or _capture == null:
		return
	for i in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, i) == _capture:
			if not AudioServer.is_bus_effect_enabled(bus_idx, i):
				AudioServer.set_bus_effect_enabled(bus_idx, i, true)
				_emit_log("capture_enabled", "bus=%s effect=%d" % [mic_bus_name, i])
			return


func _maybe_log_fanout(chunks: int, samples: int) -> void:
	if not debug_logging:
		return
	var now := Time.get_ticks_msec()
	if now - _debug_fanout_log_msec < 250:
		return
	_debug_fanout_log_msec = now
	_emit_log(
		"fanout",
		"chunks=%d samples=%d rms=%.4f peak=%.4f subs=%s"
		% [chunks, samples, _last_rms, _last_peak_abs, str(get_subscriber_ids())]
	)


func _maybe_heartbeat() -> void:
	if not debug_logging:
		return
	var now := Time.get_ticks_msec()
	if now - _debug_last_msec < HEARTBEAT_MSEC:
		return
	_debug_last_msec = now
	_emit_log(
		"heartbeat",
		(
			"frames=%d samples=%d rms=%.4f peak=%.4f subs=%s device=%s recording=%s"
			% [
				_debug_frames,
				_debug_samples,
				_last_rms,
				_last_peak_abs,
				str(get_subscriber_ids()),
				AudioServer.get_input_device(),
				is_capturing(),
			]
		)
	)
	_debug_frames = 0
	_debug_samples = 0


func _emit_log(event: String, detail: String) -> void:
	log_message.emit(event, detail)
	var always := (
		event == "capture_started"
		or event == "capture_stopped"
		or event == "capture_idle"
		or event == "subscribe"
		or event == "unsubscribe"
		or event == "subscribe_rejected"
		or event == "fanout_policy"
		or event == "mic_open"
		or event == "mic_restart"
		or event == "diagnose"
		or event == "output_monitor"
	)
	if not debug_logging and not always:
		return
	if detail.is_empty():
		print("%s %s" % [LOG_PREFIX, event])
	else:
		print("%s %s %s" % [LOG_PREFIX, event, detail])
