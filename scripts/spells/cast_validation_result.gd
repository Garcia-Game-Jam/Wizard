class_name CastValidationResult
extends RefCounted

const MIN_SPEECH_RMS := 0.015

const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")
const IncantationMatcherScript := preload("res://scripts/spells/incantation_matcher.gd")

var passed: bool = false
var words_ok: bool = false
var order_ok: bool = false
var rhythm_score: float = 0.0
var tone_score: float = 0.0
var failure_reason: String = ""
var incantation_text: String = ""
var heard_text: String = ""
var audio_rms: float = 0.0
var audio_duration_sec: float = 0.0
var expected_duration_sec: float = 0.0
var detected_pitches_hz: PackedFloat32Array = PackedFloat32Array()
var target_pitches_hz: PackedFloat32Array = PackedFloat32Array()


static func fail(reason: String) -> CastValidationResult:
	var result := CastValidationResult.new()
	result.failure_reason = reason
	return result


static func success(
	p_words_ok: bool,
	p_order_ok: bool,
	p_rhythm: float,
	p_tone: float
) -> CastValidationResult:
	var result := CastValidationResult.new()
	result.passed = true
	result.words_ok = p_words_ok
	result.order_ok = p_order_ok
	result.rhythm_score = p_rhythm
	result.tone_score = p_tone
	return result


static func apply_transcript(
	result: CastValidationResult,
	transcript_words: PackedStringArray
) -> void:
	if result == null:
		return
	if transcript_words.is_empty():
		result.heard_text = "(no speech recognized)"
	else:
		result.heard_text = IncantationMatcherScript.heard_text_from_words(transcript_words)


func get_speech_match_line() -> String:
	var expected_display := incantation_text if not incantation_text.is_empty() else "?"
	var heard_display := heard_text if not heard_text.is_empty() else "(no speech recognized)"
	return 'Heard: "%s"  ·  Expected: "%s"' % [heard_display, expected_display]


func get_feedback_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if passed:
		lines.append("Success!")
		return lines

	lines.append(failure_reason)
	if not heard_text.is_empty() or not incantation_text.is_empty():
		lines.append(get_speech_match_line())
	lines.append(_audio_line())
	if not words_ok:
		lines.append("Words: not detected (speak the full incantation clearly)")
	elif not order_ok:
		lines.append("Words: detected but wrong order")
	else:
		lines.append("Words: OK")
	lines.append(
		"Rhythm: %d%% (heard %.2fs, aim ~%.2fs)"
		% [
			int(round(rhythm_score * 100.0)),
			audio_duration_sec,
			expected_duration_sec,
		]
	)
	lines.append("Tone: %d%%" % int(round(tone_score * 100.0)))
	if not detected_pitches_hz.is_empty() and not target_pitches_hz.is_empty():
		var pitch_parts: PackedStringArray = []
		for i in mini(detected_pitches_hz.size(), target_pitches_hz.size()):
			var detected_note := SpellDefinitionScript.hz_to_note_label(detected_pitches_hz[i])
			var target_note := SpellDefinitionScript.hz_to_note_label(target_pitches_hz[i])
			pitch_parts.append("%s→%s" % [detected_note, target_note])
		if not pitch_parts.is_empty():
			lines.append("Pitch heard→target: " + ", ".join(pitch_parts))
	return lines


func get_coaching_lines(for_tome: bool = false) -> PackedStringArray:
	var lines: PackedStringArray = []
	if passed:
		if for_tome:
			lines.append("You learned the spell!")
		else:
			lines.append("Success! You cast the spell.")
		if not heard_text.is_empty():
			lines.append(get_speech_match_line())
		return lines

	lines.append(_coaching_tip())
	if not heard_text.is_empty() or not incantation_text.is_empty():
		lines.append(get_speech_match_line())
	elif not incantation_text.is_empty():
		lines.append('Target: "%s" (~%.1fs)' % [incantation_text, expected_duration_sec])
	lines.append(_audio_coaching_line())
	if for_tome:
		lines.append("Press [F] to leave the tome.")
		lines.append("Retrying automatically...")
	else:
		lines.append("Press [F] to try again.")
	return lines


func _coaching_tip() -> String:
	var tip: String
	if audio_rms <= 0.0:
		tip = "No microphone input — press ESC, open Settings, and pick your mic."
	elif audio_rms < MIN_SPEECH_RMS:
		tip = "Too quiet — speak louder and closer. The mic bar should reach the middle."
	elif failure_reason.contains("Speech recognition") or failure_reason.contains("Vosk speech model"):
		tip = failure_reason
	elif not words_ok:
		if incantation_text.is_empty():
			tip = "We didn't hear speech — say the full incantation clearly."
		else:
			tip = 'Say the full word(s): "%s". Don\'t whisper.' % incantation_text
	elif not order_ok:
		tip = "Right words, wrong order — follow the incantation left to right."
	elif rhythm_score < 0.55:
		tip = _rhythm_coaching_tip()
	elif tone_score < 0.45 and not target_pitches_hz.is_empty():
		tip = "Pitch was off — try the pitch guide above."
	elif not failure_reason.is_empty():
		tip = failure_reason
	else:
		tip = "Try again — match the timing guide above."
	return tip


func _rhythm_coaching_tip() -> String:
	var expected: float = expected_duration_sec
	var heard: float = audio_duration_sec
	if expected <= 0.0:
		return "Rhythm was off — match the beat shown above."
	if heard > expected * 1.25:
		return "You held it too long — one crisp syllable (~%.1fs), then stop." % expected
	if heard < expected * 0.75:
		return "Too quick — stretch the word to about %.1fs." % expected
	return "Close on timing — aim for ~%.1fs total." % expected


func _audio_coaching_line() -> String:
	if audio_rms <= 0.0:
		return ""
	var level_pct: int = int(round(clampf(audio_rms / 0.08, 0.0, 1.0) * 100.0))
	return "Heard %.2fs at %d%% volume (rhythm %d%%)." % [
		audio_duration_sec,
		level_pct,
		int(round(rhythm_score * 100.0)),
	]


func _audio_line() -> String:
	if audio_rms <= 0.0:
		return "Audio: none captured — check mic in Settings"
	var heard := "yes" if audio_rms >= MIN_SPEECH_RMS else "too quiet"
	return "Audio: %s (level %.0f%%, %.2fs)" % [
		heard,
		int(round(clampf(audio_rms / 0.08, 0.0, 1.0) * 100.0)),
		audio_duration_sec,
	]
