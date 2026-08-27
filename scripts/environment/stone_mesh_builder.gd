class_name StoneMeshBuilder
extends RefCounted

## Bake helper for assets/props/stone_mesh.res and assets/props/stone_collision.res —
## a faceted low-poly rock built by jittering an icosahedron's vertices per face and
## flat-shading the result. The collision hull reuses the same jittered vertices
## (same seed) so it hugs the visible mesh.
## Regenerate via: godot --headless --path . --script res://tools/generate_stone_mesh.gd

const MESH_PATH := "res://assets/props/stone_mesh.res"
const SHAPE_PATH := "res://assets/props/stone_collision.res"

const _PHI := 1.6180339887498949
## Per-vertex radius jitter range, applied before scaling to the requested size.
const _JITTER_MIN := 0.82
const _JITTER_MAX := 1.18
## Squash so the rock reads as a boulder rather than a jittered sphere.
const _Y_SQUASH := 0.8
const _BASE_GRAY := 0.55
const _GRAY_JITTER := 0.08

const _FACES: Array[Vector3i] = [
	Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10),
	Vector3i(0, 10, 11), Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2),
	Vector3i(10, 7, 6), Vector3i(7, 1, 8), Vector3i(3, 9, 4), Vector3i(3, 4, 2),
	Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9), Vector3i(4, 9, 5),
	Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
]


## Same 12 points the mesh is triangulated from — already convex, so they also
## work directly as a ConvexPolygonShape3D hull.
static func _jittered_vertices(mesh_seed: int, radius: float) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = mesh_seed
	var base_verts: Array[Vector3] = [
		Vector3(-1, _PHI, 0), Vector3(1, _PHI, 0), Vector3(-1, -_PHI, 0), Vector3(1, -_PHI, 0),
		Vector3(0, -1, _PHI), Vector3(0, 1, _PHI), Vector3(0, -1, -_PHI), Vector3(0, 1, -_PHI),
		Vector3(_PHI, 0, -1), Vector3(_PHI, 0, 1), Vector3(-_PHI, 0, -1), Vector3(-_PHI, 0, 1),
	]
	var verts: Array[Vector3] = []
	for v in base_verts:
		var jitter := rng.randf_range(_JITTER_MIN, _JITTER_MAX)
		var p := v.normalized() * jitter * radius
		p.y *= _Y_SQUASH
		verts.append(p)
	return verts


static func build(mesh_seed: int = 1, radius: float = 0.5) -> ArrayMesh:
	## Independent RNG for face color: _jittered_vertices seeds its own stream,
	## so this one starting fresh at the same seed does not skew vertex jitter.
	var rng := RandomNumberGenerator.new()
	rng.seed = mesh_seed
	var verts := _jittered_vertices(mesh_seed, radius)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in _FACES:
		var a: Vector3 = verts[face.x]
		var b: Vector3 = verts[face.y]
		var c: Vector3 = verts[face.z]
		var normal := (b - a).cross(c - a).normalized()
		var gray := clampf(_BASE_GRAY + rng.randf_range(-_GRAY_JITTER, _GRAY_JITTER), 0.0, 1.0)
		var color := Color(gray, gray, gray)
		_add_flat_vertex(st, a, normal, color)
		_add_flat_vertex(st, b, normal, color)
		_add_flat_vertex(st, c, normal, color)
	return st.commit()


static func build_collision_shape(mesh_seed: int = 1, radius: float = 0.5) -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	var verts := _jittered_vertices(mesh_seed, radius)
	shape.points = PackedVector3Array(verts)
	return shape


static func save_mesh(path: String = MESH_PATH, mesh_seed: int = 1, radius: float = 0.5) -> Error:
	return ResourceSaver.save(build(mesh_seed, radius), path)


static func save_collision_shape(
	path: String = SHAPE_PATH, mesh_seed: int = 1, radius: float = 0.5
) -> Error:
	return ResourceSaver.save(build_collision_shape(mesh_seed, radius), path)


static func _add_flat_vertex(st: SurfaceTool, pos: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(pos)
