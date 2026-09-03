class_name EncounterDefinition
extends Resource

## One wave/fight within a LevelDefinition — its monster spawns and cover
## obstacle positions. Add/remove monsters and obstacle_positions with the
## Inspector's own array controls; positions are also editable by dragging
## the matching preview marker in encounter_design_workshop.tscn and running
## its "Sync Positions From Markers" action.

## Preloaded rather than the bare "MonsterSpawnEntry" class name — a fresh
## class_name script isn't in the global class cache until the editor
## rescans the project, and a bare reference fails to resolve until then.
const MonsterSpawnEntryScript := preload("res://scripts/arena/monster_spawn_entry.gd")

@export var label: String = ""
@export var monsters: Array[MonsterSpawnEntryScript] = []
@export var obstacle_positions: Array[Vector3] = []
