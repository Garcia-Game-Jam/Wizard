class_name ShopFanMeshBuilder
extends RefCounted

## Builds ShopStructure's triangle-fan surfaces: the glass roof (apex above
## the ring) and the stone floor (apex level with the ring, one flat-shaded
## wedge per ring segment). Takes the ring's actual points rather than
## recomputing its own angle/radius math, so a surface's edges always land
## exactly on the same vertices ShopStructure used to place its piers/ribs —
## nothing to keep in sync by hand.
##
## `colors`, if given (one entry per ring segment), tints each wedge's three
## vertices uniformly — pair with a material that has
## vertex_color_use_as_albedo on to get one solid shade per wedge, e.g. the
## floor's per-tile stone variation.


static func build_pyramid(
	base_points: PackedVector3Array, apex: Vector3, colors: PackedColorArray = PackedColorArray()
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := base_points.size()
	var has_colors := colors.size() == count
	for i in count:
		var a := base_points[i]
		var b := base_points[(i + 1) % count]
		if has_colors:
			st.set_color(colors[i])
		st.add_vertex(apex)
		st.add_vertex(a)
		st.add_vertex(b)
	st.generate_normals()
	return st.commit()
