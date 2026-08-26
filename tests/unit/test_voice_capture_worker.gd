extends RefCounted

const VoiceCaptureWorkerScript := preload("res://scripts/spells/voice_capture_worker.gd")


func run() -> int:
	var failures := 0
	failures += _test_accumulates_on_worker_thread()
	return failures


func _test_accumulates_on_worker_thread() -> int:
	var worker := VoiceCaptureWorkerScript.new()
	worker.start()

	var chunk := PackedFloat32Array()
	for _i in 512:
		chunk.append(0.05)
	worker.push_chunk(chunk)

	for _attempt in 100:
		if worker.take_samples().size() >= 512:
			break
		OS.delay_msec(1)

	var samples := worker.take_samples()
	worker.stop()

	if samples.size() < 512:
		push_error("Expected worker to accumulate pushed samples, got %d" % samples.size())
		return 1
	if worker.get_listen_level() <= 0.0:
		push_error("Expected worker to compute listen level")
		return 1
	return 0
