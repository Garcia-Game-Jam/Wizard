@tool
class_name ChargerKnockupGizmo
extends Node3D

## Authored on MonsterWorkspace. Range ring, hop arc, and landing pad are
## scene children. This script only moves them and rewrites arc vertices.

const LaunchScript := preload("res://scripts/monsters/charger_launch.gd")

const ARC_SEGS := 16
const YAW_STEP := 0.35

var _ring: MeshInstance3D = null
var _arc: MeshInstance3D = null
var _landing: MeshInstance3D = null
var _label: Label3D = null
var _arc_im: ImmediateMesh = null
var _signature: String = ""


func _enter_tree() -> void:
	set_process(true)
	_bind_authored()


func _bind_authored() -> void:
	if _ring != null:
		return
	_ring = get_node_or_null("RangeRing") as MeshInstance3D
	_arc = get_node_or_null("Arc") as MeshInstance3D
	_landing = get_node_or_null("Landing") as MeshInstance3D
	_label = get_node_or_null("KnockupLabel") as Label3D
	if _arc != null:
		_arc_im = _arc.mesh as ImmediateMesh


func _process(_delta: float) -> void:
	if not _want_visible():
		_set_shown(false)
		return
	_bind_authored()
	_set_shown(true)
	_sync()


func _want_visible() -> bool:
	var host := get_parent()
	if host == null:
		return false
	if "show_knockup_preview" in host and not bool(host.get("show_knockup_preview")):
		return false
	return _charger() != null


func _sync() -> void:
	var charger := _charger()
	if charger == null or _ring == null:
		return
	var maze := _maze()
	var player := _player()
	var from := charger.global_position
	if player != null:
		from = player.global_position
	var cells := LaunchScript.DEFAULT_KNOCKUP_CELLS
	if "knockup_cells" in charger:
		cells = int(charger.get("knockup_cells"))
	var cell_size := LaunchScript.DEFAULT_CELL_SIZE_M
	if maze != null and "cell_size" in maze:
		cell_size = maxf(float(maze.get("cell_size")), 0.1)
	var radius := float(cells) * cell_size
	_ring.global_position = Vector3(from.x, 0.06, from.z)
	_ring.scale = Vector3(radius, 1.0, radius)
	var wall_h := LaunchScript.DEFAULT_WALL_HEIGHT_M
	if maze != null and "wall_height" in maze:
		wall_h = maxf(float(maze.get("wall_height")), 0.5)
	var sig := "%s|%s|%s|%s|%s" % [
		_quant_xz(from, cell_size),
		snapped(charger.rotation.y, YAW_STEP),
		cells,
		cell_size,
		wall_h,
	]
	if sig == _signature:
		return
	_signature = sig
	var away := -charger.global_transform.basis.z
	away.y = 0.0
	var over_wall := LaunchScript.DEFAULT_OVER_WALL_M
	if "knockup_over_wall_m" in charger:
		over_wall = float(charger.get("knockup_over_wall_m"))
	var vel: Vector3 = LaunchScript.knockup_velocity(
		away, 18.0, wall_h, over_wall, LaunchScript.horiz_speed(cells, cell_size), null
	)
	var pts: PackedVector3Array = LaunchScript.arc_points(from, vel, 18.0, ARC_SEGS)
	_draw_arc(pts)
	var landing := from
	if pts.size() > 0:
		landing = pts[pts.size() - 1]
		landing.y = from.y
	_landing.global_position = Vector3(landing.x, 0.05, landing.z)
	_label.global_position = Vector3(landing.x, 1.4, landing.z)
	var travel := Vector2(from.x, from.z).distance_to(Vector2(landing.x, landing.z))
	_label.text = "%s cells  %.0fm" % [cells, travel]


func _quant_xz(pos: Vector3, cell_size: float) -> Vector2:
	var step := maxf(cell_size, 0.5)
	return Vector2(snapped(pos.x, step), snapped(pos.z, step))


func _set_shown(on: bool) -> void:
	if _ring != null:
		_ring.visible = on
	if _arc != null:
		_arc.visible = on
	if _landing != null:
		_landing.visible = on
	if _label != null:
		_label.visible = on


func _draw_arc(pts: PackedVector3Array) -> void:
	if _arc_im == null:
		if _arc != null:
			_arc_im = _arc.mesh as ImmediateMesh
		if _arc_im == null:
			return
	_arc_im.clear_surfaces()
	if pts.size() < 2:
		return
	_arc_im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in pts:
		_arc_im.surface_add_vertex(p)
	_arc_im.surface_end()


func _charger() -> Node3D:
	var host := get_parent()
	if host == null:
		return null
	var root := host.get_node_or_null("SpawnRoot")
	if root == null:
		return null
	var i := root.get_child_count() - 1
	while i >= 0:
		var child: Node = root.get_child(i)
		if child is Node3D and "knockup_cells" in child:
			return child as Node3D
		i -= 1
	return null


func _player() -> Node3D:
	var host := get_parent()
	if host == null:
		return null
	var root := host.get_node_or_null("PlayerRoot")
	if root == null or root.get_child_count() < 1:
		return null
	return root.get_child(root.get_child_count() - 1) as Node3D


func _maze() -> Node:
	return null
