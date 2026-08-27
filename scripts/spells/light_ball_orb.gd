class_name LightBallOrb
extends Node3D

## Soft hovering light orb. Cast sequence: outline → mist from wand → sphere.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const HoveringOrbMotionScript := preload("res://scripts/spells/hovering_orb_motion.gd")
const SpellWorldSyncScript := preload("res://scripts/spells/spell_world_sync.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")

const DEFAULT_DURATION_SEC := 30.0
const ORB_RADIUS := 0.16
const OUTLINE_RADIUS := 0.2
const CLEAR_MARGIN := 0.08
const LIGHT_RANGE := 12.0
const LIGHT_ENERGY := 3.0
const PLACE_FORWARD := 12.0
## Min aim distance at zero charge; full charge uses PLACE_FORWARD.
const PLACE_FORWARD_MIN := 1.0
## Fixed hover height above the ground under the orb.
const PLACE_HEIGHT := HoveringOrbMotionScript.HEIGHT_LIGHT_BALL
const CAST_TRAVEL_SEC := 0.28
const FORM_SEC := 0.14
## World static geometry (maze walls / floor).
const WORLD_COLLISION_MASK := 1
const ORB_COLOR := Color(1.0, 0.96, 0.82, 0.42)
const OUTLINE_COLOR := Color(1.0, 0.94, 0.7, 0.32)
const MIST_COLOR := Color(1.0, 0.95, 0.8, 0.7)


var spawn_id := ""
var _duration_sec := DEFAULT_DURATION_SEC
var _wand_origin := Vector3.ZERO
var _target := Vector3.ZERO
var _hover_base := Vector3.ZERO
var _hover_phase := 0.0
var _hovering := false
var _omni: OmniLight3D
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _outline: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _mist: Node3D
var _mist_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _lifetime_tween: Tween


static func spawn(
	parent: Node,
	world_position: Vector3,
	duration_sec: float = DEFAULT_DURATION_SEC
) -> LightBallOrb:
	return spawn_cast(parent, world_position, world_position, duration_sec)


static func spawn_cast(
	parent: Node,
	wand_origin: Vector3,
	target_position: Vector3,
	duration_sec: float = DEFAULT_DURATION_SEC,
	orb_spawn_id: String = ""
) -> LightBallOrb:
	var orb := LightBallOrb.new()
	orb._duration_sec = maxf(duration_sec, 0.5)
	orb._wand_origin = wand_origin
	orb._target = target_position
	orb.spawn_id = orb_spawn_id
	## Place before add_child so `_ready` light is not at Match origin.
	SpellEphemeralFxScript.add_child_at(parent, orb, target_position)
	var snapped_pos := snap_to_ground(orb.get_world_3d(), target_position)
	orb._target = snapped_pos
	orb.global_position = snapped_pos
	orb._hover_base = snapped_pos
	NetLivenessScript.attach(orb)
	return orb


static func resolve_placement(player: CharacterBody3D, charge_factor: float = 1.0) -> Vector3:
	## Place along wand → crosshair aim (not body-forward), then clear + ground-snap.
	## Longer LMB hold pushes the orb farther along that aim.
	if player == null or not player.is_inside_tree():
		return Vector3.ZERO
	var wand_origin := player.global_position + Vector3(0.0, PLACE_HEIGHT, 0.0)
	var forward := -player.global_transform.basis.z
	if player.has_method("get_wand_cast_origin"):
		wand_origin = player.call("get_wand_cast_origin")
	if player.has_method("get_wand_cast_direction"):
		forward = player.call("get_wand_cast_direction")
	if forward.length_squared() < 0.0001:
		forward = -player.global_transform.basis.z
	forward = forward.normalized()
	var place_forward := lerpf(PLACE_FORWARD_MIN, PLACE_FORWARD, clampf(charge_factor, 0.0, 1.0))
	var desired := wand_origin + forward * place_forward
	## Prefer the first surface under the crosshair within place range.
	var world_3d := player.get_world_3d()
	if world_3d != null and world_3d.direct_space_state != null:
		var ray := PhysicsRayQueryParameters3D.create(
			wand_origin, wand_origin + forward * place_forward
		)
		ray.collision_mask = WORLD_COLLISION_MASK
		ray.hit_from_inside = true
		var hit := world_3d.direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			desired = hit.position
	var clear := find_clear_point(world_3d, wand_origin, desired)
	return snap_to_ground(world_3d, clear)


static func snap_to_ground(world_3d: World3D, pos: Vector3) -> Vector3:
	return HoveringOrbMotionScript.snap_base(world_3d, pos, PLACE_HEIGHT)


static func find_clear_point(
	world_3d: World3D,
	from: Vector3,
	desired: Vector3
) -> Vector3:
	if world_3d == null:
		return snap_to_ground(null, desired)
	var space := world_3d.direct_space_state
	if space == null:
		return snap_to_ground(world_3d, desired)

	var clearance := ORB_RADIUS + CLEAR_MARGIN
	var candidate := desired
	var travel := desired - from
	var travel_len := travel.length()
	if travel_len > 0.001:
		var ray := PhysicsRayQueryParameters3D.create(from, desired)
		ray.collision_mask = WORLD_COLLISION_MASK
		ray.hit_from_inside = true
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			var hit_pos: Vector3 = hit.position
			var normal: Vector3 = hit.get("normal", -travel.normalized())
			if normal.length_squared() < 0.0001:
				normal = -travel.normalized()
			candidate = hit_pos + normal.normalized() * clearance
			# Prefer staying on the wand→target segment when possible.
			var along := from.direction_to(desired)
			var projected := from + along * clampf(
				along.dot(candidate - from),
				clearance,
				maxf(travel_len - clearance, clearance)
			)
			if _sphere_is_clear(space, projected, clearance):
				candidate = projected

	# Walk back toward the wand until the orb sphere is free of geometry.
	for _i in 10:
		if _sphere_is_clear(space, candidate, clearance):
			return snap_to_ground(world_3d, candidate)
		candidate = from.lerp(candidate, 0.62)

	if _sphere_is_clear(space, from + Vector3(0.0, 0.05, 0.0), clearance):
		return snap_to_ground(world_3d, from + Vector3(0.0, 0.05, 0.0))
	return snap_to_ground(world_3d, from)


static func _sphere_is_clear(
	space: PhysicsDirectSpaceState3D,
	center: Vector3,
	radius: float
) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = WORLD_COLLISION_MASK
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return space.intersect_shape(params, 1).is_empty()


func _ready() -> void:
	if spawn_id.is_empty():
		spawn_id = SpellWorldSyncScript.make_spawn_id()
	SpellWorldSyncScript.register(self, SpellWorldSyncScript.KIND_LIGHT_BALL, spawn_id)
	_build_outline()
	_build_orb_visuals(false)
	_build_mist_and_beam()
	_play_cast_sequence()


func get_spell_world_kind() -> String:
	return SpellWorldSyncScript.KIND_LIGHT_BALL


func get_spell_world_id() -> String:
	return spawn_id


func destroy_from_spell(from_network: bool = false) -> void:
	if not is_inside_tree():
		return
	if not from_network:
		SpellWorldSyncScript.broadcast_event(self, SpellWorldSyncScript.EVENT_REMOVE)
	_clear_cast_fx()
	if _lifetime_tween != null and _lifetime_tween.is_valid():
		_lifetime_tween.kill()
		_lifetime_tween = null
	queue_free()


func _process(delta: float) -> void:
	if not _hovering:
		return
	_hover_phase = HoveringOrbMotionScript.advance_bob_phase(_hover_phase, delta)
	global_position = HoveringOrbMotionScript.visual_from_base(_hover_base, _hover_phase)


func _build_outline() -> void:
	_outline = MeshInstance3D.new()
	_outline.name = "Outline"
	var sphere := SphereMesh.new()
	sphere.radius = OUTLINE_RADIUS
	sphere.height = OUTLINE_RADIUS * 2.0
	_outline.mesh = sphere
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outline_mat.albedo_color = OUTLINE_COLOR
	_outline_mat.emission_enabled = true
	_outline_mat.emission = Color(1.0, 0.94, 0.7)
	_outline_mat.emission_energy_multiplier = 1.1
	_outline.material_override = _outline_mat
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.layers = WorldVisualLayersScript.WORLD
	_outline.scale = Vector3.ONE * 0.85
	add_child(_outline)


func _build_orb_visuals(start_visible: bool) -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Orb"
	var sphere := SphereMesh.new()
	sphere.radius = ORB_RADIUS
	sphere.height = ORB_RADIUS * 2.0
	_mesh.mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = ORB_COLOR
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.94, 0.72)
	_mat.emission_energy_multiplier = 2.4
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.layers = WorldVisualLayersScript.WORLD
	_mesh.visible = start_visible
	_mesh.scale = Vector3.ONE * (1.0 if start_visible else 0.15)
	add_child(_mesh)

	_omni = OmniLight3D.new()
	_omni.name = "Omni"
	_omni.light_color = Color(1.0, 0.95, 0.8)
	_omni.light_energy = 0.0 if not start_visible else LIGHT_ENERGY
	_omni.omni_range = LIGHT_RANGE
	_omni.omni_attenuation = 1.15
	_omni.light_volumetric_fog_energy = 6.0
	_omni.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK
	_omni.shadow_caster_mask = WorldVisualLayersScript.WORLD_LIGHT_MASK
	_omni.shadow_enabled = true
	_omni.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	_omni.shadow_bias = 0.04
	_omni.shadow_normal_bias = 1.1
	add_child(_omni)


func _build_mist_and_beam() -> void:
	_mist = Node3D.new()
	_mist.name = "Mist"
	var world := get_parent()
	if world != null:
		world.add_child(_mist)
	else:
		add_child(_mist)
	_mist.global_position = _wand_origin

	var mist_core := MeshInstance3D.new()
	var mote := SphereMesh.new()
	mote.radius = 0.045
	mote.height = 0.09
	mist_core.mesh = mote
	_mist_mat = StandardMaterial3D.new()
	_mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mist_mat.albedo_color = MIST_COLOR
	_mist_mat.emission_enabled = true
	_mist_mat.emission = Color(1.0, 0.95, 0.78)
	_mist_mat.emission_energy_multiplier = 2.2
	mist_core.material_override = _mist_mat
	mist_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist_core.layers = WorldVisualLayersScript.WORLD
	_mist.add_child(mist_core)

	var puff := CPUParticles3D.new()
	puff.name = "Puff"
	puff.emitting = true
	puff.amount = 18
	puff.lifetime = 0.28
	puff.explosiveness = 0.05
	puff.local_coords = true
	puff.direction = Vector3(0.0, 0.15, 0.0)
	puff.spread = 180.0
	puff.initial_velocity_min = 0.04
	puff.initial_velocity_max = 0.28
	puff.gravity = Vector3(0.0, 0.35, 0.0)
	puff.scale_amount_min = 0.03
	puff.scale_amount_max = 0.08
	puff.color = Color(1.0, 0.96, 0.85, 0.4)
	_mist.add_child(puff)

	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.03
	cyl.height = 1.0
	_beam.mesh = cyl
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(1.0, 0.95, 0.8, 0.28)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color(1.0, 0.94, 0.75)
	_beam_mat.emission_energy_multiplier = 1.3
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.layers = WorldVisualLayersScript.WORLD
	if world != null:
		world.add_child(_beam)
	else:
		add_child(_beam)
	_update_beam(_wand_origin, _wand_origin)


func _update_beam(from_pos: Vector3, to_pos: Vector3) -> void:
	if _beam == null or not is_instance_valid(_beam):
		return
	var delta := to_pos - from_pos
	var length := delta.length()
	if length < 0.001:
		_beam.visible = false
		return
	_beam.visible = true
	_beam.global_position = from_pos.lerp(to_pos, 0.5)
	_beam.scale = Vector3(1.0, length, 1.0)
	var dir := delta.normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.RIGHT
	_beam.basis = Basis.looking_at(dir, up)
	_beam.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


func _play_cast_sequence() -> void:
	var skip_travel := _wand_origin.distance_squared_to(_target) < 0.01
	var cast := create_tween()
	cast.set_parallel(true)
	cast.tween_property(_outline, "scale", Vector3.ONE, CAST_TRAVEL_SEC * 0.4).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	cast.tween_property(_outline_mat, "emission_energy_multiplier", 1.8, CAST_TRAVEL_SEC * 0.4)

	if skip_travel:
		cast.chain().tween_callback(_form_orb)
		return

	cast.tween_method(
		_set_mist_progress,
		0.0,
		1.0,
		CAST_TRAVEL_SEC
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	cast.chain().tween_callback(_form_orb)


func _set_mist_progress(t: float) -> void:
	if _mist == null or not is_instance_valid(_mist):
		return
	var pos := _wand_origin.lerp(_target, clampf(t, 0.0, 1.0))
	_mist.global_position = pos
	_update_beam(_wand_origin, pos)
	if _mist_mat != null:
		_mist_mat.albedo_color.a = lerpf(0.75, 0.25, t)
		_mist_mat.emission_energy_multiplier = lerpf(2.4, 1.0, t)
	if _beam_mat != null:
		_beam_mat.albedo_color.a = lerpf(0.3, 0.05, t)


func _form_orb() -> void:
	_clear_cast_fx()
	_mesh.visible = true
	var form := create_tween()
	form.set_parallel(true)
	form.tween_property(_mesh, "scale", Vector3.ONE, FORM_SEC).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	form.tween_property(_omni, "light_energy", LIGHT_ENERGY, FORM_SEC).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	if _outline != null and is_instance_valid(_outline):
		form.tween_property(_outline_mat, "albedo_color:a", 0.0, FORM_SEC * 0.7)
		form.tween_property(_outline, "scale", Vector3.ONE * 1.25, FORM_SEC)
	form.chain().tween_callback(_finish_form_and_begin_lifetime)


func _finish_form_and_begin_lifetime() -> void:
	if _outline != null and is_instance_valid(_outline):
		_outline.queue_free()
		_outline = null
	_hover_base = global_position
	_hover_phase = randf() * TAU
	_hovering = true
	_begin_lifetime_fade()


func _clear_cast_fx() -> void:
	if _mist != null and is_instance_valid(_mist):
		_mist.queue_free()
		_mist = null
	if _beam != null and is_instance_valid(_beam):
		_beam.queue_free()
		_beam = null


func _begin_lifetime_fade() -> void:
	if _lifetime_tween != null and _lifetime_tween.is_valid():
		_lifetime_tween.kill()
	_lifetime_tween = create_tween()
	_lifetime_tween.set_parallel(true)
	_lifetime_tween.tween_property(_omni, "light_energy", 0.0, _duration_sec).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	_lifetime_tween.tween_property(_mat, "emission_energy_multiplier", 0.0, _duration_sec).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	_lifetime_tween.tween_property(_mat, "albedo_color:a", 0.0, _duration_sec).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	_lifetime_tween.chain().tween_callback(queue_free)


func get_hover_base() -> Vector3:
	return _hover_base


func spell_set_guided_position(world_pos: Vector3, lock_to_ground: bool = true) -> void:
	## Update cruise base; bobbing continues on top via _process.
	var snapped_pos := world_pos
	if lock_to_ground and is_inside_tree():
		snapped_pos = snap_to_ground(get_world_3d(), world_pos)
	_hover_base = snapped_pos
	if _hovering:
		global_position = HoveringOrbMotionScript.visual_from_base(_hover_base, _hover_phase)
	else:
		global_position = _hover_base


func spell_set_follow_base(world_pos: Vector3, blend: float = 1.0) -> void:
	var t := clampf(blend, 0.0, 1.0)
	_hover_base = _hover_base.lerp(world_pos, t)
	if _hovering:
		global_position = HoveringOrbMotionScript.visual_from_base(_hover_base, _hover_phase)
	else:
		global_position = global_position.lerp(world_pos, t)


func _exit_tree() -> void:
	_hovering = false
	_clear_cast_fx()
