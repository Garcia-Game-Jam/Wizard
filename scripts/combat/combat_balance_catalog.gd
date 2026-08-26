@tool
class_name CombatBalanceCatalog
extends RefCounted

## Authored combat numbers for the editor Combat Balance dock.

const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")
const WardShieldScript := preload("res://scripts/spells/ward_shield.gd")
const ChargerWardAbilityScript := preload(
	"res://scripts/monsters/abilities/charger_ward_ability.gd"
)
const EmberLobProjectileScript := preload(
	"res://scripts/monsters/abilities/ember_lob_projectile.gd"
)
const AshIceProjectileScript := preload("res://scripts/monsters/abilities/ash_ice_projectile.gd")
const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)
const HealthScript := preload("res://scripts/combat/health.gd")

const PLAYER_SCENE := "res://scenes/characters/playable_character.tscn"
const WARD_SCENE := "res://scenes/spells/ward/ward.tscn"
const CHARGER_SCENE := "res://scenes/monsters/charger.tscn"
const EMBER_LOB_SCENE := "res://scenes/monsters/abilities/ember_lob_projectile.tscn"
const ASH_ICE_SCENE := "res://scenes/monsters/abilities/ash_ice_projectile.tscn"
const ASH_FROST_SCENE := "res://scenes/monsters/abilities/ash_frost_breath_cloud.tscn"

const MONSTER_SCENES: Array[Dictionary] = [
	{"name": "Wretch", "path": "res://scenes/monsters/wretch.tscn"},
	{"name": "Ash Wretch", "path": "res://scenes/monsters/ash_wretch.tscn"},
	{"name": "Ember Wretch", "path": "res://scenes/monsters/ember_wretch.tscn"},
	{"name": "Charger", "path": "res://scenes/monsters/charger.tscn"},
	{"name": "Wretch Rat", "path": "res://scenes/monsters/wretch_rat.tscn"},
]


static func monster_roster() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in MONSTER_SCENES:
		var packed: PackedScene = load(str(entry["path"])) as PackedScene
		if packed == null:
			continue
		var node: Node = packed.instantiate()
		var touch := 0.0
		if "touch_damage" in node:
			touch = float(node.get("touch_damage"))
		var row := {
			"name": str(entry["name"]),
			"path": str(entry["path"]),
			"node": node.name,
			"max_health": _authored_max_health(node),
			"touch_dps": touch,
		}
		node.free()
		rows.append(row)
	return rows


static func player_max_health() -> float:
	var packed: PackedScene = load(PLAYER_SCENE) as PackedScene
	if packed == null:
		return HealthScript.DEFAULT_MAX_HEALTH
	var root: Node = packed.instantiate()
	var hp := _authored_max_health(root)
	root.free()
	return hp


## Every character scene authors one Health child — players and monsters alike.
static func _authored_max_health(character: Node) -> float:
	var health := character.get_node_or_null("Health") as HealthScript
	if health == null:
		return HealthScript.DEFAULT_MAX_HEALTH
	return health.max_health


static func spell_rows(spells: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for item in spells:
		var spell := _as_spell_def(item)
		if spell == null:
			continue
		var dmg := _spell_damage(spell)
		var interval := _spell_interval(spell)
		var dps := 0.0
		if interval > 0.001:
			dps = dmg / interval
		var spell_id := str(spell.get("id"))
		var is_ward := spell_id == "ward" or str(spell.get("effect_id")) == "ward"
		var regen_delay := float(spell.get("regen_delay_sec"))
		var regen_rate := float(spell.get("regen_per_sec"))
		if is_ward:
			regen_delay = _scene_float(
				WARD_SCENE, "Ward", "regen_delay_sec", regen_delay
			)
			regen_rate = _scene_float(WARD_SCENE, "Ward", "regen_per_sec", regen_rate)
		rows.append(
			{
				"id": spell_id,
				"name": str(spell.get("display_name")),
				"path": spell.resource_path,
				"damage": dmg,
				"cooldown_sec": float(spell.get("cooldown_sec")),
				"charge_sec": _spell_charge(spell),
				"max_health": float(spell.get("max_health")),
				"regen_delay_sec": regen_delay,
				"regen_per_sec": regen_rate,
				"shatter_regen_scale": float(spell.get("shatter_regen_scale")),
				"is_ward": is_ward,
				"interval_sec": interval,
				"dps": dps,
			}
		)
	return rows


static func load_all_spell_defs() -> Array:
	return load_spell_defs_from_paths(_discover_spell_tres_paths())


static func load_spell_defs_from_paths(paths: PackedStringArray) -> Array:
	var spells: Array = []
	var seen: Dictionary = {}
	for path in paths:
		var clean := str(path).replace("\\", "/")
		if seen.has(clean):
			continue
		seen[clean] = true
		var spell := _load_spell_def(clean)
		if spell != null:
			spells.append(spell)
	spells.sort_custom(
		func(a: Resource, b: Resource) -> bool: return str(a.get("id")) < str(b.get("id"))
	)
	return spells


static func _discover_spell_tres_paths() -> PackedStringArray:
	var out := PackedStringArray()
	_scan_for_tres(SpellDefinitionScript.SPELLS_ROOT, out, 0)
	return out


static func _scan_for_tres(dir_path: String, out: PackedStringArray, depth: int) -> void:
	if depth > 3:
		return
	var path := dir_path if dir_path.ends_with("/") else dir_path + "/"
	for raw in _dir_entries(path):
		var entry := str(raw).replace("\\", "/")
		var is_dir := entry.ends_with("/")
		var name := entry.trim_suffix("/")
		if name.is_empty() or name.begins_with(".") or name.begins_with("_"):
			continue
		if name.ends_with(".tres"):
			out.append(path + name)
			continue
		if is_dir or _is_dir(path + name):
			_scan_for_tres(path + name, out, depth + 1)


static func _dir_entries(path: String) -> PackedStringArray:
	var entries := PackedStringArray()
	if ResourceLoader.has_method("list_directory"):
		entries = ResourceLoader.list_directory(path)
	if not entries.is_empty():
		return entries
	for folder in DirAccess.get_directories_at(path):
		entries.append("%s/" % str(folder).trim_suffix("/"))
	for file_name in DirAccess.get_files_at(path):
		entries.append(str(file_name))
	if not entries.is_empty():
		return entries
	var dir := DirAccess.open(path)
	if dir == null:
		return entries
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			entries.append("%s/" % entry.trim_suffix("/"))
		else:
			entries.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return entries


static func _is_dir(path: String) -> bool:
	return DirAccess.open(path) != null


static func _spell_damage(spell: Resource) -> float:
	var dmg := float(spell.get("damage"))
	if dmg > 0.0:
		return dmg
	if str(spell.get("effect_id")) == "fireball":
		return FireballProjectileScript.DEFAULT_HIT_DAMAGE
	return 0.0


static func _spell_charge(spell: Resource) -> float:
	if int(spell.get("cast_mode")) == SpellDefinitionScript.CastMode.CHANNEL:
		return 0.0
	if str(spell.get("effect_id")) == "fireball":
		return FireballProjectileScript.authored_charge_time_sec()
	return maxf(float(spell.get("charge_time_sec")), 0.0)


static func _spell_interval(spell: Resource) -> float:
	var ammo_max := int(spell.get("ammo_max"))
	var ammo_refill := float(spell.get("ammo_refill_sec"))
	if ammo_max > 0 and ammo_refill > 0.0:
		return ammo_refill
	var charge := _spell_charge(spell)
	var cd := maxf(float(spell.get("cooldown_sec")), 0.0)
	if bool(spell.get("require_full_charge")):
		return maxf(charge, 0.05)
	if int(spell.get("cast_mode")) == SpellDefinitionScript.CastMode.CHANNEL:
		return maxf(cd, 0.05)
	if cd > 0.0 or charge > 0.0:
		return maxf(cd, charge)
	return 0.05


static func _load_spell_def(path: String) -> Resource:
	if path.is_empty():
		return null
	var loaded: Resource = ResourceLoader.load(path) as Resource
	if loaded == null:
		loaded = load(path) as Resource
	return _as_spell_def(loaded)


static func _as_spell_def(res: Variant) -> Resource:
	var resource := res as Resource
	if resource == null:
		return null
	var script: Script = resource.get_script() as Script
	if script == SpellDefinitionScript:
		return resource
	var script_path := ""
	if script != null:
		script_path = str(script.resource_path).replace("\\", "/")
	if script_path.ends_with("spell_definition.gd"):
		return resource
	var res_path := str(resource.resource_path).replace("\\", "/")
	if res_path.contains("/scenes/spells/") and res_path.ends_with(".tres"):
		if not str(resource.get("id")).is_empty():
			return resource
	return null


static func _scene_float(path: String, node_name: String, prop: String, fallback: float) -> float:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return fallback
	var root: Node = packed.instantiate()
	var target: Node = root if root.name == node_name else root.find_child(node_name, true, false)
	var value := fallback
	if target != null and prop in target:
		value = float(target.get(prop))
	root.free()
	return value


static func ward_rows() -> Array[Dictionary]:
	var player_block := _scene_float(
		WARD_SCENE, "Ward", "block_hp", WardShieldScript.DEFAULT_BLOCK_HP
	)
	return [
		{
			"name": "Player / Ash ward",
			"kind": "player_ward",
			"block_hp": player_block,
		},
		{
			"name": "Charger ward",
			"kind": "charger_ward",
			"block_hp": _scene_float(
				CHARGER_SCENE,
				"ChargeWard",
				"shield_hit_points",
				ChargerWardAbilityScript.default_shield_hit_points(),
			),
		},
	]


static func monster_spell_kits() -> Array[Dictionary]:
	var kits: Array[Dictionary] = []
	for entry in MONSTER_SCENES:
		var packed: PackedScene = load(str(entry["path"])) as PackedScene
		if packed == null:
			continue
		var node: Node = packed.instantiate()
		var spells := _ability_rows_from_root(node, str(entry["path"]))
		node.free()
		if spells.is_empty():
			continue
		kits.append(
			{
				"name": str(entry["name"]),
				"path": str(entry["path"]),
				"spells": spells,
			}
		)
	return kits


static func monster_ability_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for kit in monster_spell_kits():
		for spell in kit["spells"]:
			rows.append(spell)
	return rows


static func _ability_rows_from_root(root: Node, monster_path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var abilities := root.get_node_or_null("Abilities")
	if abilities == null:
		return rows
	for child in abilities.get_children():
		var ability := child as Node
		if ability == null or not ("cooldown_sec" in ability):
			continue
		rows.append(_ability_row(ability, monster_path))
	return rows


static func _ability_row(ability: Node, monster_path: String) -> Dictionary:
	var ability_id := ability.name
	if "ability_id" in ability:
		ability_id = str(ability.get("ability_id"))
	var display := ability.name
	if "display_name" in ability:
		display = str(ability.get("display_name"))
	if display.is_empty() or display == "Ability":
		display = ability.name
	var cooldown := float(ability.get("cooldown_sec"))
	var windup := 0.0
	if "windup_sec" in ability:
		windup = float(ability.get("windup_sec"))
	var damage := 0.0
	var damage_kind := ""
	var damage_path := ""
	var damage_node := ""
	var damage_prop := "hit_damage"
	var max_health := 0.0
	var is_ward := false
	var regen_delay := 0.0
	var regen_rate := 0.0
	var shatter := 1.0
	match ability_id:
		"ember_lob":
			damage_kind = "projectile"
			damage_path = EMBER_LOB_SCENE
			damage_node = "EmberLobProjectile"
			damage = _scene_float(
				damage_path, damage_node, "hit_damage", EmberLobProjectileScript.HIT_DAMAGE
			)
		"ash_ice":
			damage_kind = "projectile"
			damage_path = ASH_ICE_SCENE
			damage_node = "AshIceProjectile"
			damage = _scene_float(
				damage_path, damage_node, "hit_damage", AshIceProjectileScript.HIT_DAMAGE
			)
		"ash_frost_breath":
			damage_kind = "projectile"
			damage_path = ASH_FROST_SCENE
			damage_node = "AshFrostBreathCloud"
			damage = _scene_float(
				damage_path,
				damage_node,
				"hit_damage",
				AshFrostBreathFlightScript.HIT_DAMAGE,
			)
		"ember_dash":
			damage_kind = "ability"
			damage_prop = "burn_dps"
			damage = 0.0
			if "burn_dps" in ability:
				damage = float(ability.get("burn_dps"))
		"charger_ward":
			is_ward = true
			max_health = ChargerWardAbilityScript.default_shield_hit_points()
			if "shield_hit_points" in ability:
				max_health = float(ability.get("shield_hit_points"))
			regen_delay = _scene_float(
				WARD_SCENE, "Ward", "regen_delay_sec", WardShieldScript.DEFAULT_REGEN_DELAY_SEC
			)
			regen_rate = _scene_float(
				WARD_SCENE, "Ward", "regen_per_sec", WardShieldScript.DEFAULT_REGEN_PER_SEC
			)
		"ash_ward":
			is_ward = true
			max_health = _scene_float(
				WARD_SCENE, "Ward", "block_hp", WardShieldScript.DEFAULT_BLOCK_HP
			)
			regen_delay = _scene_float(
				WARD_SCENE, "Ward", "regen_delay_sec", WardShieldScript.DEFAULT_REGEN_DELAY_SEC
			)
			regen_rate = _scene_float(
				WARD_SCENE, "Ward", "regen_per_sec", WardShieldScript.DEFAULT_REGEN_PER_SEC
			)
	var interval := maxf(cooldown, windup)
	if interval <= 0.001:
		interval = 0.05
	var dps := damage / interval if damage > 0.0 else 0.0
	return {
		"id": ability_id,
		"name": display,
		"monster_path": monster_path,
		"node": ability.name,
		"damage": damage,
		"damage_kind": damage_kind,
		"damage_path": damage_path,
		"damage_node": damage_node,
		"damage_prop": damage_prop,
		"cooldown_sec": cooldown,
		"charge_sec": windup,
		"max_health": max_health,
		"regen_delay_sec": regen_delay,
		"regen_per_sec": regen_rate,
		"shatter_regen_scale": shatter,
		"is_ward": is_ward,
		"interval_sec": interval,
		"dps": dps,
	}


static func ward_break_consequence() -> String:
	var scale := 2.0
	for row in spell_rows(load_all_spell_defs()):
		if bool(row.get("is_ward", false)):
			scale = float(row["shatter_regen_scale"])
			break
	return "Shattered ward: next regen delay ×%s" % _fmt_scale(scale)


static func _fmt_scale(scale: float) -> String:
	if is_equal_approx(scale, roundf(scale)):
		return "%.0f" % scale
	return "%.2f" % snappedf(scale, 0.01)


static func format_report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Combat balance[/b]  (authored)")
	lines.append("")
	lines.append("[b]Health pools[/b]")
	lines.append("Player max HP: %.0f" % player_max_health())
	for row in monster_roster():
		lines.append(
			"%s  max %.0f  touch DPS %.1f"
			% [row["name"], row["max_health"], row["touch_dps"]]
		)
	lines.append("")
	lines.append("[b]Spells (base damage · fire interval · DPS)[/b]")
	for row in spell_rows(load_all_spell_defs()):
		var line := (
			"%s  dmg %.1f  rate every %.2fs  DPS %.1f"
			% [row["name"], row["damage"], row["interval_sec"], row["dps"]]
		)
		if bool(row.get("is_ward", false)):
			line += "  hp %.0f" % float(row["max_health"])
			line += "  regen %.0f/s after %.1fs" % [
				float(row["regen_per_sec"]),
				float(row["regen_delay_sec"]),
			]
			line += "  shatter regen ×%s" % _fmt_scale(float(row["shatter_regen_scale"]))
		lines.append(line)
	lines.append("")
	lines.append("[b]Monster spells[/b]")
	for kit in monster_spell_kits():
		lines.append("%s" % kit["name"])
		for row in kit["spells"]:
			var line := (
				"  %s  dmg %.1f  rate every %.2fs  DPS %.1f"
				% [row["name"], row["damage"], row["interval_sec"], row["dps"]]
			)
			if bool(row.get("is_ward", false)):
				line += "  hp %.0f" % float(row["max_health"])
			lines.append(line)
	lines.append("")
	lines.append("[b]Ward block[/b]")
	for row in ward_rows():
		lines.append("%s  block %.0f HP" % [row["name"], row["block_hp"]])
	lines.append("")
	lines.append("[b]Ward break consequence[/b]")
	lines.append(ward_break_consequence())
	return "\n".join(lines)
