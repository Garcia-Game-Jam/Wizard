class_name WardMeshBuilder
extends RefCounted

## Pure ward dome geometry — rebuilt in-editor by WardShield.

## Spherical-cap half-angle so surface area ≈ 1/3 of a full sphere: cosθ = 1 - 2f.
const DEFAULT_SURFACE_FRACTION := 1.0 / 3.0
const DEFAULT_RADIUS := 1.35
const RING_COUNT := 10
const SEG_COUNT := 28


static func cap_cos_theta(surface_fraction: float = DEFAULT_SURFACE_FRACTION) -> float:
	return 1.0 - 2.0 * clampf(surface_fraction, 0.05, 0.95)


static func build_mesh(
	radius: float = DEFAULT_RADIUS,
	surface_fraction: float = DEFAULT_SURFACE_FRACTION,
	ring_count: int = RING_COUNT,
	seg_count: int = SEG_COUNT,
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var theta_max := acos(cap_cos_theta(surface_fraction))
	var rings := maxi(ring_count, 2)
	var segs := maxi(seg_count, 3)
	var verts: Array[Vector3] = []
	for ring in range(rings + 1):
		var t := float(ring) / float(rings)
		var theta := theta_max * t
		var sin_t := sin(theta)
		var cos_t := cos(theta)
		for seg in range(segs + 1):
			var phi := TAU * float(seg) / float(segs)
			## Local -Z is outward (toward aim after look_at).
			verts.append(
				Vector3(
					sin_t * cos(phi) * radius,
					sin_t * sin(phi) * radius,
					-cos_t * radius
				)
			)

	for ring in range(rings):
		for seg in range(segs):
			var i0 := ring * (segs + 1) + seg
			var i1 := i0 + 1
			var i2 := i0 + (segs + 1)
			var i3 := i2 + 1
			st.add_vertex(verts[i0])
			st.add_vertex(verts[i2])
			st.add_vertex(verts[i1])
			st.add_vertex(verts[i1])
			st.add_vertex(verts[i2])
			st.add_vertex(verts[i3])

	st.generate_normals()
	return st.commit()


static func build_collision_shape(
	radius: float = DEFAULT_RADIUS,
	surface_fraction: float = DEFAULT_SURFACE_FRACTION,
	ring_count: int = RING_COUNT,
	seg_count: int = SEG_COUNT,
) -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	shape.points = collision_points(radius, surface_fraction, ring_count, seg_count)
	return shape


static func collision_points(
	radius: float = DEFAULT_RADIUS,
	surface_fraction: float = DEFAULT_SURFACE_FRACTION,
	ring_count: int = RING_COUNT,
	seg_count: int = SEG_COUNT,
) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.append(Vector3.ZERO)
	var theta_max := acos(cap_cos_theta(surface_fraction))
	var rings := maxi(ring_count, 2)
	var segs := maxi(seg_count, 3)
	for ring in range(rings + 1):
		var t := float(ring) / float(rings)
		var theta := theta_max * t
		var sin_t := sin(theta)
		var cos_t := cos(theta)
		for seg in range(segs):
			var phi := TAU * float(seg) / float(segs)
			points.append(
				Vector3(
					sin_t * cos(phi) * radius,
					sin_t * sin(phi) * radius,
					-cos_t * radius
				)
			)
	return points


static func surface_fraction_of_sphere(surface_fraction: float = DEFAULT_SURFACE_FRACTION) -> float:
	## Cap surface / full sphere = (1 - cosθ) / 2.
	return (1.0 - cap_cos_theta(surface_fraction)) / 2.0
