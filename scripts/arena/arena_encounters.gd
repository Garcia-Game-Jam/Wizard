class_name ArenaEncounters
extends RefCounted

## Week-1 dumps: three different packs, then three that want Ward.

const KIND_CHARGER := "charger"
const KIND_EMBER := "ember"
const KIND_ASH := "ash"

const UNLOCK_QUEUE: Array[String] = ["ward"]

const STARTER_SPELL_IDS: Array[String] = ["fireball", "flare", "pull"]

const SCENE_BY_KIND := {
	KIND_CHARGER: "res://scenes/monsters/charger.tscn",
	KIND_EMBER: "res://scenes/monsters/ember_wretch.tscn",
	KIND_ASH: "res://scenes/monsters/ash_wretch.tscn",
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
			dump.append(_spawn(KIND_ASH, 1))
			dump.append(_spawn(KIND_ASH, 3))
		4:
			dump.append(_spawn(KIND_CHARGER, 0))
			dump.append(_spawn(KIND_ASH, 2))
		_:
			dump.append(_spawn(KIND_EMBER, 0))
			dump.append(_spawn(KIND_EMBER, 1))
			dump.append(_spawn(KIND_ASH, 3))
	return dump


static func cover_positions(encounter_index: int) -> Array[Vector3]:
	var index := encounter_index % 6
	match index:
		0:
			return [Vector3(-6.0, 1.0, -4.0), Vector3(6.0, 1.0, 3.0), Vector3(0.0, 1.0, 8.0)]
		1:
			return [Vector3(-8.0, 1.0, 2.0), Vector3(3.0, 1.0, -7.0), Vector3(7.0, 1.0, 7.0)]
		2:
			return [Vector3(-4.0, 1.0, 0.0), Vector3(4.0, 1.0, 0.0), Vector3(0.0, 1.0, -8.0)]
		3:
			return [Vector3(-7.0, 1.0, -7.0), Vector3(7.0, 1.0, -7.0), Vector3(0.0, 1.0, 6.0)]
		4:
			return [Vector3(-9.0, 1.0, 0.0), Vector3(9.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0)]
		_:
			return [Vector3(-5.0, 1.0, 5.0), Vector3(5.0, 1.0, 5.0), Vector3(0.0, 1.0, -6.0)]


static func scene_path_for(kind: String) -> String:
	return str(SCENE_BY_KIND.get(kind, ""))


static func _spawn(kind: String, pad: int) -> Dictionary:
	return {"kind": kind, "pad": pad}
