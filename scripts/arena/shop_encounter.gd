class_name ShopEncounter
extends Encounter

## Non-combat encounter: a shop stage between fights. Still a plain marker
## with no fields of its own — placeholder for inventory/pricing data once
## a real economy exists — but arena_scene.gd now recognizes
## `level_enc is ShopEncounter` and, instead of a monster dump, rises
## scenes/arenas/shop.tscn out of the ground at the arena's center (see
## shop_spawn_controller.gd) with the arena's cube cover obstacles buried
## out of the way first. What ends a shop stage and advances to the next
## encounter isn't wired up yet — arena_scene.gd deliberately never
## auto-resolves one, so today the run just parks there once the shop has
## risen and opened its doors.
