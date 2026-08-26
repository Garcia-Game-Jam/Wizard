class_name VoiceSpellValidator
extends Node

## Match-scene entrypoint for voice spell casting (STT + validation).
##
## Scene hierarchy (authored under Match):
##   VoiceSpellValidator
##     SpellValidationRunner   # background STT + cast checks
##
## Call chain when the wand finishes listening:
##   SpellCastingSession._begin_validation()
##     → VoiceSpellValidator.start_validation(...)
##       → SpeechSttLoader (model ready)
##       → SpellValidationRunner (thread)
##         → GdvoskAdapter.transcribe + SpellCastValidator
##     ← validation_finished(payload)

signal validation_finished(payload: Dictionary)

const SpellSttConfigScript := preload("res://scripts/spells/spell_stt_config.gd")
const ValidationRunnerScript := preload("res://scripts/spells/spell_validation_runner.gd")

var _runner: SpellValidationRunner


func _ready() -> void:
	_ensure_runner()
	if Engine.is_editor_hint():
		return
	if not SettingsManager.settings_applied.is_connected(_on_settings_applied):
		SettingsManager.settings_applied.connect(_on_settings_applied)


func _exit_tree() -> void:
	if _runner != null and _runner.has_method("shutdown"):
		_runner.shutdown()


func apply_settings_from_manager() -> void:
	pass


func _on_settings_applied() -> void:
	pass


## Match bootstrap: wait until the speech model is ready.
func prepare_for_match() -> void:
	if SpeechSttLoader.is_loading():
		TomeDebug.log("VoiceSpellValidator", "Waiting for speech model to load...")
		await SpeechSttLoader.loading_finished
	elif not SpeechSttLoader.is_ready():
		SpeechSttLoader.ensure_ready()
		if SpeechSttLoader.is_loading():
			TomeDebug.log("VoiceSpellValidator", "Waiting for speech model to load...")
			await SpeechSttLoader.loading_finished
	if SpeechSttLoader.is_ready():
		TomeDebug.log("VoiceSpellValidator", "Speech STT ready")
	else:
		TomeDebug.log(
			"VoiceSpellValidator",
			"Speech STT unavailable: %s" % SpeechSttLoader.get_status()
		)


func get_stt_status() -> String:
	return SpeechSttLoader.get_status()


## Empty when STT is usable; otherwise a player-facing setup issue.
func get_runtime_stt_issue() -> String:
	return SpellSttConfigScript.get_runtime_issue()


func ensure_stt_ready() -> bool:
	return SpeechSttLoader.ensure_ready()


func is_validation_running() -> bool:
	return _runner != null and _runner.is_running()


## Start STT + spell validation on the background runner.
## Emits [signal validation_finished] when the worker completes.
func start_validation(
	mode: String,
	samples: PackedFloat32Array,
	sample_rate: int,
	target_spell: SpellDefinition,
	candidate_spells: Array[SpellDefinition],
	transcript_words: PackedStringArray,
	word_starts_sec: PackedFloat32Array,
	grammar_spells: Array[SpellDefinition] = []
) -> bool:
	_ensure_runner()
	if not ensure_stt_ready():
		TomeDebug.log(
			"VoiceSpellValidator",
			"speech STT not ready: %s" % get_stt_status()
		)
	var started := _runner.start(
		mode,
		samples,
		sample_rate,
		target_spell,
		candidate_spells,
		transcript_words,
		word_starts_sec,
		grammar_spells
	)
	if started:
		set_process(true)
	return started


func abort_validation() -> void:
	if _runner != null:
		_runner.abort()
	set_process(false)


## Drive the background runner when this node is outside a normal frame loop.
func poll_validation_progress() -> void:
	_ensure_runner()
	if _runner != null:
		_runner._process(0.0)


func _ensure_runner() -> void:
	if _runner != null and is_instance_valid(_runner):
		_wire_runner_signal()
		return
	_runner = get_node_or_null("SpellValidationRunner") as SpellValidationRunner
	if _runner == null:
		_runner = ValidationRunnerScript.new()
		_runner.name = "SpellValidationRunner"
		add_child(_runner)
	_wire_runner_signal()


func _wire_runner_signal() -> void:
	if _runner == null:
		return
	if not _runner.validation_finished.is_connected(_on_runner_finished):
		_runner.validation_finished.connect(_on_runner_finished)


func _on_runner_finished(payload: Dictionary) -> void:
	set_process(false)
	validation_finished.emit(payload)


func _process(_delta: float) -> void:
	if _runner == null:
		set_process(false)
		return
	_runner._process(0.0)
	if not _runner.is_running():
		set_process(false)
