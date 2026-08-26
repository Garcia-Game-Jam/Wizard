class_name SpellCastValidator
extends RefCounted

## Single gate for spell cast validation. Words must match before rhythm/tone checks.

const IncantationMatcherScript := preload("res://scripts/spells/incantation_matcher.gd")
const SpellValidationCodecScript := preload("res://scripts/spells/spell_validation_codec.gd")

const NO_TRANSCRIPT_REASON := (
	"Couldn't verify incantation words — speech recognition is required"
)


static func validate(
	spell: SpellDefinition,
	samples: PackedFloat32Array,
	sample_rate: int,
	transcript_words: PackedStringArray,
	word_starts_sec: PackedFloat32Array
) -> CastValidationResult:
	if spell == null:
		return CastValidationResult.fail("No spell defined")

	samples = SpellAudioUtils.extract_speech_samples(samples, sample_rate)
	var incantation: String = spell.get_incantation_text()
	var expected_sec: float = spell.get_target_duration_sec()

	if samples.is_empty():
		return _with_transcript(
			SpellAudioUtils.fail_with_audio(
				"No audio captured", 0.0, 0.0, expected_sec, incantation
			),
			spell,
			transcript_words
		)

	var rms: float = SpellAudioUtils.compute_peak_window_rms(samples, sample_rate)
	var duration_sec: float = float(samples.size()) / float(sample_rate) if sample_rate > 0 else 0.0
	if rms < SpellAudioUtils.MIN_SPEECH_RMS:
		return _with_transcript(
			SpellAudioUtils.fail_with_audio(
				"Speak louder into the microphone", rms, duration_sec, expected_sec, incantation
			),
			spell,
			transcript_words
		)

	if transcript_words.is_empty():
		return _with_transcript(
			SpellAudioUtils.fail_with_audio(
				NO_TRANSCRIPT_REASON, rms, duration_sec, expected_sec, incantation
			),
			spell,
			transcript_words
		)

	var words_ok: bool = IncantationMatcherScript.matches(transcript_words, spell)
	var order_ok: bool = words_ok
	var rhythm_score: float = 1.0
	if words_ok and spell.require_rhythm:
		if not word_starts_sec.is_empty():
			rhythm_score = SpellAudioUtils.score_rhythm(
				word_starts_sec, spell.syllable_cadence_ms
			)
		else:
			rhythm_score = SpellAudioUtils.score_duration_rhythm(
				samples, sample_rate, spell
			)

	var detected_pitches: PackedFloat32Array = PackedFloat32Array()
	var target_pitches: PackedFloat32Array = spell.pitch_targets_hz.duplicate()
	SpellAudioUtils.score_tone_with_details(
		samples, sample_rate, spell, detected_pitches
	)
	var tone_score: float = SpellAudioUtils.average_pitch_scores(
		detected_pitches, target_pitches
	)

	return _with_transcript(
		SpellAudioUtils.finalize_validation(
			words_ok,
			order_ok,
			rhythm_score,
			tone_score,
			rms,
			duration_sec,
			expected_sec,
			incantation,
			spell.require_rhythm,
			detected_pitches,
			target_pitches
		),
		spell,
		transcript_words
	)


static func validate_spell_dict(
	spell_data: Dictionary,
	samples: PackedFloat32Array,
	sample_rate: int,
	transcript_words: PackedStringArray,
	word_starts_sec: PackedFloat32Array
) -> CastValidationResult:
	if spell_data.is_empty():
		return CastValidationResult.fail("No spell defined")

	samples = SpellAudioUtils.extract_speech_samples(samples, sample_rate)
	var incantation: String = SpellValidationCodecScript.spell_dict_incantation_text(spell_data)
	var expected_sec: float = SpellValidationCodecScript.spell_dict_target_duration_sec(spell_data)
	var incantation_words := SpellValidationCodecScript.packed_strings_from_array(
		spell_data.get("incantation_words", [])
	)
	var require_rhythm: bool = bool(spell_data.get("require_rhythm", false))
	var cadence_ms := SpellValidationCodecScript.packed_ints_from_array(
		spell_data.get("syllable_cadence_ms", [])
	)
	var pitch_targets := SpellValidationCodecScript.packed_floats_from_array(
		spell_data.get("pitch_targets_hz", [])
	)

	if samples.is_empty():
		return _with_transcript_dict(
			SpellAudioUtils.fail_with_audio(
				"No audio captured", 0.0, 0.0, expected_sec, incantation
			),
			spell_data,
			transcript_words
		)

	var rms: float = SpellAudioUtils.compute_peak_window_rms(samples, sample_rate)
	var duration_sec: float = float(samples.size()) / float(sample_rate) if sample_rate > 0 else 0.0
	if rms < SpellAudioUtils.MIN_SPEECH_RMS:
		return _with_transcript_dict(
			SpellAudioUtils.fail_with_audio(
				"Speak louder into the microphone", rms, duration_sec, expected_sec, incantation
			),
			spell_data,
			transcript_words
		)

	if transcript_words.is_empty():
		return _with_transcript_dict(
			SpellAudioUtils.fail_with_audio(
				NO_TRANSCRIPT_REASON, rms, duration_sec, expected_sec, incantation
			),
			spell_data,
			transcript_words
		)

	var words_ok: bool = IncantationMatcherScript.matches_incantation_words(
		transcript_words, incantation_words
	)
	var order_ok: bool = words_ok
	var rhythm_score: float = 1.0
	if words_ok and require_rhythm:
		if not word_starts_sec.is_empty():
			rhythm_score = SpellAudioUtils.score_rhythm(word_starts_sec, cadence_ms)
		else:
			rhythm_score = SpellAudioUtils.score_duration_rhythm_for_target_ms(
				samples,
				sample_rate,
				float(SpellValidationCodecScript.spell_dict_target_duration_ms(spell_data))
			)

	var detected_pitches: PackedFloat32Array = PackedFloat32Array()
	var target_pitches: PackedFloat32Array = pitch_targets.duplicate()
	SpellAudioUtils.score_tone_with_pitch_targets(
		samples,
		sample_rate,
		pitch_targets,
		maxi(1, incantation_words.size()),
		detected_pitches
	)
	var tone_score: float = SpellAudioUtils.average_pitch_scores(
		detected_pitches, target_pitches
	)

	return _with_transcript_dict(
		SpellAudioUtils.finalize_validation(
			words_ok,
			order_ok,
			rhythm_score,
			tone_score,
			rms,
			duration_sec,
			expected_sec,
			incantation,
			require_rhythm,
			detected_pitches,
			target_pitches
		),
		spell_data,
		transcript_words
	)


static func resolve_free_cast_dict(
	candidate_data: Array,
	samples: PackedFloat32Array,
	sample_rate: int,
	transcript_words: PackedStringArray,
	word_starts_sec: PackedFloat32Array
) -> Dictionary:
	var debug_lines: PackedStringArray = PackedStringArray()
	var candidate_ids: PackedStringArray = PackedStringArray()
	for spell_data in candidate_data:
		if spell_data is Dictionary and not str(spell_data.get("id", "")).is_empty():
			candidate_ids.append(str(spell_data.get("id", "")))
	debug_lines.append(
		"candidates=[%s] sample_rate=%d raw_samples=%d"
		% [", ".join(candidate_ids), sample_rate, samples.size()]
	)

	if candidate_data.is_empty():
		debug_lines.append("result=FAIL (no candidates)")
		return _pack_free_cast_dict(null, CastValidationResult.fail("No spells learned yet"), debug_lines)

	samples = SpellAudioUtils.extract_speech_samples(samples, sample_rate)
	var peak_rms: float = SpellAudioUtils.compute_peak_window_rms(samples, sample_rate)
	debug_lines.append("trimmed_samples=%d peak_rms=%.4f" % [samples.size(), peak_rms])

	if transcript_words.is_empty():
		debug_lines.append("mode=no transcript")
		debug_lines.append("result=FAIL (words not verified)")
		var reason := (
			"Speak louder into the microphone"
			if peak_rms < SpellAudioUtils.MIN_SPEECH_RMS
			else (
				"Couldn't verify which spell you said — speech recognition is required for free casting"
			)
		)
		var no_stt := CastValidationResult.fail(reason)
		no_stt.incantation_text = _expected_from_candidate_dicts(candidate_data)
		no_stt.audio_rms = peak_rms
		no_stt.audio_duration_sec = (
			float(samples.size()) / float(sample_rate) if sample_rate > 0 else 0.0
		)
		CastValidationResult.apply_transcript(no_stt, transcript_words)
		return _pack_free_cast_dict(null, no_stt, debug_lines)

	debug_lines.append('mode=transcript words="%s"' % " ".join(transcript_words))

	var word_matches: Array = []
	for spell_data in candidate_data:
		if spell_data is Dictionary:
			var incantation_words := SpellValidationCodecScript.packed_strings_from_array(
				spell_data.get("incantation_words", [])
			)
			if IncantationMatcherScript.matches_incantation_words(
				transcript_words, incantation_words
			):
				word_matches.append(spell_data)

	var match_ids: PackedStringArray = PackedStringArray()
	for spell_data in word_matches:
		match_ids.append(str(spell_data.get("id", "")))
	debug_lines.append("word_matches=[%s]" % ", ".join(match_ids))

	if word_matches.is_empty():
		debug_lines.append("result=FAIL (no incantation match)")
		var fail := CastValidationResult.fail("No learned spell matched those words")
		fail.incantation_text = _expected_from_candidate_dicts(candidate_data)
		CastValidationResult.apply_transcript(fail, transcript_words)
		return _pack_free_cast_dict(null, fail, debug_lines)

	var passed: Array[Dictionary] = []
	var first_failure: CastValidationResult = null
	for spell_data in word_matches:
		var result := validate_spell_dict(
			spell_data, samples, sample_rate, transcript_words, word_starts_sec
		)
		_append_candidate_dict_debug(debug_lines, spell_data, result)
		if result.passed:
			passed.append({"spell": spell_data, "result": result})
		elif first_failure == null:
			first_failure = result

	if passed.size() == 1:
		debug_lines.append("result=%s" % str(passed[0]["spell"].get("id", "")))
		return _pack_free_cast_dict(passed[0]["spell"], passed[0]["result"], debug_lines)

	if passed.is_empty():
		debug_lines.append("result=FAIL (incantation matched but cast checks failed)")
		return _pack_free_cast_dict(null, first_failure, debug_lines)

	# Prefer the longest matching incantation ("light ball" over "light").
	passed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_words := SpellValidationCodecScript.packed_strings_from_array(
			a.get("spell", {}).get("incantation_words", [])
		)
		var b_words := SpellValidationCodecScript.packed_strings_from_array(
			b.get("spell", {}).get("incantation_words", [])
		)
		return a_words.size() > b_words.size()
	)
	var best: Dictionary = passed[0]
	var best_len := SpellValidationCodecScript.packed_strings_from_array(
		best.get("spell", {}).get("incantation_words", [])
	).size()
	var tied := 0
	for entry in passed:
		var entry_len := SpellValidationCodecScript.packed_strings_from_array(
			entry.get("spell", {}).get("incantation_words", [])
		).size()
		if entry_len == best_len:
			tied += 1
	if tied == 1:
		debug_lines.append(
			"result=%s (longest match among %d)"
			% [str(best.get("spell", {}).get("id", "")), passed.size()]
		)
		return _pack_free_cast_dict(best["spell"], best["result"], debug_lines)

	debug_lines.append("result=FAIL (ambiguous: %d spells passed)" % passed.size())
	var ambiguous := CastValidationResult.fail("Be more specific — say one spell clearly")
	ambiguous.incantation_text = _expected_from_candidate_dicts(word_matches)
	CastValidationResult.apply_transcript(ambiguous, transcript_words)
	return _pack_free_cast_dict(null, ambiguous, debug_lines)


static func resolve_free_cast(
	candidates: Array[SpellDefinition],
	samples: PackedFloat32Array,
	sample_rate: int,
	transcript_words: PackedStringArray,
	word_starts_sec: PackedFloat32Array
) -> Dictionary:
	var debug_lines: PackedStringArray = PackedStringArray()
	var candidate_ids: PackedStringArray = PackedStringArray()
	for spell in candidates:
		if spell != null:
			candidate_ids.append(spell.id)
	debug_lines.append(
		"candidates=[%s] sample_rate=%d raw_samples=%d"
		% [", ".join(candidate_ids), sample_rate, samples.size()]
	)

	if candidates.is_empty():
		debug_lines.append("result=FAIL (no candidates)")
		return _pack_free_cast(null, CastValidationResult.fail("No spells learned yet"), debug_lines)

	samples = SpellAudioUtils.extract_speech_samples(samples, sample_rate)
	var peak_rms: float = SpellAudioUtils.compute_peak_window_rms(samples, sample_rate)
	debug_lines.append("trimmed_samples=%d peak_rms=%.4f" % [samples.size(), peak_rms])

	if transcript_words.is_empty():
		debug_lines.append("mode=no transcript")
		debug_lines.append("result=FAIL (words not verified)")
		var reason := (
			"Speak louder into the microphone"
			if peak_rms < SpellAudioUtils.MIN_SPEECH_RMS
			else (
				"Couldn't verify which spell you said — speech recognition is required for free casting"
			)
		)
		var no_stt := CastValidationResult.fail(reason)
		no_stt.incantation_text = _expected_from_candidates(candidates)
		no_stt.audio_rms = peak_rms
		no_stt.audio_duration_sec = (
			float(samples.size()) / float(sample_rate) if sample_rate > 0 else 0.0
		)
		CastValidationResult.apply_transcript(no_stt, transcript_words)
		return _pack_free_cast(null, no_stt, debug_lines)

	debug_lines.append('mode=transcript words="%s"' % " ".join(transcript_words))

	var word_matches: Array[SpellDefinition] = []
	for spell in candidates:
		if IncantationMatcherScript.matches(transcript_words, spell):
			word_matches.append(spell)

	var match_ids: PackedStringArray = PackedStringArray()
	for spell in word_matches:
		match_ids.append(spell.id)
	debug_lines.append("word_matches=[%s]" % ", ".join(match_ids))

	if word_matches.is_empty():
		debug_lines.append("result=FAIL (no incantation match)")
		var fail := CastValidationResult.fail("No learned spell matched those words")
		fail.incantation_text = _expected_from_candidates(candidates)
		CastValidationResult.apply_transcript(fail, transcript_words)
		return _pack_free_cast(null, fail, debug_lines)

	var passed: Array[Dictionary] = []
	var first_failure: CastValidationResult = null
	for spell in word_matches:
		var result := validate(
			spell, samples, sample_rate, transcript_words, word_starts_sec
		)
		_append_candidate_debug(debug_lines, spell, result)
		if result.passed:
			passed.append({"spell": spell, "result": result})
		elif first_failure == null:
			first_failure = result

	if passed.size() == 1:
		debug_lines.append("result=%s" % passed[0]["spell"].id)
		return _pack_free_cast(passed[0]["spell"], passed[0]["result"], debug_lines)

	if passed.is_empty():
		debug_lines.append("result=FAIL (incantation matched but cast checks failed)")
		return _pack_free_cast(null, first_failure, debug_lines)

	# Prefer the longest matching incantation ("light ball" over "light").
	passed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_spell: SpellDefinition = a.get("spell")
		var b_spell: SpellDefinition = b.get("spell")
		var a_len := a_spell.incantation_words.size() if a_spell != null else 0
		var b_len := b_spell.incantation_words.size() if b_spell != null else 0
		return a_len > b_len
	)
	var best: Dictionary = passed[0]
	var best_spell: SpellDefinition = best.get("spell")
	var best_len := best_spell.incantation_words.size() if best_spell != null else 0
	var tied := 0
	for entry in passed:
		var entry_spell: SpellDefinition = entry.get("spell")
		var entry_len := entry_spell.incantation_words.size() if entry_spell != null else 0
		if entry_len == best_len:
			tied += 1
	if tied == 1:
		debug_lines.append(
			"result=%s (longest match among %d)" % [best_spell.id, passed.size()]
		)
		return _pack_free_cast(best["spell"], best["result"], debug_lines)

	debug_lines.append("result=FAIL (ambiguous: %d spells passed)" % passed.size())
	var ambiguous := CastValidationResult.fail("Be more specific — say one spell clearly")
	ambiguous.incantation_text = _expected_from_candidates(word_matches)
	CastValidationResult.apply_transcript(ambiguous, transcript_words)
	return _pack_free_cast(null, ambiguous, debug_lines)


static func _pack_free_cast(
	spell: SpellDefinition,
	result: CastValidationResult,
	debug_lines: PackedStringArray
) -> Dictionary:
	return {"spell": spell, "result": result, "debug_lines": debug_lines}


static func _append_candidate_debug(
	debug_lines: PackedStringArray,
	spell: SpellDefinition,
	result: CastValidationResult
) -> void:
	var detail: String
	if result.passed:
		detail = (
			"PASS rms=%.3f heard=%.2fs target=%.2fs"
			% [result.audio_rms, result.audio_duration_sec, result.expected_duration_sec]
		)
	else:
		detail = "FAIL (%s)" % result.failure_reason
	if not result.heard_text.is_empty() or not result.incantation_text.is_empty():
		detail += " | %s" % result.get_speech_match_line()
	debug_lines.append("  '%s': %s" % [spell.id, detail])


static func _with_transcript(
	result: CastValidationResult,
	spell: SpellDefinition,
	transcript_words: PackedStringArray
) -> CastValidationResult:
	if spell != null and result.incantation_text.is_empty():
		result.incantation_text = spell.get_incantation_text()
	CastValidationResult.apply_transcript(result, transcript_words)
	return result


static func _with_transcript_dict(
	result: CastValidationResult,
	spell_data: Dictionary,
	transcript_words: PackedStringArray
) -> CastValidationResult:
	if not spell_data.is_empty() and result.incantation_text.is_empty():
		result.incantation_text = SpellValidationCodecScript.spell_dict_incantation_text(
			spell_data
		)
	CastValidationResult.apply_transcript(result, transcript_words)
	return result


static func _pack_free_cast_dict(
	spell_data: Variant,
	result: CastValidationResult,
	debug_lines: PackedStringArray
) -> Dictionary:
	return {"spell": spell_data, "result": result, "debug_lines": debug_lines}


static func _append_candidate_dict_debug(
	debug_lines: PackedStringArray,
	spell_data: Dictionary,
	result: CastValidationResult
) -> void:
	var detail: String
	if result.passed:
		detail = (
			"PASS rms=%.3f heard=%.2fs target=%.2fs"
			% [result.audio_rms, result.audio_duration_sec, result.expected_duration_sec]
		)
	else:
		detail = "FAIL (%s)" % result.failure_reason
	if not result.heard_text.is_empty() or not result.incantation_text.is_empty():
		detail += " | %s" % result.get_speech_match_line()
	debug_lines.append("  '%s': %s" % [str(spell_data.get("id", "")), detail])


static func _expected_from_candidate_dicts(candidates: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for spell_data in candidates:
		if spell_data is Dictionary:
			parts.append(
				'"%s"'
				% SpellValidationCodecScript.spell_dict_incantation_text(spell_data)
			)
	if parts.is_empty():
		return "?"
	return ", ".join(parts)


static func _expected_from_candidates(candidates: Array[SpellDefinition]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for spell in candidates:
		if spell != null:
			parts.append('"%s"' % spell.get_incantation_text())
	if parts.is_empty():
		return "?"
	return ", ".join(parts)
