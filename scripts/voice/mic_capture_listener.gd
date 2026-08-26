@tool
class_name MicCaptureListener
extends Node

## Declares one mic-capture consumer for a VoiceSession.
##
## Author under [code]VoiceSession/Listeners[/code]:
## - [enum Service.CHAT] — lobby/match voice chat
## - [enum Service.SPELLCASTING] — wand STT (match only)
##
## [GameVoiceSession] pre-registers each listener with [MicCaptureBroker] for the
## session lifetime. Services attach a short-lived PCM sink when they need audio
## (voice chat while active; wand only while listening).

enum Service { CHAT, SPELLCASTING }

const ProximityChatSettingsScript := preload("res://scripts/voice/proximity_chat_settings.gd")

@export var service: Service = Service.CHAT:
	set(value):
		service = value
		_sync_editor_name()
		notify_property_list_changed()

@export_group("Runtime status")
## True while this listener is registered with MicCaptureBroker.
@export var listening: bool = false
## PCM chunks received since last reset (telemetry).
@export var chunks_received: int = 0
## Last mono RMS from a fan-out chunk (0…~1).
@export var last_rms: float = 0.0

@export_group("Proximity chat")
## Chat only. Enable for match spatial voice; leave off for lobby open mic.
@export var proximity: Resource = ProximityChatSettingsScript.new()

## Optional consumer: Callable(mono: PackedFloat32Array, mix_rate: int).
var _pcm_sink: Callable = Callable()


func _ready() -> void:
	_ensure_proximity_resource()
	_sync_editor_name()


func _enter_tree() -> void:
	add_to_group("mic_capture_listener")


func get_subscriber_id() -> StringName:
	match service:
		Service.CHAT:
			return &"chat"
		Service.SPELLCASTING:
			return &"spellcasting"
		_:
			return &"unknown"


func is_chat() -> bool:
	return service == Service.CHAT


func is_spellcasting() -> bool:
	return service == Service.SPELLCASTING


func get_proximity_settings() -> Resource:
	if not is_chat():
		return null
	_ensure_proximity_resource()
	return proximity


func is_proximity_active() -> bool:
	var settings := get_proximity_settings()
	if settings == null:
		return false
	return bool(settings.call("is_active")) if settings.has_method("is_active") else bool(
		settings.get("enabled")
	)


## Broker fan-out entrypoint for this authored listener.
func forward_pcm(mono: PackedFloat32Array, mix_rate: int) -> void:
	_note_pcm(mono)
	if _pcm_sink.is_valid():
		_pcm_sink.call(mono, mix_rate)


func attach_sink(on_pcm: Callable) -> void:
	if not on_pcm.is_valid():
		push_error("MicCaptureListener '%s': refuse invalid PCM sink" % name)
		return
	_pcm_sink = on_pcm


func detach_sink() -> void:
	_pcm_sink = Callable()


func has_sink() -> bool:
	return _pcm_sink.is_valid()


func set_listening_state(active: bool) -> void:
	listening = active
	if not active:
		last_rms = 0.0
		detach_sink()


func reset_stats() -> void:
	chunks_received = 0
	last_rms = 0.0


func _note_pcm(mono: PackedFloat32Array) -> void:
	chunks_received += 1
	if mono.is_empty():
		last_rms = 0.0
		return
	var sum_sq := 0.0
	for sample in mono:
		sum_sq += sample * sample
	last_rms = sqrt(sum_sq / float(mono.size()))


func _ensure_proximity_resource() -> void:
	if proximity == null:
		proximity = ProximityChatSettingsScript.new()


func _sync_editor_name() -> void:
	if not Engine.is_editor_hint():
		return
	if name == "Node" or name == "MicCaptureListener" or name.is_empty():
		match service:
			Service.CHAT:
				name = "Chat"
			Service.SPELLCASTING:
				name = "Spellcasting"


func _validate_property(property: Dictionary) -> void:
	if property.name in ["listening", "chunks_received", "last_rms"]:
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	if property.name == "proximity" and service != Service.CHAT:
		property.usage = PROPERTY_USAGE_STORAGE
