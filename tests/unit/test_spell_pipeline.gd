class_name TestSpellPipeline
extends RefCounted

## Simulates what SpellCastingSession + SpellValidationRunner do after listen ends.

const FireballSpell := preload("res://scenes/spells/fireball/fireball.tres")
const SpellCastValidatorScript := preload("res://scripts/spells/spell_cast_validator.gd")
const SpellValidationRunnerScript := preload("res://scripts/spells/spell_validation_runner.gd")

const NO_TRANSCRIPT_REASON := SpellCastValidatorScript.NO_TRANSCRIPT_REASON


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_with_transcript_passes(tree)
	failures += _test_without_transcript_fails(tree)
	failures += _test_runner_payload_roundtrips_through_codec(tree)
	failures += _test_cast_fireball_with_matching_transcript(tree)
	return failures


func _loud_samples(duration_sec: float, sample_rate: int = 48000) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for _i in int(sample_rate * duration_sec):
		samples.append(0.04)
	return samples


func _run_targeted(
	tree: SceneTree,
	samples: PackedFloat32Array,
	sample_rate: int,
	transcript_words: PackedStringArray
) -> Dictionary:
	var runner: SpellValidationRunner = SpellValidationRunnerScript.new()
	tree.root.add_child(runner)
	if not runner.start(
		"targeted",
		samples,
		sample_rate,
		FireballSpell,
		[],
		transcript_words,
		PackedFloat32Array()
	):
		runner.queue_free()
		return {"ok": false, "error": "runner failed to start"}
	var payload := _wait_for_runner(runner)
	runner.queue_free()
	return payload


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


func _test_with_transcript_passes(tree: SceneTree) -> int:
	var payload := _run_targeted(
		tree,
		_loud_samples(0.5),
		48000,
		PackedStringArray(["fireball"])
	)
	if not bool(payload.get("ok", false)):
		push_error("Expected cast with transcript to succeed, got: %s" % payload)
		return 1
	var parsed := SpellValidationCodec.parse_worker_response(payload)
	var result: CastValidationResult = parsed.get("result")
	if result == null or not result.passed:
		push_error(
			"Expected matching transcript to pass, reason: %s"
			% (result.failure_reason if result != null else "null")
		)
		return 1
	return 0


func _test_without_transcript_fails(tree: SceneTree) -> int:
	var payload := _run_targeted(
		tree,
		_loud_samples(0.5),
		48000,
		PackedStringArray()
	)
	if not bool(payload.get("ok", false)):
		push_error("Expected runner to return structured payload even on failed cast")
		return 1
	var parsed := SpellValidationCodec.parse_worker_response(payload)
	var result: CastValidationResult = parsed.get("result")
	if result == null:
		push_error("Expected failed cast payload to include a result object")
		return 1
	if result.passed:
		push_error("Expected cast without transcript to fail")
		return 1
	if result.failure_reason != NO_TRANSCRIPT_REASON:
		push_error(
			"Expected speech recognition failure reason, got: %s"
			% result.failure_reason
		)
		return 1
	return 0


func _test_runner_payload_roundtrips_through_codec(tree: SceneTree) -> int:
	var payload := _run_targeted(
		tree,
		_loud_samples(0.3),
		44100,
		PackedStringArray(["fireball"])
	)
	var parsed := SpellValidationCodec.parse_worker_response(payload)
	if not bool(parsed.get("ok", false)):
		push_error("Expected codec parse to succeed for runner payload")
		return 1
	var words: PackedStringArray = parsed.get("transcript_words", PackedStringArray())
	if words.is_empty() or words[0] != "fireball":
		push_error("Expected transcript words to roundtrip through codec")
		return 1
	return 0


func _test_cast_fireball_with_matching_transcript(tree: SceneTree) -> int:
	var payload := _run_targeted(
		tree,
		_loud_samples(0.5),
		48000,
		PackedStringArray(["fireball"])
	)
	if not bool(payload.get("ok", false)):
		push_error("Expected fireball cast payload to succeed, got: %s" % payload)
		return 1
	if str(payload.get("spell_id", "")) != "fireball":
		push_error("Expected spell_id fireball in payload, got: %s" % payload.get("spell_id"))
		return 1
	var parsed := SpellValidationCodec.parse_worker_response(payload)
	var result: CastValidationResult = parsed.get("result")
	if result == null or not result.passed:
		push_error("Expected fireball cast validation to pass")
		return 1
	if result.heard_text != "fireball":
		push_error("Expected heard incantation 'fireball', got: %s" % result.heard_text)
		return 1
	if result.incantation_text != "fireball":
		push_error("Expected incantation_text 'fireball', got: %s" % result.incantation_text)
		return 1
	return 0
