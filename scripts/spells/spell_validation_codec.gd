class_name SpellValidationCodec
extends RefCounted

## Converts validation payloads between thread-safe dictionaries and typed results.


static func result_to_dict(result: CastValidationResult) -> Dictionary:
	if result == null:
		return {}
	return {
		"passed": result.passed,
		"words_ok": result.words_ok,
		"order_ok": result.order_ok,
		"rhythm_score": result.rhythm_score,
		"tone_score": result.tone_score,
		"failure_reason": result.failure_reason,
		"incantation_text": result.incantation_text,
		"heard_text": result.heard_text,
		"audio_rms": result.audio_rms,
		"audio_duration_sec": result.audio_duration_sec,
		"expected_duration_sec": result.expected_duration_sec,
		"detected_pitches_hz": array_from_floats(result.detected_pitches_hz),
		"target_pitches_hz": array_from_floats(result.target_pitches_hz),
	}


static func result_from_dict(data: Dictionary) -> CastValidationResult:
	if data.is_empty():
		return null
	var result := CastValidationResult.new()
	result.passed = bool(data.get("passed", false))
	result.words_ok = bool(data.get("words_ok", false))
	result.order_ok = bool(data.get("order_ok", false))
	result.rhythm_score = float(data.get("rhythm_score", 0.0))
	result.tone_score = float(data.get("tone_score", 0.0))
	result.failure_reason = str(data.get("failure_reason", ""))
	result.incantation_text = str(data.get("incantation_text", ""))
	result.heard_text = str(data.get("heard_text", ""))
	result.audio_rms = float(data.get("audio_rms", 0.0))
	result.audio_duration_sec = float(data.get("audio_duration_sec", 0.0))
	result.expected_duration_sec = float(data.get("expected_duration_sec", 0.0))
	result.detected_pitches_hz = packed_floats_from_array(data.get("detected_pitches_hz", []))
	result.target_pitches_hz = packed_floats_from_array(data.get("target_pitches_hz", []))
	return result


static func parse_worker_response(payload: Dictionary) -> Dictionary:
	if payload.is_empty() or not bool(payload.get("ok", false)):
		return {
			"ok": false,
			"error": str(payload.get("error", "Validation failed")),
		}
	return {
		"ok": true,
		"spell_id": str(payload.get("spell_id", "")),
		"result": result_from_dict(payload.get("result", {})),
		"transcript_words": packed_strings_from_array(payload.get("transcript_words", [])),
		"word_starts_sec": packed_floats_from_array(payload.get("word_starts_sec", [])),
		"debug_lines": packed_strings_from_array(payload.get("debug_lines", [])),
	}


static func array_from_strings(values: PackedStringArray) -> Array:
	var out: Array = []
	for value in values:
		out.append(value)
	return out


static func array_from_floats(values: PackedFloat32Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(value)
	return out


static func packed_strings_from_array(values: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if values is Array:
		for value in values:
			out.append(str(value))
	return out


static func packed_floats_from_array(values: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if values is Array:
		for value in values:
			out.append(float(value))
	return out


static func array_from_ints(values: PackedInt32Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(value)
	return out


static func packed_ints_from_array(values: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if values is Array:
		for value in values:
			out.append(int(value))
	return out


static func spell_to_dict(spell: SpellDefinition) -> Dictionary:
	if spell == null:
		return {}
	return {
		"id": spell.id,
		"display_name": spell.display_name,
		"incantation_words": array_from_strings(spell.incantation_words),
		"syllable_cadence_ms": array_from_ints(spell.syllable_cadence_ms),
		"pitch_targets_hz": array_from_floats(spell.pitch_targets_hz),
		"require_rhythm": spell.require_rhythm,
	}


static func spells_to_dict_array(spells: Array) -> Array:
	var out: Array = []
	for spell in spells:
		if spell is SpellDefinition:
			out.append(spell_to_dict(spell))
	return out


static func spell_dict_incantation_text(spell_data: Dictionary) -> String:
	return " ".join(packed_strings_from_array(spell_data.get("incantation_words", [])))


static func spell_dict_word_count(spell_data: Dictionary) -> int:
	return packed_strings_from_array(spell_data.get("incantation_words", [])).size()


static func spell_dict_target_duration_sec(spell_data: Dictionary) -> float:
	return float(spell_dict_target_duration_ms(spell_data)) / 1000.0


static func spell_dict_target_duration_ms(spell_data: Dictionary) -> int:
	const DEFAULT_ONE_WORD_DURATION_MS := 700
	var cadence_ms := packed_ints_from_array(spell_data.get("syllable_cadence_ms", []))
	var word_count := spell_dict_word_count(spell_data)
	if cadence_ms.is_empty():
		return maxi(600, word_count * 450)
	var last_ms: int = cadence_ms[cadence_ms.size() - 1]
	if word_count == 1 and last_ms <= 0:
		return DEFAULT_ONE_WORD_DURATION_MS
	if last_ms <= 0:
		return DEFAULT_ONE_WORD_DURATION_MS
	return last_ms + 250
