class_name ShopRandomizer
extends RefCounted

## Picks which ShopDisplayEntry resources (see shop_display_entry.gd) fill a
## shop's bays, based on how many players are in the lobby. Bay 0 is always
## the door (ShopStructure's default door_bay_indices) and is never used —
## every slot list below only ever names bays 1-7.
##
## Callers own the actual candidate pools: generate_displays() takes the
## live spell id list (from SpellRegistry.get_all_spells(), which needs a
## SceneTree to look up — this class deliberately stays tree-free so it can
## be unit-tested/called from anywhere) and draws artifacts from
## PLACEHOLDER_ARTIFACT_IDS below since no real artifact catalog exists yet
## (see artifact_display_entry.gd's own doc comment on that).

const SpellDisplayEntryScript := preload("res://scripts/arena/spell_display_entry.gd")
const ArtifactDisplayEntryScript := preload("res://scripts/arena/artifact_display_entry.gd")
const HealDisplayEntryScript := preload("res://scripts/arena/heal_display_entry.gd")

const MIN_PLAYERS := 1
const MAX_PLAYERS := 4

## Stand-in until a real artifact catalog exists — see this file's top doc
## comment and artifact_display_entry.gd.
const PLACEHOLDER_ARTIFACT_IDS: Array[String] = [
	"ember_ring", "oak_charm", "silver_locket", "moss_cloak", "iron_talisman", "glass_compass",
]

## Every candidate's selection weight today — no rarity/tier system yet, so
## _pick_weighted() below reduces to a uniform sample without replacement.
## Kept as a named constant (rather than inlined as 1.0) so a future per-id
## weight lookup has an obvious place to plug into _pick_weighted().
const _WEIGHT := 1.0


## Builds the full set of pedestal entries for one shop, sized to
## `player_count` (clamped to [MIN_PLAYERS, MAX_PLAYERS]). `spell_ids` is the
## candidate pool spell displays are drawn from — pass every currently known
## spell id (equal weight each); fewer displays than requested are produced
## if the pool runs short.
static func generate_displays(
	player_count: int, spell_ids: Array[String]
) -> Array[ShopDisplayEntry]:
	var config := _config_for_player_count(player_count)
	var slots: Array[int] = []
	for slot in config["slots"]:
		slots.append(int(slot))
	slots.shuffle()

	var kinds: Array[String] = []
	for i in int(config["spell_count"]):
		kinds.append("spell")
	for i in int(config["artifact_count"]):
		kinds.append("artifact")
	for i in int(config["heal_count"]):
		kinds.append("heal")

	var picked_spell_ids := _pick_weighted(spell_ids, int(config["spell_count"]))
	var picked_artifact_ids := _pick_weighted(PLACEHOLDER_ARTIFACT_IDS, int(config["artifact_count"]))

	var displays: Array[ShopDisplayEntry] = []
	var spell_cursor := 0
	var artifact_cursor := 0
	for i in kinds.size():
		var slot := slots[i]
		match kinds[i]:
			"spell":
				if spell_cursor >= picked_spell_ids.size():
					continue
				var spell_entry := SpellDisplayEntryScript.new()
				spell_entry.bay_index = slot
				spell_entry.spell_id = picked_spell_ids[spell_cursor]
				spell_cursor += 1
				displays.append(spell_entry)
			"artifact":
				if artifact_cursor >= picked_artifact_ids.size():
					continue
				var artifact_entry := ArtifactDisplayEntryScript.new()
				artifact_entry.bay_index = slot
				artifact_entry.item_id = picked_artifact_ids[artifact_cursor]
				artifact_cursor += 1
				displays.append(artifact_entry)
			"heal":
				var heal_entry := HealDisplayEntryScript.new()
				heal_entry.bay_index = slot
				displays.append(heal_entry)
	return displays


static func _config_for_player_count(player_count: int) -> Dictionary:
	match clampi(player_count, MIN_PLAYERS, MAX_PLAYERS):
		1:
			return {"slots": [3, 4, 5], "spell_count": 1, "artifact_count": 1, "heal_count": 1}
		2:
			return {
				"slots": [2, 3, 4, 5, 6], "spell_count": 2, "artifact_count": 2, "heal_count": 1
			}
		3:
			return {
				"slots": [1, 2, 3, 4, 5, 6], "spell_count": 3, "artifact_count": 2, "heal_count": 1
			}
		_:
			return {
				"slots": [1, 2, 3, 4, 5, 6, 7],
				"spell_count": 4,
				"artifact_count": 2,
				"heal_count": 1,
			}


## Picks up to `count` distinct ids from `ids`, weighted by probability ∝
## weight (_WEIGHT above — currently the same for every id). Returns fewer
## than `count` if `ids` has fewer entries than requested.
static func _pick_weighted(ids: Array[String], count: int) -> Array[String]:
	var pool := ids.duplicate()
	var picked: Array[String] = []
	while not pool.is_empty() and picked.size() < count:
		var total_weight := float(pool.size()) * _WEIGHT
		var roll := randf() * total_weight
		var cursor := 0.0
		var chosen_index := pool.size() - 1
		for i in pool.size():
			cursor += _WEIGHT
			if roll <= cursor:
				chosen_index = i
				break
		picked.append(pool[chosen_index])
		pool.remove_at(chosen_index)
	return picked
