class_name StunStarMesh
extends RefCounted

## Bake helper for assets/fx/stun_star.res. Gameplay uses the baked mesh
## on StunStars scene children; do not call this from character runtime.

const POINT_COUNT := 5
const INNER_RATIO := 0.38


static func build(outer_radius: float = 0.07) -> ArrayMesh:
	var outer := maxf(outer_radius, 0.01)
	var inner := outer * INNER_RATIO
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	var tips: PackedVector3Array = PackedVector3Array()
	for i in POINT_COUNT * 2:
		var ang := -PI * 0.5 + float(i) * PI / float(POINT_COUNT)
		var rad := outer if i % 2 == 0 else inner
		tips.append(Vector3(cos(ang) * rad, sin(ang) * rad, 0.0))
	var normal := Vector3.BACK
	for i in tips.size():
		_add_tri(st, center, tips[i], tips[(i + 1) % tips.size()], normal)
	st.generate_normals()
	return st.commit()


static func _add_tri(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3
) -> void:
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_normal(normal)
	st.add_vertex(c)
