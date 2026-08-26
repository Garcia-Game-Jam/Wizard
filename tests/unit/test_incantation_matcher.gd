extends RefCounted

const IncantationMatcherScript := preload("res://scripts/spells/incantation_matcher.gd")
const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")


func run() -> int:
	var failures := 0
	failures += _test_exact_match_fireball()
	failures += _test_exact_match_multi_word()
	failures += _test_rejects_wrong_word()
	failures += _test_fuzzy_match_typo()
	failures += _test_heard_text_contains_incantation()
	failures += _test_compound_single_word_fireball()
	failures += _test_light_and_light_ball_phrases()
	failures += _test_stt_confusable_like_for_light()
	failures += _test_white_ball_is_light_ball_not_fireball()
	failures += _test_rejects_short_substring_false_positive()
	return failures


func _make_spell(id: String, words: Array[String]) -> SpellDefinitionScript:
	var spell := SpellDefinitionScript.new()
	spell.id = id
	spell.incantation_words = PackedStringArray(words)
	return spell


func _test_exact_match_fireball() -> int:
	var fireball := _make_spell("fireball", ["fireball"])
	if not IncantationMatcherScript.matches(PackedStringArray(["fireball"]), fireball):
		push_error("Expected exact match for fireball")
		return 1
	return 0


func _test_exact_match_multi_word() -> int:
	var haste := _make_spell("haste", ["speed", "up"])
	if not IncantationMatcherScript.matches(
		PackedStringArray(["speed", "up"]), haste
	):
		push_error("Expected exact match for speed up")
		return 1
	return 0


func _test_rejects_wrong_word() -> int:
	var fireball := _make_spell("fireball", ["fireball"])
	if IncantationMatcherScript.matches(PackedStringArray(["haste"]), fireball):
		push_error("Expected haste to not match fireball")
		return 1
	return 0


func _test_fuzzy_match_typo() -> int:
	var haste := _make_spell("haste", ["speed", "up"])
	if not IncantationMatcherScript.matches(PackedStringArray(["speak", "up"]), haste):
		push_error("Expected fuzzy match for speak up -> speed up")
		return 1
	return 0


func _test_heard_text_contains_incantation() -> int:
	var haste := _make_spell("haste", ["speed", "up"])
	if not IncantationMatcherScript.matches(
		PackedStringArray(["well", "speed", "up", "now"]), haste
	):
		push_error("Expected phrase containing speed up to match haste")
		return 1
	return 0


func _test_compound_single_word_fireball() -> int:
	var fireball := _make_spell("fireball", ["fireball"])
	if not IncantationMatcherScript.matches(
		PackedStringArray(["fire", "ball"]), fireball
	):
		push_error("Expected 'fire ball' transcript to match fireball")
		return 1
	return 0


func _test_light_and_light_ball_phrases() -> int:
	var light := _make_spell("light", ["light"])
	var light_ball := _make_spell("light_ball", ["light", "ball"])
	if not IncantationMatcherScript.matches(PackedStringArray(["light"]), light):
		push_error("Expected exact match for light")
		return 1
	if not IncantationMatcherScript.matches(PackedStringArray(["light", "ball"]), light_ball):
		push_error("Expected exact match for light ball")
		return 1
	if IncantationMatcherScript.matches(PackedStringArray(["light"]), light_ball):
		push_error("Expected bare light to not match light ball")
		return 1
	if not IncantationMatcherScript.matches(PackedStringArray(["light", "ball"]), light):
		push_error("Expected light ball transcript to still contain light")
		return 1
	return 0


func _test_stt_confusable_like_for_light() -> int:
	var light := _make_spell("light", ["light"])
	var light_ball := _make_spell("light_ball", ["light", "ball"])
	if not IncantationMatcherScript.matches(PackedStringArray(["like"]), light):
		push_error("Expected STT 'like' to match light")
		return 1
	if not IncantationMatcherScript.matches(PackedStringArray(["like", "ball"]), light_ball):
		push_error("Expected STT 'like ball' to match light ball")
		return 1
	if IncantationMatcherScript.matches(PackedStringArray(["ladder"]), light):
		push_error("Expected unrelated word not to match light")
		return 1
	return 0


func _test_white_ball_is_light_ball_not_fireball() -> int:
	var light := _make_spell("light", ["light"])
	var light_ball := _make_spell("light_ball", ["light", "ball"])
	var fireball := _make_spell("fireball", ["fireball"])
	var heard := PackedStringArray(["white", "ball"])
	if not IncantationMatcherScript.matches(heard, light_ball):
		push_error("Expected STT 'white ball' to match light ball")
		return 1
	if not IncantationMatcherScript.matches(PackedStringArray(["white"]), light):
		push_error("Expected STT 'white' to match light")
		return 1
	if IncantationMatcherScript.matches(heard, fireball):
		push_error("Expected STT 'white ball' not to match fireball")
		return 1
	return 0


func _test_rejects_short_substring_false_positive() -> int:
	var light := _make_spell("light", ["light"])
	if IncantationMatcherScript.matches(PackedStringArray(["li"]), light):
		push_error("Expected short substring 'li' not to match light")
		return 1
	return 0
