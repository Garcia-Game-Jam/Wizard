class_name LevelDefinition
extends Resource

## A full playable level: one map plus an ordered sequence of encounters.
## Arena geometry (pads/gates/cover clearance) doesn't change mid-level, so a
## level commits to a single map for its whole encounter sequence.
##
## This resource IS the save file — use its own Inspector picker (the
## dropdown arrow next to the "Level" field in encounter_design_workshop.tscn)
## for New/Load/Save/Save As. Add or remove encounters with the Inspector's
## array controls on `encounters` below.

const ArenaCatalogScript := preload("res://scripts/arena/arena_catalog.gd")
## Preloaded rather than the bare "EncounterDefinition" class name — see
## encounter_definition.gd's identical note on MonsterSpawnEntryScript.
const EncounterDefinitionScript := preload("res://scripts/arena/encounter_definition.gd")

@export var level_name: String = "New Level"
@export var map_id: String = ""
@export var encounters: Array[EncounterDefinitionScript] = []


## Presents map_id as a dropdown of every ArenaCatalog map instead of a free
## string field — built live so it can never go stale as maps are added.
func _validate_property(property: Dictionary) -> void:
	if property.get("name", "") != "map_id":
		return
	var parts := PackedStringArray()
	for id in ArenaCatalogScript.all_ids():
		parts.append("%s:%s" % [ArenaCatalogScript.display_name_for_id(id), id])
	property["hint"] = PROPERTY_HINT_ENUM
	property["hint_string"] = ",".join(parts)
