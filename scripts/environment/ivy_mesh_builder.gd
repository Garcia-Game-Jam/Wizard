class_name IvyMeshBuilder
extends RefCounted

## Builds one stylized ivy leaf — a flat, five-lobed silhouette (a
## SurfaceTool triangle fan from the centroid) — shared as a single mesh
## resource across every leaf ShopStructure scatters; only each
## MeshInstance3D's transform and color vary per instance. Local +Y is the
## leaf's tip direction, local origin is the stem attachment point, sized
## so a leaf is ~1m tip-to-base before the caller's own per-instance scale.

const _OUTLINE: Array[Vector2] = [
	Vector2(0.0, 1.0),
	Vector2(0.55, 0.5),
	Vector2(0.35, 0.15),
	Vector2(0.78, -0.3),
	Vector2(0.28, -0.5),
	Vector2(0.0, -0.32),
	Vector2(-0.28, -0.5),
	Vector2(-0.78, -0.3),
	Vector2(-0.35, 0.15),
	Vector2(-0.55, 0.5),
]


static func build_leaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := _OUTLINE.size()
	for i in count:
		var a := _OUTLINE[i]
		var b := _OUTLINE[(i + 1) % count]
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(a.x, a.y, 0.0))
		st.add_vertex(Vector3(b.x, b.y, 0.0))
	st.generate_normals()
	return st.commit()
