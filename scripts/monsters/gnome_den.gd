@tool
class_name GnomeDen
extends Node3D

## Large obround cylindrical hole in the ground for gnome dens.
## Goes down 5 meters in depth with collision shapes for players/monsters to stand on.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

## Depth of the gnome den hole in meters
@export_range(1.0, 10.0, 0.1, "suffix:m") var hole_depth: float = 5.0
## Width of the gnome den opening (obround shape)
@export_range(1.0, 10.0, 0.1, "suffix:m") var hole_width: float = 2.5
## Length of the gnome den opening (obround shape)
@export_range(1.0, 10.0, 0.1, "suffix:m") var hole_length: float = 3.5
## Radius of the rounded ends of the obround shape
@export_range(0.1, 5.0, 0.1, "suffix:m") var corner_radius: float = 0.5

var _mesh_instance: MeshInstance3D = null
var _collision_shape: CollisionShape3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_geometry()


func _build_geometry() -> void:
	# Clear existing children
	for child in get_children():
		remove_child(child)
		child.free()

	# Create the visual mesh (obround cylinder)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "HoleMesh"

	var obround_mesh := _create_obround_cylinder_mesh()
	_mesh_instance.mesh = obround_mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.18, 0.15)  # Dark earth color
	material.roughness = 0.9
	material.metallic = 0.1
	_mesh_instance.material_override = material
	_mesh_instance.layers = WorldVisualLayersScript.WORLD
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(_mesh_instance)

	# Create collision shapes
	_create_collision_shapes()


func _create_obround_cylinder_mesh() -> Mesh:
	# For simplicity, we'll create a box mesh with rounded corners
	# In a more advanced implementation, we could create a proper obround shape
	var mesh := BoxMesh.new()
	mesh.size = Vector3(hole_width, hole_depth, hole_length)
	return mesh


func _create_collision_shapes() -> void:
	# Create main collision shape for the hole floor
	var floor_col := CollisionShape3D.new()
	floor_col.name = "FloorCollision"

	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(hole_width, 0.1, hole_length)
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0.0, -hole_depth + 0.05, 0.0)

	add_child(floor_col)

	# Create wall collision shapes
	# Front wall
	var front_col := CollisionShape3D.new()
	front_col.name = "FrontWallCollision"

	var front_shape := BoxShape3D.new()
	front_shape.size = Vector3(hole_width, hole_depth, 0.1)
	front_col.shape = front_shape
	front_col.position = Vector3(0.0, -hole_depth * 0.5, hole_length * 0.5)

	add_child(front_col)

	# Back wall
	var back_col := CollisionShape3D.new()
	back_col.name = "BackWallCollision"

	var back_shape := BoxShape3D.new()
	back_shape.size = Vector3(hole_width, hole_depth, 0.1)
	back_col.shape = back_shape
	back_col.position = Vector3(0.0, -hole_depth * 0.5, -hole_length * 0.5)

	add_child(back_col)

	# Left wall
	var left_col := CollisionShape3D.new()
	left_col.name = "LeftWallCollision"

	var left_shape := BoxShape3D.new()
	left_shape.size = Vector3(0.1, hole_depth, hole_length)
	left_col.shape = left_shape
	left_col.position = Vector3(hole_width * 0.5, -hole_depth * 0.5, 0.0)

	add_child(left_col)

	# Right wall
	var right_col := CollisionShape3D.new()
	right_col.name = "RightWallCollision"

	var right_shape := BoxShape3D.new()
	right_shape.size = Vector3(0.1, hole_depth, hole_length)
	right_col.shape = right_shape
	right_col.position = Vector3(-hole_width * 0.5, -hole_depth * 0.5, 0.0)

	add_child(right_col)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if hole_width <= 0.0:
		warnings.append("Hole width must be greater than 0")

	if hole_length <= 0.0:
		warnings.append("Hole length must be greater than 0")

	if hole_depth <= 0.0:
		warnings.append("Hole depth must be greater than 0")

	if corner_radius <= 0.0:
		warnings.append("Corner radius must be greater than 0")

	if corner_radius > hole_width * 0.5 or corner_radius > hole_length * 0.5:
		warnings.append("Corner radius is too large for the hole dimensions")

	return warnings