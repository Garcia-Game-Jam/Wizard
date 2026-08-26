extends RefCounted

const SpellAudioUtilsScript := preload("res://scripts/spells/spell_audio_utils.gd")
const SpellCastValidatorScript := preload("res://scripts/spells/spell_cast_validator.gd")
const CastValidationResultScript := preload("res://scripts/spells/cast_validation_result.gd")
const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")


func run() -> int:
	var failures := 0
	failures += _test_extract_speech_samples_trims_silence()
	failures += _test_peak_rms_detects_speech_in_long_recording()
	failures += _test_coaching_tip_for_long_cast()
	failures += _test_coaching_tip_for_quiet_cast()
	failures += _test_easy_spell_passes_with_transcript()
	failures += _test_free_cast_requires_transcript()
	failures += _test_free_cast_identifies_single_word_spell()
	failures += _test_free_cast_identifies_two_word_spell()
	failures += _test_free_cast_rejects_wrong_word_for_only_known_spell()
	return failures


func _test_extract_speech_samples_trims_silence() -> int:
	var sample_rate := 100
	var samples := PackedFloat32Array()
	for _i in 50:
		samples.append(0.0)
	for _i in 30:
		samples.append(0.05)
	for _i in 50:
		samples.append(0.0)

	var trimmed := SpellAudioUtilsScript.extract_speech_samples(samples, sample_rate)
	if trimmed.size() >= samples.size():
		push_error("Expected speech trim to remove leading/trailing silence")
		return 1
	if trimmed.size() < 20:
		push_error("Expected trimmed speech to keep the spoken segment")
		return 1
	return 0


func _test_peak_rms_detects_speech_in_long_recording() -> int:
	var sample_rate := 1000
	var samples := PackedFloat32Array()
	for _i in 4000:
		samples.append(0.0)
	for _i in 500:
		samples.append(0.05)
	for _i in 4000:
		samples.append(0.0)

	var average := SpellAudioUtilsScript.compute_rms(samples)
	var peak := SpellAudioUtilsScript.compute_peak_window_rms(samples, sample_rate)
	if peak < SpellAudioUtilsScript.MIN_SPEECH_RMS:
		push_error("Expected peak window RMS to detect the spoken segment")
		return 1
	if average >= SpellAudioUtilsScript.MIN_SPEECH_RMS:
		push_error("Expected average RMS to stay low when speech is padded with silence")
		return 1
	return 0


func _test_coaching_tip_for_long_cast() -> int:
	var result := CastValidationResultScript.fail("Rhythm was off")
	result.words_ok = true
	result.order_ok = true
	result.rhythm_score = 0.2
	result.audio_rms = 0.03
	result.audio_duration_sec = 1.4
	result.expected_duration_sec = 0.7
	result.incantation_text = "fireball"

	var tip: String = result.get_coaching_lines()[0]
	if not tip.contains("too long"):
		push_error("Expected long-cast coaching tip, got: %s" % tip)
		return 1
	return 0


func _test_coaching_tip_for_quiet_cast() -> int:
	var result := CastValidationResultScript.fail("Too quiet")
	result.audio_rms = 0.005
	result.incantation_text = "fireball"

	var tip: String = result.get_coaching_lines()[0]
	if not tip.to_lower().contains("quiet"):
		push_error("Expected quiet-cast coaching tip, got: %s" % tip)
		return 1
	return 0


func _test_easy_spell_passes_with_transcript() -> int:
	var spell := SpellDefinitionScript.new()
	spell.id = "fireball"
	spell.incantation_words = PackedStringArray(["fireball"])
	spell.require_rhythm = false

	var sample_rate := 44100
	var samples := PackedFloat32Array()
	for _i in 44100 * 2:
		samples.append(0.04)

	var result := SpellCastValidatorScript.validate(
		spell,
		samples,
		sample_rate,
		PackedStringArray(["fireball"]),
		PackedFloat32Array()
	)
	if not result.passed:
		push_error("Expected easy spell with transcript to pass, got: %s" % result.failure_reason)
		return 1
	return 0


func _test_free_cast_requires_transcript() -> int:
	var fireball := SpellDefinitionScript.new()
	fireball.id = "fireball"
	fireball.incantation_words = PackedStringArray(["fireball"])
	fireball.require_rhythm = false

	var samples := _loud_samples(0.3)
	var match: Dictionary = SpellCastValidatorScript.resolve_free_cast(
		[fireball],
		samples,
		44100,
		PackedStringArray(),
		PackedFloat32Array()
	)
	if match.get("spell") != null:
		push_error("Expected free cast without transcript to fail")
		return 1
	return 0


func _test_free_cast_identifies_single_word_spell() -> int:
	var fireball := SpellDefinitionScript.new()
	fireball.id = "fireball"
	fireball.incantation_words = PackedStringArray(["fireball"])
	fireball.require_rhythm = false

	var match: Dictionary = SpellCastValidatorScript.resolve_free_cast(
		[fireball],
		_loud_samples(0.3),
		44100,
		PackedStringArray(["fireball"]),
		PackedFloat32Array()
	)
	var spell := match.get("spell") as SpellDefinitionScript
	if spell == null or spell.id != "fireball":
		push_error("Expected free cast to identify fireball")
		return 1
	return 0


func _test_free_cast_identifies_two_word_spell() -> int:
	var spell := SpellDefinitionScript.new()
	spell.id = "speed_up"
	spell.incantation_words = PackedStringArray(["speed", "up"])
	spell.require_rhythm = false

	var match: Dictionary = SpellCastValidatorScript.resolve_free_cast(
		[spell],
		_loud_samples(0.3),
		44100,
		PackedStringArray(["speed", "up"]),
		PackedFloat32Array()
	)
	var matched := match.get("spell") as SpellDefinitionScript
	if matched == null or matched.id != "speed_up":
		push_error("Expected free cast to identify two-word spell")
		return 1
	return 0


func _test_free_cast_rejects_wrong_word_for_only_known_spell() -> int:
	var fireball := SpellDefinitionScript.new()
	fireball.id = "fireball"
	fireball.incantation_words = PackedStringArray(["fireball"])
	fireball.require_rhythm = false

	var match: Dictionary = SpellCastValidatorScript.resolve_free_cast(
		[fireball],
		_loud_samples(0.3),
		44100,
		PackedStringArray(["ward"]),
		PackedFloat32Array()
	)
	if match.get("spell") != null:
		push_error("Expected free cast to reject wrong word")
		return 1
	return 0


func _loud_samples(duration_sec: float, sample_rate: int = 44100) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for _i in int(sample_rate * duration_sec):
		samples.append(0.04)
	return samples
