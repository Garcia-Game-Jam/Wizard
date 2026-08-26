class_name SpellValidationRunner
extends Node

## Runs STT + spell validation on a background thread.
## Emits validation_finished on the main thread when work completes.

signal validation_finished(payload: Dictionary)

const CodecScript := preload("res://scripts/spells/spell_validation_codec.gd")
const SpellAudioUtilsScript := preload("res://scripts/spells/spell_audio_utils.gd")
const WorkerScript := preload("res://scripts/spells/spell_validation_worker.gd")

var _payload: Dictionary = {}
var _finished := false
var _pending := false
var _thread: Thread
var _generation: int = 0
var _active_generation: int = -1


func _ready() -> void:
	set_process(false)


func is_running() -> bool:
	return _pending


func is_finished() -> bool:
	return _finished


func get_payload() -> Dictionary:
	return _payload


func start(
	mode: String,
	samples: PackedFloat32Array,
	sample_rate: int,
	target_spell: SpellDefinition,
	candidate_spells: Array[SpellDefinition],
	transcript_words: PackedStringArray,
	word_starts_sec: PackedFloat32Array,
	grammar_spells: Array[SpellDefinition] = []
) -> bool:
	abort()
	_finished = false
	_payload = {}

	var grammar_source: Array = grammar_spells
	if grammar_source.is_empty():
		if mode == "free_cast":
			grammar_source = candidate_spells
		elif target_spell != null:
			grammar_source = [target_spell]

	var trimmed := SpellAudioUtilsScript.extract_speech_samples(samples, sample_rate)
	var work := {
		"mode": mode,
		"samples": samples.duplicate(),
		"trimmed": trimmed,
		"sample_rate": sample_rate,
		"spell": CodecScript.spell_to_dict(target_spell),
		"candidates": CodecScript.spells_to_dict_array(candidate_spells),
		"grammar_spells": CodecScript.spells_to_dict_array(grammar_source),
		"transcript_words": CodecScript.array_from_strings(transcript_words),
		"word_starts_sec": CodecScript.array_from_floats(word_starts_sec),
	}

	_generation += 1
	_active_generation = _generation
	_pending = true
	_thread = Thread.new()
	if _thread.start(_run_worker.bind(work, _active_generation)) != OK:
		_thread = null
		_pending = false
		_active_generation = -1
		set_process(false)
		return false
	set_process(true)
	return true


func abort() -> void:
	_generation += 1
	_pending = false
	_finished = false
	_payload = {}
	_active_generation = -1
	set_process(false)
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func shutdown() -> void:
	_generation += 1
	_pending = false
	_active_generation = -1
	set_process(false)
	if _thread == null:
		return
	_thread.wait_to_finish()
	_thread = null


func _exit_tree() -> void:
	shutdown()


func _process(_delta: float) -> void:
	_collect_thread_result()


func _collect_thread_result() -> void:
	if _thread == null:
		set_process(false)
		return
	if _thread.is_alive():
		return

	var payload: Variant = _thread.wait_to_finish()
	_thread = null

	var should_emit := _pending
	_pending = false

	if not should_emit:
		set_process(false)
		return

	if payload is Dictionary and int(payload.get("generation", -1)) != _active_generation:
		set_process(false)
		return

	if payload is Dictionary:
		payload = payload.duplicate()
		payload.erase("generation")
		_payload = payload
		_finished = true
		set_process(false)
		validation_finished.emit(_payload)
	else:
		set_process(false)


static func _run_worker(work: Dictionary, generation: int) -> Dictionary:
	var result: Dictionary = WorkerScript.run(work)
	result["generation"] = generation
	return result
