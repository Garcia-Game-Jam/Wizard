class_name TestSpellValidationAsync
extends RefCounted

## Guards against regressions that move STT/validation back onto the main thread.

const RunnerScript := preload("res://scripts/spells/spell_validation_runner.gd")
const WorkerScript := preload("res://scripts/spells/spell_validation_worker.gd")
const SpellLogScript := preload("res://scripts/spells/spell_log.gd")
const FireballSpell := preload("res://scenes/spells/fireball/fireball.tres")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_worker_runs_off_main_thread(tree)
	failures += _test_runner_start_is_non_blocking(tree)
	failures += _test_fireball_validation_completes_on_worker(tree)
	failures += _test_worker_stt_logging_avoids_scene_tree(tree)
	return failures


func _loud_samples(duration_sec: float, sample_rate: int = 48000) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for _i in int(sample_rate * duration_sec):
		samples.append(0.04)
	return samples


func _make_runner(tree: SceneTree) -> SpellValidationRunner:
	var runner: SpellValidationRunner = RunnerScript.new()
	tree.root.add_child(runner)
	return runner


func _wait_for_runner(runner: SpellValidationRunner, max_attempts: int = 300) -> Dictionary:
	var payload := {}
	var received := false
	runner.validation_finished.connect(
		func(result: Dictionary) -> void:
			payload = result
			received = true,
		CONNECT_ONE_SHOT
	)
	var attempts := 0
	while not received and attempts < max_attempts:
		runner._process(0.0)
		if not runner.is_running() and runner.is_finished():
			if payload.is_empty():
				payload = runner.get_payload()
			break
		OS.delay_msec(1)
		attempts += 1
	return payload


func _test_worker_runs_off_main_thread(tree: SceneTree) -> int:
	WorkerScript.test_delay_sec = 0.01
	var runner := _make_runner(tree)
	if not runner.start(
		"targeted",
		_loud_samples(0.2),
		48000,
		FireballSpell,
		[],
		PackedStringArray(["fireball"]),
		PackedFloat32Array()
	):
		WorkerScript.test_delay_sec = 0.0
		runner.queue_free()
		push_error("Expected async runner to start")
		return 1
	_wait_for_runner(runner)
	WorkerScript.test_delay_sec = 0.0
	runner.queue_free()
	if WorkerScript.last_ran_on_main_thread:
		push_error("Expected spell validation worker to run off the main thread")
		return 1
	return 0


func _test_runner_start_is_non_blocking(tree: SceneTree) -> int:
	WorkerScript.test_delay_sec = 0.05
	var runner := _make_runner(tree)
	if not runner.start(
		"targeted",
		_loud_samples(0.3),
		48000,
		FireballSpell,
		[],
		PackedStringArray(["fireball"]),
		PackedFloat32Array()
	):
		WorkerScript.test_delay_sec = 0.0
		runner.queue_free()
		push_error("Expected runner.start to succeed")
		return 1
	if not runner.is_running():
		WorkerScript.test_delay_sec = 0.0
		runner.queue_free()
		push_error("Expected runner to remain pending immediately after start()")
		return 1
	if runner.is_finished():
		WorkerScript.test_delay_sec = 0.0
		runner.queue_free()
		push_error("Expected runner not to finish synchronously in start()")
		return 1
	_wait_for_runner(runner)
	WorkerScript.test_delay_sec = 0.0
	runner.queue_free()
	return 0


func _test_fireball_validation_completes_on_worker(tree: SceneTree) -> int:
	WorkerScript.test_delay_sec = 0.0
	var runner := _make_runner(tree)
	if not runner.start(
		"targeted",
		_loud_samples(0.4),
		48000,
		FireballSpell,
		[],
		PackedStringArray(["fireball"]),
		PackedFloat32Array()
	):
		runner.queue_free()
		push_error("Expected fireball validation runner to start")
		return 1
	var payload := _wait_for_runner(runner)
	runner.queue_free()
	if not bool(payload.get("ok", false)):
		push_error("Expected fireball validation payload to succeed, got: %s" % payload)
		return 1
	if str(payload.get("spell_id", "")) != "fireball":
		push_error("Expected spell_id fireball in async payload")
		return 1
	var parsed := SpellValidationCodec.parse_worker_response(payload)
	var result: CastValidationResult = parsed.get("result")
	if result == null or not result.passed or result.heard_text != "fireball":
		push_error("Expected async fireball cast validation to pass with heard text")
		return 1
	return 0


func _test_worker_stt_logging_avoids_scene_tree(tree: SceneTree) -> int:
	## Validation with no transcript runs the STT path + SpellLog on the worker.
	## Skip Kaldi: constructing VoskModel in --script then quit() crashes gdvosk.
	SpellLogScript.last_used_scene_tree = false
	WorkerScript.test_delay_sec = 0.0
	GdvoskAdapter.skip_native_engine = true
	WorkerScript.force_stt_in_tests = true
	var runner := _make_runner(tree)
	if not runner.start(
		"targeted",
		_loud_samples(0.5),
		48000,
		FireballSpell,
		[],
		PackedStringArray(),
		PackedFloat32Array()
	):
		GdvoskAdapter.skip_native_engine = false
		WorkerScript.force_stt_in_tests = false
		runner.queue_free()
		push_error("Expected STT logging runner to start")
		return 1
	_wait_for_runner(runner, 5000)
	GdvoskAdapter.skip_native_engine = false
	WorkerScript.force_stt_in_tests = false
	runner.queue_free()
	if WorkerScript.last_ran_on_main_thread:
		push_error("Expected STT logging worker to run off the main thread")
		return 1
	if SpellLogScript.last_used_scene_tree:
		push_error("SpellLog must not access the scene tree during worker STT validation")
		return 1
	return 0
