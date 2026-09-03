@tool
class_name MonsterSpawnMarker
extends Node3D

## A monster spawn's preview marker IS where you switch which monster spawns
## there — select it in the viewport and pick `kind` right here in the
## Inspector, same enum as MonsterSpawnEntry.kind. Writes straight back into
## the matching Level entry immediately (via _on_kind_changed, wired up by
## encounter_design_workshop.gd's _make_monster_marker()) — unlike position,
## which needs the separate "Sync Positions From Markers" step since
## dragging fires far too often to write back every frame, a kind pick is
## one deliberate action and should just take effect.

const KIND_COLORS := {
	"charger": Color(0.85, 0.2, 0.2, 0.9),
	"ember": Color(0.95, 0.55, 0.15, 0.9),
	"ash": Color(0.35, 0.55, 0.85, 0.9),
}
const DEFAULT_COLOR := Color(0.8, 0.2, 0.8, 0.9)

## The setter strips a leaked "Label:value" enum hint down to just the value
## — see monster_spawn_entry.gd's identical note on its own kind setter,
## which this marker's kind is meant to always mirror.
@export_enum("Charger:charger", "Ember Wretch:ember", "Ash Wretch:ash") var kind: String = "charger":
	set(value):
		var stripped := value.substr(value.rfind(":") + 1) if value.contains(":") else value
		if kind == stripped and _mesh_instance != null:
			return
		kind = stripped
		_apply_color()
		if is_inside_tree() and _on_kind_changed.is_valid():
			_on_kind_changed.call(kind)

## Same immediate-write-back deal as kind above, mirroring
## MonsterSpawnEntry.spawn_animation — only one option exists today.
@export_enum("Classic Beam:classic_beam") var spawn_animation: String = "classic_beam":
	set(value):
		var stripped := value.substr(value.rfind(":") + 1) if value.contains(":") else value
		if spawn_animation == stripped and _mesh_instance != null:
			return
		spawn_animation = stripped
		if is_inside_tree() and _on_spawn_animation_changed.is_valid():
			_on_spawn_animation_changed.call(spawn_animation)

## Both set by encounter_design_workshop.gd right after instancing — not
## @export, this marker is never meant to be hand-authored/saved as a scene.
var _on_kind_changed: Callable = Callable()
var _on_spawn_animation_changed: Callable = Callable()

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	_mesh_instance.mesh = mesh
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)
	_apply_color()


func _apply_color() -> void:
	if _material == null:
		return
	_material.albedo_color = KIND_COLORS.get(kind, DEFAULT_COLOR)
