class_name SpellMana
extends RefCounted

## Cast costs and drain rates for the armed-spell mana pool.

const MANA_MAX := 100.0
const DRAIN_PER_SEC := 2.0
const EXTRA_DRAIN_LIGHT_FOLLOW := 1.0


static func cast_cost(spell: SpellDefinition) -> float:
	if spell == null:
		return 10.0
	match spell.id:
		"fireball", "flare":
			return 20.0
		"ward":
			return 35.0
		"light", "follow":
			return 0.0
		_:
			return 10.0


static func extra_drain_per_sec(spell: SpellDefinition) -> float:
	if spell == null:
		return 0.0
	if spell.id == "light" or spell.id == "follow":
		return EXTRA_DRAIN_LIGHT_FOLLOW
	return 0.0


static func drain_rate(spell: SpellDefinition) -> float:
	return DRAIN_PER_SEC + extra_drain_per_sec(spell)
