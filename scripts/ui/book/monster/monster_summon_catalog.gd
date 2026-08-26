class_name MonsterSummonCatalog
extends RefCounted

## Dev summon-book pages — ordered pre-baked page scenes.
## Spawn metadata lives on each page's MonsterSummonEntry export.

const PAGE_SCENES: Array[PackedScene] = [
	preload("res://scenes/ui/book/monster/pages/wretch.tscn"),
	preload("res://scenes/ui/book/monster/pages/ash_wretch.tscn"),
	preload("res://scenes/ui/book/monster/pages/ember_wretch.tscn"),
	preload("res://scenes/ui/book/monster/pages/charger.tscn"),
]


static func page_scenes() -> Array[PackedScene]:
	return PAGE_SCENES


static func entry_count() -> int:
	return PAGE_SCENES.size()


static func entry_at(index: int) -> Dictionary:
	var list := entries()
	if list.is_empty():
		return {}
	var i := clampi(index, 0, list.size() - 1)
	return list[i]


static func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for scene in PAGE_SCENES:
		if scene == null:
			continue
		var page := scene.instantiate()
		if page != null and page.has_method("get_catalog_entry"):
			var entry: Dictionary = page.get_catalog_entry()
			if not entry.is_empty():
				list.append(entry)
		if page != null:
			page.free()
	return list
