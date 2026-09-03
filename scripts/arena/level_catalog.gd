class_name LevelCatalog
extends RefCounted

## Registry of playable levels — LevelDefinition .tres files under
## scenes/arenas/levels/, authored with encounter_design_workshop.tscn.
## Scans the directory live (unlike ArenaCatalog's hand-maintained MAPS list)
## since levels are user-authored content that grows whenever someone clicks
## "Save As" in the workshop — a hardcoded list would go stale immediately.

const LEVELS_DIR := "res://scenes/arenas/levels/"
const DEFAULT_LEVEL_ID := "default_level"


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == "tres":
			ids.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids


## First entry — used when nothing has picked a level yet.
static func default_id() -> String:
	var ids := all_ids()
	if ids.has(DEFAULT_LEVEL_ID):
		return DEFAULT_LEVEL_ID
	return ids[0] if not ids.is_empty() else ""


## Uniform 1/N pick across every level on disk.
static func random_id() -> String:
	var ids := all_ids()
	if ids.is_empty():
		return ""
	return ids[randi() % ids.size()]


## Empty string when level_id is unknown/blank — callers fall back
## themselves, matching ArenaCatalog.scene_path_for_id()'s contract.
static func path_for_id(level_id: String) -> String:
	if level_id.is_empty():
		return ""
	var path := LEVELS_DIR + level_id + ".tres"
	return path if ResourceLoader.exists(path) else ""


static func is_known_id(level_id: String) -> bool:
	return not path_for_id(level_id).is_empty()


## Plain load() (CACHE_MODE_REUSE), deliberately NOT load_level()'s
## CACHE_MODE_REPLACE below — this is a read-only "what's this level called"
## lookup (level-select UI, dropdowns, ...), not a "give me the live level"
## one. Going through load_level() here would force-replace whatever's
## already cached for level_id on every single call — including a
## LevelDefinition another part of the process (encounter_design_workshop.gd
## editing it live, a match's own _active_level()) currently holds unsaved
## in-memory changes to, silently discarding them.
static func display_name_for_id(level_id: String) -> String:
	var path := path_for_id(level_id)
	if path.is_empty():
		return level_id
	var level := load(path)
	if level == null:
		return level_id
	var display_name := str(level.get("level_name"))
	return display_name if not display_name.is_empty() else level_id


## CACHE_MODE_REPLACE, not plain load()/CACHE_MODE_REUSE — levels are live-
## edited content (encounter_design_workshop.tscn saves over the same path
## repeatedly during a single dev session), and a stale ResourceCache entry
## from an earlier load in this same process would otherwise silently mask
## every edit made since, in-editor preview and a running match alike. Only
## call this where "the freshest saved copy" is actually the intent — e.g.
## a match resolving which level to actually play; a mere display-name
## lookup should use display_name_for_id() above instead.
static func load_level(level_id: String) -> Resource:
	var path := path_for_id(level_id)
	if path.is_empty():
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
