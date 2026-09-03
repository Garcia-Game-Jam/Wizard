class_name TestArenaCatalog
extends RefCounted

const ArenaCatalogScript := preload("res://scripts/arena/arena_catalog.gd")
## Large enough that a uniformly-random 1/N pick missing any one of N=2 maps
## is astronomically unlikely (0.5^SAMPLES), so this isn't a flaky test.
const SAMPLES := 500


func run() -> int:
	var failures := 0
	failures += _test_has_both_arenas()
	failures += _test_scene_paths_resolve_and_exist()
	failures += _test_default_id_is_first_entry()
	failures += _test_random_id_always_known()
	failures += _test_random_id_covers_every_map()
	failures += _test_unknown_id_resolves_empty()
	return failures


func _test_has_both_arenas() -> int:
	if ArenaCatalogScript.count() < 2:
		push_error("Expected at least the pit and colosseum registered")
		return 1
	var ids := ArenaCatalogScript.all_ids()
	if not ids.has("pit") or not ids.has("colosseum"):
		push_error("Expected 'pit' and 'colosseum' ids, got %s" % [ids])
		return 1
	return 0


func _test_scene_paths_resolve_and_exist() -> int:
	for map_id in ArenaCatalogScript.all_ids():
		var path := ArenaCatalogScript.scene_path_for_id(map_id)
		if path.is_empty():
			push_error("Expected a scene path for registered id '%s'" % map_id)
			return 1
		if not ResourceLoader.exists(path):
			push_error("Map '%s' points at a scene that does not exist: %s" % [map_id, path])
			return 1
	return 0


func _test_default_id_is_first_entry() -> int:
	if ArenaCatalogScript.default_id() != ArenaCatalogScript.all_ids()[0]:
		push_error("Expected default_id() to be the first registered map")
		return 1
	return 0


func _test_random_id_always_known() -> int:
	for _i in SAMPLES:
		var picked := ArenaCatalogScript.random_id()
		if not ArenaCatalogScript.is_known_id(picked):
			push_error("random_id() produced an id not in the catalog: %s" % picked)
			return 1
	return 0


## Not a precise uniformity test (that needs a statistical framework this suite
## doesn't have) — just confirms every map is actually reachable, which would
## fail immediately on an off-by-one in the modulo pick.
func _test_random_id_covers_every_map() -> int:
	var seen: Dictionary = {}
	for _i in SAMPLES:
		seen[ArenaCatalogScript.random_id()] = true
	for map_id in ArenaCatalogScript.all_ids():
		if not seen.has(map_id):
			push_error(
				"Map '%s' never came up in %d random picks — selection is not covering it"
				% [map_id, SAMPLES]
			)
			return 1
	return 0


func _test_unknown_id_resolves_empty() -> int:
	if not ArenaCatalogScript.scene_path_for_id("not_a_real_map").is_empty():
		push_error("Expected an unknown map id to resolve to an empty path")
		return 1
	if ArenaCatalogScript.is_known_id("not_a_real_map"):
		push_error("Expected is_known_id to reject an unregistered id")
		return 1
	return 0
