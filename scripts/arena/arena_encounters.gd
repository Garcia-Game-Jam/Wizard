class_name ArenaEncounters
extends RefCounted

## Week-1 dumps: three different packs, then three that want Ward.

const KIND_CHARGER := "charger"
const KIND_EMBER := "ember"
const KIND_ASH := "ash"

const UNLOCK_QUEUE: Array[String] = ["ward"]

const STARTER_SPELL_IDS: Array[String] = ["stone_throw"]

const COVER_RESTAGE_BASE := 0.5
const COVER_RESTAGE_STEP := 0.25
const COVER_HALF_XZ := 1.2
const COVER_SPAWN_CLEAR_M := COVER_HALF_XZ + 2.3

## Matches scenes/arena.tscn PlayerSpawn_* so restage cannot sit on a pad.
const PLAYER_SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(-4.0, 1.0, 14.0),
	Vector3(4.0, 1.0, 14.0),
	Vector3(-4.0, 1.0, 16.0),
	Vector3(4.0, 1.0, 16.0),
]

## ponytail: live pit is two PackedScenes. Preload them. When the roster is
## large enough that pit-enter hitchs, background-load a window instead.
const SCENE_BY_KIND := {
	KIND_CHARGER: preload("res://scenes/monsters/charger.tscn"),
	KIND_EMBER: preload("res://scenes/monsters/ember_wretch.tscn"),
	KIND_ASH: "res://scenes/monsters/evaluating/ash_wretch.tscn",
}


static func dump_for(encounter_index: int) -> Array[Dictionary]:
	var index := encounter_index % 6
	var dump: Array[Dictionary] = []
	match index:
		0:
			dump.append(_spawn(KIND_CHARGER, 0))
		1:
			dump.append(_spawn(KIND_EMBER, 1))
		2:
			dump.append(_spawn(KIND_CHARGER, 0))
			dump.append(_spawn(KIND_EMBER, 2))
		3:
			dump.append(_spawn(KIND_EMBER, 1))
			dump.append(_spawn(KIND_CHARGER, 3))
		4:
			dump.append(_spawn(KIND_CHARGER, 2))
			dump.append(_spawn(KIND_EMBER, 0))
		_:
			dump.append(_spawn(KIND_EMBER, 0))
			dump.append(_spawn(KIND_EMBER, 1))
			dump.append(_spawn(KIND_CHARGER, 3))
	return dump


static func cover_positions(encounter_index: int) -> Array[Vector3]:
	var index := encounter_index % 6
	var raw: Array[Vector3] = []
	match index:
		0:
			raw.append_array([Vector3(-6.0, 1.0, -4.0), Vector3(6.0, 1.0, 3.0), Vector3(0.0, 1.0, 8.0)])
		1:
			raw.append_array([Vector3(-8.0, 1.0, 2.0), Vector3(3.0, 1.0, -7.0), Vector3(7.0, 1.0, 7.0)])
		2:
			raw.append_array([Vector3(-4.0, 1.0, 0.0), Vector3(4.0, 1.0, 0.0), Vector3(0.0, 1.0, -8.0)])
		3:
			raw.append_array([Vector3(-7.0, 1.0, -7.0), Vector3(7.0, 1.0, -7.0), Vector3(0.0, 1.0, 6.0)])
		4:
			raw.append_array([Vector3(-9.0, 1.0, 0.0), Vector3(9.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0)])
		_:
			raw.append_array([Vector3(-5.0, 1.0, 5.0), Vector3(5.0, 1.0, 5.0), Vector3(0.0, 1.0, -6.0)])
	var safe: Array[Vector3] = []
	for pos in raw:
		safe.append(_safe_cover(pos))
	return safe


static func cover_restage_chance(misses: int) -> float:
	return minf(1.0, COVER_RESTAGE_BASE + float(maxi(misses, 0)) * COVER_RESTAGE_STEP)


static func should_restage_cover(encounter_index: int, roll: float, misses: int = 0) -> bool:
	if encounter_index <= 0:
		return false
	return roll < cover_restage_chance(misses)


static func pads_for(encounter_index: int) -> PackedInt32Array:
	var pads := PackedInt32Array()
	var seen: Dictionary = {}
	for entry in dump_for(encounter_index):
		var pad := int(entry.get("pad", 0))
		if seen.has(pad):
			continue
		seen[pad] = true
		pads.append(pad)
	return pads


static func cover_overlaps_player_spawn(pos: Vector3) -> bool:
	for spawn in PLAYER_SPAWN_POSITIONS:
		var delta := pos - spawn
		delta.y = 0.0
		if delta.length() < COVER_SPAWN_CLEAR_M:
			return true
	return false


static func _safe_cover(pos: Vector3) -> Vector3:
	var out := pos
	for spawn in PLAYER_SPAWN_POSITIONS:
		var delta := out - spawn
		delta.y = 0.0
		var dist := delta.length()
		if dist >= COVER_SPAWN_CLEAR_M:
			continue
		if dist < 0.001:
			delta = Vector3(0.0, 0.0, -1.0)
			dist = 1.0
		out += delta / dist * (COVER_SPAWN_CLEAR_M - dist)
	out.y = 1.0
	return out


static func packed_scene_for(kind: String) -> PackedScene:
	var entry: Variant = SCENE_BY_KIND.get(kind)
	if entry is PackedScene:
		return entry
	var path := str(entry) if entry != null else ""
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


static func scene_path_for(kind: String) -> String:
	var entry: Variant = SCENE_BY_KIND.get(kind)
	if entry is PackedScene:
		return (entry as PackedScene).resource_path
	return str(entry) if entry != null else ""


## Same path on every peer. Scene root names collide across waves and same-kind dumps.
static func dump_node_name(encounter_index: int, slot: int) -> String:
	return "M%d_%d" % [encounter_index, slot]


static func _spawn(kind: String, pad: int) -> Dictionary:
	return {"kind": kind, "pad": pad}
