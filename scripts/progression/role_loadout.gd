class_name RoleLoadout
extends RefCounted

## Starter kit for the apprentice caster.

const APPRENTICE_STARTER_SPELLS: Array[String] = [
	"fireball",
	"stone_throw",
	"flare",
	"ward",
	"haste",
	"light",
	"light_ball",
	"target",
	"pull",
	"follow",
	"stop",
	"dispell",
]


static func role_label(_role: int = 0) -> String:
	return "Apprentice"


static func get_starting_spell_ids(_role: int = 0) -> Array[String]:
	return APPRENTICE_STARTER_SPELLS.duplicate()
