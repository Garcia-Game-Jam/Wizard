class_name IncantationMatcher
extends RefCounted

## Matches speech-to-text transcripts against spell incantations.

## Common STT near-misses keyed by the expected spell word.
## Keep these tight — only pairs that players actually hit in-game.
const STT_CONFUSABLES := {
	"light": ["like", "lite", "lights", "white"],
	"ball": ["bowl", "bald", "boll"],
	"speed": ["speak", "steed"],
	"fireball": ["firebal", "firball"],
	"flare": ["flair", "flares", "fair"],
	"dispell": ["dispel", "dispelled", "disperse"],
	"dispel": ["dispell", "dispelled", "disperse"],
	"clone": ["cloned", "cloning"],
}


static func matches(
	transcript_words: PackedStringArray,
	spell: SpellDefinition
) -> bool:
	if spell == null:
		return false
	return matches_incantation_words(transcript_words, spell.incantation_words)


static func matches_incantation_words(
	transcript_words: PackedStringArray,
	incantation_words: PackedStringArray
) -> bool:
	if transcript_words.is_empty() or incantation_words.is_empty():
		return false
	if _exact_word_sequence(transcript_words, incantation_words):
		return true

	var heard_text := heard_text_from_words(transcript_words)
	var expected_text := " ".join(incantation_words).to_lower()
	if heard_text.contains(expected_text):
		return true

	if incantation_words.size() == 1:
		if _matches_compound_single_word(
			transcript_words, incantation_words[0]
		):
			return true

	return _fuzzy_word_sequence(transcript_words, incantation_words)


static func _matches_compound_single_word(
	transcript_words: PackedStringArray,
	expected_word: String
) -> bool:
	var expected := expected_word.to_lower().strip_edges()
	if expected.is_empty():
		return false

	var normalized: Array[String] = []
	for word in transcript_words:
		var cleaned := word.to_lower().strip_edges()
		if not cleaned.is_empty():
			normalized.append(cleaned)
	if normalized.is_empty():
		return false

	# Single heard token: allow fuzzy / confusable match against the compound.
	if normalized.size() == 1:
		return _word_similar(normalized[0], expected)

	# Multi-token joins ("fire ball" → fireball). Require prefix + suffix
	# alignment so "white ball" does not fuzzy-match fireball via edit distance.
	for start_idx in normalized.size():
		var built := ""
		for end_idx in range(start_idx, normalized.size()):
			built += normalized[end_idx]
			if built == expected or _is_stt_confusable(built, expected):
				return true
			if end_idx > start_idx and _compound_tokens_align(
				normalized[start_idx],
				normalized[end_idx],
				expected
			):
				return true
			if built.length() > expected.length() + 2:
				break
	return false


static func _compound_tokens_align(first: String, last: String, expected: String) -> bool:
	if first.is_empty() or last.is_empty() or expected.is_empty():
		return false
	var suffix_len := mini(last.length(), expected.length())
	if suffix_len < 3:
		return false
	var suffix := expected.substr(expected.length() - suffix_len)
	if not _word_similar(last, suffix):
		return false
	var prefix_len := mini(first.length(), expected.length())
	if prefix_len < 3:
		return false
	var prefix := expected.substr(0, prefix_len)
	return _word_similar(first, prefix)


static func heard_text_from_words(transcript_words: PackedStringArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for word in transcript_words:
		var cleaned := word.to_lower().strip_edges()
		if not cleaned.is_empty():
			parts.append(cleaned)
	return " ".join(parts)


static func _exact_word_sequence(
	detected: PackedStringArray,
	expected: PackedStringArray
) -> bool:
	if detected.size() < expected.size():
		return false

	var normalized_expected: Array[String] = []
	for word in expected:
		normalized_expected.append(word.to_lower().strip_edges())

	var normalized_detected: Array[String] = []
	for word in detected:
		normalized_detected.append(word.to_lower().strip_edges())

	var start := 0
	while start < normalized_detected.size() and normalized_detected[start].is_empty():
		start += 1

	for i in expected.size():
		var idx := start + i
		if idx >= normalized_detected.size():
			return false
		if normalized_detected[idx] != normalized_expected[i]:
			return false
	return true


static func _fuzzy_word_sequence(
	transcript_words: PackedStringArray,
	expected_words: PackedStringArray
) -> bool:
	var normalized_detected: Array[String] = []
	for word in transcript_words:
		var cleaned := word.to_lower().strip_edges()
		if not cleaned.is_empty():
			normalized_detected.append(cleaned)

	var scan_idx := 0
	for expected_word in expected_words:
		var target := expected_word.to_lower()
		var found := false
		while scan_idx < normalized_detected.size():
			if _word_similar(normalized_detected[scan_idx], target):
				found = true
				scan_idx += 1
				break
			scan_idx += 1
		if not found:
			return false
	return true


static func _word_similar(detected: String, expected: String) -> bool:
	if detected.is_empty() or expected.is_empty():
		return false
	var left := detected.to_lower().strip_edges()
	var right := expected.to_lower().strip_edges()
	if left.is_empty() or right.is_empty():
		return false
	if left == right:
		return true
	if _is_stt_confusable(left, right):
		return true

	# Substring only when both sides are substantial (avoid "li" ⊂ "light").
	var min_len := mini(left.length(), right.length())
	var max_len := maxi(left.length(), right.length())
	if (
		min_len >= 3
		and float(min_len) / float(max_len) >= 0.75
		and (left.contains(right) or right.contains(left))
	):
		return true

	# Reject wildly different lengths before edit-distance forgiveness.
	if absi(left.length() - right.length()) > 2:
		return false
	# Slightly looser than before (len/3 vs len/4) for short STT typos.
	var max_distance: int = maxi(1, int(ceil(float(right.length()) / 3.0)))
	max_distance = mini(max_distance, 3)
	return _edit_distance(left, right) <= max_distance


static func _is_stt_confusable(detected: String, expected: String) -> bool:
	if STT_CONFUSABLES.has(expected):
		if detected in STT_CONFUSABLES[expected]:
			return true
	if STT_CONFUSABLES.has(detected):
		if expected in STT_CONFUSABLES[detected]:
			return true
	return false


static func _edit_distance(a: String, b: String) -> int:
	var m: int = a.length()
	var n: int = b.length()
	if m == 0:
		return n
	if n == 0:
		return m

	var dp: Array = []
	for _i in m + 1:
		var row: Array = []
		row.resize(n + 1)
		dp.append(row)

	for j in n + 1:
		dp[0][j] = j
	for i in range(1, m + 1):
		dp[i][0] = i
		for j in range(1, n + 1):
			var cost: int = 0 if a[i - 1] == b[j - 1] else 1
			dp[i][j] = mini(
				mini(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
				dp[i - 1][j - 1] + cost
			)
	return dp[m][n]
