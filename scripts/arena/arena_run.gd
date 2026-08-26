class_name ArenaRun
extends RefCounted

## Rule-of-3 arena session: three fights, then one shared spell grant.

const FIGHTS_PER_SPELL := 3


var completed_fights: int = 0
var granted_spell_ids: Array[String] = []
var spell_unlock_queue: Array[String] = []


static func create(unlock_queue: Array[String] = []) -> ArenaRun:
	var run := ArenaRun.new()
	run.spell_unlock_queue = unlock_queue.duplicate()
	return run


func fights_into_cycle() -> int:
	return completed_fights % FIGHTS_PER_SPELL


func cycle_index() -> int:
	return int(float(completed_fights) / float(FIGHTS_PER_SPELL))


func encounter_index() -> int:
	return completed_fights


func next_grant_spell_id() -> String:
	if granted_spell_ids.size() >= spell_unlock_queue.size():
		return ""
	return spell_unlock_queue[granted_spell_ids.size()]


## Call when a fight ends (wipe, clear, or last wizard standing).
## Returns the spell id granted to the whole party, or "" if none this fight.
func complete_fight() -> String:
	completed_fights += 1
	if completed_fights % FIGHTS_PER_SPELL != 0:
		return ""
	var spell_id := next_grant_spell_id()
	if spell_id.is_empty():
		return ""
	granted_spell_ids.append(spell_id)
	return spell_id


func to_snapshot() -> Dictionary:
	return {
		"completed_fights": completed_fights,
		"granted_spell_ids": granted_spell_ids.duplicate(),
		"spell_unlock_queue": spell_unlock_queue.duplicate(),
	}


static func from_snapshot(data: Dictionary) -> ArenaRun:
	var run := ArenaRun.new()
	run.completed_fights = maxi(int(data.get("completed_fights", 0)), 0)
	var granted: Variant = data.get("granted_spell_ids", [])
	if granted is Array:
		for spell_id in granted:
			run.granted_spell_ids.append(str(spell_id))
	var queue: Variant = data.get("spell_unlock_queue", [])
	if queue is Array:
		for spell_id in queue:
			run.spell_unlock_queue.append(str(spell_id))
	return run
