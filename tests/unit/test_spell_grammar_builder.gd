extends RefCounted

const SpellGrammarBuilderScript := preload("res://scripts/spells/spell_grammar_builder.gd")


func run() -> int:
	var failures := 0
	failures += _test_build_phrases_empty()
	failures += _test_build_phrases_and_unk()
	failures += _test_build_phrases_dedupes()
	failures += _test_build_phrases_from_spell_dicts()
	failures += _test_build_json_matches_phrases()
	return failures


func _test_build_phrases_empty() -> int:
	var phrases := SpellGrammarBuilderScript.build_phrases([])
	if not phrases.is_empty():
		push_error("Expected empty grammar for no phrases, got: %s" % phrases)
		return 1
	if SpellGrammarBuilderScript.build_json([]) != "":
		push_error("Expected empty JSON for no phrases")
		return 1
	return 0


func _test_build_phrases_and_unk() -> int:
	var phrases := SpellGrammarBuilderScript.build_phrases(["light ball", "speed up"])
	if phrases.size() != 3:
		push_error("Expected 2 phrases plus [unk], got: %s" % phrases)
		return 1
	if phrases[0] != "light ball" or phrases[1] != "speed up" or phrases[2] != "[unk]":
		push_error("Unexpected grammar phrases: %s" % phrases)
		return 1
	return 0


func _test_build_phrases_dedupes() -> int:
	var phrases := SpellGrammarBuilderScript.build_phrases(["Light Ball", "light ball"])
	if phrases.size() != 2:
		push_error("Expected deduped phrase plus [unk], got: %s" % phrases)
		return 1
	return 0


func _test_build_phrases_from_spell_dicts() -> int:
	var spells: Array = [
		{"incantation_words": ["fireball"]},
		{"incantation_words": ["light", "ball"]},
	]
	var phrases := SpellGrammarBuilderScript.build_phrases_from_spell_dicts(spells)
	if phrases.size() != 3:
		push_error("Expected spell dict phrases plus [unk], got: %s" % phrases)
		return 1
	if phrases[0] != "fireball" or phrases[1] != "light ball":
		push_error("Unexpected spell dict grammar: %s" % phrases)
		return 1
	return 0


func _test_build_json_matches_phrases() -> int:
	var phrases := SpellGrammarBuilderScript.build_phrases(["light ball", "speed up"])
	var parsed: Variant = JSON.parse_string(
		SpellGrammarBuilderScript.build_json_from_phrases(phrases)
	)
	if not parsed is Array:
		push_error("Expected grammar JSON array")
		return 1
	var as_array: Array = parsed
	if as_array.size() != phrases.size():
		push_error("JSON size mismatch: %s vs %s" % [as_array, phrases])
		return 1
	return 0
