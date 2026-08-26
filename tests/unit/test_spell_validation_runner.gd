class_name TestSpellValidationRunner
extends RefCounted

const SpellValidationRunnerScript := preload("res://scripts/spells/spell_validation_runner.gd")
const SpellCastValidatorScript := preload("res://scripts/spells/spell_cast_validator.gd")
const FireballSpell := preload("res://scenes/spells/fireball/fireball.tres")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_targeted_validation_completes_via_signal(tree)
	failures += _test_without_transcript_fails_via_signal(tree)
	return failures


func _loud_samples(duration_sec: float, sample_rate: int = 48000) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for _i in int(sample_rate * duration_sec):
		samples.append(0.04)
	return samples


func _make_runner(tree: SceneTree) -> SpellValidationRunner:
	var runner: SpellValidationRunner = SpellValidationRunnerScript.new()
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


func _test_targeted_validation_completes_via_signal(tree: SceneTree) -> int:
	var runner := _make_runner(tree)
	var samples := PackedFloat32Array()
	samples.resize(4800)
	for i in samples.size():
		samples[i] = sin(float(i) * 0.05) * 0.05

	if not runner.start(
		"targeted",
		samples,
		48000,
		FireballSpell,
		[],
		PackedStringArray(["fireball"]),
		PackedFloat32Array()
	):
		runner.queue_free()
		push_error("Expected validation runner to start")
		return 1
	if not runner.is_running():
		runner.queue_free()
		push_error("Expected validation runner to be pending after start")
		return 1

	var payload := _wait_for_runner(runner)
	runner.queue_free()

	if runner.is_running():
		push_error("Expected validation runner to finish after signal")
		return 1
	if not bool(payload.get("ok", false)):
		push_error("Expected successful validation payload, got: %s" % payload)
		return 1
	return 0


func _test_without_transcript_fails_via_signal(tree: SceneTree) -> int:
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
		runner.queue_free()
		push_error("Expected validation runner to start")
		return 1

	var payload := _wait_for_runner(runner)
	runner.queue_free()

	var parsed := SpellValidationCodec.parse_worker_response(payload)
	var result: CastValidationResult = parsed.get("result")
	if result == null or result.passed:
		push_error("Expected validation without transcript to fail")
		return 1
	if result.failure_reason != SpellCastValidatorScript.NO_TRANSCRIPT_REASON:
		push_error(
			"Expected speech recognition failure, got: %s"
			% result.failure_reason
		)
		return 1
	return 0
