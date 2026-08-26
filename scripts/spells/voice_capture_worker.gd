class_name VoiceCaptureWorker
extends RefCounted

## Accumulates mic samples and RMS level on a background thread.
## Main thread only pushes mono chunks from AudioEffectCapture.

const LISTEN_LEVEL_TAIL_SAMPLES := 2048
const THREAD_SLEEP_USEC := 4000

var _mutex := Mutex.new()
var _thread: Thread
var _stop_requested := false
var _pending_chunks: Array[PackedFloat32Array] = []
var _recorded_samples := PackedFloat32Array()
var _listen_level := 0.0


func is_running() -> bool:
	return _thread != null


func start() -> void:
	stop()
	reset()
	_stop_requested = false
	_thread = Thread.new()
	if _thread.start(_worker_loop) != OK:
		_thread = null


func stop() -> void:
	_stop_requested = true
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func reset() -> void:
	_mutex.lock()
	_pending_chunks.clear()
	_recorded_samples = PackedFloat32Array()
	_listen_level = 0.0
	_mutex.unlock()


func push_chunk(mono: PackedFloat32Array) -> void:
	if mono.is_empty() or _thread == null:
		return
	_mutex.lock()
	_pending_chunks.append(mono.duplicate())
	_mutex.unlock()


func get_listen_level() -> float:
	_mutex.lock()
	var level := _listen_level
	_mutex.unlock()
	return level


func take_samples() -> PackedFloat32Array:
	_mutex.lock()
	var samples := _recorded_samples.duplicate()
	_mutex.unlock()
	return samples


func _worker_loop() -> void:
	while true:
		_mutex.lock()
		var should_stop := _stop_requested
		## Copy into an untyped Array — typed Array.duplicate() is unsafe off-thread.
		var chunks: Array = []
		for chunk in _pending_chunks:
			chunks.append(chunk)
		_pending_chunks.clear()
		_mutex.unlock()
		## Always flush pending audio before honoring stop, or the last listen
		## chunks are discarded and STT sees silence / truncated speech.
		for chunk_variant in chunks:
			if chunk_variant is PackedFloat32Array:
				_append_chunk(chunk_variant)
		if should_stop:
			break
		if chunks.is_empty():
			OS.delay_usec(THREAD_SLEEP_USEC)


func _append_chunk(mono: PackedFloat32Array) -> void:
	_mutex.lock()
	for i in mono.size():
		_recorded_samples.append(mono[i])
	var tail_start := maxi(0, _recorded_samples.size() - LISTEN_LEVEL_TAIL_SAMPLES)
	var sum_sq := 0.0
	for i in range(tail_start, _recorded_samples.size()):
		var sample := _recorded_samples[i]
		sum_sq += sample * sample
	var count := _recorded_samples.size() - tail_start
	if count > 0:
		_listen_level = sqrt(sum_sq / float(count))
	_mutex.unlock()
