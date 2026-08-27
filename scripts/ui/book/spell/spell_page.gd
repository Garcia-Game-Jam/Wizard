class_name SpellBookPage
extends PanelContainer

## Pre-baked spellbook leaf. Renders a scaled spell scene into the preview box.

const PREVIEW_SCENES := {
	"fireball": preload("res://scenes/spells/fireball/fireball.tscn"),
	"flare": preload("res://scenes/spells/evaluating/flare/flare.tscn"),
	"ward": preload("res://scenes/spells/ward/ward.tscn"),
}

const PREVIEW_COLORS := {
	"dispell": Color(0.55, 0.35, 0.95),
	"follow": Color(0.35, 0.85, 0.55),
	"haste": Color(0.95, 0.85, 0.25),
	"light": Color(1.0, 0.95, 0.75),
	"light_ball": Color(1.0, 0.92, 0.55),
	"pull": Color(0.35, 0.65, 1.0),
	"stop": Color(0.95, 0.35, 0.35),
	"target": Color(0.35, 1.0, 0.45),
}

@export var spell_id: String = ""
@export var preview_scene: PackedScene
@export_range(0.05, 4.0, 0.01) var preview_scale: float = 1.0

var _fit_token := 0
var _preview_host: SubViewportContainer
var _viewport: SubViewport
var _spell_anchor: Node3D
var _camera: Camera3D


func _ready() -> void:
	## Flip ghosts are visual-only duplicates — never rebuild live 3D previews.
	if has_meta("flip_ghost"):
		return
	_preview_host = $Margin/VBox/Preview
	_viewport = $Margin/VBox/Preview/SubViewport
	_spell_anchor = $Margin/VBox/Preview/SubViewport/World/SpellAnchor
	_camera = $Margin/VBox/Preview/SubViewport/World/Camera3D
	_sync_viewport_size()
	if not _preview_host.resized.is_connected(_sync_viewport_size):
		_preview_host.resized.connect(_sync_viewport_size)
	_rebuild_preview()


func _exit_tree() -> void:
	_fit_token += 1


func _sync_viewport_size() -> void:
	## stretch=false so we own size explicitly (avoids SubViewportContainer warning).
	if _preview_host == null or _viewport == null:
		return
	_preview_host.stretch = false
	var px := Vector2i(
		maxi(1, int(round(_preview_host.size.x))),
		maxi(1, int(round(_preview_host.size.y)))
	)
	if px.x <= 1 or px.y <= 1:
		px = Vector2i(180, 180)
	if _viewport.size != px:
		_viewport.size = px


func _rebuild_preview() -> void:
	if _spell_anchor == null:
		return
	for child in _spell_anchor.get_children():
		_spell_anchor.remove_child(child)
		child.free()
	var scene := _resolve_preview_scene()
	var root: Node3D
	if scene != null:
		root = _instance_spell_preview(scene)
	else:
		root = _make_fallback_orb()
	if root == null:
		return
	_spell_anchor.add_child(root)
	## Spells often enable physics in _ready — freeze after they enter the tree.
	_freeze_preview_motion(root)
	_fit_preview(root)


func _resolve_preview_scene() -> PackedScene:
	if preview_scene != null:
		return preview_scene
	if PREVIEW_SCENES.has(spell_id):
		return PREVIEW_SCENES[spell_id] as PackedScene
	return null


func _instance_spell_preview(scene: PackedScene) -> Node3D:
	var node := scene.instantiate()
	if node == null:
		return null
	## Prefer idle editor-style FX when the spell supports it.
	if "preview_smoke" in node:
		node.set("preview_smoke", true)
	if "preview_embers" in node:
		node.set("preview_embers", true)
	if "preview_glow" in node:
		node.set("preview_glow", true)
	if "preview_loop" in node:
		node.set("preview_loop", true)
	if node is Node3D:
		return node as Node3D
	var preview_wrap := Node3D.new()
	preview_wrap.name = "PreviewWrap"
	preview_wrap.add_child(node)
	return preview_wrap


func _freeze_preview_motion(root: Node) -> void:
	## monitoring / monitorable exist on Area3D only — not StaticBody3D.
	if root is Area3D:
		var area := root as Area3D
		area.monitoring = false
		area.monitorable = false
	if root is CollisionObject3D:
		var body := root as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	if root.has_method("set_physics_process"):
		root.set_physics_process(false)
	if root.has_method("set_process"):
		root.set_process(false)
	if root.has_meta("lookdev_flight"):
		root.remove_meta("lookdev_flight")
	for child in root.get_children():
		_freeze_preview_motion(child)


func _make_fallback_orb() -> Node3D:
	var root := Node3D.new()
	root.name = "FallbackOrb"
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	mesh_instance.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	var color: Color = PREVIEW_COLORS.get(spell_id, Color(0.75, 0.65, 0.45))
	mat.albedo_color = color
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mesh_instance.material_override = mat
	root.add_child(mesh_instance)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 1.5
	root.add_child(light)
	return root


func _fit_preview(root: Node3D) -> void:
	## Let transforms settle one frame so AABB is valid, then frame the camera.
	_fit_token += 1
	var token := _fit_token
	await get_tree().process_frame
	if token != _fit_token:
		return
	if not is_inside_tree() or root == null or not is_instance_valid(root):
		return
	if not root.is_inside_tree() or _camera == null or not _camera.is_inside_tree():
		return
	var aabb := _visual_aabb(root)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest <= 0.001:
		longest = 0.5
	var fit := 0.7 / longest
	root.scale = Vector3.ONE * fit * preview_scale
	root.position = -aabb.get_center() * fit * preview_scale
	_camera.position = Vector3(0.0, 0.2, 1.05)
	_aim_camera_at_origin()


func _aim_camera_at_origin() -> void:
	## Avoid Camera3D.look_at colinear warnings when eye/target align with up.
	var eye := _camera.global_position
	var target := Vector3.ZERO
	var forward := target - eye
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.98:
		up = Vector3.RIGHT
	_camera.global_transform = Transform3D(Basis.looking_at(forward, up), eye)


func _visual_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var has_any := false
	if not root.is_inside_tree():
		return AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var vis := node as VisualInstance3D
		if vis == null or not vis.is_inside_tree():
			continue
		var local := vis.get_aabb()
		var xf := root.global_transform.affine_inverse() * vis.global_transform
		var world := _xform_aabb(xf, local)
		if not has_any:
			merged = world
			has_any = true
		else:
			merged = merged.merge(world)
	if has_any:
		return merged
	return AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))


func _xform_aabb(xf: Transform3D, aabb: AABB) -> AABB:
	var points: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size,
	]
	var out := AABB(xf * points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		out = out.expand(xf * points[i])
	return out
