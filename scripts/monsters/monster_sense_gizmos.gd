@tool
class_name MonsterSenseGizmos
extends Node3D

## Authored SenseGizmos on Monster/Summon. Draws hearing, sight, light, and LOS
## when the host has show_sense_ranges enabled.

enum LosKind { FACING, CLEAR, BLOCKED, UNSEEN }

const MonsterRangeGizmosScript := preload("res://scripts/monsters/monster_range_gizmos.gd")
const MonsterSightSenseScript := preload("res://scripts/monsters/monster_sight_sense.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")

const DISC_HEIGHT := 0.02
const CONE_SEGMENTS := 24
const DISC_SEGMENTS := 32
const LOS_RADIUS := 0.016
const EYE_MARKER_RADIUS := 0.032
const HEAR_COLOR := Color(0.2, 0.75, 1.0, 0.22)
const SIGHT_FILL := Color(0.38, 1.0, 0.45, 0.28)
const SIGHT_OUTLINE := Color(0.45, 1.0, 0.55, 0.85)
const LIGHT_COLOR := Color(1.0, 0.88, 0.28, 0.18)
const COLOR_LOS_CLEAR := Color(0.25, 1.0, 0.4, 0.92)
const COLOR_LOS_BLOCKED := Color(1.0, 0.22, 0.16, 0.92)
const COLOR_LOS_FACING := Color(0.55, 0.95, 0.7, 0.5)
const COLOR_LOS_UNSEEN := Color(0.82, 0.82, 0.88, 0.4)

var _hear_mesh: MeshInstance3D = null
var _sight_outline: MeshInstance3D = null
var _sight_fill: MeshInstance3D = null
var _light_mesh: MeshInstance3D = null
var _los_mesh: MeshInstance3D = null
var _eye_mesh: MeshInstance3D = null
var _signature: String = ""


func _enter_tree() -> void:
	set_process(_want_visible())


func _ready() -> void:
	set_process(_want_visible())
	if not _want_visible():
		hide_gizmos()


func hide_gizmos() -> void:
	if _signature != "":
		_clear()
		_signature = ""
	set_process(false)


func sync_enabled(on: bool) -> void:
	if on:
		set_process(true)
	else:
		hide_gizmos()


func _process(_delta: float) -> void:
	if not _want_visible():
		hide_gizmos()
		return
	_rebuild_static_if_needed()
	_update_sight_fill()
	_update_los()


static func heading_dir(angle_rad: float) -> Vector3:
	return Vector3(sin(angle_rad), 0.0, -cos(angle_rad))


static func cone_rim_point(sight_range: float, half_angle: float, t: float) -> Vector3:
	var ang := -half_angle + clampf(t, 0.0, 1.0) * 2.0 * half_angle
	return heading_dir(ang) * maxf(sight_range, 0.01)


static func build_polyline_mesh(points: PackedVector3Array, closed: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var n := points.size()
	if n < 2:
		return st.commit()
	var last := n if closed else n - 1
	for i in last:
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % n]
		st.add_vertex(a)
		st.add_vertex(b)
	return st.commit()


static func build_cone_outline_mesh(sight_range: float, half_angle: float) -> ArrayMesh:
	var pts := PackedVector3Array()
	pts.append(Vector3.ZERO)
	for i in range(CONE_SEGMENTS + 1):
		var t := float(i) / float(CONE_SEGMENTS)
		pts.append(cone_rim_point(sight_range, half_angle, t))
	return build_polyline_mesh(pts, true)


static func build_circle_outline_mesh(radius: float, segments: int = DISC_SEGMENTS) -> ArrayMesh:
	var pts := PackedVector3Array()
	var n := maxi(segments, 8)
	for i in n:
		var ang := float(i) * TAU / float(n)
		pts.append(heading_dir(ang) * maxf(radius, 0.01))
	return build_polyline_mesh(pts, true)


static func build_clipped_fan_mesh(
	dirs: PackedVector3Array, radii: PackedFloat32Array
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := Vector3.UP
	var n := mini(dirs.size(), radii.size())
	if n < 2:
		return st.commit()
	var origin := Vector3.ZERO
	for i in range(1, n):
		var a := dirs[i - 1] * maxf(radii[i - 1], 0.02)
		var b := dirs[i] * maxf(radii[i], 0.02)
		_add_tri(st, origin, a, b, normal)
	st.generate_normals()
	return st.commit()


static func write_clipped_fan(
	im: ImmediateMesh, dirs: PackedVector3Array, radii: PackedFloat32Array
) -> void:
	im.clear_surfaces()
	var n := mini(dirs.size(), radii.size())
	if n < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin := Vector3.ZERO
	var normal := Vector3.UP
	for i in range(1, n):
		var a := dirs[i - 1] * maxf(radii[i - 1], 0.02)
		var b := dirs[i] * maxf(radii[i], 0.02)
		im.surface_set_normal(normal)
		im.surface_add_vertex(origin)
		im.surface_set_normal(normal)
		im.surface_add_vertex(a)
		im.surface_set_normal(normal)
		im.surface_add_vertex(b)
	im.surface_end()


static func build_vision_cone_mesh(sight_range: float, half_angle: float) -> ArrayMesh:
	var dirs := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in range(CONE_SEGMENTS + 1):
		var t := float(i) / float(CONE_SEGMENTS)
		var ang := -half_angle + t * 2.0 * half_angle
		dirs.append(heading_dir(ang))
		radii.append(maxf(sight_range, 0.01))
	return build_clipped_fan_mesh(dirs, radii)


static func los_line_color(kind: int) -> Color:
	match kind:
		LosKind.CLEAR:
			return COLOR_LOS_CLEAR
		LosKind.BLOCKED:
			return COLOR_LOS_BLOCKED
		LosKind.UNSEEN:
			return COLOR_LOS_UNSEEN
		_:
			return COLOR_LOS_FACING


static func segment_transform(from: Vector3, to: Vector3) -> Transform3D:
	var delta := to - from
	var length := delta.length()
	if length < 0.0001:
		return Transform3D(Basis.IDENTITY, from)
	var y_axis := delta / length
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.0001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Transform3D(Basis(x_axis, y_axis, z_axis), (from + to) * 0.5)


static func pick_nearest_node(origin: Vector3, nodes: Array) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for node in nodes:
		if not (node is Node3D):
			continue
		var candidate := node as Node3D
		var dist_sq := origin.distance_squared_to(candidate.global_position)
		if dist_sq < best_d:
			best_d = dist_sq
			best = candidate
	return best


static func _add_tri(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3
) -> void:
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_normal(normal)
	st.add_vertex(c)


func _want_visible() -> bool:
	var host := get_parent()
	return host != null and bool(host.get("show_sense_ranges"))


func _rebuild_static_if_needed() -> void:
	var hearing := _find_sense("hear_range")
	var sight := _find_sense("sight_range")
	var light := _find_light_sense()
	var signature := _sense_signature(hearing, sight, light)
	if signature == _signature:
		return
	_signature = signature
	_rebuild_hearing(hearing)
	_rebuild_sight(sight)
	_rebuild_light(light)


func _sense_signature(hearing: Node, sight: Node, light: Node) -> String:
	var hear_r := _sense_float(hearing, "hear_range")
	var hear_on := _sense_enabled(hearing)
	var sight_r := _sense_float(sight, "sight_range")
	var eye_h := _sense_float(sight, "eye_height")
	var cone_w := _sense_float(sight, "cone_width_at_max_range")
	var cone_deg := _sense_float(sight, "cone_angle_deg")
	var use_cone := _sense_bool(sight, "use_vision_cone")
	var sight_on := _sense_enabled(sight)
	var light_r := _sense_float(light, "sense_range")
	var light_on := _sense_enabled(light)
	return "%s:%s:%s:%s:%s:%s:%s:%s:%s:%s" % [
		hear_r, hear_on, sight_r, eye_h, cone_w, cone_deg, use_cone, sight_on, light_r, light_on
	]


func _rebuild_hearing(hearing: Node) -> void:
	if hearing == null or not _sense_enabled(hearing):
		MonsterRangeGizmosScript.free_gizmo(_hear_mesh)
		_hear_mesh = null
		return
	_hear_mesh = MonsterRangeGizmosScript.ensure_disc(
		self,
		_hear_mesh,
		"HearRange",
		_sense_float(hearing, "hear_range"),
		HEAR_COLOR,
		DISC_HEIGHT,
		false
	)
	_hear_mesh.position = Vector3(0.0, 0.03, 0.0)
	## Hearing is omnidirectional and ignores walls; keep a solid disc.


func _rebuild_sight(sight: Node) -> void:
	if sight == null or not _sense_enabled(sight):
		MonsterRangeGizmosScript.free_gizmo(_sight_outline)
		MonsterRangeGizmosScript.free_gizmo(_sight_fill)
		MonsterRangeGizmosScript.free_gizmo(_eye_mesh)
		_sight_outline = null
		_sight_fill = null
		_eye_mesh = null
		return
	var sight_range := _sense_float(sight, "sight_range")
	var use_cone := _sense_bool(sight, "use_vision_cone")
	_sight_outline = _ensure_mesh(_sight_outline, "SightOutline")
	if use_cone:
		var half := MonsterSightSenseScript.effective_half_angle(
			sight_range,
			_sense_float(sight, "cone_width_at_max_range"),
			_sense_float(sight, "cone_angle_deg")
		)
		_sight_outline.mesh = build_cone_outline_mesh(sight_range, half)
	else:
		_sight_outline.mesh = build_circle_outline_mesh(sight_range)
	MonsterRangeGizmosScript.apply_unshaded(_sight_outline, SIGHT_OUTLINE)
	_sight_outline.position = Vector3(0.0, 0.045, 0.0)
	_eye_mesh = _ensure_mesh(_eye_mesh, "EyeMarker")
	var sphere := _eye_mesh.mesh as SphereMesh
	if sphere == null:
		sphere = SphereMesh.new()
		_eye_mesh.mesh = sphere
	sphere.radius = EYE_MARKER_RADIUS
	sphere.height = EYE_MARKER_RADIUS * 2.0
	MonsterRangeGizmosScript.apply_unshaded(_eye_mesh, Color(0.45, 1.0, 0.55, 0.85))
	_eye_mesh.position = Vector3(0.0, _sense_float(sight, "eye_height"), 0.0)


func _rebuild_light(light: Node) -> void:
	if light == null or not _sense_enabled(light):
		MonsterRangeGizmosScript.free_gizmo(_light_mesh)
		_light_mesh = null
		return
	_light_mesh = MonsterRangeGizmosScript.ensure_disc(
		self,
		_light_mesh,
		"LightRange",
		_sense_float(light, "sense_range"),
		LIGHT_COLOR,
		DISC_HEIGHT,
		false
	)
	_light_mesh.position = Vector3(0.0, 0.058, 0.0)


func _update_sight_fill() -> void:
	var sight := _find_sense("sight_range")
	if sight == null or not _sense_enabled(sight):
		MonsterRangeGizmosScript.free_gizmo(_sight_fill)
		_sight_fill = null
		return
	var sight_range := _sense_float(sight, "sight_range")
	var use_cone := _sense_bool(sight, "use_vision_cone")
	var half := 0.0
	var samples := DISC_SEGMENTS
	if use_cone:
		half = MonsterSightSenseScript.effective_half_angle(
			sight_range,
			_sense_float(sight, "cone_width_at_max_range"),
			_sense_float(sight, "cone_angle_deg")
		)
		samples = CONE_SEGMENTS
	var dirs := PackedVector3Array()
	var radii := PackedFloat32Array()
	dirs.resize(samples + 1)
	radii.resize(samples + 1)
	var eye_h := _sense_float(sight, "eye_height")
	var from_global := global_position + Vector3(0.0, eye_h, 0.0)
	var exclude := _sight_ray_exclude()
	var world := get_world_3d()
	for i in range(samples + 1):
		var ang := float(i) * TAU / float(samples)
		if use_cone:
			var t := float(i) / float(samples)
			ang = -half + t * 2.0 * half
		var local_dir := heading_dir(ang)
		dirs[i] = local_dir
		var world_dir := (global_transform.basis * local_dir)
		world_dir.y = 0.0
		if world_dir.length_squared() < 0.0001:
			radii[i] = sight_range
			continue
		world_dir = world_dir.normalized()
		var ray_end := from_global + world_dir * sight_range
		radii[i] = MonsterSightSenseScript.occlude_distance(
			world, from_global, ray_end, exclude
		)
	_sight_fill = _ensure_mesh(_sight_fill, "SightFill")
	var im := _sight_fill.mesh as ImmediateMesh
	if im == null:
		im = ImmediateMesh.new()
		_sight_fill.mesh = im
	MonsterRangeGizmosScript.apply_unshaded(_sight_fill, SIGHT_FILL)
	write_clipped_fan(im, dirs, radii)
	_sight_fill.position = Vector3(0.0, 0.04, 0.0)


func _sight_ray_exclude() -> Array:
	var exclude: Array = []
	var host := get_parent()
	if host is CollisionObject3D:
		exclude.append((host as CollisionObject3D).get_rid())
	var player := _nearest_player()
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	return exclude


func _update_los() -> void:
	var sight := _find_sense("sight_range")
	if sight == null or not _sense_enabled(sight):
		MonsterRangeGizmosScript.free_gizmo(_los_mesh)
		_los_mesh = null
		return
	var eye_h := _sense_float(sight, "eye_height")
	var sight_range := _sense_float(sight, "sight_range")
	var from_local := Vector3(0.0, eye_h, 0.0)
	var player := _nearest_player()
	var los_end := from_local + Vector3(0.0, 0.0, -sight_range)
	var kind: int = LosKind.FACING
	if player != null:
		var player_global := player.global_position + Vector3(0.0, eye_h, 0.0)
		los_end = self.to_local(player_global)
		kind = _classify_player_los(sight, player_global)
		if kind != LosKind.UNSEEN:
			var hit_at := _ray_hit_point(from_local, los_end)
			kind = LosKind.CLEAR
			if hit_at != Vector3.INF:
				kind = LosKind.BLOCKED
				los_end = hit_at
	_place_los(from_local, los_end, los_line_color(kind))


func _classify_player_los(sight: Node, target_global: Vector3) -> int:
	var origin := global_position
	var flat := Vector3(target_global.x - origin.x, 0.0, target_global.z - origin.z)
	var sight_range := _sense_float(sight, "sight_range")
	if flat.length() > sight_range:
		return LosKind.UNSEEN
	if not _sense_bool(sight, "use_vision_cone"):
		return LosKind.CLEAR
	var half := MonsterSightSenseScript.effective_half_angle(
		sight_range,
		_sense_float(sight, "cone_width_at_max_range"),
		_sense_float(sight, "cone_angle_deg")
	)
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001 or flat.length_squared() < 0.0001:
		return LosKind.CLEAR
	if forward.normalized().angle_to(flat.normalized()) > half:
		return LosKind.UNSEEN
	return LosKind.CLEAR


func _nearest_player() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	return pick_nearest_node(global_position, tree.get_nodes_in_group("player"))


func _ray_hit_point(from_pt: Vector3, to_pt: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return Vector3.INF
	var from := to_global(from_pt)
	var to := to_global(to_pt)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = CollisionLayersScript.CHARACTER_AND_WORLD
	var exclude: Array = []
	var host := get_parent()
	if host is CollisionObject3D:
		exclude.append((host as CollisionObject3D).get_rid())
	var player := _nearest_player()
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	query.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return self.to_local(hit.position)


func _place_los(from_pt: Vector3, to_pt: Vector3, color: Color) -> void:
	var length := from_pt.distance_to(to_pt)
	if length < 0.02:
		if _los_mesh != null:
			_los_mesh.visible = false
		return
	_los_mesh = _ensure_mesh(_los_mesh, "LosRay")
	_los_mesh.visible = true
	var cyl := _los_mesh.mesh as CylinderMesh
	if cyl == null:
		cyl = CylinderMesh.new()
		cyl.top_radius = LOS_RADIUS
		cyl.bottom_radius = LOS_RADIUS
		cyl.radial_segments = 8
		_los_mesh.mesh = cyl
	cyl.height = length
	MonsterRangeGizmosScript.apply_unshaded(_los_mesh, color)
	_los_mesh.transform = segment_transform(from_pt, to_pt)


func _ensure_mesh(existing: MeshInstance3D, node_name: String) -> MeshInstance3D:
	var mesh_inst := existing
	if mesh_inst == null or not is_instance_valid(mesh_inst):
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = node_name
		add_child(mesh_inst)
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	MonsterRangeGizmosScript.apply_debug_aabb(mesh_inst)
	return mesh_inst


func _find_light_sense() -> Node:
	var found := _find_sense("sense_range")
	if found == null:
		return null
	## Sight/Hearing also might gain a sense_range later; skip those.
	if "sight_range" in found or "hear_range" in found:
		return null
	return found


func _find_sense(property_name: String) -> Node:
	var host := get_parent()
	if host == null:
		return null
	var senses := host.get_node_or_null("Senses")
	if senses == null:
		return null
	for child in senses.get_children():
		if property_name in child:
			return child
	return null


func _sense_float(sense: Node, property_name: String) -> float:
	if sense == null or not (property_name in sense):
		return 0.0
	return float(sense.get(property_name))


func _sense_bool(sense: Node, property_name: String) -> bool:
	if sense == null or not (property_name in sense):
		return false
	return bool(sense.get(property_name))


func _sense_enabled(sense: Node) -> bool:
	if sense == null:
		return false
	if "enabled" in sense:
		return bool(sense.get("enabled"))
	return true


func _clear() -> void:
	MonsterRangeGizmosScript.free_gizmo(_hear_mesh)
	MonsterRangeGizmosScript.free_gizmo(_sight_outline)
	MonsterRangeGizmosScript.free_gizmo(_sight_fill)
	MonsterRangeGizmosScript.free_gizmo(_light_mesh)
	MonsterRangeGizmosScript.free_gizmo(_los_mesh)
	MonsterRangeGizmosScript.free_gizmo(_eye_mesh)
	_hear_mesh = null
	_sight_outline = null
	_sight_fill = null
	_light_mesh = null
	_los_mesh = null
	_eye_mesh = null
