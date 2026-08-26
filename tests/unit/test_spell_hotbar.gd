extends RefCounted

const SpellHotbarScript := preload("res://scripts/spells/spell_hotbar.gd")
const LoadoutScript := preload("res://scripts/spells/character_spell_loadout.gd")
const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")


func run() -> int:
	var failures := 0
	failures += _test_pending_assign_and_overwrite()
	failures += _test_pending_clears_selection()
	failures += _test_empty_activate_does_nothing()
	failures += _test_swap_moves_selection()
	failures += _test_four_slot_cap()
	failures += _test_slots_persist_without_timer()
	failures += _test_assignment_prompt()
	failures += _test_slot_order_lmb_first()
	return failures


func _make_hotbar() -> Dictionary:
	var loadout := LoadoutScript.new()
	var fireball := SpellDefinitionScript.new()
	fireball.id = "fireball"
	fireball.display_name = "Fireball"
	var haste := SpellDefinitionScript.new()
	haste.id = "haste"
	haste.display_name = "Haste"
	var ward := SpellDefinitionScript.new()
	ward.id = "ward"
	ward.display_name = "Ward"
	var flare := SpellDefinitionScript.new()
	flare.id = "flare"
	flare.display_name = "Flare"
	loadout.configure([fireball, haste, ward, flare])
	loadout.apply_starting_spells(["fireball", "haste", "ward", "flare"])
	var hotbar := SpellHotbarScript.new()
	hotbar.configure(loadout)
	return {
		"hotbar": hotbar,
		"fireball": fireball,
		"haste": haste,
		"ward": ward,
		"flare": flare,
	}


func _test_pending_assign_and_overwrite() -> int:
	var pack := _make_hotbar()
	var hotbar: SpellHotbarScript = pack["hotbar"]
	var fireball: SpellDefinitionScript = pack["fireball"]
	var haste: SpellDefinitionScript = pack["haste"]
	var selected: Array = []
	hotbar.slot_selected.connect(
		func(_index: int, spell: SpellDefinition) -> void:
			selected.append({"id": spell.id})
	)
	hotbar.begin_pending(fireball)
	var problem := ""
	if not hotbar.has_pending():
		problem = "Expected voice confirm to start pending slot assignment"
	elif not hotbar.assign_pending_to(0):
		problem = "Expected pending spell to assign to slot 0"
	elif hotbar.has_pending() or hotbar.get_slot(0) != "fireball":
		problem = "Expected slot 0 to store fireball and clear pending"
	elif hotbar.get_selected_index() != 0:
		problem = "Expected assigning a slot to select it"
	elif selected.size() != 1 or selected[0]["id"] != "fireball":
		problem = "Expected slot_selected on assign"
	else:
		hotbar.begin_pending(haste)
		if not hotbar.assign_pending_to(0):
			problem = "Expected overwrite assign to succeed"
		elif hotbar.get_slot(0) != "haste":
			problem = "Expected occupied slot to be overwritten"
	if problem.is_empty():
		return 0
	push_error(problem)
	return 1


func _test_pending_clears_selection() -> int:
	var pack := _make_hotbar()
	var hotbar: SpellHotbarScript = pack["hotbar"]
	hotbar.begin_pending(pack["fireball"])
	hotbar.assign_pending_to(0)
	hotbar.begin_pending(pack["haste"])
	if hotbar.get_selected_index() != -1:
		push_error("Expected a new pending assign to clear the previous selection")
		return 1
	return 0


func _test_empty_activate_does_nothing() -> int:
	var pack := _make_hotbar()
	var hotbar: SpellHotbarScript = pack["hotbar"]
	if hotbar.try_activate_slot(1):
		push_error("Expected empty slot activate to fail")
		return 1
	if hotbar.get_selected_index() != -1:
		push_error("Expected empty activate to leave selection cleared")
		return 1
	return 0


func _test_swap_moves_selection() -> int:
	var pack := _make_hotbar()
	var hotbar: SpellHotbarScript = pack["hotbar"]
	hotbar.begin_pending(pack["fireball"])
	hotbar.assign_pending_to(0)
	hotbar.begin_pending(pack["haste"])
	hotbar.assign_pending_to(1)
	hotbar.try_activate_slot(0)
	hotbar.swap_slots(0, 1)
	if hotbar.get_slot(0) != "haste" or hotbar.get_slot(1) != "fireball":
		push_error("Expected swap to exchange slotted spells")
		return 1
	if hotbar.get_selected_index() != 1:
		push_error("Expected selected slot to follow the swapped spell")
		return 1
	return 0


func _test_four_slot_cap() -> int:
	var pack := _make_hotbar()
	var hotbar: SpellHotbarScript = pack["hotbar"]
	var problem := ""
	if SpellHotbarScript.SLOT_COUNT != 4:
		problem = "Expected exactly 4 spell slots"
	else:
		hotbar.begin_pending(pack["fireball"])
		hotbar.assign_pending_to(0)
		hotbar.begin_pending(pack["haste"])
		hotbar.assign_pending_to(1)
		hotbar.begin_pending(pack["ward"])
		hotbar.assign_pending_to(2)
		hotbar.begin_pending(pack["flare"])
		hotbar.assign_pending_to(3)
		hotbar.begin_pending(pack["fireball"])
		if hotbar.get_slots() != ["fireball", "haste", "ward", "flare"]:
			problem = "Expected four assigned spells to fill the hotbar"
		elif hotbar.assign_pending_to(4):
			problem = "Expected assign past slot 3 to fail"
		elif not hotbar.has_pending():
			problem = "Expected rejected assign to keep pending"
		elif hotbar.get_slots() != ["fireball", "haste", "ward", "flare"]:
			problem = "Expected a fifth assign to leave the four slots unchanged"
	if problem.is_empty():
		return 0
	push_error(problem)
	return 1


func _test_slots_persist_without_timer() -> int:
	var pack := _make_hotbar()
	var hotbar: SpellHotbarScript = pack["hotbar"]
	hotbar.begin_pending(pack["fireball"])
	hotbar.assign_pending_to(2)
	hotbar.clear_selection()
	if hotbar.get_slot(2) != "fireball":
		push_error("Expected stored spells to remain after deselect")
		return 1
	if not hotbar.try_activate_slot(2):
		push_error("Expected a stored spell to load again with no recast")
		return 1
	return 0


func _test_assignment_prompt() -> int:
	var pack := _make_hotbar()
	var hotbar: SpellHotbarScript = pack["hotbar"]
	if not hotbar.assignment_prompt().is_empty():
		push_error("Expected no assignment prompt without a pending spell")
		return 1
	hotbar.begin_pending(pack["fireball"])
	var prompt := hotbar.assignment_prompt()
	if not prompt.contains("Fireball"):
		push_error("Expected assignment prompt to name the pending spell")
		return 1
	if not prompt.contains("RMB") and not prompt.contains("["):
		push_error("Expected assignment prompt to include slot hotkeys")
		return 1
	if not prompt.contains("E") and not prompt.contains("["):
		push_error("Expected assignment prompt to include the E slot key")
		return 1
	if not prompt.contains("LMB") and not prompt.contains("["):
		push_error("Expected assignment prompt to include the LMB slot")
		return 1
	return 0


func _test_slot_order_lmb_first() -> int:
	var order := SpellHotbarScript.SLOT_FALLBACKS
	if order.size() != 4:
		push_error("Expected four spell-slot fallbacks")
		return 1
	if order[0] != "LMB" or order[1] != "RMB" or order[2] != "Q" or order[3] != "E":
		push_error("Expected spell slots ordered LMB, RMB, Q, E")
		return 1
	return 0
