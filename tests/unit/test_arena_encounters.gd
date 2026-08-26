class_name TestArenaEncounters
extends RefCounted

const ArenaEncountersScript := preload("res://scripts/arena/arena_encounters.gd")


func run() -> int:
	var failures := 0
	failures += _test_six_dumps_are_distinct()
	failures += _test_ward_exams_use_ash()
	failures += _test_starter_omits_ward()
	return failures


func _test_six_dumps_are_distinct() -> int:
	var signatures: Dictionary = {}
	for i in 6:
		var dump := ArenaEncountersScript.dump_for(i)
		if dump.is_empty():
			push_error("Encounter %d must spawn at least one monster" % i)
			return 1
		var sig := _signature(dump)
		if signatures.has(sig):
			push_error("Encounter %d repeats an earlier dump" % i)
			return 1
		signatures[sig] = true
	if _signature(ArenaEncountersScript.dump_for(6)) != _signature(ArenaEncountersScript.dump_for(0)):
		push_error("Dumps should wrap after six fights")
		return 1
	return 0


func _test_ward_exams_use_ash() -> int:
	for i in range(3, 6):
		var kinds: Array[String] = []
		for entry in ArenaEncountersScript.dump_for(i):
			kinds.append(str(entry.get("kind", "")))
		if not kinds.has(ArenaEncountersScript.KIND_ASH):
			push_error("Fight %d should include an ice caster so Ward is the clean answer" % (i + 1))
			return 1
	return 0


func _test_starter_omits_ward() -> int:
	if ArenaEncountersScript.STARTER_SPELL_IDS.has("ward"):
		push_error("Arena starters must not already include the first grant")
		return 1
	if ArenaEncountersScript.STARTER_SPELL_IDS.size() > 3:
		push_error("Keep a free hotbar slot for the spoken Ward load-in")
		return 1
	return 0


func _signature(dump: Array[Dictionary]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry in dump:
		parts.append("%s:%s" % [entry.get("kind", ""), entry.get("pad", -1)])
	return ",".join(parts)
