class_name TestArenaEncounters
extends RefCounted

const ArenaEncountersScript := preload("res://scripts/arena/arena_encounters.gd")
const ArenaCoverScript := preload("res://scripts/arena/arena_cover.gd")
const SpawnTelegraphScript := preload("res://scripts/arena/spawn_telegraph.gd")


func run() -> int:
	var failures := 0
	failures += _test_six_dumps_are_distinct()
	failures += _test_dumps_stay_on_charger_and_ember()
	failures += _test_starter_omits_ward()
	failures += _test_cover_keeps_player_spawns_clear()
	failures += _test_restage_skips_first_fight()
	failures += _test_pads_for_matches_dump()
	failures += _test_cover_restage_motion()
	failures += _test_cover_restage_survives_rewind_restore()
	failures += _test_telegraph_survives_rewind_restore()
	failures += _test_dump_slot_names_are_unique()
	failures += _test_live_kinds_are_preloaded()
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


func _test_dumps_stay_on_charger_and_ember() -> int:
	var allowed: Dictionary = {
		ArenaEncountersScript.KIND_CHARGER: true,
		ArenaEncountersScript.KIND_EMBER: true,
	}
	for i in 6:
		for entry in ArenaEncountersScript.dump_for(i):
			var kind := str(entry.get("kind", ""))
			if not allowed.has(kind):
				push_error("Fight %d spawned unevaluated kind '%s'" % [i + 1, kind])
				return 1
	return 0


func _test_starter_omits_ward() -> int:
	if ArenaEncountersScript.STARTER_SPELL_IDS != ["stone_throw"]:
		push_error("Arena starters must be stone_throw only")
		return 1
	return 0


func _signature(dump: Array[Dictionary]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry in dump:
		parts.append("%s:%s" % [entry.get("kind", ""), entry.get("pad", -1)])
	return ",".join(parts)


func _test_cover_keeps_player_spawns_clear() -> int:
	for i in 6:
		for pos in ArenaEncountersScript.cover_positions(i):
			if ArenaEncountersScript.cover_overlaps_player_spawn(pos):
				push_error("Cover layout %d overlaps a player spawn at %s" % [i, pos])
				return 1
	var on_pad := Vector3(-4.0, 1.0, 14.0)
	if not ArenaEncountersScript.cover_overlaps_player_spawn(on_pad):
		push_error("A cube on PlayerSpawn_0 must count as blocking")
		return 1
	return 0


func _test_restage_skips_first_fight() -> int:
	var issues: PackedStringArray = PackedStringArray()
	if ArenaEncountersScript.should_restage_cover(0, 0.0):
		issues.append("Fight 1 must not restage cover")
	if not ArenaEncountersScript.should_restage_cover(1, 0.0):
		issues.append("Roll 0 must restage after fight 1")
	if ArenaEncountersScript.should_restage_cover(1, 0.99):
		issues.append("High roll must keep cover")
	if ArenaEncountersScript.cover_restage_chance(0) < 0.49:
		issues.append("Base restage chance should start at half")
	if ArenaEncountersScript.cover_restage_chance(2) < 0.99:
		issues.append("Two misses must guarantee a restage")
	if not ArenaEncountersScript.should_restage_cover(1, 0.99, 2):
		issues.append("Ramped chance must restage after misses")
	if issues.is_empty():
		return 0
	push_error(issues[0])
	return 1


func _test_pads_for_matches_dump() -> int:
	for i in 6:
		var pads := ArenaEncountersScript.pads_for(i)
		if pads.is_empty():
			push_error("Encounter %d must telegraph at least one pad" % i)
			return 1
		var dump := ArenaEncountersScript.dump_for(i)
		for entry in dump:
			var pad := int(entry.get("pad", -1))
			if not Array(pads).has(pad):
				push_error("Dump pad %d missing from telegraph list" % pad)
				return 1
	return 0


func _test_cover_restage_motion() -> int:
	var cover: Node3D = ArenaCoverScript.new()
	cover.position = Vector3(-6.0, 1.0, -4.0)
	cover.call("_ready")
	cover.call("restage_to", Vector3(6.0, 1.0, 3.0))
	if not bool(cover.call("is_busy")):
		cover.free()
		push_error("Restage must start an enter/exit")
		return 1
	var steps := 0
	while bool(cover.call("is_busy")) and steps < 200:
		cover.call("_rollback_tick", 0.05, steps, true)
		steps += 1
	var seated := cover.position.distance_to(Vector3(6.0, 1.0, 3.0)) < 0.08
	var idle := not bool(cover.call("is_busy"))
	cover.free()
	if not idle or not seated:
		push_error("Cover should finish seated at the new home")
		return 1
	return 0


func _test_cover_restage_survives_rewind_restore() -> int:
	var cover: Node3D = ArenaCoverScript.new()
	cover.position = Vector3(-6.0, 1.0, -4.0)
	cover.call("_ready")
	cover.call("restage_to", Vector3(6.0, 1.0, 3.0))
	cover.set("cover_dir", 0)
	cover.set("has_queued", 0)
	cover.set("cover_t", 1.0)
	cover.call("_rollback_tick", 0.05, 1, true)
	var still_moving := bool(cover.call("is_busy"))
	var sunk := cover.position.y < 0.95
	cover.free()
	if not still_moving or not sunk:
		push_error("Rewind restore must not cancel a cover restage")
		return 1
	return 0


func _test_telegraph_survives_rewind_restore() -> int:
	var tell: Node = SpawnTelegraphScript.new()
	tell.call("show_pads", PackedInt32Array([0, 2]))
	if int(tell.get("requested_mask")) != 5:
		tell.free()
		push_error("Telegraph must keep the requested pad mask")
		return 1
	tell.set("pad_mask", 0)
	tell.set("spot_energy", 0.0)
	tell.call("_rollback_tick", 0.05, 1, true)
	var restored := int(tell.get("pad_mask")) == 5
	tell.free()
	if not restored:
		push_error("Rewind restore must not wipe the spawn tell")
		return 1
	return 0


func _test_dump_slot_names_are_unique() -> int:
	var seen: Dictionary = {}
	for encounter in 12:
		var dump := ArenaEncountersScript.dump_for(encounter)
		for slot in dump.size():
			var node_name := ArenaEncountersScript.dump_node_name(encounter, slot)
			if seen.has(node_name):
				push_error("Dump name %s collides across encounters" % node_name)
				return 1
			seen[node_name] = true
	var two_ember := ArenaEncountersScript.dump_for(5)
	if two_ember.size() < 2:
		push_error("Encounter 5 must dump at least two monsters")
		return 1
	if ArenaEncountersScript.dump_node_name(5, 0) == ArenaEncountersScript.dump_node_name(5, 1):
		push_error("Same-kind dump slots must not share a node name")
		return 1
	return 0


func _test_live_kinds_are_preloaded() -> int:
	var charger := ArenaEncountersScript.packed_scene_for(ArenaEncountersScript.KIND_CHARGER)
	var ember := ArenaEncountersScript.packed_scene_for(ArenaEncountersScript.KIND_EMBER)
	if charger == null or ember == null:
		push_error("Live dump kinds must resolve to PackedScenes")
		return 1
	if not charger.resource_path.ends_with("charger.tscn"):
		push_error("Charger dump scene should be charger.tscn")
		return 1
	if not ember.resource_path.ends_with("ember_wretch.tscn"):
		push_error("Ember dump scene should be ember_wretch.tscn")
		return 1
	var ash_path := ArenaEncountersScript.scene_path_for(ArenaEncountersScript.KIND_ASH)
	if not ash_path.ends_with("ash_wretch.tscn"):
		push_error("Evaluating ash should stay a path until it is live")
		return 1
	return 0
