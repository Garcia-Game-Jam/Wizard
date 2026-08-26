@tool
class_name LobbyPlayerRow
extends VBoxContainer

## One lobby / settings player: name, mute glyph, and a themed mix slider.

enum VoiceKind {
	MICROPHONE,
	PEER,
}

const PlayerVoiceChromeScript := preload("res://scripts/ui/player_voice_chrome.gd")

const _MIC_SLIDER_MAX := 2.0
const _PEER_SLIDER_MAX := 1.0

@export var player_name: String = "You":
	set(value):
		if value == player_name:
			return
		player_name = value
		_apply_chrome()

@export var detail_text: String = "":
	set(value):
		if value == detail_text:
			return
		detail_text = value
		_apply_chrome()

@export var voice_kind: VoiceKind = VoiceKind.MICROPHONE:
	set(value):
		if value == voice_kind:
			return
		voice_kind = value
		_apply_chrome()

@export var preview_muted: bool = false:
	set(value):
		if value == preview_muted:
			return
		preview_muted = value
		_apply_chrome()

@export var preview_speaking: bool = false:
	set(value):
		if value == preview_speaking:
			return
		preview_speaking = value
		_apply_chrome()

var _peer_id: int = -1
var _voice_button_styled := false

@onready var _name_label: Label = $IdentityRow/NameColumn/NameLabel
@onready var _detail_label: Label = $IdentityRow/NameColumn/DetailLabel
@onready var _voice_button: Button = $MixRow/VoiceButton
@onready var _volume_slider: HSlider = $MixRow/VolumeSlider


func _ready() -> void:
	if _voice_button != null and not _voice_button.pressed.is_connected(_on_voice_pressed):
		_voice_button.pressed.connect(_on_voice_pressed)
	if _volume_slider != null and not _volume_slider.value_changed.is_connected(_on_volume_changed):
		_volume_slider.value_changed.connect(_on_volume_changed)
	_apply_chrome()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _peer_id < 0:
		return
	if not is_visible_in_tree():
		return
	_refresh_voice_button()


func configure(
	peer_id: int,
	is_local: bool,
	display_name: String,
	detail: String = ""
) -> void:
	_peer_id = peer_id
	player_name = display_name
	detail_text = detail
	voice_kind = VoiceKind.MICROPHONE if is_local else VoiceKind.PEER
	if is_node_ready():
		_sync_slider_from_source()
		_refresh_voice_button()


func _apply_chrome() -> void:
	if not is_node_ready() or _volume_slider == null or _voice_button == null:
		return
	_name_label.text = player_name
	_detail_label.text = detail_text
	_detail_label.visible = not detail_text.is_empty()
	var is_mic := voice_kind == VoiceKind.MICROPHONE
	_voice_button.tooltip_text = (
		"Mute or unmute your microphone."
		if is_mic
		else "Mute or unmute this player."
	)
	_volume_slider.tooltip_text = (
		"How loud others hear you. Same dial as Audio settings."
		if is_mic
		else "How loud this player is in your headset."
	)
	_configure_slider_range(is_mic)
	_style_voice_button()
	if _peer_id >= 0 and not Engine.is_editor_hint():
		_sync_slider_from_source()
		_refresh_voice_button()
	else:
		PlayerVoiceChromeScript.apply_voice_button(
			_voice_button, preview_muted, preview_speaking, is_mic
		)


func _configure_slider_range(is_mic: bool) -> void:
	_volume_slider.max_value = _MIC_SLIDER_MAX if is_mic else _PEER_SLIDER_MAX
	_volume_slider.min_value = 0.0
	_volume_slider.step = 0.01
	_volume_slider.tick_count = 0


func _style_voice_button() -> void:
	if _voice_button_styled:
		return
	PlayerVoiceChromeScript.style_voice_button(_voice_button)
	_voice_button_styled = true


func _sync_slider_from_source() -> void:
	if _volume_slider == null or _peer_id < 0:
		return
	if voice_kind == VoiceKind.MICROPHONE:
		_volume_slider.set_value_no_signal(SettingsManager.mic_volume)
	else:
		_volume_slider.set_value_no_signal(SteamProximityVoiceHub.get_peer_volume(_peer_id))


func _refresh_voice_button() -> void:
	if _voice_button == null or _peer_id < 0:
		return
	var muted := SteamProximityVoiceHub.is_peer_muted(_peer_id)
	var speaking := (
		SteamProximityVoiceHub.is_active()
		and SteamProximityVoiceHub.is_peer_speaking(_peer_id)
	)
	PlayerVoiceChromeScript.apply_voice_button(
		_voice_button, muted, speaking, voice_kind == VoiceKind.MICROPHONE
	)


func _on_voice_pressed() -> void:
	if Engine.is_editor_hint() or _peer_id < 0:
		return
	SteamProximityVoiceHub.set_peer_muted(
		_peer_id, not SteamProximityVoiceHub.is_peer_muted(_peer_id)
	)
	_refresh_voice_button()


func _on_volume_changed(value: float) -> void:
	if Engine.is_editor_hint() or _peer_id < 0:
		return
	if voice_kind == VoiceKind.MICROPHONE:
		SettingsManager.mic_volume = clampf(value, 0.0, SettingsManager.MIC_VOLUME_MAX)
		SettingsManager.save_settings()
		return
	SteamProximityVoiceHub.set_peer_volume(_peer_id, clampf(value, 0.0, 1.0))
