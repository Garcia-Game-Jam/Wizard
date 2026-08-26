class_name SpellRegistry
extends Node

## Resolves spell ids to SpellDefinition resources for tomes and spellbook.

@export var spells: Array[Resource] = []


func _ready() -> void:
	add_to_group("spell_registry")


func get_spell(spell_id: String) -> SpellDefinition:
	for spell in spells:
		if spell is SpellDefinition and spell.id == spell_id:
			return spell
	return null


func get_all_spells() -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	for spell in spells:
		if spell is SpellDefinition:
			result.append(spell)
	return result
