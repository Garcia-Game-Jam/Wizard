class_name MonsterSummonEntry
extends Resource

## One pre-baked summoning-book page. Pages live as .tres files under
## resources/monsters/ so content is editable in the editor inspector.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var monster_scene: PackedScene
@export var tint: Color = Color.WHITE
## Bright chase-eye glow. Hidden while idle/patrol.
@export var eye_glow_color: Color = Color(0.2, 0.55, 1.0, 1.0)


func to_catalog_entry() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"description": description,
		"scene_path": monster_scene.resource_path if monster_scene != null else "",
		"tint": tint,
		"eye_glow_color": eye_glow_color,
	}
