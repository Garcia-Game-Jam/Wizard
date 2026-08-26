class_name SpellValidationWorker
extends RefCounted

## Thread-safe spell validation entry point. Only plain data crosses thread boundaries.

const CodecScript := preload("res://scripts/spells/spell_validation_codec.gd")
const GdvoskAdapterScript := preload("res://scripts/spells/gdvosk_adapter.gd")
const SpellCastValidatorScript := preload("res://scripts/spells/spell_cast_validator.gd")
const SpellGrammarBuilderScript := preload("res://scripts/spells/spell_grammar_builder.gd")
const SpellLogScript := preload("res://scripts/spells/spell_log.gd")
const TestEnvScript := preload("res://scripts/test/test_env.gd")

## Test hook: artificial delay inside the worker thread.
static var test_delay_sec: float = 0.0
## When FRIEND_SLOP_TEST=1, skip live STT unless a test sets this true.
static var force_stt_in_tests: bool = false
static var last_ran_on_main_thread: bool = true


static func run(work: Dictionary) -> Dictionary:
	last_ran_on_main_thread = Thread.is_main_thread()
	if test_delay_sec > 0.0:
		OS.delay_usec(int(test_delay_sec * 1_000_000.0))

	var transcript_words := CodecScript.packed_strings_from_array(
		work.get("transcript_words", [])
	)
	var word_starts_sec := CodecScript.packed_floats_from_array(
		work.get("word_starts_sec", [])
	)
	var samples: PackedFloat32Array = work.get("trimmed", PackedFloat32Array())
	var raw_samples: PackedFloat32Array = work.get("samples", PackedFloat32Array())
	var sample_rate: int = int(work.get("sample_rate", 0))

	if transcript_words.is_empty():
		var should_transcribe := not TestEnvScript.is_active() or force_stt_in_tests
		if not should_transcribe:
			SpellLogScript.debug(
				"CastSession",
				"skipping live STT in unit tests (samples=%d trimmed=%d rate=%d)"
				% [raw_samples.size(), samples.size(), sample_rate]
			)
		if should_transcribe:
			var grammar_phrases := _grammar_phrases_for_work(work)
			var stt := _transcribe_for_validation(
				raw_samples, samples, sample_rate, grammar_phrases
			)
			var words: Variant = stt.get("words")
			var starts: Variant = stt.get("starts")
			if words is PackedStringArray:
				transcript_words = words
			if starts is PackedFloat32Array:
				word_starts_sec = starts
			if transcript_words.is_empty():
				SpellLogScript.debug(
					"CastSession",
					"stt returned no words (samples=%d trimmed=%d rate=%d model_loaded=%s grammar=%s)"
					% [
						raw_samples.size(),
						samples.size(),
						sample_rate,
						str(GdvoskAdapterScript.is_model_loaded()),
						not grammar_phrases.is_empty(),
					]
				)
			else:
				SpellLogScript.debug(
					"CastSession",
					'stt transcript="%s" grammar=%s'
					% [" ".join(transcript_words), not grammar_phrases.is_empty()]
				)

	if str(work.get("mode", "")) == "free_cast":
		return _build_free_cast_response(
			work.get("candidates", []),
			samples,
			sample_rate,
			transcript_words,
			word_starts_sec
		)

	return _build_targeted_response(
		work.get("spell", {}),
		samples,
		sample_rate,
		transcript_words,
		word_starts_sec
	)


static func _grammar_phrases_for_work(work: Dictionary) -> PackedStringArray:
	var spell_dicts: Array = work.get("grammar_spells", [])
	if spell_dicts.is_empty():
		if str(work.get("mode", "")) == "free_cast":
			spell_dicts = work.get("candidates", [])
		else:
			var spell: Variant = work.get("spell", {})
			if spell is Dictionary and not spell.is_empty():
				spell_dicts = [spell]
	return SpellGrammarBuilderScript.build_phrases_from_spell_dicts(spell_dicts)


static func _transcribe_for_validation(
	samples: PackedFloat32Array,
	trimmed: PackedFloat32Array,
	sample_rate: int,
	grammar_phrases: PackedStringArray
) -> Dictionary:
	var stt := GdvoskAdapterScript.transcribe_samples(
		samples, sample_rate, grammar_phrases
	)
	var words: Variant = stt.get("words")
	if words is PackedStringArray and not words.is_empty():
		return stt
	if trimmed.is_empty() or trimmed.size() == samples.size():
		return stt
	return GdvoskAdapterScript.transcribe_samples(trimmed, sample_rate, grammar_phrases)


static func _build_targeted_response(
	spell_data: Dictionary,
	samples: PackedFloat32Array,
	sample_rate: int,
	transcript_words: PackedStringArray,
	word_starts_sec: PackedFloat32Array
) -> Dictionary:
	if spell_data.is_empty():
		return {"ok": false, "error": "No spell in request"}

	var result := SpellCastValidatorScript.validate_spell_dict(
		spell_data, samples, sample_rate, transcript_words, word_starts_sec
	)
	return _success_payload(
		str(spell_data.get("id", "")),
		result,
		transcript_words,
		word_starts_sec
	)


static func _build_free_cast_response(
	candidate_data: Array,
	samples: PackedFloat32Array,
	sample_rate: int,
	transcript_words: PackedStringArray,
	word_starts_sec: PackedFloat32Array
) -> Dictionary:
	var match: Dictionary = SpellCastValidatorScript.resolve_free_cast_dict(
		candidate_data,
		samples,
		sample_rate,
		transcript_words,
		word_starts_sec
	)
	var matched: Variant = match.get("spell")
	var result: CastValidationResult = match.get("result")
	var debug_lines: PackedStringArray = match.get("debug_lines", PackedStringArray())
	var spell_id := ""
	if matched is Dictionary:
		spell_id = str(matched.get("id", ""))
	return _success_payload(
		spell_id,
		result,
		transcript_words,
		word_starts_sec,
		CodecScript.array_from_strings(debug_lines)
	)


static func _success_payload(
	spell_id: String,
	result: CastValidationResult,
	transcript_words: PackedStringArray,
	word_starts_sec: PackedFloat32Array,
	debug_lines: Array = []
) -> Dictionary:
	return {
		"ok": true,
		"spell_id": spell_id,
		"result": CodecScript.result_to_dict(result),
		"transcript_words": CodecScript.array_from_strings(transcript_words),
		"word_starts_sec": CodecScript.array_from_floats(word_starts_sec),
		"debug_lines": debug_lines,
	}
