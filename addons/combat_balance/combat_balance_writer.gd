@tool
extends RefCounted

## Writes Combat Balance dock edits back onto authored .tscn / .tres files.

const PLAYER_SCENE := "res://scenes/characters/player.tscn"
const WARD_SCENE := "res://scenes/spells/ward/ward.tscn"
const FIREBALL_SCENE := "res://scenes/spells/fireball/fireball.tscn"


static func format_float(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%.1f" % value
	return "%.2f" % snappedf(value, 0.01)


static func patch_tscn_float(path: String, node_name: String, prop: String, value: float) -> bool:
	if not FileAccess.file_exists(path):
		push_error("Combat balance: missing %s" % path)
		return false
	var raw := FileAccess.get_file_as_string(path)
	var nl := "\n"
	if raw.contains("\r\n"):
		nl = "\r\n"
	var lines := raw.split(nl)
	var header := '[node name="%s"' % node_name
	var in_block := false
	var found := false
	var insert_at := -1
	for i in lines.size():
		var line := str(lines[i])
		if line.begins_with("[node "):
			if in_block and not found and insert_at >= 0:
				lines.insert(insert_at + 1, "%s = %s" % [prop, format_float(value)])
				found = true
				break
			in_block = line.begins_with(header)
			if in_block:
				insert_at = i
				found = false
			continue
		if in_block and line.strip_edges().begins_with("%s =" % prop):
			lines[i] = "%s = %s" % [prop, format_float(value)]
			found = true
			break
	if in_block and not found and insert_at >= 0:
		lines.insert(insert_at + 1, "%s = %s" % [prop, format_float(value)])
		found = true
	if not found:
		push_error("Combat balance: no node %s in %s" % [node_name, path])
		return false
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("Combat balance: cannot write %s" % path)
		return false
	out.store_string(nl.join(lines))
	return true


static func save_spell_resource(spell: Resource) -> bool:
	var path := spell.resource_path
	if path.is_empty():
		push_error("Combat balance: spell has no resource_path")
		return false
	return ResourceSaver.save(spell, path) == OK


## Player, monster, and summon scenes all author max_health on their Health child.
static func apply_max_health(scene_path: String, value: float) -> bool:
	return patch_tscn_float(scene_path, "Health", "max_health", value)


static func apply_monster(path: String, node_name: String, field: String, value: float) -> bool:
	return patch_tscn_float(path, node_name, field, value)


static func apply_spell_damage(spell: Resource, value: float) -> bool:
	spell.set("damage", value)
	var ok := save_spell_resource(spell)
	if str(spell.get("id")) == "fireball":
		ok = patch_tscn_float(FIREBALL_SCENE, "Fireball", "hit_damage", value) and ok
	return ok


static func apply_spell_cooldown(spell: Resource, value: float) -> bool:
	spell.set("cooldown_sec", value)
	return save_spell_resource(spell)


static func apply_spell_charge(spell: Resource, value: float) -> bool:
	if str(spell.get("id")) == "fireball":
		return patch_tscn_float(FIREBALL_SCENE, "Fireball", "charge_time_sec", value)
	spell.set("charge_time_sec", value)
	return save_spell_resource(spell)


static func apply_spell_shatter_scale(spell: Resource, value: float) -> bool:
	spell.set("shatter_regen_scale", maxf(value, 1.0))
	return save_spell_resource(spell)


static func apply_spell_max_health(spell: Resource, value: float) -> bool:
	spell.set("max_health", maxf(value, 0.0))
	var ok := save_spell_resource(spell)
	if str(spell.get("id")) == "ward":
		ok = patch_tscn_float(WARD_SCENE, "Ward", "block_hp", value) and ok
	return ok


static func apply_spell_regen_delay(spell: Resource, value: float) -> bool:
	var next := maxf(value, 0.0)
	spell.set("regen_delay_sec", next)
	var ok := save_spell_resource(spell)
	if str(spell.get("id")) == "ward":
		ok = patch_tscn_float(WARD_SCENE, "Ward", "regen_delay_sec", next) and ok
	return ok


static func apply_spell_regen_per_sec(spell: Resource, value: float) -> bool:
	var next := maxf(value, 0.0)
	spell.set("regen_per_sec", next)
	var ok := save_spell_resource(spell)
	if str(spell.get("id")) == "ward":
		ok = patch_tscn_float(WARD_SCENE, "Ward", "regen_per_sec", next) and ok
	return ok


static func apply_player_ward_block(value: float) -> bool:
	return patch_tscn_float(WARD_SCENE, "Ward", "block_hp", value)


static func apply_charger_ward_block(value: float) -> bool:
	return patch_tscn_float(
		"res://scenes/monsters/charger.tscn", "ChargeWard", "shield_hit_points", value
	)


static func apply_projectile_damage(path: String, node_name: String, value: float) -> bool:
	return patch_tscn_float(path, node_name, "hit_damage", value)


static func rescan_filesystem(filesystem: Object = null) -> void:
	if filesystem != null and filesystem.has_method("scan"):
		filesystem.call("scan")
