class_name PlayerVoiceChrome
extends RefCounted

## Shared mute / speaking glyphs for lobby and settings player rows.

const BUTTON_SIZE := Vector2(28, 28)
const SPEAKER_IDLE := Color(0.72, 0.82, 0.92, 0.85)
const SPEAKER_ACTIVE := Color(0.45, 1.0, 0.62, 1.0)
const SPEAKER_MUTED := Color(0.55, 0.45, 0.55, 0.75)


static func style_voice_button(button: Button) -> void:
	if button == null or not is_instance_valid(button):
		return
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_constant_override("h_separation", 0)
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(0)
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(style_name, empty)


static func apply_voice_button(
	button: Button,
	muted: bool,
	speaking: bool,
	is_mic: bool
) -> void:
	if button == null or not is_instance_valid(button):
		return
	if muted:
		button.text = "🔇"
		button.modulate = SPEAKER_MUTED
	elif is_mic:
		button.text = "🎙️" if speaking else "🎤"
		button.modulate = SPEAKER_ACTIVE if speaking else SPEAKER_IDLE
	else:
		button.text = "🔊" if speaking else "🔈"
		button.modulate = SPEAKER_ACTIVE if speaking else SPEAKER_IDLE
	button.disabled = false
	if is_mic:
		button.tooltip_text = "Unmute microphone" if muted else "Mute microphone"
	else:
		button.tooltip_text = "Unmute this player" if muted else "Mute this player"
