class_name SpellCastingSession
extends Node

signal cast_succeeded(spell: SpellDefinition, mode: String, validation: CastValidationResult)
signal cast_failed(spell: SpellDefinition, reason: String, partial: CastValidationResult)
signal spell_selected(spell: SpellDefinition)
signal state_changed(state: String, spell: SpellDefinition)
signal listen_level_changed(level: float)
signal listen_coaching_changed(message: String)
signal tome_teaching_changed(active: bool, spell: SpellDefinition)
signal tome_retry_tick(seconds_left: float)

enum Mode { LEARN, CAST }

const VoiceCaptureWorkerScript := preload("res://scripts/spells/voice_capture_worker.gd")

const STATE_IDLE := "idle"
const STATE_ARMING := "arming"
const STATE_LISTENING := "listening"
const STATE_VALIDATING := "validating"
const STATE_COACHING := "coaching"

const ARMING_SEC := 0.1
const MAX_LISTEN_SEC := 5.0
## Open-ended while wand is raised; silence still commits a recognition pass.
const WAND_SELECT_MAX_LISTEN_SEC := 120.0
const TRAILING_SILENCE_SEC := 0.15
const MIN_LISTEN_BEFORE_END_SEC := 0.25
const TOME_RETRY_SEC := 2.0

var _state: String = STATE_IDLE
var _mode: Mode = Mode.CAST
var _spell: SpellDefinition
var _tome_teaching := false
var _tome_spell: SpellDefinition
var _coaching_retry_left: float = 0.0
## Match VoiceSpellValidator — STT + validation entrypoint (not owned by this node).
var _validator: VoiceSpellValidator
var _spell_loadout: Node
var _arming_left: float = 0.0
var _listen_left: float = 0.0
var _listen_elapsed: float = 0.0
var _speech_detected := false
var _silence_after_speech: float = 0.0
var _recorded_samples: PackedFloat32Array = PackedFloat32Array()
var _sample_rate: int = 44100
var _transcript_words: PackedStringArray = PackedStringArray()
var _word_starts_sec: PackedFloat32Array = PackedFloat32Array()
var _free_cast := false
var _wand_voice_select := false
var _free_cast_candidates: Array[SpellDefinition] = []
var _free_cast_debug_lines: PackedStringArray = PackedStringArray()
var _capture_worker: VoiceCaptureWorker
## True while Match Listeners/Spellcasting sink feeds STT.
var _using_broker := false


func _ready() -> void:
	## Nested spawn-slot / gallery placeholders must not touch mic or worker threads.
	if _is_character_preview_placeholder():
		set_process(false)
		set_physics_process(false)
		return
	_capture_worker = VoiceCaptureWorkerScript.new()
	if _is_local_simulation():
		_sample_rate = int(AudioServer.get_mix_rate())


func _is_character_preview_placeholder() -> bool:
	## Nested under spawn slots or gallery/workspace — not a live player.
	var node: Node = get_parent()
	while node != null:
		if node.is_in_group("player_spawn_slot"):
			return true
		node = node.get_parent()
	if is_inside_tree():
		var scene := get_tree().current_scene
		if scene != null and scene.has_meta("character_preview_scene"):
			return true
	return false


func configure(validator: VoiceSpellValidator, spell_loadout: Node = null) -> void:
	if (
		_validator != null
		and _validator.validation_finished.is_connected(_on_validation_finished)
	):
		_validator.validation_finished.disconnect(_on_validation_finished)
	_validator = validator
	_spell_loadout = spell_loadout
	if (
		_validator != null
		and not _validator.validation_finished.is_connected(_on_validation_finished)
	):
		_validator.validation_finished.connect(_on_validation_finished)


func poll_validation_progress() -> void:
	if _validator != null and _validator.has_method("poll_validation_progress"):
		_validator.poll_validation_progress()


func is_free_cast() -> bool:
	return _free_cast


func is_wand_voice_select() -> bool:
	return _wand_voice_select


func is_active() -> bool:
	return _state != STATE_IDLE and _state != STATE_COACHING


func is_tome_teaching() -> bool:
	return _tome_teaching


func is_between_attempts() -> bool:
	return _tome_teaching and _state == STATE_COACHING


func is_validating() -> bool:
	return _state == STATE_VALIDATING


func get_state() -> String:
	return _state


func get_tome_spell() -> SpellDefinition:
	return _tome_spell if _tome_teaching else null


func get_active_spell() -> SpellDefinition:
	return _spell if _spell != null else _tome_spell


func start(spell: SpellDefinition, mode: Mode) -> void:
	if spell == null:
		TomeDebug.log("CastSession", "start aborted: spell is null")
		return
	if _tome_teaching:
		end_tome_teaching()
	if _state != STATE_IDLE:
		TomeDebug.log(
			"CastSession",
			"start aborted: not idle (state=%s)" % _state
		)
		return
	var mode_name := "LEARN" if mode == Mode.LEARN else "CAST"
	TomeDebug.log(
		"CastSession",
		"start mode=%s spell='%s'"
		% [
			mode_name,
			spell.id,
		]
	)
	_tome_teaching = false
	_tome_spell = null
	_free_cast = false
	_wand_voice_select = false
	_free_cast_candidates = []
	_begin_attempt(spell, mode)


func start_free_cast(candidates: Array[SpellDefinition]) -> void:
	## Legacy hold-to-cast path; prefer [method start_wand_voice_select].
	_start_open_mic_cast(candidates, false)


func start_wand_voice_select(candidates: Array[SpellDefinition]) -> void:
	## Raised-wand listen: first matched known spell emits [signal spell_selected].
	_start_open_mic_cast(candidates, true)


func _start_open_mic_cast(candidates: Array[SpellDefinition], wand_select: bool) -> void:
	## Prefer caller filter (e.g. cooldown / target gates); fall back to full loadout.
	var known_spells: Array[SpellDefinition] = candidates.duplicate()
	if known_spells.is_empty():
		known_spells = _known_spells_for_player()
	if known_spells.is_empty():
		TomeDebug.log("CastSession", "open mic cast aborted: no candidates")
		return
	if _tome_teaching:
		end_tome_teaching()
	if _state != STATE_IDLE:
		TomeDebug.log(
			"CastSession",
			"open mic cast aborted: not idle (state=%s)" % _state
		)
		return
	_free_cast = true
	_wand_voice_select = wand_select
	_free_cast_candidates = known_spells
	_mode = Mode.CAST
	_spell = null
	TomeDebug.log(
		"CastSession",
		"start %s (%d spells known)"
		% ["wand voice select" if wand_select else "free cast", _free_cast_candidates.size()]
	)
	_recorded_samples = PackedFloat32Array()
	_transcript_words = PackedStringArray()
	_word_starts_sec = PackedFloat32Array()
	_speech_detected = false
	_silence_after_speech = 0.0
	_listen_elapsed = 0.0
	_coaching_retry_left = 0.0
	_set_state(STATE_ARMING)
	_arming_left = ARMING_SEC


func begin_tome_teaching(spell: SpellDefinition) -> void:
	if spell == null:
		return
	if _tome_teaching and _tome_spell != null and _tome_spell.id == spell.id:
		return
	if _state != STATE_IDLE:
		end_tome_teaching()
	_free_cast = false
	_free_cast_candidates = []
	_tome_teaching = true
	_tome_spell = spell
	_mode = Mode.LEARN
	TomeDebug.log("CastSession", "begin tome teaching for '%s'" % spell.id)
	tome_teaching_changed.emit(true, spell)
	_begin_attempt(spell, Mode.LEARN)


func end_tome_teaching() -> void:
	if not _tome_teaching:
		return
	if _state == STATE_VALIDATING:
		TomeDebug.log("CastSession", "end tome teaching deferred — validation in progress")
		return
	TomeDebug.log("CastSession", "end tome teaching")
	_tome_teaching = false
	_tome_spell = null
	_coaching_retry_left = 0.0
	_abort_validation()
	_stop_mic()
	_spell = null
	_set_state(STATE_IDLE)
	tome_teaching_changed.emit(false, null)


func _begin_attempt(spell: SpellDefinition, mode: Mode) -> void:
	_spell = spell
	_mode = mode
	_recorded_samples = PackedFloat32Array()
	_transcript_words = PackedStringArray()
	_word_starts_sec = PackedFloat32Array()
	_speech_detected = false
	_silence_after_speech = 0.0
	_listen_elapsed = 0.0
	_coaching_retry_left = 0.0
	_set_state(STATE_ARMING)
	_arming_left = ARMING_SEC


func cancel() -> void:
	if _tome_teaching:
		end_tome_teaching()
		return
	if _state == STATE_IDLE:
		return
	_free_cast = false
	_free_cast_candidates = []
	_wand_voice_select = false
	_abort_validation()
	_stop_mic()
	_spell = null
	_set_state(STATE_IDLE)


## End a hold-to-cast wand session (legacy free cast only). Release commits immediately.
func release_wand_hold() -> void:
	if not _free_cast or _wand_voice_select:
		return
	match _state:
		STATE_ARMING:
			cancel()
		STATE_LISTENING:
			_begin_validation()
		_:
			pass


func _exit_tree() -> void:
	if _capture_worker != null:
		_capture_worker.stop()
		_capture_worker = null
	_stop_mic()


func _set_state(next: String) -> void:
	_state = next
	TomeDebug.log("CastSession", "state -> %s (spell=%s)" % [
		next,
		_spell.id if _spell != null else "none",
	])
	state_changed.emit(_state, _spell)


func _process(delta: float) -> void:
	if not _is_local_simulation():
		return
	match _state:
		STATE_ARMING:
			_arming_left -= delta
			_emit_arming_coaching()
			if _arming_left <= 0.0:
				_begin_listening()
		STATE_LISTENING:
			_listen_left -= delta
			_listen_elapsed += delta
			var level: float = _compute_listen_level()
			listen_level_changed.emit(level)
			_update_listen_coaching(level, delta)
			if _listen_left <= 0.0:
				if _wand_voice_select:
					## Keep the raised mic open; roll a fresh buffer.
					_recorded_samples = PackedFloat32Array()
					if _capture_worker != null:
						_capture_worker.reset()
						_capture_worker.start()
					_listen_left = WAND_SELECT_MAX_LISTEN_SEC
					_listen_elapsed = 0.0
					_speech_detected = false
					_silence_after_speech = 0.0
				else:
					_begin_validation()
		STATE_COACHING:
			_coaching_retry_left -= delta
			tome_retry_tick.emit(_coaching_retry_left)
			if _coaching_retry_left <= 0.0:
				_begin_attempt(_tome_spell, Mode.LEARN)
		_:
			pass


func _begin_listening() -> void:
	SettingsManager.stop_mic_test()
	if _capture_worker != null:
		_capture_worker.reset()
		_capture_worker.start()
	_set_state(STATE_LISTENING)
	_listen_left = (
		WAND_SELECT_MAX_LISTEN_SEC if _wand_voice_select else MAX_LISTEN_SEC
	)
	_listen_elapsed = 0.0
	_speech_detected = false
	_silence_after_speech = 0.0
	_using_broker = false

	var listener := SteamProximityVoiceHub.get_spellcasting_listener()
	if listener == null:
		## Headless --script tests have no GameApp Match VoiceSession; inject samples instead.
		if TestEnv.is_active():
			_sample_rate = int(AudioServer.get_mix_rate())
			_emit_listen_coaching()
			return
		_fail_mic_setup("Match Listeners/Spellcasting missing")
		return
	if not listener.listening:
		_fail_mic_setup(
			"Spellcasting listener not registered — Match VoiceSession must be started"
		)
		return
	listener.attach_sink(Callable(self, "_on_broker_pcm"))
	if not listener.has_sink():
		_fail_mic_setup("Spellcasting sink attach failed")
		return
	_using_broker = true
	_sample_rate = int(AudioServer.get_mix_rate())
	var broker := SteamProximityVoiceHub.get_mic_broker()
	if broker != null and broker.has_method("ensure_mic_live"):
		broker.call("ensure_mic_live")
	TomeDebug.log(
		"CastSession",
		(
			"mic via Listeners/Spellcasting last_rms=%.4f listening=%s "
			+ "broker_rms=%.4f peak_abs=%.4f chunks=%d device='%s'"
		)
		% [
			listener.last_rms,
			listener.listening,
			float(broker.call("get_last_rms")) if broker != null else 0.0,
			float(broker.call("get_last_peak_abs")) if broker != null else 0.0,
			listener.chunks_received,
			AudioServer.get_input_device(),
		]
	)
	if (
		broker != null
		and float(broker.call("get_last_peak_abs")) <= 0.0001
		and broker.has_method("diagnose_capture")
	):
		broker.call("diagnose_capture")

	_emit_listen_coaching()


func _emit_listen_coaching() -> void:
	if _free_cast:
		listen_coaching_changed.emit(_free_cast_coaching_text())
	elif _spell != null:
		listen_coaching_changed.emit(_spell.get_listen_coaching_text())


func _fail_mic_setup(reason: String) -> void:
	push_error("CastSession: %s" % reason)
	TomeDebug.log("CastSession", "mic FAILED: %s" % reason)
	_stop_mic()
	_finish_fail(reason, null, false)


func _on_broker_pcm(mono: PackedFloat32Array, _mix_rate: int) -> void:
	if not _using_broker or _state != STATE_LISTENING:
		return
	if _capture_worker == null or mono.is_empty():
		return
	_capture_worker.push_chunk(mono)


func _stop_mic() -> void:
	if _using_broker:
		var listener := SteamProximityVoiceHub.get_spellcasting_listener()
		if listener != null:
			listener.detach_sink()
		_using_broker = false
	if _capture_worker != null:
		_capture_worker.stop()


func _compute_listen_level() -> float:
	if _capture_worker == null:
		return 0.0
	return _capture_worker.get_listen_level()


func _emit_arming_coaching() -> void:
	if _free_cast:
		listen_coaching_changed.emit(_free_cast_coaching_text())
		return
	if _spell == null:
		return
	listen_coaching_changed.emit(_spell.get_listen_coaching_text())


func _update_listen_coaching(level: float, delta: float) -> void:
	var threshold: float = SpellAudioUtils.MIN_SPEECH_RMS
	if _free_cast:
		if level >= threshold:
			_speech_detected = true
			_silence_after_speech = 0.0
			listen_coaching_changed.emit("Good volume — say your spell!")
		elif _speech_detected:
			_silence_after_speech += delta
			if _wand_voice_select:
				listen_coaching_changed.emit("Got it — matching…")
				if (
					_listen_elapsed >= MIN_LISTEN_BEFORE_END_SEC
					and _silence_after_speech >= TRAILING_SILENCE_SEC
				):
					_begin_validation()
			else:
				listen_coaching_changed.emit("Got it — release to cast.")
		elif level >= threshold * 0.35:
			listen_coaching_changed.emit("Almost — speak a little louder.")
		else:
			listen_coaching_changed.emit(_free_cast_coaching_text())
		return

	if _spell == null:
		return

	if level >= threshold:
		_speech_detected = true
		_silence_after_speech = 0.0
		listen_coaching_changed.emit("Good volume — keep going!")
		return

	if _speech_detected:
		_silence_after_speech += delta
		listen_coaching_changed.emit("Got it — finishing up...")
		if _listen_elapsed >= MIN_LISTEN_BEFORE_END_SEC \
				and _silence_after_speech >= TRAILING_SILENCE_SEC:
			_begin_validation()
		return

	if level >= threshold * 0.35:
		listen_coaching_changed.emit("Almost — speak a little louder.")
	else:
		listen_coaching_changed.emit(_spell.get_listen_coaching_text())


func _free_cast_coaching_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var source: Array[SpellDefinition] = (
		_free_cast_candidates if not _free_cast_candidates.is_empty()
		else _known_spells_for_player()
	)
	for spell in source:
		if spell != null:
			parts.append('"%s"' % spell.get_incantation_text())
	if parts.is_empty():
		return "Say a spell you've learned."
	var prefix := (
		"Say a spell to arm: "
		if _wand_voice_select
		else "Say any learned incantation: "
	)
	return prefix + ", ".join(parts)


func _known_spells_for_player() -> Array[SpellDefinition]:
	if _spell_loadout != null and _spell_loadout.has_method("get_known_spells"):
		var known: Array = _spell_loadout.get_known_spells()
		var spells: Array[SpellDefinition] = []
		for spell in known:
			if spell is SpellDefinition:
				spells.append(spell)
		return spells
	return _free_cast_candidates.duplicate()


func _grammar_spells_for_player(
	known_spells: Array[SpellDefinition] = []
) -> Array[SpellDefinition]:
	var spells: Array[SpellDefinition] = []
	var seen: Dictionary = {}
	var source := known_spells
	if source.is_empty():
		source = _known_spells_for_player()
	for spell in source:
		if spell == null or seen.has(spell.id):
			continue
		seen[spell.id] = true
		spells.append(spell)
	# Tome / targeted casts may include a spell not yet in the loadout.
	if _spell != null and not seen.has(_spell.id):
		spells.append(_spell)
	return spells


func _begin_validation() -> void:
	if _state != STATE_LISTENING:
		return
	_set_state(STATE_VALIDATING)
	var used_broker := _using_broker
	var broker_rms := 0.0
	var broker := SteamProximityVoiceHub.get_mic_broker()
	if broker != null and broker.has_method("get_last_rms"):
		broker_rms = float(broker.call("get_last_rms"))
	_stop_mic()
	var worker_samples := PackedFloat32Array()
	if _capture_worker != null:
		worker_samples = _capture_worker.take_samples()
	if worker_samples.size() > _recorded_samples.size():
		_recorded_samples = worker_samples
	var peak := SpellAudioUtils.compute_peak_window_rms(_recorded_samples, _sample_rate)
	var listener := SteamProximityVoiceHub.get_spellcasting_listener()
	var listener_rms := listener.last_rms if listener != null else 0.0
	TomeDebug.log(
		"CastSession",
		(
			"validating samples=%d sample_rate=%d peak_rms=%.4f broker_rms=%.4f "
			+ "listener_rms=%.4f used_broker=%s"
		)
		% [
			_recorded_samples.size(),
			_sample_rate,
			peak,
			broker_rms,
			listener_rms,
			used_broker,
		]
	)

	if _validator == null:
		_finish_fail("Voice validator not configured")
		return

	if _try_fail_missing_stt():
		return

	var mode := "free_cast" if _free_cast else "targeted"
	var known_spells := _known_spells_for_player()
	if _free_cast:
		_free_cast_candidates = known_spells
	var grammar_spells := _grammar_spells_for_player(known_spells)
	if not _validator.start_validation(
		mode,
		_recorded_samples,
		_sample_rate,
		_spell,
		_free_cast_candidates,
		_transcript_words,
		_word_starts_sec,
		grammar_spells
	):
		_finish_fail("Could not start spell validation")
		return
	TomeDebug.log(
		"CastSession",
		"validation started (mode=%s known=%d grammar=%d)"
		% [mode, known_spells.size(), grammar_spells.size()]
	)


func _apply_validation_payload(payload: Dictionary) -> bool:
	var parsed := SpellValidationCodec.parse_worker_response(payload)
	if not bool(parsed.get("ok", false)):
		var error_text := str(parsed.get("error", "Validation failed"))
		TomeDebug.log("CastSession", "validation FAILED: %s" % error_text)
		_finish_fail(error_text)
		return false

	var transcript_words: PackedStringArray = parsed.get(
		"transcript_words", PackedStringArray()
	)
	if not transcript_words.is_empty():
		_transcript_words = transcript_words
		_word_starts_sec = parsed.get("word_starts_sec", PackedFloat32Array())
		TomeDebug.log("CastSession", 'stt transcript="%s"' % " ".join(_transcript_words))

	var spell_id := str(parsed.get("spell_id", ""))
	if not spell_id.is_empty() and _free_cast:
		for candidate in _free_cast_candidates:
			if candidate != null and candidate.id == spell_id:
				_spell = candidate
				break

	_free_cast_debug_lines = parsed.get("debug_lines", PackedStringArray())
	var result: CastValidationResult = parsed.get("result")
	if result == null:
		_finish_fail("Validation failed unexpectedly")
		return false

	_log_free_cast_debug()
	_log_validation_speech(result)
	if result.passed:
		TomeDebug.log("CastSession", "validation PASSED")
		_finish_success(result)
	else:
		TomeDebug.log("CastSession", "validation FAILED: %s" % result.failure_reason)
		_finish_fail(result.failure_reason, result)
	return true


func _on_validation_finished(_payload: Dictionary) -> void:
	if _state != STATE_VALIDATING:
		return
	_apply_validation_payload(_payload)


func _abort_validation() -> void:
	if _validator != null:
		_validator.abort_validation()


func _finish_success(validation: CastValidationResult = null) -> void:
	var mode_name: String = "learn" if _mode == Mode.LEARN else "cast"
	var finished_spell := _spell
	var was_tome := _tome_teaching
	var was_wand_select := _wand_voice_select
	if was_tome:
		_tome_teaching = false
		_tome_spell = null
	if was_wand_select and finished_spell != null:
		spell_selected.emit(finished_spell)
	else:
		cast_succeeded.emit(finished_spell, mode_name, validation)
	_spell = null
	_free_cast = false
	_wand_voice_select = false
	_free_cast_candidates = []
	_set_state(STATE_IDLE)
	if was_tome:
		tome_teaching_changed.emit(false, null)


func _finish_fail(
	reason: String,
	partial: CastValidationResult = null,
	allow_tome_coaching: bool = true
) -> void:
	var failed_spell := _spell
	## Soft teaching retries (wrong words, quiet mic) can coach; hard STT install issues cannot.
	if allow_tome_coaching and _tome_teaching and _tome_spell != null:
		cast_failed.emit(failed_spell, reason, partial)
		_spell = _tome_spell
		_coaching_retry_left = TOME_RETRY_SEC
		_set_state(STATE_COACHING)
		return
	## Wand voice select: keep listening after a miss until Q/Esc cancels.
	if _wand_voice_select and allow_tome_coaching:
		cast_failed.emit(failed_spell, reason, partial)
		_spell = null
		_recorded_samples = PackedFloat32Array()
		_transcript_words = PackedStringArray()
		_word_starts_sec = PackedFloat32Array()
		_speech_detected = false
		_silence_after_speech = 0.0
		_listen_elapsed = 0.0
		_begin_listening()
		return
	var was_tome := _tome_teaching
	if was_tome:
		_tome_teaching = false
		_tome_spell = null
	cast_failed.emit(failed_spell, reason, partial)
	_spell = null
	_free_cast = false
	_wand_voice_select = false
	_free_cast_candidates = []
	_set_state(STATE_IDLE)
	if was_tome:
		tome_teaching_changed.emit(false, null)


func _try_fail_missing_stt() -> bool:
	if _validator == null:
		return false
	var issue := _validator.get_runtime_stt_issue()
	if issue.is_empty():
		return false
	var partial := CastValidationResult.fail(issue)
	if _spell != null:
		partial.incantation_text = _spell.get_incantation_text()
	elif _tome_spell != null:
		partial.incantation_text = _tome_spell.get_incantation_text()
	CastValidationResult.apply_transcript(partial, _transcript_words)
	TomeDebug.log("CastSession", "validation FAILED: %s" % issue)
	## Missing STT cannot be fixed by coaching retry — hard-fail to idle.
	_finish_fail(issue, partial, false)
	return true


func _log_free_cast_debug() -> void:
	if _free_cast_debug_lines.is_empty():
		return
	for line in _free_cast_debug_lines:
		TomeDebug.log("FreeCastMatch", line)
	_free_cast_debug_lines = PackedStringArray()


func _log_validation_speech(result: CastValidationResult) -> void:
	if result == null:
		return
	if result.heard_text.is_empty() and result.incantation_text.is_empty():
		return
	TomeDebug.log("CastSession", "%s (passed=%s)" % [result.get_speech_match_line(), result.passed])


func _is_local_simulation() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return true
	var player_node: Node = get_parent()
	if player_node != null:
		return player_node.is_multiplayer_authority()
	return is_multiplayer_authority()
