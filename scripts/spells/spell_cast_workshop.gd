@tool
extends Node3D

## Wand-only studio: preview E-lift selection FX and LMB category cast flourishes.
## Open spell_cast_workshop.tscn → pick a spell → Play Selection / Cast / Full Sequence.

const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")

@export_group("Spells")
@export var spells: Array[SpellDefinition] = []
@export var selected_spell: SpellDefinition:
	set(value):
		selected_spell = value
		_sync_selected_index()
@export_range(0, 64, 1) var selected_index: int = 0:
	set(value):
		selected_index = maxi(value, 0)
		_apply_selected_index()

@export_group("Preview")
@export_tool_button("Play Selection", "Callable")
var play_selection_action := play_selection_preview
@export_tool_button("Play Cast", "Callable")
var play_cast_action := play_cast_preview
@export_tool_button("Play Full Sequence", "Callable")
var play_full_action := play_full_sequence
@export_tool_button("Next Spell", "Callable")
var next_spell_action := select_next_spell
@export_tool_button("Prev Spell", "Callable")
var prev_spell_action := select_prev_spell
@export_tool_button("Reset Pose", "Callable")
var reset_pose_action := reset_pose

var _preview_busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preview_busy = false
	_ensure_default_spells()
	_apply_selected_index()
	_prepare_wand()


func play_selection_preview() -> void:
	if not is_inside_tree():
		return
	if _preview_busy:
		return
	var spell := _resolve_spell()
	if spell == null:
		push_warning("SpellCastWorkshop: no spell selected")
		return
	_preview_busy = true
	await _run_selection(spell)
	_preview_busy = false


func play_cast_preview() -> void:
	if not is_inside_tree():
		return
	if _preview_busy:
		return
	var spell := _resolve_spell()
	if spell == null:
		push_warning("SpellCastWorkshop: no spell selected")
		return
	_preview_busy = true
	await _run_cast(spell)
	_preview_busy = false


func play_full_sequence() -> void:
	if not is_inside_tree():
		return
	if _preview_busy:
		return
	var spell := _resolve_spell()
	if spell == null:
		push_warning("SpellCastWorkshop: no spell selected")
		return
	_preview_busy = true
	await _run_selection(spell)
	if not is_inside_tree():
		_preview_busy = false
		return
	await _editor_wait(0.15)
	await _run_cast(spell)
	_preview_busy = false


func select_next_spell() -> void:
	if spells.is_empty():
		return
	selected_index = (selected_index + 1) % spells.size()


func select_prev_spell() -> void:
	if spells.is_empty():
		return
	selected_index = (selected_index - 1 + spells.size()) % spells.size()


func reset_pose() -> void:
	var wand := _wand()
	if wand == null:
		return
	_prepare_wand()
	wand.set_raised(false, true)
	wand.set_armed(false)
	wand.cache_idle_transform()


func _run_selection(spell: SpellDefinition) -> void:
	var wand := _wand()
	if wand == null:
		return
	_prepare_wand()
	wand.set_armed(true)
	wand.set_raised(true, false)
	await _editor_wait(0.28)
	await wand.play_spell_recognition(spell)
	wand.set_raised(false, false)
	await _editor_wait(0.28)
	wand.play_cast_success(spell, true)


func _run_cast(spell: SpellDefinition) -> void:
	var wand := _wand()
	if wand == null:
		return
	_prepare_wand()
	wand.set_raised(false, true)
	wand.set_armed(true)
	wand.begin_cast_charge(spell)
	var charge := spell.get_charge_time_sec() if spell != null else 0.0
	await _editor_wait(maxf(charge, 0.35))
	await wand.release_cast(spell, true)
	await _editor_wait(0.05)


func _editor_wait(sec: float) -> void:
	## Editor trees are often paused; process_always + ignore_pause so awaits complete.
	if not is_inside_tree():
		return
	await get_tree().create_timer(sec, true, true).timeout


func _prepare_wand() -> void:
	var wand := _wand()
	if wand == null:
		return
	wand.process_mode = Node.PROCESS_MODE_ALWAYS
	wand.ensure_preview_ready()
	var tip := wand.get_node_or_null("Model/Tip") as Node3D
	if tip == null:
		tip = wand.get_node_or_null("Tip") as Node3D
	if tip != null:
		tip.visible = true
	var listen := wand.get_node_or_null("Model/WandListeningFx") as Node
	if listen != null:
		listen.process_mode = Node.PROCESS_MODE_ALWAYS


func _wand() -> PlayerWand:
	return get_node_or_null("Wand") as PlayerWand


func _resolve_spell() -> SpellDefinition:
	if selected_spell != null:
		return selected_spell
	if selected_index >= 0 and selected_index < spells.size():
		return spells[selected_index]
	return null


func _apply_selected_index() -> void:
	if spells.is_empty():
		return
	var idx := clampi(selected_index, 0, spells.size() - 1)
	if idx != selected_index:
		selected_index = idx
		return
	var spell := spells[idx]
	if selected_spell != spell:
		selected_spell = spell


func _sync_selected_index() -> void:
	if selected_spell == null or spells.is_empty():
		return
	for i in spells.size():
		if spells[i] == selected_spell:
			if selected_index != i:
				selected_index = i
			return


func _ensure_default_spells() -> void:
	if not spells.is_empty():
		return
	## Fallback if scene exports were cleared — load authored resources by path.
	var paths := [
		"res://scenes/spells/fireball/fireball.tres",
		"res://scenes/spells/flare/flare.tres",
		"res://scenes/spells/ward/ward.tres",
		"res://scenes/spells/haste/haste.tres",
		"res://scenes/spells/light/light.tres",
		"res://scenes/spells/light_ball/light_ball.tres",
		"res://scenes/spells/show_me/show_me.tres",
		"res://scenes/spells/target/target.tres",
		"res://scenes/spells/pull/pull.tres",
		"res://scenes/spells/follow/follow.tres",
		"res://scenes/spells/stop/stop.tres",
		"res://scenes/spells/dispell/dispell.tres",
		"res://scenes/spells/clone/clone.tres",
	]
	var loaded: Array[SpellDefinition] = []
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		if res is SpellDefinitionScript:
			loaded.append(res as SpellDefinitionScript)
	spells = loaded
