class_name SpellGrammarBuilder
extends RefCounted

## Builds Vosk grammar phrases for a small spell vocabulary.
## gdvosk expects PackedStringArray via VoskRecognizer.setup_with_grammar.


static func build_phrases_from_spell_dicts(spell_dicts: Array) -> PackedStringArray:
	var phrases: Array[String] = []
	for item in spell_dicts:
		if item is Dictionary:
			var words: Variant = item.get("incantation_words", [])
			if words is Array:
				phrases.append(" ".join(PackedStringArray(words)))
			elif words is PackedStringArray:
				phrases.append(" ".join(words))
	return build_phrases(phrases)


static func build_phrases(phrases: Array) -> PackedStringArray:
	var unique: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for phrase in phrases:
		var text := str(phrase).strip_edges().to_lower()
		if text.is_empty() or seen.has(text):
			continue
		seen[text] = true
		unique.append(text)
	if unique.is_empty():
		return PackedStringArray()
	unique.append("[unk]")
	return unique


static func build_json_from_spell_dicts(spell_dicts: Array) -> String:
	return build_json_from_phrases(build_phrases_from_spell_dicts(spell_dicts))


static func build_json(phrases: Array) -> String:
	return build_json_from_phrases(build_phrases(phrases))


static func build_json_from_phrases(phrases: PackedStringArray) -> String:
	if phrases.is_empty():
		return ""
	var as_array: Array = []
	for phrase in phrases:
		as_array.append(phrase)
	return JSON.stringify(as_array)
