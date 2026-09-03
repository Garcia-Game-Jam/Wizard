class_name MonsterSpawnEntry
extends Resource

## One monster placement within an EncounterDefinition. kind matches a key in
## ArenaEncounters.SCENE_BY_KIND (scripts/arena/arena_encounters.gd) — add a
## new option here if a new monster kind is ever registered there.

## The setter strips a leaked "Label:value" enum hint down to just the value
## — some Inspector contexts (nested nested-resource-array editing observed
## in practice) write the whole @export_enum hint string back as the value
## instead of parsing it, which would otherwise silently corrupt this into
## an unrecognized kind (SCENE_BY_KIND.get() miss -> monster never spawns).
@export_enum("Charger:charger", "Ember Wretch:ember", "Ash Wretch:ash") var kind: String = "charger":
	set(value):
		## TEMP diagnostic for the "kind corrupts to 'Label:value' when picked
		## right after adding a monster" investigation — remove once closed.
		print("[MonsterSpawnEntry.kind setter] incoming value=%s (resource=%s)" % [value, self])
		kind = value.substr(value.rfind(":") + 1) if value.contains(":") else value
@export var position: Vector3 = Vector3.ZERO
@export_range(-180.0, 180.0, 1.0, "suffix:°") var facing_deg: float = 0.0
## Which spawn-telegraph effect plays at this spawn point before the monster
## appears. Only one exists today — arena_scene.gd's _play_spawn_telegraph_fx()
## is the one place to extend when a second is added; matches against these
## same string ids. Same "Label:value" leak-sanitizing setter as kind above.
@export_enum("Classic Beam:classic_beam") var spawn_animation: String = "classic_beam":
	set(value):
		spawn_animation = value.substr(value.rfind(":") + 1) if value.contains(":") else value
