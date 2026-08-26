class_name SpellAudioUtils
extends RefCounted

## Audio analysis helpers for spell cast validation.

const RHYTHM_TOLERANCE_MS := 150
const MIN_SPEECH_RMS := 0.015
## Lower threshold for finding speech windows inside a long recording.
const SPEECH_DETECT_RMS := 0.008


static func finalize_validation(
	words_ok: bool,
	order_ok: bool,
	rhythm_score: float,
	tone_score: float,
	audio_rms: float,
	duration_sec: float,
	expected_sec: float,
	incantation: String,
	require_rhythm: bool,
	detected_pitches: PackedFloat32Array,
	target_pitches: PackedFloat32Array
) -> CastValidationResult:
	if not words_ok:
		return _fail_partial(
			false, order_ok, rhythm_score, tone_score,
			"Incorrect incantation words",
			audio_rms, duration_sec, expected_sec, incantation,
			detected_pitches, target_pitches
		)
	if not order_ok:
		return _fail_partial(
			words_ok, false, rhythm_score, tone_score,
			"Wrong word order",
			audio_rms, duration_sec, expected_sec, incantation,
			detected_pitches, target_pitches
		)
	if require_rhythm and rhythm_score < 0.55:
		return _fail_partial(
			words_ok, order_ok, rhythm_score, tone_score,
			"Rhythm was off — match the beat",
			audio_rms, duration_sec, expected_sec, incantation,
			detected_pitches, target_pitches
		)
	if tone_score < 0.45:
		return _fail_partial(
			words_ok, order_ok, rhythm_score, tone_score,
			"Tone was off — try the pitch guide",
			audio_rms, duration_sec, expected_sec, incantation,
			detected_pitches, target_pitches
		)
	var result := CastValidationResult.success(words_ok, order_ok, rhythm_score, tone_score)
	_apply_audio_details(
		result, audio_rms, duration_sec, expected_sec, incantation,
		detected_pitches, target_pitches
	)
	return result


static func fail_with_audio(
	reason: String,
	audio_rms: float,
	duration_sec: float,
	expected_sec: float,
	incantation: String = ""
) -> CastValidationResult:
	var result := CastValidationResult.fail(reason)
	_apply_audio_details(
		result, audio_rms, duration_sec, expected_sec, incantation,
		PackedFloat32Array(), PackedFloat32Array()
	)
	return result


static func score_rhythm(
	word_starts_sec: PackedFloat32Array,
	cadence_ms: PackedInt32Array
) -> float:
	if cadence_ms.is_empty() or word_starts_sec.is_empty():
		return 0.7

	var expected_count := mini(cadence_ms.size(), word_starts_sec.size())
	if expected_count == 0:
		return 0.7

	var total_error_ms := 0.0
	for i in expected_count:
		var expected_ms: float = float(cadence_ms[i])
		var actual_ms: float = word_starts_sec[i] * 1000.0
		total_error_ms += absf(actual_ms - expected_ms)

	var avg_error: float = total_error_ms / float(expected_count)
	return clampf(1.0 - avg_error / RHYTHM_TOLERANCE_MS, 0.0, 1.0)


static func score_duration_rhythm(
	samples: PackedFloat32Array,
	sample_rate: int,
	spell: SpellDefinition
) -> float:
	return score_duration_rhythm_for_target_ms(
		samples,
		sample_rate,
		float(spell.get_target_duration_ms())
	)


static func score_duration_rhythm_for_target_ms(
	samples: PackedFloat32Array,
	sample_rate: int,
	expected_ms: float
) -> float:
	var actual_ms: float = float(samples.size()) / float(sample_rate) * 1000.0
	var error: float = absf(actual_ms - expected_ms)
	return clampf(1.0 - error / (RHYTHM_TOLERANCE_MS * 2.0), 0.0, 1.0)


static func score_tone_with_details(
	samples: PackedFloat32Array,
	sample_rate: int,
	spell: SpellDefinition,
	out_detected: PackedFloat32Array
) -> void:
	score_tone_with_pitch_targets(
		samples,
		sample_rate,
		spell.pitch_targets_hz,
		maxi(1, spell.word_count()),
		out_detected
	)


static func score_tone_with_pitch_targets(
	samples: PackedFloat32Array,
	sample_rate: int,
	pitch_targets_hz: PackedFloat32Array,
	word_count: int,
	out_detected: PackedFloat32Array
) -> void:
	if pitch_targets_hz.is_empty():
		return

	var slice_size: int = int(float(samples.size()) / float(word_count))
	if slice_size <= 0:
		return

	for i in word_count:
		var start := i * slice_size
		var end := start + slice_size if i < word_count - 1 else samples.size()
		var slice: PackedFloat32Array = samples.slice(start, end)
		out_detected.append(PitchAnalyzer.estimate_hz(slice, sample_rate))


static func average_pitch_scores(
	detected: PackedFloat32Array,
	targets: PackedFloat32Array
) -> float:
	if targets.is_empty():
		return 1.0
	if detected.is_empty():
		return 0.0
	var total := 0.0
	var count := 0
	for i in detected.size():
		var target_idx := mini(i, targets.size() - 1)
		total += PitchAnalyzer.pitch_band_score(detected[i], targets[target_idx])
		count += 1
	if count == 0:
		return 0.0
	return total / float(count)


static func compute_rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum := 0.0
	for sample in samples:
		sum += sample * sample
	return sqrt(sum / float(samples.size()))


static func compute_peak_window_rms(samples: PackedFloat32Array, sample_rate: int) -> float:
	if samples.is_empty() or sample_rate <= 0:
		return 0.0
	var window: int = maxi(1, int(float(sample_rate) * 0.02))
	var peak := 0.0
	var index := 0
	while index < samples.size():
		var end: int = mini(index + window, samples.size())
		peak = maxf(peak, _window_rms(samples, index, end))
		index += window
	return peak


static func extract_speech_samples(
	samples: PackedFloat32Array,
	sample_rate: int,
	threshold: float = SPEECH_DETECT_RMS
) -> PackedFloat32Array:
	if samples.is_empty() or sample_rate <= 0:
		return samples

	var window: int = maxi(1, int(float(sample_rate) * 0.02))
	var first: int = -1
	var last: int = -1
	var index: int = 0
	while index < samples.size():
		var end: int = mini(index + window, samples.size())
		if _window_rms(samples, index, end) >= threshold:
			if first < 0:
				first = index
			last = end
		index += window

	if first < 0:
		return samples

	var pad: int = int(float(sample_rate) * 0.05)
	first = maxi(0, first - pad)
	last = mini(samples.size(), last + pad)
	return samples.slice(first, last)


static func _fail_partial(
	words_ok: bool,
	order_ok: bool,
	rhythm_score: float,
	tone_score: float,
	reason: String,
	audio_rms: float,
	duration_sec: float,
	expected_sec: float,
	incantation: String,
	detected_pitches: PackedFloat32Array,
	target_pitches: PackedFloat32Array
) -> CastValidationResult:
	var result: CastValidationResult = CastValidationResult.fail(reason)
	result.words_ok = words_ok
	result.order_ok = order_ok
	result.rhythm_score = rhythm_score
	result.tone_score = tone_score
	_apply_audio_details(
		result, audio_rms, duration_sec, expected_sec, incantation,
		detected_pitches, target_pitches
	)
	return result


static func _apply_audio_details(
	result: CastValidationResult,
	audio_rms: float,
	duration_sec: float,
	expected_sec: float,
	incantation: String,
	detected_pitches: PackedFloat32Array,
	target_pitches: PackedFloat32Array
) -> void:
	result.audio_rms = audio_rms
	result.audio_duration_sec = duration_sec
	result.expected_duration_sec = expected_sec
	result.incantation_text = incantation
	result.detected_pitches_hz = detected_pitches
	result.target_pitches_hz = target_pitches


static func _window_rms(samples: PackedFloat32Array, start: int, end: int) -> float:
	if start >= end:
		return 0.0
	var sum := 0.0
	for i in range(start, end):
		var sample := samples[i]
		sum += sample * sample
	return sqrt(sum / float(end - start))
