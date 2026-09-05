class_name CombatEncounter
extends Encounter

## One wave/fight within a LevelDefinition — its monster spawns and cover
## obstacle positions. Add/remove monsters and obstacle_positions with the
## Inspector's own array controls; positions are also editable by dragging
## the matching preview marker in encounter_design_workshop.tscn and running
## its "Sync Positions From Markers" action.

## Preloaded rather than the bare "MonsterSpawnEntry" class name — a fresh
## class_name script isn't in the global class cache until the editor
## rescans the project, and a bare reference fails to resolve until then.
const MonsterSpawnEntryScript := preload("res://scripts/arena/monster_spawn_entry.gd")

@export var monsters: Array[MonsterSpawnEntryScript] = []
@export var obstacle_positions: Array[Vector3] = []
## Which of the map's GateN colosseum gates (see colosseum_gate_ring.gd) drop
## open for this encounter's telegraph — empty on a map with no gates, and
## by default on any map, since opening one is an opt-in per encounter.
## GateN is numbered clockwise from north starting at Gate0 (angles_deg's
## default in colosseum_gate_ring.gd), so index N is the (N+1)th gate
## clockwise from north — edit this array directly in the Inspector.
@export var open_gate_indices: Array[int] = []
