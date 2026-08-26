class_name CharacterSpellLoadout
extends Node

## Per-character known spells, split into starting kit vs spells learned in-run.
## Most casting is gated by voice recognition; spells with cooldown_sec use timers.

signal spell_learned(spell_id: String)
signal spell_unlearned(spell_id: String)
signal loadout_changed()

const SOURCE_STARTING := "starting"
const SOURCE_TOME := "tome"
const WARD_SHATTER_REGEN_SCALE := 2.0
const FlareEffectScript := preload("res://scripts/spells/flare_effect.gd")
const WardRuntimeScript := preload("res://scripts/spells/ward_runtime.gd")

var _spell_defs: Dictionary = {}
## spell_id -> { "learned_at": int }
var _starting: Dictionary = {}
## spell_id -> { "learned_at": int, "source": String }
var _learned: Dictionary = {}
## spell_id -> cooldown end time (msec)
var _cooldown_until_msec: Dictionary = {}
## spell_id -> { "count": int, "next_msec": int }
var _ammo: Dictionary = {}
var _ward_runtime: Resource = null


func configure(spells: Array[SpellDefinition]) -> void:
	_spell_defs.clear()
	for spell in spells:
		if spell != null:
			_spell_defs[spell.id] = spell
	_ward_runtime = WardRuntimeScript.new()
	_ward_runtime.seed_from_spell(get_spell_definition("ward"))


func reset() -> void:
	_starting.clear()
	_learned.clear()
	_cooldown_until_msec.clear()
	_ammo.clear()
	if _ward_runtime != null:
		_ward_runtime.seed_from_spell(get_spell_definition("ward"))
	loadout_changed.emit()


func is_on_cooldown(spell_id: String) -> bool:
	if _ammo_max(spell_id) > 0:
		return ammo_count(spell_id) <= 0
	return remaining_cooldown_sec(spell_id) > 0.0


func remaining_cooldown_sec(spell_id: String) -> float:
	if _ammo_max(spell_id) > 0:
		if ammo_count(spell_id) > 0:
			return 0.0
		return remaining_ammo_refill_sec(spell_id)
	if _is_ward_id(spell_id) and _ward_runtime != null:
		return _ward_runtime.remaining_cooldown_sec()
	if not _cooldown_until_msec.has(spell_id):
		return 0.0
	var remaining_msec: int = int(_cooldown_until_msec[spell_id]) - Time.get_ticks_msec()
	if remaining_msec <= 0:
		_cooldown_until_msec.erase(spell_id)
		return 0.0
	return float(remaining_msec) / 1000.0


func start_cooldown(spell_id: String) -> void:
	if _ammo_max(spell_id) > 0:
		spend_ammo(spell_id)
		return
	var spell: SpellDefinition = get_spell_definition(spell_id)
	if spell == null:
		return
	var cd := maxf(spell.cooldown_sec, 0.0)
	if cd <= 0.0:
		return
	if _is_ward_id(spell_id) and _ward_runtime != null:
		_ward_runtime.cooldown_until_msec = (
			Time.get_ticks_msec() + int(round(cd * 1000.0))
		)
		return
	_cooldown_until_msec[spell_id] = Time.get_ticks_msec() + int(round(cd * 1000.0))


func arm_ward_shatter_penalty() -> void:
	if _ward_runtime == null:
		_ward_runtime = WardRuntimeScript.new()
		_ward_runtime.seed_from_spell(get_spell_definition("ward"))
	var scale := WARD_SHATTER_REGEN_SCALE
	var spell: SpellDefinition = get_spell_definition("ward")
	if spell != null:
		scale = maxf(spell.shatter_regen_scale, 1.0)
	_ward_runtime.shatter_regen_scale = scale


func is_ward_shatter_penalty_armed() -> bool:
	return _ward_runtime != null and _ward_runtime.shatter_regen_scale > 1.001


func get_ward_runtime() -> Resource:
	return _ward_runtime


func ammo_max(spell_id: String) -> int:
	return _ammo_max(spell_id)


func ammo_refill_sec(spell_id: String) -> float:
	if spell_id == "flare":
		return FlareEffectScript.authored_ammo_refill_sec()
	var spell: SpellDefinition = get_spell_definition(spell_id)
	if spell == null:
		return 0.0
	return maxf(spell.ammo_refill_sec, 0.0)


func ammo_count(spell_id: String) -> int:
	if _ammo_max(spell_id) <= 0:
		return 0
	_tick_ammo(spell_id)
	return int(_ammo[spell_id]["count"])


func remaining_ammo_refill_sec(spell_id: String) -> float:
	if _ammo_max(spell_id) <= 0:
		return 0.0
	_tick_ammo(spell_id)
	var entry: Dictionary = _ammo[spell_id]
	if int(entry["count"]) >= _ammo_max(spell_id):
		return 0.0
	var next_msec := int(entry["next_msec"])
	if next_msec <= 0:
		return 0.0
	return maxf(0.0, float(next_msec - Time.get_ticks_msec()) / 1000.0)


func spend_ammo(spell_id: String) -> bool:
	if _ammo_max(spell_id) <= 0:
		return true
	_tick_ammo(spell_id)
	var entry: Dictionary = _ammo[spell_id]
	var count := int(entry["count"])
	if count <= 0:
		return false
	entry["count"] = count - 1
	if int(entry["next_msec"]) <= 0:
		var refill_msec := _ammo_refill_msec(spell_id)
		if refill_msec > 0:
			entry["next_msec"] = Time.get_ticks_msec() + refill_msec
	return true


func _ammo_max(spell_id: String) -> int:
	if spell_id == "flare":
		return FlareEffectScript.authored_ammo_max()
	var spell: SpellDefinition = get_spell_definition(spell_id)
	if spell == null:
		return 0
	return maxi(spell.ammo_max, 0)


func _ammo_refill_msec(spell_id: String) -> int:
	return int(round(ammo_refill_sec(spell_id) * 1000.0))


func _tick_ammo(spell_id: String) -> void:
	var max_count := _ammo_max(spell_id)
	if max_count <= 0:
		_ammo.erase(spell_id)
		return
	if not _ammo.has(spell_id):
		_ammo[spell_id] = {"count": max_count, "next_msec": 0}
		return
	var entry: Dictionary = _ammo[spell_id]
	var count := int(entry["count"])
	if count >= max_count:
		entry["count"] = max_count
		entry["next_msec"] = 0
		return
	var refill_msec := _ammo_refill_msec(spell_id)
	if refill_msec <= 0:
		return
	var now := Time.get_ticks_msec()
	var next_msec := int(entry["next_msec"])
	if next_msec <= 0:
		entry["next_msec"] = now + refill_msec
		return
	while count < max_count and now >= next_msec:
		count += 1
		if count >= max_count:
			next_msec = 0
			break
		next_msec += refill_msec
	entry["count"] = count
	entry["next_msec"] = next_msec


func knows(spell_id: String) -> bool:
	return _starting.has(spell_id) or _learned.has(spell_id)


func has_known_spells() -> bool:
	return not _starting.is_empty() or not _learned.is_empty()


## Grant the role starter kit. Spells already known are left alone.
func apply_starting_spells(spell_ids: Array[String]) -> void:
	var changed := false
	for spell_id in spell_ids:
		if _add_starting_spell(spell_id):
			changed = true
			spell_learned.emit(spell_id)
	if changed:
		loadout_changed.emit()


## Learn a spell during the run (tomes, etc.). Source "starting" goes into the starter set.
func learn_spell(spell_id: String, source: String = "") -> bool:
	if spell_id.is_empty() or not _spell_defs.has(spell_id):
		return false
	if knows(spell_id):
		return false
	if source == SOURCE_STARTING:
		_add_starting_spell(spell_id)
	else:
		_learned[spell_id] = {
			"learned_at": Time.get_ticks_msec(),
			"source": source if not source.is_empty() else SOURCE_TOME,
		}
	spell_learned.emit(spell_id)
	loadout_changed.emit()
	return true


func unlearn_spell(spell_id: String) -> void:
	var removed := false
	if _starting.has(spell_id):
		_starting.erase(spell_id)
		removed = true
	if _learned.has(spell_id):
		_learned.erase(spell_id)
		removed = true
	if not removed:
		return
	spell_unlearned.emit(spell_id)
	loadout_changed.emit()


func get_starting_spell_ids() -> Array[String]:
	return _sorted_ids(_starting)


func get_learned_spell_ids() -> Array[String]:
	return _sorted_ids(_learned)


func get_known_spell_ids() -> Array[String]:
	var seen: Dictionary = {}
	var ids: Array[String] = []
	for spell_id in _starting.keys():
		seen[spell_id] = true
		ids.append(spell_id)
	for spell_id in _learned.keys():
		if seen.has(spell_id):
			continue
		ids.append(spell_id)
	ids.sort()
	return ids


func get_starting_spells() -> Array[SpellDefinition]:
	return _defs_for_ids(get_starting_spell_ids())


func get_learned_spells() -> Array[SpellDefinition]:
	return _defs_for_ids(get_learned_spell_ids())


func get_known_spells() -> Array[SpellDefinition]:
	return _defs_for_ids(get_known_spell_ids())


func get_spell_definition(spell_id: String) -> SpellDefinition:
	return _spell_defs.get(spell_id)


func _is_ward_id(spell_id: String) -> bool:
	if spell_id == "ward":
		return true
	var spell: SpellDefinition = get_spell_definition(spell_id)
	return spell != null and spell.effect_id == "ward"


func _add_starting_spell(spell_id: String) -> bool:
	if spell_id.is_empty() or not _spell_defs.has(spell_id):
		return false
	if knows(spell_id):
		return false
	_starting[spell_id] = {"learned_at": Time.get_ticks_msec()}
	return true


func _sorted_ids(bucket: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for spell_id in bucket.keys():
		ids.append(spell_id)
	ids.sort()
	return ids


func _defs_for_ids(ids: Array[String]) -> Array[SpellDefinition]:
	var spells: Array[SpellDefinition] = []
	for spell_id in ids:
		var spell: SpellDefinition = get_spell_definition(spell_id)
		if spell != null:
			spells.append(spell)
	return spells
