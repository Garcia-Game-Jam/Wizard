class_name TargetHighlight
extends RefCounted

## Temporary dashed green box outlines on light balls and the delivery relic.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const HIGHLIGHT_NAME := "SpellTargetHighlight"
const DEFAULT_DURATION_SEC := 10.0
const EDGE_THICKNESS := 0.045
const DASH_LENGTH := 0.14
const GAP_LENGTH := 0.09
const BOX_PADDING := 0.12
const HIGHLIGHT_COLOR := Color(0.25, 0.95, 0.4, 0.95)
const HIGHLIGHT_EMISSION := Color(0.2, 0.9, 0.35)


static func apply_single(
	tree: SceneTree,
	anchor: Node3D,
	duration_sec: float = DEFAULT_DURATION_SEC
) -> void:
	## Replace any active Target highlight with a single selected object.
	if tree == null or anchor == null or not is_instance_valid(anchor):
		return
	clear_all(tree)
	_attach_or_refresh(anchor, maxf(duration_sec, 0.5))


static func has_active_highlights(tree: SceneTree) -> bool:
	return not get_highlighted_anchors(tree).is_empty()


static func get_highlighted_anchors(tree: SceneTree) -> Array[Node3D]:
	var anchors: Array[Node3D] = []
	if tree == null:
		return anchors
	for fx in tree.get_nodes_in_group("spell_target_highlight"):
		if fx == null or not is_instance_valid(fx):
			continue
		var parent := (fx as Node).get_parent()
		if parent is Node3D:
			anchors.append(parent as Node3D)
	return anchors


static func clear_all(tree: SceneTree) -> void:
	if tree == null:
		return
	for fx in tree.get_nodes_in_group("spell_target_highlight"):
		if is_instance_valid(fx):
			fx.queue_free()


static func collect_anchors(tree: SceneTree) -> Array[Node3D]:
	var anchors: Array[Node3D] = []
	var seen: Dictionary = {}
	_append_unique(anchors, seen, tree.get_nodes_in_group("light_ball"))
	_append_unique(anchors, seen, tree.get_nodes_in_group("relic_clone"))
	for node in tree.get_nodes_in_group("delivery_objective"):
		if node != null and node.has_method("get_spell_target_nodes"):
			var targets: Variant = node.call("get_spell_target_nodes")
			if targets is Array:
				_append_unique(anchors, seen, targets)
	return anchors


static func _append_unique(out: Array[Node3D], seen: Dictionary, nodes: Array) -> void:
	for node in nodes:
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		var anchor := node as Node3D
		var key := anchor.get_instance_id()
		if seen.has(key):
			continue
		seen[key] = true
		out.append(anchor)


static func _attach_or_refresh(anchor: Node3D, duration_sec: float) -> void:
	var existing := anchor.get_node_or_null(HIGHLIGHT_NAME) as Node3D
	if existing != null:
		if existing.has_method("refresh"):
			existing.call("refresh", duration_sec)
		return
	var fx := _TargetHighlightFx.new()
	fx.name = HIGHLIGHT_NAME
	anchor.add_child(fx)
	fx.start(duration_sec)


class _TargetHighlightFx extends Node3D:
	var _box: MeshInstance3D
	var _mat: StandardMaterial3D
	var _expire_at_msec: int = 0


	func start(duration_sec: float) -> void:
		add_to_group("spell_target_highlight")
		_build_dashed_box()
		refresh(duration_sec)
		set_process(true)


	func refresh(duration_sec: float) -> void:
		_expire_at_msec = Time.get_ticks_msec() + int(maxf(duration_sec, 0.5) * 1000.0)


	func _process(_delta: float) -> void:
		if Time.get_ticks_msec() >= _expire_at_msec:
			queue_free()


	func _build_dashed_box() -> void:
		var size := _estimate_box_size()
		_box = MeshInstance3D.new()
		_box.name = "DashedBox"
		_box.mesh = _make_dashed_box_mesh(size)
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.albedo_color = HIGHLIGHT_COLOR
		_mat.emission_enabled = true
		_mat.emission = HIGHLIGHT_EMISSION
		_mat.emission_energy_multiplier = 2.2
		_box.material_override = _mat
		_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box.layers = WorldVisualLayersScript.WORLD
		add_child(_box)


	func _estimate_box_size() -> Vector3:
		var parent := get_parent() as Node3D
		if parent == null:
			return Vector3.ONE * (0.5 + BOX_PADDING * 2.0)
		var aabb := AABB()
		var has_aabb := false
		for child in parent.get_children():
			if child == self:
				continue
			if child is MeshInstance3D:
				var mesh_inst := child as MeshInstance3D
				if mesh_inst.mesh == null:
					continue
				var local_aabb := mesh_inst.mesh.get_aabb()
				local_aabb.position += mesh_inst.position
				local_aabb.size *= mesh_inst.scale
				if not has_aabb:
					aabb = local_aabb
					has_aabb = true
				else:
					aabb = aabb.merge(local_aabb)
		if not has_aabb:
			return Vector3.ONE * (0.55 + BOX_PADDING * 2.0)
		return Vector3(
			maxf(aabb.size.x, 0.2) + BOX_PADDING * 2.0,
			maxf(aabb.size.y, 0.2) + BOX_PADDING * 2.0,
			maxf(aabb.size.z, 0.2) + BOX_PADDING * 2.0
		)


	func _make_dashed_box_mesh(size: Vector3) -> ArrayMesh:
		var half := size * 0.5
		var corners: Array[Vector3] = [
			Vector3(-half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, half.z),
			Vector3(-half.x, -half.y, half.z),
			Vector3(-half.x, half.y, -half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(-half.x, half.y, half.z),
		]
		var edges: Array[Vector2i] = [
			Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
			Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
			Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
		]

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for edge in edges:
			_add_dashed_edge(st, corners[edge.x], corners[edge.y])
		return st.commit()


	func _add_dashed_edge(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
		var delta := b - a
		var length := delta.length()
		if length < 0.001:
			return
		var dir := delta / length
		# Keep dash axis stable for vertical/horizontal edges.
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := dir.cross(side).normalized()
		var half_t := EDGE_THICKNESS * 0.5
		var cursor := 0.0
		var drawing := true
		while cursor < length:
			var seg := DASH_LENGTH if drawing else GAP_LENGTH
			var next_cursor := minf(cursor + seg, length)
			if drawing and next_cursor - cursor > 0.01:
				_add_box_segment(st, a + dir * cursor, a + dir * next_cursor, side, up, half_t)
			cursor = next_cursor
			drawing = not drawing


	func _add_box_segment(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		side: Vector3,
		up: Vector3,
		half_t: float
	) -> void:
		var s0 := side * half_t
		var u0 := up * half_t
		var p := [
			a - s0 - u0,
			a + s0 - u0,
			a + s0 + u0,
			a - s0 + u0,
			b - s0 - u0,
			b + s0 - u0,
			b + s0 + u0,
			b - s0 + u0,
		]
		# Side faces only (no end caps) so dashes read as open stroke segments.
		_add_quad(st, p[0], p[1], p[5], p[4])
		_add_quad(st, p[1], p[2], p[6], p[5])
		_add_quad(st, p[2], p[3], p[7], p[6])
		_add_quad(st, p[3], p[0], p[4], p[7])


	func _add_quad(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3
	) -> void:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)
