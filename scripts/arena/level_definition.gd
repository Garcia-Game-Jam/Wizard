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
## Preloaded rather than the bare "Encounter" class name — see
## combat_encounter.gd's identical note on MonsterSpawnEntryScript.
const EncounterScript := preload("res://scripts/arena/encounter.gd")

@export var level_name: String = "New Level"

## The setter strips a leaked "Label:value" enum hint down to just the id —
## same Inspector-write-back leak as MonsterSpawnEntry.kind/spawn_animation
## (see that file's note); map_id's dropdown is the dynamic one built by
## _validate_property() below, in the same "Display Name:id" shape.
@export var map_id: String = "":
	set(value):
		map_id = value.substr(value.rfind(":") + 1) if value.contains(":") else value

## Ordered, heterogeneous — any mix of CombatEncounter, ShopEncounter,
## ChallengeEncounter, etc.
@export var encounters: Array[EncounterScript] = []


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
