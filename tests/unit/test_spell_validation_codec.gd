extends RefCounted

const CastValidationResultScript := preload("res://scripts/spells/cast_validation_result.gd")


func run() -> int:
	var failures := 0
	failures += _test_result_roundtrip()
	failures += _test_parse_worker_response()
	return failures


func _test_result_roundtrip() -> int:
	var result := CastValidationResultScript.success(true, true, 0.9, 0.8)
	result.heard_text = "fireball"
	result.incantation_text = "fireball"
	result.audio_rms = 0.04

	var restored: CastValidationResultScript = SpellValidationCodec.result_from_dict(
		SpellValidationCodec.result_to_dict(result)
	)
	if restored == null or not restored.passed:
		push_error("Expected validation result roundtrip to preserve pass state")
		return 1
	if restored.heard_text != "fireball":
		push_error("Expected validation result roundtrip to preserve heard text")
		return 1
	return 0


func _test_parse_worker_response() -> int:
	var result := CastValidationResultScript.success(true, true, 1.0, 1.0)
	result.heard_text = "fireball"
	var parsed: Dictionary = SpellValidationCodec.parse_worker_response({
		"ok": true,
		"spell_id": "fireball",
		"result": SpellValidationCodec.result_to_dict(result),
		"transcript_words": ["fireball"],
		"word_starts_sec": [0.1],
		"debug_lines": ["line"],
	})
	if not bool(parsed.get("ok", false)):
		push_error("Expected worker response parse to succeed")
		return 1
	if str(parsed.get("spell_id", "")) != "fireball":
		push_error("Expected spell_id from worker response")
		return 1
	var restored: CastValidationResultScript = parsed.get("result")
	if restored == null or restored.heard_text != "fireball":
		push_error("Expected parsed validation result")
		return 1
	return 0
