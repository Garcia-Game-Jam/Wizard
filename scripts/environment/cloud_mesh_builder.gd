class_name CloudMeshBuilder
extends RefCounted

## Builds cohesive low-poly cloud meshes (overlapping boxes → voxel solid).
## Used only when baking the fixed asset pool.

const PUFFS_MIN := 5
const PUFFS_MAX := 9
## Reference radius used when baking; CloudSystem scales instances from this.
const REFERENCE_RADIUS := 22.0
## Voxel cell size relative to radius (smaller = smoother silhouette, heavier mesh).
const VOXEL_CELL_FACTOR := 0.22


static func build(puff_seed: int, radius: float = REFERENCE_RADIUS) -> ArrayMesh:
	seed(puff_seed)
	var puff_count := PUFFS_MIN + (randi() % (PUFFS_MAX - PUFFS_MIN + 1))
	var boxes: Array[Dictionary] = []
	for _i in puff_count:
		# Tight cluster so boxes heavily overlap into one silhouette.
		var offset := Vector3(
			(randf() - 0.5) * radius * 0.95,
			(randf() - 0.5) * radius * 0.22,
			(randf() - 0.5) * radius * 0.95
		)
		var puff_size := Vector3(
			radius * (0.7 + randf() * 0.55),
			radius * (0.32 + randf() * 0.28),
			radius * (0.7 + randf() * 0.55)
		)
		boxes.append({"center": offset, "size": puff_size})

	return _voxel_union_mesh(boxes, radius)


## Combat-scale clouds (sub-meter radius). Uses a smaller voxel floor so the mesh
## is not a single chunky cube at frost-breath sizes.
static func build_combat(puff_seed: int, radius: float) -> ArrayMesh:
	seed(puff_seed)
	var puff_count := PUFFS_MIN + (randi() % (PUFFS_MAX - PUFFS_MIN + 1))
	var boxes: Array[Dictionary] = []
	for _i in puff_count:
		var offset := Vector3(
			(randf() - 0.5) * radius * 0.95,
			(randf() - 0.5) * radius * 0.22,
			(randf() - 0.5) * radius * 0.95
		)
		var puff_size := Vector3(
			radius * (0.7 + randf() * 0.55),
			radius * (0.32 + randf() * 0.28),
			radius * (0.7 + randf() * 0.55)
		)
		boxes.append({"center": offset, "size": puff_size})
	return _voxel_union_mesh(boxes, radius, 0.06)


static func _voxel_union_mesh(
	boxes: Array[Dictionary], radius: float, min_cell: float = 1.25
) -> ArrayMesh:
	var cell := maxf(radius * VOXEL_CELL_FACTOR, min_cell)
	var half_extent := radius * 1.35
	var dim := int(ceil(half_extent * 2.0 / cell)) + 2
	var origin := Vector3(-half_extent, -half_extent * 0.45, -half_extent)
	var occupied: Dictionary = {}

	for box in boxes:
		var center: Vector3 = box.center
		var size: Vector3 = box.size
		var min_c := center - size * 0.5
		var max_c := center + size * 0.5
		var i0 := clampi(int(floor((min_c.x - origin.x) / cell)), 0, dim - 1)
		var j0 := clampi(int(floor((min_c.y - origin.y) / cell)), 0, dim - 1)
		var k0 := clampi(int(floor((min_c.z - origin.z) / cell)), 0, dim - 1)
		var i1 := clampi(int(floor((max_c.x - origin.x) / cell)), 0, dim - 1)
		var j1 := clampi(int(floor((max_c.y - origin.y) / cell)), 0, dim - 1)
		var k1 := clampi(int(floor((max_c.z - origin.z) / cell)), 0, dim - 1)
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				for k in range(k0, k1 + 1):
					occupied[_cell_key(i, j, k)] = true

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs := [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	for key in occupied.keys():
		var c := _key_to_cell(int(key))
		for dir in dirs:
			var n: Vector3i = c + dir
			if occupied.has(_cell_key(n.x, n.y, n.z)):
				continue
			_emit_voxel_face(st, origin, cell, c, dir)

	st.generate_normals()
	return st.commit()


static func _cell_key(i: int, j: int, k: int) -> int:
	# Pack into one int for Dictionary keys (dims stay well under 256).
	return (i & 0x3FF) | ((j & 0x3FF) << 10) | ((k & 0x3FF) << 20)


static func _key_to_cell(key: int) -> Vector3i:
	return Vector3i(key & 0x3FF, (key >> 10) & 0x3FF, (key >> 20) & 0x3FF)


static func _emit_voxel_face(
	st: SurfaceTool,
	origin: Vector3,
	cell: float,
	c: Vector3i,
	dir: Vector3i
) -> void:
	var p := origin + Vector3(c.x, c.y, c.z) * cell
	var s := cell
	var v: Array[Vector3] = []
	if dir.x == 1:
		v = [
			p + Vector3(s, 0, 0), p + Vector3(s, s, 0),
			p + Vector3(s, s, s), p + Vector3(s, 0, s),
		]
	elif dir.x == -1:
		v = [
			p + Vector3(0, 0, s), p + Vector3(0, s, s),
			p + Vector3(0, s, 0), p + Vector3(0, 0, 0),
		]
	elif dir.y == 1:
		v = [
			p + Vector3(0, s, 0), p + Vector3(0, s, s),
			p + Vector3(s, s, s), p + Vector3(s, s, 0),
		]
	elif dir.y == -1:
		v = [
			p + Vector3(0, 0, s), p + Vector3(0, 0, 0),
			p + Vector3(s, 0, 0), p + Vector3(s, 0, s),
		]
	elif dir.z == 1:
		v = [
			p + Vector3(0, 0, s), p + Vector3(s, 0, s),
			p + Vector3(s, s, s), p + Vector3(0, s, s),
		]
	else:
		v = [
			p + Vector3(s, 0, 0), p + Vector3(0, 0, 0),
			p + Vector3(0, s, 0), p + Vector3(s, s, 0),
		]
	st.add_vertex(v[0]); st.add_vertex(v[1]); st.add_vertex(v[2])
	st.add_vertex(v[0]); st.add_vertex(v[2]); st.add_vertex(v[3])
