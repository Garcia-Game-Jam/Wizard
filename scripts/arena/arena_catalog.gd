class_name ArenaCatalog
extends RefCounted

## Registry of playable arenas. Add a new map here and it's automatically part
## of the random 1/N selection NetworkManager.start_game() makes — nothing else
## needs to change. Paths only (no preload) so listing maps never eagerly loads
## arena scenes; scenes/arena_bulls-style content is loaded lazily by id.

const MAPS: Array[Dictionary] = [
	{"id": "pit", "name": "The Pit", "scene": "res://scenes/arena.tscn"},
	{"id": "colosseum", "name": "Colosseum", "scene": "res://scenes/arenas/arena_bulls.tscn"},
]


static func count() -> int:
	return MAPS.size()


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in MAPS:
		ids.append(str(entry.get("id", "")))
	return ids


## First entry — used when nothing has picked a map yet (editor preview, a
## match-world instantiation outside the normal start_game() flow, tests).
static func default_id() -> String:
	if MAPS.is_empty():
		return ""
	return str(MAPS[0].get("id", ""))


## Uniform 1/N pick across every registered map.
static func random_id() -> String:
	if MAPS.is_empty():
		return ""
	return str(MAPS[randi() % MAPS.size()].get("id", ""))


static func display_name_for_id(map_id: String) -> String:
	for entry in MAPS:
		if str(entry.get("id", "")) == map_id:
			return str(entry.get("name", map_id))
	return map_id


## Empty string when map_id is unknown/blank — callers fall back themselves
## (game_app.gd falls back to MATCH_SCENE) rather than this class guessing.
static func scene_path_for_id(map_id: String) -> String:
	if map_id.is_empty():
		return ""
	for entry in MAPS:
		if str(entry.get("id", "")) == map_id:
			return str(entry.get("scene", ""))
	return ""


static func is_known_id(map_id: String) -> bool:
	return not scene_path_for_id(map_id).is_empty()
