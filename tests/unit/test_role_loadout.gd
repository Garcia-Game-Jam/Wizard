class_name TestRoleLoadout
extends RefCounted

const RoleLoadoutScript := preload("res://scripts/progression/role_loadout.gd")


func run() -> int:
	var failures := 0
	failures += _test_apprentice_starter_kit()
	failures += _test_role_label()
	return failures


func _test_apprentice_starter_kit() -> int:
	var spell_ids := RoleLoadoutScript.get_starting_spell_ids()
	var expected := RoleLoadoutScript.APPRENTICE_STARTER_SPELLS
	var missing_required := (
		not spell_ids.has("light")
		or not spell_ids.has("light_ball")
		or not spell_ids.has("target")
		or not spell_ids.has("pull")
		or not spell_ids.has("follow")
		or not spell_ids.has("stop")
		or not spell_ids.has("dispell")
		or not spell_ids.has("flare")
		or not spell_ids.has("ward")
		or not spell_ids.has("fireball")
	)
	if spell_ids.size() != expected.size() or missing_required:
		push_error("Expected apprentice loadout to match starter kit")
		return 1
	return 0


func _test_role_label() -> int:
	if RoleLoadoutScript.role_label() != "Apprentice":
		push_error("Expected apprentice role label")
		return 1
	return 0
