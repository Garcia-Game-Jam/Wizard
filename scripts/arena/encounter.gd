class_name Encounter
extends Resource

## Base type for one stage within a LevelDefinition's ordered `encounters`
## sequence — a scene that changes the map and spawns in/despawns entities.
## Concrete subclasses: CombatEncounter (a wave/fight — monster spawns and
## cover obstacles), ShopEncounter, ChallengeEncounter. LevelDefinition's
## `encounters` array can hold any mix of these, orderable with the
## Inspector's own array controls in encounter_design_workshop.tscn — see
## that script's doc comment for how the workshop authors them.

@export var label: String = ""
